---
title: "Mutating before the impl commit makes `git checkout` a shredder — commit, then mutate"
date: 2026-10-02
category: workflow-issues
module: plugins/soleur/skills/work
issue: 9398
tags: [mutation-testing, guard-contract, worktrees, git-restore, sequencing]
---

# Mutating before the impl commit makes `git checkout` a shredder

## Problem

Driving a Guard Contract mutation matrix by hand (edit → run test → restore), I mutated the
implementation files **before committing them**, then reached for `git checkout -- <file>`
as the per-row restore. Two failure modes fired in sequence:

1. The first mutation hit the *untracked* new reference file — `git checkout` had no
   pathspec for it and printed `did not match any file(s) known to git`.
2. Restoring the *tracked* files with `git checkout` then reverted them to HEAD — discarding
   the entire uncommitted implementation (three files' worth), not just the mutation.

Recovery was possible only because the edits were fresh in context; a compacted session
would have lost them.

A second sequencing slip in the same session: ticking `tasks.md` checkboxes while
`test-all.sh --affected` was measuring the tree — the gate's repo-observation detector
counted it, and the run's measurement window covered a mutating tree.

## Solution

- **Commit before you mutate.** The mutation matrix ran green *after* I committed the
  implementation; `git restore` then recovered exactly the intended bytes per row.
- For untracked files, `git checkout` can never restore them — snapshot with `cp` before
  row 1 (per work/SKILL.md:731's pristine-copy rule) or accept that the row needs a manual
  re-write.
- When moving a section inside a document that also contains a *fenced schema example* of
  that section, anchor the splice on a unique marker (e.g. a body-only sentence), not on
  `s.index("## <name>")` — the first occurrence found was the fenced copy, and the splice
  scrambled the plan. `git restore` recovered it because the plan was already committed.
- During a running full/affected gate, the worktree is read-only — defer even
  bookkeeping edits (checkbox ticks) until it exits.

## Key Insight

The rules existed and I knew them — work/SKILL.md:731 ("restore from a PRISTINE COPY,
never `git checkout`; the fix must be COMMITTED first") and :759 ("commit each verified
unit immediately; treat the worktree as immutable while a background job is active"). The
gap was sequencing: the mutation loop ran *between* "tests green" and "commit", so the
prescribed restores were destructive. The invariant that survives ordering mistakes:
**a mutation battery may only touch state that is recoverable by definition** — committed,
or snapshotted before row 1. If neither holds, the battery itself is the hazard.

## Session Errors

1. `git checkout` restore on untracked + uncommitted files discarded three implementation
   files (re-applied manually). **Prevention:** commit before mutating; `cp` pristine
   copies of untracked files.
2. Section-move splice keyed on first `## Scope Check` hit the fenced schema copy and
   scrambled the plan. **Prevention:** anchor on a unique marker; `git diff` immediately.
3. `tasks.md` edited while `test-all` measured the tree. **Prevention:** no worktree
   writes during a running gate — queue doc edits.
4. `deepen-plan` blew its 80000 B ceiling mid-review-round (sections grow during fix
   rounds). **Prevention:** re-run `lint-skill-body-budget.py` after every edit round on
   a near-ceiling skill; keep compensating trims in reserve.
5. (Forwarded, plan subagent) exec batch ran in main checkout not worktree — one-off;
   `gh pr view --json merged` invalid field — one-off; subagent had no spawn tool and
   disclosed inline fan-outs — correct behavior.
6. MD038 lint on `.ts` comment code spans — one-off, fixed inline.

## Tags

category: workflow-issues
module: plugins/soleur/skills/work
