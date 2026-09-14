---
title: "Pluggable web agent engines work ledger"
date: 2026-09-11
branch: feat-pluggable-web-agent-engines
lane: cross-domain
status: in-progress
---

# Work ledger

Canonical scope: [implementation plan](../../plans/2026-09-11-feat-pluggable-web-agent-engines-plan.md).
Both Codex authentication modes and workspace routines are included. Each new
routine run binds the current default once; retries retain that binding.

## Preflight

- [x] Restore feature checkout after cleanup unexpectedly checked out main; confirm no authored changes lost.
- [x] Reconcile prior brief and plan with the four approved decisions.
- [x] UX specialist updates wireframe and produces implementation brief for both auth modes and routine scope.
- [x] Complete consumer/write-boundary inventory and identify extraction seams.

## Phase 0 — Neutral contract

- [x] RED-01a: registry eligibility, qualified capabilities, auth-mode binding, no alternate-engine selection, and retry binding tests for the registry surface (19 tests green).
- [x] GREEN-01a (blockedBy RED-01a): neutral engine contract and reviewed registry surface (`f5b92f5bd`/`25600a6ed`).
- [x] RED-01b: persisted conversation/routine binding, dispatch authorization, and no alternate-engine invocation at the execution boundary (4 tests green).
- [x] GREEN-01b (blockedBy RED-01b): deterministic binding store freezes conversation/routine selection and preserves it for retries (`bf930503c`).
- [x] RED-02: event sequencing, terminal-state monotonicity, uncertain cancellation, and usage provenance tests (3 tests green).
- [x] GREEN-02 (blockedBy RED-02): normalized lifecycle ledger with idempotent events and conservative cancellation (`8ff20caa8`).

## Phase 1 — Persistence and Claude extraction

- [ ] RED-03: atomic workspace-default/conversation/routine binding, owner setting writes, immutable bindings, tenant/RLS and event idempotency tests.
- [ ] GREEN-03 (blockedBy RED-03): migration, durable run/event records, scoped RPCs and repositories.
  - [x] Schema contract slice: migration 138 defines settings, live runs, immutable bindings, idempotent events, RLS, and owner RPC (5 migration tests green).
  - [x] Repository contract slice: atomic bind RPC, tenant run lookup, and idempotent event append (2 repository tests green).
  - [x] Durable event-conflict slice: event append uses a membership-scoped RPC that returns exact retries and rejects divergent sequence or payload reuse (18 persistence/migration tests green).
  - [x] Durable event-shape slice: the event table and append RPC reject empty/oversized IDs, non-positive sequences, and null payloads before persistence (140 focused regression tests green).
  - [x] Direct-write privilege slice: migration revokes mutation privileges on engine tables for anon/authenticated roles while preserving RLS-scoped member reads (140 focused regression tests green).
  - [x] Conversation binding lookup slice: the persistence repository resolves the unique immutable run by conversation ID and normalizes it into the neutral contract (11 persistence tests green).
  - [x] Routine binding lookup slice: the persistence repository resolves the unique immutable run by routine ID and application run ID, and the dispatch layer fails closed before adapter selection (30 persistence/dispatch tests green).
  - [x] Conversation composition slice: websocket conversation creation binds the trusted workspace default before first-turn dispatch; authenticated RPC execution is identity-bound (10 focused tests green).
  - [x] Binding normalization slice: persisted snake_case rows are translated to the neutral execution contract before adapter dispatch (8 focused tests green).
  - [x] Routine correlation slice: manual routine dispatch mints an application run id before Inngest send and carries it for downstream reconciliation (10 routine tests green).
  - [x] Agent routine-tool slice: tenant workspace resolution and bind-first dispatch are wired into the agent-facing routine tool (9 routine-tool tests green).
  - [x] Dashboard routine slice: the authenticated Run now route resolves workspace state and binds before dispatch (15 route/tool tests green).
  - [x] Settings persistence slice: owner-scoped default-engine writes are exposed through the persistence repository (12 persistence/migration tests green).
  - [x] Settings validation slice: registry definitions can be read as cloned metadata for future settings endpoints without granting execution (20 registry tests green).
  - [x] Settings API slice: authenticated GET/PUT reads and writes the workspace default through reviewed metadata and the owner RPC (7 persistence tests green).
  - [x] Settings UI slice: General settings renders the workspace default selector with owner-only writes and unavailable future engines (14 settings tests green).
  - [x] Settings UI coverage slice: selector loading, save, member read-only, and unavailable-engine behavior are pinned (3 focused component tests green).
  - [x] Settings API coverage slice: authentication, reads, owner writes, unknown engines, and disabled engines are pinned (5 route tests green).
  - [x] Settings failure slice: unbound workspaces and owner RPC failures remain explicit retryable errors (7 route tests green).
  - [x] Settings resolver slice: workspace lookup failures are sanitized to retryable 503 responses (8 route tests green).
  - [x] Settings observability slice: sanitized resolver/read/write failures mirror through the shared fallback reporter.
  - [x] Dispatch identity slice: persisted bindings are checked against the selected adapter before provider invocation (4 dispatch tests green).
  - [x] Persisted run identity slice: initial, continuation, replay, cancellation, and reconciliation reloads fail closed when a keyed lookup returns another run (23 dispatch tests green).
  - [x] Neutral event authenticity slice: generic dispatch rejects cross-run, malformed, and stale transport events before ledger persistence or consumer delivery across start, continuation, and cursor replay (22 dispatch tests green).
  - [x] Runtime payload validation slice: dispatch rejects unknown statuses and malformed lifecycle payload fields before persistence or consumer delivery (27 dispatch tests green).
  - [x] Event ID uniqueness slice: initial, continuation, and cursor streams reject repeated event IDs even when provider sequences advance (27 dispatch tests green).
  - [x] Event lifecycle slice: dispatch persists adapter events before exposing them to consumers and fails closed on ledger errors (6 dispatch tests green).
  - [x] Cancellation/reconciliation slice: lifecycle helpers reload persisted bindings and enforce adapter identity before cancel/reconcile calls (7 dispatch tests green).
  - [x] Continuation slice: native session continuation reloads and verifies the persisted adapter binding before streaming events (8 dispatch tests green).
  - [x] Cursor resume slice: reconnect/replay dispatch reloads and verifies the persisted binding before adapter cursor replay (9 dispatch tests green).
  - [x] Approval/erasure slice: approval responses and session erasure reload and verify persisted bindings before adapter calls (10 dispatch tests green).
  - [x] Replay durability slice: continuation and cursor replay persist emitted events before consumers receive them (10 dispatch tests green).
  - [x] New-run durability slice: bind-first composition forwards the event sink into initial adapter streaming (11 dispatch tests green).
- [ ] RED-04: current Claude behavior and denied platform tools through neutral adapter.
- [ ] GREEN-04 (blockedBy RED-04): extract Claude adapter and wire all inventoried dispatch paths.
  - [x] Dispatch boundary slice: persisted binding is required before adapter start; missing bindings fail closed (2 dispatch tests green).
  - [x] Conversation dispatch wiring slice: the neutral dispatch layer resolves a unique conversation binding before selecting an adapter and fails closed when it is absent (16 dispatch tests green).
  - [x] Claude adapter boundary slice: provider transport is wrapped behind the neutral lifecycle contract without SDK types crossing it (1 adapter test green).
  - [x] Claude adapter lifecycle coverage: start, continue, cancel, reconcile, cursor resume, approval, erasure, and disposal delegation are pinned.
  - [x] Claude neutral-boundary slice: stream identity/sequence validation and generic provider-error sanitization protect every lifecycle method (3 adapter tests green).
  - [x] Claude message translation slice: SDK assistant text, tool progress, usage, and terminal results translate into neutral payloads with stable source IDs; malformed provider shapes fail closed (6 translator tests green).
  - [x] Claude SDK transport bridge slice: an SDK-shaped lifecycle source can be wrapped behind the neutral Claude transport while preserving source-owned permissions, session, approval, and cancellation behavior (10 adapter/translator tests green).
  - [x] Claude assistant-error slice: authentication, billing, rate-limit, overload, and model failures become bounded neutral error events with explicit retryability (11 adapter/translator tests green).
  - [x] Claude source-identity hardening slice: SDK source IDs are bounded and control-character-free before becoming persisted event IDs (132 focused regression tests green).
  - [x] Claude run-identity hardening slice: stream wrappers reject malformed run IDs, including control and Unicode separator characters, before consuming provider output (133 focused regression tests green).
  - [x] Claude provider-stream integrity slice: recognized SDK messages with invalid source identities fail closed instead of disappearing silently, while unsupported SDK variants remain ignored (13 adapter/translator tests green).
  - [x] Claude identity slice: the adapter exports a single immutable engine ID for dispatch selection and registry alignment.
  - [x] Catalog identity slice: reviewed engine definitions consume the Claude adapter identity constant rather than duplicating it (21 registry/adapter tests green).
  - [x] Settings identity slice: API fallback defaults reuse the Claude adapter identity constant.
  - [x] Contract identity slice: TypeScript consumers share one neutral default-engine constant across catalog, API, and UI (31 focused tests green).
  - [x] New-run composition slice: bind-first dispatch composes persistence and adapter invocation without client engine selection (3 dispatch tests green).
  - [x] Routine chokepoint slice: `runRoutine` binds trusted workspace/routine identity before Inngest dispatch and fails closed on persistence errors (9 routine tests green).
- [ ] Write ADR and update/regenerate C4 for implemented boundaries.
  - [x] ADR-217 records persisted binding authority, adapter lifecycle, registry qualification, and the remaining service-identity consequence.
  - [x] C4 slice: canonical LikeC4 source and regenerated artifact model registry, binding/event ledger, and Claude adapter boundaries.
  - [x] C4 verification slice: freshness gate passed 3/3 and LikeC4 version-pin suite passed 2/2.
  - [x] Focused regression slice: the combined engine/settings/routine suite passes 82/82 with typecheck green after widening selectable engine state.
  - [x] Full focused evidence slice: migration-inclusive engine/settings/routine suite passes 88/88; C4 freshness passes 3/3.

## Phase 2 — Deterministic remote adapter

- [x] Test-only remote lifecycle slice: a network-free adapter models queued, running, waiting, terminal, delayed cancellation, unavailable cost, and duplicate-sequence behavior through the neutral dispatch boundary (3 adapter tests green).

## Phase 3 — Codex and settings

- [ ] RED-05: API-key and managed ChatGPT login isolation, refresh, logout, revoked credentials, approvals, recovery, usage, and cancellation.
  - [x] Auth boundary slice: API-key and managed modes have explicit, mode-stable credential leases (2 tests green).
  - [x] Transport boundary slice: Codex lifecycle calls acquire the isolated lease before provider transport invocation (3 tests green).
  - [x] Credential recovery slice: expired/empty leases fail closed and revoked-provider errors normalize without secret details (5 tests green).
  - [x] Logout isolation slice: logged-out boundaries reject future acquire/refresh calls and make logout idempotent (6 tests green).
  - [x] Settings persistence slice: workspace defaults now store an explicit auth mode and atomic run binding inherits it (15 persistence/migration tests green).
  - [x] Settings API auth-mode slice: GET exposes the persisted mode and owner PUT validates/authenticates mode selection (10 route tests green).
  - [x] Settings UI auth-mode slice: owner selector loads, displays, and persists the selected engine auth mode (4 component tests green).
  - [x] Usage provenance slice: Codex token usage normalizes to neutral events with reported or unavailable cost provenance (8 adapter tests green).
  - [x] Recovery integration slice: authorization failures trigger at most one refreshed-lease retry; other failures propagate unchanged (10 adapter tests green).
  - [x] Promise lifecycle recovery slice: Codex cancellation, reconciliation, approval, and erasure calls use the one-refresh recovery boundary before error sanitization (20 adapter tests green).
  - [x] Pre-event stream recovery slice: Codex start/continue/cursor streams retry one authorization failure before the first event and fail closed after partial delivery (21 adapter tests green).
  - [x] Raw auth-code recovery slice: transport `unauthorized`, `invalid_grant`, and `revoked` failures share the one-refresh recovery policy (22 adapter tests green).
  - [x] Error sanitization slice: Codex transport errors cross the neutral boundary with stable codes and generic messages (12 adapter tests green).
  - [x] Replay boundary slice: Codex streams reject cross-run, missing-id, and non-positive-sequence events before ledger handoff (14 adapter tests green).
  - [x] Sequence monotonicity slice: Codex streams reject stale or duplicate sequence numbers within a provider stream before ledger handoff (19 adapter tests green).
  - [x] Egress boundary slice: Codex endpoints require HTTPS and an exact configured host allowlist (16 adapter tests green).
  - [x] Binding-auth consistency slice: registry dispatch rejects egress selections whose auth mode differs from the immutable run binding before provider invocation (26 dispatch tests green).
  - [x] DSAR metadata slice: audit/export metadata contains auth mode and expiry only; credential values are excluded (17 adapter tests green).
  - [x] Adapter factory slice: reviewed registry state gates adapter creation for unknown, disabled, or unavailable engines (2 factory tests green).
  - [x] Qualification-aware factory slice: egress-selected dispatch passes the trusted selection through reviewed registry resolution; get-only registries fail closed when qualification is requested (5 factory and 28 dispatch tests green).
  - [x] Selection-operation safety slice: reviewed adapter creation rejects a `new-run` selection used for an `existing-run` dispatch (6 factory tests green).
  - [x] Registry dispatch slice: bound-run dispatch resolves the adapter from persisted engine identity through the reviewed factory (12 dispatch tests green).
  - [x] Registry injection dispatch slice: conversation, routine, and bound-run dispatch accept an explicit reviewed registry so future engines can cross the same binding boundary (24 dispatch tests green).
  - [x] Adapter composition slice: injected Claude/Codex transports compose into reviewed factories, with Codex omitted until auth dependencies exist (2 composition tests green).
  - [x] Cancellation slice: Codex cancellation normalization confirms only explicit terminal acknowledgement (18 adapter tests green).
  - [x] Egress policy slice: server-side endpoint, data-class, DPA, transfer-geography, deletion-support, and approval evidence fail closed before registry dispatch; synthetic qualification may proceed without erasure evidence, while customer data requires verified deletion support (9 policy tests and 1 dispatch integration test green).
  - [x] Observability slice: dispatch start/progress/completion/failure and reconciliation events emit safe binding metadata through a non-throwing structured sink (3 observability tests and dispatch coverage green).
  - [x] Expanded evidence slice: migration-inclusive engine/settings/routine suite passes 116/116; C4 freshness passes 3/3.
  - [x] Consolidated engine regression slice: 15 files and 122 tests pass after egress-policy integration; TypeScript typecheck passes.
  - [x] Catalog identity slice: reviewed Codex metadata reuses the adapter’s immutable engine ID (22 registry/factory tests green).
  - [x] C4 composition slice: adapter factory and provider composition boundaries are modeled and regenerated; freshness 3/3 and version pin 2/2 pass.
  - [x] Full-gate failure slice: migration tables were added to the DSAR allowlist and explicit anon/authenticated RPC revokes; focused guards now pass 17/17.
  - [x] DSAR worker slice: engine settings, runs, and events are exported with owner or parent-run scoping; DSAR worker and grant guards pass 15/15.
  - [x] Full web-platform gate: 1,085 files and 13,556 tests pass (54 skipped, 1 existing todo) after DSAR integration fixes.
  - [x] Full web-platform gate after egress/observability slices: app-local Vitest passes 1,087 files and 13,569 tests (54 skipped, 1 existing todo).
  - [x] Review fix slice: service-role binding now verifies `p_created_by` membership when `auth.uid()` is unavailable (migration/grant tests pass 12/12).
  - [x] QA checkpoint: plan has no executable `## Test Scenarios` section, so browser/API scenarios were skipped per QA workflow; diff does not touch structural nav-state paths. Full web-platform and focused migration/settings/routine suites remain green.
  - [x] GDPR evidence checkpoint: regulated-path scan examined 53 changed files and matched 4; no new Art. 9 finding. The pre-existing >90-day corpus posture signal remains tracked by #7710, with the inert cron binding tracked by #7255.
  - [x] Synthetic qualification record: Codex API-key and managed ChatGPT modes have deterministic evidence recorded separately from pending customer-content vendor/CLO approval (`codex-qualification-record.md`).
  - [x] Account-erasure slice: migration 138 anonymizes engine setting/run identity through a service-role-only RPC before auth deletion; lineage/events remain, tenant-isolation teardown parity is updated, and cascade coverage passes 35/35.
  - [x] Codex rollout flag slice: identity-aware `codex-engine` runtime flag is default-off, requires a matching workspace identity, and remains independent from registry capability, authorization, and qualification checks (34 feature-flag tests green).
  - [x] Settings rollout slice: the workspace selector and auth control keep Codex disabled when the identity-aware rollout flag is off, even if the API advertises the engine as available (6 settings component tests green).
  - [x] Regression correction: tenant-isolation teardown expectation now covers all 22 anonymization RPCs before auth deletion.
  - [x] Full app-local gate after rollout flag and teardown updates: 1,088 files and 13,575 tests pass (54 skipped, 1 existing todo).
  - [x] Repository lint gate after settings rollout: ESLint exits cleanly with 0 errors; the 191 warnings are pre-existing and none originate in the changed rollout files.
  - [x] Server settings rollout guard slice: PUT re-resolves the workspace identity and rejects Codex when a reviewed definition is enabled but the identity-aware rollout flag is off (11 route tests and 6 settings tests green).
  - [x] Generic rollout metadata slice: reviewed engines expose identity-aware `rolloutEnabled` metadata, settings UI consumes the server decision, and unmapped engines fail closed until explicitly registered (11 route, 6 settings, and 3 feature-flag tests green).
  - [x] Settings contract slice: API and UI share the neutral `EngineSettingsMetadata` projection instead of duplicating engine fields (11 route and 6 settings tests green).
  - [x] Adapter composition extensibility slice: additional reviewed-engine factories register through an additive map without changing Claude/Codex composition control flow (3 composition tests green).
  - [x] Injected reviewed registry slice: adapter creation accepts an explicit reviewed registry for future engines while preserving the built-in catalog default (3 factory tests green).
  - [x] Rollout metadata compatibility slice: missing metadata preserves the always-on Claude option while future-engine options remain disabled until explicitly enabled (7 settings tests green).
  - [x] Owner authorization slice: settings RPC error code `42501` is preserved and returned as an explicit 403 owner-required response (22 persistence/route tests green).
  - [x] Full app-local gate after settings authorization: 1,088 files and 13,585 tests pass (54 skipped, 358 expected skipped cases, 1 existing todo).
  - [x] Production build gate after settings authorization: `npm run build` passes with Next.js 16.3.1/Turbopack; generated `tsconfig.json` include changes were reverted, and existing Sentry/Next tracing warnings are summarized in the verification evidence below.
- [ ] GREEN-05 (blockedBy RED-05): Codex transport, auth lifecycle, credential isolation, shared policy and normalized events.
- [ ] RED-06: settings default, both auth modes, routines, missing credentials, availability, and owner authorization.
- [ ] GREEN-06 (blockedBy RED-06): settings UI and server endpoints following the updated wireframe.

## Qualification and delivery

- [ ] RED-07: DSAR/export/delete, provider error sanitization, egress, replay/stale-event protection, and observability.
- [ ] GREEN-07 (blockedBy RED-07): implement protections and wire production paths.
- [ ] Refresh GDPR evidence, run prescribed GDPR gate, and obtain vendor/CLO disposition for both auth modes.
- [ ] Synthetic-only qualification, feature flag, bounded live probes, QA and screenshots; customer content remains disabled without evidence.
- [ ] Run appropriate suites/lint/typecheck/build after all GREEN tasks.
- [ ] Review, QA, compound, ship and required postmerge checks.

## Verification evidence

Evidence so far: the RED-01a import failure was observed before implementation;
the registry suite now passes 19/19. The current app-local full gate passes 1,088
files and 13,585 tests (54 skipped, 358 expected skipped cases, 1 existing todo),
and the production Next.js build passes. The build still reports existing Sentry
deprecation, multi-lockfile workspace-root, middleware-convention, dynamic-module,
and dynamic-filesystem tracing warnings; these do not appear in the feature diff or
change the successful exit status. Do not mark an entire phase complete from an
isolated helper suite.

The latest full-gate rerun (2026-09-14) reached 1,081 passing suites and 54
skipped, but ended with 10 failures outside this diff: import-hook, Bun, PDF,
and email timer timeouts; an untracked `probe-octokit.ts` lint-baseline increase;
and a cron fixture expectation mismatch. The changed engine/settings/routine
focused gate remains green at 13 files and 117 tests.
