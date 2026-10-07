---
title: Opt-in open-web egress via a dedicated CONNECT-only gateway and per-session forwarder
status: accepted
date: 2026-10-05
supersedes: none
issue: 9534
related: [9529]
related_adrs: [ADR-051]
tags: [egress, sandbox, squid, security, agent-runtime]
brand_survival_threshold: single-user incident
---

# ADR-276: Opt-in open-web egress via a dedicated CONNECT-only gateway and per-session forwarder

## Status

Accepted — 2026-10-05. Ships dark: the gateway infrastructure merged first
(PR-A) with no consumer; product wiring (this ADR's subject) merged second
(PR-B). The toggle defaults off and is owner-gated.

## Context

Hosted agent sessions ran with zero network egress (the posture instituted
by PR #871). The product need — agents that can fetch documentation,
install packages, and call external APIs — requires reversing that posture
for workspaces that ask for it, without weakening it for those that do not.

Three constraints fixed the shape before any code moved:

- **Default zero-egress is the trust property.** Any relaxation must be
  opt-in, workspace-scoped, owner-writable, and revocable live — including
  against sessions already running.
- **The sandbox's own domain allowlist is not a policy boundary.** The
  Phase-0 spike (spec `feat-open-web-egress` TR7) measured that under
  `httpProxyPort` the runtime's sandbox proxy forwards upstream **without**
  applying its domain filter — the proxy owns all policy. A flat
  `allowedDomains` widening would therefore not be a boundary at all.
- **Credential quarantine is a precondition, not a follow-up.** An agent
  that can reach arbitrary HTTPS hosts can exfiltrate any credential
  visible to its sandbox. Egress cannot ship while sandboxed commands can
  read API keys, service tokens, or git auth.

### Phase-0 measurements that decided the mechanism

Measured against the pinned `@anthropic-ai/claude-agent-sdk@0.3.284`
vendored binary (full record: spec TR7):

1. `network.httpProxyPort` is a host-side loopback port the sandbox
   runtime chains to through its own in-netns proxy — the sandboxed
   child's `localhost` is not the container loopback, so a
   directly-bindable forwarder is unreachable from the sandbox path and
   every sandboxed request must transit the chain.
2. In-process WebFetch ignores `httpProxyPort` entirely but honors
   `HTTP(S)_PROXY` on the spawned CLI process.
3. A credentialed env proxy URL (`http://u:tok@127.0.0.1:port`) steers
   **both** paths — sandboxed child traffic (chained upstream with the
   child-supplied `Proxy-Authorization` preserved) and in-process fetches
   — while the session token never enters the sandboxed child's env (the
   sandbox runtime substitutes its own per-session creds on the in-netns
   hop).
4. `NO_PROXY` is not honored by the SDK's API path (control-plane CONNECTs
   still reached the proxy); the client retries direct on refusal.
   NO_PROXY is emitted as hygiene but exemption is not load-bearing — the
   gateway treats control-plane CONNECTs as ordinary public traffic.

## Decision

1. **Env proxy URL is the carrier; `httpProxyPort` is not used.** Per
   measurement 3, a per-dispatch `HTTP(S)_PROXY` (both cases) carrying
   `http://<workspaceId>:<sessionToken>@127.0.0.1:<port>` satisfies the
   forwarder's inbound-auth contract on both fetch paths — which a
   creds-less `httpProxyPort` chain cannot — and keeps the session token
   out of the sandboxed environment.
2. **A dedicated Squid gateway is the load-bearing policy boundary.**
   CONNECT-only, `SSL_ports 443`, `proxy_auth REQUIRED`, DNS-pinned per
   request, file-backed destination deny-set (private/link-local/
   cluster-private/metadata ranges), on its own docker bridge
   (`soleur-egress0`), belted by an nftables chain (`SOLEUR-EGRESS-GW`,
   iifname- and `ct state new`-scoped). The gateway — not the SDK sandbox
   and not `deniedDomains` — is authoritative; measured behavior says the
   in-process path applies no filter at all.
3. **Per-session forwarder + token, lifetime-bound to the dispatch.** A
   spawned forwarder (`egress-forwarder.mjs`, in the app image) binds
   `127.0.0.1:0`, requires the session token inbound, injects
   `Proxy-Authorization: Basic <workspaceId>:<token>` upstream, and dies
   with the session (ppid watchdog). Token files under
   `/var/lib/soleur/egress-tokens` (mode 0700 dir, 0600 files) are the
   gateway's auth basis; deleting the file revokes access — which is what
   makes toggle-off kill a live session's egress: the warm path re-resolves
   the entitlement per dispatch and tears the forwarder down.
4. **Fail-closed degradation, never a dead proxy.** Any error in
   entitlement resolution (RPC error, NULL, P0001) resolves false; any
   forwarder-spawn/readiness failure cleans up and degrades the dispatch
   to zero-egress. Both paths are mirrored to Sentry (`web-egress`
   feature tag) — silent fallback is forbidden by `cq-silent-fallback`.
5. **Credential quarantine on the sandbox, only when entitled.**
   `buildAgentSandboxConfig(allowWebEgress)` emits a deny census
   (`credentials.envVars: deny`) covering the Anthropic auth vars, the
   in-sandbox git/GitHub auth set, and the full `ALLOWED_SERVICE_ENV_VARS`
   BYOK census — sourced from the canonical export, not a hand-copied
   list — plus `denyRead` on credential files and the token-dir mount.
   `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_NOSYSTEM` are deliberately not denied
   (they neutralize config; they hold no secret). Consequence: entitled
   sessions cannot `git push` or use BYOK service creds in-sandbox until
   the Phase-B broker (#9543); the toggle's confirm copy says so.
6. **WebFetch gated on verified entitlement, not the flag alone.** The
   tool is re-admitted only when the entitlement resolved true AND the
   forwarder bound — a spawn failure leaves `WebFetch` disallowed.
   `WebSearch` stays disallowed in Phase A.
7. **Cron stays default-deny.** Crons never resolve this entitlement and
   the L4 nftables containment is untouched — verified by
   `cron-egress-firewall` fixtures.

## Consequences

- Destinations are arbitrary public hosts at the agent's choosing — the
  gateway is a chokepoint and policy boundary, not a content filter; the
  residual exfiltration risk is disclosed to the owner at enable time and
  accepted by name in the DPIA screening (residual (a)).
- Platform control-plane traffic (Anthropic API, telemetry) transits the
  gateway in entitled sessions (measurement 4) — logged with workspace
  attribution; TLS stays end-to-end.
- The audit-log queryable view is deferred to #9545; Phase A relies on the
  gateway decision log reaching Better Stack (PA-8 pipeline).
- Reversal risk: none structural — the toggle's row is a single nullable
  boolean; the forwarder, token dir, and gateway are inert when no
  workspace opts in.

## Boundary mechanics (review amendments, PR-B)

- **Membership gate on `SOLEUR-EGRESS-GW`:** the chain carries a terminal `ct state new ip saddr != <gw-ip> drop` (default-deny whole bridge when no gateway IP is derived). Without it, `docker network connect soleur-egress0 <container>` hands a second member open egress minus the deny set, bypassing Squid auth.
- **Token dir ACL is the mint boundary:** `/var/lib/soleur/egress-tokens` is `0711` owned by the app container's `soleur` uid (1001) — the dispatcher writes, the gw's `proxy`-uid helper traverses for `-f`, and token filenames (the credentials) are unlistable by others. Residual accepted: any same-uid in-container process could mint or read a token file — the container uid is the trust boundary; the sandboxed agent sits behind `denyRead` + the netns.
- **Attribution binding:** the auth helper requires the presented username to equal the token file's content (the minting dispatcher writes `<workspaceId>`) — a docker0-resident token holder cannot forge `%un` attribution in the decision log.
- **Helper cache:** `credentialsttl 30s` — the forwarder's death is the revocation mechanism; file deletion bounds the residual window.
- **Ambient proxy vars removed from `AGENT_ENV_ALLOWLIST`:** an ambient `HTTP_PROXY` on the dispatcher would otherwise steer every session outside the guard. The `egressProxy` injection is the only sanctioned carrier.
- **INPUT-side filtering for `soleur-egress0` is deliberately absent** — docker0 shares the same posture (host-local services reachable from containers); a Squid compromise would gain a host dialer on any port. Recorded acceptance, matching the standing container trust model.
- **Canary isolation:** only the prod container sets `SOLEUR_EGRESS_REAPER=1`; a second consumer of the shared token dir (deploy canary) must never sweep tokens it did not mint — its `/proc` cannot see the prod forwarders.

## Scope notes (review amendments, PR-B)

- **`ws-handler` `pendingLeader` lineage does not receive `webEgress`** (`ws-handler.ts:2553` still routes through legacy `startAgentSession`, which never threads the option). The workspace toggle is silently inert on that path. Recorded rather than fixed: leader sessions are retiring machinery; if they ship user-facing again, the entitlement wiring must be extended — tracked as a Phase-B note.
- **Prompt coherence under the quarantine**: when a session is entitled, the `GH_TOKEN`/`GIT_*` env vars still reach the CLI process (in-process tools unaffected) while the `credentials.envVars` census denies them to sandboxed commands — in-sandbox `gh`/`git push` therefore fail at auth, not network, and `GH_403_PROMPT_DIRECTIVE` keeps promising a retry that will not succeed. The mint is also functionally wasted for the entitled session (allowDomains widening is moot under the env-proxy chain). Left as-is in Phase A to keep the diff scoped; the credential broker (#9543) is the intended home of a coherent fix.
- **Revocation granularity**: the gateway's basic-auth helper caches per `credentialsttl` (pinned 30s); the binding revocation mechanism is the forwarder's death — token-file deletion bounds the residual window, it is not instant revocation. The toggle copy says "revokes live access on the session's next dispatch" — accurate for the warm-path re-resolve; a session whose host dispatcher dies AND restarts relies on the boot reaper before the first dispatch.
- **No in-session revocation notice (Phase A):** a mid-session toggle-off kills the forwarder but the running `Query`'s tool surface still advertises `WebFetch` — calls then fail at the refused listener. The prompt addendum tells the model to report rather than retry-loop; a client-visible frame (`egress_revoked`) needs a new WSMessage type + client renderer and is deferred — the session user may be a member while the toggler is the owner, so nobody is presently notified in-band.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `network.httpProxyPort` + `deniedDomains` emission | Measurement 3: `httpProxyPort` cannot carry the session token the forwarder requires; `deniedDomains` would be dead config on the chained path. |
| Flat `allowedDomains` widening | The SDK filter is not a boundary once a proxy chain exists (measurement 1); a flat allowlist gives no token scoping, no revocation, no per-session audit. |
| Per-request credential broker (Phase B mechanism) shipped in Phase A | Scope: Phase A's quarantine lands the safe half first; the broker is a separate deliverable (#9543). |
| Audit-log UI in Phase A | No queryable store ships yet; deferred to #9545 rather than shipping a dead link. |
| In-process `net.Server` forwarder per session | Reviewed (review design pass): an in-process listener would die with the dispatcher, removing the ppid watchdog, the `/proc` orphan sweep, the spawn handshake, and `EGRESS_FORWARDER_PATH` plumbing. Rejected for blast-radius isolation: the forwarder handles arbitrary client bytes for every concurrent session on one dispatcher, and a crash or memory-pinned handler inside the dispatcher takes every session's env-proxy path down with it (the SRT chain transits `api.anthropic.com` control-plane CONNECTs too — spec TR7 arm 3 — so a forwarder fault would stall the model call itself, not just WebFetch). The separate process also keeps the token-material write + the CONNECT piping off the dispatcher's event loop. The trade is recorded honestly: ~150 LOC of lifecycle machinery is the cost of that isolation, and the token-dir sweep in the reaper is needed under either shape (the dir is a shared host volume). |
