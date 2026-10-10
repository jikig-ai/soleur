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
- A read-only production count after #8849 found 179 `legacy` conversations and one `pending` conversation with a persisted conversation engine run. Migration 141's bound-row backfill tested `legacy` after adding the column with default `pending`, so that row was missed.
- A read-only production timestamp/count audit found one conversation created between the deployment of migrations 138 and 141, and zero `legacy` conversations from that interval without a persisted run. Thus no live row in that window currently demonstrates the separate failed-bind misclassification risk. No conversation content was queried.
- PR #8910 merged on 2026-09-26 as `5343659fa71d51b06b93c01b090ad6d9356c373d`. Main CI [36246159162](https://github.com/jikig-ai/soleur/actions/runs/36246159162), release build [36246159326](https://github.com/jikig-ai/soleur/actions/runs/36246159326), and the workflow-run migration and deploy [36246899916](https://github.com/jikig-ai/soleur/actions/runs/36246899916) succeeded. The deployed `/health` endpoint returned HTTP 200 with build `0224ac6b8ee843da75b19dc1abc60a3548130281`, `supabase: connected`, and `sentry: configured`; that build contains the merge. `/login` returned HTTP 200. A read-only production aggregate after migration 142 found one `bound` and 179 `legacy` conversations, with zero persisted conversation runs attached to a nonbound conversation. No conversation content was queried. The deploy's live-verify harness was skipped by its changed-file gate, so these checks establish the binding repair and app liveness, not authenticated Codex Web execution.
- On 2026-09-26, Flagsmith feature `259236` (`codex-engine`) remained default false with no dev or production cohort segments. Source inspection of the deployed lineage found the Codex dispatch seams, but `ws-handler.ts` and `routines/run-routine.ts` still assert a Claude-only legacy binding on their real execution paths. Neither mode can be qualified through those paths yet. No flag change or provider request was made.

## 2026-09-27 authorized test workspace check

The operator identified the existing **Soleur Workspace** and its owner as
the authorized synthetic test workspace. A read-only production lookup
verified that owner relationship and found no valid OpenAI API-key credential
for the owner. No credential value was read or recorded. The owner email is
omitted from this public repository. No provider request or flag mutation was
made. This authorizes the workspace boundary for synthetic tests; it does not
establish either mode's provider account, managed-account authorization, CLO
disposition, or a customer-content cohort.

The implementation branch now exercises real WebSocket create, duplicate,
resume, first-turn, and continuation handler branches in tests. Those tests
inject a synthetic runtime and do not qualify production runtime composition.
The production composition currently has no App Server launcher or managed
credential provider and reports unverified egress evidence, so both live Web
modes remain unqualified. The routine inventory found no Inngest consumer that
reads `engine_run_id`; Codex routine dispatch therefore remains rejected.
Local CLI/App Server smokes remain separate from Web qualification.

The 2026-09-27 draft PR #9051 adds synthetic tests through the real WebSocket
handler branches and a migration for durable turn attempts and protected
recovery checkpoints. The focused conversation/persistence/migration/DSAR tests
passed (58 tests); the complete Web Platform suite passed (15,315 passed, 385
skipped, 1 todo). A loopback-only local migration probe passed duplicate-key,
forward-only lifecycle, checkpoint purge, anonymization, and rollback checks.
These results qualify code and local schema behavior only: no production
migration, provider request, authenticated Web run, or flag mutation occurred.
The API-key and managed Web matrices remain pending independently.

## 2026-09-29 code-path and credential recheck

PR #9051 remains draft. A focused local test pass now covers the resumed Codex
terminal lifecycle, transactional default preservation during auth-mode rebind,
Codex mode backfill, and a production-composition boundary that rejects both
auth modes before credentials, database execution writes, process spawn, stream
output, or Claude fallback. The focused set passed 120 tests across 10 files;
the two database cases ran against disposable local PostgreSQL databases and
dropped them after completion. The TOM-4 legal-posture gate passed 24/23
assertions and its mutation suite passed 15/15, including a removed WORM trigger
attachment. Dev-ledger parity passed 256/256. These are code and local-database
checks only; they do not constitute a deployed Web qualification.

A names-only check of the dev_scheduled Doppler configuration found no secret
names containing `OPENAI` or `CODEX`. This confirms that the runtime credential
question remains unanswered; no secret values were read. No provider request,
production write, feature-flag mutation, or customer processing occurred. The
API-key and managed Web matrices remain independently pending, and each CLO
disposition remains **PENDING — no authorization**. The feature stays
default-off and neither mode is eligible for an internal cohort.

## Live-provider probes

| Mode | Probe | Observed result | Qualification scope |
|---|---|---|---|
| Managed ChatGPT | 2026-09-22, local Codex CLI v0.155.1, ephemeral read-only session in a newly created empty `/tmp` directory, with `--ignore-user-config --skip-git-repo-check`. Prompt prohibited tools, files, and secrets. | Process exited 0 and returned exactly `SOLEUR_CODEX_SYNTHETIC_OK`; 2,376 tokens were reported. | **PASS: bounded CLI smoke only.** Account plan, workspace owner, agreement, region, retention settings, and administrator controls remain unknown. This does **not** qualify Soleur Web transport, events/usage, lifecycle, attachments, approvals, cancellation, reconciliation, or erasure. |
| Managed ChatGPT | 2026-09-23, local Codex App Server v0.156.1, `read-only` sandbox and `never` approvals, empty temporary working directory, synthetic text only. A temporary Codex home contained only the already signed-in local auth file and was deleted after each probe. | Raw JSON-RPC initialize, thread/start, turn/start, thread/read, thread/turns/list, thread/items/list, and thread/delete all returned successfully. The streamed answer matched `SOLEUR_CODEX_APPSERVER_OK`; one usage notification arrived. A read after delete returned `thread not loaded`. A probe through Soleur's actual App Server transport returned exactly `SOLEUR_CODEX_TRANSPORT_OK`, one usage event (14,191 input and 11 output tokens), and running/completed statuses across 10 neutral events. Repeating that probe after the event-ID repair returned the same sentinel, one usage event (14,194 input and 11 output tokens), running/completed statuses, and 10 unique event IDs. | **PASS: local managed App Server and transport smoke.** The delete acknowledgement and subsequent read error do not establish provider-side erasure or retention. Account plan, workspace owner, agreement, region, retention, and administrator controls remain unknown. This does **not** qualify authenticated Soleur Web execution, routine dispatch, attachments, approvals, cancellation, reconciliation, or deployed usage persistence. |
| API key | Authenticated Web settings are the intended per-user/workspace credential source. | The authorized synthetic Soleur Workspace has not supplied an OpenAI API key; no provider API request was attempted. A global Soleur credential is neither expected nor required for this mode. | **BLOCKED: test workspace credential unavailable.** Qualify with a key entered by an authorized synthetic workspace through Web settings. |

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
off and the authorized Soleur Workspace currently has no valid API key; managed
ChatGPT account ownership, agreement, and authorization also remain unverified.
The 2026-09-27 CLO assessment records both modes as pending with no authorization.

## Release gates

Internal synthetic enablement requires an identified internal account and bounded Web qualification under a default-off Flagsmith feature scoped only to that cohort. Customer-content enablement additionally requires a mode-specific CLO disposition recorded in the [decision packet](clo-decision-packet.md) and verified provider-retention and transfer evidence. The managed CLI and local App Server transport smokes are complete; the Web end-to-end matrix and API-key live probe remain incomplete, so neither internal nor customer enablement is asserted here.

## Addendum — 2026-10-04 access and control recheck

The operator reconfirmed that qualification credential references have not yet
been created. The task-isolated account-setup browser navigated to
`https://platform.openai.com/settings/organization/projects`, reached sign-in,
and then showed a Cloudflare human-verification challenge. The operator reported
that verification loops; retries stopped. A redacted snapshot confirmed the
challenge. No project or key was created, credential value inspected, or provider
inference requested. Account nomination does not verify authentication.

Current official [spend-limit documentation](https://developers.openai.com/api/docs/guides/spend-limits)
describes project hard limits separately from alerts, with delayed enforcement
that can permit slight overspend. Official [key guidance](https://developers.openai.com/api/docs/guides/production-best-practices)
describes expiration dates and administrator-enforced maximum key lifetimes.
These documentation findings do not verify availability or configuration in
this account. Preserve the US$5 total maximum and seven-day expiry after setup;
qualification requires verified controls and an adequate margin for delayed
spend enforcement. A monthly alert alone does not meet that boundary.

A fresh GitHub deployment query for PR #9051's branch returned zero records.
Its CI builder check discards the image, so authenticated branch screenshot QA
and a compatible recovery application artifact/rehearsal remain unqualified.
The API-key disposition remains pending; the existing managed hosted-auth path
remains blocked under the [mode audit](../../../legal/audits/2026-10-03-codex-web-mode-authorization.md).
Neither mode's Web matrix nor routine-consumer qualification is completed.
Keep the PR draft and Codex default-off. No shared database/production write or
flag/cohort mutation occurred; local suites remain skipped at operator direction.

## Addendum — 2026-10-05 browser isolation and remaining evidence

The initial access recheck displayed Cloudflare human verification, but its
`--session-name` argument selected a persistence name rather than an isolated
browser daemon. That observation does not establish task-isolated account
authentication. The isolation label in the preceding access record must not
be inferred from that flag alone. The browser skill now distinguishes
`--session` isolation from `--session-name` persistence.

A fresh headed `--session codex9051-verify-20261005` reached OpenAI's sign-in
page. A desktop window probe confirmed a visible, mapped Chrome window, and
the CLI confirmed the new session separately from `default`. The browser
remains open for direct operator sign-in. No account authentication, project,
credential reference or spending/expiry control has been verified. No
credential value was inspected or inference requested; US$5/seven-day controls
remain prerequisites rather than operational controls.

At source head `48905982ad5e7712bb4d30aa28ae88577dc4653f`,
[CI](https://github.com/jikig-ai/soleur/actions/runs/37223921041) and
[tenant integration](https://github.com/jikig-ai/soleur/actions/runs/37223920992)
completed successfully. The branch deployment lookup still returned no
records. CI artifacts contain timings and a Docker build record; the
builder-only job does not establish a runnable recovery application. The
credential-free migration-down scan returned `codex-forward-only`; it
qualifies only refusal classification, not database recovery or a rehearsal.
The routine producer still requires legacy binding and the inspected
agent-native-audit consumer invokes Claude; neither establishes a qualifying
Codex routine consumer. These observations leave both Web matrices, the
compatible recovery build/rehearsal, authenticated branch screenshots and
mode-specific dispositions incomplete. The subsequent main sync and browser
skill correction require fresh exact-head checks. Draft/default-off and all
existing provider, credential, shared-write and cohort limits remain in force.

## Addendum — 2026-10-05 regular-browser account evidence

The operator reports account access in their regular browser and a project
hard limit subsequently set to US$5. Available expiry controls and a “Global”
region label are reported; configured expiry, agreement/custody and actual
data controls remain unresolved. The attributable [CLO account-evidence
addendum](clo-decision-packet.md#account-evidence-addendum--2026-10-05) owns
the safe-reference facts, supersession and independent mode dispositions.
No raw account identifier, email or credential value is retained here.

At source head `c968c74e0c8fe6c583f313c0b822701a3059bdbc`,
[CI](https://github.com/jikig-ai/soleur/actions/runs/37288875047) and
[tenant integration](https://github.com/jikig-ai/soleur/actions/runs/37288874914)
passed. PR #9051 reported draft and CLEAN. These code checks precede this
evidence-only update and do not qualify provider execution, recovery,
authenticated screenshots or either Web matrix. No provider request,
credential-value inspection, shared database/production write or flag/cohort
change was made by this continuation; local suites remain skipped.

## Addendum — 2026-10-05 seven-day maximum lifetime report

The operator subsequently reports the project's maximum API-key lifetime
configured to seven days. See the [CLO key-lifetime continuation](clo-decision-packet.md#key-lifetime-evidence-continuation--2026-10-05)
for its scope: reported administrator configuration, not an evidenced key or
its deadline, test-window extension, live authorization or Web qualification.
The earlier configured-control gap is historical; all remaining gates and
action prohibitions persist.

## Addendum — 2026-10-05 public agreement and data-control research

The operator requested direct online verification of agreement, custody and
data-control evidence. The attributable [public-source CLO reassessment](clo-decision-packet.md#public-source-clo-reassessment--2026-10-05)
owns the retrieved policy findings, conditional standard-DPA coverage and
remaining account/route gaps. It retains API-key PENDING and existing managed
hosted-auth BLOCKED without granting live authorization. The reported US$5
project limit and seven-day maximum key lifetime do not establish an actual
key/deadline or either Web matrix. Customer content stays blocked and the PR
stays draft/default-off.

The [offline compilation record](../feat-one-shot-codex-web-live-paths/offline-build-fa166b66.md)
records successful exact-source Next and custom server builds with synthetic
configuration. Its Node 26/webpack artifacts do not qualify a production
recovery candidate, retained-schema rehearsal or authenticated preview.
