---
title: Post-connect sync implementation patterns
date: 2026-04-10
category: implementation-patterns
tags: [scanner, health-snapshot, supabase, rls, tdd, migration, next-js]
symptoms: migration collision, type safety gap with sentinel values, icon component prop forwarding
module: apps/web-platform
---

# Learning: Post-connect sync implementation patterns

## Problem

Implementing a post-connect project health scanner and auto-triggered sync raised several integration challenges: migration number collisions from concurrent branches, type safety gaps when using sentinel values in typed columns, and UI component prop forwarding issues with SVG icons.

## Solution

### Migration collision prevention

Always merge main before creating migrations. Migration 016 was already taken by `016_github_username.sql` on main when the plan specified 016. Running `git merge origin/main` before implementation revealed the collision and allowed renumbering to 017.

### Sentinel value type safety

Using `domain_leader: "system"` as a sentinel for system-initiated conversations bypassed the `DomainLeaderId` TypeScript type. The fix: extend the union type directly (`DomainLeaderId = ... | "system"`) rather than relying on runtime string comparison. This keeps compile-time safety while avoiding a new column.

### RLS defense-in-depth for server-only columns

Migration 006 already restricts UPDATE grants to specific columns (not all), so `health_snapshot` was already protected at the privilege level. The RESTRICTIVE RLS policy is belt-and-suspenders defense following the pattern from migration 016 (`github_username`). The `IS NOT DISTINCT FROM` subquery correctly handles NULL values.

### SVG icon prop forwarding

React SVG icon components (`CheckCircleIcon`) do not forward unknown DOM props like `data-testid`. Wrap the icon in a `<span data-testid="...">` instead of passing the attribute directly to the icon component.

## Key Insight

When adding sentinel values to typed database columns, extend the TypeScript type union immediately — do not rely on runtime string comparison. The type hole is invisible until filtering logic assumes exhaustive coverage. Similarly, always merge main before creating numbered migrations to avoid collisions that only surface during integration.

## Session Errors

1. **`git commit` with wrong CWD** — Running `npx vitest` from `apps/web-platform` shifted the shell CWD. Subsequent `git add` with relative paths failed. **Prevention:** Always use absolute paths from the worktree root for git commands, or `cd` back explicitly.

2. **`npx vitest` startup error from stale npx cache** — Running from the worktree root picked up a cached vitest version missing native bindings. **Prevention:** Always `cd` to the package directory (`apps/web-platform/`) before running `npx vitest`.

3. **`data-testid` on SVG icon component** — `CheckCircleIcon` silently dropped the `data-testid` prop. Test expected 3 checkmarks, got 0. **Prevention:** Never pass `data-testid` directly to SVG icon components — wrap in a `<span>` or `<div>` element.

4. **`role="button"` on Next.js Link** — Adding `role="button"` to a `<Link>` component overrode the implicit `role="link"`, breaking a test that queried `getByRole("link")`. **Prevention:** Do not add explicit `role` attributes to `<Link>` components — the `<a>` tag provides the correct implicit role.

5. **Migration number collision** — Plan specified 016, main already had 016. **Prevention:** Always `git merge origin/main` or `git diff --name-only HEAD...origin/main -- supabase/migrations/` before creating a new migration file.

6. **Existing test referenced old step labels** — Renamed setup step labels but an existing test still asserted the old text. **Prevention:** After renaming user-visible strings, grep the test directory for the old text before committing.

## Tags

category: implementation-patterns
module: apps/web-platform
