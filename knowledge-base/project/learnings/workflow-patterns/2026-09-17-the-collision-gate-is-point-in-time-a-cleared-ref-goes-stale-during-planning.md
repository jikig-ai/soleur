---
title: "The collision gate is point-in-time: a cleared ref goes stale during planning"
date: 2026-09-17
category: workflow-patterns
tags: [one-shot, collision-gate, duplicate-work, parallel-sessions, measurement, sibling-worktree]
issues: [7535, 8242, 8249, 7510, 7507]
---

# The collision gate is point-in-time: a cleared ref goes stale during planning

## Problem

`/soleur:go 7535` routed to `one-shot`. Step 0a.5 ran **all four** collision probes against #7535
at 13:10 and cleared it correctly:

| probe | result |
|---|---|
| `closedByPullRequestsReferences` | `{"closes":[]}` |
| `linked:issue #7535 --state all` | #7507 `[MERGED]` — a disclosed predecessor |
| `#7535 in:body --state merged -L 100` | #7540, #7507 — both disclosed predecessors |
| `git log origin/main --grep="#7535"` | `dfcf7bd26`, `910f237f0` — same two |

Every hit was discriminated correctly: both were the operator-disclosed Phase 1 / rung-2
predecessors, scope-intersecting on the same file by construction, neither closing the issue.
Nothing was missed. **The gate was right.**

A sibling session then opened **PR #8249** on byte-identical scope at **13:53** — 43 minutes into
the planning subagent's 50-minute run, in worktree `feat-7535-t17-rc-capture`, non-draft, touching the same two files the plan named.

The existing post-planning re-probe instruction did not cover it. Its wording was:

> re-run items 1-3 above against **any ref not already checked at Step 0a.5**

#7535 *had* been checked. So no re-probe was owed, and the collision surfaced only incidentally —
the planning subagent's Session Summary narrated finding "a concurrent implementation" uncommitted
in the worktree.

## What made it hard to see

The sibling's code appeared **uncommitted in my own worktree**, which reads as a scope breach by
one's own planning subagent, not as evidence of a sibling. The #3937 learning primes you for
exactly that misreading ("plan-deepen subagent committed source-code edits AND its Session Summary
claimed on-disk text it had not actually written"), and the timeline fit it: worktree created
13:11, the two source files modified 13:35:45 and 13:35:53 — eight seconds apart, characteristic
of one agent making two sequential edits.

Neither command is new here (`git worktree list --porcelain` appears in 18+ repo docs,
`git log --all` in several learnings). What has no analogue is the COMPOSITE, used as an
**attribution discriminator** between your own subagent and a sibling session — and its polarity.
It is cheap and worth reaching for **before** accusing your own subagent:

```bash
for w in $(git worktree list --porcelain | awk '/^worktree /{print $2}'); do
  grep -rl "<a token the change introduces>" "$w/<dir>/" 2>/dev/null && echo "FOUND in: $w"
done
git log --all --oneline -S "<that token>"
```

It named `feat-7535-t17-rc-capture` and commit `4c6254e1a` immediately. A sibling worktree holding
the same novel token is positive evidence of a real parallel session; absence of one is what would
have implicated the subagent.

## Resolution

Generalized the re-probe in `plugins/soleur/skills/one-shot/SKILL.md` from "any ref not already
checked" to **every ref, including the ones Step 0a.5 already cleared**, with the reason stated:
the gate is point-in-time, not a lock. Cost is unchanged — ≤2 `gh` calls per ref.

## The transferable rule

**A clearance has a timestamp, and the window it guards is longer than the check.** Any gate that
runs once at the start of a 30–90 minute pipeline is making a statement about the world at t₀, not
an invariant over the run. When the pipeline's cost is concentrated *after* the gate, re-assert the
gate's own conclusion before spending that cost — re-probing a ref you already cleared is not
redundant work, it is the only thing that covers the window.

This is the same shape as the token-discipline rule about inherited verification claims ("a
verification claim you inherited is a statement about a tree that may no longer exist"), applied to
a gate's own earlier output rather than to a handoff's.

## Related

- `knowledge-base/project/learnings/2026-08-06-the-collision-gate-cleared-the-issues-i-passed-it-not-the-one-i-worked-on.md` — the
  first instance, where planning *re-targeted* the issue. That fix added the re-probe; this one
  removes its "not already checked" qualifier.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-18-one-shot-collision-gate-misses-prose-ref-merged-prs.md`
  — the `Ref #N` blind spot. Orthogonal: that one is about which PRs a probe can see, this one is
  about *when* it looked.
- #8139 — a sibling PR found only via `test-all.sh`'s `SIBLING_RUN_DETECTED` banner, after a full
  review had been spent.

## Second-order note

Two inherited numbers in the invocation were also wrong and were caught before planning began — see
the plan's `### Premise Validation` for both, and the PR body for the dispositions. The rule they
illustrate (re-measure a handoff's load-bearing figures) is already repo doctrine; it is noted here
only because it is the same root cause as the timestamp above: a claim carried forward instead of
re-derived.
