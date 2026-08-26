#!/usr/bin/env bash
#
# A fixture suite's writes must not be redirectable by a failed `cd`.
#
# THE INCIDENT (2026-08-20). `lease-protects-active.test.sh` ran under
# `set -uo pipefail` — no `-e` — and built its fixtures with errors suppressed.
# A sibling suite swept the fixture out from under it mid-run, the subshell's
# bare `cd` failed, execution continued in the INHERITED cwd, and the following
# `git commit` calls landed in the real repository: four synthetic commits
# (`victim change`, `victim2 change`, `v9 change`, `v12 change`) on a live
# `main` and a live feature branch, plus a worktree checked out to main.
#
# #7673 fixed that file by routing its four dangerous sites through a `cdx`
# helper that aborts on a failed `cd` AND verifies the resulting git toplevel is
# inside the fixture root. What it did not do is make the fix STICK: nothing
# stops the next edit — in that file or any other — from writing the same shape
# again. A repair with no enforcement is a declaration site, not a guard.
#
# THE SHAPE THIS FORBIDS
#
#     (                      # no `set -e` in scope
#       cd "$FIXTURE"        # failure does not abort…
#       git commit -m x      # …so this runs wherever the shell happens to be
#     )
#
# Three conditions must hold together, and the check requires all three so it
# stays quiet on the many harmless `cd`s in this repo:
#
#   1. no `set -e` in scope (file-level OR inside the enclosing subshell) —
#      with it, a failed `cd` aborts and nothing downstream runs;
#   2. the `cd` is not self-guarding — no `&&` chain, no `|| exit/return`, and
#      not the `cdx` helper;
#   3. a git command that WRITES follows within the same block, spelled without
#      `-C` (with `-C <fixture>` the target is explicit and a lost cwd is inert).
#
# THE FIX IS ALWAYS ONE OF: `&&`-chain it, `|| exit` it, use a `cdx`-style
# containment helper, or make the mutation absolute with `git -C "$fixture"`.
# Prefer the last — but only WITH its precondition, which an earlier version of
# this paragraph omitted: `git -C "$fixture"` cannot be redirected by a lost cwd
# only while `$fixture` is guaranteed non-empty and absolute. `git -C ""` does
# NOT error; it silently operates on the current directory, so an unasserted
# operand converts this recommendation back into the defect it replaces. That is
# a real class, not a hypothetical — it is #7652 instance 1, and it is covered by
# `fixture-dir-operand-assert.test.sh`, never by the rule below.
#
# Run: bash plugins/soleur/test/fixture-cd-containment.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== fixture cd-containment: a failed cd must not redirect a git write ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The scanner is the SHARED module, not a copy. Its sibling guard
# (`fixture-dir-operand-assert.test.sh`) forbids a different shape — an EMPTY `git -C` operand,
# which involves no `cd` at all and which this rule is structurally unable to see — over the same
# corpus, with the same heredoc-skipping and comment-skipping and `set -e`-scope machinery. Two
# copies of that machinery plus a comment asking a future reader to keep them in step is not an
# invariant; one module is. #7652
SCANNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixture-scan.py"
[[ -f "$SCANNER" ]] || { echo "FATAL: missing shared scanner $SCANNER" >&2; exit 2; }

echo "A1: no tracked *.test.sh redirects a git write through an unguarded cd"
SCAN_OUT="$(python3 "$SCANNER" --rule cd --repo "$REPO_ROOT" 2>&1)"
SITES="$(sed -n 's/^SITES=//p' <<<"$SCAN_OUT")"
if [[ "$SITES" == "0" ]]; then
  pass "no unguarded cd-then-write sites"
else
  fail "$SITES unguarded cd-then-write site(s) found"
  sed '/^SITES=/d' <<<"$SCAN_OUT" | sed 's/^/    /'
fi
echo ""

# --- Anti-vacuity ----------------------------------------------------------
# A scanner reporting zero is indistinguishable from a scanner that matches
# nothing. Both the positive and the three negative shapes are exercised on
# synthetic fixtures, so a regex that silently stops working is caught here
# rather than by the next incident.
echo "A2: the scanner detects the incident shape"
cat > "$TMP/bad.test.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
(
  cd "$FIXTURE"
  git -c user.email=t@t commit --allow-empty -m "victim change"
)
EOF
BAD="$(python3 "$SCANNER" --rule cd "$TMP/bad.test.sh" 2>&1)"
[[ "$(sed -n 's/^SITES=//p' <<<"$BAD")" == "1" ]] \
  && pass "the exact 2026-08-20 shape is flagged" \
  || { fail "the incident shape is NOT flagged — the scanner is vacuous"; echo "$BAD" | sed 's/^/    /'; }
echo ""

echo "A3: the scanner stays quiet on each guarded spelling"
# && chain — a failed cd short-circuits the write.
cat > "$TMP/ok1.test.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
( cd "$FIXTURE" && git commit --allow-empty -m seed )
EOF
# set -e in the enclosing subshell — a failed cd aborts it.
cat > "$TMP/ok2.test.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
(
  set -e
  cd "$FIXTURE"
  git commit --allow-empty -m seed
)
EOF
# git -C names its own repository, so a lost cwd cannot redirect it — PROVIDED the
# operand is non-empty and absolute, which is the sibling guard's property, not this
# one's.
cat > "$TMP/ok3.test.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
(
  cd "$FIXTURE"
  git -C "$FIXTURE" commit --allow-empty -m seed
)
EOF
for f in ok1 ok2 ok3; do
  n="$(python3 "$SCANNER" --rule cd "$TMP/$f.test.sh" 2>&1 | sed -n 's/^SITES=//p')"
  [[ "$n" == "0" ]] && pass "$f: guarded spelling is not flagged" \
    || fail "$f: guarded spelling was flagged ($n) — the check over-matches"
done
echo ""

echo "A4: a read-only command after an unguarded cd is not flagged"
cat > "$TMP/ok4.test.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
(
  cd "$FIXTURE"
  git status --porcelain
  git rev-parse HEAD
)
EOF
n="$(python3 "$SCANNER" --rule cd "$TMP/ok4.test.sh" 2>&1 | sed -n 's/^SITES=//p')"
[[ "$n" == "0" ]] && pass "reads are not writes (the check is scoped to mutations)" \
  || fail "a read-only block was flagged ($n)"
echo ""

echo "A5: a fixture embedded in a heredoc is data, not code"
# The exact shape A2 relies on, but written INSIDE a heredoc — which is how
# every fixture in this repo is authored. Flagging it made this very file red
# in CI while passing locally (the file was still untracked, so `git ls-files`
# did not hand it to the scanner).
cat > "$TMP/heredoc.test.sh" <<'OUTER'
#!/usr/bin/env bash
set -uo pipefail
cat > "$TMP/inner.sh" <<'INNER'
(
  cd "$FIXTURE"
  git commit --allow-empty -m "victim change"
)
INNER
OUTER
n="$(python3 "$SCANNER" --rule cd "$TMP/heredoc.test.sh" 2>&1 | sed -n 's/^SITES=//p')"
[[ "$n" == "0" ]] && pass "heredoc-embedded fixtures are not flagged" \
  || fail "a heredoc-embedded fixture was flagged ($n) — every fixture suite becomes a false positive"
# …and the SAME bytes, as a real script rather than heredoc data, must still flag.
n2="$(python3 "$SCANNER" --rule cd "$TMP/bad.test.sh" 2>&1 | sed -n 's/^SITES=//p')"
[[ "$n2" == "1" ]] && pass "the same shape as real code is still flagged (skip is scoped, not blanket)" \
  || fail "heredoc skipping disabled real detection ($n2)"
echo ""

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
# Floor: 8 assertions. A refactor that drops arms must not read as a pass.
if (( PASS + FAIL < 8 )); then
  echo "ANTI-VACUITY FLOOR TRIPPED: only $((PASS + FAIL)) assertions ran, expected 8." >&2
  exit 1
fi
if (( FAIL > 0 )); then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTS PASSED"
