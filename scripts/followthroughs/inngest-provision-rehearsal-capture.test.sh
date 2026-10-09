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
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2" >&2; return 0; }

printf '\n=== inngest-provision-rehearsal-capture ===\n\n'

[[ -f "$SUT" ]] || { fail "the capture script exists at ${SUT}"; printf '\n=== 0 passed, 1 failed ===\n'; exit 1; }

HOST="soleur-inngest-rehearsal-17250000001"
URL="https://github.com/jikig-ai/soleur/actions/runs/17250000001"

# ── The stub ──────────────────────────────────────────────────────────────────
# Answers by MATCHING THE SQL IT IS HANDED, not by call ordinal — a positional stub lets an
# arm PASS for a reason unrelated to the property under test. Three query shapes exist:
#   * the anchor (`count() AS n`)            -> emits {"n": <ANCHOR_N>}
#   * host rows  (`position(raw, 'HOST')`)   -> emits fixture rows, dt-bound applied
#   * both use the same raw/JSONEachRow contract as the real transport.
# The dt bound is read OUT of the SQL (parseDateTime64BestEffort or now()-INTERVAL), so the
# stub applies the same window the real server would — a bound the SUT forgot shows up as an
# empty set, not as a stub fixture.
cat > "$TMP/bs-stub.py" <<'PY'
import json, re, sys, datetime, os
sql = sys.argv[1]
rows_path = os.environ.get("STUB_ROWS", "")
anchor_n = os.environ.get("STUB_ANCHOR", "0")

def cutoff(sql):
    m = re.search(r"parseDateTime64BestEffort\('([0-9:\-T]+)'\)", sql)
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
  if ! printf '%s' "$out" | grep -qF "INNGEST_PROVISION_CAPTURE_VERDICT=${rc}"; then
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
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed host=${HOST} detail=timer=enabled unit=inactive iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=1 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout host=${HOST} detail=boot=deadbee1.waited_s=150" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=2 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-nic-ABSENT host=${HOST} detail=ip=10.0.1.60 attempt=2 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-exit-1 host=${HOST} detail=attempt=2 why=provision-nic-ABSENT iid=abc123"
run "phase-a PASS: armed + 2 attempts + NIC-absent observed + zero bootstrap-done" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-phasea.json" -- "${BASE_ARGS[@]}" --mode phase-a
grep -qF 'REHEARSAL_PHASE_A_OBSERVED=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_PHASE_A_OBSERVED=PASS" \
  || fail "evidence file carries REHEARSAL_PHASE_A_OBSERVED=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-oneattempt.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed host=${HOST} detail=iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=1 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout host=${HOST} detail=boot=deadbee1.waited_s=150"
run "phase-a TRANSIENT: only one attempt so far (absence polls, does not fail)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-oneattempt.json" -- "${BASE_ARGS[@]}" --mode phase-a

rows "$TMP/r-baddone.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-unit-armed host=${HOST} detail=iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=1 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=2 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_timeout host=${HOST} detail=boot=deadbee1.waited_s=150" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done host=${HOST} detail=attempt=2 iid=abc123"
run "phase-a FAIL: bootstrap-done while the NIC was absent (the property under test, broken)" 1 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-baddone.json" -- "${BASE_ARGS[@]}" --mode phase-a

run "phase-a TRANSIENT: live anchor but zero host rows (dark so far, not dark forever)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/empty-rows.json" -- "${BASE_ARGS[@]}" --mode phase-a

# ── phase-b arms ──────────────────────────────────────────────────────────────
rows "$TMP/r-phaseb.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_ok host=${HOST} detail=boot=cafe0002.waited_s=4.by=99-soleur-private-fallback" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=3 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-exit-1 host=${HOST} detail=attempt=3 why=pull-timeout iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=4 iid=abc123" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=bootstrap-done host=${HOST} detail=attempt=4 iid=abc123"
run "phase-b PASS: nic_ok + bootstrap-done (mid-window retry exit rows are informational)" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-phaseb.json" -- "${BASE_ARGS[@]}" --mode phase-b
grep -qF 'REHEARSAL_PHASE_B_RECOVERY=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_PHASE_B_RECOVERY=PASS" \
  || fail "evidence file carries REHEARSAL_PHASE_B_RECOVERY=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-nodone.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=private_nic_ok host=${HOST} detail=boot=cafe0002.waited_s=4" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=3 iid=abc123"
run "phase-b TRANSIENT: nic converged but bootstrap-done not yet emitted" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-nodone.json" -- "${BASE_ARGS[@]}" --mode phase-b

# ── post-reboot arms ──────────────────────────────────────────────────────────
PRE_REBOOT="2026-01-01T00:00:00"
rows "$TMP/r-latch.json" "$NOW" \
  "inngest-bs-token-restage[999]: SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 path=/run/inngest-bs-logs-token host=${HOST}" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=some-unrelated host=${HOST} detail=harmless"
run "post-reboot PASS: restage anchor re-emitted, ZERO provision markers after boundary" 0 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-latch.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"
grep -qF 'REHEARSAL_POST_REBOOT_LATCH=PASS' "$TMP/ev.env" && pass "evidence file carries REHEARSAL_POST_REBOOT_LATCH=PASS" \
  || fail "evidence file carries REHEARSAL_POST_REBOOT_LATCH=PASS" "$(cat "$TMP/ev.env")"

rows "$TMP/r-brokenlatch.json" "$NOW" \
  "inngest-bs-token-restage[999]: SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 host=${HOST}" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=5 iid=abc123"
run "post-reboot FAIL: a provision-attempt-start after the boundary (latch broken)" 1 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-brokenlatch.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"

rows "$TMP/r-norestage.json" "$NOW" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=unrelated host=${HOST} detail=harmless"
run "post-reboot TRANSIENT: restage anchor not yet emitted after the boundary" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-norestage.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "$PRE_REBOOT"

# pre-boundary rows must NOT count toward post-reboot assertions — the dt bound is real.
rows "$TMP/r-preboundary.json" "$PRE_REBOOT" \
  "SOLEUR_INNGEST_BOOT_STAGE stage=provision-attempt-start host=${HOST} detail=attempt=1 iid=abc123" \
  "inngest-bs-token-restage[999]: SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 host=${HOST}"
run "post-reboot TRANSIENT: pre-boundary rows do not count (restage row older than --reboot-since)" 2 \
  "${BASE_ENV[@]}" STUB_ROWS="$TMP/r-preboundary.json" -- "${BASE_ARGS[@]}" --mode post-reboot --reboot-since "2026-06-01T00:00:00"

# ── floors (ADR-193): the ledger, never a bare counter ────────────────────────
MIN=19
if (( passes + ${#FAILURES[@]} < MIN )); then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((passes + ${#FAILURES[@]}))" "$MIN" >&2
  exit 1
fi
printf '\n=== %s passed, %s failed ===\n\n' "$passes" "${#FAILURES[@]}"
for f in ${FAILURES[@]+"${FAILURES[@]}"}; do printf '  FAIL %s\n' "$f"; done
exit $(( ${#FAILURES[@]} > 0 ))
