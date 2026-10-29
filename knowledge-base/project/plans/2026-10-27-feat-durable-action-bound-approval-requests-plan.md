---
title: "feat: durable, action-bound approval requests (HITL approval queue, slice 1)"
date: 2026-10-27
slug: durable-action-bound-approval-requests
branch: feat-hitl-approval-queue
issue: 4672
closes: [4672, 5351]
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

> **Reconciliation 2026-10-28 (rebase onto the gate-bypass hotfix).** The hotfix (issue #11303, merged 2026-10-28, ADR-305) now owns three items this plan listed: the real-SDK probe `dev-probe-approval-gate.ts` and its `buildAllowedTools` extraction (Phase 0.1 and 0.1.1: `allowedTools` short-circuited `canUseTool`, so gated tools are no longer pre-approved, unconditionally and with no flag), the gated-branch fail-closed lifecycle (`holdForUser`: timeout or abort denies with a static message; Phase 2.1's `try/finally` defect fix), and the census over gated tools. This branch does not re-implement them; slice 1 builds the durable approval flow on top of them. The measurement record stays in `phase-0-measurements.md`.

## Overview

Replace the in-memory review gate for the highest-risk gated agent tools with a stored approval request the workspace Owner can answer later, in the product, bound to the exact action, single use, and expiring. #10443 (first-class approval primitive) is the same deliverable and is closed as a duplicate when this lands. #5351 (no liveness signal on an unanswered gate) is folded in as a precondition. Slice 1 covers eight gated tools; the existing path stays byte-identical for every other tool. The feature ships dark behind the Flagsmith flag `approval-queue`; the one flag-independent change is a defect fix (a gated-tool wait timeout or abort now returns a static deny instead of escaping `canUseTool`), shipped as its own first commit.

Inputs: brainstorm `knowledge-base/project/brainstorms/2026-10-27-hitl-approval-queue-brainstorm.md`, spec `knowledge-base/project/specs/feat-hitl-approval-queue/spec.md`, wireframes `knowledge-base/product/design/approvals/approval-request.pen` (operator-approved 2026-10-27), draft PR #11289.

## Research Insights

### Premise Validation (Phase 0.6)

- #4672, #10443, #5351, #9776, #10111, #9388, #5331, #10196 are all OPEN with no closing PR. The only collision hit (`prs=6640`) is the unrelated WIP PR "feat-eve-competitive-eval" matching the substring; no open PR touches `approval_request` or migration `180`.
- `approval_request` appears nowhere on `origin/main`; the next free migration is `180` (latest `178_api_data_grants_narrowing`; `179` is held by an unmerged sibling worktree, `179_codex_dsar_column_grants`, so this work renumbered to `180` on 2026-10-28).
- ADR ordinal: `ADR-305` (gated-tier platform tools never enter SDK `allowedTools`, the hotfix) and `ADR-306` are taken on `origin/main` (2026-10-28). Use `ADR-307` or higher and re-check against fresh `origin/main` immediately before merge (the ordinal is provisional; this plan's earlier `ADR-305` references now read `ADR-307`).
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
- Real-SDK probe infrastructure is one human-run script, `apps/web-platform/scripts/dev-probe-destroy-ask.ts`; dozens of test files mock the SDK (83 test files import `claude-agent-sdk`; the census command is `git grep -l claude-agent-sdk -- apps/web-platform/test`). #10111 is open.
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
- P7. With the flag off no approval request is created, shown or emitted, and the only behaviour change is the timeout-deny defect fix.

### Cut List (Phase 0.6b)

- File-backed queue under `knowledge-base/` (the issue's suggested direction) → P1 is served by a row the product already can read; rejected by the CTO ruling.
- Widening `action_sends` → needs a `scope_grants` row per approval, which does not exist; separate table instead.
- Per-request Inngest `step.sleepUntil` function → one 5-minute cron serves expiry, liveness flagging and scrub with one task surface.
- Server-side execution of an approved payload after the session died → different principal, larger change; deferred.
- "Approve all", remember-this, batch digest, member-role matrix, LLM-written consequence text, policy editor → not needed by P1-P7.
- A second WORM decision-log table → one table with write-once columns and constrained transitions (forward-only plus the Owner revoke edge) serves P5 (see Data model).

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
       create_approval_request RPC (+ inbox_item, same txn)                     [mig 180]
       WS approval_request card + push dispatch (best effort, own op on failure)
       wait <= 5 min: resolver wake OR 5 s poll of get_approval_status
  decided in window  -> consume_approval(id, hash, conversation) -> allow
  rejected           -> deny "denied; do not retry or respell"
  still pending      -> warn op gate_unanswered, deny "saved for the owner; do not retry"
  expired / consume rejected -> deny with its own static message + warn op

Owner decides:  chat card (WS approval_decide) | inbox row -> /dashboard/approvals/[id] (POST decide route)
                -> decide_approval(p_id, p_decision) as the authenticated user -> owner check on auth.uid() in the RPC
Cron every 5 min: expire_due_approvals() | flag_unanswered_approvals() | scrub_approval_text()
```

### Data model (migration `180_approval_request.sql`, with `.down.sql` and `supabase/verify/180_approval_request.sql`)

`approval_request`: `id`, `workspace_id` (FK to the workspace table used by `inbox_item`, confirmed at work time), `requested_by_user_id` and `decided_by` (nullable, `ON DELETE SET NULL`; the precedent is the migration 161 user-column carve-out (`audit_github_token_use.founder_id`), NOT `action_sends`, whose `user_id` is `ON DELETE RESTRICT`), `conversation_id`, `tool_name` (CHECK over the eight slice-1 names), `action_sha256` (CHECK length 64), `canonical_action jsonb` (erasable; nulled by the scrub), `status` (`pending|approved|rejected|expired|consumed`), `expires_at`, `decided_at`, `consumed_at`, `unanswered_flagged_at` (set once by the sweep), `created_at`. Derived, not stored (plan review): the request count for a card header is a `count(*)` over the same conversation and hash across all statuses; an expiry's reason is `unanswered` when `decided_at IS NULL` and `unconsumed` when it is set; scrubbed text is `canonical_action IS NULL`; the expiry time is `expires_at` with status `expired`.

Constraints and triggers: unique partial index on `(conversation_id, action_sha256)` where `status in ('pending','approved')`; a trigger allowing only `pending -> approved|rejected|expired`, `approved -> consumed|expired` and the Owner **revoke** edge `approved -> rejected` (added in review round 1: the one backward-looking edge, allowed only for an unconsumed, unexpired row, with its own write-once `revoked_at`/`revoked_by` pair; it only reduces authority and serialises with consume on the row lock, see ADR-307 invariant 3), making `workspace_id`, `conversation_id`, `tool_name`, `action_sha256`, `expires_at`, `decided_*`, `consumed_at`, `expired_at` write-once, and refusing every write other than through the RPCs (GUC-gated scrub path for `canonical_action`). The trigger carries an explicit allowed-write matrix and the cascade carve-out: migration 161 (`161_audit_github_token_use_cascade_null_carveout`) is the precedent for user columns, migration 162 (`162_action_sends_message_id_cascade_null_carveout`) for the message-style `SET NULL` on a write-once table. A row-level `SET NULL` of `requested_by_user_id` and `decided_by` from the user FK, and the workspace-cascade DELETE, are permitted; without them account erasure would be blocked by the write-once rule (Kieran P1; precedents: migrations 161 and 162). RLS: Owner `SELECT` via `is_workspace_owner`; no INSERT/UPDATE/DELETE policy. Explicit grants or a `-- soleur:no-data-api:` sentinel per ADR-303, and a `table-grants.ts` classification.

RPCs (all `SECURITY DEFINER SET search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`, then `GRANT EXECUTE`: `decide_approval` to `authenticated` only (Ruled by CTO agent 2026-10-27: one function, one authority, the actor comes from `auth.uid()` as in migration 177, never from a parameter; the HTTP route calls it with the user JWT and the WS path with the ws-handler's local `tenantFor(userId, "approval-decide")` wrapper over `lib/supabase/tenant.ts`, because the socket keeps only the verified `userId`; the handler reuses or exports that wrapper, confirmed at work time); every other RPC to `service_role` only. A sentinel test asserts that no module reachable from the MCP tool builders or the `canUseTool` deps imports the tenant-client or service-client decide path (the agent shares the process, so the boundary is code discipline and the sentinel is mandatory), and a test confirms the runtime tenant JWT passes the new function's `is_jti_denied_from_jwt()` check. The comment in migration 180 explains why the grant differs from the service-role RPCs):

- `create_approval_request(...)` — idempotent on the live unique index; also inserts the `inbox_item` (`source='approval_required'`, `severity='action_required'`, `source_ref`, `dedup_key` = approval id) in the same transaction; returns the row; when the live row is already `approved` the caller consumes it immediately with no card and no wait; the request count is a count query across all statuses.
- `decide_approval(p_id, p_decision)` — requires `expires_at > now()` and flips an overdue row to `expired` inline instead of recording `approved` (the cron is five minutes late at worst, never the authority); `is_workspace_owner(workspace, p_actor)` re-checked at decision time (an Owner who left or lost the role is refused); refuses when the conversation is archived or deleted ("conversation closed", nothing recorded as approved); idempotent for the same decision, refuses the opposite and returns the current row to the loser of a two-Owner race; in the same transaction moves the linked `inbox_item` out of the `action_required` count; `.select()`-checked.
- `consume_approval(p_id, p_hash, p_conversation)` — one atomic `UPDATE ... WHERE status='approved' AND expires_at>now() AND action_sha256=p_hash AND conversation_id=p_conversation RETURNING`.
- `get_approval_status(p_id)`, `list_live_approvals(p_conversation)` (for reattach replay).
- `expire_due_approvals()`, `flag_unanswered_approvals()`, `scrub_approval_text()` for the cron; `anonymise_approval_request(p_user)` for account deletion.

Audit trail: the row itself (hash, tool, status, actor, timestamps, all write-once, forward-only except the revoke edge) is the audit record; the raw action text is the only erasable part. A separate WORM log table was cut (Cut List) because write-once columns plus forward-only transitions give the same decision history without a second table. Retention (proposed, confirmed in the legal task): metadata row is retained and anonymised on erasure, following the migration 161 `audit_github_token_use` precedent (not `action_sends`, whose `user_id` is `RESTRICT`); `canonical_action` is nulled 30 days after the terminal state.

### Canonical action and consequence text

`server/approval/canonical.ts` exports `canonicalizeAction(tool, input, serverDerived)` returning a versioned object (`v: 1`) with every field that changes what runs, keys sorted, strings hashed exactly as supplied (no Unicode normalisation: the hashed bytes must be the executed bytes), nothing truncated:

- `email_send`, `email_reply`, `email_suppress`: full recipient list (server-derived for reply), subject, full body, attachments; suppress adds address and reason enum.
- `github_push_branch`: repo, branch, `force`, the commit list; `create_pull_request`: repo, head, base, title, full body; `github_trigger_workflow`: repo, workflow, ref, `inputs`.
- `kb_share_create`: document path, audience, expiry; `workspace_set_autonomous`: target value and scope.
- `action_sha256 = sha256(canonicalJSON({tool_name, workspace_id, conversation_id, action}))`.

`renderApprovalView(canonical)` builds the card model (field rows, one consequence line, the Approve label) from the SAME object, so display and hash cannot drift. Per-tool field lists are confirmed against each tool's zod schema at work time (a Phase 1 task with a failing test per tool).

### Gated branch (`permission-callback.ts`)

The gated branch gets a `try/finally` that always restores `status` and converts every rejection to a static deny (this part is ungated). With the flag on and the tool in `APPROVAL_REQUIRED_TOOLS`, the flow in the Architecture block runs. The wait is a bounded loop (5 minutes, about 5-second poll with jitter, at most 60 reads) whose sleep is abort-aware and which checks the signal first; abort denies and leaves the row `pending`. A transient read error continues until the deadline and never allows. The flag is evaluated once per gate, not per poll, and a Flagsmith error means off. If `create_approval_request` returns an already-`approved` row, the branch calls `consume_approval` at once with no card. The shared `allow()` always sets `updatedInput: toolInput` (to avoid an SDK schema error), so the invariant is that the object handed to `allow()` is the same deep-cloned snapshot that was hashed before the first `await`; nothing may mutate it between hash and allow. The static deny texts tell the agent what it can do next: on an undecided wait, "saved for the workspace Owner; do not retry now; once the user says it is approved, call this tool again with byte-identical arguments" (a regenerated email body hashes differently and would not consume; the rate of `approval-consume-rejected` is the success metric for this wording).

Concurrent proposals: a newer pending request for the same conversation and tool does not supersede an older one (parallel same-tool calls such as several emails are legitimate); instead the older card renders a render-time banner "A newer request from your agent exists" and each card always shows its own exact action. Approving one card never approves another.

### Reattach and WS

New message types: `approval_request` (server to client: id, view, status, expiry, request count, viewer role), `approval_status` (server to client), `approval_decide` (client to server: id, decision enum `approve|deny`). No option strings, so "Approve all" cannot be expressed. On session attach, a `SELECT` of the conversation's `pending` and `approved` rows re-emits the `approval_request` cards (this is not the stream replay ring buffer, which does not carry `review_gate`). The `approval_decide` handler takes `userId` from the socket, calls `decide_approval` through the tenant client, then resolves the in-memory waiter directly when it is on this host. Live-path mechanism (Ruled by CTO agent): single process, the decide path wakes the waiter and one database re-read at timeout closes the race; multi-host, a decide that arrives over HTTP on the other host only writes the row, so the waiter polls one indexed row by id every 5 seconds while registered and stops on resolution (a read, no WAL). Terminal rows keep their hash and are never deleted, so the request count is a `count(*)` over `(conversation_id, action_sha256)`.

### Away-user surfaces

`app/(dashboard)/dashboard/approvals/[id]/page.tsx` (Owner-only via RLS; signed-out redirects to sign-in and returns to the same path through sign-in and MFA with a same-origin allowlist; a non-Owner or unknown id gets an identical not-found) renders the same card. The member's read-only waiting card (wireframe 05) is the in-thread WS card built server-side for the requester's own session; no member landing page and no RLS widening for members is added. `app/api/approvals/[id]/decide/route.ts` (HTTP-method exports only) calls `decide_approval`. `inbox-item-row.tsx` renders `approval_required` rows with an expiry chip and a link, never an inline decide button; `inbox-nav-badge.tsx` counts them through the existing `action_required` path (confirmed at work time). `notifications.ts` gains generic push and email copy (no action text, per #8532); the TypeScript `source` union of `notifyInboxItem` is widened (union-widening grep over the three consumer patterns) and `dispatchInboxPush(inboxItemId)` is split out so the row inserted by the RPC is pushed after the RPC returns, keeping the deep-link guard and the Sentry op; `notifications.ts` stays a leaf with no imports from `server/approval/`.

### Expiry cron

`server/inngest/functions/cron-approval-expiry.ts`, every 5 minutes, one `step.run` calling one `sweep_approvals()` RPC that (1) expires due rows (an `approved` row past expiry becomes `expired` with `decided_at` set, meaning `unconsumed`), (2) flags `pending` rows older than 15 minutes once through `unanswered_flagged_at`, and (3) nulls `canonical_action` 30 days after the terminal state. For each expired row the owner's inbox item moves to FYI, a generic push goes out for the `unanswered` case only (an `unconsumed` expiry is inbox-only), and the ops fire. Registered in `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS`, `app/api/inngest/route.ts`, `execution-placement.ts` (class: not host-affine, it touches only the database and push), `routine-metadata.ts`, `infra/sentry/cron-monitors.tf`, and the other places `git grep -l cron-action-required-sla` finds outside the knowledge base (`.github/workflows/cutover-inngest.yml`, `scripts/infra-config-red-alert.sh` and its test, `test/server/inngest/cron-safe-commit-parity.test.ts`), each classified at work time as needing the new cron or not; plus a new issue-alert rule in `infra/sentry/issue-alerts.tf` and an `infra/sentry/alert-reference.json` entry for the `approval gate unanswered` op only.

### Flag

Flagsmith `approval-queue`, default off, evaluated per workspace identity so a cohort can be targeted; read in `canUseTool`, the WS attach path and the pages. Created through `soleur:flag-create` (the typed-yes write is handed to the operator; the flag is absent-means-off, so the merge does not depend on it). Flipping it is out of scope and is not done here.

## Implementation Phases

### Phase 0 — measurements and design deltas (before any product code)

- 0.1 Real-SDK probe `apps/web-platform/scripts/dev-probe-approval-gate.ts` modelled on `dev-probe-destroy-ask.ts`, human-run and out of CI like its model. It builds the query options through the real `buildAgentQueryOptions` path (an in-process stub that skips it could pass vacuously, because the legacy runner passes every platform tool as `allowedTools` and `cc-dispatcher.ts` documents `allowedTools` as bypassing `canUseTool`). Measure: (a) whether `canUseTool` is invoked for each slice-1 tool name under the real option composition and allow/deny are honoured; (b) if `allowedTools` short-circuits it, the fix is a pure `buildAllowedTools` that drops `APPROVAL_REQUIRED_TOOLS` when the flag is on, pinned by a census test. Results in `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md`. The SDK's behaviour on a throwing `canUseTool` is already verified by reading `sdk.mjs` (`control_response` with `subtype: error`, neither allow nor deny), so it is not re-measured. **Stop point:** if (a) fails for any tool, stop and re-plan before building the rest.
- 0.2 Wireframe delta via `soleur:product:design:ux-design-lead` (the spec-flow review found screens 01 and 04A promise execution that slice 1 does not perform, which is false consent on a consent gate): rename the button "Approve and send" to "Approve" and change the consequence line to "Your agent can send this once, if you ask it to try again; valid in this conversation only"; add the pending-card sub-line "Your agent stopped waiting after 5 minutes"; add the state "Approved, waiting for your agent" with the instruction to ask the agent again; replace "Email sent" and "approved but did not complete" with "Released to your agent"; add the expired-unconsumed wording ("You approved this, but your agent never asked again"), the "details removed per retention policy" state, the "already decided by <name>" loser state, the "conversation closed" refusal, the "a newer request exists" banner, and the request-count header ("the agent asked again"); drop the member landing variant (wireframe 07c) and wireframe 04G (it assumed a supersede link that the banner design replaces); split the approved state in two (live release inside the wait: 'Released, your agent is continuing'; late approval after the agent stopped: 'Approved, ask your agent again'); make the 'Your agent stopped waiting' sub-line render only after the wait ends and align the mock timers to the 5-minute-then-24-hour model; fix the copy deck (section C drops 'Approve and {verb}' and the 'no bare Approve' rule; section D drops 'Approved and ran / executed: true', 'Approved but failed' and 'superseded'; every 'the agent was told it did not run and must not retry' line becomes 'saved for your agent; asking again with the same arguments is allowed'); reword the push and email body 'Your agent is waiting for your decision' to 'A request needs your decision'; soften 'Dana has been notified' on the member card; make wireframe 05 note 3 and 05 note 4 agree with the not-found rule for non-Owners; remove the 'Ref AR-7F3K' source line or define it from the approval id. Unconsumed-expiry stays an inbox-only calm line. Re-export screenshots, scrub `fileToken`, and record the approval with the operator.
- 0.3 Confirm per-tool canonical field lists against each tool's zod schema; list the fields in the test fixtures.

### Phase 1 — failing tests, then data layer

- 1.1 Write failing tests first (Test Scenarios): canonicalization per tool, consume predicate, status machine, RPC owner check, gated-branch timeout deny, tool-map census.
- 1.2 Migration 180 + down + verify SQL + `table-grants.ts` classification + RLS fuzz entry + `inbox_item` CHECK widening.
- 1.3 `server/approval/{canonical,render,service}.ts`.

### Phase 2 — gate wiring

- 2.1 First, as its own commit: the `try/finally` deny-on-reject fix in the gated branch of `permission-callback.ts` for every gated tool (about 15 tools, not only the eight), with its test; it is a defect fix independent of the flag and a revert must not touch the feature. Then the approval flow behind the flag: `permission-callback.ts` takes `deps.approval` (injected, so the callback stays unit-testable without Supabase), `tool-tiers.ts` `APPROVAL_REQUIRED_TOOLS`, a `server/approval/waiters.ts` registry keyed by approval id, and a guard that `review_gate_response` can never resolve an approval waiter. The email handler's body-hash check is left as it is (the gate hash over the snapshot already binds what runs).
- 2.2 WS types, `ws-handler.ts` decide and reattach, `chat-state-machine.ts`.
- 2.3 Ops: static-message Sentry ops and `SOLEUR_APPROVAL_*` markers; confirm the Vector allowlist admits the marker family.

### Phase 3 — surfaces and notifications

- 3.1 `approval-request-card.tsx`, landing page, decide route, inbox row, nav badge, notification copy and the push-dispatch split.

### Phase 4 — cron, flag, infra

- 4.1 `cron-approval-expiry.ts` and its five registrations, Sentry cron monitor TF.
- 4.2 Flag plumbing in the four repo files; `flag-create` hand-over note in the PR.

### Phase 5 — governance

Commit order in the one PR (so a revert stays surgical): (1) the timeout-deny defect fix, (2) migration, RPCs and service, (3) gate wiring and WS, (4) surfaces and notifications, (5) cron and flag, (6) C4, (7) legal, (8) ADR.

- 5.1 ADR-307 (provisional) via `soleur:architecture`, plus ADR-284 and ADR-085 amendment notes.
- 5.2 C4: `approvalStore` element, edges, description fixes, `views.c4` include, regenerate `model.likec4.json`, parity counts +1 (monitors) in prose.
- 5.3 Legal (own commit; Ruled by CLO agent 2026-10-27: public documents stay in this PR with 'not yet switched on' wording; no precedent defers them to a flip PR, and the flip is a Flagsmith toggle that nothing enforces as a PR): Art. 30 entry (or PA-14/PA-16 amendment), DPD §2.3, GDPR Policy, Privacy Policy and both mirrors with `legal-doc-shas.ts` (Privacy Policy, DPD and GDPR Policy only; no Terms change, no `TC_VERSION` bump), the anonymise RPC with its `account-delete.ts` call site, `dsar-export-allowlist.ts`, a `compliance-posture.md` header comment and an Active Items row 'Approval queue: public wording and enabling gate' (trigger: before `approval-queue` is ON for any workspace except a Jikigai-owned canary; gates enabling, not the merge). Wording: conditioned on the merge, never past tense; says the feature is switched off and nothing is processed until enabled; no present-tense control claim ('single-use', 'expires in 24 h', 'bound to the exact action') until probe-measured; never 'every outward action requires your approval'; states the retention purpose and the lawful basis per column; marked draft pending counsel review. The row closes only when (a) the Phase 5.4 probe passes and is recorded, (b) a CLO attestation is discharged in `knowledge-base/legal/audits/`, (c) a docs PR removes the qualifier sentence and re-pins the SHAs, and (d) `gdpr-gate` is recorded; `flag-create` and `flag-set-role` are made to refuse a non-canary ON while the qualifier string remains in the two policy files or the row is open.
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

Updated after the round-2 fix verification so the block matches what shipped (ADR-307 is the decision record). Layer numbers are the seven layers of `observability-coverage-reviewer`: layer 1 = Inngest sentry-correlation middleware, layer 2 = `reportSilentFallback` / pino mirror to Sentry.

```yaml
liveness_signal:
  what: Sentry cron monitor `scheduled-approval-expiry` (Inngest heartbeat check-in from cron-approval-expiry on every run, regardless of the flag) plus the SOLEUR_APPROVAL_SWEEP stdout marker in Better Stack; the warn op `gate_unanswered` for a request pending more than 15 minutes is a separate signal and is emitted BY the sweep
  cadence: every 5 minutes
  alert_target: none yet for the monitor. The Sentry cron monitor is declared-unrouted under the two-PR rule (`cron_monitor_alert_unrouted` in cron-monitor-alerts.tf): a monitor cannot be routed in the PR that creates it. Routing it into `cron_monitor_failure` is item 3 of the ADR-307 flip checklist, done in a follow-up PR before the flag is turned on for anyone. Routed email alerts that exist in this PR: approval-gate-unanswered, approval-key-unavailable, art17-approval-anonymise-failed.
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (monitor), apps/web-platform/infra/sentry/cron-monitor-alerts.tf (declared-unrouted entry), apps/web-platform/server/inngest/functions/cron-approval-expiry.ts (heartbeat), apps/web-platform/infra/sentry/issue-alerts.tf (the three issue alerts)

error_reporting:
  destination: Sentry project web-platform via reportSilentFallback(null, ...) and warnSilentFallback in server/observability.ts, through the single registry server/approval/ops.ts (every op carries feature=approval-queue and its own static message; error-level ops pass a literal null first argument so the pino mirror cannot steal the capture)
  fail_loud: error-level ops approval-create-failed, approval-gate-failed, approval-bind-failed, approval-decide-failed, approval-landing-read-failed, approval-sweep-failed and approval-key-unavailable; warn ops approval-wait-timeout, approval-expired, approval-consume-rejected, approval-reproposed, approval-notify-failed, approval-reattach-failed, approval-inbox-enrich-failed, approval-cap-reached, approval-invalid-input, approval-consumed-aborted, approval-wait-read-failed, approval-viewer-role-failed, approval-flag-read-failed, approval-grant-refused and gate_unanswered; account-delete step 5.16 reports feature=account-delete op=anonymise-approval-request

failure_modes:
  - mode: Owner never answers; the request sits pending
    detection: layer 2 (reportSilentFallback -> pino/Sentry): flag_unanswered_approvals() in the sweep makes the cron fire the warn op gate_unanswered once per request after 15 minutes
    alert_route: sentry_alert.approval_gate_unanswered (feature=approval-queue, op=gate_unanswered, event_frequency_count 1h/0 so every request re-pages) emailing issue owners
  - mode: the approval HMAC key is unavailable (SENTRY_USERID_PEPPER unset or empty); every gated call is denied
    detection: layer 2 (reportSilentFallback(null, ...) -> Sentry): its own error-level op approval-key-unavailable, not the shared approval-gate-failed
    alert_route: sentry_alert.approval_key_unavailable (feature=approval-queue, op=approval-key-unavailable, frequency_minutes 44) emailing issue owners
  - mode: Art. 17 anonymise step fails, which aborts the user's account deletion
    detection: layer 2 (reportSilentFallback(null, ...) -> Sentry): feature=account-delete op=anonymise-approval-request from both the RPC-error and the thrown-error branch
    alert_route: sentry_alert.art17_approval_anonymise_failed emailing issue owners
  - mode: approval expires with nothing run
    detection: layer 2 (warnSilentFallback -> Sentry): the cron fires the warn op approval-expired for each expired row, and notifies the Owner
    alert_route: Owner inbox item and generic push; Sentry warn event for the operator (no issue alert)
  - mode: consume rejected because the input changed, the row was already used, or a decider or requester lost their role
    detection: layer 2 (warn): consume_approval returns no row; op approval-consume-rejected with the tool name, request id and reason
    alert_route: Sentry warn event with no issue alert; its rate is the rollout metric reviewed at the enabling gate
  - mode: an approved call reaches a handler and the execution grant is missing, the workspace changed, or the commit does not match
    detection: layer 2 (warn): op approval-grant-refused with extra.reason and extra.tool, from the three grant-checked handlers; the agent also gets a terminal refusal text
    alert_route: Sentry warn event with no issue alert; reviewed as a rollout metric
  - mode: pending-request caps reached (5 per conversation, 20 per workspace)
    detection: layer 2 (warn): op approval-cap-reached; the agent gets the static "too many pending requests" deny
    alert_route: Sentry warn event with no issue alert
  - mode: approval consumed but the call was aborted before it ran, or the wait's database reads fail
    detection: layer 2 (warn): ops approval-consumed-aborted and approval-wait-read-failed (one per wait, carrying the failed-poll count)
    alert_route: Sentry warn events with no issue alert; rates reviewed at the enabling gate
  - mode: push or email notification failed
    detection: layer 2 (warn): dispatch error caught; op approval-notify-failed; the inbox item still exists because the RPC writes it, and the push is dispatched separately afterwards
    alert_route: Sentry warn event with no issue alert; the inbox item remains the fallback surface
  - mode: cron stops running or the sweep RPC fails
    detection: Sentry cron monitor `scheduled-approval-expiry` missed or errored check-in (inngest-heartbeat) and layer 1 (Inngest sentry-correlation middleware) for a thrown function; a failed RPC emits the error-level op approval-sweep-failed and the SOLEUR_APPROVAL_SWEEP marker stops
    alert_route: none until the flip checklist routes the monitor (declared-unrouted by the two-PR rule; accepted deviation recorded in ADR-307). Until then a dead sweep is not paged; the flag is off, so nothing depends on it yet. approval-sweep-failed is an error-level Sentry event with no issue alert.

logs:
  where: web-platform stdout markers SOLEUR_APPROVAL_REQUESTED, SOLEUR_APPROVAL_DECIDED, SOLEUR_APPROVAL_CONSUMED and SOLEUR_APPROVAL_EXPIRED and, on every cron run regardless of the flag, SOLEUR_APPROVAL_SWEEP with counts in Better Stack (the whole lifecycle is reconstructable from one grep), plus Sentry for fault ops
  retention: Better Stack retention window; Sentry project retention

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_APPROVAL_SWEEP
  expected_output: SOLEUR_APPROVAL_SWEEP
  credentials_required: Better Stack read token via Doppler prd_terraform — the production marker stream has no unauthenticated substitute that proves the markers reach the aggregator; the sweep marker is emitted every five minutes even while the flag is off, so the probe is valid on a dark deploy
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

**Assembly.** Every path that can return `allow` for a slice-1 tool: the gated branch of `createCanUseTool` (used by `agent-runner.ts` and `cc-dispatcher.ts`, each registering its own tool set, so the census asserts registration per runner), the SDK `allowedTools` option (which bypasses `canUseTool` when a tool name is listed, measured in Phase 0.1), the shared `allow()` which always sets `updatedInput: toolInput`, the MCP registration and permission allowlist names, and the consume RPC. The Bash autonomous bypass and the 60-minute approve-prefix cache live only in the Bash branch and cannot launder platform tools; a regression test pins that. The chokepoint is `createCanUseTool`; the consume RPC is the single place that turns an approval into an allow.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop `action_sha256 = p_hash` from the consume predicate | RED |
| 2 | drop `expires_at > now()` from the consume predicate, or from `decide_approval` | RED |
| 3 | make consume non-single-use (no status change to `consumed`) | RED |
| 4 | remove the `is_workspace_owner` check in `decide_approval` | RED |
| 5 | return `allow` when the wait throws, times out or aborts | RED |
| 6 | build the card view from the tool input instead of the canonical object (preview built from different data than the hash) | RED |
| 7 | remove one slice-1 tool from `APPROVAL_REQUIRED_TOOLS`, or list one in `allowedTools` while the flag is on | RED |
| 8 | hand `allow()` an object other than the hashed snapshot (mutate the input between hash and allow) | RED |
| 9 | let `decide_approval` record `approved` for an archived conversation | RED |
| 10 | after a compliant first request, approve a second pending request for the same tool with a different hash and consume it with the first approval | RED |
| 11 | let `create_approval_request` return an `approved` row to the wait loop instead of consuming at once | RED |
| 12 | make the dispatch census report zero tools checked and exit 0 (vacuous) | RED |

(An unvalidated decision string is covered by the database CHECK and the zod enum, tested as ordinary unit tests, not as mutation rows.)

**Harness rows.** (a) Remove the assertion that `canUseTool` is invoked in the real-SDK probe; the suite must go RED. (b) A must-PASS case that is not the canonical: the same tool with the same arguments supplied in a different key order, which must hash equal and consume (strings are not normalised, so any string difference must hash differently).

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
| 5 | register a slice-1 tool in one runner but not the other without a recorded reason | RED |

## Architecture Decision (ADR/C4)

### ADR

Create ADR-307 (provisional; re-check against fresh `origin/main` before merge, 305 and 306 are taken on main) "Durable, action-bound approval requests" via `soleur:architecture`: the decision (new table, consume in `canUseTool`, Owner-only decide, no server-side execution, flag-gated), alternatives (Cut List and Alternatives table), and the relationship to ADR-284 (memory-less lane unchanged), ADR-085 (source CHECK widened), ADR-060 (hash-bound single-use precedent), ADR-249/264 (operator TTY ack kept). Amend ADR-284 and ADR-085 with a dated note. Related ADRs also cited: ADR-027 and ADR-068 (process-local state and multi-host, which the waiter plus database read answers). The ADR records that the CTO ruling's 'extend `action_sends`' was superseded by a new table (`grant_id` NOT NULL, send-shaped) so it is not re-litigated, and carries an 'Adding a gated tool' checklist (canonical field list, render entry, zod cross-check, copy-deck string, `APPROVAL_REQUIRED_TOOLS` or exempt-with-reason; the census test failure message points at it). Flag lifecycle: owner and removal trigger are recorded in the ADR (remove `approval-queue` and the old in-memory path for the eight tools once the flag has been ON for all workspaces for 30 days with consume success above the agreed threshold). Status `adopting` until the flag is flipped and the path is measured.

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
| GDPR-Art-6 | Important | New table columns need a `-- LAWFUL_BASIS:` annotation | Migration 180 annotates every personal-data column (`requested_by_user_id`, `decided_by`, `canonical_action`) with the basis recorded in the Art. 30 entry (performance of the user's own request for the action text; legitimate interest in an accountable audit trail for the decision fields); added to AC13 |
| GDPR-Art-5e | Important | Retention metadata for a personal-data table | Migration comment and Art. 30 entry state: `canonical_action` nulled 30 days after the terminal state; decision metadata is retained and anonymised on erasure, following the migration 161 `audit_github_token_use` precedent (not `action_sends`, whose `user_id` is `RESTRICT`); a solo workspace's rows are deleted on erasure (ADR-307 invariant 3). Because indefinite retention needs a stated purpose, the Art. 30 entry must name it (accountability for outward actions taken on a user's behalf) or set a bounded period; the CLO confirms in the Phase 5.3 task |
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
| ADR-307, ADR-284/085 amendments, C4 edits | — | inferred — justification: architecture decisions are a plan deliverable (wg-architecture-decision-is-a-plan-deliverable) |
| legal documents, anonymise RPC, DSAR allowlist | "gdpr-gate (persisted approval records)" | asked |
| real-SDK probe | "SDK behaviour when canUseTool throws" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `knowledge-base`, `plugins/soleur`, `.github`
- Planned files: ~58 | Estimated changed lines: ~2400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the thresholds are exceeded and the offer to split is declined with a reason: the only natural seam (backend plus RPCs versus UI) leaves a dark backend with no decide surface that the real-SDK probe and the Owner can verify end to end, the operator asked for one PR per issue, and a flag-off deploy makes the whole diff inert until a separate rollout decision. The review panel and the mutation battery carry the added risk.

## Files to Create

- `apps/web-platform/supabase/migrations/180_approval_request.sql`, `180_approval_request.down.sql`
- `apps/web-platform/supabase/verify/180_approval_request.sql`
- `apps/web-platform/server/approval/canonical.ts`, `render.ts`, `service.ts`, `waiters.ts`, `tools.ts` (`APPROVAL_REQUIRED_TOOLS` and the exempt set)
- `apps/web-platform/server/inngest/functions/cron-approval-expiry.ts`
- `apps/web-platform/components/chat/approval-request-card.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/[id]/page.tsx` (directory convention confirmed at work time)
- `apps/web-platform/app/api/approvals/[id]/decide/route.ts`
- `apps/web-platform/scripts/dev-probe-approval-gate.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-307-durable-action-bound-approval-requests.md`
- `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md`
- Tests under `apps/web-platform/test/` (approval canonical, service, permission-callback gated branch, WS decide and reattach, cron, tool-map census, card, landing page, inbox row) and `apps/web-platform/test/rls-fuzz/` entries

## Files to Edit

- `apps/web-platform/server/permission-callback.ts`, `tool-tiers.ts`, `review-gate.ts` (shared wait helper only if needed), `ws-handler.ts`, `notifications.ts`, `account-delete.ts`, `dsar-export-allowlist.ts`
- `apps/web-platform/lib/chat-state-machine.ts`, `lib/feature-flags/server.ts`, `lib/types` WS message unions
- `apps/web-platform/components/inbox/inbox-item-row.tsx`, `components/dashboard/inbox-nav-badge.tsx`
- `apps/web-platform/server/inngest/cron-manifest.ts`, `execution-placement.ts`, `routine-metadata.ts`, `app/api/inngest/route.ts`
- `apps/web-platform/infra/sentry/cron-monitors.tf`, `infra/sentry/alert-reference.json`, `infra/sentry/issue-alerts.tf`, `.github/workflows/cutover-inngest.yml`, `apps/web-platform/.env.example`
- `apps/web-platform/test/rls-fuzz/table-grants.ts`, `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 85 to 86, with its PLACEMENT/TRUTH/NO-SUBSTITUTE comment)
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
- [ ] AC4. `decide_approval` is refused for a non-Owner and for an unauthenticated actor, is idempotent for a repeated same decision, and refuses the opposite decision; a forged `approval_decide` payload (the actor is `auth.uid()` from the tenant client, never a parameter) cannot carry a different user id.
- [ ] AC5. Live path: an Owner decision inside the window releases the call; a wait that ends undecided denies with the static "saved, do not retry" message and the row stays `pending`; a later approval makes the next identical proposal consume it once.
- [ ] AC6. On session attach, live `pending` and `approved` requests for the conversation are re-sent as cards; a resolved or expired one shows its final state.
- [ ] AC7. The cron expires due rows, flags unanswered rows once, scrubs `canonical_action` 30 days after the terminal state, and a second run is a no-op (test).
- [ ] AC8. Each new Sentry op has its own static message; a grep test fails if two ops share a message string; `SOLEUR_APPROVAL_*` markers are admitted by the Vector allowlist (verified by reading the allowlist, not assumed).
- [ ] AC9. The tool-map census (Guard 2) and the mutation battery (Guard 1, every matrix row plus the harness rows) are green, and every mutation lands RED on a pristine copy with a green unmutated control; `scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC10. The real-SDK probe, built through the real `buildAgentQueryOptions` path and pointed at the dev Supabase project only (`hr-dev-prd-distinct-supabase-projects`), was run before the build (Phase 0.1) and again on the finished branch; `phase-0-measurements.md` has one result line per slice-1 tool name and shows `canUseTool` invoked for every slice-1 tool name and the deny honoured, and records whether `allowedTools` short-circuited it (with the `buildAllowedTools` fix and census test if so). A census test asserts each slice-1 tool is registered in each runner or exempt with a reason.
- [ ] AC11. Migration 180 applies and reverts cleanly; `table-grants.ts` classifies the table; the RLS fuzz and the grants gate are green; no INSERT/UPDATE/DELETE policy exists.
- [ ] AC12. ADR-307 exists (ordinal re-checked against fresh `origin/main`), C4 files edited and `model.likec4.json` regenerated, `c4-model-freshness`, `c4-count-parity` and the C4 render tests green.
- [ ] AC13. Legal documents, Art. 30 entry, anonymise RPC and DSAR allowlist entry are in the PR and the `gdpr-gate` result is recorded; migration 180 carries `-- LAWFUL_BASIS:` annotations and a retention comment; `anonymise_approval_request` has a call site in `account-delete.ts` with a test; the Art. 30 entry states the retention purpose for the decision metadata; no copy claims "every outward action requires your approval".
- [ ] AC13b. No site page, changelog entry, release note or epic text uses 'approval queue' or 'human-in-the-loop' as a coverage claim before the enabling-gate row closes.
- [ ] AC14. The approved wireframe delta (Phase 0.2) is committed, and no card, thread line, notification or copy-deck string claims an outcome ("sent", "ran") or an execution on approve that slice 1 does not perform; a string-level test over the copy deck constants asserts the absence of the outcome words `sent`, `ran`, `executed` and `delivered` and the presence of "Released to your agent" (the approved consequence line legitimately contains "send", so the test is scoped to outcome words).
- [ ] AC14b. `decide_approval` on an archived or deleted conversation returns "conversation closed" and records nothing; an approved-but-never-consumed request expires with `expired_reason='unconsumed'` and no push; a decision removes the linked inbox item from the `action_required` count; a second Owner deciding at the same time receives the final row ("already decided by <name>").
- [ ] AC14c. `decide_approval` refuses an overdue row and flips it to `expired` inline; a re-proposal that finds an `approved` row consumes it at once with no card and no wait; account erasure succeeds against rows with set user columns (write-once trigger carve-out test).
- [ ] AC15. `soleur:review` runs with `user-impact-reviewer` and the review findings are resolved; PR body carries `Closes #4672` and `Closes #5351`, and its first line answers 'does merging this alone mutate production?': it applies migration 180 to production and creates one Sentry cron monitor through the existing Sentry apply workflow, with the flag off and no behaviour change other than the timeout deny.

### Post-merge (operator and verification)

- [ ] AC16. Migration 180 is applied to production by the deploy pipeline (agent verifies through the deploy run, not by hand).
- [ ] AC17. The Flagsmith feature `approval-queue` is created through `soleur:flag-create` (typed-yes write handed to the operator, ADR-249); the flag is not flipped by this plan.
- [ ] AC18. After the first deploy the Sentry cron monitor `cron-approval-expiry` shows a check-in (read by the agent from Sentry).
- [ ] AC19. #10443 is closed as a duplicate of #4672 with a pointer to the PR; the consolidated deferral issue #11300 exists.

## Test Scenarios

- Canonicalization: stable hash across key order; NFC and NFD variants of the same text hash differently (no normalisation); every field change flips the hash; no truncation of a 100 KB body.
- Consume: happy path once; replay; concurrent double-consume (one wins); changed input; wrong conversation; expired; rejected row.
- Decide: Owner approve, Owner deny, member refused, signed-out refused, opposite decision refused, two Owners deciding at once (first wins, second sees the final state).
- Gate wait: decision in window, timeout, abort, restart mid-wait, decision made on another host (poll picks it up).
- Reattach: reload during a pending request; reload after approve; reload after expiry.
- Flag: off for the whole matrix; flag turned off while requests are pending (existing rows stay readable and decidable, new calls take the old path).
- Cron: expiry notifies once; unanswered flagged once; scrub nulls text and keeps the audit fields; rerun idempotent.
- Surfaces: card states (pending, approving, approved-waiting-for-agent, released, denied, expired, action changed, non-owner waiting); inbox row expiry chip; landing page for Owner, signed-out and member.
- Erasure: account delete anonymises both user columns and the text; DSAR export includes the row without the raw text after the scrub.

## Risks and Deferrals

- **Rollout is a dogfood slice (CPO):** the wait, deny, approve, ask-again loop and byte-identical replay will feel broken to a wider audience and `approval-consume-rejected` is likely high for free-text tools. No enablement beyond a Jikigai canary until consume success is measured over a stated window and the enabling-gate row closes; the deny text tells the agent to call again with exactly the same arguments. Roadmap: milestone `Phase 4: Validate + Scale` (same as #10443, #9776, #10111).
- **Approval fatigue and consequence-text drift** (CPO) are controlled by the narrow slice, the server-built view and AC2; the approve rate is tracked through the `SOLEUR_APPROVAL_DECIDED` markers.
- **Real-SDK behaviour on throw is inferred** until Phase 0.1; the deny-on-reject fix does not depend on the answer.
- **Cross-host decide** relies on the 5-second poll; a request decided on another host is seen within five seconds, not instantly.
- **ADR ordinal** is provisional.
- **Deferred (one consolidated tracking issue, #11300, filed because the deferral rule requires it; it also carries flag retirement):** approval outcome recording ("ran" / "failed" card states), server-side execution of an approved payload after the session died, cross-host instant wake-up, a one-hour reminder push, a requester cancel control, a persisted thread line telling the requester how a request was decided, and migrating the Bash must-ask lane to the new table. Related existing issues stay as they are: #9388, #5331, #10196, #4674, #9776, #10111.
- **Egress collection flag and #11237 steps:** untouched by this plan.
