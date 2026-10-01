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

# One scratch root for the whole suite (git shims, every fixture repo). The EXIT trap is
# installed BEFORE anything is allocated under it, so a failure at any later line still
# cleans up; nothing here ever touches a path it did not create.
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT

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
  "bad-mktemp-in-brace-body.sh.fixture|rule (c) mktemp with no owning trap|rule (c) fires on mktemp in a { } function body" \
  "bad-midline-append-named-fn-trap.sh.fixture|rule (a) subshell-append|rule (a) fires on a MID-LINE append in a one-liner helper whose trap names a FUNCTION (#6734 blind spot)"
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
GITSHIM="$T/shim-fail"
mkdir -p "$GITSHIM"
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
# actually counts a population, so the ratchet cannot be silently blind. `--census-detail`
# is the one real-tree pass: it carries the shell (class-b) count AND the walk sizes of the
# two new families, so rules (d)/(e) cannot be vacuous either (a walk that saw no py/ts
# files would leave both rules green over nothing).
detail=$(python3 "$LINT" --census-detail 2>/dev/null || echo "")
c=$(sed -n 's/^shell: //p' <<< "$detail")
if [[ "$c" =~ ^[0-9]+$ ]] && (( c > 0 )); then
  ok "census positive control: it reports a non-zero class-b population ($c)"
else
  no "census returned '$c' -- if it cannot count, --check-highwater passes vacuously"
fi
sp=$(sed -n 's/^scanned-py: //p' <<< "$detail"); st=$(sed -n 's/^scanned-ts: //p' <<< "$detail")
if [[ "$sp" =~ ^[0-9]+$ && "$st" =~ ^[0-9]+$ ]] && (( sp > 0 && st > 0 )); then
  ok "census-detail positive control: the walk saw $sp py and $st ts/js files"
else
  no "census-detail saw no py/ts files (py='$sp' ts='$st') -- rules (d)/(e) would be vacuous"
fi

# =======================================================================================
# Rules (d) and (e) -- allocation with no cleanup, and a hard-coded /tmp|/var/tmp base
# (#7004, Guard 2). Every arm below runs against a throwaway git repository, because the
# property under test is "an ADDED line is detected", and that cannot be observed by pointing
# the linter at a committed fixture (the fixture is "added" only until this PR merges).
# =======================================================================================
REAL_GIT="$(command -v git)"
export REAL_GIT
# A scrubbed git environment: an inherited GIT_DIR / GIT_INDEX_FILE would make every fixture
# repo write into the developer's real one (the #7840 failure mode).
GENV=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_PREFIX
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null)
REPO=""
g() { "${GENV[@]}" git -C "${REPO:?}" -c user.name=lint-test -c user.email=lint-test@example.invalid \
        -c commit.gpgsign=false "$@"; }

# mkrepo <dir> <hw-shell> <hw-d> <hw-e> <base-fixture>...   ; base fixtures land in src/
# The lint script is COPIED into the repo's scripts/ because it derives its repo root from
# its own location -- that is what makes the fixture repo, not this checkout, the subject.
mkrepo() {
  local dir="$1" hw_s="$2" hw_d="$3" hw_e="$4" f
  shift 4
  REPO="$T/$dir"
  mkdir -p "$REPO/scripts" "$REPO/src"
  g init -q -b main
  cp "$LINT" "$REPO/scripts/lint-trap-tempfile-ownership.py"
  printf '%s  # fixture shell highwater\n' "$hw_s" > "$REPO/scripts/lint-trap-tempfile-ownership.highwater"
  printf 'rule-d: %s\nrule-e: %s\n' "$hw_d" "$hw_e" > "$REPO/scripts/lint-trap-tempfile-ownership-tspy.highwater"
  for f in "$@"; do cp "$FIX/$f" "$REPO/src/${f%.fixture}"; done
  g add -A
  g commit -q -m base
  g checkout -q -b feat
}

# add_commit <fixture> [relname] : land a fixture on the feature branch, then PROVE it is an
# ADDED path against the merge base. Returns 1 when it is not -- a builder whose `git add`
# silently failed would otherwise leave the lint looking at an unchanged tree and every RED
# arm below would "fail to fail" for the wrong reason (harness row H1).
add_commit() {
  local fx="$1" rel="${2:-src/${1%.fixture}}"
  mkdir -p "$(dirname "$REPO/$rel")"
  cp "$FIX/$fx" "$REPO/$rel"
  g add -- "$rel"
  g commit -q -m "add $rel"
  g diff --name-only main...HEAD | grep -qxF -- "$rel" || { echo "builder: $rel is NOT an added path" >&2; return 1; }
}

# lint_in_repo [args...] : rc and stderr of the lint run from inside the fixture repo.
LRC=0; LERR=""
lint_in_repo() {
  LRC=0
  LERR="$("${GENV[@]}" python3 "${REPO:?}/scripts/lint-trap-tempfile-ownership.py" "$@" 2>&1 >/dev/null)" || LRC=$?
}
lint_in_repo_out() {
  LRC=0
  LERR="$("${GENV[@]}" python3 "${REPO:?}/scripts/lint-trap-tempfile-ownership.py" "$@" 2>&1)" || LRC=$?
}

CLEAN_SH="good-mktemp-with-trap.sh.fixture"
CLEAN_PY="d-good-py-mkdtemp-rmtree.py.fixture"
CLEAN_TS="d-good-ts-afterall-rmsync.ts.fixture"

# --- ADDED-line arms: each fixture is committed on a branch, asserted ADDED, then linted in
# default (merge-base-scoped) mode. expect=red needs rc 1 AND the right rule's message naming
# the added file; expect=pass needs rc 0. (Mutation rows 1, 3, 4, 7, 8, 9, 10; harness H2.)
for case in \
  "d-bad-py-mkdtemp-no-cleanup.py.fixture|red|rule (d) allocation with no cleanup|row 1: .py mkdtemp with no rmtree/TemporaryDirectory/atexit" \
  "d-bad-py-mkdtemp-no-cleanup-2.py.fixture|red|rule (d) allocation with no cleanup|row 1: .py mkstemp (from-import spelling) with no cleanup" \
  "d-bad-py-namedtempfile-delete-false.py.fixture|red|rule (d) allocation with no cleanup|row 1: NamedTemporaryFile(delete=False) with no cleanup" \
  "d-bad-ts-mkdtemp-no-rm.ts.fixture|red|rule (d) allocation with no cleanup|row 4: .ts mkdtempSync with no rmSync" \
  "d-bad-ts-afterall-scaffold-only.ts.fixture|red|rule (d) allocation with no cleanup|afterAll scaffolding with no removal call is not cleanup" \
  "d-bad-ts-lexer-regex-and-template.ts.fixture|red|rule (d) allocation with no cleanup|lexer survives a regex literal holding a quote and sees a call inside a template expression" \
  "d-bad-py-cleanup-in-comment-string.py.fixture|red|rule (d) allocation with no cleanup|row 9: py cleanup token only in a comment/string/docstring does not satisfy rule (d)" \
  "d-bad-ts-cleanup-in-comment-string.ts.fixture|red|rule (d) allocation with no cleanup|row 9: ts cleanup token only in a comment/string/template does not satisfy rule (d)" \
  "d-bad-py-syntax-error-with-alloc.py.fixture|red|rule (d) unparsed|an unparseable py file with an allocation token is reported unparsed, not skipped" \
  "d-bad-py-escape-no-reason.py.fixture|red|with no reason|row 8: a bare marker with no reason is RED (py)" \
  "d-bad-ts-escape-no-reason.ts.fixture|red|with no reason|row 8: a bare marker with no reason is RED (ts)" \
  "e-bad-sh-literal-base.sh.fixture|red|rule (e) hard-coded temp base|row 3: mktemp -d /var/tmp/x.XXXXXX (and -p /tmp) in a .sh" \
  "e-bad-sh-escape-no-reason.sh.fixture|red|with no reason|row 8: a bare marker with no reason is RED (rule (e), sh)" \
  "e-bad-py-literal-base.py.fixture|red|rule (e) hard-coded temp base|rule (e): mkdtemp(dir=\"/var/tmp\") in py" \
  "e-bad-ts-literal-base.ts.fixture|red|rule (e) hard-coded temp base|rule (e): mkdtempSync(\"/tmp/x-\") in ts" \
  "e-bad-ts-join-literal.ts.fixture|red|rule (e) hard-coded temp base|rule (e): mkdtempSync(join(\"/var/tmp\", ...)) in ts" \
  "d-good-ts-afterall-rmsync.ts.fixture|pass||row 7: mkdtempSync + afterAll(() => rmSync(...)) is clean (must-PASS)" \
  "d-good-ts-await-rm.ts.fixture|pass||await mkdtemp + finally await rm is clean" \
  "d-good-py-mkdtemp-rmtree.py.fixture|pass||py mkdtemp + rmtree in finally is clean" \
  "d-good-py-mkdtemp-alias-rmtree.py.fixture|pass||py mkdtemp + atexit.register(aliased rmtree) is clean" \
  "d-good-py-mkdtemp-tempdir-ctx.py.fixture|pass||py allocation inside a TemporaryDirectory is clean" \
  "d-good-py-namedtempfile-default.py.fixture|pass||NamedTemporaryFile with default delete is not an allocation" \
  "d-good-py-escape-hatch.py.fixture|pass||row 8: reason-carrying escape hatch (py)" \
  "d-good-ts-escape-hatch.ts.fixture|pass||row 8: reason-carrying escape hatch (ts)" \
  "e-good-sh-escape-hatch.sh.fixture|pass||row 8: reason-carrying escape hatch (rule (e), sh)" \
  "d-good-py-alloc-in-comment-string.py.fixture|pass||row 10: allocation name only in a py comment/string/docstring is not an allocation" \
  "d-good-ts-alloc-in-comment-string.ts.fixture|pass||row 10: allocation name only in a ts comment/string/template/regex is not an allocation" \
  "d-good-py-syntax-error-no-alloc.py.fixture|pass||an unparseable py file with no allocation token is tolerated, never a crash" \
  "e-good-sh-tmpdir-default.sh.fixture|pass||\${TMPDIR:-/tmp} is not a literal base" \
  "e-good-py-gettempdir.py.fixture|pass||tempfile.gettempdir() is not a literal base" \
  "e-good-ts-tmpdir.ts.fixture|pass||os.tmpdir() is not a literal base"
do
  IFS='|' read -r fx expect needle label <<< "$case"
  mkrepo "added-${fx%.fixture}" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
  # A distinct name: the canonical clean fixtures are also the base tree, so adding one
  # under its own name would be a no-op commit rather than an ADDED path.
  rel="src/added-${fx%.fixture}"
  if ! add_commit "$fx" "$rel" >/dev/null 2>&1; then no "$label (builder could not land $fx as an ADDED path)"; continue; fi
  lint_in_repo
  if [[ "$expect" == "red" ]]; then
    if [[ "$LRC" == "1" ]] && grep -qF "$rel" <<< "$LERR" && grep -qF "$needle" <<< "$LERR"; then
      ok "$label"
    else
      no "$label (rc=$LRC; wanted '$needle' naming $rel: ${LERR:0:240})"
    fi
  else
    if [[ "$LRC" == "0" ]]; then ok "$label"; else no "$label (expected rc 0, got $LRC: ${LERR:0:240})"; fi
  fi
done

# --- Row 2: a second offending file after a compliant one. The walk must not stop at the
# first member: BOTH bad files are named.
mkrepo "row2" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
add_commit "d-good-py-mkdtemp-alias-rmtree.py.fixture" >/dev/null 2>&1
add_commit "d-bad-py-mkdtemp-no-cleanup.py.fixture" >/dev/null 2>&1
add_commit "d-bad-py-mkdtemp-no-cleanup-2.py.fixture" >/dev/null 2>&1
lint_in_repo
if [[ "$LRC" == "1" ]] && grep -qF "src/d-bad-py-mkdtemp-no-cleanup.py" <<< "$LERR" \
   && grep -qF "src/d-bad-py-mkdtemp-no-cleanup-2.py" <<< "$LERR" \
   && ! grep -qF "d-good-py-mkdtemp-alias-rmtree" <<< "$LERR"; then
  ok "row 2: a second offending file after a compliant one is also reported (walk does not stop at the first)"
else
  no "row 2: expected both bad files and not the compliant one (rc=$LRC: ${LERR:0:300})"
fi

# --- ADDED-vs-PRESENT control (harness H1's other half). The very same offending files,
# present in the BASE instead of added, must scan clean: that is what proves the arms above
# passed because the line was ADDED, not merely because the file exists. Without it a lint
# that flagged every file it saw would satisfy every RED arm above.
for fx in d-bad-py-mkdtemp-no-cleanup.py.fixture d-bad-ts-mkdtemp-no-rm.ts.fixture e-bad-sh-literal-base.sh.fixture; do
  mkrepo "present-${fx%.fixture}" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$fx"
  lint_in_repo
  if [[ "$LRC" == "0" ]]; then
    ok "present-in-base control: $fx already on the base is not re-litigated (added-line scoped)"
  else
    no "present-in-base control: $fx on the base was flagged (rc=$LRC: ${LERR:0:200})"
  fi
  # Touched-but-not-added: the file IS in the diff (changed set) but its offending line is
  # not an added line. Scoping to touched FILES instead of added LINES is the exact defect
  # rule (c)'s docstring records -- an incidental edit would demand paying off old debt.
  cmt="#"; [[ "$fx" == *.ts.fixture ]] && cmt="//"
  printf '\n%s touched by an unrelated edit\n' "$cmt" >> "$REPO/src/${fx%.fixture}"
  g commit -q -am "touch"
  g diff --name-only main...HEAD | grep -qxF -- "src/${fx%.fixture}" || no "touch control: $fx is not in the diff"
  lint_in_repo
  if [[ "$LRC" == "0" ]]; then
    ok "touched-not-added control: an unrelated edit to $fx does not make its old allocation an entrant"
  else
    no "touched-not-added control: $fx flagged after an unrelated edit (rc=$LRC: ${LERR:0:200})"
  fi
done

# --- Harness H1: make the builder's `git add` (and commit) silently do nothing. The suite
# must notice the offending file never became an added path, instead of linting an unchanged
# tree and calling the resulting rc 0 a verdict.
mkdir -p "$T/shim-noadd"
cat > "$T/shim-noadd/git" <<'SHIM'
#!/bin/sh
for a in "$@"; do
  case "$a" in add|commit) exit 0 ;; esac
done
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$T/shim-noadd/git"
mkrepo "h1" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
h1_rc=0
PATH="$T/shim-noadd:$PATH" add_commit "d-bad-py-mkdtemp-no-cleanup.py.fixture" >/dev/null 2>&1 || h1_rc=$?
if [[ "$h1_rc" != "0" ]]; then
  ok "harness H1: a builder whose git add silently fails is detected (the ADDED assertion is not vacuous)"
else
  no "harness H1: builder reported success although nothing was added"
fi

# --- Harness H2: the canonical clean tree and a second clean tree with DIFFERENT cleanup
# spellings both pass, ADDED as new files (so the arm exercises the added-line path, not an
# empty diff).
mkrepo "h2-canonical" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
add_commit "d-good-py-mkdtemp-rmtree.py.fixture" "src/clean2.py" >/dev/null 2>&1
add_commit "d-good-ts-afterall-rmsync.ts.fixture" "src/clean2.ts" >/dev/null 2>&1
lint_in_repo; h2a=$LRC; h2a_err="$LERR"
mkrepo "h2-alt" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
add_commit "d-good-py-mkdtemp-alias-rmtree.py.fixture" "src/alt.py" >/dev/null 2>&1
add_commit "d-good-ts-await-rm.ts.fixture" "src/alt.ts" >/dev/null 2>&1
add_commit "e-good-sh-tmpdir-default.sh.fixture" "src/alt.sh" >/dev/null 2>&1
lint_in_repo
if [[ "$h2a" == "0" && "$LRC" == "0" ]]; then
  ok "harness H2: the canonical clean tree and a differently-spelled clean tree both PASS"
else
  no "harness H2: canonical rc=$h2a (${h2a_err:0:120}); alternate rc=$LRC (${LERR:0:120})"
fi

# --- Structural test exclusion: derived from a registered runner root, never from the name.
# bunfig `preload` entry that exists makes pkg/ a TS root; conftest.py makes tests/ a py root.
mkrepo "excl" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
mkdir -p "$REPO/pkg" "$REPO/tests" "$REPO/other" "$REPO/scripts2"
printf 'export {};\n' > "$REPO/pkg/setup.ts"
printf '[test]\npreload = ["./setup.ts"]\n' > "$REPO/pkg/bunfig.toml"
printf 'def pytest_configure(config):\n    pass\n' > "$REPO/tests/conftest.py"
g add -A; g commit -q -m "registry"
add_commit "d-bad-ts-mkdtemp-no-rm.ts.fixture" "pkg/x.test.ts" >/dev/null 2>&1
add_commit "d-bad-py-mkdtemp-no-cleanup.py.fixture" "tests/test_alloc.py" >/dev/null 2>&1
lint_in_repo
if [[ "$LRC" == "0" ]]; then
  ok "test-shaped files under a registered runner root are structurally excluded (pkg/*.test.ts, tests/test_*.py)"
else
  no "runner-owned test files were flagged (rc=$LRC: ${LERR:0:240})"
fi
lint_in_repo_out --census-detail
if grep -qx "excluded-tests: 2" <<< "$LERR" && grep -qx "rule-d: 0" <<< "$LERR"; then
  ok "excluded tests are COUNTED separately (excluded-tests: 2), not silently dropped"
else
  no "census-detail did not report the exclusion: ${LERR:0:240}"
fi
add_commit "d-bad-ts-mkdtemp-no-rm.ts.fixture" "other/x.test.ts" >/dev/null 2>&1
lint_in_repo
if [[ "$LRC" == "1" ]] && grep -qF "other/x.test.ts" <<< "$LERR" && ! grep -qF "pkg/x.test.ts" <<< "$LERR"; then
  ok "a test-NAMED file outside every runner root is NOT exempt (the name alone never excuses)"
else
  no "other/x.test.ts outside any root should be flagged, pkg/x.test.ts not (rc=$LRC: ${LERR:0:240})"
fi
add_commit "d-bad-py-mkdtemp-no-cleanup.py.fixture" "scripts2/test_alloc.py" >/dev/null 2>&1
lint_in_repo
if [[ "$LRC" == "1" ]] && grep -qF "scripts2/test_alloc.py" <<< "$LERR"; then
  ok "a test_*.py outside every conftest root is NOT exempt (python arm)"
else
  no "scripts2/test_alloc.py should be flagged (rc=$LRC: ${LERR:0:240})"
fi

# `--census` keeps its original one-integer shell contract (the CI/ratchet interface).
mkrepo "census-contract" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "bad-mktemp-no-trap.sh.fixture"
lint_in_repo_out --census
if [[ "$LRC" == "0" && "$LERR" == "1" ]]; then
  ok "--census still prints exactly the shell class-b count (1 for this repo)"
else
  no "--census contract changed (rc=$LRC out='${LERR:0:80}')"
fi

# --- Row 5: the file walk returns zero files. "Nothing checked" must be RED in every mode
# that walks the tree. A `git` that lists nothing and exits 0 is the strictly harder case
# than one that errors -- it is the failure that reads as clean.
mkdir -p "$T/shim-empty"
cat > "$T/shim-empty/git" <<'SHIM'
#!/bin/sh
case "$1" in ls-files|ls-tree) exit 0 ;; esac
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$T/shim-empty/git"
mkrepo "row5" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
for mode in "" "--census" "--census-detail" "--check-highwater"; do
  r5=0
  r5_err="$(cd "$REPO" && PATH="$T/shim-empty:$PATH" "${GENV[@]}" python3 scripts/lint-trap-tempfile-ownership.py $mode 2>&1 >/dev/null)" || r5=$?
  if [[ "$r5" == "2" ]] && grep -qF "returned 0" <<< "$r5_err"; then
    ok "row 5: an empty file walk is RED in mode '${mode:-default scan}' (floor), rc 2"
  else
    no "row 5: empty walk in mode '${mode:-default scan}' did not fail the floor (rc=$r5: ${r5_err:0:160})"
  fi
done
r5=0
python3 "$LINT" "$FIX/does-not-exist.py.fixture" >/dev/null 2>&1 || r5=$?
if [[ "$r5" == "2" ]]; then ok "row 5: explicit paths that name no file are RED, not an empty pass"; else no "row 5: nonexistent explicit path returned rc=$r5"; fi

# --- Row 6: the highwater is compared against the MERGE-BASE copy. Population in these
# repos: one accepted un-cleaned py file (src/legacy.py) => rule-d census 1.
LEGACY="d-bad-py-mkdtemp-no-cleanup.py.fixture"
hw_set() { printf 'rule-d: %s\nrule-e: %s\n' "$1" "$2" > "${REPO:?}/scripts/lint-trap-tempfile-ownership-tspy.highwater"; }

# 6a: lower the ceiling below the population without removing a member.
mkrepo "row6a" 0 1 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
hw_set 0 0; g commit -q -am "lower"
lint_in_repo --check-highwater
if [[ "$LRC" == "1" ]]; then ok "row 6: lowering the highwater below the census (no member removed) is RED"; else no "row 6a: rc=$LRC ${LERR:0:200}"; fi

# 6b: lower WITHIN slack, no member removed. The working-copy ceiling still covers the live
# count, so only the merge-base comparison can see it. Left UNCOMMITTED on purpose.
mkrepo "row6b" 0 3 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
hw_set 2 0
lint_in_repo --check-highwater
if [[ "$LRC" == "1" ]] && grep -qF "moved 3 -> 2" <<< "$LERR"; then
  ok "row 6: lowering within slack without removing a member is RED (merge-base copy, not the working copy)"
else
  no "row 6b: a slack-lowering edit slipped past the merge-base comparison (rc=$LRC: ${LERR:0:240})"
fi

# 6c: raise the ceiling with no new member.
mkrepo "row6c" 0 1 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
hw_set 2 0; g commit -q -am "raise"
lint_in_repo --check-highwater
if [[ "$LRC" == "1" ]] && grep -qF "moved 1 -> 2" <<< "$LERR"; then
  ok "row 6: raising the highwater with no added population member is RED"
else
  no "row 6c: a free raise slipped through (rc=$LRC: ${LERR:0:240})"
fi

# 6d (must-PASS): the member really left, and the ceiling dropped by exactly that much.
mkrepo "row6d" 0 1 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
g rm -q -f -- "src/${LEGACY%.fixture}"; hw_set 0 0; g commit -q -am "paid off"
lint_in_repo --check-highwater
if [[ "$LRC" == "0" ]]; then ok "row 6 must-PASS: removing a member and lowering the highwater by exactly one is accepted"; else no "row 6d: ${LERR:0:240}"; fi

# 6e (must-PASS): snapping a slack ceiling down to the measured count is the ratchet itself.
mkrepo "row6e" 0 3 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
hw_set 1 0; g commit -q -am "snap"
lint_in_repo --check-highwater
if [[ "$LRC" == "0" ]]; then ok "row 6 must-PASS: snapping the ceiling to the measured census is accepted"; else no "row 6e: ${LERR:0:240}"; fi

# 6f (must-PASS): a deliberate entrant raises the ceiling by exactly one.
mkrepo "row6f" 0 1 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
add_commit "d-bad-py-mkdtemp-no-cleanup-2.py.fixture" >/dev/null 2>&1
hw_set 2 0; g commit -q -am "deliberate raise"
lint_in_repo --check-highwater
if [[ "$LRC" == "0" ]]; then ok "row 6 must-PASS: one added member with the ceiling raised by exactly one is accepted"; else no "row 6f: ${LERR:0:240}"; fi

# 6g: growth with NO highwater edit is RED (the original ratchet), for rule (d) and (e) both.
mkrepo "row6g" 0 1 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS" "$LEGACY"
add_commit "d-bad-py-mkdtemp-no-cleanup-2.py.fixture" >/dev/null 2>&1
lint_in_repo --check-highwater
if [[ "$LRC" == "1" ]] && grep -qF "rule (d)" <<< "$LERR"; then ok "row 6: census growth past the rule (d) ceiling is RED"; else no "row 6g: ${LERR:0:200}"; fi
mkrepo "row6h" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
add_commit "e-bad-ts-literal-base.ts.fixture" >/dev/null 2>&1
lint_in_repo --check-highwater
if [[ "$LRC" == "1" ]] && grep -qF "rule (e)" <<< "$LERR"; then ok "row 6: census growth past the rule (e) ceiling is RED"; else no "row 6h: ${LERR:0:200}"; fi

# =======================================================================================
# Review-fix batch (PR 9339). ONE fixture repo, every fixture ADDED in one commit, ONE lint run:
# each file is reported (or not) independently, so a per-file verdict needs no per-file repo.
# That keeps ~40 arms at ~2 s instead of ~40 s.
#   * owner-marker vocabulary (a CALL to a real writer, never a bare name / string / helper)
#   * `git -z`: a path with a space or a non-ASCII byte must still reach rules (d)/(e)
#   * extension-table mutants: .bash (SHELL_E_EXT), .mjs/.js (TS_EXT), bare /tmp (LIT_BASE_SH)
#   * rule (e) is restricted to a base that BEGINS with /tmp or /var/tmp
#   * KNOWN LIMITATIONS: today's behaviour, pinned so a future change shows up as a diff
# Row: fixture|path under src/|expect (red|pass)|needle for red|label
# =======================================================================================
D_NEEDLE="rule (d) allocation with no cleanup"
E_NEEDLE="rule (e) hard-coded temp base"
KL="KNOWN LIMITATION (documents today's behaviour; flip it deliberately if tightened)"
BATCH=(
  "d-good-ts-write-scratch-marker.ts.fixture|b-marker-write.ts|pass||owner marker: a TS file calling writeScratchMarker(d) after mkdtempSync is owned"
  "d-good-ts-ensure-scratch-session.ts.fixture|b-marker-ensure.ts|pass||owner marker: a TS file calling ensureScratchSession() is owned"
  "d-good-py-write-scratch-marker.py.fixture|b-marker-write.py|pass||owner marker: a py file calling write_scratch_marker(d) after mkdtemp is owned"
  "d-bad-ts-own-markowned.ts.fixture|b-own-markowned.ts|red|$D_NEEDLE|owner marker: a file defining and calling its OWN markOwned() is not owned"
  "d-bad-ts-local-writescratchmarker-def.ts.fixture|b-own-writer-def.ts|red|$D_NEEDLE|owner marker: defining the writer's name locally and calling it is not owned"
  "d-bad-ts-session-root-identifier.ts.fixture|b-session-root.ts|red|$D_NEEDLE|owner marker: the SOLEUR_SCRATCH_SESSION_ROOT identifier alone is not owned (ts)"
  "d-bad-py-print-owned-marker.py.fixture|b-print-owned.py|red|$D_NEEDLE|owner marker: print(\".soleur-owned x\") is not owned (py)"
  "d-bad-py-local-ensure-def.py.fixture|b-own-ensure-def.py|red|$D_NEEDLE|owner marker: a py def ensure_scratch_session + call is not owned"
  "d-bad-py-session-root-string.py.fixture|b-session-root.py|red|$D_NEEDLE|owner marker: the SOLEUR_SCRATCH_SESSION_ROOT string alone is not owned (py)"
  "d-bad-ts-mkdtemp-no-rm.ts.fixture|café.ts|red|$D_NEEDLE|git -z: a non-ASCII path (café.ts) still reaches rule (d)"
  "d-bad-ts-mkdtemp-no-rm.ts.fixture|leaky file.ts|red|$D_NEEDLE|git -z: a path with a space (leaky file.ts) still reaches rule (d)"
  "e-bad-sh-bare-tmp-only.sh.fixture|b-bare-tmp-only.sh|red|$E_NEEDLE|rule (e): a bare /tmp base with NO /var/tmp on the line (LIT_BASE_SH alternative)"
  "e-bad-bash-literal-base.bash.fixture|b-literal-base.bash|red|$E_NEEDLE|rule (e): a .bash file is in scope (SHELL_E_EXT)"
  "d-bad-mjs-mkdtemp-no-rm.mjs.fixture|b-alloc.mjs|red|$D_NEEDLE|rule (d): a .mjs file is in scope (TS_EXT)"
  "d-bad-js-mkdtemp-no-rm.js.fixture|b-alloc.js|red|$D_NEEDLE|rule (d): a .js file is in scope (TS_EXT)"
  "d-bad-ts-alias-import.ts.fixture|b-alias-import.ts|red|$D_NEEDLE|rule (d): import { mkdtempSync as mk } is an allocation"
  "d-good-ts-alias-clean.ts.fixture|b-alias-clean.ts|pass||rule (d): an aliased allocation AND an aliased removal (rmSync as wipe) is clean"
  "d-bad-ts-lexer-postfix-increment.ts.fixture|b-postfix-incr.ts|red|$D_NEEDLE|lexer: \`i++ / 2\` is a division, so the allocation after it is still seen"
  "d-good-py-pytest-tmp-path-factory.py.fixture|b-tmp-path-factory.py|pass||rule (d): pytest tmp_path_factory.mktemp() is runner-managed, not an allocation"
  "e-good-ts-template-root-tmp.ts.fixture|b-template-root-tmp.ts|pass||rule (e): mkdtempSync(\`\${root}/tmp/work-\`) is not a literal base"
  "e-good-ts-join-root-tmp.ts.fixture|b-join-root-tmp.ts|pass||rule (e): join(root, \"/tmp/work-\") is not a literal base"
  "e-good-py-repo-relative-tmp.py.fixture|b-repo-relative-tmp.py|pass||rule (e): mkdtemp(dir=f\"{ROOT}/tmp/x\") (repo-relative tmp/) is not a literal base"
  "e-good-sh-repo-relative-tmp.sh.fixture|b-repo-relative-tmp.sh|pass||rule (e): mktemp -d \"\$ROOT/tmp/x\" (repo-relative tmp/) is not a literal base"
  "e-bad-ts-template-literal-base.ts.fixture|b-template-base.ts|red|$E_NEEDLE|rule (e): a template literal BEGINNING with /tmp is a literal base"
  "e-bad-py-fstring-base.py.fixture|b-fstring-base.py|red|$E_NEEDLE|rule (e): dir=f\"/tmp/{name}\" is a literal base"
  "e-bad-py-positional-join.py.fixture|b-positional-join.py|red|$E_NEEDLE|rule (e): a positional dir=os.path.join(\"/var/tmp\", ...) is a literal base"
  "kl-py-two-allocs-one-cleaned.py.fixture|kl-two-allocs.py|pass||$KL: two allocations, one removal (file-scoped cleanup)"
  "kl-ts-unrelated-rm.ts.fixture|kl-unrelated-rm.ts|pass||$KL: an unrelated .rm() on another object satisfies cleanup (name-scoped)"
  "kl-py-unrelated-os-remove.py.fixture|kl-unrelated-remove.py|pass||$KL: os.remove(cfg) of an unrelated path satisfies cleanup"
  "kl-py-delete-false-kwargs.py.fixture|kl-delete-kwargs.py|pass||$KL: NamedTemporaryFile(**{'delete': False}) is not seen"
  "kl-ts-variable-held-tmp-base.ts.fixture|kl-variable-base.ts|pass||$KL: a /tmp base routed through a variable is not seen by rule (e)"
)
mkrepo "batch-new" 0 0 0 "$CLEAN_SH" "$CLEAN_PY" "$CLEAN_TS"
for row in "${BATCH[@]}"; do
  IFS='|' read -r fx rel _x _n _l <<< "$row"
  cp "$FIX/$fx" "$REPO/src/$rel"
done
g add -A
g commit -q -m "batch"
g diff --name-only -z main...HEAD > "$T/batch-added.z"
lint_in_repo
if [[ "$LRC" == "1" ]]; then ok "review-fix batch: the shared lint run found violations (rc 1), so the per-file verdicts below are not vacuous"; else no "review-fix batch: rc=$LRC (${LERR:0:200})"; fi
for row in "${BATCH[@]}"; do
  IFS='|' read -r fx rel expect needle label <<< "$row"
  if ! grep -qzxF -- "src/$rel" "$T/batch-added.z"; then no "$label (src/$rel is NOT an added path)"; continue; fi
  hit="$(grep -F -- "src/$rel:" <<< "$LERR" || true)"
  if [[ "$expect" == "red" ]]; then
    if grep -qF -- "$needle" <<< "$hit"; then ok "$label"; else no "$label (src/$rel not flagged with '$needle': ${LERR:0:200})"; fi
  else
    if [[ -z "$hit" ]]; then ok "$label"; else no "$label (src/$rel was flagged: ${hit:0:200})"; fi
  fi
done

# --- Lexer cost guard: a 12 KB adversarial file must lint in < 2 s (the regex-literal scan
# was quadratic: `(/[` repeated took ~11 s of CPU). Each input carries a real allocation token
# so the lexer RUNS (a file with no allocation token is skipped before lexing). Also: deeply
# nested templates must not crash the recursive scanner (a RecursionError traceback). Measured
# as the CHILD'S CPU TIME, not wall time, so a loaded CI box cannot flake it, and run from the
# small fixture repo so the walk of this checkout's ~3k files is not part of the budget.
mkdir -p "$T/adv"
while read -r adv a_rc a_cpu a_tb a_size; do
  if [[ "$a_rc" =~ ^[01]$ && "$a_tb" == "no-traceback" ]] && (( a_cpu < 2000 )); then
    ok "lexer cost guard: $adv ($a_size bytes) lints in ${a_cpu} ms CPU (< 2000), no crash"
  else
    no "lexer cost guard: $adv rc=$a_rc cpu=${a_cpu} ms $a_tb"
  fi
done < <(python3 - "$REPO/scripts/lint-trap-tempfile-ownership.py" "$T/adv" <<'PYADV'
import os, resource, subprocess, sys
lint, d = sys.argv[1], sys.argv[2]
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
cases = {
    "redos-regex": "mkdtempSync(1);\n" + "(/[" * 4000,
    "redos-parens": "mkdtemp(" * 1500,
    "nested-templates": "mkdtempSync(1);\n" + "`${" * 3000,
}
for name, body in cases.items():
    path = f"{d}/{name}.ts"
    with open(path, "w") as fh:
        fh.write(body)
    b = resource.getrusage(resource.RUSAGE_CHILDREN)
    p = subprocess.run(["python3", lint, path], capture_output=True, text=True, env=env, timeout=120)
    a = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = int(((a.ru_utime - b.ru_utime) + (a.ru_stime - b.ru_stime)) * 1000)
    print(name, p.returncode, cpu, "traceback" if "Traceback" in p.stderr else "no-traceback", len(body))
PYADV
)

# --- Case floor, reported WITHOUT the pass/fail helpers. Deleting arms (the d/e RED rows,
# or the whole batch) must not read as a green suite: the count is pinned exactly. Raise it
# in lockstep when an arm is added on purpose.
EXPECTED_CASES=114
echo ""
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
if (( PASS + FAIL != EXPECTED_CASES )); then
  printf 'FLOOR BREACH: ran %d cases, expected exactly %d -- an arm was deleted or added without moving the floor\n' \
    "$((PASS + FAIL))" "$EXPECTED_CASES" >&2
  exit 1
fi
(( FAIL == 0 )) || exit 1
