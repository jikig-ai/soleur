# Tasks: Codex Web live handler wiring

Plan: `knowledge-base/project/plans/2026-09-27-feat-codex-web-live-handler-wiring-plan.md`

## Phase 1: Map execution and evidence

- [ ] 1.1 Record current main, served build, registry/flag state and the existing mode-specific qualification/CLO status.
- [ ] 1.2 Enumerate every WebSocket create, duplicate-create, first-turn, continuation, resume and lifecycle path; name its persisted binding read.
- [x] 1.3 Inventory `runRoutine()` callers and `*.manual-trigger` Inngest consumers. No consumer reads `engine_run_id`; agent-oriented cron consumers invoke Claude directly with specialized contracts. No routine qualifies for Codex without a distinct reviewed consumer, so routine binding remains rejected and this AC is blocked.
- [ ] 1.4 Map provider target endpoint, attachment data-class derivation, credential lease, protected recovery state and erasure/DSAR consumers.

## Phase 2: Failing real-path tests

- [x] 2.1 Add failing actual WebSocket first-turn and second-turn tests asserting the persisted Codex engine/auth reaches the injected reviewed bridge and never calls Claude. These are synthetic composition tests, not live runtime qualification.
- [ ] 2.2 Add failing duplicate-create, resume/restart, cancel/approval, event/usage persistence, revoked credential, denied egress and provider-error tests.
- [ ] 2.3 For the named eligible routine, add failing producer plus actual Inngest-consumer tests for binding, idempotent delivery, enqueue failure and no legacy fallback.
- [ ] 2.4 Add failing settings persistence and resumed-WebSocket tests proving an explicit owner auth-mode change updates existing Codex conversations in that workspace, without changing routine or Claude bindings, and without calling the previous provider mode. Cover the resuming user's own key, missing/revoked keys, stored-history replay, and no secret/native handle in member-readable events.
- [ ] 2.5 Add auth-mode generation race tests: active requests already accepted may finish, but stale retries and checkpoint writes fail after a mode switch; subsequent turns use the new generation.
- [ ] 2.6 Replace the engine radio list with an accessible dropdown; keep rollout-disabled engines unselectable outside the exact synthetic qualification path. Add owner confirmation of affected conversation count and provider/billing effects, plus a member resume acknowledgment before history replay.
- [ ] 2.7 Add a failing exact-workspace qualification-path test: trusted server allowlist and expiry, server-marked synthetic conversations and fixed prompts only, no arbitrary chat body or attachment, and normal customer Codex traffic denied.
- [ ] 2.8 Add a failing resume notice test: history and provider calls are withheld until the affected member acknowledges the new provider account; missing/revoked credentials return an actionable content-free error.

## Phase 3: Durable binding and handler wiring

- [ ] 3.1 Implement ADR-233 turn attempts, durable event sequences, protected recovery checkpoints and terminal lifecycle updates; keep the member-readable event ledger content-free.
- [x] 3.2 Route real conversation handler branches by persisted binding to the existing Codex bridge. Preserve legacy Claude behavior for Claude/legacy rows only. Production dispatch still fails closed because launcher, mode credentials, and trusted egress composition are unavailable.
- [ ] 3.3 Bind actual App Server target and attachment data class to server-owned egress checks at transport/launcher request time; preserve exact auth mode and tenant-scoped credential selection.
- [ ] 3.4 Wire actionable approval responses, cumulative WebSocket text/final frames, usage, cancel/reconcile/replay and deletion acknowledgements without claiming unsupported parity.
- [ ] 3.5 Wire only the named eligible Inngest routine consumer to the existing Codex routine bridge. Re-read bound identity and current policy; reconcile failed enqueue and duplicate deliveries.
- [ ] 3.6 Extend the owner settings RPC with an explicit auth-mode-change intent. Atomically update only Codex conversation auth modes in the workspace and purge old provider checkpoints; engine changes and automatic auth-mode adjustments must not trigger rebinding.
- [ ] 3.7 Fence switched turns and all lifecycle/checkpoint writes by an auth-mode generation. Restore context from tenant-scoped stored messages under the new provider account; distinguish empty history from read failure and require member acknowledgment before replay.

## Phase 4: Security, review and QA

- [ ] 4.1 Run tenant/credential/egress security checks, independent code review, QA, preflight and complete all remaining applicable gates. The full suite, focused suite, migration probe, schema-level GDPR checks (lawful basis, retention, erasure, Art. 9, and Chapter V), and CPO/CTO conditional plan review are recorded; production security review and live qualification remain.
- [ ] 4.2 Update `workspace-default-engine.pen` for the engine dropdown, owner confirmation and member history-transfer acknowledgment; run screenshot QA for the changed settings control. Current visual review is blocked by unavailable Pencil MCP.

## Phase 5: Synthetic qualification and disposition

- [ ] 5.1 Establish an expiring, exact-workspace synthetic qualification route from trusted server configuration; ordinary Codex traffic remains blocked and only server-marked conversations/fixed prompts can reach the runtime.
- [ ] 5.2 On a served build SHA, run and record the full authenticated Web matrix separately for API-key and managed modes; retain explicit blockers for unavailable workspace credentials.
- [ ] 5.3 Update the mode-specific CLO packet; keep customer-content status blocked without an attributable disposition for that mode.
- [ ] 5.4 Consider a bounded internal cohort only after its mode's Web evidence and applicable authorization pass; record any mutation and live smoke. Keep customer cohorts off until explicit mode approval.

## Phase 6: Ship and verify

- [ ] 6.1 Merge only after review and QA; verify main CI, release, deploy, served SHA and authenticated synthetic path separately.
- [ ] 6.2 Report code, API-key Web qualification, managed Web qualification, CLO disposition, internal/customer enablement and deployment as distinct statuses.
