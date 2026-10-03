---
title: "feat: Wire Codex into live Web handlers"
type: feat
date: 2026-09-27
slug: feat-codex-web-live-handler-wiring
branch: feat-one-shot-codex-web-live-paths
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Wire Codex into live Web handlers

## Overview

Connect the existing reviewed Codex Web adapter to real conversation and routine execution, starting with failing handler-path tests. Preserve the persisted engine binding and server-owned egress checks, while allowing a workspace owner to change the Codex credential mode for existing conversations as well as new ones. A mode change must atomically update Codex conversation bindings and discard provider recovery state from the previous account. Fail without provider fallback. Qualify API-key and managed modes separately with synthetic workspaces before considering flag cohorts or customer content.

## Research Insights

### Premise validation and reconciliation

`gh pr view 8980` reported MERGED at `1f919b01c7a1ab9c056af6aa19369cd3fd48599d`. This worktree begins at `51909c6fb4a459c0c1a6bf49347150c3d2b43b5f`. The current source confirms the user’s remaining gap: `ws-handler.ts` and `routines/run-routine.ts` still call `assertLegacyEngineBinding`; the Codex conversation and routine bridges have direct tests but no real handler consumer. The existing [rollout plan](2026-09-21-feat-codex-web-controlled-rollout-plan.md), [qualification record](../specs/feat-one-shot-codex-web-rollout/codex-qualification-record.md), and [CLO packet](../specs/feat-one-shot-codex-web-rollout/clo-decision-packet.md) remain the policy/evidence sources. Local CLI and App Server smokes are narrower than authenticated Web qualification.

This branch has no `spec.md` with a valid `lane:`; planning defaults to `cross-domain`.

### Property list and cut list

- A conversation or eligible routine uses its persisted engine and authorization mode through dispatch, retry, event replay, cancellation and recovery.
- Every Codex provider or attachment request has server-owned egress evidence and a currently permitted credential lease; rejected or revoked runs fail closed without Claude or alternate-mode fallback.
- Each authorization mode has its own synthetic Web evidence and attributable CLO disposition before any matching flag cohort is considered.
- Cut a new engine registry, second selector and second egress approval path: `agent-engine-reviewed-definitions.ts`, `agent-engine-dispatch.ts`, and `agent-engine-data-egress-policy.ts` already provide these mechanisms. Adapt their real call sites.

### Relevant learnings

- [Runtime credentials are inputs](../learnings/workflow-patterns/2026-09-22-ai-harness-credentials-are-runtime-inputs.md): a missing global API key does not block handler implementation; Web settings own the API-key lease. Managed authorization remains a separate mode.
- [Binding read-path audit](../learnings/2026-06-14-verify-the-read-paths-source-field-not-the-setter-when-fixing-a-binding.md): test the actual resolver and consumer, including duplicate-create and resume paths.
- [Codex replay](../learnings/integration-issues/2026-09-15-codex-replay-translation-fails-closed-with-bounded-telemetry.md): invalid provider history fails closed, and unsupported items receive bounded, content-free telemetry.
- [WebSocket auth race](../learnings/2026-03-20-websocket-first-message-auth-toctou-race.md) and [stream snapshots](../learnings/2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md): recheck socket state after awaited authorization and preserve the client’s cumulative partial/final frame contract.

### Implementation realism

`AgentEnginePersistenceRepository.appendEvent()` currently stores lifecycle metadata only and replaces provider event IDs with a sequence-derived value; it does not establish durable text, approval, usage or native resume state. `codex-ws-events.ts` renders an approval as a generic `tool_use` frame without an actionable request ID. ADR-233 explicitly reserves native handles and recovery cursors for protected checkpoints, separate from the member-readable lifecycle ledger. Plan and tests must keep these boundaries distinct. The reviewed Codex definition is currently disabled for both new and existing runs with no qualifications; a synthetic-only, exact-workspace/deployment qualification path must be established without enabling customer data. A flag flip alone cannot satisfy the registry’s mode/workflow/data-class/capability qualification checks.

## User-Brand Impact

- **If this lands broken, the user experiences:** a conversation that silently switches to Claude, keeps using Managed after an owner selected API Key, loses context when switching provider accounts, loses approval or usage events, or a routine recorded as Codex-bound while executing legacy cron code. If the bounded tab cache fills or expires, a history-transfer draft remains visibly unsent only in the mounted chat and may be lost after navigation or reload; the client warns the member to copy it before leaving, and a regression pins the capacity warning. An unsupported `default_auth_mode` on a Codex-default workspace can abort migration 145's constrained backfill and block the production release; a downgrade that drops `codex_auth_mode` can also lose an owner's selected Codex mode.
- **If this leaks or misroutes, the user's data is exposed via:** a Codex request using another workspace's credential, an unapproved endpoint, or a data class without the mode's legal basis. An explicit owner auth-mode change affects existing Codex conversation bindings in that workspace. Each conversation continues to use the credential lease belonging to the user who resumes it; the owner's key is never shared with members. If that user lacks a valid key, resume fails closed without Managed fallback. Claude bindings and routine runs remain unchanged. The next turn after a switch reconstructs context from that conversation's tenant-scoped stored messages; it must not reuse native provider state from the old account. The owner confirms workspace scope and affected-conversation count before saving. Each affected member separately acknowledges the provider history transfer before their transcript is replayed; no transcript or provider request is sent before that acknowledgment.
- **Brand-survival threshold:** `single-user incident`. CPO plan sign-off and the review-time user-impact reviewer are required before shipment; CTO reviews the launcher, egress and credential contract. CLO approval is mode-specific and applies to customer data, not the technical implementation.

## Scope and implementation sequence

1. **Map the real paths.** Enumerate all conversation creation and resume branches in `ws-handler.ts`, first and later chat turns, every `runRoutine()` producer, the `*.manual-trigger` Inngest consumers, scheduled system sends, and lifecycle/replay/persistence read and write sites. Name which routines genuinely execute agent work; specialized cron handlers cannot become Codex runs merely because the producer attaches `engine_run_id`. Preserve existing cron behavior and reject a Codex binding where no Codex executor exists. Record the authenticated workspace and user identity each path can provide.
2. **Write failing production-path tests first.** Exercise actual WebSocket first turn, duplicate create, second turn, resume, restart and disconnect/cancel. After Phase 1 names the first eligible routine fnId and consumer, exercise its dashboard/agent producer and actual Inngest consumer; if none is eligible, mark routine routing blocked and retain the current fail-closed guard. Prove the selected persisted engine/auth mode reaches the Codex transport, and denied egress, missing/wrong/revoked credentials, flag-off, provider error and malformed replay do not invoke Claude or another auth mode. Assert terminal status, bounded Sentry signal, event persistence and client frames. A direct bridge unit test alone does not satisfy this phase.
3. **Make the binding durable for multiple turns before routing them.** Implement ADR-233's pending separation of conversation binding from turn attempts, durable sequence allocation, lifecycle transition persistence, and protected checkpoints for native handles/cursors/usage provenance. The second-turn and restart tests must fail before the storage change and pass after it; the current per-dispatch sequence reset plus `engine-event-${sequence}` will collide. Keep member-readable lifecycle events content-free and maintain erasure/DSAR coverage for protected recovery state. Then branch from the persisted binding before the first or resumed turn can reach `dispatchSoleurGoForConversation` or `sendUserMessage`; retain the legacy path for legacy/Claude bindings. Reuse `codex-conversation-dispatch.ts` rather than adding another dispatch layer. Compose the reviewed Codex runtime from authenticated Web settings and the approved App Server launcher. Keep the Codex engine ID stable across retries. An explicit auth-mode control change (not an engine-dropdown change or automatic supported-mode adjustment) passes distinct intent through the existing owner RPC. In the same database transaction, update only existing Codex conversation rows in that workspace, increment their auth-mode generation, update the workspace default, and delete protected provider checkpoints. The transaction returns the affected conversation count; failures leave settings, bindings and checkpoints unchanged, and retries are idempotent. Bind each turn attempt to the generation it read. Check that generation at the provider request boundary and in every event, terminal-state and checkpoint write. A request accepted before the settings transaction may finish under its original mode and its final output may be stored and shown for that attempt; reject stale retries and checkpoint writes, and ensure old-attempt events cannot mutate the new binding. The next turn uses the new mode and tenant-scoped `messages` history read through the authenticated member's RLS context. Distinguish a legitimate empty transcript from a read/authorization error; errors fail closed without dispatch. Before the first replay after a generation change, each resuming member must acknowledge that their stored history will be sent under the selected provider account. Never reuse native provider state from the previous account. Attachments remain excluded until qualified, and missing/revoked credentials fail with an actionable, content-free error and no fallback. Each API-key lease belongs to the user resuming the conversation; never substitute the owner's credential for another member. Derive the actual target endpoint and attachment data class from server-owned runtime state, then check them at the transport/launcher request boundary as well as at dispatch; caller-supplied evidence alone is insufficient. Route event/approval/usage/replay/cancel/reconcile through persisted run identity. Supply an actionable approval request ID and response route before qualifying approval parity.
4. **Wire eligible routine execution.** Treat `runRoutine()` as an event producer, not the executor. Phase 1 must name the first eligible fnId, its exact `*.manual-trigger` Inngest consumer and its auth/workspace contract before this phase can start. If no existing routine qualifies, keep Codex routine binding rejected and record a blocked AC rather than reinterpreting a specialized cron body. For a qualifying routine, reuse `codex-routine-dispatch.ts` at its consumer; keep unrelated cron functions on their existing execution path. Preserve confirmation policy and actor attribution. The consumer re-reads binding, credential and egress policy before invoking Codex; idempotently claims duplicate deliveries, reconciles enqueue failure into a durable failed state, and never executes the legacy cron body as fallback. Test scheduled and internal producer behavior explicitly.
5. **Security, privacy and review.** Run `soleur:gdpr-gate` on the plan and implementation; inspect tenant isolation, credential/log redaction, endpoint allowlist, transfer and erasure behavior. CPO conditionally accepts the workspace-wide auth switch if its scope, provider billing and history transfer are disclosed before applying it; CTO approval is conditional on transactional rebinding, generation fencing and real transport evidence. Use a native engine dropdown. Before the setting commits, show the owner the number of affected Codex conversations and the provider/billing effect. On the first resume after the generation changes, each member separately acknowledges the history transfer. Update the existing `.pen` wireframe before UI implementation and run screenshot QA. Then run independent code review, QA, preflight and focused/full applicable tests.
6. **Qualify each mode.** Keep the global Codex flag and customer conversation selection disabled. Add a separate, expiring synthetic qualification path allowlisted to the authorized test workspace and owner identity from trusted server configuration. That path creates and resumes only server-marked synthetic conversations with fixed synthetic prompts, no attachments, and no route to ordinary user chats; the actual WebSocket transport revalidates workspace, user, conversation data class, mode qualification and expiry at request time. It must not enable ordinary workspace conversation traffic while qualification is active. On a deployed build with exact SHA, run bounded synthetic Web first/continuation, events/usage, attachment denial, approval, cancel/reconcile/replay, revocation/error/denied-egress/no-fallback, mode-switch/resume and deletion probes separately for API-key and managed ChatGPT. Record workspace/account, authorization source, commands, timestamps, affected rows and WAL measurements, observed results and limitations in the active qualification record. If no authorized synthetic workspace credential or managed authorization is available, record the exact mode blocker and leave its qualification pending; never substitute a local transport smoke for Web evidence.
7. **Disposition and rollout gate.** Refresh the CLO packet for each mode with account/agreement, data classes, region/transfer, retention/erasure, billing, ownership/admin controls and decision date. Keep `codex-engine` default false. Only after the mode’s Web qualification and applicable CLO disposition may a bounded internal cohort be evaluated; customer cohorts require explicit customer-content approval. Record any actual flag mutation and smoke result separately from code deployment. Verify merge, main CI, release/deploy, served SHA and authenticated synthetic path before declaring completion.

## Files to Edit

- `apps/web-platform/server/ws-handler.ts` and its real handler tests — binding-first conversation routing, including duplicate create and resume. Keep `agent-engine-route-guard.ts` unchanged unless a failing real-path test proves it needs a new primitive.
- `apps/web-platform/server/routines/run-routine.ts`, eligible `apps/web-platform/server/inngest/functions/` consumers, `apps/web-platform/app/api/dashboard/routines/run/route.ts`, `apps/web-platform/server/routines-tools.ts`, and tests — producer/consumer contract and trusted attribution.
- `apps/web-platform/server/agent-engine-persistence.ts`, its SQL migration and lifecycle tests — turn attempts, durable sequence, protected recovery and erasure/DSAR path from ADR-233.
- `apps/web-platform/server/codex-web-runtime.ts`, `apps/web-platform/server/agent-engine-dispatch.ts`, `apps/web-platform/server/agent-engine-data-egress-policy.ts`, transport/launcher and tests only where the mapped real paths expose a gap. Keep the existing conversation and routine dispatch bridges unless a failing real-path test shows a missing capability.
- `knowledge-base/project/specs/feat-one-shot-codex-web-rollout/codex-qualification-record.md` and `clo-decision-packet.md` for actual mode evidence and disposition status.

## Design reference

Existing engine selection wireframe: `knowledge-base/product/design/agent-engine-selection/workspace-default-engine.pen`. It must show the dropdown and explain that changing Codex auth mode affects existing Codex conversations and that each resuming user uses their own provider credentials before settings UI implementation.

## Domain Review

### Product/UX Gate

**CPO decision:** Conditional plan sign-off for the original scope on 2026-09-27 did not cover the auth-mode switch. Updated CPO disposition on 2026-09-28 conditionally accepts changing existing Codex chats if the setting clearly discloses workspace-wide scope and potential history transfer before applying. The plan requires owner confirmation and separate member acknowledgment before replay; each member uses their own provider credential. Product maturity is building; business validation is PIVOT and Codex support aligns with delivery-agnostic positioning. Revalidate delivery and harness assumptions against current positioning. Workspace-wide Codex auth-mode rebinding is currently owner-dashboard/API only: the live Concierge has no equivalent owner-confirmed tool, so agents cannot perform this action and the UI/API access does not establish agent parity. Keep agent access unavailable until the platform-tool allowlist can enforce the same owner identity, workspace scope, affected-conversation disclosure and confirmation. Verify test workspace identity, credential source and synthetic-only boundary before a live request. An absent eligible routine consumer keeps routine Codex binding closed. Mode-specific Web evidence and CLO disposition precede any matching cohort.

### Engineering Gate

**CTO decision:** Conditional technical sign-off on the original scope on 2026-09-27 did not cover auth-mode rebinding or concurrent-turn fencing. Updated CTO disposition on 2026-09-28 is conditional on a transactional owner RPC, generation checks at transport and persistence boundaries, per-user credential isolation, tenant-scoped transcript replay and tested egress composition before qualification. Measure affected conversation/checkpoint rows per switch and lifecycle/checkpoint write counts plus `pg_stat_wal.wal_bytes` around representative synthetic runs; record results in the qualification record before cohort review. The WebSocket route reads the persisted binding and never falls through to Claude on lookup failure. Name an eligible Inngest consumer before routine wiring; otherwise keep routine binding closed. Actionable approval routing precedes approval parity. Before release, guard migration 145's copy from unconstrained `default_auth_mode` values into the constrained Codex mode: an automated pre-migration check must reject unsupported values, and the downgrade's loss of `codex_auth_mode` is unsupported after owner changes unless a recoverable snapshot and restoration procedure exist. Estimate remains large.

## Observability

```yaml
liveness_signal:
  what: "deployed /health build_sha and terminal synthetic engine run status"
  cadence: "after deploy and each bounded qualification run"
  alert_target: "web-platform engineering on call"
  configured_in: "apps/web-platform health route and agent-engine-observability.ts"
error_reporting:
  destination: "Sentry web-platform and Inngest run status"
  fail_loud: "denied egress, binding mismatch, unavailable credential and provider errors produce bounded error codes and terminal run status"
failure_modes:
  - mode: "wrong persisted engine or auth mode, revoked credential, or tenant mismatch"
    detection: "engine Sentry error and failed bound-run lifecycle"
    alert_route: "web-platform engineering on call"
  - mode: "routine enqueued but no matching Codex consumer or terminal event"
    detection: "Inngest run failure plus missing terminal bound-run check in qualification"
    alert_route: "web-platform engineering on call"
  - mode: "denied provider egress, replay/approval/usage failure"
    detection: "bounded engine observability event and Sentry capture"
    alert_route: "web-platform engineering on call"
logs:
  where: "content-free engine lifecycle telemetry, Sentry and Inngest run metadata"
  retention: "existing web-platform and Sentry policy; verify exact retention before cohort rollout"
discoverability_test:
  command: "curl -fsS https://app.soleur.ai/health"
  expected_output: "build_sha"
```

The public probe establishes deployment liveness only. Authenticated synthetic runs establish execution; the qualification record must keep those observations distinct.

## Encryption Posture

```yaml
at_rest:
  - store: "Supabase Postgres agent_engine_runs and service-role-only protected recovery checkpoints (migration 143)"
    mechanism: "Supabase platform database encryption, as declared for the existing service"
    evidence: "knowledge-base/engineering/architecture/nfr-register.md §Supabase PostgreSQL; knowledge-base/legal/data-processing-agreement-template.md §Encryption at rest"
    defends_against: "raw storage-media disclosure under the provider's managed database posture"
    does_not_defend: "a compromised service credential, a member-readable RLS mistake, or provider administrator access"
    disclosed_as: "knowledge-base/legal/data-processing-agreement-template.md §Encryption at rest"
    live_verification: "confirm actual production project encryption posture and checkpoint access grants before migration or cohort enablement"
  - store: "Web settings user API-key lease"
    mechanism: "application AES-256-GCM using the existing per-user BYOK encryption path"
    evidence: "knowledge-base/engineering/architecture/decisions/ADR-004-byok-encryption-model.md §Decision; apps/web-platform/server/codex-credential-provider.ts"
    defends_against: "raw credential disclosure from a database-only snapshot"
    does_not_defend: "compromised application master key or a process authorized to use the lease"
    disclosed_as: "knowledge-base/legal/data-processing-agreement-template.md §Encryption at rest"
    live_verification: "verify the actual workspace/user lease and revoked-credential test before each mode's qualification"
in_transit:
  - connection: "Web server to allowed OpenAI endpoint through local Codex App Server stdio"
    enforced_at: "apps/web-platform/server/agent-engine-data-egress-policy.ts › normalizeEndpoint(); transport/launcher request guard to be added"
    tls: "HTTPS remote leg; local stdio process leg"
    cert_verification: "on for remote HTTPS; verify the actual launcher target and TLS behavior before qualification"
    does_not_defend: "overbroad authorized payloads, wrong account selection or provider-side retention"
    disclosed_as: "mode-specific CLO packet; no stronger claim until live evidence exists"
```

## Test Scenarios

- Given an authenticated synthetic workspace with a Codex default and authorized mode, when a real first WebSocket turn and continuation run, then both use the same persisted Codex binding and emit stable frames, terminal status and usage.
- Given duplicate creation, resume, disconnect or restart, when the bound conversation is recovered, then binding and event sequence remain durable; a missing nonlegacy run fails closed.
- Given an eligible manual routine, when its event reaches Inngest, then the consumer re-reads the bound run and executes Codex; a noneligible cron never claims Codex execution.
- Given revoked/mismatched credentials, denied egress, provider failure, or flag-off, when execution resumes, then no Claude or alternate-mode request occurs and the run records a terminal failure or approved policy state.
- Given an explicit owner auth-mode change, when a Codex conversation resumes, then only Codex conversation rows in that workspace use the new mode; routine and Claude bindings remain unchanged, the resumer's own credential is used, and the tenant-scoped stored transcript is restored without old-account native handles.
- Given a mode switch races with a turn, then a provider request accepted before the switch may finish and its result is shown as that attempt's result, while stale retries and checkpoint writes are fenced by auth-mode generation; later turns use the new mode or fail closed if that user's credential is unavailable.
- Given a member resumes a conversation after its auth-mode generation changes, when the member has not acknowledged the history-transfer notice, then no transcript or provider request is sent until the member acknowledges it.
- Given Codex is disabled for customer traffic, when the configured exact-workspace qualification path runs, then only server-marked synthetic conversations can reach the transport; ordinary chats, arbitrary prompts and attachments remain blocked.
- Given a member resumes a conversation after its auth-mode generation changes, when the member has not acknowledged the history-transfer notice, then no transcript or provider request is sent until the member acknowledges it.
- Given Codex is disabled for customer traffic, when the configured exact-workspace qualification path runs, then only server-marked synthetic conversations can reach the transport; ordinary chats, arbitrary prompts and attachments remain blocked.

## Acceptance Criteria

- [ ] Real WebSocket and eligible routine/Inngest tests fail before implementation and pass after, exercising production composition rather than only bridge mocks.
- [ ] All mapped conversation and routine paths preserve persisted engine binding, tenant identity, server-owned egress policy and no provider fallback; an explicit owner auth-mode change atomically updates only existing Codex conversation bindings and fenced resumed turns use that persisted mode and their tenant-scoped transcript after member acknowledgment.
- [ ] Events, usage, approvals, attachments, cancellation, reconciliation and replay have tested persistence and presentation behavior; each explicit qualification gap blocks enablement for the affected mode or capability.
- [ ] API-key and managed modes have separate authenticated synthetic Web evidence on a served build SHA through the exact-workspace qualification path, or each has an exact access blocker; ordinary customer chats remain excluded and local CLI/App Server smokes are labeled separately.
- [ ] Mode-specific CLO disposition is recorded before any matching cohort is evaluated; `codex-engine` remains default false and customer processing blocked absent its mode approval.
- [ ] CPO, CTO, GDPR, review, QA and preflight gates complete; PR merges and main CI, release/deploy and served health SHA are verified.
