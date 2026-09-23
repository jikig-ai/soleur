# Runbook — Terraform credential tiers (#8209, ADR-239)

**Status:** current as of 2026-09-23 (#8209, ADR-239). Phase 2 (Terraform) has merged; no credential
has moved yet.
**Applies to:** the three Terraform roots `apps/web-platform/infra`, `infra/github` and
`apps/web-platform/infra/git-data-root-key`, the `rung2-rehearsal` root, and every workflow job that
reads Doppler `soleur/prd_terraform`.

**This file is the CANONICAL copy of the Operator Sequence.** The PR body and the generated
bootstrap script (`soleur:operator-bootstrap`, ADR-228) link here and deliberately do **not**
restate it. One copy of an ordered, partly irreversible credential sequence is the whole point: two
copies drift, and the drift is only discovered at the step that has no rollback.

## What the two tiers are

**Tier A** is whatever a workflow on any branch of this public repository can reach by naming a
repository-level secret. It keeps only credentials whose disclosure is bounded: a **read-only**
Hetzner token, a **read-only** bucket-scoped R2 state key, and the `prd_terraform` values that are
not in the Tier-B set.

**Tier B** is write- and root-equivalent credentials. They live in the Doppler **project**
`soleur-infra-privileged` (a project, **not** a `prd_*` branch config — a branch config inherits
from its root, which is how these became branch-reachable in the first place; learning
`2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`). They are delivered **only** as
GitHub **environment secrets**, on environments whose deployment-branch policy admits `main` only:
`infra-privileged`, `web-platform-infra-apply`, `inngest-cutover`, `workspaces-luks-cutover`.

The Tier-B names are `DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN` (read/write), `CF_API_TOKEN_R2`, the
Terraform GitHub App identity (`GITHUB_INFRA_APP_ID` / `GITHUB_INFRA_APP_INSTALLATION_ID` /
`GITHUB_INFRA_APP_PRIVATE_KEY`), `DOPPLER_TOKEN_WRITE`, `DOPPLER_TOKEN_GIT_DATA_ROOT` and the
read/write R2 state pair `TF_STATE_AWS_ACCESS_KEY_ID` / `TF_STATE_AWS_SECRET_ACCESS_KEY`.

**Residual R1, stated up front because it bounds every claim below.** The `soleur-ai` App's
*runtime* private key stays in Doppler `prd`, readable by `DOPPLER_TOKEN_PRD` and by every `prd_*`
branch-config repository secret, and that App holds `administration:write` on `jikig-ai/soleur` — so
a holder can rewrite an environment's deployment-branch policy. **The Tier-B boundary is nominal
until R1 closes.** Assessed at
`knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`.

## Consumer inventory

Derived from the workflow files themselves, job by job, not from prose. **Classification rule**
(plan Phase 1 item 2): a job that runs `terraform plan|apply|import` against a root whose variables
include a Tier-B variable is **Tier B**; a job that only reads Hetzner is **Tier A** and uses
`HCLOUD_TOKEN_READONLY`; a job that mints a GitHub App token for writes is **Tier B**.

Scope of the sweep: every job in `.github/workflows/` referencing `secrets.DOPPLER_TOKEN`,
`secrets.DOPPLER_TOKEN_PRD`, `secrets.DOPPLER_TOKEN_WRITE` or `secrets.DOPPLER_TOKEN_GIT_DATA_ROOT`.
Jobs whose only credential is `DOPPLER_TOKEN_PRD` read the `prd` **root** config, not
`prd_terraform`, and are outside the Tier-B credential set — they are listed anyway, because "it
reads Doppler" is the wrong discriminator and the inventory has to show that it was applied.

### Group 1 — `apply-web-platform-infra.yml` (`push` on `main` + infra paths, and `workflow_dispatch`)

| `workflow.yml::job` | Triggers reaching the job | `environment:` today | Credential(s) used | Read or write | Tier after |
|---|---|---|---|---|---|
| `apply-web-platform-infra.yml::apply` | push, workflow_dispatch | **(none)** — removed deliberately (PR #4220 note in the file) | `DOPPLER_TOKEN` → `prd_terraform` (`--name-transformer tf-var` ×3), `DOPPLER_TOKEN_WRITE`, R2 state `AWS_*` | **write** — 11 apply invocations plus 6 plans | **B** — production apply of the web-platform root, and it holds a read/write Doppler token |
| `::inngest_host` | workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** — plan ×6 then apply ×2 | **B** — apply |
| `::inngest_host_replace` | workflow_dispatch | (none) | `DOPPLER_TOKEN`, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — plan then apply/`-replace` | **B** — replaces a production host |
| `::inngest_volume_recut` | workflow_dispatch | **`inngest-cutover`** | `DOPPLER_TOKEN`, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** | **B** — apply, already on a Tier-B environment |
| `::registry_host_replace` | workflow_dispatch | (none) | `DOPPLER_TOKEN`, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** | **B** — apply |
| `::registry_region_migrate` | workflow_dispatch | (none) | `DOPPLER_TOKEN`, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** | **B** — apply |
| `::registry_pull_path_gate` | workflow_dispatch (gated on `apply_target == registry-luks-recut`) | (none) | `DOPPLER_TOKEN` → `HCLOUD_TOKEN`, `api.hetzner.cloud` GETs | **read** — the job carries no `-target` and performs no Terraform action at all (its own header says so) | **A** — read-only existence probe → `HCLOUD_TOKEN_READONLY` |
| `::registry_luks_recut` | workflow_dispatch | (none) | `DOPPLER_TOKEN`, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — destructive | **B** — apply |
| `::registry_store_restore` | workflow_dispatch (`needs: registry_luks_recut`) | (none) | `DOPPLER_TOKEN_PRD` only — reads the `prd` **root**, deliberately not `prd_terraform` | **read** (then a GHCR → zot image push) | **A** — never touches `prd_terraform`; outside the Tier-B credential set |
| `::git_data_host_replace` | workflow_dispatch | **(none)** — and its own comment says so | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — plan then apply/`-replace` | **B**, and this is the U5 row: a Tier-B job with no `environment:` can read no environment secret, so Phase 4 item 1 gives it `infra-privileged`. It is one of the two paths that recovers the product |
| `::workspaces_luks_cutover` | workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** | **B** — apply |
| `::workspaces_luks_recut` | workflow_dispatch | **`workspaces-luks-cutover`** | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** | **B** — apply, already on a Tier-B environment |
| `::web_host_create` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — host birth | **B** |
| `::web_host_replace` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — host replace | **B**, and the second U5 recovery path |
| `::git_data_host_create` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, R2 state `AWS_*` | **write** — host birth | **B** |
| `::ci_ssh_token_replace` | workflow_dispatch | (none) | `DOPPLER_TOKEN` **and `DOPPLER_TOKEN_WRITE`**, tf-var, R2 state `AWS_*` | **write** — apply plus a Doppler secret write | **B** — the sharpest un-gated row today: a write-scoped Doppler token with no reviewer gate |
| `::vector_redeliver` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** | **B** — apply |
| `::entrypoint_audit` | workflow_dispatch | (none) | `DOPPLER_TOKEN` → `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from `prd_terraform` (inline mint) | **write-capable** — mints an installation token | **B** — mints a GitHub App token |

### Group 2 — single-root apply workflows

| `workflow.yml::job` | Triggers reaching the job | `environment:` today | Credential(s) used | Read or write | Tier after |
|---|---|---|---|---|---|
| `apply-deploy-pipeline-fix.yml::apply` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** | **B** |
| `apply-github-infra.yml::apply` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*`, inline App-key mint (`GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY`) | **write** | **B** — apply plus an App key |
| `apply-git-data-root-key.yml::apply` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN`, tf-var, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** | **B** — apply of the root-key root |
| `git-data-rung2-rehearsal.yml::rehearse` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** | **B** — applies the rehearsal root |
| `apply-sentry-infra.yml::plan_pr` | **pull_request** | (none) | `DOPPLER_TOKEN` → `prd_terraform`, R2 state `AWS_*` | **read** — plan only | **A work on Tier-B credentials.** PR-reachable, so it must not hold a Tier-B secret: it takes the same split as `infra-validation::plan` — `-refresh=false`, placeholders, `github.token` |
| `apply-sentry-infra.yml::apply` | push, merge_group, workflow_dispatch | (none) | `DOPPLER_TOKEN` → `prd_terraform`, R2 state `AWS_*` | **write** | **B** — production apply |

### Group 3 — drift, validation and Hetzner-read jobs

| `workflow.yml::job` | Triggers reaching the job | `environment:` today | Credential(s) used | Read or write | Tier after |
|---|---|---|---|---|---|
| `scheduled-terraform-drift.yml::drift-check` | **`workflow_dispatch` only** — the file carries no `schedule:`; the twice-daily fire is Inngest-dispatched (ADR-033) | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **read** — the only Terraform call is `terraform plan -detailed-exitcode` | **B** by the rule (it plans a Tier-B root), but read-only: a **read**-scoped Tier-B token is sufficient, and that is what `DOPPLER_TOKEN_INFRA_PRIVILEGED` is |
| `scheduled-terraform-drift.yml::heartbeat-live-reconcile` | workflow_dispatch | (none) | `DOPPLER_TOKEN` → `BETTERSTACK_API_TOKEN_READONLY` | **read** — no Terraform at all | **A** |
| `scheduled-terraform-drift.yml::rung2-rehearsal-orphan-sweep` | workflow_dispatch | (none) | `DOPPLER_TOKEN` → `HCLOUD_TOKEN`, `api.hetzner.cloud` GETs, a Doppler config listing | **read** — the one `DELETE` is echoed into a recipe, never executed | **A** → `HCLOUD_TOKEN_READONLY` |
| `infra-validation.yml::check-secrets` | push, pull_request, workflow_dispatch | (none) | `DOPPLER_TOKEN` presence probe — never reads a value | **read** | **A** |
| `infra-validation.yml::plan` | **pull_request only**, deliberately | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **read** — plan only | **A.** This is the job the whole Tier-A design is built around: `-refresh=false`, a read-only Hetzner token, placeholders for the Doppler and R2 providers, and the workflow's own `github.token` for the GitHub provider (measured, plan M8) |
| `workspaces-luks-cutover.yml::preflight` | workflow_dispatch | (none) by design | `DOPPLER_TOKEN` → the cf-tunnel SSH bridge | **read** | **A** |
| `workspaces-luks-cutover.yml::cutover` | workflow_dispatch | **`workspaces-luks-cutover`** | `DOPPLER_TOKEN` → `HCLOUD_TOKEN` (a volume-id lookup) | **read** on the Hetzner side — no Terraform in the file | **A** for the Hetzner read → `HCLOUD_TOKEN_READONLY`. The job keeps its Tier-B environment gate for its host-side mutation, which is why that environment gains a `main` policy in this PR |
| `workspaces-luks-verify.yml::verify` | schedule, workflow_dispatch | (none) | `DOPPLER_TOKEN` — read-only probe | **read** | **A** |

### Group 4 — App-token minters and the remaining `prd_terraform` readers

| `workflow.yml::job` | Triggers reaching the job | `environment:` today | Credential(s) used | Read or write | Tier after |
|---|---|---|---|---|---|
| `board-status-sync.yml::sync` | `issues`, `pull_request` | (none) | `DOPPLER_TOKEN` → `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` inline mint | **write** — mints an installation token and writes board Status | **B** by the rule, and the highest-exposure row in this table: a write-capable App mint reachable from `pull_request`. **This is why O1b exists** — it gets its own least-privilege `soleur-board` App (`apps/web-platform/infra/github-board-app-manifest.json`) whose credentials stay Tier A, rather than a Tier-B carrier it cannot reach from a PR event |
| `build-inngest-bootstrap-image.yml::bump-cloud-init-pin` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN` → `.github/actions/mint-soleur-ai-app-token` (project `soleur`, config `prd_terraform`) | **write** — `contents:write` + `pull_requests:write` installation token | **B** — App token for writes |
| `build-inngest-bootstrap-image.yml::build` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN_PRD` | **read** | **A** — `prd` root config |
| `cutover-inngest.yml::cutover` | workflow_dispatch, push | **`inngest-cutover`** | `DOPPLER_TOKEN` → `HCLOUD_TOKEN` for `op=backup` | **read** on the Hetzner side; no Terraform | **A** for the Hetzner read → `HCLOUD_TOKEN_READONLY`; keeps its Tier-B environment gate |
| `git-data-cutover.yml::cutover` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN`, **`DOPPLER_TOKEN_GIT_DATA_ROOT`** | **read** of all three; host-side cutover write | **B** — it holds `DOPPLER_TOKEN_GIT_DATA_ROOT`. **No edit to this file is needed and none is made**: it belongs to the parallel #8211 session, it already declares a Tier-B environment, and an environment secret overrides a repository secret of the same name |
| `inngest-config-drift.yml::compare` | workflow_dispatch | (none) | `DOPPLER_TOKEN` → ClickHouse / Better Stack read credentials from `prd_terraform` | **read** | **A** |
| `scheduled-inngest-health.yml::connector_census` | schedule, workflow_dispatch | (none) | `DOPPLER_TOKEN` — already the read-only token for this config | **read** | **A** |
| `build-inngest-config-bundle.yml::build-sign-publish` | workflow_dispatch | **`inngest-config-signing`** | `DOPPLER_TOKEN_PRD` | **read** | **A** — `prd`, not `prd_terraform` |
| `registry-zot-inventory.yml::inventory` | workflow_dispatch, push | (none) | `DOPPLER_TOKEN_PRD` | **read** | **A** |
| `reusable-release.yml::release` | `workflow_call` | (none) | `DOPPLER_TOKEN_PRD` | **read** | **A** |
| `web-platform-release.yml::migrate`, `::verify-migrations`, `::verify-doppler-secrets`, `::live-verify` | push, workflow_dispatch, workflow_run | (none) | `DOPPLER_TOKEN_PRD` | **read** (plus DB migrations; no Terraform) | **A** — `prd` app config, outside the Tier-B credential set |

### Three things the sweep found that the plan's prose did not carry

1. **`apply-sentry-infra.yml` is a fourth apply root and a second PR-reachable `prd_terraform`
   reader.** Its `plan_pr` job runs on `pull_request` and its `apply` job does a production apply
   with no `environment:`. Both need the same Tier-A / Tier-B split as `infra-validation::plan` and
   `apply-web-platform-infra::apply`.
2. **`scheduled-terraform-drift.yml` has no `schedule:` trigger** despite the name — the reachable
   trigger is `workflow_dispatch`, and the twice-daily fire comes from Inngest (ADR-033). Any step
   below that says "dispatch the drift check" means exactly that, and there is no cron to wait for.
3. **`registry_pull_path_gate` is Tier A, not Tier B.** It carries no `-target` and runs no
   Terraform action; it is a Hetzner existence probe. Its own abort message names
   `registry-luks-recut` rather than itself, which is a copy-paste label worth not being misled by
   when reading its log.

### `environment:` coverage, which is what AC2b asserts

Tier-B jobs that declare **no** `environment:` today, and therefore fail closed the moment O10
removes the legacy fallback: `apply-web-platform-infra::apply`, `::inngest_host`,
`::inngest_host_replace`, `::registry_host_replace`, `::registry_region_migrate`,
`::registry_luks_recut`, `::git_data_host_replace`, `::workspaces_luks_cutover`,
`::ci_ssh_token_replace`, `::entrypoint_audit`, `apply-deploy-pipeline-fix::apply`,
`apply-github-infra::apply`, `apply-sentry-infra::apply`, `board-status-sync::sync`,
`build-inngest-bootstrap-image::bump-cloud-init-pin`, `scheduled-terraform-drift::drift-check`.
Phase 4 binds each to a member of the Tier-B environment set; the census row is RED until it does.

`infra-privileged` does not exist in the repository's workflows yet — it is created by O0's push
apply and referenced by Phase 4. Of the four Tier-B environments, three are live today
(`web-platform-infra-apply`, `inngest-cutover`, `workspaces-luks-cutover`).

## Operator Sequence (canonical copy — verbatim from the plan)

Reproduced verbatim from `knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md` §Operator Sequence. This runbook is the canonical copy; the plan section is its origin. There is no O9 — the numbering skips it.

<!-- markdownlint-disable MD034 -->
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
| O10 | Evict from Tier A **(irreversible)**. Preconditions: O1b, O3, O4, O5, O5b and O8 all done | `for k in DOPPLER_TOKEN_TF HCLOUD_TOKEN CF_API_TOKEN_R2; do doppler secrets delete "$k" -p soleur -c prd_terraform --yes; done`; `printf '%s' EVICTED_SEE_ADR_238 \| doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --silent` | the three names are absent; `[ "$(printf '%s' "$(doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --plain)" \| sha256sum)" = "$(printf '%s' EVICTED_SEE_ADR_238 \| sha256sum)" ] && echo equal`; a PR touching `apps/web-platform/infra/` is green; push apply, drift, board sync and the pin bump are green | re-set the three from Tier B (O2 pattern); `doppler secrets delete GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform` drops the override |
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

**One rendering defect is inherited from the verbatim source, and is recorded rather than
silently repaired.** O11's verify cell contains a single UNESCAPED `|` — the shell pipe in
`printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl …` — while every
other pipe in the table is written `\|`. GitHub therefore splits that one row into six cells
instead of five, so O11's rollback text appears shifted. **The command is correct as written**:
the pipe is part of it, and that is exactly why it was not escaped away here. Read O11's row as
four fields regardless of how the table renders it. Escaping it is a correction to make in the
plan and here together, not in one copy.
<!-- markdownlint-enable MD034 -->

## State migration

The one state object `web-platform/git-data-root-key/terraform.tfstate` moves from
`soleur-terraform-state` to `soleur-terraform-state-privileged`. This section is what O8 and O12
refer to.

**Why it moves at all.** A distinct **key** inside a **shared** bucket was never isolation:
listing `soleur-terraform-state` with the Tier-A `prd_terraform` `AWS_*` pair returns all seven
state objects, this one included (plan M7). That object holds the SSH private key that is root on
the host storing every connected user's repositories. The Tier-A pair is bucket-scoped
(`ListBuckets` returns `AccessDenied`), so a bucket it is not scoped to is genuinely out of reach
rather than merely un-referenced.

**No key is ever printed, and no key reaches `argv`.** Every call below reads its credentials from
a `curl` config file created with `umask 077`, passed as `-K "$CFG"`. That is the same discipline
as O5's `-H @"$HDR"` header file, and it is stronger than `--user "$AK:$SK"`, which would put the
secret in the process table for anything on the machine to read.

### The credential the copy needs

A server-side copy is a single request that **reads the source and writes the destination**, so it
needs one credential scoped to **both** buckets. Neither the Tier-A pair (source only, and
read/write until O5b makes it read-only) nor the O8 bucket-scoped destination pair can do it alone.
Mint a **temporary** R2 API token scoped to exactly the two buckets — Object Read on
`soleur-terraform-state`, Object Read & Write on `soleur-terraform-state-privileged` — use it for
this section only, and delete it at the end. ADR-130: no credential held here can mint a
bucket-scoped R2 token programmatically, so this one comes from the Cloudflare dashboard like the
others.

```bash
set -euo pipefail
umask 077

ACCOUNT=4d5ba6f096b2686fbdd404167dd4e125
EP="https://$ACCOUNT.r2.cloudflarestorage.com"
SRC=soleur-terraform-state
DST=soleur-terraform-state-privileged
KEY=web-platform/git-data-root-key/terraform.tfstate

# The temporary two-bucket pair goes into a 0600 curl config and nowhere else.
CFG="$(mktemp)"; chmod 600 "$CFG"
trap 'shred -u "$CFG" 2>/dev/null || rm -f "$CFG"' EXIT
{
  printf 'aws-sigv4 = "aws:amz:auto:s3"\n'
  printf 'user = "%s:%s"\n' "$R2_TMP_ACCESS_KEY_ID" "$R2_TMP_SECRET_ACCESS_KEY"
  printf 'silent\nshow-error\ndisable\nnoproxy = "*"\n'
} > "$CFG"
unset R2_TMP_ACCESS_KEY_ID R2_TMP_SECRET_ACCESS_KEY
```

`aws-sigv4 = "aws:amz:auto:s3"` is the R2 form: R2's region is the literal `auto`. `curl` computes
and sends `x-amz-content-sha256` itself for the empty body, so it is not set by hand here.

### The server-side copy (O8)

```bash
# PUT the destination object with x-amz-copy-source — the bytes never transit this machine.
code="$(curl -K "$CFG" --fail-with-body \
  -X PUT "$EP/$DST/$KEY" \
  -H "x-amz-copy-source: /$SRC/$KEY" \
  -o /dev/null -w '%{http_code}')"
[ "$code" = "200" ] && echo copied || { echo "copy failed: $code"; exit 1; }
```

A `200` with a `CopyObjectResult` body is success; the body is discarded to `/dev/null` because it
is not needed and printing bodies is how a state object ends up in a terminal scrollback. Any other
code stops the sequence: O8 is reversible only while both objects exist.

### The equality proof — `sha256`, `lineage` and `serial`, printing only `equal`

The state object contains the root key. It is compared **in process** and only the verdict is
printed. Nothing here writes the object to disk.

```bash
# (1) byte-identity
a="$(curl -K "$CFG" --fail-with-body "$EP/$SRC/$KEY" | sha256sum | cut -d' ' -f1)"
b="$(curl -K "$CFG" --fail-with-body "$EP/$DST/$KEY" | sha256sum | cut -d' ' -f1)"
[ "$a" = "$b" ] && echo equal || { echo differ; exit 1; }
unset a b

# (2) Terraform's own identity fields — lineage and serial — read with jq, never echoed
la="$(curl -K "$CFG" --fail-with-body "$EP/$SRC/$KEY" | jq -r '.lineage')"
lb="$(curl -K "$CFG" --fail-with-body "$EP/$DST/$KEY" | jq -r '.lineage')"
sa="$(curl -K "$CFG" --fail-with-body "$EP/$SRC/$KEY" | jq -r '.serial')"
sb="$(curl -K "$CFG" --fail-with-body "$EP/$DST/$KEY" | jq -r '.serial')"
{ [ "$la" = "$lb" ] && [ "$sa" = "$sb" ]; } && echo equal || { echo differ; exit 1; }
unset la lb sa sb
```

Both limbs are required and neither implies the other. `sha256` alone would pass on two copies of a
**stale** object; `lineage`/`serial` alone would pass on two objects that differ in resource
content. Terraform refuses a state whose `lineage` changed under it, which is the failure this
proves against before the backend is repointed.

### The negative probe, before anything is deleted

```bash
# With the TIER-A prd_terraform pair (a separate 0600 config, $CFG_A), the new object must be
# unreachable. 403 is the expected answer; a 200 means the new bucket is not actually isolated.
curl -K "$CFG_A" -o /dev/null -w '%{http_code}\n' "$EP/$DST/$KEY"
```

`403` (or `404`) passes. `200` stops the sequence — the whole point of the second bucket is that
the Tier-A pair is not scoped to it.

### The delete (O12) — irreversible

Preconditions: O8 landed, the `GIT_DATA_ROOT_STATE_*` pair is set, the repo variable
`GIT_DATA_ROOT_STATE_MIGRATED=1` is set, the dispatch of `apply-git-data-root-key.yml` from `main`
was green against the new bucket, and the two proofs above printed `equal`.

```bash
code="$(curl -K "$CFG" -X DELETE "$EP/$SRC/$KEY" -o /dev/null -w '%{http_code}')"
[ "$code" = "204" ] && echo deleted || { echo "delete returned: $code"; exit 1; }

# Verification: a Tier-A listing no longer shows the key. Names only; no object is fetched.
curl -K "$CFG_A" "$EP/$SRC?list-type=2&prefix=web-platform/git-data-root-key/" \
  | grep -c '<Key>' || true   # expect 0
```

Then delete the temporary two-bucket R2 token in the Cloudflare dashboard, and confirm it is gone
by re-running the copy command and reading `403`.

R2 does not implement the S3 object-versioning API (measured under #7836 and recorded at Art. 30
PA-12 §(f)), so this delete has no vendor-side undo. The destination copy is the only copy from
that moment, which is why the equality proof is a gate and not a formality.

## Rotation

Every credential in the Tier-B set was readable from any branch of a public repository for an
as-yet-undated window. Tiering stops that going forward; **rotation is what makes the past stop
mattering**, and it is required rather than recommended (plan R5, AC16, a CPO condition).

### The invariant

**One credential at a time, and in this shape:** set the new value in Tier B → dispatch the O4
canary from `main` → only then delete the old value. Never two at once: a canary that goes red
after two changes does not say which one broke it, and the rollback budget is the window in which
the old value is still valid.

### Order

| # | Credential | Where the new value lands | Canary | The old value's negative probe (AC16) |
|---|---|---|---|---|
| 1 | Hetzner read/write token | `HCLOUD_TOKEN` in `soleur-infra-privileged/prd` | O4 | `GET /v1/servers` with the old token returns `401` |
| 2 | `CF_API_TOKEN_R2` | same project/config | O4 | the old token fails `GET /user/tokens/verify` |
| 3 | `DOPPLER_TOKEN_TF` (a new **personal** token, then revoke the old one) | same project/config | O4 | `doppler me` with the old token returns `401` |
| 4 | the read/write R2 state key (`TF_STATE_AWS_*`) | same project/config | O4, whose apply writes state | the old pair's `PutObject` to a scratch key returns `403` |
| 5 | **the `soleur-ai` App key that `prd_terraform` held** — deleted in the App's settings | nowhere; it is a delete, not a rotation | O4 must already be green | a JWT signed with the old Terraform key returns `401` from `GET /app` |

**Step 3 does not start until §O12b below is answered.** **Step 5 is the one irreversible step with
no rollback**, follows O10 and a green O4, and is preceded by the fingerprint comparison in O13(b)
and followed immediately by O13's runtime proof — a `401` from *both* keys means the runtime key
was deleted, and that is a page.

Cloudflare's token **roll** endpoint returns the new value in its response body, so step 2 is piped
straight into `doppler secrets set … --silent` from the shell variable holding it and never
rendered. Hetzner and Doppler personal tokens have no roll API; their new values are minted in the
vendor's own console and arrive by stdin from a 0600 file that is `shred -u`'d after.

### O12b — the determination this rotation's step 3 is gated on

The question, stated so it cannot be answered by assumption: **does revoking the creating personal
token invalidate the Doppler service tokens it created?** Terraform ran as `DOPPLER_TOKEN_TF`, a
workplace **personal** token, and created the service tokens the production hosts read their own
configuration with — `doppler_service_token.git_data` (`git-data-luks-boot`, `git-data-luks.tf`),
`doppler_service_token.ghcr_minter` (`ghcr-minter-write` on `soleur/prd`,
`ghcr-minter-doppler-token.tf`) and `doppler_service_token.registry` (the zot boot token,
`zot-registry.tf`). These are **boot** tokens: a live host keeps working on the environment it has
already read, so a cascade would surface at the next restart of a host, not at the revocation.

A service token is a distinct object with its own slug and its own config scope, so the **expected**
answer is that it survives. **An expected answer is not a confirmed one.** This block is where the
confirmation is recorded, and step 3 above does not run until all three rows are filled.

| Limb | How it is established | Recorded result |
|---|---|---|
| (1) The creator-bound set, from state rather than memory | `terraform state list \| grep '^doppler_service_token\.'` in each root; every name goes into the bootstrap ledger | **NOT YET RUN** |
| (2) Vendor-side citation | Doppler's service-token documentation on token lifecycle and ownership (URL + retrieval date), **plus** a written confirmation from Doppler support quoting the token names above (ticket id + the quoted sentence) | **NOT YET RUN** — the citation is filed here verbatim, not summarised |
| (3) Live negative control, decisive on its own | Mint a throwaway `read` service token using a **second, disposable** personal token; revoke that disposable personal token; then read one secret with the service token | **NOT YET RUN** — `200` proves no cascade; `401` proves there is one |

**If (3) returns `401`**, step 3 of the rotation order **must not run** until every host token in
(1) has been re-minted by a surviving identity. If (2) and (3) disagree, (3) governs: it is the
behaviour of the live workplace, and (2) is a description of it.

Nothing in O12b changes anything. It is a read-only gate, and O13 does not start until it passes.

### After step 3, prove the hosts still read their own configuration

O12b establishes the expectation; this establishes the fact. It is read from CI and from the
observability layer, with no shell on any host: each host's Better Stack heartbeat and dedicated log
source still report (the O11 read-only query), `heartbeat-live-reconcile` is green on a `main`
dispatch of `scheduled-terraform-drift.yml`, a `git ls-remote` against the store returns refs, and a
`docker pull` of the current pin from ghcr succeeds. Then force the case a cached environment hides:
dispatch `apply-web-platform-infra.yml` with `apply_target=entrypoint-audit` for the CI-side read,
and schedule the real proof — the next host replace, dispatched from `main` through the workflow —
as a deliberate, announced step rather than letting it arrive during an unrelated incident.

## Local Terraform invocation

After the cutover the local invocation is **two nested loaders**, and the inner one carries
`--preserve-env`:

```bash
cd apps/web-platform/infra
doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- terraform plan
```

**The inner `--preserve-env` is the safety, and it is load-bearing.** `doppler run` overrides
existing environment variables by default. Without the flag the inner (Tier-A) loader would
overwrite the outer (Tier-B) values, and a branch actor holding `DOPPLER_TOKEN_WRITE` could plant
`HCLOUD_TOKEN=<their own account>` in `prd_terraform` and have a privileged run plan against it.
With the flag, the outer values win **by construction** — it is not a property of what
`prd_terraform` happens to contain, and no census can read Doppler's contents to check.

Measured (plan Phase 2.8 sentinel): bare `--preserve-env` and `--preserve-env=TF_VAR_hcloud_token`
both keep the environment's value; the **source** name `HCLOUD_TOKEN` does not, because the
transformer has already renamed the key; and there is no `DOPPLER_PRESERVE_ENV` variable form. The
flag must be on the **inner** command — on the outer one it would preserve whatever the ambient
shell held, which is the opposite of the intent.

The same nesting applies to `infra/github` (`cd infra/github`). Every `doppler run` in a Tier-B CI
job carries the same flag, asserted by the census (Guard 2).

### The `git-data-root-key` root now needs `-backend-config=bucket=…`

That root's `backend "s3"` block no longer pins a bucket literal — it is a **partial** backend, so
`init` fails without the bucket:

```bash
cd apps/web-platform/infra/git-data-root-key

# BEFORE the O8 migration:
terraform init -input=false -backend-config=bucket=soleur-terraform-state

# AFTER the O8 migration (and after GIT_DATA_ROOT_STATE_MIGRATED=1, which makes the loader
# refuse the legacy bucket so a late run cannot write back to the object O12 deletes):
terraform init -input=false -backend-config=bucket=soleur-terraform-state-privileged
```

Passing the wrong bucket is not a silent error: `init` reports the state as empty and the next plan
proposes to create every resource in the root. That is the shape to stop on, not to confirm.

The backend credentials are the `AWS_*` pair for whichever bucket is named — Tier-A `prd_terraform`
before O5b, `TF_STATE_AWS_*` from Tier B after it, and `GIT_DATA_ROOT_STATE_AWS_*` for the
privileged bucket. The PR plan job never initializes this nested root (detect-changes collapses it
into its parent, ADR-220 D2.2), so no PR-side backend config exists or is needed.

## Rollback

Each step's own rollback is in its row of the Operator Sequence. This section is O0's, because O0's
is the one that is not what it looks like.

### O0's rollback is NOT a plain revert

A revert of the Phase 2 commit deletes the new resource blocks **and their `prevent_destroy`
lifecycle pins with them**. Terraform would then read six live objects with no HCL declaring them
and plan a **destroy**: the `soleur-infra-privileged` project (with every secret O2 put in it), the
`infra-privileged` environment (with the Tier-B secret O3 put in it), and the
`soleur-terraform-state-privileged` bucket (which after O8 holds the **only** copy of the git-data
root-key state). `prevent_destroy` cannot save any of them, because a revert deletes the pin in the
same diff as the resource.

**The rollback only goes forward.** It is a follow-up PR that does two things.

#### Set 1 — swap each resource this PR CREATED for a `removed` block that forgets, never destroys

All in `apps/web-platform/infra`:

```hcl
removed { from = github_repository_environment.infra_privileged                          lifecycle { destroy = false } }
removed { from = github_repository_environment_deployment_policy.infra_privileged_main   lifecycle { destroy = false } }
removed { from = github_repository_environment_deployment_policy.workspaces_luks_cutover_main lifecycle { destroy = false } }
removed { from = doppler_project.infra_privileged                                        lifecycle { destroy = false } }
removed { from = doppler_environment.infra_privileged_prd                                lifecycle { destroy = false } }
removed { from = cloudflare_r2_bucket.terraform_state_privileged                         lifecycle { destroy = false } }
```

(Written on one line each for readability; the committed form is the multi-line block the four
existing forgets already use.) `destroy = false` is the whole difference between a rollback and an
outage — without it `removed` means DELETE.

`github_repository_environment_deployment_policy.workspaces_luks_cutover_main` is on the list
because this PR created it too: that environment's live `deployment_branch_policy` was measured
`null`, so a run on any branch that cleared its reviewer click could deploy to it. Forgetting it
leaves the live policy in place, which is the safe direction; a revert would remove the policy and
re-open the branch reach.

#### Set 2 — restore the resources this PR FORGOT, with their resource blocks plus `import` blocks

Four in `apps/web-platform/infra`:

| Address | Import id form |
|---|---|
| `doppler_secret.github_app_id` | `soleur.prd.GITHUB_APP_ID` |
| `doppler_secret.github_app_private_key` | `soleur.prd.GITHUB_APP_PRIVATE_KEY` |
| `doppler_service_token.write` | `soleur.prd_terraform.<slug>` |
| `github_actions_secret.doppler_token_write` | `soleur:DOPPLER_TOKEN_WRITE` |

Two in `apps/web-platform/infra/git-data-root-key`:

| Address | Import id form |
|---|---|
| `doppler_service_token.git_data_root_read` | `soleur-git-data-root.prd.<slug>` |
| `github_actions_secret.doppler_token_git_data_root` | `soleur:DOPPLER_TOKEN_GIT_DATA_ROOT` |

The `<project>.<config>.<name>` and `<repository>:<SECRET_NAME>` shapes are the ones this repository
already uses (`apply-github-infra.yml`'s two import-id shapes, and the
`doppler_config.git_data_prd soleur.prd_git_data` recipe in `apply-web-platform-infra.yml`).

**Two of those six restore MANAGEMENT but not the VALUE relationship, and that is a real limit, not
a footnote.** A `doppler_service_token`'s `key` is returned by the API only at create time, and a
`github_actions_secret`'s `plaintext_value` is never readable back. So an adoption of
`doppler_service_token.write` leaves `key` unknown, and the `github_actions_secret` that consumes it
plans a rewrite with a value Terraform does not have. For those two pairs the honest rollback is to
**re-create** — a fresh service token and a fresh repository secret written from it, exactly as the
original resources did on first apply — with the adoption form kept here for the case where the
follow-up PR is restoring the declaration rather than the value. The two `doppler_secret.github_app_*`
addresses adopt cleanly: they pin `config = "prd"`, they carry `ignore_changes = [value]`, and the
live values are untouched by a forget.

#### Why the target list must not be tidied in the same PR

`apply-web-platform-infra.yml` applies this root with a `-target=` allow-list, and a `removed` block
is planned **only when its address is targeted**. The `-target=` lines for the four forgotten
addresses therefore stay until the forget has actually landed — an untargeted `removed` block leaves
the resource in state with no HCL declaring it, which the next untargeted apply reads as a plain
destroy. Removing those lines is R6 work, after the forget is confirmed, not rollback work.

#### The gate that makes O0 recoverable at all

O0's verification is a **stop, not a note**. If the push apply's plan JSON shows a `delete` action on
`doppler_secret.github_app_id` or `doppler_secret.github_app_private_key`, or if the `prd` key hashes
recorded before the merge have changed, the sequence halts at O0 — because that pair **is** the
`soleur-ai` App's live runtime identity, and its loss disconnects every connected user with no
rollback beyond pasting a key back. That is U1, and it is the reason this section exists in a
runbook rather than in a commit message.

## Related

- ADR-239 — the decision this runbook executes.
- `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` — the Art. 33 assessment.
  **Its L1 evidence limb must be gathered before O12 and O13**: GitHub Actions logs and run records
  expire at 90 days.
- `apps/web-platform/infra/github-infra-app-manifest.json`,
  `apps/web-platform/infra/github-board-app-manifest.json` — the two App manifests O1 and O1b use.
- `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` — the manifest flow,
  including the form-post helper and the permission-widening re-acceptance click.
- `tests/scripts/test-infra-privileged-tier-census.sh` — the PR-time guard for everything in
  §Consumer inventory.
