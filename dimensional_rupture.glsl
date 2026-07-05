// Dimensional Rupture - a Ghostty custom shader for maximal visual chaos.
//
// This is intentionally not a daily-use readability shader. It bends the
// terminal through neon plasma folds, radial rupture rings, chromatic tearing,
// scan glitches, and cursor-triggered shock bursts. The effect is still kept
// performance-conscious: fixed small loops, three terminal texture reads, no
// raymarching, no feedback buffers, no external textures, and no generated
// artifacts.
//
// Ghostty custom shaders are stateless ShaderToy-style programs. Cursor bursts
// are rebuilt each frame from iTimeCursorChange, iCurrentCursor, and
// iPreviousCursor; there is no persistent per-frame trail.
//
// This shader is original procedural code and uses no upstream shader source.
//
// All values below are tunable - see TUNING.

// ============================ TUNING =======================================
// --- Overall intensity ------------------------------------------------------
const float RUPTURE_INTENSITY = 0.82;  // strength of neon plasma and rings
const float WARP_STRENGTH     = 0.020; // screen-space distortion amount
const float CHROMA_SPLIT      = 0.006; // red/blue channel separation
const float VIGNETTE_POWER    = 0.65;  // edge darkening around the storm

// --- Plasma field -----------------------------------------------------------
const float PLASMA_SCALE      = 2.35;  // lower = larger folds
const float PLASMA_SPEED      = 0.42;  // animation speed of the color field
const float RING_DENSITY      = 34.0;  // number of radial shock bands
const float RING_SPEED        = 1.45;  // outward ring motion

// --- Glitch cuts ------------------------------------------------------------
const float GLITCH_AMOUNT     = 0.015; // horizontal tear strength
const float SCANLINE_STRENGTH = 0.15;  // thin horizontal line modulation
const int   GLITCH_BANDS      = 7;     // fixed-cost scan cuts

// --- Cursor burst -----------------------------------------------------------
const float BURST_LIFE        = 1.35;  // seconds after cursor movement
const float BURST_BOOST       = 1.35;  // extra chaos near the cursor
const float BURST_RADIUS      = 0.62;  // max cursor shock radius
const int   SHARD_COUNT       = 14;    // fixed-cost radial shards

// --- Palette ----------------------------------------------------------------
const vec3  HOT_MAGENTA       = vec3(1.00, 0.02, 0.74);
const vec3  ACID_CYAN         = vec3(0.00, 0.96, 1.00);
const vec3  TOXIC_GREEN       = vec3(0.30, 1.00, 0.08);
const vec3  SOLAR_YELLOW      = vec3(1.00, 0.82, 0.05);
const vec3  VOID_PURPLE       = vec3(0.30, 0.08, 1.00);
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

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.55;

    for (int i = 0; i < 4; i++) {
        sum += valueNoise(p) * amp;
        p = mat2(0.80, 0.60, -0.60, 0.80) * p * 2.03 + 17.17;
        amp *= 0.50;
    }

    return sum;
}

vec3 palette(float x) {
    x = fract(x);
    vec3 a = mix(HOT_MAGENTA, ACID_CYAN, smoothstep(0.00, 0.24, x));
    vec3 b = mix(ACID_CYAN, TOXIC_GREEN, smoothstep(0.24, 0.46, x));
    vec3 c = mix(TOXIC_GREEN, SOLAR_YELLOW, smoothstep(0.46, 0.68, x));
    vec3 d = mix(SOLAR_YELLOW, VOID_PURPLE, smoothstep(0.68, 0.86, x));
    vec3 e = mix(VOID_PURPLE, HOT_MAGENTA, smoothstep(0.86, 1.00, x));

    vec3 ab = mix(a, b, smoothstep(0.20, 0.30, x));
    vec3 cd = mix(c, d, smoothstep(0.64, 0.72, x));
    vec3 abcd = mix(ab, cd, smoothstep(0.42, 0.54, x));
    return mix(abcd, e, smoothstep(0.82, 0.90, x));
}

float cursorActivity(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    float fade = pow(max(1.0 - age / BURST_LIFE, 0.0), 1.55);
    return fade * eventSeen;
}

float cursorStepGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    vec2 deltaCells = (iCurrentCursor.xy - iPreviousCursor.xy) / cell;
    float cellsSq = dot(deltaCells, deltaCells);
    float localMove = 1.0 - smoothstep(8.0, 80.0, cellsSq);
    return mix(0.42, 1.0, localMove);
}

float ringField(float r, float t) {
    float phase = r * RING_DENSITY - t * RING_SPEED;
    float saw = abs(fract(phase) - 0.5) * 2.0;
    float ring = pow(1.0 - saw, 7.0);
    float broad = 0.5 + 0.5 * sin(r * 9.0 - t * 0.7);
    return ring * (0.45 + 0.55 * broad);
}

float plasmaField(vec2 p, float t) {
    float sum = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float a = fi * 1.71 + sin(t * 0.17 + fi);
        vec2 dir = vec2(cos(a), sin(a));
        float wave = sin(dot(p, dir) * (2.8 + fi * 0.72) + t * (0.65 + fi * 0.21));
        float fold = cos(length(p + dir * wave * 0.12) * (5.5 + fi) - t * 0.8);
        sum += wave * 0.42 + fold * 0.26;
    }

    return sum * 0.20 + fbm(p * 1.35 + t * 0.16);
}

float glitchCuts(vec2 uv, float t) {
    float offset = 0.0;

    for (int i = 0; i < GLITCH_BANDS; i++) {
        float fi = float(i);
        float base = hash11(fi * 41.7 + floor(t * 5.0));
        float y = fract(base + t * mix(0.05, 0.22, hash11(fi + 9.0)));
        float width = mix(0.006, 0.026, hash11(fi * 13.1 + 3.0));
        float band = 1.0 - smoothstep(0.0, width, abs(uv.y - y));
        float signValue = mix(-1.0, 1.0, step(0.5, hash11(fi * 71.3 + floor(t * 9.0))));
        offset += band * signValue * mix(0.25, 1.0, base);
    }

    return offset;
}

float shardField(vec2 p, float age, float seed) {
    float r = length(p);
    if (r <= 0.0001) {
        return 0.0;
    }

    vec2 n = p / r;
    float shards = 0.0;

    for (int i = 0; i < SHARD_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 19.71);
        float h1 = hash11(seed + fi * 43.23 + 7.0);
        float angle = h0 * TAU + sin(age * 2.0 + fi) * 0.18;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 normal = vec2(-dir.y, dir.x);

        float angular = exp(-abs(dot(n, normal)) * mix(48.0, 88.0, h1));
        float reach = mix(0.10, BURST_RADIUS, h1);
        float head = 1.0 - smoothstep(reach * 0.55, reach, r);
        float tail = smoothstep(0.012, 0.080, r);
        float flicker = mix(0.45, 1.35, hash11(seed + fi * 97.0 + floor(age * 34.0)));
        shards += angular * head * tail * flicker;
    }

    return min(shards, 2.4);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float aspect = res.x / res.y;
    float t = iTime;

    vec2 centered = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    vec2 stormP = centered * PLASMA_SCALE;

    float plasma = plasmaField(stormP, t * PLASMA_SPEED);
    float r = length(centered);
    float rings = ringField(r, t);

    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );
    vec2 cursorP = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float activity = cursorActivity(t) * cursorStepGain();
    float age = max(t - iTimeCursorChange, 0.0);
    float seed = iTimeCursorChange * 53.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 113.0;

    float shock = exp(-abs(length(cursorP) - age * 0.38) * 34.0) * activity;
    float shards = shardField(cursorP, age, seed) * activity;
    float cursorGlow = exp(-dot(cursorP, cursorP) / 0.018) * activity;

    float glitch = glitchCuts(uv, t) * GLITCH_AMOUNT;
    float noiseWarp = fbm(stormP * 1.25 + t * 0.18) - 0.5;
    vec2 swirl = vec2(
        sin(plasma * TAU + centered.y * 18.0 + t),
        cos(plasma * TAU - centered.x * 14.0 - t * 0.83)
    );
    float chaos = RUPTURE_INTENSITY * (0.38 + rings + shock * BURST_BOOST + shards * 0.35);
    vec2 warp = swirl * WARP_STRENGTH * chaos + vec2(glitch, noiseWarp * WARP_STRENGTH * 0.55);
    vec2 warpedUV = clamp(uv + warp, vec2(0.001), vec2(0.999));

    vec2 splitDir = normalize(centered + vec2(0.0001, 0.0007));
    vec2 split = splitDir * CHROMA_SPLIT * (0.45 + chaos);
    vec4 redSample = texture(iChannel0, clamp(warpedUV + split, vec2(0.001), vec2(0.999)));
    vec4 midSample = texture(iChannel0, warpedUV);
    vec4 blueSample = texture(iChannel0, clamp(warpedUV - split, vec2(0.001), vec2(0.999)));

    vec3 base = vec3(redSample.r, midSample.g, blueSample.b);
    float alpha = midSample.a;

    vec3 neon = palette(plasma * 0.55 + r * 0.85 - t * 0.08);
    vec3 shardColor = mix(SOLAR_YELLOW, ACID_CYAN, hash11(seed + floor(age * 18.0)));
    float scan = sin(fragCoord.y * PI) * 0.5 + 0.5;
    float scanMod = mix(1.0 - SCANLINE_STRENGTH, 1.0 + SCANLINE_STRENGTH, scan);
    float vignette = pow(1.0 - smoothstep(0.08, 0.86, r), VIGNETTE_POWER);

    vec3 storm = neon * (rings * 0.48 + abs(plasma - 0.45) * 0.38 + shock * 1.25);
    storm += shardColor * (shards * 0.52 + cursorGlow * 0.85);
    storm *= RUPTURE_INTENSITY;

    base = base * (0.70 + 0.30 * vignette) * scanMod;
    base += storm;
    base = mix(base, base.bgr, clamp(abs(glitch) * 26.0 + shock * 0.28, 0.0, 0.75));

    fragColor = vec4(max(base, vec3(0.0)), alpha);
}
