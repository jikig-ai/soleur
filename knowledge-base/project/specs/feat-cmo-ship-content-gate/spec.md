# CMO Ship Content Gate Improvement

**Issue:** #1265
**Branch:** cmo-ship-content-gate
**Brainstorm:** [2026-03-29-cmo-ship-content-gate-brainstorm.md](../../brainstorms/2026-03-29-cmo-ship-content-gate-brainstorm.md)

## Problem Statement

The `/ship` skill's Phase 5.5 CMO Content-Opportunity Gate uses file-path-only trigger conditions that miss user-facing product features delivered as code (e.g., PWA support in PR #1256). Additionally, when brainstorm is skipped and `/plan` runs directly, no domain assessment occurs, leaving the CMO unconsulted at both entry points.

## Goals

- Ensure the CMO evaluates every content-worthy feature at ship time using LLM semantic assessment
- Provide defense-in-depth domain assessment in `/plan` when brainstorm is skipped
- Produce immediate content artifacts (content brief + content-strategy.md update) rather than deferred queues

## Non-Goals

- Changing CMO agent behavior or marketing skill capabilities (these work correctly)
- Adding domain assessment to every workflow (brainstorm already handles this)
- Creating a separate content queue or tracking mechanism (immediate output preferred)

## Functional Requirements

- **FR1**: Phase 5.5 fires CMO gate when PR has `semver:minor`/`major` label, `feat:` title pattern, or closes a milestone issue — in addition to existing file-path triggers
- **FR2**: When structural signals are present, spawn CMO agent with PR context for LLM semantic evaluation of content-worthiness
- **FR3**: CMO gate produces content brief and updates `content-strategy.md` immediately when content opportunity is identified
- **FR4**: "Skip for code-only PRs" exclusion is replaced with "Skip for `semver:patch` PRs with `fix:` titles that do not close a milestone issue and have no file-path triggers"
- **FR5**: `/plan` skill runs Phase 0.5 domain assessment (CPO + CMO minimum) when no preceding brainstorm document is found

## Technical Requirements

- **TR1**: Changes are SKILL.md edits only (ship and plan skills) — no code changes
- **TR2**: Structural signal detection uses `gh pr view --json labels,title,closingIssuesReferences`
- **TR3**: Plan skill detects missing brainstorm by checking `knowledge-base/project/brainstorms/` for matching documents
- **TR4**: AGENTS.md Phase 5.5 description updated to reflect new trigger conditions
