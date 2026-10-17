// Dust Motes — a Ghostty custom shader: sparse floating dust over empty background.
//
// Soft, tiny motes drift slowly across the terminal as a subtle ambient overlay.
// They are painted only on background-like pixels so glyphs stay crisp. There is
// no warp, refraction, or cursor coupling — the terminal image is sampled once,
// unwarped, and motes are a cheap additive tint.
//
// THE STATELESS PATTERN
//   Ghostty custom shaders are stateless (ShaderToy format). The GPU carries no
//   per-frame state, and only iChannel0 (the terminal image) plus built-in
//   uniforms are available. This effect is rebuilt each frame from:
//     • iChannel0   — the already-rendered terminal image (one unwarped sample)
//     • iTime       — wall clock; motes drift continuously
//     • iResolution — pixel size for UVs, aspect, and the background sample
//   No iTimeCursorChange or cursor uniforms are required.
//
//   A fixed MOTE_COUNT loop hashes each mote ID to a rest position, size,
//   depth, and drift. Positions wrap, so motes re-enter rather than relying
//   on stored lifetimes. Depth is a cheap parallax stand-in: nearer motes are
//   a little larger, brighter, and faster.
//
// Background detection matches paper_grain.glsl: each pixel is compared to a
// reference background colour (an inset corner sample by default, or
// BACKGROUND_COLOR when USE_SAMPLED_BG is 0). Pixels within BG_THRESHOLD, and
// near-transparent Ghostty empty cells, receive motes; everything else is
// returned unchanged from iChannel0.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Motes ------------------------------------------------------------------
const int   MOTE_COUNT     = 20;    // fixed mote budget; keep small for daily use
const float DRIFT_SPEED    = 0.016; // base ambient drift (height-normalized UV / s)
const float MOTE_SIZE      = 0.0026;// disc radius in height-normalized UV
const float MOTE_INTENSITY = 0.16;  // brightness added at each mote core
const float PARALLAX       = 0.55;  // depth-based speed/size spread; 0 = uniform
const float TWINKLE        = 0.22;  // slow brightness breathing; 0 = steady motes

// --- Background mask --------------------------------------------------------
const float BG_THRESHOLD     = 0.055; // RGB distance treated as background
const float USE_SAMPLED_BG   = 1.0;   // 1 = sample corner; 0 = BACKGROUND_COLOR
const vec2  BG_SAMPLE_UV     = vec2(0.012, 0.988); // inset top-left sample point
const vec3  BACKGROUND_COLOR = vec3(0.05, 0.05, 0.06); // used when USE_SAMPLED_BG is 0

// --- Color ------------------------------------------------------------------
const vec3  MOTE_TINT = vec3(1.00, 0.96, 0.88); // slight warm-white dust catchlight
// ===========================================================================

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
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
    // Ghostty often leaves empty cells near-transparent; treat those as empty too.
    float alphaMask = 1.0 - smoothstep(0.02, 0.18, alpha);
    return max(colorMask, alphaMask);
}

vec2 wrapDelta(vec2 fromPos, vec2 toPos) {
    vec2 d = fromPos - toPos;
    return d - floor(d + 0.5);
}

float moteField(vec2 uv, float aspect, float t) {
    float accum = 0.0;

    for (int i = 0; i < MOTE_COUNT; i++) {
        float seed = float(i) * 17.13 + 0.37;
        float h0 = hash11(seed);
        float h1 = hash11(seed + 3.17);
        float h2 = hash11(seed + 7.91);
        float h3 = hash11(seed + 11.53);
        float h4 = hash11(seed + 13.99);

        // 0 = far / slow / small, 1 = near / faster / a little larger.
        float depth = mix(0.28, 1.0, h0);
        float speed = DRIFT_SPEED * mix(1.0 - PARALLAX, 1.0 + PARALLAX * 0.25, depth);

        vec2 vel = vec2(
            mix(-0.55, 0.70, h1),
            mix(-0.22, 0.38, h2)
        ) * speed;

        vec2 origin = vec2(h3, h4);
        vec2 wobble = vec2(
            sin(t * mix(0.11, 0.29, h1) + seed * 6.28318),
            cos(t * mix(0.09, 0.25, h2) + seed * 4.18879)
        ) * (0.010 * depth);
        vec2 pos = fract(origin + vel * t + wobble);

        vec2 delta = wrapDelta(pos, uv);
        delta.x *= aspect;

        float radius = MOTE_SIZE * mix(0.55, 1.28, depth) * mix(0.78, 1.18, h3);
        float r2 = max(radius * radius, 1e-8);
        float core = exp(-dot(delta, delta) / r2);
        float halo = exp(-dot(delta, delta) / (r2 * 5.8));
        float disc = core * 0.88 + halo * 0.22;

        float twinkle = 1.0 - TWINKLE + TWINKLE * (0.55 + 0.45 * sin(t * mix(0.32, 0.95, h4) + seed * 6.28318));
        float weight = mix(0.42, 1.0, depth);
        accum += disc * twinkle * weight;
    }

    return accum;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec4 term = texture(iChannel0, uv);

    float bgMask = backgroundMask(term.rgb, term.a, backgroundRef(BG_SAMPLE_UV));

    // Glyphs and other non-background pixels stay exactly as sampled.
    if (bgMask <= 0.0) {
        fragColor = term;
        return;
    }

    float aspect = res.x / max(res.y, 1.0);
    float motes = moteField(uv, aspect, iTime);
    term.rgb += MOTE_TINT * motes * MOTE_INTENSITY * bgMask;

    fragColor = vec4(term.rgb, term.a);
}
