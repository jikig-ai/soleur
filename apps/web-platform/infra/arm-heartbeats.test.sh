#!/usr/bin/env bash
# Behavioural tests for the measured-beat ARM gate and its re-pause sweep
# (apps/web-platform/infra/arm-heartbeats.sh, #7587/#7659).
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
# THE SWEEP IS DRIVEN THE SAME WAY (#7659). It shipped as bash inside the sibling step's YAML
# scalar, guarded by regexes over the step text — which is how an `exit 1` assertion came to be
# satisfied by an unrelated `exit 1` several lines away. It is now `arm-heartbeats.sh --sweep` and
# cases S1–S7 below execute its loop, its arithmetic, its summary line, its outcome vocabulary and
# its fail-not-annotate branch.
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
# THE FAKE `curl` MODELS HTTP STATUS, NOT ONLY TRANSPORT (#7656 C4). It used to dispatch on method,
# URL and body and IGNORE every flag, which made three separate dependencies structurally
# unexpressible: `-f` (without it curl exits 0 on a 5xx, so a rollback that got HTTP 500 read as
# success and the id left the sweep's books), the `Authorization` header, and `--max-time`. The
# stub now:
#   * REQUIRES `--max-time` and a non-empty `Authorization: Bearer …`, and `exit 64`s / answers 401
#     without them, so deleting either from the SUT reds this suite;
#   * carries a per-id, per-method HTTP STATUS fixture, so a 500 on the rollback is expressible;
#   * honours `-f` (fail on >= 400) and `-o /dev/null -w '%{http_code}'` (print the code, not the
#     body), so both curl calling conventions in the SUT are modelled rather than assumed.
# It still `exit 64`s when handed no URL or an unrecognised PATCH body, so a SUT that starts
# querying the wrong thing is detectable rather than silently served the same fixture (the
# PATH-shimmed-fake trap, #7081). Monitor ids are synthesized (`cq-test-fixtures-synthesized-only`);
# no real Better Stack id appears in this file.
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

echo "=== ARM gate (arm-heartbeats.sh, #7587/#7659) behavioural tests ==="
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
# Fake Better Stack heartbeats API. Dispatches on ARGV (flags + method + URL + body), NOT on
# argument count: a stub that answers identically regardless of what it was asked cannot detect a
# SUT querying the wrong thing, and a fixture keyed per id is what makes "one clean, one dirty"
# real. It also models the HTTP STATUS, which is what makes `-f` and the `%{http_code}` convention
# testable rather than assumed (#7656 C4).
args=("$@")
url=""; method="GET"; data=""; auth=""; maxtime=""; failflag=0; writeout=""; outfile=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -X)          method="${args[i+1]:-}" ;;
    --data-raw)  data="${args[i+1]:-}" ;;
    -H)          [[ "${args[i+1]:-}" == Authorization:* ]] && auth="${args[i+1]:-}" ;;
    --max-time)  maxtime="${args[i+1]:-}" ;;
    -w)          writeout="${args[i+1]:-}" ;;
    -o)          outfile="${args[i+1]:-}" ;;
    -f|-fsS|-sSf) failflag=1 ;;
    https://*)   url="${args[i]}" ;;
  esac
done
# HARNESS-FIDELITY REFUSALS. These are not vendor behaviours — they are the stub asserting that the
# SUT still calls it the way the contract says. A round-trip with no ceiling is exactly what the
# wall-clock ladder cannot survive, and an unauthenticated call is not a call this API answers.
if [[ -z "$url" ]]; then
  echo "fake curl: invoked with no URL argument" >&2
  exit 64
fi
if [[ -z "$maxtime" ]]; then
  echo "fake curl: invoked with no --max-time — every round-trip must carry a ceiling" >&2
  exit 64
fi
id="${url##*/}"

# Every round-trip costs wall clock. This is the term the pre-#7587 sleep-tally ignored.
c=$(cat "$FAKE_CLOCK")
now=$(( c + ${FAKE_CURL_COST:-15} ))
echo "$now" > "$FAKE_CLOCK"

printf '%s\t%s\t%s\t%s\n' "$now" "$method" "$id" "$data" >> "$FAKE_CALLS"

emit() {  # <http-status> <body>
  local code="$1" body="$2"
  if [[ -n "$writeout" ]]; then
    # `-o <file> -w '%{http_code}'`: the body goes to the file, the CODE goes to stdout. curl
    # still exits 0 on a 4xx/5xx in this mode unless -f is also given.
    [[ -z "$outfile" ]] || printf '%s' "$body" > "$outfile" 2>/dev/null
    printf '%s' "${writeout//'%{http_code}'/$code}"
    if [[ "$failflag" -eq 1 && "$code" -ge 400 ]]; then exit 22; fi
    exit 0
  fi
  if [[ "$failflag" -eq 1 && "$code" -ge 400 ]]; then
    echo "fake curl: HTTP $code (--fail)" >&2
    exit 22
  fi
  # WITHOUT -f curl prints the error body and exits 0. This is the door C4 named.
  printf '%s' "$body"
  exit 0
}

if [[ -z "$auth" || "$auth" == "Authorization: Bearer" || "$auth" == "Authorization: Bearer " ]]; then
  emit 401 '{"errors":"unauthorized"}'
fi

status_for() {  # <method> -> the fixture HTTP status, default 200
  local f="$FAKE_HTTP/$id.$1"
  if [[ -r "$f" ]]; then cat "$f"; else echo 200; fi
}

case "$method" in
  GET)
    if grep -qxF -- "$id" "$FAKE_GET_FAIL" 2>/dev/null; then emit 500 '{"errors":"boom"}'; fi
    # A GET that succeeds and THEN fails: "<id> <n>" means every GET after the nth returns 500.
    n_after="$(awk -v i="$id" '$1==i{print $2}' "$FAKE_GET_FAIL_AFTER" 2>/dev/null | head -1)"
    if [[ -n "$n_after" ]]; then
      seen="$(awk -F'\t' -v i="$id" '$2=="GET" && $3==i' "$FAKE_CALLS" | grep -c '')"
      if [[ "$seen" -gt "$n_after" ]]; then emit 500 '{"errors":"boom"}'; fi
    fi
    if grep -qxF -- "$id" "$FAKE_EMPTY_BODY" 2>/dev/null; then emit 200 ''; fi
    if grep -qxF -- "$id" "$FAKE_BAD_JSON" 2>/dev/null; then emit 200 '{"data":{"id":"x","attributes":{}}}'; fi
    status="$(cat "$FAKE_STATE/$id.status" 2>/dev/null || true)"
    [[ -n "$status" ]] || { echo "fake curl: no fixture for id $id" >&2; exit 64; }
    upat="$(cat "$FAKE_STATE/$id.upat" 2>/dev/null || true)"
    if [[ -n "$upat" && "$now" -ge "$upat" ]]; then status="up"; fi
    updated="$(cat "$FAKE_STATE/$id.updated" 2>/dev/null || echo "2026-08-20T00:00:00.000Z")"
    emit "$(status_for get)" "$(printf '{"data":{"id":"%s","attributes":{"status":"%s","updated_at":"%s"}}}' "$id" "$status" "$updated")"
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
    if grep -qxF -- "$id $want" "$FAKE_PATCH_FAIL" 2>/dev/null; then emit 500 '{"errors":"boom"}'; fi
    # "<id> <want> <code>": only the FIRST matching PATCH answers <code>; later ones succeed. This
    # is what makes a RETRY distinguishable from a first-attempt success (#7658 E8).
    once="$(awk -v i="$id" -v w="$want" '$1==i && $2==w{print $3}' "$FAKE_PATCH_FAIL_ONCE" 2>/dev/null | head -1)"
    if [[ -n "$once" ]]; then
      seen="$(awk -F'\t' -v i="$id" '$2=="PATCH" && $3==i && $4 ~ /"paused":'"$want"'/' "$FAKE_CALLS" | grep -c '')"
      if [[ "$seen" -le 1 ]]; then emit "$once" '{"errors":"boom"}'; fi
    fi
    if [[ "$want" == "false" ]]; then printf 'pending' > "$FAKE_STATE/$id.status"
    else printf 'paused' > "$FAKE_STATE/$id.status"; fi
    emit "$(status_for "patch-$want")" "$(printf '{"data":{"id":"%s"}}' "$id")"
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
FAKE_GET_FAIL_AFTER="$WORK/getfailafter-selftest"; : > "$FAKE_GET_FAIL_AFTER"
FAKE_PATCH_FAIL="$WORK/patchfail-selftest"; : > "$FAKE_PATCH_FAIL"
FAKE_PATCH_FAIL_ONCE="$WORK/patchfailonce-selftest"; : > "$FAKE_PATCH_FAIL_ONCE"
FAKE_EMPTY_BODY="$WORK/emptybody-selftest"; : > "$FAKE_EMPTY_BODY"
FAKE_BAD_JSON="$WORK/badjson-selftest"; : > "$FAKE_BAD_JSON"
FAKE_STATE="$WORK/state-selftest"; mkdir -p "$FAKE_STATE"
FAKE_HTTP="$WORK/http-selftest"; mkdir -p "$FAKE_HTTP"
export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_GET_FAIL_AFTER FAKE_PATCH_FAIL FAKE_PATCH_FAIL_ONCE FAKE_EMPTY_BODY FAKE_BAD_JSON FAKE_STATE FAKE_HTTP
PATH="$BIN:$PATH" bash -c 'curl -fsS --max-time 15 -H "Authorization: Bearer x"' >/dev/null 2>&1
assert_eq "the fake curl exits 64 when handed no URL (argv fidelity, not a fixture echo)" "64" "$?"
PATH="$BIN:$PATH" bash -c 'curl -fsS -H "Authorization: Bearer x" https://x.test/heartbeats/1' >/dev/null 2>&1
assert_eq "the fake curl exits 64 when the call carries no --max-time" "64" "$?"
PATH="$BIN:$PATH" bash -c 'curl -fsS --max-time 15 -X PATCH -H "Authorization: Bearer x" https://x.test/heartbeats/1 --data-raw "{}"' >/dev/null 2>&1
assert_eq "the fake curl exits 64 on a PATCH body it does not recognise" "64" "$?"
printf 'up' > "$FAKE_STATE/1.status"
PATH="$BIN:$PATH" bash -c 'curl -fsS --max-time 15 https://x.test/heartbeats/1' >/dev/null 2>&1
assert_eq "the fake curl answers 401 (and -f turns that into rc 22) with no Authorization header" "22" "$?"
printf '500' > "$FAKE_HTTP/1.get"
PATH="$BIN:$PATH" bash -c 'curl -fsS --max-time 15 -H "Authorization: Bearer x" https://x.test/heartbeats/1' >/dev/null 2>&1
assert_eq "the fake curl honours -f: a 500 is rc 22" "22" "$?"
# shellcheck disable=SC2034  # consumed by `assert` through eval
out_nf="$(PATH="$BIN:$PATH" bash -c 'curl -sS --max-time 15 -H "Authorization: Bearer x" https://x.test/heartbeats/1' 2>/dev/null; echo "rc=$?")"
assert "the fake curl WITHOUT -f exits 0 on a 500 and prints the error body (the C4 door)" \
  "[[ \"\$out_nf\" == *'rc=0'* ]]"
code_out="$(PATH="$BIN:$PATH" bash -c "curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H 'Authorization: Bearer x' https://x.test/heartbeats/1" 2>/dev/null)"
assert_eq "the fake curl honours -o/-w and prints the STATUS CODE, not the body" "500" "$code_out"
rm -f "$FAKE_HTTP/1.get"
# The probes above legitimately advanced the clock, so re-zero it rather than asserting against a
# number several probes contributed to.
echo 0 > "$FAKE_CLOCK"
PATH="$BIN:$PATH" bash -c 'sleep 7'
assert_eq "the fake sleep MOVES the clock rather than no-opping" "7" "$(cat "$FAKE_CLOCK")"
assert_eq "the fake date reads that clock" "7" "$(PATH="$BIN:$PATH" bash -c 'date +%s')"

# --- the declared env contract is discoverable (#7659 F3) ------------------------------------
# shellcheck disable=SC2034  # consumed by `assert` through eval
help_out="$(PATH="$BIN:$PATH" bash "$SUT" --help 2>&1)"
help_rc=$?
assert_eq "--help exits 0" "0" "$help_rc"
for var in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED BS_API_BASE ARM_POLL_INTERVAL_S; do
  assert "--help documents $var" "[[ \"\$help_out\" == *'$var'* ]]"
done
for word in noop repaused partial mint-unreadable; do
  assert "--help closes the sweep outcome vocabulary at '$word'" "[[ \"\$help_out\" == *'$word'* ]]"
done
# shellcheck disable=SC2034  # consumed by `assert` through eval
bad_out="$(PATH="$BIN:$PATH" bash "$SUT" --wat 2>&1)"; bad_rc=$?
assert_eq "an unknown argument refuses with rc=1 rather than silently arming" "1" "$bad_rc"
assert "…and names the argument it rejected" "[[ \"\$bad_out\" == *'--wat'* ]]"

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
  mkdir -p "$CASE/state" "$CASE/http" || { echo "FATAL: case setup failed for $1"; exit 2; }
  FAKE_CLOCK="$CASE/clock"; echo 0 > "$FAKE_CLOCK"
  FAKE_CALLS="$CASE/calls"; : > "$FAKE_CALLS"
  FAKE_GET_FAIL="$CASE/getfail"; : > "$FAKE_GET_FAIL"
  FAKE_GET_FAIL_AFTER="$CASE/getfailafter"; : > "$FAKE_GET_FAIL_AFTER"
  FAKE_PATCH_FAIL="$CASE/patchfail"; : > "$FAKE_PATCH_FAIL"
  FAKE_PATCH_FAIL_ONCE="$CASE/patchfailonce"; : > "$FAKE_PATCH_FAIL_ONCE"
  FAKE_EMPTY_BODY="$CASE/emptybody"; : > "$FAKE_EMPTY_BODY"
  FAKE_BAD_JSON="$CASE/badjson"; : > "$FAKE_BAD_JSON"
  FAKE_STATE="$CASE/state"
  FAKE_HTTP="$CASE/http"
  STATEFILE="$CASE/armed-unconfirmed"
  SUMMARY="$CASE/summary"; : > "$SUMMARY"
  TFSTATE="$CASE/tfstate.json"
  write_tfstate "$TFSTATE"
  local id
  for id in "$ID_ZOT1" "$ID_NIC1" "$ID_ZOT2" "$ID_NIC2" "$ID_GITDATA" "$ID_INNGEST"; do
    printf 'up' > "$FAKE_STATE/$id.status"
  done
  export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_GET_FAIL_AFTER FAKE_PATCH_FAIL \
         FAKE_PATCH_FAIL_ONCE FAKE_EMPTY_BODY FAKE_BAD_JSON FAKE_STATE FAKE_HTTP
}

run_sut() {  # [sut-path] -> sets OUT and RC
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token \
        TFSTATE_JSON="$TFSTATE" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://uptime.betterstack.test/api/v2" \
        ARM_POLL_INTERVAL_S=10 \
        bash "$sut" --arm 2>&1)"
  RC=$?
}
run_sut_defaults() {  # like run_sut but exercises the OPTIONAL vars' documented defaults
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token \
        TFSTATE_JSON="$TFSTATE" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        bash "$sut" --arm 2>&1)"
  RC=$?
}
run_sweep() {  # [sut-path] -> sets OUT and RC; SWEEP_TOKEN may be set to "" by a case
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN="${SWEEP_TOKEN-fake-token}" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://uptime.betterstack.test/api/v2" \
        GITHUB_STEP_SUMMARY="$SUMMARY" \
        bash "$sut" --sweep 2>&1)"
  RC=$?
}
patch_bodies() { awk -F'\t' '$2=="PATCH"{print $3" "$4}' "$FAKE_CALLS"; }
patch_count()  { patch_bodies | grep -c '' ; }
get_urls()     { awk -F'\t' '$2=="GET"{print $3}' "$FAKE_CALLS"; }
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

# --- T1b: the op/state gate SKIP SET is every not-paused status, not just `up` ---------------
# Every fixture used to start `up`, so narrowing the gate to `== "up"` was invisible — and it
# would unpause a monitor sitting `down` and poll it to its deadline on every apply (#7656 C5).
echo "--- T1b a monitor sitting down / pending is skipped, not unpaused"
case_setup t1b
printf 'down'    > "$FAKE_STATE/$ID_ZOT1.status"
printf 'pending' > "$FAKE_STATE/$ID_NIC1.status"
run_sut
assert_eq "T1b exits 0" "0" "$RC"
assert "T1b treats a DOWN monitor as already armed (the gate skips every non-paused status)" \
  "[[ \"\$OUT\" == *'already armed (status=down)'* ]]"
assert "T1b treats a PENDING monitor the same way" \
  "[[ \"\$OUT\" == *'already armed (status=pending)'* ]]"
assert_eq "T1b issues NO PATCH — neither monitor is unpaused" "0" "$(patch_count)"
assert "T1b enters no poll loop for either (observed clock is six GETs)" \
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
# The fixture makes an unpaused-but-unfed monitor read `pending`; what is asserted is that the SUT
# ECHOES whatever status it observed, not that `pending` is the value Better Stack would return —
# this change measured no vendor semantics and the message claims none.
assert "T2 echoes the status Better Stack reported AT ROLLBACK" \
  "[[ \"\$OUT\" == *'status=pending'* ]]"
assert "T2 emits the monitor's updated_at" \
  "[[ \"\$OUT\" == *'updated_at=2026-08-20T09:15:00.000Z'* ]]"
# #7658 E2: the retracted claim. `updated_at` is a record-mutation timestamp and this run PATCHes
# the record, so the pair cannot separate 'never beat' from 'not due yet' — and the repo measured
# no such semantics.
assert "T2 does NOT claim the two fields discriminate a missed beat (unmeasured vendor semantics)" \
  "[[ \"\$OUT\" != *'separate '* ]]"
assert "T2 warns the reader off reading a beat into updated_at" \
  "[[ \"\$OUT\" == *'record-mutation timestamp'* ]]"
assert "T2 says a healthy feeder misses most windows, so the warning is not read as a fault" \
  "[[ \"\$OUT\" == *'five windows in six'* ]]"
assert_eq "T2 unpauses then rolls back — exactly two PATCHes" "2" "$(patch_count)"
assert "T2's FIRST PATCH is the unpause" \
  "[[ \"\$(patch_bodies | head -1)\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert "T2's LAST PATCH is paused:true — the inverse would leave it live-and-unfed" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T2 clears the state file once the rollback returns 2xx" "0" "$(state_lines)"

# --- T2b: a rollback that gets HTTP 500 is NOT a successful rollback -------------------------
# `curl -fsS` used to be the whole predicate. Without -f curl exits 0 on a 5xx, so this case is
# the door C4 named: the id would leave the books and the monitor would stay live-and-unfed under
# a GREEN apply. `hb_patch_paused` now reads `%{http_code}`.
echo "--- T2c the rollback PATCH returns HTTP 500"
case_setup t2c
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '500' > "$FAKE_HTTP/$ID_INNGEST.patch-true"
run_sut
assert_eq "T2c exits 1 — a 5xx rollback is a FAILED rollback, not a soft landing" "1" "$RC"
assert "T2c names the HTTP status in the error" "[[ \"\$OUT\" == *'HTTP 500'* ]]"
assert_eq "T2c leaves the id on the re-pause sweep's books" "1" "$(state_lines)"

# --- T2d: an unpause that gets HTTP 500 never puts the id on the books -----------------------
echo "--- T2d the unpause PATCH returns HTTP 500"
case_setup t2d
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '500' > "$FAKE_HTTP/$ID_INNGEST.patch-false"
run_sut
assert_eq "T2d exits 1" "1" "$RC"
assert "T2d says the unpause failed, with its status" \
  "[[ \"\$OUT\" == *'PATCH paused=false FAILED (HTTP 500)'* ]]"
assert_eq "T2d writes no state — nothing was ever unpaused" "0" "$(state_lines)"

# --- T2e/T2f: the rollback retries a transient, and does NOT retry a 4xx (#7658 E8) -----------
# The rollback is the one write whose failure reds a routine apply, and while #7228 is open the
# inngest arm executes it on EVERY merge — ~990 unretried round-trips a year, any one of which
# could raise a false ops alarm on a lost packet.
echo "--- T2e a 5xx rollback that succeeds on the retry is NOT a failed rollback"
case_setup t2e
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true 500\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL_ONCE"
FAKE_CURL_COST=1 run_sut
assert_eq "T2e exits 0 — a transient lost round-trip is not an unpaused-and-unfed monitor" "0" "$RC"
assert "T2e says it retried, rather than retrying silently" \
  "[[ \"\$OUT\" == *'returned HTTP 500 — retrying once'* ]]"
assert "T2e does NOT declare the monitor unpaused-and-unfed" "[[ \"\$OUT\" != *'unpaused-and-unfed'* ]]"
assert_eq "T2e issues three PATCHes: unpause, failed rollback, successful rollback" "3" "$(patch_count)"
assert "T2e's LAST PATCH is paused:true" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T2e clears the books" "0" "$(state_lines)"
assert "T2e still soft-lands with the feeder verdict (the arm itself worked)" \
  "[[ \"\$OUT\" == *'no beat within 30s'* ]]"

echo "--- T2f a 403 rollback is NOT retried: a 4xx does not fix itself on an immediate second call"
case_setup t2f
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '403' > "$FAKE_HTTP/$ID_INNGEST.patch-true"
FAKE_CURL_COST=1 run_sut
assert_eq "T2f exits 1" "1" "$RC"
assert_eq "T2f issues exactly two PATCHes — no wasted retry" "2" "$(patch_count)"
assert "T2f does not claim to have retried" "[[ \"\$OUT\" != *'retrying once'* ]]"
assert "T2f names the status and the attempt count" "[[ \"\$OUT\" == *'HTTP 403'* ]]"

# --- T3: the wall-clock bound (Guard 2 row 6) -----------------------------------------------
echo "--- T3 the deadline is wall clock, not a sleep tally"
case_setup t3
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
FAKE_CURL_COST=15 run_sut
assert_eq "T3 exits 1 — a zot-consumer that never beats is fatal, unlike inngest" "1" "$RC"
e_t3="$(reported_elapsed 200)"
assert "T3 reports an elapsed at all" "[[ -n '$e_t3' ]]"
# Correct accounting stops one iteration past the deadline: 200 <= reported <= 200 + (10 + 15).
assert "T3 reports an elapsed inside one iteration of the 200s deadline" \
  "[[ '${e_t3:-99999}' -ge 200 && '${e_t3:-99999}' -le 225 ]]"
# The OBSERVED clock is the assertion that can actually see the defect. Correct: ~340s
# (arm GET+PATCH 30, nine 25s iterations 225, rollback 15, five trailing GETs 75).
# Pre-#7587 sleep-tally: ~620s, because it needs 20 iterations to tally 200.
assert "T3 the OBSERVED clock stays under 420s — the reported number alone cannot see this" \
  "[[ \$(observed_clock) -le 420 ]]"
assert "T3 positive control: the clock did advance past the deadline" "[[ \$(observed_clock) -ge 200 ]]"

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
assert "T5 does NOT emit the soft FEEDER verdict (that would leave the job green)" \
  "[[ \"\$OUT\" != *'no beat within'* ]]"
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

# --- T6b: state_remove cannot install a TRUNCATED file (#7658 E3) -----------------------------
# `grep -vxF … > keep || true` swallowed grep's exit >= 2 as readily as its exit 1, so an
# unreadable source produced an EMPTY `keep` that `mv -f` then installed over the whole state
# file — dropping a PRIOR arm's failed-rollback id, which is the only reason the file ever holds
# more than one line, and leaving that monitor live-and-unfed.
echo "--- T6b a state file that cannot be read is left INTACT, never replaced with nothing"
case_setup t6b
printf '%s\n%s\n' "$ID_ZOT2" "$ID_NIC2" > "$STATEFILE"
chmod 000 "$STATEFILE"
# shellcheck disable=SC2034  # consumed by `assert` through eval
sr_out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" \
  ARMED_UNCONFIRMED="$STATEFILE" BS_API_BASE="https://uptime.betterstack.test/api/v2" \
  bash -c 'source /dev/stdin <<< "$(sed -n "/^state_remove()/,/^}/p" "$1")"; state_remove 999; echo "rc=$?"' _ "$SUT" 2>&1)"
chmod 644 "$STATEFILE"
assert "T6b state_remove REFUSES rather than returning 0 on an unreadable source" \
  "[[ \"\$sr_out\" == *'rc=1'* ]]"
assert "T6b it says so loudly" "[[ \"\$sr_out\" == *'::error::'* ]]"
assert_eq "T6b the state file still holds BOTH ids" "2" "$(state_lines)"
assert "T6b no .keep temp file is left behind" \
  "[[ -z \"\$(find '$CASE' -name 'armed-unconfirmed.keep.*' 2>/dev/null)\" ]]"

# --- T7: a GET that fails is not a feeder verdict --------------------------------------------
echo "--- T7 GET failure is 'the gate could not do its job', never a rollback"
case_setup t7
printf '%s\n' "$ID_ZOT1" > "$FAKE_GET_FAIL"
run_sut
assert_eq "T7 exits 1" "1" "$RC"
assert "T7 names the failing GET" "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7 issues no PATCH — nothing was ever unpaused" "0" "$(patch_count)"
assert_eq "T7 writes no state" "0" "$(state_lines)"

# --- T7b: hb_fetch fails CLOSED on an empty 200 and on a 200 with no status -------------------
# Both guards were unreachable: no fixture could produce a 200 whose body was empty or whose JSON
# lacked `.data.attributes.status`, so `|| return 1` could be deleted from either with both suites
# green (#7656 C5).
echo "--- T7b a 200 with an empty body, and a 200 with no status field, both fail CLOSED"
case_setup t7b
printf '%s\n' "$ID_ZOT1" > "$FAKE_EMPTY_BODY"
run_sut
assert_eq "T7b (empty body) exits 1" "1" "$RC"
assert "T7b (empty body) reports it as a failed lookup, not as a status" \
  "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7b (empty body) issues no PATCH" "0" "$(patch_count)"
case_setup t7c
printf '%s\n' "$ID_ZOT1" > "$FAKE_BAD_JSON"
run_sut
assert_eq "T7c (200 with no .status) exits 1" "1" "$RC"
assert "T7c (200 with no .status) reports a failed lookup rather than arming on an empty status" \
  "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7c (200 with no .status) issues no PATCH" "0" "$(patch_count)"

# --- T7d: a MID-LOOP loss of visibility is not a feeder verdict (#7658 E1) --------------------
# The first GET succeeds (so the arm starts) and every later one fails. `ARM_LAST_STATUS` used to
# retain the PRE-UNPAUSE reading, so the terminal message reported `status=paused` as an
# observation — affirmatively wrong, since at rollback the monitor is unpaused — and a total loss
# of Better Stack visibility rendered as a benign feeder miss with the apply exiting 0.
echo "--- T7d every in-loop GET fails after the first: unknown, and rc=1 rather than a soft landing"
case_setup t7d
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s 1\n' "$ID_INNGEST" > "$FAKE_GET_FAIL_AFTER"
FAKE_CURL_COST=1 run_sut
assert_eq "T7d exits 1 — no status was read, so no assertion about the FEEDER is available" "1" "$RC"
assert "T7d does NOT report the stale pre-unpause status" "[[ \"\$OUT\" != *'status=paused'* ]]"
assert "T7d names the visibility loss explicitly" \
  "[[ \"\$OUT\" == *'every status read during the 30s poll FAILED'* ]]"
assert "T7d does NOT emit the soft feeder verdict" "[[ \"\$OUT\" != *'no beat within'* ]]"
assert "T7d still rolled the monitor back to paused" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T7d clears the books — the rollback did return 2xx" "0" "$(state_lines)"

# --- T7e: a vendor string cannot forge a workflow command (#7658 E7) --------------------------
echo "--- T7e a CR/LF inside updated_at cannot break out of the annotation"
case_setup t7e
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '2026-01-01T00:00:00Z\\n::error::FORGED-BY-VENDOR-STRING' > "$FAKE_STATE/$ID_INNGEST.updated"
FAKE_CURL_COST=1 run_sut
assert "T7e no line in the output BEGINS with the forged workflow command" \
  "! printf '%s' \"\$OUT\" | grep -q '^::error::FORGED-BY-VENDOR-STRING'"
assert "T7e the vendor text is still carried, inline, where it cannot be parsed as a command" \
  "[[ \"\$OUT\" == *'FORGED-BY-VENDOR-STRING'* ]]"

# --- T8: an address absent from tfstate is a no-op --------------------------------------------
echo "--- T8 git_data_prd absent from the merge-path tfstate"
case_setup t8
write_tfstate "$TFSTATE" "$ID_GITDATA"
run_sut
assert_eq "T8 exits 0" "0" "$RC"
assert "T8 reports the absent address by name" "[[ \"\$OUT\" == *'git-data-prd: not present in tfstate'* ]]"
assert_eq "T8 still arms the other five" "5" \
  "$(printf '%s' "$OUT" | grep -c 'already armed (status=up)')"

# --- T8b: a READABLE but CONTENTLESS tfstate refuses (#7658 E10) -------------------------------
echo "--- T8b a readable-but-empty tfstate is a refusal, not six silent skips and a green apply"
case_setup t8b
printf '{"values":{"root_module":{"resources":[]}}}\n' > "$TFSTATE"
run_sut
assert_eq "T8b exits 1" "1" "$RC"
assert "T8b says the state holds no resources" "[[ \"\$OUT\" == *'holds no resources'* ]]"
assert_eq "T8b issues no API call at all" "0" "$(get_urls | grep -c '' || true)"

# --- T9: a half-configured invocation refuses ------------------------------------------------
echo "--- T9 missing contract env fails closed"
case_setup t9
for missing in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED; do
  out="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://uptime.betterstack.test/api/v2" \
        env -u "$missing" bash "$SUT" --arm 2>&1)"
  rc=$?
  assert_eq "T9 refuses with rc=1 when $missing is unset" "1" "$rc"
  assert "T9 names $missing in the refusal" "[[ \"\$out\" == *'$missing is unset'* ]]"
done

# --- T10: the two OPTIONAL contract vars' documented defaults are exercised (#7659 F3) --------
# `run_sut` always exported both, so neither default was ever executed: `ARM_POLL_INTERVAL_S`
# could go `:-10 → :-1` (a 6x production API-call rate) and `BS_API_BASE` could point anywhere,
# with both suites green.
echo "--- T10 running with NEITHER optional var set exercises the shipped defaults"
case_setup t10
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CURL_COST=0 run_sut_defaults
assert_eq "T10 exits 0 (the soft inngest landing)" "0" "$RC"
# With cost 0 the clock advances only by the sleeps, so the observed clock IS the poll interval
# times the iteration count. A 30s deadline at the documented default of 10 is exactly 3 sleeps.
assert_eq "T10 the DEFAULT poll interval is 10s: a 30s deadline costs exactly 3 sleeps" "30" "$(observed_clock)"
# The GET COUNT is what a shrunken poll interval moves; the clock alone does not (30 sleeps of 1s
# reach 30 exactly as 3 sleeps of 10 do). Baseline: five no-op GETs + inngest's pre-loop GET +
# three in-loop polls = 9.
assert_eq "T10 the default interval costs exactly 9 GETs, not one per second" "9" "$(get_urls | grep -c '')"
assert "T10 the DEFAULT BS_API_BASE is the production Better Stack API" \
  "grep -q 'https://uptime.betterstack.com/api/v2/heartbeats/' <<< \"\$(grep -o 'BS_API_BASE:-[^}]*' '$SUT')/heartbeats/\""

# =================================================================================================
# --- S: the re-pause sweep (#7659) --------------------------------------------------------------
# =================================================================================================
# No suite executed the sweep at all before this: it was ~45 lines of bash inside a YAML scalar,
# and the ten regexes that "guarded" it included an `exit 1` assertion satisfied by an unrelated
# `exit 1` in the mint-unreadable branch.
echo "--- S1 nothing on the books: the modal case reports outcome=noop and exits 0"
case_setup s1
run_sweep
assert_eq "S1 exits 0" "0" "$RC"
assert "S1 reports outcome=noop rather than staying silent" "[[ \"\$OUT\" == *'outcome=noop'* ]]"
assert "S1 emits the structured tag as an ANNOTATION, which has a REST API" \
  "[[ \"\$OUT\" == *'::notice::heartbeat-repause-sweep armed=0 repaused=0 failed=0 outcome=noop'* ]]"
assert "S1 also writes the run summary block, so 'the counts are in the run summary' is TRUE" \
  "grep -q '^armed=0 repaused=0 failed=0 outcome=noop$' '$SUMMARY'"
assert_eq "S1 issues no API call" "0" "$(patch_count)"

echo "--- S2 two ids on the books, both re-pause cleanly"
case_setup s2
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
run_sweep
assert_eq "S2 exits 0" "0" "$RC"
assert_eq "S2 issues exactly two PATCHes" "2" "$(patch_count)"
assert "S2's PATCHes are both paused:true" \
  "[[ \"\$(patch_bodies | grep -c '{\"paused\":true}')\" == 2 ]]"
assert "S2 counts them: armed=2 repaused=2 failed=0" \
  "[[ \"\$OUT\" == *'armed=2 repaused=2 failed=0 outcome=repaused'* ]]"
assert "S2 names the ids it found, not just the count" \
  "[[ \"\$OUT\" == *\"$ID_ZOT1 $ID_NIC1\"* ]]"
assert "S2 says the previously-applied infrastructure is unaffected" \
  "[[ \"\$OUT\" == *'previously-applied infrastructure is unaffected'* ]]"

echo "--- S3 one of two returns HTTP 500: partial, and the step FAILS rather than annotating"
case_setup s3
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
run_sweep
assert_eq "S3 exits 1 — ::error:: does not fail a step, and a still-live monitor must red the run" "1" "$RC"
assert "S3 counts the split: armed=2 repaused=1 failed=1" \
  "[[ \"\$OUT\" == *'armed=2 repaused=1 failed=1 outcome=partial'* ]]"
assert "S3 names the id it could not re-pause, with its HTTP status" \
  "[[ \"\$OUT\" == *'heartbeat $ID_NIC1 returned HTTP 500'* ]]"
assert "S3 still re-paused the one it could (the loop does not abort at the first failure)" \
  "[[ \"\$OUT\" == *'re-paused heartbeat $ID_ZOT1'* ]]"
assert "S3 writes the partial outcome to the run summary too" \
  "grep -q 'outcome=partial' '$SUMMARY'"

echo "--- S4 the token could not be minted: mint-unreadable, and the IDS are printed"
case_setup s4
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
SWEEP_TOKEN="" run_sweep
assert_eq "S4 exits 1" "1" "$RC"
assert "S4 reports outcome=mint-unreadable" "[[ \"\$OUT\" == *'outcome=mint-unreadable'* ]]"
assert "S4 prints the monitor IDS — the only thing that lets an operator re-pause by hand" \
  "[[ \"\$OUT\" == *\"$ID_ZOT1 $ID_NIC1\"* ]]"
assert "S4 tells the operator where to click" "[[ \"\$OUT\" == *'Better Stack'* ]]"
assert_eq "S4 attempts no PATCH (it has no credential to attempt one with)" "0" "$(patch_count)"

echo "--- S5 the sweep is IDEMPOTENT: re-PATCHing an already-paused monitor is a no-op"
case_setup s5
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
run_sweep
assert_eq "S5 exits 0 — an already-paused monitor is still a clean re-pause" "0" "$RC"
assert "S5 counts it as re-paused" "[[ \"\$OUT\" == *'armed=1 repaused=1 failed=0'* ]]"
assert_eq "S5 the monitor is still paused afterwards" "paused" "$(cat "$FAKE_STATE/$ID_ZOT1.status")"

echo "--- S6 a blank line in the state file is skipped, not PATCHed as an empty id"
case_setup s6
printf '%s\n\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
run_sweep
assert_eq "S6 exits 0" "0" "$RC"
assert_eq "S6 issues two PATCHes, not three" "2" "$(patch_count)"

echo "--- S7 --sweep refuses when its one required var is unset"
case_setup s7
# shellcheck disable=SC2034  # consumed by `assert` through eval
s7_out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token env -u ARMED_UNCONFIRMED bash "$SUT" --sweep 2>&1)"
s7_rc=$?
assert_eq "S7 exits 1" "1" "$s7_rc"
assert "S7 names ARMED_UNCONFIRMED" "[[ \"\$s7_out\" == *'ARMED_UNCONFIRMED is unset'* ]]"

# --- Mutation battery -------------------------------------------------------------------------
# Each row mutates a COPY of the SUT and requires a verdict this suite asserts to CHANGE. A guard
# that cannot be driven RED is vacuous; and a mutation that does not LAND reports the baseline,
# which is indistinguishable from a pass — so every row asserts the edit applied, and asserts HOW
# MANY lines it applied to (#7656 C9: `s|^    return 1$|    return 2|` silently landed in three
# regions, and `cmp -s` reports only THAT the file differs, never where or how widely).
echo "--- M mutation battery (each row must change a verdict this suite asserts)"
MUTANT=""
mutate() {  # <name> <expected-changed-lines> <sed-expr> -> 0 and sets MUTANT, or 1
  # Separate `local` statements deliberately: `local a=$1 b=$WORK/$a` expands EVERY argument
  # before the builtin runs, so `$a` is unbound there and `set -u` kills the function.
  local name="$1"
  local want="$2"
  local expr="$3"
  local mutant="$WORK/mutant-$name.sh"
  local changed
  cp "$SUT" "$mutant" || { echo "FATAL: mutation copy failed for $name"; exit 2; }
  sed -i "$expr" "$mutant" || { echo "FATAL: sed failed for $name"; exit 2; }
  changed=$(diff <(cat "$SUT") <(cat "$mutant") | grep -c '^<' || true)
  if [[ "$changed" -eq 0 ]]; then
    fail "M-$name mutation LANDED" "sed [$expr] changed nothing — the row would test the baseline"
    return 1
  fi
  if [[ "$changed" -ne "$want" ]]; then
    fail "M-$name mutation landed on exactly $want line(s)" \
      "sed [$expr] changed $changed lines — the row does not mutate what its title says"
    return 1
  fi
  pass "M-$name mutation landed on exactly $want line(s) of a pristine copy"
  MUTANT="$mutant"
}

# M1 — revert the wall-clock accounting to the pre-#7587 sleep tally (Guard 2 row 6).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate wallclock 1 's|elapsed=\$(( \$(now_s) - started ))|elapsed=$(( elapsed + ARM_POLL_INTERVAL_S ))|g'; then
  case_setup m1
  printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
  FAKE_CURL_COST=15 run_sut "$MUTANT"
  m1_reported="$(reported_elapsed 200)"
  assert "M1 RED: the sleep-tally blows T3's 420s observed-clock bound (measured $(observed_clock)s)" \
    "[[ \$(observed_clock) -gt 420 ]]"
  # `-n` first: `[[ "" -le 225 ]]` is TRUE — `[[ ]]` coerces an empty string to 0 — so without a
  # positive control this row passes vacuously the moment the message changes shape (#7656 C9).
  assert "M1 positive control: the mutant still PRINTS an elapsed to compare against" \
    "[[ -n '$m1_reported' ]]"
  assert "M1 and it does so while REPORTING a compliant elapsed (${m1_reported:-none}s) — which is why T3 asserts the clock" \
    "[[ '${m1_reported:-99999}' -le 225 ]]"
fi

# M2 — flip the rollback to paused:false (Guard 2 row 7 at the script layer).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate unpause-rollback 1 's|hb_patch_paused "\$id" true && return 0|hb_patch_paused "$id" false \&\& return 0|'; then
  case_setup m2
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  run_sut "$MUTANT"
  assert "M2 RED: the terminal PATCH is no longer paused:true" \
    "[[ \"\$(patch_bodies | tail -1)\" != '$ID_INNGEST {\"paused\":true}' ]]"
fi

# M3 — stop recording the id at the unpause, which is what a "remove on attempt" design amounts to.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-state-add 1 's|^  state_add "\$id"$|  : "state_add removed by mutation"|'; then
  case_setup m3
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert "M3 RED: a failed rollback no longer leaves the id on the sweep's books (T5 would be vacuous)" \
    "[[ \$(state_lines) -eq 0 ]]"
fi

# M4 — soft-land a FAILED rollback back to rc=2, the pre-#7587 behaviour. ANCHORED to the rollback
# branch: the old `s|^    return 1$|    return 2|` landed in three regions at once.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate soft-failed-rollback 1 '/rollback PATCH paused=true FAILED/,/^    return 1$/ s|^    return 1$|    return 2|'; then
  case_setup m4
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert_eq "M4 RED: the apply job goes GREEN while a monitor is live-and-unfed" "0" "$RC"
  assert "M4 positive control: the mutant really did take the failed-rollback branch" \
    "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
fi

# M5 — restore the 230s inngest deadline.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate deadline-230 1 's|^ARM_INNGEST_DEADLINE=30$|ARM_INNGEST_DEADLINE=230|'; then
  case_setup m5
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert "M5 RED: the inngest arm advertises its old 230s budget again" \
    "[[ \"\$OUT\" == *'no beat within 230s'* ]]"
  assert "M5 and burns it: the observed clock passes 230s" "[[ \$(observed_clock) -ge 230 ]]"
fi

# M6 — strip the Authorization header. Ignored by the old stub, so deletable with both suites green.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-auth-header 2 's|-H "Authorization: Bearer \${BS_TOKEN}" ||g'; then
  case_setup m6
  run_sut "$MUTANT"
  assert_eq "M6 RED: an unauthenticated gate cannot verify a single arm" "1" "$RC"
  assert "M6 and it says the lookup failed rather than reporting a status" \
    "[[ \"\$OUT\" == *'failed — cannot verify arm state'* ]]"
fi

# M7 — strip the per-round-trip ceiling. The whole ladder is priced on `--max-time`.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-max-time 2 's|--max-time "\$ARM_CURL_MAX_TIME_S" ||g'; then
  case_setup m7
  run_sut "$MUTANT"
  assert_eq "M7 RED: an unbounded round-trip is a term the wall-clock ladder cannot price" "1" "$RC"
fi

# M8 — narrow the op/state gate to `== "up"`, so a `down` or `pending` monitor is unpaused and
# polled to its deadline on every apply.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate gate-up-only 1 's|if \[\[ "\$HB_STATUS" != "paused" \]\]; then|if [[ "$HB_STATUS" == "up" ]]; then|'; then
  case_setup m8
  printf 'down' > "$FAKE_STATE/$ID_ZOT1.status"
  FAKE_CURL_COST=0 run_sut "$MUTANT"
  assert "M8 RED: a DOWN monitor is now unpaused rather than skipped" \
    "[[ \"\$(patch_bodies | head -1)\" == '$ID_ZOT1 {\"paused\":false}' ]]"
  assert "M8 and it is polled to its deadline: the clock passes 200s" "[[ \$(observed_clock) -ge 200 ]]"
fi

# M10 — remove hb_fetch's empty-status guard: a 200 whose JSON has no status would arm on "".
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-status-guard 1 's@^  \[\[ -n "\$HB_STATUS" \]\] || return 1$@  :@'; then
  case_setup m10
  printf '%s\n' "$ID_ZOT1" > "$FAKE_BAD_JSON"
  FAKE_CURL_COST=0 run_sut "$MUTANT"
  assert "M10 RED: an empty status is no longer a failed lookup" \
    "[[ \"\$OUT\" != *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
fi

# M11 — lower the documented poll-interval default to 1: a 6x production API-call rate, invisible
# while every case exported the value.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate poll-default-1 1 's|ARM_POLL_INTERVAL_S="\${ARM_POLL_INTERVAL_S:-10}"|ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-1}"|'; then
  case_setup m11
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CURL_COST=0 run_sut_defaults "$MUTANT"
  assert "M11 RED: the default interval is no longer 10s — T10's 9 GETs become one per second" \
    "[[ \$(get_urls | grep -c '') -gt 12 ]]"
fi

# M12 — delete the sweep's fail-not-annotate branch. This is the mutation that survived the
# regex guard: `expect(body).toMatch(/^\s*exit 1\s*$/m)` was satisfied by an unrelated `exit 1`
# in the mint-unreadable branch, so the sweep could annotate-and-exit-0 with 159/0 green.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-annotate-only 1 '/Re-pause sweep could not re-pause/{n; s|^    return 1$|    return 0|}'; then
  case_setup m12
  printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
  printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
  run_sweep "$MUTANT"
  assert_eq "M12 RED: the sweep now exits 0 with a monitor still live-and-unfed" "0" "$RC"
  assert "M12 positive control: it really did fail to re-pause one" \
    "[[ \"\$OUT\" == *'returned HTTP 500'* ]]"
fi

# M13 — make the sweep's arithmetic lie: count a failure as a success.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-count-lie 1 's|^      failed=\$(( failed + 1 ))$|      repaused=$(( repaused + 1 ))|'; then
  case_setup m13
  printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
  printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
  run_sweep "$MUTANT"
  assert "M13 RED: the sweep reports a clean outcome while a monitor is still live" \
    "[[ \"\$OUT\" == *'armed=2 repaused=2 failed=0'* ]]"
fi

# M14 — drop the ids from the mint-unreadable message, leaving only the count.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-no-ids 1 's|and this step cannot re-pause them: \${ids}\.|and this step cannot re-pause them.|'; then
  case_setup m14
  printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
  SWEEP_TOKEN="" run_sweep "$MUTANT"
  assert "M14 RED: the operator is told a count with no id to act on" \
    "[[ \"\$OUT\" != *\"cannot re-pause them: $ID_ZOT1\"* ]]"
fi

# M16 — flip the SWEEP's PATCH to paused:false, i.e. a backstop that unpauses what it was built
# to re-pause. Anchored separately from M2 because the two call sites are different branches.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-unpause 1 's|^    if hb_patch_paused "\$id" true; then$|    if hb_patch_paused "$id" false; then|'; then
  case_setup m16
  printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
  run_sweep "$MUTANT"
  assert "M16 RED: the sweep now UNPAUSES the monitor it exists to re-pause" \
    "[[ \"\$(patch_bodies | tail -1)\" == '$ID_ZOT1 {\"paused\":false}' ]]"
fi

# M17 — drop the rollback retry, i.e. Deviation 3 as it first shipped: one unretried round-trip
# reds a routine apply and raises a false ops alarm.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-rollback-retry 1 's|^ARM_ROLLBACK_ATTEMPTS=2$|ARM_ROLLBACK_ATTEMPTS=1|'; then
  case_setup m17
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true 500\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL_ONCE"
  FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert_eq "M17 RED: a single lost round-trip now reds the apply" "1" "$RC"
  assert "M17 and it calls the monitor unpaused-and-unfed on a transient" \
    "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
fi

# M15 — the anti-vacuity control. An UNMUTATED copy, run through the same harness, must still be
# GREEN; without it a red baseline is indistinguishable from a caught mutation.
cp "$SUT" "$WORK/mutant-control.sh" || { echo "FATAL: control copy failed"; exit 2; }
case_setup m15
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CURL_COST=15 run_sut "$WORK/mutant-control.sh"
assert_eq "M15 control: the UNMUTATED copy still soft-lands at rc=0" "0" "$RC"
assert "M15 control: and still advertises the 30s deadline" "[[ \"\$OUT\" == *'no beat within 30s'* ]]"
case_setup m15b
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
run_sweep "$WORK/mutant-control.sh"
assert_eq "M15 control: the UNMUTATED sweep still exits 0 on a clean re-pause" "0" "$RC"

echo
echo "arm-heartbeats: ${PASS} passed, ${FAIL} failed ($((PASS + FAIL)) assertions)"
# MINIMUM-CARDINALITY FLOOR. A harness whose case loop silently ran nothing would otherwise report
# "0 failed" and read as success. Absolute and hand-ratcheted — there is no second producer here to
# derive it from. Ratcheted 55 → 190, the EXACT shipped count (#7656 C8: 55 against an actual 69
# left room to delete a whole ten-assertion case without tripping it). Exact, not "shipped minus a
# margin": a margin is precisely the room a silent narrowing hides in, and removing an assertion on
# purpose should cost one deliberate edit here.
ASSERT_FLOOR=190
if [[ $((PASS + FAIL)) -lt "$ASSERT_FLOOR" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran against a floor of ${ASSERT_FLOOR} — the suite is narrowed or a case aborted early."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
