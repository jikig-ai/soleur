#!/usr/bin/env bash
set -euo pipefail

SLUG=""
TENANT_ORG=""
TENANT_REPO=""
DRY_RUN=false

usage() {
  echo "Usage: provision-doppler <tenant-slug> <tenant-org> <tenant-repo> [--dry-run]" >&2
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
      elif [[ -z "$TENANT_REPO" ]]; then TENANT_REPO="$1"
      else echo "Unexpected argument: $1" >&2; usage
      fi
      shift ;;
  esac
done

[[ -n "$SLUG" ]] || { echo "Error: tenant-slug is required." >&2; usage; }
[[ -n "$TENANT_ORG" ]] || { echo "Error: tenant-org is required." >&2; usage; }
[[ -n "$TENANT_REPO" ]] || { echo "Error: tenant-repo is required." >&2; usage; }

if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Error: tenant-slug must be kebab-case (e.g. 'acme-prd')." >&2
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
  echo "Bootstrap cleanup: Revoke the Doppler personal token used for bootstrapping — it is no longer needed."
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- Pre-checks ---

command -v doppler >/dev/null 2>&1 || { echo "Error: 'doppler' CLI not found. Install: https://docs.doppler.com/docs/install-cli" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: 'curl' not found." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: 'terraform' not found." >&2; exit 1; }

# --- DPA gate ---

DPA_FILE="knowledge-base/legal/tenant-dpa-register.md"
[[ -f "$DPA_FILE" ]] || { echo "DPA register not found at $DPA_FILE. Run from Soleur monorepo root." >&2; exit 3; }
awk -F'|' -v slug="$SLUG" '/^\|/ && $2 ~ slug && $7 ~ /dpa-signed|provisioning-in-progress/' "$DPA_FILE" | grep -q . \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }

# --- Idempotency check ---

if doppler projects 2>/dev/null | grep -q "$SLUG"; then
  echo "WARNING: Doppler project '$SLUG' already exists."
  echo "  Continuing will regenerate TF config. Existing project is unchanged until 'terraform apply'."
  echo ""
fi

# --- Generate TF config ---

mkdir -p "$PROVISIONING_DIR"

cat > "${PROVISIONING_DIR}/doppler.tf" <<'TFEOF'
terraform {
  required_version = ">= 1.5"

  backend "s3" {
TFEOF

cat >> "${PROVISIONING_DIR}/doppler.tf" <<TFEOF
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
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.21"
    }
  }
}

variable "doppler_bootstrap_token" {
  description = "Doppler personal token for bootstrapping (re-entered at apply time)"
  type        = string
  sensitive   = true
}

provider "doppler" {
  doppler_token = var.doppler_bootstrap_token
}

resource "doppler_project" "tenant" {
  name        = "${SLUG}"
  description = "Tenant project for ${SLUG}"
}

resource "doppler_config" "prd" {
  project     = doppler_project.tenant.name
  environment = "prd"
  name        = "prd_tenant_${SLUG}"
}
TFEOF

echo "Generated ${PROVISIONING_DIR}/doppler.tf"

# --- OIDC API commands ---

OIDC_CREATE_CMD="curl -sS -X POST 'https://api.doppler.com/v3/workplace/service_accounts' \\
  -H 'Authorization: Bearer \$DOPPLER_TOKEN' \\
  -H 'Content-Type: application/json' \\
  -d '{\"name\": \"${SLUG}-deploy\", \"workplace_role\": {\"identifier\": \"viewer\"}}'"

OIDC_TRUST_CMD="# After creating the service account, configure OIDC trust:
# 1. Get the service account slug from the response above
# 2. Add OIDC identity with two-claim binding:
curl -sS -X POST 'https://api.doppler.com/v3/workplace/service_accounts/\$SA_SLUG/identity' \\
  -H 'Authorization: Bearer \$DOPPLER_TOKEN' \\
  -H 'Content-Type: application/json' \\
  -d '{
    \"type\": \"oidc\",
    \"oidc_identity\": {
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject_claims\": {
        \"repository_owner\": \"${TENANT_ORG}\",
        \"environment\": \"production\"
      }
    }
  }'"

OIDC_GRANT_CMD="# Grant the service account access to the tenant project:
curl -sS -X POST 'https://api.doppler.com/v3/workplace/service_accounts/\$SA_SLUG/projects' \\
  -H 'Authorization: Bearer \$DOPPLER_TOKEN' \\
  -H 'Content-Type: application/json' \\
  -d '{\"project\": \"${SLUG}\", \"role\": \"viewer\"}'"

# --- Dry-run output ---

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN — No changes will be made ==="
  echo ""
  echo "--- Generated Terraform config ---"
  cat "${PROVISIONING_DIR}/doppler.tf"
  echo ""
  echo "--- Copy-pasteable TF apply command ---"
  echo "read -rs -p 'Doppler token: ' TF_VAR_doppler_bootstrap_token && \\"
  echo "  export TF_VAR_doppler_bootstrap_token && \\"
  echo "  cd ${PROVISIONING_DIR} && terraform init && terraform apply && \\"
  echo "  unset TF_VAR_doppler_bootstrap_token"
  echo ""
  echo "--- OIDC service-account commands (run after TF apply) ---"
  echo "$OIDC_CREATE_CMD"
  echo ""
  echo "$OIDC_TRUST_CMD"
  echo ""
  echo "$OIDC_GRANT_CMD"
  echo ""
  echo "--- Smoke-test ---"
  echo "curl -sS -H 'Authorization: Bearer \$DOPPLER_TOKEN' 'https://api.doppler.com/v3/workplace/service_accounts' | jq '.service_accounts[] | select(.name == \"${SLUG}-deploy\")'"
  echo ""
  echo "--- Teardown ---"
  echo "  doppler projects delete '${SLUG}' --yes"
  echo "  # Revoke service account via dashboard: Settings → Service Accounts → ${SLUG}-deploy → Revoke"
  echo "  rm -rf ${PROVISIONING_DIR}"
  echo ""
  echo "Next step: soleur:provision-cloudflare ${SLUG} <zone-id> <account-id>"
  exit 0
fi

# --- Interactive flow ---

echo ""
echo "=== Doppler provisioning for '${SLUG}' ==="
echo ""
echo "This will:"
echo "  1. Apply Terraform to create Doppler project '${SLUG}' + prd config"
echo "  2. Create OIDC service-account '${SLUG}-deploy' via Doppler API"
echo "  3. Configure OIDC trust binding (${TENANT_ORG}/${TENANT_REPO} + production environment)"
echo ""

echo "--- Step 1: Terraform apply ---"
echo ""
echo "Run this command in a separate terminal:"
echo ""
echo "  read -rs -p 'Doppler token: ' TF_VAR_doppler_bootstrap_token && \\"
echo "    export TF_VAR_doppler_bootstrap_token && \\"
echo "    cd ${PROVISIONING_DIR} && terraform init && terraform apply && \\"
echo "    unset TF_VAR_doppler_bootstrap_token"
echo ""

read -p "TF apply complete? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

# --- Verify TF apply ---

if ! doppler projects get "$SLUG" --plain >/dev/null 2>&1; then
  echo "Error: Doppler project '$SLUG' not found. TF apply may not have completed." >&2
  exit 1
fi

CREATED_RESOURCES+=("doppler projects delete '${SLUG}' --yes")
echo "Verified: Doppler project '$SLUG' exists."

# --- Step 2: OIDC service-account via API ---

echo ""
echo "--- Step 2: OIDC service-account ---"
echo ""
echo "Accepting Doppler personal token for API calls (same token used for TF apply)."
read -rs -p "Doppler personal token: " DOPPLER_TOKEN
echo ""

SA_RESPONSE=$(
  curl -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts" \
    -H "Authorization: Bearer $DOPPLER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${SLUG}-deploy\", \"workplace_role\": {\"identifier\": \"viewer\"}}"
)

SA_SLUG=$(echo "$SA_RESPONSE" | grep -o '"slug":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -z "$SA_SLUG" ]]; then
  echo "Error: Failed to create service account. Response:" >&2
  echo "$SA_RESPONSE" >&2
  unset DOPPLER_TOKEN
  exit 1
fi

CREATED_RESOURCES+=("# Revoke service account: Settings → Service Accounts → ${SLUG}-deploy → Revoke")
echo "Created service account: ${SLUG}-deploy (slug: $SA_SLUG)"

# --- Configure OIDC trust binding ---

TRUST_RESPONSE=$(
  curl -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/identity" \
    -H "Authorization: Bearer $DOPPLER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"oidc\",
      \"oidc_identity\": {
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject_claims\": {
          \"repository_owner\": \"${TENANT_ORG}\",
          \"environment\": \"production\"
        }
      }
    }"
)

if echo "$TRUST_RESPONSE" | grep -q '"success"'; then
  echo "Configured OIDC trust: repository_owner=${TENANT_ORG}, environment=production"
else
  echo "Warning: OIDC trust binding response:" >&2
  echo "$TRUST_RESPONSE" >&2
  echo "Verify manually in Doppler dashboard." >&2
fi

# --- Grant project access ---

GRANT_RESPONSE=$(
  curl -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/projects" \
    -H "Authorization: Bearer $DOPPLER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"project\": \"${SLUG}\", \"role\": \"viewer\"}"
)

if echo "$GRANT_RESPONSE" | grep -q '"success"'; then
  echo "Granted service account access to project '${SLUG}'"
else
  echo "Warning: Project grant response:" >&2
  echo "$GRANT_RESPONSE" >&2
fi

# --- Smoke-test ---

echo ""
echo "--- Smoke-test ---"

SA_CHECK=$(
  curl -sS -H "Authorization: Bearer $DOPPLER_TOKEN" \
    "https://api.doppler.com/v3/workplace/service_accounts" \
  | grep -o "\"name\":\"${SLUG}-deploy\""
)

unset DOPPLER_TOKEN

if [[ -n "$SA_CHECK" ]]; then
  echo "Smoke-test passed: service account '${SLUG}-deploy' exists."
else
  echo "Warning: Could not verify service account '${SLUG}-deploy'. Check Doppler dashboard." >&2
fi

echo ""
echo "NOTE: OIDC trust binding cannot be fully verified locally."
echo "Test via deploy workflow (runbook Step 9) after all provisioning."
echo ""
echo "Next step: soleur:provision-cloudflare ${SLUG} <zone-id> <account-id>"
