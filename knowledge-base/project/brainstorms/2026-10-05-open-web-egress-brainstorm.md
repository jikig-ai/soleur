# Brainstorm: Open-web egress for hosted agent sessions

**Date:** 2026-10-05
**Issue:** #9534
**Branch:** `feat-open-web-egress`
**PR:** #9529 (draft)
**Lane:** cross-domain (USER_BRAND_CRITICAL unconditional per #5175)
**Status:** Decided — ready for plan

## What We're Building

Per-workspace opt-in open-web egress for hosted agent sessions, delivered
through a dedicated egress-gateway sidecar — so an agent can `WebFetch` docs,
install packages, and call arbitrary HTTPS APIs, without widening the
whole-container firewall that ADR-052 built for the spawn-bash cron
population.

Today five gates sit between an agent session and the network (verified
2026-10-05 against `main`):

- **L1 — container nftables.** `SOLEUR-EGRESS` off `DOCKER-USER`, default-drop,
  IP-only, scopes the *entire* `soleur-web-platform` container (Next.js app +
  crons + agent sessions). Allowlist: `apps/web-platform/infra/cron-egress-allowlist.txt`
  (~30 SaaS hosts + 99 GHA blob accounts), resolved per-minute with a 24 h
  rotation grace window. DNS pinned to container resolvers (`egress-dns-exfil`
  drop+log), link-local dropped (#9378).
- **L2 — per-session sandbox proxy.** `buildAgentSandboxConfig`
  (`apps/web-platform/server/agent-runner-sandbox-config.ts:295`) emits
  `network.allowedDomains=[]` + `allowManagedDomainsOnly:true`; widened to
  `ENTITLED_EGRESS_DOMAINS` (GitHub + npm + GHA logs) only when
  `allowGithubEgress = Boolean(ghToken)` (ADR-051).
- **L3 — tool deny.** `CANONICAL_DISALLOWED_TOOLS = ["WebSearch","WebFetch"]`
  (`agent-runner-query-options.ts:56`).
- **L4 — cron PreToolUse hook** (`cron-bash-allowlist-hook.mjs`) — denies
  WebFetch/WebSearch for cron sessions; spawn-bash crons bypass it entirely
  (ADR-033 I7), making L1 their only containment.
- **L5 — sandbox-hook** — filesystem/env only, no network.

Demand signal exists but is thin: #8467/#6088 record containment blocking
legitimate WebFetch (2026-10-05 marketing audits ran source-only). No external
user complaint is on record (1 alpha tester, self-hosted CLI).

## User-Brand Impact

- **Artifact:** open-web egress for hosted agent sessions (the sandbox egress
  boundary itself).
- **Vector:** a prompt-injected agent session POSTs the user's workspace
  contents, minted GitHub App token, BYOK `serviceTokens` (Stripe/Cloudflare/
  Doppler/…), or Anthropic key to an arbitrary attacker host — today bounded to
  GitHub tenancy (ADR-051), unbounded under open egress.
- **Threshold:** `single-user incident`.

## Why This Approach

| Decision | Chosen | Rationale |
|---|---|---|
| Egress scope | **HTTPS-only open web** | CONNECT/443 only; DNS stays pinned, non-HTTP exfil ports stay dropped. Operator choice over fully-open (any port) and curated-allowlist options. |
| Entitlement interaction | **Opt-in + credential broker** | Open egress and raw in-env credentials never coexist long-term; broker injects tokens per-request for pinned hosts only. Operator choice. |
| Sequencing | **Two-phase: uncredentialed first** | Phase A ships opt-in open web for sessions with `credentials.envVars` deny on all token names (SDK-native, verified in `claude-agent-sdk@0.3.284` `SandboxSettingsSchema`); Phase B lands the real cred broker so credentialed sessions can browse. Operator choice. |
| Toggle granularity | **Per-workspace setting** | Product UI toggle in workspace settings, default off; marketable as boundary control (CMO). UI surface → wireframe required. Operator choice. |
| Enforcement point | **Egress-gateway sidecar (Approach A)** | CONNECT-only forward proxy on a *second* docker bridge — escapes L1's `iifname "docker0"` jump, so L1 stays default-drop for app + crons. Sessions reach it via SDK `httpProxyPort`. Rejected: flat L1 wildcard (un-contains the very crons ADR-052 exists for); per-workspace allowlist (CLO's GDPR-optimal variant — doesn't deliver browsing); governed `web_fetch` MCP tool (CPO's variant — no installs/clones/arbitrary APIs). |
| WebFetch/WebSearch re-enable | **Per-session, gated on the same entitlement** | L3 is re-scoped per session, not deleted; crons never opt in (L4 untouched). |

## Key Decisions

1. **Egress gateway on a second bridge.** The `iifname "docker0"` scoping of
   L1 is the load-bearing fact: a gateway container on `soleur-egress0` (new
   bridge) is reachable from agent containers via exactly one new L1 rule
   (`docker0 → gw-ip:port accept`), while remaining unreachable by the same
   default-drop for arbitrary destinations. Policy lives in the proxy, which
   is domain-aware — L1 stays IP-only and untouched in spirit.
2. **The proxy owns all domain policy.** SDK caveat (verified):
   `httpProxyPort` replaces the sandbox proxy's domain enforcement — so the
   gateway must enforce HTTPS-only CONNECT, metadata/RFC1918/link-local/
   cluster-private denies, resolve-and-pin (DNS-rebinding), and emit a
   per-session CONNECT access log → Vector → Better Stack. Policy in the
   proxy, not a regex guard — three successive hand-rolled-allowlist bypasses
   are on record (learnings 2026-09-18, 2026-10-04 ×2).
3. **Phase A = uncredentialed open web.** `credentials.envVars: deny` unsets
   every token name (`GH_TOKEN`, `GIT_*`, BYOK `serviceTokens` keys,
   `ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN` handled per SDK semantics)
   inside the sandbox; `soleur_platform` MCP tools run host-side and are
   unaffected. A web session cannot leak what it cannot read.
4. **Phase B = credential broker.** Per-request token injection for pinned
   hosts (github.com CONNECTs get the real GitHub token; nothing else does),
   restoring `git push`/`gh` for web-enabled sessions. Tracked in spec as a
   follow-on phase, not this PR.
5. **Observability parity is a launch gate.** Gateway CONNECT log +
   denied-destination alerting must be live *before* the toggle ships, or we
   trade the `egress-blocked` fail-loud channel (Sentry `op=egress_blocked`,
   paging alert in `infra/sentry/issue-alerts.tf`) for silence.
6. **Legal pack precedes ship.** CLO: Art. 30 PA-2(d) closed recipient
   enumeration is broken by open egress → amend register + DPIA screening;
   privacy-policy/DPD/Eleventy mirror updates (`LEGAL_DOC_SHAS` repin);
   DPA Schedule 4 TOM records the proxy control; AUP gains a hosted-egress
   abuse clause. `hr-gdpr-gate-on-regulated-data-surfaces` fires at plan
   Phase 2.7.
7. **`wg-dark-launch-deploy-gates` applies.** The gateway and its deny rules
   deploy non-blocking first and are observed on real traffic shape before
   any session entitlement can route through them.

## Security Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Prompt-injection exfiltration of env credentials | Critical | Phase A `credentials.envVars` deny (no secrets readable in-sandbox); Phase B broker (per-request injection). ADR-051 residual restored. |
| SSRF to metadata/internal planes | Critical | Gateway denies 169.254.0.0/16 (cloud-init serves a Doppler read token — `cron-egress-nftables.sh:71`), RFC1918, link-local, cluster-private (Inngest 10.0.1.40), IP-literal connects; resolve-and-pin defeats DNS rebinding. |
| Indirect prompt injection via fetched content | High | Fetched content stays untrusted-content; plan-level: WebFetch results wrapped/marked; no auto-follow of embedded instructions (policy text in system prompt, defense-in-depth not sole control). |
| Abuse → shared egress IP reputation | Medium | Gateway rate-limits + per-session CONNECT audit; dedicated egress IP evaluation deferred (Open Questions). |
| Observability gap | High | CONNECT access log → Vector → Better Stack; Sentry alert on denied classes; parity with `egress-blocked` channel is launch-gating. |
| DNS exfil | Low | Unchanged: off-pin DNS dropped + logged `egress-dns-exfil` at L1. |
| Toggle as exfil-enablement surface | Medium | Workspace settings write-path is server-side + audited; agents cannot mutate their own entitlement (no tool surface grants it). |
| GDPR arbitrary-recipient exposure | High (legal) | User-directed fetches defensible as controller instruction; injected exfil is not — mitigations above + legal pack (Key Decision 6) are the Art. 32 adequacy story. |

## Open Questions

1. **Demand proof.** No external user has asked for open egress; the only
   demand signal is internal (#8467/#6088). Is there a cheaper demand-validating
   increment (e.g., re-enable WebSearch — server-side via api.anthropic.com,
   ~zero egress change) before building the gateway? *(Parked — operator chose
   full open web; noted for the plan's sequencing section.)*
2. **Dedicated egress IP?** Shared host IP carries Resend/web-push/API
   standing; a dedicated egress IP isolates reputation but adds cost. Defer to
   observed abuse signal?
3. **Phase B broker shape.** SDK has no per-host injection primitive —
   `credentials.envVars` is deny-only. The broker is likely a small service
   beside the gateway holding a secrets handle per session. Exact mechanism is
   a plan-time decision.
4. **Cron sessions under the gateway.** Scope says crons never opt in; confirm
   no eval cron needs general fetch as a follow-up once Phase A lands
   (UX-audit's Playwright carve already exists separately).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Need is real but unproven at user scale — zero external
complaints; the shipped pattern for third-party access is governed
`soleur_platform` MCP tools, not sandbox egress. Recommended curated
capability packs or a governed `web_fetch` tool over wildcard egress; flagged
worst-single-user case (repo + GitHub token exfiltration) as company-ending
for a solo-founder tenant.

### Legal (CLO)

**Summary:** Open egress breaks the Art. 30 closed recipient enumeration and
the ADR-051 residual-bounding argument — user-directed fetches are defensible,
injected exfiltration is not. Requires privacy/DPD/Art. 30/AUP/TOM amendments
before ship; recommends per-workspace-scoped egress grants over wildcard, with
metadata/RFC1918 deny, per-session token scoping, and egress logging as
non-negotiable Art. 32 preconditions.

### Engineering (CTO)

**Summary:** Three gates must change (L3 tool deny, L2 sandbox config, L1
container path) — L1 flat-widening is rejected since it un-contains the
spawn-bash crons ADR-052 exists for. Recommends an egress-gateway sidecar on a
second bridge + SDK `credentials` masking + entitlement-derived flag
(ADR-051 precedent); complexity medium-large; ADR required (reverses PR #871
zero-egress posture).

### Marketing (CMO)

**Summary:** Open web is table stakes trending to expectation, not a
differentiator — market the *boundary control*, not the browsing. Incident
asymmetry is brand-existential vs parity benefit; ship opt-in, never
default-on. Note: a published distribution piece argued *against* server-side
browsing ("Agents That Use APIs, Not Browsers", marked stale) — frame
carefully.
