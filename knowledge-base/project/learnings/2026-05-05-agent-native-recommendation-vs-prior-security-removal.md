---
date: 2026-05-05
category: best-practices
module: review
tags: [review, security, agent-native, wire-schema, scope-out]
related_issues: [3235, 3242, 2138, 2115]
problem_type: security_decision_collision
---

# Learning: Agent-native review recommendations may collide with prior security removals

## Problem

During PR #3235 review, the `agent-native-reviewer` agent rated as **P1** the absence
of a raw SDK tool name (`name`) on the `tool_use` WS event. Recommendation: add
`name: block.name` to `lib/types.ts`, `lib/ws-zod-schemas.ts`, and both server
emitters. The fix looked small (~4 files, ~8 lines).

Following the review skill's "fix-inline default for P1", I implemented the change.
Then, while updating the legacy `agent-runner.ts:1041-1052` emitter, I read its
inline comment:

```
// human-readable label crosses the wire — the raw SDK tool name
// (Read/Bash/Grep/...) is an internal implementation detail and
// must not leak to devtools or any WS inspector. See #2138.
```

Issue #2138 turned out to be a deliberate review finding (PR #2115) that
**removed** the raw tool name as an information-disclosure mitigation. The
agent-native recommendation was reversing that decision without revisiting the
threat model.

## Solution

1. Reverted all four file changes.
2. Re-classified the finding as **contested-design** scope-out — two viable
   approaches (re-add `name` to wire vs. introduce a separate agent-only
   channel) with materially different security/observability trade-offs.
3. Filed #3242 with explicit references to #2138 and both approach options.
4. The code-simplicity-reviewer **CONCURred** the scope-out filing on the
   condition that the issue body explicitly references the prior security
   decision.

## Key Insight

**A review agent's `Pn` rating is the LOCAL severity of a finding. It does not
automatically dominate prior cross-cutting decisions encoded as `// See #N`
comments.** Before applying a P1 fix that touches wire schemas, security
boundaries, or any field with a `// See #N` provenance comment:

1. **Grep for prior provenance.** `git log -S<symbol> -- <file>` and
   `grep -n '// See #' <file>` in the diff scope.
2. **Read the referenced issue.** If the prior PR removed the same artifact the
   review agent wants to add back, the recommendation reverses a decision that
   needs its own threat-model review — flip to **contested-design** scope-out.
3. **The second-reviewer gate (code-simplicity-reviewer) reliably catches this**
   when the scope-out justification names the prior issue and lists ≥2 viable
   approaches with different trade-offs. Without that context the gate may flip
   to fix-inline.

This complements `cm-challenge-reasoning-instead-of` and `rf-when-a-reviewer-or-user-says-to-keep-a`:
review agents are smart but local; their recommendations need to be checked
against deliberate cross-cutting decisions before being applied.

## Bonus insight: parallel async-dispatcher pattern with test-fixture microtask yield

When a review agent flags a serial `await` in an async dispatcher as cold-start
latency overhead and recommends parallel kick-off (`fetchX().then(v => x = v)`):

- The pattern works in **production** because downstream code (e.g., SDK Query
  construction) awaits the same memo, providing an ordering guarantee.
- The pattern **breaks synchronous test stubs** because the stubbed dispatch
  fires `onToolUse` before the dispatcher's `.then` microtask runs.
- **Fix:** add `await Promise.resolve()` at the top of the test stub's dispatch
  body. One microtask yield is sufficient to flush the dispatcher's `.then`
  chain when the source promise was created with `mockResolvedValue`.

This pattern is reusable for any future parallel kick-off in async dispatchers
with a memo-backed downstream consumer.

## Tags

category: best-practices
module: review
related_pr: 3235
related_issues: 3242, 2138, 2115

## Session Errors

- **Initially added `name` field to `tool_use` schema before checking for prior
  removals.** Recovery: read agent-runner's `// See #2138` comment, fetched
  issue, reverted 4 file changes (lib/types.ts, lib/ws-zod-schemas.ts,
  cc-dispatcher.ts, never landed on agent-runner.ts because the comment caught
  me first). Prevention: when a review agent recommends adding a field, grep
  the diff scope for `// See #N` comments referencing prior removals BEFORE
  implementing — covered by the new bullet routed to `review/SKILL.md` Sharp
  Edges below.

- **`DomainLeaderId` import targeted `@/lib/types` instead of
  `./domain-leaders`.** Recovery: `tsc --noEmit` flagged it; switched to the
  correct module. Discoverable via tsc — no rule needed.

- **Plan-deepening risk wording: "relocation of existing call" misframing.**
  Recovery: codebase verification during deepen showed `realSdkQueryFactory`
  runs only on cold-Query construction, making the dispatcher's await a NEW
  per-turn RTT, not a relocation. Plan corrected before work began.
  Discoverable via codebase reading — no rule needed.

- **Two scope-out DISSENTs from code-simplicity-reviewer.** The cold-start LTFT
  perf finding and the `buildToolUseWSMessage` helper extraction both flipped
  from scope-out to fix-inline. Recovery: implemented both. NOT an error —
  the gate worked as designed; included for completeness.
