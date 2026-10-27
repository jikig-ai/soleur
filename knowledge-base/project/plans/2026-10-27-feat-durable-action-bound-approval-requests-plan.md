---
title: "feat: durable, action-bound approval requests (HITL approval queue, slice 1)"
date: 2026-10-27
slug: durable-action-bound-approval-requests
branch: feat-hitl-approval-queue
issue: 4672
closes: 4672
type: feat
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
folds_in: [10443]
epic: 9601
pr: 11289
---

# feat: durable, action-bound approval requests (HITL approval queue, slice 1)

## Overview

Replace the in-memory review gate for the highest-risk gated agent tools with a stored approval request the workspace Owner can answer later, in the product, bound to the exact action, single use, and expiring. #10443 (first-class approval primitive) is the same deliverable and is closed as a duplicate when this lands. #5351 (no liveness signal on an unanswered gate) is folded in as a precondition. Slice 1 covers eight gated tools; the existing path stays byte-identical for every other tool. The feature ships dark behind the Flagsmith flag `approval-queue`.

Inputs: brainstorm `knowledge-base/project/brainstorms/2026-10-27-hitl-approval-queue-brainstorm.md`, spec `knowledge-base/project/specs/feat-hitl-approval-queue/spec.md`, wireframes `knowledge-base/product/design/approvals/approval-request.pen` (operator-approved 2026-10-27), draft PR #11289.

## Research Insights

### Premise Validation (Phase 0.6)

- #4672, #10443, #5351, #9776, #10111, #9388, #5331, #10196 are all OPEN with no closing PR. The only collision hit (`prs=6640`) is the unrelated WIP PR "feat-eve-competitive-eval" matching the substring; no open PR touches `approval_request` or migration `179`.
- `approval_request` appears nowhere on `origin/main`; the next free migration is `179` (latest `178_api_data_grants_narrowing`).
- ADR ordinal: `ADR-304` is taken by open PR #11225. Use `ADR-305` or higher and re-check against fresh `origin/main` immediately before merge (the ordinal is provisional).
- ADR corpus: no accepted ADR rejects durable server-side approval rows. ADR-284 chose a memory-less lane ("no new approval surface", "writes no acknowledgement and no cache entry"); a durable single-use request extends it and needs an amendment note. ADR-085 reserves `approval_required` for #4672 (source CHECK widening). ADR-060 rejects a bare `approved_at` column as forgeable and adopts a body-hash-bound single-use approval, which is the precedent for the binding here.

### Verified code facts (repo-research, 2026-10-27)

- The gated platform branch of `canUseTool` (`server/permission-callback.ts`, `if (tier === "gated")`) awaits `abortableReviewGate` with no try/catch and no `finally`. A timeout (5 min) or abort rejects out of `canUseTool`; the conversation stays `waiting_for_user`. The SDK (0.3.284 `sdk.mjs` `handleControlRequest`) replies `control_response {subtype:"error"}` to a throw, which is neither allow nor deny. How the bundled CLI turns that into a tool outcome is not tested anywhere in the repo.
- `holdForUser` (null = deny, "fail closed") is used only by the Bash branch.
- `review_gate` is not in `BUFFERED_FRAME_TYPE_MAP` (`server/stream-replay-buffer.ts`); a reconnected client gets no card and the agent stays blocked until the timeout.
- `action_sends` cannot take an approval: `grant_id` is NOT NULL (FK to `scope_grants`), `tier_at_send` is a four-value CHECK, and the pure-reject trigger covers 11 columns. Precedent for a dedicated table: `outbound_sends` (migration 104).
- `buildGateMessage` is display-only and lossy: `github_push_branch` omits `force`, `create_pull_request` omits `body`, `github_trigger_workflow` omits `inputs`, `workspace_set_autonomous` omits `value`, `email_send` truncates the body to 240 characters, and `email_reply`'s recipient is server-derived and absent from the input. The canonical action must be derived from the full input plus server-derived fields, never from the preview.
- The email body-hash binding (`email-triage-tools.ts` `approvedBodySha256`) is computed from the same arguments at handler time, so it binds nothing independent of the gate.
- Expiry pattern: no DB sweep exists for `expires_at` rows. The cron pattern is `server/inngest/functions/cron-action-required-sla.ts` (memoised `step.run`, `postSentryHeartbeat`, `reportSilentFallback` in the catch), registered in `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS`, `app/api/inngest/route.ts`, `execution-placement.ts`, `routine-metadata.ts`, and `infra/sentry/cron-monitors.tf`.
- RPC pattern (migration 177): `SECURITY DEFINER SET search_path = public, pg_temp`, owner check via `is_workspace_owner` (migration 098), `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`, explicit `GRANT EXECUTE`. ADR-303 / migration 178: a new public relation must declare its Data API grants or a `-- soleur:no-data-api:` sentinel, and `test/rls-fuzz/table-grants.ts` must classify it.
- `inbox_item.source` has a CHECK of `('task_completed','system')`; `approval_required` needs a widening.
- Real-SDK probe infrastructure is one human-run script, `apps/web-platform/scripts/dev-probe-destroy-ask.ts`; about 48 test files mock the SDK. #10111 is open.
- Flag files for `approval-queue`: `lib/feature-flags/server.ts` (`RUNTIME_FLAGS`), `apps/web-platform/.env.example` (`FLAG_APPROVAL_QUEUE=0`), `plugins/soleur/skills/flag-set-role/scripts/flip.sh` `FLAG_ENV_VARS` (parity test `plugins/soleur/test/flip-flag-map-parity.test.sh`), Doppler `soleur` dev and prd, and the Flagsmith feature.

### Institutional learnings applied

- `2026-10-26-an-approved-action-needs-a-durable-row-...`: durable approval row, then accepted enqueue, `.select()` on UPDATEs because an RLS-hidden update returns zero rows with no error.
- `2026-10-11-a-mocked-sdk-could-not-see-the-permission-callback-never-ran`: a real-SDK probe is required; mocks cannot model permission-chain order.
- `2026-03-20-review-gate-promise-leak-abort-timeout`: every approval wait has a timeout and a disconnect path; reject, do not resolve with a synthetic deny.
- `2026-05-19-server-derived-recipient-body-and-draft-hash-echo`: derive recipient and body server-side; a true approval needs a server-issued single-use nonce.
- `2026-09-27-crm-lead-chat-tools-need-the-permission-allowlist`: MCP registration is not permission; assert the fully qualified names `canUseTool` accepts.
- `2026-05-31-worm-bypass-fix-must-enumerate-all-mechanisms`: enumerate every write path for an audit table.

### Property List (Phase 0.6b)

- P1. The Owner can answer an approval after the agent session ended, in the product, without a command.
- P2. An approval authorizes exactly one execution of exactly the action the Owner saw.
- P3. An unanswered request is observable and reaches the away Owner; an expired request is never silently dropped.
- P4. Only a workspace Owner can decide; the sandboxed agent cannot.
- P5. Every decision leaves an audit row that survives erasure of the action text.
- P6. The consequence text the Owner reads cannot disagree with the action that runs.
- P7. With the flag off nothing new is created, shown or emitted.

### Cut List (Phase 0.6b)

- File-backed queue under `knowledge-base/` (the issue's suggested direction) → P1 is served by a row the product already can read; rejected by the CTO ruling.
- Widening `action_sends` → needs a `scope_grants` row per approval, which does not exist; separate table instead.
- Per-request Inngest `step.sleepUntil` function → one 5-minute cron serves expiry, liveness flagging and scrub with one task surface.
- Server-side execution of an approved payload after the session died → different principal, larger change; deferred.
- "Approve all", remember-this, batch digest, member-role matrix, LLM-written consequence text, policy editor → not needed by P1-P7.
- A second WORM decision-log table → one table with write-once columns and forward-only transitions serves P5 (see Data model).

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality | Plan response |
|---|---|---|
| "extend the `action_sends` records" (CTO ruling, brainstorm D1) | `action_sends` needs a `grant_id` and is send-shaped; cannot take a pre-approval | New `approval_request` table; `action_sends` is untouched. CTO ruling's intent (no new file-backed queue, reuse gated tier) is kept |
| "the gated await gets a try/catch that denies on timeout or abort" (spec TR2) | Correct, and the missing handler is an existing defect on the flag-OFF path too | Fix ships ungated for all gated tools; documented as the one flag-off behaviour change (timeout now returns a static deny and restores status instead of escaping `canUseTool`) |
| "5-minute in-session wait and 24 h durable expiry" | A live wait that outlives the in-memory resolver only works within one process; `review_gate` is not replayed on reconnect | Waiter re-reads the row every 5 s; the server re-sends live approval cards on session attach; correctness never depends on the in-memory wake |
| Wireframe 04C "Email sent" and 04D "approved but did not complete" | Slice 1 records only `consumed` (released to the agent), not the tool outcome; claiming "sent" would be an unmeasured claim | Wireframe delta (Phase 0): replace with "Released to your agent"; add "Approved, waiting for your agent"; no outcome claim |
| "owner notified at expiry" (brainstorm D5) | Nothing fires at T+24 h without a timer | One Inngest cron every 5 minutes (Task Design below) |
| Wireframe 01/04A: button "Approve and send", line "this email is sent now" | Slice 1 sends nothing on approve; the agent sends only if re-prompted and it proposes the identical action | Wireframe delta (Phase 0.2): button "Approve", honest consequence line, new "approved, waiting for your agent" state (spec-flow finding, single-user incident) |
| Brainstorm lists five Sentry ops | `approval-requested` and `approval-decided` are information events, not faults | They are Better Stack `SOLEUR_APPROVAL_*` log markers; Sentry carries only the fault ops, each with its own static message |

## Problem Statement

A gated agent action waits on an in-memory promise (5-minute timeout, lost on restart or reconnect) that leaves no audit row, binds nothing between what the user saw and what runs, and cannot reach an absent user. A timeout also escapes `canUseTool` and strands the conversation in `waiting_for_user`. This is the gate #10196 (taint downgrade) and the credential broker #9543 need as a real boundary.

## Proposed Solution

A durable `approval_request` row per exact action (`action_sha256` over the full canonical input), created by a service-role RPC when a slice-1 tool reaches `canUseTool` with the flag on. The Owner decides through a chat card, an inbox row or a push landing page; every path calls one `decide_approval` RPC. The agent waits up to five minutes, polling the row. A decision inside the window releases the call; a wait that ends undecided denies with a static "saved, do not retry" message and leaves the row `pending`. A later approval makes the next identical proposal in the same conversation consume the approved row once. No server-side execution.

## Technical Approach

### Architecture

```text
agent tool call (slice-1 tool, flag on)
  -> createCanUseTool gated branch                       [permission-callback.ts]
       canonicalizeAction(tool, input, serverDerived)   -> canonical + sha256   [server/approval/canonical.ts]
       create_approval_request RPC (+ inbox_item, same txn)                     [mig 179]
       WS approval_request card + push dispatch (best effort, own op on failure)
       wait <= 5 min: resolver wake OR 5 s poll of get_approval_status
  decided in window  -> consume_approval(id, hash, conversation) -> allow
  rejected           -> deny "denied; do not retry or respell"
  still pending      -> warn op gate_unanswered, deny "saved for the owner; do not retry"
  expired / consume rejected -> deny with its own static message + warn op

Owner decides:  chat card (WS approval_decide) | inbox row -> /dashboard/approvals/[id] (POST decide route)
                -> decide_approval(p_id, p_decision, p_actor) -> owner check in the RPC
Cron every 5 min: expire_due_approvals() | flag_unanswered_approvals() | scrub_approval_text()
```

### Data model (migration `179_approval_request.sql`, with `.down.sql` and `supabase/verify/179_approval_request.sql`)

`approval_request`: `id`, `workspace_id` (FK to the workspace table used by `inbox_item`, confirmed at work time), `requested_by_user_id` and `decided_by` (nullable, `ON DELETE SET NULL` carve-out as in `action_sends`), `conversation_id`, `tool_name` (CHECK over the eight slice-1 names), `action_sha256` (CHECK length 64), `canonical_action jsonb` (erasable; nulled by the scrub), `status` (`pending|approved|rejected|expired|consumed`), `expires_at`, `decided_at`, `consumed_at`, `expired_at`, `unanswered_flagged_at`, `text_scrubbed_at`, `created_at`, `request_count` (number of requests for this exact hash in this conversation, for the card header), `expired_reason` (`unanswered` when never decided, `unconsumed` when approved but the agent never asked again; drives the owner-facing wording and whether a push is sent).

Constraints and triggers: unique partial index on `(conversation_id, action_sha256)` where `status in ('pending','approved')`; a trigger allowing only `pending -> approved|rejected|expired` and `approved -> consumed|expired`, making `workspace_id`, `conversation_id`, `tool_name`, `action_sha256`, `expires_at`, `decided_*`, `consumed_at`, `expired_at` write-once, and refusing every write other than through the RPCs (GUC-gated scrub path for `canonical_action`). RLS: Owner `SELECT` via `is_workspace_owner`; no INSERT/UPDATE/DELETE policy. Explicit grants or a `-- soleur:no-data-api:` sentinel per ADR-303, and a `table-grants.ts` classification.

RPCs (all `SECURITY DEFINER SET search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`, then `GRANT EXECUTE ... TO service_role` only; the TypeScript callers derive the actor from the authenticated socket or session, never from a payload):

- `create_approval_request(...)` — idempotent on the live unique index; also inserts the `inbox_item` (`source='approval_required'`, `severity='action_required'`, `source_ref`, `dedup_key` = approval id) in the same transaction; returns the row and `request_count`.
- `decide_approval(p_id, p_decision, p_actor)` — `is_workspace_owner(workspace, p_actor)` re-checked at decision time (an Owner who left or lost the role is refused); refuses when the conversation is archived or deleted ("conversation closed", nothing recorded as approved); idempotent for the same decision, refuses the opposite and returns the current row to the loser of a two-Owner race; in the same transaction moves the linked `inbox_item` out of the `action_required` count; `.select()`-checked.
- `consume_approval(p_id, p_hash, p_conversation)` — one atomic `UPDATE ... WHERE status='approved' AND expires_at>now() AND action_sha256=p_hash AND conversation_id=p_conversation RETURNING`.
- `get_approval_status(p_id)`, `list_live_approvals(p_conversation)` (for reattach replay).
- `expire_due_approvals()`, `flag_unanswered_approvals()`, `scrub_approval_text()` for the cron; `anonymise_approval_request(p_user)` for account deletion.

Audit trail: the row itself (hash, tool, status, actor, timestamps, all write-once, forward-only) is the audit record; the raw action text is the only erasable part. A separate WORM log table was cut (Cut List) because write-once columns plus forward-only transitions give the same decision history without a second table. Retention (proposed, confirmed in the legal task): metadata row follows the `action_sends` precedent (retained, anonymised on erasure); `canonical_action` is nulled 30 days after the terminal state.

### Canonical action and consequence text

`server/approval/canonical.ts` exports `canonicalizeAction(tool, input, serverDerived)` returning a versioned object (`v: 1`) with every field that changes what runs, string values NFC-normalised, keys sorted, nothing truncated:

- `email_send`, `email_reply`, `email_suppress`: full recipient list (server-derived for reply), subject, full body, attachments; suppress adds address and reason enum.
- `github_push_branch`: repo, branch, `force`, the commit list; `create_pull_request`: repo, head, base, title, full body; `github_trigger_workflow`: repo, workflow, ref, `inputs`.
- `kb_share_create`: document path, audience, expiry; `workspace_set_autonomous`: target value and scope.
- `action_sha256 = sha256(canonicalJSON({tool_name, workspace_id, conversation_id, action}))`.

`renderApprovalView(canonical)` builds the card model (field rows, one consequence line, the Approve label) from the SAME object, so display and hash cannot drift. Per-tool field lists are confirmed against each tool's zod schema at work time (a Phase 1 task with a failing test per tool).

### Gated branch (`permission-callback.ts`)

The gated branch gets a `try/finally` that always restores `status` and converts every rejection to a static deny (this part is ungated). With the flag on and the tool in `APPROVAL_REQUIRED_TOOLS`, the flow in the Architecture block runs. The wait is a bounded loop (5 minutes, 5-second poll) that also honours the abort signal; abort denies and leaves the row `pending`. `allow()` passes the original input unchanged (`updatedInput` is never set on this path, so the hashed input is the executed input). The static deny texts tell the agent what it can do next: on an undecided wait, "saved for the workspace Owner; do not retry now; once the user says it is approved, call this tool again with byte-identical arguments" (a regenerated email body hashes differently and would not consume; the rate of `approval-consume-rejected` is the success metric for this wording).

Concurrent proposals: a newer pending request for the same conversation and tool does not supersede an older one (parallel same-tool calls such as several emails are legitimate); instead the older card renders a render-time banner "A newer request from your agent exists" and each card always shows its own exact action. Approving one card never approves another.

### Reattach and WS

New message types: `approval_request` (server to client: id, view, status, expiry, request count, viewer role), `approval_status` (server to client), `approval_decide` (client to server: id, decision enum `approve|deny`). No option strings, so "Approve all" cannot be expressed. On session attach, `list_live_approvals(conversation)` re-sends cards for every `pending` or `approved` row. The `approval_decide` handler takes `userId` from the socket, calls `decide_approval`, then wakes the in-memory waiter if present.

### Away-user surfaces

`app/(dashboard)/dashboard/approvals/[id]/page.tsx` (Owner-only via RLS; signed-out redirects to sign-in and returns to the same path through sign-in and MFA with a same-origin allowlist; a non-Owner or unknown id gets an identical not-found) renders the same card. The member's read-only waiting card (wireframe 05) is the in-thread WS card built server-side for the requester's own session; no member landing page and no RLS widening for members is added. `app/api/approvals/[id]/decide/route.ts` (HTTP-method exports only) calls `decide_approval`. `inbox-item-row.tsx` renders `approval_required` rows with an expiry chip and a link, never an inline decide button; `inbox-nav-badge.tsx` counts them through the existing `action_required` path (confirmed at work time). `notifications.ts` gains generic push and email copy (no action text, per #8532); the push dispatch is split out of `notifyInboxItem` if it is coupled to the insert.

### Expiry cron

`server/inngest/functions/cron-approval-expiry.ts`, every 5 minutes: (1) `expire_due_approvals()` then, per row, the owner's inbox item moves to FYI, a generic push goes out and the op `approval-expired` fires; (2) `flag_unanswered_approvals()` marks `pending` rows older than 15 minutes once and fires `gate_unanswered`; (3) `scrub_approval_text()` nulls `canonical_action` 30 days after the terminal state. Registered in the five places listed under Research Insights; its Sentry cron monitor lands in `infra/sentry/cron-monitors.tf`.

### Flag

Flagsmith `approval-queue`, default off, evaluated per workspace identity so a cohort can be targeted; read in `canUseTool`, the WS attach path and the pages. Created through `soleur:flag-create` (the typed-yes write is handed to the operator; the flag is absent-means-off, so the merge does not depend on it). Flipping it is out of scope and is not done here.

## Implementation Phases

### Phase 0 — measurements and design deltas (before any product code)

- 0.1 Real-SDK probe `apps/web-platform/scripts/dev-probe-approval-gate.ts` modelled on `dev-probe-destroy-ask.ts`: an in-process MCP stub with a slice-1 tool name, the real `createCanUseTool`, and an in-memory approval service. Measure: (a) `canUseTool` is invoked for the slice-1 tool names and allow/deny are honoured; (b) what the bundled CLI does when `canUseTool` throws today (informational: records the existing defect). Results in `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md`.
- 0.2 Wireframe delta via `soleur:product:design:ux-design-lead` (the spec-flow review found screens 01 and 04A promise execution that slice 1 does not perform, which is false consent on a consent gate): rename the button "Approve and send" to "Approve" and change the consequence line to "Your agent can send this once, if you ask it to try again; valid in this conversation only"; add the pending-card sub-line "Your agent stopped waiting after 5 minutes"; add the state "Approved, waiting for your agent" with the instruction to ask the agent again; replace "Email sent" and "approved but did not complete" with "Released to your agent"; add the expired-unconsumed wording ("You approved this, but your agent never asked again"), the "details removed per retention policy" state, the "already decided by <name>" loser state, the "conversation closed" refusal, the "a newer request exists" banner, and the request-count header ("the agent asked again"); drop the member landing variant (wireframe 07c). Re-export screenshots, scrub `fileToken`, and record the approval with the operator.
- 0.3 Confirm per-tool canonical field lists against each tool's zod schema; list the fields in the test fixtures.

### Phase 1 — failing tests, then data layer

- 1.1 Write failing tests first (Test Scenarios): canonicalization per tool, consume predicate, status machine, RPC owner check, gated-branch timeout deny, tool-map census.
- 1.2 Migration 179 + down + verify SQL + `table-grants.ts` classification + RLS fuzz entry + `inbox_item` CHECK widening.
- 1.3 `server/approval/{canonical,render,service}.ts`.

### Phase 2 — gate wiring

- 2.1 `permission-callback.ts` gated branch (try/finally deny; approval flow behind the flag), `tool-tiers.ts` `APPROVAL_REQUIRED_TOOLS`, `email-triage-tools.ts` binding fix (the handler verifies the consumed approval's body hash, removing the tautology).
- 2.2 WS types, `ws-handler.ts` decide and reattach, `chat-state-machine.ts`.
- 2.3 Ops: static-message Sentry ops and `SOLEUR_APPROVAL_*` markers; confirm the Vector allowlist admits the marker family.

### Phase 3 — surfaces and notifications

- 3.1 `approval-request-card.tsx`, landing page, decide route, inbox row, nav badge, notification copy and the push-dispatch split.

### Phase 4 — cron, flag, infra

- 4.1 `cron-approval-expiry.ts` and its five registrations, Sentry cron monitor TF.
- 4.2 Flag plumbing in the four repo files; `flag-create` hand-over note in the PR.

### Phase 5 — governance

- 5.1 ADR-305 (provisional) via `soleur:architecture`, plus ADR-284 and ADR-085 amendment notes.
- 5.2 C4: `approvalStore` element, edges, description fixes, `views.c4` include, regenerate `model.likec4.json`, parity counts +1 (monitors) in prose.
- 5.3 Legal: Art. 30 entry (or PA-14/PA-16 amendment), DPD §2.3, GDPR Policy, Privacy Policy and mirrors with `legal-doc-shas.ts`; `account-delete.ts` anonymise step; `dsar-export-allowlist.ts` entry.
- 5.4 Run the real-SDK probe against the finished branch; record in the PR.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Keep the in-memory gate, only add try/catch and a longer timeout | Lost on restart, no away-user path, no audit row, no binding (P1, P2, P5 unmet) |
| Extend `action_sends` | Needs `scope_grants` per approval; WORM; send-shaped |
| File-backed queue in `knowledge-base/` | Rejected by CTO ruling; not readable by the product with RLS |
| Server-side execution of the approved payload | New principal and blast radius; deferred |
| Per-request `sleepUntil` Inngest function | More functions than one 5-minute cron |
| Gate every tool at once | Larger blast radius; slice-1 list is the credential-use and outward-write subset |

## User-Brand Impact

- **If this lands broken, the user experiences:** the approval card showing one thing while the agent sends or pushes another, an approval that silently never reaches them, or an agent stuck "waiting for you" with nothing to click.
- **If this leaks, the user's workflow and third-party data are exposed via:** the persisted action text (email bodies, recipients, repository names) in `approval_request.canonical_action`, or a push or email body that quotes it.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong send or push made on one founder's behalf under a stale, changed, replayed or wrong-principal approval is a brand event on its own; an aggregate tier would hide it.
- Artifact and vector pairs for the reviewer: (1) approval card, via a preview built from different data than the bound hash; (2) consume path, via a changed or replayed input; (3) decide path, via a non-owner or forged socket message; (4) persisted text, via retention beyond the scrub or a notification body that echoes it; (5) flag-off path, via any new row, card or op appearing.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor and heartbeat for cron-approval-expiry, plus the Sentry warn op "approval gate unanswered" for any request pending more than 15 minutes
  cadence: every 5 minutes
  alert_target: Sentry cron monitor alert and the existing operator Sentry issue-alert route
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf and apps/web-platform/server/inngest/functions/cron-approval-expiry.ts

error_reporting:
  destination: Sentry project web-platform via reportSilentFallback and warnSilentFallback in server/observability.ts
  fail_loud: ops gate_unanswered, approval-expired, approval-consume-rejected, approval-notify-failed and approval-reproposed, each emitted with its own static message

failure_modes:
  - mode: Owner never answers; the request sits pending
    detection: flag_unanswered_approvals() fires the gate_unanswered op once per request after 15 minutes
    alert_route: Sentry issue alert to the operator route
  - mode: approval expires with nothing run
    detection: expire_due_approvals() in the cron fires the approval-expired op and notifies the Owner
    alert_route: Owner inbox item and generic push; Sentry warn for the operator
  - mode: consume rejected because the input changed or the row was already used
    detection: consume_approval returns no row; op approval-consume-rejected with the tool name and request id
    alert_route: Sentry issue alert
  - mode: push or email notification failed
    detection: dispatch error caught; op approval-notify-failed; the inbox item still exists because it is written in the same transaction
    alert_route: Sentry issue alert
  - mode: cron stops running
    detection: Sentry cron monitor missed check-in
    alert_route: Sentry cron monitor alert

logs:
  where: web-platform stdout markers SOLEUR_APPROVAL_REQUESTED, SOLEUR_APPROVAL_DECIDED and SOLEUR_APPROVAL_CONSUMED in Better Stack, plus Sentry for fault ops
  retention: Better Stack retention window; Sentry project retention

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_APPROVAL_REQUESTED
  expected_output: SOLEUR_APPROVAL_REQUESTED
  credentials_required: Better Stack read token via Doppler prd_terraform — the production marker stream has no unauthenticated substitute that proves the markers reach the aggregator
```

## Encryption Posture

```yaml
at_rest:
  - store: supabase.prd
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: existing ledger row supabase.prd in scripts/encryption-posture-ledger.json (Supabase Postgres AES-256 at-rest encryption); the new table lives in the same project, so no new store class is introduced
    defends_against: a seized or RMA'd disk and a raw volume snapshot of the database host
    does_not_defend: a leaked service-role key, an RLS or RPC bypass, or an operator with database access reading canonical_action; the erasable text is therefore scrubbed 30 days after the terminal state
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Supabase offers no per-table encryption probe
in_transit:
  - connection: web-platform server -> Supabase REST and RPC
    enforced_at: apps/web-platform/lib/supabase/service.ts
    tls: TLS 1.2 or higher, https only
    cert_verification: on
    does_not_defend: a compromised server process or a leaked service-role key
    disclosed_as: not-publicly-claimed
  - connection: browser -> web-platform (WS approval_request and approval_decide, decide route)
    enforced_at: apps/web-platform/server/ws-handler.ts and the Cloudflare edge
    tls: TLS 1.2 or higher
    cert_verification: on
    does_not_defend: a compromised browser session or an XSS in the dashboard
    disclosed_as: not-publicly-claimed
```

## Task Design

```yaml
tasks:
  - task: cron-approval-expiry
    trigger: Inngest cron every 5 minutes
    services: reads and writes approval_request and inbox_item in Supabase; sends generic web push and email through server/notifications.ts; posts the Sentry cron heartbeat
    next: nothing
    human_reentry: the Owner decides or re-requests through the card or the landing page; the cron can be paused by removing it from cron-manifest.ts or by flipping the approval-queue flag, after which it reads zero live rows
    dedupe: each RPC is a conditional UPDATE guarded by status and a write-once marker column (expired_at, unanswered_flagged_at, text_scrubbed_at), so a second run finds no rows; the owner notification is keyed by the inbox_item dedup_key (the approval id)
    source_dedupe: not a ticket source
```

## Guard Contract

### Guard 1 — approval consume gate

**Property.** A slice-1 tool call is allowed only if it consumes, exactly once, an approved and unexpired request whose hash equals the hash of the full input about to run, in the same conversation, decided by a workspace Owner.

**Assembly.** Every path that can return `allow` for a slice-1 tool: the gated branch of `createCanUseTool` (used by `agent-runner.ts` and `cc-dispatcher.ts`), the Bash autonomous bypass and the 60-minute approve-prefix cache (which must not apply to platform tools), the `updatedInput` return, the SDK auto-allow and hook-allow paths measured in Phase 0, the MCP registration and permission allowlist names, and the email handler's own body-hash check. The chokepoint is `createCanUseTool`; the consume RPC is the single place that turns an approval into an allow.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop `action_sha256 = p_hash` from the consume predicate | RED |
| 2 | drop `expires_at > now()` from the consume predicate | RED |
| 3 | make consume non-single-use (no status change to `consumed`) | RED |
| 4 | remove the `is_workspace_owner` check in `decide_approval` | RED |
| 5 | accept a free-form decision string instead of the `approve\|deny` enum | RED |
| 6 | return `allow` when the wait throws or times out | RED |
| 7 | build the card view from the tool input instead of the canonical object (preview built from different data than the hash) | RED |
| 8 | remove one slice-1 tool from `APPROVAL_REQUIRED_TOOLS` so it falls to the old path | RED |
| 9 | set `updatedInput` on the allow path | RED |
| 10 | make the dispatch guard report zero tools checked and exit 0 (vacuous census) | RED |
| 11 | add a second pending request for the same hash after a compliant first and approve only the first | RED (second must not be consumable) |
| 12 | reorder: consume before the hash comparison input is final (mutate input between hash and allow) | RED |
| 13 | let `decide_approval` record `approved` for an archived conversation | RED |
| 14 | let an approval on card A make a different pending request B (same conversation and tool, different hash) consumable | RED |

**Harness rows.** (a) Remove the assertion that `canUseTool` is invoked in the real-SDK probe; the suite must go RED. (b) A must-PASS case that is not the canonical: the same tool with a different but permitted argument ordering and whitespace-only string differences within the NFC normalisation, which must hash equal and consume.

**Anchor.** The consume predicate compares a stored hash to the executed input; one diff could edit both. The independent anchor is the real-SDK probe (Phase 0.1 and 5.4), which drives a real tool call with an altered input and asserts the deny, and the review-time mutation run recorded in the PR.

### Guard 2 — tool-map census

**Property.** Every gated tool in `TOOL_TIER_MAP` is either in `APPROVAL_REQUIRED_TOOLS` or in an explicit exempt set with a one-line reason, so a newly added gated tool cannot silently stay on the old path.

**Assembly.** `TOOL_TIER_MAP` entries with tier `gated`, the default-gated fall-through in `getToolTier`, `APPROVAL_REQUIRED_TOOLS`, the exempt set, and the MCP server registrations for the platform tools.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add a new gated tool to `TOOL_TIER_MAP` without classifying it | RED |
| 2 | empty the census (zero gated tools enumerated) | RED |
| 3 | add a second unclassified gated tool after a classified one | RED |
| 4 | exempt a tool with an empty reason | RED |

## Architecture Decision (ADR/C4)

### ADR

Create ADR-305 (provisional; re-check against fresh `origin/main` before merge, 304 is claimed by PR #11225) "Durable, action-bound approval requests" via `soleur:architecture`: the decision (new table, consume in `canUseTool`, Owner-only decide, no server-side execution, flag-gated), alternatives (Cut List and Alternatives table), and the relationship to ADR-284 (memory-less lane unchanged), ADR-085 (source CHECK widened), ADR-060 (hash-bound single-use precedent), ADR-249/264 (operator TTY ack kept). Amend ADR-284 and ADR-085 with a dated note. Status `adopting` until the flag is flipped and the path is measured.

### C4 views

All three files `model.c4`, `views.c4`, `spec.c4` were read in full. Already modelled: Owner actor (`founder`), `dashboard`, `api`, Agent Runtime, `operationalInbox`, `pushService`, `resend`, `inngest`, Supabase. Needed: add `approvalStore = database "Approval Requests"` under `infra`; add `webapp -> approvalStore` (create, decide, consume) and, if consume runs from the runner, `engine -> approvalStore`; amend the `operationalInbox` description (links by id) and the `api` description sentence on `canUseTool`/ADR-284 (gated tools now create and consume a durable request); revisit the `plugin` prose about the web runtime opting out until the web approval adapter lands (it stays true; this slice is not that adapter); add `platform.infra.approvalStore` to the `containers` view `include`; regenerate `model.likec4.json` (`scripts/regenerate-c4-model.sh`, gate `c4-model-freshness.test.sh`); the new cron moves the cron-monitor counts (C4, C6, C9) by one, so update the `model.c4` edge prose and confirm `c4-count-parity.test.sh` and the C4 render tests are green.

### Sequencing

The ADR is authored now in the target state with `adopting` status; it is not deferred.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/cron-monitors.tf`: one new `sentry_cron_monitor` for `cron-approval-expiry` (5-minute schedule, margin and failure thresholds copied from `cron-action-required-sla`). No new provider, no new sensitive variable.

### Apply path

Existing Sentry apply workflow on merge to main; no host change, no downtime.

### Host fan-out

None: no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

The monitor slug is registered in `cron-manifest.ts`, which the parity tests compare with the Terraform list.

### Vendor-tier reality check

The Sentry plan already carries the existing cron monitors; one more is within the existing pattern.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled 2026-10-27 (carried from the brainstorm): new `approval_request` table linked from `inbox_item`, hash-bound single-use consume in `canUseTool`, Owner-only decide, durable expiry, #5351 folded in, dark behind a flag, real-SDK probe required, no server-side execution. Plan-time confirmations: durable TTL 24 h; audit trail is the write-once row (separate table cut); `canUseTool` throw is an error control response, fixed by deny-on-reject; no reconnect replay exists, so cards are re-sent on attach.

### Product (CPO)

**Status:** reviewed
**Assessment:** Owner-only approver; email and GitHub writes first; extend the chat card pattern; no approve-all; expiry notifies the Owner and tells the agent; consequence text is server-built from the bound payload.

### Legal (CLO)

**Status:** reviewed
**Assessment:** A new Art. 30 entry (or PA-14/PA-16 amendment) is needed because the row holds action text; DPD §2.3, GDPR Policy and Privacy Policy move in the same PR; erasable text separated from the append-only decision fields; no public claim ahead of a measured control; no LLM-written consequence text in slice 1.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** soleur:marketing:copywriter (no domain leader recommended it by name; the wireframe copy deck carries the strings and is reviewed with the Phase 0.2 delta)
**Pencil available:** yes

#### Findings

Nine-screen `.pen` approved by the operator on 2026-10-27. Spec-flow analysis (12 gaps, one single-user-incident class) changed this plan as follows: the false-consent wording on screens 01 and 04A becomes a Phase 0.2 wireframe delta and an AC14 string test; owner re-check, conversation-closed refusal, unconsumed-expiry wording, requester visibility and flag-off behaviour are in the RPC list, Gated branch and AC1/AC14b; supersede-on-new-request was considered and replaced by a render-time "newer request exists" banner because parallel same-tool calls are legitimate; a persisted thread line for the requester and a member cancel control are deferred (see Risks and Deferrals).

**Brainstorm-recommended specialists:** none beyond the above.

## Compliance Gate (gdpr-gate, plan phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Run against this plan (advisory, headless). No `Critical` finding, so no `compliance-posture.md` write and no `compliance/critical` issue.

| check_id | Severity | Finding | Plan response |
|---|---|---|---|
| GDPR-Art-6 | Important | New table columns need a `-- LAWFUL_BASIS:` annotation | Migration 179 annotates every personal-data column (`requested_by_user_id`, `decided_by`, `canonical_action`) with the basis recorded in the Art. 30 entry (performance of the user's own request for the action text; legitimate interest in an accountable audit trail for the decision fields); added to AC13 |
| GDPR-Art-5e | Important | Retention metadata for a personal-data table | Migration comment and Art. 30 entry state: `canonical_action` nulled 30 days after the terminal state; decision metadata follows the `action_sends` precedent (retained, anonymised on erasure). Because indefinite retention needs a stated purpose, the Art. 30 entry must name it (accountability for outward actions taken on a user's behalf) or set a bounded period; the CLO confirms in the Phase 5.3 task |
| GDPR-Art-17 and GDPR-Art-17-caller | Important | FKs to users need erasure handling and every `anonymise_*` RPC needs a call site | Both user columns are `ON DELETE SET NULL`; `anonymise_approval_request` is called from `account-delete.ts` in this PR and a test asserts the call site (AC13) |
| GDPR-Chapter-V | none | No new vendor or non-EEA transfer | Web push and Resend are existing processors; no LLM touches the action text in slice 1 |
| GDPR-Art-9 | Suggestion | `canonical_action` is free-form user content (email bodies, CRM text) that may contain special-category data the column name cannot reveal | Mitigated by the 30-day scrub, Owner-only RLS, no action text in notifications, and no LLM processing; recorded in the Art. 30 entry |

## Open Code-Review Overlap

Open `code-review` issues touching planned files: #3374 and #2191 (`ws-handler.ts`), #3243, #3242 (`cc-dispatcher.ts`), #3454, #3242 (`agent-runner.ts`).

- #3374 (slot_reclaimed frame) and #2191 (session timer helper): **Acknowledge** — different concerns in `ws-handler.ts`; this plan adds a switch case only.
- #3243 (decompose `cc-dispatcher.ts`), #3242 (tool_use raw name), #3454 (pdf_metadata tool): **Acknowledge** — this plan does not edit those files beyond the shared `createCanUseTool` import; each stays open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#4672 — durable, action-bound approval requests (slice 1 of the HITL approval queue; #10443 folded in; epic #9601)" [brief] | Overview; whole plan | mapped |
| 2 | "per-exact-action binding, expiry, audit row, in-product approve/deny" [brief] | Data model, Canonical action, Gated branch, Away-user surfaces | mapped |
| 3 | "pull #5351 (liveness signal for an unanswered gate) in as a precondition" [brief] | Observability, Expiry cron, `gate_unanswered` op | mapped |
| 4 | "A UX wireframe (.pen) is required for the approval card and the agent-away surface" [brief] | Phase 0.2 delta; approved `.pen` | mapped |
| 5 | "Plan will need the single-user-incident section, user-impact-reviewer and gdpr-gate (persisted approval records)" [brief] | User-Brand Impact; Phase 5.3; review and gdpr-gate steps | mapped |
| 6 | "Do not flip the egress collection flag; do not run #11237 steps" [brief] | Non-goals; no file in the plan touches either | mapped |
| 7 | "Put any new Sentry op in its own static message" [brief] | Observability, Phase 2.3 | mapped |
| 8 | "Confirm at plan time: exact durable TTL, whether action_sends or a separate audit table receives the consumed outcome, SDK behaviour when canUseTool throws, and whether a reconnect replays an unresolved review_gate card" [brief] | Research Reconciliation; Data model; Phase 0.1; Reattach and WS | mapped |
| 9 | "keep one PR per issue, with the ship pipeline gates" [brief] | Split Assessment: single PR | mapped |
| 10 | "extend the existing review_gate flow and the gated tier in apps/web-platform/server/permission-callback.ts" [brief] | Gated branch | mapped |
| 11 | "reuse the hosted ask lane (ADR-284) but do not claim it is measured until #9776 and #10111 close" [brief] | ADR amendment note; no measured claim | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `approval_request` table, RPCs, migration, grants | "per-exact-action binding, expiry, audit row" | asked |
| canonical action + hash, consume in `canUseTool` | "per-exact-action binding" | asked |
| gated branch try/finally | "extend the existing review_gate flow and the gated tier" | asked |
| WS card types, reattach re-send | "in-product approve/deny" | asked |
| landing page, decide route, inbox row, push copy | "the agent-away surface" | asked |
| expiry cron + Sentry monitor TF | "expiry" and "liveness signal for an unanswered gate" | asked |
| `SOLEUR_APPROVAL_*` markers | "Put any new Sentry op in its own static message" (info events kept out of Sentry) | asked |
| flag `approval-queue` | — | inferred — justification: a dark launch is required by the dark-launch rule for a gate on production agent actions, and the CTO ruling recorded it |
| `email-triage-tools.ts` binding fix | "per-exact-action binding" | asked |
| ADR-305, ADR-284/085 amendments, C4 edits | — | inferred — justification: architecture decisions are a plan deliverable (wg-architecture-decision-is-a-plan-deliverable) |
| legal documents, anonymise RPC, DSAR allowlist | "gdpr-gate (persisted approval records)" | asked |
| real-SDK probe | "SDK behaviour when canUseTool throws" | asked |
| `request_count` column and card header | "per-exact-action binding" (re-proposal after deny must be visible, FR7) | inferred — justification: the spec's FR7 requires repeated re-proposal to be surfaced and the count has no other home |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `knowledge-base`, `plugins/soleur`
- Planned files: ~58 | Estimated changed lines: ~2400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the thresholds are exceeded and the offer to split is declined with a reason: the only natural seam (backend plus RPCs versus UI) leaves a dark backend with no decide surface that the real-SDK probe and the Owner can verify end to end, the operator asked for one PR per issue, and a flag-off deploy makes the whole diff inert until a separate rollout decision. The review panel and the mutation battery carry the added risk.

## Files to Create

- `apps/web-platform/supabase/migrations/179_approval_request.sql`, `179_approval_request.down.sql`
- `apps/web-platform/supabase/verify/179_approval_request.sql`
- `apps/web-platform/server/approval/canonical.ts`, `render.ts`, `service.ts`, `tools.ts` (`APPROVAL_REQUIRED_TOOLS` and the exempt set)
- `apps/web-platform/server/inngest/functions/cron-approval-expiry.ts`
- `apps/web-platform/components/chat/approval-request-card.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/[id]/page.tsx` (directory convention confirmed at work time)
- `apps/web-platform/app/api/approvals/[id]/decide/route.ts`
- `apps/web-platform/scripts/dev-probe-approval-gate.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-305-durable-action-bound-approval-requests.md`
- `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md`
- Tests under `apps/web-platform/test/` (approval canonical, service, permission-callback gated branch, WS decide and reattach, cron, tool-map census, card, landing page, inbox row) and `apps/web-platform/test/rls-fuzz/` entries

## Files to Edit

- `apps/web-platform/server/permission-callback.ts`, `tool-tiers.ts`, `email-triage-tools.ts`, `review-gate.ts` (shared wait helper only if needed), `ws-handler.ts`, `notifications.ts`, `account-delete.ts`, `dsar-export-allowlist.ts`
- `apps/web-platform/lib/chat-state-machine.ts`, `lib/feature-flags/server.ts`, `lib/types` WS message unions
- `apps/web-platform/components/inbox/inbox-item-row.tsx`, `components/dashboard/inbox-nav-badge.tsx`
- `apps/web-platform/server/inngest/cron-manifest.ts`, `execution-placement.ts`, `routine-metadata.ts`, `app/api/inngest/route.ts`
- `apps/web-platform/infra/sentry/cron-monitors.tf`, `apps/web-platform/.env.example`
- `apps/web-platform/test/rls-fuzz/table-grants.ts`
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `model.likec4.json`
- ADR-284 and ADR-085 (amendment notes)
- `knowledge-base/legal/article-30-register.md`, DPD, GDPR Policy, Privacy Policy and mirrors, `legal-doc-shas.ts` (exact paths from the CLO assessment confirmed at work time)
- `knowledge-base/product/design/approvals/approval-request.pen` and screenshots (Phase 0.2)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. With `approval-queue` off, no NEW `approval_request` row, card, inbox item, push or Sentry op is produced for any tool; the only changed behaviour is that a gated-tool wait timeout or abort returns a static deny and restores conversation status (test asserts both). Flag off gates creation only: `decide_approval`, the expiry cron and rendering stay live for rows that already exist, so turning the flag off never strands a pending request (test).
- [ ] AC2. For each of the eight slice-1 tools a test builds the canonical action from the full input (including `force`, `inputs`, PR `body`, `value`, the server-derived reply recipient and the untruncated email body) and asserts the card view is rendered from the same object as the hash.
- [ ] AC3. `consume_approval` succeeds exactly once for an approved, unexpired, same-hash, same-conversation request; each of hash mismatch, expiry, wrong conversation, already consumed and non-approved status is rejected and emits `approval-consume-rejected`.
- [ ] AC4. `decide_approval` is refused for a non-Owner and for an unauthenticated actor, is idempotent for a repeated same decision, and refuses the opposite decision; a forged `approval_decide` payload cannot carry a different user id.
- [ ] AC5. Live path: an Owner decision inside the window releases the call; a wait that ends undecided denies with the static "saved, do not retry" message and the row stays `pending`; a later approval makes the next identical proposal consume it once.
- [ ] AC6. On session attach, live `pending` and `approved` requests for the conversation are re-sent as cards; a resolved or expired one shows its final state.
- [ ] AC7. The cron expires due rows, flags unanswered rows once, scrubs `canonical_action` 30 days after the terminal state, and a second run is a no-op (test).
- [ ] AC8. Each new Sentry op has its own static message; a grep test fails if two ops share a message string; `SOLEUR_APPROVAL_*` markers are admitted by the Vector allowlist (verified by reading the allowlist, not assumed).
- [ ] AC9. The tool-map census (Guard 2) and the mutation battery (Guard 1, every matrix row plus the harness rows) are green, and every mutation lands RED on a pristine copy with a green unmutated control; `scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC10. The real-SDK probe was run against the finished branch and its output is in `phase-0-measurements.md`; it shows `canUseTool` invoked for a slice-1 tool name and the deny honoured.
- [ ] AC11. Migration 179 applies and reverts cleanly; `table-grants.ts` classifies the table; the RLS fuzz and the grants gate are green; no INSERT/UPDATE/DELETE policy exists.
- [ ] AC12. ADR-305 exists (ordinal re-checked against fresh `origin/main`), C4 files edited and `model.likec4.json` regenerated, `c4-model-freshness`, `c4-count-parity` and the C4 render tests green.
- [ ] AC13. Legal documents, Art. 30 entry, anonymise RPC and DSAR allowlist entry are in the PR and the `gdpr-gate` result is recorded; migration 179 carries `-- LAWFUL_BASIS:` annotations and a retention comment; `anonymise_approval_request` has a call site in `account-delete.ts` with a test; the Art. 30 entry states the retention purpose for the decision metadata; no copy claims "every outward action requires your approval".
- [ ] AC14. The approved wireframe delta (Phase 0.2) is committed, and no card, thread line, notification or copy-deck string claims an outcome ("sent", "ran") or an execution on approve that slice 1 does not perform; a string-level test over the copy deck constants asserts the absence of those words.
- [ ] AC14b. `decide_approval` on an archived or deleted conversation returns "conversation closed" and records nothing; an approved-but-never-consumed request expires with `expired_reason='unconsumed'` and no push; a decision removes the linked inbox item from the `action_required` count; a second Owner deciding at the same time receives the final row ("already decided by <name>").
- [ ] AC15. `soleur:review` runs with `user-impact-reviewer` and the review findings are resolved; PR body carries `Closes #4672`.

### Post-merge (operator and verification)

- [ ] AC16. Migration 179 is applied to production by the deploy pipeline (agent verifies through the deploy run, not by hand).
- [ ] AC17. The Flagsmith feature `approval-queue` is created through `soleur:flag-create` (typed-yes write handed to the operator, ADR-249); the flag is not flipped by this plan.
- [ ] AC18. After the first deploy the Sentry cron monitor `cron-approval-expiry` shows a check-in (read by the agent from Sentry).
- [ ] AC19. #10443 is closed as a duplicate of #4672 with a pointer to the PR; the consolidated deferral issue (Risks and Deferrals) exists.

## Test Scenarios

- Canonicalization: stable hash across key order and NFC variants; every field change flips the hash; no truncation of a 100 KB body.
- Consume: happy path once; replay; concurrent double-consume (one wins); changed input; wrong conversation; expired; rejected row.
- Decide: Owner approve, Owner deny, member refused, signed-out refused, opposite decision refused, two Owners deciding at once (first wins, second sees the final state).
- Gate wait: decision in window, timeout, abort, restart mid-wait, decision made on another host (poll picks it up).
- Reattach: reload during a pending request; reload after approve; reload after expiry.
- Flag: off for the whole matrix; flag turned off while requests are pending (existing rows stay readable and decidable, new calls take the old path).
- Cron: expiry notifies once; unanswered flagged once; scrub nulls text and keeps the audit fields; rerun idempotent.
- Surfaces: card states (pending, approving, approved-waiting-for-agent, released, denied, expired, action changed, non-owner waiting); inbox row expiry chip; landing page for Owner, signed-out and member.
- Erasure: account delete anonymises both user columns and the text; DSAR export includes the row without the raw text after the scrub.

## Risks and Deferrals

- **Approval fatigue and consequence-text drift** (CPO) are controlled by the narrow slice, the server-built view and AC2; the approve rate is tracked through the `SOLEUR_APPROVAL_DECIDED` markers.
- **Real-SDK behaviour on throw is inferred** until Phase 0.1; the deny-on-reject fix does not depend on the answer.
- **Cross-host decide** relies on the 5-second poll; a request decided on another host is seen within five seconds, not instantly.
- **ADR ordinal** is provisional.
- **Deferred (one consolidated tracking issue, filed at the end of planning because the deferral rule requires it):** approval outcome recording ("ran" / "failed" card states), server-side execution of an approved payload after the session died, cross-host instant wake-up, a one-hour reminder push, a requester cancel control, a persisted thread line telling the requester how a request was decided, and migrating the Bash must-ask lane to the new table. Related existing issues stay as they are: #9388, #5331, #10196, #4674, #9776, #10111.
- **Egress collection flag and #11237 steps:** untouched by this plan.
