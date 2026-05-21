---
title: Sentinel sweep for feat-team-workspace-multi-user
plan: knowledge-base/project/plans/2026-05-21-feat-team-workspace-multi-user-plan.md
spec: knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
phase: 8.1
---

# Sentinel sweep — Phase 8.1

Captures verbatim the four grep audits for inclusion in the PR body.
Mechanically annotates each match as **converted** (now reads
`is_workspace_member` / `is_message_owner_in_workspace`) or **kept**
(scope intentionally unchanged, 1-line rationale).

## 8.1.1 — `(owner_id|user_id|founder_id) = (auth.uid()|session.user_id|req.user)` in server/ + app/api/

Command:

```bash
git grep -nE "(owner_id|user_id|founder_id)\s*=\s*(auth\.uid\(\)|session\.user_id|req\.user)" \
  apps/web-platform/server/ apps/web-platform/app/api/ \
  | grep -v -E "\.test\.|/test/"
```

Result (2 hits):

```text
apps/web-platform/server/agent-runner.ts:430:  // user_id = auth.uid())` — a cross-founder write fails the policy and
apps/web-platform/server/ws-handler.ts:1781:          // ensures `conv.user_id = auth.uid()` — the convId comes
```

Annotation: **both kept (documentation comments only)**. Neither match
is executable code; both reference legacy RLS-policy shapes inside
explanatory comments. The actual policy bodies live in migrations
053–055 and route through `is_workspace_member()` post-Phase 1. No
conversion needed.

## 8.1.2 — `is_message_owner(` helper-routed sites in apps/web-platform/

Command:

```bash
git grep -nE "is_message_owner\(" apps/web-platform/
```

Result (matches in migrations only — no app-code call sites):

```text
supabase/migrations/045_attachments_storage_rls.sql:45  -- DROP FUNCTION ... is_message_owner(uuid, uuid)
supabase/migrations/045_attachments_storage_rls.sql:86  DROP FUNCTION IF EXISTS public.is_message_owner(uuid, uuid)
supabase/migrations/045_attachments_storage_rls.sql:87  CREATE FUNCTION public.is_message_owner(p_message_id uuid, p_user_id uuid)
supabase/migrations/045_attachments_storage_rls.sql:111 REVOKE ALL ON FUNCTION public.is_message_owner(uuid, uuid)
supabase/migrations/045_attachments_storage_rls.sql:112 GRANT EXECUTE ON FUNCTION public.is_message_owner(uuid, uuid) TO authenticated
supabase/migrations/045_attachments_storage_rls.sql:119  policy USING is_message_owner(message_attachments.message_id, auth.uid())
supabase/migrations/055_workspace_keyed_rls_sweep.down.sql:9-29  rollback: restore 045 shape
supabase/migrations/055_workspace_keyed_rls_sweep.sql:410-441  workspace-aware reimplementation of the same helper
```

Annotation: **converted in-place**. Migration 055 §"Reimplement
is_message_owner" rewrites the helper body to verify membership via
`is_workspace_member(messages.workspace_id, p_user_id)` while keeping
the public signature `(p_message_id uuid, p_user_id uuid)` stable. Every
RLS policy that calls the helper (message_attachments
USING/WITH-CHECK; messages-as-external-drafts; action_sends) inherits
the new workspace-aware check transparently — no policy bodies needed
to change. Per Phase 1.3.7 plan note + `cq-pg-security-definer-search-path-pin-pg-temp`.

## 8.1.3 — Per-match annotation

| Source | Hits | Status | Rationale |
|---|---|---|---|
| `server/agent-runner.ts:430` | 1 | kept | Legacy-shape doc comment, not executable. |
| `server/ws-handler.ts:1781` | 1 | kept | Legacy-shape doc comment, not executable. |
| `supabase/migrations/045_attachments_storage_rls.sql` | 6 | converted | Helper body rewritten in 055; signature stable, so 045's CREATE/GRANT/USING references continue to compile. |
| `supabase/migrations/055_workspace_keyed_rls_sweep.sql` | 3 | converted | New workspace-aware body (CREATE OR REPLACE, identical signature). |

No write sites in `server/` or `app/api/` carry the legacy auth.uid()
shape on executable code paths. The 2 documentation matches are kept
for historical clarity (they describe what migration 001's RLS policy
USED to enforce, while pointing at 053/055 for the current shape).

## 8.1.4 — AC-ROLE-UNION three-pattern grep over apps/web-platform/

### Pattern 1: `role ===` usage

```bash
git grep -nE "role\s*===" apps/web-platform/ | grep -vE "\.test\.|/test/|\.md:|migrations/"
```

Workspace-role sites (filtered to feat-team-workspace-multi-user surface):

```text
components/dashboard/org-switcher.tsx:18           return role === "owner" ? "Owner" : "Member";
components/settings/invite-member-modal.tsx:133   role === "member" ? "ring-1 ring-pri…"
components/settings/invite-member-modal.tsx:143   checked={role === "member"}
components/settings/invite-member-modal.tsx:156   role === "owner" ? "ring-1 ring-pri…"
components/settings/invite-member-modal.tsx:166   checked={role === "owner"}
components/settings/team-membership-list.tsx:117  member.role === "owner" ? "border-pri…"
components/settings/team-membership-list.tsx:122  {member.role === "owner" ? "Owner" : "Member"}
```

Annotation: **all enumerate BOTH `'owner'` AND `'member'`**. Either via
ternary (`role === "owner" ? "Owner" : "Member"`) or paired
side-by-side comparisons. The other `role ===` hits in the codebase
(chat message-role enum, KB share-link role, Stripe webhook status)
are out of scope — they're not the workspace_members.role union.

### Pattern 2: `_exhaustive: never` rails

```bash
git grep -nE "_exhaustive: never|_exhaustive:\s*never" apps/web-platform/ | grep -vE "\.test\.|/test/"
```

20+ hits across the codebase. **None enumerate the
workspace_members.role union today** — the union is small (`'owner' |
'member'`) and the UI uses ternary discriminators on each branch (see
Pattern 1) rather than switch/exhaustive-never rails. This is
intentional and acceptable: with 2 members the ternary shape is more
ergonomic than a switch. Future expansion (e.g., `'admin'` or
`'viewer'`) would warrant introducing the `_exhaustive: never` rail at
that time.

### Pattern 3: `.role?` optional-chained access

```bash
git grep -nE "\.role\?" apps/web-platform/ | grep -vE "\.test\.|/test/"
```

Zero hits. The workspace_members.role column is `NOT NULL CHECK in
('owner','member')` at the schema level (migration 053 §1.1.4), and the
TS shape carries the type as a required `"owner" | "member"` union —
never nullable. No optional-chain access points exist in the codebase.

### AC-ROLE-UNION verdict

✓ Every workspace_members.role ladder/switch encountered today
enumerates both `'owner'` and `'member'`. The Kieran N6 acceptance
criterion holds.
