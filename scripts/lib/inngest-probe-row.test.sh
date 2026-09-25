#!/usr/bin/env bash
# inngest-probe-row.test.sh — suite for the shared dedicated-host probe-row predicate (#8846).
#
# Three layers:
#   1. Unit rows: the def accepts exactly {emitter == inngest-server-probe AND message begins
#      "SOLEUR_INNGEST_SERVER_PROBE "} and rejects the live event-log shape (SYSLOG_IDENTIFIER=
#      doppler quoting the marker) plus the forged anchored shape.
#   2. Guard 1 — census + emitter parity: every tracked file that names the marker either selects
#      through the shared predicate, sources the dark-gate lib (which does), or is on the reasoned
#      allowlist below. The literals must equal the emitter's own LOG_TAG and logger payload.
#   3. Guard 2 — FSM liveness counters: every _generation_scoped_count call passes a literal
#      emitter tag equal to its FSM's LOG_TAG.
#
# Auto-globbed by test-all.sh (`scripts/lib/*.test.sh`); no run_suite line needed.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/inngest-probe-row.sh"
MARKER_LIT='SOLEUR_INNGEST_SERVER_PROBE'

SANDBOX="$(mktemp -d -t inngest-probe-row.XXXXXXXX)" || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the verbatim body; see plugins/soleur/test/test-helpers.sh).
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

# Instrument self-test: drive both helpers once, require both counters to move, then reset.
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm)" 2>/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'instrument self-test failed: passes=%s fails=%s\n' "$passes" "$fails" >&2
  exit 1
fi
passes=0
fails=0

if [[ ! -f "$LIB" ]]; then
  printf 'library missing at scripts/lib/inngest-probe-row.sh\n' >&2
  exit 1
fi

# shellcheck source=scripts/lib/inngest-probe-row.sh
source "$LIB"

# ---------------------------------------------------------------------------
# 1. Unit rows
# ---------------------------------------------------------------------------

# grade <json-row> -> prints true|false (jq exit code checked)
grade() {
  local out rc=0
  out="$(printf '%s\n' "$1" | jq -c "$INNGEST_PROBE_ROW_JQ"' inngest_probe_row')" || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "jq_rc=$rc"; return 0; }
  echo "$out"
}

expect_grade() { # <label> <expected> <row>
  local got
  got="$(grade "$3")"
  if [[ "$got" == "$2" ]]; then pass "$1 -> $2"; else fail "$1: expected $2, got $got"; fi
}

expect_grade "probe emitter + anchored marker" true \
  '{"SYSLOG_IDENTIFIER":"inngest-server-probe","message":"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active"}'
expect_grade "LIVE shape: doppler event-log row quoting the marker mid-string" false \
  '{"SYSLOG_IDENTIFIER":"doppler","message":"{\"caller\":\"api\",\"event\":{\"data\":{\"body\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active\"}}}"}'
expect_grade "FORGED shape: doppler row whose message BEGINS with the marker" false \
  '{"SYSLOG_IDENTIFIER":"doppler","message":"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active"}'
expect_grade "probe emitter, message not starting with the marker" false \
  '{"SYSLOG_IDENTIFIER":"inngest-server-probe","message":"note: SOLEUR_INNGEST_SERVER_PROBE http_code=200"}'
expect_grade "object-valued message" false \
  '{"SYSLOG_IDENTIFIER":"inngest-server-probe","message":{"x":"SOLEUR_INNGEST_SERVER_PROBE "}}'
expect_grade "marker with no trailing space (prefix of a longer word)" false \
  '{"SYSLOG_IDENTIFIER":"inngest-server-probe","message":"SOLEUR_INNGEST_SERVER_PROBEX http_code=200"}'
expect_grade "missing SYSLOG_IDENTIFIER" false \
  '{"message":"SOLEUR_INNGEST_SERVER_PROBE http_code=200"}'
expect_grade "non-object row" false '"SOLEUR_INNGEST_SERVER_PROBE http_code=200"'
# Host isolation is the CALLER's job: a web-1 probe row is still a probe row here.
expect_grade "web-1 probe row (host is not this predicate's concern)" true \
  '{"host":"soleur-web-platform","host_name":"soleur-web-platform","SYSLOG_IDENTIFIER":"inngest-server-probe","message":"SOLEUR_INNGEST_SERVER_PROBE http_code=200"}'

# --selftest executed mode prints the literal the observability contract names.
out="$(bash "$LIB" --selftest 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "inngest-probe-row selftest: ok" ]]; then
  pass "--selftest prints the discoverability literal"
else
  fail "--selftest: rc=$rc out=$out"
fi

# A tampered copy (emitter clause removed) must fail its own selftest.
TAMPER="$SANDBOX/tampered.sh"
sed 's/ and \.SYSLOG_IDENTIFIER == \\"\${INNGEST_PROBE_EMITTER}\\"//' "$LIB" > "$TAMPER"
if cmp -s "$LIB" "$TAMPER"; then
  fail "tamper mutation did not land (the emitter clause spelling changed?)"
else
  rc=0; bash "$TAMPER" --selftest >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then pass "--selftest reds when the emitter clause is removed"; else fail "tampered --selftest rc=$rc (want 1)"; fi
fi

# The lib sets no shell options and is sourceable under set -u.
if bash -c 'set -u; . "$1"; [[ -n "$INNGEST_PROBE_ROW_JQ" ]]' _ "$LIB" 2>/dev/null; then
  pass "sourceable under set -u"
else
  fail "not sourceable under set -u"
fi
if grep -qE '^[[:space:]]*set[[:space:]]+[-+][a-z]' "$LIB"; then
  fail "the lib sets shell options (it must not — it is sourced into callers)"
else
  pass "the lib sets no shell options"
fi

# ---------------------------------------------------------------------------
# 2. Guard 1 — census
# ---------------------------------------------------------------------------

# Reasoned allowlist: files that name the marker but do not SELECT probe rows.
declare -A ALLOW=(
  ["apps/web-platform/infra/inngest-bootstrap.sh"]="the emitter itself"
  ["scripts/encryption-posture-ledger.json"]="prose in a ledger entry"
  ["scripts/test-all.sh"]="comment only"
  ["scripts/inngest-dedicated-host-classify.sh"]="pure classifier; selection lives in the workflow step that sources it"
  ["apps/web-platform/infra/betterstack-logs-alerts.tf"]="SQL alert, already anchored; emitter check deferred to #8874"
)

# discover <root> <file-list> -> the members of <file-list> (paths relative to <root>) that name
# the marker, after the structural exclusions.
discover() {
  local root="$1" list="$2" f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in
      knowledge-base/*|*.md|*.test.sh|*.test.ts|tests/scripts/test-*.sh|scripts/lib/inngest-probe-row.sh) continue ;;
    esac
    [[ -f "$root/$f" ]] || continue
    grep -qF "$MARKER_LIT" "$root/$f" && printf '%s\n' "$f"
  done < "$list"
  return 0
}

# uses_shared_rule <file>: a NON-COMMENT line selects through the def (whole word, so the
# selftest function name does not count), reads the python env contract, or sources the
# dark-gate lib (bare relative or ${GITHUB_WORKSPACE}-quoted spelling).
uses_shared_rule() {
  local code
  code="$(grep -vE '^[[:space:]]*#' "$1" || true)"
  grep -qE 'inngest_probe_row([^_[:alnum:]]|$)' <<<"$code" && return 0
  grep -qF 'os.environ["INNGEST_PROBE_EMITTER"]' <<<"$code" && return 0
  grep -qE '^[[:space:]]*(source|\.)[[:space:]]+"?(\$\{GITHUB_WORKSPACE\}/)?tests/scripts/lib/inngest-host-dark-gate\.sh' <<<"$code" && return 0
  return 1
}

# census <root> <file-list> -> prints one line per problem (UNCLASSIFIED <f> | STALE <f>).
census() {
  local root="$1" list="$2" f found
  found="$(discover "$root" "$list")"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -n "${ALLOW[$f]+x}" ]] && continue
    uses_shared_rule "$root/$f" || printf 'UNCLASSIFIED %s\n' "$f"
  done <<<"$found"
  for f in "${!ALLOW[@]}"; do
    grep -qxF "$f" <<<"$found" || printf 'STALE %s\n' "$f"
  done
  return 0
}

LIST="$SANDBOX/ls-files.txt"
git -C "$REPO_ROOT" ls-files > "$LIST"
FOUND="$(discover "$REPO_ROOT" "$LIST")"
n_found="$(grep -c . <<<"$FOUND" || true)"
if [[ "$n_found" -ge 12 ]] && grep -qxF "apps/web-platform/infra/inngest-bootstrap.sh" <<<"$FOUND"; then
  pass "discovery found $n_found marker-naming files, including the emitter"
else
  fail "discovery floor: found $n_found files (want >= 12, emitter included) — the discovery regex is broken"
fi

PROBLEMS="$(census "$REPO_ROOT" "$LIST")"
if [[ -z "$PROBLEMS" ]]; then
  pass "census: every marker reader uses the shared predicate or is allowlisted (0 unclassified, 0 stale)"
else
  fail "census problems:"$'\n'"$PROBLEMS"
fi

# Per-reader granularity for cutover-inngest.sh: sourcing the dark-gate lib covers the FILE, so
# every raw probe read must feed a gate call.
CUT="$REPO_ROOT/scripts/cutover-inngest.sh"
n_reads="$(grep -vE '^[[:space:]]*#' "$CUT" | grep -cE "_bs_query_rows .*${MARKER_LIT}" || true)"
n_gates="$(grep -vE '^[[:space:]]*#' "$CUT" | grep -cE 'inngest_execute_registry_gate --rows-file' || true)"
if [[ "$n_reads" -ge 1 && "$n_reads" -eq "$n_gates" ]]; then
  pass "cutover-inngest.sh: $n_reads raw probe reads == $n_gates gate calls"
else
  fail "cutover-inngest.sh: $n_reads raw probe reads vs $n_gates dark-gate calls — a raw read no gate grades"
fi

# Census mutation rows, against a fixture tree (never the git index).
mk_tree() { # -> tree root; seeds the allowlisted files plus one compliant reader
  local t f
  t="$(mktemp -d "$SANDBOX/tree.XXXXXXXX")"
  for f in "${!ALLOW[@]}"; do
    mkdir -p "$t/$(dirname "$f")"
    printf '# %s\n' "$MARKER_LIT" > "$t/$f"
  done
  mkdir -p "$t/scripts"
  printf 'jq "$INNGEST_PROBE_ROW_JQ"'"'"' select(inngest_probe_row)'"'"' # %s\n' "$MARKER_LIT" > "$t/scripts/good.sh"
  printf '%s\n' "$t"
}
tree_list() { (cd "$1" && find . -type f | sed 's|^\./||' | sort) > "$1.list"; printf '%s\n' "$1.list"; }

T="$(mk_tree)"; assert_fixture_dir "$T"; L="$(tree_list "$T")"
if [[ -z "$(census "$T" "$L")" ]]; then pass "census control: compliant fixture tree is clean"; else fail "census control tree not clean: $(census "$T" "$L")"; fi

T="$(mk_tree)"; assert_fixture_dir "$T"
printf 'bash scripts/betterstack-query.sh --grep %s | tail -1\n' "$MARKER_LIT" > "$T/scripts/zz-new-reader.sh"
L="$(tree_list "$T")"
if grep -qx 'UNCLASSIFIED scripts/zz-new-reader.sh' <<<"$(census "$T" "$L")"; then
  pass "census reds on a new raw reader added after the compliant ones"
else
  fail "census missed a new raw reader"
fi

T="$(mk_tree)"; assert_fixture_dir "$T"
printf '. scripts/lib/inngest-probe-row.sh; inngest_probe_row_selftest; jq -r .message | grep -F %s\n' "$MARKER_LIT" > "$T/scripts/selftest-only.sh"
L="$(tree_list "$T")"
if grep -qx 'UNCLASSIFIED scripts/selftest-only.sh' <<<"$(census "$T" "$L")"; then
  pass "census reds on a reader that calls only inngest_probe_row_selftest (word-boundary rule)"
else
  fail "census accepted inngest_probe_row_selftest as a use of the def"
fi

T="$(mk_tree)"; assert_fixture_dir "$T"
printf '# inngest_probe_row is mentioned only in this comment\ngrep -F %s\n' "$MARKER_LIT" > "$T/scripts/comment-only.sh"
L="$(tree_list "$T")"
if grep -qx 'UNCLASSIFIED scripts/comment-only.sh' <<<"$(census "$T" "$L")"; then
  pass "census reds on a reader whose only mention of the def is a comment"
else
  fail "census accepted a comment mention as a use of the def"
fi

T="$(mk_tree)"; assert_fixture_dir "$T"
rm -f "$T/scripts/test-all.sh"
L="$(tree_list "$T")"
if grep -qx 'STALE scripts/test-all.sh' <<<"$(census "$T" "$L")"; then
  pass "census reds on a stale allowlist entry"
else
  fail "census missed a stale allowlist entry"
fi

T="$(mk_tree)"; assert_fixture_dir "$T"
mkdir -p "$T/.github/workflows"
# shellcheck disable=SC2016
printf '          source "${GITHUB_WORKSPACE}/tests/scripts/lib/inngest-host-dark-gate.sh"\n          # %s\n' "$MARKER_LIT" > "$T/.github/workflows/apply.yml"
printf 'source tests/scripts/lib/inngest-host-dark-gate.sh || exit 1\n_bs_query_rows 24h %s 500\n' "$MARKER_LIT" > "$T/scripts/cut.sh"
L="$(tree_list "$T")"
if [[ -z "$(census "$T" "$L")" ]]; then
  pass "census accepts both dark-gate source spellings (quoted GITHUB_WORKSPACE and bare relative)"
else
  fail "census rejected a dark-gate source spelling: $(census "$T" "$L")"
fi

# ---------------------------------------------------------------------------
# Guard 1 — emitter parity
# ---------------------------------------------------------------------------

BOOT="$REPO_ROOT/apps/web-platform/infra/inngest-bootstrap.sh"
# Bind to the LOG_TAG= assignment nearest ABOVE the logger line that emits the marker (the file
# has more than one LOG_TAG).
parity="$(awk -v m="$MARKER_LIT" '
  /^[[:space:]]*(readonly[[:space:]]+)?LOG_TAG="[^"]*"/ { t=$0; sub(/^[^"]*"/,"",t); sub(/".*/,"",t); tag=t }
  index($0, "logger -t \"$LOG_TAG\" \"" m " ") { print tag " " m; found=1; exit }
  END { if (!found) print "__NO_LOGGER_LINE__" }' "$BOOT")"
if [[ "$parity" == "$INNGEST_PROBE_EMITTER $INNGEST_PROBE_MARKER" ]]; then
  pass "emitter parity: bootstrap logger line tag+marker == lib ($parity)"
else
  fail "emitter parity: bootstrap says '$parity', lib says '$INNGEST_PROBE_EMITTER $INNGEST_PROBE_MARKER'"
fi

# ---------------------------------------------------------------------------
# 3. Guard 2 — liveness-counter caller census + tag parity
# ---------------------------------------------------------------------------

fsm_tag() { # <fsm script> -> its readonly LOG_TAG value
  sed -nE 's/^[[:space:]]*readonly[[:space:]]+LOG_TAG="([^"]+)".*/\1/p' "$1" | head -1
}
FLIP_TAG="$(fsm_tag "$REPO_ROOT/apps/web-platform/infra/inngest-cutover-flip.sh")"
LUKS_TAG="$(fsm_tag "$REPO_ROOT/apps/web-platform/infra/inngest-luks-cutover.sh")"
if [[ "$FLIP_TAG" == "inngest-cutover-flip" && "$LUKS_TAG" == "inngest-luks-cutover" ]]; then
  pass "FSM LOG_TAGs read: $FLIP_TAG / $LUKS_TAG"
else
  fail "FSM LOG_TAGs drifted: flip='$FLIP_TAG' luks='$LUKS_TAG'"
fi

CALLS="$(cd "$REPO_ROOT" && git grep -n '_generation_scoped_count' -- ':!*.test.sh' ':!knowledge-base' ':!*.md' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE '_generation_scoped_count\(\)' || true)"
n_calls=0; bad_calls=""
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  n_calls=$((n_calls + 1))
  # Third argument must be a double-quoted literal FSM tag: _generation_scoped_count "$a" "b" "<tag>"
  if ! grep -qE "_generation_scoped_count[[:space:]]+\"[^\"]*\"[[:space:]]+\"[^\"]*\"[[:space:]]+\"(${FLIP_TAG}|${LUKS_TAG})\"" <<<"$line"; then
    bad_calls+="$line"$'\n'
  fi
done <<<"$CALLS"
if [[ "$n_calls" -ge 2 && -z "$bad_calls" ]]; then
  pass "every _generation_scoped_count call ($n_calls) passes a literal FSM emitter tag"
else
  fail "_generation_scoped_count calls without a literal FSM tag (n=$n_calls):"$'\n'"$bad_calls"
fi
flip_ok="$(grep -cE "_generation_scoped_count .*\"${FLIP_TAG}\"" <<<"$CALLS" || true)"
luks_ok="$(grep -cE "_generation_scoped_count .*\"${LUKS_TAG}\"" <<<"$CALLS" || true)"
if [[ "$flip_ok" -ge 1 && "$luks_ok" -ge 1 ]]; then
  pass "both FSM tags are passed by some caller (flip=$flip_ok luks=$luks_ok)"
else
  fail "an FSM tag is never passed (flip=$flip_ok luks=$luks_ok) — a counter reads the other FSM's rows"
fi
inner="$(grep -vE '^[[:space:]]*#' "$CUT" | grep -cE '_current_instance_row_counts[[:space:]]+"\$floor"[[:space:]]+"\$tag"' || true)"
if [[ "$inner" -eq 1 ]]; then
  pass "_current_instance_row_counts is called exactly once, forwarding the tag"
else
  fail "_current_instance_row_counts tag-forwarding call count is $inner (want 1)"
fi

# ---------------------------------------------------------------------------

echo "passed: $passes  failed: $fails"

MIN_ASSERTIONS=27
total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  printf 'suite ran only %s assertions, expected at least %s -- assertions are not running\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
