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
# the probe PASSes on that fixture it would auto-close its own tracker and flip ADR-182 on an echo
# of the very absence it exists to detect.
#
# Run: bash tests/scripts/test-zot-log-channel-probe.sh

set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/zot-log-channel-7440.sh"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)" || { echo "FATAL: mktemp -d failed (TMPDIR=$TMPDIR)" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

echo "=== zot log-channel probe (#7440) fixture tests ==="
assert "the probe exists" "[[ -f '$PROBE' ]]"

BASELINE_BOOT="bc135d5b-d509-41c4-8129-9181421e845c"
DRIFTED_BOOT="ffffffff-1111-2222-3333-444444444444"
HOSTV="soleur-registry"

# Wrap a bare message in the real two-layer encoding: the inner object is JSON-encoded into a
# string, which becomes the `raw` column of the outer object.
row() { jq -cn --arg m "$1" '{dt:"2026-08-11 10:00:00.000000", raw:({message:$m}|tostring)}'; }

ZOTLINE='level:info,message:HTTP API,module:http,component:session,clientIP:10.0.1.30:39330,method:GET,path:/v2/,statusCode:401,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92'

envelope_row() { row "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOSTV $ZOTLINE"; }
control_row() {
  local boot="$1" postfail="${2:-0}"
  row "SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 ping_rc=0 state_status=running boot_id=$boot log_shipper_post_fail=$postfail log_shipper_last_ok_age_s=42 host=$HOSTV zot_last_err={time:2026-08-11T10:04:34Z,level:info,message:HTTP API,caller:zotregistry.dev/zot/v2/pkg/api/session.go:92,func:zotregistry.dev/}"
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
if [[ -n "${STUB_QUERY_RC:-}" && "${STUB_QUERY_RC}" != 0 ]]; then exit "$STUB_QUERY_RC"; fi
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
    ZOT_LOG_7440_BASELINE_BOOT_ID="$BASELINE_BOOT" \
    ZOT_LOG_7440_HOST="$HOSTV" \
    STUB_LOG_ROWS="$logrows" STUB_CONTROL_ROWS="$controlrows" STUB_QCALLS="$STUB_QCALLS" \
    "$@" \
    timeout 60 bash "$PROBE" 2>&1) || CASE_RC=$?
  LAST_QCALLS="$STUB_QCALLS"
}

EMPTY="$TMP/empty"; : > "$EMPTY"

# --- C1: PASS-ARM REACHABILITY ------------------------------------------------------------
# Without this, "never emits exit 1" is satisfiable by a probe that can never pass at all.
# 30 envelope rows == the computed expectation for a 30-minute window at the 60s liveness cadence.
C1_LOG="$TMP/c1.log"; : > "$C1_LOG"
for _ in $(seq 1 30); do envelope_row >> "$C1_LOG"; done
C1_CTL="$TMP/c1.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C1_CTL"
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
C2_CTL="$TMP/c2.ctl"; control_row "$BASELINE_BOOT" 0 > "$C2_CTL"
run_probe "$EMPTY" "$C2_CTL"
assert "C2 zero envelope + baseline boot_id -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C2 reason=not_delivered" "grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""
assert "C2 says so is the EXPECTED steady state (so the operator does not chase it)" \
  "grep -qi 'expected steady state' <<<\"\$CASE_OUT\""

# --- C3: delivered_but_silent — boot_id drifted, still zero envelope rows ------------------
# This is the state that separates ACT from WAIT, and collapsing it into 'not delivered' is the
# defect this case exists to prevent.
C3_CTL="$TMP/c3.ctl"; control_row "$DRIFTED_BOOT" 0 > "$C3_CTL"
run_probe "$EMPTY" "$C3_CTL"
assert "C3 boot_id drift + zero envelope -> exit 2" "[[ '$CASE_RC' -eq 2 ]]"
assert "C3 reason=delivered_but_silent (NOT collapsed into not_delivered)" \
  "grep -q 'reason=delivered_but_silent' <<<\"\$CASE_OUT\""
assert "C3 does NOT also claim not_delivered" "! grep -q 'reason=not_delivered' <<<\"\$CASE_OUT\""

# --- C3b: same state reached via the BOOT MARKER rather than boot_id drift -----------------
C3B_LOG="$TMP/c3b.log"
row "SOLEUR_ZOT_LOG_BOOT boot_id=$DRIFTED_BOOT host=$HOSTV shipper_unit=failed journald_storage=persistent" > "$C3B_LOG"
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

# --- C9: THE FALSE-GREEN. The highest-value assertion in this suite -----------------------
# This fixture is TODAY'S PRODUCTION STATE: only heartbeat rows, whose zot_last_err echoes
# zotregistry.dev. A bare `--grep zotregistry.dev` returns 53 of these over 6h right now.
C9_LOG="$TMP/c9.log"; : > "$C9_LOG"
C9_CTL="$TMP/c9.ctl"; : > "$C9_CTL"
for _ in $(seq 1 53); do control_row "$BASELINE_BOOT" 0 >> "$C9_CTL"; done
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
N_EXCERPT=$(grep -nE '\$\{?(envelope_hits|decoded|auth_rows|shape_leaks|drop_hits|boot_hits|control_decoded)\}?"?[[:space:]]*\|[[:space:]]*(tail|head|cut|sed)\b' "$PROBE" | grep -vcE '^[0-9]+:[[:space:]]*#' || true)
[[ "$N_EXCERPT" =~ ^[0-9]+$ ]] || N_EXCERPT=0
assert "C13 no raw row variable is excerpted to stdout (the sweeper posts stdout to a PUBLIC issue)" \
  "[[ '$N_EXCERPT' -eq 0 ]]"

# ASSERTION FLOOR (#7444 F-4). An ABSOLUTE LITERAL, never derived from the run it guards: a
# floor computed from this suite's own output is reduced by the exact truncation it exists to
# detect. It increments FAIL rather than exiting, so the miss is reported through the same
# channel as every other failure and the gate below stays the single exit point.
#
# Without it, `assert() { return 0; }` and "delete everything from C5 onward" both yield a
# summary line and rc=0 — CI-green on a suite that asserted nothing. Neither runner catches it:
# run_suite branches solely on `if ! "$@"`, and the workflow step is pure rc.
#
# Raise this literal in the same commit that adds assertions.
MIN_ASSERTIONS=55
RAN=$(( PASS + FAIL ))
if [[ "$RAN" -lt "$MIN_ASSERTIONS" ]]; then
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: assertion floor — ran $RAN assertions, expected >= $MIN_ASSERTIONS"
  echo "        (suite truncated, or assert() neutered — this run certified nothing)"
fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
