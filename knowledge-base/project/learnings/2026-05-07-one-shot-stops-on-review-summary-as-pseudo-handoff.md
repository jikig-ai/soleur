---
module: one-shot
date: 2026-05-07
problem_type: workflow_issue
component: skill_orchestration
symptoms:
  - "one-shot pipeline runs review then stops mid-task"
  - "agent treats review's '## Code Review Complete' summary as a turn-ending deliverable"
root_cause: missing_continuation_gate_after_review
severity: medium
tags: [one-shot, review, continuation-gate, workflow]
---

# Learning: one-shot stops after review because the summary block reads like a deliverable

## Problem

During PR #3399's one-shot run, the agent completed step 4 (`skill: soleur:review`),
emitted the prescribed `## Code Review Complete` block + `### Next Steps`
section, then ended the turn — leaving steps 5–8 (resolve findings, QA,
compound, ship) un-executed until the user nudged with "btw, why did you stop
mid task?"

The pipeline didn't crash. There was no error. The agent simply mistook the
review skill's verbose summary for a turn boundary, in violation of AGENTS.md
`hr-when-a-workflow-concludes-with-an-actionable-next-step`.

## Root cause

Two structural gaps in the SKILL definitions:

1. **`one-shot/SKILL.md`** had a `> CONTINUATION GATE` between work (step 3)
   and review (step 4) but **none** between review (step 4) and the resolve
   step (step 5). Work outputs `## Work Phase Complete` and the gate says
   "this is a status marker, not a stopping point — proceed in the same
   response." Review outputs `## Code Review Complete` with a `### Next Steps`
   block — and there was no equivalent gate, so the model defaulted to its
   built-in "summarize and yield" instinct.

2. **`review/SKILL.md`** Step 3 (Summary Report) emitted the same verbose
   `## Code Review Complete` template **regardless** of invocation mode.
   Pipeline detection lived in Phase 6 (Exit Gate) and only said "skip the
   exit gate" — too late: by then the agent had already written the
   terminal-shaped summary and was preparing to return. The framing
   (heading + Next Steps + advice on what `/ship` does next) reads exactly
   like an end-of-task handoff to a human reviewer, even though the calling
   orchestrator was waiting on a tight progress marker.

The two gaps compounded: review emitted a turn-ending-shaped block, and
one-shot had no rail to recognize it as a checkpoint.

## Solution

Two SKILL.md edits — both small, both reinforce the same invariant from
opposite sides.

**`plugins/soleur/skills/one-shot/SKILL.md`:** Added a `> CONTINUATION GATE`
between step 4 (review) and step 5 with the same shape as the work→review
gate. Names the failure modes explicitly ("`## Code Review Complete`",
"Findings Summary", "Next Steps") and extends the rule to every subsequent
hand-off (5 → 5.5 → 6 → 7 → 8) so each skill's exit summary is treated as a
checkpoint, not a stopping point.

**`plugins/soleur/skills/review/SKILL.md`:** Step 3 now runs **pipeline
detection FIRST**, before any heading is emitted. In pipeline mode the
review skill emits a compact `## Review Phase Complete` marker (analogous
to work's `## Work Phase Complete`) with no `### Next Steps` block —
removing the framing that triggers the stop. Phase 6's pipeline-detection
paragraph explicitly says "do not output the verbose `## Code Review
Complete` block" so the two sections agree.

The compact marker is the first-class signal; the verbose block is reserved
for direct interactive invocations where a human reader is the audience.

## Key insight

When a skill's exit summary uses the same heading-and-Next-Steps shape that
the model has been trained to use as a "task complete, return control to the
user" handoff, no amount of "skip the exit gate" instruction downstream can
prevent the stop — the agent has already framed the response as terminal.
The fix is to suppress the terminal-shaped output **at the source** for
orchestrator callers, AND add an explicit continuation rail in the
orchestrator that names the visual pattern the agent will encounter.

This generalizes: any skill in the `plan → work → review → qa → compound →
ship` chain that emits a verbose summary block needs the same two-sided
defense — a compact pipeline-mode marker on the producer side, plus a
continuation gate on the orchestrator side that names the marker and the
forbidden alternatives. Work and review are now consistent; the same
audit should apply to QA, compound, and ship summaries the next time one
of them produces a stop-on-summary regression.

## Session errors

None new for this session — the fix WAS the response to the last
session's stop-on-review-summary error.

## Cross-references

- AGENTS.md `hr-when-a-workflow-concludes-with-an-actionable-next-step` —
  the load-bearing rule the stop violated.
- `plugins/soleur/skills/work/SKILL.md` — `## Work Phase Complete` marker
  pattern that this fix mirrors for review.
- PR #3399 — the run where the stop was observed and the user nudge was
  required to resume.
