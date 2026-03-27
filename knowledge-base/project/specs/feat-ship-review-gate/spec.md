# Spec: Ship Review Gate Enforcement

**Issue:** #1227
**Branch:** feat-ship-review-gate
**Brainstorm:** [2026-03-27-ship-review-gate-brainstorm.md](../../brainstorms/2026-03-27-ship-review-gate-brainstorm.md)

## Problem Statement

The `/ship` skill's review gate only fires when `/ship` is invoked. Agents can bypass all review enforcement by using raw `gh pr create` + `gh pr merge`. This gap caused 4 PRs (#1213, #1214, #1219, #1220) to ship without review, including a TypeScript type error in #1219.

## Goals

- G1: Prevent `gh pr merge` without review evidence via a PreToolUse hook
- G2: Provide an auditable escape hatch for legitimate hotfixes
- G3: Consolidate redundant review checks in the ship skill
- G4: Document a hotfix protocol in AGENTS.md

## Non-Goals

- GitHub branch protection rules (enforcement outside Claude Code) — separate future issue
- Pre-push hooks (the merge command is the correct interception point)
- Changes to the review skill itself

## Functional Requirements

- **FR1:** New guardrails.sh Guard 6 intercepts `gh pr merge` commands
- **FR2:** Guard 6 extracts the PR number, checks for review evidence on the branch (todo files tagged `code-review` OR commit message matching review output pattern)
- **FR3:** Guard 6 checks the PR for a `hotfix` label — if present, merge is allowed without review evidence
- **FR4:** Deny message includes instructions: "Add 'hotfix' label to bypass: `gh pr edit <N> --add-label hotfix`"
- **FR5:** Ship skill Phase 5.5 review check is removed; Phase 1.5 is the single review gate
- **FR6:** AGENTS.md updated with hotfix protocol and Guard 6 documentation

## Technical Requirements

- **TR1:** Review evidence detection logic is centralized (shared between hook and ship skill to prevent drift)
- **TR2:** Hook uses `gh pr view <N> --json labels` to check for hotfix label (requires network, acceptable since `gh pr merge` is infrequent)
- **TR3:** PR number extraction handles both `gh pr merge <N>` and `gh pr merge --squash --auto` (current branch) forms
- **TR4:** Guard 6 follows existing hook patterns in guardrails.sh (deny response format, error handling)
