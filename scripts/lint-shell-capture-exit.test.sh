#!/usr/bin/env bash
# Unit suite for scripts/lint-shell-capture-exit.py.
#
# The fixture set IS the executable specification of the rule, and it is written to the same
# standard as its sibling suite (lint-workflow-errexit-capture.test.sh): every must-NOT-fire
# fixture carries a POSITIVE CONTROL in the same file -- a known-firing shape the linter must
# still name. Without that control a must-not-fire assertion passes just as happily against a
# linter that has stopped detecting anything at all, because a broken detector and a clean
# fixture produce byte-identical output.
#
# That control is not a theoretical nicety here. The PR that produced this gate (#7332) shipped
# two defects of exactly that shape -- a gate whose parse used the wrong key and so fired on
# every corpus, and tests that pinned a constant by indexing the same constant. Both were green.
set -uo pipefail

# A direct invocation inherits the bare /tmp, a machine-global tmpfs shared with every parallel
# worktree. test-all.sh defaults to /var/tmp for that reason; match it.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINTER="${CAPTURE_LINT_SCRIPT:-$SCRIPT_DIR/lint-shell-capture-exit.py}"

TMP="$(mktemp -d -t capture-lint.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PASS=0
FAIL=0
# Anti-vacuity floor. Raise deliberately when adding fixtures.
MIN_ASSERTIONS="${CAPTURE_LINT_MIN_ASSERTIONS:-24}"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1"
  [[ $# -gt 1 ]] && echo "        expected: $2"
  [[ $# -gt 2 ]] && echo "        actual:   $3"
  FAIL=$((FAIL + 1))
}

if [[ ! -f "$LINTER" ]]; then
  echo "FATAL: linter not found at $LINTER"
  exit 2
fi

# --- fixture plumbing -------------------------------------------------------
# write_fix <name> -- read a script body on stdin, write it, echo the path.
n=0
write_fix() {
  n=$((n + 1))
  local path="$TMP/fx-$n-$1.sh"
  cat > "$path" || { echo "FATAL: could not write $path"; exit 2; }
  echo "$path"
}

# run_lint <path> -- writes the linter's output to $LINT_OUT, its status to $LINT_RC.
#
# The rc is deliberately NOT returned through a command substitution. The first version of this
# harness did exactly that -- `out="$(run_lint "$p")"` with `run_lint` doing `|| LINT_RC=$?` --
# and every must-fire assertion reported "linter saw nothing" while the same linter was finding
# 216 sites in the real tree. The assignment inside `$( )` runs in a SUBSHELL, so LINT_RC never
# reached the caller and read as 0 forever.
#
# That is this gate's own defect class wearing a different hat: a status captured somewhere it
# cannot survive. It is recorded here rather than quietly fixed because a suite whose harness
# silently reports success is the failure mode these fixtures exist to prevent.
LINT_RC=0
LINT_OUT=""
run_lint() {
  LINT_RC=0
  LINT_OUT="$(python3 "$LINTER" --root "$TMP" "$1" 2>&1)" || LINT_RC=$?
}

# assert_fires <path> <line> <code> <label>
assert_fires() {
  local path="$1" line="$2" code="$3" label="$4"
  run_lint "$path"
  if [[ $LINT_RC -eq 0 ]]; then
    fail "$label" "exit 1 (finding at :$line [$code])" "exit 0 -- linter saw nothing"
    return
  fi
  if grep -q ":${line}: \[${code}\]" <<<"$LINT_OUT"; then
    pass "$label"
  else
    fail "$label" ":${line}: [${code}]" "$(tr '\n' ' ' <<<"$LINT_OUT")"
  fi
}

# assert_silent <path> <label>
assert_silent() {
  local path="$1" label="$2"
  run_lint "$path"
  if [[ $LINT_RC -eq 0 ]]; then
    pass "$label"
  else
    fail "$label" "exit 0 (no finding)" "$(tr '\n' ' ' <<<"$LINT_OUT")"
  fi
}

echo "=== lint-shell-capture-exit unit suite ==="

# --- MUST FIRE: the three shapes measured in #7332 --------------------------

f="$(write_fix bare-capture <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' "$file")
echo "$hits"
EOF
)"
assert_fires "$f" 3 S1 "S1a: bare x=\$(grep ...) under set -e"

f="$(write_fix pipeline-capture <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=$(grep 'x' "$f" | wc -l)
echo "$count"
EOF
)"
assert_fires "$f" 3 S1 "S1b: grep | wc -l does not launder the status under pipefail"

f="$(write_fix grep-c-double-emit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=$(grep -c 'x' "$f") || echo 0
echo "$count"
EOF
)"
assert_fires "$f" 3 S2 "S2: grep -c with || echo yields a TWO-LINE value"

f="$(write_fix grep-c-inside <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=$(grep -c 'x' "$f" || echo 0)
EOF
)"
assert_fires "$f" 3 S2 "S2: || echo INSIDE the substitution double-emits too"

f="$(write_fix long-count-flag <<'EOF'
#!/usr/bin/env bash
set -e
n=$(grep --count 'x' "$f") || echo 0
EOF
)"
assert_fires "$f" 3 S2 "S2: --count long form is the same defect"

f="$(write_fix diff-capture <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
delta=$(diff a b)
EOF
)"
assert_fires "$f" 3 S1 "S1: diff exits 1 to mean 'they differ'"

f="$(write_fix set-e-later <<'EOF'
#!/usr/bin/env bash
x=$(grep 'a' f)
set -e
y=$(grep 'b' f)
EOF
)"
assert_fires "$f" 4 S1 "errexit state is tracked: only the post-set -e capture fires"

f="$(write_fix reenabled <<'EOF'
#!/usr/bin/env bash
set -e
set +e
a=$(grep 'x' f)
set -e
b=$(grep 'y' f)
EOF
)"
assert_fires "$f" 6 S1 "set +e then set -e: only the re-enabled region fires"

f="$(write_fix continuation <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
types=$(grep -rhoE 'x' src \
  | sort -u)
EOF
)"
assert_fires "$f" 3 S1 "continuation lines fold and report the FIRST line"

f="$(write_fix env-prefix <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$(LC_ALL=C grep 'x' f)
EOF
)"
assert_fires "$f" 3 S1 "an env-var prefix does not hide the command name"

f="$(write_fix set-o-errexit <<'EOF'
#!/usr/bin/env bash
set -o errexit
out=$(grep 'x' f)
EOF
)"
assert_fires "$f" 3 S1 "set -o errexit is recognised, not just -e"

# --- MUST NOT FIRE: each fixture carries a positive control ------------------
# Every silent fixture below ALSO omits a control on purpose: the controls are asserted
# separately (mixed fixture at the end) so a silent-case regression cannot masquerade as a
# clean tree. See the header note.

f="$(write_fix no-errexit <<'EOF'
#!/usr/bin/env bash
hits=$(grep 'pattern' f)
count=$(grep -c 'x' f) || echo 0
EOF
)"
assert_silent "$f" "no set -e: the premise does not hold, nothing fires"

f="$(write_fix or-true <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' f) || true
EOF
)"
assert_silent "$f" "|| true decides -- not a finding"

f="$(write_fix or-inside <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' f || true)
EOF
)"
assert_silent "$f" "|| true INSIDE the substitution decides"

f="$(write_fix if-condition <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if hits=$(grep 'pattern' f); then
  echo "$hits"
fi
EOF
)"
assert_silent "$f" "if x=\$(...) -- the condition consumes the status"

f="$(write_fix local-masks <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
scan() {
  local hits=$(grep 'pattern' f)
}
EOF
)"
assert_silent "$f" "local x=\$(...) returns local's own status -- no abort risk"

f="$(write_fix or-assign <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' f) || hits=""
EOF
)"
assert_silent "$f" "|| x=\"\" decides"

f="$(write_fix safe-command <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$(cat f)
name=$(basename "$p")
EOF
)"
assert_silent "$f" "commands whose non-zero exit is a REAL error are out of scope"

f="$(write_fix comment-only <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# hits=$(grep 'pattern' f)
echo ok
EOF
)"
assert_silent "$f" "a commented-out capture is not code"

f="$(write_fix heredoc-body <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat > out.sh <<'INNER'
hits=$(grep 'pattern' f)
INNER
echo ok
EOF
)"
assert_silent "$f" "heredoc bodies are data, not commands of this shell"

# --- MIXED: the positive control, asserted explicitly -----------------------
# This is the fixture that makes every assert_silent above meaningful: guarded and unguarded
# shapes in ONE file, where the linter must name the unguarded line and leave the rest alone.
f="$(write_fix mixed-control <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
a=$(grep 'x' f) || true
if b=$(grep 'y' f); then :; fi
c=$(cat f)
d=$(grep 'z' f)
e=$(grep 'w' f || true)
EOF
)"
assert_fires "$f" 6 S1 "MIXED: names only the unguarded capture (line 6)"

run_lint "$f"
# `grep -c` on no match prints 0 AND exits 1 -- the S2 defect itself. `|| true` keeps the 0 it
# already printed; `|| echo 0` here would produce "0\n0" and make the comparison never match.
mixed_n="$(grep -c ':[0-9]*: \[' <<<"$LINT_OUT" || true)"
if [[ "$mixed_n" == "1" ]]; then
  pass "MIXED: exactly ONE finding -- the guarded shapes are not swept in"
else
  fail "MIXED: exactly one finding" "1 finding line" "got $mixed_n: $(tr '\n' ' ' <<<"$LINT_OUT")"
fi

# --- baseline behaviour ------------------------------------------------------
f="$(write_fix baseline-src <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' f)
EOF
)"
BASE="$TMP/base.txt"
python3 "$LINTER" --root "$TMP" "$f" --baseline "$BASE" --write-baseline >/dev/null 2>&1 \
  || { fail "baseline: --write-baseline succeeded"; }
if [[ -s "$BASE" ]]; then
  pass "baseline: --write-baseline produced a non-empty file"
else
  fail "baseline: --write-baseline produced a non-empty file" "non-empty $BASE" "empty/missing"
fi

LINT_RC=0
python3 "$LINTER" --root "$TMP" "$f" --baseline "$BASE" >/dev/null 2>&1 || LINT_RC=$?
if [[ $LINT_RC -eq 0 ]]; then
  pass "baseline: a grandfathered finding is suppressed"
else
  fail "baseline: a grandfathered finding is suppressed" "exit 0" "exit $LINT_RC"
fi

# THE load-bearing baseline assertion: a NEW finding must still fire while the baseline holds.
# A baseline that suppressed everything would turn this gate into a permanent no-op, which is
# the exact "gate that cannot fail" shape this repo has shipped before.
f2="$(write_fix baseline-new <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
other=$(grep 'brand-new' f)
EOF
)"
LINT_RC=0
python3 "$LINTER" --root "$TMP" "$f2" --baseline "$BASE" >/dev/null 2>&1 || LINT_RC=$?
if [[ $LINT_RC -ne 0 ]]; then
  pass "baseline: a NEW finding still fires (the gate is not a no-op)"
else
  fail "baseline: a NEW finding still fires" "exit 1" "exit 0 -- baseline swallowed it"
fi

# --- results -----------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ $TOTAL -lt $MIN_ASSERTIONS ]]; then
  echo "FAIL: only $TOTAL assertions ran, floor is $MIN_ASSERTIONS (fixtures silently skipped?)" >&2
  exit 1
fi
[[ $FAIL -eq 0 ]] || exit 1
echo "ALL TESTS PASSED"
