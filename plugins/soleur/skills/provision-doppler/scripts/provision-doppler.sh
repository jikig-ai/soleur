#!/usr/bin/env bash
set -euo pipefail

# (#7797) Refuse to run under shell tracing. UNCONDITIONAL, and DELIBERATELY not
# the conditional DOPPLER_TOKEN non-emptiness arm the linter offers for this file
# — that arm is vacuous by construction here. This script acquires the operator's
# workplace-scoped Doppler personal token with `read -rs -p "Doppler personal
# token: "` BELOW this point, so the variable is still empty at guard time, the
# arm opens, and `bash -x` goes on to print `Authorization: Bearer dp.pt.…` at
# every API call site. The linter cannot see that: its ACQUIRES set knows
# `doppler secrets get` / `gh auth token` / `_TOKEN="$(`, not `read -rs`.
# Stdout, not stderr, because agent runtimes surface stdout and swallow stderr
# (knowledge-base/project/constitution.md > Code Style).
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n'
    exit 78
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS ITSELF. SSLKEYLOGFILE writes the
# session keys and the CA vars substitute the trust store, so a CURL_CA_BUNDLE
# MITM of the workplace-scoped personal token works with every other guard intact.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

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

if ! [[ "$TENANT_ORG" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
  echo "Error: tenant-org must be a valid GitHub org name (alphanumerics and hyphens)." >&2
  exit 1
fi

if ! [[ "$TENANT_REPO" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: tenant-repo must be a valid GitHub repo name." >&2
  exit 1
fi

PROVISIONING_DIR="provisioning/${SLUG}/doppler"
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
awk -F'|' -v slug="$SLUG" '/^\|/ { gsub(/^ +| +$/, "", $2); if ($2 == slug && $8 ~ /^ *(dpa-signed|provisioning-in-progress) *$/) found=1 } END { exit !found }' "$DPA_FILE" \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }

# --- Idempotency check ---

if doppler projects 2>/dev/null | grep -q "$SLUG"; then
  echo "WARNING: Doppler project '$SLUG' already exists."
  echo "  Continuing will regenerate TF config. Existing project is unchanged until 'terraform apply'."
  echo ""
fi

# --- Generate TF config ---

mkdir -p "$PROVISIONING_DIR"

cat > "${PROVISIONING_DIR}/doppler.tf" <<TFEOF
terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "tenants/${SLUG}/doppler.tfstate"
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
  echo "  (cd ${PROVISIONING_DIR} && terraform init && terraform apply); \\"
  echo "  unset TF_VAR_doppler_bootstrap_token"
  echo ""
  echo "--- OIDC service-account commands (run after TF apply) ---"
  # These printed recipes carry a live bearer, so they must TEACH the confined
  # form: `--disable` literally first (it aborts ~/.curlrc parsing, and later is
  # too late) and `--noproxy '*'` (#7873).
  echo "curl --disable --noproxy '*' -sS -X POST 'https://api.doppler.com/v3/workplace/service_accounts' \\"
  echo "  -H 'Authorization: Bearer \$DOPPLER_TOKEN' \\"
  echo "  -H 'Content-Type: application/json' \\"
  echo "  -d '{\"name\": \"${SLUG}-deploy\", \"workplace_role\": {\"identifier\": \"viewer\"}}'"
  echo ""
  echo "# Then configure OIDC trust with two-claim binding + grant project access"
  echo ""
  echo "--- Smoke-test ---"
  echo "curl --disable --noproxy '*' -sS -H 'Authorization: Bearer \$DOPPLER_TOKEN' 'https://api.doppler.com/v3/workplace/service_accounts' | jq '.service_accounts[] | select(.name == \"${SLUG}-deploy\")'"
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
echo "    (cd ${PROVISIONING_DIR} && terraform init && terraform apply); \\"
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

# --- Step 2: OIDC service-account via API (in subshell for credential quarantine) ---

echo ""
echo "--- Step 2: OIDC service-account ---"
echo ""
echo "Accepting Doppler personal token for API calls (same token used for TF apply)."
read -rs -p "Doppler personal token: " DOPPLER_TOKEN
echo ""

(
  export DOPPLER_TOKEN

  # Payloads are HOISTED into variables rather than written inline. Each curl here
  # sends a credential, and a multi-line `-d "{…}"` literal makes the invocation
  # multi-shaped, which is what the destination-confinement linter mis-parses as an
  # env-settable destination (#7873). The destinations are literal URLs — SA_SLUG
  # comes from the previous response — so there is nothing to pin; hoisting removes
  # the parse artifact by making every invocation single-shaped.
  SA_PAYLOAD="{\"name\": \"${SLUG}-deploy\", \"workplace_role\": {\"identifier\": \"viewer\"}}"

  SA_RESPONSE=$(
    curl --disable --noproxy '*' -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts" \
      -H "Authorization: Bearer $DOPPLER_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$SA_PAYLOAD"
  )

  SA_SLUG=$(echo "$SA_RESPONSE" | grep -o '"slug":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [[ -z "$SA_SLUG" ]]; then
    echo "Error: Failed to create service account. Response:" >&2
    echo "$SA_RESPONSE" >&2
    exit 1
  fi

  echo "Created service account: ${SLUG}-deploy (slug: $SA_SLUG)"

  # --- Configure OIDC trust binding ---

  # Hoisted for the same reason as SA_PAYLOAD above: the two-claim binding is the
  # payload that made this invocation multi-shaped.
  TRUST_PAYLOAD="{\"type\": \"oidc\", \"oidc_identity\": {"
  TRUST_PAYLOAD="${TRUST_PAYLOAD}\"issuer\": \"https://token.actions.githubusercontent.com\","
  TRUST_PAYLOAD="${TRUST_PAYLOAD}\"subject_claims\": {"
  TRUST_PAYLOAD="${TRUST_PAYLOAD}\"repository_owner\": \"${TENANT_ORG}\","
  TRUST_PAYLOAD="${TRUST_PAYLOAD}\"repository\": \"${TENANT_ORG}/${TENANT_REPO}\","
  TRUST_PAYLOAD="${TRUST_PAYLOAD}\"environment\": \"production\"}}}"

  TRUST_RESPONSE=$(
    curl --disable --noproxy '*' -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/identity" \
      -H "Authorization: Bearer $DOPPLER_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$TRUST_PAYLOAD"
  )

  if echo "$TRUST_RESPONSE" | grep -q '"success"'; then
    echo "Configured OIDC trust: repository=${TENANT_ORG}/${TENANT_REPO}, environment=production"
  else
    echo "Warning: OIDC trust binding response:" >&2
    echo "$TRUST_RESPONSE" >&2
    echo "Verify manually in Doppler dashboard." >&2
  fi

  # --- Grant project access ---

  GRANT_PAYLOAD="{\"project\": \"${SLUG}\", \"role\": \"viewer\"}"

  GRANT_RESPONSE=$(
    curl --disable --noproxy '*' -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/projects" \
      -H "Authorization: Bearer $DOPPLER_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$GRANT_PAYLOAD"
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
    curl --disable --noproxy '*' -sS -H "Authorization: Bearer $DOPPLER_TOKEN" \
      "https://api.doppler.com/v3/workplace/service_accounts" \
    | grep -o "\"name\":\"${SLUG}-deploy\""
  )

  if [[ -n "$SA_CHECK" ]]; then
    echo "Smoke-test passed: service account '${SLUG}-deploy' exists."
  else
    echo "Warning: Could not verify service account '${SLUG}-deploy'. Check Doppler dashboard." >&2
  fi
)

unset DOPPLER_TOKEN

CREATED_RESOURCES+=("# Revoke service account: Settings → Service Accounts → ${SLUG}-deploy → Revoke")

echo ""
echo "NOTE: OIDC trust binding cannot be fully verified locally."
echo "Test via deploy workflow (runbook Step 9) after all provisioning."
echo ""
echo "Next step: soleur:provision-cloudflare ${SLUG} <zone-id> <account-id>"
