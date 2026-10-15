#!/usr/bin/env bash
# pr-overlap-preflight.sh -- before work starts and before a merge is armed, list the OTHER open
# changes on this repository that overlap with this one. READ-ONLY: it never comments on, edits,
# closes or pushes to anyone's change (a skill never edits another session's change).
#
# Usage:
#   pr-overlap-preflight.sh [--mode start|merge] [--pr <N>] [--files "<f ...>"] [--issue <N>]...
#                           [--vehicle <N>|this]
#
#   --mode      start (default; no change needs to exist yet) or merge (a change must exist and the
#               starting point must be readable, otherwise exit 2)
#   --pr        this change's number (default: read from `gh pr view`)
#   --files     the files this change touches, space-separated (default: git diff --name-only
#               origin/main...HEAD)
#   --issue     an issue number this work refers to; open changes that mention it are listed
#               (informational). Repeatable.
#   --vehicle   the change a CTO ruling designated to carry the work. Taken from this flag ONLY, never
#               parsed out of prose. `this` means THIS change is the vehicle (usable before a change
#               exists).
#
# An "overlap" is an open change that (a) edits a file in the set, (b) makes the same edit (equal
# per-file patch identity over the other change's diff, computed only for changes that share a file,
# at most 20 diffs, disclosed), (c) carries a change with the same title as one of ours (generic
# titles such as `chore: initialize ...`, `WIP ...` and merge commits are ignored), or (d) mentions a
# given issue.
#
# Exit codes (graduated: only a duplicate or a designated vehicle stops a merge):
#   0   clear: nothing overlaps
#   10  overlap and the designated vehicle is the OTHER change: this one carves out
#   11  overlap and THIS change is the vehicle: the others carve out (informational)
#   12  a duplicate (same edit or same title) and no vehicle designated: the caller spawns the CTO to
#       designate one and records the ruling (never an operator question)
#   13  overlap on shared files (or a mentioned issue) only, no vehicle: informational, nothing stops
#   2   could not check (printed as "I could not check", never as clear)
#
# Output: a plain-language human block, then ONE last line for the calling agent:
#   SOLEUR_OVERLAP exit=<code> prs=<n,n|none> vehicle=<n|this|none>
# Titles are attacker-controllable text on a public repository: they are printed as data (control
# characters stripped, change number and conventional-commit prefix removed, 80 characters), never
# executed and never placed in a question option.
#
# `set -uo pipefail`, deliberately NOT `-e`: the scanners are pipelines whose grep exits 1 on no
# match. Portable to bash 3.2 and mawk (no associative arrays, no mapfile, no ${var,,}, no sed -i).
# Lines carrying `# mut:<name>` are the mutation points the suite replaces to prove each check can
# fail.

set -uo pipefail
export LC_ALL=C

MODE=start
PR_ARG=""
FILES_ARG=""
FILES_SET=0
VEHICLE=""
ISSUES=""

SAMEFILE_ON=1 # mut:samefile
SCAN_LIMIT=200 # mut:firstonly
PAGE_CAP=100 # mut:paginate
SHARED_ONLY_EXIT=13 # mut:sharedblock
LIST_CAP=200
DIFF_CAP=20
SUBJECT_READ_CAP=60
MSG_EDIT="This change makes the same edit as yours." # mut:printid

say() { printf '%s\n' "$*"; }

finish() { # finish <code> <csv|none>
  local v="${VEHICLE:-none}"
  printf 'SOLEUR_OVERLAP exit=%s prs=%s vehicle=%s\n' "$1" "${2:-none}" "$v"
  exit "$1"
}

cannot_check() { # cannot_check <plain reason>
  say "I could not check whether other open work overlaps with this change ($1)."
  say "Treat this as not checked. It is not a clear result."
  finish 2 none
}

is_int() { # digits only, 1 to 9 of them
  case "${1-}" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 9 ]
}

# Bound every network call. `timeout` is coreutils and absent on a stock macOS; without it the
# call runs unbounded rather than failing, because the callers retry once and then continue with a
# visible notice.
bounded() { # bounded <seconds> <cmd...>
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

# ---- arguments -------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ $# -ge 2 ] || cannot_check "the request to this check was incomplete"
      case "$2" in
        start|merge) MODE="$2" ;;
        *) cannot_check "the request to this check named an unknown mode" ;;
      esac
      shift 2 ;;
    --pr)
      [ $# -ge 2 ] || cannot_check "the request to this check was incomplete"
      is_int "$2" || cannot_check "the request to this check gave a change number that is not a number"
      PR_ARG="$2"; shift 2 ;;
    --files)
      [ $# -ge 2 ] || cannot_check "the request to this check was incomplete"
      FILES_ARG="$2"; FILES_SET=1; shift 2 ;;
    --issue)
      [ $# -ge 2 ] || cannot_check "the request to this check was incomplete"
      is_int "$2" || cannot_check "the request to this check gave an issue number that is not a number"
      ISSUES="$ISSUES $2"; shift 2 ;;
    --vehicle)
      [ $# -ge 2 ] || cannot_check "the request to this check was incomplete"
      if [ "$2" = this ] || is_int "$2"; then VEHICLE="$2"; else
        cannot_check "the request to this check named a vehicle that is not a number"
      fi
      shift 2 ;;
    *) cannot_check "the request to this check had an option I do not recognise" ;;
  esac
done

command -v gh >/dev/null 2>&1 || cannot_check "the GitHub tool is not available here"
command -v jq >/dev/null 2>&1 || cannot_check "a required reading tool is not available here"
command -v git >/dev/null 2>&1 || cannot_check "git is not available here"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-overlap.XXXXXXXX")" || cannot_check "I could not make a scratch folder"
trap 'rm -rf "$WORK"' EXIT # mut:write

# ---- jq helpers -------------------------------------------------------------------------------
JQ_DEFS='
def clean: explode | map(select(. >= 32 and . != 127)) | implode;
def norm: clean | sub("\\s*\\(#[0-9]+\\)\\s*$";"") | ascii_downcase | gsub("\\s+";" ") | sub("^ +";"") | sub(" +$";"");
def generic: test("^(chore: initialize|wip(:| |$)|fixup!|squash!|merge )") or . == "chore: record plan-phase session state" or (length < 20);
def disp: clean | sub("\\s*\\(#[0-9]+\\)\\s*$";"") | sub("^[a-zA-Z]+(\\([^)]*\\))?!?: *";"") | gsub("#(?=[0-9])";"") | gsub("\\s+";" ") | sub("^ +";"") | sub(" +$";"") | (if length == 0 then "untitled" else . end) | (if length > 80 then .[0:77] + "..." else . end);
'

# ---- this change ----------------------------------------------------------------------------
CUR_HEAD="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$CUR_HEAD" = HEAD ] && CUR_HEAD=""
CUR_PR="$PR_ARG"
if [ -z "$CUR_PR" ]; then
  VIEW_JSON="$(bounded 30 gh pr view --json number,headRefName 2>/dev/null)"
  vrc=$?
  if [ "$vrc" -eq 0 ] && VIEW_N="$(printf '%s' "$VIEW_JSON" | jq -er '.number' 2>/dev/null)" && is_int "$VIEW_N"; then
    CUR_PR="$VIEW_N"
    VIEW_H="$(printf '%s' "$VIEW_JSON" | jq -r '.headRefName // empty' 2>/dev/null)"
    [ -n "$VIEW_H" ] && CUR_HEAD="$VIEW_H"
  elif [ "$MODE" = merge ]; then
    cannot_check "I could not find this change on GitHub"
  fi
fi

BASE_OK=0
git rev-parse --verify -q 'origin/main^{commit}' >/dev/null 2>&1 && BASE_OK=1
if [ "$MODE" = merge ] && [ "$BASE_OK" -ne 1 ]; then
  cannot_check "I cannot see where this work started from"
fi

OWN_FILES=""
if [ "$FILES_SET" -eq 1 ]; then
  set -f
  for f in $FILES_ARG; do OWN_FILES="$OWN_FILES$f"$'\n'; done
  set +f
else
  [ "$BASE_OK" -eq 1 ] || cannot_check "I could not read which files this change touches"
  OWN_FILES="$(git diff --name-only origin/main...HEAD 2>/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] || cannot_check "I could not read which files this change touches"
fi
OURS_JSON="$(printf '%s\n' "$OWN_FILES" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')" \
  || cannot_check "I could not read which files this change touches"

OWN_SUBJECTS=""
if [ "$BASE_OK" -eq 1 ]; then
  OWN_SUBJECTS="$(git log --no-merges --format=%s origin/main..HEAD 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$MODE" = merge ]; then cannot_check "I could not read the titles of this change's steps"; fi
fi
SUBJ_OURS_JSON="$(printf '%s\n' "$OWN_SUBJECTS" | jq -R -s -c "$JQ_DEFS"' split("\n") | map(norm | select(length > 0 and (generic | not))) | unique')" \
  || cannot_check "I could not read the titles of this change's steps"

# ---- the other open changes ---------------------------------------------------------------------
LIST_JSON="$(bounded 60 gh pr list --state open -L 200 --json number,title,url,isDraft,files,headRefName 2>/dev/null)"
rc=$?
[ "$rc" -ne 0 ] && cannot_check "GitHub did not answer when I asked for the open changes" # mut:listfail
printf '%s' "$LIST_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || cannot_check "GitHub gave me an answer I could not read"
LIST_COUNT="$(printf '%s' "$LIST_JSON" | jq 'length')"

OTHERS="$(printf '%s' "$LIST_JSON" | jq -c --arg cur "$CUR_PR" --arg head "$CUR_HEAD" --argjson lim "$SCAN_LIMIT" \
  '[.[0:$lim][] | select((.number | tostring) != $cur and ($head == "" or .headRefName != $head))]')" \
  || cannot_check "GitHub gave me an answer I could not read"

# A change that lists exactly PAGE_CAP files may have more: GitHub caps the list per change. Re-read
# those with a paginated call; a failed re-read is "could not check", never clear.
OV='{}'
CAPPED="$(printf '%s' "$OTHERS" | jq -r --argjson cap "$PAGE_CAP" '.[] | select((.files | length) >= $cap) | .number')"
for n in $CAPPED; do
  pages="$(bounded 60 gh api "repos/{owner}/{repo}/pulls/$n/files" --paginate --jq '.[].filename' 2>/dev/null)"
  rc=$?
  [ "$rc" -ne 0 ] && cannot_check "GitHub did not answer when I asked for the full file list of a large change" # mut:pagefail
  arr="$(printf '%s\n' "$pages" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  OV="$(printf '%s' "$OV" | jq -c --arg n "$n" --argjson a "$arr" '. + {($n): $a}')"
done

# Same-file signal.
CAND="$(printf '%s' "$OTHERS" | jq -c --argjson ours "$OURS_JSON" --argjson ov "$OV" --argjson samefile "$SAMEFILE_ON" "$JQ_DEFS"'
  [ .[] | . as $p
    | (($ov[($p.number | tostring)]) // [$p.files[]?.path]) as $eff
    | { number: $p.number, title: ($p.title // ""), url: ($p.url // ""), draft: ($p.isDraft // false),
        files: (if $samefile == 1 then [$eff[] | clean | select(IN($ours[]))] | unique else [] end) } ]')" \
  || cannot_check "GitHub gave me an answer I could not read"

# ---- same-title signal ---------------------------------------------------------------------------
SUBJ_NUMS=""
SUBJ_TOTAL=0
SUBJ_READ=0
if [ "$SUBJ_OURS_JSON" != "[]" ]; then
  TITLE_HITS="$(printf '%s' "$CAND" | jq -r --argjson s "$SUBJ_OURS_JSON" "$JQ_DEFS"'.[] | select((.title | norm) as $t | ($t | generic | not) and ($s | any(. == $t))) | .number')"
  for n in $TITLE_HITS; do SUBJ_NUMS="$SUBJ_NUMS $n"; done
  for n in $(printf '%s' "$CAND" | jq -r '.[].number'); do
    case " $SUBJ_NUMS " in *" $n "*) continue ;; esac
    SUBJ_TOTAL=$((SUBJ_TOTAL + 1))
    [ "$SUBJ_READ" -ge "$SUBJECT_READ_CAP" ] && continue
    SUBJ_READ=$((SUBJ_READ + 1))
    lines="$(bounded 60 gh api "repos/{owner}/{repo}/pulls/$n/commits" --paginate --jq '.[].commit.message | split("\n")[0]' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] || cannot_check "GitHub did not answer when I asked for the history of another change"
    hit="$(printf '%s\n' "$lines" | jq -R -s -r --argjson s "$SUBJ_OURS_JSON" "$JQ_DEFS"'split("\n") | map(norm | select(length > 0 and (generic | not))) | if any(.[]; . as $t | $s | any(. == $t)) then "yes" else "no" end')"
    [ "$hit" = yes ] && SUBJ_NUMS="$SUBJ_NUMS $n"
  done
fi
# shellcheck disable=SC2086 # the list is space-separated integers
SUBJ_JSON="$(printf '%s\n' $SUBJ_NUMS | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')"

# ---- same-edit signal ----------------------------------------------------------------------------
own_pid() { # own_pid <file> -> the patch identity of OUR edit to the file, or nothing
  local key cf
  key="$(printf '%s' "$1" | cksum | tr ' ' '_')"
  cf="$WORK/own.$key"
  if [ ! -f "$cf" ]; then
    git diff --no-ext-diff --no-color origin/main...HEAD -- "$1" 2>/dev/null | git patch-id --stable 2>/dev/null | awk 'NR==1{print $1}' > "$cf"
  fi
  cat "$cf"
}

EDIT_NUMS=""
SHARE_TOTAL=0
DIFF_N=0
DIFF_FAILED=0
NOEDIT=0
SHARING="$(printf '%s' "$CAND" | jq -r '.[] | select(.files | length > 0) | .number')"
for n in $SHARING; do
  SHARE_TOTAL=$((SHARE_TOTAL + 1))
  [ "$DIFF_N" -ge "$DIFF_CAP" ] && continue
  if [ "$BASE_OK" -ne 1 ]; then NOEDIT=1; continue; fi
  DIFF_N=$((DIFF_N + 1))
  d="$WORK/pd$n"; mkdir -p "$d"
  bounded 60 gh pr diff "$n" > "$d/all.diff" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then DIFF_FAILED=$((DIFF_FAILED + 1)); continue; fi
  awk -v dir="$d" '
    /^diff --git a\// {
      if (out != "") close(out)
      k++
      name = $0
      sub(/^diff --git a\/.* b\//, "", name)
      out = dir "/" k ".patch"
      print name > (dir "/" k ".name")
      close(dir "/" k ".name")
    }
    k > 0 { print > out }
  ' "$d/all.diff"
  printf '%s' "$CAND" | jq -r --argjson n "$n" '.[] | select(.number == $n) | .files[]' > "$WORK/shared.$n"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mine="$(own_pid "$f")"
    [ -n "$mine" ] || continue
    nf="$(grep -lFx -- "$f" "$d"/*.name 2>/dev/null | head -n 1)"
    [ -n "$nf" ] || continue
    theirs="$(git patch-id --stable < "${nf%.name}.patch" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$theirs" ] && [ "$theirs" = "$mine" ]; then EDIT_NUMS="$EDIT_NUMS $n"; break; fi
  done < "$WORK/shared.$n"
done
# shellcheck disable=SC2086 # the list is space-separated integers
EDIT_JSON="$(printf '%s\n' $EDIT_NUMS | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')"

# ---- issue signal ---------------------------------------------------------------------------------
ISSUE_PRS='[]'
for i in $ISSUES; do
  res="$(bounded 60 gh pr list --state open --search "$i" -L 50 --json number,title,url,isDraft,headRefName 2>/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] || cannot_check "GitHub did not answer when I searched for the issue"
  ISSUE_PRS="$(printf '%s\n%s' "$ISSUE_PRS" "$res" | jq -s -c --arg cur "$CUR_PR" --arg head "$CUR_HEAD" \
    '.[0] + [.[1][]? | select((.number | tostring) != $cur and ($head == "" or .headRefName != $head))]')" \
    || cannot_check "GitHub gave me an answer I could not read"
done

# ---- decide ----------------------------------------------------------------------------------------
OVER="$(jq -n -c --argjson cand "$CAND" --argjson edits "$EDIT_JSON" --argjson subj "$SUBJ_JSON" --argjson ip "$ISSUE_PRS" '
  ($cand | map(. + { edit: (.number as $n | $edits | any(. == $n)), subject: (.number as $n | $subj | any(. == $n)), issue: false })) as $a
  | ($ip | map({ number: .number, title: (.title // ""), url: (.url // ""), draft: (.isDraft // false), files: [], edit: false, subject: false, issue: true })) as $b
  | ($a + $b) | group_by(.number)
  | map(reduce .[1:][] as $x (.[0]; .files = ((.files + $x.files) | unique) | .edit = (.edit or $x.edit) | .subject = (.subject or $x.subject) | .issue = (.issue or $x.issue)))
  | map(select((.files | length) > 0 or .edit or .subject or .issue))
  | sort_by(.number)')" \
  || cannot_check "I could not combine what I found"

N_OVER="$(printf '%s' "$OVER" | jq 'length')"
IDS="$(printf '%s' "$OVER" | jq -r 'map(.number | tostring) | join(",")')"
DUP="$(printf '%s' "$OVER" | jq 'any(.[]; .edit or .subject)')"
VEH_IN=false
[ -n "$VEHICLE" ] && VEH_IN="$(printf '%s' "$OVER" | jq --arg v "$VEHICLE" 'any(.[]; (.number | tostring) == $v)')"

vehicle_is_this() { [ -n "$VEHICLE" ] && { [ "$VEHICLE" = this ] || [ "$VEHICLE" = "$CUR_PR" ]; }; } # mut:vehicle

if [ "$N_OVER" -eq 0 ]; then
  CODE=0
elif vehicle_is_this; then
  CODE=11
elif [ "$VEH_IN" = true ]; then
  CODE=10
elif [ "$DUP" = true ]; then
  CODE=12
else
  CODE="$SHARED_ONLY_EXIT"
fi

# ---- say it in plain words ------------------------------------------------------------------------
if [ "$N_OVER" -eq 0 ]; then
  say "No other open work overlaps with this change."
else
  say "Other open work overlaps with this change:"
  printf '%s' "$OVER" | jq -r --arg msgedit "$MSG_EDIT" "$JQ_DEFS"'.[] |
    "- \"" + (.title | disp) + "\" - " + (.url | clean),
    (if (.files | length) > 0 then "    Changes some of the same files as yours: " + (.files | map(clean) | .[0:5] | join(", ")) + (if (.files | length) > 5 then " and " + (((.files | length) - 5) | tostring) + " more" else "" end) else empty end),
    (if .edit then "    " + $msgedit else empty end),
    (if .subject then "    It has a change with the same title as one of yours." else empty end),
    (if .issue then "    Mentions the same issue as this work." else empty end),
    (if .draft then "    It is still being worked on and is not ready yet." else empty end)'
fi

if [ "$LIST_COUNT" -ge "$LIST_CAP" ]; then
  say "GitHub listed $LIST_CAP open changes, the most I can read at once, so there may be more that I did not see."
fi
if [ "$SHARE_TOTAL" -gt "$DIFF_CAP" ]; then
  say "I compared the actual edits of $DIFF_CAP of the $SHARE_TOTAL changes that share files with yours; the rest are matched by file name only."
fi
if [ "$SUBJ_TOTAL" -gt "$SUBJECT_READ_CAP" ]; then
  say "I read the step-by-step history of $SUBJECT_READ_CAP of the $SUBJ_TOTAL other open changes; the rest were matched by their own title only."
fi
if [ "$DIFF_FAILED" -gt 0 ]; then
  say "I could not compare the edits themselves for $DIFF_FAILED of them, so those are matched by file name only."
fi
if [ "$NOEDIT" -eq 1 ]; then
  say "I could not compare the edits themselves because I cannot see where this work started from yet."
fi

case "$CODE" in
  0)
    : ;;
  10)
    say "What this means: another open change was chosen to carry this work. I am holding mine back and will not touch theirs."
    say "Next step: wait until that change is live, then check again."
    ;;
  11)
    say "What this means: this change was chosen to carry the work, so the other changes should step aside. I am not touching them."
    say "Next step: carry on with this change; the others are listed only so you know they exist."
    ;;
  12)
    say "What this means: another open change already covers the same work and nobody has chosen which one carries it. I am holding mine back."
    say "Next step: ask the engineering lead agent to choose one change to carry the work and record its decision (a technical choice, not a question for you), then run this check again with the chosen change named."
    ;;
  13)
    say "What this means: these changes touch some of the same files, which is common and does not stop anything. Whichever goes second may need small adjustments."
    say "Next step: carry on; I will not touch their changes."
    ;;
esac

finish "$CODE" "${IDS:-none}"
