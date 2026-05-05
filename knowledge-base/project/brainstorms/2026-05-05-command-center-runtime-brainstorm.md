---
date: 2026-05-05
topic: Command Center server-side agentic runtime
status: brainstorm
branch: feat-agent-runtime-platform
pr: "#3240"
trigger: external-comparison (Augment Cosmos public preview, https://www.augmentcode.com/blog/cosmos-now-in-public-preview)
brand_survival_threshold: single-user incident
---

# Command Center: Server-Side Agentic Runtime

## What We're Building

The roadmap-implied runtime, made shippable. Three sequenced increments inside `apps/web-platform/`:

1. **Cross-tenant isolation hardening (gate-zero).** Replace the `SUPABASE_SERVICE_ROLE_KEY` escape hatch in `server/agent-runner.ts` with per-invocation user-scoped Supabase JWTs. RLS becomes the enforced isolation boundary, not a paper-only one. BYOK custody moves to a per-invocation lease with audit row.
2. **Multi-turn continuity (#1044) fix.** Domain leaders today are stateless one-shots; the runtime amplifies whatever signal they emit, so amnesia compounds. Continuity must land before background reactions ship.
3. **Daily Priorities home + one Inngest-driven background trigger.** Dashboard answers "what needs you today" across all 8 domains. End-to-end demo: Stripe failed-payment webhook → CFO drafts response + CRO logs the deal-risk → founder reviews in Command Center.

Single brand: **Soleur**. Two surfaces (CLI plugin, Web Platform) under one product, one brand — no sub-brand. Closed free preview until E&O insurance + DPA + audit log + scope-grant UX are in place. Paid tier targets $99/mo flat BYOK.

## Why This Approach

**Reframe from "Cosmos competitor" to "alignment + hardening."** CPO and CMO independently challenged the original framing. The roadmap, brand guide, and Phase 1.10/1.11 already describe a server-side runtime; the work is shipping the runtime the roadmap implies, not pivoting to a new product. Direct positioning vs Cosmos makes Soleur read as "Cosmos-lite" in a category Augment will outspend ~50:1; the real comp is Polsia ($1.5M ARR, audience-validated), Lindy, Notion AI 3.3, Relevance AI.

**Substrate already largely exists.** `server/agent-runner.ts` runs durable per-user Claude Agent SDK sessions on Hetzner Node with WS streaming, BYOK decryption, sandboxed workspaces. Inngest agent kit adds the missing pieces (durable triggers, retries, sleep-until, fan-out) as a library, not a rewrite. Bedrock AgentCore was rejected (AWS lock); LangGraph + custom event bus rejected (operationally heavy for solo-founder economics); Cloudflare Durable Objects rejected (can't host the Agent SDK long-running process).

**Solo-founder positioning is the moat, not agent count.** Cosmos targets engineering teams running an agentic SDLC. Soleur targets one operator running an entire company across 8 domains. The 8-domain leader pattern + cross-domain priority arbitration is defensible because Cosmos's eng-team buyer doesn't need it; an opinionated org simulation that resolves CTO-vs-CMO tradeoffs is the wedge, not the headcount.

**Cross-tenant isolation must be gate-zero.** The single brand-ending vector across all 5 leaders' assessments. Today's service-role escape hatch is acceptable for a synchronous WS session bound to one verified user; it is not acceptable when the same process autonomously schedules work on behalf of N founders. Fix this before any new surface ships.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framing | Alignment + hardening (NOT pivot vs Cosmos) | CPO+CMO challenge accepted; positioning vs Polsia/Lindy/Notion AI |
| Target user | Solo founder running an agentic company across 8 domains | Validation FLAG persists; not yet validated for "react-while-sleeping" form factor |
| MVP scope | Three sequenced increments: RLS hardening → #1044 fix → Daily Priorities + 1 trigger | All three required for a defensible demo |
| Branding | Single brand "Soleur" across CLI plugin + Web Platform; no sub-brand | User directive 2026-05-05; one product, one brand, two surfaces — overrides earlier "Soleur Command Center" CMO recommendation |
| Headline | "Run a company. Not a codebase." | CMO; demo = inbound email → cross-domain cascade |
| Pricing | $99/mo flat, BYOK | CMO; below "needs spouse approval," above "must be a toy" |
| Channels | X build-in-public, IndieHackers, YC W26, Lovable/Bolt Discords | CMO; skip LinkedIn/podcasts |
| Runtime substrate | Inngest agent kit on existing Hetzner+Supabase | CTO+COO converge; alpha ~$30/mo, beta ~$300/mo |
| Tenant isolation invariant | Per-invocation user-scoped Supabase JWT; service-role allowlisted to JWT-mint + audit only | CTO; load-bearing — capture in ADR |
| BYOK custody | Per-invocation lease in `AsyncLocalStorage`; audit row before Anthropic call; zeroize on lease end | CTO; HKDF-per-user already correct primitive |
| Event bus shape | Per-founder topic-keyed durable queue; Inngest events keyed `{founderId}.{domain}.{event}`; one in-flight per `(founderId, domain, eventKey)` | CTO; prevents ralph-loop pathology |
| Episodic memory | Per-founder pgvector in their Supabase project | CTO; tenant isolation already enforced via #2887 dev/prd separation |
| Procedural memory | Files on shared Hetzner host symlinked into workspace (unchanged) | CTO; cross-tenant procedural is acceptable since it's open-source plugin content |
| Trust model | "Drafts everywhere, sends nowhere" + 5-tier action-class autonomy | CPO; matches solo-founder review cadence |
| Launch gating | Closed free preview until E&O + DPA + audit log + scope-grants land | CLO; 9 must-have legal artifacts |
| ADR | Capture Inngest decision via `/soleur:architecture create` | CTO recommendation; load-bearing |

## Open Questions

- **#1044 multi-turn fix shape.** Are we storing per-(founder, domain, conversation) message history in Postgres, or extending Claude Agent SDK's session persistence? Decision blocks Phase 2 of the MVP.
- **Daily Priorities signal sources for MVP.** CPO's mock includes Stripe failed-payment, milestone-overdue, lead inbox, privacy policy stale, competitive note. Which subset for MVP? CTO can wire 1-3 cheaply.
- **Validation interview cadence.** CPO flagged validation as FLAG. Run 5 more interviews mid-MVP (after RLS hardening, before priorities surface) to confirm the "react-while-sleeping" framing? Or ship and learn?
- **Trust-tier policy storage.** Per-action-class autonomy needs a declarative policy engine. Postgres table + UI, or YAML in workspace, or both?
- **Cosmos defensibility runway.** Augment will likely add marketing/sales/support experts within 12 months. What's the brand's defensibility plan once registry parity arrives?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal (5 of 8). Sales, Finance, Support not spawned — domain signals not orthogonal to the architectural scope.

### Product (CPO)

**Summary:** Recommends shipping but reframes as alignment-not-pivot. MVP surface = Daily Priorities + 1 background trigger; trust model = "drafts everywhere, sends nowhere" + 5-tier autonomy. Validation still FLAG; recommends 5 more founder interviews. Push back: don't ship runtime before fixing #1044.

### Engineering (CTO)

**Summary:** Substrate exists; pivot is alignment + Inngest layer + RLS hardening. Per-invocation user-scoped JWT is the load-bearing isolation invariant. Per-invocation BYOK lease + audit row. Per-founder pgvector for episodic; shared host for procedural. Counter-take: substrate isn't the bottleneck, leader quality + delegation willingness are. Recommend ADR via `/soleur:architecture create`.

### Marketing (CMO)

**Summary:** Position as "the agentic operating system for one-person companies" — NOT vs Cosmos. Single brand "Soleur" (no sub-brand per user directive 2026-05-05; supersedes initial CMO sub-brand recommendation). Headline "Run a company. Not a codebase." Demo: inbound email → cross-domain cascade. $99 flat BYOK. Channels: X, IndieHackers, YC W26, Lovable/Bolt Discords. Defensible wedge: opinionated org simulation, not agent count.

### Legal (CLO)

**Summary:** Soleur is GDPR Art. 28 data processor the moment it executes against founder credentials. 9 must-have artifacts before first paid user. E&O insurance ($1-3M, ~$3-8K/yr) before paid tier. Liability cap = 12 months fees, founder retains command authority, scope-grants required, consequential-damages waiver, indemnity carve-out for gross negligence only. Forensic audit log: WORM, hash-chained, 7-year retention.

### Operations (COO)

**Summary:** Inngest agent kit recommended; reject Bedrock (AWS lock). Doppler inadequate at 1000 founders for BYOK custody — need per-tenant envelope encryption. Alpha ~$30/mo additional; beta ~$300-400/mo. Biggest risk: BYOK custody breach (one Anthropic key leak = founder bankrupt). Add: per-tenant cost attribution, kill-switch on cost spike, PagerDuty, DPA chain (Inngest/AWS/CF).

## Capability Gaps

| Gap | Owning Domain | Why needed |
|---|---|---|
| Event bus / job queue with per-tenant isolation | Engineering | Inngest layer; replaces request-scoped `session-sync.ts` event surface |
| Episodic memory store with RLS-enforced tenant boundaries | Engineering | Per-founder pgvector; multi-turn (#1044) prerequisite |
| Quality telemetry on leader outputs (correctness scoring, false-assertion detection) | Engineering + Product | `domain-leader-false-status-assertions-20260323` is the smoking gun; runtime amplifies bad signal |
| Cross-domain priority synthesizer (Daily Priorities engine) | Product + Engineering | Home page MVP; no service today aggregates GH+Stripe+KB+community |
| `runtime-architect` agent | Engineering | Architectural decision class lacks sustained owner |
| Trust-tier policy engine | Legal + Engineering | Per-action-class autonomy needs declarative policy, not hardcoded `if` ladders |
| Multi-tenant secret custody at scale | Operations | Doppler covers Soleur infra only; per-tenant envelope encryption + KMS for BYOK |
| Per-tenant cost attribution + abuse controls | Operations | Runaway loop on one founder shouldn't bankrupt Soleur; kill-switch on cost spike |
| Brand collateral (Soleur Web Platform launch — no sub-brand) | Marketing | Positioning refresh, ICP doc, landing page, demo video, content calendar |
| DPA template, sub-processor page, breach runbook, AUP, audit-log schema | Legal | 9 must-have legal artifacts before paid launch |
| E&O / Cyber insurance broker relationship | Operations + Legal | $1-3M coverage before first paying user |
| Multi-turn continuity (#1044) fix | Engineering | Stateful per-(founder, domain, conversation) message history |

## User-Brand Impact

**Artifact:** Command Center server-side agentic runtime hosting long-running per-founder agents that execute against founder-owned credentials (Anthropic, Stripe, GitHub, Supabase, Doppler).

**Vector:** Three confirmed by the founder this session, all single-user-incident threshold:

1. **Cross-tenant data leak** — Founder A's KB / chat history / agent memory / BYOK keys leak to Founder B due to runtime bug or RLS bypass. Today's `SUPABASE_SERVICE_ROLE_KEY` use in `server/agent-runner.ts` is the live exposure.
2. **BYOK credential leak** — Long-running agent holds plaintext Anthropic/Stripe/etc keys in heap; runtime bug, log leak, or memory-dump exposes them. Brand-ending; founder financially harmed.
3. **Agent fires wrong action while founder sleeps** — Event-driven agent posts to wrong customer, sends wrong invoice, ships wrong deploy, deletes data. Founder cannot supervise; trust collapses on first incident.

**Brand-survival threshold:** `single-user incident`. One incident on any of the three vectors is brand-ending for a solo-founder-operated startup. Carries forward to plan Phase 2.6 unmodified.

**Mitigations (load-bearing for plan):**
- Per-invocation user-scoped Supabase JWT; service-role allowlisted to JWT-mint + audit only.
- Per-invocation BYOK lease in `AsyncLocalStorage`; audit row before each Anthropic call; zeroize on lease end; redaction allowlist extended in `cq-silent-fallback-must-mirror-to-sentry` to exclude key payloads.
- "Drafts everywhere, sends nowhere" trust default; external brand-critical actions require approve-every-time; money/legal/credentials require per-command ack (HR rule already enforced).
- Forensic audit log: WORM, hash-chained, 7-year retention; per-tenant cost attribution + kill-switch on spike; PagerDuty rotation.
- E&O/Cyber insurance ($1-3M) bound before first paying user.

**Plan-time gate:** `user-impact-reviewer` must sign off on plan before `/work`. Preflight Check 6 fires on sensitive paths under `apps/web-platform/server/**`, `supabase/migrations/**`, BYOK custody surfaces.
