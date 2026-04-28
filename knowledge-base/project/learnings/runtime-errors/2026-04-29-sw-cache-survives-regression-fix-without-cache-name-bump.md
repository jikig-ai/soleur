---
title: Service worker cache-first survives regression fix unless CACHE_NAME is bumped
date: 2026-04-29
category: runtime-errors
related_pr: TBD
related_commits:
  - b2fed080  # PR #3014 — module-load throw observability + canary fix
---

# SW cache-first masks the regression fix until `CACHE_NAME` is bumped

## Symptom

PR #3014 deployed v0.58.0 with a corrected `NEXT_PUBLIC_SUPABASE_ANON_KEY`
inlined into the client bundle. Server health reported
`version=0.58.0, supabase=connected`. Direct inspection of the deployed
`/_next/static/chunks/8237-*.js` confirmed the inlined JWT decoded to
canonical claims (`iss=supabase, ref=ifsccnjhymdmidffkzhl, role=anon`).

The PR author's browser **continued to render the dashboard error.tsx** on
post-auth landings, despite the deploy. Server-side state was good; the
client bundle running in the browser was not the new one.

## Mechanism

`apps/web-platform/public/sw.js` registers a service worker with a
cache-first strategy for `/_next/static/**` under a single `CACHE_NAME`:

```js
const CACHE_NAME = "soleur-app-shell-v2";
// ...
event.respondWith(
  caches.match(event.request).then(
    (cached) => cached || fetch(event.request).then(/* ... cache.put */)
  )
);
```

Two stale-cache vectors compound:

1. **Stale chunk under unchanged filename.** If a chunk's content-hashed
   filename happens to be unchanged across builds (rare but possible for
   utility chunks whose content is deterministic), the SW serves the
   cached copy indefinitely.
2. **Stale HTML in a tab the user never reloaded.** If the user has an
   open tab that loaded the OLD HTML referencing OLD chunk filenames,
   client-side navigations within that tab continue to fetch those OLD
   filenames — and they're cached. Only a hard reload re-requests fresh
   HTML.

The activate handler IS designed to purge old caches:

```js
self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((names) =>
    Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
  ));
  self.clients.claim();
});
```

But it only purges caches whose name does NOT match `CACHE_NAME`. If
`CACHE_NAME` did not change between the broken build and the fix, the
single cache survives — broken chunks intact.

## Why a regression fix is special

For an additive feature, the SW behavior is acceptable: users get the
new chunks on next navigation, old ones idle in cache and eventually
get evicted. For a **regression fix on the auth surface**, that is not
acceptable — the user's browser is the source of truth for their
session, and stale code in their bundle keeps them broken until they
manually clear site data. PR #3014 did not bump `CACHE_NAME` because
the regression-fix-needs-cache-bump rule was not codified anywhere.

## Detection rule (preflight Check 8)

`plugins/soleur/skills/preflight/SKILL.md` Check 8 now fires when:

1. Branch contains a commit subject matching `^(fix\(|fix:|hotfix)` AND
2. The diff touches any of:
   - `apps/web-platform/lib/supabase/**`
   - `apps/web-platform/sentry.client.config.ts`
   - `apps/web-platform/lib/auth/**`
   - `apps/web-platform/lib/byok/**`
   - `apps/web-platform/components/error-boundary-view.tsx`

It compares `CACHE_NAME` in `apps/web-platform/public/sw.js` against
`origin/main`. Byte-equal → FAIL. Different (suffix bumped) → PASS.

## Mitigations (in order of preference)

1. **Bump `CACHE_NAME` whenever a regression fix touches the inlined
   client bundle.** One-line change; activate handler does the rest.
2. **Don't cache-first chunks at all.** A network-first or stale-while-
   revalidate strategy avoids this class entirely, at the cost of
   first-paint latency on offline / poor connections. Tradeoff is
   non-trivial — current cache-first is intentional.
3. **Bundle a content hash in `CACHE_NAME` itself** (e.g.,
   `soleur-app-shell-${BUILD_VERSION}`) so it bumps automatically per
   build. Useful but produces cache churn on every deploy — discuss
   before adopting.

## See also

- `apps/web-platform/public/sw.js` — `CACHE_NAME` declaration site
- `plugins/soleur/skills/preflight/SKILL.md` Check 8 — detection rule
- PR #3014 — the regression fix that exposed the gap
- `knowledge-base/project/learnings/runtime-errors/2026-04-28-module-load-throw-collapses-auth-surface.md` — root incident
