---
title: "feat: self-healing workflow — Deviation Analyst (v1)"
type: feat
date: 2026-03-03
semver: minor
---

# feat: self-healing workflow — Deviation Analyst (v1)

## Overview

Add a Deviation Analyst step to compound's pipeline that detects workflow deviations against AGENTS.md hard rules and proposes enforcement upgrades (hooks > prose rules). This is a single-file change to `compound/SKILL.md`.

## Problem Statement / Motivation

61 friction events show Claude sometimes deviates from established patterns. The existing compound skill captures learnings manually, but promotion from learning to enforcement is human-gated and ad-hoc. The project has proven that hooks beat documentation: all 4 existing PreToolUse hooks were added after prose rules failed. This feature closes the gap between "we learned X" and "X is now enforced."

## Proposed Solution

Add a sequential Phase 1.5 step to compound (after the parallel fan-out, before Constitution Promotion). Running sequentially avoids exceeding the max-5 parallel subagent limit from constitution.md line 143 — compound already has 6 parallel agents.

The Deviation Analyst:

1. Reads AGENTS.md hard rules (Always/Never only — skip Prefer rules) and constitution.md principles from context
2. Uses session-state.md for pre-compaction error forwarding (extends the existing pattern from compound Phase 0.5) to catch early-session deviations lost to context compaction
3. For each deviation, proposes enforcement following the hierarchy: PreToolUse hook (preferred) > skill instruction > prose rule
4. Outputs a structured deviation report that feeds into compound's existing Constitution Promotion flow (Accept/Skip/Edit)
5. Hook proposals are shown inline in Constitution Promotion — the user can Accept (copy to `.claude/hooks/` manually after testing), Skip, or Edit

**File modified:**

- `plugins/soleur/skills/compound/SKILL.md` — add Phase 1.5 "Deviation Analyst" (~30-50 lines)

**No schema changes.** The existing `workflow_issue` problem type and `missing_workflow_step` root cause in compound-capture already cover deviation tracking. No new fields needed.

**No proposals directory.** Hook proposals are shown inline during Constitution Promotion, not staged to disk. Simpler and matches the existing Accept/Skip/Edit flow.

## Technical Considerations

### Context Compaction

The Deviation Analyst runs after context may have been compacted. Strategy:

- Use the existing `session-state.md` error forwarding pattern (compound Phase 0.5 already reads this)
- Analyst reads both: (a) session-state.md for pre-compaction deviations, (b) current context for post-compaction actions

### Hook Proposal Safety

Hook proposals are presented inline during Constitution Promotion — never auto-installed.

- A buggy hook that exits non-zero on all inputs blocks all tool calls
- The user must manually copy accepted proposals to `.claude/hooks/` after testing
- This matches "design for v2, implement for v1" (constitution.md line 146)

### Enforcement Hierarchy

The analyst proposes the strongest viable enforcement for each deviation:

1. **PreToolUse hook** (preferred) — mechanical prevention, can't be bypassed
2. **Skill instruction** — checked when skill runs, but can be overridden
3. **Prose rule** (last resort) — requires agent compliance, weakest enforcement

## Acceptance Criteria

- [x] New "Deviation Analyst" defined in `compound/SKILL.md` as sequential Phase 1.5 (after parallel fan-out, before Constitution Promotion)
- [x] Analyst reads AGENTS.md hard rules and constitution.md principles
- [x] Analyst reads session-state.md for pre-compaction deviations
- [x] Only flags Always/Never violations (not Prefer rules)
- [x] For each deviation, outputs: rule violated, evidence, proposed enforcement type
- [x] Hook proposals shown inline (draft script) during Constitution Promotion (Accept/Skip/Edit)
- [x] No schema changes to compound-capture
- [x] No new directories or files beyond the SKILL.md edit

## Test Scenarios

- Given a session where the agent edits files without creating a worktree, when compound runs with the Deviation Analyst, then the report includes a deviation for "never edit files in main repo when worktree should be active" with a proposed hook
- Given a session with no deviations, when compound runs, then the Deviation Analyst produces an empty report and Constitution Promotion skips the deviation section
- Given a deviation that already has a hook enforcing it (e.g., commits on main), when the Deviation Analyst runs, then it notes the existing hook and does NOT propose a duplicate

## Dependencies and Risks

**Dependencies:**

- Existing compound skill must not change its parallel fan-out structure
- session-state.md must be writable by earlier pipeline phases

**Risks:**

- **False positives:** Mitigated by user gate (Accept/Skip/Edit) — bad proposals get skipped
- **Context budget:** Analyst reads AGENTS.md + constitution.md — adds ~3k tokens. Acceptable since it runs once per compound invocation.
- **Scope creep:** v1 is deliberately minimal. Resist adding schema fields, staging directories, or automation until the basic loop proves useful.

## Future Work (v2+)

The following were explored during brainstorming and deferred:

- **Layer 2: Weekly CI Sweep** — cross-session pattern analysis over the learnings corpus, auto-PRs with hook proposals and rule retirement candidates. Deferred because: no proven need yet (Layer 1 must demonstrate value first), significant complexity (idempotency, GITHUB_TOKEN cascade, learnings schema inconsistency where ~94.5% lack structured frontmatter).
- **Rule retirement automation** — detecting prose rules superseded by hooks (trigger A) and zero-violation decay (trigger B). Deferred because: manual retirement is sufficient at current scale (3 hooks, 194 rules), trigger B requires session counting infrastructure that doesn't exist.
- **Schema extension** — `workflow_deviation` problem type and `deviation_rule_source` field. Deferred because: existing `workflow_issue` type covers the use case, adding fields for one consumer violates YAGNI.
- **Proposals staging directory** — `knowledge-base/proposals/hooks/` with README. Deferred because: inline display during Constitution Promotion is simpler and sufficient.
- **Contradiction detection (FR8)** — scanning constitution.md for conflicting rules. Deferred to a dedicated audit task.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-03-self-healing-workflow-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-self-healing-workflow/spec.md`
- Compound skill: `plugins/soleur/skills/compound/SKILL.md`
- Compound-capture schema: `plugins/soleur/skills/compound-capture/schema.yaml`
- Hook examples: `.claude/hooks/guardrails.sh`, `.claude/hooks/worktree-write-guard.sh`
- Constitution: `knowledge-base/overview/constitution.md` (lines 113, 143, 146, 148, 192)
- Issue: #397
- PR: #416 (draft)
