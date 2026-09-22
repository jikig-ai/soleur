---
title: "Codex web engine qualification record"
date: 2026-09-21
status: incomplete
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

## Live-provider probes

| Mode | Probe | Observed result | Qualification scope |
|---|---|---|---|
| Managed ChatGPT | 2026-09-21, local Codex CLI v0.155.1, ephemeral read-only session in an empty `/tmp` directory, with `--ignore-user-config --skip-git-repo-check`. Prompt requested an exact synthetic sentinel and no tools/files. | CLI reported `Logged in using ChatGPT`; request exited 0 and returned `SOLEUR_CODEX_SYNTHETIC_OK`; 2,371 tokens were reported. | Basic ChatGPT account access and text response only. Account plan/owner is unknown. It does **not** qualify the web app, API transport, event/usage mapping, lifecycle, attachments, or erasure. |
| API key | Read-only production Doppler presence probe for `OPENAI_API_KEY`. | No global secret was found and no provider request was attempted. Web settings are the intended per-user/workspace credential source. | Product implementation is not blocked by the absent global secret; live API-key qualification remains pending until an authorized test workspace supplies a credential through settings. |

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

## Release gates

Internal synthetic enablement requires passing web-app qualification, an identified internal account, and a default-off Flagsmith feature scoped to the internal cohort. Customer-content enablement additionally requires a mode-specific CLO disposition recorded in the [decision packet](clo-decision-packet.md) and verified provider-retention and transfer evidence. Neither state is asserted here.
