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
#     CALL SEQUENCE and not merely the answers.
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
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
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
    ts="$(jq -r '.row_ts' "$WORK/stdout" 2>/dev/null)"
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
if (( SWEPT < 9 )); then
  fail "fixture count" "expected at least 9 fixtures, found $SWEPT — the missing ones are uncovered paths"
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
  "_expect": [
    { "argv": ["--source", "postgres_logs", "--since", "2026-08-25T00:00:00",
               "--until", "2026-08-26T00:00:00", "--limit", "2"],
      "exit": 0, "verdict": "COVERED", "reason": "FULLY_COVERED",
      "require": ["rows=77"],
      "calls": ["identity", "instrumentation", "window", "rows"],
      "stdout_lines": 2, "stdout_ascending": true }
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
  "_expect": [
    { "argv": ["--source", "postgres_logs", "--since", "2026-07-01T00:00:00",
               "--until", "2026-07-13T00:00:00", "--limit", "1"],
      "exit": 0, "verdict": "COVERED", "reason": "FULLY_COVERED",
      "require": ["rows=900", "probe fired and PASSED", "window=900 >= last-7d sub-window=120"],
      "calls": ["identity", "instrumentation", "window", "probe", "rows"],
      "stdout_lines": 1 }
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

STUB_STATE="$WORK/state" STUB_LOG="$WORK/calls.log" FIXTURE="$FIXDIR/success.json" \
  "$WORK/bin/curl" --silent --show-error --max-time 60 --get --header @- \
  --data-urlencode 'sql=select source, count(*) as window_source_c from logs group by source' \
  --write-out x --url 'https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/analytics/endpoints/logs' \
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

echo ""
if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
