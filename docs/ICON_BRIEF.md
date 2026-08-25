# Icon brief

A self-contained prompt for commissioning a replacement icon set, from an AI tool
or a human illustrator. Everything needed is in this file — palette, inventory,
technical constraints — so it can be pasted somewhere with no other context.

The app currently uses **system emoji** for every icon. They render differently on
every machine, ignore the palette entirely, and are the single most obviously
un-designed thing left in the interface.

Copy everything below the line.

---

## Brief: icon set for Focus Garden

You are designing a **cohesive icon set** for Focus Garden, a cozy desktop
productivity app where focused work time grows virtual plants. I need **26 SVG
icons**. Please output each as complete, standalone SVG source.

### The feel

The app's design intent is *"the interior of a small plant shop at golden hour"* —
a lamplit potting bench, not a dashboard. Warm, calm, unhurried, a little
hand-made. The whole app's artwork is drawn from simple geometry rather than
painted, and the icons should belong to that world.

Aim for: **soft-geometric, rounded, slightly organic**. Think tidy hand-drawn
rather than precise corporate line-art. Rounded line caps and joins. Gentle
asymmetry is welcome — a leaf that leans, a pot a touch off-centre — but never at
the cost of legibility.

Avoid: hard-edged Material/Bootstrap geometry, thin wiry 1px strokes, glossy
skeuomorphism, drop shadows, 3D perspective, gradients-as-decoration, and anything
that reads as "startup SaaS".

### The palette — use these exact values

Surfaces and ink (the two appearance modes):

| Role | Light | Dark |
|---|---|---|
| Page | `#E9DFC9` | `#191D1A` |
| Card surface | `#FFFCF5` | `#232A25` |
| Navigation rail | `#365A4D` | `#131A16` |
| Ink on card | `#2B2519` | `#EDE7D8` |
| Ink on rail | `#F2E9D6` | `#EDE7D8` |
| Muted ink | `#8B7C64` | `#8B8878` |

Accents:

| Role | Light | Dark |
|---|---|---|
| Moss (growth, primary) | `#4F8340` | `#7CBB63` |
| Terracotta | `#BF6440` | `#E08A5F` |
| Amber (streaks, glow) | `#DC9A32` | `#EBB55A` |
| Sky (breaks, calm) | `#5F9391` | `#7FB6B3` |
| Clay (destructive) | `#A94B33` | `#DB7358` |
| Oak (timber) | `#C69A63` | `#B98D5C` |

Plant and object colours, used throughout the app's own procedural artwork —
**match these** so an icon of a plant looks like the plants it represents:

- Foliage base `#4A7C3F`, leaf tips `#7FB069`, stems `#5F7F42`
- Deeper foliage `#3D6B44`, pale/variegated foliage `#9BC08A`
- Flowers: amber `#E8C86A`, warm yellow `#EFB63F`, pink `#E9899B`, cream `#F6F2E4`
- Terracotta pot body `#C26A45`, pot rim `#A9563A`, pot highlight `#E8C9A0`
- Soil `#4A3B2A`, garden bed soil `#6B5236`
- Grass `#82A85D`, stone/path `#A9A29A`, timber `#C69A63`

### Two families, different rules

**Family A — navigation icons (9).** These always sit on a *dark* background
(`#365A4D` in light mode, `#131A16` in dark mode), beside a text label.

- Draw them **monochrome in the rail ink `#F2E9D6`**, single weight, no fill
  colours. They must read as a set at a glance.
- Optically balanced: same visual weight and size, even though a tree and a cog
  have very different silhouettes.
- Rendered at roughly **18–20px**, so no detail that dies below 20px.

The nine, in order:

1. **Home** — a small house or a potting shed. Warm, welcoming, not a generic roof.
2. **Focus** — a timer. Hourglass or a simple clock face. This is the app's core action.
3. **Catalogue** — an open book, or a plant-press / index card.
4. **Shelf** — a potted plant on a shelf plank, or a shelving unit.
5. **Garden** — a tree, or a small plot with rows.
6. **Journal** — a closed notebook, ideally distinguishable from Catalogue at 18px.
7. **Statistics** — a bar chart, kept organic rather than clinical.
8. **Achievements** — a medal, rosette or ribbon.
9. **Settings** — a cog, softened. Rounded teeth, not a machine part.

Catalogue vs. Journal is the hardest pair — please make them clearly distinct in
silhouette, not just in detail.

**Family B — content icons (17).** These sit on *card* surfaces and must work on
both `#FFFCF5` and `#232A25`.

- These may be **full colour**, using the plant and object palette above.
- Never rely on near-white or near-black alone: every shape needs enough
  mid-tone that it survives on a light card and a dark one. Test both.
- Rendered at roughly **24–52px**, so a little more detail is allowed.

Journal entry types (9):

10. **Seed planted** — a seedling, two leaves, just emerged
11. **Stage reached** — a growing sprig, more established
12. **Plant matured** — a full potted plant
13. **Mutation discovered** — a sparkle or unusual variegated leaf
14. **Achievement unlocked** — a medal (colour version of #8)
15. **Garden expansion** — a plot widening, or a tree with new ground
16. **Level up** — a star, soft-pointed
17. **Expedition completed** — a compass
18. **Generic journal entry** — a notebook page

Empty states and notifications (8):

19. **No plant chosen** — an empty pot with soil, hopeful rather than sad
20. **Nothing on the shelf** — a bare sprig or a leafy branch
21. **Nothing to plant out** — a tree
22. **No statistics yet** — a chart with no bars
23. **Empty journal** — a closed book
24. **No search results** — a magnifying glass over a leaf
25. **Backup / save** — a floppy or an archive box, kept warm and cozy
26. **Ornament removed** — a garden bench or a stone lantern

### App icon (bonus, 27th)

A 256×256 rounded-square app icon, `rx="56"`, on the sage rail colour `#41695A`,
showing a single potted sprout. It must hold a legible silhouette at **16px** in a
Windows taskbar. There is an existing one at `assets/ui/app_icon.svg` that works;
a better-drawn version in the same spirit would be welcome.

### Technical constraints — these are hard requirements

The app is built in **Godot 4.7**, which rasterises SVG through **ThorVG**. That
limits what actually renders:

- **Plain `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<polygon>` with flat
  `fill` only.**
- **No** `<filter>`, `<mask>`, `<clipPath>`, `<text>`, `<use>`, `<image>`, CSS
  classes, or external references. These silently fail or render wrong.
- **No gradients.** If you want tonal depth, stack two flat shapes in slightly
  different tints — that is how the rest of the app's artwork does it.
- Strokes are fine, but prefer converting to filled paths where practical.
- Every colour as an explicit `fill="#RRGGBB"` attribute, not a stylesheet.
- Square `viewBox`. Use `0 0 24 24` for Family A, `0 0 48 48` for Family B, and
  `0 0 256 256` for the app icon.
- Consistent optical stroke weight within each family — around `2` on the 24 grid,
  `3` on the 48 grid.
- No `width`/`height` attributes on the icon SVGs, so they scale freely. The app
  icon may keep them.

### Deliverable

For each icon, give me:

- A short name in `snake_case` (e.g. `nav_garden`, `journal_seed_planted`)
- The complete SVG source, ready to paste into a `.svg` file
- One line on any judgement call you made

Please keep the set visually consistent above all else. A set of 26 icons that
clearly came from one hand is worth far more than 26 individually clever ones.
