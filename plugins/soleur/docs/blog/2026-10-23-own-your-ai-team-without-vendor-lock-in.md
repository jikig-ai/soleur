---
title: "What Happens to Your Business When Your AI Provider Changes the Rules?"
seoTitle: "Own Your AI Team Without Vendor Lock-In | Soleur"
date: 2026-10-23
description: "Don't lock your company's memory into one AI vendor. See how solo founders run an 8-department AI team they actually own — on any model they choose. Start building."
ogImage: "blog/og-ai-team-from-your-codebase.png"
tags:
  - solo-founder
  - vendor-lock-in
  - ai-company-platform
  - solopreneur
  - founder-sovereignty
---

You are three months into building your company. Your AI assistant drafts your contracts, plans your marketing campaigns, remembers your customers, and has learned your brand voice from a hundred conversations. Then on a Tuesday morning, the provider changes its pricing model, throttles your account, or swaps the underlying model — and every workflow you rely on breaks at once.

The contracts it drafted were good. The campaigns it planned were working. The institutional memory it accumulated was real. But all of it lived inside one company's closed system, and you had no way to take it with you.

This is the risk most founders do not see until it is too late.

## The Hidden Risk of Renting Your Company's Brain

Every time you use an AI assistant for business work — writing a privacy policy, structuring a financial model, planning a product roadmap — you are not just generating output. You are accumulating institutional knowledge. Your brand voice sharpens. Your legal posture becomes consistent. Your engineering conventions solidify. Your competitive intelligence deepens.

That knowledge has value. It is the difference between a founder who starts every prompt from scratch and one whose AI partner already understands the business.

But when that knowledge lives inside a single vendor's chat history or proprietary workspace, you do not own it. You are renting your company's brain. The vendor can change the terms, raise the price, deprecate the model, or shut down the service — and your institutional memory goes with it.

For a solo founder, this is a familiar SaaS risk: the tool you depend on can become the tool that controls you.

## What Changes When You Separate Your Team from the Engine

Soleur was built on a different premise: your company's institutional memory should live in plain files inside your own repository, readable by any tool, and your AI team should work across model providers supported by your chosen harness.

Soleur gives a single founder the leverage of a full organization — eight departments covering engineering, marketing, legal, finance, operations, product, sales, and support. Each department has specialist AI agents that share one knowledge base. Every decision, brand guide, legal audit, financial model, and engineering plan is stored as a plain document in your own Git repository.

The founder still decides everything that matters: strategy, approvals, budget, and which model provider to trust. Soleur's AI specialists handle the execution — drafting, planning, reviewing, and documenting across every department — while the institutional memory compounds with every session.

The key architectural decision is separation. Your company's knowledge and your AI team's workflows are not tied to any single model or harness. They live in your repository as plain files. You can run Soleur on Claude Code, Grok Build, Codex, Devin CLI, or OpenCode — and switch between them without losing a single past decision.

## Why Open Weights Models Change the Equation

For founders who want maximum control, open-weights models change the equation. [OpenCode's provider documentation](https://opencode.ai/docs/providers/) lists more than 75 providers and support for running local models through Ollama, llama.cpp, and LM Studio. You can run Soleur workflows on open-weights models configured through those providers, or through other providers supported by your harness.

This means three things:

- **Less model-provider lock-in.** Your brand voice, legal posture, financial models, and engineering conventions are not trapped inside one provider's ecosystem. They live in your repository.
- **Cost control.** You can choose a provider and model tier that fit your budget — from frontier APIs to self-hosted open-weights inference — without losing your file-based knowledge base.
- **Operational sovereignty.** If a provider changes its terms, raises prices, or goes offline, you can switch to another supported provider and your file-based knowledge base remains intact and available.

Soleur's knowledge base is the same regardless of which model powers the conversation. The memory is yours. The team is yours. The model is your choice.

## Plain Files You Can Read, Move, and Keep Forever

Your knowledge-base artifacts — brand guides, legal documents, financial models, engineering plans, competitive analyses, and marketing campaigns — are stored as plain documents in your repository. You can read them, edit them, version them, and move them between projects.

This is not a feature. It is the architecture. Soleur does not store your company's knowledge in a proprietary database or a vendor-locked workspace. It stores it in files you can open in any text editor, search with standard tools, and back up to any cloud provider.

When you switch AI providers, your company's file-based memory comes with you. When you hire a human contractor, they can read the same files. Committed changes to those records are auditable in your Git history.

## What This Means for Solo Founders

The solo founder's biggest risk is not running out of ideas or running out of time. It is building a company whose institutional memory is held hostage by a single vendor.

Soleur eliminates that risk by separating three things that most AI tools bundle together:

- **The memory** (your company's knowledge base) — owned by you, stored in your repo.
- **The team** (67 specialist agents across 8 departments) — runs on any supported harness.
- **The engine** (the underlying AI model) — your choice, switchable at any time.

You get the leverage of a full organization without the dependency on any single provider. Your AI team compounds its knowledge with every session, and that knowledge stays with you regardless of which model or harness you use tomorrow.

## Frequently Asked Questions

### What happens to my company's memory if I switch AI models in Soleur?

Your company's memory lives in plain files inside your own Git repository. Switching models or harnesses does not affect your knowledge base — every decision, brand guide, legal document, and engineering plan remains intact and readable by your new AI team. The memory is yours, not the model provider's.

### Do I need to run my own servers to use open-weights models with my AI team?

No. Soleur runs on supported harnesses — Claude Code, Grok Build, Codex, Devin CLI, and OpenCode. Each harness connects to providers it supports. OpenCode's provider documentation lists support for local models through Ollama, llama.cpp, and LM Studio, as well as hosted providers. You can use frontier APIs, bring-your-own-key providers, or self-hosted open-weights models depending on your preference and technical comfort. Soleur does not require you to operate Soleur-hosted infrastructure; self-hosted model inference has its own requirements.

### How does Soleur keep my marketing, legal, and finance specialists aligned across different AI providers?

All specialists share the same knowledge base — your company's plain-file repository. When you switch providers, the new model can read the same brand guide, legal posture, financial models, and engineering conventions. The institutional memory is stored in files, not in the model's context window, so it remains available to your specialists regardless of which supported provider powers the conversation.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What happens to my company's memory if I switch AI models in Soleur?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Your company's memory lives in plain files inside your own Git repository. Switching models or harnesses does not affect your knowledge base — every decision, brand guide, legal document, and engineering plan remains intact and readable by your new AI team. The memory is yours, not the model provider's."
      }
    },
    {
      "@type": "Question",
      "name": "Do I need to run my own servers to use open-weights models with my AI team?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. Soleur runs on supported harnesses — Claude Code, Grok Build, Codex, Devin CLI, and OpenCode. Each harness connects to providers it supports. OpenCode's provider documentation lists support for local models through Ollama, llama.cpp, and LM Studio, as well as hosted providers. You can use frontier APIs, bring-your-own-key providers, or self-hosted open-weights models depending on your preference and technical comfort. Soleur does not require you to operate Soleur-hosted infrastructure; self-hosted model inference has its own requirements."
      }
    },
    {
      "@type": "Question",
      "name": "How does Soleur keep my marketing, legal, and finance specialists aligned across different AI providers?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "All specialists share the same knowledge base — your company's plain-file repository. When you switch providers, the new model can read the same brand guide, legal posture, financial models, and engineering conventions. The institutional memory is stored in files, not in the model's context window, so it remains available to your specialists regardless of which supported provider powers the conversation."
      }
    }
  ]
}
</script>

---

For the technical write-up on how we built the OpenCode runtime adapter and installer, see [how we built the OpenCode harness support](https://github.com/jikig-ai/soleur/pull/10723).

Ready to build a company you actually own? [Get started with Soleur](https://soleur.ai/getting-started/).
