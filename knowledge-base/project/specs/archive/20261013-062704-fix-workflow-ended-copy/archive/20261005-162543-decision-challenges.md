# Decision Challenges — fix-workflow-ended-copy

Recorded per the headless-pipeline arm: deviations from the operator's
literal instructions that are backed by mechanical evidence are recorded
here (and surfaced in the plan) instead of a synchronous question.

## DC-1 — WARN-level unmapped-reason Sentry report → dropped (unreachable)

**Operator's stated direction** (verbatim): "Reference the merged
session-ended-copy work at commit d715256ba0 for the full pattern,
including the review-seat P1 (hasOwnProperty-gated lookup on free-form
wire strings) and the WARN-level unmapped-reason Sentry report."

**Initial plan design:** a `warnSilentFallback` with
`op: "workflow-ended-unmapped-status"` inside the `stream_event` arm of
`ws-client.ts`, mirroring `session-ended-unmapped-reason`
(ws-client.ts:1290-1306).

**Evidence gathered (deepen verify-the-negative pass, 2026-10-05):**

- `apps/web-platform/lib/ws-client.ts:951` runs `parseWSMessage(parsed)`
  on EVERY incoming frame before dispatch; on failure it reports via the
  existing `ws-zod-parse-failure`/`ws-unknown-event` Sentry events
  (lines 952-976).
- `apps/web-platform/lib/ws-zod-schemas.ts:547` declares
  `workflow_ended.status` as `z.enum(WORKFLOW_END_STATUSES)` — a closed
  enum, unlike `session_ended.reason` which is `z.string()` (free-form,
  where an unmapped value is live-reachable).
- `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts:76-88` sends frames
  over the real intercepted socket → injector frames pass the same parse
  gate. Same for the vitest MockWebSocket harness (`serverSend` drives
  `onmessage`).
- `apps/web-platform/test/ws-zod-schemas.test.ts:310`
  ("workflow_ended with unknown status rejects") already covers the drop.
- Adding a status to `WORKFLOW_END_STATUSES` without copy fails `tsc` on
  `Record<WorkflowEndStatus, string>` — compile-time coverage, stronger
  than warn.

**Consequence:** a warn inside the parse-gated `stream_event` arm can
never fire on any existing channel; a future non-WS channel would
bypass that code location entirely. It is dead code masquerading as
coverage — rejected under the mechanism-minimality gate.

**Resolution:** the warn is dropped; the asked *property* ("unmapped
statuses self-report") is preserved by (a) `ws-zod-parse-failure`
upstream (error-level, pre-existing), (b) the `Record<>` tsc rail
(compile-time), and (c) the membership-gated resolvers' generic
fallback for direct-construction channels. A comment in `ws-client.ts`'s
`stream_event` arm documents where the coverage lives. The
hasOwnProperty-gated P1 idiom is retained verbatim in the resolvers.

**Disclosure:** `Reviewed-Coverage: sequential-fallback` — this
assessment ran as an inline verify-the-negative pass by the deepen-plan
author, not an independent review seat.
