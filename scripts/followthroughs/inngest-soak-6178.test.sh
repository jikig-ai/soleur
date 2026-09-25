#!/usr/bin/env bash
# Exit-code harness for inngest-soak-6178.sh (#6178 — the ADR-100 Phase-4 soak probe).
#
# THE PROBE IS NOTIFY-ONLY, AND THAT IS THE FIRST PROPERTY THIS SUITE PINS. Its exit code is
# rendered by scripts/sweep-followthroughs.sh as NOT YET (2) / CANNOT ESTABLISH (3) / ACTION
# REQUIRED (5); 0 is the sweeper's CLOSE verb and 1 its REOPEN trigger. Closing #6178 authorises
# an ADR status flip and the release of four rollback snapshots, so neither verb may ever be
# taken by a machine — `assert_never_close_verb` runs after EVERY invocation, including the
# xtrace refusal and the EXIT-trap arm (P-D drives the trap through a scratch-copy mutant whose
# exit site is replaced by a `set -u` abort), and H3 proves the helper itself can fire.
#
# THE STUB ASSERTS ITS ARGV AND ANSWERS BY WHAT WAS ASKED. A `curl` that answers regardless of
# arguments cannot notice the probe sending the wrong method, dropping the HMAC header, widening a
# slice past the page cap, or drifting the `from=` anchor — every one of those would stay green
# forever. The stub refuses (exit 64) unless the request carries `-X GET`, `X-Signature-256:
# sha256=`, both CF-Access headers, and — for slices — the pinned URL prefix with
# `from=2026-09-15T12:40:00Z` and at most 8 ids; and it serves the fixture for the slice that
# HOLDS the first requested id (not the Nth fixture for the Nth call), so a re-dealt probe is
# answered with the wrong function set and P-C reds. H2 proves the refusal is live.
#
# EVERY RUN PINS THE CLOCK. `run()` always exports INNGEST_SOAK_NOW_EPOCH (default 1790000000,
# before SOAK_END = 1790083380). Without it an unpinned case would silently flip 2 → 5 on
# 2026-09-22 and still pass — H4 pins the export's presence in this file.
#
# FIXTURES ARE VENDOR-SHAPED, NOT MINIMAL. The on-host probe emits `{runs:[{id,functionID,
# startedAt,…}], total_count:N}`; `startedAt` carries fractional seconds of MIXED precision on
# real rows (measured 2026-09-19: none / 3 / 4 / 5 / 6 digits), run ids are 26-char ULIDs, and a
# FATAL body arrives as prose, not JSON. Values are synthesized (cq-test-fixtures-synthesized-only)
# except the thirteen explained run ids, which are the production ULIDs the probe pins (they are
# the pin; a synthetic set could not exercise it).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-soak-6178.sh"
POP="$HERE/inngest-soak-6178.function-ids.txt"
fails=0
checks=0
passes=0
# `passes` is what the floor reads (failure-inclusive `checks` would let a `fail()` that skips
# its own counter keep the floor satisfied while the verdict inverts — the 7674 sibling's note).
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }
[[ -f "$POP" ]] || { echo "FATAL: population file not found at $POP" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
# The stub needs the population's dealing to pick a fixture by requested id; it reads this copy.
grep -vE '^[[:space:]]*(#|$)' "$POP" > "$WORK/population.txt"

# ── the curl stub ─────────────────────────────────────────────────────────────────────────────
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf '%s\n' "$*" >> "$cfg/calls.log"
out=""; url=""; want_code=0; method=""; hdr_sig=0; hdr_id=0; hdr_sec=0
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; i=$((i+1)) ;;
    -w) want_code=1; i=$((i+1)) ;;
    -X) method="${args[$((i+1))]}"; i=$((i+1)) ;;
    -H)
      h="${args[$((i+1))]}"; i=$((i+1))
      case "$h" in
        "X-Signature-256: sha256="*) hdr_sig=1 ;;
        "CF-Access-Client-Id: "*) hdr_id=1 ;;
        "CF-Access-Client-Secret: "*) hdr_sec=1 ;;
      esac ;;
    --max-time|--connect-timeout|--proto|--noproxy) i=$((i+1)) ;;
    https://*) url="${args[$i]}" ;;
  esac
done
[[ "$method" == "GET" ]] || { echo "stub: not -X GET" >&2; exit 64; }
[[ "$hdr_sig" == 1 ]] || { echo "stub: missing X-Signature-256: sha256= header" >&2; exit 64; }
[[ "$hdr_id" == 1 && "$hdr_sec" == 1 ]] || { echo "stub: missing CF-Access header pair" >&2; exit 64; }
rc_file="$cfg/curl.rc"
if [[ -f "$rc_file" ]]; then rc="$(<"$rc_file")"; if [[ "$rc" != "0" ]]; then [[ "$want_code" == 1 ]] && printf '000'; exit "$rc"; fi; fi
case "$url" in
  https://deploy.soleur.ai/hooks/inngest-registry-probe)
    body="$cfg/registry.json"; code="$(cat "$cfg/registry.code" 2>/dev/null || echo 200)" ;;
  "https://deploy.soleur.ai/hooks/inngest-doublefire-probe?from=2026-09-15T12:40:00Z&function_ids="*)
    csv="${url#*function_ids=}"
    n="$(printf '%s' "$csv" | tr ',' '\n' | grep -c .)"
    printf '%s\n' "$csv" >> "$cfg/slice-ids.log"   # logged BEFORE the cap, so C15 sees an oversized slice
    [[ "$n" -le 8 ]] || { echo "stub: slice carries $n ids (> 8)" >&2; exit 64; }
    first="${csv%%,*}"
    line="$(grep -nxF "$first" "$cfg/population.txt" | cut -d: -f1)"
    [[ -n "$line" ]] || { echo "stub: first id not in population" >&2; exit 66; }
    k=$(( (line - 1) % 7 + 1 ))
    body="$cfg/slice-$k.json"; code="$(cat "$cfg/slice-$k.code" 2>/dev/null || echo 200)" ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; printf '%s\n' "OFFHOST $url" >> "$cfg/calls.log"; exit 99 ;;
esac
[[ -f "$body" ]] || { echo "stub: no fixture $body" >&2; exit 65; }
[[ -n "$out" ]] && cp "$body" "$out"
[[ "$want_code" == 1 ]] && printf '%s' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────
UUID18='["a0000000-0000-4000-8000-000000000001","a0000000-0000-4000-8000-000000000002","a0000000-0000-4000-8000-000000000003","a0000000-0000-4000-8000-000000000004","a0000000-0000-4000-8000-000000000005","a0000000-0000-4000-8000-000000000006","a0000000-0000-4000-8000-000000000007","a0000000-0000-4000-8000-000000000008","a0000000-0000-4000-8000-000000000009","a0000000-0000-4000-8000-000000000010","a0000000-0000-4000-8000-000000000011","a0000000-0000-4000-8000-000000000012","a0000000-0000-4000-8000-000000000013","a0000000-0000-4000-8000-000000000014","a0000000-0000-4000-8000-000000000015","a0000000-0000-4000-8000-000000000016","a0000000-0000-4000-8000-000000000017","a0000000-0000-4000-8000-000000000018"]'
SLICES=7   # the probe's N_SLICES = ceil(52 / 8); the dealer here mirrors the probe's `(NR-1) % N_SLICES`
pop_ids() { cat "$WORK/population.txt"; }
dealt() { pop_ids | awk -v n="$SLICES" -v k="$(( $1 - 1 ))" '(NR-1)%n==k'; }
slice_of() { local n; n="$(pop_ids | grep -nxF "$1" | cut -d: -f1)"; [[ -n "$n" ]] || { echo "harness: $1 not in population" >&2; exit 1; }; echo "$(( (n - 1) % SLICES + 1 ))"; }
TICKS=16
# slice_fixture <k> [ids...] — one run per (id, hourly tick) on 2026-09-18, mixed startedAt
# precision, unique 26-char ULID-shaped ids, total_count = distinct-id count. Slice 1 additionally
# carries the window-head run (2026-09-15T12:40:00.082079Z, the measured global minimum) unless
# NO_WINDOW_HEAD=1.
slice_fixture() {
  local k="$1"; shift
  printf '%s\n' "$@" | jq -R . | jq -s --arg k "$k" --argjson ticks "$TICKS" --arg head "${NO_WINDOW_HEAD:-0}" '
    [ to_entries[] | .key as $i | .value as $fn | range(0; $ticks) as $t
      | { id: ((("01M2Q" + $k + "F" + ("0" + ($i | tostring) | .[-2:]) + "T" + ("0" + ($t | tostring) | .[-2:])) + "00000000000000000000000000") | .[0:26]),
          functionID: $fn,
          startedAt: ("2026-09-18T" + (if $t < 10 then "0" else "" end) + ($t | tostring) + ":00:00"
                      + (if ($t % 3) == 0 then "Z" elif ($t % 3) == 1 then ".08Z" else ".101119Z" end)) } ]
    | if ($k == "1" and $head != "1" and length > 0)
      then . + [{ id: "01M2QHEADRUN00000000000000", functionID: .[0].functionID, startedAt: "2026-09-15T12:40:00.082079Z" }]
      else . end
    | { runs: ., total_count: (unique_by(.id) | length) }' > "$WORK/slice-$k.json"
}
append_runs() { # append_runs <k> <json-array>
  local k="$1" a="$2" f
  f="$WORK/slice-$k.json"
  jq --argjson a "$a" '.runs += $a | .total_count = (.runs | unique_by(.id) | length)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
# extra_runs <k> <n> <fn> — n distinct runs of one function on 2026-09-19, ids unique per (k, n).
extra_runs() {
  local k="$1" n="$2" fn="$3"
  append_runs "$k" "$(jq -nc --arg k "$k" --argjson n "$n" --arg fn "$fn" '[range(0; $n) as $i | { id: ((("01M2QX" + $k + "N" + ("0" + ($i | tostring) | .[-2:])) + "00000000000000000000000000") | .[0:26]), functionID: $fn, startedAt: ("2026-09-19T" + (if $i < 10 then "0" else "" end) + ($i | tostring) + ":00:00Z") }]')"
}
registry_fixture() { # registry_fixture [count] [omit-id] [extra-json-array]
  pop_ids | jq -R . | jq -s --argjson extra "$UUID18" --argjson more "${3:-[]}" --argjson n "${1:-70}" --arg omit "${2:-}" \
    '(. + $extra + $more) | map(select(. != $omit)) | { registry_empty: false, function_count: $n, function_ids: . }' > "$WORK/registry.json"
}
default_fixtures() {
  rm -f "$WORK"/slice-*.json "$WORK"/slice-*.code "$WORK/registry.code" "$WORK/curl.rc"
  registry_fixture
  local k
  for (( k = 1; k <= SLICES; k++ )); do
    mapfile -t _ids < <(dealt "$k")
    slice_fixture "$k" "${_ids[@]}"
  done
}
# run <id> [bash args, e.g. -x] — the ONLY launcher (P-D passes PROBE_OVERRIDE for its mutant).
RUN_ENV=(WEBHOOK_DEPLOY_SECRET=p-secret CF_ACCESS_CLIENT_ID=cf-id CF_ACCESS_CLIENT_SECRET=cf-secret)
run() {
  local name="$1"; shift
  : > "$WORK/calls.log"; : > "$WORK/slice-ids.log"
  OUT="$(env "${RUN_ENV[@]}" INNGEST_SOAK_NOW_EPOCH="${NOW:-1790000000}" \
        ${POPFILE:+INNGEST_SOAK_POPULATION_FILE="$POPFILE"} \
        PATH="$WORK/bin:$PATH" bash "$@" "${PROBE_OVERRIDE:-$PROBE}" 2>&1)"
  RC=$?
  assert_never_close_verb "$RC" "$name"
}
assert_never_close_verb() {
  if [[ "$1" == "0" || "$1" == "1" ]]; then
    fail "INVARIANT: the probe returned rc=$1 ($2) — 0 is the sweeper's close verb and 1 its reopen trigger; neither may EVER be taken"
  fi
}
expect() { # expect <case> <want-rc> <want-substring>
  local name="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name — rc=$RC want=$want_rc :: $(printf '%s\n' "$OUT" | tail -n 1)"
  elif ! grep -qF -- "$want_sub" <<<"$OUT"; then
    fail "$name — rc ok but missing '$want_sub' :: $(printf '%s\n' "$OUT" | tail -n 1)"
  else
    pass "$name"
  fi
}
expect_absent() { # expect_absent <case> <must-not-contain>
  if grep -qF -- "$2" <<<"$OUT"; then
    fail "$1 — output contains forbidden '$2'"
  else
    pass "$1"
  fi
}
slice_calls() { grep -c 'inngest-doublefire-probe' "$WORK/calls.log"; }
last_line() { printf '%s\n' "$OUT" | tail -n 1; }

echo "== inngest-soak-6178.sh exit-code harness =="

# ── H1 both verdict helpers can FAIL, on BOTH of expect()'s branches ─────────────────────────
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
RC=99; OUT="nothing like the expected text"
expect "SELFTEST expect rc (must fail)" 0 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: expect() reports an rc mismatch as a failure"
else
  printf '  FAIL INSTRUMENT: expect() did NOT fail on a guaranteed rc mismatch — every case below is decorative.\n' >&2
  exit 1
fi
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
RC=2; OUT="the rc matches but the text does not"
expect "SELFTEST expect substring (must fail)" 2 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: expect() reports a substring mismatch as a failure (the branch every token case relies on)"
else
  printf '  FAIL INSTRUMENT: expect() did NOT fail on a guaranteed substring mismatch — every token assertion below is decorative.\n' >&2
  exit 1
fi
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
OUT="the forbidden token IS here"
expect_absent "SELFTEST expect_absent (must fail)" "forbidden token" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: expect_absent() reports a present token as a failure"
else
  printf '  FAIL INSTRUMENT: expect_absent() did NOT fail when the token was present.\n' >&2
  exit 1
fi

# ── H2 the stub refuses argv without the signature header ────────────────────────────────────
: > "$WORK/calls.log"
_argv_out="$(PATH="$WORK/bin:$PATH" curl -X GET -H 'CF-Access-Client-Id: a' -H 'CF-Access-Client-Secret: b' 'https://deploy.soleur.ai/hooks/inngest-registry-probe' 2>&1; echo "rc=$?")"
if grep -q 'rc=64' <<<"$_argv_out"; then
  pass "INSTRUMENT: the stub exits 64 without the X-Signature-256 header (argv is asserted)"
else
  fail "INSTRUMENT: the stub accepted a request with no HMAC header — every argv assertion is vacuous"
fi

# ── H3 the never-close invariant helper itself fires ─────────────────────────────────────────
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
assert_never_close_verb 0 SELFTEST 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: invariant fires on rc 0"
else
  printf '  FAIL INSTRUMENT: assert_never_close_verb did NOT fail on rc 0 — the notify-only invariant is unguarded.\n' >&2
  exit 1
fi

# ── H4 every run pins the clock ───────────────────────────────────────────────────────────────
if [[ "$(grep -c 'INNGEST_SOAK_NOW_EPOCH=' "${BASH_SOURCE[0]}")" -ge 1 ]]; then
  pass "INSTRUMENT: run() exports INNGEST_SOAK_NOW_EPOCH (no case reads the wall clock)"
else
  fail "INSTRUMENT: no INNGEST_SOAK_NOW_EPOCH export in this suite — cases would flip 2→5 on 2026-09-22"
fi

# SOAK_END is read from the probe so the two files cannot drift apart silently.
SOAK_END_ISO="$(grep -oE '^SOAK_END=[^ ]+' "$PROBE" | cut -d= -f2)"
SOAK_END_EPOCH="$(date -u -d "$SOAK_END_ISO" +%s)"
[[ "$SOAK_END_EPOCH" == "1790083380" ]] && pass "the probe's SOAK_END is 2026-09-22T13:23:00Z (epoch 1790083380)" || fail "SOAK_END drifted: $SOAK_END_ISO → $SOAK_END_EPOCH"
# SLICE_MAX is a literal here, not read back: 11 ids per slice put 1023 runs behind one GET on
# 2026-09-25, and the host's scan timed out on page 8 on every retry (sweeper dry run 36121535964;
# the plan's 2026-09-25 work-phase addendum records the measurement).
[[ "$(grep -oE '^SLICE_MAX=[0-9]+' "$PROBE")" == "SLICE_MAX=8" ]] && pass "the probe deals ≤ 8 ids per slice (7 slices)" || fail "SLICE_MAX drifted: $(grep -oE '^SLICE_MAX=[0-9]+' "$PROBE")"
MINTER=26e6836b-97ad-503f-8b08-490d8a2f4ce8
CREDIT=2e625d3c-0207-569f-b10b-567bc685ad5e
OTHER=11bb44a3-ae8d-57b0-8d41-e76e57f0277a
# The production run ids of the explained groups (host .id == routine_runs.run_id, read 2026-09-19).
EXPLAINED_MINTER='[{"id":"01M2QPSG3066F4DRDEBX5FCJSC","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:52:15.072598Z"},{"id":"01M2QPSGN9WFA6ERRYCJP8ACNY","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:52:15.658007Z"},{"id":"01M2QPSH0C5MWWGVM45D73QFGF","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:52:16.012947Z"},{"id":"01M2QPSHH0TRCGYC9DBAHHCA1J","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:52:16.545459Z"}]'
EXPLAINED_CREDIT='[{"id":"01M2QPSG3C1H3HG443K6JG9Q0V","functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","startedAt":"2026-09-17T12:52:15.085288Z"},{"id":"01M2QPSGKXBTKVDD358S1GRQ76","functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","startedAt":"2026-09-17T12:52:15.61412Z"}]'
add_explained() { append_runs "$(slice_of $MINTER)" "$EXPLAINED_MINTER"; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; }
MINTER_BUCKET_WINDOW='2026-09-17T12:40:00Z–2026-09-17T13:00:00Z'
# The three groups attributed 2026-09-25 (#6178 comment 5829980093): production ids, vendor-shaped startedAt.
PROMOTE=9a26ac57-a722-5c59-9f36-115675eecbad
DRIFT=209d5706-72bd-561c-88dc-92d7e23c1849
NOW_0925=1790337600   # 2026-09-25T12:00:00Z: after SOAK_END, before SOAK_STALE
PIN_PROMOTE='[{"id":"01M2XM4813N3QE97TEZZVW9TT7","functionID":"9a26ac57-a722-5c59-9f36-115675eecbad","startedAt":"2026-09-19T20:01:08.132534Z"},{"id":"01M2XMEM8TZEDVAMRTZSCPWVVZ","functionID":"9a26ac57-a722-5c59-9f36-115675eecbad","startedAt":"2026-09-19T20:06:48.346911Z"}]'
PIN_MINTER2='[{"id":"01M341XPCWG79VZZPDJQ9W64KG","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-22T07:57:40.134819Z"},{"id":"01M341XQ4SX2KGWVF5J0XQ9PTG","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-22T07:57:40.890647Z"},{"id":"01M341XQNXQDFJSNW1C5PDP4TH","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-22T07:57:41.438198Z"}]'
PIN_DRIFT='[{"id":"01M38ZZP4PKKDB2QJ3HB77JTEY","functionID":"209d5706-72bd-561c-88dc-92d7e23c1849","startedAt":"2026-09-24T06:00:00.407387Z"},{"id":"01M390P0W5ZT51H3VDD1M2CTYJ","functionID":"209d5706-72bd-561c-88dc-92d7e23c1849","startedAt":"2026-09-24T06:12:12.29469Z"}]'
add_new_pins() { append_runs "$(slice_of $PROMOTE)" "$PIN_PROMOTE"; append_runs "$(slice_of $MINTER)" "$PIN_MINTER2"; append_runs "$(slice_of $DRIFT)" "$PIN_DRIFT"; }
WHY_1491540='explained_why: bucket=1491540 2026-09-19 20:01Z+20:06Z: two manual triggers (trigger_source=manual), an operator retry of a failed run'
WHY_1491719='explained_why: bucket=1491719 2026-09-22 catch-up: 07:00/07:20/07:40 ticks missed with no scheduler, each fired once at resume 35698687536'
WHY_1491858='explained_why: bucket=1491858 2026-09-24 06:00Z scheduled tick plus a manual trigger at 06:12:11Z (trigger_source=manual)'
# tail_head <out>: the first line the sweeper's `tail -c 4000` republishes, plus the byte size and margin.
tail_head() { printf '%s' "$1" | tail -c 4000 | head -n 1; }
out_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }
# tail_head self-test: an over-budget output must lose its first line, an under-budget one keep it.
_big="reading: x
$(printf 'y%.0s' $(seq 1 4100))"
[[ "$(tail_head "$_big")" != reading:* ]] && pass "INSTRUMENT: tail_head drops the first line of a >4000-byte output" || fail "INSTRUMENT: tail_head kept 'reading:' on a 4100-byte output"
[[ "$(tail_head "reading: x
short")" == reading:* ]] && pass "INSTRUMENT: tail_head keeps the first line of a short output" || fail "INSTRUMENT: tail_head lost 'reading:' on a short output"
# The EXPLAINED rule, read from the probe itself: only the two 09-17 pins (bucket 1491374) may omit `why`.
_ex="$(awk '/^EXPLAINED=.\[/{f=1; sub(/^EXPLAINED=./,"")} f{print} f&&/^\]'"'"'$/{exit}' "$PROBE" | sed '$ s/'"'"'$//')"
_bad="$(jq -r '[.[] | select(.bucket != 1491374 and ((.why // "") == ""))] | length' <<<"$_ex" 2>/dev/null || echo ERR)"
_n="$(jq -r 'length' <<<"$_ex" 2>/dev/null || echo ERR)"
[[ "$_bad" == 0 && "$_n" == 5 ]] && pass "EXPLAINED: 5 pins, and every pin outside bucket 1491374 carries its own why" || fail "EXPLAINED rule: pins=$_n missing_why=$_bad"

# ── C0 registry gate ──────────────────────────────────────────────────────────────────────────
default_fixtures; run C0
expect "C0 registry 70 with every population id present → the slices are queried (rc 2)" 2 "NOT YET: interim reading at day"
[[ "$(head -1 "$WORK/calls.log")" == *inngest-registry-probe* ]] && pass "C0 the registry is read BEFORE the first slice" || fail "C0 the first request was not the registry probe"
expect "C0 ...no unmeasured functions" 2 "unmeasured_fns=0"
default_fixtures; registry_fixture 71 "" '["b0000000-0000-4000-8000-000000000001"]'; run C0b
expect "C0b a function registered after 09-15 → still read, but reported UNMEASURED (rc 2)" 2 "unmeasured_fns=1"
expect "C0b ...with the registry line" 2 "registry: 1 function(s) registered after 09-15"
default_fixtures; registry_fixture 71 "" '["b0000000-0000-4000-8000-000000000001"]'; NOW=$SOAK_END_EPOCH run C0b2
expect "C0b2 ...and at SOAK_END the verdict is QUALIFIED, not blocked" 5 "SOAK CLEAN outside the explained bucket (QUALIFIED: 1 unmeasured function(s)"
default_fixtures; registry_fixture 69 "$MINTER"; run C0c
expect "C0c a population id missing from the registry → registry_drift missing_from_registry=1" 3 "reason=registry_drift missing_from_registry=1"
[[ "$(slice_calls)" == 0 ]] && pass "C0c ...and no slice request was made" || fail "C0c slices were requested after a drifted registry"
default_fixtures; echo 500 > "$WORK/registry.code"; run C0d
expect "C0d registry HTTP 500 → registry_unreadable" 3 "reason=registry_unreadable"
[[ "$(slice_calls)" == 0 ]] && pass "C0d ...and no slice request was made" || fail "C0d slices were requested after an unreadable registry"

# ── C1 / C2 / C3 the three verdicts ──────────────────────────────────────────────────────────
default_fixtures; run C1
expect "C1 clean reading before SOAK_END → NOT YET (rc 2)" 2 "NOT YET: interim reading at day"
expect "C1 ...the reading block is present with the full run count" 2 "slices=7/7 runs=833 "
default_fixtures; NOW=$SOAK_END_EPOCH run C2
expect "C2 clean reading at SOAK_END → ACTION REQUIRED (rc 5)" 5 "SOAK CLEAN"
_last="$(last_line)"
for tok in "adopting" "398857857" "406654994" "407991378" "411798619" "close #6178" "re-read"; do
  grep -qF -- "$tok" <<<"$_last" && pass "C2 the VERDICT line carries '$tok'" || fail "C2 verdict line lacks '$tok': $_last"
done
expect "C2 ...provenance names the QUALIFIED 09-15 pass" 5 "itself a QUALIFIED verdict"
expect "C2 ...the scope caveat is printed" 5 "NOT a web-host double-fire detector"
expect "C2 ...the verbs order the fresh reading BEFORE the destructive step" 5 "(2) wait for the NEXT sweep"
expect_absent "C2 ...and does not say SOAK NOT CLEAN" "SOAK NOT CLEAN"
[[ "$_last" == "ACTION REQUIRED:"* && "$_last" == *"SOAK CLEAN"* ]] && pass "C2 the verdict line is the LAST line" || fail "C2 last line is not the verdict: $_last"
_pen="$(printf '%s\n' "$OUT" | tail -n 2 | head -n 1)"
[[ "$_pen" == "SCOPE:"* ]] && pass "C2 the SCOPE: line is second-to-last" || fail "C2 second-to-last is not SCOPE: $_pen"
default_fixtures; add_explained; NOW=$SOAK_END_EPOCH run C3
expect "C3 exactly the two explained groups (their real run ids) at SOAK_END → clean (rc 5)" 5 "SOAK CLEAN"
expect "C3 ...the minter group is listed as explained" 5 "explained: functionID=$MINTER bucket=1491374 ($MINTER_BUCKET_WINDOW) count=4"
expect "C3 ...the credit-probe group is listed as explained" 5 "explained: functionID=$CREDIT bucket=1491374 ($MINTER_BUCKET_WINDOW) count=2"
expect "C3 ...with the attribution, keyed to its bucket" 5 "explained_why: bucket=1491374 2026-09-17T12:40–13:00Z catch-up"
[[ "$(grep -c 'op=resume run 35223389582' <<<"$OUT")" == 1 ]] && pass "C3 ...the attribution is printed exactly once" || fail "C3 attribution printed $(grep -c 'op=resume run 35223389582' <<<"$OUT") times"
expect "C3 ...reading block counts explained=2" 5 "explained=2 UNEXPLAINED=0"
expect_absent "C3 ...and no UNEXPLAINED group line" "UNEXPLAINED:"
_tail="$(printf '%s\n' "$OUT" | tail -c 4000)"
grep -qF 'SCOPE:' <<<"$_tail" && grep -qF 'SOAK CLEAN' <<<"$_tail" && pass "C3 both verdict lines survive the sweeper's tail -c 4000 on the heavier output" || fail "C3 verdict/scope lost under tail -c 4000"

# ── C4 an unexplained group ───────────────────────────────────────────────────────────────────
C4_RUNS='[{"id":"01M2QC4A00000000000000000A","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T13:05:00Z"},{"id":"01M2QC4B00000000000000000B","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T13:10:00Z"}]'
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C4_RUNS"; NOW=$SOAK_END_EPOCH run C4
expect "C4 explained + a group in bucket 1491375 → ACTION REQUIRED investigate (rc 5)" 5 "investigate the listed groups before flipping"
expect "C4 ...names the unexplained functionID and bucket" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491375 (2026-09-17T13:00:00Z–2026-09-17T13:20:00Z) count=2"
expect "C4 ...explained groups still listed separately" 5 "explained: functionID=$MINTER"
expect "C4 ...verdict says SOAK NOT CLEAN" 5 "SOAK NOT CLEAN"
expect "C4 ...the remedy names trigger_source" 5 "trigger_source"
_last="$(last_line)"; [[ "$_last" == *"SOAK NOT CLEAN"* ]] && pass "C4 the verdict line is last on the NOT CLEAN arm" || fail "C4 last line: $_last"
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C4_RUNS"; run C4b
expect "C4b the same before SOAK_END → NOT YET with the group surfaced" 2 "UNEXPLAINED: functionID=$OTHER"
expect "C4b ...and tells the operator not to wait" 2 "investigate now, do not wait for day 7"

# ── C5 the explained set is EXACT: triple AND member ids ─────────────────────────────────────
C5_RUNS='[{"id":"01M2QC5A00000000000000000A","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T12:45:00Z"},{"id":"01M2QC5B00000000000000000B","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T12:50:00Z"}]'
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C5_RUNS"; NOW=$SOAK_END_EPOCH run C5
expect "C5 a THIRD function in bucket 1491374 → UNEXPLAINED (a bare-bucket pin would pass it)" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491374"
default_fixtures; add_explained; append_runs "$(slice_of $MINTER)" '[{"id":"01M2QC5BX0000000000000000X","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:55:00Z"}]'; NOW=$SOAK_END_EPOCH run C5b
expect "C5b the minter at count 5 (pin is 4) → UNEXPLAINED" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491374 ($MINTER_BUCKET_WINDOW) count=5"
expect_absent "C5b ...and no attribution line sits beside the UNEXPLAINED group in its bucket" "explained_why: bucket=1491374"
default_fixtures; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; append_runs "$(slice_of $MINTER)" "$(jq -c '.[0:3]' <<<"$EXPLAINED_MINTER")"; NOW=$SOAK_END_EPOCH run C5c
expect "C5c the minter at count 3 (below the pin) → UNEXPLAINED, not clean" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491374 ($MINTER_BUCKET_WINDOW) count=3"
# P-A: the pinned triple's functionID and count, one bucket over — the `.bucket` conjunct.
default_fixtures; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; append_runs "$(slice_of $MINTER)" "$(jq -c 'map(.startedAt |= sub("T12:52"; "T13:05"))' <<<"$EXPLAINED_MINTER")"; NOW=$SOAK_END_EPOCH run C5d
expect "C5d the minter ×4 with the same ids one bucket LATER → UNEXPLAINED (the bucket conjunct)" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491375"
# P-B: the pinned triple exactly, with DIFFERENT run ids — the member-set pin.
default_fixtures; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; append_runs "$(slice_of $MINTER)" "$(jq -c 'to_entries | map(.value.id = ("01M2QNOTTHEPIN0000000000" + (.key | tostring) + "0")) | map(.value)' <<<"$EXPLAINED_MINTER")"; NOW=$SOAK_END_EPOCH run C5f
expect "C5f the minter ×4 in bucket 1491374 with OTHER run ids → UNEXPLAINED (the pin is the member set, not the count)" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491374 ($MINTER_BUCKET_WINDOW) count=4"
expect "C5f ...and the credit-probe group with its real ids stays explained" 5 "explained: functionID=$CREDIT"
# Window-head boundary: SOAK_FROM + 2×PERIOD = 2026-09-15T13:20:00Z is the last accepted head.
default_fixtures; mapfile -t _ids < <(dealt 1); NO_WINDOW_HEAD=1 slice_fixture 1 "${_ids[@]}"; run C5e
expect "C5e earliest run on 2026-09-18 (window head uncovered) → index_eroded" 3 "reason=index_eroded min_started=2026-09-18T00:00:00Z"
default_fixtures; mapfile -t _ids < <(dealt 1); NO_WINDOW_HEAD=1 slice_fixture 1 "${_ids[@]}"; append_runs 1 "[{\"id\":\"01M2QHEADEDGE0000000000000\",\"functionID\":\"${_ids[0]}\",\"startedAt\":\"2026-09-15T13:20:00Z\"}]"; run C5g
expect "C5g a head exactly at SOAK_FROM + 2×PERIOD is accepted (rc 2)" 2 "NOT YET: interim reading at day"
default_fixtures; mapfile -t _ids < <(dealt 1); NO_WINDOW_HEAD=1 slice_fixture 1 "${_ids[@]}"; append_runs 1 "[{\"id\":\"01M2QHEADEDGE1000000000000\",\"functionID\":\"${_ids[0]}\",\"startedAt\":\"2026-09-15T13:20:01Z\"}]"; run C5h
expect "C5h a head one second past SOAK_FROM + 2×PERIOD → index_eroded" 3 "reason=index_eroded min_started=2026-09-15T13:20:01Z"
default_fixtures; append_runs 1 "[{\"id\":\"01M2QUNDERRUN000000000000X\",\"functionID\":\"$(dealt 1 | head -1)\",\"startedAt\":\"2026-09-15T12:39:59Z\"}]"; run C5i
expect "C5i a run BEFORE the requested from= → window_underrun" 3 "reason=window_underrun min_started=2026-09-15T12:39:59Z"

# ── C26 the three groups attributed 2026-09-25 (exact pins, per-bucket attribution) ─────────
default_fixtures; add_explained; add_new_pins; NOW=$NOW_0925 run C26
expect "C26 all five pinned groups → SOAK CLEAN (rc 5)" 5 "ACTION REQUIRED: SOAK CLEAN"
expect "C26 ...reading block counts explained=5" 5 "explained=5 UNEXPLAINED=0"
expect "C26 ...the manual-retry group is explained" 5 "explained: functionID=$PROMOTE bucket=1491540 (2026-09-19T20:00:00Z–2026-09-19T20:20:00Z) count=2"
expect "C26 ...the 09-22 catch-up group is explained" 5 "explained: functionID=$MINTER bucket=1491719 (2026-09-22T07:40:00Z–2026-09-22T08:00:00Z) count=3"
expect "C26 ...the 09-24 manual-trigger group is explained" 5 "explained: functionID=$DRIFT bucket=1491858 (2026-09-24T06:00:00Z–2026-09-24T06:20:00Z) count=2"
expect "C26 ...the verdict counts five explained groups" 5 "5 explained group(s), 0 UNEXPLAINED"
for _w in "$WHY_1491540" "$WHY_1491719" "$WHY_1491858"; do
  [[ "$(grep -cxF -- "$_w" <<<"$OUT")" == 1 ]] && pass "C26 ...whole attribution line exactly once: ${_w:0:36}" || fail "C26 attribution line not present exactly once: $_w"
done
[[ "$(grep -c '^explained_why: bucket=1491374 2026-09-17T12:40–13:00Z catch-up' <<<"$OUT")" == 1 ]] && pass "C26 ...the 09-17 bucket's attribution is printed once for its two groups" || fail "C26 bucket=1491374 attribution printed $(grep -c '^explained_why: bucket=1491374' <<<"$OUT") times"
[[ "$(grep -c 'op=resume run 35223389582' <<<"$OUT")" == 1 ]] && pass "C26 ...the 09-17 text appears exactly once" || fail "C26 09-17 text printed $(grep -c 'op=resume run 35223389582' <<<"$OUT") times"
[[ "$(grep -c '^explained_why:' <<<"$OUT")" == 4 ]] && pass "C26 ...exactly four attribution lines (one per explained bucket)" || fail "C26 attribution lines: $(grep -c '^explained_why:' <<<"$OUT"), want 4"
expect_absent "C26 ...and no UNEXPLAINED group line" "UNEXPLAINED:"

default_fixtures; add_new_pins; NOW=$NOW_0925 run C26b
expect "C26b the three new pins alone → SOAK CLEAN (rc 5)" 5 "ACTION REQUIRED: SOAK CLEAN"
expect "C26b ...reading block counts explained=3" 5 "explained=3 UNEXPLAINED=0"
expect_absent "C26b ...no attribution for the absent 09-17 bucket" "bucket=1491374"
expect_absent "C26b ...and not the 09-17 text" "op=resume run 35223389582"

# C26c: flip the last character of one 1491719 id — still ULID-shaped and unique, so only the member-set conjunct can reject it.
default_fixtures; add_explained; append_runs "$(slice_of $PROMOTE)" "$PIN_PROMOTE"; append_runs "$(slice_of $DRIFT)" "$PIN_DRIFT"
append_runs "$(slice_of $MINTER)" "$(jq -c '.[0].id |= (.[0:25] + "Z")' <<<"$PIN_MINTER2")"; NOW=$NOW_0925 run C26c
expect "C26c the 09-22 minter pin with ONE id changed → SOAK NOT CLEAN" 5 "SOAK NOT CLEAN"
expect "C26c ...names that group UNEXPLAINED" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491719 (2026-09-22T07:40:00Z–2026-09-22T08:00:00Z) count=3"
expect_absent "C26c ...and prints no attribution for its bucket" "explained_why: bucket=1491719"
expect "C26c ...the 09-17 minter group (same function, other pin) stays explained" 5 "explained: functionID=$MINTER bucket=1491374"

# C26g: the 09-19 pinned run ids reported under a DIFFERENT function — only the functionID conjunct rejects it.
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$(jq -c --arg o "$OTHER" 'map(.functionID = $o)' <<<"$PIN_PROMOTE")"; NOW=$NOW_0925 run C26g
expect "C26g pinned ids under another functionID → UNEXPLAINED" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491540"
expect_absent "C26g ...and no attribution for that bucket" "explained_why: bucket=1491540"

C26F_RUNS='[{"id":"01M2XC26F00000000000000A0A","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-19T20:25:00Z"},{"id":"01M2XC26F00000000000000B0B","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-19T20:30:00Z"}]'
default_fixtures; add_explained; add_new_pins; append_runs "$(slice_of $OTHER)" "$C26F_RUNS"; NOW=$NOW_0925 run C26f
expect "C26f all five pins + ONE unrelated group → SOAK NOT CLEAN" 5 "SOAK NOT CLEAN"
expect "C26f ...reading block counts explained=5 UNEXPLAINED=1" 5 "explained=5 UNEXPLAINED=1"
expect "C26f ...names the unrelated group" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491541"
[[ "$(tail_head "$OUT")" == reading:* ]] && pass "C26f ...the NOT CLEAN output fits the sweeper's 4000-byte tail ($(out_bytes "$OUT") B)" || fail "C26f reading: line cut from tail -c 4000: $(out_bytes "$OUT") bytes, margin $((4000 - $(out_bytes "$OUT")))"

default_fixtures; add_explained; add_new_pins; registry_fixture 71 "" '["b0000000-0000-4000-8000-000000000001"]'; NOW=$NOW_0925 run C26q
expect "C26q the heaviest clean output (QUALIFIED) → SOAK CLEAN" 5 "SOAK CLEAN outside the explained bucket (QUALIFIED: 1 unmeasured"
[[ "$(tail_head "$OUT")" == reading:* ]] && pass "C26q ...the clean output fits the sweeper's 4000-byte tail ($(out_bytes "$OUT") B)" || fail "C26q reading: line cut from tail -c 4000: $(out_bytes "$OUT") bytes, margin $((4000 - $(out_bytes "$OUT")))"

# ── C6 / C7 unreadable slices ────────────────────────────────────────────────────────────────
default_fixtures; echo 500 > "$WORK/slice-3.code"; printf '{"error":"boom"}' > "$WORK/slice-3.json"; run C6
expect "C6 slice 3 HTTP 500 with a JSON body → slice_unreadable slice=3/7" 3 "reason=slice_unreadable slice=3/7"
expect "C6 ...cause=other with the body excerpt" 3 "cause=other"
expect "C6 ...http=500 is named" 3 "http=500"
expect_absent "C6 ...a MAPPED exit (3) does not also trip the unmapped-exit trap (an exit-1 here would be rewritten to 3 and read identical by rc alone)" "unmapped_exit"
default_fixtures; echo 500 > "$WORK/slice-3.code"; printf 'Error occurred while evaluating hook rules.' > "$WORK/slice-3.json"; run C6b
expect "C6b the hook-rule-mismatch body (a wrong HMAC) → cause=hmac_mismatch" 3 "cause=hmac_mismatch"
default_fixtures; echo 403 > "$WORK/slice-3.code"; printf '<!DOCTYPE html><html><body>Cloudflare Access denied</body></html>' > "$WORK/slice-3.json"; run C6c
expect "C6c a 403 HTML page → cause=cf_access" 3 "cause=cf_access"
expect_absent "C6c ...and no '<' is ever printed (the sweeper republishes stdout)" "<"
default_fixtures; printf 'inngest-doublefire-probe: FATAL preflight scan aborted reason=deadline pages_scanned=14 (deadline_s=90 page_ceiling=1000 from=2026-09-15T12:40:00Z total_count=1900) — narrow the window' > "$WORK/slice-2.json"; run C7
expect "C7 a FATAL body on HTTP 200 → slice_unreadable (never jq_failed, never clean)" 3 "reason=slice_unreadable"
expect "C7 ...cause=probe_fatal" 3 "cause=probe_fatal"
expect "C7 ...slice=2/7" 3 "slice=2/7"
expect "C7 ...the host's own reason tokens are extracted" 3 "reason=deadline pages_scanned=14"
default_fixtures; echo 500 > "$WORK/registry.code"; printf 'inngest-registry-probe: FATAL /v0/gql functions query failed or non-array (errors=["dial tcp 10.0.1.40:8288: connect: connection refused"] data_keys=[]); is the dedicated inngest-server reachable at http://10.0.1.40:8288/v0/gql? — refusing to emit a false-clean empty registry' > "$WORK/registry.json"; run C7b
expect "C7b a registry FATAL is classified probe-fatal with a bounded token" 3 "body_class=probe-fatal"
expect "C7b ...carrying the host's errors= token" 3 'errors=["dial tcp 10.0.1.40:8288: connect: connection refused"]'
expect_absent "C7b ...but not the free-text tail" "refusing to emit"

# ── C8 – C12 shape and completeness ──────────────────────────────────────────────────────────
default_fixtures; printf '{"runs":null,"total_count":7}' > "$WORK/slice-4.json"; run C8
expect "C8 .runs null → CANNOT ESTABLISH" 3 "cause=bad_run_shape"
default_fixtures; printf '{"runs":[],"total_count":0}' > "$WORK/slice-1.json"; run C9
expect "C9 an empty slice → slice_vacuous (never clean)" 3 "reason=slice_vacuous slice=1/7"
default_fixtures; jq '.total_count = "unknown"' "$WORK/slice-1.json" > "$WORK/t.tmp" && mv "$WORK/t.tmp" "$WORK/slice-1.json"; run C9b
expect "C9b total_count \"unknown\" with runs present → total_count_unknown (not vacuous, not clean)" 3 "reason=total_count_unknown slice=1/7"
default_fixtures; jq '.total_count = 999' "$WORK/slice-5.json" > "$WORK/t.tmp" && mv "$WORK/t.tmp" "$WORK/slice-5.json"; run C10
expect "C10 deduped < total_count (a page went missing) → slice_incomplete" 3 "reason=slice_incomplete slice=5/7 deduped=112 total_count=999"
default_fixtures; append_runs 2 "$(jq -c '[.runs[0]]' "$WORK/slice-2.json")"; run C11
expect "C11 a run repeated across pages is deduped by id → no group (rc 2)" 2 "explained=0 UNEXPLAINED=0"
default_fixtures; append_runs "$(slice_of $OTHER)" "[{\"id\":\"01M2QNULLSTART000000000000\",\"functionID\":\"$OTHER\",\"startedAt\":null}]"; run C12
expect "C12 a null-startedAt run is counted, not silently dropped (rc 2)" 2 "null_started=1"
expect "C12 ...and creates no group" 2 "UNEXPLAINED=0"
default_fixtures; append_runs 2 '[{"id":"01M2QBADFN0000000000000000","functionID":"not-a-uuid","startedAt":"2026-09-18T03:00:00Z"}]'; run C12b
expect "C12b a non-UUID functionID → bad_run_shape (never printed)" 3 "cause=bad_run_shape"
expect_absent "C12b ...the malformed value is not echoed" "not-a-uuid"
# P-H: the same malformed row FIRST in the body — inside any excerpt window — must still be withheld.
default_fixtures; jq '.runs = ([{"id":"01M2QBADFN0000000000000000","functionID":"not-a-uuid","startedAt":"2026-09-18T03:00:00Z"}] + .runs)' "$WORK/slice-2.json" > "$WORK/t.tmp" && mv "$WORK/t.tmp" "$WORK/slice-2.json"; run C12d
expect "C12d a malformed row at the FRONT of the body → bad_run_shape" 3 "cause=bad_run_shape"
expect_absent "C12d ...and the body is withheld, so the value at offset 0 is not echoed either" "not-a-uuid"
expect "C12d ...the withheld marker is printed instead" 3 "(json body withheld: run shape)"
default_fixtures; append_runs "$(slice_of $OTHER)" "[{\"id\":\"01M2QBADTS0000000000000000\",\"functionID\":\"$OTHER\",\"startedAt\":\"2026-09-18 03:00\"}]"; run C12c
expect "C12c a startedAt without T/Z → bad_run_shape" 3 "cause=bad_run_shape"
default_fixtures; append_runs "$(slice_of $OTHER)" "[{\"id\":\"short\",\"functionID\":\"$OTHER\",\"startedAt\":\"2026-09-18T03:00:00Z\"}]"; run C12e
expect "C12e a run id that is not a 26-char ULID → bad_run_shape" 3 "cause=bad_run_shape"
default_fixtures; append_runs "$(slice_of $OTHER)" "$(jq -nc --arg fn "$OTHER" '[range(0; 60) as $i | {id: ((("01M2QNULL" + ("0" + ($i|tostring) | .[-2:])) + "00000000000000000000000000") | .[0:26]), functionID: $fn, startedAt: null}]')"; run C12f
expect "C12f > 5% null-startedAt runs → index_eroded cause=null_started (a projection regression cannot hide a group)" 3 "reason=index_eroded cause=null_started null_started=60"

# ── C13 / C14 credentials ────────────────────────────────────────────────────────────────────
default_fixtures; run C13 -x
expect "C13 bash -x with a live credential → 78 (refused to trace)" 78 "refusing to trace"
[[ ! -s "$WORK/calls.log" ]] && pass "C13 ...and no request was made" || fail "C13 a request was made under xtrace"
expect_absent "C13 ...the credential value never appears in the traced output" "p-secret"
_saved_env=("${RUN_ENV[@]}")
default_fixtures; RUN_ENV=(WEBHOOK_DEPLOY_SECRET=p-secret CF_ACCESS_CLIENT_ID=cf-id CF_ACCESS_CLIENT_SECRET=); run C14
RUN_ENV=("${_saved_env[@]}")
expect "C14 an empty credential → credentials_unprovisioned (3, not 2)" 3 "reason=credentials_unprovisioned missing: CF_ACCESS_CLIENT_SECRET"
[[ ! -s "$WORK/calls.log" ]] && pass "C14 ...and no request was made" || fail "C14 a request was made with a missing credential"

# ── C15 chunking: complete coverage under the cap, and the dealing itself ─────────────────────
default_fixtures; run C15
expect "C15 a clean run" 2 "NOT YET: interim reading at day"
[[ "$(slice_calls)" == 7 ]] && pass "C15 exactly 7 slice requests" || fail "C15 slice requests = $(slice_calls), want 7"
_over="$(awk -F, '{ if (NF > 8) c++ } END { print c + 0 }' "$WORK/slice-ids.log")"
[[ "$_over" == 0 ]] && pass "C15 every request carries ≤ 8 ids" || fail "C15 $_over request(s) exceed 8 ids"
if diff <(tr ',' '\n' < "$WORK/slice-ids.log" | sort) <(pop_ids | sort) >/dev/null; then pass "C15 the union of requested ids equals the committed population"; else fail "C15 requested ids ≠ population"; fi
[[ "$(grep -c 'from=2026-09-15T12:40:00Z' "$WORK/calls.log")" == "$SLICES" ]] && pass "C15 every slice is pinned to from=2026-09-15T12:40:00Z" || fail "C15 a slice request drifted from the anchor"
# P-C: the dealing is round-robin over the density-sorted file — a contiguous chunking keeps the
# union identical and puts the minter beside the four hourlies in one slice.
_deal_ok=1
for (( k = 1; k <= SLICES; k++ )); do
  [[ "$(sed -n "${k}p" "$WORK/slice-ids.log")" == "$(dealt "$k" | paste -sd, -)" ]] || _deal_ok=0
done
[[ "$_deal_ok" == 1 ]] && pass "C15 request k carries exactly the ids line i≡k−1 (mod 7) — round-robin, not contiguous" || fail "C15 the dealing is not round-robin over the file"

# ── C16 / C22 population file ────────────────────────────────────────────────────────────────
default_fixtures; pop_ids | head -51 > "$WORK/pop51.txt"; POPFILE="$WORK/pop51.txt" run C16
expect "C16 a 51-line population → population_malformed" 3 "reason=population_malformed"
[[ ! -s "$WORK/calls.log" ]] && pass "C16 ...and no request was made" || fail "C16 a request was made on a malformed population"
default_fixtures; { echo "# header"; echo; echo "# total_count 127/447/114/25/118 measured 2026-09-19T03:57:28Z"; echo; pop_ids; echo; } > "$WORK/pop52.txt"; POPFILE="$WORK/pop52.txt" run C22
expect "C22 comment lines and blank lines around the 52 ids still parse (rc 2)" 2 "NOT YET: interim reading at day"

# ── C17 transport failure ─────────────────────────────────────────────────────────────────────
default_fixtures; echo 7 > "$WORK/curl.rc"; run C17
expect "C17 curl rc 7 → CANNOT ESTABLISH (transport is not a verdict)" 3 "curl_rc=7"
expect_absent "C17 ...with no bash redirect error on the public comment (the body file exists, empty)" "No such file"
expect "C17 ...and an empty-body length" 3 "body_len=0"

# ── C18 run shape: missing id / null functionID / foreign function ───────────────────────────
default_fixtures; append_runs "$(slice_of $OTHER)" "[{\"functionID\":\"$OTHER\",\"startedAt\":\"2026-09-18T03:00:00Z\"}]"; run C18
expect "C18 a run lacking .id → bad_run_shape (no (fn,startedAt) fallback dedupe)" 3 "cause=bad_run_shape"
default_fixtures; append_runs 2 '[{"id":"01M2QNULLFN000000000000000","functionID":null,"startedAt":"2026-09-18T03:00:00Z"}]'; run C18b
expect "C18b functionID null → bad_run_shape" 3 "cause=bad_run_shape"
default_fixtures; append_runs 2 '[{"id":"01M2QFOREIGN00000000000000","functionID":"a0000000-0000-4000-8000-000000000001","startedAt":"2026-09-18T03:00:00Z"}]'; run C18c
expect "C18c a run for a function this slice did not request → foreign_function_id" 3 "cause=foreign_function_id foreign=1"

# ── C20 population thin: the floor is a boundary, pinned on both sides ───────────────────────
default_fixtures; for (( k = 1; k <= SLICES; k++ )); do mapfile -t _ids < <(dealt "$k"); TICKS=15 slice_fixture "$k" "${_ids[@]}"; done; extra_runs "$(slice_of $OTHER)" 18 "$OTHER"; run C20
expect "C20 799 distinct runs → population_thin (one below RUN_FLOOR=800)" 3 "reason=population_thin runs=799 floor=800"
default_fixtures; for (( k = 1; k <= SLICES; k++ )); do mapfile -t _ids < <(dealt "$k"); TICKS=15 slice_fixture "$k" "${_ids[@]}"; done; extra_runs "$(slice_of $OTHER)" 19 "$OTHER"; run C20b
expect "C20b 800 distinct runs → accepted (rc 2)" 2 "slices=7/7 runs=800 "

# ── C23 a throwing jq must not fall through to a clean verdict ───────────────────────────────
# `2026-09-18T03:00:00.5.5Z` satisfies the shape regex ([0-9:.]+Z) but after the fractional strip
# becomes `…00.5Z`, which fromdateiso8601 rejects → jq exits 5. rc 5 must NEVER escape as ACTION
# REQUIRED, the pipeline must never continue into a verdict, and jq's own error (which quotes the
# offending value and the runner's tmp path) must not reach the public comment.
default_fixtures; append_runs "$(slice_of $OTHER)" "[{\"id\":\"01M2QJQTHROW00000000000000\",\"functionID\":\"$OTHER\",\"startedAt\":\"2026-09-18T03:00:00.5.5Z\"}]"; run C23
expect "C23 a jq runtime error → CANNOT ESTABLISH jq_failed at the groups site (never 5, never clean)" 3 "reason=jq_failed rc=5 site=groups"
expect_absent "C23 ...jq's error text (the host value) is not republished" "00:00:00.5Z"
expect_absent "C23 ...nor the runner's tmp path" "/runs.json"

# ── C24 the sum-of-slices union check ────────────────────────────────────────────────────────
default_fixtures; _dup="$(jq -c '.runs[0] | .functionID = "'"$(dealt 2 | head -1)"'"' "$WORK/slice-1.json")"; append_runs 2 "[$_dup]"; run C24
expect "C24 one run id reported by two slices for two different functions → union_mismatch" 3 "reason=union_mismatch union=833 sum_of_slices=834"

# ── C25 the horizon guard runs before any GET ────────────────────────────────────────────────
default_fixtures; NOW=1791244800 run C25
expect "C25 past SOAK_STALE (2026-10-06) → horizon_passed" 3 "reason=horizon_passed stale_since=2026-10-06T00:00:00Z"
[[ ! -s "$WORK/calls.log" ]] && pass "C25 ...and no request was made" || fail "C25 a request was made past the horizon"

# ── P-D the rc-filtering trap, driven through a scratch-copy mutant ──────────────────────────
# The tracked probe is never edited; a copy whose clean `exit 5` is replaced by a `set -u` abort
# (raw rc 1) must come back as 3 `unmapped_exit rc=1` — which is what the single EXIT trap buys.
# Bash keeps ONE EXIT trap, so this is also the row a second `trap … EXIT` would red.
sed 's/^  exit 5$/  : "$SOAK_SELFTEST_UNBOUND_VAR"/' "$PROBE" > "$WORK/probe-abort.sh"
if cmp -s "$PROBE" "$WORK/probe-abort.sh"; then
  printf '  FAIL INSTRUMENT: the P-D mutant did not land (no clean `exit 5` at column 2 in the probe).\n' >&2; exit 1
fi
default_fixtures; POPFILE="$POP" PROBE_OVERRIDE="$WORK/probe-abort.sh" NOW=$SOAK_END_EPOCH run PD
expect "P-D a set -u abort at the clean exit site is rewritten to 3 by the trap (never the raw rc 1)" 3 "reason=unmapped_exit rc=1"
unset PROBE_OVERRIDE

# ── summary first, then the anti-vacuity floor and conservation ───────────────────────────────
# The summary precedes the floor so a genuine failure is never reported as "cases were deleted".
printf '\ninngest-soak-6178: %s passed, %s failed\n' "$passes" "$fails"
if [[ "$((passes + fails))" -ne "$checks" ]]; then
  printf '  FAIL INSTRUMENT: passes(%s) + fails(%s) != checks(%s) — a verdict helper is not counting.\n' "$passes" "$fails" "$checks" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
# FLOOR is bound IMMEDIATELY above the floor it feeds: guard-vacuity-floor.test.sh slices the
# floor block backward over contiguous simple assignments only, so a non-assignment line between
# the binding and the `if` leaves the mutant unbound and the floor scored "not constructible".
FLOOR=151
if [[ "$passes" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s PASSES recorded, floor is %s — cases were deleted, skipped, or a helper stopped counting.\n' "$passes" "$FLOOR" >&2
  exit 1
fi
