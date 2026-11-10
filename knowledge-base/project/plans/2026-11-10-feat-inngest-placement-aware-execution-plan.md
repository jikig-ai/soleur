---
title: "feat: placement-aware Inngest execution — fnId-keyed host affinity for host-affine/volume-bound functions (#9137)"
date: 2026-11-10
slug: feat-inngest-placement-aware-execution
branch: feat-one-shot-9137-placement-aware-execution
issue: 9137
closes: 9137
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: placement-aware Inngest execution — fnId-keyed host affinity (#9137)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for
this branch.

## Overview

web-2 has served LB weight 1 since the 2026-11-08 serve flip (#12167, commit `72534a818e`),
so `https://app.soleur.ai/api/inngest` step calls now fan out randomly to web-1 and web-2
(`apps/web-platform/infra/cloudflare-lb.tf` — `origin_steering { policy = "random" }`,
`var.web2_lb_weight` default 1). Every `host-affine` and `volume-bound` function in
`apps/web-platform/server/inngest/execution-placement.ts` can therefore execute on the wrong
host **today** — the exposure the issue anticipated at "the ADR-143 Phase-3 flip" is live now,
not prospective.

This plan makes execution placement-aware **at the app layer** (CTO ruling, 2026-11-10,
`knowledge-base/project/specs/feat-one-shot-9137-placement-aware-execution/decision-challenges.md`):

- A forwarder in front of `serve()` in `app/api/inngest/route.ts` reads the step call's `?fnId`
  query key — the routing key the SDK itself requires
  (`node_modules/inngest/components/InngestCommHandler.js`: `queryKeys.FnId = "fnId"`; "No
  function ID found in async request" at ~L902) — looks it up in `EXECUTION_PLACEMENT`, and
  decides per class.
- `portable` executes wherever the call lands (web-1 or web-2 — the issue's actual goal:
  losing web-1 no longer drops portable work).
- `host-affine`, `volume-bound`, unknown and unclassifiable
  calls are forwarded **verbatim** — raw body, all signature headers, full query — to the
  exec host over pinned TLS, and the response is streamed back.
- Fail-closed everywhere: a host that cannot establish it is the exec host **refuses** the
  step call (never executes a pinned fn locally as a fallback), and a marked (already
  forwarded) call arriving at a non-exec host is refused, never re-forwarded.

One app id (`soleur-runtime`), one registered serve URL, zero function-id migration, zero
Terraform/DNS/LB changes. `EXPECTED_CRON_FUNCTIONS`, Sentry monitor slugs, the watchdog and
deploy-verify are untouched because no function identity moves.

## Research Insights

### Premise Validation (Phase 0.6)

- **#9137** OPEN; epic **#10390** OPEN (Bucket 2, listed next-actionable); **#7230** CLOSED by
  PR #9134; **#6178** CLOSED (merged 2026-11-08); **#12167** OPEN (its serve arm is done; the
  residual readyz-probe issue remains).
- Artifacts verified on `origin/main`: `server/inngest/execution-placement.ts` (manifest),
  `app/api/inngest/route.ts` (single `serve()` + hardcoded `SERVE_HOST`), `server/inngest/client.ts`
  (`id: "soleur-runtime"`, `checkpointing: false`), `server/inngest/cron-manifest.ts`
  (`EXPECTED_CRON_FUNCTIONS` — bare fn ids), `infra/inngest-host.tf` (`sdk_url =
  "http://10.0.1.10:3000/api/inngest"`, L395), `infra/cloudflare-lb.tf`, `infra/dns.tf`,
  ADR-033/068/078/100/119/143/243/248/294/323.
- **STALE PREMISE 1 (load-bearing):** the issue's "once web-2 gets serving weight" is already
  true — `cloudflare_load_balancer.app` fronts `app.soleur.ai` and serves both web hosts at
  weight 1 since 2026-11-08 (PR #12414 body: "Live web-2 has served at pool weight 1 since the
  2026-11-08 serve flip"). Step calls fan out **now**: ~50% of `host-affine` and `volume-bound`
  calls already execute on web-2, where the ADR-119 sole-copy LUKS volume is absent and
  `spawnClaudeEval`'s process-local single-flight (ADR-243 §2) does not join.
- **STALE PREMISE 2:** `dns.tf`'s "Single step-executing host is load-bearing" comment remains
  true of the A record, but the LB overlays the hostname — `cloudflare_record.app` is the
  disabled-LB fallback only (`cloudflare-lb.tf` L167). `lb-weight-gate.test.sh` C.1a still
  pins the A record to web-1 and does NOT see the LB fan-out.
- **Mechanism vs ADR corpus:** no ADR rejected in-app fnId-keyed routing; the prior plan
  (`plans/archive/20260928-134830-2026-09-28-feat-inngest-execution-host-placement-rule-plan.md`)
  named exactly the two sanctioned shapes — "per-class app ids, or an ingress layer that
  routes a step request by its function id". Option C implements the second shape in the app
  layer. ADR-243 §2 explicitly anticipates it ("host affinity for `/api/inngest`").
- **Collision precheck** (`collision-precheck.sh 9137`): PR #12554 is this branch's own
  auto-created draft — no foreign duplicate.
- **Cited consumer assumptions verified:** `soleur-runtime-<fnId>` app-scoped slugs appear in
  `ci-deploy.test.sh` (~L1440 registry-verify fixture), `cron-inngest-cron-watchdog.test.ts`
  (~L37), `agent-on-spawn-lifecycle.test.ts` (~L234) — all would break under a second app id;
  none under Option C.

### Property List (Phase 0.6b)

- **P1:** Every `host-affine` and `volume-bound` step call executes only on the exec host
  (web-1, the LUKS volume holder) — ADR-243 §2 single-flight and ADR-119 residency restored.
- **P2:** Every `portable` step call executes on whichever web host received it.
- **P3:** The routing decision consumes `EXECUTION_PLACEMENT` as the single classification
  authority; a function absent from the manifest fails closed to the exec host, never to a
  wrong host.
- **P4:** No function identity, registration, monitor or manifest churn — zero migration.
- **P5:** The web-2→web-1 hop is authenticated and encrypted (pinned TLS) and loop-free
  (marker honored only on the private-TLS ingress; marked calls never re-forward).
- **P6:** Placement decisions are observable — structured per-call logs, refuse/forward
  counters, a local discoverability probe.

### Cut List (Phase 0.6b)

- **Per-class app ids** (two clients, two serve URLs) → P1/P2 but pays ~33-37 function-id
  migrations, a second registration path, and consumer prefix churn — and STILL needs a
  host-pinned serve URL. Rejected (CTO T1).
- **Edge fnId steering** (CF LB rules / Worker matching `http.request.uri.query`) → P1/P2 via
  a generated second copy of the pinned set that drifts against the manifest; a new unlisted
  function silently misplaces. Rejected (CTO T1).
- **New `INNGEST_EXEC_ORIGIN` Doppler/env value** → #5182 forbids env-derived pins; the pin is
  a hardcoded constant (CTO T2).
- **New `SOLEUR_HOST_PRIVATE_IP` is kept; reuse of `SOLEUR_PROXY_BIND` is cut** → the
  container receives the literal `0.0.0.0` (ci-deploy.sh:5798); it cannot identify the host
  (CTO T2 re-ruled after the first ruling's premise was corrected).
- **`SOLEUR_HOST_ID` as exec identity** → instance-id changes on every web-host replace;
  pinned fns would stall until a manual constant edit (CTO T2).
- **Always-forward + marker (no self-id)** → fails when the private publish degrades to
  loopback (`RELAY_PUBLISH_BIND` fallback): web-1 could not reach its own listener at
  10.0.1.10 (CTO T2).
- **Plaintext private hop** → forwarded calls carry user payloads (agent-on-spawn); ADR-294's
  direction for private Inngest links is already TLS (CTO T3).
- **Fallback (a) — second SDK worker on the Inngest host** → no trigger today: the ADR-248
  clock runs on both web hosts, GHA `schedule:` covers the rest (CTO T4).
- **Terraform/DNS/LB work** → none needed under Option C; the only infra/** edit is one
  `-e` line in `ci-deploy.sh` (normal infra-config push path).

### Inngest SDK facts (verified against installed `inngest` v4)

- Step-execution POSTs require `?fnId=<absolute-id>`; `this.fns` is keyed by app-scoped ids
  `<appId>-<fnId>` and `<appId>-<fnId>-failure` (onFailure handlers inherit the parent's
  client and class).
- `?probe=` (signature probes) and `forceExecution` POSTs carry no fnId; registration
  GET/PUT carries no fnId.
- The forwarder must therefore classify ONLY step calls and let probe/registration traffic
  through untouched on any host.

### Institutional learnings applied

- `2026-09-23-cloudflare-524-made-every-long-inngest-step-run-twice-and-commit-nothing.md`:
  long steps must stream; the forward passes the streamed 201+heartbeat response through
  without buffering (the private hop has no CF timeout anyway).
- `2026-09-27-the-recovery-procedure-i-wrote-to-stop-a-double-fire-could-cause-one.md`:
  missed ticks are drained exactly once on scheduler resume (ADR-100 addendum) — a
  fail-closed refusal stalls ticks visibly rather than losing them silently; no double-fire.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-…`: every guard below ships a
  mutation matrix including own-dispatch rows.
- `2026-05-31-inngest-v1-loopback-gated-…`: `/v1/*` introspection is loopback-gated on the
  Inngest host — observability must come from the app-side logs/Sentry, not server queries.
- `2026-07-28-a-ten-run-sample-said-unreachable-…`: a ~2% failure rate hides in small
  samples — the fan-out exposure is verified structurally (LB config + commit), not sampled.

### Functional overlap (Phase 1.5b)

`server/session-proxy.ts` is a wss host↔host relay for WS sessions only — it does NOT cover
HTTP API requests (verified: no `api/inngest` reference). `server/proxy-tls.ts` provides the
reusable pinned-TLS material this plan reuses (T3). No existing mechanism routes Inngest
step calls by function. Community discovery skipped — internal topology problem, prior plan
recorded no coverage (carried forward).

### External research decision (Phase 1.6)

Skipped — the decision turns on this repo's topology and the installed SDK, both verified
directly.

### CTO rulings (all four, 2026-11-10 — full text in decision-challenges.md)

- **T1:** Option C — app-layer fnId-aware forwarder; one app id, one serve URL, fail-closed.
- **T2 (re-ruled):** new per-host `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` (prod container;
  empty for canary) compared to a hardcoded `10.0.1.10` pin constant drift-guarded to
  `inngest-host.tf` `sdk_url` and `network.tf`/`variables.tf`; unset/empty → refuse; marked
  call at a non-exec host → refuse. Dissent: a web-1 reboot racing the hot-attached NIC can
  deploy with an empty value → emit a distinct `placement.exec_identity_missing` error plus a
  no-SSH recovery step.
- **T3:** pinned TLS reusing `PROXY_TLS_KEY`/`PROXY_TLS_CERT` (`loadProxyTlsClientCa`,
  `rejectUnauthorized: true` — never false); receiver is a sibling listener, same
  material + private bind (tightened at plan review — the :8443 wss server's 10 s hello
  deadline would kill streamed HTTP steps). Verified post-ruling: `proxy-tls.ts` states
  the cert carries SANs over every web host's private IP, so the default IP hostname
  check passes — no `checkServerIdentity` override.
- **T4:** primary target only; fallback (a) stays deferred (Non-Goals restates its triggers).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #9137 / ADR text) | Reality on origin/main | Plan response |
|---|---|---|
| "Once web-2 gets serving weight" (re-evaluation criterion 1) | web-2 has served weight 1 since 2026-11-08; step calls fan out NOW | Plan treats the exposure as live; the fix is the only close; interim drain option is an operator row (T4a), not a plan dependency |
| `dns.tf` "Single step-executing host is load-bearing" | True of the A record only; the LB overrides routing for the hostname | Correct the comment's scope in the ADR amendment trail; `lb-weight-gate.test.sh` C.1a's check is recorded as covering the fallback record, not the LB |
| `SOLEUR_PROXY_BIND` carries the per-host private IP (first CTO T2) | Container receives literal `0.0.0.0` (ci-deploy.sh:5798); host IP is resolved host-side only (`resolve_proxy_bind` → `PROXY_BIND`) | Re-ruled T2: inject `SOLEUR_HOST_PRIVATE_IP` per host |
| Placement classes are "DECLARED and reviewed, not guarded, until the placement-aware registry of #9137 consumes it" (execution-placement.ts header) | This plan IS #9137 — the manifest becomes load-bearing at request time | The host-affine/volume-bound split's correctness becomes enforceable; Guard contract binds route decisions to the manifest |
| #5159: server never plans crons for `127.0.0.1`-registered URLs | Registered serve URL is unchanged (`https://app.soleur.ai`) — no private-URL registration needed under Option C | The spike the issue prescribed for private serve URLs is unnecessary — nothing registers privately |

## Problem Statement

Since 2026-11-08 the Cloudflare LB on `app.soleur.ai` steers randomly between web-1 and
web-2. The Inngest server calls every step at `https://app.soleur.ai/api/inngest`, so:

1. ~half of `volume-bound` calls (`agent-on-spawn-requested` — the founder-facing BYOK
   leader loop; `workspace-reconcile-on-push`; `cron-workspace-sync-health`;
   `cron-workspace-gc`; `cron-agent-spawn-stale-settle`; `cfo-on-payment-failed`;
   `github-on-event`) execute on web-2 against its empty scratch `/workspaces`.
2. ~half of `host-affine` calls (18 `spawnClaudeEval` spawners + ephemeral-clone/lease
   functions) execute on web-2 where the process-local single-flight map cannot join — a
   retried step can start a **second paid Claude session** beside the first, re-opening the
   ADR-243 §2 defect the streaming fix did not cover. Ephemeral clones also land on web-2's
   `/workspaces` where `cron-workspace-gc`'s co-location rule no longer holds.
3. Nothing in the code or CI prevents or detects this — the placement classes were
   explicitly "DECLARED and reviewed, not guarded, until the placement-aware registry of
   #9137 consumes it" (`execution-placement.ts` header). This plan is that consumer.

## Proposed Solution

### The exec-placement forwarder

A new client-free-adjacent module `server/inngest/exec-placement.ts` (imports the manifest
leaf, `proxy-tls.ts` and `host-identity`-style env reads; NOT client-free — it may import
`server/` modules but nothing that throws at module load outside prod) exposes:

```ts
// server/inngest/exec-placement.ts (shape, not code)
const EXEC_HOST_PRIVATE_IP = "10.0.1.10";           // pin constant — drift-guarded (Guard D)
const EXEC_FORWARD_HEADER = "x-soleur-exec-forward"; // loop-guard marker

type PlacementDecision =
  | { action: "execute" }                            // portable anywhere; pinned on exec host
  | { action: "forward"; target: string }            // pinned on a non-exec host
  | { action: "refuse"; reason: string };            // fail-closed

function classifyFnId(rawFnId: string | null): string | null  // strip "soleur-runtime-" and "-failure"; null → fail-closed class
function decidePlacement(fn: { fnId, isExecHost, marked, method, isStepCall }): PlacementDecision
async function forwardStepCall(req: Request, target: string, ca: string): Promise<Response>
```

Decision table (evaluated in `app/api/inngest/route.ts` around the SDK `POST` handler; GET,
PUT and `?probe=` requests bypass the forwarder entirely):

| Condition | Decision |
|---|---|
| Not a step call (GET/PUT/`?probe=`) | `execute` locally — unchanged semantics on any host |
| Class `portable` | `execute` locally |
| Class `host-affine`/`volume-bound`, host IS exec (`SOLEUR_HOST_PRIVATE_IP === "10.0.1.10"`) | `execute` locally |
| Same, host NOT exec | `forward` to `https://10.0.1.10:8445/api/inngest` with `EXEC_FORWARD_HEADER` set, raw body + all headers + query preserved, streamed response |
| Same, marked `EXEC_FORWARD_HEADER`, host NOT exec | `refuse` — loop-guard, never re-forward |
| `SOLEUR_HOST_PRIVATE_IP` unset/empty | `refuse` — HTTP 503 (retriable, NEVER a `NonRetriable` shape: a late-NIC deploy must stall ticks, not kill runs) with the distinct `placement.exec_identity_missing` error |
| fnId absent-but-step-shaped, or unknown after prefix/suffix strip | treated as pinned (fail-closed direction) |

- **Marked requests are only honored on the private-TLS ingress.** The receiver on the
  exec host terminates the pinned-TLS connection and forwards internally to the app's own
  `serve()` handler (a loopback hop to `127.0.0.1:3000` with the marker preserved is the
  simplest honest implementation — the marker is only trusted because it arrived on the
  private listener; a forged marker on the public path fails signature or is ignored by the
  non-exec refusal rule).
- **Signature gate before forwarding:** the non-exec host forwards only calls carrying an
  `x-inngest-signature` header (missing → refuse; a rate-limited warn row logs the attempt)
  and otherwise forwards raw bytes without verifying; only the exec host's `serve()`
  performs the HMAC check. Without this, any public caller could POST `?fnId=<pinned>` and
  reach web-1's private listener through web-2 — a surface that today admits only peers
  (plan-review P5). A forged-but-present signature still cannot execute — the exec host
  verifies.
- **Receiver: a sibling `https.createServer` on dedicated port 8445** using
  `loadProxyTlsServerOptions()` material, bound to the private IP, reusing the relay's
  peer admission (`isAllowedProxyPeer` / `SOLEUR_PROXY_PEER_ALLOWLIST`), published like
  :8443 in ci-deploy.sh. It invokes the app's own `/api/inngest` handler **in-process**
  (the `origin-tls.ts` pattern — a transport sharing every handler, never a second app).
  The existing :8443 wss server is NOT the receiver: its `HELLO_DEADLINE_MS` (10 s)
  destroys any socket that has not completed a WebSocket hello — an HTTP step call that
  streams for minutes would be killed mid-run (plan-review P1). If the listener's publish
  is loopback-degraded (`net.ipv4.ip_nonlocal_bind` fallback), forwarding fails closed →
  visible pinned-fn stall, which T3 accepted as the dependency.
- **Dial:** reuse `loadProxyTlsClientCa()` + the session-proxy dial shape
  (`{ ca, rejectUnauthorized: true }`) on an `https`/undici agent; if Node's default
  hostname check rejects the IP dial (cert SAN question flagged UNVERIFIED in T3), use the
  SAME identity-check mechanism the session relay's wss dial uses — never
  `rejectUnauthorized: false` and never a new verification scheme.
- **`onFailure` (`-failure`) ids** inherit the parent's class — strip the SDK's
  `-failure` suffix before the manifest lookup, matching `execution-placement.ts`'s own
  header ("inherits its parent's class; it has no row").

### Exec-host identification (T2)

- `ci-deploy.sh` injects `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` into the prod container
  beside the existing `-e SOLEUR_HOST_ID` (~L5797); the canary gets `-e
  SOLEUR_HOST_PRIVATE_IP=` (empty → any pinned call refuses, which is correct — the canary
  serves no step traffic).
- `PROXY_BIND` is already resolved per host by `resolve_proxy_bind()` (ci-deploy.sh:338)
  from the `10.0.1.x` NIC — the IP and the pin share one Terraform source
  (`variables.tf` `web_hosts` map `private_ip`, `network.tf`,
  `hcloud_server_network.web["web-1"]` = 10.0.1.10), so both survive a `web-host-replace`.
- `infra/lib/docker-run-tuple.py` + `docker-run-tuple.test.sh` pin the docker-run tuple —
  the new `-e` line must be added there and to its test, or the tuple guard rots.

### Optional unpin (in-scope small refactor — gated)

`cfo-on-payment-failed` and `github-on-event` are volume-bound only because they reach
`server/workspace-resolver.ts` through `byok-resolver.ts`'s `resolveCurrentWorkspaceId`
(a Supabase lookup, no filesystem — per the manifest `reason` fields). Moving that helper
to a filesystem-free module flips both to `portable` per Guard 2 — two fewer functions
pinned. **In scope as an optional Phase 4** because the manifest itself names #9137 as the
unpin point; implementer may defer it if the helper move has wider blast radius than the
plan-time read suggests.

## Architecture Decision (ADR/C4)

### ADR

Amend, do not create; no new ordinal. Cite full filenames (ADR-033 has same-number siblings).

1. `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
   — append `## Amendment — 2026-11-10 (#9137): placement-aware execution via the fnId-keyed
   forwarder`, in the existing amendment shape. Carries: the mechanism decision (Option C and
   the rejected A/B), the decision table, the exec-host identification rule
   (`SOLEUR_HOST_PRIVATE_IP` vs hardcoded `10.0.1.10`), the pinned-TLS transport, the
   marker/loop rule, the fail-closed refusal semantics, the statement that the
   `host-affine`/`volume-bound` split is now enforced at request time by
   `EXECUTION_PLACEMENT` + `test/server/inngest/exec-placement-forward.test.ts`, the web-1
   SPOF residual (CTO dissent — already true via the ADR-119 volume), and the fallback-(a)
   re-evaluation triggers carried verbatim from #9137.
2. `knowledge-base/engineering/architecture/decisions/ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md`
   — reversal trigger 1 ("Inngest function execution is decoupled from web-1 (#9137)")
   **fires** with this PR. Append a dated note: the trigger fired; re-derived, the clock's
   rationale is unchanged because it is a per-web-host in-process dispatch (both hosts),
   not Inngest-executed work — placement of Inngest functions does not move it.
3. `knowledge-base/engineering/architecture/decisions/ADR-243-inngest-steps-cross-the-cloudflare-proxy-and-must-stream.md`
   — append a §2 addendum: the "one web host executes steps" premise is restored by the
   forwarder — pinned-class calls execute only on the exec host regardless of which origin
   the LB selects; the process-local single-flight remains sound.
4. `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`
   — append a dated line to `## Amendment — 2026-09-23 (#8611, ADR-243)` noting the #9137
   placement mechanism landed (the addendum's "Phase-3 flip must honour the placement
   classes" is now satisfied).
5. `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`
   — one-line `## Updates / amendment log` entry pointing at the ADR-033 amendment.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`).

- **Actors/systems checked:** `inngest` (dedicated host), `api` (app container — the
  forwarder lives inside it), `hetzner` (web hosts — the private-net hop is between two
  instances of the same element), `cloudflare` (the LB — already modeled as the
  app.soleur.ai front). No new element, actor or store.
- **Relationships changed:** the `inngest -> api` "Invokes function steps at the registered
  serve URL" edge prose gains: steps route by placement class — `portable` executes on
  whichever web host answers; `host-affine`/`volume-bound` is forwarded app-side over
  pinned TLS to the exec host (the ADR-119 volume holder, web-1 today). The edge between
  web hosts is internal to `api`/`hetzner` — note it in the same edge prose rather than a
  new edge (the model has no web-1/web-2 element split).
- Validate with `apps/web-platform/test/c4-code-syntax.test.ts`,
  `apps/web-platform/test/c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

Everything lands in this PR. The ADR amendments describe the state AS MERGED (the
forwarder live), not a future state.

## Implementation Phases

### Phase 0 — Module + decision logic (no behavior change)

- `server/inngest/exec-placement.ts`: `EXEC_HOST_PRIVATE_IP` constant, `classifyFnId`
  (prefix `soleur-runtime-`, `-failure` suffix strip), `decidePlacement` (the table
  above, pure function taking env + request facts), structured `placement_decision`
  logging seam.
- `server/host-private-ip.ts` (or fold into `host-identity.ts`): read/trim
  `SOLEUR_HOST_PRIVATE_IP`; `isExecHost()` returning `true|false|unknown` where
  `unknown` means unset/empty → refuse path.
- Unit tests for the pure decision function — every row of the table plus mutation-matrix
  fixtures (synthesized, `cq-test-fixtures-synthesized-only`).

### Phase 1 — Forwarder + receiver wiring

- `app/api/inngest/route.ts`: wrap `handlers.POST` with the forwarder (GET/PUT/`?probe=`
  bypass; `cq-nextjs-route-files-http-only-exports` — handler composition only, no new
  exports).
- `server/inngest/exec-forward-client.ts`: the pinned-TLS outbound dial
  (`loadProxyTlsClientCa` + relay dial shape), verbatim body/header/query forwarding,
  streamed response pass-through, a bounded connect timeout plus per-chunk idle timeout with a distinct
  `placement.forward_failed` error (fail-closed — never fall back to local execution).
- Receiver: `request` handler for `/api/inngest` on the existing 8443 HTTPS server in
  `session-proxy.ts` (option (i)) OR sibling listener (option (ii)) — strips nothing,
  forwards the marked request internally to the app serve path.
- `server/index.ts`: wire whichever receiver shape is chosen (the proxy server already
  starts there).
- `infra/ci-deploy.sh`: add `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` to the prod `docker
  run` env (~L5798) and `-e SOLEUR_HOST_PRIVATE_IP=` to the canary tuple (~L5413).
- `infra/lib/docker-run-tuple.py` + `infra/docker-run-tuple.test.sh`: pin the new env
  line(s).

### Phase 2 — Guards + tests

- `test/server/inngest/exec-placement-forward.test.ts` — the Guard Contract below.
- Extend `test/server/inngest/execution-placement.test.ts` Guard 1: served set is now
  asserted through the forwarder's classifier (every served fnId resolves to a class,
  including `-failure` ids).
- `infra/ci-deploy.test.sh`: fixture asserting the prod tuple carries the new `-e` line.

### Phase 3 — ADR/C4 + runbook

- The five ADR edits and `model.c4` edge edit above.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (or a sibling
  runbook): `placement.exec_identity_missing` recovery — re-deploy (no SSH) after the NIC
  is up; `placement.forward_failed` diagnosis — the 8445 publish state
  (`net.ipv4.ip_nonlocal_bind`) and proxy-cert expiry are the two named causes.

### Phase 4 — Optional unpin (gated, may defer)

- Move `resolveCurrentWorkspaceId` (and only it) out of the module that reaches
  `server/workspace-resolver.ts`, re-class `cfo-on-payment-failed` and `github-on-event`
  to `portable`, let Guard 2 verify. Defer if the helper's other consumers make the move
  unsafe at work time (recorded as a scope-out, not silently skipped).

## Files to Create

- `apps/web-platform/server/inngest/exec-placement.ts` — constants + pure
  classify/decide functions + forwarder entry.
- `apps/web-platform/server/inngest/exec-forward-client.ts` — pinned-TLS outbound dial +
  streamed forward.
- `apps/web-platform/test/server/inngest/exec-placement-forward.test.ts` — Guard
  Contract suite (synthesized fixtures).
- `apps/web-platform/scripts/exec-placement-probe.sh` — committed probe
  script for the Observability discoverability test (prints `exec-placement: ok`).

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — wrap POST in the forwarder.
- `apps/web-platform/server/index.ts` — receiver wiring (if option (i), the 8443
  `request` handler for `/api/inngest`; if (ii), the sibling listener start).
- `apps/web-platform/server/session-proxy.ts` — option (i) only: consume `request`
  events for `/api/inngest` on the existing https server.
- `apps/web-platform/server/host-identity.ts` (or new sibling) — `SOLEUR_HOST_PRIVATE_IP`
  reader + `isExecHost()`.
- `apps/web-platform/infra/ci-deploy.sh` — `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"`
  (prod), `-e SOLEUR_HOST_PRIVATE_IP=` (canary).
- `apps/web-platform/infra/lib/docker-run-tuple.py` + `infra/docker-run-tuple.test.sh` —
  pin the new env line.
- `apps/web-platform/infra/ci-deploy.test.sh` — prod-tuple fixture for the new env line.
- `apps/web-platform/test/server/inngest/execution-placement.test.ts` — Guard 1
  extension (served-set through the classifier).
- `knowledge-base/engineering/architecture/decisions/ADR-033-…-child-process-spawn.md`,
  `ADR-248-….md`, `ADR-243-….md`, `ADR-143-….md`, `ADR-030-….md` — amendments above.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `inngest -> api` edge
  prose.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — recovery section.
- Phase 4 (optional): `apps/web-platform/server/byok-resolver.ts` (or wherever
  `resolveCurrentWorkspaceId` lives) + `execution-placement.ts` rows for the two
  re-classed functions.

## Guard Contract

### Guard 1 — served-set/classifier parity

**Property.** Every function id the `serve()` registry can receive resolves to exactly
  one `EXECUTION_PLACEMENT` class through the forwarder's classifier — including
  `<id>-failure` handlers (inherit parent).
**Assembly.** The route's functions array (the serve() chokepoint — its own guard (a)
  already pins the set), the classifier's strip rules, and the manifest keys. No second
  class table may exist — the forwarder imports `EXECUTION_PLACEMENT`, it does not copy.
**Mutation matrix.**
  | Mutation | Expected |
  |---|---|
  | Register a `cron-*.ts` function in the serve array with no manifest row | RED |
  | Manifest row for an id no route serves | RED |
  | `onFailure` handler added to a served function — `<id>-failure` must resolve to the parent's class | GREEN-PASS (asserts inheritance, not failure) |
  | Change a row's class `portable` → `host-affine` | classifier flips the function's decision — assert per-class verdict moves |
  | fnId arrives with the `soleur-runtime-` prefix missing or doubled | classifier returns pinned-class fail-closed, never a wrong-class execute |
  | The classifier module itself is replaced by an import that re-declares the table | RED — assert the table is THE imported `EXECUTION_PLACEMENT` (identity check), not a shape-equal copy |

### Guard 2 — fail-closed direction (decision matrix)

**Property.** No code path executes a pinned-class (`host-affine`/`volume-bound`),
  unknown-class, or unclassifiable step call on a non-exec host; a POST with no `fnId`/no `probe` is treated as pinned-class; a host that cannot
  establish exec identity refuses rather than guesses.
**Assembly.** Every branch of `decidePlacement`: method/marker/identity/class inputs —
  the chokepoint is the single decision function; the route handler must call it (wired
  in Phase 1) rather than re-implementing classification inline.
**Mutation matrix.**
  | Mutation | Expected |
  |---|---|
  | `SOLEUR_HOST_PRIVATE_IP` unset on a host receiving a pinned call | `refuse` (never `execute`) |
  | `SOLEUR_HOST_PRIVATE_IP` = `10.0.1.11` (web-2) + pinned call | `forward` to `10.0.1.10`, marker set |
  | Marked call arriving on non-exec host | `refuse` — never re-forward (loop) |
  | POST with no `fnId` and no `probe` | `forward` — the receiving SDK on the exec host rejects it; direction stays fail-closed |
  | `?probe=` request on non-exec host | `execute` locally (must-PASS — probes answer anywhere) |
  | GET/PUT registration on non-exec host | `execute` locally (must-PASS) |
  | Forwarder removed from the route (serve() exposed directly) | suite RED — a test asserts the POST export is wrapped, e.g. via a request-shaped probe asserting marker behavior |

### Guard 3 — forwarder wire fidelity

**Property.** A forwarded request is byte-faithful: identical method, path, full query
  (incl. `fnId`), all signature headers and the raw body reach the exec host; the response
  streams back without buffering; the marker header is added and nothing else mutates the
  envelope.
**Assembly.** The forward function's single fetch call — method, URL construction,
  header pass-through (minus Host), body pass-through, response pass-through, timeout
  config, TLS options (`ca` + `rejectUnauthorized: true`).
**Mutation matrix.**
  | Mutation | Expected |
  |---|---|
  | Drop an inbound end-to-end header from the forward | RED (assert header-set equality modulo Host, the marker, and the RFC 7230 hop-by-hop set) |
  | Buffer the response body before returning | RED — assert behaviour: the first chunk is emitted before the upstream completes (behavioural, not object identity) |
  | `rejectUnauthorized: false` or `ca` omitted | RED (assert TLS options literally) |
  | Marker header omitted on forward | RED (assert `EXEC_FORWARD_HEADER` present) |
  | Target URL derived from request Host or env instead of the pin constant | RED (assert the literal `https://10.0.1.10:` origin) |
  | Harness row: fixture server returns a fixed streamed body | must-PASS — forwarded response bytes + status identical |
  | Harness row: fixture sees the loop twice (marked request forwarded again) | RED — the second hop never happens (refuse path) |

### Guard 4 — pin-target drift

**Property.** The `10.0.1.10` constant, `inngest-host.tf`'s `sdk_url` host, and
  `variables.tf`/`network.tf`'s web-1 private IP are one source of truth — the exec host is
  the host that already carries the registration poll AND the LUKS workspaces volume.
**Assembly.** `server/inngest/exec-placement.ts` constant, `infra/inngest-host.tf`
  `sdk_url`, `infra/variables.tf` (or `network.tf`) `web_hosts["web-1"].private_ip`,
  the `workspaces_luks` volume's host-binding declaration under `apps/web-platform/infra/` — resolved by name at guard-authoring time (the resource set that mounts the LUKS workspaces volume on web-1; if no attachment resource exists, the guard binds the pin to the web-1 `hcloud_server`/`hcloud_server_network` pair instead and the volume coupling is recorded as a stated residual).
**Mutation matrix.**
  | Mutation | Expected |
  |---|---|
  | Change the constant to `10.0.1.11` | RED |
  | Change `sdk_url` host | RED |
  | Repoint the workspaces-LUKS host binding to web-2 | RED — the pin constant must follow the volume holder; if no declarable attachment resource exists the row binds pin ↔ `hcloud_server_network.web["web-1"]` instead and the volume coupling is a stated residual |
  | `SOLEUR_HOST_PRIVATE_IP` injection line removed from the prod docker-run tuple | RED (docker-run-tuple.test.sh row) |
  | must-PASS: constants consistent (real tree, unmutated) | GREEN |
  | Introduce a TOTAL read deadline on the forward | RED — streamed steps outlive any total deadline; only connect + per-chunk idle timeouts are legal |

## Observability

```yaml
liveness_signal:
  what: "placement_decision structured log rows (op=inngest-exec-placement, fields: fnId, class, decision, host_ip) on every step call; placement.forward_failed and placement.exec_identity_missing are error-level and mirrored to Sentry via reportSilentFallback"
  cadence: per request
  alert_target: Better Stack log alert — 0 placement_decision rows on pinned fns for 24h (cron silence already pages per-function via Sentry monitors)
  configured_in: "reportSilentFallback + createChildLogger('inngest-exec-placement'); Better Stack SQL in infra/betterstack-logs-alerts.tf only if a new alert is warranted — the per-function Sentry monitors already cover a total stall"
error_reporting:
  destination: Sentry (reportSilentFallback) + journald -> Vector -> Better Stack
  fail_loud: "refusals (exec_identity_missing, marked-on-nonexec) and forward failures are error-level + Sentry; they are never swallowed into the step response"
failure_modes:
  - mode: "exec host unreachable (8445 publish degraded to loopback / cert expired)"
    detection: "placement.forward_failed error rows + per-function missed Sentry check-ins"
    alert_route: Sentry + per-function cron monitors (existing)
  - mode: "SOLEUR_HOST_PRIVATE_IP empty after NIC-late deploy"
    detection: "placement.exec_identity_missing error rows on every pinned call"
    alert_route: Sentry (distinct tag) + runbook recovery step
  - mode: "marker spoofed on public path"
    detection: "marked request arriving on the public listener is ignored by the non-exec refusal rule; log warn row"
    alert_route: journald warn (no page — unsigned calls fail signature anyway)
logs:
  where: "pino -> journald -> Vector -> Better Stack (feature=inngest-exec-placement)"
  retention: Better Stack standard retention
discoverability_test:
  command: "bash apps/web-platform/scripts/exec-placement-probe.sh"
  expected_output: "exec-placement: ok"
```

## Encryption Posture

```yaml
at_rest: "no new persistent store — nothing persists; step payloads transit memory only"
in_transit:
  - connection: "web-2 app -> web-1 exec listener (private net, 10.0.1.10)"
    tls: "pinned self-signed CA — PROXY_TLS_CERT via loadProxyTlsClientCa"
    cert_verification: "on (rejectUnauthorized: true + default identity check — the cert carries SANs over every web host's private IP, proxy-tls.ts header)"
    does_not_defend: "a holder of prd env (the cert is an env value — same exposure as the relay itself); compromise of the exec host itself"
    disclosed_as: "host-to-host relay TLS (same posture as session-proxy)"
  - connection: "inngest host -> app.soleur.ai step calls (existing)"
    tls: "unchanged — Cloudflare edge; edge-to-origin is `flexible` (ADR-321 in flight, #10479) — pre-existing posture, not modified by this plan"
    cert_verification: "n/a (pre-existing)"
    does_not_defend: "(pre-existing, unchanged)"
    disclosed_as: "(pre-existing, unchanged)"
exception: none — the new hop is TLS by ruling (T3); no plaintext exception is declared
```

## User-Brand Impact

**If this lands broken, the user experiences:** `agent-on-spawn-requested` (volume-bound —
the founder-facing BYOK leader loop) silently dying (refusal → missed Sentry check-in →
page), or — worse — a volume-bound function corrupting/duplicating workspace state by
executing on the wrong host, or a duplicated paid Claude session billed to the shared
substrate while the founder's own spawn queue stalls. The threshold is arguably **already
breached today**: since the 2026-11-08 flip, ~half of these calls land on web-2 (CPO
sign-off point — this PR closes a live exposure, it does not introduce the risk).

**If this leaks, the user's [data / workflow / money] is exposed via:** step-call payloads
(BYOK agent-spawn event data, workspace ids, prompt content) crossing the private net —
mitigated by pinned-TLS transport (T3) and the private subnet boundary; the exposure class
that remains is a prd-env holder forging the relay, already true of session-proxy.

**Brand-survival threshold:** single-user incident — the route carries the founder-facing
`agent-on-spawn-requested` leader loop; ADR-243 held this exact surface to that threshold.

**Sign-off:** `requires_cpo_signoff: true` in frontmatter; `soleur:product:cpo` invoked at
plan time (see Domain Review); `soleur:engineering:review:user-impact-reviewer` will run at
review-time per the review skill's conditional-agent block.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Once web-2 gets serving weight, `portable` functions may run on any web host. `host-affine` functions stick to one host and `volume-bound` functions stay on the volume holder." [issue #9137] | The forwarder + decision table (Phases 0–2); Files to Create/Edit | mapped |
| 2 | "This delivers most of what option (a) would (losing web-1 no longer drops portable work) without touching the singleton control plane." [issue #9137] | Option C — no inngest-host/server changes at all | mapped |
| 3 | "Pointing `cloudflare_record.app` at a second host without this work reopens ADR-243 §2." [issue #9137] | ADR-243 §2 addendum + Guard 2 fail-closed | mapped |
| 4 | "a second SDK worker on the Inngest host. Only for the case where a verifier must survive the loss of every web host." [issue #9137, fallback] | Non-Goals — deferred per CTO T4; trigger unmet | descoped — justification: fallback trigger ("a verifier must survive the loss of every web host") does not exist today per ADR-248 clock on both hosts + GHA-native schedule (CTO T4) |
| 5 | "host affinity for host-affine/volume-bound functions" [brief/issue title] | The fnId forwarder — literal host affinity at the app layer | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| exec-placement.ts forwarder | "host affinity for host-affine/volume-bound functions" | asked |
| SOLEUR_HOST_PRIVATE_IP + ci-deploy edit | — | inferred — justification: the app cannot self-identify the exec host without a per-host value; ci-deploy already resolves it (`PROXY_BIND`) — CTO T2 |
| pinned-TLS forward transport | — | inferred — justification: forwarded calls carry user payloads; plaintext rejected by CTO T3 under the stricter-default rule |
| ADR-033/248/243/143/030 amendments + model.c4 | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the mechanism is a recorded-architecture change and ADR-248 reversal trigger 1 fires on this diff |
| Guard suite + probe script | — | inferred — justification: Phase 2.12 Guard Contract + Phase 2.9 observability gates; the manifest header requires enforcement now that #9137 consumes it |
| Phase 4 optional unpin | "moving that helper to a filesystem-free module unpins it (#9137)" (manifest reason fields) | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform/server/` (forwarder + receiver), `app/api/inngest/`,
  `apps/web-platform/infra/` (one env line + tuple pins), `knowledge-base/engineering/architecture/` (ADRs + C4)
- Planned files: ~16 | Estimated changed lines: ~900 (new module ~350, forwarder ~250, receiver ~120, tests ~150, docs ~30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the threshold is grazed but the change is one mechanism; the
  ADR/C4 edits are deliverables of the same decision, not separable scope.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change inside the app
boundary (forwarder, env, tests, ADRs). Product domain assessed: no user-facing surface
created or modified (the mechanical UI-surface scan of Files to Create/Edit matches no
`components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx`); tier NONE. CPO sign-off is
nevertheless required by the `single-user incident` threshold (User-Brand Impact), not by
the UX gate — invoked separately (see below).

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan — the issue's
prior plan was the input).

## GDPR / Compliance note (Phase 2.7)

The `single-user incident` threshold triggers the gate. Scoped assessment: the forwarder
moves step-call payloads — which can carry user workspace ids and agent-spawn event data —
between two hosts we operate on our own subnet, under the same prd data custody. No new
processor, no new processing purpose, no new storage: Art. 30 posture unchanged; the hop is
a transport detail of an existing processing activity, TLS-protected (Encryption Posture).
Advisory only; no Critical finding (no Art. 9 data, lawful basis unchanged, no register
update needed). `compliance-posture.md` Active Items: no new entry.

## Infrastructure (IaC) — Phase 2.8

Not triggered: no new resource, service, secret, vendor or runtime process. The single
`infra/ci-deploy.sh` `-e` line rides the existing infra-config push path — the established
mechanism for this file, not a manual provisioning step.

## Task Design (Phase 2.9.3)

Not triggered: no new workflow/cron/timer/daemon — the forwarder is request-path code on an
existing route.

## Acceptance Criteria

- [ ] AC1: A synthesized step POST carrying `fnId=soleur-runtime-<host-affine-fn>` reaching a
  non-exec host is forwarded verbatim to `https://10.0.1.10:8445/api/inngest` with the marker
  header, pinned-CA TLS, all original headers/query/body, and the response streamed back —
  asserted end-to-end against a fixture receiver.
- [ ] AC2: The same call reaching the exec host (`SOLEUR_HOST_PRIVATE_IP=10.0.1.10`)
  executes locally — the SDK handler receives it unwrapped.
- [ ] AC3: A `portable`-class step call executes locally on EITHER host value.
- [ ] AC4: A pinned-class call with `SOLEUR_HOST_PRIVATE_IP` unset/empty is refused with the
  distinct `placement.exec_identity_missing` error — never executed locally.
- [ ] AC5: A marked call arriving on a non-exec host is refused — no second forward hop
  (loop-guard).
- [ ] AC6: GET/PUT registration and `?probe=` requests bypass the forwarder on any host —
  registration semantics unchanged (`#5159` invariants intact: `serveOrigin`/`servePath`
  still report `https://app.soleur.ai` only).
- [ ] AC7: Every route-served function id (including `-failure` ids) resolves through the
  classifier to a manifest class — Guard 1 mutation matrix green, including the own-dispatch
  row.
- [ ] AC8: Guard 4 pins `10.0.1.10` against `inngest-host.tf` `sdk_url` AND the web-1 private
  IP source AND the `workspaces_luks` attachment — mutating any one reddens it.
- [ ] AC9: `docker-run-tuple.test.sh` (and `ci-deploy.test.sh` fixture) pins
  `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` on prod and empty on canary, and names the
  first-boot tuple's value (resolved IP or recorded stall-until-first-deploy residual).
- [ ] AC9b: A refused pinned call returns HTTP 503 (retriable) — an `agent-on-spawn` run
  refused during an identity-missing window recovers within the SDK retry window after
  the redeploy runbook step; a forward carrying no `x-inngest-signature` header is refused
  before any dial.
- [ ] AC10: `placement_decision`/`forward_failed`/`exec_identity_missing` log rows carry
  fnId, class, decision and host identity; the discoverability probe prints
  `exec-placement: ok` under 15 s.
- [ ] AC11: ADR-033 amendment, ADR-248 trigger note, ADR-243 §2 addendum, ADR-143 addendum,
  ADR-030 log line, and the `model.c4` edge edit all land in the same PR; the c4 syntax /
  render / count-parity tests pass.
- [ ] AC12: Live verification post-merge: a pinned-class cron's `placement_decision` rows
  show `decision=forward` on web-2 and `decision=execute` on web-1; a portable cron shows
  `execute` on both — read from Better Stack, no SSH (the follow-through is a tracked
  `scripts/followthroughs/` probe if the verdict needs >24h of evidence).
- [ ] AC13: `next build` + the full vitest suite + the infra shell-test suite pass; no
  workflow files are edited.

## Test Scenarios

- Forward fidelity: signature header set preserved; body bytes identical; query including
  `fnId`/`stepId` identical; response stream unbuffered.
- Identity edge cases: `SOLEUR_HOST_PRIVATE_IP` unset vs empty vs `0.0.0.0` vs `10.0.1.10`
  vs `10.0.1.11` vs whitespace-padded.
- Classification edge cases: `-failure` suffix, unknown id, doubled/missing prefix,
  POST with no `fnId` and no `probe`, `?probe=` + `fnId` combos.
- TLS: dial with `rejectUnauthorized: true` and pinned CA; an untrusted-cert fixture fails
  closed; expired/absent material fails closed with a Sentry mirror (not a crash loop).
- Concurrency: two parallel pinned calls forward independently; a retried call within the
  single-flight window joins on the exec host (ADR-243 §2 semantics preserved — the join
  happens where the spawn runs).

## Risks and Deferrals

- **web-1 remains SPOF for pinned classes** (CTO dissent, accepted): already true via the
  ADR-119 sole-copy volume; this plan makes it visible in the model, not new.
- **8445 publish degradation** (loopback fallback when `ip_nonlocal_bind` ≠ 1): forwarding
  fails closed → pinned-fns stall visibly; recovery is a redeploy (runbook). Accepted per
  T2/T3 — the alternative (exec-side blind spot) is worse.
- **Receiver-choice residual:** the sibling listener on :8445 was chosen (the :8443 wss `request` handler was rejected at plan-review — `HELLO_DEADLINE_MS` kills streamed step calls); if it had proven awkward at work
  time, a sibling listener is the fallback (same material); the plan does not pin which —
  noted for `soleur:work` to decide with the diff in hand.
- **Phase 4 unpin** may defer to a scope-out if `resolveCurrentWorkspaceId`'s consumers
  block the move.
- **ADR-248 reversal trigger 1 fires** with this PR — the amendment records the re-derivation.
- **Forward-timeout duplicate-billing (CPO condition 3):** if a forward times out after the
  exec host started a paid Claude session, Inngest retries and a naive design would double
  the session. This mechanism is protected BY CONSTRUCTION: the retried call lands on any
  host, is re-forwarded to the exec host, and `spawnClaudeEval`'s process-local
  single-flight map — which lives on the exec host — JOINS the in-flight run (the exact
  join path ADR-243 §2 defines, including the 2 h `SETTLED_TTL_MS` result replay). The
  residual is a forward that succeeds but whose response is lost after completion — the
  TTL-replay arm covers it. Asserted by a Test Scenario row: a retried call within the
  single-flight window joins, never respawns.
- **Founder-visible stall state (CPO condition 2, deferred scope-out):** a fail-closed
  refusal surfaces to the operator (Sentry page) but the founder only sees a hung spawn.
  A "queued/retrying" surface for refused spawns is a product-facing affordance — scope-out,
  to be filed as a follow-up issue at work time if not already tracked (`user-impact-reviewer`
  verifies this and the duplicate-billing point at review).

## Non-Goals

- **Fallback (a) — second SDK worker on the Inngest host:** deferred under #9137's own
  re-evaluation criteria (a host-state verifier that neither GHA `schedule:` nor the ADR-248
  clock can serve; or a measured incident of web-host loss dropping portable work). Restated
  verbatim so it is not silently dropped (CTO T4).
- Function-id/app-id migration — Option A rejected (CTO T1).
- Any Terraform/DNS/LB/workflow change; any change to `EXPECTED_CRON_FUNCTIONS`, Sentry
  monitor slugs, or the watchdog manifest.
- The `_cron-shared.ts` split (prior plan's deferred T5) — the forwarder does not need it;
  it stays a candidate refactor for a later hygiene pass (it is the Guard-2 allowlist's
  complexity source, not a correctness blocker).
- `origin-tls`/`flexible`-mode work (ADR-321) — pre-existing posture, unchanged.
- Moving the exec pin off web-1 (volume-holder mobility) — a web-host replace keeps
  10.0.1.10 via the TF key; a *volume* move is a separate migration that must re-point the
  constant (Guard 4 reddens until it does — by design).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the planned
file paths (`route.ts`, `execution-placement.ts`, `ci-deploy.sh`, `session-proxy.ts`,
`host-identity.ts`, `index.ts`). Checked 2026-11-10.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails `deepen-plan`
  Phase 4.6 — filled above.
- The `inngest -> api` C4 edge edit must not add numeric counts (c4-count-parity).
- Never widen `PORTABLE_SAFE_SHARED_EXPORTS` to make a row pass; re-class the row instead
  (manifest header, carried from #7230).
- infra/** merge fires `apply-web-platform-infra.yml` — the ci-deploy.sh edit is the only
  infra-path change and rides the normal push path; no workflow edits.
- `next build` loads route modules without env — the forwarder must not throw at module
  load on missing `SOLEUR_HOST_PRIVATE_IP`/`PROXY_TLS_*` (mirror `client.ts`'s
  `IS_BUILD_PHASE` and `session-proxy`'s inert-when-absent pattern).

## Deferred-item tracking

- Fallback (a) second SDK worker: no new issue — it lives in #9137's re-evaluation criteria
  and this plan closes #9137 with the primary target; the Non-Goals section restates the
  triggers so a future audit re-opens rather than loses it.
- `_cron-shared.ts` split (prior-plan T5) and the Phase-4 optional unpin: not deferred
  items — Phase 4 is in-scope but gated; the T5 split remains a hygiene candidate and is
  named in Non-Goals.

## Plan Review Revisions

Panel run 2026-11-10 (condensed eng panel + spec-flow, spawned via `claude -p`; CPO sign-off
recorded separately). Mechanical findings auto-applied; taste findings persisted to
`decision-challenges.md` per headless policy.

**Applied (mechanical):** P1 sibling-listener receiver (the :8443 `HELLO_DEADLINE_MS` would
kill streamed HTTP steps — option (i) removed); P2 `workspaces_luks` attachment is not a
declared TF resource → Guard 4/AC8 name the resolvable binding instead; P3 `forceExecution`
is an internal SDK flag, not HTTP-visible → decision rows rewritten as "POST with no `fnId`
and no `probe` → forward"; P4 connect + per-chunk idle timeouts only (no total deadline —
would recreate the 524 double-run); P5 `x-inngest-signature` presence gate before forwarding
(the private listener must not become reachable to anonymous public traffic); P6
`https.request`/undici `Agent` transport + hop-by-hop header strip + behavioural stream
assertion; P7 cert carries web-host private-IP SANs (`proxy-tls.ts` header) → default
identity check, hedge removed; P8 first-boot `docker run` tuple in `cloud-init.yml` covered
(AC9 + residual option); P9 refusal returns HTTP 503 retriable, never `NonRetriable` (AC9b).

**CPO sign-off:** APPROVED with conditions — threshold holds (arguably already breached
since the 2026-11-08 flip); founder-visible stall state deferred as a scope-out follow-up;
duplicate-billing risk addressed by construction (retried calls re-forward to the exec host
and JOIN the single-flight — recorded in Risks); Phase 4 unpin recommended rather than
default-deferred (kept as gated-optional phase); `user-impact-reviewer` must re-verify the
stall-visibility and duplicate-billing items at review time.

## Deepen-pass record (soleur:deepen-plan, 2026-11-10)

Gate outcomes: 4.6 User-Brand Impact — PASS (single-user incident + scope content); 4.7
Observability — PASS (5 fields, allowlisted `bash` verb, literal `exec-placement: ok`,
sub-15s probe); 4.8 PAT shapes — PASS (none); 4.9 UI wireframe — N/A (no UI-surface files);
4.10 Encryption Posture — PASS (TLS declared per hop, no exception needed); 4.11 Guard
Contract — PASS (`lint-guard-contract.py` green: 4 entries, matrices ≥3 rows incl.
own-dispatch and must-PASS rows); 4.12 Scope Check — PASS (5 asks mapped, inferred items
justified); 4.13 Task Design — N/A (no new autonomous-task surface); 4.4 precedent-diff —
covered (pinned-TLS dial reuses `session-proxy`/`proxy-tls.ts` precedent verbatim, named in
the plan); 4.45 verify-the-negative — spot-checked the plan's NEVER/fail-closed claims
against the cited files (all held; the two that didn't — `SOLEUR_PROXY_BIND` identity,
`hcloud_volume_attachment.workspaces_luks` — were corrected pre-commit via the T2 re-ruling
and panel P2); 4.5 network-outage — no trigger patterns in Overview/Problem/Hypotheses;
4.55 downtime — no new downtime class (standard rolling deploy + ADR-078 drain lease; the
forwarder adds no host replace or migration).

## Downtime & Cutover

No downtime-inducing operation: the change rides the standard rolling deploy (canary +
drain) with the ADR-078 deploy lease; no host replace, no migration, no singleton cutover.
The one new publish (sibling listener port on the private IP) is additive — it serves
nothing until the forwarder ships in the same image.
