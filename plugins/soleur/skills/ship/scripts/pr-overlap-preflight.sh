#!/usr/bin/env bash
# pr-overlap-preflight.sh -- before work starts and before a merge is armed, list the OTHER open
# changes on this repository that overlap with this one. READ-ONLY: it never comments on, edits,
# closes or pushes to anyone's change (a skill never edits another session's change).
#
# Usage:
#   pr-overlap-preflight.sh [--mode start|merge] [--pr <N>] [--files "<f ...>"] [--vehicle <N>|this]
#
#   --mode      start (default; no change needs to exist yet) or merge (a change must exist and the
#               starting point must be readable, otherwise exit 2)
#   --pr        this change's number (default: read from `gh pr view`)
#   --files     the files this change touches, space-separated (default: git diff --name-only
#               origin/main...HEAD)
#   --vehicle   the change a CTO ruling designated to carry the work. Taken from this flag ONLY, never
#               parsed out of prose. `this` means THIS change is the vehicle (usable before a change
#               exists).
#
# An "overlap" is an open change that (a) edits a file in the set, or (b) carries a change with the
# same title as one of ours (generic titles such as `chore: initialize ...`, `WIP ...`, merge commits
# and titles under 20 characters are ignored). Generated files (lockfiles, suite timing tables,
# *.likec4.json, rule-body-hashes.txt, *.baseline.txt) never count as shared files.
#
# A DUPLICATE is an overlap where the other change makes the identical edit (equal per-file patch
# identity) on ALL of our changed files, or on at least two of them; or carries the same title. One
# identical hunk in one of several shared files is not a duplicate.
#
# Who can stop a merge: only a change whose author is OWNER, MEMBER or COLLABORATOR of the repository
# (GitHub's author_association, read from the REST list of open pulls) can produce exit 10 or 12. A
# change from anyone else is listed for information (exit 13) and costs no history or diff reads.
#
# Exit codes (graduated: only a duplicate or a designated vehicle stops a merge):
#   0   clear: nothing overlaps
#   10  overlap and the designated vehicle is the OTHER (team) change: this one carves out
#   11  overlap and THIS change is the vehicle: the others carve out (informational)
#   12  a duplicate (same edit or same title) by a team author and no vehicle designated: the caller
#       spawns the CTO to designate one and records the ruling (never an operator question)
#   13  overlap on shared files only, or any overlap by a non-team author, no vehicle: informational,
#       nothing stops
#   2   could not check, or called wrongly (printed as "I could not check", never as clear)
#
# Cost bounds: one list call plus one author read (100 a page); same-title history is read only for
# team changes that share a file (per_page=100); a diff is downloaded only when the other change's
# per-file additions/deletions equal ours; at most 20 diffs; the whole run stops comparing after 45
# seconds (PR_OVERLAP_DEADLINE_SECS overrides, whole seconds, 1 to 999) and says so.
#
# Output: a plain-language human block, then ONE last line for the calling agent:
#   SOLEUR_OVERLAP exit=<code> prs=<n,n|none> vehicle=<n|this|none>
# Titles are attacker-controllable text on a public repository: they are printed as data (control,
# format, bidirectional and line-separator characters stripped, change number and conventional-commit
# prefix removed, 80 characters), never executed and never placed in a question option.
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

PAGE_CAP=100 # mut:paginate
LIST_CAP=200 # mut:lcap
DIFF_CAP=20
DEADLINE_SECS=45
case "${PR_OVERLAP_DEADLINE_SECS:-}" in
  '' | *[!0-9]*) ;;
  *) if [ "${#PR_OVERLAP_DEADLINE_SECS}" -le 3 ] && [ "$PR_OVERLAP_DEADLINE_SECS" -gt 0 ]; then DEADLINE_SECS="$PR_OVERLAP_DEADLINE_SECS"; fi ;;
esac
T0=$SECONDS

say() { printf '%s\n' "$*"; }

over_deadline() { [ $((SECONDS - T0)) -ge "$DEADLINE_SECS" ]; } # mut:deadline

finish() { # finish <code> <csv|none>
  local v="${VEHICLE:-none}"
  printf 'SOLEUR_OVERLAP exit=%s prs=%s vehicle=%s\n' "$1" "${2:-none}" "$v"
  exit "$1"
}

cannot_check() { # cannot_check <plain reason> [noretry]
  say "I could not check whether other open work overlaps with this change ($1)."
  say "It was not checked, and that is not a clear result."
  if [ "${2:-}" = noretry ]; then
    say "Next step for me: continue, and say plainly that the overlap check did not run."
  else
    say "Next step for me: retry once, then continue and say plainly that it was not checked."
  fi
  finish 2 none
}

usage_error() { # usage_error <plain reason>
  say "I could not check whether other open work overlaps with this change ($1)."
  say "It was not checked, and that is not a clear result."
  say "Next step for me: correct the way I called the check (pr-overlap.md lists the options) and run it again."
  finish 2 none
}

is_int() { # digits only, 1 to 9 of them
  case "${1-}" in '' | *[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 9 ]
}

# Bound every network call by its own cap and by what is left of the run deadline. `timeout` is
# coreutils and absent on a stock macOS; without it the call runs unbounded (the deadline is then
# only checked between calls) rather than failing, because the callers retry once and then continue
# with a visible notice.
bounded() { # bounded <seconds> <cmd...>
  local secs="$1" left
  shift
  left=$((DEADLINE_SECS - (SECONDS - T0)))
  [ "$left" -lt 1 ] && left=1
  [ "$secs" -gt "$left" ] && secs="$left"
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
      [ $# -ge 2 ] || usage_error "the request to this check was incomplete"
      case "$2" in
        start | merge) MODE="$2" ;;
        *) usage_error "the request to this check named an unknown mode" ;;
      esac
      shift 2 ;;
    --pr)
      [ $# -ge 2 ] || usage_error "the request to this check was incomplete"
      is_int "$2" || usage_error "the request to this check gave a change number that is not a number"
      PR_ARG="$2"; shift 2 ;;
    --files)
      [ $# -ge 2 ] || usage_error "the request to this check was incomplete"
      FILES_ARG="$2"; FILES_SET=1; shift 2 ;;
    --vehicle)
      [ $# -ge 2 ] || usage_error "the request to this check was incomplete"
      if [ "$2" = this ] || is_int "$2"; then VEHICLE="$2"; else
        usage_error "the request to this check named a vehicle that is not a number"
      fi
      shift 2 ;;
    *) usage_error "the request to this check had an option I do not recognise" ;;
  esac
done

command -v gh >/dev/null 2>&1 || cannot_check "the GitHub tool is not available here" noretry
command -v jq >/dev/null 2>&1 || cannot_check "a required reading tool is not available here" noretry
command -v git >/dev/null 2>&1 || cannot_check "git is not available here" noretry

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-overlap.XXXXXXXX")" || cannot_check "I could not make a scratch folder"
trap 'rm -rf "$WORK"' EXIT # mut:write

# ---- jq helpers -------------------------------------------------------------------------------
# clean drops control characters, C1 controls, soft hyphen, Arabic letter mark, Mongolian vowel
# separator, zero-width and directional marks, line and paragraph separators, bidirectional
# embeddings and isolates, invisible operators, the byte-order mark, interlinear annotation marks and
# tag characters: everything a stranger could use to hide, reorder or split the text of a title.
JQ_DEFS='
def clean: explode | map(select(. >= 32 and . != 127 and (. < 128 or . > 159) and . != 173 and . != 1564 and . != 6158 and (. < 8203 or . > 8207) and (. < 8232 or . > 8238) and (. < 8288 or . > 8297) and . != 65279 and (. < 65529 or . > 65531) and (. < 917504 or . > 917631))) | implode; # mut:clean
def norm: clean | sub("\\s*\\(#[0-9]+\\)\\s*$";"") | ascii_downcase | gsub("\\s+";" ") | sub("^ +";"") | sub(" +$";""); # mut:norm
def short: length < 20; # mut:short
def generic: test("^(chore: initialize|wip(:| |$)|fixup!|squash!|merge )") or . == "chore: record plan-phase session state" or short;
def disp: clean | sub("\\s*\\(#[0-9]+\\)\\s*$";"") | sub("^[a-zA-Z]+(\\([^)]*\\))?!?: *";"") | gsub("#(?=[0-9])";"") | gsub("\\s+";" ") | sub("^ +";"") | sub(" +$";"") | (if length == 0 then "untitled" else . end) | (if length > 80 then .[0:77] + "..." else . end);
def noise: test("(^|/)(package-lock\\.json|npm-shrinkwrap\\.json|bun\\.lockb?|yarn\\.lock|pnpm-lock\\.yaml|Gemfile\\.lock|Cargo\\.lock|poetry\\.lock|uv\\.lock|composer\\.lock|go\\.sum|suite-[a-z-]+\\.tsv|rule-body-hashes\\.txt)$") or test("\\.likec4\\.json$") or test("\\.baseline\\.txt$"); # mut:noise
def trusted: IN("OWNER","MEMBER","COLLABORATOR"); # mut:assoc
'
SELF_DEFS='
def own_number: (.number | tostring) == $cur; # mut:selfnum
def own_branch: $head != "" and .headRefName == $head and ((.isCrossRepository // false) | not) or ($head != "" and .headRefName == $head and $owner != "" and (.headRepositoryOwner.login // "") == $owner); # mut:selfbranch
'
SHARED_DEFS='
def sharedfiles($eff; $ours): [$eff[] | clean | select((noise | not) and IN($ours[]))] | unique; # mut:samefile
'
EDIT_RULE_JQ='$e >= 2 or ($e >= 1 and $e == $o)' # mut:dup

# ---- this change ----------------------------------------------------------------------------
CUR_HEAD="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$CUR_HEAD" = HEAD ] && CUR_HEAD=""
CUR_PR="$PR_ARG"
VIEW_OWNER=""
if [ -z "$CUR_PR" ]; then
  VIEW_JSON="$(bounded 30 gh pr view --json number,headRefName,headRepositoryOwner 2>/dev/null)"
  vrc=$?
  if [ "$vrc" -eq 0 ] && VIEW_N="$(printf '%s' "$VIEW_JSON" | jq -er '.number' 2>/dev/null)" && is_int "$VIEW_N"; then
    CUR_PR="$VIEW_N"
    VIEW_H="$(printf '%s' "$VIEW_JSON" | jq -r '.headRefName // empty' 2>/dev/null)"
    [ -n "$VIEW_H" ] && CUR_HEAD="$VIEW_H"
    VIEW_OWNER="$(printf '%s' "$VIEW_JSON" | jq -r '.headRepositoryOwner.login // empty' 2>/dev/null)"
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
  OWN_FILES="$(git diff --no-renames --name-only origin/main...HEAD 2>/dev/null)" # mut:norenames
  rc=$?
  [ "$rc" -eq 0 ] || cannot_check "I could not read which files this change touches"
fi
OURS_JSON="$(printf '%s\n' "$OWN_FILES" | jq -R -s -c "$JQ_DEFS"' split("\n") | map(select(length > 0 and (noise | not))) | unique')" \
  || cannot_check "I could not read which files this change touches"
NOURS="$(printf '%s' "$OURS_JSON" | jq 'length')"
NEED=2
[ "$NOURS" -lt 2 ] && NEED="$NOURS"

# Our own per-file additions and deletions, to compare with the numbers the list already carries.
OWN_STATS='{}'
if [ "$BASE_OK" -eq 1 ]; then
  OWN_STATS="$(git diff --no-renames --numstat origin/main...HEAD 2>/dev/null \
    | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | select(length >= 3 and .[0] != "-") | {key: .[2], value: (.[0] + ":" + .[1])}) | from_entries')" \
    || OWN_STATS='{}'
fi
HAVE_EDITS="$(printf '%s' "$OURS_JSON" | jq --argjson st "$OWN_STATS" '[.[] | select($st[.] != null)] | length')"

OWN_SUBJECTS=""
if [ "$BASE_OK" -eq 1 ]; then
  OWN_SUBJECTS="$(git log --no-merges --format=%s origin/main..HEAD 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$MODE" = merge ]; then cannot_check "I could not read the titles of this change's steps"; fi
fi
SUBJ_OURS_JSON="$(printf '%s\n' "$OWN_SUBJECTS" | jq -R -s -c "$JQ_DEFS"' split("\n") | map(norm | select(length > 0 and (generic | not))) | unique')" \
  || cannot_check "I could not read the titles of this change's steps"

# ---- the other open changes ---------------------------------------------------------------------
LIST_JSON="$(bounded 40 gh pr list --state open -L "$LIST_CAP" --json number,title,url,isDraft,files,headRefName,headRepositoryOwner,isCrossRepository 2>/dev/null)"
rc=$?
[ "$rc" -ne 0 ] && cannot_check "GitHub did not answer when I asked for the open changes" # mut:listfail
printf '%s' "$LIST_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || cannot_check "GitHub gave me an answer I could not read"
LIST_COUNT="$(printf '%s' "$LIST_JSON" | jq 'length')"

# Who wrote each change. `gh pr list --json` has no author-association field, so read it from the REST
# list of open pulls (one paginated call, 100 a page). Without it nobody can be told from a stranger,
# so a failed read is "could not check", never a guess.
ASSOC_MAP='{}'
if [ "$LIST_COUNT" -gt 0 ]; then
  ASSOC_RAW="$(bounded 30 gh api "repos/{owner}/{repo}/pulls?state=open&per_page=100" --paginate --jq '.[] | {number: .number, assoc: (.author_association // "")}' 2>/dev/null)"
  rc=$?
  [ "$rc" -ne 0 ] && cannot_check "GitHub did not answer when I asked who wrote the open changes" # mut:authread
  ASSOC_MAP="$(printf '%s\n' "$ASSOC_RAW" | jq -s -c 'map({key: (.number | tostring), value: .assoc}) | from_entries')" \
    || cannot_check "GitHub gave me an answer I could not read"
fi

# This change is never an overlap: not by number, and not a change from the same branch of this
# repository (a fork's change that merely shares the branch name is somebody else's).
OTHERS="$(printf '%s' "$LIST_JSON" | jq -c --arg cur "$CUR_PR" --arg head "$CUR_HEAD" --arg owner "$VIEW_OWNER" --argjson assoc "$ASSOC_MAP" "$SELF_DEFS"'[.[] | select((own_number or own_branch) | not) | .authorAssociation = ($assoc[(.number | tostring)] // "")]')" \
  || cannot_check "GitHub gave me an answer I could not read"

# A change that lists PAGE_CAP files may have more: GitHub caps the list per change. Re-read the team
# changes whose first page shares nothing with us, with a paginated call; a failed re-read is "could
# not check", never clear. Nothing to look for (no files) or nothing to learn (the first page already
# shares a file) means no call.
OV='{}'
CAPPED=""
if [ "$NOURS" -gt 0 ]; then
  CAPPED="$(printf '%s' "$OTHERS" | jq -r --argjson cap "$PAGE_CAP" --argjson ours "$OURS_JSON" "$JQ_DEFS"'.[] | select(((.authorAssociation // "") | trusted) and (.files | length) >= $cap and ([.files[]?.path | clean | select((noise | not) and IN($ours[]))] | length) == 0) | .number')"
fi
for n in $CAPPED; do
  over_deadline && cannot_check "I ran out of time reading the full file list of a large change"
  pages="$(bounded 30 gh api "repos/{owner}/{repo}/pulls/$n/files?per_page=100" --paginate --jq '.[].filename' 2>/dev/null)"
  rc=$?
  [ "$rc" -ne 0 ] && cannot_check "GitHub did not answer when I asked for the full file list of a large change" # mut:pagefail
  arr="$(printf '%s\n' "$pages" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  OV="$(printf '%s' "$OV" | jq -c --arg n "$n" --argjson a "$arr" '. + {($n): $a}')"
done

# Same-file signal. `eq` lists the shared files whose additions/deletions equal ours (or cannot be
# told because the file list was re-read by name): only those can carry the identical edit.
CAND="$(printf '%s' "$OTHERS" | jq -c --argjson ours "$OURS_JSON" --argjson ov "$OV" --argjson st "$OWN_STATS" "$JQ_DEFS$SHARED_DEFS"'
  [ .[] | . as $p
    | ($ov[($p.number | tostring)]) as $ovf
    | ($p.files // []) as $pf
    | (if $ovf != null then $ovf else [$pf[]?.path] end) as $eff
    | sharedfiles($eff; $ours) as $sh
    | { number: $p.number, title: ($p.title // ""), url: ($p.url // ""), draft: ($p.isDraft // false),
        trusted: (($p.authorAssociation // "") | trusted),
        files: $sh,
        eq: [ $sh[] | . as $f | select($st[$f] != null and ($ovf != null or ([$pf[] | select(.path == $f) | (((.additions // 0) | tostring) + ":" + ((.deletions // 0) | tostring))] | any(. == $st[$f])))) ] } ]')" \
  || cannot_check "GitHub gave me an answer I could not read"

# ---- same-title signal (the change title) ------------------------------------------------------------
SUBJ_NUMS=""
if [ "$SUBJ_OURS_JSON" != "[]" ]; then
  TITLE_HITS="$(printf '%s' "$CAND" | jq -r --argjson s "$SUBJ_OURS_JSON" "$JQ_DEFS"'.[] | select((.title | norm) as $t | ($t | generic | not) and ($s | any(. == $t))) | .number')"
  for n in $TITLE_HITS; do SUBJ_NUMS="$SUBJ_NUMS $n"; done
fi

# ---- same-edit and same-title-history signals: team changes that share a file only -------------------
own_pid() { # own_pid <file> -> the patch identity of OUR edit to the file, or nothing
  local key cf
  key="$(printf '%s' "$1" | cksum | tr ' ' '_')"
  cf="$WORK/own.$key"
  if [ ! -f "$cf" ]; then
    git diff --no-ext-diff --no-color --no-renames origin/main...HEAD -- "$1" 2>/dev/null | git patch-id --stable 2>/dev/null | awk 'NR==1{print $1}' > "$cf"
  fi
  cat "$cf"
}

EDIT_NUMS=""
DIFF_ELIG=0
DIFF_N=0
DIFF_FAILED=0
DEADLINE_HIT=0
DEADLINE_SKIPPED=0
NOBASE=0
NOEDITS=0
[ "$BASE_OK" -eq 1 ] || NOBASE=1 # mut:nobasenote
[ "$BASE_OK" -eq 1 ] && [ "$HAVE_EDITS" -eq 0 ] && NOEDITS=1
SHARING="$(printf '%s' "$CAND" | jq -r '.[] | select(.trusted and (.files | length) > 0) | (.number | tostring) + ":" + (.eq | length | tostring)')"
for tok in $SHARING; do
  n="${tok%%:*}"
  eqn="${tok##*:}"
  if over_deadline; then DEADLINE_HIT=1; DEADLINE_SKIPPED=$((DEADLINE_SKIPPED + 1)); continue; fi
  # Edits: only when we have a saved edit of our own and the numbers can match.
  if [ "$BASE_OK" -eq 1 ] && [ "$HAVE_EDITS" -gt 0 ] && [ "$eqn" -ge "$NEED" ] && [ "$NEED" -gt 0 ]; then
    DIFF_ELIG=$((DIFF_ELIG + 1))
    if [ "$DIFF_N" -lt "$DIFF_CAP" ]; then
      DIFF_N=$((DIFF_N + 1))
      d="$WORK/pd$n"; mkdir -p "$d"
      bounded 30 gh pr diff "$n" > "$d/all.diff" 2>/dev/null
      rc=$?
      if [ "$rc" -ne 0 ]; then
        if over_deadline; then DEADLINE_HIT=1; DEADLINE_SKIPPED=$((DEADLINE_SKIPPED + 1)); continue; fi
        DIFF_FAILED=$((DIFF_FAILED + 1))
      else
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
        printf '%s' "$CAND" | jq -r --argjson n "$n" '.[] | select(.number == $n) | .eq[]' > "$WORK/eq.$n"
        E=0
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          mine="$(own_pid "$f")"
          [ -n "$mine" ] || continue
          nf="$(grep -lFx -- "$f" "$d"/*.name 2>/dev/null | head -n 1)"
          [ -n "$nf" ] || continue
          theirs="$(git patch-id --stable < "${nf%.name}.patch" 2>/dev/null | awk 'NR==1{print $1}')"
          if [ -n "$theirs" ] && [ "$theirs" = "$mine" ]; then
            E=$((E + 1))
            if [ "$(jq -n --argjson e "$E" --argjson o "$NOURS" "$EDIT_RULE_JQ")" = true ]; then
              EDIT_NUMS="$EDIT_NUMS $n"
              break
            fi
          fi
        done < "$WORK/eq.$n"
      fi
    fi
  fi
  # Same title in the step-by-step history: one read of up to 100 steps, only for what shares a file.
  case " $SUBJ_NUMS $EDIT_NUMS " in *" $n "*) continue ;; esac
  if [ "$SUBJ_OURS_JSON" != "[]" ]; then
    if over_deadline; then DEADLINE_HIT=1; DEADLINE_SKIPPED=$((DEADLINE_SKIPPED + 1)); continue; fi
    lines="$(bounded 30 gh api "repos/{owner}/{repo}/pulls/$n/commits?per_page=100" --paginate --jq '.[].commit.message | split("\n")[0]' 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      if over_deadline; then DEADLINE_HIT=1; DEADLINE_SKIPPED=$((DEADLINE_SKIPPED + 1)); continue; fi
      cannot_check "GitHub did not answer when I asked for the history of another change"
    fi
    hit="$(printf '%s\n' "$lines" | jq -R -s -r --argjson s "$SUBJ_OURS_JSON" "$JQ_DEFS"'split("\n") | map(norm | select(length > 0 and (generic | not))) | if any(.[]; . as $t | $s | any(. == $t)) then "yes" else "no" end')"
    [ "$hit" = yes ] && SUBJ_NUMS="$SUBJ_NUMS $n"
  fi
done
# shellcheck disable=SC2086 # the lists are space-separated integers
EDIT_JSON="$(printf '%s\n' $EDIT_NUMS | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')"
# shellcheck disable=SC2086
SUBJ_JSON="$(printf '%s\n' $SUBJ_NUMS | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')"

# ---- decide ----------------------------------------------------------------------------------------
OVER="$(printf '%s' "$CAND" | jq -c --argjson edits "$EDIT_JSON" --argjson subj "$SUBJ_JSON" '
  map(. + { edit: (.number as $n | $edits | any(. == $n)), subject: (.number as $n | $subj | any(. == $n)) })
  | map(select((.files | length) > 0 or .subject))
  | sort_by(.number)')" \
  || cannot_check "I could not combine what I found"

N_OVER="$(printf '%s' "$OVER" | jq 'length')"
IDS="$(printf '%s' "$OVER" | jq -r 'map(.number | tostring) | join(",")')"
DUP="$(printf '%s' "$OVER" | jq 'any(.[]; .trusted and (.edit or .subject))')"
VEH_IN=false
[ -n "$VEHICLE" ] && VEH_IN="$(printf '%s' "$OVER" | jq --arg v "$VEHICLE" 'any(.[]; .trusted and (.number | tostring) == $v)')"

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
  CODE=13 # mut:sharedblock
fi

# ---- say it in plain words ------------------------------------------------------------------------
if [ "$N_OVER" -eq 0 ]; then
  say "No other open work overlaps with this change."
else
  say "Other open work overlaps with this change:"
  printf '%s' "$OVER" | jq -r "$JQ_DEFS"'.[] |
    "- \"" + (.title | disp) + "\" - " + (.url | clean),
    (if (.files | length) > 0 then "    Changes some of the same files as yours: " + (.files | map(clean) | .[0:5] | join(", ")) + (if (.files | length) > 5 then " and " + (((.files | length) - 5) | tostring) + " more" else "" end) else empty end),
    (if .edit then "    This change makes the same edit as yours." else empty end),
    (if .subject then "    It has a change with the same title as one of yours." else empty end),
    (if .trusted | not then "    It comes from someone outside the team, so I list it for information only and will not hold anything back for it." else empty end),
    (if .draft then "    It is still being worked on and is not ready yet." else empty end)'
fi

if [ "$LIST_COUNT" -ge "$LIST_CAP" ]; then
  say "GitHub listed $LIST_CAP open changes, the most I can read at once, so there may be more that I did not see."
fi
if [ "$DIFF_ELIG" -gt "$DIFF_CAP" ]; then
  say "I compared the actual edits of $DIFF_CAP of the $DIFF_ELIG changes that could be the same edit as yours; the rest are matched by file name only."
fi
if [ "$DIFF_FAILED" -gt 0 ]; then
  say "I could not compare the edits themselves for $DIFF_FAILED of them, so those are matched by file name only."
fi
if [ "$DEADLINE_HIT" -eq 1 ]; then
  say "I stopped comparing after $DEADLINE_SECS seconds so this check would not hold things up; $DEADLINE_SKIPPED of the changes that share files with yours were matched by file name and title only."
fi
if [ "$NOBASE" -eq 1 ]; then
  say "I could not compare the edits themselves because I cannot see where this work started from yet."
elif [ "$NOEDITS" -eq 1 ]; then
  say "I cannot compare the actual edits yet because none of the files for this work have saved changes, so shared files are matched by name only. The edit check runs again before this is merged."
fi

case "$CODE" in
  0)
    : ;;
  10)
    say "What this means: another open change was chosen to carry this work. I am holding mine back and will not touch theirs."
    say "Next step for me: wait until that change is live, then check again."
    ;;
  11)
    say "What this means: this change was chosen to carry the work, so the other changes should step aside. I am not touching them."
    say "Next step for me: carry on with this change; the others are listed only so you know they exist."
    ;;
  12)
    say "What this means: another open change already covers the same work and nobody has chosen which one carries it. I am holding mine back."
    say "Next step for me: ask the engineering lead agent to choose one change to carry the work and record its decision (a technical choice, not a question for the operator), then run this check again with the chosen change named."
    ;;
  13)
    say "What this means: these changes touch some of the same files, which is common and does not stop anything. Whichever goes second may need small adjustments."
    say "Next step for me: carry on; I will not touch their changes."
    ;;
esac

finish "$CODE" "${IDS:-none}"
