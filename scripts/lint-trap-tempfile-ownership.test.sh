#!/usr/bin/env bash
# lint-trap-tempfile-ownership.test.sh -- both-arm tests for the #6734 lint gate.
#
# FIXTURES ARE SYNTHESIZED AND FROZEN (cq-test-fixtures-synthesized-only), never copies
# of the real subjects. This is load-bearing here specifically: Phase 1 of this PR FIXES
# both real subjects (content-publisher.sh, skill-freshness-aggregate.sh), so a positive
# arm pointed at them would have had no subject left and would have gone vacuously green
# the moment the fix landed.
#
# Fixtures carry a `.sh.fixture` suffix, not `.sh`, so `git ls-files '*.sh'` in the
# linter's own full-scan mode cannot pick them up and flag the deliberate bad ones.
# Explicit-path mode (used below) lints them regardless of suffix.
#
# Each rule is tested in BOTH directions. A positive-only suite cannot distinguish a
# working rule from one that flags everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-trap-tempfile-ownership.py"
FIX="$SCRIPT_DIR/fixtures/trap-tempfile-ownership"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL: $1" >&2; }

[[ -f "$LINT" ]] || { echo "FATAL: $LINT not found" >&2; exit 1; }
[[ -d "$FIX" ]] || { echo "FATAL: $FIX not found" >&2; exit 1; }

# Run the linter over one fixture; echo its exit code. Never let `set -e` abort here.
lint_rc() {
  local rc=0
  python3 "$LINT" "$1" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# Capture stderr so a message can be asserted (proves the RIGHT rule fired, not just
# that something failed).
lint_err() {
  # `2>&1 >/dev/null` is deliberate and order-dependent: fd2 is duped to the CURRENT
  # fd1 (the caller's capture), THEN fd1 is sent to /dev/null -- so this yields stderr
  # ONLY, which is where the linter prints its findings. Verified: a command emitting
  # both streams through this form captures exactly the stderr line.
  # Reversing to `>/dev/null 2>&1` would capture NOTHING and silently make every
  # message assertion below vacuous.
  # shellcheck disable=SC2069
  python3 "$LINT" "$1" 2>&1 >/dev/null || true
}

# --- Positive arm: the gate must FLAG these -------------------------------------------
for case in \
  "bad-subshell-append.sh.fixture|rule (a) subshell-append|rule (a) flags the command-substitution append" \
  "bad-mktemp-no-trap.sh.fixture|rule (c) mktemp with no owning trap|rule (c) flags mktemp with zero traps" \
  "bad-escape-hatch-no-reason.sh.fixture|with no reason|a bare escape hatch is itself an error" \
  "bad-mktemp-inside-double-quotes.sh.fixture|rule (c) mktemp with no owning trap|rule (c) still fires on an allocation inside double quotes" \
  "bad-mktemp-in-brace-body.sh.fixture|rule (c) mktemp with no owning trap|rule (c) fires on mktemp in a { } function body"
do
  IFS='|' read -r file needle label <<< "$case"
  rc=$(lint_rc "$FIX/$file")
  err=$(lint_err "$FIX/$file")
  if [[ "$rc" == "1" ]] && grep -qF "$needle" <<< "$err"; then
    ok "$label"
  else
    no "$label (rc=$rc, stderr did not contain '$needle': ${err:0:200})"
  fi
done

# --- Explicit-path mode must not depend on git history --------------------------------
# REGRESSION (this is what broke CI, and it broke ONLY in CI): rule (c) scopes itself to
# lines added vs `git merge-base HEAD origin/main`. The test-scripts job checked out at
# fetch-depth 1, where origin/main does not exist -- merge-base exited 128, the changed
# set resolved empty, and every positive-arm assertion above went green-on-nothing.
#
# The same scoping had a second, worse consequence: the fixtures are COMMITTED, so they
# read as "added" only until this PR merges. After merge the diff against the base is
# empty and rule (c) stops firing on them permanently. Explicit paths therefore lint the
# WHOLE file and ask git nothing.
#
# Asserted by putting a `git` on PATH that fails every invocation, which is a strictly
# harsher environment than a shallow checkout. If rule (c) still fires, it consulted no
# history and neither shallowness nor merge can make it vacuous.
GITSHIM="$(mktemp -d)"
trap 'rm -rf "$GITSHIM"' EXIT
printf '#!/bin/sh\nexit 128\n' > "$GITSHIM/git"
chmod +x "$GITSHIM/git"

shim_rc=0
shim_err="$(PATH="$GITSHIM:$PATH" python3 "$LINT" "$FIX/bad-mktemp-no-trap.sh.fixture" 2>&1 >/dev/null)" || shim_rc=$?
if [[ "$shim_rc" == "1" ]] && grep -qF "rule (c) mktemp with no owning trap" <<< "$shim_err"; then
  ok "rule (c) fires on an explicit path with git entirely unavailable (shallow-checkout regression)"
else
  no "rule (c) went vacuous without git (rc=$shim_rc): ${shim_err:0:200}"
fi

# The negative arm must stay negative under the same shim -- a rule (c) that fired on
# everything once git was gone would also satisfy the assertion above.
shim_good_rc=0
PATH="$GITSHIM:$PATH" python3 "$LINT" "$FIX/good-mktemp-with-trap.sh.fixture" >/dev/null 2>&1 || shim_good_rc=$?
if [[ "$shim_good_rc" == "0" ]]; then
  ok "a trap-owning file is still clean with git unavailable (shim is not flag-everything)"
else
  no "shim made the gate flag a good file (rc=$shim_good_rc)"
fi

# --- Negative arm: the gate must NOT flag these ---------------------------------------
# These are the shapes a naive rule gets wrong. R7 in the plan: provision-hetzner.sh is
# safe only because its second trap sits inside `( … )`, and vendor-pin-integrity.test.sh
# uses `trap - EXIT` CORRECTLY -- the very shape a trap-replacement rule would condemn.
for case in \
  "good-parent-append.sh.fixture|parent-scope append is not flagged (the fix shape)" \
  "good-mktemp-with-trap.sh.fixture|mktemp with an owning trap is not flagged" \
  "good-subshell-scoped-second-trap.sh.fixture|a second trap scoped inside ( … ) is not flagged (R7)" \
  "good-trap-clear-handoff.sh.fixture|a deliberate 'trap - EXIT' handoff is not flagged (R7)" \
  "good-escape-hatch.sh.fixture|a reason-carrying escape hatch suppresses the finding" \
  "good-local-args-array.sh.fixture|a local args array in a \$()-invoked fn is not flagged (over-broad-rule regression)" \
  "good-local-cleanup-array.sh.fixture|a function-local shadow of a cleanup array is not flagged" \
  "good-mktemp-word-in-string-only.sh.fixture|the WORD mktemp as string data is not flagged (bare-token-anchor regression)" \
  "good-return-trap.sh.fixture|a per-function trap ... RETURN counts as ownership (EXIT-only-anchor regression)"
do
  IFS='|' read -r file label <<< "$case"
  rc=$(lint_rc "$FIX/$file")
  if [[ "$rc" == "0" ]]; then
    ok "$label"
  else
    no "$label (expected rc 0, got $rc: $(lint_err "$FIX/$file" | head -2))"
  fi
done

# --- The gate must be clean on the real tree ------------------------------------------
# Full scan: rule (a) repo-wide, rule (c) new-entrants-only (the class-b accept).
full_rc=0
python3 "$LINT" >/dev/null 2>&1 || full_rc=$?
if [[ "$full_rc" == "0" ]]; then
  ok "full repo scan is clean (rule (a) repo-wide + rule (c) on changed files)"
else
  no "full repo scan is NOT clean (rc=$full_rc): $(python3 "$LINT" 2>&1 >/dev/null | head -5)"
fi

# --- The high-water ratchet -----------------------------------------------------------
hw_rc=0
python3 "$LINT" --check-highwater >/dev/null 2>&1 || hw_rc=$?
if [[ "$hw_rc" == "0" ]]; then
  ok "class-b population is at or below the accepted high-water"
else
  no "class-b high-water exceeded (rc=$hw_rc): $(python3 "$LINT" --check-highwater 2>&1 >/dev/null | head -3)"
fi

# --- Census is a positive control for the ratchet -------------------------------------
# A high-water check whose census always returned 0 would pass forever. Assert the census
# actually counts a population, so the ratchet cannot be silently blind.
c=$(python3 "$LINT" --census 2>/dev/null || echo "")
if [[ "$c" =~ ^[0-9]+$ ]] && (( c > 0 )); then
  ok "census positive control: it reports a non-zero class-b population ($c)"
else
  no "census returned '$c' -- if it cannot count, --check-highwater passes vacuously"
fi

echo ""
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
(( FAIL == 0 )) || exit 1
