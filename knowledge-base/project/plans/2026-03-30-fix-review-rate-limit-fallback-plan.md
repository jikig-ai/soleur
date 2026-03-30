---
title: "fix(review): document inline fallback when subagents are rate-limited"
type: fix
date: 2026-03-30
---

# fix(review): Document Inline Fallback When Subagents Are Rate-Limited

## Problem

When all review subagents hit API rate limits simultaneously, the `/review` skill
has no documented fallback behavior. In the #1291 session, all 4 parallel agents
(security-sentinel, architecture-strategist, code-simplicity-reviewer,
performance-oracle) returned "out of extra usage" with zero output. The main agent
performed an ad-hoc inline review, but this fallback is not codified in SKILL.md.

Without documentation, future sessions may silently skip review when all agents
fail, treating "no findings" as "clean code."

**Evidence:** `knowledge-base/project/learnings/2026-03-30-review-agent-rate-limit-fallback.md`

## Proposed Solution

Add a "Rate Limit Fallback" section to `plugins/soleur/skills/review/SKILL.md`
between the parallel agent launch (Section 1) and the Ultra-Thinking Deep Dive
(Section 4). The section:

1. Checks whether ALL parallel agents returned empty or error output
2. If all failed: performs inline review in the main context covering security,
   architecture, performance, and simplicity
3. Documents this as expected fallback behavior, not an error condition
4. If any agent succeeded: proceeds normally (no fallback needed)

### Placement in SKILL.md

Insert after `</parallel_tasks>` / `</conditional_agents>` and before
`### 4. Ultra-Thinking Deep Dive Phases`. Use a new heading:
`### 2. Rate Limit Fallback`.

The current SKILL.md jumps from Section 1 (parallel agents) to Section 4
(Ultra-Thinking). The new section fills the gap as Section 2. Renumbering
existing sections is out of scope -- the numbering inconsistency predates
this change.

### Section Content

The new section will contain:

- A `<decision_gate>` XML tag (per constitution: "XML semantic tags for control flow")
- Detection logic: check if all parallel agent outputs are empty or contain
  rate-limit error strings
- Fallback action: inline review covering all 4 core dimensions
- Binary gate: any agent with output means proceed normally (no per-dimension
  partial fallback -- YAGNI)
- A note that this is expected behavior during high-usage periods

### Consistency with Existing Patterns

The one-shot skill (`plugins/soleur/skills/one-shot/SKILL.md:94`) already documents
a subagent fallback pattern: "If absent or subagent failed (fallback):" followed by
inline execution. The review fallback follows the same pattern.

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/review/SKILL.md` | Add "Rate Limit Fallback" section after parallel agents |

## Acceptance Criteria

- [x] Review SKILL.md contains a "Rate Limit Fallback" section
- [x] Fallback triggers only when ALL agents return empty/error (not when some succeed)
- [x] Inline review covers security, architecture, performance, and simplicity dimensions
- [x] Section uses `<decision_gate>` XML tag per constitution conventions
- [x] Markdown passes `npx markdownlint-cli2 --fix`

## Test Scenarios

- Given all review subagents return empty output, when the review skill reaches the
  fallback check, then it performs inline review in main context
- Given 3 of 4 agents fail but 1 succeeds, when the review skill reaches the
  fallback check, then it proceeds normally with partial results (no full fallback)
- Given all agents succeed, when the review skill reaches the fallback check, then
  it skips the fallback entirely

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/documentation change.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Retry failed agents | Recovers from transient limits | Rate limits are session-wide; retries will fail too | Rejected |
| Skip review on failure | Simple | Silent quality gap; "no findings" misread as "clean" | Rejected |
| Inline fallback (chosen) | Guaranteed review coverage; matches one-shot pattern | Uses main context tokens | Accepted |

## MVP

Single-file change to SKILL.md. No scripts, no agent changes, no new files.
