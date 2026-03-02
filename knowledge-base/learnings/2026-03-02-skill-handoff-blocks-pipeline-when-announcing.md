# Learning: Skill handoff instructions block pipelines when they tell the model to "announce"

## Problem

The work skill's Phase 4 "Handoff" section instructed the model to "Announce to the user: Implementation complete. Next steps: review -> compound -> ship." When one-shot invoked work via the Skill tool, the model interpreted "announce to the user" as a terminal action -- output text and wait for user input. Since there is no user in a pipeline context, the model treated the announcement as the end of its turn and stopped. Steps 4-10 of the one-shot pipeline (review, compound, ship, etc.) never executed.

## Solution

Changed Phase 4 to: "Return control immediately. Do not prompt the user for next steps or wait for input." Added a fallback for direct user invocation: "If invoked directly by the user (not via one-shot), output a single line: 'Implementation complete.' and stop."

The key change is eliminating any language that implies user-facing output as the final action. "Return control" is an unambiguous instruction that does not trigger the model's turn-ending behavior.

## Key Insight

In LLM skill instructions, any phrasing that implies user-facing output ("announce", "tell the user", "inform the user", "display") is interpreted as a terminal action. The model outputs the text and ends its turn, waiting for user input that will never come in a pipeline context. When a skill must hand off control to a caller, the instruction must be framed as "return control" or "yield to caller" -- never as "announce" or "output."

This is a specific instance of a broader pattern: skill instructions are executed by a model that treats user-directed output as turn boundaries. Any instruction that looks like "say something to the user" will end the model's turn, regardless of whether more work remains in the pipeline.

See also: `2026-02-26-decouple-work-from-ship-review-before-merge.md` (the architectural change that introduced the handoff; this learning documents the bug in how the handoff was phrased).

## Session Errors

1. **Edit tool "file not read" errors** -- Attempted to edit 6 files without reading them first. The Edit tool requires a prior Read call in the same conversation before it allows modifications.
2. **Edit tool "string not found"** -- Used HTML entity `&amp;` in the old_string when the file contained a literal `&`. The Edit tool matches exact bytes, not rendered characters.
3. **Git merge blocked by uncommitted changes** -- Tried to merge a branch before committing working tree changes. Git requires a clean working tree for merge operations.
4. **Work skill Phase 4 blocked the pipeline** -- The main bug. "Announce to the user" caused the model to stop, preventing one-shot from continuing to review/compound/ship steps.

## Tags
category: logic-errors
module: plugins/soleur/skills/work
