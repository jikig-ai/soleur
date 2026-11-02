# context-reviewed-gate false-positives when the command `cd`s to the bare root before `git -C <worktree>` commit

**Date:** 2026-10-23
**Context:** shipping a docs-asset commit in worktree `feat-og-agentic-verification`.

## What happened

`.claude/hooks/context-reviewed-gate.sh` denied a `git -C .worktrees/feat-og-agentic-verification commit` whose entire payload was one binary PNG (no `*.md` in the diff at all). The deny message claims the commit "removes or changes a `last_reviewed:` line in a Markdown file".

Root cause chain:

1. My command led with `cd /data/git-repositories/jikig-ai/soleur` (the **bare root**) before chaining `git -C "$WT" add … && git -C "$WT" commit`.
2. `resolve_command_cwd` picked the `cd` target — the bare root — as `WORK_DIR`, not the `git -C` path on the commit segment.
3. The bare root is a `shared_bare` repo **with a live `.git/index`** (~2.9 MB — the synced overlay of HEAD is maintained through it). That index carries staged deltas vs HEAD that are not mine; at the time it contained 26 removed `last_reviewed:` lines across `*.md`.
4. For a plain commit (no `-a`, no pathspec) the gate computes `git diff --cached -U0 -- '*.md'` in `WORK_DIR` — so it scored the bare root's staged index, not the worktree's index, and fired.

## Fix pattern (what worked)

Run the whole sequence **inside** the worktree so `resolve_command_cwd` lands on the repo that actually owns the commit:

```bash
cd /path/to/.worktrees/<name> && git add <file> && git commit -m "…"
```

not `cd <bare-root> && git -C <wt> … && git -C <wt> commit …`.

## Why it matters

The Devin adapter note recommends `git -C <worktree-abs-path>` for worktree commits because the hook envelope omits `.cwd`. That advice is correct for *working-directory* resolution but is incomplete for hooks that re-derive `WORK_DIR` from the command text: a leading `cd` to a different repo (or to the bare root, whose index can carry staged `*.md` deltas) outranks `git -C` in the resolver, and the gate then audits the wrong index. Bare-root-cwd sessions hit this whenever their `cd` prefix names the bare root.

## Related

- The bare root having a populated index at all is the deeper surprise — `git diff --cached` silently "works" there and returns other people's/overlay deltas. Any hook that diffs `--cached` in a resolved cwd inherits this.
- Deny was logged to the incident ledger by the hook (`emit_incident context-reviewed-gate deny`), as designed.
