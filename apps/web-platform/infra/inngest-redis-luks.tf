# ============================================================================
# LUKS apparatus for the dedicated inngest host's Redis AOF volume (#7695).
#
# ONE FILE, DELIBERATELY. `scripts/lint-encryption-posture.py` resolves a ledger
# row's citation STRUCTURALLY, not by name similarity: it requires a co-located
# `random_password` + `doppler_secret` pair alongside the apparatus they key. A
# split across two files fails that resolution even when both halves exist, so
# do not "tidy" these into the sibling files their names suggest.
#
# WHAT THIS FILE DOES NOT DO. It creates a passphrase and escrows it. It does
# NOT change `hcloud_volume.inngest_redis`, does NOT recut anything, and is
# inert with respect to the running host until a boot reads the key. The recut
# itself is the reviewer-gated `apply_target=inngest-volume-recut`; ADR-142
# forbids an unconditional `-replace` of this exact volume and that prohibition
# stands — the destructive path is conditional on a measured-dark host, with
# ADR-142's byte-copy the only lawful alternative.
#
# "MERGE IS INERT" IS THE DEFECT HERE, NOT THE SAFETY PROPERTY. Both resources
# below MUST be in the per-merge `-target=` allowlist in
# .github/workflows/apply-web-platform-infra.yml. The passphrase has to EXIST
# before any host boots that reads it: a host replaced ahead of the secret
# reaches its LUKS stage, finds INNGEST_REDIS_LUKS_KEY empty, and — correctly —
# refuses to mount rather than falling back to plaintext. That is a dark host,
# on a fleet whose only scheduler is elsewhere and whose diagnosis is a Better
# Stack read. Ordering is the safety property; inertness is not.
# ============================================================================

# length 40 / special = false — mirrors random_password.workspaces_luks and
# random_password.git_data_luks. `special = false` is not cosmetic: the value is
# piped to `cryptsetup --key-file -` through a `doppler run` environment, and a
# shell-metacharacter-free alphabet removes a whole class of quoting defect from
# a path where a mistake is unrecoverable (a wrong passphrase on a formatted
# volume is indistinguishable from a lost one).
#
# NO `lifecycle { ignore_changes = ... }`, deliberately. A regenerated passphrase
# must cascade — a drifted key that Terraform declines to notice is a volume
# nobody can open, discovered at the next boot rather than at plan time.
resource "random_password" "inngest_redis_luks" {
  length  = 40
  special = false
}

# --- Key escrow -------------------------------------------------------------
# The isolated `soleur-inngest` project, NOT `soleur`. This is the SAME boundary
# the host's own token already draws (doppler_service_token.inngest, #6178): the
# inngest project has no inheritance path to `soleur/prd`, so a compromise of
# either side does not hand over the other's secret set.
#
# Do NOT "simplify" this to `soleur/prd` to match the web host's pattern. The web
# host runs `doppler secrets download --config prd` and injects the whole config
# into the agent container's environment (the boundary workspaces-luks.tf
# documents at length). This host does not, and the isolation is the reason its
# apparatus can key off the root `prd` config at all.
resource "doppler_secret" "inngest_redis_luks_key" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_REDIS_LUKS_KEY"
  value      = random_password.inngest_redis_luks.result
  visibility = "masked"
}
