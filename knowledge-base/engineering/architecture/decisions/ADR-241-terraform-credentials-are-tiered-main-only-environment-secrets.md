---
title: "ADR-241: Terraform credentials are tiered; Tier B is delivered only through main-only environment secrets"
status: proposed
date: 2026-09-22
issue: 8209
supersedes: []
amends:
  - ADR-220
  - ADR-169
tags: [credentials, terraform, doppler, github-environments, r2, secrets, security]
---

# ADR-241: Terraform credentials are tiered; Tier B is delivered only through main-only environment secrets

## Status

`proposed` in frontmatter, because the frontmatter holds one value and the decisions below do not
share one. Each decision's own status is in the **Statuses** table. This follows ADR-220's
convention: `architecture list` shows the frontmatter's single status, which is the least-advanced
one, and D2's is `proposed`.

- **D1 and D3–D8 are `adopting`.** They are implemented by the PR that carries this ADR
  (references #8209; it does not close it). They flip to `accepted` when the runbook's post-operator
  verification passes — AC12 through AC16 of the plan.
- **D2 stays `proposed` until residual R1 closes.** This is explicit, and it is the CPO sign-off
  condition. Until R1 closes, D2 stops a branch workflow from *naming* a Tier-B secret; it does not
  stop an actor who already holds a `prd` repo-secret token, because that actor can rewrite the very
  deployment-branch policy D2 rests on. A boundary whose own enforcement is inside the blast radius
  is not `accepted`.
- **D9's residuals are standing constraints.** They are not accepted as closed; each is discharged
  by the issue named with it.

The ordinal was chosen after enumerating every `origin/*` ref: `feat-8322-affected-test-gate`
already claims ADR-238. Re-run that probe immediately before merge — a parallel #8211 session may
claim 239.

## Context

`jikig-ai/soleur` is a public repository. Any workflow on any branch of it can name the
`DOPPLER_TOKEN` repo secret, and that token reads Doppler `soleur/prd_terraform`. Measurement
(#8209, recorded in the plan's Research Reconciliation table) found that `prd_terraform` is a
**branch config of `prd`**, not an isolated config, and that it holds four credentials whose reach
goes far past Terraform:

1. `DOPPLER_TOKEN_TF` — a workplace **personal** token that reads every Doppler project, including
   the isolated `soleur-git-data-root`.
2. `CF_API_TOKEN_R2` — account-wide R2.
3. `HCLOUD_TOKEN` — read/write Hetzner, which is root on any host through rescue, rebuild or a
   volume re-attach.
4. `GITHUB_APP_PRIVATE_KEY` — a distinct private key of the soleur-ai App, which has three
   installations, two of them outside `jikig-ai`.

Two further paths reach the git-data root key, which is root on the host that stores every connected
user's repositories: the repo secret `DOPPLER_TOKEN_GIT_DATA_ROOT`, and the state object
`web-platform/git-data-root-key/terraform.tfstate`, which the `prd_terraform` R2 backend keys read.
A separate measurement showed those backend keys are **read/write** on `soleur-terraform-state`, so a
branch actor could also tamper with state a later `main` run acts on.

ADR-220's amendment already named this: its D2 entry records that "the custody goal is nominal
today", that the separate root "does not protect against a repo-secret holder", and that closing
that gap is #8209 and "needs its own ADR". This is that ADR.

Two constraints shape what the fix can be:

- **Doppler service-account identities and OIDC need the Team or Enterprise plan**, and the
  workplace is on the Developer plan. ADR-220's amendment already rejected OIDC for this reason and
  took the repo-secret fallback.
- **The Terraform GitHub identity cannot write environment secrets.** The soleur-ai App holds
  `administration:write` and `secrets:write` but no `environments` permission, which is consistent
  with the measured 403 on `environments/<env>/secrets/public-key`.

A reviewer-gated environment is not a substitute. ADR-220's own finding stands: an environment gate
is a single-human acknowledgement on branch bytes, not a secret boundary. What *is* a boundary is
the deployment-branch policy, because GitHub evaluates it before the job starts and before any
environment secret is materialized.

## Decision

### D1 — Two tiers

Credentials are split by what their disclosure costs, not by what they are named.

- **Tier A is branch-reachable.** It is repo secrets plus every Doppler config a repo-secret token
  reads. It holds only credentials whose disclosure is bounded: read-only, placeholder, or
  bucket-scoped to the non-privileged state bucket.
- **Tier B is main-only.** It holds every credential that writes infrastructure, reads another
  tier's secrets, or reaches third-party installations.

Tiering is by measured config and access, never by a secret's name (learning
`2026-05-15-token-namespace-divergence-across-secret-stores.md`).

### D2 — The boundary is a main-only environment secret

**A Tier-B credential is delivered only as a GitHub environment secret, on an environment whose
deployment-branch policy admits `main` only.** This holds whether or not the environment also has
required reviewers: the reviewers are a human gate, the branch policy is the secret boundary.

A new environment, **`infra-privileged`**, carries the `main` policy and has **no reviewers**. It
serves the unattended Tier-B jobs — apply-on-merge and the scheduled drift check — which a reviewer
gate would deadlock. Jobs that already declare a reviewer-gated environment keep it; that
environment then carries the same Tier-B secret and **must** have a `main` policy of its own. The
four Tier-B environments are `infra-privileged`, `web-platform-infra-apply`, `inngest-cutover` and
`workspaces-luks-cutover`. The last of these had **no** deployment-branch policy when measured, so a
branch run with reviewer approval passed; this ADR gives it one.

Both halves of the policy are required and both are load-bearing: `deployment_branch_policy {
protected_branches = false, custom_branch_policies = true }` says "this environment uses a named
list", and the named list itself is a separate
`github_repository_environment_deployment_policy` resource. Omitting the block leaves the
environment open to every branch; omitting the policy resource leaves the list empty, which GitHub
reads as "no branch may deploy". An environment a job references but that does not yet exist is
**auto-created by GitHub with no protection at all**, which is why the runbook's O0 step reads the
live policy back on all four environments before any secret is seeded.

**A stated consequence, not a side effect: `git_data_host_replace` gains an environment, and
therefore a non-`main` dispatch of that incident-recovery path is refused.** That job shipped with
no `environment:` key deliberately, so that a `workflow_dispatch` ran the *selected ref* and the
branch it polices supplied its own gate. As a Tier-B job it can read no environment secret without
one, so it gets `infra-privileged` — and with it the `main` policy. This is the right trade (the
job's own header already concedes that the no-environment shape "does NOT hold against a deliberate
actor with repository write access"), but it changes the behaviour of a path that recovers the
product, so it is recorded here as a decision. It is also why the runbook rehearses both
host-replace paths from `main`, in plan-only mode, **before** the eviction step removes the legacy
fallback that is currently masking any breakage. See U5 below.

### D3 — Carrier: a Doppler project, not a branch config

A new Doppler **project**, `soleur-infra-privileged` (environment and config `prd`), holds the
Tier-B values:

- `DOPPLER_TOKEN_TF`;
- `HCLOUD_TOKEN` (read/write);
- `CF_API_TOKEN_R2`;
- `GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_INSTALLATION_ID`, `GITHUB_INFRA_APP_PRIVATE_KEY`;
- `GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID` and `GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY`;
- `TF_STATE_AWS_ACCESS_KEY_ID` and `TF_STATE_AWS_SECRET_ACCESS_KEY` — the read/write key for
  `soleur-terraform-state` (D9, R7).

A **project**, not a `prd_*` branch config, because a branch config resolves its root's secrets
(learning `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`) — that is
exactly how the four credentials became branch-reachable. Its read service token is the environment
secret `DOPPLER_TOKEN_INFRA_PRIVILEGED`.

**Terraform creates the containers; it never mints the token or the values.** The project and the
environment are declared in `apps/web-platform/infra/infra-privileged-environment.tf`, which
deliberately declares **no** `doppler_secret` and **no** `doppler_service_token`. Anything the
web-platform root mints lands in a state object the Tier-A backend keys read, so a secret minted
there would be readable by exactly the tier this decision exists to evict it from. A container's
existence is not a secret; its contents are. The file's header comment states this so a later edit
cannot re-add one by accident, and a census row greps for it.

Bucket names are likewise not secret and stay in code (ADR-130 governs the token: no credential we
hold can mint a bucket-scoped R2 token programmatically, so that one is operator-minted).

### D4 — Tier-A substitutes

Eviction without substitutes would break the PR plan, so every Tier-A consumer gets a bounded
replacement first.

- **State keys.** `prd_terraform` `AWS_*` becomes a **read-only**, bucket-scoped key for
  `soleur-terraform-state`. The read/write key moves to Tier B as `TF_STATE_AWS_*`. PR plans only
  read state, so a branch can no longer forge state that a later `main` run acts on.
- **Hetzner.** Tier A gains `HCLOUD_TOKEN_READONLY`, a Hetzner Read-permission token. A **different
  name**, deliberately, so it can never shadow the Tier-B value.
- **Removals.** Tier A loses `DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN` and `CF_API_TOKEN_R2` outright.
- **The App key.** `GITHUB_APP_PRIVATE_KEY` is inherited from `prd`, so it cannot be deleted from
  `prd_terraform`. It gets a **sentinel override**, `EVICTED_SEE_ADR_241`, which shadows the
  inherited runtime key for the Tier-A token. A sentinel rather than an empty value, because Doppler
  may treat an empty branch-config value as "inherit"; a non-empty non-PEM value can be mistaken for
  neither inheritance nor a usable key. Both legacy App-token fallbacks refuse it with
  `verdict=legacy_app_key_evicted`. `EVICTED_SEE_ADR_241` is the literal byte string as it already
  appears in `apps/web-platform/infra/variables.tf`, in `main.tf`'s auth-mode comment and in the
  runbook's eviction step; its ordinal is one below this ADR's and that is **not** to be "corrected"
  in place, because the post-eviction check (AC12) compares a sha256 of that exact string. If the
  ordinal is ever realigned, the code, the runbook and the check change together in one PR.
- **The PR plan.** `infra-validation.yml`'s plan job runs `terraform plan -refresh=false` with
  well-formed placeholders for the Doppler and R2 providers and the GitHub provider in token mode,
  carrying `--preserve-env` for those variables so the placeholders win in the before state too and
  the PR's own CI exercises the Tier-A path. This was measured: a `-refresh=false` plan of the
  web-platform root succeeds with placeholders and a `GITHUB_TOKEN`-shaped token, and differs from a
  full-refresh plan by exactly one drifted address, which is the drift job's concern.

### D5 — GitHub identity

- **Three auth modes, selected by which variables are non-empty.** The selector is the
  configuration, because Terraform cannot tell a plan from an apply and so cannot be given a `tier`
  variable it could precondition on. The `dynamic "app_auth"` block's `for_each` is the exact
  complement of the `token` condition, so exactly one of `token`/`app_auth` always resolves. That
  construction is load-bearing: HCL cannot precondition a provider, and `integrations/github` v6
  silently falls back to an ambient `GITHUB_TOKEN` or `gh auth token` when neither resolves, which
  would authenticate as whoever the runner happens to be rather than failing.
  - **infra** — `github_infra_app_private_key` set: the dedicated Tier-B App.
  - **token** — `github_plan_actions_credential` set and no infra key: the PR plan job's own
    `GITHUB_TOKEN`.
  - **legacy** — neither set: the soleur-ai key from `prd_terraform`. This is the before state only.
- **A dedicated App, `soleur-infra`,** installed on `jikig-ai` alone, on the selected repositories
  Terraform manages, with permissions derived from the resource types Terraform manages —
  `environments:write` included, which is what eventually lets R6 (#8610) close.
- **Board sync does not use it.** `board-status-sync.yml` runs on `pull_request`/`issues`, stays
  Tier A, and mints from its own least-privilege App, `soleur-board`
  (`organization_projects:write` plus the read scopes its GraphQL queries need), whose key lives in
  `prd_terraform`. A leak there reaches the org project board and nothing else. Giving an
  admin-capable App to a fork-triggerable job was the single largest new attack surface in the first
  draft, and both the CTO and the advisor reviews rejected it.
- **The soleur-ai key that Terraform used is deleted in the App settings after the switch.** There
  is no API for that delete, and the App's two keys are distinguishable only by fingerprint. See U2.

### D6 — Integrity: the loader's values win by construction

`doppler run` **overrides** existing environment variables by default. A Tier-B job that loads Tier-B
values and then runs `doppler run -c prd_terraform` would therefore have its values replaced by
whatever `prd_terraform` holds — and `DOPPLER_TOKEN_WRITE`, a Tier-A repo secret, was measured
read/write on `prd_terraform`. A branch actor could plant `HCLOUD_TOKEN=<their own account>` there
and a Tier-B run would act on it.

- **Every `doppler run` in a Tier-B job carries `--preserve-env`.** The flag makes precedence a
  property of the code rather than of an external config's contents. It was measured: bare
  `--preserve-env` and the explicit-list form both keep the environment value; the source name does
  not, and there is no environment-variable form of the flag. Under `--name-transformer tf-var`
  every Doppler key becomes `TF_VAR_*`, and the only `TF_VAR_*` in a Tier-B job's environment are the
  loader's, so "all" is exactly "the loader's". This makes the before and after states identical: the
  eviction becomes hygiene rather than a correctness condition, and a later same-named secret
  appearing in `prd` cannot shadow Tier B either.
- **`DOPPLER_TOKEN_WRITE` moves to Tier B,** which removes the only measured Tier-A write path into
  `prd_terraform`.
- **The loader checks its auth mode in shell before any plan.** When `source=tier_b` it requires
  `TF_VAR_github_infra_app_private_key` to be non-empty and refuses otherwise. This is in shell
  because HCL cannot precondition a provider, and because a composite action cannot unset a variable
  for later steps.

A sha-compare guard against `prd_terraform` was considered and cut: it made correctness depend on an
external config's contents, and it hard-failed apply-on-merge whenever an unrelated same-named secret
appeared in `prd`, which `prd_terraform` inherits.

### D7 — The privileged state bucket and the partial backend

The git-data root key is the highest-value credential in this system, and the two paths to it are a
repo secret and a state object. Both move.

- **The read token keeps its name.** `DOPPLER_TOKEN_GIT_DATA_ROOT` becomes an environment secret on
  `web-platform-infra-apply` under the **same name**, so the #8211-owned `git-data-cutover.yml` needs
  no edit: its `cutover` job already declares that environment, and an environment secret overrides
  a repo secret of the same name. The Terraform-minted token and the repo secret are **forgotten** by
  Terraform (`removed` blocks with `lifecycle { destroy = false }`), then revoked and deleted out of
  band. Forget-not-destroy is what makes the merge safe: the live token and secret keep working until
  they are replaced.
- **A second state bucket.** `web-platform/git-data-root-key/terraform.tfstate` moves to a new R2
  bucket, `soleur-terraform-state-privileged`, declared as
  `cloudflare_r2_bucket.terraform_state_privileged`. The Tier-A backend keys are **bucket-scoped**
  (measured: `ListBuckets` returns `AccessDenied`, `ListObjectsV2` returns the seven objects), so a
  bucket they are not scoped to is genuinely out of reach rather than merely un-referenced. The
  bucket-scoped token for it is Tier-B only and operator-minted (ADR-130). This supersedes ADR-220's
  D2.1 reversal, which put the root-key state in the shared bucket precisely because no credential
  could mint a bucket-scoped token — the token is still operator-minted; what changed is that the
  bucket is now worth having anyway, because the Tier-A keys are scoped rather than account-wide.
- **A partial backend, so both states work.** `git-data-root-key/main.tf` drops its literal `bucket`,
  so `terraform init` takes `-backend-config=bucket=$BUCKET`. `$BUCKET` is the privileged bucket when
  the loader exported the `GIT_DATA_ROOT_STATE_*` key pair and the legacy bucket otherwise; the pair
  is all-or-none and a half-set pair is refused (`verdict=git_data_root_state_half_set`). Once the
  repo variable `GIT_DATA_ROOT_STATE_MIGRATED=1` is set, the legacy bucket is **refused**
  (`verdict=git_data_root_state_legacy_after_migration`), so the fallback cannot silently outlive the
  migration. The PR plan job never initializes this nested root — `detect-changes` collapses it into
  its parent (ADR-220 D2.2) — so no PR-plan backend config is needed.
- **Fail-closed after the old object is gone.** If the legacy fallback were ever taken after the old
  object is deleted, `init` would yield an empty state and a create would be planned. The existing
  `git_data_root_key_remint_refused` gate, which keys on the committed fingerprint file, refuses that
  plan. A re-mint is structurally unreachable, not merely unlikely.

### D8 — The census is the enforcement mechanism

A decision that lives only in prose is not a boundary. **One CI suite,
`tests/scripts/test-infra-privileged-tier-census.sh`, runs on every PR** and asserts the property
over every workflow file and every composite action. It is registered in `scripts/test-all.sh`
beside the existing git-data root-token census, whose harness conventions it follows: an instrument
self-test, floors, `mutant_red` rows, and an input-tree seam so the suite can be driven against a
synthesized tree.

The contract it enforces, and the four guards that stand beside it:

1. **Guard 1 — tier census.** Every job naming `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE`
   or `DOPPLER_TOKEN_GIT_DATA_ROOT` (case-insensitively, including `secrets[<expr>]`,
   `toJSON(secrets)` and `secrets: inherit`) declares an environment; every arm of that declaration
   is a Tier-B environment; every such environment has a Terraform-declared `main` deployment policy,
   parsed from the `.tf` sources; no step outside the loader reads a Tier-B name from
   `prd_terraform`; and a Tier-B job with **no** `environment:` key is red.
2. **Guard 2 — Tier-B precedence.** Every `doppler run` inside a Tier-B job carries `--preserve-env`,
   including runs inside scripts those jobs invoke (the census resolves one level of `bash
   <repo-path>` indirection and fails closed on an unresolvable path), and the loader step precedes
   every one of them.
3. **Guard 3 — the root-key allowlist arm.** `apply-git-data-root-key.yml` admits exactly a forget of
   the two custody addresses and nothing else. The arm is one-shot; R6 (#8610) deletes it.
4. **Guard 4 — `removed` blocks forget, never destroy.** Every `removed` block names an address that
   exists in that root's state, carries `lifecycle { destroy = false }`, and appears in the
   `-target=` list of the workflow that plans it. This has a guard of its own rather than a bullet in
   Guard 1 because of U1: getting it wrong is not a failed run, it is every connected user
   disconnected.
5. **Guard 5 — `plan_only` only ever subtracts.** In the two recovery jobs, every mutating step
   carries the guard, no step is *enabled* by it, and the input-validation, typo-guard and
   environment gates stay unconditional.

**The anchor matters more than the lists.** The Tier-B job set is derived from references to the
Tier-B secret, and the environment set from what those jobs declare — never from a hand-kept
allowlist. A new job therefore cannot escape the rule by omission, and a list-weakening edit has
nothing to weaken. What the census cannot see is live state (it holds no credential at PR time), so
the live limb is the runbook's O0 hard gate: read all four environments' live policies back before
any secret is seeded.

### D9 — Residuals, recorded with a status each

These are **not** accepted as closed.

| # | Residual | Status |
|---|---|---|
| R1 | The soleur-ai **runtime** key in Doppler `prd` is readable by `DOPPLER_TOKEN_PRD` and by every `prd_*` branch-config repo-secret token. The App holds `administration:write` on `jikig-ai/soleur`, so a holder can rewrite an environment's deployment-branch policy — which defeats D2 — and can use `contents:write` plus its ruleset-bypass listing to change scripts that `main` jobs run. | **OPEN — [#8609](https://github.com/jikig-ai/soleur/issues/8609).** Filed at `p1-high`, `type/security`, ranked on its own risk (the runtime key reaches two third-party installations **today**), not merely as a cutover precondition. Blocks #8211 and the first real git-data cutover. **D2 stays `proposed` until it closes.** Detective control meanwhile: `scheduled-terraform-drift.yml` (Tier B) plans the `github_repository_environment*` resources and the `infra/github` rulesets, so a rewritten policy or bypass list surfaces as drift on that job's existing email and Sentry route. |
| R2 | Web-platform root state is Tier-A readable and holds other Terraform-minted secrets. | **PRE-EXISTING, accepted by ADR-220.** Narrowed here: the two `doppler_secret.github_app_*` mirrors leave that state. |
| R3 | Tier-B dry runs can no longer be dispatched from a branch ref. | **ACCEPTED.** A branch-ref Tier-B dispatch is exactly the reach this ADR closes. |
| R4 | The PR plan no longer shows live drift. | **ACCEPTED.** `scheduled-terraform-drift.yml` owns drift; the plan comment header says so. |
| R5 | The four credentials were branch-reachable in a public repository before this change. Moving them does not revoke copies taken earlier. | **OPEN until rotation completes.** Rotation is **required**, not optional (CPO condition): each credential is rotated one at a time, new value first, canary, then delete. #8209 does not close until the per-credential invalidation probes (AC16) pass. A dated Art. 33 **assessment** — REACHABILITY-ONLY disposition, evidence limbs INCONCLUSIVE until shown clean — is filed in `knowledge-base/legal/audits/` and indexed in the breach register. |
| R6 | The Tier-B environment secrets are operator-seeded, because the Terraform identity cannot write environment secrets until the infra App exists. | **OPEN — [#8610](https://github.com/jikig-ai/soleur/issues/8610).** Target design: keep `doppler_service_token.git_data_root_read` in the (by then Tier-B) root-key state and publish it with `github_actions_environment_secret` under the infra App. That issue also drops the dangling `-target=` lines of the forgotten addresses and deletes Guard 3's one-shot arm. |
| R7 | Before this change the Tier-A backend keys were **read/write** on `soleur-terraform-state`, so a branch actor could tamper with web-platform state — for example by swapping a `doppler_service_token.key` that a later `main` run publishes. | **FOLDED IN; closes at the runbook's state-key step (O5b).** D4's read-only Tier-A key plus `TF_STATE_AWS_*` in Tier B, with every backend-credential extraction in a Tier-B job preferring the Tier-B pair. Every **writer** of that bucket must be Tier B before the swap, `apply-sentry-infra.yml`'s apply job included. Required in-PR by both the CTO and the architecture reviews. |

## Statuses

| Decision | Status | Flips when |
|---|---|---|
| D1 tiers | `adopting` | AC12–AC16 pass: the three names are absent from `prd_terraform`, the App key there hashes equal to the sentinel, and the per-credential invalidation probes return `401`/verify-failure. |
| D2 boundary | `proposed` | **R1 (#8609) closes** (and R7 closes at O5b). Until then the boundary is nominal against a `prd` repo-secret holder. This is the CPO sign-off condition. |
| D3 carrier | `adopting` | The Tier-B project is populated and its read token is seeded on all four environments, and the canary reads `source=tier_b`. |
| D4 Tier-A substitutes | `adopting` | The read-only Hetzner token returns `token_readonly` on a write, and the Tier-A state pair returns `403` on a put and `200` on a get. |
| D5 GitHub identity | `adopting` | The infra App's write scopes are exercised by a green no-op apply-on-merge from `main`, and board sync runs with no legacy warning. |
| D6 integrity | `adopting` | The loader's sentinel row and Guard 2 are green on the PR, and a planted same-named `prd_terraform` value is measured to have no effect. |
| D7 state custody | `adopting` | The privileged bucket's object matches the source by sha256, lineage and serial; a Tier-A key gets `403` on it; the two custody forgets have applied. |
| D8 census | `adopting` | Every mutation row of the Guard Contract is measured RED, and the suite is green on the PR head. |
| D9 residuals | Standing constraints | Not accepted. Each is discharged by the issue named with it. |

## Consequences

**Easier:**

- A branch workflow can no longer obtain a credential that writes infrastructure, reads another
  tier's secrets, or reaches a third-party installation — by construction, before the job starts.
- A branch can no longer forge the *state* a later `main` run acts on, nor plant a value a Tier-B run
  would read.
- The carrier is swappable. If the workplace later moves to a Doppler plan with service-account
  identities, only the delivery mechanism changes; the boundary design is unchanged.
- Rotation gains an audit trail: Tier-B values live in one project rather than scattered across repo
  secrets.

**Harder or newly true:**

- **A Tier-B job that loses its environment binding fails closed.** That is the point, and it is why
  the census has an explicit row for a Tier-B job with no `environment:`.
- **A non-`main` dispatch of `git_data_host_replace` is refused** (D2). Recorded in the job header,
  here, and in the runbook.
- **Environment deployments create a deployment record for every Tier-B run.** Cosmetic.
- **The merge itself mutates production.** Apply-on-merge fires on push to `main` for the
  web-platform root's `.tf` files and creates the environment, its policy, the Doppler project and
  environment, and the R2 bucket — and plans the four forgets. The merge click is the authorization
  for that, and the PR body's first line says so.
- **Revert is not the rollback.** A plain revert deletes the new resource blocks and their
  `prevent_destroy` with them, so the next run would destroy the project, the environment and the
  bucket. Rolling back means a follow-up PR that swaps each new resource for `removed { … lifecycle {
  destroy = false } }` and restores the forgotten ones with `import` blocks.
- **Nine operator-sequenced steps stand between the merge and the property.** Merging and stopping
  leaves every workflow on the legacy path, which is today's behaviour — the code half works in both
  states by construction. But the property is not bought until the sequence completes, and #8209
  cannot close on the merge alone.

### What this decision must not break

Five user-facing failure modes were found by the user-impact review at the `single-user incident`
threshold. Each is guarded in code and in the operator sequence; they are recorded here because the
guards are only legible next to the harm they bound.

- **U1 — the live GitHub App key must not be destroyed.** `doppler_secret.github_app_id` and
  `doppler_secret.github_app_private_key` pin `config = "prd"`. That pair is not a Terraform
  bookkeeping copy: it **is** the soleur-ai App's runtime identity, which the web app reads to mint
  every connected user's installation token. Replacing those resources with `removed` blocks
  destroys them if the address is misspelled, if the `-target=` list omits the address (the forget
  never plans, the resource stays managed with no HCL declaring it, and the next untargeted run
  destroys it), or if `destroy = false` is omitted. `ignore_changes = [value]` protects the value,
  never the resource. The moment they are gone, every connected user's GitHub connection stops,
  every inbound webhook is rejected, and no repository operation succeeds — and after the sentinel
  lands, a naive recreate would write a non-PEM sentinel over the runtime key. Guarded by: addresses
  copied from `terraform state list` rather than typed, Guard 4, AC2c, the destroy-guard forget rows,
  and the runbook's O0 gate (before/after `prd` key hashes, a no-`delete` assertion on the plan JSON,
  and a live installation-token mint proved through the App's own runtime path).
- **U2 — the wrong App private key must not be deleted.** The soleur-ai App has three installations,
  two outside `jikig-ai`, and its runtime key serves all three. Deleting the Terraform key is a click
  in App settings on a list of fingerprints; there is no API. Deleting the runtime key instead
  produces U1's outcome with no Terraform involvement and **no rollback** — GitHub issues a new key,
  it does not restore one. Guarded by: a DER-SHA-256 fingerprint comparison of both keys before the
  click, and a runtime proof after it.
- **U3 — the hosts must not lose their configuration at the next restart.** Terraform, running as
  `DOPPLER_TOKEN_TF`, created the Doppler **service tokens the production hosts read their own
  configuration with**: the git store's boot token, the ghcr minter's, and the zot registry's. D9's
  R5 rotation revokes `DOPPLER_TOKEN_TF`. If Doppler cascades a personal token's revocation to the
  service tokens it created, a running host keeps working on its cached environment and then fails at
  its next restart or replace — and the git store comes back with no secrets and no LUKS passphrase.
  A cascade is therefore **silent until the worst possible moment**. Guarded by a read-only gate
  before the revocation: enumerate the creator-bound set from state, settle the vendor behaviour in
  writing rather than by inference, and prove it with a disposable-personal-token negative control.
  An expected answer is not a confirmed one.
- **U4 — a revocation must not take out the running git store.** Two tokens are revoked by *slug*, an
  opaque string that names nothing. A wrong slug on the `soleur-git-data-root` line revokes the token
  the **running** git-data host uses to reach its root key — and the stated verification, a cutover
  dry run, runs in CI with its own credential and never exercises the host's own access, so it passes
  while the store is broken. Guarded by: printing the full `name`/`slug` table and requiring an exact
  ledger-name match before each revoke (aborting on a duplicate or a missing name), then reading the
  store's health from the observability layer and its own endpoint within minutes.
- **U5 — incident recovery must not fail closed unnoticed.** Between seeding the Tier-B secret and
  the eviction, the legacy fallback hides a broken recovery path; the eviction is what removes the
  fallback. `web_host_replace` declares a reviewer-gated environment and is seeded; **`git_data_host_replace`
  declares no environment at all**, so as a Tier-B job it can read no environment secret until D2
  gives it one — and D2 giving it one is precisely what makes a non-`main` dispatch refuse. A no-op
  apply-on-merge canary exercises neither path. Guarded by: the census's environment-binding row at
  PR time, a `plan_only` dispatch arm that only ever *subtracts* steps (Guard 5), and a rehearsal of
  both recovery paths from `main` before the eviction. Rehearsing them for the first time during an
  incident is the failure this bullet exists to prevent.

## Alternatives considered

| # | Alternative | Why not |
|---|---|---|
| A1 | Doppler Team plan plus OIDC service-account identities bound to the environment `sub` | **A cost decision, not a design one.** Service-account identities need Team or Enterprise; the workplace is on the Developer plan, and the recurring cost has not been approved. ADR-220's amendment already recorded that limit and took the repo-secret fallback. The environment-secret design buys the same property on the current plan, and is plan-agnostic: a later upgrade replaces only the carrier, not the boundary. |
| A2 | A dedicated **read-only plan** GitHub App for the PR plan | The workflow's own `GITHUB_TOKEN` in token mode is enough for a `-refresh=false` plan (measured). A second App is a second identity to provision, install and revoke for no property gained. |
| A3 | Per-environment distinct privileged tokens | One token set on N environments already meets the property. Per-environment tokens only refine revocation granularity, at the cost of N mints and N rotations per credential. Deferred, not rejected on principle. |
| A4 | Put the four credentials directly into GitHub environment secrets, with no Doppler hop | Loses AP-008 (Doppler is the source of truth). Every rotation becomes a multi-environment `gh secret set` with no audit trail in Doppler. |
| A5 | Keep full-refresh PR plans with read-only credentials | No read-only Doppler credential exists on the Developer plan, and an account-level R2 read token reads every bucket's objects. The placeholder path was measured instead. |
| A6 | Move the PR plan behind a reviewer-gated environment with an all-branches policy | Branch bytes execute with the credentials (providers, `external` data). A human acknowledgement on branch bytes is not a secret boundary — ADR-220's own finding. |
| A7 | Terraform-manage `DOPPLER_TOKEN_GIT_DATA_ROOT` as an environment secret now | The correct end state, adopted by R6 (#8610). Not merge-safe here: until the infra App exists the provider is still the soleur-ai App (403 on environment secrets), and a partially applied rotation arm could revoke the old token before the new environment secret exists. |
| A8 | Keep the sha-compare integrity guard instead of `--preserve-env` | It made correctness depend on an external config's contents, and hard-failed apply-on-merge whenever an unrelated same-named secret appeared in `prd`, which `prd_terraform` inherits. `--preserve-env` makes precedence a code property. |
| A9 | Board sync on `pull_request_target` with the infra App | Hands an App with administration and environment write to a fork-triggerable job. A board-only App in Tier A is least privilege. |
| A10 | Grant `environments:write` to the soleur-ai App | Widens the permissions of a customer-installed App, and every installation must re-approve. |
| A11 | Evict the soleur-ai runtime key from `prd` in this change | Needs runtime and host bootstrap changes (hash-bound cloud-init, immutable redeploy). Deferred as R1 (#8609) — and R1 is why D2 is not `accepted`. |
| A12 | A `tier` variable plus an apply-refusing precondition in HCL | Terraform cannot tell a plan from an apply in configuration. A token-mode run that tried to write would fail anyway: the PR `GITHUB_TOKEN` is read-only and the Doppler and R2 placeholders are rejected by the vendor APIs. No property needs it. |

## References

- Plan: `knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md`
  (Decision, Guard Contract, Operator Sequence, User-Brand Impact)
- Runbook: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- Terraform: `apps/web-platform/infra/infra-privileged-environment.tf` (the Tier-B carriers and the
  privileged bucket), the provider auth modes in `apps/web-platform/infra/main.tf`,
  `infra/github/main.tf` and `apps/web-platform/infra/git-data-root-key/main.tf`, the `removed`
  blocks in `github-app.tf`, `doppler-write-token.tf` and `git-data-root-key/access.tf`
- Guard: `tests/scripts/test-infra-privileged-tier-census.sh`; loader
  `.github/actions/infra-credentials/action.yml`
- ADR-220 (git-data root access; its D2 custody goal is carried here, its D4 repo-secret-reach
  residual is addressed here — see its Amendment log entry dated 2026-09-22),
  ADR-130 (no programmatic bucket-scoped R2 token), ADR-168 (a mis-bound service token errors
  loudly), ADR-065 (Terraform variables exist before an IaC merge), ADR-231 (workflow byte budget),
  ADR-228 (generated operator scripts), ADR-237 (host keys are pinned; its #8209 residual is in
  scope here)
- Issues: #8209, #6167, #8189, #8211, #8385, #8093
