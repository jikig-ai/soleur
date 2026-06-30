# Learning: reading merged files — brace `git show "${SHA}:path"` and don't trust local `main`

## Problem

During `/soleur:postmerge` file-freshness verification (and again when grounding a
follow-up `/one-shot` against a just-merged PR), two distinct papercuts cost
cycles while trying to read files out of a merge commit in this **bare-root +
worktrees** repo:

1. `git show main:apps/web-platform/.../file.ts` returned the **pre-merge**
   content. The local `main` ref had not advanced — it sat at the previous tip
   (`fd034007`) while the actual merged commit was `0102ad1a` on `origin/main`.
   In a bare-root repo nobody runs `git pull` on `main`, so the local ref is
   routinely stale right after a squash-merge.

2. `SHA=0102ad…; git show $SHA:apps/web-platform/...` produced
   `fatal: ambiguous argument '…0102ad…pps/web-platform/...'` — the `:a` in
   `$SHA:apps` was eaten by **zsh's `:a` history/parameter modifier**
   (absolute-path). The default session shell here is zsh, so any
   `$VAR:<word-starting-with-a/h/e/r/t/...>` silently applies a modifier instead
   of being passed to git as a `rev:path` argument.

## Solution

- **Read merged files from the explicit merge SHA or `origin/main`, never bare
  `main`** — and `git fetch origin main` first if you must use a ref. The merge
  commit SHA from `gh pr view <n> --json mergeCommit` is the authoritative,
  drift-proof handle.
- **Always brace the rev when it is a shell variable:**
  `git show "${SHA}:path/to/file"` — the braces stop zsh from parsing `:a`/`:h`/
  `:e`/`:r`/`:t` as modifiers. (`git show "$SHA":path` also works; braces are the
  habit that always reads right.)

## Key Insight

`rev:path` is a git syntax, but `$VAR:word` is *also* a zsh modifier syntax, and
they collide exactly on the colon. Brace every `git show`/`git cat-file` ref that
comes from a variable. And in this bare-root layout, the local `main` ref is a
stale mirror — treat `origin/main` (post-fetch) or the merge SHA as truth for any
"did the merged file land?" check.

## Session Errors

- **Stale local `main` masked merged content** — Recovery: `git fetch origin main`,
  re-read from the merge SHA. Prevention: read merged files from the
  `gh pr view --json mergeCommit` SHA, not a local branch ref (reinforces
  `hr-when-in-a-worktree-never-read-from-bare` + memory `project-git-bare-root-worktrees`).
- **zsh `:a` modifier mangled `git show $SHA:apps/...`** — Recovery: brace as
  `git show "${SHA}:apps/..."`. Prevention: always brace a variable rev in
  `git show`/`cat-file`.
- **`${PIPESTATUS[0]}` printed empty after a piped `tsc`** (zsh) — one-off.
  Recovery: run the command unpiped and capture `rc=$?`.
- **One-shot collision gate flagged `#5659` (cited predecessor) as a closed-issue
  ABORT** — already a documented false-positive class
  (`2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs`); continued
  per guidance, no change needed.

## Tags
category: workflow-patterns
module: git / postmerge / one-shot
