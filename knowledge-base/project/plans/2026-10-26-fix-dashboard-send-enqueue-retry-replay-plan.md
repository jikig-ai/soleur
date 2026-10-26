---
title: "fix: dashboard send must retry the Inngest enqueue and never archive an un-enqueued approved action"
type: fix
date: 2026-10-26
slug: dashboard-send-enqueue-retry-replay
branch: feat-one-shot-10543-dashboard-send-retry
issue: 10543
closes: 10543
priority: p2-medium
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: dashboard send must retry the Inngest enqueue and never archive an un-enqueued approved action

## Overview

The founder-callable send route (`apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`) writes the WORM
`action_sends` approval row, then issues ONE bare enqueue of the spawn event with no retry and no event id, then flips
the draft to archived. When that single enqueue throws, the route still archives the draft and answers 200 with a
degraded marker, so the founder's approved Concierge action is silently lost. Worse, the loss is unrecoverable by the
founder: a re-click inserts a second `action_sends` row, hits the unique-per-message constraint (23505), and the route
answers `already_sent`, which the client treats as a soft success.

This plan routes the enqueue through the shared retry helper with a stable event id, makes the archive conditional on the
enqueue having been accepted, turns an exhausted enqueue into a retryable 503 that leaves the draft visible, and adds a
founder re-click replay path that re-dispatches the same event id from the already-committed approval row (bounded to 23h
so Inngest's 24h dedup window is never straddled). All technical forks were ruled by the CTO agent, including a second
round after plan review (see `## Decision Rulings`).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #10543 / brief) | Reality (verified on this branch) | Plan response |
|---|---|---|
| "a single inngest.send with no retry and no event id" | True: bare `inngest.send({name:"agent.spawn.requested", ...})` inside the route's `try`, no `id`. | Phase 2 helper adds the id and the retry wrapper. |
| "when it throws, the draft is archived (degraded=enqueue_failed) and the approved action is lost" | True, and compounded: the route archives regardless, answers 200, and a re-click returns 409 `already_sent` (the WORM insert hits `action_sends_message_unique`), which `use-action-send.ts` treats as soft success. No re-dispatch path exists anywhere. | Phase 3 replay lookup runs BEFORE the insert and re-dispatches. |
| "Use sendInngestWithRetry ... with a stable event id" | The helper's `context.eventId` is only spread into the retry warn log; it is NOT passed to `inngest.send`. The id must be set on the event inside the thunk. | Helper passes `id` in the event AND `eventId` in the context. |
| Test (4) in `send-route.spawn.test.ts`: "A 500 would suggest retry to the operator and create orphan rows" | Stale once replay exists: a retry that finds the unacknowledged row reuses it instead of inserting. The new failure status is 503 (retryable), not 500. | Tests (3)/(4) are rewritten to the 503 + draft-kept contract (Phase 1). |
| "already used by schedule-reminder and the webhook routes" | True; also resend-inbound, stripe, run-routine, server/index. Event-id namespaces in use: `github-`, `resend-`, `stripe-`, `sla-`, `oneshot-`, bare `reminderId`. | New namespace `agent-spawn-` (no collision, grep-verified by the CTO). |
| Consumer is idempotent so a replay is always safe | Only inside ~24h: `agentOnSpawnRequested` has `idempotency: "event.data.actionSendId"` and Inngest dedups the event id, both for ~24h. The consumer's `persist-failure` swallows its own write error and the settle write is conditional, so a run that DID execute can leave `acknowledged_at` and `failure_reason` both NULL. | Replay is refused after 23h (`approval_expired`); `undone_at` / `cancellation_requested_at` rows are terminal (CTO R1). |

## Research Insights

**Premise Validation.** #10543 is OPEN with no closing PR; #10136 is the encryption-posture exceptions issue (context
only) and #10501 is MERGED. The route, helper, consumer function and migrations 051/064/069 all exist on this branch (cut
from `origin/main`). The mechanism (outbox via the unacknowledged WORM row, retry helper, stable event id) is not in any
ADR's rejected-alternatives table: ADR-034/035/036/037 cover ordering and dedup-release invariants (durable row before
side effect, release on failure) and are consistent with this plan. Direct precedent: #10542 (Stripe webhook,
`knowledge-base/project/plans/archive/20261020-114524-2026-10-20-fix-stripe-webhook-inngest-send-failure-plan.md`) — a
catch that only reports and returns success is a decision to lose the event.

**Property List.**

- P1. A transient enqueue failure does not lose the founder's approval (bounded retry).
- P2. Re-dispatching the same approval cannot start a second agent run (stable event id plus consumer idempotency, inside
  the 23h replay window).
- P3. The draft is archived only after the spawn event was accepted, or when no event is applicable (`no_artifact_in_pr_a`)
  or the approval is already terminal.
- P4. An approved-but-not-enqueued action is recoverable by the founder without writing a second WORM row.
- P5. A replay never outlives a revoked grant, a failed template gate, an edited draft, an undo/cancel, or the 23h window.
- P6. The founder is never told "Acknowledged" for an action that did not start.
- P7. Every failure, recovery and refusal is visible in Sentry without SSH.

**Cut List.**

| Mechanism | Property | Already covered by / disposition |
|---|---|---|
| Outbox column / migration | P4 | The unacknowledged `action_sends` row (`acknowledged_at` NULL and `failure_reason` NULL, mig 064) is already a durable outbox. REJECTED (CTO D2). |
| Server-side sweeper cron | P4 (founder never re-clicks) | Deferred, tracked in #11211 (needs a service-role re-authorization design). |
| 23505 re-lookup / replay arm | P4 | Cut (CTO R3): the pre-insert lookup covers every non-concurrent case; a concurrent loser keeps today's plain 409 `already_sent`, which neither dispatches nor archives. |
| Separate `find-action-send-by-message.ts` module | — | Cut (CTO de minimis): one caller, ~15 lines; inlined as a non-exported function in `route.ts`. |
| New Sentry alert rule / metric | P7 | Existing Sentry mirroring plus the platform outage signals suffice; no Terraform apply. CTO D6. |
| Delete the dead `"queued"` pill variant | P6 | Split to #11212 (a `components/**` edit would force a `.pen` wireframe gate). |
| Reusing `isBackendUnavailable` to pick 503 vs 502 | P6 | Cut: every post-retry failure is 503, because the WORM row makes replay safe. |

**Institutional learnings applied.** Report once after retry exhaustion, not per attempt (`reportSilentFallback` does not
debounce); pass `null` as the first argument with an `errorName` in `extra` so the feature/op tags survive the pino mirror
(#10542 ruling, #8629); a stateless mock cannot see a missing `await`, so the harness models the row as state; backoff
tests use `vi.advanceTimersByTimeAsync`.

**Related.** #10543 (this), #10542 (sibling precedent), #8719 (spawn dead-letter alert, unaffected), #11211 (sweeper),
#11212 (pill cleanup), draft PR #11208 (this branch).

## Decision Rulings

All rows are persisted in `knowledge-base/project/specs/feat-one-shot-10543-dashboard-send-retry/decision-challenges.md`.
What the implementation must honor (the second round, R1-R4, supersedes D2/D4/D5 where they conflict):

- D1. Exhausted enqueue returns **503** `{error:"enqueue_unavailable", action_send_id, retryable:true}` with
  `Retry-After: 5`; the draft stays `draft`; `no_artifact_in_pr_a` still archives and returns 200; `"enqueue_failed"` is
  deleted from the route and the hook unions (the pill file is left untouched, #11212).
- D3. Event id `agent-spawn-${actionSendId}`.
- R2 (moves D4). The read-only `action_sends` lookup runs right after the `not_a_draft` / known-action-class checks and
  BEFORE the grant, template and typed-confirm gates. A terminal row (acknowledged, failed, undone or cancel-requested)
  archives the draft and returns 409 `already_sent` ungated (it dispatches nothing). A pending row older than 23h returns
  409 `approval_expired` (draft kept, op `inngest-replay-stale` at warning level). Only the no-row arm and the
  pending-within-23h arm continue through ALL gates (revocation 403, template gate, approve_every_time typed-confirm and
  hash echo); the pending arm additionally returns 409 `draft_changed_since_approval` when `sha256(draft_preview)` differs
  from the row's `per_send_body_sha256`, skips only the insert, and dispatches with the same event id.
- R1 (reverses D5). Replay age gate at 23h (`clicked_at` against the server clock; the margin keeps the 24h dedup window
  from being straddled). The consumer can leave NULL/NULL on an executed run, so past the window a visible expiry beats a
  possible second GitHub artifact. The 23h margin is a plan-level choice, not verified against the DB clock.
- R3 (reverses D2's 23505 arm). 23505 on the insert keeps today's plain 409 `already_sent`.
- R4 (D6). Keep `reportSilentFallback` on exhausted retries (feature `spawn-agent`, op `inngest-enqueue`, `extra.replay`,
  `extra.transient`); ops `inngest-enqueue-replay` (successful replay, warning) and `inngest-replay-stale` (expiry
  refusal, warning). `extra.attempts` is dropped: the helper does not surface the attempt count and is not edited. No
  Terraform change and no new metric.

## Open Code-Review Overlap

None. (Queried open `code-review` issues for every path in `## Files to Edit` / `## Files to Create`: zero matches.)

## Proposed Solution

### New route flow

Gates that exist today and stay in this order: origin check, auth, message load, `status === "draft"` (else 409
`not_a_draft`), known action class. Then:

```text
parsed = parseSourceRef(source_ref)                       // hoisted; pure and local
existing = lookupActionSend(cookieClient, userId, message.id)   // non-exported function in route.ts
  select id, per_send_body_sha256, clicked_at, acknowledged_at, failure_reason, undone_at, cancellation_requested_at
  lookup error                      -> reportSilentFallback, 500 internal_error
  terminal row (acknowledged_at, failure_reason, undone_at or cancellation_requested_at set)
                                    -> archive the draft (existing error handling), 409 already_sent   [UNGATED]
  pending row, parsed AND clicked_at older than 23h
                                    -> warnSilentFallback op "inngest-replay-stale", 409 approval_expired  [UNGATED]
  pending row                       -> replay = true (continues; actionSendId = row.id)
  no row                            -> replay = false

isGranted -> tier switch -> template gate -> approve_every_time typed-confirm + hash echo     (all unchanged)

replay:    sha256(draft_preview) != row.per_send_body_sha256
                                    -> reportSilentFallback op "replay-draft-changed", 409 draft_changed_since_approval
           else skip the insert; actionSendId = row.id
no row:    try { writeActionSend(...) } catch
              23505 -> 409 already_sent (plain; concurrent winner owns the dispatch)
              other -> 500 send_failed (unchanged)        // the try wraps ONLY writeActionSend

parsed     -> enqueueAgentSpawn(...)   // sendInngestWithRetry + id agent-spawn-<actionSendId>
   throws after retries -> reportSilentFallback(null, {feature:"spawn-agent", op:"inngest-enqueue", ...})
                           503 enqueue_unavailable + Retry-After: 5, draft NOT archived
   ok and replay        -> warnSilentFallback op "inngest-enqueue-replay"
source_ref set but unparseable -> degraded "no_artifact_in_pr_a" (no enqueue; archive proceeds; applies to a replayed row too)

archive draft (unchanged error handling), 200 {id, action_send_id, artifact_view_url, degraded?}
```

The draft-hash comparison reuses the already-computed `draftPreviewHash` (`route.ts` computes it once from `draft_preview`;
`per_send_body_sha256 = sha256(bodyContent)` and `bodyContent = draftPreview`, so the values are comparable).

### Helper module (cookie client only; no service-role, no `.service-role-allowlist` change)

`apps/web-platform/server/action-sends/enqueue-agent-spawn.ts` — exports `enqueueAgentSpawn({founderId, messageId,
actionClass, sourceRef, actionSendId})`, which calls `sendInngestWithRetry(() => inngest.send({ id, name:
"agent.spawn.requested", data }), { feature: "spawn-agent", eventId: id })` with `id = agent-spawn-${actionSendId}`
(`agentSpawnEventId` is exported only if a test needs it). `actionClass` is typed `ActionClass` (no `as string` near the
send, so the `action-class-typed-literals` sentinel stays green). `installationId` stays OMITTED from `data` (consumer
invariant I1). The route no longer imports `@/server/inngest/client`.

### Client (hook only; `components/**` is deliberately untouched)

`apps/web-platform/hooks/use-action-send.ts`:

- 503 `enqueue_unavailable` in BOTH `onSend` and `onConfirmTyped`: copy "Your approval is saved, but we couldn't start the
  agent. Click Send again to retry."; `acknowledged` stays false, `onAcknowledgedArchive` is not called, the typed-confirm
  modal stays open with the error rendered in-modal.
- 409 `draft_changed_since_approval` (copy: "This draft was edited after your approval was recorded. Discard it and start
  from a fresh draft.") and 409 `approval_expired` (copy: "This approval expired before the agent could start. Discard
  this draft and create a fresh one.") in BOTH paths.
- `onConfirmTyped`'s catch-all 409 branch is made explicit: the existing "Draft changed since you confirmed — please
  re-send." copy applies only to `requires_confirmation`; any other 409 falls through to `Send failed (409)`.
- Narrow the `degraded` unions to `"no_artifact_in_pr_a" | undefined`; refresh the stale header comment about
  `enqueue_failed`.

## Implementation Phases

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

Write every test below BEFORE any production edit, with the test commit ahead of the fix commit in history. Run each file
with a targeted `./node_modules/.bin/vitest run <file>` from `apps/web-platform` (never a full-suite or gate runner).
RED must be behavioral for the route and hook tests (`writeActionSend` called, no `inngest.send`, wrong status); a
module-not-found RED is acceptable only for the new-helper unit test. Route tests mock at the supabase
`from("action_sends")` level through ONE shared stateful helper, never at a helper-module level.

0. `apps/web-platform/test/helpers/action-sends-row-mock.ts` (new, shared by the three route test files): installs an
   `action_sends` branch on a `mockFrom` implementation, backed by a mutable row (or none) and a settable lookup error;
   the default is "no row", so existing tests only need the one-line install.
1. `apps/web-platform/test/server/action-sends/enqueue-agent-spawn.test.ts` (unit)
   - `inngest.send` receives `id` equal to `agent-spawn-<actionSendId>` and `data` has exactly `{founderId, messageId,
     actionClass, sourceRef, actionSendId}` (`toStrictEqual`; no `installationId`).
   - With the REAL `sendInngestWithRetry` and `vi.useFakeTimers`: `TypeError("fetch failed")` on attempts 1 and 2 then
     success resolves after `advanceTimersByTimeAsync`, and the SAME `id` is sent on all 3 attempts.
   - A non-transient `Error` is not retried (one call) and rejects; three transient failures reject after exactly 3 calls.
2. `apps/web-platform/test/api/dashboard/today/send-route.spawn.test.ts` (rewrite tests 3 and 4; add id assertion)
   - Tests 1b/2: the `inngest.send` argument includes `id: "agent-spawn-<AS_ID>"`; the route no longer calls the client
     module directly.
   - Replaced test 3: `inngest.send` rejects (non-transient) -> **503**, `error: "enqueue_unavailable"`, `action_send_id
     === AS_ID`, header `Retry-After` equals `5`, `callOrder` equals `["writeActionSend", "inngest.send-throw"]` (NO
     `messages-archive`), `reportSilentFallback` called once with first argument `null`, `feature: "spawn-agent"`, `op:
     "inngest-enqueue"`, `extra.replay === false`, `extra.transient === false`.
   - Replaced test 4 (route-level, `vi.useFakeTimers`): transient failure on attempt 1, success on attempt 2 -> 200,
     archived once, `inngest.send` called twice with the same `id`.
3. `apps/web-platform/test/api/dashboard/today/send-route.replay.test.ts` (new; stateful `action_sends` row; any case that
   reaches the real backoff uses fake timers)
   - Replay: pending row within 23h with matching hash -> `writeActionSend` NOT called, `inngest.send` called with the SAME
     `action_send_id` and `id`, draft archived, 200, op `inngest-enqueue-replay` emitted; a re-click afterwards returns 409
     `not_a_draft` (status gate first).
   - Replay whose enqueue fails again -> 503, draft not archived, `extra.replay === true`.
   - `it.each` terminal rows (acknowledged_at / failure_reason / undone_at / cancellation_requested_at set) -> archive
     called, 409 `already_sent`, no `inngest.send`; each also with a REVOKED grant (`isGranted` -> null) still archives and
     returns 409 (ungated), proving the lookup precedes the gates.
   - Pending row + revoked grant -> 403 `no_active_grant`, no `inngest.send`, no archive.
   - Pending row + edited draft (hash differs) -> 409 `draft_changed_since_approval`, no `inngest.send`, Sentry op
     `replay-draft-changed`.
   - Pending row `clicked_at` 24h old and a boundary case just under 23h: the former -> 409 `approval_expired`, no
     `inngest.send`, no archive, `warnSilentFallback` op `inngest-replay-stale`; the latter replays.
   - `approve_every_time` pending replay without `confirmed_typed`/hash echo -> 409 `requires_confirmation`, no send; with
     them -> replays (this case does NOT assert the template gate, which does not run for this tier).
   - `draft_one_click` replay: `authorize_template` is invoked at most once across the first click and the replay (the
     predicate returns `authorized` the second time) and nothing errors.
   - `no_artifact_in_pr_a` (unparseable `source_ref`) with a pending row — including one older than 23h (archive-failed,
     then re-click): NO `inngest.send`, draft archived, 200 `degraded: "no_artifact_in_pr_a"`, no `approval_expired`.
   - `writeActionSend` rejects `{code:"23505"}` -> plain 409 `already_sent`, no `inngest.send`, no archive (pins the cut
     23505 replay arm).
   - Lookup error -> 500 `internal_error`, no send, no archive.
   - Archive failure after a successful enqueue: the next click is a replay (same `id`) or the terminal arm and archives.
4. `apps/web-platform/test/api/dashboard/today/send-route.test.ts` — install the shared helper (default no row); no
   assertion changes.
5. `apps/web-platform/test/components/today-card.click.test.tsx` — replace the stale "200 with degraded:'enqueue_failed'"
   case with one 503 `enqueue_unavailable` case: in-place error copy shown, no acknowledged pill, card not archived, Send
   control re-enabled.
6. `apps/web-platform/test/hooks/use-action-send.test.tsx` (new, `renderHook`) — typed-confirm path only: 503 keeps
   `confirming` non-null with the same `expectedDraftPreviewHash` and sets the error; `acknowledged` stays false and
   `onAcknowledgedArchive` is never called; 409 `draft_changed_since_approval` and `approval_expired` set their copy; a
   409 `requires_confirmation` after confirm keeps the "please re-send" copy.

### Phase 2 — helper

Create `server/action-sends/enqueue-agent-spawn.ts` as specified. The helper unit test (Phase 1 item 1) goes GREEN.

### Phase 3 — route

Restructure `route.ts` to the flow in `## Proposed Solution`: hoist `parseSourceRef`, add the non-exported
`lookupActionSend`, add the terminal/expired arms before the gates, the replay branch after them, narrow the `try` to
`writeActionSend`, and route the enqueue through the helper. Replace the two duplicated stale comment blocks above the dispatch
(the existing file carries the same "PR-A (#4124): dispatch agent.spawn.requested ..." paragraph twice, back to back) with
one that states the ordering contract: durable approval row, then accepted enqueue, then archive; an un-accepted enqueue
leaves the draft visible and the row replayable for 23h. Delete `"enqueue_failed"` from the local `degraded` union. Keep
exports to HTTP methods plus `dynamic` (`cq-nextjs-route-files-http-only-exports`). The retry budget is 1.5s total
(`MAX_RETRIES` 2, 500ms base), so a deploy-restart blip longer than that surfaces as the 503 by design.

### Phase 4 — hook

Edit `hooks/use-action-send.ts` as specified; never edit `components/**`.

### Phase 5 — verification

- Targeted vitest runs of every test file above, plus `test/lint/action-class-typed-literals.test.ts` and the pre-existing
  `test/api/dashboard/today/*.test.ts` siblings.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (or the repo's typecheck script) green.
- Three-pattern union-narrowing grep (`cq-union-widening-grep-three-patterns`) for `enqueue_failed` over `apps/web-platform/{app,
  components,hooks,lib,server,test,e2e}` and `knowledge-base/` docs: literal (`"enqueue_failed"`), type-union position
  (`| "enqueue_failed"`), comparison position (`=== "enqueue_failed"`); the only residual allowed hits are
  `components/dashboard/acknowledged-pill.tsx` (#11212) and its unit test.
- Do NOT run the full-gate runner; do NOT run any live credentialed probe.

## Acceptance Criteria

- [ ] `rg 'from "@/server/inngest/client"' "apps/web-platform/app/api/dashboard/today/[id]/send/route.ts"` returns nothing,
      and `rg -n "sendInngestWithRetry" apps/web-platform/server/action-sends/enqueue-agent-spawn.ts` shows the send is
      wrapped.
- [ ] Every `agent.spawn.requested` send carries `id: agent-spawn-<actionSendId>`; the same id is sent on every retry
      attempt and on every replay (asserted by tests 1, 2, 3).
- [ ] After retries are exhausted the route returns 503 `{error:"enqueue_unavailable", action_send_id, retryable:true}` with
      `Retry-After: 5`, never calls the messages-archive update, and mirrors to Sentry once (`feature:"spawn-agent"`,
      `op:"inngest-enqueue"`, `extra.transient` set).
- [ ] A founder re-click on a pending row within 23h skips `writeActionSend`, re-dispatches the same id, archives on
      success; a re-click after that returns `not_a_draft`.
- [ ] The lookup precedes the gates: a terminal row is archived with 409 `already_sent` even when the grant is revoked; a
      pending row with a revoked grant is 403 and dispatches nothing.
- [ ] Replay is fail-closed: changed draft hash (409 `draft_changed_since_approval`), `clicked_at` older than 23h (409
      `approval_expired`), `undone_at` / `cancellation_requested_at` set (terminal arm), and `approve_every_time` without
      re-confirmation (409 `requires_confirmation`) all dispatch nothing.
- [ ] `no_artifact_in_pr_a` shapes never enqueue and still archive, including on the replay path and past 23h.
- [ ] A 23505 on the insert returns the plain 409 `already_sent` and dispatches nothing.
- [ ] The hook shows the in-place error on 503 in both the card path and the typed-confirm modal path; the modal stays open.
- [ ] `"enqueue_failed"` no longer appears in the route or `hooks/use-action-send.ts`; `components/**` has zero diff.
- [ ] No migration added or edited (migration 163 untouched); no change under `apps/web-platform/infra/`; no
      `.service-role-allowlist` change.
- [ ] Accepted residuals are stated in the PR body: a deterministic non-transient Inngest error 503s on every re-click until
      fixed (Sentry `extra.transient === false` distinguishes it); an edited draft behind a WORM row, and an expired
      approval, can only be discarded and recreated; a concurrent-click loser sees a cosmetic soft-success until refresh.
- [ ] The PR body names the duplicated-comment-block removal (so the diff is not read as churn), carries the Sentry query
      `feature:spawn-agent op:inngest-enqueue*` for operators, and contains `Closes #10543`, `Ref #11211`, `Ref #11212`;
      commits end with the Co-Authored-By trailer.
- [ ] Git history shows the RED test commit before the fix commit (test-first is verified by commit order, not by a PR
      sentence).

## Test Scenarios

(Layer labels: unit unless stated.)

- Given a transient `fetch failed` on the first two attempts, when the founder sends, then the draft is archived after the
  third attempt and all three attempts carry the same event id. (integration: route + real retry helper, fake timers)
- Given the enqueue fails after retries, when the founder sends, then the response is 503, the draft is still a draft, and
  the founder sees "Your approval is saved ... Click Send again".
- Given a pending approval row, when the founder clicks Send again within 23h, then no second row is written, the same id is
  re-dispatched, and the draft is archived.
- Given an acknowledged approval row on an unarchived draft whose grant was since revoked, when the founder clicks Send,
  then the draft is archived and the founder gets `already_sent` without typing anything.
- Given the grant was revoked after a pending row was written, when the founder re-clicks, then the replay is refused with
  403 and nothing is dispatched.
- Given the draft was edited after approval, when the founder re-clicks, then the replay is refused with 409
  `draft_changed_since_approval`.
- Given a pending row older than 23h, when the founder re-clicks, then the replay is refused with 409 `approval_expired`.
- Given two concurrent clicks, when one wins the insert, then the loser gets the plain 409 `already_sent` and the winner owns
  the dispatch (its failure leaves the draft for the next click).
- Regression: the pre-existing send-route matrix (tier gating, confirmation, template gate) is unchanged.

No browser/QA verification commands: the change is exercised entirely by the unit/integration layer; the e2e layer is not
justified for a status-code/ordering fix.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Six forks (response contract, replay scope, event id, gate placement, ambiguous failure, observability)
ruled 2026-10-26; follow-ups (pill deletion split, test rewrite) and a second round after plan review (R1-R4: 23h replay age
gate, lookup before the gates, 23505 arm cut, stale op kept) ruled the same day. See `## Decision Rulings`. No Product/UX
gate: no UI-surface file is created or edited (the hook is not under `components/`; the pill file is deliberately left
untouched and tracked in #11212); the only visible change is an inline error string rendered by existing error UI.

**UI-surface determination:** none of `## Files to Edit` / `## Files to Create` matches the shared UI-surface glob superset
(`components/**/*.{tsx,...}`, `app/**/page.tsx`, ...). `app/api/**/route.ts` is backend; test files are not UI surfaces.

**GDPR / compliance:** the route is a regulated-data surface by path (`action_sends` is the Art. 5(2) accountability
record), so `soleur:gdpr-gate` ran against this plan (advisory, headless): see the Compliance note below.

**Compliance note (gdpr-gate, advisory; this is not legal review).** `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`,
`GDPR-Art-17-caller`, `GDPR-Chapter-V` and `GDPR-Art-9`: no finding — the plan adds no column, table, foreign key, vendor,
SDK or environment variable and reads an existing owner-RLS row. Accountability (Art. 5(2)) is preserved and strengthened:
the replay never writes a second approval row and refuses to dispatch when the draft body no longer matches the WORM row's
`per_send_body_sha256`, so the approval stays bound to the body the founder saw. One `Suggestion` (API-layer): the new Sentry
`extra` payloads carry identifiers only (`userId`, `messageId`, `actionSendId`, `errorName`, `replay`, `transient`) — never
`draft_preview` or the caught error message (which may embed ids); keep it that way in review. No Critical finding, so no
`compliance-posture.md` write and no `compliance/critical` issue.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder approves a Concierge action on a dashboard card and sees it
  vanish with an "Acknowledged" pill while no agent ever runs; or, after this change, a replay that fails to dispatch leaves
  a card stuck with an error.
- **If this leaks, the user's workflow is exposed via:** a replay that dispatches an approval after the grant was revoked,
  after the draft body changed, or after the 24h dedup window (a stale approval acting on the founder's GitHub, or a
  duplicate artifact); mitigated by re-running every gate on the dispatch arm, the draft-hash check, and the 23h replay cap.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** one founder losing one approved action is recoverable (re-click) and
  non-destructive, so not a single-user incident (the CTO devex review concurred); a pattern of silent drops during an
  Inngest outage would be the aggregate trust problem this fixes.

## Observability

```yaml
liveness_signal:
  what: Sentry events feature=spawn-agent with op inngest-enqueue (exhausted enqueue), inngest-enqueue-replay (recovered replay) and inngest-replay-stale (expired replay refused)
  cadence: per send click
  alert_target: Sentry issue stream for the web-platform project (no new alert rule, CTO D6/R4)
  configured_in: apps/web-platform/app/api/dashboard/today/[id]/send/route.ts
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (SENTRY_DSN of the web-platform app)
  fail_loud: HTTP 503 enqueue_unavailable to the caller plus a Sentry event tagged feature=spawn-agent op=inngest-enqueue
failure_modes:
  - mode: Inngest unreachable so the enqueue is exhausted
    detection: Sentry event op=inngest-enqueue and the 503 in the route response log
    alert_route: Sentry issue stream; the platform Inngest outage signals fire independently
  - mode: founder never re-clicks so an approved row stays unacknowledged
    detection: Sentry op=inngest-enqueue followed by no op=inngest-enqueue-replay for the same actionSendId
    alert_route: tracked for a future sweeper in #11211 (re-evaluation criteria recorded there)
  - mode: replay refused (draft edited after approval, or approval older than 23h)
    detection: Sentry ops replay-draft-changed and inngest-replay-stale
    alert_route: Sentry issue stream
logs:
  where: pino logs shipped to Better Stack plus Sentry breadcrumbs
  retention: per the existing Better Stack and Sentry retention settings
discoverability_test:
  command: rg -o -m1 inngest-enqueue-replay apps/web-platform/app/api/dashboard/today
  expected_output: inngest-enqueue-replay
```

(The discoverability probe is a wiring grep confirming the recovery op exists in the route, not a liveness probe; the live
read is the credentialed Sentry search `feature:spawn-agent op:inngest-enqueue*`, outside the sandboxed preflight probe.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Use sendInngestWithRetry (apps/web-platform/server/inngest/send-with-retry.ts, already used by schedule-reminder and the webhook routes)" [brief] | Phase 2 `enqueue-agent-spawn.ts` | mapped |
| 2 | "with a stable event id" [brief] | Phase 2 event id `agent-spawn-${actionSendId}` | mapped |
| 3 | "and a replay path" [brief] | Phase 3 lookup-before-gates replay arm | mapped |
| 4 | "do not archive the draft unless the enqueue succeeded or is durably recorded for replay" [brief] | Phase 3 flow (503 leaves the draft; the unacknowledged WORM row is the durable record) | mapped |
| 5 | "add failing tests first" [brief] | Phase 1 | mapped |
| 6 | "PR body uses 'Closes #10543'" [brief] | Acceptance Criteria PR-body line | mapped |
| 7 | "no production-mutating act" [brief standing rules] | Acceptance Criteria (no migration, no infra, no live probe) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `enqueue-agent-spawn.ts` | "Use sendInngestWithRetry" (asks 1-2) | asked |
| `route.ts` lookup, replay arm, archive-after-accept | "a replay path" and "do not archive the draft unless the enqueue succeeded" (asks 3-4) | asked |
| 23h replay cap and `approval_expired` / terminal arms | — | inferred — justification: the consumer can leave an executed run NULL/NULL and Inngest's dedup expires at ~24h, so an uncapped replay could post a second artifact (CTO R1). |
| `hooks/use-action-send.ts` 503 + 409 handling + union narrowing | — | inferred — justification: otherwise a new 503/409 renders as the generic "Send failed (NNN)" and the founder would not know the approval is saved or what to do; the stale `enqueue_failed` union would rot. |
| All test files and the shared `action-sends-row-mock.ts` helper | "add failing tests first" (ask 5) | asked |
| Deferral issues #11211, #11212 | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for each deferred capability. |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 11 | Estimated changed lines: ~600 (about 230 production, 370 test)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`
- `apps/web-platform/hooks/use-action-send.ts`
- `apps/web-platform/test/api/dashboard/today/send-route.spawn.test.ts`
- `apps/web-platform/test/api/dashboard/today/send-route.test.ts`
- `apps/web-platform/test/components/today-card.click.test.tsx`

## Files to Create

- `apps/web-platform/server/action-sends/enqueue-agent-spawn.ts`
- `apps/web-platform/test/helpers/action-sends-row-mock.ts`
- `apps/web-platform/test/server/action-sends/enqueue-agent-spawn.test.ts`
- `apps/web-platform/test/api/dashboard/today/send-route.replay.test.ts`
- `apps/web-platform/test/hooks/use-action-send.test.tsx`
- `knowledge-base/project/specs/feat-one-shot-10543-dashboard-send-retry/tasks.md`

## Deferrals (tracked)

- #11211 — dispatch-recovery sweeper for unacknowledged `action_sends` rows (re-evaluate when Sentry `spawn-agent /
  inngest-enqueue` fires and rows with NULL/NULL ack older than 1h exist with the message still a draft). Notes recorded on
  the issue: a sweeper must filter on `messages.status = 'draft'` or a parseable `source_ref` (`no_artifact_in_pr_a` rows are
  permanently NULL/NULL by design), must honor the 23h cap, and `approval_expired` / `draft_changed_since_approval` drafts
  need a discard-and-recreate path.
- #11212 — delete the dead `"queued"` pill variant and `"enqueue_failed"` prop value in `acknowledged-pill.tsx`
  (re-evaluate on the next PR that touches `components/dashboard`).

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled.
- The new lookup adds one `action_sends` SELECT to every send click; every existing send-route test harness returns `{}` for
  unknown tables, so Phase 1 item 0 and 4 must land before any RED run (otherwise the RED failure is a harness TypeError, not
  the behavior under test).
- `sendInngestWithRetry` retries only transient network errors; a 4xx from Inngest is not retried but still maps to 503 here
  by design (the row makes replay safe). A deterministic 4xx will 503 on every re-click until fixed; Sentry
  `op:inngest-enqueue` with `extra.transient: false` distinguishes it.
- Edited-draft edge: after an approval row exists, an edit makes the dispatch arm fail closed with 409
  `draft_changed_since_approval`. With `approve_every_time` the founder first gets a 409 `requires_confirmation` (fresh
  hash), then, after re-confirming, the 409 `draft_changed_since_approval` — two consecutive 409s. The founder's exit is the
  existing Discard action; recorded as an accepted residual.
- The 23h cap is measured with the server clock against `clicked_at` (a DB-default timestamp); clock skew of minutes is
  absorbed by the 1h margin, but the margin is a plan-level choice, not verified against the DB clock.
- The route's `reportSilentFallback` calls must pass `null` as the first argument (message path) with `errorName` in `extra`
  — passing the caught Error loses the `feature`/`op` tags to the pino mirror (#10542 ruling, #8629).
- The #8719 `spawn-agent-dead-letter` alert requires ALL of `feature = spawn-agent`, `op = agent-on-spawn-requested` and a
  `reason` in a fixed list (`issue-alerts.tf`, verified), so the new ops `inngest-enqueue-replay` and
  `inngest-replay-stale` and the existing `inngest-enqueue` cannot page it and no emit site that alert filters on is removed.
- The exhausted-enqueue `message:` string is changed deliberately: the old text ("manual retry via new messages row") asserts
  behavior that no longer exists; operator dashboards group on `feature`/`op`, which are unchanged.
- `vitest.config.ts` collects `test/**/*.test.ts` (node) and `test/**/*.test.tsx` (jsdom); every new test path above matches,
  and `test/helpers/action-sends-row-mock.ts` is a helper, not a collected suite.
- Do not touch migration 163, draft PRs #10692 / #10936 or their worktrees, and make no production-mutating act.
