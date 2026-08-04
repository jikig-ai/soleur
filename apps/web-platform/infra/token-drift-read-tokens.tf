# --- #7234: the per-config Doppler read credentials for the token-drift scan -----------------
#
# The twice-daily Cloudflare-token-drift scan (`.github/workflows/scheduled-terraform-drift.yml`
# + `scripts/check-cloudflare-token-drift.sh`) reads token-shaped keys across EVERY Doppler config
# in the `soleur` project. This file mints one config-scoped read token per config and publishes
# them as ONE Actions secret holding a JSON map.
#
# WHY NOT A PROJECT-SCOPED SERVICE ACCOUNT — this shape's predecessor, and the measurement that
# killed it. #7159 chose a `doppler_service_account` with a `viewer` project membership, on the
# inferred premise that such an identity can enumerate and read every config in the project. That
# premise was never probed. Measured 2026-08-03 against the real credential:
#
#   doppler configs -p soleur --json                   -> null   (0 configs visible)
#   doppler secrets -p soleur -c prd --only-names      -> {"error":"Could not find requested config 'prd'"}
#
# It could neither enumerate NOR read. `workplace_permissions = []` — chosen as the
# least-privileged value satisfying the provider's ExactlyOneOf — yields `workplace_role:
# no_access`, and workplace-level visibility turns out to be a precondition for project access
# rather than something a project membership can confer on its own. The two values that might have
# worked (`all_enclave_projects`, or any `workplace_role`) both reach EVERY project in the
# workplace, strictly wider than the single `soleur` project #7159 authorised. The operator chose
# this shape instead on 2026-08-03 with that measurement in hand. ADR-168 records the reversal;
# ADR-164 records the falsified premise, which is worth keeping rather than overwriting.
#
# WHAT DOES THE ENUMERATING, NOW THAT NO CREDENTIAL CAN — the committed inventory. `local
# .token_drift_configs` below IS the config list, and the detector iterates the map's keys instead
# of asking Doppler to list a project it cannot see. That makes the inventory load-bearing in a
# way its header used to deny; the header is rewritten in this same change.
#
# THE ONE MIS-BINDING TERRAFORM CAN PRODUCE, and the four controls on it. `config = "prd"` written
# in place of `config = each.key` mints 13 DISTINCT tokens with 13 CORRECT map keys, all bound to
# one config — it passes every shape check there is.
#   C-a  a static test asserts `config = each.key` and rejects a string literal. Pre-merge, free.
#        `plugins/soleur/test/token-drift-workflow-causes.test.sh`, assertions F5 and C-a.
#   C-b  the detector validates the map parses as an object of string values before any network
#        call.
#   C-c  the READ ITSELF is the binding assertion — see the next paragraph.
#   C-d  `sort -u` on the detector's CONFIG_NAMES array. Without it, N assertions of one config
#        still length-N the array and print a confident N/13.
#
# WHY THE READ IS THE CONTROL (measured 2026-08-03, Phase 0 of this change). A config-scoped
# service token ERRORS on a wrong `-c` — it does NOT silently serve its bound config:
#
#   token bound to prd:  -c prd -> 129 keys;  -c dev / ci / cli / prd_terraform / prd_ghcr
#                        -> rc=1 "This token does not have access to requested config 'X'"
#   token bound to prd_kb_drift_walker (a BRANCH config): -c prd_kb_drift_walker -> 130 keys;
#                        -c prd -> rc=1 (a branch token cannot even read its own root)
#
# So under the mis-binding above, twelve of the thirteen reads fail closed, twelve configs count
# UNREAD, and the run grades `1/13 degraded` naming them. No extra probe is needed and none is
# made. NOTE this contradicts `knowledge-base/project/learnings/
# 2026-03-29-doppler-service-token-config-scope-mismatch.md`, which says `-c` is IGNORED — that is
# true of the `configs list` verb (see `kb-drift.tf`) and false of `secrets` in the pinned CLI
# v3.75.3. The two verbs differ; do not generalise either one.
#
# autonomy-considered: provider-mint-applied. Terraform mints and publishes every one of these
# in-band via `DOPPLER_TOKEN_TF` and the Terraform GitHub App: there is no operator
# credential-entry step in the CREATE path, which is what the `hr-tf-variable-no-operator-mint-default`
# class asks about. ROTATION is a different claim and is stated separately below, because an
# earlier version of this comment said "mints, publishes and rotates … in-band … no operator step
# at any point" and the rotation half of that is not true today.
#
# ROTATION. Per token:
#
#   terraform apply \
#     -replace='doppler_service_token.token_drift["<config>"]' \
#     -target='doppler_service_token.token_drift["<config>"]' \
#     -target='github_actions_secret.doppler_token_drift_map'
#
# BOTH `-target=`s ARE REQUIRED, AND THE RECIPE USED TO CARRY NEITHER. Two independent defects in
# the bare `-replace=`-only form:
#
#   1. `terraform apply -replace=<addr>` with no `-target=` plans the WHOLE ROOT. Copy-pasted
#      under incident pressure it applies every unrelated pending change in this configuration,
#      destroys included. That is not a rotation, it is a fleet apply with a replacement in it.
#   2. Adding `-target=` on the TOKEN ALONE is worse than useless: `-target` selects the address
#      and its DEPENDENCIES, never its DEPENDENTS. `github_actions_secret.doppler_token_drift_map`
#      reads `doppler_service_token.token_drift[*].key`, so it is a dependent — it would be
#      PRUNED from the plan. The apply would mint a new token, destroy the old one, and leave the
#      published map holding the destroyed value: every scan then reads with a revoked credential
#      and reports `degraded 0/13` until someone notices. The map must be targeted explicitly.
#
# The sentence this replaces read "The map republishes in the same apply either way", which is true
# only of the whole-root form in (1) — i.e. true of exactly the variant that is unsafe for the
# other reason.
#
# Whole set: one `-replace=` per config in a single apply, generated from the inventory, plus the
# same map `-target=`. Emergency revocation of the whole set is deleting the resource; the next
# scan reports `degraded 0/13` within 12 hours. Thirteen tokens is thirteen rotation obligations —
# the accepted cost of this shape, disclosed in ADR-168.
#
# NO DISPATCH ROUTE, AND THAT IS A GAP THIS CHANGE DOES NOT CLOSE. `ci-ssh-token-replace` in
# `apply-web-platform-infra.yml` is the precedent that has one — a `workflow_dispatch` arm with a
# distinct typo-guard token, a required reason, a concurrency mutex and a publish-channel check
# BEFORE the irreversible apply. Nothing equivalent exists for these tokens, so rotating one today
# means an operator running Terraform locally with `DOPPLER_TOKEN_TF` in hand. That is an operator
# step, and it is the status quo for all ten sibling `doppler_service_token`s in this root
# (`git_data`, `registry`, `ghcr_minter`, `kb_drift`, `write`, `inngest_arm`, …), every one of
# which documents the same bare recipe. It is a family-wide gap rather than one this shape
# introduces — tracked in issue #7263 so it is fixed for all eleven at once rather than bolted
# onto this change for one.
#
# NO `lifecycle` BLOCK AND NO `ignore_changes` ON `plaintext_value`, DELIBERATELY. With one, a
# `-replace=` rotation would mint values that never reached the Actions secret, and the scan would
# keep presenting revoked credentials while the apply read green. Mirrors `kb-drift.tf` and
# `doppler-write-token.tf`, which omit it for the same reason.
#
# NO `expires_at`. The sibling service tokens in this root do not expire. An expiry would fail the
# scan CLOSED with no in-band re-mint path, and it buys no detection this design lacks — a dead
# credential surfaces as `degraded` within 12 hours either way.
#
# STATE STORAGE. Each token's `key` is Computed + Sensitive + write-once, so the cleartext lands in
# `terraform.tfstate` on the R2 backend (`soleur-terraform-state`; server-side encrypted, TLS-only
# — see `main.tf`), the same posture the other ten `doppler_service_token` keys in this root already have.
#
# ⚠️ BLAST RADIUS — UNCHANGED FROM ADR-164, AND STILL A WIDENING. Thirteen read credentials
# covering the whole `soleur` project, including `prd`, which holds SUPABASE_SERVICE_ROLE_KEY
# (bypass-RLS read of all user data), the Terraform GitHub App private key (which yields an
# installation token that can rewrite every repository Actions secret, INCLUDING this one),
# GHCR_MINTER_DOPPLER_TOKEN (itself a read/write Doppler credential), PROXY_TLS_KEY and three git
# transport SSH keys. That reach was disclosed and accepted at #7159; what changes here is that it
# becomes REAL, where today's live reach is one config. A leaked `DOPPLER_TOKEN_DRIFT_MAP` or a
# leaked R2 access key yields all thirteen at once.
#   What actually TRANSITS the runner is narrower than what is reachable: values only for
#   `CF_API_TOKEN*` and the `*_ACCESS_TOKEN_ID/_SECRET` pair, though `--only-names` pulls each
#   config's full key-NAME listing. The bypass-RLS reach is a capability, not an exercised read.
# Prior art, cited rather than re-derived:
#   knowledge-base/project/learnings/security-issues/
#     2026-07-07-doppler-branch-config-does-not-isolate-secrets.md  (severity: high)
#
# PUBLICATION. `DOPPLER_TOKEN_DRIFT_MAP` is a REPOSITORY-level Actions secret, not because that is
# preferred but because the Terraform GitHub App cannot write ENVIRONMENT-scoped secrets (403; see
# `doppler_token_inngest_arm`'s comment for the precedent). Every sibling `github_actions_secret`
# in this root is repo-scoped for the same reason. The governing control is who can merge under
# `.github/workflows/`, which `CODEOWNERS` pins to the operator.
#
# APPLY PATH. Both addresses ride the DEFAULT per-merge `-target=` allow-list in
# `apply-web-platform-infra.yml`. ONE leg covers all thirteen instances: `-target=` on a `for_each`
# resource expands to every instance (measured on the CI Terraform pin, v1.10.5), and
# `terraform-target-parity.test.ts` matches the un-indexed base address on both sides.

locals {
  # THE config list. Derived from the committed inventory so there is no second place the set
  # lives — a restated list would be a fifth place the number 13 hides, pinned to the inventory by
  # nothing.
  #
  # NO `trimspace()`/`trim()`/`chomp()`, and that is load-bearing rather than an oversight. This
  # filter must accept exactly what the detector's `grep -E '^[a-z0-9_]+$'` accepts. Measured: over
  # raw `split("\n")` lines the two agree on every ASCII input, including rejecting a
  # trailing-space line — because Terraform's `regex` anchors per string exactly as grep anchors
  # per line. Adding a normaliser here BREAKS that agreement: `trimspace()` would make the .tf
  # accept ` prd ` while the detector still rejects it, minting a token for a config the scan
  # never counts. The one measured divergence is locale, not whitespace — under a glibc
  # en_US.UTF-8 locale grep's `[a-z]` matches accented lowercase where RE2 does not — so the
  # detector's grep sites are pinned `LC_ALL=C` rather than this claim being softened.
  #
  # `distinct()` because HCL does not dedupe and the detector's parse does (`sort -u`), so this
  # makes the local directly comparable to it. `toset()` below would dedupe anyway; the explicit
  # call is what makes the local ITSELF the accepted set, which is what F5 compares.
  token_drift_configs = distinct([
    for _l in split("\n", file("${path.module}/doppler-config-inventory.txt")) :
    _l if can(regex("^[a-z0-9_]+$", _l))
  ])
}

# The credentials. One per config, read-only.
#
# `project` is a literal because the `soleur` Doppler project is not Terraform-managed. That is
# correct for every config in today's inventory, all of which pre-exist outside Terraform.
#
# ⚠️ SE-4 — `config = each.key` is a STRING, so it builds NO dependency edge, and one future config
# IS Terraform-managed: `git-data-luks.tf` declares `doppler_config.git_data_prd`, and ADR-149 says
# `prd_git_data` appears at git-data birth. The PR that adds that name to the inventory must ALSO
# add `depends_on = [doppler_config.git_data_prd]` here, or the token create can be ordered before
# the config exists and the apply fails on a race that reads as flake. This trap is restated in the
# inventory's floor-raising block, because that is the block a floor-raiser actually reads.
resource "doppler_service_token" "token_drift" {
  for_each = toset(local.token_drift_configs)

  project = "soleur"

  # LOAD-BEARING. A string literal in place of `each.key` mints one token per config NAME and
  # binds them all to ONE config: 13 distinct tokens, 13 correct map keys, one config actually
  # read. Asserted statically by the C-a test, and fail-closed at runtime by the reads themselves
  # (see the header's measurement).
  config = each.key

  name   = "token-drift-ci-tf-${each.key}"
  access = "read"
}

# The sink. ONE repository Actions secret carrying a JSON object keyed by config name.
#
# `.key` — NOT `.api_key`, which belonged to the retired `doppler_service_account_token` and is the
# single most likely transcription error when copying from the file this replaces.
#
# Measured on the CI Terraform pin (v1.10.5): `jsonencode` over a `for_each` map of sensitive
# attributes tracks the encoded string as sensitive, and emits keys SORTED — so the secret churns
# only when a token value or the key set actually changes, not on every re-plan. ~800 bytes against
# GitHub's 48 KB limit. `jsonencode` HTML-escapes `<`; Doppler tokens are `dp.st.<name>.<url-safe>`
# so nothing escapes, but the detector parses it with `jq`, never a regex.
#
# Key and value come from the SAME iteration variable, so a key/value skew would be an HCL bug
# rather than something a careless edit can produce. The C-a test pins it regardless.
resource "github_actions_secret" "doppler_token_drift_map" {
  repository  = "soleur"
  secret_name = "DOPPLER_TOKEN_DRIFT_MAP"

  plaintext_value = jsonencode({
    for _cfg, _t in doppler_service_token.token_drift : _cfg => _t.key
  })
}
