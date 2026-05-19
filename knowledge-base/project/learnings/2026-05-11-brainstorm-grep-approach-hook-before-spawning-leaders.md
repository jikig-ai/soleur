# Learning: Grep main for the approach hook before brainstorm leader spawn

## Problem

Issue #3258 framed two architectural approaches:
- **Approach 1:** persist cc assistant turns at SDK stream-end in `cc-dispatcher.ts`.
- **Approach 2:** exclude cc rows from `api-messages.ts` hydration.

The issue body explicitly asked for a planning cycle to "weigh approach 1 vs approach 2." A bare-number `/soleur:go 3258` invocation routed the work to `soleur:brainstorm`. The brainstorm followed the prescribed shape — worktree creation, USER_BRAND_CRITICAL framing, CPO + CLO + CTO leaders in parallel + repo-research + learnings-researcher — and only at Phase 2 did two of those five agents independently surface that **the headline approach-1 fix had already shipped in PR #3286** (merged 2026-05-05, same day as the parent PR #3254 the issue body referenced).

Phase 1.1 pre-research had checked for prior KB artifacts (`find knowledge-base/project/brainstorms knowledge-base/project/specs -iname "*cc-soleur*" …`) and surfaced two adjacent cc-soleur-go specs, but neither contained a fully-fleshed plan and the search did NOT grep the working tree for the obvious approach-1 hook function (`saveAssistantMessage`). The check that would have caught the staleness in five seconds — `grep -n "saveAssistantMessage" apps/web-platform/server/cc-dispatcher.ts` — was not run until the post-spawn pivot.

Five agents and roughly 250k tokens of context were spent before the orchestrator pivoted from "design the fix" to "audit residual risk of a fix that already shipped."

## Solution

Pivoted mid-brainstorm. The wasted leader context turned out to be load-bearing in the new framing — CTO Risks 2-3, CLO cross-tenant invariants, CPO migration-cohort affordance, and the privacy-policy refresh became a hardening-pass spec captured in issue #3603 with a verification-gated 3-PR sequence. Closed #3258 as superseded; reused the worktree (`feat-cc-assistant-turn-persistence-3258`) and draft PR (#3602) for the new issue.

The salvage worked because USER_BRAND_CRITICAL framing was already in place, but the underlying inefficiency was real: the same outcome could have been reached by grepping `main` first and then spawning leaders with a narrower hardening-pass prompt from the start, saving ~50% of agent context.

## Key Insight

**When a feature description proposes "approach 1 vs approach 2" AND cites a parent PR or recent commit, grep `main` for the approach-1 hook symbol BEFORE spawning domain leaders.** Issue bodies are written at one moment in time and don't update when adjacent PRs land or stall — the canonical version of this lesson is `2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md`, but that learning's verification step asks `gh pr view <N> --json state,mergedAt`. That is necessary but not sufficient when an *adjacent* PR (not the cited one) implements the approach.

The cheaper, sufficient check is to grep `main`'s working tree for the symbol that approach 1 would introduce. If the symbol is present, the approach is already implemented and the brainstorm should pivot to *audit residual risk* not *design the fix*. If absent, proceed with standard leader spawn.

This is a generalization of `2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`: that learning warned about asserting a feature is "not mounted" based on absence of a generic phrase; this learning warns about *asserting a feature is not implemented* based on absence of a prior brainstorm artifact. The fix is the same — grep for the specific consuming symbol, not the topic name.

## Session Errors

1. **Stale-issue detection at Phase 2 instead of Phase 1.1.** Pre-research checked KB artifacts but did not grep main for approach-1's hook function. CTO and repo-research independently surfaced PR #3286 mid-session after substantial leader spend. **Recovery:** pivoted to hardening-pass scope, repurposed worktree/PR/leader context. **Prevention:** add a pre-spawn grep step to brainstorm Phase 1.1 — when the feature description (or referenced issue body) names "approach 1" and a specific hook location (function name, file, callback name), grep `main` for the function/symbol before spawning leaders. Treat presence-on-main as a strong staleness signal.

## Tags

category: process
module: brainstorm
related:
  - knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md
  - knowledge-base/project/learnings/2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md
  - knowledge-base/project/learnings/2026-04-23-verify-trigger-path-before-attributing-regression.md
issues:
  - "#3258 (closed, superseded by #3286)"
  - "#3603 (hardening umbrella, OPEN)"
prs:
  - "#3286 (the already-shipped fix that this brainstorm rediscovered)"
  - "#3602 (this session's draft PR, now tracking #3603)"
