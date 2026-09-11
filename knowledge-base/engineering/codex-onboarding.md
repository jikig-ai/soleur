---
title: Codex onboarding for Soleur
last_updated: 2026-09-11
tags: [codex, harness, onboarding]
domain: engineering
---

# Soleur on Codex

Soleur packages the same canonical skills, agents, and MCP connections for
Claude Code, Grok Build, and Codex. Native discovery was verified with
`codex-cli 0.154.0`: 95 workflow skills plus three command wrappers.

## Install

```bash
codex plugin marketplace add jikig-ai/soleur --sparse .agents/plugins --sparse plugins/soleur
codex plugin add soleur@soleur
```

The Codex marketplace is in this repository. The separate
`jikig-ai/soleur-marketplace` repository remains the Claude distribution source.

Start a new Codex conversation. Open `/hooks` and review the plugin hooks.
Connect bundled MCP servers when prompted. Use `$soleur:go <intent>`,
`$soleur:sync`, or `$soleur:help` in the composer.

## Work in this repository

From the checkout or feature worktree:

```bash
bash scripts/setup-codex.sh
codex
```

Trust the project when Codex prompts, then inspect both project and plugin
sources in `/hooks`. The committed `.codex/config.toml` loads the existing
session rule corpus and Bash guardrails. Plugin hooks separately load Codex
compatibility context, the browser credential guard, and existing Stop hooks.
Untrusted hooks are listed but do not execute.

Codex reads linked-worktree hooks from the shared repository root.
The setup script installs the checked-in configuration there when missing,
preserves an identical existing configuration, and refuses to overwrite
different configuration or follow a configuration symlink. It registers the
current checkout as the local marketplace, so plugin edits come from that
checkout while hook commands resolve the active worktree at execution time.

The repository's remaining Claude hooks are not automatically imported.
In particular, Claude Write/Edit hooks expect per-file payloads whereas Codex
uses `apply_patch`; no file-edit guard parity is claimed by this setup.
Project permissions remain governed by Codex's own sandbox and approval policy.

## Update and validate

For a Git-backed marketplace:

```bash
codex plugin marketplace upgrade soleur
codex plugin add soleur@soleur
```

For a local checkout, repeat only the second command after editing source.
Restart the conversation after refreshing the installed cache. Manifests
intentionally omit `version`; local installs report `local`.

```bash
codex plugin list --marketplace soleur --json
node scripts/codex-plugin-smoke.mjs
bun test plugins/soleur/test/codex-harness.test.ts plugins/soleur/test/codex-plugin.test.ts
```

The smoke test starts an app server, lists installed skills and hooks, and
exits without model inference. A process-local project-trust override lets
it inspect the repository layer without changing persistent project trust.
It executes no hooks and does not bypass hook trust. It needs ordinary access
to Codex's state directory.

## Compatibility contract

- The Codex manifest explicitly lists both skill roots. In the tested CLI, a
  custom `skills` path replaces default discovery; naming only command wrappers
  hides the 95 canonical skills. Native discovery tests cover both roots.
- Command wrappers link back to `commands/`; workflow definitions are not
  copied or rewritten. Component counts remain 95 skills and three commands.
- Agents run through Codex delegation with canonical definition paths in
  their prompts. All 68 agent definitions resolve; custom Codex agent types
  and Anthropic model aliases are not required.
- Skill chaining loads each complete skill. Claude Workflow scripts require
  equivalent orchestration using the tools available to Codex.
- Direct shell execution of installed scripts must bind
  `CLAUDE_PLUGIN_ROOT` to the verified installed root. Hook environment
  variables do not automatically propagate to ordinary shell tools.
- Discovery and protocol tests establish packaging compatibility, not
  end-to-end execution of every autonomous workflow. Unsupported required
  gates must be reported rather than silently skipped.

## Sources

- [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
