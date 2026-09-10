---
title: "Three measurement instruments, two wrong before they were right"
date: 2026-09-10
category: workflow-patterns
module: measurement
tags: [measurement, instrument-validation, external-tool-eval, counting, falsification]
related_issues: [5708, 1055]
related_prs: [8025]
---

# Learning: three measurement instruments, two wrong before they were right

## Problem

The Serena MCP evaluation (PR #8025) had to decide adoption on **measured**
evidence against pre-registered thresholds, rather than architectural intuition.
Three instruments were built. Two produced confident, plausible, wrong numbers
first — and in both cases the wrong number would have supported the same final
verdict **for the wrong reason**, which is precisely why neither was caught by
sanity-checking the conclusion.

## Solution

### 1. `wc -l | tail -1` over a file list undercounts, sometimes by 36×

```bash
# WRONG — xargs splits the list into batches; wc emits a `total` PER BATCH,
# so tail -1 captures only the LAST batch.
git ls-files -- 'knowledge-base/**/*.md' | xargs wc -l | tail -1
#   -> 38,440

# RIGHT
git ls-files -z -- 'knowledge-base/**/*.md' | xargs -0 cat | wc -l
#   -> 1,403,888
```

The undercount was **36×**, and it landed on the single most load-bearing fact in
the evaluation (how much of the repo is prose vs code). It is silent: the command
exits 0 and prints a number that looks like an answer.

**The tell was present and missed.** A subagent made the identical error
independently, and its results table had a cumulative-percentage column that
reached **102.5%**. A percentage column summing past 100% is instrument failure,
never rounding.

### 2. A classifier must model how *this* repo actually navigates

The first A1 instrument classified `tool_result` bytes by the tool that produced
them, counting only `Read`/`Grep`/`Glob`. It returned `nav_code = 0.00%`.

That reads as a finding — "agents never look at code" — and it was an artifact.
This repo runs in bypass-permissions mode, whose instructions tell agents to read
with `cat`/`sed` and search with `grep` **through the Bash tool**. Bash carried
**93.19%** of all tool-result bytes; the classifier was blind to every one of
them. After teaching it to parse Bash commands for read/search verbs and target
paths, `nav_code` moved 0.00% → 5.86%.

**Generalizable rule:** before trusting a *share*, check where the **denominator**
went. A 93% bucket labelled "other" is the finding, not the background.

### 3. Bracket when the ambiguous bucket exceeds the margin to the threshold

A1 measured 5.86% against a pre-registered 15% threshold — with a **23.53%**
unadjudicated bucket sitting right next to it. The ambiguity was four times the
apparent margin, so the point estimate could not settle the question even though
it looked decisively below the line.

The fix was not to adjudicate the bucket (expensive) but to compute a
**deliberately over-generous upper bound**: count a navigation result as "code"
if *any* code extension appears anywhere in the command, so a `grep` touching one
`.ts` and five `.md` files scores as code. That returned **11.13%** — still below
threshold. The failure became conclusive without the ambiguity ever being resolved.

## Key Insight

All three failures share one shape: **the instrument answered a different question
than the one asked, and its output was well-formed enough to pass as an answer.**
A wrong count, a wrong denominator, and a wrong precision claim are the same defect
at three levels.

Two practices caught them, and both are cheap:

- **Drive every instrument against a synthesized known-positive AND known-negative
  before believing its output.** Both A1 versions were validated on fixtures with
  hand-computed answers; that is what exposed v1's 0.00% as a classifier gap rather
  than a finding.
- **Pre-register thresholds to a committed file before measuring.** The criteria
  were committed at `f2b04cabb` ahead of any data, so when the first number came
  back at 0.00% there was no temptation to reinterpret the threshold around it.

Corollary, learned from the prior Headroom evaluation's own recorded error:
**commit the reproduction scaffold.** It was committed here under
`knowledge-base/project/specs/feat-serena-mcp-eval/measurement/`, *including the
known-broken v1*, because a future reader needs to see the failure mode, not just
the corrected result.

## Prevention

| Error | Prevention |
|---|---|
| `wc -l \| tail -1` undercount | Never `wc -l` over an xargs-batched file list; use `xargs -0 cat \| wc -l`. Treat any percentage column past 100% as instrument failure. |
| Subagent's count taken on trust | Re-derive any count that bounds a decision. The existing rule already says this; the addition is that a >100% column is a free, automatic tell — look for it. |
| Classifier blind to the dominant tool | Before trusting a share, print the denominator's own breakdown. If one bucket is >50% and labelled "other", the classifier is the problem. |
| Point estimate near a threshold | When an unadjudicated bucket exceeds the margin to the threshold, bracket with a deliberately generous bound before concluding. |
| Inherited premise unfalsified | For a premise handed in with the task ("we now have a baseline"), name the command that would falsify it and run it before building on it. |

## Session Errors

1. **`wc -l | tail -1` undercounted KB markdown 36×** (38,440 vs 1,403,888) and
   the wrong figure reached the brainstorm's first draft.
   **Recovery:** re-derived with `xargs -0 cat | wc -l`, which independently
   confirmed a subagent's separately-produced 1,499,642 for all markdown.
   **Prevention:** as above — never `wc -l` over a batched file list.

2. **A subagent produced the same undercount, with an uncaught tell.** Its table's
   cumulative column read 102.5%.
   **Recovery:** re-derivation; the conflict between three different values for
   one quantity forced the check.
   **Prevention:** treat a >100% percentage column as a hard stop.

3. **A1 v1 reported `nav_code = 0.00%`, which was false.** Blind to Bash (93.19%
   of tool-result bytes).
   **Recovery:** v2 parses Bash read/search commands; 0.00% → 5.86%.
   **Prevention:** inspect the denominator before trusting a numerator.

4. **A1 was nearly reported as a point estimate** with a 23.53% ambiguous bucket
   against a 15% threshold.
   **Recovery:** computed a generous upper bound (11.13%), making the failure
   conclusive at both bounds.
   **Prevention:** bracket when ambiguity exceeds the margin.

5. **The task's stated premise — that the newly shipped per-workflow cost
   instrumentation provided "a real baseline to measure against" — did not hold.**
   Migration 136 is tenant-side and conversation-grain; operator-local sessions
   never write to it, and ADR-209 extends the turn-grain non-goal into attribution.
   **Recovery:** reported the mismatch as a finding and corrected the premise in
   the record instead of force-fitting a measurement onto the wrong table.
   **Prevention:** an inherited premise is a claim to falsify, not a floor to build
   on — recorded under `wg-every-session-error-must-produce-either`, because
   quietly measuring the wrong thing to satisfy a stated premise is how a wrong
   number acquires authority.

What DID hold: the fixture validation of both instruments, the pre-registration
discipline, and the prior-art sweep that surfaced the unmerged 2026-06-29
codebase-memory record and its still-open tracking issue #5708.
