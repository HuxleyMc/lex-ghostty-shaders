# Repository Guidelines

## Project Shape

This repository is a small collection of custom Ghostty terminal shaders. Each shader should remain a single, self-contained `.glsl` file in Ghostty's ShaderToy-compatible fragment shader format.

There is no package manager, build system, generated workspace, or automated test suite in this repo.

## Editing Shaders

- Keep shaders self-contained unless the repo is intentionally restructured.
- Preserve the `mainImage(out vec4 fragColor, in vec2 fragCoord)` entry point and Ghostty-compatible uniform usage.
- Prefer tunable `const` values near the top of each shader, grouped and commented clearly.
- Keep comments useful for future tuning and Ghostty behavior, especially where stateless ShaderToy-style constraints matter.
- Avoid adding dependencies, preprocessing steps, or generated shader artifacts unless explicitly requested.
- If a shader uses upstream code or is derived from another source, document the source and license in the shader header.

## Documentation

- Update `README.md` when adding, renaming, or removing a shader.
- Keep the shader table, installation examples, and tuning sections in sync with actual `.glsl` files.
- When adding notable tuning constants, document the most user-facing knobs in the README.
- Keep usage instructions centered on Ghostty config via `custom-shader`.

## Validation

Before finishing changes, run lightweight repository checks:

```sh
rg --files
git diff --check
```

For shader behavior changes, validate manually in Ghostty:

1. Copy or symlink the shader into `~/.config/ghostty/shaders/`.
2. Set `custom-shader = ./shaders/<shader>.glsl` in `~/.config/ghostty/config`.
3. Reload or restart Ghostty.
4. Check legibility, motion, idle behavior, cursor-triggered behavior, and edge artifacts.

If Ghostty is not available in the current environment, state that only static checks were run.

## Style

- Keep new project guidance and shell snippets portable POSIX-style `sh` unless there is a Ghostty-specific reason otherwise.
- Use stable file names in lowercase with underscores for shader files.
- Keep unrelated marketing or app-listing edits out of shader changes.
- Do not commit local Ghostty config, copied shader installs, screenshots, or temporary render captures.
