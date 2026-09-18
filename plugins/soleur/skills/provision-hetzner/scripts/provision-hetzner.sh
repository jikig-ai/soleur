#!/usr/bin/env bash
# The proving consumer for plugins/soleur/scripts/lib/operator-script.sh (#8287
# Phase 4). The `--dry-run` stdout is pinned byte-for-byte by
# test/provision-hetzner-characterization.test.sh; that golden is the safety net
# for this refactor and it must stay byte-identical.
set -euo pipefail

# --- PROLOGUE (must stay ABOVE the `source` line) ----------------------------
# Duplicated here, never moved into the library — see "SOURCING PRECONDITIONS"
# §2 in plugins/soleur/scripts/lib/operator-script.sh for why.
#
# UNCONDITIONAL, not the conditional `${HCLOUD_TOKEN:+x}` arm: this script
# ACQUIRES its token with `read -rs` BELOW this point, so the variable is empty
# at guard time and a conditional arm would be open by construction. The linter
# cannot see that — its ACQUIRES set knows `doppler secrets get` / `gh auth
# token` / `_TOKEN="$(`, not `read -rs`.
#
# Stdout, not stderr: agent runtimes surface stdout and swallow stderr.
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n'
    exit 78
    ;;
esac

# SSLKEYLOGFILE writes TLS session keys to disk; the smoke test must not
# inherit it. The CA-pool variables (SSL_CERT_FILE, SSL_CERT_DIR,
# CURL_CA_BUNDLE) are deliberately NOT stripped: `hcloud` is a Go client that
# reads them for its root pool, and a founder behind a TLS-inspecting proxy
# would otherwise see an x509 failure on the billable smoke test reported as
# "token lacks write scope" (the credential linter requires only the xtrace
# refusal above — measured).
unset SSLKEYLOGFILE

# --- shared operator-script library ------------------------------------------
# Sourced, never inlined: there is one distribution mode and therefore no copy to
# drift from. The library supplies the prompt classes, the run ledger and the
# secret-write helpers. The `read -rs` below STAYS IN THIS FILE — the prompt
# string is the operator-facing product, and the prologue rule above is why the
# surround cannot be moved either.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# An override must be ABSOLUTE, for the reason template.sh states at its own
# resolution ladder: `-r` tests a relative name against cwd while `source`
# searches PATH for it, so a relative value can pass the readability check and
# then source a DIFFERENT file into a shell that is about to hold a live token.
# The generated scripts have carried this guard since R26; the proving consumer
# is the one place it was missing.
if [[ -n "${SOLEUR_OP_LIB:-}" && "${SOLEUR_OP_LIB}" != /* ]]; then
  printf 'SOLEUR_BOOTSTRAP_BAD_ARG var=SOLEUR_OP_LIB reason=must-be-absolute value=%s\n' "$SOLEUR_OP_LIB"
  exit 64
fi
SOLEUR_OP_LIB="${SOLEUR_OP_LIB:-${SCRIPT_DIR}/../../../scripts/lib/operator-script.sh}"
if [[ ! -r "$SOLEUR_OP_LIB" ]]; then
  printf 'SOLEUR_BOOTSTRAP_LIB_MISSING path=%s\n' "$SOLEUR_OP_LIB"
  exit 64
fi
# shellcheck source=../../../scripts/lib/operator-script.sh disable=SC1091
source "$SOLEUR_OP_LIB"
# API contract (library header §API): prints nothing on success. EQUALITY, not
# -ge — the library auto-updates with the plugin; see the template's comment.
[[ ${SOLEUR_OP_LIB_API:-0} -eq 1 ]] || {
  printf 'SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=1 got=%s\n' "${SOLEUR_OP_LIB_API:-0}"
  exit 64
}

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
awk -F'|' -v slug="$SLUG" '/^\|/ { gsub(/^ +| +$/, "", $2); if ($2 == slug) found = ($8 ~ /^ *(dpa-signed|provisioning-in-progress) *$/) } END { exit !found }' "$DPA_FILE" \
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

# Run ledger home. The library's default is "beside the main script", which for
# THIS script is the plugin tree (a marketplace cache, untracked, not ignored —
# review P2-19). The DPA gate above already requires cwd to be the monorepo
# root, so the ledger goes under its `.soleur/` (gitignored). Set AFTER the
# dry-run branch so the golden stdout is untouched, and BEFORE ledger_init.
: "${SOLEUR_BOOTSTRAP_LEDGER:=$(pwd)/.soleur/bootstrap-runs.jsonl}"
export SOLEUR_BOOTSTRAP_LEDGER

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

soleur_op_ledger_init 2 "provision-hetzner.sh"
soleur_op_stage_begin 1 "operator mints the project-scoped token"

# CLASS 3 — out-of-band completion barrier. It attests that a human did something
# OUTSIDE this script, so it takes a named skip variable AND is followed by an
# independent verification: the write-class smoke test below fails if the
# attestation was false. Today's behaviour was fail-closed but MUTE — EOF read
# into an empty ACK and `exit 1` with "Aborted.", the right outcome with an
# unattributed cause. Now: SOLEUR_BOOTSTRAP_INPUT_REQUIRED and exit 64.
soleur_op_barrier SOLEUR_BOOTSTRAP_SKIP_HETZNER_TOKEN_BARRIER "Token created? Type 'yes' to continue: "

# --- Accept token + smoke-test ---

echo ""
echo "--- Write-class smoke-test ---"
echo "Creating + deleting probe server '${PROBE_NAME}' (cx11, nbg1) to verify token scope."
echo ""

# Credential ENTRY. The library supplies the SURROUND (named skip variable, TTY
# gate, exit 64 naming the variable); the `read -rs` itself stays in this file
# because the prompt string is the operator-facing product (plan D12). The
# library's class-1 helper echoes its input and is for non-secret values only.
#
# The TTY gate sits ABOVE the read, never below it: the property is about the
# instant BEFORE the read, and a check that runs after it cannot see the hang.
hcloud_token_skip="$(soleur_op_skip_value SOLEUR_BOOTSTRAP_HCLOUD_TOKEN)"
if [[ -n "$hcloud_token_skip" ]]; then
  HCLOUD_TOKEN="$hcloud_token_skip"
else
  [[ -t 0 ]] || soleur_op_input_required SOLEUR_BOOTSTRAP_HCLOUD_TOKEN
  read -rs -p "Hetzner project-scoped API token: " HCLOUD_TOKEN
  echo ""
fi
unset hcloud_token_skip

soleur_op_stage_end 1 "operator mints the project-scoped token" ok 0
soleur_op_stage_begin 2 "write-class smoke test (billable)"

# CLASS 2 — per-command destructive-write acknowledgement, and it takes NO SKIP
# VARIABLE by design. `hcloud server create` below bills a real server, and this
# file had no acknowledgement in front of it: the existing "Token created?" ack
# acknowledges TOKEN CREATION and is separated from the create by the token read.
# Giving this one an environment-variable escape would be exactly the "prior
# approval extending to a new command" that hr-menu-option-ack-not-prod-write-auth
# forbids — an unattended billable create introduced by the machinery that claims
# to prevent it (plan revision R8).
soleur_op_ack_or_die "Create the billable probe server '${PROBE_NAME}' now? Type 'yes': "

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

soleur_op_stage_end 2 "write-class smoke test (billable)" ok 0

echo ""
echo "Smoke-test passed: token has write scope for sub-project 'tenant-${SLUG}-prd'."
echo ""
echo "Next step: soleur:provision-github ${SLUG} <org> <reviewer>"
