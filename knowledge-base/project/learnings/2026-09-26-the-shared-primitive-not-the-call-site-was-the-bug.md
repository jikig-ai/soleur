---
title: the shared primitive — not the call site — was the bug
date: 2026-09-26
category: workflow-patterns
tags: [caching, ttl, matcher, middleware, review-panel, security, lru]
module: apps/web-platform
symptoms: [unbounded-staleness-claim, sliding-ttl-in-security-cache, matcher-suffix-bypass-on-dynamic-routes, battery-log-loss]
issue: "#5531 #5532 #5533 #5654"
pr: "#8903"
---

# The shared primitive — not the call site — was the bug

## Problem

PR #8903 built two "≤30 s bounded-staleness" verdict caches in middleware on top of the existing `lib/feature-flags/lru-cache.ts`. Every layer I wrote was correct — positive-only store predicates, read-time version rechecks, fail-closed misses — and four review seats still converged on one P1 that none of my call-site tests could see: `LRUCache.get()` refreshed `entry.at` on every hit, making expiry **sliding**. Under exactly the traffic profile the caches existed for (a dashboard issuing ~10 req/few-seconds), a `paid → unpaid` flip or a member revocation stayed invisible for the whole access-token lifetime, not 30 s. The class's `at` field was doing double duty — TTL clock *and* implicit freshness anchor — and the reordering Map already carried the LRU recency, so the refresh was pure poison with no consumer signaling intent.

A second P2 had the same shape one level up: the matcher exclusion `.*\.(svg|png|…)$` was written as a path-pattern thought ("skip image files") while the property it controlled was request-space ("skip any pathname an attacker can shape") — so `/api/kb/file/x.png` on a `[...path]` catch-all skipped the revocation/T&C/billing/unpaid gates entirely. My Guard-1 test asserted route *patterns* (directory names that literally spell `[...path]`) and was structurally blind to the request-path space those patterns generate.

## Solution

Fix the primitive, not the call site:

- `lru-cache.ts`: `get()` no longer touches `entry.at` — absolute write-anchored expiry for every consumer (the shared `_roleCache` gets strictly better bounded behavior too). The Map delete/set already carried recency; `at` was only ever the TTL clock.
- `middleware.ts`: gate `tcRowCache.set` with `!tcRowHit` — a served hit re-writing its own row was a *second* refresh channel under absolute TTL. Two-layer thinking: removing the refresh in `get()` is not enough if any hit path re-`set`s.
- Matcher: exclusion narrowed to `_next/*`, `favicon.ico`, `sw.js`, `icons/`, and single-segment `[^/]+\.ext$` filenames — every nested `.ext` pathname now traverses middleware, which is the safe direction (running a gate costs a lookup; skipping it costs the gates).
- Guard-1: walk `app/**/route.ts` (not `app/api`), strip `(group)` segments, and substitute a `.png` request-pathname probe into every dynamic-terminal route — asserting the *request space*, not the directory names.

## Prevention

- **When a security property is claimed over a shared primitive, verify the primitive's semantics — not the wrapper's.** "TTL-bounded" meant something different in the class than at the call site; the divergence lived where nobody re-read it. Before writing bounded-freshness claims on top of any cache/clock/map, name the anchor: `createdAt` vs `lastAccessAt` vs `lastCheckAt`, and grep every write path that could re-stamp it (a `.set` on the read path is a refresh in disguise).
- **A pattern match on filenames is not a match on the space those filenames generate.** Every guard that walks a tree and asserts per-member must include at least one member per *shape the pattern can't express*: bracketed segments → substituted request pathnames; route groups → stripped paths; catch-alls → extension-suffixed values. `dir-list ∩ assertion` proves nothing about `request-space ∩ exclusion`.
- **Commit-hook batteries that clean their run dir on exit must persist the failure tail first** — two consecutive ~2h `test-all --affected` runs produced `bun-test 🥊` with zero diagnostic output because the tempdir was gone before triage. Run 3 succeeded only because the real failure list was captured to a persistent file on retry.
- **Session errors (this session):** battery failure output lost to tempdir cleanup (×2); `*/` inside a `/**/` JSDoc comment (`app/api/**/route.ts`) silently terminating the block — use `//` lines near glob spellings; `Promise.resolve(thenable)` required before `.catch` on PostgREST builders (recurs — three sites now carry the comment); zero-padded `ADR-0253` vs the corpus's `ADR-N` convention (check-adr-ordinals caught it at plugins/soleur); a staged-index race — `git add` during a running `git commit` rides into the commit object (worked as intended but non-obvious); issue-filing gate rejected missing milestone/`User-Impact`/approximate `Fix-Size` — plain integers only.
- **Prevention (battery log):** `scripts/test-all.sh` should tee the failing suite's last N lines to a durable path (e.g. `$SOLEUR_STATE_DIR/logs/`) before cleanup — a `trap` that preserves diagnostics costs one line per run and saves a 2h blind re-run.
- **Prevention (PromiseLike):** codebase rule of thumb — anything `PostgrestBuilder`-shaped needs `Promise.resolve(...)` before `.catch`; the type-checker catches it (PromiseLike lacks `.catch`), but only if the `.catch` is attempted — an *unarmed* chain is invisible to tsc and fails at runtime on the unhappy path.
