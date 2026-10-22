# soleur

The Company-as-a-Service platform. Collapse the friction between a startup idea and a billion-dollar outcome.

67 agents across engineering, finance, legal, marketing, operations, product, sales, and support -- compounding your company knowledge with every session.

[![Version](https://img.shields.io/github/v/release/jikig-ai/soleur)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)
[![Website](https://img.shields.io/badge/website-soleur.ai-C9A962)](https://soleur.ai)

## What is Soleur?

Soleur gives a single founder the leverage of a full organization. **67 agents**, **4 commands**, and **103 skills** that compound your company knowledge over time -- every problem you solve makes the next one easier.

## Installation

**Devin CLI:**

```bash
devin plugins install jikig-ai/soleur#plugins/soleur -y
```

Start a Devin session and use `/soleur:go <what you want to do>`. Use `-y` to skip the confirmation prompt. If the install hangs or fails, clone the repository and run `bash scripts/setup-devin.sh` to install from the local checkout.

Update to the latest version with `devin plugins update soleur`, or `devin plugins update` to refresh all installed plugins. If you see a transient "content could not be fetched" warning, Devin will retry automatically; run the update command again if it persists.

The plugin also loads in **Devin Cloud** sessions (`/handoff` or web app). Cloud sessions run under Soleur Cloud Mode — plugin subagents and SessionStart/SessionEnd hooks are absent, so fan-out runs sequentially inline with `Reviewed-Coverage: sequential-fallback` disclosure and secrets/production steps require an explicit session-scoped acknowledgement. See the [capability matrix](plugins/soleur/devin/INSTRUCTIONS.md#cloud-mode-devin-cloud-sessions).

**Codex:**

```bash
codex plugin marketplace add jikig-ai/soleur --sparse .agents/plugins --sparse plugins/soleur
codex plugin add soleur@soleur
```

Start a new Codex session, review the bundled hooks in `/hooks`, and use
`$soleur:go <what you want to do>`. See the
[Codex setup guide](knowledge-base/engineering/codex-onboarding.md) for local
development, updates, and compatibility details.

**Grok Build:**

Soleur loads the same in-repo plugin under Grok Build. From the repository root, confirm the plugin is discovered and start a session:

```bash
grok inspect    # the soleur plugin, skills, agents, and MCP servers must appear
grok            # interactive session
```

Use `/go <what you want to do>` (Grok's bare entry name), not `/soleur:go`. If `grok inspect` does not list Soleur, stop — there is no `grok plugin install` command to fall back on today, so install is done by pointing Grok at this repository (`.grok/config.toml`, merged via the project plugin loader) rather than a marketplace command. Full setup — subagent spawning, trust, and command naming — is in the [Grok Build onboarding guide](knowledge-base/engineering/grok-onboarding.md).

**OpenCode:**

Install Soleur into your OpenCode config directory via npm (this needs `bun` on `PATH`), then start a session:

```bash
npx @soleur/opencode install
# or: bunx @soleur/opencode install
```

Verify the install with `npx @soleur/opencode install --check` — it prints `opencode-install ok` when the vendored payload in `~/.config/opencode/soleur/` matches. (From a local checkout of this repository, you can also run `bun plugins/soleur/scripts/install-opencode-adapter.ts` and keep the checkout in place.) Use `/go <what you want to do>`. Commands are bare (`/go`, `/sync`, `/help`) and skills are invoked by bare id (`plan`, not `soleur:plan`), because OpenCode has no `soleur:` namespace. Two guards decide shell commands on OpenCode, and both run for real — a `deny` blocks the call, an `ask` opens a prompt — but they decide shell calls only: actions taken through OpenCode's code-mode `execute` are not covered. Soleur's operator-stage approval gate is not wired on OpenCode: those flows refuse rather than approve. OpenCode has no Stop hook, so the pipeline's `<promise>DONE</promise>` completion marker is advisory: a finished gate sequence is reported rather than hard-stopped, and autonomous skills rely on their own structural checks. `/version` is installed but reports an unknown version, because the canonical command resolves the plugin through `CLAUDE_PLUGIN_ROOT`, which this harness does not set. Full routing rules and the remaining capability differences: [OpenCode instructions](plugins/soleur/opencode/INSTRUCTIONS.md).

**Claude Code (recommended, via the published marketplace):**

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
claude plugin marketplace update soleur-marketplace       # advances the marketplace checkout ONLY
claude plugin update soleur@soleur-marketplace            # updates the installed plugin (restart to apply)
```

Both halves name the marketplace. On current releases the bare plugin name can fail with
`Plugin not found` — an Anthropic collaborator confirmed the `<plugin>@<marketplace>` form as
the reliable one on anthropics/claude-code#76882 (2026-08-17). `soleur-marketplace` is the
marketplace id on the path above; if you added this repository directly the id is `soleur`
instead, so run `claude plugin list` and use whatever it prints beside `soleur`.

`marketplace update` moves the marketplace checkout to the new HEAD. It does **not** touch
the plugin install, which keeps its own `gitCommitSha` in `installed_plugins.json`. Soleur's
commands resolve `${CLAUDE_PLUGIN_ROOT}` to the *install*, never the marketplace checkout —
so after step 1 alone you can read a fix as shipped while every run still executes the old
payload.

**If the fix still isn't taking effect after both steps,** reinstall outright:

```bash
claude plugin uninstall soleur@soleur-marketplace && claude plugin install soleur@soleur-marketplace
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
| `/soleur:version` | Show the installed plugin version and whether a newer release exists (Claude Code only) |

Claude Code: `/soleur:go`. Grok Build: `/go`. Codex: `$soleur:go`. Devin CLI: `/soleur:go`. OpenCode: `/go`.

| Step | Claude Code | Grok Build | Codex | Devin CLI | OpenCode |
|------|-------------|------------|-------|-----------|----------|
| Entry | `/soleur:go` | `/go` | `$soleur:go` | `/soleur:go` | `/go` |
| Sync | `/soleur:sync` | `/sync` | `$soleur:sync` | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/local:help` | `$soleur:help` | `/soleur:help` | `/help` |
| Version | `/soleur:version` (Claude Code only) | not available | not available | not available | `/version` (reports unknown) |
| Next skill | Skill tool `soleur:<skill>` | Read `SKILL.md` in this process (`/<skill>`) | Load `$soleur:<skill>`, or read `SKILL.md` | Slash `/soleur:<skill>` | `skill` tool, bare id (`plan`) |

Per-harness setup guides: [Claude Code](https://code.claude.com/docs/en/plugins) · [Grok Build](knowledge-base/engineering/grok-onboarding.md) · [Codex](knowledge-base/engineering/codex-onboarding.md) · [Devin](plugins/soleur/devin/INSTRUCTIONS.md) · [OpenCode](plugins/soleur/opencode/INSTRUCTIONS.md).

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
