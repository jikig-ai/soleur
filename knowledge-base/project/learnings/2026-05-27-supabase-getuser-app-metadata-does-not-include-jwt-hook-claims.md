---
date: 2026-05-27
category: runtime-errors
module: auth
tags: [supabase, jwt, feature-flags, workspace, multi-tenant]
severity: high
affects: [settings-layout, chat-layout, billing, delegations, ws-handler, org-memberships, team-membership]
---

# Learning: Supabase getUser().app_metadata does not include JWT hook claims

## Problem

The team workspace Members tab and all org-gated features (BYOK delegations, org-switcher, team membership) silently failed for every user. The `resolveMembersTab()` function returned null, hiding the Members link from the Settings sidebar.

## Root Cause

Supabase's `auth.getUser()` endpoint returns `app_metadata` from the stored `auth.users.raw_app_meta_data` column — NOT from the JWT token claims. The custom access token hook (`runtime_jwt_mint_hook`, migration 060) injects `current_organization_id` into JWT claims at mint time but never persists it to `raw_app_meta_data`. Every call site reading `getUser().app_metadata.current_organization_id` received `undefined`.

This is a Supabase platform behavior, not a bug in the hook itself. The hook correctly modifies the JWT, but `getUser()` reads from the database, not the token.

## Solution

Added `resolveCurrentOrganizationId(userId, supabase)` which queries the `user_session_state` table directly — the same source of truth the JWT hook reads from. Migrated all 10 call sites across 8 files. Added Sentry `reportSilentFallback` for DB errors so outages surface in observability.

## Key Insight

When using Supabase custom access token hooks, `getUser()` and `getSession()` return different `app_metadata`:
- `getUser()` → stored `raw_app_meta_data` (database, no hook modifications)
- `getSession()` → decoded JWT claims (includes hook modifications)

For hook-injected claims, either use `getSession()` or query the source table directly. Direct DB query is more reliable since it doesn't depend on JWT refresh timing.

## Pre-existing Findings Fixed

1. `resolveIdentity` in `identity.ts` lacked `ORDER BY created_at` for multi-org users, producing non-deterministic org resolution.
2. Test mock in `conversations-rail.test.tsx` referenced the old deprecated function name.
3. Test mock in `team-membership-resolver.test.ts` derived `user_session_state` from `app_metadata`, masking the exact divergence this fix addresses.

## Session Errors

1. **Supabase MCP OAuth auth failed 3 times** — the localhost callback listener consumed the auth code before `complete_authentication` could process it. Recovery: used Doppler CLI + direct Supabase REST API. Prevention: when MCP auth shows "connection successful" in browser, don't paste the URL — the auth completed automatically.
2. **npx tsc from wrong directory** — ran from bare repo root instead of `apps/web-platform`. Recovery: ran from correct directory. Prevention: always `cd` to the app directory or use the worktree path for TypeScript commands.
3. **git add with doubled path prefix** — ran `git add apps/web-platform/...` while CWD was already inside `apps/web-platform`. Recovery: used `git -C <worktree-root> add ...` with paths relative to worktree root. Prevention: use `git -C <absolute-worktree-path>` for all git commands to avoid CWD-relative path confusion.
4. **git grep --include argument order** — `--include` must precede non-option arguments. Recovery: moved `--include` before the pattern. Prevention: use `git grep -l "pattern" -- "*.ts"` pathspec syntax instead of `--include`.

## Tags
category: runtime-errors
module: auth
