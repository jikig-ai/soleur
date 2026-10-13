---
date: 2026-05-22
status: committed
decision: trigger-based-membership-mutations-audit
brand_survival_threshold: single-user incident
lane: cross-domain
parent: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
related:
  - apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql
  - apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql
  - apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql
closes_issues:
  - 4231
---

# `workspace_member_actions` Audit Log Brainstorm

## What We're Building

An append-only `workspace_member_actions` audit table that captures every membership mutation on a shared workspace (member added, member removed, role changed) with workspace owner-only read access, 7-year retention, and Art. 17 anonymise cascade. v1 scope is **membership mutations only** — the parent brainstorm's broader scope (KB writes, agent runs, BYOK lifecycle, canUseTool decisions) is explicitly deferred to v2+.

Required before the first non-jikigai workspace is enabled in the invite-UI beta (blocks `TEAM_WORKSPACE_INVITE_ENABLED` flag-flip in prd for any org outside `@jikigai.com`).

## Why This Scope (Carry-Forward from #4229)

Parent brainstorm Decision 10 deferred this table because Jean + Harry trust each other and `tenant_deploy_audit` (043) covered the deploy boundary. Re-evaluation criterion fires at the first external workspace — that workspace will need Art. 5(2) accountability evidence (who added/removed whom, when) the moment a regulator, departing member, or workspace owner asks.

**Scope reduction from parent's framing (broader → narrower):**

- Parent named KB writes + agent runs + BYOK + membership.
- Existing surfaces already cover three of four: BYOK lifecycle is logged by migration 061 (`byok_audit_workspace_id_rpcs`); KB writes route through `append_kb_sync_row_rpc` (053b) which can be extended in place; agent runs are operator-visible via existing chat history. **Only membership mutations have no current audit surface.**
- Membership-mutations-only is the YAGNI-correct v1 — fastest to ship, smallest blast radius, easiest to extend later when v2 evidence demands a broader surface.

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — inherited from parent brainstorm, confirmed in Phase 0.1.

**Artifact at risk:** `workspace_member_actions` table contents (workspace_id, actor_user_id, target_user_id, action_type, role transitions, attestation_id FK).

**Vectors named (all three load-bearing):**

1. **Cross-workspace audit-row read.** A mis-written RLS predicate (e.g., gating on `is_workspace_member` instead of `is_workspace_owner`) leaks one workspace's membership history to a member of a different workspace. Vector 1 from parent.
2. **Silent audit gap — Art. 5(2) accountability missing.** A future RPC that mutates membership without firing the trigger creates a gap; under regulator inquiry or member dispute we cannot prove who did what. Trigger-on-table (vs. call-site write) is the structural mitigation.
3. **Append-amplification.** Mitigated by scope reduction to membership-only — volume is tens of rows per workspace per year, not the per-canUseTool-call rate the parent considered.

**Threshold:** `single-user incident` (inherited).

## Domain Assessments

**Assessed:** Carry-forward from parent brainstorm `2026-05-21-team-workspace-multi-user-brainstorm.md`. Per AGENTS.md in-flight refresh policy, parent's CPO + CLO + CTO + CFO sign-offs apply unchanged. `user-impact-reviewer` at PR review is the load-bearing gate; no new leader spawn this brainstorm.

### Carry-forward summary

- **CTO** — endorses additive migration on top of 053/058; identifies trigger-on-table as the impossible-to-forget surface vs. per-RPC call-site writes.
- **CLO** — endorses 7y retention + Art. 17 anonymise as SOC2/SOX-defensible without conflicting with GDPR Art. 5(1)(e) data-minimisation; the audit row's lineage columns (id, workspace_id, action_type, created_at) survive anonymise.
- **CPO** — narrowed scope ratifies parent's "no UI for external members beyond owner". An owner-only audit view is a settings-page concern, not a public surface; flag-flip gate logic owns the visibility.
- **CFO** — zero marginal COGS; volume floor (tens of rows/workspace/year) is decimal-dust on Supabase Pro.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Action scope v1 | Membership mutations only (added, removed, role_changed) | YAGNI; BYOK + KB + agent-run audit surfaces already exist or are explicitly deferred per parent Decision 10 |
| 2 | Writer surface | `AFTER INSERT/UPDATE/DELETE` trigger on `public.workspace_members` | Impossible to forget — any future RPC mutating membership auto-audits. No call-site discipline required. |
| 3 | Read posture | Workspace owner only (SECURITY DEFINER RPC fronted, RLS-deny-default underneath) | Closes Vector 1 (cross-workspace leak). Owner-only matches the "audit for accountability, not transparency" principle from `tenant_deploy_audit` (043). |
| 4 | Retention | 7 years + Art. 17 anonymise on user-delete | SOC2 / SOX-defensible forensic window. Daily pg_cron job DELETEs rows older than 7y; `anonymise_workspace_member_actions(p_user_id)` NULLs `actor_user_id` and `target_user_id` while preserving `id`, `workspace_id`, `action_type`, `created_at`. |
| 5 | WORM enforcement | Trigger blocks UPDATE/DELETE except the Art. 17 anonymise shape | Structural-diff recognition per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` and migration 058 precedent |
| 6 | Schema lift pattern | Lift `tenant_deploy_audit` (043) zero-RLS-policy + service_role writer pattern; lift `workspace_member_attestations` (058) anonymise-cascade pattern | Both patterns are battle-tested in prd; no novel substrate |
| 7 | Owner read mechanism | SECURITY DEFINER RPC `list_workspace_member_actions(p_workspace_id uuid)` not a direct SELECT-with-RLS-policy | Centralises the owner-check in one place; matches 043's service_role-only-via-RPC discipline; easier to extend later (pagination, filtering) without RLS rewrites |
| 8 | ADR requirement | None new — this is additive to the foundational primitive ADR from parent (#4229) | Not introducing a new primitive class; same data-model layer |
| 9 | Action class enum | Three values: `added`, `removed`, `role_changed` | No `pending_invite` event (that's `workspace_member_attestations` 058's domain); no `org_owner_transferred` (out of v1 scope) |
| 10 | Attestation linkage | `attestation_id uuid NULL REFERENCES workspace_member_attestations(id) ON DELETE RESTRICT` | Joins the add-event audit row to its attestation evidence (CLO Art. 5(2) chain); NULL for non-add events |

## Proposed Schema (will be finalised at plan-skill phase)

```sql
CREATE TABLE public.workspace_member_actions (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  -- PII columns — NULL after Art. 17 anonymise.
  actor_user_id     uuid         NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  target_user_id    uuid         NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  -- Audit lineage — never cleared.
  action_type       text         NOT NULL CHECK (action_type IN ('added', 'removed', 'role_changed')),
  old_role          text         NULL,
  new_role          text         NULL,
  attestation_id    uuid         NULL REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT,
  created_at        timestamptz  NOT NULL DEFAULT now()
);
```

Plus: WORM trigger; AFTER trigger on `workspace_members`; `anonymise_workspace_member_actions(p_user_id)` RPC; `list_workspace_member_actions(p_workspace_id)` reader RPC; `pg_cron` retention job at 7y. Exact bodies are plan-skill work.

## Non-Goals

- Logging KB writes, agent runs, BYOK lifecycle, or canUseTool decisions (parent Decision 10 — deferred until v2 evidence demands it)
- Member-facing audit view ("see who added/removed me") — owner-only this round; if external workspaces request it, file as a follow-up
- Cross-workspace audit aggregation ("show all my activity across all workspaces I'm in") — Art. 15 DSAR path covers this via the anonymise RPC's mirror
- Real-time push notifications on membership changes (UI poll on owner settings page is enough for v1)
- Tamper-evident hash-chaining (`prev_hash`, Merkle root) — defer until Trust Center or external regulator names it
- Replacing or extending `workspace_member_attestations` (058) — that table's accept-moment shape is structurally distinct

## Open Questions (for plan-skill phase)

1. **Trigger-time actor resolution.** `auth.uid()` inside an AFTER trigger fired by a SECURITY DEFINER RPC returns the SECURITY DEFINER's owner (postgres role), not the caller's user_id. Plan must capture `actor_user_id` via a session GUC set by the RPC (`SET LOCAL workspace_audit.actor_user_id = '<uuid>'`) and the trigger reads `current_setting(..., true)`. Precedent: any 058 RPCs that touch `auth.uid()` — re-grep at plan time.
2. **Role-change diff capture.** UPDATE trigger needs to emit a row only when `role` actually changes (not on noop UPDATEs or admin-tool touch). Use `OLD.role IS DISTINCT FROM NEW.role`.
3. **Pre-existing membership rows.** Migration 053 created `workspace_members` weeks ago; do we backfill audit rows for the existing `jikigai` org members (Jean owner + Harry member from the parent PR)? Probably yes, with `actor_user_id = NULL` and a synthetic `action_type = 'added'` row per existing membership so the table is not deceptively empty on day one.
4. **`list_workspace_member_actions` pagination shape.** Cursor or offset? Default page size? Punt to plan.
5. **Anonymise vs. account-delete ordering.** Parent brainstorm's Capability Gap #1 noted `dsar-reauth.ts` is keyed on `founder_id`. The anonymise RPC must be called BEFORE `auth.admin.deleteUser()` cascades; document the runbook ordering in the migration comment.
6. **Index strategy.** `(workspace_id, created_at DESC)` for owner-page list; `(target_user_id)` for Art. 17 anonymise sweep. Confirm at plan.

## Cross-Domain Dependencies

| From | To | Dependency |
|---|---|---|
| CTO | feat-team-workspace-legal-scaffolding | Independent — that worktree is the ToS 2.2.0 / AUP §5.5 / Side Letter track from parent. No code overlap. |
| CTO | #3637 (DSAR endpoint) | The anonymise RPC must be added to the existing per-table DSAR cascade list. Plan should grep `dsar-export-allowlist.ts` and `account-delete.ts` and add `workspace_member_actions` to the anonymise sweep. |
| CTO | TEAM_WORKSPACE_INVITE_ENABLED flag | This migration + RPCs must land BEFORE the flag flips ON for any non-jikigai org. PR description should call this out as a flip-gate. |

## Out of Scope for This Brainstorm

- Exact SQL bodies (plan-skill work)
- pg_cron job name + exact cadence wording (plan-skill, lift from 043)
- `list_workspace_member_actions` API contract (plan-skill)
- Settings-page UI for the audit viewer (defer to a follow-up — v1 ships the data primitive; UI lands when an external workspace asks)

## Session Errors

None this session. Premise probes (parent #4229 state, 043/053/058 migrations, canUseTool surface, prior brainstorm presence) all returned the expected state.

## Productize Candidate

**Candidate name:** `tenant-audit-table` migration template / skill.

**Pattern observed:** `tenant_deploy_audit` (043) + `workspace_member_attestations` (058) + this table (`workspace_member_actions`) all lift the same shape: WORM trigger, SECURITY DEFINER writer RPC, owner/admin-only reader RPC, Art. 17 anonymise cascade, optional pg_cron retention, RLS-zero-policies. The fourth time this shape ships, file a follow-up to extract a `/soleur:audit-table-scaffold` skill that takes (table_name, pii_columns, lineage_columns, retention_days) and emits the migration scaffold.

Not pivoting this brainstorm. File as deferred follow-up only if the post-merge count of audit tables passes 4.
