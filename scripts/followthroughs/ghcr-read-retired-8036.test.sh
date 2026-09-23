#!/usr/bin/env bash
# Exit-code harness for ghcr-read-retired-8036.sh (#8036 item 1c: the host-side GHCR read path).
#
# The probe's exit code closes #8036 (0), alarms (1), asks a human (5) or retries (2/3). The
# cardinal sin here is a PURE-ABSENCE pass: the operator's stated criterion was "stage=relogin_failed
# absent", and a host that is down, or that never ran the new script, emits no relogin_failed
# either. Row 1 below is that defect in testable form, and it is the row the plan's Guard 3 names.
#
# FIXTURES ARE PRODUCTION-SHAPED: betterstack-query.sh emits JSONEachRow whose `raw` column is a
# JSON-ENCODED STRING holding the journald JSON (fields SYSLOG_IDENTIFIER, _MACHINE_ID,
# __REALTIME_TIMESTAMP, message). Rows are built with jq so `raw` is genuinely double-encoded, and
# one case asserts that a row which is NOT double-encoded is refused rather than graded.
# Values are synthesized (cq-test-fixtures-synthesized-only): machine ids and timestamps are
# fabricated, and no fixture carries a credential-shaped literal.
#
# THE STUB ASSERTS ITS ARGV: the evidence gate is the server-side `--since`, so a probe that
# dropped it, or stopped asking for one of the three graded markers, goes red here rather than
# silently grading a narrower result set.

export TMPDIR="${TMPDIR:-/var/tmp}"  # a shared /tmp tmpfs under quota must not decide this verdict
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/ghcr-read-retired-8036.sh"
fails=0
checks=0
cases=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }
# INSTRUMENT SELF-TEST: pass() and fail() must each move their counters, or every verdict below
# is unmeasured (a neutered fail() would turn this whole file green).
pass "self-test" >/dev/null; fail "self-test" 2>/dev/null
if [[ "$checks" -ne 2 || "$fails" -ne 1 ]]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not record one pass and one fail" >&2; exit 2
fi
fails=0; checks=0

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

EARLIEST_ISO="2026-09-01T00:00:00Z"
EARLIEST_SQL="2026-09-01 00:00:00"
E_US=1788220800000000            # EARLIEST_ISO in microseconds
T1=$((E_US + 3600000000))        # +1h
T2=$((E_US + 7200000000))        # +2h
T3=$((E_US + 10800000000))       # +3h
T_OLD=$((E_US - 3600000000))     # -1h: before earliest
HA="aaaaaaaaaaaa1111111111111111aaaa"
HB="bbbbbbbbbbbb2222222222222222bbbb"

cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
[[ "$argv" == *"--since ${STUB_WANT_SINCE}"* ]] || { echo "stub: wrong/missing --since (argv: $argv)" >&2; exit 64; }
# All THREE graded markers must be asked for. A probe that grades leg 3 while only fetching the
# first two markers would read "no verify verdict" for every host and pass vacuously.
[[ "$argv" == *"--grep SOLEUR_DEPLOY_GHCR_CONFIG"* ]] || { echo "stub: missing --grep SOLEUR_DEPLOY_GHCR_CONFIG (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--grep relogin_failed"* ]] || { echo "stub: missing --grep relogin_failed (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--grep IMAGE_VERIFY"* ]] || { echo "stub: missing --grep IMAGE_VERIFY (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--limit "* ]] || { echo "stub: missing --limit (argv: $argv)" >&2; exit 64; }
cat "${STUB_ROWS:-/dev/null}"
STUB
chmod +x "$WORK/stub-query"

# row <mid> <ts_us> <message> [identifier] — ONE production-shaped, double-encoded JSONEachRow line.
row() {
  local mid="$1" ts="$2" msg="$3" ident="${4:-ci-deploy}"
  jq -cn --arg mid "$mid" --arg ts "$ts" --arg msg "$msg" --arg id "$ident" \
    '{dt:"2026-09-02 10:00:00.000000",
      raw: ({SYSLOG_IDENTIFIER:$id, _MACHINE_ID:$mid, __REALTIME_TIMESTAMP:$ts,
             host:"soleur-web-platform", host_name:"soleur-web-platform", message:$msg} | tostring)}'
}
# marker <swept> <deploy_auth> [home_auth] — the SOLEUR_DEPLOY_GHCR_CONFIG line, full token set.
# home_ghcr_auth defaults to `inline`: that is the LIVE post-1c reading (the fossil is unreachable
# under ProtectHome=read-only), so every PASS fixture carries it and a probe that started grading
# it would red on its own happy path.
marker() {
  printf 'SOLEUR_DEPLOY_GHCR_CONFIG effective=deploy_cfg swept=%s deploy_cfg=present deploy_ghcr_auth=%s deploy_creds_store=none deploy_ghcr_helper=none home_cfg=present home_ghcr_auth=%s home_creds_store=none home_ghcr_helper=none root_cfg=unreadable root_ghcr_auth=na root_creds_store=na root_ghcr_helper=na' \
    "$1" "$2" "${3:-inline}"
}
# The pre-1c marker: identical EXCEPT that it carries no `swept=` token at all.
marker_pre1c() {
  printf 'SOLEUR_DEPLOY_GHCR_CONFIG effective=deploy_cfg deploy_cfg=present deploy_ghcr_auth=%s deploy_creds_store=none deploy_ghcr_helper=none home_cfg=present home_ghcr_auth=inline home_creds_store=none home_ghcr_helper=none root_cfg=unreadable root_ghcr_auth=na root_creds_store=na root_ghcr_helper=na' "$1"
}
RELOGIN_MSG='PRELUDE: docker login ghcr.io STILL FAILED after Doppler re-fetch (stage=relogin_failed) — private pull may fail-closed'
VERIFY_OK='IMAGE_VERIFY: ok ref=10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:0000000000000000000000000000000000000000000000000000000000000001'
verify_fail() { printf 'IMAGE_VERIFY_FAIL: result=%s ref=10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:00 mode=warn detail=free text' "$1"; }

# run_case <desc> <want-rc> <want-substring> <fixture> [env assignments...]
run_case() {
  local desc="$1" want_rc="$2" want_sub="$3" fx="$4"; shift 4
  cases=$((cases + 1))
  local rc=0
  OUT="$(env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        SOLEUR_FT_EARLIEST="$EARLIEST_ISO" GHCR_RETIRED_8036_BQ="$WORK/stub-query" \
        STUB_ROWS="$fx" STUB_WANT_SINCE="$EARLIEST_SQL" "$@" bash "$SUT" 2>&1)" || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$desc -- rc=$rc want=$want_rc :: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
  elif [[ -n "$want_sub" ]] && ! grep -qF -- "$want_sub" <<<"$OUT"; then
    fail "$desc -- rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
  else
    pass "$desc (exit=$rc)"
  fi
}

fx() { printf '%s/%s.jsonl' "$WORK" "$1"; }

echo "== ghcr-read-retired-8036.sh exit-code harness =="

# ── The happy path, first: without it every RED row below could be produced by a probe that
#    always fails, and nothing here would notice.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx pass1)"
run_case "one host, swept=yes + deploy_ghcr_auth=none + no relogin + verify ok -> PASS" 0 "PASS:" "$(fx pass1)"

# swept=no is a PASS: it means the config ARRIVED clean, which is the steady state from the
# second deploy onward. Grading only `swept=yes` would make the probe pass exactly once per host
# and then FAIL forever — the shape that makes a follow-through un-closable.
{ row "$HA" "$T1" "$(marker no none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx pass2)"
run_case "swept=no (arrived clean on a later deploy) is still a PASS" 0 "PASS:" "$(fx pass2)"

# ── GUARD 3 ROW 1 — the defect the conjunction exists to catch, and the one a pure-absence probe
#    passes: a host that emitted relogin_failed and NO post-sweep marker. Under the operator's
#    criterion as literally stated ("relogin_failed absent") this host FAILS; the trap is the
#    inverse case, so row 1b below carries it.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$RELOGIN_MSG"; } > "$(fx g3r1)"
run_case "G3 row 1: a host emitting stage=relogin_failed -> FAIL (leg 2)" 1 "FAIL:" "$(fx g3r1)"

# 1b: the pure-absence trap itself. This host emitted NO relogin_failed — so the operator's
# criterion, read literally, passes it — but its marker carries no `swept=` token, i.e. it is
# still running the PRE-1c script. A probe graded on absence alone closes #8036 here.
{ row "$HA" "$T1" "$(marker_pre1c none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx g3r1b)"
run_case "G3 row 1b: zero relogin_failed but a pre-1c marker (no swept= token) -> FAIL, not PASS" 1 "FAIL:" "$(fx g3r1b)"

# ── GUARD 3 ROW 2 — `inline` and `na` must both fail leg 1, and `na` for its own reason: it is
#    the jq-absent case, where the sweep could not run AND the probe could not read the config.
{ row "$HA" "$T1" "$(marker yes inline)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx g3r2a)"
run_case "G3 row 2a: latest marker reads deploy_ghcr_auth=inline -> FAIL (leg 1)" 1 "FAIL:" "$(fx g3r2a)"
{ row "$HA" "$T1" "$(marker na na)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx g3r2b)"
run_case "G3 row 2b: deploy_ghcr_auth=na (jq absent) fails CLOSED, never passes" 1 "FAIL:" "$(fx g3r2b)"

# ── GUARD 3 ROW 3 — the probe must not stop at the first host. Compliant first, bad second.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"
  row "$HB" "$T1" "$(marker yes inline)"; row "$HB" "$T2" "$VERIFY_OK"; } > "$(fx g3r3)"
run_case "G3 row 3: compliant host A + non-compliant host B -> FAIL (both graded)" 1 "FAIL:" "$(fx g3r3)"

# ── GUARD 3 ROW 4 (HARNESS, must-RED) — a transport failure must be TRANSIENT, never a numeric
#    verdict. Both shapes: the query tool exits non-zero, and it returns rows that do not decode.
: > "$(fx empty)"
run_case "G3 row 4a: the query tool exits non-zero -> TRANSIENT, never a verdict" 2 "TRANSIENT:" "$(fx empty)" STUB_RC=7
printf '%s\n' 'not json at all' > "$(fx undecodable)"
run_case "G3 row 4b: rows that do not decode as the journald envelope -> CANNOT ESTABLISH" 3 "CANNOT ESTABLISH:" "$(fx undecodable)"

# The `raw` column is a JSON-ENCODED STRING. A row whose `raw` is already an OBJECT is a query
# shape change, not evidence — this asserts the double-encoding is genuinely required.
jq -cn --arg mid "$HA" --arg ts "$T1" --arg msg "$(marker yes none)" \
  '{dt:"2026-09-02 10:00:00.000000", raw:{SYSLOG_IDENTIFIER:"ci-deploy", _MACHINE_ID:$mid, __REALTIME_TIMESTAMP:$ts, message:$msg}}' \
  > "$(fx singleenc)"
run_case "a singly-encoded raw still decodes (jq passes the object through) -> PASS" 0 "PASS:" "$(fx singleenc)"

# ── LEG 3 — verify_failed is ACTION REQUIRED, not FAIL: the GHCR read path IS retired on that
#    host, so closing it as a retirement failure would name a cause the probe did not measure.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail verify_failed)"; } > "$(fx leg3)"
run_case "leg 3: latest verdict result=verify_failed -> ACTION REQUIRED (5), not FAIL" 5 "ACTION REQUIRED:" "$(fx leg3)"

# Another failure class is NOT leg 3's business — only verify_failed is, because that is the class
# a clipped zot auths entry produces. A `cosign_absent` host still passes here (it is #8037's).
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail cosign_absent)"; } > "$(fx leg3b)"
run_case "leg 3: a NON-verify_failed verdict class does not trip this probe -> PASS" 0 "PASS:" "$(fx leg3b)"

# A later `ok` must clear an earlier verify_failed — leg 3 grades the LATEST verdict, or one blip
# would FAIL the tracker forever.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail verify_failed)"; row "$HA" "$T3" "$VERIFY_OK"; } > "$(fx leg3c)"
run_case "leg 3 grades the LATEST verdict: verify_failed then ok -> PASS" 0 "PASS:" "$(fx leg3c)"

# ── FIELD ISOLATION — the one that matters most here. The Better Stack source carries issue and
#    PR bodies verbatim, and THIS TRACKER'S OWN BODY contains the literal `stage=relogin_failed`.
#    A substring match would grade the issue text as fleet evidence and FAIL forever.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"
  row "$HA" "$T3" "issue #8036 body quoting stage=relogin_failed verbatim" "soleur-inngest"; } > "$(fx isolation)"
run_case "a non-ci-deploy row quoting stage=relogin_failed is ignored -> PASS" 0 "PASS:" "$(fx isolation)"

# ── EVIDENCE GATE — rows before earliest cannot grade, and an unset earliest refuses outright.
{ row "$HA" "$T_OLD" "$RELOGIN_MSG"; row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx window)"
run_case "a relogin_failed BEFORE earliest does not grade -> PASS" 0 "PASS:" "$(fx window)"
{
  cases=$((cases + 1)); rc=0
  OUT="$(env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        GHCR_RETIRED_8036_BQ="$WORK/stub-query" STUB_ROWS="$(fx pass1)" STUB_WANT_SINCE="$EARLIEST_SQL" \
        bash "$SUT" 2>&1)" || rc=$?
  if [[ "$rc" -eq 3 ]] && grep -qF 'CANNOT ESTABLISH:' <<<"$OUT"; then
    pass "SOLEUR_FT_EARLIEST unset -> CANNOT ESTABLISH (3), never a verdict"
  else
    fail "unset earliest must be CANNOT ESTABLISH; rc=$rc :: $(head -2 <<<"$OUT" | tr '\n' ' ')"
  fi
}

# ── ZERO HOSTS IS NEVER A PASS. A relogin-only host cannot be graded, and must not vanish.
{ row "$HA" "$T1" "$RELOGIN_MSG"; } > "$(fx relogin_only)"
run_case "a host with relogin_failed and NO marker -> FAIL, reported as ungraded" 1 "ungraded" "$(fx relogin_only)"
{ row "$HA" "$T1" "some unrelated ci-deploy line"; } > "$(fx nomarkers)"
run_case "rows exist but no ci-deploy marker -> TRANSIENT (2), never PASS" 2 "TRANSIENT:" "$(fx nomarkers)"

# ── --explain is the network-free self-description AC-F11 pins.
{
  cases=$((cases + 1)); rc=0
  OUT="$(env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD \
        -u SOLEUR_FT_EARLIEST GHCR_RETIRED_8036_BQ=/nonexistent/no-such-query bash "$SUT" --explain 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qF 'PROBE-READY' <<<"$OUT" && grep -qF 'leg 1' <<<"$OUT"; then
    pass "--explain prints PROBE-READY and the three legs with no creds and no query tool (AC-F11)"
  else
    fail "--explain must exit 0 with PROBE-READY; rc=$rc :: $(head -2 <<<"$OUT" | tr '\n' ' ')"
  fi
}

# ── Anti-vacuity floor. `checks` already excludes the instrument self-test above, which resets
# both counters to 0 after driving pass() and fail() once each — so there is nothing to subtract
# and no second constant to bind. The threshold sits on the line IMMEDIATELY above its `if`:
# guard-vacuity-floor builds its mutant from the `if` plus the CONTIGUOUS simple assignments over
# it, and a constant declared further up would be unbound in that slice and die under `set -u`,
# scoring as a construction failure instead of as the floor firing.
printf '\n%s assertion(s), %s case(s), %s failure(s)\n' "$checks" "$cases" "$fails"
MIN_CHECKS=18
if [[ "$checks" -lt "$MIN_CHECKS" ]]; then
  printf 'FATAL: only %s assertion(s) ran, expected at least %s — a row was deleted.\n' "$checks" "$MIN_CHECKS" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'FAILED: %s assertion(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK: ghcr-read-retired-8036.sh exit-code contract holds\n'
