---
plan: knowledge-base/project/plans/2026-07-02-fix-web-platform-infra-moved-target-allowlist-plan.md
issue: 5887
lane: cross-domain
---

# Tasks — fix(infra) #5887 moved-block wedge + moved/`-target` guard

## Phase 0 — Preconditions
- [x] 0.1 `grep -n '^moved' apps/web-platform/infra/*.tf` — confirm 4 moved bases (server, volume, volume_attachment, server_network) are the complete set.
- [x] 0.2 Confirm all 4 bases are in `OPERATOR_APPLIED_EXCLUSIONS` (terraform-target-parity.test.ts:370-423).
- [x] 0.3 Baseline green: `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
- [x] 0.4 Do NOT run terraform from the agent (no prd creds / R2 state in-session).

## Phase 1 — moved/`-target` parity guard (recurrence fix) — minimal shape: 1 helper + 1 set + 3 tests
- [x] 1.1 Add `parseMovedBlocks(stripped)` helper — **flat regex** `/moved\s*\{[^}]*\}/g` (blocks are flat; no brace-matcher) + `from`/`to` captures, reduce to base address (strip `["…"]`).
- [x] 1.2 Add documented `MOVED_OPERATOR_CONSUMED` set with the 4 #5877 bases + per-entry rationale; add cross-ref comment on BOTH it and `OPERATOR_APPLIED_EXCLUSIONS` (dual-maintenance / lockstep-on-rename).
- [x] 1.3 Test 1 (coverage + regression anchor in one): every moved base ∈ (`allTargets` ∪ `MOVED_OPERATOR_CONSUMED`); uncovered → fail.
- [x] 1.4 Test 2 (non-vacuity): synthetic-forgotten-moved-block flagged uncovered (mirror `synthetic_untargeted_ssh`, lines 278-333).
- [x] 1.5 Test 3 (drift guard): assert `MOVED_OPERATOR_CONSUMED ⊆ OPERATOR_APPLIED_EXCLUSIONS` (closes sync-drift; replaces the cut tautological anchor).
- [x] 1.6 Comment WHY the #5566 exclusion check is orthogonal to plan-time move processing + the known-limitation note (accounting check, not interlock; repo not live state).
- [x] 1.7 `bun test plugins/soleur/test/terraform-target-parity.test.ts` green.

## Phase 2 — ADR amendment + learning
- [x] 2.1 Append `> **Amendment (2026-07-02, #5877/#5887)**` to ADR-068 (sequencing rule; do NOT change `status: adopting`).
- [x] 2.2 Write CONCISE learning under `knowledge-base/project/learnings/` (date picked at write-time) as a **pointer to the ADR amendment**, not a restatement.

## Phase 3 — Full suite + PR
- [x] 3.1 `bun test plugins/soleur/test/` green (no sibling suite regresses).
- [x] 3.2 Confirm `git diff .github/workflows/apply-web-platform-infra.yml` is EMPTY (no `-target` change).
- [ ] 3.3 Open PR with `Ref #5887` (NOT `Closes`); labels `domain/engineering`, `priority/p1-high`; `semver:patch`; `## Changelog` section.
- [ ] 3.4 Enroll `follow-through` tracker + `scripts/followthroughs/<name>-5887.sh` (both workflows green post-cutover).
- [ ] 3.5 File deferred follow-up issue (`domain/engineering`, `priority/p2-medium`): reboot-aware destroy-guard for in-place `update` on `hcloud_server.*` reboot-forcing attrs (architecture review P2).

## Post-merge (operator — maintenance window; NOT agent-executed)
- [ ] O.1 Dry-run `terraform plan` via canonical Doppler tf-var invocation; confirm `0 to destroy` + expected cutover scope.
- [ ] O.2 `terraform apply` in maintenance window; confirm web-1 healthy after reboot.
- [ ] O.3 Confirm `apply-web-platform-infra.yml` + `apply-deploy-pipeline-fix.yml` next runs green.
- [ ] O.4 `gh issue close 5887` after apply succeeds.
