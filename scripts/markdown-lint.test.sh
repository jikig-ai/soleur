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

# DERIVED from the SUT, never restated. A hand-kept copy is the stale-snapshot class
# this repo names explicitly: the two would drift silently and the sandbox would stop
# covering the roots the guard actually asserts.
mapfile -t ROOTS < <(
  sed -n 's/^[[:space:]]*EXPECTED_ROOTS=(\(.*\))[[:space:]]*$/\1/p' "$REPO_ROOT/$SUT_REL" | tr ' ' '\n'
)
(( ${#ROOTS[@]} >= 8 )) || die "derived ${#ROOTS[@]} roots from the SUT; the extraction is broken"


build_sandbox() {
  local d="$1" i=0 r
  mkdir -p "$d/scripts" || die "sandbox mkdir failed"
  cp "$REPO_ROOT/$SUT_REL" "$d/scripts/markdown-lint.sh" || die "cannot copy SUT"
  chmod +x "$d/scripts/markdown-lint.sh"
  cp "$REPO_ROOT/.markdownlint.json" "$d/.markdownlint.json" || die "cannot copy config"
  cp "$REPO_ROOT/package.json" "$d/package.json" || die "cannot copy manifest"
  # The engine pin is read from the LOCKFILE, so the sandbox needs one. Without it
  # every case would die on "declares no markdownlint rules-engine version" and the
  # whole suite would measure that precondition instead of what each row names.
  cp "$REPO_ROOT/package-lock.json" "$d/package-lock.json" || die "cannot copy lockfile"
  ln -s "$REPO_ROOT/node_modules" "$d/node_modules" || die "cannot link node_modules"
  printf 'ignored-corpus/\n' > "$d/.markdownlintignore"

  # A clean synthesized corpus, spread over every asserted root, sized above the SUT's
  # floor. 150 per root x 11 derived roots = 1650. Sized so M4 can drop a WHOLE root
  # (-150) and still sit above MIN_SWEPT_FILES=1200 -- an earlier 170x8 sizing put the
  # drop at 1190, so M4 tripped the FLOOR and never reached the roots assertion it
  # exists to test. Re-derive this product whenever the root set or the floor moves.
  for r in "${ROOTS[@]}"; do
    mkdir -p "$d/$r/docs" || die "sandbox mkdir $r failed"
    for ((i=0; i<150; i++)); do
      printf '# Title %s\n\nBody text for %s number %s.\n' "$i" "$r" "$i" \
        > "$d/$r/docs/doc-$i.md" || die "sandbox fixture write failed"
    done
  done
  mkdir -p "$d/ignored-corpus" && printf '#Bad\n\n\n\nstuff\n' > "$d/ignored-corpus/x.md"
  # A depth-1 file. The real corpus has nine (AGENTS.md, README.md, ...) and every
  # sandbox fixture was three components deep, so the depth-reach guard had no
  # fixture that could exercise it and the cheapest narrowing in the producer was
  # invisible to the whole suite.
  printf '# Root\n\nRepository-root document.\n' > "$d/ROOT-DOC.md"

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
# The swept-file count on the pristine sandbox. Every legal-input row adds exactly one
# file, so `CONTROL_N + 1` is the count that proves the fixture REACHED the linter.
CONTROL_N="$(run_sut --repo-sweep | sed -n 's/.*markdown-lint: \([0-9][0-9]*\) file(s) clean.*/\1/p' | tail -1)"
[[ "$CONTROL_N" =~ ^[0-9]+$ ]] || die "could not read the control's swept-file count"

# `assert_green` alone is satisfied by a fixture that was never written: the sandbox is
# then pristine and the sweep is green for exactly the reason the CONTROL is green, so
# the row reports a pass having tested nothing. Measured on H3 -- redirecting its write
# to /dev/null left the whole suite green. Unlike the `assert_red` rows, which are
# self-detecting (an absent fixture means no error to catch, so the row flips to FAIL),
# the green direction needs the count to prove the file was actually linted. It cannot
# use `assert_landed`: these rows CREATE files, so there is no pristine counterpart.
assert_green_covering() { # <label> <args...> -- asserts green AND that one new file was swept
  local label="$1"; shift
  local out rc
  out="$(run_sut "$@")"; rc=$?
  local n; n="$(sed -n 's/.*markdown-lint: \([0-9][0-9]*\) file(s) clean.*/\1/p' <<<"$out" | tail -1)"
  if (( rc != 0 )); then
    fail "$label -- guard went RED on legal input"
  elif [[ "$n" != "$(( CONTROL_N + 1 ))" ]]; then
    fail "$label -- swept $n file(s), expected $(( CONTROL_N + 1 )); the fixture never reached the linter"
  else
    pass "$label"
  fi
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
    # NAMED EXCLUSION, with its reason, following this repo's convention that an
    # exclusion is a recorded decision rather than a silent absorption.
    #
    # plugins/soleur/test/hook-git-env-coverage.mutation.sh SYNTHESISES workflow
    # snippets as fixture DATA -- its `run: markdownlint --fix docs/` is a quoted
    # string argument to a test helper (case "J3 GREEN: a non-test run: line needs no
    # scrub"), not an invocation. It is the file that demonstrated the old pattern's
    # blind spot: the pattern could not see a bare `markdownlint` off PATH, and this
    # is the only place in the repo that writes one. Widening the pattern was correct;
    # this file is the one true match that is not a call site.
    [[ "$f" == "$base/plugins/soleur/test/hook-git-env-coverage.mutation.sh" ]] && continue
    # Anchored on command POSITION for the bare form: `markdownlint` off PATH and a
    # direct `node .../markdownlint.js` are invocations the earlier pattern could not
    # see. A fixture in this repo already carries `run: markdownlint --fix docs/` and
    # went unmatched -- the blind spot demonstrated rather than argued.
    sed 's/#.*//' "$f" 2>/dev/null | grep -qE '(npx[^|]*markdownlint|markdownlint-cli|\.bin/markdownlint|(^|[;&|[:space:]])markdownlint[[:space:]]|node[^|]*markdownlint[^|]*\.js)' \
      && printf '%s\n' "$f"
  done < <(
    { [[ -f "$base/lefthook.yml" ]] && printf '%s\n' "$base/lefthook.yml"
      find "$base/.github" -name '*.yml' -o -name '*.yaml' 2>/dev/null
      find "$base/scripts" -name '*.sh' 2>/dev/null
      # package.json is the single likeliest home for a second invoker (a "lint:md"
      # script entry), and plugins/ ships executables to customers. Omitting them made
      # M7b non-vacuous only WITHIN a population that excluded the obvious next site.
      # The population must be the places an invoker can LIVE, not the places we
      # happened to think of. .github/scripts, .claude/hooks, tests/ and apps/ were all
      # outside it, as were non-.sh scripts.
      find "$base/.github/scripts" "$base/.claude/hooks" "$base/tests" \
           \( -name '*.sh' -o -name '*.mjs' -o -name '*.js' \) 2>/dev/null
      find "$base/plugins" "$base/apps" -name '*.sh' 2>/dev/null
      find "$base/scripts" \( -name '*.py' -o -name '*.mjs' -o -name '*.ts' \) 2>/dev/null; } | sort -u
  )
}
# package.json is scanned through its `scripts` block ALONE. A whole-file grep matches
# the devDependencies pin -- a DECLARATION this PR adds deliberately -- and reports the
# manifest as a second invoker. Only a script entry can actually invoke anything.
# ...and EVERY manifest, not only the root one. There are five tracked sub-manifests
# (apps/web-platform, plugins/soleur/docs, two plugin script dirs, spike); a `lint:md`
# entry in any of them is a second invoker the root-only scan could not see.
pkg_hits=""
for _pkg in $(cd "$REPO_ROOT" && git ls-files 'package.json' '*/package.json' 2>/dev/null); do
  python3 -c "
import json,sys,re
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
v=' '.join(str(x) for x in (d.get('scripts') or {}).values())
sys.exit(0 if re.search(r'markdownlint-cli|[.]bin/markdownlint|npx[^|]*markdownlint|(^|[;&|\s])markdownlint\s', v) else 1)
" "$REPO_ROOT/$_pkg" 2>/dev/null && pkg_hits="$pkg_hits$REPO_ROOT/$_pkg"$'\n'
done
if false && [[ -f "$REPO_ROOT/package.json" ]] && python3 -c "
import json,sys,re
d=json.load(open(sys.argv[1]))
v=' '.join(str(x) for x in (d.get('scripts') or {}).values())
sys.exit(0 if re.search(r'markdownlint-cli|[.]bin/markdownlint|npx[^|]*markdownlint', v) else 1)
" "$REPO_ROOT/package.json" 2>/dev/null; then
  pkg_hits="$REPO_ROOT/package.json"
fi
real_hits="$(printf '%s\n%s\n' "$(call_sites "$REPO_ROOT")" "$pkg_hits" | grep -v '^[[:space:]]*$' || true)"
if [[ -z "$real_hits" ]]; then
  pass "M7a -- the real repository has exactly one invoker"
else
  fail "M7a -- a second invoker exists: $(tr '\n' ' ' <<<"$real_hits")"
fi
# Positive control, ONE CELL PER ARM. Injecting only into lefthook.yml proves that ONE
# branch of the population reaches the matcher; every other branch could be blind while
# this still reported "not vacuous". The population is a union, so the control has to be
# a union too -- and the spellings matter as much as the locations, because the whole
# defect class here is a runner that resolves an UNPINNED binary (`npx --yes`, and its
# four siblings that arrived after it).
m7b_blind=()
m7b_probe() { # <relative-path> <content>
  restore
  mkdir -p "$SANDBOX/$(dirname "$1")"
  printf '%s\n' "$2" > "$SANDBOX/$1"
  [[ -n "$(call_sites "$SANDBOX")" ]] || m7b_blind+=("$1 :: $2")
}
m7b_probe "lefthook.yml"                 '      - run: npx markdownlint-cli .'
m7b_probe ".github/workflows/x.yml"      '      - run: npx --yes markdownlint-cli docs/'
m7b_probe ".github/scripts/x.sh"         'bunx markdownlint docs/'
m7b_probe ".claude/hooks/x.sh"           'pnpm dlx markdownlint docs/'
m7b_probe "scripts/x.sh"                 'npm exec markdownlint -- docs/'
m7b_probe "scripts/x.mjs"                'node ./node_modules/markdownlint-cli/markdownlint.js docs/'
m7b_probe "tests/x.js"                   'markdownlint docs/'
m7b_probe "apps/x.sh"                    './node_modules/.bin/markdownlint docs/'
m7b_probe "plugins/x.sh"                 'yarn markdownlint docs/'
restore
if (( ${#m7b_blind[@]} == 0 )); then
  pass "M7b -- every arm of the population sees an injected second invoker (9 location x spelling cells)"
else
  fail "M7b -- ${#m7b_blind[@]} cell(s) INVISIBLE: $(printf '%s | ' "${m7b_blind[@]}")"
fi
# M7c: the package.json arm must be able to FIRE. Without this it is a check whose
# passing state is indistinguishable from a check that cannot run -- and it currently
# passes on a manifest that DOES name the binary, which is exactly the shape that hides
# a dead predicate.
pkg_probe() { python3 -c "
import json,sys,re
d=json.load(open(sys.argv[1]))
v=' '.join(str(x) for x in (d.get('scripts') or {}).values())
sys.exit(0 if re.search(r'markdownlint-cli|[.]bin/markdownlint|npx[^|]*markdownlint', v) else 1)
" "$1"; }
pj="$(mktemp "$TMPDIR/mdlint-pkg.XXXXXXXX.json")" || die "mktemp failed"
python3 -c "
import json,sys
json.dump({'devDependencies':{'markdownlint-cli':'0.49.1'},'scripts':{'test':'bash x.sh'}}, open(sys.argv[1],'w'))
" "$pj"
pkg_probe "$pj" && decl_fires=0 || decl_fires=1
python3 -c "
import json,sys
json.dump({'scripts':{'lint:md':'npx markdownlint-cli .'}}, open(sys.argv[1],'w'))
" "$pj"
pkg_probe "$pj" && inv_fires=0 || inv_fires=1
rm -f "$pj"
if (( decl_fires == 1 && inv_fires == 0 )); then
  pass "M7c -- the package.json arm ignores a dependency DECLARATION and fires on a script INVOCATION"
else
  fail "M7c -- expected declaration=no-fire invocation=fire; got decl=$decl_fires inv=$inv_fires"
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
assert_green_covering "H3 -- a long line, inline HTML, an unlabelled fence and a second H1 are legal here" --repo-sweep
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

# --- H4: git is the SOLE scope interpreter -----------------------------------------
# The linter reads .markdownlintignore ITSELF and silently drops explicitly-passed
# paths, so without --ignore-path /dev/null the scope is interpreted TWICE and the
# guards above (which count the PRE-filter set) would certify files the linter never
# read. Two arms: the flag is in the invocation, and the flag CHANGES the verdict.
printf 'H4 sole scope interpreter\n'

# (a) The SUT passes it. Anchored on the comment-STRIPPED source: the block explaining
#     this flag names it in prose, so a bare grep would match its own rationale.
if sed 's/#.*//' "$REPO_ROOT/$SUT_REL" | grep -qE '^[^#]*xargs -0 .*--ignore-path /dev/null'; then
  pass "H4a -- the sweep invocation passes --ignore-path /dev/null"
else
  fail "H4a -- the sweep invocation does not pass --ignore-path /dev/null"
fi

# (b) It is load-bearing, not decoration. Same binary, same red file, same ignore file:
#     with the flag the error is reported, without it the file is silently dropped.
h4="$(mktemp -d "$TMPDIR/mdlint-h4.XXXXXXXX")" || die "mktemp failed"
mkdir -p "$h4/sub"
printf '#NoSpace\n\n\n\nText.\n' > "$h4/sub/red.md"
printf 'sub/\n' > "$h4/.markdownlintignore"
( cd "$h4" && "$REPO_ROOT/node_modules/.bin/markdownlint" --ignore-path /dev/null sub/red.md >/dev/null 2>&1 ); with_flag=$?
( cd "$h4" && "$REPO_ROOT/node_modules/.bin/markdownlint" sub/red.md >/dev/null 2>&1 ); without_flag=$?
rm -rf "$h4"
if (( with_flag != 0 && without_flag == 0 )); then
  pass "H4b -- the flag is load-bearing (red file: caught with it, silently dropped without)"
else
  fail "H4b -- expected with=non-zero without=0; got with=$with_flag without=$without_flag"
fi
restore

# --- M6c: the RULES ENGINE pin, not just the CLI pin -----------------------------
# markdownlint-cli depends on its engine by RANGE (~0.41.1), so the CLI version matching
# says nothing about the version that actually decides verdicts. Without this the script
# reports a satisfied pin while the engine floats -- defect 1, inside its own fix.
printf 'M6c rules-engine pin\n'
python3 - "$SANDBOX/package-lock.json" <<'PYFIX'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
for k,v in d["packages"].items():
    if k=="node_modules/markdownlint" or k.endswith("/node_modules/markdownlint"):
        v["version"]="99.99.99"; break
else:
    raise SystemExit("no engine entry in the sandbox lockfile")
json.dump(d,open(p,"w"))
PYFIX
assert_landed "package-lock.json" "M6c"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'rules engine' <<<"$out"; then
  pass "M6c -- an engine version differing from the lockfile pin is refused"
else
  fail "M6c -- expected an engine-pin refusal; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M8: a file-level disable silences a file that still counts --------------------
printf 'M8 inline silencing\n'
{ printf '<!-- markdownlint-disable -->\n\n# T\n\n\n\nBody.\n'; } > "$SANDBOX/docs/docs/silenced.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'markdownlint-disable' <<<"$out"; then
  pass "M8 -- an unmatched file-level disable is caught (the file still counts toward the floor)"
else
  fail "M8 -- expected an unbalanced-directive refusal; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M8b: a scoped disable-line is NOT caught (the guard is not too aggressive) -----
# Direction control. Without this the suite could only see the guard being too weak.
printf 'M8b scoped disable-line stays legal\n'
printf '# T\n\nA span `run_suite ` prefix. <!-- markdownlint-disable-line MD038 -->\n' \
  > "$SANDBOX/docs/docs/scoped.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
assert_green_covering "M8b -- a scoped -disable-line is permitted (it silences one visible site, not a file)" --repo-sweep
restore

# --- E3: explicit paths resolve against the CALLER's cwd -------------------------
# The script cd's to the repo root, so a bare map lookup silently missed any
# cwd-relative argument and reported "nothing to lint" at exit 0 -- a green that means
# nothing. Measured before the fix, from plugins/: `soleur/README.md` reported nothing
# to lint while `plugins/soleur/README.md` reported 1 file clean.
printf 'E3 cwd-relative explicit paths\n'
printf '#NoSpace\n\n\n\nText.\n' > "$SANDBOX/docs/docs/red.md"
( cd "$SANDBOX" && git add -A >/dev/null 2>&1 )
( cd "$SANDBOX/docs" && bash ../scripts/markdown-lint.sh docs/red.md >/dev/null 2>&1 )
if (( $? != 0 )); then
  pass "E3 -- a cwd-relative path from a subdirectory is linted, not silently skipped"
else
  fail "E3 -- a cwd-relative path reported success; the caller-cwd resolution regressed"
fi
restore

# --- M11: the no-network precondition -------------------------------------------
# The `[[ -x "$BIN" ]] || die` line IS the no-fallback policy -- it is the difference
# between "refuse loudly" and the `npx --yes` behaviour that #7927 exists to remove.
# Nothing exercised it, so deleting it (or replacing the die with an npx fallback) left
# the suite fully green while reinstating the originating defect.
printf 'M11 missing binary refuses, never falls back\n'
rm -f "$SANDBOX/node_modules"
mkdir -p "$SANDBOX/node_modules"          # present but carrying no .bin/markdownlint
out="$(run_sut --repo-sweep 2>&1)"; rc=$?
if (( rc != 0 )) && grep -q 'not installed' <<<"$out" && grep -q 'npm install' <<<"$out"; then
  pass "M11 -- an absent binary is a loud refusal naming the fix, not a network fallback"
else
  fail "M11 -- expected a no-binary refusal; rc=$rc out=$(head -c 200 <<<"$out")"
fi
# The refusal must not be reachable by DOWNLOADING one: no npx/curl/wget anywhere in
# the SUT. A fallback added later would satisfy the row above while defeating its point.
# Comments AND double-quoted strings are stripped first. The SUT's refusal messages
# NAME the remedy ("run: npm install --ignore-scripts") and one comment block explains
# why npx is refused, so a bare-token grep reports the policy's own documentation as a
# breach of the policy -- the body-grep false-positive class this suite already handles
# in M7 and H4a. Only a command POSITION counts.
if python3 - "$REPO_ROOT/$SUT_REL" <<'PYNET'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"#.*", "", src)                      # comments
src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)      # double-quoted strings
src = re.sub(r"'[^']*'", "''", src)                # single-quoted strings
pat = r"(?:^|[;&|]|\bthen\b|\bdo\b|\belse\b)\s*(npx|curl|wget|bunx|npm\s+(?:i|install|exec)|pnpm\s+dlx|yarn\s+add)\b"
sys.exit(0 if re.search(pat, src, re.M) else 1)
PYNET
then
  fail "M11b -- the SUT contains a network/installer invocation; the no-fallback policy is broken"
else
  pass "M11b -- the SUT contains no network or installer invocation at all"
fi
rmdir "$SANDBOX/node_modules" 2>/dev/null || rm -rf "$SANDBOX/node_modules"
ln -s "$REPO_ROOT/node_modules" "$SANDBOX/node_modules" || die "could not restore the node_modules link"
restore

# --- W1: the gate is WIRED (existence, not just uniqueness) -----------------------
# M7 asserts "at most one invoker". It never asserted "at least one". Deleting the CI
# job AND the lefthook line leaves every M7 arm green and the gate simply stops running
# -- which is verbatim defect 3 in the SUT's own header ("Nothing in CI ran markdownlint
# at all"). Uniqueness without existence is satisfied by a repository that does not lint.
printf 'W1 the gate is wired\n'

if grep -qE '^[[:space:]]*run:[[:space:]]*bash scripts/markdown-lint\.sh --repo-sweep' \
     "$REPO_ROOT/.github/workflows/pr-quality-guards.yml"; then
  pass "W1a -- the CI job invokes the sweep"
else
  fail "W1a -- no CI step runs 'bash scripts/markdown-lint.sh --repo-sweep'"
fi

if grep -qE '^[[:space:]]*run:[[:space:]]*bash scripts/markdown-lint\.sh \{staged_files\}' \
     "$REPO_ROOT/lefthook.yml"; then
  pass "W1b -- the pre-commit hook invokes the script with staged files"
else
  fail "W1b -- lefthook does not pass {staged_files} to scripts/markdown-lint.sh"
fi

if grep -qx 'markdown-lint' "$REPO_ROOT/scripts/required-checks.txt"; then
  pass "W1c -- the context is registered in required-checks.txt"
else
  fail "W1c -- 'markdown-lint' is absent from scripts/required-checks.txt"
fi

# W1d: the job must carry no `if:`. A required context that does not report on
# merge_group leaves the queue entry pending forever.
if awk '/^  markdown-lint:/{f=1;next} /^  [a-z]/{f=0} f' \
     "$REPO_ROOT/.github/workflows/pr-quality-guards.yml" | grep -qE '^[[:space:]]*if:'; then
  fail "W1d -- the markdown-lint job carries an 'if:'; a required context that skips on merge_group wedges the queue"
else
  pass "W1d -- the markdown-lint job carries no 'if:' gate"
fi

# --- M9: the producer must reach depth 1 -----------------------------------------
# `git ls-files '*.md'` -> `'*/*.md'` is a two-character edit that drops all nine
# repo-root files (README.md, AGENTS.md, CLAUDE.md, CONTRIBUTING.md and five more),
# leaving 1,336 -- above the floor, and invisible to the roots assertion because a
# depth-1 path's "root" is the filename itself.
printf 'M9 depth-1 reach\n'
python3 - "$SANDBOX/scripts/markdown-lint.sh" <<'PYFIX'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
old="git ls-files -z '*.md'"
assert s.count(old)==1, f"anchor count {s.count(old)}"
open(p,"w",encoding="utf-8").write(s.replace(old, "git ls-files -z '*/*.md'"))
PYFIX
assert_landed "scripts/markdown-lint.sh" "M9"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'depth-1' <<<"$out"; then
  pass "M9 -- a producer that stops matching at depth 1 is caught (the floor cannot see it)"
else
  fail "M9 -- expected a depth-reach refusal; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- M10: the count must be DISTINCT ----------------------------------------------
printf 'M10 distinctness\n'
python3 - "$SANDBOX/scripts/markdown-lint.sh" <<'PYFIX'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
old="mapfile -d '' -t FILES < <(scope_nul)"
assert s.count(old)==1, f"anchor count {s.count(old)}"
open(p,"w",encoding="utf-8").write(s.replace(old, "mapfile -d '' -t FILES < <(scope_nul; scope_nul)"))
PYFIX
assert_landed "scripts/markdown-lint.sh" "M10"
out="$(run_sut --repo-sweep)"; rc=$?
if (( rc != 0 )) && grep -q 'distinct' <<<"$out"; then
  pass "M10 -- a duplicated producer is caught (the floor would otherwise pass on a multiset)"
else
  fail "M10 -- expected a distinctness refusal; rc=$rc out=$(head -c 160 <<<"$out")"
fi
restore

# --- Anti-vacuity floor -----------------------------------------------------------
# Reported with printf + exit, NEVER through fail(): a floor that calls the helper it
# backstops is disarmed by the same edit that disarms the helper (ADR-193).
printf '\n=== markdown-lint.test.sh: %s passed, %s failed (%s cases) ===\n' "$passes" "$fails" "$cases"
# The threshold is declared IMMEDIATELY above its `if`, with nothing between them.
# guard-vacuity-floor.test.sh builds a mutant by slicing from the `if` to its `fi` and
# walking BACKWARD over adjacent bare assignments to bind the constants; any other
# statement in between stops that walk, the mutant dies on `set -u` with the threshold
# unbound, and a fully compliant floor is reported as a construction failure rather
# than as covered. Measured: this floor joined that uncovered set until the printf moved.
MIN_CASES=29
if (( cases < MIN_CASES )); then
  printf 'ERROR: only %s cases ran, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
exit 0
