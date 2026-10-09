# (#9175) Rehearsal-root inputs.
#
# NO `default` ON ANY SECRET-BEARING VARIABLE (hr-tf-variable-no-operator-mint-default). A
# default on a credential is an invitation to apply with a placeholder and discover the
# mistake at boot, which on this route means a rehearsal that proves nothing while costing
# a real host.

variable "hcloud_token" {
  description = "Hetzner Cloud API token. The SAME project credential the parent root uses — the state separation isolates the resource lifecycle, not the account (see main.tf)."
  type        = string
  sensitive   = true
}

variable "doppler_token_tf" {
  description = "Doppler token for the `doppler` provider, used to create the SCRATCH environment (rehearsal_<runid>), write the five throwaway secrets into it, and mint the read-only boot token."
  type        = string
  sensitive   = true
}

variable "sentry_dsn" {
  description = "The SAME Sentry DSN prod bakes — the rehearsal must exercise the real emit channel for its evidence to be meaningful. Passed through to the template's sentry_dsn arg."
  type        = string
  sensitive   = true
}

variable "betterstack_logs_token" {
  description = "The SAME write-only Better Stack ingest token prod's config holds — write-only against the shared source, so a throwaway host gains no readback. Passed to the template arg AND staged into the scratch config (the boot re-fetches it)."
  type        = string
  sensitive   = true
}

variable "zot_pull_token" {
  description = "The REAL zot pull credential (random_password.zot_pull.result in the parent root). The rehearsal must perform the real registry login + image pull — a stub here would rehearse a boot that does not exist."
  type        = string
  sensitive   = true
}

variable "rehearsal_run_id" {
  description = "The GitHub Actions run id — makes every rehearsal resource name unique (soleur-inngest-rehearsal-<runid>) so a second rehearsal cannot collide with or adopt a leaked first one's resources. Digits only so the name stays DNS/host-label safe."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.rehearsal_run_id))
    error_message = "rehearsal_run_id must be digits only (it lands in the Hetzner host name, the Doppler environment slug, and the host-pinned Better Stack host_name)."
  }
}

variable "nic_attached" {
  description = "THE FORCED-RACE CONTROL. false (Phase A) creates the host with NO private NIC so the provision unit's NIC wait times out and retries; true (Phase B) creates hcloud_server_network.rehearsal — the ONLY diff between the two applies."
  type        = bool
}

variable "location" {
  description = "Hetzner location — defaults to prod's hel1 so the rehearsal exercises the same zone behavior (and stays inside the private network's eu-central zone)."
  type        = string
  default     = "hel1"
}

variable "server_type" {
  description = "Hetzner server type — defaults to prod's cpx22 so the arch derivation (amd64) matches production."
  type        = string
  default     = "cpx22"

  validation {
    condition     = can(regex("^(cax|cpx|cx|ccx)", var.server_type))
    error_message = "server_type must be a recognized Hetzner type (cax*=arm64, or cpx*/cx*/ccx*=amd64); arch is derived from the prefix."
  }
}
