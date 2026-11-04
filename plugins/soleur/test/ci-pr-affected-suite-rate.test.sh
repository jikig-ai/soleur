#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2034,SC2120,SC1091  # rows are dispatched indirectly; A && B || why is the assertion idiom
# Suite for the `suite-rate` subcommand of scripts/ci-pr-affected-replay.py (#12025): the EXISTING selection rate of every
# suite over the last N first-parent commits, modelled offline from the selector's own edge column.
#
# THE SEAMS. The selector is PR_AFFECTED_REPLAY_TEST_ALL, a stub that prints the real five-column AFFECTED_SELECTED shape
# (label, bit, class, edges) with the bit decided from the path list by plain case patterns, NOT by the model under test
# (the spot-check's independent instrument). `gh` is a PATH stub that records any call: the tool must never reach the network.
# The repository is a synthesized git repo; every path is a synthetic fx/ name because this file is itself an audited suite.
#
# WHAT IS PINNED. R1 rate and denominator (3 of 8 is 37.5; an always_on row is flagged and 100 by definition, never measured).
# R2 runner / not-evaluable / empty commits are counted in their own columns and leave the denominator. R3 a selector failure
# on the spot-check exits non-zero and zero attributable commits exits 1. R4 the header carries window, base sha, the lib blob
# sha (equal to git's own answer for the base) and the caveat; the run writes only under --out; gh was never called.
# MUTATION ROWS copy the SUT and apply ONE edit; the edit must land once, the mutant must parse, the row must be GREEN on the
# pristine SUT and RED on the mutant without a crash. The instrument self-test and the anti-vacuity floor report through
# printf + exit, never through the pass()/fail() pair they backstop.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"   # arms the git-location tripwire and gives git_fixture_env (one list, one builder)
REAL_SUT="$SCRIPT_DIR/../../../scripts/ci-pr-affected-replay.py"
SUT="$REAL_SUT"

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 2
fi
passes=0; fails=0; FAILED=()

[[ -f "$REAL_SUT" ]] || { echo "[FATAL] SUT not found at $REAL_SUT" >&2; exit 2; }
for tool in python3 git; do
  command -v "$tool" >/dev/null || { echo "[FATAL] $tool required" >&2; exit 2; }
done

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

SANDBOX="$(mktemp -d "$TMPDIR/ci-pr-affected-suite-rate.XXXXXXXX")" || { echo "[FATAL] mktemp failed" >&2; exit 2; }
case "$SANDBOX" in /*) : ;; *) echo "[FATAL] sandbox is not absolute" >&2; exit 2 ;; esac
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX"

git_fixture_env "$SANDBOX/repo" || { echo "[FATAL] git_fixture_env refused the sandbox" >&2; exit 2; }
gitq() { git -c commit.gpgsign=false -c maintenance.auto=false -c gc.auto=0 -c init.defaultBranch=main "$@"; }

FX="$SANDBOX/repo"
BIN="$SANDBOX/bin"
OUT="$SANDBOX/out"
GHLOG="$SANDBOX/gh.log"
FIXHOME="$SANDBOX/fixhome"
mkdir -p "$BIN" "$FIXHOME" || { echo "[FATAL] cannot create the stub dirs" >&2; exit 2; }

# ---- the fake repository: a seed, then 8 attributable commits, then runner / not-evaluable / empty last -----------------
build_repo() {
  assert_fixture_dir "$FX"
  mkdir -p "$FX/scripts/lib" "$FX/fx/a" "$FX/fx/b" "$FX/fx/c" || return 1
  (
    cd "$FX" || exit 1
    gitq init -q -b main . || exit 1
    printf 'lib-seed\n' > "$FX/scripts/lib/test-affected-paths.sh"
    printf 'seed\n' > "$FX/README.md"
    gitq add -A && gitq commit -qm seed || exit 1
    n=0
    c1() { n=$((n + 1)); mkdir -p "$(dirname "$FX/$1")"; printf 'v%s\n' "$n" > "$FX/$1"; gitq add -A && gitq commit -qm "u$n $1"; }
    c1 fx/a/one.sh; c1 fx/b/x.txt; c1 fx/b/y.txt; c1 fx/a/one.sh; c1 fx/b/z.txt; c1 fx/c/q.txt; c1 fx/a/one.sh; c1 fx/c/r.txt
    c1 scripts/lib/test-affected-paths.sh
    c1 'fx/c,d.dat'
    gitq commit -q --allow-empty -m "u-empty" || exit 1
    gitq update-ref refs/remotes/origin/main HEAD
  ) || return 1
}
build_repo || { echo "[FATAL] could not build the fixture repo" >&2; exit 2; }
BASE="$(gitq -C "$FX" rev-parse HEAD)"
[[ "$(gitq -C "$FX" rev-list --first-parent --count HEAD)" -eq 12 ]] || { echo "[FATAL] fixture: expected 12 commits" >&2; exit 2; }

cat > "$BIN/sel.sh" <<'SEL'
#!/usr/bin/env bash
# the real selector, stood in for: each row's bit is decided from the path list by plain case patterns, NOT by the model under test.
paths=""
for a in "$@"; do case "$a" in --paths=*) paths="${a#--paths=}" ;; esac; done
[ -n "$paths" ] || { echo "sel-stub: no --paths" >&2; exit 64; }
if [ -n "${PR_AFFECTED_REPLAY_SR_FAIL:-}" ]; then echo "sel-stub: forced failure" >&2; exit 1; fi
a_one=0; case ",$paths," in *,fx/a/one.sh,*) a_one=1 ;; esac
b_dir=0; case ",$paths," in *,fx/b/*) b_dir=1 ;; esac
printf 'AFFECTED_SELECTED\tsA\t%s\tedge:declared\t^fx/a/one.sh\n' "$a_one"
printf 'AFFECTED_SELECTED\tsE\t%s\tedge:declared\t^fx/b/\n' "$b_dir"
printf 'AFFECTED_SELECTED\tsF\t0\tedge:declared\t^fx/never/\n'
printf 'AFFECTED_SELECTED\tsAO\t1\talways_on\t^fx/b/\n'
printf 'AFFECTED_SUMMARY selected=1 of=4 always_on=1 edge=3 fallback=none\n'
SEL
chmod +x "$BIN/sel.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 64\n' "$GHLOG" > "$BIN/gh"; chmod +x "$BIN/gh"
ROWS="$SANDBOX/rows.txt"
{
  printf 'AFFECTED_SELECTED\tsA\t0\tedge:declared\t^fx/a/one.sh\n'
  printf 'AFFECTED_SELECTED\tsE\t0\tedge:declared\t^fx/b/\n'
  printf 'AFFECTED_SELECTED\tsF\t0\tedge:declared\t^fx/never/\n'
  printf 'AFFECTED_SELECTED\tsAO\t1\talways_on\t^fx/b/\n'
  printf 'AFFECTED_SUMMARY selected=1 of=4 always_on=1 edge=3 fallback=none\n'
} > "$ROWS"

RCLOG="$SANDBOX/rc.log"; : > "$RCLOG"
sr_run() {  # sr_run <suite-rate args...>: the subcommand in the fixture repository (selector stubbed); every exit code is logged
  local rc
  ( cd "$FX" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" timeout 60 python3 "$SUT" suite-rate "$@" ); rc=$?
  printf '%s\n' "$rc" >> "$RCLOG"
  return "$rc"
}
sr_main() {  # sr_main [extra args...]: the canonical run; sets SR_RC, writes $OUT, stdout in $SANDBOX/sr.stdout, stderr in $SANDBOX/sr.stderr
  rm -rf "$OUT"
  sr_run --list "$ROWS" --commits "${SR_COMMITS:-11}" --base "$BASE" --out "$OUT" --spot-check "${SR_SPOT:-3}" "$@" >"$SANDBOX/sr.stdout" 2>"$SANDBOX/sr.stderr"
  SR_RC=$?
}
sr_cell() { awk -F'\t' -v s="$1" -v c="$2" 'NR==1{for(i=1;i<=NF;i++) if($i==c) k=i; next} $1==s{print $k}' "$OUT/suite-rate.tsv"; }
hdr() { tr ' ' '\n' < "$OUT/suite-rate.header" | sed -n "s/^$1=//p"; }

chk() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }   # chk <name> <cmd...>
_c_p=$passes; _c_f=$fails; _c_n=${#FAILED[@]}
{ chk "instrument: a true predicate" true; chk "instrument: a false predicate" false; } >/dev/null 2>&1
if [[ "$passes" -ne $((_c_p + 1)) || "$fails" -ne $((_c_f + 1)) || "${#FAILED[@]}" -ne $((_c_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: chk did not record both a pass and a failure\n' >&2; exit 2
fi
passes=$_c_p; fails=$_c_f; if (( _c_n == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:_c_n}"); fi

echo "== suite-rate: rate and denominator, excluded commits, refusals, header and read-only"

row_r1() {   # 3 of 8 attributable commits hit sA and sE; sF never; an always_on row is flagged and 100 by definition
  sr_main; [[ "$SR_RC" -eq 0 ]] || return 1
  [[ "$(sr_cell sA hits)" == 3 && "$(sr_cell sA attributable)" == 8 && "$(sr_cell sA rate_pct)" == 37.5 && "$(sr_cell sA measured)" == yes ]] || return 1
  [[ "$(sr_cell sE hits)" == 3 && "$(sr_cell sE rate_pct)" == 37.5 ]] || return 1
  [[ "$(sr_cell sF hits)" == 0 && "$(sr_cell sF rate_pct)" == 0.0 ]] || return 1
  [[ "$(sr_cell sAO measured)" == no && "$(sr_cell sAO rate_pct)" == 100.0 && "$(sr_cell sAO class)" == always_on ]]
}
row_r2() {   # the runner, not-evaluable and empty commits are counted in their own columns and leave the denominator
  sr_main; [[ "$SR_RC" -eq 0 ]] || return 1
  [[ "$(hdr units)" == 11 && "$(hdr attributable)" == 8 && "$(hdr runner_changed)" == 1 && "$(hdr not_evaluable)" == 1 && "$(hdr empty)" == 1 ]] || return 1
  [[ "$(awk -F'\t' 'NR>1 && $2=="attributable"' "$OUT/commits.tsv" | wc -l)" -eq 8 ]] || return 1
  [[ "$(awk -F'\t' 'NR>1 && $2=="runner"' "$OUT/commits.tsv" | wc -l)" -eq 1 && "$(awk -F'\t' 'NR>1 && $2=="not_evaluable"' "$OUT/commits.tsv" | wc -l)" -eq 1 ]] || return 1
  [[ "$(sr_cell sA attributable)" == 8 ]]
}
row_r3() {   # a selector failure on the spot-check is never "selected nothing"; zero attributable commits exits 1
  PR_AFFECTED_REPLAY_SR_FAIL=1 sr_main; [[ "$SR_RC" -ne 0 && ! -e "$OUT/suite-rate.tsv" ]] || return 1
  SR_COMMITS=3 sr_main; [[ "$SR_RC" -eq 1 && ! -e "$OUT/suite-rate.tsv" ]] && grep -q 'no attributable' "$SANDBOX/sr.stderr"
}
row_r4() {   # the header names window, base, the lib blob sha (git's own answer) and the caveat; only --out is written; gh never called
  local before after want
  before="$(gitq -C "$FX" status --porcelain; gitq -C "$FX" rev-parse HEAD)"
  sr_main; [[ "$SR_RC" -eq 0 ]] || return 1
  after="$(gitq -C "$FX" status --porcelain; gitq -C "$FX" rev-parse HEAD)"
  want="$(gitq -C "$FX" rev-parse "$BASE:scripts/lib/test-affected-paths.sh")"
  [[ -n "$want" && "$(hdr lib_sha)" == "$want" && "$(hdr base)" == "$BASE" && "$(hdr window)" == 11 ]] || return 1
  grep -q 'current-edges-applied-to-older-diffs' "$OUT/suite-rate.header" || return 1
  [[ "$before" == "$after" && "$(find "$OUT" -type f -printf '%f\n' | sort | tr '\n' ' ')" == "commits.tsv suite-rate.header suite-rate.tsv " && ! -e "$GHLOG" ]]
}
row_window() {   # permitted variation: a different window (9 commits = 6 attributable) gives 2 of 6 for sA
  SR_COMMITS=9 sr_main; [[ "$SR_RC" -eq 0 && "$(sr_cell sA hits)" == 2 && "$(sr_cell sA attributable)" == 6 && "$(sr_cell sA rate_pct)" == 33.3 ]]
}
row_help() { python3 "$SUT" --help 2>&1 | grep -q 'suite-rate' && python3 "$SUT" suite-rate --help 2>&1 | grep -q -- '--spot-check'; }

chk "R1: a suite hit by 3 of 8 attributable commits reports 3, 8 and 37.5; an always_on row is flagged and 100 by definition" row_r1
chk "R2: runner, not-evaluable and empty commits are counted in their own columns and leave the denominator" row_r2
chk "R3: a spot-check selector failure and a window with no attributable commit both exit non-zero, never 'selected nothing'" row_r3
chk "R4: the header carries window, base and the lib blob sha, the run writes only under --out, and gh was never called" row_r4
chk "window: a different commit count changes the denominator and the hits (2 of 6)" row_window
chk "help: the subcommand and its --spot-check flag are discoverable" row_help

# ---- mutation harness: copy the SUT, apply ONE edit, require landed + parses + pristine GREEN + mutant RED without a crash ----
MUT_RUN=0; MUT_KILLED=0
mutate() {   # mutate <name> <row-fn> <python-snippet-old> <python-snippet-new>
  local name="$1" rowfn="$2" old="$3" new="$4" mdir="$SANDBOX/mut-$1" cp0
  MUT_RUN=$((MUT_RUN + 1))
  mkdir -p "$mdir" || { fail "mutant $name: cannot create its dir"; return; }
  cp "$REAL_SUT" "$mdir/ci-pr-affected-replay.py"
  if ! python3 - "$mdir/ci-pr-affected-replay.py" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
  then fail "mutant $name: the edit did not land exactly once"; return; fi
  cmp -s "$REAL_SUT" "$mdir/ci-pr-affected-replay.py" && { fail "mutant $name: the mutant is byte-identical to the SUT"; return; }
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$mdir/ci-pr-affected-replay.py" 2>/dev/null || { fail "mutant $name: the mutant does not parse"; return; }
  if ! "$rowfn" >/dev/null 2>&1; then fail "mutant $name: the row is not GREEN on the pristine SUT"; return; fi
  cp0="$SUT"; SUT="$mdir/ci-pr-affected-replay.py"
  if "$rowfn" >/dev/null 2>&1; then SUT="$cp0"; fail "mutant $name SURVIVED: row $rowfn stayed green"; return; fi
  if grep -qE 'Traceback|internal error' "$SANDBOX/sr.stderr" 2>/dev/null; then SUT="$cp0"; fail "mutant $name crashed: a crash is not a kill"; return; fi
  SUT="$cp0"; MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $name killed by $rowfn"
}

mutate drop-exclusion row_r2 'attr = [u for u in units if u[2] == "attributable"]  # sr:attr' 'attr = [u for u in units]  # sr:attr'
mutate always-on-measured row_r1 'measured = cls.startswith("edge:") and bool(edges)  # sr:measured' 'measured = True  # sr:measured'
mutate swallow-spot-check row_r3 'spot_k, spot_cmp = glob_spot_check(root, rows, units, a.spot_check, rows)  # sr:spot' $'try:\n        spot_k, spot_cmp = glob_spot_check(root, rows, units, a.spot_check, rows)\n    except ReadError:\n        spot_k, spot_cmp = 0, 0'
mutate wrong-lib-sha row_r4 '(base_sha, RUNNER_TRIGGERS[1])], cwd=root, check=False)  # sr:lib' '(base_sha, "README.md")], cwd=root, check=False)  # sr:lib'

# ---- controls: the harness itself must report a survivor and an edit that did not land --------------------------------
ctl_harness() {
  local p0=$passes f0=$fails n0=${#FAILED[@]} m0=$MUT_RUN k0=$MUT_KILLED last
  mutate ctl-nolanding row_help 'THIS-TEXT-IS-NOT-IN-THE-SUT-ANYWHERE' 'x' >/dev/null 2>&1
  last="${FAILED[${#FAILED[@]}-1]:-}"
  passes=$p0; fails=$f0; MUT_RUN=$m0; MUT_KILLED=$k0
  if (( n0 == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:n0}"); fi
  [[ "$last" == *"did not land exactly once"* ]]
}
chk "control: an edit that does not land is refused by name, not scored as a kill" ctl_harness

if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

# Anti-vacuity floor, reported through printf + exit so it never rides on the helpers it guards.
FLOOR_ASSERTIONS=12
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, expected at least %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 2
fi
echo "ci-pr-affected-suite-rate.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
