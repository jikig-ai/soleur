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
- [ ] 2.4 Add failing settings persistence and resumed-WebSocket tests proving an explicit owner auth-mode change updates existing Codex conversations in that workspace, without changing routine or Claude bindings, and without calling the previous provider mode. Cover the resuming user's own key, missing/revoked keys, explicit resend-only behavior (no saved-history transfer), and no secret/native handle in member-readable events.
- [ ] 2.5 Add auth-mode generation race tests: active requests already accepted may finish, but stale retries and checkpoint writes fail after a mode switch; subsequent turns use the new generation.
- [ ] 2.6 Replace the engine radio list with an accessible dropdown; keep rollout-disabled engines unselectable outside the exact synthetic qualification path. Add owner confirmation of affected conversation count and provider/billing effects, plus a member resume acknowledgment before explicit resend; acknowledgment does not replay or send saved history.
- [ ] 2.7 Add a failing exact-workspace qualification-path test: trusted server allowlist and expiry, server-marked synthetic conversations and fixed prompts only, no arbitrary chat body or attachment, and normal customer Codex traffic denied.
- [ ] 2.8 Add a failing resume notice test: the pending message and provider calls are withheld until the affected member acknowledges the new provider account, then only the explicitly resent message is sent; missing/revoked credentials return an actionable content-free error.

## Phase 3: Durable binding and handler wiring

- [ ] 3.1 Implement ADR-233 turn attempts, durable event sequences, protected recovery checkpoints and terminal lifecycle updates; keep the member-readable event ledger content-free.
- [x] 3.2 Route real conversation handler branches by persisted binding to the existing Codex bridge. Preserve legacy Claude behavior for Claude/legacy rows only. Production dispatch still fails closed because launcher, mode credentials, and trusted egress composition are unavailable.
- [ ] 3.3 Bind actual App Server target and attachment data class to server-owned egress checks at transport/launcher request time; preserve exact auth mode and tenant-scoped credential selection.
- [ ] 3.4 Wire actionable approval responses, cumulative WebSocket text/final frames, usage, cancel/reconcile/replay and deletion acknowledgements without claiming unsupported parity.
- [ ] 3.5 Wire only the named eligible Inngest routine consumer to the existing Codex routine bridge. Re-read bound identity and current policy; reconcile failed enqueue and duplicate deliveries.
- [ ] 3.6 Extend the owner settings RPC with an explicit auth-mode-change intent. Atomically update only Codex conversation auth modes in the workspace and purge old provider checkpoints; engine changes and automatic auth-mode adjustments must not trigger rebinding.
- [ ] 3.7 Fence switched turns and all lifecycle/checkpoint writes by an auth-mode generation. Keep tenant-scoped stored messages visible in Soleur, but send only the member's explicitly resent message and future messages to the new provider; distinguish empty history from read failure and require member acknowledgment before resend.
- [x] 3.8 Preserve the migration 169/170 acknowledgment RPC barrier without editing applied migration files: revoke within 169's transaction, commit a separate revoke before pending 170, and restore authenticated grants only after both owner-scoped definitions. Runner tests cover successful ordering and refusal when the revoke or owner-scope apply fails; shared database verification remains blocked by the ledger gate and CTO ruling.

## Phase 4: Security, review and QA

- [ ] 4.1 Run tenant/credential/egress security checks, independent code review, QA, preflight and complete all remaining applicable gates. The full suite, focused suite, migration probe, schema-level GDPR checks (lawful basis, retention, erasure, Art. 9, and Chapter V), and CPO/CTO conditional plan review are recorded; production security review and live qualification remain.
- [ ] 4.1a Finish current-source auth-capable production candidate and independent full-schema rehearsal review. October 12 committed offline preparation binds the complete source/schema/browser contract and passes ownership/cleanup/validator fixtures; no image, TLS orchestration, recovery execution or independent-review completion is established. See `safe-qualification-preparation-2026-10-12.md`.
  - [x] Prepare exact-role policy and callable TLS/DNS components with synthetic adversarial tests.
  - [x] Prepare all-source scenario SQL and fix canonical fresh-ledger insertion without changing migration bodies/guards.
  - [ ] Finish actual operational role profiles, namespace/session orchestration and retained file-byte manifests; obtain independent source review and immutable image/auth observations before requesting fresh exact execution approval.
    - [x] Prepare descriptor-relative retained-file collection and comparison, including exact scoped erasure and synthetic refusal fixtures. Root ownership and quiescence observations remain pending.
    - [x] Prepare source-bound builder/role/namespace and evidence contracts without an execution adapter or invented image observations.
    - [x] Prepare bounded session/race sequencing with exact backend identity and failure cleanup; verify only injected synthetic observations.
    - [x] Independently verify the preparation delta; retain all runtime observation and fresh approval blockers.
    - [x] Prepare source-bound profile/builder specifications, nonexecutable adapter requirements and retained ownership/quiescence consistency checks; actual Configs, adapters and observations remain pending.
    - [x] Implement callable builder/namespace/session/retained adapters over injected transports after the October 13 scope expansion; synthetic verification passes. Concrete production wiring, independently reviewed transports/profiles and authenticated runtime evidence remain pending; see `controller-adapter-implementation-2026-10-13.md`.
    - [x] RED(unit/integration): write synthetic namespace HTTP transport cases before implementation; initial run refuses the absent source module. See `transport-interface.md` for the October 14 source-only authorization.
    - [x] GREEN: implement the explicit Unix JSON transport with bounded framing and one socket deadline; depends on the preceding RED task. All 17 contract tests and the complete offline wrapper pass; focused review is separately pending.
    - [x] Verify focused namespace transport source independently; all four test-design findings close at pushed `8db5c652a7` with 23 tests and 8.9/10 Grade B. Refresh source pairing/file-only export while retaining pending builder/session/retained wiring, actual profiles/observations and exact-action approval.
    - [x] Prepare the finite GET-only image Config collector and exclusive file-only action manifest; it binds explicit immutable image IDs, deduplicates bounded GETs and preserves pending authority. Synthetic tests only; actual observations, profiles, independent review and fresh exact-action approval remain pending.
    - [x] Implement and independently review separate prebuild acquisition per the October 16 CTO ruling: private source-bound preparation and one-use exact metadata/image GET execution behind fresh harness approval. Focused CTO/security findings close at `663256a894`. One reviewed action at `177b981cb6` was freshly approved and consumed incomplete, retaining daemon projections and no image Configs; no retry is authorized. See `prebuild-acquisition-2026-10-16.md`. Preserve the complete eleven-role gate and all build/recovery holds.
    - [x] Repair the acquisition failure diagnostic gap with fixed phase/reason enums, approved action/reference hashes and strict returned HTTP status; 28 synthetic cases pass. Focused CTO/security review at `6c9489d37e` identifies no code blocker; its selected-versus-sent documentation correction is applied. A new manifest, binding review and fresh exact-action approval remain required. Preserve the consumed receipt without inferring its cause.
    - [x] Refresh source after canonical main sync, independently review v4 bindings and execute one freshly approved metadata action at `ff1e7aa9ee`. It stopped after three requests with HTTP 404 for the pinned Mailpit request; two daemon projections and zero image Configs retained. Both attempts are spent. Diagnose reference resolution versus absence before proposing a separate exact action; no retry or pull is authorized.
    - [x] Prepare and independently review the separate Mailpit-only five-GET resolution diagnostic, then obtain fresh exact-action approval. The approved action at `3f2b5979eb` completed statuses 200/200/404/404/404 with zero Configs; its marker is spent and all prior receipts unchanged. None of the approved lookup forms resolved; image/layer absence is not established. No follow-on operation is authorized.
    - [ ] Complete Mailpit-only registry Config acquisition and independent review. CTO/security cleared the framing correction at `74da79933c`; fresh actual bindings at synced `960d04e249` were reviewed and separately approved once. The attempt observed 200/200/307 and retained the pinned 864-byte platform manifest; no Config or layer was downloaded and no redirect followed. Marker spent, all admission pending. See `prebuild-acquisition-2026-10-16.md` for verified receipt and next CTO ruling.
    - [x] Implement and synthetically test the dormant two-GET redirect-header diagnostic: unchanged anonymous token scope, exact pinned Config endpoint, 307 plus one bounded Location, spec-limited routing/hash projection, no Config body or destination request. Source head `c16cc9dea7` passed 10 focused and 318 offline qualification tests; Ruff passed. Independent security and quality reviews concurred with removal of the out-of-spec `route_class` field.
    - [ ] Finish the test-design follow-up on explicit false projection flags, then bind and independently review a fresh actual manifest to the final source, helpers, verified 864-byte platform bytes/descriptor, CA, new attempt and private output. All prior actual manifests are superseded and must not be approved.
    - [ ] After corrected actual-manifest review, obtain fresh exact-action approval for the exact 90-second outer-timeout/5-second kill-grace command before any diagnostic request. No Location destination request or layer fetch is authorized by this action; any follow-on requires its own ruling and approval.
- [x] 4.2 Update `workspace-default-engine.pen` for the engine dropdown, owner confirmation and member history-transfer acknowledgment; native Pencil screenshot QA is complete for all four settings/confirmation frames. These are design captures, not rendered implementation screenshots.

## Phase 5: Synthetic qualification and disposition

- [ ] 5.1 Establish an expiring, exact-workspace synthetic qualification route from trusted server configuration; ordinary Codex traffic remains blocked and only server-marked conversations/fixed prompts can reach the runtime.
- [ ] 5.2 On a served build SHA, run and record the full authenticated Web matrix separately for API-key and managed modes; retain explicit blockers for unavailable workspace credentials.
- [ ] 5.3 Update the mode-specific CLO packet; keep customer-content status blocked without an attributable disposition for that mode.
- [ ] 5.4 Consider a bounded internal cohort only after its mode's Web evidence and applicable authorization pass; record any mutation and live smoke. Keep customer cohorts off until explicit mode approval.

## Phase 6: Ship and verify

- [ ] 6.1 Merge only after review and QA; verify main CI, release, deploy, served SHA and authenticated synthetic path separately.
- [ ] 6.2 Report code, API-key Web qualification, managed Web qualification, CLO disposition, internal/customer enablement and deployment as distinct statuses.
