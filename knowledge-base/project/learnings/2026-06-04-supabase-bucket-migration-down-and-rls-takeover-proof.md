---
title: Supabase storage-bucket migration — down.sql can't DELETE storage tables, and column-takeover proof needs permissive-vs-restrictive RLS reasoning
date: 2026-06-04
category: database-issues
tags: [supabase, storage, rls, migration, down-migration, doppler, pg, feat-workspace-logo-upload]
module: apps/web-platform/supabase/migrations
issue: 4916
---

# Learning: Supabase bucket-migration down.sql + RLS column-takeover proof

## Problem

Applying + live-verifying migration 098 (a new private `workspace-logos` Storage
bucket + owner-only RLS) on DEV via the Doppler `DATABASE_URL_POOLER` + node-pg
fallback surfaced three things the plan got wrong or under-specified — each of
which will recur on the next storage-bucket migration:

1. **`down.sql` cannot `DELETE FROM storage.objects` / `storage.buckets`.**
   The plan prescribed "delete objects → delete bucket row" (so the bucket row
   drop wouldn't orphan objects). Both statements fail at runtime:
   `ERROR: Direct deletion from storage tables is not allowed. Use the Storage
   API instead.` — Supabase installs a platform `BEFORE DELETE` trigger
   `protect_objects_delete` → `storage.protect_delete()` on BOTH tables.
2. **A "no client write policy" assertion is imprecise** if it only counts
   policy names. `public.workspaces` carries a RESTRICTIVE `FOR ALL` policy
   (`workspaces_jti_not_denied`, `polpermissive=false`) in addition to the
   PERMISSIVE `workspaces_select_for_members` SELECT policy.
3. **The Supabase pooler presents a self-signed CA chain.** node-pg with
   `ssl: { rejectUnauthorized: true }` aborts with `self-signed certificate in
   certificate chain`.

## Solution

1. **down.sql for a bucket migration reverts only SQL-droppable objects**
   (policies → function → column). Do NOT attempt `DELETE FROM
   storage.{objects,buckets}`. Bucket + object teardown is a Storage-API /
   operator concern (rare rollback path; an empty orphan bucket is harmless once
   the column/route are gone). This matches the 019/042 precedent (no SQL bucket
   teardown); migration 071's `DELETE FROM storage.buckets` is a dormant bug that
   would fail if ever run. Runtime object cleanup goes through the Storage API
   (`service.storage.from(bucket).remove([...])`) — that path is allowed; only
   direct SQL `DELETE` is blocked.

2. **Column-takeover ("no client can set this column") is proven against
   PERMISSIVE policies, not policy names.** PostgreSQL RLS requires a passing
   PERMISSIVE policy for a command; RESTRICTIVE policies (`AS RESTRICTIVE`,
   `polpermissive=false`) can only further *deny*, never *grant*. So assert: no
   PERMISSIVE INSERT/UPDATE/DELETE/ALL policy exists, AND behaviorally an
   authenticated `UPDATE` of the column affects **0 rows**. A RESTRICTIVE
   `FOR ALL` policy in the list is a red herring.
   ```sql
   SELECT polpermissive,
     CASE polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                 WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL' END cmd
   FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='<table>';
   -- takeover-safe iff no row has (polpermissive=true AND cmd in INSERT/UPDATE/DELETE/ALL)
   ```

3. **For the transient DEV verification script** (node-pg, not committed,
   operator machine), mirror the canonical `run-migrations.sh` posture: it runs
   `psql "$DATABASE_URL"` with Supabase's `sslmode=require` (encrypt, CA not
   pinned). The node-pg equivalent is `ssl: { rejectUnauthorized: false }` with
   an inline comment that it's transient/dev-only and matches the canonical
   runner. No committed/runtime code disables TLS verification. (A stricter
   alternative is pinning Supabase's published CA, but that's overkill for a
   throwaway verify script.) Also: use session-mode (`:6543`→`:5432`) for
   multi-statement DDL, write the tracking row (`_schema_migrations` with
   `git hash-object` content_sha) in the SAME transaction, and run a pre-apply
   collision check against `origin/main`.

## Key Insight

Plan-prescribed SQL for Supabase Storage teardown and RLS-policy enumeration are
**preconditions to verify live, not facts** — the `protect_delete` platform
trigger and the permissive/restrictive policy split are both invisible from the
plan's conceptual narrative and only surface when you apply + probe against a
real Supabase project. Live DEV verification (apply → catalog-shape → behavioral
RLS probes → down-revert, all ROLLBACK-wrapped where they shouldn't persist) is
what turned three latent ship-breakers into pre-merge corrections.

## Session Errors

- **down.sql `DELETE FROM storage.{objects,buckets}` blocked by `protect_delete`** — Recovery: rewrote down to drop policies/function/column only; documented Storage-API-only bucket teardown. Prevention: /work Supabase fallback chain now notes the trigger (routed below).
- **AC5b "only one policy" claim imprecise (RESTRICTIVE jti policy present)** — Recovery: re-derived the proof as "no PERMISSIVE write policy" + behavioral 0-row UPDATE probe. Prevention: this learning's §2 query.
- **node-pg `rejectUnauthorized:true` → self-signed CA chain** — Recovery: `rejectUnauthorized:false` for the transient dev verify script, mirroring run-migrations.sh `sslmode=require`. Prevention: this learning's §3.
- **vitest `@/server/observability` mock dropped transitive `hashUserId`** — Recovery: `vi.importActual` spread + override only the spied export. Prevention: already in /work SKILL.md vitest catalogue (wrapper-extension mock-sweep).
- **`@sentry/nextjs` mock missing `addBreadcrumb`** (rate-limiter path) — Recovery: added to the mock. Prevention: when a test exercises a 429/rate-limit path, the Sentry mock must include `addBreadcrumb`.
- **mock call-history accumulated across tests** — Recovery: `vi.clearAllMocks()` in `beforeEach` + re-set resolved values. Prevention: already covered (bun/vitest leak rules).
- **CSRF 403 on test happy-path** — Recovery: omit `Origin` (non-browser path passes). Prevention: route tests that don't exercise CSRF should send no Origin; set a disallowed Origin only for the explicit CSRF case.
- **`new File([Buffer])` tsc BlobPart error** — Recovery: wrap in `new Uint8Array(buf)`. Prevention: noted.
- **legal-doc-shas drift on legal-doc edits** — Recovery: `sha256sum docs/legal/<doc>.md` → refresh `legal-doc-shas.ts`. Prevention: already enforced by the #4289 guard (caught it at full-suite gate).
- **`hasLogo` required-field widening broke 4 fixtures** — Recovery: swept fixtures (tsc-driven). Prevention: the cross-consumer type-widening grep (already a hard rule) — tsc surfaced all sites.
- **Background `grep` exit masked vitest non-zero** — Recovery: read the log tail for the real `Tests N failed` line. Prevention: already an AGENTS rule (capture `rc=$?` explicitly).
- **CWD drift into `apps/web-platform` broke `git add`** — Recovery: `cd <worktree-root> &&` before git. Prevention: already an AGENTS rule.
- **nav-states `/dashboard/kb` cold-compile 30s timeout** — one-off/environmental: CI green on main; same route loaded warm (474ms) in the same run; `gotoOrSkip` doesn't retry slow compiles. Not a regression (my diff adds no module to the KB route graph). No fix.
- **`bun add pg` hoisted to `/tmp/node_modules`** — one-off: required via `/tmp/node_modules/pg`. No fix.
