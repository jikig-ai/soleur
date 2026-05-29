---
title: "git checkout to undo a test mutation clobbers uncommitted sibling edits; rebase before editing a target file a sibling PR moved"
date: 2026-05-29
category: workflow-patterns
tags: [git, mutation-testing, regression-guard, rebase, one-shot, worktree]
issue: 4575
pr: 4589
---

# Learning: don't `git checkout` a file to revert a test mutation while you hold uncommitted edits to it; rebase before editing a target a sibling PR moved

## Problem

While building a source-text regression guard for `apps/web-platform/infra/seo-rulesets.tf`
(#4575), two distinct mechanical footguns cost rework:

1. **Mutation-revert clobber.** To prove the guard was non-vacuous, I mutated a
   header value in `seo-rulesets.tf` (`noindex, nofollow` → `noindex`), ran the
   test (expected FAIL), then ran `git checkout -- infra/seo-rulesets.tf` to
   revert the mutation. But the file *also* carried my still-uncommitted AC3
   cross-link comment edit. `git checkout -- <file>` reverts the **entire** file
   to its committed (HEAD) state — it cannot distinguish "the mutation I just
   made" from "the legit edit I haven't committed yet." The comment edit
   vanished. This happened **twice** before I committed the real edit first.

2. **Stale base on the exact target file.** This one-shot worktree was created
   from `origin/main`, but sibling PR #4577 (the apex-canonical reconcile)
   merged into `origin/main` and rewrote `seo-rulesets.tf` *after* the worktree
   existed. `/work` Phase 0.5 check 6 flagged divergence, but `seo-rulesets.tf`
   is not in the hard-fail set (AGENTS.*, ship/SKILL.md, legal) — it WARNed.
   Editing the stale copy would have silently reverted #4577 at merge.

## Solution

1. **Commit the real edit BEFORE any mutation-testing cycle**, or mutate a
   throwaway copy. Once the legit edit is committed, `git checkout -- <file>`
   safely reverts only the mutation back to the committed (edit-included) state.
   Best: never mutate the working tree at all — assert non-vacuity by mutating
   an in-memory copy of the file string in the test harness, or pipe a `sed`
   through a process-substitution the test reads, so the on-disk file is never
   dirtied.

2. **When Phase 0.5 reports divergence and the diverged file IS your edit
   target, rebase onto `origin/main` BEFORE the first edit** — even when the
   file is only in the WARN class, not the hard-fail class. The hard-fail set
   exists for *high-collision* files; but ANY diverged file you are about to
   edit is a merge-revert hazard. After rebasing, re-read the file (its content
   changed) and re-anchor edits/assertions to the post-rebase text.

## Key Insight

`git checkout -- <file>` is whole-file, not hunk-aware: it is the wrong tool to
"undo a mutation" whenever the working copy holds any uncommitted change you
want to keep. And `/work` Phase 0.5's hard-fail divergence set is a *minimum*,
not the complete set of files that warrant rebase-before-edit — the operative
test is "did a merged sibling move the file I'm about to edit," not "is this
file in the high-collision list."

## Session Errors

1. **IaC-routing hook blocked the plan Write** (prose contained "operator"). Recovery: added the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out, justified because the only proposed `.tf` change is comment-only and auto-applies on merge. **Prevention:** plan-authoring skills already document the ack opt-out; no workflow change needed (already-enforced).
2. **Stale branch base on the edit target** (#4577 merged into origin/main post-worktree-creation, moving `seo-rulesets.tf`). Recovery: `git rebase origin/main` before editing; re-read the file. **Prevention:** treat Phase 0.5 divergence on the *edit target* as rebase-required regardless of hard-fail-set membership (this learning).
3. **Push rejected (non-fast-forward)** after rebase rewrote the draft-PR commit SHA. Recovery: `git push --force-with-lease` (safe — own draft branch). **Prevention:** expected after rebasing a branch with a pushed draft-PR commit; force-with-lease is the standard resolution.
4. **`git checkout -- <file>` clobbered an uncommitted sibling edit, twice.** Recovery: re-applied the comment edit; committed it before further mutation cycles. **Prevention:** commit real edits before mutation-testing, or mutate an in-memory/throwaway copy (this learning).
5. **Mis-targeted first mutation** (`sed '0,/.../'` hit the api rule, not deploy → false "7 passed"). Recovery: targeted the deploy rule explicitly via python offset search. **Prevention:** when proving a *specific* assertion non-vacuous, mutate the exact construct that assertion targets — verify the mutation landed where intended before trusting the FAIL/PASS signal.
