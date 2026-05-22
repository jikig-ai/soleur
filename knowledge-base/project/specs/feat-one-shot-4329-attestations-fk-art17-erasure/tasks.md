---
issue: 4329
plan: knowledge-base/project/plans/2026-05-22-fix-058-attestations-workspace-id-restrict-art17-erasure-plan.md
spec: knowledge-base/project/specs/feat-one-shot-4329-attestations-fk-art17-erasure/spec.md
---

# Tasks: 058 attestations workspace_id FK fix (#4329)

## Phase 0 — Pre-implementation Decision Gate

- [ ] 0.0.1 CWD verification: `pwd` returns `.worktrees/feat-one-shot-4329-attestations-fk-art17-erasure`
- [ ] 0.0.2 File follow-up issue #4329-A for sister-table 063 defect (`workspace_member_actions.workspace_id` RESTRICT). Title: `fix(supabase): mig 065 063-workspace_member_actions workspace_id RESTRICT → SET NULL (Art. 17 erasure unblock, sister to #4329)`. Body cites plan §Risks + §Sharp Edges. Apply labels: `priority/p2-medium`, `type/bug`, `domain/legal`, `blocks-flag-flip`. Link `Blocks: #4284`.
- [ ] 0.0.3 Edit #4284 to add `blocks-on: #4329-A` in the body.

## Phase 0.1 — Preconditions

- [ ] 0.1.0 Confirm ALTER ordering rationale (read plan §Phase 0.1.0). Single multi-clause ALTER TABLE.
- [ ] 0.1.1 Grep verifies defect site at 058:43 still present on main.
- [ ] 0.1.2 `ls apps/web-platform/supabase/migrations/` confirms next number is 064.
- [ ] 0.1.3 Read 062 trigger function body (lines 140-212) for pattern template.
- [ ] 0.1.4 Read 062 lint test for shape lint template.
- [ ] 0.1.5 Confirm FK constraint default name `workspace_member_attestations_workspace_id_fkey` (Postgres convention).

## Phase 1 — RED: Migration-shape lint test

- [ ] 1.1 Create `apps/web-platform/test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts`. Mirror 062 lint test 1:1, adapted to attestations column set.
- [ ] 1.2 Test groups: AC2 (FK SET NULL), AC2.5 (single-statement ALTER atomicity), AC3 (DROP NOT NULL), trigger rewrite structural-shape, AC4 (no current_user), AC11 (carve-out parity vs 062), down-migration parity.
- [ ] 1.3 Run lint test — confirm RED checkpoint (064 migration absent).

## Phase 2 — GREEN: Migration

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql`.
- [ ] 2.2 §1 Preflight DO-block (verify table + constraint name existence; fail loud with hint if divergent name).
- [ ] 2.3 §2 Single ALTER TABLE statement: `DROP CONSTRAINT IF EXISTS … , ADD CONSTRAINT … ON DELETE SET NULL, ALTER COLUMN workspace_id DROP NOT NULL;` (atomic).
- [ ] 2.4 §3 `CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()` body adapted from 062:140-212. Lineage = `(id, accepted_at)` only. workspace_id NOT NULL → NULL admissible. 5 PII columns each NOT NULL → NULL admissible (preserved). No `current_user`.
- [ ] 2.5 §4 Re-attach BEFORE UPDATE + BEFORE DELETE triggers + REVOKE ALL ON FUNCTION.
- [ ] 2.6 Run Phase 1 lint test — MUST pass.

## Phase 3 — Down migration

- [ ] 3.1 Create `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql`.
- [ ] 3.2 §0 0-row guard: RAISE EXCEPTION if any row has workspace_id IS NULL.
- [ ] 3.3 §1 Restore original 058:72-125 trigger body verbatim.
- [ ] 3.4 §2 Re-attach triggers.
- [ ] 3.5 §3 ALTER COLUMN SET NOT NULL.
- [ ] 3.6 §4 ALTER TABLE: DROP CONSTRAINT … ADD CONSTRAINT … ON DELETE RESTRICT.
- [ ] 3.7 Re-run lint test — down-migration assertions pass.

## Phase 4 — Comment + doc updates

- [ ] 4.1 Update `apps/web-platform/server/account-delete.ts` step 3.90 + 3.91 docstrings.
- [ ] 4.2 Add `### Invariants` subsection to ADR-038 documenting the workspace_id carve-out.
- [ ] 4.3 Update ADR-039 §Invariants.1 sister-table cross-reference.
- [ ] 4.4 Update `article-30-register.md` PA-2 co-member note + PA-19 cross-reference.
- [ ] 4.5 Update `compliance-posture.md` row for #4329 (close note).

## Phase 5 — Verification

- [ ] 5.1 Run each AC verification command (AC1–AC15). Capture output to /tmp/ac-verify.log.
- [ ] 5.2 Run full migration lint suite: `bun x vitest run test/supabase-migrations/`.
- [ ] 5.3 Run schema-probe gate: `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh`.
- [ ] 5.4 Type-check: `bun x tsc --noEmit`.

## Phase 6 — PR open + multi-agent review

- [ ] 6.1 Push branch.
- [ ] 6.2 Open PR with title + body per plan §Phase 6.2 (includes `Closes #4329` + cross-ref to #4329-A + brand-survival annotation).
- [ ] 6.3 Spawn 5-agent panel: data-integrity-guardian, user-impact-reviewer, code-simplicity-reviewer, architecture-strategist, git-history-analyzer.
- [ ] 6.4 Fix-inline every P0/P1 finding. Re-run AC commands.

## Phase 7 — Merge + post-merge verify

- [ ] 7.1 `gh pr merge --auto --squash` after CI green.
- [ ] 7.2 Wait for `web-platform-release.yml#migrate` job to complete; verify success.
- [ ] 7.3 Run AC16 prd-state probes via Supabase MCP (confdeltype='n', is_nullable='YES').
- [ ] 7.4 `gh issue close 4329` with verification comment.
- [ ] 7.5 Capture session learnings via `/soleur:compound` (deepen-added 063 finding + ALTER atomicity gate are the load-bearing knowledge).
