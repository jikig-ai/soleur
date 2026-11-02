# Learning: a cap's reachable maximum is set by the tightest downstream gate, and a scan result must record what it was asked

## Problem

Two defects in one PR (#11157, Ref #10552) had the same root: a statement was derived from the component being
changed instead of from the whole path it sits on.

1. **The cap.** A model-written SKILL.md line cap was raised from 500 to 1000 characters, and the ADR and the DPIA
   addendum said "a SKILL.md edit can carry up to 20 lines of 1000 characters". The apply step's pre-existing
   `proposed_diff_unified.length > MAX_DIFF_BYTES` (16,384) refuses a 20-line diff of that size, so the reachable
   maximum is 16 full lines, and the refusal happens after the paid model call. Six documents quoted the validator's
   number. Three review seats found it independently. The gate is a LENGTH check, so the unit is characters, not
   bytes — the first correction said "bytes" and a security seat had to fix that too.
2. **The verdict.** `skillConflictVerdict` returned `clear` for any target absent from `changed` when `incomplete`
   was null. The scan result recorded what it found but not which targets it had been asked about, so a target the
   scan never covered read as "no conflict". Latent today (the handler builds the target set from the same
   proposals), but the one invariant keeping it latent lived in a comment. Two seats flagged it in round one.

## Solution

- For a cap, trace the whole path and quote the minimum: validator -> diff size gate -> PR. Write the derived
  maximum ("at most 16 full lines; larger is refused `diff-size-exceeded`"), not the component's own constant.
- For a verdict, make the input self-describing: the scan result carries `scanned`, and a target outside it is
  `unverifiable` (bound `targets`), never `clear`. One boolean (`needsSkillGuard`) now drives both the scan and the
  verdict, and the tripwire branch is documented as unreachable-today.
- A bound that fires only on a FULL final page needs the partial-page fixtures too (250 PRs, 950 files, exactly 150
  requests), and a "stops the list" test needs a fixture whose next page would be read if the break were lost.

## Key Insight

"What does this component accept" and "what can reach production" are different numbers whenever a later stage has
its own limit; documentation and tests written beside the component quote the first. Likewise a function that
answers "is X clear" must be able to tell "checked and clear" from "never checked": if the input does not carry the
question it was asked, absence reads as success.

## Session Errors

See the companion learning dated 2026-10-26 (`...a-ruling-row-named-the-ruler-before-the-ruler-was-asked...`) for the
full session error list; none is specific to this insight.

## Tags
category: logic-errors
module: apps/web-platform/server/inngest/functions/cron-compound-promote
