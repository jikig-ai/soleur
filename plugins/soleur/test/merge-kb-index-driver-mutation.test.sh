#!/usr/bin/env bash
# Guard 2 mutation battery — scripts/merge-kb-index.sh's validation loop.
#
# WHAT THIS ANSWERS THAT THE FUNCTIONAL SUITE DOES NOT. The functional suite
# proves the driver merges correctly on the shapes it was shown. This proves
# each of the driver's GUARDS can actually be driven red — that removing one
# changes an outcome. Those are different questions, and a guard that cannot be
# driven red is vacuous no matter how green the suite around it is.
#
# ROWS ARE EXERCISED BY DIRECT INVOCATION, not through `git merge`. Every
# property below is about the driver's own validation loop rather than about
# git's merge machinery, and a real merge per row would cost minutes for no
# additional discrimination. The functional suite owns the git-invocation
# contract.
#
# Contract, per traps this repo has already paid for:
#   * Restore from a PRISTINE COPY, never `git checkout` — checkout restores to
#     HEAD, which is a different thing from "what I had a moment ago" while a
#     fix is in flight, and would score later rows against a reverted fix.
#   * A GREEN unmutated control runs FIRST. A red baseline voids every row.
#   * Each mutation is asserted to have LANDED (diff vs pristine). A mutation
#     that does not land reports the BASELINE, which is indistinguishable from a
#     pass — the exact vacuity this battery exists to prevent.
#   * Mutators live in FILES, not inline strings: a python body quoted inside a
#     bash single-quoted string breaks on its own apostrophes, and that failure
#     is a silent no-op.
#
# MUTATION MATRIX (observed verdicts; every row RED = the guard holds)
#   G1  %P validation removed .......................... RED
#   G2  round-trip validation removed ................... RED
#   G3  `..` containment check removed .................. RED
#   G4  absolute-rel check removed ...................... RED
#   G5  two-sided retitle silently takes ours ........... RED
#   G6  two-sided add silently takes ours ............... RED
#   G7  ERR trap removed (unhandled path writes nothing)  RED
#   G8  sentinel writer neutered to a no-op ............. RED
#   G9  a row deleted on one side is resurrected ........ RED
#   G10 LC_ALL=C sort dropped from the merged render .... RED
#   G11 renderer drift: kb-index-render.sh header edited  RED
#   G12 the 8 KB physical-line cap removed ............... RED
#   G13 `set -E` dropped — ERR trap no longer covers functions  RED
#   H1  the probe's own failure counter is neutered ..... RED (harness self-test)

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

TRACKED_DRIVER="$REPO_ROOT/scripts/merge-kb-index.sh"
TRACKED_RENDER="$REPO_ROOT/scripts/lib/kb-index-render.sh"
[[ -f "$TRACKED_DRIVER" ]] || { printf 'FATAL: driver missing at %s\n' "$TRACKED_DRIVER" >&2; exit 2; }
[[ -f "$TRACKED_RENDER" ]] || { printf 'FATAL: renderer missing at %s\n' "$TRACKED_RENDER" >&2; exit 2; }

WORK="$(mktemp -d -t g2mut.XXXXXXXX)" || exit 2
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
M="$WORK/mut"; mkdir -p "$M" || exit 2
F="$WORK/fx";  mkdir -p "$F" || exit 2

PRISTINE_DRIVER="$WORK/driver.pristine"
PRISTINE_RENDER="$WORK/render.pristine"
# MUTATE A COPY, NEVER THE TRACKED FILE.
#
# An earlier revision mutated `scripts/merge-kb-index.sh` in place -- the driver
# that is REGISTERED in the shared bare-repo config and therefore live in every
# linked worktree on this machine. Two consequences, one of them measured during
# review: a concurrent `--check` in this worktree returned a false "kb index
# artifacts are fresh" against a knowingly-stale file, because the generator was
# on disk mid-mutation; and a SIGKILL or OOM between apply and restore would
# leave a neutered driver armed fleet-wide, reintroducing precisely the
# markerless-conflict defect this PR exists to close. The EXIT/INT/TERM/HUP trap
# cannot cover either case.
#
# The copy replicates the directory shape because the driver resolves its
# renderer through `$(dirname "${BASH_SOURCE[0]}")/lib/` -- a flat copy would
# fail to source and every row would report a spurious RED that is a
# missing-file crash rather than a caught defect.
SUT="$WORK/sut"
mkdir -p "$SUT/lib" || exit 2
DRIVER="$SUT/merge-kb-index.sh"
RENDER="$SUT/lib/kb-index-render.sh"
cp "$TRACKED_DRIVER" "$DRIVER" || { printf 'FATAL: cp driver failed\n' >&2; exit 2; }
cp "$TRACKED_RENDER" "$RENDER" || { printf 'FATAL: cp renderer failed\n' >&2; exit 2; }
cp "$DRIVER" "$PRISTINE_DRIVER" || { printf 'FATAL: cp driver failed\n' >&2; exit 2; }
cp "$RENDER" "$PRISTINE_RENDER" || { printf 'FATAL: cp renderer failed\n' >&2; exit 2; }

restore() {
  cp "$PRISTINE_DRIVER" "$DRIVER" || { printf 'FATAL: restore driver failed\n' >&2; exit 2; }
  cp "$PRISTINE_RENDER" "$RENDER" || { printf 'FATAL: restore renderer failed\n' >&2; exit 2; }
}
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

# --- fixtures (built ONCE from the pristine renderer) --------------------------
mk() {
  # mk <out> <rel>TAB<title>...
  local out="$1"; shift
  local tsv="$F/.tsv"
  : > "$tsv"
  local r; for r in "$@"; do printf '%s\n' "$r" >> "$tsv"; done
  LC_ALL=C sort -o "$tsv" "$tsv"
  ( source "$PRISTINE_RENDER"; kb_render_index "$tsv" )> "$out"
}
A_ROW="$(printf 'engineering/alpha.md\tAlpha')"
B_ROW="$(printf 'project/beta.md\tBeta')"
G_ROW="$(printf 'engineering/gamma.md\tGamma')"
D_ROW="$(printf 'project/delta.md\tDelta')"

mk "$F/base.O" "$A_ROW" "$B_ROW"
mk "$F/add.A"  "$A_ROW" "$B_ROW" "$G_ROW"
mk "$F/add.B"  "$A_ROW" "$B_ROW" "$D_ROW"
mk "$F/want"   "$A_ROW" "$B_ROW" "$G_ROW" "$D_ROW"
mk "$F/del.A"  "$A_ROW"
mk "$F/wantdel" "$A_ROW"
mk "$F/re.O"   "$A_ROW"
mk "$F/re.A"   "$(printf 'engineering/alpha.md\tOurs')"
mk "$F/re.B"   "$(printf 'engineering/alpha.md\tTheirs')"
mk "$F/two.A"  "$A_ROW" "$(printf 'engineering/new.md\tOurNew')"
mk "$F/two.B"  "$A_ROW" "$(printf 'engineering/new.md\tTheirNew')"
# THREE fixtures, on three DIRECTIONS of the containment transform. `../../.env`
# alone is the one shape insensitive to BOTH loosenings of `case "/$rel/"`:
# dropping the leading slash still catches it (it holds an interior `/../`), and
# so does dropping the trailing one. Measured: with only that fixture, the
# one-character mutation `case "/$rel/"` -> `case "$rel/"` accepts `../.env` and
# `../secrets` with all four suites green. A first-position and a final-position
# `..` bracket the transform instead of sitting inside it.
mk "$F/esc.B"  "$A_ROW" "$(printf '../../.env\tEscape')"
mk "$F/escLead.B" "$A_ROW" "$(printf '../.env\tLeadingEscape')"
mk "$F/escTail.B" "$A_ROW" "$(printf 'engineering/..\tTrailingEscape')"
mk "$F/abs.B"  "$A_ROW" "$(printf '/etc/passwd\tAbsolute')"
# A corrupt ancestor: a header count that no row set can produce.
sed 's/^> Total files: .*/> Total files: 99/' "$F/base.O" > "$F/corrupt.O"
# CRLF: not a canonical generated index. Round-trip validation rejects it; see P9.
sed 's/$/\r/' "$F/add.B" > "$F/crlf.B"
# An over-long physical row, and it must be a CANONICAL render or this fixture
# tests nothing: an over-long row simply APPENDED to a rendered index is
# out of sort order, so round-trip validation rejects the file whether or not
# the byte cap exists, and the cap's mutation row survives. The over-length
# therefore lives in the TITLE, with a rel that sorts into its proper place.
HUGE_TITLE="$(head -c 9000 /dev/zero | tr '\0' 'x')"
mk "$F/huge.B" "$A_ROW" "$B_ROW" "$(printf 'engineering/huge.md\t%s' "$HUGE_TITLE")"

run_driver() {
  # run_driver <O> <A-source> <B> <P>  -> echoes "<rc> <sentinel-count> <apath>"
  local o="$1" asrc="$2" b="$3" p="$4"
  local a="$WORK/A.$RANDOM"
  cp "$asrc" "$a"
  local rc=0
  bash "$DRIVER" "$o" "$a" "$b" "$p" >/dev/null 2>&1 || rc=$?
  local sc
  sc="$(grep -c '^<<<<<<< kb-index' "$a" 2>/dev/null || true)"
  printf '%s %s %s' "$rc" "${sc:-0}" "$a"
}

PROBE_FAIL=0
probe_fail() { PROBE_FAIL=$((PROBE_FAIL + 1)); printf '      probe: %s\n' "$1" >> "$WORK/probe.log"; }

# The probe returns 0 only if EVERY property holds. Each property is
# independently checked so that any single mutation flips the verdict, and each
# names what it is protecting rather than just what it compares.
probe() {
  PROBE_FAIL=0
  : > "$WORK/probe.log"
  local out rc sc a

  # P1 — the common case resolves cleanly and matches the canonical render.
  out="$(run_driver "$F/base.O" "$F/add.A" "$F/add.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" == 0 ]] || probe_fail "P1 clean two-sided add should exit 0 (got $rc)"
  cmp -s "$a" "$F/want" || probe_fail "P1 merged output is not the canonical render"

  # P2 — a foreign %P is refused, loudly.
  # The refusal must exit non-zero AND leave the file untouched. Writing a
  # sentinel here would PERFORM the denial of service the %P check prevents: git
  # writes %A into the working tree even on a non-zero driver exit, so one
  # committed `* merge=kb-index` line would prepend a text line to every file in
  # every merge, corrupting binaries with a UTF-8 prefix. An earlier revision of
  # this property asserted the opposite and pinned that defect.
  out="$(run_driver "$F/base.O" "$F/add.A" "$F/add.B" some/other/path.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P2 a foreign %P should be refused"
  [[ "$sc" == 0 ]] || probe_fail "P2 the refusal must NOT write to a path this driver does not own (got $sc)"
  cmp -s "$a" "$F/add.A" || probe_fail "P2 the refused file must be left byte-identical"

  # P3 — a corrupt input fails round-trip validation, loudly.
  out="$(run_driver "$F/corrupt.O" "$F/add.A" "$F/add.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P3 a corrupt ancestor should be rejected"
  [[ "$sc" == 1 ]] || probe_fail "P3 rejection should write exactly one sentinel (got $sc)"

  # P4 — a rel escaping knowledge-base/ is rejected even though it round-trips.
  local esc
  for esc in esc escLead escTail; do
    out="$(run_driver "$F/base.O" "$F/add.A" "$F/${esc}.B" knowledge-base/INDEX.md)"
    read -r rc sc a <<<"$out"
    [[ "$rc" != 0 ]] || probe_fail "P4[$esc] an escaping rel should be rejected"
    [[ "$sc" == 1 ]] || probe_fail "P4[$esc] rejection should write exactly one sentinel (got $sc)"
  done

  # P5 — an absolute rel is rejected.
  out="$(run_driver "$F/base.O" "$F/add.A" "$F/abs.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P5 an absolute rel should be rejected"

  # P6 — a two-sided retitle refuses rather than picking a side.
  out="$(run_driver "$F/re.O" "$F/re.A" "$F/re.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P6 a two-sided retitle should refuse"

  # P7 — a two-sided ADD of one rel with differing titles refuses. Distinct from
  # P6: this rel is absent from the ancestor, so the retitle branch never sees it.
  out="$(run_driver "$F/re.O" "$F/two.A" "$F/two.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P7 a two-sided add with differing titles should refuse"

  # P8 — a row deleted on one side stays deleted; the other side's untouched row
  # must not resurrect it.
  out="$(run_driver "$F/base.O" "$F/del.A" "$F/base.O" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" == 0 ]] || probe_fail "P8 add-vs-delete should resolve (got $rc)"
  cmp -s "$a" "$F/wantdel" || probe_fail "P8 a deleted row was resurrected"

  # P9 — a CRLF side does not split the rel-keyed set into duplicate rows.
  # P9 — a CRLF side is REJECTED, not silently absorbed. A CRLF file is not a
  # canonical generated index, and round-trip validation is what catches it: the
  # re-render uses LF, so the byte-compare fails before the set arithmetic could
  # ever see a CR-suffixed rel.
  out="$(run_driver "$F/base.O" "$F/add.A" "$F/crlf.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P9 a CRLF side should be rejected"
  [[ "$sc" == 1 ]] || probe_fail "P9 rejection should write exactly one sentinel (got $sc)"

  # P11 — an over-long physical line is refused rather than read into memory.
  out="$(run_driver "$F/base.O" "$F/add.A" "$F/huge.B" knowledge-base/INDEX.md)"
  read -r rc sc a <<<"$out"
  [[ "$rc" != 0 ]] || probe_fail "P11 an over-long row should be refused"
  [[ "$sc" == 1 ]] || probe_fail "P11 refusal should write exactly one sentinel (got $sc)"

  # P10 — an UNHANDLED failure still writes the sentinel. This is the only
  # property that reaches the ERR trap: every other failure above routes through
  # an explicit `die`, which writes the sentinel by hand, so the trap survived
  # its own mutation row until this property existed. A broken TMPDIR kills the
  # driver at `mktemp -d`, before any validation runs and with no `die` on the
  # path — which is the shape of every adversarial-input crash the trap is there
  # to cover.
  local a10="$WORK/A.unhandled.$RANDOM"
  cp "$F/add.A" "$a10"
  local rc10=0
  TMPDIR="$WORK/definitely-not-a-directory" bash "$DRIVER" \
    "$F/base.O" "$a10" "$F/add.B" knowledge-base/INDEX.md >/dev/null 2>&1 || rc10=$?
  [[ "$rc10" != 0 ]] || probe_fail "P10 an unhandled failure should exit non-zero"
  local sc10
  sc10="$(grep -c '^<<<<<<< kb-index' "$a10" 2>/dev/null || true)"
  [[ "${sc10:-0}" == 1 ]] || probe_fail "P10 the ERR trap should still write the sentinel (got ${sc10:-0})"

  # P12 — an unhandled failure INSIDE A FUNCTION still writes the sentinel.
  #
  # A DIFFERENT PROPERTY FROM P10, AND THE DISTINCTION IS THE WHOLE POINT. P10's
  # trigger (a broken TMPDIR killing `mktemp -d`) sits at the driver's TOP LEVEL,
  # where bash runs an ERR trap whether or not errtrace is set. Every line of the
  # driver's parsing, validation and rendering runs inside a FUNCTION, where an
  # ERR trap fires ONLY under `set -E`. So P10 passes with or without the `E`,
  # and without this property the G13 mutation below survives — which is exactly
  # what happened: the driver shipped without `-E`, and an unhandled failure in
  # `parse_index` produced rc=1 with ZERO sentinel lines, reproducing inside its
  # own fix the markerless-conflict defect the trap exists to prevent.
  #
  # The trigger is an input that passes the driver's `-f` test and then fails the
  # `<` redirect inside parse_index. The precondition is VERIFIED, not assumed:
  # if the harness can still read the file (running as root, or a filesystem that
  # ignores the mode) the property is not exercisable here, and it says so
  # loudly rather than reporting clean over an unmeasured axis.
  local unreadable="$WORK/unreadable.$RANDOM"
  cp "$F/add.B" "$unreadable"
  chmod 000 "$unreadable" 2>/dev/null || true
  if head -c 1 "$unreadable" >/dev/null 2>&1; then
    probe_fail "P12 NOT EXERCISABLE — the fixture stayed readable (root?); the errtrace axis is UNMEASURED"
  else
    local a12="$WORK/A.fnscope.$RANDOM"
    cp "$F/add.A" "$a12"
    local rc12=0
    bash "$DRIVER" "$F/base.O" "$a12" "$unreadable" knowledge-base/INDEX.md >/dev/null 2>&1 || rc12=$?
    [[ "$rc12" != 0 ]] || probe_fail "P12 an unreadable input should fail closed"
    local sc12
    sc12="$(grep -c '^<<<<<<< kb-index' "$a12" 2>/dev/null || true)"
    [[ "${sc12:-0}" == 1 ]] || probe_fail "P12 a FUNCTION-SCOPE unhandled failure must still write the sentinel (got ${sc12:-0}) — is errtrace set?"
  fi
  chmod 644 "$unreadable" 2>/dev/null || true

  (( PROBE_FAIL == 0 ))
}

PASS=0; FAIL=0
declare -a RESULTS=()

printf '=== control (unmutated) ===\n'
if probe; then
  printf '  GREEN — baseline valid\n'
else
  printf 'FATAL: unmutated control is RED. Every row below would be meaningless.\n' >&2
  cat "$WORK/probe.log" >&2
  exit 2
fi

apply() {
  local id="$1" target="$2" expect="$3" desc="$4"
  restore
  if ! python3 "$M/$id.py" "$target" 2>"$WORK/mut.err"; then
    printf '  %-4s LANDING-FAILED (mutator errored: %s)\n' "$id" "$(tail -1 "$WORK/mut.err")"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local pristine
  case "$target" in
    "$DRIVER") pristine="$PRISTINE_DRIVER" ;;
    "$RENDER") pristine="$PRISTINE_RENDER" ;;
    *) printf '  %-4s FATAL: unknown target\n' "$id"; FAIL=$((FAIL+1)); return ;;
  esac
  if diff -q "$pristine" "$target" >/dev/null 2>&1; then
    printf '  %-4s LANDING-FAILED (file unchanged) — %s\n' "$id" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local got
  if probe; then got="GREEN"; else got="RED"; fi
  if [[ "$got" == "$expect" ]]; then
    printf '  %-4s %-5s (want %-5s) ok       — %s\n' "$id" "$got" "$expect" "$desc"
    PASS=$((PASS+1)); RESULTS+=("$id ok")
  else
    printf '  %-4s %-5s (want %-5s) SURVIVED — %s\n' "$id" "$got" "$expect" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id SURVIVED")
  fi
}

# --- mutators (quoted heredocs disable every bash expansion inside) ------------

cat > "$M/G1.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '[[ "$P" == "$EXPECTED_PATH" ]] || refuse'
assert old in s, "G1 anchor missing"
open(p, 'w').write(s.replace(old, '[[ "$P" == "$P" ]] || refuse', 1))
MUT

cat > "$M/G2.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  cmp -s "$rendered" "$src" || die'
assert old in s, "G2 anchor missing"
open(p, "w").write(s.replace(old, '  cmp -s "$rendered" "$src" || true # die', 1))
PY

cat > "$M/G3.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = """    case "/$rel/" in
      */../*) die "rel '$rel' escapes knowledge-base/ via a .. segment" ;;
    esac
"""
assert old in s, "G3 anchor missing"
open(p, "w").write(s.replace(old, "", 1))
PY

cat > "$M/G4.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    [[ "$rel" != /* ]] || die "absolute rel'
assert old in s, "G4 anchor missing"
open(p, "w").write(s.replace(old, '    [[ "$rel" == "$rel" ]] || die "absolute rel', 1))
PY

cat > "$M/G5.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''    else
      die "both sides retitled '$rel' differently; refusing to pick one"
    fi'''
assert old in s, "G5 anchor missing"
new = '''    else
      merged["$rel"]="$t_a"
    fi'''
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/G6.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''      else
        die "'$rel' was added on both sides with different titles; refusing to pick one"
      fi'''
assert old in s, "G6 anchor missing"
new = '''      else
        merged["$rel"]="${ours[$rel]}"
      fi'''
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/G7.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = "trap 'write_sentinel"
assert old in s, "G7 anchor missing"
# The trap is the MECHANISM; removing it must expose the unhandled paths a
# hand-placed sentinel write cannot reach. Every `die` call site stays intact,
# which is what makes this row discriminating rather than redundant.
i = s.index(old); j = s.index("' ERR", i) + len("' ERR")
open(p, 'w').write(s[:i] + "trap - ERR" + s[j:])
MUT

cat > "$M/G8.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'write_sentinel() {\n  local reason='
assert old in s, "G8 anchor missing"
# Neuter the sentinel WRITER to a no-op while leaving every caller intact, so
# only the write is removed and not the failure detection around it.
open(p, 'w').write(s.replace(old, 'write_sentinel() {\n  return 0\n  local reason=', 1))
MUT

cat > "$M/G9.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = """    if [[ "$in_a" != 1 || "$in_b" != 1 ]]; then
      continue
    fi"""
assert old in s, "G9 anchor missing"
# Resurrect a row that one side deleted: the union-flavoured mistake.
new = """    if [[ "$in_a" != 1 && "$in_b" != 1 ]]; then
      continue
    fi
    if [[ "$in_a" != 1 ]]; then merged["$rel"]="${theirs[$rel]}"; continue; fi
    if [[ "$in_b" != 1 ]]; then merged["$rel"]="${ours[$rel]}"; continue; fi"""
open(p, "w").write(s.replace(old, new, 1))
PY

cat > "$M/G10.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "done | LC_ALL=C sort > \"$OUT_TSV\""
assert old in s, "G10 anchor missing"
# Bash associative-array iteration order is a hash order, so dropping the sort
# does not merely change the locale collation -- it emits rows in an arbitrary
# order that no generator would produce.
open(p, "w").write(s.replace(old, "done > \"$OUT_TSV\"", 1))
PY

cat > "$M/G11.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  printf '> Total files: %s\\n' \"$total\""
assert old in s, "G11 anchor missing"
# RENDERER DRIFT. The driver copy stays pristine; only the shared renderer moves.
# Round-trip validation must catch it, because the inputs were rendered by the
# ORIGINAL renderer and no longer re-render to themselves.
open(p, "w").write(s.replace(old, "  printf '> Total indexed files: %s\\n' \"$total\"", 1))
PY

cat > "$M/G12.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    (( ${#line} <= MAX_LINE_BYTES )) || die'
assert old in s, "G12 anchor missing"
# Remove the memory bound on adversarial input. The over-long row still parses
# and still round-trips, so only the cap's absence can flip the probe.
open(p, 'w').write(s.replace(old, '    (( 1 )) || die', 1))
MUT

cat > "$M/G13.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'set -Eeuo pipefail'
assert old in s, "G13 anchor missing"
# Drop errtrace ONLY. Every `die` call site stays intact, so the only thing this
# can break is the ERR trap's reach into functions -- which is precisely why the
# trap is the mechanism and the `die` calls are defence in depth.
open(p, 'w').write(s.replace(old, 'set -euo pipefail', 1))
MUT

cat > "$M/H1.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
# HARNESS SELF-TEST, and it targets the DRIVER so the battery's own plumbing is
# what is under test: delete the driver's entire merge body so it produces
# nothing at all. A probe that still reports GREEN here is not measuring the
# driver, and every row above it would be meaningless.
old = 'kb_render_index "$OUT_TSV" > "$WORKDIR/merged.md"\ncat "$WORKDIR/merged.md" > "$A"\nexit 0'
assert old in s, "H1 anchor missing"
open(p, "w").write(s.replace(old, 'exit 0', 1))
PY

printf '=== driver mutations ===\n'
apply G1  "$DRIVER" RED '%P validation removed — any path is accepted'
apply G2  "$DRIVER" RED 'round-trip validation no longer fails closed'
apply G3  "$DRIVER" RED '.. containment check removed'
apply G4  "$DRIVER" RED 'absolute-rel check removed'
apply G5  "$DRIVER" RED 'a two-sided retitle silently takes ours'
apply G6  "$DRIVER" RED 'a two-sided add silently takes ours'
apply G7  "$DRIVER" RED 'the ERR trap is removed — unhandled paths write no sentinel'
apply G8  "$DRIVER" RED 'the sentinel writer is neutered to a no-op'
apply G9  "$DRIVER" RED 'a row deleted on one side is resurrected'
apply G10 "$DRIVER" RED 'LC_ALL=C sort dropped — rows emit in hash order'
apply G12 "$DRIVER" RED 'the 8 KB physical-line cap is removed'
apply G13 "$DRIVER" RED 'errtrace dropped — the ERR trap stops reaching functions'

printf '=== shared-renderer drift ===\n'
apply G11 "$RENDER" RED 'the renderer header changes while the driver stays pristine'

printf '=== harness self-test ===\n'
apply H1  "$DRIVER" RED 'the driver writes no output at all'

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

# Reported by direct printf and its OWN exit, never through the FAIL counter the
# rows above increment: a floor that shares a lifetime with what it guards is
# not a floor.
EXPECTED_ROWS=14
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$PRISTINE_DRIVER" "$DRIVER" >/dev/null 2>&1 \
   || ! diff -q "$PRISTINE_RENDER" "$RENDER" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the tree to pristine\n' >&2
  exit 1
fi
printf '  restore verified clean (copies under %s; the tracked files were never written)\n' "$SUT" 
if (( FAIL > 0 )); then exit 1; fi
exit 0
