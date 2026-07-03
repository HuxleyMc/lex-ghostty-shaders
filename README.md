# lex-ghostty-shaders

A collection of custom [Ghostty](https://ghostty.org/) terminal shaders, authored and tuned by hand.

Ghostty supports custom GLSL fragment shaders that run on the terminal's rendered output every frame. This repo collects the shaders I've built for it. Each shader is a single, self-contained `.glsl` file written in Ghostty's ShaderToy-compatible format, with tunable constants documented at the top.

## AI implementation note

All shader implementations in this project were automatically learned and improved by AI based on existing shaders found online. The primary models used are OpenAI GPT-5.5 Extra High and [ZAI GLM 5.2 Max](https://z.ai/subscribe?ic=LGCYU9JDKH).

## Shaders

| Shader           | File                                       | Description                                                                                                                                                                                                                                                                                        |
| ---------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Water Ripple** | [`water_ripple.glsl`](./water_ripple.glsl) | Renders the terminal behind a calm water surface. A subtle ambient undulation is always present, and each keystroke drops a "pebble" at the cursor — a damped radial wave train that expands outward and fades to calm. Faster typing keeps fresh ripples near the cursor; idle water stays still. |
| **Water Caustic** | [`water_caustic.glsl`](./water_caustic.glsl) | A lit-water caustic shimmer over the terminal, ported from [Paper Design's "Water"](https://shaders.paper.design/water). A recursive fractal-noise caustic field (zozuar's algorithm) distorts the texture lookup, a simplex-noise wave term adds slow lateral drift, and a soft highlight tint follows the caustic web. Always in motion, no cursor coupling. |
| **Fire Embers** | [`fire_embers.glsl`](./fire_embers.glsl) | A subtle ambient fire shader tuned for terminal legibility. A bottom-weighted ember bed adds warm glow, sparse procedural sparks drift upward, and mild heat-haze refraction fades out before it reaches most of the text. Always in motion, no cursor coupling. |
| **Matrix Rain** | [`matrix_rain.glsl`](./matrix_rain.glsl) | A subtle Matrix-inspired falling-code overlay. Sparse hashed columns drift downward with brighter leading heads and fading trails, while procedural rectangular glyph fragments avoid font assets and keep terminal text readable. Wakes on cursor changes such as typing, then fades out when idle. |
| **Cursor Sparks** | [`cursor_sparks.glsl`](./cursor_sparks.glsl) | An electric-blue cursor lightning effect. Each cursor change creates a compact glow, soft halo, and short jagged bolt branches from the cursor; fast typing keeps the burst active, while idle terminals fade back to normal. Large cursor jumps are damped to avoid oversized flashes. |
| **Aurora Veil** | [`aurora_veil.glsl`](./aurora_veil.glsl) | A soft ambient aurora overlay. Layered cyan, green, and violet ribbons drift near the top third of the terminal with a faint tint and very light refraction, keeping text readability first. Always in motion, no cursor coupling. |
| **Ink Bloom** | [`ink_bloom.glsl`](./ink_bloom.glsl) | A cursor-reactive ink/color bloom. Each cursor change emits one expanding radial bloom from the cursor; fast typing keeps fresh blooms active, while large cursor jumps are damped through the previous cursor position. |
| **CRT Phosphor Bloom** | [`crt_phosphor_bloom.glsl`](./crt_phosphor_bloom.glsl) | A bold CRT pass with strong scanlines, phosphor slot tint, local brightness bloom, red/blue pixel separation, static tube grain, controlled phosphor flicker, glass glow, mild barrel curvature, and tube edge darkening. |

> **About the Water Ripple "stateless" design.** Ghostty custom shaders are stateless (ShaderToy format) — the GPU carries no per-frame state, and only `iChannel0` (the terminal image) plus built-in uniforms are available. This shader builds its dynamic effect purely from `iTime` and `iTimeCursorChange` (the timestamp of the most recent cursor change, which fires per keystroke and is not retriggered by cursor blink). Because only the single latest keystroke is timestamped, at most one pebble wave train is active at a time; the ambient field plus the wave train's many rings provide the "interacting ripples" feel within that constraint. See the shader's header comment for the full explanation and the list of tunable knobs.

## Requirements

- [Ghostty](https://ghostty.org/) (custom shader support ships with recent versions)

## Installation

1. Clone this repository:

   ```sh
   git clone https://github.com/lexrus/lex-ghostty-shaders.git
   ```

2. Copy the shader(s) you want into Ghostty's config directory:

   ```sh
   mkdir -p ~/.config/ghostty/shaders/
   cp lex-ghostty-shaders/water_ripple.glsl lex-ghostty-shaders/water_caustic.glsl lex-ghostty-shaders/fire_embers.glsl lex-ghostty-shaders/matrix_rain.glsl lex-ghostty-shaders/cursor_sparks.glsl lex-ghostty-shaders/aurora_veil.glsl lex-ghostty-shaders/ink_bloom.glsl lex-ghostty-shaders/crt_phosphor_bloom.glsl ~/.config/ghostty/shaders/
   ```

## Enabling a shader in Ghostty

Add a `custom-shader` line to your Ghostty config file at `~/.config/ghostty/config`:

```ini
custom-shader = ./shaders/water_ripple.glsl
```

Paths are relative to the config file's location, or you can use an absolute path:

```ini
custom-shader = ~/.config/ghostty/shaders/water_ripple.glsl
```

Restart Ghostty (or reload its config) for the change to take effect. You can comment out the line with `#` to disable the shader.

### Tip: keep this repo as your shaders folder

If you'd like this repo to _be_ your Ghostty shaders directory, you can symlink it:

```sh
# Back up any existing shaders folder first, then:
ln -s "$PWD/lex-ghostty-shaders" ~/.config/ghostty/shaders
```

Then reference shaders directly:

```ini
custom-shader = ./shaders/water_ripple.glsl
```

## Tuning

Each shader exposes its parameters as clearly commented `const` values near the top of the file. For **Water Ripple**, the most useful knobs are:

| Knob                         | What it controls                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `REFRACTION`                 | How strongly the water distorts the terminal text. Lower = more legible.             |
| `AMBIENT_STRENGTH`           | Strength of the always-on shallow-water undulation. `0` = perfectly still when idle. |
| `PEBBLE_AMP`                 | Height of the cursor-drop ripples.                                                   |
| `WAVENUMBER` / `OMEGA`       | Ring spacing and propagation speed.                                                  |
| `FRONT_SPEED`                | How fast ripples expand across the screen.                                           |
| `RIPPLE_LIFE` / `DECAY_RATE` | How long ripples persist before calming.                                             |

Edit the values in the `.glsl` file and reload Ghostty — no recompilation step is needed.

For **Water Caustic**, the most useful knobs are (defaults match the upstream "Default" preset):

| Knob          | What it controls                                                                              |
| ------------- | --------------------------------------------------------------------------------------------- |
| `CAUSTIC`     | Overall caustic distortion strength. Lower = more legible text.                               |
| `WAVES`       | Simplex lateral shimmer independent of the caustic web.                                       |
| `HIGHLIGHTS`  | Caustic-shaped tint brightening the surface along the web (the "wet shimmer").                |
| `LAYERING`    | Strength of the second, finer/slower caustic layer.                                           |
| `EDGES`       | How much caustic distortion concentrates near the edges vs. uniformly across the surface.     |
| `SIZE`        | Pattern scale (caustic cell size). Higher = tighter webbing.                                  |

For **Fire Embers**, the most useful knobs are:

| Knob               | What it controls                                                                      |
| ------------------ | ------------------------------------------------------------------------------------- |
| `EMBER_HEIGHT`     | How far the ember glow and heat shimmer rise from the bottom of the terminal.         |
| `EMBER_INTENSITY`  | Strength of the broken ember color near the lower edge.                               |
| `GLOW_INTENSITY`   | Broad warm tint over the bottom-weighted heat area.                                   |
| `HEAT_REFRACTION`  | How strongly the heat haze distorts terminal text. Lower = more legible.              |
| `HEAT_SPEED`       | Upward speed of the heat shimmer.                                                     |
| `HEAT_SCALE`       | Size of the heat-haze cells. Higher = finer, tighter shimmer.                         |
| `SPARK_DENSITY`    | Number of procedural spark lanes across the terminal.                                 |
| `SPARK_BRIGHTNESS` | Brightness of the sparse rising sparks.                                               |

For **Matrix Rain**, the most useful knobs are:

| Knob                  | What it controls                                                                      |
| --------------------- | ------------------------------------------------------------------------------------- |
| `RAIN_DENSITY`        | Fraction of columns that can emit falling glyph fragments.                            |
| `FALL_SPEED`          | Base downward speed of the rain streams.                                              |
| `GLYPH_SCALE`         | Size of the procedural grid. Higher = smaller, denser glyph cells.                    |
| `DARKEN_STRENGTH`     | Overall darkening applied while the activity-gated Matrix effect is visible.          |
| `GLOW_INTENSITY`      | Brightness added by the green rain fragments. Lower = more legible.                  |
| `TRAIL_FADE`          | How quickly each stream fades behind the bright leading head.                         |
| `GREEN_TINT_STRENGTH` | Strength of the low green cast while the Matrix effect is visible.                    |
| `ACTIVITY_LIFE`       | How long the Matrix effect stays visible after typing or cursor movement.             |
| `ACTIVITY_FADE_POWER` | Shape of the idle fade-out. Higher = fades more sharply near the end.                 |

For **Cursor Sparks**, the most useful knobs are:

| Knob                  | What it controls                                                                      |
| --------------------- | ------------------------------------------------------------------------------------- |
| `ACTIVITY_LIFE`       | How long the cursor burst stays visible after typing or cursor movement.              |
| `ACTIVITY_FADE_POWER` | Shape of the idle fade-out. Higher = fades more sharply near the end.                 |
| `GLOW_RADIUS`         | Radius of the soft blue halo around the cursor.                                       |
| `CORE_INTENSITY`      | Brightness of the compact cursor-centered light.                                      |
| `HALO_INTENSITY`      | Strength of the broader glow around the cursor.                                       |
| `LIGHTNING_INTENSITY` | Brightness of the jagged white-blue bolt cores.                                       |
| `BOLT_SPEED`          | How quickly bolts crawl outward from the cursor after a strike.                       |
| `BOLT_WIDTH`          | Thickness of the bright bolt cores. Lower = sharper lightning.                        |
| `BOLT_JAGGEDNESS`     | Sideways kink amount along each bolt. Higher = more angular lightning.                |
| `BRANCH_INTENSITY`    | Brightness of short side branches compared with main bolts.                           |
| `FLICKER_INTENSITY`   | Per-frame brightness flicker during an active strike.                                 |
| `BOLT_COUNT`          | Number of procedural bolt directions in each burst.                                   |

For **Aurora Veil**, the most useful knobs are:

| Knob               | What it controls                                                                      |
| ------------------ | ------------------------------------------------------------------------------------- |
| `AURORA_HEIGHT`    | Vertical reach of the aurora from the top of the terminal.                            |
| `RIBBON_INTENSITY` | Brightness added by the colored ribbon bands. Lower = more legible.                   |
| `DRIFT_SPEED`      | How quickly the aurora curtains move laterally over time.                             |
| `RIBBON_SCALE`     | Pattern scale of the folds. Higher = tighter, more frequent ribbon bends.             |
| `TINT_STRENGTH`    | Strength of the faint top-area color cast behind the brighter bands.                  |
| `REFRACTION`       | How strongly aurora gradients distort the terminal image.                             |

For **Ink Bloom**, the most useful knobs are:

| Knob             | What it controls                                                                        |
| ---------------- | --------------------------------------------------------------------------------------- |
| `BLOOM_LIFE`     | How long each cursor-triggered bloom remains visible.                                   |
| `BLOOM_RADIUS`   | Final radius of the expanding ink bloom.                                                |
| `INK_INTENSITY`  | Strength of the added bloom color and light. Lower = more legible.                      |
| `EDGE_SOFTNESS`  | Softness of the expanding bloom edge. Higher = hazier, lower = sharper ring.            |
| `COLOR_SHIFT`    | Default palette balance between blue and magenta ink.                                   |
| `JUMP_DAMPING`   | How much large cursor jumps are reduced compared with local typing-style cursor moves.  |

For **CRT Phosphor Bloom**, the most useful knobs are:

| Knob                | What it controls                                                                      |
| ------------------- | ------------------------------------------------------------------------------------- |
| `SCANLINE_STRENGTH` | Darkness of the horizontal scanline pattern.                                          |
| `BLOOM_INTENSITY`   | Strength of the local brightness halo around bright terminal pixels.                  |
| `PHOSPHOR_TINT`     | Amount of RGB/phosphor color tint and slot-mask color.                                |
| `VIGNETTE`          | Edge darkening around the terminal viewport.                                          |
| `PIXEL_SHARPNESS`   | Balance between neighbor smoothing and crisp center pixels. Higher = sharper text.    |
| `GRAIN_STRENGTH`    | Static subpixel/tube texture strength. Higher = more visible CRT grain.              |
| `FLICKER_STRENGTH`  | Controlled phosphor shimmer strength. Higher = more visible CRT flicker.             |
| `FLICKER_SPEED`     | Flicker cadence in updates per second.                                               |
| `GLASS_TINT`        | Stable low tube glow that makes the CRT treatment visible on dark backgrounds.        |
| `MASK_VISIBILITY`   | Shadow-mask contrast that does not depend only on bright text pixels.                 |
| `CHROMATIC_OFFSET`  | Red/blue sample offset in physical pixels. Higher = more color fringing.             |
| `CURVATURE`         | Mild barrel curvature that makes the terminal plane read more like a CRT tube.        |
| `TUBE_EDGE`         | Extra darkening near curved screen edges.                                             |

## If you like this project

You might also like my other apps.

### 💸 [SubList](https://apps.apple.com/app/sublist-subscription-list/id6757860829) (iOS, macOS)

Track subscriptions, renewals, and spending in one place with reminders, analytics, and iCloud sync.

### 🗂️ [SwiftyMenu](https://apps.apple.com/app/id1567748223) (macOS)

A Finder extension which presents a customizable menu to rapidly open selected folders or files with your favorite applications.

### 📱 [Sharptooth](https://apps.apple.com/app/id6748440814) (macOS)

Effortlessly manage your Bluetooth devices right from the menu bar with custom hotkeys and smart automation.

### 🔤 [RegEx+](https://apps.apple.com/app/id1511763524) (iOS, macOS)

An app to test your regular expressions with live matching.

### 📸 [LiveExtractor](https://apps.apple.com/app/id6746672642) (iOS, macOS, tvOS, visionOS)

Extract individual photos and videos from your Live Photos across all your Apple devices.

## License

Provided as-is for personal use. Individual shaders note their upstream sources and licenses in their header comments where applicable.
