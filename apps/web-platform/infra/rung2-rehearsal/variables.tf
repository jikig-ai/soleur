# (#7025) Rehearsal-root inputs.
#
# NO `default` ON ANY SECRET-BEARING VARIABLE (hr-tf-variable-no-operator-mint-default). A
# default on a credential is an invitation to apply with a placeholder and discover the
# mistake at boot, which on this route means a rehearsal that proves nothing while costing a
# real host.
#
# THE PINNED-VS-DIVERGING SPLIT is the rung-2 contract and is enforced downstream by
# RUNG2_VAR_DIVERGENCE (see tests/scripts/lib/git-data-birth-readiness-gate.sh). Variables
# here that feed the render MUST carry prod's values, because the evidence hash binds the
# template and payloads but NOT the templatefile arguments.

variable "hcloud_token" {
  description = "Hetzner Cloud API token. The SAME project credential the parent root uses — the state separation isolates the resource lifecycle, not the account (see main.tf)."
  type        = string
  sensitive   = true
}

variable "doppler_token_tf" {
  description = "Doppler personal/service token for the `doppler` provider, used to create the SCRATCH config, write the throwaway LUKS passphrase into it, and mint the read-only boot token."
  type        = string
  sensitive   = true
}

variable "sentry_dsn" {
  description = "MUST be prod's DSN, byte-for-byte. The rehearsal exists to prove the off-host fatal channel works for the template production will boot; against a different DSN it would prove a channel prod does not use. On the rung-2 MUST-MATCH set, not the divergence allowlist."
  type        = string
}

variable "betterstack_ingest_url" {
  description = "MUST be prod's Better Stack ingest URL, byte-for-byte. Same argument as sentry_dsn — this is the stage-marker channel the capture script queries to distinguish a dark boot from a slow one."
  type        = string
  # DEFAULTED to prod's value rather than threaded from the workflow, because prod does not
  # thread it either: it is `local.betterstack_logs_ingest_url` in zot-registry.tf, a
  # hardcoded literal. Threading it here would let a dispatch silently point the rehearsal at
  # a different source and still produce hash-valid evidence.
  #
  # THAT MAKES THIS A SECOND COPY OF A LITERAL, so it is guarded rather than trusted:
  # git-data-rung2-rehearsal.test.sh extracts both sides BY SHAPE and fails if they diverge.
  # Not a credential, so hr-tf-variable-no-operator-mint-default does not apply — an ingest
  # URL is a public endpoint; the token that authorizes writing to it is separate.
  default = "https://s2457081.eu-fsn-3.betterstackdata.com/"
}

variable "betterstack_logs_token" {
  description = "Better Stack Logs INGEST token, written into the scratch Doppler config so the post-Doppler stage markers ship off-box. Write-only against a shared source: it cannot read anything back."
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Hetzner location. MUST match prod's — the Doppler CLI download and the volume shapes are the same everywhere, but a rehearsal in another DC is not rehearsing prod's capacity reality (#6570 made a host unbornable on exactly that axis)."
  type        = string
  default     = "fsn1"
}

variable "git_data_server_type" {
  description = "MUST match prod's. doppler_arch and doppler_sha256 are DERIVED from it, and they select which binary is downloaded and which checksum verifies it — so a divergence here rehearses a different boot-brick surface than production has (#6570)."
  type        = string
  default     = "cpx22"
}

variable "git_data_volume_size" {
  description = "Plaintext store volume size, GB. Smaller than prod is fine and cheaper: size is not a render var and does not enter the evidence hash."
  type        = number
  default     = 10
}

variable "git_data_luks_volume_size" {
  description = "LUKS volume size, GB. As above — the rehearsal proves cryptsetup luksOpen SUCCEEDS, which is a property of the mechanism and not of the capacity."
  type        = number
  default     = 10
}

variable "rehearsal_run_id" {
  description = "The dispatching GitHub Actions run id. Makes every rehearsal resource name unique, so a leaked host from a previous run cannot be silently adopted by the next one — and gives the capture script a host_name it can isolate on Better Stack's shared source 2457081."
  type        = string

  validation {
    # A run id, not free text. The name reaches Hetzner resource names AND the Better Stack
    # SQL the capture script builds, so anything that is not `[0-9]+` is either a mistake or
    # an injection surface. Fail at plan time rather than at query time.
    condition     = can(regex("^[0-9]+$", var.rehearsal_run_id))
    error_message = "rehearsal_run_id must be the numeric GitHub Actions run id (it names Hetzner resources and is interpolated into the Better Stack query the capture script runs)."
  }
}
