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

Originally tracked as [`supabase/supabase-js#1559`](https://github.com/supabase/supabase-js/issues/1559) — a Node-only race in the `realtime-js` ws-fallback constructor (closed 2025-12-15 upstream).

In the installed `@supabase/realtime-js@2.99.2`, the fallback path was removed in favor of an explicit failure: `lib/websocket-factory.ts` returns `{ type: 'unsupported', error: 'Node.js X detected without native WebSocket support' }` on Node <22 with no `globalThis.WebSocket`. The client's `connect()` then throws, the realtime client transitions to `disconnected`, and the channel's `subscribe()` sits in the reconnect loop until `joinTimeout` fires at 10s — producing the same `TIMED_OUT → CLOSED` sequence the upstream issue described, via a different code path.

Setting `globalThis.WebSocket = ws` BEFORE `createClient()` pushes the factory into its `type: 'native'` branch (the same branch the browser path uses), so subscribe completes deterministically.

Browsers don't hit this: native `WebSocket` is on `globalThis` so the unsupported branch is never reached.

The upstream issue documents `transport: ws` as an alternative workaround (passed via `createClient` options). The polyfill was chosen here because it does not require changing the `createClient` signature in test code, mirrors the browser path more closely, and is a single shared helper rather than per-call configuration.

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
- Issue #3060 — follow-up: nightly or pre-merge realtime determinism gate in CI
- PR #3021 — the original Command Center conversation rail; integration test added there
- Upstream `supabase/supabase-js#1559` — closed 2025-12-15; the documented workaround was applied here

## Session Errors

- **Wrong root-cause mechanism in first draft of this learning** — I encoded the upstream issue's documented mechanism ("ws-fallback path drops phx_reply before handlers attach") but the installed `realtime-js@2.99.2` no longer has a ws-fallback — its factory returns `unsupported` on Node <22. Same end-symptom, different code path. **Recovery:** git-history-analyzer agent verified against `node_modules/@supabase/realtime-js/dist/main/lib/websocket-factory.js` and flagged the drift; learning rewritten to describe the installed mechanism with the upstream issue retained as historical context. **Prevention:** when documenting a workaround for an upstream issue, verify the mechanism against the installed library source (`node_modules/<pkg>/`) rather than relying on the upstream issue's prose — major version churn between issue-close and version-installed can change the failing code path while preserving the symptom.

- **P1 probe race: `setTimeout(30s)` bypassed the `resolved` guard and was never cleared** — a late SUBSCRIBED at t≈29.9s could have exited code 3 if `removeAllChannels()` took >100ms, masking a successful run as a hard timeout. **Recovery:** code-quality-analyst + code-simplicity-reviewer both flagged the race; fixed by capturing the timer handle, calling `clearTimeout` inside `finish()`, and guarding the timer body with `if (resolved) return`. **Prevention:** for any harness that owns both an "early success" callback and a "hard deadline" timer, the timer body MUST re-check the success-flag before exiting, and the success path MUST clear the timer. Belt-and-suspenders.

- **Unhandled promise rejection on `removeAllChannels()`** — the cleanup promise had no `.catch` arm, so a torn-down-socket rejection during exit would log `UnhandledPromiseRejection` and skip the verdict exit. **Recovery:** added a no-op rejection arm so cleanup is best-effort and the exit code reflects the verdict. **Prevention:** in `process.exit()` shutdown paths, treat cleanup as best-effort — the verdict is already determined; never let a cleanup rejection eat the exit code.

- **TDD gap on the polyfill helper** — shipped `ensureNodeWebSocketPolyfill` without a unit test, violating `cq-write-failing-tests-before`. **Recovery:** test-design-reviewer flagged; added `node-websocket-polyfill.test.ts` covering all three behaviors (assigns when undefined, no-op when defined, idempotent). **Prevention:** the work skill's TDD gate already requires this; the failure was rationalizing "the integration test covers it" — but the integration test gates on `SUPABASE_DEV_INTEGRATION=1` and never exercises the helper's three internal contracts in CI. Helper-level unit test is what protects against future "simplification" PRs that remove the guard.

- **Bash CWD non-persistence between tool calls** — relative paths like `apps/web-platform/...` failed with "No such file or directory" between Bash calls because the tool starts each call from the worktree root, not the CWD of the prior call. **Recovery:** chain `cd <abs> && <cmd>` in a single call, or use absolute paths everywhere. **Prevention:** already documented in AGENTS.md (`cd <abs-path> && <cmd>` in a single Bash call); the gap was momentary forgetfulness, not a missing rule.

- **Initial TS2352 on the polyfill cast** — `(globalThis as { ... }).WebSocket = WS as unknown as ...` was rejected because `typeof globalThis` doesn't sufficiently overlap with `{ WebSocket: typeof WebSocket }`. **Recovery:** added outer `as unknown as` to launder; review later collapsed to `(globalThis as { WebSocket?: unknown }).WebSocket = WS` which is both shorter and matches `safe-session.test.ts` precedent. **Prevention:** when polyfilling a global, prefer the optional-property cast `(globalThis as { X?: unknown })` over the structural-shape cast — TS treats `globalThis` as a wide structural type and the optional form passes type checking without a double cast.

- **Plan subagent didn't pre-create `knowledge-base/project/specs/<branch>/`** — `session-state.md` write target was missing. **Recovery:** `mkdir -p` before write. **Prevention:** the plan skill should ensure the specs directory exists before any pipeline-orchestrator step writes session-state.md (or session-state.md write should self-create the parent directory).

- **Context7 MCP quota exhausted mid-deepen** — `Monthly quota exceeded` mid-research. **Recovery:** fell back through `gh api` → `npm view` → WebFetch and reached the same evidence. **Prevention:** plan/deepen-plan should treat MCP doc-tools as best-effort (already do), but the fallback chain (gh api / npm view for version state, WebFetch for changelogs) deserves to be the documented first-line approach for library-version evidence — Context7 is a nice-to-have, not a load-bearing tool.

- **WebFetch 404 on realtime-js CHANGELOG** — `github.com/supabase/realtime-js/blob/master/CHANGELOG.md` returned 404; the path moved when the repo restructured. **Recovery:** supabase-js CHANGELOG had sufficient realtime-tagged entries. **Prevention:** when an upstream package's CHANGELOG WebFetch 404s, fall back to the parent-package CHANGELOG (monorepo-pinned releases often surface upstream entries) or the GitHub release notes endpoint.
