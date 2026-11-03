# Tasks — feat-one-shot-12001-10033-suite-times

Plan: `knowledge-base/project/plans/2026-11-03-fix-ci-ratchet-suite-times-apply-redrive-plan.md`
PR: #12002 (draft) | Issues: Closes #12001, Closes #10033 | filed: #12015-#12019

## 1. Setup / Re-verify
- [x] 1.1 fetch + sibling-PR check (all still OPEN, none merged)
- [x] 1.2 `audit --all-refs` run — boundary set confirmed

## 2. Phase 1 — Ratchet repair (#12001)
- [x] 2.1 declared `scripts/lib/bearer-curl.sh` + `.github/actions/dispatch-web-redeploy/track.sh` in AFFECTED_PLUGINS_SOLEUR_PATHS
- [x] 2.2 appended 6 anchor-keyed accept rows (EOF append, house style)
- [x] 2.3 `ratchet` → `exit=0 reason=pass live=1510 baseline=1510` (fixpoint converged, no residue)
- [x] 2.4 baseline regen = no-op (live==baseline; verified identical, file untouched)

## 3. Phase 2 — Top-15 report (Lever A2)
- [x] 3.1-3.4 report written: `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (5 green merge_group runs, n=5 medians, 726 labels; replay-a=1280s outlier)
- [x] 3.5 issues filed: #12015 (replay-a leg), #12016 (stale prices), #12017 (soak bounds)

## 4. Phase 3 — Apply-delivery re-queue (#10033)
- [x] 4.1 `apply-delivery-gap.sh`: `emit_redrive_output` (deploy-fix rows>0, all evicted-before-start, N_INFLIGHT_deploy_fix==0 → redrive_deploy_fix + reserved redrive_infra=false); per-key N_INFLIGHT_* in count_inflight; called after reconcile_issue; self-test extended (4 shapes)
- [x] 4.2 workflow: `follow` outputs + step `id: reconcile`; new `redrive` job (needs/if/permissions: actions: write only); header → bounded actuation doc
- [x] 4.3 test suite: W wiring asserts rewritten to two-job contract (permissions scoping, outputs pin, if: chokepoint, needs, exact run lines, step key sets, banned-keys minus if/needs/outputs)
- [x] 4.4 runbook: redrive arm section appended
- [x] 4.5 ADR-318 authored (status: adopting; ordinal free — max on main was 317)

## 5. Close-out
- [x] 5.1 deferral issues: #12018 (queue:max re-eval), #12019 (infra redrive)
- [ ] 5.2 PR body: `Closes #12001`, `Closes #10033`, `Ref #11556` — at ship
- [ ] 5.3 AC1-AC9 verify — at ship

## Status at commit bae6070657
Self-test green (`apply_delivery_gap_self_test=ok`). Full follower suite running in background.
NOT yet pushed. Next: suite green → push → soleur:review → qa → compound → ship → postmerge.
