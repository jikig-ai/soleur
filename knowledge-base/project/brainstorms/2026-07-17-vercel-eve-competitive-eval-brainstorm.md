---
date: 2026-07-17
topic: vercel-eve-competitive-eval
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
draft_pr: 6640
leaders: [cpo, cto, clo, cmo]
research: [repo-research-analyst, learnings-researcher]
---

# Brainstorm: Vercel Eve competitive / strategic evaluation

## User-Brand Impact

| Field | Value |
|-------|--------|
| **Artifact** | Soleur product substrate / agent-runtime positioning decisions involving Eve |
| **Vector** | Wrong adoption could lock founders onto Vercel-only agent paths, blur CaaS vs framework positioning, or process workspace PII through undeclared US sub-processors without HITL |
| **Threshold** | `single-user incident` |

## What We're Evaluating

[Vercel Eve](https://vercel.com/eve) (open-source filesystem-first TypeScript agent framework; npm `eve`; docs [eve.dev](https://eve.dev/docs); GitHub `vercel/eve`) against Soleur strategy.

Operator questions:

1. Is Eve only Vercel-tied, or usable with Claude Code / Grok Build?
2. Should Soleur adopt Eve as substrate or product component?
3. How does Soleur compare to Eve?
4. What should Soleur take from Eve?

## External floor (verified)

- **Category:** Production agent **framework** (“Next.js for agents”), not CaaS.
- **Authoring:** Directory = agent (`instructions.md`, `tools/`, `skills/`, `channels/`, `sandbox/`, `subagents/`, `schedules/`, evals).
- **Coding harnesses:** Scaffold and edit Eve apps; Eve is **not** a Claude Code / Grok Build runtime.
- **Sandbox:** Adapter backends — Vercel Sandbox, Docker, microsandbox, just-bash, custom; local `eve dev` is real.
- **Production deploy:** **Vercel-first**; multi-platform “on the way”; public beta under Vercel beta terms.
- **License snapshot:** Apache-2.0 OSS + beta commercial overlay when using Vercel’s product path (re-read live before any dependency).
- **Soleur has zero `eve` package dependency** (repo research confirmed).

## Why This Approach (consensus)

**Primary posture: steal patterns + monitor (Tier 4). Do not adopt Eve as Soleur’s runtime or identity.**

Rationale:

1. **Layer mismatch** — Eve builds deployable agent apps; Soleur is the AI company OS (domains, lifecycle, git KB, multi-harness plugin + cloud Concierge).
2. **~75–85% of Eve-like surface already exists** as a *different* layer (plugin + Concierge + Inngest + sandbox + `/go`) — confirmed by repo mapping.
3. **Porting Soleur skills to Eve is a rewrite**, not a dependency bump (harness adapter, workflow.js, worktrees, Agent SDK Concierge).
4. **Legal:** patterns-only avoids undeclared US sub-processor + beta $100 liability; production Vercel agent plane needs deeper review before any founder data.
5. **Roadmap:** Phase 4 validation focus; substrate shopping harms founder recruitment window.
6. **Learnings precedent:** external frameworks → audit primitives first (Self-Harness #6037 class); not greenfield re-platform.

## Key Decisions

| # | Decision | Owner lens |
|---|----------|------------|
| D1 | **Do not adopt Eve as core substrate**, Concierge replacement, or plugin runtime | CTO + CPO |
| D2 | **Primary posture = patterns-only**; secondary = monitor ecosystem | All leaders |
| D3 | Place Eve in competitive intel as **Tier 4 (frameworks)** next to CrewAI/LangGraph — **not** Tier 3 CaaS | CPO + CMO |
| D4 | **No co-branding** (“powered by Eve”, “build Eve agents with Soleur”) | CMO |
| D5 | **Optional isolated eng spike only** if a founder-visible gap requires it, with hard constraints: no shared workspaces, no prod traffic, no founder BYOK, synthetic data only, time-box + kill criteria | CTO + CLO |
| D6 | Patterns worth harvesting without dependency: explicit sandbox trust-boundary language; tool-level HITL metadata clarity; channel-adapter separation; eval-as-files discipline; directory-as-agent packaging clarity | CTO + CPO |
| D7 | Real Soleur gaps to fill **without** Eve: multi-channel durable *sessions* (Slack/Discord), productized connections UX, broader eval catalog — track as product backlog if prioritized | CTO (gap map) |
| D8 | Messaging firewall: **organization ≠ framework** (extend CrewAI playbook); refuse “agent framework” frame for Soleur | CMO |

## Answers to operator questions

### 1. Vercel-only or any harness?

| Layer | Reality |
|-------|---------|
| Authoring / local | Open-source; Docker/local sandbox; no Vercel project required for `eve dev` |
| Production | **Vercel-first** today |
| Claude Code / Grok | **Builders of Eve apps**, not runtimes *for* Eve; Eve does not replace multi-harness Soleur |

### 2. Should Soleur adopt Eve?

**No** as substrate or product identity. **Yes** as pattern source + Tier 4 monitor. Spike only under D5 constraints.

### 3. Comparison (layer table)

| Dimension | Soleur | Eve |
|-----------|--------|-----|
| Product type | Company-as-a-Service | Agent framework (npm) |
| ICP | Solo founders | Developers shipping production agents |
| Runtime | Claude Agent SDK Concierge + Claude/Grok harnesses | Eve loop + Workflow SDK sessions |
| Moat | Git KB, 8 domains, lifecycle, HITL, multi-harness | Durable multi-channel custom agents on Vercel gravity |
| Durability | Inngest (self-hosted; Cloud rejected ADR-030) | Workflow SDK / Vercel Workflows |
| Isolation | bubblewrap + canUseTool + path deny | Sandbox backends (adapter model) |

### 4. What to take

**Steal (no dep):** sandbox trust-boundary narrative; HITL as first-class tool property; channel adapters; eval packaging; filesystem-as-interface polish.

**Do not take:** npm `eve` as runtime of record; Vercel-only production path for tenant agents; beta terms as load-bearing for founder data.

## Research synthesis

### Repo mapping (12 Eve concepts)

~8 none gap, ~3 partial, ~1 partial→real (multi-channel agent sessions). Coverage **≈75–85%** as different layer. No `eve` in package trees.

### Learnings implications

- Audit-first / gap-map / smallest non-mutating increment (or no-adopt reframe).
- Port cost is carrier format + orchestration, not prose skills.
- Vendor-branded skill surface: lift clean or clean-room; never co-position on vendor marketing.
- Moat test remains KB + lifecycle depth, not harness surface parity with Eve.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Eve is a Tier 4 pattern-source/peer, not a CaaS competitor or safe substrate. Primary posture: steal patterns; monitor gravity; refuse re-platform during Phase 4. Founder value from Eve brand is null; risk of positioning confusion and opportunity cost is high.

### Engineering (CTO)

**Summary:** Eve and Soleur have incompatible cores (product-agent framework vs multi-harness coding OS + Concierge). Skills-on-Eve = rewrite. Primary: patterns-only; do-not-adopt as core. Residual isolation work (#5862/#5863) beats importing Eve. Vercel host would be a second control plane vs Hetzner+Inngest.

### Legal (CLO)

**Summary:** Apache-2.0 is fine for study; production path under Vercel beta + AI Product Terms + US primary processing is **patterns-only preferred**. Product runtime dependency needs deeper review (undeclared sub-processor, $100 liability, beta terminate-at-will). Always-on multi-channel PII → gdpr-gate mandatory if ever built. Disposition: PERMITTED for patterns/OSS synthetic eval; blocked for silent always-on PII.

### Marketing (CMO)

**Summary:** Eve = infrastructure for building agents; Soleur = assembled company. Highest risk is self-inflicted “framework” language. Monitor Tier 4; no battlecard/comparison page unless demand; no co-branding. Conditional framework-vs-org content after CrewAI template if prospects confuse categories.

## Capability Gaps

None for this assessment. Follow-ups are documentation (CI Tier 4 row) and optional product backlog items already named (channels, connections, eval breadth) — not Eve-shaped greenfield.

## Non-Goals / Explicitly deferred

- Rewriting Concierge or plugin pipelines on Eve
- Marketing claim that Soleur is multi-harness complete vs Eve multi-channel
- Full CI rescan (only add Eve row on next intake unless operator prioritizes)
- Time-boxed Eve spike (not opened unless founder-visible gap named)

## Open Questions (for operator)

1. Confirm **add Eve to Tier 4** on next CI pass (or do a small doc PR now on this branch)?
2. Fold Eve-derived pattern notes into Multica / harness backlog, or a separate “Tier 4 substrate patterns” issue?
3. Any **founder-visible** failure (durable multi-channel sessions, etc.) that should unlock a D5 spike?
4. Is Hetzner + multi-cloud independence non-negotiable for product story (CPO Q5)?

## Lane

`cross-domain` (USER_BRAND_CRITICAL triad + external-product CMO).

## Session Errors

None. Prior single-agent answer (session start) was incomplete; this document supersedes it with full leader + research fan-out.

## Operator reframe (2026-07-17, post-leader pass)

**Reframe (operator):** Stop comparing Eve *against* Soleur. Ask whether Soleur should build a **similar production layer inside Soleur** so *Soleur users* ship more securely and reliably — not whether to depend on Eve.

### Interpretation

| Misread | Better read |
|---------|-------------|
| “Should Soleur become an agent framework like Eve?” | **No** — wrong category for ICP messaging |
| “Should Soleur use Eve under the hood?” | **No** (leaders: patterns-only) |
| “Should Soleur productize Eve-*class* capabilities (durable, sandboxed, HITL, multi-channel, scheduled agents) for tenants?” | **Yes as investment framing** — this is mostly *already the Concierge + CP roadmap*, not a greenfield framework |

### Does a “similar layer” make sense?

**Yes — as finishing Soleur’s production agent *platform* for founders, not as shipping a second npm framework.**

Eve’s product insight is: agents that touch real systems need **production already built in** (isolation, durability, approvals, channels, evals). That insight applies *directly* to Soleur users running company work on `app.soleur.ai`. The research mapping shows Soleur already owns most of that *for itself*; the user-visible gap is **polish + productization of the remaining edges**, not inventing Eve.

### Two layers (do not conflate)

| Layer | Audience | Eve analog | Soleur status |
|-------|----------|------------|---------------|
| **L0 — Founder execution runtime** | Soleur tenants | Eve’s “batteries included production” | Concierge + sandbox + HITL + Inngest + BYOK — **invest here** |
| **L1 — DIY agent framework for builders** | Developers writing custom agents as code | Eve itself | **Do not productize** (wrong ICP; dilutes CaaS; recreates Tier 4) |

**Recommendation:** Build **L0 completeness** (secure shipping *for* Soleur users). Do **not** build L1 (“Soleur Framework” / Eve clone).

### What “more secure shipping for Soleur users” maps to (existing issues)

Roadmap / CI already named the Eve-class gaps as **tenant product work**, not framework R&D:

| Eve production primitive | Soleur tenant investment | Existing tracker |
|--------------------------|--------------------------|------------------|
| Human-in-the-loop approvals | Structured approval queue for write/send | [#4672](https://github.com/jikig-ai/soleur/issues/4672) (CP2) |
| Sandboxed untrusted work | Per-tenant FS isolation + bwrap TOCTOU close | [#5863](https://github.com/jikig-ai/soleur/issues/5863), [#5862](https://github.com/jikig-ai/soleur/issues/5862) |
| Multi-channel delivery | Business SaaS / inbox breadth | [#4673](https://github.com/jikig-ai/soleur/issues/4673) |
| Schedules / always-on work | Cross-system business automations | [#4674](https://github.com/jikig-ai/soleur/issues/4674) |
| Residual agent-**run** visibility (live session state, work log, intervene) | Open residual of [#2004](https://github.com/jikig-ai/soleur/issues/2004) after **Workstream** shipped *issue/task* kanban (not the same as live agent runs); chat tool chips + debug stream are partial only. Related open bridge: [#6010](https://github.com/jikig-ai/soleur/issues/6010) agents-as-teammates on Workstream |
| Product packaging of primitives | Multica → Command Center adaptations | [#6006](https://github.com/jikig-ai/soleur/issues/6006) |

**Sequencing already correct on roadmap:** CP1 → CP2 (HITL) before expanding external surfaces (CP4/CP3). Eve validates that order; it does not invent new work.

### What *not* to build (even under this reframe)

- A public “define your agent as a directory and deploy” framework product
- npm/`eve`-compatible tool registry for third-party agent authors
- Vercel-shaped multi-platform agent host as Soleur’s identity
- Replacing multi-harness plugin lifecycle with a generic agent OS

### Updated key decision (D9)

| # | Decision |
|---|----------|
| **D9** | Treat Eve as **inspiration for L0 tenant production completeness**, not as competitor or substrate. Investment = accelerate existing CP/sandbox/HITL/channel issues; **not** a new “Soleur Eve” framework layer. |
| **D10** | Track gap closure under umbrella epic **[#6641](https://github.com/jikig-ai/soleur/issues/6641)** — *L0 tenant production completeness* — linking #5862, #5863, #4672, #2004, #6006, #4674, #4673 (sequenced security/HITL before channels). |

### Open product questions under the reframe

1. Is the near-term priority **security of Concierge isolation** (#5862/#5863) or **operator UX for approvals** (#4672)?
2. Should “channels” mean **founder business surfaces** (email/Slack for company work) only, or also **customer-facing bots** the founder deploys?
3. Do we brand L0 completeness as “production agent platform” internally only, or ever in marketing (CMO: avoid framework language either way)?
