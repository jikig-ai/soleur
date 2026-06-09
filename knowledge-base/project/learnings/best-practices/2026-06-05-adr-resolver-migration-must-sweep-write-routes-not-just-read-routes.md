---
title: "An ADR that relocates state + migrates READ routes to a new resolver must sweep the WRITE routes too — or they keep the old failure surface"
date: 2026-06-05
category: best-practices
module: apps/web-platform/server
tags: [adr-044, resolver, tenant-boundary, observability, kb-share, partial-migration]
---

# Learning: a partial resolver migration leaves write routes on the old, divergent failure surface

## Problem

KB "Generate link" (share) failed in production for the operator even after PR #4922
fixed the dominant `workspace_id` NOT-NULL insert bug and PR #4947 surfaced the
client error. The share popup showed the new generic error ("Couldn't generate a
link") with **zero Sentry events** — the failure was invisible.

## Root cause (two compounding gaps)

1. **Partial ADR-044 migration.** ADR-044 relocated workspace/repo/readiness state
   from `users` to `workspaces` and migrated the KB *read* routes (content / tree /
   search / c4-project) to the service-role, membership-scoped
   `resolveActiveWorkspaceKbRoot`. But the *write* routes — `kb/share` and
   `kb/upload` — were left on the legacy `resolveUserKbRoot`, which mints a
   per-request TENANT client (`getFreshTenantClient`) and reads the CALLER's
   `users.workspace_status` under RLS. That column is stale/empty for users
   provisioned after the relocation, so the legacy resolver returned 503
   "Workspace not ready" while the service-role resolver (reading
   `workspaces.repo_status`) would have passed. The two resolvers compute the
   SAME path for a solo owner — the divergence is the read CREDENTIAL +
   readiness-source + an extra tenant-mint failure surface, not the path.
2. **Silent failure branches.** `createShare`'s 5 pre-insert validation returns
   (invalid-path/not-found/not-a-file/symlink-rejected/too-large) and the share
   route's resolver-error response did NOT call `reportSilentFallback` — only the
   INSERT branches did. So the failing branch left no Sentry trace, making remote
   diagnosis impossible (`cq-silent-fallback-must-mirror-to-sentry` was satisfied
   for the insert but not the pre-insert returns).

## Solution

- **Sweep the write routes onto the same resolver** the read routes already use:
  migrate `kb/share` + `kb/upload` to `resolveActiveWorkspaceKbRoot`, add a sibling
  `resolveActiveWorkspaceRepoMeta` for upload's git-push metadata (reads
  `workspaces.repo_url` + the membership-checked `resolveInstallationId` RPC, since
  `workspaces.github_installation_id` is revoked from the `authenticated` grant),
  then REMOVE `resolveUserKbRoot`. This also fixed a latent #4543 dual-ownership
  bug (an invited member's empty `users` row → "No repository connected").
- **Instrument the silent branches first** (Workstream A, shipped together): mirror
  every pre-insert validation return + the resolver-error response to Sentry with
  `reason=<code>`, so the exact branch surfaces on the next click.

## Key Insight

When an ADR relocates a state column AND migrates some consumers to a new resolver,
the migration is NOT done until EVERY consumer of the old resolver moves — **write
routes are consumers too, and they're easy to miss because the read routes "work."**
A `git grep <oldResolver>` enumerates the authoritative remaining-consumer work-list;
the migration is complete only when that grep returns 0 (function + all callers).
A divergent resolver that "works for reads" is a latent failure surface for the
unmigrated writes, and if those writes have un-mirrored failure branches the
divergence is invisible until a user hits it. Pair the migration with an
observability pass over the unmigrated route's silent returns BEFORE (or with) the
swap, so the fix is *confirmed*, not assumed.

Corollary (verified at review): when the swap resolves an id that downstream code
reuses (here `access.activeWorkspaceId` for the insert `workspace_id` AND the
`kb_files` attribution write), thread the ONE resolved id through all sites — a
second independent `resolveCurrentWorkspaceId` call re-introduces divergence on the
revoked-membership self-heal edge.

## Tags
category: best-practices
module: apps/web-platform/server
