# Runbook — Terraform credential tiers (#8209, ADR-241)

**Status:** current as of 2026-09-23 (#8209, ADR-241). Phase 2 (Terraform) has merged; no credential
has moved yet.
**O0 completed 2026-09-24.** The first four push applies after the merge (35912754656, 35921899265,
35927849285, 35951193547) failed creating `doppler_project.infra_privileged`: its description was
273 characters against Doppler's 255 cap. Everything else in O0 applied in the first of them. The
fix (#8668) merged and push apply 35963237090 created the project and its `prd` environment (plan
`3 to add, 1 to change, 0 to destroy`). O2 is unblocked. `scripts/lint-doppler-description-length.py`
now fails a PR carrying an over-cap `doppler_*` description.
**Applies to:** the three Terraform roots `apps/web-platform/infra`, `infra/github` and
`apps/web-platform/infra/git-data-root-key`, the `rung2-rehearsal` root, and every workflow job that
reads Doppler `soleur/prd_terraform`.

**This file is the CANONICAL copy of the Operator Sequence.** The PR body and the generated
bootstrap script (`soleur:operator-bootstrap`, ADR-228) link here and deliberately do **not**
restate it. One copy of an ordered, partly irreversible credential sequence is the whole point: two
copies drift, and the drift is only discovered at the step that has no rollback.
It is likewise the canonical copy of the #8609 runtime-App-key sequence (R-steps 0–9), in §Runtime App
key (#8609) below (added 2026-09-30), and of the #9321 release-job App source sequence, in §Release-job App
source (#9321) below (added 2026-10-01).

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

**Dated note, 2026-09-30 (#8609).** R1's mechanism is ADR-241 D10: the runtime key moves, rotated, to
the isolated Doppler project `soleur-github-app`, through §Runtime App key (#8609) below. ADR-241 marks
residual R1 OPEN — mechanism merged (D10); it closes on that section's gates G1–G4. The paragraph above
stays true until they hold.

## Consumer inventory

Derived from the workflow files themselves, job by job, not from prose. **Classification rule**
(plan Phase 1 item 2): a job that runs `terraform plan|apply|import|destroy` against a root whose
variables include a Tier-B variable is **Tier B** (the census classifies `destroy` with `apply`: both
write the state object and need the same credentials); a job that only reads Hetzner is **Tier A** and uses
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

*Dated note, 2026-10-01 (#9360), on `::entrypoint_audit`:* it no longer mints an App token; it
posts with the job's own `github.token` (`issues: write`). Its Doppler reads are now the CF ones only.
The row's "(none)" predates the job's `environment: infra-privileged` binding.

### Group 2 — single-root apply workflows

| `workflow.yml::job` | Triggers reaching the job | `environment:` today | Credential(s) used | Read or write | Tier after |
|---|---|---|---|---|---|
| `apply-deploy-pipeline-fix.yml::apply` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*` | **write** | **B** |
| `apply-github-infra.yml::apply` | push, workflow_dispatch | (none) | `DOPPLER_TOKEN` tf-var, R2 state `AWS_*`, inline App-key mint (`GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY`) | **write** | **B** — apply plus an App key |
| `apply-git-data-root-key.yml::apply` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN`, tf-var, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** | **B** — apply of the root-key root |
| `git-data-rung2-rehearsal.yml::rehearse` | workflow_dispatch | **`web-platform-infra-apply`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** | **B** — applies the rehearsal root |
| `git-data-rung2-rehearsal.yml::teardown` | workflow_dispatch (`needs: rehearse`, `if: always()`) | **`infra-privileged`** | `DOPPLER_TOKEN` tf-var, `HCLOUD_TOKEN`, `api.hetzner.cloud`, R2 state `AWS_*` | **write** — `terraform destroy` of the rehearsal root | **B** — destroys against the privileged state bucket; no reviewer, so teardown never waits on a second approval |
| `apply-sentry-infra.yml::plan_pr` | **pull_request** | (none) | `DOPPLER_TOKEN` → `prd_terraform`, R2 state `AWS_*` | **read** — plan only | **A work on Tier-B credentials.** PR-reachable, so it must not hold a Tier-B secret: it takes the same split as `infra-validation::plan` — `-refresh=false`, placeholders, `github.token` |
| `apply-sentry-infra.yml::apply` | push, merge_group, workflow_dispatch | (none) | `DOPPLER_TOKEN` → `prd_terraform`, R2 state `AWS_*` | **write** | **B** — production apply |

*Dated note, 2026-10-01 (#9360), on `apply-github-infra.yml::apply`:* the inline App-key mint is
gone. The credential is `DOPPLER_TOKEN_INFRA_PRIVILEGED` → `.github/actions/mint-infra-app-token`
(soleur-infra, `administration:write` on `soleur-marketplace` only), run before Terraform. *Dated note,
2026-10-03 (#9321):* the composite's default source is now the narrow `soleur-infra-app` project, so this
job names the whole Tier-B project explicitly with `doppler-project: soleur-infra-privileged` beside the
broad token (it already holds that token for Terraform); the shape suite pins both lines, and dropping the
`doppler-project` line would make every `infra/github` apply stop at this mint step. The two
`soleur` ruleset probes use the job's `github.token`. None of these failures is a key problem, and
none is fixed by setting anything in `prd_terraform`. The mint's message names the cause; it does not
print the HTTP status, so match on the text:

| Message (mint step or the check before it) | Cause | Remedy |
|---|---|---|
| `title=infra-app-installation` | loader on its legacy arm, or a different installation id | restore the `infra-privileged` environment secret, or reconcile `GITHUB_INFRA_APP_INSTALLATION_ID` |
| `…not accessible…` / `…not installed…` (relayed from GitHub) | the installation's repository grant no longer covers `soleur-marketplace` | operator-authorized grant change |
| `…permissions requested are not granted…` (relayed) | the App or installation lost `administration:write`, or a permission change was not accepted | operator-authorized App change |
| grant-mismatch lines (exact-grant check) | the App's permissions drifted from `apps/web-platform/infra/github-infra-app-manifest.json` | operator-authorized App change |

Diagnose (agent, read-only): `gh api /orgs/jikig-ai/installations --jq
'.installations[]|select(.app_slug=="soleur-infra")|{repository_selection,permissions}'`. Remedy: the
operator authorizes the change in the App or installation settings
(`hr-menu-option-ack-not-prod-write-auth`). Verify (agent): dispatch `apply-github-infra.yml` from
`main` and find `app=soleur-infra` in the `app-token` notice.

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
| `build-inngest-bootstrap-image.yml::bump-cloud-init-pin` (re-tiered by #9262) | workflow_dispatch only — #9262 removed the `push: tags` trigger (ADR-232 A5), so every build is dispatched from `main` | **`infra-privileged`** (#9262) | `DOPPLER_TOKEN_INFRA_APP` (since 2026-10-03, #9321; `DOPPLER_TOKEN_INFRA_PRIVILEGED` from #9262 until then) → `.github/actions/mint-infra-app-token`, which reads `GITHUB_INFRA_APP_ID` / `GITHUB_INFRA_APP_PRIVATE_KEY` from its default source, the narrow project `soleur-infra-app`, config `prd` (no `doppler-project` input; before 2026-10-03 the fixed source was `soleur-infra-privileged`); installation `166065653`, scoped to `permissions: {"contents":"write","pull_requests":"write"}`, `repositories: soleur` | **write** — scoped `contents:write` + `pull_requests:write` installation token of the `soleur-infra` App | **B** — App token for writes. **Before #9262:** push (tags) and workflow_dispatch, no `environment:`, `DOPPLER_TOKEN` → `.github/actions/mint-soleur-ai-app-token` (renamed `mint-infra-app-token` in #9262; project `soleur`, config `prd_terraform`), unscoped |
| `build-inngest-bootstrap-image.yml::build` | workflow_dispatch (the `push: tags` trigger was removed by #9262) | (none) | `DOPPLER_TOKEN_PRD` | **read** | **A** — `prd` root config |
| `mint-inngest-bootstrap-tag.yml::mint` (added by #4326; re-tiered by #9262) | push to `main` (paths), workflow_dispatch; job-gated `github.ref == 'refs/heads/main'` | **`infra-privileged`** (#9262) | Two, never in one step: `DOPPLER_TOKEN_INFRA_APP` (since 2026-10-03, #9321; `DOPPLER_TOKEN_INFRA_PRIVILEGED` from #9262 until then) → `.github/actions/mint-infra-app-token` (default source `soleur-infra-app`/`prd`; before 2026-10-03 the fixed source was `soleur-infra-privileged`/`prd`), installation `166065653`, scoped to `permissions: {"actions":"write"}`, `repositories: soleur`, minted BEFORE the tag step and read only by the dispatch step (then revoked); and the job's `GITHUB_TOKEN` (`contents: write`) for the tag write only | **write** — a tag ref, then one `workflow_dispatch` | **B** — a push-to-`main` job, so the `main` policy admits it. **Before #9262:** no `environment:`, and its App step read the soleur-ai key from `prd_terraform` through `DOPPLER_TOKEN`, so O10's sentinel would have failed it with `verdict=legacy_app_key_evicted` before any tag was cut (ADR-232 §8) |
| `cutover-inngest.yml::cutover` | workflow_dispatch, push | **`inngest-cutover`** | `DOPPLER_TOKEN` → `HCLOUD_TOKEN` for `op=backup`; since 2026-09-24 also the G3 generation anchor (`GET /v1/servers?name=soleur-inngest`) on op=resume / op=arm / op=luks-*, which reads `HCLOUD_TOKEN_READONLY` first and falls back to `HCLOUD_TOKEN` until step O5 | **read** on the Hetzner side for the anchor (op=backup's `create_image` is a write, tracked in #8767); no Terraform | **A** for the Hetzner read → `HCLOUD_TOKEN_READONLY`; keeps its Tier-B environment gate |
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
`scheduled-terraform-drift::drift-check`.
Phase 4 binds each to a member of the Tier-B environment set; the census row is RED until it does.
*Updated 2026-09-30 (#9262):* `build-inngest-bootstrap-image::bump-cloud-init-pin` and
`mint-inngest-bootstrap-tag::mint` (#4326) left this list. Both declare `infra-privileged` and read
`DOPPLER_TOKEN_INFRA_PRIVILEGED`, so the census's G1b/G1c rows now cover them. *Dated note, 2026-10-03
(#9321):* they now read `DOPPLER_TOKEN_INFRA_APP`, which is also an `ENV_SECRETS` member, so G1b/G1c still
cover them; census row G7f pins their call shape.

`infra-privileged` exists: O0's push apply created it with its `main` policy, and it is referenced
by `apply-web-platform-infra.yml`, `apply-github-infra.yml`, `apply-sentry-infra.yml`,
`apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml` and, since #9262,
`build-inngest-bootstrap-image.yml` (job `bump-cloud-init-pin`) and `mint-inngest-bootstrap-tag.yml`
(job `mint`). All four Tier-B environments
(`infra-privileged`, `web-platform-infra-apply`, `inngest-cutover`, `workspaces-luks-cutover`) are
live; none carries `DOPPLER_TOKEN_INFRA_PRIVILEGED` until O3.
*Dated note, 2026-09-30 (#9262):* O3 done (measured 2026-09-30: the secret exists on
`infra-privileged`, and on the other three Tier-B environments, all set 2026-09-29).

## Operator Sequence (canonical copy — verbatim from the plan)

Reproduced verbatim from `knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md` §Operator Sequence. This runbook is the canonical copy; the plan section is its origin. There is no O9 — the numbering skips it. Rows and cells marked "added by #9262" or "changed by #9262" are not from that plan: their origin is `knowledge-base/project/plans/archive/20261004-100500-2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md` §Operator Sequence addition.

<!-- markdownlint-disable MD034 -->
**Conventions.**

- `R=jikig-ai/soleur`.
- No step prints a value. A value moves shell variable → stdin: `v="$(doppler secrets get K … --plain)"; printf '%s' "$v" | …; unset v`. Command substitution strips the trailing newline that `--plain` emits (measured: `doppler secrets get … --plain | od -c` ends in `\n`). A bare pipe would store that newline.
- Every token mint first lists and revokes a token of the same name (`doppler configs tokens -p … -c … --json | jq -r '.[] | select(.name=="<name>") | .slug'`), so reruns are idempotent. The slug of each **old** token to revoke later is recorded in the bootstrap ledger (names and slugs, never values).
- Steps marked **(irreversible)** must not be reordered.
- The runbook `infra-credential-tiers-8209.md` is the canonical copy. The PR body and the generated bootstrap script link to it.

| # | Step | Exact command(s) | Verify (read-only) | Rollback |
|---|---|---|---|---|
| O0 | Merge the PR. The push apply creates: the `infra-privileged` environment and its `main` policy; the `workspaces-luks-cutover` policy; the empty Doppler project; and the privileged state bucket. It also forgets the 2 `doppler_secret.github_app_*` mirrors and the write-token pair. | merge in GitHub | **Hard gate before O3/O7**, on all four Tier-B environments: `for e in infra-privileged web-platform-infra-apply inngest-cutover workspaces-luks-cutover; do gh api repos/$R/environments/$e --jq '"\(.name) custom=\(.deployment_branch_policy.custom_branch_policies)"'; gh api repos/$R/environments/$e/deployment-branch-policies --jq '[.branch_policies[].name]'; done`. Each must print `custom=true` and `["main"]`. This includes `web-platform-infra-apply`, whose TF state shows drift (M9). If the live value is not `["main"]`, stop. Also run `doppler projects get soleur-infra-privileged --json \| jq -r .name`. **Plus the U1 live-key gate, run immediately before the merge click and again the moment the push apply is green:** (a) `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain \| sha256sum` and the same for `GITHUB_APP_ID` — record both digests **before** the merge in the ledger, and both must be byte-identical afterwards (this is the `prd` runtime key, not the `prd_terraform` one; never compare across configs, they differ by M3); (b) the push apply's plan JSON contains **no** `delete` action for `doppler_secret.github_app_id` or `doppler_secret.github_app_private_key` — `jq -r '.resource_changes[]\|select(.address\|test("^doppler_secret\\.github_app_(id\|private_key)$"))\|"\(.address) \(.change.actions\|join(","))"'` must print `no-op` for both or print nothing at all, and **anything containing `delete` means stop and do not proceed to O1**; (c) **the web app can still mint an installation token**, proved through the App's own runtime path rather than by re-reading Doppler: fire `cron/github-app-drift-guard.manual-trigger` through `POST /api/internal/trigger-cron` (the `soleur:trigger-cron` skill; the event is allowlisted because every entry of `EXPECTED_CRON_FUNCTIONS` is). That handler mints an App JWT from the `prd` `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` via `createAppJwtOctokit()` and calls `GET /app` plus the installation-grant diff (`apps/web-platform/server/github/probe-octokit.ts`, `server/github/app-private-key.ts`). A clean run proves the runtime key is intact; a `401` on App-JWT discovery means the key is wrong or gone — **stop and restore before O1**. `cron/oauth-probe.manual-trigger` is the fallback probe, and it also exercises `GET /repos/{owner}/{repo}/installation`. **Dated note, 2026-09-30 (#8609):** limb (a) reads the runtime key from `-p soleur -c prd`. After §Runtime App key (#8609) R-step 6 the key is no longer there: read it from `-p soleur-github-app -c prd`, and treat a not-found from `soleur/prd` as the expected state, not as a changed hash | **Not a plain revert.** A revert deletes the resource blocks, and `prevent_destroy` with them, so the next apply would destroy the project (with O2's secrets), the environment (with O3's secret) and the bucket. Roll back with a follow-up PR that swaps each new resource for `removed { from = … lifecycle { destroy = false } }` and restores the forgotten ones with `import` blocks (both listed in the runbook) |
| O1 | Provide the Tier-B GitHub identity. **Recommended:** create the `soleur-infra` App from the committed manifest `apps/web-platform/infra/github-infra-app-manifest.json` and install it on `jikig-ai` (selected repos). **Allowed alternative** (decision-challenges DC-4): reuse the existing soleur-ai Terraform key under the `GITHUB_INFRA_APP_*` names. That option defers the 403 fix to R6 and keeps a customer-reaching key in Tier B. | manifest flow, with one browser consent (the runbook gives the form-post helper) | `gh api /orgs/jikig-ai/installations --jq '.installations[]\|select(.app_slug=="soleur-infra")\|.permissions'` | delete the App |
| O1b | Create the least-privilege `soleur-board` App from `apps/web-platform/infra/github-board-app-manifest.json` and install it on `jikig-ai`. Store `SOLEUR_BOARD_APP_ID` and `SOLEUR_BOARD_APP_PRIVATE_KEY` in `prd_terraform` by stdin from the downloaded PEM file, then `shred -u` the file | as O1 | the next `board-status-sync` run carries no `legacy` warning | delete the two names; board sync falls back to legacy until O10 |
| O2 | Populate `soleur-infra-privileged/prd` | `for k in DOPPLER_TOKEN_TF HCLOUD_TOKEN CF_API_TOKEN_R2; do v="$(doppler secrets get "$k" -p soleur -c prd_terraform --plain)"; printf '%s' "$v" \| doppler secrets set "$k" -p soleur-infra-privileged -c prd --silent; unset v; done`, then `GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_INSTALLATION_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY` from O1 by stdin | the names are listed; for each copied name, source and destination hash equal in-process (`[ "$(… \| sha256sum)" = "$(… \| sha256sum)" ] && echo equal`) | `doppler secrets delete … -p soleur-infra-privileged -c prd` |
| O3 | Mint the Tier-B read token and seed the four environments (after O0's hard gate and O2) | `T="$(doppler configs tokens create gha-infra-privileged -p soleur-infra-privileged -c prd --access read --plain)"; for e in infra-privileged web-platform-infra-apply inngest-cutover workspaces-luks-cutover; do printf '%s' "$T" \| gh secret set DOPPLER_TOKEN_INFRA_PRIVILEGED --env "$e" -R $R; done; unset T` | `gh api --paginate repos/$R/environments/$e/secrets --jq '[.secrets[].name]'` shows the name on all four | `gh secret delete … --env $e`; `doppler configs tokens revoke gha-infra-privileged -p soleur-infra-privileged -c prd` |
| O4 | Canary before any eviction. Dispatch from `main`: `scheduled-terraform-drift.yml`, and a **no-op apply** each of `apply-github-infra.yml` and `apply-web-platform-infra.yml` (the runbook names the no-op `apply_target`) | `gh workflow run … -R $R --ref main` | every run carries the `source=tier_b` annotation. Pass means plan exit `0` or `2` (the known drift is expected) **and** the no-op applies are green. The infra App's write scopes are exercised by the apply. `gh api repos/$R/rulesets` confirms the pin-bump identity is in any bypass list it needs | none needed |
| O4b | **U5, the incident-recovery rehearsal.** A no-op apply does not exercise the two paths that recover the product: `web_host_replace` (environment `web-platform-infra-apply`) and `git_data_host_replace` (which declares **no** environment today, so Phase 4 item 1 gives it `infra-privileged`). Both must be proved reachable **before** O10 removes the legacy fallback that is currently hiding any breakage. Dispatch each from `main` in **plan-only** mode: `gh workflow run apply-web-platform-infra.yml -R $R --ref main -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f reason=tier-b-credential-probe -f plan_only=true`, then the same with `apply_target=git-data-host-replace` and that target's own confirm token. `plan_only=true` (Phase 4 item 1b) makes both jobs run checkout → loader → `terraform plan` → the path's existing gate in **report** mode, then exit 0 **before** any apply, any `-replace`, any SSH and any host contact. It is a strict subset of the real path: nothing that a `terraform plan` does not already do | both runs green; each log carries `source=tier_b` and `plan_only=1`; the gate reports its verdict without aborting; `gh api repos/$R/actions/runs/<id>/jobs --jq '.jobs[].steps[]\|select(.name\|test("Apply"))'` returns **nothing**, proving no apply step ran. If `git_data_host_replace` reports `source=legacy`, its `environment:` is missing or unseeded — **fix before O10** | none; the probe applies nothing. If a run fails, do not proceed to O10: the recovery path is already broken and O10 makes it permanent |
| O4c | **(added by #9262; not in the 2026-09-22 plan.)** Widen the `soleur-infra` App to the committed manifest (adds `actions: write`, `pull_requests: write`) and accept the change on the jikig-ai installation; then prove the re-tiered consumers on Tier B. Preconditions: O1, O3. **Recommended before merging #9262** (merging first is safe — releases fail at the mint step with nothing published until this step is done). Probe precondition: the pin drift guard is green on `main` (AC6 of `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, which asserts the cloud-init pin equals the semver-max `vinngest-v*` tag merged into `main`), otherwise the probe opens a real (held) pin PR. A separate check, that no mint is pending: `git fetch --tags origin && bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` prints `result=noop` (otherwise an auto-mint's build and bump are due and would overlap the probe) | App settings → Permissions (Actions: Read and write; Pull requests: Read and write) → Save; org → Installed GitHub Apps → soleur-infra → accept (`automation-status: UNVERIFIED` — Playwright route in the #9262 plan's §Apply path, `knowledge-base/project/plans/archive/20261004-100500-2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md`). After #9262 merges: `gh workflow run build-inngest-bootstrap-image.yml -R jikig-ai/soleur --ref main -f ref=<current max vinngest tag> -f mirror_only=true`. **Writes it performs:** a digest-preserving crane re-copy of the existing GHCR manifest to zot (idempotent), a cosign signature on that digest, and a deployment record on `infra-privileged`; no PR (pin already at max; `--mirror-only` would hold one anyway) | `gh api /orgs/jikig-ai/installations --jq '.installations[]\|select(.app_slug=="soleur-infra")\|.permissions'` shows `actions:"write"` and `pull_requests:"write"`; `gh run view <id> -R jikig-ai/soleur --log \| grep 'app=soleur-infra installation=166065653'` finds the `app-token` notice in the `bump-cloud-init-pin` job, `gh run view <id> -R jikig-ai/soleur --json jobs --jq '.jobs[]\|select(.name=="bump-cloud-init-pin")\|.conclusion'` prints `success`, and the bump ends `result=noop`. If the build job goes red for a zot/tunnel reason the bump is skipped and the probe proved nothing — re-run after the registry is healthy. The mint job's admission: `gh run list -R jikig-ai/soleur --workflow mint-inngest-bootstrap-tag.yml --event push --branch main -L1 --json headSha,conclusion` shows #9262's merge SHA and `success`; its token path is proven end to end by the next real auto-mint's notice | Step rollback: revert the two permissions in App settings; the jobs then fail at the mint step with nothing published. Code rollback: `git revert` of #9262 works until O10. Between O10 and the earlier of #8609 R-step 6 and O13's App-key delete, it works only with O10's rollback (dropping the `prd_terraform` override), and the reverted jobs then mint with the soleur-ai RUNTIME key inherited from `prd`. After either, fix-forward only (restore the App permissions, or rotate the `soleur-infra` key in `soleur-infra-privileged/prd`). Before reverting, close and delete any open `soleur/inngest-pin-*` PR authored by `soleur-infra[bot]`; after reverting, also revert O4c's two permissions so the manifest and the live App match. If the App token path is dead, the pin fallback is a pin PR written by a human (a human author passes CLA) |
| O5 | Mint `HCLOUD_TOKEN_READONLY` (Hetzner **Read** permission; console-minted, no API) and store it in `prd_terraform` by stdin from a 0600 file, then `shred -u` the file | as described | `curl -s -X DELETE -H @"$HDR" "https://api.hetzner.cloud/v1/ssh_keys/$NOPE" \| jq -r .error.code` must print `token_readonly`, where `NOPE=999999999` is an id chosen NOT to exist and `$HDR` is a 0600 file holding the auth header so the token never reaches argv. **The id matters.** This probe proves a token cannot write by ASKING IT TO WRITE, and it runs precisely when you are not yet sure which token you pasted — so on the branch it exists to catch (you pasted the read/WRITE one) it must not succeed. Against a real id it would: this check previously named `ssh_keys/1`, and a wrong paste would have DELETED that key from production. Against a nonexistent id both branches are inert — read-only gets `403 token_readonly` (permission is evaluated before the lookup), read/write gets `404 not_found` and destroys nothing. Any code other than `token_readonly` — including `not_found` — is inconclusive: stop, you are holding a writable token. Then confirm the token still READS: a GET on `/v1/servers` returns `200` | delete the name |
| O5b | **R7, the state key.** Mint a bucket-scoped **read-only** R2 token for `soleur-terraform-state` (ADR-130: operator-minted). Move the current read/write pair into Tier B as `TF_STATE_AWS_ACCESS_KEY_ID`/`TF_STATE_AWS_SECRET_ACCESS_KEY` (O2 pattern). Then replace `prd_terraform` `AWS_*` with the read-only pair | as described | the O4 canary is green again, and its apply writes state. A PR plan is green. With the Tier-A pair, `PutObject` to a scratch key returns `403` and `GET` of `web-platform/terraform.tfstate` returns `200` | restore the read/write pair into `prd_terraform` `AWS_*` (the source is still in Tier B) |
| O6 | Move `DOPPLER_TOKEN_WRITE` to Tier B | `v="$(doppler configs tokens create gha-prd-terraform-write -p soleur -c prd_terraform --access read/write --plain)"; printf '%s' "$v" \| gh secret set DOPPLER_TOKEN_WRITE --env infra-privileged -R $R; unset v` | environment secret listed; the next push apply's `Verify DOPPLER_TOKEN_WRITE present` step passes | `gh secret delete DOPPLER_TOKEN_WRITE --env infra-privileged -R $R` |
| O7 | Move `DOPPLER_TOKEN_GIT_DATA_ROOT` to its environment | `v="$(doppler configs tokens create gha-git-data-root-read -p soleur-git-data-root -c prd --access read --plain)"; printf '%s' "$v" \| gh secret set DOPPLER_TOKEN_GIT_DATA_ROOT --env web-platform-infra-apply -R $R; unset v` | a `git-data-cutover.yml` dry run from `main` reads `role=git-data-auth` as before | `gh secret delete DOPPLER_TOKEN_GIT_DATA_ROOT --env web-platform-infra-apply -R $R` |
| O8 | Migrate the git-data root-key state, and in the same dispatch apply the 2 custody forgets. Mint a bucket-scoped R2 token for `soleur-terraform-state-privileged`. Disable `apply-git-data-root-key.yml` behind a `trap` that re-enables it on any exit. Copy the object server-side (the runbook's `--aws-sigv4` `x-amz-copy-source` helper, which prints no key). **Then** set `GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID`/`…_SECRET_ACCESS_KEY` together; the loader treats the pair as all-or-none and refuses a half-set pair. Then set the repo variable `GIT_DATA_ROOT_STATE_MIGRATED=1` (`gh variable set`), after which the loader refuses the legacy bucket. Re-enable the workflow and dispatch it from `main` | runbook §State migration | Compared in-process, printing only `equal`: `sha256`, `lineage` and `serial` of source and destination. With the Tier-A pair, `GET` on the new object → `403`. The dispatch plans **exactly 2 forgets** (`github_actions_secret.doppler_token_git_data_root`, `doppler_service_token.git_data_root_read`) under arm `8209_custody_forget`, applies them and reads `git_data_root_state=privileged` | before the dispatch: unset the pair and the variable, and the legacy bucket works. After the dispatch the old object is stale: the rollback only goes forward (fix the new bucket's credentials). A forget changes only state, so no import is needed |
| O10 | Evict from Tier A **(irreversible)**. Preconditions: O1b, O3, O4, O5, O5b and O8 all done; **added by #9262:** #9262 merged and O4c done | `for k in DOPPLER_TOKEN_TF HCLOUD_TOKEN CF_API_TOKEN_R2; do doppler secrets delete "$k" -p soleur -c prd_terraform --yes; done`; `printf '%s' EVICTED_SEE_ADR_241 \| doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --silent` | the three names are absent; `[ "$(printf '%s' "$(doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --plain)" \| sha256sum)" = "$(printf '%s' EVICTED_SEE_ADR_241 \| sha256sum)" ] && echo equal`; a PR touching `apps/web-platform/infra/` is green; push apply, drift and board sync are green; **changed by #9262** (this limb read "and the pin bump are green", which tests nothing unless a build happens to run): re-run O4c's `mirror_only` probe after the sentinel is set — its `bump-cloud-init-pin` job is green with the `app-token` notice (`app=soleur-infra installation=166065653`) | re-set the three from Tier B (O2 pattern); `doppler secrets delete GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform` drops the override |
| O11 | Delete the old repo secrets and revoke the old tokens **(irreversible)**. Preconditions: O6, O7 and O8 | **First resolve each slug back to its name (U4).** A slug is opaque and the ledger is the only thing that binds it to a token; a wrong slug on the `soleur-git-data-root` line revokes the token the **running** git-data host uses to reach its root key. For each project/config pair, print the full name↔slug table and require an exact name match before revoking: `doppler configs tokens -p soleur-git-data-root -c prd --json \| jq -r '.[]\|"\(.name)\t\(.slug)"'` — the slug to revoke **must** be the row whose `name` the ledger recorded (the old `gha-git-data-root-read`, **not** the O7 mint of the same name, which is why O7's mint is listed first in the ledger with its creation timestamp, and not the git-data **host** boot token). Abort if the table shows two rows with the ledger's name, or none. Repeat for `-p soleur -c prd_terraform`. Then: `gh secret delete DOPPLER_TOKEN_GIT_DATA_ROOT -R $R`; `gh secret delete DOPPLER_TOKEN_WRITE -R $R`; `doppler configs tokens revoke <confirmed slug> -p soleur-git-data-root -c prd`; `doppler configs tokens revoke <confirmed slug> -p soleur -c prd_terraform` | `gh api --paginate repos/$R/actions/secrets --jq '[.secrets[].name]'` lacks both; the cutover dry run and the push apply are still green. **Plus the git store's own health (U4), which the CI dry run does not test** — the dry run carries its own credential and proves nothing about the running store. Read it from the observability layer and from the store's own endpoint, with no operator shell on the host: (a) the git-data heartbeat and its dedicated Better Stack log source (#7772) are still reporting, queried read-only with the established idiom `doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://uptime.betterstack.com/api/v2/heartbeats'`; (b) `gh workflow run scheduled-terraform-drift.yml -R $R --ref main` — its `heartbeat-live-reconcile` job reads Better Stack's live heartbeats and is the existing instrument for a host going dark; (c) a `git ls-remote` against one repository through the store's normal endpoint returns refs. Run all three within minutes of the revoke, while a rollback is still cheap | mint again and re-set (this re-opens the reach; last resort). If the **host's** token was revoked by mistake, mint a replacement of the same name into the same project/config and redeliver it to the host before its next restart — the host keeps running on its cached environment until then, and that window is the whole rollback budget |
| O12 | Delete the git-data root-key object from `soleur-terraform-state` **(irreversible)** | runbook §State migration, delete step | a Tier-A listing no longer shows the key | none |
| O12b | **U3, the host-read service tokens. A read-only gate on O13's `DOPPLER_TOKEN_TF` revocation — no action, and O13 does not start until it passes.** Terraform, running as `DOPPLER_TOKEN_TF` (a workplace **personal** token), created the Doppler service tokens the production hosts read their own configuration with: `doppler_service_token.git_data` (`git-data-luks-boot`, `git-data-luks.tf:161`), `doppler_service_token.ghcr_minter` (`ghcr-minter-write-*` on `soleur/prd`, `ghcr-minter-doppler-token.tf`, anchor `resource "doppler_service_token" "ghcr_minter"`) and `doppler_service_token.registry` (the zot boot token, `zot-registry.tf:299`). The question O13 must not assume the answer to: **does revoking the creating personal token invalidate the service tokens it created?** | (1) Enumerate the creator-bound set from state, not from memory: `terraform state list \| grep '^doppler_service_token\.'` in each root, and record every name in the ledger. (2) Settle the vendor behaviour **on the vendor side**, not by inference: Doppler's service-token documentation on token lifecycle and ownership, plus a written confirmation from Doppler support quoting the token names, filed in the runbook §Rotation as the citation for this step. A service token is a distinct object with its own slug and its own config scope, so the expected answer is that it survives; **an expected answer is not a confirmed one, and this step is what turns one into the other.** (3) A live negative control, which is decisive on its own: mint a throwaway `read` service token with a **second, disposable** personal token, revoke that personal token, then read a secret with the service token. A `200` proves no cascade; a `401` proves there is one and **O13's `DOPPLER_TOKEN_TF` revocation must not run** until every host token above has been re-minted by a surviving identity | n/a — nothing is changed |
| O13 | Rotate each public-branch-reachable credential (R5, **required**), **one at a time**: set the new value in Tier B → run the O4 canary → only then delete the old value. Order: Hetzner R/W; `CF_API_TOKEN_R2` (Cloudflare roll API, piped); `DOPPLER_TOKEN_TF` (new personal token, then revoke the old — **gated on O12b**); the R2 read/write state key; finally **delete the soleur-ai App key that `prd_terraform` held** (App settings → Private keys; no API exists) | runbook §Rotation. **Two additions.** (a) **After the `DOPPLER_TOKEN_TF` revocation (U3):** prove each host still reads its own config, because O12b establishes the expectation and this establishes the fact. Read it from CI and from the observability layer, never from an operator shell on the host: each host's Better Stack heartbeat and log source still report (the O11 read-only query), `scheduled-terraform-drift.yml`'s `heartbeat-live-reconcile` is green on a `main` dispatch, a `git ls-remote` against the store returns refs, and a `docker pull` of the current pin from ghcr succeeds. **Then force the case a cached environment hides:** the tokens under test are *boot* tokens, so a live host keeps working on the environment it already read. Dispatch `apply-web-platform-infra.yml` with `apply_target=entrypoint-audit` for the CI-side read, and schedule the real proof — the next host replace, dispatched from `main` through the workflow — as a deliberate, announced step rather than letting it arrive during an unrelated incident. O12b's negative control is what makes this a confirmation rather than the first time the question is asked. (b) **Before the App-key click (U2):** the two soleur-ai keys are distinguishable **only** by fingerprint, and the App settings UI lists fingerprints, so compare rather than guess. Compute the Terraform key's fingerprint from the value the operator captured to a 0600 file at the start of O13 — GitHub shows the SHA-256 of the DER public key, so `openssl rsa -in "$f" -pubout -outform DER \| openssl dgst -sha256 -binary \| base64` — and compute the **runtime** key's the same way from `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain`. The two **must** differ (M3 says they do; if they match, the two configs are not holding distinct keys and the whole delete is wrong — stop). Delete **only** the row whose fingerprint equals the `prd_terraform` one, and `shred -u` both files. (c) **After the `DOPPLER_TOKEN_TF` revocation:** list the Tier-B project's tokens — `doppler configs tokens -p soleur-infra-privileged -c prd --json \| jq -r '.[].name'` must print exactly `gha-infra-privileged`. `DOPPLER_TOKEN_TF` is a workplace personal token that can mint service tokens in this project, a branch-reachable copy of it existed from O0 to O10, and O12b expects a service token to survive the revocation of the token that minted it — so any other name is a token minted in that window: revoke it and open the breach-triage path. **Dated note, 2026-09-30 (#8609), on (b):** after §Runtime App key (#8609) R-step 6, compute the runtime key's fingerprint from `-p soleur-github-app -c prd`, not `-p soleur -c prd`; before R-step 6 both hold it. The row to delete is still the one equal to the `prd_terraform` fingerprint, which R-step 0 of that section also recorded | AC16's per-credential `401`/verify-failure probes. **Plus, immediately after the App-key delete (U2):** the runtime key must still work — a JWT signed with the **`prd`** key gets `200` from `GET /app` (`slug=soleur-ai`), a runtime **installation-token mint** succeeds on a `jikig-ai` installation, and the `cron/github-app-drift-guard.manual-trigger` probe from O0 runs clean. The old **Terraform** key's JWT must get `401` from the same `GET /app`, which is AC16's first limb; a `401` from *both* means the runtime key was deleted — **page immediately**, every connected user is disconnected | each old value stays valid until its own delete. The App-key delete has **no rollback**: GitHub cannot restore a deleted private key, only issue a new one. If the runtime key was the one deleted, recovery is: generate a new key in App settings, write it to `prd` (`GITHUB_APP_PRIVATE_KEY`, by stdin from the downloaded PEM), `shred -u` the file, restart the web app, and re-run the O0 mint check. **Dated note, 2026-09-30 (#8609):** after §Runtime App key (#8609) R-step 6, never write a key back to `prd` — it is branch-readable there, so the key would be burned. The recovery is R-step 7's short recovery in that section: store the new key in `soleur-github-app/prd` and ship a release |

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
- **O4c precedes O10** (added by #9262). Before O4c the `soleur-infra` App lacks `actions:write` and
  `pull_requests:write`, so the auto-mint and the pin bump fail at their mint step; O10's pin-bump
  verify limb re-runs O4c's probe, which can only pass once O4c is done. The chain is **#9262 merge
  → O4c → O10 → O13's `DOPPLER_TOKEN_TF` rotation → #8609 R-step 1** (§Runtime App key gates R-step 1
  on #8209 O10 done **and** O13's `DOPPLER_TOKEN_TF` rotation done). O4c's App widening may run
  before the merge; its probe dispatch runs after it.
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

**Dated note, 2026-09-30 (#9262), on O13.** O13's App-key delete concerns only the `soleur-ai` key
that `prd_terraform` held. #9262 does not change it: after #9262 no inngest-release job reads that
key, because both mint the `soleur-infra` App from `soleur-infra-privileged/prd`. #9262 mints no
Doppler token either: both jobs reuse `DOPPLER_TOKEN_INFRA_PRIVILEGED`, the O3 token
`gha-infra-privileged`. *(Dated 2026-10-03, #9321: superseded; once the switch change merges both jobs
hold only `DOPPLER_TOKEN_INFRA_APP`, the read token `release-app-mint` of `soleur-infra-app`, and no longer
the O3 token.)* **Reconciling O13(c) with #8609 (#9263).** §Runtime App key R-step 2 stores
`GITHUB_APP_RUNTIME_DOPPLER_TOKEN` in `soleur-infra-privileged/prd`. That value is a **secret**
holding a service token of the `soleur-github-app` project (`web-host-github-app-read`, which R-step
8 lists under `-p soleur-github-app -c prd`). It is not a service token of `soleur-infra-privileged`,
so O13(c)'s listing (`doppler configs tokens -p soleur-infra-privileged -c prd`) must still print
exactly `gha-infra-privileged`. Any change that mints a second token **in** `soleur-infra-privileged`
must update O13(c)'s expected set in the same change. Separately,
since #9263 every holder of `DOPPLER_TOKEN_INFRA_PRIVILEGED` can read `GITHUB_APP_RUNTIME_DOPPLER_TOKEN`,
and that now includes the two unattended jobs #9262 re-tiered (ADR-241 Amendment log, #9262). *(Dated
2026-10-03, #9321: after the switch change merges those two jobs no longer hold that token; only the
other Tier-B jobs, including `apply-github-infra.yml::apply`, do.)*

**Dated note, 2026-10-01 (#9360), on O4 and O13.** After O10, `apply-github-infra.yml` failed at its
`prd_terraform` App-key fetch (`verdict=legacy_app_key_evicted`, run 36839787788), so O4's
`apply-github-infra` no-op has been red since O10, and every O13 sub-step re-runs the O4 canary. The
chain is therefore **O10 → #9360 merged and its proof run green → O13**. #9360 moves the job to the
soleur-infra App (ADR-241 Amendment log, 2026-10-01). O4's bypass-list limb stays **open for the
marketplace ruleset** until #9361 lands: its App bypass actor is still soleur-ai, so a manifest write
made as soleur-infra is refused with a 409. That is the known gap, not a fault of the canary.

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
`doppler_service_token.ghcr_minter` (`ghcr-minter-write-*` on `soleur/prd`,
`ghcr-minter-doppler-token.tf`; destroyed by #8714 task 5.4, so it drops out of this check) and `doppler_service_token.registry` (the zot boot token,
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

## Runtime App key (#8609)

**This section is the CANONICAL copy of the #8609 operator sequence (R-steps 0–9, ADR-241 D10).** It was moved verbatim from `knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md` §Operator Sequence, which now points here, and revised in place by the PR-A review (2026-09-30; this section is new in that PR). The generated bootstrap script, `knowledge-base/project/specs/feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`, stages every row with a per-command go-ahead and runs each row's verification; it links here and does not restate the reasoning.

**Labels.** The rows below are **R-steps** ("R-step 7" is the GitHub delete). ADR-241's **residuals** R1–R8 are a different namespace ("residual R7" is the state key closed at #8209 O5b). Always write the qualifier.

Every step that writes to production or dispatches a production workflow is shown as the exact
command and runs only after its own go-ahead (`hr-menu-option-ack-not-prod-write-auth`). No secret
value is printed; every `doppler secrets set`/`delete` ends `>/dev/null` and is verified by a
separate read that prints a hash comparison or a count. A read that fails, or returns a shape the
check does not know, is **UNREADABLE / INCONCLUSIVE — never a pass**.

**Gate before R-step 1:** #8209 O10 is done (`DOPPLER_TOKEN_TF` gone from `prd_terraform`) **and** O13's
`DOPPLER_TOKEN_TF` rotation is done (the old personal token revoked). Before that, the new key would
be branch-reachable at birth through `DOPPLER_TOKEN_TF` (architecture review P0). PR-A may merge and
R-step 0 may run before the gate.

**The reads every row uses** (no SSH, no dashboard):

- **web-1 deploy state:** `doppler run -p soleur -c prd_terraform -- bash apps/web-platform/scripts/github-app-key-status.sh`. It prints `github_app_key_source=`, `_fetch=`, `_probe=` plus `tag=`, `exit_code=`, `reason=` and `component=`. "`isolated`/`ok`/`ok`" means all three **and** `exit_code=0`, `component=web-platform` and `tag=v<the version https://app.soleur.ai/health reports>`, so a verdict left by an older or failed deploy cannot pass. Exit 3 (credentials not injected) and exit 6 (the read failed) are UNREADABLE, never a verdict.
- **web-2 boot verdict (Sentry):** the host is named `soleur-web-2` (`server.tf` names hosts `soleur-${each.key}`; the bare `web-2` matches nothing). For each stage `github_app_key_{ok,ok_fallback,rejected,missing,transport,probe_absent,exec_failed}` run `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-web-2 --stage <stage> --start <YYYY-MM-DDTHH:MM:SS> --end <YYYY-MM-DDTHH:MM:SS>` and take the **newest** event across all seven. **The R-step 5 discriminator:** only `github_app_key_ok` means the isolated key was fetched and accepted. `github_app_key_ok_fallback` means the container runs on the `prd` fallback key (the isolated fetch failed, was withheld or found no token), and it is a **fail**. Exit 77/78 from `sentry-issue.sh` is a token-scope problem: UNREADABLE, not "no event".
- **web-2 boot verdict (Better Stack fallback):** when Sentry has no event or is unreadable, `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep GITHUB_APP_KEY_BOOT` and keep the rows with `host_name=soleur-web-2`. The journald line carries the overlay's `source=`/`fetch=` detail; `source=isolated fetch=ok` is the same discriminator. The line is written whatever the Sentry DSN, so its absence means the check never ran.

<!-- lint-infra-ignore start: GitHub exposes no API to list, generate or delete an App private key; these rows name the one gated page action each and automate everything around it -->
| R-step | What | Mechanism | Verification (pass condition) | Rollback |
|---|---|---|---|---|
| R0 | **Key inventory (K0) and park the old key.** Read every private-key row on the App settings page (fingerprint, added date) and record R-step 0's installation-id set from `GET /app/installations`. Pipe `soleur/prd` `GITHUB_APP_PRIVATE_KEY` straight into `doppler secrets set GITHUB_APP_PRIVATE_KEY_RETIRED -p soleur-github-app -c prd_retired --silent >/dev/null` (no file on disk; the host's `prd`-scoped token cannot read `prd_retired`). Compute the DER-SHA-256 fingerprints of the `prd` and `prd_terraform` values in memory. This one-time move parks from `soleur/prd`; every later rotation parks from `soleur-github-app/prd` (§Routine rotation) | Playwright read of the App page; Doppler CLI; `openssl pkey -pubout -outform DER \| openssl dgst -sha256 -binary \| base64` | Every row maps to a holder. **Stop** if the `prd` and `prd_terraform` fingerprints are equal, or a row is unmapped (breach triage); treat a value that does not parse as a key as NOT a key (openssl on it yields `47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`, the SHA-256 of empty input, which reads as a distinct fingerprint; a sentinel in `prd_terraform` is expected after #8209 O13) | delete the parked name |
| R0b | **Evidence limbs K1–K3 (CLO, read-only).** Non-`main` run census naming a `prd`-reading token (ids/counts only), Doppler access-log retention and entries for `soleur/prd*`, org audit log for `soleur-ai[bot]` admin actions | `gh api` + Doppler CLI activity logs | Recorded in the new assessment; `API-UNAVAILABLE` is INCONCLUSIVE, not clean | n/a |
| R1 | **New key into the isolated project** (after the gate). **Already done?** Only a `200` from `GET /app` (right slug and id) with the key already in `soleur-github-app/prd` means done; a `401` means generate again; **any other answer (timeout, 5xx, another App) stops the step** — it is not "not done", and generating again would add a live row. Generate a key on the App page (the gated click; Playwright's download directory on `$XDG_RUNTIME_DIR` tmpfs under `umask 077`), then `doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur-github-app -c prd --silent < "$PEM" >/dev/null`. **The PEM is deleted only after** the read-back fingerprint equals the file's **and** `GET /app` accepts the stored value; on any failure the file stays on tmpfs at mode 0600 (GitHub never shows a private key twice) and the step prints how to resume or abandon. Then clear the browser's download history (`shred` is not relied on — it is not reliable on copy-on-write filesystems or SSDs). Before the store, the raw values of **every** `soleur` config hold no `${soleur-github-app.` reference (count only) — this count, repeated at R-step 6, replaces the dropped R0c scratch-project probe: it runs whether or not Doppler resolves cross-project references | Playwright to the click; Doppler CLI | The fingerprint of the value read back from Doppler equals the downloaded key's and the new row's on the App page; a JWT signed with it gets `200` from `GET /app` with `slug=soleur-ai` and `id=3261325`; the cross-project reference count is `0` | delete the new row + the secret |
| R2 | **Read token into Tier B.** Under `set -o pipefail`: `doppler configs tokens create web-host-github-app-read -p soleur-github-app -c prd --access read --plain \| tr -d '\n' \| doppler secrets set GITHUB_APP_RUNTIME_DOPPLER_TOKEN -p soleur-infra-privileged -c prd --silent >/dev/null`; if the set fails, revoke the just-minted token | Doppler CLI, piped | With the stored value passed through the environment (never `--token`, never shell history): the key it reads has the live key's fingerprint (prints `equal`), and a read of `soleur/prd` with it is refused | revoke the token; delete the Tier-B name |
| R3 | **Deliver to web-1.** A one-line PR bumping `"github_app_runtime_token_generation=N"` in `apps/web-platform/infra/server.tf` (the bootstrap script opens it). A bare `gh workflow run apply-deploy-pipeline-fix.yml` replaces nothing: the `deploy_pipeline_fix` trigger hashes the KEYLESS render plus that generation literal, so every plan context computes the same trigger. Merging fires the opted-in apply | Tier-B job, `environment: infra-privileged`, triggered by the merge (`server.tf` is in its paths filter) | The first run after the merge concludes `success` (not `cancelled` — the shared `terraform-apply-web-platform-host` concurrency group keeps only the newest pending run); its log shows the loader at `source=tier_b`; web-1's infra-config state shows `/etc/default/soleur-doppler-token` with a **changed** digest | set the Tier-B name empty and bump the generation again in a new PR: the file re-renders without the line (SSH-free) |
| R4 | **Ship on the new key.** `gh workflow run web-platform-release.yml --ref main -f bump_type=patch` | release → `ci-deploy.sh` | The web-1 deploy-state read above is `isolated`/`ok`/`ok` for the serving release; `GET /app/installations` with the new key returns a **superset** of R-step 0's installation ids; one installation-token mint on `jikig-ai` returns `201`; `cron/github-app-drift-guard.manual-trigger` and `cron/oauth-probe.manual-trigger` (via `soleur:trigger-cron`) are accepted **and**, five minutes later, Sentry holds **zero** events for `feature:cron-github-app-drift-guard level:[error,fatal]` and for `feature:cron-oauth-probe level:[error,fatal]` over [trigger − 1 min, now] (org discover endpoint, `SENTRY_ISSUE_RO_TOKEN` from `soleur/prd`). Zero errors does not prove the run happened; the drift guard's cron monitor pages on a missed check-in | R-step 3 rollback + release (falls back to the still-valid `prd` key); list failed webhook deliveries for the window (`GET /app/hook/deliveries`) and redeliver them (`POST /app/hook/deliveries/{id}/attempts`) |
| R5 | **Replace standby web-2 from `main`.** Preconditions: web-1 healthy and serving `isolated`/`ok`/`ok`, web-2 not in the traffic path; the image the replace pins (by default web-1's running tag, read from `/health` — input `image_tag`) is R-step 4's release or later, R-step 4's release fanned out to web-2 **before** the replace (its `ci-deploy` wrote the pinned-identity verified-digest record to web-2's `/mnt/data/github-app-key-verified-ref`; `hcloud_volume.workspaces` survives the replace, so the reborn host boots with `vref=match` — without it the boot reports `github_app_key_ok_fallback` with `vref=absent` and the key arrives only at the next fan-out deploy), **and** its baked host-scripts hash equals `local.host_scripts_content_hash` on `main`; cpx22 in stock in hel1. `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f reason=8609-github-app-token` | Tier-B job, reviewer-gated `web-platform-infra-apply` | The web-2 boot read above, from the dispatch time: the **newest** `github_app_key_*` event for `soleur-web-2` is `github_app_key_ok`. `github_app_key_ok_fallback` fails (the prd fallback key); no event fails (read Better Stack to tell "never ran" from "POST failed"); UNREADABLE fails. Private NIC reachable per the immutable-redeploy learning | web-2 is cattle; re-replace |
| R5b | **Re-pin web-2's SSH host key** (deployment review). A replaced web-2 presents a new host key, and `deploy_pipeline_fix_web2` trusts only the committed pin, so every later `apply-deploy-pipeline-fix` run — web-1's leg included — fails closed until it is re-captured. Run `scripts/capture-web-2-host-key.sh <web-2-ipv4>` (the IPv4 from the Hetzner read of `servers?name=soleur-web-2`; egress in `var.admin_ips`; if not, the operator types `/soleur:admin-ip-refresh` first), commit the pin file in a PR, merge | `scripts/capture-web-2-host-key.sh` + PR | The next `apply-deploy-pipeline-fix` run's web-2 leg is green. **R-step 5b precedes R-step 6** | re-capture |
| R6 | **Evict from `prd`.** Preconditions: AC-R6a and AC-R6b hold; the web-1 deploy-state read **immediately before** is `isolated`/`ok`/`ok` for the serving release (an operator-local or legacy-arm apply between R-steps 3 and 6 would silently strip the line); web-2's newest boot event since R-step 5 is `github_app_key_ok`. Then `doppler secrets delete GITHUB_APP_PRIVATE_KEY -p soleur -c prd --yes >/dev/null`. **Accepted consequences, recorded here:** (1) after this step, rolling back to an older image signed only from a tag (not from a `refs/heads/main` run) gets **no** key: the canary refuses promotion (`canary_github_app_key_missing`) and the running container keeps serving — fail-safe, no outage; roll forward instead. (2) A cosign verification outage (for example a rate-limited pull of the verifier image, `cosign_absent`) now withholds the key, so releases are refused until verification works again; the running release keeps serving. Retry the release; do not restore a key to `prd` | Doppler CLI | Every `prd`/`prd_*` config in `apps/web-platform/infra/doppler-config-inventory.txt` returns not-found, except `prd_terraform` (its own sentinel/override, #8209); raw values in **every** `soleur` config hold no `${soleur-github-app.` reference (count only); Doppler webhooks and syncs on `soleur/prd` listed (`GET /v3/webhooks?project=soleur`, `GET /v3/integrations`); a fresh release is `isolated`/`ok`/`ok` and the R-step 4 probes pass | restore a key to `prd` from the isolated project — this **burns** the new key (branch-readable again): restart at R-step 1 with a fresh key; PR-B may not cite a burned key |
| R7 | **Kill the old key at GitHub.** Preconditions: a release **other than R-step 4's** has shipped on `isolated`; web-1 (deploy state) and web-2 (newest boot event) both report the isolated key after R-step 6; the row's fingerprint equals R-step 0's `prd` fingerprint, **differs** from R-step 1's, and **differs** from R-step 0's `prd_terraform` fingerprint. Delete that row (the gated click) | Playwright to the click | A JWT from the new key → `200` (`slug=soleur-ai`); a JWT from `GITHUB_APP_PRIVATE_KEY_RETIRED` (read from `prd_retired`) → `401`; then delete the parked name; the R-step 4 cron probes clean. **1-hour watch:** Sentry holds **zero** events for `feature:github-app op:generate-installation-token` over [the delete, +1 h]. Every agent git push / PR step mints its token through that function, so the one query covers both | **none** — a wrong delete disconnects every user. Short recovery: generate a key → `doppler secrets set` into the isolated project → release (R-step 3 is not needed; the token is unchanged) → redeliver failed webhook deliveries for the window |
| R8 | **Gate G4** (after #8209 O13's App-key delete, and after R-step 7's 1-hour watch) | Playwright read; Doppler CLI/API; Sentry | R-step 7's mint-failure query returns `0`; the App lists exactly one key, the live one (R-step 1's, or R-step 9's once it ran); `doppler configs tokens -p soleur-github-app -c prd --json \| jq -r '.[].name'` prints exactly `web-host-github-app-read`; `prd_retired` has no token; the project's members hold no service account or group; `GET /v3/webhooks?project=soleur-github-app` lists none and no sync in `GET /v3/integrations` reads `soleur-github-app`. An unreadable Doppler API answer is INCONCLUSIVE, not a pass | n/a |
| R9 | **Closure rotation (gate G3; conditional).** Runs only once G1 and G2 have both closed, and only if the live key was born **before** the later of the two closures (a key that existed while a branch-reachable path to it was open is treated as taken). If R-step 1 ran after both closed, R-step 1 was the closure rotation and R-step 9 records "skipped". Otherwise: park the live key from **`soleur-github-app/prd`** into `prd_retired`; generate one more key and store it as R-step 1 does (PEM deleted only after the read-back and `GET /app` pass); mint a second `web-host-github-app-read` token and store it in Tier B (new before old — the old token could read the new key); R-step 3's push; R-step 4's release; R-step 5's web-2 replace and R-step 5b's re-pin; delete the previous row at GitHub (the gated click); revoke the old token's slug after matching it in the name↔slug table; delete the parked name | Doppler CLI; Playwright to the click; the R-step 3–5b dispatches | A JWT from the new key → `200`; from the parked previous key → `401`; the old token slug is gone and the Tier-B token reads the new key; the key's birth time is later than both closures; after the 1-hour watch, R-step 8's checks pass against the new key | before the delete: restore the parked key to `soleur-github-app/prd` and ship a release. After it: **none**, as R-step 7 |
<!-- lint-infra-ignore end -->

Order: R-step 0 before R-steps 1 and 7 (a delete destroys the "added" date); R-step 0b's K1 before the 90-day Actions
retention; the gate before R-step 1; R-steps 1 → 2 → 3 → 4 → 5 → 5b → 6 → 7 strictly; R-step 8 after R-step 7's 1-hour watch; R-step 9 once G1 and G2 have closed.
Installation tokens minted before R-step 7 are expected to stay valid until their ~1 h expiry; R-step 7's 1-hour
mint-failure query is what confirms it rather than assumes it. **Do not delay R-steps 1–7 for G1/G2:** the old key is
directly readable from `prd` today, R-steps 6 and 7 only remove paths, and the cost of not waiting is at most R-step 9.

### Closure gates G1–G4 (before PR-B)

ADR-241 residual R1 stays **OPEN** — mechanism merged (D10) — until all four hold. PR-B (D2 and D10 → `accepted`,
`Closes #8609`) is **not opened** until G1–G3 are evidenced with links in its body: the two issue closures, and
the live key's birth time compared against their closure times.

| Gate | Holds when | Evidence |
|---|---|---|
| G1 | #9294 is closed: the deploy channel (`WEBHOOK_DEPLOY_SECRET` and the CF Access client pair in `soleur/prd_terraform`) is out of branch reach (Tier B) and rotated. Until then `/hooks/infra-config` can replace `ci-deploy.sh`, the enforcer of D10's gate | `gh issue view 9294 --json state,closedAt` |
| G2 | #9295 is closed: no branch-nameable token can write `soleur/prd`. Until then a Tier-A writer can inject unenumerated names or change the values of allowed ones; the env-class refusal is defence in depth | `gh issue view 9295 --json state,closedAt` |
| G3 | The live key was born after both closures, or R-step 9 has rotated it (and the read token) and the previous key gets `401` | R-step 9's output: birth time vs `closedAt` |
| G4 | R-step 8 passes: old key `401`, one App key, one project token after #8209 O13, no attachments | R-step 8's output |

### Routine rotation (steady state)

After the one-time move, rotating the key is R-step 9's sub-sequence without its G3 condition: park the **current** key from `soleur-github-app/prd` (not `soleur/prd`, which is empty once R-step 6 has run — R-step 0 as written refuses there), generate the new key into `soleur-github-app/prd`, mint the new read token, push it (R-step 3), ship a release so the canary proves the key (`isolated`/`ok`/`ok`), replace web-2 from `main` (R-step 5, then R-step 5b's host-key re-pin), then delete the old row at GitHub with the `401` proof, revoke the old token and delete the parked name. R-steps 2 and 6 are one-time as written: the key never returns to `prd`, and R-step 1's birth gate stays met once #8209 O13 has run.

**The read token rotates with every key rotation**, never on its own schedule, so one release and one web-2 replace cover both. Mint new before revoking old (learning `security-issues/2026-09-25-doppler-token-rotation-with-a-secret-consumer-and-revoke-first-removes-the-blanket-ack.md`): record the current `web-host-github-app-read` slug (names and slugs only), mint a second token of the same name through R-step 2's pipe, deliver it with R-step 3's dispatch, and ship the release and the web-2 replace. Only then revoke the recorded slug, after confirming it against the name↔slug table as O11 does. Revoking earlier strands web-2, whose credentials change only at a replace. R-step 8's token listing (exactly one `web-host-github-app-read`) is the check that the old one is gone.

## Release-job App source (#9321)

**This section is the canonical order for giving the two App-token release jobs
(`build-inngest-bootstrap-image.yml::bump-cloud-init-pin`, `mint-inngest-bootstrap-tag.yml::mint`) a
credential that reads only `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY`.** The decision, its
measured reach, its cost and its boundary are ADR-241 D11; this section holds the sequence only.

The work is two changes, because one cannot land safely: the credential can be minted only after
Terraform has created its container, and the release jobs run `main`'s YAML the moment the switch
merges.

| # | Step | Done by | The release jobs meanwhile |
|---|---|---|---|
| 1 | Merge the first change (container, script, census, ADR text). Merging it runs the push apply, which creates two **empty** Doppler containers, and (the file is under `apps/web-platform/`) also starts `web-platform-release.yml` and `infra-validation.yml`. A `[skip-web-platform-apply]` line in the squash message suppresses the apply only, not the release | the operator's merge decision | unchanged, on the broad token |
| 2 | The push apply creates `soleur-infra-app` and its `prd` environment | CI | unchanged |
| 3 | The agent runs `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` one stage at a time with `bash <script> --stage <name>`, in this order: `preflight`; `copy-app-values` (its plan first, then `--apply --plan-digest <d>`); `prove-live-app`; `mint-and-store-token` (its plan first, then `--apply --plan-digest <d>`); `verify`. Together they check the sources, copy the two values, prove the copy is the live App, mint the read token and store it as the `infra-privileged` **environment** secret `DOPPLER_TOKEN_INFRA_APP`, and finish with a read-only verification. The two read stages and the two plans need no approval. Each of the two writes (`copy-app-values --apply`, `mint-and-store-token --apply`) is approved by the person at the Claude Code approval prompt, on the exact command shown there; no terminal is needed. Re-running is safe | the agent runs it; the operator approves each write at the approval prompt | unchanged |
| 4 | Open and merge the second change (the composite's validated `doppler-project` input with its narrow default; both release workflows passing `secrets.DOPPLER_TOKEN_INFRA_APP`; `apply-github-infra.yml` naming `doppler-project: soleur-infra-privileged` explicitly; the three fixture suites; census row G7f; `Closes #9321`) only after step 3 printed `SOLEUR_BOOTSTRAP_READY_FOR_PR2`. Before merging, re-run the two read-only checks under "Verification reads" below (the environment-secret listing prints `DOPPLER_TOKEN_INFRA_APP`; the token-name listing prints `release-app-mint`) and the `verify` stage (`bash knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh --stage verify`: rc 0 and a line starting `SOLEUR_BOOTSTRAP_READY_FOR_PR2`) | the operator's merge decision | switched to the narrow token |
| 5 | Prove the switch with the dispatch block below, run after step 4 merges. The evidence is on the run, not in its green colour alone | the agent runs it and watches the run; the operator approves the dispatch (a GitHub write) at the Claude Code approval prompt on the exact command | on the narrow token |

**Proof dispatch and evidence (step 5).** Dispatch the build workflow from `main` in `mirror_only` mode,
the command of step O4c, and check the run it produced. One block, in order; each check prints what its
comment says, and any other output means the proof has not passed:

```bash
R=jikig-ai/soleur; WF=build-inngest-bootstrap-image.yml
MERGE_SHA="$(gh pr view 9453 -R "$R" --json state,mergeCommit --jq 'select(.state=="MERGED")|.mergeCommit.oid')"   # a 40-hex sha: this PR's merge commit on main (the PR itself, never a search)
[[ "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "PR 9453 is not merged: stop"; exit 1; }   # no output
git fetch origin main >/dev/null 2>&1
git show --name-only --format= "$MERGE_SHA" | grep -qx .github/actions/mint-infra-app-token/action.yml || { echo "that commit is not the second change: stop"; exit 1; }   # no output
TAG="$(git fetch --tags origin >/dev/null 2>&1; git tag --list 'vinngest-v*' --sort=-v:refname | head -1)"   # the current max tag
PREV="$(gh run list -R "$R" --workflow "$WF" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
gh workflow run "$WF" -R "$R" --ref main -f ref="$TAG" -f mirror_only=true                  # the write the person approves
ID=""; for _ in $(seq 1 30); do   # bounded: up to 5 minutes for the new run to be listed
  ID="$(gh run list -R "$R" --workflow "$WF" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
  [ -n "$ID" ] && [ "$ID" != "$PREV" ] && break; ID=""; sleep 10; done
[ -n "$ID" ] || { echo "no new run was listed in 5 minutes: stop"; exit 1; }                # expected: no output
gh run watch "$ID" -R "$R" --exit-status; echo "run rc=$?"                                  # run rc=0
git fetch origin main >/dev/null 2>&1
git merge-base --is-ancestor "$MERGE_SHA" "$(gh run view "$ID" -R "$R" --json headSha --jq .headSha)"; echo "ancestor rc=$?"   # ancestor rc=0
gh run view "$ID" -R "$R" --json jobs --jq '.jobs[]|select(.name=="bump-cloud-init-pin")|.steps[]|select(.name=="Verify DOPPLER_TOKEN_INFRA_APP present")|.conclusion'   # success
gh run view "$ID" -R "$R" --log | grep -F '##[notice]app=soleur-infra' | grep -o 'source=[^ ]*' | sort -u   # exactly one line: source=soleur-infra-app/prd
```

Side effects, so nobody is surprised: the `bump-cloud-init-pin` job mints a **real** installation token of the
`soleur-infra` App with `contents:write` and `pull_requests:write` on `soleur`, from the narrow source. The bump
targets the semver-max tag whatever tag was dispatched, so with the pin already at the max (the drift guard
green is the precondition, as in O4c) it ends `result=noop`: no push and no pull request. A `mirror_only`
run never arms auto-merge. The build job's own effects are O4c's (a digest-preserving mirror copy and a
cosign signature). The four outputs are the evidence: the run is green, its `headSha` descends from the
second change's merge (a stale pre-merge run cannot pass), the credential check passed, and the `app-token`
notice names the narrow project and never `source=soleur-infra-privileged/prd`. The `source=` grep is anchored on
`##[notice]app=soleur-infra`, the runner's rendering of the annotation: GitHub also echoes the composite's script
text into the log, and that echo (`source=${DOPPLER_SOURCE}/prd"`), like unrelated `source=` hits from other steps,
must not be counted. Read `source=` for what it
is: the project the run **requested**, derived from the validated input, not a value Doppler attested. The
proof that the narrow source is what served the credentials is the combination of the G7f pairing of the token
and the project (census), the `verify` stage (it lists the stored token's name and slug and compares the copies
with their sources; it never uses the token), and the successful mint with that token, which is what shows the
token is bound to `soleur-infra-app`. This run exercises the build job's caller only. The mint job's
credential steps run only when its `Decide` step returns `would-mint`, so its caller is proven by the next real
auto-mint's notice (the same `source=` field), and `apply-github-infra.yml::apply` keeps its token and now
also names `doppler-project: soleur-infra-privileged` explicitly. ADR-241 D11 flipped from `adopting` to
`accepted` on 2026-10-04 (#9462, run 37222544138) on the build-job proof plus the static suites.

**When a release run fails on the source, which stage fixes it.** The composite cannot tell these causes
apart (the Doppler CLI's stderr is suppressed so no value can leak; the two `not readable` lines carry only
the CLI's exit status, `doppler rc=<n>`) and does not guess; this table does. Read the failing line with
`gh run view <id> -R jikig-ai/soleur --log-failed | grep -F '##[error]mint-infra-app-token:'` (the runner
prefixes the real annotation with `##[error]`; the echoed script text has `::error::` and lists every alternative message, so it must not be matched). **First diagnostic for every
row: `bash knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh --stage verify`**
(read-only, needs no approval; its first red check names the cause). Only then pick a write stage.

| What the run shows | Cause | Remedy |
|---|---|---|
| `Verify DOPPLER_TOKEN_INFRA_APP present` fails (`DOPPLER_TOKEN_INFRA_APP is not available`) | the environment secret is missing or was deleted | agent re-runs `--stage mint-and-store-token` (plan, then `--apply --plan-digest <d>`; the person approves the write at the prompt) |
| the mint step reports `GITHUB_INFRA_APP_ID not readable from Doppler soleur-infra-app/prd` and `verify` shows the token missing or the slug mismatched | the stored read token is missing, revoked or out of step with the live one | `--stage mint-and-store-token` (add `--rotate-token` when a token exists but is rejected), then `--stage verify` |
| the same line, and `verify` shows the project or a value missing or unequal to its source | the project was emptied, or a value was lost | `--stage copy-app-values` (its plan, then `--apply --plan-digest <d>`), then `prove-live-app` |
| the same line, and `verify` is green | a transient Doppler outage (or a network failure on the runner) | re-run the failed job; nothing to change in Doppler. If the re-run fails the same way, the stored token is listed but rejected, which `verify` cannot see: run `--stage mint-and-store-token` with `--rotate-token` (plan, then `--apply --plan-digest <d> --rotate-token`; the person approves the write) |
| `... GITHUB_INFRA_APP_PRIVATE_KEY not readable ...` or `GitHub App credentials empty ...` | a value is missing from `soleur-infra-app/prd` | `--stage copy-app-values` (its plan, then `--apply --plan-digest <d>`), then `prove-live-app` |
| `... is not a valid RSA PEM` or `the installation-token exchange ... returned no token` | the copied key is stale or corrupted after an App key rotation | `--stage copy-app-values`, then `prove-live-app`; the rotation order below prevents it |
| `doppler-project must be exactly soleur-infra-app or soleur-infra-privileged` | a caller passed an unlisted source (a code regression, which census row G7f also reds) | fix the caller; nothing to re-run in Doppler |

After the remedy, re-run the failed job or re-dispatch.

If the second change merges before step 3, the failure is safe by construction: the
`Verify DOPPLER_TOKEN_INFRA_APP present` step fails before the App-token mint, and both jobs mint before
the tag and before the push, so no tag is created, nothing is pushed and no pull request is opened,
and the existing Slack failure post fires. It surfaces at the next carrier change or build dispatch, not at
merge, and the build job has by then already published its image, so the second change's description must
paste the `SOLEUR_BOOTSTRAP_READY_FOR_PR2` line the script printed. Running the script and re-running the job
recovers it.

**Do not run the #8609 R-step 2 (storing the runtime key's read token in the Tier-B project) before the second
change has merged.** Until then both release jobs still hold the broad token and would read it, which is the
reach this section removes. *(Dated 2026-10-03: this gate is satisfied once the second change merges; from then on
the two release jobs hold only the narrow token.)*

**Verification reads (names and counts only; no value is printed).**

```bash
doppler projects get soleur-infra-app --json >/dev/null && echo project-exists                          # project-exists
gh api --paginate repos/jikig-ai/soleur/environments/infra-privileged/secrets --jq '.secrets[].name' | grep -x DOPPLER_TOKEN_INFRA_APP   # DOPPLER_TOKEN_INFRA_APP
REPOL="$(gh api --paginate repos/jikig-ai/soleur/actions/secrets --jq '.secrets[].name')" || echo "repo secret listing failed: not clear"; printf '%s\n' "$REPOL" | grep -cx DOPPLER_TOKEN_INFRA_APP   # prints 0, and no "failed" line
doppler configs tokens -p soleur-infra-app -c prd --json | jq -r '[(. // [])[].name] | sort | join(",")'   # release-app-mint (empty output when no token exists: Doppler prints null for an empty list)
```

**The script is permanent for this feature.** It stays at its spec path as the rotation tool; census G7d
finds it by its content, including under `specs/archive/`, and fails if no such script exists. If it is
ever replaced, move it and keep the `soleur-infra-app` literal in the new file.

**Rotation.** After any rotation of the `soleur-infra` App private key, have the agent re-run the staged commands
(`preflight`, `copy-app-values`, `prove-live-app`, `mint-and-store-token`, `verify`, in that order; the person
approves each write at the Claude Code approval prompt on the exact command): `copy-app-values`
re-copies the two values on a hash difference and `prove-live-app` proves the copy with `GET /app`. Rotate in
this order so no release run sees a stale copy: add the new App key at GitHub, update both copies, prove
both, and only then delete the old key at GitHub (GitHub Apps accept several keys at once). To rotate the
read token on its own, the agent runs `--stage mint-and-store-token`, then the same stage again with
`--apply --plan-digest <d> --rotate-token`, which the person approves at the prompt on the exact command: it mints
a second token, stores it, and revokes the first only after the new one is stored and verified (new before old). A re-run that finds one
token it cannot show is the stored one (a lost `.env`, a crash between the steps) does the same
automatically; with two or more tokens it stops and prints the revoke commands. The read token is created
without an expiry (accepted: it is read-only on a project holding two values, and it is rotated on demand,
with every App key rotation or on any suspicion of exposure, rather than expiring on its own in the middle
of a release). Do not revoke the old read
token while a release run is in flight or queued (`gh run list -R jikig-ai/soleur --workflow build-inngest-bootstrap-image.yml --status in_progress`
and `--status queued`, `waiting`, `requested` and `pending` (an environment-approval hold is `waiting`), and the same five for `mint-inngest-bootstrap-tag.yml`, must all list nothing), because that run would fail at
its mint. A stale copy of the App key is detected only at the next release run, not before.

**Rollback, in this order.** A stale or rejected token, or a stale copy, is fixed forward first, with the
remedy column of the table above; roll back only when no remedy recovers. Each step gives its command and
what it must print. If #8609 R-step 2 has already run (the runtime key's read token is stored in
`soleur-infra-privileged/prd`), do not roll back: the revert hands both unattended release jobs the whole
project again, re-opening the D10 gate on `GITHUB_APP_RUNTIME_DOPPLER_TOKEN`; fix forward with the table above.

**Every fence below runs verbatim in a fresh shell** (an agent's Bash calls do not share variables): each one
derives what it needs from GitHub, and each gate ends in `exit 1`, so a pasted block stops at the first failed gate.

**(a) Revert the second change and push the revert.** This also reverts the bootstrap script fix carried in the
same diff, so a later re-run of the script needs it re-applied. The second change is looked up as PR 9453 itself
(a search for its issue number also matches unrelated pull requests), and the commit must touch the composite.

```bash
R=jikig-ai/soleur; BR=revert-release-app-source
MERGE_SHA="$(gh pr view 9453 -R "$R" --json state,mergeCommit --jq 'select(.state=="MERGED")|.mergeCommit.oid')"   # a 40-hex sha: the second change's merge commit
[[ "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "PR 9453 is not merged: stop"; exit 1; }   # no output
git fetch origin main >/dev/null 2>&1
git show --name-only --format= "$MERGE_SHA" | grep -qx .github/actions/mint-infra-app-token/action.yml || { echo "that commit is not the second change: stop"; exit 1; }   # no output
git switch -c "$BR" origin/main || { echo "branch setup failed: stop"; exit 1; }       # no output beyond git's own
git revert --no-edit "$MERGE_SHA" || { echo "revert failed: stop"; exit 1; }           # one new commit
git push -u origin HEAD || { echo "push failed: stop"; exit 1; }
gh pr create -R "$R" --fill || { echo "pr create failed: stop"; exit 1; }
gh pr merge -R "$R" --squash --auto || { echo "auto-merge not armed: stop"; exit 1; }
```

The merge waits for the required checks. This second fence re-derives the revert PR from its branch, so it can be
run again as often as needed; it prints a state other than `MERGED` until the merge lands:

```bash
R=jikig-ai/soleur; BR=revert-release-app-source
PR="$(gh pr list -R "$R" --head "$BR" --state all --json number --jq '.[0].number')"     # the revert PR, found from its branch
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "no revert PR found: stop"; exit 1; }                  # no output
STATE=""; for _ in $(seq 1 27); do   # bounded: about 9 minutes
  STATE="$(gh pr view "$PR" -R "$R" --json state --jq .state)"; [ "$STATE" = MERGED ] && break; sleep 20; done
echo "state=$STATE"                                                                      # state=MERGED
```

**(b) Prove the broad token works again, BEFORE anything is revoked.** A complete block of its own, driven by three
variables: the run must descend from the revert's merge (so a run from before it cannot pass), the credential step
is the reverted one and must conclude `success`, and the reverted composite prints no `source=` field. The notice
itself must be present exactly once, so an empty or absent log cannot read as zero. The block sets `PROVED=1` only
when every check holds, and prints `PROVED=1` as its last line; any other last line means the proof has not passed.

```bash
R=jikig-ai/soleur; WF=build-inngest-bootstrap-image.yml; BR=revert-release-app-source
VERIFY_STEP="Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present"     # the step name on main before the second change
EXPECT=0                                                        # the number of source= fields in the notice
BASE_SHA="$(gh pr list -R "$R" --head "$BR" --state merged --json mergeCommit --jq '.[0].mergeCommit.oid')"   # the revert's merge commit
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "revert not merged: stop"; exit 1; }       # no output
TAG="$(git fetch --tags origin >/dev/null 2>&1; git tag --list 'vinngest-v*' --sort=-v:refname | head -1)"   # the current max tag
PREV="$(gh run list -R "$R" --workflow "$WF" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
gh workflow run "$WF" -R "$R" --ref main -f ref="$TAG" -f mirror_only=true                  # the write the person approves
ID=""; for _ in $(seq 1 30); do   # bounded: up to 5 minutes for the new run to be listed
  ID="$(gh run list -R "$R" --workflow "$WF" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
  [ -n "$ID" ] && [ "$ID" != "$PREV" ] && break; ID=""; sleep 10; done
[ -n "$ID" ] || { echo "no new run was listed in 5 minutes: stop"; exit 1; }                # no output
gh run watch "$ID" -R "$R" --exit-status; RUN_RC=$?; echo "run rc=$RUN_RC"                  # run rc=0
git fetch origin main >/dev/null 2>&1
git merge-base --is-ancestor "$BASE_SHA" "$(gh run view "$ID" -R "$R" --json headSha --jq .headSha)"; ANC_RC=$?; echo "ancestor rc=$ANC_RC"   # ancestor rc=0 (the run is newer than the revert's merge)
STEP_CONCL="$(gh run view "$ID" -R "$R" --json jobs --jq ".jobs[]|select(.name==\"bump-cloud-init-pin\")|.steps[]|select(.name==\"$VERIFY_STEP\")|.conclusion")"; echo "$STEP_CONCL"   # success
NOTICE="$(gh run view "$ID" -R "$R" --log | grep -F '##[notice]app=soleur-infra')"
NCOUNT="$(printf '%s\n' "$NOTICE" | grep -c .)"; echo "notices=$NCOUNT"                      # notices=1 (the notice is present, once)
PROVED=0
if [ "$RUN_RC" = 0 ] && [ "$ANC_RC" = 0 ] && [ "$STEP_CONCL" = success ] && [ "$NCOUNT" = 1 ] \
   && [ "$(printf '%s\n' "$NOTICE" | grep -c 'source=')" = "$EXPECT" ]; then PROVED=1; echo "source count ok"; fi   # source count ok
echo "PROVED=$PROVED"                                                                       # PROVED=1
```

**(c) Run only after (b) printed `PROVED=1`.** Only now remove the narrow credentials. The fence re-proves (b) from
the runs already on GitHub (a variable does not survive between shells): a successful run of the build workflow
that descends from the revert's merge, whose reverted credential step concluded `success` and whose notice appears
once with no `source=` field. It then stops at the first failed gate: the revert must be merged, a post-revert
proof must exist, no release run may be queued, waiting or in flight (it would fail at its mint once the secret
is gone; a failed or non-numeric listing counts as a failed gate, never as zero), and exactly one token slug must
be found. The slug gate comes before the first deletion, so an abort leaves nothing half done.

```bash
R=jikig-ai/soleur; BWF=build-inngest-bootstrap-image.yml; BR=revert-release-app-source
REVERT_SHA="$(gh pr list -R "$R" --head "$BR" --state merged --json mergeCommit --jq '.[0].mergeCommit.oid')"   # the revert's merge commit
[[ "$REVERT_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "revert not merged: stop"; exit 1; }     # no output
PROVED=0
for RID in $(gh run list -R "$R" --workflow "$BWF" --status success --limit 10 --json databaseId --jq '.[].databaseId'); do
  git merge-base --is-ancestor "$REVERT_SHA" "$(gh run view "$RID" -R "$R" --json headSha --jq .headSha)" || continue
  [ "$(gh run view "$RID" -R "$R" --json jobs --jq '.jobs[]|select(.name=="bump-cloud-init-pin")|.steps[]|select(.name=="Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present")|.conclusion')" = success ] || continue
  PN="$(gh run view "$RID" -R "$R" --log | grep -F '##[notice]app=soleur-infra')"
  [ "$(printf '%s\n' "$PN" | grep -c .)" = 1 ] && [ "$(printf '%s\n' "$PN" | grep -c 'source=')" = 0 ] && { PROVED=1; break; }
done
[ "$PROVED" = 1 ] || { echo "no green post-revert run proves the broad token: run (b) first: stop"; exit 1; }   # no output
BUSY=0; for WF in build-inngest-bootstrap-image.yml mint-inngest-bootstrap-tag.yml; do for ST in in_progress queued waiting requested pending; do
  N="$(gh run list -R "$R" --workflow "$WF" --status "$ST" --json databaseId --jq length)" || { echo "run listing failed: stop"; exit 1; }
  [[ "$N" =~ ^[0-9]+$ ]] || { echo "run count is not a number: stop"; exit 1; }
  BUSY=$((BUSY + N)); done; done
[ "$BUSY" = 0 ] || { echo "release runs in flight or queued: stop"; exit 1; }                # no output
SLUG="$(doppler configs tokens -p soleur-infra-app -c prd --json | jq -r '(. // [])[] | select(.name=="release-app-mint") | .slug')"   # exactly one slug
[ -n "$SLUG" ] && [ "$(printf '%s\n' "$SLUG" | wc -l)" = 1 ] || { echo "not exactly one release-app-mint token: stop"; exit 1; }   # no output
gh secret delete DOPPLER_TOKEN_INFRA_APP --env infra-privileged -R "$R"; echo "rc=$?"    # rc=0
ENVL="$(gh api --paginate repos/$R/environments/infra-privileged/secrets --jq '.secrets[].name')" || { echo "listing failed: stop"; exit 1; }
printf '%s\n' "$ENVL" | grep -cx DOPPLER_TOKEN_INFRA_APP                                   # 0
doppler configs tokens revoke "$SLUG" -p soleur-infra-app -c prd >/dev/null; echo "rc=$?"   # rc=0
TOKS="$(doppler configs tokens -p soleur-infra-app -c prd --json)" || { echo "token listing failed: stop"; exit 1; }
LEFT="$(printf '%s' "$TOKS" | jq -r '[(. // [])[].name] | sort | join(",")')" || { echo "token listing unreadable: stop"; exit 1; }
echo "tokens left=[$LEFT]"                                                                  # tokens left=[]
# the person approves the next write; the line must end in the redirect
doppler secrets delete GITHUB_INFRA_APP_ID GITHUB_INFRA_APP_PRIVATE_KEY -p soleur-infra-app -c prd --yes > /dev/null
NAMES="$(doppler secrets -p soleur-infra-app -c prd --only-names)" || { echo "name listing failed: stop"; exit 1; }
echo "names left=$(printf '%s\n' "$NAMES" | grep -c GITHUB_INFRA_APP)"                      # names left=0 (names only, never values)
```

The `doppler secrets delete` line MUST end `> /dev/null`: the CLI prints every remaining secret of the config to
stdout on a delete, and the repo hook refuses the command without the redirect; the separate `--only-names`
read is the verification. A live credential with no consumer is exposure with no purpose, and revoking before
(b) has passed breaks the release jobs that still name it. The empty containers can stay; both Terraform
resources carry `prevent_destroy`, so removing them needs a PR that drops that guard first.

**Exposure the script cannot close.** An organisation-level secret named `DOPPLER_TOKEN_INFRA_APP`
would also be reachable from any branch's workflow. The script lists it when the `gh` login can read
the organisation's secrets and says INCONCLUSIVE otherwise. In that case run
`ORGL="$(gh api --paginate orgs/jikig-ai/actions/secrets --jq '.secrets[].name')" && printf '%s\n' "$ORGL" | grep -cx DOPPLER_TOKEN_INFRA_APP` (expected `0`; a failed listing prints nothing and must be read as unchecked, never as clear).
Listing organisation secrets needs the `admin:org` scope; a 403 means this login lacks it, so the exposure
stays unchecked and must be reported as unchecked, never read as clear.

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

- ADR-241 — the decision this runbook executes.
- `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` — the Art. 33 assessment.
  **Its L1 evidence limb must be gathered before O12 and O13**: GitHub Actions logs and run records
  expire at 90 days.
- `apps/web-platform/infra/github-infra-app-manifest.json`,
  `apps/web-platform/infra/github-board-app-manifest.json` — the two App manifests O1 and O1b use.
- `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` — the manifest flow,
  including the form-post helper and the permission-widening re-acceptance click.
- `tests/scripts/test-infra-privileged-tier-census.sh` — the PR-time guard for everything in
  §Consumer inventory.
