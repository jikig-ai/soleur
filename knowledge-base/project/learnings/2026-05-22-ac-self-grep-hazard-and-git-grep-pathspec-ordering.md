---
date: 2026-05-22
type: workflow-pattern
category: review
related_pr: 4344
related_issue: 4322
tags: [acceptance-criteria, git-grep, self-grep, audit-pattern, pathspec]
---

# AC self-grep hazard + git-grep pathspec ordering gotcha

Two related defects surfaced while executing the identity-rbac-reviewer fold (PR #4344, issue #4322). Both stem from the same root pattern: when an acceptance criterion verifies *absence* of a token, the verification grep can self-fail on artifacts the same PR creates. Capturing both lessons because the second one (pathspec ordering) is independent enough to bite future ACs even without the first.

## Pattern 1 — AC self-grep hazard

### The setup

Plan §AC encoded a sweep verifying no live references to the deleted agent remain:

```bash
git grep -nE 'identity-rbac-reviewer|identity-rbac' -- 'plugins/' 'knowledge-base/' 'docs/' '.github/' 'apps/' \
  ':!**/archive/**' \
  ':!knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md' \
  ':!knowledge-base/project/plans/2026-05-22-chore-audit-identity-rbac-reviewer-subset-plan.md'
```

The two `:!` excludes cover the audit learning + the chore plan — the two artifacts that document the deletion's reasoning and verdict.

### How it self-failed

My first drafts contained the deleted identifier in places the AC didn't exclude:

- `security-sentinel.md` historical note: *"Folded in from the standalone `identity-rbac-reviewer` agent on 2026-05-22…"*
- Same file, cross-reference: *"See `knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md` for the audit verdict and reasoning."* — the path itself contains the identifier.

Both required two rewrites:
1. Drop the literal identifier from the historical note. Rephrase as "Folded in on 2026-05-22 after the post-#4288 falsifiability audit (issue #4322)…"
2. Reference the audit doc by date + issue number instead of filename: "The audit verdict and reasoning live in the 2026-05-22 learning under `knowledge-base/project/learnings/` (search for issue #4322)."

The plan's Sharp Edges explicitly flagged this — *"the Phase 6 verification grep MUST exclude both this plan AND the audit-learning that Phase 1 creates"* — and I still tripped it twice because I focused on the **excludes** rather than on **all new artifacts the PR creates**.

### Prevention

When an AC verifies "no references to deleted X exist" via a self-grep sweep:

1. **Enumerate every artifact this PR creates or modifies** (not just files-to-create). `git diff --name-only HEAD~1..HEAD` is the canonical list.
2. For each, grep for X. Any match is either: (a) the audit/plan that legitimately needs the historical reference and must be added to `:!` excludes, OR (b) a stale draft that should be rephrased to avoid the identifier.
3. **Prefer rephrasing over expanding the exclude list.** A clean grep predicate is more durable than a growing exclude list, because future ACs/audits may not know to extend the excludes.
4. The provenance note in the *consuming* file (the agent that absorbed the deleted lens) is the highest-risk surface — it's the most natural place to say "we folded in X" and the most failure-prone.

This is a generalizable pattern for any deletion-with-fold (agent fold, helper consolidation, skill merge, table column removal, env-var rename). The grep predicate is correctly strict; the discipline is on the *producer* of the new artifacts.

## Pattern 2 — `git grep` pathspec ordering

### What I did first

```bash
git grep -nE 'identity-rbac-reviewer|identity-rbac' plugins/ knowledge-base/ docs/ .github/ apps/ \
  -- ':!**/archive/**' ':!knowledge-base/.../subset-audit.md' ':!knowledge-base/.../plan.md'
```

Result: `fatal: unable to resolve revision: plugins/` (exit 128).

### Why it failed

`git grep` parses positional args as `<pattern> [<rev>...] [-- <pathspec>...]`. The bare directory names (`plugins/`, `knowledge-base/`, etc.) before `--` are interpreted as **revisions**, not pathspecs. `plugins/` isn't a valid revision, so git aborts before scanning anything.

### Correct form

Either move every pathspec after `--`:

```bash
git grep -nE '<pattern>' -- 'plugins/' 'knowledge-base/' 'docs/' '.github/' 'apps/' \
  ':!**/archive/**' ':!<audit-file>' ':!<plan-file>'
```

…or skip `--` entirely (no exclude pathspecs work without it). The second form is fine when no excludes are needed; the moment you need `:!` excludes, every positional must be after `--`.

### Prevention

When writing a `git grep` AC that uses both:
- a positive scope (directories to search), and
- negative pathspecs (`:!exclude`),

put **every** positional after `--`. The mental model is: `git grep <pattern> -- <list-of-pathspecs>`, where the list contains both positive (`'plugins/'`) and negative (`':!archive/'`) entries. Don't try to split the positives and negatives across the `--` boundary.

This also applies to `git log -- <pathspec>`, `git diff -- <pathspec>`, and any other plumbing/porcelain command that takes pathspecs — the boundary is consistent.

## Session Errors

- **`git grep` pathspec ordering trip.** First AC3 verification failed with `fatal: unable to resolve revision: plugins/`. Recovery: rewrite with everything after `--`. **Prevention:** Pattern 2 above — every positional after `--` when `:!` excludes are present.
- **Self-grep self-fail on `security-sentinel.md` historical note.** Two rewrites needed (drop literal identifier, then drop cross-reference path). **Prevention:** Pattern 1 above — enumerate ALL new artifacts and grep them BEFORE running the AC sweep.
- **README undercount exacerbated.** Pre-existing drift in `Engineering (31)` heading (actual count 30 on main when this PR was branched); my decrement made it `(31)` vs actual 30. Recovery: bump heading to `(30)` and backfill the two missing review-agent rows (`observability-coverage-reviewer`, `user-impact-reviewer`) caught by code-quality-analyst at review. **Prevention:** when decrementing a domain count in README, recount the on-disk files (`find plugins/soleur/agents/<domain> -name '*.md' | wc -l`) BEFORE the edit; reconcile any pre-existing drift inline rather than leaving it for review.

## References

- The fold itself: PR #4344, issue #4322.
- Audit verdict + reasoning: `2026-05-22-identity-rbac-reviewer-subset-audit.md`.
- Plan that pre-committed the AC sweep (and warned about self-grep hazard): `knowledge-base/project/plans/2026-05-22-chore-audit-identity-rbac-reviewer-subset-plan.md` §Sharp Edges and §Enhancement Summary "Key Improvements after deepen-pass" §1.
