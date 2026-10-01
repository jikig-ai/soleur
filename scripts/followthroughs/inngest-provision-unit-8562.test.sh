#!/usr/bin/env bash
# Exit-code harness for inngest-provision-unit-8562.sh (#8562, ADR-257).
#
# The probe's PASS auto-closes #8562 and flips ADR-257's promotion criterion, so every case below
# is a way the verdict can be wrong in the PASS direction — an old host life's bootstrap-done, a
# row that merely MENTIONS a stage, a foreign host or marker — plus the TRANSIENT/FAIL boundaries,
# because a probe stuck at TRANSIENT is a tracker that never closes and a probe that FAILs early
# posts a daily false alarm.
#
# The 8539 twin (inngest-private-nic-8539.sh) has no harness of its own, so this mirrors the
# nearest sibling that does, inngest-zot-boot-7462.test.sh: production-shaped rows (`raw` is a
# JSON-ENCODED STRING, exactly as betterstack-query.sh emits it), and a stub that ASSERTS ITS ARGV.
# Values are synthesized (cq-test-fixtures-synthesized-only): every iid, time and detail is made up.
#
# Every case also asserts the stdout contract: exactly ONE line, and it starts with `verdict=`.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-provision-unit-8562.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub serves two queries, keyed on their --grep set, and refuses any other shape.
cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
argv="$*"
[[ "$argv" == *"--since 30d"* ]] || { echo "stub: query missing --since 30d (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--limit"* ]] || { echo "stub: query missing --limit (argv: $argv)" >&2; exit 64; }
# The archive arm is mandatory at a 30d window; --no-archive would truncate to the hot keyhole.
[[ "$argv" == *"--no-archive"* ]] && { echo "stub: --no-archive at a multi-day window (argv: $argv)" >&2; exit 64; }
if [[ "$argv" == *"--grep provision-unit-armed"* ]]; then
  [[ "${STUB_RC_ARMED:-0}" == "0" ]] || exit "${STUB_RC_ARMED}"
  cat "${STUB_ARMED:-/dev/null}"
elif [[ "$argv" == *"--grep provision-attempt-start"* && "$argv" == *"--grep bootstrap-done"* ]]; then
  [[ "${STUB_RC_LIFE:-0}" == "0" ]] || exit "${STUB_RC_LIFE}"
  cat "${STUB_LIFE:-/dev/null}"
else
  echo "stub: unexpected query shape (argv: $argv)" >&2; exit 64
fi
STUB
chmod +x "$WORK/stub-query"

NOW=1790000000
# row <epoch> <stage> <detail> [host] [marker] [message-override] — ONE production-shaped line.
row() {
  local t="$1" stage="$2" detail="$3" host="${4:-soleur-inngest}" marker="${5:-SOLEUR_INNGEST_BOOT_STAGE}" msg="${6:-}"
  [[ -n "$msg" ]] || msg="SOLEUR_INNGEST_BOOT_STAGE stage=${stage} ${detail}"
  jq -cn --argjson t "$t" --arg m "$marker" --arg s "$stage" --arg d "$detail" --arg h "$host" --arg msg "$msg" \
    '{dt: ($t | todate | sub("T"; " ") | sub("Z"; "")),
      raw: ({message: $msg, marker: $m, stage: $s, detail: $d, host: $h, dt: ($t | todate), shipper: "cloud-init-phone-home"} | tostring)}'
}

# run <armed-file> <life-file> -> sets RC / STDOUT (stderr lands in $WORK/stderr)
run() {
  STDOUT="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        INNGEST_PROVISION_8562_QUERY_BIN="$WORK/stub-query" INNGEST_PROVISION_8562_NOW="$NOW" \
        STUB_ARMED="$1" STUB_LIFE="$2" STUB_RC_ARMED="${STUB_RC_ARMED:-0}" STUB_RC_LIFE="${STUB_RC_LIFE:-0}" \
        bash "$PROBE" 2>"$WORK/stderr")"
  RC=$?
}

expect() { # expect <case> <want-rc> <want-exact-stdout>
  local name="$1" want_rc="$2" want_out="$3" lines
  lines="$(printf '%s\n' "$STDOUT" | grep -c . || true)"
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name — rc=$RC want=$want_rc :: stdout=$(printf '%s' "$STDOUT" | head -1)"
  elif [[ "$lines" != "1" ]]; then
    fail "$name — stdout must be exactly one verdict line, got $lines"
  elif [[ "$STDOUT" != "$want_out" ]]; then
    fail "$name — rc ok but stdout '$STDOUT' != '$want_out'"
  else
    pass "$name"
  fi
}

echo "== inngest-provision-unit-8562.sh exit-code harness =="

: > "$WORK/empty.jsonl"
row $((NOW - 3600)) provision-unit-armed "iid=900000001 timer=enabled" > "$WORK/armed-1h.jsonl"
row $((NOW - 300)) provision-unit-armed "iid=900000001 timer=enabled" > "$WORK/armed-5m.jsonl"
row $((NOW - 14400)) provision-unit-armed "iid=900000001 timer=enabled" > "$WORK/armed-4h.jsonl"
# Every FAIL line carries the per-iid cause counts; most cases have none of the four stages.
C0="cause=isolation-check-FAILED:0,inngest_pull_fatal:0,provision-fsm-busy:0,bootstrap-done-DEGRADED:0"

# --- C1 credentials absent is probe-fault, never not-delivered --------------------------------------
STDOUT="$(INNGEST_PROVISION_8562_QUERY_BIN="$WORK/stub-query" INNGEST_PROVISION_8562_NOW="$NOW" \
      STUB_ARMED="$WORK/armed-1h.jsonl" \
      env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD \
      bash "$PROBE" 2>/dev/null)"; RC=$?
expect "C1 unprovisioned credentials -> TRANSIENT probe-fault (exit 3)" 3 "verdict=TRANSIENT reason=probe-fault"

# --- C2/C3 a failed query on either leg is probe-fault ----------------------------------------------
STUB_RC_ARMED=7 run "$WORK/armed-1h.jsonl" "$WORK/empty.jsonl"
expect "C2 armed query rc!=0 -> probe-fault" 3 "verdict=TRANSIENT reason=probe-fault"
STUB_RC_LIFE=7 run "$WORK/armed-1h.jsonl" "$WORK/empty.jsonl"
expect "C3 life query rc!=0 -> probe-fault" 3 "verdict=TRANSIENT reason=probe-fault"

# --- C4 no armed row -> not delivered ---------------------------------------------------------------
{ row $((NOW - 3600)) bootstrap-done "iid=900000001"; } > "$WORK/done-only.jsonl"
run "$WORK/empty.jsonl" "$WORK/done-only.jsonl"
expect "C4 no provision-unit-armed row -> TRANSIENT not-delivered (a bare bootstrap-done is not delivery)" 2 "verdict=TRANSIENT reason=not-delivered"

# --- C5 the PASS -------------------------------------------------------------------------------------
{ row $((NOW - 3590)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 3000)) bootstrap-done "iid=900000001"; } > "$WORK/good.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/good.jsonl"
expect "C5 armed + bootstrap-done with the same iid -> PASS" 0 "verdict=PASS"

# --- C6 an OLD host life's bootstrap-done never PASSes the new one ----------------------------------
{ row $((NOW - 90000)) provision-unit-armed "iid=800000009 timer=enabled";
  row $((NOW - 3600)) provision-unit-armed "iid=900000001 timer=enabled"; } > "$WORK/armed-two.jsonl"
{ row $((NOW - 89000)) provision-attempt-start "attempt=1 iid=800000009";
  row $((NOW - 88000)) bootstrap-done "iid=800000009";
  row $((NOW - 1000)) bootstrap-done "iid=800000009"; } > "$WORK/old-life.jsonl"
run "$WORK/armed-two.jsonl" "$WORK/old-life.jsonl"
expect "C6 newest armed iid wins; an older iid's bootstrap-done (even a late one) -> FAIL never-started" 1 "verdict=FAIL reason=never-started $C0"

# --- C7 armed recently, nothing started yet -> in-progress --------------------------------------------
run "$WORK/armed-5m.jsonl" "$WORK/empty.jsonl"
expect "C7 armed < 10 min ago, no attempt -> TRANSIENT in-progress" 2 "verdict=TRANSIENT reason=in-progress"

# --- C8 armed long ago, no attempt ever -> FAIL never-started -----------------------------------------
run "$WORK/armed-1h.jsonl" "$WORK/empty.jsonl"
expect "C8 armed > 10 min ago, no attempt -> FAIL never-started" 1 "verdict=FAIL reason=never-started $C0"

# --- C9 attempts older than 2 h and no bootstrap-done -> FAIL ---------------------------------------
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 600)) provision-attempt-start "attempt=40 iid=900000001"; } > "$WORK/stuck.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/stuck.jsonl"
expect "C9 first attempt > 2 h ago, no bootstrap-done -> FAIL no-bootstrap-done" 1 "verdict=FAIL reason=no-bootstrap-done $C0"

# --- C10 attempts inside the 2 h bound -> in-progress -------------------------------------------------
{ row $((NOW - 3590)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 60)) provision-attempt-start "attempt=12 iid=900000001"; } > "$WORK/retrying.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/retrying.jsonl"
expect "C10 attempts for 1 h, no bootstrap-done -> TRANSIENT in-progress" 2 "verdict=TRANSIENT reason=in-progress"

# --- C11 FIELD ISOLATION: a row that merely MENTIONS bootstrap-done must not count --------------------
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 100)) post-boot-health "iid=900000001" soleur-inngest SOLEUR_INNGEST_BOOT_STAGE \
      "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done iid=900000001 echoed-in-prose"; } > "$WORK/spoof.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/spoof.jsonl"
expect "C11 stage name in the MESSAGE does not satisfy the .stage anchor" 1 "verdict=FAIL reason=no-bootstrap-done $C0"

# --- C12 a foreign HOST's rows are ignored (web-1 shares the source) --------------------------------
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 100)) bootstrap-done "iid=900000001" soleur-inngest-prd; } > "$WORK/foreign-host.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/foreign-host.jsonl"
expect "C12 a bootstrap-done from another host cannot PASS" 1 "verdict=FAIL reason=no-bootstrap-done $C0"
row $((NOW - 3600)) provision-unit-armed "iid=900000001" web-1 > "$WORK/armed-foreign.jsonl"
run "$WORK/armed-foreign.jsonl" "$WORK/good.jsonl"
expect "C12b an armed row from another host is not delivery" 2 "verdict=TRANSIENT reason=not-delivered"

# --- C13 a foreign MARKER's rows are ignored ----------------------------------------------------------
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 100)) bootstrap-done "iid=900000001" soleur-inngest SOLEUR_INNGEST_BOOT_TRACE_LOST; } > "$WORK/foreign-marker.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/foreign-marker.jsonl"
expect "C13 a different marker's row cannot supply bootstrap-done" 1 "verdict=FAIL reason=no-bootstrap-done $C0"

# --- C14 undecodable rows are dropped, not fatal ------------------------------------------------------
{ echo '{"dt":"2026-09-28 10:00:00","raw":"not-json-at-all"}'; echo 'total garbage'; cat "$WORK/good.jsonl"; } > "$WORK/garbage.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/garbage.jsonl"
expect "C14 undecodable rows are skipped, valid ones still counted -> PASS" 0 "verdict=PASS"

# --- C15 an armed row with no iid cannot anchor anything -> probe-fault -------------------------------
row $((NOW - 3600)) provision-unit-armed "timer=enabled" > "$WORK/armed-noiid.jsonl"
run "$WORK/armed-noiid.jsonl" "$WORK/good.jsonl"
expect "C15 armed row without iid= -> probe-fault, never PASS" 3 "verdict=TRANSIENT reason=probe-fault"

# --- C16 iid is matched as a whole token, not a prefix ------------------------------------------------
{ row $((NOW - 3590)) provision-attempt-start "attempt=1 iid=9000000011";
  row $((NOW - 3000)) bootstrap-done "iid=9000000011"; } > "$WORK/prefix.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/prefix.jsonl"
expect "C16 iid=9000000011 is not iid=900000001" 1 "verdict=FAIL reason=never-started $C0"

# --- C17 output never carries a row's detail ----------------------------------------------------------
{ row $((NOW - 3590)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 3000)) bootstrap-done "iid=900000001 tail=synthetic-tail-10.0.1.40"; } > "$WORK/detail.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/detail.jsonl"
if grep -qE 'tail=|10\.0\.1\.|synthetic-tail' <<<"$STDOUT$(cat "$WORK/stderr")"; then
  fail "C17 output leaked a row detail (the sweeper posts this to a PUBLIC issue)"
else
  pass "C17 output is counts + iid only"
fi

# --- C18 xtrace with a live credential is refused before anything else runs ---------------------------
# Built by concatenation so no contiguous credential-shaped literal reaches the secret scanner.
C18_PW="synthetic""-pw-""8562"
xout="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD="$C18_PW" \
      INNGEST_PROVISION_8562_QUERY_BIN="$WORK/stub-query" bash -x "$PROBE" 2>&1)"; xrc=$?
if [[ "$xrc" -eq 78 ]] && ! grep -qF "$C18_PW" <<<"$xout"; then
  pass "C18 bash -x with a live credential -> exit 78, credential not traced"
else
  fail "C18 xtrace refusal — rc=$xrc (want 78) or the credential appeared in the trace"
fi

# --- C21 the hostname / `unknown` iid fallbacks are SHARED by every host life -> probe-fault -------
row $((NOW - 3600)) provision-unit-armed "iid=unknown timer=enabled" > "$WORK/armed-unknown.jsonl"
{ row $((NOW - 3000)) bootstrap-done "attempt=1 iid=unknown"; } > "$WORK/done-unknown.jsonl"
run "$WORK/armed-unknown.jsonl" "$WORK/done-unknown.jsonl"
expect "C21 armed iid=unknown -> probe-fault, never PASS on a shared id" 3 "verdict=TRANSIENT reason=probe-fault"
row $((NOW - 3600)) provision-unit-armed "iid=soleur-inngest timer=enabled" > "$WORK/armed-hostname.jsonl"
{ row $((NOW - 3000)) bootstrap-done "attempt=1 iid=soleur-inngest"; } > "$WORK/done-hostname.jsonl"
run "$WORK/armed-hostname.jsonl" "$WORK/done-hostname.jsonl"
expect "C21b armed iid=<hostname> -> probe-fault, never PASS on a shared id" 3 "verdict=TRANSIENT reason=probe-fault"

# --- C22 a stage field that is not one token never reads as bootstrap-done -----------------------------
# A whitespace split would read "bootstrap-done 900000001" as stage=bootstrap-done iid=900000001.
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 100)) "bootstrap-done 900000001" ""; } > "$WORK/forged-stage.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/forged-stage.jsonl"
expect "C22 forged stage 'bootstrap-done <iid>' is dropped -> FAIL, not PASS" 1 "verdict=FAIL reason=no-bootstrap-done $C0"
# A TAB inside the stage would shift columns in the probe's TAB-separated decode; the single-token
# stage filter drops it before that can happen.
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 100)) $'bootstrap-done\t900000001' ""; } > "$WORK/forged-tab.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/forged-tab.jsonl"
expect "C22b forged stage with an embedded TAB is dropped -> FAIL, not PASS" 1 "verdict=FAIL reason=no-bootstrap-done $C0"

# --- C23 a DEGRADED completion is never a PASS ----------------------------------------------------------
{ row $((NOW - 3590)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 3000)) bootstrap-done-DEGRADED "attempt=1 iid=900000001"; } > "$WORK/degraded.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/degraded.jsonl"
expect "C23 only bootstrap-done-DEGRADED -> FAIL degraded" 1 \
  "verdict=FAIL reason=degraded cause=isolation-check-FAILED:0,inngest_pull_fatal:0,provision-fsm-busy:0,bootstrap-done-DEGRADED:1"
{ cat "$WORK/degraded.jsonl"; row $((NOW - 60)) bootstrap-done "attempt=2 iid=900000001"; } > "$WORK/degraded-then-done.jsonl"
run "$WORK/armed-1h.jsonl" "$WORK/degraded-then-done.jsonl"
expect "C23b a later full bootstrap-done after a degraded one -> PASS" 0 "verdict=PASS"

# --- C24 cause= counts only this iid's rows, per stage --------------------------------------------------
{ row $((NOW - 14390)) provision-attempt-start "attempt=1 iid=900000001";
  row $((NOW - 14380)) isolation-check-FAILED "attempt=1 iid=900000001";
  row $((NOW - 9000)) inngest_pull_fatal "zot miss rc=124 attempt=20 iid=900000001";
  row $((NOW - 8000)) inngest_pull_fatal "zot miss rc=124 attempt=21 iid=900000001";
  row $((NOW - 7000)) provision-fsm-busy "units=[x] attempt=22 iid=900000001";
  row $((NOW - 6000)) inngest_pull_fatal "zot miss rc=124 attempt=3 iid=800000009"; } > "$WORK/causes.jsonl"
run "$WORK/armed-4h.jsonl" "$WORK/causes.jsonl"
expect "C24 FAIL cause= carries this iid's per-stage counts only" 1 \
  "verdict=FAIL reason=no-bootstrap-done cause=isolation-check-FAILED:1,inngest_pull_fatal:2,provision-fsm-busy:1,bootstrap-done-DEGRADED:0"

# --- C19 the banned ${VAR:?} form would turn an unset secret into a daily false-FAIL -----------------
# Pattern and comment-scoping mirror scripts/lint-followthrough-varq-ban.sh.
if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$PROBE" | grep -qvE '^[0-9]+:[[:space:]]*#'; then
  fail "C19 probe uses the banned \${VAR:?} form in CODE (aborts rc=1 -> reads as FAIL)"
else
  pass "C19 probe avoids the banned \${VAR:?} form in code"
fi

# --- C20 anti-vacuity: the harness ran its whole inventory --------------------------------------------
# EXACT, not >=. A floor that only catches shrinkage still lets a case be silently replaced.
if [[ "$checks" -ne 27 ]]; then
  fail "C20 anti-vacuity: expected 27 checks before this one, ran $checks"
else
  pass "C20 anti-vacuity: full inventory ran (27 checks + this one)"
fi

echo
if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "OK: all $checks exit-code checks correct"
