#!/usr/bin/env bash
# Characterization + strict-mode suite for scripts/fresh-host-boot-trail.sh (#12866).
#
# PROPERTY (characterization). The web callers (web_host_create, web_host_replace) never set
# BOOT_TRAIL_STRICT, so whatever the reader prints for them — stdout+stderr, exit code, and the
# GITHUB_STEP_SUMMARY it appends — must stay BYTE-IDENTICAL across the change that adds strict mode.
# The goldens under test-fixtures/fresh-host-boot-trail/ were captured from the reader as it stood on
# origin/main BEFORE strict mode existed (the first commit of this suite), so a strict-mode edit that
# leaks into the default path reds here, row by row, naming the case.
#
# INSTRUMENT. curl is a PATH stub serving fixture Sentry pages by endpoint (project events vs org
# Discover); sleep refuses (no characterization case may reach the 30 s poll sleep, so every case
# terminates on its first iteration and the output is deterministic). Every run is bounded by
# `timeout`. Event fixtures are synthesized (no real host ids, ADR-322).
#
# Regenerate goldens ONLY from a reader you have proven unchanged on the default path:
#   FHBT_REGEN=1 bash apps/web-platform/infra/fresh-host-boot-trail.test.sh
#
# ANTI-VACUITY. `cases` moves at every assertion call site; the floor and passes+fails==cases are
# reported by printf + exit 1, never through fail() (ADR-193).
# Presence under apps/web-platform/infra/ IS registration — run-registered-suites.sh (#8736).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

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

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAIL="$DIR/scripts/fresh-host-boot-trail.sh"
GOLD="$DIR/test-fixtures/fresh-host-boot-trail"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both verdict helpers once; refuse to continue unless both moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) - EXPECTED, subtracted below"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left passes=%d fails=%d, expected 1/1.\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

eq() { # <name> <actual> <expected>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1"; printf '  got:  %s\n  want: %s\n' "$(head -c 600 <<<"$2")" "$(head -c 600 <<<"$3")" >&2; fi
}
ok() { # <name> <rc>: 0 = holds
  cases=$((cases + 1))
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

harness() { printf '[HARNESS] %s\n' "$1" >&2; exit 2; }
[[ -s "$TRAIL" ]] || harness "missing $TRAIL"
command -v jq >/dev/null 2>&1 || harness "jq is required"
command -v python3 >/dev/null 2>&1 || harness "python3 is required"

WORK="$(mktemp -d "${TMPDIR}/fhbt.XXXXXXXX")" || harness "mktemp failed"
assert_fixture_dir "$WORK"
trap 'rm -rf "${WORK:?}"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

# curl stub: serves the fixture page for the endpoint the reader asked; drains the stdin config
# (the bearer channel); refuses any URL it was not taught.
cat > "$BIN/curl" <<'STUB'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -w|--max-time|--data-urlencode|--noproxy|--config) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
cat > /dev/null
case "$url" in
  https://de.sentry.io/api/0/organizations/*) cp "$FHBT_ORG" "$out"; printf '200' ;;
  https://de.sentry.io/api/0/projects/*) cp "$FHBT_PROJ" "$out"; printf '%s' "${FHBT_PROJ_CODE:-200}" ;;
  *) printf '000'; exit 7 ;;
esac
STUB
# sleep stub: no characterization case may reach the poll sleep. Reaching it is a fixture defect,
# so it is made loud (and the outer `timeout` bounds the busy loop that would follow).
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
echo "FHBT_SLEEP_REACHED $*" >&2
exit 1
STUB
chmod +x "$BIN/curl" "$BIN/sleep"

# ev.py <out> <spec>...: each spec is message|stage|host|level|date|detail ("-" host = untagged).
cat > "$WORK/ev.py" <<'PY'
import json, sys
out = sys.argv[1]
evs = []
for spec in sys.argv[2:]:
    msg, stage, host, level, date, detail = spec.split("|")
    tags = [{"key": "stage", "value": stage}, {"key": "level", "value": level}]
    if host != "-":
        tags.append({"key": "host_name", "value": host})
    if detail:
        tags.append({"key": "detail", "value": detail})
    evs.append({"message": msg, "dateCreated": date, "tags": tags})
json.dump(evs, open(out, "w"))
PY
CI_MSG="soleur-cloud-init boot stage"
D1="2026-09-24T10:01:00Z"; D2="2026-09-24T10:02:00Z"; D3="2026-09-24T10:03:00Z"
ANCHOR=1790000000   # 2026-09-21: older than every fixture row
mkev() { python3 "$WORK/ev.py" "$@" || harness "event fixture build failed"; }
echo '{"data":[]}' > "$WORK/org-empty.json"

# run_trail <case> [VAR=value ...]: runs the reader under the stubs with exactly the given env (plus
# the fixture paths), and writes "<rc>\n--- out\n<stdout+stderr>\n--- summary\n<summary>" to
# $WORK/<case>.got.
run_trail() {
  local name="$1"; shift
  local sum="$WORK/$name.summary" rc=0 out
  : > "$sum"
  out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" \
    FHBT_ORG="${FHBT_ORG_FILE:-$WORK/org-empty.json}" FHBT_PROJ="$WORK/$name.proj.json" \
    GITHUB_STEP_SUMMARY="$sum" "$@" timeout 30 bash "$TRAIL" 2>&1)" || rc=$?
  printf 'rc=%s\n--- out\n%s\n--- summary\n%s\n' "$rc" "$out" "$(cat "$sum")" > "$WORK/$name.got"
}

# char <case>: compares (or, under FHBT_REGEN=1, writes) the golden for one case.
CHAR_ROWS=0
char() {
  local name="$1" got
  CHAR_ROWS=$((CHAR_ROWS + 1))
  got="$(cat "$WORK/$name.got")"
  if [[ "${FHBT_REGEN:-0}" == 1 ]]; then
    assert_fixture_dir "$GOLD"
    mkdir -p "$GOLD"; printf '%s\n' "$got" > "$GOLD/$name.golden"
  fi
  [[ -f "$GOLD/$name.golden" ]] || { cases=$((cases + 1)); fail "char $name: golden missing ($GOLD/$name.golden)"; return; }
  eq "char $name: default-path output is byte-identical to the pre-strict golden" "$got" "$(cat "$GOLD/$name.golden")"
  grep -q 'FHBT_SLEEP_REACHED' <<<"$got" && { cases=$((cases + 1)); fail "char $name: the case reached the poll sleep (fixture defect)"; }
  return 0
}

# ── Characterization cases (web callers; BOOT_TRAIL_STRICT never set) ─────────────────────────
mkev "$WORK/c01.proj.json"
run_trail c01 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR"; char c01            # unbound token, success
mkev "$WORK/c02.proj.json"
run_trail c02 JOB_STATUS=failure WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR"; char c02            # unbound token, failed job
mkev "$WORK/c03.proj.json"
run_trail c03 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" 'SENTRY_ACTIONS_RO_TOKEN=a b'; char c03  # bad-shape token
mkev "$WORK/c04.proj.json"
run_trail c04 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE=abc SENTRY_ACTIONS_RO_TOKEN=x; char c04   # non-epoch anchor
mkev "$WORK/c05.proj.json"
run_trail c05 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x FHBT_PROJ_CODE=500 DISPATCH_LABEL=web-host-replace; char c05
mkev "$WORK/c06.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-2|info|$D3|" "$CI_MSG|cloud_init_complete|soleur-web-2|info|$D2|" "$CI_MSG|runcmd_start|soleur-web-2|info|$D1|"
run_trail c06 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c06   # ready
mkev "$WORK/c07.proj.json" "$CI_MSG|apt_install|soleur-web-2|fatal|$D2|rc=100 attempts=3" "$CI_MSG|runcmd_start|soleur-web-2|info|$D1|"
run_trail c07 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x DISPATCH_LABEL=web-host-replace; char c07   # fatal
mkev "$WORK/c08.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-platform|info|$D3|"
run_trail c08 JOB_STATUS=success WEB_HOST_KEY=web-1 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c08   # web-1 host_name mapping
mkev "$WORK/c09.proj.json" "$CI_MSG|fresh_boot_ready|-|info|$D3|"
run_trail c09 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c09   # untagged ready matches today
mkev "$WORK/c10.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-3|info|$D3|"
run_trail c10 JOB_STATUS=failure WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c10   # other host's ready excluded
mkev "$WORK/c11.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-2|info|$D3|"
run_trail c11 JOB_STATUS=success WEB_HOST_KEY=web-2 SENTRY_ACTIONS_RO_TOKEN=x; char c11   # no run anchor
mkev "$WORK/c12.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-2|info|$D3|" "$CI_MSG|doppler_retry|soleur-web-2|info|$D1|rc=124 attempt=1"
run_trail c12 JOB_STATUS=success WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c12   # retried but ready
mkev "$WORK/c13.proj.json" "$CI_MSG|apt_install|soleur-web-2|fatal|$D2|rc=100"
run_trail c13 JOB_STATUS=failure WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c13   # fatal, failed job
mkev "$WORK/c14.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-2|info|1999-01-01T00:00:00Z|"
run_trail c14 JOB_STATUS=failure WEB_HOST_KEY=web-2 BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x; char c14   # predecessor event excluded by anchor

echo
MIN_CASES=14
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'fresh-host-boot-trail: FAIL (only %d assertions ran; floor %d - the suite may have been truncated)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ "$CHAR_ROWS" -ne 14 ]]; then
  printf 'fresh-host-boot-trail: FAIL (%d characterization rows ran, expected exactly 14)\n' "$CHAR_ROWS" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'fresh-host-boot-trail: FAIL (accounting: passes+fails=%d != cases=%d; a verdict helper was neutered)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'fresh-host-boot-trail: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2
  exit 1
fi
printf 'fresh-host-boot-trail: PASS (%d assertions, 0 failed)\n' "$cases"
