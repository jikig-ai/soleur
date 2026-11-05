---
branch: feat-one-shot-10861-pr5z-strict-zero
issue: 10861
lane: cross-domain
date: 2026-11-05
---

# Spec: S4 affected-index PR5z — strict zero (delete the baseline, remove the adoption arm)

Plan: `knowledge-base/project/plans/2026-11-05-feat-one-shot-10861-pr5z-strict-zero-plan.md`.
Canonical contract: `knowledge-base/project/specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 4 (tasks 4.1-4.9) + its Verification block.
Prior rulings: `.../decision-challenges.md` rows 5 (deletion+arm one commit), 8 (sweep items), 15 (`RATCHET_BASELINE` stays in `RATCHET_ORACLE`), 16 (preactivation zero coupling); `.../session-state.md`.

## Scope

1. Assert strict zero on the final tree: `audit --accept` exit 0 `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` `live=0`.
2. `git rm scripts/ci-pr-affected-audit.baseline.tsv` (tracked empty blob) in the SAME commit as 3.
3. Add the `baseline-reintroduced` arm to `scripts/ci-pr-affected-replay.py` (base absent / HEAD present → exit 1 unconditionally; ADR-276 item 5(d)); update the `ratchet --help` BASELINE STATE text + verdict list.
4. Rework `plugins/soleur/test/ci-pr-affected-replay.test.sh`: adoption rows → reintroduced rows; keep present/present machinery + grown/stale/dup/order rows (reachable via `--baseline`/stale bases); new mutants (`ratchet-reintroduced-tolerated`, content-weakening, live-gated); `rt_p_weak`/`row_rt_helper_pr_tree_ignored` comments.
5. Sweep: delete the 42 orphaned accept rows (14×3 on `-a`/`-b`/`-c`) in the same commit; `.gitattributes:2` removal; `RATCHET_BASELINE` kept in `RATCHET_ORACLE`; observation probe + `inngest-probe-row.test.sh` + `ci-pr-affected-preactivation.sh` verify-only; `ci.yml` job comment only (step name untouched — probe keys on it).
6. ADR-276 `### Stage status` closing dated line; runbook §7 strict-zero rewrite + observation-log entry.
7. Close-out: #10861 final marker `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0`; `s4-drain` label released post-merge; #10448 mirror.

## Holds

No `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR, no new edges/accept rows beyond Phase-0 residual drift. One `s4-drain` PR at a time.

## Plan-time state (re-measure at work time)

- `origin/main` = `f06b595420` is currently RED: `exit=1 reason=stale-accept live=3 baseline=0` (merge_group runs 41943389794, 41991683080). Issue #12110; fix PR #12128 in flight → Phase 0.3 coordination arm.
- 42 accept rows key on the baseline path (`awk -F'\t' '$2=="scripts/ci-pr-affected-audit.baseline.tsv"'`) — orphaned by the deletion; same-commit removal mandatory.
