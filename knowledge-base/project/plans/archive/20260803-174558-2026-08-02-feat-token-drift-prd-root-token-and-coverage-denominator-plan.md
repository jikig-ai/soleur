---
title: "infra: a project-scoped Doppler read identity and a declared coverage floor"
date: 2026-08-02
issue: 7159
branch: feat-one-shot-7159-doppler-prd-read-token-coverage
type: infra
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
revision: v4 (retargeted 2026-08-03 to the credential shape the operator chose; see "Plan Review Revisions" R26–R34)
---

# infra: a project-scoped Doppler read identity and a declared coverage floor

> **Lane note.** No `spec.md` existed for this branch when planning began, so `lane:` could
> not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

> **Filename note.** The file keeps its original
> `…-prd-root-token-and-coverage-denominator-…` slug so every existing citation resolves. The
> prd-root token is no longer the shape; the plan was retitled in place rather than renamed.

## Enhancement Summary

**Deepened on:** 2026-08-02. **Retargeted:** 2026-08-03.
**Review passes:** plan-review panel (architecture-strategist, spec-flow-analyzer,
code-simplicity-reviewer, kieran-rails-reviewer) → v2/v3; deepen-plan pass (security-sentinel,
observability-coverage-reviewer) → v3; operator decision on the credential shape (interactive,
2026-08-03) → this revision. 34 numbered revisions, R1–R34.

### Key improvements

1. **One project-scoped identity, not a union of config-scoped tokens.** The v3 union kept
   `DOPPLER_TOKEN` and added a second credential because a `doppler_service_token` on `prd`
   root cannot see `prd_terraform`. The pinned provider also ships `doppler_service_account`,
   which is **not** config-scoped. Shown the measurements, the operator chose that shape on
   2026-08-03. One credential reaches all 13 configs, the union is dropped, and the token-drift
   step's `DOPPLER_TOKEN` becomes a plain swap onto `secrets.DOPPLER_TOKEN_DRIFT` — exactly
   what the #7159 checklist asked for.
2. **The denominator reports; it does not gate.** A short inventory must never be able to
   derive the healthy state and close the channel. The gate uses a floor **declared** by the
   step; the inventory only prints the ratio and the unread list.
3. **The floor had to be re-founded.** With a project-scoped credential, a denominator taken
   from the scan's own listing is satisfied by construction, so `degraded` would have no
   producer. The floor is now a literal the step declares about its own credential, pinned by a
   repo-internal CI check against the inventory's name count.
4. **The credential's real reach is disclosed, and it is genuinely wider than before.** This
   identity reads the whole `soleur` project — all 4 environments, all 13 configs — which is
   broader than the "whole prd tree" #7159 accepted, and broader than the pre-existing
   `DOPPLER_TOKEN_PRD`. The v3 "adds no new capability" mitigation is **false** at this shape
   and has been withdrawn rather than softened.
5. **Every failure mode still reaches a channel.** Five paths that previously ended in a green
   run with an unread annotation (empty credential, revoked credential, failed issue update,
   unreachable issue channel, the rung-2 scratch-config sweep) stay re-routed.

### New considerations discovered

- A project-scoped credential makes `configs == expected` hold trivially, so the ladder is
  decorative unless the denominator comes from a source the credential cannot move.
- The three reachable narrowings (role downgrade, `environments` scoping, a swap back to a
  config-scoped token) all *shorten* reach and never lengthen it — which is what makes a
  one-sided floor sound.
- A role that can enumerate but not read values would list 13 configs and scan none, so
  `configs` must count configs actually **read**.
- `doppler_service_account_token` exposes its value as **`api_key`**, not `key` — a silent
  `terraform plan` failure if copied from the sibling `doppler_service_token` resources.
- A revoked credential exited before `emit_json`, so the coverage outputs were never published.
- The `--status success` filter in the discoverability probe returned the last *healthy* run.
- Ambient `DOPPLER_TOKEN`/`DOPPLER_CONFIG` fallback was prevented by a test rather than by
  construction.
- An orphaned state write on a secret-bearing create is invisible to `terraform plan`, and the
  provider ships no data source that could find it.

## Overview

Two deliverables, one change, against #7159 and the operator's 2026-08-03 shape decision.

1. **A project-scoped read identity.** Three Doppler resources —
   `doppler_service_account.token_drift`,
   `doppler_project_member_service_account.token_drift` (`project = "soleur"`,
   `role = "viewer"`, `environments` unset) and `doppler_service_account_token.token_drift` —
   published as a dedicated `github_actions_secret` `DOPPLER_TOKEN_DRIFT`, consumed only by the
   token-drift step. No `lifecycle.ignore_changes` on `plaintext_value`, so a `-replace=`
   rotation propagates in the same run. Plus four `-target=` legs in the infra allow-list.

2. **Replace the coverage enum with a declared floor and a reported ratio.** `coverage` is
   today a 3-state enum with no denominator, so its "more than one config" state cannot
   distinguish *2 of 13* from *13 of 13*. This change takes the live count from 1 to **13**.

The credential shape was reopened once, by the operator, on the strength of the 2026-08-02
measurements; it is settled again and is not reopened here. What this plan adds is the measured
behaviour of that shape: the provider schema, the project role set, a per-config census and the
config topology were all probed on 2026-08-03 ([Appendix A](#appendix-a--the-probes)).

**The `terraform apply` stays behind the environment's required-reviewer set. This plan
produces a PR.**

---

## Research Reconciliation — Spec vs. Codebase

Measured **2026-08-02** against live Doppler with ephemeral read credentials, each revoked in
the same command. Reproduce via [Appendix A](#appendix-a--the-probes).

| Claim (issue #7159 / decision comment) | Measured reality | Plan response |
|---|---|---|
| "Branch configs inherit from root, so a single credential restores the fan-out view." | A `prd`-ROOT read **service token** enumerates **exactly 1** config: `doppler configs -p soleur --token <root>` returns `['prd']`; raw `GET /v3/configs?project=soleur` returns 1 with `success: true` — a list silently scoped to the credential, not an error. `GET /v3/environments?project=soleur` returns `[]`. | True of `doppler_service_token`, and the reason that shape was abandoned. A `doppler_service_account` holding a project membership is a **different resource class** and is not config-scoped. The measurement survives as the argument for the shape change, not as a constraint on it. |
| "Point the token-drift step's `DOPPLER_TOKEN` at `secrets.DOPPLER_TOKEN_DRIFT`" (a swap). | The key sets of the two configs are **not in a superset relation in either direction**. `prd_terraform` carries 10 `CF_API_TOKEN*` keys plus `CI_SSH_ACCESS_TOKEN_ID/_SECRET`; `prd` root carries `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`. A swap of one *config-scoped* token for another **drops** the `CI_SSH_ACCESS_TOKEN` pair — the credential of the 2026-07-29 outage (ADR-154). | **The regression dissolves at this shape.** A project-scoped `viewer` reads `prd_terraform` as well as `prd`, so nothing is dropped and no union is needed. The swap is implemented literally: `DOPPLER_TOKEN` points at `secrets.DOPPLER_TOKEN_DRIFT`. |
| The remedy prose "Set the live value on the `prd` ROOT config; branch configs inherit it." | Falsified by the census: `CF_API_TOKEN_DNS_EDIT` is present in 7 configs, and `prd_terraform` does **not** carry `REGISTRY_PUSH_ACCESS_TOKEN_*` that `prd` root does. Setting root alone does not repair the fan-out. | Corrected at **all five** sites (FR6). Two are on the DEAD path — the acute arm — and were missing from the first draft's consumer list. |
| "There is no single project-scoped read token to mint." | **Falsified premise.** True for `doppler_service_token`; **false** for `doppler_service_account` in the pinned `DopplerHQ/doppler v1.21.2`, which ships `doppler_service_account` + `doppler_project_member_service_account` + `doppler_service_account_token` — a project-scoped, provider-minted identity needing no credential-entry step. Absent from the issue's 3-row option table. | **Adopted.** The operator was shown the measurements and chose this shape on 2026-08-03 (UC-2 in `decision-challenges.md`, now ADOPTED rather than deferred). It is the whole basis of this revision. |
| The `::warning::` remedy "a project-scoped **token** … restores fleet-wide coverage". | The noun is wrong: no Doppler service *token* is project-scoped. The *claim* is true of a service **account** with project membership. | Corrected (FR6.5) — the remedy now names the service account and the `viewer` membership, and the falsified noun is asserted absent by AC7. |
| A prd-root Actions secret does not yet exist. | `DOPPLER_TOKEN_PRD` **already exists** (prd-root, read) and is consumed by **six** workflows/actions. It is **not** Terraform-managed. `reusable-release.yml:488-490` independently documents "A Doppler service token also reads exactly ONE config and ignores `DOPPLER_CONFIG`" (the sentence wraps, so a single-line grep misses it); `tunnel.tf:273` repeats it. | The dedicated, TF-managed `DOPPLER_TOKEN_DRIFT` remains correct: single consumer, rotatable via `-replace=`. `DOPPLER_TOKEN_PRD` is not reused — and, critically, its scope is now **narrower** than the new credential's, which is why the v3 "adds no new capability" mitigation is withdrawn. |
| (Found while probing, 2026-08-03.) | The pinned provider's `doppler_service_account_token` exposes its secret as **`api_key`** (computed, sensitive), not `key` as on `doppler_service_token`. | Pinned in FR1 and asserted by AC1. Copying the sibling attribute name is a `terraform plan` failure, not a runtime one, but it is the single most likely transcription error in this change. |
| (Found while probing.) | `rung2-rehearsal-orphan-sweep` (same workflow file, `:1115-1116`) filters `startswith("prd_git_data_rehearsal_")` over a list its `prd_terraform` credential can only ever return one entry for. The predicate is **unsatisfiable**; the job reports "no orphans" unconditionally. | Folded in (FR7) — routed into the job's existing `infra-drift` issue channel, not a new warning on a green run. Wiring `DOPPLER_TOKEN_DRIFT` into that job would also satisfy the predicate, but it is deliberately **out of scope**: the new credential keeps exactly one consumer. |

### Live per-config census (2026-08-02, key names only)

| Key | Configs holding it | In `prd_terraform`? | In `prd` root? |
|---|---|---|---|
| `CF_API_TOKEN_DNS_EDIT` | 7 (all `prd*`) | yes | yes |
| `CF_API_TOKEN_PURGE` | 7 (all `prd*`) | yes | yes |
| `REGISTRY_PUSH_ACCESS_TOKEN_ID` / `_SECRET` | 6 (`prd*` except `prd_terraform`) | **no** | yes |
| `CI_SSH_ACCESS_TOKEN_ID` / `_SECRET` | 1 (`prd_terraform`) | yes | **no** |
| `CF_API_TOKEN`, `_AUDIT`, `_BOTMANAGEMENT`, `_BOT_MANAGEMENT`, `_DNS_RULESETS`, `_R2`, `_RULESETS`, `_ZONE_SETTINGS` | `prd_terraform` (+ `dev*` for `_AUDIT`) | yes | **no** |
| `X_ACCESS_TOKEN_SECRET` | 11 | skipped (no `_ID` half) | skipped |

Token-shaped credentials verified per scan mode: **today 11**, **root-only 3**, **union 12**.
`REGISTRY_PUSH_ACCESS_TOKEN` — the *first* case the detector's header cites as motivating it —
**is not scanned at all today**. The union covered both Access-service-token families; the
project-scoped identity covers them and the remaining eleven configs as well.

### Per-config census of scannable keys (2026-08-03)

Scannable = the key families the detector actually probes: `CF_API_TOKEN*` and
`*_ACCESS_TOKEN_ID` / `*_ACCESS_TOKEN_SECRET`. This is the measurement that justifies leaving
`environments` **unset** rather than scoping the membership to `prd`.

| Config | Scannable keys | | Config | Scannable keys |
|---|---|---|---|---|
| `dev` | 2 | | `prd_ghcr` | 5 |
| `dev_personal` | 2 | | `prd_kb_drift_walker` | 5 |
| `dev_scheduled` | 2 | | `prd_scheduled` | 5 |
| `ci` | 1 | | `prd_terraform` | 13 |
| `prd` | 5 | | `prd_workspaces_luks` | 5 |
| `prd_cla` | 5 | | `cli` | 0 |
| | | | `cli_ops` | 0 |

50 scannable key occurrences across the 13 configs. **Only `cli` and `cli_ops` are vacuous**,
so project-wide membership is a real coverage gain rather than pure blast radius: scoping
`environments` to `prd` would forfeit 7 scannable keys across `dev*` and `ci` while removing
none of the escalation hops disclosed below, because those live in `prd` root.

### Config topology (2026-08-03)

13 configs across 4 environments — `dev` (3), `ci` (1), `prd` (7), `cli` (2). The `prd`
environment's **7** configs are the detector header's own motivating case, which cites a
credential "stale in 5 of 7 configs".

> **Provenance for ADR-160.** The dispositive evidence is this census, not the
> `inheriting=false / inherits=[]` metadata. That metadata describes Doppler's *explicit
> cross-config inheritance feature*, which is off everywhere, and is **not** evidence about
> the built-in environment-root-to-branch behaviour. The census is sufficient for every
> conclusion drawn here and does not depend on which mechanism explains it.
> `apps/web-platform/infra/git-data-luks.tf:53-55` carries an independent, dated, probe-verified
> enumeration of the seven `prd*` configs that corroborates the "7 (all `prd*`)" rows.

---

## How the denominator is obtained

The shape change moves this problem rather than solving it. A project-scoped identity makes
`doppler configs -p soleur` return the project's true total, so any denominator taken from the
scan's own credential satisfies `configs == expected` **by construction**: the ratio would
always print `13/13`, `degraded` would have no producer, and the whole ladder would be
decorative. The denominator has to come from a source the credential cannot move.

### What it has to detect

Exactly three narrowings are reachable after this lands.

| Narrowing | How it lands | What the scan sees |
|---|---|---|
| **N1 — the membership role is downgraded** | `role` moves off `viewer`, or the `doppler_project_member_service_account` resource is removed | 0 configs read — either the enumeration returns nothing, or it returns names whose secret reads all fail |
| **N2 — the membership is scoped to a subset of environments** | `environments` is set (e.g. `["prd"]`) | 7 of 13 read |
| **N3 — `DOPPLER_TOKEN_DRIFT` is repointed at a config-scoped `doppler_service_token`** | the resource set is swapped back, or the Actions secret is sourced elsewhere | 1 of 13 read |

All three **shorten** what the credential reaches; none of them can lengthen it. The only thing
that lengthens the count is Doppler genuinely growing (C7). So the scan's own listing is a
*monotone* signal: it can be inflated by legitimate growth, never by a narrowing. That
asymmetry is what makes a one-sided gate sound, and it is why the gate compares against a floor
rather than against an equality.

### The four candidates, and why three fail

| Candidate | Verdict |
|---|---|
| Ask Doppler with the scan's own credential — `GET /v3/configs`, `GET /v3/environments` | **Rejected: credential-derived.** Both endpoints return a list *silently scoped to the caller* (measured 2026-08-02: a config-scoped token gets 1 config and `[]` environments, both with `success: true`). Under N1/N2/N3 the denominator narrows in lockstep with the numerator, `configs == expected` still holds, and `degraded` never fires. This is the failure the whole question exists to avoid, so it is rejected on structure, not on measurement. |
| Derive `expected` from the environments endpoint | **Rejected, twice over.** It is the same credential (above), *and* it counts environments, not configs: 4 versus 13, and the per-environment fan-out is uneven (3/1/7/2). Turning environments into configs needs a per-environment config listing — the same scoped call again. |
| Assert the credential's **identity class** (is this a service-account token?) | **Rejected as the mechanism, and not kept as a fallback.** It detects N3 only. A service-account token narrowed by `environments` (N2) or sitting at a reduced role (N1) still asserts as the same identity class while reading a fraction of the project, so the check reports healthy through two of the three narrowings. It also depends on an API response contract that has not been probed. A check that is green through two of three failure modes is worse than no check, because it reads as coverage. |
| A committed inventory that a CI step re-verifies against **live** Doppler | **Rejected, three independent reasons.** (i) The live side needs a listing credential, and the only credential that can list the whole project is `DOPPLER_TOKEN_DRIFT` itself — so the comparison narrows *with* the credential, and a change that narrows the grant and shortens the inventory together passes green. That is the same two-place defeat as the static check below, with a network dependency and a live-credential consumer added. (ii) C7 holds: the live set is expected to grow (`doppler_config.git_data_prd` at git-data birth, ephemeral `prd_git_data_rehearsal_*` from rehearsal dispatches), so the step reds merges in the direction that does not matter. (iii) It re-creates the merge blocker the v2 panel already cut (R5). |
| Doppler Terraform provider data sources | **Rejected** — v1.21.2 ships `doppler_environments`, `doppler_group`, `doppler_secrets`, `doppler_user` only; the graph cannot publish a config list. |
| Derive from committed source (`config = "…"` in `*.tf`, `DOPPLER_CONFIG:` in workflows, `-c <cfg>`) | **Rejected** — 6–9 names depending on the source set; it misses live configs (`ci`, `cli`, `dev_personal`, `prd_cla`, `prd_ghcr`) and emits `prd_git_data`, which is TF-declared (`git-data-luks.tf:79`) but verified absent from live Doppler. A short denominator flatters coverage, the unsafe direction. |

### Chosen: the floor is *declared*, the ratio is *measured*, and they are different numbers

- **`configs_floor` is a literal declared in the token-drift step's own `env:` —
  `DOPPLER_CONFIGS_FLOOR: 13` — and is read from nowhere else.** It is *exact by construction*
  in the same sense the v3 floor was: the step cannot be wrong about a number it declares. What
  it declares is not a fact about Doppler but a **demand on its own credential**: "the identity
  I was handed must reach at least this many configs." The v3 floor made the same kind of
  statement about credential count; the shape change only changes the unit.
- **The gate is one-sided.** `configs < floor → degraded`; `configs >= floor → at-floor`.
  `>=`, not `==`, because C7 says growth is legitimate and must not red a cron twice daily.
  Growth pushes the printed ratio above 1 and changes no state.
- **`configs` counts configs actually READ, not configs listed.** A config enters the count
  only once its `doppler secrets --only-names` read has succeeded. Without this, N1 in its
  subtler form — a role that can enumerate but cannot read values — would list 13 and scan
  none, and the floor would be satisfied by a credential that measures nothing.
- **`configs_expected` is the committed inventory's name count, and gates nothing.** It
  supplies `coverage_ratio = configs/configs_expected`, the `configs_unread` list, and
  `inventory_age_days`. A short, long or stale inventory changes the printed ratio and the
  unread list, and changes **no state**: no arm starts or stops firing, no issue opens or
  closes. That is the R1 property, carried forward unchanged at the new shape.
- **Staleness is bounded without a credential.** The detector emits `inventory_age_days` from
  the `# generated:` header; a caveat is appended to the ratio past 90 days.

**What `degraded` concretely detects.** N1 → `0/13`. N2 → `7/13` with `configs_unread` naming
the six dropped configs. N3 → `1/13`. Plus the two operational modes that already existed: an
absent or empty `DOPPLER_TOKEN_DRIFT` (the merge-to-release window, or a deleted secret) and a
revoked or expired credential. Every one of those is a real, producible regression with a
performable remedy — which is the property `multi-config` never had.

### Why the floor cannot quietly follow the credential down

The v3 hazard (R18) generalises: a floor lowered in the same change that narrows the grant
would keep the scan at `at-floor` while coverage regressed. Three places must move together,
and the third is a test:

1. `DOPPLER_CONFIGS_FLOOR` in `.github/workflows/scheduled-terraform-drift.yml`.
2. The name count in `apps/web-platform/infra/doppler-config-inventory.txt`.
3. **`plugins/soleur/test/token-drift-workflow-causes.test.sh` pins the literal as a named
   integer — `DOPPLER_CONFIGS_FLOOR` must parse and be `>= 13` — and separately asserts it
   equals the inventory's name count.**

Item 3 is the CI check that fails when the floor and the inventory drift apart. It is
repo-internal and deterministic: no credential, no network, no live dependency, and it runs on
every PR under `scripts/test-all.sh`. It is strictly stronger than the live-verification step
rejected above — same two-place defeat condition, no merge blocker on legitimate growth, no new
consumer of a listing credential.

The step additionally re-asserts `configs_floor >= 13` at run time and downgrades to `degraded`
when that assertion fails, so a workflow-level override cannot lower the bar between merges.
The assertion is **external** to the floor, exactly as AC29 required at the old value of 2.

### Who updates the floor and the inventory

The change that alters the project's config set owns both edits, in the same PR.
`git-data-luks.tf` already declares `doppler_config.git_data_prd`, so the git-data birth change
raises the floor to 14 and regenerates the inventory; the inventory's `# command:` header line
carries the regeneration command, so the edit is mechanical rather than remembered. Ephemeral
`prd_git_data_rehearsal_*` configs need no edit at all — they only push `configs` above the
floor, which `>=` absorbs.

A config **removal** is the one case that produces a false `degraded`: the coverage channel
reds until the floor is lowered. That is left as-is deliberately. Engineering it away means
letting a shrinking live count lower its own alarm threshold, which is N1/N2/N3 with extra
steps. Noisy-in-the-safe-direction is the trade this design takes, and it is recorded in
`## Risks & Mitigations` rather than hidden.

---

## The new coverage ladder

`coverage` keeps its name; every consumer is in-repo and is updated in this change.

| Value | Condition | Notes |
|---|---|---|
| `unknown` | either side unparseable — the **default** | unchanged fail-closed polarity |
| `degraded` | `configs < configs_floor` | the credential is missing, empty, revoked, or has been narrowed (N1/N2/N3). **Producible and actionable.** |
| `at-floor` | `configs >= configs_floor` | the credential reached at least every config the step demanded |

Evaluation order is pinned: `unknown` → `degraded` → `at-floor`.

`multi-config`, `single-config` and `full` are all retired. `single-config` collapses into
`degraded` at a floor of 13. `full` would have been a state with no reachable producer whose
only consumer was the close arm — shipping it would leave the standing issue asserting a
closing condition the same plan had already decided would never occur, which is verbatim the
regression `scheduled-terraform-drift.yml:357-359` records from a previous revision.

`at-floor` keeps its name rather than becoming `full`, even though the steady state is now
`13/13`. The state is defined against the *declared floor*, not against the project — that is
the whole point of the gate/report split, and a name asserting completeness would invite a
future reader to gate on the inventory again.

**The close arm fires on `at-floor`.** The recurring `token-drift-coverage` issue therefore
auto-closes once the credential reaches all 13 configs — satisfying the #7159 checklist's
Done-when literally, at `coverage_ratio: 13/13` rather than at a partial ratio the previous
revision had to defend. The coverage channel goes back to signalling *regression*, which is
what it is good at.

### The merge-to-release window

The workflow edits go live at merge; the credential exists only after the environment gate
releases the infra run. In that window `secrets.DOPPLER_TOKEN_DRIFT` interpolates to the empty
string, and the token-drift step's `DOPPLER_TOKEN` is sourced from it. That window must not red
the cron twice daily — the file's own comment (`:346-349`) explains a standing red here would
poison the DEAD arm's red signal too. So:

- An **unset or empty** `DOPPLER_TOKEN` is a *configuration* fault: `configs` is 0, which is
  below the floor, so `coverage: degraded` reaches the warning and the issue channel while the
  job stays green and the detector exit code is untouched. The detector must **not** fall
  through to an ambient credential here — an empty value is treated by the Doppler CLI as
  unset, which would silently rebind to whatever the runner happens to carry (FR3).
- A **non-empty** credential that enumerates nothing is a *detector* fault: exit 2,
  `verdict: unavailable`, the existing DETECTOR-UNAVAILABLE email — with `emit_json` already
  run, so `configs`, `configs_floor` and `coverage` are still published.

The window produces one `degraded` issue at `0/13` that self-clears to `at-floor` at `13/13`
and auto-closes when the credential lands.

---

## Functional Requirements

- **FR1 — the credential.** New `apps/web-platform/infra/token-drift-service-account.tf`,
  carrying four resources. Attribute names are taken from the pinned provider's own schema
  (`terraform providers schema -json`, `DopplerHQ/doppler v1.21.2`, probe D), not from the
  sibling `doppler_service_token` files:

  1. `doppler_service_account.token_drift` — `name = "token-drift-ci-tf"`.
     `workplace_role` is **deliberately unset** and `workplace_permissions` is an explicitly
     **empty list** (the pinned provider enforces `ExactlyOneOf` on the pair, so neither-unset
     fails `terraform validate`; an empty list is the least-privileged satisfying value), so the
     project membership below is the identity's *only* grant and it can reach no other Doppler
     project. This is a design statement, not an omission, and the header says so.
  2. `doppler_project_member_service_account.token_drift` — `project = "soleur"`,
     `role = "viewer"`, `service_account_slug = doppler_service_account.token_drift.slug`.
     `environments` is **left unset**, i.e. project-wide, justified by the 2026-08-03 per-config
     census above: only `cli`/`cli_ops` are vacuous, so scoping to `prd` would forfeit 7
     scannable keys while removing none of the escalation hops.
  3. `doppler_service_account_token.token_drift` — `name = "token-drift-ci-tf"`,
     `service_account_slug = doppler_service_account.token_drift.slug`, plus
     `depends_on = [doppler_project_member_service_account.token_drift]`. Terraform derives
     ordering from the `slug` reference to the *account*, not to the *membership*, so without
     the explicit edge a partial apply can publish a working token whose grant has not landed.
     That state is fail-loud (the first scan reads `0/13` → `degraded`), but it should be
     unreachable rather than merely detectable.
  4. `github_actions_secret.doppler_token_drift` — `repository = "soleur"`,
     `secret_name = "DOPPLER_TOKEN_DRIFT"`,
     `plaintext_value = doppler_service_account_token.token_drift.api_key`.

  **`api_key`, not `key`.** `doppler_service_account_token` names its computed, sensitive value
  `api_key`; every sibling `doppler_service_token` in this root uses `key`. Copying the sibling
  attribute fails at `terraform plan`, not at run time, but it is the single most likely
  transcription error in this change (AC1).

  **`expires_at` is left unset — deliberately, and here is why.** The attribute is optional and
  the sibling service tokens do not expire. An expiry would fail the scan closed twice daily
  with no in-band re-mint path: the only remedy is an infra apply behind the environment gate,
  which converts a routine credential lifetime into a gated action. It also buys no detection
  the plan does not already have — a dead credential surfaces as `degraded` within 12 hours
  either way — and rotation on demand is already available through `-replace=`, which
  propagates in one apply because there is no `lifecycle.ignore_changes`. Asserted absent by
  AC34 so the choice is visible rather than assumed.

  No `lifecycle` block on any of the four. Header carries
  `autonomy-considered: provider-mint-applied`, the rotation recipe
  (`-replace=doppler_service_account_token.token_drift`), the reason no `ignore_changes` is
  present, the emergency path (the same `-replace=` mints a new `api_key` and invalidates the
  old one in a single apply; removing the membership resource strips reach without touching the
  token), **and a BLAST RADIUS block written in the `workspaces-luks.tf:77-89` shape** — see
  `## Encryption Posture` for the text it must carry, including the explicit statement that the
  v3 "no new capability" claim does **not** hold at this shape.
  *Templates:* `apps/web-platform/infra/web-arm-write-token.tf`,
  `apps/web-platform/infra/kb-drift.tf:92-113` (shape and header conventions only — the
  resource types and attribute names differ).

- **FR2 — the allow-list.** All **four** addresses added to the **default** per-merge `-target=`
  block in `apply-web-platform-infra.yml` (between the `cloudflare_ruleset.cache_shared_binaries`
  anchor at `:465` and the `betteruptime_team_member.ops` terminator at `:573`), and to no
  dispatch-job set: `doppler_service_account.token_drift`,
  `doppler_project_member_service_account.token_drift`,
  `doppler_service_account_token.token_drift`, `github_actions_secret.doppler_token_drift`.
  Omitting the membership leg is the dangerous partial: the account and token would be created
  and published with no project grant. None may go in `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`
  (`terraform-target-parity.test.ts:795`) or `AUDIT_PENDING_UNCOVERED` (`:631`) — both are
  exact-string `Set<string>`, and `allTargets` is built from `stripDispatchJobs(...)`
  (`:841-849`), so inclusion in the default block is the only way to pass.

- **FR3 — one credential, a loop over configs.** `scripts/check-cloudflare-token-drift.sh` keeps
  taking its single credential from `DOPPLER_TOKEN` and gains **no credential-iteration surface
  at all**: no `DOPPLER_TOKEN_ENVS`, no repeatable flag, no `for_each`. The detector loops over
  the configs the one credential enumerates. This is simpler than both the v3 union and the
  per-config `for_each` shape, and it means the three existing single-credential call sites are
  unchanged **by construction** rather than by care.
  - **Reject unknown flags.** The argument loop's `*) shift ;;` catch-all (`:91`) silently
    swallows a typo. Replace with an error + exit 2. The credential-typo motivation is gone,
    but the hazard is not: a misspelled `--inventory` silently drops the denominator and prints
    a caveat nobody asked for, and the catch-all is exactly the silent-degradation class this
    change exists to remove.
  - **An unset or empty `DOPPLER_TOKEN` is a failed credential, not an ambient fallback.**
    Record the failure, emit `configs = 0`, and do **not** invoke the CLI with an empty
    `--token` or an empty env value — the CLI treats it as unset and silently rebinds to
    whatever ambient credential the runner carries, which would report a confident wrong
    answer. This is the same failure the Appendix A footnote records from the probe itself.
  - Enumerate once with `doppler configs -p "$PROJECT" --json`, delivering the credential as an
    **env prefix** (`DOPPLER_TOKEN="$t" doppler …`), never as `--token <value>` on argv.
  - Drop the `2>/dev/null` on the enumeration (`:102`): a non-empty credential that enumerates
    nothing must be loud, and its stderr is currently swallowed.
  - **Route all four downstream reads through an explicit `-c "$cfg"`**, iterating the
    enumerated config list: `:138` (`doppler secrets --only-names`), `:223`, `:505`, `:506`
    (`doppler secrets get`). Under the previous single-config design these bound implicitly to
    `DOPPLER_CONFIG`; with 13 configs in play, an implicit bind grades the wrong config's bytes.
  - **`configs` counts configs whose `--only-names` read SUCCEEDED**, not configs enumerated.
    A role that can list but not read would otherwise satisfy the floor while measuring
    nothing (N1). A config that enumerates but fails its read is recorded by **name** in the
    failed set and contributes to `configs_unread`.
  - **`unset DOPPLER_TOKEN DOPPLER_CONFIG` once the credential is snapshotted into a local.**
    The step keeps both in its environment for the whole run, so a fifth read site added later
    — or one of the four missed — silently binds the ambient credential and the ambient config.
    A test catches that at review time only. Unsetting makes a missed site **fail loudly by
    construction**, and it closes the empty-value/ambient-rebind hazard at the source rather
    than per call site.
  - **Register every distinct scanned value with `::add-mask::` under `GITHUB_ACTIONS=true`,
    before the first probe.** Actions auto-masks only `secrets.*`-sourced values, so every
    `CF_API_TOKEN*` value and every Access secret the detector pulls is currently unmasked in
    the job log — in the same change that deliberately un-swallows stderr from that subsystem.
    This matters **more** at 13 configs than it did at 2: the census counts 50 scannable key
    occurrences that will transit the runner, against 18 under the union.
  - **Argv, stated accurately.** Env-prefix delivery defends against a *different-UID local
    observer* (`/proc/<pid>/cmdline` is world-readable, `/proc/<pid>/environ` is 0400), not
    against a compromised runner — on a GitHub-hosted runner every step shares one UID. It is
    still the right default, and it is not the whole picture: the detector already places
    scanned values on curl's argv at `:210` (`-H "Authorization: Bearer $v"`) and `:361-362`
    (the Access id/secret headers), and going from 1 config to 13 **widens** that from 11
    token-shaped values to the fleet set. That is pre-existing and accepted on an ephemeral
    runner; the plan says so rather than implying argv is clean. Bounding fact worth keeping in
    the header: the detector reads only *token-shaped* keys (`:146`, `:152`, `:162`), not the
    whole config, so "13 configs means more secret material transits the runner" is bounded to
    that family — 50 key occurrences, not ~1500 secrets.
  - **`emit_json` runs before every exit-2 return.** Today the enumeration guard (`:104-107`)
    and the non-vacuity gate (`:184-192`) exit before `emit_json` (`:679`), so a revoked
    credential produces no verdict file at all, the step parses `configs` as `-1`, and
    coverage lands on `unknown` — whose issue Remedy reads "do not widen the Doppler token,
    fix the verdict file first", which is unperformable for a revoked credential. Emitting
    first keeps `configs`, `configs_floor` and `coverage` published on every path, so a
    revoked credential surfaces as `degraded` at `0/13` rather than blinding the whole scan.
    The exit codes themselves are unchanged.

- **FR4 — the detector owns the ladder.** Add `--inventory <path>` and `--configs-floor <n>`;
  `emit_json` gains `config_names` (successfully read, sorted), `configs_floor`,
  `configs_expected`, `configs_unread` (inventory minus read, sorted), `coverage`,
  `coverage_ratio` and `inventory_age_days`. `--configs-floor` defaults to `1` when absent, so
  the three existing call sites keep their current behaviour and only the token-drift step
  passes `13`.
  Every existing key — `live`, `dead`, `unverifiable`, `probes`, `configs`, `stale`,
  `unverifiable_keys` — keeps its name and type; two other call sites read three of them with
  no compile-time link.
  Moving the ladder here rather than leaving it in the YAML `run:` block removes the
  one-physical-line python constraint, makes all three states unit-testable in the producer
  suite, and gives `configs_unread` a producer — three consumers need that list.
  **Argv contract:** `emit_json` (`:574-598`) passes five scalars then packs variable-length
  arrays behind a single `"--"` sentinel parsed with `range(1,6)` / `sys.argv[6:]` /
  `rest.index("--")`. Inserting scalars shifts every index, and a third and fourth list need
  **distinct sentinels**, not another `index`.

- **FR5 — the step publishes, it does not decide.** The `token_drift` step reads the fields
  from the JSON and writes them to `$GITHUB_OUTPUT`. No ladder arithmetic remains in YAML.
  Three constraints on the `read -r` line (`:195`), all currently load-bearing:
  1. **`configs` stays last-and-greedy.** Any field-shift lands in it and fails `^[0-9]+$` →
     `unknown`. `config_names` is a comma-join that is the **empty string** when nothing is
     enumerated; IFS word-splitting collapses an empty field and shifts every later field
     left, so placing it before `configs` would let `configs` receive a wrong-but-numeric value
     and derive a confident state from garbage — fail-open.
  2. **Every new field gets a non-empty guard** (`or "-"` on the producer side), mirroring
     `causes`.
  3. **The `|| echo "-1 -1 - -1"` fallback's arity moves in lockstep** with the variable list,
     or new variables silently arrive empty on the fallback path.
  Also, in the step's `env:`:
  - `DOPPLER_TOKEN` is repointed from `secrets.DOPPLER_TOKEN` to
    **`secrets.DOPPLER_TOKEN_DRIFT`** — the literal swap the #7159 checklist asked for, now
    safe because the new credential is a superset of the old one's reach.
  - `DOPPLER_CONFIG: prd_terraform` is **removed** (`:156`) — a Doppler credential of this
    class does not take direction from it, and with 13 configs in play it reads as "which
    config this scans".
  - `DOPPLER_CONFIGS_FLOOR: 13` is **added**, and is the only place the floor is written
    outside the tests.

  **Two guards on the floor, and the order matters.** The floor is declared rather than
  derived, so it is exact about what the step demands — but a declared number can be edited
  down, and a floor lowered alongside a narrowed grant would keep the scan at `at-floor` while
  coverage regressed. So:
  1. The step asserts `configs_floor >= 13` — an assertion **external** to the declaration,
     because a number cannot catch its own reduction — and downgrades to `degraded` when it
     fails. The consumer suite pins the literal as a named integer and separately asserts it
     equals the committed inventory's name count (FR8).
  2. When `DOPPLER_CONFIGS_FLOOR` is unset, empty or unparseable, the step **writes
     `coverage=unknown` and `verdict=unavailable` to `$GITHUB_OUTPUT` first, and only then
     fails.** Failing before the write leaves every output as the empty string, and every
     consumer arm in this job tests positively (`== 'dead'`, `== 'degraded'`, `contains(...)`),
     so *nothing* matches: no email, no issue, and the final Sentry check-in derives its status
     from `steps.plan.outputs.exit_code` rather than from `token_drift`, so the monitor still
     reports `ok`. Writing first routes the failure to the DETECTOR-UNAVAILABLE email and the
     `unknown` issue arm.

- **FR6 — every consumer moves.** In `.github/workflows/scheduled-terraform-drift.yml` unless
  noted:
  1. `::warning::` arms: one for `degraded` (naming the ratio and the unread configs), one for
     `unknown`. The retired states' arms go.
  2. Coverage-issue filer `if:` — positive comparisons only:
     `coverage == 'degraded' || coverage == 'unknown'`. A negative test matches the empty
     string the skipped `infra/github` matrix leg publishes.
  3. Filer becomes **create-or-update-body**: on an existing open issue it runs
     `gh issue edit <n> --title … --body-file …` instead of short-circuiting at `:418-425`. It
     still never comments, so the "730 comments a year" property is kept, while a state
     transition rewrites the body rather than freezing whichever state filed first. Dedup is
     **label-scoped, not title-scoped**, so without this a `single-config`-era issue would pin
     a stale title and a remedy this change has already performed.
  4. Filer `TITLE`/`LEAD` per class; the `degraded` body lists `configs_unread` and the ratio.
  5. Filer Remedy prose (`:461-476`) — the inheritance sentence goes, and the
     "project-scoped read **token**" phrase is replaced by the credential that actually exists:
     a `doppler_service_account` holding a `viewer` project membership. The remedy for
     `degraded` is no longer "widen the token" (there is nothing left to widen); it is "the
     credential has been narrowed or has stopped working — compare `coverage_ratio` and
     `configs_unread` against the declared floor", with the three narrowings N1/N2/N3 named.
  6. Filer Closing prose (`:481-485`) — closing condition becomes `coverage: at-floor`.
  7. Close arm `if:` → `coverage == 'at-floor'`; close comment body updated.
  8. **DEAD ops email body (`:280`)** — `… branch configs inherit it.` The acute arm, on the
     path that produced the 63-hour ADR-154 outage.
  9. **DEAD issue body (`:584`)** — same sentence, same correction; and its closing condition
     at `:595`.
  10. **`scripts/check-cloudflare-token-drift.sh:629`** — the human report prints the same
      falsified remedy under `STALE —`.
  11. Both ops-email `<em>Scan coverage: …</em>` spans (`:280`, `:645`) — rewritten to carry
      `coverage_ratio`, kept **byte-identical to each other**.
  12. **`knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md:87`** — an
      operator runbook whose stated exit condition is `coverage: multi-config`. This change
      makes that token unreachable, so the runbook step becomes unperformable if left.
  13. **The verdict echo line (`:251`).** Today it prints
      `token-drift verdict: … (detector exit …, causes: …, configs: …, coverage: …)` — no
      `floor:` and no `ratio:`. The `discoverability_test` and AC26 both assert those fields,
      so this line is a consumer and must be listed as one; without it the grep prefix matches
      while the asserted fields are absent.
  14. **The filer's update path gets its own error slug.** `gh issue edit --body-file` branches
      on its exit status and emits `token_drift_coverage_update_failed` on failure. The
      existing label re-assert at `:420` is `… || true` and must stay a separate call, so the
      body edit's status is not swallowed into it. A failed update freezes the issue at
      whichever state filed first — the exact defect FR6.3 exists to remove.
  15. **An ops-email fallback for a dead issue channel.** Each of the four filer/close paths
      sets a step output on any named `::error::`; a `notify-ops-email` step gated on that
      output carries the finding. Without it, a rate-limited or failed filer is a green cron
      run whose only artifact is an annotation nobody opens — which is the shape the block at
      `:324-330` exists to eliminate, and which `continue-on-error: true` plus `exit 0` at
      `:415-416` makes reachable today.
  16. `apps/web-platform/infra/tunnel.tf:277` and
      `apps/web-platform/infra/workspaces-luks.tf:78,114` reason about credential blast radius
      from the same falsified premise. Their *conclusions* may still hold; a one-line premise
      correction each is in scope, re-deriving their blast-radius arguments is not.

- **FR7 — the sibling fail-open.** In `rung2-rehearsal-orphan-sweep`, the `_cfgs=` pipeline
  (`:1115-1116`) drops `2>/dev/null` and `|| true` and captures the status **explicitly**. The
  enclosing block opens `set -euo pipefail` (`:1085`), unlike the token-drift step's
  `set -uo pipefail`, so a bare removal would abort with no named annotation — the opposite of
  fail-loud. Because that job keeps only the `prd_terraform` credential and can never satisfy
  its own `startswith("prd_git_data_rehearsal_")` predicate, it publishes its status as its
  **own step output** and gets its **own filer** gated on that output.
  It must **not** be folded into `steps.sweep.outputs.orphans`: that filer is gated
  `orphans != '0'` (`:1131`) plus an implicit `success()`, so in the steady state — no Hetzner
  orphans — it is skipped and the finding reaches nothing; and inflating `orphans` to force the
  gate open would file a diagnostic line under a body (`:1141-1148`) asserting the listed items
  are paying hosts running the git transport wrappers with LUKS volumes attached, which would
  be untrue of a diagnostic. Its own title and lead keep both statements honest. Routing it to
  an issue rather than a `::warning::` on a green run is the point: a warning on a green cron
  is the shape this file's own header block (`:324-330`) exists to eliminate.

- **FR8 — the inventory (report only) and the floor pin.**
  `apps/web-platform/infra/doppler-config-inventory.txt`: a `# generated: <ISO-8601>` header,
  the generator command in a `# command:` comment, then the 13 sorted config names measured on
  2026-08-03. It feeds `coverage_ratio`, `configs_unread` and `inventory_age_days`, and
  **gates no state**. There is still no cross-workflow live-verification step, for the three
  reasons recorded above. The file is expected to drift — `git-data-luks.tf:79` declares a
  `prd_git_data` config that will exist after git-data birth, and rehearsal dispatches create
  ephemeral ones — which is precisely why it must not gate.

  The one thing that *is* enforced is repo-internal consistency:
  `plugins/soleur/test/token-drift-workflow-causes.test.sh` asserts that the workflow's
  `DOPPLER_CONFIGS_FLOOR` literal parses, is `>= 13`, and equals `grep -cE '^[a-z0-9_]+$'` over
  the inventory. This is the CI check that fails when the floor and the inventory drift apart.
  It reads no credential and makes no network call, so it cannot be defeated by narrowing the
  credential, and it cannot red a merge because live Doppler grew.

- **FR9 — the ADR.** `ADR-160` records: that a `doppler_service_token` is config-scoped and a
  `doppler_service_account` with a project membership is not (with the falsified
  "no project-scoped read token exists" premise from #7159); that the `viewer` role is the
  least-privileged role carrying `enclave_project_config_secrets_read`; the decision to leave
  `environments` and `workplace_role` unset, `workplace_permissions = []`; and the gate-versus-report
  split — **the floor is declared, the ratio is reported**. Provenance cites the 2026-08-02
  census and the 2026-08-03 probes.

---

## Architecture Decision (ADR/C4)

**Create `ADR-160 — A project-scoped Doppler service account reads the fleet; the coverage floor
is declared, not derived`** as an in-scope task of this plan. It corrects reasoning currently
carried in shipped comments, in the workflow's remedy prose, in a runbook and in the #7159
option table, and it records why the denominator may report but must not gate.

> **Ordinal — provisional until merge, and it has already moved twice.** This plan was authored
> against **ADR-155**; 155, 156 and 157 all landed on `origin/main` from sibling PRs while it was
> being written, so it was renumbered to **158**. **158** was then claimed mid-flight by
> `ADR-158-kb-file-tree-host-is-a-derived-value.md` (merged via #7189), so it is renumbered again
> to **159**. An ordinal chosen on a branch is a claim, not a reservation, and a branch that is
> behind `origin/main` cannot see the collision at all — re-check against a freshly fetched
> `origin/main` immediately before merge. On renumber, sweep this plan, the spec, the tasks file,
> `decision-challenges.md`, the `.tf` citations and every AC naming it:
> `grep -rn 'ADR-160' knowledge-base/project/{plans,specs}/feat-one-shot-7159-doppler-prd-read-token-coverage/`

Related: ADR-154, ADR-007, ADR-149.

**C4 views — no impact.** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). `doppler`
(`model.c4:238`), `github` (`:230`) and `cloudflare` (`:234`) are already modelled as external
systems and are already included in both container views (`views.c4:14`, `:36`). The change
adds no external human actor, no external system, no container or data store, and moves no
actor-to-surface access relationship — a read identity on an existing scheduled job sits below
C4 component granularity.

---

## Infrastructure (IaC)

**Terraform changes.** `apps/web-platform/infra/token-drift-service-account.tf` (new: the three
Doppler resources plus the Actions secret); `apps/web-platform/infra/doppler-config-inventory.txt`
(new: a data file, not Terraform); `.github/workflows/apply-web-platform-infra.yml` (four
`-target=` lines). Providers `DopplerHQ/doppler ~> 1.21` and `integrations/github` are already
required and locked — no version or lockfile change, and the three new resource types are
present in the already-pinned v1.21.2 schema (probe D). No new Terraform variable, so no new
`TF_VAR_*` precondition on the merge-triggered run.

**Apply path.** Not host-touching, so no cloud-init and no bootstrap script. Merge to `main`
triggers the infra workflow on `apps/web-platform/infra/*.tf`; all four new addresses sit in
the default allow-list; the run waits on the `web-platform-infra-apply` environment gate. Blast
radius of the *apply itself*: one Doppler service account, one project membership, one service
account token, one repository Actions secret. Zero destroys, zero reboots, zero host creates —
the destroy-guard, reboot counter and `host_creates` tripwire all read 0. Rotation is
`-replace=doppler_service_account_token.token_drift`; with no `lifecycle.ignore_changes`, the
new `api_key` reaches `DOPPLER_TOKEN_DRIFT` in the same run.

**Ordering.** The token carries an explicit
`depends_on = [doppler_project_member_service_account.token_drift]`. Terraform infers an edge
from the token to the *account* via `service_account_slug`, but none from the token to the
*membership*, so under a partial or reordered apply the Actions secret could be published
before the grant lands. The explicit edge removes that window.

**Distinctness / drift safeguards.** The identity is project-scoped, so `dev` is **no longer
untouched** by construction — it is in reach, deliberately, and that is disclosed rather than
asserted away (see `## Encryption Posture`). The absence of `lifecycle.ignore_changes` is
deliberate and explained in the file header. `doppler_service_account_token.token_drift.api_key`
is Computed + Sensitive + write-once and lands in `terraform.tfstate` on the R2 backend. If any
of the four `-target=` lines is dropped, the twice-daily `terraform plan` surfaces that resource
as unmanaged drift — and dropping the *membership* leg additionally shows up at run time as
`coverage: degraded` at `0/13`, because the token would exist with no grant.

**Vendor-tier reality check.** No per-tier quota affects service-token creation on the current
plan; five service tokens already exist on the `prd` config alone, measured 2026-08-02. Service
accounts are a distinct object class and their quota was **not** probed — if the apply fails on
a plan limit, that surfaces as a red infra run at the environment gate, not as a silent partial.
No new recurring vendor expense.

---

## Encryption Posture

```yaml
at_rest:
  - store: the ENTIRE Doppler soleur project — 4 environments, 13 configs
    mechanism: vendor-managed encryption at rest (Doppler)
    evidence: >
      ADR-007-doppler-secrets-management.md. Doppler-side SCOPE evidence: the pinned provider
      schema (probe D) and GET /v3/projects/roles (probe E), both 2026-08-03. SINK evidence is
      a different comparator and must not be conflated — web_probes.key goes to a host
      /etc/default file, never to a repo-wide Actions secret. The load-bearing sink
      comparators are github_actions_secret.workspaces_luks_boot_token
      (workspaces-luks.tf:131-148) and github_actions_secret.doppler_token_write
      (doppler-write-token.tf:47-51).
    defends_against: disclosure from Doppler's storage layer
    does_not_defend: >
      anyone holding the api_key value. THIS IS A WIDENING, AND THE v3 MITIGATION NO LONGER
      APPLIES. The credential is a project-scoped identity, so its reach is the whole soleur
      project: the 7 prd configs, the 3 dev configs, ci, and the 2 cli configs. That is
      strictly broader than the "whole prd tree" #7159 accepted, and strictly broader than the
      pre-existing DOPPLER_TOKEN_PRD, which is prd-root-scoped. The v3 sentence "this adds NO
      new capability — only a second copy" is FALSE at this shape and is WITHDRAWN, not
      softened. The operator was shown these measurements and chose this shape on 2026-08-03;
      it is an accepted, disclosed trade-off, recorded here rather than buried.
      What the reach resolves to, unchanged from v3 because these all live in prd root:
      (a) GHCR_MINTER_DOPPLER_TOKEN (ghcr-minter-doppler-token.tf:56-60) whose value is
      doppler_service_token.ghcr_minter.key — declared access = "read/write" on config "prd"
      at :45-50 — so this credential reads a Doppler WRITE credential;
      (b) GITHUB_APP_PRIVATE_KEY / GITHUB_APP_ID / GITHUB_APP_WEBHOOK_SECRET
      (github-app.tf:40-78) for the same App the Terraform provider authenticates with
      (main.tf:83-90), which kb-drift.tf:101-102 records as holding secrets:write — so it
      yields an installation token that can rewrite every repository Actions secret,
      including DOPPLER_TOKEN_DRIFT itself;
      (c) SUPABASE_SERVICE_ROLE_KEY (bypass-RLS read of all user data), PROXY_TLS_KEY,
      the three git transport/provision/remove SSH private keys, the zot push token, and the
      Inngest signing/event/manual-trigger keys.
      NEW at this shape: the same reach now also covers dev, dev_personal, dev_scheduled, ci,
      cli and cli_ops. Materially, the credential is equivalent to Doppler WRITE on prd and to
      GitHub App administration of the repository, and it additionally reads every non-prd
      config in the project.
      ROLE HONESTY. "viewer" is the least-privileged role that can read secret VALUES — it
      carries enclave_project_config_secrets_read and, verified via GET /v3/projects/roles,
      does NOT carry enclave_project_config_secrets_write; the only lower role, no_access, has
      zero permissions. But "viewer" is not purely read-only: it also carries
      enclave_project_config_dynamic_secrets_leases_write (a WRITE verb — it can create
      dynamic-secret leases), enclave_project_config_dynamic_secrets_read,
      enclave_project_config_rotated_secrets_read and enclave_config_logs. Those are disclosed
      rather than elided.
      WHAT STILL BOUNDS IT, each verified rather than assumed:
      (1) workplace_role is unset and workplace_permissions is empty, so the project membership is the
      ONLY grant — the identity cannot reach any other Doppler project;
      (2) the role cannot write secret values (roles probe above);
      (3) the credential is Terraform-managed and rotatable by -replace= in a single apply,
      which DOPPLER_TOKEN_PRD is not;
      (4) the detector reads only token-shaped keys, so what transits the runner is bounded to
      50 scannable key occurrences (2026-08-03 census), not every secret in the project.
      OPERATIONAL OBLIGATION: an incident response must revoke BOTH this credential and
      DOPPLER_TOKEN_PRD; only this one is Terraform-managed.
    disclosed_as: >
      BLAST RADIUS header block in token-drift-service-account.tf, written in the shape
      workspaces-luks.tf:77-89 already uses for this exact class ("THIS IS NOT LEAST
      PRIVILEGE, AND SAYING SO WOULD BE FALSE"), citing
      knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md
      and #6167 rather than inventing fresh prose, and stating explicitly that this shape is
      WIDER than DOPPLER_TOKEN_PRD.
    live_verification: >
      terraform state list | grep -c '^doppler_service_account_token\.token_drift$' returns
      exactly 1, and the same for the account and the membership addresses. Count-asserting,
      not a bare grep: a bare match cannot distinguish a clean state from a half-completed
      -replace= or an accumulated orphan (cq-assert-anchor-not-bare-token). The runtime proof
      that the GRANT is at the intended breadth is the scan itself reporting
      coverage_ratio 13/13 (AC26) — a token that exists with a narrowed or missing membership
      reads below the floor. A `doppler` CLI enumeration path for service-account tokens was
      NOT probed and is deliberately not asserted here.
  - store: terraform.tfstate in the R2 backend bucket soleur-terraform-state
    mechanism: Cloudflare R2 server-side encryption at rest (provider-default, always on),
               TLS-only access; same posture as every sibling token key already in state
    evidence: backend "s3" block, apps/web-platform/infra/main.tf
    defends_against: disclosure from R2's storage layer
    does_not_defend: anyone holding the R2 access key pair — the key is cleartext inside the
                     encrypted object, as it already is for five sibling resources
    disclosed_as: the "State storage" paragraph in the new .tf header
    live_verification: "existing infra suite asserts backend configuration; no new probe"
  - store: GitHub repository Actions secret DOPPLER_TOKEN_DRIFT
    mechanism: GitHub-managed libsodium sealed box; never readable back through the API
    evidence: the four sibling github_actions_secret resources in this root
    defends_against: disclosure from GitHub's storage layer and from workflow logs (masking)
    does_not_defend: any workflow in the repository — the TF GitHub App cannot write
                     ENVIRONMENT-scoped secrets, so this is repository-scoped like every
                     sibling
    disclosed_as: the publication paragraph in the new .tf header
    live_verification: "gh secret list --json name -q '.[].name' | grep DOPPLER_TOKEN_DRIFT"
in_transit:
  - connection: CI runner to api.doppler.com
    tls: TLS 1.2+ enforced by Doppler; plain HTTP refused
    cert_verification: on — no --no-verify-tls in any changed path
    does_not_defend: a compromised runner, which holds credentials in process memory. FR3
                     deliberately keeps them OUT of argv (env prefix, not --token) so they are
                     not additionally exposed to other processes via ps.
    disclosed_as: FR3
  - connection: CI runner to api.github.com
    tls: TLS 1.2+
    cert_verification: on
    does_not_defend: the GitHub App installation's own scope
    disclosed_as: unchanged
exception: none — no plaintext-exception store, no connection with verification disabled.
```

---

## Observability

```yaml
liveness_signal:
  what: the token_drift step's coverage and coverage_ratio outputs, echoed into the step log
        line "token-drift verdict: …"
  cadence: twice daily (06:00 / 18:00 UTC), Inngest-dispatched via cron-terraform-drift.ts
  alert_target: the token-drift-coverage action-required issue (label-deduped,
                create-or-update-body) plus the two verdict-bearing ops emails
  configured_in: .github/workflows/scheduled-terraform-drift.yml — token_drift step, the
                 coverage filer, the close arm
error_reporting:
  destination: GitHub Actions ::error:: annotations with named slugs
               (token_drift_coverage_list_failed, token_drift_coverage_escalation_failed,
               token_drift_coverage_update_failed, token_drift_coverage_close_list_failed,
               token_drift_coverage_close_failed, token_drift_floor_unparseable,
               token_drift_configs_unparseable, rung2_scratch_cfg_list_failed,
               rung2_scratch_cfg_escalation_failed) plus the action-required issue channel
               and, when the issue channel itself is unreachable, the ops-email fallback
               described in mode 6. THE LIST IS THE OPERATOR CONTRACT: the fallback emails
               tell the reader to search the run log for "the named error slug", so a slug
               emitted by the code and absent here sends them looking for the wrong string
               — and a slug listed here that no arm emits trains them to distrust the list.
  fail_loud: true — every arm that cannot reach its channel emits a named ::error:: AND
             sets an output the email fallback gates on; the detector emits its JSON
             BEFORE any exit-2 return, so a failure never blinds the coverage outputs
failure_modes:
  - mode: DOPPLER_TOKEN_DRIFT is absent or empty (the merge-to-release window, or a deleted
          secret)
    detection: the value is empty, so no config is read; configs=0 < configs_floor yields
               coverage=degraded at ratio 0/13. The detector must NOT fall through to an
               ambient credential, which the Doppler CLI does for an empty value.
    alert_route: ::warning:: plus the coverage action-required issue, whose body is rewritten
                 on every state transition
    layer: GitHub Actions run annotations + the GitHub issue channel harvested by
           operator-digest
  - mode: the credential is REVOKED or EXPIRED — non-empty, but enumerates nothing
    detection: configs=0 < floor, so coverage is degraded. This is a DIFFERENT path from the
               absent-secret mode above and must not be collapsed into it: the value is
               present, so the remedy is rotation, not provisioning. Since it is the only
               credential, no conclusion was drawn and the detector additionally exits 2
               (verdict=unavailable) — but emit_json has already run, so coverage,
               configs_floor and coverage_ratio are still published.
    alert_route: the coverage issue for the degraded case; additionally the
                 DETECTOR-UNAVAILABLE ops email because nothing at all was measured
    layer: GitHub issue channel + Resend ops email (notify-ops-email composite action)
  - mode: the credential is NARROWED — N1 the membership role is downgraded, N2 environments
          is scoped to a subset, N3 DOPPLER_TOKEN_DRIFT is repointed at a config-scoped
          doppler_service_token
    detection: configs falls below the declared floor of 13 — 0/13 for N1, 7/13 for N2, 1/13
               for N3 — so coverage=degraded and configs_unread names the dropped configs.
               This is the mode the whole denominator design exists to catch, and it is the
               reason the denominator may not be taken from the scan's own credential: a
               credential-derived denominator narrows in lockstep and reports 13/13 forever.
               N1's subtle form (a role that lists but cannot read) is caught because configs
               counts configs successfully READ, not configs listed.
    alert_route: ::warning:: plus the coverage action-required issue, body rewritten per state
    layer: GitHub Actions run annotations + the GitHub issue channel
  - mode: DOPPLER_CONFIGS_FLOOR is unset, empty or unparseable, or has been lowered so a
          narrowed credential would read as healthy
    detection: the step writes coverage=unknown and verdict=unavailable to $GITHUB_OUTPUT and
               THEN fails; it separately asserts configs_floor >= 13 at run time — a declared
               number cannot catch its own reduction, so the assertion is external to it — and
               the consumer suite pins the literal against the committed inventory's name
               count at PR time
    alert_route: the DETECTOR-UNAVAILABLE ops email arm and the `unknown` coverage-issue arm,
                 both reachable because the outputs were written before the failure; plus a
                 red PR check for the pre-merge half
    layer: Resend ops email + the GitHub issue channel + the CI test suite
  - mode: the committed inventory goes short or stale, so the reported ratio overstates
          coverage
    detection: inventory_age_days exceeds 90, appended as a caveat wherever the ratio prints
    alert_route: the step log only. At at-floor no warning arm fires, no issue is open, and
                 neither ops email is sent — so on a healthy run this caveat reaches the run
                 log and nothing else.
    layer: GitHub Actions run log
    note: deliberately un-escalated, and safe because the inventory gates no state. The ratio
          is decorative; a wrong ratio cannot silence a channel or close an issue.
  - mode: the coverage signal is derived correctly but the issue channel is unreachable
          (gh list/create/edit/close fails, a rate limit, a stripped label)
    detection: each path branches on its own exit status and emits its named slug, and sets a
               step output flag
    alert_route: an ops-email step gated on that flag — mirroring the DEAD filer's "reached
                 the email channel only" fallback. Without it a failed filer is a green cron
                 run whose only artifact is an annotation nobody opens, which is the exact
                 shape scheduled-terraform-drift.yml:324-330 exists to eliminate.
    layer: Resend ops email (notify-ops-email composite action)
  - mode: the scratch-config half of the rung-2 orphan sweep is not performed
    detection: the captured status of the _cfgs= pipeline, published as its OWN step output
    alert_route: its own filer gated on that output. It must NOT be folded into
                 steps.sweep.outputs.orphans: that filer is gated `orphans != '0'` plus an
                 implicit success(), so in the steady state it is skipped and the finding
                 reaches nothing — and forcing the gate open by inflating `orphans` would put
                 a diagnostic line under a body asserting the listed items are paying hosts
                 with LUKS volumes attached.
    layer: the GitHub issue channel
logs:
  where: GitHub Actions run logs for the Terraform Drift Detection workflow; the body of the
         standing token-drift-coverage issue
  retention: 90 days for run logs (GitHub default); issue bodies are permanent
discoverability_test:
  command: >
    curl -fsS --max-time 10 -o /dev/null -w "%{http_code}"
    https://api.github.com/repos/jikig-ai/soleur/actions/workflows/scheduled-terraform-drift.yml/runs
  expected_output: "200"
  # WHY THIS PROBE AND NOT THE RICHER `gh` ONE. Preflight Check 10 EXECUTES this command
  # with the operator's ambient file-backed CLI auth reachable (`env -i` preserves $HOME,
  # so the Doppler on-disk token, SSH keys and git credentials are all readable), and it
  # therefore refuses any credentialed CLI — `gh` included — and any shell-active token,
  # which rules out the pipe chain below. A probe that the gate will not run is not a
  # discoverability test; it is a comment. This form is a single unpiped, unauthenticated
  # request against a PUBLIC repo (verified: the endpoint returns 200 and the newest run's
  # conclusion anonymously), so it proves the run history for this workflow is reachable
  # with no credential and no SSH — which is the property `hr-observability-as-plan-quality-gate`
  # actually asks for.
  #
  # OPERATOR FOLLOW-UP (not the gate's probe — richer, needs `gh` auth):
  #   gh run list --workflow=scheduled-terraform-drift.yml -L 1 --json databaseId,conclusion,createdAt
  #   gh run view <id> --log | grep -E 'token-drift verdict: [a-z]+ \(detector exit'
  # Deliberately NOT filtered by --status success: that filter returns the last HEALTHY run
  # and prints a green verdict line while a newer run is failing — a clean bill of health for
  # a question never asked, which is this PR's own subject.
  operator_followup_expected_output: >
    the newest run's id, conclusion and timestamp, then a line of the form "token-drift
    verdict: clean (detector exit 0, causes: -, configs: 13, floor: 13, coverage: at-floor,
    ratio: 13/13)" once the credential has landed — or, in the merge-to-release window,
    "configs: 0, floor: 13, coverage: degraded, ratio: 0/13". NOTE the command deliberately
    does NOT filter --status success: that filter returns the last HEALTHY run and prints a
    green verdict line while a newer run is failing, which is a clean bill of health for a
    question never asked.
    NOTE ALSO why the grep is anchored on "[a-z]+ \(detector exit" and not on the bare
    prefix "token-drift verdict:". Actions echoes the RESOLVED `run:` script into the log,
    and the script's source line contains that literal prefix verbatim — so the loose
    pattern matched on a run that ABORTED before ever printing a verdict, and the
    discoverability probe could not fail. Measured on a two-line fixture holding the echoed
    source line and the resolved output line: the loose pattern matches 2, the anchored one
    matches 1 (the resolved line only), because the source carries "${verdict}" where the
    output carries a bare lowercase word.
```

No SSH anywhere in the verification path.

**Soak follow-through enrollment: not applicable.** No acceptance criterion is time-gated.

**Affected-surface observability:** a GitHub Actions runner surface, fully inspectable via
`gh run view --log`. Not a sandbox, readiness gate or cron worker, so the in-surface-probe
extension does not fire.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a production deploy that cannot happen. The
detector is on the critical path of five workflows (ADR-154). If the swap lands with a
credential whose grant did not (the membership `-target=` dropped, the ordering edge missing),
`CI_SSH_ACCESS_TOKEN` stops being scanned; the next rotation of that credential outside
Terraform goes undetected and every remote write path to the production host dark-fails — the
measured 2026-07-29 outcome, where the product served a stale build for roughly 63 hours while
every dashboard read green. That state is fail-loud here (`coverage: degraded` at `0/13`),
which is the point of the floor. Implemented with a gating denominator instead, a short
inventory would silence the channel entirely while the job stayed green.

**If this leaks, the user's data and workflow are exposed via:** the new `DOPPLER_TOKEN_DRIFT`
value — and the exposure is **the whole `soleur` project**, not "read-only on prd". This is a
genuine widening over both #7159's accepted scope and the pre-existing `DOPPLER_TOKEN_PRD`.
Within reach: the `ghcr_minter` **read/write** Doppler token
(`ghcr-minter-doppler-token.tf:56-60` storing `doppler_service_token.ghcr_minter.key`, declared
`access = "read/write"` at `:45-50`); the Terraform GitHub App private key
(`github-app.tf:55-59`) for an App with `secrets:write`, which can rewrite every repository
Actions secret including this one; `SUPABASE_SERVICE_ROLE_KEY` — bypass-RLS access to all user
data; and, new at this shape, every secret in `dev`, `dev_personal`, `dev_scheduled`, `ci`,
`cli` and `cli_ops`. The honest statement is that this credential is materially equivalent to
Doppler write on `prd` and to GitHub App administration of the repository, and it reads the
non-prd environments as well.

Vectors: the repository Actions secret (readable by any workflow in the repo — the governing
control is who can merge under `.github/workflows/`, and `CODEOWNERS` pins that path to the
operator while its own header records that the branch-protection rule enforcing CODEOWNERS
review is still an unfinished follow-up, with no ruleset in IaC enforcing it), the Terraform
state object in R2, and the runner process during the scan.

**What the trade-off is, and what it obliges.** The v3 answer — "`DOPPLER_TOKEN_PRD` already
carries identical scope, so this adds no new capability" — is **false at this shape** and is
withdrawn. This change *does* add capability: a repository-level credential that reads four
environments where the previous widest read one. That was put to the operator with the
measurements on 2026-08-03 and accepted, in exchange for the coverage the census quantifies —
50 scannable key occurrences across 13 configs instead of 11 in one, and both
Access-service-token families in scope for the first time. What remains true and verified:
`viewer` cannot write secret values; the identity holds no workplace role or permissions, so
it cannot reach another Doppler project; and unlike `DOPPLER_TOKEN_PRD` it is Terraform-managed
and rotates in a single apply. The obligation that follows is unchanged: an incident response
must revoke **both**, and only the new one is Terraform-managed.

**Brand-survival threshold:** `single-user incident`.

`requires_cpo_signoff: true` is set; `user-impact-reviewer` runs at review time; the review
panel escalates to include `architecture-strategist` and `spec-flow-analyzer`; and every
acceptance criterion below asserts the invariant rather than a proxy.

---

## Domain Review

**Domains relevant:** Engineering (CTO).

**Engineering (CTO) — reviewed.** Four risks dominate, each with a named mitigation: (1) a
credential published without its grant, from a dropped `-target=` leg or a missing ordering
edge (FR1, FR2, AC3, AC24); (2) the per-config read binding implicitly instead of through
`-c "$cfg"`, grading the wrong config's bytes across 13 configs (FR3, test P3); (3) detector
JSON schema stability, since two other call sites read `live`/`dead`/`unverifiable` with no
compile-time link (FR4, AC11); (4) a denominator that gates state — now sharper, because a
project-scoped credential makes a self-derived denominator *look* correct while being
structurally blind (resolved by the declared floor plus the repo-internal pin).

**Product/UX Gate — NONE.** The mechanical UI-surface override was evaluated against Files to
Create/Edit: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or
any UI-surface term. Ops emails, issue bodies and a runbook are operator-facing text, not
product surfaces.

**Finance / COO:** no new recurring vendor expense.

**Legal / GDPR:** the canonical regex does not match; trigger (b) fires (`single-user
incident`), so the gate was run rather than skipped. The *artifacts* this change writes are
credential material and Doppler config names — no personal data. But the gate must be scoped to
the credential's **reach**, not the artifacts: `soleur/prd` root holds
`SUPABASE_SERVICE_ROLE_KEY`, so the credential resolves bypass-RLS read of all user data, and
this change publishes a repository-level sink for it. That is a change to the access-control
surface over regulated data, which is what `hr-gdpr-gate-on-regulated-data-surfaces` targets.

**The v3 assessment's premise is dead and the conclusion is re-derived, not inherited.** v3
concluded "no new Article 30 row, because `DOPPLER_TOKEN_PRD` grants the identical reach — the
surface is duplicated, not widened." At this shape the surface **is** widened: the credential
reads four environments, `DOPPLER_TOKEN_PRD` reads one.

Re-derived assessment: still **no new processing activity and no new Article 30 row**, on
different grounds. The regulated-data reach is `SUPABASE_SERVICE_ROLE_KEY` in `prd` root, which
`DOPPLER_TOKEN_PRD` already exposes to the same set of repository workflows; the widening is
over *non-prd* environments, and `dev` is a distinct Supabase project
(`hr-dev-prd-distinct-supabase-projects`), so it adds no new category of personal data, no new
purpose, no new recipient and no new retention. What changed is the number of credentials that
resolve the existing production reach — a security fact, handled by the dual-revocation
obligation in `## User-Brand Impact` — not a processing fact. Recording the reasoning rather
than the conclusion, because "the artifacts contain no personal data" is a false negative in
the understating direction, and because the v3 conclusion would have been *right by accident*
if carried over unexamined.

---

## Open Code-Review Overlap

- **#7098** (`run:` bodies whose `set` omits `-e`) matches `apps/web-platform/infra`.
  **Acknowledge** — a repo-wide audit; folding it in would balloon a credential change into a
  56-site sweep. This change edits one existing `run:` body (FR7) that already begins
  `set -euo pipefail`, and FR7 explicitly accounts for that difference.
- **#3829**, **#2197** — matched a coarse path token only; no overlap. **Acknowledge.**

---

## Acceptance Criteria

Every criterion is a command whose output decides it.

### Pre-merge (PR)

- **AC1 — the four resources have the chosen shape, with the right attribute names.** In
  `apps/web-platform/infra/token-drift-service-account.tf`, all whitespace-tolerant because
  `terraform fmt` realigns `=` when any attribute is added:
  `grep -cE '^resource "doppler_service_account" "token_drift"'` = 1;
  `grep -cE '^resource "doppler_project_member_service_account" "token_drift"'` = 1;
  `grep -cE '^resource "doppler_service_account_token" "token_drift"'` = 1;
  `grep -cE '^\s*project\s*=\s*"soleur"'` = 1; `grep -cE '^\s*role\s*=\s*"viewer"'` = 1;
  `grep -cE '^\s*name\s*=\s*"token-drift-ci-tf"'` = 2 (the account and the token);
  `grep -cE '^\s*secret_name\s*=\s*"DOPPLER_TOKEN_DRIFT"'` = 1;
  `grep -cF 'doppler_service_account_token.token_drift.api_key'` = 1 **and**
  `grep -cE '\.token_drift\.key\b'` = **0** — `api_key`, not `key`.
- **AC2 — no rotation suppression, documentation allowed.**
  `grep -cE '^\s*(lifecycle|ignore_changes)' apps/web-platform/infra/token-drift-service-account.tf`
  = 0. Comment lines explaining the absence are required by FR1 and must not fail this.
- **AC3 — all four addresses are in the default allow-list, and only there.** For each of
  `doppler_service_account.token_drift`,
  `doppler_project_member_service_account.token_drift`,
  `doppler_service_account_token.token_drift` and `github_actions_secret.doppler_token_drift`:
  `awk 'NR>=465 && NR<=575' .github/workflows/apply-web-platform-infra.yml | grep -cF -- '-target=<addr>'`
  = 1, and the whole-file `grep -cF` = 1, so none appears in a dispatch block. `-F` because `.`
  is a metacharacter. The membership leg is the load-bearing one: without it the account and
  token are created and published with no project grant.
- **AC4 — the parity gate passes by inclusion, not exclusion.**
  `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes **and**
  `grep -c 'token_drift' plugins/soleur/test/terraform-target-parity.test.ts` = 0.
- **AC5 — the swap is wired and the floor is declared exactly once.** The `token_drift` step's
  `env:` sets `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DRIFT }}`, contains no `DOPPLER_CONFIG:`,
  contains no reference to `secrets.DOPPLER_TOKEN` (the swap is literal, not a union), sets
  `DOPPLER_CONFIGS_FLOOR: 13`, and its `run:` writes `coverage=unknown`/`verdict=unavailable`
  before failing when that value is unset, empty or unparseable. `grep -c 'DOPPLER_TOKEN_ENVS'`
  over `.github/` and `scripts/` = 0 — the union's credential-iteration surface is gone, not
  left dormant.
- **AC6 — single-credential behaviour is preserved, asserted at the detector.** Producer test P1
  passes: with `--configs-floor` and `--inventory` both absent, the human report and exit code
  are byte-identical to the merge-base's for the same fixture, and the JSON is a superset.
  Additionally
  `git diff origin/main...HEAD -- .github/workflows/reusable-release.yml .github/actions/cf-tunnel-ssh-bridge/action.yml`
  is empty — three-dot, so a sibling PR advancing `origin/main` cannot fail this.
- **AC7 — the falsified claims are gone from every site.**
  `grep -rcE 'branch configs inherit' .github/workflows/scheduled-terraform-drift.yml scripts/check-cloudflare-token-drift.sh`
  = 0 on both (the pattern omits "from" deliberately — two of the sites say "inherit it", and a
  literal including "from" matches only the low-severity filer); and
  `grep -rc 'project-scoped read token' .github/workflows/scheduled-terraform-drift.yml` = 0 —
  the falsified **noun**. No Doppler service *token* is project-scoped; the remedy must name the
  service account and the `viewer` membership. The v3 grep for `restores fleet-wide coverage` is
  retired: that claim is now true of the credential this change mints, so asserting its absence
  would forbid correct prose.
- **AC8 — the retired states are gone from executable positions, repo-wide.**
  `grep -rn "multi-config\|== 'single-config'\|== 'full'" .github/ scripts/ plugins/soleur/test/ knowledge-base/engineering/operations/runbooks/`
  returns 0 matches outside `#`-prefixed comment lines. The runbook scope is load-bearing:
  `ci-ssh-token-replace.md:87` names `coverage: multi-config` as a step's exit condition.
- **AC9 — the ladder derives three states, and only three.** Producer fixtures prove: 13 configs
  read at floor 13 → `at-floor`; 14 read at floor 13 (legitimate growth) → **also** `at-floor`,
  ratio above 1, no state change; 7 read at floor 13 → `degraded`; unparseable `configs` (`-1`,
  `-2`, `None`, `abc`, `null`, empty, field-shift) → `unknown`. And
  `grep -oE '"coverage": *"(at-floor|degraded|unknown)"' <emitted JSON across fixtures> | sort -u | wc -l`
  = 3.
- **AC10 — an empty credential is `degraded`, not exit 2, not a silent success.**
  Producer test: `DOPPLER_TOKEN=""` with `--configs-floor 13` yields `configs=0`,
  `configs_floor=13`, `coverage=degraded`, `coverage_ratio=0/13`, exit code unchanged from the
  clean case, and **no** ambient fallback — the stub CLI fails loudly if invoked without an
  explicit credential.
- **AC10b — the three narrowings each produce `degraded` with a distinguishing ratio.**
  Producer fixtures at floor 13: an enumeration returning 0 (N1) → `0/13`; 7 names all in the
  `prd` environment (N2) → `7/13` with `configs_unread` naming the other six; 1 name (N3) →
  `1/13`. Plus the subtle N1: 13 names enumerated but every `--only-names` read failing →
  `configs=0`, **not** 13, because the count is of configs read rather than listed.
- **AC11 — the existing JSON contract is intact.** A `python3 -c` assertion over the producer
  suite's emitted JSON confirms `{live,dead,unverifiable,probes,configs,stale,unverifiable_keys}`
  is a subset of the top-level keys with unchanged types, and the three-field parse used by
  `apply-web-platform-infra.yml` and `cf-tunnel-ssh-bridge/action.yml` is re-run against it and
  succeeds.
- **AC12 — the two email caveats are present, two in number, and identical.**
  `grep -cP '<em>Scan coverage:' .github/workflows/scheduled-terraform-drift.yml` = **2** and
  `grep -oP '<em>Scan coverage:.*?</em>' … | sort -u | wc -l` = 1, and that span contains
  `coverage_ratio`. The raw count is load-bearing: `sort -u | wc -l` alone returns 1 when one
  span has been deleted.
- **AC13 — the filer updates rather than freezes.** The filer's `run:` contains `gh issue edit`
  with `--body-file`, contains no `create-only, not commenting` short-circuit on the
  existing-issue path, and still contains no `gh issue comment`.
- **AC14 — the close arm's condition is reachable.** The close step's `if:` contains
  `coverage == 'at-floor'`, and AC9's `at-floor` fixture demonstrates a producer for it.
- **AC15 — the filer covers every non-`at-floor` state, positively.** The filer `if:` contains
  `always()`, `== 'degraded'` and `== 'unknown'`, and no `coverage !=`.
- **AC16 — the detector rejects an unknown flag.** Producer test: an unrecognised argument exits
  2 with a named message. Today `:91`'s `*) shift ;;` swallows it, so a typo'd `--inventory` or
  `--configs-floor` degrades the scan with no signal.
- **AC17 — the orphan sweep no longer suppresses its own failure, and does not abort silently.**
  In the `_cfgs=` statement: `2>/dev/null` and `|| true` are both absent from the whole
  statement — not merely from one physical line, since they currently sit on adjacent lines and
  a same-line test passes on unmodified code — the status is captured explicitly rather than
  left to `set -e`, and the sweep's issue body contains a line naming the unperformed
  scratch-config half.
- **AC18 — the inventory gates nothing.** Within the detector function that computes `coverage`,
  `grep -cE 'configs_expected|inventory'` = 0; the inventory appears only in the ratio,
  unread-list and age computations. Reinforced by producer test P7.
- **AC19 — the inventory is a dated, generator-documented measurement.**
  `apps/web-platform/infra/doppler-config-inventory.txt` begins with a `# generated:` line
  parsing as ISO-8601 and dated 2026-08-03, contains a `# command:` line, and
  `grep -cE '^[a-z0-9_]+$'` = 13 — the same 13 the topology probe (G) returned.
- **AC20 — anti-vacuity floors were raised to named integers.** The consumer suite's floor
  literal reads `>= 37` (from 28) and the producer suite's `>= 68` (from 53), matching the
  assertion counts those suites run. Both suites currently pass at *exactly* their floor, so
  the raise is forced. Named integers, not "at least the number added" — the floors count
  assertions, and most listed cases are rewrites. The retarget adds four producer cases (P2b,
  P5b, P5c, P7b) and three consumer assertions (the AC29.3 floor pin) on top of the v3 counts;
  if the realized `PASS + FAIL` total exceeds these literals, the literals are raised to match
  rather than left low.
- **AC21 — the ADR for this change exists.**
  `git diff --name-only origin/main...HEAD -- knowledge-base/engineering/architecture/decisions/`
  lists exactly one new file, and that file's `## Decision` section contains the literals
  `declared floor, reported ratio` and `project-scoped service account`.
- **AC22 — the full suite is green by its own invocation.** `bash scripts/test-all.sh` passes —
  run as that command, not as a hand-enumerated subset of the suites it discovers.
- **AC23 — the doc lint is green over the gate's own scope.**
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- **AC29 — the floor cannot be silently lowered, and it is pinned against the inventory.**
  Three assertions, and the third is the CI check FR8 names:
  1. The `token_drift` step's `run:` asserts `configs_floor >= 13` and downgrades to `degraded`
     when it fails.
  2. A consumer-suite case sets the floor to `1`, runs the step logic, and asserts the state is
     **not** `at-floor`.
  3. The consumer suite reads `DOPPLER_CONFIGS_FLOOR` out of
     `.github/workflows/scheduled-terraform-drift.yml`, asserts it parses as an integer `>= 13`
     (a named integer in the test, not "at least what is there"), and asserts it **equals**
     `grep -cE '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt`. No
     credential, no network.
- **AC30 — no scanned value reaches a sink, and the widened-reach disclosure is present.**
  Producer test P11 passes across all six sinks; and the new `.tf` header contains the literals
  `ghcr_minter`, `GITHUB_APP_PRIVATE_KEY`, `DOPPLER_TOKEN_PRD` and `viewer`, **and** a sentence
  stating the credential is wider than `DOPPLER_TOKEN_PRD`, so the escalation hops and the
  withdrawn no-new-capability claim are stated at the resource rather than only in the plan.
  `grep -c 'no new capability' apps/web-platform/infra/token-drift-service-account.tf` = 0 —
  the v3 sentence must not survive a copy-paste from a sibling file.
- **AC31 — scanned values are masked in the run log.** The detector emits one `::add-mask::`
  line per distinct scanned value when `GITHUB_ACTIONS=true`, asserted by producer test P14.
  Actions auto-masks only `secrets.*` values, so without this every `CF_API_TOKEN*` the
  detector reads is unmasked in the job log.
- **AC32 — the ambient credential and config cannot be reached after the snapshot.**
  `grep -cE '^\s*unset DOPPLER_TOKEN DOPPLER_CONFIG' scripts/check-cloudflare-token-drift.sh`
  = 1, and producer test P15 passes.
- **AC33 — the grant is exactly as narrow as it was chosen to be, and no narrower.** In
  `apps/web-platform/infra/token-drift-service-account.tf`:
  `grep -cE '^\s*workplace_role\s*='` = 0, `grep -cE '^\s*environments\s*='` = 0 (project-wide,
  per the 2026-08-03 census), and `grep -cE '^\s*workplace_permissions\s*=\s*\[\]\s*$'` = **1**
  — an explicitly EMPTY list, never a populated one. Each is required to be explained by an
  adjacent comment, asserted by `grep -c 'deliberately unset'` >= 2 — an unexplained absence
  reads as an oversight to the next reader and invites a "fix".

  **Amended 2026-08-03, at implementation.** This AC originally required
  `workplace_permissions` to be ABSENT (= 0), alongside `workplace_role`. That is
  unsatisfiable: the pinned `DopplerHQ/doppler v1.21.2` enforces `ExactlyOneOf` on the pair.
  With neither set, `terraform validate` fails `"one of workplace_permissions,workplace_role
  must be specified"`; with both, `"Invalid combination of arguments"`. Verified by mutating
  the as-written file and re-running `validate` (fails), then restoring (passes) — not from
  the schema dump, which lists both as merely `optional` because `ExactlyOneOf` is
  provider-side validation and does not appear in `providers schema -json`.

  The design intent is unchanged and is what the assertion now pins: an empty list is the
  least-privileged satisfying value — zero workplace-wide permissions, and no assumption about
  the workplace-role vocabulary (a different endpoint, never measured here) — so the project
  membership remains this identity's only grant. The `\[\]\s*$` anchor is load-bearing: it
  fails the moment anyone adds an entry, which a bare `= 1` count would not catch.
- **AC34 — `expires_at` is absent by decision.**
  `grep -cE '^\s*expires_at\s*=' apps/web-platform/infra/token-drift-service-account.tf` = 0,
  and the header contains the literal `expires_at` in the prose explaining why (FR1). The
  absence is asserted so the choice is auditable rather than inferred from silence.

### Post-merge

The infra run is gated on the `web-platform-infra-apply` environment. AC24–AC28 are evaluated
after that gate releases; they are automatic in the sense that no command is typed for them, not
in the sense that they need no approval.

- **AC24 — all four resources are created, and the membership is one of them.** The infra run
  for the merge commit reports `4 to add, 0 to change, 0 to destroy`, limited to
  `doppler_service_account.token_drift`,
  `doppler_project_member_service_account.token_drift`,
  `doppler_service_account_token.token_drift` and `github_actions_secret.doppler_token_drift`
  (`gh run view <id> --log`). A run reporting `3 to add` is a **failure**, not a partial
  success: the missing one is almost certainly the grant.
- **AC25 — the secret is published.**
  `gh secret list --json name -q '.[].name' | grep -c DOPPLER_TOKEN_DRIFT` = 1.
- **AC26 — the first scan after the credential lands reports `at-floor` at 13/13.** The
  `discoverability_test` command returns a line containing `configs: 13`, `floor: 13`,
  `coverage: at-floor`, `ratio: 13/13`. This is also the live proof that the project membership
  landed at full breadth — a token published without its grant, or with `environments` scoped,
  cannot produce this line.
- **AC27 — the fan-out gain is checked where it is observable.** The same run's detector
  *report* line lists **13** config names under `configs scanned:`, and its Access-service-token
  count is `>= 2` naming both `CI_SSH_ACCESS_TOKEN` and `REGISTRY_PUSH_ACCESS_TOKEN` — the
  latter is the *first* case the detector's own header cites as motivating it and was not
  scanned at all before this change. Asserted as a floor with both families named rather than
  as an exact integer, because the fleet-wide distinct count was not measured; asserted against
  the report line, not the verdict line, because the verdict line does not carry it.
- **AC28 — the coverage channel ends in the closed state.** Any `token-drift-coverage` issue open
  at merge (none existed at plan time; the filer's first-ever run is the 18:00 UTC run on
  2026-08-02) has had its body rewritten by the filer rather than frozen, and the
  `Close the coverage issue once the declared floor is met` step auto-closes it with a comment
  naming `at-floor` and `13/13`. This is the #7159 checklist's Done-when, satisfied literally.

---

## Test Scenarios

### Producer suite — `scripts/check-cloudflare-token-drift.test.sh`

| Case | Asserts |
|---|---|
| P1 | `--configs-floor` and `--inventory` both absent → report text and exit code byte-identical to the merge-base's; JSON a superset with the seven existing keys unchanged in name and type |
| P2 | a 13-config enumeration at floor 13 → `configs=13`, `config_names` sorted, `configs_floor=13`, `coverage=at-floor`, `coverage_ratio=13/13` |
| P2b | a **14**-config enumeration at floor 13 (legitimate growth, C7) → still `at-floor`, ratio above 1, no state flip and no warning arm — the `>=` rather than `==` guard |
| P3 | each per-config read passes an explicit `-c <cfg>` matching the config being graded, across all four read sites — a stub fails loudly when the config argument is absent or wrong; mutation check: shuffle the config passed at one site and confirm P3 goes red |
| P4 | `DOPPLER_TOKEN` unset or empty → `configs=0`, `coverage=degraded`, ratio `0/13`, exit code unchanged, and **no** ambient fallback (the stub fails loudly if invoked with no explicit credential) |
| P5 | a non-empty credential enumerating nothing → exit 2 with enumeration stderr visible, and `emit_json` already written |
| P5b | **the three narrowings.** 0 enumerated (N1) → `0/13`; the 7 `prd*` names (N2) → `7/13` with the other six in `configs_unread`; 1 name (N3) → `1/13`. All `degraded`. |
| P5c | **N1's subtle form.** 13 names enumerated, every `--only-names` read failing → `configs=0`, not 13 — the count is of configs *read*. Mutation check: count listings instead and confirm P5c goes red. |
| P6 | `configs_unread` = inventory minus read, sorted; `coverage_ratio` = `13/13`; `inventory_age_days` parsed from the `# generated:` header |
| P7 | a short inventory (2 names) changes `coverage_ratio` to `13/2` and changes **nothing else** — `coverage` stays `at-floor`, no state flips, no arm fires. The regression guard for the rejected gating design, and the direct test of "the denominator reports, it does not gate". |
| P7b | a **long** inventory (20 names) yields `13/20` and `coverage=at-floor` — the floor, not the inventory, decides. The inventory cannot manufacture `degraded` any more than it can manufacture `at-floor`. |
| P8 | a missing or unparseable inventory → ratio absent with a caveat; `coverage` still derived from the floor |
| P9 | the credential value never appears in any child-process argv (the stub receives no `--token`) |
| P10 | an unrecognised argument exits 2 with a named message |
| P11 | **sentinel sweep across every sink.** Inject a sentinel credential value, run every mode (`--json`, `--json-file`, human report, empty-credential, revoked-credential, unknown-flag) and assert the sentinel appears in none of: stdout, stderr, the JSON payload, the `--json-file` on disk, `$GITHUB_OUTPUT`, or the rendered issue/email body fixtures. P9 covers one sink of six; this covers the rest, and the new emitted fields and un-swallowed stderr are exactly what makes it necessary |
| P12 | a bogus credential's stderr does not contain the credential value (the `2>/dev/null` removal hands a CLI a bad secret and lets it speak) |
| P13 | a failed read records the **config name**, never any secret value |
| P14 | under `GITHUB_ACTIONS=true` every distinct scanned value is emitted as `::add-mask::` before the first probe — exercised at 13 configs, not 1 |
| P15 | after the credential is snapshotted, `DOPPLER_TOKEN` and `DOPPLER_CONFIG` are unset — a read site that forgets its `-c` fails loudly instead of binding the ambient config |

### Consumer suite — `plugins/soleur/test/token-drift-workflow-causes.test.sh`

Rewrites of T6, T7, T8, T8b, T13, T13b, T14, T14b, T14c, T14d, T16, T16b, T17, T19 against the
three-state vocabulary. New cases: the filer edits an existing issue rather than
short-circuiting; a `degraded` body carries the unread config names and the ratio; the close arm
fires only on `at-floor`; the DEAD email and DEAD issue bodies no longer carry the falsified
remedy; both `<em>Scan coverage:` spans exist and are identical; the step's `DOPPLER_TOKEN` is
sourced from `secrets.DOPPLER_TOKEN_DRIFT` and `secrets.DOPPLER_TOKEN` appears nowhere in the
step; the step guards an unset/empty/unparseable `DOPPLER_CONFIGS_FLOOR` by writing outputs
before failing; and **the floor pin** — `DOPPLER_CONFIGS_FLOOR` parses, is `>= 13`, and equals
the inventory's name count (AC29.3, the CI check FR8 relies on).

### Guards that must stay green

`plugins/soleur/test/terraform-target-parity.test.ts`;
`plugins/soleur/test/terraform-drift-step-order.test.sh` (its `step_index` helper does a
`grep -n -F -- "      - name: $1"`, so adding steps is safe and renaming the four pinned
reporting steps is not); `tests/scripts/test-destroy-guard-counter-web-platform.sh`;
`scripts/lint-orphan-test-suites.sh`.

---

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/token-drift-service-account.tf` | FR1 — the three Doppler resources plus the Actions secret |
| `apps/web-platform/infra/doppler-config-inventory.txt` | FR8 — 13 names, report only |
| `knowledge-base/engineering/architecture/decisions/ADR-160-project-scoped-service-account-and-declared-coverage-floor.md` | FR9 |
| `knowledge-base/project/specs/feat-one-shot-7159-doppler-prd-read-token-coverage/{spec,tasks,decision-challenges}.md` | planning artifacts |

No new `.test.sh`. (`plugins/soleur/test/*.test.sh` is auto-discovered by
`scripts/test-all.sh`; `scripts/*.test.sh` needs an explicit `run_suite` line or
`scripts/lint-orphan-test-suites.sh` reds CI.)

## Files to Edit

| Path | Change |
|---|---|
| `scripts/check-cloudflare-token-drift.sh` | FR3, FR4, FR6.10 — the config loop, unknown-flag rejection, explicit `-c <cfg>` at all four read sites, read-not-listed counting, `--configs-floor`, `--inventory`, the ladder, `emit_json`, the falsified remedy at `:629` |
| `.github/workflows/scheduled-terraform-drift.yml` | FR5, FR6, FR7 — including the `DOPPLER_TOKEN` swap onto `secrets.DOPPLER_TOKEN_DRIFT` and the new `DOPPLER_CONFIGS_FLOOR: 13` |
| `.github/workflows/apply-web-platform-infra.yml` | FR2 — four allow-list lines only |
| `knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md` | FR6.12 — the `multi-config` exit condition at `:87` |
| `apps/web-platform/infra/tunnel.tf`, `apps/web-platform/infra/workspaces-luks.tf` | FR6.16 — one-line premise correction each |
| `scripts/check-cloudflare-token-drift.test.sh` | P1–P15, floor to 62 |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` | rewrites + new cases including the AC29.3 floor pin, floor to 34 |

**Not edited, deliberately:** `.github/workflows/reusable-release.yml` and
`.github/actions/cf-tunnel-ssh-bridge/action.yml` (AC6);
`plugins/soleur/test/terraform-target-parity.test.ts` (AC4).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A per-config read binds implicitly and grades the wrong config's bytes — far more damaging at 13 configs than at 1. | P3 asserts an explicit `-c <cfg>` at all four read sites with a stub that fails loudly, plus a mutation check; FR3 unsets `DOPPLER_CONFIG` so a missed site cannot bind anything. |
| An empty `DOPPLER_TOKEN` silently rebinds to the ambient credential and reports a confident wrong answer. | FR3 never invokes the CLI with an empty credential; P4 asserts `degraded` at `0/13` and no fallback. |
| A typo'd option silently drops the inventory or the floor. | FR3 rejects unknown flags (exit 2); AC16, P10. |
| **The token is published without its grant** — a dropped membership `-target=` leg, or a partial apply ordering the token before the membership. | All four addresses in the default allow-list (AC3); an explicit `depends_on` from the token to the membership (FR1); AC24 requires `4 to add` and calls `3 to add` a failure; and the failure is fail-loud at run time as `degraded` at `0/13`. |
| `DOPPLER_CONFIGS_FLOOR` is unset, empty or unparseable, so the gate has no threshold. | The step writes `coverage=unknown`/`verdict=unavailable` before failing; AC5. |
| A new `read -r` field shifts the parse and lets `configs` receive a wrong-but-numeric value. | `configs` stays last-and-greedy, non-empty guards on every field, fallback arity in lockstep; FR5. |
| A schema change breaks the two `--only` call sites that read three fields with no compile-time link. | FR4 pins the seven existing keys; AC11 asserts a superset and re-runs both parses. |
| The merge-to-release window reds the cron twice daily. | An absent secret is a configuration fault, not a detector fault: `degraded` at `0/13`, green job, one self-clearing issue. |
| The standing issue's body freezes at whichever state filed first (dedup is label-scoped, not title-scoped). | FR6.3 makes the filer update the body; AC13, AC28. |
| A short or stale inventory misleads. | It gates nothing (AC18, P7, P7b); `inventory_age_days` bounds staleness with no credential; the inventory is *expected* to drift as `prd_git_data` and rehearsal configs appear. |
| **The floor is lowered alongside a narrowed grant, so `at-floor` survives a real regression.** | Three places must move together and the third is a test: the run-time `configs_floor >= 13` assertion, the consumer-suite named integer, and the inventory-equality pin (AC29). Defeating it requires editing a test whose only purpose is to stop that edit. |
| **A config is legitimately deleted, so the scan reds `degraded` until the floor is lowered.** | Accepted, not engineered away: a mechanism that let a shrinking live count lower its own threshold would be N1/N2/N3 with extra steps. Noisy in the safe direction. The remedy is a two-line change (floor + inventory) in the same PR that deletes the config. |
| The `viewer` role is not purely read-only — it carries `enclave_project_config_dynamic_secrets_leases_write`. | Disclosed verbatim in `## Encryption Posture` rather than elided. It is still the least-privileged role that can read secret values; the only lower role, `no_access`, has zero permissions and cannot run the scan. |
| A lost or clobbered state write on the **create** orphans a live project-wide credential in Doppler with no Terraform record — unrotatable by `-replace=`, and it accumulates on the next run. The R2 backend has no conditional writes and `use_lockfile = false`; the Actions concurrency group is the sole serializer. The "dropped `-target=` surfaces as drift" safeguard does **not** cover this: an object absent from state is invisible to `plan`, and provider v1.21.2 ships no data source that could enumerate service accounts or their tokens. | The count-asserting `live_verification` in `## Encryption Posture` is the detector for this mode; the `-replace=` path in the `.tf` header is the remedy. **This risk is strictly larger at this shape** — an orphan now reads the whole project rather than one config — and it is disclosed as such rather than carried over unchanged. |
| The credential is a repository-level secret on a public repo; the governing control is who can merge under `.github/workflows/`. `CODEOWNERS` pins that path to the operator, but its own header records the branch-protection rule enforcing CODEOWNERS review as an unfinished follow-up, and no ruleset in IaC enforces it. | Named rather than assumed. This is the same control that already governs `DOPPLER_TOKEN_PRD`, so the change does not alter it; the gap is pre-existing and is called out so a reviewer does not read "repository-scoped like every sibling" as a control. |
| The issue body and the ops emails are API payloads, so GitHub's log masking does not reach them — and the repo is public, so the coverage issue body is world-readable. | AC30 pins that those bodies carry key/config **names** and counts only, never values. `configs_unread` is a list of Doppler config names, which the committed `.tf` files already disclose. |
| ADR-160's ordinal is claimed by a sibling PR. | Provisional; the renumber sweep is named above. |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **A union of two config-scoped `doppler_service_token`s** — keep `DOPPLER_TOKEN` on `prd_terraform`, add a `prd`-root token (the v1–v3 design) | The shape this revision replaces. At N=2 the union *is* a `for_each` with the loop unrolled, so it inherits that option's cost without its generality, and it carries prd-root blast radius while still reading 2 of 13. #7159's own "Known follow-up" section warns that a 2-config scan "would go quiet while still missing the fan-out class" — which the union's `at-floor` close arm would have done. It also forced credential-iteration through the detector, a surface the chosen shape does not need at all. Its measurements survive in `## Research Reconciliation`: they are why the shape changed. |
| **`for_each` credential per config** (13 `doppler_service_token`s) | 13 credentials, 13 Actions secrets, 13 `-target=` legs and a detector that loops credentials — to obtain what one project membership obtains. Every credential is an independent rotation and revocation obligation. Rejected in the #7159 decision comment, and the union's collapse into it at N=2 is the reason the union went too. |
| Reuse of `DOPPLER_TOKEN_TF` | Rejected in the decision comment; it is a workplace-scope personal token (`variables.tf:476`) and reusing it would make the scan a consumer of the widest credential in the repo. |
| Reuse the existing `DOPPLER_TOKEN_PRD` repo secret | Not Terraform-managed, shared by six consumers, not rotatable by `-replace=`, and config-scoped to `prd` root so it reads 1 of 13. |
| A denominator that gates the state | A short inventory derives the healthy state, fires the close arm and silences the channel — fail-open in the direction the design claimed to guard. |
| A denominator taken from the scan's own credential | Structurally blind: it narrows in lockstep with the credential, so `13/13` prints forever through all three narrowings. This becomes *more* seductive at the chosen shape, because the number it prints is correct today. |
| A cross-workflow inventory verification step against live Doppler | Needs a listing credential (which narrows with the grant), reds merges on legitimate growth (C7), and re-creates the merge blocker R5 already cut. The repo-internal floor/inventory equality pin has the same defeat condition and none of the costs. |
| Asserting the credential's identity class | Detects only a swap back to a config-scoped token; green through a role downgrade and through `environments` scoping. A check that is green through two of three failure modes reads as coverage and is worse than none. |
| Pin `expected` to a constant with no provenance | Forbidden by the brief. The chosen floor is a *declared demand* with a dated census behind it and a test pinning it to the inventory — not a guess, and not the denominator. |
| Scope the membership with `environments = ["prd"]` | Would forfeit 7 scannable keys across `dev*` and `ci` (2026-08-03 census) while removing **none** of the escalation hops, which all live in `prd` root. Narrower on paper, no narrower in consequence. |

---

## Sharp Edges

- `scripts/lint-infra-no-human-steps.py` flags a human-actor token and an infra-imperative token
  on the same line, and a strong-actor line adjacent to an imperative line. `-target` followed by
  `apply` on one line is itself an imperative. Fenced code blocks are skipped; inline backticks
  are not.
- `.claude/hooks/iac-plan-write-guard.sh` blocks a set of whole-phrase framings on any write into
  `knowledge-base/project/plans` or `.../specs`. Read its pattern list in the hook before wording
  a provisioning section — quoting the banned phrases inside the plan trips the same guard, which
  is how two writes of this file were rejected.
- The coverage filer's `if:` must test **positively**. `token_drift` is gated on
  `matrix.directory == 'apps/web-platform/infra'`, so on the other matrix leg every
  `steps.token_drift.outputs.*` is the empty string and any `!=` comparison matches it.
- The filer's dedup is **label-scoped, not title-scoped** — an issue filed under one class
  suppresses every later class unless the body is rewritten.
- A Doppler service token **ignores `DOPPLER_CONFIG`**, and an **empty `--token` value** is
  treated as unset, silently rebinding to the ambient credential.
- `doppler_service_account_token` exposes its secret as **`api_key`**; every sibling
  `doppler_service_token` in this root uses `key`. Copying the sibling attribute fails at
  `terraform plan`.
- Terraform derives an edge from `doppler_service_account_token` to the *account* through
  `service_account_slug`, and **none** to the project membership. Without an explicit
  `depends_on`, a partial apply can publish a working token whose grant has not landed.
- `viewer` is the least-privileged role that can read secret values, but it is **not** purely
  read-only: it carries `enclave_project_config_dynamic_secrets_leases_write` alongside
  `enclave_project_config_dynamic_secrets_read`,
  `enclave_project_config_rotated_secrets_read` and `enclave_config_logs`. The only lower role
  is `no_access`, which has zero permissions.
- A role that can **enumerate** configs but not **read** them would satisfy a floor that counts
  listings. `configs` must count configs whose secret read succeeded.
- The gate is `configs >= floor`, not `==`. C7 says the live set grows; an equality gate would
  red the cron twice daily the first time a rehearsal config appeared.
- With a project-scoped credential, `doppler configs -p soleur` returns the true project total,
  so any self-derived denominator is satisfied by construction. The number it prints is correct
  today and structurally blind tomorrow — this is the most inviting wrong turn in the design.
- `emit_json` splits variable-length arrays on a single `"--"` argv sentinel with
  `rest.index("--")`, after five positional scalars parsed as `range(1,6)`. A third list needs a
  distinct sentinel, not another `index`.
- In the step's `read -r`, the last variable is greedy — that is what makes a field-shift
  fail-closed today. An empty field is collapsed by IFS word-splitting, so a comma-joined field
  that can be empty must never sit before `configs`.
- Both shell suites carry anti-vacuity floors counting **assertions** (`PASS + FAIL`), not cases
  — one loop over five fixtures calls `pass` once. Both currently run at exactly their floor.
- `2>/dev/null` and `|| true` on a two-line pipeline are on *different* physical lines. An AC
  testing "not on the same line" passes on unmodified code.
- The orphan-sweep block opens `set -euo pipefail`, unlike the token-drift step's
  `set -uo pipefail`. Removing `|| true` there without capturing the status aborts with no
  annotation.
- The orphan-sweep's issue filer is gated `steps.sweep.outputs.orphans != '0'`, and a
  plain-expression `if:` also carries an implicit `success()`. A finding routed into that
  filer's body reaches nothing in the steady state.
- `gh run list --status success` returns the last **healthy** run. A discoverability probe
  carrying that filter prints a green verdict line while a newer run is failing — a clean bill
  of health for a question never asked.
- Actions auto-masks only `secrets.*`-sourced values. Anything the detector reads out of
  Doppler is unmasked in the job log unless it emits `::add-mask::` itself. A future `set -x`
  would additionally render an env-prefixed `DOPPLER_TOKEN=<value>` into the log.
- `/proc/<pid>/cmdline` is world-readable; `/proc/<pid>/environ` is 0400. Env-prefix delivery
  therefore defends against a different-UID observer, not against a compromised runner where
  every step shares one UID. Do not overstate it.
- The issue body and the ops emails are API payloads, not log output, so masking does not
  reach them — and this repository is public.
- `access = "read"` on a Doppler service token is not a capability boundary when the config it
  reads contains other credentials. `soleur/prd` holds a read/write Doppler token for itself
  and the Terraform GitHub App private key.
- `plugins/soleur/test/terraform-drift-step-order.test.sh` matches step names on the literal
  `      - name: <text>`. Adding steps is safe; renaming the four pinned reporting steps is not.

---

## Plan Review Revisions

A four-agent panel (architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer,
kieran-rails-reviewer) reviewed the first draft. Changes that altered the design rather than the
prose:

- **R1 (P0).** The denominator gated the healthy state, so a short inventory would have derived
  it, fired the close arm and silenced the channel while the job stayed green. Gate and report
  are now separate: the gate uses a floor exact by construction; the inventory only reports.
- **R2 (P0).** The filer stayed create-only while its dedup key widened from 2 states to 4, and
  dedup is label-scoped rather than title-scoped, so the merge-window body — and its "do not
  widen the token" remedy — would have been pinned open permanently. The filer now updates the
  body.
- **R3 (P0).** The `full` state was unreachable by construction, making the standing issue's
  stated closing condition unsatisfiable — the regression `:357-359` already records. Replaced by
  `at-floor`, which is reachable and which satisfies the decision comment's Done-when.
- **R4 (P0).** The AC grep for the falsified inheritance remedy used a literal matching only the
  coverage filer; the two DEAD-path sites say "inherit it" without "from" and would have
  survived. AC7 now covers all sites including the detector's own report.
- **R5 (P0).** The cross-workflow inventory check rested on a credential that is not injected at
  workflow level and is a personal workplace-scope token; it would also have redded every infra
  merge once `prd_git_data` or a rehearsal config appears. Cut.
- **R6 (P1).** An empty `--token` rebinds to the ambient credential, so "a credential that
  enumerates nothing is exit 2" could not catch the empty secret it was cited to catch. Explicit
  unset/empty handling added, yielding `degraded` rather than a red cron.
- **R7 (P1).** Credentials were to be passed as `--token <value>`, exposing them in `ps`. Env
  prefix instead.
- **R8 (P1).** The ladder moved from the YAML `run:` block into the detector, removing the
  one-physical-line constraint, making states unit-testable, and giving `configs_unread` a
  producer — three consumers needed that list and no output carried it.
- **R9 (P1).** FR7 would have emitted a permanent warning on a green cron, the shape the same
  file exists to eliminate; and its AC tested a same-line condition that passes on unmodified
  code. Routed into the existing `infra-drift` channel, with the `set -euo pipefail` difference
  handled.
- **R10 (P1).** `--token-env` as a repeatable flag was replaced by the `DOPPLER_TOKEN_ENVS` env
  list, making the three single-credential call sites unchanged by construction; the detector now
  also rejects unknown flags, which the old `*) shift ;;` catch-all swallowed.
- **R11 (P1).** The `read -r` field-order, non-empty-guard and fallback-arity constraints were
  added; a comma-joined field placed before `configs` would have converted a fail-closed
  field-shift into a fail-open one.
- **R12 (P1).** `knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md:87` was
  added as a consumer — an operator runbook whose exit condition this change makes unreachable.
- **R13 (P2).** ACs repaired: AC2 no longer forbids the documentation FR1 requires; AC3 uses
  `-F`; AC6 uses a three-dot diff against the merge base; AC7 asserts the claim rather than a
  noun that evades it; AC12 adds the raw count distinguishing "identical" from "one deleted";
  AC20 names integers; AC21 uses `git diff` rather than a glob matching 54 existing ADRs; the
  post-merge section no longer claims its criteria are approval-free. `credentials` was renamed
  `configs_floor` to end a collision with "credentials verified".
- **R14 (P2).** ADR-160's provenance moved from the inheritance metadata (which describes a
  different Doppler feature) to the per-config census. The `DOPPLER_TOKEN_PRD` consumer count was
  corrected from five to six, and the source-derivation rejection was restated so it is
  reproducible.

A second deepen-plan pass (security-sentinel, observability-coverage-reviewer) then found:

- **R15 (P0).** `access = "read"` was treated as a capability boundary. `soleur/prd` root
  contains `GHCR_MINTER_DOPPLER_TOKEN` — the key of a `read/write` service token for the same
  config — and the Terraform GitHub App private key for an App with `secrets:write`. The
  credential is therefore materially equivalent to Doppler **write** on prd and to GitHub App
  administration of the repository. Both disclosure sections now name the escalation hops, and
  both name the mitigation that makes the trade-off acceptable: `DOPPLER_TOKEN_PRD` already
  carries the identical scope, so this adds no new capability — only a second copy, which
  obliges a dual revocation in incident response.
- **R16 (P1).** A revoked or expired credential took a different path from an absent one:
  non-empty, so it hit exit 2 *before* `emit_json`, publishing no coverage at all and landing
  on `unknown`, whose remedy prose is unperformable for a revoked token. `emit_json` now runs
  before every exit-2 return, and the two modes are separated.
- **R17 (P1).** The empty-`DOPPLER_TOKEN_ENVS` guard failed the step before writing outputs,
  so every consumer arm — all of which test positively — matched nothing, and the final Sentry
  check-in derives its status from a different step and still reported `ok`. The guard now
  writes `coverage=unknown` / `verdict=unavailable` first, then fails.
- **R18 (P1).** The floor is self-referential and so is blind to its own shortening: a list cut
  from two names to one yields `floor=1, scanned=1 → at-floor` and closes the issue while
  coverage regresses. An external `configs_floor >= 2` assertion and a consumer-suite pin were
  added (AC29).
- **R19 (P1).** `gh issue edit --body-file` had no error slug and no AC asserting its status is
  checked, so a failed update would freeze the issue at whichever state filed first — the very
  defect R2 introduced the update path to remove. Added `token_drift_coverage_update_failed`
  and an ops-email fallback for a dead issue channel.
- **R20 (P1).** FR7's finding was routed into a filer gated `orphans != '0'` plus an implicit
  `success()`, so in the steady state it reached nothing; and forcing that gate open would have
  filed a diagnostic under a body claiming the listed items are paying hosts. It now has its
  own step output, filer and lead.
- **R21 (P1).** The `discoverability_test` filtered `--status success`, so it returned the last
  healthy run and printed a green verdict line while a newer run was failing. Filter dropped;
  conclusion and timestamp now print alongside.
- **R22 (P1).** The argv-versus-env argument was mis-scoped: env-prefix defends against a
  different-UID observer, not a compromised runner, and the same script already places
  credential values on curl's argv — which the union widens by one. Stated accurately, and
  `::add-mask::` registration was added as the control that actually covers the log sink.
- **R23 (P1).** Ambient fallback was prevented by a test rather than by construction. The
  detector now unsets `DOPPLER_TOKEN`/`DOPPLER_CONFIG` once the map is built, so a missed read
  site fails loudly.
- **R24 (P1).** Sink coverage: P9 asserted only that no credential reaches argv. P11–P15 now
  sweep a sentinel across stdout, stderr, the JSON, the `--json-file`, `$GITHUB_OUTPUT` and the
  rendered issue/email bodies.
- **R25 (P1/P2).** The GDPR assessment was re-scoped from the artifacts to the credential's
  reach (it resolves `SUPABASE_SERVICE_ROLE_KEY`); conclusion unchanged, reasoning recorded.
  Failure mode 4's alert route was corrected to "step log only" rather than a channel that does
  not fire at `at-floor`. `live_verification` became count-asserting. The Encryption Posture
  evidence citation was split into scope-evidence and sink-evidence. An orphaned-state-write
  risk row and a repository-secret control row were added. An emergency revocation path joined
  the rotation recipe in the `.tf` header.

### Retarget — the operator's credential-shape decision (2026-08-03)

The v3 plan was presented with its measurements. The operator was asked, interactively, to
choose the credential shape and the coverage ladder, and answered both. R1–R25 above are
retained as the record of how the design got here; R26–R34 record what that decision changed.

- **R26 (shape).** UC-2 was **adopted**. The credential is a project-scoped
  `doppler_service_account` + `doppler_project_member_service_account` + a
  `doppler_service_account_token`, at `role = "viewer"`, with `environments` unset. The union is
  dropped; `doppler_service_token` is not used. #7159's option-table premise "there is no single
  project-scoped read token to mint" was falsified: true for `doppler_service_token`, false for
  `doppler_service_account` in the pinned v1.21.2 provider.
- **R27 (the swap-regression dissolves).** UC-1 existed because a prd-root service token could
  not see `prd_terraform`, so a swap dropped `CI_SSH_ACCESS_TOKEN_ID/_SECRET` and 8
  `CF_API_TOKEN*` keys. A project-scoped `viewer` reads `prd_terraform` too, so nothing is
  dropped and no union is needed. `DOPPLER_TOKEN` now points at `secrets.DOPPLER_TOKEN_DRIFT` as
  a plain swap — exactly as the #7159 checklist asked. The measurement that motivated UC-1 is
  kept; its remedy is superseded.
- **R28 (no credential iteration).** `DOPPLER_TOKEN_ENVS`, the config-to-credential map and
  every trace of multi-credential enumeration are removed. The detector loops **configs**, not
  credentials, and the four read sites take an explicit `-c <cfg>`. Simpler than both the union
  and `for_each`.
- **R29 (the floor had to be re-founded).** A project-scoped credential makes a self-derived
  denominator hold by construction, so `degraded` would have had no producer. `configs_floor`
  becomes a literal the step declares — `DOPPLER_CONFIGS_FLOOR: 13` — compared one-sidedly
  (`>=`, so legitimate growth is not a regression). The inventory keeps reporting and keeps
  gating nothing. The three narrowings it must catch are enumerated as N1/N2/N3 with the ratio
  each produces.
- **R30 (read, not listed).** `configs` counts configs whose secret read succeeded. A role that
  can enumerate but not read would otherwise satisfy the floor while measuring nothing.
- **R31 (the pin moved from names to a number).** AC29 generalises: the run-time assertion is
  `configs_floor >= 13`, the consumer suite pins the literal as a named integer, and a new third
  assertion requires it to equal the committed inventory's name count. That equality is the CI
  check that fails when floor and inventory drift apart — repo-internal, no credential, no
  network, no merge blocker on growth.
- **R32 (P0 — the blast-radius mitigation was withdrawn, not softened).** v3's "adds no new
  capability, `DOPPLER_TOKEN_PRD` already carries identical scope" is **false** at this shape:
  the new credential reads 4 environments where `DOPPLER_TOKEN_PRD` reads 1. Both disclosure
  sections were rewritten to state the widening plainly and to record it as an accepted,
  operator-chosen trade-off. The surviving mitigations are the ones that were verified: `viewer`
  cannot write secret values, no workplace role or permissions are granted, and the credential
  is Terraform-managed and `-replace=`-rotatable. `viewer`'s
  `enclave_project_config_dynamic_secrets_leases_write` is disclosed rather than elided.
- **R33 (the GDPR conclusion was re-derived).** R25's reasoning rested on "the surface is
  duplicated, not widened", which is now false. The conclusion (no new Article 30 row) survives
  on different grounds — the regulated-data reach is prd-root `SUPABASE_SERVICE_ROLE_KEY`, which
  `DOPPLER_TOKEN_PRD` already exposes to the same workflows, and `dev` is a distinct Supabase
  project — and the re-derivation is recorded so the conclusion is not right by accident.
- **R34 (schema and lifecycle details that would have failed the apply).**
  `doppler_service_account_token` exposes `api_key`, not `key` (AC1 asserts both the presence of
  one and the absence of the other). An explicit `depends_on` from the token to the membership
  closes the partial-apply window Terraform's own graph leaves open. `expires_at` is left unset,
  with the reason stated and asserted (AC34). The `-target=` allow-list grows from two legs to
  four, and AC24 treats `3 to add` as a failure because the missing leg is almost certainly the
  grant.

---

## Appendix A — the probes

Each probe creates a read-scoped credential with a 10-minute maximum age and revokes it in the
same command via an `EXIT` trap.

```bash
# A) What can a prd-ROOT read credential enumerate?
TOK=$(doppler configs tokens create probe --project soleur --config prd \
        --access read --max-age 10m --plain)
trap 'doppler configs tokens revoke "$TOK" -p soleur -c prd' EXIT
doppler configs -p soleur --json --token "$TOK"                             # -> 1 config: prd
curl -s -u "$TOK:" "https://api.doppler.com/v3/configs?project=soleur"      # -> 1, success:true
curl -s -u "$TOK:" "https://api.doppler.com/v3/environments?project=soleur" # -> []
```

```bash
# B) The dispositive census: key sets are not in a superset relation either way.
doppler secrets -p soleur -c prd --only-names --json
doppler secrets -p soleur -c prd_terraform --only-names --json
```

```bash
# C) Config metadata for all 13 configs — context only. This is the explicit cross-config
#    inheritance feature, NOT the root-to-branch behaviour, and is not cited as evidence.
curl -s -u "$CLI_TOKEN:" "https://api.doppler.com/v3/configs?project=soleur&per_page=100" \
  | python3 -c 'import json,sys; [print(c["name"], c["root"], c["inheriting"], c["inherits"]) for c in json.load(sys.stdin)["configs"]]'
```

> **Note on the probe itself.** A first attempt passed the credential as `DOPPLER_TOKEN` alongside
> `--no-read-env` and produced a confident, wrong answer (13 configs), because that flag makes the
> CLI ignore the environment and fall back to the ambient workplace credential. The corrected form
> uses `--token`. Recorded because the failure mode — a probe that measures the wrong credential
> and reads as a clean result — is precisely the class this detector exists to catch, and it
> recurs in FR3 as the empty-value hazard.

### 2026-08-03 — the probes behind the retarget

Probes A–C above stand as the record of why the v3 shape was abandoned. D–G are the
measurements the chosen shape rests on.

```bash
# D) What does the PINNED provider actually ship? Read from the v1.21.2 binary already in
#    .terraform, not from vendor docs — the lockfile is what will run.
terraform -chdir=apps/web-platform/infra providers schema -json \
  | python3 -c 'import json,sys
s=json.load(sys.stdin)["provider_schemas"]["registry.terraform.io/dopplerhq/doppler"]["resource_schemas"]
for r in ("doppler_service_account","doppler_project_member_service_account","doppler_service_account_token"):
    print(r, sorted(s[r]["block"]["attributes"]))'
```

Result, and the three facts that constrain FR1:

| Resource | Attributes |
|---|---|
| `doppler_service_account` | `name` (required), `slug` (computed), `workplace_permissions` (optional `list(string)`), `workplace_role` (optional), `id` |
| `doppler_project_member_service_account` | `project` (required), `role` (required), `service_account_slug` (required), `environments` (optional `set(string)`), `id` |
| `doppler_service_account_token` | `name` (required), `service_account_slug` (required), **`api_key` (computed, SENSITIVE)**, `expires_at` (optional), `created_at` / `slug` / `id` (computed) |

`api_key` — **not** `key` as on `doppler_service_token`. This is the transcription error most
likely to be made and is asserted against by AC1.

```bash
# E) Which project role is least-privileged while still able to READ secret values?
curl -s -u "$CLI_TOKEN:" "https://api.doppler.com/v3/projects/roles" \
  | python3 -c 'import json,sys; [print(r["identifier"], sorted(r["permissions"])) for r in json.load(sys.stdin)["roles"]]'
```

`viewer` carries `enclave_project_config_secrets_read` and does **not** carry
`enclave_project_config_secrets_write`. The only lower role, `no_access`, has zero permissions.
`viewer` additionally carries `enclave_project_config_dynamic_secrets_leases_write`,
`enclave_project_config_dynamic_secrets_read`, `enclave_project_config_rotated_secrets_read` and
`enclave_config_logs` — disclosed in `## Encryption Posture` rather than elided, because the
first of those is a write verb.

```bash
# F) Per-config census of SCANNABLE keys — the families the detector actually probes.
#    This is what justifies leaving `environments` unset rather than scoping to prd.
for c in dev dev_personal dev_scheduled ci prd prd_cla prd_ghcr prd_kb_drift_walker \
         prd_scheduled prd_terraform prd_workspaces_luks cli cli_ops; do
  n=$(doppler secrets -p soleur -c "$c" --only-names --json \
        | grep -cE '"(CF_API_TOKEN[A-Z_]*|[A-Z_]+_ACCESS_TOKEN_(ID|SECRET))"')
  printf '%s %s\n' "$c" "$n"
done
```

Result: `dev` 2, `dev_personal` 2, `dev_scheduled` 2, `ci` 1, `prd` 5, `prd_cla` 5, `prd_ghcr` 5,
`prd_kb_drift_walker` 5, `prd_scheduled` 5, `prd_terraform` 13, `prd_workspaces_luks` 5, `cli` 0,
`cli_ops` 0 — 50 occurrences, and only `cli`/`cli_ops` vacuous.

```bash
# G) Config topology — the source of the floor's value and of the inventory's 13 names.
doppler configs -p soleur --json \
  | python3 -c 'import json,sys,collections
c=json.load(sys.stdin)
print(len(c), collections.Counter(x["environment"] for x in c))'
```

Result: 13 configs across 4 environments — `dev` 3, `ci` 1, `prd` 7, `cli` 2. The `prd`
environment's 7 configs are the detector header's own motivating case ("stale in 5 of 7
configs").
