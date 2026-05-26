#!/usr/bin/env bash
set -euo pipefail

SLUG=""
DRY_RUN=false

usage() {
  echo "Usage: provision-hetzner <tenant-slug> [--dry-run]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage ;;
    -*)        echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$SLUG" ]]; then SLUG="$1"
      else echo "Unexpected argument: $1" >&2; usage
      fi
      shift ;;
  esac
done

[[ -n "$SLUG" ]] || { echo "Error: tenant-slug is required." >&2; usage; }

if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Error: tenant-slug must be kebab-case (e.g. 'acme-prd')." >&2
  exit 1
fi

PROBE_NAME="probe-provision-${SLUG}"
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
  echo "If the probe server '${PROBE_NAME}' was not cleaned up:"
  echo "  hcloud server delete '${PROBE_NAME}'"
  echo ""
  echo "To tear down the Hetzner sub-project:"
  echo "  Delete via Hetzner Console → Projects → tenant-${SLUG}-prd → Delete"
  echo "  (CLI does not support project deletion)"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- Pre-checks ---

command -v hcloud >/dev/null 2>&1 || { echo "Error: 'hcloud' CLI not found. Install: https://github.com/hetznercloud/cli" >&2; exit 1; }

# --- DPA gate ---

DPA_FILE="knowledge-base/legal/tenant-dpa-register.md"
[[ -f "$DPA_FILE" ]] || { echo "DPA register not found at $DPA_FILE. Run from Soleur monorepo root." >&2; exit 3; }
awk -F'|' -v slug="$SLUG" '/^\|/ && $2 ~ slug && $7 ~ /dpa-signed|provisioning-in-progress/' "$DPA_FILE" | grep -q . \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }

# --- Dry-run output ---

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN — No changes will be made ==="
  echo ""
  echo "--- Console guidance ---"
  echo "1. Log in to the tenant's Hetzner Cloud Console"
  echo "2. Create a sub-project named 'tenant-${SLUG}-prd'"
  echo "3. Inside the sub-project, go to Security → API Tokens"
  echo "4. Create a project-scoped API token with Read+Write permissions"
  echo "5. Copy the token (shown only once)"
  echo ""
  echo "--- Smoke-test commands (run after token creation) ---"
  echo "read -rs -p 'Hetzner token: ' HCLOUD_TOKEN; echo"
  echo "("
  echo "  export HCLOUD_TOKEN"
  echo "  hcloud server create --name '${PROBE_NAME}' --type cx11 --image ubuntu-22.04 --location nbg1"
  echo "  hcloud server delete '${PROBE_NAME}'"
  echo ")"
  echo "unset HCLOUD_TOKEN"
  echo ""
  echo "--- Teardown ---"
  echo "  Delete sub-project via Console: Projects → tenant-${SLUG}-prd → Delete"
  echo "  Revoke the API token: Security → API Tokens → Revoke"
  echo ""
  echo "Next step: soleur:provision-github ${SLUG} <org> <reviewer>"
  exit 0
fi

# --- Interactive flow ---

echo ""
echo "=== Hetzner provisioning for '${SLUG}' ==="
echo ""
echo "Hetzner does not have a Terraform resource for project creation or token minting."
echo "Follow these steps in the Hetzner Cloud Console:"
echo ""
echo "  1. Log in to the tenant's Hetzner Cloud master account"
echo "  2. Create a sub-project named 'tenant-${SLUG}-prd'"
echo "  3. Inside the sub-project, go to Security → API Tokens"
echo "  4. Create a project-scoped API token with Read+Write permissions"
echo "  5. Copy the token (shown only once)"
echo ""

read -p "Token created? Type 'yes' to continue: " ACK
[[ "$ACK" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

# --- Accept token + smoke-test ---

echo ""
echo "--- Write-class smoke-test ---"
echo "Creating + deleting probe server '${PROBE_NAME}' (cx11, nbg1) to verify token scope."
echo ""

read -rs -p "Hetzner project-scoped API token: " HCLOUD_TOKEN
echo ""

(
  export HCLOUD_TOKEN
  trap 'echo "Cleaning up probe server..."; hcloud server delete "$PROBE_NAME" 2>/dev/null || true' EXIT INT TERM

  echo "Creating probe server '${PROBE_NAME}'..."
  if ! hcloud server create --name "$PROBE_NAME" --type cx11 --image ubuntu-22.04 --location nbg1; then
    echo "" >&2
    echo "Error: Server creation failed. The token may have insufficient scope." >&2
    echo "Verify the token has Read+Write permissions for this sub-project." >&2
    exit 1
  fi

  CREATED_RESOURCES+=("hcloud server delete '${PROBE_NAME}'")
  echo "Probe server created. Deleting..."

  if ! hcloud server delete "$PROBE_NAME"; then
    echo "" >&2
    echo "Error: Server deletion failed. The probe server '${PROBE_NAME}' may still exist." >&2
    echo "Delete manually: hcloud server delete '${PROBE_NAME}'" >&2
    exit 1
  fi

  echo "Probe server deleted."
)

unset HCLOUD_TOKEN

echo ""
echo "Smoke-test passed: token has write scope for sub-project 'tenant-${SLUG}-prd'."
echo ""
echo "Next step: soleur:provision-github ${SLUG} <org> <reviewer>"
