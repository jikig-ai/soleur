---
issue: 3052
type: bug-fix
classification: investigation-then-fix
related_prs: [3021]
related_issues: [3049]
related_upstream_issues: [supabase/supabase-js#1559]
requires_cpo_signoff: false
created: 2026-04-29
deepened: 2026-04-29
branch: feat-one-shot-3052-supabase-realtime-join-timeout
---

# fix: supabase-js Phoenix JOIN handshake times out from local shell despite WS upgrade succeeding

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Hypotheses, Acceptance Criteria, Implementation Phases, Risks, Test Strategy
**Research sources used:** supabase-js CHANGELOG (live), supabase/supabase-js#1559 (live `gh api`), Supabase Realtime troubleshooting docs (search-surfaced), local `npm ls` + `npm view`, repo `node --version`.

### Key Improvements

1. **Root cause is identified upstream as a documented Node.js race condition** (supabase/supabase-js#1559, closed 2025-12-15). The plan's prior H1 (version pin) and H4 (auth shape) framing is replaced with a concrete known-cause-and-known-workaround flow: **`global.WebSocket` is `undefined` in Node, supabase-js falls back to `ws`, but the handler-registration vs `phx_reply` race causes the reply to be lost — silent `TIMED_OUT` after 10s.** The documented workaround is to set `global.WebSocket` to a polyfill *before* creating the supabase client.
2. **Concrete version evidence collected at deepen time:** installed = `@supabase/supabase-js@2.99.2` + `@supabase/realtime-js@2.99.2`; latest = `2.105.1` (`npm view @supabase/supabase-js version` ran 2026-04-29). Six minor versions of fix-relevant churn between installed and latest, including `v2.81.0 implement V2 serializer`, `v2.88.0 handle websocket race condition in node.js`, `v2.100.0 use phoenix's js lib inside realtime-js`, `v2.105.0 Realtime deferred disconnect`, `v2.105.1 surface real Error on transport-level CHANNEL_ERROR`. The v2.88 entry directly targets this issue class — but the issue still reproducing on `2.99.2` indicates either the v2.88 fix didn't cover Node 21.7.3, or there's a regression between v2.88 and v2.99.
3. **Operator's Node version (`v21.7.3`) matches the original #1559 environment exactly** ("Node.js Version: 21.1.0 (also tested with 20.x LTS)"). Confirms the race-condition class — not a Cloudflare/middlebox/Phoenix-vsn issue.
4. **Two fix paths now ranked by confidence:** Path A (apply documented `global.WebSocket` polyfill in the integration test fixture and probe — lowest risk, doesn't touch app code) is preferred over Path B (bump supabase-js across 6 minor versions — wider blast radius, may carry breaking changes). Plan defaults to Path A; Path B is fallback if Path A fails.
5. **Probe script adopts Phoenix V2 serializer awareness** — must use `vsn=1.0.0` if falling back to raw WS, but more importantly, any polyfill must register `WebSocket` BEFORE `createClient()` to avoid the race.

### New Considerations Discovered

- The `ws` package is a transitive dep via supabase-js — already installed; no new dep needed for the polyfill.
- Vitest unit-test setup at `apps/web-platform/test/ws-client-resume-history.test.tsx` already mocks `globalThis.WebSocket` for unit tests but does NOT inject a real `ws`-backed polyfill for integration tests; the integration test's `createClient` path therefore hits the same race.
- `apps/web-platform/lib/supabase/client.ts` uses `createBrowserClient` from `@supabase/ssr` — that's the browser wrapper, not relevant to Node/shell. Shell code paths use `@supabase/supabase-js` `createClient` directly. The fix lives at the test fixture / probe layer, not in `lib/supabase/client.ts`.
- Risk #5 (Phoenix vsn= server-side moving target) is downgraded — the symptom is reproducible-cause-known, not a server-side surprise.

## Overview

Issue #3052 reports that `@supabase/supabase-js` channel `.subscribe()`
calls run from a local shell time out at the Phoenix JOIN step (10s
`joinTimeout` → `CLOSED`) against both the dev project
(`mlwiodleouzwniehynfz.supabase.co`) and prd (`api.soleur.ai`). The
WebSocket upgrade itself succeeds (`HTTP 101 Switching Protocols`
confirmed via curl), yet no `phx_reply` ever arrives. Production
browsers running the same supabase-js code path subscribe successfully.

The blocking consequence: the cross-tenant Realtime isolation
integration test
(`apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`)
— the load-bearing HARD MERGE GATE behind PR #3021 — cannot run from
this environment, so issue #3049's verification step remains stuck.

This plan investigates the root cause across three layers (Phoenix
protocol version, supabase-js client config, network/middlebox), lands
a fix or environment workaround, and unblocks #3049.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `@supabase/supabase-js@x.y.z` (TBD) | `apps/web-platform/package.json` declares `"@supabase/supabase-js": "^2.49.0"` | Plan resolves the actual installed version via `npm ls @supabase/supabase-js` in Phase 1 before hypothesis testing. Bumping is one possible fix path, not a prescribed action. |
| Migration 034 already adds `conversations` + `messages` to `supabase_realtime` publication | Confirmed (PR #3021 included this migration). Issue body verifies this is not the cause. | Plan does not re-verify; treats as solved infrastructure. |
| TLS WS upgrade returns `HTTP 101` with `sb-project-ref: ifsccnjhymdmidffkzhl` | `api.soleur.ai` is the prd Realtime endpoint; the `sb-project-ref` returned proves Cloudflare is routing to a real Supabase project. | Plan accepts L3 (firewall, DNS, routing) and L4 (TLS, WS upgrade) as already verified — investigation is L7-only. |
| `use-conversations.ts:243-246` defensive client-side `user_id !== uid` drop is the layer 3 isolation defense | `apps/web-platform/hooks/use-conversations.ts` lines 224-282 use `.channel("command-center")` with `.subscribe()` — this matches the failing reproducer pattern in the issue. | Plan uses the same `.channel("name").subscribe()` form as the production hook in its reproducer fixture. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing
regression — this is an investigative debugging task. The risk is
*continued absence* of integration-level proof for the cross-tenant
isolation invariant. End users do not see the Phoenix JOIN
timeout — only operator developers running the integration test
locally do.

**If this leaks, the user's data is exposed via:** N/A directly. The
indirect exposure is that a future Realtime regression on the
cross-tenant filter (already protected by RLS + filter + client-side
defensive drop) could ship without integration coverage if this gap
remains unresolved. The three defensive layers are still in place; this
plan adds back the fourth (integration test).

**Brand-survival threshold:** none

This plan does not modify auth, credential handling, payments,
RLS policies, or user-owned data flows. The reproducer harness uses
synthetic `conv-rail-cross-tenant-*@soleur.test` accounts already
allowlisted by the test (line 43-44, `SYNTHETIC_EMAIL_PATTERN`).

The plan's only data-touching path is the existing integration test
itself, which the plan unblocks rather than modifies semantically.

## Hypotheses

The investigation MUST proceed through these layers in order. The
issue body's manual verification already eliminates L3 (firewall, DNS)
and L4 (TLS, WS upgrade) — the failing layer is L7 (Phoenix protocol).
The L3→L7 discipline from `hr-ssh-diagnosis-verify-firewall` is
satisfied by the issue body's curl trace; the plan re-confirms each
layer in Phase 1 to defend against drift.

### L3 — Firewall allow-list

**Verified (issue body):** Operator's egress IP can reach
`api.soleur.ai:443` because the `curl -H 'Upgrade: websocket'` returns
`HTTP 101 Switching Protocols`. No firewall block at the Hetzner
Cloudflare-fronted Realtime endpoint.

Re-verification artifact in Phase 1: paste fresh
`curl -sI -H 'Upgrade: websocket' wss://api.soleur.ai/realtime/v1/websocket`
into the spec.

### L3 — DNS / routing

**Verified (issue body):** Both project hosts resolve. Phase 1
re-verification: `dig +short +time=5 +tries=2 api.soleur.ai` and
`dig +short +time=5 +tries=2 mlwiodleouzwniehynfz.supabase.co`.

### L4 — TLS / WS upgrade

**Verified (issue body):** `HTTP 101` with `sb-project-ref` header
present. Phase 1 re-verification: full upgrade trace with project ref
visible.

### L7 — Phoenix JOIN handshake (failing layer — investigation focus)

The reproducer sends `phx_join` over the established WS but never
receives `phx_reply`. **Deepen-pass 2026-04-29 identified the root
cause as a documented upstream issue.**

#### Confirmed root cause: Node.js `global.WebSocket` race condition

**Source:** [supabase/supabase-js#1559](https://github.com/supabase/supabase-js/issues/1559)
"WebSocket Race Condition in Supabase JS Client - Node.js Only"
(closed 2025-12-15 by upstream maintainer `mandarini`).

**Mechanism (verbatim from upstream issue):** When `global.WebSocket`
is `undefined` (Node.js environments), the Supabase client falls back
to the `ws` module but has a race condition where:
1. WebSocket connects and server responds immediately with `phx_reply`.
2. Client hasn't finished setting up response handlers yet.
3. Response gets lost → `TIMED_OUT` after 10 seconds.

**Environment match:** The upstream issue reported "Node.js Version:
21.1.0 (also tested with 20.x LTS)". Operator's `node --version` on
2026-04-29 returns `v21.7.3` — exact same major. Browsers don't hit
this because `globalThis.WebSocket` is native and the fallback path
is never taken.

**Documented workaround (verbatim from upstream issue):**
```js
const OriginalWebSocket = global.WebSocket || (await import('ws')).default;
class PatchedWebSocket extends OriginalWebSocket {
  constructor(url, protocols, options) { super(url, protocols, options); }
}
global.WebSocket = PatchedWebSocket;
// Now Supabase client works correctly
const supabase = createClient(url, key);
```

The polyfill MUST be registered BEFORE `createClient` is called; the
race lives in the supabase-js fallback constructor, so the reference
captured at client-creation time is what counts.

#### Live version state (collected 2026-04-29)

```text
$ npm ls @supabase/supabase-js @supabase/realtime-js \
    --prefix apps/web-platform
soleur-web-platform@0.0.1
├─┬ @supabase/ssr@0.6.1
│ └── @supabase/supabase-js@2.99.2 deduped
└─┬ @supabase/supabase-js@2.99.2
  └── @supabase/realtime-js@2.99.2

$ npm view @supabase/supabase-js version
2.105.1
```

Installed `2.99.2`; latest `2.105.1`. The fix-relevant changelog
entries between these versions:

- v2.105.1 (2026-04-28) — `realtime: surface real Error on transport-level CHANNEL_ERROR`
- v2.105.0 (2026-04-27) — `realtime: Realtime deferred disconnect`
- v2.100.0 (2026-03-23) — `realtime: use phoenix's js lib inside realtime-js`
- v2.88.0 (2025-12-16) — `realtime: handle websocket race condition in node.js`
- v2.88.0 (2025-12-16) — `realtime: omit authorization header when no access token exists`
- v2.81.0 (2025-11-10) — `realtime: implement V2 serializer`

`v2.88.0` (2025-12-16, one day after #1559 was closed) is plausibly
the fix that resolved #1559 — and the repo IS on `2.99.2` which is
post-v2.88. Two interpretations:
1. The v2.88 fix didn't cover Node 21.7.3 specifically (the original
   issue tested 21.1.0).
2. A regression between v2.88 and v2.99 brought back the race.

Either way, the documented `global.WebSocket` polyfill is robust
against both interpretations because it eliminates the fallback code
path entirely — the supabase-js client uses the polyfilled global
just like a browser would.

#### Reframed hypotheses

**H1 (LEADING — confirmed-mechanism, fix-pending):** Apply the
documented `global.WebSocket` polyfill in the integration test
fixture and the new probe. Expected outcome: probe reaches
`SUBSCRIBED` deterministically across 5 consecutive runs.

**H2 (FALLBACK if H1 fails):** Bump `@supabase/supabase-js` from
`2.99.2` to `2.105.1` — capture v2.100's phoenix-js lib swap and
v2.105's transport-level CHANNEL_ERROR surfacing. Wider blast radius
(touches every supabase-js consumer in the app, not just shell);
keep as fallback rather than primary.

**H3 (TAIL):** If both H1 and H2 fail, the issue is environment-local
(operator ISP middlebox dropping non-browser WS frames, or HTTP/2
negotiation difference). Phase 2.5 broadens to raw WS capture via
`websocat` and falls back to running the integration test from the
deployed prd container.

#### Hypotheses RETIRED by deepen pass

The pre-deepen plan listed `vsn=` mismatch and `apikey`-query-param
shape as live hypotheses. Both are now retired:

- **vsn= mismatch:** The Supabase Realtime broker negotiates V1↔V2
  serializers transparently per the v2.81.0 changelog entry. If this
  were the cause, every supabase-js client below v2.81 would be
  broken globally — they're not. Browsers on 2.99.2 work.
- **apikey query param:** The same `2.99.2` client works in browsers
  with the same URL-construction path. Shell vs browser cannot differ
  on the URL the client builds — it's deterministic from `(url, key)`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-checked
against `apps/web-platform/hooks/use-conversations.ts`,
`apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`,
and `apps/web-platform/lib/supabase/client.ts` returned zero matches.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Reproducer minimal script (`scripts/realtime-probe.mjs` or
      similar) committed under `apps/web-platform/scripts/` so future
      Realtime debugging starts from a known-working baseline. Script
      MUST accept `SUPABASE_URL` + `SUPABASE_ANON_KEY` from env
      (no hardcoded values).
- [ ] **H1 fix (default path)** lands: a `global.WebSocket` polyfill
      registered before `createClient` in (a) the new probe script
      and (b) the integration test fixture file
      `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`.
      Polyfill imports `ws` (already a transitive dep — verify with
      `npm ls ws --prefix apps/web-platform`) and assigns to
      `globalThis.WebSocket` IFF unset. The polyfill MUST NOT
      overwrite a native `WebSocket` (browser/jsdom) — guard with
      `if (typeof globalThis.WebSocket === 'undefined')`.
- [ ] **H2 fallback** (only if H1 polyfill does not resolve TIMED_OUT
      after 5 consecutive probe runs): bump
      `@supabase/supabase-js` from `2.99.2` to `2.105.1` in
      `apps/web-platform/package.json`. Pin the explicit version
      (NOT `@latest`). Regenerate `package-lock.json` AND `bun.lock`
      per `cq-before-pushing-package-json-changes`. Smoke-test
      `/dashboard/chat/*` routes against dev to confirm the bump
      doesn't regress browser-side realtime (the production code path
      that currently works).
- [ ] **H3 fallback** (only if H1 + H2 both fail): file a follow-up
      issue for environment-specific WS capture (`websocat`,
      `mitmproxy`) and add a workaround note to the learning file
      directing future operators to run the integration test from
      the prd deployed container. Do NOT scope the workaround into
      this PR; defer cleanly.
- [ ] `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
      runs to completion against dev (Phase 5b verification) with
      `SUPABASE_DEV_INTEGRATION=1` set. The test must reach
      `SUBSCRIBED` for both userA and userB channels (no
      `TIMED_OUT`).
- [ ] Learning file written under
      `knowledge-base/project/learnings/best-practices/` capturing the
      root cause (link to upstream supabase/supabase-js#1559), the
      diagnostic procedure (Mode A vs Mode B probe), version state
      (installed 2.99.2 at fix time, latest 2.105.1, Node 21.7.3),
      and the fix shape (`global.WebSocket` polyfill in test helper).
      Filename topic: `supabase-phx-join-handshake-shell-environment.md`.
      Date prefix is set at write time (per dated-filename sharp edge),
      not pre-prescribed here.
- [ ] PR body uses `Closes #3052`. PR body uses `Ref #3049` (NOT
      `Closes`) because #3049's acceptance criterion is the verified
      cross-tenant test pass, which is a separate verification step.
- [ ] No regressions in existing Vitest unit tests
      (`apps/web-platform`) — run `bun test` from `apps/web-platform`.

### Post-merge (operator)

- [ ] Re-run the integration test against dev once more from the
      operator's local shell to confirm no environmental drift between
      PR-time and post-merge:
      `doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1
      ./node_modules/.bin/vitest run
      test/conversations-rail-cross-tenant.integration.test.ts`
- [ ] If the integration test passes, close #3049 with a one-line
      verification note: `gh issue close 3049 --comment "Verified
      cross-tenant isolation integration test passes — see #<this
      PR>."`
- [ ] If the integration test still fails post-merge, file a follow-up
      issue with the new diagnostic trace and reopen this thread.

## Network-Outage Deep-Dive

Per AGENTS.md `hr-ssh-diagnosis-verify-firewall` and deepen-plan
Phase 4.5, every layer L3→L7 must show a verification artifact before
service-layer hypotheses. Status as of 2026-04-29:

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | verified (issue body) | `curl ... HTTP 101 Switching Protocols` returned with `sb-project-ref` header |
| L3 DNS / routing | verified (issue body) | DNS resolves for both `api.soleur.ai` and `mlwiodleouzwniehynfz.supabase.co`; Phase 1 re-confirms with `dig +time=5 +tries=2` |
| L4 TLS / WS upgrade | verified (issue body) | `HTTP 101` confirms TLS handshake AND HTTP→WS upgrade succeeded; `sb-project-ref: ifsccnjhymdmidffkzhl` proves Cloudflare is routing to a real Supabase project |
| L7 application (Phoenix JOIN) | **failing layer** — see Hypotheses § Confirmed root cause | `phx_join` sent, `phx_reply` lost in client (Node WS race per supabase/supabase-js#1559) |

The L3-L4 verifications come from the operator's curl trace embedded
in issue #3052. Phase 1 re-runs them with bounded `dig` flags
(`+time=5 +tries=2`) and `curl --max-time 10` per the
plan-network-CLI sharp edge — a fresh re-verification on PR-day
defends against silent infra drift between issue-file time
(2026-04-29 morning) and PR-merge time.

No L3 firewall change, ISP egress IP allowlist update, or DNS rotation
is required — the firewall is verified working at the issue level.

## Test Strategy

### Reproducer-first

Phase 1 lands a minimal `apps/web-platform/scripts/realtime-probe.mjs`
that exhibits the bug. Once the probe reaches `SUBSCRIBED`, the same
fix is exercised by re-running the existing integration test —
no new test surface is added beyond the probe script.

### Two-mode baseline (Phase 1)

The probe runs in two modes to make the fix attributable:

- **Mode A (with polyfill, default):** `globalThis.WebSocket` is set
  to `ws` BEFORE `createClient`. Expected: `SUBSCRIBED` in <2s.
- **Mode B (without polyfill):** comment out the polyfill block and
  re-run. Expected: `TIMED_OUT` after ~10s (reproduces #3052).

Both outputs go into the learning file as the before/after evidence
that this is the documented #1559 race condition, not a new mode of
failure.

### Existing test framework

`vitest` is already installed and configured for `apps/web-platform`
(see `package.json scripts.test`). The integration test file already
exists at
`apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
and is gated by `SUPABASE_DEV_INTEGRATION=1` — no new framework
prescribed.

### Pre-fix baseline

Before any fix, capture the failing probe output (status sequence,
stderr) into `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md`
as the baseline. This makes the fix-effect attributable to the
intervention rather than environment drift.

### Post-fix verification

The post-fix probe MUST reach `SUBSCRIBED` deterministically across 5
consecutive runs. Flake at this layer would indicate H3 (transport
negotiation) is involved and the fix is incomplete.

## Implementation Phases

### Phase 1 — Capture pre-fix baseline + create shared polyfill helper

Files to create:
- `apps/web-platform/scripts/realtime-probe.mjs` (probe script)
- `apps/web-platform/test/helpers/node-websocket-polyfill.ts`
  (shared polyfill — used by probe and integration test)

Files to edit: none.

Steps:
1. Re-confirm version state (already captured during deepen pass; run
   again to defend against drift):
   ```bash
   cd apps/web-platform && npm ls @supabase/supabase-js \
     @supabase/realtime-js ws
   node --version
   ```
   Paste into baseline section of the learning file.
2. Re-confirm L3-L4 with bounded `dig` per
   `cq` plan-CLI-form sharp edge:
   ```bash
   dig +short +time=5 +tries=2 api.soleur.ai
   dig +short +time=5 +tries=2 mlwiodleouzwniehynfz.supabase.co
   curl --max-time 10 -sI -H 'Upgrade: websocket' \
     -H 'Connection: Upgrade' -H 'Sec-WebSocket-Version: 13' \
     -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
     "wss://api.soleur.ai/realtime/v1/websocket?apikey=$KEY&vsn=1.0.0"
   ```
3. Create the shared polyfill helper:
   ```ts
   // apps/web-platform/test/helpers/node-websocket-polyfill.ts
   //
   // Workaround for supabase/supabase-js#1559 — Node.js race condition
   // where the ws-fallback constructor loses phx_reply before handlers
   // attach. Polyfill globalThis.WebSocket BEFORE createClient() so the
   // supabase-js client uses the polyfilled global instead of the
   // racy fallback. No-op when WebSocket is already defined (browsers,
   // jsdom). Idempotent — safe to call from multiple test files.
   import WS from "ws";

   export function ensureNodeWebSocketPolyfill(): void {
     if (typeof globalThis.WebSocket === "undefined") {
       // The race lives in the ws fallback constructor's handler-
       // attach order. Setting globalThis.WebSocket eliminates the
       // fallback path entirely — supabase-js uses globalThis.WebSocket
       // directly, mirroring the browser code path that already works.
       (globalThis as { WebSocket: typeof WS }).WebSocket =
         WS as unknown as typeof globalThis.WebSocket;
     }
   }
   ```
   Note: `ws` is already a transitive dep via supabase-js — verify
   with `npm ls ws --prefix apps/web-platform` before importing.
4. Write the probe script:
   ```js
   // apps/web-platform/scripts/realtime-probe.mjs
   //
   // Standalone reproducer for issue #3052. Always installs the
   // node-websocket-polyfill BEFORE createClient — this is the H1
   // documented fix for supabase/supabase-js#1559.

   import WS from "ws";
   if (typeof globalThis.WebSocket === "undefined") {
     globalThis.WebSocket = WS;
   }
   const { createClient } = await import("@supabase/supabase-js");

   const url =
     process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
   const key =
     process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
     process.env.SUPABASE_ANON_KEY;
   if (!url || !key) {
     console.error(
       "Set SUPABASE_URL + SUPABASE_ANON_KEY (or NEXT_PUBLIC_ variants).",
     );
     process.exit(2);
   }
   const c = createClient(url, key);
   const ch = c.channel("probe-" + Date.now());
   const t0 = Date.now();
   ch.subscribe((status, err) => {
     console.log(`[probe ${Date.now() - t0}ms]`, status, err ?? "");
     if (status === "SUBSCRIBED" || status === "CLOSED") {
       c.removeAllChannels().then(() =>
         process.exit(status === "SUBSCRIBED" ? 0 : 1),
       );
     }
   });
   setTimeout(() => {
     console.error("[probe] hard timeout after 30s");
     process.exit(3);
   }, 30_000);
   ```
   The probe MUST read URL/key from env only (per Risk #4).
5. Run two-mode baseline so the fix-effect is attributable:
   ```bash
   # Mode A: with polyfill (default — should SUBSCRIBE)
   doppler run -p soleur -c dev -- node ./scripts/realtime-probe.mjs

   # Mode B: without polyfill (reproduces TIMED_OUT — comment out the
   # if-block at the top to confirm baseline)
   ```
   Paste both outputs into the learning file. Mode B reproduction is
   the contract that this is the same bug; Mode A success is the fix.

Exit gate: Mode A reaches `SUBSCRIBED` within 2s; Mode B reproduces
`TIMED_OUT` after ~10s. If Mode A also TIMED_OUT, jump to Phase 2.

### Phase 2 — Wire polyfill into integration test fixture (H1)

Files to edit:
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
  — import the polyfill helper, call it in `beforeAll` BEFORE the two
  `createClient` calls.

Steps:
1. Add at the top of the test file (after the existing imports):
   ```ts
   import { ensureNodeWebSocketPolyfill } from
     "./helpers/node-websocket-polyfill";
   ```
2. Inside the existing `beforeAll` (the one that runs the supabase
   service-role admin login), call `ensureNodeWebSocketPolyfill()` as
   the FIRST statement — before any `createClient` invocation. The
   polyfill is idempotent so calling it from a single beforeAll is
   sufficient even if vitest runs the file multiple times under
   `--runInBand`.
3. Run the integration test:
   ```bash
   doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 \
     ./node_modules/.bin/vitest run \
     test/conversations-rail-cross-tenant.integration.test.ts
   ```
4. Both userA and userB channels must reach `SUBSCRIBED`. The
   isolation assertions then run on the same path the production
   browser uses.

Exit gate: integration test passes against dev with assertions green.

### Phase 2.5 — H2 fallback (ONLY if Phase 2 still TIMED_OUT)

Files to edit (only on this branch):
- `apps/web-platform/package.json` — bump `@supabase/supabase-js`
  from `^2.49.0` to `^2.105.0` (pinned to the deepen-time latest
  minor). Do NOT use `@latest`.
- `apps/web-platform/package-lock.json` — regenerate.
- `apps/web-platform/bun.lock` — regenerate.

Steps (only if H1 polyfill alone is insufficient):
1. Read the supabase-js CHANGELOG for v2.99.2 → v2.105.1 carefully —
   six minor versions of churn including v2.100's phoenix-js lib swap
   may have breaking changes.
2. `cd apps/web-platform && npm install @supabase/supabase-js@2.105.1
   --save-exact` (then unpin to `^2.105.0` in package.json after
   confirming).
3. `bun install` to regenerate `bun.lock`.
4. `bun test` — confirm no unit-test regressions.
5. Smoke-test `/dashboard/chat/*` against dev (Playwright MCP)
   — confirm browser-side realtime still works.
6. Re-run the integration test from Phase 2.

Exit gate: integration test passes AND no browser regression.

### Phase 2.6 — H3 fallback (ONLY if Phase 2.5 still TIMED_OUT)

Steps (defer to follow-up issue):
1. File a follow-up GitHub issue with full WS frame capture from
   `websocat` and `mitmproxy` showing the divergence between Node and
   browser frames.
2. Add a workaround note to the learning file: "Run the integration
   test from inside the deployed prd container (`docker exec` into
   the web-platform container with `SUPABASE_DEV_INTEGRATION=1`) until
   the underlying issue is resolved upstream."
3. Do NOT widen this PR with the workaround — defer cleanly.

Exit gate: follow-up issue filed; this PR ships with whatever H1+H2
achieved (probe + polyfill + version bump) so future regressions
surface earlier.

### Phase 3 — Write learning + finalize

Files to create:
`knowledge-base/project/learnings/best-practices/<date>-supabase-phx-join-handshake-shell-environment.md`

Files to edit: none.

Steps:
1. Write the learning file with: symptoms, baseline trace (Mode A +
   Mode B from Phase 1), upstream issue link (#1559), version state
   captured 2026-04-29, root cause (Node WS race), fix shape
   (polyfill in test helper), why this only affects shell not browser,
   and re-runnable probe instructions. Date the filename at write
   time, NOT plan time, per the dated-filename sharp edge.
2. `bun test` from `apps/web-platform` — final regression sweep.
3. Re-run the probe 5× consecutively to confirm determinism.

Exit gate: integration test green, learning file present, probe
script committed.

### Phase 4 — Verify integration test, write learning, prepare PR

Files to create:
`knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md`.

Files to edit: none (PR body composition is a /ship-time concern).

Steps:
1. `doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1
   ./node_modules/.bin/vitest run
   test/conversations-rail-cross-tenant.integration.test.ts`. Confirm
   userA + userB both reach SUBSCRIBED and isolation assertions pass.
2. Write the learning file with: symptoms, baseline trace, hypothesis
   tree, root cause, fix shape, and a re-runnable probe section. The
   filename uses today's date (`2026-04-29`) — but per
   `cq` sharp edge on date-pinning, do not over-prescribe future
   filenames.
3. Confirm probe script committed under
   `apps/web-platform/scripts/realtime-probe.mjs` so the next
   debugging session starts hot.

Exit gate: integration test green, learning file present, probe
script committed.

## Risks

1. **The polyfill may not actually resolve TIMED_OUT on Node 21.7.3.**
   Issue #1559 was closed 2025-12-15 against Node 21.1.0; the
   underlying race could still surface in 21.7.3 if the `ws` module's
   `onopen` timing changed in a Node minor. Mitigation: Phase 2 has a
   deterministic exit gate (5 consecutive `SUBSCRIBED` runs); if it
   fails, Phase 2.5 (version bump) is queued and the plan does not
   ship a partial fix.

2. **The version bump (H2 fallback) may carry breaking changes.**
   v2.99.2 → v2.105.1 spans v2.100's "use phoenix's js lib inside
   realtime-js" — a structural realtime refactor. Browser-side
   realtime currently works; a regression there would be a
   user-facing outage on `/dashboard/chat/*`. Mitigation: H2 only
   fires if H1 fails. Pre-merge: read CHANGELOG diff for every minor
   skipped, run `bun test`, smoke-test `/dashboard/chat/*` via
   Playwright MCP. Per `cq-before-pushing-package-json-changes`, both
   `bun.lock` and `package-lock.json` regenerated atomically.

3. **Bun and npm lockfile drift.** Per
   `cq-before-pushing-package-json-changes`, both lockfiles must be
   regenerated atomically. Skipping one ships a different version to
   prd via the Dockerfile (`npm ci`) than the developer tested.
   Mitigation: only relevant if H2 fires; CI's lockfile-drift check is
   the second line of defense.

4. **Probe script env hardening.** If the probe accepts URL/key from
   CLI args (not env), an operator might paste prd anon-key into
   shell history. Mitigation: probe reads from env only, does NOT log
   the key, exits non-zero if env is missing. Skeleton in Phase 1
   already satisfies this.

5. **Polyfill leaks into production code paths.** The polyfill helper
   lives in `apps/web-platform/test/helpers/`. It MUST NOT be imported
   from `lib/`, `app/`, `server/`, or any non-test code. A test-only
   import of `ws` doesn't ship to the prd Docker image because Next.js
   tree-shakes test files; verify with
   `grep -r "node-websocket-polyfill" apps/web-platform/{lib,app,server}
   2>/dev/null` (must return nothing) and confirm `ws` stays in
   `dependencies` (it's already pulled by supabase-js, not a new dep).

6. **CI follow-up: regression detection.** A future supabase-js bump
   inside the H1 polyfill range might silently re-trigger the race.
   Mitigation: file a post-merge follow-through issue to add a
   nightly integration-test cron (NOT in this PR — keep scope tight)
   so regressions surface within hours.

7. **The integration test's `beforeAll` may run before the polyfill
   import resolves.** Vitest hoists `vi.mock` but not regular
   imports. Mitigation: the polyfill is called from `beforeAll`, not
   at module top level — so `import { ensureNodeWebSocketPolyfill }`
   resolves before any `createClient` is called. Verify by re-reading
   the test file structure; if any `createClient` lives at module
   scope, hoist it into the `beforeAll` along with the polyfill call.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled above.
- Bumping `@supabase/supabase-js` MUST use an explicit pinned range
  (e.g., `^2.X.0`), NOT `@latest` — `@latest` resolves globally and
  may cross major version boundaries.
- The probe script MUST `removeAllChannels()` and exit cleanly per
  `2026-04-29-supabase-removeallchannels-api-shape.md` — one Promise,
  not an array of Promises. The skeleton above does this correctly.
- Do not prescribe an exact dated learning filename in `tasks.md`; let
  the work-time author pick the date. Filename in this plan is a
  suggested convention, not a hard contract.
- The integration test exists already and is the post-fix
  verification — do NOT modify the test's assertions to make it pass.
  If the test fails for reasons other than the JOIN timeout, file a
  separate issue.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is an investigation-then-fix bug for an internal debugging
workflow. No user-facing surface, no marketing/product/legal
implications. CMO/CPO/CLO/COO/CIO/CSO are not relevant — no content,
no revenue, no policy, no expense, no infra provisioning, no
new external attack surface.

The CTO domain leader's relevance is at the architectural-decision
level (e.g., should this prompt a broader supabase-js version pin
strategy? Should we add a Realtime smoke test to CI?). These are
captured as Risk #5 follow-throughs rather than blocking the PR.

### Engineering (CTO)

**Status:** carried-forward (no fresh leader spawn — this is a
narrow debugging task; full domain leader fan-out would be ceremony).

**Assessment:** The fix shape is bounded by the four hypotheses; each
ends in a 1-3 file change. No architectural decision is gated by this
PR. Risk #5 (CI smoke test for Realtime regression detection) is a
deliberate post-merge follow-through to avoid widening this PR.

## Files to Edit

**Default (H1 polyfill) path:**
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
  — add polyfill import + `ensureNodeWebSocketPolyfill()` call in
  `beforeAll`.

**H2 fallback path (ONLY if Phase 2 fails):**
- `apps/web-platform/package.json` — bump supabase-js to `^2.105.0`.
- `apps/web-platform/package-lock.json` — regenerate
  (`cq-before-pushing-package-json-changes`).
- `apps/web-platform/bun.lock` — regenerate
  (`cq-before-pushing-package-json-changes`).

**Not in scope:** `apps/web-platform/lib/supabase/client.ts`.
Production browser flow is not affected; the fix is contained to
shell/Node test paths via the polyfill helper.

## Files to Create

- `apps/web-platform/test/helpers/node-websocket-polyfill.ts`
  (always — shared polyfill consumed by both probe and integration
  test).
- `apps/web-platform/scripts/realtime-probe.mjs` (always — captures
  baseline + post-fix verification, doubles as future-debugging
  artifact).
- `knowledge-base/project/learnings/best-practices/<date>-supabase-phx-join-handshake-shell-environment.md`
  (always — captures root cause, upstream link, fix, and
  re-runnable probe instructions; date inserted at write time).

## Out of Scope

- Adding a CI smoke test for Realtime JOIN (filed as post-merge
  follow-through; tracked separately to avoid widening this PR).
- Changes to `use-conversations.ts` (the production hook is not
  failing — only the shell environment is).
- Migration changes (Migration 034 already lands publication
  membership; nothing else needed at the DB layer).
- Any test framework swap. Vitest stays.

## Why this matters

The cross-tenant Realtime isolation test is the load-bearing
integration assertion behind the Command Center conversation rail.
Currently it is unrunnable from the only environment where it can be
exercised against a real Supabase broker (operator workstation).
Closing this gap restores the ability to validate every future
Realtime change against a real broker before merge — defense in depth
on top of the unit-test layer 3 client-side drop and code-review
sign-off.

## Acceptance Criteria — Issue Linkage

- `Closes #3052` (this issue — the JOIN timeout bug).
- `Ref #3049` (#3049's verification step is post-merge; do NOT use
  `Closes`).

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-04-29-fix-supabase-realtime-phx-join-timeout-from-shell-plan.md.
Branch: feat-one-shot-3052-supabase-realtime-join-timeout.
Worktree: .worktrees/feat-one-shot-3052-supabase-realtime-join-timeout/.
Issue: #3052. PR: not yet opened. Plan reviewed, implementation next.
```
