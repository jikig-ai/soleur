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
#   $1              path to variables.tf   (default: <repo>/apps/web-platform/infra/variables.tf)
#   $DERIVE_CONTEXT optional call-site tag, echoed into every ::error:: so an operator can tell
#                   a PRE-destroy failure from one in the post-destroy refill leg
#   stdout          the resolved base, and NOTHING else — callers command-substitute it
#   stderr          one machine-greppable resolution line
#   exit            0 on success; 1 with an `::error::` naming the file and variable on failure
#
# FAIL-CLOSED. Every exit path that cannot produce a verified base is non-zero. A gate that
# authorizes an irreversible destroy must never let "I could not check" read as "it is fine".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VAR_NAME="app_domain_base"
# The sibling variable that names the FULL host. Kept in sync with the base by convention only
# (see the divergence guard below) — nothing in Terraform constrains the two.
HOST_VAR_NAME="app_domain"

# CWD-INDEPENDENT by construction: derived from this script's own location, never from `pwd`
# and never from the environment. An earlier revision preferred `$GITHUB_WORKSPACE` over the
# script's own root, which INVERTED the property this comment claims: under a `path:`-scoped
# checkout, a reusable workflow with two checkouts, or this repo's documented worktree flow, an
# exported GITHUB_WORKSPACE would make the script read a DIFFERENT tree than the one it lives
# in. In GitHub Actions the two are identical, so the env tier only ever bought a way to be
# wrong.
TF_FILE="${1:-${REPO_ROOT}/apps/web-platform/infra/variables.tf}"

die() {
  printf '::error::derive-app-domain-base%s: %s\n' "${DERIVE_CONTEXT:+[${DERIVE_CONTEXT}]}" "$*" >&2
  exit 1
}

# Reads `default = "<value>"` for a variable.
#
# Anchored on the variable name PLUS its opening brace, so `app_domain_base` cannot prefix-match
# a sibling `app_domain_base_legacy`, and BRACE-DEPTH-TRACKED so a nested block cannot end the
# search early or leak a nested default. Both matter against the real file: `variables.tf`
# already carries validation blocks, and a `validation { … }` placed ABOVE `default` made an
# earlier revision abort with "has no readable default" — re-arming, via a routine Terraform
# edit, the exact "gate aborts before reaching its destroy-guard" defect this script removes.
#
# A trailing `# comment` on the default line is stripped for the same reason: it previously
# parsed as part of the value and tripped the whitespace guard.
#
# The exit status of this pipeline is NOT trustworthy — awk exits 0 whether or not it printed.
# The caller MUST test for emptiness instead. That is the exact bug class the original gate
# shipped, so it is stated here rather than assumed.
read_default() {
  awk -v name="$2" '
    {
      line = $0
      # Entering the block CONSUMES the opening line rather than skipping it, so a one-line
      # `variable "x" { default = "y" }` is parsed too. Skipping it left the divergence guard
      # below silently no-op on exactly that shape — a fail-open inside the guard added to
      # close a fail-open.
      if (!inblock) {
        if (line !~ "^[[:space:]]*variable[[:space:]]+\"" name "\"[[:space:]]*\\{") next
        inblock = 1; depth = 1
        sub("^[[:space:]]*variable[[:space:]]+\"" name "\"[[:space:]]*\\{", "", line)
      }
      sub(/[[:space:]]*#.*$/, "", line)

      if (depth == 1 && line ~ /^[[:space:]]*default[[:space:]]*=/) {
        val = line
        sub(/^[[:space:]]*default[[:space:]]*=[[:space:]]*/, "", val)
        sub(/[[:space:]]*\}[[:space:]]*$/, "", val)
        sub(/[[:space:]]*$/, "", val)
        # A bare HCL expression (`local.base`, `var.x`) is NOT a domain literal. Printing it
        # verbatim would fabricate a hostname that still passes a dot check, so require the
        # value to have been a quoted string and fail closed otherwise.
        if (val ~ /^".*"$/) {
          sub(/^"/, "", val)
          sub(/"$/, "", val)
          print val
        }
        exit
      }

      tmp = line; n_open  = gsub(/\{/, "", tmp)
      tmp = line; n_close = gsub(/\}/, "", tmp)
      depth += n_open - n_close
      if (depth <= 0) exit
    }
  ' "$1"
}

# Rejects anything that would corrupt the URL it gets interpolated into. The guard sits AFTER
# precedence resolution, at the single consumption point, so an override is policed identically
# to a committed default.
validate_base() {
  local value="$1"
  local lower="${value,,}"

  case "$value" in
    *://*)         die "value '${value}' contains a URI scheme; expected a bare domain" ;;
    */*)           die "value '${value}' contains a slash; expected a bare domain" ;;
    *[[:space:]]*) die "value '${value}' contains whitespace; expected a bare domain" ;;
  esac

  # ONE arm closes every character that can relocate or reshape the URL. The sharpest is `@`:
  # `https://app.x@evil.com/health` sends the request to evil.com with `app.x` as userinfo —
  # and both consumers make that catastrophic rather than merely wrong. The D10 gate reads that
  # host's /health to DEFINE the restore set, and cf-tunnel-registry-bridge interpolates the
  # same value into `--hostname`, where cloudflared presents the production CF Access service
  # token. Also closes `:` (port), `?` (query), `#` (fragment), `%` (percent-encoding), quote
  # and backslash injection into the double-quoted URL, and non-ASCII IDN homoglyphs.
  case "$value" in
    *[!a-zA-Z0-9.-]*) die "value '${value}' contains a character that is not a letter, digit, dot or hyphen" ;;
  esac

  # Case-insensitive: the callers prepend `app.`, and a case-varied `App.` would otherwise slip
  # through to https://app.App.soleur.ai/health.
  case "$lower" in
    app.*) die "value '${value}' already begins with 'app.'; the callers prepend it, which would yield https://app.${value}/health" ;;
  esac

  case "$value" in
    .*|*.|-*|*-) die "value '${value}' begins or ends with a dot or hyphen; expected a well-formed domain" ;;
    *..*)        die "value '${value}' contains an empty label; expected a well-formed domain" ;;
    *.*)         : ;;
    *)           die "value '${value}' contains no dot; expected a base domain such as soleur.ai" ;;
  esac
}

[[ -f "$TF_FILE" ]] || die "cannot read '${TF_FILE}' — the file that declares variable \"${VAR_NAME}\" does not exist"

BASE=""
SOURCE="$TF_FILE"

# An explicit Terraform variable override, honoured ahead of the committed default so that a
# caller which DOES inject one is not silently ignored.
#
# READ THIS BEFORE TRUSTING IT AS PRECEDENCE PARITY. `TF_VAR_*` reaches Terraform only inside
# the `doppler run -p soleur -c prd_terraform --name-transformer tf-var --` wrappers around the
# apply steps. None of this script's call sites runs under such a wrapper, so at the D10 arms
# and in the restore leg this branch is unreachable in CI today. It is defence for a future
# caller that exports the variable, NOT a claim that this script observes Terraform's live
# precedence. The divergence guard below is what actually protects the gate.
TF_VAR_OVERRIDE="TF_VAR_${VAR_NAME}"
if [[ -n "${!TF_VAR_OVERRIDE:-}" ]]; then
  BASE="${!TF_VAR_OVERRIDE}"
  SOURCE="$TF_VAR_OVERRIDE"
else
  BASE="$(read_default "$TF_FILE" "$VAR_NAME")" || BASE=""
  [[ -n "$BASE" ]] || die "variable \"${VAR_NAME}\" has no readable quoted 'default =' in '${TF_FILE}'"
fi

validate_base "$BASE"

# ── DIVERGENCE GUARD ────────────────────────────────────────────────────────────────────────
# The consumers rebuild the host by CONVENTION (`https://app.${base}/health`), but the fleet
# also declares the full host as its own variable, and nothing in Terraform constrains the two
# to agree. That matters because `app_domain` HAS a live override lever and `app_domain_base`
# does not: `APP_DOMAIN` is present in Doppler `prd_terraform` (measured 2026-08-06), so
# `TF_VAR_app_domain` is injected on every apply, while `APP_DOMAIN_BASE` exists in no config.
#
# So a domain move performed the only way it can be performed today moves production while this
# derivation keeps returning the old base — and if the old host still answers /health with a
# parseable version, the gate goes GREEN having measured the wrong host and authorizes the
# destroy on its inventory. Asserting the two committed values agree turns that from a silent
# wrong-host read into a loud abort.
#
# Scope, stated honestly: this compares the two COMMITTED defaults. It cannot see a live
# `TF_VAR_app_domain` override, because reading Doppler is what this change removed from the
# gate. The cold-vehicle check in the runbook covers that half.
HOST=""
HOST="$(read_default "$TF_FILE" "$HOST_VAR_NAME")" || HOST=""
if [[ -n "$HOST" && "$HOST" != "app.${BASE}" ]]; then
  die "variables.tf declares ${HOST_VAR_NAME}='${HOST}' but ${VAR_NAME}='${BASE}' yields 'app.${BASE}' — the two disagree, so the /health host the gate would measure is not the host the fleet serves. Reconcile them in '${TF_FILE}'."
fi

# Diagnostics on stderr ONLY — stdout is the value and nothing else.
printf 'derive-app-domain-base%s: base=%s source=%s health_url=https://app.%s/health\n' \
  "${DERIVE_CONTEXT:+[${DERIVE_CONTEXT}]}" "$BASE" "$SOURCE" "$BASE" >&2

printf '%s\n' "$BASE"
