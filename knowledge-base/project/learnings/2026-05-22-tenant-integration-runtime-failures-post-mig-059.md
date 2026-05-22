---
date: 2026-05-22
category: best-practices
tags: [supabase, migrations, tenant-isolation, ci, contract-pairing]
related-prs: [4339, 4225, 4294]
related-issues: [4342, 4338]
---

# NOT NULL constraints + SECURITY DEFINER RPC bodies are a contract pair

## Problem

PR #4225 (team-workspace) added migrations 053–060 which introduced the
`workspaces` + `workspace_members` tables, the `workspace_id` column on
six write tables (`conversations`, `messages`, `kb_share_links`,
`audit_github_token_use`, `scope_grants`, `audit_byok_use`), and the
matching `workspace_id NOT NULL` + CHECK constraints in mig 059. Mig 061
re-issued `record_byok_use_and_check_cap` with a 6-arg `p_workspace_id`
signature; mig 062 re-issued `remove_workspace_member`. But mig 059
silently left `grant_action_class` (mig 051) at its old 2-arg shape
INSERTing `(founder_id, action_class, tier)` — without `workspace_id`.
Every production caller (POST `/api/scope-grants/grant`) and every test
caller (13 sites) failed with 23514 on the next `grant`.

Migration 053:139 also REVOKEd `is_workspace_member` from service_role
"for prod security posture" — but tenant-iso integration tests call the
helper via `SUPABASE_SERVICE_ROLE_KEY` and fail 42501.

The issue body (#4342) named 2 failure classes. The actual CI log
(`gh run view --log-failed`) showed 8+ failures across 6 root-cause
classes (A: scope_grants 23514, B: is_workspace_member 42501, C:
record_byok PGRST202, D: conversations.workspace_id 23502 across 4
sites, E: DSAR over-broad SELECT, F: remove_workspace_member 3rd-arg
mismatch). The CI failures were the canary catching contract divergence
the migration author never sweep-grep'd.

## Pattern (the gate)

When a migration adds a `NOT NULL` constraint to a column on a table
that has SECURITY DEFINER RPC writers, every RPC writing to that table
**MUST** be re-issued in the same migration (or an immediate follow-up):

```bash
# Discovery grep at plan time:
#   for table T getting NOT NULL on column C, find every RPC writing T
git grep -nE "INSERT INTO public\\.${TABLE}" apps/web-platform/supabase/migrations/ \
  | grep -v "${TABLE}_no_mutate" \
  | grep -v "DROP\\|REVOKE"
```

Each match is a contract pair: the new CHECK invariant and the RPC body
that must satisfy it. Skipping a sweep leaves silent contract drift that
surfaces as CI canary failures days later (best case) or as 500 errors
in production (worst case — the deepen-pass discovery for this PR
identified 4 production INSERT sites at risk).

## Sharp edge: service-role GRANT ≠ authenticated GRANT

Tests using `SUPABASE_SERVICE_ROLE_KEY` bypass RLS but still need
`GRANT EXECUTE` on SECURITY DEFINER functions. Migration 053's
`REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` is
correct prod security posture (no role should be able to call
`is_workspace_member` arbitrarily — it's an RLS substrate). But tests
that exercise the helper via service-role need an explicit additive
`GRANT EXECUTE ... TO service_role` in a downstream migration. The
function is read-only and side-effect-free with a pinned `search_path`;
service_role already SELECTs `workspace_members` directly without RLS,
so the GRANT is functionally equivalent in access pattern.

## Sharp edge: solo-canary invariant as derivation source

When the RPC needs `workspace_id` and the caller can't supply it (back-
compat constraint), derive it from the solo-canary predicate
established by the original backfill migration. For workspace_id post
mig 059: `workspace_members WHERE user_id = founder_id AND workspace_id
= founder_id AND role = 'owner'`. This invariant holds because
`handle_new_user` (mig 053) provisions exactly one solo-backfill row
per new user at signup. Multi-workspace support requires widening the
RPC to accept explicit `p_workspace_id`; track via Future Work.

## Sharp edge: fixture-leak from handle_new_user

`handle_new_user` provisions a solo backfill `workspace_members` row
for every `auth.users` row. Tests that synthesize multiple users via
`auth.admin.createUser` and then INSERT them into a shared workspace
end up with N+1 rows per user (their own solo backfill + the shared).
Any test that asserts `count = 1` for a user's membership must scope
`.eq("workspace_id", fixture.workspaceId)` — unscoped queries return 2.

## Sharp edge: silent fallback masks signature mismatches

The DSAR test's `if (rmErr) { fallback DELETE }` clause masked a
3-arg-vs-2-arg `remove_workspace_member` signature mismatch for ~24h
because the direct DELETE succeeded and the post-state assertion still
passed (against the wrong workspace scope, no less). Defense-in-depth
fallbacks are fine but the primary RPC call must match the canonical
signature; otherwise the fallback becomes the test's only contract
verification.

## Detection

1. **At migration-author time:** before adding `NOT NULL` to column C
   on table T, grep `apps/web-platform/supabase/migrations/` for every
   `INSERT INTO public.T` (excluding mutation-guards, REVOKEs). Every
   match is an RPC that must be re-issued in the same migration.
2. **At review time:** if a migration adds `NOT NULL`, the reviewer
   should ask "what RPCs INSERT to this table without the new column?"
3. **At CI time:** the `tenant-integration.yml` workflow is the canary
   for this class — it exercises production code paths against the
   actual dev-Supabase schema. A single failing tenant-iso test is
   often a 5-class iceberg.

## Resolution shape

Single `CREATE OR REPLACE`-only migration (`063`) repairs both classes
A + B. Down migration restores pre-fix RPC body verbatim (knowingly
broken state — documented in down-file header). Test fixtures get four
mechanical updates (Class C: add `p_workspace_id`; Class D: add
`workspace_id: user.id` to 4 conversations.insert sites; Class E: scope
SELECTs by `workspace_id = fixture.workspaceId`; Class F: drop the
phantom 3rd arg). No application code changes — the API surface of
`grant_action_class` is preserved.
