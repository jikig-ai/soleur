# Learning: a new telemetry field's reading guide must enumerate every verdict path, including the catch arm

## Problem

PR #11441 added `create_offered` to the create-arm outcome marker so an operator could tell how many patterns the
model was offered (the third live-fire declined with `patterns_open=7` and nobody could say whether the model saw all
seven; derived afterwards: six, one pattern was owned by an open edit PR). The code was a four-line stamp. The review
found about twenty defects, and the substantive ones were all in the reading guide, not the code:

- "Whenever a model call was made it is exactly the number the model saw" was false on `model-invalid/internal` (the
  step's catch arm returns no count even when a call was already spent) and loose on `model-invalid/transport`.
- The "absent on week-cap / index-empty" list omitted that same catch arm; four of seven seats found it independently.
- `persist/clone-missing`, `budget` and `slug` were listed as pre-call refusals but are also raised after a spent call
  (by the persist step and by the post-call content gates), so the field alone cannot tell the two sides apart.
- Fixing the reading guide deleted a caveat that was still true (the cost row for the create call shares its source and
  run id with the edit and clustering calls).

## Solution

Before writing a reading guide for a new marker field, list every verdict the emitting function can return, including
the `catch` arm, and write one row per path: "carries the field / does not / carries it with a different meaning". Then
grep the guide for universal words ("whenever", "exactly", "every") and falsify each against that list. The same applies
to a field's ABSENCE list: absence has more causes than the ones you were thinking about (old memo, early refusal, step
defect).

Smaller lessons from the same session:

- A strip that removes the new field before a downstream consumer is only worth keeping if a test can observe it. The
  mutant that deleted the strip survived because the consumer reads named fields only; deleting the strip was the fix.
- A source-text assertion of the form `slice(step, assign).toMatch(/\}\);\s*\n/)` is satisfied by any `});` in the
  slice. Behavioural tests plus the census guard already pinned the property; the text test was deleted.
- A count that is a set difference needs a fixture where the two sets overlap and one with stray members, or the
  arithmetic form (`patterns - sameRun - ledger`) is indistinguishable from the filtered set.
- Committing while a full affected gate is running moves HEAD under the runner (the runner flags any HEAD movement as a
  suite writing to the repo); land review fixes before the battery or after it.

## Probe result recorded for the investigation (#10550)

An offline probe (spend-capped `ci` config, no cost markers, no GitHub writes, 5 calls) over the real create prompt
and the real skill population produced a create in 5 of 5 calls; the server-side gates refused 4 of them: 3 on
`prefer-patch/nearest-not-top3` (the model's `nearest_skill` ranked 10, 22 and 32 against a limit of 3, a ranking the
model is never shown), 1 on a shape rule (`instruction-risk`). Adding the pattern bodies (arm 1) did not change that.
So the live-fire's 30-token decline is not evidence that the model cannot propose a skill, and the `nearest_skill`
top-3 gate is the first measured candidate for a behaviour change. This PR ships only the count; that follow-up needs a
separate ruling and a live-fire to measure.

## Session Errors

1. **A git commit command was blocked by the PreToolUse repo-resolution hook because the path was held in a variable.**
   Recovery: re-ran with a literal absolute path. Prevention: write `git -C <literal path> commit` or `cd <literal>`
   as its own command; never `$D`/`$(...)` paths in a commit command (already enforced by the hook).
2. **Committed twice while the affected gate was running**, invalidating its read-only boundary check; killed the run
   and re-planned it. Prevention: the work skill already says not to write during a full-gate run; check
   `ps` for the runner before every commit in a gate window.
3. **Launched `test-all.sh --print-selection` into a queue behind four other worktrees' runs**, which hung for minutes.
   Prevention: run `--capacity` first and skip the preview when contended.
4. **Wrote a wrong assertion (a `toHaveProperty` with a spread that asserted presence for the absent case)** and a
   test that leaked state across cases (`createReply` not reset). Both caught by the next run. One-off.
5. **Reading guide claimed "exactly the number the model saw" and omitted the catch arm** (see Problem). Prevention:
   enumerate verdict paths before writing the guide (above).

## Tags
category: workflow-patterns
module: compound-promote
