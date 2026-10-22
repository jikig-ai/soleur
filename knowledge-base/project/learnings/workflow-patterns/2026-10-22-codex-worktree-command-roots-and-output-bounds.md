---
title: Codex worktree commands must match path roots and bound output
date: 2026-10-22
category: workflow-patterns
tags:
  - codex
  - worktrees
  - shell
  - testing
module: plugins/soleur
---

# Learning: Codex worktree commands must match path roots and bound output

## Problem

While continuing PR #9051, a shell command prefixed an app-relative path with
`apps/web-platform/` even though its working directory was already the app.
The edit failed, but the shell continued into a filtered test run that skipped
every test. A separate dependency inspection printed a minified bundle as one
very long line, overwhelming the useful output.

## Resolution

Choose each command's working directory before constructing relative paths. Use
`set -e` or `&&` around edits and their verification, and treat a zero-match
filtered test run as no coverage. For generated bundles, query metadata or a
specific bounded match instead of printing the whole line. Check optional paths
before including them in multi-file commands.

## GitHub issue filing gate

The issue-create hook also requires an explicit milestone and one filing
exit: a machinery label, a `Mandated-By:` line on its own, or `User-Impact:`
plus `Fix-Size:` fields that name the user-facing surface and count lines/files.
Check the available milestone and put the selected exit in the exact body file
passed to `gh issue create`.

## Bounded test commands

The host Python may not include `pytest`; `uvx --with pytest pytest ...` ran
the qualification tests without changing project dependencies. Ruff was also
not installed as a bare command, so use `uvx ruff`. Check tracked files before
including optional config paths in `rg` commands. Keep large test assertions
bounded: compare type, length, hash, or boolean equality rather than embedding
the entire expected text into a failure diff.

The preflight environment-isolation check can run where `dig` is not installed;
follow its prescribed `resolvectl query --type=CNAME <host>` fallback and still
require a canonical Supabase hostname before comparing project refs.

Before delegating, resolve agent-definition paths with `rg --files
plugins/soleur/agents/...` and copy the exact current SHA from `git rev-parse
HEAD` into every prompt. A guessed top-level `agents/` path or a mistyped SHA
causes avoidable failed reads; agents should report the actual SHA they verify.

Vitest spies need an explicit `vi` import in files that do not enable globals;
`tsc --noEmit` catches the missing symbol before tests run.
