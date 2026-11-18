---
title: Remaining Codex Web acceptance criteria runtime audit
date: 2026-10-11
status: incomplete-readiness-audit
source_sha: 3c3ba13b29053071b690598325362b343299bc1a
pr: 9051
---

# Remaining acceptance criteria runtime audit

This source audit supports continuation of the [active plan](../../plans/2026-09-27-feat-codex-web-live-handler-wiring-plan.md#scope-and-implementation-sequence). It is not a full review, recovery qualification or acceptance-criteria completion. No application, provider, credential, database or routine execution occurred in this audit. Prior evidence remains source-bound. Keep the PR draft and auto-merge disarmed; keep Codex default-off and customer content blocked.

## Production composition gaps

Paths below are relative to `apps/web-platform/`.

| Source | Observed boundary | Required work |
| --- | --- | --- |
| `server/codex-conversation-runtime.ts` | Returns only `runtime: { userId }`, `dataClass: customer`, no accepted data classes and unverified/unknown transfer evidence. | Resolve an authorized, durable synthetic conversation identity and compose real credentials, launcher, transport, registry and server-owned egress evidence. |
| `server/agent-engine-reviewed-definitions.ts` | Codex new and existing runs disabled; qualifications empty. | Permit only explicitly authorized synthetic qualification execution through a scoped gate; preserve the ordinary catalog/default flag. Do not label an unfinished Web matrix verified. |
| `server/codex-app-server-launcher.ts`, `Dockerfile` | Launcher accepts a supplied command/environment; production Dockerfile has no Codex installation. | Establish pinned production binary provenance and isolated process configuration. Host installation is not runner provenance. |
| `server/codex-app-server-lifecycle-source.ts`, `server/codex-code-adapter.ts` | Lifecycle checks cancellation/lease expiry; `assertCodexEndpoint` has no production caller. | Enforce actual endpoint, exact synthetic scope, authorization expiry and generation at transport/request boundaries, including retries. |
| `server/codex-ws-events.ts`, `server/codex-app-server-session.ts` | Approval is displayed as a generic tool-use label; lower session layer can respond by request ID. | Preserve an actionable approval ID through an authenticated, conversation/run/attempt-scoped response path. Reject stale, foreign and duplicate responses. |

The real `server/ws-handler.ts` reads persisted bindings and routes Codex turns through `dispatchCodexChatTurn`, but calls the closed runtime above. Existing positive resume tests inject runtime/adapter implementations. They do not prove that production composition launches an authenticated App Server or permits a synthetic Web matrix.

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server) describes API-key authentication using `account/login/start` with `{ type: "apiKey", apiKey: ... }`. Implement and test the explicit protocol boundary; the launcher's test-only `CODEX_ACCESS_TOKEN` environment does not establish authentication. The coordinating session reports that host `codex-cli 0.162.1` help accepts `app-server --stdio`; this confirms host syntax only. No login ran.

The [official ChatGPT plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source) addresses open-source/local apps and directs paid or remotely hosted apps to an interest form. Documentation and technical compatibility do not establish permission for this hosted managed mode. Preserve its blocker; do not copy browser authentication or substitute an API key for managed credentials.

## Routine consumer inventory

| Producer | Trusted attribution | Current behavior |
| --- | --- | --- |
| `app/api/dashboard/routines/run/route.ts` | Authenticated user and database-resolved workspace | Persists binding, then calls `runRoutine`. |
| `server/routines-tools.ts` (`routine_run`) | Fresh tenant context and delegating principal | Persists binding, then calls `runRoutine`. |
| `app/api/internal/trigger-cron/route.ts` | System secret tier | Calls `runRoutine` without tenant engine binding. |
| `server/inngest/functions/cron-weekly-analytics.ts` | Trusted system cascade | Sends manual-trigger events directly, without tenant engine binding. |

`server/routines/run-routine.ts` rejects non-Claude persisted bindings before enqueue through `assertLegacyEngineBinding`. No production Inngest consumer reads `engine_run_id` or imports `dispatchCodexRoutineToEvents`. Agent-oriented cron consumers, including daily triage, bug fixer and content generator, invoke `spawnClaudeEval` with specialized tool, credential and output contracts. Remaining routines perform their existing monitoring, publication, deterministic or infrastructure operations.

No eligible consumer exists in this source. `test/codex-routine-dispatch.test.ts` uses a mocked daily-triage binding; the actual consumer is Claude-specific. Preserve the rejection and blocked routine AC as the plan requires. Completing it needs a named real consumer, product purpose and reviewed workspace/auth/tool/output contract first. Do not invent a fake producer or reinterpret a specialized cron. Producer rejection tests can strengthen this boundary but cannot complete routine execution qualification.

## Bounded RED/GREEN implementation sequence

1. **Synthetic identity and grant.** RED: missing/expired grant, wrong owner/workspace/source/mode, forged marker and ordinary-conversation reuse all deny before writes or credentials. GREEN: server-only configuration plus a durable, non-tenant-writable qualification marker and restricted transactional creation RPC. Existing `bind_agent_engine_run` takes workspace defaults, so do not change those defaults to create a qualification run. Cover marker RLS, erasure and atomic conversation/run creation.
2. **Fixed-prompt entry point.** RED: arbitrary text, attachments, unknown fields and duplicate creation/turn delivery fail or reconcile idempotently. GREEN: authenticated/CSRF-checked qualification route accepting only server-defined scenario and idempotency IDs; normal chat rejects arbitrary input for marked conversations. Preserve existing first-turn/resume ownership and history-transfer acknowledgment.
3. **Real API-key composition.** RED: valid synthetic identity reaches the actual credential/launcher/JSONL boundary; missing/revoked credentials deny without Claude or managed fallback. GREEN: resolve runtime by user, conversation and binding; use `createCodexApiKeyProviderForUser`, the real launcher, transport and adapter. Pin/install the production binary and implement documented login in a task-owned isolated home/workdir with minimal environment. Do not substitute an optional empty runtime or mock adapter for the positive test.
4. **Request-time policy.** RED: expiry or revocation during acquisition, denied actual endpoint, stale generation and retry after a switch prevent new provider requests. GREEN: revalidate server-owned scope and endpoint at launch and lifecycle request boundaries; define bounded cancellation/cleanup after grant expiry. Keep customer selection and global flag unchanged.
5. **Actionable lifecycle.** RED: real provider approval request reaches the client with attributable ID; foreign/stale/duplicate decisions deny, and accepted decision reaches the original pending RPC response. GREEN: authenticated response wiring plus event/usage/terminal/cancel/replay/deletion tests. Do not infer parity from the current generic approval label.
6. **Qualification evidence.** After current-source/full-production recovery and authenticated screenshots, run only separately permitted mode-specific deployed Web matrices. Record exact served SHA, account/workspace, authorization, timestamps, rows/WAL and limitations. Obtain attributable CLO dispositions before evaluating a cohort. Managed hosted permission and actual account sharing/retention/regions remain unresolved.

Reuse `test/server/ws-handler-codex-production-boundary.test.ts`, `test/ws-resume-by-context-path.test.ts`, `test/ws-handler-context-path-23505.test.ts`, `test/codex-web-runtime.test.ts`, `test/codex-credential-provider.test.ts`, `test/codex-app-server-launcher.test.ts` and `test/codex-conversation-dispatch.test.ts`. Add route/config/marker-RPC tests. Keep route, handler, resolver, registry, credential provider, transport and adapter real; isolate external SQL and child-process streams at their boundaries. Local composition tests do not replace authenticated deployed evidence.

Discovery errors were limited to oversized combined reads and guessed absent qualification/config/test filenames. `rg --files` corrected the path guesses before any edit. No prior record was changed by this audit.
