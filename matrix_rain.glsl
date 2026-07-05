// Matrix Rain — a Ghostty custom shader: subtle falling code overlay.
//
// Matrix-inspired terminal rain, written as original procedural shader code.
// It is not derived from upstream Matrix/rain shaders and uses no external
// textures, font assets, feedback buffers, preprocessing, or generated data.
//
// Ghostty custom shaders are stateless ShaderToy-style fragment shaders: every
// frame is rebuilt from iTime, iResolution, iChannel0, and pure math. This file
// models sparse vertical streams on a coarse grid, then draws glyph-like
// rectangular fragments inside each active cell. The effect wakes after cursor
// changes such as typing, then fades away while the terminal is idle.
//
// All values below are tunable — see TUNING.

// ============================ TUNING =======================================
// --- Rain layout ------------------------------------------------------------
const float RAIN_DENSITY        = 0.72;  // fraction of columns with active rain
const float FALL_SPEED          = 0.38;  // base downward stream speed
const float GLYPH_SCALE         = 28.0;  // rows across the viewport height

// --- Visibility -------------------------------------------------------------
const float DARKEN_STRENGTH    = 0.12;  // overall darkening before rain is added
const float GLOW_INTENSITY      = 0.55;  // brightness added by rain fragments
const float TRAIL_FADE          = 0.14;  // higher = shorter/dimmer trails
const float GREEN_TINT_STRENGTH = 0.075; // low constant terminal tint

// --- Typing activity --------------------------------------------------------
const float ACTIVITY_LIFE       = 4.2;   // seconds before the whole effect fades out
const float ACTIVITY_FADE_POWER = 1.4;   // higher = quicker fade near the end

// --- Color -----------------------------------------------------------------
const vec3  TINT_GREEN          = vec3(0.72, 1.05, 0.78);
const vec3  TRAIL_GREEN         = vec3(0.10, 0.68, 0.22);
const vec3  HEAD_GREEN          = vec3(0.72, 1.00, 0.74);
// ===========================================================================

const float TRAIL_ROWS = 13.0;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float rectMask(vec2 p, vec2 center, vec2 halfSize) {
    vec2 d = abs(p - center) - halfSize;
    float outside = length(max(d, vec2(0.0)));
    float inside = min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(0.0, 0.018, outside + inside);
}

float glyphFragments(vec2 cellUV, vec2 cellId) {
    float seed = hash12(cellId);
    float variant = floor(seed * 6.0);

    // Build small synthetic strokes rather than text. The variants stay stable
    // per grid cell and are only rectangular marks, so no font asset is needed.
    float g = 0.0;
    g = max(g, rectMask(cellUV, vec2(0.28, 0.30 + 0.16 * fract(seed * 7.1)), vec2(0.060, 0.26)));
    g = max(g, rectMask(cellUV, vec2(0.63, 0.58 - 0.18 * fract(seed * 5.3)), vec2(0.060, 0.24)));

    if (variant < 2.0) {
        g = max(g, rectMask(cellUV, vec2(0.48, 0.28), vec2(0.28, 0.055)));
        g = max(g, rectMask(cellUV, vec2(0.48, 0.70), vec2(0.24, 0.055)));
    } else if (variant < 4.0) {
        g = max(g, rectMask(cellUV, vec2(0.48, 0.48), vec2(0.28, 0.055)));
        g = max(g, rectMask(cellUV, vec2(0.72, 0.72), vec2(0.055, 0.15)));
    } else {
        g = max(g, rectMask(cellUV, vec2(0.40, 0.76), vec2(0.24, 0.055)));
        g = max(g, rectMask(cellUV, vec2(0.74, 0.32), vec2(0.055, 0.16)));
    }

    // Leave small breaks so the rain reads as fragmented glyphs, not solid bars.
    float cut = step(0.08, hash12(cellId + floor(cellUV * 3.0)));
    float inset = smoothstep(0.05, 0.18, cellUV.x)
                * (1.0 - smoothstep(0.82, 0.95, cellUV.x))
                * smoothstep(0.05, 0.18, cellUV.y)
                * (1.0 - smoothstep(0.82, 0.95, cellUV.y));
    return g * cut * inset;
}

vec2 rainField(vec2 uv, vec2 res, float t) {
    float aspect = res.x / res.y;
    vec2 grid = vec2(uv.x * aspect * GLYPH_SCALE, uv.y * GLYPH_SCALE);
    vec2 cellId = floor(grid);
    vec2 cellUV = fract(grid);

    float column = cellId.x;
    float row = cellId.y;
    float columnSeed = hash12(vec2(column, 17.0));
    float columnActive = step(1.0 - RAIN_DENSITY, columnSeed);

    float streamSpeed = FALL_SPEED * GLYPH_SCALE * mix(0.55, 1.45, hash12(vec2(column, 41.0)));
    float cycleRows = GLYPH_SCALE + TRAIL_ROWS;
    float headRow = mod(t * streamSpeed + columnSeed * cycleRows, cycleRows);
    float trailDistance = mod(headRow - row + cycleRows, cycleRows);

    float inTrail = 1.0 - smoothstep(TRAIL_ROWS - 0.6, TRAIL_ROWS + 0.6, trailDistance);
    float trail = exp(-trailDistance * TRAIL_FADE) * inTrail;
    float head = 1.0 - smoothstep(0.0, 1.2, trailDistance);

    // Stationary dark gaps and slow phase flicker keep the columns sparse.
    float gap = step(0.12, hash12(cellId + vec2(9.7, 3.1)));
    float flicker = mix(0.72, 1.0, hash12(cellId + vec2(floor(t * 4.0))));
    float glyph = glyphFragments(cellUV, cellId);

    float headAmount = columnActive * head * glyph * gap;
    float rainAmount = columnActive * (head * 1.35 + trail * 0.70) * glyph * gap * flicker;
    return vec2(rainAmount, headAmount);
}

float matrixActivity(float t) {
    float age = max(t - iTimeCursorChange, 0.0);
    float eventSeen = step(0.0001, iTimeCursorChange);
    return pow(max(1.0 - age / ACTIVITY_LIFE, 0.0), ACTIVITY_FADE_POWER) * eventSeen;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;

    vec4 color = texture(iChannel0, uv);
    float activity = matrixActivity(iTime);
    if (activity <= 0.0001) {
        fragColor = color;
        return;
    }

    color.rgb *= 1.0 - DARKEN_STRENGTH * activity;

    // Subtle activity-gated green cast, kept separate from the falling glyph
    // light so terminal colors return to normal after the fade.
    color.rgb = mix(color.rgb, color.rgb * TINT_GREEN, GREEN_TINT_STRENGTH * activity);

    vec2 rainSample = rainField(uv, res, iTime);
    float rain = rainSample.x;
    float headAmount = rainSample.y;
    vec3 rainColor = mix(TRAIL_GREEN, HEAD_GREEN, clamp(headAmount * 1.4, 0.0, 1.0));
    color.rgb += rainColor * rain * GLOW_INTENSITY * activity;

    fragColor = vec4(color.rgb, color.a);
}
