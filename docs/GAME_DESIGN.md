# Game design

## Premise

Every plant represents real time the player spent focusing. The product exists to
make hundreds of hours of study or work visually meaningful.

## Core loop

1. Choose what you are working on
2. Choose a plant to grow
3. Start a focus session
4. Time passes
5. Valid focus minutes grow the plant
6. The plant visibly advances through stages
7. Mature plants enter the collection
8. Plants go on the shelf or in the garden
9. Sessions also give XP, achievements, unlocks and statistics
10. Choose the next goal

## Design rules

These are constraints, not preferences. Each one has a corresponding structural
guarantee in the code, listed so a future change cannot quietly violate it.

**Productivity first.** The focus screen stays clean. Game mechanics reward
focusing; they never compete with it for attention.

**No punishment.** Plants never die. Missing a day resets a number and does
nothing else. `StreakCalculator` only ever *returns* integers — it has no ability
to modify anything, so "never punish" is structural rather than a convention.

**No anxiety mechanics.** A streak survives while the most recent qualifying day
is today *or yesterday*, because a day the player has not finished yet is not a
day they skipped. Without this, opening the app at 9am would show a broken streak
every morning.

**Progress is permanent.** Growth never runs backwards. A mature plant stays
mature even if a content update later retunes its requirement upward. There are
tests for both.

**Levels never change the value of time.** XP per focus minute is a flat
constant. There is no multiplier and no bonus tier — that would turn a
productivity tool into a grind.

**Mutations are cosmetic.** They may never increase focus productivity.

**No monetization.** No ads, premium currency, loot boxes, energy systems or
artificial timers. Rarity exists for collection excitement, and basic gameplay
never depends on a random rare drop.

**Never lose legitimate time.** A session ended early is credited for the time
actually focused. Even cancelled sessions are recorded, so interruptions appear
in analytics rather than vanishing.

## Session credit policy

| Outcome | Credit |
|---|---|
| Ran to full duration | Exactly the intended duration |
| Ended early by the player | Actual focused time |
| Cancelled | Recorded, zero credit |
| Below the minimum threshold (default 1 min) | Recorded and XP-eligible, no plant growth |
| Paused | Pause time excluded entirely |
| Interrupted by app close | Offered back to the player, capped at the intended duration, flagged |

Anomalous sessions (machine slept, clock changed) are kept and flagged, never
discarded and never punished.

## Progression

**XP:** 2 per focus minute, 0.25 per break minute. Breaks are rewarded but must
not compete with focusing as an XP source.

**Levels:** cumulative XP for level *L* is `50(L-1) + 25(L-1)²`, capped at 100.
Quadratic, so early levels arrive quickly and later ones represent real
investment without becoming unreachable. Level 2 at 75 XP (~40 minutes), level 10
at 2,475 XP (~20 hours), level 20 at 9,975 XP (~83 hours).

**Growth stages:** derived, never a threshold table. A plant's stage is its
maturity requirement's 0..1 ratio quantized into equal bands — three stages means
exactly thirds. Reaching the last band is not maturity: that is still a full
ratio only, so the final third is the plant filling out and coming into flower.
Flowers are the reward for finishing rather than for getting close.

**Maturity cost:** derived from rarity, never authored per species. Three hours
of focus for a common houseplant, 4h30 uncommon, 6h rare, 8h epic, 10h for the
legendary bonsai. The figures used to be tuned per entry and had drifted into
eleven arbitrary numbers between 100 and 420 minutes — a plant whose cost you
cannot guess from its badge is a plant you cannot plan around.

**Display gate:** a plant can go on the shelf or into the garden once it reaches
stage 1, a third of the way, and finishes growing where it can be seen. Waiting
for full maturity meant a plant spent hours as a row in a list with nowhere to
be, which is the opposite of what a game about watching things grow should do.
Placement has never had anything to do with growth: a displayed plant stays
selectable as the growth target and advances exactly as it would have in the
collection.

**Streaks:** a day counts when its total focus meets the configurable threshold
(default 25 minutes). Breaks do not build a focus streak.

## Not yet designed in detail

Expedition content, mutation genetics, mystery-seed reveal pacing, and the garden
expansion milestone table exist as data structures but have no authored content.
They are scheduled for Milestones 5 and 7 and are deliberately not specified here
in advance of building them.
