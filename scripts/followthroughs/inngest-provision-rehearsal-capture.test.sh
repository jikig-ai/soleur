#!/usr/bin/env bash
#
# (#9175) Test suite for scripts/followthroughs/inngest-provision-rehearsal-capture.sh.
#
# EVERY ARM STUBS betterstack-query.sh (BETTERSTACK_QUERY_SH seam). The script under test is
# the thing that decides whether a paid rehearsal's evidence says PASS, so its decision
# function has to be exercised against every shape the log source can return — including the
# shapes a real rehearsal would be unlucky to produce.
#
# THE PROPERTY THAT MATTERS MOST IS THE ONE ABOUT SILENCE. Zero rows for a brand-new host is
# ambiguous between "the host booted dark" and "the instrument is broken". The script resolves
# it with a SOURCE-LIVENESS anchor, and the arms below pin both directions.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
SUT="${ROOT}/scripts/followthroughs/inngest-provision-rehearsal-capture.sh"

TMP="$(mktemp -d -t ipcap.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2" >&2; return 0; }

printf '\n=== inngest-provision-rehearsal-capture ===\n\n'

[[ -f "$SUT" ]] || { fail "the capture script exists at ${SUT}"; printf '\n=== 0 passed, 1 failed ===\n'; exit 1; }

HOST="soleur-inngest-rehearsal-17250000001"
URL="https://github.com/jikig-ai/soleur/actions/runs/17250000001"

# ── The stub ──────────────────────────────────────────────────────────────────
# Answers by MATCHING THE SQL IT IS HANDED, not by call ordinal — a positional stub lets an
# arm PASS for a reason unrelated to the property under test. Three query shapes exist:
#   * the anchor (`count() AS n`)            -> emits {"n": <ANCHOR_N>}
#   * host rows  (`position(raw, 'HOST')`)   -> emits fixture rows, dt-bound applied
#   * TSV unless the SQL asks FORMAT JSONEachRow — the real transport's default.
#   * a host-confined anchor SQL is refused (the anchor must be source-liveness).
#   * both use the same raw/JSONEachRow contract as the real transport.
# The dt bound is read OUT of the SQL (parseDateTime64BestEffort or now()-INTERVAL), so the
# stub applies the same window the real server would — a bound the SUT forgot shows up as an
# empty set, not as a stub fixture.
cat > "$TMP/bs-stub.py" <<'PY'
import json, re, sys, datetime, os
sql = sys.argv[1]
rows_path = os.environ.get("STUB_ROWS", "")
anchor_n = os.environ.get("STUB_ANCHOR", "0")
# Transport-faithful: the real ClickHouse HTTP default is TabSeparated; the SUT must ask
# for JSONEachRow explicitly. An anchor that carries a host needle is refused — the anchor
# must be source-liveness, not host-keyed, or "the instrument is dead" reads as a dark host.
if "FORMAT JSONEachRow" not in sql:
    print("n\n0")  # TSV: a lone column name + row, unparseable as the SUT's JSON
    sys.exit(0)
if "count()" in sql and "AS n" in sql and "position(" in sql:
    print('{"exception":"host-confined anchor refused by stub"}')
    sys.exit(0)

def cutoff(sql):
    # 3-arg form (s, precision, tz): arg 2 is PRECISION — a 2-arg (s, 'UTC') call is a
    # server-side Code 43, which is why the SUT emits the explicit precision.
    m = re.search(r"parseDateTime64BestEffort\('([0-9:\-T]+)'", sql)
    if m: return m.group(1)
    m = re.search(r"now\(\) - INTERVAL ([0-9]+) (MINUTE|HOUR|DAY|WEEK|MONTH)", sql)
    if not m: return "1970-01-01T00:00:00"
    n, unit = int(m.group(1)), m.group(2)
    mult = {"MINUTE": 60, "HOUR": 3600, "DAY": 86400, "WEEK": 604800, "MONTH": 2592000}[unit]
    return (datetime.datetime.utcnow() - datetime.timedelta(seconds=n * mult)).strftime("%Y-%m-%dT%H:%M:%S")

if "count()" in sql and "AS n" in sql:
    print(json.dumps({"n": anchor_n}))
    sys.exit(0)
if not rows_path or not os.path.exists(rows_path):
    sys.exit(0)
host = re.search(r"position\(raw, '([^']+)'\)", sql).group(1)
cut = cutoff(sql)
for line in open(rows_path):
    line = line.strip()
    if not line: continue
    row = json.loads(line)
    if host not in row.get("raw", ""): continue
    if row.get("dt", "") <= cut: continue
    print(json.dumps(row))
PY
STUB="$TMP/bs-stub.sh"
printf '#!/usr/bin/env bash\nexec python3 "%s" "$1"\n' "$TMP/bs-stub.py" > "$STUB"
chmod +x "$STUB"

# run <label> <want-rc> <extra-env...> -- <sut args...>; asserts rc and the terminal sentinel.
run() {
  local label="$1" wrc="$2"; shift 2
  local envs=() args=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  args=("$@")
  local out rc
  out="$(env "${envs[@]}" bash "$SUT" "${args[@]}" 2>&1)"; rc=$?
  if [[ "$rc" != "$wrc" ]]; then
    fail "$label — rc=${rc} (wanted ${wrc})" "$out"; return 1
  fi
  if ! grep -qF "INNGEST_PROVISION_CAPTURE_VERDICT=${rc}" < <(printf '%s' "$out"); then
    fail "$label — terminal sentinel missing or wrong (wanted VERDICT=${rc})" "$out"; return 1
  fi
  pass "$label"
  return 0
}

NOW="$(date -u +%Y-%m-%dT%H:%M:%S)"
# rows <file> <dt> <raw-lines...>: JSONEachRow fixtures; every raw embeds $HOST.
rows() {
  local f="$1" dt="$2"; shift 2
  : > "$f"
  local r
  for r in "$@"; do
    printf '{"dt":"%s","raw":"%s"}\n' "$dt" "$(printf '%s' "$r" | sed 's/"/\\"/g')" >> "$f"
  done
}

BASE_ENV=(STUB_ANCHOR=500 BETTERSTACK_QUERY_SH="$STUB" SOLEUR_TEST_MODE=1)
BASE_ARGS=(--host-name "$HOST" --evidence-url "$URL" --out "$TMP/ev.env" --window "2 HOUR")

# ── refusal arms (usage 64, never a verdict) ──────────────────────────────────
run "prod host name is refused (soleur-inngest is not rehearsal-scoped)" 64 "${BASE_ENV[@]}" -- \
  --host-name soleur-inngest --evidence-url "$URL" --mode phase-a --out "$TMP/e.env"
run "a host name with no run suffix is refused" 64 "${BASE_ENV[@]}" -- \
  --host-name soleur-inngest-rehearsal --evidence-url "$URL" --mode phase-a --out "$TMP/e.env"
run "host/url naming DIFFERENT runs is refused" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "https://github.com/jikig-ai/soleur/actions/runs/99999" --mode phase-a --out "$TMP/e.env"
run "a non-Actions evidence URL is refused" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "https://example.com/x" --mode phase-a --out "$TMP/e.env"
run "a malformed --window is refused (it reaches the SQL)" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "$URL" --mode phase-a --window "0 DAY OR 1=1" --out "$TMP/e.env"
run "post-reboot without --reboot-since is refused (the boundary is the whole claim)" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "$URL" --mode post-reboot --out "$TMP/e.env"
run "a malformed --reboot-since is refused" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "$URL" --mode post-reboot --reboot-since "yesterday" --out "$TMP/e.env"
run "an unknown --mode is refused" 64 "${BASE_ENV[@]}" -- \
  --host-name "$HOST" --evidence-url "$URL" --mode destroy --out "$TMP/e.env"

# ── TRANSIENT arms (instrument silent or dead) ────────────────────────────────
run "dead source anchor -> TRANSIENT (never FAIL)" 2 STUB_ANCHOR=0 BETTERSTACK_QUERY_SH="$STUB" -- \
  "${BASE_ARGS[@]}" --mode phase-a
cat > "$TMP/dead-stub.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
chmod +x "$TMP/dead-stub.sh"
run "anchor query transport failure -> TRANSIENT" 2 STUB_ANCHOR=500 BETTERSTACK_QUERY_SH="$TMP/dead-stub.sh" -- \
  "${BASE_ARGS[@]}" --mode phase-a

# ── phase-a arms ──────────────────────────────────────────────────────────────
: > "$TMP/ev.env"
rows "$TMP/r-phasea.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed detail=timer=enabled unit=inactive iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout detail=boot=deadbee1.waited_s=150 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=2 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-nic-ABSENT detail=ip=10.0.1.60 attempt=2 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-exit-1 detail=attempt=2 why=provision-nic-ABSENT iid=abc123 \"host\":\"${HOST}\""
run "phase-a PASS: armed + 2 attempts + NIC-absent observed + zero bootstrap-done" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-phasea.json" -- "${BASE_ARGS[@]}" --mode phase-a
grep -qF 'REHEARSAL_PHASE_A_OBSERVED=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_PHASE_A_OBSERVED=PASS" \
  || fail "evidence file carries REHEARSAL_PHASE_A_OBSERVED=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-oneattempt.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed detail=iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout detail=boot=deadbee1.waited_s=150 \"host\":\"${HOST}\""
run "phase-a TRANSIENT: only one attempt so far (absence polls, does not fail)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-oneattempt.json" -- "${BASE_ARGS[@]}" --mode phase-a

rows "$TMP/r-baddone.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed detail=iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=2 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout detail=boot=deadbee1.waited_s=150 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done detail=attempt=2 iid=abc123 \"host\":\"${HOST}\""
run "phase-a FAIL: bootstrap-done while the NIC was absent (the property under test, broken)" 1 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-baddone.json" -- "${BASE_ARGS[@]}" --mode phase-a

: > "$TMP/empty-rows.json"
run "phase-a TRANSIENT: live anchor but zero host rows (dark so far, not dark forever)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/empty-rows.json" -- "${BASE_ARGS[@]}" --mode phase-a

# ── phase-b arms ──────────────────────────────────────────────────────────────
# THE P0 REGRESSION CASE (architecture review): private_nic_ok is emitted ONLY by the
# nic-wait helper, which runs only when nic_present FAILS — after the attach converges the
# next attempt skips it entirely. bootstrap-done must pass with nic_ok ABSENT.
rows "$TMP/r-phaseb.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=3 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-exit-1 detail=attempt=3 why=pull-timeout iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=4 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done detail=attempt=4 iid=abc123 \"host\":\"${HOST}\""
run "phase-b PASS: bootstrap-done ALONE (private_nic_ok is unreachable in the happy path)" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-phaseb.json" -- "${BASE_ARGS[@]}" --mode phase-b
grep -qF 'REHEARSAL_PHASE_B_RECOVERY=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_PHASE_B_RECOVERY=PASS" \
  || fail "evidence file carries REHEARSAL_PHASE_B_RECOVERY=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-nodone.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_ok detail=boot=cafe0002.waited_s=4 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=3 iid=abc123 \"host\":\"${HOST}\""
run "phase-b TRANSIENT: nic converged but bootstrap-done not yet emitted" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-nodone.json" -- "${BASE_ARGS[@]}" --mode phase-b

# bootstrap-done-DEGRADED writes NO latch — a substring match must not count it as done.
rows "$TMP/r-degraded.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done-DEGRADED detail=attempt=4 why=.redis-inactive iid=abc123 \"host\":\"${HOST}\""
run "phase-b TRANSIENT: bootstrap-done-DEGRADED is NOT bootstrap-done (no latch was written)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-degraded.json" -- "${BASE_ARGS[@]}" --mode phase-b

# ── post-reboot arms ──────────────────────────────────────────────────────────
PRE_REBOOT="2026-01-01T00:00:00"
rows "$TMP/r-latch.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bs-token-restaged detail=ok=1.boot-trace.channel.re-armed \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=some-unrelated detail=harmless \"host\":\"${HOST}\""
run "post-reboot PASS: restage anchor re-emitted ON THE PHONE-HOME CHANNEL, zero provision rows after boundary" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-latch.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"
grep -qF 'REHEARSAL_POST_REBOOT_LATCH=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_POST_REBOOT_LATCH=PASS" \
  || fail "evidence file carries REHEARSAL_POST_REBOOT_LATCH=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-brokenlatch.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bs-token-restaged detail=ok=1 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=5 iid=abc123 \"host\":\"${HOST}\""
run "post-reboot FAIL: a provision-attempt-start after the boundary (latch broken)" 1 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-brokenlatch.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"

# THE CHANNEL-MISMATCH CASE (architecture review): the logger'd SOLEUR_INNGEST_BS_TOKEN_RESTAGED
# rides journald -> Vector, a DIFFERENT channel than the provision markers. Vector alive while
# phone-home is dead would vouch for a silence that was never measured — TRANSIENT, not PASS.
rows "$TMP/r-vectoronly.json" "$NOW" \
  "inngest-bs-token-restage[999]: SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 path=/run/inngest-bs-logs-token \"host\":\"${HOST}\""
run "post-reboot TRANSIENT: Vector-only restage does not vouch for the phone-home silence" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-vectoronly.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"

rows "$TMP/r-norestage.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=unrelated detail=harmless \"host\":\"${HOST}\""
run "post-reboot TRANSIENT: restage anchor not yet emitted after the boundary" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-norestage.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"

# pre-boundary rows must NOT count toward post-reboot assertions — the dt bound is real.
rows "$TMP/r-preboundary.json" "$PRE_REBOOT" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bs-token-restaged detail=ok=1 \"host\":\"${HOST}\""
run "post-reboot TRANSIENT: pre-boundary rows do not count (restage row older than --reboot-since)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-preboundary.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "2026-06-01T00:00:00"

# A bootstrap-done-DEGRADED after the boundary IS a provision marker (the unit re-entered,
# even if it finished degraded) — the latch assertion is zero provision rows, no exception.
rows "$TMP/r-postdegraded.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bs-token-restaged detail=ok=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done-DEGRADED detail=attempt=1 iid=abc123 \"host\":\"${HOST}\""
run "post-reboot FAIL: bootstrap-done-DEGRADED after the boundary is still provision re-entry" 1 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-postdegraded.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "2026-06-01T00:00:00"

# --since IS THE SAME-RUN-ID RE-RUN GATE (the workflow passes it on every capture call): a
# prior life's bootstrap-done inside the window would trip the no-done check, but the bound
# excludes it — this arm proves the bound is wired, not just parsed.
SINCE_BOUND="2026-06-01T00:00:00"
rows "$TMP/r-since.json" "2026-05-31T00:00:00" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed detail=iid=zzz999 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done detail=attempt=9 iid=zzz999 \"host\":\"${HOST}\""
rows "$TMP/r-since.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed detail=iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=1 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start detail=attempt=2 iid=abc123 \"host\":\"${HOST}\"" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout detail=boot=deadbee1.waited_s=150 \"host\":\"${HOST}\""
run "phase-a PASS under --since: a prior life's rows are excluded by the bound" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-since.json" -- "${BASE_ARGS[@]}" --mode phase-a --since "$SINCE_BOUND" --out "$TMP/ev-since.env"

# ── floors (ADR-193): the ledger, never a bare counter ────────────────────────
# `fails` is a scalar counter for exactly this floor: the vacuity guard's mutant slice
# initializes counters (`X=$((X+1))` increments) but not the FAILURES array — a floor on
# `${#FAILURES[@]}` dies unbound under set -u and scores CONSTRUCTION, not FIRES. And MIN
# must sit ADJACENT to the `if` — the mutant builder's walk-back stops at any comment.
MIN=19
if (( passes + fails < MIN )); then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((passes + fails))" "$MIN" >&2
  exit 1
fi
printf '\n=== %s passed, %s failed ===\n\n' "$passes" "${#FAILURES[@]}"
for f in ${FAILURES[@]+"${FAILURES[@]}"}; do printf '  FAIL %s\n' "$f"; done
exit $(( ${#FAILURES[@]} > 0 ))
