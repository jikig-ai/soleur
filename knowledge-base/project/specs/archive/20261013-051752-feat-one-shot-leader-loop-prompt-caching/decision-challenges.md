# Decision Challenges — feat-one-shot-leader-loop-prompt-caching

Recorded by the planning phase, which ran headless, for `ship` to show in the PR body and file as an `action-required` issue. The operator's stated direction is the default and has been kept.

## DC-1: keep or drop the explicit system-block cache marker (User-Challenge, taste)

- **Your direction:** remove the per-tool `cache_control` and keep exactly one explicit marker on the last system block, plus top-level automatic caching.
- **The challenge:** the plan-time advisor consult (fable) suggested dropping the explicit system marker and keeping only the top-level automatic field. At plan review, DHH (P2-6) and code-simplicity said the same, so three independent reviewers agree.
- **Why:** the tools and system prompt together are about 220-670 tokens. That is below the 1024-token minimum on Sonnet 5 and the 4096-token minimum on Haiku 4.5, so the system marker has no effect today, and the test suite would be enforcing a marker that does nothing.
- **Why the plan kept your direction:** the marker costs one of the 4 breakpoint slots and no money. The claude-api prompt-caching guidance calls "explicit marker on the static system prefix plus top-level automatic caching" the robust combination for agent loops, and the marker starts paying off if a class's prompt ever grows past the minimum.
- **To accept the challenge:** remove `cache_control` from the system block in `agent-on-spawn-requested.ts`, and change Guard 1's system-block `toEqual({ type: "ephemeral" })` assertion to `toBeUndefined()` (the total becomes 1). The ADR-042 §I5 amendment text changes to match.
