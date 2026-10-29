---
title: Durable, action-bound approval requests for high-risk gated agent tools
status: adopting
date: 2026-10-29
supersedes: none
issue: 4672
related: [4672, 10443, 5351, 11289, 11303, 9601, 10196, 9543, 9776, 10111, 8532]
related_adrs: [ADR-027, ADR-029, ADR-060, ADR-068, ADR-085, ADR-249, ADR-264, ADR-284, ADR-303, ADR-305]
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

- **Option A: a new `approval_request` table, consumed inside `canUseTool` (chosen).** One row per exact action, a constrained status machine (forward-only except an Owner revoke before consume),
  write-once decision columns, an Owner-only `decide_approval` RPC, no server-side execution. Pros: durable, audit-bearing, bound to a hash of the
  full canonical input, answerable from a card, an inbox row or a push landing page. Cons: a new table, RPC set, cron and flag to own.
- **Option B: widen `action_sends`.** Rejected. `grant_id` is NOT NULL (FK to `scope_grants`), `tier_at_send` is a four-value CHECK and the pure-reject
  trigger covers send-shaped columns; an approval exists before any send and has no grant. The CTO ruling's "extend `action_sends`" is therefore
  superseded by a new table. This is recorded so it is not re-litigated; the ruling's intent (no new file-backed queue, reuse the gated tier) is kept.
- **Option C: a file-backed queue under `knowledge-base/` (the issue's suggestion).** Rejected by the CTO ruling: P1 is served by a row the product can already read.
- **Option D: a per-request Inngest `step.sleepUntil` function.** Rejected: one 5-minute cron serves expiry, the unanswered flag and the scrub with one task surface.
- **Option E: server-side execution of an approved payload after the session died.** Deferred: a different principal and a larger change. Slice 1 only
  releases the agent's next identical call once.
- **Option F: a second WORM decision-log table.** Rejected: write-once columns plus a constrained transition matrix on the one table give the same history.
- **Option G: keep the in-memory gate and add only the timeout fix.** Rejected for these tools: it does not give P1, P2 or an audit row. The timeout-deny fix itself is
  not part of this decision; ADR-305 owns it.

## Decision

Adopt Option A for eight gated platform tools, behind the Flagsmith flag `approval-queue` (default off, absent means off, fail closed on a flag error):
`email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`,
`workspace_set_autonomous`. Every other gated tool stays on the existing in-memory review gate, byte-identical.

Flow. In the gated branch of `canUseTool` (the same branch ADR-305 and ADR-284 use), with the flag on and the tool in `APPROVAL_REQUIRED_TOOLS`:
the full canonical action is hashed before the first `await`, a service-role RPC creates (idempotently, and subject to the pending caps below) the request and its
inbox item, the Owner is notified with content-free text (coalesced, see invariant 9), and the agent waits at most 5 minutes (wake on the in-process decide, plus an abortable poll of one indexed row about every
5 s, at most 60 reads, so a decision made over HTTP on another host is seen). A decision inside the window releases the call through an atomic consume.
A wait that ends undecided denies with a static "saved for the workspace Owner; do not retry now" message and leaves the row `pending`; a later approval
lets the next byte-identical proposal in the same conversation consume the approved row once.

### Invariants

1. **Action-bound.** `action_sha256 = HMAC-SHA256(key, canonicalJSON({tool_name, workspace_id, conversation_id, action}))`, over every field that changes what runs, keys sorted,
   strings hashed exactly as supplied (no Unicode normalisation), nothing truncated. The key is derived, not new: `key = HKDF-SHA256(SENTRY_USERID_PEPPER, info = "soleur:approval-request:action-sha256:v1")`
   (domain-separated by the HKDF `info`, so the key is not the pseudonymisation HMAC of any attacker-chosen string; the pepper already exists in `server/observability.ts` and backs ADR-029, so there is no new secret).
   The derivation is `deriveApprovalHashKey` in `server/approval/canonical.ts`, read at call time. An unset or empty pepper raises
   `ApprovalCanonicalError("key_unavailable")`, which the gate treats as a gate failure (static unavailable deny, reported as its own error-level op `approval-key-unavailable`, which has a routed Sentry alert). There is **no fallback to an unkeyed hash and no sentinel key**: fail closed.
   Why keyed: the hash is kept as the audit record after the 30-day text scrub and after erasure; an unkeyed hash over a low-entropy action (an `email_suppress` recipient) is dictionary-confirmable.
   The keyed hash is still personal data in the legal sense while the secret exists (pseudonymous, not anonymous); it is described as a keyed fingerprint of the action that cannot be reversed or
   confirmed without a secret held only by the server. The pepper only has to be stable for the life of a live row (at most 48 h): all recomputation is in-process (the gate and the hash it passes to consume, the reattach re-verify, and `view-model.ts`, which the push
   landing page and the inbox enrichment use to re-render a stored row), so **a rotation invalidates every live approval**: pending and approved rows fail closed as `hash_mismatch` ("needs a new approval"), and ADR-029
   pseudonyms change with the same secret. Drain or let live rows expire before rotating. The card view is rendered from the same canonical object, so display and hash cannot drift.
   The object handed to `allow()` is the same deep-cloned snapshot that was hashed.
2. **Single use, principals re-checked.** Consume is one atomic conditional `UPDATE ... WHERE status='approved' AND expires_at>now() AND action_sha256=p_hash AND conversation_id=p_conversation
   AND is_workspace_owner(workspace_id, decided_by) AND is_workspace_member(workspace_id, requested_by_user_id)`. The principal re-check is inside the same UPDATE (not a second read), so it cannot be raced:
   a decider demoted from Owner, a requester removed from the workspace, or an erased user (a NULL id makes the predicate NULL) leaves the row unconsumable. The reject reasons are `decider_not_owner` and
   `requester_not_member`, and the agent is told the approval can no longer be applied and a new one is needed from a current Owner. This also closes, for this feature, the #4307 gap that a role change does not invalidate a granted session capability.
3. **Constrained transitions, write-once facts.** A trigger allows exactly these transitions and no others:

   | From | To | Who |
   |---|---|---|
   | `pending` | `approved`, `rejected` | `decide_approval` (Owner) |
   | `pending` | `expired` | sweep or inline expiry |
   | `approved` | `consumed` | `consume_approval` (service role) |
   | `approved` | `expired` | sweep or inline expiry |
   | `approved` | `rejected` | `decide_approval` deny by an Owner (**revoke**), only for an unconsumed, unexpired row |

   The revoke path (`approved -> rejected`) is the one backward-looking edge: it only ever reduces authority, so it is allowed while consume is not. It has its own audit pair (`revoked_at`, `revoked_by`,
   write-once, settable only on that transition); `decided_at` and `decided_by` keep the approval facts. Revoke and consume serialise on the row lock and the conditional UPDATE, so exactly one wins; a
   revoke that loses the race reports `conflict`. A denied request is not sticky: a later re-ask finds no live row and creates a new pending request. Identity, hash, tool, expiry and decision columns are
   write-once, and every write outside the RPCs is refused. The permitted exceptions are only: (a) the account-erasure `SET NULL` of the user FKs (`requested_by_user_id`, `decided_by`, `revoked_by`),
   (b) the workspace-cascade DELETE, (c) the GUC-gated scrub of `canonical_action`, and (d) a **GUC-gated DELETE carve-out for a memberless workspace**: during account erasure a solo workspace's rows
   (`workspace_id` equals the erased user's id and no `workspace_members` row remains) are deleted by `anonymise_approval_request` under the dedicated erase GUC `app.approval_erase` (set only inside that function, reset before it returns; distinct from the text-scrub GUC `app.approval_scrub`),
   together with their `approval_required` inbox items. A DELETE outside the GUC, or while a member exists, still raises. A team workspace keeps its history with only the user columns nulled, **including a team
   workspace whose last member was erased** (its id is not the erased user's id; a memberless team workspace is an accepted residual, pinned as "rows retained" in `approval-request.tenant-isolation.test.ts`).
   For the same reason `verify/180` carries no row-level "no rows for an erased solo workspace" check: by catalog query it also matches that memberless team workspace and would fail `verify-migrations` on every later
   release; the falsifier is the integration test. The migration header carries the same matrix and carve-outs.
4. **Owner-only decision, actor from the session.** `decide_approval(p_id, p_decision)` is granted to `authenticated` only and takes the actor from `auth.uid()`, never from a
   parameter; it re-checks `is_workspace_owner` and `expires_at > now()` at decision time. The Owner check runs BEFORE the row lock is taken (the workspace is looked up without a lock), so a
   signed-in non-Owner who guesses a request id cannot lock it, and a missing row and a non-Owner return the same error. Every other RPC is `service_role` only.
5. **Expiry is bounded and never silent.** 24 h expiry; the cron is never the authority (an overdue row is expired inline by the decide RPC); `canonical_action` is nulled 30 days after the terminal state;
   an unanswered request is flagged once after 15 minutes. Each statement of the sweep (expire, flag, scrub) is bounded and indexed (at most 500 rows per statement per tick, `FOR UPDATE SKIP LOCKED`), so a backlog drains over successive ticks.
6. **Content-free off-session notifications.** Push and email carry no action text (#8532); the surface is the in-product card.
7. **Honest consent.** "Approve" releases the agent's next identical call once; it does not execute anything and the record claims no tool outcome (`consumed` means released to the agent).
8. **`review_gate_response` can never resolve an approval waiter**; the approval path has its own wire types (`approval_request`, `approval_status`, `approval_decide`) with no option strings, so "approve all" cannot be expressed.
9. **Bounded queue, coalesced nudges.** Caps are enforced in `create_approval_request` (the database, not TypeScript) and count rows that are `pending` AND unexpired (`expires_at > now()`): **5 per conversation** (error code `AP429`) and **20 per workspace**
   (`AP430`). An idempotent re-ask of an already-live request is never blocked by the cap. The count is a bound, not an invariant: a concurrent race can overshoot by at most the in-process `MAX_PENDING_GATES` (5, **per agent session**, so the overshoot grows with the number of concurrent sessions in a workspace)
   and there is no advisory lock. The gate maps each code to a static "too many pending requests" deny and a warn op. Notifications are coalesced: `create_approval_request` returns `notify`, true only when
   the request is new AND no other pending request in the workspace was created in the previous **10 minutes**; the card and inbox row are always created, only the push or email is suppressed (its text is
   content-free, so a coalesced nudge loses nothing). The 15-minute unanswered flag and the expiry notice are unchanged.

### Bound versus executed: ExecutionGrants

The hash binds the identifiers the Owner saw, but several handlers re-resolve content when they run, up to five minutes (the wait) after the gate. For a push the handler would otherwise push `HEAD`, which
may have moved during the wait. A per-session in-process side channel, `ExecutionGrants` (`server/approval/grants.ts`), closes the part of that gap which is closable without changing the tool schemas:

- **Mechanism.** The gate writes a grant immediately before `allow()` on BOTH allow paths (the live `approved` case and the `released` re-proposal case); the three handlers that need it read it once.
  A side channel is needed because the tool zod strips keys not in the schema and SDK `tool()` handlers get no reliable `tool_use_id`, so a binding cannot ride in `updatedInput` without letting the model supply it.
  The object is created once per user message (turn) in `agent-runner.ts` (`startAgentSessionInner`) and shared by closure between the gate deps and the tool builders; no MCP tool exposes it and the Bash sandbox holds no handle to it, so the model cannot forge it.
  A grant is keyed by `canonicalJson(zod-parsed handler args)` (the same `SPECS[tool].input.parse` on both sides, so defaults such as `force=false` match), is one-shot (`take` deletes), expires after 120 s,
  and the map is capped at 64 entries (oldest dropped).
- **Fail closed, sticky for the rest of the turn.** The gate sets `enforcing = true` as soon as the flag evaluates true in a turn. From then on a handler that finds no grant refuses with a TERMINAL message ("the action was NOT performed; do not retry in
  this conversation; start a new conversation"). If the flag is turned off, or its read errors, later in the same turn: the three grant-checked tools (`github_push_branch`, `kb_share_create`, `workspace_set_autonomous`) refuse at the
  handler, and the gate itself denies the other five approval-required tools with the static "approval unavailable" text instead of falling back to the legacy requester-answerable card, for the rest of that turn (the
  `ExecutionGrants` lifetime). The grants object is created per user message, so the next user message starts with a fresh, non-enforcing grants object and evaluates the flag again. This is accepted. When `grants` is never `enforcing` (the flag was never on in the turn), handler behaviour is byte-identical to before.
  Two accepted consequences of that lifetime, both bounded to the dark/cohort phase. (1) A flag read error on the FIRST gated call of a turn takes the same path as flag off: the legacy card runs. "Unreadable means off" is the accepted contract while the flag is dark or limited to the Jikigai canary; the flip checklist asks for a decision on hardening it before the flag goes wider. (2) A legacy card opened before enforcement began in the turn and approved afterwards lets the five tools without a handler grant check run on that legacy approval; the window is the card wait and is accepted.
  `grants` is a REQUIRED argument of the three builders, so a forgotten wiring is a compile error. Every grant refusal is reported as the warn op `approval-grant-refused` (`extra.reason`, `extra.tool`).
- **Hotfix boundary untouched.** The grant is written inside the existing `canUseTool` allow path; `allowedTools` and ADR-305 are unchanged.

| Tool | Disposition | Residual |
|---|---|---|
| `github_push_branch` | **Pin** the commit: the gate binds the derived head sha, `pushBranch` takes `commitSha` (40 or 64 hex, `git cat-file -e <sha>^{commit}` verified, refspec `<sha>:refs/heads/<branch>`), so exactly the approved commit is pushed even if `HEAD` moved. | None for the pushed commit. |
| `workspace_set_autonomous` | **Verify** at execution that the active workspace equals the granted workspace; refuse with `workspace_changed` on mismatch. | None for the workspace. |
| `kb_share_create` | **Verify** the workspace as above. | **Accepted:** the file's bytes. The Owner is shown a path, never content, so a content hash would bind a version nobody reviewed; `createShare` already stores `content_sha256` and re-issues on drift, so a link only serves the bytes hashed at create time. |
| `create_pull_request` | None. | **Accepted:** head and base are names; the approval covers opening the pull request only and does not review the changes on the branch (stated on the card). |
| `github_trigger_workflow` | None. | **Accepted:** the workflow runs as defined on `ref` when it starts. Ref-sha pinning needs a GitHub API call at gate time and is deferred (tracked). |
| `email_reply` | None. | **Accepted:** the recipient is derived from the same immutable inbound row at gate and handler. |
| `email_send`, `email_suppress` | Fully bound by the hash: every field is model-supplied input. | None. |

Residual risk, stated on the cards and here: *The approval binds the action's identifiers and, for a push, the exact commit. It does not bind the content a handler re-reads at execution for `kb_share_create`
(file bytes), `create_pull_request` (branch contents) or `github_trigger_workflow` (workflow file at the ref). Those stay residual and are stated on the card.* The detail
lines live in `apps/web-platform/server/approval/render.ts` (`PHRASES`, rendered from the canonical object); `lib/approval-copy.ts` is the client-safe copy deck for the verb phrases and fixed strings, not the detail lines. The three:
`kb_share_create` "Creates a public link to this file as it is when your agent creates the link. The file's contents are not shown here.";
`create_pull_request` "Opens a pull request between these branches. This approval covers opening the pull request only; it does not review the changes on the branch."; `github_trigger_workflow` "Runs the workflow as it exists on this branch or tag when it starts."

### Flag-off posture

With `approval-queue` off (the state at merge), no request is created, shown, emitted or notified, no cron work is done for new rows, and the gate behaves as
ADR-305 left it. The code paths are dormant by construction (the flag seam is the only reader). "Dormant" means no `approval_request` read: the reattach sites on session attach still do the attaching session's workspace
resolution and the flag read before the flag check short-circuits. Flipping the flag is not part of this decision and is not done by the PR that lands it.

### Residual risk: sentinel discipline (the DB grant is not a barrier)

The agent session runs in the same process as the server and the Owner's WebSocket handler, and the process can mint a tenant client for the founder. Granting `decide_approval` to
`authenticated` therefore does not by itself stop a compromised or prompt-injected agent path from calling it as the founder: **the barrier is code discipline, and it is only as strong
as its sentinel.** What exists:

- No MCP tool exposes a decide capability, and the sandboxed Bash tool holds no database credential (ADR-272).
- The sentinel test `test/approval/decide-boundary.test.ts` pins these conjuncts: the `decide_approval` RPC name appears in exactly one source module (`server/approval/decide.ts`); `decide.ts` has exactly the
  allowlisted importers, which are **two**: the WebSocket handler (`server/ws-handler.ts`, the `approval_decide` frame) and the HTTP decide route (`app/api/approvals/[id]/decide/route.ts`, the push landing page);
  and a static, dynamic and re-export import walk (a `.js` suffix resolves to its `.ts` source) from the gate side, every module under `server/approval/`, both runners (`agent-runner.ts`, `cc-dispatcher.ts`) and every MCP tool
  builder never reaches `decide.ts`. The walk skips type-only imports (`import type`, `export type`, `import { type X }`-only specifiers). The builder set is derived by CONTENT, not by filename: any module under
  `server/` (any depth) that value-imports `tool` or `createSdkMcpServer` from the Agent SDK, with a floor assertion on the count and a must-contain list (which includes `narrate-tool.ts`, a builder a `*-tools.ts` glob
  would miss) so a refactor cannot silently empty the walk. The WebSocket handler is the process hub and is not traversed. The hub is not unreachable, and the plan's stronger "nothing reachable" form is unsatisfiable: both runners
  import `sendToClient` from it directly, and `cost-writer.ts` (reached from `agent-runner.ts`) does too. The one tool builder that reaches the hub is `account-tools.ts`, through `account-delete.ts` -> `agent-runner.ts` ->
  `cost-writer.ts` -> `ws-handler.ts`; it is a NAMED exemption, and any other builder, approval module or gate-side module that starts reaching the hub fails the sentinel. Two further assertions bound the hub: no module
  outside the allowlisted set imports `handleMessage` (or any value export) from `ws-handler`, no gate-side, approval or builder module value-imports `ws-handler` directly, and every hub export imported by anything reachable
  is one of the two senders (`sendToClient`, `forceDisconnectForTierChange`), so the hub exemption cannot be used to reach `handleMessage`, which mints a tenant client.
- `readCcMcpAllowlist` (the cc runner's env-driven MCP allowlist) throws if any resolved name is in `APPROVAL_REQUIRED_TOOLS`: the cc runner has no approval wiring, so a promoted approval tool would otherwise run
  on the legacy in-memory gate and silently skip the queue.

Pre-existing and not changed by this ADR: `pushBranch` runs `git push` inside the agent-writable workspace with the installation token in the child's environment, and whether `bwrap` makes `.git/hooks` read-only
for the agent is UNVERIFIED. A hook planted by the agent could therefore observe the token during a push the Owner approved. This is outside the approval boundary (it exists with the flag off) and is recorded here so it is not
read as covered by the commit pin.

What it does not cover: an RPC name assembled at runtime, a new importer added together with its allowlist entry, or a code path that obtains a tenant client and calls `decide_approval` through a
channel the grep does not model. A prompt-injected agent that can only emit tool calls cannot do this; arbitrary code execution in the server process can, and is outside this decision's threat model
(it already holds the founder's tenant client for the CRM and other tools). Moving the decide path out of the agent's process (a separate service principal) is the real fix and is a follow-up, not a slice-1 claim.

### Relationship to other ADRs

- **ADR-305** is the prerequisite and is unchanged: gated tools never enter `allowedTools`, and the shared `holdForUser` lifecycle fails closed. This ADR adds a second stage inside that gated branch. For the eight tools with the flag on, ADR-305's timeout wording differs by design (the wait ends with "saved for the workspace Owner; do not retry now" and the row stays pending rather than "the action was not performed"); see ADR-305's dated Addendum.
- **ADR-284** (memory-less must-ask lane for hosted Bash) is unchanged in behaviour for Bash: no acknowledgement and no cache entry are added to it. The two mechanisms are not isolated, though: they share the `holdForUser` lifecycle and the per-session `pendingGates` budget (5 pending cards, Bash and platform together), so a pending approval wait counts against the same budget as a pending Bash card. A durable single-use request extends the idea of an ask to platform tools, which that ADR's wording ("no new approval surface") did not contemplate; see its dated Addendum.
- **ADR-085**: the inbox `source` CHECK is widened to include `approval_required`, as that ADR reserved; see its dated Addendum. The per-Owner recipient-state join stays deferred. ADR-085's trigger ("when broadcast `approval_required` first needs it") was evaluated for this ADR and is **not met**: the approval is a workspace-grain decision (the first Owner's decision settles it for every Owner), the approval row carries its own state, and the decide RPC moves the linked inbox item out of the `action_required` count in the same transaction, so no independent per-Owner `acted_at` exists to reconcile. Re-evaluate if a future approval needs per-Owner acknowledgement.
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

### Flag-flip checklist (before the flag is turned on for anyone)

The same list is copied verbatim into `knowledge-base/project/specs/feat-hitl-approval-queue/flag-create-handover.md`; edit them together.

1. **Cohort rule: no workspace with more than one member gets the flag until the Owner card names the requester and `reattach` stops sending full action text to non-Owners.** Until both hold, the flag is limited to
   single-member workspaces (also: the decide path out of the agent process, or the sentinel gap re-accepted). Check the `workspace_members` count for the workspace before any per-workspace override, and **re-check it on
   every member invite**: inviting a second member to an enabled workspace takes it out of the cohort, so its override is removed first or in the same change.
2. **`SENTRY_USERID_PEPPER` is non-empty in the running container** (not only set in Doppler `prd`; invariant 1 fails closed without it, and `approval-key-unavailable` pages). Verify read-only after the deploy that
   the container has it and that the `approval-key-unavailable` alert has no events. **Never rotate the pepper while any approval is live**: a rotation invalidates every pending and approved row (and changes ADR-029 pseudonyms).
3. **Route the cron monitor** (accepted deviation, below): `scheduled_approval_expiry` is declared-unrouted under the two-PR rule and has no independent cover (the unanswered alert is emitted by the sweep itself, and no Better Stack
   missing-`SOLEUR_APPROVAL_SWEEP` monitor exists). After its first measured check-in, route it into `cron_monitor_failure` (add its id to the sorted `monitor_ids`, delete the unrouted entry) in a follow-up PR before the flip.
4. **Real-SDK probe and post-deploy verification**: re-run the probe (`dev-probe-approval-gate.ts`, ADR-305 checklist) and confirm the post-deploy verification below is green.
5. **Erasure and fingerprint conformance** (compliance-posture row, item (i)): after a real-database erasure of a personal workspace, `select count(*) from approval_request where workspace_id = :erased_user_id` is 0 and the
   fingerprint is keyed (pepper set, known-answer vector green); both recorded in `knowledge-base/legal/audits/`. The integration test `approval-request.tenant-isolation.test.ts` is the falsifier; `verify/180` deliberately has no row-level check (invariant 3).
6. **CLO attestation and sign-offs** (compliance-posture row, items (b), (h), (i)): (b) the full CLO attestation is discharged in `knowledge-base/legal/audits/` (a Jikigai-owned canary needs only its (b-canary) verification step);
   (h) the autonomous-mode card copy is non-provisional with both the CPO and CLO reviewer fields filled; (i) as item 5. Evidence gates #9776 and #10111 are closed.
7. **First-call flag-error posture**: decide whether to harden a flag read error on the first gated call of a turn to deny before enabling beyond the Jikigai canary (today it takes the flag-off path, a legacy card; see "Fail closed, sticky for the rest of the turn").

### Accepted deviation: cron monitor routing (the CTO review's cron-and-alerts ruling, second clause)

The CTO review asked that the cron monitor's cover be real: name an independent monitor, or route the Sentry monitor in this change. Neither is possible in this PR. No Better Stack missing-`SOLEUR_APPROVAL_SWEEP` monitor
exists to cite, and a `sentry_cron_monitor` cannot be routed in the PR that creates it (the two-PR rule: the monitor must exist and report a measured check-in before it joins `cron_monitor_failure`'s `monitor_ids`). The monitor is therefore declared
unrouted with its cover sentence corrected to say that no independent cover exists, and routing it is item 3 of the checklist above. Until then a dead sweep is not paged; the flag is off, so nothing depends on the sweep
yet. The approval alerts that DO exist and are routed in this PR: `approval-gate-unanswered`, `approval-key-unavailable` and `art17-approval-anonymise-failed`.

## Rollback and post-deploy verification

**Rollback is: flag off, keep the schema.** `180_approval_request.down.sql` is NOT a hot rollback. Run by hand against production it (1) leaves the `_schema_migrations` row, so the runner never re-applies 180 while
the schema is gone; (2) strands `verify/068` (which expects the extra `_jti_not_denied` policy) and `verify/180`, which stay in `main` and fail every following release's `verify-migrations`, blocking `deploy`; (3) breaks
account deletion for every user if the new app is live, because saga step 5.16 calls `anonymise_approval_request`; and (4) deletes the `approval_required` inbox rows and DROPs the table including its audit rows.
Turning the flag off is also safe mid-session, with one stated effect: for the rest of any turn in which the approval flow already ran (the `ExecutionGrants` lifetime, one user message), the three grant-checked tools refuse at the handler
and the other five approval-required tools are denied by the gate with the static unavailable text (they never fall back to the legacy requester-answerable card); the next user message starts with a fresh, non-enforcing grants object. Live `pending` and `approved` rows are
not touched and expire by themselves. **Rotating `SENTRY_USERID_PEPPER` is a rollback hazard of its own**: it invalidates every live approval (pending and approved rows fail closed as `hash_mismatch`; ADR-029 pseudonyms change with it), so
do it only with the flag off and no live rows.

An app-only rollback (redeploy the previous image) is safe: old code never references the new objects, the table stays empty while the flag is off, and the Sentry monitor goes `missed` after its margin.

If a schema down is unavoidable, the order is: (a) deploy the previous image FIRST; (b) take a `pg_dump` snapshot of `public.approval_request` (and the `approval_required` rows of `inbox_item`) BEFORE the DROP, because
the down drops the audit rows; (c) apply the down; (d) `DELETE FROM public._schema_migrations WHERE filename = '180_approval_request.sql'`; (e) revert the `verify/068` and `verify/180` edits and the app code in the
same change. The preferred alternatives are a revert PR that removes migration, verify files and app code together, or a forward-fix migration. Migration 180 is edited in place before merge (DEV only); the DEV
reset is down, delete the ledger row, up, then `verify/180` and `scripts/dev-ledger-parity.sh`, never against prd.

Merge order: the release pipeline runs `migrate`, then `verify-migrations`, then `deploy`, so the schema lands before the app. The sibling branch `fix-codex-notice-rights-slice-a` holds migration 179 and is stale against
the hotfix; its merge order is recorded in the PR body.

Post-deploy verification (flag still off; read-only, counts only, within 5 minutes of the deploy):

```sql
-- 1. High-value invariants (expected: every row 0)
SELECT 'rls' AS chk, CASE WHEN relrowsecurity THEN 0 ELSE 1 END AS bad FROM pg_class WHERE oid = 'public.approval_request'::regclass
UNION ALL SELECT 'ledger', CASE WHEN count(*) = 1 THEN 0 ELSE 1 END FROM public._schema_migrations WHERE filename = '180_approval_request.sql'
UNION ALL SELECT 'no_service_role_table_priv', CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'SELECT,INSERT,UPDATE,DELETE') THEN 1 ELSE 0 END;

-- 2. No stale narrow source CHECK left beside the widened one (expected 0)
SELECT count(*) AS stale_narrow_checks FROM pg_constraint
 WHERE conrelid = 'public.inbox_item'::regclass AND contype = 'c'
   AND pg_get_constraintdef(oid) LIKE '%task_completed%' AND pg_get_constraintdef(oid) NOT LIKE '%approval_required%';

-- 3. Dormancy while the flag is off (expected 0, 0, 0)
SELECT (SELECT count(*) FROM public.approval_request) AS approval_rows,
       (SELECT count(*) FROM public.inbox_item WHERE source = 'approval_required') AS approval_inbox_rows,
       (SELECT count(*) FROM public.approval_request WHERE status = 'pending') AS pending_rows;
```

Also: the inbox per-source and per-severity counts equal the pre-deploy baseline; `SOLEUR_APPROVAL_SWEEP` reaches Better Stack at least twice in 15 minutes, each `ok=true expired=0 flagged=0 scrubbed=0
notify_failed=0`; the `scheduled-approval-expiry` Sentry monitor shows an `ok` check-in within 15 minutes; Sentry has zero `feature=account-delete op=anonymise-approval-request` events in the first 24 hours
(that step is flag-independent and fail-closed, and it now has its own routed alert); and `soleur:flag-list` shows `approval-queue` off everywhere. Pre-deploy, the baseline is the same inbox counts, the ledger
row and table absent in prd, and exactly one `inbox_item` source CHECK. Nothing in this section flips or creates the flag; an end-to-end gate smoke in prd belongs to the enabling gate.

Retention and WAL: the 30-day scrub is an `UPDATE` that nulls `canonical_action`, so the old row version remains in WAL and database backups until their own retention windows pass. "Nulled after 30 days" is the
application-visible state, not a claim of physical erasure. Metadata rows only grow (one per request, never deleted except a solo workspace on erasure), bounded by the pending caps and the 5-minute cron rather than by
retention.

## Consequences

- An Owner can answer a high-risk action after the session ended, and every decision leaves a hash-bound audit row with constrained transitions (including an Owner revoke before consume) that survives erasure of the action text. The row survives erasure of the *account* except for a solo workspace, where it is deleted with the account (invariant 3); a team workspace keeps its history with the user columns nulled.
- Slice 1 does not execute on approve: the agent must propose the identical action again, so a regenerated email body hashes differently and is not consumed. That friction is accepted and measured.
- One more table, six-plus RPCs, a 5-minute cron and a flag to maintain; every new gated tool pays the checklist above.
- Three tools keep stated residuals (file bytes, branch contents, workflow file at the ref), shown on their cards; a push is pinned to the approved commit.
- The flag is limited to single-member workspaces until the cohort rule in the flip checklist is met.
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
