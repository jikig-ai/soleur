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

Changes to files under `plugins/soleur/` must update three files together:

- **`plugin.json`** -- bump the version (MAJOR for breaking, MINOR for new agent/command/skill, PATCH for fixes)
- **`CHANGELOG.md`** -- document what changed
- **`README.md`** -- verify component counts and tables are accurate

See the [plugin development guide](plugins/soleur/AGENTS.md) for the full checklist including skill compliance requirements.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.
