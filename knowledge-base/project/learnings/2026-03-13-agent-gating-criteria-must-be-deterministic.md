# Learning: Agent gating criteria must be deterministic

## Problem
Step 2b of the community-manager agent instructed it to call fetch-user-timeline for mentions with "ambiguous brand association risk" but provided no concrete criteria. The agent had no deterministic gate for when to make the API call.

## Solution
Replaced the vague instruction with a concrete follower-count threshold: call fetch-user-timeline when author_followers_count < 100. Accounts with 100+ followers skip the check.

## Key Insight
Agent prompt instructions that gate expensive operations (API calls, tool invocations) must use deterministic criteria the agent can evaluate mechanically. Vague qualifiers like "ambiguous" or "unclear" leave the decision to LLM judgment, which leads to either over-calling (wasting resources) or under-calling (missing cases). Convert qualitative gates to quantitative thresholds.

## Related Learnings
- `2026-03-10-guardrails-must-match-observable-data.md` -- complementary: that learning addresses gating on data the agent cannot see; this one addresses gating on data it CAN see but with vague criteria
- `2026-02-13-agent-prompt-sharp-edges-only.md` -- adjacent: both concern agent prompt quality, but that one covers what to include while this one covers how to specify decision criteria

## Tags
category: agent-prompts
module: community-manager
