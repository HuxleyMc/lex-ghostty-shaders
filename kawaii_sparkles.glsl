// Kawaii Sparkles — a Ghostty custom shader: pastel cursor hearts and twinkles.
//
// Each cursor change emits a compact cute burst around the cursor: a soft
// blush glow, small hearts, four-point sparkles, and faint bubbles drifting
// upward. The effect is stateless ShaderToy-style: every frame is rebuilt from
// iTime, iTimeCursorChange, iCurrentCursor, iPreviousCursor, iResolution,
// iChannel0, and pure math. Fast typing keeps the decorations active, while
// idle terminals fade back to the unmodified terminal image.
//
// Large cursor jumps are damped through iPreviousCursor so mouse clicks,
// teleports, and selection jumps do not create oversized pastel flashes.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 1.35;  // seconds before the burst fades out
const float ACTIVITY_FADE_POWER = 1.55;  // higher = sharper fade near the end

// --- Glow ------------------------------------------------------------------
const float GLOW_RADIUS         = 0.115; // halo radius in height-normalized UV
const float GLOW_INTENSITY      = 0.24;  // blush/cyan light around the cursor

// --- Hearts ----------------------------------------------------------------
const int   HEART_COUNT         = 7;     // number of procedural hearts
const float HEART_INTENSITY     = 0.42;  // brightness of pastel heart fills

// --- Sparkles ---------------------------------------------------------------
const int   SPARKLE_COUNT       = 12;    // number of four-point twinkles
const float SPARKLE_INTENSITY   = 0.46;  // brightness of star sparkle cores

// --- Bubbles ----------------------------------------------------------------
const int   BUBBLE_COUNT        = 9;     // number of faint drifting bubbles
const float BUBBLE_INTENSITY    = 0.20;  // brightness of bubble rims

// --- Color -----------------------------------------------------------------
const vec3  PASTEL_PINK         = vec3(1.00, 0.47, 0.76);
const vec3  PASTEL_PEACH        = vec3(1.00, 0.66, 0.55);
const vec3  PASTEL_LAVENDER     = vec3(0.70, 0.58, 1.00);
const vec3  PASTEL_CYAN         = vec3(0.48, 0.90, 1.00);
const vec3  WARM_WHITE          = vec3(1.00, 0.94, 0.82);
// ===========================================================================

const float PI = 3.1415926535897932;
const float TAU = 6.2831853071795864;

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

mat2 rotate2(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

float cursorStepGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cellsSq = dot(cursorDelta, cursorDelta);

    // One-cell movement is usually typing. Big jumps still decorate, but softly.
    float typedStep = smoothstep(0.12, 1.56, cellsSq) * (1.0 - smoothstep(3.24, 36.0, cellsSq));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.12, cellsSq);
    float localEvent = max(typedStep, stationaryEvent * 0.72);
    return mix(0.24, 1.0, localEvent);
}

float heartMask(vec2 p, float size) {
    vec2 q = p / max(size, 0.0001);
    q.y = -q.y + 0.18;
    q.x *= 0.92;

    float a = q.x * q.x + q.y * q.y - 1.0;
    float heart = a * a * a - q.x * q.x * q.y * q.y * q.y;
    float fill = 1.0 - smoothstep(-0.045, 0.045, heart);
    float softEdge = exp(-dot(q, q) * 2.6);
    return fill * softEdge;
}

float sparkleMask(vec2 p, float size, float phase) {
    vec2 q = p / max(size, 0.0001);
    float twinkle = 0.62 + 0.38 * sin(phase);

    float horizontal = exp(-q.y * q.y * 92.0) * (1.0 - smoothstep(0.05, 1.10, abs(q.x)));
    float vertical = exp(-q.x * q.x * 92.0) * (1.0 - smoothstep(0.05, 1.10, abs(q.y)));

    vec2 d = rotate2(0.78539816339) * q;
    float diagA = exp(-d.y * d.y * 130.0) * (1.0 - smoothstep(0.02, 0.68, abs(d.x)));
    float diagB = exp(-d.x * d.x * 130.0) * (1.0 - smoothstep(0.02, 0.68, abs(d.y)));

    float core = exp(-dot(q, q) * 18.0);
    return (max(horizontal, vertical) + (diagA + diagB) * 0.34 + core * 0.55) * twinkle;
}

float bubbleMask(vec2 p, float radius) {
    float dist = length(p);
    float rim = exp(-pow((dist - radius) / max(radius * 0.16, 0.0008), 2.0));
    float glint = exp(-dot(p - vec2(-radius * 0.32, -radius * 0.36), p - vec2(-radius * 0.32, -radius * 0.36)) / max(radius * radius * 0.05, 0.000001));
    return rim * 0.78 + glint * 0.42;
}

vec3 palette(float h) {
    vec3 a = mix(PASTEL_PINK, PASTEL_PEACH, smoothstep(0.00, 0.33, h));
    vec3 b = mix(PASTEL_LAVENDER, PASTEL_CYAN, smoothstep(0.40, 1.00, h));
    return mix(a, b, smoothstep(0.28, 0.78, h));
}

vec3 kawaiiField(vec2 p, float age, float seed, float jumpGain, out float alphaOut) {
    vec3 light = vec3(0.0);
    float alpha = 0.0;

    for (int i = 0; i < HEART_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 13.11);
        float h1 = hash11(seed + fi * 23.71 + 7.0);
        float h2 = hash11(seed + fi * 37.43 + 3.0);
        float h3 = hash11(seed + fi * 53.09 + 11.0);

        float localAge = max(age - h1 * 0.18, 0.0);
        float life = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.55, 1.00, h2)), 0.0);
        float appear = smoothstep(0.0, 0.10, localAge);
        float angle = h0 * TAU;
        vec2 dir = vec2(cos(angle), sin(angle));
        float drift = 0.018 + localAge * mix(0.030, 0.075, h2);
        vec2 center = dir * drift + vec2(0.0, -localAge * mix(0.014, 0.035, h3));

        vec2 q = rotate2((h2 - 0.5) * 0.72 + sin(age * 5.0 + h0 * TAU) * 0.12) * (p - center);
        float size = mix(0.009, 0.017, h3);
        float m = heartMask(q, size) * appear * life * jumpGain;
        light += palette(h0) * m * HEART_INTENSITY;
        alpha = max(alpha, m * 0.42);
    }

    for (int i = 0; i < SPARKLE_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 19.37 + 2.0);
        float h1 = hash11(seed + fi * 29.91 + 5.0);
        float h2 = hash11(seed + fi * 43.27 + 13.0);
        float h3 = hash11(seed + fi * 71.63 + 17.0);

        float localAge = max(age - h2 * 0.22, 0.0);
        float life = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.38, 0.82, h1)), 0.0);
        float appear = smoothstep(0.0, 0.055, localAge);
        float angle = h0 * TAU;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 center = dir * (mix(0.018, 0.095, h1) + localAge * mix(0.020, 0.060, h3));
        center.y -= localAge * 0.020;

        vec2 q = rotate2(h3 * TAU + localAge * 0.55) * (p - center);
        float size = mix(0.010, 0.022, h2);
        float m = sparkleMask(q, size, iTime * mix(8.0, 15.0, h1) + h0 * TAU) * appear * life * jumpGain;
        light += mix(WARM_WHITE, palette(h2), 0.36) * m * SPARKLE_INTENSITY;
        alpha = max(alpha, m * 0.30);
    }

    for (int i = 0; i < BUBBLE_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 11.83 + 1.0);
        float h1 = hash11(seed + fi * 31.17 + 9.0);
        float h2 = hash11(seed + fi * 47.41 + 4.0);
        float h3 = hash11(seed + fi * 67.29 + 6.0);

        float localAge = max(age - h3 * 0.16, 0.0);
        float life = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.60, 1.08, h1)), 0.0);
        float appear = smoothstep(0.0, 0.12, localAge);
        float angle = h0 * TAU;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 center = dir * (mix(0.020, 0.072, h2) + localAge * 0.024);
        center.y -= localAge * mix(0.030, 0.070, h1);
        center.x += sin(localAge * 5.0 + h0 * TAU) * 0.006;

        float radius = mix(0.0065, 0.016, h2) * (1.0 + localAge * 0.45);
        float m = bubbleMask(p - center, radius) * appear * life * jumpGain;
        light += mix(PASTEL_CYAN, WARM_WHITE, 0.48) * m * BUBBLE_INTENSITY;
        alpha = max(alpha, m * 0.22);
    }

    alphaOut = alpha;
    return light;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float t = iTime;

    vec4 color = texture(iChannel0, uv);

    float activity = activityAmount(t);
    if (activity <= 0.0001) {
        fragColor = color;
        return;
    }

    float aspect = res.x / res.y;
    float age = max(t - iTimeCursorChange, 0.0);
    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );

    float jumpGain = cursorStepGain();
    float burst = activity * jumpGain;

    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float distSq = dot(p, p);

    float seed = iTimeCursorChange * 47.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 131.0;
    float decoAlpha = 0.0;
    vec3 deco = kawaiiField(p, age, seed, jumpGain, decoAlpha);

    float halo = exp(-distSq / max(GLOW_RADIUS * GLOW_RADIUS, 0.0000001));
    float core = exp(-distSq / max(GLOW_RADIUS * GLOW_RADIUS * 0.11, 0.0000001));
    vec3 haloColor = mix(PASTEL_PINK, PASTEL_CYAN, 0.28 + 0.18 * sin(seed));

    // Keep the effect additive and activity-gated so idle terminals return to
    // their original colors without a permanent pastel wash.
    color.rgb += haloColor * halo * GLOW_INTENSITY * burst;
    color.rgb += WARM_WHITE * core * GLOW_INTENSITY * 0.34 * burst;
    color.rgb += deco * activity;

    float softBlush = clamp(decoAlpha * activity * 0.055, 0.0, 0.055);
    color.rgb = mix(color.rgb, color.rgb * vec3(1.02, 0.985, 1.01), softBlush);

    fragColor = vec4(color.rgb, color.a);
}
