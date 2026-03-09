---
last_reviewed: 2026-03-09
tiers_scanned: [0, 3]
---

# Competitive Intelligence Report

## Executive Summary

The competitive landscape has shifted meaningfully since the 2026-03-02 scan. **Polsia has emerged as the most direct CaaS competitor in Tier 3**, crossing $1M ARR in one month with 1,100+ autonomously managed companies, covering engineering, marketing, operations, sales outreach, and social media -- the closest domain coverage to Soleur among Tier 3 entrants. Polsia's fully autonomous model (nightly CEO agent cycles, $50/month + 20% revenue share) validates the solo-founder CaaS thesis but represents a fundamentally different philosophy: zero human-in-the-loop vs. Soleur's founder-as-decision-maker approach. **Tier 0 threats remain critical and stable**: Anthropic Cowork now has 10 department-specific plugin categories (up from 11 open-source plugins at last scan) including engineering, and expanded enterprise connectors. **Tier 3 CaaS competitors continue consolidating**: Lovable reached $300M+ ARR at $6.6B valuation with Lovable 2.0 (multi-user collaboration, Chat Mode Agent), v0 rebranded to v0.app with agentic architecture and database integrations, and Notion Custom Agents enter free beta through May 2026 with credit-based pricing on the horizon. Soleur's structural moats -- compounding knowledge, cross-domain coherence, founder-in-the-loop workflow orchestration, and local-first open-source design -- remain defensible, but Polsia's traction proves the market is ready for autonomous company operation.

---

## Tier 0: Platform Threats

Platform-native competition represents the existential risk tier. These competitors control the model, the distribution surface, or the IDE -- and can bundle AI capabilities that Soleur sells as differentiated features.

### Overlap Matrix

| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| **Anthropic Cowork Plugins** | Full 8-domain agent organization | High | Cowork now has 10 department-specific plugin categories: HR, Design, Engineering, Operations, Financial Analysis, Investment Banking, Equity Research, Private Equity, Wealth Management, and Brand Voice. Enterprise connectors expanded to include Google Workspace, DocuSign, Apollo, Clay, Outreach, Similarweb, MSCI, FactSet, LegalZoom, Harvey, WordPress, S&P Global, LSEG, Common Room, and Slack. Private marketplaces with admin controls. Plugin Create for custom agent building. Plugins remain stateless and siloed per domain -- no compounding knowledge base, no cross-domain coherence, no workflow lifecycle orchestration. Available on Pro, Max, Team, and Enterprise plans. | **Critical** -- Anthropic controls the model, API, and distribution. Engineering plugins now exist (standup summaries, incident coordination, deploy checklists, postmortems). 7+ of 8 Soleur domains face first-party competition. Excel/PowerPoint integration in research preview for finance workflows. |
| **Claude Code Native Features** | Engineering workflow agents + plugin ecosystem | High | Claude Code now has 9,000+ plugins, MCP tool search, auto-memory, Plan subagent, and dynamic model selection for subagents. Native capabilities are converging on what Soleur's engineering agents provide. Soleur differentiates through curated multi-domain workflows, institutional memory that compounds across domains, and opinionated agent behaviors. | **High** -- Claude Code's native plugin ecosystem is expanding rapidly. Individual plugins can replicate specific Soleur skills. The compound knowledge base remains Soleur's strongest moat against piecemeal plugin assembly. |
| **Cursor (Anysphere)** | Engineering agents, code review, planning | Medium | Cursor is engineering-only but now offers cloud agents with computer use, Bugbot autofix (35% merge rate), Mission Control for parallel agents, and CLI-to-cloud handoff. $29.3B valuation, $1B ARR, used by 50%+ of Fortune 500. No marketing, legal, ops, or product domains. No persistent cross-domain knowledge base. | **Medium** -- Cursor dominates the IDE-native engineering segment. Risk is indirect: if Cursor satisfies all engineering needs, founders may not see value in Soleur's engineering agents. Soleur's non-engineering domains become the differentiator. |
| **GitHub Copilot (Coding Agent + CLI)** | Engineering workflow, code review, planning | Medium | Copilot coding agent is now GA for all paid subscribers -- assigns issues, creates PRs autonomously. CLI has memory, specialized sub-agents (Explore, Task, Code Review, Plan), background delegation, and autopilot mode. Custom agents via `.agent.md`. MCP support. Multi-model (GPT-5.1-Codex, Claude Opus 4.5, Gemini). Copilot Spaces for context organization. | **Medium-High** -- GitHub controls the repository surface. CLI memory and specialized agents are converging on Claude Code plugin capabilities. Distribution advantage: Copilot is bundled with every GitHub paid plan. |
| **OpenAI GPT-5.3-Codex** | Engineering agents | Medium | GPT-5.3-Codex works 7+ hours autonomously, achieves SWE-Bench Pro records, and is the first model instrumental in creating itself. Codex agent can "do nearly anything developers can do on a computer." 400K context window. Primarily accessed via OpenAI Codex platform (cloud IDE). No multi-domain business workflows. | **Medium** -- OpenAI's strength is model capability, not distribution in the CLI/terminal workflow. Risk materializes if OpenAI ships a Codex platform with business domain agents (no signal of this yet). |
| **Windsurf (Cognition/Codeium)** | Engineering agents, code review | Medium | Acquired by Cognition (Devin). Cascade agent writes 90% of user code, 57M lines/day. Memories system for persistent learning. Arena Mode for model comparison. MCP integrations (GitHub, Slack, Stripe, Figma). $15/month (cheapest IDE). JetBrains integration. No multi-domain business workflows. | **Medium** -- Windsurf + Devin merger creates a full-stack engineering platform. Memories system is a partial analog to Soleur's knowledge base, but scoped to code patterns only. |
| **Google Gemini Code Assist** | Engineering agents | Low | Agent mode GA for all users. Multi-file edits, plan-then-execute workflow, Gemini CLI. 1M token context window. Free tier with 6,000 daily requests. $299/year premium. Enterprise edition with private repo access. No business domain capabilities. | **Low** -- Google's strength is in the enterprise/GCP ecosystem. Minimal overlap with Soleur's solo-founder CaaS positioning. |

### Tier 0 Analysis

**Material changes since last review (2026-03-02):**

1. **Anthropic Cowork plugin taxonomy clarified to 10 categories.** Previous report cited "11+ open-source plugins." The structure is now clearer: 10 department-specific plugin categories, each built with domain practitioners. Engineering plugins cover standup summaries, incident response coordination, deploy checklists, and postmortem drafting. Design plugins cover critique frameworks, UX copy drafting, accessibility audits, and user research planning ([source](https://www.eesel.ai/blog/claude-cowork-plugins-updates)).

2. **Cowork enterprise connectors expanded.** New partners include Harvey (legal AI), S&P Global, LSEG, Common Room, and Tribe AI (brand voice). The connector ecosystem now spans 15+ enterprise platforms ([source](https://www.constellationr.com/insights/news/anthropic-expands-cowork-plugins-across-enterprise-functions)).

3. **No material changes to Cursor, Copilot, OpenAI, Windsurf, or Gemini** since 2026-03-02. Positions remain as documented in prior scan.

**Soleur's remaining Tier 0 advantages:**
- Compounding cross-domain knowledge base (no competitor has this)
- Workflow lifecycle orchestration (brainstorm > plan > implement > review > compound)
- 60+ agents with shared institutional memory across 8 domains
- Opinionated, curated agent behaviors vs. generic plugin assembly
- Local-first, open-source core vs. cloud-locked enterprise platforms

---

## Tier 3: Company-as-a-Service / Full-Stack Business Platforms

Tier 3 competitors either offer AI-powered coding services or position as full-stack business platforms for founders. The overlap with Soleur varies -- some compete on engineering, others on business operations, and a few attempt both.

### Overlap Matrix

| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| **Polsia** | Multi-domain agent organization (autonomous operations) | High | Autonomous AI company-operating platform built on Claude Agent SDK (Claude Opus 4.6). Role-based agents (CEO, Engineer, Growth Manager) run nightly autonomous cycles: evaluate company state, decide priorities, execute tasks, send founder morning summary. $50/month + 20% revenue share on business revenue + 20% cut on managed ad spend. 1,100+ managed companies, $1M ARR crossed within one month of launch (growing toward $1.8M ARR with 2,000+ companies). Covers 5+ domains: engineering, marketing, cold outreach, social media, Meta ads. Polsia provisions all infrastructure (email, servers, databases, Stripe, GitHub). 91,000+ human messages, averaging 15 daily messages per user. Solo founder Ben Broca. **Key difference from Soleur:** fully autonomous (zero human-in-the-loop) vs. Soleur's founder-as-decision-maker model. No legal, finance, or product strategy domains. No structured knowledge base that compounds across domains. No Claude Code integration -- cloud-hosted proprietary platform. Autonomous output quality reportedly basic. Shares Soleur's Anthropic platform dependency. | **High** -- Polsia is the most direct CaaS competitor. Its traction ($1M ARR in one month) validates the market thesis that solo founders will pay for autonomous company operation. Convergence risk is high if Polsia adds legal/finance domains or implements cross-domain knowledge compounding. Mitigating factor: Polsia's fully autonomous philosophy is fundamentally different from Soleur's human-in-the-loop approach -- these may serve different founder personas. |
| **SoloCEO** | Multi-domain agent organization (advisory layer) | Medium | Positions as "Your Business Operating System" with AI board of directors (CFO, CMO, COO, etc.). Advisory-only -- produces diagnostics and recommendations, not operational execution. No engineering domain. No compounding knowledge base across sessions. Limited public information available; site shows minimal detail beyond tagline. | **Low** -- SoloCEO validates the CaaS category thesis but is advisory-only vs. Soleur's operational approach. No convergence signal toward execution capabilities. |
| **Tanka** | Cross-domain knowledge base + agent collaboration | Medium | Memory-native platform repositioned as "The Operating Base for AI-Native Companies." EverMemOS persistent knowledge graphs, multi-agent collaboration (content, sales, product, data agents), fundraising agent, and planned Agent Store. Integrates Slack, WhatsApp, Gmail, Calendar, Notion, Telegram. SOC 2 Type II and ISO 27001 certified. Pricing: $0/user/month for teams under 50; $299/month for teams 50+. Communication-centric, no engineering workflow. Mobile apps on iOS and Google Play. | **Medium** -- Tanka's memory architecture is the closest analog to Soleur's compounding knowledge base. Risk: if Tanka adds engineering agents via their Agent Store, the overlap increases significantly. Memory compounding is their explicit moat claim. Free pricing for small teams could attract solo founders. |
| **Lovable.dev** | Engineering agents (web app generation) | Low | $300M+ ARR, $6.6B valuation ($330M Series B, Dec 2025). Full-stack React app builder. Lovable 2.0 (Feb 2026): real-time multi-user collaboration (up to 20 users), Chat Mode Agent for reasoning without editing code, visual edits reducing UI iteration by 40%. Lovable Cloud: auto-managed login, databases, file uploads, AI features without API keys. Enterprise customers: Klarna, Uber, Zendesk. $25/month Pro, $50/month Business, custom Enterprise. GitHub sync, TypeScript/React code export. | **Low** -- Lovable competes in the "vibe coding" category, not the CaaS category. No signal of expansion into business operations. Risk: Lovable's scale ($300M+ ARR) and funding could enable rapid domain expansion if they chose to. |
| **Bolt.new** | Engineering agents (web app generation) | Low | Browser-based full-stack generation via StackBlitz WebContainers. $40M+ ARR. Supports Node.js environment in-browser (npm install, dev server, API routes). Prompt-to-app generation, visual editor, GitHub integration. $25/month Pro. Free plan limited to 1M tokens/month with 300K daily cap. Open-source bolt.diy for self-hosting. Support is AI-only with no human escalation. Known issue: rewrites entire files instead of targeted edits. | **Low** -- Purely engineering/prototyping tool. No multi-domain ambition visible. |
| **v0.dev (v0.app)** | Engineering agents (UI/frontend generation) | Low | Rebranded from v0.dev to v0.app (Jan 2026). Evolved from UI component generator to full-stack builder. "Agentic by default" architecture: plans, creates tasks, connects to databases autonomously. Sandbox-based runtime: imports GitHub repos, pulls Vercel environment variables. New Git panel for branch creation and PR opening. Database integrations with Snowflake and AWS. One-click Vercel deployment. Token-based pricing (variable per generation). iOS app for mobile building. 6M+ developers. | **Low** -- v0 is frontend-focused within the Vercel ecosystem. No multi-domain capability. New agentic features and database integrations represent maturation within engineering, not expansion into business domains. |
| **Replit Agent** | Engineering agents (autonomous coding) | Low | Agent 3: 10x more autonomous, 200-minute autonomous sessions, self-testing loop, agents building agents via Stacks. Code Optimizations for self-review. Economy/Power/Turbo modes. Replit Core $20/month, Replit Pro $100/month (with $100 monthly credits). Teams plan sunset March 2026, customers upgraded to Pro. 50+ languages. Effort-based pricing. Cloud-hosted. | **Low** -- Engineering-only, cloud-hosted. Pricing restructuring (Teams sunset, tiered modes) signals monetization pressure. No multi-domain agents. |
| **Devin 2.0 (Cognition)** | Engineering agents (autonomous coding) | Low | Autonomous AI software engineer. Core plan dropped to $20/month (was $500). Parallel sessions, interactive planning, Devin Search/Wiki/Review. Enterprise adoption (Goldman Sachs, Santander). Now owns Windsurf. 83% more tasks completed per ACU vs. predecessor. | **Low** -- Devin is the premier autonomous coding agent but engineering-only. Cognition+Windsurf merger creates the most complete engineering stack in market. No business domain agents. |
| **Notion AI 3.3** | Multi-domain agent organization (workspace layer) | Medium | Custom Agents launched Feb 24, 2026: autonomous, scheduled, 24/7 operation. Cross-app MCP integrations (Slack, Figma, Linear, HubSpot, Asana). Multi-model (GPT-5.2, Claude Opus 4.5, Gemini 3). 21,000+ agents built in early testing. Free beta through May 3, 2026; then credit-based pricing ($10/1,000 credits, variable per task complexity). Business and Enterprise plans only. AI Meeting Notes with one-tap transcription. Agent capabilities include task triaging, Q&A, standups, status reports, inbox management. | **Medium-High** -- Notion's Custom Agents are the closest Tier 3 analog to Soleur's multi-domain approach. Risk: Notion has massive distribution (35M+ users), workspace context, and cross-app integrations. Credit-based pricing after May 2026 could make it expensive for heavy autonomous use. Differentiation: Notion has no engineering workflow, no structured knowledge base that compounds specifically for solo founders, and agents are workspace-scoped not business-scoped. |
| **Systeme.io** | Marketing and sales agents | Low | All-in-one marketing platform: funnels, email, courses, webinars, affiliate management, blogs. $0-97/month. Startup plan now $17/month (down from $27). Unlimited plan $97/month. Free plan: 2,000 contacts, unlimited email, 3 funnels, 1 membership site, 1 blog. No transaction fees. Free migration and 1-on-1 coaching. Competes with ClickFunnels ($297/month). | **None** -- Systeme.io is a traditional SaaS tool, not an AI platform. Overlap limited to marketing/sales function. No AI agent layer, no intelligence, no cross-domain capability. |
| **Stripe Atlas** | Legal/operations agents (company formation) | None | Delaware C-corp or LLC formation. $500 setup fee + $100/year registered agent. Includes EIN, stock issuance, 83(b) tax election. Bank account + Stripe payments within 2 days. $2,500 in Stripe product credits + $50,000+ in partner discounts. Incorporates 1 in 5 Delaware C-corps. 23,000 companies formed in 2025. | **None** -- One-time formation service, not ongoing operations. No AI, no agents, no compounding knowledge. Soleur's legal agents handle ongoing compliance and document generation, not incorporation. |
| **Firstbase** | Legal/operations agents (company formation) | None | Company formation in Delaware or Wyoming. $399 one-time fee + $149/year registered agent. Firstbase One platform: accounting, address, tax filing. Bookkeeping $99/month. $350,000+ in partner discounts. Global company formation with banking and payroll integrations. | **None** -- Formation-focused service, not ongoing operations. Broader than Atlas (accounting, bookkeeping) but still administrative, not AI-driven. No agents, no multi-domain workflow. |

### Tier 3 Analysis

**Material changes since last review (2026-03-02):**

1. **Polsia added to competitive landscape.** The most significant new entrant since the last scan. $1M ARR in one month, 1,100+ autonomously managed companies, covering engineering + marketing + operations + sales outreach + social media. Built on Claude Agent SDK with Claude Opus 4.6 as the CEO agent's reasoning model. Validates the CaaS thesis aggressively -- but with a fully autonomous (no human-in-the-loop) philosophy that differs fundamentally from Soleur's founder-as-decision-maker approach ([source](https://www.teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies), [source](https://polsia.com)).

2. **Lovable reached $300M+ ARR with Lovable 2.0.** Multi-user collaboration (up to 20 users) and Chat Mode Agent represent maturation beyond single-player "vibe coding." Visual edits reduce iteration by 40%. Enterprise adoption deepening (Klarna, Uber, Zendesk). No expansion into business domains ([source](https://lovable.dev/blog/lovable-2-0), [source](https://www.taskade.com/blog/lovable-review)).

3. **v0 rebranded to v0.app with agentic architecture.** "Agentic by default" with database integrations (Snowflake, AWS), Git workflow panel, and sandbox runtime that imports GitHub repos. Still engineering/frontend-focused but significantly more capable than the component generator it started as ([source](https://vercel.com/blog/v0-app)).

4. **Notion Custom Agents pricing clarified.** Free beta through May 3, 2026; then $10/1,000 credits on Business and Enterprise plans. Credit consumption varies by task complexity. 21,000+ agents built during beta. Cross-app integrations now include Asana ([source](https://www.notion.com/help/custom-agent-pricing), [source](https://www.notion.com/releases/2026-02-24)).

5. **Replit restructuring.** Core plan dropped to $20/month, Pro at $100/month. Teams plan sunset March 2026. Economy/Power/Turbo modes replace autonomy settings. Code Optimizations for agent self-review. Signals monetization pressure ([source](https://blog.replit.com/pro-plan), [source](https://replit.com/pricing)).

6. **Tanka repositioned as "Operating Base for AI-Native Companies."** Free for teams under 50. SOC 2 Type II and ISO 27001 certified. Mobile apps on both platforms. Communication-centric positioning unchanged ([source](https://www.tanka.ai/)).

7. **Stripe Atlas and Firstbase added for completeness.** Both were in business-validation.md but absent from prior CI reports. Atlas: $500 one-time, 1 in 5 Delaware C-corps. Firstbase: $399 one-time, broader platform (accounting, bookkeeping, tax). Neither represents competitive overlap -- they are point-in-time formation services, not ongoing AI operations ([source](https://stripe.com/atlas), [source](https://www.firstbase.io/)).

**Soleur's remaining Tier 3 advantages:**
- Only platform combining engineering depth with 8-domain business breadth
- Compounding knowledge base across all domains (Polsia has no cross-domain knowledge compounding; Tanka has memory but communication-scoped)
- Founder-as-decision-maker philosophy (vs. Polsia's fully autonomous approach) -- human judgment as a feature, not a limitation
- Workflow orchestration (brainstorm > plan > implement > review > compound)
- Local-first, open-source core (vs. cloud-locked competitors)
- Claude Code native integration (terminal-first workflow)
- Legal, finance, and product strategy domains that no Tier 3 competitor covers

---

## New Entrants

Competitors identified during this scan that were not present in the previous competitive-intelligence.md report:

| Entrant | Category | Relevance | Notes |
|---|---|---|---|
| **Polsia** | CaaS / Autonomous Company Operations | **High** | Most direct CaaS competitor. $1M ARR in one month, 1,100+ managed companies. Built on Claude Agent SDK. $50/month + 20% revenue share. Covers engineering, marketing, ops, sales outreach, social media. Fully autonomous -- CEO agent runs nightly cycles. Missing: legal, finance, product strategy, structured knowledge base, Claude Code integration. ([source](https://polsia.com), [source](https://www.teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies)) |
| **Stripe Atlas** | Formation Service | **None** | Already in business-validation.md Tier 3. $500 one-time company formation. No competitive overlap. Added to overlap matrix for completeness. ([source](https://stripe.com/atlas)) |
| **Firstbase** | Formation Service | **None** | Already in business-validation.md Tier 3. $399 one-time company formation with bookkeeping. No competitive overlap. Added to overlap matrix for completeness. ([source](https://www.firstbase.io/)) |

---

## Recommendations

### Priority 1: Position Against Polsia's Autonomous Model (Immediate)

Polsia's $1M ARR in one month proves the CaaS market is real and solo founders will pay. The philosophical split is clear: **Polsia = fully autonomous (AI decides everything) vs. Soleur = founder-in-the-loop (AI executes, human decides)**. This is a positioning opportunity, not just a threat. Polsia's autonomous output is reportedly basic, and its 20% revenue share creates friction at scale. **Action:** Frame "founder-as-decision-maker" as the premium approach. Create content contrasting "autopilot" (Polsia) vs. "copilot organization" (Soleur) and why human judgment compounds better than fully autonomous execution. Highlight domains Polsia lacks (legal, finance, product strategy).

### Priority 2: Defend the Knowledge Base Moat (Immediate)

The compounding knowledge base is Soleur's single strongest differentiator. No competitor -- not Polsia, not Anthropic Cowork, not Notion Custom Agents, not Tanka -- has cross-domain institutional memory that compounds across business functions within a terminal-first workflow. Polsia has no structured knowledge base. Cowork plugins are stateless. Notion agents are workspace-scoped. **Action:** Accelerate knowledge base documentation, create showcase demos of cross-domain compounding (e.g., brand guide informing marketing content informing sales battlecards), and make this the centerpiece of positioning.

### Priority 3: Reposition Against Cowork's Engineering Expansion (Immediate)

Anthropic's 10 department-specific plugin categories now cover engineering (standup summaries, incident coordination, deploy checklists, postmortems). The differentiation axis must shift from "Soleur covers domains Anthropic doesn't" to "Soleur orchestrates workflows across domains with compounding memory that Anthropic's stateless plugins cannot." **Action:** Update all positioning materials to emphasize orchestration and compounding, not domain coverage alone.

### Priority 4: Monitor Polsia's Domain Expansion (30-day review cycle)

Polsia currently covers 5 domains. If it adds legal, finance, or product strategy -- or implements cross-domain knowledge compounding -- the competitive gap narrows significantly. Polsia shares Soleur's Anthropic platform dependency (both use Claude models), so model improvements benefit both equally. **Action:** Track Polsia's product updates monthly. Monitor Ben Broca's public communications for domain expansion signals. If Polsia adds structured knowledge base or legal/finance domains, escalate to Priority 1.

### Priority 5: Monitor Notion Custom Agents (30-day review cycle)

Notion 3.3's Custom Agents represent the highest convergence risk among established platforms. Notion has massive distribution (35M+ users), cross-app integrations (Slack, Figma, Linear, Asana), and is evolving toward autonomous business operations. Credit-based pricing ($10/1,000 credits) after May 2026 may make heavy use expensive. Current gap: no engineering workflow, no structured knowledge base for solo founders. **Action:** Track Notion's agent capabilities monthly. If Notion adds engineering agents or persistent business-scoped memory, escalate to Priority 1.

### Priority 6: Exploit the CaaS Category Validation (Near-term)

Polsia ($1M ARR), SoloCEO ("Your Business Operating System"), Tanka ("Operating Base for AI-Native Companies"), and the broader solo-founder renaissance validate the category thesis. Soleur is the only CaaS entrant with both engineering execution and 8-domain business breadth, plus open-source local-first design. **Action:** Own the "Company-as-a-Service" narrative before Polsia, Notion, or Tanka define it. Polsia's traction is proof the market exists -- use it in positioning.

### Priority 7: Reassess Revenue Model Against Polsia's Pricing (Near-term)

Polsia's $50/month + 20% revenue share model creates an interesting comparison. The $50 subscription "roughly breaks even on AI costs" -- the real revenue is the 20% cut. Soleur's hypothesized $49-99/month flat-rate avoids revenue share friction but must deliver enough value to justify the price without taking a cut. **Action:** Revisit issue #287. Consider whether a pure subscription model or a hybrid (lower subscription + small revenue share on generated revenue) better aligns with solo founder willingness to pay. Polsia proves $50/month is viable; the 20% share may be a vulnerability to exploit.

---

_Generated: 2026-03-09_

**Source documents:**
- `knowledge-base/overview/brand-guide.md` (last updated: 2026-02-21)
- `knowledge-base/overview/business-validation.md` (last updated: 2026-03-09)

**Research sources:**
- [Anthropic Cowork Plugins Enterprise Launch (TechCrunch, Feb 24 2026)](https://techcrunch.com/2026/02/24/anthropic-launches-new-push-for-enterprise-agents-with-plugins-for-finance-engineering-and-design/)
- [Anthropic Cowork Agentic Plugins (TechCrunch, Jan 30 2026)](https://techcrunch.com/2026/01/30/anthropic-brings-agentic-plugins-to-cowork/)
- [Anthropic Cowork Expansion (Constellation Research)](https://www.constellationr.com/insights/news/anthropic-expands-cowork-plugins-across-enterprise-functions)
- [Cowork Plugins Updates 2026 (eesel.ai)](https://www.eesel.ai/blog/claude-cowork-plugins-updates)
- [Anthropic Cowork Office Worker Update (CNBC, Feb 24 2026)](https://www.cnbc.com/2026/02/24/anthropic-claude-cowork-office-worker.html)
- [Cowork Plugin Templates (GitHub)](https://github.com/anthropics/knowledge-work-plugins)
- [Polsia Homepage](https://polsia.com)
- [Polsia $1M ARR Analysis (TeamDay.ai)](https://www.teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies)
- [Polsia Product Hunt](https://www.producthunt.com/products/polsia)
- [Polsia AI Overview (MOGE)](https://moge.ai/product/polsia)
- [Polsia Mixergy Interview](https://mixergy.com/interviews/this-ai-generates-689k/)
- [Andreas Klinger Polsia Review (X/Twitter)](https://x.com/andreasklinger/status/2029932031002415163)
- [SoloCEO](https://soloceoai.com/)
- [Tanka Homepage](https://www.tanka.ai/)
- [Tanka Google Play](https://play.google.com/store/apps/details?id=ai.tanka.app.team)
- [Tanka App Store](https://apps.apple.com/us/app/tanka-ai-agents-for-founders/id6504231775)
- [Tanka AI Guide (tanka.ai blog)](https://www.tanka.ai/blog/posts/the-ultimate-guide-to-tanka)
- [Lovable 2.0 Launch (lovable.dev blog)](https://lovable.dev/blog/lovable-2-0)
- [Lovable Review 2026 (Taskade)](https://www.taskade.com/blog/lovable-review)
- [Lovable One Year (lovable.dev blog)](https://lovable.dev/blog/one-year-of-lovable)
- [Lovable Pricing (lovable.dev)](https://lovable.dev/pricing)
- [Bolt.new Review 2026 (banani.co)](https://www.banani.co/blog/bolt-new-ai-review-and-alternatives)
- [Bolt.new Review 2026 (SimilarLabs)](https://similarlabs.com/blog/bolt-new-review)
- [v0.app Rebrand (Vercel blog)](https://vercel.com/blog/v0-app)
- [v0 New Introduction (Vercel blog)](https://vercel.com/blog/introducing-the-new-v0)
- [v0 Platform API (Vercel blog)](https://vercel.com/blog/build-your-own-ai-app-builder-with-the-v0-platform-api)
- [v0 Review 2026 (NoCode MBA)](https://www.nocode.mba/articles/v0-review-ai-apps)
- [Replit Agent 3 Introduction (Replit blog)](https://blog.replit.com/introducing-agent-3-our-most-autonomous-agent-yet)
- [Replit Pro Plan (Replit blog)](https://blog.replit.com/pro-plan)
- [Replit Pricing](https://replit.com/pricing)
- [Replit Review 2026 (Hackceleration)](https://hackceleration.com/replit-review/)
- [Notion 3.3 Custom Agents Release (Feb 24 2026)](https://www.notion.com/releases/2026-02-24)
- [Notion Custom Agent Pricing](https://www.notion.com/help/custom-agent-pricing)
- [Notion Custom Agents Guide (ALM Corp)](https://almcorp.com/blog/notion-custom-agents/)
- [Notion Pricing](https://www.notion.com/pricing)
- [Systeme.io Pricing](https://systeme.io/pricing)
- [Systeme.io Review 2026 (blogrecode)](https://blogrecode.com/systeme-io-review-the-budget-all-in-one-that-works/)
- [Stripe Atlas](https://stripe.com/atlas)
- [Stripe Atlas Review 2026 (Startup Savant)](https://startupsavant.com/service-reviews/stripe-atlas)
- [Stripe Atlas vs Firstbase vs Doola 2026 (Global Solo)](https://www.globalsolo.global/blog/stripe-atlas-vs-firstbase-vs-doola-pricing-comparison-2026)
- [Firstbase Homepage](https://www.firstbase.io/)
- [Firstbase Pricing](https://www.firstbase.io/pricing)
