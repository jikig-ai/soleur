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

# ADR-278: Opt-in open-web egress via a dedicated CONNECT-only gateway and per-session forwarder

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

> **Pin moved 2026-11-04 (#12026):** the SDK pin is now `0.3.311` (CLI `2.1.311`, one shared binary). The measurements below were taken on 0.3.284 and are a dated record; they were not re-run for this ADR. The rewritten in-sandbox socat bridge (IPv6-first group, readiness watchdog) was re-exercised on 0.3.311 by the NO-EGRESS control arm in `sandbox-wrapped-command-runtime.test.ts` and by `broker-mechanism-spike.test.ts`, both passing under `C4_BWRAP_REQUIRED=1`.

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
- **Canary isolation:** only the prod and first-boot starts set `SOLEUR_EGRESS_REAPER=1` and mount the shared token dir; the deploy canary does neither. The mount omission is least privilege (the canary runs no egress sessions; the original design mounted it on the canary too, and a merge-conflict resolution (commit `35846d304f`, on the local-only `feat-open-web-egress` branch) later dropped every one of these lines from `ci-deploy.sh`, so this is a decision, not a restoration). The flag omission is correctness: a canary reaper would sweep tokens it did not mint, because its `/proc` cannot see the prod forwarders. `lib/docker-run-tuple.py` pins both halves of the start ARGV: the prod and first-boot starts must carry the mount and the flag, and the canary must carry neither. Env injected outside the argv (the Doppler `--env-file`, `EGRESS_TOKEN_DIR`) is a stated residual of that checker, not a pinned property.

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

> **See also ADR-311 (#9543, 2026-10-30):** the route back to credentialed push that Decision 5 names is now the cc approval wiring first (#11635, #11636), then the broker (#11637).

## Amendment — 2026-11-09 (#12469): entitled sessions lose all in-sandbox `gh`, reads included

This amendment extends Decision 5 and the Consequences above. It rewrites none of the earlier text, which is a dated record.

- **What Decision 5 means for `gh`.** The credential quarantine denies the GitHub auth variables to the sandbox of an entitled session with a live egress forwarder (the deny census is keyed on the live forwarder, `allowWebEgress = webEgress !== undefined`), so in-sandbox `gh` has no credentials for any operation. A granted session whose forwarder spawn degraded keeps a working `gh`. Reads are lost along with writes: `gh pr list`, `gh issue view` and `gh run list` fail at auth, not network. Decision 5 and the "Prompt coherence under the quarantine" scope note named push and `GH_403_PROMPT_DIRECTIVE`; this amendment names the read loss explicitly and records it as a consequence of the decision, not a defect in it.
- **Mitigation: server-side platform read tools.** The cc `soleur_platform` server registers six read-only tools for an entitled session: `github_list_pull_requests`, `github_read_pr`, `github_read_issue`, `github_read_issue_comments`, `github_list_pr_comments` and `github_read_ci_status`. They run in the dispatch process with the GitHub App installation token. The token never enters the sandbox, so Decision 5 is unchanged and the in-sandbox exfiltration channel stays closed. The repository is closed over server-side (the model never supplies owner, repo or installation).
- **Registered only for PUBLIC connected repositories (checked at registration).** The registrar verifies the connected repository is public with one bounded lookup; any error, timeout or missing field is treated as not public: it fails closed under its own reason, `visibility-unknown`, which tells the user the visibility could not be confirmed rather than that the repository is private. A workspace with a private repository keeps today's behaviour: no read tools. Private repositories widen the data co-resident with open egress and need their own ruling (#12471).
- **Named residuals left open by this change.** (i) Repository visibility is verified once, at cold registration, by one bounded `GET /repos/{owner}/{repo}`. The per-call revalidation compares repository identity (owner and repo) and the stored installation id only, not visibility, so a public-to-private flip during a live conversation keeps the tools serving until the next cold start (CTO ruling D2, named residual; private repositories are #12471). The statement above that the tools register only for public repositories is therefore a registration-time property, not a per-call one. (ii) Turning Agent web access off mid-conversation tears down the forwarder, but the read tools stay registered until the conversation ends; the change is effective for new conversations.
- **No new credential path.** No in-sandbox read token, no broker and no flag were added. The tools are gated by the same entitlement as the egress (the per-workspace toggle); kill switch is turning the toggle off, which takes effect for a new conversation (a running conversation keeps the tools until it ends, its forwarder having been torn down).
- **Disclosure.** The toggle copy now says that the command-line `gh` tool is unavailable while the toggle is on, that agents still read issues, pull requests and CI status of public repositories through Soleur, that they cannot create or edit them, and that private repositories cannot be read.
- **Consequence for the standing residual.** Third-party issue, PR, comment and CI text becomes agent input in a session with open egress. It is framed as untrusted content and field-capped; the egress gateway remains a chokepoint, not a content filter (Consequences above). The DPIA screening addendum of 2026-11-09 records the residual.
- **Scope.** Writes, workflow logs, read-tool refinements, private repositories and legacy redirect handling are deferred to #12467, #12468, #12470, #12471 and #12472. See the ADR-311 addendum of the same date.

## Addendum — 2026-11-10 (#12517): measurement 4 re-measured on Agent SDK 0.3.311

Measurement 4 above records that `NO_PROXY` is not honored by the SDK's API path. The egress injector spike (PR #12518; results note `knowledge-base/project/specs/archive/20261110-211546-feat-agent-runtime-sandbox-eval/injector-spike-results.md`, finding "The CLI's own traffic goes direct") measured the opposite on Agent SDK 0.3.311 with the exact `buildAgentEnv` output: with `api.anthropic.com` in `NO_PROXY`, the CLI's Messages API, settings and policy-limit calls reached the stub directly from the app container (read from the stub's peer address), never through the proxy. Measurement 4 stands as the record of the SDK it was taken on. For 0.3.311 the exemption is load-bearing, and the `agent-env.ts` comment that repeats measurement 4 is corrected under #11637 (ADR-325, Consequences). This addendum is not current for SDK 0.3.321 (#12553): that pin move fires the results note's re-measure trigger, which #11637 owns before adoption.
