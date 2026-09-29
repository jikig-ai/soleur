#!/usr/bin/env bash
# Exit-code + branch harness for cwv-field-rum-9178.sh (#9178 field-RUM follow-through).
#
# The probe's exit code IS its authorization artifact: sweep-followthroughs.sh closes
# #9178 on 0, comments+leaves-open on 1, renders 2 as NOT YET and 3 as CANNOT ESTABLISH.
# The verdicts that must never lie:
#   * PASS requires a returned row carrying a non-null vital MEASUREMENT — a row
#     count alone (or a `has:` clause trusting the query grammar) is not proof the
#     vitals attachment survived the wire.
#   * FAIL requires a vital-LESS PAGELOAD row — pageload transactions demonstrably
#     landing without the measurements this deploy exists to attach. A window with
#     only navigation rows (which never carry FCP/LCP/TTFB) or none at all must NOT
#     post a public FAIL on a healthy fleet.
#   * The start= pin must reach the wire — the stub records its argv and a case
#     asserts the SOLEUR_FT_EARLIEST-derived start appears in the query URL, so
#     "pinnable strictly after deploy" is pinned mechanically, not by prose.
#
# SEAM: the probe's only I/O is one curl GET. The stub below is FAITHFUL to the
# real invocation `curl -sS -w '\nHTTP_STATUS:%{http_code}'`: it prints the body,
# then the HTTP_STATUS trailer on its own line, and records argv so the query
# construction is asserted, not assumed. No network, no creds.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): every timestamp,
# title and measurement is fabricated in this file.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/cwv-field-rum-9178.sh"
[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

fails=0
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Byte-for-byte copy of the canonical assertion in plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh drift-checks every copy). Guards the scratch root
# before any write lands under it.
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

WORK="$(mktemp -d -t cwvrum9178.XXXXXXXX)" || { echo "FATAL: no scratch root" >&2; exit 1; }
assert_fixture_dir "$WORK"
readonly WORK
trap 'rm -rf -- "$WORK"' EXIT INT TERM

EARLIEST="2026-09-27T18:00:00Z"   # fabricated post-deploy pin (deploy+1d shape)

# A Sentry events payload is {"data":[rows]}. Each row carries the fields the
# probe requests; absent measurements serialize as missing keys -> jq reads null.
row() { # <op> <measurements-json-fragment-or-empty>
  local m=""; [[ -n "${2:-}" ]] && m=", $2"
  printf '{"title":"/dashboard","timestamp":"2026-09-30T09:00:00+00:00","transaction.op":"%s"%s}\n' "$1" "$m"
}
rows_doc() { # rows on stdin -> {"data":[...]}
  printf '{"data":['; paste -sd, -; printf ']}\n'
}

# run_probe <fixture-file> [NAME=val ...] — installs the curl stub, runs the SUT
# under env -i (the sweeper's real shape) with the default env + any extra
# NAME=val overrides (LAST assignment wins inside env). Prints the exit code;
# combined output lands in $WORK/out and the stubbed curl argv in $WORK/last-argv.
run_probe() {
  local fixture="$1"; shift
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/curl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$WORK/last-argv"
case "\${CURL_STUB_MODE:-200}" in
  200) cat "$fixture"; printf '\nHTTP_STATUS:200\n' ;;
  401) printf '{"detail":"Invalid token"}\nHTTP_STATUS:401\n' ;;
  borked) printf 'this is not json\nHTTP_STATUS:200\n' ;;
esac
STUB
  chmod +x "$WORK/bin/curl"
  env -i \
    PATH="$WORK/bin:/usr/bin:/bin" \
    HOME="$HOME" \
    SENTRY_ACTIONS_RO_TOKEN=stub-token \
    SOLEUR_FT_EARLIEST="$EARLIEST" \
    "$@" \
    bash "$SUT" >"$WORK/out" 2>&1
  echo $?
}

expect() { # <name> <expected-rc> <branch-marker-substring> — reads $WORK/rc + $WORK/out
  local name="$1" want="$2" marker="$3" got
  got="$(cat "$WORK/rc")"
  if [[ "$got" == "$want" ]] && grep -qF -- "$marker" "$WORK/out"; then
    pass "$name (exit $got)"
  else
    fail "$name — expected exit $want + marker '$marker', got exit $got"
    sed 's/^/        | /' "$WORK/out" >&2
  fi
}

echo "== cwv-field-rum-9178.sh arms =="

# 1 — PASS: a pageload row carrying vital measurements.
printf '{"data":[%s]}\n' "$(row pageload '"measurements.lcp":1240.5,"measurements.fcp":610.2,"measurements.cls":0.02,"measurements.inp":88,"measurements.ttfb":310.0')" > "$WORK/f1"
run_probe "$WORK/f1" > "$WORK/rc"
expect "vital-bearing pageload -> PASS" 0 "PASS: 1 vital-bearing"

# 2 — FAIL: pageload rows land but NONE carries a vital measurement (the
#    broken-attachment signature this probe exists to catch).
{ row pageload; row pageload; } | rows_doc > "$WORK/f2"
run_probe "$WORK/f2" > "$WORK/rc"
expect "pageloads without any vital -> FAIL" 1 "FAIL: 2 /dashboard pageload"

# 3 — NOT YET: zero rows at all. Absence of a sampled pageload is not evidence
#    of a broken pipeline (0.1 sampling + a quiet day) — must never read as FAIL
#    and must never PASS vacuously.
printf '{"data":[]}\n' > "$WORK/f3"
run_probe "$WORK/f3" > "$WORK/rc"
expect "zero rows -> NOT YET" 2 "NOT YET: zero /dashboard pageload"

# 4 — NOT YET: only NAVIGATION rows, none vital-bearing. Navigation transactions
#    cannot carry FCP/LCP/TTFB, so they prove nothing in either direction —
#    the FAIL denominator is pageload rows only.
{ row navigation; row navigation; } | rows_doc > "$WORK/f4"
run_probe "$WORK/f4" > "$WORK/rc"
expect "navigation-only rows -> NOT YET (never FAIL)" 2 "NOT YET"

# 5 — PASS: a navigation row WITH a vital still proves the pipeline lands.
printf '{"data":[%s]}\n' "$(row navigation '"measurements.inp":96')" > "$WORK/f5"
run_probe "$WORK/f5" > "$WORK/rc"
expect "vital-bearing navigation row -> PASS" 0 "PASS: 1 vital-bearing"

# 6 — PASS mixed window: vital-less pageloads plus ONE vital-bearing row still
#    close PASS (the numerator is "any vital-bearing", not "all").
printf '{"data":[%s,%s]}\n' "$(row pageload)" "$(row pageload '"measurements.fcp":540')" > "$WORK/f6"
run_probe "$WORK/f6" > "$WORK/rc"
expect "one vital-bearing among vital-less -> PASS" 0 "PASS: 1 vital-bearing"

# 7 — TRANSIENT: Sentry auth failure (401) is never a verdict.
run_probe "$WORK/f1" CURL_STUB_MODE=401 > "$WORK/rc"
expect "HTTP 401 -> TRANSIENT" 2 "TRANSIENT: Sentry API returned 401"

# 8 — TRANSIENT: unparseable body under a 200 (proxy HTML, truncated payload).
run_probe "$WORK/f1" CURL_STUB_MODE=borked > "$WORK/rc"
expect "unparseable body -> TRANSIENT" 2 "TRANSIENT: could not grade"

# 9 — TRANSIENT: the credential is unset/empty. Must be exit 2, NEVER 1: a `:?`
#    gate would abort with status 1 = FAIL = a false public alarm on a
#    provisioning gap.
run_probe "$WORK/f1" SENTRY_ACTIONS_RO_TOKEN= > "$WORK/rc"
expect "SENTRY_ACTIONS_RO_TOKEN empty -> TRANSIENT" 2 "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN not set"

# 10 — CANNOT ESTABLISH: no start pin at all. SOLEUR_FT_EARLIEST empty and no
#     CWV_RUM_START override -> refusing to grade an unbounded window is exit 3.
run_probe "$WORK/f1" SOLEUR_FT_EARLIEST= > "$WORK/rc"
expect "no start pin -> CANNOT ESTABLISH" 3 "CANNOT ESTABLISH: no post-deploy window start"

# 11 — CANNOT ESTABLISH: a malformed earliest is a PROBE defect to name, not a
#     window to silently widen (date -d accepts natural language).
run_probe "$WORK/f1" SOLEUR_FT_EARLIEST="next friday" > "$WORK/rc"
expect "malformed earliest -> CANNOT ESTABLISH" 3 "CANNOT ESTABLISH: window start"

# 12 — NOT YET: a future-dated start. The sweeper's earliest gate makes this
#     unreachable in CI, but a manually-set pin must not produce a verdict.
run_probe "$WORK/f1" SOLEUR_FT_EARLIEST="2999-01-01T00:00:00Z" > "$WORK/rc"
expect "future start -> NOT YET" 2 "NOT YET: window start 2999-01-01T00:00:00 is in the future"

# 13 — CWV_RUM_START overrides SOLEUR_FT_EARLIEST and reaches the wire.
run_probe "$WORK/f1" CWV_RUM_START="2026-09-26T12:00:00Z" > "$WORK/rc"
expect "CWV_RUM_START override -> PASS" 0 "PASS: 1 vital-bearing"
if grep -qF 'start=2026-09-26T12:00:00' "$WORK/last-argv"; then
  pass "the override start reached the query URL (start=2026-09-26T12:00:00)"
else
  fail "override start missing from URL :: $(cat "$WORK/last-argv")"
fi

# 14 — The SOLEUR_FT_EARLIEST pin reaches the wire as start= (the mechanical
#     half of "start= pinnable strictly after deploy"), and the query carries
#     the op scoping + measurement fields the grading depends on.
run_probe "$WORK/f1" > "$WORK/rc"
expect "earliest-pin window -> PASS" 0 "PASS: 1 vital-bearing"
if grep -qF 'start=2026-09-27T18:00:00' "$WORK/last-argv"; then
  pass "SOLEUR_FT_EARLIEST reached the URL as start=2026-09-27T18:00:00 (post-deploy pin)"
else
  fail "earliest pin missing from URL :: $(cat "$WORK/last-argv")"
fi
if grep -qF 'pageload' "$WORK/last-argv" && grep -qF 'navigation' "$WORK/last-argv" \
   && grep -qF 'field=measurements.lcp' "$WORK/last-argv" \
   && grep -qF 'end=' "$WORK/last-argv"; then
  pass "query carries op scoping, vital fields and end="
else
  fail "query construction drifted :: $(cat "$WORK/last-argv")"
fi

# 15 — XTRACE REFUSAL: live credential + tracing -> exit 78, never a run.
rc=0
env -i PATH="/usr/bin:/bin" HOME="$HOME" SENTRY_ACTIONS_RO_TOKEN=stub-token \
  bash -x "$SUT" >"$WORK/out" 2>&1 || rc=$?
if [[ "$rc" -eq 78 ]] && grep -qF 'refusing to run under xtrace' "$WORK/out"; then
  pass "xtrace + credential -> refusal (exit 78)"
else
  fail "xtrace refusal — expected 78 + refusal marker, got exit $rc"
  sed 's/^/        | /' "$WORK/out" >&2
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails case(s)" >&2
  exit 1
fi
echo "OK: all cwv-field-rum-9178 arms passed"
