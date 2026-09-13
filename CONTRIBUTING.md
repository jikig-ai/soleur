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

### Codex

From the repository or feature worktree root:

```bash
bash scripts/setup-codex.sh
codex
```

Review the project and plugin hooks in `/hooks`, then use `$soleur:go <intent>`.
After plugin edits, repeat `codex plugin add soleur@soleur` and start a new
session: Codex runs the installed cache, not the source directory.
Run `node scripts/codex-plugin-smoke.mjs` to verify native discovery without
model calls. See [Codex onboarding](knowledge-base/engineering/codex-onboarding.md)
for the supported repository guards and remaining harness differences.

With [Grok Build](https://docs.x.ai/build/overview), the same in-repo plugin loads automatically via the committed `.grok/config.toml` (project plugin path + Claude-compat hooks/MCP). From the repo root:

```bash
grok inspect   # verify soleur plugin, skills, and MCP servers are discovered
grok           # start an interactive session
```

Soleur is hook-heavy. Live CLI 1.0.29 has no `grok --trust` — do not invent one. Use `/hooks` in-session for the unified extensions modal. Unarmed hooks skip with `SOLEUR_HOOK_SKIP reason=untrusted-session`.

### Grok command naming

Grok and Claude use **different slash-command namespaces** for the same plugin:

| What | Claude Code | Grok Build |
|------|-------------|------------|
| Unified entry | `/soleur:go <intent>` | `/go <intent>` |
| Knowledge-base sync | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/help` |
| Workflow skills | Skill tool (`soleur:brainstorm`, etc.) | Slash commands (`/brainstorm`, `/one-shot`, …) |

Do **not** document `/soleur:go` for Grok sessions — use `/go`. Workflow routing must invoke registered skills (slash commands under Grok, Skill tool under Claude), not improvised steps. See `knowledge-base/engineering/grok-onboarding.md` and `plugins/soleur/lib/harness.ts`.

Before `git push` under Grok Build, run `bash plugins/soleur/scripts/grok-pre-push-gate.sh` from the repo root (local CI parity: `test-all.sh` + fast required checks + `grok-fidelity`). Do not push and wait for CI to fail.

**Grok agent compat:** Soleur agents are nested under `plugins/soleur/agents/**` (Claude recurses; Grok does not). After adding or renaming an agent, run `cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts` to refresh `.grok/agents/` stubs and `.claude-plugin/agents.manifest.json`.

## Contributor License Agreement

Before your first pull request can be merged, you must sign the [Individual Contributor License Agreement](https://soleur.ai/pages/legal/individual-cla.html) (CLA). The CLA bot will prompt you automatically on your first PR.

**How it works:** Comment `I have read the CLA Document and I hereby sign the CLA` on your first PR. The CLA bot records your signature and the check passes. That is the whole ask, and you only need to sign once.

**What does the CLA do?** You keep your copyright. Jikigai gets a license to use, distribute, and relicense your contribution -- this is needed because Soleur uses a [Business Source License](LICENSE) with dual licensing.

**If your employer owns your work** (common with full-time employment contracts), a [Corporate CLA](https://soleur.ai/pages/legal/corporate-cla.html) is also needed -- **and chasing it is the maintainer's job, not yours.** Do not hold your pull request back on it, and do not approach your employer's legal team yourself. Send us your employer's name at <legal@jikigai.com> and we will approach them; we aim to reply within **3 business days**. Email rather than the pull request thread, unless you would rather it were public -- the thread is world-readable and permanent, and who you work for is yours to disclose or not.

**What happens if that Corporate CLA is signed.** Once your employer executes one and names you under it, we publish an entry linking your GitHub account to that organisation in a public file in this repository (`apps/cla-evidence/roster/ccla-roster.json`). It carries no name, no email and no postal address -- but the account-to-employer association is itself personal data about you, it is created only at or after you sign the Individual CLA, and once written it is copied into every clone and fork and **cannot be erased**. [Section 0 of the Individual CLA](https://soleur.ai/pages/legal/individual-cla.html) is the full notice; it is worth reading before you sign rather than after.

One thing we do have to ask you, because signing says it on your behalf. Section 4(a) of the Individual CLA is a representation about your employer's position: that your employer has given you permission to contribute, **or** has waived its rights in this work, **or** has signed a Corporate CLA naming you as an Authorized Representative. Most contributors are already covered by the first. **If none of the three is true for you, or you are not sure, tell us at <legal@jikigai.com> instead of signing** -- you need not say why on the pull request. We will sort the Corporate CLA out first and come back to you. We would rather wait than have you make a statement that is not accurate.

While a Corporate CLA **of yours** is in flight, your pull request is reviewed and merged on its merits exactly as any other: that paperwork is what we owe your employer, not a task assigned to you, and the corporate side never gates your merge. None of this applies if you are contributing your own work on your own time; then the individual CLA is the whole ask.

**What one Corporate CLA covers.** No employer ever signs a second one -- but coverage runs through the list of Authorized Representatives held with it, not through the company as a whole. A colleague is covered once your employer adds them to that list (Corporate CLA [Section 5](https://soleur.ai/pages/legal/corporate-cla.html)), which is an email to <legal@jikigai.com> from the signatory, and again our job to chase rather than yours. Each colleague also signs the Individual CLA once, on their own first pull request.

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

Do NOT add a `version` key to `plugin.json` or to `marketplace.json`'s `plugins[]` entry. Neither carries one, and that is deliberate: `claude plugin update` compares version strings, and with no key the CLI records the plugin's commit SHA as its version, so the string changes with every commit and the update is detected. A constant version never changes, so the comparison always comes back equal -- the update short-circuits, reports "already at the latest version", and exits 0 having delivered nothing ([#7471](https://github.com/jikig-ai/soleur/issues/7471)). The same applies to the published distribution manifest in [`jikig-ai/soleur-marketplace`](https://github.com/jikig-ai/soleur-marketplace). Release versions live in git tags; a release publishes nothing to any manifest.

(`marketplace.json`'s **top-level** `version` is a different field -- the manifest-format version -- and stays.)

See the [plugin development guide](plugins/soleur/AGENTS.md) for the full checklist including skill compliance requirements.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.
