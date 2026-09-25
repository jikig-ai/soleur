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
MIN_ASSERTIONS="${CAPTURE_LINT_MIN_ASSERTIONS:-74}"

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
  if [[ ! -s "$path" ]]; then
    fail "$label" "fixture $path exists and is non-empty" "missing/empty fixture file"
    return
  fi
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
  if [[ ! -s "$path" ]]; then
    fail "$label" "fixture $path exists and is non-empty" "missing/empty fixture file"
    return
  fi
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

# --- S3 MUST FIRE: the dead status read from #8784 ----------------------------

f="$(write_fix s3-plain-call <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
some_command "$arg"
rc=$?
echo "$rc"
EOF
)"
assert_fires "$f" 4 S3 "S3a: plain call then rc=\$? -- the read is dead under set -e"

f="$(write_fix s3-capture-call <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$(cat f)
rc=$?
echo "$rc"
EOF
)"
assert_fires "$f" 4 S3 "S3b: x=\$(cmd) then rc=\$? -- same dead read"

f="$(write_fix s3-same-line <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd_run; rc=$?
echo "$rc"
EOF
)"
assert_fires "$f" 3 S3 "S3c: cmd; rc=\$? on one line"

f="$(write_fix s3-local-mid-fn <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
f() {
  run_step
  local rc=$?
  echo "$rc"
}
EOF
)"
assert_fires "$f" 5 S3 "S3d: local rc=\$? MID-function reads the previous command, not the caller"

f="$(write_fix s3-pipestatus <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
a_cmd | b_cmd
rc=${PIPESTATUS[0]}
echo "$rc"
EOF
)"
assert_fires "$f" 4 S3 "S3e: rc=\${PIPESTATUS[0]} is the same read"

f="$(write_fix s3-clear-after <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
risky_call
set +e
rc=$?
EOF
)"
assert_fires "$f" 5 S3 "S3f: set +e AFTER the command is the mis-fix -- the command already ran armed"

f="$(write_fix s3-declare <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
declare -i rc=$?
echo "$rc"
EOF
)"
assert_fires "$f" 4 S3 "S3g: declare -i rc=\$? -- attributed form is the same read"

# --- S3 MUST NOT FIRE ----------------------------------------------------------

f="$(write_fix s3-or-protected <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
maybe_fail || rc=$?
echo "$rc"
EOF
)"
assert_silent "$f" "S3: cmd || rc=\$? -- the canonical protection idiom"

f="$(write_fix s3-and-operand <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
first_ok && rc=$?
echo "$rc"
EOF
)"
assert_silent "$f" "S3: cmd && rc=\$? short-circuits the read -- documented exclusion"

f="$(write_fix s3-fn-head <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
handler() {
  local rc=$?
  echo "$rc"
}
EOF
)"
assert_silent "$f" "S3: local rc=\$? at function head reads the CALLER's status"

f="$(write_fix s3-inside-subst <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
result=$(
  inner_cmd
  rc=$?
  echo "$rc"
)
EOF
)"
assert_silent "$f" "S3: read inside an unclosed \$( ) group -- the carry-status-out idiom"

f="$(write_fix s3-set-plus-e <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
set +e
cmd_a
rc=$?
EOF
)"
assert_silent "$f" "S3: read inside a set +e region -- genuinely disarmed"

f="$(write_fix s3-comment-not-e <<'EOF'
#!/usr/bin/env bash
set -uo pipefail  # deliberately NOT -e
cmd_run
rc=$?
EOF
)"
assert_silent "$f" "S3: 'set -uo pipefail # NOT -e' must not phantom-arm errexit"

f="$(write_fix s3-no-errexit <<'EOF'
#!/usr/bin/env bash
cmd_x
rc=$?
EOF
)"
assert_silent "$f" "S3: no set -e anywhere -- the premise does not hold"

f="$(write_fix s3-if-body <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! check_thing; then
  rc=$?
  echo "$rc"
fi
EOF
)"
assert_silent "$f" "S3: read inside an if ! body -- the condition consumed the status"

# --- S3 MIXED: one unguarded read among protected idioms ------------------------

f="$(write_fix s3-mixed <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
a_cmd || rc=$?
if ! b_cmd; then
  rc=$?
fi
handler() {
  local rc=$?
}
real_cmd
rc=$?
EOF
)"
assert_fires "$f" 11 S3 "S3 MIXED: names only the unguarded read (line 11)"

run_lint "$f"
s3_n="$(grep -c ':[0-9]*: \[' <<<"$LINT_OUT" || true)"
if [[ "$s3_n" == "1" ]]; then
  pass "S3 MIXED: exactly ONE finding -- protected idioms are not swept in"
else
  fail "S3 MIXED: exactly one finding" "1 finding line" "got $s3_n: $(tr '\n' ' ' <<<"$LINT_OUT")"
fi

# --- S4 MUST FIRE: the status-leaking test tail --------------------------------

f="$(write_fix s4-arith-tail <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
run_scan() {
  total=$((total + 1))
  (( skipped > 0 )) && echo "skipped=$skipped"
}
EOF
)"
assert_fires "$f" 5 S4 "S4a: (( n > 0 )) && echo as a function tail leaks the test's status"

f="$(write_fix s4-bracket-tail <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
finish() {
  [[ -f f ]] && grep -q x f
}
EOF
)"
assert_fires "$f" 4 S4 "S4b: [[ cond ]] && action as a function tail"

f="$(write_fix s4-one-line-fn <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
run() { (( c > 0 )) && echo x; }
EOF
)"
assert_fires "$f" 3 S4 "S4c: a one-line function body still leaks the tail's status"

# --- S4 MUST NOT FIRE ----------------------------------------------------------

f="$(write_fix s4-bare-predicate <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
probe() {
  [[ -f f ]]
}
EOF
)"
assert_silent "$f" "S4: bare [[ cond ]] tail -- the predicate idiom, not this class"

f="$(write_fix s4-or-arm <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
report() {
  (( n > 0 )) && echo "n=$n" || echo "none"
}
EOF
)"
assert_silent "$f" "S4: test && act || fallback -- the || arm decides the status"

f="$(write_fix s4-predicate-name <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
is_ready() {
  [[ -c /dev/x ]] && notify
}
EOF
)"
assert_silent "$f" "S4: predicate-named function (is_*) -- the status IS the contract"

f="$(write_fix s4-return-action <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
maybe() {
  [[ -f f ]] && return 1
}
EOF
)"
assert_silent "$f" "S4: [[ c ]] && return 1 -- explicit status flow, not a leak"

f="$(write_fix s4-set-plus-e <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
set +e
run() {
  (( c > 0 )) && echo x
}
EOF
)"
assert_silent "$f" "S4: tail inside a set +e file -- nothing aborts anyway"

# --- S3/S4 coverage expansion (review findings) ---------------------------------
f="$(write_fix s3-sameline-clear-after <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
some_command; set +e; rc=$?
EOF
)"
assert_fires "$f" 3 S3 "S3: cmd; set +e; rc=\$? same line -- the clear runs AFTER the armed command"

f="$(write_fix s3-canonical-fix <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if out="$(some_command)"; then
  rc=0
else
  rc=$?
fi
echo "$rc $out"
EOF
)"
assert_silent "$f" "S3: if cmd; then rc=0; else rc=\$?; fi -- the gate's own recommended fix"

f="$(write_fix s3-trap-string <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
work
trap 'rc=$?; if [ "$rc" -ne 0 ]; then cleanup; fi' EXIT
EOF
)"
assert_silent "$f" "S3: rc=\$? inside a trap string reads the fire-time status, not this line's"

f="$(write_fix s3-or-brace-block <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$(some_command 2>&1) || {
  rc=$?
  echo "failed rc=$rc" >&2
}
EOF
)"
assert_silent "$f" "S3: cmd || { rc=\$? ... } failure block -- the protection idiom itself"

f="$(write_fix s3-pipeline-2gt1 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
grep -E 'pat' "$1" 2>&1
rc=$?
EOF
)"
assert_fires "$f" 4 S3 "S3: 2>&1 before the read does not poison the segment split"

f="$(write_fix s3-indexed-read <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
rcs[0]=$?
EOF
)"
assert_fires "$f" 4 S3 "S3: rcs[0]=\$? indexed assignment is the same read"

f="$(write_fix s3-quoted-read <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
rc="$?"
EOF
)"
assert_fires "$f" 4 S3 "S3: rc=\"\$?\" quoted form is the same read"

f="$(write_fix s4-single-bracket-tail <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
report() {
  local total=0
  [ "$total" -gt 0 ] && echo "total=$total"
}
EOF
)"
assert_fires "$f" 5 S4 "S4d: [ expr ] && act tail -- single-bracket form leaks too"

f="$(write_fix s4-test-tail <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
report() {
  local total=0
  test "$total" -gt 0 && echo "total=$total"
}
EOF
)"
assert_fires "$f" 5 S4 "S4e: test expr && act tail -- the test-builtin form leaks too"

f="$(write_fix s4-function-kw <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
function report {
  local total=0
  (( total > 0 )) && echo "total=$total"
}
EOF
)"
assert_fires "$f" 5 S4 "S4f: 'function name {' opener is still a function tail"

# --- review-round coverage: resolved-detector shapes -------------------------
f="$(write_fix s3-subst-semi-rejoin <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
x=$(a; b); rc=$?
EOF
)"
assert_fires "$f" 3 S3 "S3: x=\$(a; b); rc=\$? -- the \$( rejoin keeps the capture as antecedent"

f="$(write_fix s3-sameline-disarm <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == test ]]; then
  set +e; cmd; rc=$?; set -e
fi
EOF
)"
assert_silent "$f" "S3: set +e; cmd; rc=\$? same line -- the fold judges the command disarmed"

f="$(write_fix s3-pipestatus-nopipe <<'EOF'
#!/usr/bin/env bash
set -eu
grep x f | wc -l
rc=${PIPESTATUS[0]}
EOF
)"
assert_silent "$f" "S3: PIPESTATUS read without pipefail -- the read is live, not dead"

f="$(write_fix s3-pipestatus-pipe <<'EOF'
#!/usr/bin/env bash
set -eu
grep x f | wc -l
rc=${PIPESTATUS[0]}
set -o pipefail
grep y f | wc -l
rc2=${PIPESTATUS[0]}
EOF
)"
assert_fires "$f" 7 S3 "S3: PIPESTATUS read WITH pipefail armed -- dead again"

f="$(write_fix s3-arg-read <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
echo rc=$?
EOF
)"
assert_silent "$f" "S3: echo rc=\$? -- the bare-in-arguments class is scoped out"

f="$(write_fix s3-arg-then-read <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
echo rc=$?; rc2=$?
EOF
)"
assert_fires "$f" 4 S3 "S3: every read is judged -- the arg-position first match does not mask the second"

f="$(write_fix s3-eval-antecedent <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
eval "$script"; rc=$?
EOF
)"
assert_fires "$f" 3 S3 "S3: eval <arg>; rc=\$? -- eval is a command, not a context exemption"

f="$(write_fix s3-compound-if <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f f ]]; then worker; fi
rc=$?
EOF
)"
assert_fires "$f" 4 S3 "S3: if c; then cmd; fi + rc=\$? -- the compound's armed arm aborts"

f="$(write_fix s3-set-sandwich-decl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worker
cmd; set +e; local rc=$?
EOF
)"
assert_fires "$f" 4 S3 "S3: cmd; set +e; local rc=\$? -- resolves cmd, not the set statement"

f="$(write_fix s1-semi-tail <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
x=$(grep pattern f); echo done
EOF
)"
assert_fires "$f" 3 S1 "S1: x=\$(grep p f); echo -- the ;-tail capture is still unguarded"

f="$(write_fix s4-inner-group <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
report() {
  cmd || {
    echo fail
  }
  local total=0
  (( total > 0 )) && echo "total=$total"
}
EOF
)"
assert_fires "$f" 8 S4 "S4: inner { group close does not mis-pop the function"

f="$(write_fix s3-set-onounset <<'EOF'
#!/usr/bin/env bash
set -onounset
x=$(grep pattern f)
rc=$?
EOF
)"
assert_silent "$f" "S3: set -onounset is nounset, not errexit -- no phantom arm"

f="$(write_fix s3-dont-quote <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "don't"; rc=$?
EOF
)"
assert_fires "$f" 3 S3 "S3: ' inside a \"-quoted word cannot spoof the quote parity check"

# --- baseline behaviour ------------------------------------------------------
# --write-baseline refuses explicit paths (a subset scan would truncate the
# grandfathered set), so the write path is exercised through a mini git root.
PROJ="$TMP/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q 2>/dev/null
cat > "$PROJ/one.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hits=$(grep 'pattern' f)
EOF
git -C "$PROJ" add -A 2>/dev/null
BASE="$TMP/base.txt"
python3 "$LINTER" --root "$PROJ" --baseline "$BASE" --write-baseline >/dev/null 2>&1 \
  || { fail "baseline: --write-baseline succeeded"; }
if [[ -s "$BASE" ]]; then
  pass "baseline: --write-baseline produced a non-empty file"
else
  fail "baseline: --write-baseline produced a non-empty file" "non-empty $BASE" "empty/missing"
fi

LINT_RC=0
python3 "$LINTER" --root "$PROJ" "$PROJ/one.sh" --baseline "$BASE" --write-baseline >/dev/null 2>&1 || LINT_RC=$?
if [[ $LINT_RC -eq 2 ]]; then
  pass "baseline: --write-baseline refuses explicit paths (subset scan would truncate)"
else
  fail "baseline: --write-baseline refuses explicit paths" "exit 2" "exit $LINT_RC"
fi

f="$PROJ/one.sh"

LINT_RC=0
python3 "$LINTER" --root "$PROJ" "$f" --baseline "$BASE" >/dev/null 2>&1 || LINT_RC=$?
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
