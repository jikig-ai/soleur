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
- **D10 is `adopting`** (added 2026-09-30, #8609; see the Amendment log). It flips with D2, in the
  PR that closes #8609, once residual R1's gates G1–G4 hold.
- **D11 is `accepted`** (added 2026-10-01, #9321; `adopting` 2026-10-03; `accepted` 2026-10-04, #9462;
  see the Amendment log). The first change added the container, the bootstrap script and census Guard 7
  and switched nothing; the second change (the composite action and both release workflows) is the
  switch. A release run after that merge was green through the narrow credential, which that run's
  `app-token` notice showed by its `source=soleur-infra-app/prd` field.

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

> **Amended 2026-09-30 (#8609), D1 census:** `WEBHOOK_DEPLOY_SECRET` and the CF Access client ID
> and secret in `soleur/prd_terraform` are **Tier B**, not Tier A. Together they authenticate
> `/hooks/infra-config`, which can rewrite `ci-deploy.sh` on the production host and read the host's
> credential file, so they write infrastructure. Their eviction to Tier B and their rotation is
> [#9294](https://github.com/jikig-ai/soleur/issues/9294) (gate G1 of residual R1). This is a tier
> classification change, recorded here rather than as a new ADR. See the Amendment log.

### D2 — The boundary is a main-only environment secret

**A Tier-B credential is delivered only as a GitHub environment secret, on an environment whose
deployment-branch policy admits `main` only.** This holds whether or not the environment also has
required reviewers: the reviewers are a human gate, the branch policy is the secret boundary.

A new environment, **`infra-privileged`**, carries the `main` policy and has **no reviewers**. It
serves the unattended Tier-B jobs — apply-on-merge and the scheduled drift check — which a reviewer
gate would deadlock. *(Note, 2026-09-28, #6604 step 7: it also serves one dispatched state-forget,
`workspaces-plaintext-forget.yml`, a `terraform state rm` that only forgets addresses whose object is
measured gone; the census now classifies `terraform state rm|mv|push` as a state write.)* *(Note,
2026-09-30, #9262: it also serves the two inngest-release App-token consumers, the auto-mint
`mint-inngest-bootstrap-tag.yml::mint` and the pin bump
`build-inngest-bootstrap-image.yml::bump-cloud-init-pin`. Both mint the `soleur-infra` App token
through `.github/actions/mint-infra-app-token` and are unattended. The build's `push: tags` trigger
was removed in the same change, because this environment's `main` policy refuses a tag-ref run.)* *(Note, 2026-10-04, #9377: it also serves one dispatched, read-only diagnostic, `web-host-escrow-diagnose.yml`, which lists Doppler secret names and changes nothing; the residual it shares with them is stated in full in the 2026-10-04 entry of the Amendment log.)* Jobs that already declare a reviewer-gated environment keep it; that
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

`GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY` also have a second copy in the project
`soleur-infra-app` (D11), and a rotation of the App key updates both.

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

  > **Amended 2026-09-30 (#9262):** `soleur-infra` also serves the two inngest-release App-token
  > consumers above (D2's note), and its committed manifest
  > (`apps/web-platform/infra/github-infra-app-manifest.json`) carries `pull_requests: write` and
  > `actions: write` for them: the pin bump opens and auto-merges a PR, and the auto-mint dispatches
  > the build. Its permissions are therefore **no longer purely derived from the resource types
  > Terraform manages**. The widening applies to **every unscoped token minted from this App**, not
  > only to the two new consumers: that includes the Terraform provider's `app_auth` tokens in every
  > Tier-B root (`apps/web-platform/infra/main.tf`, `infra/github`), which now carry `actions:write`
  > and `pull_requests:write` too. The two new consumers each request a scoped token
  > (`{"contents":"write","pull_requests":"write"}` or `{"actions":"write"}` on `soleur`), and the
  > composite's exact-grant check bounds only them. `actions:write` (dispatch and re-run workflows)
  > and `pull_requests:write` (open, review and merge PRs) are new capabilities, not implied by the
  > `administration:write` or `contents:write` the App already holds. The blast radius is
  > comparable, because `administration:write` already allows ruleset and repository
  > administration. No API changes a live App's permissions, so the widening is #8209 runbook step
  > O4c.
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
| R8 | `GITHUB_APP_WEBHOOK_SECRET` and `GITHUB_CLIENT_SECRET` stay in Doppler `prd`, as branch-reachable as R1's key was. A holder can forge inbound webhook deliveries or act as the App's OAuth client; neither signs an App JWT or mints an installation token. The webhook secret is minted by `random_id.github_webhook_secret` in the Tier-A-readable web-platform state (`github-app.tf`), so moving its Doppler copy closes nothing until its minting moves. | **OPEN — [#9277](https://github.com/jikig-ai/soleur/issues/9277)** (added 2026-09-30, #8609). Move the webhook secret's minting out of the web-platform root, then both names into `soleur-github-app` (D10). Re-evaluate when #8610 lands. |

> **Superseded 2026-09-30 (#8609), as to R1's status:** **OPEN — mechanism merged (D10); closes on
> G1–G4.** The mechanism is D10; the residual closes only when all four gates hold, because two
> branch-to-key chains outlive the merge (the deploy channel and Tier-A writes to `prd`, both in D10's
> residuals):
>
> - **G1** — [#9294](https://github.com/jikig-ai/soleur/issues/9294) closed: the deploy channel
>   (`WEBHOOK_DEPLOY_SECRET` and the CF Access client pair) is out of branch reach and rotated.
> - **G2** — [#9295](https://github.com/jikig-ai/soleur/issues/9295) closed: no branch-nameable token
>   can write `soleur/prd`.
> - **G3** — the live key was born after G1 and G2 closed. If it was not, the runbook's R-step 9
>   (closure rotation) mints one more key and read token, and the previous key gets `401`.
> - **G4** — the existing probes pass: the old key's JWT gets `401`, the App lists exactly one key,
>   and the project lists exactly one token after #8209 O13 (the runbook's R-step 8).
>
> The runbook's §Runtime App key (#8609) holds the gates' evidence commands. See the Amendment log.

### D10 — The runtime App key lives in its own Doppler project, `soleur-github-app`

*Added 2026-09-30 (#8609); see the Amendment log. This is R1's mechanism.*

**The key leaves the `soleur` project.** A new Doppler **project**, `soleur-github-app` (config
`prd`), holds the soleur-ai runtime `GITHUB_APP_PRIVATE_KEY`. A project, not a `prd_*` branch
config, for D3's reason: no `prd` or `prd_*` reader can see it, whatever branch config is added
later (#6167). `GITHUB_APP_ID` stays in `prd`; it is a public identifier. Terraform declares the
project, its `prd` environment and a `prd_retired` branch config
(`apps/web-platform/infra/github-app-runtime-project.tf`) and, as in D3, mints nothing into them.
The census (Guard 6) enforces it.

**Moved and rotated together.** Every copy of the old key was branch-reachable, and Doppler keeps
the value in `prd`'s version history after a delete, so a move alone closes nothing against a copy
already taken. A **new** key is generated straight into the project and never touches `prd`. It is
born only after #8209 O10 and O13 take `DOPPLER_TOKEN_TF`, a workplace token that reads every
project, out of branch reach. The old key is parked in `prd_retired`, which the host's token cannot
read, for the final `401` probe, and is deleted at GitHub last, after both web hosts are proven on
the new one.

**The web host reads it with its own token.** An operator-minted, read-only service token for
`soleur-github-app/prd` is stored only in Tier B, as `GITHUB_APP_RUNTIME_DOPPLER_TOKEN`.
Operator-minted, because a `doppler_service_token` in the web-platform root would land in
Tier-A-readable state (D3). The loader always exports its `TF_VAR_` name and fills it only for the
jobs that opt in, so the `prd_terraform` legacy arm cannot supply it under `--preserve-env` (D6). It
reaches the host as one conditional line of the existing `soleur-doppler-token.tmpl` render; an
empty variable renders byte-identical content. That render feeds cloud-init for fresh hosts and the
`terraform_data.deploy_pipeline_fix` push to the running web-1 (#7095). That push's trigger hashes
the KEYLESS render plus a committed `"github_app_runtime_token_generation=N"` literal, so every plan
context (Tier-A PR plan, the drift job, the push apply, the opted-in applies) computes the same
trigger whether or not it holds the token; delivery, re-delivery and roll-back are each a one-line
PR bumping N. The value never reaches Tier-A-readable state, because the locked `hcloud` provider
(1.63.0) stores `user_data` as a hash and the token travels only in the provisioner's
`environment {}`. A provider bump that drops that hashing invalidates this
paragraph.

**A11's "immutable redeploy" is superseded for web-1** by that Terraform-declared, generation-bumped
credential push, until #6730 gives web-1 an automated replace path. The push shares its source with
cloud-init and is not an SSH or rescue edit, so `hr-prod-host-config-change-immutable-redeploy`
holds. web-2, whose credentials are birth-frozen, gets the line only through an immutable
`web_host_replace` from `main`.

**The key is handed only to images signed from `main`.** The deploy overlays exactly one name:
`ci-deploy.sh` and the boot path download `prd` as before, then fetch `GITHUB_APP_PRIVATE_KEY` from
the isolated project and let it win — only for an image signed by `reusable-release.yml` from a run
whose ref is `refs/heads/main` of `jikig-ai/soleur`. The verifier pins that on the caller's run
(`--certificate-github-workflow-ref=refs/heads/main` and
`--certificate-github-workflow-repository=jikig-ai/soleur`, next to the SAN and issuer), whatever the
global `IMAGE_VERIFY_MODE` (#6129). The SAN alone is not enough: it names the reusable workflow's
ref, which a branch run satisfies by calling `reusable-release.yml@main`; and the identity no longer
admits a `refs/tags/v…` arm. The pin holds on **every hand-off arm**:

- **the deploy** — the digest `verify_image_signature` returned with rc 0, and nothing else, is the
  overlay's verified ref;
- **the local-cache arm** — the reused image is re-verified by its digest, or overlaid with an empty
  ref, which means no key;
- **boot** — the key goes only to the digest `ci-deploy.sh` last verified with the pinned identity,
  recorded 0600 by the `deploy` user on the host's persistent volume
  (`/mnt/data/github-app-key-verified-ref` — `webhook.service` runs `ci-deploy.sh` as `deploy` under
  `ProtectSystem=strict`, so a root-only path is unwritable, and the volume survives a host replace);
  any other image reference boots keyless (`unverified_image`, in Sentry).

The overlay refuses a `prd` env that carries a runtime-hijack name, by **prefix class** rather than
by a list of names: `NODE_*` except `NODE_ENV`, `LD_*`, `GLIBC_*`, `GIT_*` except the app's own
`GIT_(DATA|PROVISION|REMOVE|TRANSPORT)_*` names (six in `prd`; git reads none of those prefixes),
`BASH_*`, `ENV`, `PATH`,
`SHELL`, `HOME`, `TMPDIR`, `SSL_*`, `OPENSSL_*`, `CURL_*`, `*_PROXY`/`*_proxy`,
`NPM_CONFIG_*`/`npm_config_*`, `PYTHON*` and `PERL*`. A collision fails safe: the `prd` key before
eviction, a refused canary after. Before promotion, the canary proves GitHub accepts the key
(`GET /app` returns `slug=soleur-ai` and the expected `id`). The probe runs as an absolute-path node
under `env -i`, which passes only `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`, so a planted `node`
or an environment hook cannot answer for it. The probe is code inside the image under test: `ok`
proves key acceptance for an image whose provenance the pin above already established, and is never
provenance evidence itself. A missing or rejected key leaves the running container serving. Until the
key is evicted from `prd`, a failed or withheld fetch falls back to the still-valid `prd` key, says so
in Sentry, and reports at boot as `github_app_key_ok_fallback`, never as `github_app_key_ok`.

**A key that existed while a branch-reachable path to it was open is treated as taken.** That is why
the old key is rotated rather than moved, and it applies to the new key too: if it was born before
residual R1's gates G1 and G2 closed, the runbook's R-step 9 mints one more key (and read token) and
retires the previous one with a `401` proof.

**Residuals D10 does not close**, recorded so that they are not read as closed:

- **Host, container and unit environment.** The key is in the web container's environment, and the
  token is in the host's credential file — the class today's full-`prd` host token already occupies.
  Eight units load that file; each carries `UnsetEnvironment=GITHUB_APP_DOPPLER_TOKEN` (applied after
  `EnvironmentFile=`), so only `ci-deploy.sh` and the boot download, which parse the file themselves,
  see the token. What remains is host-compromise class.
- **The gate's enforcer is replaceable through the deploy channel.** `/hooks/infra-config`
  authenticates only by the Tier-A HMAC secret and CF Access pair, and can rewrite `ci-deploy.sh` and
  read the host's token. Until that pair leaves branch reach, the host-side gates above are defence in
  depth. **Closure gate G1**, [#9294](https://github.com/jikig-ai/soleur/issues/9294).
- **Tier A can write `prd`.** The prefix-class refusal is defence in depth: a `prd` writer can still
  use a name outside the classes, or change the value of an allowed one. **Closure gate G2**,
  [#9295](https://github.com/jikig-ai/soleur/issues/9295).
- **Signer-side guards.** There is no tag ruleset for `v*`/`web-v*`, and neither `reusable-release.yml`
  nor `web-platform-release.yml`'s `workflow_dispatch` checks its ref before signing. The verifier pin
  makes this hygiene, not a gate, because a signer runs code the branch controls and so cannot be the
  boundary: [#8780](https://github.com/jikig-ai/soleur/issues/8780).
- **Hetzner metadata.** For web hosts born after the token is seeded, it is in `user_data`, which
  the metadata endpoint serves to host processes, so an SSRF in the app could reach it. web-1's
  `user_data` is birth-frozen and never carries it. The web-host drop of `169.254.169.254` is
  [#9278](https://github.com/jikig-ai/soleur/issues/9278); web-2 is not promoted to serving traffic
  until it exists.
- **The branch-reachable deploy channel for every other `prd` secret.** The signed-image condition
  closes that path for this key only; the general fix is #6129.
- **The two opt-in Tier-B jobs carry the token** (not the key): the deploy-pipeline push and the
  web-host create/replace jobs. Same reasoning as A3.
- **`DOPPLER_TOKEN_TF` and workplace administrators** read every project. The birth gate above and
  gate G4 (exactly one project token after O13) bound the first; the second is the
  vendor-side trust every Doppler-held secret already rests on.

The canonical operator sequence is
`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` §Runtime App key
(#8609).

### D11 — The release jobs' App values live in their own Doppler project, `soleur-infra-app`

*Added 2026-10-01 (#9321); see the Amendment log. This decision lands in two changes: the first added the
dormant container, the bootstrap script, census Guard 7 and this text; the second (2026-10-03) switches
the consumers and is built as described below. Sentences about the consumers were written as the target
state; they are now the as-built state of the change that carries this note, and were `adopting` until
a release run proved them (`accepted` 2026-10-04, #9462; Statuses table).*

**What.** Two unattended release jobs, `build-inngest-bootstrap-image.yml::bump-cloud-init-pin` and
`mint-inngest-bootstrap-tag.yml::mint`, need exactly two values to mint the `soleur-infra`
installation token: `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY`. Today both jobs are handed
`DOPPLER_TOKEN_INFRA_PRIVILEGED`, which reads the whole `soleur-infra-privileged/prd` project
*(superseded 2026-10-03, #9321: that was the state before the switch change; the two jobs now hold only
`DOPPLER_TOKEN_INFRA_APP`, see "As built" below)*. A new
Doppler **project**, `soleur-infra-app` (config `prd`), holds a copy of only those two values, and a
read-only service token scoped to it, `release-app-mint`, is stored as the environment secret
`DOPPLER_TOKEN_INFRA_APP` on `infra-privileged` only. In the second change the composite action
`mint-infra-app-token` and both jobs switch to it. The composite has a third caller since the
2026-10-01 (#9360) amendment, `apply-github-infra.yml`, which mints for the marketplace ruleset verify
and stays on the Tier-B token: it already holds that token for Terraform, so narrowing it gains
nothing. The switch therefore cannot repoint the composite's fixed project unconditionally. **As
built (2026-10-03):** the composite gains one optional input, `doppler-project`, whose default is
`soleur-infra-app` and which is validated against exactly `soleur-infra-app` and
`soleur-infra-privileged` before any Doppler call (anything else, an empty value included, is
refused). Both reads carry `--project "$DOPPLER_SOURCE" --config prd` in argv, and the per-run
`app-token` notice gains a `source=<project>/prd` field. The two release jobs pass only
`doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}` and inherit the narrow default (a new caller
that forgets the input also lands on the narrow source); `apply-github-infra.yml` passes
`doppler-project: soleur-infra-privileged` with `DOPPLER_TOKEN_INFRA_PRIVILEGED`, which keeps its
current source. A sibling composite was rejected: it would copy the JWT recipe a third time. Census
row G7f pins which callers may use which shape and the composite's allow-list and reads. The notice's
`source=` field records the project the run **requested** (derived from the validated input), not a value
Doppler attested; the proof that the narrow source served the credentials is G7f's pairing of token and
project and the successful mint with that token (which is what shows the token is bound to
`soleur-infra-app`; the runbook's read-only `verify` stage only lists names and slugs and compares the
copies, it never uses the token). The read token `release-app-mint` is created without an expiry (accepted: it is read-only
on a project holding two values, and it is rotated on demand, with every App key rotation or on suspicion
of exposure).

**A project, not a config.** D3's reason: a branch config resolves its root's secrets, so a token
scoped to one still reads them. A token scoped to the `prd` root config of a separate project reads
nothing else.

**What the broad token reaches, measured.** A read-only names listing of `soleur-infra-privileged/prd`
on 2026-10-01 shows `DOPPLER_TOKEN_TF` (a workplace token that reads and writes every project),
`HCLOUD_TOKEN` (read/write), `CF_API_TOKEN_R2`, both R2 state key pairs, and the three
`GITHUB_INFRA_APP_*` names. `GITHUB_APP_RUNTIME_DOPPLER_TOKEN`, the read token for the soleur-ai
runtime key (D10), is not stored there yet; it arrives with D10's operator sequence. The narrowing
therefore removes more reach than the day D10's token lands, and does not wait for it. **Ordering with
D10:** do not run the runbook's R-step 2 (which stores that token in Tier B) before the switch change
has merged; until then both release jobs still hold the broad token and would read it. *(Dated
2026-10-03: this gate is satisfied once the switch change merges; the two release jobs then hold only
`DOPPLER_TOKEN_INFRA_APP`.)*

**Terraform creates the containers only.** `apps/web-platform/infra/infra-app-project.tf` declares the
project and its `prd` environment, and no `doppler_secret`, `doppler_service_token`, data source,
variable or output, for D3's reason: this root's state is readable by the Tier-A backend keys. The two
values and the token are put there by an operator-run, re-runnable script
(`knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh`), which is
the part Terraform cannot hold. The script is permanent for this feature: it is also the rotation tool
(`--rotate-token`, and a re-run after an App key rotation), so it stays at that path. Census Guard 7
enforces the container half (G7c: no stateful `doppler_*` resource on the project through any alias of
it; G7e: no `${soleur-infra-app.` cross-project reference) and the token half (G7d: no CI mint, and the
script stores the token only with `gh secret set --env infra-privileged`). It is a census of spelled
patterns, not a proof over every spelling; its header says what it does not cover.

**The cost is a second copy of the infra App private key.** The two values cannot move: the Terraform
roots read them whole from the Tier-B project through the infra-credentials loader. Mitigation: GitHub
Apps accept several private keys at once, so a rotation adds the new App key, updates both copies (the
script's copy stage), proves both with `GET /app`, and only then deletes the old key at GitHub. A copy
that is stale anyway fails closed at the next release run, with a stage-named error and the existing
Slack post, before any tag, push or pull request. That run may be days later; the residual is accepted
and stated. Who can read the new project is Doppler's own access model: workplace administrators and
`DOPPLER_TOKEN_TF` read it, exactly as they read the original. The script does not enumerate project
members, webhooks or syncs (the CLI has no read for them); compare the new project's members with
`soleur-infra-privileged`'s before running it.

**The honest boundary.** The narrowing is least privilege by reference. GitHub passes a secret to a
job only when the workflow names it ("GitHub Actions can only read a secret if you explicitly include the
secret in a workflow", docs.github.com/en/actions/concepts/security/secrets), so a compromised step in
these two jobs cannot read a secret the jobs no longer name. It does not hold against a step with
runner root, which can harvest referenced secrets from memory (docs.github.com/en/actions/concepts/
security/compromised-runners). It is also narrower than "the key is no longer Tier-B-equivalent":
the `soleur-infra` App keeps `administration:write`, `environments:write` and `secrets:write` (committed
manifest), and residual R1 records that `administration:write` lets a holder rewrite an
environment's deployment-branch policy, the very policy the main-only boundary rests on. What the change removes is the release jobs' direct reach to
`DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN` and the other Tier-B names, not the reach of whoever holds the App
key. It is not a boundary against a change merged to `main`, which can name any secret of the
environment: the `main`-only deployment policy remains that boundary, and it stays nominal while
residual R1 is open. The structural follow-up is a release-scoped App (contents, pull requests and
actions only) in place of the full-grant `soleur-infra` App for these two jobs; it is not part of this
decision.

**Rejected here.** A separate fifth GitHub environment for the two jobs (the jobs run `main`'s YAML,
so it adds no property and adds a policy resource and census churn). A cross-project Doppler
reference to avoid the second copy (unmeasured, not refuted: its resolution behaviour could not be
probed without a write, and it would put a reader-resolved reference to the key into another project;
revisit it with a scratch-config measurement). A Terraform-minted token (it would sit in
Tier-A-readable state). A fallback to the broad token in the composite (it keeps the broad token
reachable and cannot serve two projects with fixed argv). A `main`-dispatched workflow that does the
copy, mint and store (it would need `DOPPLER_TOKEN_TF`-class authority in a job any `main` writer can
trigger, re-creating the reach D11 removes).

**Landing order.** Two changes (the second is the 2026-10-03 amendment), because one cannot be made safe without an availability outage: the
credential can only be minted after the containers exist, and the release jobs run `main`'s YAML the
moment the switch merges. The first change is dormant; the operator runs the script; the second change is
opened after the script prints `SOLEUR_BOOTSTRAP_READY_FOR_PR2`. The runbook's §Release-job App source
(#9321) is the canonical sequence. **Rollback:** reverting the second change restores the broad token;
then (in this order: revert, prove a release run green on the broad token, only then revoke; the
runbook's Rollback is the canonical sequence) revoke the `release-app-mint` token, delete the
`DOPPLER_TOKEN_INFRA_APP` environment secret and delete the two copies, because a live credential with no
consumer is exposure with no purpose. If #8609 R-step 2 has already run, the revert re-opens the D10 gate
on `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` (both release jobs would again hold the whole project), so fix forward
instead.

## Statuses

| Decision | Status | Flips when |
|---|---|---|
| D1 tiers | `adopting` | AC12–AC16 pass: the three names are absent from `prd_terraform`, the App key there hashes equal to the sentinel, and the per-credential invalidation probes return `401`/verify-failure. |
| D2 boundary | `proposed` | **R1 (#8609) closes** (and R7 closes at O5b). Until then the boundary is nominal against a `prd` repo-secret holder. This is the CPO sign-off condition. |
| D3 carrier | `adopting` | The Tier-B project is populated and its read token is seeded on all four environments, and the canary reads `source=tier_b`. |
| D4 Tier-A substitutes | `adopting` | The read-only Hetzner token returns `token_readonly` on a write, and the Tier-A state pair returns `403` on a put and `200` on a get. |
| D5 GitHub identity | `adopting` | The infra App's write scopes are exercised by a green no-op apply-on-merge from `main`, and board sync runs with no legacy warning. **Amended 2026-09-30 (#9262):** and O4c's evidence (#9262 plan AC15): one `main`-dispatched build whose `bump-cloud-init-pin` job is green under `infra-privileged` with the `app-token` notice naming `app=soleur-infra`. D5 cannot reach `accepted` until the new scopes have been exercised. **Amended 2026-10-01 (#9360):** and the marketplace bypass-actor follow-up (#9361) has landed, with a manifest write exercised as soleur-infra. |
| D6 integrity | `adopting` | The loader's sentinel row and Guard 2 are green on the PR, and a planted same-named `prd_terraform` value is measured to have no effect. |
| D7 state custody | `adopting` | The privileged bucket's object matches the source by sha256, lineage and serial; a Tier-A key gets `403` on it; the two custody forgets have applied. |
| D8 census | `adopting` | Every mutation row of the Guard Contract is measured RED, and the suite is green on the PR head. |
| D9 residuals | Standing constraints | Not accepted. Each is discharged by the issue named with it. |
| D10 runtime App key | `adopting` | Residual R1's gates G1–G4 hold (see the blockquote under the D9 table): #9294 and #9295 closed; the live key born after both closures, or rotated by the runbook's R-step 9 with the previous key at `401`; and the runbook's R-steps 7 and 8 pass — the old key's JWT gets `401`, both web hosts report the isolated key, the App lists exactly one key, and the project lists exactly one token after #8209 O13. Flips to `accepted` with D2, in PR-B, which is not opened until G1–G3 are evidenced with links. |
| D11 release-job App source | `accepted` | The first change (container, bootstrap script, census Guard 7) is merged and its bootstrap has run; the switch change (2026-10-03) moved D11 to `adopting`. It flipped to `accepted` on 2026-10-04 (#9462): a `main`-dispatched build run at or after the switch merge (run 37222544138) was green through `Verify DOPPLER_TOKEN_INFRA_APP present` and the mint, and its `app-token` notice carried `source=soleur-infra-app/prd` (the notice's `source=` field is the discriminator between the narrow and the broad source). That run exercises the build job's caller only; the mint job's credential steps run only when its `Decide` step returns `would-mint`, and `apply-github-infra.yml` is unchanged in source and token, so `accepted` is claimed on the build-job proof plus the static suites (the two release suites, the shape suite, census G7f) for the others. |

> **Superseded 2026-09-30 (#8609), as to D2's row:** D2 flips when **residual R1 closes (G1–G4)**
> and residual R7 closes at #8209 O5b. "R7" in D2's row is the residual (the state key), not the
> runbook's R-step 7. D2 and D10 flip together, in PR-B.

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
| A11 | Evict the soleur-ai runtime key from `prd` in this change | Needs runtime and host bootstrap changes (hash-bound cloud-init, immutable redeploy). Deferred as R1 (#8609) — and R1 is why D2 is not `accepted`. **Superseded by D10** (2026-09-30, #8609). |
| A12 | A `tier` variable plus an apply-refusing precondition in HCL | Terraform cannot tell a plan from an apply in configuration. A token-mode run that tried to write would fail anyway: the PR `GITHUB_TOKEN` is read-only and the Doppler and R2 placeholders are rejected by the vendor APIs. No property needs it. |

## Amendment log

### 2026-09-30 (#8609): D10 — the runtime App key moves to its own project

R1's mechanism lands. The PR carries `Ref #8609`; the key itself moves only through the operator
sequence in the runbook's §Runtime App key (#8609), which is the canonical copy.

- **D10 added, `adopting`.** The decision, its supersession of A11 for web-1 and its residuals are
  in D10 above.
- **R1 → OPEN — mechanism merged (D10); closes on G1–G4.** The 2026-09-22 cell stays verbatim; the
  new status is the `Superseded 2026-09-30` blockquote under the D9 table. It is OPEN, not closing,
  while two branch-to-key chains exist: the deploy channel (G1, #9294) and Tier-A writes to `prd`
  (G2, #9295). G3 is the closure rotation (runbook
  R-step 9) and G4 the existing probes (runbook R-step 8).
- **D1 census amendment.** `WEBHOOK_DEPLOY_SECRET` and the CF Access client pair are reclassified
  Tier B (blockquote under D1); their eviction and rotation is #9294. A tier classification change,
  not a new ADR.
- **D10 residuals added:** the deploy channel can replace the gate's enforcer (G1, #9294); Tier A can
  write `prd` (G2, #9295); no signer-side or tag guards (hygiene, #8780). The host unit-environment
  residual records the `UnsetEnvironment=GITHUB_APP_DOPPLER_TOKEN` narrowing this PR applies.
- **R8 added** (webhook and client secrets, #9277), because moving their Doppler copies closes
  nothing until the webhook secret's minting moves.
- **A11 annotated, not rewritten.** It records the deferral as it was decided.
- **D2 stays `proposed`.** D2 and D10 flip to `accepted` in the follow-up PR (PR-B) that closes
  #8609, after the runbook's R-steps 7 and 8 pass and gates G1–G4 hold. PR-B is not opened until
  G1–G3 are evidenced with links (the two issue closures, and the live key's birth time against their
  closure times). That PR also records the #8209 limb of ADR-220 D2–D3, naming it "ADR-241 D2
  `accepted`" (residual R1 **and** residual R7), never by runbook R-step labels.
- **Labels.** In this ADR, R1–R8 are residuals. The runbook's steps are written "R-step N"
  (R-step 7 is the GitHub key delete); an unqualified "R7" here always means the residual.

Plan: `knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md`.

### 2026-09-30 (#9262): the inngest-release App-token consumers move to Tier B

The pin bump (`build-inngest-bootstrap-image.yml::bump-cloud-init-pin`) and the auto-mint
(`mint-inngest-bootstrap-tag.yml::mint`) minted the `soleur-ai` App token from `soleur/prd_terraform`
through a repository secret, with no `environment:`. O10's sentinel would have failed both, so O10
was held on them. They now declare `environment: infra-privileged` and mint the `soleur-infra` App
token from `soleur-infra-privileged/prd` (ADR-232, amended the same day) *(superseded 2026-10-03, #9321:
they now mint from `soleur-infra-app/prd` by default; see the 2026-10-03 entry below)*. The dated notes in D2 and
D5 and the D5 Statuses row carry the decision text.

- **Census:** G4e's floor moves from 4 to 3, because the renamed composite no longer reads
  `GITHUB_APP_PRIVATE_KEY`. G1b/G1c pick up both jobs through their reference to
  `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`; no row is added. *(Superseded 2026-10-03, #9321: they pick
  the jobs up through `secrets.DOPPLER_TOKEN_INFRA_APP`, an `ENV_SECRETS` member.)*
- **Runbook:** the new step O4c (widen the live App and prove the consumers on Tier B) precedes O10;
  the chain is #9262 merge → O4c → O10 → O13's `DOPPLER_TOKEN_TF` rotation → #8609 R-step 1
  (the runbook's §Runtime App key gates R-step 1 on both).
- **Exposure, stated plainly:** both jobs hold `DOPPLER_TOKEN_INFRA_PRIVILEGED`, which reads the
  **whole** Tier-B project. Since #8609 PR-A (#9263) that project also holds
  `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` (D10), so these two unattended jobs can read the path to the
  soleur-ai runtime key without naming it. They share that reach with every other Tier-B job, and
  it is bounded by the `main`-only policy, which stays nominal until residual R1 closes. The
  structural fix is a narrower Doppler source holding only the two `GITHUB_INFRA_APP_*` names,
  recorded as a deferral in the #9262 plan. *(Superseded 2026-10-03, #9321: the exposure described in
  this bullet is removed for these two jobs; the narrower source is adopted, see the 2026-10-03 entry
  below. Everything above in this bullet is the state as of 2026-09-30.)*
- No decision's status changes here.

Plan: `knowledge-base/project/plans/archive/20261004-100500-2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md`.

### 2026-10-01 (#9360): apply-github-infra and entrypoint_audit leave the soleur-ai key

O10 replaced `GITHUB_APP_PRIVATE_KEY` in `soleur/prd_terraform` with the `EVICTED_SEE_ADR_241`
sentinel. `apply-github-infra.yml` still fetched the soleur-ai pair from that config for its
post-apply verify, so every ruleset apply failed with `verdict=legacy_app_key_evicted`
(run 36839787788). Its Terraform already ran as soleur-infra through the loader; only the fetch and
the verify's inline mint used the evicted key.

- **Apply path:** no step consumes the soleur-ai pair (the tf-var layer still injects the sentinel,
  inert under infra mode). The marketplace verify's token comes from
  `.github/actions/mint-infra-app-token` (`administration:write` on `soleur-marketplace` only: that
  ruleset's `bypass_actors` are returned only to a writer); the two `soleur` ruleset probes need
  Metadata read and use the job's `github.token`. The mint runs **before** Terraform, after a check
  that refuses a loader on its legacy arm or with a different installation id. A final `always()`
  step revokes the token. Shape pins: `tests/scripts/test-apply-github-infra-mint-shape.sh`.
- **`apply-web-platform-infra.yml::entrypoint_audit`:** posts with the job's own `github.token`
  (`issues: write`), because soleur-infra holds no `issues` permission.
- **Census:** G4e moves from a floor of 3 to an exact 1 read (board-status-sync's legacy arm). It
  gains a tier clause: no read may sit in a job that can resolve to a Tier-B environment, including
  a composite through its callers. The row counts `doppler secrets get` fetches only; `doppler run`
  injection of `prd_terraform` is out of its scope and inert, as above.
- **Known gap:** the `soleur-marketplace` ruleset's App bypass actor is still soleur-ai (3261325), so a
  manifest write made as soleur-infra is refused (409, repository rule violations). Swapping the
  actor is a production ruleset write, tracked as #9361. It also narrows D9 residual R1: the
  soleur-ai runtime key loses its ruleset-bypass listing on the marketplace.
- **Pre-existing, unchanged here:** the tf-var `doppler run` over `prd_terraform` still lets a value
  planted there (`ACTIONS_INTEGRATION_ID`, `CODEQL_INTEGRATION_ID`, `GH_OWNER`, `GH_REPO`) rebind the
  required checks in place; tracked as #9362.
- **D5 evidence, by limb:** O4c is done (an O10 precondition). Board sync is green on 2026-10-01 with
  `source=soleur-board` and no legacy warning (runs 36853754168, 36858491319). The apply has only a
  *dispatched no-op* (#9360 plan AC12, not the #8209 plan's AC12-AC16), not an apply-on-merge; the
  run will be recorded on #8209 after merge. The D5 Statuses row gains one dated condition.
- No decision's status changes here.

Plan: `knowledge-base/project/plans/archive/20261001-161547-2026-10-01-fix-retier-apply-github-infra-app-identity-plan.md`.

### 2026-10-01 (#9321): D11 — the release jobs' App values move to their own project

The two release jobs named in the 2026-09-30 entry above stop holding the whole-project Tier-B token.
This record is the first of two changes: it adds the dormant container, the bootstrap script, census
Guard 7 and this decision. It carries `Ref #9321`, not a closing keyword, because the credential is
not narrowed until the second change (the switch) merges; that one carries the close.
*(Marker, 2026-10-03, #9321: "dormant" and "the first of two changes" describe the state on 2026-10-01. The
switch has merged, so the container is no longer dormant, and this record is the first of the two changes
now that the second is the 2026-10-03 entry below.)*

- **D11 added, `proposed`.** The decision, its measured reach, its cost and its boundary are in D11; its consumer half is not implemented by this change.
- **Census:** `DOPPLER_TOKEN_INFRA_APP` joins `ENV_SECRETS` (any job naming it must declare a main-only
  Tier-B environment); Guard 7 adds G7c, G7d and G7e.
- **The 2026-09-30 entry's "structural fix is a narrower Doppler source" sentence stays as written.** It
  records the deferral as it was decided; the dated marker that it is now adopted lands with the switch.
  *(Marker, 2026-10-03, #9321: it is now adopted. The marker sits inline on that sentence in the 2026-09-30
  entry, and the 2026-10-03 entry below lists what it supersedes.)*
- No other decision's status changes here.

Plan: `knowledge-base/project/plans/2026-10-01-security-scoped-doppler-source-for-app-token-release-jobs-plan.md`.

### 2026-10-02 (#8211): `RESEND_API_KEY` is Tier A

- **D1 census, one line.** The repo secret `RESEND_API_KEY` is **Tier A**: it can send a notification
  email through `./.github/actions/notify-ops-email` and nothing else. It reads no other tier, writes
  no infrastructure and reaches no third-party installation, so its disclosure is bounded to spam from
  the ops sender. The census previously named it nowhere; it is already bound by Tier A and Tier B
  jobs (`apply-git-data-root-key.yml`, `infra-validation.yml`).
- **Consequence for the cutover workflow.** `git-data-cutover.yml` gains a `notify-failure` job with
  **no `environment:`** that binds only this secret (plus the job's own `GITHUB_TOKEN` with
  `issues: write`). It never holds a `prd` or git-data credential; the census suite pins that
  (Guard 2 rows 4 and 5 in the #8211 plan). No other decision's status changes here.

Plan: `knowledge-base/project/plans/archive/20261003-090828-2026-10-02-feat-git-data-cutover-residual-real-mode-gaps-plan.md`.

### 2026-10-03 (#9321): D11 — the switch; the release jobs read the narrow source

The second of the two D11 changes. The composite `mint-infra-app-token` reads the App id and key from
`soleur-infra-app/prd` by default, the two release jobs pass `DOPPLER_TOKEN_INFRA_APP`, and the third
caller keeps its source through one explicit, validated input. D11's text is amended in place (what
was built, the Ordering-with-D10 note, the landing order) and D11 moves to `adopting`.

- **As built:** D11's "As built (2026-10-03)" paragraph is the single statement of the composite input,
  the two release callers, the explicit third caller and census row G7f with the per-suite
  `no-broad-tier-b` rows; this entry does not restate it.
- **Statements this amendment supersedes** (each also carries an inline dated marker at its own site), all of
  which named the broad token as the release jobs' composite source. In the 2026-09-30 inngest-release re-tier
  entry: "mint the `soleur-infra` App token from `soleur-infra-privileged/prd`"; "G1b/G1c pick up both jobs
  through their reference to `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`"; and the Exposure bullet ("both jobs hold
  `DOPPLER_TOKEN_INFRA_PRIVILEGED`" and its closing sentence that the narrower source is a recorded deferral).
  The two jobs now hold only the narrow token, G1b/G1c pick them up through `DOPPLER_TOKEN_INFRA_APP` (an
  `ENV_SECRETS` member), and the deferral is adopted here. In the 2026-10-01 first-change entry above:
  "dormant", "the first of two changes", and the sentence that the dated marker lands with the switch. In D11:
  "Today both jobs are handed `DOPPLER_TOKEN_INFRA_PRIVILEGED`" (it describes the state before this change).
  The 2026-10-01 marketplace-verify entry's statement that its token comes from the composite stays true:
  that caller names the broad project explicitly.
- **Unchanged:** the App's own grant, the second copy of the App key and its rotation order, the boundary
  statement (least privilege by reference under a main-only policy), and the loader.
- D11 moves to `adopting`; no other decision's status changes here.

Plan: `knowledge-base/project/plans/archive/20261004-015859-2026-10-03-security-switch-app-token-release-jobs-to-infra-app-doppler-token-plan.md`.

### 2026-10-04 (#9462): D11 — `accepted` on a real release run

The runbook's step-5 proof was dispatched from `main` (`build-inngest-bootstrap-image.yml`, `mirror_only=true`,
tag `vinngest-v1.1.44`), run 37222544138. Measured on that run: it concluded `success`; its `headSha`
(`fa8bc5961f`) descends from the switch merge `bbf95a3f19`; step `Verify DOPPLER_TOKEN_INFRA_APP present`
concluded `success`; and the rendered `##[notice]app=soleur-infra` lines carry exactly one source,
`source=soleur-infra-app/prd`. The mint with the narrow token succeeded, which is what shows the token is bound
to `soleur-infra-app`. The `verify` stage's live checks pass (the environment secret is listed, the repository
level does not list it, `soleur-infra-app/prd` holds exactly one token, `release-app-mint`, and both copies equal
their sources).

- **One `verify` check reads red for a bookkeeping reason, not a live one:** "the recorded slug is the live token
  and was stored". It compares the token's slug with the `TOKEN_SLUG` and `TOKEN_STORED` lines in the script's
  gitignored `.env`, which lived in the worktree of the original bootstrap run and was removed with it. Nothing
  live disagrees. The record is re-created by the next `--stage mint-and-store-token` (a rotation), so no write
  was made to restore it, and the stage's `SOLEUR_BOOTSTRAP_READY_FOR_PR2` line is not claimed as re-observed here.
- **Not proven by this run, and unchanged:** the `mint` job's caller (its credential steps run only when `Decide`
  returns `would-mint`; the next real auto-mint's notice carries the same `source=` field).
- D11 moves to `accepted`; no other decision's status changes here.

### 2026-10-04 (#9377): D2 — a dispatched, read-only escrow diagnostic joins `infra-privileged`

`.github/workflows/web-host-escrow-diagnose.yml` is dispatch-only, `permissions: contents: read`, with one job on
`infra-privileged`. It loads credentials through the loader with only `doppler-token-infra-privileged` and runs
`scripts/web-host-escrow-preflight.sh`, so an agent can ask whether web-host escrow is ready before it starts a
birth, with no human step. It lists Doppler secret NAMES, writes a scrubbed verdict to the job summary and, with the run
context (commit, dispatcher, UTC time), to the run log, and changes nothing. A green run is necessary, not sufficient: names cannot tell a bucket-scoped R2 pair from web-1's pair
pasted under new names.

- **Where its token comes from.** No environment secret on `infra-privileged` reads both Doppler configs the check lists
  (`prd` and `prd_workspaces_luks_web`): `DOPPLER_TOKEN_INFRA_PRIVILEGED` reads only the carrier project, and
  `DOPPLER_TOKEN_INFRA_APP` only the App project. The working route is the loader's Tier-B export of `DOPPLER_TOKEN_TF` (the
  workplace personal token, held in the carrier project) as `TF_VAR_doppler_token_tf`. Nothing is minted. The preflight's own
  fallback, a read of `DOPPLER_TOKEN_TF` from `soleur/prd_terraform`, is dead since step O10 evicted that name. Not verifiable
  before the first dispatch: that step O2 seeded the carrier with the token, and that the O13 rotation left a valid value
  there. A loader failure with no summary, a NO TOKEN verdict or an UNREADABLE one is how that shows.
- **The residual, at full strength.** (a) The job holds the workplace personal token, which reads and writes every Doppler
  project, and the whole Tier-B set the loader exports beside it. "Read-only" is a property of the workflow's steps, not of the
  token. (b) Anyone who can merge to `main` can change what this no-reviewer job does, and no ruleset on this repository requires a
  pull-request review or a code-owner approval today (the CODEOWNERS header calls enforcement an admin follow-up). The bound is
  the main-only branch policy, which this ADR itself calls nominal until residual R1 closes. (c) Anyone with repository write
  access can dispatch the job, as they can every other workflow on this environment (all nine others carry
  `workflow_dispatch`), and can re-run any retained run of it for 30 days: GitHub re-runs a run at its original commit, so the
  `main` policy passes and today's Tier-B secrets run whatever step text existed then, including a leaky intermediate version
  that was merged and later reverted. There is no `concurrency:` group, so a burst of dispatches costs runner minutes and
  Doppler read calls on the one workplace token the apply jobs also use; it fails closed. (d) `::add-mask::` does not apply
  inside the job summary, and summaries on a public repository are world-readable, so the explicit token-shape redaction and
  the output prefix filter in the step are the only controls there; the full checker output, redacted only by the two `sed`
  expressions, also goes to the public run log. The step also drops every exported variable and exported function with a valid
  name but a short allowlist before the check runs; that is hygiene against accidental inheritance, not a boundary (the parent
  step shell keeps its environment readable at `/proc/$PPID/environ`, and a readonly exported variable such as `SHELLOPTS`
  survives the unset). The suite's command allow-list is consistency, not integrity: one pull request can change the workflow
  and the suite together, and no review is required to merge it.
- **Reconciliation with D11's rejected alternative.** D11 rejected "a `main`-dispatched workflow that does the copy, mint and
  store (it would need `DOPPLER_TOKEN_TF`-class authority in a job any `main` writer can trigger, re-creating the reach D11
  removes)". D11 removed that reach from the two release jobs. `infra-privileged` already hosts jobs that hold it (apply-on-merge,
  the drift check, the dispatched forget and teardown); this job is one more consumer of the same class and adds no new reach,
  and dispatchability is not new either (the residual above). It is accepted because the alternative is a person reading a
  stale runbook command.
- **Deferred, by decision, with its trigger.** A narrower credential (a D11-style project that holds only a names-read token) is
  tracked by #9461 and stays open for the birth and replace jobs. A scheduled or Inngest-dispatched escrow check is not built:
  the drift check has no `schedule:` trigger either (an Inngest function dispatches it), so a scheduled run would need a TypeScript
  function, an allowlist entry and a monitor, for early warning of drift between births only. Revisit it when births become
  frequent, or when escrow drift is observed between two births.
- No decision's status changes here; D2 stays `proposed`.

Plan: `knowledge-base/project/plans/archive/20261004-155440-2026-10-04-chore-web-host-escrow-readiness-diagnostic-workflow-plan.md`. Shape suite:
`plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh`.

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
- D10 (2026-09-30): #8609, #9277, #9278, #6730, #6129, #7095, #9294 (G1), #9295 (G2), #8780
- D2/D5 amendment (2026-09-30): #9262; ADR-232 (amended the same day)
- D5 apply-path note (2026-10-01): #9360, #9361, #9362
- D11 (2026-10-01, switch 2026-10-03): #9321
- D2 note (2026-10-04): #9377, #9461
