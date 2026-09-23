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
    # (#8209, ADR-239 D7) PARTIAL BACKEND — the bucket is supplied at init time as
    # `-backend-config=bucket=$BUCKET`, NOT pinned here.
    #
    # WHY. A distinct KEY inside a SHARED bucket is not isolation. Measured (M7):
    # listing `soleur-terraform-state` with the Tier-A `prd_terraform` AWS_* keys
    # returns all seven state objects, this one included — so the git-data root key,
    # which is root on the host storing every connected user's repositories, was
    # readable from any branch workflow through the state object. ADR-220 D2's "never
    # enters the web-platform state" is true and was never the whole reach.
    #
    # The object moves to `soleur-terraform-state-privileged`
    # (cloudflare_r2_bucket.terraform_state_privileged in the parent root), whose
    # bucket-scoped token is Tier-B only. The Tier-A keys are bucket-scoped (M7:
    # ListBuckets returns AccessDenied), so a bucket they are not scoped to is out of
    # reach rather than merely un-referenced.
    #
    # The loader (.github/actions/infra-credentials) passes the privileged bucket when
    # it exported the GIT_DATA_ROOT_STATE_* key pair, and the legacy bucket otherwise —
    # which is what keeps this merge-safe before the operator migrates the object. Once
    # the repo variable GIT_DATA_ROOT_STATE_MIGRATED=1 is set (operator step O8), the
    # loader REFUSES the legacy bucket, so a post-migration run cannot silently write
    # back to the object the operator is about to delete.
    #
    # The PR plan job never initializes this nested root (detect-changes collapses it
    # into its parent, ADR-220 D2.2/TS2b), so no PR-plan backend config is needed. A
    # local operator init passes -backend-config=bucket=… ; the runbook gives the form.
    #
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
  token = var.github_plan_actions_credential != "" && var.github_infra_app_private_key == "" ? var.github_plan_actions_credential : null

  # (#8209, ADR-239) Three auth modes, selected by which variables are non-empty:
  # INFRA (github_infra_app_private_key set) is the Tier-B `soleur-infra` App and the
  # mode every apply runs in after the operator sequence; TOKEN
  # (github_plan_actions_credential set, no infra key) is the PR plan job's own
  # read-only `github.token`; LEGACY (neither) is the soleur-ai key from prd_terraform,
  # the BEFORE state that keeps this merge safe. The `for_each` is the exact complement
  # of the `token` condition so exactly one always resolves -- integrations/github v6
  # otherwise falls back to an ambient GITHUB_TOKEN/`gh auth token`, authenticating as
  # whoever the runner happens to be instead of failing. Full rationale:
  # apps/web-platform/infra/main.tf, the same block.
  dynamic "app_auth" {
    for_each = var.github_infra_app_private_key != "" || var.github_plan_actions_credential == "" ? [1] : []
    content {
      id = var.github_infra_app_private_key != "" ? var.github_infra_app_id : var.github_app_id
      # 122213433 is the soleur-ai INSTALLATION id on jikig-ai, not the App id
      # (3261325). Literal because it belongs to the legacy mode only.
      installation_id = var.github_infra_app_private_key != "" ? var.github_infra_app_installation_id : "122213433"
      pem_file        = var.github_infra_app_private_key != "" ? var.github_infra_app_private_key : var.github_app_private_key
    }
  }
}
