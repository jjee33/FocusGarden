# Coding conventions

## GDScript

- **Static typing everywhere.** `var count: int = 0`, `func f(x: float) -> String:`.
  Typed loop variables too: `for plant: PlantInstance in plants:`.
- Tabs for indentation (Godot standard).
- `snake_case` for functions and variables, `PascalCase` for classes,
  `SCREAMING_SNAKE_CASE` for constants.
- `_leading_underscore` for private members.
- Two blank lines between top-level functions, one between methods in a class.
- File order: `class_name`, `extends`, docstring, signals, enums, constants,
  exports, variables, `_ready`, public methods, private methods.

### Two Godot 4.7 traps

**Inferred `Variant` is an error, not a warning.** `var x := returns_variant()`
fails to compile with "the variable type is being inferred from a Variant value".
Write `var x: Variant = returns_variant()` explicitly.

**GDScript has no implicit string concatenation.** Adjacent string literals are a
parse error — unlike Python. Use `+`:

```gdscript
screen_body = (
    "First part of the sentence "
    + "and the rest of it."
)
```

## Documentation comments

`##` doc comments explain **why**, not what. The signature already says what.

Prefer recording the reasoning that is expensive to rediscover: why an ordering
matters, what breaks if a rule is violated, what an earlier version got wrong.
`atomic_file.gd` documents the exact failure its step order prevents, because
someone will eventually be tempted to simplify it.

Reference the spec section (`§36`) where a requirement drove a decision.

## Rules

**One implementation per calculation.** Listed in
[ARCHITECTURE.md](ARCHITECTURE.md#the-single-implementation-rule). Never re-derive
a level, a stage threshold or a duration format anywhere else.

**No magic values.** Colours and spacing come from `DesignTokens`; gameplay
numbers are named constants next to the logic that uses them.

**No UI logic in autoloads. No game formulas in UI.**

**`systems/` may not reference autoloads.** It is what makes the test suite
possible. `ui/theme/motion.gd` is the single documented exception.

**Enums over string literals** for anything with a fixed set of values, so a typo
is a parse error rather than a silent no-op.

**Ids are `StringName`** for content (`&"monstera"`), `String` for player-data
ids.

**One-time events return `bool`.** `grant_unlock()`, `discover()`, `unlock()` and
`grant_expansion()` all return `true` only on the first call, so callers can fire
a celebration exactly once without tracking state themselves.

**Deserialization is defensive.** Everything from JSON goes through `DictUtil`,
and out-of-range values are clamped or defaulted at the boundary.

## Before you change something

- **Modifying a system?** Read the existing file. Do not assume its contents.
- **Adding a manager?** Check whether an existing system already owns that
  responsibility.
- **Changing a data format?** Bump `SaveData.CURRENT_VERSION` and add a migration
  step plus a test.
- **Deleting or renaming?** Search for references first.
- **Using a new engine API?** Add it to `tests/api_probe.gd`.
- **Changing a design token?** Re-bake the theme and commit the `.tres`.
- **Finished?** Run the boot check, the API probe and the test suite. For UI
  work, capture screenshots and actually look at them.

## Avoid

Giant scripts. Circular dependencies. Deeply nested scene access
(`get_node("../../Foo")`). Repeated business logic. Magic strings. Premature
abstraction. Marking anything complete because a placeholder exists.
