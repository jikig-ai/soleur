# Decision challenges: feat-one-shot-8664-zot-pull-mutation-misroute

Recorded headless by `soleur:plan` plan review (2026-09-25). These are taste calls where a reviewer
wanted to go further than the brief ("small one-shot, one PR"). The default taken is the brief's.
`soleur:ship` renders these into the PR body and files the `action-required` issue.

## 1. The same scorer bug in four sibling mutation batteries

- **Source:** CTO devex review, finding F1 (taste).
- **What:** four other batteries in `apps/web-platform/infra/` score rows with the same early-exit
  pipe this PR removes (`grep … "$log" | grep -qF -- "$expect"`), so they can flake the same way
  under the parallel runner. The six sites are in:
  - `apex-single-node-replace-mutation.test.sh:178`
  - `ssl-full-mitigation-mutation.test.sh:365`
  - `web-host-provisioner-parity-mutation.test.sh:289,875,1203`
  - `www-apex-canonicalizer-mutation.test.sh:560`
- **Default taken:** not folded in. The brief asked for a small one-PR fix, and
  `apex-single-node-replace-mutation.test.sh` is already in sibling PR #8763's diff. The work phase
  files one tracking issue listing the six sites, the capture-and-glob fix, and the option of a
  shared `infra/lib/mutation-scorer.sh`.
- **Alternative:** fold the five sites outside #8763 into this PR. Each is a one-line change, plus
  adding each file to `.claude/hooks/grep-q-pipe-guard.test.sh`'s named list.

## 2. Converting the guard's 19 `| head -1` pipelines to `grep -m1`

- **Source:** DHH review, finding 1.
- **Default taken:** declined. The 7 unguarded sites write at most 135 B each, so they are measured
  unreachable, and the 12 others already carry `|| true`. The widened header sentence names the
  class for future edits.
- **Alternative:** convert all 19 in this PR, so that the whole class is gone from the guard file.
