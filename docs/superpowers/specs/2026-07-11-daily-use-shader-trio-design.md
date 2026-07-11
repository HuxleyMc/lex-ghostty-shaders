# Daily-Use Shader Trio Design

## Goal

Add three visually distinct Ghostty shaders that are pleasant during long terminal sessions. The set should expand the repository without repeating its existing water, aurora, comet, frost, hologram, or CRT effects. Every shader must prioritize text legibility, use bounded procedural work, and remain a single self-contained `.glsl` file.

The trio consists of:

- `cloud_shadow.glsl`: a quiet ambient effect.
- `cursor_fireflies.glsl`: a typing-reactive effect.
- `paper_grain.glsl`: a static screen treatment.

## Shared Constraints

- Preserve `mainImage(out vec4 fragColor, in vec2 fragCoord)` and Ghostty-compatible uniforms.
- Preserve the terminal's original colors instead of replacing them with a fixed palette.
- Apply no text refraction or coordinate distortion by default.
- Group clearly commented tuning constants near the top of each file.
- Use no external textures, feedback buffers, preprocessing, or generated assets.
- Keep loops fixed and small, with minimal sampling of `iChannel0`.
- Update the README shader table, installation command, and tuning documentation for all three files.

## Cloud Shadow

`cloud_shadow.glsl` will cast broad, feathered shadows that move slowly across the terminal. The motion should be difficult to notice from one moment to the next but apparent over a longer session.

The effect will combine three inexpensive procedural noise layers at different scales and drift directions. The resulting mask will slightly darken the existing terminal image without adding bright cloud shapes or moving its texture coordinates. Shadow coverage must remain soft and sparse enough that foreground text retains its normal contrast.

Primary tuning constants will cover:

- shadow strength;
- pattern scale;
- drift speed;
- softness;
- layer contribution.

## Cursor Fireflies

`cursor_fireflies.glsl` will create a compact cluster of warm amber and pale-green lights after a cursor change. Each light will float outward and slightly upward, flicker gently, and disappear within 1.5 seconds by default. When no recent cursor activity exists, the terminal output will be unchanged.

The shader will derive activity from `iTimeCursorChange` and position the burst using `iCurrentCursor` and `iPreviousCursor`. It will reuse the repository's large-jump damping pattern so page changes and distant cursor jumps do not create oversized streaks. A fixed loop of nine hashed particles will determine each firefly's direction, speed, phase, and color variation. Each particle will use a compact core and restrained halo; there will be no persistent trail.

Primary tuning constants will cover:

- activity lifetime and fade curve;
- particle count;
- burst radius and upward drift;
- core size and halo size;
- glow intensity;
- amber and pale-green colors;
- large-jump damping.

## Paper Grain

`paper_grain.glsl` will apply a static warm paper character to the terminal. It will combine fine coordinate-hashed grain, extremely faint low-frequency fiber variation, a small contrast adjustment, and soft edge shading. The treatment must remain neutral enough for arbitrary terminal color schemes and must not read as a strong sepia filter.

The grain will be anchored to fragment coordinates and remain stationary. This avoids temporal shimmer and makes the shader suitable for continuous use. The terminal image will be sampled once, then adjusted with low-amplitude luminance variation and a subtle warm bias.

Primary tuning constants will cover:

- grain strength and scale;
- fiber strength and scale;
- warmth;
- contrast;
- edge softness and strength.

## Performance and Failure Behavior

All procedural work will have a fixed cost per pixel. Cloud Shadow will use only a few noise layers, Cursor Fireflies will use one fixed small particle loop, and Paper Grain will avoid loops entirely. Each shader will use one normal terminal texture sample and avoid multipass techniques.

If a shader fails Ghostty runtime compilation or destabilizes Ghostty, it will not be retained merely because config validation passes. Compilation errors will be corrected before handoff; a crash will trigger removal or rollback of the offending shader.

## Documentation and Validation

The README will gain a description and tuning section for each shader, and its installation copy command will include all three new files.

Validation will include:

1. `rg --files` to confirm repository shape.
2. `git diff --check` to detect whitespace errors.
3. Ghostty `+validate-config` using a temporary config for each shader when Ghostty is available.
4. Runtime-log inspection for GLSL or SPIR-V errors if compilation behavior is suspicious.
5. Manual visual review in Ghostty for text legibility, motion, idle behavior, cursor response, and edge artifacts.

If manual visual review cannot be performed in the current environment, the final report will distinguish static and config-level validation from visual confirmation.

## Acceptance Criteria

- All three shader files follow the repository's self-contained Ghostty format.
- Cloud Shadow is slow, soft, ambient, and non-distorting.
- Cursor Fireflies activates on cursor changes, stays local, and fades fully to the original terminal image when idle.
- Paper Grain is static, subtle, warm-neutral, and free of shimmer.
- Default settings keep text readable and preserve the user's terminal palette.
- Procedural work remains bounded and documentation matches the implemented constants.
- Required repository and available Ghostty validation checks pass.
