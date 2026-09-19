#!/usr/bin/env bash
# Mutation battery for tests/scripts/test-registry-delivery-change.sh (#8279).
#
# A committed battery, not a transcript: each row mutates a SANDBOX COPY of the helper (never the
# worktree), asserts the mutation LANDED (a mutation that does not land reports the baseline,
# which is indistinguishable from a pass), runs the suite, and requires the NAMED row to red.
# Rows are chosen by AXIS (request shape, cardinality, direction, arm), not by count — see the
# review of PR #8355 for the survivors each one closes.
#
# Registered in scripts/test-all.sh next to the suite it guards (tests/scripts/ is not globbed).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0; FAIL=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

SB="$(mktemp -d)" || exit 2
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/scripts/lib" "$SB/tests/scripts"
cp "$ROOT/scripts/registry-delivery-change.sh" "$SB/scripts/"
cp "$ROOT/scripts/lib/strip-log-injection.sh" "$SB/scripts/lib/"
cp "$ROOT/tests/scripts/test-registry-delivery-change.sh" "$SB/tests/scripts/"
SUT="$SB/scripts/registry-delivery-change.sh"; SUITE="$SB/tests/scripts/test-registry-delivery-change.sh"
cp "$SUT" "$SB/pristine.sh"

# CONTROL first: a red baseline voids every row.
if bash "$SUITE" > "$SB/control.log" 2>&1 && grep -qE '^=== Results: [0-9]+/[0-9]+ passed, 0 failed ===$' "$SB/control.log"; then
  pass "control: the unmutated sandbox suite is GREEN ($(tail -1 "$SB/control.log"))"
else
  echo "  FATAL: control is RED in the sandbox — every row below would be noise: $(tail -1 "$SB/control.log")" >&2; exit 2
fi

# row <name> <expect-red-row-regex> <python-old> <python-new>
row() {
  local name="$1" want="$2" old="$3" new="$4"
  cp "$SB/pristine.sh" "$SUT"
  if ! OLD="$old" NEW="$new" python3 - "$SUT" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); old = os.environ["OLD"]; new = os.environ["NEW"]
n = s.count(old)
if n != 1: print(f"anchor count {n} for {old[:60]!r}", file=sys.stderr); sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
  then fail "$name: mutation anchor not found (the SUT drifted — re-anchor the row)"; cp "$SB/pristine.sh" "$SUT"; return; fi
  if cmp -s "$SB/pristine.sh" "$SUT"; then fail "$name: mutation did NOT land"; return; fi
  bash "$SUITE" > "$SB/row.log" 2>&1; local rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qE "^  FAIL: ($want)" "$SB/row.log"; then
    pass "$name: KILLED by $(grep -oE "^  FAIL: ($want)[^:]*" "$SB/row.log" | head -1 | sed 's/^  FAIL: //')"
  elif [[ "$rc" -ne 0 ]]; then
    fail "$name: reddened, but not the named row ($(grep -E '^  FAIL' "$SB/row.log" | grep -v canary | head -1))"
  else
    fail "$name: SURVIVED ($(tail -1 "$SB/row.log"))"
  fi
  cp "$SB/pristine.sh" "$SUT"
}

# ── axis: request shape (the two string-built URLs) ──────────────────────────────────────────
row "E1 reversed compare range" 'T1' \
  'cmp_json="$(api "repos/${REPO}/compare/${BEFORE}...${AFTER}")"' \
  'cmp_json="$(api "repos/${REPO}/compare/${AFTER}...${BEFORE}")"'
row "E3 listing from the watermark instead of after" 'T1' \
  '-f sha="$AFTER" -f path="$CFG"' '-f sha="$BEFORE" -f path="$CFG"'
row "compare carries a paging param (250-cap contract)" 'T1|T10' \
  'cmp_json="$(api "repos/${REPO}/compare/' 'cmp_json="$(api -F per_page=100 "repos/${REPO}/compare/'
# ── axis: arm ───────────────────────────────────────────────────────────────────────────────
row "seam guard removed" 'T12' \
  'if [[ -n "${GITHUB_ACTIONS:-}" && -n "${REGISTRY_DELIVERY_GH_CMD:-}" ]]; then' 'if [[ 1 -eq 0 ]]; then'
row "failed /pulls treated as empty (subject picks the target)" 'T21' \
  '  if [[ "$rc" -ne 0 ]]; then' '  if [[ "$rc" -eq 999 ]]; then'
row "proven-no-touch falls back to [after]" 'T11|T15' \
  '        note "no commit in range touched ${CFG}"' '        CANDIDATES=("$AFTER")'
row "range intersection dropped (path list unfiltered)" 'T11|T3' \
  'grep -Fxq -- "$s" "$touch_file" && CANDIDATES+=("$s")' 'CANDIDATES+=("$s")'
row "B4 watermark SHA re-attributed on an identical re-fire" 'T15' \
  '      if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then' \
  '      grep -Fxq -- "$AFTER" "$touch_file" && CANDIDATES+=("$AFTER"); if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then'
row "identical treated as unproven" 'T15' \
  '"$status" != "identical"' '"$status" != "never"'
# ── axis: cardinality ───────────────────────────────────────────────────────────────────────
row "join collapses to the first part" 'T2|T2c|T4c' \
  'do out="${out:+$out; }$x"; done' 'do out="${out:-$x}"; done'
row "join uses a bare ;" 'T2|T4c' \
  'out="${out:+$out; }$x"' 'out="${out:+$out;}$x"'
row "PR dedupe dropped" 'T13' \
  '[[ "$seen" -eq 0 ]] && PRS+=("$pr")' 'PRS+=("$pr")'
row "MAX_LOOKUPS cap dropped" 'T14' 'MAX_LOOKUPS=10' 'MAX_LOOKUPS=1000'
row "/pulls takes the first entry regardless of merged_at" 'T9b' \
  "'[.[] | select(.merged_at != null)][0].number // empty'" "'.[0].number // empty'"
# ── axis: direction (a transform made MORE aggressive) ──────────────────────────────────────
row "C1 strip eats every non-ASCII byte" 'T1|T16' \
  "LC_ALL=C tr -d '\\000-\\037'" "LC_ALL=C tr -d '\\000-\\037\\177-\\377'"
row "C4 subject fallback reads the whole message" 'T7c' \
  'n="$(printf '"'"'%s'"'"' "${SUBJECT[$sha]:-}" | head -n 1 | tr -d' \
  'n="$(printf '"'"'%s'"'"' "${SUBJECT[$sha]:-}" | tr -d'
row "subject cap dropped" 'T20' 'printf '"'"'%s'"'"' "${s:0:200}"' 'printf '"'"'%s'"'"' "$s"'
row "unanchored (#N) fallback" 'T7b' '(?=\)$)' '(?=\))'
row "SHA regex dropped" 'T18' 'is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }' 'is_sha() { return 0; }'
row "control-char strip dropped" 'T16' \
  "| head -n 1 | strip_log_injection" "| head -n 1"
row "compare failure exits 1" 'T6' '    note "compare rc=${crc}"' '    exit 1'

# ── anti-vacuity: helper self-test + a floor that reads the append-only ledger ───────────────
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
if [[ "$PASS" -lt 21 ]]; then printf '  FATAL: anti-vacuity: only %s passes; the floor is 21 (one control + 20 rows).\n' "$PASS" >&2; exit 2; fi
cmp -s "$SB/pristine.sh" "$SUT" || { printf '  FATAL: the sandbox SUT was left mutated.\n' >&2; exit 2; }
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
