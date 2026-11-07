---
module: System
date: 2026-10-23
problem_type: workflow_issue
component: tooling
symptoms:
  - "Plan said eval-gate.cjs and verdict.cjs need no change because --target-task accepts a retention case; two review seats falsified it"
  - "The CLI passes no epsilon (eval-gate.cjs:278 hands computeVerdict empty options) and --target-task is only a 0.5 floor on the candidate's own rate"
  - "A public issue comment posted in the work phase omitted the evidence bar and had to be edited in place after review"
  - "The Why-share figure (12.9 percent, 8.8k tokens) was stated as a point estimate but is 5.1 to 16.1 percent depending on where a span ends"
root_cause: missing_workflow_step
resolution_type: documentation_update
severity: medium
tags: [eval-harness, plan-claims, verification, outward-record, measurement-span]
---

# Troubleshooting: a plan claim about a gate's reach was read at the function, not run through the CLI

## Problem

WikiSkills Phase 3 (#10551) asked to move rationale out of `ship/SKILL.md` once the eval harness could show a moved-rationale skill behaves no worse. The harness could not (`--check` gated:false, `--dry-run --target ship` exit 1), so the run stopped after the finding. The plan's description of the smallest closure was wrong in three ways that only the review panel found.

## What Didn't Work

**Reading the gate's functions to establish what the gate can do.** The plan said "`verdict.cjs` and `eval-gate.cjs` need no change" and that a retention case goes through `--target-task`, "verified in code by the CTO and the simplicity seat". That was true of `computeVerdict` and false of the entry point a Capability PR would actually drive: `eval-gate.cjs:278` calls `computeVerdict(..., {})` with no options and `parseArgs` has no epsilon or threshold flag, so the "explicit epsilon" route in the discrimination bar was unreachable. `--target-task` decides on the candidate's own rate (`>= 0.5`), never the baseline's, so a retention case can fall 1.0 to 0.5 and still accept. And a no-op edit short-circuits to `accept:true` before any API call.

**Posting the durable record before the evidence bar was settled.** The one comment on the open tracker is the only text that survives when the plan and specs are archived. It was posted in the work phase, before review produced rulings T7 to T10, so it omitted the harness-plus-lint bar and paraphrased spec TR1 lossily. It had to be edited in place (marker line kept byte-identical, count still 1).

**A single number for a span-dependent quantity.** "54 lines, 12.9 percent" counted whole lines containing the marker. Measured three ways it is 5.1 percent (first marker to end of line), 12.9 percent (whole lines) or 16.1 percent (to the next blank line).

## Solution

- The CTO amended T2, T2b and T5 (rows T7, T7b, T8): the Capability PR adds no flag to the shared gate, puts retention cases in the corpus, and asserts on the `per_task` array by script; the Move PR evidence is the slice verdict plus a non-circular CI lint; moved paragraphs must lie inside the wrapped span.
- The figure became a range with its basis (T9), the comment was edited in place (T10), and the plan was swept by claim, not by file.

## Key Insight

When a plan states what a tool can do, the claim is about the tool's reachable surface, so run the path a caller would take (the CLI with its real flags, against a fixture) before writing it down, and name the entry point in the claim. Reading the inner function proves what the function does, not what any caller can make it do. Likewise, hold a durable outward record (an issue comment, a PR body) until the rulings it summarizes have survived review, or write it so that a later correction is a small edit; and when a quantity depends on where a span ends, state the range and the span definition, not a point.

## Session Errors

**Planning subagent hit a TLS handshake timeout on one `gh issue list`** - Recovery: retry succeeded. Prevention: none needed (transient).

**Deepen-plan's all-agent fan-out was not run** - Recovery: disclosed in the plan's Enhancement Summary; five plan-review seats and two CTO rulings substituted. Prevention: none needed (docs-only deliverable, disclosed).

**`session-state.md` was not written after the planning subagent returned (one-shot Step 2)** - Recovery: written during compound. Prevention: write it in the same turn the Session Summary is parsed, before the technical-ruling gate.

**Closing message put a technical fork (is slice evidence sufficient, what to build first) to the operator** - Recovery: the Stop hook blocked it, the CTO ruled (T5, T6). Prevention: already hook-enforced; spawn the CTO before drafting any closing question about evidence bars or ordering.

**Closing text promised a next action and ended the turn** - Recovery: the Stop hook caught it and the action was taken. Prevention: already hook-enforced; end a waiting turn with a `Paused:` sentence.

**Plan claim about the gate's reach verified at the function, not the CLI** - Recovery: review falsified it, CTO amended (T7, T7b, T8). Prevention: run the real entry point with its real flags against a fixture before writing a "needs no change" or "can be passed" claim; the Capability PR owns the eval-harness README note on what the CLI can and cannot pass.

**Public tracker comment posted before the evidence bar was settled** - Recovery: edited in place via the comment API, marker count verified at 1. Prevention: post the durable record after the review rulings, or keep the first post minimal and amend.

**First fix commit swept by file and left the pre-T8 lint description and move-PR bullet in the plan** - Recovery: the verification pass found both; second fix commit. Prevention: after any ruling, grep the paraphrases of the superseded claim across every file, not only the sentence edited.

**CTO-written ruling row carried a bare URL (markdownlint MD034)** - Recovery: backticked it. Prevention: run markdownlint on files a delegated agent edited before committing.

**Why-share quoted as a point estimate** - Recovery: restated as a range with its span definitions (T9). Prevention: measure a span-dependent quantity at each plausible span boundary before quoting one number.

## Tags

category: workflow-issues
module: System
