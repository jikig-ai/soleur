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

A first-time `claude plugin marketplace add jikig-ai/soleur` clones the whole repository
(~181 MiB), which takes about 329 seconds — well past the CLI's 120-second default. Add `--sparse`
so it fetches only what a plugin install needs; that completes in about 78 seconds, inside the
default limit:

```bash
claude plugin marketplace add jikig-ai/soleur --sparse .claude-plugin plugins
claude plugin install soleur@soleur
```

**Only on a first add.** If you already have a plain `~/.claude/plugins/marketplaces/soleur`
checkout, do **not** add `--sparse` to it: applying `--sparse` to an existing checkout does not
convert it in place, it forces a full re-clone — which on this repository is the 329-second
operation that cannot finish under the 120-second default. Migrate instead, using the commands
below. Details and recovery: the
[plugin delivery runbook](knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md),
under `## Symptom 2`.

Once the checkout exists, routine refreshes are incremental `git pull`s rather than fresh clones, so
the 329 seconds is a one-time cost of adding this way — but it is paid again whenever a refresh
cannot update in place and restarts as a re-clone.

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

Removing the marketplace does **not** reclaim the plugin cache — though it does remove the
marketplace checkout itself. Measured: after `uninstall` and `marketplace remove` both succeed, the
378 MiB checkout is gone and the old plugin **cache** survives — 26 MiB on the machine this was
measured on, with no CLI verb to reclaim it. Expect more the longer the install has been updating:
each update caches into a new directory and leaves the previous one behind.

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

## Updating

Updating is **two steps**, and the first one looks sufficient on its own:

```bash
claude plugin marketplace update soleur   # advances the marketplace checkout ONLY
claude plugin update soleur               # updates the installed plugin (restart to apply)
```

`marketplace update` moves the marketplace checkout to the new HEAD. It does **not** touch
the plugin install, which keeps its own `gitCommitSha` in `installed_plugins.json`. Soleur's
commands resolve `${CLAUDE_PLUGIN_ROOT}` to the *install*, never the marketplace checkout —
so after step 1 alone you can read a fix as shipped while every run still executes the old
payload.

**If the fix still isn't taking effect after both steps,** reinstall outright:

```bash
claude plugin uninstall soleur && claude plugin install soleur
```

That used to be the only step that worked, and the reason no longer holds. The manifests are
keyless as of 2026-08-12, so the CLI now records a **compound version whose leading half is the
delivered commit** — measured across two installs on the same day as `43c7d3d79542-31fddb37` then
`0d6443960662-31fddb37`. The string therefore changes with every commit, the install directory
name changes with it, and `plugin update` has something to compare. The old frozen `0.0.0-dev`
sentinel is what made an install sit months stale while every command reported success; that is
the defect the keyless manifests removed.

Two consequences worth knowing:

- A full reinstall is still the surest way to converge a stubborn install, but it is a fallback
  now rather than the only mechanism.
- Because the directory name is derived from that changing version, **each update leaves the
  previous cache directory behind**. There is no CLI verb to reclaim them. See the reclaim section
  of `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md`.

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
