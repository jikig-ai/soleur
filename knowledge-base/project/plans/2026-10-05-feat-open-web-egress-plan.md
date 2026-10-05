---
title: "feat: open-web egress for hosted agent sessions (per-workspace opt-in + egress gateway)"
type: feat
date: 2026-10-05
slug: feat-open-web-egress
branch: feat-open-web-egress
issue: 9534
closes: 9534
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domain: engineering
priority: p2
---

# feat: open-web egress for hosted agent sessions (#9534)

## Overview

Per-workspace opt-in open-web egress for hosted agent sessions, delivered
through a dedicated **egress-gateway sidecar** — a Squid CONNECT-only forward
proxy on a second docker bridge (`soleur-egress0`), reachable via a
per-dispatch in-container forwarder (`httpProxyPort` is localhost-only) plus
exactly one new `SOLEUR-EGRESS` accept rule. Sessions in opted-in workspaces
get `network.httpProxyPort` → forwarder → gateway, `credentials.envVars` deny
on every secret name, and `WebFetch`/`WebSearch` re-enabled per-session
(WebFetch gated on an HTTP_PROXY-honor verification). L1 container nftables,
L4 cron containment, and the default-drop posture for non-entitled sessions
are unchanged.

Two merge units, ordered by `wg-dark-launch-deploy-gates`:

- **PR-A (infra dark-launch):** gateway service + bridge + nftables rules +
  CONNECT decision logging, deployed **non-blocking** — nothing routes through
  it yet; the synthetic probe pair (allow+deny) exercises the real path.
- **PR-B (product wiring):** `workspaces.web_egress` grant + Scope Grants
  toggle + dispatch-time entitlement + sandbox config widening + tool re-scope.

Brainstorm: `knowledge-base/project/brainstorms/2026-10-05-open-web-egress-brainstorm.md`.
Spec: `knowledge-base/project/specs/feat-open-web-egress/spec.md`.
Wireframe (approved): `knowledge-base/product/design/settings/agent-web-access.pen`.

## Problem Statement

Hosted agent sessions cannot reach the web. Five layers compose to
zero-egress (verified 2026-10-05 on `main`):

| Layer | Enforcement | File |
|---|---|---|
| L1 | nftables `SOLEUR-EGRESS` off `DOCKER-USER`, default-drop, IP-only, whole-container | `apps/web-platform/infra/cron-egress-nftables.sh` |
| L2 | sandbox `network.allowedDomains` + `allowManagedDomainsOnly` | `apps/web-platform/server/agent-runner-sandbox-config.ts:365` |
| L3 | `CANONICAL_DISALLOWED_TOOLS = ["WebSearch","WebFetch"]` | `apps/web-platform/server/agent-runner-query-options.ts:56` |
| L4 | cron PreToolUse catch-all deny | `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` |
| L5 | fs/env-only sandbox hook | `apps/web-platform/server/sandbox-hook.ts` |

Flat-widening L1 is rejected: it un-contains the four `spawn("bash")` crons
ADR-052 exists for (the hook does not reach them) and has no per-session
granularity — forwarded packets are not session-attributable.

Demand signal is real but internal (#8467/#6088 — containment blocks
legitimate cron WebFetch; zero external complaints, 1 alpha tester). The
operator accepted open-web scope with that asymmetry stated.

## Proposed Solution

**Egress gateway (Squid, CONNECT-only) on a second docker bridge.** The
`iifname "docker0"` jump in `cron-egress-nftables.sh:210` scopes the entire
default-drop chain to docker0-originated packets. A container on the
`soleur-egress0` bridge escapes the chain for *outbound* (gw→internet packets
enter FORWARD with iifname soleur-egress0, no jump) while remaining reachable
from docker0 via one accept rule:

```
add rule ip filter SOLEUR-EGRESS ip daddr 172.31.100.2 tcp dport 8443 accept \
  comment "soleur-egress: egress gateway (Phase A)"
```

**Two-hop path — `httpProxyPort` is port-only.** SRT injects
`HTTP_PROXY=http://localhost:<httpProxyPort>` into the sandboxed child — it
cannot address a remote gateway directly (advisor consult; SRT hardcodes
`TCP:localhost:<port>`). **This assumption is the design's load-bearing joint
and gets a Phase-0 spike in PR-B** — run `query()` with `httpProxyPort` under
the pinned SDK and observe where the connection lands (Kieran: SRT's Linux
path removes the sandbox netns and bridges via bind-mounted unix sockets —
the child's `localhost` may not be the container's loopback).

An entitled dispatch spawns a **per-session in-container forwarder**
(~40 LOC): binds `127.0.0.1:0` (kernel-assigned port — no allocator state to
leak), TCP-tunnels to `172.31.100.2:8443`, and rewrites credentials both
ways: requires the per-session token inbound (allocated at spawn, injected
only into the entitled sandbox env), strips whatever SRT sent, and injects
`Proxy-Authorization: Basic <workspaceId>:<sessionToken>` outbound. It dies
with the dispatch (ppid watchdog + dispatcher-startup reaper for orphans);
warm-path re-resolve-false kills it → toggle-off revokes mid-session.

**Session tokens, not a shared secret** (replaces the earlier
`EGRESS_PROXY_SECRET` design — spec-flow found no writer-path and arch found
a /proc-harvest hole): dispatch mints a random token and writes it to a
host-side dir (`/var/lib/soleur/egress-tokens/<token>`) mounted rw into the
app container and ro into the gateway; the Squid auth helper validates that
`<password>` exists as a file → OK. No static credential exists anywhere;
harvested tokens are valid only for that session's lifetime; teardown or
revocation is `rm <file>` + kill the forwarder. `%un` still gives workspace
attribution via the username field.

**Squid owns all policy** (replaces the earlier bespoke-proxy call — bespoke
under-budgets the deny spec: v4-mapped-v6, NAT64 `64:ff9b::/96`, 6to4
`2002::/16`, octal/hex/short IP literals, zone IDs are all mandatory denies,
and Squid evaluates `dst` ACLs per-connection on *resolved* IPs):

- `http_access deny !CONNECT` + `deny CONNECT !SSL_ports` (443 only —
  Extended-CONNECT/MASQUE is never honored: Squid does not implement
  `:protocol` on CONNECT, so `connect-udp`/`connect-ip` cannot ride it)
- Deny set — ONE shared CIDR file (`infra/egress-deny-cidrs.txt`) consumed by
  BOTH layers (Squid via file-backed `acl egress_deny dst
  "/etc/squid/egress-deny-cidrs.txt"`; nftables via the resolver that renders
  the egress0 drop from the same file — parity test asserts the two renders
  carry identical CIDRs). Contents: `to_localhost` + `to_linklocal`
  builtin ACLs AND the file's explicit set — `169.254.0.0/16` (cloud-init
  user_data carries a Doppler read token), RFC1918 `10/8 172.16/12
  192.168/16`, CGNAT `100.64.0.0/10`, cluster-private `10.0.1.0/24`,
  `fc00::/7` ULA, `fe80::/10` link-local, `::/128`, `::ffff:0:0/96`
  v4-mapped, `64:ff9b::/96` NAT64, `2002::/16` 6to4 — plus `dns_v4_first on`
  (the nftables layer is `ip`-only). NOTE (Kieran): `to_localhost` covers
  only `127/8`/`::1`; `to_linklocal` covers 169.254+fe80; ULA needs the
  explicit CIDR.
- `proxy_auth REQUIRED` — auth helper validates the password as a
  session-token file under the bind-mounted token dir; username =
  `workspaceId` → `%un` gives per-workspace attribution from a
  container-wide source IP.
- DNS rebinding: Squid resolves the CONNECT target itself and `dst` is
  checked against resolved answers; whether a mixed public+private answer
  set is refused outright or the denied IP filtered-and-dialed is empirical
  — the fixture's expected value gets pinned after measuring the pinned
  image, not assumed.
- JSON `logformat` decision+close lines: `decision`, `decision_reason`,
  `requested_host`, `resolved_ip` (close-time `%<a` — rebinding forensics),
  `bytes`, `duration`, `%un` workspace. (The `enforce_would_deny` shadow
  field is cut — with zero real traffic in dark-launch it can never
  diverge; the synthetic probe pair carries the signal instead.)

**nftables layer — three rules, reply-path aware** (arch-strategist P0: the
forward leg works because the docker0-scoped jump hits our accept before
DOCKER-ISOLATION; but gw→docker0 SYN-ACKs arrive `iifname soleur-egress0
oifname docker0` and `DOCKER-ISOLATION-STAGE-2` drops them BEFORE the
established/related accepts — and an unscoped egress0→RFC1918 drop would eat
them anyway since docker0's `172.17.0.0/16` IS RFC1918):

1. `iifname "docker0" ip daddr 172.31.100.2 tcp dport 8443 accept` inside
   SOLEUR-EGRESS before the default-drop (the forward leg);
2. `iifname "soleur-egress0" oifname "docker0" ct state established,related
   accept` at DOCKER-USER level BEFORE inter-bridge isolation (the reply
   leg);
3. A new `SOLEUR-EGRESS-GW` chain jumped from DOCKER-USER on `iifname
   soleur-egress0` holding the gw-outbound deny — **`ct state new` scoped**
   (replies must pass) — rendered from the SAME `egress-deny-cidrs.txt` the
   squid.conf consumes. Chain placement note: this drop CANNOT live inside
   SOLEUR-EGRESS (egress0 packets never enter that iifname-scoped chain —
   dead code), and `cron-egress-resolve.sh`'s self-heal needle set must be
   extended or chain deletion goes unnoticed. `EnableIPv6` guard
   (`cron-egress-nftables.sh:43-46`) replicated for the new bridge.

**Per-session wiring (Phase A / PR-B):** `workspaces.web_egress` boolean +
SECURITY DEFINER RPC pair cloned from migration 101 (`debug_mode` template);
`resolveWebEgress` is a **pure read** in the dispatch `Promise.all` at
`cc-dispatcher.ts:1766` (active-workspace-keyed like `resolveBashAutonomous`;
RPC error → catch → `false` + Sentry — a Supabase blip must not reject every
dispatch). Forwarder spawn is a **separate post-read step**: mint token →
write token file → spawn forwarder (`bind 127.0.0.1:0`, read the port back)
→ on any spawn failure degrade `allowWebEgress`→false + Sentry rather than
emit a dead config. `buildAgentSandboxConfig` gains `allowWebEgress`
(derived, never independently threadable — ADR-051 precedent) emitting
`network.httpProxyPort=<boundPort>` + `credentials.envVars` deny census.
(`deniedDomains` emission is cut — under `httpProxyPort` the SDK ignores it;
dead config invites false confidence.) `HTTP_PROXY` injection for in-process
tools is **explicit and per-dispatch** (never ambient — `HTTP_PROXY` is on
`AGENT_ENV_ALLOWLIST` at `agent-env.ts:44`, so an ambient server value would
silently leak into every session). `CANONICAL_DISALLOWED_TOOLS` becomes
per-session: **WebFetch** removed only when entitlement is active AND the
Phase-0 verification passes; **WebSearch stays disallowed this PR** (it is
server-side, needs no egress, and coupling it to the grant is scope creep).

## Technical Approach

### Architecture

```
┌─ web host ─────────────────────────────────────────────────────────────┐
│ docker0 (soleur-web-platform: Next.js + crons + agent CLIs)            │
│   agent session (bwrap) ──CONNECT──▶ 127.0.0.1:<session-port>           │
│     per-dispatch forwarder (baked script; injects Proxy-Authorization)  │
│                      │                                                 │
│                      ▼ (L1 accept rule: docker0 → gw only)             │
│ soleur-egress0 bridge (172.31.100.0/24; -o com.docker.network.bridge    │
│   .name=soleur-egress0)                                                │
│   soleur-egress-gw container = Squid, CONNECT-only, auth+dst ACLs,     │
│     JSON decision/close log → journald → Vector                         │
│          │ (iifname soleur-egress0 → never hits SOLEUR-EGRESS; own      │
│          │  link-local/RFC1918 nft drop as defense-in-depth)            │
└──────────┼──────────────────────────────────────────────────────────────┘
           ▼ internet :443
```

**Gateway implementation: Squid** (distro image pinned by digest —
`ubuntu/squid@sha256:…` pulled from docker.io at bootstrap; ghcr is
sinkholed on web hosts per `web-ghcr-deny.test.sh`, zot holds only CI-built
platform images). Chosen over bespoke Node (~250 LOC under-budgets the real
deny spec — v4-mapped-v6, NAT64, 6to4, short/octal literals, zone IDs are all
mandatory), Smokescreen (no Go toolchain/image pipeline in repo), and
go-egress-proxy (pre-1.0, same Go problem). Squid's `dst` ACL evaluates
resolved IPs per connection, `to_localhost` covers loopback/ULA/link-local,
and `logformat` JSON covers the audit schema + shadow field.

**Load-bearing SDK facts (verified against `claude-agent-sdk@0.3.284` typings
+ docs + issue evidence):**

- `httpProxyPort` **replaces** the built-in domain enforcement entirely —
  `allowedDomains`/`allowManagedDomainsOnly`/`deniedDomains` and credential
  `mask` are bypassed when it is set (anthropics/claude-code#87296). Policy
  MUST live in the gateway.
- `credentials.envVars: {name, mode:"deny"}` unsets the var **for sandboxed
  commands only** — the CLI process keeps the value, in-process tools are
  unaffected. Denying `ANTHROPIC_API_KEY` therefore does not break model
  calls; denying `GH_TOKEN`/`GIT_*` breaks in-sandbox `git push` (intended in
  Phase A; Phase B restores via broker).
- **WebFetch is NOT sandbox-proxied** — in-process tools follow permission
  rules, not the sandbox proxy (#89762). For a web-entitled session, in-process
  WebFetch must honor `HTTP_PROXY` env → routes via the gateway → through the
  L1 accept rule. **Verification task in Phase B-1:** confirm the SDK's
  WebFetch honors `HTTP_PROXY`; if it does not, WebFetch stays disabled for
  web-entitled sessions in this PR (curl/Bash browsing still works) and the
  limitation is documented.
- `deniedDomains` merges from all sources and survives
  `allowManagedDomainsOnly` — but per #87296 assume bypassed under
  `httpProxyPort`; it is belt on top of the gateway's braces, not load-bearing.

**Env-deny census** (`credentials.envVars`, Phase A web-entitled sessions):
`GH_TOKEN`, `GIT_INSTALLATION_TOKEN`, `GIT_ASKPASS`, `GIT_USERNAME`,
`GIT_TERMINAL_PROMPT`, `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL`,
`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, plus every name in
`ALLOWED_SERVICE_ENV_VARS` (`server/providers.ts:10-24`: `OPENAI_API_KEY`,
`AWS_ACCESS_KEY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`, `CLOUDFLARE_API_TOKEN`,
`STRIPE_SECRET_KEY`, `PLAUSIBLE_API_KEY`, `HETZNER_API_TOKEN`, `GITHUB_TOKEN`,
`DOPPLER_TOKEN`, `RESEND_API_KEY`, `X_BEARER_TOKEN`, `LINKEDIN_ACCESS_TOKEN`,
`BLUESKY_APP_PASSWORD`, `BUTTONDOWN_API_KEY`). Two corrections from review:
(a) drop `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` from the deny set — they
are deliberate `/dev/null` neutralizations, not secrets (denying them undoes
the neutralization); (b) `ALLOWED_SERVICE_ENV_VARS` is module-private in
`agent-env.ts:74-76` — export it (or recompute from `PROVIDER_CONFIG`) and
dedupe the overlap (`ANTHROPIC_API_KEY`/`GITHUB_TOKEN` appear in both
sources). Credential **files** need `denyRead`, not envVars deny —
`GOOGLE_APPLICATION_CREDENTIALS` targets and the token-dir mount get added
to the entitled session's `denyRead` set.

**Persistence + dispatch:** `workspaces.web_egress` boolean column +
member-read RPC (NULL → fail-closed false) + owner-write RPC (P0001 for
non-owners) — clone migrations `097`/`101` verbatim shape. Route
`app/api/workspace/web-egress/route.ts` (validateOrigin + verifiedUserId,
clone of `bash-autonomous/route.ts`). `emitWorkspaceActionContext` audit on
every flip (`"scope-grant"` action, `server/workspace-action-audit.ts:13`).
Dispatch: `resolveWebEgress(userId)` in the `Promise.all` at
`cc-dispatcher.ts:1766-1809`; entitlement re-resolves on the warm path
(:3486 precedent). Toggle UI: clone `bash-autonomous-toggle.tsx` onto the
Scope Grants page per the approved wireframe (off / inline confirm / on).

**Non-goal (Phase B, #9543):** credential broker — per-request token
injection for pinned hosts so credentialed sessions can browse AND push.
SDK has no per-host injection primitive; the forwarder port is the seam.

### Implementation Phases

#### PR-A: Gateway infra dark-launch (non-blocking)

1. `apps/web-platform/infra/egress-gateway-squid.conf` — Squid policy:
   CONNECT-only, `SSL_ports 443`, `to_localhost` + `to_linklocal` + file-
   backed `dst` deny (`egress-deny-cidrs.txt`: RFC1918/CGNAT/cluster-
   private/ULA/NAT64/6to4/v4-mapped), `proxy_auth REQUIRED` + baked auth
   helper (`egress-auth-helper.sh` — password = session-token file exists
   under the ro-mounted token dir, username = workspaceId), `dns_v4_first`,
   JSON `logformat` (decision+close).
2. `apps/web-platform/infra/egress-forwarder.mjs` — the per-dispatch
   in-container forwarder (~40 LOC: bind `127.0.0.1:0` read back, tunnel to
   172.31.100.2:8443, require the session token inbound / inject
   `workspaceId:token` outbound). Spawned/killed by the dispatch layer,
   bound to session lifetime; rides the image build, NOT the bake chain.
3. `apps/web-platform/infra/egress-gateway-bootstrap.sh` — probe/reserve the
   bridge subnet (default `172.31.100.0/24`, collision-checked against
   existing `docker network` allocations) +
   `docker network create --subnet=… -o
   com.docker.network.bridge.name=soleur-egress0 soleur-egress0` (idempotent)
   + `mkdir -p /var/lib/soleur/egress-tokens` + `docker run -d --name
   soleur-egress-gw --network soleur-egress0 --ip 172.31.100.2 --log-driver
   journald --restart unless-stopped -v …/egress-gateway-squid.conf:… -v
   /var/lib/soleur/egress-tokens:/etc/squid/session-tokens:ro
   ubuntu/squid@sha256:<pinned>` — digest-pinned docker.io pull (ghcr
   sinkholed; zot is CI-images only). **Digest-freshness triptych** cloned
   from zot (`zot-registry.tf:59-68` precedent): `egress-image.provenance.md`
   bump procedure, upstream-poll step in `rule-audit.yml` (1st/15th,
   idempotent issue), `egress-image-staleness.test.sh` — a stale pin on the
   policy engine is an unpatched CVE in the security control itself.
4. `cron-egress-nftables.sh` + `cron-egress-resolve.sh` — THREE rules (see
   Proposed Solution: forward accept; DOCKER-USER `established,related`
   reply accept ordered before inter-bridge isolation; new `SOLEUR-EGRESS-GW`
   chain with `ct state new`-scoped outbound deny rendered from
   `egress-deny-cidrs.txt`) + resolver self-heal needle set extended to cover
   the new chain and the reply rule + `EnableIPv6` guard replication.
5. `infra/egress-deny-cidrs.txt` — the single deny-set source for both the
   squid ACL and the nftables render (removes the two-table drift class;
   parity test asserts identical CIDR sets on both surfaces).
6. cloud-init slot: one `runcmd` line invoking the bootstrap BEFORE the app
   `docker run` (`:785`) and before `cron-egress-enforce-probe.sh` (`:807`);
   the app `docker run` also gains `-v /var/lib/soleur/egress-tokens:
   /var/lib/soleur/egress-tokens` (rw — the token writer path). cloud-init.yml
   byte-cap headroom is ~300 B — everything else lives in the baked file set.
7. **Bake chain (all four surfaces, terraform-architect finding):** add the
   new files to `local.host_script_files` (`server.tf:173`), the Dockerfile
   COPY set (`Dockerfile:251-310`), `.dockerignore` `!infra/<file>`
   re-includes, and `soleur-host-bootstrap.sh` install loops+assertions
   (:75-109, :174-199). The forwarder script (`egress-forwarder.mjs`) does
   NOT need this chain — it executes inside the app container and rides the
   normal image build (CTO). Skipping any baked surface reds
   `cloud-init-user-data-size.test.ts` / `web-host-provisioner-parity.test.sh`
   or fail-closed-poweroffs fresh hosts.
8. `terraform_data` SSH block for running web-1 — shape = the
   `cron_egress_firewall` sibling (`server.tf:2508-2525`):
   `triggers_replace = { config_hash = sha256(join(",", [file(…)])),
   server_id = hcloud_server.web["web-1"].id }`, `host_key =
   local.web_1_ssh_host_key`, literal `destination=` paths, post-assertion.
   NOT the `journald_persistent` shape (file-hash only — misses
   replaced-VM delivery). The web-1 block ALSO creates the token dir and
   re-runs the app `docker run` so the rw mount lands there (cloud-init is
   frozen on web-1).
9. `-target` allowlist: the new `terraform_data` joins the post-bridge SSH
   stage in `apply-web-platform-infra.yml:1181-1200` (asserted by
   `terraform-target-parity.test.ts:257-260`). The `cron-egress-nftables.sh`
   rule change rides the EXISTING `terraform_data.cron_egress_firewall`
   (already hashes that file).
10. Vector: new `[sources.egress_gw_journald]` `CONTAINER_NAME` match AND add
    it to `transforms.pii_scrub_drop_userdata` `inputs` (`vector.toml:377`) —
    a source alone never reaches `sinks.betterstack` (:589). web-1 delivery
    is free via `journald_persistent` hashing (`server.tf:1313`).
11. Probe + alerts: extend `cron-egress-enforce-probe.sh` (the existing cron
    that already probes L1) with a synthetic CONNECT pair through the
    gateway — one public-443 allow, one denied class — emitting a heartbeat
    line per run. This gives the dark-launch its real signal (zero real
    traffic otherwise makes "observed healthy" unfalsifiable) AND is the
    heartbeat emitter. Alerts: deny-class spike + heartbeat absence →
    Better Stack `logtail_exploration_alert` (betterstack-logs-alerts.tf
    checklist: `escalation_target` ternary on `var.betterstack_paid_tier`,
    two `-target` lines, drift guard + `infra-validation.yml` registration,
    runbook row).
12. Tests: `cron-egress-firewall.test.sh` fixtures (accept-rule order, reply
    `established,related` before isolation, `ct state new` scope on the gw
    chain, one-way invariant — new gw→docker0 connections still dropped);
    `egress-gateway.test.sh` (Guard 1 matrix — squid.conf + auth helper +
    token lifecycle); `egress-deny-cidrs` parity test;
    `web-host-provisioner-parity` baked-set parity;
    `cloud-init-user-data-size.test.ts`; `terraform-target-parity.test.ts`
    update. The selftest (`scripts/probes/egress-gateway-policy.sh`) invokes
    the same fixtures — no second fixture set.

#### PR-B: Product wiring (entitlement → session)

0. **Phase-0 spike (gate before all PR-B work):** run `query()` with
   `network.httpProxyPort` under the pinned `claude-agent-sdk@0.3.284` and
   observe where the connection lands (SRT's Linux path removes the sandbox
   netns and unix-socket-bridges — "localhost" semantics must be measured,
   not assumed). Simultaneously verify whether in-process WebFetch honors
   `HTTP_PROXY`. Both outcomes shape task 4; a negative on the proxy-port
   assumption re-scopes the forwarder design before any wiring is built.
1. Migration `1XX_workspace_web_egress.sql` (+ `.down.sql` sibling — both
   097/101 ship one) — column + read/write RPC pair
   (clone `101_workspace_debug_mode.sql`); carry
   `-- LAWFUL_BASIS: consent (Art. 6(1)(a)) — owner opt-in via Scope Grants;
   withdrawal = toggle off` (gdpr-gate Art. 6 finding).
2. `server/resolve-web-egress.ts` + `server/set-web-egress.ts` (clones of the
   bash-autonomous pair — fail-closed, Sentry-mirrored, owner-denied 403).
3. `app/api/workspace/web-egress/route.ts` + `WebEgressToggle` client
   component on the Scope Grants page (clone `bash-autonomous-toggle.tsx`;
   wireframe copy verbatim, plus: member locked/read-only state cloned from
   the sibling's treatment — wireframe covers owner states only; on-state
   sub-line "Applies to sessions started after enabling; turning off revokes
   live web access" since in-sandbox env-deny applies next-dispatch while
   the forwarder kill is immediate; tighten the credential copy to "…in
   sandboxed commands" (the CLI process retains env by design — the sentence
   is the boundary claim, CMO P2); verify the confirm CTA's gold-gradient
   against the anti-slop scan + sibling destructive-confirm styling).
   The "View egress audit log" affordance is **deferred** — the wireframe
   keeps it as future-state (there is no queryable store in Phase A; a
   follow-up issue tracks the audit view).
4. `cc-dispatcher.ts` + `agent-runner-query-options.ts`: `resolveWebEgress`
   (pure read) in the dispatch `Promise.all`; post-read token mint + token-
   file write + forwarder spawn (bind `127.0.0.1:0`, read back; spawn
   failure → `allowWebEgress=false` + Sentry); `allowWebEgress` derived flag
   → `buildAgentSandboxConfig` (adds `httpProxyPort`, `credentials.envVars`
   census deny, `denyRead` additions for credential files + the token-dir
   mount); conditional removal of `WebFetch` from
   `CANONICAL_DISALLOWED_TOOLS` for entitled+verified sessions only
   (WebSearch stays disallowed — server-side, decoupled); forwarder teardown
   on session end AND on warm-path re-resolve-false (mid-session revoke);
   dispatcher-startup reaper for orphaned forwarders.
5. Entitlement decision logged per dispatch (`agent-sandbox` structured log
   shape, `webEgress: true|false` + forwarder port/PID fields); forwarder
   exit → Sentry event.
6. Legal pack (CLO-required before merge): Art. 30 PA-2(d) amendment + DPIA
   screening; privacy-policy/DPD/Eleventy mirror updates + `LEGAL_DOC_SHAS`
   repin; DPA Schedule 4 TOM entry; AUP hosted-egress abuse clause.
7. Deferral tracking (already filed): Phase B credential broker = **#9543**,
   workspace-visible audit view = **#9545**, both `blocked-by #9534`. PR-B's
   merge does not wait on them but must not regress their premises.
8. ADR (this PR — `wg-architecture-decision-is-a-plan-deliverable`): records
   the PR-#871 zero-egress reversal scope (opted-in sessions only), the
   gateway-vs-flat-open decision, `httpProxyPort`-replaces-enforcement
   caveat, token-file auth model + same-UID /proc residual, Phase A
   credential-deny bound + Phase B broker direction (forwarder port is the
   integration seam — CONNECT-passthrough forecloses transparent header
   injection, so the broker must be a credential-*vending* localhost
   endpoint slotting into the same forwarder shape), SNI-vs-CONNECT
   domain-fronting residual, squid resolve-cache TTL window.
9. C4: enumerate external actors/systems/access-relationships against
   `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` —
   new element: arbitrary external hosts as egress destination + the gateway
   as a new boundary component.

## Hypotheses

(Network-outage checklist fires — feature touches firewall + Terraform.)

1. **L3 — firewall rule correctness.** The new `docker0 → 172.31.100.2:8443`
   accept must land BEFORE the `egress-blocked` log+drop in
   `SOLEUR-EGRESS`; and gw→internet packets must be confirmed to arrive with
   `iifname br-soleur-egress0` (escaping the jump). Verification:
   `nft list chain ip filter SOLEUR-EGRESS` ordering + a positive/negative
   probe pair through the gateway (curl via `HTTPS_PROXY` to an allowed host
   and a denied one) — scripted probe mirroring `cron-egress-enforce-probe.sh`.
   [to verify at impl]
2. **L3 — DNS.** Gateway resolves targets host-side (container has its own
   resolver view); resolve-check-pin must reject when ANY answer is private.
   [to verify at impl]
3. **L7 — TLS/CONNECT.** Proxy is CONNECT-passthrough (no TLS termination);
   SNI-vs-CONNECT mismatch = documented accepted residual (domain fronting on
   shared CDNs — kern precedent). [design decision, not a defect]
4. **L7 — service layer.** Gateway decision+close logs discriminating
   `deny_private` / `deny_port` / `deny_literal` / `allow` / `upstream_error`
   in one event (blind-surface rule — in-surface probe). [to verify at impl]

## User-Brand Impact

- **If this lands broken, the user experiences:** an opted-in agent session
  loses all web access mid-task (fails closed — proxy unreachable = today's
  posture, not silent corruption), OR worse: the toggle silently does nothing
  while the UI claims browsing works.
- **If this leaks, the user's data is exposed via:** a prompt-injected agent
  session POSTing workspace contents to an arbitrary host; Phase A bounds this
  to workspace content only (no readable secrets in-sandbox). Phase B restores
  the credential question behind per-request injection.
- **Brand-survival threshold:** `single-user incident`.
- **Threshold decision (challengeable):** one prompt-injected exfil of a
  solo-founder's repo is a company-ending event for that user — CPO's framing;
  operator accepted open scope with the credential-deny bound in place.
- **CPO sign-off:** `requires_cpo_signoff: true`. CPO reviewed the brainstorm
  and recommended the narrower curated-pack / `web_fetch`-tool scope; the
  operator chose open-web opt-in with eyes open — recorded as a decision
  challenge in the brainstorm's Open Questions (demand proof unresolved).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Flat L1 wildcard (`allowedDomains: ["*"]` + nftables open) | Un-contains spawn-bash crons (ADR-052's raison d'être); no per-session granularity; kills `egress-blocked` signal semantics |
| Per-workspace extendable allowlist (CLO-preferred) | Preserves GDPR recipient enumeration but does not deliver browsing; resurfaces if demand proves narrower |
| Governed `web_fetch` MCP tool (CPO variant) | No installs/clones/arbitrary APIs; doesn't meet the ask. Noted as cheap fallback if open egress stalls |
| Bespoke Node CONNECT proxy (~250 LOC) | Under-budgets the mandatory deny spec (v4-mapped-v6, NAT64 `64:ff9b::/96`, 6to4, octal/hex/short literals, zone IDs) — advisor consult flipped this to Squid, whose `dst` ACLs evaluate resolved IPs natively |
| Smokescreen / go-egress-proxy binary | No Go toolchain or image-build pipeline in repo; would need a new build lane |
| Host-gateway systemd proxy at 172.17.0.1 (Inngest :8288 precedent) | Less infra (no bridge/container) but runs code on the host — a compromised proxy on-host is strictly worse than in a container; second-bridge wins on isolation |
| WebSearch-only interim | ~zero egress change (server-side via api.anthropic.com); parked as demand-validation option in Open Questions |

## Observability

```yaml
liveness_signal:
  what: "cron-egress-enforce-probe.sh synthetic CONNECT pair (allow+deny) through the gateway — the probe IS the heartbeat emitter"
  cadence: "probe cron interval (existing enforcement probe cadence); decision line per CONNECT"
  alert_target: "Better Stack logtail_exploration_alert (deny-class spike + heartbeat absence)"
  configured_in: "egress-gateway-squid.conf (log schema), cron-egress-enforce-probe.sh (probe), vector.toml (source+transform), infra/betterstack-logs-alerts.tf (alerts)"

error_reporting:
  destination: "Better Stack (journald→Vector→sink); Sentry only for app-side entitlement drift (feature=agent-sandbox)"
  fail_loud: "deny_* decision lines + heartbeat absence alert to operator; gateway-down = session egress fails closed"

failure_modes:
  - mode: "gateway container dead/unreachable"
    detection: "Squid heartbeat line absent → logtail_exploration_alert (paid-tier ternary per betterstack-logs-alerts.tf checklist); entitled session's forwarder gets connection-refused → in-session transport error surfaces to the user"
    alert_route: "Better Stack escalation → operator"
  - mode: "policy bypass (SSRF/rebinding/private-range reach)"
    detection: "egress-gateway.test.sh mutation matrix + runtime TCP_DENIED log lines carrying resolved_ip (%<a) for rebinding forensics"
    alert_route: "Better Stack log alert (deny classes logged at allow-verbosity, Squid TCP_DENIED precedent)"
  - mode: "auth bypass / unattributed CONNECT (confused deputy)"
    detection: "any decision line with empty %un or auth failure → TCP_DENIED/407 class alert; test asserts no-auth CONNECT is refused"
    alert_route: "Better Stack log alert"
  - mode: "entitlement drift (grant on but sandbox not widened / off but widened)"
    detection: "per-dispatch agent-sandbox structured log carries webEgress field + httpProxyPort presence + forwarder PID; mismatch = Sentry event"
    alert_route: "Sentry feature:agent-sandbox"
  - mode: "in-process WebFetch bypasses proxy env (SDK)"
    detection: "Phase B-1 verification task pins behavior; if unproven, WebFetch stays disabled for entitled sessions (documented)"
    alert_route: "fails closed — L1 default-drop catches the dial"
  - mode: "policy-ALLOWED abuse (scraping, C2 to public hosts, bulk fetch) — deny-class alerts never see it"
    detection: "per-workspace CONNECT volume/rate anomaly on the gw decision log (Better Stack exploration alert); AUP clause defines the suspension trigger"
    alert_route: "Better Stack escalation → operator; AUP suspension path"

logs:
  where: "journald (container log-driver) → Vector CONTAINER_NAME=soleur-egress-gw → Better Stack; decision+close JSON lines"
  retention: "same window as the existing Vector→Better Stack pipeline (30d); named in the Art. 30 entry (gdpr-gate DL finding) — CONNECT targets are user-adjacent metadata"

discoverability_test:
  command: "bash scripts/probes/egress-gateway-policy.sh --selftest"
  expected_output: "egress-gw-selftest-ok"
```

(The selftest script is committed in PR-A and exercises the proxy's policy
table against fixture CONNECT requests locally — first token `bash` is on the
preflight Check 10 allowlist; runs in <15 s with no network.)

## Encryption Posture

```yaml
at_rest:
  - store: "egress CONNECT decision/close logs (journald → Better Stack)"
    mechanism: "provider-managed:Better Stack encryption at rest"
    evidence: "Better Stack security docs (retrieved 2026-10-05); journald host disk covered by LUKS posture (ADR-119 workspaces volume; host root per provider)"
    defends_against: "at-rest read of audit rows off-host"
    does_not_defend: "live host compromise reading journald; Better Stack account compromise"
    disclosed_as: "docs/legal/privacy-policy.md TOM list (update in legal pack)"
    live_verification: "available: query Better Stack for decision lines post-deploy"
in_transit:
  - connection: "app container → egress gateway (CONNECT handshake)"
    enforced_at: "apps/web-platform/infra/cron-egress-nftables.sh accept rule + egress-gateway.mjs"
    tls: "none — plaintext CONNECT request line on private bridge; tunneled payload is end-to-end TLS to destination (proxy is passthrough, no MITM)"
    cert_verification: "n/a for the handshake; end-to-end TLS verification is the agent's own TLS stack (unmodified)"
    does_not_defend: "a same-bridge observer reads CONNECT targets (hostname+port metadata, not payload)"
    disclosed_as: "not-publicly-claimed"
  - connection: "egress gateway → arbitrary internet host"
    enforced_at: "egress-gateway.mjs CONNECT handler (passthrough)"
    tls: "TLS 1.2+ end-to-end (agent↔destination; proxy sees CONNECT metadata only)"
    cert_verification: "on (agent-side, unmodified)"
    does_not_defend: "SNI/CONNECT-authority mismatch (domain fronting — accepted residual, ADR task 7)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "CONNECT handshake metadata on a private docker bridge is host-internal control-plane traffic; payload TLS is untouched end-to-end"
  tracking_issue: "#9534"
  reevaluate_when: "if tlsTerminate (SDK experimental) or MITM policy is adopted, or if the bridge topology changes to shared"
  expires_on: "2027-01-03"
```

## Guard Contract

### Guard 1 — Gateway SSRF/deny policy

**Property.** No CONNECT to a private, link-local, loopback, CGNAT,
cluster-private, or IP-literal target — and no CONNECT without a valid
`Proxy-Authorization` — enforced at the gateway, including post-resolution.

**Assembly.** Three chokepoints, all must flow: (a) `squid.conf` `dst` +
`to_localhost` deny ACLs evaluated per-connection on resolved IPs; (b) the
`iifname "soleur-egress0"` nftables drop as defense-in-depth for the gw's own
outbound; (c) `proxy_auth REQUIRED` + auth helper — every CONNECT carries a
workspace-attributed credential. The forwarder is NOT a policy chokepoint —
it only injects auth; a sandboxed process skipping it still hits (a) and (c).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `169.254.0.0/16` from the `dst` deny table | RED — metadata-CONNECT fixture must TCP_DENIED |
| 2 | Drop `proxy_auth REQUIRED` (unauthenticated CONNECT reaches internet) | RED — no-auth fixture must get 407/deny |
| 3 | Guard's own dispatch: `--selftest` runs with empty ACL/0 fixtures | RED — selftest asserts ≥N deny ACLs + ≥N fixture decisions |
| 4 | Second member after compliant first: remove `10.0.1.0/24` while 169.254 stays | RED — Inngest-IP CONNECT fixture must deny |
| 5 | Harness: flip a fixture's expected decision (deny→allow) | RED — suite pins decisions, not exit codes |
| 6 | IP-literal CONNECT (`CONNECT 169.254.169.254:443`) — literal dst path | RED — literal-deny fixture |
| 7 | `iifname soleur-egress0` nftables drop deleted while squid.conf intact | RED — defense-in-depth fixture asserts both layers deny |
| 8 | Must-PASS: `CONNECT registry.npmjs.org:443` + valid credential | PASS — normal browsing still works |

### Guard 2 — Entitlement derivation (no half-wired state)

**Property.** `allowWebEgress` is true iff `resolveWebEgress` returned true
for this workspace — the flag is derived, never independently threadable
(ADR-051 pattern); a non-owner RPC write raises P0001; and the forwarder
(with its injected credential) exists only inside an entitled dispatch's
lifetime.

**Assembly.** Chokepoints: `cc-dispatcher.ts` dispatch `Promise.all` (entitlement
read + forwarder-port allocation) → forwarder spawn/kill bound to session
lifecycle → `agent-runner-query-options.ts` (flag derivation) →
`buildAgentSandboxConfig` (config emission). API write path:
`app/api/workspace/web-egress/route.ts` → owner-write RPC. `HTTP_PROXY` env
injection is per-dispatch only (never ambient — `AGENT_ENV_ALLOWLIST`
already passes `HTTP_PROXY` through, so the set must be explicit).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `allowWebEgress` accepts a raw boolean arg (independently threadable) | RED — type/test asserts derivation from resolver output |
| 2 | Entitlement read resolves `true` on RPC NULL (fail-open) | RED — NULL→false fixture |
| 3 | Non-owner POST to the route succeeds | RED — P0001→403 fixture |
| 4 | WebFetch removed from disallowedTools while `allowWebEgress=false` | RED — entitled-only fixture |
| 5 | Guard's own dispatch: `resolveWebEgress` absent from the Promise.all | RED — dispatch-shape test asserts the call |
| 6 | Forwarder outlives the dispatch (listener persists post-session) | RED — lifecycle assertion: port refuses after teardown |
| 7 | `HTTP_PROXY` set via ambient server env instead of per-dispatch | RED — test asserts env injection originates in dispatch arg, not process env |

### Guard 3 — Env-deny census completeness

**Property.** Every secret-bearing env name passed to a session is denied
inside the sandbox of a web-entitled session — the deny list is derived from
`ALLOWED_SERVICE_ENV_VARS` + the fixed token names, never hand-copied.

**Assembly.** Chokepoint: the deny-list builder in
`agent-runner-sandbox-config.ts` reads `ALLOWED_SERVICE_ENV_VARS`
(`server/providers.ts`) + a fixed literal set (git/anthropic names). Drift
pin: adding a provider to `PROVIDER_CONFIG` must auto-extend the deny set —
asserted by a test that computes expected = `ALLOWED_SERVICE_ENV_VARS` ∪ fixed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a new `PROVIDER_CONFIG.envVar` without touching the deny list | RED — derived-census test fails (list must equal computed set) |
| 2 | Remove `GH_TOKEN` from the fixed literal set | RED — fixture asserting GH_TOKEN denied |
| 3 | Guard's own dispatch: deny list emitted as `[]` when entitlement on | RED — zero-coverage assertion |
| 4 | Must-PASS: entitled session env contains all real vars at CLI level (deny is sandbox-scoped only) | PASS — CLI process unaffected |

### Guard 4 — nftables single-accept invariant

**Property.** L1 admits exactly `docker0 → 172.31.100.2:8443` beyond the
existing allowlist — no wildcard rule, no second bridge opening into the
chain.

**Assembly.** `cron-egress-nftables.sh` rule list + the resolver's per-tick
re-assert (`cron-egress-resolve.sh`) — the rule must survive the self-heal
re-assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Accept rule widened to `tcp dport 1-65535` | RED — fixture asserts exact dport |
| 2 | Rule placed AFTER the `egress-blocked` drop | RED — ordering assertion in cron-egress-firewall.test.sh |
| 3 | Guard's own dispatch: rule comment token absent → test greps for ruleset that lacks it | RED — presence pin |
| 4 | Resolver re-assert drops the rule on next tick | RED — postapply-assert fixture replays a tick |

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — `local.host_script_files` entries for
  the four new infra files; new `terraform_data` SSH provisioner for web-1
  (`config_hash + server_id` triggers per `server.tf:2508` sibling).
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — two
  `logtail_exploration_alert` resources (deny-class spike, heartbeat absence)
  gated on `var.betterstack_paid_tier` ternary.
- `apps/web-platform/infra/vector.toml` — new journald source + transform
  `inputs` wiring (delivered to web-1 via existing `journald_persistent`
  file-hash triggers).
- `apps/web-platform/infra/cloud-init.yml` — one `runcmd` line (byte-budget
  conscious; ~300 B headroom).
- No new secret inputs — the review-driven redesign replaced
  `EGRESS_PROXY_SECRET` with per-session token files under
  `/var/lib/soleur/egress-tokens` (no static credential exists anywhere;
  nothing reaches tfstate).

### Apply path

(b) cloud-init + idempotent bootstrap script: fresh hosts get the gateway via
the baked script + runcmd; running web-1 via `terraform_data` SSH
(`ignore_changes=[user_data]` means cloud-init edits cannot reach it).
Expected blast-radius: additive-only — a failed gateway never blocks existing
traffic (no session routes through it until PR-B).

### Distinctness / drift safeguards

- `dev != prd`: gateway + token dir exist in both; tokens are per-session
  files, no shared secret to diverge.
- `-target` allowlist: new `terraform_data` + `logtail_exploration_alert`s
  join the post-bridge stage (`apply-web-platform-infra.yml:1181-1200`);
  `terraform-target-parity.test.ts` updated in the same diff.
- No `for_each` over `var.web_hosts` on the provisioner — literal web-1 only
  (web-2 is a standby outside the routine `-target` set; the #5933-class
  transitive-create trap is avoided by not iterating that map).

### Vendor-tier reality check

`logtail_exploration_alert` requires Better Stack paid tier —
`escalation_target` ternary on `var.betterstack_paid_tier` per
`betterstack-logs-alerts.tf:165-168` convention.

## Architecture Decision (ADR/C4)

### ADR

Deliverable of this PR (`wg-architecture-decision-is-a-plan-deliverable`):
new ADR recording (a) the PR-#871 zero-egress posture reversal scoped to
opted-in sessions, (b) gateway-on-second-bridge vs flat L1 open (why the
`iifname` scope is the lever), (c) `httpProxyPort`-replaces-enforcement →
gateway owns all policy, (d) forwarder + `Proxy-Authorization` confused-
deputy boundary, (e) Phase A credential-deny bound and Phase B broker plan,
(f) accepted residuals: SNI-vs-CONNECT domain fronting, squid resolve-cache
TTL rebinding window, shared egress IP reputation. The ADR write includes a
sweep of `knowledge-base/legal/` for future-tense claims about the egress
boundary being flipped (the #9094-class status-flip sweep).

### C4 views

Enumerate against `knowledge-base/engineering/architecture/diagrams/
{model,views,spec}.c4`: new component `soleur-egress-gw` (boundary crossing
to external systems = arbitrary HTTPS hosts — a new external-actor class);
new relationship app-container→gw→internet; the forwarder is in-process
detail, below C4 granularity. ADR-052's existing edges unchanged.

### Sequencing

ADR ships `status: adopting` with PR-A's dark-launch; flips `accepted` when
PR-B lands and the first entitled session completes a verified CONNECT.

## Domain Review

**Domains relevant:** Engineering, Legal, Product, Marketing

### Engineering

**Status:** reviewed (brainstorm carry-forward, CTO)

**Assessment:** Three of five gates must change; flat L1-widening rejected.
Gateway sidecar on second bridge + SDK `credentials` masking +
entitlement-derived flag is the recommended shape; complexity medium-large;
ADR required. See brainstorm `## Domain Assessments`.

### Legal

**Status:** reviewed (brainstorm carry-forward, CLO)

**Assessment:** Open egress breaks the Art. 30 closed recipient enumeration —
user-directed fetches defensible as controller instruction, injected
exfiltration is not. Legal pack is a merge blocker (Phase B-6).
`soleur:gdpr-gate` runs against this plan (Phase 2.7).

### Product

**Status:** reviewed (brainstorm carry-forward, CPO)

**Assessment:** Demand unproven at user scale; recommended curated capability
packs or governed `web_fetch` tool. Operator chose open-web opt-in — dissent
recorded in Open Questions (demand proof) and CPO sign-off note above.

### Product/UX Gate

**Tier:** blocking (UI surface: settings toggle)
**Decision:** reviewed — wireframe approved by operator 2026-10-05
**Agents invoked:** soleur:product:design:ux-design-lead (headless `pen` CLI path)
**Skipped specialists:** soleur:marketing:copywriter (toggle copy is verbatim
from the approved wireframe — no marketing copy)
**Pencil available:** yes (headless CLI)

#### Findings

Wireframe: `knowledge-base/product/design/settings/agent-web-access.pen` +
`screenshots/06-agent-web-access-states.png` — three states on the existing
Scope Grants surface, inline-confirm pattern matching `bash-autonomous-toggle`,
persistent risk callout, audit-log affordance. Owner-only gating assumed
(matches sibling toggles' `isOwner`).

### Marketing

**Status:** reviewed (brainstorm carry-forward, CMO)

**Assessment:** Table stakes, not a differentiator — market the boundary
control; opt-in is non-negotiable vs default-on. A published piece argued
against server-side browsing (marked stale) — frame carefully.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "egress domains in Soleur WebApp might be limiting for users if our agents need to browse the web" [brief] | PR-A gateway + PR-B entitlement wiring (FR1–FR4) | mapped |
| 2 | "open it up fully … what would be the security risks and how could we address them" [brief] | HTTPS-only scope decision + risk table + Guard Contract + Phase A credential deny | mapped |
| 3 | "HTTPS-only open web" [dialogue] | CONNECT :443-only proxy; non-HTTP stays dropped | mapped |
| 4 | "Opt-in + cred broker" [dialogue] | Phase A envVars deny now; broker = Phase B follow-up (Non-Goal in spec) | mapped — Phase B descoped to separate issue |
| 5 | "Two-phase: uncredentialed first" [dialogue] | PR-B Phase A denies all token names; entitled+open waits for broker | mapped |
| 6 | "Per-workspace setting" [dialogue] | `workspaces.web_egress` + Scope Grants toggle (FR1) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Egress-gateway sidecar (PR-A) | "open it up fully and what would be the security risks and how could we address them" | inferred — justification: per-session egress requires a domain-aware path that escapes the docker0-scoped L1; a second-bridge proxy is the only shape preserving the cron containment ADR-052 requires |
| Legal pack (PR-B task 6) | "what would be the security risks" | inferred — justification: CLO's Art. 30 recipient-enumeration finding makes doc amendments a merge precondition, not optional hygiene |
| ADR + C4 (PR-B tasks 7-8) | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; reverses the #871 zero-egress posture, a recorded architectural decision |
| Vector/Sentry wiring | — | inferred — justification: `hr-observability-as-plan-quality-gate`; open egress without CONNECT logging is blind (research: observability parity is launch-gating) |
| Dark-launch split PR-A/PR-B | — | inferred — justification: `wg-dark-launch-deploy-gates`; a new egress-gating component must run non-blocking on real traffic before sessions route through it |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform` (server+app+infra+migrations),
  `.github/workflows`, `knowledge-base`/`docs/legal`
- Planned files: ~24 | Estimated changed lines: ~1400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **split** — PR-A (infra: gateway + bridge + nftables +
  logging, inert/dark-launch) then PR-B (entitlement + toggle + sandbox +
  tools + legal + ADR). PR-A ships and observes before PR-B gates on it.

## Open Code-Review Overlap

9 open `code-review` issues mention planned files — all name-mentions, no real
scope collision. Dispositions: #3243 (decompose cc-dispatcher) — **acknowledge**
(the plan adds ~20 lines to the Promise.all; the decomposition is a separate
large refactor, not folded). #3242/#3820/#4254 (cc-dispatcher) — **acknowledge**,
unrelated concerns. #2197/#3216 (server.tf), #3053/#8487/#8920 (cloud-init) —
**acknowledge**, unrelated; none touch the sections this plan edits.

## Acceptance Criteria

- [ ] `soleur-egress-gw` (Squid, digest-pinned image) runs on the
      `soleur-egress0` bridge (172.31.100.2:8443) on every web host via
      Terraform/cloud-init from empty state; running web-1 gets it via
      `terraform_data` SSH provisioner with config_hash+server_id triggers
- [ ] CONNECT to public :443 with valid Proxy-Authorization succeeds;
      unauthenticated CONNECT → 407/deny; CONNECT to 169.254.169.254,
      RFC1918, loopback, cluster-private, IP-literal, non-443, and
      Extended-CONNECT all denied and logged
- [ ] Every decision line carries `workspace` (%un) + `resolved_ip` +
      `decision`/`decision_reason` (no `enforce_would_deny` — cut as dead
      schema; the probe pair carries dark-launch signal)
- [ ] Per-dispatch forwarder: exists only while an entitled session runs,
      binds `127.0.0.1:0` (kernel-assigned), requires the per-session token
      inbound + injects `workspaceId:sessionToken` outbound, dies with the
      session, dies on warm-path re-resolve-false (mid-session revoke),
      orphan-reaped at dispatcher startup
- [ ] Session tokens: minted per dispatch, written to
      `/var/lib/soleur/egress-tokens/` (rw→app, ro→gw); Squid helper accepts
      iff token file exists; deletion revokes. No static credential exists
      in any env (verified: no `EGRESS_PROXY_*` in any container env)
- [ ] Reply path verified: forward CONNECT + reply packets both traverse
      (`established,related` accept before inter-bridge isolation; egress0
      drop is `ct state new`-scoped); one-way invariant — new gw→docker0
      connections still dropped
- [ ] `cron-egress-enforce-probe.sh` emits the synthetic allow+deny CONNECT
      pair per run (heartbeat + policy verification on the real path);
      heartbeat-absence + deny-class Better Stack alerts wired through the
      paid-tier ternary
- [ ] `workspaces.web_egress` + RPC pair (+ `.down.sql`); non-owner write →
      403/P0001; member read NULL→false; member view renders the locked
      sibling treatment
- [ ] Scope Grants toggle renders per approved wireframe (off/confirm/on);
      on-state carries the applies-to-new-sessions sub-line; flip emits
      `workspace_action_context` audit; audit-log affordance absent pending
      the follow-up issue
- [ ] Entitled session sandbox has `httpProxyPort` → forwarder AND
      `credentials.envVars` deny covering exported `ALLOWED_SERVICE_ENV_VARS`
      ∪ fixed secret names (GIT_CONFIG_* excluded — neutralization not
      secret) AND `denyRead` covering credential-file paths + the token-dir
      mount
- [ ] WebFetch enabled only when `webEgress` entitlement active AND the
      Phase-0 HTTP_PROXY verification passed; WebSearch remains disallowed
- [ ] Phase-0 spike recorded: `httpProxyPort` localhost/netns semantics +
      WebFetch proxy-honor verified against pinned SDK, outcome in the spec
- [ ] Phase A trade documented in toggle copy + AC: entitled sessions have
      no readable credentials — in-sandbox `git push`/BYOK calls fail until
      Phase B; Phase-B broker issue (#9543) + audit-view issue (#9545) filed, blocked-by #9534
- [ ] Crons unaffected: `cron-bash-allowlist-hook` self-test still denies
      WebFetch; spawn-bash crons still under L1 default-drop
- [ ] ADR merged in this PR reversing #871 posture for opted-in sessions;
      C4 model/views updated or "no impact" justified per 2.10 enumeration
- [ ] Legal pack merged: Art. 30 amendment, DPIA screening record,
      privacy/DPD/mirror updates, `LEGAL_DOC_SHAS` repin, DPA Sch.4, AUP clause
- [ ] `soleur:gdpr-gate` run on this plan and on the diff at work Phase 2 exit
- [ ] PR-B is gated on PR-A observed healthy on real traffic (dark-launch)

## Test Scenarios

All security-invariant tests drive the forwarder/gateway/sandbox-config
directly — no `query()` prompts in the assertion path (the LLM must not be
inside a security assertion, per the #1450-class edge). The squid.conf
selftest verifies syntax with `squid -k parse` inside the digest-pinned image
— the ACL claims are measured against the pinned artifact, not the docs.

- Given web_egress=off workspace, when a session dispatches, then
  `network.allowedDomains` behavior is unchanged (no httpProxyPort, tools
  still disallowed).
- Given web_egress=on, when a session runs `curl https://example.com` via the
  proxy env, then the CONNECT succeeds and a decision+close log pair lands in
  journald with workspace + resolved_ip fields.
- Given web_egress=on, when a session runs `curl https://169.254.169.254` or
  `curl https://10.0.1.40`, then the gateway denies pre/post-resolution and the
  deny reason is in the log.
- Given web_egress=on, when a hostname resolves to mixed public+private
  answers, then the CONNECT is refused (rebinding pin).
- Given web_egress=on, when sandboxed Bash prints `env`, then no
  `*_TOKEN`/`*_KEY`/`GIT_*` secret names are present; the in-process session
  still works (model calls unaffected).
- Given a non-owner, when POST `/api/workspace/web-egress`, then 403.
- Given the gateway container stopped, when an entitled session dials, then
  egress fails closed (same as today's posture) and Sentry gets the signal.
- Given `deniedDomains`/`allowedDomains` set alongside `httpProxyPort`, then
  the plan's caveat is honored: the gateway (not the SDK) is the policy owner —
  test asserts the gateway denies what the SDK list would have.

## Success Metrics

- Entitled session can `curl https://<arbitrary-https>` end-to-end; denied
  classes produce `decision=deny_*` lines
- Zero `egress-blocked` regression for non-entitled traffic (existing probes
  stay green)
- CONNECT decision logs queryable in Better Stack within 1 min of dispatch

## Dependencies & Risks

- **SDK version pin:** `claude-agent-sdk@0.3.284` typings confirm the knobs;
  issue #87296 evidence says `httpProxyPort` disables built-in enforcement —
  pin-verify at impl; upgrade path may change semantics.
- **WebFetch in-process:** if it ignores `HTTP_PROXY`, WebFetch stays off for
  entitled sessions in Phase A (documented limitation; Bash/curl unaffected).
- **Shared egress IP reputation:** gateway shares the host IP with
  Resend/web-push — abuse could poison deliverability. Dedicated egress IP
  deferred to observed signal (spec Open Question 2).
- **cloud-init byte budget:** ~300 B headroom — gateway launch rides a baked
  script file + one runcmd line.
- **cloud-init drift on web-1:** `ignore_changes=[user_data]` — running host
  needs the SSH provisioner path; fresh hosts get it automatically.
- **Domain fronting residual:** CONNECT-authority vs SNI mismatch is
  undetectable without MITM — accepted residual recorded in the ADR (kern
  precedent).
- **Compliance window:** legal pack is a merge blocker — do not merge PR-B
  before CLO's Art. 30/privacy/AUP amendments land.
- **Adjacent, not this plan:** #9539 — support-persona sessions dead-end on
  write-requiring tasks (the `sandboxWrite:"none"` L5 axis; the grant pattern
  here is reusable for it but the threat model differs — ADR-113).

## Research Insights

**Relevant files:**
`apps/web-platform/infra/cron-egress-nftables.sh` (rule order; `:210` iifname
jump; `:185` drop point) · `apps/web-platform/infra/cron-egress-allowlist.txt`
(evidence-comment convention) · `apps/web-platform/server/agent-runner-sandbox-config.ts`
(:295 `buildAgentSandboxConfig`, :365 `network`, :275 `ENTITLED_EGRESS_DOMAINS`)
· `apps/web-platform/server/agent-runner-query-options.ts` (:56 disallowed
tools, :287 `allowGithubEgress` derivation) · `apps/web-platform/server/cc-dispatcher.ts`
(:1766 dispatch `Promise.all`, :2773 sdkQuery, :2810 persona tools, :3486
warm-path re-resolve) · `apps/web-platform/server/agent-env.ts` (secret env
census) · `apps/web-platform/server/providers.ts:10-24` (`ALLOWED_SERVICE_ENV_VARS`)
· `apps/web-platform/server/tool-tiers.ts` (MCP tier gate — Phase C `web_fetch`
fallback path) · `app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
(:170 owner gate) · `components/settings/bash-autonomous-toggle.tsx` (clone
source) · `supabase/migrations/101_workspace_debug_mode.sql` (RPC template) ·
`server/workspace-action-audit.ts` (`scope-grant` action) · `apps/web-platform/infra/cloud-init.yml`
(:785 app run, :807 enforce-probe — gateway runcmd slots between docker
restart and app run) · `apps/web-platform/infra/server.tf` (:173
host_script_files, :1346 terraform_data running-host delivery, :597
ignore_changes=[user_data]) · `vector.toml:89` (CONTAINER_NAME source).

**Learnings applied:** ADR-051 (derived entitlement flag); ADR-052 (docker0
scoping is the lever; intended-drop discipline); ADR-033 I7 (spawn-bash crons
hook-blind → L1 must stay); allowlist-bypass trilogy (policy in proxy, not
regex); 2026-09-30 secret-custody (env secrets reachable = exfil
prerequisite → envVars deny); #9269 (bound every network subprocess).

**External prior art:** Stripe Smokescreen (ACL + deny-range + decision/close
JSON schema + `enforce_would_deny`); kern (IP-literal refuse, 443-only, SNI
residual documented); E2B BYOP (dial-time re-resolve+pin); Devin sandbox
(`denied_domains` deny-wins, limited mode); turbo.net egress validation suite
(test list); Next.js #92338 (pinned-lookup TOCTOU pattern).

**Scoped-consult outcomes (applied):** (a) advisor — `httpProxyPort` is
localhost-port-only → per-dispatch in-container forwarder leg added;
container-wide endpoint = confused deputy → `Proxy-Authorization` +
workspace attribution added; bespoke proxy under-budgeted deny spec →
Squid; gw-outbound needs its own nft deny; HTTP_PROXY must be injected
per-dispatch (ambient leaks via `AGENT_ENV_ALLOWLIST`). (b) terraform-
architect — bake chain is four files (host_script_files + Dockerfile COPY +
.dockerignore + soleur-host-bootstrap.sh); `triggers_replace` must fold
`server_id`; `-target` allowlist names the new terraform_data; Vector source
must join the pii_scrub transform inputs; absence-detection is Better Stack
`logtail_exploration_alert` (paid-tier ternary), not Sentry.

**Premise Validation:** #8467/#6088 verified OPEN (cron-scoped, adjacent not
duplicate); #9534 OPEN; cited files/symbols all confirmed on origin/main;
no existing proxy/CONNECT infra (grep: zero `httpProxyPort`/`socksProxyPort`
usage); ADR corpus checked for the mechanism — ADR-052 rejected SNI-proxy for
*cron* SPOF reasons that don't apply to per-session opt-in (gateway failure
fails closed per-session, doesn't darken crons).

**Property List (0.6b):** (a) sessions reach arbitrary HTTPS; (b) per-workspace
opt-in; (c) secrets unreadable in-sandbox; (d) per-session egress audit; (e)
L1 posture unchanged for app/crons.
**Cut List:** none — no mechanism duplicates an existing one; MCP tool-tier
covers governed tools, not arbitrary egress; WebSearch (server-side) is a
demand-validation option, not a substitute (Open Question 1).

## Files to Create

- `apps/web-platform/infra/egress-gateway-squid.conf` (Squid policy —
  CONNECT/443-only ACLs, `dst` deny table, `proxy_auth`, JSON logformat)
- `apps/web-platform/infra/egress-auth-helper.sh` (Squid basic-auth helper:
  OK iff `<password>` exists as a file under the mounted session-tokens dir;
  username = workspaceId passthrough to `%un`)
- `apps/web-platform/infra/egress-deny-cidrs.txt` (single deny-set source for
  squid ACL + nftables render)
- `apps/web-platform/infra/egress-image.provenance.md` +
  `egress-image-staleness.test.sh` (zot-style digest-freshness triptych)
- `apps/web-platform/infra/egress-forwarder.mjs` (per-dispatch in-container
  localhost forwarder + auth injection)
- `apps/web-platform/infra/egress-gateway-bootstrap.sh` (bridge + container
  bring-up, idempotent)
- `apps/web-platform/infra/egress-gateway.test.sh` (Guard 1/4 mutation matrix)
- `apps/web-platform/supabase/migrations/1XX_workspace_web_egress.sql`
- `apps/web-platform/server/resolve-web-egress.ts`,
  `server/set-web-egress.ts`
- `apps/web-platform/app/api/workspace/web-egress/route.ts`
- `apps/web-platform/components/settings/web-egress-toggle.tsx`
- `apps/web-platform/supabase/migrations/1XX_workspace_web_egress.down.sql`
- `scripts/probes/egress-gateway-policy.sh` (discoverability selftest wrapper
  — invokes the same fixtures as egress-gateway.test.sh)
- ADR-2XX + C4 updates; legal-pack files (privacy-policy.md, DPD, DPA Sch.4,
  AUP, article-30-register.md, compliance-posture.md entry, Eleventy mirror)

## Files to Edit

- `apps/web-platform/infra/cron-egress-nftables.sh` (docker0→gw accept +
  DOCKER-USER reply accept + SOLEUR-EGRESS-GW chain + IPv6 guard)
- `apps/web-platform/infra/cron-egress-resolve.sh` (self-heal needle set +
  egress0-CIDR render)
- `apps/web-platform/infra/cron-egress-enforce-probe.sh` (synthetic CONNECT
  pair = heartbeat emitter)
- `apps/web-platform/infra/cron-egress-firewall.test.sh` (rule fixtures)
- `apps/web-platform/infra/cloud-init.yml` (runcmd line + token-dir mount on
  the app docker run)
- `apps/web-platform/infra/server.tf` (host_script_files entries +
  terraform_data running-host block with config_hash+server_id triggers)
- `apps/web-platform/Dockerfile` (COPY set for baked files)
- `apps/web-platform/.dockerignore` (`!infra/<file>` re-includes)
- `apps/web-platform/infra/soleur-host-bootstrap.sh` (install loops +
  assertions for new baked files)
- `.github/workflows/apply-web-platform-infra.yml` (`-target` allowlist,
  post-bridge SSH stage ~:1181-1200)
- `.github/workflows/rule-audit.yml` (squid-digest upstream-poll step)
- `apps/web-platform/infra/vector.toml` (CONTAINER_NAME source + transform
  inputs)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (deny-class +
  heartbeat-absence logtail_exploration_alerts, paid-tier ternary)
- `apps/web-platform/server/agent-runner-sandbox-config.ts` (allowWebEgress +
  deny census)
- `apps/web-platform/server/agent-runner-query-options.ts` (conditional
  disallowed-tools)
- `apps/web-platform/server/cc-dispatcher.ts` (resolveWebEgress in
  Promise.all + forwarder lifecycle + per-dispatch HTTP_PROXY)
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
  (mount toggle)
- Tests: `agent-runner-helpers.test.ts` (or sibling sandbox-config test),
  `cloud-init-user-data-size.test.ts`, `web-host-provisioner-parity.test.sh`,
  `terraform-target-parity.test.ts`
