# Tasks: per-PR monitor lock (P4c of #10924)

Plan: knowledge-base/project/plans/2026-10-27-feat-per-pr-monitor-lock-plan.md
Ref #9757, Ref #10924 (no closing keyword). Draft PR #11286.

## Phase 0: RED first

- [ ] 0.1 Create plugins/soleur/test/monitor-lock.test.sh with the INSTRUMENT self-test, FLOOR, unit arms and integration arms (stubbed gh and ps; owning trap before sourcing test-helpers.sh)
- [ ] 0.2 Export SOLEUR_MONITOR_LOCK_DIR="$STUB/locks" in plugins/soleur/test/monitor-pr-checks.test.sh
- [ ] 0.3 Run both against the unmodified script; confirm RED for the right reasons (no lib, no rc 4)

## Phase 1: the lib

- [ ] 1.1 Create plugins/soleur/scripts/lib/monitor-lock.sh: _ml_dir, _ml_key (repo normaliser, + join), _ml_ident (TZ=UTC LC_ALL=C), _ml_alive (ps -p, not Z, lstart)
- [ ] 1.2 monitor_lock_acquire (ln -s, compare-before-remove reclaim, one retry, grace x2 on a live holder, rc 0/1/2 + ML_STATE/ML_WHY/ML_HOLDER_*)
- [ ] 1.3 monitor_lock_release (readlink-equals-ours, early return, never branches on $?); bash 3.2 and set -u safe

## Phase 2: wire the script

- [ ] 2.1 Source the lib after ERRTMP (absent -> UNAVAILABLE line + no-op release)
- [ ] 2.2 Replace the inline EXIT trap with one _cleanup (release first, then rm ERRTMP); no INT/TERM trap
- [ ] 2.3 Add acquire_or_exit between the trap and the loop; rc 4 DUPLICATE line; loud UNAVAILABLE and DISABLED lines; ${REPO_ARG[1]:-}
- [ ] 2.4 Update header, Usage block (--help lists rc 4 and SOLEUR_MONITOR_LOCK) and the exit-code sentence

## Phase 3: GREEN and mutants

- [ ] 3.1 Make the unit and integration arms pass; set FLOOR to the measured count
- [ ] 3.2 Add the 10 sed mutants on a copied tree (killed -eq 10), plus the assertion-only checks (rc 4 exactly, token-absence with control, root-gated pid-1 arm)

## Phase 4: callers

- [ ] 4.1 plugins/soleur/lib/harness.ts claude pollInstructions: ownership-branched rc-4 prose (one place)
- [ ] 4.2 plugins/soleur/skills/drain-prs/SKILL.md: one sentence in the Arming returns at ENQUEUE paragraph

## Phase 5: verify

- [ ] 5.1 monitor-lock.test.sh, isolation-edited monitor-pr-checks.test.sh (detached), cd plugins/soleur && bun test test/harness.test.ts
- [ ] 5.2 c4-count-parity, lint-orphan-test-suites, lint-trap-tempfile-ownership, technical-ruling-gate --branch, lint-guard-contract, markdownlint
- [ ] 5.3 Run the discoverability probe command from the plan; expect SOLEUR_MONITOR_LOCK_OK

## Phase 6: ship

- [ ] 6.1 soleur:ship; PR body Ref #9757 / Ref #10924, ## Changelog, semver:patch; gh pr merge <N> --squash --auto
- [ ] 6.2 git diff --name-only origin/main...HEAD lists no apps/**, registry-restore-from-ghcr.sh, .github/workflows/**, .claude/hooks/**; if apply-web-platform-infra.yml appears, stop and ask the operator
- [ ] 6.3 After merge: tick the P4c box in #10924; do not close #10924 or #9757
