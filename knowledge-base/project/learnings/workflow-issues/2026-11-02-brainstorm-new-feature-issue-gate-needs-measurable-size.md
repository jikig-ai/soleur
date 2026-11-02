# Learning: a brand-new feature cannot pass the issue-filing gate at brainstorm time

## Problem

Brainstorm Phase 3.6 tells the agent to `gh issue create` a tracking issue for the feature. The PreToolUse issue-filing gate refused it twice: first for naming no user-visible consequence, then, once `User-Impact:` and `Fix-Size: 0 lines / 0 files` were added, because that size is inside the inline threshold (<=100 lines and <=4 files, ADR-131) and so reads as "fix inline instead of filing". A feature that is not built yet has no measurable fix size, so the only honest `Fix-Size` is 0/0, which the gate always refuses.

## Solution

Do not file a tracking issue at brainstorm time for a new unbuilt feature. Use the draft PR as the tracker, record the missing issue under Open Questions, and file at plan time once the feature is sized and placed in a roadmap phase, where `wg-every-feature-listed-in-a-roadmap-phase` supplies the `Mandated-By:` exit. Deferred Non-Goals are documented in the spec rather than filed (`wg-when-deferring-a-capability-create-a`).

## Key Insight

The gate's three exits assume a defect, a machinery finding, or a rule-mandated filing. A fresh feature idea fits none until it is sized and roadmapped. Inventing a plausible `Fix-Size` to get through would defeat the gate's "measured, not estimated" requirement.

## Session Errors

1. **Ran condensed equivalents of the go gate scripts instead of the three verbatim fences.** Recovery: none needed, all probes passed. Prevention: one-off; the equivalents covered the same checks, but quote the fences when the harness is unfamiliar.
2. **Issue-filing gate refused the feature tracking issue twice.** Recovery: dropped the issue, used the draft PR as tracker. Prevention: a brand-new feature with no code yet cannot satisfy the `Fix-Size:` exit (`0 lines / 0 files` is inside the inline threshold); skip the tracking issue at brainstorm time, note the draft PR as the tracker, and file the issue at plan time once the feature is sized and placed in a roadmap phase. (A skill bullet was drafted and dropped: `brainstorm/SKILL.md` is exactly at its lifecycle byte ceiling, `scripts/lint-skill-body-budget.py`, so this learning is the record.)
3. **Stop hook flagged a closing sentence promising a next action.** Recovery: did the action (asked the scoping question). Prevention: one-off.
4. **Skill-description budget probe printed no headroom number** (grep for "word|budget" matched only the pass count). Recovery: left the headroom measurement to plan time. Prevention: one-off; measure through `discoverSkills()` when a new skill is named.

## Tags

category: workflow-issues
module: brainstorm, issue-filing gate
