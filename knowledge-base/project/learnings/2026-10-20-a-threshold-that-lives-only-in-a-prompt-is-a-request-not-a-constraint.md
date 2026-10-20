---
title: a threshold that lives only in the prompt is a request, not a constraint -- and the fixtures that encode the unenforced number are the blast radius
date: 2026-10-20
category: integration-issues
module: apps/web-platform/server/inngest/functions/cron-compound-promote.ts
tags: [compound-promote, llm-contract, server-side-enforcement, refusal-vocabulary, fixture-blast-radius, followthrough-probe]
issue: 10552
pr: 10673
---

# Learning: a number the model is only ASKED to respect has to be a number the server CHECKS

## Problem

The Compound Promotion Loop promises a draft PR only for a cluster of at least five related learnings. That
"five" existed as prompt prose and as the literal `/5` in the `Threshold-Hit: N/5` trailer. Nothing checked it, so a
two-learning cluster would open a draft PR whose own trailer read `Threshold-Hit: 2/5` (an inference from the code and
the fixtures, not an observed incident: the weekly run had opened zero PRs). The previous PR (#10553) made
`source_learnings` honest (non-strings dropped, duplicates collapsed, only corpus keys kept), which is what made the
length of that list a trustworthy count, and it deliberately deferred the check.

## Solution

One exported constant, `PROMOTION_QUORUM`, read by the prompt, the check and the trailer. The check is the first
statement that can refuse inside `draftAdditiveEdit`, so it precedes every git read and the phase-2 model call, and it
rides the existing memoized `draft-edit-*` step: `record()`, marker `refusals[]` and the message-path Sentry call are
reused, the outcome-marker field set is unchanged, and the Sentry event fires once per step instead of once per replay.
The refusal is `quorum-not-met`, deliberately not an `edit-*` name, because census Guard 1b pins that prefix to a
fixed vocabulary of seven.

## Key Insight

1. **Place a new refusal inside the unit that is already memoized, not beside it.** A handler-body predicate re-runs on
   every replay (its Sentry call would too); a second memoized step breaks the census that allows exactly one callback of
   that shape. The CTO ruled option A for exactly that reason, and it also made the "no model call" property structural.
2. **The tests that encoded the unenforced number were the real blast radius.** Every handler fixture used two-source
   clusters and one asserted `Threshold-Hit: 2/5`; they were valid exactly because nothing enforced the quorum. The sweep
   for a new refusal reason has to include fixtures that quietly depend on its absence, and the rebuild should size them
   from the constant, never a literal, or lowering the constant passes vacuously. One row pins the value so a change is a
   visible diff.
3. **A new refusal reason is a sweep over every artifact that enumerates reasons, done up front:** the closed-set types
   and census, the follow-through probe's class sets (a reason in no set prints as `unknown`, so the name vanishes), the
   probe suite's `MIN_CASES` floor (raise it by exactly the measured delta), both runbook tables and the ADR amendment.
4. **A model-side refusal must be class N in the probe.** Class P would let a quorum refusal count as proof the derived-diff
   path works; class F would page a server defect for a model behaviour. Mutation rows that add it to the P set and drop it
   from the N set prove the classification is load-bearing.
5. **A census that counts declarations and uses pins the endpoints, not the wire.** The first census proved the
   constant was declared once and read by the prompt, trailer and comparison, yet moving the check below the file read
   or emptying its body kept it green (only the behavioural rows caught that). The structural-enumeration seat's
   question, "does the guard's assembly equal the property it names", produced the fix: assert the comparison's `if`
   returns the refusal and ends before the first `readEditTarget(`/`post(` in its function.
6. **Do not thread a diagnostic through a function that never uses it.** A raw list length rode
   ProposedCluster -> drafter parameter -> refusal field -> handler just to reach one Sentry field; the handler already
   held the proposal, so the route was cut and the three-name drift (raw/proposed/proposedCount) went with it.
