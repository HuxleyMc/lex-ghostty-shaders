// Ink Bloom — a Ghostty custom shader: cursor-triggered expanding color bloom.
//
// Each cursor change emits one soft radial ink bloom centered on the cursor.
// The shader is stateless ShaderToy-style: every frame is rebuilt from iTime,
// iTimeCursorChange, iCurrentCursor, iPreviousCursor, iResolution, iChannel0,
// and pure math. Fast typing keeps restarting the bloom near the cursor; idle
// terminals fade back to the unmodified terminal image.
//
// Large cursor jumps are damped through iPreviousCursor so mouse clicks,
// teleports, and selection jumps produce a quieter bloom than local typing.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Bloom envelope ---------------------------------------------------------
const float BLOOM_LIFE      = 1.25;  // seconds before the ink bloom disappears
const float BLOOM_RADIUS    = 0.34;  // final radius in height-normalized UV
const float INK_INTENSITY   = 0.38;  // color and light added by the bloom
const float EDGE_SOFTNESS   = 0.18;  // softness of the expanding outer edge

// --- Cursor activity --------------------------------------------------------
const float COLOR_SHIFT     = 0.48;  // palette variation between blue and magenta
const float JUMP_DAMPING    = 0.30;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  INK_BLUE        = vec3(0.08, 0.48, 1.00);
const vec3  INK_MAGENTA     = vec3(0.85, 0.18, 0.78);
const vec3  INK_CYAN        = vec3(0.18, 0.95, 1.00);
// ===========================================================================

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    float life = max(1.0 - age / BLOOM_LIFE, 0.0);
    return life * life * eventSeen;
}

float cursorJumpGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cells = length(cursorDelta);

    float typedStep = smoothstep(0.12, 1.20, cells) * (1.0 - smoothstep(2.2, 7.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.12, cells);
    float localEvent = max(typedStep, stationaryEvent * 0.72);
    return mix(JUMP_DAMPING, 1.0, localEvent);
}

float bloomMask(float dist, float age) {
    float lifeT = clamp(age / BLOOM_LIFE, 0.0, 1.0);
    float radius = BLOOM_RADIUS * (0.08 + 0.92 * smoothstep(0.0, 1.0, lifeT));
    float edgeWidth = max(radius * EDGE_SOFTNESS, 0.004);

    float disk = 1.0 - smoothstep(radius - edgeWidth, radius + edgeWidth, dist);
    float rim = exp(-pow((dist - radius) / edgeWidth, 2.0));
    float centerFade = exp(-dist * 8.0) * (1.0 - smoothstep(0.0, 0.48, lifeT));
    return max(disk * 0.45, rim) + centerFade * 0.55;
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

    vec4 color = texture(iChannel0, uv);

    float activity = activityAmount(t);
    float jumpGain = cursorJumpGain();
    float burst = activity * jumpGain;

    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float dist = length(p);
    float ink = bloomMask(dist, age) * burst;

    float seed = hash12(iCurrentCursor.xy + iPreviousCursor.yx + iTimeCursorChange);
    float shift = clamp(COLOR_SHIFT + (seed - 0.5) * 0.30, 0.0, 1.0);
    vec3 inkColor = mix(INK_BLUE, INK_MAGENTA, shift);
    inkColor = mix(inkColor, INK_CYAN, smoothstep(0.0, 0.18, dist) * 0.32);

    float darkInk = ink * 0.055;
    color.rgb *= 1.0 - darkInk;
    color.rgb += inkColor * ink * INK_INTENSITY;

    fragColor = vec4(color.rgb, color.a);
}
