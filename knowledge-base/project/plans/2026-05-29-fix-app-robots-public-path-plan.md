---
title: "fix: app robots.ts shadowed by auth middleware (PUBLIC_PATHS missing /robots.txt)"
date: 2026-05-29
type: fix
issue: 4587
branch: feat-one-shot-4587-robots-public-path
lane: single-domain
brand_survival_threshold: none
status: planned
---

# 🐛 fix: app `robots.ts` shadowed by auth middleware (`PUBLIC_PATHS` missing `/robots.txt`)

Ref #4587. Ref #4573 (added the unreachable `robots.ts`).

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Risks & Mitigations (precedent diff), Verification, AC6/Phase 2 (typecheck script form)

### Key Improvements
1. Added precedent-diff (Phase 4.4): `/manifest.webmanifest` is the exact sibling precedent; pattern is NOT novel.
2. Verified all negative claims and AC commands against the worktree (matcher, pre-fix grep counts, vitest binary, typecheck script).
3. Confirmed all three deepen halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped) pass.

### New Considerations Discovered
- `/manifest.webmanifest` is already public (live HTTP 200) — the issue's "verify it isn't shadowed" resolves to no-change; AC2 guards against an accidental duplicate.
- The correct AC6 form is `npm run typecheck` (script at `package.json:18`), not a raw `tsc` invocation.

## Overview

`apps/web-platform/app/robots.ts` returns `User-agent: *\nDisallow: /` to keep the app
subdomain out of search indexes. The Supabase auth middleware 307-redirects
`/robots.txt` to `/login` **before** the Next.js metadata route handler runs, because
`/robots.txt` is absent from `PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts`), the
allowlist consulted at `middleware.ts:129`. Crawlers therefore never receive the
`Disallow: /` body.

**Live-verified 2026-05-29** (this branch, plan-write time):

```
$ curl -sI https://app.soleur.ai/robots.txt
HTTP/2 307           # shadowed → /login (bug confirmed)

$ curl -s https://app.soleur.ai/manifest.webmanifest
{"name":"Soleur Dashboard",...}   # HTTP 200 JSON — already public, NOT shadowed
```

The fix is a **one-line allowlist addition** (`"/robots.txt"` → `PUBLIC_PATHS`) plus a
regression test, mirroring the identical fix already applied to `/manifest.webmanifest`
(learning `2026-03-29-pwa-manifest-auth-middleware-and-icon-purpose-types.md`).

No new dependencies. No code outside `apps/web-platform/`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| `PUBLIC_PATHS` does not include `/robots.txt`; consulted at `middleware.ts:129` | Confirmed. `routes.ts:5-29` has no `/robots.txt`; `middleware.ts:129` is `PUBLIC_PATHS.some((p) => pathname === p \|\| pathname.startsWith(p + "/"))` | Add `"/robots.txt"` to `PUBLIC_PATHS` |
| Add `/manifest.webmanifest` (verify it isn't already shadowed) | **Already present** at `routes.ts:25`; live probe returns HTTP 200 JSON, not 307 | No change needed for manifest. Note it as already-fixed; add nothing. Avoid duplicate array entry. |
| `robots.txt` is "public-by-design, no auth, no PII" | Confirmed: `robots.ts` returns a static `Disallow: /` body, no session, no DB read | Allowlisting does not widen the auth boundary |
| Middleware matcher excludes static assets but the metadata route is reachable | Matcher regex (`middleware.ts:351`) excludes `_next/*`, `favicon.ico`, `sw.js`, and image extensions only — `/robots.txt` and `/manifest.webmanifest` DO reach middleware | Confirms the shadow is real; `PUBLIC_PATHS` (not matcher) is the correct fix surface (preserves CSP headers per the 2026-03-29 learning) |
| "Add a probe to the canary/discoverability set" | No existing endpoint canary covers `app.soleur.ai/robots.txt`. `main-health-monitor.yml` and `scheduled-realtime-probe.yml` do not probe it | Covered by the `## Observability` `discoverability_test` (curl, no ssh). A standing scheduled probe is **out of scope** (see Non-Goals) given the p3-low, defense-in-depth nature |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible. The fix makes a
  defense-in-depth crawler signal (`Disallow: /`) reachable; if the allowlist entry were
  wrong (e.g., over-broad prefix), the only risk is an unintended path becoming
  session-bypassed. Mitigated by exact-string matching + a prefix-collision regression test.
- **If this leaks, the user's data is exposed via:** N/A. `/robots.txt` is a static,
  auth-free, PII-free metadata body by design; making it public does not expose any
  authenticated route. Every authenticated app route still 307s to the noindexed
  `/login`, so app content stays out of the index regardless (per #4587 Impact section).
- **Brand-survival threshold:** none.

  threshold: none, reason: change exposes only a static auth-free Disallow body and does not touch any session-gated, PII, or regulated-data surface.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `"/robots.txt"` is present exactly once in `PUBLIC_PATHS`
  (`apps/web-platform/lib/routes.ts`). Verify:
  `grep -c '"/robots.txt"' apps/web-platform/lib/routes.ts` returns `1`.
- [x] **AC2** — `/manifest.webmanifest` remains present exactly once (no duplicate
  introduced). Verify: `grep -c '"/manifest.webmanifest"' apps/web-platform/lib/routes.ts`
  returns `1`.
- [x] **AC3** — A regression test asserts `isPublicPath("/robots.txt") === true` in
  `apps/web-platform/test/middleware.test.ts` (added to the existing
  `"public paths are allowed without auth"` test or a dedicated test).
- [x] **AC4** — A prefix-collision guard asserts `isPublicPath("/robots.txt-evil")` (or
  `/robots.txtx`) is `false`, mirroring the existing `prefix collision prevention` block
  (`middleware.test.ts:80-90`). (Exact-match for `/robots.txt`; the `startsWith(p + "/")`
  arm only matches `/robots.txt/...`, so a sibling like `/robots.txtx` is correctly
  excluded — the test pins this.)
- [x] **AC5** — Web-platform test suite passes:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/middleware.test.ts`
  (runner is **vitest** per `package.json` `"test": "vitest"`; bun test is blocked by
  `bunfig.toml [test]` per #1469 — do NOT use `bun test`).
- [x] **AC6** — Typecheck clean in `apps/web-platform`: `cd apps/web-platform && npm run typecheck`
  (the package's `typecheck` script is `tsc --noEmit`, verified at `package.json:18`).
- [ ] **AC7** — PR body uses `Closes #4587` (pure code change, closes at merge — not an
  ops-remediation deferral).

### Post-merge (operator)

- [ ] **AC8** — After deploy, `curl -sI https://app.soleur.ai/robots.txt` returns
  `HTTP/2 200` (not `307`), and `curl -s https://app.soleur.ai/robots.txt` body contains
  `Disallow: /`.
  **Automation:** `/soleur:postmerge` / `/soleur:ship` post-merge verification can run this
  curl directly (no ssh, no dashboard) — bake into the ship verification rather than punt
  to a human.

## Implementation Phases

### Phase 1 — Add `/robots.txt` to the allowlist (RED → GREEN)

1. **RED:** In `apps/web-platform/test/middleware.test.ts`, add
   `expect(isPublicPath("/robots.txt")).toBe(true);` to the
   `"public paths are allowed without auth"` test (after line 23), and add
   `expect(isPublicPath("/robots.txtx")).toBe(false);` to the
   `"paths that share a prefix with public paths are NOT public"` test
   (after line 89). Run vitest → the first assertion fails (path not yet public).
2. **GREEN:** In `apps/web-platform/lib/routes.ts`, add `"/robots.txt"` to `PUBLIC_PATHS`
   with a one-line comment, e.g.:

   ```ts
   // /robots.txt: Next.js robots.ts metadata route (Disallow: /). Public-by-design,
   // no auth/PII — must bypass Supabase middleware or crawlers get 307→/login and
   // never see the Disallow body. Same class as /manifest.webmanifest (#4587, #4573).
   "/robots.txt",
   ```

   Place it adjacent to the existing `"/manifest.webmanifest"` entry (line 25) so the
   two sibling metadata routes sit together.
3. Re-run vitest → all green.

### Phase 2 — Verify

1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/middleware.test.ts`
   (`vitest` binary verified present in the worktree `node_modules/.bin/` at deepen time).
2. `cd apps/web-platform && npm run typecheck` (`tsc --noEmit`).

## Observability

```yaml
liveness_signal:
  what: "curl -sI https://app.soleur.ai/robots.txt returns HTTP 200 with a Disallow body"
  cadence: "post-deploy one-shot (ship/postmerge verification); ad-hoc thereafter"
  alert_target: "ship-phase verification output (operator-visible run log)"
  configured_in: "/soleur:ship + /soleur:postmerge post-merge curl probe"
error_reporting:
  destination: "GSC Coverage report (existing) + ship-phase curl assertion failure surfaces in the run log"
  fail_loud: "ship/postmerge curl assertion fails the post-merge check if status != 200 or body lacks 'Disallow: /'"
failure_modes:
  - mode: "robots.txt still 307s after deploy (allowlist entry typo or deploy not propagated)"
    detection: "AC8 curl returns 307 instead of 200"
    alert_route: "ship-phase verification failure → operator run log"
  - mode: "over-broad allowlist entry session-bypasses a sibling path"
    detection: "middleware.test.ts prefix-collision assertion (AC4) fails in CI"
    alert_route: "CI test failure on PR"
logs:
  where: "Cloudflare/Next.js access logs (existing); CI vitest output for the unit guard"
  retention: "existing platform defaults (no new log surface introduced)"
discoverability_test:
  command: "curl -s https://app.soleur.ai/robots.txt"
  expected_output: "HTTP 200; body contains 'User-agent: *' and 'Disallow: /'"
```

## Non-Goals / Out of Scope

- **Standing scheduled robots canary workflow.** The issue suggests "add a probe to the
  canary/discoverability set." Given the p3-low, defense-in-depth nature (the GSC-flagged
  page is already fixed by `noindex` meta on `(auth)/layout.tsx`, verified live in #4587),
  a dedicated nightly GitHub Actions probe is disproportionate. The `## Observability`
  `discoverability_test` + ship-phase curl cover the regression window. **Deferral:** if a
  standing canary is later wanted, fold it into `main-health-monitor.yml` as an extra curl
  assertion rather than a new workflow. No tracking issue filed (suggestion, not a
  committed requirement; re-open #4587 follow-up if desired).
- **`/manifest.webmanifest`** — already public (live-verified HTTP 200). No change.
- **Matcher-regex changes** — `PUBLIC_PATHS` is the correct surface (preserves CSP headers
  per the 2026-03-29 learning). Do not touch the matcher.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — single-file auth-allowlist change for a public,
auth-free, PII-free metadata route. No new user-facing UI, no schema, no infra, no
regulated-data surface.

## Research Insights

- **Direct precedent:** `knowledge-base/project/learnings/2026-03-29-pwa-manifest-auth-middleware-and-icon-purpose-types.md`
  — `/manifest.webmanifest` was added to `PUBLIC_PATHS` for the identical middleware-shadow
  reason. Key insight carried forward: prefer `PUBLIC_PATHS` over a matcher-exclusion
  because `PUBLIC_PATHS` still applies CSP headers (consistent security posture). `/robots.txt`
  is the same class.
- **Middleware matching semantics** (`middleware.ts:129`): `pathname === p || pathname.startsWith(p + "/")`
  — exact-match OR sub-path-with-trailing-slash. `/robots.txt` is a leaf path with no
  sub-routes, so the exact-match arm is what fires; siblings like `/robots.txtx` are
  correctly NOT matched (the `+ "/"` boundary prevents prefix collision). Pinned by AC4.
- **Matcher config** (`middleware.ts:351`) excludes `_next/static`, `_next/image`,
  `favicon.ico`, `sw.js`, and image extensions only. `/robots.txt` is NOT excluded → it
  reaches middleware → the `PUBLIC_PATHS` allowlist is the only thing that lets it through.
- **Test runner:** vitest (`apps/web-platform/package.json` `"test": "vitest"`). `bun test`
  is blocked by `apps/web-platform/bunfig.toml [test]` (#1469) — must use
  `./node_modules/.bin/vitest run`.
- **Test helper:** `middleware.test.ts:7` defines a local `isPublicPath` that replicates the
  `middleware.ts:129` logic over the imported `PUBLIC_PATHS` array — the unit test is a true
  guard on the array contents, not a mock.

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

**Pattern:** auth-allowlist entry for a Next.js metadata route. **Precedent exists** — this
is NOT a novel pattern. `/manifest.webmanifest` is the exact sibling, added to the same
`PUBLIC_PATHS` array for the same middleware-shadow reason (learning
`2026-03-29-pwa-manifest-auth-middleware-and-icon-purpose-types.md`, `routes.ts:25`).

Side-by-side:

```ts
// precedent (routes.ts:25) — already shipped, live-verified HTTP 200
"/manifest.webmanifest",
// this plan (routes.ts, new) — same class, same array, same matching semantics
"/robots.txt",
```

| Risk | Mitigation |
| --- | --- |
| Over-broad entry session-bypasses a sibling path | Exact-string entry; `middleware.ts:129` matches `=== p` OR `startsWith(p + "/")`; AC4 prefix-collision test pins that `/robots.txtx` stays non-public |
| CSP headers dropped for the route | `PUBLIC_PATHS` branch applies `withCspHeaders` (`middleware.ts:130`); matcher exclusion would NOT — that's why `PUBLIC_PATHS` is the correct surface (per the 2026-03-29 learning) |
| Duplicate `/manifest.webmanifest` introduced | AC2 asserts count stays 1 |
| Deploy doesn't propagate | AC8 post-deploy curl gate (ship/postmerge) |

**No new scheduled job, no SQL, no infra, no lock/atomic-write pattern** — Phase 4.4
scheduled-work and SECURITY DEFINER/atomic-write precedent checks are N/A.

## Deepen Verification Results (2026-05-29)

- Matcher regex (`middleware.ts:351`) contains no `robots` token → `/robots.txt` reaches
  middleware (negative claim confirmed; `grep -c robots` on matcher = 0).
- Pre-fix `grep -c '"/robots.txt"' routes.ts` = 0 (AC1 transitions 0→1); manifest count = 1
  (AC2 invariant holds).
- `vitest` binary present at `apps/web-platform/node_modules/.bin/vitest` (AC5 runnable in worktree).
- `typecheck` script = `tsc --noEmit` at `package.json:18` (AC6 form corrected to `npm run typecheck`).
- Live probe: `app.soleur.ai/robots.txt` → 307 (bug live); `app.soleur.ai/manifest.webmanifest` → 200 JSON (manifest already public).
- Gates 4.6 (User-Brand Impact), 4.7 (Observability 5-field, no-ssh discoverability), 4.8 (no PAT-shaped vars) all PASS.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with a `threshold: none` reason.)
- Do NOT add `/robots.txt` to the matcher exclusion regex (`middleware.ts:351`) — that
  would skip CSP header application. Use `PUBLIC_PATHS` (per the 2026-03-29 learning).
- Do NOT introduce a duplicate `/manifest.webmanifest` entry — it is already at
  `routes.ts:25` (AC2 guards this).
- Use `./node_modules/.bin/vitest run`, never `bun test` (blocked by `bunfig.toml`, #1469).
