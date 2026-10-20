#!/usr/bin/env bash
# Fixture tests for the #8743 web-2 plugin-seed follow-through probe. A stub
# query helper answers the probe's two reads — the aggregate scan (control +
# marker counts + first_marker_dt) and the post-marker fchmodat2 count — from
# env-set fixture bodies, so every exit arm is driven by exactly one field.
#
# The property under test: PASS (exit 0) is reachable ONLY through the
# conjunction — positive control alive AND a post-fix marker AND zero
# fchmodat2 rows at/after that marker. A dark channel, an unexercised host, a
# transient query failure, or a missing clock must never produce 0.
#
# All data synthesized (cq-test-fixtures-synthesized-only): fabricated counts
# and timestamps only.
set -uo pipefail

WORK=$(mktemp -d -t ft8743root.XXXXXXXX) || { echo "FATAL: could not create scratch root" >&2; exit 1; }
[[ "$WORK" == /* && -d "$WORK" && ! -L "$WORK" ]] || { echo "FATAL: bad scratch root: $WORK" >&2; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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
assert_fixture_dir "$WORK"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/web2-plugin-seed-8743.sh"
[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

EARLIEST="2026-10-19T00:00:00Z"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/bsq" <<'STUB'
#!/usr/bin/env bash
# Stub for betterstack-query.sh: answers by query shape. The scan query carries
# the first_marker_dt aggregate; the post-marker count query does not. Each
# invocation logs an INVOCATION sentinel — the SQL itself is multi-line, so a
# line count would count SQL lines, not calls.
printf 'INVOCATION\n%s\n' "$*" >> "${STUB_CALLS:?}"
case "$*" in
  *first_marker_dt*) printf '%s\n' "${STUB_SCAN_OUT:-}"; exit "${STUB_SCAN_RC:-0}" ;;
  *) printf '%s\n' "${STUB_COUNT_OUT:-}"; exit "${STUB_COUNT_RC:-0}" ;;
esac
STUB
chmod +x "$WORK/bin/bsq"

passes=0
FAILURES=()
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; FAILURES+=("$1"); }

# Fixture builders — the two JSONEachRow bodies the probe decodes.
scan_row() { # control_rows probe_rows deploy_ok_rows fchmod_total first_marker_dt machine_ids
  printf '{"control_rows":"%s","probe_rows":"%s","deploy_ok_rows":"%s","fchmod_rows_total":"%s","first_marker_dt":"%s","machine_ids":"%s"}' "$@"
}
count_row() { printf '{"n":"%s"}' "$1"; }

# run_case <label> <want-rc> <scan-rc> <scan-out> <count-rc> <count-out> [extra env...]
run_case() {
  local label="$1" want="$2" scan_rc="$3" scan_out="$4" count_rc="$5" count_out="$6"; shift 6
  assert_fixture_dir "$WORK/calls-$passes-${#FAILURES[@]}.log"
  : > "$WORK/calls-$passes-${#FAILURES[@]}.log"
  local got
  env -i PATH="$PATH" HOME="$WORK" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    SOLEUR_FT_EARLIEST="$EARLIEST" FT8743_QUERY_SH="$WORK/bin/bsq" \
    STUB_CALLS="$WORK/calls-$passes-${#FAILURES[@]}.log" \
    STUB_SCAN_RC="$scan_rc" STUB_SCAN_OUT="$scan_out" \
    STUB_COUNT_RC="$count_rc" STUB_COUNT_OUT="$count_out" \
    "$@" bash "$PROBE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$label (rc=$got)"; else fail "$label: want rc=$want, got rc=$got"; fi
}

echo "web2-plugin-seed-8743 probe:"

# 0. Artifact hygiene — a non-executable probe is skipped silently by the sweeper.
if [ -x "$PROBE" ]; then pass "probe is executable"; else fail "probe is not executable ($PROBE)"; fi

# 1. The PASS conjunction: control alive, post-fix marker present, zero
#    fchmodat2 at/after it — INCLUDING pre-marker fchmodat2 rows in-window
#    (fchmod_rows_total=4 are history, not a verdict).
run_case "post-fix deploy with zero post-marker fchmodat2 is PASS" 0 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)"

# 2. fchmodat2 at/after the first post-fix marker = the abort path is still
#    live after the fix — the one genuine FAIL.
run_case "fchmodat2 after the first post-fix marker is FAIL" 1 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 2)"

# 3. Channel alive but no post-fix marker: the fix has not exercised web-2 —
#    in-window fchmodat2 rows are pre-delivery history, so NOT YET not FAIL.
run_case "marker absent (fix not exercised) is NOT YET" 2 0 \
  "$(scan_row 9 0 0 8 "1970-01-01 00:00:00" 1)" 0 "$(count_row 0)"

# 4. Zero control rows = dark channel: unmeasurable, never a clean zero.
run_case "dark channel (0 control rows) is CANNOT ESTABLISH" 3 0 \
  "$(scan_row 0 0 0 8 "1970-01-01 00:00:00" 0)" 0 "$(count_row 0)"

# 5. A marker is a marker whichever literal produced it — the
#    Deploy-succeeded-class arm alone (no PLUGIN_SEED_PROBE) still anchors the
#    absence window.
run_case "marker via Deploy-succeeded-class only still passes" 0 0 \
  "$(scan_row 9 0 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)"

# 6-9. Transport arms.
run_case "scan query rc=3 (nothing was queried) is CANNOT ESTABLISH" 3 3 "" 0 "$(count_row 0)"
run_case "scan query transient error is NOT YET"                          2 1 "" 0 "$(count_row 0)"
run_case "scan result carrying a ClickHouse exception is NOT YET"         2 0 "Code: 62. DB::Exception: Syntax error" 0 "$(count_row 0)"
run_case "unparseable scan fields are NOT YET"                            2 0 "$(scan_row x 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)"

# 10-11. Absence-arm transport faults.
run_case "absence query transient error is NOT YET"    2 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 1 ""
run_case "unparseable absence count is NOT YET"        2 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "not json"

# 12. A marker with an undecodable first_marker_dt must never floor the absence
#     window at the epoch (that would re-grade history as post-fix).
run_case "marker with undecodable first_marker_dt is NOT YET" 2 0 \
  "$(scan_row 9 2 1 4 "not-a-date" 1)" 0 "$(count_row 0)"

# 13-15. Clock arms.
run_case "unset SOLEUR_FT_EARLIEST is CANNOT ESTABLISH"     3 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)" SOLEUR_FT_EARLIEST=
run_case "malformed earliest is CANNOT ESTABLISH"           3 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)" SOLEUR_FT_EARLIEST=not-a-date
run_case "earliest in the future is NOT YET"                2 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)" SOLEUR_FT_EARLIEST=2099-01-01T00:00:00Z

# 16. Missing credential is CANNOT ESTABLISH.
run_case "missing credential is CANNOT ESTABLISH" 3 0 \
  "$(scan_row 9 2 1 4 "2026-10-19 05:12:33" 1)" 0 "$(count_row 0)" BETTERSTACK_QUERY_PASSWORD=

# 17. The absence query is issued ONLY when a marker exists — a probe that
#     graded the raw window would FAIL case 3's pre-delivery rows.
: > "$WORK/calls-marker.log"
env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  SOLEUR_FT_EARLIEST="$EARLIEST" FT8743_QUERY_SH="$WORK/bin/bsq" \
  STUB_CALLS="$WORK/calls-marker.log" \
  STUB_SCAN_RC=0 STUB_SCAN_OUT="$(scan_row 9 0 0 8 "1970-01-01 00:00:00" 1)" \
  STUB_COUNT_RC=0 STUB_COUNT_OUT="$(count_row 0)" \
  bash "$PROBE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ] && [ "$(grep -c '^INVOCATION$' "$WORK/calls-marker.log")" = "1" ]; then
  pass "no-marker arm never issues the absence query (rc=$rc, 1 query)"
else
  fail "no-marker arm must stop after the scan query (rc=$rc, calls: $(grep -c '^INVOCATION$' "$WORK/calls-marker.log" 2>/dev/null))"
fi

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '%s passed, %s failed\n' "$passes" "${#FAILURES[@]}"; exit 1
fi
# Anti-vacuity floor, reported outside the helpers it backstops (ADR-193: printf + exit 1).
if [[ "$passes" -lt 17 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s cases passed (expected 17)\n' "$passes" >&2
  exit 1
fi
printf '%s passed, 0 failed\n' "$passes"
