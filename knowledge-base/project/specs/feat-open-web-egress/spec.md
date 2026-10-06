---
lane: "cross-domain"
issue: 9534
brand_survival_threshold: "single-user incident"
wireframe: "knowledge-base/product/design/settings/agent-web-access.pen"
---

# Feature: Open-web egress for hosted agent sessions (#9534)

Brainstorm: [`knowledge-base/project/brainstorms/2026-10-05-open-web-egress-brainstorm.md`](../../brainstorms/2026-10-05-open-web-egress-brainstorm.md).

## Problem Statement

Hosted agent sessions cannot reach the web. Five enforcement layers compose to
zero-egress: L1 container nftables default-drop (`SOLEUR-EGRESS` off
`DOCKER-USER`, whole-container scope), L2 per-session sandbox
`network.allowedDomains` (empty unless GitHub-entitled, ADR-051), L3
`CANONICAL_DISALLOWED_TOOLS = ["WebSearch","WebFetch"]`, L4 cron PreToolUse
deny-hook, L5 fs/env sandbox hook. Legitimate agent work — fetching docs,
installing packages, calling external APIs — is impossible; #8467/#6088 record
containment blocking real WebFetch uses. Flat-widening L1 is rejected: it
un-contains the spawn-bash crons ADR-052 exists for and carries no per-session
granularity.

## Goals

- Per-workspace opt-in "Agent web access" toggle on Settings → Scope Grants
  (inline-confirm pattern per `bash-autonomous-toggle.tsx`; wireframe:
  `knowledge-base/product/design/settings/agent-web-access.pen`).
- Egress-gateway sidecar on a second docker bridge: CONNECT-only, port 443,
  metadata/RFC1918/link-local/cluster-private/IP-literal denies,
  resolve-and-pin (DNS-rebinding), per-session CONNECT access log → Vector →
  Better Stack.
- Phase A (this PR's scope): opted-in sessions get `network.httpProxyPort`
  → gateway, `deniedDomains` guardrails, and `credentials.envVars: deny` on
  all token names — no readable secrets in-sandbox; WebFetch/WebSearch
  re-enabled only for web-entitled sessions.
- Observability parity before the toggle ships: CONNECT log + denied-destination
  Sentry alert must be live (replaces `egress-blocked` coverage for the new path).
- Legal pack (CLO-required before ship): Art. 30 register amendment + DPIA
  screening; privacy-policy/DPD/Eleventy mirror updates + `LEGAL_DOC_SHAS`
  repin; DPA Schedule 4 TOM entry for the proxy control; AUP hosted-egress
  abuse clause.
- ADR recording the reversal of the PR #871 zero-egress posture and the
  gateway-vs-flat-open decision.

## Non-Goals

- **Phase B credential broker** (per-request token injection so credentialed
  sessions can browse + `git push`) — follow-on phase, not this PR.
- Cron egress changes — L4 containment untouched; crons never opt in.
- Unconditional/default-on egress — opt-in only, ever (CMO/CPO).
- Per-workspace extendable host allowlist (Approach B) and governed
  `web_fetch` MCP tool (Approach C) — evaluated and rejected in the
  brainstorm; may resurface if demand proves narrower than assumed.
- Dedicated egress IP — deferred to observed abuse signal (Open Question 2).

## Functional Requirements

### FR1: Workspace opt-in toggle

New "Agent web access" card on the Scope Grants settings page, default OFF,
owner-gated, inline gold-bordered confirm on enable (no confirm on disable),
persistent risk callout, "View egress audit log" link — per the approved
wireframe's three states (off / confirm / on).

### FR2: Entitlement-derived sandbox widening

`buildAgentSandboxConfig` gains a derived flag (ADR-051 precedent —
`allowGithubEgress`-style, never independently threadable): when the
workspace grant is on, emit `network.httpProxyPort` + `deniedDomains`
(metadata-provider hosts, internal planes) + `credentials.envVars` deny list
covering `GH_TOKEN`, `GIT_*`, all BYOK `serviceTokens` names, and the
Anthropic credential names. `allowManagedDomainsOnly` stays on.

### FR3: Egress gateway

Terraform-managed container on a new `soleur-egress0` bridge: forward proxy
accepting CONNECT :443 only; deny set = 169.254.0.0/16, RFC1918, link-local,
cluster-private ranges (incl. Inngest 10.0.1.40), IP-literal targets;
resolve-and-pin per CONNECT; structured access log. L1 gains exactly one rule:
`iifname "docker0" → <gw-ip>:<port> accept`. Deployed non-blocking and
observed on real traffic before any entitlement can route through it
(`wg-dark-launch-deploy-gates`).

### FR4: Tool-surface re-scope

`CANONICAL_DISALLOWED_TOOLS` becomes per-session: `WebFetch`/`WebSearch`
removed only when the web entitlement is active. Cron sessions unaffected
(L4 unchanged).

### FR5: Observability

Gateway CONNECT log shipped via Vector → Better Stack; Sentry alert on
denied-destination classes; per-session entitlement decision logged
(`agent-sandbox` feature, same shape as the `sibling-deny` structured log).
`## Observability` plan block per `hr-observability-as-plan-quality-gate`.

## Technical Requirements

- TR1: SDK surface is `@anthropic-ai/claude-agent-sdk@0.3.284` — verify
  `httpProxyPort` semantics at implementation time (it *replaces* domain
  enforcement; the proxy must own all policy). Pin-verify before relying.
- TR2: `deniedDomains` is merged from all settings sources regardless of
  `allowManagedDomainsOnly` — safe for guardrails.
- TR3: Gateway is a standing dependency for opted-in sessions only —
  default-drop remains for everything else; gateway failure must fail closed
  per-session (proxy unreachable = no egress, same as today).
- TR4: `hr-all-infrastructure-provisioning-servers` — gateway via Terraform,
  converged by the apply workflow on a fresh host, zero manual steps.
- TR5: `hr-gdpr-gate-on-regulated-data-surfaces` at plan Phase 2.7 and work
  Phase 2 exit — regulated surface (auth flows + egress of workspace data).
- TR6: Drift-guard updates: `agent-runner-helpers.test.ts`,
  `cron-egress-firewall.test.sh`, `terraform-target-parity.test.ts`
  (-target allowlist for the new gateway resources).
- TR7 (Phase-0 spike, measured 2026-10-05 against the vendored
  `claude-agent-sdk-linux-x64@0.3.284` binary, `-p` + `--settings
  {sandbox:{enabled,failIfUnavailable,enableWeakerNestedSandbox,
  network:{allowedDomains, httpProxyPort:28711}}}` — two loopback
  listeners discriminating "bridged port" vs "shared netns"):
  - **POSITIVE — `httpProxyPort` is a host-side port SRT chains to.** The
    sandboxed child runs in a separate netns (readlink /proc/self/ns/net
    differs from host) and sees `HTTP_PROXY=http://localhost:3128` — SRT's
    own allowlist proxy inside the netns — plus
    `CLAUDE_CODE_HOST_HTTP_PROXY_PORT=28711` naming our host port. A child
    `curl https://example.com/` (example.com NOT in allowedDomains) arrived
    at the host listener as `CONNECT example.com:443` — so under
    `httpProxyPort` SRT forwards upstream WITHOUT applying its own domain
    filter: the gateway owns all policy, as TR1 predicts, and
    `deniedDomains` emission stays cut (it would filter nothing anyway).
  - **The child's localhost is NOT the container loopback.** Direct
    `curl http://localhost:28711` and `:18081` both fail —
    connect-refused inside the netns. Only the SRT-bridged proxy ports
    work. Consequence for the forwarder design: the forwarder MUST live on
    the container's real loopback (the "in-container" of the plan means
    host-of-sandbox, not in-netns) and is reached only via SRT's internal
    proxy → upstream chain. The forwarder port is never directly dialable
    by the sandboxed child — an accidental hardening, not a leak.
  - **SRT pre-fills `no_proxy` with the RFC1918/link-local set** —
    private-IP requests bypass the proxy and die in the netns. Belt under
    the Squid CIDR denies.
  - **In-process WebFetch ignores sandbox `httpProxyPort` entirely** —
    with no env proxy on the CLI process it fetched example.com direct
    (no listener hit). It DOES honor process-env `HTTP(S)_PROXY`:
    rerunning with `HTTP_PROXY=http://127.0.0.1:28711` on the CLI env
    produced `CONNECT api.anthropic.com:443` and Datadog-intake CONNECTs
    at the listener — ambient env-proxy steers ALL in-process fetch,
    including the model API call itself (first arm died: API call got my
    listener's 502). PR-B consequence: WebFetch can only transit the
    gateway via `query({options:{env:{HTTP_PROXY,HTTPS_PROXY,NO_PROXY}}}`
    on the spawned CLI subprocess — per-dispatch, never ambient on the
    dispatcher — and NO_PROXY MUST enumerate the platform control plane
    (api.anthropic.com, Sentry, Statsig, Datadog, Supabase, Stripe, GitHub
    endpoints) or those calls transit the tenant gateway. Failure mode if
    a platform host is missed: Squid allows public hosts, so the call
    would still work but platform auth headers transit the egress path —
    list completeness is a hard requirement, not a nicety.

## Open Questions (parked from brainstorm)

1. Demand proof — no external user has requested open egress; consider a
   WebSearch-only demand-validating increment first (server-side tool, ~zero
   egress change).
2. Dedicated egress IP vs shared host IP (Resend/web-push reputation).
3. Phase B broker mechanism — SDK has deny-only `credentials`; real
   per-request injection likely needs a secrets-holding service beside the
   gateway.
