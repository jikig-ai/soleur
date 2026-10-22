# Learning: a hostile fixture for a "stop sourcing this file" fix must put the payload in the VALUE the fix reads (F5 of #9639)

## Problem

F5 replaced `. /etc/default/webhook-deploy` (root sourcing a deploy-owned file) with a `sed` read of the one
`DOPPLER_TOKEN=` line in two scripts. The first test set looked complete: a hostile fixture (`set -x`, `touch PLANT`,
`DOPPLER_TOKEN=tok`) that must not execute, a negative control that restores sourcing and must execute it,
non-canonical and empty/absent fixtures, a static no-sourcing row. Both suites were green and the author's first
mutation pass reported the revert killed.

The test-design seat then found seven surviving mutants. The sharpest: `eval "DOPPLER_TOKEN=$_t"` (eval only the
matched token line) passed every hostile row, because the planted payload sat on the neighbouring lines and never on
the token line the fix reads. A fix that stops sourcing the FILE and still evals the VALUE would have shipped green.

## Solution

- Put the payload in the value: `DOPPLER_TOKEN=$(touch PLANT)` and the backtick form must arrive literally and never
  execute; run the same fixture through the sourcing control, which must execute it.
- Vary the fixture axes the fix's regex is sensitive to: the token line first (production order) with later keys, a
  trailing commented `# DOPPLER_TOKEN=`, and a `DOPPLER_TOKEN_OLD=` prefixed key kill `sed` without `-n`, an
  unanchored match and a prefix match.
- Pin cardinality of the observable: make the stub append one line per call and assert one value line per doppler
  call, which kills dropping `| tail -n 1` (the value-equality row alone still passes under that mutant).
- Test both directions of the no-export semantics: a run with an inherited exported token and one with none (the read
  must stay unexported), and empty/absent fixtures that must keep the inherited token.
- Define a shared regex once; a non-vacuity row that carries its own copy of the pattern proves the copy, not the guard.

## Key Insight

When a fix changes WHERE untrusted data is consumed (file → one value), the hostile case is the data in the new
consumption point, not the data the old path executed. A fixture modelled on the old defect cannot see a fix that
moved the same hazard one level down.

## Session Errors

1. **`check()` labels containing backticks were command-substituted by its `eval`** — Recovery: reworded the label. **Prevention:** no backticks in assertion labels that pass through `eval`; the repo's commit-message backtick trap applies to any quoted-then-evaluated string.
2. **`\x27` inside a single-quoted bash condition is literal text, not an apostrophe** — Recovery: built the sample with `$'...'` in a variable. **Prevention:** put quote-bearing samples in a variable, never inside a single-quoted `eval` condition.
3. **A `shellcheck disable` directive before `a; b` covers only `a`** — Recovery: split the statements. **Prevention:** one statement per line when a directive must cover it.
4. **A scripted edit's `assert count == 1` aborted on an escape mismatch** — Recovery: re-ran with a raw string. **Prevention:** keep the count assertion (it prevented a silent no-op) and print the changed line back.
5. **Bulk-ticked every `tasks.md` box with `sed`, so "refresh the stale comments" and "file a tracking issue" read as done when they were not** — Recovery: review caught it; the comments were refreshed and 4.2 was reworded. **Prevention:** the work skill already forbids bulk-toggling checkboxes; tick each box from its own verified command.
6. **First hostile fixture put the payload on neighbouring lines, not in the value** — Recovery: added the value-payload rows and controls. **Prevention:** per fix, ask which new consumption point the data now reaches and fixture it there.
7. **The feature worktree was reaped mid-postmerge of the previous PR, so monitors lost their working directory** — Recovery: re-armed them from `/var/tmp` with `gh -R`. **Prevention:** run post-merge monitors from `/var/tmp` or a detached `origin/main` worktree (already in ship/postmerge).
8. **`rm -rf "$D"` was blocked by the protected-location hook while the cwd was the worktree** — Recovery: used a file instead of a directory. **Prevention:** scratch files, not scratch directories, when the cwd is a worktree root.

## Tags
category: security-issues
module: apps/web-platform/infra (cron-egress-enforce-probe, soleur-host-bootstrap)
