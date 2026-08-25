# Asset status

Tracks what art and audio exist, what is a placeholder, and what is missing.
No third-party or copyrighted game assets are used anywhere in this project.

## The SVG constraint

Artwork is authored as SVG. Godot rasterizes SVG at import through **ThorVG**,
whose feature support is limited. Assets must stay within:

- `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`
- flat fills, `<linearGradient>`, `<radialGradient>`
- simple strokes

Not supported — these silently render wrong or not at all:

- `<text>` — must be converted to paths
- filters, masks, clip paths
- complex nested groups with transforms

**Every new SVG must be visually checked after import.** A file that renders
correctly in a browser can still come out wrong in Godot.

For genuinely complex vector art, render to PNG at 4× and import that instead.

SVG import options live in the accompanying `.import` file; `scale` controls
raster resolution.

## Present

| Asset | Path | Status |
|---|---|---|
| Application icon | `assets/ui/app_icon.svg` | Original, final for now |
| Theme | `ui/theme/focus_garden_light.tres`, `focus_garden_dark.tres` | Generated from tokens; re-bake both, never hand-edit |

Navigation and empty-state glyphs are **emoji**, deliberately. They are a
placeholder for authored icons and are never the sole carrier of meaning — every
one is paired with a text label. Replacing them with custom SVG icons is a
Milestone 8 task and requires no code change beyond the glyph strings.

## Missing

### Plants — Milestone 2

12–20 species, each needing 5–6 growth-stage sprites, a catalogue illustration
and a small icon. This is the single largest outstanding art task; quality
matters more than quantity, and a smaller set of attractive plants beats a
hundred poor ones.

Target starter set: Pothos, Aloe Vera, Snake Plant, Spider Plant, Peace Lily,
Monstera, Jade Plant, Echeveria, Boston Fern, Rubber Plant, Lavender, Sunflower.

`PlantSpecies.get_stage_texture()` returns `null` when art is absent, and callers
must substitute a placeholder rather than rendering an empty rectangle.

### Also outstanding

| Asset | Milestone | Notes |
|---|---|---|
| Pots (5+ designs) | 4 | Referenced by `pot_id` |
| Shelf styles (3) + backgrounds | 4 | |
| Decorations (10+) | 7 | |
| Garden environment | 7 | |
| UI icons | 8 | Replaces emoji |
| Achievement icons (20+) | 5 | |
| Ambient audio | 8 | Rain, forest, fireplace, café, night, wind |
| UI and timer sounds | 8 | Must be quiet and unobtrusive |
| Display font | 8 | Currently the engine default. Needs a licence permitting redistribution — check before bundling. |

## Rules

- Placeholders follow the same aesthetic as the final art. Programmer art does
  not ship, even temporarily.
- Keep correct dimensions from the start so swapping in real art needs no layout
  change.
- Asset references go through species and theme resources, so a whole art set can
  be replaced without touching gameplay code.
- Update this file whenever an asset lands or a new gap appears.
