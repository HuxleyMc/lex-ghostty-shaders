// Paper Grain — a Ghostty custom shader: static paper/film grain + warm vignette.
//
// Adds a low-contrast, static grain texture and a gentle warm edge vignette.
// Both are applied only to pixels close to the terminal background colour so
// glyphs stay crisp. The pass is one unwarped iChannel0 sample of the current
// pixel, one optional background-reference sample, and a single hash12() —
// no loops, no extra octaves, no motion, no cursor coupling.
//
// Background detection: each pixel is compared to a reference background
// colour (an inset corner sample by default, or BACKGROUND_COLOR when
// USE_SAMPLED_BG is 0). Pixels within BG_THRESHOLD, and near-transparent
// Ghostty empty cells, receive the paper treatment; everything else is
// returned unchanged from iChannel0.
//
// THE STATELESS PATTERN
//   Ghostty custom shaders are stateless (ShaderToy format). This effect is
//   static, so it does not read iTime or iTimeCursorChange. It uses:
//     • iChannel0   — the already-rendered terminal image
//     • iResolution — pixel size for UVs and the background sample
//   Grain is a function of fragCoord only, so it never crawls or flickers.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Grain ------------------------------------------------------------------
const float GRAIN_STRENGTH    = 0.040; // grain amplitude; keep low for daily use
const float GRAIN_SCALE       = 1.0;   // hash cell size in pixels; 1 = per-pixel film grain

// --- Warm vignette ----------------------------------------------------------
const float VIGNETTE_STRENGTH = 0.20;  // edge darkening toward the warm paper tone
const float VIGNETTE_INNER    = 0.32;  // radius^2 where the vignette begins
const float VIGNETTE_OUTER    = 1.42;  // radius^2 of full corner darkening

// --- Background mask --------------------------------------------------------
const float BG_THRESHOLD      = 0.055; // RGB distance treated as background
const float USE_SAMPLED_BG    = 1.0;   // 1 = sample corner; 0 = BACKGROUND_COLOR
const vec2  BG_SAMPLE_UV      = vec2(0.012, 0.988); // inset top-left sample point
const vec3  BACKGROUND_COLOR  = vec3(0.05, 0.05, 0.06); // used when USE_SAMPLED_BG is 0

// --- Color ------------------------------------------------------------------
const vec3  VIGNETTE_WARM     = vec3(1.00, 0.88, 0.70); // warm paper falloff at the edges
const vec3  GRAIN_TINT        = vec3(1.00, 0.96, 0.88); // slight warm bias on the grain
// ===========================================================================

// One cheap 2D hash. Same construction used by other shaders in this repo.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 backgroundRef(vec2 uv) {
    // Branch keeps the extra texture read off the USE_SAMPLED_BG = 0 path.
    if (USE_SAMPLED_BG > 0.5) {
        return texture(iChannel0, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
    }
    return BACKGROUND_COLOR;
}

float backgroundMask(vec3 color, float alpha, vec3 bgRef) {
    float colorDist = distance(color, bgRef);
    float colorMask = 1.0 - smoothstep(0.0, max(BG_THRESHOLD, 1e-5), colorDist);
    // Ghostty often leaves empty cells near-transparent; treat those as paper too.
    float alphaMask = 1.0 - smoothstep(0.02, 0.18, alpha);
    return max(colorMask, alphaMask);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec4 term = texture(iChannel0, uv);

    float bgMask = backgroundMask(term.rgb, term.a, backgroundRef(BG_SAMPLE_UV));

    // Static grain: one hash of the pixel (or GRAIN_SCALE cell). No iTime.
    float n = hash12(floor(fragCoord / max(GRAIN_SCALE, 1.0)));
    float grain = (n - 0.5) * GRAIN_STRENGTH;

    vec2 centered = uv * 2.0 - 1.0;
    float vig = smoothstep(VIGNETTE_INNER, VIGNETTE_OUTER, dot(centered, centered));

    vec3 paper = term.rgb;
    paper *= 1.0 + grain * GRAIN_TINT;
    paper *= mix(vec3(1.0), VIGNETTE_WARM * (1.0 - VIGNETTE_STRENGTH), vig);

    // Glyphs and other non-background pixels stay exactly as sampled.
    fragColor = vec4(mix(term.rgb, paper, bgMask), term.a);
}
