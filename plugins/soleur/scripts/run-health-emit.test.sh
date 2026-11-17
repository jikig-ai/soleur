#!/usr/bin/env bash
# Tests for run-health-emit.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/run-health-emit.sh"

TMP="$(mktemp -d -t runhealth.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; return 0; }

# Case 1: creates run_health.json with required fields
RD="$TMP/run1"
printf 'prompt text' > "$TMP/p.md"
bash "$SUT" --run-dir "$RD" --run-id r1 --issue 12573 --branch b --harness opencode --phase 0 --status started --prompt-file "$TMP/p.md"
if [[ -f "$RD/run_health.json" ]] && python3 -c "import json,sys; d=json.load(open('$RD/run_health.json')); sys.exit(0 if d['run_id']=='r1' and d['issue']=='12573' and len(d['phases'])==1 else 1)"; then
  pass "creates run_health.json with required fields"
else
  fail "creates run_health.json with required fields"
fi

# Case 2: idempotent upsert (same phase updates, no duplicate)
bash "$SUT" --run-dir "$RD" --phase 0 --status completed
N=$(python3 -c "import json; print(len(json.load(open('$RD/run_health.json'))['phases']))")
if [[ "$N" == "1" ]]; then pass "idempotent upsert (no duplicate phase)"; else fail "idempotent upsert" "got $N"; fi

# Case 3: prompt snapshot created and not overwritten on retry
if [[ -f "$RD/phase_prompts/0.md" ]] && grep -q "prompt text" "$RD/phase_prompts/0.md"; then
  pass "prompt snapshot created"
else
  fail "prompt snapshot created"
fi

# Case 4: retry creates attempt-2 file, preserves original
printf 'retry prompt' > "$TMP/p2.md"
bash "$SUT" --run-dir "$RD" --phase 0 --status started --prompt-file "$TMP/p2.md"
if [[ -f "$RD/phase_prompts/0.attempt-2.md" ]] && grep -q "retry prompt" "$RD/phase_prompts/0.attempt-2.md" && grep -q "prompt text" "$RD/phase_prompts/0.md"; then
  pass "retry preserves original snapshot"
else
  fail "retry preserves original snapshot"
fi

# Case 5: missing required args exits 0 (non-fatal)
bash "$SUT" --run-dir "$RD" 2>/dev/null; rc=$?
if [[ "$rc" == "0" ]]; then pass "missing args non-fatal"; else fail "missing args non-fatal" "rc=$rc"; fi

echo "passes=$passes fails=$fails"
[[ "$fails" -eq 0 ]]