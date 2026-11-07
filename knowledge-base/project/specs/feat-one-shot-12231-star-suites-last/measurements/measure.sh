#!/usr/bin/env bash
# measure.sh <name> <tree-commit> [--fifo] — ONE cold reading of the local affected gate on the pinned diff (Ref #12013).
#
# Method (a measurement method only; it bypasses nothing in a ship path):
#   - Fresh `git clone` of the repository into its OWN directory (own git-common-dir, so the advisory lock is its own and the
#     pool engages; empty per-clone derive cache, so cold). The two node_modules directories are symlinked from the source
#     worktree so the web-platform arm engages. A clone is never reused: a second reading gets a second clone.
#   - `origin/main` in the clone is set to <tree-commit>, so a runner edit is part of the base and the gate is not degraded
#     to a full run.
#   - Pinned diff: the files commit 7af192071d touched (web-platform, 8 files). Files it ADDED are removed; files it MODIFIED are
#     restored to that commit's parent content. Committed on top of <tree-commit>. Expected: AFFECTED_SUMMARY selected=162 of=740.
#   - Command: env -u CI SOLEUR_TEST_JOBS=4 TEST_TIMING_LOG=<f> bash scripts/test-all.sh --affected, run under nice -n 10,
#     every output line stamped with the seconds since start. --fifo sets SOLEUR_PJ_FIFO=1 (the strict-FIFO A/B control).
#   - Disturbance guard: the reading ABORTS before it starts when the 1-minute load average is above MAX_LOAD1 (default 9.0) or
#     when ANY other test-all.sh run is live on the host (a foreign run shares the CPU and the advisory lock). The same two
#     facts are recorded at the end; a reading whose end state is bad is printed as DISTURBED, not as a result.
#   - Nothing may edit the source worktree's runner or batteries while a reading runs.
# Output dir: /var/tmp/m12231/<name>/ (run.log stamped, rc, start.txt, end.txt, clone/). One summary line is printed per reading.
set -uo pipefail

NAME="${1:?name}"; TREE="${2:?tree commit}"; FIFO=0; [[ "${3:-}" == "--fifo" ]] && FIFO=1
SRC_WT="${SRC_WT:-/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12231-star-suites-last}"
BARE="${BARE:-/data/git-repositories/jikig-ai/soleur}"
PIN="${PIN:-7af192071d}"
MAX_LOAD1="${MAX_LOAD1:-9.0}"
O="/var/tmp/m12231/$NAME"
[[ ! -e "$O" ]] || { echo "ABORT: $O exists (a clone is never reused)"; exit 2; }
mkdir -p "$O" || exit 2

foreign_runs() {  # one line per live test-all.sh run (pid, cwd) other than a reading's own clone
  local p cwd args
  for p in /proc/[0-9]*; do
    args="$(tr '\0' ' ' <"$p/cmdline" 2>/dev/null)" || continue
    case "$args" in
      *"bash scripts/test-all.sh"*|*"bash "*"/scripts/test-all.sh"*) ;;
      *) continue ;;
    esac
    cwd="$(readlink "$p/cwd" 2>/dev/null)" || continue
    [[ "$cwd" == "$O/clone"* ]] && continue
    echo "${p#/proc/} $cwd"
  done
}

load1="$(cut -d' ' -f1 /proc/loadavg)"
fr="$(foreign_runs | sort -u)"
{
  echo "name=$NAME tree=$TREE fifo=$FIFO"
  echo "loadavg_start=$(cut -d' ' -f1-3 /proc/loadavg)"
  date -u +%FT%TZ
  echo "foreign_test_all_start: ${fr:-none}"
} >"$O/start.txt"
if awk -v l="$load1" -v m="$MAX_LOAD1" 'BEGIN{exit !(l>m)}'; then
  echo "ABORT $NAME: load1=$load1 > $MAX_LOAD1 at start"; echo ABORTED >"$O/rc"; exit 3
fi
if [[ -n "$fr" ]]; then
  echo "ABORT $NAME: foreign test-all.sh run(s) live: $(tr '\n' ';' <<<"$fr")"; echo ABORTED >"$O/rc"; exit 3
fi

C="$O/clone"
git clone -q --no-checkout "$BARE" "$C" || { echo "ABORT: clone failed"; exit 2; }
cd "$C" || exit 2
git checkout -q --detach "$TREE" || { echo "ABORT: cannot check out $TREE"; exit 2; }
git update-ref refs/remotes/origin/main "$TREE"
ln -s "$SRC_WT/node_modules" node_modules
ln -s "$SRC_WT/apps/web-platform/node_modules" apps/web-platform/node_modules
git config user.email measure@invalid
git config commit.gpgsign false
# the pinned diff: added files removed, modified files restored to the pin's parent content
while IFS=$'\t' read -r st f; do
  case "$st" in
    A) git rm -q -f --ignore-unmatch -- "$f" ;;
    M) git checkout -q "$PIN^" -- "$f" ;;
  esac
done < <(git diff --name-status "$PIN^" "$PIN" | awk '{ if ($1=="A"||$1=="M") { st=$1; $1=""; sub(/^ /,""); print st "\t" $0 } }')
LEFTHOOK=0 git commit -q --no-verify -m "measure: pinned diff of $PIN" || { echo "ABORT: pinned-diff commit empty"; exit 2; }

T0=${EPOCHREALTIME/./}
export TEST_TIMING_LOG="$O/timing.tsv"
[[ "$FIFO" == 1 ]] && export SOLEUR_PJ_FIFO=1
(
  env -u CI SOLEUR_TEST_JOBS=4 nice -n 10 bash scripts/test-all.sh --affected 2>&1
  echo "$?" >"$O/rc.raw"
) | while IFS= read -r l; do
  e=$(( (${EPOCHREALTIME/./} - T0) / 1000 ))
  printf '%d.%03d %s\n' $((e / 1000)) $((e % 1000)) "$l"
done >"$O/run.log"
# the rc is the runner's own (written inside the subshell, never the pipeline's)
cat "$O/rc.raw" >"$O/rc" 2>/dev/null || echo UNKNOWN >"$O/rc"

fr_end="$(foreign_runs | sort -u)"
{
  echo "loadavg_end=$(cut -d' ' -f1-3 /proc/loadavg)"
  date -u +%FT%TZ
  echo "foreign_test_all_end: ${fr_end:-none}"
} >"$O/end.txt"
disturbed=""
[[ -n "$fr_end" ]] && disturbed=" DISTURBED(foreign test-all.sh live at end)"
wall="$(tail -1 "$O/run.log" | awk '{print int($1)}')"
echo "READING $NAME rc=$(cat "$O/rc") wall_s=$wall load_start=$load1 load_end=$(cut -d' ' -f1 /proc/loadavg)$disturbed"
