---
title: "infra: split Terraform credentials into a branch-reachable tier and a main-only tier, and evict the four privileged credentials from Doppler prd_terraform"
date: 2026-09-22
slug: feat-evict-privileged-terraform-credentials
branch: feat-one-shot-8209-evict-prd-terraform-secrets
issue: 8209
closes: []
refs: [8209, 6167, 8189, 8211, 8385, 8093]
type: security
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# infra: evict the repo-secret-reachable Terraform credentials from `prd_terraform`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec or brainstorm exists
for this branch; the one-shot path entered `plan` directly.

## Overview

Any workflow on any branch of this public repository can name the `DOPPLER_TOKEN` repo secret, and
that token reads Doppler `soleur/prd_terraform`. That config holds four credentials that reach far
past Terraform: `DOPPLER_TOKEN_TF` (a workplace personal token that reads every Doppler project,
including the isolated `soleur-git-data-root`), `CF_API_TOKEN_R2` (account-wide R2), `HCLOUD_TOKEN`
(read/write Hetzner, which is root on any host through rescue, rebuild or a volume re-attach) and
`GITHUB_APP_PRIVATE_KEY`. Two more paths reach the git-data root key: the repo secret
`DOPPLER_TOKEN_GIT_DATA_ROOT`, and the state object
`web-platform/git-data-root-key/terraform.tfstate`, which the `prd_terraform` R2 backend keys read.

This plan does three things:

1. It records the decision in a new ADR (**ADR-241, provisional ordinal**). Credentials are split
   into two tiers. **Tier A** holds whatever a branch workflow can reach, and it keeps only
   credentials whose disclosure is bounded. **Tier B** holds write and root-equivalent credentials.
   It is delivered only as **GitHub environment secrets** on environments whose deployment-branch
   policy admits `main` only.
2. It ships the **code half** of the migration. Every consumer works in both the *before* state
   (credentials still in `prd_terraform`) and the *after* state (credentials only in Tier B). That
   makes the PR safe to merge before any operator step.
3. It prepares the **operator half** as an ordered runbook. Each step has an exact command, a
   read-only verification and a rollback. Nothing irreversible is executed by the agent or the
   pipeline.

**This PR does not close #8209 by itself.** Measurement found a residual that the issue did not
name. The soleur-ai App's *runtime* private key lives in Doppler `prd`. `DOPPLER_TOKEN_PRD` and every
`prd_*` branch-config repo secret can read it. The App holds `administration:write` on
`jikig-ai/soleur`, so a holder can rewrite any environment's deployment-branch policy, and that
defeats the Tier-B boundary. The PR references #8209 with `Ref #8209`. Closing #8209 needs this PR,
the operator runbook, **and** the residual issue filed in this plan (R1).

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Measured reality (2026-09-22) | Plan response |
|---|---|---|
| "`prd_terraform` holds `GITHUB_APP_PRIVATE_KEY`" | True, and more. `prd_terraform` is a **branch config of `prd`** (`doppler configs -p soleur`: `prd_terraform root=false env=prd`). It *overrides* the key with a **distinct private key of the same soleur-ai App** (sha256 prefixes of the two values differ; a JWT signed with the `prd_terraform` key authenticates as `slug=soleur-ai`). The App has **3 installations, 2 of them outside `jikig-ai`**. | The Terraform copy is a separate, revocable App key. Terraform moves to a dedicated infra App and the soleur-ai Terraform key is deleted in the App settings (operator, last). The runtime key in `prd` is out of this PR's reach; it becomes residual **R1**. |
| "Evict these four credentials from any config a branch workflow can name" | `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2` and `HCLOUD_TOKEN` exist **only** in `prd_terraform` (not in `prd`), so deleting them there evicts them. `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` are also in `prd`, which `prd_terraform` inherits. | Three are evicted by deletion. For the App key, `prd_terraform` gets a sentinel override (`EVICTED_SEE_ADR_241`), and R1 tracks the `prd` copy. |
| "The PR plan job needs these credentials" (implicit in "changes every plan/apply workflow") | Measured locally with Terraform 1.10.5 against the web-platform root: `terraform plan -refresh=false` succeeds with a **placeholder** `doppler_token_tf`, a **placeholder** `cf_api_token_r2`, a GitHub **token** (no App) and a real Hetzner token. The root's only data sources are `hcloud_server_type` ×2 and `hcloud_ssh_keys`. A full-refresh plan reads `15 to add, 3 to change, 6 to destroy`. The `-refresh=false` plan reads `14/3/6`. The **only** difference is one drifted address (`github_repository_environment_deployment_policy.web_platform_infra_apply_main`), which is live drift and the drift job's concern. | The PR plan (Tier A) runs `-refresh=false`, with a **read-only** Hetzner token, placeholders for the Doppler and R2 providers, and the workflow's own `GITHUB_TOKEN` for the GitHub provider. |
| "The Terraform App cannot write environment secrets — 403" | `gh api /orgs/jikig-ai/installations`: soleur-ai has `administration:write` and `secrets:write` but **no `environments` permission**, which is consistent with the 403 on `environments/<env>/secrets/public-key`. | A dedicated infra App gets `environments:write`. Until it is live, Tier-B environment secrets are seeded by the operator. A follow-up issue moves them to IaC. |
| "The `prd_terraform` R2 backend keys read the git-data root-key state" | True. Listing `soleur-terraform-state` with those keys returns all 7 state objects, including `web-platform/git-data-root-key/terraform.tfstate`. `ListBuckets` returns `AccessDenied`, so the keys are **bucket-scoped** (they are not account-wide). | Move that one state object into a new bucket. A **bucket-scoped** R2 token for that bucket is held only in Tier B. The Tier-A keys cannot reach a bucket they are not scoped to. |
| (not in issue) Tier-A **write** path | `DOPPLER_TOKEN_WRITE` (repo secret) is `read/write` on `soleur/prd_terraform` (`doppler-write-token.tf`). Tier-B jobs run `doppler run -c prd_terraform`, and **Doppler values override existing env vars by default**. A branch actor could therefore plant `HCLOUD_TOKEN=<their own account>` in `prd_terraform`, and a Tier-B apply would plan against it. | (a) Every `doppler run` in a Tier-B job carries `--preserve-env`, so the loader's values win **by construction**. This was measured with a sentinel: bare `--preserve-env` and `--preserve-env=TF_VAR_hcloud_token` keep the environment value; the source name `HCLOUD_TOKEN` does not; and there is no `DOPPLER_PRESERVE_ENV` variable form. (b) `DOPPLER_TOKEN_WRITE` becomes a Tier-B environment secret. Its consumers are already Tier-B jobs. |
| "Reviewer-gated environment on main" is the boundary | `web-platform-infra-apply`, `inngest-cutover` and `sentry-infra-apply` have a `main` branch policy. **`workspaces-luks-cutover` and `inngest-config-signing` have none** (`deployment_branch_policy: null`), so a branch run with reviewer approval passes. | The census asserts that every environment holding a Tier-B secret has a Terraform-declared `main` policy. `workspaces-luks-cutover` gains one. |
| Doppler service accounts / OIDC as the mechanism | The workplace is on the Developer plan. Service-account identities need Team or Enterprise (ADR-220 amendment; vendor docs). | Rejected for now as a cost decision (see Alternatives). The environment-secret design is plan-agnostic, and a Doppler upgrade later replaces only the carrier. |

## Research Insights

### Premise Validation (Phase 0.6)

- #8209: OPEN. Cited blockers and relations: #8189 CLOSED (delivered the root-key root and the repo
  secret this plan re-scopes), #8211 OPEN (parallel session, WIP PR #8564 with no files yet),
  #8210 CLOSED, #7226 CLOSED (host keys pinned, ADR-237), #6167 OPEN (branch-config
  non-isolation, the home of residual R1's class).
- Cited artifacts exist on `origin/main`:
  - `apps/web-platform/infra/git-data-root-key/` (access.tf, key.tf, main.tf, variables.tf);
  - `.github/workflows/apply-git-data-root-key.yml`;
  - `tests/scripts/test-git-data-root-token-census.sh`;
  - `apps/web-platform/infra/inngest-arm-write-token.tf` (the 403 note at lines 107-117).
- Mechanism against the ADR corpus:
  - ADR-220's amendment already **rejected** OIDC for now (Developer plan) and **took the
    repo-secret fallback**, naming #8209 as the eviction.
  - ADR-130 says no credential can mint a bucket-scoped R2 token programmatically, so the new
    bucket token is operator-minted.
  - ADR-065 requires TF variables to exist before an IaC merge. Every new variable here has a
    default of `""`, so a merge before provisioning does not fail.
  - ADR-231 caps workflow files at 490,000 bytes. `apply-web-platform-infra.yml` measures
    **482,443 bytes**, so there are 7,557 bytes of headroom and every edit to that file is
    byte-budgeted (see Phase 4).
  - ADR-168 says a service token errors loudly on a `-c` mismatch.
  - ADR-228 governs generated operator scripts.
- No stale premise. One premise is **incomplete**: the issue's acceptance cannot be met while the
  soleur-ai runtime key is repo-secret-reachable (R1).

### Property List (Phase 0.6b)

- **P1.** No workflow run that has not passed an environment whose deployment-branch policy admits
  only `main` can obtain `DOPPLER_TOKEN_TF`, a read/write Hetzner token, `CF_API_TOKEN_R2`, or a
  GitHub App key Terraform uses for writes.
- **P2.** The same holds for `DOPPLER_TOKEN_GIT_DATA_ROOT`.
- **P3.** The same holds for the git-data root-key state object.
- **P4.** No branch workflow can change the *credentials* or the *state* that a Tier-B Terraform
  run uses. That covers substitution through a Tier-A-writable config, and state forged with a
  Tier-A read/write backend key (R7, folded in on the CTO and architecture reviews).
- **P5.** Apply-on-merge, dispatch jobs and the drift check keep working in both the before and the
  after state. The PR is safe to merge before any operator step.
- **P6.** The PR-time plan comment is preserved for every root.
- **P7.** A regression is caught at PR time. The census catches what the repository can see: a new reference to a Tier-B secret from a job not bound
  to a main-only environment, a Tier-B environment without a `main` policy, or a Tier-B name
  re-added to `prd_terraform`.
- **P8.** The decision, its residuals and its statuses are recorded in an ADR and in C4.

### Cut List (Phase 0.6b)

- **Doppler Team plan + OIDC service-account identities** → P1 → the environment-secret design
  already buys P1 on the current plan. It is deferred as a cost decision, not required.
- **A dedicated "read-only plan" GitHub App** → P6 → the workflow's own `GITHUB_TOKEN` in token
  mode is enough for a `-refresh=false` plan (measured).
- **A read-only Doppler token for the PR plan** → P6 → it does not exist on the Developer plan, and
  a `-refresh=false` plan never calls the Doppler API (measured with a placeholder).
- **A read-only R2 token for the PR plan** → P6 → a `-refresh=false` plan never calls R2 through
  `cloudflare.r2` (measured with a placeholder).
- **Per-environment distinct privileged tokens** → P1 → one token set on N environments meets P1.
  Per-environment tokens only refine revocation granularity.
- **Moving Terraform-managed environment secrets to IaC in this PR** → P1 → it is blocked by the
  403 until the infra App exists. It is deferred to a follow-up issue, filed in the work phase.

### Measurements taken for this plan (all read-only; no value printed)

| # | Probe | Result |
|---|---|---|
| M1 | `doppler configs -p soleur --json` | `prd_terraform` is a branch of `prd` |
| M2 | Secret-name diff `prd_terraform` vs `prd` (`--only-names`) | `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2`, `HCLOUD_TOKEN`, `AWS_*` only in `prd_terraform`; `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` in both |
| M3 | sha256 prefix compare of the App key in both configs | differ |
| M4 | App JWT signed with the `prd_terraform` key → `GET /app` | `slug=soleur-ai` |
| M5 | `GET /app/installations` (counts only) | 3 installations, 2 outside `jikig-ai` |
| M6 | `gh api /orgs/jikig-ai/installations` | soleur-ai: `administration:write, secrets:write, actions:write, contents:write, organization_projects:write`, no `environments`. The Doppler App: `environments:write, secrets:write` on selected repos |
| M7 | R2 `ListBuckets` / `ListObjectsV2` with `prd_terraform` `AWS_*` | `AccessDenied` / 7 keys incl. `web-platform/git-data-root-key/terraform.tfstate` |
| M8 | `terraform plan -refresh=false` with placeholders + `GITHUB_TOKEN`-shaped token (TF 1.10.5, scratch copy) | rc=0, `14/3/6` |
| M9 | Full-refresh plan with real credentials | rc=0, `15/3/6`; the one-address difference is drift |
| M10 | `gh api repos/.../environments` | policies listed in the reconciliation table; no environment holds a secret today |
| M11 | `wc -c` of the workflows | `apply-web-platform-infra.yml` 482,443 B; `infra-validation.yml` 147,561 B |
| M12 | `DOPPLER_TOKEN` consumers | 38 jobs across 19 workflows name `secrets.DOPPLER_TOKEN`. Per-job tier classification is Phase 1's deliverable |

### Relevant files

- Workflows that consume the four credentials (from the per-job inventory):
  - `.github/workflows/apply-web-platform-infra.yml`: jobs `apply`, `inngest_host`,
    `inngest_host_replace`, `inngest_volume_recut`, `registry_host_replace`,
    `registry_region_migrate`, `registry_pull_path_gate`, `registry_luks_recut`,
    `git_data_host_replace`, `workspaces_luks_cutover`, `workspaces_luks_recut`, `web_host_create`,
    `web_host_replace`, `git_data_host_create`, `ci_ssh_token_replace`, `vector_redeliver`,
    `entrypoint_audit`;
  - `apply-deploy-pipeline-fix.yml::apply`, `apply-github-infra.yml::apply`,
    `apply-git-data-root-key.yml::apply`, `git-data-rung2-rehearsal.yml::rehearse`;
  - `scheduled-terraform-drift.yml`: `drift-check`, `heartbeat-live-reconcile`,
    `rung2-rehearsal-orphan-sweep`;
  - `workspaces-luks-cutover.yml::cutover` (a Hetzner read only);
  - `infra-validation.yml::plan` (PR);
  - `board-status-sync.yml::sync` (PR/issues, App key);
  - `build-inngest-bootstrap-image.yml::bump-cloud-init-pin` (App key via
    `.github/actions/mint-soleur-ai-app-token`).
- Terraform: `apps/web-platform/infra/main.tf` (providers at lines 78-120), `variables.tf`
  (`hcloud_token`:15, `cf_api_token_r2`:417, `doppler_token_tf`:602, `github_app_private_key`:653),
  `github-app.tf:40-65` (the `doppler_secret` mirrors), `doppler-write-token.tf:40-60`,
  `web-host-birth-environment.tf:53-80` (the precedent for an environment plus a `main` policy),
  `workspaces-luks.tf:271`, `git-data-root-key/{main,access}.tf`, `rung2-rehearsal/main.tf`,
  `infra/github/main.tf:20-40`.
- Census precedent: `tests/scripts/test-git-data-root-token-census.sh`. It is registered in
  `scripts/test-all.sh:2570` and matches secret names case-insensitively, including
  `toJSON(secrets)`.
- The #8211 session owns these files, and this plan edits none of them:
  - `.github/workflows/git-data-cutover.yml`;
  - `apps/web-platform/infra/git-data-cutover.sh` and the cutover, rollback and wipe scripts;
  - `.github/workflows/git-data-pin-redeploy.yml`.

  `git-data-cutover.yml` still gets `DOPPLER_TOKEN_GIT_DATA_ROOT` after the move with no edit. Its
  job declares `environment: web-platform-infra-apply`, and an environment secret overrides a repo
  secret of the same name.

### Institutional learnings applied

- `learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`: the
  Tier-B carrier is a **project**, not a `prd_*` branch config.
- `2026-03-29-doppler-service-token-config-scope-mismatch.md` and ADR-168: mis-bound tokens error
  loudly, so the loader passes an explicit `-p/-c`.
- `2026-03-21-ci-terraform-plan-workflow.md` and `2026-03-21-doppler-tf-var-naming-alignment.md`:
  - backend `AWS_*` stays plain-named;
  - `--name-transformer tf-var` renames every key;
  - Doppler-fetched values need `::add-mask::` (per line for a PEM).
- `2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum.md`: a secret created mid-run is
  empty in that run. `read/write` is the literal access enum.
- `2026-05-15-token-namespace-divergence-across-secret-stores.md`: never reason from a secret's
  name, so the tiering inventory is by measured config and access.
- `2026-09-14-read-a-never-completed-rotation-script-before-firing-it.md`: every operator step is
  written end to end with its verify step, and the tail (revocations) is not left implied.
- `best-practices/2026-06-17-operator-supplied-doppler-secret-cite-github-app-not-inngest.md`: the
  Tier-B values are operator-supplied, so cite `github-app.tf` as the precedent.
- `2026-05-16` secret-sweep inventory learning: scheduled and dispatch-only consumers are part of
  the blast radius. The inventory is derived from every workflow file, never from a list.

### CLI verification (Phase 6 gate)

- `doppler run --preserve-env` exists; verified locally with `doppler run --help`: "a comma
  separated list of secrets for which the existing value from the environment ... should take
  precedence".
- `doppler secrets set` accepts stdin; verified with `doppler secrets set --help`
  ("1) stdin (recommended)", `--no-interactive`, `--silent`).
- `doppler configs tokens create <name> -p -c --access read --plain` and `gh secret set <NAME> --env
  <env> -R <repo>` (the body is read from stdin when it is not a TTY) are cited from vendor
  references. The work phase re-verifies both with `--help` before the runbook is committed.

## Decision (ADR-241 content)

- **D1. Two tiers.**
  - **Tier A** is branch-reachable: repo secrets and every Doppler config a repo-secret token
    reads. It holds only credentials whose disclosure is bounded: read-only, placeholder, or
    bucket-scoped to the non-privileged state bucket.
  - **Tier B** is main-only. It holds every credential that writes infrastructure, reads another
    tier's secrets, or reaches third-party installations.
- **D2. The boundary is a GitHub environment secret on an environment whose deployment-branch
  policy is `main` only.** This holds whether or not the environment also has required reviewers.
  A new environment, **`infra-privileged`**, has the `main` policy and no reviewers. It serves the
  unattended Tier-B jobs (apply-on-merge, scheduled drift). Jobs that already declare a
  reviewer-gated environment keep it. That environment then carries the same Tier-B secret and
  **must** have a `main` policy.
- **D3. Carrier.** A new Doppler **project**, `soleur-infra-privileged` (config `prd`), holds:
  - `DOPPLER_TOKEN_TF`;
  - `HCLOUD_TOKEN` (read/write);
  - `CF_API_TOKEN_R2`;
  - `GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_INSTALLATION_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY`;
  - `GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID` and `GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY` (the
    bucket name is not secret, so it is a literal in code);
  - `TF_STATE_AWS_ACCESS_KEY_ID` and `TF_STATE_AWS_SECRET_ACCESS_KEY`: the **read/write** key for
    `soleur-terraform-state` (R7, folded in).

  Its read service token is the environment secret `DOPPLER_TOKEN_INFRA_PRIVILEGED`. Terraform
  creates the project and environment, which carry no secret. Terraform never mints the token or
  the values, because anything the web-platform root mints lands in a state object that Tier A
  reads.
- **D4. Tier-A substitutes.**
  - `prd_terraform` `AWS_*` becomes a **read-only**, bucket-scoped key for
    `soleur-terraform-state` (O5b). The read/write key moves to Tier B as `TF_STATE_AWS_*`. PR
    plans only read state, so a branch can no longer forge state that a later `main` apply acts
    on.
  - It gains `HCLOUD_TOKEN_READONLY`, a Hetzner Read-permission token. It is a **different name**,
    so it can never shadow the Tier-B value.
  - It loses `DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN` and `CF_API_TOKEN_R2`.
  - It gets a **sentinel override** for `GITHUB_APP_PRIVATE_KEY` (`EVICTED_SEE_ADR_241`), which
    shadows the inherited `prd` runtime key for the Tier-A token. A sentinel is used instead of an
    empty value because the CTO review flagged that Doppler might treat an empty branch-config
    value as "inherit". A non-empty non-PEM value cannot be mistaken for either inheritance or a
    usable key.
  - The PR plan runs `-refresh=false` with placeholders for the Doppler and R2 providers and the
    GitHub provider in token mode.
- **D5. GitHub identity.**
  - Terraform authenticates through a mode chosen by which variables are non-empty. The infra App
    is used when `github_infra_app_private_key` is set. Token mode is used when
    `github_plan_actions_credential` is set (PR plan). The legacy soleur-ai key is used otherwise, which is the
    before state only.
  - The dedicated App `soleur-infra` is installed on `jikig-ai` only, on the selected repositories
    Terraform manages. Its permissions are derived from the resource types Terraform manages,
    `environments:write` included.
  - It also mints the pin-bump PR token (a push-to-`main` job, Tier B). **Board sync does not use
    it.** Board sync runs on `pull_request`/`issues` and stays Tier A with a separate
    least-privilege App, `soleur-board` (`organization_projects:write` plus the read scopes its
    GraphQL queries need). Its key goes in `prd_terraform`, and a leak reaches only the org project
    board. This follows the CTO and advisor reviews: giving an admin-capable App to a
    fork-triggerable `pull_request_target` job was the largest new attack surface in the draft.
  - The soleur-ai key used by Terraform is deleted in the App settings after the switch.
- **D6. Integrity.**
  - Every `doppler run` in a Tier-B job carries `--preserve-env`, so values the loader exported
    take precedence over any same-named `prd_terraform` value. Under tf-var, every Doppler key
    becomes `TF_VAR_*`, and the only `TF_VAR_*` in a Tier-B job's environment are the loader's, so
    "all" is exactly "the loader's". This makes the before and after states identical. Deleting
    the names from `prd_terraform` (O10) becomes hygiene, not a correctness condition, and a later
    same-named secret in `prd` cannot shadow Tier B. The census enforces the flag.
  - `DOPPLER_TOKEN_WRITE` (read/write on `prd_terraform`) moves to Tier B, which removes the only
    measured Tier-A write path into `prd_terraform`.
  - The loader checks the auth mode in shell before any plan. When `source=tier_b`, it requires
    `TF_VAR_github_infra_app_private_key` to be non-empty. HCL cannot precondition a provider.
    The provider's ambient-token fallback cannot trigger, because the `dynamic "app_auth"` block
    is present whenever `token` is null (a composite action cannot unset a variable for later
    steps, so the plan relies on this construction instead).
- **D7. git-data root-key custody.**
  - `DOPPLER_TOKEN_GIT_DATA_ROOT` becomes an environment secret on `web-platform-infra-apply` under
    the **same name**, so the #8211-owned `git-data-cutover.yml` is untouched.
  - The Terraform-minted token and the repo secret are forgotten by Terraform, then revoked and
    deleted by the operator.
  - The root's state moves to a new bucket, `soleur-terraform-state-privileged`, that only a Tier-B
    bucket-scoped token reads.
- **D8. Census.** One CI suite, run on every PR, asserts P7 over every workflow and composite
  action.
- **D9. Residuals.** These are recorded in the ADR with a status each. They are not accepted as
  closed.
  - **R1.** The soleur-ai runtime key in `prd` is readable by `DOPPLER_TOKEN_PRD` and by every
    `prd_*` branch-config repo secret. The App has `administration:write` on `jikig-ai/soleur`, so a
    holder can rewrite an environment's branch policy, which defeats D2. It can also use
    `contents:write` and its ruleset-bypass listing to change scripts that `main` jobs run.
    **Until R1 closes, D2 stops a branch workflow from naming a Tier-B secret. It does not stop an
    actor who already holds a `prd` repo-secret token.** Residual R1 gets a new issue at
    **`priority/p1-high`, `type/security`**. It is ranked on its own risk (the runtime key reaches
    two third-party installations **today**), not only as a cutover precondition. It is marked as
    blocking #8211 and the first real git-data cutover, and D2 stays `proposed` until R1 closes
    (CPO condition).
  - **R2.** Web-platform root state is Tier-A readable and holds other TF-minted secrets. That is
    pre-existing and ADR-220 accepted it. The two `doppler_secret.github_app_*` mirrors are removed
    from state here.
  - **R3.** Tier-B dry runs (for example `workspaces-luks-cutover` in dry-run mode) can no longer
    run from a branch ref. A branch-ref Tier-B dispatch is exactly the reach this ADR closes.
  - **R4.** The PR plan does not show live drift. `scheduled-terraform-drift.yml` (Tier B) owns
    drift.
  - **R5.** The four credentials were branch-reachable in a public repository before this change.
    Moving them does not revoke copies taken earlier. **Rotation (O13) is required**, following the
    CPO sign-off condition. #8209 cannot close until O13's checks pass. O13 is ordered last only
    because each old value must stay valid until its replacement is proven.
  - **R6.** The Tier-B environment secrets are operator-seeded until the infra App makes them IaC.
    A follow-up issue tracks that. Its target design comes from the terraform-architect review:
    keep `doppler_service_token.git_data_root_read` in the (by then Tier-B) root-key state, and
    publish it with `github_actions_environment_secret` under the infra App.
  - **R7 (folded in; closed at O5b).** Before this change, the Tier-A backend keys
    (`prd_terraform` `AWS_*`) are **read/write** on `soleur-terraform-state`. A branch actor could
    therefore tamper with web-platform state, for example by swapping a
    `doppler_service_token.key` that a later `main` apply publishes. The fix is D4's read-only
    Tier-A key plus `TF_STATE_AWS_*` in Tier B. Every "Extract backend credentials" step in a
    Tier-B job reads `${TF_STATE_AWS_ACCESS_KEY_ID:-<prd_terraform value>}`, which is the same
    both-states pattern as `HCLOUD_TOKEN`. Every **writer** of `soleur-terraform-state` must be
    Tier B before O5b. The Phase 1 inventory enumerates the writers, including
    `apply-sentry-infra.yml::apply` (sentry state lives in the same bucket), and any other root
    whose backend is that bucket (`cla-evidence`, `telegram-bridge`: their credential source is
    verified in the inventory). The CTO and the architecture review both required this in-PR; see
    decision-challenges DC-1 (resolved).

## Implementation Phases (code — this PR)

### Phase 1 — Guard first: tier census and inventory (write before code)

1. Create `tests/scripts/test-infra-privileged-tier-census.sh`, following the house harness
   conventions of `test-git-data-root-token-census.sh`: instrument self-test, floors,
   `mutant_red`, and an input-tree seam `IPT_GITHUB_DIR`. Register it in `scripts/test-all.sh`
   next to line 2570, so it runs on every PR. Its assertions are the Guard Contract below. The
   Tier-B names and the environment set live as constants **in the census script** (the loader
   loads the whole privileged project, so the census is the only reader, per the simplicity
   review). The environment set is cross-checked against the Terraform-declared `main` policies.
   The constants are: the secret `DOPPLER_TOKEN_INFRA_PRIVILEGED`; the moved repo secrets
   `DOPPLER_TOKEN_WRITE` and `DOPPLER_TOKEN_GIT_DATA_ROOT`; the Tier-B names; and the
   environments `infra-privileged`, `web-platform-infra-apply`, `inngest-cutover` and
   `workspaces-luks-cutover`.

2. Write the census's mutation rows **before** editing any workflow, and run the suite against the
   unmodified tree. It must go **red**, because today's jobs read `HCLOUD_TOKEN` from
   `prd_terraform` outside a Tier-B environment. That red output is the inventory. Commit the
   classified inventory as a table in the runbook (`§Consumer inventory`), with one row per job:
   `workflow::job`, trigger set, environment today, credential(s) used, read or write, and tier
   after. Classification rule: a job that runs `terraform plan|apply|import` against a root whose
   variables include a Tier-B variable is Tier B. A job that only reads Hetzner is Tier A, using
   `HCLOUD_TOKEN_READONLY`. A job that mints an App token for writes is Tier B.

### Phase 2 — Terraform (web-platform root, infra/github, git-data-root-key, rung2-rehearsal)

1. **`apps/web-platform/infra/main.tf`, `infra/github/main.tf`,
   `apps/web-platform/infra/git-data-root-key/main.tf`: GitHub auth mode.** Replace the static
   `app_auth` with the following:

   ```hcl
   provider "github" {
     owner = "jikig-ai"
     token = var.github_plan_actions_credential != "" && var.github_infra_app_private_key == "" ? var.github_plan_actions_credential : null
     dynamic "app_auth" {
       for_each = var.github_infra_app_private_key != "" || var.github_plan_actions_credential == "" ? [1] : []
       content {
         id              = var.github_infra_app_private_key != "" ? var.github_infra_app_id : var.github_app_id
         installation_id = var.github_infra_app_private_key != "" ? var.github_infra_app_installation_id : "122213433"
         pem_file        = var.github_infra_app_private_key != "" ? var.github_infra_app_private_key : var.github_app_private_key
       }
     }
   }
   ```

   Add these variables with `default = ""`, marked `sensitive` where they are secret:
   `github_plan_actions_credential`, `github_infra_app_id`, `github_infra_app_installation_id` and
   `github_infra_app_private_key`. `github_app_private_key` and `github_app_id` also gain
   `default = ""`. After O10's sentinel override, Tier A resolves the key to a non-PEM sentinel,
   which only the legacy mode would ever read. The PR plan is always in token mode. The work phase
   re-runs probe M8 against this exact block (in a scratch copy) for all three modes:
   - the legacy mode uses the real `prd_terraform` values;
   - the token mode uses a `GITHUB_TOKEN`-shaped token;
   - the infra mode uses an unset key and expects the **loader's** shell mode check to refuse
     before Terraform runs (D6).

   HCL cannot precondition a provider, and provider v6 falls back to ambient `GITHUB_TOKEN`/`gh
   auth token` when neither `token` nor `app_auth` resolves. By construction, one of them always
   resolves here, because the `for_each` is the exact complement of the `token` condition. Add a
   comment on `installation_id = "122213433"` naming it as the soleur-ai **installation** id on
   `jikig-ai` (not the App id 3261325), used only by the legacy mode.
2. (Cut in the 0.6b pass: a `tier` variable plus an apply-refusing precondition. Terraform cannot
   tell a plan from an apply in configuration. A token-mode apply would fail anyway, because the
   PR `GITHUB_TOKEN` is read-only and the Doppler and R2 placeholders are rejected by the vendor
   APIs. No property needs it.)
3. **New `apps/web-platform/infra/infra-privileged-environment.tf`:**
   - `github_repository_environment.infra_privileged`, with no reviewers and
     `deployment_branch_policy { protected_branches = false, custom_branch_policies = true }`;
   - `github_repository_environment_deployment_policy.infra_privileged_main` (`branch_pattern =
     "main"`), mirroring `web-host-birth-environment.tf:53-80`, including its load-bearing comment
     about both halves being required;
   - `doppler_project.infra_privileged` (`soleur-infra-privileged`, `prevent_destroy`) and
     `doppler_environment.infra_privileged_prd` (`prd`).

   - `cloudflare_r2_bucket.terraform_state_privileged` (`soleur-terraform-state-privileged`,
     `provider = cloudflare.r2`, `location`/`jurisdiction` matching `soleur-terraform-state`,
     `prevent_destroy`) and its `-target` line. A bucket name is not a secret, so it belongs in
     IaC (terraform-architect). The **bucket-scoped token** stays operator-minted (ADR-130).

   **No** `doppler_secret`, and **no** `doppler_service_token` in this root, because this state is
   Tier-A readable. The header comment states why.
4. **`workspaces-luks.tf:271`:** give `github_repository_environment.workspaces_luks_cutover` a
   `deployment_branch_policy` block, plus
   `github_repository_environment_deployment_policy.workspaces_luks_cutover_main`.
   `inngest_cutover` already has one.
5. **`github-app.tf`:** add `removed { from = doppler_secret.github_app_private_key; lifecycle {
   destroy = false } }` (and the same for `github_app_id`), and delete the two resource blocks.
   Doppler `prd` keeps its value. Web-platform state stops holding a copy of an App key. **Keep**
   the `-target` lines at `apply-web-platform-infra.yml:646-647`.

   **This is the U1 pair, and it is the most dangerous edit in the PR.** Those two resources pin
   `config = "prd"` (`github-app.tf:40-65`), so they are the soleur-ai App's **runtime** identity —
   the key the web app mints every connected user's installation token from — not a Terraform
   bookkeeping copy. Three ways to destroy it: a misspelled `from` address (Terraform then plans a
   plain **destroy** of the orphaned resource, because the resource block is gone and no `removed`
   block claims it); the right address with no `-target` line (the forget never applies, the
   resource stays managed with no HCL, and the next **untargeted** apply destroys it); or
   `lifecycle { destroy = false }` omitted, which turns the forget into a delete outright.
   `ignore_changes = [value]` protects the value, never the resource. Therefore: copy each address
   from `terraform state list` rather than typing it, assert it with AC2c's script row, keep both
   `-target` lines, add both to the destroy-guard forget rows (item 7b), and record the `prd` key
   hashes in the ledger before O0 (O0's U1 limb). After O10 the legacy variable resolves to the
   `EVICTED_SEE_ADR_241` sentinel, so a recreate would write a non-PEM sentinel into `prd` — a
   destroy here is not merely a delete, it is a delete that a naive re-apply "fixes" by writing
   garbage over the runtime key. This was measured in the plan
   phase on a scratch copy with TF 1.10.5. A `removed` block is planned ("will no longer be managed
   by Terraform, but will not be destroyed") **only when its address is targeted**. A `-target`
   list that omits it plans nothing for it, so the forget would never happen. The same applies to
   item 6's two addresses (`-target=github_actions_secret.doppler_token_write` stays at :709; add
   `-target=doppler_service_token.write` if it is absent). Removing the dangling `-target` lines
   after the forget has applied is part of the R6 follow-up.
6. **`doppler-write-token.tf`:** add `removed { lifecycle { destroy = false } }` for
   `github_actions_secret.doppler_token_write` and for `doppler_service_token.write`. Forget only,
   so the repo secret and the token stay live until the operator replaces them. That keeps the
   merge safe.
7. **`git-data-root-key/access.tf`:** add `removed { from = … lifecycle { destroy = false } }` for
   `github_actions_secret.doppler_token_git_data_root` and for
   `doppler_service_token.git_data_root_read`.
   - **`git-data-root-key/main.tf` backend:** drop the literal `bucket` so that `terraform init`
     receives `-backend-config=bucket=$BUCKET`. `$BUCKET` is `soleur-terraform-state-privileged`
     when the loader exported the `GIT_DATA_ROOT_STATE_*` key pair, and the legacy
     `soleur-terraform-state` otherwise. The legacy bucket is **refused**
     (`verdict=git_data_root_state_legacy_after_migration`) once the repo variable
     `GIT_DATA_ROOT_STATE_MIGRATED=1` is set (O8). The PR `plan` job never initializes this nested
     root: `detect-changes` collapses it into its parent (ADR-220 D2.2, TS2b), so no PR-plan
     backend config is needed. Local operator inits pass `-backend-config=bucket=…`, as the
     runbook documents.
   - Update `apps/web-platform/infra/git-data-root-key.test.sh`: its address census, its backend
     pin and its "seven D-1 addresses" derivation.
7b. **Web-platform destroy guard** (`apply-web-platform-infra.yml`, near the `[ack-destroy]`
   counter around :958). The plan JSON carries `actions:["forget"]`, and the guard does not count
   forgets today. Add fixture rows to its executed test so that an **unlisted** forget is
   surfaced. The rows name exactly the four forgets this PR introduces:
   `doppler_secret.github_app_private_key`, `doppler_secret.github_app_id`,
   `github_actions_secret.doppler_token_write` and `doppler_service_token.write`.
8. **`apply-git-data-root-key.yml`:** add one typed allowlist arm, `8209_custody_forget`. It is
   one-shot: the R6 follow-up deletes it once the O8 dispatch has applied the forgets (DHH review). It admits
   exactly a **forget** of those two addresses and nothing else. It is additive to the existing
   `create_addrs` or no-op arm, mirroring the ADR-220 D3 rule that any change is a reviewed PR with
   a typed arm. Extend the workflow's own executed test (the one that runs the `allowlist` step body
   against synthesized fixtures) with rows for:
   - the forget of exactly those two addresses (PASS);
   - a forget of a third address (RED);
   - a delete of either address (RED).
9. **`rung2-rehearsal/`:** no GitHub provider exists there. It only consumes the loader through its
   workflow.

### Phase 3 — Loader composite action

Create `.github/actions/infra-credentials/action.yml`. It installs the Doppler CLI itself, pinned
to the same SHA, so it **replaces** each Tier-B job's `DopplerHQ/cli-action` step one for one and
the ADR-231 byte budget stays flat.

- **Inputs:**
  - `privileged-token` (`${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}`);
  - `tier-a-token` (`${{ secrets.DOPPLER_TOKEN }}`).
- **Behavior:**
  1. **Mode check (D6).** When `privileged-token` is non-empty, **download the whole privileged
     project** (`doppler secrets download --no-file --format json`, held in a variable and never
     printed). Require `DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN`, `CF_API_TOKEN_R2`,
     `TF_STATE_AWS_ACCESS_KEY_ID/SECRET` and the three `GITHUB_INFRA_APP_*` to be non-empty, which yields `source=tier_b`. The GitHub infra
     variables are among them. When the token is empty, emit `source=legacy_prd_terraform`. There
     is no value comparison against `prd_terraform`: `--preserve-env` (Phase 4) makes shadowing
     impossible, so the sha-compare guard of the draft was cut.
  2. If `privileged-token` is non-empty: for each key, emit `::add-mask::` (line by line for
     multi-line values). Write `TF_VAR_<lower>` to `$GITHUB_ENV`, plus the plain name for
     `HCLOUD_TOKEN`, `TF_STATE_AWS_*` and `GIT_DATA_ROOT_STATE_*`. The `GIT_DATA_ROOT_STATE_*`
     pair is all-or-none: exactly one set refuses `verdict=git_data_root_state_half_set`. Use a random heredoc delimiter, following
     `apply-github-infra.yml:187-190`. Emit `::notice title=infra-privileged::source=tier_b`.
  3. If it is empty (the **before** state): export only plain `HCLOUD_TOKEN` from `prd_terraform`,
     so that inline Hetzner sites work uniformly. Emit
     `::warning title=infra-privileged::source=legacy_prd_terraform`. `doppler run -c prd_terraform`
     still injects the TF variables in this state.
  4. Refuse with `verdict=privileged_source_missing name=<NAME>` when a **required** name is
     empty from both sources. The root-key job's `terraform init` for the privileged bucket takes
     its keys **per command**:
     `AWS_ACCESS_KEY_ID="$GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY=… terraform init -backend-config=bucket=soleur-terraform-state-privileged`.
     The job-wide `AWS_*` in `$GITHUB_ENV` (`apply-git-data-root-key.yml:82-90`) are Tier A, and
     keys passed through `-backend-config` would be persisted in `.terraform/`.
     `GIT_DATA_ROOT_STATE_*` are **optional** until O8. When they are absent, the root-key job keeps the legacy bucket and the Tier-A `AWS_*`,
     and emits `::warning title=infra-privileged::git_data_root_state=legacy_bucket`. After O12
     that fallback would find no object, so `init` yields an empty state. The existing
     `git_data_root_key_remint_refused` gate (the fingerprint file is committed) then refuses the
     plan, which fails closed and cannot re-mint.
- **Why the ordering is safe in both states:** every later `doppler run` in the job carries
  `--preserve-env`, so the exported `TF_VAR_*` win whether or not `prd_terraform` still holds the
  names. The App variables also use new names (`github_infra_*`) that are never in `prd_terraform`.
- Add `.github/actions/infra-credentials/infra-credentials.test.sh`. It drives the action's `run:`
  body with stubbed `doppler` and a fake `$GITHUB_ENV` through six rows:
  - before-state;
  - after-state;
  - missing required name (red);
  - `source=tier_b` with an empty infra App key (red, mode check);
  - a multi-line PEM, where every line is masked;
  - a delimiter collision.

  It also runs a real `doppler run --preserve-env` sentinel row, gated on `command -v doppler`,
  as the executable proof of the precedence property.

### Phase 4 — Workflow edits (byte-budgeted)

1. **Tier-B jobs:**
   - add `environment: infra-privileged` to each job that lacks an environment. **Enumerate these
     from the Phase 1 census, not by reading the file top to bottom**, and assert the result with
     AC2b: a Tier-B job with no `environment:` can read no environment secret, so it works only
     while the legacy fallback exists and fails closed at O10. The known case is
     `git_data_host_replace` (`apply-web-platform-infra.yml:4023-4035`), whose header states it
     has no `environment:` deliberately, so that a `workflow_dispatch` runs the **selected ref**
     and the branch it polices supplies its own gate. Giving it `infra-privileged` changes that:
     a non-`main` dispatch is refused by the branch policy. **That is a behaviour change, not a
     side effect** — record it in the job header, in ADR-241 D2 and in the runbook. It is the
     right trade (the job's own header already says the no-environment shape "does NOT hold
     against a deliberate actor with repository write access"), but it must be a stated decision,
     and it is why O4b rehearses this path from `main` before O10;
   - replace `uses: DopplerHQ/cli-action@…` with `uses: ./.github/actions/infra-credentials` plus
     its two token inputs;
   - add `--preserve-env` to **every** `doppler run` inside a Tier-B job. Measured sites: 47 in
     `apply-web-platform-infra.yml` (36 of them tf-var), 10 in `apply-deploy-pipeline-fix.yml`,
     4 in `apply-github-infra.yml`, 2 in `apply-git-data-root-key.yml`, 15 in
     `git-data-rung2-rehearsal.yml` and 2 in `scheduled-terraform-drift.yml`. That is about
     16 B per site, or ~750 B in the budgeted file. The flag covers the non-tf-var runs too, where
     a script reads a plain `$HCLOUD_TOKEN`;
   - replace every inline `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c
     prd_terraform --plain) || HCLOUD_TOKEN=""` with `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"`;
   - in each "Extract backend credentials" step of a Tier-B job (measured: 15 in
     `apply-web-platform-infra.yml`, 1 each in `apply-github-infra.yml`,
     `apply-deploy-pipeline-fix.yml`, `git-data-rung2-rehearsal.yml`, `apply-git-data-root-key.yml`
     and `scheduled-terraform-drift.yml`, and 2 in `apply-sentry-infra.yml`), prefer the Tier-B
     read/write key: `KEY_ID="${TF_STATE_AWS_ACCESS_KEY_ID:-$(doppler secrets get AWS_ACCESS_KEY_ID --plain)}"`,
     and the same for the secret (R7);
   - `apply-sentry-infra.yml::apply` (push to `main`) becomes Tier B, because it writes
     `soleur-terraform-state`. Its `plan_pr` job stays Tier A (read-only after O5b). The
     existing fail-closed `-z` branches and their messages stay, with "(prd_terraform)" reworded to
     "(infra-credentials loader)". There are about 12 sites in `apply-web-platform-infra.yml` plus
     `apply-git-data-root-key.yml:225`.

   Jobs whose environment is conditional (`workspaces-luks-cutover.yml::cutover`,
   `cutover-inngest.yml::cutover`) get `infra-privileged` in place of the empty-string arm **only
   if** the Phase 1 inventory classifies them Tier B. The measured case,
   `workspaces-luks-cutover::cutover`, only *reads* a Hetzner volume id, so it stays Tier A and
   switches to `HCLOUD_TOKEN_READONLY` with a fallback to `HCLOUD_TOKEN` (before state). Its
   environment expression is unchanged.
1b. **`plan_only` — the incident-recovery rehearsal arm (U5, O4b).** Add one `workflow_dispatch`
   input to `apply-web-platform-infra.yml`, `plan_only` (boolean, `default: false`), honoured by
   the two recovery jobs `web_host_replace` and `git_data_host_replace`. When it is true the job
   runs its existing steps up to and including `terraform plan` and the path's gate, the gate
   reports its verdict **without** aborting the run, and the job then exits 0. Implementation is a
   single `if: inputs.plan_only != true` on each mutating step from the apply onward (the apply,
   the `-replace`, the SSH bridge, the boot-trail poll and the post-apply token sync), plus one
   `::notice::` line carrying `plan_only=1` and the loader's `source=`. No step is added to the
   real path, so the byte cost is roughly 40 B per guarded step.

   Three properties make this safe to add to a destructive job, and the census asserts all three:
   (a) `plan_only` **never widens** anything — it only skips steps, so a true value can make the
   job do less and never more; (b) every mutating step in both jobs carries the guard, derived by
   the same `-target=`/`apply` sweep Phase 4 item 5 uses, so a newly added apply step without the
   guard is RED; (c) the input-validation step, the typo-guard token and the environment gate run
   **unchanged**, so `plan_only` is not a way around any of them. Add executed fixture rows: a
   `plan_only=true` dispatch reaches the plan and runs no apply; a `plan_only=false` dispatch is
   byte-identical in behaviour to today; and a mutating step with no guard fails the census.
2. **`infra-validation.yml::plan` (Tier A).** Add a step before `Terraform plan` that exports:
   - `TF_VAR_github_plan_actions_credential=${{ github.token }}`;
   - `TF_VAR_doppler_token_tf` and `TF_VAR_cf_api_token_r2` as fixed, well-formed placeholders
     (`dp.pt.tier-a-placeholder` padded, and a 40-character `[a-z0-9]` string; the formats were
     measured in M8);
   - `TF_VAR_hcloud_token` from `HCLOUD_TOKEN_READONLY`, falling back to `HCLOUD_TOKEN` in the
     before state.

   Add `--preserve-env=TF_VAR_github_plan_actions_credential,TF_VAR_doppler_token_tf,TF_VAR_cf_api_token_r2,TF_VAR_hcloud_token`
   to the plan step's `doppler run`, so the placeholders win **in both states** and the PR's own
   CI run exercises the Tier-A path (Kieran P1). Without it, the before state would override them
   with real values and AC5 would test nothing. Change `terraform plan` to
   `terraform plan -refresh=false`. Update the plan comment header to
   read "config-vs-state plan (no refresh; drift is scheduled-terraform-drift's job)". Keep the job
   non-environment. Because of `--preserve-env`, the placeholders and the read-only Hetzner token
   win in both states. The backend key it extracts is whatever `prd_terraform` `AWS_*` holds:
   read/write before O5b, read-only after it.
3. **`board-status-sync.yml` stays Tier A.** The triggers are unchanged (`pull_request`,
   `issues`) and there is no environment. It mints from `SOLEUR_BOARD_APP_ID`/
   `SOLEUR_BOARD_APP_PRIVATE_KEY` in `prd_terraform` (the least-privilege `soleur-board` App, O1b).
   In the before state it falls back to the legacy `GITHUB_APP_*` pair, with a `::warning::`,
   when the board names are absent. That fallback refuses the O10 sentinel with
   `verdict=legacy_app_key_evicted`. `mint-soleur-ai-app-token` gets the same refusal. It must move before O13 deletes the soleur-ai Terraform key.
   The runbook orders O1b before O13.
4. **`.github/actions/mint-soleur-ai-app-token/action.yml` (consumer:
   `build-inngest-bootstrap-image.yml::bump-cloud-init-pin`):** add inputs `app-id-name` and
   `private-key-name` so it can mint as the infra App from the privileged project. The consumer job
   gains `environment: infra-privileged`. The before-state fallback is the same as in item 3.
5. **`apply-web-platform-infra.yml -target` lists:** add
   `github_repository_environment.infra_privileged`,
   `github_repository_environment_deployment_policy.infra_privileged_main`,
   `github_repository_environment_deployment_policy.workspaces_luks_cutover_main`,
   `doppler_project.infra_privileged` and `doppler_environment.infra_privileged_prd`.
6. **Byte budget.** First prototype the full edit (environment line, loader swap and
   `--preserve-env`) on **one** job, measure the delta, and multiply it by the job count before
   editing the rest (advisor). After each file's edits, run `wc -c` and
   `bun test plugins/soleur/test/workflow-file-size.test.ts`. The target is
   `apply-web-platform-infra.yml` ≤ 488,000 B, which keeps a 2 KB margin under 490,000. If a draft
   exceeds it, shorten the new prose (a `# Rationale: <runbook> §<job>` pointer per ADR-231 §2)
   before anything else. Never relocate unrelated rationale, and never raise the gate.
7. **Out of scope by ownership:**
   - `git-data-cutover.yml`, whose `cutover` job keeps working through the same-name environment
     secret;
   - `git-data-pin-redeploy.yml`;
   - the cutover, rollback and wipe scripts.

### Phase 5 — ADR, C4, runbook, compliance docs

1. `soleur:architecture` → **ADR-241** "Terraform credentials are tiered; Tier B is delivered only
   through main-only environment secrets". It holds D1–D9, with statuses:
   - D1–D8: `adopting` until the runbook's O-final verification;
   - D2 `accepted` gated on R1;
   - an Alternatives table (see below).

   The ordinal is **provisional**. The #8211 session may claim 238. On a renumber, sweep
   `grep -rn 'ADR-241' knowledge-base/project/{plans,specs}/feat-one-shot-8209-evict-prd-terraform-secrets* knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md`.
2. **Amend ADR-220's Amendment log.** Add an entry "2026-09-22 (#8209)" covering:
   - the D2 custody-goal status (nominal → bounded by ADR-241, with R1 still open);
   - D4's "Repo-secret reach" residual, now discharged for the Terraform credentials, the read
     token and the state object;
   - the D5 table row "D2–D3" updated to name R1.

   Supersede the dated text in place with a Superseded marker (ADR-220 convention).
3. **C4.** Read all three of `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`
   in full, then:
   - amend `github -> doppler` (model.c4:610) and add one edge, `github -> doppler` "Tier-B
     Terraform credentials: `soleur-infra-privileged` read through a main-only environment secret
     (ADR-241)";
   - amend `github -> soleurMarketplace` (model.c4:556): the identity changes from the soleur-ai
     App to the infra App once it is provisioned;
   - amend `github -> gitDataStore` (model.c4:655): `DOPPLER_TOKEN_GIT_DATA_ROOT` is an environment
     secret;
   - amend the `github -> cloudflare` edge that covers tfstate: a second, privileged state bucket.

   Enumerate the actors, systems and relationships checked. Run
   `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
   `plugins/soleur/test/c4-count-parity.test.sh`.
4. **New runbook `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`**:
   the consumer inventory (Phase 1), the operator sequence (next section) verbatim, and the local
   operator invocation after cutover:

   ```bash
   doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
     doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- terraform plan
   ```

   The inner run carries `--preserve-env`, so the outer Tier-B values win. That flag is the
   safety, not the contents of `prd_terraform`: no census can read Doppler's contents.
   Grep the other 7 runbooks that cite the single `doppler run --name-transformer tf-var`
   invocation. Update each to point at this section.
5. **Legal** (CLO assessment: nothing blocks the merge; an Art. 33 **assessment**, not a presumed
   breach):
   - **`article-30-register.md`, PA-12 §(g) (the GitHub-infra row):** fix TOM items (1), (2) and
     (3) in the cell, with `Superseded` markers. Use the conditional wording: "On completion of
     runbook O10/O13 (#8209, ADR-241), the Terraform credential is a dedicated infra App key in
     `soleur-infra-privileged/prd`, delivered only to environments whose deployment-branch policy
     admits `main` only; until then it remains in `prd_terraform`." Cite code by name, never by
     line number.
   - **`article-30-register.md`, the cross-cutting "Secrets management" qualification that cites
     #8209:** restate it to name R1.
   - **`compliance-posture.md`:** add two Active Items:
     - R1 (OPEN; the Tier-B boundary is nominal until it closes);
     - the "R5 prior-exposure Art. 33 assessment" (IN-PROGRESS; evidence limbs pending).
   - **New `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`**, indexed in
     `breach-register.md`. It follows the 2026-06-29 REACHABILITY-ONLY precedent, with
     disposition REACHABILITY-ONLY and the evidence limbs INCONCLUSIVE until shown clean. The
     reachable class is the write collaborators plus Apps with `contents:write`. Fork PRs never
     received secrets. If the finding flips, Art. 33(2) processor notification to the two
     third-party installers applies.
   - **Evidence the work phase gathers now** (read-only `gh api`; no values). It is recorded in
     that audit file **before** O13, because Actions logs expire at 90 days:
     - every run on a non-`main` ref of a workflow that references `DOPPLER_TOKEN`,
       `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_GIT_DATA_ROOT`, `DOPPLER_TOKEN_WRITE` or any `prd_*`
       token;
     - within those, runs whose `head_sha` changed `.github/workflows/**`, including deleted
       branches;
     - org audit-log collaborator, permission and App-installation events, where the API exposes
       them.

     **Evidence the operator gathers:** Doppler access logs for `prd_terraform`/`prd`, Hetzner
     actions (rescue, rebuild, volume attach), the Cloudflare account audit log, and the start of
     the exposure window from the `prd_terraform` secret history.
6. **Follow-up issues, filed in the work phase** (the pipeline files issues; it takes no other
   action on GitHub):
   - **R1** (soleur-ai runtime key reachable from `prd` repo-secret tokens, plus the App's admin
     write on `jikig-ai/soleur`; `priority/p1-high`, `type/security`; blocks #8211's real cutover);
   - **R6** (Terraform-manage the Tier-B environment secrets once the infra App has
     `environments:write`, following the terraform-architect design; also drop the dangling
     `-target` lines of the forgotten addresses);
   - **R7** (Tier-A backend keys are read/write on `soleur-terraform-state`: a read-only Tier-A
     bucket key, with the read/write key in Tier B; `priority/p1-high`, `type/security`; gates D2
     `accepted`);
   - a note on #6167 linking R1.
7. **Generate the operator bootstrap.** Use `soleur:operator-bootstrap`: the merge leaves
   more than two operator steps that block on the same operator credentials. The script must
   conform to ADR-228: non-interactive by default, no skip variable on destructive acknowledgements,
   and a ledger of stage names only.

## Operator Sequence (prepared, NOT executed by the pipeline)

**Conventions.**

- `R=jikig-ai/soleur`.
- No step prints a value. A value moves shell variable → stdin: `v="$(doppler secrets get K … --plain)"; printf '%s' "$v" | …; unset v`. Command substitution strips the trailing newline that `--plain` emits (measured: `doppler secrets get … --plain | od -c` ends in `\n`). A bare pipe would store that newline.
- Every token mint first lists and revokes a token of the same name (`doppler configs tokens -p … -c … --json | jq -r '.[] | select(.name=="<name>") | .slug'`), so reruns are idempotent. The slug of each **old** token to revoke later is recorded in the bootstrap ledger (names and slugs, never values).
- Steps marked **(irreversible)** must not be reordered.
- The runbook `infra-credential-tiers-8209.md` is the canonical copy. The PR body and the generated bootstrap script link to it.

| # | Step | Exact command(s) | Verify (read-only) | Rollback |
|---|---|---|---|---|
| O0 | Merge the PR. The push apply creates: the `infra-privileged` environment and its `main` policy; the `workspaces-luks-cutover` policy; the empty Doppler project; and the privileged state bucket. It also forgets the 2 `doppler_secret.github_app_*` mirrors and the write-token pair. | merge in GitHub | **Hard gate before O3/O7**, on all four Tier-B environments: `for e in infra-privileged web-platform-infra-apply inngest-cutover workspaces-luks-cutover; do gh api repos/$R/environments/$e --jq '"\(.name) custom=\(.deployment_branch_policy.custom_branch_policies)"'; gh api repos/$R/environments/$e/deployment-branch-policies --jq '[.branch_policies[].name]'; done`. Each must print `custom=true` and `["main"]`. This includes `web-platform-infra-apply`, whose TF state shows drift (M9). If the live value is not `["main"]`, stop. Also run `doppler projects get soleur-infra-privileged --json \| jq -r .name`. **Plus the U1 live-key gate, run immediately before the merge click and again the moment the push apply is green:** (a) `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain \| sha256sum` and the same for `GITHUB_APP_ID` — record both digests **before** the merge in the ledger, and both must be byte-identical afterwards (this is the `prd` runtime key, not the `prd_terraform` one; never compare across configs, they differ by M3); (b) the push apply's plan JSON contains **no** `delete` action for `doppler_secret.github_app_id` or `doppler_secret.github_app_private_key` — `jq -r '.resource_changes[]\|select(.address\|test("^doppler_secret\\.github_app_(id\|private_key)$"))\|"\(.address) \(.change.actions\|join(","))"'` must print `no-op` for both or print nothing at all, and **anything containing `delete` means stop and do not proceed to O1**; (c) **the web app can still mint an installation token**, proved through the App's own runtime path rather than by re-reading Doppler: fire `cron/github-app-drift-guard.manual-trigger` through `POST /api/internal/trigger-cron` (the `soleur:trigger-cron` skill; the event is allowlisted because every entry of `EXPECTED_CRON_FUNCTIONS` is). That handler mints an App JWT from the `prd` `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` via `createAppJwtOctokit()` and calls `GET /app` plus the installation-grant diff (`apps/web-platform/server/github/probe-octokit.ts`, `server/github/app-private-key.ts`). A clean run proves the runtime key is intact; a `401` on App-JWT discovery means the key is wrong or gone — **stop and restore before O1**. `cron/oauth-probe.manual-trigger` is the fallback probe, and it also exercises `GET /repos/{owner}/{repo}/installation` | **Not a plain revert.** A revert deletes the resource blocks, and `prevent_destroy` with them, so the next apply would destroy the project (with O2's secrets), the environment (with O3's secret) and the bucket. Roll back with a follow-up PR that swaps each new resource for `removed { from = … lifecycle { destroy = false } }` and restores the forgotten ones with `import` blocks (both listed in the runbook) |
| O1 | Provide the Tier-B GitHub identity. **Recommended:** create the `soleur-infra` App from the committed manifest `apps/web-platform/infra/github-infra-app-manifest.json` and install it on `jikig-ai` (selected repos). **Allowed alternative** (decision-challenges DC-4): reuse the existing soleur-ai Terraform key under the `GITHUB_INFRA_APP_*` names. That option defers the 403 fix to R6 and keeps a customer-reaching key in Tier B. | manifest flow, with one browser consent (the runbook gives the form-post helper) | `gh api /orgs/jikig-ai/installations --jq '.installations[]\|select(.app_slug=="soleur-infra")\|.permissions'` | delete the App |
| O1b | Create the least-privilege `soleur-board` App from `apps/web-platform/infra/github-board-app-manifest.json` and install it on `jikig-ai`. Store `SOLEUR_BOARD_APP_ID` and `SOLEUR_BOARD_APP_PRIVATE_KEY` in `prd_terraform` by stdin from the downloaded PEM file, then `shred -u` the file | as O1 | the next `board-status-sync` run carries no `legacy` warning | delete the two names; board sync falls back to legacy until O10 |
| O2 | Populate `soleur-infra-privileged/prd` | `for k in DOPPLER_TOKEN_TF HCLOUD_TOKEN CF_API_TOKEN_R2; do v="$(doppler secrets get "$k" -p soleur -c prd_terraform --plain)"; printf '%s' "$v" \| doppler secrets set "$k" -p soleur-infra-privileged -c prd --silent; unset v; done`, then `GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_INSTALLATION_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY` from O1 by stdin | the names are listed; for each copied name, source and destination hash equal in-process (`[ "$(… \| sha256sum)" = "$(… \| sha256sum)" ] && echo equal`) | `doppler secrets delete … -p soleur-infra-privileged -c prd` |
| O3 | Mint the Tier-B read token and seed the four environments (after O0's hard gate and O2) | `T="$(doppler configs tokens create gha-infra-privileged -p soleur-infra-privileged -c prd --access read --plain)"; for e in infra-privileged web-platform-infra-apply inngest-cutover workspaces-luks-cutover; do printf '%s' "$T" \| gh secret set DOPPLER_TOKEN_INFRA_PRIVILEGED --env "$e" -R $R; done; unset T` | `gh api repos/$R/environments/$e/secrets --jq '[.secrets[].name]'` shows the name on all four | `gh secret delete … --env $e`; `doppler configs tokens revoke gha-infra-privileged -p soleur-infra-privileged -c prd` |
| O4 | Canary before any eviction. Dispatch from `main`: `scheduled-terraform-drift.yml`, and a **no-op apply** each of `apply-github-infra.yml` and `apply-web-platform-infra.yml` (the runbook names the no-op `apply_target`) | `gh workflow run … -R $R --ref main` | every run carries the `source=tier_b` annotation. Pass means plan exit `0` or `2` (the known drift is expected) **and** the no-op applies are green. The infra App's write scopes are exercised by the apply. `gh api repos/$R/rulesets` confirms the pin-bump identity is in any bypass list it needs | none needed |
| O4b | **U5, the incident-recovery rehearsal.** A no-op apply does not exercise the two paths that recover the product: `web_host_replace` (environment `web-platform-infra-apply`) and `git_data_host_replace` (which declares **no** environment today, so Phase 4 item 1 gives it `infra-privileged`). Both must be proved reachable **before** O10 removes the legacy fallback that is currently hiding any breakage. Dispatch each from `main` in **plan-only** mode: `gh workflow run apply-web-platform-infra.yml -R $R --ref main -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f reason=tier-b-credential-probe -f plan_only=true`, then the same with `apply_target=git-data-host-replace` and that target's own confirm token. `plan_only=true` (Phase 4 item 1b) makes both jobs run checkout → loader → `terraform plan` → the path's existing gate in **report** mode, then exit 0 **before** any apply, any `-replace`, any SSH and any host contact. It is a strict subset of the real path: nothing that a `terraform plan` does not already do | both runs green; each log carries `source=tier_b` and `plan_only=1`; the gate reports its verdict without aborting; `gh api repos/$R/actions/runs/<id>/jobs --jq '.jobs[].steps[]\|select(.name\|test("Apply"))'` returns **nothing**, proving no apply step ran. If `git_data_host_replace` reports `source=legacy`, its `environment:` is missing or unseeded — **fix before O10** | none; the probe applies nothing. If a run fails, do not proceed to O10: the recovery path is already broken and O10 makes it permanent |
| O5 | Mint `HCLOUD_TOKEN_READONLY` (Hetzner **Read** permission; console-minted, no API) and store it in `prd_terraform` by stdin from a 0600 file, then `shred -u` the file | as described | `curl -s -X DELETE -H @"$HDR" https://api.hetzner.cloud/v1/ssh_keys/1 \| jq -r .error.code` must print `token_readonly`, with the auth header in a 0600 file (`$HDR`) so the token never reaches argv. Any other code is inconclusive: stop. A GET on `/v1/servers` returns `200` | delete the name |
| O5b | **R7, the state key.** Mint a bucket-scoped **read-only** R2 token for `soleur-terraform-state` (ADR-130: operator-minted). Move the current read/write pair into Tier B as `TF_STATE_AWS_ACCESS_KEY_ID`/`TF_STATE_AWS_SECRET_ACCESS_KEY` (O2 pattern). Then replace `prd_terraform` `AWS_*` with the read-only pair | as described | the O4 canary is green again, and its apply writes state. A PR plan is green. With the Tier-A pair, `PutObject` to a scratch key returns `403` and `GET` of `web-platform/terraform.tfstate` returns `200` | restore the read/write pair into `prd_terraform` `AWS_*` (the source is still in Tier B) |
| O6 | Move `DOPPLER_TOKEN_WRITE` to Tier B | `v="$(doppler configs tokens create gha-prd-terraform-write -p soleur -c prd_terraform --access read/write --plain)"; printf '%s' "$v" \| gh secret set DOPPLER_TOKEN_WRITE --env infra-privileged -R $R; unset v` | environment secret listed; the next push apply's `Verify DOPPLER_TOKEN_WRITE present` step passes | `gh secret delete DOPPLER_TOKEN_WRITE --env infra-privileged -R $R` |
| O7 | Move `DOPPLER_TOKEN_GIT_DATA_ROOT` to its environment | `v="$(doppler configs tokens create gha-git-data-root-read -p soleur-git-data-root -c prd --access read --plain)"; printf '%s' "$v" \| gh secret set DOPPLER_TOKEN_GIT_DATA_ROOT --env web-platform-infra-apply -R $R; unset v` | a `git-data-cutover.yml` dry run from `main` reads `role=git-data-auth` as before | `gh secret delete DOPPLER_TOKEN_GIT_DATA_ROOT --env web-platform-infra-apply -R $R` |
| O8 | Migrate the git-data root-key state, and in the same dispatch apply the 2 custody forgets. Mint a bucket-scoped R2 token for `soleur-terraform-state-privileged`. Disable `apply-git-data-root-key.yml` behind a `trap` that re-enables it on any exit. Copy the object server-side (the runbook's `--aws-sigv4` `x-amz-copy-source` helper, which prints no key). **Then** set `GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID`/`…_SECRET_ACCESS_KEY` together; the loader treats the pair as all-or-none and refuses a half-set pair. Then set the repo variable `GIT_DATA_ROOT_STATE_MIGRATED=1` (`gh variable set`), after which the loader refuses the legacy bucket. Re-enable the workflow and dispatch it from `main` | runbook §State migration | Compared in-process, printing only `equal`: `sha256`, `lineage` and `serial` of source and destination. With the Tier-A pair, `GET` on the new object → `403`. The dispatch plans **exactly 2 forgets** (`github_actions_secret.doppler_token_git_data_root`, `doppler_service_token.git_data_root_read`) under arm `8209_custody_forget`, applies them and reads `git_data_root_state=privileged` | before the dispatch: unset the pair and the variable, and the legacy bucket works. After the dispatch the old object is stale: the rollback only goes forward (fix the new bucket's credentials). A forget changes only state, so no import is needed |
| O10 | Evict from Tier A **(irreversible)**. Preconditions: O1b, O3, O4, O5, O5b and O8 all done | `for k in DOPPLER_TOKEN_TF HCLOUD_TOKEN CF_API_TOKEN_R2; do doppler secrets delete "$k" -p soleur -c prd_terraform --yes; done`; `printf '%s' EVICTED_SEE_ADR_241 \| doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --silent` | the three names are absent; `[ "$(printf '%s' "$(doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --plain)" \| sha256sum)" = "$(printf '%s' EVICTED_SEE_ADR_241 \| sha256sum)" ] && echo equal`; a PR touching `apps/web-platform/infra/` is green; push apply, drift, board sync and the pin bump are green | re-set the three from Tier B (O2 pattern); `doppler secrets delete GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform` drops the override |
| O11 | Delete the old repo secrets and revoke the old tokens **(irreversible)**. Preconditions: O6, O7 and O8 | **First resolve each slug back to its name (U4).** A slug is opaque and the ledger is the only thing that binds it to a token; a wrong slug on the `soleur-git-data-root` line revokes the token the **running** git-data host uses to reach its root key. For each project/config pair, print the full name↔slug table and require an exact name match before revoking: `doppler configs tokens -p soleur-git-data-root -c prd --json \| jq -r '.[]\|"\(.name)\t\(.slug)"'` — the slug to revoke **must** be the row whose `name` the ledger recorded (the old `gha-git-data-root-read`, **not** the O7 mint of the same name, which is why O7's mint is listed first in the ledger with its creation timestamp, and not the git-data **host** boot token). Abort if the table shows two rows with the ledger's name, or none. Repeat for `-p soleur -c prd_terraform`. Then: `gh secret delete DOPPLER_TOKEN_GIT_DATA_ROOT -R $R`; `gh secret delete DOPPLER_TOKEN_WRITE -R $R`; `doppler configs tokens revoke <confirmed slug> -p soleur-git-data-root -c prd`; `doppler configs tokens revoke <confirmed slug> -p soleur -c prd_terraform` | `gh api repos/$R/actions/secrets --jq '[.secrets[].name]'` lacks both; the cutover dry run and the push apply are still green. **Plus the git store's own health (U4), which the CI dry run does not test** — the dry run carries its own credential and proves nothing about the running store. Read it from the observability layer and from the store's own endpoint, with no operator shell on the host: (a) the git-data heartbeat and its dedicated Better Stack log source (#7772) are still reporting, queried read-only with the established idiom `doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://uptime.betterstack.com/api/v2/heartbeats'`; (b) `gh workflow run scheduled-terraform-drift.yml -R $R --ref main` — its `heartbeat-live-reconcile` job reads Better Stack's live heartbeats and is the existing instrument for a host going dark; (c) a `git ls-remote` against one repository through the store's normal endpoint returns refs. Run all three within minutes of the revoke, while a rollback is still cheap | mint again and re-set (this re-opens the reach; last resort). If the **host's** token was revoked by mistake, mint a replacement of the same name into the same project/config and redeliver it to the host before its next restart — the host keeps running on its cached environment until then, and that window is the whole rollback budget |
| O12 | Delete the git-data root-key object from `soleur-terraform-state` **(irreversible)** | runbook §State migration, delete step | a Tier-A listing no longer shows the key | none |
| O12b | **U3, the host-read service tokens. A read-only gate on O13's `DOPPLER_TOKEN_TF` revocation — no action, and O13 does not start until it passes.** Terraform, running as `DOPPLER_TOKEN_TF` (a workplace **personal** token), created the Doppler service tokens the production hosts read their own configuration with: `doppler_service_token.git_data` (`git-data-luks-boot`, `git-data-luks.tf:161`), `doppler_service_token.ghcr_minter` (`ghcr-minter-write` on `soleur/prd`, `ghcr-minter-doppler-token.tf:45`) and `doppler_service_token.registry` (the zot boot token, `zot-registry.tf:299`). The question O13 must not assume the answer to: **does revoking the creating personal token invalidate the service tokens it created?** | (1) Enumerate the creator-bound set from state, not from memory: `terraform state list \| grep '^doppler_service_token\.'` in each root, and record every name in the ledger. (2) Settle the vendor behaviour **on the vendor side**, not by inference: Doppler's service-token documentation on token lifecycle and ownership, plus a written confirmation from Doppler support quoting the token names, filed in the runbook §Rotation as the citation for this step. A service token is a distinct object with its own slug and its own config scope, so the expected answer is that it survives; **an expected answer is not a confirmed one, and this step is what turns one into the other.** (3) A live negative control, which is decisive on its own: mint a throwaway `read` service token with a **second, disposable** personal token, revoke that personal token, then read a secret with the service token. A `200` proves no cascade; a `401` proves there is one and **O13's `DOPPLER_TOKEN_TF` revocation must not run** until every host token above has been re-minted by a surviving identity | n/a — nothing is changed |
| O13 | Rotate each public-branch-reachable credential (R5, **required**), **one at a time**: set the new value in Tier B → run the O4 canary → only then delete the old value. Order: Hetzner R/W; `CF_API_TOKEN_R2` (Cloudflare roll API, piped); `DOPPLER_TOKEN_TF` (new personal token, then revoke the old — **gated on O12b**); the R2 read/write state key; finally **delete the soleur-ai App key that `prd_terraform` held** (App settings → Private keys; no API exists) | runbook §Rotation. **Two additions.** (a) **After the `DOPPLER_TOKEN_TF` revocation (U3):** prove each host still reads its own config, because O12b establishes the expectation and this establishes the fact. Read it from CI and from the observability layer, never from an operator shell on the host: each host's Better Stack heartbeat and log source still report (the O11 read-only query), `scheduled-terraform-drift.yml`'s `heartbeat-live-reconcile` is green on a `main` dispatch, a `git ls-remote` against the store returns refs, and a `docker pull` of the current pin from ghcr succeeds. **Then force the case a cached environment hides:** the tokens under test are *boot* tokens, so a live host keeps working on the environment it already read. Dispatch `apply-web-platform-infra.yml` with `apply_target=entrypoint-audit` for the CI-side read, and schedule the real proof — the next host replace, dispatched from `main` through the workflow — as a deliberate, announced step rather than letting it arrive during an unrelated incident. O12b's negative control is what makes this a confirmation rather than the first time the question is asked. (b) **Before the App-key click (U2):** the two soleur-ai keys are distinguishable **only** by fingerprint, and the App settings UI lists fingerprints, so compare rather than guess. Compute the Terraform key's fingerprint from the value the operator captured to a 0600 file at the start of O13 — GitHub shows the SHA-256 of the DER public key, so `openssl rsa -in "$f" -pubout -outform DER \| openssl dgst -sha256 -binary \| base64` — and compute the **runtime** key's the same way from `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain`. The two **must** differ (M3 says they do; if they match, the two configs are not holding distinct keys and the whole delete is wrong — stop). Delete **only** the row whose fingerprint equals the `prd_terraform` one, and `shred -u` both files | AC16's per-credential `401`/verify-failure probes. **Plus, immediately after the App-key delete (U2):** the runtime key must still work — a JWT signed with the **`prd`** key gets `200` from `GET /app` (`slug=soleur-ai`), a runtime **installation-token mint** succeeds on a `jikig-ai` installation, and the `cron/github-app-drift-guard.manual-trigger` probe from O0 runs clean. The old **Terraform** key's JWT must get `401` from the same `GET /app`, which is AC16's first limb; a `401` from *both* means the runtime key was deleted — **page immediately**, every connected user is disconnected | each old value stays valid until its own delete. The App-key delete has **no rollback**: GitHub cannot restore a deleted private key, only issue a new one. If the runtime key was the one deleted, recovery is: generate a new key in App settings, write it to `prd` (`GITHUB_APP_PRIVATE_KEY`, by stdin from the downloaded PEM), `shred -u` the file, restart the web app, and re-run the O0 mint check |

**Order constraints** (the bootstrap ledger enforces them):

- O2 precedes O3.
- O0's hard gate precedes O3 and O7. **Its U1 limb (the `prd` App-key hashes, the no-delete plan
  assertion and the installation-token mint) is a stop, not a note: a `delete` on either
  `doppler_secret.github_app_*` address, or a changed `prd` hash, halts the sequence at O0.**
- O3 and O4 precede O5b, O10 and every later step.
- **O4b precedes O10.** Between O3 and O10 the legacy fallback hides a broken recovery path, and
  O10 is what removes the fallback. Rehearsing both host-replace paths after O10 would be
  rehearsing them for the first time during an incident.
- **O12b precedes O13's `DOPPLER_TOKEN_TF` revocation.** If the vendor answer or the negative
  control shows a cascade, the host boot tokens are re-minted by a surviving identity first.
- **O11's name↔slug confirmation precedes each `doppler configs tokens revoke`,** and its
  post-revoke git-store health read follows within minutes.
- **O13's App-key fingerprint comparison precedes the click,** and its runtime proof follows
  immediately. This is the one irreversible step with no rollback.
- O1b, O5 and O5b precede O10. Without O5 the PR plan's Hetzner fallback is empty. Without O1b,
  board sync mints with the sentinel. The fallback refuses the sentinel with
  `verdict=legacy_app_key_evicted`.
- O6, O7 and O8 precede O11.
- O8 precedes O12.
- The evidence limbs of the prior-exposure assessment (Phase 5 item 5) precede O12 and O13. The
  Actions logs expire at 90 days.
- O13's last delete (the App key) follows O10 and a green O4.
- Merging (O0) and stopping there leaves every workflow on the legacy path, which is today's
  behavior.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`: Tier-B jobs, inline Hetzner reads, `-target`
  lines. Byte-budgeted.
- `.github/workflows/apply-deploy-pipeline-fix.yml`, `apply-github-infra.yml`,
  `apply-git-data-root-key.yml` (loader, backend bucket, typed arm, Hetzner read at :225),
  `git-data-rung2-rehearsal.yml`, `scheduled-terraform-drift.yml`,
  `build-inngest-bootstrap-image.yml`, `board-status-sync.yml`, `infra-validation.yml` (plan job),
  `workspaces-luks-cutover.yml` (read-only Hetzner token only), `apply-sentry-infra.yml` (apply job Tier B, R7).
- `.github/actions/mint-soleur-ai-app-token/action.yml`.
- `apps/web-platform/infra/main.tf`, `variables.tf`, `github-app.tf`, `doppler-write-token.tf`,
  `workspaces-luks.tf`, `git-data-root-key/main.tf`, `git-data-root-key/access.tf`,
  `git-data-root-key/variables.tf`, `rung2-rehearsal/variables.tf` (defaults only, if needed).
- `infra/github/main.tf`, `infra/github/variables.tf`.
- `apps/web-platform/infra/git-data-root-key.test.sh`, `tests/scripts/test-git-data-root-token-census.sh`
  (the allowlist now also admits the environment-scoped secret; rows added).
- `scripts/test-all.sh` (register the new suites).
- `plugins/soleur/test/terraform-target-parity.test.ts`, `tests/scripts/lib/destroy-guard-filter-web-platform.jq`,
  `tests/scripts/test-destroy-guard-counter-web-platform.sh` (the `-target=` allowlist and forget
  rows; re-derive with `git grep -ln -- '-target='`).
- `knowledge-base/engineering/architecture/decisions/ADR-220-…md` (amendment log).
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` if an include
  changes).
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`.
- The runbooks that cite the local `doppler run --name-transformer tf-var` invocation (7 files,
  found by grep).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `.github/actions/infra-credentials/action.yml`, `.github/actions/infra-credentials/infra-credentials.test.sh`
- `apps/web-platform/infra/infra-privileged-environment.tf`
- `apps/web-platform/infra/github-infra-app-manifest.json`, `apps/web-platform/infra/github-board-app-manifest.json`
- `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- The operator bootstrap script from `soleur:operator-bootstrap` (path chosen by that skill)

## Open Code-Review Overlap

1 open scope-out touches these files. #7942 ("Two mutation batteries in plugins/soleur/test/ are
named *.mutation.sh and run in no gate") names `infra-validation.yml`. **Acknowledge.** It concerns
suite registration of two unrelated batteries. This plan registers its own suites in
`scripts/test-all.sh` and does not touch those batteries.

## User-Brand Impact

**If this lands broken, the user experiences:**

- **U1 (direct, irreversible). The live GitHub App key is destroyed.** `github-app.tf:40-65`
  declares `doppler_secret.github_app_id` and `doppler_secret.github_app_private_key` with
  `config = "prd"`. That pair is not a Terraform bookkeeping copy: it **is** the soleur-ai App's
  runtime identity, which the web app reads to mint installation tokens. Phase 2 item 5 replaces
  those two resources with `removed` blocks. If a `removed` block's address is misspelled, or the
  address is right but the `-target=` list for O0's push apply omits it (so the block never
  applies and the resources stay managed while the HCL that declares them is gone), or a later
  **untargeted** apply runs, Terraform deletes the Doppler secrets in `prd`. The moment they are
  gone, the web app cannot mint an installation token: **every connected user's GitHub connection
  stops working, every inbound webhook is rejected, and no repository operation succeeds** until
  the operator pastes a key back by hand. `ignore_changes = [value]` does not protect against a
  delete, and O10's `EVICTED_SEE_ADR_241` sentinel makes it worse, because after O10 the legacy
  variable resolves to a non-PEM sentinel, so a recreate would write the sentinel into `prd`.
  Guarded by: the `removed`-address proof in Phase 2 item 5, AC18, the destroy-guard forget rows
  (Phase 2 item 8), and O0's `prd` key-hash and token-mint check.
- **U2 (direct, irreversible). The wrong App key is deleted in the App settings UI.** The
  soleur-ai App has **3 installations, 2 of them outside `jikig-ai`** (M5), and its *runtime*
  private key serves all three. O13's last step deletes the *Terraform* key of the same App in
  github.com → App settings → Private keys. There is **no API for that delete** (vendor limit), so
  it is a click on a list of fingerprints, and the two keys are indistinguishable by anything but
  their fingerprint. Deleting the runtime key instead produces exactly U1's outcome, with no
  Terraform involvement and no rollback: **GitHub does not let a deleted private key be
  recovered**, only replaced, and replacing it means a new key, a Doppler write and a web-app
  restart while every connected user is disconnected. Guarded by: O13's fingerprint comparison
  before the click and its runtime proof after (AC19).
- **U3 (direct). The hosts lose their configuration at the next restart.** Terraform, running as
  `DOPPLER_TOKEN_TF`, created the Doppler **service tokens the production hosts read their own
  config with**: `doppler_service_token.git_data` (`git-data-luks-boot`, the git store's boot
  token), `doppler_service_token.ghcr_minter` (`ghcr-minter-write`, on `soleur/prd`) and
  `doppler_service_token.registry` (the zot boot token). O13 revokes `DOPPLER_TOKEN_TF`. If
  Doppler cascades a personal token's revocation to the service tokens that token created, web-1
  and the git store keep running on their cached environment and then **fail on the next restart,
  reboot or host replace** — the git store serving every connected user's repositories comes back
  with no secrets and no LUKS passphrase. Guarded by: the vendor-side survival confirmation and the
  disposable-token negative control in O12b **before** O13, and the heartbeat, log-source and
  endpoint checks after (AC20).
- **U4 (direct). A revocation takes out the running git store.** O11 revokes two tokens *by slug*
  read from the bootstrap ledger. A slug is an opaque string; nothing in the command names what it
  belongs to. A wrong slug on the `soleur-git-data-root` line revokes the token the **running**
  git-data host uses to reach its root key, and the O11 verification — a cutover dry run — runs in
  CI with its own credential and **never exercises the host's own access**, so the check passes
  while the store is broken. Guarded by: O11's name-before-slug confirmation and its post-revoke
  git-store health check, read from Better Stack and the store's own endpoint (AC21).
- **U5 (indirect, during an incident). Incident recovery fails closed between O3 and O10.** Tier-B
  jobs fail closed with a named annotation: apply-on-merge stops, so an urgent infra fix cannot
  ship, and the drift check goes dark. The sharp case is the two recovery paths. `web_host_replace`
  declares `environment: web-platform-infra-apply`, so O3 seeds it; **`git_data_host_replace`
  declares no `environment:` at all** (apply-web-platform-infra.yml:4023-4035), so as a Tier-B job
  it can read no environment secret until Phase 4 item 1 gives it one. Between O3 and O10 the
  legacy path still covers this, so it is invisible; at O10 it becomes a recovery path that
  refuses at the moment the git store is already down. O4's no-op applies do not exercise either
  path. Guarded by: the census's environment-binding row (AC2b) at PR time, and O4b's dry-run
  dispatch of both recovery paths from `main` (AC22).
- Evicted in the wrong order (O10 before O3), every infra apply fails until the operator restores
  the three names. The rollback column covers this, and the fix takes about a minute.
- Board sync or the pin-bump PR stops, which is internal only.

**If this leaks, the user's data / workflow is exposed via:**

- the soleur-ai App key — `GITHUB_APP_PRIVATE_KEY` with `GITHUB_APP_ID`, in Doppler `prd` for the
  runtime copy and in `prd_terraform` for the Terraform copy — which mints installation tokens on
  the **two third-party installations** (repository read/write on connected users' repos);
- the git-data root key, which is root on the host that stores **every connected user's
  repositories**;
- `HCLOUD_TOKEN`, which is root on web-1, where the user workspaces live.

Today every one of these is readable from any branch workflow. After this change, the Terraform
copies are reachable only from `main`. The soleur-ai *runtime* copy stays reachable through
`prd` repo-secret tokens (R1).

**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true` is set. `soleur:engineering:review:user-impact-reviewer` runs at
review time. CPO sign-off is required before `soleur:work` begins (see Domain Review).

## Acceptance Criteria

### Pre-merge (this PR; checked by CI and review)

- [ ] **AC1.** `tests/scripts/test-infra-privileged-tier-census.sh` is registered in
  `scripts/test-all.sh`, passes on the PR head, and every row of its mutation matrix (Guard
  Contract) is RED when applied. It reports the scanned file count and exits non-zero on 0 files.
- [ ] **AC2.** No job outside `tier_b_environments` names `DOPPLER_TOKEN_INFRA_PRIVILEGED` (census
  row), and every environment in `tier_b_environments` has a Terraform-declared
  `github_repository_environment_deployment_policy` with `branch_pattern = "main"` (census row that
  parses `.tf`).
- [ ] **AC2b.** *(U5)* Every job the census classifies Tier B declares an `environment:` that is a
  member of `tier_b_environments`. A Tier-B job with **no** `environment:` key is RED — it can
  read no environment secret, so it fails closed the moment O10 removes the legacy fallback. This
  row exists because `git_data_host_replace` is exactly that job today
  (`apply-web-platform-infra.yml:4023-4035`, whose header states it deliberately has no
  environment), and it is one of the two paths that recovers the product. The mutation matrix
  includes: deleting the `environment:` line from a Tier-B job, and pointing one at an environment
  outside `tier_b_environments`.
- [ ] **AC2c.** *(U1)* The `removed` blocks resolve to addresses that exist in the live state.
  `terraform state list` in each touched root contains every `removed { from = … }` address
  verbatim, no `removed` block omits `lifecycle { destroy = false }`, and every such address also
  appears in the `-target=` list of the workflow that applies it — an unapplied `removed` block
  whose resource block is gone is the U1 failure mode. Checked by a script row, not by eye, and
  the four web-platform addresses also carry destroy-guard forget rows (Phase 2 item 8).
- [ ] **AC3.** No workflow step reads a `tier_b_names` entry with `-c prd_terraform` except the
  loader's legacy arm (census row, anchored to `.github/actions/infra-credentials/action.yml`).
- [ ] **AC4.** `.github/actions/infra-credentials/infra-credentials.test.sh` passes all six rows
  plus the `--preserve-env` sentinel row. Every `doppler run` in a Tier-B job carries
  `--preserve-env` (census Guard 2). The loader-order row is RED under the reorder mutation.
- [ ] **AC5.** Local `terraform plan -refresh=false` of `apps/web-platform/infra` and `infra/github`
  in token mode with placeholders succeeds (probe M8 re-run on the final code). The legacy mode (the
  real `prd_terraform` values, no infra variables) also plans. The PR's own `infra-validation` plan job is green,
  because this PR touches `apps/web-platform/infra`, so CI runs M8 on the real runner.
- [ ] **AC6.** `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 488,000, and
  `plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] **AC7.** `git diff origin/main --name-only` contains none of `.github/workflows/git-data-cutover.yml`,
  `.github/workflows/git-data-pin-redeploy.yml`, `apps/web-platform/infra/git-data-cutover.sh`, or any
  git-data rollback or wipe script.
- [ ] **AC7b.** Every "Extract backend credentials" step in a Tier-B job reads
  `TF_STATE_AWS_*` first (census row). Every job that writes `soleur-terraform-state` (any
  `terraform apply` whose root's backend bucket is `soleur-terraform-state`) is Tier B (census
  row, parsing each root's `backend "s3"` block).
- [ ] **AC8.** The `apply-git-data-root-key.yml` allowlist test admits exactly the 2-address forget
  and rejects a 3-address forget or a delete (fixture rows).
- [ ] **AC9.** ADR-241 exists with D1–D9, the statuses and the Alternatives. The ADR-220 amendment
  entry exists. The C4 tests and `c4-count-parity` pass. The runbook contains the Operator
  Sequence verbatim and the consumer inventory.
- [ ] **AC10.** The R1 and R6 issues are filed and linked from ADR-241 and from the PR body. The PR
  body says `Ref #8209` (not `Closes`), carries the Operator Sequence and states the order
  constraints.
- [ ] **AC10b.** `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` exists,
  records the read-only GitHub evidence limb (the non-`main` run census described in Phase 5
  item 5, with counts and run ids only), and is indexed in `breach-register.md`. The Article 30
  PA-12 §(g) items (1)-(3), the cross-cutting secrets bullet and the two `compliance-posture.md`
  rows are updated.
- [ ] **AC11.** No file under the plan or the runbook contains a secret value. Run the gitleaks
  pre-commit and `rg -n 'dp\.(pt|st)\.[A-Za-z0-9]{20,}|-----BEGIN' <changed files>`, which must
  return 0 lines.

### Post-operator (verification the operator runs; not a merge gate)

- [ ] **AC12.** `doppler secrets -p soleur -c prd_terraform --only-names` contains none of
  `DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN`, `CF_API_TOKEN_R2`. `GITHUB_APP_PRIVATE_KEY` there hashes
  equal to the `EVICTED_SEE_ADR_241` sentinel.
- [ ] **AC13.** `gh api repos/jikig-ai/soleur/actions/secrets` lacks `DOPPLER_TOKEN_GIT_DATA_ROOT`
  and `DOPPLER_TOKEN_WRITE`. The listed environments hold them.
- [ ] **AC14.** A Tier-A `AWS_*` `GET` of the git-data root-key state object returns 403 or 404 in
  both buckets. The Tier-B bucket-scoped key reads it.
- [ ] **AC14b.** With the Tier-A `prd_terraform` `AWS_*` pair, `PutObject` of a scratch key into
  `soleur-terraform-state` returns `403` and `GET` of `web-platform/terraform.tfstate` returns
  `200`. With the Tier-B pair, a push apply writes state (R7).
- [ ] **AC15.** A throwaway branch workflow that declares `environment: infra-privileged` is
  refused by the branch policy. This is a read-only negative probe: the job never starts, and the
  run shows "Branch … is not allowed to deploy".
- [ ] **AC16.** A JWT signed with the old `prd_terraform` soleur-ai key gets `401` from `GET /app`.
  The old Hetzner R/W token gets `401` from `GET /v1/servers`. The old `CF_API_TOKEN_R2` fails
  `GET /user/tokens/verify`. The old `DOPPLER_TOKEN_TF` gets `401` from `doppler me`. Each probe
  uses a value the operator captured to a 0600 temp file before rotating and shreds afterwards.
  These are required (CPO condition), and #8209 does not close until they pass.
- [ ] **AC17.** The operator's evidence limbs (Doppler, Hetzner and Cloudflare logs) are recorded in
  the prior-exposure assessment, and its disposition is final before #8209 closes.
- [ ] **AC18.** *(U1)* `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` in Doppler **`prd`** hash
  identical before and after O0's push apply, the apply's plan JSON shows no `delete` on either
  `doppler_secret.github_app_*` address, and the `cron/github-app-drift-guard.manual-trigger`
  probe runs clean afterwards. Re-checked once more at the end of the sequence.
- [ ] **AC19.** *(U2)* After O13's App-settings delete: a JWT signed with the **`prd`** key returns
  `200` from `GET /app` with `slug=soleur-ai`, a runtime installation-token mint on a `jikig-ai`
  installation succeeds, and `GET /app/installations` still reports **3** installations. The
  **Terraform** key's JWT returns `401` (this is AC16's first limb; both `401` means the wrong key
  was deleted).
- [ ] **AC20.** *(U3)* O12b's determination is recorded in runbook §Rotation with its vendor
  citation and the negative-control result. After O13's `DOPPLER_TOKEN_TF` revocation, every
  host-facing observable is still green with no operator shell on a host: the web-1 and git-data
  Better Stack heartbeats and log sources report, `heartbeat-live-reconcile` is green on a `main`
  dispatch of `scheduled-terraform-drift.yml`, a `git ls-remote` returns refs, and a `docker pull`
  of the current pin from ghcr succeeds.
- [ ] **AC21.** *(U4)* Every slug O11 revokes was matched to the ledger's **name** in the
  `name\tslug` table before the revoke, and that table is pasted into the ledger. After the
  revokes, the git store is healthy by the same CI-and-observability route as AC20: the git-data
  heartbeat and log source report, `heartbeat-live-reconcile` is green, and a `git ls-remote`
  returns refs.
- [ ] **AC22.** *(U5)* O4b's two plan-only dispatches (`web-host-replace` and
  `git-data-host-replace`) are green from `main` **before** O10, each annotated `source=tier_b`
  and `plan_only=1`, with no apply step present in either run's job list.

## Test Scenarios

1. Before state (PR merged, no operator step): the push apply is green with a `source=legacy`
   warning; the PR plan is green in `-refresh=false`; board sync and the bump still mint.
2. After O3 (the environment secret exists, the names are still in `prd_terraform`): the loader
   takes `source=tier_b`. A **different** `HCLOUD_TOKEN` planted in `prd_terraform` (for example
   with `DOPPLER_TOKEN_WRITE` before O6/O11) has **no effect**: `--preserve-env` keeps the
   loader's value. The loader test's sentinel row proves this, and so does a dispatch whose
   Terraform provider targets the right Hetzner project.
3. After O10: a branch PR plan uses the read-only Hetzner token, and a Tier-B apply uses the
   Tier-B values.
4. A branch workflow names `DOPPLER_TOKEN_INFRA_PRIVILEGED` without an environment: the census
   reds on the PR. Even unmerged, the value is empty at runtime.
5. A branch workflow declares `environment: infra-privileged`: GitHub refuses the deployment
   (AC15).
6. The git-data dry run from `main` still authenticates after O7 and O11.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (threshold sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The principle is sound. A main-only environment secret is the right boundary on
the Developer plan, the carrier is a separate project, and the merge is safe. The boundary is
nominal until R1 closes. The review required five changes before work, and all five are applied:

- `--preserve-env` on every Tier-B `doppler run`, which replaces the sha-compare guard;
- explicit per-command backend keys for the root-key root;
- the auth-mode check in loader shell, since HCL cannot precondition a provider;
- board sync moved off the infra App and off `pull_request_target`;
- the Tier-A read/write state key (R7).

R7 was first deferred, then **folded in**, after the plan-review architecture-strategist repeated
the CTO's finding: a read-only Tier-A key, a Tier-B `TF_STATE_AWS_*` key, and the
`${TF_STATE_AWS_ACCESS_KEY_ID:-…}` fallback in each extract step.

### Plan review (5-agent panel, single-user threshold)

The panel was DHH, Kieran, code-simplicity, architecture-strategist and spec-flow-analyzer.
The named panel's CTO and CPO had already reviewed in Phase 2.5 and were not re-spawned.

**Applied (mechanical):**

- the sentinel's trailing-newline bug (Kieran P0), with values moved through a variable in all
  steps;
- O9 folded into O8, because the `removed` blocks make the first root-key dispatch plan the
  forgets (Kieran P0);
- inner `--preserve-env` in the local invocation (Kieran P0);
- the ambient-token "unset" claim dropped (Kieran P1);
- `--preserve-env` on the PR plan, so CI tests the placeholders now (Kieran P1);
- the stale guard text removed (DHH, Kieran, architecture);
- O5's verify moved to a header file and to the `token_readonly` code;
- the `removed` HCL syntax fixed;
- new order constraints: O2→O3, O5/O5b/O1b→O10, O6/O7/O8→O11 (spec-flow);
- O0 turned into a four-environment hard gate before O3 and O7 (spec-flow, architecture);
- O4 changed to a canary with no-op applies and exit `0`/`2` as the pass signal;
- O8's trap re-enable, the all-or-none key pair, the post-migration latch, and the forward-only
  rollback;
- idempotent token mints;
- per-credential canaries in O13;
- the sentinel refused by the legacy App fallbacks;
- R7 folded in;
- a drift-based detective control for R1 (R-e);
- the #8211 rebase note.

**Simplifications applied** (simplicity, DHH):

- `.github/infra-privileged-tiers.json` deleted; the lists are in the census;
- the loader's `want`/optional split replaced by a whole-project load;
- the bucket name is a literal, not a secret;
- the census merge-base shrink check and the `--live` mode cut;
- the typed arm is one-shot, removed by R6;
- the runbook is the single canonical copy of the operator commands.

**Not applied, with reasons:**

- *Cut `--preserve-env` (simplicity).* The correctness panel, CTO and advisor all want it. It is
  cheap (~750 B), it is the only protection in the window between merge and O6, and it guards
  against a later same-named `prd` secret. Kept.
- *Two PRs instead of dual-state (DHH).* The operator constraint prefers a merge-safe single PR.
  Kept dual-state.
- *Defer the `soleur-infra` App (simplicity).* The code is App-agnostic. O1 lets the operator
  choose, and the choice is recorded in decision-challenges DC-4.
- *Cut C4 and Encryption Posture (DHH).* Both are required plan-gate deliverables (Phase 2.10,
  2.11). Kept.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Nothing blocks the merge (DISCHARGED for merge). R5 calls for an Art. 33
**assessment**, not a presumed breach, following the REACHABILITY-ONLY precedent (2026-06-29).
The reachable class is the write collaborators plus Apps with `contents:write`. Required:

- a dated determination in `knowledge-base/legal/audits/`, indexed in `breach-register.md`;
- Article 30 PA-12 §(g) items (1)-(3), in conditional wording;
- the cross-cutting secrets bullet restated to name R1;
- two `compliance-posture.md` rows;
- evidence gathered **before** O13 (the Actions logs expire at 90 days).

All of these are folded into Phase 5 item 5 and AC10b/AC17.

### Product/UX Gate

**Tier:** none (no UI surface; Product was relevant only for the `single-user incident` threshold sign-off)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**CPO sign-off: granted with conditions**, all applied:

1. R1 is filed at p1, `type/security`, and blocks #8211's real cutover. It is ranked on its own
   risk, not as a deferred cutover precondition.
2. O13 rotation is **required**. AC16 has probes for each old credential, and #8209 does not close
   until they pass.
3. ADR-241 keeps D2 `proposed` until R1 (and R7) close, and the PR body says so.
4. The "lands broken" bullet is reworded as indirect user impact during an incident.

**Brainstorm-recommended specialists:** none (no brainstorm).

### User-impact review (`soleur:engineering:review:user-impact-reviewer`, 2026-09-23)

The `single-user incident` threshold triggers this reviewer against `## User-Brand Impact`. It
found five failure modes missing or under-covered. All five are applied, each as a named impact
(U1–U5), a plan-side guard and an operator-checklist step:

| # | Finding | Applied as |
|---|---|---|
| 1 | The live web-app keys `GITHUB_APP_PRIVATE_KEY`/`GITHUB_APP_ID` in Doppler `prd` (`github-app.tf:40-65` pins `config = "prd"`). A wrong `removed` address or `-target` entry — or a later untargeted apply — destroys the runtime key, breaking every connected user's GitHub connection and webhooks. | **U1** in User-Brand Impact; the expanded warning in Phase 2 item 5; **Guard 4**; **AC2c**, **AC18**; O0's U1 gate (before/after `prd` hashes, a no-`delete` assertion on the plan JSON, and a `cron/github-app-drift-guard.manual-trigger` mint proof); **R-f**; a sharp edge. |
| 2 | The soleur-ai App's runtime key serves all 3 installations; O13's last step deletes a key in the App settings UI with no API, and could take the runtime key instead of the Terraform one. | **U2**; O13 now compares DER-SHA-256 fingerprints before the click and proves the runtime key after (`GET /app` → 200, a runtime installation-token mint, the drift-guard probe); **AC19**; **R-g**; a sharp edge. The no-undo rollback is written out. |
| 3 | Host-read Doppler service tokens Terraform created with `DOPPLER_TOKEN_TF` (`doppler_service_token.git_data`, `ghcr_minter`, the zot boot token). If Doppler cascades a personal token's revocation, web-1 and the git store lose their secrets at the next restart. | **U3**; new read-only step **O12b**, a hard gate on O13's revocation: enumerate the creator-bound set from state, confirm the vendor behaviour in writing, and settle it with a disposable-personal-token negative control. Post-revoke per-host read-back in O13(a); **AC20**; **R-h**; a sharp edge. |
| 4 | A wrong revoked slug in O11 could revoke the token the running git-data host uses to reach its root key; O11's check is a cutover dry run, which does not test the host's own access. | **U4**; O11 now prints the `name\tslug` table and requires an exact ledger-name match before each revoke, aborting on a duplicate or missing name, then reads the git store's health from the host; **AC21**; **R-i**; a sharp edge. |
| 5 | Incident recovery (`web-host-replace`, `git-data-host-replace`) fails closed between O3 and O10; O4 runs only no-op applies. | **U5**; census mutation rows 8–9 and **AC2b**; the `plan_only` arm (Phase 4 item 1b) with **Guard 5**; new step **O4b**, a plan-only dispatch of both recovery paths from `main` before O10; **AC22**; **R-j**. The environment-policy consequence for `git_data_host_replace` is recorded as a decision, not a side effect. |

## Infrastructure (IaC)

### Terraform changes

- Web-platform root:
  - new `infra-privileged-environment.tf`: `github_repository_environment` plus its policy,
    `doppler_project` plus `doppler_environment`, and no secrets;
  - a `workspaces-luks.tf` policy;
  - `removed` blocks in `github-app.tf` and `doppler-write-token.tf`;
  - the provider auth mode in `main.tf`;
  - new variables `github_plan_actions_credential`, `github_infra_app_id`,
    `github_infra_app_installation_id` and `github_infra_app_private_key`, all `default = ""`, and
    all sensitive where they are secret.
- `infra/github`: the same auth mode and variables.
- `git-data-root-key`: partial backend (`bucket` via `-backend-config`), `removed` blocks, the auth
  mode.
- Providers are unchanged: `integrations/github ~> 6.0`, `DopplerHQ/doppler ~> 1.21`, `hcloud`,
  `cloudflare`. CI Terraform is 1.10.5, and `removed` blocks need at least 1.7 (satisfied).
- Sensitive-variable sources:
  - Tier B: `TF_VAR_*` from `soleur-infra-privileged/prd` via the loader;
  - Tier A: `prd_terraform` via `DOPPLER_TOKEN`, with `github_plan_actions_credential` from `github.token`.

### Apply path

(b) Push apply on merge, for the environment, the policy and the empty project. This is additive,
has no downtime, and touches no host. The forgets happen in the same push apply (web-platform) and
in an operator-dispatched root-key apply (git-data-root-key). **No `-replace`, no host change, no
cloud-init change.**

### Distinctness / drift safeguards

- The Tier-B project is a separate Doppler **project**, not a branch config.
- The `main` policy is declared in Terraform and asserted by the census.
- The drift job plans the new environment resources.
- The web-platform state holds no Tier-B value by construction: there is no `doppler_secret` or
  `doppler_service_token` in `infra-privileged-environment.tf`, and a census row greps it.
- The git-data root-key state moves to a bucket the Tier-A keys cannot list.

### Vendor-tier reality check

- GitHub environments, environment secrets and custom branch policies are available on public
  repos on every plan. The org is now on Team (#8450), which is not needed.
- Doppler Developer plan: projects and service tokens are available; service accounts and OIDC are
  not (the reason for D2's carrier).
- Hetzner read-only tokens exist. The `token_readonly` error code is the O5 verify.
- R2 bucket-scoped tokens can be minted only by the operator (ADR-130).

## Observability

```yaml
liveness_signal:
  what: "`::notice title=infra-privileged::source=tier_b` annotation on every Tier-B job, plus the existing scheduled-terraform-drift Sentry heartbeat"
  cadence: "every Tier-B run; drift on its existing trigger-cron schedule"
  alert_target: "existing drift heartbeat monitor + notify-ops-email on non-success"
  configured_in: ".github/actions/infra-credentials/action.yml; .github/workflows/scheduled-terraform-drift.yml"
error_reporting:
  destination: "GitHub run annotations (::error title=infra-privileged::verdict=<word>) + the drift job's existing notify-ops-email/Sentry path"
  fail_loud: true
failure_modes:
  - mode: "Tier-B token missing on an environment (O3 skipped)"
    detection: "loader verdict=privileged_source_missing name=<NAME> after O10; before O10 source=legacy warning"
    alert_route: "job red + notify-ops-email where the job already routes it (apply, drift)"
  - mode: "a Tier-B doppler run loses --preserve-env (a re-planted prd_terraform name would then shadow Tier B)"
    detection: "tests/scripts/test-infra-privileged-tier-census.sh Guard 2 row red on the PR"
    alert_route: "required test check"
  - mode: "a new workflow names the Tier-B secret outside a main-only environment"
    detection: "tests/scripts/test-infra-privileged-tier-census.sh red on the PR"
    alert_route: "required test check"
  - mode: "PR plan cannot run (read-only Hetzner token missing or revoked)"
    detection: "infra-validation plan job red with the provider error; fallback to HCLOUD_TOKEN only in the before state"
    alert_route: "PR check"
logs:
  where: "GitHub Actions run logs (public repo; values masked)"
  retention: "GitHub default 90 days"
discoverability_test:
  command: "grep -l -e 'source=tier_b' .github/actions/infra-credentials/action.yml"
  expected_output: ".github/actions/infra-credentials/action.yml"
```

## Architecture Decision (ADR/C4)

### ADR

New **ADR-241** (provisional ordinal): "Terraform credentials are tiered; Tier B is delivered only
through main-only environment secrets". It holds D1–D9. **Amend ADR-220** in its Amendment log: the
D2 custody-goal status, the D4 "Repo-secret reach" residual and the D5 status row. Both are Phase 5
tasks in this PR.

### C4 views

The work phase reads `model.c4`, `views.c4` and `spec.c4` in full. The elements already enumerated
are:

- external systems `github`, `doppler`, `cloudflare`, `soleurMarketplace`, `gitDataStore`
  (all modeled);
- the actor `founder` (modeled; it now performs the operator sequence).

The relationships that change:

- `github -> doppler` (model.c4:610; a new Tier-B edge);
- `github -> soleurMarketplace` (model.c4:556, the App identity);
- `github -> gitDataStore` (model.c4:655, the token scope);
- `github -> cloudflare` (the tfstate edge, a second bucket).

No new container. `c4-count-parity` runs because edge prose may carry counts.

### Sequencing

ADR-241 D1–D8 are `adopting` until AC12–AC16 pass. D2 is `accepted` only after R1 closes. ADR-220's
D2–D3 row names ADR-241 and R1.

## Encryption Posture

```yaml
at_rest:
  - store: "R2 bucket soleur-terraform-state-privileged (git-data root-key state)"
    mechanism: "Cloudflare R2 provider-managed encryption at rest (AES-256, per Cloudflare R2 docs 'Data security'); bucket declared as cloudflare_r2_bucket.terraform_state_privileged in apps/web-platform/infra/infra-privileged-environment.tf"
    evidence: "https://developers.cloudflare.com/r2/reference/data-security/"
    defends_against: "disclosure from provider media"
    does_not_defend: "any holder of a key that reads the bucket — that is why the key is bucket-scoped and Tier-B only; plaintext private_key_openssh remains inside the object"
    disclosed_as: "ADR-241 D7; ADR-220 amendment"
    live_verification: "AC14 (Tier-A key 403, Tier-B key 200)"
  - store: "Doppler project soleur-infra-privileged"
    mechanism: "Doppler-managed encryption at rest (vendor attestation, Doppler security page)"
    evidence: "https://www.doppler.com/security"
    defends_against: "disclosure from provider storage"
    does_not_defend: "any holder of DOPPLER_TOKEN_INFRA_PRIVILEGED or a workplace personal token (DOPPLER_TOKEN_TF itself reads it)"
    disclosed_as: "ADR-241 D3"
    live_verification: "O3 verify lists environment-secret names only"
in_transit:
  - connection: "GitHub Actions runner -> Doppler API, R2 S3 endpoint, Hetzner API, GitHub API"
    tls: "TLS 1.2+ (vendor endpoints are HTTPS-only)"
    cert_verification: on
    does_not_defend: "a compromised runner or a main-branch code change that exfiltrates in-job"
    disclosed_as: "ADR-241 D2 (boundary is main-branch integrity)"
```

## Guard Contract

### Guard 1: Tier census (`tests/scripts/test-infra-privileged-tier-census.sh`)

**Property.** Every job that names `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE` or
`DOPPLER_TOKEN_GIT_DATA_ROOT` (case-insensitive) declares an environment. Every arm of that
declaration is in `tier_b_environments`, and every one of those environments has a
Terraform-declared `main` deployment policy. No step outside the loader reads a `tier_b_names`
entry from `prd_terraform`.
**Assembly.** Everything that can inject a secret into a job:

- every file matched by `git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml'
  '.github/actions/**/action.yml'`, with totality checked against `git ls-files`;
- within each, the chokepoints `secrets.<NAME>` (any case), `secrets[<expr>]`, `toJSON(secrets)`
  and `secrets: inherit`;
- the environment set is parsed from every `*.tf` under `apps/*/infra` and `infra/`
  (`github_repository_environment_deployment_policy` resources).
**Mutation matrix** (each MUST drive the suite RED):

| # | Mutation (MUST drive RED) |
|---|---|
| 1 | add `secrets.doppler_token_infra_privileged` (lower case) to a job with no `environment:` (e.g. `infra-validation.yml::plan`); |
| 2 | **reorder**: keep a compliant first job and add a *second* job in the same workflow that names the secret with `environment: ${{ cond && 'infra-privileged' \|\| '' }}` (an empty arm); |
| 3 | delete `workspaces_luks_cutover_main` from `workspaces-luks.tf` while the environment stays in `tier_b_environments`; |
| 4 | add `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)` to any job step outside the loader; |
| 5 | add `toJSON(secrets)` to any Tier-B job; |
| 6 | **dispatch self-test**: point `IPT_GITHUB_DIR` at an empty tree; the suite must report 0 files scanned and exit non-zero (the floor); |
| 7 | `pull_request_target` job in `tier_b_environments` that checks out `ref: ${{ github.event.pull_request.head.sha }}`. |
| 8 | **(U5)** delete the `environment:` line from `git_data_host_replace` (or from any other Tier-B job) while it keeps the loader step. This is the *recovery-path* arm of row 1 and it is listed separately because that job shipped with no environment on purpose: the row must red on the job as it exists today plus a loader, not only on a synthetic job; |
| 9 | **(U5)** point a Tier-B job's `environment:` at a name outside `tier_b_environments` (e.g. `web-platform-infra-apply-2`), so the job declares *an* environment that O3 never seeds. |

**Harness rows.**

- A suite edit that makes `mutant_red` always pass must red the instrument self-test.
- One must-PASS non-canonical input: a Tier-B job whose `environment:` uses the mapping form
  `environment: { name: infra-privileged }`. The contract permits both forms.
**Anchor.** The environment set is taken from the workflows themselves: every environment a
Tier-B-secret job declares. The census then requires a Terraform `main` policy for each one. A
list-weakening edit therefore has nothing to weaken. Removing a policy reds the census, and adding
a job under a new environment without a policy reds it too. The live-state check is O0's hard gate
in the runbook, with no census `--live` mode (DHH and simplicity reviews).

### Guard 2: Tier-B precedence (`--preserve-env`), a census row plus the loader's sentinel test

**Property.** In a Tier-B job, a value the loader exported is never replaced by a same-named
value from a Tier-A-writable Doppler config.
**Assembly.** Every `doppler run` invocation inside any job that references
`DOPPLER_TOKEN_INFRA_PRIVILEGED`. That covers inline `run:` bodies **and** scripts those bodies
invoke through `bash <path>` under `scripts/`, `.github/scripts/` or `apps/*/infra/`. The census
resolves one level of `bash <repo-path>` indirection and fails closed on an unresolvable path.
The loader action itself is also in scope.
**Mutation matrix** (each MUST drive RED):

| # | Mutation (MUST drive RED) |
|---|---|
| 1 | remove `--preserve-env` from one tf-var `doppler run` in `apply-web-platform-infra.yml::apply`; |
| 2 | a first compliant `doppler run` with the flag, then a **second** one in the same step without it (the scan must not stop at the first); |
| 3 | remove the flag from a `doppler run` inside a script that a Tier-B job invokes by `bash scripts/<x>.sh`; |
| 4 | **reorder**: move the loader step *after* the first Terraform step in a Tier-B job. The row "the loader precedes every `doppler run`" is RED; |
| 5 | a sentinel row (loader test, real `doppler` CLI when present): with the flag deleted from the wrapper under test, the environment value is overridden, which is RED. |

**Harness rows.**

- Must-PASS: `--preserve-env=TF_VAR_hcloud_token` (the explicit-list form, which the contract
  permits).
- Must-PASS: a Tier-A job's `doppler run` without the flag (out of scope, so it must not red).
- A suite edit that skips script indirection must red row 3.
**Anchor.** The Tier-B job set is derived from references to the environment secret, never from
a list. Adding a job cannot escape the rule by omission.

### Guard 3: git-data root-key allowlist arm (`apply-git-data-root-key.yml`)

**Property.** The only non-additive change the root accepts is a forget of exactly the two
custody addresses.
**Assembly.** The `allowlist` step body is the single chokepoint every plan passes through
before apply.
**Mutation matrix:**

| # | Mutation (MUST drive RED) |
|---|---|
| 1 | forget of 3 addresses → RED; |
| 2 | delete (not forget) of `doppler_service_token.git_data_root_read` → RED; |
| 3 | forget of `tls_private_key.git_data_root` → RED; |
| 4 | a compliant 2-address forget followed by a second, non-listed forget in the same plan → RED. |

**Harness rows.**

- A must-PASS no-op plan.
- A must-PASS 2-address forget in reverse order (order is permitted).

### Guard 4: `removed` blocks forget, never destroy (U1)

**Property.** Every `removed` block in a touched root names an address that exists in that root's
state, carries `lifecycle { destroy = false }`, and is present in the `-target=` list of the
workflow that applies it. No resource block is deleted without a matching `removed` block.
**Assembly.** The `removed` blocks in `apps/web-platform/infra/*.tf` and
`git-data-root-key/*.tf`, the `-target=` lists Phase 4 item 5 maintains, and — for the state
limb — a `terraform state list` the operator pastes into the ledger, since CI holds no state
credential at PR time. The static limbs run in CI; the state limb is an O0 precondition.
**Why it is its own guard.** `doppler_secret.github_app_id` and
`doppler_secret.github_app_private_key` pin `config = "prd"` and hold the **live** App identity.
Getting this wrong is not a failed apply, it is every connected user disconnected.
**Mutation matrix** (each MUST drive RED):

| # | Mutation (MUST drive RED) |
|---|---|
| 1 | misspell a `removed { from = … }` address (`doppler_secret.github_app_privatekey`) → RED; |
| 2 | drop `lifecycle { destroy = false }` from one `removed` block → RED; |
| 3 | delete a resource block with no `removed` block added → RED; |
| 4 | delete the `-target=doppler_secret.github_app_private_key` line while its `removed` block stays → RED (the forget would never apply, and the resource would be orphaned under management); |
| 5 | a `removed` address that is absent from the pasted `terraform state list` → RED. |

**Harness rows.**

- A must-PASS: all four web-platform forgets present, targeted, and `destroy = false`.
- The instrument self-test: an empty `.tf` set reports 0 files and exits non-zero.

### Guard 5: `plan_only` only ever subtracts (U5)

**Property.** In `web_host_replace` and `git_data_host_replace`, every step that applies,
replaces, reaches a host over SSH or writes a token carries `if: inputs.plan_only != true`. No
step is *enabled* by `plan_only`, and the input-validation, typo-guard and environment gates are
unconditional.
**Assembly.** The two job bodies, with the mutating-step set derived the same way Phase 4 item 5
derives the `-target=` sweep (`terraform apply`, `-replace=`, the cf-tunnel-ssh-bridge action, the
boot-trail poll and the post-apply token sync), never from a hand-kept list.
**Mutation matrix** (each MUST drive RED):

| # | Mutation (MUST drive RED) |
|---|---|
| 1 | remove the guard from the apply step in `web_host_replace` → RED; |
| 2 | add a new `terraform apply` step with no guard → RED (the derived set is the authority); |
| 3 | make a step `if: inputs.plan_only == true` (a step that exists *only* under the probe) → RED; |
| 4 | put the guard on the input-validation or typo-guard step → RED. |

**Harness rows.**

- Executed fixture: a `plan_only=true` dispatch reaches `terraform plan` and runs no apply.
- Executed fixture: `plan_only=false` is behaviourally identical to the pre-PR job.

## Alternatives Considered

| Alternative | Why not (now) |
|---|---|
| Doppler Team + service-account OIDC bound to the environment `sub` | Recurring cost; the operator has not approved it. ADR-220 already recorded the plan limit. The carrier is swappable later without touching the boundary design. |
| Put the four credentials directly into GitHub environment secrets (no Doppler hop) | Loses AP-008 (Doppler is the source of truth). Every rotation becomes a multi-environment `gh secret set`, with no audit trail in Doppler. |
| Keep full-refresh PR plans with read-only credentials | No read-only Doppler credential exists on the Developer plan. An account-level R2 read token reads every bucket's objects. |
| Move the PR plan behind a reviewer-gated environment with an all-branches policy | Branch bytes execute with the credentials (providers, `external` data). A human acknowledgement on branch bytes is not a secret boundary (ADR-220's own finding). |
| Terraform-manage `DOPPLER_TOKEN_GIT_DATA_ROOT` now, as an environment secret through the infra App (terraform-architect) | This is the correct end state, and R6 adopts it. It is not merge-safe in this PR: before O1–O3 the provider is still the soleur-ai App (403 on environment secrets), and a partially applied rotation arm could revoke the old token before the new environment secret exists. |
| Keep the draft's sha-compare integrity guard instead of `--preserve-env` | It made correctness depend on an external config's contents. It also hard-failed apply-on-merge whenever an unrelated same-named secret appeared in `prd`, which `prd_terraform` inherits (advisor). `--preserve-env` makes precedence a code property. |
| Board sync on `pull_request_target` with the infra App | That gives an App with administration and environment write to a fork-triggerable job (CTO, advisor). A board-only App in Tier A is least privilege. |
| Grant soleur-ai `environments:write` | Widens the permissions of a customer-installed App, and every installation must re-approve. |
| Evict the soleur-ai runtime key from `prd` in this PR | It needs runtime and host bootstrap changes (hash-bound cloud-init, immutable redeploy). Deferred as R1 with its own issue. |

## Non-Goals

- Changing how the web host or the app reads `prd` (R1).
- Changing any #8211-owned file.
- Terraform-managing the operator-seeded environment secrets (R6).
- Touching #8451.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text or omits the
  threshold fails `deepen-plan` Phase 4.6.
- **`doppler_secret.github_app_id` and `doppler_secret.github_app_private_key` are `config = "prd"`
  — the App's live runtime identity, not a Terraform copy.** Every edit near them is a
  user-facing edit. Never let a `removed` block for either one merge without its `-target` line,
  its `destroy = false`, and an address copied from `terraform state list`.
- **The soleur-ai App has two private keys and the UI distinguishes them only by fingerprint.**
  Never delete a key in App settings without first computing both fingerprints
  (`openssl rsa -pubout -outform DER | openssl dgst -sha256 -binary | base64`) and matching the
  one being deleted to the `prd_terraform` value. The delete has no undo.
- **Revoking a Doppler personal token may or may not reach the service tokens it created — find
  out before O13, not after.** A running host caches its environment, so a cascade is silent
  until the next restart, which may be a host replace during an unrelated incident.
- **`git_data_host_replace` deliberately declares no `environment:`.** Giving it one to carry a
  Tier-B secret also subjects it to a `main` deployment-branch policy, which is a real behaviour
  change to an incident-recovery path. Decide it explicitly (ADR-241 D2), and rehearse the path
  from `main` before O10 removes the legacy fallback that is currently masking it.
- **A CI dry run of a cutover proves nothing about a host's own credential.** CI carries its own
  token. Any check that a revocation did not break a host has to read something the *host*
  produces — its heartbeat, its log source, its serving endpoint — and per
  `hr-no-ssh-fallback-in-runbooks` that read goes through CI and the observability layer, never
  through an operator shell on the box.
- **A boot token's failure is invisible while the host is up.** The host holds the environment it
  read at boot, so a revoked boot token surfaces at the next restart, which may be a host replace
  during an unrelated incident. That is why O12b settles the cascade question with a negative
  control *before* the revocation rather than watching for symptoms after it.
- `doppler run` **overrides** existing environment variables by default. Tier-B precedence rests
  entirely on `--preserve-env` being present on every `doppler run` in a Tier-B job. A new
  `doppler run` added without it would let a `prd_terraform` value shadow a Tier-B value, and only
  census Guard 2 catches that. Never weaken that census row.
- An environment referenced by a job but not yet created is **auto-created by GitHub with no
  protection**. In O0's push apply, the job that declares `environment: infra-privileged` starts
  first, so GitHub auto-creates the environment *before* Terraform (later in the same run) adds
  the `main` policy. That window is harmless only because no secret exists before O3. O0's
  four-environment hard gate is therefore a precondition of O3 and O7, not a courtesy check.
- The #8211 session is likely to edit the ADR-220 amendment log and `model.c4` (the `gitDataStore`
  edge) and may claim ADR-241. Before ship, rebase onto `origin/main` and resolve conflicts in those
  files **additively**: each session appends its own dated amendment entry. Re-verify the ADR
  ordinal (ship's ADR-Ordinal Collision Gate).
- GitHub secret names are case-insensitive, and `GITHUB_*` names are reserved for Actions secrets.
  Hence `GITHUB_INFRA_APP_*` are **Doppler** names only. No Actions secret uses that prefix.
- `apply-web-platform-infra.yml` has ~7.5 KB of headroom (ADR-231). The loader **replaces** the
  Doppler install step for that reason.
- The ADR ordinal is provisional. **239** was chosen after enumerating every `origin/*` ref:
  `feat-8322-affected-test-gate` already claims ADR-238. Re-run the all-refs probe immediately
  before merge (the parallel #8211 session may claim 239).
- **Merging this PR mutates production.** `apply-web-platform-infra.yml` fires on push to `main`
  for `apps/web-platform/infra/*.tf`. Its `-target=` list (extended in Phase 4 item 5) creates the
  `infra-privileged` environment and its policy, the `workspaces-luks-cutover` policy, the Doppler
  project and environment, and the R2 bucket. It also forgets the four addresses. The merge click
  is therefore the operator's authorization for that apply. The PR body's **first line** must say
  so, and the pipeline does not merge.
- Extending the `-target=` allowlist must sweep every suite that asserts on it (sharp edge
  #4591). `git grep -ln -- '-target='` finds `plugins/soleur/test/terraform-target-parity.test.ts`,
  `tests/scripts/lib/destroy-guard-filter-web-platform.jq` and
  `tests/scripts/test-destroy-guard-counter-web-platform.sh`. The work phase re-runs that grep and
  updates every hit.

## Risks

- **R-a: the before-state PR plan with `-refresh=false` hides drift that reviewers used to see.**
  Mitigation: the plan comment header says so, and drift runs on its schedule.
- **R-c: the loader's GITHUB_ENV exports are visible to every later step of the job, including
  third-party actions.** This is the same exposure the App PEM export already has. The actions are
  pinned by SHA.
- **R-e: R1 still lets a `prd` repo-secret holder rewrite an environment policy.** Detective
  control: `scheduled-terraform-drift.yml` (Tier B) already plans the web-platform root's
  `github_repository_environment*` resources and the `infra/github` rulesets. A rewritten `main`
  policy or bypass list therefore surfaces as drift with the job's existing email/Sentry alert. The
  work phase confirms the drift job's plan covers the new `infra_privileged*` and
  `workspaces_luks_cutover_main` addresses (architecture review).
- **R-d: environment deployments create a deployment record for every Tier-B run.** This is
  cosmetic.
- **R-f (U1): a `removed` block destroys the live App identity in `prd`.** The two
  `doppler_secret.github_app_*` resources are the soleur-ai App's runtime key, not a copy.
  Mitigation: Guard 4 (address exists in state, `destroy = false` present, `-target` line
  present, no orphaned resource block), AC2c at PR time, the destroy-guard forget rows, and O0's
  U1 gate (before/after hashes, a no-`delete` assertion on the plan JSON, and an
  installation-token mint). Severity is the reason this has a guard of its own rather than a
  bullet in Guard 1.
- **R-g (U2): the wrong soleur-ai private key is deleted in the App settings UI.** No API exists
  for that delete (vendor limit), the two keys differ only by fingerprint, and the delete is
  **not reversible** — GitHub issues a new key, it does not restore one. Mitigation: O13 compares
  the DER-SHA-256 fingerprint of the `prd_terraform` key against the `prd` key and against the UI
  list before clicking, and proves the runtime key afterwards (AC19). Residual: a mis-click still
  costs a key regeneration and a web-app restart; the rollback is written out in O13.
- **R-h (U3): revoking `DOPPLER_TOKEN_TF` cascades to the service tokens it created.** The hosts
  read their own config with tokens Terraform minted under that personal token
  (`git-data-luks-boot`, `ghcr-minter-write`, the zot boot token). A cascade would not show until
  the next restart, because a running host holds its environment in memory. Mitigation: O12b is a
  read-only gate on O13 — the creator-bound set is enumerated from state, the vendor behaviour is
  confirmed in writing rather than assumed, and a disposable-personal-token negative control
  settles it empirically. AC20 re-reads each host after the revoke.
- **R-i (U4): a wrong slug in O11 revokes a token the running git store depends on.** Slugs are
  opaque and O11's stated verification (a cutover dry run) uses CI's own credential, so it is
  green either way. Mitigation: O11 resolves every slug back to its ledger **name** in a printed
  `name\tslug` table and aborts on a duplicate or missing name, then reads the git store's health
  through the host's own token within minutes (AC21).
- **R-j (U5): the incident-recovery paths fail closed and nobody finds out until an incident.**
  `git_data_host_replace` has no `environment:` today, so as a Tier-B job it can read no
  environment secret; between O3 and O10 the legacy fallback hides this. Mitigation: census rows
  8 and 9 (AC2b) at PR time, the `plan_only` arm (Guard 5), and O4b's dry-run dispatch of both
  paths from `main` **before** O10 (AC22). Accepted consequence: giving that job an environment
  means a non-`main` dispatch is refused, which is recorded as a decision in ADR-241 D2, in the
  job header and in the runbook.
