---
title: The rework that removed three instances of a defect class shipped four more
date: 2026-08-13
category: workflow-patterns
module: ship, work, review
tags: [review, mutation-axes, fail-open, pagination, gates, rework]
pr: 7515
issues: [7105, 7352]
---

# Learning: a rework is a high-yield site for the class it removes

## Problem

PR #7515's own thesis was *"the fix shipped three instances of the class it fixes"*. Its
rework commit cut 61 lines and added 21 to remove them. A 4-seat re-review panel then found
the **rework** had introduced four more instances of the same class, plus a PR body still
advertising every defect the rework had just deleted.

11 findings. All fixed inline; zero scope-outs.

## The generalizable lesson

**A commit whose purpose is removing instances of a defect class is where that class
recurs.** The author is holding the removed instances in mind, not the new prose, and the
new prose is written fast because it feels like cleanup rather than authorship. Review a
rework's *additions* at least as hard as the original implementation — and note that this
recurred here one day after the same class was documented in `2026-08-12-my-ladder-rung-…`.

## What the panel found

### 1. A gate whose input is conversational context reports clean because it could not look

The hold-discharge gate read the operator's hold from *"the plan you already have in
context at this point"*. That is absent after compaction and was never present when
`/ship` is invoked standalone — a path the same file explicitly supports. So **"no hold in
context" was indistinguishable from "no hold was given"**, and the gate built to stop a
held PR from merging went quiet in exactly the compacted-context sessions where holds are
most likely to be forgotten.

Fix: read a durable `## Operator Holds` plan section; stop on an unreachable plan file
rather than reading its absence as an all-clear; record each condition's verdict plus the
producing command so a discharge is auditable.

**Ask of every gate: what is its INPUT, and does that input survive a compaction?**

### 2. A rule that disclaims name-keying while keying on names

The step classifier said, verbatim:

> a step's NAME is a string, and mapping a name to a role is exactly the guess this rule
> exists to replace

…then defined its only exception via `Install <tool>` / `Setup <tool> CLI` **name
patterns**, and its counter-exception via the quoted literal `"Install dependencies"`.

Measured against this repo's `ci.yml`: `Install root dependencies` and `Install
web-platform dependencies` run `bun install --frozen-lockfile` and `npm ci`. **Five of six
dependency-install steps match the exception's name shape and escape the counter-exception's
literal**, so lockfile drift would be reported to a non-technical operator as a CDN outage —
the precise harm the counter-exception existed to prevent.

Fix: discriminate on the failing step's **command**, never its name.

**When prose disclaims a mechanism, check whether its own exception uses that mechanism.**

### 3. A fix for unpaginated truncation, shipping an unpaginated call

Item 3 of the PR fixes `gh run list` defaulting to 20 (a truncated page reads as a clean
result). Item 2, in the same diff, introduced `gh api .../runs/<id>/jobs` with no
`--paginate`.

Measured: `gh api` does **not** auto-paginate; the API caps at **30 jobs per page**; this
repo's `ci.yml` runs carry **23–24 jobs**. Six of headroom — latent, not live, but the same
mechanism and the same signature. The PR's own sentence indicts it: *"A truncated page is
indistinguishable from a clean result."*

Fix constraint worth recording: `--paginate` silently raises the request to `per_page=100`,
and `--jq` runs **per page**, so the `.jobs[]` stream shape survives while an aggregate
(`.jobs | length`) would print one count per page.

### 4. A mitigation that was directionally inverted

The registration-race paragraph said to *"re-query after a delay and treat a **shrinking**
pending-count as evidence the set was still filling."*

A shrinking pending count is the ordinary evidence that runs are **completing**. A set still
filling registers new runs, so pending **grows**. Worse, the failure mode the same paragraph
names holds pending at `0` throughout — so it never shrinks at all, and the prescribed
signal was silent in precisely its own target case.

Fix: key on a **growing total**, held steady across two consecutive checks.

**For any interim mitigation, ask: in the failure mode this paragraph just named, what does
this signal actually read?**

### 5. Smaller instances from the same commit

- **Duplicate step ordinal** — renumbered 5→6 and left the following `6.` un-bumped. Blast
  radius enumerated and found **empty**: every by-ordinal citation in the repo targets
  `2.5`, above the insertion, and no test keys on ordinals. Correctly a P3, not a P2.
- **A dropped mutation axis** — `demotion` was in the deleted section, absent from the
  replacement, and absent from `review/SKILL.md` (its claimed owner), while `ship/SKILL.md`
  and `fullsuite-merge-gate.test.ts` both still actively guard that mutation. The repo was
  testing for an axis it no longer documented.
- **An authority claim that does not hold** — work/SKILL.md said the axes catalogue *"is
  owned by review/SKILL.md … read it there rather than working from memory."* There is no
  catalogue section: the axes are distributed across ~10 bullets under three naming schemes.
  One named axis (`region boundaries`) appeared in no review list at all.
- **A citation that does not carry its evidence** — the diff cited *"#7352 — review found 13
  survivors across five axes it never touched"*. #7352's body contains none of it; the only
  record in the repo says the retraction *"ran a 13-mutation Round 2"*, a different
  proposition. This shipped **inside the paragraph mandating that every added claim have its
  falsifying command run first**.

## Reviewer-side lessons

**A diff hunk header is not the enclosing structure.** I told a review seat that two new
paragraphs sat in a checklist introduced by *"Run these checks before proceeding to Phase 1.
A FAIL blocks execution"*. That string was the **git hunk header** — `xfuncname` picks the
nearest preceding column-0 line, which across ~630 lines of indented list bodies was a
sentence from a different phase. The real context was `### Phase 2: Execute`. The seat caught
it. Verify a hunk header before building a finding on it.

**Rate a renumber finding only after enumerating its by-ordinal citations.** I called the
duplicate ordinal P2 on sight; the enumeration showed zero external consumers and it is a P3.

**Two seats can disagree, and the rule settles it.** One seat said the untracked deferral
violated `wg-when-deferring-a-capability-create-a`; another said its absence was correct.
Reading the rule: documenting in-place **is** the default, and filing requires the
`wg-defer-only-after-inline-triage` triple test to pass. They reconcile once you notice a
documented-in-place deferral is only legitimate if its stated interim mitigation actually
detects the mode — and this one was inverted (§4). Fix the mitigation, and no issue is owed.

## What was verified sound and should not be second-guessed

The mid-run classification mechanism holds end-to-end against a live in-progress run:
`gh run view --log-failed` refuses (*"run … is still in progress"*) while both `gh api`
calls return rows at rc=0. The `-L 200` choice also checks out — three existing issue-side
gates in the same file already use it.

## Session Errors

**`cleanup-merged` hangs at session start** — Recovery: timed out at 2m, noted and deferred,
investigated during compound. Root cause: one `gh pr list --head` network call per worktree
(`worktree-manager.sh:2651`) against **27 worktrees** = 27 sequential round-trips.
**Prevention:** batch the PR lookup into a single query, or cap/parallelize it. The
session-start gate is mandatory (`wg-at-session-start-run-bash-plugins-soleur`), so this
taxes every session. Filed as a tracked issue.

**Fed a review subagent a wrong premise (git hunk header read as the enclosing list)** —
Recovery: the structural-enumeration seat detected and corrected it. **Prevention:** never
cite a hunk header as structure; resolve the enclosing heading before writing the prompt.

**Over-rated a renumber finding before enumerating its blast radius** — Recovery: downgraded
P2→P3 after the by-ordinal citation sweep returned zero external consumers.
**Prevention:** for any renumber, enumerate by-ordinal citations *first*; severity is a
function of the consumer set, not of the edit.

**Scratchpad directory did not exist; heredoc write failed** — Recovery: `mkdir -p`.
**Prevention:** one-off; `mkdir -p` before first write to the scratchpad path.

**Session limit reached twice mid-turn** — Recovery: re-derived worktree state from
`git status` / `git log` and confirmed the uncommitted edit had survived.
**Prevention:** one-off, environmental. Committing inline fixes earlier (rather than
batching all edits before the first commit) bounds the loss.
