#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/zot-log-channel-7440.sh (#7440).
#
# WHY A FIXTURE SUITE AT ALL. The probe is INERT UNTIL DISPATCHED: the registry host is
# cloud-init-only, so nothing it asserts can be exercised before a provisioning event. That makes
# every one of its arms a false-green candidate — a probe that can never PASS is indistinguishable
# from one correctly reporting a not-yet, and a probe that always PASSes is indistinguishable from a
# working channel. Only a fixture suite can tell those apart before merge.
#
# THE FIXTURES MODEL THE REAL DOUBLE-ENCODED ClickHouse SHAPE. betterstack-query.sh emits
# JSONEachRow whose `raw` column is itself a JSON *string*, so a row is
# {"dt":"...","raw":"{\"message\":\"...\"}"} — two decode hops. A fixture that skipped the outer
# encoding would let a probe pass that cannot read production. Values are synthesized
# (cq-test-fixtures-synthesized-only); the SHAPE is measured, taken from a live
# betterstack-query.sh row on 2026-08-11.
#
# THE HIGHEST-VALUE CASE IS C9, THE FALSE-GREEN. Its fixture is TODAY'S ACTUAL PRODUCTION STATE: a
# window containing nothing but SOLEUR_ZOT_DISK heartbeat rows whose `zot_last_err` field echoes
# `zotregistry.dev/...`. A bare `--grep zotregistry.dev` returns 53 such rows over 6h right now. If
# the probe PASSes on that fixture it would auto-close its own tracker and flip ADR-184 on an echo
# of the very absence it exists to detect.
#
# Run: bash tests/scripts/test-zot-log-channel-probe.sh

set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/zot-log-channel-7440.sh"

# COUNTERS ARE DERIVED FROM AN EMITTED RECORD, never from two increments (#7444 R6).
# A floor over PASS+FAIL certifies the number of assert CALLS, not that any condition was
# evaluated: moving the increment from the else-branch to the if-branch yields
# "=== N passed, 0 failed ===" at rc=0 with N literal "FAIL:" lines on screen, and the
# fully count-preserving form (never evaluate $cond, just increment PASS) does the same.
# Both are one-token edits. Deriving each verdict from a line appended at decision time
# makes the count a function of what actually happened.
RESULTS="$(mktemp)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then printf 'PASS\n' >> "$RESULTS"; echo "  PASS: $desc"
  else printf 'FAIL\n' >> "$RESULTS"; echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}
_tally() { PASS=$(grep -cx PASS "$RESULTS" || true); FAIL=$(grep -cx FAIL "$RESULTS" || true); }

# HARNESS CANARY. Verifies the instrument before trusting any verdict it produces: one
# assertion that MUST fail and one that MUST pass, both required to register, then the
# record is reset. Without this, a neutered assert() is indistinguishable from a clean run.
assert "canary: a false condition MUST register as FAIL" "false"
assert "canary: a true condition MUST register as PASS"  "true"
_tally
if [[ "$FAIL" -ne 1 || "$PASS" -ne 1 ]]; then
  echo "FATAL: harness canary did not register (PASS=$PASS FAIL=$FAIL) — assert() is neutered;" >&2
  echo "       every verdict from this run would be meaningless." >&2
  exit 2
fi
: > "$RESULTS"
CANARY_OK=1
echo "  [canary ok] assert() registers both verdicts"

# The floor + gate run from an EXIT trap declared HERE, not at EOF (#7444 R7). At EOF they are
# deleted by the very tail-truncation they exist to detect: cutting the suite from T5 onward
# removed the floor, the gate and the summary line, and the runner saw only rc=0.
_final_gate() {
  local rc=$?
  [[ "$rc" -eq 2 ]] && return   # FATAL paths already reported
  # The canary must be LOAD-BEARING, not merely present: without this check, deleting the
  # canary block is itself an undetected mutation that re-opens the count-preserving
  # assert() neutering the canary exists to catch. Measured — M4 in the battery.
  if [[ "${CANARY_OK:-0}" != "1" ]]; then
    echo "  FAIL: harness canary did not run — assert() is unverified for this whole run" >&2
    echo ""; echo "=== 0 passed, 1 failed ==="
    rm -f "$RESULTS"; rm -rf "$TMP"; exit 1
  fi
  _tally
  local ran=$(( PASS + FAIL ))
  if [[ "$ran" -lt "95" ]]; then
    FAIL=$(( FAIL + 1 ))
    echo "  FAIL: assertion floor — ran $ran assertions, expected >= 95"
    echo "        (suite truncated, or assert() neutered — this run certified nothing)"
  fi
  echo ""
  echo "=== $PASS passed, $FAIL failed ==="
  rm -f "$RESULTS"; rm -rf "$TMP"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
}

TMP="$(mktemp -d)" || { echo "FATAL: mktemp -d failed (TMPDIR=$TMPDIR)" >&2; exit 2; }
# ONE trap: bash keeps only the LAST handler per signal, so a second
# `trap ... EXIT` line would silently discard the gate. Cleanup happens
# inside _final_gate, before it exits.
trap '_final_gate' EXIT

echo "=== zot log-channel probe (#7440) fixture tests ==="
assert "the probe exists" "[[ -f '$PROBE' ]]"

BASELINE_BOOT="bc135d5b-d509-41c4-8129-9181421e845c"
DRIFTED_BOOT="ffffffff-1111-2222-3333-444444444444"
FOREIGN_BOOT="aaaaaaaa-0000-0000-0000-000000000000"
HOSTV="soleur-registry"
ENV_PREFIX_LITERAL="SOLEUR_ZOT_LOG shipper=zot-log-shipper host="

# `dt` IS THE BOUNDARY KEY the probe now scopes on (#8278): the graded set is the newest real
# boot's span, so fixtures must be able to place rows at chosen ingest times. dt is the only
# field the producer cannot set — it is what binds rows to a boot when the envelope carries no
# boot_id of its own.
DT0="2026-08-11 10:00:00.000000"

# Wrap a bare message in the real two-layer encoding: the inner object is JSON-encoded into a
# string, which becomes the `raw` column of the outer object. $2 is the optional ingest dt.
row() { jq -cn --arg dt "${2:-$DT0}" --arg m "$1" '{dt:$dt, raw:({message:$m}|tostring)}'; }

ZOTLINE='level:info,message:HTTP API,module:http,component:session,clientIP:10.0.1.30:39330,method:GET,path:/v2/,statusCode:401,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92'

envelope_row() { row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV $ZOTLINE" "${1:-$DT0}"; }
# A boot marker row on the named boot at a chosen dt. The probe no longer queries it separately:
# in-window markers flow through the SOLEUR_ZOT_LOG arm and tighten the graded boundary to
# ~provision time.
boot_marker_row() { row "SOLEUR_ZOT_LOG_BOOT boot_id=$1 host=$HOSTV shipper_cron=present journald_storage=persistent" "$2"; }
# A foreign-host marker — host-scoped rows from another host must never select the boot.
foreign_marker_row() { row "SOLEUR_ZOT_LOG_BOOT boot_id=$1 host=some-other-host shipper_cron=present" "$2"; }
# SOLEUR_ZOT_LOG_DROPPED carries boot_id but NO host= — it corroborates and counts on a boot
# already derived, but must never SELECT the boot or the boundary.
dropped_row() { row "SOLEUR_ZOT_LOG_DROPPED n=4 interval_s=300 boot_id=$1 seq=9 cum=57 reason=rate_cap" "$2"; }
# A control row from the reporter THIS CHANGE SHIPS — it carries the log_shipper_* fields, whose
# presence is the probe's delivery discriminator (#7444 F-7).
control_row() {
  local boot="$1" postfail="${2:-0}" dt="${3:-$DT0}"
  row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$boot log_shipper_post_fail=$postfail log_shipper_last_ok_age_s=42 log_shipper_dropped_cum=0 log_shipper_drop_seq=0 host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92,func:zotregistry.dev/}" "$dt"
}

# A control row whose shipper has NEVER completed a tick: last_ok_age_s is the literal -1 the
# reporter emits when no row has ever shipped. Distinct from control_row_predelivery, which has no
# log_shipper_* fields AT ALL — that difference is the whole point of C3g.
# $2 = zot_uptime_s, carried only so a case can prove the probe does NOT read it as host age:
# it is the zot CONTAINER's current-run age, so under a restart loop it is permanently small.
# -1 is the reporter's DEFAULT on an unreadable state file, so it is ALSO what a permanently dead
# shipper emits. No field here separates "born four minutes ago" from "dead for a week", which is
# why the ACT framing is never suppressed and the first-tick note is additive.
control_row_never_ticked() {
  local boot="$1" uptime="${2:-240}" dt="${3:-$DT0}"
  row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running zot_uptime_s=$uptime boot_id=$boot log_shipper_post_fail=unknown log_shipper_last_ok_age_s=-1 log_shipper_dropped_cum=unknown log_shipper_drop_seq=unknown host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92,func:zotregistry.dev/}" "$dt"
}

# A control row from the reporter running on the host TODAY, i.e. BEFORE this change is delivered.
# It has no log_shipper_* fields at all, because the reporter that emits them ships with the
# shipper. This is what makes "not delivered" a POSITIVE, measured observation rather than an
# inference from boot_id, which drifts on every self-reboot without any provisioning happening.
control_row_predelivery() {
  local boot="$1" dt="${2:-$DT0}"
  row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$boot host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92,func:zotregistry.dev/}" "$dt"
}

# The query stub dispatches on --grep, which is what makes per-case fixtures possible. It VALIDATES
# argv and exits 64 on a missing required flag: a stub that answers regardless of its arguments puts
# the fixture seam ABOVE the code under test, so the probe could query the wrong window, drop
# --no-archive, or lose its --grep entirely and still pass every case here.
STUB="$TMP/query-stub.sh"
cat > "$STUB" <<'EOS'
#!/usr/bin/env bash
grep_arg=""; since=""; has_noarchive=0; prev=""
for a in "$@"; do
  case "$a" in --no-archive) has_noarchive=1 ;; esac
  [[ "$prev" == "--grep"  ]] && grep_arg="$a"
  [[ "$prev" == "--since" ]] && since="$a"
  prev="$a"
done
printf 'grep=%s since=%s noarchive=%s\n' "$grep_arg" "$since" "$has_noarchive" >> "$STUB_QCALLS"
[[ -n "$grep_arg" ]] || { echo "stub: no --grep" >&2; exit 64; }
[[ -n "$since"    ]] || { echo "stub: no --since" >&2; exit 64; }
if [[ -n "${STUB_QUERY_RC:-}" && "${STUB_QUERY_RC}" != 0 ]]; then
  # Emit on STDERR the way betterstack-query.sh does. Without this the rc=3 credential message
  # cannot be asserted at all, and `2>/dev/null` in the probe stays invisible.
  echo "betterstack-query.sh: credentials not injected (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD)" >&2
  exit "$STUB_QUERY_RC"
fi
# The probe no longer queries the boot marker on a separate 72h archive window (#8278): the
# split-span query was the defect — delivery evidence came from a different span than the rows
# being graded. In-window SOLEUR_ZOT_LOG_BOOT / _DROPPED rows now arrive through the SAME
# SOLEUR_ZOT_LOG result set as the envelope rows (the warehouse LIKE is a substring match), so
# there is exactly one LOG arm here and no separate boot dispatch to model.
case "$grep_arg" in
  SOLEUR_ZOT_LOG)  [[ -r "${STUB_LOG_ROWS:-/nonexistent}"     ]] && cat "$STUB_LOG_ROWS" ;;
  SOLEUR_ZOT_DISK) [[ -r "${STUB_CONTROL_ROWS:-/nonexistent}" ]] && cat "$STUB_CONTROL_ROWS" ;;
esac
exit 0
EOS
chmod +x "$STUB"

# Run the probe for one case. Returns rc in CASE_RC and combined output in CASE_OUT.
run_probe() {
  local logrows="$1" controlrows="$2"; shift 2
  STUB_QCALLS="$TMP/qcalls.$RANDOM"; : > "$STUB_QCALLS"
  CASE_RC=0
  CASE_OUT=$(env PATH="/usr/bin:/bin" \
    BETTERSTACK_QUERY_HOST="synthetic.example.invalid" \
    BETTERSTACK_QUERY_USERNAME="synthetic-user" \
    BETTERSTACK_QUERY_PASSWORD="synthetic-not-a-real-secret" \
    ZOT_LOG_7440_QUERY_BIN="$STUB" \
    ZOT_LOG_7440_HOST="$HOSTV" \
    ZOT_LOG_7440_NOW="$(date -u -d "$DT0" +%s)" \
    STUB_LOG_ROWS="$logrows" STUB_CONTROL_ROWS="$controlrows" STUB_QCALLS="$STUB_QCALLS" \
    "$@" \
    timeout 60 bash "$PROBE" 2>&1) || CASE_RC=$?
  LAST_QCALLS="$STUB_QCALLS"
}

EMPTY="$TMP/empty"; : > "$EMPTY"

# --- C1: PASS-ARM REACHABILITY ------------------------------------------------------------
# Without this, "never emits exit 1" is satisfiable by a probe that can never pass at all.
# 30 envelope rows == the computed expectation for a 30-minute window at the 60s liveness cadence.
# The control row sits 30 minutes back so the bounded span (B0 -> newest row) is a full window
# and the floor reads the same ~30-row expectation it computed before the boot-scoping fix.
C1_LOG="$TMP/c1.log"; : > "$C1_LOG"
for _ in $(seq 1 30); do envelope_row >> "$C1_LOG"; done
C1_CTL="$TMP/c1.ctl"; control_row "$DRIFTED_BOOT" 0 "2026-08-11 09:30:00.000000" > "$C1_CTL"
run_probe "$C1_LOG" "$C1_CTL"
assert "C1 control+envelope present -> exit 0 (the PASS arm is REACHABLE)" "[[ '$CASE_RC' -eq 0 ]]"
assert "C1 PASS output states the envelope and control counts" \
  "grep -qE 'PASS: envelope rows observed \(envelope=30 control=1' <<<\"\$CASE_OUT\""
assert "C1 PASS output prints the four evidence-class counts so the verdict is auditable" \
  "grep -q 'gc_start=' <<<\"\$CASE_OUT\" && grep -q 'gc_done=' <<<\"\$CASE_OUT\" && grep -q 'gc_blobs=' <<<\"\$CASE_OUT\" && grep -q 'patch_upload=' <<<\"\$CASE_OUT\""
assert "C1 the probe queried with --no-archive (30m window is inside the ~40m hot keyhole)" \
  "grep -q 'noarchive=1' '$LAST_QCALLS'"
assert "C1 the probe queried the 30m window" "grep -q 'since=30m' '$LAST_QCALLS'"

# --- C2: not_delivered — no boot marker, boot_id still the pre-delivery baseline -----------
C2_CTL="$TMP/c2.ctl"; control_row_predelivery "$BASELINE_BOOT" > "$C2_CTL"
run_probe "$EMPTY" "$C2_CTL"
assert "C2 zero envelope + baseline boot_id -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C2 reason=not_delivered" "grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""
# Post-delivery (2026-08-12, #7455) this arm is reachable only through a REGRESSION, so the advice
# inverted: it must tell the operator to investigate, not to wait. The old assertion pinned
# 'expected steady state' — a green test locking in an instruction that is now wrong, and one the
# sweeper republishes verbatim as a public issue comment on every tick.
assert "C2 says INVESTIGATE, not wait (post-delivery this arm is a regression)" \
  "grep -qi 'REGRESSION, NOT A NOT-YET' <<<\"\$CASE_OUT\" && grep -qi 'Next: INVESTIGATE' <<<\"\$CASE_OUT\""

# --- C3: delivered_but_silent — reporter carries log_shipper_* fields, zero envelope rows --
# This is the state that separates ACT from WAIT, and collapsing it into 'not delivered' is the
# defect this case exists to prevent.
C3_CTL="$TMP/c3.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C3_CTL"
run_probe "$EMPTY" "$C3_CTL"
assert "C3 shipper fields present + zero envelope -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C3 reason=delivered_but_silent (NOT collapsed into not_delivered)" \
  "grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "C3 does NOT also claim not_delivered" "! grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""

# --- C3d: BOOT_ID DRIFT ALONE IS NOT A PROVISIONING EVENT (#7444 F-7) ---------------------
# THE REPRODUCED DEFECT. The private-NIC guard calls `reboot` as a convergence primitive and
# cloud-init's runcmd is per-instance, so a plain reboot of the CURRENT, UN-REPLACED host drifts
# boot_id while delivering nothing. Keyed on drift, that flipped delivered=1 ->
# reason=delivered_but_silent -> "ACT, NOT WAIT" and started the 90-day escalation clock against a
# host that was never replaced.
#
# The fixture is exactly that state: a DRIFTED boot_id on a PRE-DELIVERY reporter row. The verdict
# must be not_delivered, because the log_shipper_* fields — which only the new cloud-init emits —
# are absent.
C3D_CTL="$TMP/c3d.ctl"; control_row_predelivery "$DRIFTED_BOOT" > "$C3D_CTL"
run_probe "$EMPTY" "$C3D_CTL"
assert "C3d drifted boot_id WITHOUT shipper fields -> not_delivered (drift is not evidence)" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""
assert "C3d it does NOT claim delivered_but_silent (that would start the escalation clock)" \
  "! grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""

# --- C3e: log_shipper_post_fail=unknown is its OWN sub-state, never a zero -----------------
# The reporter emits `unknown` when the shipper's state file is unreadable. A `[0-9]+` extraction
# cannot match it, so it silently read as "no POST failures" — reporting an absence the probe
# never measured, and naming the INVERTED root cause (jq missing => 100% silent loss => state
# never written => `unknown`).
C3E_CTL="$TMP/c3e.ctl"; control_row "$DRIFTED_BOOT" "unknown" > "$C3E_CTL"
run_probe "$EMPTY" "$C3E_CTL"
assert "C3e an 'unknown' post_fail still counts as DELIVERED (the field's presence is the proof)" \
  "grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "C3e it is reported as shipper_state_unreadable, not as 'no POST failures'" \
  "grep -q 'reason=shipper_state_unreadable' <<<\"\$CASE_OUT\""
assert "C3e it does NOT claim the reporter saw no POST failures" \
  "! grep -q 'reports no POST failures' <<<\"\$CASE_OUT\""

# --- C3b: same state reached via the BOOT MARKER rather than boot_id drift -----------------
# The marker now arrives in-window through the LOG arm, not a separate query. Given a dt NEWER
# than the pre-delivery control row, it selects the newest boot itself — it is host-scoped AND
# stamped, which is exactly what qualifies a row to choose the evidence base — and delivery then
# keys on it.
C3B_LOG="$TMP/c3b.log"
boot_marker_row "$DRIFTED_BOOT" "2026-08-11 10:01:00.000000" > "$C3B_LOG"
run_probe "$C3B_LOG" "$C2_CTL"
assert "C3b a boot marker with zero envelope rows -> delivered_but_silent" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "C3b the boot marker alone does not count as an envelope row" \
  "! grep -q 'PASS:' <<<\"\$CASE_OUT\""

# --- C3c: shipper_post_failing — the reporter's INDEPENDENT path names the cause -----------
C3C_CTL="$TMP/c3c.ctl"; control_row "$DRIFTED_BOOT" 17 > "$C3C_CTL"
run_probe "$EMPTY" "$C3C_CTL"
assert "C3c a non-zero log_shipper_post_fail is surfaced as shipper_post_failing" \
  "grep -q 'reason=shipper_post_failing' <<<\"\$CASE_OUT\""
assert "C3c the reported counter value comes from the reporter's own line" \
  "grep -q 'log_shipper_post_fail=17' <<<\"\$CASE_OUT\""

# --- C3f-C3j: FIRST-TICK SOFTENING + STALE-ARM + rc=3 (#7456) ------------------------------
# Measured 2026-08-12: the host was replaced at 20:54:12Z, this probe said delivered_but_silent
# ("ACT, NOT WAIT") at 20:56:32Z, and PASSed unassisted at 20:58:45Z. The shipper is a 4-59/5 cron
# one-shot, so a host born at 20:54 has its first tick at 20:59 — the escalation fired against a
# host that had simply never run one. The softening reads the LITERAL -1 the reporter already
# emits; the softening needs no host-age clock of its own (the probe does carry dt for the
# boundary and a wall-clock for producer freshness — but the -1 gate deliberately reads neither).
C3F_CTL="$TMP/c3f.ctl"; control_row_never_ticked "$DRIFTED_BOOT" > "$C3F_CTL"
run_probe "$EMPTY" "$C3F_CTL"
assert "C3f last_ok_age_s=-1 still exits 2 (softening is not a pass)" "[[ '$CASE_RC' -eq 2 ]]"
assert "C3f the ACT framing is NEVER suppressed, even on a never-ticked shipper" \
  "grep -q 'ACT, NOT WAIT' <<<\"\$CASE_OUT\""
assert "C3f a never-ticked shipper additionally gets the first-tick note" \
  "grep -q 'rule out a first tick' <<<\"\$CASE_OUT\""

# C3f2: THE BOUND. Same never-ticked pair, but the host has been up for hours. `-1` is the
# reporter's DEFAULT on an unreadable state file, so this is ALSO the permanently-dead-shipper
# signature (jq off PATH -> shipper exits 1 -> state never written). Without the uptime bound the
# sweeper would post the reassuring "expected until its first tick" line every day, forever, and
# nothing would escalate.
C3F2_CTL="$TMP/c3f2.ctl"; control_row_never_ticked "$DRIFTED_BOOT" 86400 > "$C3F2_CTL"
run_probe "$EMPTY" "$C3F2_CTL"
assert "C3f2 a never-ticked shipper on an OLD host is told to ACT, not to wait" \
  "grep -q 'ACT, NOT WAIT' <<<\"\$CASE_OUT\""
assert "C3f2 uptime is NOT used as host age (zot_uptime_s is container-run age)" \
  "! grep -q 'zot_uptime_s=' <<<\"\$CASE_OUT\""

# C3f3: absence is not youth. A missing zot_uptime_s must not suppress the ACT framing — the
# row DOES carry last_ok_age_s=-1, so the additive first-tick note is expected too; the axis is
# that a field the probe does not read cannot soften or harden the verdict.
C3F3_CTL="$TMP/c3f3.ctl"
row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$DRIFTED_BOOT log_shipper_post_fail=unknown log_shipper_last_ok_age_s=-1 host=$HOSTV" > "$C3F3_CTL"
run_probe "$EMPTY" "$C3F3_CTL"
assert "C3f3 an absent zot_uptime_s leaves both the ACT framing AND the first-tick note" \
  "grep -q 'ACT, NOT WAIT' <<<\"\$CASE_OUT\" && grep -q 'rule out a first tick' <<<\"\$CASE_OUT\""

# C3g: THE REGRESSION GUARD. control_row_predelivery has NO log_shipper_* fields; reading absent
# as "never ticked" would soften the arm here and silently weaken the escalation C3b pins.
C3G_LOG="$TMP/c3g.log"
boot_marker_row "$DRIFTED_BOOT" "2026-08-11 10:01:00.000000" > "$C3G_LOG"
run_probe "$C3G_LOG" "$C2_CTL"
assert "C3g an ABSENT last_ok_age_s does NOT soften (absence != the literal -1)" \
  "grep -q 'ACT, NOT WAIT' <<<\"\$CASE_OUT\""

# C3h: a finite age is a delivering shipper with a drifted prefix — the loudest arm, unsoftened.
C3H_CTL="$TMP/c3h.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C3H_CTL"
run_probe "$EMPTY" "$C3H_CTL"
assert "C3h a finite last_ok_age_s gets ACT and NO first-tick note" \
  "grep -q 'ACT, NOT WAIT' <<<\"\$CASE_OUT\" && ! grep -q 'rule out a first tick' <<<\"\$CASE_OUT\""

# C3i: the not_delivered arm sent an operator who had JUST dispatched a replace to wait for step-6
# of an ordered path that closed 2026-08-12T20:39Z, on a host replaced 15 minutes later.
run_probe "$EMPTY" "$C2_CTL"
assert "C3i not_delivered no longer cites an OPEN ordered path" \
  "! grep -qE 'open zot-pin ordered path' <<<\"\$CASE_OUT\""
assert "C3i not_delivered no longer instructs a wait on step-6" \
  "! grep -q 'step-6 registry-host-replace' <<<\"\$CASE_OUT\""

# C3j: rc=3 is betterstack-query.sh's credential guard and the likeliest first-run failure. The
# probe's run_query swallowed it with 2>/dev/null, so the operator's comment said only "exited 3".
run_probe "$EMPTY" "$C2_CTL" STUB_QUERY_RC=3
assert "C3j a query rc is still TRANSIENT" "[[ '$CASE_RC' -eq 2 ]]"
assert "C3j the credential message reaches the operator, not /dev/null" \
  "grep -q 'credentials not injected' <<<\"\$CASE_OUT\""

# --- C4: below_expected_floor -------------------------------------------------------------
C4_LOG="$TMP/c4.log"; : > "$C4_LOG"
for _ in $(seq 1 2); do envelope_row >> "$C4_LOG"; done
run_probe "$C4_LOG" "$C1_CTL"
assert "C4 2 envelope rows against a floor of 7 -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C4 reason=below_expected_floor" "grep -q 'reason=below_expected_floor' <<<\"\$CASE_OUT\""
assert "C4 the expectation and floor are both printed (computed, not asserted)" \
  "grep -qE 'expectation of ~30 and a floor of 7' <<<\"\$CASE_OUT\""

# --- C5: control_missing — envelope present, control absent -------------------------------
# NOT channel_dark: the envelope proves the read path answers, so this masks a SEPARATE incident.
run_probe "$C1_LOG" "$EMPTY"
assert "C5 envelope present + zero control -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C5 reason=control_missing" "grep -q 'reason=control_missing' <<<\"\$CASE_OUT\""
assert "C5 is NOT reported as channel_dark" "! grep -q 'reason=channel_dark' <<<\"\$CASE_OUT\""
assert "C5 names the separate live incident it is masking" \
  "grep -qi 'separate live incident' <<<\"\$CASE_OUT\""

# --- C6: channel_dark — both empty. NEVER 'marker_absent' --------------------------------
run_probe "$EMPTY" "$EMPTY"
assert "C6 zero envelope + zero control -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C6 reason=channel_dark" "grep -q 'reason=channel_dark' <<<\"\$CASE_OUT\""
assert "C6 explicitly refuses to read the silence as an absence" \
  "grep -q 'measured' <<<\"\$CASE_OUT\" && grep -qi 'NOTHING about the channel' <<<\"\$CASE_OUT\""
assert "C6 never says marker_absent" "! grep -q 'marker_absent' <<<\"\$CASE_OUT\""

# --- C7: unset credential gets its OWN reason, not collapsed into not_delivered ------------
C7_RC=0
C7_OUT=$(env PATH="/usr/bin:/bin" \
  BETTERSTACK_QUERY_USERNAME="synthetic-user" BETTERSTACK_QUERY_PASSWORD="synthetic" \
  ZOT_LOG_7440_QUERY_BIN="$STUB" \
  timeout 60 bash "$PROBE" 2>&1) || C7_RC=$?
assert "C7 an unset credential -> exit 2" "[[ '$C7_RC' -eq 2 ]]"
assert "C7 reason=credentials_unset (its OWN distinct reason)" \
  "grep -q 'reason=credentials_unset' <<<\"\$C7_OUT\""
assert "C7 an unprovisioned credential is NOT reported as a delivery state" \
  "! grep -qE 'reason=(not_delivered|delivered_but_silent|channel_dark)' <<<\"\$C7_OUT\""

# --- C7b: a failed query is not an absence -----------------------------------------------
run_probe "$C1_LOG" "$C1_CTL" STUB_QUERY_RC=3
assert "C7b betterstack-query.sh exit 3 (unset creds) -> probe exit 2, not a false absence" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=query_failed' <<<\"\$CASE_OUT\""
run_probe "$C1_LOG" "$C1_CTL" STUB_QUERY_RC=64
assert "C7b betterstack-query.sh exit 64 (unknown flag) -> probe exit 2" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=query_failed' <<<\"\$CASE_OUT\""

# --- C8: the SOLE exit-1 arm — a credential shape in the channel ---------------------------
C8_LOG="$TMP/c8.log"; cat "$C1_LOG" > "$C8_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" >> "$C8_LOG"
run_probe "$C8_LOG" "$C1_CTL"
assert "C8 an unmasked Authorization value -> exit 1 (the sole FAIL arm)" "[[ '$CASE_RC' -eq 1 ]]"
assert "C8 reason=credential_shape_in_channel" \
  "grep -q 'reason=credential_shape_in_channel' <<<\"\$CASE_OUT\""
assert "C8 the leaked VALUE is never echoed (this output is posted to a public issue verbatim)" \
  "! grep -q 'c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA' <<<\"\$CASE_OUT\""
assert "C8 counts are reported instead of values" \
  "grep -q 'unmasked_authorization_rows=1' <<<\"\$CASE_OUT\""
assert "C8 tells the operator to rotate BEFORE fixing the code" \
  "grep -qi 'rotate the affected credential FIRST' <<<\"\$CASE_OUT\""

# C8b: zot's OWN mask and our REDACTED marker must NOT trip the leak arm — otherwise the probe
# FAILs daily on the normal, correct production shape and reopens the tracker every sweep.
C8B_LOG="$TMP/c8b.log"; cat "$C1_LOG" > "$C8B_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[******],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" >> "$C8B_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Authorization:[REDACTED]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" >> "$C8B_LOG"
run_probe "$C8B_LOG" "$C1_CTL"
assert "C8b zot's own ****** mask does NOT trip the leak arm" "[[ '$CASE_RC' -eq 0 ]]"
assert "C8b our REDACTED marker does NOT trip the leak arm" "! grep -q 'reason=credential_shape' <<<\"\$CASE_OUT\""

# C8c: a Doppler-token shape anywhere in a shipped row also trips exit 1.
#
# THE FIXTURE IS ASSEMBLED FROM FRAGMENTS, AND THAT IS NOT COSMETIC. The value is synthesized
# (cq-test-fixtures-synthesized-only) — it is not and never was a real credential — but a synthetic
# value carrying a REAL token SHAPE still matches GitHub's secret-scanning regex, and Push Protection
# rejects the whole push on it (GH013). It scans every commit in the range, so a working-tree fix
# alone is insufficient once the literal has been committed. Splitting immediately after the
# `dp.st.` prefix means no contiguous token literal exists in source, while `$SYNTH_DP_TOKEN`
# reconstitutes the full shape at runtime so the probe's leak regex still has something to match.
# Do NOT "tidy" this back into one string — that re-blocks the push.
DP_PREFIX="dp.st."
SYNTH_DP_TOKEN="${DP_PREFIX}prd.SyNtHeTiCnOtArEaLtOkEnVaLuE1234567890abcd"
C8C_LOG="$TMP/c8c.log"; cat "$C1_LOG" > "$C8C_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:error,message:upstream sync failed url=https://x.invalid/?t=${SYNTH_DP_TOKEN},caller:zotregistry.dev/zot/v2/pkg/api/routes.go:1" >> "$C8C_LOG"
run_probe "$C8C_LOG" "$C1_CTL"
assert "C8c a Doppler service-token shape -> exit 1" \
  "[[ '$CASE_RC' -eq 1 ]] && grep -q 'token_or_hash_shaped_rows=1' <<<\"\$CASE_OUT\""

# --- C15: evidence-class counts key on the PARSED field, like the producer (#7444 R33) ----
# is_cap_exempt matches zerolog's .message; the reader counted the same four literals over the
# WHOLE row, so a header-borne "executing gc" counted downstream even though the producer had
# stopped exempting it. Byte-identical literals, different semantics. One real gc row and one
# header-borne decoy: the count must be 1, not 2.
C15_LOG="$TMP/c15.log"; : > "$C15_LOG"
for _ in $(seq 1 29); do envelope_row >> "$C15_LOG"; done
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV {level:info,message:executing gc,component:gc,caller:zotregistry.dev/zot/v2/pkg/api/x.go:1}" >> "$C15_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV {level:info,message:HTTP API,headers:{User-Agent:[executing gc]},caller:zotregistry.dev/zot/v2/pkg/api/x.go:2}" >> "$C15_LOG"
C15_CTL="$TMP/c15.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C15_CTL"
run_probe "$C15_LOG" "$C15_CTL"
assert "C15 a header-borne 'executing gc' is NOT counted as gc evidence (gc_start=1, not 2)" \
  "grep -qE 'gc_start=1( |\\))' <<<\"\$CASE_OUT\""
assert "C15 the genuine gc row IS counted (non-vacuity: the count is not simply zero)" \
  "! grep -qE 'gc_start=0( |\\))' <<<\"\$CASE_OUT\""

# --- C14: the boot marker flows through the LOG arm; there is NO second query (#8278) ------
# The old arm read the marker out of a separate 72h archive query — a different span than the
# rows being graded, which was the defect this fix removes. In-window marker rows now arrive in
# the same SOLEUR_ZOT_LOG result set, select the boot only when host-scoped and stamped, and
# tighten the graded boundary to ~provision time. Assert (a) delivery via an in-window marker,
# (b) no separate boot-marker query is issued at all, and (c) no 72h window is queried.
C14_LOG="$TMP/c14.log"; boot_marker_row "$DRIFTED_BOOT" "2026-08-11 10:01:00.000000" > "$C14_LOG"
C14_CTL="$TMP/c14.ctl"; control_row_predelivery "$BASELINE_BOOT" > "$C14_CTL"
run_probe "$C14_LOG" "$C14_CTL"
assert "C14 an in-window boot marker counts as delivery on its own boot" \
  "grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "C14 the probe issues NO separate SOLEUR_ZOT_LOG_BOOT query (the split span is gone)" \
  "! grep -q 'grep=SOLEUR_ZOT_LOG_BOOT' '$LAST_QCALLS'"
assert "C14 no query runs on a 72h window (only the one bounded window exists)" \
  "! grep -q 'since=72h' '$LAST_QCALLS'"
assert "C14 exactly TWO queries are issued (one per channel, one span — cardinality, not spelling)" \
  "[[ \$(wc -l < '$LAST_QCALLS') -eq 2 ]]"
assert "C14 every query runs on the same bounded hot window" \
  "! grep -vq 'since=30m noarchive=1' '$LAST_QCALLS'"
# Host isolation: source 2457081 is shared, so a boot marker from ANOTHER host can neither
# select the boot nor count as delivery here.
C14_OTHER="$TMP/c14.other"; foreign_marker_row "$DRIFTED_BOOT" "2026-08-11 10:01:00.000000" > "$C14_OTHER"
run_probe "$C14_OTHER" "$C14_CTL"
assert "C14 a boot marker from a DIFFERENT host does not count as delivery here" \
  "grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""

# --- C13b: THE DISCRIMINATOR MUST BE ANCHORED (#7444 R18) ---------------------------------
# The envelope grep was `grep -F`, which has NO anchor, while the comment above it claimed "a
# fixed prefix at offset 0 … can never sit at offset 0". C9/C9b could not see the difference:
# no fixture in the suite placed the prefix anywhere but offset 0, so anchored and unanchored
# were indistinguishable — one encoding level deeper than the false-green C9 is billed to refuse.
#
# These rows MENTION the envelope mid-line, which is what an ingested PR body, ADR, tracker
# comment or this very file looks like once it reaches the warehouse.
C13B_LOG="$TMP/c13b.log"; : > "$C13B_LOG"
for _ in $(seq 1 30); do
  # ADVERSARIAL: correct in every field the success path reads EXCEPT the offset. It carries the
  # zot-only token too, because without it the probe rejects the row via envelope_without_zot_content
  # and the case passes for a reason that has nothing to do with the anchor — measured, the first
  # version of this fixture did exactly that and the unanchored mutant survived it.
  row "ci-runner: PR #7444 quotes a shipped row: ${ENV_PREFIX_LITERAL}${HOSTV} ${ZOTLINE}" >> "$C13B_LOG"
done
C13B_CTL="$TMP/c13b.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C13B_CTL"
run_probe "$C13B_LOG" "$C13B_CTL"
assert "C13b 30 rows MENTIONING the envelope mid-line do NOT count as delivery" \
  "[[ '$CASE_RC' -ne 0 ]]"
assert "C13b and it does not PASS (a prose mention must never flip ADR-184)" \
  "! grep -q 'PASS:' <<<\"\$CASE_OUT\""
# Non-vacuity in the other direction: the same count of REAL rows must still pass, so this
# fixture cannot be satisfied by a probe that simply rejects everything.
C13B_OK="$TMP/c13b.ok"; : > "$C13B_OK"
for _ in $(seq 1 30); do envelope_row >> "$C13B_OK"; done
run_probe "$C13B_OK" "$C13B_CTL"
assert "C13b non-vacuity: 30 GENUINE offset-0 rows still PASS" "[[ '$CASE_RC' -eq 0 ]]"

# --- C9: THE FALSE-GREEN. The highest-value assertion in this suite -----------------------
# This fixture is TODAY'S PRODUCTION STATE: only heartbeat rows, whose zot_last_err echoes
# zotregistry.dev. A bare `--grep zotregistry.dev` returns 53 of these over 6h right now.
C9_LOG="$TMP/c9.log"; : > "$C9_LOG"
C9_CTL="$TMP/c9.ctl"; : > "$C9_CTL"
for _ in $(seq 1 53); do control_row_predelivery "$BASELINE_BOOT" >> "$C9_CTL"; done
run_probe "$C9_LOG" "$C9_CTL"
assert "C9 FALSE-GREEN REFUSED: a heartbeat-echo-only window does NOT pass" "[[ '$CASE_RC' -ne 0 ]]"
assert "C9 it is reported as not_delivered, not as a live channel" \
  "grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""
assert "C9 53 rows naming zotregistry.dev produced ZERO envelope hits" \
  "! grep -q 'PASS:' <<<\"\$CASE_OUT\""

# C9b: the echo rows fed into the ENVELOPE query too — the sharper form of the same trap. A probe
# grepping `zotregistry.dev` (or `caller:zotregistry.dev`) instead of the anchored envelope would
# count all 53 as genuine and PASS on the exact absence it exists to detect.
run_probe "$C9_CTL" "$C9_CTL"
assert "C9b heartbeat echoes in the envelope result set still yield zero envelope hits" \
  "[[ '$CASE_RC' -ne 0 ]] && ! grep -q 'PASS:' <<<\"\$CASE_OUT\""
assert "C9b and the verdict is a delivery state, never a pass" \
  "grep -qE 'reason=(not_delivered|delivered_but_silent)' <<<\"\$CASE_OUT\""

# --- C10: envelope framing present but no zot content ------------------------------------
C10_LOG="$TMP/c10.log"; : > "$C10_LOG"
for i in $(seq 1 30); do row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV some other unit output line $i" >> "$C10_LOG"; done
run_probe "$C10_LOG" "$C1_CTL"
assert "C10 envelope rows with no zot-only token -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C10 reason=envelope_without_zot_content" \
  "grep -q 'reason=envelope_without_zot_content' <<<\"\$CASE_OUT\""

# --- C11: HOST ISOLATION — another host's envelope must not satisfy this probe ------------
# All hosts multiplex into Logs source 2457081, so this is the only isolation available.
C11_LOG="$TMP/c11.log"; : > "$C11_LOG"
for _ in $(seq 1 30); do row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-web-1 $ZOTLINE" >> "$C11_LOG"; done
run_probe "$C11_LOG" "$C1_CTL"
assert "C11 a DIFFERENT host's envelope rows do not count (shared source, in-message isolation)" \
  "[[ '$CASE_RC' -ne 0 ]]"

# --- S1–S10: BOOT-SPAN SCOPING (#8278) ----------------------------------------------------
# THE DEFECT THESE PIN. The probe used to grade leaks over an unscoped 30-minute window while
# its delivery evidence came from a SEPARATE 72h marker query — a window straddling a replace
# mixed two host generations, so a public FAIL or a close could rest on evidence about a dead
# host. The fix: the newest real boot is derived from host-scoped stamped rows ONLY (control
# rows + SOLEUR_ZOT_LOG_BOOT markers; _DROPPED rows corroborate but never select), the graded
# set is bounded to that boot's span by the ingest-assigned dt column, and every verdict-keyed
# value comes out of ONE awk pass.
DT_0900="2026-08-11 09:00:00.000000"
DT_0930="2026-08-11 09:30:00.000000"
DT_0950="2026-08-11 09:50:00.000000"
DT_0955="2026-08-11 09:55:00.000000"
DT_0956="2026-08-11 09:56:00.000000"
DT_1005="2026-08-11 10:05:00.000000"

# S1: THE STRADDLE. A leak-shaped envelope row BEFORE the boundary is outside the graded set —
# the pre-fix probe would exit 1 on it (evidence about a dead host). Post-fix it must neither
# FAIL (rows outside the newest boot are unattributed) nor silently clean: an ungradeable
# credential shape is CANNOT ESTABLISH with the count named.
S1_LOG="$TMP/s1.log"; : > "$S1_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0900" >> "$S1_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S1_LOG"; done
S1_CTL="$TMP/s1.ctl"; : > "$S1_CTL"
control_row "$DRIFTED_BOOT" 0 "$DT_0950" >> "$S1_CTL"
control_row "$DRIFTED_BOOT" 0 "$DT0" >> "$S1_CTL"
run_probe "$S1_LOG" "$S1_CTL"
assert "S1 a pre-boundary leak row does NOT exit 1 (the dead boot's rows are not graded)" \
  "[[ '$CASE_RC' -ne 1 ]]"
assert "S1 it is exit 3 CANNOT ESTABLISH — never a false FAIL and never a silent clean" \
  "[[ '$CASE_RC' -eq 3 ]]"
assert "S1 the ungraded credential-row count is named in the verdict" \
  "grep -qE 'ungraded_credential_rows=1' <<<\"\$CASE_OUT\""

# S2: a leak-shaped row INSIDE the newest boot's span exits 1 and names the boot it was graded
# against. The boot= token is a Guard Contract requirement, not decoration: without it a FAIL
# says nothing about WHICH host generation leaked.
S2_LOG="$TMP/s2.log"; : > "$S2_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S2_LOG"; done
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0956" >> "$S2_LOG"
run_probe "$S2_LOG" "$S1_CTL"
assert "S2 a post-boundary leak -> exit 1 (the sole FAIL arm, on the graded boot)" \
  "[[ '$CASE_RC' -eq 1 ]]"
assert "S2 reason=credential_shape_in_channel" \
  "grep -q 'reason=credential_shape_in_channel' <<<\"\$CASE_OUT\""
assert "S2 the verdict names the boot it graded (boot=$DRIFTED_BOOT)" \
  "grep -q \"boot=$DRIFTED_BOOT\" <<<\"\$CASE_OUT\""
assert "S2 the leaked VALUE is never echoed (counts-only output discipline)" \
  "! grep -q 'c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA' <<<\"\$CASE_OUT\""

# S3: log_shipper_post_fail on the OLD boot only proves nothing about the NEWEST one. This is
# the same span discipline the issue names, applied to the delivery key: a reporter field from
# the previous host generation is not evidence this boot delivered.
S3_CTL="$TMP/s3.ctl"; : > "$S3_CTL"
control_row "$DRIFTED_BOOT" 0 "$DT_0930" >> "$S3_CTL"
control_row_predelivery "$BASELINE_BOOT" "$DT0" >> "$S3_CTL"
run_probe "$EMPTY" "$S3_CTL"
assert "S3 post_fail present only on the OLDER boot -> not_delivered, never delivered_but_silent" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\" && ! grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""

# S4: THE FORGED TAIL. zot_last_err is free text (attacker-influenced through request headers):
# a tail carrying ` boot_id=` + ` log_shipper_post_fail=` must not select the boot NOR supply
# the proof token — the trusted-head cut holds for both.
S4_CTL="$TMP/s4.ctl"
row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$BASELINE_BOOT host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API} boot_id=$FOREIGN_BOOT log_shipper_post_fail=0 log_shipper_last_ok_age_s=9" "$DT0" > "$S4_CTL"
run_probe "$EMPTY" "$S4_CTL"
assert "S4 a forged tail cannot supply post_fail= (would read delivered_but_silent uncut)" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\" && ! grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "S4 a forged tail cannot select the boot (verdict stays on $BASELINE_BOOT)" \
  "grep -q \"boot=$BASELINE_BOOT\" <<<\"\$CASE_OUT\" && ! grep -q \"boot=$FOREIGN_BOOT\" <<<\"\$CASE_OUT\""

# S5 + S7: NO USABLE boot_id — the 'unknown' /proc-fallback sentinel or no field at all. The
# newest boot cannot be derived, so nothing is gradable: exit 3, never 0/1/2.
S5_CTL="$TMP/s5.ctl"
row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=unknown host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API}" "$DT0" > "$S5_CTL"
S5_LOG="$TMP/s5.log"; : > "$S5_LOG"; for _ in $(seq 1 30); do envelope_row >> "$S5_LOG"; done
run_probe "$S5_LOG" "$S5_CTL"
assert "S5 boot_id=unknown on every stamped row -> exit 3 (it is not an identity)" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'CANNOT ESTABLISH' <<<\"\$CASE_OUT\""
S7_CTL="$TMP/s7.ctl"
row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API}" "$DT0" > "$S7_CTL"
run_probe "$S5_LOG" "$S7_CTL"
assert "S7 boot_id absent from every stamped row -> exit 3 (no boot can be derived)" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'CANNOT ESTABLISH' <<<\"\$CASE_OUT\""

# S6: THE VACUITY GUARD. A pass that emits nothing (or non-integers) must exit 3 — a failed awk
# reading as 'zero rows everywhere' would post verdicts on a measurement that never happened.
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/awk"; chmod +x "$FAKEBIN/awk"
run_probe "$S1_LOG" "$S1_CTL" PATH="$FAKEBIN:/usr/bin:/bin"
assert "S6 an awk that produces NO summary -> exit 3, not a vacuous clean" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'grading pass produced no usable summary' <<<\"$CASE_OUT\""
printf '#!/bin/sh\necho not-a-summary\n' > "$FAKEBIN/awk"; chmod +x "$FAKEBIN/awk"
run_probe "$S1_LOG" "$S1_CTL" PATH="$FAKEBIN:/usr/bin:/bin"
assert "S6 an awk that produces a non-integer summary -> exit 3" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'grading pass produced no usable summary' <<<\"$CASE_OUT\""
rm -f "$FAKEBIN/awk"

# S8: THE MARKER TIGHTENS THE BOUNDARY to ~provision time. With control rows on the boot at
# 10:00 only, the boundary without a marker is 10:00 — a row in the (provision, first-heartbeat)
# gap would go ungraded. An in-window SOLEUR_ZOT_LOG_BOOT marker on the same boot at 09:55 is
# itself a host-scoped stamped row, so it moves B0 back to 09:55 and the gap row IS graded.
S8_LOG="$TMP/s8.log"; : > "$S8_LOG"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0956" >> "$S8_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S8_LOG"; done
boot_marker_row "$DRIFTED_BOOT" "$DT_0955" >> "$S8_LOG"
S8_CTL="$TMP/s8.ctl"; control_row "$DRIFTED_BOOT" 0 "$DT0" > "$S8_CTL"
run_probe "$S8_LOG" "$S8_CTL"
assert "S8 a leak in the marker-tightened gap IS graded -> exit 1" "[[ '$CASE_RC' -eq 1 ]]"
assert "S8 the verdict names the marker's boot" "grep -q \"boot=$DRIFTED_BOOT\" <<<\"\$CASE_OUT\""
# The control: remove the marker and the SAME gap row leaves the graded set (boundary falls
# back to the first stamped row at 10:00) — proving the marker moved B0, not something else.
S8_NOMARK="$TMP/s8nomark.log"; grep -v SOLEUR_ZOT_LOG_BOOT "$S8_LOG" > "$S8_NOMARK"
run_probe "$S8_NOMARK" "$S8_CTL"
assert "S8 without the marker the gap row is pre-boundary -> exit 3, not 1" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'ungraded_credential_rows=1' <<<\"$CASE_OUT\""

# S9: A SOLEUR_ZOT_LOG_DROPPED ROW NEVER SELECTS. It carries boot_id but NO host= (verified in
# cloud-init-registry.yml's ship() call), so it cannot be host-verified. A DROPPED row stamped
# with a NEWER foreign boot_id must leave the ctl-derived boot in place — one unverifiable row
# must not get to choose the evidence base.
S9_LOG="$TMP/s9.log"; dropped_row "$FOREIGN_BOOT" "$DT_1005" > "$S9_LOG"
run_probe "$S9_LOG" "$S8_CTL"
assert "S9 a DROPPED row on a foreign newer boot cannot select the evidence base" \
  "[[ '$CASE_RC' -eq 2 ]] && grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\" && grep -q \"boot=$DRIFTED_BOOT\" <<<\"\$CASE_OUT\""

# S10: rows without stamps are BOUNDED, not dropped (must-PASS). An unstamped envelope row on
# the graded span still grades alongside a stamped DROPPED row on the same boot — delivery
# needs only one same-boot source.
S10_LOG="$TMP/s10.log"; : > "$S10_LOG"
dropped_row "$DRIFTED_BOOT" "$DT_0955" >> "$S10_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S10_LOG"; done
run_probe "$S10_LOG" "$S1_CTL"
assert "S10 an unstamped envelope row on the bounded span still grades -> exit 0" \
  "[[ '$CASE_RC' -eq 0 ]]"
assert "S10 the stamped DROPPED row is counted on the derived boot (dropped_rows=1)" \
  "grep -q 'dropped_rows=1' <<<\"\$CASE_OUT\""

# S11: AN UNANCHORED C-CHANNEL ROW NEVER SELECTS OR BOUNDS. --grep SOLEUR_ZOT_DISK is a
# substring LIKE, so a row that merely CONTAINS the marker — a quoted row, a request-header
# echo — lands in the control channel. Only a message STARTING with "SOLEUR_ZOT_DISK " is a
# reporter row; a mid-line mention carrying host=+boot_id= must not pick the evidence base.
S11_CTL="$TMP/s11.ctl"
control_row "$DRIFTED_BOOT" 0 "$DT_0950" > "$S11_CTL"
row "notice forwarder quoting a row: SOLEUR_ZOT_DISK pcent=9 zot_restarts=0 ping_rc=0 host=$HOSTV boot_id=$FOREIGN_BOOT" "$DT_1005" >> "$S11_CTL"
run_probe "$S8_NOMARK" "$S11_CTL"
assert "S11 a mid-line SOLEUR_ZOT_DISK mention on the newest dt cannot select the boot" \
  "[[ '$CASE_RC' -eq 1 ]] && grep -q \"boot=$DRIFTED_BOOT\" <<<\"\$CASE_OUT\" && ! grep -q \"boot=$FOREIGN_BOOT\" <<<\"\$CASE_OUT\""
# The drag direction: a same-boot mid-line mention EARLY in the window must not pull B0 back
# past the marker — without the anchor it would un-grade a real pre-marker leak into the span.
S11B_LOG="$TMP/s11b.log"
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Accept:[*/*],Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==],User-Agent:[curl/8.5.0]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "2026-08-11 09:40:00.000000" > "$S11B_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S11B_LOG"; done
boot_marker_row "$DRIFTED_BOOT" "$DT_0955" >> "$S11B_LOG"
S11_CTL2="$TMP/s11b.ctl"
control_row "$DRIFTED_BOOT" 0 "$DT0" > "$S11_CTL2"
row "notice forwarder quoting a row: SOLEUR_ZOT_DISK pcent=9 zot_restarts=0 ping_rc=0 host=$HOSTV boot_id=$DRIFTED_BOOT" "$DT_0900" >> "$S11_CTL2"
run_probe "$S11B_LOG" "$S11_CTL2"
assert "S11 a mid-line same-boot mention at an early dt cannot drag B0 before the marker" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'ungraded_credential_rows=1' <<<\"\$CASE_OUT\""

# S12: PRODUCER FRESHNESS. Rows whose newest dt is older than two heartbeat ticks describe a
# host that stopped emitting — residue must never satisfy the floor into a PASS. The seam is
# ZOT_LOG_7440_NOW (pinned to DT0 by run_probe): newest row 09:35 against now=10:00 is 1500s
# stale, over the 600s threshold.
S12_CTL="$TMP/s12.ctl"; control_row "$DRIFTED_BOOT" 0 "$DT_0930" > "$S12_CTL"
S12_LOG="$TMP/s12.log"; : > "$S12_LOG"; for _ in $(seq 1 30); do envelope_row "2026-08-11 09:35:00.000000" >> "$S12_LOG"; done
run_probe "$S12_LOG" "$S12_CTL"
assert "S12 a window whose newest row is >600s stale -> exit 3 reason=producer_silent, never PASS" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'producer_silent' <<<\"\$CASE_OUT\""

# S12b: THE MASKING CASE. NEWEST_DT is scoped to producer-attributable rows — a FRESH row that
# merely mentions the marker (grep noise, a webhook quote on this shared source) must not defeat
# producer_silent. Same stale window as S12 + one fresh "other"-class row at 09:55 (300s, inside
# the gate threshold): unscoped freshness would see a live source and PASS the corpse.
S12B_LOG="$TMP/s12b.log"; cp "$S12_LOG" "$S12B_LOG"
row "ci-runner log quoting a shipped row: SOLEUR_ZOT_LOG shipper=zot-log-shipper seen upstream" "$DT_0955" >> "$S12B_LOG"
run_probe "$S12B_LOG" "$S12_CTL"
assert "S12b a fresh non-producer row cannot mask producer silence -> still exit 3" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'producer_silent' <<<\"\$CASE_OUT\""

# S13: A DECOY MASK MUST NOT CANCEL A REAL VALUE. authleak is per-occurrence: a row carrying
# both `Authorization:[******]` and `Authorization:[Basic …]` still flags.
S13_LOG="$TMP/s13.log"; : > "$S13_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S13_LOG"; done
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{Authorization:[******],X-Fwd:[Authorization:[Basic c3ludGhldGljOm5vdC1yZWFsLXNlY3JldA==]]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0956" >> "$S13_LOG"
run_probe "$S13_LOG" "$S1_CTL"
assert "S13 a masked + unmasked Authorization pair on ONE row still fails -> exit 1" \
  "[[ '$CASE_RC' -eq 1 ]] && grep -q 'unmasked_authorization_rows=1' <<<\"\$CASE_OUT\""

# S14: DOT PADDING IS NOT A TOKEN. `.` sits in the measured token charset, so `dp.st.` followed
# by nothing but dots must NOT trip the shape scan — otherwise a crafted request path could post
# a public FAIL on demand.
S14_LOG="$TMP/s14.log"; : > "$S14_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S14_LOG"; done
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:HTTP API,headers:{User-Agent:[dp.st........................]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0956" >> "$S14_LOG"
run_probe "$S14_LOG" "$S1_CTL"
assert "S14 dot padding after a dp.<kind>. prefix is not token-shaped -> still PASS" \
  "[[ '$CASE_RC' -eq 0 ]]"

# S14b: A DECOY PREFIX FIRST OCCURRENCE MUST NOT MASK A LATER TOKEN. shapeleak walks every
# dp.<kind>. occurrence — `dp.st.x dp.st.<substantive>` still flags.
S14B_LOG="$TMP/s14b.log"; : > "$S14B_LOG"
for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S14B_LOG"; done
row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV level:info,message:dp.st.x then dp.st.abcdxyz0123456789token,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92" "$DT_0956" >> "$S14B_LOG"
run_probe "$S14B_LOG" "$S1_CTL"
assert "S14b a decoy dp.st.x before a real token still fails -> exit 1" \
  "[[ '$CASE_RC' -eq 1 ]] && grep -q 'token_or_hash_shaped_rows=1' <<<\"\$CASE_OUT\""

# S15: AN EMPTY-dt STAMPED ROW CANNOT SET THE BOUNDARY — and must not corrupt the verdict. The
# boundary skip (Rdt=="") means the next stamped row binds; with ONLY an empty-dt stamped row
# the boot derives but B0 can't, which is CANNOT ESTABLISH, not a silently-misgraded span.
# (row() defaults an empty dt to DT0, so these rows are written with jq directly.)
S15_CTL="$TMP/s15.ctl"
jq -cn --arg m "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$DRIFTED_BOOT log_shipper_post_fail=0 host=$HOSTV" '{dt:"", raw:({message:$m}|tostring)}' > "$S15_CTL"
run_probe "$S13_LOG" "$S15_CTL"
assert "S15 empty-dt stamped row + leak-shaped envelope -> exit 3 (boundary unmeasurable)" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'ungraded_credential_rows=1' <<<\"\$CASE_OUT\""
S15_CTL2="$TMP/s15b.ctl"
cat "$S15_CTL" > "$S15_CTL2"
control_row "$DRIFTED_BOOT" 0 "$DT_0950" >> "$S15_CTL2"
S15_LOG2="$TMP/s15b.log"; : > "$S15_LOG2"; for _ in $(seq 1 30); do envelope_row "$DT_0956" >> "$S15_LOG2"; done
run_probe "$S15_LOG2" "$S15_CTL2"
assert "S15b a readable stamped row still supplies B0 when an empty-dt sibling precedes it" \
  "[[ '$CASE_RC' -eq 0 ]]"
# S15c: the sentinel arm itself — boot derived, every stamped row dt-less, no leak to name ->
# the boundary-measurability arm, never a silent misgrade nor a false delivery verdict.
run_probe "$S15_LOG2" "$S15_CTL"
assert "S15c a boot whose only stamped row has empty dt -> exit 3 boundary unmeasurable" \
  "[[ '$CASE_RC' -eq 3 ]] && grep -q 'boundary timestamp is' <<<\"\$CASE_OUT\""

# --- C12: structural contract assertions on the probe as a FILE --------------------------
# AC14: anchored on the executable form, because the prose above legitimately contains 'exit 1'.
N_EXIT1=$(grep -cE '^[[:space:]]*exit[[:space:]]+1[[:space:]]*$' "$PROBE" || true)
assert "C12 the probe contains EXACTLY ONE executable 'exit 1' (the credential arm)" \
  "[[ '$N_EXIT1' -eq 1 ]]"
# AC15: the ${VAR:?msg} form aborts with status 1 under the sweeper's shell, which this contract
# reads as FAIL — so an unprovisioned secret would post a daily false-FAIL forever.
#
# THIS ASSERTION MIRRORS scripts/lint-followthrough-varq-ban.sh's OWN TWO-STAGE PREDICATE, and the
# two stages are not optional. A single-stage grep for the literal matches the probe's own
# DOCUMENTATION of the ban (the header explains why the form is forbidden, and the sibling probe
# carries the same prose), so a naive form false-FAILS a compliant file — the "grep over a script
# body false-matches its own comments" class. The linter greps the RAW file with `-n` first, THEN
# drops full-line-comment hits; line-number order is load-bearing there and copied faithfully here.
# The linter remains the authority and is what reds CI.
N_VARQ=$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$PROBE" | grep -vcE '^[0-9]+:[[:space:]]*#' || true)
[[ "$N_VARQ" =~ ^[0-9]+$ ]] || N_VARQ=0
assert "C12 the probe uses no \${VAR:?} form OUTSIDE comments (mirrors the linter's own predicate)" \
  "[[ '$N_VARQ' -eq 0 ]]"
assert "C12 and the real linter agrees (it is the authority that reds CI)" \
  "bash '$REPO_ROOT/scripts/lint-followthrough-varq-ban.sh' >/dev/null 2>&1"
assert "C12 the probe is committed with mode 100755 (the exec-bit guard reads the git INDEX)" \
  "[[ \"\$(cd '$REPO_ROOT' && git ls-files -s scripts/followthroughs/zot-log-channel-7440.sh | awk '{print \$1}')\" == '100755' ]]"
assert "C12 the probe is syntactically valid bash" "bash -n '$PROBE'"
assert "C12 the probe's tracker is NOT #7440 (the sweeper would make it a silent no-op)" \
  "grep -qE 'NOT #7440' '$PROBE'"
# The probe must not reach for the archive arm: its window is inside the hot keyhole, and the
# archive arm would add an S3 failure mode to a steady-state probe for no coverage.
assert "C12 the probe passes --no-archive on its queries" "grep -qF -- '--no-archive' '$PROBE'"

# --- C13: no raw row content reaches stdout (#7444 F-6) -----------------------------------
# sweep-followthroughs.sh captures this probe's stdout with 2>&1 and posts it as a comment on a
# PUBLIC repo issue. The FAIL arm is counts-only by design; the PASS arm ended in a three-row
# excerpt. A raw zot row carries internal 10.0.1.x topology, service usernames, OCI repo names,
# digests, filesystem paths and User-Agent — and the credential scan above covers exactly three
# patterns, so a secret shape outside those three exits 0 and is published verbatim.
#
# Counts and ratios are the contract. Row VALUES never are.
#
# Two-stage predicate mirroring C12's, and the two stages are not optional: the prose above
# legitimately names the forbidden construct, so a single-stage grep false-FAILS a compliant file.
N_EXCERPT=$(grep -nE '\$\{?(envelope_hits|decoded|auth_rows|shape_leaks|drop_hits|boot_hits|control_decoded|raw_log|control_raw|SUMMARY)\}?"?[[:space:]]*\|[[:space:]]*(tail|head|cut|sed)\b' "$PROBE" | grep -vcE '^[0-9]+:[[:space:]]*#' || true)
[[ "$N_EXCERPT" =~ ^[0-9]+$ ]] || N_EXCERPT=0
assert "C13 no raw row variable is excerpted to stdout (the sweeper posts stdout to a PUBLIC issue)" \
  "[[ '$N_EXCERPT' -eq 0 ]]"

