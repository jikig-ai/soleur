# Spec: Self-Healing Workflow with Session-Level Learning Loops

**Issue:** #397
**Branch:** feat-self-healing-workflow
**Status:** Draft

## Problem Statement

Workflow deviations are detected and corrected manually through the compound skill's learning capture pipeline. While effective, this requires human intervention at every promotion step (learning -> constitution rule -> hook). Cross-session pattern analysis doesn't exist — each session operates in isolation with no mechanism to identify recurring deviations across the corpus of 80+ learnings.

## Goals

- G1: Automate deviation detection within sessions by scanning actions against AGENTS.md and constitution.md rules
- G2: Automate cross-session pattern analysis by periodically scanning the learnings corpus for recurring issues
- G3: Propose enforcement mechanisms following the hooks-first hierarchy (hooks > skill instructions > prose rules)
- G4: Implement rule retirement to prevent unbounded growth of prose rules
- G5: Keep humans in the loop at the PR review stage, not the proposal stage

## Non-Goals

- N1: Accessing Claude Code session transcripts (not available via API/hooks)
- N2: Replacing the existing compound skill's manual promotion flow
- N3: Auto-merging proposed rule changes without human review
- N4: Real-time monitoring or alerting (out of scope for v1)

## Functional Requirements

- FR1: Add a "Deviation Analyst" subagent to compound's parallel fan-out (Phase 1) that compares session actions against AGENTS.md hard rules and constitution.md principles
- FR2: For each detected deviation, the subagent outputs a structured report: rule violated, evidence, proposed enforcement (hook or prose rule)
- FR3: Hook proposals include a draft `.claude/hooks/` script or `lefthook.yml` entry
- FR4: Create a `self-healing-sweep.yml` GitHub Actions workflow that runs weekly on cron
- FR5: The CI sweep reads all files in `knowledge-base/learnings/` and identifies patterns where 3+ learnings share the same root cause or component
- FR6: The CI sweep generates auto-PRs containing: proposed hooks, constitution.md additions, and rule retirement candidates
- FR7: Rule retirement triggers on two conditions: (a) a PreToolUse hook now enforces what a prose rule described, (b) zero related violations found across 20+ sessions of learnings
- FR8: The CI sweep checks for contradictory or near-duplicate rules in constitution.md and AGENTS.md

## Technical Requirements

- TR1: Deviation Analyst subagent runs in compound's existing parallel fan-out alongside the 6 existing subagents
- TR2: CI sweep uses `claude-code-action` with appropriate tool permissions (Bash, Read, Write, Edit, Glob, Grep)
- TR3: CI sweep workflow requires `id-token: write` permission per constitution.md CI constraints
- TR4: Auto-PRs must include clear labels (`self-healing`, `auto-generated`) for filtering
- TR5: Deviation reports use structured YAML format compatible with the existing learnings schema (problem_type, component, severity)
- TR6: The CI sweep must be idempotent — running twice with no new learnings produces no new PRs

## Components

| Component | Type | Path |
|-----------|------|------|
| Deviation Analyst | Subagent (compound) | `plugins/soleur/skills/compound/` (SKILL.md update) |
| Self-Healing Sweep | GitHub Actions workflow | `.github/workflows/self-healing-sweep.yml` |
| Hook proposal template | Asset | `plugins/soleur/skills/compound/assets/hook-proposal-template.sh` |
| Violation tracking | Schema extension | `plugins/soleur/skills/compound-capture/schema.yaml` (add deviation fields) |

## Success Criteria

- SC1: Compound's deviation scanner detects at least 1 known deviation type (e.g., CWD drift, skipped worktree) in a test session
- SC2: Weekly CI sweep generates a valid PR from the existing learnings corpus
- SC3: At least one prose rule is retired after a corresponding hook is merged
- SC4: No rule bloat — AGENTS.md stays under 15 hard rules, constitution.md grows net-zero or shrinks
