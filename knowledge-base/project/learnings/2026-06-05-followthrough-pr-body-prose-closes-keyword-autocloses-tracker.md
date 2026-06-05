---
title: 'Prose `closes #N` in a follow-through PR body auto-closes the tracker on merge, defeating the deferred verification'
date: 2026-06-05
category: workflow-traps
tags: [github-auto-close, follow-through, sweeper, closing-keyword, deferred-verification]
related_issues: [#4977, #4981]
related_rules: [wg-use-closes-n-in-pr-body-not-title-to]
---

# Learning: descriptive `closes #N` prose in a follow-through PR body silently closes the tracker

## Context

`/soleur:go #4977` wired the missing post-deploy Sentry probe for follow-through
tracker #4977 into the sweeper substrate (PR #4981): a probe script under
`scripts/followthroughs/` + a `<!-- soleur:followthrough -->` directive in the
issue body, so `scheduled-followthrough-sweeper.yml` (cron `0 18 * * *`) runs the
probe ~24h post-deploy and closes the issue **only on PASS**.

The PR deliberately avoided a standalone `Closes #4977` line — closure is owned
by the sweeper, not the merge. But the PR body contained the descriptive prose:

```
Exit 0 (zero events) → sweeper closes #4977.
```

GitHub's keyword parser does not read English. On squash-merge it matched
`closes #4977` in the commit body (the squash inlines the PR description) and
auto-closed #4977 immediately — **before the probe ever ran**. A closed issue is
skipped by the sweeper, so the deferred verification would never have executed.

## Why the existing guardrails missed it

- The sibling learning `2026-05-07-pr-title-closes-keyword-ignores-qualifiers...`
  and rule `wg-use-closes-n-in-pr-body-not-title-to` cover closing keywords in the
  PR **title** and qualifier-stripping (`Closes #N (after fire)`). They do NOT
  cover *descriptive prose in the body* — and the body is precisely the
  *recommended* channel for an intentional `Closes`, so prose there is parsed too.
- `pr-auto-close-scanner.yml` is **warn-only** (its header notes `Closes #N` is
  sometimes intentional). It does not block.

## Rule of thumb

For ANY PR that wires a follow-through (or otherwise must leave its referenced
tracker OPEN for a sweeper / scheduled job to close later): the PR title AND body
must contain **zero** `<closing-keyword> #N` adjacencies — `close[sd]`, `fix(es|ed)`,
`resolve[sd]` immediately followed by `#<tracker>` — *including descriptive prose*.
Rephrase to break the adjacency: `the sweeper will close that issue` /
`sweeper-owned closure of issue 4977` / `→ sweeper closes the tracker`. Reference
the tracker with `Refs #N` only.

## Detection / recovery

- Timeline tell: a `referenced` event carrying the merge `commit_id` immediately
  followed by a `closed` event at the same timestamp = native commit-keyword
  auto-close (no `commit_id` on the close row itself; no closing comment).
- Recovery: `gh issue reopen <N>` with a forensic comment. The merged commit
  fires auto-close exactly once, so reopening is stable — it will not re-close.
  Verify the follow-through directive is still in the body afterward.
