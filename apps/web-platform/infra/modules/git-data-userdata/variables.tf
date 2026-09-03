# (#7025, R7) Render-time inputs to the shared git-data user_data render.
#
# THE DIVERGENCE TAXONOMY IS THE POINT OF THIS FILE, so it is stated here rather than left
# to the rehearsal root to remember. The rung-2 evidence hash binds the TEMPLATE plus the
# nine `file()`-bound payloads. It does NOT bind these variables — they are `templatefile`
# arguments, not hashed inputs — so a rehearsal that diverged on the wrong one produces
# hash-valid evidence for a boot that is not the boot production would get.
#
# That gap is closed by declaration, not by hope: the rehearsal writes RUNG2_VAR_DIVERGENCE
# into its evidence file and git_data_rung2_rehearsal_gate refuses any divergence outside
# the allowlist below.
#
#   MAY DIVERGE (identity-shaped — they name WHICH host/volume/credential, never WHAT boots):
#     host_name, git_data_volume_id, git_data_luks_volume_id, doppler_token,
#     doppler_config_name, git_transport_pubkey, git_provision_pubkey, git_remove_pubkey
#
#   MUST MATCH PROD BYTE-FOR-BYTE (they change WHAT the host does):
#     git_data_server_type          — the Doppler download arch AND its checksum are DERIVED
#                                     from this inside this module (#7025 R7), so a divergence
#                                     here rehearses a different boot-brick surface than prod
#                                     has (#6570). git-data-rung2-rehearsal.test.sh pins that
#                                     both roots bind it from their own var, because text
#                                     equality of the two derivations says nothing about
#                                     equality of their inputs.
#     sentry_dsn                    — the fatal channel under test; a rehearsal against a
#                                     different DSN proves a channel prod does not use
#     betterstack_ingest_url        — same, for the stage-marker channel
#
#   NOT INPUTS AT ALL — doppler_arch and doppler_sha256 were module variables until #7025 R7
#   and are now derived internally from git_data_server_type. They are listed here only to
#   say they are gone: a caller cannot pass its own pair, so that divergence is unexpressible
#   rather than merely refused, and it can never appear in RUNG2_VAR_DIVERGENCE. The rung-2
#   suite pins the module's COMPLETE input surface, so re-adding either name (or any other
#   input) is RED until declared here.
#
# NO `default` ON ANY SECRET-BEARING VARIABLE (hr-tf-variable-no-operator-mint-default).
# doppler_config_name carries a default because it is a config NAME, not a credential, and
# defaulting it to the prod value keeps git-data.tf's call byte-equivalent to its pre-#7025
# behaviour.

variable "host_name" {
  description = "Baked into the Better Stack stage markers and the Sentry events, so it is what discriminates this host's rows from its siblings on shared source 2457081. Prod: soleur-git-data. Rehearsal: soleur-git-data-rehearsal-<run-id>."
  type        = string
}

variable "git_data_volume_id" {
  description = "hcloud_volume id for the PLAINTEXT bare-repo store, mounted by-id."
  type        = string
}

variable "git_data_luks_volume_id" {
  description = "hcloud_volume id for the LUKS-at-rest volume the guest cryptsetup luksOpens. A stub id here makes luksOpen fail, which is the rung-2 FAIL arm rather than a shortcut."
  type        = string
}

variable "doppler_token" {
  description = "Read-only Doppler service token scoped to EXACTLY the config named by doppler_config_name. Scoped elsewhere, `doppler run` exits 1 before the LUKS heredoc and the host boots dark (#6982 W0)."
  type        = string
  sensitive   = true
}

variable "doppler_config_name" {
  description = "The Doppler config the two boot-time `doppler run` invocations name. MUST be the config doppler_token is scoped to. Prod: prd_git_data."
  type        = string
  default     = "prd_git_data"
}

variable "git_data_server_type" {
  description = "Hetzner server type. The Doppler CLI arch token and its checksum are DERIVED FROM THIS, inside this module, so the pair exists exactly once for both roots. Callers pass the type, never the derived pair."
  type        = string
}

variable "sentry_dsn" {
  description = "BAKED into user_data deliberately: the one channel that still reports when Doppler is the broken stage. Semi-public (already in the client bundle) and lands in tfstate + metadata-retrievable user_data — accepted."
  type        = string
}

variable "betterstack_ingest_url" {
  description = "Better Stack Logs ingest URL for the boot-stage markers."
  type        = string
}

variable "betterstack_logs_token" {
  description = "Write-only Better Stack Logs INGEST token, baked into user_data at 0600 root:root so the pre-Doppler boot stages can reach the queryable channel (#7460). Capability ceiling is append-to-a-telemetry-sink: forged rows and quota burn, never log READ (that is BETTERSTACK_QUERY_*) and never sink management (BETTERSTACK_API_TOKEN). No default (hr-tf-variable-no-operator-mint-default) — both roots already resolve it from Doppler prd_terraform. See ADR-198 for why this is bakeable where GIT_DATA_LUKS_KEY is not."
  type        = string
  sensitive   = true
}

variable "git_transport_pubkey" {
  description = "PUBLIC half of the transport keypair, trimspace()'d by the caller."
  type        = string
}

variable "git_provision_pubkey" {
  description = "PUBLIC half of the provision keypair, trimspace()'d by the caller."
  type        = string
}

variable "git_remove_pubkey" {
  description = "PUBLIC half of the erasure keypair, trimspace()'d by the caller."
  type        = string
}
