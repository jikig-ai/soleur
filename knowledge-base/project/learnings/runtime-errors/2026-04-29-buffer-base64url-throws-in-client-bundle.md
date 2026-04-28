---
title: Buffer.from(_, "base64url") throws in client-bundle webpack polyfill
date: 2026-04-29
category: runtime-errors
related_pr: TBD
related_commits:
  - 7d556531  # PR #3007 — JWT-claims guardrails (introduced the bug)
  - b2fed080  # PR #3014 — observability/canary fix (added Sentry mirror but not the source-level gate)
---

# `Buffer.from(_, "base64url")` is Node-only and throws in browser bundles

## Symptom

After PR #3014 deployed v0.58.1 with a verified-canonical inlined JWT
(`iss=supabase, ref=ifsccnjhymdmidffkzhl, role=anon`), users continued to see
the `Something went wrong` error.tsx — on `/login` AND `/dashboard`. Hard
refresh, cleared cookies, cleared cache: no change. Diagnostic via Playwright
console capture surfaced:

```
TypeError: Unknown encoding: base64url
    at s (5376-3155e54cb192971f.js:1:2438)
    at u.from (5376-3155e54cb192971f.js:1:5109)
    at 8237-9ee97fc0757ef8e6.js:1:2622   ← supabase init module
```

## Mechanism

`apps/web-platform/lib/supabase/validate-anon-key.ts` (added in PR #3007)
contained:

```ts
const json = Buffer.from(middle, "base64url").toString("utf8");
```

`"base64url"` is a Node 16+ encoding token. **In Node, this works.** In the
browser, webpack's `buffer@5.x` polyfill ships in the client bundle —
`buffer@5.x` does NOT support the `"base64url"` encoding token, so
`Buffer.from(_, "base64url")` throws `TypeError: Unknown encoding: base64url`
at module evaluation time. The surrounding try/catch in `client.ts` (added
in PR #3014) caught the throw, mirrored to Sentry as
`feature: supabase-validator-throw`, then re-threw — so the React render
path bailed out and `error.tsx` rendered.

## Why every existing gate missed it

| Gate | What it ran | Why it missed |
|---|---|---|
| Vitest unit tests (PR #3007) | Node env (default) | Node has native `base64url`; tests passed |
| Vitest unit tests (PR #3014) | Node env | Same — tests covered claim shapes, not encoding compatibility |
| `tsc --noEmit` | TypeScript types only | `BufferEncoding` includes `"base64url"`; types are wrong about runtime |
| Layer 1 canary (curl /login + /dashboard) | SSR HTML over HTTP | The throw is client-only; SSR HTML renders fine |
| Layer 3 canary (bash JWT decode) | bash `base64 -d` | Tests claim shape, doesn't exercise `Buffer.from` polyfill |
| Sentry alert | Real browser at runtime | Alert fires AFTER users hit the bug — too late |

The single shared assumption was that **vitest's Node env is a faithful
proxy for the browser bundle**. It is not. `Buffer.from`, `crypto.subtle`,
`fetch`, `URL`, `process.versions` — these all behave differently in the
browser-polyfilled runtime than in Node, and any of them in client-bundle
code at module load is a regression vector.

## The fix

Decode base64url manually using browser-safe primitives (`atob` is native
since Node 16 AND in all browsers):

```ts
const base64 = middle.replace(/-/g, "+").replace(/_/g, "/");
const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
const json =
  typeof atob === "function"
    ? atob(padded)
    : Buffer.from(padded, "base64").toString("utf8");
```

The conditional preserves SSR/Node fallback for environments without `atob`
(Node ≤15 — currently unreachable in this repo, but cheap).

## The systemic gate (preflight Check 9)

`plugins/soleur/skills/preflight/SKILL.md` Check 9 ("Node-Only Encodings
Banned in Client-Bundle Paths") greps the canonical client-bundle path list
for `Buffer\.from\([^)]*"base64url"`. Match → FAIL with file/line. The
ban-list is extensible; future Node-only-API regressions add an entry plus
a `**Why:**` pointer to the discovery learning file.

## The systemic safety net (Layer 2 canary, promoted from deferred)

`knowledge-base/engineering/ops/runbooks/canary-probe-set.md` Layer 2
(headless chromium hydrating `/login` + `/dashboard` and rejecting on any
`pageerror` / console.error) was deferred as D1 in PR #3014. Post-incident
it is **required** — the only gate that exercises the production browser
runtime including webpack's polyfill chain. Implementation (Playwright in
the canary container) is tracked separately; until it lands, Check 9 + the
jsdom test pattern are the load-bearing gates.

## Test pattern

`apps/web-platform/test/lib/supabase/validate-anon-key-browser-decode.test.ts`
patches `Buffer.from` to throw on `"base64url"`, then exercises the
validator. This is the GREEN gate for the browser-safe decoder. The
sentinel test (`Buffer.from(_, "base64url") is genuinely patched`) locks in
the patching so future regressions cannot bypass the test by accidentally
removing the mock.

## See also

- `apps/web-platform/lib/supabase/validate-anon-key.ts` — fix site
- `apps/web-platform/test/lib/supabase/validate-anon-key-browser-decode.test.ts` — regression-class test
- `plugins/soleur/skills/preflight/SKILL.md` Check 9 — source-level gate
- `knowledge-base/engineering/ops/runbooks/canary-probe-set.md` — Layer 2 promotion to required
- `knowledge-base/project/learnings/runtime-errors/2026-04-28-module-load-throw-collapses-auth-surface.md` — root incident
- `knowledge-base/project/learnings/runtime-errors/2026-04-29-sw-cache-survives-regression-fix-without-cache-name-bump.md` — adjacent miss
