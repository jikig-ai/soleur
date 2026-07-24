#!/usr/bin/env bash
# Tests for scripts/audit-ruleset-bypass.sh.
# Deterministic; no live API. Uses AUDIT_FETCH_OVERRIDE to bypass curl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/audit-ruleset-bypass.sh"
CANONICAL_REAL="$REPO_ROOT/scripts/ci-required-ruleset-canonical-bypass-actors.json"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Runs the audit script with overridden live + canonical files; captures
# $GITHUB_OUTPUT to a tempfile so the test can inspect failure_mode/label.
# Returns the script's exit status (always 0 — failure modes are emitted
# via $GITHUB_OUTPUT, not exit codes, per the 3-output failure-routing
# model mirrored from scheduled-github-app-drift-guard.yml).
_run() {
  local live_json="$1" canonical_json="$2"
  local tmp; tmp=$(mktemp -d)
  local live="$tmp/live.json" canon="$tmp/canonical.json"
  local output_file="$tmp/output"
  printf '%s' "$live_json" > "$live"
  printf '%s' "$canonical_json" > "$canon"
  : > "$output_file"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$live" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$canon" \
  GITHUB_OUTPUT="$output_file" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  echo "$tmp:$rc"
}

_mode() {
  local tmp="$1"
  grep -E '^failure_mode=' "$tmp/output" | head -1 | cut -d= -f2- || true
}
_label() {
  local tmp="$1"
  grep -E '^failure_label=' "$tmp/output" | head -1 | cut -d= -f2- || true
}
_detail() {
  local tmp="$1"
  grep -E '^failure_detail=' "$tmp/output" | head -1 | cut -d= -f2- || true
}

CANONICAL='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'

# T1: identity -> no drift
t_identity() {
  local r; r=$(_run "$CANONICAL" "$CANONICAL")
  local tmp="${r%:*}" rc="${r##*:}"
  local mode; mode=$(_mode "$tmp")
  if [[ "$rc" == "0" && -z "$mode" ]]; then
    _report "T1 identity -> no drift" ok
  else
    _report "T1 identity -> no drift" fail "rc=$rc mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T2: added entry -> ci/auth-broken
t_added_entry() {
  local live='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"},{"actor_id":4,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "bypass_actors_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T2 added entry -> auth-broken drift" ok
  else
    _report "T2 added entry -> auth-broken drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T3: removed entry -> drift
t_removed_entry() {
  local live='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "bypass_actors_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T3 removed entry -> auth-broken drift" ok
  else
    _report "T3 removed entry -> auth-broken drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T4: mode broadening -> drift (the brand-damaging case)
t_mode_change() {
  local live='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"always"},{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "bypass_actors_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T4 mode broadening (pull_request -> always) -> drift" ok
  else
    _report "T4 mode broadening (pull_request -> always) -> drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T5: order-insensitive -> no drift
t_order_insensitive() {
  local live='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"},{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ -z "$mode" ]]; then
    _report "T5 reversed order -> no drift" ok
  else
    _report "T5 reversed order -> no drift" fail "mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T6: actor_id missing-key vs null -> no drift (projection collapses)
t_missing_key_eq_null() {
  local live='[{"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ -z "$mode" ]]; then
    _report "T6 missing actor_id key vs explicit null -> no drift" ok
  else
    _report "T6 missing actor_id key vs explicit null -> no drift" fail "mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T7: canonical missing -> ci/guard-broken
t_canonical_missing() {
  local tmp; tmp=$(mktemp -d)
  local live="$tmp/live.json"
  printf '%s' "$CANONICAL" > "$live"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$live" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/does-not-exist.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "canonical_file_missing" && "$label" == "ci/guard-broken" ]]; then
    _report "T7 canonical file missing -> guard-broken" ok
  else
    _report "T7 canonical file missing -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T7b: canonical malformed JSON -> ci/guard-broken
t_canonical_malformed() {
  local r; r=$(_run "$CANONICAL" "not valid json {")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "canonical_file_invalid_json" && "$label" == "ci/guard-broken" ]]; then
    _report "T7b canonical malformed -> guard-broken" ok
  else
    _report "T7b canonical malformed -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T8: live HTTP 5xx (simulated via AUDIT_HTTP_CODE_OVERRIDE) -> guard-broken
t_live_http_5xx() {
  local tmp; tmp=$(mktemp -d)
  local live="$tmp/live.json"
  printf '%s' "$CANONICAL" > "$live"
  printf '%s' "$CANONICAL" > "$tmp/canonical.json"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$live" \
  AUDIT_HTTP_CODE_OVERRIDE="503" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canonical.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "github_api_http" && "$label" == "ci/guard-broken" ]]; then
    _report "T8 HTTP 503 -> guard-broken" ok
  else
    _report "T8 HTTP 503 -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T9: log-injection sanitation (CRLF + U+2028 in failure_detail)
t_log_injection_strip() {
  # Construct a live JSON whose drift detail string would contain CRLF if
  # we naively echoed it. We inject via actor_type since jq -c will produce
  # the literal in the diff string. CRLF in JSON values is escaped as \r\n
  # by jq; the SUT must strip CR/LF/U+0085/U+2028/U+2029 bytes from the
  # emitted failure_detail line.
  local live; live=$(printf '[{"actor_id":null,"actor_type":"Inj\r\nected\xe2\x80\xa8X","bypass_mode":"always"}]')
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  # Sanitation is per-LINE on $GITHUB_OUTPUT (NL is the record separator).
  # A surviving raw CR/LF/U+2028 in the failure_detail value would either
  # split the line OR yield a key=value with the literal byte. Assert
  # zero CR/LF bytes in the failure_detail line, AND no U+2028 bytes
  # anywhere in the output file.
  local detail_line; detail_line=$(grep -E '^failure_detail=' "$tmp/output" || true)
  local has_cr=0 has_u2028=0
  if printf '%s' "$detail_line" | grep -qP '\r'; then has_cr=1; fi
  if grep -qP '\xe2\x80\xa8' "$tmp/output"; then has_u2028=1; fi
  if [[ "$has_cr" == "0" && "$has_u2028" == "0" ]]; then
    _report "T9 CRLF + U+2028 stripped from failure_detail" ok
  else
    _report "T9 CRLF + U+2028 stripped from failure_detail" fail "cr=$has_cr u2028=$has_u2028 line='$detail_line'"
  fi
  rm -rf "$tmp"
}

# T10: unknown actor_type (Integration) -> drift
t_unknown_actor_type() {
  local live='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"},{"actor_id":99,"actor_type":"Integration","bypass_mode":"always"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "bypass_actors_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T10 Integration actor_type added -> drift" ok
  else
    _report "T10 Integration actor_type added -> drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T11: number-vs-string actor_id -> drift
t_number_vs_string_actor_id() {
  local live='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":"5","actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ "$mode" == "bypass_actors_drift" ]]; then
    _report "T11 number-vs-string actor_id -> drift" ok
  else
    _report "T11 number-vs-string actor_id -> drift" fail "mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T12: live missing bypass_actors key -> guard-broken
# Fixture deliberately lacks `enforcement` so the new token-scope sentinel
# (T12c) does NOT match and the legacy `live_missing_bypass_actors` path
# remains the routed failure mode for true-delete-shaped responses.
t_live_missing_bypass_actors() {
  local live='{"id":14145388,"name":"CI Required"}'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  # When the override file is a top-level object (not an array) the script
  # treats it as the full ruleset and extracts .bypass_actors; missing key
  # -> live_missing_bypass_actors / guard-broken.
  if [[ "$mode" == "live_missing_bypass_actors" && "$label" == "ci/guard-broken" ]]; then
    _report "T12 live missing bypass_actors -> guard-broken" ok
  else
    _report "T12 live missing bypass_actors -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T12b: live looks healthy (id+enforcement sentinel matches) but bypass_actors
# is missing AND the test override opts into the new sentinel via
# AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE=enabled -> token_scope_insufficient.
# Models the production GitHub-API redaction shape where a non-admin token
# gets HTTP 200 but bypass_actors is stripped from the response payload.
t_token_scope_insufficient() {
  local live='{"id":14145388,"name":"CI Required","enforcement":"active","rules":[]}'
  local tmp; tmp=$(mktemp -d)
  printf '%s' "$live" > "$tmp/live.json"
  printf '%s' "$CANONICAL" > "$tmp/canonical.json"
  : > "$tmp/output"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$tmp/live.json" \
  AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE="enabled" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canonical.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "token_scope_insufficient" && "$label" == "ci/guard-broken" ]]; then
    _report "T12b token_scope_insufficient (sentinel match + probe enabled) -> guard-broken" ok
  else
    _report "T12b token_scope_insufficient (sentinel match + probe enabled) -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T12c: same id+enforcement-sentinel-matching fixture as T12b but WITHOUT
# AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE -> still routes to legacy
# live_missing_bypass_actors. Proves the test-override gate is load-bearing
# and existing override-driven tests don't accidentally regress to the new
# failure mode.
t_token_scope_probe_override_gated() {
  local live='{"id":14145388,"name":"CI Required","enforcement":"active","rules":[]}'
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "live_missing_bypass_actors" && "$label" == "ci/guard-broken" ]]; then
    _report "T12c sentinel-matching fixture without probe override -> live_missing_bypass_actors (legacy path)" ok
  else
    _report "T12c sentinel-matching fixture without probe override -> live_missing_bypass_actors (legacy path)" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T12d: ruleset id matches but enforcement was paused (e.g., "disabled" or
# "evaluate"). bypass_actors guarantee is gone — the operator triage path
# must be "re-enable", not "recreate". Routes to ruleset_enforcement_disabled
# / ci/auth-broken (auth surface widened, not guard malfunction).
t_ruleset_enforcement_disabled() {
  local live='{"id":14145388,"name":"CI Required","enforcement":"disabled","rules":[]}'
  local tmp; tmp=$(mktemp -d)
  printf '%s' "$live" > "$tmp/live.json"
  printf '%s' "$CANONICAL" > "$tmp/canonical.json"
  : > "$tmp/output"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$tmp/live.json" \
  AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE="enabled" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canonical.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label detail; mode=$(_mode "$tmp"); label=$(_label "$tmp"); detail=$(_detail "$tmp")
  if [[ "$mode" == "ruleset_enforcement_disabled" && "$label" == "ci/auth-broken" ]] \
     && grep -qF "enforcement='disabled'" <<<"$detail"; then
    _report "T12d ruleset enforcement disabled -> ruleset_enforcement_disabled / ci/auth-broken" ok
  else
    _report "T12d ruleset enforcement disabled -> ruleset_enforcement_disabled / ci/auth-broken" fail "mode='$mode' label='$label' detail='${detail:0:120}'"
  fi
  rm -rf "$tmp"
}

# T14: missing GH_TOKEN -> missing_gh_token / guard-broken
t_missing_gh_token() {
  local tmp; tmp=$(mktemp -d)
  printf '%s' "$CANONICAL" > "$tmp/canonical.json"
  local rc=0
  env -u GH_TOKEN -u AUDIT_FETCH_OVERRIDE \
    AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canonical.json" \
    GITHUB_OUTPUT="$tmp/output" \
    RULESET_URL="http://127.0.0.1:1/no-network" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "missing_gh_token" && "$label" == "ci/guard-broken" ]]; then
    _report "T14 missing GH_TOKEN -> guard-broken" ok
  else
    _report "T14 missing GH_TOKEN -> guard-broken" fail "mode='$mode' label='$label' rc=$rc"
  fi
  rm -rf "$tmp"
}

# T15: live HTTP network_error (simulated) -> guard-broken
t_live_network_error() {
  local tmp; tmp=$(mktemp -d)
  printf '%s' "$CANONICAL" > "$tmp/live.json"
  printf '%s' "$CANONICAL" > "$tmp/canonical.json"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$tmp/live.json" \
  AUDIT_HTTP_CODE_OVERRIDE="network_error" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canonical.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "github_api_network" && "$label" == "ci/guard-broken" ]]; then
    _report "T15 network_error -> guard-broken" ok
  else
    _report "T15 network_error -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T16: canonical with string actor_id (schema violation) -> guard-broken
t_canonical_invalid_schema() {
  local bad_canonical='[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},{"actor_id":"5","actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  local r; r=$(_run "$CANONICAL" "$bad_canonical")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "canonical_file_invalid_schema" && "$label" == "ci/guard-broken" ]]; then
    _report "T16 canonical string actor_id -> invalid_schema" ok
  else
    _report "T16 canonical string actor_id -> invalid_schema" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T17: empty canonical [] vs non-empty live -> drift
t_empty_canonical() {
  local r; r=$(_run "$CANONICAL" '[]')
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ "$mode" == "bypass_actors_drift" ]]; then
    _report "T17 empty canonical vs non-empty live -> drift" ok
  else
    _report "T17 empty canonical vs non-empty live -> drift" fail "mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T18: cross-script parity — audit and update use byte-identical jq filter
t_cross_script_parity() {
  local repo_root="$REPO_ROOT"
  local audit_file="$repo_root/scripts/audit-ruleset-bypass.sh"
  local update_file="$repo_root/scripts/update-ci-required-ruleset.sh"
  local lib_file="$repo_root/scripts/lib/canonicalize-bypass-actors.sh"
  if [[ ! -f "$lib_file" ]]; then
    _report "T18 shared canonicalize lib exists" fail "missing $lib_file"
    return
  fi
  # Both scripts must source the lib (not redefine the jq expression)
  if ! grep -qF 'canonicalize-bypass-actors.sh' "$audit_file"; then
    _report "T18 audit script sources lib" fail
    return
  fi
  if ! grep -qF 'canonicalize-bypass-actors.sh' "$update_file"; then
    _report "T18 update script sources lib" fail
    return
  fi
  # Neither script should redeclare the projection inline. Ignore comment
  # lines (^# or whitespace-then-#) — only flag executable jq expressions.
  if grep -nE 'map\(\{actor_type, actor_id, bypass_mode\}\)' "$audit_file" "$update_file" 2>/dev/null \
      | grep -vE ':[[:space:]]*#' >/dev/null; then
    _report "T18 no inline projection redeclaration" fail "found executable map({...}) in audit or update script"
    return
  fi
  _report "T18 cross-script jq parity via shared lib" ok
}

# T19: $GITHUB_OUTPUT shape — exactly 3 lines, key=value, no leading whitespace
t_github_output_shape() {
  local r; r=$(_run "$CANONICAL" "$CANONICAL")
  local tmp="${r%:*}"
  local line_count; line_count=$(wc -l < "$tmp/output")
  local malformed; malformed=$(grep -cvE '^[a-z_]+=' "$tmp/output" || true)
  if [[ "$line_count" == "3" && "$malformed" == "0" ]]; then
    _report "T19 GITHUB_OUTPUT shape: 3 key=value lines on identity" ok
  else
    _report "T19 GITHUB_OUTPUT shape: 3 key=value lines on identity" fail "lines=$line_count malformed=$malformed"
  fi
  rm -rf "$tmp"
}

# T20: drift detail capped at ~500 chars (markdown/email length guard)
t_drift_detail_capped() {
  # Build a live entry whose stringified form would explode beyond 500 chars
  # if not capped — use a long unicode-safe actor_type that's still valid JSON.
  local long_name
  long_name=$(printf 'A%.0s' $(seq 1 600))
  local live; live=$(printf '[{"actor_id":1,"actor_type":"%s","bypass_mode":"always"}]' "$long_name")
  local r; r=$(_run "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local detail; detail=$(_detail "$tmp")
  if (( ${#detail} <= 600 )); then  # 500 cap + truncation marker
    _report "T20 drift detail capped (length=${#detail})" ok
  else
    _report "T20 drift detail capped (length=${#detail})" fail "detail too long"
  fi
  rm -rf "$tmp"
}

# T13: real canonical JSON matches the expected shape (regression guard)
t_real_canonical_shape() {
  if [[ ! -f "$CANONICAL_REAL" ]]; then
    _report "T13 real canonical exists" fail "missing $CANONICAL_REAL"
    return
  fi
  if ! jq -e . "$CANONICAL_REAL" >/dev/null 2>&1; then
    _report "T13 real canonical is valid JSON" fail
    return
  fi
  local n; n=$(jq 'length' < "$CANONICAL_REAL")
  if [[ "$n" != "2" ]]; then
    _report "T13 real canonical has 2 entries" fail "got $n"
    return
  fi
  _report "T13 real canonical valid JSON, 2 entries" ok
}

# ---------- RSC (required_status_checks) audit tests (#3547) ----------
# These tests use object-shape live fixtures (legacy array-shape skips RSC).
CANONICAL_RSC='[{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"CodeQL","integration_id":57789},{"context":"skill-security-scan PR gate","integration_id":15368}]'

# Helper: run with both canonical files and an object-shape live fixture.
_run_with_rsc() {
  local live_object="$1" canonical_bypass="$2" canonical_rsc="$3"
  local tmp; tmp=$(mktemp -d)
  printf '%s' "$live_object" > "$tmp/live.json"
  printf '%s' "$canonical_bypass" > "$tmp/canon-bypass.json"
  printf '%s' "$canonical_rsc" > "$tmp/canon-rsc.json"
  : > "$tmp/output"
  local rc=0
  AUDIT_FETCH_OVERRIDE="$tmp/live.json" \
  AUDIT_CANONICAL_FILE_OVERRIDE="$tmp/canon-bypass.json" \
  AUDIT_RSC_CANONICAL_FILE_OVERRIDE="$tmp/canon-rsc.json" \
  GITHUB_OUTPUT="$tmp/output" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  echo "$tmp:$rc"
}

# T-rsc-1: identity (live RSC matches canonical) -> no drift
t_rsc_identity() {
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$CANONICAL_RSC" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ -z "$mode" ]]; then
    _report "T-rsc-1 RSC identity -> no drift" ok
  else
    _report "T-rsc-1 RSC identity -> no drift" fail "mode='$mode' stderr=$(head -3 "$tmp/stderr")"
  fi
  rm -rf "$tmp"
}

# T-rsc-2: live missing CodeQL -> required_status_checks_drift / auth-broken
t_rsc_missing_codeql() {
  local live_rsc='[{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"skill-security-scan PR gate","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$live_rsc" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "required_status_checks_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T-rsc-2 live missing CodeQL -> required_status_checks_drift" ok
  else
    _report "T-rsc-2 live missing CodeQL -> required_status_checks_drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T-rsc-3: CodeQL integration_id 15368 (would let github-actions[bot] spoof) -> drift
# Asserts drift_detail names "CodeQL" specifically — without this, a regression
# that drifts a different context (e.g., dependency-review) would still pass.
t_rsc_codeql_wrong_app() {
  local live_rsc='[{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"CodeQL","integration_id":15368},{"context":"skill-security-scan PR gate","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$live_rsc" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode detail; mode=$(_mode "$tmp"); detail=$(_detail "$tmp")
  if [[ "$mode" == "required_status_checks_drift" ]] && \
     grep -qF 'CodeQL' <<<"$detail" && \
     grep -qE 'integration_id":15368' <<<"$detail"; then
    _report "T-rsc-3 CodeQL integration_id 15368 (wrong app) -> drift names CodeQL+15368" ok
  else
    _report "T-rsc-3 CodeQL integration_id 15368 (wrong app) -> drift names CodeQL+15368" fail "mode='$mode' detail='${detail:0:200}'"
  fi
  rm -rf "$tmp"
}

# T-rsc-4: live ruleset has no required_status_checks rule -> guard-broken
t_rsc_live_missing_rsc_rule() {
  local live; live=$(jq -nc --argjson b "$CANONICAL" '{bypass_actors: $b, rules: []}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "live_missing_required_status_checks" && "$label" == "ci/guard-broken" ]]; then
    _report "T-rsc-4 live missing RSC rule -> guard-broken" ok
  else
    _report "T-rsc-4 live missing RSC rule -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T-rsc-5b: canonical RSC has duplicate context (e.g., two CodeQL rows) -> guard-broken
t_rsc_canonical_duplicate_context() {
  local dup='[{"context":"CodeQL","integration_id":57789},{"context":"CodeQL","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$CANONICAL_RSC" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$dup")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "canonical_rsc_file_invalid_schema" && "$label" == "ci/guard-broken" ]]; then
    _report "T-rsc-5b canonical RSC duplicate context -> invalid_schema" ok
  else
    _report "T-rsc-5b canonical RSC duplicate context -> invalid_schema" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T-rsc-5: canonical RSC has string integration_id (schema violation) -> guard-broken
t_rsc_canonical_invalid_schema() {
  local bad_canonical='[{"context":"test","integration_id":"15368"}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$CANONICAL_RSC" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$bad_canonical")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "canonical_rsc_file_invalid_schema" && "$label" == "ci/guard-broken" ]]; then
    _report "T-rsc-5 canonical RSC string integration_id -> invalid_schema" ok
  else
    _report "T-rsc-5 canonical RSC string integration_id -> invalid_schema" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T-rsc-6: reordered live RSC -> no drift (sort_by canonical)
t_rsc_order_insensitive() {
  local live_rsc='[{"context":"skill-security-scan PR gate","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"CodeQL","integration_id":57789},{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$live_rsc" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode; mode=$(_mode "$tmp")
  if [[ -z "$mode" ]]; then
    _report "T-rsc-6 reordered live RSC -> no drift" ok
  else
    _report "T-rsc-6 reordered live RSC -> no drift" fail "mode='$mode'"
  fi
  rm -rf "$tmp"
}

# T-rsc-7: real canonical RSC has 21 entries with CodeQL pinned to 57789.
# Reconciled from the stale 5-check baseline to the Terraform-managed live set
# (#4397); bumped 16->17 by #6049 (adr-ordinals reconciled from live); bumped
# 17->18 by #6103 (rule-body-lint, ADR-091); bumped 18->19 by #6325
# (grok-fidelity, Phase F); bumped 19->20 by #6589 (sentry-destroy-required —
# the always-run aggregator that makes an unacknowledged Sentry destroy
# unmergeable rather than merely visible); bumped 20->21 by #6882
# (credential-path-guard, ADR-139 — the always-run full-scan job that blocks a
# tracked doc from reintroducing a resolvable credential-file path; its bot-PR
# synthetic is EARNED in the composite action's Phase-4 ceiling, not
# fabricated-but-unreachable, because its SCAN_DIRS intersects ALLOWED_PATHS).
# The exact count is kept in lockstep
# with infra/github/ruleset-ci-required.tf by T-rsc-9 below.
#
# The literal is deliberate and must stay a literal: deriving it from the file
# would make this assertion tautological, and its whole job is to catch an
# addition nobody intended. Bumping it is the acknowledgement.
t_rsc_real_canonical_shape() {
  local real="$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json"
  if [[ ! -f "$real" ]]; then
    _report "T-rsc-7 real canonical RSC exists" fail "missing $real"
    return
  fi
  local n codeql_app non_codeql_apps
  n=$(jq 'length' < "$real")
  codeql_app=$(jq -r '.[] | select(.context=="CodeQL") | .integration_id' < "$real")
  # Every non-CodeQL check is a GitHub Actions context (15368). A flattened
  # CodeQL integration_id would let github-actions[bot] spoof the GHAS gate.
  non_codeql_apps=$(jq -r '[.[] | select(.context!="CodeQL") | .integration_id] | unique | join(",")' < "$real")
  if [[ "$n" == "21" && "$codeql_app" == "57789" && "$non_codeql_apps" == "15368" ]]; then
    _report "T-rsc-7 real canonical RSC: 21 entries, CodeQL=57789, rest=15368" ok
  else
    _report "T-rsc-7 real canonical RSC: 21 entries, CodeQL=57789, rest=15368" fail "n=$n codeql_app=$codeql_app non_codeql=$non_codeql_apps"
  fi
}

# T-rsc-9 (canonical↔terraform sync gate): the canonical RSC JSON context set
# MUST equal the required_check contexts declared in the Terraform source of
# truth (infra/github/ruleset-ci-required.tf). This is the root-cause fix for
# #4397 — the snapshot silently went stale (5) while Terraform widened the live
# ruleset (16), and nothing forced them back into lockstep. Any future .tf edit
# now fails CI until the JSON is reconciled in the same PR.
t_rsc_canonical_matches_terraform() {
  local real="$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json"
  local tf="$REPO_ROOT/infra/github/ruleset-ci-required.tf"
  if [[ ! -f "$tf" ]]; then
    _report "T-rsc-9 terraform ruleset source exists" fail "missing $tf"
    return
  fi
  # Context-set equality only. integration_id pinning is covered elsewhere:
  # T-rsc-7 asserts the JSON's CodeQL=57789/rest=15368, and the live audit's
  # compareRequiredStatusChecks flags any integration_id divergence as a
  # critical `removed` — so a CodeQL app swap still surfaces at audit time.
  local json_ctx tf_ctx
  json_ctx=$(jq -r '.[].context' < "$real" | sort)
  # Extract `context = "..."` (required_check blocks are the only `context =`
  # assignments in this root); strip quotes; sort for set comparison.
  tf_ctx=$(grep -oE 'context[[:space:]]*=[[:space:]]*"[^"]+"' "$tf" \
    | sed -E 's/.*"([^"]+)"$/\1/' | sort)
  if [[ "$json_ctx" == "$tf_ctx" ]]; then
    _report "T-rsc-9 canonical RSC context set == ruleset-ci-required.tf" ok
  else
    _report "T-rsc-9 canonical RSC context set == ruleset-ci-required.tf" fail \
      "diff:$(diff <(echo "$json_ctx") <(echo "$tf_ctx") | tr '\n' ' ')"
  fi
}

# T-mq-1 (merge_queue stays REVERTED, #5780): the merge queue was enabled by
# PR #5800 then reverted (kill-switch) because GitHub CodeQL default setup does
# not post the required `CodeQL` context on `merge_group` temp refs → every
# queue entry deadlocked. Until CodeQL is moved to *advanced* setup with an
# `on: merge_group` trigger, neither the Terraform source of truth
# (infra/github/ruleset-ci-required.tf) nor the DR-restore skeleton
# (scripts/create-ci-required-ruleset.sh) may declare a `merge_queue` rule —
# re-adding one before the CodeQL fix re-introduces the outage. This guard
# fails CI if a `merge_queue` rule reappears in either file. See ADR-032 +
# the PIR. (When re-adopting, replace this guard with a param-parity gate.)
t_mq_stays_reverted() {
  local tf="$REPO_ROOT/infra/github/ruleset-ci-required.tf"
  local dr="$REPO_ROOT/scripts/create-ci-required-ruleset.sh"
  if [[ ! -f "$tf" || ! -f "$dr" ]]; then
    _report "T-mq-1 merge_queue source files exist" fail "missing $tf or $dr"
    return
  fi
  # .tf: a `merge_queue {` HCL block (not a comment) would re-enable the queue.
  # Strip comment lines (leading #) before matching so the revert-rationale
  # comment that names "merge_queue" does not false-fail.
  # `grep -c` exits 1 on zero matches — the EXPECTED reverted state — so `|| true`
  # keeps `set -euo pipefail` from aborting the suite mid-run.
  local tf_block
  tf_block=$(grep -vE '^[[:space:]]*#' "$tf" | grep -cE 'merge_queue[[:space:]]*\{' || true)
  # DR skeleton: a "type": "merge_queue" rule in the heredoc would re-add it.
  local dr_rule
  dr_rule=$(sed -n "/cat > \"\$skeleton\" << 'EOF'/,/^EOF\$/p" "$dr" \
    | sed '1d;$d' \
    | jq -c '[.rules[] | select(.type=="merge_queue")] | length' 2>/dev/null || true)
  [[ -z "$dr_rule" ]] && dr_rule=0
  if [[ "$tf_block" == "0" && "$dr_rule" == "0" ]]; then
    _report "T-mq-1 merge_queue stays reverted (.tf + DR skeleton)" ok
  else
    _report "T-mq-1 merge_queue stays reverted (.tf + DR skeleton)" fail \
      "tf_merge_queue_blocks=$tf_block dr_merge_queue_rules=$dr_rule — re-adopting requires CodeQL advanced setup first (#5780)"
  fi
}

# T-rsc-8: cross-script parity — shared canonicalize-required-status-checks lib is sourced
t_rsc_shared_lib_used() {
  local audit_file="$REPO_ROOT/scripts/audit-ruleset-bypass.sh"
  local create_file="$REPO_ROOT/scripts/create-ci-required-ruleset.sh"
  local lib_file="$REPO_ROOT/scripts/lib/canonicalize-required-status-checks.sh"
  if [[ ! -f "$lib_file" ]]; then
    _report "T-rsc-8 canonicalize-required-status-checks.sh exists" fail "missing"
    return
  fi
  local update_file="$REPO_ROOT/scripts/update-ci-required-ruleset.sh"
  if ! grep -qF 'lib/canonicalize-required-status-checks.sh' "$audit_file"; then
    _report "T-rsc-8 audit script sources RSC lib" fail
    return
  fi
  if ! grep -qF 'lib/canonicalize-required-status-checks.sh' "$update_file"; then
    _report "T-rsc-8 update-ci script sources RSC lib (data-integrity P2)" fail
    return
  fi
  if ! grep -qF 'ci-required-ruleset-canonical-required-status-checks.json' "$create_file"; then
    _report "T-rsc-8 create-ci script references canonical RSC JSON" fail
    return
  fi
  # No-inline-redeclaration guard: neither audit nor update may carry the
  # jq projection literal — only the shared lib should hold it.
  if grep -qE 'map\(\{context, integration_id\}\)' "$audit_file" "$update_file" 2>/dev/null; then
    if grep -nE 'map\(\{context, integration_id\}\)' "$audit_file" "$update_file" | grep -vE ':[[:space:]]*#' >/dev/null; then
      _report "T-rsc-8 no inline RSC projection redeclaration" fail "found executable map({context,integration_id}) outside lib"
      return
    fi
  fi
  _report "T-rsc-8 shared RSC lib sourced by audit + update; create-ci references canonical; no inline redecl" ok
}

# ---------- CLA ruleset canonical sync gates (#6061, Terraform-ified #6072) ----------
# The CLA Required ruleset is Terraform-managed via
# infra/github/ruleset-cla-required.tf (as of #6072 — the imperative
# scripts/create-cla-required-ruleset.sh is now a DR-only restore skeleton that
# reads the canonicals, not the SSOT). These gates pin the two CLA canonical
# JSONs (which the daily cron-ruleset-bypass-audit Inngest fn reads) to the `.tf`
# — matching how T-rsc-9 pins the CI canonical to ruleset-ci-required.tf — so a
# value change in the `.tf` without reconciling the canonical (or vice versa)
# fails CI. Co-located with T-rsc-9 (the CI canonical↔terraform sync gate).
CLA_TF="$REPO_ROOT/infra/github/ruleset-cla-required.tf"
CLA_RSC_CANONICAL="$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
CLA_BYPASS_CANONICAL="$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-bypass-actors.json"

# T-cla-1 (CLA canonical↔terraform RSC sync gate): the canonical RSC JSON context
# set MUST equal the required_check contexts declared in the Terraform source of
# truth (infra/github/ruleset-cla-required.tf), and the integration_id is pinned:
# every canonical row is 15368 AND the `.tf` binds every required_check to
# var.actions_integration_id (default 15368 per variables.tf), NOT
# var.codeql_integration_id (which would let github-actions[bot] spoof a GHAS
# gate). Mirrors T-rsc-9 (context set) + T-rsc-7 (integration_id pin). The `.tf`
# header/block comments must not carry a literal `context = "..."` token (SE-3),
# else the comment-naive grep over-counts.
t_cla_rsc_canonical_matches_tf() {
  if [[ ! -f "$CLA_TF" ]]; then
    _report "T-cla-1 CLA terraform ruleset source exists" fail "missing $CLA_TF"
    return
  fi
  if [[ ! -f "$CLA_RSC_CANONICAL" ]]; then
    _report "T-cla-1 CLA RSC canonical exists" fail "missing $CLA_RSC_CANONICAL"
    return
  fi
  # Context-set equality: canonical `.[].context` vs the `.tf` `context = "..."`
  # assignments (required_check blocks are the only `context =` lines in the file).
  # Same extraction mechanism as T-rsc-9.
  local json_ctx tf_ctx
  json_ctx=$(jq -r '.[].context' < "$CLA_RSC_CANONICAL" | sort)
  tf_ctx=$(grep -oE 'context[[:space:]]*=[[:space:]]*"[^"]+"' "$CLA_TF" \
    | sed -E 's/.*"([^"]+)"$/\1/' | sort)
  # integration_id pin: every canonical row is 15368, AND the `.tf` binds every
  # required_check to var.actions_integration_id, never var.codeql_integration_id.
  local canon_all_15368 actions_binds ctx_count
  canon_all_15368=$(jq -r 'all(.[]; .integration_id == 15368)' < "$CLA_RSC_CANONICAL")
  # `grep -c` exits 1 on zero matches (a broken `.tf`); `|| true` keeps
  # `set -euo pipefail` from aborting the suite on the happy path.
  actions_binds=$(grep -cE 'integration_id[[:space:]]*=[[:space:]]*var\.actions_integration_id' "$CLA_TF" || true)
  ctx_count=$(printf '%s\n' "$tf_ctx" | grep -c . || true)
  # Comment-safe codeql check: match an actual `= var.codeql_integration_id`
  # BINDING, never the bare token — a comment naming it must not false-fail (same
  # SE-3 class as the `context = "..."` hygiene). Explicit signal alongside
  # actions_binds==ctx_count; keeps a clear `codeql=yes` failure line.
  local has_codeql=no
  if grep -qE 'integration_id[[:space:]]*=[[:space:]]*var\.codeql_integration_id' "$CLA_TF"; then has_codeql=yes; fi
  # Pin the integration_id NUMBER end-to-end: the `.tf` binds required_checks to
  # var.actions_integration_id by NAME, so also assert that var's default == the
  # canonical's 15368 (restores the literal pin the retired create-script carried;
  # closes the variables.tf-default→codeql-id path T-rsc-7 guards on the JSON side).
  local actions_default
  actions_default=$(awk '/variable "actions_integration_id"/{f=1} f&&/^[[:space:]]*default[[:space:]]*=/{gsub(/[^0-9]/,"",$0); print; exit}' "$REPO_ROOT/infra/github/variables.tf")
  # No-dup guard: the canonical must not carry a duplicate context row.
  local dup
  dup=$(jq -r '(map(.context) | length) - (map(.context) | unique | length)' "$CLA_RSC_CANONICAL")
  # Non-vacuity floor: CLA requires cla-check + cla-evidence (>= 2). A double-empty
  # fault (canonical [] AND `.tf` no contexts) is blocked by the floor + the
  # actions_binds==ctx_count check (both would be 0, but n_canon>=2 fails).
  local n_canon
  n_canon=$(jq 'length' "$CLA_RSC_CANONICAL")
  if [[ "$json_ctx" == "$tf_ctx" && "$canon_all_15368" == "true" \
        && "$actions_binds" == "$ctx_count" && "$has_codeql" == "no" \
        && "$actions_default" == "15368" \
        && "$dup" == "0" && "$n_canon" -ge 2 ]]; then
    _report "T-cla-1 CLA RSC canonical context set + integration_id == ruleset-cla-required.tf" ok
  else
    _report "T-cla-1 CLA RSC canonical context set + integration_id == ruleset-cla-required.tf" fail \
      "all15368=$canon_all_15368 actions_binds=$actions_binds ctx_count=$ctx_count codeql=$has_codeql actions_default=$actions_default dup=$dup diff:$(diff <(echo "$json_ctx") <(echo "$tf_ctx") | tr '\n' ' ')"
  fi
}

# T-cla-1b (CLA canonical↔terraform bypass sync gate): the `.tf` bypass_actors
# blocks (actor_id|actor_type|bypass_mode triples) MUST equal the canonical bypass
# JSON, with the `.tf`'s OrganizationAdmin `actor_id = 0` sentinel (provider issue
# #2536) normalized to the canonical's `null` (SE-1 — the canonical mirrors the
# LIVE API shape, which is null). The Integration:1236702/always actor is the CLA
# bot — legitimately `always` and IN the canonical, so the audit flags only
# ADDITIONAL bypass actors (widening).
t_cla_bypass_canonical_matches_tf() {
  if [[ ! -f "$CLA_TF" ]]; then
    _report "T-cla-1b CLA terraform ruleset source exists" fail "missing $CLA_TF"
    return
  fi
  if [[ ! -f "$CLA_BYPASS_CANONICAL" ]]; then
    _report "T-cla-1b CLA bypass canonical exists" fail "missing $CLA_BYPASS_CANONICAL"
    return
  fi
  # Parse `.tf` bypass_actors { ... } blocks into actor_id|actor_type|bypass_mode
  # triples; default actor_id to "null" per block; strip quotes + trailing
  # comments. Normalize actor_id "0" -> "null" (OrganizationAdmin sentinel; no real
  # actor has id 0) so the `.tf`'s 0 compares equal to the canonical's null.
  # Strip any trailing `# ...` comment FIRST (before the greedy `.*=` value slice)
  # so an inline comment containing a stray `=` cannot corrupt the extracted value
  # (removes the SE-3 `# ... = ...`-on-assignment-line latent trap at the parser).
  local tf_triples
  tf_triples=$(awk '
    /^[[:space:]]*bypass_actors[[:space:]]*\{/ {blk=1; aid="null"; at=""; bm=""; next}
    blk && /^[[:space:]]*actor_id[[:space:]]*=/    {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*/,"",v);  sub(/[[:space:]]*$/,"",v); aid=v}
    blk && /^[[:space:]]*actor_type[[:space:]]*=/  {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*$/,"",v); at=v}
    blk && /^[[:space:]]*bypass_mode[[:space:]]*=/ {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*$/,"",v); bm=v}
    blk && /^[[:space:]]*\}/ {print aid"|"at"|"bm; blk=0}
  ' "$CLA_TF" | sed 's/^0|/null|/' | sort)
  # Canonical triples: null prints as "null".
  local canon_triples
  canon_triples=$(jq -r '.[] | "\(.actor_id)|\(.actor_type)|\(.bypass_mode)"' "$CLA_BYPASS_CANONICAL" | sort)
  # No-dup guard on the canonical.
  local dup
  dup=$(jq -r '(map("\(.actor_id)|\(.actor_type)|\(.bypass_mode)")) as $k | ($k | length) - ($k | unique | length)' "$CLA_BYPASS_CANONICAL")
  # Non-vacuity floor (>= 3): OrgAdmin + RepoRole + CLA-bot Integration.
  local n_canon
  n_canon=$(jq 'length' "$CLA_BYPASS_CANONICAL")
  if [[ "$tf_triples" == "$canon_triples" && "$dup" == "0" && "$n_canon" -ge 3 ]]; then
    _report "T-cla-1b CLA bypass canonical triples == ruleset-cla-required.tf (0↔null) + no-dup" ok
  else
    _report "T-cla-1b CLA bypass canonical triples == ruleset-cla-required.tf (0↔null) + no-dup" fail \
      "dup=$dup diff:$(diff <(echo "$canon_triples") <(echo "$tf_triples") | tr '\n' ' ')"
  fi
}

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2
  exit 1
fi

t_identity
t_added_entry
t_removed_entry
t_mode_change
t_order_insensitive
t_missing_key_eq_null
t_canonical_missing
t_canonical_malformed
t_live_http_5xx
t_log_injection_strip
t_unknown_actor_type
t_number_vs_string_actor_id
t_live_missing_bypass_actors
t_token_scope_insufficient
t_token_scope_probe_override_gated
t_ruleset_enforcement_disabled
t_missing_gh_token
t_live_network_error
t_canonical_invalid_schema
t_empty_canonical
t_cross_script_parity
t_github_output_shape
t_drift_detail_capped
t_real_canonical_shape

# RSC tests (#3547)
t_rsc_identity
t_rsc_missing_codeql
t_rsc_codeql_wrong_app
t_rsc_live_missing_rsc_rule
t_rsc_canonical_invalid_schema
t_rsc_canonical_duplicate_context
t_rsc_order_insensitive
t_rsc_real_canonical_shape
t_rsc_shared_lib_used
t_rsc_canonical_matches_terraform
t_mq_stays_reverted

# CLA ruleset canonical↔terraform sync gates (#6061; Terraform-ified #6072)
t_cla_rsc_canonical_matches_tf
t_cla_bypass_canonical_matches_tf

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
