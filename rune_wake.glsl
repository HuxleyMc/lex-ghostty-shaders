// Rune Wake - a Ghostty custom shader: brief glyph fragments near the cursor.
//
// Each cursor change releases small procedural arcane marks around the cursor:
// short strokes, rings, and ticks that drift outward and dissipate. The shader
// is stateless ShaderToy-style: every frame is rebuilt from iTime,
// iTimeCursorChange, iCurrentCursor, iPreviousCursor, iResolution, iChannel0,
// and pure math.
//
// Large cursor jumps are damped so mouse clicks, selection jumps, and pane
// changes do not cover the terminal with oversized marks.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 1.15;  // seconds before runes dissipate
const float ACTIVITY_FADE_POWER = 1.65;  // higher = sharper fade near the end

// --- Rune shape -------------------------------------------------------------
const float RUNE_RADIUS         = 0.125; // radius of the cursor-local wake
const float STROKE_WIDTH        = 0.0027;// line width of rune fragments
const float ARC_WIDTH           = 0.0036;// ring/arc line width
const int   RUNE_COUNT          = 9;     // number of procedural fragments

// --- Intensity --------------------------------------------------------------
const float RUNE_INTENSITY      = 0.46;  // brightness of glyph fragments
const float HALO_INTENSITY      = 0.10;  // faint glow behind marks

// --- Cursor activity --------------------------------------------------------
const float JUMP_DAMPING        = 0.26;  // gain used for large cursor jumps

// --- Color -----------------------------------------------------------------
const vec3  RUNE_CYAN           = vec3(0.30, 0.92, 1.00);
const vec3  RUNE_VIOLET         = vec3(0.62, 0.42, 1.00);
const vec3  RUNE_AMBER          = vec3(1.00, 0.72, 0.34);
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

float cursorJumpGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cells = length(cursorDelta);

    float typedStep = smoothstep(0.10, 1.35, cells) * (1.0 - smoothstep(2.4, 8.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.10, cells);
    float localEvent = max(typedStep, stationaryEvent * 0.70);
    return mix(JUMP_DAMPING, 1.0, localEvent);
}

float segmentMask(vec2 p, vec2 a, vec2 b, float width) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
    vec2 d = pa - ba * h;
    return exp(-dot(d, d) / max(width * width, 0.0000001));
}

float arcMask(vec2 p, float radius, float width, float startAngle, float arcLen) {
    float dist = length(p);
    float ring = exp(-pow((dist - radius) / max(width, 0.0001), 2.0));
    float ang = atan(p.y, p.x);
    float wrapped = mod(ang - startAngle + PI, TAU) - PI;
    float gate = 1.0 - smoothstep(arcLen * 0.72, arcLen, abs(wrapped));
    return ring * gate;
}

float runeGlyph(vec2 p, float h0, float h1, float h2) {
    vec2 q = rotate2((h0 - 0.5) * 1.8) * p;
    float scale = mix(0.018, 0.032, h1);

    float mark = segmentMask(q, vec2(-scale * 0.70, 0.0), vec2(scale * 0.70, 0.0), STROKE_WIDTH);
    mark += segmentMask(q, vec2(0.0, -scale * 0.62), vec2(0.0, scale * 0.62), STROKE_WIDTH) * step(0.35, h2);
    mark += segmentMask(q, vec2(-scale * 0.42, scale * 0.42), vec2(scale * 0.48, -scale * 0.36), STROKE_WIDTH) * step(0.18, h1);
    mark += segmentMask(q, vec2(scale * 0.18, -scale * 0.68), vec2(scale * 0.58, -scale * 0.22), STROKE_WIDTH) * step(0.52, h0);
    mark += arcMask(q, scale * mix(0.68, 1.08, h2), ARC_WIDTH, h0 * TAU, mix(0.72, 1.35, h1)) * 0.78;

    return min(mark, 1.75);
}

vec3 runeField(vec2 p, float age, float seed, float jumpGain, out float alphaOut) {
    vec3 light = vec3(0.0);
    float alpha = 0.0;

    for (int i = 0; i < RUNE_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 17.19);
        float h1 = hash11(seed + fi * 29.51 + 3.0);
        float h2 = hash11(seed + fi * 43.87 + 7.0);
        float h3 = hash11(seed + fi * 61.23 + 11.0);

        float localAge = max(age - h2 * 0.18, 0.0);
        float life = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.55, 1.05, h1)), 0.0);
        float appear = smoothstep(0.0, 0.080, localAge);
        float angle = h0 * TAU;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 center = dir * (mix(0.020, RUNE_RADIUS, h1) + localAge * mix(0.010, 0.035, h3));
        center.y -= localAge * 0.012;

        vec2 q = p - center;
        float mark = runeGlyph(q, h0, h1, h2) * appear * life * jumpGain;
        vec3 runeColor = mix(mix(RUNE_CYAN, RUNE_VIOLET, h0), RUNE_AMBER, smoothstep(0.72, 1.0, h2) * 0.38);
        light += runeColor * mark;
        alpha = max(alpha, mark);
    }

    alphaOut = alpha;
    return light;
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
    float seed = iTimeCursorChange * 71.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 113.0;

    float runeAlpha = 0.0;
    vec3 runes = runeField(p, age, seed, jumpGain, runeAlpha);
    float halo = exp(-dot(p, p) / max(RUNE_RADIUS * RUNE_RADIUS * 1.2, 0.0000001));

    color.rgb += mix(RUNE_CYAN, RUNE_VIOLET, 0.45) * halo * HALO_INTENSITY * burst;
    color.rgb += runes * RUNE_INTENSITY * activity;
    color.rgb = mix(color.rgb, color.rgb * vec3(0.99, 1.01, 1.025), clamp(runeAlpha * activity * 0.045, 0.0, 0.055));

    fragColor = vec4(color.rgb, color.a);
}
