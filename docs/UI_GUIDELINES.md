# UI guidelines

## Look

Cozy botanical. Warm grounds, deep moss greens, terracotta and amber accents,
rounded cards, layered shadows. A lamplit potting bench — not a dashboard.

Two appearances, light and dark. Dark is the same shop after closing: the light
goes, the warmth does not, so its surfaces are warm charcoal-green rather than
neutral black. Both are held to the same contrast bar.

## Tokens are the only source of colour

The token layer is split along the one axis that matters — whether a value
depends on the appearance mode.

| File | Holds | Shape |
|---|---|---|
| `ui/theme/palette.gd` | Every colour, in both modes | Static getters: `Palette.ink_primary()` |
| `ui/theme/design_tokens.gd` | Spacing, radii, type, motion, elevation, layout | Constants: `DesignTokens.SPACE_MD` |

**Nothing in the codebase may hardcode a colour or a pixel spacing.** If a screen
needs a shade that is not there, add a token.

**The dark-mode rule: never write a literal `Color` in a `_draw`.** Half this
app's surfaces — plants, pots, the shelf, the garden, the heatmap — are drawn by
hand, and Godot's theme system knows nothing about them. A hex literal in a
`_draw` looks perfectly correct in light and invisible in dark, and the only way
to find it is to look at a picture. Go through `Palette`.

Authored CONTENT colours are the exception, and they are still not literals: a
species' foliage, a pot's clay and an ornament's timber are the same colour in
both modes and live on their resources. `Palette.content()` seats them into the
active scene's light so foliage does not glow out of a dark garden.

`ThemeBuilder.build(mode)` turns tokens into a `Theme`. `tools/bake_theme.gd`
writes BOTH modes, to `ui/theme/focus_garden_light.tres` and
`focus_garden_dark.tres`. The light one is referenced by `project.godot` so the
editor previews real styling, while git still diffs readable GDScript instead of
a giant `.tres`.

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/bake_theme.gd
```

Re-bake and commit BOTH results after any token change. Never hand-edit a
generated `.tres`. A variation that exists in one mode and not the other is the
failure the shared builder is shaped to prevent — the app would fall back to
Godot's default styling the moment a player switched appearance.

Scales: spacing on a 4px grid (4/8/12/16/24/32/48); radii 8/12/18/pill; type
88/42/26/18/15/13/12/11.

## Typography

No typeface is bundled. `DesignTokens.font()` builds a `SystemFont` over a
fallback chain (Segoe UI Variable Text → Segoe UI → Inter → Noto Sans → Open
Sans → DejaVu Sans), wrapped in a `FontVariation` for weight. The countdown and
the stat tiles pass `tabular_figures`, so digits keep a fixed width and a running
timer does not jitter as it counts down.

## Elevation

Surfaces are separated by a two-layer shadow, indexed by level in
`DesignTokens.ELEVATION_*`: 0 is flush, 1 is a card, 2 is a dialog or something
being dragged. A single flat shadow reads as a sticker; a wide ambient layer plus
a tight offset key layer reads as something lifted off the page. `StyleBoxFlat`
supports only one shadow, so a stylebox gets the ambient layer — the one doing
the work — and custom `_draw` code uses both.

## Components

| Component | Use |
|---|---|
| `AppScreen` | Base for every section. Owns padding, scrolling and max content width. |
| `MilestoneScreen` | Base for sections not yet built. |
| `SectionHeader` | The title block every screen opens with. |
| `StatTile` | A labelled figure. |
| `EmptyState` | A deliberate "nothing here yet". |
| `PlantCard` | A species or an owned plant, presented as a card. |
| `PlantStageText` | The one wording for how far along a plant is. |
| `Motion` | Animation timing that honours accessibility settings. |

Theme variations, set via `theme_type_variation`:

- Buttons: `PrimaryButton` (filled), `SecondaryButton` (tonal), `SubtleButton`
  (ghost), `DangerButton`, `NavButton`, `Chip`
- Surfaces: `Card`, `CardFlush` (no padding, for a full-bleed drawing),
  `CardSunken`, `NavPanel`, `Badge`
- Text: `Display`, `Title`, `Heading`, `CardTitle`, `Muted`, `Caption`,
  `Eyebrow`, `Countdown`, `NavBrand`, `NavCaption`

Three button weights, not two. Reaching for `PrimaryButton` to make a second
action visible puts two competing primaries on one card; `SecondaryButton` is the
tonal middle that case actually wants.

Screens set a variation. They do not override colours locally.

## Layout

Design resolution 1920×1080, minimum 1280×720. Stretch mode is `canvas_items`
with `expand` aspect, so the UI scales cleanly and wider aspect ratios reveal
more space rather than letterboxing.

`AppScreen` caps the content column at 1180px and centres it. On an ultrawide
monitor the surplus becomes equal margins instead of paragraphs stretched across
3440 pixels.

**The minimum window size scales with the interface scale, and `UiScale` owns
both.** `content_scale_factor` does not resize the window — it shrinks the
LOGICAL viewport the layout is measured in, so a 1280×720 window at 200% is a
640×360 layout, half the supported minimum. Setting the factor without raising
the minimum is what used to push the app's top-left corner off screen: a Control
whose minimum size exceeds its anchored size gets repositioned to make room, and
`GROW_DIRECTION_BOTH` splits that overflow evenly — half of it past the origin,
where there is no scrollbar to reach it. `Main` therefore grows toward the end,
and `AppScreen` scrolls horizontally when something genuinely does not fit.

**A hand-drawn view letterboxes itself; it does not fill its card.** `GardenView`
and `ShelfView` centre their scene in the space they are given and paint the
surround as part of it — a table top, a wall. Stretching to fill turned square
garden cells into strips; a strict aspect fit left a small scene marooned in a
tall card. Both keep their proportions inside a stated range instead, and use
whatever room is left.

**Long body copy must be width-capped.** Inside a `VBoxContainer` a `Label`
defaults to filling the full width, so autowrap never triggers and a sentence
becomes one enormous line that technically fits and is miserable to read. Use
`SIZE_SHRINK_CENTER` with a `custom_minimum_size.x` — that is what makes autowrap
break at a readable measure. `EmptyState` does this; copy the pattern.

Never hardcode screen positions. Use anchors, containers and size flags.

## Accessibility

- Navigation entries show a glyph **and** a label. An icon is never the only
  carrier of meaning.
- Rarity has a colour **and** a name. Status is never communicated by colour
  alone.
- Every interactive control has visible hover, pressed, focus and disabled
  states, defined once in the theme so no screen can ship a button that silently
  lacks feedback.
- Disabled text stays readable. A pale label on a pale disabled fill fails this —
  `ink_on_disabled` exists because an earlier version did exactly that.
- **Every drag has a click-and-keyboard equivalent.** A gesture that is the only
  way to do something is a feature some players do not have. The shelf and the
  garden each carry a keyboard cursor: Tab reaches the view, the arrow keys walk
  it, Enter acts as a click would, and R turns whatever is under it. The cursor
  is the same highlight the mouse uses — one idea of "the square being
  considered", so the two can never drift apart — drawn heavier when the keyboard
  is driving, because a hover follows a pointer while a cursor IS the player's
  position and has to be findable without one. The cursor stops at the edges
  rather than wrapping, so the arrow key that would move focus out of the view is
  not swallowed.
- Reduced motion is honoured through `Motion.duration()`. At zero duration a
  tween still applies its **end state**, so nothing is left half-faded or
  invisible. Effects that cannot simply be shortened — idle sway, drifting
  particles — must check `Motion.is_reduced()` and switch off.

## Screen quality gate

Before any screen is called finished:

- [ ] Hierarchy is obvious; the primary action is visually dominant
- [ ] Spacing comes from the scale; typography comes from a variation
- [ ] Hover, pressed, focus and disabled states all respond
- [ ] No clipped text, no overlap at both 1280×720 and 1920×1080
- [ ] Nothing is lost at 75%, 150% or 200% interface scale — the rail and the
      section heading are still there, and nothing is cut off at the top or left
- [ ] It reads correctly in dark mode, including anything drawn by hand
- [ ] Line length is readable — body copy is width-capped
- [ ] Empty and loading states look intentional
- [ ] Nothing repeats the page title immediately below itself
- [ ] It looks like part of the same game as every other screen

Verify visually, not by reading code. Seed a save worth photographing first, or
every screen captures empty:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/simulate_progress.gd
```

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . --script res://tools/capture_screens.gd
```

That renders all nine screens at both resolutions, again in dark mode, and the
widest three at 75/100/150/200% interface scale, into `user://captures`. Reading
the code cannot tell you that a progress bar is the same colour as the card
behind it, or that a scaled-up layout has walked off the top-left of the window —
looking at the picture can, and did, twice.

## Screens are built in code

Screens are GDScript classes extending `AppScreen` rather than hand-authored
`.tscn` files. This keeps them deterministic and diffable, and avoids a large
class of hand-written scene-file errors. `scenes/main/main.tscn` is the only
authored scene.

As screens gain real complexity in later milestones, converting individual ones
to `.tscn` is expected — the component classes work either way.
