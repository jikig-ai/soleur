# (#7025) THE RUNG-2 REHEARSAL ROOT — a SEPARATE Terraform root, and that separation is the
# whole safety argument rather than one guard among several.
#
# WHY NOT `count = 0` IN THE SHARED ROOT. It looks equivalent and is not. `-target` is
# TRANSITIVE ON DEPENDENCIES, so any rehearsal address referencing a prod `git_data`
# attribute drags hcloud_server.git_data into the plan closure — and a rehearsal apply whose
# closure reached that address would CREATE the production git-data host outside the birth
# route: bypassing its environment reviewer, its confirm token, both interlocks and its
# `-target` allow-set. That host would hold every connected user's source code and would have
# been born by a workflow whose approval prompt said "rehearsal".
#
# A separate state file makes that a structural impossibility for Terraform's managed-resource
# lifecycle rather than something the greps in git-data-rung2-rehearsal.test.sh have to catch.
# The greps are the belt.
#
# WHAT THE SEPARATION DOES **NOT** ISOLATE, stated here because ADR-149's DC-6 was drafted
# claiming it made prod-reach "structurally impossible" full stop, and that overstated it in
# the same register the sentinel gate's header already had to correct once:
#
#   - the Hetzner PROJECT credential (one project, one token — a rehearsal apply is
#     authorized against the same account that holds web-1, the registry and inngest)
#   - the Doppler PROJECT (soleur; only the CONFIG is scratch)
#   - the Sentry project (deliberately: the rehearsal must exercise the REAL fatal channel)
#   - the parent root's push-triggered apply (mitigated by a `paths-ignore` on this subdir in
#     apply-web-platform-infra.yml, which is a workflow property and not a state one)
#   - teardown garbage collection: nothing outside this root's own `if: always()` destroy and
#     the drift sweeper's orphan probe reclaims a host this state file has forgotten. That is
#     a NAMED RESIDUAL, not a solved problem.
#
# NO NETWORK ATTACHMENT (R2). An earlier draft attached the rehearsal host to the prod
# 10.0.1.0/24 behind a deny-all firewall. Dropping the attachment removes the leak vector
# structurally instead of guarding it — and `hcloud_firewall.git_data`'s own comment records
# why the guard was never sufficient anyway: intra-network traffic "is open by network
# membership", so the firewall never covered the private surface. Measured before removing it:
# `grep -c '10\.0\.1\.'` on cloud-init-git-data.yml is 0, and the NIC/EXPECTED_IP reference
# count is 0 — the boot needs public egress plus Sentry and Better Stack, and nothing else.
# It also deletes the 10.0.1.20 hazard: that address is free only while git-data is unborn,
# and it is baked into every web host as GIT_DATA_ENDPOINT.
terraform {
  backend "s3" {
    bucket = "soleur-terraform-state"
    # A DISTINCT KEY. This is the control; everything else in this file is defence in depth.
    # Directory-shaped, matching the `sentry/` precedent in this bucket.
    key                         = "web-platform/rung2-rehearsal/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 does not support S3 conditional writes, so there is NO state lock here either —
    # identical to the parent root, and the reason this workflow JOINS the parent's
    # `git-data-state` concurrency group rather than declaring its own. A distinct group
    # would PERMIT a rehearsal and a birth to run at once, which is the opposite of what a
    # concurrency group is for; birth and replace already share that literal for this reason.
    use_lockfile = false
  }

  # PINNED TO THE PARENT ROOT'S VERSIONS. The rehearsal's entire claim is that it boots the
  # same bytes production would, so a provider that rendered or attached differently would
  # make the evidence attest a boot nobody is going to get.
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.21"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.7"
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "doppler" {
  doppler_token = var.doppler_token_tf
}
