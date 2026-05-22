---
title: 'Post-implementation review can amend plan-time architectural invariants (workspace_id immutable → orphan-cleanup carve-out)'
date: 2026-05-22
category: engineering
tags: [multi-agent-review, dissent-flip, scope-out, worm-ledger, architectural-invariant, adr, on-delete-restrict, orphan-cleanup, gdpr-art-17]
symptoms: [ADR claims an invariant ("lineage immutable") that turns out to block a downstream-cascade requirement, code-simplicity-reviewer DISSENTs on a scope-out filing arguing the fix is inline-shaped, scope-out criteria 1+2+4 all fail under literal reading, the inline fix contradicts an invariant declared in an ADR landed in the same PR]
module: review + plan + ship
related_files: [apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql, knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md, apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql]
related_issues:
  - 4230
  - 4294
  - 4329
related_prs:
  - 4225
  - 4294
component: review
problem_type: design_decision
resolution_type: code_fix
root_cause: plan-time invariant didn't anticipate downstream cascade interaction
severity: medium
---

# Post-implementation review can amend plan-time architectural invariants

## Problem

PR #4294 (feat-dsar-departed-member-coverage) shipped migration 062 + ADR-039 declaring `workspace_member_removals` audit-lineage columns (`id`, `workspace_id`, `removed_at`) as **strictly immutable** — mirroring the 058 pattern for `workspace_member_attestations`. The WORM trigger rejected any UPDATE that altered these columns; the FK was `workspace_id REFERENCES public.workspaces(id) ON DELETE RESTRICT`.

Post-implementation, security-sentinel surfaced a real Art. 17 erasure failure: `anonymise_organization_membership` (058:419-468) in the account-delete cascade issues `DELETE FROM public.workspaces WHERE organization_id = …` for orphan orgs (owner deleted, zero remaining members). The new RESTRICT FK from `workspace_member_removals.workspace_id` would block that DELETE — propagating the error up step 3.92, aborting the cascade, and leaving the user's `auth.admin.deleteUser()` step unreached.

The same defect class exists in 058's `workspace_member_attestations.workspace_id` (also RESTRICT) but predates this PR.

## Investigation steps

1. **Initial disposition: scope-out.** The fix appeared cross-cutting (touches 058 + 062 + account-delete.ts) and contested-design (two named alternatives: extend cleanup RPC vs. ALTER FK shape). Drafted a filing under criteria 1 (cross-cutting-refactor) + 2 (contested-design).
2. **CONCUR gate caught it.** `code-simplicity-reviewer` returned `DISSENT` with concrete reasoning:
   - **Criterion 4 (pre-existing-unrelated) fails:** the new FK at `062:66` is in the `+` diff. Per the literal SKILL.md definition: "Mirroring an existing brittle pattern 'for symmetry' is exacerbation, not preservation." Mirroring 058's RESTRICT shape "for symmetry" disqualifies criterion 4.
   - **Criterion 1 (cross-cutting-refactor) fails:** all touched files live under `apps/web-platform/supabase/migrations/` — same top-level directory; tightly coupled to this PR's core change (WORM-ledger + erasure-cascade); the "materially unrelated" test fails.
   - **Criterion 2 (contested-design) fails:** option (ii) ALTER FK→SET NULL + WORM trigger NULL-transition admission is strictly cheaper than option (i) extend cleanup RPC; trade-off is lopsided, not genuinely contested.
3. **Architectural tension surfaced:** the DISSENT's proposed inline fix (workspace_id NULL-able + WORM trigger admits NULL transition) contradicts ADR-039's plan-time invariant ("lineage columns immutable").
4. **Resolution:** apply the inline fix AND amend ADR-039's invariant statement to acknowledge the carve-out. File the sister-table defect on 058 separately as `pre-existing-unrelated` (#4329) — that one genuinely predates this PR.

## Root cause

**Plan-time invariants are hypotheses about what the system needs to be, not facts about what the system can support.** ADR-039 declared workspace_id immutable because:
- 058 made the same declaration for attestations (precedent)
- Audit-lineage semantics suggest workspace_id is load-bearing
- WORM-ledger discipline favors maximum immutability

But the downstream cascade (`anonymise_organization_membership` orphan-cleanup) requires `DELETE FROM workspaces`, which an immutable-workspace_id RESTRICT FK blocks. The plan-time review (DHH/Kieran/Simplicity) didn't trace through to the orphan-cleanup path. Post-implementation multi-agent review with the full cascade context did.

058 has the same defect but it predates this PR; it's filed as #4329 with `pre-existing-unrelated`.

## Solution

The inline fix:

1. `workspace_id` FK shape: `NULL REFERENCES workspaces(id) ON DELETE SET NULL` (was `NOT NULL ... RESTRICT`).
2. WORM trigger: permits `workspace_id` NOT NULL → NULL transition (mirrors PII column shape).
3. Strict-immutable lineage narrowed to `{id, removed_at}` (workspace_id demoted to NULL-transition admissible).
4. ADR-039 §Invariants.1 amended with the carve-out paragraph + rationale.
5. PA-19 register entry amended with the new FK shape.
6. Lint test updated to match (35/35 still pass).
7. Sister-table on 058 filed separately at #4329 (pre-existing-unrelated).

The audit-information loss from `workspace_id` going NULL is bounded: once the workspace itself is DELETEd by orphan-cleanup, zero co-members remain to read the row via RLS; the workspace_id no longer points anywhere meaningful. The surviving columns (id, removed_user_id, removed_by_user_id, removed_at) still serve DSAR Art. 15 export.

## Prevention

1. **Plan-review must trace downstream cascades for new RESTRICT FKs.** When a plan adds a `REFERENCES X ON DELETE RESTRICT` FK to a table that another part of the cascade DELETEs, verify the cascade path won't be blocked. Grep for `DELETE FROM <target_table>` across `account-delete.ts`, `anonymise_*` RPCs, and pg_cron sweeps before approving the plan.

2. **ADRs declaring invariants should enumerate "what could break this invariant" first.** ADR-039 listed `id`, `workspace_id`, `removed_at` as immutable lineage; if it had asked "what code path would need to change any of these?", the orphan-cleanup interaction would have surfaced at plan time.

3. **The CONCUR/DISSENT gate is load-bearing — trust it.** `code-simplicity-reviewer` correctly identified that all three scope-out criteria failed under literal reading. The temptation to defer architecturally-significant fixes to follow-ups is exactly the failure mode the gate exists to prevent. Inline-fix + amend the plan-time invariant is the right shape when post-implementation review surfaces an invariant carve-out.

4. **Per-PR architectural amendments are allowed.** ADR-039 was authored in this PR; amending it in the same PR (vs. a follow-up ADR) is the cleanest disposition. The amendment paragraph explicitly cites the DISSENT and the orphan-cleanup interaction so future readers can trace why the invariant has a carve-out.

5. **Symmetric pre-existing defects file separately.** When the inline fix exposes that a sister table has the same shape (here: 058's `workspace_member_attestations.workspace_id` RESTRICT FK), file the sister defect as `pre-existing-unrelated` with a concrete re-evaluation trigger (here: before `FLAG_TEAM_WORKSPACE_INVITE=1` rollout). Don't try to fix both in one PR — the PR's diff scope guards against that.

## Session Errors

1. **Initial bash ran against bare-repo root** — Recovery: `cd <worktree-abs-path>` + `git -C <worktree>` for git ops. **Prevention:** AGENTS.md `hr-when-in-a-worktree-never-read-from-bare` covers this; no new rule needed.

2. **Bash CWD doesn't persist across calls** — Multiple `cd && cmd` chains followed by stale-CWD next call. **Prevention:** Use absolute paths consistently. Already in tool description.

3. **psql not installed locally** — Built Docker-wrapped `postgres:17-alpine` psql shim at `/tmp/psql-wrapper/psql`. **Prevention:** Already documented in `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` §Session Errors. No new prevention needed.

4. **Dev-Supabase drift (workspaces tables missing despite tracking)** — Filed at #4325. Pre-existing. **Recovery:** Workspaces tables need re-creation via DELETE-then-reapply of tracking rows + re-run of 053+058. **Prevention:** Add a CI integrity probe that asserts `_schema_migrations` rows correspond to actual table existence in `information_schema.tables`.

5. **`.or()` change broke per-row-where lint** — Lint expected `.eq(<owner>, X)`; my change replaced with `.or(...)`. **Recovery:** Relaxed lint to accept `.or(...<ownerField>.eq....)` shape. **Prevention:** when changing a query shape covered by a per-row-where lint, anticipate and update the lint in the same commit. Worth a reviewer-side instruction: when a PR changes `service.from(...)...eq(...)`, grep for `dsar-worker-per-row-where.test.ts`-style lints in the same module.

6. **Multi-agent review hit Anthropic session limits (3 of 5 agents)** — Retry after delay worked. **Prevention:** Existing skill prose warns about 12-agent stalls; my 5-agent batch hit a different threshold (Anthropic session budget). Consider sequential batching of 2-3 review agents at a time for token-heavy reviews on large diffs.

7. **DISSENT-flip caught attempted scope-out (worked as designed)** — Success event, not a failure. Documented as the primary insight of this learning.

8. **user-impact-reviewer F8 false-positive P1** — Agent claimed missing export block at L600-755 window; block existed at L762-789. **Prevention:** when claiming "missing X" against a file ≥500 lines, prompts should require an explicit `git grep -n` verification before reporting.

9. **Plan §Phase 1.4 prescribed broken WORM bypass pattern** — Plan said use GUC + role-gate; learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` says role-gate fails (pg_cron runs as `postgres`). Substituted row-state bypass. **Prevention:** plan-review should cross-check WORM-bypass instructions against the `2026-05-15` learning before approving. Worth a `wg-plan-must-cross-reference-worm-bypass-learning` rule on the plan-review skill.

## References

- ADR-039 §Invariants.1 — the amended carve-out paragraph.
- PR #4294 — feat-dsar-workspace-member-4230 (DSAR departed-member coverage).
- #4329 — sister-table defect on 058 (filed under `pre-existing-unrelated`).
- #4325 — dev-Supabase drift (workspaces tables missing).
- `plugins/soleur/skills/review/SKILL.md` §"Step 1: Synthesize All Findings" — scope-out criterion definitions.
- Learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` — row-state vs role-gate WORM bypass precedent.
- Learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — structural-shape vs GUC + role-gate for anonymise UPDATE bypass.
