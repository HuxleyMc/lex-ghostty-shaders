// Anime Speed Lines — a Ghostty custom shader: manga power-up burst at the cursor.
//
// Each cursor change triggers a classic shonen action-scene treatment: sharp
// speed lines radiate outward from the cursor, a brief white flash pops at the
// focus point, and the screen edges darken slightly like a manga dramatic
// vignette. The effect is stateless ShaderToy-style: every frame is rebuilt
// from iTime, iTimeCursorChange, iCurrentCursor, iPreviousCursor, iResolution,
// iChannel0, and pure math. Fast typing keeps the burst alive, while idle
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
const float ACTIVITY_LIFE       = 1.60;  // seconds before the burst fades out
const float ACTIVITY_FADE_POWER = 1.40;  // higher = sharper fade near the end

// --- Speed lines -------------------------------------------------------------
const int   RAY_COUNT           = 26;    // number of angular ray sectors
const float RAY_ACTIVE_FRACTION = 0.78;  // fraction of sectors that emit a line
const float RAY_MAX_LENGTH      = 0.55;  // max ray length in height-normalized UV
const float RAY_GROWTH_SPEED    = 0.90;  // outward ray growth speed (units/sec)
const float RAY_MIN_WIDTH       = 0.004; // thinnest angular half-width (radians)
const float RAY_MAX_WIDTH       = 0.016; // widest angular half-width (radians)
const float RAY_INTENSITY       = 0.42;  // brightness of the speed lines
const float RAY_TIP_BOOST       = 0.55;  // extra glow at the growing ray tips
const float RAY_INNER_GAP       = 0.035; // clear radius around the cursor glyph

// --- Flash -------------------------------------------------------------------
const float FLASH_RADIUS        = 0.085; // radius of the cursor flash
const float FLASH_INTENSITY     = 0.30;  // brightness of the cursor flash
const float FLASH_LIFE          = 0.22;  // seconds before the flash dies out

// --- Dramatic vignette ---------------------------------------------------------
const float VIGNETTE_STRENGTH   = 0.10;  // edge darkening while the burst is live

// --- Color -----------------------------------------------------------------
const vec3  LINE_COLOR          = vec3(0.86, 0.93, 1.00); // cool white lines
const vec3  FLASH_COLOR         = vec3(1.00, 0.98, 0.92); // warm white flash
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

    // One-cell movement is usually typing. Big jumps still decorate, but softly.
    float typedStep = smoothstep(0.12, 1.56, cellsSq) * (1.0 - smoothstep(3.24, 36.0, cellsSq));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.12, cellsSq);
    float localEvent = max(typedStep, stationaryEvent * 0.72);
    return mix(0.24, 1.0, localEvent);
}

// Sum of all speed-line streaks (plus tip glows) at point p, in
// aspect-corrected cursor-relative coordinates.
float speedLineField(vec2 p, float age, float seed, float jumpGain) {
    float dist = length(p);
    float u = atan(p.y, p.x) / TAU + 0.5; // angular position, 0..1 around cursor

    float total = 0.0;
    for (int i = 0; i < RAY_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 17.13 + 1.0);
        float h1 = hash11(seed + fi * 29.71 + 4.0);
        float h2 = hash11(seed + fi * 41.37 + 9.0);
        float h3 = hash11(seed + fi * 53.93 + 2.0);

        // Only a fraction of sectors emit a line, so the burst looks hand-drawn
        // instead of like a perfect sunburst.
        if (h3 > RAY_ACTIVE_FRACTION) continue;

        // Angular line mask: constant angular width, so lines taper toward the
        // focus point like real manga speed lines.
        float rayCenter = (fi + 0.5 + (h0 - 0.5) * 0.9) / float(RAY_COUNT);
        float du = u - rayCenter;
        du -= floor(du + 0.5); // wrap to [-0.5, 0.5)
        float angular = du * TAU;
        float halfWidth = mix(RAY_MIN_WIDTH, RAY_MAX_WIDTH, h2);
        float lineMask = 1.0 - smoothstep(halfWidth * 0.55, halfWidth, abs(angular));

        // Per-ray timing: staggered starts, varied lifespans, outward growth.
        float localAge = max(age - h1 * 0.22, 0.0);
        float life = max(1.0 - localAge / (ACTIVITY_LIFE * mix(0.55, 1.00, h2)), 0.0);
        float appear = smoothstep(0.0, 0.05, localAge);
        float len = min(RAY_INNER_GAP + RAY_GROWTH_SPEED * localAge * mix(0.55, 1.25, h0),
                        RAY_MAX_LENGTH);

        // Radial mask: lines start a little away from the cursor and soften
        // near their current tip.
        float radial = smoothstep(RAY_INNER_GAP, RAY_INNER_GAP + 0.03, dist)
                     * (1.0 - smoothstep(len * 0.72, len, dist));

        // Energy flicker keeps the lines feeling alive while the burst is up.
        float flicker = 0.72 + 0.28 * sin(iTime * mix(14.0, 26.0, h1) + h0 * TAU);

        float m = lineMask * radial * appear * life * flicker * jumpGain;
        total += m;

        // Bright traveling tip where the line is currently growing to.
        float tipSigma = max(halfWidth * dist + 0.006, 0.004);
        float tip = exp(-pow((dist - len) / tipSigma, 2.0))
                  * (1.0 - smoothstep(halfWidth, halfWidth * 2.2, abs(angular)));
        total += tip * appear * life * RAY_TIP_BOOST * jumpGain;
    }
    return total;
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

    float aspect = res.x / res.y;
    float age = max(t - iTimeCursorChange, 0.0);
    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );

    float jumpGain = cursorStepGain();
    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float distSq = dot(p, p);

    float seed = iTimeCursorChange * 61.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 137.0;

    // Keep the effect additive and activity-gated so idle terminals return to
    // their original colors without a permanent wash.
    float field = speedLineField(p, age, seed, jumpGain);
    color.rgb += LINE_COLOR * field * RAY_INTENSITY * activity;

    // Brief focus-point flash, decaying much faster than the lines.
    float flashDecay = pow(max(1.0 - age / FLASH_LIFE, 0.0), 2.0);
    float flash = exp(-distSq / max(FLASH_RADIUS * FLASH_RADIUS, 0.0000001))
                * flashDecay * FLASH_INTENSITY * jumpGain;
    color.rgb += FLASH_COLOR * flash;

    // Manga dramatic vignette: slight edge darkening while the burst is live.
    float vignette = smoothstep(0.45, 0.75, length(uv - 0.5));
    color.rgb *= 1.0 - VIGNETTE_STRENGTH * vignette * activity;

    fragColor = vec4(color.rgb, color.a);
}
