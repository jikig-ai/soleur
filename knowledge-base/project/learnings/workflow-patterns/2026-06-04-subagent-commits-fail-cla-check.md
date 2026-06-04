---
title: Subagent commits author as the unsigned harness identity and fail cla-check at merge
date: 2026-06-04
category: workflow-patterns
tags: [workflow-patterns, cla-check, subagent-commits, pre-merge-gate, git-author, ci-required-status]
---

# Learning: Subagent commits fail the required `cla-check` CI status

The unsigned identity this learning refers to throughout is defined once here, then
referenced as `$UNSIGNED` to keep it off the fixture-content linter's radar
(`knowledge-base/project/learnings/**/*.md` is in that linter's scope):

```bash
UNSIGNED="noreply@anthropic.com"  # gitleaks:allow # issue:#4951 the literal CLA-unsigned identity is the subject of this learning
```

## Problem

PR #4948 (the D4-bolder nav redesign) failed the required `cla-check` GitHub
status at merge time. The failure was NOT in the feature code — it was a single
commit whose author was `Claude <$UNSIGNED>`.

The commit came from a **subagent**, not the main session. During the work
phase, the `ux-design-lead` agent committed a Pencil recovery-anchor stub (the
fresh `.pen` file created to work around the destructive `open_document` bug).
Subagents that run `git commit` without an explicit author inherit the default
`Claude <$UNSIGNED>` identity. That identity has not signed the CLA, so the
repo's required `cla-check` status fails.

The cost is asymmetric and silent: the branch passes local review, typecheck,
unit tests, and preflight. The author problem only surfaces *after* `gh pr ready`
queues auto-merge and a full CI cycle burns — then `cla-check` reports FAILURE
and the merge is blocked. One wasted CI cycle per occurrence.

## Solution

Two parts: a recovery recipe and a mechanical gate so it cannot recur silently.

### Recovery (when cla-check already failed)

Rewrite both the author AND committer email of every offending commit, then
force-push (`$UNSIGNED` as defined above):

```bash
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
if [ "$GIT_AUTHOR_EMAIL" = "'"$UNSIGNED"'" ]; then
  export GIT_AUTHOR_NAME="<Your Name>"; export GIT_AUTHOR_EMAIL="<you@domain>"
fi
if [ "$GIT_COMMITTER_EMAIL" = "'"$UNSIGNED"'" ]; then
  export GIT_COMMITTER_NAME="<Your Name>"; export GIT_COMMITTER_EMAIL="<you@domain>"
fi
' origin/main..HEAD
git push --force-with-lease
```

Rewrite the committer too, not just the author — `cla-check` implementations
vary on which trailer they inspect, and a subagent commit is typically unsigned
on both.

### Prevention (so it never reaches CI)

`.claude/hooks/cla-signed-author-gate.sh` — a PreToolUse(Bash) hook that denies
`gh pr ready` / `gh pr merge` when any commit in `origin/main..HEAD` is authored
OR committed by `$UNSIGNED`. The deny message embeds the `filter-branch` recovery
above. Fail-open on main/master/detached/non-worktree/no-origin-main so it never
blocks legitimately. Rule: `wg-cla-signed-author-before-merge` (AGENTS.rest.md).
Tests: `.claude/hooks/cla-signed-author-gate.test.sh` (5 fixture cases). The
hook file itself holds the literal email (it is out of the linter's scope —
only `learnings/**/*.md` is in scope).

## Key Insight

A required CI status that gates on commit *metadata* (author/committer identity)
rather than diff content is invisible to every local quality gate — review,
typecheck, tests, preflight all read the tree, not the authorship. The only way
to catch it pre-CI is a gate that inspects `git log` author/committer fields at
the `gh pr ready`/`merge` boundary. This generalizes: any merge-blocking signal
derived from commit metadata (signed-off-by, DCO, GPG signature, author allowlist)
needs its own author-scanning pre-merge hook, because content-only gates are
structurally blind to it.

The subagent angle is the root cause: a subagent's `git commit` runs in a context
where the operator's git identity may not be configured, so it silently falls back
to the harness default. Any workflow that lets a subagent commit must either pass
an explicit `--author` or be backstopped by an author-checking gate.

## Session Errors

- **cla-check FAILURE on PR #4948** — Recovery: `git filter-branch --env-filter`
  rewrite of author+committer + force-push. Prevention:
  `cla-signed-author-gate.sh` PreToolUse hook (`wg-cla-signed-author-before-merge`)
  blocks `gh pr ready`/`merge` before the CI cycle is spent.
- **Test harness env-var scoping bug (one-off)** — The first test draft wrote
  `INCIDENTS_REPO_ROOT="$1" printf … | "$HOOK"`, which scopes the env var to
  `printf` only, not the piped hook. The incident JSONL landed at the real repo
  root instead of the fixture, so the rule-id assertion read empty. Recovery:
  move the assignment onto the hook side of the pipe
  (`printf … | INCIDENTS_REPO_ROOT="$1" "$HOOK"`). Prevention: one-off — generic
  shell knowledge, no recurrence vector worth a rule.
- **fixture-content linter rejected the learning (one-off, self-corrected)** —
  The `lint fixture content` CI gate scans `learnings/**/*.md` for real-looking
  emails; the literal unsigned identity tripped it 6×. Recovery: define the
  literal once on a waived line (a `gitleaks:allow` comment carrying an
  `issue:#NNN` trailer with a ≥3-char reason) and reference `$UNSIGNED`
  elsewhere. Prevention: one-off — known linter behavior, documented waiver
  mechanism.
