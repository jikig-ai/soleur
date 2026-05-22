---
feature: feat-workspace-member-actions-audit-4231
status: draft
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4231
parent_issue: 4229
branch: feat-workspace-member-actions-audit-4231
pr: 4287
brainstorm: knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md
---

# Spec: `workspace_member_actions` Audit Log

## Problem Statement

Shared workspaces (organizations introduced in #4229) have no audit trail for membership mutations. When a workspace owner adds, removes, or changes the role of a member, no row records who-did-what-to-whom-when. Under GDPR Art. 5(2) accountability, a regulator inquiry into "did the controller (workspace owner) manage member access lawfully?" cannot be answered. Under SOC2 / member-dispute scenarios ("Harry says he was never removed"), the same gap exists.

Parent brainstorm `#4229` explicitly deferred this audit log (Decision 10) for internal dogfood (Jean + Harry trust each other; `tenant_deploy_audit` (043) covers the deploy boundary). The deferral's re-evaluation criterion fires at the first external workspace — that workspace owner cannot operate without this evidence trail.

**Blocks:** `TEAM_WORKSPACE_INVITE_ENABLED` flag-flip in prd for any org outside `@jikigai.com`.

## Goals

- G1 — Capture every membership mutation (add, remove, role-change) on `public.workspace_members` as an append-only audit row with sufficient identity columns to answer "who acted, against whom, when, what changed."
- G2 — Make the audit surface impossible to forget: any future RPC or admin tool that mutates `workspace_members` automatically writes an audit row without call-site discipline.
- G3 — Restrict read access to the workspace owner only (closes parent's Vector 1 — cross-workspace audit-row read).
- G4 — Preserve audit lineage for 7 years while honouring GDPR Art. 17 erasure requests via a non-destructive anonymise cascade.
- G5 — Inherit the WORM + SECURITY DEFINER + named-role REVOKE patterns from `tenant_deploy_audit` (043) and `workspace_member_attestations` (058) — no novel substrate.

## Non-Goals

- NG1 — Log KB writes, agent runs, BYOK lifecycle, or `canUseTool` permission decisions (parent #4229 Decision 10; revisit if v2 evidence demands).
- NG2 — Member-facing audit view ("see who added/removed me"). Owner-only this round.
- NG3 — Cross-workspace activity aggregation for a single user (covered by Art. 15 DSAR path via anonymise RPC mirror).
- NG4 — Real-time notifications on membership changes (owner settings-page poll is enough for v1).
- NG5 — Tamper-evident hash chaining or Merkle roots (defer until Trust Center / external regulator asks).
- NG6 — Member-departure DSAR routing (parent Capability Gap #1 — separate follow-up).

## Functional Requirements

- **FR1 — Audit table.** A new `public.workspace_member_actions` table with columns: `id`, `workspace_id`, `actor_user_id` (PII, NULLable), `target_user_id` (PII, NULLable), `action_type` (`added | removed | role_changed`), `old_role`, `new_role`, `attestation_id` (FK → `workspace_member_attestations`, NULL for non-add events), `created_at`.
- **FR2 — Trigger-driven writer.** An `AFTER INSERT/UPDATE/DELETE` trigger on `public.workspace_members` writes one `workspace_member_actions` row per mutation. UPDATE fires a `role_changed` row only when `OLD.role IS DISTINCT FROM NEW.role` (no rows on noop UPDATEs).
- **FR3 — Actor capture via session GUC.** Calling RPCs (`accept_workspace_invite`, `remove_workspace_member`, `change_member_role`) `SET LOCAL workspace_audit.actor_user_id = auth.uid()::text` before the mutation. Trigger reads `current_setting('workspace_audit.actor_user_id', true)::uuid`. NULL when the mutation is admin-tool / migration-time backfill.
- **FR4 — Owner-only read RPC.** SECURITY DEFINER `list_workspace_member_actions(p_workspace_id uuid, p_limit int DEFAULT 50, p_cursor timestamptz DEFAULT NULL)` returns rows for `p_workspace_id` only when `auth.uid() = (SELECT owner_user_id FROM organizations o JOIN workspaces w ON w.org_id = o.id WHERE w.id = p_workspace_id)`. Returns empty (not error) for non-owners — never reveal table existence.
- **FR5 — Anonymise RPC.** SECURITY DEFINER `anonymise_workspace_member_actions(p_user_id uuid)` sets `actor_user_id = NULL` and `target_user_id = NULL` for every row referencing `p_user_id`. Audit lineage columns (`id`, `workspace_id`, `action_type`, `old_role`, `new_role`, `created_at`, `attestation_id`) preserved. Callable from `account-delete.ts` and `dsar-export.ts` cascade lists.
- **FR6 — WORM enforcement trigger.** BEFORE UPDATE/DELETE trigger rejects all mutations except the Art. 17 anonymise structural shape (only PII columns NOT NULL → NULL; all other columns unchanged). Recognise the anonymise shape by structural diff, not by GUC + role check (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`).
- **FR7 — Retention job.** `pg_cron` job `workspace-member-actions-retention` runs daily 04:00 UTC and `DELETE FROM workspace_member_actions WHERE created_at < now() - interval '7 years'`. Service-role only.
- **FR8 — Backfill existing memberships.** Migration includes a one-shot backfill: one synthetic `action_type = 'added'` row per existing `workspace_members` row with `actor_user_id = NULL`, `target_user_id = workspace_members.user_id`, `new_role = workspace_members.role`, `created_at = workspace_members.created_at`. Prevents day-one "empty audit" deception.
- **FR9 — DSAR cascade wiring.** Add `workspace_member_actions` to `apps/web-platform/server/dsar-export-allowlist.ts` and `apps/web-platform/server/account-delete.ts` so Art. 15 export includes (anonymised-where-applicable) rows and Art. 17 deletion invokes the anonymise RPC.

## Technical Requirements

- **TR1 — Migration number.** Next available in `apps/web-platform/supabase/migrations/` (062 or later — verify at implementation time, including any sibling worktrees with claimed-but-unmerged numbers).
- **TR2 — `cq-pg-security-definer-search-path-pin-pg-temp`.** Every SECURITY DEFINER fn pins `SET search_path = public, pg_temp` (public first).
- **TR3 — Default-privileges defeat REVOKE.** Per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`: explicit `REVOKE FROM PUBLIC, anon, authenticated` AND explicit `GRANT EXECUTE TO service_role` on every RPC. REVOKE FROM PUBLIC alone is insufficient.
- **TR4 — RLS-zero-policies + service_role bypass.** Match `tenant_deploy_audit` (043) pattern. Enable RLS; create zero policies. All reads route through `list_workspace_member_actions` SECURITY DEFINER RPC.
- **TR5 — No `CREATE INDEX CONCURRENTLY`.** Per `cq-supabase-migration-no-concurrently` (Supabase wraps each migration in a transaction).
- **TR6 — Indexes.** `CREATE INDEX ON workspace_member_actions (workspace_id, created_at DESC)` for owner-list query path. `CREATE INDEX ON workspace_member_actions (target_user_id) WHERE target_user_id IS NOT NULL` for Art. 17 anonymise sweep.
- **TR7 — Down migration.** Provide `06X_workspace_member_actions.down.sql` that drops the cron job, RPCs, triggers, and table in reverse-dependency order.
- **TR8 — Article 30 register update.** Add a processing-activity row (`PA-X — workspace membership audit`) to `knowledge-base/legal/article-30-register.md` with lawful basis (Art. 6(1)(c) legal obligation + Art. 6(1)(f) legitimate interest for accountability), retention (7y), and the anonymise cascade.
- **TR9 — Sentinel coverage.** `hr-write-boundary-sentinel-sweep-all-write-sites` — grep every `workspace_members` write site and confirm each is reachable from a SECURITY DEFINER RPC that sets the `workspace_audit.actor_user_id` GUC before mutating.
- **TR10 — GUC-name uniqueness.** Confirm `workspace_audit.actor_user_id` does not collide with any existing GUC namespace (grep `current_setting\(.*workspace` across migrations and server code).

## Acceptance Criteria

- **AC1** — Inserting a row into `workspace_members` via `accept_workspace_invite` produces exactly one `workspace_member_actions` row with `action_type='added'`, `actor_user_id = inviter.user_id`, `target_user_id = invitee.user_id`, `new_role = members.role`, `attestation_id` linked.
- **AC2** — Deleting a `workspace_members` row via `remove_workspace_member` produces exactly one `workspace_member_actions` row with `action_type='removed'`, `actor_user_id = remover.user_id`, `target_user_id = removed.user_id`, `old_role = members.role`.
- **AC3** — `UPDATE workspace_members SET role='owner' WHERE user_id=$1` via `change_member_role` produces exactly one `workspace_member_actions` row with `action_type='role_changed'`, `old_role` + `new_role` populated. No-op UPDATEs (same role) produce no audit row.
- **AC4** — Direct `UPDATE workspace_member_actions SET actor_user_id='...'` outside the anonymise shape is rejected by the WORM trigger.
- **AC5** — `anonymise_workspace_member_actions(p_user_id)` invocation NULLs both `actor_user_id` and `target_user_id` for matching rows while leaving lineage columns intact. Re-running is idempotent.
- **AC6** — A non-owner authenticated session calling `list_workspace_member_actions(p_workspace_id)` for a workspace they do not own returns zero rows (no error, no leak).
- **AC7** — The owner of a workspace calling `list_workspace_member_actions(p_workspace_id)` sees all rows for that workspace ordered by `created_at DESC`.
- **AC8** — Backfill produces one synthetic `added` row per pre-existing `workspace_members` row at migration-apply time. No duplicates on re-run.
- **AC9** — `pg_cron` job is scheduled with the canonical name `workspace-member-actions-retention` at `0 4 * * *`.
- **AC10** — Down migration removes the cron job, triggers, RPCs, indexes, and table cleanly with no orphan objects.

## Test Plan

- **Unit (pgTAP)** — One file `apps/web-platform/supabase/tests/workspace_member_actions.sql` covering AC1–AC10.
- **Integration (Vitest)** — Extend `apps/web-platform/e2e/team-membership.e2e.ts` with two scenarios: (a) Jean adds Harry → expect 1 audit row; (b) Jean lists audit → returns 1 row; Harry lists same workspace's audit → returns 0 rows.
- **DSAR cascade** — Add to `apps/web-platform/test/dsar-cascade.test.ts` (or sibling) confirming anonymise sweeps `workspace_member_actions` when a user requests Art. 17 erasure.
- **WORM** — Direct-SQL UPDATE/DELETE attempts in pgTAP must fail with the documented WORM error code.

## Risks & Mitigations

- **R1 — Actor GUC missing on a mutation path** → trigger writes `actor_user_id = NULL`. Mitigation: TR9 sentinel sweep + AC2/AC3 cover the named RPC paths; admin-tool / migration-time mutations are intentionally NULL.
- **R2 — Anonymise RPC missing from DSAR cascade list** → user-delete completes without anonymising audit rows, leaving PII orphaned. Mitigation: FR9 makes the cascade wiring a first-class FR; AC + dsar-cascade test must fail if missing.
- **R3 — `workspace_audit.actor_user_id` GUC collision** → wrong user_id captured. Mitigation: TR10 grep.
- **R4 — Backfill races with a live `workspace_members` insert at migration-apply time** → duplicate row. Mitigation: migration runs in a transaction; insert lock on `workspace_members` for the backfill duration.
- **R5 — Flag-flip happens before this lands** → first external workspace operates without audit. Mitigation: PR description names this as a flip-gate; ops checklist for first external onboard mentions this migration as a prereq.

## Out of Scope (deferred follow-ups)

- Settings-page UI for the audit viewer — file a follow-up issue when an external workspace requests it.
- v2 broader-scope audit (KB writes, agent runs, BYOK, canUseTool) — parent #4229 Decision 10; revisit when external evidence demands.
- `tenant-audit-table` productize skill (see brainstorm Productize Candidate) — file follow-up only if post-merge audit-table count passes 4.

## References

- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md` (Decision 10 deferral)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md`
- Migration patterns: `043_tenant_deploy_audit.sql`, `053_organizations_and_workspace_members.sql`, `058_workspace_member_attestations.sql`
- WORM trigger learning: `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
- Default privileges learning: `knowledge-base/project/learnings/2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`
- Issue: #4231 (this scope); #4229 (parent, CLOSED via #4225)
- Branch: `feat-workspace-member-actions-audit-4231`
- Draft PR: #4287
