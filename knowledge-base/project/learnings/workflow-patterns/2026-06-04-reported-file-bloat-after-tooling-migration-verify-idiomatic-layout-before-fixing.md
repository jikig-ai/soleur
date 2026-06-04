---
title: "Reported 'too many files' after a tooling migration: verify the tool's idiomatic layout before 'fixing'"
date: 2026-06-04
category: workflow-patterns
tags: [likec4, c4-model, architecture-diagrams, migration, bare-repo, soleur-go, documentation]
branch: feat-one-shot-c4-diagrams-readme
pr: 4936
---

# Reported file-bloat after a tooling migration is often idiomatic structure, not a regression

## Problem

The operator reported that `knowledge-base/engineering/architecture/diagrams/`
had "too many files" after the Mermaid → LikeC4 migration (PR #4883) — recalling
that the Mermaid era had **3 files, one per C4 layer**, and asking to "fix it."
The framing invited a destructive fix (delete/consolidate files).

## Key Insight

**A user reporting "more files than before" after a tooling migration is a
hypothesis to verify against the new tool's idiomatic layout — not a defect to
'fix' by deletion.** Here the 8-file structure was correct and load-bearing:

- The 3 C4-layer pages the operator remembered (`system-context.md`,
  `container.md`, `component-plugin.md`) **still exist**, one per layer — only
  the embedded block changed from ` ```mermaid ` to ` ```likec4-view `.
- The "extra" files are the **canonical LikeC4 project shape** (`spec.c4` /
  `model.c4` / `views.c4`), prescribed verbatim in the skill's own
  `likec4-reference.md`. Mermaid inlined the diagram source into each `.md`;
  LikeC4 cannot, so the model lives in `.c4` files (define-once, render-many).
- `model.likec4.json` is a **required runtime artifact**, not cruft: the web
  viewer (`c4-diagram.tsx`) renders a pre-compiled, pre-layouted dump because
  the client libs are deliberately pinned WITHOUT the likec4 compiler. Deleting
  it breaks the visualizer.

The correct fix was **documentation** (a README explaining the taxonomy), not
deletion. Surfacing this to the operator — "you're half right, here's why" —
before acting honored the "correct me if I'm wrong" invitation and the
"surface contradictions before deleting" discipline.

## How to apply

- When a request to "fix file bloat / redundancy" follows a tooling migration,
  first read the tool's canonical project layout (its reference doc / skill) and
  confirm whether each file is source, compiled artifact, or rendered view.
  Compiled artifacts and DSL sources are *expected* alongside the human-readable
  pages; that is not redundancy.
- Trace the runtime consumer before declaring an artifact deletable: grep the
  viewer/consumer for the file (`c4-diagram.tsx` → `LikeC4Model.create(dump)`)
  to prove whether it is load-bearing.
- Prefer correcting the operator's mental model + a clarifying README over a
  destructive "tidy-up" that reverts a merged, intentional migration.

## Bare-repo verification gotcha

`git ls-files <dir>` run from the **bare repo root** returned only a stale
subset (4 of 8 files) — the bare repo's index lags. The authoritative
branch-state view is `git ls-tree HEAD <dir>` (and `git ls-tree main <dir>`).
Always cross-check on-disk `ls` against `git ls-tree HEAD` when working from a
bare-repo CWD; never trust `git ls-files` there.

## Session Errors

1. **`.mcp.json` overwrite denied by the auto-mode classifier** (Self-Modification)
   during the `soleur:go` session-start chain (`git show main:.mcp.json > .mcp.json`).
   — Recovery: skipped per the go skill's "skip silently on first error";
   non-blocking.
   — **Prevention:** known/expected; the go skill already documents the silent-skip.
   No new enforcement warranted.
2. **Session-start `&&` chain aborted by the denial**, so `git worktree list` did
   not run in that first call — a *permission denial* aborts the whole Bash tool
   call regardless of the trailing `|| true` (which only catches non-zero exit
   codes, not tool-layer denials).
   — Recovery: re-ran `git worktree list` as a standalone command.
   — **Prevention:** when a session-start chain mixes a denial-prone op
   (`.mcp.json` self-write) with must-run probes (`cleanup-merged`,
   `git worktree list`), run the must-run probes in a separate Bash call so a
   denial cannot suppress them. Candidate refinement to the `soleur:go`
   session-start preamble.
