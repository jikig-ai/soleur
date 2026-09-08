#!/usr/bin/env bash
# markdown-lint.test.sh -- proves scripts/markdown-lint.sh can be driven RED.
#
# WHY (#7927): the gate's whole value is that it fails when the corpus is dirty. A guard
# that cannot be driven red is vacuous, and reading it is not proof -- this repo has
# shipped several that read as protective and held nothing. Every row below MUTATES
# something and asserts the observed outcome.
#
# HERMETIC SANDBOX, SYNTHESIZED FIXTURES. Rows mutate .markdownlintignore, package.json
# and the script itself, so they cannot run against the real tree. The sandbox is a real
# git repository with a synthesized corpus large enough to clear the SUT's own floor --
# fixtures are synthesized, never captured (cq-test-fixtures-synthesized-only).

set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by every parallel worktree; a direct
# invocation of this suite inherits it while the repo runners default to /var/tmp. A
# sandbox that fails to build must abort, not silently score the previous row again.
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT_REL="scripts/markdown-lint.sh"

passes=0; fails=0; cases=0
pass() { passes=$((passes+1)); cases=$((cases+1)); printf '  [ok]   %s\n' "$1"; }
fail() { fails=$((fails+1));  cases=$((cases+1)); printf '  [FAIL] %s\n' "$1"; }

# --- Instrument self-test ----------------------------------------------------------
# Drive both helpers once and require both counters to move. A suite whose pass/fail
# helpers are broken reports whatever it likes; this is the one check that must run
# before any row is believed.
_p0=$passes; _f0=$fails
pass "instrument self-test (expected)"
fail "instrument self-test (expected -- subtracted below)"
if (( passes != _p0+1 || fails != _f0+1 )); then
  printf 'FATAL: assertion helpers do not move their counters; every row below is meaningless.\n' >&2
  exit 2
fi
passes=$((passes-1)); fails=$((fails-1)); cases=$((cases-2))
printf '  (instrument OK -- both counters moved; counters reset)\n'

die() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }

# --- Sandbox -----------------------------------------------------------------------
SANDBOX="$(mktemp -d "$TMPDIR/mdlint-sut.XXXXXXXX")" || die "mktemp failed"
PRISTINE="$(mktemp -d "$TMPDIR/mdlint-pristine.XXXXXXXX")" || die "mktemp failed"
cleanup() { rm -rf "$SANDBOX" "$PRISTINE"; }
trap cleanup EXIT INT TERM HUP

# Roots the SUT asserts it reaches. Kept in sync with EXPECTED_ROOTS in the SUT.
ROOTS=(.claude .github apps docs knowledge-base plugins scripts tests)

build_sandbox() {
  local d="$1" i=0 r
  mkdir -p "$d/scripts" || die "sandbox mkdir failed"
  cp "$REPO_ROOT/$SUT_REL" "$d/scripts/markdown-lint.sh" || die "cannot copy SUT"
  chmod +x "$d/scripts/markdown-lint.sh"
  cp "$REPO_ROOT/.markdownlint.json" "$d/.markdownlint.json" || die "cannot copy config"
  cp "$REPO_ROOT/package.json" "$d/package.json" || die "cannot copy manifest"
  ln -s "$REPO_ROOT/node_modules" "$d/node_modules" || die "cannot link node_modules"
  printf 'ignored-corpus/\n' > "$d/.markdownlintignore"

  # A clean synthesized corpus, spread over every asserted root, sized above the SUT's
  # floor. 200 per root x 8 roots = 1600. Sized so M4 can drop a WHOLE root (-200)
  # and still sit above MIN_SWEPT_FILES=1200 -- at 170/root the drop landed at 1190,
  # so M4 tripped the FLOOR and never reached the roots assertion it exists to test.
  for r in "${ROOTS[@]}"; do
    mkdir -p "$d/$r/docs" || die "sandbox mkdir $r failed"
    for ((i=0; i<200; i++)); do
      printf '# Title %s\n\nBody text for %s number %s.\n' "$i" "$r" "$i" \
        > "$d/$r/docs/doc-$i.md" || die "sandbox fixture write failed"
    done
  done
  mkdir -p "$d/ignored-corpus" && printf '#Bad\n\n\n\nstuff\n' > "$d/ignored-corpus/x.md"

  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A >/dev/null 2>&1 && git commit -q -m fixture >/dev/null 2>&1 ) \
    || die "sandbox git init/commit failed"
}

build_sandbox "$SANDBOX"
cp -a "$SANDBOX/." "$PRISTINE/" || die "pristine snapshot failed"

restore() {
  rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  cp -a "$PRISTINE/." "$SANDBOX/" || die "restore from pristine failed"
}

run_sut() { ( cd "$SANDBOX" && bash scripts/markdown-lint.sh "$@" 2>&1 ); }
run_sut_rc() { ( cd "$SANDBOX" && bash scripts/markdown-lint.sh "$@" >/dev/null 2>&1 ); }

# --- CONTROL: the unmutated sandbox must be GREEN ----------------------------------
# A red baseline voids every row below -- each would then be scoring the baseline.
if run_sut_rc --repo-sweep; then
  pass "CONTROL -- the unmutated sandbox is GREEN, so every row below scores a real mutation"
else
  printf 'FATAL: control run is RED. Every mutation row would pass for the wrong reason.\n' >&2
  run_sut --repo-sweep | tail -15 >&2
  exit 2
fi

assert_red() {  # <label> <args...>
  local label="$1"; shift
  if run_sut_rc "$@"; then fail "$label -- guard stayed GREEN under mutation"; else pass "$label"; fi
}
assert_green() {
  local label="$1"; shift
  if run_sut_rc "$@"; then pass "$label"; else fail "$label -- guard went RED on legal input"; fi
}
# Assert the mutation actually LANDED. A mutation that silently no-ops reports the
# baseline, which is indistinguishable from a guard that works.
assert_landed() { # <path> <label>
  cmp -s "$SANDBOX/$1" "$PRISTINE/$1" && die "mutation did not land: $2 (file identical to pristine)"
}

# --- M1: the originating defect must be catchable ----------------------------------
printf 'M1 escaped-backtick span (the originating defect)\n'
python3 - "$SANDBOX/plugins/docs/escaped.md" <<'PYFIX'
import sys
# Verified to reproduce the originating signature: MD038 x3 + MD052. A shorter fixture
# does NOT reproduce it -- an escaped tick only misaligns the spans that FOLLOW it, so
# the trailing backticks are load-bearing, not decoration.
open(sys.argv[1], "w").write(
    "# T\n\n"
    "- When a change edits a Supabase embedded `.select(\\`...\\`)` against an UNTYPED "
    "client, add a select-string test (capture `chain.select.mock.calls[i][0]`, assert no "
    "`auth.users`-only column like `raw_user_meta_data`) AND/OR an opt-in "
    "`*.integration.test.ts` vs dev.\n"
)
PYFIX
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
assert_red "M1 -- a restored escaped-backtick span is caught" --repo-sweep
restore

# --- M2: second member, different root, unchanged by any diff ----------------------
printf 'M2 red file in a different root\n'
printf '#NoSpace\n\n\n\nText.\n' > "$SANDBOX/docs/docs/red.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
assert_red "M2 -- a red file in another root is caught (sweep is not changed-files-only)" --repo-sweep
restore

# --- M3: dispatch row -- empty set must fail on the floor, not pass ----------------
printf 'M3 ignore everything\n'
printf '*.md\n' > "$SANDBOX/.markdownlintignore"
assert_landed ".markdownlintignore" "M3"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'below the floor' <<<"$out"; then
  pass "M3 -- an emptied scope fails on the FLOOR (not exit-0 on an empty set)"
else
  fail "M3 -- expected a floor failure; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M4: narrowing that stays above the floor -------------------------------------
printf 'M4 drop one whole root, staying above the floor\n'
printf 'ignored-corpus/\nknowledge-base/\n' > "$SANDBOX/.markdownlintignore"
assert_landed ".markdownlintignore" "M4"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'did NOT reach' <<<"$out"; then
  pass "M4 -- a dropped root fails the ROOTS assertion (a count floor cannot see this)"
else
  fail "M4 -- expected a roots failure; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M5: invocation from a subdirectory -------------------------------------------
# DEVIATION FROM THE PLAN, DELIBERATE. The Guard Contract expected M5 to FAIL on a
# working-directory assertion. This SUT resolves its root from BASH_SOURCE and cd's
# there, so it cannot lose .markdownlintignore no matter where it is invoked from --
# which is the stronger property the assertion existed to buy. Asserting the failure
# would pin the weaker design. The row therefore asserts EQUIVALENCE instead.
printf 'M5 invocation from a subdirectory\n'
from_root="$( cd "$SANDBOX" && bash scripts/markdown-lint.sh --repo-sweep 2>&1 )"
from_sub="$( cd "$SANDBOX/plugins/docs" && bash ../../scripts/markdown-lint.sh --repo-sweep 2>&1 )"
if [[ "$from_root" == "$from_sub" ]]; then
  pass "M5 -- a subdirectory invocation is byte-identical to a root one (scope cannot be lost)"
else
  fail "M5 -- subdirectory invocation diverged from root invocation"
fi

# --- M6: manifest pin moved without reinstalling ----------------------------------
printf 'M6 pin bumped without reinstall\n'
python3 - "$SANDBOX/package.json" <<'PY'
import json,sys,collections
p=sys.argv[1]; d=json.load(open(p), object_pairs_hook=collections.OrderedDict)
d["devDependencies"]["markdownlint-cli"]="99.99.99"
json.dump(d, open(p,"w"), indent=2)
PY
assert_landed "package.json" "M6"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'but package.json pins' <<<"$out"; then
  pass "M6 -- an installed binary that differs from the pin is refused"
else
  fail "M6 -- expected a version-pin failure; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M6b: a RANGE pin is refused --------------------------------------------------
# The defect #7927 exists to close is an unpinned resolver, so an exact-pin assertion
# that accepts a caret would readmit it.
printf 'M6b range pin\n'
python3 - "$SANDBOX/package.json" <<'PY'
import json,sys,collections
p=sys.argv[1]; d=json.load(open(p), object_pairs_hook=collections.OrderedDict)
d["devDependencies"]["markdownlint-cli"]="^0.49.1"
json.dump(d, open(p,"w"), indent=2)
PY
assert_landed "package.json" "M6b"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'is a RANGE' <<<"$out"; then
  pass "M6b -- a caret range is refused (an unpinned resolver is the original defect)"
else
  fail "M6b -- expected a range refusal; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M7: a second invoker anywhere in the repo ------------------------------------
# Runs against the REAL repository: the property is "this script is the only invoker",
# which is a statement about the repo, not about a sandbox.
#
# ANCHORED ON COMMAND POSITION, NOT A BARE TOKEN. Comments legitimately name the old
# command, and a bare-token grep would match its own explanatory prose -- the documented
# false-positive class for body-greps. Comments are stripped before matching.
printf 'M7 single-invoker call-site check\n'
call_sites() { # <root-dir>
  local base="$1" f
  while IFS= read -r f; do
    [[ "$f" == "$base/$SUT_REL" ]] && continue
    # This suite necessarily CONTAINS the tokens it greps for -- in M7b's injected
    # fixture and in the pattern itself. A checker that matches its own text is the
    # documented body-grep false-positive class.
    [[ "$f" == "$base/scripts/markdown-lint.test.sh" ]] && continue
    sed 's/#.*//' "$f" 2>/dev/null | grep -qE '(npx[^|]*markdownlint|markdownlint-cli|\.bin/markdownlint)' \
      && printf '%s\n' "$f"
  done < <(
    { [[ -f "$base/lefthook.yml" ]] && printf '%s\n' "$base/lefthook.yml"
      find "$base/.github" -name '*.yml' -o -name '*.yaml' 2>/dev/null
      find "$base/scripts" -name '*.sh' 2>/dev/null; } | sort -u
  )
}
real_hits="$(call_sites "$REPO_ROOT")"
if [[ -z "$real_hits" ]]; then
  pass "M7a -- the real repository has exactly one invoker"
else
  fail "M7a -- a second invoker exists: $(tr '\n' ' ' <<<"$real_hits")"
fi
# Positive control: the check must be able to SEE a second invoker.
mkdir -p "$SANDBOX/.github"
printf 'jobs:\n  x:\n    steps:\n      - run: npx markdownlint-cli .\n' > "$SANDBOX/lefthook.yml"
if [[ -n "$(call_sites "$SANDBOX")" ]]; then
  pass "M7b -- the call-site check detects an injected second invoker (not vacuous)"
else
  fail "M7b -- the call-site check could not see an injected second invoker"
fi
restore

# --- H1: SUT replaced by a no-op --------------------------------------------------
printf 'H1 SUT replaced by exit 0\n'
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/scripts/markdown-lint.sh"
chmod +x "$SANDBOX/scripts/markdown-lint.sh"
assert_landed "scripts/markdown-lint.sh" "H1"
printf '#NoSpace\n\n\n\nText.\n' > "$SANDBOX/docs/docs/red.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
if run_sut_rc --repo-sweep; then
  pass "H1 -- a no-op SUT is GREEN on a red corpus, which is exactly what M1/M2 catch"
else
  fail "H1 -- expected the no-op SUT to pass vacuously (M1/M2 are what make that detectable)"
fi
restore

# --- H2: zero cases must not exit 0 -----------------------------------------------
# Asserted by the floor below rather than by a row: a tally of 0 passed, 0 failed is
# the shape this suite must never exit 0 on.

# --- H3: legal-but-unusual input must NOT false-positive ---------------------------
printf 'H3 legal-but-unusual document\n'
{
  printf '# One\n\n'
  printf 'A very long line: '; printf 'x%.0s' $(seq 1 300); printf '\n\n'
  printf '<div align="center">inline html</div>\n\n'
  printf '```\nunlabelled fence\n```\n\n'
  printf '# Two top-level headings\n\nBody.\n'
} > "$SANDBOX/apps/docs/unusual.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
assert_green "H3 -- a long line, inline HTML, an unlabelled fence and a second H1 are legal here" --repo-sweep
restore

# --- Explicit-paths mode ----------------------------------------------------------
printf 'Explicit-paths mode\n'
if [[ "$(run_sut "ignored-corpus/x.md")" == *"nothing to lint"* ]]; then
  pass "E1 -- an out-of-scope path is a no-op, not a failure (the hook passes staged files)"
else
  fail "E1 -- an out-of-scope path was not reported as out of scope"
fi
printf '#NoSpace\n\n\n\nText.\n' > "$SANDBOX/docs/docs/red.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
assert_red "E2 -- an in-scope red path fails in explicit mode" "docs/docs/red.md"
restore

# --- Anti-vacuity floor -----------------------------------------------------------
# Reported with printf + exit, NEVER through fail(): a floor that calls the helper it
# backstops is disarmed by the same edit that disarms the helper (ADR-193).
MIN_CASES=12
printf '\n=== markdown-lint.test.sh: %s passed, %s failed (%s cases) ===\n' "$passes" "$fails" "$cases"
if (( cases < MIN_CASES )); then
  printf 'ERROR: only %s cases ran, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
exit 0
