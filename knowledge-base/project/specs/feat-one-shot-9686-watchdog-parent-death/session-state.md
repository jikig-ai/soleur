# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9686-watchdog-parent-death/knowledge-base/project/plans/2026-10-07-fix-test-all-parent-death-watchdog-debounce-plan.md
- Status: complete

### Errors
None. (The issue's cited location "~line 3806" had drifted — the `_RUN_WD` watchdog block actually sits at ~4303–4393 on origin/main `66717b6f7f`; the plan anchors on symbols, not line numbers, and records the drift in Research Reconciliation.)

### Decisions
- Debounce design: single per-poll `_wd_bad` verdict over the three parent legs (`kill -0` ESRCH / `stat==Z*` / `lstart` mismatch), `_wd_fails` consecutive counter gated by new knob `SOLEUR_TEST_ALL_WD_FAILS_N` (default 3, floor >=1), plus a deciding-poll re-verify that resets on a recovered read — implementing the issue's suggested fix verbatim.
- Inferred scope items (flagged in Scope Check): runner-death leg gets the same counter discipline, a per-failure `WARN ... (leg=..., k/N consecutive) (#9686)` diagnostic, and a soak followthrough probe (`scripts/followthroughs/watchdog-debounce-soak-9686.sh` + registered `.test.sh`).
- Test-first ordering (cq-write-failing-tests-before): Phase 1 adds ps-PATH-shim arms that MUST be red pre-fix; `kill -0` is a builtin and unshimmable — documented test-seam limit.
- Invariant pinned: consecutive-only, never cumulative/N-of-M — sustained failure always reaps; reap order, `parent process gone` message text, opt-out banner, and disarm stay byte-identical.
- Gates: `## Domain Review` = none (CI-machinery fix, no UI surface); User-Brand threshold `none`; Guard Contract with 7-row mutation matrix (lint-guard-contract.py green); #8659/#7942 acknowledged non-overlapping.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan (deepen ran inline; halts 4.6–4.12 evaluated PASS)
- Commands: gh issue view/list, cloud-detect.sh (local), lint-guard-contract.py (green), git grep/log/show
- Commits: 237d5987f0 (plan + tasks), 0064c6bfe3 (deepen amendments)
