#!/usr/bin/env bash
set -euo pipefail

SLUG=""
CF_ZONE_ID=""
CF_ACCOUNT_ID=""
DRY_RUN=false

usage() {
  echo "Usage: provision-cloudflare <tenant-slug> <cf-zone-id> <cf-account-id> [--dry-run]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage ;;
    -*)        echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$SLUG" ]]; then SLUG="$1"
      elif [[ -z "$CF_ZONE_ID" ]]; then CF_ZONE_ID="$1"
      elif [[ -z "$CF_ACCOUNT_ID" ]]; then CF_ACCOUNT_ID="$1"
      else echo "Unexpected argument: $1" >&2; usage
      fi
      shift ;;
  esac
done

[[ -n "$SLUG" ]] || { echo "Error: tenant-slug is required." >&2; usage; }
[[ -n "$CF_ZONE_ID" ]] || { echo "Error: cf-zone-id is required." >&2; usage; }
[[ -n "$CF_ACCOUNT_ID" ]] || { echo "Error: cf-account-id is required." >&2; usage; }

if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Error: tenant-slug must be kebab-case (e.g. 'acme-prd')." >&2
  exit 1
fi

if ! [[ "$CF_ZONE_ID" =~ ^[a-f0-9]{32}$ ]]; then
  echo "Error: cf-zone-id must be a 32-char hex string." >&2
  exit 1
fi

if ! [[ "$CF_ACCOUNT_ID" =~ ^[a-f0-9]{32}$ ]]; then
  echo "Error: cf-account-id must be a 32-char hex string." >&2
  exit 1
fi

PROVISIONING_DIR="provisioning/${SLUG}"
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
  echo "Bootstrap cleanup: Revoke the Cloudflare API token used for bootstrapping — it is no longer needed."
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- Pre-checks ---

command -v curl >/dev/null 2>&1 || { echo "Error: 'curl' not found." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: 'terraform' not found." >&2; exit 1; }

# --- DPA gate ---

DPA_FILE="knowledge-base/legal/tenant-dpa-register.md"
[[ -f "$DPA_FILE" ]] || { echo "DPA register not found at $DPA_FILE. Run from Soleur monorepo root." >&2; exit 3; }
awk -F'|' -v slug="$SLUG" '/^\|/ && $2 ~ slug && $7 ~ /dpa-signed|provisioning-in-progress/' "$DPA_FILE" | grep -q . \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }

# --- Idempotency check ---

if [[ -f "${PROVISIONING_DIR}/cloudflare.tf" ]]; then
  echo "WARNING: ${PROVISIONING_DIR}/cloudflare.tf already exists."
  echo "  Continuing will overwrite. Existing CF resources are unchanged until 'terraform apply'."
  echo ""
fi

# --- Generate TF config ---

mkdir -p "$PROVISIONING_DIR"

cat > "${PROVISIONING_DIR}/cloudflare.tf" <<TFEOF
terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "tenants/${SLUG}/provisioning.tfstate"
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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "cf_bootstrap_token" {
  description = "Cloudflare API token for bootstrapping (re-entered at apply time)"
  type        = string
  sensitive   = true
}

provider "cloudflare" {
  api_token = var.cf_bootstrap_token
}

resource "cloudflare_api_token" "tenant_deploy" {
  name = "${SLUG}-deploy"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["Workers Routes Write"],
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${CF_ZONE_ID}" = "*"
    }
  }

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Workers Scripts Write"],
      data.cloudflare_api_token_permission_groups.all.account["Cloudflare Pages Write"],
    ]
    resources = {
      "com.cloudflare.api.account.${CF_ACCOUNT_ID}" = "*"
    }
  }
}

data "cloudflare_api_token_permission_groups" "all" {}

output "cf_deploy_token" {
  value     = cloudflare_api_token.tenant_deploy.value
  sensitive = true
}
TFEOF

echo "Generated ${PROVISIONING_DIR}/cloudflare.tf"

# --- Dry-run output ---

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN — No changes will be made ==="
  echo ""
  echo "--- Generated Terraform config ---"
  cat "${PROVISIONING_DIR}/cloudflare.tf"
  echo ""
  echo "--- Copy-pasteable TF apply command ---"
  echo "read -rs -p 'Cloudflare API token: ' TF_VAR_cf_bootstrap_token && \\"
  echo "  export TF_VAR_cf_bootstrap_token && \\"
  echo "  cd ${PROVISIONING_DIR} && terraform init && terraform apply && \\"
  echo "  unset TF_VAR_cf_bootstrap_token"
  echo ""
  echo "--- Smoke-test (run after TF apply) ---"
  echo "cd ${PROVISIONING_DIR} && terraform output -raw cf_deploy_token | ("
  echo "  read -r TOKEN"
  echo "  curl -sS -H \"Authorization: Bearer \$TOKEN\" \\"
  echo "    https://api.cloudflare.com/client/v4/user/tokens/verify | jq .result.status"
  echo ")"
  echo ""
  echo "--- Teardown ---"
  echo "  cd ${PROVISIONING_DIR} && terraform destroy"
  echo "  rm -rf ${PROVISIONING_DIR}/cloudflare.tf"
  echo ""
  echo "Next step: soleur:provision-hetzner ${SLUG}"
  exit 0
fi

# --- Interactive flow ---

echo ""
echo "=== Cloudflare provisioning for '${SLUG}' ==="
echo ""
echo "This will create a scoped API token with:"
echo "  - Workers Scripts:Edit (account: ${CF_ACCOUNT_ID})"
echo "  - Workers Routes:Edit (zone: ${CF_ZONE_ID})"
echo "  - Cloudflare Pages:Edit (account: ${CF_ACCOUNT_ID})"
echo "  - DNS:Edit (zone: ${CF_ZONE_ID})"
echo ""

echo "--- Step 1: Terraform apply ---"
echo ""
echo "Run this command in a separate terminal:"
echo ""
echo "  read -rs -p 'Cloudflare API token: ' TF_VAR_cf_bootstrap_token && \\"
echo "    export TF_VAR_cf_bootstrap_token && \\"
echo "    cd ${PROVISIONING_DIR} && terraform init && terraform apply && \\"
echo "    unset TF_VAR_cf_bootstrap_token"
echo ""

read -p "TF apply complete? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

# --- Token extraction + smoke-test ---

echo ""
echo "--- Smoke-test: verifying scoped token ---"

cd "$PROVISIONING_DIR"
VERIFY_RESULT=$(terraform output -raw cf_deploy_token | (
  read -r TOKEN
  curl -sS -H "Authorization: Bearer $TOKEN" \
    https://api.cloudflare.com/client/v4/user/tokens/verify
))
cd - >/dev/null

CREATED_RESOURCES+=("cd ${PROVISIONING_DIR} && terraform destroy")

TOKEN_STATUS=$(echo "$VERIFY_RESULT" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
if [[ "$TOKEN_STATUS" == "active" ]]; then
  echo "Smoke-test passed: scoped token is active."
else
  echo "Warning: Token verify returned status '${TOKEN_STATUS:-unknown}'. Full response:" >&2
  echo "$VERIFY_RESULT" >&2
fi

# --- Wrangler fallback ---

if command -v wrangler >/dev/null 2>&1; then
  echo ""
  echo "Wrangler verify (bonus):"
  cd "$PROVISIONING_DIR"
  terraform output -raw cf_deploy_token | (
    read -r T
    CLOUDFLARE_API_TOKEN="$T" wrangler whoami 2>&1 || true
  )
  cd - >/dev/null
fi

echo ""
echo "Next step: soleur:provision-hetzner ${SLUG}"
