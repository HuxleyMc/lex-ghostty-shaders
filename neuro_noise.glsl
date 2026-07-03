// Neuro Noise — a Ghostty custom shader ported from Paper Design's "Neuro Noise".
//
// Renders a glowing, web-like structure of fluid lines and soft intersections
// as the terminal background, with glyphs from iChannel0 composited on top.
// Great for an atmospheric, organic-yet-futuristic look. Pure pattern: no
// cursor coupling, always in motion.
//
// SOURCE
//   Upstream fragment shader: paper-design/shaders (Apache-2.0)
//     https://github.com/paper-design/shaders
//     file: packages/shaders/src/shaders/neuro-noise.ts
//           (neuroNoiseFragmentShader)
//     page: https://shaders.paper.design/neuro-noise
//   Original algorithm by zozuar:
//     https://x.com/zozuar/status/1625182758745128981
//   The rotate helper and colorBandingFix dither are verbatim from
//   paper-design/shaders shader-utils.ts (same Apache-2.0 license).
//
// CONVERSION NOTES (vs. upstream)
//   • Entry point rewritten to Ghostty's ShaderToy-style mainImage().
//   • u_time -> iTime. u_resolution unused (terminal fills the viewport).
//   • v_patternUV (a vertex-fit pattern UV) -> centered fragCoord/iResolution.
//     The defaultPatternSizing scale (1.0) and the upstream shape_uv *= .13
//     are preserved; the pattern reads at the same density.
//   • Runtime uniforms converted to tunable const values, defaulted to the
//     upstream "Default" preset
//     (colorFront #ffffff, colorMid #47a6ff, colorBack #000000,
//      brightness 0.05, contrast 0.3).
//   • DEVIATION from upstream (intentional, for Ghostty):
//       - colorBack is transparent instead of #000000, so the terminal's real
//         background shows through empty areas.
//       - colorMid cycles continuously through a neon palette (see TUNING)
//         instead of the fixed #47a6ff.
//   • COMPOSITING (Ghostty-specific): upstream emits a standalone RGBA
//     graphic over a transparent canvas. Ghostty supplies the already-
//     rendered terminal as iChannel0, where glyph pixels are opaque and the
//     background is transparent, and the shader's fragColor FULLY REPLACES
//     the frame (no later glyph redraw). So we composite inside the shader
//     with a standard premultiplied "over": terminal on top, pattern behind.
//     The pattern's own alpha tracks its intensity (colorBack is transparent,
//     not a fill), so dim web areas are see-through to whatever is behind
//     Ghostty. Result: the neuro web animates in the empty background areas;
//     glyphs render unchanged on top of it.
//
//   • colorBandingFix (1/256 dither) preserved to avoid banding in the dark
//     gradient regions — important on a terminal background.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Defaults match the upstream "Default" preset ---------------------------
const vec3  COLOR_FRONT   = vec3(1.0);                  // #ffffff crossing-point highlight
const float BRIGHTNESS    = 0.05;                       // luminosity of crossing points (0..1)
const float CONTRAST      = 0.3;                        // sharpness of the bright-dark transition (0..1)
const float PATTERN_SCALE = 0.13;                       // shape_uv scale (upstream literal); smaller = denser web

// --- colorMid: rotating neon palette ---------------------------------------
// colorMid cycles continuously through these key colors. Add/remove entries
// freely; the palette interpolates between adjacent stops and wraps around.
const float COLOR_CYCLE_SPEED = 0.08;                   // full palette passes per second (lower = slower)
const vec3  NEON_0 = vec3(1.0, 0.06, 0.94);             // hot pink  #ff10f0
const vec3  NEON_1 = vec3(0.0, 1.0, 1.0);               // cyan      #00ffff
const vec3  NEON_2 = vec3(0.22, 1.0, 0.08);             // neon green#39ff14
const vec3  NEON_3 = vec3(1.0, 0.84, 0.0);              // neon yellow #ffd700
const vec3  NEON_4 = vec3(1.0, 0.34, 0.12);             // neon orange #ff571f
const vec3  NEON_5 = vec3(0.31, 0.31, 1.0);             // electric indigo #4f4fff
// ===========================================================================

#define TWO_PI 6.28318530718

// --- rotate (upstream shader-utils.ts, rotation2) --------------------------
vec2 rotate(vec2 uv, float th) {
  return mat2(cos(th), sin(th), -sin(th), cos(th)) * uv;
}

// Smoothly cycle colorMid through the neon palette. `phase` is a continuous
// index into the stops; fractional parts blend adjacent colors with a
// smoothstep for a flowing, non-linear transition.
vec3 neonMidColor(float phase) {
  float n = 6.0;                          // number of palette stops above
  float i = mod(phase, n);                // continuous index in [0, n)
  float idx = floor(i);
  float f = i - idx;
  float s = smoothstep(0.0, 1.0, f);      // ease the crossfade

  // Lookup table (kept inline to stay self-contained, per repo conventions).
  vec3 a, b;
  if      (idx < 0.5) { a = NEON_0; b = NEON_1; }
  else if (idx < 1.5) { a = NEON_1; b = NEON_2; }
  else if (idx < 2.5) { a = NEON_2; b = NEON_3; }
  else if (idx < 3.5) { a = NEON_3; b = NEON_4; }
  else if (idx < 4.5) { a = NEON_4; b = NEON_5; }
  else                { a = NEON_5; b = NEON_0; }   // wrap

  return mix(a, b, s);
}

// zozuar's neuro shape: 15 rotated, time-drifting octaves accumulating
// cos/sin into a web field. Returns a value used (squared) for brightness.
float neuroShape(vec2 uv, float t) {
  vec2 sine_acc = vec2(0.);
  vec2 res = vec2(0.);
  float scale = 8.;

  for (int j = 0; j < 15; j++) {
    uv = rotate(uv, 1.);
    sine_acc = rotate(sine_acc, 1.);
    vec2 layer = uv * scale + float(j) + sine_acc - t;
    sine_acc += sin(layer);
    res += (.5 + .5 * cos(layer)) / scale;
    scale *= (1.2);
  }
  return res.x + res.y;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 res = iResolution.xy;

  // Pattern space: centered normalized coords, scaled to upstream density.
  vec2 shape_uv = (fragCoord / res - 0.5) * PATTERN_SCALE * 10.0;

  float t = 0.5 * iTime;

  float noise = neuroShape(shape_uv, t);

  noise = (1. + BRIGHTNESS) * noise * noise;
  noise = pow(noise, 0.7 + 6. * CONTRAST);
  noise = min(1.4, noise);

  float blend = smoothstep(0.7, 1.4, noise);

  // colorMid cycles through the neon palette; COLOR_FRONT stays white at the
  // bright crossings.
  vec3 midC = neonMidColor(iTime * COLOR_CYCLE_SPEED);
  vec3 blendFront = mix(midC, COLOR_FRONT, blend);

  float safeNoise = max(noise, 0.0);
  vec3 color = blendFront * safeNoise;

  // colorBack is transparent: no fill behind the web. Empty areas see
  // through to the terminal's real background.

  // 8-bit dither to kill banding in the dark gradient (upstream colorBandingFix).
  color += 1. / 256. * (fract(sin(dot(.014 * gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453123) - .5);

  // --- Pattern alpha: dim web areas are transparent (colorBack = pure trans) ---
  // color already = blendFront * safeNoise, i.e. it is effectively premultiplied
  // by safeNoise (dark areas are ~0). So alpha = safeNoise makes those areas
  // genuinely see-through to whatever sits behind Ghostty.
  float patternAlpha = clamp(safeNoise, 0.0, 1.0);

  // --- Ghostty compositing: pattern behind the terminal, glyphs on top ---
  // The shader's fragColor FULLY REPLACES the frame (Ghostty does no later
  // glyph-redraw pass), so we must composite inside the shader. Both layers
  // are premultiplied: pattern.rgb is already scaled by safeNoise above, and
  // iChannel0 (the terminal) is premultiplied by Ghostty. Standard "over":
  //   result.rgb = front.rgb + back.rgb * (1 - front.a)
  //   result.a   = front.a  + back.a  * (1 - front.a)
  vec4 term = texture(iChannel0, fragCoord / res);
  float backA = 1.0 - term.a;
  vec3  finalColor = term.rgb + color * backA;
  float finalAlpha = term.a + patternAlpha * backA;
  fragColor = vec4(finalColor, finalAlpha);
}
