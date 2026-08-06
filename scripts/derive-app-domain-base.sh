#!/usr/bin/env bash
# Resolve the application's BASE domain (e.g. `soleur.ai`) from committed Terraform config.
#
# ── WHY THIS EXISTS ─────────────────────────────────────────────────────────────────────────
# The D10 authorization gate for `registry-luks-recut` read APP_DOMAIN_BASE from Doppler
# `soleur/prd` with no fallback and failed closed on empty. That secret exists in NO config of
# the `soleur` project — measured 2026-08-06 across all 13. So the gate aborted at PREPARE
# before reaching its own destroy-guard, making the dispatch unfireable during exactly the
# incident it exists to recover from.
#
# The name was not invented: `server.tf` sets `APP_DOMAIN_BASE = var.app_domain_base` as a HOST
# env var. It is a DERIVED COPY of the Terraform variable, never a Doppler key. So the causal
# source is `variables.tf`, and reading Doppler could at best have re-read a copy of it.
# `.github/actions/cf-tunnel-registry-bridge/action.yml` already stated this correctly in a
# comment ("APP_DOMAIN_BASE is not in prd") while the D10 comment asserted the opposite.
#
# ── CONTRACT ────────────────────────────────────────────────────────────────────────────────
#   $1     path to variables.tf   (default: <repo>/apps/web-platform/infra/variables.tf,
#                                  overridable via $GITHUB_WORKSPACE)
#   stdout the resolved base, and NOTHING else — callers command-substitute it
#   stderr one machine-greppable resolution line
#   exit   0 on success; 1 with an `::error::` naming the file and variable on any failure
#
# PRECEDENCE mirrors Terraform's own: an explicit `TF_VAR_app_domain_base` wins over the
# committed `default =`. Without that tier this reports "what Terraform WOULD apply absent an
# override" rather than "what Terraform applied" — and the whole point of the inversion is that
# the value is causally what production runs on.
#
# FAIL-CLOSED. Every exit path that cannot produce a verified base is non-zero. A gate that
# authorizes an irreversible destroy must never let "I could not check" read as "it is fine".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VAR_NAME="app_domain_base"

# CWD-INDEPENDENT by construction: derived from this script's own location, not `pwd`. Several
# steps in apply-web-platform-infra.yml set `working-directory:`, and the discoverability
# contract requires the script to run from any checkout.
DEFAULT_TF="${GITHUB_WORKSPACE:-${REPO_ROOT}}/apps/web-platform/infra/variables.tf"
TF_FILE="${1:-$DEFAULT_TF}"

die() {
  printf '::error::derive-app-domain-base: %s\n' "$*" >&2
  exit 1
}

# Reads `default = "<value>"` for a variable, anchored on the variable name PLUS its opening
# brace so `app_domain_base` cannot prefix-match a sibling `app_domain_base_legacy`, and
# terminated at the block's closing brace so a later variable's default cannot bleed in.
#
# The exit status of this pipeline is NOT trustworthy — it ends in `head`/`sed`, which exit 0
# even when the variable is absent. The caller MUST test for emptiness instead. That is the
# exact bug class the original gate shipped, so it is stated here rather than assumed.
read_default() {
  awk -v name="$VAR_NAME" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" name "\"[[:space:]]*\\{" { inblock = 1; next }
    inblock && /^[[:space:]]*\}/ { inblock = 0 }
    inblock && /^[[:space:]]*default[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*default[[:space:]]*=[[:space:]]*/, "", line)
      gsub(/^"|"[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$1"
}

# Rejects anything that would corrupt the URL it gets interpolated into. The guard sits AFTER
# precedence resolution, at the single consumption point, so an override is policed identically
# to a committed default.
validate_base() {
  local value="$1"
  case "$value" in
    *://*)            die "value '${value}' contains a URI scheme; expected a bare domain" ;;
    */*)              die "value '${value}' contains a slash; expected a bare domain" ;;
    *[[:space:]]*)    die "value '${value}' contains whitespace; expected a bare domain" ;;
    app.*)            die "value '${value}' already begins with 'app.'; the callers prepend it, which would yield https://app.${value}/health" ;;
    *.*)              : ;;
    *)                die "value '${value}' contains no dot; expected a base domain such as soleur.ai" ;;
  esac
}

BASE=""
SOURCE=""

# Tier 1 — an explicit Terraform variable override (what `--name-transformer tf-var` produces
# from a Doppler `APP_DOMAIN_BASE` entry in the prd_terraform config).
if [[ -n "${TF_VAR_app_domain_base:-}" ]]; then
  BASE="${TF_VAR_app_domain_base}"
  SOURCE="TF_VAR_app_domain_base"
else
  # Tier 2 — the committed default. This is the measured state today: no override exists in
  # any Doppler config, so `variables.tf` IS what Terraform applied.
  [[ -f "$TF_FILE" ]] || die "cannot read '${TF_FILE}' — the file that declares variable \"${VAR_NAME}\" does not exist"

  # `local`-free at top level, and deliberately NOT `BASE=$(read_default …)` on one line with a
  # declaration: `local x=$(cmd)` swallows the command's exit status even under `set -e`.
  BASE="$(read_default "$TF_FILE")" || BASE=""
  SOURCE="$TF_FILE"

  [[ -n "$BASE" ]] || die "variable \"${VAR_NAME}\" has no readable 'default =' in '${TF_FILE}'"
fi

validate_base "$BASE"

# Diagnostics on stderr ONLY — stdout is the value and nothing else.
printf 'derive-app-domain-base: base=%s source=%s health_url=https://app.%s/health\n' \
  "$BASE" "$SOURCE" "$BASE" >&2

printf '%s\n' "$BASE"
