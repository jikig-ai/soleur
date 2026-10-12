# Spec: Enforce UX Design and Content Review Gates

**Issue:** #1137
**Date:** 2026-03-25
**Status:** Draft

## Problem Statement

Domain leader specialist recommendations (wireframes, copywriter review) are captured as text in brainstorm documents but never enforced as prerequisites in the plan and work skills. This allows implementation to start on user-facing pages without UX design or content review.

## Goals

- G1: Prevent brainstorm carry-forward from satisfying the BLOCKING UX gate on new pages
- G2: Add a Content Review gate that enforces copywriter/content specialist review for copy-heavy pages
- G3: Hard-block work skill implementation when recommended specialists have unresolved `pending` status

## Non-Goals

- Changing the brainstorm skill (brainstorm = WHAT, not HOW)
- Adding new specialist agents
- Retroactively fixing existing plans (legacy plans get softer treatment)

## Functional Requirements

- **FR1**: Plan skill BLOCKING UX gate rejects "carried from brainstorm" for new user-facing pages. Must produce wireframes or explicitly skip with justification.
- **FR2**: Plan skill Content Review gate fires when BOTH: (a) plan auto-detects "copy-heavy" page, and (b) domain leader recommends copywriter/content specialist.
- **FR3**: Plan skill writes structured specialist status fields: `Specialist: ran | skipped(reason) | pending`.
- **FR4**: Work skill Phase 0.5 reads specialist status fields and hard-blocks on any `pending` status.
- **FR5**: Work skill prompts user to run specialist or explicitly decline (updates to `skipped(reason)`) before proceeding.
- **FR6**: Plans created before this fix (no status fields) receive a softer warning, not a hard block.

## Technical Requirements

- **TR1**: Status fields must be parseable by grep (consistent format, no ambiguous syntax).
- **TR2**: Changes limited to `plugins/soleur/skills/plan/SKILL.md` and `plugins/soleur/skills/work/SKILL.md`.
- **TR3**: Decline justification is recorded in the plan file for audit trail.

## Key Design Decisions

See brainstorm: `knowledge-base/project/brainstorms/2026-03-25-enforce-ux-content-gates-brainstorm.md`

1. Dual-signal Content Review trigger (auto-detect + domain leader confirmation)
2. Structured status fields over heading presence checks
3. Skip with justification over unconditional skip or no-skip
4. Hard block over warning for work skill enforcement
5. Inline gate enhancement over separate registry file
