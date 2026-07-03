// Fire Embers — a Ghostty custom shader: subtle bottom-weighted fire haze.
//
// Renders the terminal as if warm embers are glowing below the screen: a soft
// lower-edge ember bed, sparse rising sparks, and mild heat-haze refraction
// that fades upward to preserve text legibility. The effect is ambient-only
// and uses no cursor coupling, feedback buffers, external textures, or assets.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Coverage and glow ------------------------------------------------------
const float EMBER_HEIGHT     = 0.42;   // vertical reach of ember/glow influence
const float EMBER_INTENSITY  = 0.16;   // ember color added near the bottom
const float GLOW_INTENSITY   = 0.12;   // broad warm tint strength

// --- Heat shimmer -----------------------------------------------------------
const float HEAT_REFRACTION  = 0.010;  // texture displacement from heat haze
const float HEAT_SPEED       = 0.55;   // upward shimmer speed
const float HEAT_SCALE       = 7.0;    // heat cell scale (higher = finer haze)

// --- Sparks ----------------------------------------------------------------
const float SPARK_DENSITY    = 24.0;   // horizontal spark lanes across screen
const float SPARK_SPEED      = 0.18;   // upward spark drift speed
const float SPARK_BRIGHTNESS = 0.22;   // spark brightness added to terminal

// --- Color -----------------------------------------------------------------
const vec3  DEEP_EMBER       = vec3(0.72, 0.12, 0.03);
const vec3  ORANGE_GLOW      = vec3(1.00, 0.38, 0.08);
const vec3  GOLD_SPARK       = vec3(1.00, 0.72, 0.22);
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
        p = p * 2.03 + vec2(13.7, 7.1);
        amp *= 0.5;
    }
    return v;
}

float bottomMask(vec2 uv) {
    float bottomDistance = 1.0 - uv.y;
    float lower = 1.0 - smoothstep(0.0, EMBER_HEIGHT, bottomDistance);
    float edgeFade = smoothstep(0.0, 0.035, bottomDistance);
    return lower * edgeFade;
}

float sparkField(vec2 uv, float t, float heatMask) {
    float fromBottom = 1.0 - uv.y;
    vec2 lane = vec2(uv.x * SPARK_DENSITY, fromBottom * 8.0 - t * SPARK_SPEED * 8.0);
    vec2 id = floor(lane);
    vec2 cell = fract(lane);

    float rnd = hash12(id);
    float spawn = step(0.92, rnd);
    float x = 0.15 + 0.70 * hash12(id + 19.7);
    float y = fract(hash12(id + 3.1) + t * SPARK_SPEED * (0.7 + rnd));

    vec2 d = vec2((cell.x - x) * 3.4, cell.y - y);
    float emberDot = exp(-dot(d, d) * 42.0);
    float riseFade = 1.0 - smoothstep(0.26, 0.72, fromBottom);

    return emberDot * spawn * heatMask * riseFade;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float aspect = res.x / res.y;
    float t = iTime;

    float heatMask = bottomMask(uv);

    // Heat haze rises from the ember bed, using nearby noise samples as a small
    // gradient so text remains readable instead of wobbling in large waves.
    vec2 heatUV = vec2(uv.x * aspect, 1.0 - uv.y) * HEAT_SCALE;
    heatUV += vec2(0.0, -t * HEAT_SPEED);
    float h = fbm(heatUV + vec2(0.0, fbm(heatUV * 0.55 + t * 0.08)));
    float hx = fbm(heatUV + vec2(0.035, 0.0));
    float hy = fbm(heatUV + vec2(0.0, 0.035));
    vec2 heatTilt = vec2(h - hx, h - hy);

    vec2 refractedUV = clamp(uv + heatTilt * HEAT_REFRACTION * heatMask, vec2(0.0), vec2(1.0));
    vec4 color = texture(iChannel0, refractedUV);

    // Ember bed: broken, breathing glow strongest at the lower edge.
    float emberNoise = fbm(vec2(uv.x * aspect * 5.8, (1.0 - uv.y) * 6.0 - t * 0.32));
    float emberBand = pow(max(heatMask, 0.0), 1.7) * smoothstep(0.36, 0.92, emberNoise);
    float glow = pow(max(heatMask, 0.0), 1.25) * (0.55 + 0.45 * emberNoise);

    vec3 warmTint = mix(DEEP_EMBER, ORANGE_GLOW, emberNoise);
    color.rgb = mix(color.rgb, color.rgb * (1.0 + ORANGE_GLOW * 0.24), glow * GLOW_INTENSITY);
    color.rgb += warmTint * emberBand * EMBER_INTENSITY;

    float sparks = sparkField(uv, t, heatMask);
    color.rgb += GOLD_SPARK * sparks * SPARK_BRIGHTNESS;

    fragColor = vec4(color.rgb, color.a);
}
