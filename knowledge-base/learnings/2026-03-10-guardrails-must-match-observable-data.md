# Learning: Guardrails Must Match Observable Data

## Problem
Brand guide guardrails referenced data (profile images, follower counts, account history, thread context) that the community-manager agent does not receive from the fetch-mentions API. The agent reads the guardrails but cannot enforce criteria that exceed its data pipeline.

## Solution
Scope each guardrail criterion to data the agent actually observes (mention text, username, display name). For criteria requiring richer data (account history, profile metadata), add parenthetical notes delegating to the human reviewer: "(full account review is a human reviewer responsibility during the approval step)."

## Key Insight
Policy documents consumed by agents must be grounded in the agent's observable data. Aspirational criteria that exceed the data pipeline create two failure modes: (1) the agent silently ignores them, or (2) the agent hallucinates judgments from insufficient signals. When a guardrail requires data the agent does not have, explicitly delegate that check to the human in the loop rather than leaving it as an implicit expectation.

## Tags
category: architecture
module: brand-guide
