// Signal Pulse - a Ghostty custom shader: cursor-triggered horizontal pulses.
//
// Cursor changes emit subtle scanline/radar pulses centered on the cursor row.
// The effect is mostly full-width, but it is activity-gated and quickly fades
// back to the unmodified terminal image. The shader is stateless ShaderToy-style:
// every frame is rebuilt from iTime, iTimeCursorChange, iCurrentCursor,
// iPreviousCursor, iResolution, iChannel0, and pure math.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 1.10;  // seconds before pulses fade out
const float ACTIVITY_FADE_POWER = 1.55;  // higher = sharper fade near the end

// --- Pulse geometry ---------------------------------------------------------
const float PULSE_SPEED         = 0.42;  // vertical travel speed in UV units/sec
const float PULSE_WIDTH         = 0.010; // thickness of bright pulse bands
const float PULSE_SPACING       = 0.105; // distance between secondary echoes
const float CENTER_GLOW_HEIGHT  = 0.060; // soft cursor-row glow height

// --- Scanlines --------------------------------------------------------------
const float SCANLINE_SCALE      = 820.0; // horizontal line frequency
const float SCANLINE_STRENGTH   = 0.085; // strength while activity is visible
const float RADAR_DASH_SCALE    = 38.0;  // segmented dash frequency across width

// --- Intensity --------------------------------------------------------------
const float PULSE_INTENSITY     = 0.28;  // brightness of traveling pulses
const float CENTER_INTENSITY    = 0.14;  // brightness near the cursor row
const float TINT_STRENGTH       = 0.08;  // subtle activity-time signal tint

// --- Color -----------------------------------------------------------------
const vec3  SIGNAL_CYAN         = vec3(0.22, 0.92, 1.00);
const vec3  SIGNAL_GREEN        = vec3(0.35, 1.00, 0.70);
// ===========================================================================

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

float cursorStepGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cells = length(cursorDelta);

    float typedStep = smoothstep(0.10, 1.40, cells) * (1.0 - smoothstep(2.7, 9.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.10, cells);
    float localEvent = max(typedStep, stationaryEvent * 0.70);
    return mix(0.38, 1.0, localEvent);
}

float pulseBand(float dy, float radius, float width) {
    return exp(-pow((abs(dy) - radius) / max(width, 0.0001), 2.0));
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

    float age = max(t - iTimeCursorChange, 0.0);
    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );

    float eventGain = activity * cursorStepGain();
    float dy = uv.y - cursorCenter.y;

    float radius = age * PULSE_SPEED;
    float pulse = pulseBand(dy, radius, PULSE_WIDTH);
    pulse += pulseBand(dy, radius - PULSE_SPACING, PULSE_WIDTH * 0.82) * 0.48 * step(PULSE_SPACING, radius);
    pulse += pulseBand(dy, radius - PULSE_SPACING * 2.0, PULSE_WIDTH * 0.72) * 0.24 * step(PULSE_SPACING * 2.0, radius);

    float dashPhase = floor(uv.x * RADAR_DASH_SCALE) + floor(t * 16.0) + iTimeCursorChange * 7.0;
    float dash = mix(0.55, 1.0, step(0.32, hash11(dashPhase)));
    float scan = 0.5 + 0.5 * sin((fragCoord.y + floor(t * 18.0)) * SCANLINE_SCALE / max(res.y, 1.0));
    float centerGlow = exp(-dy * dy / max(CENTER_GLOW_HEIGHT * CENTER_GLOW_HEIGHT, 0.000001));
    float pulseEnvelope = clamp(pulse + centerGlow * 0.35, 0.0, 1.0);

    vec3 pulseColor = mix(SIGNAL_CYAN, SIGNAL_GREEN, 0.28 + 0.22 * sin(iTimeCursorChange * 3.1));
    float scanWeight = mix(0.32, 1.0, pulseEnvelope);
    float scanShade = 1.0 - scan * SCANLINE_STRENGTH * eventGain * scanWeight;
    color.rgb *= scanShade;
    color.rgb += pulseColor * pulse * dash * PULSE_INTENSITY * eventGain;
    color.rgb += pulseColor * centerGlow * CENTER_INTENSITY * eventGain;
    color.rgb = mix(color.rgb, color.rgb * (vec3(1.0) + pulseColor * 0.18), TINT_STRENGTH * eventGain);

    fragColor = vec4(color.rgb, color.a);
}
