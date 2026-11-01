# Session State

cto_spawns=1

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11648-fast-tier-demotion/knowledge-base/project/plans/2026-11-01-chore-fast-tier-always-on-demotion-plan.md
- Status: complete

### Errors
- Exec-tool CWD does not persist between calls — resolved by passing `workdir` / explicit `cd` + `git -C` on every call.
- `git commit` blocked once by the main/master commit guard (resolved the bare repo's `main` HEAD); retried with `cd <worktree> && git -C <worktree> commit`.
- Collision precheck flagged PR #11779 (this branch's own draft PR — not foreign work) and 7 foreign `test-all.sh` processes belonging to sibling pipeline worktree `feat-one-shot-11556-epic-ci-time-batch` (disjoint files; plan prices from CI artifacts, not local wall-clock).
- No nested subagent tool available to the planning child (depth-1 harness): all prescribed fan-outs executed inline; disclosed as `Reviewed-Coverage: sequential-fallback` — no independent review claimed. Review-panel seats must spawn from the pipeline (parent) session.
- Context exhausted during sharp-edges read — lines 1–145 read fully plus targeted keyword sweep; applicable trap classes verified and applied.
- Deepen-plan fix applied: `discoverability_test.command` replaced (budget suite itself fails Check 10) → `grep -c "LOCAL_FAST_CAP_MS=10000" scripts/test-all-fast-tier-budget.test.sh` → `1`.

### Decisions
- Demote all 8 labels with declared edges rather than gating on a calm main-side re-run: #11562 post-merge 8-run `merge_group` medians corroborate all 8 at 11.4–356.9s; fresh-median re-derivation folded into Phase 0 as AC2 evidence, not a gate.
- Per-suite edge sets enumerated from source — seven new `AFFECTED_*_PATHS` arrays + extending `grep-q-pipe-guard` with root-anchored `glob:*.<ext>` PJ_EXTS edges.
- Census arithmetic: 122 − 8 = 114 members → `_MIN_ALWAYS_ON_DECLARED` and f1 literal pin move 117 → 109 in lockstep; 8 justification rows deleted from `always-on-justifications.tsv`.
- Ratchet dispositions: `token-drift-workflow-causes` gets a real `knowledge-base/` covering edge; citation-only refs → `false-positive:` baseline rows; ci-pr-affected pairs resolved by edges/accept rows only — baseline shrink-only.
- `lane: cross-domain` — no spec.md exists for the branch; fail-closed default recorded (`pending - assumed`).

### Components Invoked
- `soleur:plan` (all phases incl. inline research substitutions, plan-review substitution, Save Tasks + commit)
- `soleur:deepen-plan` (Phase 1 parse; gates 4.4/4.45/4.5/4.55 evaluated-skipped; halts 4.6–4.13 executed inline, all pass; Enhancement Summary; committed)
- `scripts/collision-precheck.sh`, `scripts/lint-guard-contract.py` (green), `scripts/test-all-fast-tier-budget.test.sh` (green baseline)

## Work Phase
- Status: complete. Demotion set locked (all 8, no artifact keeps); floor 114-5=109 at both pin sites.
- Edge additions beyond the plan table (ratchet-discovered real reads): scratch-root.sh + git-fixture-env.sh (test-helpers source hops) for check-deps/gitleaks; lefthook.yml, both committed lint-ratchet baselines, scripts/test-all.sh, repo-wide-suites.ts, eslint-test-dirs-ratchet.test.ts for lint-ratchet; tree-wide glob:<dir>/**package.json + docs/legal/privacy-policy.md (disclosed_as) for lint-encryption-posture.
- ci-pr-affected ratchet: 68 anchor-keyed accept rows added (mention-only pairs incl. pre-existing main churn on home-census-trigger + betterstack stale re-anchor); live==baseline=1510.
- tg6 family pin in test-all-affected.test.sh updated 7->9 (two new ^glob:knowledge-base/**.sh carriers); mid-run edit crashed the first full run at line 3782 — blocks 36-38 re-run via --rows green (99/99); blocks 1-35 all green in run 1.
- Guard battery: fast-tier-budget, always-on-ledger (14), lint-orphan, kb-consumers (31), weight-drift (52), corpus-weight-budget (14), group-affected (28), ratchet live==baseline — ALL GREEN.
