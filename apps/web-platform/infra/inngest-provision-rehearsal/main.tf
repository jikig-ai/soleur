# (#9175) THE INNGEST-PROVISION REHEARSAL ROOT — a SEPARATE Terraform root, and that
# separation is the whole safety argument rather than one guard among several (same
# reasoning as rung2-rehearsal/main.tf, which this file mirrors).
#
# WHY NOT `count = 0` IN THE SHARED ROOT. `-target` is TRANSITIVE ON DEPENDENCIES, so any
# rehearsal address referencing a prod `hcloud_server.inngest` attribute would drag the
# production scheduler into the plan closure — and a rehearsal apply whose closure reached
# that address would REPLACE the sole production inngest host inside a workflow whose
# approval prompt said "rehearsal". A separate state file makes that a structural
# impossibility rather than a grep-level one.
#
# WHAT THE SEPARATION DOES **NOT** ISOLATE, stated plainly:
#
#   - the Hetzner PROJECT credential (one project, one token — a rehearsal apply is
#     authorized against the same account that holds web-1, the registry and inngest)
#   - the Doppler PROJECT (`soleur-inngest`; only the ENVIRONMENT is scratch —
#     `rehearsal_<runid>` is a ROOT config that inherits NOTHING, unlike the branch
#     config rung2 used under `prd`, which inherits every prd secret)
#   - the Better Stack source and the Sentry project (deliberately: the rehearsal must
#     exercise the REAL emit channel so its evidence is meaningful)
#   - the private network (Phase B attaches the throwaway host at 10.0.1.60 — that is the
#     POINT: the forced race is NIC-absent -> NIC-attached on the real subnet)
#   - the parent root's push-triggered apply (mitigated by the NEGATED path glob for this
#     subdir in apply-web-platform-infra.yml)
#   - teardown garbage collection: `terraform destroy` acts only on state; the drift
#     sweeper DETECTS `soleur-inngest-rehearsal-*` / `app=soleur-inngest-provision-
#     rehearsal` / `rehearsal_*` orphans and reports rather than deleting.
terraform {
  backend "s3" {
    bucket = "soleur-terraform-state"
    # A DISTINCT KEY. This is the control; everything else in this file is defence in depth.
    key                         = "web-platform/inngest-provision-rehearsal/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 does not support S3 conditional writes, so there is NO state lock here either —
    # identical to the parent root, and the reason the rehearsal workflow JOINS the
    # parent's `terraform-apply-web-platform-host` concurrency group rather than
    # declaring its own.
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
