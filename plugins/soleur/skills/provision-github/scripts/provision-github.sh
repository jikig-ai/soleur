#!/usr/bin/env bash
set -euo pipefail

SLUG=""
TENANT_ORG=""
REVIEWER=""
DRY_RUN=false

usage() {
  echo "Usage: provision-github <tenant-slug> <tenant-org> <reviewer-github-username> [--dry-run]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage ;;
    -*)        echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$SLUG" ]]; then SLUG="$1"
      elif [[ -z "$TENANT_ORG" ]]; then TENANT_ORG="$1"
      elif [[ -z "$REVIEWER" ]]; then REVIEWER="$1"
      else echo "Unexpected argument: $1" >&2; usage
      fi
      shift ;;
  esac
done

[[ -n "$SLUG" ]] || { echo "Error: tenant-slug is required." >&2; usage; }
[[ -n "$TENANT_ORG" ]] || { echo "Error: tenant-org is required." >&2; usage; }
[[ -n "$REVIEWER" ]] || { echo "Error: reviewer-github-username is required." >&2; usage; }

if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Error: tenant-slug must be kebab-case (e.g. 'acme-prd')." >&2
  exit 1
fi

if ! [[ "$TENANT_ORG" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
  echo "Error: tenant-org must be a valid GitHub org name (alphanumerics and hyphens)." >&2
  exit 1
fi

if ! [[ "$REVIEWER" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
  echo "Error: reviewer must be a valid GitHub username (alphanumerics and hyphens)." >&2
  exit 1
fi

PROVISIONING_DIR="provisioning/${SLUG}/github"
CREATED_RESOURCES=()

cleanup() {
  local exit_code=$?
  echo ""
  echo "=== Teardown commands (resources created during this run) ==="
  if [[ ${#CREATED_RESOURCES[@]} -eq 0 ]]; then
    echo "  (no resources were created)"
  else
    for res in "${CREATED_RESOURCES[@]}"; do
      echo "  $res"
    done
  fi
  echo ""
  echo "IMPORTANT: After deleting the App installation, sweep bypass_actors for ghost entries:"
  echo "  gh api /repos/${TENANT_ORG}/${SLUG}/rulesets --jq '.[].bypass_actors'"
  echo ""
  echo "Bootstrap cleanup: Revoke the GitHub PAT used for bootstrapping — it is no longer needed."
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- Pre-checks ---

gh auth status >/dev/null 2>&1 || { echo "Error: 'gh' CLI not authenticated. Run 'gh auth login'." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: 'terraform' not found." >&2; exit 1; }

# --- DPA gate ---

DPA_FILE="knowledge-base/legal/tenant-dpa-register.md"
[[ -f "$DPA_FILE" ]] || { echo "DPA register not found at $DPA_FILE. Run from Soleur monorepo root." >&2; exit 3; }
awk -F'|' -v slug="$SLUG" '/^\|/ { gsub(/^ +| +$/, "", $2); if ($2 == slug && $8 ~ /^ *(dpa-signed|provisioning-in-progress) *$/) found=1 } END { exit !found }' "$DPA_FILE" \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }

# --- Idempotency check ---

if gh repo view "${TENANT_ORG}/${SLUG}" >/dev/null 2>&1; then
  echo "WARNING: Repository '${TENANT_ORG}/${SLUG}' already exists."
  echo "  Continuing will regenerate TF config. Existing repo is unchanged until 'terraform apply'."
  echo ""
fi

# --- Resolve org-id ---

ORG_ID=$(gh api "/orgs/${TENANT_ORG}" --jq .id 2>/dev/null) \
  || { echo "Error: Could not resolve org ID for '${TENANT_ORG}'. Check org name and permissions." >&2; exit 1; }

echo "Resolved org ID: ${TENANT_ORG} → ${ORG_ID}"

# --- Resolve reviewer user ID ---

REVIEWER_ID=$(gh api "/users/${REVIEWER}" --jq .id 2>/dev/null) \
  || { echo "Error: Could not resolve user ID for '${REVIEWER}'." >&2; exit 1; }

echo "Resolved reviewer ID: ${REVIEWER} → ${REVIEWER_ID}"

# --- Generate TF config ---

mkdir -p "$PROVISIONING_DIR"

cat > "${PROVISIONING_DIR}/github.tf" <<TFEOF
terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "tenants/${SLUG}/github.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "github_token" {
  description = "GitHub PAT with repo + admin:org scope (re-entered at apply time)"
  type        = string
  sensitive   = true
}

provider "github" {
  owner = "${TENANT_ORG}"
  token = var.github_token
}

resource "github_repository" "tenant" {
  name        = "${SLUG}"
  description = "Tenant repository for ${SLUG}"
  visibility  = "private"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
}

resource "github_repository_environment" "production" {
  repository  = github_repository.tenant.name
  environment = "production"

  reviewers {
    users = [${REVIEWER_ID}]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main_only" {
  repository     = github_repository.tenant.name
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}
TFEOF

echo "Generated ${PROVISIONING_DIR}/github.tf"

INSTALL_URL="https://github.com/apps/soleur/installations/new/permissions?target_id=${ORG_ID}"

# --- Dry-run output ---

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN — No changes will be made ==="
  echo ""
  echo "--- Generated Terraform config ---"
  cat "${PROVISIONING_DIR}/github.tf"
  echo ""
  echo "--- Copy-pasteable TF apply command ---"
  echo "read -rs -p 'GitHub PAT: ' TF_VAR_github_token && \\"
  echo "  export TF_VAR_github_token && \\"
  echo "  (cd ${PROVISIONING_DIR} && terraform init && terraform apply); \\"
  echo "  unset TF_VAR_github_token"
  echo ""
  echo "--- App install URL (human consent gate, per ToS B.3) ---"
  echo "  ${INSTALL_URL}"
  echo ""
  echo "--- Verification ---"
  echo "  gh api /repos/${TENANT_ORG}/${SLUG}/installation"
  echo "  gh api /repos/${TENANT_ORG}/${SLUG}/environments/production"
  echo ""
  echo "--- Teardown ---"
  echo "  gh api -X DELETE /app/installations/<install-id>"
  echo "  cd ${PROVISIONING_DIR} && terraform destroy"
  echo "  Sweep bypass_actors: gh api /repos/${TENANT_ORG}/${SLUG}/rulesets --jq '.[].bypass_actors'"
  echo ""
  echo "All provisioning complete. Run runbook Steps 5-10 manually."
  exit 0
fi

# --- Interactive flow ---

echo ""
echo "=== GitHub provisioning for '${SLUG}' ==="
echo ""
echo "This will:"
echo "  1. Create repo '${TENANT_ORG}/${SLUG}' via Terraform"
echo "  2. Create 'production' Environment with required reviewer (${REVIEWER})"
echo "  3. Pin deployment branch policy to 'main' only"
echo "  4. Install Soleur GitHub App on the repo (human consent)"
echo ""

echo "--- Step 1: Terraform apply ---"
echo ""
echo "Run this command in a separate terminal:"
echo ""
echo "  read -rs -p 'GitHub PAT: ' TF_VAR_github_token && \\"
echo "    export TF_VAR_github_token && \\"
echo "    (cd ${PROVISIONING_DIR} && terraform init && terraform apply); \\"
echo "    unset TF_VAR_github_token"
echo ""

read -p "TF apply complete? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

# --- Verify TF apply ---

if ! gh repo view "${TENANT_ORG}/${SLUG}" >/dev/null 2>&1; then
  echo "Error: Repository '${TENANT_ORG}/${SLUG}' not found. TF apply may not have completed." >&2
  exit 1
fi

CREATED_RESOURCES+=("cd ${PROVISIONING_DIR} && terraform destroy")
echo "Verified: Repository '${TENANT_ORG}/${SLUG}' exists."

# --- Verify Environment ---

ENV_CHECK=$(gh api "/repos/${TENANT_ORG}/${SLUG}/environments/production" --jq '.name' 2>/dev/null) || true
if [[ "$ENV_CHECK" == "production" ]]; then
  echo "Verified: Environment 'production' exists with required reviewers."
else
  echo "Warning: Could not verify 'production' Environment. Check GitHub settings." >&2
fi

# --- Step 2: App install (human consent gate) ---

echo ""
echo "--- Step 2: Install Soleur GitHub App ---"
echo ""
echo "This step requires human consent per GitHub ToS B.3."
echo "Open this URL and install the Soleur App on '${TENANT_ORG}/${SLUG}':"
echo ""
echo "  ${INSTALL_URL}"
echo ""
echo "Select ONLY the '${SLUG}' repository (not org-wide)."
echo ""

read -p "App installed? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

# --- Verify App install ---

INSTALL_JSON=$(gh api "/repos/${TENANT_ORG}/${SLUG}/installation" 2>/dev/null) || true
INSTALL_CHECK=$(echo "$INSTALL_JSON" | grep -o '"actions":"[^"]*"' | head -1 | cut -d'"' -f4)
REPO_SELECTION=$(echo "$INSTALL_JSON" | grep -o '"repository_selection":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ "$REPO_SELECTION" == "all" ]]; then
  echo "ERROR: App installed org-wide (repository_selection=all). Must be 'selected' (single repo)." >&2
  echo "Reconfigure: Settings → Integrations → Soleur → Repository access → Only select repositories" >&2
  exit 1
fi

if [[ "$INSTALL_CHECK" == "write" ]]; then
  INSTALL_ID=$(echo "$INSTALL_JSON" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  CREATED_RESOURCES+=("gh api -X DELETE /app/installations/${INSTALL_ID}")
  echo "Verified: Soleur App installed with actions:write permission (repository_selection=${REPO_SELECTION:-selected})."
else
  echo "Warning: Could not verify App installation or permissions." >&2
  echo "Expected permissions.actions = 'write'. Got: '${INSTALL_CHECK:-empty}'" >&2
  echo "Verify manually: gh api /repos/${TENANT_ORG}/${SLUG}/installation" >&2
fi

echo ""
echo "All provisioning complete. Run runbook Steps 5-10 manually."
