# --- #7159: the project-scoped Doppler read identity for the token-drift scan ----------------
#
# The twice-daily Cloudflare-token-drift scan (`.github/workflows/scheduled-terraform-drift.yml`
# + `scripts/check-cloudflare-token-drift.sh`) has to read token-shaped keys across EVERY Doppler
# config in the `soleur` project, not one. A `doppler_service_token` cannot do that: it is
# CONFIG-scoped, enumerates exactly ONE config and ignores `DOPPLER_CONFIG`. Measured 2026-08-02
# with an ephemeral prd-ROOT read token: `doppler configs -p soleur` returned `['prd']` and
# `GET /v3/environments?project=soleur` returned `[]` — both with `success: true`, i.e. a list
# silently scoped to the caller rather than an error, which is why the shortfall was invisible.
#
# A `doppler_service_account` holding a PROJECT MEMBERSHIP is a different resource class and is
# NOT config-scoped. That is the shape this file mints. #7159's option-table premise "there is no
# single project-scoped read token to mint" is FALSIFIED for this class — true of
# `doppler_service_token`, false of `doppler_service_account` in the pinned DopplerHQ/doppler
# v1.21.2 (`.terraform.lock.hcl`). ADR-160 records that, the census behind it, and the
# gate-versus-report split the coverage ladder rests on.
#
# FOUR RESOURCES, ONE CREDENTIAL: the account (the identity), the project membership (the GRANT),
# the token (the secret value) and the repo Actions secret (the sink the workflow reads as
# `secrets.DOPPLER_TOKEN_DRIFT`). Exactly ONE consumer — the `token_drift` step. The rung-2
# rehearsal orphan sweep in the same workflow is deliberately NOT wired to it.
#
# autonomy-considered: provider-mint-applied (Doppler service account + membership + token and
# the GitHub repo secret, all minted in-band by the Terraform GitHub App and `DOPPLER_TOKEN_TF`;
# there is no operator credential-entry step at any point).
#
# ROTATION, AND EMERGENCY REVOCATION:
#   terraform apply -replace=doppler_service_account_token.token_drift
# mints a fresh `api_key`, invalidates the old one and republishes the Actions secret in a SINGLE
# apply. To strip REACH without touching the token, remove the
# `doppler_project_member_service_account` resource — the identity survives, the grant does not,
# and the next scan reports `coverage: degraded` at `0/13`.
#
# NO `lifecycle` BLOCK AND NO `ignore_changes` ON `plaintext_value` ANYWHERE IN THIS FILE, AND
# THAT IS DELIBERATE. With one, a `-replace=` rotation would mint a new value that never reached
# `DOPPLER_TOKEN_DRIFT`, and the scan would keep presenting a revoked credential while the apply
# read green. Mirrors `kb-drift.tf` and `doppler-write-token.tf`, which omit it for the same
# reason.
#
# NO `expires_at` ON THE TOKEN, AND THAT IS ALSO A DECISION. The attribute is optional and the
# sibling service tokens in this root do not expire. An expiry would fail the scan CLOSED twice
# daily with no in-band re-mint path: the only remedy is an infra apply behind the
# `web-platform-infra-apply` environment gate, which converts a routine credential lifetime into
# a gated action. It buys no detection this design lacks either — a dead credential surfaces as
# `coverage: degraded` within 12 hours either way — and on-demand rotation is already the
# `-replace=` above.
#
# STATE STORAGE: the token's `api_key` is Computed + Sensitive + write-once (the provider cannot
# re-read it after create), so the cleartext value lands in `terraform.tfstate` on the R2 backend
# (`soleur-terraform-state`; server-side encrypted, TLS-only — see `main.tf`), the same posture
# five sibling token keys already have. State loss is unrecoverable; recovery is the same
# `-replace=`, which mints a new token and ORPHANS the old one (still valid until revoked
# Doppler-side).
#
# PUBLICATION: `DOPPLER_TOKEN_DRIFT` is a REPOSITORY-level Actions secret, readable by every
# workflow in the repo. That is not a preference — the Terraform GitHub App cannot write
# ENVIRONMENT-scoped secrets (403; see `doppler_token_inngest_arm`'s comment for the precedent),
# so every sibling `github_actions_secret` in this root is repo-scoped too. The governing control
# is who can merge under `.github/workflows/`, which `CODEOWNERS` pins to the operator.
#
# ⚠️ BLAST RADIUS — THIS IS A WIDENING, AND SAYING OTHERWISE WOULD BE FALSE.
# This credential is PROJECT-scoped, so its reach is the WHOLE `soleur` project: 4 environments
# and 13 configs — the 7 `prd*` configs, the 3 `dev*` configs, `ci`, and the 2 `cli*` configs.
# That is strictly WIDER than the pre-existing `DOPPLER_TOKEN_PRD`, which is prd-ROOT scoped, and
# wider than the "whole prd tree" #7159 accepted. The operator was shown the 2026-08-02 census
# and the 2026-08-03 probes and chose this shape on 2026-08-03: an accepted, disclosed trade-off,
# recorded here rather than buried. Prior art for this exact class, cited rather than re-derived:
#   knowledge-base/project/learnings/security-issues/
#     2026-07-07-doppler-branch-config-does-not-isolate-secrets.md  (severity: high)
#   #6122 fixed zot by moving to a SEPARATE Doppler project; #6167 audits the rest.
#
# WHAT THE REACH RESOLVES TO — all of these live in `prd` ROOT and are reachable today:
#   (a) GHCR_MINTER_DOPPLER_TOKEN (`ghcr-minter-doppler-token.tf`), whose value is the
#       `ghcr_minter` service token, declared `access = "read/write"` — so this READ credential
#       reads a Doppler WRITE credential;
#   (b) GITHUB_APP_PRIVATE_KEY / GITHUB_APP_ID / GITHUB_APP_WEBHOOK_SECRET (`github-app.tf`) for
#       the same App the Terraform provider authenticates with (`main.tf`), which holds
#       `secrets:write` — so it yields an installation token that can rewrite every repository
#       Actions secret, INCLUDING DOPPLER_TOKEN_DRIFT itself;
#   (c) SUPABASE_SERVICE_ROLE_KEY (bypass-RLS read of all user data), PROXY_TLS_KEY, the three
#       git transport/provision/remove SSH private keys, the zot push token, and the Inngest
#       signing / event / manual-trigger keys.
# NEW AT THIS SHAPE: the same reach now also covers `dev`, `dev_personal`, `dev_scheduled`, `ci`,
# `cli` and `cli_ops`. Materially, this credential is equivalent to Doppler WRITE on prd and to
# GitHub App administration of the repository, and it reads every non-prd config as well.
#
# ROLE HONESTY. `viewer` is the LEAST-privileged role that can read secret VALUES: verified via
# `GET /v3/projects/roles` (2026-08-03) it carries `enclave_project_config_secrets_read` and does
# NOT carry `enclave_project_config_secrets_write`; the only lower role, `no_access`, has zero
# permissions. But `viewer` is not purely read-only — it also carries
# `enclave_project_config_dynamic_secrets_leases_write` (a WRITE verb: it can create
# dynamic-secret leases), `enclave_project_config_dynamic_secrets_read`,
# `enclave_project_config_rotated_secrets_read` and `enclave_config_logs`. Disclosed, not elided.
#
# WHAT STILL BOUNDS IT, each verified rather than assumed:
#   (1) no workplace role, and an EMPTY workplace-permission list on the account (the pinned
#       provider requires exactly one of the pair — see the resource comment), so the project
#       membership is the ONLY grant and the identity cannot reach any other Doppler project;
#   (2) the role cannot write secret VALUES (roles probe above);
#   (3) it is Terraform-managed and rotates in a single apply, which `DOPPLER_TOKEN_PRD` is not;
#   (4) the detector reads only TOKEN-SHAPED keys (`CF_API_TOKEN*`, `*_ACCESS_TOKEN_ID/_SECRET`),
#       so what transits the runner is bounded to 50 scannable key occurrences across the 13
#       configs (2026-08-03 census), not every secret in the project.
# OPERATIONAL OBLIGATION: an incident response must revoke BOTH this credential AND
# `DOPPLER_TOKEN_PRD`. Only this one is Terraform-managed.
#
# APPLY PATH: all four addresses ride the DEFAULT per-merge `-target=` allow-list in
# `apply-web-platform-infra.yml`, and no dispatch-job set. The MEMBERSHIP leg is the load-bearing
# one: without it the account and the token are created and published with NO project grant. That
# state is fail-loud at run time (`coverage: degraded` at `0/13`) but it must be unreachable, not
# merely detectable — hence both the fourth allow-list leg and the explicit `depends_on` below.

# The identity. It holds nothing on its own; the membership below is what gives it reach.
resource "doppler_service_account" "token_drift" {
  name = "token-drift-ci-tf"

  # `workplace_role` is deliberately unset. A workplace role grants reach across EVERY Doppler
  # project in the workplace, and the project membership below must be this identity's ONLY
  # grant. This is a design statement, not an omission — do not "fix" it.
  #
  # `workplace_permissions` CANNOT be deliberately unset alongside it, and the empty list below
  # is what that intent compiles to. The pinned provider (DopplerHQ/doppler v1.21.2) enforces
  # EXACTLY ONE of the pair: with neither set, `terraform validate` fails "one of
  # `workplace_permissions,workplace_role` must be specified"; with both set, it fails "Invalid
  # combination of arguments". Both were probed against the pinned binary on 2026-08-03. An
  # EMPTY list is the least-privileged satisfying value — zero workplace-wide permissions,
  # needing no role-vocabulary assumption — so the project membership below remains this
  # identity's only grant, exactly as designed. Do NOT add an entry here.
  workplace_permissions = []
}

# The GRANT, and the only one. `viewer` is the least-privileged role that can read secret VALUES
# (see ROLE HONESTY in the header); `no_access`, the only lower role, reads nothing at all.
# Downgrading or deleting this resource is narrowing N1 — the scan then reports `0/13`.
resource "doppler_project_member_service_account" "token_drift" {
  project              = "soleur"
  role                 = "viewer"
  service_account_slug = doppler_service_account.token_drift.slug

  # `environments` is deliberately unset, so the membership is PROJECT-WIDE. Scoping it to
  # ["prd"] would forfeit 7 scannable keys across `dev`, `dev_personal`, `dev_scheduled` and `ci`
  # while removing NONE of the escalation hops listed in the header — those all live in `prd`
  # root — and the 2026-08-03 census found only `cli` and `cli_ops` vacuous. Setting it is
  # narrowing N2: the scan then reports `7/13` and names the six dropped configs.
}

# The secret value. The provider names this token's computed, sensitive value `api_key` — NOT
# `key`, which is what every sibling `doppler_service_token` in this root uses. Copying the
# sibling attribute fails at `terraform plan`, and it is the single most likely transcription
# error in this file.
resource "doppler_service_account_token" "token_drift" {
  name                 = "token-drift-ci-tf"
  service_account_slug = doppler_service_account.token_drift.slug

  # Terraform infers a graph edge from this token to the ACCOUNT (via `service_account_slug`) but
  # NONE to the MEMBERSHIP, so without this explicit edge a partial or reordered apply can
  # publish a working token whose grant has not landed yet.
  depends_on = [doppler_project_member_service_account.token_drift]
}

# The sink. The `token_drift` step reads this as its `DOPPLER_TOKEN`, and it is the ONLY consumer
# — repointing it at a config-scoped `doppler_service_token` is narrowing N3, which the scan
# reports as `1/13`.
resource "github_actions_secret" "doppler_token_drift" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_DRIFT"
  plaintext_value = doppler_service_account_token.token_drift.api_key
}
