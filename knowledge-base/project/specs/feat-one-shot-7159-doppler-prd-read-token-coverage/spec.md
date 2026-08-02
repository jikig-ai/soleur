---
title: "Doppler prd-root read credential + a denominator for the token-drift coverage ladder"
issue: 7159
branch: feat-one-shot-7159-doppler-prd-read-token-coverage
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-08-02-feat-token-drift-prd-root-token-and-coverage-denominator-plan.md
---

# Spec — token-drift read credential and coverage denominator

The plan is the source of truth for rationale and measurements. This file states the
requirements and the contracts they pin.

## Problem

The twice-daily Cloudflare token-drift scan reads **1 of 13** Doppler configs and reports
`verdict: clean`. Its `coverage` signal is a 3-state enum with no denominator, so the state
meaning "more than one config" cannot distinguish 2-of-13 from 13-of-13.

## Measured constraints (2026-08-02)

- **C1.** A Doppler service token enumerates exactly the one config it is scoped to.
  `GET /v3/configs?project=soleur` returns 1 with `success: true` — scoped, not errored.
  `GET /v3/environments?project=soleur` returns `[]`.
- **C2.** The scan's config count therefore equals the number of read credentials supplied.
- **C3.** The `prd` and `prd_terraform` key sets are **not in a superset relation in either
  direction**: `prd_terraform` holds `CI_SSH_ACCESS_TOKEN_ID/_SECRET` and 10 `CF_API_TOKEN*`
  keys; `prd` root holds `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and
  `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`.
- **C4.** No committed-source derivation of the config list is faithful: it misses live configs
  and emits `prd_git_data`, which is TF-declared (`git-data-luks.tf:79`) but verified absent
  from live Doppler.
- **C5.** Provider `DopplerHQ/doppler v1.21.2` exposes no config-list data source.
- **C6.** `TF_VAR_doppler_token_tf` is **not** injected at workflow level in
  `apply-web-platform-infra.yml`; it materialises only inside the `doppler run … -- terraform`
  child process, and `variables.tf:476` records it as a workplace-scope personal token.
- **C7.** The live config set is expected to grow — `doppler_config.git_data_prd` at git-data
  birth, and ephemeral `prd_git_data_rehearsal_*` configs from rehearsal dispatches.
- **C8.** An empty `--token` value is treated by the Doppler CLI as unset and rebinds to the
  ambient credential.

## Requirements

| ID | Requirement | Pinned by |
|---|---|---|
| FR1 | A read-scoped `doppler_service_token` on `soleur`/`prd` named `token-drift-ci-tf`, published as `github_actions_secret` `DOPPLER_TOKEN_DRIFT`, with no `lifecycle.ignore_changes`. | AC1, AC2 |
| FR2 | Both addresses in the default per-merge `-target=` allow-list, in no dispatch set, and in neither parity-test exclusion set. | AC3, AC4 |
| FR3 | The detector reads credentials from `DOPPLER_TOKEN_ENVS` (names, not values), rejects unknown flags, treats an unset/empty name as a failed credential rather than an ambient fallback, delivers credentials by env prefix (never argv), routes all four `doppler secrets` reads through the credential that enumerated that config, `unset`s the ambient credential once the map is built, registers every scanned value with `::add-mask::`, and emits its JSON before every exit-2 return. | AC5, AC6, AC10, AC16, AC31, AC32, P1–P5, P9–P15 |
| FR4 | The detector owns the ladder (`--inventory`), emitting `config_names`, `configs_floor`, `configs_expected`, `configs_unread`, `coverage`, `coverage_ratio`, `inventory_age_days`; the seven existing JSON keys are unchanged. | AC9, AC11, P6 |
| FR5 | The step publishes and does not decide; `configs` stays last-and-greedy in `read -r`; every new field has a non-empty guard; the fallback arity moves in lockstep; `DOPPLER_CONFIG` is removed; an empty `DOPPLER_TOKEN_ENVS` writes `coverage=unknown`/`verdict=unavailable` **before** failing; an external `configs_floor >= 2` assertion guards the self-referential floor. | AC5, AC29 |
| FR6 | All consumers move: the two `::warning::` arms, the filer `if:`/title/lead/remedy/closing, the close arm, both ops-email caveat spans, the DEAD email and DEAD issue bodies, the detector's own report line, the `ci-ssh-token-replace.md` runbook, and the two `.tf` premise comments. | AC7, AC8, AC12–AC15 |
| FR7 | The rung-2 orphan sweep stops reporting a clean sweep it did not perform, captures status explicitly under `set -euo pipefail`, and routes the finding into the existing `infra-drift` issue channel. | AC17 |
| FR8 | A committed, dated, generator-documented inventory that supplies the ratio and unread list and **gates no state**. | AC18, AC19, P7, P8 |
| FR9 | An ADR recording the credential-count-versus-config-count contract and the gate/report split. | AC21 |

## Coverage vocabulary

`unknown` (fail-closed default) → `degraded` (`scanned < floor`) → `at-floor`
(`scanned == floor`). Evaluation in that order. `multi-config`, `single-config` and `full` are
retired.

## Non-goals

- Changing the credential shape settled in the #7159 decision comment.
- Adopting `doppler_service_account` (UC-2 in `decision-challenges.md`).
- Reaching full fleet coverage. This change reaches 2 of 13, honestly reported.

## Contracts this change pins

1. **Detector JSON is additive only** — two other call sites read three of its fields with no
   compile-time link.
2. **The coverage arm's `if:` is positive** — the step is gated on one matrix leg, so every
   output is the empty string on the other.
3. **The two ops-email coverage caveats are byte-identical**, and there are exactly two of them.
4. **Zero-config detector invocation is unchanged** — three call sites depend on it.
5. **The inventory gates nothing** — it is expected to drift (C7), so a state that depended on
   it would be a fail-open.
6. **`access = "read"` is not a capability boundary.** `soleur/prd` root holds
   `GHCR_MINTER_DOPPLER_TOKEN` (the key of a `read/write` service token for the same config,
   `ghcr-minter-doppler-token.tf:45-60`), the Terraform GitHub App private key
   (`github-app.tf:55-59`, an App with `secrets:write`), and `SUPABASE_SERVICE_ROLE_KEY`. The
   credential is materially equivalent to Doppler write on `prd` and GitHub App administration
   of the repository. `DOPPLER_TOKEN_PRD` already carries this scope, so the change adds no new
   capability — but incident response must revoke both, and only one is Terraform-managed.
7. **No credential value reaches any sink** — stdout, stderr, the JSON, the `--json-file`,
   `$GITHUB_OUTPUT`, or the issue/email bodies. Masking is log-only and this repository is
   public.

## State at plan time

- No `token-drift-coverage` issue exists and the label has not been created. #7152 merged at
  2026-08-02 11:51 UTC; the last scheduled run (30735099570, 06:00 UTC) predates it and its log
  still shows the pre-#7152 verdict line with no `configs`/`coverage` fields. The 18:00 UTC run
  is the first to carry the coverage code.
- Consequence: an issue filed by that first run, or during the merge-to-release window, will
  carry an earlier class. The filer's dedup is label-scoped rather than title-scoped, which is
  why FR6 changes it to rewrite the body rather than short-circuit (AC13, AC28).
