---
title: Durable, action-bound approval requests for high-risk gated agent tools
status: adopting
date: 2026-10-29
supersedes: none
issue: 4672
related: [4672, 10443, 5351, 11289, 11303, 9601, 10196, 9543, 9776, 10111, 8532]
related_adrs: [ADR-027, ADR-060, ADR-068, ADR-085, ADR-249, ADR-264, ADR-284, ADR-303, ADR-305]
tags: [security, hosted, permission-callback, review-gate, approval, rls, flag-gated]
brand_survival_threshold: single-user incident
---

# ADR-307: Durable, action-bound approval requests for high-risk gated agent tools

## Context

A gated agent action waits on an in-memory promise (the `review_gate` card, 5-minute timeout, lost on restart or reconnect). That wait leaves no
audit row, binds nothing between what the user saw and what runs, and cannot reach an Owner who is away. ADR-305 (#11303) made `canUseTool` the only
approver of gated platform tools; this ADR builds the durable flow on top of it for the highest-risk subset.

Forces:

- The Owner must be able to answer after the agent session ended, in the product, without a command (P1).
- An approval must authorise exactly one execution of exactly the action the Owner saw (P2). The existing card text is display-only and lossy
  (it omits `force`, a PR body, workflow `inputs`, a settings value, and truncates an email body), so the binding cannot be derived from the preview.
- ADR-060 rejected a bare `approved_at` column as forgeable and adopted a body-hash-bound single-use approval; that is the precedent for the binding.
- ADR-284 chose a memory-less ask lane ("no new approval surface", no acknowledgement and no cache entry) for hosted Bash. This ADR does not change that lane.
- ADR-085 reserved `approval_required` as an inbox `source` for #4672.
- The agent runs in the same Node process as the server and the Owner's WebSocket handler (see Residual risk).

## Considered Options

- **Option A: a new `approval_request` table, consumed inside `canUseTool` (chosen).** One row per exact action, forward-only status machine,
  write-once decision columns, an Owner-only `decide_approval` RPC, no server-side execution. Pros: durable, audit-bearing, bound to a hash of the
  full canonical input, answerable from a card, an inbox row or a push landing page. Cons: a new table, RPC set, cron and flag to own.
- **Option B: widen `action_sends`.** Rejected. `grant_id` is NOT NULL (FK to `scope_grants`), `tier_at_send` is a four-value CHECK and the pure-reject
  trigger covers send-shaped columns; an approval exists before any send and has no grant. The CTO ruling's "extend `action_sends`" is therefore
  superseded by a new table. This is recorded so it is not re-litigated; the ruling's intent (no new file-backed queue, reuse the gated tier) is kept.
- **Option C: a file-backed queue under `knowledge-base/` (the issue's suggestion).** Rejected by the CTO ruling: P1 is served by a row the product can already read.
- **Option D: a per-request Inngest `step.sleepUntil` function.** Rejected: one 5-minute cron serves expiry, the unanswered flag and the scrub with one task surface.
- **Option E: server-side execution of an approved payload after the session died.** Deferred: a different principal and a larger change. Slice 1 only
  releases the agent's next identical call once.
- **Option F: a second WORM decision-log table.** Rejected: write-once columns plus forward-only transitions on the one table give the same history.
- **Option G: keep the in-memory gate and add only the timeout fix.** Rejected for these tools: it does not give P1, P2 or an audit row. The timeout-deny fix itself is
  not part of this decision; ADR-305 owns it.

## Decision

Adopt Option A for eight gated platform tools, behind the Flagsmith flag `approval-queue` (default off, absent means off, fail closed on a flag error):
`email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`,
`workspace_set_autonomous`. Every other gated tool stays on the existing in-memory review gate, byte-identical.

Flow. In the gated branch of `canUseTool` (the same branch ADR-305 and ADR-284 use), with the flag on and the tool in `APPROVAL_REQUIRED_TOOLS`:
the full canonical action is hashed before the first `await`, a service-role RPC creates (idempotently) the request and its inbox item, the Owner is
notified with content-free text, and the agent waits at most 5 minutes (wake on the in-process decide, plus an abortable poll of one indexed row about every
5 s, at most 60 reads, so a decision made over HTTP on another host is seen). A decision inside the window releases the call through an atomic consume.
A wait that ends undecided denies with a static "saved for the workspace Owner; do not retry now" message and leaves the row `pending`; a later approval
lets the next byte-identical proposal in the same conversation consume the approved row once.

### Invariants

1. **Action-bound.** `action_sha256 = sha256(canonicalJSON({tool_name, workspace_id, conversation_id, action}))`, over every field that changes what runs, keys sorted,
   strings hashed exactly as supplied (no Unicode normalisation), nothing truncated. The card view is rendered from the same canonical object, so display and hash cannot drift.
   The object handed to `allow()` is the same deep-cloned snapshot that was hashed.
2. **Single use.** Consume is one atomic conditional `UPDATE ... WHERE status='approved' AND expires_at>now() AND action_sha256=p_hash AND conversation_id=p_conversation`.
3. **Forward-only, write-once.** A trigger allows only `pending -> approved|rejected|expired` and `approved -> consumed|expired`; identity, hash, tool, expiry and
   decision columns are write-once; every write outside the RPCs is refused. Only the account-erasure carve-outs (a row-level `SET NULL` of the user FKs, the workspace-cascade DELETE) and
   the GUC-gated scrub of `canonical_action` are permitted exceptions.
4. **Owner-only decision, actor from the session.** `decide_approval(p_id, p_decision)` is granted to `authenticated` only and takes the actor from `auth.uid()`, never from a
   parameter; it re-checks `is_workspace_owner` and `expires_at > now()` at decision time. Every other RPC is `service_role` only.
5. **Expiry is bounded and never silent.** 24 h expiry; the cron is never the authority (an overdue row is expired inline by the decide RPC); `canonical_action` is nulled 30 days after the terminal state;
   an unanswered request is flagged once after 15 minutes.
6. **Content-free off-session notifications.** Push and email carry no action text (#8532); the surface is the in-product card.
7. **Honest consent.** "Approve" releases the agent's next identical call once; it does not execute anything and the record claims no tool outcome (`consumed` means released to the agent).
8. **`review_gate_response` can never resolve an approval waiter**; the approval path has its own wire types (`approval_request`, `approval_status`, `approval_decide`) with no option strings, so "approve all" cannot be expressed.

### Flag-off posture

With `approval-queue` off (the state at merge), no request is created, shown, emitted or notified, no cron work is done for new rows, and the gate behaves as
ADR-305 left it. The code paths are dormant by construction (the flag seam is the only reader). Flipping the flag is not part of this decision and is not done by the PR that lands it.

### Residual risk: sentinel discipline (the DB grant is not a barrier)

The agent session runs in the same process as the server and the Owner's WebSocket handler, and the process can mint a tenant client for the founder. Granting `decide_approval` to
`authenticated` therefore does not by itself stop a compromised or prompt-injected agent path from calling it as the founder: **the barrier is code discipline, and it is only as strong
as its sentinel.** What exists:

- No MCP tool exposes a decide capability, and the sandboxed Bash tool holds no database credential (ADR-272).
- The sentinel test `test/approval/decide-boundary.test.ts` pins three conjuncts: the `decide_approval` RPC name appears in exactly one source module; that module has exactly the allowlisted
  importers (today the WebSocket handler); and a static, dynamic and re-export import walk from the gate side and every MCP tool builder never reaches it (the WebSocket handler is treated as the process hub and not traversed,
  because it is reachable from every module that sends a notification, which is why the plan's stronger "nothing reachable" form is unsatisfiable).

What it does not cover: an RPC name assembled at runtime, a new importer added together with its allowlist entry, or a code path that obtains a tenant client and calls `decide_approval` through a
channel the grep does not model. A prompt-injected agent that can only emit tool calls cannot do this; arbitrary code execution in the server process can, and is outside this decision's threat model
(it already holds the founder's tenant client for the CRM and other tools). Moving the decide path out of the agent's process (a separate service principal) is the real fix and is a follow-up, not a slice-1 claim.

### Relationship to other ADRs

- **ADR-305** is the prerequisite and is unchanged: gated tools never enter `allowedTools`, and the shared `holdForUser` lifecycle fails closed. This ADR adds a second stage inside that gated branch.
- **ADR-284** (memory-less must-ask lane for hosted Bash) is unchanged for Bash. A durable single-use request extends the idea of an ask to platform tools, which that ADR's wording ("no new approval surface") did not contemplate; see its dated Addendum.
- **ADR-085**: the inbox `source` CHECK is widened to include `approval_required`, as that ADR reserved; see its dated Addendum. The per-Owner recipient-state join stays deferred: the approval row carries its own state and the decide RPC moves the linked inbox item out of the `action_required` count in the same transaction.
- **ADR-060**: its body-hash-bound single-use approval is the precedent. The email handler's own `approvedBodySha256` stays as it is; it is computed from the same arguments at handler time and binds nothing independent of the gate, so the gate hash over the snapshot is the binding.
- **ADR-249 / ADR-264**: the operator TTY ack and staged operator scripts are unchanged. They cover operator production writes, a different principal; this queue covers a founder's agent acting on the founder's behalf.
- **ADR-027 / ADR-068** (process-local state, multi-host): the in-process waiter is an optimisation; correctness never depends on it, because every wait re-reads the row.
- **ADR-303**: the new public relation declares its Data API grants and is classified in `table-grants.ts`.

## Adding a gated tool

This is the single source of the checklist; other sites point here. A new gated platform tool must either join the approval queue or be exempted with a reason; the census test fails until it is classified.

1. Add its canonical field list (every input field that changes the outcome, plus server-derived fields) in `server/approval/canonical.ts` and cross-check it against the tool's zod schema (`canonical-schema-drift` test).
2. Add its `renderApprovalView` entry in `server/approval/render.ts` (rendered from the canonical object, never from the legacy `buildGateMessage` preview).
3. Add its copy-deck verb phrase (and keep the push and email text content-free; the copy-deck string test bans outcome words).
4. List it in `APPROVAL_REQUIRED_TOOLS`, or add it to `APPROVAL_EXEMPT_TOOLS` with a one-line reason.
5. Widen the `approval_request.tool_name` CHECK in a new migration (a joined tool only).
6. Re-run the real-SDK probe (`apps/web-platform/scripts/dev-probe-approval-gate.ts`) after any SDK, tier-map or option-builder change (ADR-305).

## Flag lifecycle

Owner: Jikigai engineering (CTO lane); the flag is created through `soleur:flag-create` with the typed-yes write handed to the operator. Removal trigger: remove `approval-queue` and the old in-memory path for these eight tools once
the flag has been ON for all workspaces for 30 days with consume success above the agreed threshold (the rate of `approval-consume-rejected` is the measure of the "byte-identical arguments" wording). Public-document wording is
gated separately (the compliance posture row); this ADR does not enable the feature.

## Consequences

- An Owner can answer a high-risk action after the session ended, and every decision leaves a hash-bound, forward-only audit row that survives erasure of the action text.
- Slice 1 does not execute on approve: the agent must propose the identical action again, so a regenerated email body hashes differently and is not consumed. That friction is accepted and measured.
- One more table, six-plus RPCs, a 5-minute cron and a flag to maintain; every new gated tool pays the checklist above.
- The decide path stays code-discipline protected in the agent's process until it moves out (Residual risk).
- Nothing in this ADR is a measured production claim. Status is `adopting` until the flag is flipped for a canary and the path (consume success, unanswered rate) is measured.

## Cost Impacts

None for vendors. One additional Sentry cron monitor and one Inngest scheduled function (every 5 minutes, one database call). Row volume is bounded by gated-call volume for eight tools.

## NFR Impacts

None. No NFR register row changes tier.

## Principle Alignment

- AP-020 (Untrusted input at the agent boundary): Aligned. The tool call is model-controlled; the approval binds to a hash of the full canonical input and is consumed once. The in-process decide path is the stated residual risk, mitigated by a sentinel, not eliminated.
- AP-021 (Diagnostic honesty): Aligned. The card says "released to your agent", not "sent"; no outcome is claimed, and nothing here asserts a measured control.

## Diagram

C4: `platform.infra.approvalStore` ("Approval Requests") with `webapp -> approvalStore` and `engine -> approvalStore`, included in the `containers` view.
