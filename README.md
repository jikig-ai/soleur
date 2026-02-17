# soleur

Soleur is meant to be a "Company-as-a-Service" platform designed to allow solo founders (soloentrepreneurs) to collapse the friction between a startup idea and a $1B outcome

Currently at phase of being an Orchestration engine for Claude Code -- agents, workflows, and compounding knowledge.

[![Version](https://img.shields.io/badge/version-2.12.0-blue)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)
[![With ❤️ by Soleur](https://img.shields.io/badge/with%20❤️%20by-Soleur-yellow)](https://github.com/jikig-ai/soleur)

## Table of Contents

- [What is Soleur?](#what-is-soleur)
- [The Soleur Vision](#the-soleur-vision)
- [Installation](#installation)
- [The Workflow](#the-workflow)
- [Contributing](#contributing)
- [Community](#community)
- [Credits](#credits)
- [License](#license)

## What is Soleur?

Soleur is meant to be a "Company-as-a-Service" platform designed to allow solo founders (soloentrepreneurs) to collapse the friction between a startup idea and a $1B outcome

AI-powered company orchestration for Claude Code (and Bring Your Own Model later) that get smarter with every use. 
Soleur currently provides **25 agents**, **8 commands**, and **37 skills** that compound your company knowledge (currently only engineering so far) over time -- every problem you solve makes the next one easier.

## Installation

**From the registry (recommended):**

```bash
claude plugin install soleur
```

**From GitHub:**

```bash
claude plugin install --url https://github.com/jikig-ai/soleur/tree/main/plugins/soleur
```

**For existing codebases:** Run `/soleur:sync` first to populate your knowledge-base with conventions and patterns.

## The Workflow

```text
/soleur:brainstorm --> /soleur:plan --> /soleur:work --> /soleur:review --> /soleur:compound
```

| Command | Purpose |
| ------- | ------- |
| `/soleur:sync` | Analyze codebase and populate knowledge-base |
| `/soleur:brainstorm` | Explore ideas and make design decisions |
| `/soleur:plan` | Create structured implementation plans |
| `/soleur:work` | Execute plans with incremental commits |
| `/soleur:review` | Run comprehensive code review with specialized agents |
| `/soleur:compound` | Capture learnings for future work |
| `/soleur:help` | List all available Soleur commands, agents, and skills |
| `/soleur:one-shot` | Full autonomous engineering workflow from plan to PR |

See **[full component reference](./plugins/soleur/README.md)** for all agents, commands, and skills.

## The Soleur Vision

Soleur is a "Company-as-a-Service" platform designed to collapse the friction between a startup idea and a $1B outcome. The world is moving toward infinite leverage. When code and AI can replicate labor at near-zero marginal cost, the only remaining bottlenecks are **Judgment** and **Taste**. Soleur is the vessel that allows those with unique insights to capture the non-linear rewards of the AI revolution.

Soleur is the world's first model-agnostic Orchestration Engine designed to turn a single founder into a billion-dollar enterprise. It provides the architectural "brain" that organizes fragmented AI models into a cohesive, goal-oriented workforce, allowing a human CEO to manage a "Swarm of Agents" instead of a headcount of employees.

By leveraging synthetic labor (AI Agent Swarms), Soleur allows a single founder to act as a high-level curator (CEO) while AI handles the heavy lifting of execution, from MVP to global scale.

### The Core Value Proposition

* **The Billion-Dollar Solopreneur:** Providing the leverage of a 100, 1,000 and more person organization to an individual without the permission of venture capital or the friction of human management.
* **Human-in-the-Loop Governance:** The founder remains the "source of truth," providing judgment and taste, while the "Co-CEO" and "COO" agents translate vision into actionable tasks for specialized swarms (Dev, Marketing, Sales).
* **Iterative Evolution:** Built on "Lean Startup" principles, the platform guides users through a structured path: Idea -> MVP -> PMF ($10k/mo) -> Scale.

### The Model-Agnostic Architecture

* **Bring Your Own Intelligence (BYOI):** Users plug in their own API keys (OpenAI, Anthropic, Gemini, Llama, etc.). This eliminates Soleur's compute overhead and gives the founder total control over their "intelligence spend."
* **The Orchestrator:** Soleur acts as the "Global Brain." It selects the best model for specific tasks (e.g., using Claude for coding, GPT-4o for strategy, and local models for privacy-sensitive data).
* **The Decision Ledger:** A centralized "CEO Dashboard" where the human-in-the-loop reviews, approves, or pivots agent decisions, ensuring the company maintains "Human Taste" while operating at "Machine Speed."

### Strategic Architecture

* **The Coordination Engine:** Moving beyond simple "wrappers," Soleur uses a multi-agent hierarchy where "Lead Agents" manage specialized sub-swarms, preventing the CEO from becoming a micro-management bottleneck.
* **Recursive Dogfooding:** Soleur is built using its own engine. The platform's own growth, marketing, and code maintenance are handled by Soleur agents, ensuring the product is battle-tested by its creators daily.

### The Revenue Philosophy

Since Soleur isn't reselling tokens, the pricing shifts from "Utility" to "Value Capture":

* **Low Barrier Entry:** Free or low-cost access for the "Idea Phase." Founders only pay their model providers, making Soleur the obvious choice for experimentation.
* **The Success Tax:** A tiered revenue-share model (e.g., 5% after hitting $10k/month ARR). We are not charging for software; we are charging for leveraged outcomes.
* **Enterprise/Scale Tier:** High-performance "Lead Agent" templates and advanced coordination logic for companies scaling toward the $1B mark.

### Strategic Milestones (The "Ladder")

* **Phase 1 (The Toy):** Build a single-agent Micro-SaaS.
* **Phase 2 (The Business):** Automate the "Lean Startup" loop (Build -> Measure -> Learn) using specialized swarms.
* **Phase 3 (The Empire):** Autonomous scaling where the founder focuses 100% on Judgment, Brand, and Strategy, while Soleur handles the 99% of execution.

### The Competitive Edge: Recursive Dogfooding

Soleur is built by Soleur. The platform's code, marketing, and customer support are all managed by its own internal swarms using various API keys. This ensures the system is inherently practical--if the agents can't build the platform, they aren't ready to build the customers' companies.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started, file issues, and submit pull requests.

## Community

Join the conversation on [Discord](https://discord.gg/PYZbPBKMUY).

## Credits

This work builds on ideas and patterns from these excellent projects:

- [Compound Engineering Plugin](https://github.com/EveryInc/compound-engineering-plugin) - The original Claude Code plugin that inspired this work
- [OpenSpec](https://github.com/Fission-AI/OpenSpec) - Spec-driven development (SDD) for AI coding assistants
- [Spec-Kit](https://github.com/github/spec-kit) - GitHub's toolkit for spec-driven development

## License

Apache-2.0. See [LICENSE](LICENSE) for details.

