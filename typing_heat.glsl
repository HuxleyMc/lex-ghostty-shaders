// Typing Heat — a Ghostty custom shader: a quiet warm tint near the cursor.
//
// The area around the cursor warms slightly as typing speeds up, then cools
// back to the unmodified terminal when idle. There is no distortion, warp,
// grain, bloom geometry, or extra texture reads — glyphs stay crisp. Heat is
// a cheap color mix only.
//
// THE STATELESS PATTERN
//   Ghostty custom shaders carry no per-frame GPU state. This effect is rebuilt
//   each frame from:
//     • iChannel0          — the current terminal image (sampled once, unwarped)
//     • iTime              — wall clock
//     • iTimeCursorChange  — timestamp of the last cursor change (per keystroke;
//                            not retriggered by blink). age = iTime − this.
//     • iCurrentCursor / iPreviousCursor — heat origin + typing-vs-teleport
//                            classification (1 cell = typing, big jump = click)
//
//   "Faster typing → warmer": each keystroke resets age→0. Rapid typing keeps
//   age near zero, so the activity envelope and recency boost stay high. Slower
//   typing lets the tint recede between keystrokes. After ACTIVITY_LIFE with no
//   cursor change, the terminal returns to neutral.
//
//   Limitation: only the single most recent cursor change is timestamped, so a
//   true keystroke-rate history cannot be accumulated. Recency of the latest
//   event is the frequency proxy.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 1.15;  // seconds before heat cools to neutral
const float ACTIVITY_FADE_POWER = 1.70;  // higher = sharper cooldown near the end

// --- Recency / typing tempo -------------------------------------------------
const float RECENCY_BOOST       = 0.55;  // extra warmth when the last change is very fresh
const float RECENCY_TAU         = 0.16;  // seconds — how quickly the recency boost falls

// --- Heat shape -------------------------------------------------------------
const float HEAT_RADIUS         = 0.165; // cursor-local warm area in height-normalized UV
const float HEAT_CORE           = 0.48;  // extra warmth in the very center of the area
const float HEAT_STRENGTH       = 0.14;  // mix amount of the warm tint (keep quiet)

// --- Cursor activity --------------------------------------------------------
const float JUMP_DAMPING        = 0.22;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  WARM_AMBER          = vec3(1.00, 0.68, 0.32);
const vec3  WARM_EMBER          = vec3(1.00, 0.42, 0.14);
// ===========================================================================

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

float cursorJumpGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cells = length(cursorDelta);

    // One-cell movement is usually typing. Clicks and teleports stay cooler.
    float typedStep = smoothstep(0.10, 1.35, cells) * (1.0 - smoothstep(2.4, 8.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.10, cells);
    float localEvent = max(typedStep, stationaryEvent * 0.70);
    return mix(JUMP_DAMPING, 1.0, localEvent);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;

    // Single unwarped sample so glyphs stay crisp.
    vec4 color = texture(iChannel0, uv);

    float t = iTime;
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

    float recency = exp(-age / max(RECENCY_TAU, 0.0001));
    float heat = activity * cursorJumpGain() * (1.0 + RECENCY_BOOST * recency);

    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float distSq = dot(p, p);
    float radiusSq = max(HEAT_RADIUS * HEAT_RADIUS, 0.0000001);
    float localMask = exp(-distSq / radiusSq);
    float core = exp(-distSq / (radiusSq * 0.18));
    float warmth = localMask * (1.0 + HEAT_CORE * core);

    vec3 heatColor = mix(WARM_AMBER, WARM_EMBER, recency);
    float amount = clamp(HEAT_STRENGTH * heat * warmth, 0.0, 1.0);

    // Quiet multiply tint: warms midtones without displacing the terminal image.
    color.rgb = mix(color.rgb, color.rgb * mix(vec3(1.0), heatColor, 0.55), amount);

    fragColor = vec4(color.rgb, color.a);
}
