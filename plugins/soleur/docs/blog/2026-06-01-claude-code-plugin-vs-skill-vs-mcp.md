---
title: "Claude Code Plugin vs Skill vs MCP: A Clear Disambiguation"
seoTitle: "Claude Code Plugin vs Skill vs MCP: Scope, Lifecycle, Distribution"
date: 2026-06-01
description: "Plugins, skills, and MCP servers are the three ways to extend Claude Code, and they are constantly conflated. A clear table of scope, lifecycle, and distribution."
ogImage: "blog/og-best-claude-code-plugins-2026.png"
tags:
  - claude-code
  - agentic-engineering
  - mcp
  - solo-founder
---

Three terms get used interchangeably when people talk about extending Claude Code: **plugin**, **skill**, and **MCP server**. They are not the same thing. They operate at different layers, load at different times, and ship through different channels. Conflating them leads to bad architecture decisions — packaging a one-off instruction as an MCP server, or reaching for a plugin when a skill would do.

This post draws the lines cleanly. Each primitive answers a different question: a **skill** answers "what should the model know how to do," an **MCP server** answers "what external systems can the model reach," and a **plugin** answers "how do I distribute a bundle of capabilities to a team."

## The one-line definitions

- A **skill** is a packaged unit of procedural knowledge — a `SKILL.md` file (plus optional scripts and references) that teaches the model how to perform a task. It is loaded on demand when the task is relevant. ([Agent Skills documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills))
- An **MCP server** is a separate process that exposes tools, resources, and prompts over the [Model Context Protocol](https://modelcontextprotocol.io/), an open standard for connecting AI applications to external systems. It is how the model reaches databases, APIs, and services. ([MCP in Claude Code](https://docs.claude.com/en/docs/claude-code/mcp))
- A **plugin** is a distributable bundle that can contain commands, agents, skills, hooks, and MCP server configuration, installed as a single unit and shared across a team via a marketplace. ([Claude Code plugins documentation](https://docs.claude.com/en/docs/claude-code/plugins))

## Plugin vs Skill vs MCP: the disambiguation table

| Dimension | Skill | MCP server | Plugin |
|-----------|-------|------------|--------|
| What it is | Packaged procedural knowledge (`SKILL.md` + assets) | A process exposing tools, resources, and prompts over an open protocol | A distributable bundle of commands, agents, skills, hooks, and MCP config |
| Scope | Teaches the model how to do a task | Connects the model to external systems and data | Packages and distributes many capabilities at once |
| Lifecycle | Loaded on demand when the task is relevant | Runs as a long-lived process; connected for the session | Installed once; its contents load per their own rules |
| Runs where | In-context, no separate process | A separate local or remote process | N/A — a container; its parts run per their type |
| Distribution | A directory or repo; bundled inside plugins | Configured per project or user; published to MCP registries | Installed from a plugin marketplace |
| Answers | "What should the model know how to do?" | "What systems can the model reach?" | "How do I ship a capability set to a team?" |

The key insight: these are **composable, not competing**. A plugin can ship skills and wire up MCP servers. A skill can describe how to use the tools an MCP server exposes. You rarely choose one *instead of* another — you choose which layer a given capability belongs to.

## How to choose

- Reach for a **skill** when you are encoding a repeatable procedure — a workflow, a checklist, a domain method — that the model should apply when relevant. No new process, no external connection.
- Reach for an **MCP server** when the model needs to *touch something outside itself*: query a database, call an API, read a file store, hit a SaaS product. If it requires authentication or a network call to a system, it is an MCP concern.
- Reach for a **plugin** when you have a *set* of capabilities — several commands, a few agents, a handful of skills, maybe an MCP server — that you want to install and version as one unit and share with a team.

For a ranked, opinionated tour of what is actually worth installing across all three, see [Best Claude Code Plugins 2026](/blog/best-claude-code-plugins-2026/). For the deeper distinction between portable skill libraries and end-to-end workflow plugins — the two dominant *shapes* a plugin takes — read [Skill Libraries vs. Workflow Plugins](/blog/skill-libraries-vs-workflow-plugins/).

Soleur itself is a plugin: it ships {{ stats.agents }} agents and {{ stats.skills }} skills across {{ stats.departments }} departments, and configures the MCP servers its agents rely on — one install, the whole [Company-as-a-Service](/company-as-a-service/) organization.

## Frequently asked questions

<div class="faq-list">
  <details class="faq-item">
    <summary class="faq-question">What is the difference between a Claude Code plugin, skill, and MCP server?</summary>
    <p class="faq-answer">A skill is packaged procedural knowledge that teaches the model how to do a task and loads on demand. An MCP server is a separate process that connects the model to external systems and data over an open protocol. A plugin is a distributable bundle that can contain commands, agents, skills, hooks, and MCP server configuration, installed as a single unit. They operate at different layers and are composable, not competing.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">When should I use a skill instead of an MCP server?</summary>
    <p class="faq-answer">Use a skill when you are encoding a repeatable procedure the model should apply when relevant, with no external connection required. Use an MCP server when the model needs to reach something outside itself, such as a database, an API, or a SaaS product, which requires a running process and usually authentication. Skills teach know-how; MCP servers provide reach.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Can a plugin contain skills and MCP servers?</summary>
    <p class="faq-answer">Yes. A plugin is a container. It can bundle commands, agents, skills, hooks, and MCP server configuration and install them all as one versioned unit. This is why the three primitives are composable rather than mutually exclusive: the plugin is the distribution layer, while skills and MCP servers are the capability layers inside it.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Which one do I distribute to my team?</summary>
    <p class="faq-answer">Distribute a plugin. Plugins install from a marketplace as a single versioned unit and can carry many skills, agents, and MCP server configurations at once, so a team installs one thing and gets the whole capability set. Individual skills and MCP servers can be shared on their own, but a plugin is the channel built for packaging and sharing a set of capabilities.</p>
  </details>
</div>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is the difference between a Claude Code plugin, skill, and MCP server?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A skill is packaged procedural knowledge that teaches the model how to do a task and loads on demand. An MCP server is a separate process that connects the model to external systems and data over an open protocol. A plugin is a distributable bundle that can contain commands, agents, skills, hooks, and MCP server configuration, installed as a single unit. They operate at different layers and are composable, not competing."
      }
    },
    {
      "@type": "Question",
      "name": "When should I use a skill instead of an MCP server?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Use a skill when you are encoding a repeatable procedure the model should apply when relevant, with no external connection required. Use an MCP server when the model needs to reach something outside itself, such as a database, an API, or a SaaS product, which requires a running process and usually authentication. Skills teach know-how; MCP servers provide reach."
      }
    },
    {
      "@type": "Question",
      "name": "Can a plugin contain skills and MCP servers?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. A plugin is a container. It can bundle commands, agents, skills, hooks, and MCP server configuration and install them all as one versioned unit. This is why the three primitives are composable rather than mutually exclusive: the plugin is the distribution layer, while skills and MCP servers are the capability layers inside it."
      }
    },
    {
      "@type": "Question",
      "name": "Which one do I distribute to my team?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Distribute a plugin. Plugins install from a marketplace as a single versioned unit and can carry many skills, agents, and MCP server configurations at once, so a team installs one thing and gets the whole capability set. Individual skills and MCP servers can be shared on their own, but a plugin is the channel built for packaging and sharing a set of capabilities."
      }
    }
  ]
}
</script>
