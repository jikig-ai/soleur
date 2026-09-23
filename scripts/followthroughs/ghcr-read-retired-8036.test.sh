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
# a closed ALLOWLIST (`ok` | `reused_local_reload`), so every other class is ACTION REQUIRED.
{ row "$HA" "$T1" "$(marker yes none)"; row "$HA" "$T2" "$(verify_fail cosign_absent)"; } > "$(fx leg3b)"
run_case "leg 3: result=cosign_absent is ACTION REQUIRED (5), not a silent PASS" 5 "ACTION REQUIRED:" "$(fx leg3b)"
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
# ── EXPLAIN-vs-CODE DRIFT GUARD (#8600 post-merge; rebuilt after the #8636 review).
#    `--explain`, the file header and the PASS/ACTION summaries are FOUR prose copies of one
#    contract, and all four drifted when the legs were corrected.
#
#    TWO EARLIER VERSIONS OF THIS GUARD WERE VACUOUS, both measured by review:
#      * v1 derived "what the grader uses" from `grep -vE '^[[:space:]]*#' "$SUT"`, but the
#        `--explain` heredoc is not comment-prefixed, so every token the TEXT named was present in
#        that "source" by construction. The left conjunct was always true and the guard was blind
#        in the direction the defect actually ran.
#      * v2 asserted bare TOKENS. `grep -qF ok` matches the word "token"; and a sentence saying
#        "leg 1 does NOT grade deploy_ghcr_helper" satisfies a presence test for that token.
#    So this version asserts the CLAIM with a content anchor (cq-assert-anchor-not-bare-token),
#    and leg 3 is not asserted at all -- its allowlist is SINGLE-SOURCED from LEG3_ALLOW_PAT, which
#    both the grader's `case` arm and the heredoc read, making that drift unrepresentable.
GRADER_SRC="$(awk '/^if \[\[ "\$\{1:-\}" == "--explain"/,/^EXPLAIN$/ {next} !/^[[:space:]]*#/' "$SUT")"
_ex="$("$SUT" --explain 2>&1)"
# The header slice runs to the first executable line, not a hard-coded line count: a line-number
# window silently stops covering the header the moment anything is inserted above it.
_hdr="$(awk '/^[^#]/{exit} {print}' "$SUT")"

# MEMBERSHIP IS PINNED, not just single-sourced. Single-sourcing stops prose and code disagreeing;
# it does nothing about the set being WIDENED. Measured: adding `unsigned` to LEG3_ALLOW_PAT left
# the whole suite green while a host running unsigned images graded PASS. The allowlist is a
# security decision, so changing it must mean deliberately changing this line too.
if grep -qF "readonly LEG3_ALLOW_PAT='ok|reused_local_reload'" "$SUT"; then
  pass "leg 3's allowlist is exactly {ok, reused_local_reload}"
else
  fail "leg 3's allowlist membership changed - widening it silently weakens signature verification"
fi
if grep -qF '"$lver" =~ ^($LEG3_ALLOW_PAT)$' <<<"$GRADER_SRC"; then
  pass "leg 3's allowlist is single-sourced (grader reads LEG3_ALLOW_PAT), so its prose cannot drift"
else
  fail "leg 3's allowlist is no longer single-sourced -- the grader stopped reading LEG3_ALLOW_PAT"
fi
if grep -qF 'case "$swept" in' <<<"$GRADER_SRC" && ! grep -qF 'leg 1  latest' <<<"$GRADER_SRC"; then
  pass "GRADER_SRC isolates the grader (carries the case arm, excludes the --explain body)"
else
  fail "GRADER_SRC extraction is wrong - it must contain the grader and NOT the --explain heredoc"
fi

# CLAIM ANCHORS, not token presence. Each pins a phrase that only a CORRECT description contains,
# in BOTH prose copies, so a negation ("does NOT grade the helper") reds instead of passing.
_claim_helper="AND 'deploy_ghcr_helper=none'"
_claim_helper_hdr="\`deploy_ghcr_auth=none\` AND \`deploy_ghcr_helper=none\`"
_claim_postmarker="NEWER THAN"
grep -qF -- "$_claim_helper" <<<"$_ex" \
  && pass "--explain states leg 1's helper CONJUNCTION, not merely the token" \
  || fail "--explain no longer states leg 1 as auth AND helper"
grep -qF -- "$_claim_helper_hdr" <<<"$_hdr" \
  && pass "the file header states leg 1's helper conjunction" \
  || fail "the file header no longer states leg 1 as auth AND helper"
grep -qF -- "$_claim_postmarker" <<<"$_ex" && grep -qF -- "$_claim_postmarker" <<<"$_hdr" \
  && pass "both prose copies scope leg 2 to rows NEWER THAN the latest marker" \
  || fail "a prose copy describes leg 2 as a bare window count"

# The reverse direction -- prose claiming a check the GRADER dropped. Anchored on the conjunction,
# never on the bare name `dhelper`, which also appears in the read loop and the REPORT string.
if grep -qF -- "$_claim_helper" <<<"$_ex" \
   && ! grep -qE '\$dauth" == "none" *&& *"\$dhelper" == "none"' <<<"$GRADER_SRC"; then
  fail "--explain claims a deploy_ghcr_helper check the grader no longer CONJOINS into leg 1"
else
  pass "--explain's helper claim is backed by the grader's leg-1 conjunction"
fi
if grep -qF -- "$_claim_postmarker" <<<"$_ex" && ! grep -qF 'mts[mid]' <<<"$GRADER_SRC"; then
  fail "--explain claims post-marker scoping the grader's fold does not implement"
else
  pass "--explain's post-marker claim is backed by the grader's fold"
fi
# `na_absent` must be described as a BYPASS, not folded into the conjunction: the grader passes it
# without consulting either carrier token.
grep -qF 'na_absent' <<<"$GRADER_SRC" \
  && { grep -qiE 'na_absent.*(clean|bypass)' <<<"$_ex" \
       && pass "--explain describes swept=na_absent as passing leg 1" \
       || fail "--explain omits that swept=na_absent passes leg 1 without consulting the carriers"; } \
  || fail "guard anchor 'na_absent' is no longer in the grader - re-point this row"

# The retired single-literal framing must be gone from EVERY operator-facing surface, including
# the PASS and ACTION REQUIRED summaries that land in a public issue comment.
if grep -qE "is not 'result=verify_failed'|verdict is result=verify_failed" "$SUT"; then
  fail "a summary or comment still frames leg 3 as the single literal verify_failed"
else
  pass "no surface frames leg 3 as a single-literal test"
fi
unset _ex _hdr GRADER_SRC _claim_helper _claim_helper_hdr _claim_postmarker



printf '\n%s assertion(s), %s case(s), %s failure(s)\n' "$checks" "$cases" "$fails"
MIN_CHECKS=39
if [[ "$checks" -lt "$MIN_CHECKS" ]]; then
  printf 'FATAL: only %s assertion(s) ran, expected at least %s — a row was deleted.\n' "$checks" "$MIN_CHECKS" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'FAILED: %s assertion(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK: ghcr-read-retired-8036.sh exit-code contract holds\n'
