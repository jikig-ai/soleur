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
- The first Pencil dependency check found the headless CLI but could not
  authenticate it. Loading `PENCIL_CLI_KEY` from Doppler and re-running the
  check unlocked the connected Pencil MCP; the committed wireframe was then
  authored, exported, saved, and layout-verified. A prose substitute would not
  satisfy the design gate.
- Pencil rejected a first `batch_design` block because frame borders use the
  object shape `{align, thickness, fill}`, not `stroke: string` plus
  `strokeWidth`. The adapter rolled back the block; re-read an existing `.pen`
  precedent and reran with the canonical shape.
- `lint-guard-contract.py` accepts plan paths as positional arguments; passing
  the literal `plan` made it look for a nonexistent file. Use the explicit plan
  path (or omit paths to scan the repository) and inspect non-zero output before
  continuing.

## Work-phase preflight addendum

- Reading the installed work skill in one call truncated its output. Use bounded
  section reads; the installed file includes long single-line learned rules.
- Agent definitions recurse: `ux-design-lead.md` lives under `agents/product/design/`.
  Discover with `rg --files` before reading an assumed flat path.
- The installed `cleanup-merged` cleaned one sibling, then treated the linked
  feature worktree as a non-bare root and checked it out to main. Both specialist
  agents detected absent artifacts before writing. `git reflog` confirmed the
  checkout, the feature ref was intact, and `git switch feat-pluggable-web-agent-engines`
  restored the clean feature tree. Its non-bare post-cleanup arm in
  `worktree-manager.sh` also contains a hard reset, so do not rerun it from a
  linked checkout. Verify branch and HEAD after cleanup before any task starts;
  run future cleanup from the actual common repository root.
- Two work-phase subagents hit the session usage limit after one produced a
  partial inventory artifact and the other produced no persistence changes.
  Preserve any files they wrote, inspect them against the worktree HEAD, and
  continue the failed slice sequentially; an errored agent notification is not
  evidence that its earlier writes were absent.
- Pencil export timed out waiting for its prompt after writing a complete PNG.
  Verify the file signature, dimensions, visual output, and `.pen` post-save size
  before retrying an export; a timeout notification alone does not establish a
  failed export.
- A shell probe was accidentally issued as JavaScript (`const x=1`), producing a
  predictable `command not found`; keep JavaScript orchestration inside
  `functions.exec` and pass only valid shell syntax to `exec_command`.
- `apply_patch` resolves paths from the session root, so edits to a linked
  worktree must use the `.worktrees/<name>/...` path when invoked from the root.
- The pre-commit full gate ran for more than 90 minutes and completed with 397/404
  suites passed and two failures while several sibling gates were active; an
  isolated web-platform rerun then queued behind the same shared lock and was
  stopped. The commit was created only after the targeted registry test was green;
  the full-gate failures remain an open validation issue to resolve before merge.
