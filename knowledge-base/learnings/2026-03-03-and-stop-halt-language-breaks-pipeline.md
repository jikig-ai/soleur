# Learning: "and stop" Halt Language Breaks One-Shot Pipeline

## Problem

The work skill's Phase 4 handoff instruction said `"Implementation complete." and stop.` When invoked by the one-shot orchestrator at step 3, the model interpreted "stop" as a turn-ending signal and ended its response. Steps 4-10 (review, resolve-todo-parallel, compound, ship, test-browser, feature-video) were skipped entirely. The user had to manually intervene to continue the pipeline.

## Root Cause

Constitution.md line 39 already prohibited "Announce to the user" and "Output to the user" as implicit stop signals in pipeline-invokable skills (learned from `2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md`). However, the literal word "stop" was not listed, and the work skill used "and stop" in its Phase 4 pipeline handoff. The model treats "stop" as an unambiguous halt signal regardless of surrounding context.

## Solution

Three-layer fix:

1. **work/SKILL.md Phase 4**: Replaced `"and stop"` with `"then proceed to the next step in the orchestrator's sequence"` — removes the halt signal
2. **one-shot/SKILL.md step 3**: Added continuation guard `"After work completes, continue to step 4 -- do not end your turn."` — belt-and-suspenders defense at the call site
3. **constitution.md line 39**: Extended the Never rule to include `"and stop"` alongside existing prohibited phrases

## Key Insight

Pipeline-invokable skills must never use words that signal finality ("stop", "done", "announce", "tell the user") in their handoff instructions. The model interprets these as turn-ending signals regardless of the parent orchestrator's step sequence. The fix pattern is: replace halt language with explicit continuation ("proceed to the next step") and reinforce at the orchestrator level ("continue to step N -- do not end your turn").

This is the second instance of the same failure class — the first was "announce to the user" (2026-03-02). The constitution.md rule now covers three prohibited phrases but the underlying principle is: **any language that implies the task is complete will cause the model to end its turn in a pipeline context**.

## Session Errors

1. One-shot pipeline halted after work skill step 3 due to "and stop" in Phase 4 handoff — required manual user intervention to diagnose and fix

## Tags

category: integration-issues
module: skills/work, skills/one-shot
related: 2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md
