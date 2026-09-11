---
title: Pluggable agent engine consumer and write-site inventory
date: 2026-09-11
feature: feat-pluggable-web-agent-engines
source_revision: 9c3c0cccc
status: implementation-input
---

# Agent engine consumer inventory

All paths below are relative to `apps/web-platform/` unless explicitly marked
otherwise. Symbols are the anchors; line numbers are deliberately omitted.
This inventory describes the code before implementation, not completed engine
support. The user approved both Codex authentication modes and included routines:
every new routine run must select the workspace default at first dispatch, then
retain that selection across retries and continuations.

## Conversation producers and mutation boundaries

| Path and symbol | Existing behavior | Required treatment |
|---|---|---|
| `server/ws-handler.ts` › `createConversation()` | Tenant insert with resolved workspace, current repo, optional domain leader/context/active workflow. Called on first user message. Context-path unique violation reuses an existing row. Supports both command-center and support kinds. | Atomically bind new user conversations to the current default. On duplicate reuse return the existing binding; do not reselect the default. Creation must remain available to authorized members, even though changing the workspace default is owner-only. |
| `server/support-conversation.ts` › `resolveOrCreateSupportConversation()` | Separate SSE producer; reuses most recent support row or inserts on force-new. Resolves current workspace and stores repo-less support kind. | Classify explicitly as user support workload and bind at insertion, or explicitly constrain an approved support engine. Do not silently default a Codex support row to Claude. |
| `app/api/support/route.ts` › `POST()` | Calls the support producer and `dispatchSoleurGo()` directly, bypassing WS creation. | Route through the same durable engine/policy boundary and preserve support read-only tool and repo-less restrictions. |
| `server/auto-sync-trigger.ts` › `triggerHeadlessSync()` | Service-role conversation insert once outside bounded lease retries; assigns a random legacy session ID and calls injected `startAgentSession`. Anthropic effective-key presence gate precedes insertion. | This executes on a customer's repository. Bind once and preserve across retries. A Codex-only workspace must not be skipped because it lacks Anthropic. Replace fabricated native session identity with real adapter identity. |
| `app/api/repo/setup/route.ts` › `POST()` | After clone completes, dynamically imports legacy runner and injects `startAgentSession()` into headless sync. | Include this producer in default/credential tests. It is not covered by changing WS dispatch alone. |
| `server/conversation-writer.ts` › `updateConversationFor()` / `ConversationPatch` | Central targeted tenant update keyed by conversation ID and user ID, with optional status predicate and expected-match enforcement. Patches status, activity, legacy session ID, workflow and leader. | Preserve authorization and conditional terminal transitions. Binding/native-reference writes need dedicated immutable-binding semantics, not arbitrary addition to `ConversationPatch`. |
| `server/agent-runner.ts` › `updateConversationStatus()`, `updateConversationStatusIfActive()` | Call the targeted writer; guarded variant avoids overwriting a terminal concurrent result. | Preserve across all adapters; use normalized lifecycle projection without widening statuses blindly. |
| `server/agent-runner.ts` › `cleanupOrphanedConversations()` | Direct bulk updates fail active/waiting rows, then complete older completed workflows. | Remote queued/running work cannot be declared dead merely because local process handles are absent. Reconcile durable run state before bulk status projection. |
| `server/conversations-tools.ts` › `buildConversationsTools()` | Direct archive, unarchive, and status writes use conversation/user/repo filters; separate from targeted writer. | Keep visibility/ownership checks; engine binding must remain immutable through these paths. |
| `server/ws-handler.ts` | Targeted writes on disconnect, ledger recovery, workflow persistence and explicit close. | Every path must distinguish local socket state from durable provider job state. |
| `server/cc-dispatcher.ts` › `dispatchSoleurGo()` / `persistCcSessionId()` / `clearCcSessionId()` | Ownership probe and workflow/status/native-session writes through targeted writer. | Shared dispatcher must load persisted engine before selecting adapter. A Claude resume error must never clear a Codex/remote reference. |

The source sweep found three direct conversation insert sites: WS creation,
support creation, and headless sync. `agentOnSpawnRequestedHandler()` instead
mints a deterministic conversation UUID without inserting a conversation; see
the routine section. Read-only conversation consumers also include
`api-messages.ts`, `lookup-conversation-for-path.ts`, `api-usage.ts`,
`dsar-export-co-uploader.ts`, attachment presign/download routes, repo status,
chat/dashboard/billing pages, and admin analytics.

SQL writers must also be considered: migrations `017` and `042` define the
conversation cost increment function; `075` and `076` contain visibility/activity
updates. Historical backfills in `029`, `031`, `059`, and `075` are migration-time
writes, not live dispatch paths. New binding triggers must allow unrelated cost,
visibility, activity, archive and retention updates while rejecting rebinding.

## Routines: scheduled and manual are both in scope

The current Routines surface displays code-defined Inngest functions. This is
implementation evidence, not grounds to exclude the user's requested routines.
There is no workspace argument on `runRoutine()` today, no workspace column on
the initial `routine_runs` table, and no workspace on `spawnClaudeEval()`.
Adding a default setting alone therefore cannot meet the routine requirement.

| Producer / execution path | Scope proven by source | Extraction requirement |
|---|---|---|
| `server/routines/run-routine.ts` › `runRoutine()` | Validates `EXPECTED_CRON_FUNCTIONS`, confirmation policy; adds trusted actor attribution, then sends manual-trigger event. Has no workspace field. | Resolve trusted workspace and logical run identity before enqueue/first engine dispatch; server-controlled scope must override payload. Preserve confirmation policy. |
| `app/api/dashboard/routines/run/route.ts` › `POST()` | Authenticates user and calls `runRoutine({ fnId, actorClass: "human", actorId })`. | Derive workspace and current authorization server-side; test a manual run with Codex default. |
| `server/routines-tools.ts` › `buildRoutinesTools()` | Exposes list, runs list, and gated `routine_run`; supplies agent attribution. | Same workspace resolution and first-dispatch binding as human route. Preserve review approval. |
| `app/api/internal/trigger-cron/route.ts` | Secret-tier caller of `runRoutine`, system actor. | Require an explicit trusted scope for workspace work. Do not use an ambient interactive user's current workspace. |
| `server/inngest/cron-manifest.ts`, `routine-metadata.ts`, `app/api/inngest/route.ts` | Manifest, descriptions/policy, and serve registration for code-defined scheduled functions. | Register workload scope and required capabilities alongside each routine; both scheduled and manual entry points converge before engine dispatch. |
| `server/inngest/functions/cron-weekly-analytics.ts` | Trusted KPI-miss cascade emits manual-trigger events directly, bypassing `runRoutine`. | Include this producer in scope/binding propagation; a manual-route-only fix misses cascades. |
| `server/inngest/functions/_cron-claude-eval-substrate.ts` › `spawnClaudeEval()` | Receives optional Inngest run ID/attempt, spawns resolved Claude binary, handles timeout/escalation, progress heartbeat, redacted tails and Claude result cost parsing. | Replace engine-specific spawn/flags/result parsing behind an adapter while retaining containment. First dispatch durably claims `(workspace, logical routine run)`; retries reuse it. |
| `server/inngest/functions/cron-daily-triage.ts`, `cron-follow-through-monitor.ts` | Inline Claude spawn paths with their own narrow tool flags and env allowlists; do not use `spawnClaudeEval`. | Include both in extraction/qualification or they remain silent Claude-only routine paths. |
| `server/inngest/functions/agent-on-spawn-requested.ts` › `agentOnSpawnRequestedHandler()` | Tenant leader loop receives server-derived founder ID, uses BYOK, per-class tools and spend cap, raw `Anthropic.messages.create`, stable `actionSendId`; deterministic conversation UUID is not persisted. | This is an autonomous tenant workload, not an auxiliary classifier. Route through selected engine and durable run binding, preserving allowlisted leader actions, budget reservation and per-turn idempotency. Use explicit workspace resolution rather than assuming every team workspace equals founder ID. |
| `app/api/dashboard/today/[id]/send/route.ts` › `POST()` | Persists action-send before `agent.spawn.requested` event; emits founder/action identity. | Preserve producer idempotency and carry trusted workspace into the tenant leader run. |
| `server/inngest/functions/event-scheduled-reminder.ts` | Generic scheduled action/reminder primitive; action validation in `lib/inngest/scheduled-reminder-action.ts`. | Non-agent reminders do not need a model. Any action that dispatches an agent must converge on the same workspace engine boundary. |

The shared Claude-substrate callers found in the source sweep are
`cron-agent-native-audit`, `cron-architecture-diagram-sync`, `cron-bug-fixer`,
`cron-campaign-calendar`, `cron-community-monitor`, `cron-competitive-analysis`,
`cron-content-generator`, `cron-growth-audit`, `cron-growth-execution`,
`cron-legal-audit`, `cron-roadmap-review`, `cron-seo-aeo-audit`, `cron-ux-audit`,
`event-ship-merge`, `oneshot-f2-defer-gate-review`, and
`oneshot-recheck-4217-calibration` (all under `server/inngest/functions/`).
The source `_cron-shared.ts` explicitly pins `REPO_OWNER = "jikig-ai"` and
`REPO_NAME = "soleur"`; these existing jobs operate on Soleur's own repository.
Workspace-owned execution needs an explicit scope/target boundary, not replacing
those constants with an untrusted payload. Routine scope must be classified from
actual ownership and intended target; “operator job” cannot be used to drop the
requested ability for workspace routines to use Codex.

`routine_runs` migration `107` creates a terminal-only WORM log written by
`server/inngest/middleware/run-log.ts` › `runLogMiddleware`. `routine_run_progress`
is transient heartbeat state written by `upsertRoutineRunProgress()` and read by
`server/routines/list-routines.ts`. Neither is a suitable first-dispatch authority:
terminal rows do not exist yet and progress writes are fail-soft. Create durable
engine runs before side effects with stable scheduler/action identity; link the
terminal audit row afterward. Do not require a pre-existing terminal-log FK.
Scheduled runs have no actor by design; derive workspace from a trusted routine
definition, not `actor_id`. Authenticated global-read RLS in migration `107` and
list APIs must be narrowed before tenant routine rows are exposed.

## Session identity, transport and recovery

- `soleur-go-runner.ts` › `QueryFactoryArgs`, SDK message processing, and
  `onSessionIdCaptured` carry Claude query/session identity. Its synthetic user
  messages also contain SDK `session_id`; keep those in the Claude translation.
- `cc-dispatcher.ts` › `persistCcSessionId()` and `clearCcSessionId()` write
  `conversations.session_id`; `dispatchSoleurGo()` receives it and passes it to
  the query factory. These are compatibility projections, not universal handles.
- `agent-runner.ts` › `startAgentSession()` captures the SDK ID;
  `sendUserMessage()` reads the DB ID or active-session ID, resumes, and clears a
  stale ID before retry. Preserve same-engine retry and avoid cross-engine replay.
- `ws-handler.ts` caches `session_id` with routing/context, reads it on resumed
  turns and supplies it to dispatch. New binding/config/native-reference caches
  must invalidate at the same workspace/conversation transitions.
- `stream-replay-buffer.ts` › `StreamReplayBuffer` / `isBufferedFrame()` uses a
  process-local sequence and bounded frames; WS reconnect validates ownership
  before replay. Durable provider-event cursors are separate from WS cursors.
- `cc-dispatcher.ts` › `closeCcConversation()`, `reapIdleCcQueries()`, and close
  cleanup; `agent-runner.ts` session abort/reaper; `inflight-checkpoint.ts` ›
  `checkpointInflightWorkForConversation()` / `restoreInflightCheckpoint()`
  control process and filesystem recovery. Remote job cancellation and durable
  reconciliation cannot be inferred from socket closure or missing local maps.
- `session-registry.ts` holds WS clients, and runner maps hold active handles.
  They remain caches. Reconstruct durable runs after restart before admitting a
  new attempt.
- JWT `session_id` in DSAR reauthentication and Stripe checkout `session_id`
  are unrelated identifiers; do not migrate them as native agent handles.

## SDK, tools and policy extraction

`soleur-go-runner.ts` defines `QueryFactory = (...) => Promise<Query> | Query`,
imports Claude SDK query/message types and Anthropic message types, and consumes
the SDK iterator directly. Its public lifecycle and browser messages are not a
neutral engine contract. `cc-dispatcher.ts` › `realSdkQueryFactory()` binds
`sdkQuery()` and `createSdkMcpServer()`; `agent-runner.ts` has another live SDK
entry. `agent-runner-query-options.ts` › `buildAgentQueryOptions()` builds SDK
options, hooks, environment, resume and permission configuration for both.

`permission-callback.ts` › `createCanUseTool()` is the policy behavior to preserve,
but its current signature imports SDK `CanUseTool`/`PermissionResult`. Extract a
neutral policy request/result underneath it and keep the existing SDK callback
as a Claude wrapper. Mapping Codex tool names into Claude names without checking
their input semantics is insufficient: file paths, shell commands, approval
scopes, sandbox root, and unsupported tools must be enforced before execution.

The SDK `tool()` imports occur in `account-tools.ts`, `auth-status-tools.ts`,
`c4-concierge-tools.ts`, `conversations-tools.ts`, `email-triage-tools.ts`,
`github-tools.ts`, `inbox-tools.ts`, `kb-share-tools.ts`, `narrate-tool.ts`,
`plausible-tools.ts`, `routines-tools.ts`, `workspace-settings-tools.ts`,
`crm/crm-tools.ts`, and `workstream/workstream-tools.ts` (all under `server/`).
Extract metadata/schema/handler definitions from SDK registration; shared policy
must still run at tool execution. `tool-tiers.ts`, `tool-path-checker.ts`,
`safe-bash.ts`, `bash-sandbox.ts`, `sandbox-hook.ts`, and `review-gate.ts` carry
classification/containment/approval behavior. `cc-interactive-prompt-response.ts`
› `handleInteractivePromptResponse()` and `pending-prompt-registry.ts` enforce
response correlation and tombstones; preserve them for native approvals.

SDK hook-type consumers also include `agent-prefill-guard.ts`,
`context-queries-hook.ts`, `git-lock-marker-telemetry.ts`, `phase-surface-hook.ts`,
`tool-attempt-telemetry.ts`, and `pdf-chapter-router.ts`. They belong in the
Claude wrapper unless a separate engine-neutral behavior is extracted.

## Credentials, usage, attachments and data rights

| Surface | Current boundary and required change |
|---|---|
| `byok-lease.ts` › `runWithByokLease()` / `fetchProviderRow()` | Tenant/key-owner lease, decryption context and zeroization. Fetch union is only `anthropic` or `anthropic_oauth`; raw REST and SDK credentials are deliberately separate. Codex credentials need explicit engine/auth-mode selection, no provider inference from a generic `oauth_token`. |
| `agent-env.ts` › `AgentCredential` / `buildAgentEnv()` | Scheme-only `api_key` or `oauth_token` chooses Anthropic/Claude env vars; allowlisted service env vars derive from `PROVIDER_CONFIG`. Do not inject Codex credentials through this Claude helper or leak both vendors' auth into one subprocess. |
| `providers.ts`, `token-validators.ts`, `lib/types.ts` › `Provider` | Shared service catalog and partial validator map; valid Provider lacks OpenAI and excludes internal Anthropic OAuth. Adding a provider affects services UI/env injection as well as credential storage. Use an explicit auth descriptor instead of treating a ChatGPT session as a generic API key. |
| `app/api/keys/route.ts`, `app/api/services/route.ts` | User-key upsert and provider-controlled service CRUD/validation. Managed login needs trusted begin/callback/poll/logout behavior, user/workspace ownership and encrypted refresh state; do not accept browser access-token submission. |
| `byok-resolver.ts`, `byok-delegation-ui-resolver.ts`, `byok-cap-rpc.ts`, `auth-status-tools.ts` | Effective-key checks, delegated owner identity, cap authorization and user guidance. Audit all callers before declaring Codex-only workspaces eligible. Reauthorize warm continuations as well as cold factories. |
| `cost-writer.ts` › `TurnCostInput`, `persistTurnCost()`, `persistTurnCostAwaitable()` | Requires numeric totalCostUsd and currently converts non-finite cost to zero; usage is Anthropic uncached/cache counts. Callers: legacy runner, CC dispatcher and autonomous leader loop. Introduce explicit reported/estimated/unavailable monetary provenance before passing Codex results. Subscription usage is not known zero cost. |
| `claude-cost-marker.ts`, `cc-cost-caps.ts`, `session-metrics.ts`, `api-usage.ts`, Today action cost route | Claude-shaped source/model/usage aggregation and spend guards. Preserve billing owner and distinguish pricing estimates, tokens, subscription entitlement and enforceable caps. |
| `attachment-pipeline.ts` › `persistAndDownloadAttachments()` | Shared authorization/persistence/download boundary consumed by both runners; presign/url routes validate conversation access. Preserve attachment ownership and size/type controls before engine translation. |
| `pdf-text-extract.ts`, `pdf-linearize.ts`, `pdf-chapter-router.ts`, `kb-document-resolver.ts` | PDF context pipeline uses a Claude auxiliary query for chapter choice; engine-specific native input support must not bypass limits or send documents to an unqualified vendor. |
| `dsar-export.ts`, `dsar-export-allowlist.ts`, `dsar-export-co-uploader.ts` | Export is allowlisted and relation-aware, not automatically extended by new tables. Add engine binding/config/run/event/native reference/usage and workspace routine coverage. `routine_runs` is explicitly excluded on a single-operator assumption that cannot cover customer routine data. |
| `account-delete.ts` | Cancels local work and performs storage/PII erasure saga; calls `anonymise_routine_runs` before auth deletion due WORM/RESTRICT constraints. Add remote stop/reconcile/erase before local references and usable credentials are purged. |

## Anthropic auxiliary and independent calls

- `domain-router.ts` › `routeMessage()` performs raw Anthropic HTTP classification,
  called by legacy `sendUserMessage()`. Local mention parsing is separate. Codex
  sign-in does not supply the Anthropic REST key this call expects.
- `pdf-chapter-router.ts` › `selectChapter()` uses Claude SDK query; called by
  both `agent-runner.ts` and `soleur-go-runner.ts`. This sends document-derived
  context and must be included in egress disclosure/qualification.
- `email-triage/summarize.ts` › `summarizeEmail()` uses `Anthropic.messages.create`,
  called by `inngest/functions/email-on-received.ts`. Record separate email
  processing policy; do not claim all user data follows the selected chat engine.
- `inngest/functions/_cron-shared.ts` › `postAnthropicMessage()` is called by
  `cron-weekly-release-digest`, `cron-compound-promote`, and
  `cron-anthropic-credit-probe`. The first two perform model work; the last is
  deliberately an Anthropic health probe. `cron-anthropic-cost-report` uses the
  Anthropic Admin API for billing metadata. Provider-specific probes need not be
  changed into Codex probes merely because a workspace switches engines.
- `agent-on-spawn-requested` is listed with routines above because it is a full
  tenant autonomous agent loop, not a classifier to silently leave on Anthropic.

## Shared type consumer sweep

Run all three discriminant patterns when widening any shared union:
`const _exhaustive: never`, `.kind === "`, and `?.kind === "`.
The baseline sweep found relevant exhaustive rails in `ws-handler.ts`,
`cc-dispatcher.ts`, `soleur-go-runner.ts`, `agent-runner.ts`,
`cc-interactive-prompt-response.ts`, `conversation-routing.ts`, `agent-env.ts`,
`byok-lease.ts`, `lib/chat-state-machine.ts`, `lib/ws-client.ts`, and chat input,
surface, workflow-lifecycle and interactive-prompt components. Non-exhaustive
kind comparisons also occur in runners/dispatcher, `cost-writer.ts`,
`lib/chat-state-machine.ts` and `components/chat/chat-surface.tsx`; the optional
kind comparison sweep specifically finds `ws-handler.ts`.

Do not indiscriminately widen `Conversation.status` to the entire engine state
machine: `conversations-rail.tsx` has complete status label/badge maps,
`cc-dispatcher.ts` has a runtime status allowlist, and WS/browser reducers accept
the existing protocol. Durable engine state can be projected into that protocol
with explicit queued/remote UI additions. Grep hits in unrelated inbox/git/PII
unions are not proof those unions need changing.

Important characterization tests to retain are `agent-runner-query-options`,
`cc-dispatcher-real-factory`, `cc-dispatcher-session-id-writer`,
`ws-handler-cc-session-id-wiring`, `soleur-go-runner-session-id-rebound`,
`soleur-go-runner-lifecycle`, interactive-prompt/approval tests, conversation
writer and orphan recovery tests, and the existing `test/server/routines/` and
`test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` tests. Query
fixtures in `test/helpers/soleur-go-fixtures.ts` and
`test/helpers/cc-dispatcher-harness.ts` deliberately remain Claude-shaped while
new neutral contract tests must load without the Claude SDK.

## Minimum extraction cuts and plan corrections

1. Introduce neutral identity/lifecycle/capability and policy types independently
   of `QueryFactory`. Wrap the two existing live Claude entry points, rather
   than renaming their SDK types to engine-neutral names.
2. Atomically bind conversation creation and first routine dispatch in the DB;
   use dedicated immutable run identity. Preserve member conversation creation,
   owner-only default mutation, and explicit service-role workspace assertions.
3. Extract shared tool definitions and neutral policy underneath SDK wrappers.
   Preserve all existing sandbox/env/tool review boundaries before Codex starts.
4. Include scheduled/manual/cascade and tenant autonomous leader producers.
   Explicitly add routine dispatch, middleware, progress/read routes, and tenant
   leader-loop files to the plan's file/AC list. Operator-global scope is an
   existing limitation to resolve for workspace routines, not a scope waiver.
5. Decouple usage provenance and native identity from legacy numeric cost and
   `session_id`; no unknown-cost-to-zero coercion for new engines.
6. The plan's blanket “owner-only RPCs” language must distinguish creating a
   conversation (authorized member) from changing a default (owner). The routine
   run FK must not require a terminal-only `routine_runs` row before dispatch.
7. Migration `107` explicitly documents that Supabase migrations are wrapped in
   a transaction and `CREATE INDEX CONCURRENTLY` is forbidden there. The plan's
   concurrent-index rollout needs a separate supported operation or bounded
   ordinary indexes, not that statement inside the migration.
8. A settings label saying only “new conversations” omits the user's routine
   decision; explain that changes also affect future routine runs. Active runs
   and existing conversations retain their engine.

## Verification notes

Read-only code searches covered runtime TS/TSX, SQL migrations and named tests.
Source revision was checked before artifact creation. The worktree temporarily
pointed to `main` during cleanup; the parent restored `feat-pluggable-web-agent-engines`
at `9c3c0cccc`, and `git diff 9c3c0cccc <temporary-main> -- apps/web-platform`
had no source differences. No source implementation was edited by this inventory.
Two discovery globs referred to nonexistent routine route/middleware paths;
`rg --files` located the actual `app/api/dashboard/routines/` routes and
`server/inngest/middleware/run-log.ts` before tracing them. Future probes should
discover paths before globbing. No live model calls or full suites were run.
