# Learning: Automating Pencil MCP Registration via Skill

## Problem

The Pencil MCP server (Go binary inside `highagency.pencildev` IDE extension) couldn't be bundled in plugin.json. The previous solution (see `2026-02-14-pencil-mcp-local-binary-constraint.md`) was "degrade gracefully and link to docs." But users still had to manually install, locate the binary, and register it — with registration going stale on every extension update.

## Solution

Created a `pencil-setup` skill with inline bash that handles the full lifecycle:

1. **`claude mcp add` is NOT idempotent** — exits 1 on duplicate name. Always `remove` then `add`.
2. **Use `-s user` scope** — default is `local` (project-level). Global scope ensures Pencil works across all projects.
3. **Glob for binary, not hardcoded paths** — `ls -d ${EXTDIR}/highagency.pencildev-*/out/mcp-server-* | sort -V | tail -1` handles version drift, multiple coexisting versions, and platform detection in one command.
4. **`--app <ide>` is always required** — the binary won't start without it. HTTP mode (`-http -http-port`) also requires `--app`.
5. **`command -v` over `which`** — POSIX-portable alternative found during review.

## Key Insight

When a CLI tool (`claude mcp add`) isn't idempotent, the remove-then-add pattern makes fresh installs, version updates, and re-registration all follow the same code path — no separate drift detection needed. This is the simplest approach when the remove operation is itself idempotent (which it is: `claude mcp remove` succeeds silently if nothing to remove).

## Session Errors

1. **Edit before Read** — Edit tool rejected modification of `bug_report.yml` without prior Read. Always read first.
2. **marketplace.json version drift** — Was at 3.5.0 (not 3.5.1) due to parallel branch. Always fetch main before bumping.
3. **Plan overengineered** — First pass had a 7-function shell script, version drift detection, snap paths, and HTTP docs. Reviewers correctly cut it to inline SKILL.md only. Skills that are ~5 sequential commands don't need script abstractions.
4. **Review false positive** — Agent flagged non-existent `docs/_data/skills.js`. Validate review findings before acting.
5. **README table count missed** — Bumped plugin.json description (52→53) but missed README markdown table. The versioning checklist should include "README component count tables" explicitly.

## Tags
category: integration-issues
module: pencil-setup, mcp-registration
symptoms: claude mcp add fails on duplicate, stale MCP binary path after extension update
