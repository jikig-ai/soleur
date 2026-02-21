# soleur

The Company-as-a-Service platform. Collapse the friction between a startup idea and a billion-dollar outcome.

Currently: an orchestration engine for Claude Code -- agents, workflows, and compounding knowledge.

[![Version](https://img.shields.io/badge/version-2.23.11-blue)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)
[![Website](https://img.shields.io/badge/website-soleur.ai-C9A962)](https://soleur.ai)

## What is Soleur?

Soleur gives a single founder the leverage of a full organization. **45 agents**, **8 commands**, and **45 skills** that compound your company knowledge over time -- every problem you solve makes the next one easier.

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

Apache-2.0. See [LICENSE](LICENSE) for details.
