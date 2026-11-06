# Learning: a guard's floor constant is TWO write sites, not one — and the mutation battery is the net that proves it

## Problem

While porting `inngest-luks-wrong-volume-alert.test.sh` (#11528, PR #11695) a review round added four `param()` presence rows, so `PRESENCE_ROWS` had to go 39 → 43. The edit tool's first-occurrence `replace` hit the `mutate_floor_red` sed anchor `s/^PRESENCE_ROWS=39$/PRESENCE_ROWS=40/` *before* the declaration at the file's bottom — the sed became `s/^PRESENCE_ROWS=43$/PRESENCE_ROWS=40/`, a DECREMENT that can never trip the floor, while the declaration stayed `39`. Result: the floor-mutation row reported `SURVIVED` and the battery red-flagged its own dispatch row — exactly the self-referential-mute class the row exists to catch.

A second shape from the same round: `param()`'s `^<key> = <ERE>$` whole-line anchoring needs the ERE to cover the ENTIRE value. Handing it a prefix (`var\.betterstack_paid_tier` for a ternary value) produces a red row that looks like a code bug but is an assertion bug — the correct ERE is the full ternary `var\.betterstack_paid_tier \? tonumber\(...\) : null`.

## Solution

- When bumping a guard floor constant, grep for EVERY text occurrence of the old value (`grep -n 'PRESENCE_ROWS=39'`) — the declaration AND the `mutate_floor_red` sed anchor are coupled write sites; change both to `N`/`N+1` respectively, then run the suite so the floor-mutation row re-proves the pair.
- For `param()`-style whole-line pins, copy the value ERE verbatim (including spaces) from the real `.tf` line, not a truncated prefix.
- The failure was caught by the file's own mutation battery (`mutation SURVIVED: DISPATCH: PRESENCE_ROWS raised by one`), not by review — the instrument worked as designed; trust it and rerun it after every constant touch.

## Key Insight

A self-referential assertion (a floor that counts the file's own rows) always carries a hidden second write site — the mutation that perturbs it. A mechanical find-replace of the constant silently neuters the row that guards the constant. The correction is procedural: after any edit to a floor constant, grep for the numeric literal and check every hit is the one intended.
