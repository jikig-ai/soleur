# Spec: Self-Healing Workflow — Deviation Analyst (v1)

**Issue:** #397
**Branch:** feat-self-healing-workflow
**Status:** Draft

## Problem Statement

Workflow deviations are detected and corrected manually through the compound skill's learning capture pipeline. While effective, this requires human intervention at every promotion step (learning -> constitution rule -> hook). The project has proven that hooks beat documentation: all 4 existing PreToolUse hooks were added after prose rules failed. This feature closes the gap between "we learned X" and "X is now enforced."

## Goals

- G1: Automate deviation detection within sessions by scanning actions against AGENTS.md hard rules and constitution.md principles
- G2: Propose enforcement mechanisms following the hooks-first hierarchy (hooks > skill instructions > prose rules)
- G3: Keep humans in the loop via compound's existing Constitution Promotion gate (Accept/Skip/Edit)

## Non-Goals

- N1: Accessing Claude Code session transcripts (not available via API/hooks)
- N2: Replacing the existing compound skill's manual promotion flow
- N3: Auto-merging or auto-installing hook proposals without human review
- N4: Cross-session pattern analysis (deferred to v2 — see Future Work)
- N5: Rule retirement automation (deferred to v2)
- N6: Schema extension to compound-capture (existing `workflow_issue` type is sufficient)
- N7: Contradiction detection across constitution.md rules (deferred to dedicated audit)

## Functional Requirements

- FR1: Add a "Deviation Analyst" as sequential Phase 1.5 in compound (after the parallel fan-out, before Constitution Promotion) — sequential to avoid exceeding the max-5 parallel subagent limit (compound already has 6 parallel agents)
- FR2: For each detected deviation, output a structured report: rule violated, evidence, proposed enforcement type (hook/skill_instruction/prose_rule)
- FR3: Hook proposals include an inline draft script following `.claude/hooks/` conventions (shebang, header comment, set -euo pipefail, stdin JSON, jq parsing, deny/allow)
- FR4: Output feeds into compound's existing Constitution Promotion flow (Accept/Skip/Edit gate)
- FR5: Only flag Always/Never rule violations from AGENTS.md (skip Prefer rules to reduce noise)
- FR6: Read session-state.md for pre-compaction deviations (extends existing Phase 0.5 pattern)

## Technical Requirements

- TR1: Deviation Analyst runs as sequential Phase 1.5 (NOT parallel) to respect max-5 subagent limit
- TR2: Uses existing `workflow_issue` problem type and `missing_workflow_step` root cause — no schema changes
- TR3: Hook proposals displayed inline during Constitution Promotion — no staging directory needed

## Components

| Component | Type | Path |
|-----------|------|------|
| Deviation Analyst | Sequential Phase 1.5 (compound) | `plugins/soleur/skills/compound/SKILL.md` (edit) |

## Success Criteria

- SC1: Compound's Deviation Analyst detects at least 1 known deviation type (e.g., CWD drift, skipped worktree) in a test session
- SC2: Detected deviations appear in Constitution Promotion with proposed enforcement
- SC3: Hook proposals are well-formed (valid bash, follows `.claude/hooks/` conventions)

## Future Work (v2+)

- **Layer 2: Weekly CI Sweep** — cross-session pattern analysis, auto-PRs, idempotency
- **Rule retirement** — hook supersession detection, zero-violation decay
- **Schema extension** — `workflow_deviation` problem type if v1 reveals `workflow_issue` is insufficient
- **Proposals staging** — `knowledge-base/proposals/hooks/` directory if inline display proves insufficient
- **Contradiction detection** — scanning constitution.md for conflicting rules
