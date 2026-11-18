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
printf 'STRICT=%s HOST=%s HID=%s SINCE=%s JOB=%s LABEL=%s\n' "${BOOT_TRAIL_STRICT:-}" "${BOOT_TRAIL_HOST_NAME:-}" "${BOOT_TRAIL_HOST_ID:-}" "${BOOT_TRAIL_SINCE:-}" "${JOB_STATUS:-}" "${DISPATCH_LABEL:-}" > "$BBV_LOG/reader.env"
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
# Like real curl: the body goes to -o when given, else to stdout, and -w's '\n%{http_code}' follows it.
emit() { if [ -n "$out" ]; then printf '%s' "$1" > "$out"; printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi; }
case "$method $url" in
  "GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion")
    [ "${BBV_LOOKUP_CODE:-200}" = 200 ] || { emit '{}' "$BBV_LOOKUP_CODE"; exit 0; }
    if [ -n "${BBV_LOOKUP_BODY:-}" ]; then emit "$BBV_LOOKUP_BODY" 200
    else emit '{"servers":[{"id":4242,"name":"soleur-bastion"}]}' 200; fi ;;
  "POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff")
    emit '{"action":{"id":1,"status":"running"}}' "${BBV_POWEROFF_CODE:-201}" ;;
  *) emit '' 000; exit 7 ;;
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
LABEL_ARG=""   # set for one row to pass bastion_boot_verify's optional 3rd argument
# run <case> <reader-out> <reader-rc> <apply-outcome> [VAR=value...] -> RC, OUT, PO (poweroff_result),
# SUM (step summary), logs in $WORK/<case>/
run() {
  local name="$1" rout="$2" rrc="$3" apply="$4"; shift 4
  local log="$WORK/$name"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/curl.cfg"; : > "$log/gh.log"; : > "$log/out"; : > "$log/sum"
  RC=0
  OUT="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" BBV_READER_OUT="$rout" BBV_READER_RC="$rrc" \
    BASTION_BOOT_TRAIL="$WORK/reader.sh" HCLOUD_TOKEN=hcloudtok123 GH_TOKEN=ghtok RUN_URL="https://github.com/o/r/actions/runs/1" \
    GITHUB_OUTPUT="$log/out" GITHUB_STEP_SUMMARY="$log/sum" \
    "$@" bash -c 'source "$1" || exit 98; bastion_boot_verify 1790000000 "$2" ${3:+"$3"}' _ "$LIB_UNDER_TEST" "$apply" "$LABEL_ARG" 2>&1)" || RC=$?
  CURL="$(cat "$log/curl.log")"; GH="$(cat "$log/gh.log")"; CFG="$(cat "$log/curl.cfg")"; RENV="$(cat "$log/reader.env" 2>/dev/null)"
  PO="$(sed -n 's/^poweroff_result=//p' "$log/out")"; SUM="$(cat "$log/sum")"
}
POWEROFF="POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff"
t() { cases=$((cases + 1)); if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "rc=$RC out=$OUT curl=$CURL gh=$GH"; fi; }
not_ready_shape() { [[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && "$GH" == *"issue comment 12879"* && "$OUT" == *"bastion-host-replace"* ]]; }

RC=0 CURL="" GH=""
t "the library exists at scripts/lib/bastion-boot-verify.sh" "$([[ -s "$LIB" ]]; echo $?)"

ready_bound_shape() { [[ "$RC" -eq 0 && "$CURL" != *POST* && -z "$GH" && "$RENV" == "STRICT=1 HOST=soleur-bastion HID=4242 SINCE=1790000000 JOB=success LABEL=bastion-host-create" ]]; }
echo "verdicts"
run ready 'verdict=ready\n' 0 success
t "ready: exactly one verdict=ready and exit 0 returns 0" "$([[ "$RC" -eq 0 ]]; echo $?)"
t "ready: nothing is powered off and no comment is posted" "$([[ "$CURL" != *POST* && -z "$GH" ]]; echo $?)"
t "ready: the reader ran strict for soleur-bastion, bound to the created server's id, with the anchor and job=success" "$(ready_bound_shape; echo $?)"
t "ready: poweroff_result=not_needed and the summary says READY" "$([[ "$PO" == not_needed && "$SUM" == *"**READY**"* ]]; echo $?)"
run notready 'verdict=not_ready\n' 1 success
t "not_ready: powers off, comments on #12879, names the recovery, returns 1" "$(not_ready_shape; echo $?)"
t "not_ready: poweroff_result=powered_off and the summary says it was powered off" "$([[ "$PO" == powered_off && "$SUM" == *"was powered off"* ]]; echo $?)"
t "the reader's trail is printed exactly once (streamed, not re-printed)" "$([[ "$(grep -c '^verdict=not_ready$' <<<"$OUT")" -eq 1 ]]; echo $?)"
t "the recovery names bastion-host-replace as not yet available" "$([[ "$OUT" == *"bastion-host-replace (#12879, not yet available — escalate to the owner)"* ]]; echo $?)"
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
t "a failed apply reads the trail with job=failure (no id lookup first)" "$([[ "$RENV" == *"HID= "*"JOB=failure"* ]]; echo $?)"
t "a failed apply that created the server still powers it off" "$(not_ready_shape; echo $?)"
run noreader 'verdict=ready\n' 0 success BASTION_BOOT_TRAIL="$WORK/missing.sh"
t "an unreadable reader is not ready" "$(not_ready_shape; echo $?)"
run goneafterapply 'verdict=ready\n' 0 success BBV_LOOKUP_BODY='{"servers":[]}'
t "a successful apply with no soleur-bastion server is not ready, and the trail is not read" "$([[ "$RC" -eq 1 && -z "$RENV" && "$PO" == absent && "$OUT" == *"no soleur-bastion server exists; the boot trail was not read"* ]]; echo $?)"
run lookupblip 'verdict=ready\n' 0 success BBV_LOOKUP_CODE=503
t "a failed pre-read lookup is named and the read proceeds bound by host_name only" "$([[ "$RC" -eq 0 && "$RENV" == *"HID= "* && "$OUT" == *"bound by host_name only"* ]]; echo $?)"
LABEL_ARG=bastion-host-replace
run replacelabel 'verdict=not_ready\n' 1 success
LABEL_ARG=""
t "a dispatch label reaches the reader and the comment, and the create-only advice is dropped" \
  "$([[ "$RENV" == *"LABEL=bastion-host-replace"* && "$GH" == *"bastion-host-replace did not reach ready"* && "$OUT" != *"Do not re-run bastion-host-create"* ]]; echo $?)"
# The library's DEFAULT reader path (no override) reaches the real strict reader: an unbound Sentry
# token there is the reader's own named skip, so its strict line in the output proves which file ran.
run defaultreader 'unused' 0 failure BASTION_BOOT_TRAIL=
t "with no BASTION_BOOT_TRAIL the real reader at the default path runs (its strict skip line is printed)" \
  "$([[ "$RC" -eq 1 && "$OUT" == *"boot-trail strict: the Sentry token is not bound (unbound token)"* && "$OUT" == *"verdict=skipped"* ]]; echo $?)"

echo "power-off arm"
run noserver 'verdict=not_ready\n' 1 failure BBV_LOOKUP_BODY='{"servers":[]}'
t "no soleur-bastion server: nothing to power off, still returns 1 and comments" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"12879"* && "$OUT" == *"no soleur-bastion server"* && "$PO" == absent ]]; echo $?)"
run twoservers 'verdict=not_ready\n' 1 success BBV_LOOKUP_BODY='{"servers":[{"id":4242,"name":"soleur-bastion"},{"id":4343,"name":"soleur-bastion"}]}'
t "two servers named soleur-bastion: refuses to guess, powers off nothing, returns 1" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$OUT" == *"2 servers"* && "$PO" == failed ]]; echo $?)"
lookup_failed_shape() { [[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"12879"* && "$OUT" == *"server lookup failed"* && "$OUT" != *"nothing to power off"* && "$PO" == failed ]]; }
run lookup500 'verdict=not_ready\n' 1 failure BBV_LOOKUP_CODE=500
t "an unreadable server lookup is named as failed (never 'nothing to power off'), still returns 1 and comments" "$(lookup_failed_shape; echo $?)"
t "a failed lookup's summary says the power-off FAILED, never that the host was powered off" "$([[ "$SUM" == *"power-off FAILED"* && "$SUM" != *"was powered off"* ]]; echo $?)"
run lookupnoarray 'verdict=not_ready\n' 1 failure BBV_LOOKUP_BODY='{}'
t "a 200 lookup without a servers array is a failed lookup, not an absent server" "$(lookup_failed_shape; echo $?)"
run poweroff500 'verdict=not_ready\n' 1 success BBV_POWEROFF_CODE=500
t "a failed poweroff call is an error naming the manual step, returns 1" "$([[ "$RC" -eq 1 && "$OUT" == *"::error::"*"poweroff"* && "$PO" == failed ]]; echo $?)"
run notoken 'verdict=not_ready\n' 1 success HCLOUD_TOKEN=
t "no HCLOUD_TOKEN: no API call, an error, returns 1" "$([[ "$RC" -eq 1 && -z "$CURL" && "$OUT" == *"HCLOUD_TOKEN"* && "$PO" == failed ]]; echo $?)"
run notready 'verdict=not_ready\n' 1 success
t "the Hetzner token rides the stdin config, never curl's argv" "$([[ "$CFG" == *"hcloudtok123"* ]] && ! grep -q hcloudtok123 "$WORK/notready/curl.log"; echo $?)"
t "the comment carries the run URL" "$([[ "$GH" == *"https://github.com/o/r/actions/runs/1"* ]]; echo $?)"
nogh_shape() { [[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && -z "$GH" && "$OUT" == *"GH_TOKEN is not set"* ]]; }
run nogh 'verdict=not_ready\n' 1 success GH_TOKEN=
t "no GH_TOKEN: the comment is skipped by name, the power-off still happens" "$(nogh_shape; echo $?)"

echo "mutation rows"
MUT=0
mrow() { # <label> <from> <to> <predicate> <case-args...>: the predicate holds on the real library and fails on the mutant
  local label="$1" from="$2" to="$3" pred="$4"; shift 4
  MUT=$((MUT + 1))
  python3 - "$LIB" "$WORK/mut$MUT.sh" "$from" "$to" <<'PY' || { cases=$((cases + 1)); fail "mutation $label did not land"; return; }
import sys
s, d, a, b = sys.argv[1:]
t = open(s).read()
if t.count(a) != 1: sys.exit(1)
open(d, "w").write(t.replace(a, b))
PY
  run "$@"; local before=1; "$pred" && before=0
  LIB_UNDER_TEST="$WORK/mut$MUT.sh" run "$@"; local after=1; "$pred" && after=0
  LIB_UNDER_TEST="$LIB"
  cases=$((cases + 1))
  if [[ "$before" -eq 0 && "$after" -ne 0 ]]; then pass "mutation caught: $label"; else fail "mutation SURVIVED: $label (predicate before=$before after=$after)"; fi
}
mrow "skipped accepted as ready" '[[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]' '[[ ( "$verdicts" == "verdict=ready" || "$verdicts" == "verdict=skipped" ) ]]' not_ready_shape skipped 'verdict=skipped\n' 2 success
mrow "the exit code ignored" '[[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]' '[[ "$verdicts" == "verdict=ready" ]]' not_ready_shape readyrc1 'verdict=ready\n' 1 success
mrow "the poweroff call removed" '"https://api.hetzner.cloud/v1/servers/${_BBV_SERVER_ID}/actions/poweroff"' '"https://api.hetzner.cloud/v1/servers/${_BBV_SERVER_ID}/actions/reboot"' not_ready_shape notready 'verdict=not_ready\n' 1 success
# The two mutants that survived the pre-review suite (PR #12873 test-design review), then the new arms.
mrow "a failed lookup treated as an absent server" '  if [[ "$lrc" -eq 3 ]]; then
    echo "bastion-boot-verify: no soleur-bastion server exists (the apply' '  if [[ "$lrc" -ne 0 ]]; then
    echo "bastion-boot-verify: no soleur-bastion server exists (the apply' lookup_failed_shape lookup500 'verdict=not_ready\n' 1 failure BBV_LOOKUP_CODE=500
mrow "the GH_TOKEN-unset warning deleted" '    echo "::warning::bastion-boot-verify: GH_TOKEN is not set; the run URL was not commented on #12879."' '    :' nogh_shape nogh 'verdict=not_ready\n' 1 success GH_TOKEN=
mrow "a lookup without a servers array read as empty" "'.servers | arrays | length'" "'.servers | length'" lookup_failed_shape lookupnoarray 'verdict=not_ready\n' 1 failure 'BBV_LOOKUP_BODY={}'
mrow "the read not bound to the created server" 'BOOT_TRAIL_HOST_ID="$host_id" BOOT_TRAIL_SINCE="$since" \
        JOB_STATUS="$job_status" DISPATCH_LABEL="$label" bash "$reader" 2>&1 | tee "$tmp"' 'BOOT_TRAIL_HOST_ID="" BOOT_TRAIL_SINCE="$since" \
        JOB_STATUS="$job_status" DISPATCH_LABEL="$label" bash "$reader" 2>&1 | tee "$tmp"' ready_bound_shape ready 'verdict=ready\n' 0 success

echo
MIN_CASES=38
if [[ "$cases" -lt "$MIN_CASES" ]]; then printf 'test-bastion-boot-verify: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2; exit 1; fi
if [[ $((passes + fails)) -ne "$cases" ]]; then printf 'test-bastion-boot-verify: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2; exit 1; fi
if [[ "$fails" -gt 0 ]]; then printf 'test-bastion-boot-verify: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2; exit 1; fi
printf 'test-bastion-boot-verify: PASS (%d assertions, 0 failed)\n' "$cases"
