---
title: "Best Claude Code Plugins 2026: Top Extensions for Solo Founders and Developers"
seoTitle: "Best Claude Code Plugins 2026: Top Claude Code Extensions Ranked"
date: 2026-04-28
description: "The best Claude Code plugins and extensions in 2026 -- from full-stack AI organizations to MCP servers. Which plugins are worth installing for solo founders."
ogImage: "blog/og-best-claude-code-plugins-2026.png"
tags:
  - comparison
  - claude-code
  - claude-code-plugins
  - solo-founder
---

Claude Code became the development environment serious AI builders chose when they needed more than autocomplete. The CLI tool Anthropic released as a terminal-native coding interface quickly attracted an ecosystem of plugins -- first a handful, then dozens, then a marketplace.

The official Anthropic marketplace grew into a catalog spanning engineering tools, productivity extensions, and a thin slice of business-domain plugins. For a solo founder or developer standing in front of that catalog asking which ones are worth installing, the answer is not obvious. Most plugins optimize for a narrow use case. A few aim for something larger.

This is a breakdown of the plugins that matter most in 2026 and what each one is actually good for.

## What Claude Code Plugins Are

Claude Code plugins extend the default Claude Code CLI with slash commands, agents, and skills that the base installation does not include. A plugin is a directory of configuration and instruction files that Claude Code reads at session startup -- making new commands, agents, and workflows available without any configuration beyond the install command.

Beyond plugins, Claude Code supports MCP (Model Context Protocol) servers -- external processes that expose tools like browser automation, API access, and filesystem operations to the Claude session. MCP servers are not plugins in the traditional sense: they are separate processes that register their capabilities over a standardized protocol. The distinction matters when evaluating what you are actually installing.

The best setups combine a foundational plugin for cross-domain organizational workflows with targeted MCP servers for specific tool integrations.

## The 2026 Marketplace Landscape

The Anthropic marketplace grew quickly in engineering-adjacent plugins and grew slowly everywhere else. Engineering coverage -- code review, testing, infrastructure, security -- reached near-saturation in the official catalog. Non-engineering domains told a different story: the overwhelming majority of plugins covered software engineering. Marketing, legal, finance, operations, and product strategy remained undercovered.

This gap is significant for solo founders. Running a company requires legal compliance, financial planning, marketing, and product strategy alongside engineering. The engineering quarter of the problem has excellent tooling. The other three-quarters have coverage that ranges from thin to absent.

That gap is where the most interesting plugins in 2026 live.

## Soleur: The Company-as-a-Service Platform

Soleur is the only Claude Code plugin built to operate as a complete business organization rather than a coding assistant. The distinction is not cosmetic.

Where most plugins extend Claude Code with additional engineering capabilities, Soleur deploys a full multi-department AI organization inside the Claude Code environment: {{ stats.agents }} agents, {{ stats.skills }} skills, and a compounding knowledge base organized across {{ stats.departments }} departments -- engineering, marketing, legal, finance, operations, product, sales, support, and community.

Every department receives the same depth of specialist coverage. The legal agents generate contracts, review compliance requirements, and audit documents. The marketing agents run competitive intelligence, write copy, and build content calendars. The finance agents model revenue and track budget-to-actual variance. The product agents validate specs before engineering starts building them. The engineering agents review code, design architecture, provision infrastructure, and ship.

What makes the organizational model work is not the number of agents -- it is the compounding knowledge base. When the brand-architect agent writes a brand guide, every piece of copy the marketing agents generate afterward reflects it automatically. When the legal agent documents a compliance requirement, the engineering agents reference it before writing the relevant feature. When competitive intelligence updates, the product agents read it before the next roadmap session. Knowledge does not live in siloed contexts. It accumulates across domains and compounds with every session.

This is the architecture the [one-person billion-dollar company]({{ site.url }}/blog/one-person-billion-dollar-company/) requires. An AI software engineer handles one of eight jobs a solo founder needs to do. Soleur is designed to handle all eight -- with each domain informing the others.

**Best for:** Solo founders building companies who need cross-domain organizational intelligence, not just faster coding.

**Pricing:** Open source (Apache 2.0). Core platform is free. Costs are Claude API credits for sessions.

**Install:** `claude plugin install soleur`

## Anthropic Cowork: First-Party Domain Plugins

Anthropic's own Cowork platform delivers domain-specific plugins directly from the model maker. The platform delivers domain-specific plugins covering areas including Brand Voice, Legal, Finance, Engineering, and Operations, making it well-suited for founders who need first-party integrations maintained by Anthropic directly.

Cowork plugins integrate with enterprise connectors -- Google Workspace, DocuSign, Apollo, FactSet, Slack -- making them well-suited for founders who are already embedded in enterprise tool stacks. The Microsoft partnership (Microsoft Copilot Cowork, announced March 2026) extended Cowork's reach into Microsoft 365, giving enterprise-adjacent founders a dual distribution surface.

The tradeoff is scope and architecture. Cowork plugins are domain specialists with enterprise connector integrations. They do not share a compounding knowledge base. Marketing agents do not inherit what legal agents decided. The knowledge that accumulates in a Cowork session belongs to that session, not to a persistent organizational memory that carries forward.

**Best for:** Founders with existing enterprise tool stacks who need deep integration with Google Workspace, Microsoft 365, or financial data providers.

## alirezarezvani/claude-skills: The Cross-Tool Skill Pack

The alirezarezvani/claude-skills repository took a different approach to extending Claude Code: maximum compatibility across AI coding environments. The pack ships 235 production-ready skills across nine domains and claims compatibility with twelve AI tools including Claude Code, Gemini CLI, Cursor, Aider, Windsurf, and OpenCode.

The domain coverage is broad: engineering (core and advanced), product, marketing, project management, regulatory and quality, C-level advisory, business development, and finance. The marketing pod alone spans seven specialized sub-domains.

The architectural difference from Soleur is significant. claude-skills is a skill library: a collection of instructions that work in any compatible tool. Soleur is an organization: a structured system where agents share a persistent knowledge base and cross-domain coherence is built into the architecture. Cross-tool compatibility requires tool-agnostic design. Tool-agnostic design means the knowledge base cannot be integrated at the platform level -- each session still starts from scratch.

For founders who split work across multiple AI tools and need consistent skill coverage everywhere, claude-skills delivers broad reach. For founders who want organizational memory that compounds across every session, the stateless architecture is the ceiling.

**Best for:** Developers who use multiple AI tools and want consistent cross-tool skill coverage.

**Install:** Available on GitHub at alirezarezvani/claude-skills.

## Paperclip: Infrastructure-Layer Orchestration

Paperclip is not a plugin in the conventional sense -- it is an open-source orchestration platform for zero-human company workflows, covering org structures, task scheduling, budget governance, and audit trails. Its growth on GitHub validated a thesis: infrastructure-layer orchestration for automated companies has strong developer appetite.

Where Soleur focuses on domain intelligence and the compounding knowledge base, Paperclip focuses on infrastructure: running agents, managing task queues, and orchestrating workflows programmatically. The upcoming Clipmart -- a library of pre-built company workflow templates -- extends Paperclip toward higher-level business workflows.

The two tools occupy different positions in the stack. Paperclip handles runtime infrastructure; Soleur handles organizational intelligence. The Soleur [comparison with Paperclip]({{ site.url }}/blog/soleur-vs-paperclip/) covers this in more detail.

**Best for:** Technically advanced founders building custom agent pipelines who need a programmable runtime, not a pre-built organization.

**Install:** Open source (MIT). Available on GitHub.

## Essential MCP Servers

MCP servers handle tool integration -- the connections between Claude Code and external systems. The right MCP servers extend what Claude Code can see and do inside a session. The wrong ones add noise. These are the ones that matter:

**Playwright MCP:** Browser automation inside Claude Code sessions. Allows Claude to navigate websites, fill forms, take screenshots, and test web interfaces without leaving the session. Essential for any workflow that touches live web properties -- testing, QA, research, competitor monitoring.

**Context7 MCP:** Real-time library documentation pulled directly into Claude Code sessions. When working with any framework or SDK, Context7 fetches the current official documentation -- catching API changes and deprecated patterns that training data would miss. One of the highest-leverage MCP servers for developers.

**Stripe MCP:** Stripe API access from within Claude Code. Read subscription data, check payment status, query customer records, and manage pricing configurations without leaving the session.

**Vercel MCP:** Vercel project and deployment management from Claude Code. Create deployments, check build status, manage environment variables, and query project analytics.

**Cloudflare MCP:** Cloudflare configuration management -- WAF rules, DNS records, Workers, Zero Trust settings -- directly from the session. Essential for infrastructure work that touches Cloudflare.

## How to Choose

The right Claude Code plugin stack depends on where your actual bottleneck is.

If the bottleneck is engineering velocity -- shipping code faster on well-scoped tasks -- the existing engineering-focused tools in the marketplace are comprehensive. Additional engineering plugins produce diminishing returns quickly.

If the bottleneck is everything else -- legal compliance, financial planning, marketing, product strategy -- the non-engineering quarter of the marketplace is thin. Soleur is the only plugin in the current catalog that covers all eight non-engineering domains with the same depth and cross-domain coherence as a specialist team.

If the bottleneck is tool integration -- connecting Claude Code to external APIs, live web interfaces, or real-time documentation -- targeted MCP servers deliver the most direct value. Playwright, Context7, and the relevant service MCP servers (Stripe, Vercel, Cloudflare) are the highest-leverage additions for most technical founders.

The best performing setup for a solo founder building a company: Soleur as the organizational layer, plus the MCP servers relevant to your infrastructure.

| Plugin | Best for | Pricing | Architecture |
|--------|----------|---------|--------------|
| Soleur | Full-stack AI organization | Free (API costs) | Compounding knowledge base |
| Anthropic Cowork | Enterprise connector integration | Subscription | Session-scoped |
| alirezarezvani/claude-skills | Cross-tool skill coverage | Free | Stateless skill library |
| Paperclip | Custom agent runtime infrastructure | Free (MIT) | Runtime orchestration |
| Playwright MCP | Browser automation | Free | MCP server |
| Context7 MCP | Live library documentation | Free | MCP server |

## FAQ

### What is the best Claude Code plugin for solo founders?

For solo founders building companies, Soleur is the most comprehensive option in the 2026 marketplace. It covers the full organizational stack -- engineering, marketing, legal, finance, operations, product, sales, support, and community -- with a compounding knowledge base that connects domain decisions across every session. Most Claude Code plugins cover engineering only. Running a company requires solving all eight domains, not just the engineering one.

### What are Claude Code extensions vs. plugins vs. MCP servers?

Claude Code plugins are installed packages that add slash commands, agents, and skills to your Claude Code environment at session startup. MCP (Model Context Protocol) servers are external processes that register additional tools -- browser automation, API access, file operations -- using a standardized protocol. Extensions is a general term covering both. For most workflows, plugins handle organizational logic while MCP servers handle external tool integration.

### How many Claude Code plugins are in the Anthropic marketplace?

The official Anthropic marketplace grew substantially through early 2026. Engineering-adjacent plugins dominate the catalog. Non-engineering domains -- marketing, legal, finance, operations -- remain undercovered. For the current count, check the official Anthropic marketplace directly, as the catalog updates continuously.

### Can Claude Code plugins share context with each other?

Most Claude Code plugins are stateless -- each session starts from scratch with no memory of prior decisions. Soleur is the exception: its compounding knowledge base is a git-tracked directory of documents that accumulates decisions across sessions and makes them available to every agent in every domain. Cross-domain knowledge sharing -- legal informing engineering, competitive intelligence informing product strategy -- happens automatically within the Soleur architecture.

### What is the best Claude Code plugin for marketing?

Most Claude Code plugins do not include marketing capabilities. Soleur's marketing department includes agents for competitive intelligence, brand management, content strategy, SEO and AEO auditing, copywriting, paid media, retention, and social distribution -- all reading from the same brand guide and competitive intelligence the rest of the organization uses. For solo founders who need marketing output that reflects the same strategic context as their engineering and legal decisions, Soleur is the only current option.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is the best Claude Code plugin for solo founders?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "For solo founders building companies, Soleur is the most comprehensive option in the 2026 marketplace. It covers the full organizational stack — engineering, marketing, legal, finance, operations, product, sales, support, and community — with a compounding knowledge base that connects domain decisions across every session. Most Claude Code plugins cover engineering only. Running a company requires solving all eight domains, not just the engineering one."
      }
    },
    {
      "@type": "Question",
      "name": "What are Claude Code extensions vs. plugins vs. MCP servers?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Claude Code plugins are installed packages that add slash commands, agents, and skills to your Claude Code environment at session startup. MCP (Model Context Protocol) servers are external processes that register additional tools — browser automation, API access, file operations — using a standardized protocol. Extensions is a general term covering both. For most workflows, plugins handle organizational logic while MCP servers handle external tool integration."
      }
    },
    {
      "@type": "Question",
      "name": "How many Claude Code plugins are in the Anthropic marketplace?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The official Anthropic marketplace grew substantially through early 2026, with engineering-adjacent plugins dominating the catalog. Non-engineering domains — marketing, legal, finance, operations — remain undercovered. Check the official Anthropic marketplace for the current count, as the catalog updates continuously."
      }
    },
    {
      "@type": "Question",
      "name": "Can Claude Code plugins share context with each other?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Most Claude Code plugins are stateless — each session starts from scratch with no memory of prior decisions. Soleur is the exception: its compounding knowledge base is a git-tracked directory of documents that accumulates decisions across sessions and makes them available to every agent in every domain. Cross-domain knowledge sharing — legal informing engineering, competitive intelligence informing product strategy — happens automatically within the Soleur architecture."
      }
    },
    {
      "@type": "Question",
      "name": "What is the best Claude Code plugin for marketing?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Most Claude Code plugins do not include marketing capabilities. Soleur's marketing department includes agents for competitive intelligence, brand management, content strategy, SEO and AEO auditing, copywriting, paid media, retention, and social distribution — all reading from the same brand guide and competitive intelligence the rest of the organization uses."
      }
    }
  ]
}
</script>
