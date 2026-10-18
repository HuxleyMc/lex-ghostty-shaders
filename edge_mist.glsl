// Edge Mist — a Ghostty custom shader: cool fog that gathers at the viewport
// edges and clears toward the working centre.
//
// Soft blue-grey haze collects along the borders and corners while the middle
// of the terminal stays near the unmodified image, so daily text work stays
// readable. A cheap value-noise field crawls very slowly through the mist so
// the fog feels alive without becoming a spectacle. Optional tiny refraction
// is gated to the thickest mist and defaults near zero.
//
// Distinct from other treatments in this repo:
//   • aurora_veil  — coloured ribbons weighted to the top third
//   • frost_glass  — cursor-triggered frost veins that thaw when idle
//   • paper_grain  — static grain plus a warm vignette, no motion
//
// THE STATELESS PATTERN
//   Ghostty custom shaders are stateless (ShaderToy format). The GPU carries
//   no per-frame state, and only iChannel0 (the already-rendered terminal
//   image) plus built-in uniforms are available. There is no feedback buffer,
//   no history of past frames, and no way to accumulate fog over time.
//
//   This effect is rebuilt every frame from:
//     • iChannel0   — the current terminal image (one sample: unwarped, or a
//                     single tiny offset when mist is strong and REFRACTION>0)
//     • iResolution — pixel size, used for UVs
//     • iTime       — wall clock, drives the slow noise crawl
//
//   No cursor uniforms are read. iTimeCursorChange is not required. Motion is
//   only the ambient drift of the mist texture; idle terminals keep the same
//   quiet edge fog they had while typing.
//
//   Limitation: because nothing persists between frames, the mist cannot
//   "settle" or respond to recent activity. The look is a function of UV and
//   iTime alone.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Edge mask (UV radius from centre; corners sit near 1.414) --------------
const float INNER_RADIUS     = 0.52;  // mist begins; keep high so the centre stays clear
const float OUTER_RADIUS     = 1.18;  // full mist; mid-edges are partial, corners thicker
const float EDGE_POWER       = 1.35;  // falloff shape; higher = mist hugs the borders more

// --- Mist look --------------------------------------------------------------
const float MIST_STRENGTH    = 0.22;  // mix amount of the cool haze (keep quiet for daily use)
const float TINT_STRENGTH    = 0.55;  // how strongly the haze is pulled toward MIST_TINT
const float MIST_SCALE       = 2.35;  // value-noise cell size; lower = broader wisps
const float DRIFT_SPEED      = 0.016; // UV/s crawl of the mist texture; keep very slow

// --- Optional refraction (one warped sample only where mist is strong) ------
const float REFRACTION       = 0.0012;// terminal lookup offset; 0 disables the warped path
const float REFRACT_THRESHOLD = 0.38; // mist amount that must be exceeded before warping

// --- Color ------------------------------------------------------------------
const vec3  MIST_TINT        = vec3(0.62, 0.74, 0.86); // cool blue-grey
const vec3  MIST_HAZE        = vec3(0.78, 0.86, 0.94); // paler lift in the thickest fog
// ===========================================================================

// One cheap 2D hash. Same construction used by other shaders in this repo.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two cheap value-noise looks, not a fractal octave stack and not a loop.
float mistTexture(vec2 uv, float t) {
    vec2 drift = vec2(t * DRIFT_SPEED * 0.37, t * DRIFT_SPEED * 0.21);
    vec2 p = uv * MIST_SCALE + drift;
    float broad = valueNoise(p);
    float wisp  = valueNoise(p * 1.73 + vec2(5.1, -3.7) - drift * 0.62);
    return mix(broad, wisp, 0.42);
}

float edgeMask(vec2 uv) {
    vec2 centered = uv * 2.0 - 1.0;
    float r = length(centered);
    float inner = min(INNER_RADIUS, OUTER_RADIUS);
    float outer = max(INNER_RADIUS, OUTER_RADIUS);
    float edge = smoothstep(inner, outer, r);
    return pow(edge, max(EDGE_POWER, 0.001));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float t = iTime;

    float mask = edgeMask(uv);
    float n = mistTexture(uv, t);
    // Noise valleys still keep a little edge fog so the frame does not hole out.
    float mist = mask * mix(0.42, 1.0, n);

    // Prefer one unwarped sample. Offset iChannel0 only in thick mist, and only
    // when REFRACTION is non-zero, so the centre glyphs stay on their pixels.
    vec4 term;
    if (REFRACTION > 0.0001 && mist > REFRACT_THRESHOLD) {
        vec2 warp = (vec2(n, fract(n * 17.13)) - 0.5) * 2.0 * REFRACTION * mist;
        term = texture(iChannel0, clamp(uv + warp, vec2(0.0), vec2(1.0)));
    } else {
        term = texture(iChannel0, uv);
    }

    float amount = mist * MIST_STRENGTH;
    vec3 cooled = mix(term.rgb, term.rgb * MIST_TINT, amount * TINT_STRENGTH);
    vec3 misted = mix(cooled, mix(cooled, MIST_HAZE, 0.50), amount);

    fragColor = vec4(misted, term.a);
}
