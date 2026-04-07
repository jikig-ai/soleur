---
title: "Fix compound rule budget false alarm by distinguishing always-loaded vs on-demand rules"
date: 2026-04-07
category: logic-errors
tags: [compound, rule-budget, AGENTS.md, constitution.md, context-management]
module: compound
---

# Learning: Rule Budget False Alarm — Always-Loaded vs On-Demand Rules

## Problem

The compound skill's Phase 1.5 step 8 (rule budget count) was counting BOTH `AGENTS.md` and `constitution.md` as "always-loaded rules" with a combined budget of 250. At 316 rules (252 constitution + 64 AGENTS.md), the warning fired on every session: "Rule budget exceeded (316/250)."

However, only `AGENTS.md` is always-loaded (via `CLAUDE.md @AGENTS.md`). Constitution.md is loaded on-demand by skills when needed — it is NOT included via `@` directive and the AGENTS.md header itself says "read it when needed."

## Root Cause

The original rule budget check (introduced in the feat-rule-retirement PR, 2026-03-05) assumed both files were always-loaded. At the time, the combined count was 219 (under 250). As rules grew to 316, the false alarm became persistent.

## Solution

1. **Fixed the budget check** in compound SKILL.md Phase 1.5 step 8:
   - Counts only AGENTS.md as "always-loaded" (budget: 100)
   - Tracks constitution.md separately as "on-demand" (informational, warns at 300)

2. **Trimmed AGENTS.md** from 64 → 58 rules (-9%):
   - Consolidated related rules (5 "exhaust automated options" → 2, 3 Terraform → 2, 2 CC memory → 1, 2 markdown lint → 1)
   - Added `[skill-enforced: ...]` cross-references for rules fully covered by skill instructions
   - Removed verbose `**Why:**` explanations from skill-enforced rules (explanations remain in the skills)

3. **Review feedback applied**: Restored 2 rules that reviewers flagged as incorrectly deleted (Phase 5.5 domain gates stub, retroactive gate application), fixed inaccurate cross-references.

## Key Insight

Before designing a budget check, verify what is actually in the budget. The `@` include directive in CLAUDE.md is the only mechanism that makes a file "always-loaded." A prose instruction to "read it when needed" does NOT make a file always-loaded. Conflating on-demand and always-loaded creates false alarms that desensitize users to real budget warnings.

When trimming rules, consolidate related rules and add `[skill-enforced: ...]` cross-references rather than deleting — this preserves defense-in-depth while reducing context cost.

## Session Errors

1. **Worktree lost to cleanup-merged** — Created worktree, but `cleanup-merged` removed it because the remote branch didn't exist yet. **Prevention:** The worktree-manager creates a local branch but doesn't push; `cleanup-merged` checks remote tracking. This is expected behavior for brand-new branches — recreating is the correct recovery.

2. **Initial rule count mismatch (237 vs 252)** — First `grep -c` ran on a stale commit; user's session had the current 252. **Prevention:** Always verify counts after fetching latest main into the worktree.

## Tags

category: logic-errors
module: compound
