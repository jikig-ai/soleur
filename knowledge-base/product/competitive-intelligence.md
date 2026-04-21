---
last_updated: 2026-04-21
last_reviewed: 2026-04-21
review_cadence: monthly
owner: CPO
depends_on:
  - knowledge-base/product/business-validation.md
tiers_scanned: [0, 3, "skill-library"]
---

# Competitive Intelligence Report

## Executive Summary

Five material shifts since the 2026-03-12 scan demand strategic attention. **Anthropic's Claude Code source code leaked via npm on March 31, revealing unreleased feature flags including KAIROS (a persistent background assistant with nightly "dreaming" sessions), ULTRAPLAN (30-minute remote cloud planning sessions), and Coordinator Mode (one Claude spawning and managing parallel worker agents).** These features, when shipped, will directly converge on Soleur's workflow orchestration and compounding knowledge advantages. Separately, **Anthropic's Cowork platform shipped Dispatch (persistent phone-to-desktop agent thread), Computer Use (screen-level autonomy), and Recurring/Scheduled Tasks in March** -- transforming Cowork from a stateless template system into an operational agent platform with persistence, scheduling, and cross-device control. **Cursor surpassed $2B ARR (doubled in 3 months) and shipped Composer 2, self-hosted cloud agents GA, and JetBrains integration**, cementing its position as the dominant agent platform in the IDE layer.

In Tier 3, **Polsia accelerated to $4.5M ARR in approximately 3 months (up from $1.5M at last scan), with the founder posting "$4.5M ARR, 0 employees, 3 months"** -- the fastest CaaS traction ever recorded. **Paperclip surged to 30,000+ GitHub stars (up from 14.6k) and shipped a full plugin framework (v2026.318.0)**, accelerating its evolution from bare orchestration into a pluggable company-operating platform. **Notion shipped Notion 3.4 with Dashboard Views, Custom Skills, and Image Generation for agents, extending its multi-domain reach ahead of the May 3 pricing transition.** Lovable expanded beyond app building into "general-purpose co-founder" territory (data analysis, business intelligence, marketing workflows), and Cognition shipped Scheduled Devins, Managed Devins (parallel delegation), and Windsurf Codemaps. Soleur's structural moats -- compounding cross-domain knowledge, founder-in-the-loop orchestration, and 8-domain breadth -- remain intact but are under the most pressure observed to date. The Claude Code source leak is the single most important intelligence item: Anthropic is building features that directly target Soleur's differentiation axis. The timeline is uncertain, but the direction is clear.

---

## Tier 0: Platform Threats

Platform-native competition represents the existential risk tier. These competitors control the model, the distribution surface, or the IDE -- and can bundle AI capabilities that Soleur sells as differentiated features.

### Overlap Matrix

| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| **Anthropic Cowork + Dispatch** | Full 8-domain agent organization | High | **Material update (March 2026).** Three major launches: (1) **Dispatch** (March 17) -- persistent phone-to-desktop agent thread; send tasks from phone, Claude executes locally on computer. (2) **Computer Use in Cowork** -- Claude can open files, run dev tools, point, click, and navigate what is on your screen with no setup required. (3) **Recurring & Scheduled Tasks** -- create scheduled and on-demand tasks with a new Customize section grouping skills, plugins, and connectors. Sonnet 4.6 is now the default model. Excel and PowerPoint add-ins now share full conversation context across applications. Plugin Marketplace and Admin Controls launched for Team and Enterprise plans. LLM gateway connectivity added for Bedrock, Vertex AI, and Foundry users. **Cowork is no longer stateless** -- Dispatch creates persistence, Scheduling creates autonomy, Computer Use creates agency. However, there is still no compounding knowledge base across sessions, no cross-domain coherence, and no workflow lifecycle orchestration. | **Critical** (unchanged) -- The gap between Cowork and Soleur's operational model narrowed significantly. Dispatch + Computer Use + Scheduling = the primitives for an operational agent platform. Anthropic controls the model, API, distribution, and now has cross-device persistence. 7+ of 8 Soleur domains face first-party competition. ([source](https://releasebot.io/updates/anthropic/claude), [source](https://thenewstack.io/anthropic-brings-plugins-to-cowork/)) |
| **Claude Code Native Features** | Engineering workflow agents + plugin ecosystem | High | **Material updates (March-April 2026).** Claude Code shipped significant updates: PowerShell tool for Windows, `--bare` flag for scripted calls, `--channels` permission relay for phone approval prompts, transcript search, named subagents in typeahead, `TaskCreated` hook, `initialPrompt` in agent frontmatter, env credential scrubbing. Performance: 64k default output tokens for Opus 4.6, up to 128k upper bound. Prompt cache miss fix for long sessions. 9,000+ plugins in ecosystem. **Critical intelligence: Source code leak (March 31)** revealed unreleased feature flags: **KAIROS** (persistent background assistant with nightly "dreaming" sessions and proactive task initiation), **ULTRAPLAN** (30-minute remote cloud planning sessions), **Coordinator Mode** (one Claude spawning parallel worker agents), three-layer memory architecture with MEMORY.md pointer index and topic files, and BUDDY (Tamagotchi-style AI pet). Anthropic confirmed "human error," no customer data exposed. Claude Code ARR reported at $2.5B. | **Critical** (upgraded from High) -- KAIROS persistent assistant with "dreaming" sessions directly converges on Soleur's compounding knowledge concept. Coordinator Mode directly converges on Soleur's multi-agent orchestration. The three-layer memory architecture (MEMORY.md + topic files + transcript grep) is architecturally similar to Soleur's knowledge-base approach. Timeline for these features is unknown, but the code is built and sitting behind feature flags. ([source](https://venturebeat.com/technology/claude-codes-source-code-appears-to-have-leaked-heres-what-we-know), [source](https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/), [source](https://fortune.com/2026/03/31/anthropic-source-code-claude-code-data-leak-second-security-lapse-days-after-accidentally-revealing-mythos/), [source](https://releasebot.io/updates/anthropic/claude-code)) |
| **Microsoft Copilot Cowork** | Multi-domain agent organization (enterprise workflow) | Medium | **Material update (March 30, 2026).** Copilot Cowork became available via the Frontier program. Now GA (previously Research Preview with limited customers). Converts user intent into multi-step plans that execute in background across Outlook, Teams, Excel. Clear checkpoints for user approval before actions are applied. Skills from Claude and Microsoft built in (calendar management, daily briefing). Part of M365 E7 Frontier Suite bundling E5, Copilot, and Agent 365 (GA May 1). Multi-model advantage: routes work to model best suited per task (Claude, GPT-5.4 Thinking, GPT-5.3 Instant). Early adopter feedback: useful for planning, scheduling, deliverables, but struggles with nuance and complex exceptions. No engineering domain, no compounding knowledge base, no local-first option. | **Medium-High** (unchanged) -- Frontier GA rollout validates the enterprise agentic workflow category. E7 pricing targets enterprises, not solo founders. However, normalization of "agent plans that execute autonomously" raises baseline user expectations. ([source](https://www.microsoft.com/en-us/microsoft-365/blog/2026/03/30/copilot-cowork-now-available-in-frontier/), [source](https://techcommunity.microsoft.com/blog/microsoft365copilotblog/what%E2%80%99s-new-in-microsoft-365-copilot--march-2026/4506322)) |
| **Cursor (Anysphere)** | Engineering agents, code review, planning | High | **Material updates (March 2026).** Cursor surpassed **$2B ARR** (doubled in 3 months), holds ~25% market share among gen-AI software buyers, 60% revenue from enterprise. Key launches: (1) **Composer 2** technical report published (March 27). (2) **Self-hosted cloud agents GA** -- enterprise-ready with code and execution in-house, up to 8 parallel agents in isolated Ubuntu VMs. (3) **JetBrains integration** via Agent Client Protocol (March 4). (4) **Bugbot** -- original automation, triggered thousands of times daily, has caught millions of bugs. Cursor runs hundreds of automations per hour. Automation templates available at cursor.com/marketplace. Private team marketplaces for Teams/Enterprise. 30+ marketplace plugins from Atlassian, Datadog, GitLab, Glean, Hugging Face, monday.com, PlanetScale. | **Critical** (upgraded from High) -- $2B ARR makes Cursor the commercial leader in AI-assisted development. Self-hosted cloud agents GA + JetBrains integration dramatically expands addressable market. Automations with memory that learns across runs is the closest analog to Soleur's compounding knowledge for engineering tasks. Enterprise-first tilt (60% revenue) reduces direct solo-founder overlap but raises the ceiling for what developers expect from agent platforms. ([source](https://cursor.com/changelog), [source](https://releasebot.io/updates/cursor), [source](https://techcrunch.com/2026/03/05/cursor-is-rolling-out-a-new-system-for-agentic-coding/)) |
| **GitHub Copilot (Coding Agent + CLI)** | Engineering workflow, code review, planning | Medium-High | **Material updates (March 2026).** (1) **Agentic code review shipped March 5** -- gathers full project context before analyzing PRs, can pass suggestions to coding agent for automatic fix PRs (closed loop). (2) **Custom Copilot Agents in Visual Studio** (March 2026 update) -- `.agent.md` files with workspace awareness, model flexibility, MCP connections, auto-discovered skills from `.github/skills/`. (3) **Improved coding agent session visibility** (March 19) -- subagent activity collapsed with HUD, built-in setup step logging. (4) **Copilot CLI v1.0.12** (March 26) -- workspace MCP servers, multi-session support, `/undo` command. (5) **GitHub Spark** -- natural language app builder (Pro+/Enterprise). Copilot CLI reads both `AGENTS.md` and `CLAUDE.md` instruction files. | **Medium-High** (unchanged) -- Agentic code review creating a closed loop (review -> fix PR -> merge) is a significant capability upgrade. Custom agents with `.agent.md` + skills discovery is an emerging agent platform. Distribution advantage remains: bundled with every GitHub paid plan. ([source](https://github.com/features/copilot/whats-new), [source](https://github.blog/changelog/2026-03-19-more-visibility-into-copilot-coding-agent-sessions/), [source](https://www.magnetismsolutions.com/news/visual-studio-march-2026-update-brings-custom-copilot-agents-to-the-forefront)) |
| **OpenAI GPT-5.4 + Codex** | Engineering agents | Medium-High | **Material updates (March 2026).** (1) **GPT-5.3-Codex** released -- most capable agentic coding model, combines Codex + GPT-5 training stacks, 25% faster, real-time steering. (2) **GPT-5.3-Codex-Spark** -- first model designed for real-time coding, 1,000+ tokens/sec, built with Cerebras partnership. (3) **Codex Plugins & Triggers** -- plugins are now first-class (Sentry, Datadog), Triggers auto-respond to GitHub events creating automated pipeline: "Issue arrives -> Auto-fix -> Auto-open PR." (4) **GPT-5.4 mini** available across all Codex surfaces. (5) **Multi-agent v2** with readable path-based addresses and structured inter-agent messaging. Codex Security agent now in broader use. | **Medium-High** (upgraded from Medium) -- Codex Plugins + Triggers create an automated engineering pipeline comparable to Cursor Automations. Multi-agent v2 with structured messaging signals platform maturation. The Codex-Spark model (1,000+ tokens/sec) could enable real-time agent interactions that are impractical at current speeds. OpenAI building a "full agent stack for professional work." ([source](https://developers.openai.com/codex/changelog), [source](https://help.apiyi.com/en/openai-codex-march-2026-updates-summary-plugins-triggers-security-en.html), [source](https://releasebot.io/updates/openai)) |
| **Windsurf/Devin (Cognition)** | Engineering agents, code review | Medium-High | **Material updates (March 2026).** (1) **Scheduled Devins** (March 19) -- Devin schedules its own recurring sessions with state carried between runs via notes. (2) **Managed Devins** (March 1) -- task decomposition with parallel delegation to multiple Devins in isolated VMs. (3) **Windsurf Codemaps** (March 20) -- AI-annotated structured code maps powered by SWE-1.5. (4) **Windsurf pricing increase** to $20/month (from $15), sparking developer backlash. (5) Cognition valued at **$10.2B** post-money, combined enterprise ARR up 30% post-Windsurf acquisition. Category-defining customers: Goldman Sachs, Citi, Dell, Cisco, Ramp, Palantir. Windsurf ranked #1 in LogRocket AI Dev Tool Power Rankings. | **Medium-High** (upgraded from Medium) -- Scheduled Devins with cross-session state is a direct analog to persistent knowledge compounding. Managed Devins (parallel decomposition) converges on Soleur's multi-agent orchestration for engineering tasks. $10.2B valuation and enterprise customer list signal rapid maturation. Still engineering-only with no multi-domain ambition visible. ([source](https://cognition.ai/blog/devin-can-now-schedule-devins), [source](https://docs.devin.ai/release-notes/overview), [source](https://cognition.ai/blog/codemaps)) |
| **Google Gemini Code Assist** | Engineering agents | Low-Medium | **Material updates (March 2026).** (1) **Free for individual developers** -- no credit card, no trial. (2) **Gemini 3.1 Pro and 3.0 Flash** available in Preview for VS Code and IntelliJ. (3) **Agent Mode with Auto Approve** -- acts as intelligent collaborator understanding entire codebase. (4) **Persistent Memory on GitHub** -- stores previous interactions for future context. (5) **Context Drawer UI** for managing conversation context. (6) Code customization supported in CLI and agent mode. Google AI Ultra gives 20x higher limits. | **Low-Medium** (upgraded from Low) -- Free tier with 6,000 daily requests is the most aggressive pricing in the market. Persistent Memory on GitHub is a new capability that was absent at last scan. Agent Mode with Auto Approve signals Google is catching up on agentic capabilities. Still minimal overlap with Soleur's CaaS positioning. ([source](https://developers.google.com/gemini-code-assist/resources/release-notes), [source](https://developers.googleblog.com/unleash-your-development-superpowers-refining-the-core-coding-experience/)) |

### Tier 0 Analysis

**Material changes since last review (2026-03-12):**

1. **Claude Code source leak reveals Soleur-convergent roadmap (March 31).** The most strategically significant event this cycle. KAIROS persistent assistant, Coordinator Mode multi-agent orchestration, and the three-layer memory architecture all target the exact differentiation axes Soleur relies on: compounding knowledge, workflow orchestration, and persistent agent context. The features are built (code exists behind feature flags) but unshipped. Soleur's response window is measured in months, not years. ([source](https://venturebeat.com/technology/claude-codes-source-code-appears-to-have-leaked-heres-what-we-know), [source](https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/))

2. **Anthropic Cowork shipped Dispatch, Computer Use, and Scheduled Tasks (March 2026).** Cowork transitioned from stateless templates to an operational platform. Dispatch creates persistent cross-device agent threads (phone to desktop). Computer Use gives Claude screen-level autonomy. Scheduled Tasks enable recurring workflows. The "stateless and siloed" characterization from our last report is now outdated -- Cowork has persistence and scheduling, though still lacks cross-domain knowledge compounding. ([source](https://releasebot.io/updates/anthropic/claude))

3. **Cursor hit $2B ARR and shipped Composer 2 + self-hosted cloud agents GA (March 2026).** Revenue doubled in 3 months. Self-hosted cloud agents mean enterprise customers can keep code execution in-house while using Cursor's orchestration. JetBrains integration opens the Java/Kotlin/Python developer market. Cursor now runs hundreds of automations per hour. The competitive clock on the engineering layer is accelerating dramatically. ([source](https://cursor.com/changelog), [source](https://releasebot.io/updates/cursor))

4. **OpenAI shipped Codex Plugins, Triggers, and GPT-5.3-Codex-Spark (March 2026).** The automated pipeline (Issue -> Auto-fix -> Auto-PR) via Triggers, combined with first-class plugin support, makes Codex a legitimate agent platform rather than just a model. Codex-Spark at 1,000+ tokens/sec enables real-time agent interactions. Multi-agent v2 with structured messaging signals architectural maturation. ([source](https://developers.openai.com/codex/changelog))

5. **Cognition shipped Scheduled Devins and Managed Devins (March 2026).** Devin can now schedule its own recurring sessions and carry state between runs -- the closest any engineering agent has come to Soleur's compounding knowledge concept. Managed Devins decompose tasks across parallel workers. $10.2B valuation. ([source](https://cognition.ai/blog/devin-can-now-schedule-devins))

6. **GitHub Copilot shipped agentic code review with closed-loop fix generation and custom agents with skills discovery (March 2026).** The review-to-fix pipeline creates an autonomous quality loop. Custom agents via `.agent.md` with auto-discovered skills from `.github/skills/` is structurally similar to Soleur's agent/skill architecture. ([source](https://github.com/features/copilot/whats-new))

**Soleur's remaining Tier 0 advantages:**

- Compounding cross-domain knowledge base across 8 business domains (no competitor has this; KAIROS is the closest planned analog but is engineering-scoped and unshipped)
- Workflow lifecycle orchestration (brainstorm > plan > implement > review > compound) -- no competitor offers this end-to-end lifecycle
- 61+ agents with shared institutional memory across engineering, marketing, legal, operations, product, finance, sales, and support
- Opinionated, curated agent behaviors vs. generic plugin assembly
- Local-first, open-source core vs. cloud-locked enterprise platforms
- Founder-as-decision-maker philosophy vs. enterprise-targeted or fully-autonomous approaches
- Legal, finance, and product strategy domains that no Tier 0 competitor covers

**Critical watch items:**

- KAIROS shipping timeline -- this feature directly threatens Soleur's knowledge compounding moat
- Cowork Dispatch expansion into business domains beyond M365 workflow
- Cursor marketplace expansion into non-engineering plugins

---

## Tier 3: Company-as-a-Service / Full-Stack Business Platforms

Tier 3 competitors either offer AI-powered coding services or position as full-stack business platforms for founders. The overlap with Soleur varies -- some compete on engineering, others on business operations, and a few attempt both.

### Overlap Matrix

| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| **Polsia** | Multi-domain agent organization (autonomous operations) | High | **Material update (March-April 2026).** Polsia reached **$4.5M ARR in ~3 months** (up from $1.5M at last scan), posted "$4.5M ARR, 0 employees, 3 months." Revenue growth: $0 to $1M ARR in 30 days, then $1M to $4.5M in approximately 2 additional months. Manages 1,000+ companies simultaneously. Pricing: **$49/month + 20% revenue share** ("Think incubator, not SaaS"). Polsia provisions everything: email addresses, Render web servers, Neon databases, Stripe accounts, GitHub repos. CEO agent runs Claude Opus 4.6, wakes nightly, evaluates company state, executes tasks, sends morning summary email. Covers engineering, marketing, cold outreach, social media, Meta Ads, and investor inbox management (including VC negotiations). **Key concerns raised by observers:** quality control across 1,000+ autonomous companies, liability for faulty ads/inaccurate information, concentration risk ($49/month as backbone of entire business), sustainability (Claude API costs for 1,000+ companies 24/7). Not compliant with FedRAMP, SOC2, or HIPAA (on roadmap). No legal, finance, or product strategy domains. No structured cross-domain knowledge base. No Claude Code integration -- cloud-hosted proprietary platform. | **High** -- Polsia's $4.5M ARR in 3 months is the strongest market validation of CaaS ever observed. The 20% revenue share model aligns Polsia's incentives with customer success. However, the fully autonomous model (zero human-in-the-loop) is structurally different from Soleur's founder-as-decision-maker approach. Quality concerns at 1,000+ companies may create an opening for Soleur's curated, human-guided approach. ([source](https://www.indiehackers.com/post/tech/growing-a-fully-autonomus-business-to-a-500k-mo-in-3-months-diZ8gkqMHm0CvEsc7Pfo), [source](https://www.contextstudios.ai/blog/polsia-how-a-solo-founder-hit-1m-arr-in-30-days-with-ai-agents), [source](https://polsia.com)) |
| **Paperclip** | Multi-domain workflow orchestration (infrastructure layer) | Medium-High | **Material update (March 2026).** Surged to **30,000+ GitHub stars** (up from 14.6k at last scan), 6,400+ forks. v2026.318.0 (March 18) shipped a **full plugin framework and SDK** with runtime lifecycle management, CLI tooling, settings UI, breadcrumb and slot extensibility. Automated canary and stable release workflows with npm trusted publishing and provenance metadata. Repository actively updated as of March 31, 2026. Agent-runtime-agnostic: supports Claude, OpenClaw, Cursor, Codex, Bash, HTTP webhooks. Features: persistent agent state (resumes across heartbeats), runtime skill injection, governance with rollback, multi-company isolation, portable company templates with secret scrubbing. MIT-licensed, self-hosted, embedded PostgreSQL. No Paperclip account required. | **Medium-High** (upgraded from Medium) -- The plugin framework transforms Paperclip from bare orchestration into a pluggable platform. 30k GitHub stars signal community adoption velocity that could create a de facto standard for multi-agent company orchestration. If third-party plugin developers build domain-specific intelligence on Paperclip's framework, it could offer a "Soleur-like" experience at the orchestration layer without Soleur. Paperclip's architectural choice (bring-your-own-agents) means it could be complementary or competitive depending on whether Soleur publishes a Paperclip adapter. ([source](https://github.com/paperclipai/paperclip), [source](https://github.com/paperclipai/paperclip/releases/tag/v2026.318.0), [source](https://paperclip.ing/)) |
| **Notion AI 3.4 (Custom Agents)** | Multi-domain agent organization (workspace layer) | Medium-High | **Material update (March 26, 2026).** Notion 3.4 shipped: (1) **Dashboard Views** -- database view combining multiple views, KPIs, and key properties into control panels (Business/Enterprise). (2) **Image Generation** in-context with agents. (3) **Custom Skills** -- reusable AI commands accessible from text selection menu or @mention in agent chats. (4) **Presentation mode** -- present directly from pages. (5) **Page Archiving** that improves AI responses by hiding old content from search. (6) **Custom Instructions for AI Meeting Notes.** 21,000+ Custom Agents built, 2,800 running at Notion internally. Real-world impact: Remote's IT Ops Manager reports saving 20 hours/week, 95% triage accuracy, 25%+ autonomous resolution. **Free through May 3, 2026; credit-based pricing after.** Integrations: Slack, Figma, Linear, HubSpot, Asana via MCP. Multi-model: GPT-5.2, Claude Opus 4.5, Gemini 3, MiniMax M2.5. | **Medium-High** (unchanged) -- Custom Skills make Notion agents more programmable, closing the gap with Soleur's skill system. Dashboard Views create a visual command center that solo founders want (per user research). 35M+ user distribution advantage is massive. However, Notion still has no engineering workflow, no structured knowledge base that compounds for business operations, and agents are workspace-scoped not business-scoped. The May 3 pricing transition is a critical inflection point. ([source](https://www.notion.com/releases/2026-03-26), [source](https://releasebot.io/updates/notion)) |
| **Tanka** | Cross-domain knowledge base + agent collaboration | Medium | Tanka positions as "the operating base for the AI-Native era." EverMemOS provides persistent memory via knowledge graphs. Fundraising Agent launched with curated VC network partnership (GRAB Ventures). Upcoming Agent Store for GTM, hiring, and product management agents. Recent app updates: Carry Context Across Outputs (generate next output from previous one with context preserved), @mentions for data source targeting, Weekly Recap in Markdown, cross-team calls. Pricing: **$0/user/month for teams under 50**; $299/month for 50+. SOC 2 Type II and ISO 27001 certified. Mobile apps on iOS and Google Play. Integrates Slack, Gmail, Outlook, Drive, Notion, Dropbox, Telegram. | **Medium** (unchanged) -- EverMemOS remains the closest architectural analog to Soleur's compounding knowledge base. "Carry Context Across Outputs" is functionally similar to Soleur's cross-domain knowledge flow. Agent Store launch would broaden Tanka's domain coverage. Free pricing for teams under 50 is highly competitive for solo founders. Communication-centric with no engineering workflow. ([source](https://www.tanka.ai/), [source](https://www.prnewswire.com/news-releases/tanka-releases-fundraising-agent-ushering-in-a-new-era-of-ai-powered-vertical-agents-for-startup-founders-302556770.html)) |
| **SoloCEO** | Multi-domain agent organization (advisory layer) | Medium | Positions as "AI Executive Board" with AI board members (CFO, CMO, COO, etc.). Advisory-only -- produces diagnostics and recommendations, not operational execution. No material updates found since last scan. Limited public visibility; search results return community sites and general AI-in-boardroom content rather than the specific product. No engineering domain. No compounding knowledge base across sessions. | **Low** (unchanged) -- SoloCEO validates the CaaS advisory thesis but shows no signal of product evolution. Low visibility suggests limited traction. ([source](https://soloceoai.com/)) |
| **Factory AI (Droids)** | Engineering agents (autonomous coding) | Low-Medium | **New entrant to CI report.** Factory builds "agent-native software development" with Droids -- specialized AI coding agents. **Benchmark leader: 58.75% on Terminal-Bench** (state-of-the-art), Droid with Opus beats Claude Code with Opus (58.8% vs 43.2%). Multi-model support (Anthropic + OpenAI). IDE and terminal integration (VS Code, JetBrains, Vim). Full lifecycle: converts tickets/specs to production-ready features. Context management via `Agents.md` standard file. Native integrations: GitHub, GitLab, Jira, Slack, PagerDuty. Exploring running thousands of Droids in parallel. Y Combinator alumnus. SOC 2 attested, ISO 27001 aligned. VPC deployment available. | **Low** -- Engineering-only with no multi-domain ambition. Strong benchmark performance makes Factory relevant as a best-in-class engineering agent. The `Agents.md` context management approach is structurally similar to Soleur's `AGENTS.md`. ([source](https://factory.ai), [source](https://factory.ai/news/terminal-bench), [source](https://stackoverflow.blog/2026/02/04/code-smells-for-ai-agents-q-and-a-with-eno-reyes-of-factory/)) |
| **Cosine (Genie 2)** | Engineering agents (autonomous coding) | Low-Medium | **New entrant to CI report.** Cosine builds Genie 2, a proprietary model for autonomous software engineering. **Benchmark leader: 72% on SWE-Lancer** (outperforming OpenAI and Anthropic). Multi-agent decomposition, local environment integration (runs in actual dev environment, not sandbox), Slack integration. 50+ language support. SOC 2 attested, ISO 27001 aligned. VPC deployment. Y Combinator alumnus. Training approach: taught model how a human engineer works using step-by-step verification and self-play. | **Low** -- Engineering-only with no multi-domain ambition. Genie 2's 72% SWE-Lancer score is the highest benchmark result in the market. Relevant as the most capable autonomous coding agent but does not compete with Soleur's CaaS positioning. ([source](https://cosine.sh), [source](https://cosine.sh/product)) |
| **Lovable.dev** | Engineering agents (web app generation) | Low-Medium | **Material update (March 2026).** Lovable announced expansion beyond app building into **"general-purpose co-founder"** territory: data analysis, business intelligence, presentation decks, marketing workflows. Chat Mode with follow-up questions (agent asks clarifying questions before building). New model support: GPT-5.2 and Gemini 3 Flash (now default model). Test and Live environments for Cloud projects. Google and Apple Sign-In generation. Free managed connectors through April 2026 (Perplexity, Firecrawl, TTS). **$200M ARR, $6.6B valuation** (Series B December 2025). Enterprise customers: Klarna, Uber, Zendesk. | **Low-Medium** (upgraded from Low) -- The "general-purpose co-founder" expansion is a meaningful signal. If Lovable successfully extends beyond app building into business intelligence, marketing, and data analysis, overlap with Soleur's non-engineering domains increases. $200M ARR and $6.6B valuation provide resources for rapid domain expansion. Still fundamentally a web app builder, but the trajectory matters. ([source](https://lovable.dev/blog/chat-mode-and-questions), [source](https://docs.lovable.dev/changelog)) |
| **Bolt.new** | Engineering agents (web app generation) | Low | Bolt V2 added Bolt Cloud (databases, auth, file storage, hosting, analytics). Opus 4.6 with adjustable reasoning depth. Team Templates for reusable project starters. $40M+ ARR. $105.5M Series B at ~$700M valuation. Known limitations: context retention degrades at 15-20+ components, success rate drops to 31% for enterprise-grade features, rewrites entire files instead of targeted edits. Support is AI-only with no human escalation. Open-source bolt.diy for self-hosting. No material March-April 2026 updates found. | **Low** (unchanged) -- Purely engineering/prototyping tool. Bolt Cloud reduces deployment friction but does not expand into business domains. ([source](https://bolt.new/), [source](https://www.banani.co/blog/bolt-new-ai-review-and-alternatives)) |
| **v0.app (Vercel)** | Engineering agents (UI/frontend generation) | Low | **March-April 2026 updates.** February 2026 overhaul continues rolling out: Git integration with branching/PRs, VS Code-compatible editor, database connectors (Snowflake, AWS). Pricing: Free ($0 + $5 credits), Premium ($20/month), Team ($30/user), Business ($100/user), Enterprise. Vercel AI SDK added Gemini 3 support. Marketplace resource transfers between teams. 6M+ developers. Still React/Next.js only. No built-in authentication or provisioned database. "Agentic workflows" promised for 2026 but not yet shipped. | **Low** (unchanged) -- Frontend-focused within Vercel ecosystem. Git workflow integration is useful but does not signal multi-domain expansion. ([source](https://vercel.com/changelog), [source](https://releasebot.io/updates/vercel)) |
| **Replit Agent 4** | Engineering agents (autonomous coding) | Low | **Material update (March 2026).** Agent 4 launched: parallel agents for simultaneous auth/database/backend/frontend work, infinite canvas for design variants, auto merge conflict resolution (90% success rate). **$400M Series D at $9B valuation.** Replit Pro plan with Turbo Mode (2x faster). Teams plan being sunset. 50M+ users. Connectors powering 100k+ active repl connections. Economy/Power/Turbo modes. ChatGPT integration. | **Low** (unchanged) -- Engineering-only, cloud-hosted. $9B valuation reflects category confidence but not CaaS expansion. ChatGPT integration is notable for distribution. ([source](https://blog.replit.com/introducing-agent-4-built-for-creativity), [source](https://docs.replit.com/updates/2026/03/13/changelog)) |
| **Systeme.io** | Marketing and sales agents | Low | All-in-one marketing platform: funnels, email, courses, webinars, affiliate management, blogs. $0-97/month. No AI agent layer. No material updates. | **None** -- Traditional SaaS tool, not an AI platform. ([source](https://systeme.io/pricing)) |
| **Stripe Atlas** | Legal/operations agents (company formation) | None | Delaware C-corp or LLC formation. $500 setup + $100/year registered agent. 23,000 companies formed in 2025. | **None** -- One-time formation service. ([source](https://stripe.com/atlas)) |
| **Firstbase** | Legal/operations agents (company formation) | None | Company formation in Delaware or Wyoming. $399 one-time + $149/year registered agent. Bookkeeping $99/month. | **None** -- Formation-focused service. ([source](https://www.firstbase.io/)) |

### Tier 3 Analysis

**Material changes since last review (2026-03-12):**

1. **Polsia reached $4.5M ARR in ~3 months (up from $1.5M).** Growth trajectory is extraordinary: $0 to $1M in 30 days, $1M to $4.5M in ~60 days. Polsia manages 1,000+ companies and provisions full infrastructure (email, servers, databases, Stripe, GitHub). The $49/month + 20% revenue share model is an incubator model, not traditional SaaS. Quality concerns at scale (1,000+ autonomous companies) and absence of compliance certifications may limit enterprise/serious-founder adoption. ([source](https://www.indiehackers.com/post/tech/growing-a-fully-autonomus-business-to-a-500k-mo-in-3-months-diZ8gkqMHm0CvEsc7Pfo))

2. **Paperclip surged to 30k+ GitHub stars and shipped plugin framework (March 18).** The v2026.318.0 release with a full plugin SDK, CLI tooling, and runtime lifecycle management transforms Paperclip from bare orchestration into a pluggable platform. Community adoption is accelerating (30k stars vs 14.6k at last scan). Paperclip is becoming the open-source standard for multi-agent company orchestration. ([source](https://github.com/paperclipai/paperclip/releases/tag/v2026.318.0))

3. **Notion 3.4 shipped Custom Skills, Dashboard Views, and Image Generation (March 26).** Custom Skills make Notion agents programmable (reusable AI commands), Dashboard Views create visual command centers, and Image Generation adds a creative capability. 21,000+ agents built. May 3 free beta end will be a critical transition -- pricing will determine whether solo founders stay or leave. ([source](https://www.notion.com/releases/2026-03-26))

4. **Lovable expanded to "general-purpose co-founder" (March 19).** Lovable now handles data analysis, business intelligence, presentations, and marketing workflows. This is the first signal of a major "vibe coding" platform expanding into multi-domain territory. At $200M ARR and $6.6B valuation, Lovable has resources to execute. ([source](https://lovable.dev/blog/chat-mode-and-questions))

5. **Cognition shipped Scheduled Devins, Managed Devins, and Windsurf Codemaps (March 2026).** Scheduled Devins with cross-session state and Managed Devins with parallel delegation represent the most capable autonomous engineering agent platform. $10.2B valuation. Windsurf pricing increased to $20/month. ([source](https://cognition.ai/blog/devin-can-now-schedule-devins))

6. **Factory AI and Cosine (Genie 2) emerged as benchmark leaders.** Factory's Droid scored 58.75% on Terminal-Bench (beating Claude Code's 43.2%), and Cosine's Genie 2 scored 72% on SWE-Lancer. These represent the most capable autonomous coding agents in the market but remain engineering-only. ([source](https://factory.ai/news/terminal-bench), [source](https://cosine.sh))

**Soleur's remaining Tier 3 advantages:**

- Only platform combining engineering depth with 8-domain business breadth
- Compounding knowledge base across all domains (Polsia has no cross-domain knowledge compounding; Tanka has memory but communication-scoped; Paperclip has no knowledge layer; Notion has workspace context but not business-domain-structured knowledge)
- Founder-as-decision-maker philosophy (vs. Polsia's fully autonomous approach) -- quality concerns at Polsia's 1,000+ company scale validate human-in-the-loop
- Workflow orchestration (brainstorm > plan > implement > review > compound) -- unique in the market
- Local-first, open-source core (vs. cloud-locked competitors; Paperclip is also open-source but infrastructure-only)
- Legal, finance, and product strategy domains that no Tier 3 competitor covers
- Cross-domain coherence: the brand guide informs marketing content, the legal audit references the privacy policy, the competitive analysis informs product validation

---

## Skill Library Tier: Portable Skill Collections

A complementary category alongside workflow plugins. Skill libraries package reusable SKILL.md instructions (often with CLI tooling) that convert across multiple AI coding tools. They compete on inventory breadth and portability, not on workflow orchestration or compounding knowledge. Convergence risk to Soleur is typically low because the product shapes differ — but the category is worth tracking because a skill library with strong curation signals demand for the skill primitives Soleur orchestrates.

### Overlap Matrix

| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
|---|---|---|---|---|
| **[alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills)** | Soleur plugin (workflow orchestration vs. portable skill library — different product shape) | Low — structurally different (library vs. workflow lifecycle) | 235+ skills across 9 domains; 305 stdlib-Python CLI tools; converts to 12 AI coding tools (Claude Code, Cursor, Aider, Windsurf, etc.); MIT licensed; v2.0.0 (Mar 2026); 12.2k stars; 1.6k forks. No workflow orchestration, no compounding KB, no /one-shot pipeline, no domain leaders. | **Low** — complementary product shape. Watch for: new workflow or orchestration additions; any move toward stateful KB; cross-tool converter gaining traction that erodes Claude Code exclusivity. |

### Tier Analysis

**Material changes since last review (initial entry, 2026-04-21):**

First entry to this tier. Category added to the CI report following the 2026-04-21 comparative audit (see PR `#2734`, parent audit `#2718`). The `peer-plugin-audit` sub-mode of `competitive-analysis` (`#2722`) is the ongoing intake mechanism for new entries to this tier.

**Soleur's advantages in this tier:**

- Workflow lifecycle (brainstorm → plan → implement → review → compound → ship).
- Compounding knowledge base across 8 business domains.
- Domain leaders with cross-delegation.
- Opinionated curation vs. inventory breadth.

**Watch items:**

- New portable skill libraries >10k stars (indicates category demand).
- Existing libraries adding orchestration, KB, or workflow primitives.

---

## New Entrants

Competitors identified during this scan that were not present in the previous competitive-intelligence.md report:

| Entrant | Category | Relevance | Notes |
|---|---|---|---|
| **Factory AI (Droids)** | Autonomous coding agents (Tier 3) | **Low-Medium** | Agent-native software development with Droids. State-of-the-art Terminal-Bench score (58.75%). Multi-model, IDE/terminal integration, full lifecycle from ticket to PR. `Agents.md` context standard. Y Combinator alumnus. Engineering-only. ([source](https://factory.ai)) |
| **Cosine (Genie 2)** | Autonomous coding agents (Tier 3) | **Low-Medium** | Proprietary AI software engineer model. 72% on SWE-Lancer (highest benchmark score in market). Multi-agent decomposition, local environment integration, 50+ languages. Y Combinator alumnus. Engineering-only. ([source](https://cosine.sh)) |

---

## Recommendations

### Priority 1: Prepare for KAIROS and Claude Code Persistent Memory (Immediate -- Critical)

The Claude Code source leak reveals that Anthropic has built (but not shipped) features that directly target Soleur's core differentiation: KAIROS persistent assistant with nightly "dreaming" sessions, Coordinator Mode for multi-agent orchestration, and a three-layer memory architecture (MEMORY.md pointer index + topic files + transcript grep). **Action:** (a) Accelerate documentation of Soleur's knowledge base architecture as a community standard, not a proprietary feature. Position Soleur's knowledge base as the open, human-readable, git-tracked alternative to Anthropic's opaque MEMORY.md system. (b) Identify capabilities KAIROS cannot replicate: cross-domain knowledge compounding across 8 business domains (KAIROS appears engineering-scoped), founder-controlled curation of institutional memory, and the full brainstorm-plan-implement-review-compound lifecycle. (c) Prepare messaging for when KAIROS ships: "KAIROS gives Claude memory. Soleur gives your company memory."

### Priority 2: Respond to Cowork's Operational Platform Evolution (Immediate)

Cowork is no longer stateless. Dispatch (persistent cross-device threads), Computer Use (screen autonomy), and Scheduled Tasks (recurring workflows) make Cowork an operational agent platform with persistence and scheduling. The previous characterization of Cowork as "stateless and siloed" is outdated. **Action:** Update all competitive positioning materials to acknowledge Cowork's new capabilities. Differentiate on: cross-domain knowledge compounding (Cowork still lacks this), workflow lifecycle orchestration (Cowork has tasks, not lifecycles), and the 8-domain breadth of curated agent behaviors vs. generic Cowork plugins. The gap is narrowing -- Soleur's differentiation must emphasize depth and coherence, not breadth alone.

### Priority 3: Frame Polsia's Quality Risk as Soleur's Opportunity (Immediate)

Polsia's $4.5M ARR in 3 months validates the CaaS market at scale. However, quality concerns at 1,000+ autonomous companies, the absence of compliance certifications (no SOC2, no HIPAA), the 20% revenue share model, and the fully autonomous (zero human-in-the-loop) approach create an opening for Soleur's curated, founder-controlled alternative. **Action:** Create content contrasting autonomous output quality vs. human-guided quality at scale. Position Soleur's founder-as-decision-maker philosophy as the premium approach for founders who care about brand integrity, legal compliance, and institutional knowledge. Frame: "Polsia runs your company while you sleep. Soleur helps you run a company worth staying awake for."

### Priority 4: Evaluate Paperclip Adapter Strategy (Near-term)

Paperclip's 30k+ GitHub stars and plugin framework make it a potential distribution channel. Paperclip provides orchestration; Soleur provides domain intelligence. Publishing a Soleur-for-Paperclip adapter could reach Paperclip's growing community without competing head-to-head. **Action:** Evaluate technical feasibility of a Paperclip adapter that exposes Soleur's 8-domain agents within Paperclip's orchestration framework. This would position Soleur as the best-in-class agent layer for Paperclip deployments, riding open-source distribution.

### Priority 5: Position Against Cursor's $2B Platform (Ongoing)

Cursor's $2B ARR and enterprise-first tilt (60% revenue from enterprise) reduce direct solo-founder overlap but raise the ceiling for what developers expect from agent platforms. Automations with cross-run memory, Composer 2, and self-hosted cloud agents are converging on Soleur's engineering workflow differentiation. **Action:** Accept that Soleur cannot compete with Cursor on engineering agent capabilities. Differentiate on the 7 non-engineering domains. Position: "Cursor makes you a 10x engineer. Soleur makes you a 10x company."

### Priority 6: Monitor Notion Custom Agents Pricing Transition (May 3, 2026)

Notion's free beta ends May 3. Credit-based pricing will determine whether Notion agents are affordable for solo founders running autonomous workloads. 21,000+ agents built, Custom Skills shipped, Dashboard Views for visual command centers -- Notion is building the visual, multi-domain agent workspace that user research says founders want. **Action:** Track pricing announcements and user migration patterns. If Notion agents prove affordable for continuous autonomous use, convergence risk escalates. Soleur's advantage remains: no engineering workflow in Notion, no structured business-domain knowledge base, no workflow lifecycle.

### Priority 7: Reassess Revenue Model Against Market Data (Near-term)

Updated pricing landscape: Polsia $49/month + 20% revenue share, Cursor $20-40/month, Notion credit-based (TBD May), Devin $20/month, Windsurf $20/month, Replit $20-100/month, Lovable $25-50/month, Gemini Code Assist free. Soleur's hypothesized $49-99/month must clearly differentiate from Polsia's $49 entry (which includes full autonomous operations). **Action:** The revenue share model (Polsia) and credit-based model (Notion) are emerging alternatives to flat SaaS pricing. Consider whether a value-aligned pricing model (tied to outcomes or usage) would better position Soleur against competitors offering autonomous operations at $49/month.

### Priority 8: Track "General-Purpose Co-Founder" Expansion by Vibe Coding Platforms (30-day review cycle)

Lovable's expansion into data analysis, business intelligence, and marketing workflows signals that well-funded vibe coding platforms ($200M ARR, $6.6B valuation) are moving beyond engineering into multi-domain territory. If Lovable, Bolt, or v0 successfully add business operations capabilities, the competitive landscape shifts materially. **Action:** Monitor monthly for domain expansion announcements from Lovable, Bolt, and v0. The gap between "app builder" and "company builder" is narrowing.

---

_Generated: 2026-04-01_

**Source documents:**

- `knowledge-base/marketing/brand-guide.md` (last updated: 2026-03-26) -- 6 days since last update, within 30-day freshness window
- `knowledge-base/product/business-validation.md` (last updated: 2026-03-22) -- 10 days since last update, within 30-day freshness window

**Research sources:**

- [Anthropic Release Notes March-April 2026 (Releasebot)](https://releasebot.io/updates/anthropic)
- [Claude Code Release Notes (Releasebot)](https://releasebot.io/updates/anthropic/claude-code)
- [Claude Code Source Leak Analysis (VentureBeat)](https://venturebeat.com/technology/claude-codes-source-code-appears-to-have-leaked-heres-what-we-know)
- [Claude Code Source Leak Technical Analysis (Alex Kim Blog)](https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/)
- [Claude Code Source Leak (Fortune)](https://fortune.com/2026/03/31/anthropic-source-code-claude-code-data-leak-second-security-lapse-days-after-accidentally-revealing-mythos/)
- [Claude Code Source Leak (The Register)](https://www.theregister.com/2026/03/31/anthropic_claude_code_source_code/)
- [Claude Code Source Leak (Axios)](https://www.axios.com/2026/03/31/anthropic-leaked-source-code-ai)
- [Claude Code Source Leak (CNBC)](https://www.cnbc.com/2026/03/31/anthropic-leak-claude-code-internal-source.html)
- [Claude Code Source Leak (The Hacker News)](https://thehackernews.com/2026/04/claude-code-tleaked-via-npm-packaging.html)
- [Anthropic Cowork Plugins (The New Stack)](https://thenewstack.io/anthropic-brings-plugins-to-cowork/)
- [Anthropic Cowork Expansion (Constellation Research)](https://www.constellationr.com/insights/news/anthropic-expands-cowork-plugins-across-enterprise-functions)
- [Microsoft Copilot Cowork Frontier GA (Microsoft 365 Blog, Mar 30 2026)](https://www.microsoft.com/en-us/microsoft-365/blog/2026/03/30/copilot-cowork-now-available-in-frontier/)
- [Microsoft 365 Copilot March 2026 Updates (Microsoft Community Hub)](https://techcommunity.microsoft.com/blog/microsoft365copilotblog/what%E2%80%99s-new-in-microsoft-365-copilot--march-2026/4506322)
- [Cursor Changelog (cursor.com)](https://cursor.com/changelog)
- [Cursor Release Notes March 2026 (Releasebot)](https://releasebot.io/updates/cursor)
- [Cursor Automations Launch (TechCrunch, Mar 5 2026)](https://techcrunch.com/2026/03/05/cursor-is-rolling-out-a-new-system-for-agentic-coding/)
- [Cursor New Plugins (Cursor Blog)](https://cursor.com/blog/new-plugins)
- [Cursor March 2026 Updates (Agency Journal)](https://theagencyjournal.com/cursors-march-2026-updates-jetbrains-integration-and-smarter-agents/)
- [GitHub Copilot What's New](https://github.com/features/copilot/whats-new)
- [GitHub Copilot Coding Agent Visibility (GitHub Changelog, Mar 19 2026)](https://github.blog/changelog/2026-03-19-more-visibility-into-copilot-coding-agent-sessions/)
- [Visual Studio March 2026 Custom Copilot Agents (Magnetism Solutions)](https://www.magnetismsolutions.com/news/visual-studio-march-2026-update-brings-custom-copilot-agents-to-the-forefront)
- [GitHub Copilot 2026 Guide (NxCode)](https://www.nxcode.io/resources/news/github-copilot-complete-guide-2026-features-pricing-agents)
- [OpenAI Codex Changelog (OpenAI Developers)](https://developers.openai.com/codex/changelog)
- [OpenAI Codex March 2026 Updates Summary (Apiyi)](https://help.apiyi.com/en/openai-codex-march-2026-updates-summary-plugins-triggers-security-en.html)
- [OpenAI Release Notes (Releasebot)](https://releasebot.io/updates/openai)
- [GPT-5.4 Launch (OpenAI)](https://openai.com/index/introducing-gpt-5-4/)
- [Codex Security Research Preview (OpenAI)](https://openai.com/index/codex-security-now-in-research-preview/)
- [Cognition Blog (cognition.ai)](https://cognition.ai/blog/1)
- [Devin Scheduled Devins (Cognition Blog)](https://cognition.ai/blog/devin-can-now-schedule-devins)
- [Windsurf Codemaps (Cognition Blog)](https://cognition.ai/blog/codemaps)
- [Devin Release Notes (Devin Docs)](https://docs.devin.ai/release-notes/overview)
- [Gemini Code Assist Release Notes (Google Developers)](https://developers.google.com/gemini-code-assist/resources/release-notes)
- [Gemini Code Assist New Features (Google Developers Blog)](https://developers.googleblog.com/unleash-your-development-superpowers-refining-the-core-coding-experience/)
- [Polsia $4.5M ARR (Indie Hackers)](https://www.indiehackers.com/post/tech/growing-a-fully-autonomus-business-to-a-500k-mo-in-3-months-diZ8gkqMHm0CvEsc7Pfo)
- [Polsia $1M ARR Analysis (Context Studios)](https://www.contextstudios.ai/blog/polsia-how-a-solo-founder-hit-1m-arr-in-30-days-with-ai-agents)
- [Polsia Homepage](https://polsia.com)
- [Paperclip GitHub](https://github.com/paperclipai/paperclip)
- [Paperclip v2026.318.0 Release](https://github.com/paperclipai/paperclip/releases/tag/v2026.318.0)
- [Paperclip Homepage](https://paperclip.ing/)
- [Notion 3.4 Release Notes (Mar 26 2026)](https://www.notion.com/releases/2026-03-26)
- [Notion Release Notes (Releasebot)](https://releasebot.io/updates/notion)
- [Tanka Homepage](https://www.tanka.ai/)
- [Tanka Fundraising Agent (PR Newswire)](https://www.prnewswire.com/news-releases/tanka-releases-fundraising-agent-ushering-in-a-new-era-of-ai-powered-vertical-agents-for-startup-founders-302556770.html)
- [SoloCEO Homepage](https://soloceoai.com/)
- [Factory AI Homepage](https://factory.ai)
- [Factory Terminal-Bench Results](https://factory.ai/news/terminal-bench)
- [Factory AI Interview (Stack Overflow Blog, Feb 2026)](https://stackoverflow.blog/2026/02/04/code-smells-for-ai-agents-q-and-a-with-eno-reyes-of-factory/)
- [Cosine Homepage](https://cosine.sh)
- [Cosine Product Page](https://cosine.sh/product)
- [Lovable Chat Mode Blog Post](https://lovable.dev/blog/chat-mode-and-questions)
- [Lovable Changelog](https://docs.lovable.dev/changelog)
- [Bolt.new Homepage](https://bolt.new/)
- [Bolt.new 2026 Review (Banani)](https://www.banani.co/blog/bolt-new-ai-review-and-alternatives)
- [Vercel Changelog](https://vercel.com/changelog)
- [Vercel Release Notes (Releasebot)](https://releasebot.io/updates/vercel)
- [Replit Agent 4 Launch (Replit Blog)](https://blog.replit.com/introducing-agent-4-built-for-creativity)
- [Replit Changelog (Replit Docs)](https://docs.replit.com/updates/2026/03/13/changelog)
- [Replit $400M Series D (PR Newswire)](https://www.prnewswire.com/news-releases/georgian-leads-400m-series-d-investment-in-replit-to-support-continued-investment-in-replit-agent-302711218.html)
- [Systeme.io Pricing](https://systeme.io/pricing)
- [Stripe Atlas](https://stripe.com/atlas)
- [Firstbase](https://www.firstbase.io/)
- [Solo Founder Market Trends (Substack)](https://natesnewsletter.substack.com/p/executive-briefing-one-solo-founder)
- [AI Coding Agents State 2026 (Medium)](https://medium.com/@dave-patten/the-state-of-ai-coding-agents-2026-from-pair-programming-to-autonomous-ai-teams-b11f2b39232a)

---

## Cascade Results

_Generated: 2026-04-01_

Cascade skipped: Task tool not available in this environment. The 4 downstream specialist agents (growth-strategist, pricing-strategist, deal-architect, programmatic-seo-specialist) could not be spawned. Their target files should be manually refreshed with data from this CI report:

| Specialist | Status | Target File | Action Needed |
|---|---|---|---|
| growth-strategist | Not spawned | knowledge-base/marketing/content-strategy.md | Content gap analysis against updated competitors (KAIROS leak, Polsia $4.5M ARR, Lovable general-purpose expansion, Paperclip 30k stars) |
| pricing-strategist | Not spawned | knowledge-base/product/pricing-strategy.md | Competitive pricing matrix refresh (Polsia $49 + 20% rev share, Cursor $2B ARR, Notion credit pricing May 3, Windsurf $20/month) |
| deal-architect | Not spawned | knowledge-base/sales/battlecards/ | Battlecard updates for Cursor ($2B ARR, Composer 2), Polsia ($4.5M ARR), Cowork (Dispatch, Computer Use), Claude Code (KAIROS leak). New battlecards needed for Factory AI and Cosine. |
| programmatic-seo-specialist | Not spawned | knowledge-base/marketing/seo-refresh-queue.md | Flag stale comparison pages: Cursor (major update), Polsia (major update), Cowork (Dispatch/Computer Use). New comparison pages needed for Factory AI and Cosine. |

### Updated Metrics for business-validation.md Reconciliation

The following metrics discovered during this scan are fresher than `knowledge-base/product/business-validation.md` (last updated 2026-03-22):

- **Polsia:** $4.5M ARR (was $1.5M ARR), 1,000+ managed companies (was 2,000+ -- discrepancy, verify), pricing confirmed at $49/month + 20% revenue share
- **Cursor:** $2B ARR (was $1B ARR at last scan), $29.3B valuation, 25% market share, 60% enterprise revenue
- **Paperclip:** 30,000+ GitHub stars (was 14.6k), 6,400+ forks
- **Cognition/Windsurf:** $10.2B valuation, Windsurf pricing increased to $20/month (was $15)
- **Lovable:** $200M ARR, $6.6B valuation, expanding to "general-purpose co-founder"
- **Anthropic Claude Code:** $2.5B ARR reported, $19B total Anthropic annualized revenue
- **Replit:** $9B valuation, $400M Series D, 50M+ users
