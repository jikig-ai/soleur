#!/usr/bin/env bash
# Suite for scripts/lib/bastion-boot-verify.sh (#12866, Phase 4.2).
#
# PROPERTY. The bastion birth is ready ONLY when the strict reader prints exactly one
# `verdict=ready` and exits 0. Every other outcome (not_ready, skipped, no verdict, two verdicts, a
# ready line beside a non-zero exit, an unreadable reader) powers soleur-bastion off through the
# Hetzner API, prints the recovery step, comments the run on #9421 (the open epic, R4), and returns 1, so
# a wrong host never sits running on the private network. A server that existed BEFORE the apply (the
# pre-apply id set, the 4th argument) is never read or powered off, on either route.
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
    [ "${BBV_LOOKUP_CODE:-200}" = 200 ] || { emit "${BBV_LOOKUP_ERRBODY:-{\}}" "$BBV_LOOKUP_CODE"; exit 0; }
    if [ -n "${BBV_LOOKUP_BODY:-}" ]; then emit "$BBV_LOOKUP_BODY" 200
    else emit '{"servers":[{"id":4242,"name":"soleur-bastion"}]}' 200; fi ;;
  "POST https://api.hetzner.cloud/v1/servers/"*"/actions/poweroff")
    emit '{"action":{"id":1,"status":"running"}}' "${BBV_POWEROFF_CODE:-201}" ;;
  "GET https://api.hetzner.cloud/v1/actions/1")
    emit "{\"action\":{\"id\":1,\"status\":\"${BBV_ACTION_STATUS:-success}\"}}" 200 ;;
  *) emit '' 000; exit 7 ;;
esac
STUB
cat > "$BIN/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$BBV_LOG/gh.log"
[ "$1 $2 $3" = "issue comment 9421" ] || exit 9
exit "${BBV_GH_RC:-0}"
STUB
chmod +x "$WORK/reader.sh" "$BIN/curl" "$BIN/gh"

LIB_UNDER_TEST="$LIB"
LABEL_ARG=""   # set for one row to pass bastion_boot_verify's optional 3rd argument
PRE_ARG="__unset__"  # bastion_boot_verify's 4th argument (the pre-apply id set); __unset__ omits it
# run <case> <reader-out> <reader-rc> <apply-outcome> [VAR=value...] -> RC, OUT, PO (poweroff_result),
# SUM (step summary), logs in $WORK/<case>/
run() {
  local name="$1" rout="$2" rrc="$3" apply="$4"; shift 4
  local log="$WORK/$name"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/curl.cfg"; : > "$log/gh.log"; : > "$log/out"; : > "$log/sum"
  RC=0
  OUT="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" BBV_READER_OUT="$rout" BBV_READER_RC="$rrc" \
    BASTION_BOOT_TRAIL="$WORK/reader.sh" HCLOUD_TOKEN=hcloudtok123 GH_TOKEN=ghtok RUN_URL="https://github.com/o/r/actions/runs/1" \
    GITHUB_OUTPUT="$log/out" GITHUB_STEP_SUMMARY="$log/sum" \
    "$@" bash -c 'source "$1" || exit 98; if [[ "$4" == __unset__ ]]; then bastion_boot_verify 1790000000 "$2" ${3:+"$3"}; else bastion_boot_verify 1790000000 "$2" "${3:-bastion-host-create}" "$4"; fi' _ "$LIB_UNDER_TEST" "$apply" "$LABEL_ARG" "$PRE_ARG" 2>&1)" || RC=$?
  CURL="$(cat "$log/curl.log")"; GH="$(cat "$log/gh.log")"; CFG="$(cat "$log/curl.cfg")"; RENV="$(cat "$log/reader.env" 2>/dev/null)"
  PO="$(sed -n 's/^poweroff_result=//p' "$log/out")"; SUM="$(cat "$log/sum")"; CR="$(sed -n 's/^comment_result=//p' "$log/out")"
}
POWEROFF="POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff"
t() { cases=$((cases + 1)); if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "rc=$RC out=$OUT curl=$CURL gh=$GH"; fi; }
not_ready_shape() { [[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && "$GH" == *"issue comment 9421"* && "$OUT" == *"bastion-host-replace"* ]]; }

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
t "not_ready: powers off, comments on #9421, names the recovery, returns 1" "$(not_ready_shape; echo $?)"
t "not_ready: poweroff_result=powered_off and the summary says it was powered off" "$([[ "$PO" == powered_off && "$SUM" == *"was powered off"* ]]; echo $?)"
t "the reader's trail is printed exactly once (streamed, not re-printed)" "$([[ "$(grep -c '^verdict=not_ready$' <<<"$OUT")" -eq 1 ]]; echo $?)"
t "the recovery names the live replace route, never 'not yet available'" "$([[ "$OUT" == *"-f apply_target=bastion-host-replace -f confirm=REPLACE-bastion -f expected_bastion_server_id=4242"* && "$OUT" != *"not yet available"* ]]; echo $?)"
t "the recovery line says a replace destroys the kept disk" "$([[ "$OUT" == *"fix bastion-cloud-init.yml if it is a template fault, then replace (this destroys the kept disk)"* ]]; echo $?)"
t "the create label keeps its own advice (the birth gate refuses a second create)" "$([[ "$OUT" == *"Do not re-run bastion-host-create"* ]]; echo $?)"
t "a posted comment records comment_result=posted" "$([[ "$CR" == posted ]]; echo $?)"
run skipped 'verdict=skipped\n' 2 success
t "skipped (an unread boot) is not ready: powers off and returns 1" "$(not_ready_shape; echo $?)"
run noverdict 'boot-trail: something\n' 0 success
t "no verdict line is not ready, even with exit 0" "$(not_ready_shape; echo $?)"
run twoverdicts 'verdict=ready\nverdict=ready\n' 0 success
t "two verdict lines are not ready" "$(not_ready_shape; echo $?)"
run mixedverdicts 'verdict=not_ready\nverdict=ready\n' 0 success
t "a not_ready verdict beside a ready one is not ready" "$(not_ready_shape; echo $?)"
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
LABEL_ARG=bastion-host-replace PRE_ARG=4343   # the replace label requires the pre-apply id set (#12879)
run replacelabel 'verdict=not_ready\n' 1 success
LABEL_ARG="" PRE_ARG="__unset__"
t "a dispatch label reaches the reader and the comment, and the create-only advice is dropped" \
  "$([[ "$RENV" == *"LABEL=bastion-host-replace"* && "$GH" == *"bastion-host-replace did not reach ready"* && "$OUT" != *"Do not re-run bastion-host-create"* ]]; echo $?)"
# The library's DEFAULT reader path (no override) reaches the real strict reader: an unbound Sentry
# token there is the reader's own named skip, so its strict line in the output proves which file ran.
run defaultreader 'unused' 0 failure BASTION_BOOT_TRAIL=
t "with no BASTION_BOOT_TRAIL the real reader at the default path runs (its strict skip line is printed)" \
  "$([[ "$RC" -eq 1 && "$OUT" == *"boot-trail strict: the Sentry token is not bound (unbound token)"* && "$OUT" == *"verdict=skipped"* ]]; echo $?)"

echo "streaming"
# The library runs with stdout on a REGULAR FILE (an operator's `> log`, not the pipe the rows above
# use). The reader stub prints a trail line, then polls that file for it before printing its verdict:
# `streamed=yes` means the line reached the run log while the reader was still running. The line the
# shell printed before the call must survive (a reopened /dev/fd/N truncates it).
cat > "$WORK/reader-stream.sh" <<'STUB'
#!/usr/bin/env bash
printf 'boot-trail: stage1\n'
s=no
for _ in $(seq 1 50); do grep -qx 'boot-trail: stage1' "$BBV_STDOUT" 2>/dev/null && { s=yes; break; }; sleep 0.1; done
printf '%s\n' "$s" > "$BBV_LOG/streamed"
printf 'verdict=ready\n'
STUB
chmod +x "$WORK/reader-stream.sh"
stream_row() {
  local log="$WORK/stream"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/gh.log"; : > "$log/out"; : > "$log/sum"
  RC=0
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" BBV_STDOUT="$log/stdout" \
    BASTION_BOOT_TRAIL="$WORK/reader-stream.sh" HCLOUD_TOKEN=hcloudtok123 GH_TOKEN=ghtok RUN_URL="https://github.com/o/r/actions/runs/1" \
    GITHUB_OUTPUT="$log/out" GITHUB_STEP_SUMMARY="$log/sum" \
    bash -c 'source "$1" || exit 98; echo BEFORE-CALL; bastion_boot_verify 1790000000 success' _ "$LIB_UNDER_TEST" > "$log/stdout" 2>&1 || RC=$?
  STREAMED="$(cat "$log/streamed" 2>/dev/null)"; OUT="$(tr -d '\000' < "$log/stdout")"; CURL="$(cat "$log/curl.log")"; GH="$(cat "$log/gh.log")"
}
stream_shape() { [[ "$RC" -eq 0 && "$STREAMED" == yes && "$(grep -cx 'BEFORE-CALL' <<<"$OUT")" -eq 1 && "$(grep -cx 'boot-trail: stage1' <<<"$OUT")" -eq 1 && "$OUT" == *"READY"* ]]; }
stream_row
t "the trail reaches a file stdout while the reader runs, once, and the line printed before the call survives" "$(stream_shape; echo $?)"
# srow <label> <from> <to>: stream_shape holds on the real library and fails on the mutant.
srow() {
  local label="$1" from="$2" to="$3"
  MUT=$((MUT + 1))
  python3 - "$LIB" "$WORK/mut$MUT.sh" "$from" "$to" <<'PY2' || { cases=$((cases + 1)); fail "mutation $label did not land"; return; }
import sys
s, d, a, b = sys.argv[1:]
t = open(s).read()
if t.count(a) != 1: sys.exit(1)
open(d, "w").write(t.replace(a, b))
PY2
  stream_row; local before=1; stream_shape && before=0
  LIB_UNDER_TEST="$WORK/mut$MUT.sh" stream_row; local after=1; stream_shape && after=0
  LIB_UNDER_TEST="$LIB"
  cases=$((cases + 1))
  if [[ "$before" -eq 0 && "$after" -ne 0 ]]; then pass "mutation caught: $label"; else fail "mutation SURVIVED: $label (predicate before=$before after=$after)"; fi
}
MUT=0
srow "the trail printed only after the reader ends" 'printf '"'"'%s\n'"'"' "$line" >&"$fd"; printf '"'"'%s\n'"'"' "$line"; done; }
      exit "${PIPESTATUS[0]}")" || rc=$?' 'printf '"'"'%s\n'"'"' "$line"; done; }
      exit "${PIPESTATUS[0]}")" || rc=$?; printf '"'"'%s\n'"'"' "$out"'
srow "the trail teed by reopening /dev/fd/N" '      | { while IFS= read -r line || [[ -n "$line" ]]; do printf '"'"'%s\n'"'"' "$line" >&"$fd"; printf '"'"'%s\n'"'"' "$line"; done; }' '      | tee "/dev/fd/${fd}"'

echo "power-off arm"
run noserver 'verdict=not_ready\n' 1 failure BBV_LOOKUP_BODY='{"servers":[]}'
t "no soleur-bastion server: nothing to power off, still returns 1 and comments" "$([[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"9421"* && "$OUT" == *"no soleur-bastion server"* && "$PO" == absent ]]; echo $?)"
run twoservers 'verdict=not_ready\n' 1 success BBV_LOOKUP_BODY='{"servers":[{"id":4242,"name":"soleur-bastion"},{"id":4343,"name":"soleur-bastion"}]}'
two_servers_shape() { [[ "$RC" -eq 1 && "$CURL" != *POST* && "$OUT" == *"2 servers"* && "$PO" == failed && "$GH" == *"issue comment 9421"*"power-off FAILED"* ]]; }
t "two servers named soleur-bastion: refuses to guess, powers off nothing, returns 1, still comments the failure" "$(two_servers_shape; echo $?)"
lookup_failed_shape() { [[ "$RC" -eq 1 && "$CURL" != *POST* && "$GH" == *"9421"* && "$OUT" == *"server lookup failed"* && "$OUT" != *"nothing to power off"* && "$PO" == failed ]]; }
run lookup500 'verdict=not_ready\n' 1 failure BBV_LOOKUP_CODE=500
t "an unreadable server lookup is named as failed (never 'nothing to power off'), still returns 1 and comments" "$(lookup_failed_shape; echo $?)"
t "a failed lookup's summary says the power-off FAILED, never that the host was powered off" "$([[ "$SUM" == *"power-off FAILED"* && "$SUM" != *"was powered off"* ]]; echo $?)"
run lookupnoarray 'verdict=not_ready\n' 1 failure BBV_LOOKUP_BODY='{}'
t "a 200 lookup without a servers array is a failed lookup, not an absent server" "$(lookup_failed_shape; echo $?)"
run poweroff500 'verdict=not_ready\n' 1 success BBV_POWEROFF_CODE=500
t "a failed poweroff call is an error naming the manual step, returns 1" "$([[ "$RC" -eq 1 && "$OUT" == *"::error::"*"poweroff"* && "$PO" == failed ]]; echo $?)"
poweroff_failed_comment_shape() { [[ "$GH" == *"issue comment 9421"*"the power-off FAILED, soleur-bastion may still be running"* && "$GH" != *"powered off, disk kept"* && "$SUM" == *"power-off FAILED"* ]]; }
t "a failed poweroff: the #9421 comment and the summary say the power-off FAILED" "$(poweroff_failed_comment_shape; echo $?)"
run actionerror 'verdict=not_ready\n' 1 success BBV_ACTION_STATUS=error
t "an accepted poweroff whose action ends in error is a failed power-off, never 'powered off'" "$([[ "$RC" -eq 1 && "$PO" == failed && "$OUT" == *"ended in error"* && "$SUM" == *"power-off FAILED"* ]]; echo $?)"
run notoken 'verdict=not_ready\n' 1 success HCLOUD_TOKEN=
t "no HCLOUD_TOKEN: no API call, an error, returns 1, still comments" "$([[ "$RC" -eq 1 && -z "$CURL" && "$OUT" == *"HCLOUD_TOKEN"* && "$PO" == failed && "$GH" == *"issue comment 9421"* ]]; echo $?)"
run notready 'verdict=not_ready\n' 1 success
t "the Hetzner token rides the stdin config, never curl's argv" "$([[ "$CFG" == *"hcloudtok123"* ]] && ! grep -q hcloudtok123 "$WORK/notready/curl.log"; echo $?)"
t "the comment carries the run URL" "$([[ "$GH" == *"https://github.com/o/r/actions/runs/1"* ]]; echo $?)"
nogh_shape() { [[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && -z "$GH" && "$OUT" == *"GH_TOKEN is not set"* ]]; }
run nogh 'verdict=not_ready\n' 1 success GH_TOKEN=
t "no GH_TOKEN: the comment is skipped by name, the power-off still happens" "$(nogh_shape; echo $?)"

echo "mutation rows"
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
mrow "the GH_TOKEN-unset warning deleted" '    echo "::warning::bastion-boot-verify: GH_TOKEN is not set; the run URL was not commented on #9421."' '    :' nogh_shape nogh 'verdict=not_ready\n' 1 success GH_TOKEN=
mrow "a lookup without a servers array read as empty" "'.servers | arrays | length'" "'.servers | length'" lookup_failed_shape lookupnoarray 'verdict=not_ready\n' 1 failure 'BBV_LOOKUP_BODY={}'
mrow "the read not bound to the created server" 'BOOT_TRAIL_HOST_ID="$host_id"' 'BOOT_TRAIL_HOST_ID=""' ready_bound_shape ready 'verdict=ready\n' 0 success
mrow "the comment claims a power-off that failed" '    *) poweroff_note="the power-off FAILED, soleur-bastion may still be running"' '    *) poweroff_note="soleur-bastion powered off, disk kept"' poweroff_failed_comment_shape poweroff500 'verdict=not_ready\n' 1 success BBV_POWEROFF_CODE=500
mrow "the comment only on a successful power-off" 'if [[ -n "${GH_TOKEN:-}" ]]; then' 'if [[ -n "${GH_TOKEN:-}" && "$_BBV_POWEROFF" == powered_off ]]; then' two_servers_shape twoservers 'verdict=not_ready\n' 1 success 'BBV_LOOKUP_BODY={"servers":[{"id":4242,"name":"soleur-bastion"},{"id":4343,"name":"soleur-bastion"}]}'
mrow "the lookup takes the first of two servers" '  if [[ "$n" -ne 1 ]]; then' '  if [[ "$n" -lt 1 ]]; then' two_servers_shape twoservers 'verdict=not_ready\n' 1 success 'BBV_LOOKUP_BODY={"servers":[{"id":4242,"name":"soleur-bastion"},{"id":4343,"name":"soleur-bastion"}]}'

echo "the replace label (#12879)"
LABEL_ARG=bastion-host-replace PRE_ARG=4343
run replacenr 'verdict=not_ready\n' 1 success
LABEL_ARG="" PRE_ARG="__unset__"
t "replace label, not ready: powers off the new server and prints the ready-to-run replace dispatch for it" \
  "$([[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && "$OUT" == *"gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-replace -f confirm=REPLACE-bastion -f expected_bastion_server_id=4242"* ]]; echo $?)"
t "replace label: never 'not yet available', never 'Do not re-run bastion-host-create'" \
  "$([[ "$OUT" != *"not yet available"* && "$OUT" != *"Do not re-run bastion-host-create"* ]]; echo $?)"
t "replace label: the comment targets #9421 and names the label" "$([[ "$GH" == "issue comment 9421 "*"bastion-host-replace did not reach ready"* ]]; echo $?)"

echo "the pre-apply id set (4th argument; _bbv_poweroff [pre-ids])"
# The API holds only the pre-apply server: an apply that failed before the destroy. It is never touched.
old_untouched_shape() { [[ "$RC" -eq 1 && "$CURL" != *POST* && "$PO" == old_untouched && "$SUM" == *"pre-apply"* && "$SUM" == *"untouched"* && "$GH" == *"untouched"* ]]; }
LABEL_ARG=bastion-host-replace PRE_ARG=4242
run preapplyfail 'verdict=not_ready\n' 1 failure
LABEL_ARG="" PRE_ARG="__unset__"
t "failed-apply path: a pre-apply id is never powered off (poweroff_result=old_untouched, its own summary and comment)" "$(old_untouched_shape; echo $?)"
t "failed-apply path: the old_untouched recovery keeps the same pin" "$([[ "$OUT" == *"expected_bastion_server_id=4242"* ]]; echo $?)"
LABEL_ARG=bastion-host-replace PRE_ARG=4242
run preapplyok 'verdict=ready\n' 0 success
LABEL_ARG="" PRE_ARG="__unset__"
t "a successful apply whose API still shows only the pre-apply id is not ready, and nothing is powered off" \
  "$([[ "$RC" -eq 1 && "$CURL" != *POST* && -z "$RENV" && "$PO" == old_untouched ]]; echo $?)"
# Positive control: a DIFFERENT id that is not ready IS powered off (the curl fake logs the id in the URL).
LABEL_ARG=bastion-host-replace PRE_ARG=4343
run precontrol 'verdict=not_ready\n' 1 failure
LABEL_ARG="" PRE_ARG="__unset__"
t "positive control: a server outside the pre-apply set (4242, set 4343) IS powered off" "$([[ "$RC" -eq 1 && "$CURL" == *"POST https://api.hetzner.cloud/v1/servers/4242/actions/poweroff"* && "$PO" == powered_off ]]; echo $?)"
# Both the old (pre-apply) and the new server exist: only the new one is read and powered off.
BOTH='{"servers":[{"id":4242,"name":"soleur-bastion"},{"id":5555,"name":"soleur-bastion"}]}'
LABEL_ARG=bastion-host-replace PRE_ARG=4242
run preboth 'verdict=not_ready\n' 1 success "BBV_LOOKUP_BODY=$BOTH"
LABEL_ARG="" PRE_ARG="__unset__"
t "old and new both present: the new one (5555) is powered off, the pre-apply one (4242) never" \
  "$([[ "$CURL" == *"POST https://api.hetzner.cloud/v1/servers/5555/actions/poweroff"* && "$CURL" != *"servers/4242/actions"* && "$RENV" == *"HID=5555"* ]]; echo $?)"
LABEL_ARG=bastion-host-replace PRE_ARG=none
run prenone 'verdict=not_ready\n' 1 success
LABEL_ARG="" PRE_ARG="__unset__"
t "an empty set (none, the recovery arm) behaves exactly as today" "$([[ "$RC" -eq 1 && "$CURL" == *"$POWEROFF"* && "$PO" == powered_off ]]; echo $?)"
LABEL_ARG=bastion-host-replace PRE_ARG=""
run premissing 'verdict=not_ready\n' 1 success
LABEL_ARG="" PRE_ARG="__unset__"
refused_shape() { [[ "$RC" -eq 1 && "$CURL" != *POST* && "$PO" == refused_no_preids && "$OUT" == *"pre-apply id set"* ]]; }
t "a missing set on the replace label fails closed (refused_no_preids, nothing powered off)" "$(refused_shape; echo $?)"
LABEL_ARG=bastion-host-replace PRE_ARG="4242;rm"
run premalformed 'verdict=not_ready\n' 1 success
LABEL_ARG="" PRE_ARG="__unset__"
t "a malformed set fails closed (refused_no_preids)" "$(refused_shape; echo $?)"
LABEL_ARG=bastion-host-create PRE_ARG=4242
run precreate 'verdict=not_ready\n' 1 failure
LABEL_ARG="" PRE_ARG="__unset__"
t "the birth route passes the set too: a live bastion that predates a failed birth is never powered off" "$([[ "$CURL" != *POST* && "$PO" == old_untouched ]]; echo $?)"
# The cancel path calls _bbv_poweroff directly.
run_po() { # <case> <args...>: sources the library, calls _bbv_poweroff with the args -> RC OUT CURL POR
  local name="$1"; shift
  local log="$WORK/$name"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/curl.cfg"; : > "$log/gh.log"
  RC=0
  OUT="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" HCLOUD_TOKEN=hcloudtok123 \
    bash -c 'source "$1" || exit 98; shift; _bbv_poweroff "$@"; r=$?; echo "POWEROFF=${_BBV_POWEROFF}"; exit "$r"' _ "$LIB_UNDER_TEST" "$@" 2>&1)" || RC=$?
  CURL="$(cat "$log/curl.log")"; GH=""; POR="$(sed -n 's/^POWEROFF=//p' <<<"$OUT")"
}
run_po cancelpre 4242
t "cancel path: _bbv_poweroff with the pre-apply id never powers it off (old_untouched)" "$([[ "$RC" -eq 0 && "$CURL" != *POST* && "$POR" == old_untouched ]]; echo $?)"
run_po cancelcontrol 4343
t "cancel path control: an id outside the set is powered off" "$([[ "$RC" -eq 0 && "$CURL" == *"$POWEROFF"* && "$POR" == powered_off ]]; echo $?)"
run_po cancelempty ""
t "cancel path: an explicitly empty set refuses (refused_no_preids)" "$([[ "$RC" -ne 0 && "$CURL" != *POST* && "$POR" == refused_no_preids ]]; echo $?)"
run_po cancellegacy
t "cancel path: no argument at all keeps the 2a behaviour (powers off the one soleur-bastion)" "$([[ "$RC" -eq 0 && "$CURL" == *"$POWEROFF"* && "$POR" == powered_off ]]; echo $?)"

echo "comment_result"
run cmtfailed 'verdict=not_ready\n' 1 success BBV_GH_RC=1
t "a failed comment on the create label: comment_result=failed and a ::warning::" "$([[ "$CR" == failed && "$OUT" == *"::warning::bastion-boot-verify: the comment on #9421 FAILED"* ]]; echo $?)"
LABEL_ARG=bastion-host-replace PRE_ARG=4343
run cmtfailedr 'verdict=not_ready\n' 1 success BBV_GH_RC=1
LABEL_ARG="" PRE_ARG="__unset__"
t "a failed comment on the replace label: comment_result=failed and an ::error::" "$([[ "$CR" == failed && "$OUT" == *"::error::bastion-boot-verify: the comment on #9421 FAILED"* ]]; echo $?)"
t "a failed comment: the summary never claims the comment posted" "$([[ "$SUM" != *"commented on #9421"* && "$SUM" == *"did NOT post"* ]]; echo $?)"
run cmtnotoken 'verdict=not_ready\n' 1 success GH_TOKEN=
t "no GH_TOKEN: comment_result=no_token" "$([[ "$CR" == no_token ]]; echo $?)"

echo "_bbv_servers_doc <out-file> (the one Hetzner reader of the replace route)"
run_doc() { # <case> [VAR=value...] -> RC OUT DOC
  local name="$1"; shift
  local log="$WORK/$name"; rm -rf "$log"; mkdir -p "$log"; : > "$log/curl.log"; : > "$log/curl.cfg"
  RC=0
  OUT="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" TMPDIR="$TMPDIR" BBV_LOG="$log" HCLOUD_TOKEN=hcloudtok123 "$@" \
    bash -c 'source "$1" || exit 98; _bbv_servers_doc "$2"' _ "$LIB_UNDER_TEST" "$log/doc.json" 2>&1)" || RC=$?
  DOC="$(cat "$log/doc.json" 2>/dev/null)"; CURL="$(cat "$log/curl.log")"; CFG="$(cat "$log/curl.cfg")"
}
run_doc docok
t "HTTP 200 with a servers array: rc 0 and the document is saved" "$([[ "$RC" -eq 0 && "$DOC" == *'"servers"'* ]]; echo $?)"
t "the token rides bc_curl's stdin config, never argv" "$([[ "$CFG" == *hcloudtok123* && "$CURL" != *hcloudtok123* ]]; echo $?)"
run_doc doc403 BBV_LOOKUP_CODE=403 'BBV_LOOKUP_ERRBODY={"error":{"code":"forbidden","message":"SECRET-BODY-TEXT"}}'
t "HTTP 403: non-zero, names http=403 and .error.code, never the body's message" "$([[ "$RC" -ne 0 && "$OUT" == *"http=403"* && "$OUT" == *"forbidden"* && "$OUT" != *"SECRET-BODY-TEXT"* ]]; echo $?)"
run_doc docnoarray 'BBV_LOOKUP_BODY={"servers":{}}'
t "HTTP 200 with a non-array servers: non-zero (unreadable is not zero)" "$([[ "$RC" -ne 0 && "$OUT" == *"http=200"* ]]; echo $?)"
run_doc docnotoken HCLOUD_TOKEN=
t "no HCLOUD_TOKEN: non-zero and no API call" "$([[ "$RC" -ne 0 && -z "$CURL" ]]; echo $?)"

echo "bastion_birth_readiness <label> (F1)"
RLIB="${ROOT}/scripts/lib/bastion-birth-readiness.sh"
t "the readiness library exists at scripts/lib/bastion-birth-readiness.sh" "$([[ -s "$RLIB" ]]; echo $?)"
GOOD_CI="$WORK/ci-good.yml"; printf 'runcmd:\n  - echo fresh_boot_ready\n  - echo fresh_boot_not_ready_x\n  - echo cloud_init_complete\n' > "$GOOD_CI"
COMMENT_CI="$WORK/ci-comment.yml"; printf 'runcmd:\n  - echo fresh_boot_ready\n  # fresh_boot_not_ready_x only in a comment\n  - echo cloud_init_complete\n' > "$COMMENT_CI"
run_rd() { # <label> <cloud-init> [VAR=value...] -> RC OUT
  local label="$1" ci="$2"; shift 2
  RC=0
  OUT="$(env -i PATH="/usr/bin:/bin" HOME="$WORK" BASTION_CLOUD_INIT="$ci" SENTRY_ACTIONS_RO_TOKEN=sntryu_abc123 "$@" \
    bash -c 'source "$1" || exit 98; bastion_birth_readiness "$2"' _ "$RLIB" "$label" 2>&1)" || RC=$?
}
run_rd bastion-host-replace "$GOOD_CI"
t "readiness passes on a good emitter and a well-formed token" "$([[ "$RC" -eq 0 && "$OUT" == *"PASSED"* ]]; echo $?)"
run_rd bastion-host-replace "$COMMENT_CI"
t "a literal only in a comment is missing: the replace label is HELD" "$([[ "$RC" -ne 0 && "$OUT" == *"bastion-host-replace is HELD"*"fresh_boot_not_ready_"* ]]; echo $?)"
run_rd bastion-host-create "$COMMENT_CI"
t "the create label says bastion-host-create is HELD" "$([[ "$RC" -ne 0 && "$OUT" == *"bastion-host-create is HELD"* && "$OUT" != *"bastion-host-replace"* ]]; echo $?)"
run_rd bastion-host-replace "$GOOD_CI" SENTRY_ACTIONS_RO_TOKEN=
t "an unbound boot-trail token is HELD" "$([[ "$RC" -ne 0 && "$OUT" == *"bastion-host-replace is HELD: SENTRY_ACTIONS_RO_TOKEN is not bound"* ]]; echo $?)"
run_rd bastion-host-replace "$GOOD_CI" 'SENTRY_ACTIONS_RO_TOKEN=bad token!'
t "a malformed boot-trail token is HELD" "$([[ "$RC" -ne 0 && "$OUT" == *"token-shape check"* ]]; echo $?)"
run_rd bastion-host-replace "$WORK/no-such-ci.yml"
t "an unreadable cloud-init is HELD, never a pass" "$([[ "$RC" -ne 0 && "$OUT" == *"is HELD"* ]]; echo $?)"
run_rd 'x;y' "$GOOD_CI"
t "a malformed label is refused" "$([[ "$RC" -ne 0 ]]; echo $?)"

echo "mutation rows (#12879: the pre-apply id set and comment_result)"
LABEL_ARG=bastion-host-replace PRE_ARG=4242
mrow "the pre-apply exclusion dropped from the lookup" '  if [[ -n "$pre" ]]; then
    _BBV_PRE_PRESENT=' '  if false; then
    _BBV_PRE_PRESENT=' old_untouched_shape preapplyfail 'verdict=not_ready\n' 1 failure
LABEL_ARG=bastion-host-replace PRE_ARG=""
mrow "the pre-id check dropped from _bbv_poweroff (the lowest level)" '    if ! _bbv_preids_ok "${1:-}"; then' '    if false; then' refused_shape premissing 'verdict=not_ready\n' 1 success
LABEL_ARG=bastion-host-replace PRE_ARG="__unset__"
mrow "the replace label's required set dropped" '  [[ "$label" == bastion-host-replace && "$pre_given" -eq 0 ]] && pre_given=1' '  :' refused_shape repnoset 'verdict=not_ready\n' 1 success
LABEL_ARG=bastion-host-replace PRE_ARG=4343
cmt_failed_shape() { [[ "$CR" == failed && "$SUM" == *"did NOT post"* ]]; }
mrow "a failed comment recorded as posted" '      _bbv_record_comment failed "- boot-verify: the #9421 comment did NOT post; post the run URL there by hand."' '      _bbv_record_comment posted "- boot-verify: the run URL was commented on #9421."' cmt_failed_shape cmtfailedr 'verdict=not_ready\n' 1 success BBV_GH_RC=1
LABEL_ARG="" PRE_ARG="__unset__"

echo
MIN_CASES=87  # measured 2026-11-28 (#12879: 47 -> 87, the replace label, pre-apply set, comment_result, _bbv_servers_doc and readiness rows)
if [[ "$cases" -lt "$MIN_CASES" ]]; then printf 'test-bastion-boot-verify: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2; exit 1; fi
if [[ $((passes + fails)) -ne "$cases" ]]; then printf 'test-bastion-boot-verify: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2; exit 1; fi
if [[ "$fails" -gt 0 ]]; then printf 'test-bastion-boot-verify: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2; exit 1; fi
printf 'test-bastion-boot-verify: PASS (%d assertions, 0 failed)\n' "$cases"
