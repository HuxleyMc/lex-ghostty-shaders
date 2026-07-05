// Hologram Jitter - a Ghostty custom shader: cyan hologram treatment.
//
// The idle state has a restrained cyan hologram tint. Cursor changes briefly
// add small horizontal glitch lines, tiny chromatic jitter, and local shimmer
// near the cursor, then fade back to daily-use readability. The shader is
// stateless ShaderToy-style: every frame is rebuilt from iTime,
// iTimeCursorChange, iCurrentCursor, iPreviousCursor, iResolution, iChannel0,
// and pure math.
//
// Large cursor jumps are damped so mouse clicks, selection jumps, and pane
// changes do not cause heavy full-screen glitches.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 0.92;  // seconds before jitter fades out
const float ACTIVITY_FADE_POWER = 1.72;  // higher = sharper fade near the end

// --- Idle hologram ----------------------------------------------------------
const float IDLE_TINT_STRENGTH  = 0.055; // faint always-on cyan tint
const float IDLE_SCANLINE       = 0.035; // subtle stable scanline shading

// --- Cursor-local jitter ----------------------------------------------------
const float JITTER_RADIUS       = 0.170; // cursor-local activity area
const float GLITCH_LINE_COUNT   = 9.0;   // number of possible line bands
const float GLITCH_WIDTH        = 0.010; // height of horizontal glitch bands
const float GLITCH_SHIFT        = 0.0045;// maximum horizontal line displacement
const float CHROMA_OFFSET       = 0.0017;// red/blue channel separation
const float GLITCH_INTENSITY    = 0.22;  // brightness of activity-time glitches

// --- Cursor activity --------------------------------------------------------
const float JUMP_DAMPING        = 0.26;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  HOLO_CYAN           = vec3(0.20, 0.90, 1.00);
const vec3  HOLO_BLUE           = vec3(0.18, 0.34, 1.00);
const vec3  HOLO_WHITE          = vec3(0.86, 1.00, 1.00);
// ===========================================================================

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

float glitchBands(vec2 p, float age, float seed, out float shiftOut) {
    float bands = 0.0;
    float shift = 0.0;

    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float keep = step(fi, GLITCH_LINE_COUNT - 0.5);
        float h0 = hash11(seed + fi * 13.71);
        float h1 = hash11(seed + fi * 29.17 + 3.0);
        float h2 = hash11(seed + fi * 47.53 + 7.0);

        float centerY = (h0 * 2.0 - 1.0) * JITTER_RADIUS * 0.82;
        centerY += sin(age * mix(7.0, 15.0, h1) + h2 * 6.28318) * 0.012;
        float band = exp(-pow((p.y - centerY) / max(GLITCH_WIDTH * mix(0.55, 1.35, h2), 0.0001), 2.0));
        float xGate = smoothstep(-JITTER_RADIUS, -JITTER_RADIUS * 0.35, p.x) * (1.0 - smoothstep(JITTER_RADIUS * 0.35, JITTER_RADIUS, p.x));
        float life = max(1.0 - age / (ACTIVITY_LIFE * mix(0.45, 1.0, h1)), 0.0);
        float amount = band * xGate * life * keep;

        bands = max(bands, amount);
        shift += amount * (h1 * 2.0 - 1.0) * GLITCH_SHIFT;
    }

    shiftOut = shift;
    return bands;
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
    float localMask = exp(-dot(p, p) / max(JITTER_RADIUS * JITTER_RADIUS, 0.0000001));
    float seed = iTimeCursorChange * 83.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 127.0;

    float lineShift = 0.0;
    float bands = glitchBands(p, age, seed, lineShift);
    float jitter = burst * max(bands, localMask * 0.18);

    vec2 sampleUv = uv + vec2(lineShift * burst, 0.0);
    sampleUv += vec2((hash11(floor(fragCoord.y) + floor(t * 18.0) + seed) - 0.5) * GLITCH_SHIFT * 0.18 * burst * localMask, 0.0);
    sampleUv = clamp(sampleUv, vec2(0.0), vec2(1.0));

    vec4 base = texture(iChannel0, sampleUv);
    float chroma = CHROMA_OFFSET * jitter;
    vec3 chromatic;
    chromatic.r = texture(iChannel0, clamp(sampleUv + vec2(chroma, 0.0), vec2(0.0), vec2(1.0))).r;
    chromatic.g = base.g;
    chromatic.b = texture(iChannel0, clamp(sampleUv - vec2(chroma, 0.0), vec2(0.0), vec2(1.0))).b;

    vec3 color = mix(base.rgb, chromatic, clamp(jitter * 1.8, 0.0, 1.0));

    float scan = 0.5 + 0.5 * sin(fragCoord.y * 2.35 + floor(t * 6.0));
    color.rgb *= 1.0 - scan * IDLE_SCANLINE;
    color.rgb = mix(color.rgb, color.rgb * (vec3(1.0) + HOLO_CYAN * 0.22), IDLE_TINT_STRENGTH);

    vec3 glitchColor = mix(HOLO_CYAN, HOLO_BLUE, 0.35 + 0.25 * sin(seed));
    color.rgb += glitchColor * bands * GLITCH_INTENSITY * burst;
    color.rgb += HOLO_WHITE * localMask * GLITCH_INTENSITY * 0.18 * burst;
    color.rgb = mix(color.rgb, color.rgb * vec3(0.94, 1.03, 1.06), clamp(jitter * 0.12, 0.0, 0.12));

    fragColor = vec4(color.rgb, base.a);
}
