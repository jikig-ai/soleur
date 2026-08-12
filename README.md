# soleur

The Company-as-a-Service platform. Collapse the friction between a startup idea and a billion-dollar outcome.

68 agents across engineering, finance, legal, marketing, operations, product, sales, and support -- compounding your company knowledge with every session.

[![Version](https://img.shields.io/github/v/release/jikig-ai/soleur)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)
[![Website](https://img.shields.io/badge/website-soleur.ai-C9A962)](https://soleur.ai)

## What is Soleur?

Soleur gives a single founder the leverage of a full organization. **68 agents**, **3 commands**, and **95 skills** that compound your company knowledge over time -- every problem you solve makes the next one easier.

## Installation

**From the marketplace (recommended):**

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
```

This installs the plugin subtree only — about 10 MiB in well under a minute.

<details>
<summary>Installing from this repository directly (slower, and may time out)</summary>

A plain `claude plugin marketplace add jikig-ai/soleur` clones the whole repository (~181 MiB),
which takes about 329 seconds — well past the CLI's 120-second default — and a failed refresh can
leave the local checkout unusable. Add `--sparse` so it fetches only what a plugin install needs;
that completes in about 78 seconds, inside the default limit:

```bash
claude plugin marketplace add jikig-ai/soleur --sparse .claude-plugin plugins
claude plugin install soleur@soleur
```

**Already installed this way?** Switch to the marketplace above — it does not clone the monorepo,
so the migration is not subject to the timeout:

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
claude plugin uninstall soleur@soleur
claude plugin marketplace remove soleur
```

Restart the CLI afterwards; plugin changes apply on restart. If your original install used
`--scope project` or `--scope local`, pass the same `--scope` to every command above — the
default is `user`, and a scope mismatch silently targets an install that isn't there.

Removing the marketplace does **not** reclaim the plugin cache. Measured: after `uninstall`
and `marketplace remove` both succeed, the old plugin cache survives — about 9.6 MiB, with no
CLI verb to reclaim it.

**Do this only once the migration above has completed.** First confirm the new install is live
and the old one is gone:

```bash
claude plugin list
```

You should see `soleur@soleur-marketplace` and no `soleur@soleur`. If you still see
`soleur@soleur`, stop — the migration did not finish, and the directory below is still your
working install.

Then ask the CLI which paths are actually in use, and delete only what is **not** in that list:

```bash
claude plugin list --json | jq -r '.[].installPath'
```

```bash
rm -rf ~/.claude/plugins/cache/soleur
```

The old and new cache directories differ by a single suffix — `soleur` versus
`soleur-marketplace` — so compare against the output above rather than typing from memory.
Note that scope does not change this path: installs made with `--scope project` or
`--scope local` still cache under your home directory, so the directory above is yours to
check regardless of how you installed.


</details>

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
