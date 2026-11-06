# Learning: a refusal logged at a level that never ships, and an invariant enforced on a narrower predicate than it was stated for

## Problem

PR #11715 (follow-ups of the Authentication mode work, #11594 and #11599) passed its own suite and a 12-seat review panel found:

1. **Dark logs.** To avoid a double Sentry event, five call sites stopped mirroring a lease refusal and logged it at INFO instead. The plan said "pino to Better Stack". The log shipper (`infra/vector.toml` `app_container_warn_filter`) forwards level >= 40 only, so INFO stayed on the host. The only remaining signal carried a closed reason and no user or conversation.
2. **Invariant narrower than its statement.** The ADR and the ruling said "the binding's workspace must equal the delegation's workspace". The guard was `slot.delegationId != null && slot.delegationWorkspaceId == null`, while the skip applied to every cross-owner lease. An owner-mismatch lease with no delegation id reached the resolver with no workspace to compare, and a test row pinned that as intended. Seven seats found it independently.
3. **The fix for (1) introduced two more.** Debouncing the lease event per (user, reason) also drops its pino ERROR line, so the per-turn trace moved to the call-site WARN lines, and one site (`ws-handler.ts`) did not carry `conversationId`. The module-level debounce map leaked between tests (13 failures).
4. **Ruling wording not falsified.** The CLO-drafted re-evaluation trigger ("selects or serves the subscription row for a cross-owner lease") was already true of shipped, ruled behaviour (the owner gate still SELECTs the row before refusing). It went into the audit verbatim and was caught by a fix-round seat.

## Solution

- Log the refusal at WARN (no `err`, hashed user id, `conversationId`); keep `non_api_key` at debug; tag the lease event with `cause` and the hashed user; debounce it; pin each level in a test that reads the level, not only the message.
- Guard on the same flag the skip is gated by (`crossOwner`), not on one of its two inputs; flip the pinned row to a refusal; add a mutation check that reverts the guard.
- Derive the cause list once in the import-free leaf, pin the client's literals to it with a parity test that reads the wire schema's own members.
- Narrow the audit trigger to what section 5 actually prohibits.

## Key Insight

A claim that "this signal reaches the dashboard" is a claim about the shipper's filter, not about the log call: read the filter (`vector.toml`) before accepting INFO as an observability channel. And when a prose invariant has two inputs, the guard must key on the predicate that gates the action, not on whichever input the author was thinking about; a test row that pins the uncovered shape as "intended" is the tell.

## Session Errors

1. **Ended turns mid-pipeline.** I stopped at the review marker and at "Paused" lines when the next step was mine. — Recovery: the user asked why; continued with QA. — **Prevention:** emit the marker and continue in the same response; use "Paused:" only for a real external wait. (Already covered by `hr-when-a-workflow-concludes-with-an`.)
2. **`gh issue create` refused twice** by the filing gate: `User-Impact:` needs a whole-word singular surface term (`document`, `route`, `page`, …) from `.claude/hooks/lib/user-surface-taxonomy.txt`; "documents" fails `\bdocument\b`. — **Prevention:** noted in `review-todo-structure.md`.
3. **Semgrep crashed on first run** (io_uring backend, exit 2, 0 files scanned) — a void result, not a clean one. — **Prevention:** re-run with `EIO_BACKEND=posix semgrep -j 1`; already documented in the semgrep-sast agent's Critical Constraints (#9096), so no routing was needed. A first routing attempt into `review/SKILL.md` put that file 247 bytes over its ceiling and reddened the required `rule-body-lint` check; grep the agent definition before routing a sharp edge into a skill body.
4. **Transcribed CLO-drafted wording without falsifying it** against the code. — **Prevention:** run the "name the command that falsifies each added sentence" pass over ruling text before it is written into an audit or ADR.
5. **Module-level debounce map leaked across tests** when the lease event became debounced. — **Prevention:** call `__resetMirrorDebounceForTests()` in the top-level `beforeEach` of any suite that drives a debounced emitter.

## Tags

category: logic-errors
module: apps/web-platform/server/byok-lease
