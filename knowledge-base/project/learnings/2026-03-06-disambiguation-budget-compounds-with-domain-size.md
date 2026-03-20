---
title: "Disambiguation budget compounds with domain size"
date: 2026-03-06
category: integration-issues
tags:
  - agents
  - token-budget
  - disambiguation
  - marketing
module: plugins/soleur/agents
synced_to: knowledge-base/project/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md
---

# Learning: Disambiguation budget compounds with domain size

## Problem

When adding a fact-checker agent to the marketing domain (11 specialists), the constitution requires updating ALL sibling descriptions with disambiguation sentences. Each disambiguation addition consumes ~5 words from the global 2,500-word agent description budget. Adding disambiguation to 2 siblings (copywriter, growth-strategist) consumed 10 words, and the fact-checker's own description needed 34 words. After the addition, the budget stood at 2,498/2,500 -- effectively full.

The word count exceeded the 2,500 limit twice during implementation, requiring iterative trimming of the fact-checker description (removing "via WebFetch", "content" from "content drafts", "writing" and "generating" from disambiguation sentences).

## Solution

Budget-aware disambiguation when adding agents to large domains:

1. Check the budget BEFORE writing the new agent description: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w`
2. Count how many siblings need disambiguation (usually 1-3 with overlapping scope, not all N)
3. Reserve ~5 words per sibling disambiguation in the new agent's word allocation
4. Use minimal disambiguation phrasing: `use <agent> for <scope>;` (5 words) not `use <agent> for <detailed scope description>;`

## Key Insight

The agent description word budget is a shared resource that grows sublinearly with agent count but disambiguation requirements grow linearly with domain size. Marketing (11 specialists) is the largest domain and is now at the budget ceiling. The next agent addition to ANY domain will require either trimming existing descriptions or raising the budget limit. Plan for this during the brainstorm/plan phase, not during implementation.

## Tags
category: integration-issues
module: plugins/soleur/agents
