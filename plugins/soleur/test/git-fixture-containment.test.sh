#!/usr/bin/env bash
# Containment regression test for #7822 / #7835 — the shell counterpart of Guard 1.
#
# THE INCIDENT. Under lefthook, git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE to every hook
# as ABSOLUTE paths. Those beat a subprocess's working directory AND `git -C`, so a fixture's
# `git init` initialises nothing and its commits land on the caller's live branch. #7835 records
# exactly that: a rewritten branch tip and a wiped index.
#
# TWO LAYERS, AND CONFLATING THEM IS WHAT MAKES THIS SUITE MEANINGLESS.
#
#   Refusal    — the test-helpers.sh prelude. Detects the nine location variables and exits 97.
#                It NEVER scrubs; its own comment says "This ABORTS rather than unsetting."
#   Containment— the `unset GIT_DIR … GIT_EXEC_PATH` line in scripts/test-all.sh. Removes the
#                variables before any suite runs. It detects nothing; it is silent when it works.
#
# SOLEUR_GIT_TRIPWIRE_ALLOW=1 disarms REFUSAL by announcing and falling through — it does not
# scrub. So a suite run with ALLOW=1 and a hostile environment keeps that environment fully
# intact, which is precisely what makes the containment arm below a test of the OTHER layer.
#
# WHY THE ORACLE INCLUDES THE CHILD'S EXIT CODE. A swept suite sources test-helpers.sh, so under a
# hostile GIT_DIR the tripwire fires and the child exits 97 BEFORE running any git write. The
# victim is then trivially unchanged and a state-only assertion passes — and keeps passing if an
# entry point's `unset` is deleted, which is the single most likely real regression. Asserting
# only victim state certifies "contained OR refused to run". Both arms therefore pin rc.
#
# WHY THE HOSTILE VALUE IS THE VICTIM. A hostile GIT_DIR pointing somewhere neutral (/tmp/hostile)
# is correct for the refusal arm, which only needs the tripwire to see SOME location variable. It
# is fatal for the containment arm: if the hostile value does not point at the victim, the
# victim's state cannot move whether containment holds or not, and the arm cannot be driven red.
#
# THIS FILE MUST NOT SOURCE test-helpers.sh. It controls the tripwire, so sourcing it would abort
# this suite in the exact arms it exists to exercise. git-tripwire.test.sh carries the same
# constraint and states it in its own header.
#
# Reached by scripts/test-all.sh through its existing plugins/soleur/test/*.test.sh glob — BY
# NAMING, not by registration. scripts/test-all.sh is a do-not-touch path and is never edited,
# invoked or nested by this suite.
#
# Run: bash plugins/soleur/test/git-fixture-containment.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPERS="$SCRIPT_DIR/test-helpers.sh"
RUNNER_SRC="$REPO_ROOT/scripts/test-all.sh"

# Shared constant with four existing copies (test-helpers.sh, git-tripwire.test.sh's TRIPWIRE_RC,
# AC17, T6). Bound once here rather than inlined, mirroring git-tripwire.test.sh.
readonly TRIPWIRE_RC=97

PASS=0
FAIL=0
ASSERTED=0
ck() { ASSERTED=$((ASSERTED + 1)); }
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "git-fixture-containment.test.sh"

# --- Instrument self-test. Driven, not grepped. ------------------------------------------------
# A suite whose only gate is a failure counter exits 0 having asserted nothing. Both counters must
# be observed to move, because a fail() that credits PASS keeps every literal a grep could look
# for while making this suite structurally unable to report a defect.
HARNESS_OK=0
_h_p=$PASS
_h_f=$FAIL
pass "instrument self-test — expected, reconciled immediately" >/dev/null
fail "instrument self-test — expected, reconciled immediately" 2>/dev/null
if [[ $PASS -eq $((_h_p + 1)) && $FAIL -eq $((_h_f + 1)) ]]; then
  HARNESS_OK=1
fi
PASS=$_h_p
FAIL=$_h_f

TMP_ROOT=$(mktemp -d -t gitfixcontain.XXXXXXXX) || { echo "FATAL: no scratch root" >&2; exit 2; }
cleanup() { [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"; }
trap cleanup EXIT INT TERM HUP

# --- The victim. A synthesized fixture, never the developer's worktree. -------------------------
VICTIM="$TMP_ROOT/victim"
mkdir -p "$VICTIM"
git -C "$VICTIM" init -q -b main
git -C "$VICTIM" config user.email victim@fixture.test
git -C "$VICTIM" config user.name victim
git -C "$VICTIM" config commit.gpgsign false
printf 'seed\n' > "$VICTIM/seed.txt"
git -C "$VICTIM" add -A
git -C "$VICTIM" commit -q -m "victim seed"

# The hostile environment IS the victim — see the header. This is the shape #7835 records.
HOSTILE_GIT_DIR="$VICTIM/.git"
HOSTILE_WORK_TREE="$VICTIM"
HOSTILE_INDEX="$VICTIM/.git/index"

# --- Preconditions. Without these every arm below is satisfiable by an accident. -----------------
ck
if [[ "$VICTIM" == /* ]] && [[ "$VICTIM" != "$PWD"* ]]; then
  pass "precondition: the victim is an absolute path outside \$PWD"
else
  fail "precondition: victim '$VICTIM' is relative or inside \$PWD — a breach would hit real work"
fi

ck
_vgd=$(git -C "$VICTIM" rev-parse --absolute-git-dir 2>&1)
case "$_vgd" in
  "$VICTIM"/*) pass "precondition: the victim resolves to its OWN git dir" ;;
  *)           fail "precondition: victim resolved to '$_vgd', outside the fixture" ;;
esac

ck
if [[ -f "$HELPERS" ]] && grep -qE "exit ${TRIPWIRE_RC}\b" "$HELPERS"; then
  pass "precondition: test-helpers.sh carries the exit ${TRIPWIRE_RC} tripwire"
else
  fail "precondition: test-helpers.sh has no exit ${TRIPWIRE_RC} — the refusal arm is meaningless"
fi

# --- The scrub line, DERIVED from scripts/test-all.sh, never transcribed. ------------------------
# A transcribed copy drifts silently the moment the real line gains a variable, and this suite
# would then certify a scrub the runner no longer performs. Derivation is what keeps the sandbox
# honest. scripts/test-all.sh is READ here and never written, invoked or nested.
SCRUB_LINE=$(grep -m1 -E '^unset GIT_DIR ' "$RUNNER_SRC" || true)

ck
if [[ -n "$SCRUB_LINE" ]] && grep -qE '(^|[[:space:]])GIT_INDEX_FILE([[:space:]]|$)' <<<"$SCRUB_LINE"; then
  pass "the scrub line was derived from scripts/test-all.sh and names GIT_INDEX_FILE"
else
  fail "could not derive the scrub line from $RUNNER_SRC (got: ${SCRUB_LINE:-<empty>})"
fi

# --- Two synthesized children. Real swept suites are deliberately NOT used: pointing these arms
# at gitleaks-merge-commit would couple a containment proof to a 27-assertion battery and make this
# verdict track unrelated churn. Two, so a per-member regression has a second member to break.
CHILDREN=()
for n in 1 2; do
  child="$TMP_ROOT/child-$n.sh"
  cat > "$child" <<CHILDEOF
#!/usr/bin/env bash
set -uo pipefail
# Sources the real helper: that is what makes the refusal arm a test of the shipped tripwire.
source "$HELPERS"
d=\$(mktemp -d -t containchild$n.XXXXXXXX) || exit 2
git -C "\$d" init -q
git -C "\$d" config user.email child@fixture.test
git -C "\$d" config user.name child
git -C "\$d" config commit.gpgsign false
printf 'child $n\\n' > "\$d/child-$n.txt"
git -C "\$d" add -A
# --allow-empty is load-bearing, not laziness. A breach retargets this commit at the VICTIM, whose
# work tree does not contain \$d/child-$n.txt -- so 'git add -A' stages nothing there and a plain
# commit would exit 1 with "nothing to commit" WITHOUT moving HEAD. The breach would then be
# invisible to the oracle and the containment arm would pass vacuously. --allow-empty makes the
# breach deterministic: HEAD moves whenever this commit lands on the wrong repository.
git -C "\$d" commit -q --allow-empty -m "child $n wrote"
rm -rf "\$d"
exit 0
CHILDEOF
  CHILDREN+=("$child")
done

# --- The sandbox runner: a COPY of the derived scrub line, then the child. -----------------------
# scripts/test-all.sh cannot be the child's invocation path — it takes only all|webplat|bun|
# scripts|infra, has no single-suite mode, refuses rc 4 under SOLEUR_SUBAGENT=1, and nesting it
# inside its own run is absurd. Invoking a swept suite DIRECTLY means no scrub exists anywhere in
# the path, so the containment arm would be red from birth. Hence this copy.
# --- assert_fixture_dir: a BYTE-EXACT inline copy of the canonical body. ------------------------
# This file cannot source test-helpers.sh (it controls the tripwire -- see the header), and the P1b
# scanner reports a row for write_runner's redirect operand, so the guard is carried inline. The
# copy JOINS fixture-dir-operand-assert.test.sh's repo-wide drift corpus (git ls-files '*.sh') and
# must stay byte-identical to test-helpers.sh's body; it was extracted with the same awk that guard
# uses, not retyped. The call sits at the ENCLOSING FUNCTION HEAD because the P1b window starts
# there -- a single call at file scope would not cover a helper.
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

write_runner() { # <path> <with-scrub:0|1>
  local path="$1" with="$2"
  assert_fixture_dir "$path"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -uo pipefail\n'
    [[ "$with" == "1" ]] && printf '%s\n' "$SCRUB_LINE"
    printf 'exec bash "$1"\n'
  } > "$path"
}
RUNNER_SCRUBBED="$TMP_ROOT/runner-scrubbed.sh"
RUNNER_BARE="$TMP_ROOT/runner-bare.sh"
write_runner "$RUNNER_SCRUBBED" 1
write_runner "$RUNNER_BARE" 0

victim_quad() { # -> "<head>|<refs>|<staged>|<loose-objects>"
  local head refs staged objects
  head=$(git -C "$VICTIM" rev-parse HEAD 2>&1)
  refs=$(git -C "$VICTIM" show-ref 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
  staged=$(git -C "$VICTIM" diff --cached --name-only 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
  objects=$(find "$VICTIM/.git/objects" -type f 2>/dev/null | wc -l | tr -d ' ')
  printf '%s|%s|%s|%s\n' "$head" "$refs" "$staged" "$objects"
}

# A QUADRUPLE, not HEAD alone. Two independent measured reasons: with GIT_DIR scrubbed an absolute
# GIT_INDEX_FILE still retargets `git add` while HEAD stays put (hence refs + staged), and
# GIT_COMMON_DIR / GIT_OBJECT_DIRECTORY write the child's objects into the victim's object store
# while HEAD, refs and the index stay byte-identical — a real breach that a three-component oracle
# certifies as contained. The oracle reads git state, never the child's stderr: under ALLOW=1 the
# helper prints a DISARMED line on every containment invocation.

run_child() { # <runner> <child> <allow:0|1> [shape:location|objects] -> sets CHILD_RC
  local runner="$1" child="$2" allow="$3" shape="${4:-location}"
  local -a env_args=()
  case "$shape" in
    location)
      env_args+=(
        "GIT_DIR=$HOSTILE_GIT_DIR"
        "GIT_WORK_TREE=$HOSTILE_WORK_TREE"
        "GIT_INDEX_FILE=$HOSTILE_INDEX"
      )
      ;;
    objects)
      # The M-14 shape: the child keeps its OWN repository, so HEAD, refs and the index stay
      # byte-identical on the victim -- only its object store grows. A three-component oracle
      # certifies this as contained, which is why the fourth component exists.
      env_args+=("GIT_OBJECT_DIRECTORY=$VICTIM/.git/objects")
      ;;
    *)
      echo "run_child: unknown shape '$shape'" >&2; CHILD_RC=64; return ;;
  esac
  [[ "$allow" == "1" ]] && env_args+=("SOLEUR_GIT_TRIPWIRE_ALLOW=1")
  env "${env_args[@]}" bash "$runner" "$child" >/dev/null 2>&1
  CHILD_RC=$?
}

# --- ARM 1: REFUSAL. Tripwire armed, hostile environment set -> the child must exit 97. ----------
for child in "${CHILDREN[@]}"; do
  ck
  run_child "$RUNNER_BARE" "$child" 0
  if [[ "$CHILD_RC" -eq "$TRIPWIRE_RC" ]]; then
    pass "refusal arm: $(basename "$child") aborts ${TRIPWIRE_RC} under a hostile environment"
  else
    fail "refusal arm: $(basename "$child") exited $CHILD_RC, expected ${TRIPWIRE_RC}"
  fi
done

# --- ARM 2 NEGATIVE CONTROL: the oracle must be able to SEE a breach. ---------------------------
# Without this the containment arm is unfalsifiable prose. Tripwire disarmed AND no scrub in the
# path: the child's writes land on the victim, and the quadruple MUST move. If this arm ever
# passes-as-unchanged, the oracle is blind and every containment verdict below is worthless.
ck
_before=$(victim_quad)
run_child "$RUNNER_BARE" "${CHILDREN[0]}" 1
_after=$(victim_quad)
if [[ "$CHILD_RC" -eq 0 && "$_before" != "$_after" ]]; then
  pass "negative control: with NO scrub in the path the victim is breached and the oracle sees it"
else
  fail "negative control: oracle is blind — rc=$CHILD_RC, before=$_before after=$_after"
fi

# Rebuild the victim: the negative control deliberately breached it.
rm -rf "$VICTIM"
mkdir -p "$VICTIM"
git -C "$VICTIM" init -q -b main
git -C "$VICTIM" config user.email victim@fixture.test
git -C "$VICTIM" config user.name victim
git -C "$VICTIM" config commit.gpgsign false
printf 'seed\n' > "$VICTIM/seed.txt"
git -C "$VICTIM" add -A
git -C "$VICTIM" commit -q -m "victim seed"

# --- ARM 2b NEGATIVE CONTROL: the OBJECT-STORE breach, which HEAD alone cannot see. -------------
# GIT_OBJECT_DIRECTORY alone: the child keeps its own repo, so the victim's HEAD, refs and index are
# untouched and only its loose-object count moves. Without this arm the 2nd, 3rd and 4th components
# of the quadruple are unfalsifiable by this suite's own fixtures -- the first negative control moves
# HEAD, so it would pass against a HEAD-only oracle. This is the arm that earns the fourth field.
ck
_ob_before=$(victim_quad)
run_child "$RUNNER_BARE" "${CHILDREN[0]}" 1 objects
_ob_after=$(victim_quad)
_ob_head_before=${_ob_before%%|*}
_ob_head_after=${_ob_after%%|*}
_ob_objs_before=${_ob_before##*|}
_ob_objs_after=${_ob_after##*|}
if [[ "$_ob_head_before" == "$_ob_head_after" && "$_ob_objs_after" -gt "$_ob_objs_before" ]]; then
  pass "negative control: an object-store breach moves ONLY the object count (${_ob_objs_before} -> ${_ob_objs_after}), which a HEAD-only oracle would miss"
else
  fail "negative control: object-store breach not observed as expected — before=$_ob_before after=$_ob_after"
fi

# Rebuild again: the object-store control deliberately grew the victim's store.
rm -rf "$VICTIM"
mkdir -p "$VICTIM"
git -C "$VICTIM" init -q -b main
git -C "$VICTIM" config user.email victim@fixture.test
git -C "$VICTIM" config user.name victim
git -C "$VICTIM" config commit.gpgsign false
printf 'seed\n' > "$VICTIM/seed.txt"
git -C "$VICTIM" add -A
git -C "$VICTIM" commit -q -m "victim seed"

# --- ARM 3: CONTAINMENT. Tripwire disarmed, hostile environment set, scrub in the path. ---------
# rc AND state, as a pair — see the header. This is the arm where the scrub is actually under test,
# and mutation M1 (delete the scrub line from the sandbox runner) is what drives it red.
for child in "${CHILDREN[@]}"; do
  before=$(victim_quad)
  run_child "$RUNNER_SCRUBBED" "$child" 1
  after=$(victim_quad)

  ck
  if [[ "$CHILD_RC" -eq 0 ]]; then
    pass "containment arm: $(basename "$child") ran to completion (rc 0, not a refusal)"
  else
    fail "containment arm: $(basename "$child") exited $CHILD_RC — refusal is not containment"
  fi

  ck
  if [[ "$before" == "$after" ]]; then
    pass "containment arm: $(basename "$child") left the victim's HEAD, refs, index and objects unchanged"
  else
    fail "containment arm: $(basename "$child") moved the victim: before=$before after=$after"
  fi
done

# --- Accounting, emitted DIRECTLY and never through pass()/fail(). ------------------------------
echo
echo "  Total: $((PASS + FAIL))  pass: $PASS  FAIL: $FAIL  asserted: $ASSERTED"

if [[ $((PASS + FAIL)) -ne $ASSERTED ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != asserted (%d).\n' "$((PASS + FAIL))" "$ASSERTED" >&2
  printf '        An assertion was counted without a verdict, or a verdict without a counted case.\n' >&2
  exit 1
fi

# ASSERTION FLOOR. Absolute, derived from a green run, ratcheted UP by hand when arms are added and
# never derived from a variable this file computes — a floor that descends with the thing it guards
# is not a floor. Any slack is budget for a future edit to delete an arm unnoticed, so there is none.
MIN_ASSERTIONS=12
if [[ $ASSERTED -lt $MIN_ASSERTIONS ]]; then
  printf '\n[FATAL] assertion floor: ran %d, expected at least %d.\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2
  printf '        Arms were skipped or the reporting helpers were disabled.\n' >&2
  exit 1
fi

if [[ "$HARNESS_OK" != "1" ]]; then
  printf '\n[FATAL] harness self-test did not observe BOTH counters move.\n' >&2
  printf '        pass() or fail() is disabled; this suite cannot report a failure.\n' >&2
  exit 1
fi

[[ $FAIL -eq 0 ]] || exit 1
exit 0
