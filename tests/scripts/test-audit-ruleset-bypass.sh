#!/usr/bin/env bash
# Tests for scripts/audit-ruleset-bypass.sh.
# Deterministic; no live API. Uses AUDIT_FETCH_OVERRIDE to bypass curl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/audit-ruleset-bypass.sh"
CANONICAL_REAL="$REPO_ROOT/scripts/ci-required-ruleset-canonical-bypass-actors.json"
pass=0; fail=0

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# Scratch dirs staged by _mq_stage; the single owning EXIT trap removes whatever a dying run left.
MQ_STAGE_DIRS=()
MQ_STAGE_DIR=""
_mq_cleanup() {
  local d
  for d in ${MQ_STAGE_DIRS[@]+"${MQ_STAGE_DIRS[@]}"}; do assert_fixture_dir "$d"; rm -rf "$d"; done
}
trap _mq_cleanup EXIT

# MQ_OK counts the Guard 2 (T-mq-*) rows that reported ok. The end of the suite pins it EXACTLY, so a
# deleted Guard 2 invocation (fewer rows) or a neutered _report (no rows counted) turns the suite red
# instead of leaving it green on the rows that remain.
MQ_OK=0
_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    [[ "$label" == T-mq-* ]] && MQ_OK=$((MQ_OK + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Instrument self-test: _report must move pass on ok, fail on fail, and MQ_OK on a T-mq-* ok. Driven once
# with each verdict (printf + exit, never routed through the helper under test); counters are restored.
_ist_p="$pass"; _ist_f="$fail"; _ist_m="$MQ_OK"
_report "T-mq-selftest ok" ok >/dev/null
_report "T-mq-selftest fail" fail "(expected; retracted)" >/dev/null 2>&1
if [[ "$pass" -ne $((_ist_p + 1)) || "$fail" -ne $((_ist_f + 1)) || "$MQ_OK" -ne $((_ist_m + 1)) ]]; then
  printf '[FATAL] instrument self-test: _report did not move pass/fail/MQ_OK as a verdict helper must\n' >&2
  exit 1
fi
pass="$_ist_p"; fail="$_ist_f"; MQ_OK="$_ist_m"

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
# Neutral synthetic fixture: no CodeQL row. CodeQL is advisory (not a required check) since #9454,
# so the real canonical no longer carries it; the GHAS-style spoof-guard intent lives in
# t_rsc_codeql_wrong_app's own two-row synthetic fixture below.
CANONICAL_RSC='[{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"skill-security-scan PR gate","integration_id":15368}]'

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

# T-rsc-2: live missing a required context -> required_status_checks_drift / auth-broken
t_rsc_missing_context() {
  local live_rsc='[{"context":"test","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"skill-security-scan PR gate","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$live_rsc" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$CANONICAL_RSC")
  local tmp="${r%:*}"
  local mode label; mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "required_status_checks_drift" && "$label" == "ci/auth-broken" ]]; then
    _report "T-rsc-2 live missing a required context -> required_status_checks_drift" ok
  else
    _report "T-rsc-2 live missing a required context -> required_status_checks_drift" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}

# T-rsc-3: a same-name context bound to the wrong app (would let github-actions[bot]
# spoof a GHAS-bound gate) -> drift naming the context and the wrong app id.
# SYNTHETIC two-row fixture only: the real canonical has no CodeQL row since #9454
# (CodeQL is advisory). The intent is kept for the day CodeQL is re-tightened to a
# required check (57789) — see codeql-1537-revisit-watch.yml. Asserts drift_detail
# names "CodeQL" specifically — without this, a regression that drifts a different
# context would still pass.
t_rsc_codeql_wrong_app() {
  local canon_rsc='[{"context":"CodeQL","integration_id":57789},{"context":"test","integration_id":15368}]'
  local live_rsc='[{"context":"CodeQL","integration_id":15368},{"context":"test","integration_id":15368}]'
  local live; live=$(jq -nc --argjson b "$CANONICAL" --argjson r "$live_rsc" \
    '{bypass_actors: $b, rules: [{type:"required_status_checks", parameters:{required_status_checks: $r}}]}')
  local r; r=$(_run_with_rsc "$live" "$CANONICAL" "$canon_rsc")
  local tmp="${r%:*}"
  local mode detail; mode=$(_mode "$tmp"); detail=$(_detail "$tmp")
  if [[ "$mode" == "required_status_checks_drift" ]] && \
     grep -qF 'CodeQL' <<<"$detail" && \
     grep -qE 'integration_id":15368' <<<"$detail"; then
    _report "T-rsc-3 synthetic CodeQL row bound to 15368 (wrong app) -> drift names CodeQL+15368" ok
  else
    _report "T-rsc-3 synthetic CodeQL row bound to 15368 (wrong app) -> drift names CodeQL+15368" fail "mode='$mode' detail='${detail:0:200}'"
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

# T-rsc-5b: canonical RSC has duplicate context (same name, two integration ids) -> guard-broken
t_rsc_canonical_duplicate_context() {
  local dup='[{"context":"test","integration_id":15368},{"context":"test","integration_id":57789}]'
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
  local live_rsc='[{"context":"skill-security-scan PR gate","integration_id":15368},{"context":"e2e","integration_id":15368},{"context":"test","integration_id":15368},{"context":"dependency-review","integration_id":15368}]'
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

# T-rsc-7: real canonical RSC has 23 entries, all GitHub Actions (15368), and NO CodeQL row
# (#9454: CodeQL is advisory; a merge queue and a required CodeQL context are mutually exclusive).
# Reconciled from the stale 5-check baseline to the Terraform-managed live set
# (#4397); bumped 16->17 by #6049 (adr-ordinals reconciled from live); bumped
# 17->18 by #6103 (rule-body-lint, ADR-091); bumped 18->19 by #6325
# (grok-fidelity, Phase F); bumped 19->20 by #6589 (sentry-destroy-required —
# the always-run aggregator that makes an unacknowledged Sentry destroy
# unmergeable rather than merely visible); bumped 20->21 by #6882
# (credential-path-guard, ADR-139 — the always-run full-scan job that blocks a
# tracked doc from reintroducing a resolvable credential-file path; its bot-PR
# synthetic is EARNED in the composite action's Phase-4 ceiling, not
# fabricated-but-unreachable, because its SCAN_DIRS intersects ALLOWED_PATHS);
# bumped 22->23 by #7927 (markdown-lint — the always-run whole-corpus
# Markdown gate. Its bot-PR synthetic is sound-by-UNREACHABILITY, not earned: the
# swept set is 1,345 files and its intersection with the composite action's
# ALLOWED_PATHS is 0 — weakness-digest.md sits under the knowledge-base/project/
# exclusion and rule-metrics.json is not Markdown, so a bot PR cannot touch a file
# this gate reads);
# bumped 21->22 by #7493 (marketplace-manifest-guard — the always-run job
# validating the marketplace manifest SOURCE that Terraform publishes to
# jikig-ai/soleur-marketplace; born blocking because once the drift workflow
# dispatches a reconcile apply, a bad manifest that merges is REPUBLISHED daily
# while a published-vs-source byte-diff reports in-sync. Its bot-PR synthetic is
# sound-by-UNREACHABILITY like rule-body-lint, not earned like
# credential-path-guard: SCAN_DIRS is one file and ALLOWED_PATHS does not
# contain it — re-derived per ADR-139, not inherited);
# bumped 23->24 by #8203 (vendor-pin-required — vendor-pin-verify.yml's
# always-run aggregator, the third #5585-pattern instance, wrapping the
# path-gated verify-upstream-blobs job so the #8181 NOTICE binding's red
# actually blocks merge. Bot-PR disposition: composite-action synthetic is
# sound-by-UNREACHABILITY (ALLOWED_PATHS ∩ plugins/soleur/skills/** = ∅) and
# the Inngest SYNTHETIC_CHECK_NAMES path deliberately EXCLUDES this name so
# re-vendor PRs earn it via real CI on App-token pushes, #8166);
# bumped 24->23 by #9454 (the `CodeQL` row was REMOVED when the merge queue was
# adopted — CodeQL cannot report a status on `merge_group`, codeql-action#1537).
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
  local n codeql_rows non_15368_apps
  n=$(jq 'length' < "$real")
  codeql_rows=$(jq '[.[] | select(.context=="CodeQL")] | length' < "$real")
  # Every check is a GitHub Actions context (15368). CodeQL (GHAS 57789) is NOT required.
  non_15368_apps=$(jq -r '[.[] | select(.integration_id != 15368) | .context] | join(",")' < "$real")
  if [[ "$n" == "23" && "$codeql_rows" == "0" && -z "$non_15368_apps" ]]; then
    _report "T-rsc-7 real canonical RSC: 23 entries, no CodeQL row, all 15368" ok
  else
    _report "T-rsc-7 real canonical RSC: 23 entries, no CodeQL row, all 15368" fail "n=$n codeql_rows=$codeql_rows non_15368=$non_15368_apps"
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
  # T-rsc-7 asserts the JSON is all-15368 with no CodeQL row, and the live audit's
  # compareRequiredStatusChecks flags any integration_id divergence as a
  # critical `removed` — so an app swap still surfaces at audit time.
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

# ---------- Guard 2 (#9454): merge_queue parameter parity + CodeQL-absent invariant ----------
# Successor of the old T-mq-1 "merge_queue stays REVERTED" gate (#5780). The queue is adopted
# (#9454), so the guard is now a PARITY gate across every source that carries the rule:
#   - infra/github/ruleset-ci-required.tf        (HCL `merge_queue {}` block; comments stripped,
#                                                 aligned `=` and trailing `# comments` accepted)
#   - scripts/create-ci-required-ruleset.sh      (DR heredoc skeleton; rule selected by .type,
#                                                 never positionally)
#   - infra/github/README.md                     (params table rows `| `param` | `value` |`)
#   - scripts/ci-required-ruleset-canonical-required-status-checks.json (must carry no CodeQL)
# All SEVEN value-bearing parameters are compared (the REST API 422s a partial payload). CodeQL
# cannot report on `merge_group` (codeql-action#1537), so a CodeQL required check and a
# merge_queue rule are mutually exclusive in every one of those sources. The guard is a function of
# four file paths so the mutation rows and the must-PASS fixture run the SAME engine as the real
# repo case (never a copy of its logic).
MQ_PARAMS="merge_method grouping_strategy max_entries_to_merge min_entries_to_merge min_entries_to_merge_wait_minutes max_entries_to_build check_response_timeout_minutes"
MQ_REASON=""
# The stall probe workflow: Guard 2 derives STALL_THRESHOLD_MINUTES from it for the safety assertion
# check_response_timeout_minutes > threshold (the probe must be able to report BEFORE the queue ejects).
MQ_STALL_WF="$REPO_ROOT/.github/workflows/merge-queue-stall-check.yml"

# Strip HCL comments (/* ... */ blocks, `#` and `//` line comments) OUTSIDE string literals, preserving line
# structure. Every tf read below goes through this, so a commented-out COPY of the old merge_queue block (or of a
# `context = "CodeQL"` row) can never be parsed as the real thing and mask changed real values (#9454 L17).
_mq_strip_hcl() {
  python3 - "$1" <<'PYSTRIP'
import sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []; i = 0; n = len(s); instr = False
while i < n:
    c = s[i]
    if instr:
        out.append(c)
        if c == "\\" and i + 1 < n:
            out.append(s[i + 1]); i += 2; continue
        if c == '"':
            instr = False
        i += 1; continue
    if c == '"':
        instr = True; out.append(c); i += 1; continue
    if s.startswith("/*", i):
        j = s.find("*/", i + 2)
        if j < 0:
            break          # unterminated block comment: drop the rest; the 7-param floor then reds
        out.append("\n" * s.count("\n", i, j)); i = j + 2; continue
    if c == "#" or s.startswith("//", i):
        while i < n and s[i] != "\n":
            i += 1
        continue
    out.append(c); i += 1
sys.stdout.write("".join(out))
PYSTRIP
}

# Parse the merge_queue block of an HCL file (comments stripped) to sorted `key=value` lines.
_mq_parse_tf() {
  _mq_strip_hcl "$1" | awk '
    /^[[:space:]]*merge_queue[[:space:]]*\{/ { blk=1; next }
    blk && /^[[:space:]]*\}/ { exit }
    blk && /^[[:space:]]*[a-z_]+[[:space:]]*=/ {
      line=$0
      k=line; sub(/^[[:space:]]*/, "", k); sub(/[[:space:]]*=.*/, "", k)
      v=line; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"[[:space:]]*$/, "", v); sub(/[[:space:]]+$/, "", v)
      print k "=" v
    }' | sort
}

# Parse the DR skeleton heredoc's merge_queue rule (selected by .type) to sorted `key=value` lines.
_mq_parse_dr() {
  sed -n "/cat > \"\$skeleton\" << 'EOF'/,/^EOF\$/p" "$1" | sed '1d;$d' \
    | jq -r '.rules[] | select(.type=="merge_queue") | .parameters | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null | sort || true
}

# Parse the README params table rows to sorted `key=value` lines (only the seven known params).
_mq_parse_readme() {
  awk -F'|' -v want="$MQ_PARAMS" '
    BEGIN { n=split(want, a, " "); for (i=1; i<=n; i++) ok[a[i]]=1 }
    NF >= 4 {
      k=$2; gsub(/[ `]/, "", k); v=$3; gsub(/[ `]/, "", v)
      if (k in ok) print k "=" v
    }' "$1" | sort -u
}

# Value of <key> in a sorted `key=value` block ($1).
_mq_val() { sed -n "s/^$2=//p" <<<"$1" | head -1; }

# STALL_THRESHOLD_MINUTES from the stall workflow ($1); empty when absent/non-numeric.
_mq_stall_threshold() {
  sed -nE "s/^[[:space:]]*STALL_THRESHOLD_MINUTES:[[:space:]]*'?([0-9]+)'?[[:space:]]*(#.*)?\$/\\1/p" "$1" 2>/dev/null | head -1
}

# Positive evidence that the queue is OFF in every source: no `merge_queue` token in the comment-stripped tf, a
# PARSEABLE DR skeleton with no rule whose type mentions merge_queue, and no README table row naming any of the
# seven params. "Parsed to nothing" is NOT evidence (a renamed block key parses to nothing too, T-mq-1.m5), which
# is why an unparseable skeleton or any leftover token keeps the 0-params floor RED.
_mq_queue_absent() {
  local tf="$1" dr="$2" readme="$3" skel
  if _mq_strip_hcl "$tf" | grep -q 'merge_queue'; then return 1; fi
  skel=$(sed -n "/cat > \"\$skeleton\" << 'EOF'/,/^EOF\$/p" "$dr" | sed '1d;$d')
  jq -e '(.rules | type == "array") and all(.rules[]; ((.type // "") | test("merge_queue") | not))' <<<"$skel" >/dev/null 2>&1 || return 1
  if awk -v want="$MQ_PARAMS" '
      BEGIN { n=split(want, a, " ") }
      /^[[:space:]]*\|/ { for (i=1; i<=n; i++) if (index($0, a[i])) found=1 }
      END { exit found ? 0 : 1 }' "$readme"; then return 1; fi
  return 0
}

# _mq_guard2 <tf> <dr> <readme> <canonical-rsc.json> [stall-workflow]; returns 0 = parity + safety hold (or the
# queue is OFF everywhere), 1 = violation (reason in MQ_REASON). Order matters: the vacuity floor runs first so
# "everything parsed to nothing" can never read as "everything matches".
_mq_guard2() {
  local tf="$1" dr="$2" readme="$3" canon="$4" wf="${5:-$MQ_STALL_WF}"
  MQ_REASON=""
  local tf_p dr_p rd_p n_tf n_dr n_rd
  tf_p=$(_mq_parse_tf "$tf"); dr_p=$(_mq_parse_dr "$dr"); rd_p=$(_mq_parse_readme "$readme")
  n_tf=$(grep -c . <<<"$tf_p" || true); n_dr=$(grep -c . <<<"$dr_p" || true); n_rd=$(grep -c . <<<"$rd_p" || true)
  if (( n_tf + n_dr + n_rd == 0 )); then
    # Queue OFF (a rollback of #9454): every source POSITIVELY lacks the queue. The CodeQL-absent invariant and the
    # safety values are queue-on invariants, so a rollback that re-adds CodeQL must not red here.
    if _mq_queue_absent "$tf" "$dr" "$readme"; then
      MQ_REASON="queue off: no merge_queue block in the tf, the DR skeleton or the README (rollback state); parity and safety values not applicable"
      return 0
    fi
    MQ_REASON="0 params compared (no merge_queue params parsed from any source)"; return 1
  fi
  if (( n_tf != 7 )); then MQ_REASON="tf carries $n_tf of 7 merge_queue params"; return 1; fi
  if (( n_dr != 7 )); then MQ_REASON="DR skeleton carries $n_dr of 7 merge_queue params"; return 1; fi
  if (( n_rd != 7 )); then MQ_REASON="README table carries $n_rd of 7 merge_queue params"; return 1; fi
  if [[ "$dr_p" != "$tf_p" ]]; then
    MQ_REASON="DR skeleton params != tf: $(diff <(echo "$tf_p") <(echo "$dr_p") | tr '\n' ' ')"; return 1
  fi
  if [[ "$rd_p" != "$tf_p" ]]; then
    MQ_REASON="README params != tf: $(diff <(echo "$tf_p") <(echo "$rd_p") | tr '\n' ' ')"; return 1
  fi
  # SAFETY VALUES (not just parity: three sources can agree on a dangerous value).
  #  - max_entries_to_merge == 1: merge-queue-cla-verify.sh takes the PR number from head_ref, which is exact only
  #    for a one-PR group.
  #  - merge_method == SQUASH: matches `gh pr merge --squash` and the repo's linear-history contract.
  #  - check_response_timeout_minutes > the stall probe's threshold: else the probe cannot report before the queue
  #    ejects the entry silently.
  local me mm to thr
  me=$(_mq_val "$tf_p" max_entries_to_merge); mm=$(_mq_val "$tf_p" merge_method); to=$(_mq_val "$tf_p" check_response_timeout_minutes)
  if [[ "$me" != "1" ]]; then
    MQ_REASON="max_entries_to_merge=$me, must be 1 (the CLA verify takes the PR number from head_ref; a larger group batches PRs)"; return 1
  fi
  if [[ "$mm" != "SQUASH" ]]; then MQ_REASON="merge_method=$mm, must be SQUASH"; return 1; fi
  thr=$(_mq_stall_threshold "$wf")
  if [[ ! "$thr" =~ ^[0-9]+$ ]]; then MQ_REASON="stall threshold not derivable from $wf (STALL_THRESHOLD_MINUTES missing or non-numeric)"; return 1; fi
  if [[ ! "$to" =~ ^[0-9]+$ ]] || (( to <= thr )); then
    MQ_REASON="check_response_timeout_minutes ($to) must exceed STALL_THRESHOLD_MINUTES ($thr): the probe could not report before the queue ejects the entry"; return 1
  fi
  # CodeQL-absent invariant. tf: comment-stripped (line AND block) `context = "CodeQL"`; DR: any context in the
  # skeleton JSON; canonical: any row.
  if _mq_strip_hcl "$tf" | grep -qE 'context[[:space:]]*=[[:space:]]*"CodeQL"'; then
    MQ_REASON="CodeQL required_check present in tf alongside a merge_queue block"; return 1
  fi
  local dr_codeql
  dr_codeql=$(sed -n "/cat > \"\$skeleton\" << 'EOF'/,/^EOF\$/p" "$dr" | sed '1d;$d' \
    | jq -r '[.. | .context? // empty] | map(select(. == "CodeQL")) | length' 2>/dev/null || echo "unparseable")
  if [[ "$dr_codeql" != "0" ]]; then
    MQ_REASON="CodeQL context present in DR skeleton alongside a merge_queue rule (count=$dr_codeql)"; return 1
  fi
  if jq -e 'any(.[]; .context == "CodeQL")' "$canon" >/dev/null 2>&1; then
    MQ_REASON="CodeQL row present in canonical required_status_checks alongside a merge_queue rule"; return 1
  fi
  return 0
}

# Copy the four real sources into a scratch dir (pristine/ and work/); the dir is left in MQ_STAGE_DIR
# (NOT echoed: a command substitution would register it for cleanup in a subshell and lose it).
_mq_stage() {
  local d; d=$(mktemp -d)
  MQ_STAGE_DIRS+=("$d")
  mkdir -p "$d/pristine" "$d/work"
  cp "$REPO_ROOT/infra/github/ruleset-ci-required.tf" "$d/pristine/tf"
  cp "$REPO_ROOT/scripts/create-ci-required-ruleset.sh" "$d/pristine/dr"
  cp "$REPO_ROOT/infra/github/README.md" "$d/pristine/readme"
  cp "$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json" "$d/pristine/canon"
  cp "$MQ_STALL_WF" "$d/pristine/wf"
  cp "$d/pristine/"* "$d/work/"
  MQ_STAGE_DIR="$d"
}

# T-mq-1 (real repo): parity holds on the live sources.
t_mq_param_parity_real() {
  # Optional positional overrides (tf dr readme canon) exist only so t_mq_controls can drive this invocation
  # with an input that must fail; the suite itself always calls it with no arguments.
  local tf="${1:-$REPO_ROOT/infra/github/ruleset-ci-required.tf}"
  local dr="${2:-$REPO_ROOT/scripts/create-ci-required-ruleset.sh}"
  local readme="${3:-$REPO_ROOT/infra/github/README.md}"
  local canon="${4:-$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json}"
  local f
  for f in "$tf" "$dr" "$readme" "$canon"; do
    if [[ ! -f "$f" ]]; then _report "T-mq-1 merge_queue source files exist" fail "missing $f"; return; fi
  done
  if _mq_guard2 "$tf" "$dr" "$readme" "$canon"; then
    _report "T-mq-1 merge_queue param parity (.tf == DR skeleton == README, 7 params) + CodeQL absent" ok
  else
    _report "T-mq-1 merge_queue param parity (.tf == DR skeleton == README, 7 params) + CodeQL absent" fail "$MQ_REASON"
  fi
}

# Mutation row: stage the real sources, apply one mutation (a sed -E script, or the literal
# `JQ:<filter>` for the JSON file, or `FN:<function>` called as `fn <src> <dst>`) to the named files, PROVE the mutation landed (cmp against the
# pristine copy), then require the guard to go RED with the expected reason.
#   _mq_mutation <label> <expected-reason-regex> <file-key[,file-key...]> <sed-script|JQ:filter>
# File keys: tf | dr | readme | canon | wf (the stall workflow). A row that would pass for the wrong reason is a FAIL.
_mq_mutation() {
  local label="$1" want="$2" keys="$3" script="$4"
  local d; _mq_stage; d="$MQ_STAGE_DIR"
  local k landed=1
  for k in ${keys//,/ }; do
    case "$script" in
      JQ:*) jq "${script#JQ:}" "$d/pristine/$k" > "$d/work/$k" ;;
      FN:*) "${script#FN:}" "$d/pristine/$k" "$d/work/$k" ;;
      *)    sed -E "$script" "$d/pristine/$k" > "$d/work/$k" ;;
    esac
    if cmp -s "$d/pristine/$k" "$d/work/$k"; then landed=0; fi
  done
  if [[ "$landed" == "0" ]]; then
    _report "$label" fail "mutation did not land (mutated copy identical to pristine)"
    rm -rf "$d"; return
  fi
  if _mq_guard2 "$d/work/tf" "$d/work/dr" "$d/work/readme" "$d/work/canon" "$d/work/wf"; then
    _report "$label" fail "guard stayed GREEN under the mutation"
  elif grep -qE "$want" <<<"$MQ_REASON"; then
    _report "$label" ok
  else
    _report "$label" fail "RED for the wrong reason: '$MQ_REASON' (wanted /$want/)"
  fi
  rm -rf "$d"
}


# Mutation helper for T-mq-1.m8: put a /* ... */ commented COPY of the pristine merge_queue block ahead of
# the real block and change a real value (timeout 60 -> 30) in the real block only. A parser that matches the
# commented copy first compares the stale values and goes green over the real drift.
_mq_mut_commented_old_block() {
  awk '
    /^[[:space:]]*merge_queue[[:space:]]*\{/ && !done { inblk=1; buf=$0 "\n"; mod=$0 "\n"; next }
    inblk {
      buf = buf $0 "\n"; l=$0
      if (l ~ /check_response_timeout_minutes/) sub(/=[[:space:]]*60/, "= 30", l)
      mod = mod l "\n"
      if ($0 ~ /^[[:space:]]*\}/) { printf "/*\n%s*/\n%s", buf, mod; inblk=0; done=1 }
      next
    }
    { print }' "$1" > "$2"
}

# shellcheck disable=SC2016  # sed scripts are single-quoted on purpose; backticks are literal README markup
t_mq_mutations() {
  # 1 — DR skeleton timeout drifts from the .tf (only the skeleton changes)
  _mq_mutation "T-mq-1.m1 DR skeleton check_response_timeout_minutes drift -> RED" \
    'DR skeleton params != tf' dr \
    's/("check_response_timeout_minutes":[[:space:]]*)[0-9]+/\199/'
  # 2 — CodeQL required_check re-added to the .tf while the queue block exists
  _mq_mutation "T-mq-1.m2 CodeQL re-added to .tf beside merge_queue -> RED" \
    'CodeQL required_check present in tf' tf \
    '0,/^([[:space:]]*)required_check \{/s//\1required_check {\n\1  context        = "CodeQL"\n\1  integration_id = var.codeql_integration_id\n\1}\n\1required_check {/'
  # 3 — CodeQL re-added to the DR skeleton only (second source after a compliant first)
  _mq_mutation "T-mq-1.m3 CodeQL re-added to DR skeleton only -> RED" \
    'CodeQL context present in DR skeleton' dr \
    's/"required_status_checks":[[:space:]]*\[\]/"required_status_checks": [{"context":"CodeQL","integration_id":57789}]/'
  # 4 — merge_queue block deleted from the .tf but not from the DR skeleton / README
  _mq_mutation "T-mq-1.m4 merge_queue block deleted from .tf only -> RED" \
    'tf carries 0 of 7' tf \
    '/^[[:space:]]*merge_queue[[:space:]]*\{/,/^[[:space:]]*\}/d'
  # 5 — guard-dispatch floor: the block key renamed in EVERY source, so each parses to zero
  # params and "all sources equal" is vacuously true. Only the floor can catch it.
  _mq_mutation "T-mq-1.m5 block key renamed in all sources (vacuous equality) -> RED via 0-params floor" \
    '0 params compared' tf,dr,readme \
    's/^([[:space:]]*)merge_queue([[:space:]]*\{)/\1merge_queue_renamed\2/; s/"type":[[:space:]]*"merge_queue"/"type": "merge_queue_renamed"/; s/^\|([[:space:]]*)`(merge_method|grouping_strategy|max_entries_to_merge|min_entries_to_merge|min_entries_to_merge_wait_minutes|max_entries_to_build|check_response_timeout_minutes)`/|\1`renamed_\2`/'
  # 6 (extra) — CodeQL re-added to the canonical JSON beside a live queue
  _mq_mutation "T-mq-1.m6 CodeQL row re-added to canonical JSON -> RED" \
    'CodeQL row present in canonical' canon \
    'JQ:. + [{"context":"CodeQL","integration_id":57789}]'
  # 7 (extra) — README table value drifts (third source)
  _mq_mutation "T-mq-1.m7 README max_entries_to_build drift -> RED" \
    'README params != tf' readme \
    's/^(\|[[:space:]]*`max_entries_to_build`[[:space:]]*\|[[:space:]]*`)[0-9]+/\199/'
  # 8 — a /* */ block-comment copy of the OLD merge_queue block ahead of the real one, real timeout
  # changed in the .tf only: the stale commented values must not mask the real drift (the DR/README
  # still say 60, so the guard must go RED on parity against the REAL value).
  _mq_mutation "T-mq-1.m8 /* */ commented stale block ahead of a drifted real block -> RED" \
    'DR skeleton params != tf' tf \
    'FN:_mq_mut_commented_old_block'
  # 9-11 — SAFETY VALUES, changed consistently in all three sources so PARITY still holds and only
  # the safety assertion can catch it.
  _mq_mutation "T-mq-1.m9 max_entries_to_merge 1 -> 2 in tf+DR+README (parity holds) -> RED on the safety value" \
    'max_entries_to_merge' tf,dr,readme \
    's/(max_entries_to_merge[[:space:]]*=[[:space:]]*)1/\12/; s/("max_entries_to_merge":[[:space:]]*)1/\12/; s/^(\|[[:space:]]*`max_entries_to_merge`[[:space:]]*\|[[:space:]]*`)1/\12/'
  _mq_mutation "T-mq-1.m10 merge_method SQUASH -> MERGE in tf+DR+README (parity holds) -> RED on the safety value" \
    'merge_method' tf,dr,readme \
    's/(merge_method[[:space:]]*=[[:space:]]*")SQUASH/\1MERGE/; s/("merge_method":[[:space:]]*")SQUASH/\1MERGE/; s/^(\|[[:space:]]*`merge_method`[[:space:]]*\|[[:space:]]*`)SQUASH/\1MERGE/'
  _mq_mutation "T-mq-1.m11 check_response_timeout_minutes 60 -> 30 in tf+DR+README (parity holds, below the stall threshold) -> RED" \
    'must exceed STALL_THRESHOLD_MINUTES' tf,dr,readme \
    's/(check_response_timeout_minutes[[:space:]]*=[[:space:]]*)60/\130/; s/("check_response_timeout_minutes":[[:space:]]*)60/\130/; s/^(\|[[:space:]]*`check_response_timeout_minutes`[[:space:]]*\|[[:space:]]*`)60/\130/'
  _mq_mutation "T-mq-1.m12 stall workflow threshold raised to 60 (>= timeout) -> RED" \
    'must exceed STALL_THRESHOLD_MINUTES' wf \
    "s/(STALL_THRESHOLD_MINUTES:[[:space:]]*')45'/\160'/"
  _mq_mutation "T-mq-1.m13 stall workflow threshold made non-numeric (underivable) -> RED" \
    'stall threshold not derivable' wf \
    "s/(STALL_THRESHOLD_MINUTES:[[:space:]]*')45'/\1soon'/"
}

# ---- queue-OFF (rollback) state, #9454 L5 ----
# Write a synthetic rollback-shaped source set into <dir>: no merge_queue block / rule / README rows anywhere,
# and the CodeQL required check RE-ADDED to the tf, the DR skeleton and the canonical JSON (what a revert of
# the queue adoption does). Guard 2 must not red on it; a half-removed state must still red.
_mq_write_off_sources() {
  local d="$1"
  assert_fixture_dir "$d"
  cat > "$d/tf" <<'FIX'
resource "x" "y" {
  rules {
    required_status_checks {
      required_check {
        context        = "CodeQL"
        integration_id = 57789
      }
    }
  }
}
FIX
  cat > "$d/dr" <<'FIX'
cat > "$skeleton" << 'EOF'
{
  "rules": [
    {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context":"CodeQL","integration_id":57789}]}}
  ]
}
EOF
FIX
  # shellcheck disable=SC2016  # backticks are literal README markup
  printf '%s\n' '| Param | Value |' '|---|---|' '| `unrelated` | `1` |' > "$d/readme"
  printf '%s' '[{"context":"test","integration_id":15368},{"context":"CodeQL","integration_id":57789}]' > "$d/canon"
}
_mq_write_queue_block() { # <tf-file> : append a complete, parity-valid merge_queue block to the tf
  cat >> "$1" <<'FIX'
resource "x" "q" {
  rules {
    merge_queue {
      merge_method                      = "SQUASH"
      grouping_strategy                 = "ALLGREEN"
      max_entries_to_merge              = 1
      min_entries_to_merge              = 1
      min_entries_to_merge_wait_minutes = 0
      max_entries_to_build              = 2
      check_response_timeout_minutes    = 60
    }
  }
}
FIX
}

# One fixture row: <label> <want: green|red> <reason-regex> <variant>
_mq_off_row() {
  local label="$1" want="$2" rx="$3" variant="$4" rc
  local d; d=$(mktemp -d); assert_fixture_dir "$d"; MQ_STAGE_DIRS+=("$d")
  _mq_write_off_sources "$d"
  case "$variant" in
    off) : ;;
    dr-only)     cp "$REPO_ROOT/scripts/create-ci-required-ruleset.sh" "$d/dr" ;;
    readme-only) cp "$REPO_ROOT/infra/github/README.md" "$d/readme" ;;
    tf-only)     _mq_write_queue_block "$d/tf" ;;
    # An unparseable queue token in the tf (a dynamic block parses to no params) with DR and README clean: only the tf
    # token arm of _mq_queue_absent keeps this RED.
    tf-token)
      printf '%s\n' 'resource "x" "dyn" {' '  dynamic "merge_queue" {' '    for_each = []' '  }' '}' >> "$d/tf" ;;
    # A README table row that names a queue param but does not parse as a `| param | value |` row: only the README arm
    # of _mq_queue_absent keeps this RED.
    readme-stray)
      # shellcheck disable=SC2016  # backticks are literal README markup
      printf '%s\n' '| see `max_entries_to_build` in the tf | n/a |' >> "$d/readme" ;;
  esac
  if _mq_guard2 "$d/tf" "$d/dr" "$d/readme" "$d/canon" "$MQ_STALL_WF"; then rc=0; else rc=$?; fi
  if [[ "$want" == "green" ]]; then
    if [[ "$rc" -eq 0 ]] && grep -qE "$rx" <<<"$MQ_REASON"; then _report "$label" ok; else _report "$label" fail "rc=$rc reason='$MQ_REASON' (wanted GREEN /$rx/)"; fi
  else
    if [[ "$rc" -ne 0 ]] && grep -qE "$rx" <<<"$MQ_REASON"; then _report "$label" ok; else _report "$label" fail "rc=$rc reason='$MQ_REASON' (wanted RED /$rx/)"; fi
  fi
}

t_mq_queue_off() {
  # The rollback PR re-adds CodeQL in tf + DR + canonical while the queue is removed everywhere: GREEN, "queue off".
  _mq_off_row "T-mq-1.off1 queue off everywhere + CodeQL re-added in tf/DR/canonical (rollback) -> GREEN 'queue off'" \
    green 'queue off' off
  # Half-removed states are inconsistencies, never "queue off": each must stay RED.
  _mq_off_row "T-mq-1.off2 queue rule left ONLY in the DR skeleton -> RED" red 'tf carries 0 of 7' dr-only
  _mq_off_row "T-mq-1.off3 queue params left ONLY in the README table -> RED" red 'tf carries 0 of 7' readme-only
  _mq_off_row "T-mq-1.off4 queue block left ONLY in the tf -> RED" red 'DR skeleton carries 0 of 7' tf-only
  # The two evidence arms that the per-source rows above never reach (they exit earlier on the per-source floors):
  # every source parses to ZERO params, yet a queue token / a queue-param table row survives. The queue is NOT proven
  # off, so the 0-params floor must stay RED.
  _mq_off_row "T-mq-1.off5 unparseable merge_queue token in the tf (dynamic block), DR and README clean -> RED" red '0 params compared' tf-token
  _mq_off_row "T-mq-1.off6 stray README table row naming a queue param, tf and DR clean -> RED" red '0 params compared' readme-stray
}

# H2 (must-PASS, non-canonical): the SAME values in a different layout — aligned `=` with
# trailing `# comments`, keys reordered in the .tf and in the skeleton, README rows reordered and
# unpadded. A guard that only recognises the real files' exact layout fails here.
t_mq_param_parity_noncanonical_pass() {
  local d; d=$(mktemp -d)
  cat > "$d/tf" <<'FIX'
resource "x" "y" {
  rules {
    required_status_checks {
      required_check {
        context        = "test"   # a comment with context = "CodeQL" in it stays inert
        integration_id = 15368
      }
    }
    # merge_queue { in a comment must not start a block
    merge_queue {
      check_response_timeout_minutes    = 60  # trailing comment
      merge_method                      = "SQUASH"       # aligned
      max_entries_to_build              = 2
      grouping_strategy                 = "ALLGREEN"
      min_entries_to_merge_wait_minutes = 0
      min_entries_to_merge              = 1
      max_entries_to_merge              = 1
    }
  }
}
FIX
  cat > "$d/dr" <<'FIX'
cat > "$skeleton" << 'EOF'
{
  "rules": [
    {"type": "merge_queue", "parameters": {
      "min_entries_to_merge_wait_minutes": 0, "max_entries_to_build": 2,
      "check_response_timeout_minutes": 60, "merge_method": "SQUASH",
      "grouping_strategy": "ALLGREEN", "max_entries_to_merge": 1, "min_entries_to_merge": 1}},
    {"type": "required_status_checks", "parameters": {"required_status_checks": []}}
  ]
}
EOF
FIX
  cat > "$d/readme" <<'FIX'
| Param | Value |
|---|---|
|`check_response_timeout_minutes`|`60`|
| `max_entries_to_build` | 2 |
| `merge_method` | `SQUASH` |
| `min_entries_to_merge_wait_minutes` | `0` |
| `grouping_strategy` | `ALLGREEN` |
| `max_entries_to_merge` | `1` |
| `min_entries_to_merge` | `1` |
FIX
  printf '%s' '[{"context":"test","integration_id":15368}]' > "$d/canon"
  if _mq_guard2 "$d/tf" "$d/dr" "$d/readme" "$d/canon"; then
    _report "T-mq-1.H2 must-PASS non-canonical layout (aligned =, trailing comments, reordered keys) -> GREEN" ok
  else
    _report "T-mq-1.H2 must-PASS non-canonical layout (aligned =, trailing comments, reordered keys) -> GREEN" fail "$MQ_REASON"
  fi
  rm -rf "$d"
}

# ---- Guard 2 controls: the guard and its row batteries must be provably FALSIFIABLE (#9454 L17/L18) ----
# Every Guard 2 invocation is driven once with an input that MUST fail, and its verdict recorded through printf
# (never through the helper under test). `_mq_drive_must_fail` runs a battery, requires >= 1 recorded failure
# (and, for batteries stubbed to a wrong-verdict guard, zero passes), then RESTORES the counters so the driven
# failures do not count as suite failures.
_mq_drive_must_fail() {
  local label="$1" strict="$2"; shift 2
  local p0="$pass" f0="$fail" m0="$MQ_OK" df dp
  "$@" >/dev/null 2>&1 || true
  df=$((fail - f0)); dp=$((pass - p0))
  pass="$p0"; fail="$f0"; MQ_OK="$m0"
  if (( df >= 1 )) && { [[ "$strict" != "strict" ]] || (( dp == 0 )); }; then
    _report "$label" ok
  else
    _report "$label" fail "driven with a must-fail input but recorded failures=$df passes=$dp"
  fi
}

# Run "$@" with _mq_guard2 temporarily replaced by an always-green (green) or always-red (red) stub, then restore it.
_mq_with_guard_stub() {
  local mode="$1"; shift
  local saved; saved="$(declare -f _mq_guard2)"
  # shellcheck disable=SC2329  # the stubs are invoked indirectly, by the battery run below
  if [[ "$mode" == "green" ]]; then _mq_guard2() { MQ_REASON=""; return 0; }; else _mq_guard2() { MQ_REASON="stub: always red"; return 1; }; fi
  "$@" || true
  eval "$saved"
}

# Run "$@" with _mq_queue_absent temporarily replaced by a sed-mutated copy of ITS OWN source text (read from this file, so
# the mutation is of the real function), then restore it. A mutation that does not land is a FATAL, by printf + exit.
_mq_with_absent_mutated() {
  local expr="$1"; shift
  local saved src mutated
  saved="$(declare -f _mq_queue_absent)"
  src="$(sed -n '/^_mq_queue_absent() {/,/^}/p' "${BASH_SOURCE[0]}")"
  mutated="$(sed -E "$expr" <<<"$src")"
  if [[ -z "$src" || "$mutated" == "$src" ]]; then
    printf '[FATAL] _mq_queue_absent mutation did not land: %s\n' "$expr" >&2; exit 1
  fi
  eval "$mutated"
  "$@" || true
  eval "$saved"
}

t_mq_controls() {
  local e; e=$(mktemp -d); assert_fixture_dir "$e"; MQ_STAGE_DIRS+=("$e")
  : > "$e/empty"
  # 1. The engine itself rejects four empty sources (so it cannot be an unconditional return 0).
  if _mq_guard2 "$e/empty" "$e/empty" "$e/empty" "$e/empty"; then
    _report "T-mq-ctl1 guard rejects four EMPTY sources (0-params floor, not a vacuous green)" fail "guard returned 0"
  else
    _report "T-mq-ctl1 guard rejects four EMPTY sources (0-params floor, not a vacuous green)" ok
  fi
  # 2-5. Each of the four Guard 2 invocations, driven with an input that must fail.
  _mq_drive_must_fail "T-mq-ctl2 real-source parity invocation reds on empty sources" strict \
    t_mq_param_parity_real "$e/empty" "$e/empty" "$e/empty" "$e/empty"
  _mq_drive_must_fail "T-mq-ctl3 mutation battery reds when the guard is neutered to always-green (every row must red)" strict \
    _mq_with_guard_stub green t_mq_mutations
  _mq_drive_must_fail "T-mq-ctl4 non-canonical must-PASS invocation reds when the guard always rejects" strict \
    _mq_with_guard_stub red t_mq_param_parity_noncanonical_pass
  _mq_drive_must_fail "T-mq-ctl5 queue-off battery reds when the guard is neutered to always-green (half-removed rows must red)" "" \
    _mq_with_guard_stub green t_mq_queue_off
  # 6-7. The two queue-off evidence arms are PINNED: removing either from _mq_queue_absent must red the queue-off battery.
  _mq_drive_must_fail "T-mq-ctl6 queue-off battery reds when _mq_queue_absent loses its tf merge_queue token arm" "" \
    _mq_with_absent_mutated "s/^  if _mq_strip_hcl \"\\\$tf\" \\| grep -q 'merge_queue'; then return 1; fi\$/  :/" t_mq_queue_off
  _mq_drive_must_fail "T-mq-ctl7 queue-off battery reds when _mq_queue_absent loses its README arm" "" \
    _mq_with_absent_mutated 's/exit found \? 0 : 1/exit 1/' t_mq_queue_off
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
    | sed -E 's/.*"([^"]+)"$/\1/' | sort || true)
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

# --- Marketplace ruleset canonical↔terraform sync gates (#7493) --------------------------------
# WHY THESE EXIST, stated plainly because their absence was the review's worst finding.
# Guard 1 (scripts/verify-marketplace-ruleset.sh) compares the LIVE ruleset against the canonical,
# and it runs POST-APPLY. Nothing compared the canonical — or the rule values Guard 1 asserts —
# against the `.tf` that actually creates the ruleset. Measured on this feature's own branch:
# setting `required_approving_review_count = 0` AND adding a fourth bypass actor to the `.tf`
# left ALL FIVE suites green, because every suite reads the canonical or a fixture and none reads
# the `.tf`. That widening would merge, apply LIVE to the plugin's distribution channel, and only
# then redden — after the ruleset it weakened was already in force. Both sibling rulesets already
# carry this gate (T-rsc-9, T-cla-1b); this one shipped without it.
MP_TF="$REPO_ROOT/infra/github/ruleset-marketplace-pr-required.tf"
MP_BYPASS_CANONICAL="$REPO_ROOT/scripts/marketplace-ruleset-canonical-bypass-actors.json"

# T-mp-1b: the `.tf` bypass_actors triples MUST equal the canonical, with the `.tf`'s
# OrganizationAdmin `actor_id = 0` sentinel (provider issue #2536) normalized to the canonical's
# `null` (the canonical mirrors the LIVE API shape). Same extraction mechanism as T-cla-1b.
t_mp_bypass_canonical_matches_tf() {
  if [[ ! -f "$MP_TF" ]]; then
    _report "T-mp-1b marketplace terraform ruleset source exists" fail "missing $MP_TF"
    return
  fi
  if [[ ! -f "$MP_BYPASS_CANONICAL" ]]; then
    _report "T-mp-1b marketplace bypass canonical exists" fail "missing $MP_BYPASS_CANONICAL"
    return
  fi
  local tf_triples
  tf_triples=$(awk '
    /^[[:space:]]*bypass_actors[[:space:]]*\{/ {blk=1; aid="null"; at=""; bm=""; next}
    blk && /^[[:space:]]*actor_id[[:space:]]*=/    {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*/,"",v);  sub(/[[:space:]]*$/,"",v); aid=v}
    blk && /^[[:space:]]*actor_type[[:space:]]*=/  {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*$/,"",v); at=v}
    blk && /^[[:space:]]*bypass_mode[[:space:]]*=/ {v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*$/,"",v); bm=v}
    blk && /^[[:space:]]*\}/ {print aid"|"at"|"bm; blk=0}
  ' "$MP_TF" | sed 's/^0|/null|/' | sort)
  local canon_triples
  canon_triples=$(jq -r '.[] | "\(.actor_id)|\(.actor_type)|\(.bypass_mode)"' "$MP_BYPASS_CANONICAL" | sort)
  local dup
  dup=$(jq -r '(map("\(.actor_id)|\(.actor_type)|\(.bypass_mode)")) as $k | ($k | length) - ($k | unique | length)' "$MP_BYPASS_CANONICAL")
  # Non-vacuity floor (== 3): OrgAdmin + RepoRole 5 + soleur-ai Integration, and NO MORE. An
  # equality floor rather than `>=` is deliberate here — the whole point is that a FOURTH actor
  # is the widening that matters, so the floor must not be satisfiable by adding one.
  local n_canon
  n_canon=$(jq 'length' "$MP_BYPASS_CANONICAL")
  if [[ "$tf_triples" == "$canon_triples" && "$dup" == "0" && "$n_canon" -eq 3 ]]; then
    _report "T-mp-1b marketplace bypass canonical triples == ruleset-marketplace-pr-required.tf (0↔null) + no-dup + exactly 3" ok
  else
    _report "T-mp-1b marketplace bypass canonical triples == ruleset-marketplace-pr-required.tf (0↔null) + no-dup + exactly 3" fail \
      "dup=$dup n_canon=$n_canon diff:$(diff <(echo "$canon_triples") <(echo "$tf_triples") | tr '\n' ' ')"
  fi
}

# T-mp-1c: the RULE VALUES Guard 1 asserts at runtime MUST be what the `.tf` declares. Guard 1's
# fixtures encode the expected values as literals; if the `.tf` drifts from them, Guard 1 keeps
# passing 22/22 against its fixtures while the live ruleset it verifies is weaker than the
# fixtures claim. This is the row that catches `required_approving_review_count = 0`.
t_mp_rule_values_match_tf() {
  if [[ ! -f "$MP_TF" ]]; then
    _report "T-mp-1c marketplace terraform ruleset source exists" fail "missing $MP_TF"
    return
  fi
  # Read each value from the `.tf`, stripping trailing comments before the value slice (SE-3).
  _mp_tf_val() {
    awk -v key="$1" '
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        v=$0; sub(/#.*/,"",v); sub(/.*=[[:space:]]*/,"",v)
        gsub(/^"|"[[:space:]]*$/,"",v); sub(/[[:space:]]*$/,"",v); print v; exit
      }' "$MP_TF"
  }
  local enforcement approvals target include exclude problems=()
  enforcement="$(_mp_tf_val enforcement)"
  approvals="$(_mp_tf_val required_approving_review_count)"
  target="$(_mp_tf_val target)"
  include="$(_mp_tf_val include)"
  exclude="$(_mp_tf_val exclude)"

  [[ "$enforcement" == "active" ]] || problems+=("enforcement='$enforcement' expected 'active'")
  # The literal 1 is this feature's own shipped defect. `required_approving_review_count` has NO
  # provider default — omitting it yields 0, and a 0-approval PR requirement closes nothing
  # against actors already holding pull_requests:write.
  [[ "$approvals" == "1" ]] || problems+=("required_approving_review_count='$approvals' expected '1'")
  [[ "$target" == "branch" ]] || problems+=("target='$target' expected 'branch'")
  [[ "$include" == '["~DEFAULT_BRANCH"]' ]] || problems+=("ref_name.include='$include' expected '[\"~DEFAULT_BRANCH\"]'")
  # A non-empty exclude subtracts exactly what include adds, leaving the ruleset active and
  # governing nothing. Guard 1 asserts this at runtime; nothing asserted it pre-merge.
  [[ "$exclude" == "[]" ]] || problems+=("ref_name.exclude='$exclude' expected '[]'")
  # deletion + non_fast_forward are the only UNCONDITIONAL protections; a PR flow routes around
  # neither, and an omission reads as false with no other symptom.
  grep -Eq '^[[:space:]]*deletion[[:space:]]*=[[:space:]]*true' "$MP_TF" \
    || problems+=("deletion = true not declared")
  grep -Eq '^[[:space:]]*non_fast_forward[[:space:]]*=[[:space:]]*true' "$MP_TF" \
    || problems+=("non_fast_forward = true not declared")

  if [[ "${#problems[@]}" -eq 0 ]]; then
    _report "T-mp-1c marketplace rule values == ruleset-marketplace-pr-required.tf (approvals/target/refs/deletion/nff)" ok
  else
    _report "T-mp-1c marketplace rule values == ruleset-marketplace-pr-required.tf (approvals/target/refs/deletion/nff)" fail \
      "$(printf '%s; ' "${problems[@]}")"
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
t_rsc_missing_context
t_rsc_codeql_wrong_app
t_rsc_live_missing_rsc_rule
t_rsc_canonical_invalid_schema
t_rsc_canonical_duplicate_context
t_rsc_order_insensitive
t_rsc_real_canonical_shape
t_rsc_shared_lib_used
t_rsc_canonical_matches_terraform
t_mq_param_parity_real
t_mq_mutations
t_mq_param_parity_noncanonical_pass
t_mq_queue_off
t_mq_controls

# CLA ruleset canonical↔terraform sync gates (#6061; Terraform-ified #6072)
t_cla_rsc_canonical_matches_tf
t_cla_bypass_canonical_matches_tf

# Marketplace ruleset canonical↔terraform sync gates (#7493)
t_mp_bypass_canonical_matches_tf
t_mp_rule_values_match_tf

echo "=== $pass passed, $fail failed ==="
# EXACT floor on the Guard 2 rows (printf + exit, independent of the verdict helpers it audits). Deleting a Guard
# 2 invocation, dropping a row, or neutering _report (which stops counting T-mq-* oks) moves MQ_OK off the
# constant. Update MQ_EXPECTED_OK deliberately when a Guard 2 row is added or removed.
MQ_EXPECTED_OK=28
if [[ "$MQ_OK" -ne "$MQ_EXPECTED_OK" ]]; then
  printf 'FAIL: Guard 2 reported %s ok T-mq rows, expected exactly %s (an invocation or row was deleted/added, or _report was neutered)\n' "$MQ_OK" "$MQ_EXPECTED_OK" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
