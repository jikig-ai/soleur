#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2018,SC2019  # A && B || C is the check idiom; tr A-Z is the portable ASCII lowering
# The /ship Phase 6 step 5 hold evaluator: turns the recorded `Gate:` predicates of `## Operator Holds` (or of a
# Production Envelope's `Preconditions:`) into a mechanical verdict, so a hold is discharged by evidence and never
# by a model's reading of prose. Procedure and wording: skills/ship/references/operator-holds.md. Format source:
# skills/brainstorm-techniques/references/standing-delegation.md.
#
# Property: a hold is discharged only if a verified Standing Delegation is cited and EVERY one of its `Gate:`
# predicates is a known kind that evaluates true now. Any other state leaves it standing:
# an unknown kind, an unreadable probe, a missing or invalid delegation, a timeout, a hold with no gate.
#
# Usage:
#   hold-gate-eval.sh --plan <plan.md>                              evaluate `## Operator Holds`
#   hold-gate-eval.sh --file <envelope.md> --section "<heading>"    evaluate one envelope's gates
# Run from the repository root (repo-relative paths are resolved from the working directory).
#
# Plan format (read from the file, never from conversation):
#   ## Operator Holds
#   Delegation: <comment url>        optional; without it no hold can be discharged here (exit 3)
#   Envelope: <path>                 optional; passed to the verifier
#   - Hold: <the operator's words, verbatim>
#     Gate: pr-merged <N> | no-inflight-run <workflow-file> | run-green <workflow-file> <sha>
#     Gate: command <repo-relative script and args> => <literal expected output>
#
# Exit: 0 every hold discharged (or none recorded: an absent or empty section is a no-op);
#       1 at least one hold STANDS; 2 cannot evaluate (treated as STANDS by the caller; includes a non-blank
#       section that parses to zero holds, an unknown kind, an unreadable probe, an unreadable delegation);
#       3 no delegation recorded (the caller keeps today's prose evaluation).
# stdout: one plain line per hold, then `holds: N discharged: M standing: K`. Exit 2 and 1 are never converted to
# a pass by any caller; nothing here retries a failed probe into a pass.
#
# `command` gates run only a repo-relative script (no `..`, no absolute path, no symlink, no ssh, no sourcing),
# tracked at HEAD, unmodified, and byte-identical to origin/main after a fresh `git fetch origin main`, so a
# probe cannot ship in the change that relies on it. 30 s cap, arguments from the charset [A-Za-z0-9._/@=:+-],
# passed as an array and never evaluated; the output is compared literally with the text after the FIRST `=>`.
#
# `set -uo pipefail`, deliberately NOT `-e`. Portable to bash 3.2 and mawk. Lines ending `# mut:<name>` are the
# mutation points the suite edits to prove each check can fail.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VERIFY="$SCRIPT_DIR/../../../scripts/delegation-verify.sh"
ARG_RE='^[A-Za-z0-9._/@=:+-]+$'
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "${WORK:?}"; return 0; }
trap cleanup EXIT

die2() { printf '%s\n' "$1" >&2; exit 2; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
clean_text() { printf '%s' "$1" | tr -d '[:cntrl:]' | cut -c1-160; }

TO10=(); TO30=()
if command -v timeout >/dev/null 2>&1; then TO10=(timeout 10); TO30=(timeout 30)
elif command -v gtimeout >/dev/null 2>&1; then TO10=(gtimeout 10); TO30=(gtimeout 30); fi

FETCHED=""; FETCH_RC=0
ensure_fetch() {
  [ -n "$FETCHED" ] && return "$FETCH_RC"
  git fetch -q origin main >/dev/null 2>&1; FETCH_RC=$? # mut:fetch
  FETCHED=1
  return "$FETCH_RC"
}

gh_json() { # <outfile> <gh args...>: 0 only when gh succeeded and printed valid JSON
  local out="$1"; shift
  ${TO10[@]+"${TO10[@]}"} gh "$@" > "$out" 2>/dev/null || return 1
  jq -e . "$out" >/dev/null 2>&1
}

known_kind() { case "$1" in pr-merged|no-inflight-run|run-green|command) return 0 ;; esac; return 1; }

GRES=""; GWHY=""
gate_pr_merged() {
  local n="$1" st sha base rc
  [[ "$n" =~ ^[0-9]+$ ]] || { GRES=UNEVAL; return; }
  ensure_fetch || true
  gh_json "$WORK/pr.json" pr view "$n" --json state,mergeCommit,baseRefName || { GRES=UNEVAL; return; }
  st="$(jq -r '.state // empty' "$WORK/pr.json")"; sha="$(jq -r '.mergeCommit.oid // empty' "$WORK/pr.json")"; base="$(jq -r '.baseRefName // empty' "$WORK/pr.json")"
  GWHY="the earlier change has not gone live yet"
  if [ "$st" = MERGED ] && [ "$base" = main ] && [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
    git merge-base --is-ancestor "$sha" HEAD >/dev/null 2>&1; rc=$?
    case "$rc" in 0) GRES=TRUE ;; 1) GRES=FALSE ;; *) GRES=UNEVAL ;; esac
  else
    GRES=FALSE
  fi
}

gate_no_inflight() {
  local wf="$1" s len any_live=0 any_fail=0
  [[ "$wf" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] || { GRES=UNEVAL; return; }
  for s in queued in_progress waiting; do
    if gh_json "$WORK/runs.json" run list --workflow "$wf" --status "$s" --limit 5 --json databaseId \
       && jq -e 'type == "array"' "$WORK/runs.json" >/dev/null 2>&1; then
      len="$(jq 'length' "$WORK/runs.json")"
      [ "$len" -eq 0 ] || any_live=1
    else
      any_fail=1
    fi
  done
  GWHY="a release is still running"
  if [ "$any_live" -eq 1 ]; then GRES=FALSE
  elif [ "$any_fail" -eq 1 ]; then GRES=UNEVAL
  else GRES=TRUE; fi
}

gate_run_green() {
  local wf="$1" sha="$2"
  [[ "$wf" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] && [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { GRES=UNEVAL; return; }
  gh_json "$WORK/green.json" run list --workflow "$wf" --commit "$sha" --limit 5 --json status,conclusion \
    && jq -e 'type == "array"' "$WORK/green.json" >/dev/null 2>&1 || { GRES=UNEVAL; return; }
  GWHY="the check has not passed yet"
  if [ "$(jq -r '.[0].status // empty' "$WORK/green.json")" = completed ] && [ "$(jq -r '.[0].conclusion // empty' "$WORK/green.json")" = success ]; then GRES=TRUE; else GRES=FALSE; fi
}

gate_command() {
  local rest="$1" left right tok script top topp dirp i rc args=()
  local toks=()
  case "$rest" in *"=>"*) ;; *) GRES=UNEVAL; return ;; esac
  left="$(trim "${rest%%=>*}")"; right="$(trim "${rest#*=>}")"
  [ -n "$left" ] || { GRES=UNEVAL; return; }
  read -r -a toks <<< "$left"
  for tok in "${toks[@]}"; do
    [[ "$tok" =~ $ARG_RE ]] || { GRES=UNEVAL; return; }
    [ "$tok" != ssh ] || { GRES=UNEVAL; return; }
  done
  script="${toks[0]}"
  case "$script" in /*|*..*) GRES=UNEVAL; return ;; esac
  [ -f "$script" ] && [ ! -L "$script" ] || { GRES=UNEVAL; return; }
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || { GRES=UNEVAL; return; }
  topp="$(cd -P "$top" 2>/dev/null && pwd -P)"; dirp="$(cd -P "$(dirname "$script")" 2>/dev/null && pwd -P)"
  case "$dirp/" in "$topp"/*) ;; *) GRES=UNEVAL; return ;; esac
  git ls-files --error-unmatch -- "$script" >/dev/null 2>&1 && git diff --quiet HEAD -- "$script" >/dev/null 2>&1 || { GRES=UNEVAL; return; } # mut:cmd-tracked
  ensure_fetch || { GRES=UNEVAL; return; }
  git show "origin/main:./$script" 2>/dev/null | cmp -s - "$script" || { GRES=UNEVAL; return; } # mut:cmd-identical
  grep -Eq '(^|[;&|[:space:](])ssh([[:space:]]|$)' "$script" && { GRES=UNEVAL; return; }
  grep -Eq '^[[:space:]]*(source|\.)[[:space:]]' "$script" && { GRES=UNEVAL; return; }
  for ((i = 1; i < ${#toks[@]}; i++)); do args[${#args[@]}]="${toks[$i]}"; done
  ${TO30[@]+"${TO30[@]}"} bash "$script" ${args[@]+"${args[@]}"} > "$WORK/probe.out" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || { GRES=UNEVAL; return; }
  printf '%s\n' "$right" > "$WORK/exp.nl"; printf '%s' "$right" > "$WORK/exp.raw"
  GWHY="the live check does not show it yet"
  if cmp -s "$WORK/probe.out" "$WORK/exp.nl" || cmp -s "$WORK/probe.out" "$WORK/exp.raw"; then GRES=TRUE; else GRES=FALSE; fi
}

eval_gate() { # <gate text after `Gate:`> -> GRES (TRUE|FALSE|UNEVAL), GWHY
  local text="$1" kind rest a b
  GRES=UNEVAL; GWHY="I could not check this, so it stays on hold"
  kind="${text%%[[:space:]]*}"; rest="$(trim "${text#"$kind"}")"
  known_kind "$kind" || { GRES=UNEVAL; return; } # mut:unknown-kind
  case "$kind" in
    pr-merged) gate_pr_merged "$rest" ;;
    no-inflight-run) gate_no_inflight "$rest" ;;
    run-green) a="${rest%%[[:space:]]*}"; b="$(trim "${rest#"$a"}")"; gate_run_green "$a" "$b" ;;
    command) gate_command "$rest" ;;
  esac
}

# split_section <file> <mode> <match>: sections into $WORK/sec.<n> (heads in sec.heads), count in sec.count.
split_sections() {
  awk -v dir="$WORK" -v mode="$2" -v match_text="$3" '
    { t = $0; sub(/\r$/, "", t)
      if (t ~ /^ ? ? ?```/ || t ~ /^ ? ? ?~~~/) { ch = substr(t, match(t, /[`~]/), 1); if (fch == "") fch = ch; else if (ch == fch) fch = "" }
      if (fch == "" && t ~ /^## /) {
        if (cur != "") close(cur)
        cur = ""
        hit = (mode == "plan") ? (t ~ /^## Operator Holds/) : (index(t, match_text) > 0)
        if (hit) { n++; cur = dir "/sec." n; print t > (dir "/sec.heads") }
      }
      if (cur != "") print $0 > cur
    }
    END { print n + 0 > (dir "/sec.count") }
  ' "$1"
}

# parse_items <section file> <mode>: records DELEG / ENVF / HOLD i text / GATE i text / ORPHAN.
parse_items() {
  awk -v mode="$2" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    NR == 1 { if (mode == "file") { n = 1; print "HOLD\t1\tthe conditions before the act" } next }
    { t = $0; sub(/\r$/, "", t)
      if (t ~ /^ ? ? ?```/ || t ~ /^ ? ? ?~~~/) { infence = !infence; next }
      if (infence) next
      if (mode == "plan" && t ~ /^[ \t]*(-[ \t]+)?Delegation:/) { v = t; sub(/^[ \t]*(-[ \t]+)?Delegation:[ \t]*/, "", v); print "DELEG\t" trim(v); next }
      if (mode == "plan" && t ~ /^[ \t]*(-[ \t]+)?Envelope:/) { v = t; sub(/^[ \t]*(-[ \t]+)?Envelope:[ \t]*/, "", v); print "ENVF\t" trim(v); next }
      if (mode == "plan" && t ~ /^[ \t]*-[ \t]+Hold:/) { v = t; sub(/^[ \t]*-[ \t]+Hold:[ \t]*/, "", v); n++; print "HOLD\t" n "\t" trim(v); next }
      if (t ~ /^[ \t]*(-[ \t]+)?Gate:[ \t]*[^ \t]/) { v = t; sub(/^[ \t]*(-[ \t]+)?Gate:[ \t]*/, "", v); if (n > 0) print "GATE\t" n "\t" trim(v); else print "ORPHAN"; next }
    }
  ' "$1"
}

print_result_line() { # <verdict> <text> <why>
  case "$1" in
    OK) printf 'Done: %s\n' "$(clean_text "$2")" ;;
    WAIT) printf 'Still waiting: %s - %s\n' "$(clean_text "$2")" "$3" ;;
    NEEDS) printf 'Needs a person: %s - only a person can settle this\n' "$(clean_text "$2")" ;;
    *) printf 'Could not check: %s - %s\n' "$(clean_text "$2")" "$3" ;;
  esac
}

# stand_all <verdict>: the delegation did not verify, so every hold stands (1 when invalid, 2 when it could not be checked).
stand_all() {
  local i text
  echo "Your standing approval could not be confirmed, so every hold stays on hold."
  while IFS=$'\t' read -r _ i text; do print_result_line WAIT "$text" "waiting for your standing approval"; done < <(grep '^HOLD' "$WORK/items")
  echo "holds: $NH discharged: 0 standing: $NH"
  [ "$1" = invalid ] && exit 1
  exit 2
}

MODE=""; PLAN=""; FILE=""; SECTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) [ $# -ge 2 ] || die2 "--plan needs a file"; PLAN="$2"; shift 2 ;;
    --file) [ $# -ge 2 ] || die2 "--file needs a file"; FILE="$2"; shift 2 ;;
    --section) [ $# -ge 2 ] || die2 "--section needs a heading"; SECTION="$2"; shift 2 ;;
    *) die2 "unknown argument: $1" ;;
  esac
done
if [ -n "$PLAN" ] && [ -z "$FILE" ] && [ -z "$SECTION" ]; then MODE="plan"; SRC="$PLAN"
elif [ -n "$FILE" ] && [ -n "$SECTION" ] && [ -z "$PLAN" ]; then MODE="file"; SRC="$FILE"
else die2 "usage: hold-gate-eval.sh --plan <plan.md> | --file <envelope.md> --section <heading>"; fi
[ -f "$SRC" ] && [ -r "$SRC" ] || die2 "cannot read $SRC, so no hold can be checked"
command -v jq >/dev/null 2>&1 || die2 "jq is not installed, so no hold can be checked"
command -v gh >/dev/null 2>&1 || die2 "the GitHub command line tool is not installed, so no hold can be checked"
command -v git >/dev/null 2>&1 || die2 "git is not installed, so no hold can be checked"
WORK="$(mktemp -d -t hge.XXXXXXXX)" || die2 "could not create a scratch folder"

split_sections "$SRC" "$MODE" "$SECTION"
CNT="$(cat "$WORK/sec.count" 2>/dev/null || echo 0)"
if [ "$MODE" = plan ]; then
  if [ "$CNT" -eq 0 ] || ! grep -q '[^[:space:]]' <(sed 1d "$WORK/sec.1"); then
    echo "No holds are recorded, so there is nothing to wait for."
    echo "holds: 0 discharged: 0 standing: 0"
    exit 0
  fi
  [ "$CNT" -eq 1 ] || { echo "The plan has more than one hold section, so I am treating every hold as still on hold."; exit 2; }
else
  [ "$CNT" -eq 1 ] || { echo "I could not find exactly one matching envelope section, so I am treating its conditions as not met."; exit 2; }
fi
parse_items "$WORK/sec.1" "$MODE" > "$WORK/items"
NH="$(grep -c '^HOLD' "$WORK/items")"
if [ "$MODE" = file ]; then
  [ "$(grep -c '^GATE' "$WORK/items")" -ge 1 ] || { echo "The envelope lists no conditions I can check, so I am treating them as not met."; exit 2; }
fi
if grep -q '^ORPHAN' "$WORK/items"; then echo "A condition is written outside any hold, so I am treating every hold as still on hold."; exit 2; fi
[ "$NH" -gt 0 ] || { echo "I found a hold section but could not read any hold in it, so I am treating it as still on hold."; exit 2; } # mut:zero-holds

DISCHARGED=0; STANDING=0; ANY_UNEVAL=0
if [ "$MODE" = plan ]; then
  DELEG="$(awk -F'\t' '$1 == "DELEG" { print $2; exit }' "$WORK/items")"
  ENVF="$(awk -F'\t' '$1 == "ENVF" { print $2; exit }' "$WORK/items")"
  [ -n "$DELEG" ] || { echo "No standing approval is recorded, so the usual check applies."; echo "holds: $NH discharged: 0 standing: $NH"; exit 3; } # mut:no-deleg
  [ -f "$VERIFY" ] || { echo "I could not find the standing-approval checker, so every hold stays on hold."; echo "holds: $NH discharged: 0 standing: $NH"; exit 2; }
  vargs=(verify --delegation "$DELEG")
  [ -z "$ENVF" ] || vargs[${#vargs[@]}]="--envelope"; [ -z "$ENVF" ] || vargs[${#vargs[@]}]="$ENVF"
  bash "$VERIFY" "${vargs[@]}" > "$WORK/verdict" 2>"$WORK/verdict.err"
  DV="$(head -1 "$WORK/verdict" | sed -n 's/^delegation: \([a-z]*\) reason=.*/\1/p')"
  [ "$DV" = valid ] || stand_all "$DV" # mut:deleg-valid
fi

while IFS=$'\t' read -r _ i text; do
  awk -F'\t' -v i="$i" '$1 == "GATE" && $2 == i { print $3 }' "$WORK/items" > "$WORK/g.$i"
  ng="$(wc -l < "$WORK/g.$i" | tr -d ' ')"
  HV=OK; WHY=""
  [ "$ng" -gt 0 ] || HV=NEEDS # mut:zero-gates
  while IFS= read -r gate; do
    eval_gate "$gate"
    case "$GRES" in TRUE) ;; FALSE) [ "$HV" = OK ] && { HV=WAIT; WHY="$GWHY"; } ;; *) HV=UNEVAL; WHY="$GWHY"; ANY_UNEVAL=1 ;; esac # mut:all-gates
  done < "$WORK/g.$i"
  print_result_line "$HV" "$text" "$WHY"
  if [ "$HV" = OK ]; then DISCHARGED=$((DISCHARGED + 1)); else STANDING=$((STANDING + 1)); fi
done < <(grep '^HOLD' "$WORK/items")

echo "holds: $NH discharged: $DISCHARGED standing: $STANDING"
[ "$ANY_UNEVAL" -eq 0 ] || exit 2
[ "$STANDING" -eq 0 ] || exit 1
exit 0
