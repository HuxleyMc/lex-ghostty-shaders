// Aurora Veil — a Ghostty custom shader: slow top-weighted aurora ribbons.
//
// Adds soft cyan, green, and violet curtains near the upper third of the
// terminal while preserving text legibility. The effect is ambient-only and is
// rebuilt every frame from iTime, iResolution, iChannel0, and pure procedural
// noise. It uses no cursor coupling, feedback buffers, external textures,
// preprocessing, or generated data.
//
// This shader is original procedural code and uses no upstream shader source.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Aurora layout ----------------------------------------------------------
const float AURORA_HEIGHT    = 0.44;   // vertical reach from the top of screen
const float RIBBON_INTENSITY = 0.34;   // brightness added by the aurora bands
const float DRIFT_SPEED      = 0.080;  // lateral/time drift speed
const float RIBBON_SCALE     = 2.70;   // pattern scale; higher = tighter folds

// --- Surface rendering ------------------------------------------------------
const float TINT_STRENGTH    = 0.055;  // low ambient aurora tint over top area
const float REFRACTION       = 0.006;  // subtle terminal lookup displacement

// --- Color -----------------------------------------------------------------
const vec3  CYAN_RIBBON      = vec3(0.28, 0.92, 1.00);
const vec3  GREEN_RIBBON     = vec3(0.30, 1.00, 0.54);
const vec3  VIOLET_RIBBON    = vec3(0.68, 0.40, 1.00);
// ===========================================================================

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

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * valueNoise(p);
        p = p * 2.03 + vec2(17.1, 9.3);
        amp *= 0.5;
    }
    return v;
}

float topMask(vec2 uv) {
    float reach = 1.0 - smoothstep(AURORA_HEIGHT * 0.55, AURORA_HEIGHT, uv.y);
    float edge = smoothstep(0.0, 0.035, uv.y);
    return reach * edge;
}

float ribbonLayer(vec2 uv, float t, float seed, float baseY, float width, float wobble) {
    vec2 p = vec2(uv.x * RIBBON_SCALE + seed, uv.y * 2.0);
    float slowNoise = fbm(p + vec2(t * DRIFT_SPEED * (0.7 + seed * 0.11), seed));
    float fastNoise = fbm(p * 1.7 + vec2(-t * DRIFT_SPEED * 0.55, seed * 2.3));

    float curve = baseY
        + sin(uv.x * (2.6 + seed * 0.22) + t * (0.18 + seed * 0.025) + seed) * wobble
        + (slowNoise - 0.5) * wobble * 1.55
        + (fastNoise - 0.5) * wobble * 0.55;

    float dist = abs(uv.y - curve);
    float ribbon = exp(-(dist * dist) / max(width * width, 0.00001));
    float strand = 0.58 + 0.42 * sin((uv.x + slowNoise * 0.65) * 18.0 + t * 0.42 + seed);
    return ribbon * strand * topMask(uv);
}

float auroraField(vec2 uv, float t) {
    float a = 0.0;
    a += ribbonLayer(uv, t, 1.0, 0.095, 0.032, 0.030) * 0.95;
    a += ribbonLayer(uv, t, 4.0, 0.185, 0.050, 0.050) * 0.78;
    a += ribbonLayer(uv, t, 7.0, 0.305, 0.072, 0.070) * 0.52;
    return min(a, 1.4);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float t = iTime;

    vec2 eps = 1.0 / res;
    float field = auroraField(uv, t);
    float fx = auroraField(uv + vec2(eps.x, 0.0), t);
    float fy = auroraField(uv + vec2(0.0, eps.y), t);
    vec2 tilt = vec2(field - fx, field - fy);

    vec2 refractedUV = clamp(uv + tilt * REFRACTION, vec2(0.0), vec2(1.0));
    vec4 color = texture(iChannel0, refractedUV);

    vec3 ribbonColor = mix(CYAN_RIBBON, GREEN_RIBBON, smoothstep(0.05, 0.38, uv.y));
    ribbonColor = mix(ribbonColor, VIOLET_RIBBON, smoothstep(0.22, AURORA_HEIGHT, uv.y) * 0.55);

    float mask = topMask(uv);
    color.rgb = mix(color.rgb, color.rgb * (1.0 + ribbonColor * 0.18), TINT_STRENGTH * mask);
    color.rgb += ribbonColor * field * RIBBON_INTENSITY * mask;

    fragColor = vec4(color.rgb, color.a);
}
