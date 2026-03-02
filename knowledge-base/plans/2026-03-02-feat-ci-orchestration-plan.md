---
title: "feat: Multi-agent CI orchestration"
type: feat
date: 2026-03-02
---

# feat: Multi-agent CI orchestration

## Overview

Extend the `competitive-intelligence` agent to cascade updates to 4 downstream specialist agents after producing its base CI report. Specialists update existing repo files with fresh competitive data. The CI agent appends a consolidated `## Cascade Results` section summarizing what changed.

Issue: #333
Brainstorm: `knowledge-base/brainstorms/2026-03-02-ci-orchestration-brainstorm.md`
Spec: `knowledge-base/specs/feat-ci-orchestration/spec.md`
Branch: `feat-ci-orchestration`

## Non-Goals

- Normalized data contract between CI agent and specialists (deferred; YAGNI)
- Smart detection of which specialists need to run (always-run for v1)
- Cross-specialist consistency auditing
- Interactive cascade mode or per-specialist selection
- New agents or skills (orchestration added to existing CI agent body)
- Delegating through CMO/CRO domain leaders (v2 if specialist count grows)

See also: `knowledge-base/specs/feat-ci-orchestration/spec.md` Non-Goals section.

## Problem Statement / Motivation

The CI report is a standalone artifact. Downstream documents -- battlecards, pricing analysis, content strategy, comparison pages -- go stale when the competitive landscape changes. Manual invocation of each specialist is tedious and easy to forget.

## Proposed Solution

Add a **Phase 2: Cascade** section to `competitive-intelligence.md` that spawns 4 specialist agents in parallel via Task tool after writing the base report. Each specialist reads the CI report from disk, updates its domain artifacts, and returns a summary. The CI agent collects results and appends a `## Cascade Results` section.

### Cascade Delegation Table

| Agent | Scoped Task | Files Updated | Domain |
|-------|-------------|---------------|--------|
| growth-strategist | Content gap analysis against updated competitor list | Existing content strategy docs in knowledge-base | Marketing |
| pricing-strategist | Refresh competitive pricing matrix | Pricing analysis docs in knowledge-base | Marketing |
| deal-architect | Update/create competitive battlecards | Battlecard docs in knowledge-base | Sales |
| programmatic-seo-specialist | Flag comparison pages needing regeneration | Comparison page tracking docs | Marketing |

### Cascade Results Format

Appended to `competitive-intelligence.md`:

```markdown
## Cascade Results

_Generated: YYYY-MM-DD_

| Specialist | Status | Files Modified | Summary |
|------------|--------|---------------|---------|
| growth-strategist | success | `path/to/file.md` | Updated content gap analysis for 3 new competitors |
| pricing-strategist | success | `path/to/file.md` | Refreshed pricing matrix with tier 0 changes |
| deal-architect | failed | -- | Error: no brand-guide.md found |
| programmatic-seo-specialist | success | `path/to/file.md` | Flagged 5 comparison pages for regeneration |

### Failures

- **deal-architect**: [error details]
```

### Specialist Return Contract

Each specialist must return results using these structured headings (per constitution line 164):

```markdown
## Session Summary
Files modified: [list of file paths]
Summary: [one-line description of what changed]

### Errors
[Any errors encountered, or "None"]
```

## Affected Teams

- **Product** — owns the competitive-intelligence agent being modified
- **Marketing** — 3 specialist agents (growth-strategist, pricing-strategist, programmatic-seo-specialist) spawned cross-domain
- **Sales** — 1 specialist agent (deal-architect) spawned cross-domain

## Technical Considerations

### CI/Scheduled Workflow

The scheduled workflow (`scheduled-competitive-analysis.yml`) runs the cascade in GitHub Actions:
- Report written to ephemeral filesystem (runner is writable, just not pushed)
- Specialists run and update ephemeral files
- Cascade Results included in the GitHub Issue body alongside base report
- Increase `timeout-minutes: 30` to `45` and `--max-turns 30` to `45`

### Fan-Out Pattern

Follows established pattern from `work-subagent-fanout.md`:
- Max 4 parallel agents (within 5-agent limit)
- Lead-coordinated commits (subagents do NOT commit)
- Failed specialists logged in Cascade Results

### CI Report Heading Contract

Specialists consume the CI report by heading name (per constitution line 139). The relevant headings from the CI agent's existing output contract:

- `## Executive Summary` — high-level landscape overview
- `## Tier N: <name>` — per-tier competitor analysis with overlap matrices
- `## Recommendations` — strategic recommendations

Specialists should parse by heading name, not position.

The cascade triggers automatically via the agent body; no workflow `prompt:` field change is required.

## Acceptance Criteria

- [ ] CI agent Phase 2 spawns 4 specialist agents in parallel after base report
- [ ] Each specialist reads CI report from disk and updates its domain files
- [ ] Each specialist runs independently (one failing does not block others)
- [ ] `## Cascade Results` section appended to `competitive-intelligence.md`
- [ ] Cascade Results shows per-specialist status, files modified, and summaries
- [ ] Failed specialists are reported with error details
- [ ] Cascade runs in GitHub Actions scheduled workflow with increased timeout
- [ ] Verified all 4 specialist agents run to completion when invoked via Task tool with autonomous-mode instruction (pre-implementation gate)
- [ ] Specialist return contract uses structured headings (`## Session Summary`, `### Errors`)

## Test Scenarios

- Given a fresh CI report, when cascade runs, then all 4 specialists complete and Cascade Results section appears
- Given one specialist fails (e.g., missing prerequisite file), when cascade runs, then the other 3 complete successfully and the failure is logged in Cascade Results
- Given a CI report with an existing Cascade Results section, when cascade re-runs, then the old section is replaced (not duplicated)
- Given a read-only CI environment (GitHub Actions), when cascade runs, then results are included in the Issue body
- Given all 4 specialists fail, when cascade completes, then Cascade Results section shows all 4 as failed with error details
- Given Phase 1 fails to write the CI report file, when Phase 2 starts, then cascade is skipped entirely with a logged reason
- Given a specialist hangs or exceeds turn budget, when other specialists complete, then the hanging specialist is reported as failed and does not block Cascade Results

## Dependencies and Risks

- **Prerequisite met:** #330 (base competitive-intelligence agent) is CLOSED
- **Specialist readiness risk (Medium):** Downstream agents may not handle autonomous CI-triggered invocation gracefully. Task prompts must explicitly disable interactive patterns.
- **Cross-domain coupling risk (High for future, Low for v1):** Product agent spawning Marketing/Sales agents bypasses domain leaders. Acceptable for v1 with explicit documentation.
- **Token budget risk (Low):** 4 isolated Task agents, each with its own context window. Within max-5 limit.
- **Timeout risk (Medium):** Scheduled workflow needs increased limits. Full cascade with WebSearch may exceed 30 turns.

## Rollback Plan

1. Revert Phase 2: Cascade section from `competitive-intelligence.md` (single section removal)
2. Revert `timeout-minutes` and `max-turns` in `scheduled-competitive-analysis.yml` back to 30
3. Revert version bump files

All changes are additive to existing files. Rollback is a clean revert with no data migration.

## References and Research

### Internal References

- Agent: `plugins/soleur/agents/product/competitive-intelligence.md`
- Skill: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Fan-out: `plugins/soleur/skills/work/references/work-subagent-fanout.md`
- Workflow: `.github/workflows/scheduled-competitive-analysis.yml`
- CMO delegation pattern: `plugins/soleur/agents/marketing/cmo.md:40-54`

### Institutional Learnings Applied

- `parallel-agents-on-main-cause-conflicts.md` -- enforce non-overlapping file sets
- `parallel-subagent-fan-out-in-work-command.md` -- lead-coordinated commits, max 5
- `parallel-subagent-css-class-mismatch.md` -- deferred normalization (YAGNI v1)
- `workshop-agents-as-subagents-require-relay.md` -- autonomous mode in Task prompts
- `skill-cannot-invoke-skill.md` -- orchestration in agent body, not skill

## MVP

### `plugins/soleur/agents/product/competitive-intelligence.md` (Phase 2 addition)

```markdown
## Phase 2: Cascade Updates

If the base CI report was not written to disk (Phase 1 fallback to code block),
skip this phase entirely and log: "Cascade skipped: CI report not written to disk."

After writing the base CI report, spawn downstream specialist agents to refresh
their artifacts with the latest competitive data.

**Cross-domain note:** This phase spawns agents from Marketing and Sales domains.
This is intentional for speed and directness.
CASCADE LIMIT: 4 specialists maximum. If adding more, refactor to delegate
through domain leaders (CMO/CRO). See issue #333 for rationale.

### Cascade Delegation Table

| Agent | Task | Scope |
|-------|------|-------|
| growth-strategist | Content gap analysis against updated competitors | Read CI report, update content strategy gaps |
| pricing-strategist | Competitive pricing matrix refresh | Read CI report, update pricing comparison |
| deal-architect | Competitive battlecard update | Read CI report, update/create battlecards |
| programmatic-seo-specialist | Comparison page regeneration flags | Read CI report, flag stale comparison pages |

Spawn all 4 in parallel using a single message with multiple Task tool calls.

Each Task prompt must include:
- Path to the CI report (`knowledge-base/overview/competitive-intelligence.md`)
- Scoped task description (only the narrow cascade responsibility)
- Instruction to run autonomously (no AskUserQuestion)
- Instruction not to commit
- Return contract: respond using `## Session Summary` (files modified, summary)
  and `### Errors` (any issues, or "None") headings

### Failure Handling

- Collect results from all 4 specialists
- If any failed: log the failure with error details
- Do not retry automatically -- report failures in Cascade Results

### Cascade Results

After all specialists complete, append a `## Cascade Results` section to the
CI report.

Format: date, per-specialist status table (agent, status, files modified, summary),
and a Failures subsection for any that failed.
```

### `.github/workflows/scheduled-competitive-analysis.yml` (timeout increase)

```yaml
timeout-minutes: 45
# ...
claude_args: '--model claude-opus-4-6 --max-turns 45 --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch'
```

## Version Bump

**Intent:** PATCH (no new agents, no new skills -- modifying existing agent body and workflow config)

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/agents/product/competitive-intelligence.md` | Add Phase 2: Cascade section to agent body |
| `.github/workflows/scheduled-competitive-analysis.yml` | Increase timeout-minutes and max-turns |
| `.claude-plugin/plugin.json` | Version bump (PATCH) |
| `CHANGELOG.md` | Document cascade feature |
| `plugins/soleur/README.md` | Verify counts (no new components) |
| Root `README.md` | Sync version badge |
| `.claude-plugin/marketplace.json` | Version sync |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Sync version placeholder |
