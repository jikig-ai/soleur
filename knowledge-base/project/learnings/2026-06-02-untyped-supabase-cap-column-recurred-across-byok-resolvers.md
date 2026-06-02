# Learning: untyped-Supabase wrong-column bug recurred across both BYOK delegation read resolvers

## Problem

The "Share a key" owner toggle reported four symptoms (state not persisting after
re-login, "Couldn't share a key" error, cannot-disable, future join date). The
plan attributed symptom-1 (persistence) entirely to owner-side workspace-resolution
divergence. Multi-agent review (data-integrity-guardian) found the **more
fundamental** cause: both delegation read resolvers selected non-existent columns.

- `apps/web-platform/server/team-membership-resolver.ts` and
  `apps/web-platform/server/byok-delegation-ui-resolver.ts` selected
  `daily_cap_cents` / `hourly_cap_cents` from `byok_delegations`.
- The real columns are `daily_usd_cap_cents` / `hourly_usd_cap_cents`
  (migration `064_byok_delegations.sql:82,86`). `daily_cap_cents` exists in **zero**
  migrations — no column, no view alias.
- The Supabase client at these call sites is **untyped** (cast to a structural
  interface), so `tsc --noEmit` is silent. At runtime PostgREST returns 42703
  (column does not exist) → `delegResp.error` truthy → `delegationFromMe` is never
  populated → the owner toggle renders **OFF on every reload regardless of
  workspace**. The workspace-resolution fix was necessary but not sufficient.

This is a **second occurrence of the exact class** documented in
[[2026-06-01-untyped-supabase-select-nonexistent-column-ships-green]] (#4715/#4713)
— the prior fix patched one resolver; these two sibling resolvers carried the
identical bug and the prior guard did not cover them.

## Solution

Query the real columns via PostgREST aliases so the downstream TS shape keeps its
short key with a one-token change per select:

```ts
.select("id, grantor_user_id, grantee_user_id, daily_cap_cents:daily_usd_cap_cents")
```

Added a **source-level regression guard** (`test/byok-delegation-cap-column-names.test.ts`)
that reads both resolver files, extracts every `.select("…")` string mentioning
`cap_cents`, and asserts each uses `daily_usd_cap_cents` and never a bare
(unaliased) `daily_cap_cents`. Source-grep is the right gate here because the
chain mocks discard the select argument and `tsc` can't see untyped selects.

## Key Insight

An untyped Supabase `.select()` against a real table is an **unverified contract**:
neither `tsc` nor arg-discarding chain mocks catch a wrong column name; it ships
green and degrades to a silent `[]`/error at runtime. When a bug class recurs
across sibling files, the fix is not just "patch this file" — generalize the guard
to **enumerate every call site of the same shape** (here: every `.select` against
`byok_delegations`). A symptom the plan attributes to one mechanism (workspace
divergence) can have a second, more fundamental mechanism (column name) hiding
behind the same silent-failure surface — multi-agent review with an agent that
reads the migration body against the query string is what surfaces it.

## Session Errors

1. **`next lint` / direct `eslint` not runnable in this worktree env** — `next lint`
   opened an interactive ESLint-config setup prompt; `./node_modules/.bin/eslint`
   failed with "couldn't find eslint.config.js". — Recovery: relied on a clean
   `tsc --noEmit` + matching surrounding style; CI runs lint as the authoritative
   gate. — Prevention: treat `tsc --noEmit` (run from `apps/web-platform` via
   `./node_modules/.bin/tsc`) as the local web-platform gate; do not block a
   pipeline on `next lint` headlessly.
2. **No `psql` and no `pg` node module for prod-data verification** — could not
   directly query prod to quantify the orphaned-pre-fix-grant concern. — Recovery:
   resolved structurally (multi-workspace is deferred to #2778, so the workspace
   divergence cannot manifest today) and via Doppler (`FLAG_BYOK_DELEGATIONS=0` in
   prd, feature is Flagsmith-gated to dogfood orgs). — Prevention: for prod reads
   in this environment use the Supabase MCP or the Doppler `DATABASE_URL_POOLER` +
   bun-installed `pg` fallback chain; do not assume `psql` exists on PATH.

## Tags
category: integration-issues
module: web-platform / byok-delegations
