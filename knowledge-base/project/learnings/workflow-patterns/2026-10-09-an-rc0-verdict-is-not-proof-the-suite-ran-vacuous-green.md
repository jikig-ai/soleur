---
module: web-platform deploy pipeline (apps/web-platform/infra/ci-deploy.sh, test harnesses)
date: 2026-10-09
problem_type: workflow_issue
component: test_infrastructure
symptoms:
  - "a canary verdict classified purely on process rc is vacuously green when the suite collects zero tests"
  - "vitest exits 0 when every collected test is skipped — passWithNoTests only covers zero FILES, not zero tests"
  - "a test helper whose last statement is a metadata printf returns printf's rc, not the SUT's"
root_cause: process
resolution_type: fix
severity: medium
issue: 2640
pr: 9809
tags: [vacuous-green, canary, vitest, soak, verification, guard-shape]
---

# An rc-0 verdict is not proof the suite ran — classify canary output on a tests-executed marker, not exit code alone

## Problem

The #2640 deploy probe classified `docker exec vitest` exit 0 → `pass`.
Two vacuous-green channels a pure-rc verdict cannot see:

1. **All-skipped is green.** `vitest run` exits 1 on zero *matched files*
   (`passWithNoTests` defaults false) but exits **0** when it collects files
   and every test inside skips. A future `skipIf`/`runIf` regression (or a
   tier-filter typo that slips the closed-set guard) would measure nothing
   and still record `pass` — the soak accumulator would promote a guard that
   never ran. Verified empirically: `-t <no-match>` → `Tests 16 skipped` →
   rc 0.
2. **The harness can hide it too.** `run_cwi_deploy` ended with a metadata
   `printf` — so it returned printf's rc 0 and every caller's
   `&& rc=0 || rc=$?` measured nothing. The "deploy stays green on a red
   verdict" assertion was vacuous until the helper `return`s the subshell's
   rc.

## Fix

- rc 0 additionally requires the reporter's nonzero-passed marker:
  `[[ "$out" =~ Tests\ +[1-9][0-9]*\ passed ]]`; absent →
  `workspace_isolation_failed` (`reason=vacuous_green_no_tests_passed`) —
  loud, never promoting. Bash `=~`, not `printf | grep -q`: under
  `set -o pipefail`, grep's `-q` early-exit SIGPIPEs the printf and the
  pipeline reports 141 *on a match*.
- Harness helpers that wrap a run under test must propagate the wrapped
  command's rc explicitly (`( ... ) && src=0 || src=$?; …; return "$src"`),
  never let a trailing metadata emit become the effective status.
- Mock fixtures feeding line-selection logic need real newlines: ANSI-C
  `$'...\n...'` quoting through the eval channel — `printf '%s'` does not
  interpret `\n` escapes, so single-line blobs only prove substring presence.

## Sibling learning worth pairing

Mock arms that key on an argv token (`*vitest.canary.config.ts*`) can never
observe wrappers around the command (`timeout`, `env -i`, `nice`). Pin those
with a static source grep row, not a mock assertion — the mock can't see them
by construction.
