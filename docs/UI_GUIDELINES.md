# UI guidelines

## Look

Cozy botanical. Warm parchment grounds, deep moss greens, terracotta and amber
accents, rounded cards, soft shadows. A lamplit potting bench — not a dashboard.

The design commits to a single warm light appearance rather than offering a dark
mode, so contrast and mood can be tuned properly once.

## Tokens are the only source of colour

`ui/theme/design_tokens.gd` holds every colour, spacing value, radius, type size
and motion duration. **Nothing in the codebase may hardcode a colour or a pixel
spacing.** If a screen needs a shade that is not there, add a token.

`ThemeBuilder` turns tokens into a `Theme`. `tools/bake_theme.gd` writes
`ui/theme/focus_garden.tres`, which is committed and referenced by
`project.godot` so the editor previews real styling while git still diffs a
readable GDScript file instead of a giant `.tres`.

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/bake_theme.gd
```

Re-bake and commit the result after any token change. Never hand-edit the
generated `.tres`.

Scales: spacing on a 4px grid (4/8/12/16/24/32/48); radii 6/10/16/pill; type
44/28/20/16/14/12.

## Components

| Component | Use |
|---|---|
| `AppScreen` | Base for every section. Owns padding, scrolling and max content width. |
| `MilestoneScreen` | Base for sections not yet built. |
| `SectionHeader` | The title block every screen opens with. |
| `StatTile` | A labelled figure. |
| `EmptyState` | A deliberate "nothing here yet". |
| `Motion` | Animation timing that honours accessibility settings. |

Theme variations, set via `theme_type_variation`: `PrimaryButton`,
`SubtleButton`, `DangerButton`, `NavButton`, `Card`, `CardSunken`, `NavPanel`,
`Display`, `Title`, `Heading`, `Caption`, `Muted`.

Screens set a variation. They do not override colours locally.

## Layout

Design resolution 1920×1080, minimum 1280×720, enforced at runtime via
`DisplayServer.window_set_min_size`. Stretch mode is `canvas_items` with `expand`
aspect, so the UI scales cleanly and wider aspect ratios reveal more space rather
than letterboxing.

`AppScreen` caps the content column at 1180px and centres it. On an ultrawide
monitor the surplus becomes equal margins instead of paragraphs stretched across
3440 pixels.

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
  `INK_ON_DISABLED` exists because an earlier version did exactly that.
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
- [ ] Line length is readable — body copy is width-capped
- [ ] Empty and loading states look intentional
- [ ] Nothing repeats the page title immediately below itself
- [ ] It looks like part of the same game as every other screen

Verify visually, not by reading code:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . --script res://tools/capture_screens.gd
```

That renders all nine screens at both resolutions to `user://captures`. Reading
the code cannot tell you that a progress bar is the same colour as the card
behind it — looking at the picture can, and did.

## Screens are built in code

Screens are GDScript classes extending `AppScreen` rather than hand-authored
`.tscn` files. This keeps them deterministic and diffable, and avoids a large
class of hand-written scene-file errors. `scenes/main/main.tscn` is the only
authored scene.

As screens gain real complexity in later milestones, converting individual ones
to `.tscn` is expected — the component classes work either way.
