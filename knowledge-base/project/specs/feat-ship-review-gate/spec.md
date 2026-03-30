# Spec: Ship Review Gate Enforcement

**Issue:** #1227
**Branch:** feat-ship-review-gate
**Brainstorm:** [2026-03-27-ship-review-gate-brainstorm.md](../../brainstorms/2026-03-27-ship-review-gate-brainstorm.md)

## Problem Statement

The `/ship` skill's review gate only fires when `/ship` is invoked. Agents can bypass all review enforcement by using raw `gh pr create` + `gh pr merge`. This gap caused 4 PRs (#1213, #1214, #1219, #1220) to ship without review, including a TypeScript type error in #1219.

## Goals

- G1: Prevent `gh pr merge` without review evidence via a PreToolUse hook
- G2: Consolidate redundant review checks in the ship skill (Phase 1.5 is the single gate)
- G3: Update AGENTS.md hook awareness

## Non-Goals

- GitHub branch protection rules (enforcement outside Claude Code) — separate future issue
- Pre-push hooks (the merge command is the correct interception point)
- Changes to the review skill itself
- Hotfix escape hatch (YAGNI — dropped after plan review)

## Functional Requirements

- **FR1:** Review evidence check added to `pre-merge-rebase.sh` as early-exit before fetch/merge/push
- **FR2:** Check detects review evidence via todo files tagged `code-review` OR commit message matching review output pattern
- **FR3:** Deny message is clear: "Run /review before merging"
- **FR4:** Ship skill Phase 5.5 Code Review Completion Gate subsection is removed; Phase 1.5 is the single review gate
- **FR5:** AGENTS.md hook awareness line updated to include review evidence gate

## Technical Requirements

- **TR1:** Review evidence detection uses `-C "$WORK_DIR"` consistently for both grep and git log
- **TR2:** Guard is purely local — zero network calls, no PR number extraction needed
- **TR3:** Guard follows existing pre-merge-rebase.sh patterns (deny response format, `.cwd` resolution)
- **TR4:** Phase 5.5 removal preserves other subsections (CMO, COO conditional gates)
