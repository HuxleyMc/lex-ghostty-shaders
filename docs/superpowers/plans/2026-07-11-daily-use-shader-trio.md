# Daily-Use Shader Trio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cloud Shadow, Cursor Fireflies, and Paper Grain as three legible, low-cost Ghostty shaders with matching documentation.

**Architecture:** Each effect is an independent ShaderToy-compatible fragment shader that samples the terminal once and applies bounded procedural math. Cloud Shadow provides slow ambient darkening, Cursor Fireflies uses Ghostty cursor-event uniforms for a nine-particle burst, and Paper Grain applies a static fragment-coordinate treatment.

**Tech Stack:** Ghostty custom-shader GLSL, ShaderToy `mainImage`, POSIX shell validation, Markdown documentation.

## Global Constraints

- Preserve `mainImage(out vec4 fragColor, in vec2 fragCoord)` and Ghostty-compatible uniforms.
- Preserve the terminal's original colors instead of replacing them with a fixed palette.
- Apply no text refraction or coordinate distortion by default.
- Keep each shader in one self-contained `.glsl` file with tuning constants near the top.
- Use no external textures, feedback buffers, preprocessing, or generated assets.
- Keep loops fixed and small, with one normal `iChannel0` sample per shader.
- Update the README shader table, installation command, and tuning documentation.

## File Map

- Create `cloud_shadow.glsl`: three-layer ambient cloud mask and terminal darkening.
- Create `cursor_fireflies.glsl`: activity envelope, jump damping, and nine cursor-local particles.
- Create `paper_grain.glsl`: static fine grain, fiber variation, warmth, contrast, and edge shading.
- Modify `README.md`: add the three shader rows, installation filenames, and tuning tables.

---

### Task 1: Cloud Shadow

**Files:**
- Create: `cloud_shadow.glsl`

**Interfaces:**
- Consumes: `iResolution`, `iTime`, `iChannel0`.
- Produces: Ghostty entry point `void mainImage(out vec4 fragColor, in vec2 fragCoord)`.

- [ ] **Step 1: Add the shader header and exact tuning surface**

Create `cloud_shadow.glsl` with the repository-style provenance comment and these constants:

```glsl
const float SHADOW_STRENGTH = 0.115;
const float PATTERN_SCALE   = 1.65;
const float DRIFT_SPEED     = 0.018;
const float SHADOW_SOFTNESS = 0.34;
const vec3  LAYER_WEIGHT    = vec3(0.58, 0.28, 0.14);
```

The header must state that the shader is original procedural code, uses three noise layers, samples no external textures, and does not distort terminal coordinates.

- [ ] **Step 2: Implement deterministic value noise**

Add these helpers below the tuning block:

```glsl
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
```

- [ ] **Step 3: Implement the fixed three-layer shadow field and output**

Use three explicit calls rather than a variable loop:

```glsl
float cloudField(vec2 p, float t) {
    float a = valueNoise(p * 1.00 + vec2( t * DRIFT_SPEED,        t * DRIFT_SPEED * 0.31));
    float b = valueNoise(p * 1.91 + vec2(-t * DRIFT_SPEED * 0.47, t * DRIFT_SPEED * 0.23));
    float c = valueNoise(p * 3.73 + vec2( t * DRIFT_SPEED * 0.19,-t * DRIFT_SPEED * 0.29));
    return dot(vec3(a, b, c), LAYER_WEIGHT);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec2 p = vec2(uv.x * res.x / res.y, uv.y) * PATTERN_SCALE;
    vec4 color = texture(iChannel0, uv);
    float field = cloudField(p, iTime);
    float shadow = smoothstep(0.50 - SHADOW_SOFTNESS, 0.50 + SHADOW_SOFTNESS, field);
    color.rgb *= 1.0 - shadow * SHADOW_STRENGTH;
    fragColor = color;
}
```

- [ ] **Step 4: Run static and Ghostty config validation**

Run:

```sh
git diff --no-index --check /dev/null cloud_shadow.glsl
tmp_config=$(mktemp)
printf '%s\n' "custom-shader = $PWD/cloud_shadow.glsl" > "$tmp_config"
/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config --config-file="$tmp_config"
rc=$?
rm -f "$tmp_config"
exit "$rc"
```

Expected: both commands exit `0`. If the Ghostty binary is absent, record config validation as unavailable and continue with the whitespace check.

- [ ] **Step 5: Commit Cloud Shadow**

```sh
git add cloud_shadow.glsl
git commit -m "feat: add cloud shadow shader"
```

---

### Task 2: Cursor Fireflies

**Files:**
- Create: `cursor_fireflies.glsl`

**Interfaces:**
- Consumes: `iResolution`, `iTime`, `iTimeCursorChange`, `iCurrentCursor`, `iPreviousCursor`, `iChannel0`.
- Produces: Ghostty entry point `void mainImage(out vec4 fragColor, in vec2 fragCoord)`.

- [ ] **Step 1: Add the shader header and exact tuning surface**

Create `cursor_fireflies.glsl` with:

```glsl
const float ACTIVITY_LIFE       = 1.50;
const float ACTIVITY_FADE_POWER = 1.70;
const float BURST_RADIUS        = 0.105;
const float UPWARD_DRIFT        = 0.060;
const float CORE_SIZE           = 0.0032;
const float HALO_SIZE           = 0.0130;
const float GLOW_INTENSITY      = 0.34;
const float JUMP_DAMPING        = 0.25;
const int   FIREFLY_COUNT       = 9;
const vec3  AMBER_FIREFLY       = vec3(1.00, 0.72, 0.22);
const vec3  GREEN_FIREFLY       = vec3(0.72, 1.00, 0.48);
```

The header must describe the 1.5-second activity envelope, complete idle transparency, large-jump damping, and fixed nine-particle budget.

- [ ] **Step 2: Add hashing, activity, and jump damping helpers**

```glsl
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

float cursorJumpGain() {
    float cell = max(iCurrentCursor.z, 1.0);
    float cells = length((iCurrentCursor.xy - iPreviousCursor.xy) / cell);
    float typedStep = smoothstep(0.10, 1.35, cells) * (1.0 - smoothstep(2.4, 8.0, cells));
    float stationaryEvent = 1.0 - smoothstep(0.0, 0.10, cells);
    return mix(JUMP_DAMPING, 1.0, max(typedStep, stationaryEvent * 0.70));
}
```

- [ ] **Step 3: Implement the nine-particle light field**

```glsl
vec3 fireflyField(vec2 p, float age, float seed) {
    vec3 light = vec3(0.0);
    for (int i = 0; i < FIREFLY_COUNT; i++) {
        float fi = float(i);
        float h0 = hash11(seed + fi * 17.13);
        float h1 = hash11(seed + fi * 31.71 + 5.0);
        float h2 = hash11(seed + fi * 47.29 + 11.0);
        float h3 = hash11(seed + fi * 61.83 + 19.0);
        float delay = h1 * 0.20;
        float localAge = max(age - delay, 0.0);
        float born = step(delay, age);
        float life = max(1.0 - localAge / max(ACTIVITY_LIFE - delay, 0.01), 0.0);
        float angle = h0 * TAU;
        vec2 dir = vec2(cos(angle), sin(angle) * 0.58 - 0.42);
        float speed = mix(0.35, 1.0, h2);
        vec2 center = dir * BURST_RADIUS * speed * localAge / ACTIVITY_LIFE;
        center.y -= UPWARD_DRIFT * localAge * mix(0.55, 1.15, h3);
        vec2 d = p - center;
        float flicker = 0.72 + 0.28 * sin(iTime * mix(7.0, 13.0, h2) + h3 * TAU);
        float core = exp(-dot(d, d) / (CORE_SIZE * CORE_SIZE));
        float halo = exp(-dot(d, d) / (HALO_SIZE * HALO_SIZE)) * 0.26;
        vec3 tint = mix(AMBER_FIREFLY, GREEN_FIREFLY, step(0.67, h3));
        light += tint * (core + halo) * born * life * life * flicker;
    }
    return light;
}
```

- [ ] **Step 4: Implement the exact-idle fast path and final output**

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec4 color = texture(iChannel0, uv);
    float activity = activityAmount(iTime);
    if (activity <= 0.0001) {
        fragColor = color;
        return;
    }
    float aspect = res.x / res.y;
    float age = max(iTime - iTimeCursorChange, 0.0);
    vec2 cursorCenter = vec2(
        (iCurrentCursor.x + iCurrentCursor.z * 0.5) / res.x,
        (iCurrentCursor.y - iCurrentCursor.w * 0.5) / res.y
    );
    vec2 p = vec2((uv.x - cursorCenter.x) * aspect, uv.y - cursorCenter.y);
    float seed = iTimeCursorChange * 41.0 + hash12(iCurrentCursor.xy + iPreviousCursor.yx) * 97.0;
    color.rgb += fireflyField(p, age, seed) * activity * cursorJumpGain() * GLOW_INTENSITY;
    fragColor = color;
}
```

- [ ] **Step 5: Run static and Ghostty config validation**

Repeat Task 1 Step 4 with `cursor_fireflies.glsl`. Expected: exit `0`, no GLSL reserved-word or SPIR-V errors.

- [ ] **Step 6: Commit Cursor Fireflies**

```sh
git add cursor_fireflies.glsl
git commit -m "feat: add cursor fireflies shader"
```

---

### Task 3: Paper Grain

**Files:**
- Create: `paper_grain.glsl`

**Interfaces:**
- Consumes: `iResolution`, `iChannel0`.
- Produces: Ghostty entry point `void mainImage(out vec4 fragColor, in vec2 fragCoord)`.

- [ ] **Step 1: Add the shader header and exact tuning surface**

```glsl
const float GRAIN_STRENGTH = 0.018;
const float GRAIN_SCALE    = 1.00;
const float FIBER_STRENGTH = 0.010;
const float FIBER_SCALE    = 0.085;
const float WARMTH         = 0.018;
const float CONTRAST       = 0.025;
const float EDGE_SOFTNESS  = 0.72;
const float EDGE_STRENGTH  = 0.035;
const vec3  PAPER_WARMTH   = vec3(1.00, 0.93, 0.82);
```

The header must state that all noise is anchored to fragment coordinates and is static.

- [ ] **Step 2: Implement static fine grain and broad fibers**

```glsl
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float fiberNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
```

- [ ] **Step 3: Implement the single-sample paper treatment**

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec4 color = texture(iChannel0, uv);
    float grain = hash12(floor(fragCoord * GRAIN_SCALE)) - 0.5;
    float fibers = fiberNoise(fragCoord * FIBER_SCALE) - 0.5;
    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = vec3(luma) + (color.rgb - vec3(luma)) * (1.0 + CONTRAST);
    color.rgb += grain * GRAIN_STRENGTH + fibers * FIBER_STRENGTH;
    color.rgb = mix(color.rgb, color.rgb * PAPER_WARMTH, WARMTH);
    vec2 edge = abs(uv * 2.0 - 1.0);
    float vignette = smoothstep(EDGE_SOFTNESS, 1.0, max(edge.x, edge.y));
    color.rgb *= 1.0 - vignette * EDGE_STRENGTH;
    fragColor = vec4(color.rgb, color.a);
}
```

- [ ] **Step 4: Run static and Ghostty config validation**

Repeat Task 1 Step 4 with `paper_grain.glsl`. Expected: exit `0`; because the shader does not use `iTime`, repeated frames must produce identical output for identical terminal content.

- [ ] **Step 5: Commit Paper Grain**

```sh
git add paper_grain.glsl
git commit -m "feat: add paper grain shader"
```

---

### Task 4: README Integration

**Files:**
- Modify: `README.md:13` shader table.
- Modify: `README.md:50` installation command.
- Modify: `README.md:84-303` tuning section.

**Interfaces:**
- Consumes: exact constant names from Tasks 1-3.
- Produces: discoverable shader descriptions, copy instructions, and user-facing tuning guidance.

- [ ] **Step 1: Add exact shader table rows before Dimensional Rupture**

```markdown
| **Cloud Shadow** | [`cloud_shadow.glsl`](./cloud_shadow.glsl) | Broad, feathered cloud shadows drift slowly across the terminal with gentle darkening and no text distortion. Three inexpensive noise layers keep the motion soft and suitable for long sessions. |
| **Cursor Fireflies** | [`cursor_fireflies.glsl`](./cursor_fireflies.glsl) | Cursor changes release nine compact amber and pale-green lights that float outward and upward, flicker gently, and fade completely within 1.5 seconds. Large jumps are damped and idle output is unchanged. |
| **Paper Grain** | [`paper_grain.glsl`](./paper_grain.glsl) | A static warm-neutral paper treatment with fine grain, faint fibers, restrained contrast, and soft edge shading. It preserves the terminal palette and introduces no animation or refraction. |
```

- [ ] **Step 2: Extend the installation command**

Insert `lex-ghostty-shaders/cloud_shadow.glsl`, `lex-ghostty-shaders/cursor_fireflies.glsl`, and `lex-ghostty-shaders/paper_grain.glsl` before the destination `~/.config/ghostty/shaders/`.

- [ ] **Step 3: Add exact tuning tables before `## If you like this project`**

Add three sections whose rows use these implemented constants:

```markdown
For **Cloud Shadow**, the most useful knobs are:

| Knob | What it controls |
| --- | --- |
| `SHADOW_STRENGTH` | Maximum darkening from the passing cloud field. |
| `PATTERN_SCALE` | Size of the broad cloud forms. |
| `DRIFT_SPEED` | How quickly the shadows cross the terminal. |
| `SHADOW_SOFTNESS` | Width of the transition between clear and shaded areas. |
| `LAYER_WEIGHT` | Relative contribution of the three fixed noise layers. |

For **Cursor Fireflies**, the most useful knobs are:

| Knob | What it controls |
| --- | --- |
| `ACTIVITY_LIFE` | Seconds before a cursor-triggered burst disappears. |
| `BURST_RADIUS` | Maximum outward spread of the fireflies. |
| `UPWARD_DRIFT` | How strongly particles float upward. |
| `CORE_SIZE` / `HALO_SIZE` | Size of each bright point and its restrained glow. |
| `GLOW_INTENSITY` | Overall firefly brightness. |
| `JUMP_DAMPING` | Gain used for distant cursor jumps. |

For **Paper Grain**, the most useful knobs are:

| Knob | What it controls |
| --- | --- |
| `GRAIN_STRENGTH` / `GRAIN_SCALE` | Visibility and size of the static fine grain. |
| `FIBER_STRENGTH` / `FIBER_SCALE` | Visibility and size of broad paper fibers. |
| `WARMTH` | Strength of the warm-neutral paper bias. |
| `CONTRAST` | Small contrast lift applied around luminance. |
| `EDGE_SOFTNESS` / `EDGE_STRENGTH` | Reach and darkness of the soft edge shading. |
```

- [ ] **Step 4: Verify documentation matches files and commit**

Run:

```sh
for shader in cloud_shadow cursor_fireflies paper_grain; do
    test -f "$shader.glsl"
    rg -q "$shader.glsl" README.md
done
git diff --check
```

Expected: exit `0` and no output from `git diff --check`.

Commit:

```sh
git add README.md
git commit -m "docs: document daily-use shader trio"
```

---

### Task 5: Repository and Runtime Verification

**Files:**
- Verify: `cloud_shadow.glsl`
- Verify: `cursor_fireflies.glsl`
- Verify: `paper_grain.glsl`
- Verify: `README.md`

**Interfaces:**
- Consumes: complete deliverables from Tasks 1-4.
- Produces: recorded evidence of repository, config, runtime, and visual validation.

- [ ] **Step 1: Run required repository checks**

```sh
rg --files
git diff --check
git status --short --branch
```

Expected: all three new `.glsl` files and both Superpowers documents appear in `rg --files`; `git diff --check` is silent; the working tree is clean after the planned commits.

- [ ] **Step 2: Validate all shaders through temporary Ghostty configs**

```sh
for shader in cloud_shadow.glsl cursor_fireflies.glsl paper_grain.glsl; do
    tmp_config=$(mktemp)
    printf '%s\n' "custom-shader = $PWD/$shader" > "$tmp_config"
    /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config --config-file="$tmp_config" || exit 1
    rm -f "$tmp_config"
done
```

Expected: exit `0`. If Ghostty is unavailable, do not claim config validation.

- [ ] **Step 3: Perform manual Ghostty review**

Temporarily load each shader without committing local Ghostty config changes. Confirm:

- Cloud Shadow remains subtle, moves slowly, keeps glyphs crisp, and has no harsh cloud boundaries.
- Cursor Fireflies remains local during typing, fully disappears after 1.5 seconds, and does not flare on large jumps.
- Paper Grain remains stationary, avoids shimmer and a strong sepia cast, and keeps all common terminal colors distinguishable.
- None of the shaders produces edge artifacts or runtime log entries containing `GlslangFailed` or SPIR-V errors.

If any shader destabilizes Ghostty, remove or revert that shader before handoff. If visual review is unavailable, report only the static and config-level evidence.

- [ ] **Step 4: Record final branch state**

```sh
git status --short --branch
git log --oneline --decorate -8
git rev-list --left-right --count origin/main...HEAD
```

Expected: clean working tree and an explicit count of commits that would be included in any future push. Do not push unless the user asks.
