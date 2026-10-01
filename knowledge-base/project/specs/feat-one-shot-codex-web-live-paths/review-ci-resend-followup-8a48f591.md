# Focused CI and held-turn resend follow-up

- PR: #9051
- Reviewed pushed SHA: `8a48f59163c66606061de281bd16ad5d7a5f73e3`
- Scope: `06fbbba65ba4675d6cc06c99f41887b56adedc64` CI corrections and the held-turn resend implementation/tests added since prior panel target `6e55d879525`.
- Roles: independent code-quality analyst and test-design reviewer, executed sequentially in one review agent. This is a focused follow-up to the recorded panel, not a new full-panel attestation.
- Verification limit: source inspection only. No local suites, mutation battery, provider requests, database operations, flags, or production writes; operator requires CI-only testing. Current-head CI must supply execution evidence.
- Canonical definitions and Codex instructions were read. Installed review skill workflow/phase/gate prose was read in bounded chunks; the oversized historical defect catalogue/sharp-edge tail was not fully read. Initial oversized reads truncated and were not counted as complete. Parent owns the remaining review, deterministic gates, QA, disposition, trailer, and shipping chain.

## Finding requiring an inline correction

**P2 / pr-introduced: resend clears the held draft when the socket cannot send.**

Location: `apps/web-platform/lib/ws-client.ts` → `resendMessage()` and `send()`.

`resendMessage()` checks the rendered connection status, then clears the message delivery marker, calls `send()`, and deletes the held-turn map entry. `send()` returns without sending when the actual socket is absent or its `readyState` is not `OPEN`. A socket can enter `CLOSING`/`CLOSED` before the close event updates React's status. An explicit resend during that interval therefore leaves the original bubble looking sent and removes its resend action even though no chat frame was transmitted. A synchronous send exception also occurs after the delivery marker was cleared.

Recommended correction: make send success observable, and clear delivery/delete the held entry only after an actual successful socket send. Keep both the draft and its held entry unchanged on a non-open socket or send failure. Recheck socket readiness at the transport boundary; the rendered status alone is insufficient.

Required regression: acknowledge a held draft, retain `status === connected`, change the mock socket's readyState to `CLOSING` (then `CLOSED`), attempt resend, and assert zero chat frames plus unchanged ID/body/attachments/retryable state. Restore a usable connection and explicitly retry; assert exactly one frame and one existing bubble. Add a send-throws arm if failures are caught. Estimated correction: small, two files, low refactoring risk; no broader redesign needed.

Structural-cause roll-up: one transport-success gap encompassing silent refusal and the premature delivery update. No independent P1 finding found in this focused delta.

## Source checks that passed

- Deferred-creation fixtures now provide the persisted binding generation `7` and a boolean acknowledgment RPC result. The real handler requires `data === true` and supplies that generation to attempt admission; the tests assert both RPC arguments and attempt mode/generation. Error and stale-admission coverage remains present. The Claude path now asserts `dispatchSoleurGo` rather than the legacy `sendUserMessage`; this matches the pending Soleur routing branch.
- `vi.mocked(...)` preserves the typed WebSocket mock contract while exposing Vitest mock methods. It changes the test access, not application behavior.
- Both disposable PostgreSQL readiness probes now use TCP `127.0.0.1`, avoiding the image's temporary socket-only initialization server. Assertions and cleanup remain present; no readiness failure is converted to a pass.
- The shared Button primitive spreads `onClick` and `type` into a native button, preserves disabled behavior, and retains the resend aria-label. Existing component coverage drives the actual click callback. Screenshot QA still belongs to the parent.
- PIN_LATER adds exactly `150_codex_history_ack_owner_scope.down.sql` and `152_agent_engine_erasure_lock_order.down.sql`. Both redefine shared functions via `CREATE OR REPLACE`, matching the classifier's later-row-sensitive predicate. `149` removes its own objects without CASCADE or shared redefinition; `151` drops an index. Their omission from this particular set is appropriate. Full set equality is retained, not loosened to a count/subset assertion. The classifier was read but not executed locally.
- Both credential modes are covered with two distinct held turns. Acknowledgment sends only its own frame; confirmation changes delivery without automatic chat transmission. Explicit retry preserves first-turn ID/body/attachments and second-turn ID/body, and does not add a bubble after the first resend. Source guards also reject wrong-role/non-retryable/unacknowledged/wrong-conversation drafts and remove the map entry after an explicit retry.

## Test-design assessment and coverage limits

Source-only test quality: **7.6/10 (B)**; no execution or TDD evidence inferred.

| Property | Score | Assessment |
| --- | --- | --- |
| Understandable | 8 | Scenarios describe user-visible behavior and credential modes. |
| Maintainable | 7 | Real hook/handler paths are useful; the partial cc-dispatcher mock imports a large production graph. |
| Repeatable | 8 | Synthetic data and isolated PostgreSQL containers; actual timing remains CI-dependent. |
| Atomic | 8 | Fixtures reset mocks and sessions; acknowledgment and explicit retries are distinct actions. |
| Necessary | 9 | Transfer consent and preservation of unsent drafts matter. |
| Granular | 8 | Exact frame assertions and admission arguments identify contract drift. |
| Fast | 8 | Hook/component arms are small; database tests are intentionally heavier. |
| First/TDD | 5 | Unverified for this delta; neutral score, not a claim of TDD. |

Prioritized additions:

1. Pin the transport-refusal race above (repeatability/reliability); a mock that remains OPEN cannot exercise it.
2. Give stale-generation and different-session arms actual correlated held turns. Current arms assert notice persistence/reset but have no held message, so they do not prove that stale acknowledgments fail to unlock a resend or that session changes invalidate retryability. Source implements generation/conversation fences; their held-turn behavior needs regression coverage.
3. Explicitly retry the same retained message twice and assert one chat frame; count bubbles after the second distinct resend too. Map deletion appears to prevent duplicate clicks by construction, but the current suite does not directly pin that property.

The `cc-dispatcher` partial mock still uses `importOriginal`, importing its broad dependency graph. Inspection found lazy singleton/timer creation rather than an unconditional live dispatch at import. This is a maintainability concern, not evidence of a provider call or blocker; retain real helpers where needed or replace only after enumerating handler consumers and preserving their contracts.

Global acceptance remains incomplete: correction and CI verification, screenshot QA, remaining independent lenses/gates, routine consumer qualification, authorized API-key and managed Web qualification, and attributable mode-specific CLO dispositions. This report authorizes none of those runtime or rollout actions.

## Subsequent assigned implementation, uncommitted

After returning the detection finding, the parent explicitly assigned its correction in `lib/ws-client.ts`, `components/chat/chat-surface.tsx`, `test/ws-client-resume-history.test.tsx`, and `test/chat-surface-codex-history-transfer.test.tsx`. Regression definitions were added before the transport/UI correction; they were not executed locally, so RED/GREEN and mutation evidence are pending CI. The correction retains the draft/map entry on a non-open socket or a synchronous send failure, requires session confirmation, and marks delivery sent only after successful socket send. Exceptions use the existing client observability helper.

Held reconnect exposes the existing recovery button. That button explicitly authorizes a same-conversation resume on the next authenticated socket, without sending chat; retry waits for server session confirmation. Replay-eligible held sessions retain the same explicit recovery requirement even after stamped streaming frames: `ws-handler.ts` → authenticated `newSession` creation omits conversation binding, and `handleResumeStream()` verifies ownership/replays frames without assigning that binding. Stream continuity cannot prove chat-admission readiness. This disposition avoids expanding server/session ownership in the correction. Added coverage pins stale-generation rejection with actual held turns, session-switch invalidation, duplicate retry rejection, unchanged IDs/body/attachments, and bubble cardinality. `git diff --check` passed. No source or test execution, commit, or push occurred in this child task; the parent owns verification and review of the correction.
