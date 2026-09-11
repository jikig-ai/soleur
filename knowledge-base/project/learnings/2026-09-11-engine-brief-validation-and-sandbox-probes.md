---
title: "Validate engine briefs with native interfaces and repository tooling"
date: 2026-09-11
category: workflow-patterns
tags: [codex, grok, architecture, validation]
---

# Engine brief validation

Plugin discovery is not hosted-runtime qualification. Grok's installed CLI help
exposes stdio and WebSocket agent modes; checking the local interface also led to
the existing web-runtime epic instead of inventing a new Grok integration track.
An architecture review identified a separate invariant: engine failure must not
silently transfer conversation context to another provider.

Session tooling corrections:

- Inspect `lefthook.yml` before selecting a Markdown command. Guessing
  `markdownlint-cli2` and `lint-markdown.sh` produced missing-file errors. The
  repository uses `bash scripts/markdown-lint.sh <paths>`.
- That invoker scopes through tracked files and `.markdownlintignore`. The project
  artifact directory is explicitly excluded even after staging; report that skip
  honestly and check document links and whitespace separately.
- Git metadata writes and GitHub access needed sandbox escalation. Treat cleanup
  lock failures and network errors as failed actions, not successful hygiene.
- Login-shell probes printed stream-fd warnings while reads succeeded. Repeating
  with `login: false` removed those warnings; no shared shell configuration changed.
- Lefthook reported hook-sync skipped because a shared `core.hooksPath` was set.
  The executable pre-commit hook was present and invoked Lefthook; the sync notice
  was not evidence that checks had been disabled.
- The commit guard resolved the hook's main-branch CWD despite the shell tool's
  feature-worktree `workdir`. Its documented resolver understands an explicit
  `cd <worktree> && git commit`; use that supported form so the guard checks the
  intended branch. The `cd` must be the first shell operation in a compound
  command; staging before it still trips the main-branch guard. Do not disable
  the guard.
- Two planned read-only research agents hit the current agent usage limit before
  returning findings. Recovery: continue with bounded local `rg`/`cat` research,
  record the fan-out as partial, and never interpret an agent-limit error as an
  empty research result.
- The required Pencil dependency check found the headless CLI but could not
  authenticate it, so no `.pen` wireframe can be produced in this session. Keep
  the UI work hard-blocked until Pencil Desktop, an IDE extension, or an
  authenticated headless CLI is available; do not claim that a prose wireframe
  satisfies the design gate.
