# Learning: Pipeline continuation stalls when work skill output sounds conclusive

## Problem

The one-shot pipeline stalled after the work skill completed. The work skill's Phase 4 "Handoff" section instructed the model to output `## Work Phase Complete` and "immediately continue executing the next numbered step in the one-shot sequence." However, the instruction relied on natural language ("continue executing") without a corresponding explicit gate in one-shot to enforce that continuation.

At the same time, one-shot's step 3 prose ended with: "Work handles implementation only (Phases 0-3). It does NOT invoke ship -- one-shot controls the full lifecycle below." This framing described work's boundaries but did not tell the model what to do *next* in its current turn. The model read the work skill's output, saw "Implementation complete." (a conclusive-sounding phrase), and treated it as a turn boundary.

The result: steps 4-10 of the one-shot pipeline (review, resolve-todo-parallel, compound, ship, test-browser, feature-video) never executed.

## Solution

Two coordinated fixes:

1. **work/SKILL.md Phase 4** -- Replaced "Implementation complete" with `## Work Phase Complete` as the explicit handoff marker. Added: "Do NOT end your turn after outputting this marker." This tells the model the marker is a continuation signal, not a terminal statement.

2. **one-shot/SKILL.md** -- Added a CONTINUATION GATE block immediately after the work step:

   > **CONTINUATION GATE**: When work outputs `## Work Phase Complete`, that is your signal to continue. Do NOT end your turn. Do NOT treat "Implementation complete" or similar phrases as a stopping point. Immediately proceed to step 4 in the same response.

This gives one-shot an explicit instruction to watch for the marker and keep going, rather than relying on the model to infer continuation from the pipeline structure.

## Key Insight

LLM pipeline continuation depends on **explicit gates, not structural inference**. A model will not automatically continue past a sub-skill's output just because the skill instructions say "proceed to the next step." Conclusive-sounding output -- even a heading like `## Work Phase Complete` -- can be interpreted as a turn boundary unless the *caller* explicitly tells the model what to do when it sees that marker.

The fix pattern for any multi-step pipeline where one step hands off to the next:
- The sub-skill outputs a *structured marker* (not a natural-language completion phrase)
- The orchestrator has an explicit CONTINUATION GATE that names the marker and says "this is your signal to keep going"

Without both halves, the pipeline is vulnerable to stall at any sub-skill boundary.

See also: `2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md` (earlier instance where "announce" language caused an identical stall; this session's fix adds the orchestrator-side gate that was missing from the prior fix).

## Session Errors

1. **Deepen-plan audit false negative** -- The deepen-plan audit reported zero incompatibilities with upgrading bare `set -e` to `set -euo pipefail`, but missed two concrete failure modes (bare positional args under nounset, grep-in-pipeline under pipefail). Audit subagents must be instructed to test the script against all invocation patterns, not just the happy path.
2. **Pipeline stall itself** -- One-shot ran the work skill but stopped after it returned, never proceeding to review or ship. Root cause: missing CONTINUATION GATE in one-shot and overly conclusive language in work Phase 4.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/one-shot
