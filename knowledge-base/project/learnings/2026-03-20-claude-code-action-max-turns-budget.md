# Learning: claude-code-action max-turns budget for Soleur plugin workflows

## Problem

The `scheduled-community-monitor.yml` workflow failed with `error_max_turns` after exhausting its 30-turn limit. The agent needed to:

- Read plugin files (AGENTS.md, constitution, brand guide) — ~5 turns overhead
- Detect platforms (1 turn)
- Collect data from 5 platforms (Discord, X, GitHub, HN, LinkedIn) — ~10 turns
- Write digest file (1 turn)
- Persist via PR (branch, commit, push, status checks, PR create, auto-merge) — ~5 turns
- Create GitHub Issue (1 turn)

Total: ~23+ turns, exceeding the 30-turn budget.

## Solution

1. Increased `--max-turns` from 30 to 50 to provide adequate headroom
2. Restructured the prompt to instruct batching data collection commands with `;` separators, reducing the number of tool calls needed for data collection from ~10 to ~3

## Key Insight

When setting `--max-turns` for `claude-code-action` workflows that load the Soleur plugin (`plugins: 'soleur@soleur'`), account for ~10 turns of plugin overhead (reading AGENTS.md, constitution.md, brand guide, and other project files) on top of the actual task turns. The formula:

**Required turns = plugin overhead (~10) + task tool calls + error/retry buffer (~5)**

Current workflow turn budgets for reference:

- Bug fixer: 55 (increased from 35 on 2026-04-18 after run 24599250091 hit max_turns on a test-heavy issue; 25 → 35 → 55)
- Community monitor: 50 (fixed from 30)
- Ship/merge: 40
- Competitive analysis: 45
- Daily triage: 80

Batching shell commands with `;` (not `&&` — failures shouldn't halt the batch) is the most effective way to reduce turn consumption for data-collection-heavy workflows.

## Tags

category: ci-workflows
module: github-actions
