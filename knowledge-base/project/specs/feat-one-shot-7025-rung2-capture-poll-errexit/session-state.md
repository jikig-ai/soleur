# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-30-fix-rung2-capture-poll-errexit-plan.md
- Status: complete

### Errors
None. CWD verified on the first attempt. All named gates green at baseline (43 / 58 / 30 / 101 assertions).
Two self-caught corrections during planning: `lane` initially set to `single-domain` when no branch `spec.md`
exists (fail-closed to `cross-domain`); `deploy-docs.yml` initially miscounted as 5 unguarded sites, measured as 4.

### Decisions
- Fix form chosen by measurement: `set +e` … `rc=${PIPESTATUS[0]}` … `set -e`. Both obvious alternatives are
  disqualified — `|| true` yields `PIPESTATUS[0]=0` (every TRANSIENT reads PASS), and `|| rc=$?` misreports a
  `tee` failure as a host fatal. The ordering is load-bearing: `set -e` is a builtin, so re-arming BEFORE the
  `PIPESTATUS` read produces a silent false PASS (exit 0, 1 attempt, green summary, host never booted) — a
  worse outcome than the bug being fixed.
- The regression guard executes rather than greps. Fixed and buggy bodies have identical grep counts (1/1/1)
  for `seq 1 N`, `PIPESTATUS`, `capture_rc`, proving a text guard is blind here. Arms 13/13b/13c/13e extract
  the real step body by `id: capture` and run it under `bash -e` with stubs; three mutation arms must go RED.
- A standalone repo-wide lint was cut (4 of 6 reviewers agreed). Over 637 `run:` bodies the drafted rule
  matches 1 — the bug itself — and 0 of the 3 sibling bugs. Scoped to arm 13d instead; recorded as a
  User-Challenge since it trims operator-requested scope.
- Two items moved inline rather than deferred: the birth-job poll (same defect, would be hit on the very next
  dispatch) and the `teardown_only`/`dry_run` survivor-gate skip.
- Scope limits held: no banner change, no host birth, no evidence file. `Ref #7025` with no closing keyword.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `Explore` x2 (guard-suite mapping, interlock mapping); review panel `dhh-rails-reviewer`,
  `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto`
- Verification: local reproduction under `bash -e` against the extracted workflow body; `gh issue/pr view`;
  `shellcheck` probe; python/`yaml.safe_load` sweeps over 637 `run:` bodies; deepen-plan gates 4.5-4.10

## Upstream context
Produced while resuming the git-data host birth (ADR-149). Rung 1 (dry run) PASSED — `plan is clean:
14 create(s), all rehearsal-scoped; 0 destroys`. Rung 2 (real rehearsal, Actions run 30560266736) returned
`RUNG2_CAPTURE_VERDICT=2`; teardown ran and the independent Hetzner survivor check passed, so no orphan host.
The birth sequence resumes at rung 2 once this fix merges.
