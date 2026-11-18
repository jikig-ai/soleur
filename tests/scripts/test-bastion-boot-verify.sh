#!/usr/bin/env bash
# Suite for scripts/lib/bastion-boot-verify.sh (#12866, Phase 4.2).
#
# PROPERTY. The bastion birth is ready ONLY when the strict reader prints exactly one
# `verdict=ready` and exits 0. Every other outcome (not_ready, skipped, no verdict, two verdicts, a
# ready line beside a non-zero exit, an unreadable reader) powers soleur-bastion off through the
# Hetzner API, prints the recovery step, comments the run on #12879, and returns 1, so a wrong host
# never sits running on the private network while it waits for the replace route.
#
# INSTRUMENT. The reader is a stub that prints a scripted body and exit code; curl and gh are PATH
# stubs that log their argv (and the curl config on stdin) and refuse anything they were not taught.
# Mutation rows edit a sandbox copy of the library and require the matching row to flip.
#
# ANTI-VACUITY. `cases` moves at every assertion; floor and passes+fails==cases by printf + exit (ADR-193).
# Run: bash tests/scripts/test-bastion-boot-verify.sh
# shellcheck disable=SC2319  # each row passes a [[ ]] test's own status as its verdict, by design
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
LIB="${ROOT}/scripts/lib/bastion-boot-verify.sh"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -z "${2:-}" ]] || printf '       %s\n' "$(head -c 900 <<<"$2")"; }
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail)" >/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: INSTRUMENT BROKEN (passes=%d fails=%d)\n' "$passes" "$fails" >&2; exit 2
fi
passes=0
fails=0
harness() { printf 'HARNESS: %s\n' "$1" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR}/bbv.XXXXXXXX")" || harness "mktemp failed"
case "$WORK" in /*/bbv.*) : ;; *) harness "mktemp returned '$WORK'" ;; esac
trap 'rm -rf "${WORK:?}"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# Reader stub: prints $BBV_READER_OUT and exits $BBV_READER_RC; records its env.
cat > "$WORK/reader.sh" <<'STUB'
#!/usr/bin/env bash
printf 'STRICT=%s HOST=%s SINCE=%s JOB=%s LABEL=%s\n' "${BOOT_TRAIL_STRICT:-}" "${BOOT_TRAIL_HOST_NAME:-}" "${BOOT_TRAIL_SINCE:-}" "${JOB_STATUS:-}" "${DISPATCH_LABEL:-}" > "$BBV_LOG/reader.env"
printf '%b' "$BBV_READER_OUT"
exit "$BBV_READER_RC"
STUB
# curl stub: Hetzner servers lookup and poweroff only.
cat > "$BIN/curl" <<'STUB'
#!/bin/sh
out=""; url=""; method=GET
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -X) method="$2"; shift ;;
    -w|--max-time|--config|-H|--data|-d) shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
cfg=$(cat)
printf '%s %s\n' "$method" "$url" >> "$BBV_LOG/curl.log"
printf '%s\n' "$cfg" >> "$BBV_LOG/curl.cfg"
case "$method $url" in
  "GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion")
    [ "${BBV_LOOKUP_CODE:-200}" = 200 ] || { echo '{}' > "$out"; printf '%s' "$BBV_LOOKUP_CODE"; exit 0; }
    if [ -n "${BBV_LOOKUP_BODY:-}" ]; then printf '%s' "$BBV_LOOKUP_BODY" > "$out"
    else echo '{"servers":[{"id":4242,"name":"soleur-bastion"}]}' > "$out"; fi
    printf '200' ;;
  "POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff")
    echo '{"action":{"id":1,"status":"running"}}' > "$out"; printf '%s' "${BBV_POWEROFF_CODE:-201}" ;;
  *) printf '000'; exit 7 ;;
esac
STUB
cat > "$BIN/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$BBV_LOG/gh.log"
[ "$1 $2 $3" = "issue comment 12879" ] || exit 9
exit 0
STUB
chmod +x "$WORK/reader.sh" "$BIN/curl" "$BIN/gh"

LIB_UNDER_TEST="$LIB"
# run <case> <reader-out> <reader-rc> <apply-outcome> [VAR=value...] -> RC, OUT, logs in $WORK/<case>/
run() {
  local name="$1" rout="$2" rrc="$3" apply="$4"; shift 4
  local log="$WORK/$name"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/curl.cfg"; : > "$log/gh.log"
  RC=0
  OUT="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" BBV_READER_OUT="$rout" BBV_READER_RC="$rrc" \
    BASTION_BOOT_TRAIL="$WORK/reader.sh" HCLOUD_TOKEN=hcloudtok123 GH_TOKEN=ghtok RUN_URL="https://github.com/o/r/actions/runs/1" \
    "$@" bash -c 'source "$1" || exit 98; bastion_boot_verify 1790000000 "$2"' _ "$LIB_UNDER_TEST" "$apply" 2>&1)" || RC=$?
  CURL="$(cat "$log/curl.log")"; GH="$(cat "$log/gh.log")"; CFG="$(cat "$log/curl.cfg")"; RENV="$(cat "$log/reader.env" 2>/dev/null)"
}
POWEROFF="POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff"
t() { cases=$((cases + 1)); if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "rc=$RC out=$OUT curl=$CURL gh=$GH"; fi; }
not_ready_shape() { [[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && "$GH" == *"issue comment 12879"* && "$OUT" == *"bastion-host-replace"* ]]; }

RC=0 CURL="" GH=""
t "the library exists at scripts/lib/bastion-boot-verify.sh" "$([[ -s "$LIB" ]]; echo $?)"

echo "verdicts"
run ready 'verdict=ready\n' 0 success
t "ready: exactly one verdict=ready and exit 0 returns 0" "$([[ "$RC" -eq 0 ]]; echo $?)"
t "ready: nothing is powered off and no comment is posted" "$([[ -z "$CURL" && -z "$GH" ]]; echo $?)"
t "ready: the reader ran strict for soleur-bastion with the anchor and job=success" "$([[ "$RENV" == "STRICT=1 HOST=soleur-bastion SINCE=1790000000 JOB=success LABEL=bastion-host-create" ]]; echo $?)"
run notready 'verdict=not_ready\n' 1 success
t "not_ready: powers off, comments on #12879, names the recovery, returns 1" "$(not_ready_shape; echo $?)"
run skipped 'verdict=skipped\n' 2 success
t "skipped (an unread boot) is not ready: powers off and returns 1" "$(not_ready_shape; echo $?)"
run noverdict 'boot-trail: something\n' 0 success
t "no verdict line is not ready, even with exit 0" "$(not_ready_shape; echo $?)"
run twoverdicts 'verdict=ready\nverdict=ready\n' 0 success
t "two verdict lines are not ready" "$(not_ready_shape; echo $?)"
run readyrc1 'verdict=ready\n' 1 success
t "verdict=ready beside a non-zero exit is not ready" "$(not_ready_shape; echo $?)"
run readyspace 'verdict=ready \n' 0 success
t "a verdict with trailing bytes is not ready" "$(not_ready_shape; echo $?)"
run applyfail 'verdict=not_ready\n' 1 failure
t "a failed apply reads the trail with job=failure" "$([[ "$RENV" == *"JOB=failure"* ]]; echo $?)"
t "a failed apply that created the server still powers it off" "$(not_ready_shape; echo $?)"
run noreader 'verdict=ready\n' 0 success BASTION_BOOT_TRAIL="$WORK/missing.sh"
t "an unreadable reader is not ready" "$(not_ready_shape; echo $?)"

echo "power-off arm"
run noserver 'verdict=not_ready\n' 1 failure BBV_LOOKUP_BODY='{"servers":[]}'
t "no soleur-bastion server: nothing to power off, still returns 1 and comments" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"12879"* && "$OUT" == *"no soleur-bastion server"* ]]; echo $?)"
run twoservers 'verdict=not_ready\n' 1 success BBV_LOOKUP_BODY='{"servers":[{"id":4242,"name":"soleur-bastion"},{"id":4343,"name":"soleur-bastion"}]}'
t "two servers named soleur-bastion: refuses to guess, powers off nothing, returns 1" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$OUT" == *"2 servers"* ]]; echo $?)"
run lookup500 'verdict=not_ready\n' 1 success BBV_LOOKUP_CODE=500
t "an unreadable server lookup is named, still returns 1 and comments" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"12879"* && "$OUT" == *"::error::"*"power"* ]]; echo $?)"
run poweroff500 'verdict=not_ready\n' 1 success BBV_POWEROFF_CODE=500
t "a failed poweroff call is an error naming the manual step, returns 1" "$([[ "$RC" -eq 1 && "$OUT" == *"::error::"*"poweroff"* ]]; echo $?)"
run notoken 'verdict=not_ready\n' 1 success HCLOUD_TOKEN=
t "no HCLOUD_TOKEN: no API call, an error, returns 1" "$([[ "$RC" -eq 1 && -z "$CURL" && "$OUT" == *"HCLOUD_TOKEN"* ]]; echo $?)"
run notready 'verdict=not_ready\n' 1 success
t "the Hetzner token rides the stdin config, never curl's argv" "$([[ "$CFG" == *"hcloudtok123"* ]] && ! grep -q hcloudtok123 "$WORK/notready/curl.log"; echo $?)"
t "the comment carries the run URL" "$([[ "$GH" == *"https://github.com/o/r/actions/runs/1"* ]]; echo $?)"
run nogh 'verdict=not_ready\n' 1 success GH_TOKEN=
t "no GH_TOKEN: the comment is skipped by name, the power-off still happens" "$([[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && -z "$GH" && "$OUT" == *"#12879"* ]]; echo $?)"

echo "mutation rows"
MUT=0
mrow() { # <label> <from> <to> <case-args...>: the mutant must change the case's verdict
  local label="$1" from="$2" to="$3"; shift 3
  MUT=$((MUT + 1))
  python3 - "$LIB" "$WORK/mut$MUT.sh" "$from" "$to" <<'PY' || { cases=$((cases + 1)); fail "mutation $label did not land"; return; }
import sys
s, d, a, b = sys.argv[1:]
t = open(s).read()
if t.count(a) != 1: sys.exit(1)
open(d, "w").write(t.replace(a, b))
PY
  run "$@"; local before="$RC|$CURL"
  LIB_UNDER_TEST="$WORK/mut$MUT.sh" run "$@"; local after="$RC|$CURL"
  LIB_UNDER_TEST="$LIB"
  cases=$((cases + 1))
  if [[ "$before" != "$after" ]]; then pass "mutation caught: $label"; else fail "mutation SURVIVED: $label"; fi
}
mrow "skipped accepted as ready" '[[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]' '[[ ( "$verdicts" == "verdict=ready" || "$verdicts" == "verdict=skipped" ) ]]' skipped 'verdict=skipped\n' 2 success
mrow "the exit code ignored" '[[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]' '[[ "$verdicts" == "verdict=ready" ]]' readyrc1 'verdict=ready\n' 1 success
mrow "the poweroff call removed" '"https://api.hetzner.cloud/v1/servers/${id}/actions/poweroff"' '"https://api.hetzner.cloud/v1/servers/${id}/actions/reboot"' notready 'verdict=not_ready\n' 1 success

echo
MIN_CASES=24
if [[ "$cases" -lt "$MIN_CASES" ]]; then printf 'test-bastion-boot-verify: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2; exit 1; fi
if [[ $((passes + fails)) -ne "$cases" ]]; then printf 'test-bastion-boot-verify: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2; exit 1; fi
if [[ "$fails" -gt 0 ]]; then printf 'test-bastion-boot-verify: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2; exit 1; fi
printf 'test-bastion-boot-verify: PASS (%d assertions, 0 failed)\n' "$cases"
