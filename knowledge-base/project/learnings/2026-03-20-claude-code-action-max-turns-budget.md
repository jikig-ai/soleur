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

## Timeout-to-Turns Ratio (added 2026-04-18)

When raising `--max-turns`, also check that `timeout-minutes / max-turns` stays aligned with peer workflows. Median peer ratio is ~0.75 min/turn; outliers dip to 0.55 (community-monitor) or climb to 1.2 (content-generator with WebSearch). A bumped turn budget with an unchanged timeout is a silent failure mode — the agent runs out of wall clock before using the turns it was given.

Peer reference table (2026-04-18):

| Workflow | timeout | turns | ratio (min/turn) |
|---|---|---|---|
| campaign-calendar | 15 | 20 | 0.75 |
| follow-through | 15 | 30 | 0.50 |
| community-monitor | 30 | 50 | 0.60 |
| bug-fixer | 45 | 55 | 0.82 |
| ship-merge | 30 | 40 | 0.75 |
| roadmap-review | 30 | 40 | 0.75 |
| seo-aeo-audit | 30 | 40 | 0.75 |
| growth-execution | 30 | 40 | 0.75 |
| competitive-analysis | 45 | 45 | 1.00 |
| content-generator | 60 | 50 | 1.20 |
| ux-audit | 45 | 60 | 0.75 |
| growth-audit | 75 | 70 | 1.07 |
| daily-triage | 60 | 80 | 0.75 |

**Rule:** when editing `claude_args --max-turns`, also edit `timeout-minutes` to keep the ratio ≥ 0.75 min/turn unless the workflow is data-collection-only (no test execution, no WebSearch). Below 0.75 is only safe for tasks where each turn is a sub-minute API call (follow-through at 0.50 is an outlier because every turn is a `gh pr view`).

**Review catch:** In PR #2536, the initial commit raised max-turns 35 → 55 but left `timeout-minutes: 30` (0.55 ratio, below the median). The git-history-analyzer review agent surfaced this; the follow-up commit bumped timeout to 45 (0.82 ratio).

## Tags

category: ci-workflows
module: github-actions
