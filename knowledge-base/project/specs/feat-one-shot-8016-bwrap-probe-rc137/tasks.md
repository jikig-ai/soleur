# Tasks: fix deploy bwrap probe docker-exec PDEATHSIG race (#8016)

Plan: knowledge-base/project/plans/2026-10-01-fix-deploy-bwrap-probe-sigkill-canary-rollback-plan.md

## Phase 1: Setup and evidence

- 1.1 Re-run the Docker repro loop (plan Phase 0) in a container with bwrap and setpriv; record the with-flag, without-flag and setpriv rates for the PR body

## Phase 2: RED tests (before any production edit)

- 2.1 ci-deploy.test.sh: add ONE pre-case hook in the mock docker (before the mode dispatch, next to the pgrep block) that appends one joined line per exec with any bwrap arg to MOCK_DOCKER_ARGV_LOG; the log lives in a caller-owned mktemp -d, truncated per scenario, exported inside the scenario subshell
  - 2.1.1 Guard 2 assertion helper: space-padded whole-token match; requires --unshare-pid, --dev /dev, --bind / /; forbids --die-with-parent; refuses an empty log; failure prints the token and the log; guard grep captures with || true; bump CI_DEPLOY_ASSERT_FLOOR
  - 2.1.2 Guard 1 function bwrap_exec_flag_violations (join continuations, drop comment lines, command-token bwrap match, docker exec only) with two inline must-flag fixtures and three must-pass inputs
  - 2.1.3 Confirm these fail on the current tree
- 2.2 audit-bwrap-uid.test.sh: exec mock arm appends argv to ${DOCKER_EXEC_ARGV_LOG:-/dev/null} (path passed through run_case); assert --die-with-parent absent and --unshare-user --unshare-pid present; confirm it fails now

## Phase 3: Core implementation

- 3.1 ci-deploy.sh: drop --die-with-parent from the probe statement (about line 3987); keep the || BWRAP_RC=$? capture, line shapes and final_write_state untouched
- 3.2 ci-deploy.sh: rewrite the NOTE block to one rule line plus a pointer to the learning file; delete the stale 97.6 percent figure here and in the ci-deploy.test.sh comment (~line 917)
- 3.3 audit-bwrap-uid.sh: drop --die-with-parent (lines about 75-80)

## Phase 4: Docs

- 4.1 Learning file bug-fixes/2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md (mechanism, measurements, repro loop, rule)
- 4.2 canary-probe-set.md: rc=137 row marks the signature historical (post-fix any 137 is unexplained, discriminate by ms/cstate/err_chars, next suspects OOM at the canary cap and a host reaper); closing paragraph states no automatic reopen and names #9342; triage steps use only the no-SSH probes
- 4.3 Post-mortem: two-line pointer to the learning

## Phase 5: Verification

- 5.1 Live loop on the probe argv extracted from ci-deploy.sh: 5000 execs, expect 0 nonzero; no-SYS_ADMIN control expects rc=1
- 5.2 Run ci-deploy.test.sh and audit-bwrap-uid.test.sh; shellcheck touched scripts
- 5.3 Apply Guard 2 mutation rows 1-4, confirm RED, revert
- 5.4 python3 scripts/lint-guard-contract.py on the plan; bash plugins/soleur/test/c4-count-parity.test.sh
- 5.5 Post-merge informational read: confirm script-sha parity for web-1 and web-2 and SANDBOX_PROBE_OK rows (apply is fail-closed across both hosts)
- 5.6 PR body: Closes #8016, measurement tables, 0 of 5000 result, statement that this removes a flag
