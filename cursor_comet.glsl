// Cursor Comet - a Ghostty custom shader: a short bright tail follows the cursor.
//
// Each cursor change creates a compact comet head and a short fading tail from
// the previous cursor position toward the current one. The shader is stateless
// ShaderToy-style: every frame is rebuilt from iTime, iTimeCursorChange,
// iCurrentCursor, iPreviousCursor, iResolution, iChannel0, and pure math.
//
// Large cursor jumps are damped so mouse clicks, selection jumps, and pane
// changes do not throw a huge streak across the terminal.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 0.82;  // seconds before the comet fades out
const float ACTIVITY_FADE_POWER = 1.70;  // higher = sharper fade near the end

// --- Comet shape ------------------------------------------------------------
const float HEAD_RADIUS         = 0.032; // compact cursor head radius
const float TAIL_LENGTH         = 0.150; // maximum tail length in height-normalized UV
const float TAIL_WIDTH          = 0.010; // tail stroke width
const float SPARK_DENSITY       = 10.0;  // number of small sparks along the tail

// --- Intensity --------------------------------------------------------------
const float HEAD_INTENSITY      = 0.36;  // brightness at the cursor head
const float TAIL_INTENSITY      = 0.44;  // brightness of the fading trail
const float SPARK_INTENSITY     = 0.26;  // brightness of detached tail sparks

// --- Cursor activity --------------------------------------------------------
const float JUMP_DAMPING        = 0.24;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  COMET_CORE          = vec3(0.96, 1.00, 0.82);
const vec3  COMET_CYAN          = vec3(0.22, 0.78, 1.00);
const vec3  COMET_BLUE          = vec3(0.18, 0.36, 1.00);
// ===========================================================================

const float PI = 3.1415926535897932;

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

float segmentMask(vec2 p, vec2 a, vec2 b, float width, out float along) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    along = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
    vec2 d = pa - ba * along;
    return exp(-dot(d, d) / max(width * width, 0.0000001));
}

float sparkField(vec2 p, vec2 tailDir, vec2 tailNormal, float tailLen, float age, float seed) {
    float sparks = 0.0;

    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float lane = (fi + 0.5) / SPARK_DENSITY;
        float h0 = hash11(seed + fi * 17.31);
        float h1 = hash11(seed + fi * 29.73 + 5.0);
        float h2 = hash11(seed + fi * 43.19 + 2.0);
        float keep = step(fi, SPARK_DENSITY - 0.5);

        float drift = age * mix(0.010, 0.036, h1);
        vec2 center = -tailDir * (tailLen * lane + drift);
        center += tailNormal * ((h0 * 2.0 - 1.0) * TAIL_WIDTH * 3.5);
        center.y -= age * mix(0.004, 0.018, h2);

        float size = mix(0.0028, 0.0065, h2);
        float life = max(1.0 - lane * 0.68 - age / ACTIVITY_LIFE * 0.36, 0.0);
        float twinkle = 0.65 + 0.35 * sin(iTime * mix(9.0, 18.0, h1) + h0 * PI);
        sparks += exp(-dot(p - center, p - center) / max(size * size, 0.0000001)) * life * twinkle * keep;
    }

    return sparks;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float aspect = res.x / res.y;
    float t = iTime;
    float age = max(t - iTimeCursorChange, 0.0);

    vec2 currentCursor = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );
    vec2 previousCursor = vec2(
        (iPreviousCursor.x + iPreviousCursor.z * 0.5) / res.x,
        (iPreviousCursor.y - iPreviousCursor.w * 0.5) / res.y
    );

    vec4 color = texture(iChannel0, uv);

    float activity = activityAmount(t);
    float jumpGain = cursorJumpGain();
    float burst = activity * jumpGain;

    vec2 p = vec2((uv.x - currentCursor.x) * aspect, uv.y - currentCursor.y);
    vec2 prevP = vec2((previousCursor.x - currentCursor.x) * aspect, previousCursor.y - currentCursor.y);

    vec2 moveDir = -prevP;
    float moveLen = length(moveDir);
    float stationary = 1.0 - smoothstep(0.001, 0.010, moveLen);
    vec2 fallbackDir = vec2(-1.0, 0.12);
    vec2 tailDir = normalize(mix(moveDir / max(moveLen, 0.0001), normalize(fallbackDir), stationary));
    float tailLen = min(max(moveLen, 0.048), TAIL_LENGTH) * mix(0.55, 1.0, jumpGain);
    vec2 tailNormal = vec2(-tailDir.y, tailDir.x);

    float trailAlong = 0.0;
    float trail = segmentMask(p, -tailDir * tailLen, vec2(0.0), TAIL_WIDTH, trailAlong);
    float taper = smoothstep(0.0, 0.18, trailAlong) * (1.0 - smoothstep(0.78, 1.0, trailAlong) * 0.30);
    float wake = trail * taper * (1.0 - age / max(ACTIVITY_LIFE, 0.0001));

    float head = exp(-dot(p, p) / max(HEAD_RADIUS * HEAD_RADIUS, 0.0000001));
    float core = exp(-dot(p, p) / max(HEAD_RADIUS * HEAD_RADIUS * 0.16, 0.0000001));

    float seed = iTimeCursorChange * 53.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 97.0;
    float sparks = sparkField(p, tailDir, tailNormal, tailLen, age, seed);

    vec3 tailColor = mix(COMET_BLUE, COMET_CYAN, trailAlong);
    color.rgb += tailColor * wake * TAIL_INTENSITY * burst;
    color.rgb += COMET_CYAN * head * HEAD_INTENSITY * burst;
    color.rgb += COMET_CORE * core * HEAD_INTENSITY * 0.70 * burst;
    color.rgb += mix(COMET_CYAN, COMET_CORE, 0.48) * sparks * SPARK_INTENSITY * activity;

    fragColor = vec4(color.rgb, color.a);
}
