---
title: Getting Started with Soleur
description: "Install the Soleur Claude Code plugin and start running your company-as-a-service — AI agents for engineering, marketing, legal, finance, and more."
layout: base.njk
permalink: pages/getting-started.html
---

<section class="hero">
  <div class="container">
    <h1>Getting Started with Soleur</h1>
    <p class="subtitle">Install the Claude Code plugin that gives you a full AI organization.</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

## What Is Soleur?

Soleur is a company-as-a-service platform — a single Claude Code plugin that deploys a full AI organization across your business. Instead of hiring across departments, you install one plugin and get agents that handle engineering, marketing, legal, finance, operations, product, sales, and support. Every problem you solve compounds into patterns that make the next one faster.

## Why Soleur

Soleur gives a single founder the operational capacity of a full organization. **{{ stats.agents }} agents** across engineering, finance, marketing, legal, operations, product, sales, and support -- plus **{{ stats.skills }} skills** and **{{ stats.commands }} commands** -- that compound your company knowledge over time. Every problem you solve makes the next one easier.

## Installation

<div class="quickstart-code">
  <pre><code>claude plugin install soleur</code></pre>
</div>

<div class="callout">
  <strong>Existing project?</strong> Run <code>/soleur:sync</code> to analyze your codebase and populate the knowledge base.<br>
  <strong>Starting fresh?</strong> Run <code>/soleur:go</code> and describe what you need.
</div>

## The Workflow

Soleur follows a structured 5-step workflow for software development:

<div class="commands-list">
  <div class="command-item">
    <code>/soleur:go</code>
    <p>The recommended entry point -- describe what you want and Soleur routes to the right workflow</p>
  </div>
</div>

The 5-step workflow (invoked automatically via `/soleur:go` or directly via Skill tool):

<div class="commands-list">
  <div class="command-item">
    <code>1. brainstorm</code>
    <p>Explore what to build</p>
  </div>
  <div class="command-item">
    <code>2. plan</code>
    <p>Create a structured implementation plan</p>
  </div>
  <div class="command-item">
    <code>3. work</code>
    <p>Execute the plan with quality checks</p>
  </div>
  <div class="command-item">
    <code>4. review</code>
    <p>Run multi-agent code review</p>
  </div>
  <div class="command-item">
    <code>5. compound</code>
    <p>Document learnings for future reference</p>
  </div>
</div>

## Commands

<div class="commands-list">
  <div class="command-item">
    <code>/soleur:go</code>
    <p>Unified entry point -- routes to the right workflow skill</p>
  </div>
  <div class="command-item">
    <code>/soleur:sync</code>
    <p>Analyze and document your codebase</p>
  </div>
  <div class="command-item">
    <code>/soleur:help</code>
    <p>List all available components</p>
  </div>
</div>

## Example Workflows

<div class="commands-list">
  <div class="command-item">
    <code>Building a Feature</code>
    <p>/soleur:go build [feature] &rarr; brainstorm &rarr; plan &rarr; work &rarr; review &rarr; compound</p>
  </div>
  <div class="command-item">
    <code>Generating Legal Documents</code>
    <p>/soleur:go generate legal documents &rarr; Terms, Privacy Policy, GDPR Policy, and more</p>
  </div>
  <div class="command-item">
    <code>Fixing a Bug</code>
    <p>/soleur:go fix [bug] &rarr; autonomous fix from plan to PR</p>
  </div>
  <div class="command-item">
    <code>Defining Your Brand</code>
    <p>/soleur:go define our brand identity &rarr; interactive workshop producing a brand guide</p>
  </div>
  <div class="command-item">
    <code>Reviewing a PR</code>
    <p>/soleur:go review &rarr; multi-agent review on existing PR</p>
  </div>
  <div class="command-item">
    <code>Validating a Business Idea</code>
    <p>/soleur:go validate our business idea &rarr; 6-gate validation workshop</p>
  </div>
  <div class="command-item">
    <code>Tracking Expenses</code>
    <p>/soleur:go review our expenses &rarr; routed to ops-advisor agent</p>
  </div>
</div>

## Learn More

<ul class="learn-more-links">
  <li><a href="pages/agents.html">Agents <span class="learn-more-desc">AI agents across engineering, finance, marketing, legal, operations, product, sales, and support</span></a></li>
  <li><a href="pages/skills.html">Skills <span class="learn-more-desc">Multi-step skills for complex workflows</span></a></li>
  <li><a href="pages/changelog.html">Changelog <span class="learn-more-desc">All notable changes to Soleur</span></a></li>
</ul>

## Frequently Asked Questions

<details>
<summary>What do I need to run Soleur?</summary>

Soleur requires the Claude Code CLI with an Anthropic API key or a Claude subscription. Install with `claude plugin install soleur` and run `/soleur:go` to start. No additional dependencies or server setup needed.

</details>

<details>
<summary>Does Soleur work on Windows, Linux, and macOS?</summary>

Soleur runs anywhere Claude Code runs — Linux, macOS, and Windows via WSL. The platform operates entirely within the Claude Code CLI environment with no platform-specific dependencies.

</details>

<details>
<summary>How much does Soleur cost?</summary>

Soleur is free and open source. Your costs depend entirely on your Claude usage through Anthropic. Among solo founder AI tools, Soleur is the only platform that gives you a full AI organization at zero software cost.

</details>

<details>
<summary>What is the difference between /soleur:go and individual skills?</summary>

`/soleur:go` is the unified entry point that classifies your intent and routes to the right workflow automatically. Individual skills like brainstorm, plan, work, and review can be invoked directly when you know exactly which stage you need.

</details>

<details>
<summary>Can I use Soleur with an existing project?</summary>

Yes. Run `/soleur:sync` to analyze your codebase and populate the knowledge base with your project's conventions, architecture, and patterns. Soleur adapts to your existing codebase rather than requiring a fresh start.

</details>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What do I need to run Soleur?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Soleur requires the Claude Code CLI with an Anthropic API key or a Claude subscription. Install with claude plugin install soleur and run /soleur:go to start. No additional dependencies or server setup needed."
      }
    },
    {
      "@type": "Question",
      "name": "Does Soleur work on Windows, Linux, and macOS?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Soleur runs anywhere Claude Code runs — Linux, macOS, and Windows via WSL. The platform operates entirely within the Claude Code CLI environment with no platform-specific dependencies."
      }
    },
    {
      "@type": "Question",
      "name": "How much does Soleur cost?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Soleur is free and open source. Your costs depend entirely on your Claude usage through Anthropic. Among solo founder AI tools, Soleur is the only platform that gives you a full AI organization at zero software cost."
      }
    },
    {
      "@type": "Question",
      "name": "What is the difference between /soleur:go and individual skills?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "/soleur:go is the unified entry point that classifies your intent and routes to the right workflow automatically. Individual skills like brainstorm, plan, work, and review can be invoked directly when you know exactly which stage you need."
      }
    },
    {
      "@type": "Question",
      "name": "Can I use Soleur with an existing project?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Run /soleur:sync to analyze your codebase and populate the knowledge base with your project's conventions, architecture, and patterns. Soleur adapts to your existing codebase rather than requiring a fresh start."
      }
    }
  ]
}
</script>

    </div>
  </div>
</section>
