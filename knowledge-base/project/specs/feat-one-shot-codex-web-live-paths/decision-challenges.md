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
