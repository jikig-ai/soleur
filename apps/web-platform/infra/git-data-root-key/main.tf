# (#8189, ADR-220) THE GIT-DATA ROOT-KEY ROOT — a SEPARATE Terraform root that mints the git-data
# root SSH key, publishes its public half to Hetzner (label soleur-role=git-data-root, read by the
# web-platform root's data source at create time), stores the private half in the separate Doppler
# project soleur-git-data-root, and publishes one read token for the reviewer-gated cutover job.
#
# Why a separate root, what it does NOT isolate (R2 state readable by prd_terraform credentials,
# DOPPLER_TOKEN_TF workplace scope), and the rotation path live in ADR-220 (D2/D3/D4). This file
# carries only what a reviewer needs at the code:
#
#   - Applied ONLY by .github/workflows/apply-git-data-root-key.yml (dispatch-only, environment
#     reviewer, git-data-state serialized, additive-only plan allowlist). The parent root's push
#     apply excludes this directory by a negated path glob.
#   - No output block, no nonsensitive(), no local_file, no local-exec, no provisioner, no
#     terraform_remote_state: git-data-root-key.test.sh censuses all of them.
#   - Every key-bearing resource carries prevent_destroy. A rotation is a reviewed PR that lifts it.
terraform {
  backend "s3" {
    bucket = "soleur-terraform-state"
    # A DISTINCT KEY from the parent's web-platform/terraform.tfstate — the key never enters the
    # web-platform state that dozens of plan/apply jobs read (ADR-220 D2).
    key                         = "web-platform/git-data-root-key/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 has no conditional writes, so no state lock: the apply workflow's job-level
    # `git-data-state` concurrency group is the serializer.
    use_lockfile = false
  }

  # Same constraints as the parent root; the lock pins the parent's exact versions.
  required_providers {
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.21"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
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

# Copied verbatim from the parent root's App-auth block (hr-github-app-auth-not-pat).
provider "github" {
  owner = "jikig-ai"
  app_auth {
    id              = var.github_app_id
    installation_id = "122213433"
    pem_file        = var.github_app_private_key
  }
}
