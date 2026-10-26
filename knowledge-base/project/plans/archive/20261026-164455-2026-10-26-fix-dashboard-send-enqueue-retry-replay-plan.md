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

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Proposed Solution (flow, bodies, client), Phase 1 (test plan), Acceptance Criteria, Test Scenarios,
Decision Rulings, Risks.
**Review agents used:** repo-research-analyst, learnings-researcher, functional-discovery (none found), CTO (rulings D1-D6,
R1-R4, S1-S4), plan-review panel (DHH, Kieran, code-simplicity, CTO devex), security-sentinel, spec-flow-analyzer,
test-design-reviewer, gdpr-gate (advisory). Mechanical gates 4.6-4.13 passed (User-Brand Impact, Observability, no PAT
shape, no UI surface, no store, no guard deliverable, Scope Check compliant, no new autonomous task).

### Key Improvements

1. Security: a replay is now bound to the whole approval (draft hash, `action_class`, `tier_at_send`), the 23h age check
   fails closed on an unparseable timestamp, response bodies and Sentry `extra` are constant-field and test-pinned, and the
   archive update filters `status = 'draft'`.
2. Flow: ungated terminal / no-dispatch / expired arms; hash refusal precedes the gates so a refused replay never triggers the
   template gate's first-send authorization; expired approvals archive so no card is left as a permanent 409 dead end.
3. Tests: a stateful store honoring `.eq()` filters and column projection, real archive state transitions, a vacuous
   template-gate case replaced by refusal cases, arm-order and boundary pins, `[guard]` labels for characterization cases.

### New Considerations Discovered

- GitHubCard and KbDriftCard bind no `disabled` to any hook flag and have no Discard/Edit, so every client state must be
  recoverable by a refresh; copy names no affordance (CTO S1).
- A concurrent-click loser must not archive its own card client-side (`send_in_progress`, CTO S2).
- The consumer's `persist-failure` and settle writes can leave NULL/NULL on an executed run, which is why replay is capped
  at 23h (CTO R1).

## Overview

The founder-callable send route (`apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`) writes the WORM
`action_sends` approval row, then issues ONE bare enqueue of the spawn event with no retry and no event id, then flips
the draft to archived. When that single enqueue throws, the route still archives the draft and answers 200 with a
degraded marker, so the founder's approved Concierge action is silently lost. Worse, the loss is unrecoverable by the
founder: the draft is already archived, so a re-click is refused with 409 `not_a_draft` (the client shows a generic
"Send failed (409)") and nothing re-dispatches the saved approval row. (An earlier draft of this paragraph said a
re-click hit the unique constraint and read as `already_sent`; the published route archives before any re-click, so
the `not_a_draft` gate answers first: corrected after review, history seat.)

This plan routes the enqueue through the shared retry helper with a stable event id, makes the archive conditional on the
enqueue having been accepted, turns an exhausted enqueue into a retryable 503 that leaves the draft visible, and adds a
founder re-click replay path that re-dispatches the same event id from the already-committed approval row (bounded to 23h
so Inngest's 24h dedup window is never straddled). All technical forks were ruled by the CTO agent, including a second
round after plan review (see `## Decision Rulings

All rows are persisted in `knowledge-base/project/specs/feat-one-shot-10543-dashboard-send-retry/decision-challenges.md`.
What the implementation must honor (later rounds supersede D2/D4/D5 where they conflict):

- D1. Exhausted enqueue returns **503** `{error:"enqueue_unavailable", action_send_id, retryable:true}` with
  `Retry-After: 5`; the draft stays `draft`; `no_artifact_in_pr_a` still archives and returns 200; `"enqueue_failed"` is
  deleted from the route and the hook unions (the pill file is left untouched, #11212).
- D3. Event id `agent-spawn-${actionSendId}`.
- R1. Replay age gate at 23h (`clicked_at` against the server clock, fail-closed on an unparseable timestamp). The consumer
  can leave NULL/NULL on an executed run and Inngest's dedup expires at ~24h, so a visible expiry beats a possible second
  GitHub artifact. The 23h margin is a plan-level choice, not verified against the DB clock.
- R2 + S4. The read-only `action_sends` lookup runs right after the `not_a_draft` / known-action-class checks, before the
  gates. Ungated arms (they dispatch nothing): a terminal row (acknowledged, failed, undone or cancel-requested) archives
  and returns 409 `already_sent`; a pending row whose `source_ref` is non-empty but unparseable, or empty (S3), archives and
  returns 200 (`degraded: "no_artifact_in_pr_a"` when non-empty); a pending parseable row older than 23h archives and
  returns 409 `approval_expired` (S1). Replay checks: the draft-hash check (NULL stored hash is a mismatch) runs before
  `isGranted`; the `row.action_class` / `row.tier_at_send` vs current class and `grant.tier` check runs after `isGranted`
  and the tier switch and before the template gate and typed-confirm gate; both return 409
  `draft_changed_since_approval` WITHOUT archiving (recoverable). The pending arm then passes ALL gates, skips only the
  insert, and dispatches with the same event id.
- R3 + S2. A 23505 on the insert returns a distinct 409 `send_in_progress` (no re-lookup, dispatch or archive); the hook
  renders "Another send is in progress - try again in a moment" and does NOT acknowledge or archive the card; the next click
  finds the pending row and replays.
- R4. Keep `reportSilentFallback` on exhausted retries (feature `spawn-agent`, op `inngest-enqueue`, `extra.replay`,
  `extra.transient`); ops `inngest-enqueue-replay` (successful replay, warning), `inngest-replay-stale` (expiry, warning)
  and `replay-draft-changed` (refused replay). `extra.attempts` is dropped (the helper does not surface it). No Terraform
  change and no new metric.
- S1. The client surface is `hooks/use-action-send.ts` only: GitHubCard and KbDriftCard bind no `disabled` to any hook
  flag, so a `blocked` flag would need a `components/**` edit (out of bounds); `approval_expired` therefore archives the
  draft so the card clears, with card-neutral copy that names no affordance.

## Open Code-Review Overlap

None. (Queried open `code-review` issues for every path in `## Files to Edit` / `## Files to Create`: zero matches.)

## Proposed Solution

### New route flow

Gates that exist today and stay in this order: origin check, auth, message load, `status === "draft"` (else 409
`not_a_draft`), known action class. Then:

```text
parsed = parseSourceRef(source_ref)                       // hoisted; pure and local
draftPreviewHash = sha256(draft_preview)                  // hoisted (already computed once today, after the gates)
existing = lookupActionSend(cookieClient, userId, message.id)   // non-exported function in route.ts
  select id, per_send_body_sha256, action_class, tier_at_send, clicked_at, acknowledged_at, failure_reason,
         undone_at, cancellation_requested_at   (filtered by message_id AND user_id)
  lookup error  -> reportSilentFallback, 500 internal_error
  terminal row (acknowledged_at, failure_reason, undone_at or cancellation_requested_at set)
                -> archive (.eq status draft), 409 already_sent                      [UNGATED; 409 even if archive fails]
  pending row, source_ref empty or unparseable (nothing would be dispatched)
                -> archive, 200 {id, action_send_id: row.id, artifact_view_url:"", degraded: "no_artifact_in_pr_a" when
                   source_ref non-empty}                                              [UNGATED]
  pending row, parsed, NOT (now - clicked_at <= 23h)      // unparseable/NaN/future clicked_at fails closed
                -> archive, warnSilentFallback op "inngest-replay-stale", 409 approval_expired            [UNGATED]
  pending row, parsed, per_send_body_sha256 is NULL or != draftPreviewHash
                -> reportSilentFallback op "replay-draft-changed", 409 draft_changed_since_approval (draft kept)
  pending row, parsed  -> replay = true
  no row               -> replay = false

isGranted -> tier switch
  replay: row.action_class != actionClass or row.tier_at_send != grant.tier
                -> reportSilentFallback op "replay-draft-changed", 409 draft_changed_since_approval (draft kept)
template gate -> approve_every_time typed-confirm + hash echo                          (unchanged)

replay:    skip the insert; actionSendId = row.id
no row:    try { writeActionSend(...) } catch
              23505 -> 409 send_in_progress (no dispatch, no archive)
              other -> 500 send_failed (unchanged)        // the try wraps ONLY writeActionSend

parsed     -> enqueueAgentSpawn(...)   // sendInngestWithRetry + id agent-spawn-<actionSendId>
   throws after retries -> reportSilentFallback(null, {feature:"spawn-agent", op:"inngest-enqueue", ...})
                           503 enqueue_unavailable + Retry-After: 5, draft NOT archived
   ok and replay        -> warnSilentFallback op "inngest-enqueue-replay"
no parseable source_ref (first click) -> unchanged: no enqueue, archive, 200 (degraded "no_artifact_in_pr_a" when non-empty)

archive draft: update ... .eq("id").eq("user_id").eq("status","draft")  (unchanged error handling otherwise)
200 {id, action_send_id, artifact_view_url, degraded?}
```

Response bodies carry constant fields only: 409s are `{error, message_id}` (never `failure_reason`, `clicked_at`, the stored
hash or any hash value); the 503 is `{error, action_send_id, retryable}`. The draft-hash comparison reuses the single
`draftPreviewHash` value; `per_send_body_sha256 = sha256(bodyContent)` and `bodyContent = draftPreview`, so the values are
comparable.

### Helper module (cookie client only; no service-role, no `.service-role-allowlist` change)

`apps/web-platform/server/action-sends/enqueue-agent-spawn.ts` — exports `enqueueAgentSpawn({founderId, messageId,
actionClass, sourceRef, actionSendId})`, which calls `sendInngestWithRetry(() => inngest.send({ id, name:
"agent.spawn.requested", data }), { feature: "spawn-agent", eventId: id })` with `id = agent-spawn-${actionSendId}`
(`agentSpawnEventId` is exported only if a test needs it). `actionClass` is typed `ActionClass` (no `as string` near the
send, so the `action-class-typed-literals` sentinel stays green). `installationId` stays OMITTED from `data` (consumer
invariant I1). The route no longer imports `@/server/inngest/client`.

### Client (hook only; `components/**` is deliberately untouched)

`apps/web-platform/hooks/use-action-send.ts`, in BOTH `onSend` and `onConfirmTyped` unless noted:

- 503 `enqueue_unavailable`: "Your approval is saved, but we couldn't start the agent. Click Send again to retry."
  `acknowledged` stays false, `onAcknowledgedArchive` is not called, the typed-confirm modal stays open with the error
  rendered in-modal.
- 409 `approval_expired` and 409 `not_a_draft`: "This approval can no longer run. Refresh to update this card." (the
  route archived the draft, so the refresh clears the card; no affordance is named and no new draft is promised).
- 409 `draft_changed_since_approval`: "This draft changed after you approved it. Restore the approved text or refresh."
- 409 `send_in_progress`: "Another send is in progress - try again in a moment"; does NOT set `acknowledged` and does NOT
  call `onAcknowledgedArchive`.
- 403 fallback (when `denyReasonCopy` has no entry): "Permissions changed since you approved. This action can't run."
- `onConfirmTyped` 409 `requires_confirmation`: keep the "please re-send" copy AND adopt the fresh
  `expected_draft_preview_hash` from the response body into `confirming`, so a retype does not loop on the stale hash; any
  other 409 falls through to `Send failed (409)`.
- Terminal rows keep returning `already_sent` (soft success): the mounted LeaderLoopStatus is driven by the real row state,
  so a failed or undone run renders its true state, not an "Acknowledged" claim.
- Narrow the `degraded` unions to `"no_artifact_in_pr_a" | undefined`; refresh the stale header comment about
  `enqueue_failed`.

## Implementation Phases

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

Write every test below BEFORE any production edit, with the test commit ahead of the fix commit in history. Run each file
with a targeted `./node_modules/.bin/vitest run <file>` from `apps/web-platform` (never a full-suite or gate runner).
RED must be behavioral for the route and hook tests (`writeActionSend` called, no `inngest.send`, wrong status); a
module-not-found RED is acceptable only for the new-helper unit test. Cases that already pass today are
CHARACTERIZATION guards, not RED, and are labelled `[guard]` so a green run of them is not read as a broken harness. Route
tests mock at the supabase `from(...)` level through ONE shared stateful helper, never at a helper-module level, and pin the
clock with `vi.setSystemTime` wherever the 23h gate is read.

0. `apps/web-platform/test/helpers/action-sends-row-mock.ts` (new, shared by the three route test files): a small in-memory
   store with (a) an `action_sends` table whose `select(cols).eq(...).eq(...).maybeSingle()` HONORS the `.eq()` filters
   (message_id and user_id) and PROJECTS only the requested columns, so dropping a filter or a column from the route's
   select goes red; (b) a `messages` table whose archive `update(...).eq(id).eq(user_id).eq("status","draft")` flips `status`
   in the store, so "re-click after archive" and "archive failure then next click" are real state transitions (an archive
   failure is an injectable error); (c) settable lookup/insert errors. Default store: no `action_sends` row, one draft
   message. It also exposes the hoisted `warnSilentFallback` / `reportSilentFallback` mocks so op assertions are possible.
1. `apps/web-platform/test/server/action-sends/enqueue-agent-spawn.test.ts` (unit)
   - `inngest.send` receives `id` equal to `agent-spawn-<actionSendId>` and `data` has exactly `{founderId, messageId,
     actionClass, sourceRef, actionSendId}` (`toStrictEqual`; no `installationId`).
   - With the REAL `sendInngestWithRetry` and `vi.useFakeTimers`: `TypeError("fetch failed")` on attempts 1 and 2 then
     success resolves after `advanceTimersByTimeAsync`, and the SAME `id` is sent on all 3 attempts.
   - A non-transient `Error` is not retried (one call) and rejects; three transient failures reject after exactly 3 calls
     (attach the `rejects` expectation BEFORE advancing timers to avoid an unhandled-rejection false red).
2. `apps/web-platform/test/api/dashboard/today/send-route.spawn.test.ts` (rewrite tests 3 and 4; add id assertion)
   - Tests 1b/2: the `inngest.send` argument `id` equals `agent-spawn-<AS_ID>` (the data-shape assertion lives in item 1).
   - Replaced test 3: `inngest.send` rejects (non-transient) -> **503**, body `toStrictEqual({error:
     "enqueue_unavailable", action_send_id: AS_ID, retryable: true})`, header `Retry-After` is `"5"`, `callOrder` equals
     `["writeActionSend", "inngest.send-throw"]` (NO `messages-archive`), `reportSilentFallback` called once with first
     argument `null`, `feature: "spawn-agent"`, `op: "inngest-enqueue"`, `extra.replay === false`, `extra.transient ===
     false`; a sibling case exhausts `TypeError("fetch failed")` with fake timers -> `extra.transient === true`.
   - Replaced test 4 (route-level, `vi.useFakeTimers`): transient failure on attempt 1, success on attempt 2 -> 200,
     archived once, `inngest.send` called twice with the same `id`.
   - Sentry `extra` key set: for each of the three ops the `extra` keys equal exactly `{userId, messageId, actionSendId,
     errorName, replay, transient}` (the exhausted op) or `{userId, messageId, actionSendId, replay}` (the others); no
     `draft_preview`, hash or error message value appears.
3. `apps/web-platform/test/api/dashboard/today/send-route.replay.test.ts` (new; stateful store; the pending row's id differs
   from `AS_ID`, so a replay that dispatched the INSERT's id would go red; any case that reaches the real backoff uses fake
   timers)
   - Replay: pending row within 23h with matching hash -> `writeActionSend` NOT called, `inngest.send` called with the ROW's
     `action_send_id` and `id`, draft archived (the stored row status becomes archived), 200, op `inngest-enqueue-replay`; a re-click afterwards
     returns 409 `not_a_draft` (real state transition).
   - Replay whose enqueue fails again -> 503, draft still `draft`, `extra.replay === true`.
   - Terminal rows via `it.each` (acknowledged_at / failure_reason / undone_at / cancellation_requested_at set) -> archive,
     409 `{error:"already_sent", message_id}` (`toStrictEqual`; no `failure_reason` or timestamp echoed), no `inngest.send`;
     each also with a REVOKED grant (`isGranted` -> null) still archives and returns 409 (proves the lookup precedes the
     gates), and one row that is acknowledged AND older than 23h returns `already_sent`, not `approval_expired` (arm order).
     Archive failure still returns 409.
   - `[guard]` Pending row + revoked grant -> 403 `no_active_grant`, no `inngest.send`, no archive.
   - Draft-hash refusal: pending row + edited draft, and pending row with `per_send_body_sha256 = NULL` -> 409
     `draft_changed_since_approval`, draft kept, no `inngest.send`, op `replay-draft-changed`, and `isGranted` /
     `runTemplateGate` NOT called (the check precedes the gates; revoked grant + edited draft is 409, not 403).
   - Tier/class refusal: pending row written under `draft_one_click` while the grant is now `approve_every_time` (and a row
     with a different `action_class`) -> 409 `draft_changed_since_approval`, no `inngest.send`, and `runTemplateGate` NOT
     called (the check follows `isGranted` and precedes the template gate); a 409 from this arm never reaches typed-confirm.
   - Template-gate refusal on replay: pending row + `runTemplateGate` -> deny -> 403 `template_not_authorized`, no
     `inngest.send`, no archive.
   - 23h gate with `vi.setSystemTime`: `clicked_at` 22h59m ago replays; 23h01m ago -> archive, 409 `approval_expired`
     (`toStrictEqual` body), no `inngest.send`, `warnSilentFallback` op `inngest-replay-stale`; a garbage or null
     `clicked_at` and a future `clicked_at` -> `approval_expired` (fail-closed, no NaN replay).
   - `approve_every_time` pending replay without `confirmed_typed`/hash echo -> 409 `requires_confirmation`, no send; with
     them -> replays.
   - Unparseable non-empty `source_ref` with a pending row (archive-failed, then re-click) and an empty `source_ref` with a
     pending row, including one older than 23h and with a revoked grant: NO `inngest.send`, archive, 200 (`degraded:
     "no_artifact_in_pr_a"` for the non-empty case only), no `approval_expired`, no 403.
   - `[guard]` `writeActionSend` rejects `{code:"23505"}` -> 409 `{error:"send_in_progress", message_id}`, no
     `inngest.send`, no archive; a pending row for ANOTHER user_id (store filter) falls into the no-row arm.
   - Lookup error -> 500 `internal_error`, no send, no archive.
   - Archive failure after a successful enqueue (injected store error): the next click replays with the same `id` (or takes
     the terminal arm if acknowledged) and archives.
4. `apps/web-platform/test/api/dashboard/today/send-route.test.ts` — install the shared helper (default no row); no
   assertion changes.
5. `apps/web-platform/test/components/today-card.click.test.tsx` — replace the stale "200 with degraded:'enqueue_failed'"
   case with one 503 `enqueue_unavailable` case: in-place error copy shown, no acknowledged pill, card not archived, Send
   control re-enabled.
6. `apps/web-platform/test/hooks/use-action-send.test.tsx` (new, `renderHook`) covering BOTH `onSend` and `onConfirmTyped`:
   503 sets the error, `acknowledged` stays false, `onAcknowledgedArchive` never called, and (confirm path) `confirming`
   stays non-null with the same hash; 409 `approval_expired` / `not_a_draft` / `draft_changed_since_approval` /
   `send_in_progress` each set their copy, and `send_in_progress` never acknowledges or archives; 403 `no_active_grant`
   with no `denyReasonCopy` shows the generic "Permissions changed" copy; a confirm-path 409 `requires_confirmation`
   adopts the fresh `expected_draft_preview_hash` from the body and keeps the "please re-send" copy.

### Phase 2 — helper

Create `server/action-sends/enqueue-agent-spawn.ts` as specified. The helper unit test (Phase 1 item 1) goes GREEN.

### Phase 3 — route

Restructure `route.ts` to the flow in `## Proposed Solution`: hoist `parseSourceRef` and `draftPreviewHash`, add the
non-exported `lookupActionSend`, add the ungated arms (terminal, no-dispatch pending, expired) and the pre-`isGranted` hash
refusal, add the post-`isGranted`/tier-switch class-and-tier refusal before the template gate, skip the insert on replay,
narrow the `try` to `writeActionSend` (23505 -> `send_in_progress`), add `.eq("status","draft")` to the archive update, and
route the enqueue through the helper. Replace the two duplicated stale comment blocks above the dispatch (the existing file
carries the same "PR-A (#4124): dispatch agent.spawn.requested ..." paragraph twice, back to back) with one that states the
ordering contract: durable approval row, then accepted enqueue, then archive; an un-accepted enqueue leaves the draft
visible and the row replayable for 23h. Delete `"enqueue_failed"` from the local `degraded` union. Keep exports to HTTP
methods plus `dynamic` (`cq-nextjs-route-files-http-only-exports`). The retry budget is 1.5s total (`MAX_RETRIES` 2, 500ms
base), so a deploy-restart blip longer than that surfaces as the 503 by design. `sendInngestWithRetry` logs the raw error to
pino on a transient retry (the helper is not edited); this is an accepted residual and the Sentry payloads stay
identifier-only.

### Phase 4 — hook

Edit `hooks/use-action-send.ts` as specified in `## Proposed Solution` > Client; never edit `components/**`.

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
      attempt and on every replay, and a replay uses the ROW's id (asserted by tests 1, 2, 3).
- [ ] After retries are exhausted the route returns 503 `{error:"enqueue_unavailable", action_send_id, retryable:true}` with
      `Retry-After: 5`, never calls the messages-archive update, and mirrors to Sentry once (`feature:"spawn-agent"`,
      `op:"inngest-enqueue"`, `extra.transient` set).
- [ ] A founder re-click on a pending row within 23h skips `writeActionSend`, re-dispatches the same id, archives on
      success; a re-click after that returns `not_a_draft`.
- [ ] The lookup precedes the gates for the ungated arms: a terminal row is archived with 409 `already_sent` even when the
      grant is revoked (and wins over the 23h expiry); a pending row with a revoked grant is 403 and dispatches nothing.
- [ ] Replay is fail-closed and dispatches nothing on: a changed or NULL stored draft hash and a changed `action_class` /
      `tier_at_send` (409 `draft_changed_since_approval`, draft kept, `runTemplateGate` not called), `clicked_at` older than
      23h or unparseable (archive + 409 `approval_expired`), a template-gate denial (403), and `approve_every_time`
      without re-confirmation (409 `requires_confirmation`).
- [ ] `no_artifact_in_pr_a` and empty-`source_ref` shapes never enqueue and still archive, including on the replay path, past
      23h and with a revoked grant, without a spurious 403/409.
- [ ] A 23505 on the insert returns 409 `send_in_progress`, dispatches and archives nothing, and the hook neither
      acknowledges nor archives the card.
- [ ] The 409/503 bodies carry constant fields only (no `failure_reason`, `clicked_at` or hash value); Sentry `extra` key
      sets are pinned by test.
- [ ] The archive update filters `status = 'draft'`.
- [ ] The hook shows the specified copy for 503, `approval_expired`, `not_a_draft`, `draft_changed_since_approval`,
      `send_in_progress` and the generic 403 in both `onSend` and `onConfirmTyped`; the modal stays open on 503; a
      confirm-path `requires_confirmation` adopts the fresh hash.
- [ ] `"enqueue_failed"` no longer appears in the route or `hooks/use-action-send.ts`; `components/**` has zero diff.
- [ ] No migration added or edited (migration 163 untouched); no change under `apps/web-platform/infra/`; no
      `.service-role-allowlist` change.
- [ ] Accepted residuals are stated in the PR body: a deterministic non-transient Inngest error 503s on every re-click until
      fixed (Sentry `extra.transient === false` distinguishes it); a draft refused for changed content or tier stays
      visible with neutral copy (GitHubCard/KbDriftCard have no Edit, so that state is effectively Stripe-only); an expired
      approval is archived and whether the producer proposes a fresh draft is unverified; the transient-retry log line
      carries the raw error (helper not edited).
- [ ] The PR body names the duplicated-comment-block removal (so the diff is not read as churn), carries the Sentry query
      `feature:spawn-agent op:inngest-enqueue*` for operators, and contains `Closes #10543`, `Ref #11211`, `Ref #11212`;
      commits end with the Co-Authored-By trailer.
- [ ] Git history shows the RED test commit before the fix commit (test-first is verified by commit order, not by a PR
      sentence).

## Test Scenarios

(Layer labels: all unit under this repo's taxonomy — mocked supabase/Inngest, no real DB or service.)

- Given a transient `fetch failed` on the first two attempts, when the founder sends, then the draft is archived after the
  third attempt and all three attempts carry the same event id (route + real retry helper, fake timers).
- Given the enqueue fails after retries, when the founder sends, then the response is 503, the draft is still a draft, and
  the founder sees "Your approval is saved ... Click Send again".
- Given a pending approval row, when the founder clicks Send again within 23h, then no second row is written, the ROW's id
  is re-dispatched, and the draft is archived.
- Given an acknowledged approval row on an unarchived draft whose grant was since revoked, when the founder clicks Send,
  then the draft is archived and the founder gets `already_sent` without typing anything.
- Given the grant was revoked after a pending row was written (draft unchanged), when the founder re-clicks, then the replay
  is refused with 403 and nothing is dispatched.
- Given the draft was edited after approval (even with a revoked grant), when the founder re-clicks, then the replay is
  refused with 409 `draft_changed_since_approval` before any gate runs and the draft stays visible.
- Given a pending row older than 23h, when the founder re-clicks, then the draft is archived and the replay is refused with
  409 `approval_expired`.
- Given two concurrent clicks, when one wins the insert, then the loser gets 409 `send_in_progress` (its card stays), and
  the next click finds the pending row and replays the same id.
- Regression: the pre-existing send-route matrix (tier gating, confirmation, template gate) is unchanged.

No browser/QA verification commands: the change is exercised entirely by the unit layer; the e2e layer is not justified for
a status-code/ordering fix.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Six forks (response contract, replay scope, event id, gate placement, ambiguous failure, observability)
ruled 2026-10-26; follow-ups (pill deletion split, test rewrite), a second round after plan review (R1-R4: 23h replay age
gate, lookup before the gates, 23505 re-lookup cut, stale op kept) and a third round after deepen-plan (S1-S4: expired
approvals archived, `send_in_progress` for 23505, no-dispatch pending rows ungated, hash check before the gates) ruled the
same day. See `## Decision Rulings`. Product/UX
review is not required because no UI-surface file is created or edited (the hook is not under `components/`; the pill file is deliberately left
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
  Inngest unavailability would be the aggregate trust problem this fixes.

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
    alert_route: Sentry issue stream; the platform Inngest liveness signals fire independently
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
| `hooks/use-action-send.ts` 503 + 409/403 handling + union narrowing | — | inferred — justification: otherwise a new 503/409 renders as the generic "Send failed (NNN)" and the founder would not know the approval is saved or what to do; the stale `enqueue_failed` union would rot. |
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
  permanently NULL/NULL by design), must honor the 23h cap, and a refused replay needs a recovery path: `approval_expired` drafts are now archived by the route
  (CTO S1) and whether the producer proposes a fresh draft is unverified, while `draft_changed_since_approval` drafts stay
  visible.
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
- Edited-draft edge: after an approval row exists, an edit makes the replay fail closed with 409
  `draft_changed_since_approval` BEFORE any gate or typed-confirm (so no double-409 and no template-gate side effect); the
  draft is kept because the state is recoverable (restore the approved text). Only Stripe cards expose Edit.
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
