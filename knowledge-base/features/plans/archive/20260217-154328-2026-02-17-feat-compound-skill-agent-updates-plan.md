---
title: "feat: Compound routes learnings to skill and agent definitions"
type: feat
date: 2026-02-17
issue: "#104"
version_bump: MINOR
---

# feat: Compound routes learnings to skill and agent definitions

## Overview

Extend `/soleur:compound` with a new step after learning capture that routes the learning as a one-line bullet edit to the active skill/agent/command definition. The user confirms every edit with Accept/Skip/Edit.

## Problem Statement

Compound captures learnings in `knowledge-base/learnings/` and optionally promotes to the constitution, but never updates the skill/agent instructions that directly govern behavior. Skills repeat mistakes because their definitions never improve.

## Proposed Solution

Two file edits -- all prompt instruction changes, no code:

1. **`plugins/soleur/skills/compound-docs/SKILL.md`** -- Add Step 8 (route learning to definition) inside the existing `<critical_sequence>` block, between Step 7's `</step>` tag (line ~253) and the `</critical_sequence>` closing tag (line ~255).

2. **`plugins/soleur/commands/soleur/compound.md`** -- Add a summary section describing the new routing flow, between the existing "Constitution Promotion (Manual)" section and "Managing Learnings (Update/Archive/Delete)" section.

## Design Decisions

### D1: Detection

Identify which skills, agents, or commands were invoked in this session by examining conversation history. No parsing engine -- the LLM reads its own context.

### D2: Multiple targets

If multiple components were active, present a numbered list ordered by relevance to the learning content. User picks one or skips.

### D3: Section identification

Read the target definition file. Insert the bullet in the most relevant existing section. If no section with bullets exists, skip routing for this target with a warning.

### D4: Versioning

Compound edits definition files but does NOT commit or version-bump. The edits are staged changes picked up by the normal workflow completion protocol (`/ship` handles versioning).

## Acceptance Criteria

- [ ] After capturing a learning, compound detects which skill/agent/command was active and proposes a one-line bullet edit
- [ ] User can Accept, Skip, or Edit the proposed edit
- [ ] Routing skips gracefully when `plugins/soleur/` directory does not exist
- [ ] Routing skips gracefully when no skill/agent/command was detected in session
- [ ] Routing skips with a warning when the target definition has no suitable section for bullets

## Test Scenarios

- Given a session where `/soleur:brainstorm` was invoked and a learning about brainstorm behavior is captured, when compound runs, then it proposes an edit to `skills/brainstorming/SKILL.md`
- Given a session where multiple skills were invoked, when compound runs, then it presents a selection list ordered by relevance
- Given a session with no skill/agent invocations, when compound runs, then it skips routing with no error
- Given the user selects Edit on a proposed bullet, when they modify the text, then the modified text is written to the definition

## Implementation Phases

### Phase 1: Update compound-docs SKILL.md

**File:** `plugins/soleur/skills/compound-docs/SKILL.md`

Insert a new Step 8 inside `<critical_sequence>`, between Step 7's `</step>` tag and the `</critical_sequence>` closing tag. The new step must be INSIDE the critical sequence.

Also rename the section heading from "7-Step Process" to remove the hardcoded number (e.g., "Documentation Capture Process") to avoid stale headings when steps are added in the future.

**Step 8: Route Learning to Definition**

```markdown
<step number="8">
## Step 8: Route Learning to Definition

After capturing and cross-referencing the learning, route the insight to the skill, agent, or command definition that needs it.

### 8.1 Detect Active Components

Identify which skills, agents, or commands were invoked in this session by examining the conversation history.

If no components detected, skip this step.

If `plugins/soleur/` directory does not exist, skip this step.

### 8.2 Select Target

If one component detected: propose it as the routing target.

If multiple detected: use **AskUserQuestion** to present a numbered list ordered by relevance to the learning. Include an option to skip.

Map component names to file paths:
- Skill `foo` -> `plugins/soleur/skills/foo/SKILL.md`
- Agent `soleur:engineering:review:baz` -> `plugins/soleur/agents/engineering/review/baz.md`
- Command `soleur:bar` -> `plugins/soleur/commands/soleur/bar.md`

If the target file does not exist at the expected path, warn and skip.

### 8.3 Propose Edit

1. Read the target definition file
2. Find the most relevant existing section for a new bullet (do not create new sections)
3. If no section with bullets exists, warn and skip this target
4. Draft a one-line bullet capturing the sharp edge -- non-obvious gotcha only, skip if the insight is general knowledge the model already knows
5. Display the proposed edit showing the section name, existing bullets, and the new bullet

### 8.4 Confirm

Use **AskUserQuestion** with options:
- **Accept** -- Apply the edit to the definition file
- **Skip** -- Do not modify the definition
- **Edit** -- Modify the bullet text, then confirm

If accepted, write the edit to the file. Do NOT commit or version-bump -- the edit is staged for the normal workflow completion protocol.
</step>
```

### Phase 2: Update compound.md command

**File:** `plugins/soleur/commands/soleur/compound.md`

Add a new section between "Constitution Promotion (Manual)" and "Managing Learnings (Update/Archive/Delete)":

```markdown
### Route Learning to Definition

After constitution promotion, compound routes the captured learning to the skill, agent, or command definition that was active in the session. This step:

1. Detects which components were invoked in the conversation
2. Proposes a one-line bullet edit to the relevant definition file
3. User confirms with Accept/Skip/Edit

See compound-docs Step 8 for the full flow.

Skips if `plugins/soleur/` does not exist or no components detected.
```

### Phase 3: Version bump and documentation

- MINOR bump (new capability in existing skill/command)
- Update `plugin.json`, `CHANGELOG.md`, `README.md`
- No new skills/agents/commands created -- just enhanced existing ones

## Non-Goals

- Fully automatic edits without user confirmation
- Constitution cross-check (deferred -- tracked in separate issue)
- Sync broad-scan of learnings against definitions (deferred -- tracked in separate issue)
- Replacing the constitution (project-wide rules stay there)
- Restructuring skill/agent definition formats
- Building a detection engine or metadata system

## Rollback Plan

`git revert` the commit containing the SKILL.md and compound.md changes. No data migration, no schema changes, no external dependencies.

## Affected Teams

Solo developer. No external teams affected. The change modifies the compound workflow that only runs interactively with user confirmation at every step.

## Dependencies and Risks

**Dependencies:** None. All changes are to prompt instruction files.

**Risks:**
- Detection quality: The LLM might not reliably identify which skill was active. Mitigation: the user confirms the target, so misdetection is correctable.
- Instruction bloat: Over time, definitions accumulate bullets. Mitigation: "sharp edges only" principle + user confirmation gate. A warning threshold can be added in v2 if definitions get crowded.

## Future Work

- Constitution cross-check: After routing a learning, check if the constitution has a redundant rule and propose migration. Tracked separately.
- Sync definitions: `/soleur:sync definitions` scans all accumulated learnings against all definitions for batch routing. Tracked separately.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-17-compound-skill-updates-brainstorm.md`
- Spec: `knowledge-base/specs/feat-compound-skill-updates/spec.md`
- Learning: `knowledge-base/learnings/agent-prompt-sharp-edges-only.md` (sharp edges principle)
- Learning: `knowledge-base/learnings/2026-02-12-review-compound-before-commit-workflow.md` (compound placement in workflow)
