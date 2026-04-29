---
title: supabase-js Phoenix JOIN handshake hangs from Node shell — fix is the documented `global.WebSocket` polyfill
date: 2026-04-29
category: best-practices
tags: [supabase, realtime, websocket, node, integration-test, vitest]
related_issues: [3052, 3049, 3021]
related_upstream: [supabase/supabase-js#1559]
---

# supabase-js Phoenix JOIN handshake hangs from Node shell

## Symptom

Calling `supabase.channel("…").subscribe()` from a local Node shell against either dev (`mlwiodleouzwniehynfz.supabase.co`) or prd (`api.soleur.ai`) returns:

```text
[probe 10003ms] TIMED_OUT
[probe 10004ms] CLOSED
```

The same supabase-js code path running in production browsers (`/dashboard/chat/*`) reaches `SUBSCRIBED` in <2s. Cross-tenant integration tests (`apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`) cannot run from the operator's workstation, blocking issue #3049.

## What we already verified (all green) before suspecting the client

| Layer | Evidence |
|---|---|
| L3 firewall / DNS | `dig +short` resolves both hosts; `curl -sI -H 'Upgrade: websocket' wss://api.soleur.ai/realtime/v1/websocket` returns `HTTP 101 Switching Protocols` |
| L4 TLS / WS upgrade | `sb-project-ref: ifsccnjhymdmidffkzhl` returned in 101 response — Cloudflare routes to a real Supabase project |
| Publication / RLS | Migration 034 added `conversations` + `messages` to `supabase_realtime`; RLS is `auth.uid() = user_id` |
| Auth | `signInWithPassword` returns valid access token |

The WebSocket establishes — what fails is the Phoenix `phx_join` ⇄ `phx_reply` handshake at L7.

## Root cause

[`supabase/supabase-js#1559`](https://github.com/supabase/supabase-js/issues/1559) — Node-only race condition (closed 2025-12-15 by upstream maintainer).

When `globalThis.WebSocket` is `undefined`, supabase-js falls back to the `ws` module. The fallback path attaches the response handlers AFTER the server has already pushed `phx_reply`, so the reply is dropped on the floor and the channel sits idle until the 10s `joinTimeout`.

Browsers don't hit this: native `WebSocket` is on `globalThis` so the racy fallback is never taken.

### Environment match (verified 2026-04-29)

```text
$ node --version
v21.7.3
$ npm ls @supabase/supabase-js --prefix apps/web-platform
└── @supabase/supabase-js@2.99.2
    └── @supabase/realtime-js@2.99.2
```

Upstream issue tested Node 21.1.0 + 20.x LTS. Node 21.7.3 is the same major. The `v2.88.0` realtime-js fix mentioned in the supabase-js CHANGELOG ("handle websocket race condition in node.js") did not cover this exact path on 21.7.3 — the race still reproduces on `2.99.2`.

## Fix

Polyfill `globalThis.WebSocket` BEFORE `createClient()`. The polyfill eliminates the racy fallback path: supabase-js then uses the polyfilled global the same way it uses the browser's native `WebSocket`.

`apps/web-platform/test/helpers/node-websocket-polyfill.ts`:

```ts
import WS from "ws";

export function ensureNodeWebSocketPolyfill(): void {
  if (typeof globalThis.WebSocket === "undefined") {
    (globalThis as unknown as { WebSocket: typeof globalThis.WebSocket })
      .WebSocket = WS as unknown as typeof globalThis.WebSocket;
  }
}
```

`apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` calls `ensureNodeWebSocketPolyfill()` as the first statement of `beforeAll`, before any `createClient()`.

`ws@8.19.0` is already a top-level dep (also pulled transitively via supabase-js + happy-dom) — no new dependency.

## Two-mode probe baseline (`apps/web-platform/scripts/realtime-probe.mjs`)

Default mode applies the polyfill; `--no-polyfill` reproduces the bug for diagnostic baselines.

### Mode B (no polyfill, before fix)

```text
$ doppler run -p soleur -c dev -- node ./scripts/realtime-probe.mjs --no-polyfill
[probe] polyfill: skipped (--no-polyfill, expect TIMED_OUT)
[probe 10003ms] TIMED_OUT
[probe 10004ms] CLOSED
```

### Mode A (polyfill, after fix) — 5 consecutive runs

```text
[probe 1746ms] SUBSCRIBED   exit=0
[probe 2487ms] SUBSCRIBED   exit=0
[probe 1052ms] SUBSCRIBED   exit=0
[probe  967ms] SUBSCRIBED   exit=0
[probe 1376ms] SUBSCRIBED   exit=0
```

5/5 reach SUBSCRIBED in <2.5s. Determinism gate passed.

### Integration test (Phase 2 gate)

```text
$ doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 \
    ./node_modules/.bin/vitest run \
    test/conversations-rail-cross-tenant.integration.test.ts

 ✓ user A receives ZERO payloads from user B's INSERT  (2232ms)
 ✓ user A receives ZERO payloads from user B's UPDATE  (2450ms)
 ✓ user A receives ZERO payloads from user B's DELETE  (4488ms)
 Test Files  1 passed (1)
      Tests  3 passed (3)
```

## Why this is contained to test/probe paths (not `lib/supabase/client.ts`)

`apps/web-platform/lib/supabase/client.ts` uses `createBrowserClient` from `@supabase/ssr` — runs in the browser where `globalThis.WebSocket` is native. Production traffic never enters the racy path.

The polyfill helper lives under `test/helpers/`. It MUST NOT be imported from `lib/`, `app/`, or `server/` — Next.js tree-shakes test files out of the prod bundle, but a stray prod-side import would force `ws` into the browser chunk. Verify with `grep -r "node-websocket-polyfill" apps/web-platform/{lib,app,server}` — must return nothing.

## When you should re-run this probe

- Whenever `@supabase/supabase-js` or `@supabase/realtime-js` is bumped — there's a non-trivial chance the underlying race comes back, or the polyfill becomes unnecessary.
- When integration tests start TIMED_OUT'ing again after a Node upgrade (≥21.x).
- Before debugging any "browser works but shell doesn't" Realtime symptom — Mode B reproduces in ~10s and rules in/out the #1559 class instantly.

## Related

- Issue #3052 — this bug
- Issue #3049 — cross-tenant isolation integration test (unblocked by this fix)
- PR #3021 — the original Command Center conversation rail; integration test added there
- Upstream `supabase/supabase-js#1559` — closed 2025-12-15; documented workaround applied here
