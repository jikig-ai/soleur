---
title: "Complete Codex web integration and controlled rollout"
date: 2026-09-21
branch: feat-one-shot-codex-web-rollout
status: in-progress
---

# Complete Codex web integration and controlled rollout

## Overview

Connect the existing Codex App Server adapter to real conversation and routine execution, qualify each authorization mode with synthetic or explicitly redacted data, and preserve the customer-content block until the CLO records an applicable decision. Verify the deployed build and internal use before declaring rollout complete.

## Research Insights

### Premise validation

PR #8447 is MERGED at `7e8dfab4dfd9fa8dbf656260a67216c6487630a7` (verified with `gh pr view`). Current `origin/main` is `b53173a04e813ca11bb47b14ea4e89e129343064`. The prior qualification record is archived and marks both modes synthetic-only. `agent-engine-reviewed-definitions.ts` has Codex disabled for both new and existing runs, with no qualification entries. `agent-engine-adapter-composition.ts` can construct Codex only when transport and auth are supplied. Research found no production call to `composeReviewedEngineFactories`, `createCodexAppServerLifecycleSource`, `dispatchConversationEngineRun`, or `dispatchRoutineEngineRun`; these remain definition/test seams. The first 500 open GitHub issues contain no title matching Codex/OpenAI/engine; this does not prove no related issue exists by body or label.

Applicable institutional learnings: `knowledge-base/project/learnings/integration-issues/2026-09-15-codex-replay-translation-fails-closed-with-bounded-telemetry.md` requires bounded replay-drop telemetry and fail-closed malformed history; `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` requires attachment, context, stream-end and presentation tracing across a runner cutover; `knowledge-base/project/learnings/2026-06-18-never-assert-live-prod-state-from-a-migration-header-snapshot.md` and `knowledge-base/project/learnings/best-practices/2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md` require live flag and segment inspection. The research agent's prescribed `critical-patterns.md` path did not exist in this checkout; no contents were inferred.

### Research reconciliation — spec vs. codebase

| Requested behavior | Current code | Plan response |
|---|---|---|
| Real Codex conversation and routine execution | Registry, adapter, dispatch and binding seams exist, but their production execution call sites were not found | Trace real handlers, write integration tests, then connect both paths |
| Default-off controlled availability | Reviewed definition is disabled with no qualifications; settings route rejects disabled definitions | Keep customer disabled and represent internal eligibility only after evidence and flag checks |
| Credential and data policy | Auth boundary and fail-closed egress policy exist but production composition is absent | Select an account-scoped lease, bind auth mode, recheck egress at execution and lifecycle boundaries |

### Property list

- Real conversation and routine requests must preserve one engine and authorization mode across retries, events and lifecycle operations.
- No customer content may reach Codex until qualification and an applicable CLO disposition exist.
- Internal qualification must be bounded, synthetic or explicitly redacted, and traceable to a deployed build.
- Rollout state and postmerge health must be directly observable.

### Cut list

- A second engine selector → engine binding across retries → reuse the reviewed registry, dispatch and persisted binding mechanisms.
- A second egress approval channel → customer-content control → reuse `agent-engine-data-egress-policy.ts`.
- Alternate provider retry → run continuity → rejected because the existing bound engine must remain authoritative.

## User-Brand Impact

Threshold: single-user incident. A mistaken credential selection, egress classification, or provider fallback could expose one user's repository content under the wrong agreement or retain it unexpectedly. Require CPO and user-impact review before shipping the production path. Keep customer-content execution blocked until CLO disposition for the exact auth mode and account.

## Implementation Phases

1. **Inspect current state.** Read production settings and execution call sites, Flagsmith feature state, credential stores, current deploy SHA, main CI and release/deploy runs. Verify the exact auth/account path and any existing related issues by body/labels. Record the baseline in this plan or a linked qualification record.
2. **Write failing integration tests.** Start with one real-path conversation test and one real-path routine test; retain focused adapter/dispatch tests for events, usage, attachments, approvals, cancel/reconcile/restart, revocation, provider failures, no fallback, and denied egress. Cover expected 4xx and silent-fallback observability. Test the flag-off and revoked-credential transitions for an existing bound run.
3. **Connect the production path.** First map real create, resume, event, approval, cancel, reconcile, restart, attachment, usage, and scheduled-routine producers, Inngest execution consumers, presentation/replay consumers, and persistence write sites; change only the gaps. `runRoutine()` currently emits an Inngest event after binding, so connecting that producer alone cannot execute Codex. Gate system-triggered routine dispatch on a dedicated service identity with tenant authorization, per ADR-233. Specify which event payloads are persisted and replayable versus transient and verify the visible stream, approval and usage contract end to end; `AgentEnginePersistenceRepository.appendEvent()` currently retains only lifecycle metadata. Complete ADR-233's pending separation of conversation binding from turn attempts, protected recovery checkpoints, durable sequence allocation and lifecycle transition persistence before claiming restart or reconciliation support; keep native handles, cursors and usage provenance out of the member-readable event ledger. Wire the reviewed Codex transport and mode-stable credential provider into those call sites. The current SQL binder records `adapter_version = 'registry-pending'`; resolve the reviewed adapter version and persist it atomically with engine/auth/session binding before provider invocation, including concurrent retry behavior. Require server-owned egress evidence in the Codex invocation boundary immediately before every provider invocation and attachment transfer; the dispatch API currently accepts optional `egress`, so caller omission must not bypass policy. Route lifecycle actions through the persisted engine. After flag-off or credential revocation, an existing run may continue only if current policy permits; otherwise it fails closed with durable terminal state and never switches provider. Amend ADR-233 if the binding/checkpoint design changes.
4. **Security and GDPR.** Run `soleur:gdpr-gate`, inspect logs and telemetry for prompt/credential leakage, test tenant isolation and provider-host allowlist, verify erasure response and local deletion. Cite the applicable agreement and transfer evidence for each auth mode.
5. **Live qualification.** First identify a deployed internal or staging build and record its SHA, account and tenant; if none is available before merge, label premerge exercises local-only and perform the deployed-build qualification after an internal deploy. Run a bounded internal scenario matrix separately for API-key and managed ChatGPT mode where account access permits, using synthesized or expressly redacted data and no customer repository. Record actual commands/build/tenant, timestamps, observed events and usage, attachments, approvals, cancel/reconcile, deletion response, failures and limitations in an active qualification record. Missing access is a named gap, never a synthetic PASS recast as live.
6. **CLO packet and flag.** Prepare mode-specific agreement/account, location/transfer, retention, erasure, billing, ownership, admin-control and residual-risk evidence with a specific disposition request. Verify or create `codex-engine` in Flagsmith with default false. Before changing the flag, record the exact internal tenant/account and the maximum users, runs, duration, owner, rollback trigger and smoke success criteria in the active qualification record. Server-side selection and run creation must intersect reviewed-definition enablement, mode/workflow/data-class qualification, current credential lease, flag cohort and egress decision. Internal and customer eligibility are distinct for each auth mode. Enable only the bounded internal cohort after its qualification passes and internal data use is authorized. Do not enable customer cohorts without the actual CLO disposition for that auth mode. Settings must explain eligible, unavailable-credential, qualification-pending, approval-pending and existing-bound-run-after-flag-off states; update the existing `.pen` first if these require a new UI state.
7. **Review and ship.** Run focused and full required tests, security review, QA including UI screenshots and `.pen` wireframe if settings UI changes, preflight, PR, merge, main CI, release build, workflow-run deploy job, `/health` expected build SHA and deployed app smoke. Investigate red gates. Report implementation, live qualification, CLO approval, internal enablement, customer enablement and deployment separately.

## Files to Edit

- `apps/web-platform/server/agent-engine-reviewed-definitions.ts` — only when qualification and rollout policy can be represented without enabling customer content.
- `apps/web-platform/server/agent-engine-adapter-composition.ts`, `apps/web-platform/server/ws-handler.ts`, `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/server/routines/run-routine.ts`, `apps/web-platform/app/api/dashboard/routines/run/route.ts`, and the discovered Inngest consumers — production transport/auth wiring and bind-before-dispatch. `ws-handler.ts › createConversation()` and its chat branches currently route to the legacy runner or Soleur Go; `runRoutine()` currently sends Inngest after an optional binding callback. Trace scheduled and agent-triggered routine producers and consumers before implementing.
- `apps/web-platform/server/agent-engine-persistence.ts`, `apps/web-platform/server/agent-engine-dispatch.ts` and their call sites — immutable binding and lifecycle where current implementation proves a gap.
- `apps/web-platform/app/api/dashboard/settings/agent-engine/route.ts` and `apps/web-platform/components/settings/agent-engine-settings.tsx` — only if settings state requires a UI change.
- `apps/web-platform/test/agent-engine-*.test.ts`, `apps/web-platform/test/codex-*.test.ts` and relevant handler integration tests — real-path and regression coverage.
- `knowledge-base/legal/data-processing-agreements/openai.md` and a current qualification record under this feature's spec directory — actual evidence and decision packet.

## Design Reference

Existing committed workspace-engine selection wireframe: `knowledge-base/product/design/agent-engine-selection/workspace-default-engine.pen`. If Codex adds a new UI state beyond this design, update the `.pen` before implementing that state.

## Open Code-Review Overlap

None found by a bounded query of the first 200 open `code-review` issues for the planned engine, Codex, conversation-routing and routine-run terms. This query does not establish that no differently worded issue overlaps.

## Observability

```yaml
liveness_signal:
  what: "deployed /health response includes the expected build SHA; authenticated internal synthetic run emits a terminal engine status"
  cadence: "after each deploy and during bounded internal rollout"
  alert_target: "web-platform engineering on call"
  configured_in: "apps/web-platform health route and engine lifecycle telemetry"
error_reporting:
  destination: "Sentry for server-side failures; GitHub Actions for build and deploy failures"
  fail_loud: "provider failure, denied egress or unavailable credential terminates the bound run and records a bounded error code"
failure_modes:
  - mode: "credential unavailable, revoked, or wrong auth mode"
    detection: "engine failure code in Sentry and bounded lifecycle event"
    alert_route: "web-platform engineering on call"
  - mode: "denied egress, stream/approval/cancel/reconcile failure, or erasure acknowledgement missing"
    detection: "Sentry event plus terminal or unresolved bound-run status"
    alert_route: "web-platform engineering on call"
  - mode: "release, deploy or health SHA mismatch"
    detection: "GitHub Actions conclusion and direct /health build SHA probe"
    alert_route: "release owner"
logs:
  where: "bounded engine lifecycle telemetry and Sentry without prompt, credential or customer content"
  retention: "existing web-platform logging and Sentry retention policy; verify before rollout"
discoverability_test:
  command: "curl -fsS https://app.soleur.ai/health"
  expected_output: "build_sha"
```

The fast preflight probe checks that the public response includes `build_sha`. Postmerge verification must parse `.build_sha` and compare it with the actual merged main commit; the SHA is not knowable while this plan is written. `/health` is liveness-only, so the authenticated synthetic smoke separately verifies the execution path. The active qualification record owns live observations and cohort bounds; the CLO packet owns vendor evidence and the requested decision. This plan links those records instead of copying mutable status.

## Encryption Posture

```yaml
at_rest:
  - store: "existing web-platform engine binding and conversation records in Supabase"
    mechanism: "reuse the existing Supabase persistence path; no new at-rest encryption claim is introduced by this plan"
    evidence: "apps/web-platform/server/agent-engine-persistence.ts and the existing Supabase storage posture; verify the live tenant configuration before customer rollout"
    defends_against: "the existing provider-side disk access protections documented for the tenant"
    does_not_defend: "provider administrator access, a compromised application credential, or OpenAI's independent retained copy"
    disclosed_as: "no new encryption claim; vendor retention and erasure limits go to the CLO packet"
    live_verification: "confirm tenant encryption setting and agreement evidence before customer rollout"
in_transit:
  - connection: "web-platform server -> Codex App Server process -> OpenAI endpoint"
    tls: "HTTPS to an exact allowed OpenAI host; local process leg uses stdio"
    cert_verification: "on for remote HTTPS; inspect actual Codex transport before rollout"
    does_not_defend: "credential misuse at either process, provider-side retention, or an authorized request containing excessive data"
    disclosed_as: "mode-specific vendor packet and product account-boundary disclosure"
```

## Acceptance Criteria

- [ ] Current main and production baseline recorded; no archived ledger treated as live truth.
- [ ] Conversation and routine integration tests exercise the real production composition and binding path, including negative authorization and no-fallback cases.
- [ ] API-key and managed-mode live results are separately recorded, or each unavailable mode has its exact access blocker.
- [ ] CLO packet identifies mode-specific evidence and requests a disposition; no approval is inferred.
- [ ] Flagsmith `codex-engine` exists with default false; customer cohorts remain off until their mode's qualification and CLO approval pass.
- [ ] Attempt a bounded internal enablement only after the required gates. Record the exact flag/cohort mutation and smoke evidence, or the exact gate that blocked the mutation; never treat a blocked attempt as enabled.
- [ ] PR is merged and GitHub reports MERGED; main CI, release build, workflow-run deploy job, expected `/health` SHA and live app smoke are directly verified.

## Planning Gate Status

Repo and learnings research completed. The available plan-review pass identified a binding-version defect: migration 138 wrote `adapter_version='registry-pending'` even when the selected engine was Codex, which would make a qualified `codex-v1` selection fail closed. The migration now derives `codex-v1` and `claude-code-v1` from the persisted engine id, while unknown engines remain `registry-pending` and fail qualification. Focused tests pass (21 files, 196 tests).

The required full plan-review panel (five engineering specialists plus relevant CPO/UX/CTO lenses) did not complete because the review agent hit its usage limit; this is recorded as incomplete coverage, not as a green review. Live Flagsmith evidence is now recorded: feature `codex-engine` exists with `default_enabled=false` and no dev/prod segment overrides. Production `/health` and CI evidence are recorded in the qualification record; the deployed SHA remains older than the merged adapter. Public OpenAI evidence and a concrete CLO packet are committed, but the actual account/agreement, tenant region, retention settings, provider erasure behavior, billing owner, and administrator controls remain unresolved. The plan stays `status: in-progress`; it is not implementation approval.
