#!/usr/bin/env bash
# collision-precheck.sh -- before plan or review work starts on issue <N>,
# report live work that may already be doing the same change:
#
#   probe 1: gh pr list --state open --search "<N>"   open PRs naming the issue
#   probe 2: lib/proc.sh list_runs <basename>         foreign-owned process rows
#                                                     (a sibling session's live
#                                                     gate in another worktree)
#
# A hit is REPORTED, never resolved: this script is read-only -- it never
# comments on, edits, closes or pushes to anyone's change. The caller surfaces
# every hit to the operator before work starts. The measured failure was two
# sessions of the same operator converting the same file for the same issue
# (#10320 / #10322; issue #10333) -- discovered only at the end of review,
# through a foreign worktree's test run and `gh pr list --head`.
#
# Usage:
#   collision-precheck.sh <issue-number> [<proc-basename>...]
#
#   <issue-number>    digits only
#   <proc-basename>   process basenames for the proc.sh half (default:
#                     test-all.sh). proc.sh matches on BASENAME and refuses any
#                     pattern containing '/', so pass e.g. test-all.sh, never a
#                     path.
#
# Output: one plain-language line per finding (and per probe that could not
# run), then ONE machine line:
#   SOLEUR_COLLISION exit=<code> prs=<csv|none|unchecked> foreign=<csv|none|unchecked>
#
# Exit codes:
#   0   clear -- both probes ran and found nothing
#   10  hit -- >=1 open PR names the issue, or >=1 foreign process row
#   2   could not check -- a probe failed AND the other found nothing; a check
#       that could not run never reads as clear
#   64  usage error
#
# `set -uo pipefail`, deliberately NOT `-e`: the probes' failures are inputs,
# never aborts. Portable to bash 3.2 (no associative arrays, no mapfile).

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROC_SH="$SELF_DIR/lib/proc.sh"

usage() {
  echo "usage: $0 <issue-number> [<proc-basename>...]" >&2
  echo "  reports open PRs naming the issue and foreign proc.sh list_runs rows; read-only." >&2
}

ISSUE="${1:-}"
case "$ISSUE" in
  *[!0-9]* | "")
    echo "collision-precheck: issue number must be digits only (got: '${ISSUE:-<empty>}')" >&2
    usage
    exit 64
    ;;
esac
shift

PATS=()
while (($#)); do
  case "$1" in
    */* | "")
      echo "collision-precheck: proc pattern '$1' is not a bare basename (proc.sh rejects '/')." >&2
      exit 64
      ;;
  esac
  PATS+=("$1")
  shift
done
if [[ ${#PATS[@]} -eq 0 ]]; then PATS=(test-all.sh); fi

say() { printf '%s\n' "$*"; }

PRS=""
PR_STATE=unchecked
FGN=""
FGN_STATE=unchecked

# --- probe 1: open PRs naming the issue -------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  say "I could not check open PRs for #$ISSUE (gh is not installed)."
elif ! rows="$(gh pr list --state open --search "$ISSUE" -L 100 \
              --json number,url --jq '.[] | "\(.number)\t\(.url)"' 2>/dev/null)"; then
  say "I could not check open PRs for #$ISSUE (gh pr list failed -- auth, network or API error)."
else
  PR_STATE=none
  while IFS=$'\t' read -r _n _u; do
    [[ -n "$_n" ]] || continue
    PR_STATE=csv
    PRS="${PRS:+$PRS,}$_n"
    say "An open change names #$ISSUE: PR #$_n -- $_u"
  done <<< "$rows"
fi

# --- probe 2: foreign proc.sh rows ------------------------------------------
if [[ ! -f "$PROC_SH" ]]; then
  say "I could not check sibling-session processes ($PROC_SH is missing)."
else
  _ok=0
  _failed=0
  for _pat in ${PATS[@]+"${PATS[@]}"}; do
    _out="$(bash "$PROC_SH" list_runs "$_pat" 2>/dev/null)"
    _rc=$?
    if ((_rc == 0)); then
      _ok=$((_ok + 1))
      while IFS=$'\t' read -r _pid _owner _cwd; do
        [[ "$_owner" == "foreign" ]] || continue
        FGN="${FGN:+$FGN,}$_pid"
        say "A running process matching '$_pat' is owned by another worktree: pid $_pid ($_cwd)"
      done <<< "$_out"
    else
      _failed=$((_failed + 1))
      say "I could not check sibling-session processes for '$_pat' (proc.sh exited $_rc)."
    fi
  done
  if [[ -n "$FGN" ]]; then
    FGN_STATE=csv
  elif ((_ok > 0 && _failed == 0)); then
    FGN_STATE=none
  fi
fi

# --- verdict ----------------------------------------------------------------
if [[ -z "$PRS" && -z "$FGN" && "$PR_STATE" == "none" && "$FGN_STATE" == "none" ]]; then
  say "No open change names #$ISSUE and no foreign gate process is running."
  printf 'SOLEUR_COLLISION exit=0 prs=none foreign=none\n'
  exit 0
fi

if [[ -n "$PRS" || -n "$FGN" ]]; then
  say "Report the hit(s) above before work starts -- never silently continue on a live duplicate."
  printf 'SOLEUR_COLLISION exit=10 prs=%s foreign=%s\n' \
    "${PRS:-$PR_STATE}" "${FGN:-$FGN_STATE}"
  exit 10
fi

say "The collision pre-check could not fully run; that is not a clear result."
printf 'SOLEUR_COLLISION exit=2 prs=%s foreign=%s\n' "$PR_STATE" "$FGN_STATE"
exit 2
