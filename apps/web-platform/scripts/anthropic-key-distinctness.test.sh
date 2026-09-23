#!/usr/bin/env bash
# Tests for anthropic-key-distinctness.sh (#8505, Guard 1 in the plan).
#
# Run via:  bash apps/web-platform/scripts/anthropic-key-distinctness.test.sh
#
# A fake `doppler` on PATH serves SYNTHESIZED values per config from a fixture
# directory. It refuses (exit 64) any argv shape the script is not supposed to
# send, so a script that queried the wrong thing cannot read a right answer.
# The live Doppler API is never called.

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/anthropic-key-distinctness.sh"
[[ -x "$SCRIPT" ]] || { printf 'ERROR: %s not found or not executable\n' "$SCRIPT" >&2; exit 1; }

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Helper self-test (ADR-193): both helpers must move their counters.
( pass probe >/dev/null; [[ "$PASS" == 1 ]] ) || { printf '[FATAL] pass() does not count\n' >&2; exit 1; }
( fail probe >/dev/null; [[ "$FAIL" == 1 ]] ) || { printf '[FATAL] fail() does not count\n' >&2; exit 1; }

ROOT="$(mktemp -d)"
trap 'rm -rf -- "$ROOT"' EXIT
case "$ROOT" in /*) : ;; *) printf '[FATAL] mktemp returned a non-absolute path\n' >&2; exit 2 ;; esac

BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/doppler" <<'FAKE'
#!/usr/bin/env bash
# configs:  doppler configs -p soleur --json
# secrets:  doppler secrets get ANTHROPIC_API_KEY -p soleur -c <cfg> --plain
printf '%s\n' "$*" >> "$FIX/calls"
if [[ "$*" == "configs -p soleur --json" ]]; then
  [[ -f "$FIX/configs.fail" ]] && { echo "Doppler Error: network" >&2; exit 1; }
  cat "$FIX/configs.json"; exit 0
fi
if [[ "$1 $2 $3 $4 $5 $6 $8" == "secrets get ANTHROPIC_API_KEY -p soleur -c --plain" && $# -eq 8 ]]; then
  cfg="$7"
  if [[ -f "$FIX/val.$cfg.error" ]]; then echo "Doppler Error: Unable to reach Doppler" >&2; exit 1; fi
  if [[ ! -f "$FIX/val.$cfg" ]]; then echo "Doppler Error: Could not find requested secret: ANTHROPIC_API_KEY" >&2; exit 1; fi
  cat "$FIX/val.$cfg"; exit 0
fi
echo "fake doppler: unexpected argv: $*" >&2
exit 64
FAKE
chmod +x "$BIN/doppler"

CI_VAL="sk-ant-test-ci-0000000000"
PRD_VAL="sk-ant-test-prd-1111111111"

# new_fixture <configs...> — fresh fixture dir, configs.json listing the names.
new_fixture() {
  FIX="$(mktemp -d "$ROOT/fix.XXXXXX")"
  export FIX
  local names=""
  for c in "$@"; do names+="{\"name\":\"$c\"},"; done
  printf '[%s]' "${names%,}" > "$FIX/configs.json"
}
setval() { printf '%s' "$2" > "$FIX/val.$1"; }

# run_case <name> <expected-rc> [expected-stdout-literal]
run_case() {
  local name="$1" want_rc="$2" want_out="${3:-}" rc=0
  PATH="$BIN:$PATH" bash "$SCRIPT" > "$ROOT/out" 2> "$ROOT/err" || rc=$?
  if [[ "$rc" != "$want_rc" ]]; then
    fail "$name: rc=$rc want $want_rc (stdout: $(tr '\n' '|' < "$ROOT/out") stderr: $(tr '\n' '|' < "$ROOT/err"))"
    return
  fi
  if [[ -n "$want_out" ]] && ! grep -qxF -- "$want_out" "$ROOT/out"; then
    fail "$name: stdout lacks the line '$want_out'"; return
  fi
  if [[ "$want_rc" != 0 ]] && grep -qxF DISTINCT "$ROOT/out"; then
    fail "$name: printed DISTINCT on a non-zero exit"; return
  fi
  # No synthesized value may ever appear on either stream.
  if grep -qF -e "$CI_VAL" -e "$PRD_VAL" "$ROOT/out" "$ROOT/err"; then
    fail "$name: a key value leaked to stdout/stderr"; return
  fi
  if grep -q 'unexpected argv' "$ROOT/err"; then
    fail "$name: the script sent a doppler argv the contract does not allow"; return
  fi
  pass "$name"
}

echo "anthropic-key-distinctness.sh"

# run_case self-test: a deliberately wrong expected rc MUST count as a FAIL, or every
# row below that asserts only an exit code asserts nothing. Counters are unwound after.
new_fixture ci prd
setval ci "$CI_VAL"; setval prd "$PRD_VAL"
_p=$PASS; _f=$FAIL
run_case "self-test: wrong expected rc" 1 >/dev/null
if [[ "$FAIL" != $((_f + 1)) || "$PASS" != "$_p" ]]; then
  printf '[FATAL] run_case does not fail on an rc mismatch\n' >&2; exit 1
fi
PASS=$_p; FAIL=$_f

# Must-PASS: every config distinct, plus a prd_* branch with no key at all.
new_fixture dev ci prd prd_terraform prd_x cli
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; setval prd_terraform "$PRD_VAL"; setval dev "$CI_VAL"
run_case "distinct across every prd* config (prd_x ABSENT is allowed; dev/cli ignored)" 0 "DISTINCT"
if grep -qxE 'prd_x ABSENT' "$ROOT/out"; then pass "an ABSENT prd* config is reported, not skipped"; else fail "prd_x ABSENT line missing"; fi
if grep -qE '^dev ' "$ROOT/out"; then fail "a non-prd, non-ci config was compared"; else pass "non-prd configs are not enumerated"; fi
ci_fp="$(printf '%s' "$CI_VAL" | sha256sum | cut -c1-12)"
if grep -qxF "ci $ci_fp" "$ROOT/out"; then pass "ci line carries the 12-char fingerprint of the value"; else fail "ci fingerprint line wrong"; fi

# Row 1: ci equals prd.
new_fixture ci prd
setval ci "$PRD_VAL"; setval prd "$PRD_VAL"
run_case "row1: ci equal to prd -> exit 1" 1

# Row 2: no prd* config enumerated at all (the anti-vacuity floor).
new_fixture ci dev
setval ci "$CI_VAL"
run_case "row2: zero prd* configs enumerated -> exit 2" 2

# Row 2b: prd* configs exist but none holds the key (nothing was compared).
new_fixture ci prd prd_terraform
setval ci "$CI_VAL"
run_case "row2b: no prd* config holds a key -> exit 2" 2

# Row 3: prd distinct, a LATER member equal to ci (the loop must not stop at the first).
new_fixture ci prd prd_scheduled
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; setval prd_scheduled "$CI_VAL"
run_case "row3: second prd* member equal to ci -> exit 1" 1

# Row 4: a read error on one prd* config.
new_fixture ci prd prd_git_data
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; : > "$FIX/val.prd_git_data.error"
run_case "row4: doppler read error on one prd* config -> exit 2" 2 "prd_git_data ERROR"

# Row 5: ci has no key.
new_fixture ci prd
setval prd "$PRD_VAL"
run_case "row5: ci ABSENT -> exit 1" 1 "ci ABSENT"

# Row 6: a prd* config the script was never told about (derived, not hard-coded).
new_fixture ci prd prd_brand_new
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; setval prd_brand_new "$CI_VAL"
run_case "row6: newly added prd_* branch equal to ci -> exit 1" 1

# Enumeration failure is not a pass.
new_fixture ci prd
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; : > "$FIX/configs.fail"
run_case "doppler configs failure -> exit 2" 2

# Name boundary: `prdx` and `cix` are outside ^prd($|_) / ^ci($|_).
new_fixture ci prd prdx cix
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; setval prdx "$CI_VAL"; setval cix "$PRD_VAL"
run_case "prdx / cix are outside the ^prd(\$|_) / ^ci(\$|_) scope" 0 "DISTINCT"

# A ci_* branch is in scope: it equal to a prd key is a failure; ABSENT is allowed.
new_fixture ci ci_eval ci_empty prd
setval ci "$CI_VAL"; setval ci_eval "$PRD_VAL"; setval prd "$PRD_VAL"
run_case "ci_* branch equal to prd -> exit 1" 1 "ci_empty ABSENT"

# A failed read of the root ci config is "could not measure", not "ci holds no key".
new_fixture ci prd
setval prd "$PRD_VAL"; : > "$FIX/val.ci.error"
run_case "ci read error -> exit 2" 2 "ci ERROR"

# A malformed config list must not truncate the population and then pass.
new_fixture ci prd
printf '[{"name":"ci"},{"name":"prd"},"not-an-object",{"name":"prd_late"}]' > "$FIX/configs.json"
setval ci "$CI_VAL"; setval prd "$PRD_VAL"; setval prd_late "$CI_VAL"
run_case "malformed config list -> exit 2, never DISTINCT" 2

# Refuses xtrace before touching anything: rc 78 AND no doppler call made.
new_fixture ci prd
setval ci "$CI_VAL"; setval prd "$PRD_VAL"
rc=0; PATH="$BIN:$PATH" bash -x "$SCRIPT" > "$ROOT/out" 2> "$ROOT/err" || rc=$?
if [[ "$rc" == 78 && ! -s "$FIX/calls" ]]; then pass "refuses to run under bash -x (rc 78, no doppler call)"; else fail "xtrace refusal: rc=$rc want 78, calls=$(wc -l < "$FIX/calls" 2>/dev/null || echo 0)"; fi

TOTAL=$((PASS + FAIL))
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
# Anti-vacuity floor: 17 assertions today. Report outside the helpers.
if (( TOTAL < 17 )); then printf '[FATAL] only %d assertions ran (floor 17)\n' "$TOTAL" >&2; exit 1; fi
(( FAIL == 0 ))
