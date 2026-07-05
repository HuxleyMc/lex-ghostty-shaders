// Frost Glass - a Ghostty custom shader: cool glass tint with thawing veins.
//
// The idle state adds only a faint cool glass tint. Cursor changes briefly grow
// frost veins near the cursor, add a tiny refractive wobble, then thaw quickly
// back to the original terminal image. The shader is stateless ShaderToy-style:
// every frame is rebuilt from iTime, iTimeCursorChange, iCurrentCursor,
// iPreviousCursor, iResolution, iChannel0, and pure math.
//
// Large cursor jumps are damped so mouse clicks, selection jumps, and pane
// changes do not frost over the terminal.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 1.05;  // seconds before frost veins thaw
const float ACTIVITY_FADE_POWER = 1.85;  // higher = sharper fade near the end

// --- Idle glass -------------------------------------------------------------
const float IDLE_TINT_STRENGTH  = 0.035; // faint always-on cool tint
const float IDLE_CONTRAST       = 0.018; // tiny glass-like contrast lift

// --- Frost veins ------------------------------------------------------------
const float FROST_RADIUS        = 0.190; // cursor-local frost area
const float VEIN_SCALE          = 34.0;  // higher = finer vein pattern
const float VEIN_WIDTH          = 0.045; // lower = thinner frost cracks
const float VEIN_INTENSITY      = 0.36;  // brightness of thawing veins
const float FROST_HAZE          = 0.13;  // soft local icy haze

// --- Refraction -------------------------------------------------------------
const float REFRACTION          = 0.0022;// activity-time glass displacement

// --- Cursor activity --------------------------------------------------------
const float JUMP_DAMPING        = 0.25;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  GLASS_TINT          = vec3(0.82, 0.94, 1.00);
const vec3  FROST_BLUE          = vec3(0.56, 0.88, 1.00);
const vec3  FROST_WHITE         = vec3(0.94, 0.99, 1.00);
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
    float amp = 0.55;
    for (int i = 0; i < 4; i++) {
        v += valueNoise(p) * amp;
        p = p * 2.03 + vec2(13.7, 5.9);
        amp *= 0.50;
    }
    return v;
}

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

float cursorJumpGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cells = length(cursorDelta);

    float typedStep = smoothstep(0.10, 1.35, cells) * (1.0 - smoothstep(2.4, 8.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.10, cells);
    float localEvent = max(typedStep, stationaryEvent * 0.70);
    return mix(JUMP_DAMPING, 1.0, localEvent);
}

float frostVeins(vec2 p, float age, float seed) {
    vec2 q = p * VEIN_SCALE;
    float n1 = fbm(q + vec2(seed * 0.013, age * 1.4));
    float n2 = fbm(q * 0.62 + vec2(-age * 0.9, seed * 0.017));
    float cells = abs(n1 - n2);
    float cracks = 1.0 - smoothstep(VEIN_WIDTH, VEIN_WIDTH * 2.7, cells);
    float branches = 1.0 - smoothstep(0.018, 0.105, abs(fract(n1 * 6.0 + n2 * 3.0) - 0.5));
    return max(cracks, branches * 0.38);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float aspect = res.x / res.y;
    float t = iTime;
    float age = max(t - iTimeCursorChange, 0.0);

    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );

    float activity = activityAmount(t);
    float burst = activity * cursorJumpGain();
    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float localMask = exp(-dot(p, p) / max(FROST_RADIUS * FROST_RADIUS, 0.0000001));

    float seed = iTimeCursorChange * 67.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 89.0;
    float veins = frostVeins(p, age, seed) * localMask;
    float frost = veins * burst;

    vec2 grad = vec2(
        frostVeins(p + vec2(0.006, 0.0), age, seed) - frostVeins(p - vec2(0.006, 0.0), age, seed),
        frostVeins(p + vec2(0.0, 0.006), age, seed) - frostVeins(p - vec2(0.0, 0.006), age, seed)
    );
    vec2 refractUv = uv + grad * REFRACTION * burst;
    refractUv = clamp(refractUv, vec2(0.0), vec2(1.0));

    vec4 color = texture(iChannel0, refractUv);

    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, mix(color.rgb, GLASS_TINT, 0.32), IDLE_TINT_STRENGTH);
    color.rgb = mix(color.rgb, vec3(luma) + (color.rgb - vec3(luma)) * (1.0 + IDLE_CONTRAST), IDLE_CONTRAST);

    color.rgb += mix(FROST_BLUE, FROST_WHITE, veins) * frost * VEIN_INTENSITY;
    color.rgb = mix(color.rgb, mix(color.rgb, FROST_BLUE, 0.18), localMask * FROST_HAZE * burst);

    fragColor = vec4(color.rgb, color.a);
}
