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

# ADR-272: Opt-in open-web egress via a dedicated CONNECT-only gateway and per-session forwarder

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

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `network.httpProxyPort` + `deniedDomains` emission | Measurement 3: `httpProxyPort` cannot carry the session token the forwarder requires; `deniedDomains` would be dead config on the chained path. |
| Flat `allowedDomains` widening | The SDK filter is not a boundary once a proxy chain exists (measurement 1); a flat allowlist gives no token scoping, no revocation, no per-session audit. |
| Per-request credential broker (Phase B mechanism) shipped in Phase A | Scope: Phase A's quarantine lands the safe half first; the broker is a separate deliverable (#9543). |
| Audit-log UI in Phase A | No queryable store ships yet; deferred to #9545 rather than shipping a dead link. |
