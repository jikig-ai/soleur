#!/usr/bin/env bash
# Mutation battery for scripts/lint-dual-lockfile.sh (Guard 1).
#
# Every row below drives the guard RED, except the must-PASS rows — without those, a guard
# that rejects everything would score full marks on every RED row.
#
# The suite builds synthetic git repos rather than copying the real tree (13k+ files), and
# runs the REAL guard script inside them. A fixture that re-declares the guard's logic
# inline would assert that a known-good snippet is known-good.
set -euo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct invocation of
# this suite (the documented inner loop) would otherwise inherit it and its verdicts would
# become a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lint-dual-lockfile.sh"
[[ -r "$GUARD" ]] || {
  echo "FATAL: guard not readable at $GUARD" >&2
  exit 2
}

passes=0
fails=0
asserted=0
# ADR-193 #2: the verdict helpers touch ONLY the verdict counters. `asserted` (the CASE
# counter) moves at the CALL SITE instead. That is the whole difference between a
# conservation identity that catches a discarded verdict and one that cannot: a counter
# incremented inside both helpers moves WITH the verdict, so stubbing fail() drops the row
# AND its count together and `passes + fails == asserted` still holds under the exact fault
# it exists to catch.
pass() {
  passes=$((passes + 1))
  echo "[ok] $*"
}
fail() {
  fails=$((fails + 1))
  echo "[FAIL] $*" >&2
}

SANDBOX_ROOT=$(mktemp -d -t lint-dual-lockfile.XXXXXXXX) || {
  echo "FATAL: mktemp failed" >&2
  exit 2
}
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# Builds a synthetic repo with `n` package-lock.json directories. A harness that fails to
# SET UP must abort rather than silently produce a confident wrong verdict about the SUT.
make_repo() {
  local name="$1"
  local n="${2:-4}"
  local d="$SANDBOX_ROOT/$name"
  mkdir -p "$d" || return 2
  git -C "$d" init -q -b main || return 2
  git -C "$d" config user.email t@t || return 2
  git -C "$d" config user.name t || return 2
  # A filler tracked file so that removing every package-lock.json leaves a NON-empty
  # index. Without it, row 3 empties `git ls-files` and trips the guard's earlier
  # "enumeration returned nothing" arm instead of the floor it means to exercise.
  printf 'filler\n' > "$d/README.md" || return 2
  printf '{"name":"root","lockfileVersion":3}\n' > "$d/package-lock.json" || return 2
  local i
  for ((i = 1; i < n; i++)); do
    mkdir -p "$d/pkg$i" || return 2
    printf '{"name":"pkg%d","lockfileVersion":3}\n' "$i" > "$d/pkg$i/package-lock.json" || return 2
  done
  git -C "$d" add -A || return 2
  printf '%s' "$d"
}

run_guard() {
  local repo="$1" out rc
  out=$(cd "$repo" && bash "$GUARD" 2>&1) || rc=$?
  rc=${rc:-0}
  printf '%s\n---RC:%d\n' "$out" "$rc"
}

guard_rc() { run_guard "$1" | sed -n 's/^---RC:\(.*\)$/\1/p'; }
guard_out() { run_guard "$1" | sed '/^---RC:/d'; }

expect_red() {
  asserted=$((asserted + 1))
  local repo="$1" label="$2" needle="${3:-}" rc out
  rc=$(guard_rc "$repo")
  out=$(guard_out "$repo")
  if [[ "$rc" == "0" ]]; then
    fail "$label — expected RED, guard exited 0"
    return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    fail "$label — RED but message did not name '$needle'"
    return
  fi
  pass "$label — RED${needle:+ naming '$needle'}"
}

expect_pass() {
  asserted=$((asserted + 1))
  local repo="$1" label="$2" rc
  rc=$(guard_rc "$repo")
  if [[ "$rc" != "0" ]]; then
    fail "$label — expected PASS, guard exited $rc: $(guard_out "$repo" | head -3)"
    return
  fi
  pass "$label — PASS"
}

# --- CONTROL: a clean synthetic repo must PASS, or every RED row below is meaningless. ---
CLEAN=$(make_repo clean 4) || {
  echo "FATAL: sandbox setup failed" >&2
  exit 2
}
expect_pass "$CLEAN" "CONTROL clean repo (4 package-lock dirs, no bun.lock)"

# H3 must-PASS: the clean state reports a NON-ZERO scanned count, so it is distinguishable
# from a broken enumeration.
asserted=$((asserted + 1))
if guard_out "$CLEAN" | grep -qE '4 package-lock\.json director'; then
  pass "H3 clean tree reports a non-zero scanned count"
else
  fail "H3 clean tree did not report its scanned count"
fi

# --- Row 1: restore apps/web-platform/bun.lock ---
R1=$(make_repo row1 4)
: "${R1:?fixture dir is empty; git -C <empty> would retarget this write}"
mkdir -p "$R1/apps/web-platform"
printf 'lockfile\n' > "$R1/apps/web-platform/bun.lock"
git -C "$R1" add -A
expect_red "$R1" "row1 apps/web-platform/bun.lock restored" "apps/web-platform/bun.lock"

# --- Row 2: restore root bun.lock ---
R2=$(make_repo row2 4)
: "${R2:?fixture dir is empty; git -C <empty> would retarget this write}"
printf 'lockfile\n' > "$R2/bun.lock"
git -C "$R2" add -A
expect_red "$R2" "row2 root bun.lock restored" "tracked bun lockfile: bun.lock"

# --- Row 3: enumeration broken (zero package-lock.json) → RED via the floor, not exit 0 ---
R3=$(make_repo row3 4)
: "${R3:?fixture dir is empty; git -C <empty> would retarget this write}"
git -C "$R3" rm -q --cached package-lock.json pkg1/package-lock.json pkg2/package-lock.json pkg3/package-lock.json
expect_red "$R3" "row3 empty package-lock enumeration" "below the floor"

# --- Row 4: a THIRD bun.lock while both known directories stay clean ---
R4=$(make_repo row4 4)
: "${R4:?fixture dir is empty; git -C <empty> would retarget this write}"
mkdir -p "$R4/spike"
printf 'lockfile\n' > "$R4/spike/bun.lock"
git -C "$R4" add -A
expect_red "$R4" "row4 spike/bun.lock (whole-set quantification)" "spike/bun.lock"

# --- Row 5: a bun.lock in a directory with NO package-lock.json ---
R5=$(make_repo row5 4)
: "${R5:?fixture dir is empty; git -C <empty> would retarget this write}"
mkdir -p "$R5/lonely"
printf 'lockfile\n' > "$R5/lonely/bun.lock"
git -C "$R5" add -A
expect_red "$R5" "row5 bun.lock with no sibling package-lock.json" "lonely/bun.lock"

# --- Row 6: reintroduce [install] into a bunfig.toml ---
R6=$(make_repo row6 4)
: "${R6:?fixture dir is empty; git -C <empty> would retarget this write}"
printf '[install]\nminimumReleaseAge = 259200\n\n[test]\npreload = "./x.ts"\n' > "$R6/bunfig.toml"
git -C "$R6" add -A
expect_red "$R6" "row6 [install] section reintroduced" "declares an [install] section"

# Row 6b: a bunfig.toml with ONLY [test] must PASS — the guard must not reject bun as a
# test runner. Without this, row 6 would also pass against a guard that rejects any bunfig.
R6B=$(make_repo row6b 4)
: "${R6B:?fixture dir is empty; git -C <empty> would retarget this write}"
printf '[test]\npreload = "./x.ts"\n' > "$R6B/bunfig.toml"
git -C "$R6B" add -A
expect_pass "$R6B" "row6b bunfig.toml with only [test] (bun stays the test runner)"

# Row 6c: `[install.scopes]` — a sub-table must redden too, or the clause is bypassable.
R6C=$(make_repo row6c 4)
: "${R6C:?fixture dir is empty; git -C <empty> would retarget this write}"
printf '[install.scopes]\n"@x" = "https://y"\n' > "$R6C/bunfig.toml"
git -C "$R6C" add -A
expect_red "$R6C" "row6c [install.scopes] sub-table" "declares an [install] section"

# Rows 6d-6g: TOML admits several spellings of the same table. The original anchor saw only
# the canonical `[install]`, so each of these declared install config and passed green.
for spelling in "[ install ]" '["install"]' 'install.registry = "https://reg"'; do
  RS=$(make_repo "row6-$(printf '%s' "$spelling" | tr -cd '[:alnum:]')" 4)
  : "${RS:?fixture dir is empty; git -C <empty> would retarget this write}"
  printf '%s\nminimumReleaseAge = 259200\n' "$spelling" > "$RS/bunfig.toml"
  git -C "$RS" add -A
  expect_red "$RS" "row6 TOML spelling '$spelling' is seen" "declares an [install] section"
done

# Row 6h: bun also reads bunfig.local.toml, which was outside the scanned set entirely.
R6H=$(make_repo row6h 4)
: "${R6H:?fixture dir is empty; git -C <empty> would retarget this write}"
printf '[install]\nminimumReleaseAge = 259200\n' > "$R6H/bunfig.local.toml"
git -C "$R6H" add -A
expect_red "$R6H" "row6h bunfig.local.toml is scanned" "declares an [install] section"

# --- Row 7: the floor must be ASSERTED, not decorative. ---
asserted=$((asserted + 1))
if grep -qE '^MIN_PACKAGE_LOCK_DIRS=[4-9][0-9]*$' "$GUARD"; then
  pass "row7 floor constant is >= 4 (not lowered to a decorative value)"
else
  fail "row7 MIN_PACKAGE_LOCK_DIRS is missing or below 4 — the floor is decorative"
fi
# ...and behaviorally: a repo with fewer dirs than the floor must RED even when clean.
R7=$(make_repo row7 2)
expect_red "$R7" "row7 clean repo below the floor still REDs" "below the floor"

# --- Row 8: the retained sdk-bump-sandbox-gate PRESENCE arm. ---
# Guard 1 does not own this check; the row exists so that retiring the bun half of
# sdk-bump-sandbox-gate.sh cannot silently take the empty-head_v catch with it (#5849).
SDK_GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/web-platform/scripts/sdk-bump-sandbox-gate.sh"
asserted=$((asserted + 1))
if [[ -r "$SDK_GATE" ]]; then
  if grep -qE '\[\[[[:space:]]*-z[[:space:]]*"\$\{?pv\}?"[[:space:]]*\]\]' "$SDK_GATE"; then
    pass "row8 sdk-bump-sandbox-gate.sh retains its [[ -z \$pv ]] PRESENCE arm"
  else
    fail "row8 sdk-bump-sandbox-gate.sh lost its [[ -z \$pv ]] PRESENCE arm — the empty-head_v silent-green class (#5849) is reopened"
  fi
else
  fail "row8 could not read $SDK_GATE"
fi

# --- H2 must-PASS: an npm-only directory, never dual. ---
H2=$(make_repo h2 4)
: "${H2:?fixture dir is empty; git -C <empty> would retarget this write}"
mkdir -p "$H2/pencil-scripts"
printf '{"name":"pencil","lockfileVersion":3}\n' > "$H2/pencil-scripts/package-lock.json"
git -C "$H2" add -A
expect_pass "$H2" "H2 npm-only directory"

# --- H1: the suite's own executed-assertion floor (ADR-193). ---
# The floor sits on PASSES, never on `asserted`: a floor on the case counter measures that
# assertions RAN and never that they CONCLUDED. Deleting
# the single line `fails=$((fails + 1))` from fail() left this suite reporting
# "5 passed, 0 failed, 14 assertion(s)" and exiting 0 with the guard fully neutered. The
# reconciliation catches that directly -- passes+fails must account for every assertion,
# so a counter that stops incrementing is a hard failure rather than a quiet one.
#
# Emitted WITHOUT routing through fail(), because a floor dispatched through the helper it
# backstops is disarmed by the same one-line edit it exists to catch.
#
# ORDER (ADR-193 #4): conservation runs FIRST. A neutered fail() deflates the pass count, so
# both checks trip on the same fault -- and whichever runs first names it. Conservation says
# "a verdict was discarded"; the floor would say the misleading "assertions were removed".
#
# The threshold binding sits DIRECTLY above the floor it binds, with no intervening block.
# scripts/guard-vacuity-floor.test.sh builds its mutant by slicing the floor `if` plus the
# contiguous simple assignments above it; with the conservation block in between, the slice
# stops at `fi`, MIN_ASSERTIONS is unbound, and the mutant dies at `set -u` BEFORE reaching
# the floor -- scored "not constructible", i.e. this floor would be asserted by nothing.
if [[ $((passes + fails)) -ne $asserted ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d).\n' \
    "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt "$asserted" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded without a counted case — a call site is missing its increment (a harness bug, not a product failure).\n' >&2
  fi
  exit 1
fi
MIN_ASSERTIONS=18
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] H1 only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — assertions were neutered or skipped" >&2
  exit 1
fi

echo
echo "lint-dual-lockfile.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
