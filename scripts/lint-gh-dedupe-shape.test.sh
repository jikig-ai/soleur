#!/usr/bin/env bash
# Unit suite for scripts/lint-gh-dedupe-shape.py (#9659, Guard 1).
#
# The fixture set IS the executable specification of the rule: an unquoted
# `IDENT=$(` capture of `gh (issue|pr) (list|search)` in a workflow is a
# finding unless it is condition-context-bound, `||`-handled on its logical
# line (OUTSIDE the substitution — a `|| true` inside is the silent swallow
# this lint exists to catch), or within 2 lines of a `# dedupe:` marker.
# Quoted `IDENT="$(` sites are the advisory class: measured, never gated.
#
# Every must-NOT-fire case carries a POSITIVE CONTROL in the same fixture —
# a known-firing shape whose line the linter must name while leaving the
# guarded one alone. Without that control, a must-not-fire assertion passes
# against a linter that has stopped working entirely (a broken detector and a
# clean tree produce byte-identical output).
set -uo pipefail

# Keep scratch on the large tmpfs — see lint-workflow-errexit-capture.test.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="${GH_DEDUPE_LINT_SCRIPT:-$SCRIPT_DIR/lint-gh-dedupe-shape.py}"

TMP="$(mktemp -d -t gh-dedupe-lint.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# Canonical copy of the fixture-dir guard from plugins/soleur/test/test-helpers.sh
# (byte-identical per fixture-dir-operand-assert.test.sh). Sourcing the helper
# file is not an option here — it sets -e, and this suite deliberately runs
# `set -uo pipefail` so a fixture lint failure lands in FAIL, not an abort.
# The single top-level call below is what fixture-scan.py --rule relative
# recognises: every fixture write under $TMP chains to it as endvar.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMP"

passes=0
fails=0

pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() {
  echo "  FAIL: $1"
  [[ $# -gt 1 ]] && echo "        expected: $2"
  [[ $# -gt 2 ]] && echo "        actual:   $3"
  fails=$((fails + 1))
}

# Instrument self-test FIRST: a harness that has never been shown to emit a
# FAIL has not returned a pass. The fail() below is expected; it is erased by
# the counters reset right after, and the floor subtracts the proven SELFTEST
# literal rather than trusting the live counter.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, erased below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0; fails=0

if [[ ! -f "$LINTER" ]]; then
  echo "FATAL: linter not found at $LINTER"
  exit 2
fi

# --- fixture plumbing -------------------------------------------------------
# mkfix <name> -- create a fixture root holding .github/workflows/.
mkfix() {
  local name="$1"
  local root="$TMP/fx-$name"
  # In-function re-assert: the relative-rule guard window stops at this
  # function head, so the top-level $TMP guard cannot reach writes below.
  assert_fixture_dir "$root"
  rm -rf "$root" || { echo "FATAL: rm -rf $root failed"; exit 2; }
  mkdir -p "$root/.github/workflows" \
    || { echo "FATAL: mkdir $root failed"; exit 2; }
  printf '%s' "$root"
}

# run_lint <root> -- sets LINT_OUT and LINT_RC. Called as a plain function,
# never `$(run_lint)` — command substitution discards caller-visible rc.
LINT_RC=0
LINT_OUT=""
run_lint() {
  LINT_OUT="$(python3 "$LINTER" --root "$1" --quiet 2>&1)"
  LINT_RC=$?
  printf '%s\n' "$LINT_OUT" > "$TMP/out.txt"
}

# assert_fires <label> <root> <line-number-that-must-be-named>
assert_fires() {
  local label="$1" root="$2" want_line="$3"
  run_lint "$root"
  if [[ "$LINT_RC" != "1" ]]; then
    fail "$label" "rc=1 (a finding)" "rc=$LINT_RC; output: $(tr '\n' ' ' < "$TMP/out.txt")"
    return 0
  fi
  if grep -qE ":${want_line}:" "$TMP/out.txt"; then
    pass "$label"
  else
    fail "$label" "a finding at line ${want_line}" "$(tr '\n' ' ' < "$TMP/out.txt")"
  fi
}

# assert_clean <label> <root>
assert_clean() {
  local label="$1" root="$2"
  run_lint "$root"
  if [[ "$LINT_RC" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "rc=0 (no findings)" "rc=$LINT_RC; $(tr '\n' ' ' < "$TMP/out.txt")"
  fi
}

# assert_not_named <label> <root> <line-that-must-NOT-be-named>
assert_not_named() {
  local label="$1" root="$2" bad_line="$3"
  run_lint "$root"
  if grep -qE ":${bad_line}:" "$TMP/out.txt"; then
    fail "$label" "no finding at line ${bad_line}" "$(tr '\n' ' ' < "$TMP/out.txt")"
  else
    pass "$label"
  fi
}

echo "=== lint-gh-dedupe-shape fixtures ==="

# --- MUST FIRE --------------------------------------------------------------

# F1 -- the canonical defect: a bare `IDENT=$(gh issue list …)` capture in a
# run body. Under set -e a transient gh fault aborts the step mid-alarm.
r="$(mkfix bare)"
# fixture-scan --rule relative chains "$r/..." sites to a call it cannot
# resolve (mkfix). The guard names the USE var: assert once here — every later
# rebinding is still "$TMP/fx-*", and the guard window runs to file start.
assert_fixture_dir "$r"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --json number --jq '.[0].number // empty')
          echo "$EXISTING"
YAML
assert_fires "F1 a bare dedupe capture FIRES" "$r" 9

# F2 -- `|| true` INSIDE the substitution is the silent swallow, not a
# handler: the read can never abort, so the defect reports nothing.
r="$(mkfix swallow)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --state open 2>/dev/null || true)
          good=$(gh issue list --state open)
YAML
assert_fires "F2 control: the bare second site in the same body FIRES" "$r" 10
assert_fires "F2b a || true INSIDE the substitution FIRES (silent swallow)" "$r" 9

# F3 -- `gh pr list` is the same class (the create-dedupe read).
r="$(mkfix prlist)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          existing=$(gh pr list --head "$b" --state open --json url --jq '.[0].url // ""')
YAML
assert_fires "F3 a bare gh-pr-list dedupe capture FIRES" "$r" 9

# F4 -- a `# dedupe:` marker parked >2 lines above its site is decorative,
# not a disposition (Guard 1 mutation row 3: adjacency is load-bearing).
r="$(mkfix markerfar)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          # dedupe: benign — parked four lines away, must NOT classify
          NOW=$(date -u)
          A=1
          B=2
          EXISTING=$(gh issue list --state open)
          echo "$EXISTING $NOW $A $B"
YAML
assert_fires "F4 a marker >2 lines from its site FIRES" "$r" 13

# F5 -- multi-line continuation: the capture starts on the `=$(` line and the
# defect is named there even though the `)` closes three lines later.
r="$(mkfix contbare)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --repo "$GH_REPO" --state open \
            --label ci/fx --json number \
            --jq '.[0].number // empty')
          echo "$EXISTING"
YAML
assert_fires "F5 a bare multi-line dedupe capture FIRES at the capture line" "$r" 9

# F6 -- a defect in the SECOND scanned file after a clean first file (a
# scanner that returns after the first file would read green here).
r="$(mkfix secondfile)"
cat > "$r/.github/workflows/a-clean.yml" <<'YAML'
name: clean
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          X=$(gh issue list --state open) || { echo "::error::dedupe"; X=""; }
YAML
cat > "$r/.github/workflows/z-dirty.yml" <<'YAML'
name: dirty
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          EXISTING=$(gh issue list --state open)
YAML
assert_fires "F6 defect in a later-scanned file FIRES" "$r" 8

# --- MUST NOT FIRE (each with a positive control in the same file) ----------

# G1 -- the normalized fail-open shape: `|| { ::error:: …; VAR=""; }` outside
# the substitution.
r="$(mkfix normshape)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --state open) || { echo "::error::fx: dedupe query failed"; EXISTING=""; }
          bad=$(gh issue list --state open)
YAML
assert_fires "G1 control: the bad line in the same body FIRES" "$r" 10
assert_not_named "G1b the normalized || handler does NOT fire" "$r" 9

# G2 -- `if !`-wrapped capture: the condition context binds the rc.
r="$(mkfix ifwrap)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          if ! EXISTING=$(gh issue list --state open); then
            echo "::error::fx: dedupe query failed"; EXISTING=""
          fi
          bad=$(gh issue list --state open)
YAML
assert_fires "G2 control: the bad line after the if/fi FIRES" "$r" 12
assert_not_named "G2b an if-wrapped capture does NOT fire" "$r" 9

# G3 -- a `# dedupe:` marker on the immediately preceding line classifies.
r="$(mkfix markerok)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          bad=$(gh issue list --state open)
          # dedupe: benign — close-path read; a gh fault leaves the issue open
          STALE=$(gh issue list --state open)
YAML
assert_fires "G3 control: the unmarked bad line FIRES" "$r" 9
assert_not_named "G3b the marked site does NOT fire" "$r" 11

# G4 -- a marker exactly 2 lines above is inside the adjacency window.
r="$(mkfix markertwo)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          # dedupe: benign — exactly two lines above, the window's edge
          NOW=$(date -u)
          STALE=$(gh issue list --state open)
          bad=$(gh issue list --state open)
YAML
assert_fires "G4 control: the unmarked bad line FIRES" "$r" 12
assert_not_named "G4b a marker two lines above still classifies" "$r" 11

# G5 -- a `||` handler on the LAST line of a continuation-classified site.
r="$(mkfix conthandled)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --repo "$GH_REPO" --state open \
            --label ci/fx --json number \
            --jq '.[0].number // empty') || { echo "::error::fx: dedupe query failed"; EXISTING=""; }
          bad=$(gh issue list --state open)
YAML
assert_fires "G5 control: the bad line FIRES" "$r" 12
assert_not_named "G5b the ||-handled multi-line site does NOT fire" "$r" 9

# G6 -- a `=$(` shape inside a comment is data, not a capture.
r="$(mkfix comment)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          # EXISTING=$(gh issue list --state open) is the pre-#9659 bare shape
          bad=$(gh issue list --state open)
YAML
assert_fires "G6 control: the real defect below the comment FIRES" "$r" 10
assert_not_named "G6b the capture shape quoted inside a comment does NOT fire" "$r" 9

# G7 -- a `$(gh issue list)` inside a heredoc body is stdin data, never argv
# (fixture generators embed gh-shaped text routinely).
r="$(mkfix heredoc)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          cat > "$RUNNER_TEMP/gen.sh" <<'INNER'
          EXISTING=$(gh issue list --state open)
          INNER
          bad=$(gh issue list --state open)
YAML
assert_fires "G7 control: the real defect AFTER the heredoc FIRES" "$r" 12
assert_not_named "G7b a dedupe capture inside a heredoc body does NOT fire" "$r" 10

# G8 -- a `for n in $(gh issue list …)` word-expansion is NOT the class: the
# substitution's rc is not the command's rc, so it cannot abort the step.
r="$(mkfix forloop)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          for n in $(gh issue list --state open --json number --jq '.[].number'); do
            gh issue close "$n"
          done
          bad=$(gh issue list --state open)
YAML
assert_fires "G8 control: the bad line FIRES" "$r" 12
assert_not_named "G8b a for-list gh-issue-list substitution does NOT fire" "$r" 9

# G9 -- the quoted twin: `EXISTING="$(` is advisory, never a gate finding —
# but it must appear in the advisory census (measured, not hidden).
r="$(mkfix quoted)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING="$(gh issue list --state open)"
          bad=$(gh issue list --state open)
YAML
assert_fires "G9 control: the bad unquoted line FIRES" "$r" 10
run_lint "$r"
if ! grep -qE ':9:.*unclassified dedupe capture' "$TMP/out.txt"; then
  pass "G9b the quoted-capture site is NOT a census finding"
else
  fail "G9b the quoted-capture site is NOT a census finding" "no finding at line 9" "$(tr '\n' ' ' < "$TMP/out.txt")"
fi
_qout="$(python3 "$LINTER" --root "$r" 2>&1 || true)"
if printf '%s\n' "$_qout" | grep -q 'advisory.*:9:.*EXISTING'; then
  pass "G9c the quoted site lands in the advisory census"
else
  fail "G9c the quoted site lands in the advisory census" "advisory row naming :9:" "$(printf '%s' "$_qout" | tr '\n' ' ')"
fi

# G10 -- a quoted site that IS handled (`||`) leaves the advisory too.
r="$(mkfix quotedhandled)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING="$(gh issue list --state open)" || { echo "::error::fx"; EXISTING=""; }
          bad=$(gh issue list --state open)
YAML
assert_fires "G10 control: the bad unquoted line FIRES" "$r" 10
_qhout="$(python3 "$LINTER" --root "$r" 2>&1 || true)"
if ! printf '%s\n' "$_qhout" | grep -q 'advisory.*:9:'; then
  pass "G10b a ||-handled quoted site is absent from the advisory"
else
  fail "G10b a ||-handled quoted site is absent from the advisory" "no advisory row for :9:" "$(printf '%s' "$_qhout" | tr '\n' ' ')"
fi

# --- the gate's own scope ---------------------------------------------------

# H1 -- a root with no .github/workflows is a USAGE error (rc=2), never a pass.
r="$(mkfix emptyroot)"
rm -rf "$r/.github"
out="$(python3 "$LINTER" --root "$r" 2>&1)"; rc=$?
if [[ "$rc" == "2" ]]; then
  pass "H1 a root with no workflows dir exits 2, not 0"
else
  fail "H1 a root with no workflows dir exits 2, not 0" "rc=2" "rc=$rc ($out)"
fi

# H2 -- workflows present but ZERO census sites is a vacuity RED, not a pass
# (Guard 1 mutation row 4: a 0-match census is a broken detector).
r="$(mkfix zerohits)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: echo hello
YAML
out="$(python3 "$LINTER" --root "$r" 2>&1)"; rc=$?
if [[ "$rc" == "2" ]]; then
  pass "H2 a zero-census tree exits 2 (vacuity), not 0"
else
  fail "H2 a zero-census tree exits 2 (vacuity), not 0" "rc=2" "rc=$rc ($out)"
fi

# H3 -- VERIFY THE VERIFIER: plant the defect into a copy of a live workflow
# and require the linter to catch it. Without this every must-not-fire case
# is compatible with a detector that finds nothing at all.
r="$(mkfix regression)"
rm -rf "$r/.github" && cp -r "$REPO_ROOT/.github" "$r/.github" \
  || { echo "FATAL: could not copy .github"; exit 2; }
target="$r/.github/workflows/scheduled-zot-restart-loop.yml"
if [[ -f "$target" ]]; then
  printf '\n# planted regression\nEXISTING=$(gh issue list --json number)\n' >> "$target"
  mout="$(python3 "$LINTER" --root "$r" --quiet 2>&1)"; mrc=$?
  printf '%s\n' "$mout" > "$TMP/mut.txt"
  if [[ "$mrc" == "1" ]] && grep -q 'scheduled-zot-restart-loop.yml' "$TMP/mut.txt"; then
    pass "H3 a planted bare dedupe capture in a live workflow is CAUGHT"
  else
    fail "H3 a planted bare dedupe capture in a live workflow is CAUGHT" \
      "rc=1 naming scheduled-zot-restart-loop.yml" \
      "rc=$mrc; $(tr '\n' ' ' < "$TMP/mut.txt")"
  fi
else
  fail "H3 the zot-restart-loop workflow is present in the tree copy" "a readable file" "absent"
fi

# H4 -- the live tree passes the gate's actual contract.
live="$(python3 "$LINTER" --root "$REPO_ROOT" 2>&1)"; live_rc=$?
printf '%s\n' "$live" > "$TMP/live.txt"
if [[ "$live_rc" == "0" ]] && grep -q 'dedupe-shape: unclassified: 0' "$TMP/live.txt"; then
  pass "H4 the live tree prints dedupe-shape: unclassified: 0"
else
  fail "H4 the live tree prints dedupe-shape: unclassified: 0" "rc=0 + pass literal" "rc=$live_rc; $(printf '%s' "$live" | tail -5 | tr '\n' ' ')"
fi

# H5 -- the census reached a non-trivial site population on the live tree (a
# scanner that silently narrowed the class reads green with real numbers).
site_n="$(sed -n 's/.*census site(s): .*/&/p' "$TMP/live.txt" | grep -oE '[0-9]+ census site' | grep -oE '^[0-9]+')"
if [[ "${site_n:-0}" -ge 70 ]]; then
  pass "H5 live census reaches >=70 sites (got ${site_n:-0})"
else
  fail "H5 live census reaches >=70 sites" ">=70" "${site_n:-<unparsed>}"
fi

# --- verdict ----------------------------------------------------------------
echo ""
echo "Total: $((passes + fails))  Pass: $passes  Fail: $fails"

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi

# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments
# into a mutant, and a binding far above is unbound there (measured: CONSTRUCTION,
# not FIRES). The instrument self-test above asserts passes == 1, so the literal
# is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=24
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "All tests passed"
