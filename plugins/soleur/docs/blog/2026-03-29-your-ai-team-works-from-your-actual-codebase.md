---
title: "Your AI Team Now Works From Your Actual Codebase"
seoTitle: "Your AI Team Now Works From Your Actual Codebase | Soleur"
date: 2026-03-29
description: "Connect your GitHub repo at onboarding and every Soleur agent conversation starts with real project context. No blank workspaces, no lost context."
tags:
  - product-update
  - github
  - agentic-engineering
  - solo-founder
---

Every AI development workflow has the same failure mode: the agent starts with a blank workspace. It does not know your architecture, your brand voice, your legal constraints, or what you shipped last week. You brief it from scratch every session. The context you build evaporates when the session ends.

Soleur agents now operate on your actual codebase. Connect your GitHub repository during onboarding, and every agent conversation starts with full project context — your decisions, your patterns, what you have built so far.

## What Changed

The onboarding flow now includes a repository connection step. You have three options:

**Connect an existing project.** If you already have code on GitHub, install the Soleur GitHub App, select your repository, and your workspace is provisioned with your code. Your AI team reads your knowledge base, brand guide, specifications, and learnings from the first conversation.

**Start fresh.** If you are pre-code or starting a new venture, Soleur creates a private repository under your GitHub account. The workspace scaffolds a knowledge base structure from day one — brainstorms, specs, plans, and learnings directories ready for your first session.

**Skip for now.** Repository connection is optional. You can connect later from Settings.

The entire flow is designed for founders who may not be technical. Plain language, no jargon, clear explanations of what each step does and why.

## How It Works

When you connect a repository, Soleur installs a [GitHub App](https://docs.github.com/en/apps) on your account. The app requests permission to read and manage your project files — nothing else. Your code stays in your GitHub account, under your control.

Behind the scenes:

- **Session start:** Your workspace pulls the latest changes from your repository. If your team (or another agent) pushed changes since your last session, you get them automatically.
- **Session end:** Any changes your AI team made — new specifications, updated brand guide, generated legal documents — are pushed back to your repository.
- **Sync is best-effort.** A failed sync never blocks your session. If something goes wrong, the next session retries. Your work is never interrupted by a network hiccup or a merge conflict.

Authentication uses short-lived GitHub App installation tokens that expire after one hour. No long-lived credentials are stored in your workspace. The AI team accesses your repository through secure, scoped tokens that you can revoke at any time.

## The Compounding Effect

Repository connection is not a convenience feature. It is the infrastructure that makes [compound knowledge]({{ site.url }}blog/why-most-agentic-tools-plateau/) work in practice.

Every Soleur session produces artifacts: brainstorm documents capture design decisions. Plans encode implementation strategy. Learnings record what worked and what did not. Legal agents generate compliance documents. Marketing agents produce content briefs. All of these accumulate in your knowledge base.

Without repository connection, these artifacts exist only in a temporary workspace. They vanish when the session ends. With repository connection, they persist in your GitHub repository. The next session reads them. The session after that builds on them. Your AI team's institutional memory compounds across every conversation, every domain, every decision.

This is the difference between an AI that forgets and an AI team that learns.

## What This Means for Your Workflow

Before repository connection, a typical Soleur session started with context-setting. You explained what you were building, what you had decided, what constraints applied. The AI team was capable but amnesiac.

Now, a typical session starts with the AI team already knowing:

- Your project architecture and codebase
- Your brand voice and messaging guidelines
- Your legal documents and compliance requirements
- Your product roadmap and strategic priorities
- Every decision you have made in previous sessions

The founder's role does not change. You still make every decision. You still approve every output. But the starting point is different. Your AI team begins where the last session ended, not from zero.

## Getting Started

New users see the repository connection flow during onboarding. Existing users can connect a repository from Settings.

The feature is live now. No waitlist, no beta, no pricing change. Repository connection is part of the Soleur open-source platform.

---

**Q: Does Soleur access my private repositories?**

The Soleur GitHub App accesses only the repositories you explicitly select during installation. You choose which repositories to grant access to, and you can modify or revoke that access at any time from your GitHub settings.

**Q: What happens if I disconnect my repository?**

Your workspace continues to function with the code and knowledge base already provisioned. You lose automatic sync — changes will not pull or push until you reconnect. No data is deleted.

**Q: Can I use Soleur without connecting a repository?**

Yes. Repository connection is optional. You can skip it during onboarding and connect later, or use Soleur with a standalone workspace. The AI team works in both modes — repository connection adds persistence and compounding across sessions.

**Q: What if I do not have a GitHub account?**

The onboarding flow requires a GitHub account for repository connection. If you choose "Start Fresh," Soleur creates the repository under your GitHub account. GitHub offers free accounts with unlimited private repositories.

**Q: Is my code sent to third parties?**

Your code stays in your GitHub account and in your local Soleur workspace. Soleur agents read your codebase to understand context. The code itself is processed by Anthropic's Claude models under their [data retention policies](https://www.anthropic.com/policies). No code is stored on Soleur servers or shared with other parties.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Does Soleur access my private repositories?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The Soleur GitHub App accesses only the repositories you explicitly select during installation. You choose which repositories to grant access to, and you can modify or revoke that access at any time from your GitHub settings."
      }
    },
    {
      "@type": "Question",
      "name": "What happens if I disconnect my repository?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Your workspace continues to function with the code and knowledge base already provisioned. You lose automatic sync — changes will not pull or push until you reconnect. No data is deleted."
      }
    },
    {
      "@type": "Question",
      "name": "Can I use Soleur without connecting a repository?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Repository connection is optional. You can skip it during onboarding and connect later, or use Soleur with a standalone workspace. The AI team works in both modes — repository connection adds persistence and compounding across sessions."
      }
    },
    {
      "@type": "Question",
      "name": "What if I do not have a GitHub account?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The onboarding flow requires a GitHub account for repository connection. If you choose Start Fresh, Soleur creates the repository under your GitHub account. GitHub offers free accounts with unlimited private repositories."
      }
    },
    {
      "@type": "Question",
      "name": "Is my code sent to third parties?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Your code stays in your GitHub account and in your local Soleur workspace. Soleur agents read your codebase to understand context. The code itself is processed by Anthropic's Claude models under their data retention policies. No code is stored on Soleur servers or shared with other parties."
      }
    }
  ]
}
</script>
