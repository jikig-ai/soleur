# Learning: a pinned floor needs its value pinned, and an unreachable backstop must be driven through a mutated copy

## Problem

The #12180 soak probe could not reach exit 0 (PR #12244, tracker #12189): it counted incident 1048111600 (old alert
shape, resolved before the apply) as a recurrence forever, and its pass path demanded that the anchor was resolved by
the alert when it had been resolved through the API. The repair pinned the apply time as a stored literal floor
(`APPLY_FLOOR_EPOCH`), replaced three age gates by one soak clock (`quiet_since`), made the anchor's resolve actor
informational and made the warehouse rows read verdict-bearing on the pass path. The review then found that the
repair's own verification and prose repeated the defect classes it was written to remove.

## Solution

- The stored floor is the load-bearing constant, so the suite pins its VALUE (an ISO conversion of the literal read from
  the probe, the same instant in the runbook) and runs once with every default seam empty on a clock derived from the pin.
  Without that, a pin moved by an hour passed every row, because every other row passes the floor through a seam.
- Two internal backstops no input can reach (a verdict word/exit pairing refusal and a final conjunction of the good
  values before `verdict pass 0`) were first "pinned" with `grep -qF` on their messages. A one-line edit disabled both
  with the suite green. They are now DRIVEN: the suite copies the probe, edits exactly one occurrence (`make_mutant`
  asserts the anchor count) to hand the guard a bad state, and requires exit 3.
- A canary/pin cross-check that only qualifies canary evidence must not outrank findings about production: it is
  recorded and raised after the production-alert and recurrence blocks (CTO ruling). Every setup check that exits 3 first
  hides a worse verdict behind a milder one.
- A fixture edit helper (`patch`) must fail when the filter changes nothing, and a row that claims a scoping property
  needs a fixture precondition proving the scoped records really carry the patched values.
- Prose: an inference is not OBSERVED. Only `resolved_by` null on incident 1048111600 was observed; "auto-resolved" and
  "the alert recovered" were readings of it. A re-pin after a reshape of the alert is a follow-up commit measured from
  the apply run, because the reshape PR cannot know the apply time, and a forward re-pin while the canary exists trips the
  cross-check at every sweep.

## Key Insight

A stored value that decides a verdict has two failure surfaces, the value and the wire that reads it; a suite that passes
the value in through a seam on every row pins neither. And a guard that exists only for states no input produces cannot be
verified by reading it: hand it the state by mutating a copy of the code, then assert the refusal.

## Session Errors

1. **The first CTO soak origin (alert `updated_at`) was falsified by two live reads** (forwarded from planning) —
   Recovery: sent the measurement back, ruling withdrawn, pinned literal floor instead — Prevention: measure a field's
   behaviour before ruling that a clock can be read from it (`hr-technical-fork-is-not-an-operator-question` still
   applies, with the evidence attached).
2. **`patch` was called with jq args before the filter in two rows, so two fixtures silently did not apply** — Recovery:
   corrected the argument order after the first green-looking run printed "fixture patch did not apply" — Prevention: a
   fixture helper fails loudly on a no-op, now enforced by `patch` itself and its negative control.
3. **An empty or whitespace roster exited 5, not 3** — Recovery: `read_rows` treats an empty roster as unknown —
   Prevention: the suite row for an unproven roster (caught by the suite).
4. **The incidents-pagination row was vacuous** (the walk breaks at the anchor's page before it reads `pagination`) —
   Recovery: remove the anchor from the fixture so the walk continues — Prevention: for any "malformed X is refused" row,
   first prove the code path reads X at all (delete the guard and require RED).
5. **My own mutation `if false; then :; elif …` was equivalent and "survived"** — Recovery: replaced by `if false && …`
   — Prevention: before labelling a survivor, check the mutated program still differs in behaviour (the survivor rule
   in `review/SKILL.md` already covers this).
6. **Mutation sandboxes outside the repo layout turned two rows red at baseline** (the runbook-date and
   `variables.tf` rows read repo-relative files) — Recovery: replicate those files beside `scripts/followthroughs/`
   in the sandbox — Prevention: run the unmutated control in the sandbox and read its FAIL count before any mutant
   (covered by the subtree-sandbox bullet in `review/SKILL.md`).
7. **Prose stated an inference as OBSERVED and an unverified outcome as fact** (found by the git-history, architecture
   and pattern seats) — Recovery: reworded, with the unmeasured items listed — Prevention: for each causal or universal
   sentence a diff ADDS, name the command that would falsify it (the existing Phase 0.5 rule); here it was not applied to
   the author's own header comments.
8. **The local affected gate queued behind a sibling worktree's full-gate lock a second time** — Recovery: stopped my
   run (never the sibling's), CI is the battery, stated in the review-evidence comment — Prevention: none new; the
   contention is tracked and `--capacity` reports it before launching.
9. **Stop-hook feedback twice for closing text naming an unperformed action, a duplicate monitor, and markdownlint run on
   an ignored directory** — Recovery: acted or ended with a `Paused:` line; stopped the duplicate; read
   `.markdownlintignore` — Prevention: none new.

## Tags

category: logic-errors
module: scripts/followthroughs/egress-gw-probe-silent-12180.sh
related: [[2026-11-06-an-absence-alert-on-a-zero-filling-evaluator-must-count-the-missing-and-the-fix-narrowed-its-own-input]]
