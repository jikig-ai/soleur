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
  https://de.sentry.io/api/0/projects/*)
    # After the poll has slept once (strict rows only), the next page is a 500: the reader then
    # ends on its read-failed arm, so a row that must NOT terminate on the first page still ends.
    if [ -n "${FHBT_SLEPT:-}" ] && [ -e "$FHBT_SLEPT" ]; then echo '{"detail":"stub: after sleep"}' > "$out"; printf '500'; exit 0; fi
    cp "$FHBT_PROJ" "$out"; printf '%s' "${FHBT_PROJ_CODE:-200}" ;;
  *) printf '000'; exit 7 ;;
esac
STUB
# sleep stub: no characterization case may reach the poll sleep. Reaching it is a fixture defect,
# so it is made loud (and the outer `timeout` bounds the busy loop that would follow).
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
echo "FHBT_SLEEP_REACHED $*" >&2
[ -z "${FHBT_SLEPT:-}" ] || : > "$FHBT_SLEPT"
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

# ── Strict mode (the bastion route, #12866) ───────────────────────────────────────────────────
# BOOT_TRAIL_STRICT=1 reads by BOOT_TRAIL_HOST_NAME, requires the event's host_name tag to EQUAL it
# (an untagged event no longer matches), refuses a missing or non-epoch anchor, and prints exactly
# one verdict=ready|not_ready|skipped line (exit 0|1|2). Rows that must NOT terminate on the first
# page sleep once and then read a 500, so they end on the skipped arm instead of spinning.
STRICT_ROWS=0
# run_strict <case> [VAR=value ...] (TRAIL_UNDER_TEST overrides the reader, for the mutation rows)
run_strict() {
  local name="$1"; shift
  rm -f "$WORK/$name.slept"
  TRAIL="${TRAIL_UNDER_TEST:-$TRAIL}" run_trail "$name" BOOT_TRAIL_STRICT=1 FHBT_SLEPT="$WORK/$name.slept" "$@"
  S_RC="$(sed -n '1s/^rc=//p' "$WORK/$name.got")"
  S_VERDICTS="$(grep -c '^verdict=' "$WORK/$name.got" || true)"
  S_VERDICT="$(sed -n 's/^verdict=//p' "$WORK/$name.got" | head -1)"
  S_SLEPT=no; [[ -e "$WORK/$name.slept" ]] && S_SLEPT=yes
}
# srow <name> <case> <want: verdict rc slept> [VAR=value ...]
srow() {
  local label="$1" name="$2" want="$3"; shift 3
  STRICT_ROWS=$((STRICT_ROWS + 1))
  run_strict "$name" "$@"
  eq "strict $name: $label" "$S_VERDICT $S_RC $S_SLEPT" "$want"
  eq "strict $name: exactly one verdict line" "$S_VERDICTS" 1
}
B=soleur-bastion
SB=(JOB_STATUS=success "BOOT_TRAIL_HOST_NAME=$B" BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x DISPATCH_LABEL=bastion-host-create)
mkev "$WORK/s01.proj.json" "$CI_MSG|fresh_boot_ready|$B|info|$D3|" "$CI_MSG|cloud_init_complete|$B|info|$D2|"
srow "a ready event tagged for the bastion is ready" s01 "ready 0 no" "${SB[@]}"
mkev "$WORK/s02.proj.json" "$CI_MSG|fresh_boot_ready|-|info|$D3|"
srow "an UNTAGGED ready event does not match (it would on the web path)" s02 "skipped 2 yes" "${SB[@]}"
mkev "$WORK/s03.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-2|info|$D3|"
srow "a ready event tagged for another host does not match" s03 "skipped 2 yes" "${SB[@]}"
mkev "$WORK/s04.proj.json" "$CI_MSG|fresh_boot_ready|$B|info|$D3|"
srow "a missing run anchor is refused before any read" s04 "skipped 2 no" JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B SENTRY_ACTIONS_RO_TOKEN=x
cp "$WORK/s04.proj.json" "$WORK/s05.proj.json"
srow "a non-epoch run anchor is refused" s05 "skipped 2 no" JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B BOOT_TRAIL_SINCE=abc SENTRY_ACTIONS_RO_TOKEN=x
cp "$WORK/s04.proj.json" "$WORK/s06.proj.json"
srow "an unbound token is skipped, never ready" s06 "skipped 2 no" JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B BOOT_TRAIL_SINCE="$ANCHOR"
cp "$WORK/s04.proj.json" "$WORK/s07.proj.json"
srow "a malformed token is skipped, never ready" s07 "skipped 2 no" JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B BOOT_TRAIL_SINCE="$ANCHOR" 'SENTRY_ACTIONS_RO_TOKEN=a"b'
mkev "$WORK/s08.proj.json" "$CI_MSG|fresh_boot_not_ready_egress|$B|fatal|$D3|why=apt_update" "$CI_MSG|fresh_boot_ready|$B|info|$D2|"
srow "a fatal event for the bastion is not ready, even beside a ready one" s08 "not_ready 1 no" "${SB[@]}"
cp "$WORK/s01.proj.json" "$WORK/s09.proj.json"
srow "a failed job is not ready, even when a ready event exists" s09 "not_ready 1 no" JOB_STATUS=failure BOOT_TRAIL_HOST_NAME=$B BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x
mkev "$WORK/s10.proj.json" "$CI_MSG|cloud_init_complete|$B|info|$D2|"
srow "cloud_init_complete without fresh_boot_ready is not ready" s10 "not_ready 1 no" "${SB[@]}" SOLEUR_BOOT_TRAIL_CC_GRACE=0
cp "$WORK/s01.proj.json" "$WORK/s11.proj.json"
srow "a malformed host name is refused" s11 "skipped 2 no" JOB_STATUS=success 'BOOT_TRAIL_HOST_NAME=soleur bastion' BOOT_TRAIL_SINCE="$ANCHOR" SENTRY_ACTIONS_RO_TOKEN=x
cp "$WORK/s01.proj.json" "$WORK/s12.proj.json"
srow "an unreadable Sentry page is skipped, never ready" s12 "skipped 2 no" "${SB[@]}" FHBT_PROJ_CODE=500
mkev "$WORK/s13.proj.json" "$CI_MSG|fresh_boot_ready|soleur-web-platform|info|$D3|"
srow "the web-1 host_name mapping is not applied in strict mode" s13 "skipped 2 yes" "${SB[@]}" WEB_HOST_KEY=web-1
# An invalid switch value is refused by name (a typo must never silently fall back to the lax path).
cp "$WORK/s01.proj.json" "$WORK/s14.proj.json"
run_trail s14 BOOT_TRAIL_STRICT=yes "${SB[@]}"
eq "strict s14: BOOT_TRAIL_STRICT=yes is refused (skipped, rc 2), not read as off" \
  "$(sed -n '1s/^rc=//p' "$WORK/s14.got") $(sed -n 's/^verdict=//p' "$WORK/s14.got")" "2 skipped"
# The web path never prints a verdict line (the characterization goldens hold it byte for byte;
# this row names the property directly).
eq "web path: no characterization case printed a verdict= line" "$(cat "$WORK"/c*.got | grep -c '^verdict=' || true)" 0

# ── Mutation rows over a sandbox copy of the reader ──────────────────────────────────────────
MUT_ROWS=0
# mrow <name> <case> <from> <to> <args...>: the mutant must change the case's verdict away from ready-safe
mrow() {
  local name="$1" case="$2" from="$3" to="$4" before after; shift 4
  MUT_ROWS=$((MUT_ROWS + 1))
  local m="$WORK/mutant-$MUT_ROWS.sh"
  python3 - "$TRAIL" "$m" "$from" "$to" <<'MPY' || { cases=$((cases + 1)); fail "mutation $name did not land"; return; }
import sys
src, dst, a, b = sys.argv[1:]
t = open(src).read()
if t.count(a) != 1:
    sys.exit(1)
open(dst, "w").write(t.replace(a, b))
MPY
  run_strict "$case" "$@"; before="$S_VERDICT"
  TRAIL_UNDER_TEST="$m" run_strict "$case" "$@"; after="$S_VERDICT"
  cases=$((cases + 1))
  if [[ "$before" != "$after" ]]; then pass "mutation $name is caught by $case ($before -> $after)"; else fail "mutation $name SURVIVED $case ($before)"; fi
}
mrow "strict host match accepts an untagged event" s02 '($hn != null and $hn == $eh)' '($hn == null or $hn == "" or $hn == $eh)' "${SB[@]}"
mrow "strict host name not used (web mapping)" s03 'EXPECT_HOST="$BOOT_TRAIL_HOST_NAME"' 'EXPECT_HOST="soleur-web-2"' "${SB[@]}"
mrow "missing anchor accepted" s04 '|| "$BOOT_TRAIL_SINCE" == "0"' '' JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B SENTRY_ACTIONS_RO_TOKEN=x
mrow "unbound token read as not-skipped" s06 'strict_verdict skipped "the Sentry token is not bound (unbound token)"' 'strict_verdict ready "the Sentry token is not bound (unbound token)"' JOB_STATUS=success BOOT_TRAIL_HOST_NAME=$B BOOT_TRAIL_SINCE="$ANCHOR"

echo
MIN_CASES=46
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'fresh-host-boot-trail: FAIL (only %d assertions ran; floor %d - the suite may have been truncated)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ "$CHAR_ROWS" -ne 14 || "$STRICT_ROWS" -ne 13 || "$MUT_ROWS" -ne 4 ]]; then
  printf 'fresh-host-boot-trail: FAIL (rows ran: characterization %d/14, strict %d/13, mutation %d/4)\n' "$CHAR_ROWS" "$STRICT_ROWS" "$MUT_ROWS" >&2
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
