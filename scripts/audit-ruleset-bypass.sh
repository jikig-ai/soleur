#!/usr/bin/env bash
# Audit live CI Required ruleset bypass_actors against the in-repo canonical.
#
# Runs daily from .github/workflows/scheduled-ruleset-bypass-audit.yml.
# Drift = the live `bypass_actors` array on ruleset #14145388 does not
# canonicalize-equal scripts/ci-required-ruleset-canonical-bypass-actors.json.
#
# Brand-survival threshold: single-user incident (carries forward from
# #2719/#3542 R15). A widened bypass_actors entry would let a malicious
# skill-install PR merge without the `skill-security-scan PR gate` running;
# one merged skill-install = installable-skill code-execution on any
# operator who pulls. This is the audit-log-only blind spot in the R15
# mitigation -- scripts/update-ci-required-ruleset.sh PUTs bypass_actors
# verbatim from the live snapshot, so an admin-broadening between two
# PUTs leaves no repo-side trace.
#
# Trust model: NOT `set -e`. Collect failure modes via record_failure();
# emit failure_mode / failure_detail / failure_label to $GITHUB_OUTPUT
# (one key=value per line). The workflow routes to ci/auth-broken (drift
# detected) or ci/guard-broken (audit malfunctioned). Mirror of
# scheduled-github-app-drift-guard.yml's 3-output failure-routing model.
#
# Test-only env vars (documented for tests/scripts/test-audit-ruleset-bypass.sh):
#   AUDIT_FETCH_OVERRIDE          path to a file with mocked live JSON;
#                                 if set, skip the curl fetch entirely
#   AUDIT_HTTP_CODE_OVERRIDE      simulate a non-200 HTTP code from the
#                                 fetch step (e.g. "503"); requires
#                                 AUDIT_FETCH_OVERRIDE to also be set
#   AUDIT_CANONICAL_FILE_OVERRIDE override the canonical JSON path
#
# Refs: #3544 (this audit), #3542 (parent R15 mitigation), #2719 (R15 origin).

# NOT set -e (collect failure modes, single-pass emit).
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CANONICAL_FILE="${AUDIT_CANONICAL_FILE_OVERRIDE:-${SCRIPT_DIR}/ci-required-ruleset-canonical-bypass-actors.json}"
RULESET_URL="https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388"

# Shared jq projection (must match scripts/update-ci-required-ruleset.sh
# post-PUT verification). See scripts/lib/canonicalize-bypass-actors.sh.
# shellcheck source=scripts/lib/canonicalize-bypass-actors.sh
. "${SCRIPT_DIR}/lib/canonicalize-bypass-actors.sh"

# Emit-once state. Mirrors drift-guard's record_failure (yaml :91-110).
failure_mode=""
failure_detail=""
failure_label=""

record_failure() {
  local mode="$1"
  local detail="$2"
  local label="$3"
  case "$label" in
    ci/auth-broken|ci/guard-broken) ;;
    *)
      echo "::warning::record_failure called with unknown label '$label' — routing as ci/guard-broken" >&2
      label="ci/guard-broken"
      ;;
  esac
  if [[ -z "$failure_mode" ]]; then
    failure_mode="$mode"
    failure_detail="$detail"
    failure_label="$label"
  fi
}

# Sanitize for $GITHUB_OUTPUT: strip CR/LF/FF/VT/DEL + U+0085 (NEL) +
# U+2028 (LS) + U+2029 (PS). The latter two render as line breaks in
# markdown issue bodies and would break the key=value contract for
# $GITHUB_OUTPUT (NL is the record separator). Mirror of drift-guard's
# strip_log_injection (yaml :279-284). Per AGENTS.md
# cq-regex-unicode-separators-escape-only, the U+2028/U+2029 byte
# sequences are spelled out as explicit hex (\xe2\x80\xa8, \xe2\x80\xa9).
strip_log_injection() {
  # POSIX/GNU/uutils tr supports \NNN octal but NOT \xHH hex escapes —
  # empirically: `echo "f" | tr -d '\x7f'` strips 'f', not DEL. Use \177
  # for portability. The drift-guard precedent at
  # .github/workflows/scheduled-github-app-drift-guard.yml:283 uses
  # `\x7f` and is tracked in issue #3561 for a separate fix.
  tr -d '\r\n\f\v\177' | sed -e 's/\xc2\x85//g' -e 's/\xe2\x80\xa8//g' -e 's/\xe2\x80\xa9//g'
}

# Fetch live ruleset. Tests bypass via AUDIT_FETCH_OVERRIDE.
LIVE_FILE=""
HTTP_CODE=""
LIVE_FILE_OWNED=0  # set when we mktemp'd it ourselves (governs trap cleanup)

# fetch_live() — one curl shot. Returns HTTP code via $HTTP_CODE.
# Token goes via stdin (--header @-) to keep it out of process-substitution
# /proc/<pid>/cmdline visibility. Pinned --max-time 15 (Sharp Edge).
fetch_live() {
  HTTP_CODE=$(printf 'Authorization: Bearer %s' "$GH_TOKEN" \
    | curl -s --max-time 15 -w '%{http_code}' \
      -o "$LIVE_FILE" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      --header @- \
      "$RULESET_URL") || HTTP_CODE="network_error"
}

if [[ -n "${AUDIT_FETCH_OVERRIDE:-}" ]]; then
  LIVE_FILE="$AUDIT_FETCH_OVERRIDE"
  HTTP_CODE="${AUDIT_HTTP_CODE_OVERRIDE:-200}"
else
  LIVE_FILE=$(mktemp -p "${RUNNER_TEMP:-/tmp}" live-ruleset.XXXXXX)
  LIVE_FILE_OWNED=1
  trap '[[ "$LIVE_FILE_OWNED" == "1" && -n "$LIVE_FILE" ]] && rm -f "$LIVE_FILE"' EXIT
  if [[ -z "${GH_TOKEN:-}" ]]; then
    record_failure "missing_gh_token" \
      "GH_TOKEN env var is not set" \
      "ci/guard-broken"
  else
    fetch_live
    # Single retry on transient errors (network or 5xx). Avoids paging
    # operators every time GitHub has a 15s blip. Daily cadence × no
    # retry = alarm fatigue. One retry × 5s pause = acceptable noise floor.
    if [[ "$HTTP_CODE" == "network_error" ]] \
       || [[ "$HTTP_CODE" =~ ^5[0-9][0-9]$ ]]; then
      sleep 5
      fetch_live
    fi
  fi
fi

# Inspect fetch result.
if [[ -z "$failure_mode" ]]; then
  if [[ "$HTTP_CODE" == "network_error" ]]; then
    record_failure "github_api_network" \
      "curl ${RULESET_URL} -> network error" \
      "ci/guard-broken"
  elif [[ "$HTTP_CODE" != "200" ]]; then
    record_failure "github_api_http" \
      "GET /rulesets/14145388 -> HTTP ${HTTP_CODE}" \
      "ci/guard-broken"
  elif ! jq -e . "$LIVE_FILE" >/dev/null 2>&1; then
    record_failure "github_api_invalid_json" \
      "live ruleset body is not valid JSON" \
      "ci/guard-broken"
  fi
fi

# Extract live bypass_actors. The override file may be either:
#   - a top-level array (the bypass_actors array directly), OR
#   - a top-level object (the full ruleset response, .bypass_actors inside)
# Tests use both shapes (array shape is the more common mocking pattern).
LIVE_BYPASS=""
if [[ -z "$failure_mode" ]]; then
  if jq -e 'type == "array"' "$LIVE_FILE" >/dev/null 2>&1; then
    LIVE_BYPASS=$(jq -c '.' "$LIVE_FILE")
  elif jq -e 'type == "object"' "$LIVE_FILE" >/dev/null 2>&1; then
    if jq -e '.bypass_actors // null | type == "array"' "$LIVE_FILE" >/dev/null 2>&1; then
      LIVE_BYPASS=$(jq -c '.bypass_actors' "$LIVE_FILE")
    else
      record_failure "live_missing_bypass_actors" \
        "live ruleset response has no .bypass_actors array" \
        "ci/guard-broken"
    fi
  else
    record_failure "github_api_invalid_json" \
      "live ruleset body is neither array nor object" \
      "ci/guard-broken"
  fi
fi

# Load canonical.
CANONICAL_BYPASS=""
if [[ -z "$failure_mode" ]]; then
  if [[ ! -f "$CANONICAL_FILE" ]]; then
    record_failure "canonical_file_missing" \
      "canonical file not found at ${CANONICAL_FILE}" \
      "ci/guard-broken"
  elif ! jq -e . "$CANONICAL_FILE" >/dev/null 2>&1; then
    record_failure "canonical_file_invalid_json" \
      "canonical file at ${CANONICAL_FILE} is not valid JSON" \
      "ci/guard-broken"
  elif ! jq -e 'type == "array"' "$CANONICAL_FILE" >/dev/null 2>&1; then
    record_failure "canonical_file_invalid_json" \
      "canonical file is not a top-level JSON array" \
      "ci/guard-broken"
  elif ! jq -e 'all(.[]; (.actor_id == null or (.actor_id | type == "number")) and (.actor_type | type == "string") and (.bypass_mode | type == "string"))' "$CANONICAL_FILE" >/dev/null 2>&1; then
    # Schema guard: hand-edit could quote "5" as a string, or omit a
    # required field. Surfaces drift as guard-broken (operator error)
    # vs auth-broken (real ruleset edit) — different triage path.
    record_failure "canonical_file_invalid_schema" \
      "canonical entries must have string actor_type, null|number actor_id, string bypass_mode" \
      "ci/guard-broken"
  else
    CANONICAL_BYPASS=$(jq -c '.' "$CANONICAL_FILE")
  fi
fi

# Canonicalize + compare. The map({actor_type, actor_id, bypass_mode})
# projection BEFORE sort_by is load-bearing: it collapses
# missing-actor_id-key entries to {actor_id: null}, so the
# null-vs-missing-key trap from the GitHub API contract doesn't surface as
# a false-positive drift signal. See plan Risk #2 + Research Reconciliation.
if [[ -z "$failure_mode" ]]; then
  live_canonical=$(printf '%s' "$LIVE_BYPASS" | jq -c "$CANONICALIZE_BYPASS_ACTORS_JQ")
  canonical_canonical=$(printf '%s' "$CANONICAL_BYPASS" | jq -c "$CANONICALIZE_BYPASS_ACTORS_JQ")
  if [[ "$live_canonical" != "$canonical_canonical" ]]; then
    # Cap detail length to keep markdown/email rendering bounded; the
    # full diff is recoverable from the run log. Sanitation downstream
    # also strips control chars from this string.
    drift_detail="live=${live_canonical}; canonical=${canonical_canonical}"
    if [[ ${#drift_detail} -gt 500 ]]; then
      drift_detail="${drift_detail:0:500}…(truncated; see run log)"
    fi
    record_failure "bypass_actors_drift" \
      "$drift_detail" \
      "ci/auth-broken"
  fi
fi

# Emit outputs (sanitized).
fail_mode_safe=$(printf '%s' "$failure_mode" | strip_log_injection)
fail_detail_safe=$(printf '%s' "$failure_detail" | strip_log_injection)
fail_label_safe=$(printf '%s' "$failure_label" | strip_log_injection)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "failure_mode=${fail_mode_safe}"
    echo "failure_detail=${fail_detail_safe}"
    echo "failure_label=${fail_label_safe}"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -n "$fail_mode_safe" ]]; then
  echo "::warning::Ruleset bypass audit failed: ${fail_mode_safe} — ${fail_detail_safe} (label=${fail_label_safe})"
else
  echo "Ruleset bypass audit passed."
fi

# Always exit 0 — failure modes ride on $GITHUB_OUTPUT, not exit codes.
exit 0
