---
name: multi-agent-review-catches-feature-wiring-bugs
description: When wiring a new subsystem (SDK runner, registry, rate limiter) into an existing entry point (ws-handler.ts), multi-agent review in parallel catches a distinct bug class — semantic-collision, resource-leak, and defense-in-depth — that tsc + unit tests + semgrep all pass cleanly on
type: best-practice
tags: [code-review, multi-agent, feature-wiring, command-center, soleur-go]
category: best-practices
module: apps/web-platform/server
---

# Multi-Agent Review Catches Feature-Wiring Bugs (feat-cc-single-leader-routing Stage 2)

## Problem

Stage 2 of `feat-cc-single-leader-routing` (PR #2858, issue #2853) wired three new
modules (`cc-dispatcher.ts`, `cc-interactive-prompt-response.ts`,
`cc-interactive-prompt-types.ts`) into `ws-handler.ts` alongside a runner
extension (`bridgeInteractivePromptIfApplicable`, `classifyInteractiveTool`,
`respondToToolUse`) and a `WSMessage` widening.

All mechanical gates passed cleanly pre-review:

- `./node_modules/.bin/vitest run` → 2502 pass / 0 fail
- `npx tsc --noEmit` → only the pre-existing spike error
- `semgrep` with custom rules + OWASP pack → 0 findings

Yet parallel review by 8 specialized agents (security, architecture,
performance, data-integrity, code-quality, patterns, test-design, git-history)
surfaced **14 actionable findings**, of which **5 were P1**. None of these
bugs would have been caught by tsc, the unit suite, or deterministic SAST —
they are structural concerns that only surface when a human-or-agent reader
holds the whole wiring in their head and asks "does this cohere?".

## Solution

Apply multi-agent review as a mandatory gate before shipping any
cross-cutting wiring change (new subsystem + entry-point integration).
Launch agents in parallel; spawn at least these four for wiring PRs:

1. **security-sentinel** — cross-user ownership, rate-limit bypass,
   resource-exhaustion amplifiers
2. **architecture-strategist** — semantic taxonomy collisions, singleton
   bootstrap shape, event-routing lossiness
3. **performance-oracle** — per-turn DB cost, unbounded growth in long-lived
   data structures, quota-exhaustion failure modes
4. **data-integrity-guardian** — sticky-state invariants, silent-drop on
   race paths, defense-in-depth query scoping

A bug class we catch exclusively here: **"the new module is correct in
isolation but its integration with an existing taxonomy is wrong."**
Examples from this session:

- `leaderId: "system"` — a valid `DomainLeaderId` value, but the UI
  avatar layer (`components/leader-avatar.tsx`) treats `"system"` as
  "internal health-check output, not a conversational bubble". Emitting
  CC router output under `"system"` would render every turn as the
  System avatar. Fix: introduce a new `cc_router` leader
  (`server/domain-leaders.ts`) with `internal: true`, separate
  `LEADER_COLORS` / `LEADER_BG_COLORS` entries.

- Tombstones in `cc-interactive-prompt-response.ts` grew per-consumed
  prompt with no reaper in production — `registry.reap()` existed as a
  public method but had **no caller outside tests**. tsc is silent on
  "method is never called in prod". Fix: schedule `setInterval(...).unref()`
  at singleton init in `cc-dispatcher.getPendingPromptRegistry()` that
  calls both `registry.reap()` and `pruneTombstonesFor(registry)`.

- `persistActiveWorkflow(null)` wrote DB `NULL` which
  `parseConversationRouting` reads back as `{kind: "legacy"}` — silently
  regressing a soleur-go conversation to legacy mid-turn. The runner
  never actually calls back with `null`, but the type contract allowed
  it. Data-integrity review asked "what if null?"; the answer was a P1
  stickiness violation. Fix: map `null` → `soleur_go_pending` sentinel
  in the ws-handler callback.

- Per-turn `SELECT active_workflow` added ~1 QPS/user DB cost on the
  soleur-go path despite the routing value being in-process single
  source-of-truth. tsc has no opinion on "this DB fetch is unnecessary";
  perf review asked "why does every turn hit the DB?". Fix: cache on
  `ClientSession.routing`, invalidate on abort/resume/close, seed at
  materialization + refresh via `persistActiveWorkflow`.

- `session.ip ?? "unknown"` rate-limit fallback would collide every
  IP-missing user into a single 30/hour bucket — a DoS pivot under
  proxy misconfiguration. Security review framed it as "what if the
  string fallback is reachable?"; fix: fall back to `userId` so per-user
  isolation still holds.

## Key Insight

**tsc + tests + semgrep enforce local correctness. Multi-agent review
enforces systemic coherence.**

The bugs review caught all share a common shape: "A is correct given
only A's context. B is correct given only B's context. A + B together
are wrong because of a constraint that lives in C." Examples:

- "A = emit WS event with leaderId: 'system'" + "B = UI avatar layer
  existing behavior" → wrong because C = "system" avatar semantics.
- "A = register prompt" + "B = consume prompt" → wrong because C = no
  reaper schedule means the tombstone set accumulates forever.
- "A = runner emits workflow_ended" + "B = client treats session_ended
  as terminal" → wrong because C = cost_ceiling / runner_runaway are
  recoverable.
- "A = chat dispatch reads active_workflow" + "B = active_workflow is
  in-process single-SoT" → wrong because C = no cache, so every turn
  pays DB latency.

None of these are syntactic bugs; all are composition bugs. Only a
reviewer holding all three (A, B, C) at once can catch them. Running
multiple specialized reviewers in parallel is the cheapest way to
approximate "many readers each holding a different C".

## Prevention

- **Gate any cross-cutting wiring PR on multi-agent review.** Threshold:
  a PR that introduces a new module AND integrates it into an entry
  point (ws-handler, route files, the main `App.tsx` render tree) MUST
  run at least security-sentinel + architecture-strategist + performance-
  oracle + data-integrity-guardian before ship.
- **Write the review prompt with specific probes, not generic questions.**
  "Check for security issues" returns vague advice. "Probe X=
  composite-key cross-user consume, Y=rate-limit bypass via flag flip,
  Z=respondToToolUse length cap" returns actionable P1s. Include file:
  line refs in the prompt so the agent grounds its analysis in code.
- **Explicitly enumerate integration concerns** in the review prompt —
  "this ws-handler case delegates to dispatcher singleton which captures
  sendToClient at first call; is the bootstrap shape correct?". Agents
  are good at evaluating a hypothesis; they are weaker at generating
  the hypothesis unprompted.
- **Don't rely on `registry.reap()` / `tombstone.clear()` / similar
  cleanup methods being called — verify the scheduler.** A cleanup
  method with no scheduler is a memory leak. In code review, grep for
  the method name + confirm there's an `Interval` / `Timeout` / cron /
  explicit call outside tests. Missing scheduler → file-or-fix.
- **For any new `DomainLeaderId` / tagged-union literal, check the
  downstream consumer (avatar, color map, bubble renderer) BEFORE
  committing.** Adding to the union without adding to the `Record<Id,
  X>` maps is a tsc error (caught). Using an existing value that carries
  UI semantics you don't want is NOT a tsc error (review-only).

## Session Errors

1. **Wrong cwd for `./node_modules/.bin/vitest`** — Recovery: single-call
   `cd apps/web-platform && …`. **Prevention:** already codified in
   `cq-for-local-verification-of-apps-doppler`; add a muscle-memory
   reminder to first line of any apps/web-platform bash sequence.

2. **`npx tsc --noEmit` from wrong cwd triggered `tsc@2.0.4` installer** —
   same root cause. **Prevention:** same rule.

3. **Wrote RED test for `conversation_mismatch` error that was
   unreachable** because the registry's composite-key design makes the
   cross-conversation probe return `not_found` via the key-miss path.
   Recovery: updated test expectation to `not_found`, removed
   unreachable branch in handler. **Prevention:** before adding a
   per-error discriminant to a pure decision function, trace each error
   path from caller to callee to confirm reachability — composite keys
   often make semantically distinct errors mechanically indistinguishable.

4. **Tautological `toBeGreaterThanOrEqual(0)` assertion on unsigned
   count** — test-design-reviewer caught. **Prevention:** already
   codified in `cq-mutation-assertions-pin-exact-post-state`.

5. **leaderId: "system" conflated with internal health-check output** —
   architecture-strategist caught. **Prevention:** see above under
   "Prevention" (check downstream consumer before using existing
   tagged-union literal).

6. **4-way kind taxonomy with one-way exhaustiveness check** —
   pattern-recognition caught. **Prevention:** when replicating a union
   across multiple files, use `satisfies Record<Union, true>` for
   bidirectional drift detection, not a one-direction `:` annotation.

7. **Tombstone Set + `registry.reap()` never scheduled in production** —
   perf-oracle caught. **Prevention:** see above under "Prevention"
   (grep for scheduler of any cleanup method).

8. **Per-turn DB fetch with no caching** — perf-oracle caught.
   **Prevention:** when introducing a new lookup on a hot path, ask
   "does anything outside this process mutate the value? if no, cache
   on session state."

9. **`session.ip ?? "unknown"` collision bucket** — security-sentinel
   caught. **Prevention:** when a rate-limit key could be missing,
   fall back to a value that preserves per-entity isolation (userId,
   sessionId), never a literal like `"unknown"`.

10. **`respondToToolUse` no length cap for `ask_user` response** —
    security caught. **Prevention:** any path that pushes client-
    supplied string content into the SDK must enforce the same byte
    cap as `prompt-injection-wrap.ts` (`MAX_USER_INPUT_BYTES`).

11. **`persistActiveWorkflow(null)` wrote DB NULL breaking stickiness**
    — data-integrity caught. **Prevention:** when a callback parameter
    has a nullable type but the caller contract forbids null, the
    implementer should still treat null as a defensive branch that
    preserves invariants (here: map to the sentinel, not the legacy
    NULL).

12. **`createConversation` 23505 fallback silently dropped
    `activeWorkflow`** — data-integrity caught. **Prevention:** when
    a race-path fallback returns a pre-existing row, SELECT the fields
    your caller passed to verify intent-vs-actual match; mirror to
    Sentry on divergence per `cq-silent-fallback-must-mirror-to-sentry`.

13. **`persistActiveWorkflow` UPDATE missing `.eq("user_id", userId)`** —
    data-integrity caught. **Prevention:** UPDATE / DELETE statements
    that fire from per-user handlers must always include the user scope
    clause as defense-in-depth, even when the key is server-derived.

14. **Stub `queryFactory` per-request Sentry mirror** — perf caught.
    **Prevention:** when shipping a known-failing stub behind a feature
    flag, gate its Sentry mirror behind a once-per-process boolean so a
    misconfigured flag-on state cannot exhaust the event quota.

15. **`onWorkflowEnded → session_ended` lossy for recoverable states** —
    arch caught. **Prevention:** when mapping a multi-variant source
    enum onto a binary "terminal" sink, enumerate each source variant
    and classify terminal vs recoverable explicitly; don't collapse
    wholesale.

16. **Line-number anchors in comments** — pattern caught. **Prevention:**
    already codified in `cq-code-comments-symbol-anchors-not-line-numbers`.

## Files

- `/apps/web-platform/server/cc-dispatcher.ts` — singleton orchestration + reaper scheduler + stub once-guard
- `/apps/web-platform/server/cc-interactive-prompt-response.ts` — `pruneTombstonesFor` + bidirectional `KIND_SET` derivation
- `/apps/web-platform/server/cc-interactive-prompt-types.ts` — bidirectional exhaustive check + sunset TODO
- `/apps/web-platform/server/soleur-go-runner.ts` — bridge exhaustiveness rail
- `/apps/web-platform/server/ws-handler.ts` — routing cache + fail-closed rate-limit fallback + 23505 divergence detection
- `/apps/web-platform/server/domain-leaders.ts` — `cc_router` leader
- `/apps/web-platform/components/chat/leader-colors.ts` — palette entries for `cc_router`
- `/apps/web-platform/lib/types.ts` — `WSErrorCode` extended with `interactive_prompt_rejected`

## References

- PR #2858 (feat-cc-single-leader-routing)
- Plan: `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`
- ADR-022: `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md`
- Related: `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
