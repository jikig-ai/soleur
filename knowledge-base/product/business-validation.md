---
last_updated: 2026-06-14
last_reviewed: 2026-06-08
review_cadence: quarterly
owner: CPO
depends_on: []
---

# Business Validation: Soleur -- Company-as-a-Service Platform

## Problem

**Problem statement (solution-free):** Solo founders face a twofold problem. First, a capacity gap: one person cannot fill the roles of engineer, marketer, lawyer, operations manager, and product strategist simultaneously. Second, an expertise gap: even if they had the time, most technical founders do not know how to run a marketing department, draft enforceable contracts, or build a pricing strategy. The non-engineering work -- brand identity, legal compliance, pricing, operational logistics, product validation -- consumes the majority of a founder's time but receives almost none of the AI tooling investment.

**Current workarounds:**

- **Hire freelancers or agencies:** Expensive, slow, requires management overhead that solo founders are trying to avoid. A brand agency costs $5-15k; a lawyer costs $300-500/hour for basic documents.
- **DIY with templates:** Founders use generic templates (Stripe Atlas legal docs, Canva brand kits, spreadsheet expense trackers). These are better than nothing but produce generic output that does not compound -- next month's work starts from scratch.
- **AI chat for one-off tasks:** Ask ChatGPT to draft a privacy policy or brainstorm a tagline. No persistence, no cross-domain coherence, no institutional memory. The privacy policy does not know about the brand guide. The pricing strategy does not reference the competitive analysis.
- **Ignore non-engineering work:** Ship first, worry about brand/legal/ops later. This is the most common approach and creates compounding debt that becomes harder to address as the company grows.

**Pain severity:** High for solo founders who take their companies seriously. The pain is chronic rather than acute -- the cumulative friction of being a one-person company that needs the capabilities of a 20-person organization. The capacity gap is felt daily; the expertise gap is felt whenever the founder encounters a domain they have never operated in before.

**Assessment:** PASS [Re-validated 2026-06-08]. The problem is real, structural, and clearly articulated independent of any solution. It is not a tooling gap in one domain -- it is the absence of an integrated AI workforce that can operate across domains the way a human organization does. The 2026 market data reinforces the framing: U.S. solopreneurs now number ~29.8M generating ~$1.7T revenue, solo-founded startups rose from 23.7% to 36.3% of new companies since 2019, and a full solopreneur AI stack costs ~$3-12k/year (a 95-98% reduction vs. equivalent headcount) -- evidence that "one person operating at organization scale" is now the structural norm, not a fringe aspiration ([Fortune 2026-05-18](https://fortune.com/2026/05/18/solo-founders-ai-automation-entire-teams-entrepreneurs/), [solopreneur statistics 2026](https://autofaceless.ai/blog/solopreneur-statistics-2026)). Third-party market figures are flagged as unverified aggregator data, but the trend direction is corroborated across multiple independent 2026 sources.

## Customer

**Target customer profile:**

- **Role:** Solo founders building companies, not just shipping code. Technical builders who think in terms of businesses, not just products.
- **Stage:** Initially technical solo founders across all stages (pre-revenue through scaling). Eventually non-technical founders, but the beachhead is technical.
- **Company size:** One person. The "company of one" who wants to operate at the scale of a funded startup without hiring.
- **Industry:** SaaS, developer tools, creative businesses, consulting-turned-product -- any domain where one person builds and sells.
- **Behavior:** Already using AI coding assistants (Claude Code, Cursor, Windsurf) as their primary development interface. Frustrated that AI helps with code but not with the other 70% of running a company.
- **Frequency:** Daily. These founders interact with their company (not just their codebase) every working day.

**Reachable customer examples:**

The user can name 2-3 real contacts who fit the profile, falling short of the 5-person threshold. However, the market thesis is supported by strong external signals:

- Naval Ravikant's prediction of AI-enabled solo billion-dollar companies
- Dario Amodei's projections on AI capability expansion
- Solo founder growth statistics (23.7% to 36.3% of new companies)
- Active communities (IndieHackers, Claude Code Discord, Twitter/X solopreneur networks)

**Assessment:** CONDITIONAL PASS [Re-validated 2026-06-08; was CONDITIONAL PASS 2026-03-22]. The customer segment is specific, passionate, and reachable. The risk is unchanged and still real: the definition is broad (technical solo founders across all stages) and named individual contacts remain below the 5-person threshold. What changed since 2026-03-22 is the reachability mechanism, not the segment: the deployed web platform (app.soleur.ai) now ships a Buttondown-backed waitlist and an invite surface, converting "the user can name 2-3 contacts" into an instrumented demand-capture funnel. The segment definition still needs a tighter beachhead, and a list of named contacts is not the same as a list of captured signups -- so the condition holds. External 2026 market signals (29.8M solopreneurs; 36.3% solo-founder share) confirm the addressable market exists at scale; they do not substitute for a named, reachable initial cohort.

**User research update (2026-03-22):** 5+ conversations with solo founders revealed a critical beachhead assumption failure. The original recommendation was to narrow to "Claude Code power users who have already pushed beyond coding into broader workflows." However, the majority of founders interviewed do not use Claude Code at all. They want AI business operations but through a visual UI accessible from any device -- not through a terminal-based plugin. The beachhead must be redefined around the problem (running a company solo) rather than the tool (Claude Code). See Gate 4 Demand Evidence for full findings.

## Competitive Landscape

The competitive landscape spans six tiers, from platform-native competition to loosest alternatives.

**Tier 0: Platform-native competition (existential threat)** [Added 2026-02-25]

| Competitor | Overlap | Differentiation from Soleur |
|-----------|---------|---------------------------|
| [Anthropic Cowork Plugins](https://claude.com/blog/cowork-plugins-across-enterprise) | 11 first-party plugins across productivity, sales, support, product, marketing, legal, finance, data, enterprise-search, bio-research, and meta-tooling. Enterprise connectors (Google Workspace, Docusign, Apollo, Clay, FactSet, LegalZoom). Private plugin marketplace with admin controls, per-user provisioning, OpenTelemetry tracking. | Cowork templates are stateless and siloed per domain -- no compounding knowledge base, no cross-domain coherence, no workflow lifecycle orchestration (brainstorm > plan > implement > review > compound). Templates are nouns; Soleur's workflows are verbs. However, Anthropic controls the model, the API, the distribution surface, and the pricing. 5 of 8 Soleur domains face direct first-party competition. Engineering workflow is the notable gap in Anthropic's offering. See `knowledge-base/project/brainstorms/2026-02-25-cowork-plugins-risk-analysis-brainstorm.md` for full analysis. |
| [OpenAI Codex](https://developers.openai.com/codex/) [Added 2026-06-08 scan] | IDE-agent + desktop Computer Use (macOS) + multi-agent parallel workflows + memory preview + scheduled long-running tasks + 90+ plugins. **Sites** (preview): create/deploy/inspect websites, dashboards, internal tools, and web apps hosted by OpenAI -- directly overlapping the Lovable/NanoCorp landing-page-deploy wedge. Amazon Bedrock support. | Platform-native: OpenAI controls the model, API, and IDE surface. Codex now spans IDE-agent, desktop-agent, plugin ecosystem, persistent memory, scheduled autonomy, AND site deployment -- a founder on the OpenAI stack has few reasons to add a Claude-stack product, and Soleur's Anthropic lock-in becomes a distribution liability if target founders drift to OpenAI. No compounding cross-domain knowledge base, no business-domain agents, no workflow lifecycle. April 2026 shift to API-token billing; Pro 2x promo expired May 31 (effective capacity halved June 1 at $100/mo). |

**Tier 1: Claude Code plugins (closest substitutes)**

| Competitor | Overlap | Differentiation from Soleur |
|-----------|---------|---------------------------|
| [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) [Added 2026-06-08 scan] | Closest structural match. 337 skills (up from 235 in April), 5,200+ stars, 30+ agents, 70+ commands, 12+ AI-tool compatibility (Claude Code, Codex, Gemini CLI, Cursor + 8 more). Domains: engineering, marketing, product, compliance, C-level advisory, research, business ops, finance, productivity. Explicit **Solo Founder persona** + 6-week launch framework; cross-domain orchestration protocol; self-improving/auto-memory skill. | Claims all three Soleur moats (multi-domain breadth, cross-domain orchestration, self-improving memory) and runs in 12+ tools vs. Soleur's 1 -- the "more agents/domains" framing is no longer defensible. Soleur's remaining moats: the full workflow lifecycle with enforced stage-to-stage handoffs (brainstorm > plan > work > review > compound), the integrated branded CaaS product (this is a skills library, not a product), git-tracked knowledge-base files as first-class artifacts, and named persona-agents wired into the lifecycle. Distributed through the same Claude Code channel Soleur depends on. |
| [Deep Trilogy](https://pierce-lamb.medium.com/the-deep-trilogy-claude-code-plugins-for-writing-good-software-fast-33b76f2a022d) | Plan-first engineering workflow | Engineering only -- no marketing, legal, ops, or product domains. No compounding knowledge base across sessions. |

**Tier 2: No-code AI agent platforms**

| Competitor | Approach | Differentiation from Soleur |
|-----------|----------|---------------------------|
| [Lindy.ai](https://lindy.ai) | No-code AI agent builder for business workflows (email, scheduling, sales) | Horizontal agent builder, not integrated into the development workflow. Agents are standalone, not part of a unified organization with shared memory. |
| [Relevance AI](https://relevanceai.com) | AI workforce platform with agent teams for sales, support, and research. Free (200 actions/mo) / Pro $29 / Team $349 / Enterprise; Actions + Vendor-Credits (BYO-API-key) pricing. **Funding: $37.2M total incl. a $24M Series B led by Bessemer** (Insight Partners, King River participating); Sydney-based. [Updated 2026-06-08 scan] | Enterprise-focused, sales-heavy. No engineering domain. Not designed for solo founders. Well-funded category validator -- the "AI workforce" framing rhymes with Soleur's "AI organization," but the ICP and integration model differ. |

**Tier 3: Company-as-a-Service / full-stack business platforms**

| Competitor | Approach | Differentiation from Soleur |
|---|---|---|
| [SoloCEO](https://soloceoai.com) | AI executive board: 12 AI board members (CFO, CMO, COO, etc.) analyze business simultaneously. $2,000 diagnostic, beta 2026. | Closest CaaS competitor. Advisory-only (diagnostic + recommendations), not operational. One-time analysis, not an ongoing workflow. No engineering domain, no compounding knowledge base. |
| [Tanka](https://tanka.ai) | AI co-founder platform with persistent memory, smart replies, landing page generation. Integrates Slack, WhatsApp, Gmail, Notion. | Memory-native like Soleur, but communication-centric. No engineering workflow, no legal domain, no structured knowledge base that compounds across business domains. |
| [Polsia](https://polsia.com) [Updated 2026-06-08 scan] | Autonomous AI company-operating platform built on Claude Agent SDK. Role-based agents (CEO, Engineer, Growth Manager) run nightly autonomous cycles of development, marketing, operations, and outbound sales. ~$49/mo base (one nightly task + on-demand credits) **plus a 20% revenue share**. **Funding: $30M raised at a $250M valuation (Sound Ventures, May 2026)** -- the verifiable signal. Self-reported traction is contradictory across sources (~$10M ARR / 7,600 customers / 85% retention in newer claims vs. earlier $1.5M ARR / 2,000+ companies vs. a ~$450K read) -- treat metrics as marketing, not verified. | Cloud-hosted, fully autonomous (no human-in-the-loop). Covers 5+ domains (engineering, marketing, ops, support, sales outreach) vs. Soleur's 8. No legal, finance, or product domains. No structured knowledge base that compounds across domains. No Claude Code integration. Proprietary, closed-source. Autonomous output quality reportedly basic. The 20% revenue share is an aggressive monetization wedge Soleur has not matched. Shares Soleur's Anthropic platform dependency. The $30M round confirms the autonomous-CaaS thesis is venture-validated at scale, not fading. |
| [NanoCorp](https://nanocorp.so) [Added 2026-06-08; reconciled 2026-06-08 scan] | One-prompt autonomous AI company (parent: Phospho Inc., Wilmington DE): an agent names the product, defines the ICP, writes copy, deploys a Vercel landing page, creates Stripe products + pricing, queues outreach, and runs scheduled agents -- toward "maximize revenue, avoid bankruptcy" with no human in the loop. (Google Search Ads is listed "Coming Soon" on the site, NOT yet live.) YC W24, solo founder, San Francisco. Free $0 (3 lifetime credits, 1 company) / Founder $30/mo (credit-based, scalable), both with a 20% revenue-withdrawal fee. ARR claims are contradictory/unverified ("$740k in 33 days" vs. newer "$193k in 3 days" vs. a ~$264 user-revenue leaderboard) -- treat as marketing. | Closest analog: Polsia. Founder-in-the-loop (Soleur) vs. no-human-in-the-loop. Narrow go-to-market revenue engine (landing page + Stripe + outreach; ads pending) vs. Soleur's 8 domains -- no engineering code-review/deploy, legal, finance, product-strategy, or support. Cloud-hosted proprietary state vs. git-tracked compounding knowledge base. The 20% revenue-withdrawal fee is an aggressive monetization wedge (same class as Polsia's revenue share) Soleur has not matched. Shares Soleur's Anthropic-platform dependency. |
| [Cofounder](https://cofounder.co) [Added 2026-06-14 scan] | Full-stack agent-company platform by **The General Intelligence Company of New York** (CEO Andrew Pignanelli). Coordinating agent departments -- engineering, sales/GTM, marketing, design, finance, legal (LLC incorporation + bank-account setup), ops, support -- with managers and shared context. **Human-in-the-loop approval gates** on dangerous/binding actions. Extensible via MCP, custom APIs, custom skills, or an entire custom codebase. Work modeled as reusable **"Flows"** along a guided idea->$1B roadmap; three-tier memory with **"sleep-time compute"** background consolidation (ingests Gmail/Notion/Linear/Slack). **Funding: $8.7M seed led by Union Square Ventures (Dec 2025; Acrew, Compound).** Pricing: 7-day trial / Pro $20/mo (usage-included; domain + hosting, agent inboxes, preview envs, project "graduation") / Team $50/mo coming soon (multiplayer, SOC 2). Usage-based overage; **no revenue share** -- founders can "graduate" a project to own the provisioned GitHub/Supabase/Vercel. | **Closest product-level match in Tier 3.** Unlike Polsia/NanoCorp it converges *toward* Soleur: founder-in-the-loop HITL (not full autonomy), 8-department breadth, MCP/custom-codebase extensibility, and no-lock-in -- neutralizing three differentiators Soleur uses against the rest of the tier. Soleur's moats that hold specifically vs. Cofounder: the **git-tracked, verbatim, founder-readable KB in the founder's own repo** (Cofounder's memory compresses/distills lossily into proprietary cloud), the **named-artifact lifecycle with explicit review + compound stages**, and **local-first execution** (caveat: founders want a visual UI -- a liability as much as a moat). On no-lock-in Soleur is structurally ahead (`provision-github` creates founder-owned repos from day one). USV funding + a real memory system raise the execution bar. See `competitive-intelligence.md` Tier 3 (2026-06-14) + feature-gap issue #5292. |
| [Paperclip](https://paperclip.ing/) | Open-source orchestration platform for zero-human companies. MIT-licensed, self-hosted (Node.js + React). Agent-runtime-agnostic org chart with budget controls, heartbeat scheduling, governance, and audit logs. 74,000+ GitHub stars (verified 2026-07-20). | Infrastructure-layer orchestration, not domain-specific intelligence. Does not provide agents -- users bring their own (Claude, OpenClaw, Codex, etc.). No compounding knowledge base, no cross-domain coherence, no workflow lifecycle (brainstorm/plan/work/review/compound). Orchestration framework, not a Company-as-a-Service product. Complementary to Soleur rather than directly competitive. |
| [Lovable.dev](https://lovable.dev) | AI full-stack React app builder. $300M+ ARR, $6.6B valuation. | Website/app generation only. No legal, marketing, ops, or finance domains. No institutional memory across sessions. |
| [Bolt.new](https://bolt.new) | AI web app builder with framework flexibility. ~$100M ARR projected 2025. | Fastest to prototype but engineering-only. No cross-domain agents or compounding knowledge base. |
| [v0.app](https://v0.app) | Vercel's AI Next.js app generator. Agentic by default, database integrations (Snowflake, AWS). | Highest code quality but engineering-only. No business operations, no multi-domain workflow. |
| [Replit Agent](https://replit.com) | Autonomous coding agent with 200-minute sessions. $20/month Core, $100/month Pro. Cloud-hosted. $400M Series D at $9B valuation. | Most autonomous for coding but no marketing, legal, or product domains. Cloud-hosted, not local-first. |
| [Notion AI 3.3](https://notion.com) | Autonomous AI agents across workspace (docs, databases, projects). Custom Agents with 21,000+ in beta. Multi-model (GPT-5.2, Claude Opus, Gemini, MiniMax M2.5). Credit-based pricing after May 2026. | Broadest platform but shallow per domain. No engineering workflow (code review, deployment), no legal, no structured business validation. Workspace tool, not a business operating system. |
| [Systeme.io](https://systeme.io) | All-in-one marketing platform: funnels, email, courses, websites. $17/month. | Marketing and sales only. No engineering, legal, or product domains. Workflow automation, not AI intelligence. |
| [Stripe Atlas](https://stripe.com/atlas) | Delaware C-corp formation + banking + payments. $500 one-time. | Legal formation only. One-time event, not ongoing operations. No AI, no agents, no compounding knowledge. |
| [Firstbase](https://firstbase.io) | Global company formation with banking, payroll, accounting integrations. | Broader than Atlas but still formation-focused. No engineering, marketing, or product domains. No AI workflow. |

**Tier 4: AI agent frameworks**

| Competitor | Approach | Differentiation from Soleur |
|-----------|----------|---------------------------|
| [Crew AI](https://crewai.com) [Updated 2026-06-08 scan] | Role-playing multi-agent orchestration framework for building AI teams. 47.8k GitHub stars, 27M+ PyPI downloads, ~2B executions/12mo, 100k+ certified devs, used by ~half the Fortune 500. **Funding: $18M Series A (Insight Partners; Andrew Ng, Dharmesh Shah angels).** CrewAI AMP enterprise suite. | Framework, not a product. Requires significant setup. No built-in business domains, no compounding KB, no lifecycle. But it is the de-facto enterprise multi-agent standard -- a technical founder could build a Soleur-shaped system on top; Soleur's value is the assembled, opinionated, domain-loaded product. Most likely framework to grow upward into a product -- monitor for opinionated domain packs. |
| [AutoGPT / AgentGPT](https://agentgpt.rber.dev) | Autonomous AI agents that chain tasks | General-purpose autonomy, not domain-specific. No institutional memory, no knowledge base that compounds. |

**Tier 5: DIY stack (AI coding tools used individually)**

| Competitor | Platform | Overlap |
|-----------|----------|---------|
| [Cursor](https://cursor.com) + Composer | IDE | Project conventions + multi-file orchestration. IDE-native. Engineering only. |
| [Windsurf](https://windsurf.com) + Cascade | IDE | Agentic IDE with built-in workflow automation. Engineering only. |
| [Aider](https://aider.chat/) | CLI | Git-aware AI coding. Engineering only, no multi-domain agents. |

**Structural advantages:**

1. **Compounding knowledge base:** Every domain feeds a shared institutional memory that persists across sessions. The brand guide informs marketing content, the legal audit references the privacy policy, the business validation draws on the competitive landscape. This cross-domain coherence is not possible when using separate tools for each function. The 100th session is dramatically more productive than the 1st.
2. **Full-stack 8-domain integration:** Engineering, marketing, legal, operations, product, finance, sales, and support agents share context within a single workflow. Competitors either do engineering well but nothing else, or do business automation well but not engineering.
3. **Operational continuity vs. one-time diagnostics:** SoloCEO and Stripe Atlas provide point-in-time outputs (a diagnostic report, incorporation papers). Soleur operates continuously -- agents learn from prior decisions and cross-domain coherence deepens over time.
4. **Full-domain coverage vs. partial overlap:** Every CaaS competitor covers 1-3 domains. Lovable/Bolt/v0 cover engineering. Systeme.io covers marketing/sales. Tanka covers communication. SoloCEO covers advisory across domains but not execution. Only Soleur covers all 8 domains as an integrated operating system.

**Vulnerabilities:**

1. **Platform dependency -- PARTIALLY MATERIALIZED (2026-02-25).** Anthropic has built multi-domain capabilities -- not into Claude Code directly, but into Cowork (their web/desktop product). 11 first-party plugins cover 6+ business domains. The original mitigation ("Soleur's value is in curated agent behaviors and accumulated knowledge") is partially validated: Cowork templates are stateless with no compounding knowledge base. But the mitigation is partially invalidated: Cowork's enterprise connectors (Google Workspace, Docusign, FactSet) and cross-app context make "curated agent behaviors" less differentiating when the platform has native access to real data sources. The revenue plan (standalone web dashboard at $49-99/month) is directly threatened -- see Tier 0 above and brainstorm `2026-02-25-cowork-plugins-risk-analysis-brainstorm.md`.
2. **Breadth vs. depth trade-off:** 65+ agents across 8 domains means each domain gets fewer resources than a dedicated tool. Mitigation: The integration IS the product -- a mediocre-but-connected marketing agent is more valuable to a solo founder than an excellent-but-isolated marketing tool. [Updated 2026-02-25]: Anthropic is now commoditizing horizontal domain breadth. The differentiation axis must shift from domain count to orchestration depth and compounding knowledge.
3. **Revenue model collision (2026-02-25).** The hosted web platform revenue plan (issue #297) faces a distribution asymmetry problem. Anthropic controls the surface, the model, and the marketplace. The pricing math collapses when the comparison set shifts from "Soleur vs. hiring an agency" to "Soleur's hosted platform vs. Anthropic's free bundled templates." See brainstorm for strategic options (knowledge infrastructure pivot, multi-platform, ride Cowork distribution).

**Assessment:** CONDITIONAL PASS [Updated 2026-03-22, was PASS]. The six-tier competitive landscape validates the thesis but reveals a Tier 0 threat that did not exist at prior assessment. Anthropic's Cowork Plugins represent platform-native competition across 5 of 8 Soleur domains. The structural advantages (compounding knowledge, cross-domain coherence, workflow orchestration) remain genuine moats -- Cowork templates are stateless and siloed. However, the revenue model assumption (standalone web dashboard) is directly challenged. The competitive assessment now requires distinguishing between the thesis (valid) and the revenue plan (threatened). Engineering workflow remains Soleur's strongest differentiated position -- Anthropic has no first-party engineering plugin.

**Delivery format shift (2026-03-22):** User research confirms a broader competitive dynamic -- solo founders compare Soleur not just against other CLI tools but against any accessible business automation surface. Polsia ($29-59/month, 2,000+ companies) and Notion AI (35M+ users, custom agents) deliver through web/mobile interfaces. Founders explicitly rejected CLI/plugin delivery in favor of visual dashboards and cross-device access. The competitive question is shifting from "which agent platform has the best capabilities?" to "which agent platform is accessible where founders actually work?"

**Tier-model refresh (2026-06-08):** competitive-landscape section refreshed against the full all-tier (0–5) `/soleur:competitive-analysis` scan (source: `knowledge-base/product/competitive-intelligence.md`, `last_reviewed: 2026-06-08`). Changes: promoted **OpenAI Codex** to Tier 0 (Sites preview moves OpenAI into landing-page/app deployment — the Lovable/NanoCorp wedge); added **alirezarezvani/claude-skills** to Tier 1 (337 skills, 12+ tools — closest structural match, "more agents/domains" framing no longer defensible); reversed the stale **Polsia** figures ($1.5M ARR/2,000 companies → $30M @ $250M raise, contradictory ARR claims); added funding context for **Relevance AI** ($24M Series B / $37.2M total) and **Crew AI** ($18M Series A). Scope: competitive landscape only — Problem/Customer/Demand/Business-Model sections and the CONDITIONAL PASS verdict were not re-validated this pass and continue to hold from 2026-03-22. Self-reported competitor metrics are flagged as marketing/unverified throughout.

**Tier 3 addition (2026-06-14):** Added **Cofounder** ([cofounder.co](https://cofounder.co)) to Tier 3 — The General Intelligence Company of New York, **$8.7M seed led by Union Square Ventures** (Dec 2025). The closest product-level match to Soleur in the landscape: it converges *toward* Soleur (HITL approval gates, 8-department breadth, MCP/custom-codebase extensibility, sleep-time-compute memory, no-rev-share + ownership graduation), narrowing Soleur's durable contrast to the verbatim git-tracked KB in the founder's own repo, the named-artifact review/compound lifecycle, and local-first execution. Targeted single-competitor addition mirroring the source `competitive-intelligence.md` 2026-06-14 intake (`last_reviewed` unchanged — no full re-validation of other sections). Feature-gap output filed: background KB consolidation (#5292).

## Demand Evidence

**Direct demand signals:**

- 5+ problem interviews with solo founders (2026-03-22). See user research finding below. No new external interviews have been logged since; this count is unchanged at re-validation.
- Soleur is in active daily use by its creator for running a real company. The "dogfooding" signal is genuine -- the creator uses all domains and has iterated through 5,000+ merged PRs (latest merged PR #5044 as of 2026-06-08; ~2,350 commits on main). [Re-validated 2026-06-08 — was "420+ merged PRs"]
- The plugin is published to the Claude Code registry and installable via `claude plugin install soleur`.
- **[New 2026-06-08] A standalone web platform is deployed to production at app.soleur.ai** with a public waitlist (Buttondown-backed, rate-limited) and a waitlist-first conversion funnel on the marketing site (PRs #1139/#1140, #1141/#1142, #5028, #5035). This is the demand-capture surface the 2026-03-22 research said was "REQUIRED" -- it now exists and is instrumented. **However, no waitlist-signup count, activation, or retention data has been recorded in this document; the surface exists, the captured-demand numbers do not yet.**

**User research finding (2026-03-22):** 5+ conversations with solo founders surfaced three consistent themes:

1. **Plugin delivery rejected.** Founders want a visual UI with dashboards, not a CLI plugin. The plugin model assumes the user already lives in Claude Code -- most don't. Even technical founders want a standalone product accessible from any device.
2. **Claude Code not in their stack.** The majority of interviewed founders do not use Claude Code as their primary development interface. They use Cursor, VS Code with Copilot, or no AI coding tool at all. The plugin distribution channel reaches a fraction of the target market.
3. **Standalone product expected.** Founders want to access their AI organization from a browser or mobile device -- checking on agent work during commutes, reviewing dashboards between meetings. A terminal-only product is incompatible with how they actually work.

**What this validates:** The core thesis (solo founders need AI business operations beyond coding) resonated strongly. Every founder described multi-domain pain unprompted. The problem is real and acute.

**What this invalidates:** The delivery mechanism. A Claude Code plugin is the wrong vehicle for reaching the target market. The product must be accessible as a standalone web/mobile application, not embedded in a developer tool that most target customers don't use.

**Indirect demand signals:**

- Naval Ravikant's podcast discussion of AI-enabled solo billion-dollar companies -- cultural validation of the thesis at the highest level.
- Dario Amodei's predictions on AI capability trajectories -- technical validation of the underlying assumption.
- Solo founder market growth data (23.7% to 36.3% of new startups; ~29.8M U.S. solopreneurs, ~$1.7T revenue) -- structural trend validation, corroborated across multiple independent 2026 sources ([Fortune](https://fortune.com/2026/05/18/solo-founders-ai-automation-entire-teams-entrepreneurs/), [PYMNTS](https://www.pymnts.com/artificial-intelligence-2/2026/the-one-person-billion-dollar-company-is-here/)). [Re-validated 2026-06-08]
- The autonomous-CaaS / AI-agent-workforce category is now venture-validated at scale, not fading: agentic-AI startups raised ~$2.8B in H1 2025 alone ([Business Standard / Prosus](https://www.business-standard.com/companies/start-ups/agentic-ai-startups-attract-2-8-billion-vc-funding-2025-prosus-125080501059_1.html)), and direct thesis-competitors are funded -- Polsia ($30M @ $250M, May 2026), Relevance AI ($37.2M total / $24M Series B), CrewAI ($18M Series A), Lovable ($6.6B), Replit ($9B). Per `competitive-intelligence.md` (2026-06-08), this confirms market demand for the category while raising competitive intensity. Self-reported competitor ARR/customer figures are flagged unverified throughout. [Updated 2026-06-08 — supersedes the prior "Lindy/Relevance/Crew raising funding" line with the post-scan funding picture]
- Claude Code Discord has active discussions about extending AI beyond coding into broader business workflows.
- Real-world existence proof of the "one-person company at scale" thesis: solo-founder firms reaching eight- and nine-figure revenue with AI tooling and no employees are now documented in mainstream press (e.g. Medvi). Cultural/market validation of the ceiling Soleur targets; not Soleur-specific demand. [Added 2026-06-08]

**What is missing:** [Re-validated 2026-06-08 — the delivery-surface gaps are closed; the captured-demand gaps remain open]

- No evidence of external users (beyond the creator) actively using Soleur across multiple domains. **Still open.**
- Only 5+ customer discovery conversations -- at the minimum recommended for problem validation, not beyond it; no new external interviews logged since 2026-03-22. **Still open** (the 10+ target is unmet).
- No data on waitlist-signup counts, web-platform activation, or retention rates. The instrumentation surface now exists (waitlist API, Plausible goals); the recorded numbers do not. **Partially advanced** (surface built, metrics unmeasured).
- No testimonials or case studies from external users testing the full-organization hypothesis. **Still open.**
- No external user has been recorded asking to be notified when a paid version exists, or offering to pay early. The waitlist is the mechanism to capture exactly this signal; no captured-signal data is in this document yet. **Partially advanced** (capture surface live, signal uncounted).

> WARNING: Kill criterion still applies at Gate 4 [Re-validated 2026-06-08] -- user chose to proceed. Direct external-customer validation remains thin: 5+ interviews and zero recorded external active users. The delivery surface that the 2026-03-22 research flagged as the blocker (a web-accessible product) has now been built and deployed -- a genuine status change -- but building the surface is not the same as proving demand through it. The strong external signals (market trends at scale, agentic-AI funding, real one-person-company existence proofs) provide directional confidence but do not substitute for measured signups, activation, and willingness-to-pay through the new platform.

**Assessment:** FLAG [Re-validated 2026-06-08; was FLAG 2026-03-22]. The problem resonates (5+ founders described multi-domain pain unprompted) and the delivery mechanism is no longer hypothetical -- the web platform is deployed. The blocking question has therefore moved one step downstream: from "will founders adopt a web-based version?" (the surface now exists to answer this) to **"are founders actually signing up for, activating in, and paying through the deployed platform?"** -- which remains unmeasured in this document. The FLAG holds because the demand-evidence bar is captured external behavior, and the captured numbers are still absent. The next step is no longer "build the web surface" (done) but "instrument and report the funnel: waitlist conversion, activation across 2+ domains, and willingness-to-pay."

## Business Model

**Current model:** Free and open-source (Apache-2.0 license). No revenue.

**Revenue model direction:** Leaning toward a hybrid model -- free self-hosted plugin (open source core) with a paid hosted platform / managed service. The exact model is under active exploration (GitHub issue #287 exists to brainstorm this). Options being considered:

| Model | Feasibility | Alignment |
|-------|------------|-----------|
| **Hosted platform / managed service** | Medium-high. Cloud-synced institutional memory, managed agents, team collaboration. | Strong. Natural extension of the knowledge base as a compounding asset. |
| **Freemium domain tiers** | Medium. Free engineering domain, paid marketing + legal + ops + product domains. | Strong. Non-engineering domains are the differentiator and the value users cannot get elsewhere. |
| **Managed AI org service** | Medium. Concierge onboarding: set up your AI organization, configure domains, seed knowledge base. | Strong for early adopters. Does not scale, but validates willingness to pay. |
| **Enterprise licensing** | Low priority. Multi-seat, private hosting, custom agents. | Weak alignment with solo founder target. Defer until adoption proves otherwise. |

**Competitor pricing context:** [Re-validated 2026-06-08 against `competitive-intelligence.md`]

- Lindy.ai: Free 400 credits/mo; Starter $19.99 / Pro $49.99 / Business $299 -- usage-based credits (1-3/task, 10/task advanced)
- Relevance AI: Free (200 actions/mo) / Pro $29 / Team $349 / Enterprise; split Actions + Vendor-Credits (BYO-API-key)
- Cursor: Hobby $0 / Pro $20 / Pro+ $60 / Ultra $200 (Composer 2.5, cheap-frontier per-token economics)
- Polsia: $49/mo + **20% revenue share**; NanoCorp: Free / $30/mo + **20% revenue-withdrawal fee** -- a 2-player aggressive-monetization pattern Soleur has not matched
- Most Claude Code plugins / skill libraries (incl. alirezarezvani/claude-skills): Free/open-source

**Market pricing shift (2026-06-08):** The entire Tier 0 IDE/agent layer repriced to metered/credit billing in the same window -- GitHub Copilot "AI Credits" (June 1, with reported 10-50x agentic bill spikes and public backlash), OpenAI Codex API-token billing + promo expiry, Cursor dollar-bucket, Windsurf quotas (+33% Pro), Notion Custom Agents now credit-metered and Business/Enterprise-only (evicting the free/Plus solo-founder long tail). This is both a positioning opening (Soleur's git-native, predictable-footprint model contrasts with resented metered billing) and a constraint (Soleur's own hosted pricing will live in this same metered-cost reality, so the message is "predictable + you own your memory," not "free"). Source: `competitive-intelligence.md` Tier 0/Tier 3 takeaways.

**Willingness-to-pay hypothesis:** Solo founders already pay $20-40/month for AI coding tools, and a full solopreneur AI stack now runs ~$3-12k/year ([solopreneur statistics 2026](https://autofaceless.ai/blog/solopreneur-statistics-2026)) -- a budget that exists and is growing. If Soleur delivers the value of a marketing agency ($5k+), a legal advisor ($300/hour), and an ops manager -- even at 10% of that value -- a $49-99/month price point is justified. **Still no direct evidence of willingness to pay** -- no recorded paid conversions or pre-orders through the deployed platform. [Re-validated 2026-06-08]

**Assessment:** CONDITIONAL PASS [Re-validated 2026-06-08; was CONDITIONAL PASS 2026-03-22]. The business model is still plausible but uncommitted -- no published price, no revenue model decision, no recorded willingness-to-pay. What changed is that the cost-structure precondition the model depends on is no longer hypothetical: the hosted platform exists (see below), so "the platform IS the product" is now a shipped fact, not a planning statement. The freemium thesis (open-source core + paid hosted platform with non-engineering domains as the differentiator) is still the leading path, and monetization should still follow measured adoption rather than precede it. The condition holds because the revenue model remains undecided and unvalidated.

**Cost structure implication [Re-validated 2026-06-08; was 2026-03-22 forward-looking]:** The 2026-03-22 note framed cloud infrastructure, API costs per user, frontend engineering, and authentication as "table stakes -- not optional enhancements" that the platform pivot would require. **These are now built, not pending:** apps/web-platform is a deployed Next.js 15 app (Supabase auth + 183 migrations, Claude Agent SDK runners, Terraform infra on Hetzner/Cloudflare, Sentry observability, a live deploy pipeline, branded email via Resend/SES) serving app.soleur.ai. The business-model question therefore shifts again: from "the platform IS the product" (2026-03-22 prediction) to **"the per-user API/compute cost of the deployed runners must be modeled against a price point before monetizing"** -- a unit-economics question the metered-billing market shift makes urgent. Mobile remains unbuilt; the web surface is responsive/PWA-capable, not native.

## Minimum Viable Scope

**Core value proposition to test:** Can a solo founder use Soleur's multi-domain AI agents to actually run a company -- not just write code?

**Two "aha moments" that prove the breadth thesis:**

1. **End-to-end feature lifecycle across domains:** A founder brainstorms a feature (product), plans it (engineering), implements it (engineering), reviews legal implications (legal), generates launch content (marketing), and ships it -- all within one integrated workflow where each step has context from the previous ones.
2. **Cross-domain knowledge flow:** A decision made in one domain automatically informs others. The brand guide shapes marketing content. The competitive analysis informs product validation. The legal audit references the privacy policy. The knowledge base compounds across domains, not just within them.

**Why breadth IS the minimum scope:**

The Company-as-a-Service thesis requires demonstrating that an integrated AI organization across multiple domains is more valuable than separate tools for each domain. If the MVP were reduced to just the engineering workflow, it would test a different hypothesis entirely -- "does structured AI coding help?" -- which is already answered by competitors. The domains cohere through the shared knowledge base and agent context, passing the breadth-coherence check.

**Build timeline:** The product already exists and exceeds MVP scope -- 67 agents, 83 skills, 3 commands, 5,000+ merged PRs (latest #5044, ~2,350 commits on main), plus a deployed web platform (app.soleur.ai). [Re-validated 2026-06-08 — corrects the stale and internally-inconsistent "65+ agents, 50+ skills, 280+ merged PRs" / "420+ PRs" figures]. The MVP is built. The validation work is about measuring external adoption, not building more features.

**Success metrics:**

- 10 solo founders who use agents from at least 2 different domains (not just engineering) on their real projects for 2+ weeks
- At least 5 of 10 report that the integrated experience is more valuable than using separate tools
- At least 3 of 10 express willingness to pay for the hosted version

**Assessment:** PASS [Re-validated 2026-06-08; was PASS 2026-03-22]. The product exceeds MVP scope in depth and matches it in breadth, and the access-surface gap identified in 2026-03-22 is now closed. The breadth thesis remains validated by external evidence (every interviewed founder described multi-domain pain unprompted) and aligns with the brand-guide positioning that defines multi-domain breadth as the core value proposition -- so the kill criterion here is breadth-coherence (do the domains connect to a unified value prop?), which passes, not scope-size. The remaining MVP risk is no longer "what to build" but "prove the built breadth gets used": the success metrics below are still unmet.

**Delivery challenge -- RESOLVED [Re-validated 2026-06-08; was REQUIRED 2026-03-22]:** The 2026-03-22 assessment said the MVP must expand to "multi-domain agents accessible from any device" via a web-accessible interface (dashboards, review queues, KB browsing). **This is now shipped:** app.soleur.ai hosts the chat router (`/soleur:go`), a dashboard, a KB Concierge sidebar, auth, and the Claude Agent SDK runners. The access surface that was the gating constraint exists in production. The MVP definition's expansion has been executed; what remains is measuring whether the now-accessible breadth converts external founders -- the success metrics, not the surface.

## Validation Verdict

> **[Full re-validation 2026-06-08]** This pass re-validated every stable section (Problem, Customer, Demand Evidence, Business Model, Minimum Viable Scope, Verdict) against current reality; the Competitive Landscape was refreshed separately on 2026-06-08 and was not re-touched here. **What this re-validation changed:**
> 1. **The delivery pivot is EXECUTED, not pending.** The single most important status change: the 2026-03-22 doc framed the standalone web platform as "REQUIRED" but unbuilt. It is now deployed to production at app.soleur.ai (Next.js 15, Supabase auth + 183 migrations, Claude Agent SDK runners, Terraform infra, live deploy pipeline succeeding 2026-06-08, public Buttondown waitlist). The "stop building, build the platform" half of the 2026-03-22 pivot is complete.
> 2. **Stale product metrics corrected:** "65+ agents, 50+ skills" → **67 agents, 83 skills, 3 commands** (verified via `scripts/sync-readme-counts.sh --check`); inconsistent "280+ / 420+ merged PRs" → **5,000+** (latest merged PR #5044; ~2,350 commits on main).
> 3. **A demand-capture surface now exists** (waitlist + invite + Plausible goals) where 2026-03-22 had none -- but **no captured signup / activation / willingness-to-pay numbers are recorded yet.** External demand evidence is still thin: 5+ interviews, zero recorded external active users.
> 4. **Verdict reframed but held at PIVOT.** The pivot is no longer "stop building, start validating" (the build half is done) -- it is now **"the platform is shipped; measure adoption through it."** See the reframed verdict and "What to do next" below. Gate results are unchanged in label; the underlying reasons are updated.
> 5. External market signals refreshed (29.8M solopreneurs/$1.7T; agentic-AI ~$2.8B H1'25 funding; metered/credit-pricing market shift) -- all flagged where self-reported/third-party.

**Verdict: PIVOT** [Re-validated 2026-06-08 -- reframed from "stop building, start validating" to "platform shipped, now measure adoption"; label held]

The verdict remains PIVOT, but its meaning has inverted on one axis. At 2026-03-22 the pivot was *from building to validating* and the delivery pivot was *required but unbuilt*. As of 2026-06-08 the delivery pivot is **executed** -- so the open question is no longer "build the web surface" but "prove external founders adopt and pay through it." The label stays PIVOT (not GO) because the gating evidence -- measured external demand and a committed, validated revenue model -- is still absent, not because anything needs rebuilding. This is a measurement-and-monetization pivot, not a direction change.

| Gate | Result |
|------|--------|
| Problem | PASS |
| Customer | CONDITIONAL PASS |
| Competitive Landscape | CONDITIONAL PASS |
| Demand Evidence | OVERRIDE |
| Business Model | CONDITIONAL PASS |
| Minimum Viable Scope | PASS |

### Vision Alignment Check

The validation assessment was compared against the brand guide's stated positioning (mission: enable a single founder to build, ship, and scale a billion-dollar company; positioning: full AI organization across every department; thesis: the billion-dollar solo company is an engineering problem).

**Alignment findings:**

1. **CaaS positioning:** Aligned. The validation directly tests the Company-as-a-Service thesis. The problem framing (capacity + expertise gaps), the customer definition (technical solo founders), and the MVP scope (multi-domain breadth) all map to the brand guide's mission.
2. **MVP scope and breadth:** Aligned. Gate 6 explicitly argues that breadth is the minimum scope, and removing any domain undermines the thesis. This honors the brand guide's positioning of "a full AI organization that operates as every department."
3. **No contradictions requiring resolution.** One productive tension persists [Re-validated 2026-06-08]: the brand guide speaks with the conviction of inevitability ("It's an engineering problem. We're solving it."), while the validation still shows this conviction has not been tested by measured external adoption. The tension has narrowed since 2026-03-22 -- the delivery surface the brand guide anticipated ("accessible anywhere," web-platform CTA) is now shipped, so the gap is no longer "build the thing" but "prove external founders use it." This remains a timing/evidence tension, not a directional one. The brand identity remains intact, and breadth-as-value-proposition is honored by the deployed multi-domain platform.

### What is strong [Re-validated 2026-06-08]

- **The problem is real and growing.** Solo founders managing entire companies alone is a structural pain that intensifies as AI expands what one person can build. The twofold framing (capacity gap + expertise gap) is clean and testable, and 2026 market data (29.8M solopreneurs, 36.3% solo-founder share, real eight/nine-figure one-person companies) corroborates it at scale.
- **The product is well-built, genuinely used, and now deployed as a product.** 5,000+ merged PRs, daily dogfooding across all domains, and -- new since 2026-03-22 -- a production web platform at app.soleur.ai (auth, dashboard, Agent SDK runners, deploy pipeline shipping daily). Execution is strong; the product exceeds MVP scope in depth and now matches it in access surface.
- **The competitive landscape validates the category.** Multiple funded companies are building AI agent workforces (Polsia $30M/$250M, Relevance $37.2M, CrewAI $18M, plus Lovable/Replit at billions). None combine engineering depth, full business breadth, founder-in-the-loop, AND a git-tracked compounding knowledge base. The structural advantages (compounding knowledge, cross-domain coherence, workflow lifecycle) remain genuine and difficult to replicate.
- **The breadth thesis is coherent.** The domains connect through a shared knowledge base and agent context -- an integrated system where decisions in one domain inform others. This aligns with the brand-guide positioning of breadth as the core value proposition.

### What is weak [Re-validated 2026-06-08]

- **External demand evidence is still thin.** 5+ interviews and **zero recorded external active users**; no waitlist-signup, activation, or willingness-to-pay numbers captured through the now-deployed platform. The strong external signals (market trends at scale, agentic-AI funding, existence proofs) provide directional validation but do not substitute for measured behavior through Soleur's own funnel. This is the single biggest gap and it did not close this cycle.
- **The business model is plausible but uncommitted.** No published pricing, no revenue model decision, no evidence of willingness to pay -- and the metered/credit-pricing market shift means the deployed platform's per-user compute unit economics now need explicit modeling before monetizing.
- **The customer definition is broad.** "Technical solo founders across all stages" is a market thesis, not a beachhead segment; named individual contacts remain below 5. The waitlist can now instrument a tighter cohort, but the segment definition itself still needs narrowing.
- **Single-platform distribution risk.** Soleur ships through the Claude Code channel and is Anthropic-stack-locked while the closest structural competitor (alirezarezvani/claude-skills) runs in 12+ tools and Tier 0 platforms (Codex, Copilot) bundle competing breadth -- a vulnerability the competitive scan flags as standout. [Added 2026-06-08]

### What to do next (the PIVOT) [Re-validated 2026-06-08]

The pivot is still not a change in direction -- but the activity has moved one step downstream. At 2026-03-22 the next move was "build the web platform and start validating." The platform is now built and deployed, so the next move is **"drive founders to it and measure the funnel."**

1. **Hold feature scope; instrument the funnel.** The product (67 agents, 83 skills, deployed platform) has more than enough capability. Redirect engineering from new agents to: waitlist-conversion tracking, activation events (first multi-domain workflow), retention, and a willingness-to-pay prompt. The success metric is captured behavior, not shipped features.
2. **Drive 10+ solo founders to app.soleur.ai from mixed channels.** Claude Code Discord, GitHub signal mining, IndieHackers, direct network, and the waitlist-first marketing funnel. Avoid segment bias -- different stages and industries. Record the numbers in this document next cycle.
3. **Run problem interviews in parallel (no demo).** Continue testing whether founders independently describe multi-domain pain; the 5+ count must move toward 10+. Note distribution reality from prior research: most target founders do not live in Claude Code, so the web platform is the correct surface to convert them.
4. **Guided onboarding with the top 5 on the deployed platform.** Walk them through multiple domains on their real projects via app.soleur.ai. Observe which domains they engage first and which they ignore.
5. **2-week unassisted usage, measured.** Track returns, knowledge-base growth, and non-engineering-agent usage without prompting -- now observable through platform instrumentation rather than self-report.
6. **Test willingness to pay through the live surface.** The platform exists, so the question is concrete: do waitlist signups convert, and will founders pay $49-99/month? Model the per-user API/compute cost against that price before committing -- the metered-billing market makes unit economics non-optional.
7. **Commit to a business model after 50+ active platform users.** Build the revenue model around observed funnel behavior, not hypotheses, and decide the posture vs. the 20%-revenue-share pattern (Polsia/NanoCorp) -- likely "you keep 100% + predictable pricing + you own your git-tracked memory."

The core insight is sound: a solo founder needs more than a coding assistant -- they need an AI organization, and that organization is now a deployed product. But a deployed product with zero measured external adoption is still an unvalidated hypothesis. The verdict is PIVOT because the evidence bar (measured demand + a committed revenue model) is unmet -- not because anything needs rebuilding. The build risk is retired; the demand and monetization risks are live.

### User Research Update (2026-03-22): Two-Dimensional Pivot

The 5+ founder conversations confirm the PIVOT verdict but add a second dimension. The original pivot was one-dimensional: stop building, start validating. The research reveals a two-dimensional pivot:

1. **Thesis pivot (original):** From building features to validating with users. Status: VALIDATED. The problem resonates. Founders describe multi-domain pain independently and urgently.
2. **Delivery pivot (new):** From CLI plugin to standalone web platform. Status (2026-03-22): REQUIRED. **Status (2026-06-08): EXECUTED** -- see re-validation note below. The plugin delivery mechanism was rejected by the target market; founders wanted visual dashboards, cross-device access, and a product that doesn't assume they use Claude Code. That product is now deployed at app.soleur.ai.

**Impact on "What to do next":** [superseded by the 2026-06-08 "What to do next" above -- the platform that steps 3-6 required is now built; the steps now read against the deployed surface]

- Steps 1-2 (hold scope, source founders) remain correct.
- Steps 3-6 (interviews, onboarding, usage tracking, willingness to pay) are now conducted against the **deployed** web platform, not a prototype.
- Step 7 (commit business model after 50+ users) is now both more urgent and more tractable -- the platform is the product, shipped, and its unit economics are measurable.

**Gate-by-gate impact summary:**

| Gate | Original | After Research (2026-03-22) | Full Re-validation (2026-06-08) |
|------|----------|---------------------------|--------------------------------|
| Problem | PASS | PASS (confirmed by 5+ conversations) | PASS (corroborated by 2026 market data at scale) |
| Customer | CONDITIONAL PASS | CONDITIONAL PASS (beachhead redefined: problem-first, not tool-first) | CONDITIONAL PASS (waitlist now an instrumented capture surface; named cohort still <5) |
| Competitive | CONDITIONAL PASS | CONDITIONAL PASS (delivery format is now a competitive dimension) | CONDITIONAL PASS (Tier 0 platform threat + funded CaaS field; refreshed 2026-06-08; gate table reconciled to match section) |
| Demand Evidence | FLAG | FLAG (problem validated, delivery mechanism invalidated) | FLAG (delivery surface built; captured signup/activation/pay numbers still absent) |
| Business Model | CONDITIONAL PASS | CONDITIONAL PASS (platform-first, not plugin+platform) | CONDITIONAL PASS (platform shipped; price/revenue model still undecided; unit economics now urgent) |
| Minimum Viable Scope | PASS | PASS (breadth validated, access surface must expand) | PASS (access surface shipped; success metrics still unmet) |

### Delivery Pivot Execution Evidence (2026-06-08)

Verified against the repository this cycle (per `hr-verify-repo-capability-claim-before-assert`):

- **Deployed product:** `apps/web-platform/` is a Next.js 15 app serving app.soleur.ai (Cloudflare-proxied A record → Hetzner server). Hosts the chat router (`/soleur:go`), dashboard, KB Concierge sidebar, and Claude Agent SDK runners.
- **Auth + data:** Supabase auth (login/signup/callback/connect-repo/accept-terms routes) with **183 migrations**; branded OAuth via Supabase custom domain.
- **Infra + ops:** Terraform infra (DNS, Cloudflare, server, tunnel, firewall, fail2ban), Sentry observability, branded email (Resend/SES), bubblewrap/seccomp sandboxing for runners.
- **Deploy pipeline:** `.github/workflows/web-platform-release.yml` (push-to-main on `apps/web-platform/**`) -- **successful production runs on 2026-06-08.**
- **Demand capture:** public Buttondown-backed waitlist (`/api/waitlist`, rate-limited, honeypot), waitlist-first marketing funnel (PRs #1139-#1142, #5028, #5035), Plausible goal tracking.
- **Counts (verified via `scripts/sync-readme-counts.sh --check`):** 67 agents, 83 skills, 3 commands. Latest merged PR #5044; ~2,350 commits on main.

This is the basis for marking the delivery pivot EXECUTED and correcting the stale "required but untested / not yet built" framing.
