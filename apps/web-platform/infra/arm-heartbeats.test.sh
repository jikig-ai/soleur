#!/usr/bin/env bash
# Behavioural tests for the measured-beat ARM gate (apps/web-platform/infra/arm-heartbeats.sh, #7587).
#
# WHY THIS FILE EXISTS. Before #7587 the gate was ~130 lines of bash inside a YAML scalar and
# `git grep arm_one` across the test trees returned only comments — it was asserted by NOTHING.
# The first design for asserting it was a regex over the workflow, which the plan's test-design
# review showed is not merely brittle but WEAK: "the counter advances by measured elapsed time" is
# checkable that way only as "a clock read appears in the step", which a decoy `date +%s` satisfies
# and an equivalent `SECONDS`-based rewrite false-REDs. So the gate is a real script and this suite
# drives it BEHAVIOURALLY, against a fake clock and a fake `curl` on PATH — the house shape used by
# `web-private-nic-guard.sh` + `.test.sh` and the other pairs in this directory.
#
# WHAT IS FAKED, AND WHAT IS NOT. `curl`, `sleep` and `date` are PATH stubs. `jq`, `grep`, `mv` and
# every other utility the SUT uses are REAL, and so is the SUT: this executes
# `apps/web-platform/infra/arm-heartbeats.sh` itself, never a reconstruction of it.
#
# THE FAKE CLOCK IS THE WHOLE POINT, AND IT IS WHY THE ASSERTIONS READ TWO DIFFERENT NUMBERS.
# `sleep N` advances the clock by N and returns instantly; every `curl` advances it by
# FAKE_CURL_COST. The SUT REPORTS an elapsed, and the harness separately OBSERVES the clock. Under
# the pre-#7587 sleep-tally those two diverge — the reported elapsed stops at the nominal deadline
# while the real clock reaches deadline x 2.5 — so an assertion on the reported number alone cannot
# see the defect. Mutation row M1 reverts the fix and requires the OBSERVED clock to blow its
# bound; that is the row the reported-elapsed assertion would have passed over.
#
# The stub `curl` dispatches on its ARGV — method, URL and body — and `exit 64`s when it is handed
# no URL or an unrecognised PATCH body, so a SUT that starts querying the wrong thing is detectable
# rather than silently served the same fixture (the PATH-shimmed-fake trap, #7081). Monitor ids are
# synthesized (`cq-test-fixtures-synthesized-only`); no real Better Stack id appears in this file.
#
# Pure bash + jq + PATH stubs — no network, no docker, no doppler, no root, no terraform.
#
# Run: bash apps/web-platform/infra/arm-heartbeats.test.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"   # a self-invoked suite must not inherit the bare 4 GiB /tmp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/arm-heartbeats.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ $# -lt 2 ]] || echo "        $2"; }
assert() {  # <desc> <condition>
  if eval "$2"; then pass "$1"; else fail "$1" "condition: $2"; fi
}
assert_eq() {  # <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A harness that fails to SET UP must abort, never continue: the next case would then run against
# the previous case's state and produce a confident verdict about the SUT that the harness authored.
[[ -d "$WORK" ]] || { echo "FATAL: mktemp -d failed"; exit 2; }

REAL_DATE="$(command -v date)"
[[ -x "$REAL_DATE" ]] || { echo "FATAL: no real date binary"; exit 2; }

echo "=== ARM gate (arm-heartbeats.sh, #7587) behavioural tests ==="
assert "the SUT exists" "[[ -f '$SUT' ]]"
assert "the SUT is syntactically valid bash" "bash -n '$SUT'"
[[ -f "$SUT" ]] || { echo "FATAL: SUT missing"; exit 2; }

# --- PATH stubs ---------------------------------------------------------------------------
BIN="$WORK/bin"
mkdir -p "$BIN" || { echo "FATAL: mkdir stub dir failed"; exit 2; }

cat > "$BIN/date" <<EOS
#!/usr/bin/env bash
if [[ "\${1:-}" == "+%s" ]]; then cat "\$FAKE_CLOCK"; exit 0; fi
exec "$REAL_DATE" "\$@"
EOS

cat > "$BIN/sleep" <<'EOS'
#!/usr/bin/env bash
# Instant, but it MOVES THE CLOCK. A sleep stubbed to a no-op silently voids every wall-clock
# assertion in this suite (#6441 (c)).
n="${1:-0}"
c=$(cat "$FAKE_CLOCK")
echo $(( c + n )) > "$FAKE_CLOCK"
EOS

cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# Fake Better Stack heartbeats API. Dispatches on ARGV (method + URL + body), NOT on argument
# count: a stub that answers identically regardless of what it was asked cannot detect a SUT
# querying the wrong thing, and a fixture keyed per id is what makes "one clean, one dirty" real.
args=("$@")
url=""; method="GET"; data=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -X)         method="${args[i+1]:-}" ;;
    --data-raw) data="${args[i+1]:-}" ;;
    https://*)  url="${args[i]}" ;;
  esac
done
if [[ -z "$url" ]]; then
  echo "fake curl: invoked with no URL argument" >&2
  exit 64
fi
id="${url##*/}"

# Every round-trip costs wall clock. This is the term the pre-#7587 sleep-tally ignored.
c=$(cat "$FAKE_CLOCK")
now=$(( c + ${FAKE_CURL_COST:-15} ))
echo "$now" > "$FAKE_CLOCK"

printf '%s\t%s\t%s\t%s\n' "$now" "$method" "$id" "$data" >> "$FAKE_CALLS"

case "$method" in
  GET)
    if grep -qxF -- "$id" "$FAKE_GET_FAIL" 2>/dev/null; then exit 22; fi
    status="$(cat "$FAKE_STATE/$id.status" 2>/dev/null || true)"
    [[ -n "$status" ]] || { echo "fake curl: no fixture for id $id" >&2; exit 22; }
    upat="$(cat "$FAKE_STATE/$id.upat" 2>/dev/null || true)"
    if [[ -n "$upat" && "$now" -ge "$upat" ]]; then status="up"; fi
    updated="$(cat "$FAKE_STATE/$id.updated" 2>/dev/null || echo "2026-08-20T00:00:00.000Z")"
    printf '{"data":{"id":"%s","attributes":{"status":"%s","updated_at":"%s"}}}\n' "$id" "$status" "$updated"
    ;;
  PATCH)
    # Keyed on the id AND the paused value, so a fixture can fail the ROLLBACK without also
    # failing the unpause that precedes it — those are different SUT branches and a fixture that
    # cannot separate them tests neither.
    case "$data" in
      *'"paused":false'*) want=false ;;
      *'"paused":true'*)  want=true ;;
      *) echo "fake curl: PATCH with an unrecognised body [$data]" >&2; exit 64 ;;
    esac
    if grep -qxF -- "$id $want" "$FAKE_PATCH_FAIL" 2>/dev/null; then exit 22; fi
    if [[ "$want" == "false" ]]; then printf 'pending' > "$FAKE_STATE/$id.status"
    else printf 'paused' > "$FAKE_STATE/$id.status"; fi
    printf '{"data":{"id":"%s"}}\n' "$id"
    ;;
  *)
    echo "fake curl: unsupported method $method" >&2; exit 64 ;;
esac
EOS
chmod +x "$BIN/date" "$BIN/sleep" "$BIN/curl" || { echo "FATAL: chmod stubs failed"; exit 2; }

# Stub fidelity, asserted rather than assumed.
FAKE_CLOCK="$WORK/clock-selftest"; echo 0 > "$FAKE_CLOCK"
FAKE_CALLS="$WORK/calls-selftest"; : > "$FAKE_CALLS"
FAKE_GET_FAIL="$WORK/getfail-selftest"; : > "$FAKE_GET_FAIL"
FAKE_PATCH_FAIL="$WORK/patchfail-selftest"; : > "$FAKE_PATCH_FAIL"
FAKE_STATE="$WORK/state-selftest"; mkdir -p "$FAKE_STATE"
export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_PATCH_FAIL FAKE_STATE
PATH="$BIN:$PATH" bash -c 'curl -fsS -H "Authorization: Bearer x"' >/dev/null 2>&1
assert_eq "the fake curl exits 64 when handed no URL (argv fidelity, not a fixture echo)" "64" "$?"
PATH="$BIN:$PATH" bash -c 'curl -fsS -X PATCH https://x.test/heartbeats/1 --data-raw "{}"' >/dev/null 2>&1
assert_eq "the fake curl exits 64 on a PATCH body it does not recognise" "64" "$?"
# The PATCH probe above legitimately advanced the clock before rejecting the body, so re-zero it
# rather than asserting against a number two probes contributed to.
echo 0 > "$FAKE_CLOCK"
PATH="$BIN:$PATH" bash -c 'sleep 7'
assert_eq "the fake sleep MOVES the clock rather than no-opping" "7" "$(cat "$FAKE_CLOCK")"
assert_eq "the fake date reads that clock" "7" "$(PATH="$BIN:$PATH" bash -c 'date +%s')"

# --- fixture -----------------------------------------------------------------------------
# Synthesized ids only. The ADDRESSES are the SUT's real ones — they are its contract with
# tfstate, so a rename there must red this suite.
ID_ZOT1=900101; ID_NIC1=900102; ID_ZOT2=900103; ID_NIC2=900104; ID_GITDATA=900105; ID_INNGEST=900106

write_tfstate() {  # <path> [omit-id ...]
  local out="$1"; shift
  local omit=" $* "
  {
    printf '{"values":{"root_module":{"resources":['
    local first=1 pair addr id
    for pair in \
      "betteruptime_heartbeat.web_zot_consumer[\"web-1\"]|$ID_ZOT1" \
      "betteruptime_heartbeat.web_nic_guard[\"web-1\"]|$ID_NIC1" \
      "betteruptime_heartbeat.web_zot_consumer[\"web-2\"]|$ID_ZOT2" \
      "betteruptime_heartbeat.web_nic_guard[\"web-2\"]|$ID_NIC2" \
      "betteruptime_heartbeat.git_data_prd|$ID_GITDATA" \
      "betteruptime_heartbeat.inngest_consumer|$ID_INNGEST"
    do
      addr="${pair%|*}"; id="${pair##*|}"
      [[ "$omit" == *" $id "* ]] && continue
      [[ $first -eq 1 ]] || printf ','
      first=0
      printf '{"address":%s,"values":{"id":"%s"}}' "$(printf '%s' "$addr" | jq -Rs .)" "$id"
    done
    printf ']}}}\n'
  } > "$out"
}

case_setup() {  # <name> — fresh clock/calls/state for one run; every id defaults to `up`
  CASE="$WORK/$1"
  mkdir -p "$CASE/state" || { echo "FATAL: case setup failed for $1"; exit 2; }
  FAKE_CLOCK="$CASE/clock"; echo 0 > "$FAKE_CLOCK"
  FAKE_CALLS="$CASE/calls"; : > "$FAKE_CALLS"
  FAKE_GET_FAIL="$CASE/getfail"; : > "$FAKE_GET_FAIL"
  FAKE_PATCH_FAIL="$CASE/patchfail"; : > "$FAKE_PATCH_FAIL"
  FAKE_STATE="$CASE/state"
  STATEFILE="$CASE/armed-unconfirmed"
  TFSTATE="$CASE/tfstate.json"
  write_tfstate "$TFSTATE"
  local id
  for id in "$ID_ZOT1" "$ID_NIC1" "$ID_ZOT2" "$ID_NIC2" "$ID_GITDATA" "$ID_INNGEST"; do
    printf 'up' > "$FAKE_STATE/$id.status"
  done
  export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_PATCH_FAIL FAKE_STATE
}

run_sut() {  # [sut-path] -> sets OUT and RC
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token \
        TFSTATE_JSON="$TFSTATE" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://uptime.betterstack.test/api/v2" \
        ARM_POLL_INTERVAL_S=10 \
        bash "$sut" 2>&1)"
  RC=$?
}
patch_bodies() { awk -F'\t' '$2=="PATCH"{print $3" "$4}' "$FAKE_CALLS"; }
patch_count()  { patch_bodies | grep -c '' ; }
state_lines()  { if [[ -f "$STATEFILE" ]]; then grep -c '' "$STATEFILE"; else echo 0; fi; }
observed_clock() { cat "$FAKE_CLOCK"; }
reported_elapsed() {  # <deadline> — the elapsed the SUT PRINTS, distinct from the observed clock
  printf '%s' "$OUT" | sed -n "s/.*never reached 'up' within \([0-9]*\)s of a $1s deadline.*/\1/p" | head -1
}

# --- T1: the steady state — every monitor already up ---------------------------------------
echo "--- T1 the modal merge: every monitor already armed"
case_setup t1
run_sut
assert_eq "T1 exits 0" "0" "$RC"
assert_eq "T1 reports every one of the six arms as a no-op" "6" \
  "$(printf '%s' "$OUT" | grep -c 'already armed (status=up)')"
assert_eq "T1 issues NO PATCH at all" "0" "$(patch_count)"
assert_eq "T1 never writes the unconfirmed-arm state file" "0" "$(state_lines)"
assert "T1 positive control: the fake curl was actually invoked" "[[ -s '$FAKE_CALLS' ]]"
assert "T1 enters no poll loop (observed clock is six GETs, nothing more)" \
  "[[ \$(observed_clock) -le 120 ]]"

# --- T2: inngest paused, feeder dark — the soft landing -------------------------------------
echo "--- T2 inngest_consumer paused with a dark feeder"
case_setup t2
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '2026-08-20T09:15:00.000Z' > "$FAKE_STATE/$ID_INNGEST.updated"
run_sut
assert_eq "T2 exits 0 — a dark feeder is soft-landed, not an apply failure" "0" "$RC"
assert "T2 emits the ::warning:: rather than an apply-failing error" \
  "[[ \"\$OUT\" == *'::warning::inngest-consumer'* ]]"
assert "T2 names the 30s deadline from the variable, never a literal 230" \
  "[[ \"\$OUT\" == *'no beat within 30s'* ]]"
assert "T2 does NOT tell the reader the probe is broken (the pre-#7587 instruction)" \
  "[[ \"\$OUT\" != *'the probe or the private-net path is broken'* ]]"
assert "T2 emits the observed status so 'never beat' is distinguishable" \
  "[[ \"\$OUT\" == *'status=pending'* ]]"
assert "T2 emits the monitor's updated_at as the second discriminator" \
  "[[ \"\$OUT\" == *'updated_at=2026-08-20T09:15:00.000Z'* ]]"
assert "T2 says a healthy feeder misses most windows, so the warning is not read as a fault" \
  "[[ \"\$OUT\" == *'five windows in six'* ]]"
assert_eq "T2 unpauses then rolls back — exactly two PATCHes" "2" "$(patch_count)"
assert "T2's FIRST PATCH is the unpause" \
  "[[ \"\$(patch_bodies | head -1)\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert "T2's LAST PATCH is paused:true — the inverse would leave it live-and-unfed" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T2 clears the state file once the rollback returns 2xx" "0" "$(state_lines)"

# --- T3: the wall-clock bound (Guard 2 row 6) -----------------------------------------------
echo "--- T3 the deadline is wall clock, not a sleep tally"
case_setup t3
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
FAKE_CURL_COST=15 run_sut
assert_eq "T3 exits 1 — a zot-consumer that never beats is fatal, unlike inngest" "1" "$RC"
e_t3="$(reported_elapsed 230)"
assert "T3 reports an elapsed at all" "[[ -n '$e_t3' ]]"
# Correct accounting stops one iteration past the deadline: 230 <= reported <= 230 + (10 + 15).
assert "T3 reports an elapsed inside one iteration of the 230s deadline" \
  "[[ '${e_t3:-99999}' -ge 230 && '${e_t3:-99999}' -le 255 ]]"
# The OBSERVED clock is the assertion that can actually see the defect. Correct: ~370s
# (arm GET+PATCH 30, ten 25s iterations 250, rollback 15, five trailing GETs 75).
# Pre-#7587 sleep-tally: ~695s, because it needs 23 iterations to tally 230.
assert "T3 the OBSERVED clock stays under 450s — the reported number alone cannot see this" \
  "[[ \$(observed_clock) -le 450 ]]"
assert "T3 positive control: the clock did advance past the deadline" "[[ \$(observed_clock) -ge 230 ]]"

# --- T4: a beat lands inside the window -----------------------------------------------------
echo "--- T4 a real beat lands: ARMED, and the id leaves the books"
case_setup t4
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '10'     > "$FAKE_STATE/$ID_INNGEST.upat"   # flips to up once the clock passes 10s
FAKE_CURL_COST=1 run_sut
assert_eq "T4 exits 0" "0" "$RC"
assert "T4 declares the monitor ARMED on a measured beat" "[[ \"\$OUT\" == *'a real beat landed. ARMED'* ]]"
assert_eq "T4 issues ONLY the unpause — no rollback on a successful arm" "1" "$(patch_count)"
assert "T4's single PATCH is the unpause" \
  "[[ \"\$(patch_bodies | head -1)\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert_eq "T4 removes the id from the state file on reaching up" "0" "$(state_lines)"

# --- T5: the rollback itself fails ----------------------------------------------------------
echo "--- T5 the rollback PATCH fails: the id STAYS on the sweep's books and the apply reds"
case_setup t5
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"   # the ROLLBACK fails; the unpause succeeds
run_sut
assert_eq "T5 exits 1 even for the SOFT caller — a failed rollback is about the arming" "1" "$RC"
assert "T5 reached the rollback (positive control: the unpause did succeed)" \
  "[[ \"\$(patch_bodies | head -1)\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert "T5 says the monitor is unpaused-and-unfed" "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
assert "T5 does NOT emit the soft ::warning:: (that would leave the job green)" \
  "[[ \"\$OUT\" != *'::warning::inngest-consumer'* ]]"
assert_eq "T5 leaves exactly the failed id on the re-pause sweep's books" "1" "$(state_lines)"
assert "T5's remaining id is the right one" "[[ \"\$(cat '$STATEFILE')\" == '$ID_INNGEST' ]]"

# --- T6: per-id removal, not truncation -----------------------------------------------------
echo "--- T6 two arms unpaused, one rollback fails: the file keeps ONE id, not zero and not two"
case_setup t6
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_sut
assert_eq "T6 exits 1" "1" "$RC"
assert_eq "T6 keeps exactly one id" "1" "$(state_lines)"
assert "T6 keeps the FAILED rollback's id, not the successful one" \
  "[[ \"\$(cat '$STATEFILE')\" == '$ID_INNGEST' ]]"

# --- T7: a GET that fails is not a feeder verdict --------------------------------------------
echo "--- T7 GET failure is 'the gate could not do its job', never a rollback"
case_setup t7
printf '%s\n' "$ID_ZOT1" > "$FAKE_GET_FAIL"
run_sut
assert_eq "T7 exits 1" "1" "$RC"
assert "T7 names the failing GET" "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7 issues no PATCH — nothing was ever unpaused" "0" "$(patch_count)"
assert_eq "T7 writes no state" "0" "$(state_lines)"

# --- T8: an address absent from tfstate is a no-op --------------------------------------------
echo "--- T8 git_data_prd absent from the merge-path tfstate"
case_setup t8
write_tfstate "$TFSTATE" "$ID_GITDATA"
run_sut
assert_eq "T8 exits 0" "0" "$RC"
assert "T8 reports the absent address by name" "[[ \"\$OUT\" == *'git-data-prd: not present in tfstate'* ]]"
assert_eq "T8 still arms the other five" "5" \
  "$(printf '%s' "$OUT" | grep -c 'already armed (status=up)')"

# --- T9: a half-configured invocation refuses ------------------------------------------------
echo "--- T9 missing contract env fails closed"
case_setup t9
for missing in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED; do
  out="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://uptime.betterstack.test/api/v2" \
        env -u "$missing" bash "$SUT" 2>&1)"
  rc=$?
  assert_eq "T9 refuses with rc=1 when $missing is unset" "1" "$rc"
  assert "T9 names $missing in the refusal" "[[ \"\$out\" == *'$missing is unset'* ]]"
done

# --- Mutation battery -------------------------------------------------------------------------
# Each row mutates a COPY of the SUT and requires a verdict this suite asserts to CHANGE. A guard
# that cannot be driven RED is vacuous; and a mutation that does not LAND reports the baseline,
# which is indistinguishable from a pass — so every row asserts the edit applied before running it.
echo "--- M mutation battery (each row must change a verdict this suite asserts)"
MUTANT=""
mutate() {  # <name> <sed-expr> -> 0 and sets MUTANT, or 1
  # Separate `local` statements deliberately: `local a=$1 b=$WORK/$a` expands EVERY argument
  # before the builtin runs, so `$a` is unbound there and `set -u` kills the function.
  local name="$1"
  local expr="$2"
  local mutant="$WORK/mutant-$name.sh"
  cp "$SUT" "$mutant" || { echo "FATAL: mutation copy failed for $name"; exit 2; }
  sed -i "$expr" "$mutant" || { echo "FATAL: sed failed for $name"; exit 2; }
  if cmp -s "$SUT" "$mutant"; then
    fail "M-$name mutation LANDED" "sed [$expr] changed nothing — the row would test the baseline"
    return 1
  fi
  pass "M-$name mutation landed against a pristine copy"
  MUTANT="$mutant"
}

# M1 — revert the wall-clock accounting to the pre-#7587 sleep tally (Guard 2 row 6).
if mutate wallclock 's|elapsed=\$(( \$(now_s) - started ))|elapsed=$(( elapsed + ARM_POLL_INTERVAL_S ))|g'; then
  case_setup m1
  printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
  FAKE_CURL_COST=15 run_sut "$MUTANT"
  assert "M1 RED: the sleep-tally blows T3's 450s observed-clock bound (measured $(observed_clock)s)" \
    "[[ \$(observed_clock) -gt 450 ]]"
  assert "M1 and it does so while REPORTING a compliant elapsed ($(reported_elapsed 230)s) — which is why T3 asserts the clock" \
    "[[ '$(reported_elapsed 230)' -le 255 ]]"
fi

# M2 — flip the rollback to paused:false (Guard 2 row 7 at the script layer).
if mutate unpause-rollback 's|hb_patch_paused "\$id" true|hb_patch_paused "$id" false|'; then
  case_setup m2
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  run_sut "$MUTANT"
  assert "M2 RED: the terminal PATCH is no longer paused:true" \
    "[[ \"\$(patch_bodies | tail -1)\" != '$ID_INNGEST {\"paused\":true}' ]]"
fi

# M3 — stop recording the id at the unpause, which is what a "remove on attempt" design amounts to.
if mutate no-state-add 's|^  state_add "\$id"$|  : "state_add removed by mutation"|'; then
  case_setup m3
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert "M3 RED: a failed rollback no longer leaves the id on the sweep's books (T5 would be vacuous)" \
    "[[ \$(state_lines) -eq 0 ]]"
fi

# M4 — soft-land a FAILED rollback back to rc=2, the pre-#7587 behaviour.
if mutate soft-failed-rollback 's|^    return 1$|    return 2|'; then
  case_setup m4
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert_eq "M4 RED: the apply job goes GREEN while a monitor is live-and-unfed" "0" "$RC"
fi

# M5 — restore the 230s inngest deadline.
if mutate deadline-230 's|^ARM_INNGEST_DEADLINE=30$|ARM_INNGEST_DEADLINE=230|'; then
  case_setup m5
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert "M5 RED: the inngest arm advertises its old 230s budget again" \
    "[[ \"\$OUT\" == *'no beat within 230s'* ]]"
  assert "M5 and burns it: the observed clock passes 230s" "[[ \$(observed_clock) -ge 230 ]]"
fi

# M6 — the anti-vacuity control. An UNMUTATED copy, run through the same harness, must still be
# GREEN; without it a red baseline is indistinguishable from a caught mutation.
cp "$SUT" "$WORK/mutant-control.sh" || { echo "FATAL: control copy failed"; exit 2; }
case_setup m6
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CURL_COST=15 run_sut "$WORK/mutant-control.sh"
assert_eq "M6 control: the UNMUTATED copy still soft-lands at rc=0" "0" "$RC"
assert "M6 control: and still advertises the 30s deadline" "[[ \"\$OUT\" == *'no beat within 30s'* ]]"

echo
echo "arm-heartbeats: ${PASS} passed, ${FAIL} failed ($((PASS + FAIL)) assertions)"
# MINIMUM-CARDINALITY FLOOR. A harness whose case loop silently ran nothing would otherwise report
# "0 failed" and read as success. Absolute and hand-ratcheted — there is no second producer here
# to derive it from.
if [[ $((PASS + FAIL)) -lt 55 ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran — the suite is narrowed or a case aborted early."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
