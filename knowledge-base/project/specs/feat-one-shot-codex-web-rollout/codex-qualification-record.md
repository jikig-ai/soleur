---
title: "Codex web engine qualification record"
date: 2026-09-23
status: incomplete-live-qualification
customer_content_status: blocked
---

# Codex web engine qualification record

The archived 2026-09-14 record contains deterministic fixtures, not live provider qualification. This record tracks new observations against the current web integration. No customer repository content, provider token, or prompt transcript is stored here.

## Baseline

- Source branch was created from `origin/main` at `b53173a04e813ca11bb47b14ea4e89e129343064`.
- PR #8447 is MERGED at `7e8dfab4dfd9fa8dbf656260a67216c6487630a7`.
- An initial 2026-09-21 probe returned HTTP 200 with `build_sha: 9768645adcd765a11603836399e8078fb8348065`; a later direct probe returned HTTP 200 with `build_sha: b53173a04e813ca11bb47b14ea4e89e129343064`, `supabase: connected`, and `sentry: configured`. The later value matches current `origin/main`, but it still does not prove that the Codex feature path is deployed or wired.
- The Codex reviewed definition remains disabled for new and existing runs. Production calls to the adapter composition and Codex dispatch were not found at this baseline.
- A post-rebase health probe on 2026-09-21 still returned HTTP 200 with build `b53173a04e813ca11bb47b14ea4e89e129343064`, `supabase: connected`, and `sentry: configured`; this is liveness evidence only. A fresh Flagsmith read confirmed `codex-engine` exists as feature `259236`, `default_enabled: false`, with no cohort override observed. No enablement mutation was attempted.
- A fresh direct probe on 2026-09-22 returned HTTP 200 with build `69b08a4ee5022b69bd1fb1061dc85011af660ab7`, `supabase: connected`, and `sentry: configured`. Flagsmith still reports feature `259236` (`codex-engine`) with `default_enabled: false`; no cohort override or enablement mutation was observed.
- Post-merge verification for PR #8507 completed on 2026-09-22: main CI, the workflow-run deploy, and live verification passed. `https://app.soleur.ai/health` returned `version: 0.286.5`, `build_sha: 19875b58bcbd85d8e4c7bfce98cc5482c53efc2e`, `supabase: connected`, and `sentry: configured`. This proves deployment and liveness, not customer-content authorization.
- PR #8849 merged on 2026-09-25 as `a8ce7bf09294d231984a485c3168bffd4cd1f409`. Its main CI, release build, workflow-run migration/deploy, and live-verify jobs passed. A direct `/health` probe returned `version: 0.302.6`, `build_sha: 26f63a66af5464ef57da4699021310b34f383b9a`, `supabase: connected`, and `sentry: configured`; the served descendant contains #8849. The unauthenticated login page returned HTTP 200. These checks establish deployment and app liveness, not Codex Web qualification.
- A read-only production count after #8849 found 179 `legacy` conversations and one `pending` conversation with a persisted conversation engine run. Migration 141's bound-row backfill tested `legacy` after adding the column with default `pending`, so that row was missed. Migration 142 repairs the marker and tightens transition authority; its production result remains unverified until its own deploy.

## Live-provider probes

| Mode | Probe | Observed result | Qualification scope |
|---|---|---|---|
| Managed ChatGPT | 2026-09-22, local Codex CLI v0.155.1, ephemeral read-only session in a newly created empty `/tmp` directory, with `--ignore-user-config --skip-git-repo-check`. Prompt prohibited tools, files, and secrets. | Process exited 0 and returned exactly `SOLEUR_CODEX_SYNTHETIC_OK`; 2,376 tokens were reported. | **PASS: bounded CLI smoke only.** Account plan, workspace owner, agreement, region, retention settings, and administrator controls remain unknown. This does **not** qualify Soleur Web transport, events/usage, lifecycle, attachments, approvals, cancellation, reconciliation, or erasure. |
| Managed ChatGPT | 2026-09-23, local Codex App Server v0.156.1, `read-only` sandbox and `never` approvals, empty temporary working directory, synthetic text only. A temporary Codex home contained only the already signed-in local auth file and was deleted after each probe. | Raw JSON-RPC initialize, thread/start, turn/start, thread/read, thread/turns/list, thread/items/list, and thread/delete all returned successfully. The streamed answer matched `SOLEUR_CODEX_APPSERVER_OK`; one usage notification arrived. A read after delete returned `thread not loaded`. A probe through Soleur's actual App Server transport returned exactly `SOLEUR_CODEX_TRANSPORT_OK`, one usage event (14,191 input and 11 output tokens), and running/completed statuses across 10 neutral events. Repeating that probe after the event-ID repair returned the same sentinel, one usage event (14,194 input and 11 output tokens), running/completed statuses, and 10 unique event IDs. | **PASS: local managed App Server and transport smoke.** The delete acknowledgement and subsequent read error do not establish provider-side erasure or retention. Account plan, workspace owner, agreement, region, retention, and administrator controls remain unknown. This does **not** qualify authenticated Soleur Web execution, routine dispatch, attachments, approvals, cancellation, reconciliation, or deployed usage persistence. |
| API key | Authenticated Web settings are the intended per-user/workspace credential source. | No authorized synthetic test workspace has supplied an OpenAI API key; no provider API request was attempted. A global Soleur credential is neither expected nor required for this mode. | **BLOCKED: test workspace credential unavailable.** Qualify with a key entered by an authorized synthetic workspace through Web settings. |

The first CLI attempt failed because the sandbox could not initialize the in-process App Server on a read-only filesystem. The same bounded request succeeded after an approved unsandboxed invocation. No customer content was included in either attempt. The App Server launcher contract is a CTO-owned technical runtime decision; it is not a reason to require a global customer credential.

## Required end-to-end matrix

| Scenario | API key | Managed ChatGPT |
|---|---|---|
| Soleur Web first turn and continuation, bound to one engine and auth mode | PENDING | PENDING |
| Events and usage persist and render correctly | PENDING | PENDING |
| Synthetic attachment, approval allow/deny, cancellation | PENDING | PENDING |
| Restart/reconcile/replay and provider-side delete acknowledgement | PENDING | PENDING |
| Revocation, provider error, denied egress and no fallback | PENDING | PENDING |
| Authenticated settings and deployed-app smoke on exact build SHA | PENDING | PENDING |

The deployed `/health` check and unauthenticated `/login` redirect passed on the
exact PR #8507 merged build. A 2026-09-23 health probe returned HTTP 200 with
`version: 0.286.12`, `build_sha: 251cfa650e3f4d675cdf4d3d1d44c49279c1ab59`,
`supabase: connected`, and `sentry: configured`; this is liveness evidence for
the then-current deployed build, not evidence that this protocol repair is deployed.
No authenticated Codex Web run was attempted because the feature flag remains
off and neither an API-key test workspace nor an identified managed ChatGPT
workspace is authorized for this qualification.

## Release gates

Internal synthetic enablement requires an identified internal account and bounded Web qualification under a default-off Flagsmith feature scoped only to that cohort. Customer-content enablement additionally requires a mode-specific CLO disposition recorded in the [decision packet](clo-decision-packet.md) and verified provider-retention and transfer evidence. The managed CLI and local App Server transport smokes are complete; the Web end-to-end matrix and API-key live probe remain incomplete, so neither internal nor customer enablement is asserted here.
