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
# intact, which is precisely what makes the containment arms below a test of the OTHER layer.
#
# WHY EVERY ARM PINS THE CHILD'S EXIT CODE AND ITS LIVENESS. A swept suite sources test-helpers.sh,
# so under a hostile GIT_DIR the tripwire fires and the child exits 97 BEFORE running any git
# write; the victim is then trivially unchanged. A state-only assertion certifies "contained OR
# refused to run OR never started". Each of those three has been observed here, so each is pinned:
# rc separates refusal, and a liveness sentinel separates never-started.
#
# WHY THE HOSTILE VALUE IS THE VICTIM. A hostile GIT_DIR pointing somewhere neutral (/tmp/hostile)
# is correct for the refusal arm, which only needs the tripwire to see SOME location variable. It
# is fatal for a containment arm: if the hostile value does not point at the victim, the victim's
# state cannot move whether containment holds or not, and the arm cannot be driven red.
#
# THIS FILE MUST NOT SOURCE test-helpers.sh. It controls the tripwire, so sourcing it would abort
# this suite in the exact arms it exists to exercise. git-tripwire.test.sh carries the same
# constraint and states it in its own header.
#
# ...WHICH IS EXACTLY WHY IT MUST SCRUB ITSELF. Review of the first revision found this file took
# NEITHER layer: no tripwire (correct, by the paragraph above) and no self-scrub. Run under an
# inherited git-location environment — the invocation printed below, a hook, `git rebase --exec`,
# or .github/scripts/test/run-all.sh, which carries no scrub — its own victim setup retargeted at
# the caller: it committed the developer's uncommitted work onto their live branch as
# `victim <victim@fixture.test>`, and rewrote .git/config, which test-helpers.sh calls "the SHARED
# file every worktree on the machine inherits". Reproduced independently three times. The scrub
# below is therefore the first executable statement, and it is DERIVED, not transcribed.
#
# Reached by scripts/test-all.sh through its existing plugins/soleur/test/*.test.sh glob — BY
# NAMING, not by registration. scripts/test-all.sh is a do-not-touch path here: it is READ, as
# data, and is never edited, invoked or nested.
#
# Run: bash plugins/soleur/test/git-fixture-containment.test.sh

set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPERS="$SCRIPT_DIR/test-helpers.sh"
RUNNER_SRC="$REPO_ROOT/scripts/test-all.sh"

# The tripwire's abort code. Bound once rather than inlined, mirroring git-tripwire.test.sh:26.
# It is also bound at test-helpers.sh:38 (the emitter), kb-index-merge-driver.test.sh:414 (T14),
# and — most consequentially — scripts/test-all.sh:851, where the runner special-cases rc 97 as
# [TRIPWIRE] rather than a failing assertion. Five further inline copies live under
# plugins/soleur/skills/git-worktree/test/.
readonly TRIPWIRE_RC=97

# --- The scrub line, DERIVED from scripts/test-all.sh, never transcribed. ------------------------
# A transcribed copy drifts silently the moment the real line gains a variable, and this suite
# would then certify a scrub the runner no longer performs.
#
# The shape check is not decoration. The derivation is LINE-WISE, so reflowing that line onto
# backslash continuations — a pure formatting change that keeps all nine variables — yields a
# SCRUB_LINE ending in a backslash, which swallows the following `exec` and means THE CHILD NEVER
# RUNS while the containment arm still reports "contained". Measured: 12/12 green with the child
# never executed. Anchoring the shape rejects that before it can reach the self-scrub or an arm.
SCRUB_LINE=$(grep -m1 -E '^unset GIT_DIR ' "$RUNNER_SRC" || true)
if [[ ! "$SCRUB_LINE" =~ ^unset(\ +GIT_[A-Z_]+)+$ ]]; then
  printf 'FATAL: could not derive a well-formed scrub line from %s\n' "$RUNNER_SRC" >&2
  printf '       got: %s\n' "${SCRUB_LINE:-<empty>}" >&2
  printf '       expected shape: ^unset( +GIT_[A-Z_]+)+$ — a reflow onto continuations breaks this\n' >&2
  exit 2
fi

# SELF-SCRUB. Everything below runs in a clean git-location environment; every arm supplies its
# hostile values explicitly via `env`, so this changes no arm and is what stops this suite from
# being an instance of the incident it pins.
eval "$SCRUB_LINE"

PASS=0
FAIL=0
ASSERTED=0
# A precondition whose failure message says "a breach would hit real work" must ABORT, not count.
# In the first revision these were non-fatal, so a run that had already breached the caller
# continued into the deliberate-breach arms and reported 10 of 12 PASS.
die() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

echo "git-fixture-containment.test.sh"

TMP_ROOT=$(mktemp -d -t gitfixcontain.XXXXXXXX) || die "no scratch root"
# The handler EXITS. Without that, Ctrl-C removed the sandbox and then resumed at the interrupted
# statement with the runners, children and victim gone, so the remaining arms ran against a deleted
# victim and could still exit 0.
cleanup() { [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT TERM HUP

VICTIM="$TMP_ROOT/victim"
SENTINEL_DIR="$TMP_ROOT/sentinels"
VERDICT_LOG="$TMP_ROOT/verdicts.txt"
mkdir -p "$SENTINEL_DIR"
: > "$VERDICT_LOG"

# The verdict helpers are defined HERE, below the sandbox, so VERDICT_LOG's redirect operand is
# provably rooted at a mktemp directory rather than at an unbound name.
#
# VERDICT_LOG is append-only and is the INDEPENDENT observable the accounting reconciles against.
# A sum check conserves the total, so it cannot see a verdict moved from the fail bucket to the
# pass bucket — measured elsewhere in this repo as `64 passed, 0 failed` exit 0 with a genuine
# regression printing FAIL on screen. Silencing the ledger means deleting evidence, not moving a
# number. Idiom adopted from fixture-dir-operand-assert.test.sh, which is stronger here.
ck() { ASSERTED=$((ASSERTED + 1)); }
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; printf 'PASS\n' >> "$VERDICT_LOG"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; return 0; }

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
# The self-test drives both helpers, so it appended one row to each bucket. Truncate rather than
# decrement: the ledger's whole value is that it is append-only DURING the run, and the run has
# not started yet.
: > "$VERDICT_LOG"

# The hostile environment IS the victim — see the header. This is the shape #7835 records.
HOSTILE_GIT_DIR="$VICTIM/.git"
HOSTILE_WORK_TREE="$VICTIM"
HOSTILE_INDEX="$VICTIM/.git/index"

# --- Preconditions: ALL FATAL, ALL ABOVE the first git write. -----------------------------------
# The containment predicate is the REPOSITORY, not $PWD. A raw $PWD-prefix test is not
# path-boundary aware (a sibling directory sharing a prefix false-fires) and is unconditionally
# true when $PWD is "/". The hazard is "inside the developer's repository"; REPO_ROOT names it.
[[ "$VICTIM" == /* ]] || die "victim path is not absolute: ${VICTIM:-<empty>}"
[[ "$VICTIM" != "$REPO_ROOT" && "$VICTIM" != "$REPO_ROOT"/* ]] \
  || die "victim '$VICTIM' resolves inside the repository at '$REPO_ROOT' — a breach would hit real work"
[[ -f "$HELPERS" ]] || die "missing $HELPERS"

# --- The nine, DERIVED from test-helpers.sh's own loop rather than transcribed. ------------------
# The first revision asserted only that the derived line named GIT_INDEX_FILE. Measured: deleting
# six of the nine from scripts/test-all.sh left this suite 12/12 green, and deleting ONLY
# GIT_OBJECT_DIRECTORY also left it green — while this suite's own control proves that variable is
# a live breach vector its oracle can see. Demonstrated, then undefended.
TRIPWIRE_VARS=$(awk '/for _v in GIT_DIR/,/; do/' "$HELPERS" \
  | tr ' \\;' '\n\n\n' | grep -E '^GIT_[A-Z_]+$' | LC_ALL=C sort -u)
[[ -n "$TRIPWIRE_VARS" ]] || die "could not derive the tripwire variable list from $HELPERS"
TRIPWIRE_VAR_COUNT=$(printf '%s\n' "$TRIPWIRE_VARS" | grep -c .)
(( TRIPWIRE_VAR_COUNT >= 9 )) || die "derived only $TRIPWIRE_VAR_COUNT tripwire variables from $HELPERS; expected at least 9"

# The self-scrub must actually have worked. Checked AFTER the derivation so the list is the
# authority, and before any git write.
while IFS= read -r _leaked; do
  [[ -z "${!_leaked:-}" ]] || die "self-scrub failed: $_leaked is still set — refusing to build a fixture"
done <<<"$TRIPWIRE_VARS"
unset _leaked

# --- Victim construction, factored so the rebuilds cannot drift from the original. ---------------
# The first revision inlined this three times and asserted only the FIRST. Measured: neutering a
# later rebuild left the suite 12/12 green, because the fingerprint of a non-repository is a stable
# constant, so before == after held trivially and every containment arm certified containment
# against a directory that was not a repository at all.
build_victim() {
  # The only recursive delete in this file, and the operand is guarded rather than trusted.
  case "$VICTIM" in
    /*) : ;;
    *) die "refusing rm -rf on a non-absolute victim path: ${VICTIM:-<empty>}" ;;
  esac
  [[ "$VICTIM" != "$REPO_ROOT" && "$VICTIM" != "$REPO_ROOT"/* ]] \
    || die "refusing rm -rf inside the repository at $REPO_ROOT"
  rm -rf "$VICTIM"
  mkdir -p "$VICTIM" || die "could not create the victim fixture"
  git -C "$VICTIM" init -q -b main || die "victim init failed"
  git -C "$VICTIM" config user.email victim@fixture.test || die "victim config failed"
  git -C "$VICTIM" config user.name victim || die "victim config failed"
  git -C "$VICTIM" config commit.gpgsign false || die "victim config failed"
  printf 'seed\n' > "$VICTIM/seed.txt"
  git -C "$VICTIM" add -A || die "victim add failed"
  git -C "$VICTIM" commit -q -m "victim seed" || die "victim commit failed"
}

assert_victim_is_a_repo() { # <where>
  ck
  local gd
  gd=$(LC_ALL=C git -C "$VICTIM" rev-parse --absolute-git-dir 2>&1)
  case "$gd" in
    "$VICTIM"/*) pass "victim resolves to its OWN git dir ($1)" ;;
    *)           fail "victim resolved to '$gd', outside the fixture ($1)" ;;
  esac
}

build_victim
assert_victim_is_a_repo "initial build"

ck
if grep -qE '^[[:space:]]*exit '"$TRIPWIRE_RC"'$' "$HELPERS"; then
  pass "test-helpers.sh carries the exit ${TRIPWIRE_RC} tripwire"
else
  fail "test-helpers.sh has no exit ${TRIPWIRE_RC} — the refusal arm is meaningless"
fi

# The derived scrub must cover EVERY variable the tripwire refuses. Both lists are derived; if they
# ever disagree that is real drift between the two layers, and this arm is where it surfaces.
ck
_missing=""
while IFS= read -r _v; do
  grep -qE "(^|[[:space:]])${_v}([[:space:]]|$)" <<<"$SCRUB_LINE" || _missing="$_missing $_v"
done <<<"$TRIPWIRE_VARS"
if [[ -z "$_missing" ]]; then
  pass "the derived scrub covers all ${TRIPWIRE_VAR_COUNT} variables the tripwire refuses"
else
  fail "the derived scrub is missing:${_missing}"
fi
unset _missing _v

# --- Two DIFFERENTIATED synthesized children. ---------------------------------------------------
# Real swept suites are deliberately not used: pointing these arms at gitleaks-merge-commit would
# couple a containment proof to a 27-assertion battery and make this verdict track unrelated churn.
#
# The two children differ in WHICH observable a breach moves, which is what makes a second member a
# discriminator rather than floor padding. In the first revision they were byte-identical modulo
# $n, so every assertion satisfied by one was satisfied by both: replacing child-2 with a no-op
# that performed zero git writes left the suite 12/12 green.
#   child-1 COMMITS   -> a breach moves HEAD, refs and the object store
#   child-2 ADDs only -> a breach moves the INDEX and the object store, HEAD and refs unmoved
# Each writes a liveness sentinel, so an arm can tell "ran and was contained" from "never ran".
CHILDREN=()
for n in 1 2; do
  child="$TMP_ROOT/child-$n.sh"
  # A QUOTED heredoc for the body, with every value passed in through a generated prelude. Two
  # reasons, both measured. (1) An UNQUOTED heredoc expands `$` and backticks at write time, and a
  # backtick in an explanatory comment inside it was command-substituted on every run. (2) Building
  # the body with `printf` instead makes each generated `git -C "$d"` line visible to the P1b
  # scanner as if it were this file's own code — 7 spurious rows, none of which a guard here could
  # honestly clear, because the operand is bound in the CHILD. A heredoc body is skipped by the
  # scanner and the child carries its own absolute-path guard below.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'HELPERS=%q\n' "$HELPERS"
    printf 'SENT=%q\n' "$SENTINEL_DIR"
    printf 'N=%q\n' "$n"
    printf 'DO_COMMIT=%q\n' "$([[ "$n" == "1" ]] && echo yes || echo no)"
    cat <<'CHILDEOF'
set -uo pipefail
# Sources the real helper: that is what makes the refusal arm a test of the shipped tripwire.
source "$HELPERS"
d=$(mktemp -d -t containchild.XXXXXXXX) || exit 2
case "$d" in /*) : ;; *) printf 'FATAL: child fixture dir not absolute\n' >&2; exit 2 ;; esac
git -C "$d" init -q
git -C "$d" config user.email child@fixture.test
git -C "$d" config user.name child
git -C "$d" config commit.gpgsign false
printf 'child %s\n' "$N" > "$d/child-$N.txt"
git -C "$d" add -A
if [ "$DO_COMMIT" = yes ]; then
  # --allow-empty is load-bearing: a breach retargets this at the VICTIM, whose work tree does not
  # hold the child file, so `add -A` stages nothing there and a plain commit would exit 1 without
  # moving HEAD, making the breach invisible to the oracle.
  git -C "$d" commit -q --allow-empty -m "child $N wrote"
fi
printf 'ran' > "$SENT/ran-$N"
rm -rf "$d"
exit 0
CHILDEOF
  } > "$child"
  CHILDREN+=("$child")
done

# --- The oracle. FAIL-CLOSED, and wider than HEAD. ----------------------------------------------
# The first revision piped every probe through `2>/dev/null | sha256sum`, so a git command that
# FAILED emitted nothing and hashed to e3b0c442…7852b855 — byte-identical to a clean repository.
# Measured: a child with only GIT_INDEX_FILE surviving overwrote the victim's index (md5 e3b6f8dc
# -> 52da6db7) while all four components stayed identical, because the retargeted index references
# a blob in the CHILD's object store and `diff --cached` then exits 128. That is the exact scenario
# this file's header cites as the reason the staged component exists.
#
# So every probe captures rc, and a failure renders as a DISTINCT sentinel, never as clean.
probe() { # <ok-rcs-csv> <cmd...> -> a hash, or ERR:<rc>
  local ok="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [[ ",$ok," != *",$rc,"* ]]; then printf 'ERR:%s' "$rc"; return 0; fi
  printf '%s' "$out" | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}

victim_fingerprint() {
  local head refs staged objects headfile config hooks
  head=$(probe 0 git -C "$VICTIM" rev-parse HEAD)
  # show-ref exits 1 on a repository with no refs, which is legitimate; anything else is an error.
  refs=$(probe 0,1 git -C "$VICTIM" show-ref)
  staged=$(probe 0 git -C "$VICTIM" diff --cached --name-only)
  # A COUNT is not an identity: it is conserved by add-one/remove-one and by writing a blob the
  # victim already has (measured: plant one, destroy one -> 4 -> 4, fsck still clean). The sorted
  # LISTING is the identity.
  objects=$(find "$VICTIM/.git/objects" -type f 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
  # rev-parse RESOLVES the symref, so retargeting .git/HEAD to an equal-SHA branch is invisible to
  # `head`. The raw bytes are not.
  headfile=$(sha256sum < "$VICTIM/.git/HEAD" 2>/dev/null | cut -d' ' -f1)
  # Both measured invisible to a refs/index/objects oracle, and both are real #7822 harm: GIT_DIR
  # alone plus `git config` writes the victim's config (the children do exactly this), and
  # GIT_TEMPLATE_DIR plus the child's own `git init` implants an EXECUTABLE pre-commit hook.
  config=$(sha256sum < "$VICTIM/.git/config" 2>/dev/null | cut -d' ' -f1)
  hooks=$(find "$VICTIM/.git/hooks" -type f -printf '%m %P\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$head" "$refs" "$staged" "$objects" "$headfile" "$config" "$hooks"
}

run_child() { # <mode:scrubbed|bare> <child> <allow:0|1> [shape] -> sets CHILD_RC
  local mode="$1" child="$2" allow="$3" shape="${4:-location}"
  local -a env_args=()
  local _u
  # Start clean for ALL nine, then set only the shape under test. Without this sweep, `env` passes
  # every inherited location variable through, so an arm could not assert the shape it names — and
  # in the first revision six of the nine flowed straight into the child.
  while IFS= read -r _u; do env_args+=("-u" "$_u"); done <<<"$TRIPWIRE_VARS"
  case "$shape" in
    location)
      env_args+=("GIT_DIR=$HOSTILE_GIT_DIR" "GIT_WORK_TREE=$HOSTILE_WORK_TREE" "GIT_INDEX_FILE=$HOSTILE_INDEX") ;;
    index)
      # The header's stated justification for the refs and staged components. Without this shape it
      # is never instantiated, and setting both to a constant left the suite fully green.
      env_args+=("GIT_INDEX_FILE=$HOSTILE_INDEX") ;;
    objects)
      # The M-14 shape: the child keeps its OWN repository, so the victim's HEAD, refs and index
      # stay byte-identical and only its object store moves.
      env_args+=("GIT_OBJECT_DIRECTORY=$VICTIM/.git/objects") ;;
    *) fail "run_child: unknown shape '$shape'"; CHILD_RC=64; return 0 ;;
  esac
  [[ "$allow" == "1" ]] && env_args+=("SOLEUR_GIT_TRIPWIRE_ALLOW=1")

  # No sandbox runner FILE. An earlier revision materialised the scrub into a temp script, which
  # needed a redirect operand, which produced a P1b scanner row, which needed an inline byte-exact
  # assert_fixture_dir, which permanently joined two repo-wide drift corpora — a standing
  # obligation incurred to write a two-line file. `bash -c` is byte-identical on both arms.
  if [[ "$mode" == "scrubbed" ]]; then
    env "${env_args[@]}" bash -c "$SCRUB_LINE"$'\n''exec bash "$1"' _ "$child" >/dev/null 2>&1
  else
    env "${env_args[@]}" bash -c 'exec bash "$1"' _ "$child" >/dev/null 2>&1
  fi
  CHILD_RC=$?
}

ran_sentinel() { [[ -f "$SENTINEL_DIR/ran-$1" ]]; }
clear_sentinels() { rm -f "$SENTINEL_DIR"/ran-*; }

# --- ARM 1: REFUSAL. Tripwire armed, hostile environment -> the child must exit 97. -------------
for i in 0 1; do
  n=$((i + 1))
  ck
  clear_sentinels
  run_child bare "${CHILDREN[$i]}" 0
  if [[ "$CHILD_RC" -eq "$TRIPWIRE_RC" ]]; then
    pass "refusal arm: child-$n aborts ${TRIPWIRE_RC} under a hostile environment"
  else
    fail "refusal arm: child-$n exited $CHILD_RC, expected ${TRIPWIRE_RC}"
  fi
done

# --- ARM 2 NEGATIVE CONTROLS: the oracle must SEE a breach, per child and per shape. -------------
# Without these the containment arms are unfalsifiable prose. Both children run, because in the
# first revision only CHILDREN[0] was ever proven to be a writer — so child-2 could be replaced by
# a no-op with the suite fully green. Every control pins rc AND liveness for the same reason the
# containment arms do: a control that "breached" without running proves nothing either.
for i in 0 1; do
  n=$((i + 1))
  ck
  clear_sentinels
  before=$(victim_fingerprint)
  run_child bare "${CHILDREN[$i]}" 1
  after=$(victim_fingerprint)
  if [[ "$CHILD_RC" -eq 0 && "$before" != "$after" ]] && ran_sentinel "$n"; then
    pass "negative control [location/child-$n]: with NO scrub the victim is breached and the oracle sees it"
  else
    fail "negative control [location/child-$n]: rc=$CHILD_RC sentinel=$(ran_sentinel "$n" && echo present || echo ABSENT) before=$before after=$after"
  fi
  build_victim
  assert_victim_is_a_repo "rebuild after negative control child-$n"
done

# --- ARM 2b: the OBJECT-STORE breach, which HEAD alone cannot see. ------------------------------
ck
clear_sentinels
_ob_before=$(victim_fingerprint)
run_child bare "${CHILDREN[0]}" 1 objects
_ob_after=$(victim_fingerprint)
_ob_head_before=$(cut -d'|' -f1 <<<"$_ob_before"); _ob_head_after=$(cut -d'|' -f1 <<<"$_ob_after")
_ob_obj_before=$(cut -d'|' -f4 <<<"$_ob_before"); _ob_obj_after=$(cut -d'|' -f4 <<<"$_ob_after")
if [[ "$CHILD_RC" -eq 0 && "$_ob_head_before" == "$_ob_head_after" && "$_ob_obj_before" != "$_ob_obj_after" ]] && ran_sentinel 1; then
  pass "negative control [objects]: the breach moves ONLY the object store, which a HEAD-only oracle would miss"
else
  fail "negative control [objects]: rc=$CHILD_RC before=$_ob_before after=$_ob_after"
fi
build_victim
assert_victim_is_a_repo "rebuild after object-store control"

# --- ARM 2c: the INDEX-ONLY breach — the component the first revision could not see. -------------
ck
clear_sentinels
_ix_before=$(victim_fingerprint)
run_child bare "${CHILDREN[1]}" 1 index
_ix_after=$(victim_fingerprint)
if [[ "$CHILD_RC" -eq 0 && "$_ix_before" != "$_ix_after" ]] && ran_sentinel 2; then
  pass "negative control [index]: an index-only breach is visible — the fail-open this oracle was rebuilt to close"
else
  fail "negative control [index]: rc=$CHILD_RC sentinel=$(ran_sentinel 2 && echo present || echo ABSENT) before=$_ix_before after=$_ix_after"
fi
build_victim
assert_victim_is_a_repo "rebuild after index-only control"

# --- ARM 3: CONTAINMENT, across every shape a negative control proved observable. ---------------
# rc AND state AND liveness. rc alone cannot tell containment from refusal; state alone cannot tell
# containment from a child that never executed, which is exactly what a reflowed scrub line
# silently produced.
for shape in location index objects; do
  for i in 0 1; do
    n=$((i + 1))
    clear_sentinels
    before=$(victim_fingerprint)
    run_child scrubbed "${CHILDREN[$i]}" 1 "$shape"
    after=$(victim_fingerprint)

    ck
    if [[ "$CHILD_RC" -eq 0 ]] && ran_sentinel "$n"; then
      pass "containment arm [$shape/child-$n]: the child RAN to completion (rc 0, sentinel present)"
    else
      fail "containment arm [$shape/child-$n]: rc=$CHILD_RC sentinel=$(ran_sentinel "$n" && echo present || echo ABSENT) — refusal, or a child that never ran, is not containment"
    fi

    ck
    if [[ "$before" == "$after" ]]; then
      pass "containment arm [$shape/child-$n]: victim byte-identical across all seven components"
    else
      fail "containment arm [$shape/child-$n]: the victim moved: before=$before after=$after"
    fi
  done
done

# --- Accounting, emitted DIRECTLY and never through pass()/fail(). ------------------------------
echo
echo "  Total: $((PASS + FAIL))  pass: $PASS  FAIL: $FAIL  asserted: $ASSERTED"

# DIRECTION-AWARE. The sum below conserves the total, so it cannot see a verdict moved from the
# fail bucket to the pass bucket. The ledger is the independent observable.
_ledger_pass=$(grep -c '^PASS$' "$VERDICT_LOG" || true)
_ledger_fail=$(grep -c '^FAIL$' "$VERDICT_LOG" || true)
if [[ "${_ledger_pass:-0}" -ne "$PASS" || "${_ledger_fail:-0}" -ne "$FAIL" ]]; then
  printf '\n[FATAL] accounting: ledger (%s pass / %s fail) disagrees with counters (%d pass / %d fail).\n' \
    "${_ledger_pass:-0}" "${_ledger_fail:-0}" "$PASS" "$FAIL" >&2
  printf '        A verdict was recorded in one bucket and counted in the other.\n' >&2
  exit 1
fi

if [[ $((PASS + FAIL)) -ne $ASSERTED ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != asserted (%d).\n' "$((PASS + FAIL))" "$ASSERTED" >&2
  printf '        An assertion was counted without a verdict, or a verdict without a counted case.\n' >&2
  exit 1
fi

# ASSERTION FLOOR. Absolute, derived from a green run, ratcheted UP by hand when arms are added, and
# never derived from a variable this file computes — a floor that descends with the thing it guards
# is not a floor. Any slack is budget for a future edit to delete an arm unnoticed, so there is none.
MIN_ASSERTIONS=25
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

# Read from the LEDGER, not the counter: a `FAIL=0` inserted after the last arm passes every gate
# above, but it cannot delete the recorded FAIL lines.
[[ "${_ledger_fail:-0}" -eq 0 ]] || exit 1
exit 0
