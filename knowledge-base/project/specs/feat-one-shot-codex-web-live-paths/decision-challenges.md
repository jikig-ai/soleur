# Decision Challenges — feat-one-shot-codex-web-live-paths

Persisted from the 2026-09-28 plan-review panel. User-challenge items are surfaced
before the implementation that depends on them; named-panel product recommendations
are advisory and do not change the operator's requested scope.

## Taste findings applied

### Workspace-wide auth switch disclosures

**CPO finding:** Conditional acceptance of the owner changing existing Codex conversations,
provided the workspace-wide impact and history transfer are clear before applying. The
workspace includes conversations created by other members, and changing provider mode can
change transfer and billing behavior.

**Applied:** The owner confirms the affected-conversation count and provider/billing effect
before saving. A member separately acknowledges the history transfer before their stored
messages are replayed under the newly selected provider account. Missing credentials still
fail closed; each member's own credential is used.

### Engine and auth-mode controls

**UX / code-simplicity finding:** The engine selector should be a native dropdown, while the
auth-mode control remains distinct. Selecting a different engine or an automatically
adjusted supported mode must not rewrite existing Codex conversation bindings.

**Applied:** Only an explicit auth-mode change carries rebind intent into the owner RPC.
Unavailable engines remain unavailable outside the exact synthetic qualification path.

## UC-1 — Result from an in-flight turn after the switch (Resolved)

**Operator's stated direction:** Changing the Codex auth mode must affect existing
conversations.

**Panel finding:** A provider request accepted before the settings transaction cannot be
unsent. The plan currently allows it to finish under its original mode, while fencing stale
retries and checkpoint writes. The remaining product choice is whether its already accepted
result should still be stored and shown after the setting changes.

**Recommendation:** Let the accepted request finish and show its result as that turn's
result. Do not retry under the old mode or write its checkpoint after the generation changes;
the next turn uses the new mode. This preserves the response to work the user already sent
while ensuring the new setting governs every newly accepted request.

**Operator decision (2026-09-28):** Follow the recommendation. A Codex request already accepted
before the mode switch may finish and its result may be stored and shown as that attempt's
result. The next turn uses the new mode. Stale retries and recovery-checkpoint writes remain
fenced; accepted lifecycle events stay attached to the immutable attempt and cannot change the
new binding.

## Mechanical findings applied

- Store and increment an auth-mode generation in the owner RPC transaction; compare it at
  the provider request boundary and on event, terminal-state and checkpoint writes.
- Keep the workspace default update, Codex conversation rebinding and protected-checkpoint
  deletion atomic and idempotent. Return the affected count and leave all values unchanged if
  any part fails.
- Distinguish an empty stored transcript from read or authorization errors; errors fail
  closed. Restore only tenant-scoped messages and never reuse old-account provider handles.
- Keep Codex disabled for normal customer traffic. Any synthetic qualification selector is
  exact-workspace, expiring, server-authorized and limited to server-marked synthetic
  conversations and fixed synthetic prompts.
- Measure affected conversation/checkpoint rows and lifecycle/checkpoint write counts and
  WAL during synthetic qualification before any cohort review.
- Surface missing/revoked member credentials as actionable, content-free resume errors.

## Review dispositions

- **CPO:** Conditional acceptance of the new scope, subject to workspace-wide disclosure and
  mode-specific Web/CLO gates.
- **CTO:** Conditional technical approval; implementation evidence must prove transactional
  rebinding, generation fencing, per-user credentials, transcript isolation and egress checks.
- **UX:** Dropdown and flow advice concurred; visual review and screenshot QA remain blocked
  because Pencil MCP is unavailable in this session.
- **User impact:** One uncovered member-history transfer vector was found; the member-level
  acknowledgment above is the planned mitigation.

### Agent-native surface — workspace auth-mode mutation (UI/API only)

**Finding:** The owner auth-mode and rebind controls have no matching agent tool. This action
changes credential routing and history-transfer behavior for every affected Codex conversation
in the workspace.

**Disposition:** Keep this mutation on the authenticated owner settings route, with its explicit
affected-count and provider/billing confirmation. An agent tool would add a second path for a
workspace-wide credential-routing change without improving the member's required acknowledgment
or qualification gates. Agent-native parity is therefore intentionally deferred until a scoped,
owner-authorized confirmation contract exists; Codex execution remains disabled for ordinary
traffic.

## Decision Classes

| Item | Class | Ruling |
| Provider-mode acknowledgment disclosure | technical | Ruled by CTO agent, 2026-10-23: the current conversation-dispatch path starts a new provider thread with only the explicitly resent message; saved conversation history is not transferred. Keep the acknowledgment gate, state that the resent and future messages go to the selected account, and explicitly disclose that saved history is not transferred. Transcript transfer is separate implementation work requiring source selection, limits, filtering, attachment coverage, and legal review. |
| Legacy migration ledger compatibility | technical | Ruled by CTO agent, 2026-10-23: protect both legacy migration 145 and renamed migration 165 as forward-only, including in the runner pre-migration guard. Before applying any renamed migration 163–165, fail closed when a corresponding legacy ledger row 143–145 exists and its renamed row is absent; report each mapping and require explicit ledger reconciliation. Never silently skip the renamed file as applied. Keep tenant integration blocked until a dry run demonstrates the mapping and a separately authorized reconciliation is available. No database writes are authorized by this ruling. |
|---|---|---|
| CodeQL alerts 288–292 in qualification boundaries | technical | Ruled by CTO agent, 2026-10-22: canonicalize controller-profile bind sources before Docker use, preserve the fixed private TLS destination and origin-form request guard, and preserve rejection of unsafe upstream header bytes - the path check must bind the bytes Docker later receives; fixed-destination and pre-forwarding header controls address the remaining reported flows. Dissent: ownership of the private upstream address was not independently verified by the ruling agent. |
| CodeQL alerts 288–292 in qualification boundaries-r | technical | Ruled by CTO agent, 2026-10-23: amended - the prior upstream-ownership claim required a regression binding `namespace_recipe()` output to `TLSProxy`; `tls_proxy_from_receipts()` now constructs the proxy from the validated Kong IP/port, and `test_tls_proxy_uses_only_the_registered_kong_receipt_endpoint()` covers changed and refused receipts. Keep alerts open until exact-head CodeQL reanalysis; `TLSProxy.make_server()` still uses the fixed endpoint and rejects unsafe response headers before forwarding. |
| Migration 169/170 acknowledgment RPC exposure | technical | Ruled by CTO agent, 2026-10-23: keep 169 and 170 migration files immutable; revoke both RPCs in 169's transaction before its ledger commit, then issue a separate committed revoke before applying pending migration 170, retain the in-transaction revoke, and restore authenticated grants only after both owner-scoped definitions are installed. If 170 fails, keep grants revoked until a successful retry. Do not apply or qualify against shared dev in this session; tenant-ledger parity refuses before apply and no shared database writes are authorized. Dissent: verify runner branch conditions, transaction boundaries, retry and failure recovery with isolated tests. |
| Migration 165 concurrent run admission | technical | Ruled by CTO agent, 2026-10-23: after the settings lock, acquire `LOCK TABLE public.agent_engine_runs IN SHARE MODE` and check for conflicting auth modes at the latest run timestamp inside the injected transaction. Keep the shell preflight as an early diagnostic and migration 165 bytes immutable. Dissent: none; a complete writer-path audit plus verified database grants proving every writer holds a conflicting lock could change this ruling. |
| Notice-bound acknowledgment proof and scope | technical | Ruled by CTO agent, 2026-10-23: add server-authoritative, one-use notice-issuance state keyed by member, conversation, and auth-mode generation; create it only when the server sends the matching notice and require/consume it when recording acknowledgment. Keep record/read scope owner-only while dispatch remains owner-only; widen if non-owners become eligible. Dissent: issuance proves server delivery, not visible reading; if the contract requires proof of rendering, add a client presentation receipt tied to issuance. CLO disposition separately keeps release blocked until this presentation-bound control or an explicitly reviewed contract change. |
| Notice delivery race and stale issuance retention | technical | Ruled by CTO agent, 2026-10-23: bind acknowledgment to a server-generated one-use nonce; persist only its hash in pending state, send the nonce only in the notice, mark the issuance delivered only after WebSocket send acceptance, and consume only a delivered issuance with a matching hash. Delete pending state on failed/superseded sends and purge issuance rows when auth-mode generation or membership epoch changes. The nonce proves possession of the notice payload, not visual reading or understanding; the CLO hold remains. |

### Current acknowledgment and transcript disposition — 2026-10-23

The earlier “Applied” history-transfer prose and the mechanical note about restoring stored messages describe a superseded design. Current behavior keeps messages visible in Soleur and starts a new provider thread with only the member's explicitly resent message and future messages. Acknowledgment gates resend; it does not transfer or replay stored history.

The user-impact review also identified direct RPC invocation as a bypass vector: a member could try to acknowledge without seeing the notice or acknowledge a conversation they do not own. The settled mitigation is the owner-scoped record/read RPC pair in migrations 169/170, with authenticated grants restored only after both definitions are installed. Static migration and runner tests cover grant ordering and owner predicates; isolated unauthorized and cross-tenant database tests remain required before qualification.

### CLO disposition — acknowledgment must follow notice — 2026-10-23

CLO review confirms that owner identity and membership do not establish that the
notice was presented. The plan requires each affected member to acknowledge after
seeing the notice and prohibits direct RPC bypass; migration 170 currently permits
an owner RPC call without proof of notice issuance, and its owner-only scope differs
from the plan's affected-member scope. Keep this release blocked until a
presentation-bound server control is implemented or the internal contract is
explicitly and independently reviewed. This is an internal posture assessment, not
external-counsel advice. Legal posture does not treat the acknowledgment as GDPR
consent or independent provider-transfer authorization.

### Addendum — notice recovery after reconnect — 2026-10-23

Ruled by CTO agent, 2026-10-23: explicitly amend the earlier engineering
condition that delivery marking follows only WebSocket send acceptance. After
reconnect, the authenticated conversation owner may repair a pending marker by
presenting the original unpredictable nonce, disclosed exclusively in that
notice. This proves payload possession, not rendering or understanding; the CLO
presentation-proof hold remains unchanged.

Recovery must preserve the existing matching-session wait and shared retry,
reject a different nonce when current local state identifies the same notice,
and use the existing bounded abortable attempts without issuing a new notice or
dispatching a provider turn. The service-only marker must independently lock the
run then membership, check current owner/Codex generation/membership epoch and
issuance hash, and leave invalid or consumed issuance untouched. The tenant RPC
alone consumes the delivered issuance and records acknowledgment. Recheck socket
session and conversation after asynchronous boundaries. Synthetic outage,
reconnect, concurrent recovery, wrong scope, membership replacement, consumed
nonce, and timeout tests are required before accepting the fix.

Dissent: this technical amendment does not resolve legal presentation proof or
authorize shared database access, migration application, provider requests,
qualification, readiness or merge.
