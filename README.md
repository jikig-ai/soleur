# soleur

The Company-as-a-Service platform. Collapse the friction between a startup idea and a billion-dollar outcome.

60 agents across engineering, finance, marketing, legal, operations, product, sales, and support -- compounding your company knowledge with every session.

[![Version](https://img.shields.io/badge/version-3.3.5-blue)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)
[![Website](https://img.shields.io/badge/website-soleur.ai-C9A962)](https://soleur.ai)

## What is Soleur?

Soleur gives a single founder the leverage of a full organization. **60 agents**, **3 commands**, and **51 skills** that compound your company knowledge over time -- every problem you solve makes the next one easier.

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

The recommended way to use Soleur:

```text
/soleur:go <what you want to do>
```

This classifies your intent and routes to the right workflow. For the full step-by-step:

```text
brainstorm  -->  plan  -->  work  -->  review  -->  compound
```

### Commands

| Command | Purpose |
|---------|---------|
| `/soleur:go` | Unified entry point -- routes to the right workflow skill |
| `/soleur:sync` | Analyze codebase and populate knowledge-base |
| `/soleur:help` | List all available Soleur commands, agents, and skills |

### Workflow Skills

| Skill | Purpose |
|-------|---------|
| `brainstorm` | Explore ideas and make design decisions |
| `plan` | Create structured implementation plans |
| `work` | Execute plans with incremental commits |
| `review` | Run comprehensive code review with specialized agents |
| `compound` | Capture learnings for future work |
| `one-shot` | Full autonomous engineering workflow from plan to PR |

See **[full component reference](./plugins/soleur/README.md)** for all agents, commands, and skills.

## Your AI Organization

| Department | What It Does | Entry Point |
|-----------|-------------|-------------|
| Engineering | Code review, architecture, security, testing, deployment | `/soleur:go` (routes to plan, work, review skills) |
| Finance | Budgeting, revenue analysis, financial reporting, cash flow | Ask about finance (routed via agents) |
| Marketing | Brand identity, content strategy, SEO, community, pricing | `/soleur:go define our brand` |
| Legal | Terms, privacy policy, GDPR, compliance audits | `/legal-generate`, `/legal-audit` |
| Operations | Expense tracking, vendor research, tool provisioning | Ask about ops (routed via agents) |
| Product | Business validation, spec analysis, UX design | `/soleur:go validate our idea` |
| Sales | Pipeline management, outbound prospecting, deal negotiation | Ask about sales (routed via agents) |
| Support | Issue triage, community engagement, customer success | Ask about support (routed via agents) |

## Learn More

- **[Getting Started](https://soleur.ai/getting-started/)** -- Installation, first steps, and workflow overview
- **[Vision](https://soleur.ai/vision/)** -- Where Soleur is headed
- **[Changelog](https://soleur.ai/changelog/)** -- Release history
- **[Community](https://soleur.ai/community/)** -- Discord, contributing, and support

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

BSL 1.1 (Business Source License). See [LICENSE](LICENSE) for details.

Source-available for all individual and internal company use. The only restriction is offering Soleur as a competing hosted service. Each version converts to Apache-2.0 after 4 years. Versions v3.0.10 and earlier remain Apache-2.0.
