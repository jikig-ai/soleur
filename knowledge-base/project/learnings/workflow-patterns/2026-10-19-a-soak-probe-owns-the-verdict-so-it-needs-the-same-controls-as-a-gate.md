# Learning: a follow-through soak probe owns a verdict, so it needs a gate's controls (Item I, #7432)

## Problem

Item I removes the infra-step `JOBS: 1` pin in `main-health-monitor.yml` and leaves a 12-run soak probe
(`scripts/followthroughs/jobs1-stopgap-7432.sh`) to decide whether the removal held. The first two probe
drafts passed their own suite and were still wrong in ways only a 17-seat review found:

- The job-log fetch failed on gh 2.102: logs carry ESC bytes and need `gh api --allow-escape-sequences`.
  A fake `gh` that never refused the unflagged call hid it.
- Strikes were counted per run in one place and per RED suite in another.
- A forged RED line in a log could satisfy the accounting; the runner's own tally line is the only
  unforgeable anchor.
- Unanchored width greps, unbounded K, glob expansion on log text and duplicate run ids each let a
  crafted or accidental line change the verdict.

## Solution

- Verdict source is the `main-health-outcomes` check-run annotation, never the run conclusion
  (`continue-on-error` pins it to success).
- Classify each run in a fixed order (width, annotation, killed, clean, accounting, allowlist, strike) and
  pin the precedence of exit codes with reorder mutants (8 of 9 swaps killed, the 9th by a message-only row).
- The fake `gh` is strict: exact arity, and it models the real ESC refusal.
- Every verdict-owning helper gets a positive control (`_selftest_helpers`); exact `MIN_ASSERTIONS` floor.
- Bounds that the soak depends on (`_SUITE_BOUNDS`) ship in a separate PR that must merge first, because an
  edit under `apps/web-platform/infra/` arms the nested infra runner in the tests step and the dispatch
  would no longer measure the cold shape.

## Key Insight

A probe that closes or gates a tracker is a gate. Apply the gate checklist before the review does: a
fake that is more permissive than the real tool, a count with two units, a trusted field parsed from a
region an attacker can write, and a precedence order with no reorder mutants are all the same defect
class as in any other verdict-owning script.

## Session Errors

1. **Scripted splice dropped plan sections; wrong denominator 81/192 (should be 81/269)** — Recovery: restored the sections, recomputed. **Prevention:** diff a doc after any scripted rewrite; recompute a ratio from its named numerator and denominator populations.
2. **Probe log fetch failed on gh 2.102 (ESC bytes)** — Recovery: `--allow-escape-sequences`, ESC-faithful fake gh. **Prevention:** a test double must refuse what the real tool refuses.
3. **Strike unit mismatch, forgeable RED line, unanchored/unbounded parses** — Recovery: `n_other` strike model, runner tally-line check, anchors, caps, `unique_by`. **Prevention:** positive controls and kill rows per verdict-owning helper.
4. **Test slips (env override leaking across rows, surviving K9b mutant, K23 fixture shape, SC2034, no-op rows, malformed mutation)** — Recovery: fixed in place. **Prevention:** run each new mutation row against the unmutated tree first.
5. **Called #10486 "stuck" on a red `test` check; it was the draft-light path failing by design** — Recovery: corrected to the user after the fork showed the cause. **Prevention:** read the check's gating condition before describing a red check as a blocker.
6. **Deleted sibling sessions' `/var/tmp/ship-battery` logs** — Recovery: disclosed; unrecoverable. **Prevention:** never clean scratch paths this session did not create.
7. **Review seat re-delivered its report ~6 times** — Recovery: TaskStop. **Prevention:** stop a seat after the first complete report.

## Tags

category: workflow-patterns
module: scripts/followthroughs, main-health-monitor
