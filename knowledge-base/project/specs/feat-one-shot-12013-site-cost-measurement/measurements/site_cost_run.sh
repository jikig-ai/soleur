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
#     (default 9.0) or when any other test-all.sh / replay-arm run is live; the same facts are recorded at the end, a sampler notes any
#     foreign run seen WHILE the arms ran (it makes the reading DISTURBED), and the maximum load1 seen is recorded (informational: it
#     includes the reading's own three arms). guard.txt ends in CLEAN or DISTURBED. One reading at a time: an exclusive lock on SC_LOCK.
#     Limits of the guard, stated honestly: it sees only test-all.sh and replay-arm runs spelled `bash scripts/test-all.sh`, `bash */scripts/test-all.sh` or
#     `bash plugins/soleur/test/ci-pr-affected-replay.test.sh`, from users whose cwd it can read, sampled every 15 s (a shorter run can fall between ticks);
#     other CPU load only shows as max_load1_during, which does not gate.
#     (Hardened after readings r4 and r5 were taken: the exit trap, the in-run sightings, the fixed lock path, LC_ALL=C and the arm timeout.)
# Env: TREE (required, a commit), SC_SRC (repo to clone; default the soleur repo), SC_SRC_WT (worktree whose node_modules are
#      linked), SC_OUT_ROOT (default /var/tmp/m12013), SC_LOCK (default /var/tmp/m12013.lock), SC_ARM_TIMEOUT (seconds, default 5400), MAX_LOAD1, SC_LOAD1_OVERRIDE (synthetic load, used to exercise the guard),
#      SC_ONLY_ARM_ROWS (smoke: "<A-B>" runs ONE arm named smoke with that range).
# Output dir: $SC_OUT_ROOT/<rep>/ (never reused): <arm>.stamps.tsv <arm>.rc <arm>.wall <arm>.out guard.txt clone/ tmp-<arm>/
set -uo pipefail
export LC_ALL=C   # the EPOCHREALTIME stamps and the .wall files must use a dot radix whatever the caller's locale

REP="${1:?usage: site_cost_run.sh <rep>}"
[[ "$REP" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ABORT: rep must match [A-Za-z0-9._-]+"; exit 2; }
TREE="${TREE:?TREE must name the commit under test}"
SC_SRC="${SC_SRC:-/data/git-repositories/jikig-ai/soleur}"
SC_SRC_WT="${SC_SRC_WT:-}"
SC_OUT_ROOT="${SC_OUT_ROOT:-/var/tmp/m12013}"
SC_LOCK="${SC_LOCK:-/var/tmp/m12013.lock}"
SC_ARM_TIMEOUT="${SC_ARM_TIMEOUT:-5400}"
MAX_LOAD1="${MAX_LOAD1:-9.0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/rows-range-site-cost-hook.patch"
case "$SC_OUT_ROOT" in /*) ;; *) echo "ABORT: SC_OUT_ROOT must be absolute (got '$SC_OUT_ROOT')"; exit 2 ;; esac
[[ -f "$PATCH" ]] || { echo "ABORT: patch $PATCH missing"; exit 2; }
# The commit under test, resolved once: an option-looking or unknown value is refused here and the guard records the full SHA.
TREE_SHA="$(git -C "$SC_SRC" rev-parse --verify --quiet "${TREE}^{commit}")" || { echo "ABORT: TREE '$TREE' is not a commit of $SC_SRC"; exit 2; }
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
assert_fixture_dir "$SC_LOCK"
exec 9>"$SC_LOCK"
if ! flock -n 9; then
  echo "ABORT $REP: another site-cost reading holds $SC_LOCK"; echo "DISTURBED (concurrent reading)" >"$O/guard.txt"; exit 3
fi

live_runs() {  # one line per live test-all.sh or replay-arm run whose cwd is not under this reading's output dir
  local p cwd args
  for p in /proc/[0-9]*; do
    args="$(tr '\0' ' ' 2>/dev/null <"$p/cmdline")" || continue
    case "$args" in
      *"bash scripts/test-all.sh"*|*"bash "*"/scripts/test-all.sh"*) ;;
      *"bash plugins/soleur/test/ci-pr-affected-replay.test.sh"*) ;;
      *) continue ;;
    esac
    cwd="$(readlink "$p/cwd" 2>/dev/null)" || continue
    [[ "$cwd" == "$O" || "$cwd" == "$O/"* ]] && continue   # this reading's own arms and their fixture subshells (cwd under the clone or a tmp-<arm> dir)
    echo "${p#/proc/} $cwd"
  done
}

descendants() {  # all descendant pids of $1 (ps ppid walk)
  local kids k
  kids="$(ps -eo pid=,ppid= | awk -v p="$1" '$2==p{print $1}')"
  for k in $kids; do echo "$k"; descendants "$k"; done
}

FINISHED=0
cleanup() {
  assert_fixture_dir "$O"   # the ratchet bounds a guard window at the enclosing function head
  : >"$O/.arms-done" 2>/dev/null
  if [[ "$FINISHED" != 1 ]]; then  # killed or aborted mid-reading: stop the sampler and the arms, so no orphan keeps burning the host
    # shellcheck disable=SC2046
    kill $(descendants "$$") 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT   # SIGKILL cannot be trapped: the arms then run to their timeout still holding the lock, which is the right state for a busy host

assert_fixture_dir "$O"   # re-asserted after the last function head: the ratchet bounds a guard window at the enclosing function head
load1="${SC_LOAD1_OVERRIDE:-$(cut -d' ' -f1 /proc/loadavg)}"
fr="$(live_runs | sort -u)"
{
  echo "rep=$REP tree=$TREE_SHA"
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
git checkout -q --detach "$TREE_SHA" || { echo "ABORT: cannot check out $TREE_SHA"; exit 2; }
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

ARM_ORDER="$(printf '%s\n' "${!ROWS[@]}" | sort)"
for arm in $ARM_ORDER; do mkdir -p "$O/tmp-$arm"; echo "${ROWS[$arm]}" >"$O/$arm.range"; done
MAIN=$$
(  # sampler: maximum load1 and any foreign run seen while the arms run; it stops when the arms are done or this script is gone
  mx=0; ticks=0
  while kill -0 "$MAIN" 2>/dev/null && [[ ! -e "$O/.arms-done" ]]; do
    l="$(cut -d' ' -f1 /proc/loadavg)"
    awk -v l="$l" -v m="$mx" 'BEGIN{exit !(l>m)}' && mx="$l"
    echo "$mx" >"$O/.max-load1"
    live_runs >>"$O/.foreign-during"
    ticks=$((ticks + 1)); echo "$ticks" >"$O/.sampler-ticks"
    sleep 15
  done
) 9>&- &
SAMPLER=$!   # not niced on purpose: a niced sampler would be starved exactly when the host is busy; its cost is one /proc scan per 15 s

pids=()
for arm in $ARM_ORDER; do
  (
    s="$EPOCHREALTIME"
    LC_ALL=C TMPDIR="$O/tmp-$arm" SITE_COST_LOG="$O/$arm.stamps.tsv" \
      nice -n 10 timeout -k 30 "$SC_ARM_TIMEOUT" env -u CI -u SOLEUR_PJ_FIFO bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows "${ROWS[$arm]}" >"$O/$arm.out" 2>&1
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

FINISHED=1
fr_end="$(live_runs | sort -u)"
fr_during="$(sort -u "$O/.foreign-during" 2>/dev/null | head -n 5)"
verdict=CLEAN
[[ -n "$fr_end" || -n "$fr_during" ]] && verdict=DISTURBED
# a sampler that never ran (or died) observed nothing: that is not a clean reading
[[ -s "$O/.sampler-ticks" && -s "$O/.max-load1" ]] || verdict=DISTURBED
{
  echo "loadavg_end=$(cut -d' ' -f1-3 /proc/loadavg)"
  echo "max_load1_during=$(cat "$O/.max-load1" 2>/dev/null || echo unknown)"
  date -u +%FT%TZ
  echo "sampler_ticks=$(cat "$O/.sampler-ticks" 2>/dev/null || echo 0)"
  echo "foreign_runs_during: ${fr_during:-none}"
  echo "foreign_runs_end: ${fr_end:-none}"
  echo "$verdict"
} >>"$O/guard.txt"
line="READING $REP verdict=$verdict load_start=$load1 max_load1_during=$(cat "$O/.max-load1" 2>/dev/null || echo unknown)"
bad=0
for arm in $ARM_ORDER; do
  armrc="$(cat "$O/$arm.rc" 2>/dev/null || echo ?)"
  [[ "$armrc" == 0 ]] || bad=1
  line="$line $arm:rc=$armrc,wall_s=$(awk -F'\t' '{printf "%.1f", $2-$1}' "$O/$arm.wall" 2>/dev/null || echo ?)"
done
echo "$line"
[[ "$verdict" == CLEAN && "$bad" == 0 ]] || exit 4
