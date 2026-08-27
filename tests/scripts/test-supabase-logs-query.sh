#!/usr/bin/env bash
# Guard 2 harness for scripts/supabase-logs-query.sh.
#
# THE PROPERTY
# ============
# The helper never reports a row count without an inseparable coverage verdict
# naming the resolved project, and never reports zero rows for a query that
# failed, was truncated, targeted an uninstrumented source, or hit the wrong
# project. The verdict must also reach `$?`, because `if helper; then ...`,
# `set -e` and any agent reading the exit code are blind to a printed line.
#
# QUANTIFICATION
# ==============
# This suite iterates the fixture DIRECTORY, and every fixture carries its own
# _expect runs. A fixture added later is therefore covered automatically, with
# no edit here. That is load-bearing for the guard: an absent fixture would
# otherwise be an uncovered path by construction.
#
# THE SEAM
# ========
# A fake `curl` on PATH. The API host is deliberately NOT env-overridable in the
# script under test: this process holds a cloud-admin PAT and an overridable host
# is an exfil-via-redirect seam. Stubbing the BINARY gives testability at no
# production cost (same reasoning as tests/scripts/test-supabase-advisor-scan.sh).
#
# A fake that dispatches on $1 alone would put the fixture seam ABOVE the code
# under test and answer every request identically, which cannot detect the helper
# querying the WRONG thing. So this fake:
#   - resolves a per-request KEY from the SQL's alias and answers per key;
#   - exits 64 if a required curl flag is missing;
#   - exits 64 if a logs request omits either iso bound (finding G);
#   - exits 65 if the PAT appears in argv at all;
#   - exits 99 on an unrecognized URL or SQL shape, rather than falling through
#     to some other fixture's well-formed 200;
#   - exits 66 on a key the fixture does not define, so the fixture set pins the
#     CALL SEQUENCE and not merely the answers;
#   - exits 67 if the `rows` SQL is not the NESTED newest-N subquery. Flattening
#     that subquery silently changes which rows --limit selects, and a stub that
#     answers any SQL identically would replay the same fixture rows either way;
#   - exits 68 if the project ref in the URL is not the fixture's own `_ref`.
#     Without this the fake answers for ANY project, so the helper could query
#     the wrong ref -- finding F, the failure this tool exists for -- and every
#     assertion above would still pass.
#
# SUITE CONSTRAINTS -- documented repo defect classes, all load-bearing:
#   - TMPDIR defaults to /var/tmp; /tmp here is a shared 4 GiB tmpfs.
#   - NEVER `producer | grep -q PATTERN` in an assertion. Under `pipefail` an
#     early match hands the producer SIGPIPE (141), so the pipeline exits
#     non-zero even though grep MATCHED -- every NEGATIVE assertion then fails
#     OPEN. Grep a FILE directly, or use `grep -cE`.
#   - Every setup command's exit code is checked, and setup failure is exit 2 so
#     it can never be read as a test failure (or, worse, as a pass).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/supabase-logs-query.sh"
LIB="$REPO_ROOT/scripts/lib/supabase-logs-verdict.sh"
FIXDIR="$REPO_ROOT/tests/scripts/fixtures/supabase-logs"

# A non-credential literal that never authenticated anything. It is shaped like a
# PAT precisely so the "never in argv" and "never in output" assertions have
# something real to catch.
FAKE_PAT='sbp_synthetic000000000000000000000000000000'

fails=0
passes=0
pass() { printf '  ok   %s\n' "${1:-}"; passes=$((passes + 1)); }
fail() { printf '  FAIL %s\n       %s\n' "${1:-}" "${2:-}"; fails=$((fails + 1)); }
setup() { "$@" || { printf 'SETUP FAILED (exit %d): %s\n' "$?" "$*" >&2; exit 2; }; }

for f in "$SCRIPT" "$LIB"; do
  [[ -f "$f" ]] || { printf 'FATAL: %s does not exist\n' "$f" >&2; exit 2; }
done
[[ -d "$FIXDIR" ]] || { printf 'FATAL: %s does not exist\n' "$FIXDIR" >&2; exit 2; }
command -v jq >/dev/null || { printf 'FATAL: jq is required\n' >&2; exit 2; }

WORK="$(mktemp -d)" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
setup mkdir -p "$WORK/bin" "$WORK/state" "$WORK/extra"

# ---------------------------------------------------------------------------
# The fake curl.
# ---------------------------------------------------------------------------
setup tee "$WORK/bin/curl" >/dev/null <<'STUB'
#!/usr/bin/env bash
# Synthetic curl. Replays fixture envelopes; never touches the network.
set -uo pipefail

args="$*"

# The PAT must reach curl on STDIN via `--header @-`, never in argv: the shell
# expands an inline -H before exec, so an interpolated token would be readable at
# /proc/<pid>/cmdline for the life of the request.
case "$args" in
  *sbp_*) printf 'STUB: PAT PRESENT IN ARGV\n' >&2; exit 65 ;;
esac

for req in --silent --show-error --max-time --write-out --url --header; do
  case " $args " in
    *" $req "*) ;;
    *) printf 'STUB: missing required curl flag %s\n' "$req" >&2; exit 64 ;;
  esac
done

url=""; sql=""; ts_start=""; ts_end=""; is_get=0; prev=""
for a in "$@"; do
  [[ "$a" == "--get" ]] && is_get=1
  case "$prev" in
    --url) url="$a" ;;
    --data-urlencode)
      case "$a" in
        sql=*)                 sql="${a#sql=}" ;;
        iso_timestamp_start=*) ts_start="${a#iso_timestamp_start=}" ;;
        iso_timestamp_end=*)   ts_end="${a#iso_timestamp_end=}" ;;
      esac ;;
  esac
  prev="$a"
done

case "$url" in
  *"/analytics/endpoints/logs")
    (( is_get )) || { printf 'STUB: logs request without --get\n' >&2; exit 64; }
    # FINDING G. The replacement endpoint answers a bounds-less request with a
    # deterministic HTTP 200 Backend error, diverging from its own OpenAPI
    # description, so a helper that drops a bound must be caught HERE and not be
    # allowed to read the resulting failure as a dialect error.
    if [[ -z "$ts_start" || -z "$ts_end" ]]; then
      printf 'STUB: logs request missing an iso bound (start=%q end=%q)\n' "$ts_start" "$ts_end" >&2
      exit 64
    fi
    case "$sql" in
      *instrumentation_c*) key=instrumentation ;;
      *window_source_c*)   key=window ;;
      *probe_c*)           key=probe ;;
      *bisect_c*)          key=bisect ;;
      *slice_c*)           key=slice ;;
      *row_ts*)            key=rows ;;
      *) printf 'STUB: unrecognized sql shape: %s\n' "$sql" >&2; exit 99 ;;
    esac ;;
  *"/v1/projects/"*) key=identity ;;
  *) printf 'STUB: unrecognized url: %s\n' "$url" >&2; exit 99 ;;
esac

# The tail SQL must be the nested newest-N-presented-oldest-first subquery. An
# INNER `order by ... desc limit n` picks WHICH rows survive; the outer select
# only reorders them for reading. Flattened, --limit starts describing a
# different window -- and a stub keyed on the alias alone cannot tell.
if [[ "$key" == "rows" ]]; then
  case "$sql" in
    *"from (select "*"order by "*" desc limit "*) ;;
    *) printf 'STUB: rows sql is not the nested newest-N subquery: %s\n' "$sql" >&2; exit 67 ;;
  esac
fi

# The URL's project ref must be the one this fixture speaks for. Checked AFTER
# the finding-G bounds check so a bounds-less request still reports 64.
url_ref="${url#*/v1/projects/}"; url_ref="${url_ref%%/*}"
want_ref="$(jq -r '._ref // ""' "$FIXTURE" 2>/dev/null)"
if [[ -z "$want_ref" ]]; then
  printf 'STUB: fixture %s declares no _ref, so the project it answers for is unpinned\n' "$FIXTURE" >&2
  exit 68
fi
if [[ "$url_ref" != "$want_ref" ]]; then
  printf 'STUB: request targets project %s but this fixture answers for %s\n' "$url_ref" "$want_ref" >&2
  exit 68
fi

# Per-key call counter. A second call with the same key is the half-width
# re-issue; a fixture that wants a DIFFERENT answer there defines <key>_retry.
n=0
[[ -f "$STUB_STATE/$key" ]] && n="$(cat "$STUB_STATE/$key")"
n=$(( n + 1 ))
printf '%s' "$n" > "$STUB_STATE/$key"

lookup="$key"
if (( n > 1 )) && jq -e --arg k "${key}_retry" 'has($k)' "$FIXTURE" >/dev/null 2>&1; then
  lookup="${key}_retry"
fi

printf '%s\t%s\t%s\n' "$key" "$ts_start" "$ts_end" >> "$STUB_LOG"

if ! jq -e --arg k "$lookup" 'has($k)' "$FIXTURE" >/dev/null 2>&1; then
  printf 'STUB: fixture %s defines no entry for key %s\n' "$FIXTURE" "$lookup" >&2
  exit 66
fi

code="$(jq -r --arg k "$lookup" '.[$k].code' "$FIXTURE")"
body="$(jq -c --arg k "$lookup" '.[$k].body' "$FIXTURE")"
printf '%s\n%s' "$body" "$code"
STUB
setup chmod +x "$WORK/bin/curl"

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
RC=0
run_helper() {
  local fixture="$1"; shift
  setup rm -f "$WORK/calls.log"
  setup rm -rf "$WORK/state"
  setup mkdir -p "$WORK/state"
  : > "$WORK/calls.log"
  PATH="$WORK/bin:$PATH" \
    FIXTURE="$fixture" STUB_LOG="$WORK/calls.log" STUB_STATE="$WORK/state" \
    SUPABASE_ACCESS_TOKEN="$FAKE_PAT" \
    bash "$SCRIPT" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  RC=$?
}

# grep a FILE, never a pipeline (see the pipefail note in the header).
has() { grep -qF -- "$2" "$1"; }

check_fixture_run() {
  local fx="$1" run="$2" label="$3"
  local want_exit want_verdict want_reason want_lines
  want_exit="$(jq -r '.exit' <<<"$run")"
  want_verdict="$(jq -r '.verdict' <<<"$run")"
  want_reason="$(jq -r '.reason' <<<"$run")"
  want_lines="$(jq -r '.stdout_lines // 0' <<<"$run")"

  local argv=()
  readarray -t argv < <(jq -r '.argv[]' <<<"$run")
  (( ${#argv[@]} > 0 )) || { fail "$label" "fixture run has no argv"; return; }

  run_helper "$fx" "${argv[@]}"

  # --- the verdict must reach $?
  if [[ "$RC" != "$want_exit" ]]; then
    fail "$label exit code" "want $want_exit got $RC; stderr tail: $(tail -3 "$WORK/stderr" | tr '\n' ' ')"
    return
  fi

  # --- the block must exist, be contiguous, and carry the count INSIDE it
  awk '/EVIDENCE BLOCK/,/end evidence block/' "$WORK/stderr" > "$WORK/block"
  if ! has "$WORK/block" "EVIDENCE BLOCK"; then
    fail "$label evidence block" "no block emitted at all; stderr: $(tail -3 "$WORK/stderr" | tr '\n' ' ')"
    return
  fi
  local missing=""
  local k
  for k in "verdict=" "reason=" "ref=" "project=" "rows=" "covered_window=" "next_action="; do
    has "$WORK/block" "$k" || missing="${missing}${missing:+ }${k}"
  done
  [[ -z "$missing" ]] || { fail "$label block fields" "missing from the block: $missing"; return; }

  # Ordering: the verdict is emitted BEFORE the count, inside the same block. A
  # verdict merely PRESENT in the file could have been emitted after an
  # empty-result early return, i.e. outside the window where a zero is rendered.
  local ln_v ln_r
  ln_v="$(grep -n '^verdict=' "$WORK/block" | head -1 | cut -d: -f1)"
  ln_r="$(grep -n '^rows=' "$WORK/block" | head -1 | cut -d: -f1)"
  if [[ -z "$ln_v" || -z "$ln_r" ]] || (( ln_v >= ln_r )); then
    fail "$label verdict precedes count" "verdict line=$ln_v rows line=$ln_r"
    return
  fi

  # A row count must NEVER be a bare number for a query that failed.
  if [[ "$want_verdict" == "INCONCLUSIVE" && "$want_exit" != "3" ]]; then
    if grep -qE '^rows=[0-9]+$' "$WORK/block"; then
      fail "$label no count for a failed query" "a failed query rendered a numeric rows= line"
      return
    fi
  fi

  has "$WORK/block" "verdict=$want_verdict" || { fail "$label verdict" "want verdict=$want_verdict; got: $(grep '^verdict=' "$WORK/block")"; return; }
  has "$WORK/block" "reason=$want_reason"   || { fail "$label reason"  "want reason=$want_reason; got: $(grep '^reason=' "$WORK/block")"; return; }

  # Finding F: identity on EVERY path, success and failure.
  if grep -qE '^(ref|project)=\s*$' "$WORK/block" || has "$WORK/block" "project=(unknown)"; then
    fail "$label project identity" "ref/project missing from the block"
    return
  fi

  local req
  while IFS= read -r req; do
    [[ -z "$req" ]] && continue
    has "$WORK/stderr" "$req" || { fail "$label requires" "expected in output: $req"; return; }
  done < <(jq -r '.require[]? // empty' <<<"$run")

  # The PAT must never survive into any output stream.
  if grep -qF -- "$FAKE_PAT" "$WORK/stderr" "$WORK/stdout"; then
    fail "$label PAT scrub" "the token reached the output unredacted"
    return
  fi

  # --- stdout is the pipeable payload; the block belongs on stderr
  if has "$WORK/stdout" "EVIDENCE BLOCK"; then
    fail "$label stdout purity" "the human block leaked onto stdout, which is meant to stay pipeable"
    return
  fi
  local got_lines
  got_lines="$(grep -c '' "$WORK/stdout")"
  if [[ "$got_lines" != "$want_lines" ]]; then
    fail "$label stdout lines" "want $want_lines got $got_lines"
    return
  fi
  if [[ "$(jq -r '.stdout_ascending // false' <<<"$run")" == "true" ]]; then
    local ts sorted
    # Only the JSON row lines. Human mode also prints a trailing
    # `verdict=... reason=...` line on stdout (so a redirect cannot yield an
    # empty file), which is not JSON and would abort jq mid-stream.
    ts="$(grep -E '^\{' "$WORK/stdout" | jq -r '.row_ts' 2>/dev/null)"
    sorted="$(printf '%s\n' "$ts" | sort)"
    if [[ "$ts" != "$sorted" ]]; then
      fail "$label tail ordering" "rows are not oldest-first; the nested newest-N subquery is what produces that"
      return
    fi
  fi

  # --- the call sequence: a helper querying the WRONG thing is detectable
  local want_calls got_calls
  want_calls="$(jq -r '.calls[]? // empty' <<<"$run" | tr '\n' ' ')"
  got_calls="$(cut -f1 "$WORK/calls.log" | tr '\n' ' ')"
  if [[ -n "$want_calls" && "$want_calls" != "$got_calls" ]]; then
    fail "$label call sequence" "want [$want_calls] got [$got_calls]"
    return
  fi

  # --- the machine path carries the verdict too
  run_helper "$fx" "${argv[@]}" --json
  if [[ "$RC" != "$want_exit" ]]; then
    fail "$label --json exit code" "want $want_exit got $RC"
    return
  fi
  if [[ "$(grep -c '' "$WORK/stdout")" != "1" ]]; then
    fail "$label --json shape" "expected exactly one line of JSON"
    return
  fi
  if [[ "$(jq -r 'type' "$WORK/stdout" 2>/dev/null)" != "object" ]]; then
    fail "$label --json object" "--json must emit ONE OBJECT, never a bare array: $(head -c 120 "$WORK/stdout")"
    return
  fi
  local jmissing
  jmissing="$(jq -r '["verdict","coverage","ref","project","sources","rows"] - (. | keys) | join(" ")' "$WORK/stdout")"
  [[ -z "$jmissing" ]] || { fail "$label --json keys" "missing: $jmissing"; return; }
  if [[ "$(jq -r '.verdict' "$WORK/stdout")" != "$want_verdict" ]]; then
    fail "$label --json verdict" "want $want_verdict got $(jq -r '.verdict' "$WORK/stdout")"
    return
  fi
  if [[ "$(jq -r '.exit_code' "$WORK/stdout")" != "$want_exit" ]]; then
    fail "$label --json exit_code" "the object must carry the same code the process exits with"
    return
  fi
  if [[ "$want_verdict" != "COVERED" && "$(jq -r '.next_action | length' "$WORK/stdout")" == "0" ]]; then
    fail "$label --json next action" "every failure mode must name the agent's next action"
    return
  fi
  # A failed query is rows: null on the machine path too -- never 0.
  if [[ "$want_exit" == "1" || "$want_exit" == "2" ]]; then
    if [[ "$(jq -r '.rows' "$WORK/stdout")" != "null" ]]; then
      fail "$label --json rows null" "a failed query must be rows:null, not a number"
      return
    fi
  fi
  pass "$label"
}

# Sets SWEPT. Deliberately NOT `SWEPT=$(sweep_dir ...)`: command substitution
# runs the body in a SUBSHELL, so every `fails` increment inside it would be
# discarded and the suite would report green no matter how many fixtures failed.
SWEPT=0
sweep_dir() {
  local dir="$1" seen=0 fx name n i run
  for fx in "$dir"/*.json; do
    [[ -e "$fx" ]] || continue
    seen=$((seen + 1))
    name="$(basename "$fx" .json)"
    if ! jq -e 'has("_expect") and (._expect | type == "array")' "$fx" >/dev/null 2>&1; then
      fail "$name" "fixture has no _expect array; the suite quantifies over this directory, so an unannotated fixture is an untested path"
      continue
    fi
    if ! jq -e 'has("_synthesized")' "$fx" >/dev/null 2>&1; then
      fail "$name" "fixture is missing the _synthesized provenance note"
      continue
    fi
    n="$(jq -r '._expect | length' "$fx")"
    for (( i = 0; i < n; i++ )); do
      run="$(jq -c "._expect[$i]" "$fx")"
      check_fixture_run "$fx" "$run" "${name}[$i]"
    done
  done
  SWEPT="$seen"
}

echo "== Fixture sweep (quantified over the directory) =="
sweep_dir "$FIXDIR"
# The floor is the CURRENT population, not a round number: a floor left trailing
# what it guards lets the newest fixture be deleted unnoticed. `<`, never `!=`,
# so ADDING a fixture stays free.
if (( SWEPT < 11 )); then
  fail "fixture count" "expected at least 11 fixtures, found $SWEPT — the missing ones are uncovered paths"
else
  pass "swept $SWEPT fixtures"
fi

# ---------------------------------------------------------------------------
# Guard-2 matrix rows 11 and 12: must-PASS controls, synthesized here rather
# than committed, so they also PROVE the directory quantification works -- a
# fixture dropped in later is exercised with no edit to this file.
# ---------------------------------------------------------------------------
echo "== Must-PASS controls (matrix rows 11 and 12) =="

# Row 11: a well-formed but NON-CANONICAL success. Different source ordering, a
# source the documented list does not carry, extra envelope fields, whole-second
# timestamps. The contract permits all of it; a guard that reddens here rejects
# valid input and would be worked around rather than fixed.
setup tee "$WORK/extra/row11-noncanonical-success.json" >/dev/null <<'FX11'
{
  "_scenario": "row11-noncanonical-success",
  "_synthesized": "Synthesized. Matrix row 11: the must-PASS non-canonical control.",
  "_ref": "pigsfuxruiopinouvjwy",
  "_expect": [
    { "argv": ["--ref", "pigsfuxruiopinouvjwy", "--source", "postgres_logs",
               "--since", "2026-08-25T00:00:00",
               "--until", "2026-08-26T00:00:00", "--limit", "2"],
      "exit": 0, "verdict": "COVERED", "reason": "FULLY_COVERED",
      "require": ["rows=77"],
      "calls": ["identity", "instrumentation", "window", "rows"],
      "stdout_lines": 3, "stdout_ascending": true }
  ],
  "identity": { "code": 200,
    "body": { "id": "pigsfuxruiopinouvjwy", "name": "soleur-synthetic-prd",
              "organization_id": "synthetic-org", "database": { "version": "17.4" } } },
  "instrumentation": { "code": 200, "body": { "result": [
    { "source": "postgres_logs", "instrumentation_c": 88 },
    { "source": "multigres_logs", "instrumentation_c": 4 },
    { "source": "supavisor_logs", "instrumentation_c": 12 } ], "error": null } },
  "window": { "code": 200, "body": { "result": [
    { "source": "postgres_logs", "window_source_c": 77,
      "window_lo": "2026-08-25T00:00:00", "window_hi": "2026-08-26T00:00:00" } ], "error": null } },
  "rows": { "code": 200, "body": { "result": [
    { "row_ts": "2026-08-25T03:00:00", "id": "aaaa", "event_message": "synthetic line one" },
    { "row_ts": "2026-08-25T19:00:00", "id": "bbbb", "event_message": "synthetic line two" } ], "error": null } }
}
FX11

# Row 12: the monotonicity FALSE-POSITIVE control. A 12-day window, old but
# legitimately narrow in content, whose last-7d sub-window naturally holds FEWER
# rows than the whole window. The probe FIRES and must NOT trip. A check written
# with the comparison inverted reddens here -- and would make the tool unusable
# for exactly the 12-day journey that motivated it, while shipping green.
setup tee "$WORK/extra/row12-narrow-but-old.json" >/dev/null <<'FX12'
{
  "_scenario": "row12-narrow-but-old",
  "_synthesized": "Synthesized. Matrix row 12: the monotonicity false-POSITIVE control.",
  "_ref": "pigsfuxruiopinouvjwy",
  "_expect": [
    { "argv": ["--ref", "pigsfuxruiopinouvjwy", "--source", "postgres_logs",
               "--since", "2026-07-01T00:00:00",
               "--until", "2026-07-13T00:00:00", "--limit", "1"],
      "exit": 0, "verdict": "COVERED", "reason": "FULLY_COVERED",
      "require": ["rows=900", "probe fired and PASSED", "window=900 >= last-7d sub-window=120"],
      "calls": ["identity", "instrumentation", "window", "probe", "rows"],
      "stdout_lines": 2 }
  ],
  "identity": { "code": 200,
    "body": { "id": "pigsfuxruiopinouvjwy", "name": "soleur-synthetic-prd" } },
  "instrumentation": { "code": 200, "body": { "result": [
    { "source": "postgres_logs", "instrumentation_c": 2044 } ], "error": null } },
  "window": { "code": 200, "body": { "result": [
    { "source": "postgres_logs", "window_source_c": 900,
      "window_lo": "2026-07-01T00:04:00.000000", "window_hi": "2026-07-12T23:52:00.000000" } ],
    "error": null } },
  "probe": { "code": 200, "body": { "result": [ { "probe_c": 120 } ], "error": null } },
  "rows": { "code": 200, "body": { "result": [
    { "row_ts": "2026-07-12T23:52:00.000000", "id": "cccc", "event_message": "synthetic tail line" } ],
    "error": null } }
}
FX12

sweep_dir "$WORK/extra"
if (( SWEPT != 2 )); then
  fail "directory quantification" "expected the 2 synthesized controls to be picked up automatically, saw $SWEPT"
else
  pass "the directory sweep picked up 2 fixtures it was never told about"
fi

# ---------------------------------------------------------------------------
# The seam's own guards. Without these the fake could be silently permissive and
# every assertion above would be weaker than it looks.
# ---------------------------------------------------------------------------
echo "== Seam self-checks =="

# ONE literal for the logs URL, reused by every self-check below. Kept as a
# single occurrence deliberately: this file is inside the deprecation-assembly
# guard's census (a host token immediately followed by /v1/projects/), so a
# second inline copy would silently move that highwater number.
STUB_LOGS_URL='https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/analytics/endpoints/logs'
STUB_ID_URL="${STUB_LOGS_URL%/analytics/endpoints/logs}"

STUB_STATE="$WORK/state" STUB_LOG="$WORK/calls.log" FIXTURE="$FIXDIR/success.json" \
  "$WORK/bin/curl" --silent --show-error --max-time 60 --get --header @- \
  --data-urlencode 'sql=select source, count(*) as window_source_c from logs group by source' \
  --write-out x --url "$STUB_LOGS_URL" \
  >/dev/null 2>&1 </dev/null
if [[ "$?" -eq 64 ]]; then
  pass "the fake REJECTS a logs request with no iso bounds (finding G is mechanically pinned)"
else
  fail "finding G seam" "the fake accepted a bounds-less request, so a helper that drops a bound would pass"
fi

STUB_STATE="$WORK/state" STUB_LOG="$WORK/calls.log" FIXTURE="$FIXDIR/success.json" \
  "$WORK/bin/curl" --silent --show-error --max-time 60 --get \
  --header "Authorization: Bearer $FAKE_PAT" \
  --data-urlencode 'sql=x' --write-out x --url 'https://api.supabase.com/x' \
  >/dev/null 2>&1 </dev/null
if [[ "$?" -eq 65 ]]; then
  pass "the fake REJECTS a PAT passed in argv (the /proc/<pid>/cmdline exposure)"
else
  fail "argv PAT seam" "the fake accepted an argv-borne PAT"
fi

# The fake must discriminate on the SQL SHAPE, not just the alias. A flattened
# tail query keeps `row_ts` and would otherwise be answered with the same fixture
# rows, so flattening build_rows_sql -- which changes WHICH rows --limit keeps --
# would ship green.
STUB_STATE="$WORK/state" STUB_LOG="$WORK/calls.log" FIXTURE="$FIXDIR/success.json" \
  "$WORK/bin/curl" --silent --show-error --max-time 60 --get --header @- \
  --data-urlencode 'sql=select timestamp as row_ts, id, event_message from logs order by row_ts desc limit 5' \
  --data-urlencode 'iso_timestamp_start=2026-08-25T00:00:00' \
  --data-urlencode 'iso_timestamp_end=2026-08-26T00:00:00' \
  --write-out x --url "$STUB_LOGS_URL" \
  >/dev/null 2>&1 </dev/null
if [[ "$?" -eq 67 ]]; then
  pass "the fake REJECTS a FLATTENED tail query (the nested newest-N subquery is pinned, not just its alias)"
else
  fail "nested-subquery seam" "the fake answered a flattened rows query, so build_rows_sql could be flattened undetected"
fi

# ...and on the PROJECT REF. Without this the fake answers for any project, so
# finding F -- a format-valid ref pointed at the wrong project -- is invisible to
# every assertion in this file.
STUB_STATE="$WORK/state" STUB_LOG="$WORK/calls.log" FIXTURE="$FIXDIR/success.json" \
  "$WORK/bin/curl" --silent --show-error --max-time 30 --header @- \
  --write-out x --url "${STUB_ID_URL%/*}/aaaaaaaaaaaaaaaaaaaa" \
  >/dev/null 2>&1 </dev/null
if [[ "$?" -eq 68 ]]; then
  pass "the fake REJECTS a request for a project the fixture does not speak for (finding F is mechanically pinned)"
else
  fail "wrong-project seam" "the fake answered for a ref other than the fixture's _ref, so a wrong-project query would pass"
fi

# ---------------------------------------------------------------------------
# Argument-handling paths that never reach the API, and so never reach a
# fixture: they exit before the first curl call.
# ---------------------------------------------------------------------------
echo "== Pre-flight argument handling =="

# --ref has NO DEFAULT. It used to default to the Inngest BACKING project, so a
# DSAR ("what data do you hold on me") invoked with no --ref queried a project
# that never held the data and answered rows=0 / COVERED.
run_helper "$FIXDIR/success.json" --source postgres_logs --since 24h
if [[ "$RC" -eq 2 ]] && has "$WORK/stderr" "--ref is REQUIRED" \
   && has "$WORK/stderr" "ifsccnjhymdmidffkzhl" && has "$WORK/stderr" "pigsfuxruiopinouvjwy"; then
  pass "a missing --ref is a CONFIG_ERROR naming both known project refs, not a silent default"
else
  fail "required --ref" "want exit 2 naming both refs, got exit $RC: $(tail -2 "$WORK/stderr" | tr '\n' ' ')"
fi
if [[ "$(grep -c '' "$WORK/calls.log")" == "0" ]]; then
  pass "a missing --ref issues NO request at all (nothing is asked of an unnamed project)"
else
  fail "required --ref call count" "the helper called the API before knowing which project it meant"
fi

# --limit needs a CEILING, not just an integer check. The bounded limit is this
# helper's only real data-minimisation control (stdout lands in an agent
# transcript), so `--limit 500000` would defeat it while passing ^[0-9]+$.
run_helper "$FIXDIR/success.json" --ref pigsfuxruiopinouvjwy --source postgres_logs --limit 500000
if [[ "$RC" -eq 2 ]] && has "$WORK/stderr" "exceeds the 1000-line ceiling"; then
  pass "--limit is bounded above, so the data-minimisation claim is a bound and not a hope"
else
  fail "limit ceiling" "want exit 2 rejecting an oversized --limit, got exit $RC"
fi

# The unknown-flag path is the one print site that predates emit_and_exit, so it
# is the one that can bypass scrub_pat. A mistyped
# `doppler run -- script "$SUPABASE_ACCESS_TOKEN"` lands a live cloud-admin PAT
# in argv, and this used to echo it back verbatim.
run_helper "$FIXDIR/success.json" "$FAKE_PAT"
if [[ "$RC" -eq 64 ]]; then
  pass "an unknown flag is a usage error (exit 64)"
else
  fail "unknown flag exit" "want exit 64 got $RC"
fi
if grep -qF -- "$FAKE_PAT" "$WORK/stderr" "$WORK/stdout"; then
  fail "unknown flag PAT scrub" "the argv word was echoed back UNREDACTED; a PAT mistyped as a flag leaks to the transcript"
else
  pass "an unknown flag is echoed back SCRUBBED (a PAT in argv cannot survive the usage error)"
fi

# ---------------------------------------------------------------------------
# Write-boundary sweep. The only mechanical check on the data-minimisation
# claim: the helper holds GDPR-relevant log lines, so it must not persist them.
# ---------------------------------------------------------------------------
echo "== Write-boundary sweep =="
# Blank out comments and `2>/dev/null`-style discards before scanning, keeping
# the line count (and so the line numbers) intact. Without this the sweep trips
# on its own documentation and on stderr discards, and a noisy check that is
# always red gets deleted rather than obeyed. It can in principle hide a write
# site written after a `#` inside a string literal; neither file contains one,
# and the alternative is a check nobody keeps.
strip_noise() { sed -e 's/#.*//' -e 's|[0-9]*>[[:space:]]*/dev/null||g' "$1"; }
WRITE_RE='(\btee\b|\$GITHUB_OUTPUT|upload-artifact|\bmktemp\b|>>?[[:space:]]*["'"'"']?[/$~]|>[[:space:]]*[A-Za-z_.][A-Za-z0-9_./-]*\.(json|txt|log|csv|out))'
: > "$WORK/writes"
for f in "$SCRIPT" "$LIB"; do
  strip_noise "$f" | grep -nE "$WRITE_RE" | sed "s|^|$(basename "$f"):|" >> "$WORK/writes"
done
if [[ "$(grep -c '' "$WORK/writes")" == "0" ]]; then
  pass "no write site in the helper or its lib (no tee, no redirect to a path, no artifact)"
else
  fail "write boundary" "candidate write site(s): $(head -5 "$WORK/writes" | tr '\n' ' ')"
fi

# Non-vacuity for the sweep above. A regex that matches nothing would report a
# clean write boundary forever, which is strictly worse than no check because it
# retires the attention currently substituting for it.
setup tee "$WORK/writeprobe" >/dev/null <<'PROBE'
printf 'x' | tee "$GITHUB_OUTPUT"
printf 'y' > /var/tmp/leaked-rows.json
PROBE
if [[ "$(strip_noise "$WORK/writeprobe" | grep -cE "$WRITE_RE")" == "2" ]]; then
  pass "the write-boundary regex DOES match known write sites (the sweep is not vacuous)"
else
  fail "write sweep non-vacuity" "the regex failed to match a tee and a redirect-to-file; the clean result above means nothing"
fi

# ---------------------------------------------------------------------------
# NO fail_now REACHABLE FROM INSIDE A COMMAND SUBSTITUTION.
#
# fail_now -> emit_and_exit is the helper's sole exit path, and `exit` inside
# `x="$(f ...)"` kills only the SUBSHELL. The caller then carries on with x="" --
# and in --json mode with the EVIDENCE OBJECT captured into x and parsed as an
# HTTP body. api_logs held exactly that shape: it asserted finding G's both-bounds
# rule, and every call site was `raw="$(api_logs ...)"`, so the assertion could
# never terminate anything.
#
# Structural, and quantified over the file rather than naming api_logs: any
# function whose output is CAPTURED anywhere must not contain fail_now. A guard
# spelled as "api_logs specifically" would be silent the next time the shape
# reappears in a different function, which is how it got here the first time.
# ---------------------------------------------------------------------------
echo "== fail_now is never swallowed by a subshell =="

# Sets SUBSHELL_FAILNOW to the offending function names (empty when clean).
scan_substituted_fail_now() {
  local src="$1" fn
  SUBSHELL_FAILNOW=""
  while IFS= read -r fn; do
    [[ -n "$fn" ]] || continue
    grep -qE "^${fn}\(\) \{" "$src" || continue
    # A one-line definition (`f() { ...; }`) closes on its own line; a multi-line
    # one closes on a bare `}`. Conflating them would run the extraction past the
    # end of a one-liner and attribute the NEXT function's body to it.
    awk -v f="$fn" '
      !inf && $0 ~ "^"f"\\(\\) \\{" {
        print; inf = 1
        if ($0 ~ /\}[[:space:]]*$/) exit
        next
      }
      inf { print }
      inf && /^\}$/ { exit }
    ' "$src" > "$WORK/fnbody"
    [[ "$(grep -cF 'fail_now' "$WORK/fnbody")" == "0" ]] ||
      SUBSHELL_FAILNOW="${SUBSHELL_FAILNOW}${SUBSHELL_FAILNOW:+ }${fn}"
  done < <(grep -oE '\$\([a-z_][a-z0-9_]*' "$src" | sed 's/^\$(//' | sort -u)
}

scan_substituted_fail_now "$SCRIPT"
if [[ -z "$SUBSHELL_FAILNOW" ]]; then
  pass "no command-substituted function calls fail_now (its exit would die with the subshell)"
else
  fail "fail_now in a subshell" "these functions are captured with \$( ) yet call fail_now, so their exit is discarded and the caller continues with an empty/garbage value: $SUBSHELL_FAILNOW"
fi

# Non-vacuity. A scanner that matches nothing would certify this property forever.
setup tee "$WORK/subprobe.sh" >/dev/null <<'SUBPROBE'
api_logs() {
  local a="$1"
  fail_now CONFIG_ERROR "this exit dies with the subshell"
  printf '%s' "$a"
}
clean_helper() {
  printf 'no exit here'
}
raw="$(api_logs x)"
name="$(clean_helper)"
SUBPROBE
scan_substituted_fail_now "$WORK/subprobe.sh"
if [[ "$SUBSHELL_FAILNOW" == "api_logs" ]]; then
  pass "the scanner DOES catch a captured function that calls fail_now, and does NOT flag the clean one"
else
  fail "subshell scan non-vacuity" "expected exactly 'api_logs', got '$SUBSHELL_FAILNOW'; the clean result above means nothing"
fi

# ---------------------------------------------------------------------------
# Host pin and default ref: both are members of a sibling guard's assembly.
# ---------------------------------------------------------------------------
echo "== Pinned constants =="
if [[ "$(grep -cE '^API="https://api\.supabase\.com" #' "$SCRIPT")" == "1" ]]; then
  pass "the API host is a bare pinned literal with no env override"
else
  fail "host pin" "expected exactly one bare API= literal; an interpolated host is a PAT-exfil-via-redirect seam"
fi
# Comments are stripped first: the header legitimately NAMES the deprecated path
# to say it is being replaced, and a check that cannot tell a citation from a
# call would forbid documenting the migration at all.
if [[ "$(strip_noise "$SCRIPT" | grep -cE 'analytics/endpoints/logs\.all')" == "0" ]]; then
  pass "the helper CALLS the replacement endpoint, never the deprecated logs.all"
else
  fail "deprecated endpoint" "a non-comment line still references analytics/endpoints/logs.all"
fi

# ---------------------------------------------------------------------------
# HARNESS SELF-CHECK.
#
# Every assertion above dispatches through fail(), and the final `fails -gt 0`
# gate reads a counter fail() maintains. `fail() { :; }` therefore turns this
# whole file into "all checks passed", exit 0 -- including the fixture-count
# floor, which is disarmed by the very edit it exists to catch because it too
# calls fail(). Prove the reporters still move their own counters, then subtract
# the probes. Dispatched by a BARE echo+exit, never through fail(), or the check
# would be neutered by the same edit.
# ---------------------------------------------------------------------------
_p0=$passes; _f0=$fails
pass "__self-check (expected; not a real check)"
fail "__self-check (expected; not a real failure)" "harness self-check probe"
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  echo "FAIL: pass()/fail() are not discriminating (+$((passes - _p0))/+$((fails - _f0)); expected +1/+1). A neutered reporter reports every assertion above as green." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo ""
printf 'supabase-logs-query: %d passed, %d failed\n' "$passes" "$fails"

# MINIMUM CARDINALITY. Neutering the reporters yields "0 passed, 0 failed" and a
# clean exit, and a runner reads only the exit code. Set to the FULL count of a
# green run, not a slack value: a floor trailing its population lets the newest
# assertion be deleted unnoticed. `-lt` (a floor, never `-eq`) so ADDING
# assertions stays free; only deletion reds.
MIN_ASSERTIONS=31
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((passes + fails)) assertions ran, expected >= ${MIN_ASSERTIONS}. An empty fixture directory or a short-circuited sweep must not exit 0 with zero coverage." >&2
  exit 1
fi

if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
