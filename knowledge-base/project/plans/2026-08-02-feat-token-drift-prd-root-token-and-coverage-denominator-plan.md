---
title: "infra: mint the prd-root read token and give the coverage ladder a denominator"
date: 2026-08-02
issue: 7159
branch: feat-one-shot-7159-doppler-prd-read-token-coverage
type: infra
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
revision: v3 (after a four-agent plan-review panel; see "Plan Review Revisions")
---

# infra: mint the prd-root read token and give the coverage ladder a denominator

> **Lane note.** No `spec.md` existed for this branch when planning began, so `lane:` could
> not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Two deliverables, one change, per the decision comment on #7159 (2026-08-02).

1. **Mint the read credential.** A read-scoped `doppler_service_token` on `soleur` / `prd`
   ROOT named `token-drift-ci-tf`, published as a dedicated `github_actions_secret`
   `DOPPLER_TOKEN_DRIFT`, consumed only by the token-drift step. Mirrors
   `apps/web-platform/infra/kb-drift.tf:92-113`: `access = "read"`, and no
   `lifecycle.ignore_changes` on `plaintext_value`, so a `-replace=` rotation propagates in
   the same run. Plus two `-target=` legs in the infra allow-list.

2. **Replace the coverage enum with a measured floor and a reported ratio.** `coverage` is
   today a 3-state enum with no denominator, so its "more than one config" state cannot
   distinguish *2 of 13* from *13 of 13*. This change takes the live count from 1 to 2 —
   exactly the case the issue flags as latent.

The credential shape is settled and is not reopened. What this plan adds is the measured
behaviour of that shape: six premises in the issue body were probed, and three of the
falsifications change the implementation.

**The `terraform apply` stays behind the environment's required-reviewer set. This plan
produces a PR.**

---

## Research Reconciliation — Spec vs. Codebase

Measured **2026-08-02** against live Doppler with ephemeral read credentials, each revoked in
the same command. Reproduce via [Appendix A](#appendix-a--the-probes).

| Claim (issue #7159 / decision comment) | Measured reality | Plan response |
|---|---|---|
| "Branch configs inherit from root, so a single credential restores the fan-out view." | A `prd`-ROOT read service token enumerates **exactly 1** config: `doppler configs -p soleur --token <root>` returns `['prd']`; raw `GET /v3/configs?project=soleur` returns 1 with `success: true` — a list silently scoped to the credential, not an error. `GET /v3/environments?project=soleur` returns `[]`. | The scan's config count equals **the number of read credentials supplied**. One credential can never yield `configs >= 2`. |
| "Point the token-drift step's `DOPPLER_TOKEN` at `secrets.DOPPLER_TOKEN_DRIFT`" (a swap). | The key sets of the two configs are **not in a superset relation in either direction**. `prd_terraform` carries 10 `CF_API_TOKEN*` keys plus `CI_SSH_ACCESS_TOKEN_ID/_SECRET`; `prd` root carries `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`. A swap **drops** the `CI_SSH_ACCESS_TOKEN` pair — the credential of the 2026-07-29 outage (ADR-154). | **Union, not swap.** Keep `DOPPLER_TOKEN`, add `DOPPLER_TOKEN_DRIFT`. Also the only reading under which the decision's own Done-when (which needs `configs >= 2`) is reachable. |
| The remedy prose "Set the live value on the `prd` ROOT config; branch configs inherit it." | Falsified by the census: `CF_API_TOKEN_DNS_EDIT` is present in 7 configs, and `prd_terraform` does **not** carry `REGISTRY_PUSH_ACCESS_TOKEN_*` that `prd` root does. Setting root alone does not repair the fan-out. | Corrected at **all five** sites (FR6). Two are on the DEAD path — the acute arm — and were missing from the first draft's consumer list. |
| "There is no single project-scoped read token to mint." | True for `doppler_service_token`. Provider `DopplerHQ/doppler v1.21.2` also ships `doppler_service_account` + `doppler_service_account_token` — a project-scoped, provider-minted identity needing no credential-entry step. Absent from the issue's 3-row option table. | Not adopted (outside the settled decision). Deferred with re-evaluation criteria; owns the residual fan-out gap. Recorded as **UC-2**. |
| The `::warning::` remedy "a project-scoped token … restores fleet-wide coverage". | False. No Doppler service token restores fleet-wide coverage. | Corrected (FR6). |
| A prd-root Actions secret does not yet exist. | `DOPPLER_TOKEN_PRD` **already exists** (prd-root, read) and is consumed by **six** workflows/actions. It is **not** Terraform-managed. `reusable-release.yml:488-490` independently documents "A Doppler service token also reads exactly ONE config and ignores `DOPPLER_CONFIG`" (the sentence wraps, so a single-line grep misses it); `tunnel.tf:273` repeats it. | The dedicated, TF-managed `DOPPLER_TOKEN_DRIFT` remains correct: single consumer, rotatable via `-replace=`. `DOPPLER_TOKEN_PRD` is not reused. |
| (Found while probing.) | `rung2-rehearsal-orphan-sweep` (same workflow file, `:1115-1116`) filters `startswith("prd_git_data_rehearsal_")` over a list its `prd_terraform` credential can only ever return one entry for. The predicate is **unsatisfiable**; the job reports "no orphans" unconditionally. | Folded in (FR7) — routed into the job's existing `infra-drift` issue channel, not a new warning on a green run. |

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
Only the union covers both Access-service-token families, and `REGISTRY_PUSH_ACCESS_TOKEN` —
the *first* case the detector's header cites as motivating it — **is not scanned at all
today**.

> **Provenance for ADR-155.** The dispositive evidence is this census, not the
> `inheriting=false / inherits=[]` metadata. That metadata describes Doppler's *explicit
> cross-config inheritance feature*, which is off everywhere, and is **not** evidence about
> the built-in environment-root-to-branch behaviour. The census is sufficient for every
> conclusion drawn here and does not depend on which mechanism explains it.
> `apps/web-platform/infra/git-data-luks.tf:53-55` carries an independent, dated, probe-verified
> enumeration of the seven `prd*` configs that corroborates the "7 (all `prd*`)" rows.

---

## How the denominator is obtained

The brief forbids a guessed constant. Five derivations were considered; four are rejected by
measurement, so they need not be re-derived downstream.

| Candidate | Result | Verdict |
|---|---|---|
| Ask Doppler with the scan's own credential | `GET /v3/configs?project=soleur` returns 1, `success: true` | **Rejected** — silently scoped |
| Ask Doppler for environments | `GET /v3/environments?project=soleur` returns `[]` | **Rejected** |
| Derive from committed source (`config = "…"` in `*.tf`, `DOPPLER_CONFIG:` in workflows, `-c <cfg>`) | 6–9 names depending on the exact source set. Either way it **misses live configs** (`ci`, `cli`, `dev_personal`, `prd_cla`, `prd_ghcr`) and **emits `prd_git_data`**, which is TF-declared (`git-data-luks.tf:79`) but verified absent from live Doppler. | **Rejected** — a short denominator flatters coverage, the unsafe direction |
| A committed inventory re-verified on every infra merge by a new step in `apply-web-platform-infra.yml` | The premise was false: `grep -nEi 'doppler_token_tf' .github/workflows/apply-web-platform-infra.yml` returns **nothing**. That credential materialises only inside the `doppler run … -- terraform` child process, and `variables.tf:476` records it as a workplace-scope **personal** token. Such a step would also red every infra merge the moment live Doppler legitimately grows — `doppler_config.git_data_prd` takes it to 14 at git-data birth, and `rung2-rehearsal/rehearsal.tf:57` creates ephemeral `prd_git_data_rehearsal_*` configs. | **Rejected** — a *new* consumer of the widest credential in the repo, which is a stronger form of the option the decision comment rejected, plus a self-inflicted merge blocker |
| Doppler Terraform provider data sources | v1.21.2 ships `doppler_environments`, `doppler_group`, `doppler_secrets`, `doppler_user` only | **Rejected** — the graph cannot publish a config list |

### Chosen: separate the *gate* from the *report*

The trap the first draft walked into is that a denominator which **gates a state** must itself
be trustworthy, and nothing available can make it so. A short inventory — one truncated to
`prd` + `prd_terraform` — would have satisfied `scanned == expected`, derived the healthy
state, fired the close arm and silenced the channel for good: a fail-open in exactly the
direction the design claimed to guard. And the live config set is *expected* to drift, by two
in-repo mechanisms named above.

So the two roles are split:

- **The gate uses a floor that is exact by construction.** `configs_floor` = the number of
  credential env-var names the step supplies. The detector knows it without asking anything
  external. `scanned < floor` means a configured credential stopped working — a real,
  producible regression. `scanned == floor` means every credential the step was given did its
  job.
- **The report uses the committed inventory, and gates nothing.**
  `apps/web-platform/infra/doppler-config-inventory.txt` carries a `# generated:` ISO-8601
  header and the generator command. It supplies `coverage_ratio` (`2/13`) and the list of
  **unread** config names for the annotation, the two ops emails and the issue body. If it
  goes short or stale, the printed ratio is wrong — and nothing else. No state changes, no arm
  starts or stops firing, no channel goes quiet.
- **Staleness is bounded without a credential.** The detector emits `inventory_age_days` from
  the header; a caveat is appended to the ratio past 90 days. Derived, no listing credential,
  strictly inside the property the decision comment protects.

This satisfies the brief — `coverage_ratio` reports `scanned/expected` rather than a 3-state
enum, and `expected` is measured rather than guessed — without letting an untrustworthy number
decide whether the operator hears anything.

---

## The new coverage ladder

`coverage` keeps its name; every consumer is in-repo and is updated in this change.

| Value | Condition | Notes |
|---|---|---|
| `unknown` | either side unparseable — the **default** | unchanged fail-closed polarity |
| `degraded` | `scanned < floor` | a configured credential is missing, empty, or stopped enumerating. **Producible and actionable.** |
| `at-floor` | `scanned == floor` | every configured credential worked |

Evaluation order is pinned: `unknown` → `degraded` → `at-floor`.

`multi-config`, `single-config` and `full` are all retired. `single-config` collapses into
`degraded` once the floor is 2. `full` would have been a state with no reachable producer
whose only consumer was the close arm — shipping it would leave the standing issue asserting a
closing condition the same plan had already decided would never occur, which is verbatim the
regression `scheduled-terraform-drift.yml:357-359` records from a previous revision.

**The close arm fires on `at-floor`.** The recurring `token-drift-coverage` issue therefore
auto-closes once both credentials work — satisfying the decision comment's Done-when — and the
residual 11-config fan-out gap is owned by exactly one artifact: the UC-2 deferred-capability
issue with its re-evaluation criteria. The coverage channel returns to signalling
*regression*, which is what it is good at, rather than a standing condition nobody can clear.

### The merge-to-release window

The workflow edits go live at merge; the credential exists only after the environment gate
releases the infra run. In that window `secrets.DOPPLER_TOKEN_DRIFT` interpolates to the empty
string. That window must not red the cron twice daily — the file's own comment
(`:346-349`) explains a standing red here would poison the DEAD arm's red signal too. So:

- A named credential variable that is **unset or empty** is a *configuration* fault: it counts
  toward `configs_floor` but not toward `configs`, yields `coverage: degraded`, reaches the
  warning and the issue channel, and leaves the job green and the detector exit code
  untouched.
- A **non-empty** credential that enumerates nothing is a *detector* fault: exit 2,
  `verdict: unavailable`, the existing DETECTOR-UNAVAILABLE email.

The window produces one `degraded` issue that self-clears to `at-floor` and auto-closes when
the credential lands.

---

## Functional Requirements

- **FR1 — the credential.** New `apps/web-platform/infra/token-drift-read-token.tf`:
  `doppler_service_token.token_drift` (`project = "soleur"`, `config = "prd"`,
  `name = "token-drift-ci-tf"`, `access = "read"`) and
  `github_actions_secret.doppler_token_drift` (`repository = "soleur"`,
  `secret_name = "DOPPLER_TOKEN_DRIFT"`,
  `plaintext_value = doppler_service_token.token_drift.key`). No `lifecycle` block on either.
  Header carries the BLAST RADIUS note (the credential reads the whole `prd` config — the
  accepted trade-off), `autonomy-considered: provider-mint-applied`, the rotation recipe, and
  the reason no `ignore_changes` is present.
  *Templates:* `apps/web-platform/infra/web-arm-write-token.tf`,
  `apps/web-platform/infra/kb-drift.tf:92-113`.

- **FR2 — the allow-list.** Both addresses added to the **default** per-merge `-target=` block
  in `apply-web-platform-infra.yml` (between the `cloudflare_ruleset.cache_shared_binaries`
  anchor at `:465` and the `betteruptime_team_member.ops` terminator at `:573`), and to no
  dispatch-job set. Neither may go in `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`
  (`terraform-target-parity.test.ts:795`) or `AUDIT_PENDING_UNCOVERED` (`:631`) — both are
  exact-string `Set<string>`, and `allTargets` is built from `stripDispatchJobs(...)`
  (`:841-849`), so inclusion in the default block is the only way to pass.

- **FR3 — multi-credential enumeration.** `scripts/check-cloudflare-token-drift.sh` takes its
  credentials from **`DOPPLER_TOKEN_ENVS`**, a whitespace-separated list of *environment-variable
  names*, defaulting to `DOPPLER_TOKEN` when unset. No new argv surface, so the three
  single-credential call sites are unchanged **by construction** rather than by care.
  - **Reject unknown flags.** The argument loop's `*) shift ;;` catch-all (`:91`) silently
    swallows a typo. Replace with an error + exit 2. Without this, a misspelling degrades the
    scan to one credential with no signal — the class this change exists to remove.
  - For each name: if the variable is unset or empty, record a failed credential and continue.
    Do **not** pass an empty `--token` — the CLI treats it as unset and silently rebinds to the
    ambient credential, so a two-credential run would dedupe to one and report success. This
    is the same failure the Appendix A footnote records from the probe itself.
  - Enumerate per credential with `doppler configs -p "$PROJECT" --json`, delivering the
    credential as an **env prefix** (`DOPPLER_TOKEN="$t" doppler …`), never as `--token <value>`
    on argv, which would expose every credential in `ps` for the length of a fleet sweep.
  - Drop the `2>/dev/null` on the enumeration (`:102`): a non-empty credential that enumerates
    nothing must be loud, and its stderr is currently swallowed.
  - Build an exact config-to-credential map (each credential returns exactly one config) and
    route **all four** downstream reads through it by env prefix: `:138`
    (`doppler secrets --only-names`), `:223`, `:505`, `:506` (`doppler secrets get`).

- **FR4 — the detector owns the ladder.** Add `--inventory <path>`; `emit_json` gains
  `config_names` (scanned, sorted), `configs_floor`, `configs_expected`, `configs_unread`
  (inventory minus scanned, sorted), `coverage`, `coverage_ratio` and `inventory_age_days`.
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
  Also: `DOPPLER_CONFIG: prd_terraform` is **removed** from the step's `env:` (`:156`) — a
  Doppler service token ignores it, and with two credentials in play it reads as "which config
  this scans". And the step **fails loudly if `DOPPLER_TOKEN_ENVS` is empty**: an unset list
  silently falls back to a floor of 1, where a single-config scan reads as `at-floor` and
  closes the issue — the same fail-open in a new place.

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
  5. Filer Remedy prose (`:461-476`) — the inheritance sentence and the fleet-wide-coverage
     promise both replaced with the measured behaviour.
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
  13. `apps/web-platform/infra/tunnel.tf:277` and
      `apps/web-platform/infra/workspaces-luks.tf:78,114` reason about credential blast radius
      from the same falsified premise. Their *conclusions* may still hold; a one-line premise
      correction each is in scope, re-deriving their blast-radius arguments is not.

- **FR7 — the sibling fail-open.** In `rung2-rehearsal-orphan-sweep`, the `_cfgs=` pipeline
  (`:1115-1116`) drops `2>/dev/null` and `|| true` and captures the status **explicitly**. The
  enclosing block opens `set -euo pipefail` (`:1085`), unlike the token-drift step's
  `set -uo pipefail`, so a bare removal would abort with no named annotation — the opposite of
  fail-loud. Because that job keeps only the `prd_terraform` credential and can never satisfy
  its own `startswith("prd_git_data_rehearsal_")` predicate, it contributes a named line to the
  **existing** `infra-drift` issue body (`:1130-1190`) recording that the scratch-config half of
  the sweep was not performed. Routing it there rather than emitting a `::warning::` on a green
  run is the point: a warning on a green cron is the shape this file's own header block
  (`:324-330`) exists to eliminate.

- **FR8 — the inventory (report only).**
  `apps/web-platform/infra/doppler-config-inventory.txt`: a `# generated: <ISO-8601>` header,
  the generator command in a comment, then the sorted config names measured on 2026-08-02. It
  feeds `coverage_ratio`, `configs_unread` and `inventory_age_days`, and **gates no state**.
  There is no cross-workflow verification step. The file is expected to drift — `git-data-luks.tf:79`
  declares a `prd_git_data` config that will exist after git-data birth, and rehearsal
  dispatches create ephemeral ones — which is precisely why it must not gate.

- **FR9 — the ADR.** `ADR-155` records the measured scope of a Doppler service token, that
  fan-out coverage scales with credential count rather than config count, the union-over-swap
  correction, and the gate-versus-report split. Provenance cites the census.

---

## Architecture Decision (ADR/C4)

**Create `ADR-155 — Fan-out coverage scales with credentials, not configs`** as an in-scope
task of this plan. It corrects reasoning currently carried in shipped comments, in the
workflow's remedy prose, in an operator runbook and in the decision comment, and it records
why the denominator may report but must not gate.

> **Ordinal.** ADR-155 is the next free ordinal (highest existing is ADR-154). **Provisional**
> — a sibling PR can claim it. On renumber, sweep this plan, the spec, the tasks file and every
> AC naming it:
> `grep -rn 'ADR-155' knowledge-base/project/{plans,specs}/feat-one-shot-7159-doppler-prd-read-token-coverage/`

Related: ADR-154, ADR-007, ADR-149.

**C4 views — no impact.** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). `doppler`
(`model.c4:238`), `github` (`:230`) and `cloudflare` (`:234`) are already modelled as external
systems and are already included in both container views (`views.c4:14`, `:36`). The change
adds no external human actor, no external system, no container or data store, and moves no
actor-to-surface access relationship — a second read credential on an existing scheduled job
sits below C4 component granularity.

---

## Infrastructure (IaC)

**Terraform changes.** `apps/web-platform/infra/token-drift-read-token.tf` (new: the resource
pair); `apps/web-platform/infra/doppler-config-inventory.txt` (new: a data file, not
Terraform); `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines). Providers
`DopplerHQ/doppler ~> 1.21` and `integrations/github` are already required and locked — no
version or lockfile change. No new Terraform variable, so no new `TF_VAR_*` precondition on the
merge-triggered run.

**Apply path.** Not host-touching, so no cloud-init and no bootstrap script. Merge to `main`
triggers the infra workflow on `apps/web-platform/infra/*.tf`; both new addresses sit in the
default allow-list; the run waits on the `web-platform-infra-apply` environment gate. Blast
radius: one Doppler service token, one repository Actions secret. Zero destroys, zero reboots,
zero host creates — the destroy-guard, reboot counter and `host_creates` tripwire all read 0.
Rotation is `-replace=doppler_service_token.token_drift`; with no `lifecycle.ignore_changes`,
the new key reaches `DOPPLER_TOKEN_DRIFT` in the same run.

**Distinctness / drift safeguards.** `dev` untouched (the credential is `prd`-scoped by
construction). The absence of `lifecycle.ignore_changes` is deliberate and explained in the
file header. `doppler_service_token.token_drift.key` is Computed + Sensitive + write-once and
lands in `terraform.tfstate` on the R2 backend. If either `-target=` line is dropped, the
twice-daily `terraform plan` surfaces the resource as unmanaged drift.

**Vendor-tier reality check.** No per-tier quota affects service-token creation on the current
plan; five already exist on the `prd` config alone, measured 2026-08-02. No new recurring
vendor expense.

---

## Encryption Posture

```yaml
at_rest:
  - store: Doppler soleur/prd config (the secret set the new credential can read)
    mechanism: vendor-managed encryption at rest (Doppler); identical posture to the five
               sibling doppler_service_token resources in this root, notably
               doppler_service_token.web_probes on the SAME config
    evidence: ADR-007-doppler-secrets-management.md; apps/web-platform/infra/web-probe-read-token.tf
    defends_against: disclosure from Doppler's storage layer
    does_not_defend: anyone holding the token value — a Doppler service token is
                     config-scoped, so this reads the WHOLE prd config; the trade-off the
                     decision comment accepts
    disclosed_as: BLAST RADIUS header block in token-drift-read-token.tf
    live_verification: "doppler configs tokens -p soleur -c prd --json | grep token-drift-ci-tf"
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
               token_drift_coverage_close_failed) plus the action-required issue channel
  fail_loud: true — every arm that cannot reach its channel emits a named ::error::; the
             detector exits 2 rather than reporting a clean fleet from a partial enumeration
failure_modes:
  - mode: a configured credential is revoked, expires, or its Actions secret is absent
    detection: scanned < floor yields coverage=degraded; the floor is exact because it counts
               the credential NAMES the step supplies, not anything the credentials report
    alert_route: ::warning:: plus the coverage action-required issue, whose body is rewritten
                 on every state transition
    layer: GitHub Actions run annotations + the GitHub issue channel harvested by
           operator-digest
  - mode: DOPPLER_TOKEN_ENVS is empty, so the floor silently collapses to 1 and a
          single-config scan reads as healthy
    detection: the step's own guard fails the step before the detector runs
    alert_route: red step with a named ::error::
    layer: GitHub Actions job status
  - mode: a non-empty credential enumerates nothing (Doppler outage, scope revoked mid-flight)
    detection: exit 2, verdict=unavailable — the enumeration stderr is no longer swallowed
    alert_route: the DETECTOR-UNAVAILABLE ops email arm
    layer: Resend ops email (notify-ops-email composite action)
  - mode: the committed inventory goes short or stale, so the reported ratio overstates
          coverage
    detection: inventory_age_days exceeds 90, appended as a caveat wherever the ratio prints
    alert_route: the same annotation and issue body that carry the ratio
    layer: GitHub Actions run annotations + the GitHub issue channel
    note: this can no longer silence anything — the inventory gates no state
  - mode: the coverage signal is derived correctly but reaches nobody
    detection: the consumer suite asserts the filer fires on every non-at-floor state, that an
               existing issue is UPDATED rather than short-circuited, and that a failed create
               or edit emits a named ::error::
    layer: CI test suite pre-merge, then GitHub Actions annotations post-merge
  - mode: the scratch-config half of the rung-2 orphan sweep is not performed
    detection: the captured status of the _cfgs= pipeline
    alert_route: a named line in the existing infra-drift orphan issue body
    layer: the GitHub issue channel
logs:
  where: GitHub Actions run logs for the Terraform Drift Detection workflow; the body of the
         standing token-drift-coverage issue
  retention: 90 days for run logs (GitHub default); issue bodies are permanent
discoverability_test:
  command: >
    gh run list --workflow=scheduled-terraform-drift.yml --status success -L 1 --json
    databaseId -q '.[0].databaseId' | xargs -I{} gh run view {} --log | grep -E 'token-drift
    verdict:'
  expected_output: >
    a line of the form "token-drift verdict: clean (detector exit 0, causes: -, configs: 2,
    floor: 2, coverage: at-floor, ratio: 2/13)"
```

No SSH anywhere in the verification path.

**Soak follow-through enrollment: not applicable.** No acceptance criterion is time-gated.

**Affected-surface observability:** a GitHub Actions runner surface, fully inspectable via
`gh run view --log`. Not a sandbox, readiness gate or cron worker, so the in-surface-probe
extension does not fire.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a production deploy that cannot happen. The
detector is on the critical path of five workflows (ADR-154). Implemented as a swap,
`CI_SSH_ACCESS_TOKEN` stops being scanned; the next rotation of that credential outside
Terraform goes undetected and every remote write path to the production host dark-fails — the
measured 2026-07-29 outcome, where the product served a stale build for roughly 63 hours while
every dashboard read green. Implemented with a gating denominator, a short inventory silences
the channel entirely while the job stays green.

**If this leaks, the user's data and workflow are exposed via:** the new `DOPPLER_TOKEN_DRIFT`
value. A Doppler service token is config-scoped, so anything holding it reads the entire
`soleur/prd` config — the production application's whole secret set, including database
credentials. Vectors: the repository Actions secret (readable by any workflow in the repo), the
Terraform state object in R2, and the runner process during the scan. FR3 keeps credential
values out of argv so they are not additionally exposed to other processes on the runner.

**Brand-survival threshold:** `single-user incident`.

`requires_cpo_signoff: true` is set; `user-impact-reviewer` runs at review time; the review
panel escalates to include `architecture-strategist` and `spec-flow-analyzer`; and every
acceptance criterion below asserts the invariant rather than a proxy.

---

## Domain Review

**Domains relevant:** Engineering (CTO).

**Engineering (CTO) — reviewed.** Four risks dominate, each with a named mitigation: (1)
swap-versus-union, a measured coverage regression (FR3); (2) the config-to-credential map,
which must be exact so no per-config read falls back to an ambient credential (FR3, test P3);
(3) detector JSON schema stability, since two other call sites read `live`/`dead`/`unverifiable`
with no compile-time link (FR4, AC11); (4) a denominator that gates state, resolved by the
gate/report split.

**Product/UX Gate — NONE.** The mechanical UI-surface override was evaluated against Files to
Create/Edit: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or
any UI-surface term. Ops emails, issue bodies and a runbook are operator-facing text, not
product surfaces.

**Finance / COO:** no new recurring vendor expense.

**Legal / GDPR:** the canonical regex does not match. Trigger (b) fires (`single-user
incident`), so the gate was considered rather than skipped: the change processes zero personal
data — the artifacts are credential material and Doppler config *names*. No new processing
activity, no Article 30 row, nothing for `compliance-posture.md`.

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

- **AC1 — the resource pair has the settled shape.** In
  `apps/web-platform/infra/token-drift-read-token.tf`: `grep -cE '^\s*config\s*=\s*"prd"$'` = 1,
  `grep -cE '^\s*name\s*=\s*"token-drift-ci-tf"'` = 1, `grep -cE '^\s*access\s*=\s*"read"'` = 1,
  `grep -cE '^\s*secret_name\s*=\s*"DOPPLER_TOKEN_DRIFT"'` = 1. Whitespace-tolerant, because
  `terraform fmt` realigns `=` when any attribute is added.
- **AC2 — no rotation suppression, documentation allowed.**
  `grep -cE '^\s*(lifecycle|ignore_changes)' apps/web-platform/infra/token-drift-read-token.tf` = 0.
  Comment lines explaining the absence are required by FR1 and must not fail this.
- **AC3 — both addresses are in the default allow-list, and only there.**
  `awk 'NR>=465 && NR<=575' .github/workflows/apply-web-platform-infra.yml | grep -cF -- '-target=doppler_service_token.token_drift'`
  = 1 and the same for `github_actions_secret.doppler_token_drift`; and the whole-file `grep -cF`
  for each = 1, so neither appears in a dispatch block. `-F` because `.` is a metacharacter.
- **AC4 — the parity gate passes by inclusion, not exclusion.**
  `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes **and**
  `grep -c 'token_drift' plugins/soleur/test/terraform-target-parity.test.ts` = 0.
- **AC5 — the union is wired, nothing was swapped away, and the floor cannot silently collapse.**
  The `token_drift` step's `env:` contains both `secrets.DOPPLER_TOKEN` and
  `secrets.DOPPLER_TOKEN_DRIFT`, contains no `DOPPLER_CONFIG:`, sets `DOPPLER_TOKEN_ENVS` naming
  both variables, and its `run:` fails the step when `DOPPLER_TOKEN_ENVS` is empty.
- **AC6 — single-credential behaviour is preserved, asserted at the detector.** Producer test P1
  passes: with `DOPPLER_TOKEN_ENVS` unset, the human report and exit code are byte-identical to
  the merge-base's for the same fixture, and the JSON is a superset. Additionally
  `git diff origin/main...HEAD -- .github/workflows/reusable-release.yml .github/actions/cf-tunnel-ssh-bridge/action.yml`
  is empty — three-dot, so a sibling PR advancing `origin/main` cannot fail this.
- **AC7 — the falsified claims are gone from every site.**
  `grep -rcE 'branch configs inherit' .github/workflows/scheduled-terraform-drift.yml scripts/check-cloudflare-token-drift.sh`
  = 0 on both (the pattern omits "from" deliberately — two of the sites say "inherit it", and a
  literal including "from" matches only the low-severity filer); and
  `grep -rc 'restores fleet-wide coverage' .github/workflows/scheduled-terraform-drift.yml` = 0
  (the claim, not the noun — `:466` says "project-scoped read token" and would evade a
  `project-scoped token` literal).
- **AC8 — the retired states are gone from executable positions, repo-wide.**
  `grep -rn "multi-config\|== 'single-config'\|== 'full'" .github/ scripts/ plugins/soleur/test/ knowledge-base/engineering/operations/runbooks/`
  returns 0 matches outside `#`-prefixed comment lines. The runbook scope is load-bearing:
  `ci-ssh-token-replace.md:87` names `coverage: multi-config` as a step's exit condition.
- **AC9 — the ladder derives three states, and only three.** Producer fixtures prove: two
  credentials both enumerating → `at-floor`; one of two empty → `degraded`; unparseable
  `configs` (`-1`, `-2`, `None`, `abc`, `null`, empty, field-shift) → `unknown`. And
  `grep -oE '"coverage": *"(at-floor|degraded|unknown)"' <emitted JSON across fixtures> | sort -u | wc -l`
  = 3.
- **AC10 — an empty credential variable is `degraded`, not exit 2, not a silent success.**
  Producer test: `DOPPLER_TOKEN_ENVS="A B"` with `B` empty yields `configs=1`, `configs_floor=2`,
  `coverage=degraded`, exit code unchanged from the clean case, and **no** ambient fallback for
  `B`.
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
  2 with a named message. Today `:91`'s `*) shift ;;` swallows it, so a typo'd option degrades
  the scan with no signal.
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
  parsing as ISO-8601, contains a `# command:` line, and `grep -cE '^[a-z0-9_]+$'` = 13.
- **AC20 — anti-vacuity floors were raised to named integers.** The consumer suite's floor
  literal reads `>= 34` (from 28) and the producer suite's `>= 62` (from 53), matching the
  assertion counts those suites run. Both suites currently pass at *exactly* their floor, so
  the raise is forced. Named integers, not "at least the number added" — the floors count
  assertions, and most listed cases are rewrites.
- **AC21 — the ADR for this change exists.**
  `git diff --name-only origin/main...HEAD -- knowledge-base/engineering/architecture/decisions/`
  lists exactly one new file, and that file's `## Decision` section contains the literal
  `credential count, not config count`.
- **AC22 — the full suite is green by its own invocation.** `bash scripts/test-all.sh` passes —
  run as that command, not as a hand-enumerated subset of the suites it discovers.
- **AC23 — the doc lint is green over the gate's own scope.**
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.

### Post-merge

The infra run is gated on the `web-platform-infra-apply` environment. AC24–AC28 are evaluated
after that gate releases; they are automatic in the sense that no command is typed for them, not
in the sense that they need no approval.

- **AC24 — the resources are created.** The infra run for the merge commit reports
  `2 to add, 0 to change, 0 to destroy`, limited to `doppler_service_token.token_drift` and
  `github_actions_secret.doppler_token_drift` (`gh run view <id> --log`).
- **AC25 — the secret is published.**
  `gh secret list --json name -q '.[].name' | grep -c DOPPLER_TOKEN_DRIFT` = 1.
- **AC26 — the first scan after the credential lands reports `at-floor` at 2/13.** The
  `discoverability_test` command returns a line containing `configs: 2`, `floor: 2`,
  `coverage: at-floor`, `ratio: 2/13`.
- **AC27 — the credential-count gain is checked where it is observable.** The same run's detector
  *report* line contains `Access service tokens: 2` (up from 1) — the `REGISTRY_PUSH_ACCESS_TOKEN`
  family is now in scope. Asserted against the report line, not the verdict line, because the
  verdict line does not carry it.
- **AC28 — the coverage channel ends in the closed state.** Any `token-drift-coverage` issue open
  at merge (none existed at plan time; the filer's first-ever run is the 18:00 UTC run on
  2026-08-02) has had its body rewritten by the filer rather than frozen, and is closed by the
  close arm with a comment naming `at-floor` and the ratio.

---

## Test Scenarios

### Producer suite — `scripts/check-cloudflare-token-drift.test.sh`

| Case | Asserts |
|---|---|
| P1 | `DOPPLER_TOKEN_ENVS` unset → report text and exit code byte-identical to the merge-base's; JSON a superset with the seven existing keys unchanged in name and type |
| P2 | two credential names, two distinct single-config enumerations → `configs=2`, `config_names` sorted, `configs_floor=2`, `coverage=at-floor` |
| P3 | each per-config read uses the credential that enumerated **that** config, across all four read sites — a stub fails loudly on the wrong credential; mutation check: swap the map and confirm P3 goes red |
| P4 | a named variable unset or empty → `degraded`, exit code unchanged, **no** ambient fallback for that name |
| P5 | a non-empty credential enumerating nothing → exit 2 with enumeration stderr visible |
| P6 | `configs_unread` = inventory minus scanned, sorted; `coverage_ratio` = `2/13`; `inventory_age_days` parsed from the header |
| P7 | a short inventory (2 names) changes `coverage_ratio` to `2/2` and changes **nothing else** — `coverage` stays `at-floor`, no state flips. The regression guard for the rejected gating design. |
| P8 | a missing or unparseable inventory → ratio absent with a caveat; `coverage` still derived from the floor |
| P9 | credential values never appear in any child-process argv (the stub receives no `--token`) |
| P10 | an unrecognised argument exits 2 with a named message |

### Consumer suite — `plugins/soleur/test/token-drift-workflow-causes.test.sh`

Rewrites of T6, T7, T8, T8b, T13, T13b, T14, T14b, T14c, T14d, T16, T16b, T17, T19 against the
three-state vocabulary. New cases: the filer edits an existing issue rather than
short-circuiting; a `degraded` body carries the unread config names; the close arm fires only on
`at-floor`; the DEAD email and DEAD issue bodies no longer carry the falsified remedy; both
`<em>Scan coverage:` spans exist and are identical; the step guards an empty
`DOPPLER_TOKEN_ENVS`.

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
| `apps/web-platform/infra/token-drift-read-token.tf` | FR1 |
| `apps/web-platform/infra/doppler-config-inventory.txt` | FR8 |
| `knowledge-base/engineering/architecture/decisions/ADR-155-fan-out-coverage-scales-with-credentials-not-configs.md` | FR9 |
| `knowledge-base/project/specs/feat-one-shot-7159-doppler-prd-read-token-coverage/{spec,tasks,decision-challenges}.md` | planning artifacts |

No new `.test.sh`. (`plugins/soleur/test/*.test.sh` is auto-discovered by
`scripts/test-all.sh`; `scripts/*.test.sh` needs an explicit `run_suite` line or
`scripts/lint-orphan-test-suites.sh` reds CI.)

## Files to Edit

| Path | Change |
|---|---|
| `scripts/check-cloudflare-token-drift.sh` | FR3, FR4, FR6.10 — credential list, unknown-flag rejection, config-to-credential map across all four read sites, the ladder, `emit_json`, the falsified remedy at `:629` |
| `.github/workflows/scheduled-terraform-drift.yml` | FR5, FR6, FR7 |
| `.github/workflows/apply-web-platform-infra.yml` | FR2 — two allow-list lines only |
| `knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md` | FR6.12 — the `multi-config` exit condition at `:87` |
| `apps/web-platform/infra/tunnel.tf`, `apps/web-platform/infra/workspaces-luks.tf` | FR6.13 — one-line premise correction each |
| `scripts/check-cloudflare-token-drift.test.sh` | P1–P10, floor to 62 |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` | rewrites + new cases, floor to 34 |

**Not edited, deliberately:** `.github/workflows/reusable-release.yml` and
`.github/actions/cf-tunnel-ssh-bridge/action.yml` (AC6);
`plugins/soleur/test/terraform-target-parity.test.ts` (AC4).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A per-config read falls back to an ambient credential and grades the wrong config's bytes. | P3 across all four read sites with a stub that fails loudly, plus a mutation check. |
| An empty `--token` silently rebinds to the ambient credential, so a two-credential run dedupes to one and reports success. | FR3 never passes an empty credential; P4 asserts `degraded` and no fallback. |
| A typo'd option degrades the scan to one credential with no signal. | FR3 rejects unknown flags (exit 2); AC16, P10. |
| `DOPPLER_TOKEN_ENVS` goes empty, collapsing the floor to 1 so a single-config scan reads healthy. | The step fails loudly before the detector runs; AC5. |
| A new `read -r` field shifts the parse and lets `configs` receive a wrong-but-numeric value. | `configs` stays last-and-greedy, non-empty guards on every field, fallback arity in lockstep; FR5. |
| A schema change breaks the two `--only` call sites that read three fields with no compile-time link. | FR4 pins the seven existing keys; AC11 asserts a superset and re-runs both parses. |
| The merge-to-release window reds the cron twice daily. | An absent secret is a configuration fault, not a detector fault: `degraded`, green job, one self-clearing issue. |
| The standing issue's body freezes at whichever state filed first (dedup is label-scoped, not title-scoped). | FR6.3 makes the filer update the body; AC13, AC28. |
| A short or stale inventory misleads. | It gates nothing (AC18, P7); `inventory_age_days` bounds staleness with no credential; the inventory is *expected* to drift as `prd_git_data` and rehearsal configs appear. |
| ADR-155's ordinal is claimed by a sibling PR. | Provisional; the renumber sweep is named above. |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Swap `DOPPLER_TOKEN` for `DOPPLER_TOKEN_DRIFT` as the checklist reads | Measured regression: drops the `CI_SSH_ACCESS_TOKEN` pair, and can never reach `configs >= 2`, making the decision's own Done-when unreachable. |
| A denominator that gates the state | A short inventory derives the healthy state, fires the close arm and silences the channel — fail-open in the direction the design claimed to guard. |
| A cross-workflow inventory verification step | Premise false (the credential is not injected at workflow level and is a personal workplace-scope token), and it would red every infra merge once live Doppler legitimately grows. |
| `for_each` credential per config; reuse of `DOPPLER_TOKEN_TF` | Rejected in the decision comment. |
| Reuse the existing `DOPPLER_TOKEN_PRD` repo secret | Not Terraform-managed, shared by six consumers, not rotatable by `-replace=`. |
| `doppler_service_account` + `doppler_service_account_token` | Outside the settled decision; would deliver true fleet coverage and an exact denominator. **Deferred with re-evaluation criteria** (UC-2); owns the residual 11-config gap. |
| Pin `expected` to a constant | Forbidden by the brief; the repo-grep derivation that looked like a middle path was falsified by measurement. |

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
- **R14 (P2).** ADR-155's provenance moved from the inheritance metadata (which describes a
  different Doppler feature) to the per-config census. The `DOPPLER_TOKEN_PRD` consumer count was
  corrected from five to six, and the source-derivation rejection was restated so it is
  reproducible.

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
> recurs in FR3 as the empty-`--token` hazard.
