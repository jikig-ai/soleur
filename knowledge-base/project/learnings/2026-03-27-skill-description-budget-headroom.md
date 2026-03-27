---
module: plugins/soleur/skills
date: 2026-03-27
problem_type: best_practice
tags: [skill-creation, token-budget, description]
severity: medium
---

# Learning: Check Skill Description Budget Headroom Before Writing

## Problem

When adding a new skill (`architecture`), the initial description (22 words) pushed the cumulative skill description word count to 1808, exceeding the 1800-word budget. Required 3 iterative trims before tests passed, wasting time on trial-and-error.

## Solution

Before writing a new skill's description, check current headroom:

```bash
# Count current cumulative words
bun test plugins/soleur/test/components.test.ts 2>&1 | grep -E 'Budget|pass'
```

Then allocate the new description within the remaining budget. In this case, headroom was only ~2 words before adding the new skill — the budget was already at 1798/1800 from 60 existing skills.

## Key Insight

The skill description word budget (1800 words across all skills) is nearly exhausted. Every new skill addition requires trimming existing descriptions or keeping new descriptions extremely tight (~14 words). Check the budget BEFORE writing the description, not after. The plan skill should include a budget check as a pre-implementation step when plans involve new skills.

## Session Errors

1. **Markdown lint failure** — Plan file missing blank lines around lists. Recovery: added blank lines. **Prevention:** Already enforced by pre-commit markdown-lint hook.
2. **Skill description budget exceeded (1808/1800)** — Required 3 trim iterations. Recovery: shortened to 14 words. **Prevention:** Check budget headroom before writing description (this learning).
3. **Plan prescribed wrong paths (3 instances)** — Wrong `docs/_data/skills.js` path, nonexistent `plugin.json` skills array, contradictory template locations. Recovery: caught by Kieran reviewer before implementation. **Prevention:** Already covered by AGENTS.md rule and plan-review gate.
4. **Root README skill count stale (59 vs actual 61)** — Recovery: updated to 61. **Prevention:** Grep for old count across repo before updating (already documented in skill-count-propagation-locations learning).
