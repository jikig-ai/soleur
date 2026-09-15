---
title: "feat: add pluggable web agent engines"
date: 2026-09-11
slug: feat-pluggable-web-agent-engines
branch: feat-pluggable-web-agent-engines
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Define and implement the first extensible Soleur Web agent runtime: Claude Code
and Codex adapters behind a common engine contract, a workspace default for new
conversations, and explicit capability and authorization checks that can support
future local or remote engines such as Grok Build and Devin.

## Enhancement Summary

**Deepened on:** 2026-09-11
**Sections enhanced:** architecture, persistence, authorization, remote execution,
observability, GDPR, UI, rollout, and acceptance criteria.
**Research used:** architecture-strategist, security-sentinel,
data-integrity-guardian, CPO, CMO, repository learnings, Supabase Context7 docs,
official Codex App Server/auth docs, and Pencil MCP.

### Key improvements

1. Durable run/event records and atomic workspace-default binding now carry the
   remote lifecycle and concurrency invariants.
2. Credential ownership, vendor data-egress qualification, remote event
   authenticity, DSAR erasure/export, and provider-error sanitization are explicit.
3. The workspace settings wireframe is committed at
   `knowledge-base/product/design/agent-engine-selection/workspace-default-engine.pen`
   with the rendered review image at
   `knowledge-base/product/design/agent-engine-selection/screenshots/01-workspace-default-agent-engine.png`.

### New considerations

- Codex `thread.sessionId` is distinct from `thread.id`; the adapter must persist
  the documented session identity and resume by thread ID rather than deriving one.
- Codex API-key authentication and ChatGPT subscription sign-in have different
  billing, access, retention, and data-control behavior; v1 supports both and
  keeps the authentication mode visible in workspace settings and policy checks.
- The deepening fan-out was partial because two earlier research agents hit the
  session usage limit; local evidence and the three successful review agents are
  recorded below.

## User-Brand Impact

**Artifact:** Soleur Web agent-engine selection and execution.
**Vector:** An incorrectly adapted engine could expose a user's repository or
credentials, perform an unauthorized action, lose conversation continuity, or
incur unreported cost.
**Threshold:** single-user incident.
**Required signoff:** CPO, CTO, CLO, and CMO before public rollout. CPO and CMO
reviews completed for this plan; CTO's bounded review completed during the brief;
CLO review remains a work-phase gate.

## Worst-Case User Outcome

If the change fails silently, one user could have conversation context or scoped
credentials sent to the wrong engine, or could be charged for work whose status
and usage were not recorded. The design therefore pins every conversation to an
engine, resolves authorization and credentials at execution time, fails closed on
missing capability or qualification, and makes uncertain remote cancellation and
cost visible.

## Research Insights

### Repository evidence

- `apps/web-platform/server/soleur-go-runner.ts` exposes `QueryFactory`, but its
  `QueryFactoryArgs` and async iterator are Claude SDK-shaped (`SDKUserMessage`,
  `SDKMessage`, and `Query`). The first implementation must extract a neutral
  contract while retaining a Claude adapter behind it.
- `apps/web-platform/server/cc-dispatcher.ts` creates the platform MCP server with
  `createSdkMcpServer` and imports Anthropic's `sdkQuery`; platform tools and
  approvals therefore need an adapter translation boundary rather than a second
  UI-specific path.
- `apps/web-platform/server/agent-runner-query-options.ts` and
  `apps/web-platform/server/permission-callback.ts` are the current policy seams.
  The shared policy decision must stay outside any vendor protocol.
- `apps/web-platform/server/byok-lease.ts`, `byok-resolver.ts`, and
  `agent-env.ts` currently resolve Anthropic credentials. `apps/web-platform/lib/types.ts`
  has no OpenAI/Codex provider and `Conversation` has `session_id` but no engine
  binding, so both the provider union and persistence model need deliberate
  widening with a consumer grep.
- Workspace settings are rendered by
  `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` and
  `apps/web-platform/components/settings/settings-content.tsx`; this is the
  existing surface for the workspace default selector and credential status.
- Conversation creation and routing are spread across `ws-handler.ts`,
  `conversation-writer.ts`, `agent-runner.ts`, and `cc-dispatcher.ts`. The plan
  must cover all creation paths, including support and workspace-owned routines,
  before making the engine column required for new rows.
- Existing learnings require abort-before-replace for session races, rethrowing
  resume failures so fallback can be explicit, and capability declarations in
  the baseline prompt. They also distinguish a plugin `Harness` (invocation
  surface) from an execution engine; the new registry must not widen that union.

### External qualification evidence

- [Codex App Server](https://learn.chatgpt.com/docs/app-server) documents threads,
  resumptions, streamed events, approval requests, permissions, and token usage.
  [Codex authentication](https://learn.chatgpt.com/docs/auth) supports API-key and
  ChatGPT subscription sign-in with different billing and data controls. Both
  modes are in the first-release scope; the adapter must preserve the mode in
  credential metadata and apply the corresponding policy.
- The App Server requires an initialize/initialized handshake, uses
  `thread/start` and `thread/resume`, and documents `thread.sessionId` as the live
  session-tree root while `thread.id` is the resume handle. Required MCP-server
  initialization can fail a start/resume rather than degrading silently. Approval
  requests include command/file/permission scopes; dynamic tools are experimental
  and stay out of the first adapter until separately qualified.
- Runtime claims were verified against the live docs on 2026-09-11. The App
  Server states that “`thread.sessionId` identifies the current live session
  tree root” and the auth guide states “Codex supports two ways for a person to
  sign in”: ChatGPT subscription or API key. These short excerpts anchor the
  adapter's session mapping and first-release auth decision; all other parity
  claims remain qualification hypotheses.
- OpenAI documents that API-key auth follows API-organization retention and
  data-sharing settings, may lack ChatGPT-workspace/cloud features, and must not
  expose Codex execution in untrusted or public environments. The adapter must
  therefore enforce Soleur's trusted server boundary and capability checks.
- The installed `grok 1.0.29` CLI exposes stdio, headless, WebSocket, resume,
  sandbox, and permission modes. CLI help proves an integration surface only;
  protocol and enforcement remain unqualified.
- [Devin's v3 session API](https://docs.devin.ai/api-reference/v3/sessions/post-organizations-sessions)
  exposes remote session creation, repository and secret selection, resumability,
  messages, status, and ACU limits. It does not yet prove artifact provenance,
  approval parity, event delivery, or cancellation semantics for Soleur.
- Existing [Grok epic #6547](https://github.com/jikig-ai/soleur/issues/6547)
  remains OPEN and retains its dogfood measurements and CPO/CLO prerequisites.
  This plan does not change that epic or promise Grok production support.

### Domain review

- **CPO:** Building/early-beta maturity; large (week+). Signoff requires clear
  default and conversation-binding UX, explicit Codex auth scope, qualification
  metrics, and no automatic transfer on failure.
- **CMO:** Direction fits Soleur's device-agnostic “Company-as-a-Service” frame.
  Public copy must lead with shared organization and approvals, use a capability
  matrix, qualify Claude Code-only claims, and avoid parity claims for Grok/Devin.
- **CTO:** The brief's engine-dispatch fallback invariant is binding: preserve
  the selected conversation, surface failure, and require an authorized
  explicit new engine-bound conversation before context transfer.
- **CLO:** Required before rollout because credentials, repository content, and
  possible cross-border remote processing are in scope.

### Research limitations and recovery

The planned repository and learning fan-out agents both hit the current agent
usage limit before returning results. Functional-discovery fan-out was therefore
not independently available; local `rg`/`cat` inspection covered runtime,
settings, schema, tests, learnings, and existing issue overlap. The result is a
bounded local inventory, not an assertion that no other consumer exists. The
deepen review then completed with architecture, security, and data-integrity
agents; their findings are incorporated in this revision. Pencil authentication
was resolved by loading `PENCIL_CLI_KEY` from Doppler; the committed wireframe
was authored, saved, exported, and layout-verified.

## Mechanism Minimality

### Properties to preserve

1. Every new user-chat conversation and routine run dispatches through the
   persisted workspace default; each routine run records the engine selected at
   dispatch so retries and continuations remain stable.
2. Existing conversations keep their engine and native session handle.
3. Chat rendering and lifecycle consumers read a normalized event contract.
4. Soleur authorization, tenant isolation, credential ownership, and spend caps
   apply to every adapter.
5. Local and remote asynchronous execution are represented honestly.
6. Engine dispatch for an unavailable, disabled, or unqualified engine cannot
   silently fall back.
7. Usage provenance, recovery, and reconciliation survive restarts and disconnects.

### Deliberate cuts

- A general transport framework is cut; adapters may use subprocess, stdio,
  WebSocket, or remote HTTP directly until two implementations justify shared
  transport code.
- Customer-uploaded executable adapters are cut; the registry is a reviewed,
  server-deployed allowlist.
- A provider-level model selector as the primary abstraction is cut; model,
  authentication, and entitlement are engine configuration.
- Synthetic token streaming for remote jobs is cut; remote progress is coarse and
  honest.
- In-place migration of old transcripts between engines is cut; transfer creates
  a new engine-bound conversation only after explicit authorization.
- Experimental external ChatGPT token handoff and unsupported Codex auth modes
  are cut from the first release; v1 supports managed ChatGPT sign-in and API-key
  authentication through the server-side credential boundary.

## Research Reconciliation — Spec vs. Codebase

| Spec assumption | Codebase reality | Plan response |
|---|---|---|
| `QueryFactory` is a generic extension point | It imports Claude SDK message and query types | Define a neutral `AgentEngine` contract and wrap current Claude behavior first |
| Platform tools are shared through MCP | `cc-dispatcher.ts` constructs a Claude-specific MCP server | Move tool definitions/policy to a neutral layer and translate per adapter |
| Credentials are provider-specific | BYOK lease and env resolution are Anthropic-only | Add engine/provider credential descriptors and preserve per-user lease ownership |
| Workspace defaults and conversation binding exist | `conversations` has `session_id`, but no engine/default columns | Add migration, RLS-safe read/write helpers, and backfill legacy rows to Claude |
| Remote engines fit the same lifecycle | Current runtime is local Claude with native streaming | Add a deterministic remote test adapter before Codex to force honest states |

### Deepen-review findings applied

- The registry is authoritative for enabled/qualified adapters; persisted
  `engine_id` is an opaque identifier validated against that registry on every
  write and dispatch. An engine may be disabled for new conversations while
  existing conversations remain resumable only if its adapter still passes the
  existing-session qualification check.
- Conversation creation must be one database transaction/RPC: verify the
  authenticated member, read and validate the current workspace default, insert
  the engine binding and configuration snapshot, and return that binding. A
  concurrent default change cannot produce a split-brain conversation.
- Service-role writes require the same workspace assertion as user writes;
  authorization is rechecked immediately before dispatch and every continuation,
  after any external await. The current schema supports `owner` and `member`, so
  changing the default is owner-only until a separate role migration exists.
- A single `session_id` is insufficient for retries and remote event ordering.
  Durable `agent_engine_runs` and `agent_engine_events` records will carry run
  attempts, provider request/idempotency keys, event cursors, cancellation and
  reconciliation state, native session references, and usage provenance.
- Remote adapters require signed/authenticated callbacks, replay protection,
  provider-job-to-workspace/conversation binding, and rejection of all
  client-supplied tenant identifiers. Duplicate IDs with divergent payloads are
  anomalies; stale events cannot regress terminal state.
- Account deletion and DSAR export must stop, cancel/reconcile, and erase remote
  sessions where supported before purging or anonymizing local snapshots, runs,
  events, native references, and usage metadata. Providers without a verified
  erasure capability cannot be enabled for customer content.
- Provider errors are sanitized before pino/Sentry; native references use a
  keyed HMAC rather than a plain hash. The client cannot choose provider,
  credential owner, model, endpoint, or engine configuration.
- Durable database state is authoritative for engine binding, run status, and
  recovery. Process-local registries hold only active transport handles and
  caches; restart recovery reconstructs them from durable state. The neutral
  contract must import without importing the Claude SDK, and `SoleurGoRunner`
  must not become a falsely generic protocol layer.

### Live ordinal verification

The plan author fetched `origin/main` on 2026-09-11 before choosing provisional
artifact names:

```text
git fetch origin main
architecture ADRs on origin/main: latest 216 → ADR-217
Supabase migrations on origin/main: latest 137 → 138_agent_engine_binding
```

The work-phase ledger now lives at
`knowledge-base/project/specs/feat-pluggable-web-agent-engines/tasks.md`; it is
the execution checklist for the RED/GREEN slices below and records verification
evidence as implementation proceeds.

## Implementation Plan

### Phase 0 — Contract and inventory (TDD first)

1. Add failing contract tests for registry lookup, capability evidence,
   conversation binding, no-fallback behavior, event normalization, idempotent
   event sequencing, and current-authorization resolution.
2. Inventory every `conversations` creation/update path, `session_id` consumer,
   tool/approval dispatch, cost writer, attachment path, restart/reconnect path,
   and Anthropic-only auxiliary call. Include `ws-handler.ts`,
   `support-conversation.ts`, `auto-sync-trigger.ts`,
   `app/api/support/route.ts`, and `app/api/repo/setup/route.ts`. Classify each
   as an engine-bound user workload, an engine-bound routine run, a separately
   constrained system job, or an auxiliary model call before making `engine_id`
   required. Persist the result
   in `knowledge-base/project/specs/feat-pluggable-web-agent-engines/agent-engine-consumer-inventory.md`.
3. Define neutral types: `AgentEngineId`, engine definition, capability status
   (`unsupported`, `supported`, `verified`), opaque native session handle,
   normalized lifecycle/event union, usage provenance, and explicit transfer
   command. Include run-attempt identity, cursor-aware event resume,
   provider-job binding, and typed retryability. Keep `Harness` unchanged.
4. Define `EngineAdapter` operations for start, continue, send, cancel,
   reconcile, respond-to-approval, resume-from-cursor, qualify, erase, and
   dispose. Adapters own protocol translation; shared policy owns authorization,
   data-egress, and platform-tool decisions.
5. Define explicit transfer as a separate owner-authorized command: choose the
   target engine from the reviewed registry, select and redact context, record
   consent and an audit row, use an idempotency key, and create a new bound
   conversation. A failed dispatch never replays the source transcript or
   transfers context implicitly.

### Phase 1 — Claude extraction and persistence

1. Add expand/contract migrations `138_agent_engine_binding.sql` and its paired
   `.down.sql` (re-derive the ordinal from a fresh `origin/main` immediately
   before implementation) that add
   `workspaces.default_engine_id`, `conversations.engine_id`,
   `conversations.engine_bound_at`, and non-secret `engine_config_snapshot` JSONB.
   Add durable `agent_engine_runs` and `agent_engine_events` tables with workspace
   and conversation FKs, RLS, unique provider idempotency/event keys, cursors,
   cancellation/reconciliation state, native-reference provenance, and usage
   metadata. Include execution kind and routine-run linkage where applicable so
   routine dispatches carry the same persisted engine binding. Annotate lawful
   basis and retention intent; keep credential values out of snapshots. Backfill
   legacy conversations to Claude, verify counts, and enforce new-row binding
   only after the backfill check. The first-dispatch claim for a routine uses a
   stable scheduler/action identity before any external side effect; the
   terminal-only `routine_runs` WORM row is linked afterward and is not a
   pre-dispatch foreign-key authority. Existing migration 107 forbids
   `CREATE INDEX CONCURRENTLY` inside Supabase's transaction wrapper, so use
   ordinary bounded indexes in this migration or a separately supported index
   operation.
2. Add a SECURITY DEFINER RPC with `SET search_path = public, pg_temp` for the
   owner-only workspace-default mutation and a separate member-authorized RPC
   for atomically creating a conversation from the current default. Revoke
   direct writes, validate the reviewed registry identifier, and test concurrent
   default changes, first-dispatch binding, and attempted direct updates. Members
   may read the setting; `admin` is not a current role and must not be introduced
   implicitly.
3. Extract current Claude SDK code from `soleur-go-runner.ts`, `cc-dispatcher.ts`,
   and `agent-runner-query-options.ts` into a Claude adapter. Preserve existing
   permission callback, session resume, abort-before-replace, worktree lease,
   MCP tool, and Sentry behavior through the adapter boundary.
4. Keep `permission-callback.ts` as the shared policy decision point. Add adapter
   translation tests proving a deny is enforced both before a native approval and
   at platform-tool execution.

### Phase 2 — Deterministic remote adapter and registry

1. Implement a test-only remote asynchronous adapter with queued/running/waiting/
   terminal states, no live streaming, delayed cancellation acknowledgement,
   duplicate/out-of-order events, uncertain dispatch, and missing monetary usage.
2. Register it through the same reviewed registry path as real adapters. Its tests
   must pass without touching network, credentials, or a real paid service.
3. Add transactional event-claim/projection logic and reconciliation records so
   restart/disconnect recovery never blindly starts a second uncertain remote
   job. Reject forged, replayed, cross-workspace, and divergent duplicate events.

### Phase 3 — Codex adapter and workspace UX

1. Add the Codex adapter with both supported authentication modes: API key and
   ChatGPT subscription sign-in. Map App Server thread start/resume, streamed
   events, approval requests, permission scopes, cancellation, and token usage
   into the neutral contract. Persist `thread.id` as the resume handle and
   `thread.sessionId` as native session identity; do not derive one from the
   other or expose protocol objects to client code.
2. Extend provider and lease resolution for Codex/OpenAI credentials. Reuse the
   current encrypted storage and zeroization boundary; implement the managed
   ChatGPT OAuth/device login and token refresh server-side, and never accept
   browser-supplied access tokens. Preserve the auth mode, billing source, and
   data-control profile in non-secret metadata. The client cannot supply
   provider, credential owner, model, endpoint, or engine configuration. Resolve
   all of them server-side and recheck membership, revocation, entitlement,
   spend authorization, and egress policy immediately before dispatch and every
   continuation.
3. Add a pre-dispatch data-egress policy that records endpoint allowlist, accepted
   data classes, vendor/DPA status, transfer geography, deletion support, and
   approval requirements. Refuse dispatch when evidence or workspace policy is
   missing; authenticate and replay-protect all remote callbacks.
4. Add a “Default agent engine for new conversations” section to the existing
   workspace settings page. Show engine availability, required credential state,
   capability gaps, the selected Codex auth mode (API key or ChatGPT sign-in),
   and the rule that existing conversations and routine runs keep their engine.
   The API must validate ownership, engine qualification, and credential presence
   independently of the UI.
5. The committed Pencil wireframe is
   `knowledge-base/product/design/agent-engine-selection/workspace-default-engine.pen`;
   keep the shipped flow aligned with it and export the review PNG to
   `knowledge-base/product/design/agent-engine-selection/screenshots/01-workspace-default-agent-engine.png`.

### Phase 4 — Qualification and rollout

1. Run both real adapters through the same matrix: authorized platform tool,
   approval denial, restart recovery, cancellation, cross-workspace isolation,
   revoked credential, usage attribution, attachment handling, and capability
   mismatch. Bound live usage and record the measured results.
2. Add a feature flag for Codex dispatch and roll out to an internal cohort using
   synthetic or explicitly redacted repository data only. Keep Claude as the
   default until Codex qualification passes; never use a flag as a substitute for
   capability or authorization checks.
3. Add explicit DSAR/account-delete ordering: stop new work, cancel and reconcile
   active runs, erase remote content where supported, then purge/anonymize local
   runs/events/snapshots and include them in export. Providers without verified
   erasure remain disabled for customer content.
4. Publish a capability matrix and update Claude Code-only public claims only after
   CMO/CLO signoff. Keep Grok Build and Devin behind capability-scoped registry
   entries until the workflow-specific qualification gates pass; do not imply
   full interactive parity.
5. Complete the vendor qualification record for Codex (and each future remote
   engine): auth-mode-specific data-processing/DPA status, billing owner and
   recurring expense, retention/deletion behavior, endpoint and subprocess trust
   boundary, failure and support assumptions, pinned package/binary version and
   digest where applicable, lockfile/provenance scan, and a no-network-at-runtime
   decision. CLO approval is required before customer repository content is
   enabled.

## Acceptance Criteria

- The neutral contract tests pass for Claude, Codex, and the deterministic remote
  adapter; adding a fourth adapter changes only registration, adapter code, and
  adapter tests.
- New user-chat conversations inherit the workspace default; existing rows
  retain their engine and native session binding across default changes and
  restarts. Routine runs inherit the current default at dispatch and retain that
  binding across retries and continuations.
- Atomic creation tests prove the persisted engine and configuration snapshot are
  selected and inserted in one transaction; concurrent default changes and
  concurrent first dispatches cannot split the binding. A database boundary
  prevents direct mutation after `engine_bound_at`.
- For engine dispatch, an unavailable, disabled, or unqualified selected engine
  produces a visible failure, invokes no alternate adapter, and sends no context
  to another provider.
- All adapters enforce current membership, credential validity, revocation,
  permission decisions, spend authorization, and platform-tool policy.
- Codex supports both API-key and ChatGPT subscription sign-in; the selected mode
  is encrypted at rest, visible in workspace settings, and mapped to its own
  billing and data-control policy without accepting browser-supplied tokens.
- For engine dispatch, clients cannot select provider, credential owner, model,
  endpoint, or engine configuration. Workspace A cannot use workspace/user B's
  key, including delegated-key continuations after revocation.
- Every service-role conversation, run, event, reconciliation, DSAR, and
  account-delete write asserts workspace scope; the creation inventory names
  support, auto-sync, repo-setup, routine, and user-chat paths with an explicit
  engine-bound or system-job treatment.
- Queued remote work, absent streaming, duplicate events, uncertain dispatch,
  delayed cancellation, and estimated/unavailable usage have deterministic tests
  and honest client states.
- A remote engine can be enabled for a restricted workflow only when its declared
  capabilities and vendor evidence qualify that workflow; no partial adapter is
  presented as full interactive parity.
- Native usage units and provenance remain distinct from monetary cost; no
  unverified value is stored or displayed as zero.
- Restart and disconnect recovery is idempotent, and a cancellation request is
  not marked complete until reconciliation confirms termination.
- Remote callbacks require signature verification, replay protection, strict
  provider-job-to-workspace/conversation mapping, and rejection of forged,
  cross-workspace, divergent-duplicate, or stale terminal events.
- DSAR export and account deletion include engine snapshots, runs, events, native
  references, usage metadata, and remote erase/cancel ordering; providers without
  verified remote erasure are disabled for customer content.
- The first-release inventory names every remaining Anthropic-dependent auxiliary
  call and states its user-visible implication before Codex rollout.
- Workspace settings explain default scope, existing-conversation continuity,
  routine-run binding, both Codex auth modes, missing credentials, and capability
  gaps; the committed `.pen` wireframe exists and matches the shipped flow.
- ADR-217, `model.c4`, and the regenerated `model.likec4.json` describe the
  same registry, adapter, persistence, credential, remote-execution, and
  observability boundaries.

## Files to Edit

- `apps/web-platform/lib/types.ts`
- `apps/web-platform/server/soleur-go-runner.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/agent-runner-query-options.ts`
- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/byok-lease.ts`
- `apps/web-platform/server/byok-resolver.ts`
- `apps/web-platform/server/agent-env.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/server/conversation-writer.ts`
- `apps/web-platform/server/support-conversation.ts`
- `apps/web-platform/server/auto-sync-trigger.ts`
- `apps/web-platform/server/routines/run-routine.ts`
- `apps/web-platform/server/routines-tools.ts`
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts`
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-weekly-analytics.ts`
- `apps/web-platform/server/inngest/middleware/run-log.ts`
- `apps/web-platform/server/inngest/cron-manifest.ts`
- `apps/web-platform/server/dsar-export.ts`
- `apps/web-platform/server/dsar-export-allowlist.ts`
- `apps/web-platform/server/account-delete.ts`
- `apps/web-platform/app/api/support/route.ts`
- `apps/web-platform/app/api/repo/setup/route.ts`
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- `apps/web-platform/components/settings/settings-content.tsx`
- `apps/web-platform/package.json`, `apps/web-platform/Dockerfile` (only if the
  chosen Codex transport requires a pinned runtime executable)
- `apps/web-platform/supabase/migrations/138_agent_engine_binding.sql` and its
  paired `138_agent_engine_binding.down.sql`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json`
- Existing adapter, dispatcher, permission, BYOK, conversation, and WebSocket
  test files identified by the Phase 0 consumer inventory.

## Files to Create

- `apps/web-platform/server/agent-engine-contract.ts`
- `apps/web-platform/server/agent-engine-registry.ts`
- `apps/web-platform/server/agent-engine-policy.ts`
- `apps/web-platform/server/agent-engine-data-egress-policy.ts`
- `apps/web-platform/server/agent-engine-remote-test-adapter.ts`
- `apps/web-platform/server/codex-agent-adapter.ts`
- `apps/web-platform/server/agent-engine-error-sanitizer.ts`
- `apps/web-platform/components/settings/agent-engine-settings.tsx`
- `apps/web-platform/test/agent-engine-contract.test.ts`
- `apps/web-platform/test/agent-engine-registry.test.ts`
- `apps/web-platform/test/agent-engine-routing.test.ts`
- `apps/web-platform/test/agent-engine-remote-reconciliation.test.ts`
- `apps/web-platform/test/codex-agent-adapter.test.ts`
- `apps/web-platform/test/agent-engine-security-boundary.test.ts`
- `apps/web-platform/test/agent-engine-dsar.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-217-pluggable-web-agent-runtime.md`
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/agent-engine-consumer-inventory.md`
- `knowledge-base/product/design/agent-engine-selection/implementation-brief.md`
- `knowledge-base/product/design/agent-engine-selection/workspace-default-engine.pen`
- `knowledge-base/product/design/agent-engine-selection/screenshots/01-workspace-default-agent-engine.png`

## Observability

liveness_signal: Emit structured `engine_dispatch_started`,
`engine_dispatch_progress`, `engine_dispatch_completed`,
`engine_dispatch_failed`, and `engine_session_reconciled` events for every
execution. Durable conversation
status and existing WebSocket lifecycle remain the product signal; a watchdog
marks queued/running/waiting jobs whose heartbeat or reconciliation deadline
passes.

error_reporting: Use structured pino logs and `reportSilentFallback` to Sentry
for adapter startup, auth/credential, permission, reconciliation, cancellation,
and usage failures. Sanitize provider errors before both sinks. Selected-engine
failure is fail-loud and never invokes a silent fallback path.

failure_modes: The table below maps each failure to its detection and observability layer.

| Failure mode | Detection and response | Observability layer |
|---|---|---|
| Adapter unavailable/disabled/unqualified | Registry eligibility check; durable conversation failure; no fallback | Sentry exception + pino + `engine_dispatch_*` event |
| Permission or platform-tool denial | Shared policy decision and audit event; native adapter deny | Permission audit row + Sentry for unexpected errors |
| Remote timeout or uncertain cancellation | Reconciliation deadline; honest waiting/unknown state; retry requires idempotency key | Durable job/conversation state + watchdog event + Sentry |
| Duplicate or out-of-order event | Sequence/idempotency guard; ignore duplicate and record anomaly | Event ledger + pino warning + Sentry anomaly |
| Missing or estimated usage | Preserve native units/provenance and mark unavailable/estimated | Cost writer + usage event + Sentry on writer failure |
| Cross-workspace credential/session lookup | RLS and lease-owner checks fail closed | Auth audit row + Sentry + test fixture |

logs: Pino structured fields include `engine_id`, `conversation_id`,
`workspace_id`, `adapter_version`, `event_id`, `native_session_ref_hash`, and
`failure_class`; never log prompts, credentials, native handles, or remote
payloads. `native_session_ref_hash` is a keyed HMAC. Durable product state
stores normalized lifecycle, approval, usage, and reconciliation metadata with
existing retention/deletion paths.

discoverability_test:
  command: `rg -n "engine_dispatch_started|engine_dispatch_failed|engine_session_reconciled" apps/web-platform/server apps/web-platform/lib`
  expected: one start, one failure, and one reconciliation instrumentation site;
    tests assert each marker is emitted without credentials.

## GDPR Gate

The plan touches provider credentials, authentication routes, schema migrations,
and remote customer-content handling. The advisory gate was invoked against
representative migration/API/BYOK paths and reported:

- `gdpr-gate rules 124 days stale` and `POSTURE_FAIL` (last verified 2026-05-10);
  findings are advisory, the corpus needs refresh before relying on a clean
  result, and implementation remains `pending-operator` for this gate until the
  rules are refreshed or CLO accepts the stale-corpus exception.
- `3 examined, 2 matched` regulated-data paths; run `/soleur:gdpr-gate` again at
  work Phase 2 exit after the concrete migration and routes exist.

Implementation must add lawful-basis and retention annotations to the migration,
preserve erasure/export coverage for engine snapshots and event records, document
the Codex vendor/DPA and any Chapter-V transfer, and obtain CLO review. No prompt,
credential, or remote row value may be sent to the gate or committed to fixtures.

## Encryption Posture

at_rest:
  - store: Supabase project (workspaces, conversations, engine runs/events)
    mechanism: provider-managed encryption plus app-layer envelope encryption for BYOK
    evidence: existing BYOK encryption/zeroization path; migration tests reject plaintext credential columns
    defends_against: disk loss or raw snapshot access exposing stored credentials and engine metadata
    does_not_defend: compromised service role, vendor retention, prompt content intentionally sent to a qualified engine, or a live credential in process memory
    disclosed_as: existing encrypted storage posture; remote vendor processing disclosed separately
    live_verification: unavailable until preflight verifies the target Supabase project posture
in_transit:
  - connection: Soleur server -> Codex App Server or future remote adapter
    enforced_at: agent-engine-data-egress-policy.ts › authorizeEndpoint()
    tls: HTTPS/TLS with certificate verification
    cert_verification: on
    does_not_defend: a compromised trusted endpoint, vendor retention allowed by contract, or an authorized user action
    disclosed_as: transfer only to qualified, allowlisted vendors with documented geography, DPA, retention, and deletion support

## Guard Contract

### Guard 1 — Engine eligibility and engine-dispatch no-fallback boundary

**Property.** Engine dispatch routes only to the persisted engine when that
engine is registered, enabled for the operation, qualified for the required
capabilities and data classes, and authorized for the current workspace. Failure
does not invoke another adapter.

**Assembly.** The dispatch chokepoint resolves the persisted binding through the
reviewed registry, then passes the result through current authorization and
data-egress policy before invoking an adapter; all adapter entry points consume
that decision rather than accepting client-selected provider fields.

**Mutation matrix.**

| Mutation | Expected RED signal |
|---|---|
| Remove the registry eligibility check | No-fallback contract test dispatches an unqualified engine |
| Allow a client-supplied `engine_id` to override the persisted binding | Tenant-bound routing test reaches the wrong adapter |
| Skip the pre-dispatch data-egress decision | Unqualified vendor test sends context instead of failing closed |
| Replace the atomic conversation creator with separate read/insert calls | Concurrent-default test observes a split binding |

### Guard 2 — Remote event authenticity and projection

**Property.** Only authenticated, tenant-bound, idempotent provider events may
advance a run projection; duplicate or stale events cannot regress terminal state.

**Assembly.** The event-ingress chokepoint verifies the provider signature and
replay window, resolves the provider job to the durable run row, claims the
unique event key, and applies the projection in one database transaction.

**Mutation matrix.**

| Mutation | Expected RED signal |
|---|---|
| Remove signature verification | Forged callback test is accepted |
| Drop the unique event-key constraint | Concurrent duplicate delivery double-applies |
| Permit terminal-state regression | Stale completion test overwrites the terminal projection |

## Architecture Deliverables

- ADR documenting the engine-versus-harness boundary, adapter ownership,
  workspace/conversation binding, authorization and credential trust boundaries,
  local/remote lifecycle, and no-fallback rule.
- Update `knowledge-base/engineering/architecture/diagrams/model.c4` and regenerate
  `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`. Model the neutral
  engine registry, Claude/Codex adapters, remote execution boundary, and their
  relationships to workspace state, session storage, credentials, and observability.
- Keep the existing `Harness` union and ADR-215 plugin compatibility decision
  unchanged; this plan concerns Web execution engines.

## Scope, Risks, and Rollout

**Estimate:** large, week+; split into contract/persistence, deterministic remote
adapter, Codex, and qualification slices. Do not merge a partial adapter that
can bypass shared policy.

**Primary risks:** Claude behavior regression during extraction; Codex approval or
resume semantics not matching assumptions; remote jobs duplicating paid work;
credential ownership crossing workspace boundaries; stale public claims; and
unmeasured vendor spend. Each risk has a deterministic test or a qualification
gate above.

**Rollout:** Keep Claude enabled and the workspace default unchanged while the
Codex flag is internal-only. Promote only after both adapters pass qualification,
GDPR/CLO review, CPO/CMO messaging review, the settings `.pen` gate, and QA with
restart/cancellation evidence. Grok Build and Devin remain capability-scoped
registry entries until their workflow-specific qualification gates pass.

## Downtime & Cutover

The migration touches hot `workspaces` and `conversations` tables, so the plan
uses an expand/contract, zero-downtime path: add nullable columns and new tables;
backfill in bounded batches; add ordinary bounded indexes inside the migration
transaction (or use a separately supported non-transactional index operation);
add foreign keys/checks as `NOT VALID` and validate them separately; then enable
the atomic creator for new rows. Existing Claude dispatch remains valid
throughout. Verify row counts, null coverage, and dual-read compatibility before
enforcing the new binding, and roll back by disabling the new creator while
preserving the added columns and records. No serving host restart or maintenance
window is required.

## Resolved Decisions Before `/work`

1. Codex v1 supports both API-key authentication and ChatGPT subscription
   sign-in. The auth mode, billing source, retention controls, and data-control
   profile remain distinct policy inputs.
2. Workspace routines are included in the workspace default. Each routine run
   resolves the current default at dispatch and persists that engine binding;
   retries and continuations retain it.
3. The registry supports capability-scoped remote engines. A restricted workflow
   may be enabled only after workflow-specific capability and vendor
   qualification; no partial adapter is presented as full interactive parity.
4. Synthetic or explicitly redacted internal dogfooding is allowed behind the
   Codex flag. Customer repository content remains blocked until the vendor
   qualification record and CLO disposition cover both auth modes, processing,
   retention, geography, billing, and remote erasure.

The remaining items are work-phase gates and evidence collection, rather than
unresolved product direction.
