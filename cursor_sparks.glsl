// Cursor Sparks — a Ghostty custom shader: electric-blue lightning at the cursor.
//
// Adds a compact cursor-centered glow, soft blue halo, and short jagged
// lightning bolts over the terminal. The effect is stateless ShaderToy-style:
// each frame is rebuilt from iTime, iTimeCursorChange, the cursor uniforms,
// iResolution, iChannel0, and pure math. Each cursor change restarts one
// lightning burst; fast typing keeps the burst visibly active, and idle
// terminals fade back to the unmodified terminal image.
//
// Large cursor jumps are damped through iPreviousCursor so mouse clicks,
// teleports, and selection jumps do not create oversized flashes.
//
// This shader is original procedural code and uses no upstream shader source,
// external textures, feedback buffers, preprocessing, or generated data.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Activity envelope ------------------------------------------------------
const float ACTIVITY_LIFE       = 0.95;  // seconds before a burst fades out
const float ACTIVITY_FADE_POWER = 1.65;  // higher = sharper fade near the end

// --- Glow ------------------------------------------------------------------
const float GLOW_RADIUS         = 0.105; // halo radius in height-normalized UV
const float CORE_INTENSITY      = 0.34;  // compact light at the cursor center
const float HALO_INTENSITY      = 0.18;  // soft radial cursor halo

// --- Lightning -------------------------------------------------------------
const float LIGHTNING_INTENSITY = 0.58;  // brightness of jagged bolt cores
const float BOLT_SPEED          = 0.18;  // slight outward crawl after a strike
const float BOLT_WIDTH          = 0.0022;// core stroke width in height-normalized UV
const float BOLT_JAGGEDNESS     = 0.30;  // sideways kink amount along each bolt
const float BRANCH_INTENSITY    = 0.55;  // side-branch brightness vs. main bolts
const float FLICKER_INTENSITY   = 0.42;  // per-frame lightning flicker strength
const int   BOLT_COUNT          = 10;    // number of procedural bolt directions
const int   BOLT_SEGMENTS       = 5;     // kinks per bolt

// --- Color -----------------------------------------------------------------
const vec3  ELECTRIC_CORE       = vec3(0.72, 0.94, 1.00);
const vec3  ELECTRIC_BLUE       = vec3(0.10, 0.54, 1.00);
const vec3  ELECTRIC_VIOLET     = vec3(0.40, 0.28, 1.00);
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

float activityAmount(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

float cursorStepGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 cursorDelta = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cellsSq = dot(cursorDelta, cursorDelta);

    // One-cell movement is usually typing. Big jumps still glow, but softly.
    float typedStep = smoothstep(0.12, 1.56, cellsSq) * (1.0 - smoothstep(3.24, 36.0, cellsSq));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.12, cellsSq);
    float localEvent = max(typedStep, stationaryEvent * 0.72);
    return mix(0.28, 1.0, localEvent);
}

float segmentDistanceSq(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
    vec2 d = pa - ba * h;
    return dot(d, d);
}

vec2 strokeLight(float distSq, float width, float tipFade) {
    float invWidthSq = 1.0 / max(width * width, 0.0000001);
    float core = exp(-distSq * invWidthSq) * tipFade;
    float glow = exp(-distSq * invWidthSq * 0.04) * tipFade;
    return vec2(core, glow);
}

vec2 jaggedBolt(vec2 p, vec2 origin, vec2 dir, vec2 normal, float start, float len, float seed, float width, float jaggedness) {
    vec2 light = vec2(0.0);

    for (int j = 0; j < BOLT_SEGMENTS; j++) {
        float a = float(j) / float(BOLT_SEGMENTS);
        float b = float(j + 1) / float(BOLT_SEGMENTS);

        float kinkA = (hash11(seed + a * 113.7) * 2.0 - 1.0) * jaggedness * len * sin(a * PI);
        float kinkB = (hash11(seed + b * 113.7) * 2.0 - 1.0) * jaggedness * len * sin(b * PI);

        vec2 pa = origin + dir * (start + len * a) + normal * kinkA;
        vec2 pb = origin + dir * (start + len * b) + normal * kinkB;

        float distSq = segmentDistanceSq(p, pa, pb);
        float tipFade = mix(1.0, 0.48, b);
        light = max(light, strokeLight(distSq, width, tipFade));
    }

    return light;
}

vec2 lightningBranch(vec2 p, vec2 origin, vec2 dir, vec2 normal, float len, float seed, float width, float jaggedness) {
    float kink = (hash11(seed + 43.7) * 2.0 - 1.0) * jaggedness * len;
    vec2 mid = origin + dir * (len * 0.52) + normal * kink;
    vec2 end = origin + dir * len;

    vec2 first = strokeLight(segmentDistanceSq(p, origin, mid), width, 0.80);
    vec2 second = strokeLight(segmentDistanceSq(p, mid, end), width, 0.48);
    return max(first, second);
}

vec2 lightningField(vec2 p, float age, float seed, float jumpGain) {
    vec2 light = vec2(0.0);

    for (int i = 0; i < BOLT_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 17.13);
        float h1 = hash11(seed + fi * 31.71 + 5.0);
        float h2 = hash11(seed + fi * 47.29 + 11.0);
        float h3 = hash11(seed + fi * 61.83 + 19.0);
        float h4 = hash11(seed + fi * 79.51 + 23.0);

        float angle = h0 * TAU + (h4 - 0.5) * 0.36;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 normal = vec2(-dir.y, dir.x);

        float rayDelay = h1 * 0.12;
        float localAge = max(age - rayDelay, 0.0);
        float rayLife = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.38, 0.82, h3)), 0.0);
        float strikeIn = smoothstep(0.0, 0.075, localAge);
        float strike = strikeIn * rayLife;
        float selected = step(0.22, h3);

        float start = 0.007 + localAge * BOLT_SPEED * mix(0.4, 1.0, h2);
        float len = mix(0.052, 0.145, h1) * strike;
        float width = BOLT_WIDTH * mix(0.70, 1.28, h2);
        vec2 mainBolt = jaggedBolt(p, vec2(0.0), dir, normal, start, len, seed + fi * 101.3, width, BOLT_JAGGEDNESS);

        float branchT = mix(0.35, 0.72, h4);
        float branchSign = mix(-1.0, 1.0, step(0.5, h2));
        float branchOffset = branchSign * mix(0.48, 1.02, h0);
        float branchCos = cos(branchOffset);
        float branchSin = sin(branchOffset);
        vec2 branchDir = dir * branchCos + normal * branchSin;
        vec2 branchNormal = vec2(-branchDir.y, branchDir.x);
        float branchLen = len * mix(0.22, 0.46, h3);
        float branchKink = (h2 * 2.0 - 1.0) * BOLT_JAGGEDNESS * len * sin(branchT * PI);
        vec2 branchOrigin = dir * (start + len * branchT) + normal * branchKink;
        vec2 branchBolt = lightningBranch(p, branchOrigin, branchDir, branchNormal, branchLen, seed + fi * 211.9, width * 0.78, BOLT_JAGGEDNESS * 1.25);

        light = max(light, (mainBolt + branchBolt * BRANCH_INTENSITY) * selected * mix(0.55, 1.0, h0));
    }

    return min(light * jumpGain, vec2(2.0));
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
    float jumpGain = cursorStepGain();
    float burst = activity * jumpGain;

    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    // Cursor cell footprint keeps the core compact and tied to Ghostty's cursor
    // dimensions instead of scaling only with viewport size.
    vec2 cursorSize = vec2(max(iCurrentCursor.z / res.x * aspect, 0.0025), max(iCurrentCursor.w / res.y, 0.004));
    vec2 cellD = abs(p) / cursorSize;
    float core = exp(-dot(cellD, cellD) * 0.82) * CORE_INTENSITY;
    float halo = exp(-dot(p, p) / max(GLOW_RADIUS * GLOW_RADIUS, 0.0000001)) * HALO_INTENSITY;

    float seed = iTimeCursorChange * 41.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 97.0;
    vec2 lightning = lightningField(p, age, seed, jumpGain) * LIGHTNING_INTENSITY;
    float flicker = mix(1.0 - FLICKER_INTENSITY, 1.0 + FLICKER_INTENSITY, hash11(seed + floor(t * 52.0)));

    vec3 glowColor = mix(ELECTRIC_BLUE, ELECTRIC_CORE, clamp(core * 3.2, 0.0, 1.0));
    vec3 boltGlowColor = mix(ELECTRIC_BLUE, ELECTRIC_VIOLET, 0.28 + 0.22 * sin(seed));

    color.rgb += glowColor * (core + halo) * burst;
    color.rgb += ELECTRIC_CORE * lightning.x * activity * flicker;
    color.rgb += boltGlowColor * lightning.y * activity * flicker * 0.55;

    fragColor = vec4(color.rgb, color.a);
}
