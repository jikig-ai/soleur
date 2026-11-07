#!/usr/bin/env bash
# site_cost_run.sh <rep> — ONE site-cost reading of the three ci-pr-affected-replay arms (Ref #12013).
#
# Method (measurement only; it bypasses nothing in a ship path):
#   - Fresh `git clone` of the repository into its own directory, detached at $TREE (the exact commit under test), then the
#     uncommitted stamp hook rows-range-site-cost-hook.patch is applied INSIDE the clone. The tree under test is never edited.
#   - The three arms (ranges read from scripts/ci-oracle-lane-suites.txt of the clone, never hard-coded) run CONCURRENTLY and
#     standalone, each with its own TMPDIR and its own SITE_COST_LOG, under `nice -n 10 env -u CI`.
#   - Stamp files: line "0" at the end of arg parsing, "k" at the gate of site k, "EOF" at the entry of the end-of-file gate.
#     site_cost_table.py turns them into per-site costs.
#   - Disturbance guard (rejection rule of the plan): the reading ABORTS before it starts (rc 3) when load1 is above MAX_LOAD1
#     (default 9.0) or when any other test-all.sh / replay-arm run is live; the same facts are recorded at the end plus the
#     maximum load1 seen while the arms ran (informational). guard.txt ends in CLEAN or DISTURBED.
# Env: TREE (required, a commit), SC_SRC (repo to clone; default the soleur repo), SC_SRC_WT (worktree whose node_modules are
#      linked), SC_OUT_ROOT (default /var/tmp/m12013), MAX_LOAD1, SC_LOAD1_OVERRIDE (synthetic load, used to exercise the guard),
#      SC_ONLY_ARM_ROWS (smoke: "<A-B>" runs ONE arm named smoke with that range).
# Output dir: $SC_OUT_ROOT/<rep>/ (never reused): <arm>.stamps.tsv <arm>.rc <arm>.wall <arm>.out guard.txt clone/ tmp-<arm>/
set -uo pipefail

REP="${1:?usage: site_cost_run.sh <rep>}"
[[ "$REP" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ABORT: rep must match [A-Za-z0-9._-]+"; exit 2; }
TREE="${TREE:?TREE must name the commit under test}"
SC_SRC="${SC_SRC:-/data/git-repositories/jikig-ai/soleur}"
SC_SRC_WT="${SC_SRC_WT:-}"
SC_OUT_ROOT="${SC_OUT_ROOT:-/var/tmp/m12013}"
MAX_LOAD1="${MAX_LOAD1:-9.0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/rows-range-site-cost-hook.patch"
case "$SC_OUT_ROOT" in /*) ;; *) echo "ABORT: SC_OUT_ROOT must be absolute (got '$SC_OUT_ROOT')"; exit 2 ;; esac
[[ -f "$PATCH" ]] || { echo "ABORT: patch $PATCH missing"; exit 2; }
# Canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh); the relative-path ratchet recognises only this
# executed statement before a write into the output root.
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

O="$SC_OUT_ROOT/$REP"
assert_fixture_dir "$O"
[[ ! -e "$O" ]] || { echo "ABORT: $O exists (an output dir is never reused)"; exit 2; }
mkdir -p "$SC_OUT_ROOT" && mkdir -m 700 "$O" || exit 2

# One reading at a time on the host: two readings that pass the start guard within seconds of each other disturb each other
# (r2 and r3 of the first attempt did exactly that, and the later one finished before the earlier one looked). The lock is
# held for the life of this script, and a second instance aborts with rc 3 like any other disturbance.
assert_fixture_dir "$SC_OUT_ROOT"
exec 9>"$SC_OUT_ROOT/.reading.lock"
if ! flock -n 9; then
  echo "ABORT $REP: another site-cost reading holds $SC_OUT_ROOT/.reading.lock"; echo "DISTURBED (concurrent reading)" >"$O/guard.txt"; exit 3
fi

live_runs() {  # one line per live test-all.sh or replay-arm run whose cwd is not this reading's clone
  local p cwd args
  for p in /proc/[0-9]*; do
    args="$(tr '\0' ' ' 2>/dev/null <"$p/cmdline")" || continue
    case "$args" in
      *"bash scripts/test-all.sh"*|*"bash "*"/scripts/test-all.sh"*) ;;
      *"bash plugins/soleur/test/ci-pr-affected-replay.test.sh"*) ;;
      *) continue ;;
    esac
    cwd="$(readlink "$p/cwd" 2>/dev/null)" || continue
    [[ "$cwd" == "$O/clone"* ]] && continue
    echo "${p#/proc/} $cwd"
  done
}

assert_fixture_dir "$O"   # re-asserted after the last function head: the ratchet bounds a guard window at the enclosing function head
load1="${SC_LOAD1_OVERRIDE:-$(cut -d' ' -f1 /proc/loadavg)}"
fr="$(live_runs | sort -u)"
{
  echo "rep=$REP tree=$TREE"
  echo "loadavg_start=$(cut -d' ' -f1-3 /proc/loadavg) load1_used=$load1 max_load1=$MAX_LOAD1"
  date -u +%FT%TZ
  echo "foreign_runs_start: ${fr:-none}"
} >"$O/guard.txt"
if awk -v l="$load1" -v m="$MAX_LOAD1" 'BEGIN{exit !(l>m)}'; then
  echo "ABORT $REP: load1=$load1 > $MAX_LOAD1 at start"; echo DISTURBED >>"$O/guard.txt"; exit 3
fi
if [[ -n "$fr" ]]; then
  echo "ABORT $REP: foreign run(s) live: $(tr '\n' ';' <<<"$fr")"; echo DISTURBED >>"$O/guard.txt"; exit 3
fi

C="$O/clone"
git clone -q --no-checkout "$SC_SRC" "$C" || { echo "ABORT: clone failed"; exit 2; }
cd "$C" || exit 2
git checkout -q --detach "$TREE" || { echo "ABORT: cannot check out $TREE"; exit 2; }
git apply "$PATCH" || { echo "ABORT: hook patch does not apply"; exit 2; }
if [[ -n "$SC_SRC_WT" ]]; then
  ln -s "$SC_SRC_WT/node_modules" node_modules || { echo "ABORT: node_modules link failed"; exit 2; }
fi

declare -A ROWS
if [[ -n "${SC_ONLY_ARM_ROWS:-}" ]]; then
  ROWS[smoke]="$SC_ONLY_ARM_ROWS"
else
  for arm in a b c; do
    r="$(awk -F'\t' -v l="plugins/soleur/test/ci-pr-affected-replay-$arm" '$1==l{n=split($2,w," "); print w[n]}' scripts/ci-oracle-lane-suites.txt)"
    [[ "$r" =~ ^[0-9]+-[0-9]+$ ]] || { echo "ABORT: no --rows range for arm $arm in scripts/ci-oracle-lane-suites.txt"; exit 2; }
    ROWS[$arm]="$r"
  done
fi

for arm in "${!ROWS[@]}"; do mkdir -p "$O/tmp-$arm"; echo "${ROWS[$arm]}" >"$O/$arm.range"; done
(  # load sampler: maximum load1 while the arms run (informational)
  mx=0
  while [[ ! -e "$O/.arms-done" ]]; do
    l="$(cut -d' ' -f1 /proc/loadavg)"
    awk -v l="$l" -v m="$mx" 'BEGIN{exit !(l>m)}' && mx="$l"
    echo "$mx" >"$O/.max-load1"
    sleep 15
  done
) &
SAMPLER=$!

pids=()
for arm in "${!ROWS[@]}"; do
  (
    s="$EPOCHREALTIME"
    LC_ALL=C TMPDIR="$O/tmp-$arm" SITE_COST_LOG="$O/$arm.stamps.tsv" \
      nice -n 10 env -u CI -u SOLEUR_PJ_FIFO bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows "${ROWS[$arm]}" >"$O/$arm.out" 2>&1
    rc=$?
    echo "$rc" >"$O/$arm.rc"
    tail -n 1 "$O/$arm.out" >"$O/$arm.passed"
    printf '%s\t%s\n' "$s" "$EPOCHREALTIME" >"$O/$arm.wall"
  ) &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p"; done
: >"$O/.arms-done"
wait "$SAMPLER" 2>/dev/null

fr_end="$(live_runs | sort -u)"
verdict=CLEAN
[[ -n "$fr_end" ]] && verdict=DISTURBED
{
  echo "loadavg_end=$(cut -d' ' -f1-3 /proc/loadavg)"
  echo "max_load1_during=$(cat "$O/.max-load1" 2>/dev/null || echo unknown)"
  date -u +%FT%TZ
  echo "foreign_runs_end: ${fr_end:-none}"
  echo "$verdict"
} >>"$O/guard.txt"
line="READING $REP verdict=$verdict load_start=$load1 max_load1_during=$(cat "$O/.max-load1" 2>/dev/null || echo unknown)"
for arm in "${!ROWS[@]}"; do
  line="$line $arm:rc=$(cat "$O/$arm.rc" 2>/dev/null || echo ?),wall_s=$(awk -F'\t' '{printf "%.1f", $2-$1}' "$O/$arm.wall" 2>/dev/null || echo ?)"
done
echo "$line"
