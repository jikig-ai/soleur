---
title: "Project-scoped Doppler read identity + a declared floor for the token-drift coverage ladder"
issue: 7159
branch: feat-one-shot-7159-doppler-prd-read-token-coverage
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-08-02-feat-token-drift-prd-root-token-and-coverage-denominator-plan.md
---

# Spec — token-drift read identity and coverage floor

The plan is the source of truth for rationale and measurements. This file states the
requirements and the contracts they pin.

> **Retargeted 2026-08-03.** The credential shape moved from a union of two config-scoped
> `doppler_service_token`s to a single project-scoped `doppler_service_account`, on the
> operator's interactive decision. See `decision-challenges.md` (UC-1 superseded, UC-2 adopted,
> UC-3 new). The plan file keeps its original filename slug.

## Problem

The twice-daily Cloudflare token-drift scan reads **1 of 13** Doppler configs and reports
`verdict: clean`. Its `coverage` signal is a 3-state enum with no denominator, so the state
meaning "more than one config" cannot distinguish 2-of-13 from 13-of-13.

## Measured constraints

- **C1 (2026-08-02).** A Doppler **service token** enumerates exactly the one config it is
  scoped to. `GET /v3/configs?project=soleur` returns 1 with `success: true` — scoped, not
  errored. `GET /v3/environments?project=soleur` returns `[]`. This is a property of
  `doppler_service_token`, not of Doppler credentials in general.
- **C2 (2026-08-02).** The `prd` and `prd_terraform` key sets are **not in a superset relation
  in either direction**: `prd_terraform` holds `CI_SSH_ACCESS_TOKEN_ID/_SECRET` and 10
  `CF_API_TOKEN*` keys; `prd` root holds `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and
  `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`. A project-scoped credential reads both, so the swap
  the #7159 checklist asked for is safe at the chosen shape.
- **C3 (2026-08-03, probe D).** Pinned provider `DopplerHQ/doppler v1.21.2` ships
  `doppler_service_account` (`name`, `slug`, `workplace_permissions`, `workplace_role`),
  `doppler_project_member_service_account` (`project`, `role`, `service_account_slug`,
  `environments`) and `doppler_service_account_token` (`name`, `service_account_slug`,
  **`api_key`** computed+sensitive, `expires_at`, `created_at`, `slug`). The value attribute is
  `api_key`, **not** `key` as on `doppler_service_token`. The #7159 claim "there is no single
  project-scoped read token to mint" is therefore false for this resource class.
- **C4 (2026-08-03, probe E).** `viewer` is the least-privileged project role that can read
  secret values: it carries `enclave_project_config_secrets_read` and not
  `enclave_project_config_secrets_write`; `no_access` has zero permissions. `viewer` also
  carries `enclave_project_config_dynamic_secrets_leases_write`,
  `enclave_project_config_dynamic_secrets_read`,
  `enclave_project_config_rotated_secrets_read` and `enclave_config_logs`.
- **C5 (2026-08-03, probe F).** Per-config scannable-key census: `dev` 2, `dev_personal` 2,
  `dev_scheduled` 2, `ci` 1, `prd` 5, `prd_cla` 5, `prd_ghcr` 5, `prd_kb_drift_walker` 5,
  `prd_scheduled` 5, `prd_terraform` 13, `prd_workspaces_luks` 5, `cli` 0, `cli_ops` 0. Only
  `cli`/`cli_ops` are vacuous.
- **C6 (2026-08-03, probe G).** 13 configs across 4 environments — `dev` 3, `ci` 1, `prd` 7,
  `cli` 2.
- **C7.** No committed-source derivation of the config list is faithful: it misses live configs
  and emits `prd_git_data`, which is TF-declared (`git-data-luks.tf:79`) but verified absent
  from live Doppler.
- **C8.** Provider v1.21.2 exposes no config-list data source.
- **C9.** The live config set is expected to **grow** — `doppler_config.git_data_prd` at
  git-data birth, and ephemeral `prd_git_data_rehearsal_*` configs from rehearsal dispatches.
- **C10.** An empty `--token` value (or an empty `DOPPLER_TOKEN`) is treated by the Doppler CLI
  as unset and rebinds to the ambient credential.
- **C11.** A denominator taken from the scan's own credential is satisfied by construction at a
  project-scoped shape, and narrows in lockstep with the credential under every reachable
  narrowing. It cannot be the gate.

## Requirements

| ID | Requirement | Pinned by |
|---|---|---|
| FR1 | `doppler_service_account.token_drift` (`name = "token-drift-ci-tf"`, `workplace_role`/`workplace_permissions` unset), `doppler_project_member_service_account.token_drift` (`project = "soleur"`, `role = "viewer"`, `environments` unset), `doppler_service_account_token.token_drift` (`expires_at` unset, `depends_on` the membership), and `github_actions_secret.doppler_token_drift` fed from `.api_key`. No `lifecycle.ignore_changes` on any. | AC1, AC2, AC33, AC34 |
| FR2 | All **four** addresses in the default per-merge `-target=` allow-list, in no dispatch set, and in neither parity-test exclusion set. | AC3, AC4 |
| FR3 | The detector keeps **one** credential and loops **configs**: no `DOPPLER_TOKEN_ENVS`, no credential iteration. It rejects unknown flags, treats an unset/empty `DOPPLER_TOKEN` as a failed credential rather than an ambient fallback, delivers the credential by env prefix (never argv), passes an explicit `-c <cfg>` at all four `doppler secrets` read sites, counts only configs whose read **succeeded**, `unset`s `DOPPLER_TOKEN`/`DOPPLER_CONFIG` once the credential is snapshotted, registers every scanned value with `::add-mask::`, and emits its JSON before every exit-2 return. | AC5, AC6, AC10, AC16, AC31, AC32, P1–P15 |
| FR4 | The detector owns the ladder (`--inventory`, `--configs-floor`, default 1), emitting `config_names`, `configs_floor`, `configs_expected`, `configs_unread`, `coverage`, `coverage_ratio`, `inventory_age_days`; the seven existing JSON keys are unchanged. | AC9, AC11, P6 |
| FR5 | The step publishes and does not decide. `DOPPLER_TOKEN` is sourced from `secrets.DOPPLER_TOKEN_DRIFT` (a literal swap, not a union); `DOPPLER_CONFIG` is removed; `DOPPLER_CONFIGS_FLOOR: 13` is added; `configs` stays last-and-greedy in `read -r`; every new field has a non-empty guard; the fallback arity moves in lockstep; an unset/empty/unparseable floor writes `coverage=unknown`/`verdict=unavailable` **before** failing; an external `configs_floor >= 13` assertion guards the declared floor. | AC5, AC29 |
| FR6 | All consumers move: the two `::warning::` arms, the filer `if:`/title/lead/remedy/closing, the close arm, both ops-email caveat spans, the DEAD email and DEAD issue bodies, the detector's own report line, the `ci-ssh-token-replace.md` runbook, and the two `.tf` premise comments. | AC7, AC8, AC12–AC15 |
| FR7 | The rung-2 orphan sweep stops reporting a clean sweep it did not perform, captures status explicitly under `set -euo pipefail`, and routes the finding into the existing `infra-drift` issue channel. Wiring the new credential into that job is out of scope. | AC17 |
| FR8 | A committed, dated, generator-documented 13-name inventory that supplies the ratio and unread list and **gates no state**, plus a repo-internal CI assertion that the workflow's `DOPPLER_CONFIGS_FLOOR` equals the inventory's name count. | AC18, AC19, AC29.3, P7, P7b, P8 |
| FR9 | An ADR recording the service-token-versus-service-account distinction, the `viewer` role choice, the unset-by-design attributes, and the declared-floor/reported-ratio split. | AC21 |

## Coverage vocabulary

`unknown` (fail-closed default) → `degraded` (`configs < configs_floor`) → `at-floor`
(`configs >= configs_floor`). Evaluation in that order. `multi-config`, `single-config` and
`full` are retired. The comparison is `>=` rather than `==` because C9 makes growth legitimate.

## The denominator contract

- **The floor gates and is declared.** `DOPPLER_CONFIGS_FLOOR: 13` lives in the token-drift
  step's `env:` and nowhere else in executable position. It states a demand on the step's own
  credential, so the step cannot be wrong about it.
- **The inventory reports and gates nothing.** It supplies `coverage_ratio`, `configs_unread`
  and `inventory_age_days`. Short, long or stale, it moves no state.
- **`degraded` detects a narrowing.** N1 a downgraded membership role → `0/13`; N2 an
  `environments`-scoped membership → `7/13`; N3 `DOPPLER_TOKEN_DRIFT` repointed at a
  config-scoped service token → `1/13`. Plus an absent, empty or revoked credential.
- **The floor cannot quietly follow the credential down.** Three places move together: the
  workflow literal, the inventory's name count, and a consumer-suite assertion that pins the
  literal as a named integer `>= 13` **and** requires it to equal the inventory count. That
  assertion is the CI check; it uses no credential and no network.

## Non-goals

- Reopening the credential shape settled by the operator on 2026-08-03.
- A live-verification step comparing the inventory against Doppler on every infra merge.
- Wiring `DOPPLER_TOKEN_DRIFT` into any second consumer, including the rung-2 orphan sweep.

## Contracts this change pins

1. **Detector JSON is additive only** — two other call sites read three of its fields with no
   compile-time link.
2. **The coverage arm's `if:` is positive** — the step is gated on one matrix leg, so every
   output is the empty string on the other.
3. **The two ops-email coverage caveats are byte-identical**, and there are exactly two of them.
4. **Zero-config detector invocation is unchanged** — three call sites depend on it;
   `--configs-floor` defaults to 1 and `--inventory` is optional.
5. **The inventory gates nothing** — it is expected to drift (C9), so a state that depended on
   it would be a fail-open.
6. **`configs` counts configs READ, not configs listed** — otherwise a role that can enumerate
   but not read satisfies the floor while measuring nothing.
7. **This credential is a widening, and the v3 mitigation is withdrawn.** It reads the whole
   `soleur` project: 4 environments, 13 configs. That is broader than `DOPPLER_TOKEN_PRD`
   (prd root only), so "adds no new capability" is **false** and must not appear in the `.tf`
   header or the plan. Within reach: `GHCR_MINTER_DOPPLER_TOKEN` (a read/write Doppler token),
   the Terraform GitHub App private key (`secrets:write`), `SUPABASE_SERVICE_ROLE_KEY`, and
   every secret in `dev`, `ci` and `cli`. What bounds it: `viewer` cannot write secret values
   (C4); no workplace role or permissions are granted, so no other Doppler project is
   reachable; and the credential is Terraform-managed and `-replace=`-rotatable. Incident
   response must revoke this **and** `DOPPLER_TOKEN_PRD`; only this one is Terraform-managed.
8. **No scanned value reaches any sink** — stdout, stderr, the JSON, the `--json-file`,
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
