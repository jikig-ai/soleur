#!/usr/bin/env bash
# Exit-code harness for inngest-soak-6178.sh (#6178 — the ADR-100 Phase-4 soak probe).
#
# THE PROBE IS NOTIFY-ONLY, AND THAT IS THE FIRST PROPERTY THIS SUITE PINS. Its exit code is
# rendered by scripts/sweep-followthroughs.sh as NOT YET (2) / CANNOT ESTABLISH (3) / ACTION
# REQUIRED (5); 0 is the sweeper's CLOSE verb and 1 its REOPEN trigger. Closing #6178 authorises
# an ADR status flip and the release of four rollback snapshots, so neither verb may ever be
# taken by a machine — `assert_never_close_verb` runs after EVERY invocation, including the
# xtrace refusal and the EXIT-trap arm, and H3 proves the helper itself can fire.
#
# THE STUB ASSERTS ITS ARGV. A `curl` that answers regardless of arguments cannot notice the
# probe sending the wrong method, dropping the HMAC header, widening a slice past the page
# cap, or drifting the `from=` anchor — every one of those would stay green forever. The stub
# refuses (exit 64) unless the request carries `-X GET`, `X-Signature-256: sha256=`, both
# CF-Access headers, and — for slices — the pinned URL prefix with `from=2026-09-15T12:40:00Z`
# and at most 11 ids. H2 proves the refusal is live.
#
# EVERY RUN PINS THE CLOCK. `run()` always exports INNGEST_SOAK_NOW_EPOCH (default 1790000000,
# before SOAK_END = 1790083380). Without it an unpinned case would silently flip 2 → 5 on
# 2026-09-22 and still pass — H4 pins the export's presence in this file.
#
# FIXTURES ARE VENDOR-SHAPED, NOT MINIMAL. The on-host probe emits `{runs:[{id,functionID,
# startedAt,…}], total_count:N}`; `startedAt` carries fractional seconds of MIXED precision on
# real rows (measured 2026-09-19: none / 3 / 4 / 5 / 6 digits), and a FATAL body arrives as
# prose, not JSON. Values are synthesized (cq-test-fixtures-synthesized-only): run ids and
# instants are fabricated; the population ids are the committed 52 (the property under test is
# coverage of THAT set).

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
    --max-time|--proto|--noproxy) i=$((i+1)) ;;
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
    [[ "$n" -le 11 ]] || { echo "stub: slice carries $n ids (> 11)" >&2; exit 64; }
    printf '%s\n' "$csv" >> "$cfg/slice-ids.log"
    k="$(( $(cat "$cfg/ordinal" 2>/dev/null || echo 0) + 1 ))"; printf '%s' "$k" > "$cfg/ordinal"
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
pop_ids() { grep -vE '^[[:space:]]*(#|$)' "$POP"; }
# slice_of_index k → the ids the probe's dealer places in slice k (1-based): line i → slice (i-1)%5.
dealt() { pop_ids | awk -v k="$(( $1 - 1 ))" '(NR-1)%5==k'; }
slice_of() { local n; n="$(pop_ids | grep -nF "$1" | cut -d: -f1)"; echo "$(( (n - 1) % 5 + 1 ))"; }
TICKS=16
# slice_fixture <k> [ids...] — one run per (id, hourly tick) on 2026-09-18, mixed startedAt
# precision, unique ULID-shaped ids, total_count = distinct-id count. Slice 1 additionally
# carries the window-head run (2026-09-15T12:40:00.082079Z, the measured global minimum) unless
# NO_WINDOW_HEAD=1.
slice_fixture() {
  local k="$1"; shift
  printf '%s\n' "$@" | jq -R . | jq -s --arg k "$k" --argjson ticks "$TICKS" --arg head "${NO_WINDOW_HEAD:-0}" '
    [ to_entries[] | .key as $i | .value as $fn | range(0; $ticks) as $t
      | { id: ("01M2Q" + $k + "F" + ($i | tostring) + "T" + ($t | tostring) + "ZZZZ"),
          functionID: $fn,
          startedAt: ("2026-09-18T" + (if $t < 10 then "0" else "" end) + ($t | tostring) + ":00:00"
                      + (if ($t % 3) == 0 then "Z" elif ($t % 3) == 1 then ".08Z" else ".101119Z" end)) } ]
    | if ($k == "1" and $head != "1" and length > 0)
      then . + [{ id: "01M2QHEADRUN000000000000", functionID: .[0].functionID, startedAt: "2026-09-15T12:40:00.082079Z" }]
      else . end
    | { runs: ., total_count: (unique_by(.id) | length) }' > "$WORK/slice-$k.json"
}
append_runs() { # append_runs <k> <json-array>
  local k="$1" a="$2" f
  f="$WORK/slice-$k.json"
  jq --argjson a "$a" '.runs += $a | .total_count = (.runs | unique_by(.id) | length)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
set_total_count() { jq --argjson n "$2" '.total_count = $n' "$WORK/slice-$1.json" > "$WORK/t.tmp" && mv "$WORK/t.tmp" "$WORK/slice-$1.json"; }
registry_fixture() { # registry_fixture [count] [omit-id]
  pop_ids | jq -R . | jq -s --argjson extra "$UUID18" --argjson n "${1:-70}" --arg omit "${2:-}" \
    '(. + $extra) | map(select(. != $omit)) | { registry_empty: false, function_count: $n, function_ids: . }' > "$WORK/registry.json"
}
default_fixtures() {
  rm -f "$WORK"/slice-*.json "$WORK"/slice-*.code "$WORK/registry.code" "$WORK/curl.rc"
  registry_fixture
  local k
  for k in 1 2 3 4 5; do
    # shellcheck disable=SC2046
    slice_fixture "$k" $(dealt "$k")
  done
}
# run <id> [args passed after the probe path: -x] — the ONLY launcher.
RUN_ENV=(WEBHOOK_DEPLOY_SECRET=p-secret CF_ACCESS_CLIENT_ID=cf-id CF_ACCESS_CLIENT_SECRET=cf-secret)
run() {
  local name="$1"; shift
  : > "$WORK/calls.log"; : > "$WORK/slice-ids.log"; rm -f "$WORK/ordinal"
  OUT="$(env "${RUN_ENV[@]}" INNGEST_SOAK_NOW_EPOCH="${NOW:-1790000000}" \
        ${POPFILE:+INNGEST_SOAK_POPULATION_FILE="$POPFILE"} \
        PATH="$WORK/bin:$PATH" bash "$@" "$PROBE" 2>&1)"
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
    fail "$name — rc=$RC want=$want_rc :: $(printf '%s' "$OUT" | head -1)"
  elif ! grep -qF -- "$want_sub" <<<"$OUT"; then
    fail "$name — rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -1)"
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

echo "== inngest-soak-6178.sh exit-code harness =="

# ── H1 both verdict helpers can FAIL ──────────────────────────────────────────────────────────
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
RC=99; OUT="nothing like the expected text"
expect "SELFTEST expect (must fail)" 0 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: expect() reports a genuine mismatch as a failure"
else
  printf '  FAIL INSTRUMENT: expect() did NOT fail on a guaranteed mismatch — every case below is decorative.\n' >&2
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

SOAK_END_EPOCH=1790083380   # 2026-09-22T13:23:00Z
MINTER=26e6836b-97ad-503f-8b08-490d8a2f4ce8
CREDIT=2e625d3c-0207-569f-b10b-567bc685ad5e
EXPLAINED_MINTER='[{"id":"01M2QEXPLM1","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:53:07.683Z"},{"id":"01M2QEXPLM2","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:53:08.787Z"},{"id":"01M2QEXPLM3","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:53:10.008Z"},{"id":"01M2QEXPLM4","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:53:11.149Z"}]'
EXPLAINED_CREDIT='[{"id":"01M2QEXPLC1","functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","startedAt":"2026-09-17T12:53:28.576Z"},{"id":"01M2QEXPLC2","functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","startedAt":"2026-09-17T12:53:29.972Z"}]'
add_explained() { append_runs "$(slice_of $MINTER)" "$EXPLAINED_MINTER"; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; }

# ── C0 registry gate ──────────────────────────────────────────────────────────────────────────
default_fixtures; run C0
expect "C0 registry 70 with every population id present → the slices are queried (rc 2)" 2 "NOT YET"
[[ "$(head -1 "$WORK/calls.log")" == *inngest-registry-probe* ]] && pass "C0 the registry is read BEFORE the first slice" || fail "C0 the first request was not the registry probe"
default_fixtures; registry_fixture 71; run C0b
expect "C0b registry function_count=71 → CANNOT ESTABLISH registry_drift" 3 "reason=registry_drift"
default_fixtures; registry_fixture 70 "$MINTER"; run C0c
expect "C0c a population id missing from the registry → registry_drift missing_from_registry=1" 3 "missing_from_registry=1"
default_fixtures; echo 500 > "$WORK/registry.code"; run C0d
expect "C0d registry HTTP 500 → registry_unreadable" 3 "reason=registry_unreadable"
[[ "$(slice_calls)" == 0 ]] && pass "C0d ...and no slice request was made" || fail "C0d slices were requested after an unreadable registry"

# ── C1 / C2 / C3 the three verdicts ──────────────────────────────────────────────────────────
default_fixtures; run C1
expect "C1 clean reading before SOAK_END → NOT YET (rc 2)" 2 "NOT YET"
expect "C1 ...the reading is labelled interim" 2 "interim"
expect "C1 ...the reading block is present" 2 "slices=5/5"
default_fixtures; NOW=$SOAK_END_EPOCH run C2
expect "C2 clean reading at SOAK_END → ACTION REQUIRED (rc 5)" 5 "SOAK CLEAN"
for tok in "adopting" "398857857" "406654994" "407991378" "411798619" "close #6178" "QUALIFIED" "NOT a web-host double-fire detector" "runs=" "slices=5/5"; do
  expect "C2 ...output carries '$tok'" 5 "$tok"
done
expect_absent "C2 ...and does not say investigate" "investigate"
_last="$(printf '%s\n' "$OUT" | tail -n 1)"; _pen="$(printf '%s\n' "$OUT" | tail -n 2 | head -n 1)"
[[ "$_last" == "ACTION REQUIRED:"* && "$_last" == *"SOAK CLEAN"* ]] && pass "C2 the verdict line is the LAST line" || fail "C2 last line is not the verdict: $_last"
[[ "$_pen" == "SCOPE:"* ]] && pass "C2 the SCOPE: line is second-to-last" || fail "C2 second-to-last is not SCOPE: $_pen"
_tail="$(printf '%s\n' "$OUT" | tail -c 4000)"
grep -qF 'SCOPE:' <<<"$_tail" && grep -qF 'SOAK CLEAN' <<<"$_tail" && pass "C2 both survive the sweeper's tail -c 4000" || fail "C2 verdict/scope lost under tail -c 4000"
default_fixtures; add_explained; NOW=$SOAK_END_EPOCH run C3
expect "C3 exactly the two explained groups at SOAK_END → clean (rc 5)" 5 "SOAK CLEAN"
expect "C3 ...the bucket is listed as explained" 5 "explained: functionID=$MINTER bucket=1491374"
expect "C3 ...with the attribution" 5 "op=resume run 35223389582"
expect "C3 ...reading block counts explained=2" 5 "explained=2"
expect_absent "C3 ...and no UNEXPLAINED group line" "UNEXPLAINED:"

# ── C4 an unexplained group ───────────────────────────────────────────────────────────────────
OTHER=11bb44a3-ae8d-57b0-8d41-e76e57f0277a
C4_RUNS='[{"id":"01M2QC4A","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T13:05:00Z"},{"id":"01M2QC4B","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T13:10:00Z"}]'
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C4_RUNS"; NOW=$SOAK_END_EPOCH run C4
expect "C4 explained + a group in bucket 1491375 → ACTION REQUIRED investigate (rc 5)" 5 "investigate"
expect "C4 ...names the unexplained functionID" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491375"
expect "C4 ...renders the bucket window" 5 "2026-09-17T13:00:00Z"
expect "C4 ...explained groups still listed separately" 5 "explained: functionID=$MINTER"
expect "C4 ...verdict says SOAK NOT CLEAN" 5 "SOAK NOT CLEAN"
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C4_RUNS"; run C4b
expect "C4b the same before SOAK_END → NOT YET with the group surfaced" 2 "UNEXPLAINED: functionID=$OTHER"
expect "C4b ...and tells the operator not to wait" 2 "investigate now"

# ── C5 the explained set is EXACT triples ────────────────────────────────────────────────────
C5_RUNS='[{"id":"01M2QC5A","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T12:45:00Z"},{"id":"01M2QC5B","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-17T12:50:00Z"}]'
default_fixtures; add_explained; append_runs "$(slice_of $OTHER)" "$C5_RUNS"; NOW=$SOAK_END_EPOCH run C5
expect "C5 a THIRD function in bucket 1491374 → UNEXPLAINED (a bare-bucket pin would pass it)" 5 "UNEXPLAINED: functionID=$OTHER bucket=1491374"
default_fixtures; add_explained; append_runs "$(slice_of $MINTER)" '[{"id":"01M2QC5BX","functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","startedAt":"2026-09-17T12:55:00Z"}]'; NOW=$SOAK_END_EPOCH run C5b
expect "C5b the minter at count 5 (pin is 4) → UNEXPLAINED" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491374 (2026-09-17T12:40:00Z–2026-09-17T13:00:00Z) count=5"
default_fixtures; append_runs "$(slice_of $CREDIT)" "$EXPLAINED_CREDIT"; append_runs "$(slice_of $MINTER)" "$(jq -c '.[0:3]' <<<"$EXPLAINED_MINTER")"; NOW=$SOAK_END_EPOCH run C5c
expect "C5c the minter at count 3 (below the pin) → UNEXPLAINED, not clean" 5 "UNEXPLAINED: functionID=$MINTER bucket=1491374 (2026-09-17T12:40:00Z–2026-09-17T13:00:00Z) count=3"
default_fixtures; NO_WINDOW_HEAD=1 slice_fixture 1 $(dealt 1); run C5e
expect "C5e earliest run on 2026-09-18 (window head uncovered) → index_eroded" 3 "reason=index_eroded"

# ── C6 / C7 unreadable slices ────────────────────────────────────────────────────────────────
default_fixtures; echo 500 > "$WORK/slice-3.code"; printf '{"error":"boom"}' > "$WORK/slice-3.json"; run C6
expect "C6 slice 3 HTTP 500 with a JSON body → slice_unreadable slice=3/5" 3 "reason=slice_unreadable slice=3/5"
expect "C6 ...cause=other" 3 "cause=other"
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
expect "C7 ...slice=2/5" 3 "slice=2/5"
expect "C7 ...the host's own reason tokens are extracted" 3 "reason=deadline pages_scanned=14"

# ── C8 – C12 shape and completeness ──────────────────────────────────────────────────────────
default_fixtures; printf '{"runs":null,"total_count":7}' > "$WORK/slice-4.json"; run C8
expect "C8 .runs null → CANNOT ESTABLISH" 3 "cause=bad_run_shape"
default_fixtures; printf '{"runs":[],"total_count":0}' > "$WORK/slice-1.json"; run C9
expect "C9 an empty slice → slice_vacuous (never clean)" 3 "reason=slice_vacuous slice=1/5"
default_fixtures; jq '.total_count = "unknown"' "$WORK/slice-1.json" > "$WORK/t.tmp" && mv "$WORK/t.tmp" "$WORK/slice-1.json"; run C9b
expect "C9b total_count \"unknown\" with runs present → total_count_unknown (not vacuous, not clean)" 3 "reason=total_count_unknown slice=1/5"
default_fixtures; set_total_count 5 999; run C10
expect "C10 deduped < total_count (a page went missing) → slice_incomplete" 3 "reason=slice_incomplete slice=5/5 deduped=160 total_count=999"
default_fixtures; append_runs 2 "$(jq -c '[.runs[0]]' "$WORK/slice-2.json")"; run C11
expect "C11 a run repeated across pages is deduped by id → no group (rc 2)" 2 "explained=0 UNEXPLAINED=0"
default_fixtures; append_runs 2 '[{"id":"01M2QNULLSTART","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":null}]'; run C12
expect "C12 a null-startedAt run is counted, not silently dropped (rc 2)" 2 "null_started=1"
expect "C12 ...and creates no group" 2 "UNEXPLAINED=0"
default_fixtures; append_runs 2 '[{"id":"01M2QBADFN","functionID":"not-a-uuid","startedAt":"2026-09-18T03:00:00Z"}]'; run C12b
expect "C12b a non-UUID functionID → bad_run_shape (never printed)" 3 "cause=bad_run_shape"
expect_absent "C12b ...the malformed value is not echoed" "not-a-uuid"
default_fixtures; append_runs 2 '[{"id":"01M2QBADTS","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-18 03:00"}]'; run C12c
expect "C12c a startedAt without T/Z → bad_run_shape" 3 "cause=bad_run_shape"

# ── C13 / C14 credentials ────────────────────────────────────────────────────────────────────
default_fixtures; run C13 -x
expect "C13 bash -x with a live credential → 78 (refused to trace)" 78 "refusing to trace"
[[ ! -s "$WORK/calls.log" ]] && pass "C13 ...and no request was made" || fail "C13 a request was made under xtrace"
expect_absent "C13 ...the credential value never appears in the traced output" "p-secret"
default_fixtures; RUN_ENV=(WEBHOOK_DEPLOY_SECRET=p-secret CF_ACCESS_CLIENT_ID=cf-id CF_ACCESS_CLIENT_SECRET=); run C14
RUN_ENV=(WEBHOOK_DEPLOY_SECRET=p-secret CF_ACCESS_CLIENT_ID=cf-id CF_ACCESS_CLIENT_SECRET=cf-secret)
expect "C14 an empty credential → credentials_unprovisioned (3, not 2)" 3 "reason=credentials_unprovisioned"
expect "C14 ...names the missing one" 3 "CF_ACCESS_CLIENT_SECRET"
[[ ! -s "$WORK/calls.log" ]] && pass "C14 ...and no request was made" || fail "C14 a request was made with a missing credential"

# ── C15 chunking: complete coverage under the cap ────────────────────────────────────────────
default_fixtures; run C15
expect "C15 a clean run" 2 "NOT YET"
[[ "$(slice_calls)" == 5 ]] && pass "C15 exactly 5 slice requests" || fail "C15 slice requests = $(slice_calls), want 5"
_over="$(awk -F, '{ if (NF > 11) c++ } END { print c + 0 }' "$WORK/slice-ids.log")"
[[ "$_over" == 0 ]] && pass "C15 every request carries ≤ 11 ids" || fail "C15 $_over request(s) exceed 11 ids"
if diff <(tr ',' '\n' < "$WORK/slice-ids.log" | sort) <(pop_ids | sort) >/dev/null; then pass "C15 the union of requested ids equals the committed population"; else fail "C15 requested ids ≠ population"; fi
[[ "$(grep -c 'from=2026-09-15T12:40:00Z' "$WORK/calls.log")" == 5 ]] && pass "C15 every slice is pinned to from=2026-09-15T12:40:00Z" || fail "C15 a slice request drifted from the anchor"

# ── C16 / C22 population file ────────────────────────────────────────────────────────────────
default_fixtures; pop_ids | head -51 > "$WORK/pop51.txt"; POPFILE="$WORK/pop51.txt" run C16
expect "C16 a 51-line population → population_malformed" 3 "reason=population_malformed"
[[ ! -s "$WORK/calls.log" ]] && pass "C16 ...and no request was made" || fail "C16 a request was made on a malformed population"
default_fixtures; { echo "# header"; echo; echo "# total_count 127/447/114/25/118 measured 2026-09-19T03:57:28Z"; echo; pop_ids; echo; } > "$WORK/pop52.txt"; POPFILE="$WORK/pop52.txt" run C22
expect "C22 comment lines and blank lines around the 52 ids still parse (rc 2)" 2 "NOT YET"

# ── C17 transport failure ─────────────────────────────────────────────────────────────────────
default_fixtures; echo 7 > "$WORK/curl.rc"; run C17
expect "C17 curl rc 7 → CANNOT ESTABLISH (transport is not a verdict)" 3 "curl_rc=7"

# ── C18 run shape: missing id / null functionID ──────────────────────────────────────────────
default_fixtures; append_runs 2 '[{"functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-18T03:00:00Z"}]'; run C18
expect "C18 a run lacking .id → bad_run_shape (no (fn,startedAt) fallback dedupe)" 3 "cause=bad_run_shape"
default_fixtures; append_runs 2 '[{"id":"01M2QNULLFN","functionID":null,"startedAt":"2026-09-18T03:00:00Z"}]'; run C18b
expect "C18b functionID null → bad_run_shape" 3 "cause=bad_run_shape"

# ── C20 population thin ──────────────────────────────────────────────────────────────────────
default_fixtures; for k in 1 2 3 4 5; do TICKS=6 slice_fixture "$k" $(dealt "$k"); done; run C20
expect "C20 only ~312 distinct runs → population_thin (below RUN_FLOOR=800)" 3 "reason=population_thin"

# ── C23 a throwing jq must not fall through to a clean verdict ───────────────────────────────
# `2026-09-18T03:00:00.5.5Z` satisfies the shape regex ([0-9:.]+Z) but after the fractional strip
# becomes `…00.5Z`, which fromdateiso8601 rejects → jq exits 5. rc 5 must NEVER escape as ACTION
# REQUIRED and the pipeline must never continue into a verdict.
default_fixtures; append_runs 2 '[{"id":"01M2QJQTHROW","functionID":"11bb44a3-ae8d-57b0-8d41-e76e57f0277a","startedAt":"2026-09-18T03:00:00.5.5Z"}]'; run C23
expect "C23 a jq runtime error → CANNOT ESTABLISH jq_failed (never 5, never clean)" 3 "reason=jq_failed"

# ── anti-vacuity floor + conservation ────────────────────────────────────────────────────────
FLOOR=85
if [[ "$passes" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s PASSES recorded, floor is %s — cases were deleted, skipped, or a helper stopped counting.\n' "$passes" "$FLOOR" >&2
  exit 1
fi
if [[ "$((passes + fails))" -ne "$checks" ]]; then
  printf '  FAIL INSTRUMENT: passes(%s) + fails(%s) != checks(%s) — a verdict helper is not counting.\n' "$passes" "$fails" "$checks" >&2
  exit 1
fi

printf '\ninngest-soak-6178: %s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
