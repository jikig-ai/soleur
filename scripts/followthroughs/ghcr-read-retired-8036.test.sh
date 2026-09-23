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
[[ "$argv" == *"--limit ${STUB_WANT_LIMIT:-5000}"* ]] || { echo "stub: wrong/missing --limit (argv: $argv)" >&2; exit 64; }
# NEGATIVE PINS over the whole vector. The four checks above are membership tests, and a prefix or
# membership pin structurally cannot express "nothing downstream undoes this". `--no-archive`
# collapses betterstack-query.sh to the hot window (~40 min); leg 2 then asserts "zero
# relogin_failed since earliest" over 40 minutes of a multi-day window and exits 0 on a host that
# emitted them all week. Refuse it stub-side so the regression reds here rather than in production.
[[ "$argv" != *"--no-archive"* ]] || { echo "stub: --no-archive truncates to the hot window; leg 2 grades an absence over the FULL window (argv: $argv)" >&2; exit 64; }
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
# marker_full <swept> <deploy_cfg> <deploy_auth> <deploy_store> <deploy_helper> — drives the three
# tokens leg 1 now grades. `marker` stays the two-arg shorthand for the common present/none case.
marker_full() {
  printf 'SOLEUR_DEPLOY_GHCR_CONFIG effective=deploy_cfg swept=%s deploy_cfg=%s deploy_ghcr_auth=%s deploy_creds_store=%s deploy_ghcr_helper=%s home_cfg=present home_ghcr_auth=inline home_creds_store=none home_ghcr_helper=none root_cfg=present root_ghcr_auth=inline root_creds_store=none root_ghcr_helper=none' \
    "$1" "$2" "$3" "$4" "$5"
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
  elif grep -qF -- "$HA" <<<"$OUT" || grep -qF -- "$HB" <<<"$OUT"; then
    # AC-N2. This stdout is posted VERBATIM into a PUBLIC issue comment by sweep-followthroughs.sh.
    # Machine ids are capped at 12 hex chars; a full 32-hex id reaching the sink is a leak. The
    # fixtures make this free to check — $HA/$HB are the full ids.
    fail "$desc -- AC-N2: a full 32-hex _MACHINE_ID reached stdout"
  elif grep -qE 'canary-helper|creds_store=[a-z-]*helper|STUB_STDERR_SENTINEL' <<<"$OUT"; then
    fail "$desc -- AC-N2: a credential-helper name or query-tool stderr reached stdout"
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

# The `raw` column is a JSON-ENCODED STRING, but a row whose `raw` is already an OBJECT is
# DEGRADED GRACEFULLY rather than refused: `fromjson? // null` on a non-string falls through to
# the value itself. This row pins that tolerance deliberately. (It does NOT assert a refusal —
# an earlier comment here claimed it did, while the case asserted a PASS.) The verify row is
# present so the case grades the DECODE path and not leg 3.
{ jq -cn --arg mid "$HA" --arg ts "$T1" --arg msg "$(marker yes none)" \
    '{dt:"2026-09-02 10:00:00.000000", raw:{SYSLOG_IDENTIFIER:"ci-deploy", _MACHINE_ID:$mid, __REALTIME_TIMESTAMP:$ts, message:$msg}}'
  row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx singleenc)"
run_case "a singly-encoded raw is tolerated, not refused (jq passes the object through) -> PASS" 0 "PASS:" "$(fx singleenc)"

# ── LEG 3 — verify_failed is ACTION REQUIRED, not FAIL: the GHCR read path IS retired on that
#    host, so closing it as a retirement failure would name a cause the probe did not measure.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail verify_failed)"; } > "$(fx leg3)"
run_case "leg 3: latest verdict result=verify_failed -> ACTION REQUIRED (5), not FAIL" 5 "ACTION REQUIRED:" "$(fx leg3)"

# INVERTED 2026-09-23 (#8600 review). This row used to assert that a non-`verify_failed` class
# "is not leg 3's business" and still PASSES, deferring it to #8037. That was wrong twice over:
# #8037 is CLOSED (so its sweeper only evaluates inside a closed-set lookback, as this probe's own
# header records), and `cosign_absent` is the literal this work's evidence records firing 89/89 —
# so the deferral closed #8036 over the very condition the retirement exists to end. Leg 3 is now
# a closed ALLOWLIST (see LEG3_ALLOW_RE); every other class is ACTION REQUIRED.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail cosign_absent)"; } > "$(fx leg3b)"
run_case "leg 3: result=cosign_absent is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3b)"
# ── LEG 3, THE LAUNDERING CASE (#8636 security review). `reused_local_reload` is emitted by
#    `_try_local_cache_reload` on the arm where the registry did NOT serve and cosign was SKIPPED.
#    It was in the allowlist, so a host whose real verdict was `cosign_absent` -- the class this
#    work records firing 89/89 -- graded PASS as soon as a later reload breadcrumb arrived.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail cosign_absent)"; row "$HA" "$T3" "$(verify_fail reused_local_reload)"; } > "$(fx launder)"
run_case "leg 3: a reused_local_reload AFTER cosign_absent does not launder it into a PASS" 5 "ACTION REQUIRED:" "$(fx launder)"
run_case "leg 3: the reload sentence names the last REAL verdict, so it cannot hide it" 5 "last real verdict=cosign_absent" "$(fx launder)"

#    And the weaker form: a host whose ONLY verdict is the reload breadcrumb ran no cosign at all,
#    which the leg's own contract says is ACTION REQUIRED ("markers but NO verdict"). Admitting the
#    breadcrumb made "no verification" indistinguishable from "verification passed".
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail reused_local_reload)"; } > "$(fx reload_only)"
run_case "leg 3: a host whose only verdict is reused_local_reload (cosign never ran) -> ACTION REQUIRED" 5 "ACTION REQUIRED:" "$(fx reload_only)"

# Classes adjacent to the laundering one, so a use-site widening to either is caught too (the
# coverage previously existed only for the class review happened to name).
# ── THE REFUSALS, DRIVEN. All three exit-3 arms were unpinned and unexercised: deleting them
#    left the suite green, and the `verify` kind was missing from the attribution list entirely,
#    so an unattributable `unsigned` was dropped and the host graded PASS.
for _k in marker relogin verify; do
  case "$_k" in
    marker)  _m="$(marker yes none)" ;;
    relogin) _m="$RELOGIN_MSG" ;;
    verify)  _m="$(verify_fail unsigned)" ;;
  esac
  { row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"
    jq -cn --arg ts "$T3" --arg msg "$_m" \
      '{dt:"2026-09-02 10:00:00.000000", raw:({SYSLOG_IDENTIFIER:"ci-deploy", __REALTIME_TIMESTAMP:$ts, message:$msg}|tojson)}'
  } > "$(fx "nomid_$_k")"
  run_case "a ${_k} row with no _MACHINE_ID is REFUSED, never dropped" 3 "CANNOT ESTABLISH:" "$(fx "nomid_$_k")"
done
unset _k _m

# A row with no usable clock, on a graded kind, is refused; an UNGRADED ci-deploy row without one
# must NOT latch the tracker (that scoping bug refused on lines nothing grades).
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"
  jq -cn --arg mid "$HA" --arg msg "$RELOGIN_MSG" \
    '{dt:"", raw:({SYSLOG_IDENTIFIER:"ci-deploy", _MACHINE_ID:$mid, message:$msg}|tojson)}'
} > "$(fx noclock)"
run_case "a graded row with no usable timestamp is REFUSED, never dropped" 3 "CANNOT ESTABLISH:" "$(fx noclock)"
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"
  jq -cn --arg mid "$HA" \
    '{dt:"", raw:({SYSLOG_IDENTIFIER:"ci-deploy", _MACHINE_ID:$mid, message:"IMAGE_VERIFY_MODE=warn selected for this deploy"}|tojson)}'
} > "$(fx noclock_ungraded)"
run_case "an UNGRADED ci-deploy row with no timestamp does not latch the tracker -> PASS" 0 "PASS:" "$(fx noclock_ungraded)"

# An ordering that is UNKNOWN must be refused, not guessed. Both rows fall back to `dt` (second
# granularity) at the same second, so the relogin could be before or after the marker: passing it
# re-opens the fail-open hole, failing it latched a clean host shut (measured - a relogin 0.8s
# EARLIER than the marker was graded FAIL under `>=`).
{ jq -cn --arg mid "$HA" --arg msg "$(marker yes none)" \
    '{dt:"2026-09-02 10:00:00.100000", raw:({SYSLOG_IDENTIFIER:"ci-deploy",_MACHINE_ID:$mid,message:$msg}|tojson)}'
  jq -cn --arg mid "$HA" --arg msg "$RELOGIN_MSG" \
    '{dt:"2026-09-02 10:00:00.900000", raw:({SYSLOG_IDENTIFIER:"ci-deploy",_MACHINE_ID:$mid,message:$msg}|tojson)}'
  row "$HA" "$T3" "$VERIFY_OK"; } > "$(fx ambig)"
run_case "a relogin tying the latest marker at dt second-granularity is REFUSED, not guessed" 3 "CANNOT ESTABLISH:" "$(fx ambig)"

{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail rekor_unreachable)"; } > "$(fx leg3g)"
run_case "leg 3: result=rekor_unreachable is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3g)"
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail inspect_failed)"; } > "$(fx leg3h)"
run_case "leg 3: result=inspect_failed is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3h)"
# A reload verdict must be ACTION REQUIRED with its OWN sentence, never "verification is broken".
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"; row "$HA" "$T3" "$(verify_fail reused_local_reload)"; } > "$(fx leg3i)"
run_case "leg 3: a same-version reload after an ok is ACTION REQUIRED naming the reload, not a broken verifier" 5 "no cosign ran on the latest deploy" "$(fx leg3i)"

{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail unsigned)"; } > "$(fx leg3f)"
run_case "leg 3: result=unsigned is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3f)"
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail wrong_identity)"; } > "$(fx leg3d)"
run_case "leg 3: result=wrong_identity is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3d)"
# A host that ran the new script but emitted NO verify verdict is ACTION REQUIRED with its own
# sentence — a pure-absence PASS is the grading this probe's header rejects for legs 1 and 2, and
# leg 3 was the one leg still doing it.
{ row "$HA" "$T1" "$(marker yes none)"; } > "$(fx leg3e)"
run_case "leg 3: markers but no IMAGE_VERIFY verdict at all is ACTION REQUIRED (5), never PASS" 5 "ACTION REQUIRED:" "$(fx leg3e)"

# ── LEG 2, THE LATCH (regression row for #8600 review). `earliest` is deliberately set to the
#    apply's completion PLUS A MARGIN, because the co-fired release may still run the OLD script —
#    so the window is EXPECTED to contain pre-1c relogin rows. Counting every row since `earliest`
#    pinned leg 2 to fail forever on a host that then retired cleanly: no later deploy could ever
#    clear it, and #8036 could never close. Only rows NEWER than the host's latest marker count.
{ row "$HA" "$T1" "$RELOGIN_MSG"; row "$HA" "$T2" "$(marker yes none)"; row "$HA" "$T3" "$VERIFY_OK"; } > "$(fx latch)"
run_case "leg 2: a relogin_failed BEFORE the host's latest marker is pre-1c residue -> PASS" 0 "PASS:" "$(fx latch)"

# The other side of the same rule: a relogin AFTER the latest marker is the new script logging in,
# which is the regression leg 2 exists to catch. Without this row the fix above would be a way to
# make leg 2 unconditionally green.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$RELOGIN_MSG"; row "$HA" "$T3" "$VERIFY_OK"; } > "$(fx latch2)"
run_case "leg 2: a relogin_failed AFTER the latest marker is a live regression -> FAIL" 1 "FAIL:" "$(fx latch2)"

# ── LEG 1, THE HELPER CARRIER. docker resolves ghcr.io through `credHelpers["ghcr.io"]` with or
#    without an auths entry, so `deploy_ghcr_auth=none deploy_ghcr_helper=set` is still a host
#    presenting a credential. Leg 1 graded only the auths token and passed this.
{ row "$HA" "$T1" "$(marker_full yes present none none set)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx helper)"
run_case "leg 1: deploy_ghcr_helper=set is still a live credential -> FAIL" 1 "FAIL:" "$(fx helper)"

# ── LEG 1, THE FRESH HOST. A ForceNew/recut host has no deploy docker config until its first
#    successful zot login writes one. A file that is not there presents no credential, so this is
#    CLEAN — grading it FAIL made #8036 unclosable on exactly the host class ADR-169 produces.
{ row "$HA" "$T1" "$(marker_full na_absent absent na na na)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx freshhost)"
run_case "leg 1: swept=na_absent (no deploy config yet) is CLEAN -> PASS" 0 "PASS:" "$(fx freshhost)"

# ...but a sweep that could not RUN is not the same state and must still refuse.
{ row "$HA" "$T1" "$(marker_full na_readonly present inline none none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx rocfg)"
run_case "leg 1: swept=na_readonly (sweep could not run) fails CLOSED -> FAIL" 1 "FAIL:" "$(fx rocfg)"

# ...and a sweep that ran but could not VERIFY its own post-state must refuse too, or `swept=`
# goes back to meaning "a removal was attempted".
{ row "$HA" "$T1" "$(marker_full failed present inline none none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx sfail)"
run_case "leg 1: swept=failed (post-state still dirty) -> FAIL" 1 "FAIL:" "$(fx sfail)"

# ── SATURATION. The query keeps the NEWEST rows, so a saturated read has dropped the OLDEST —
#    exactly where a surviving pre-1c relogin sits. Leg 2 grades an ABSENCE, and an absence over a
#    truncated window is not evidence.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx sat)"
run_case "a result set saturated at the limit is TRANSIENT, never a verdict" 2 "TRANSIENT:" "$(fx sat)" SOLEUR_FT_LIMIT=2 STUB_WANT_LIMIT=2

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
# Sits EXACTLY on the suite's count, raised in the same edit that settled it — the sibling
# CI_DEPLOY_ASSERT_FLOOR pays the same price. A floor one below the count is not headroom, it is
# how many assertions can be deleted before the one guard that detects truncation notices.
# CODE SIDE. The pins above fix the PROSE; these assert the grader still does what it says.
# Trailing comments are stripped too: `if [[ "$dauth" == "none" ]]; then ... # was: && "$dhelper"`
# restored the dropped token to a full-line-only strip and left the reverse-direction row green.
GRADER_SRC="$(awk '/^if \[\[ "\$\{1:-\}" == "--explain"/,/^EXPLAIN$/ {next} !/^[[:space:]]*#/ { sub(/[[:space:]]+#.*$/, ""); print }' "$SUT")"

# ── CONTRACT PIN (#8600 -> #8636; the fifth and, deliberately, the smallest).
#    The contract used to exist in FIVE prose copies and drifted from the grader FOUR times. Four
#    guards tried to DETECT that and each leaked -- a tautology; bare-token matching; phrase
#    anchors with hand-enumerated negation lists and unbounded awk slices; and a line-count pin
#    defeated by an embedded newline inside an existing `echo`. Every guard needed a guard, which
#    is the signal that detection was the wrong mechanism.
#
#    So the copies were DELETED. The three legs are stated once as LEG1_CLAIM / LEG2_CLAIM /
#    LEG3_CLAIM and rendered by `--explain` and by every verdict summary; the file header points at
#    `--explain` instead of restating them. Drift is now unrepresentable rather than detected, so
#    all that is left to pin is the three assignments and the fact that the summaries really do
#    render them.
_pin_n=0; _pin_fail=0
_pin_one() {  # <exact line> <what it says>
  _pin_n=$((_pin_n + 1))
  local n; n="$(grep -cxF -- "$1" <<<"$GRADER_SRC" || true)"
  if [[ "$n" != 1 ]]; then fail "contract constant not found exactly once (${n}x) -- $2"; _pin_fail=1; fi
}
# The refusals must be pinned as CODE, not only exercised: they are the only thing standing
# between an absence leg and a silently-dropped row, and deleting all three left the suite at
# 42/34/0. One predicate covers every graded kind, so pin that rather than a list of kinds.
if grep -qF '$3 == "-" { n++ }' <<<"$GRADER_SRC"; then
  pass "the attribution refusal covers every graded kind via one predicate, not a list"
else
  fail "the attribution refusal is gone or was narrowed to a list of kinds - an unlisted kind is dropped silently"
fi
_pin_one "readonly LEG3_ALLOW_RE='ok'" "leg 3 allowlist membership"
_pin_one "readonly LEG1_CLAIM=\"a 'swept=' token AND both carriers clean: deploy_ghcr_auth=none AND deploy_ghcr_helper=none\"" "LEG1_CLAIM"
_pin_one "readonly LEG2_CLAIM=\"zero '\${RELOGIN_LITERAL}' rows NEWER THAN that host's latest marker (not zero rows in the window)\"" "LEG2_CLAIM"
_pin_one "readonly LEG3_CLAIM=\"a latest \${VERIFY_LITERAL} verdict in \${LEG3_ALLOW_HUMAN}\"" "LEG3_CLAIM"
# The tie rule is a claim like the others: rendered into --explain, and reverting it to the
# superseded ">= counts against the pass" wording left the suite green because only the BEHAVIOUR
# was driven, never the sentence describing it.
_pin_one "readonly LEG2_TIE_CLAIM=\"a tie is an UNKNOWN ordering and is REFUSED (exit 3), neither passed nor failed\"" "LEG2_TIE_CLAIM"
[[ "$_pin_fail" == 0 ]] && pass "all $_pin_n contract constants are pinned whole and exactly once"
unset _pin_fail _pin_n

# THE RENDERED OUTPUT, not the source. A source-line count is defeated by an embedded newline --
# measured: moving a "CORRECTION: leg 1 in fact grades the auths token only" line INSIDE an
# existing `echo` string left every line pin and the count green while the public close
# authorisation contradicted itself. Pinning what the probe actually PRINTS closes that, and
# subsumes the count.
_pass_out="$(env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      SOLEUR_FT_EARLIEST="$EARLIEST_ISO" GHCR_RETIRED_8036_BQ="$WORK/stub-query" \
      STUB_ROWS="$(fx pass1)" STUB_WANT_SINCE="$EARLIEST_SQL" bash "$SUT" 2>&1)"
_pass_hdr="$(sed -n '/^PASS:/,/^  host /p' <<<"$_pass_out" | sed '$d')"
_pass_lines="$(grep -c . <<<"$_pass_hdr" || true)"
if [[ "$_pass_lines" != 6 ]]; then
  fail "the PASS verdict block renders $_pass_lines line(s), pinned 6 - a line was added or removed; re-read it against the grader, then re-pin"
elif ! grep -qF -- "$(bash -c 'set -a; source <(grep -E "^readonly LEG1_CLAIM=" "'"$SUT"'"); echo "$LEG1_CLAIM"' 2>/dev/null)" <<<"$_pass_hdr"; then
  fail "the PASS verdict block does not render LEG1_CLAIM - it can state a contract the grader does not implement"
else
  pass "the PASS verdict block renders exactly 6 lines and carries LEG1_CLAIM verbatim"
fi
unset _pass_out _pass_hdr _pass_lines

# FAIL AND ACTION REQUIRED ARE RENDERED SURFACES TOO. Only PASS was pinned, so the FAIL block's
# remediation prose could be INVERTED ("swept=na_absent IS a failure") with the suite green -- the
# exact opposite of `na_absent) [[ "$dcfg" == "absent" ]] && leg1=pass`.
{ row "$HA" "$T1" "$(marker_pre1c inline)"; row "$HA" "$T2" "$VERIFY_OK"; } > "$(fx failblk)"
_render() {  # <fixture> -> stdout+stderr of a full run
  env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      SOLEUR_FT_EARLIEST="$EARLIEST_ISO" GHCR_RETIRED_8036_BQ="$WORK/stub-query" \
      STUB_ROWS="$1" STUB_WANT_SINCE="$EARLIEST_SQL" bash "$SUT" 2>&1 || true
}
# `(readonly )?` -- VERIFY_LITERAL and friends are PLAIN assignments, so a `^readonly` filter
# silently dropped them and the claim resolved with an empty gap that matched nothing.
_claim_of() { bash -c 'set -a; source <(grep -E "^(readonly )?(RELOGIN_LITERAL|VERIFY_LITERAL|MARKER_LITERAL|LEG3_ALLOW_RE|LEG3_ALLOW_HUMAN|'"$1"')=" "'"$SUT"'" 2>/dev/null); echo "${'"$1"'}"' 2>/dev/null; }
for _pair in "failblk:LEG1_CLAIM:FAIL" "leg3:LEG3_CLAIM:ACTION REQUIRED"; do
  _fxn="${_pair%%:*}"; _rest="${_pair#*:}"; _cv="${_rest%%:*}"; _lbl="${_rest#*:}"
  _out="$(_render "$(fx "$_fxn")")"; _cl="$(_claim_of "$_cv")"
  if [[ -z "$_cl" ]]; then
    fail "$_lbl block: could not resolve $_cv - re-point this row"
  elif ! grep -qF -- "$_lbl" <<<"$_out"; then
    fail "$_lbl block did not render at all for its fixture - re-point this row"
  elif ! grep -qF -- "$_cl" <<<"$_out"; then
    fail "the $_lbl verdict block does not render $_cv - it can state a contract the grader does not implement"
  else
    pass "the $_lbl verdict block renders $_cv verbatim"
  fi
done
unset _pair _fxn _rest _cv _lbl _out _cl

# Prove the exclusion FIRED, and that the sentinel is inside the excluded range -- not merely
# absent from GRADER_SRC, which is also true when the sentinel has been moved out of the heredoc.
_hd="$(awk '/^if \[\[ "\$\{1:-\}" == "--explain"/,/^EXPLAIN$/' "$SUT")"
if [[ "$(grep -cF 'PROBE-READY' <<<"$_hd")" != 1 ]]; then
  fail "the PROBE-READY sentinel is not inside the --explain heredoc - the exclusion proof has no anchor"
elif grep -qF 'PROBE-READY' <<<"$GRADER_SRC"; then
  fail "GRADER_SRC still contains the --explain heredoc - the awk range did not fire (tautology)"
elif ! grep -qF 'case "$swept" in' <<<"$GRADER_SRC"; then
  fail "GRADER_SRC lost the grader body - the awk range over-excluded"
else
  pass "GRADER_SRC provably excludes the --explain heredoc and retains the grader"
fi
unset _hd
if [[ "$(grep -cxF "readonly LEG3_ALLOW_RE='ok'" <<<"$GRADER_SRC")" == 1 ]]; then
  pass "leg 3's allowlist is exactly {ok}, pinned on the live assignment"
else
  fail "leg 3's allowlist membership changed - widening it silently weakens signature verification"
fi
if grep -E '"\$dauth" == "none"' <<<"$GRADER_SRC" | grep -q '"\$dhelper" == "none"'; then
  pass "the grader still conjoins both leg-1 carriers"
else
  fail "the grader no longer conjoins deploy_ghcr_auth and deploy_ghcr_helper, which every prose copy claims"
fi
if grep -qF '> (mts[m] + 0)) n++' <<<"$GRADER_SRC"; then
  pass "the fold still scopes leg 2 to rows at-or-after the host's latest marker"
else
  fail "the fold no longer compares against the latest marker - leg 2 is back to a bare window count"
fi
if grep -qF '"$lver" =~ ^($LEG3_ALLOW_RE)$' <<<"$GRADER_SRC"; then
  pass "leg 3 grades via the single-sourced allowlist"
else
  fail "leg 3 no longer reads LEG3_ALLOW_RE - its prose can drift from the grader again"
fi
# --explain must INTERPOLATE the allowlist, not restate it. The two render identically, so only
# perturbation can tell them apart.
_probe='ok|zzprobe'
if sed "s/^readonly LEG3_ALLOW_RE=.*/readonly LEG3_ALLOW_RE='$_probe'/" "$SUT" > "$WORK/sut-probe.sh" \
   && grep -qF "readonly LEG3_ALLOW_RE='$_probe'" "$WORK/sut-probe.sh" \
   && bash "$WORK/sut-probe.sh" --explain 2>/dev/null | grep -qF 'zzprobe'; then
  pass "--explain INTERPOLATES the leg-3 allowlist (single-sourced, not a matching literal)"
else
  fail "--explain hardcodes the leg-3 allowlist, or the probe rewrite did not land"
fi
unset _probe
unset _ex _hdr GRADER_SRC _claim_helper _claim_helper_hdr _claim_postmarker



printf '\n%s assertion(s), %s case(s), %s failure(s)\n' "$checks" "$cases" "$fails"
MIN_CHECKS=52
if [[ "$checks" -lt "$MIN_CHECKS" ]]; then
  printf 'FATAL: only %s assertion(s) ran, expected at least %s — a row was deleted.\n' "$checks" "$MIN_CHECKS" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'FAILED: %s assertion(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK: ghcr-read-retired-8036.sh exit-code contract holds\n'
