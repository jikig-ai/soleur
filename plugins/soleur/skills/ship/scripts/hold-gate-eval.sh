#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2018,SC2019  # A && B || C is the check idiom; tr A-Z is the portable ASCII lowering
# The /ship Phase 6 step 5 hold evaluator: turns the recorded `Gate:` predicates of `## Operator Holds` (or of a
# Production Envelope's `Preconditions:`) into a mechanical verdict, so a hold is discharged by evidence and never
# by a model's reading of prose. Procedure and wording: skills/ship/references/operator-holds.md. Format source:
# skills/brainstorm-techniques/references/standing-delegation.md.
#
# Property: plan mode verifies the delegation, and a hold is discharged only if a Standing Delegation is cited
# (verifier rc 0 AND a first line `delegation: valid`) and EVERY one of its `Gate:` predicates is a known kind that
# evaluates true now. Any other state leaves it standing: an unknown kind, an unreadable probe, a missing,
# ambiguous or invalid delegation, a missing envelope, a timeout, a missing time-limit tool, a hold with no gate.
# --file mode does not verify a delegation (the caller just did); it only measures one envelope's `Preconditions:` gates.
#
# Usage:
#   hold-gate-eval.sh --plan <plan.md>                              evaluate `## Operator Holds`
#   hold-gate-eval.sh --file <envelope.md> --section "<title>"      evaluate one envelope's gates
#   hold-gate-eval.sh --file "<envelope.md>#<title>"                the same, addressed as the verifier does
# Run from the repository root (repo-relative paths are resolved from the working directory). The title is matched
# without regard to case against `##`..`####` headings (substring).
#
# Plan format (read from the file, never from conversation). The heading is `## Operator Holds` at level 2 to 4,
# any case; a section ends at the next heading of the same or a shallower level:
#   ## Operator Holds
#   Delegation: <comment url>        exactly one; without it no hold can be discharged here (exit 3)
#   Envelope: <path>[#<title>]       REQUIRED beside a Delegation line; passed to the verifier
#   - Hold: <the operator's words, verbatim>
#     Gate: pr-merged <N> | no-inflight-run <workflow-file>
# `command` and `run-green` are deferred. The first real consumer re-adds them, and only by CTO ruling. A `Gate:`
# line of any other kind is an unknown kind: it exits 2 and the hold stands. Markers (`Hold:`, `Gate:`,
# `Delegation:`, `Envelope:`) are read in any case, with or without the list dash and a space before the colon.
# Lines inside a code fence (same character to close, at least as long) are examples and are ignored.
#
# Exit: 0 every hold discharged (or none recorded: an absent or empty section is a no-op);
#       1 at least one hold STANDS; 2 cannot evaluate (treated as STANDS by the caller; includes a hold or a gate
#       outside any section this script can read, a Delegation line with zero holds, two Delegation or
#       Envelope lines, a missing Envelope line, an unknown kind, an unreadable probe, an unreadable delegation,
#       a missing time-limit tool);
#       3 no `Delegation:` line anywhere in the hold sections: legacy prose holds. Decided BEFORE every structure
#       and tool check, so the caller keeps its prose evaluation (operator-holds.md section 3).
# stdout: when a delegation was checked, its verdict line first (`delegation: <valid|invalid|unverifiable>
# reason=<token>`); then one plain line per hold, then `holds: N discharged: M standing: K`. A `Done:` line carries
# the gate text that was true. Exit 2 and 1 are never converted to a pass by any caller; nothing here retries a
# failed probe into a pass. Any other status the caller sees (127 script not found, 124, 137) is a hold that was
# not checked: treat it as 2.
#
# `Operator-reserved:` (at the START of a hold's words, any case) marks a hold that reserves the decision to the
# operator (pricing approval, brand copy, spend). A gate only says WHEN a condition is true, never WHO may clear the
# hold, so such a hold always STANDS: it is printed `Reserved for you: ... - only you can clear this`, its gates are
# not probed, and the run exits 2. Every `Hold:` or `Gate:` line must sit inside a readable hold section; one that does
# not (a misspelt second heading, text after the next heading) is exit 2, never silently dropped. --file mode reads the
# COMMITTED blob (HEAD), exactly as the verifier does, never the working tree: an untracked, symlinked or dirty file
# cannot change the answer. Test seam: HGE_VERIFY_TIMEOUT (seconds, 1-59) can only SHORTEN the 60 s verifier limit.
#
# The default branch is resolved once (origin/HEAD, else `git ls-remote --symref`); `pr-merged` needs MERGED into
# it and the merge commit reachable from HEAD after a fresh fetch of it. Every gh, git and verifier call gets
# `</dev/null`, so a call that drains stdin cannot swallow the remaining gates or holds. In flight means the
# status is queued, in_progress, waiting, requested or pending (ONE `gh run list`, the last 100 runs); a status
# this script does not know is exit 2.
#
# `set -uo pipefail`, deliberately NOT `-e`. Portable to bash 3.2 and mawk. Lines ending `# mut:<name>` are the
# mutation points the suite edits to prove each check can fail.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VERIFY="$SCRIPT_DIR/../../../scripts/delegation-verify.sh"
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "${WORK:?}"; return 0; }
trap cleanup EXIT

die2() { printf '%s\n' "$1" >&2; exit 2; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
# Control characters, C1 controls, zero-width and bidi marks and the line/paragraph separators are dropped (byte-wise: LC_ALL=C).
clean_text() { printf '%s' "$1" | tr -d '[:cntrl:]' | sed -e $'s/\xc2[\x80-\x9f]//g' -e $'s/\xe2\x80[\x8b-\x8f\xa8-\xae]//g' -e $'s/\xe2\x81[\xa6-\xa9]//g' -e $'s/\xef\xbb\xbf//g' | cut -c1-160; } # mut:clean-text

VT=60
case "${HGE_VERIFY_TIMEOUT:-}" in ''|*[!0-9]*) ;; *) [ "$HGE_VERIFY_TIMEOUT" -ge 1 ] && [ "$HGE_VERIFY_TIMEOUT" -lt 60 ] && VT="$HGE_VERIFY_TIMEOUT" ;; esac
TO10=(); TO30=(); TO60=(); HAVE_TO=0
if command -v timeout >/dev/null 2>&1; then TO10=(timeout 10); TO30=(timeout 30); TO60=(timeout "$VT"); HAVE_TO=1
elif command -v gtimeout >/dev/null 2>&1; then TO10=(gtimeout 10); TO30=(gtimeout 30); TO60=(gtimeout "$VT"); HAVE_TO=1; fi

DEFBR=""; DEFBR_DONE=""
resolve_default_branch() { # sets DEFBR to the repository's default branch name, or leaves it empty
  [ -z "$DEFBR_DONE" ] || return 0
  DEFBR_DONE=1
  local ref
  ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD </dev/null 2>/dev/null)"; ref="${ref#origin/}"
  if [ -z "$ref" ]; then
    ref="$(GIT_TERMINAL_PROMPT=0 ${TO10[@]+"${TO10[@]}"} git ls-remote --symref origin HEAD </dev/null 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p' | head -1)"
  fi
  [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] && DEFBR="$ref" # mut:defbr
  return 0
}

FETCHED=""; FETCH_RC=0
ensure_fetch() {
  [ -n "$FETCHED" ] && return "$FETCH_RC"
  FETCHED=1
  GIT_TERMINAL_PROMPT=0 ${TO30[@]+"${TO30[@]}"} git fetch -q origin "$DEFBR" </dev/null >/dev/null 2>&1; FETCH_RC=$? # mut:fetch
  return "$FETCH_RC"
}

gh_json() { # <outfile> <gh args...>: 0 only when gh succeeded and printed valid JSON
  local out="$1"; shift
  ${TO10[@]+"${TO10[@]}"} gh "$@" > "$out" 2>/dev/null </dev/null || return 1 # mut:stdin-gh
  jq -e . "$out" >/dev/null 2>&1 </dev/null
}

known_kind() { case "$1" in pr-merged|no-inflight-run) return 0 ;; esac; return 1; }

GRES=""; GWHY=""
gate_pr_merged() {
  local n="$1" st sha base rc
  [[ "$n" =~ ^[0-9]+$ ]] || { GRES=UNEVAL; GWHY="the earlier change is not named by a plain number"; return; }
  resolve_default_branch
  [ -n "$DEFBR" ] || { GRES=UNEVAL; GWHY="I could not tell which line of work is the main one"; return; }
  ensure_fetch || true
  gh_json "$WORK/pr.json" pr view "$n" --json state,mergeCommit,baseRefName || { GRES=UNEVAL; GWHY="I could not read the state of the earlier change"; return; }
  st="$(jq -r '.state // empty' "$WORK/pr.json" </dev/null)"; sha="$(jq -r '.mergeCommit.oid // empty' "$WORK/pr.json" </dev/null)"; base="$(jq -r '.baseRefName // empty' "$WORK/pr.json" </dev/null)"
  GWHY="the earlier change has not gone live yet"
  if [ "$st" = MERGED ] && [ "$base" = "$DEFBR" ] && [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
    git merge-base --is-ancestor "$sha" HEAD </dev/null >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) GRES=TRUE ;;
      1) GRES=FALSE; GWHY="the earlier change is live, but this work has not been brought up to date with it yet" ;;
      *) GRES=UNEVAL; GWHY="I could not compare this work with the earlier change" ;;
    esac
  else
    GRES=FALSE
    if [ "$st" = MERGED ] && [ "$base" = "$DEFBR" ]; then GWHY="the earlier change is recorded as live, but I cannot see which version of the work it became"
    elif [ "$st" = MERGED ]; then GWHY="the earlier change went into another line of work, not the main one"; fi
  fi
}

gate_no_inflight() {
  local wf="$1" live unk
  [[ "$wf" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] || { GRES=UNEVAL; GWHY="the release is not named as a plain workflow file"; return; }
  if ! gh_json "$WORK/runs.json" run list --workflow "$wf" --limit 100 --json status \
     || ! jq -e 'type == "array" and all(.[]; type == "object")' "$WORK/runs.json" >/dev/null 2>&1 </dev/null; then
    GRES=UNEVAL; GWHY="I could not read the list of running releases"; return
  fi
  live="$(jq '[.[] | .status as $s | select($s == "queued" or $s == "in_progress" or $s == "waiting" or $s == "requested" or $s == "pending")] | length' "$WORK/runs.json" </dev/null)"
  unk="$(jq '[.[] | .status as $s | select($s != "completed" and $s != "queued" and $s != "in_progress" and $s != "waiting" and $s != "requested" and $s != "pending")] | length' "$WORK/runs.json" </dev/null)"
  GWHY="a release is still running"
  if [ "${live:-1}" -gt 0 ]; then GRES=FALSE
  elif [ "${unk:-1}" -gt 0 ]; then GRES=UNEVAL; GWHY="a release is in a state I do not know" # mut:status-unknown
  else GRES=TRUE; fi
}

eval_gate() { # <gate text after `Gate:`> -> GRES (TRUE|FALSE|UNEVAL), GWHY
  local text="$1" kind rest
  GRES=UNEVAL; GWHY="I do not know this kind of condition, so it stays on hold"
  kind="${text%%[[:space:]]*}"; rest="$(trim "${text#"$kind"}")"
  known_kind "$kind" || { GRES=UNEVAL; return; } # mut:unknown-kind
  case "$kind" in
    pr-merged) gate_pr_merged "$rest" ;;
    no-inflight-run) gate_no_inflight "$rest" ;;
  esac
}

# split_sections <file> <mode> <match>: sections into $WORK/sec.<n> (heads in sec.heads), count in sec.count.
# Plan mode: a heading of level 2-4 reading "Operator Holds" in any case. File mode: a level 2-4 heading containing
# <match> (any case). A section ends at the next heading of the same or a shallower level. Fenced lines are text.
split_sections() {
  awk -v dir="$WORK" -v mode="$2" -v match_text="$3" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function fence(   tok, c, n) {
      tok = t; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    BEGIN { mt = tolower(match_text) }
    { t = $0; sub(/\r$/, "", t) }
    t ~ /^ ? ? ?(```+|~~~+)/ { fence() } # mut:fence-split
    f == 0 && (t ~ /^#+[ \t]/ || t ~ /^#+$/) {
      match(t, /^#+/); L = RLENGTH
      if (cur != "" && L <= curlvl) { close(cur); cur = "" }
      if (cur == "" && L >= 2 && L <= 4) {
        rest = tolower(trim(substr(t, L + 1))) # mut:heading-ci
        sub(/[ \t]+#+$/, "", rest)
        if (mode == "plan") hit = (rest ~ /^operator[ \t]+holds$/ || rest ~ /^operator[ \t]+holds[^a-z0-9]/); else hit = (mt != "" && index(rest, mt) > 0)
        if (hit) { n++; cur = dir "/sec." n; curlvl = L; print t > (dir "/sec.heads") }
      }
    }
    cur != "" { print $0 > cur }
    END { print n + 0 > (dir "/sec.count") }
  ' "$1"
}

# marker_count <file>: prints how many unfenced `Hold:` or `Gate:` marker lines the file has.
marker_count() {
  awk '
    function fence(   tok, c, n) {
      tok = t; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    { t = $0; sub(/\r$/, "", t) }
    t ~ /^ ? ? ?(```+|~~~+)/ { fence(); next }
    f { next }
    { lt = tolower(t) }
    lt ~ /^[ \t]*(-[ \t]+)?(hold|gate)[ \t]*:/ { found++ }
    END { print found + 0 }
  ' "$1"
}

# parse_items <section file> <mode>: records DELEG / ENVF / HOLD i text / GATE i text / ORPHAN.
parse_items() {
  awk -v mode="$2" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function val(s) { return trim(substr(s, index(s, ":") + 1)) }
    function fence(   tok, c, n) {
      tok = t; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    NR == 1 { if (mode == "file") { n = 1; print "HOLD\t1\tthe conditions before the act" } next }
    { t = $0; sub(/\r$/, "", t)
      if (t ~ /^ ? ? ?(```+|~~~+)/) { fence(); next }
      if (f) next
      lt = tolower(t) # mut:ci-markers
      if (mode == "plan" && lt ~ /^[ \t]*(-[ \t]+)?delegation[ \t]*:/) { print "DELEG\t" val(t); next }
      if (mode == "plan" && lt ~ /^[ \t]*(-[ \t]+)?envelope[ \t]*:/) { print "ENVF\t" val(t); next }
      if (mode == "plan" && lt ~ /^[ \t]*(-[ \t]+)?hold[ \t]*:/) { n++; print "HOLD\t" n "\t" val(t); next }
      if (lt ~ /^[ \t]*(-[ \t]+)?gate[ \t]*:/) { if (n > 0) print "GATE\t" n "\t" val(t); else print "ORPHAN"; next }
    }
  ' "$1"
}

print_result_line() { # <verdict> <text> <why> <gate text>
  local gsuffix=""
  [ -z "${4:-}" ] || gsuffix=" - checked: $(clean_text "$4")" # mut:done-gates
  case "$1" in
    OK) printf 'Done: %s%s\n' "$(clean_text "$2")" "$gsuffix" ;;
    WAIT) printf 'Still waiting: %s - %s\n' "$(clean_text "$2")" "$3" ;;
    NEEDS) printf 'Needs a person: %s - only a person can settle this\n' "$(clean_text "$2")" ;;
    RESERVED) printf 'Reserved for you: %s - only you can clear this\n' "$(clean_text "$2")" ;;
    *) printf 'Could not check: %s - %s\n' "$(clean_text "$2")" "$3" ;;
  esac
}

# stall_unchecked <sentence> <why>: every hold stays on hold because the record itself cannot be used (exit 2).
stall_unchecked() {
  local i text
  echo "$1"
  while IFS=$'\t' read -r _ i text; do print_result_line UNEVAL "$text" "$2"; done < <(grep '^HOLD' "$WORK/items")
  echo "holds: $NH discharged: 0 standing: $NH"
  exit 2
}

# stand_all <state> <token> <rc-fits>: the delegation did not verify, so every hold stands (1 when invalid, 2 otherwise).
stand_all() {
  local i text
  echo "delegation: $1 reason=$2"
  echo "Your standing approval could not be confirmed, so every hold stays on hold."
  while IFS=$'\t' read -r _ i text; do print_result_line WAIT "$text" "waiting for your standing approval"; done < <(grep '^HOLD' "$WORK/items")
  echo "holds: $NH discharged: 0 standing: $NH"
  [ "$1" = invalid ] && [ "$3" = fits ] && exit 1
  exit 2
}

split_file_title() { # --file "<path>#<title>": the title becomes the section; naming it twice is a usage error
  case "$FILE" in
    *'#'*)
      local ht="${FILE#*#}"
      FILE="${FILE%%#*}"
      [ -n "$ht" ] || die2 "the envelope title after # is empty, so no condition can be found"
      [ -z "$SECTION" ] || die2 "the envelope title is named twice (after # and with --section), so no condition can be found"
      SECTION="$ht" ;;
  esac
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
split_file_title # mut:file-title
if [ -n "$PLAN" ] && [ -z "$FILE" ] && [ -z "$SECTION" ]; then MODE="plan"; SRC="$PLAN"
elif [ -n "$FILE" ] && [ -n "$SECTION" ] && [ -z "$PLAN" ]; then MODE="file"; SRC="$FILE"
else die2 "usage: hold-gate-eval.sh --plan <plan.md> | --file <envelope.md> --section <title> | --file <envelope.md>#<title>"; fi
[ "$MODE" = file ] || { [ -f "$SRC" ] && [ -r "$SRC" ] || die2 "cannot read $SRC, so no hold can be checked"; }
WORK="$(mktemp -d -t hge.XXXXXXXX)" || die2 "could not create a scratch folder"

# read_head_blob <path>: --file mode reads the COMMITTED regular file (as the verifier does), never the working tree.
read_head_blob() {
  local p="$1" ent
  case "$p" in ""|/*|..|../*|*/..|*/../*|*[*?[]*) die2 "the envelope path is not a plain path inside this repository, so its conditions are treated as not met" ;; esac
  p="${p#./}"
  command -v git >/dev/null 2>&1 || die2 "git is not installed, so no hold can be checked"
  ent="$(GIT_LITERAL_PATHSPECS=1 git ls-tree HEAD -- "./$p" </dev/null 2>/dev/null | head -1)"
  case "$ent" in "100644 blob "*) ;; *) die2 "the envelope file is not saved in the project history as a normal file, so its conditions are treated as not met" ;; esac
  GIT_LITERAL_PATHSPECS=1 git show "HEAD:./$p" > "$WORK/head.md" 2>/dev/null </dev/null || die2 "could not read the saved envelope file, so its conditions are treated as not met"
}
if [ "$MODE" = file ]; then read_head_blob "$FILE"; SRC="$WORK/head.md"; fi # mut:file-head

need_tools() { # after the no-delegation exit: nothing below can run without these
  command -v jq >/dev/null 2>&1 || die2 "jq is not installed, so no hold can be checked"
  command -v gh >/dev/null 2>&1 || die2 "the GitHub command line tool is not installed, so no hold can be checked"
  command -v git >/dev/null 2>&1 || die2 "git is not installed, so no hold can be checked"
  [ "$HAVE_TO" -eq 1 ] || die2 "no time limit tool (timeout) is available on this machine, so no hold can be checked" # mut:need-timeout
}

split_sections "$SRC" "$MODE" "$SECTION"
CNT="$(cat "$WORK/sec.count" 2>/dev/null || echo 0)"
if [ "$MODE" = plan ]; then
  if [ "$CNT" -eq 0 ]; then
    [ "$(marker_count "$SRC")" -gt 0 ] && { echo "I found a hold that is not inside a hold section I can read, so I am treating it as still on hold."; exit 2; } # mut:stray
    echo "No holds are recorded, so there is nothing to wait for."
    echo "holds: 0 discharged: 0 standing: 0"
    exit 0
  fi
  nonblank=0; ND=0; NE=0; NH=0; : > "$WORK/items"
  for ((s = 1; s <= CNT; s++)); do
    awk 'NR > 1 && /[^ \t\r]/ { f = 1 } END { exit (f ? 0 : 1) }' "$WORK/sec.$s" && nonblank=1
    parse_items "$WORK/sec.$s" plan > "$WORK/items.$s"
    cat "$WORK/items.$s" >> "$WORK/items"
  done
  if [ "$nonblank" -eq 0 ]; then
    [ "$(marker_count "$SRC")" -eq 0 ] || { echo "I found a hold that is not inside a hold section I can read, so I am treating it as still on hold."; exit 2; }
    echo "No holds are recorded, so there is nothing to wait for."
    echo "holds: 0 discharged: 0 standing: 0"
    exit 0
  fi
  ND="$(grep -c '^DELEG' "$WORK/items" || true)"; NE="$(grep -c '^ENVF' "$WORK/items" || true)"; NH="$(grep -c '^HOLD' "$WORK/items" || true)"
  [ "$ND" -gt 0 ] || { echo "No standing approval is recorded, so the usual check applies."; [ "$NH" -eq 0 ] || echo "holds: $NH discharged: 0 standing: $NH"; exit 3; } # mut:no-deleg
  SEC_M=0; for ((s = 1; s <= CNT; s++)); do SEC_M=$((SEC_M + $(marker_count "$WORK/sec.$s"))); done
  [ "$(marker_count "$SRC")" -le "$SEC_M" ] || { echo "I found a hold that is not inside a hold section I can read, so I am treating every hold as still on hold."; echo "holds: $NH discharged: 0 standing: $NH"; exit 2; } # mut:stray-all
  [ "$ND" -eq 1 ] || stall_unchecked "More than one standing approval is named, so I am treating every hold as still on hold." "the standing approval is not clear" # mut:deleg-multi
  [ "$CNT" -eq 1 ] || stall_unchecked "The plan has more than one hold section, so I am treating every hold as still on hold." "the plan is not clear"
  [ "$NE" -eq 1 ] || stall_unchecked "The standing approval does not name exactly one runbook it covers, so I am treating every hold as still on hold." "the standing approval is incomplete" # mut:envelope-req
  need_tools
  if grep -q '^ORPHAN' "$WORK/items"; then echo "A condition is written outside any hold, so I am treating every hold as still on hold."; echo "holds: $NH discharged: 0 standing: $NH"; exit 2; fi
  [ "$NH" -gt 0 ] || { echo "I found a hold section but could not read any hold in it, so I am treating it as still on hold."; exit 2; } # mut:zero-holds
  DELEG="$(awk -F'\t' '$1 == "DELEG" { print $2; exit }' "$WORK/items")"
  ENVF="$(awk -F'\t' '$1 == "ENVF" { print $2; exit }' "$WORK/items")"
  [ -f "$VERIFY" ] || { echo "I could not find the standing-approval checker, so every hold stays on hold."; echo "holds: $NH discharged: 0 standing: $NH"; exit 2; }
  ${TO60[@]+"${TO60[@]}"} bash "$VERIFY" verify --delegation "$DELEG" --envelope "$ENVF" </dev/null > "$WORK/verdict" 2>"$WORK/verdict.err"; VRC=$? # mut:stdin-verify
  VLINE="$(head -1 "$WORK/verdict" 2>/dev/null)"; VSTATE=""; VTOKEN=""
  if [[ "$VLINE" =~ ^delegation:\ (valid|invalid|unverifiable)\ reason=([a-z0-9-]+)$ ]]; then VSTATE="${BASH_REMATCH[1]}"; VTOKEN="${BASH_REMATCH[2]}"; fi
  VOK=0; [ "$VSTATE" = valid ] && [ "$VRC" -eq 0 ] && VOK=1 # mut:deleg-rc
  if [ "$VOK" -eq 1 ]; then
    echo "delegation: valid reason=$VTOKEN"
  else
    [ -n "$VSTATE" ] || { VSTATE=unverifiable; VTOKEN=no-answer; }
    FITS=no; [ "$VSTATE" = invalid ] && [ "$VRC" -eq 1 ] && FITS=fits
    [ "$VSTATE" = valid ] && { VSTATE=unverifiable; VTOKEN=verifier-error; }
    [ "$VSTATE" = invalid ] && [ "$FITS" != fits ] && { VSTATE=unverifiable; VTOKEN=verifier-error; }
    stand_all "$VSTATE" "$VTOKEN" "$FITS" # mut:deleg-valid
  fi
else
  [ "$CNT" -eq 1 ] || { echo "I could not find exactly one matching envelope section, so I am treating its conditions as not met."; exit 2; }
  need_tools
  parse_items "$WORK/sec.1" "$MODE" > "$WORK/items"
  NH="$(grep -c '^HOLD' "$WORK/items" || true)"
  [ "$(grep -c '^GATE' "$WORK/items" || true)" -ge 1 ] || { echo "The envelope lists no conditions I can check, so I am treating them as not met."; exit 2; }
fi

DISCHARGED=0; STANDING=0; ANY_UNEVAL=0
while IFS=$'\t' read -r _ i text; do
  lt="$(printf '%s' "$text" | tr 'A-Z' 'a-z')"
  case "$lt" in operator-reserved:*) print_result_line RESERVED "$text" ""; STANDING=$((STANDING + 1)); ANY_UNEVAL=1; continue ;; esac # mut:reserved
  awk -F'\t' -v i="$i" '$1 == "GATE" && $2 == i { print $3 }' "$WORK/items" > "$WORK/g.$i"
  ng="$(wc -l < "$WORK/g.$i" | tr -d ' ')"
  HV=OK; WHY=""; GTXT=""
  [ "$ng" -gt 0 ] || HV=NEEDS # mut:zero-gates
  while IFS= read -r gate; do
    eval_gate "$gate"
    GTXT="${GTXT:+$GTXT; }$gate"
    case "$GRES" in TRUE) ;; FALSE) [ "$HV" = OK ] && { HV=WAIT; WHY="$GWHY"; } ;; *) HV=UNEVAL; WHY="$GWHY"; ANY_UNEVAL=1 ;; esac # mut:all-gates
  done < "$WORK/g.$i"
  print_result_line "$HV" "$text" "$WHY" "$GTXT"
  if [ "$HV" = OK ]; then DISCHARGED=$((DISCHARGED + 1)); else STANDING=$((STANDING + 1)); fi
done < <(grep '^HOLD' "$WORK/items")

echo "holds: $NH discharged: $DISCHARGED standing: $STANDING"
[ "$ANY_UNEVAL" -eq 0 ] || exit 2
[ "$STANDING" -eq 0 ] || exit 1
exit 0
