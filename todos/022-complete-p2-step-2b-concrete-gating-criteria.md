---
status: pending
priority: p2
issue_id: "022"
tags: [code-review, agent-native]
dependencies: []
---

# Add concrete gating criteria for fetch-user-timeline in Step 2b

## Problem Statement

Step 2b says to call `fetch-user-timeline` for mentions with "ambiguous brand association risk" but provides no actionable criteria. An LLM agent will either over-call (wasting API credits on every non-RT mention) or under-call (skipping the check entirely).

## Findings

- The plan warns about API credit conservation (0-3 calls per session expected)
- Currently the agent has no deterministic gate for when "ambiguous" applies
- Also missing: fallback if `#### Engagement Guardrails` subsection is absent from brand guide
- Also missing: explicit sort directive for conversation dedup (assumes API ordering)

## Proposed Solutions

### Option 1: Add follower-count threshold + text-signal gate

**Approach:** Add explicit criteria: "Call `fetch-user-timeline` when `author_followers_count` is below 100 AND the mention text does not contain a direct question or product reference." Also add brand guide subsection fallback and sort directive for dedup.

**Effort:** 10 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `plugins/soleur/agents/support/community-manager.md:321` (gating criteria)
- `plugins/soleur/agents/support/community-manager.md:333` (dedup sort directive)

## Acceptance Criteria

- [ ] Step 2b has concrete criteria for when to call fetch-user-timeline
- [ ] Step 2b includes fallback for absent Engagement Guardrails subsection
- [ ] Step 3 conversation dedup includes explicit sort by created_at

## Work Log

### 2026-03-13 - Initial Discovery

**By:** Code Review (agent-native-reviewer)
