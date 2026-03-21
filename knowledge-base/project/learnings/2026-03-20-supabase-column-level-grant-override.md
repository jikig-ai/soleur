---
title: "Supabase column-level REVOKE is silently ineffective with table-level grants"
date: 2026-03-20
category: database-issues
module: supabase-migrations
tags:
  - column-level-security
  - postgresql-grants
  - rls
  - supabase
  - legal-audit-trail
severity: high
related_issues:
  - 911
---

# Learning: Supabase column-level REVOKE is silently ineffective with table-level grants

## Problem

The `public.users` table had an unrestricted UPDATE RLS policy that allowed authenticated users to modify their own `tc_accepted_at` timestamp -- a T&C acceptance record that must be immutable for legal compliance. The intuitive fix (`REVOKE UPDATE (tc_accepted_at) ON TABLE public.users FROM authenticated`) is silently ignored by PostgreSQL when a table-level `UPDATE` grant exists on the same table. The column-level revoke succeeds without error but has no effect, leaving the column writable.

This is a PostgreSQL privilege resolution rule: a table-level grant subsumes all column-level grants/revokes on the same table. The column-level revoke does not "punch a hole" in the table-level grant.

## Solution

Migration `006_restrict_tc_accepted_at_update.sql` applies two statements in order:

1. `REVOKE UPDATE ON TABLE public.users FROM authenticated;` -- removes the table-level UPDATE grant entirely.
2. `GRANT UPDATE (email) ON TABLE public.users TO authenticated;` -- re-grants UPDATE only on user-safe columns.

This inverts the privilege model from "all columns updatable, try to exclude some" (which PostgreSQL silently ignores) to "no columns updatable, explicitly allow safe ones" (which PostgreSQL enforces correctly).

The migration includes a maintenance comment reminding future developers to add new user-updatable columns to the GRANT list explicitly.

## Key Insight

In PostgreSQL (and by extension Supabase), **table-level grants always override column-level revokes**. When you need to protect specific columns from user updates:

1. **Revoke the table-level grant first.** Column-level revokes are no-ops while a table-level grant exists. This is documented in [Supabase's column-level security docs](https://supabase.com/docs/guides/database/postgres/column-level-security) but is a non-obvious gotcha because the REVOKE command succeeds silently.

2. **Re-grant only the columns that should be writable.** This creates a whitelist model where new columns are protected by default until explicitly added to the GRANT.

3. **Treat legal audit fields as infrastructure, not application data.** Columns like `tc_accepted_at`, `consent_recorded_at`, and similar legal timestamps should never be user-writable. They should be set by server-side functions or triggers, and protected at the database privilege level -- not just by application logic.

4. **Test privilege changes with a real UPDATE attempt.** A silent no-op revoke will pass any syntax-level check. The only reliable verification is attempting the prohibited UPDATE and confirming it fails.

## Session Errors

1. **Ralph Loop script path error** -- the initial attempt used a wrong path to invoke the Ralph Loop review script. Fix: verify script paths by reading the directory structure before executing.

2. **CWD drift after worktree creation** -- after creating the worktree, subsequent commands ran from the wrong directory. Fix: always verify `pwd` before file writes or git commands, especially after worktree creation or `cd` in a prior step.

## Related

- `2026-03-20-safe-tools-allowlist-bypass-audit.md` -- same date, similar pattern of a security bypass caused by a permissive default (allowlist bypass vs. table-level grant override)
- Issue #911 -- the tracking issue for this vulnerability
- Supabase column-level security docs -- <https://supabase.com/docs/guides/database/postgres/column-level-security>

## Tags

category: database-issues
module: supabase-migrations
