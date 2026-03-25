---
title: "fix: enforce UX design and content review gates in plan/work skills"
type: fix
date: 2026-03-25
---

# fix: enforce UX design and content review gates in plan/work skills

Closes #1137

## Overview

Domain leader specialist recommendations (wireframes, copywriter review) are captured as text but never enforced. The plan skill's BLOCKING UX gate accepts "carried from brainstorm" for new pages, no Content Review gate exists, and the work skill has no specialist check.

**Origin:** Pricing page v2 (#656) — CMO recommended copywriter, CPO recommended UX review, but implementation bypassed both.

## Proposed Solution

Three changes to two SKILL.md files. Simplified per plan review: domain-leader-only trigger (no dual-signal), extend existing heading contract fields (no separate Specialist Status subsection), no legacy detection (existing check 7 suffices).

### Change 1: Tighten BLOCKING UX Gate (`plugins/soleur/skills/plan/SKILL.md`)

**Location:** "On BLOCKING" section (lines 218-224). Insert a pre-check **before** step 3 (ux-design-lead invocation).

Add before step 3:

```markdown
**Brainstorm carry-forward check (BLOCKING tier only):**

Before invoking ux-design-lead, check the UX signal source:

- If the only UX validation is brainstorm carry-forward (brainstorm assessed the
  *idea*, not the *page design*), reject it. Display: "Brainstorm validated the
  idea, not the page design. Proceeding to wireframes."
- This check applies to BLOCKING tier only. ADVISORY and NONE tiers may still
  carry forward brainstorm UX findings.
- After this check, proceed to step 3 (ux-design-lead invocation) as normal.
  The existing Pencil-unavailable handling in step 3 remains unchanged.
```

After step 3 resolves (wireframes produced or Pencil unavailable), record the outcome using the existing heading contract fields:

- If ux-design-lead produced wireframes: add `ux-design-lead` to `**Agents invoked:**`
- If Pencil unavailable and user skips with justification: add to `**Skipped specialists:** ux-design-lead (<reason>)`

### Change 2: Add Content Review Gate (`plugins/soleur/skills/plan/SKILL.md`)

**Location:** Within the "On BLOCKING" section, as a new step 4 after ux-design-lead (step 3).

```markdown
4. **Content Review Gate.** Check if any domain leader (CMO, CRO, CPO, or other)
   recommended a copywriter or content specialist in their Step 1 assessment.
   If yes:

   a. Invoke copywriter agent via Task with prompt: "Review the planned page
      content for brand voice compliance, value proposition clarity, and
      messaging effectiveness. Reference brand-guide.md."

   b. If copywriter ran successfully: add `copywriter` to `**Agents invoked:**`

   c. If user declines: add to `**Skipped specialists:** copywriter (<reason>)`

   d. If copywriter agent fails (timeout, error): add to
      `**Skipped specialists:** copywriter (agent error — review manually)`
      and set `**Decision:** reviewed (partial)`

   If no domain leader recommended a copywriter: skip this step silently.

   This gate also fires on ADVISORY tier when a domain leader recommended
   a copywriter — the recommendation is the signal, not the tier.
```

### Change 3: Update Domain Review Heading Contract (`plugins/soleur/skills/plan/SKILL.md`)

**Location:** Heading contract template (lines 240-262)

Add a `**Skipped specialists:**` field to the Product/UX Gate block:

```markdown
### Product/UX Gate

**Tier:** blocking | advisory
**Decision:** reviewed | reviewed (partial) | skipped | auto-accepted (pipeline)
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter | [subset]
**Skipped specialists:** ux-design-lead (<reason>), copywriter (<reason>) | none
**Pencil available:** yes | no | N/A
```

The work skill checks two fields:

- `**Agents invoked:**` — which specialists actually ran
- `**Skipped specialists:**` — which were skipped with justification

No new subsection needed. No `pending` state. A specialist is either in `Agents invoked` (ran), in `Skipped specialists` (declined), or absent from both (not recommended — no action needed).

### Change 4: Work Skill Pre-Implementation Check (`plugins/soleur/skills/work/SKILL.md`)

**Location:** Phase 0.5 Pre-Flight Checks (lines 58-83), add as check 9

```markdown
9. If a plan file was provided (check 5 passed) and a `## Domain Review` section
   exists with a `### Product/UX Gate` subsection:

   a. Read the `**Decision:**` field. If it says `reviewed (partial)`, WARN:
      "Domain review was partial — some specialist agents failed. Review the
      Domain Review section before proceeding."

   b. Check if domain leader assessments (in `## Domain Review` subsections)
      recommended specialists (copywriter, ux-design-lead, conversion-optimizer)
      that are NEITHER in `**Agents invoked:**` NOR in `**Skipped specialists:**`.
      If any recommended specialist is missing from both fields: FAIL with message
      listing the missing specialists and options:
      - "Run <specialist> now" — work skill invokes the specialist agent directly,
        updates the plan file's `**Agents invoked:**` field, then continues
      - "Skip with justification" — work skill adds to the plan file's
        `**Skipped specialists:**` field, then continues

   c. **Pipeline mode (headless/one-shot):** If the work skill is in pipeline
      mode and missing specialists are detected, auto-invoke each specialist
      agent. If the agent succeeds, add to `**Agents invoked:**`. If it fails,
      add to `**Skipped specialists:** <name> (auto-skipped — agent unavailable
      in pipeline)` and WARN. Do not FAIL in pipeline mode — log the gap and
      continue.

   d. If all recommended specialists are accounted for (in Agents invoked or
      Skipped specialists): pass silently.
```

## Acceptance Criteria

- [ ] Plan skill: BLOCKING UX gate rejects brainstorm carry-forward — pre-check fires before ux-design-lead invocation (`plugins/soleur/skills/plan/SKILL.md`)
- [ ] Plan skill: Content Review gate fires when any domain leader recommends copywriter, on both BLOCKING and ADVISORY tiers (`plugins/soleur/skills/plan/SKILL.md`)
- [ ] Plan skill: `**Skipped specialists:**` field added to heading contract (`plugins/soleur/skills/plan/SKILL.md`)
- [ ] Work skill: check 9 blocks when recommended specialists are missing from both `Agents invoked` and `Skipped specialists` (`plugins/soleur/skills/work/SKILL.md`)
- [ ] Work skill: pipeline mode auto-invokes missing specialists instead of blocking
- [ ] Work skill: user can resolve by running specialist or skipping with justification

## Test Scenarios

- Given a BLOCKING plan with brainstorm carry-forward only, when plan runs, then it rejects carry-forward and proceeds to ux-design-lead invocation
- Given a plan where CMO recommends copywriter, when plan runs BLOCKING pipeline, then Content Review gate fires and invokes copywriter
- Given a plan where no domain leader recommends copywriter, when plan runs, then Content Review gate is skipped silently
- Given a plan where copywriter agent fails during Content Review gate, when plan writes Domain Review, then `Decision: reviewed (partial)` and `Skipped specialists: copywriter (agent error)` are written
- Given a plan with recommended specialists missing from both `Agents invoked` and `Skipped specialists`, when work skill runs Phase 0.5, then it FAIL-blocks with remediation options
- Given a plan with all recommended specialists in `Agents invoked` or `Skipped specialists`, when work skill runs Phase 0.5, then it passes silently
- Given a plan with `Decision: reviewed (partial)`, when work skill runs Phase 0.5, then it WARNs about partial review
- Given a plan in pipeline mode with missing specialists, when work skill runs Phase 0.5, then it auto-invokes specialists and continues (no hard block)

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** Low architectural risk. Two SKILL.md files with well-defined patterns. Extends existing heading contract fields rather than introducing new formats.

### Product

**Tier:** none (plan discusses UI concepts but implements orchestration changes to skills)

No Product/UX Gate pipeline needed — this is internal tooling.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-25-enforce-ux-content-gates-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-enforce-ux-content-gates/spec.md`
- Origin case: #656 (pricing page v2)
- Plan skill target: `plugins/soleur/skills/plan/SKILL.md:194-274`
- Work skill target: `plugins/soleur/skills/work/SKILL.md:58-83`
- Plan review: DHH, Kieran, code-simplicity (2026-03-25)
