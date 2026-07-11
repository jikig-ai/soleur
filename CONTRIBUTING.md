# Contributing to Soleur

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

Clone the repository and run the plugin locally:

```bash
git clone https://github.com/jikig-ai/soleur.git
cd soleur
claude --plugin-dir ./plugins/soleur
```

This loads the plugin directly without installation, so you can test changes immediately.

With [Grok Build](https://docs.x.ai/build/overview), the same in-repo plugin loads automatically via the committed `.grok/config.toml` (project plugin path + Claude-compat hooks/MCP). From the repo root:

```bash
grok inspect   # verify soleur plugin, skills, and MCP servers are discovered
grok --trust   # first session only: trust project hooks (or run /hooks-trust in-session)
grok           # start an interactive session
```

Soleur is hook-heavy; without trust, PreToolUse guards from `.claude/settings.json` stay inactive.

### Grok command naming

Grok and Claude use **different slash-command namespaces** for the same plugin:

| What | Claude Code | Grok Build |
|------|-------------|------------|
| Unified entry | `/soleur:go <intent>` | `/go <intent>` |
| Knowledge-base sync | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/help` |
| Workflow skills | Skill tool (`soleur:brainstorm`, etc.) | Slash commands (`/brainstorm`, `/one-shot`, …) |

Do **not** document `/soleur:go` for Grok sessions — use `/go`. Workflow routing must invoke registered skills (slash commands under Grok, Skill tool under Claude), not improvised steps. See `knowledge-base/engineering/grok-onboarding.md` and `plugins/soleur/lib/harness.ts`.

**Grok agent compat:** Soleur agents are nested under `plugins/soleur/agents/**` (Claude recurses; Grok does not). After adding or renaming an agent, run `cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts` to refresh `.grok/agents/` stubs and `.claude-plugin/agents.manifest.json`.

## Contributor License Agreement

Before your first pull request can be merged, you must sign the [Individual Contributor License Agreement](https://soleur.ai/pages/legal/individual-cla.html) (CLA). The CLA bot will prompt you automatically on your first PR.

**What does the CLA do?** You keep your copyright. Jikigai gets a license to use, distribute, and relicense your contribution -- this is needed because Soleur uses a [Business Source License](LICENSE) with dual licensing.

**If your employer owns your work** (common with full-time employment contracts), ask them to sign the [Corporate CLA](https://soleur.ai/pages/legal/corporate-cla.html) by emailing legal@jikigai.com.

**How it works:** Comment `I have read the CLA Document and I hereby sign the CLA` on your first PR. The CLA bot will record your signature and the check will pass. You only need to sign once.

## Submitting Changes

1. **Check existing issues** before starting work to avoid duplicates.
2. **Branch from `main`** with a descriptive branch name (e.g., `add-skill-x`, `fix-issue-123`).
3. **Write clear commit messages** using conventional prefixes: `feat:`, `fix:`, `docs:`, `chore:`.
4. **Open a pull request** referencing any related issues.

### Plugin changes

Changes to files under `plugins/soleur/` require:

- **PR body `## Changelog` section** -- describe what changed (CI uses this as the GitHub Release body)
- **`semver:patch|minor|major` label** -- CI bumps the version from the latest release tag at merge time
- **`README.md`** -- verify component counts and tables are accurate

Do NOT edit `plugin.json` or `marketplace.json` version fields -- they are frozen sentinels (`0.0.0-dev`).

See the [plugin development guide](plugins/soleur/AGENTS.md) for the full checklist including skill compliance requirements.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.