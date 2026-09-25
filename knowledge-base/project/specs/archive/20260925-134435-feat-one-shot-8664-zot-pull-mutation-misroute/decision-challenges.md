# Decision challenges: feat-one-shot-8664-zot-pull-mutation-misroute

Recorded headless by `soleur:plan` plan review (2026-09-25). These are taste calls where a reviewer
wanted to go further than the brief ("small one-shot, one PR"). The default taken is the brief's.
`soleur:ship` renders these into the PR body and files the `action-required` issue.

## 1. The same scorer bug in four sibling mutation batteries

- **Source:** CTO devex review, finding F1 (taste).
- **What:** other mutation batteries score rows with the same early-exit shape this PR removes (a
  log grep piped into `grep -qF --`), so they can flake the same way under the parallel runner.
  Tracked in #8855, which lists the sites, including two a review re-census found outside the
  `infra/` directory (`apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
  `attributed()`, and the `STAY-GREEN` floor in `infra-config-repush-mutation.test.sh`).
- **Default taken:** not folded in. The brief asked for a small one-PR fix, and
  `apex-single-node-replace-mutation.test.sh` is already in sibling PR #8763's diff. The work phase
  filed #8855, which makes a shared scorer library the default remedy.
- **Alternative:** fold the five sites outside #8763 into this PR. Each is a one-line change, plus
  adding each file to `.claude/hooks/grep-q-pipe-guard.test.sh`'s named list.

## 2. Converting the guard's 19 `| head -1` pipelines to `grep -m1`

- **Source:** DHH review, finding 1.
- **Default taken:** declined. The 7 unguarded sites write at most 135 B each, so they are measured
  unreachable, and the 12 others already carry `|| true`. The widened header sentence names the
  class for future edits.
- **Alternative:** convert all 19 in this PR, so that the whole class is gone from the guard file.
