#!/usr/bin/env bash
# Benchmark harness for credential-persist-home-guard.test.sh (#7001).
#
# WHY THIS FILE EXISTS
# ====================
# The sandbox-footprint change in #7001 was justified entirely by measurement, and one of
# its measurements OVERRODE a plan prescription (a `.terraform`-absent fast path the plan
# called "load-bearing, not an optimisation"). Evidence that lives only in a session
# transcript or a PR description is as perishable as uncommitted code — and a source
# comment that says "measured X" while nothing can re-derive X reads as protection while
# asserting a property nothing re-checks. So the harness ships with the change.
#
# Two things this harness exists to get right, both of which the plan's own sequential
# 3-run blocks got wrong:
#
#   1. INTERLEAVING. Comparing arm A (3 runs) then arm B (3 runs) lets thermal drift and
#      sibling load land unevenly on the two arms. `--ab` alternates them run-by-run so
#      any drift hits both equally. The plan's un-interleaved cold-root figure (11.0s for
#      the no-fast-path arm) did not reproduce in ANY of 5 interleaved pairs.
#   2. A DISK-BACKED TMPDIR. The pathology being measured is a ~3.9 GB peak against a
#      4.0 GB tmpfs /tmp. Measuring it on tmpfs lets exhaustion truncate the number being
#      measured. This harness puts TMPDIR under /var/tmp (ext4 here) deliberately.
#
# The suite reads its scan root from CRED_GUARD_INFRA_ROOT, which is what lets this run
# against a synthesized bench root instead of the live infra dir.
#
# USAGE
#   # single arm, warm root (a 162 MB .terraform present — the local-developer shape)
#   ./credential-persist-home-guard.bench.sh --mode warm --runs 3
#
#   # single arm, cold root (no .terraform — the ONLY shape CI ever runs)
#   ./credential-persist-home-guard.bench.sh --mode cold --runs 3
#
#   # interleaved A/B against another revision of the suite (the form that decided #7001)
#   git show origin/main:apps/web-platform/infra/credential-persist-home-guard.test.sh > /var/tmp/base.sh
#   ./credential-persist-home-guard.bench.sh --mode cold --ab /var/tmp/base.sh --runs 5
#
# A warm run needs a populated .terraform. Point --terraform-cache at one, or let the
# harness find any sibling worktree that has run `terraform init`. Never run
# `terraform init` inside the repo worktree to create one — use a scratch copy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SCRIPT_DIR/credential-persist-home-guard.test.sh"
MODE=warm
RUNS=3
AB=""
TF_CACHE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)            MODE="$2"; shift 2 ;;
    --runs)            RUNS="$2"; shift 2 ;;
    --ab)              AB="$2";   shift 2 ;;
    --terraform-cache) TF_CACHE="$2"; shift 2 ;;
    --suite)           SUITE="$2"; shift 2 ;;
    -h|--help)         sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in warm|cold) ;; *) echo "--mode must be warm|cold" >&2; exit 2 ;; esac
[[ -f "$SUITE" ]] || { echo "suite not found: $SUITE" >&2; exit 2; }
[[ -z "$AB" || -f "$AB" ]] || { echo "--ab suite not found: $AB" >&2; exit 2; }

# Locate a warm provider cache for --mode warm. Any sibling worktree that has run
# `terraform init` will do; .terraform is never mutated and never enters a sandbox, so
# hardlinking it into the bench root (cp -al) is safe and keeps setup near-instant.
if [[ "$MODE" == warm && -z "$TF_CACHE" ]]; then
  while IFS= read -r cand; do
    [[ -d "$cand" ]] && { TF_CACHE="$cand"; break; }
  done < <(find "$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir)/.." \
                -maxdepth 5 -type d -path '*/apps/web-platform/infra/.terraform' 2>/dev/null)
fi
if [[ "$MODE" == warm ]]; then
  [[ -n "$TF_CACHE" && -d "$TF_CACHE" ]] || {
    echo "FATAL: --mode warm needs a populated .terraform; none found." >&2
    echo "       Pass --terraform-cache <path>, or run --mode cold." >&2
    echo "       Without it the warm arm is byte-identical to the cold arm and the" >&2
    echo "       before/after delta is meaningless (a silent no-measurement)." >&2
    exit 3
  }
fi

# Disk-backed, NOT /tmp. See header.
ROOT="$(mktemp -d /var/tmp/credbench.XXXXXXXX)"
trap 'rm -rf "$ROOT"' EXIT INT TERM HUP

setup() { # $1 = suite file to install into the bench root
  rm -rf "$ROOT/infra" "$ROOT/tmp"
  mkdir -p "$ROOT/infra" "$ROOT/tmp"
  cp -a "$SCRIPT_DIR/." "$ROOT/infra/"
  rm -rf "$ROOT/infra/.terraform"   # MODE alone decides the shape, never the source tree
  cp "$1" "$ROOT/infra/credential-persist-home-guard.test.sh"
  [[ "$MODE" == warm ]] && cp -al "$TF_CACHE" "$ROOT/infra/.terraform"
  return 0
}

# Peak sampler. `head -1` + digit-scrub is load-bearing: a directory vanishing mid-walk
# makes du emit extra lines, and a partially-written peak file reads back as two lines —
# either shape blows up the arithmetic compare and silently DROPS the sample, which would
# under-report the very peak this harness exists to measure.
timeit() {
  rm -rf "$ROOT/tmp"; mkdir -p "$ROOT/tmp"
  local pf="$ROOT/peak"; echo 0 > "$pf"
  ( while :; do
      c=$(du -sm "$ROOT/tmp" 2>/dev/null | head -1 | cut -f1 | tr -cd '0-9')
      p=$(head -1 "$pf" 2>/dev/null | tr -cd '0-9')
      [[ "${c:-0}" -gt "${p:-0}" ]] && echo "$c" > "$pf"
      sleep 0.2
    done ) & local sampler=$!
  local t0 t1 rc
  t0=$(date +%s.%N)
  TMPDIR="$ROOT/tmp" CRED_GUARD_INFRA_ROOT="$ROOT/infra" \
    bash "$ROOT/infra/credential-persist-home-guard.test.sh" > "$ROOT/out" 2>&1 && rc=0 || rc=$?
  t1=$(date +%s.%N)
  kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true
  LAST_WALL=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
  LAST_PEAK=$(head -1 "$pf" | tr -cd '0-9')
  LAST_RC=$rc
  LAST_SUMMARY=$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' "$ROOT/out" | tail -1 || echo "NO-SUMMARY")
}

med() { printf '%s\n' "$@" | sort -n | awk '{v[NR]=$1} END{print (NR%2)?v[(NR+1)/2]:(v[NR/2]+v[NR/2+1])/2}'; }

echo "mode=$MODE runs=$RUNS suite=$(basename "$SUITE")${AB:+ ab=$(basename "$AB")}"
[[ "$MODE" == warm ]] && echo "terraform-cache=$TF_CACHE ($(du -sm "$TF_CACHE" | cut -f1) MB)"

if [[ -z "$AB" ]]; then
  declare -a W
  for i in $(seq 1 "$RUNS"); do
    setup "$SUITE"; timeit
    echo "  run$i: wall=${LAST_WALL}s peak=${LAST_PEAK}MB rc=$LAST_RC $LAST_SUMMARY"
    W+=("$LAST_WALL")
  done
  echo "MEDIAN wall=$(med "${W[@]}")s"
else
  declare -a A B
  for i in $(seq 1 "$RUNS"); do
    setup "$SUITE"; timeit; a=$LAST_WALL; arc=$LAST_RC; apk=$LAST_PEAK
    setup "$AB";    timeit; b=$LAST_WALL; brc=$LAST_RC; bpk=$LAST_PEAK
    echo "  pair$i: this=${a}s(peak ${apk}MB rc=$arc)  ab=${b}s(peak ${bpk}MB rc=$brc)"
    A+=("$a"); B+=("$b")
  done
  echo "MEDIAN this=$(med "${A[@]}")s   ab=$(med "${B[@]}")s   (mode=$MODE, n=$RUNS each)"
fi
