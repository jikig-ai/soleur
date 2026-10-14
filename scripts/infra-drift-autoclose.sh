#!/usr/bin/env bash
# infra-drift-autoclose.sh -- decide whether an open `infra-drift` issue may be auto-closed.
#
# Called by the "Auto-close any open drift issues for this stack" step of
# .github/workflows/apply-deploy-pipeline-fix.yml. That workflow plans and applies a FIXED set of
# `-target` terraform_data resources, while the drift issue is filed by
# scheduled-terraform-drift.yml from an UNTARGETED `terraform plan -detailed-exitcode`. So the
# comment "re-aligned with HEAD" is only substantiated for the targets; an issue whose plan shows
# a pending hcloud_server replacement is NOT re-aligned and must stay open.
#
# Modes:
#   (default)    loop over open `infra-drift` issues; close each one the classifier clears.
#   --classify   read {"body": <string>, "comments": [<string>, ...]} on stdin, print exactly one
#                line (`close` or `skip:<slug>`), never call gh. Empty stdin is the empty envelope.
#                Needs jq (without it the probe prints skip:unparseable).
#
# EVIDENCE RULES. Only artifacts written by the drift bot count (loop mode blanks any other
# author's text before classifying: the repo is public and anyone can comment). The decision judges
# the NEWEST plan-bearing artifact (the last of body + comments carrying `<summary>Plan output`),
# because scheduled-terraform-drift.yml writes the first plan into the body and every later scan as
# a comment. Anything not provably complete, readable and replacement-free is a skip.
#
# SKIP SLUGS (stable; pinned by infra-drift-autoclose.test.sh) and what an operator does next:
#   hcloud-server-replacement  newest plan still shows a server replace/destroy/create: leave open,
#                              close by hand once the host is replaced (web-host-replace runbook)
#   plan-incomplete            recorded plan has no terraform terminator (cut by head -c 60000):
#                              re-run scheduled-terraform-drift.yml for a fresh plan
#   plan-truncated-marker      the plan summary says "(truncated)": same as plan-incomplete
#   no-plan-block              no bot-written plan on the issue: not machine-filed, close by hand
#   empty-body                 bot body empty or authored by someone else: close by hand
#   gh-view-failed             reading the issue failed (see the notice): re-run the apply
#   classifier-failed          the classifier itself failed: unexpected, read the run log
#   unparseable                the envelope was not valid: unexpected, read the run log
#   non-numeric-issue-number   unexpected list entry
# A failed close or view is a ::warning::/skip with rc 0 (deliberately softer than the old `set -e`
# step); only an unreadable LIST is rc 1.
#
# `# mut:<tag>` trailers are anchors rewritten by the mutation battery in the test file: each tag
# must occur on exactly one line and that whole line is replaced. Keep the tag on its line.
#
# No `set -e`: every gh/jq call is captured with an explicit `|| rc=$?` so a failing producer is
# never read as an empty-but-OK result. Functions called as `$(fn)` have a stdout-only contract.
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
# Byte semantics: a locale-dependent [A-Za-z] class made non-ASCII addresses a silent close.
export LC_ALL=C

LIST_LIMIT=200
ERR_TAIL=300

# R1: a resource-header line for exactly type hcloud_server, with any module prefix, any instance
# key (keys may hold `/`, spaces) and any trailing qualifier such as `(deposed object ...)` or
# `is tainted, so`. `hcloud_server_network` is NOT matched (`hcloud_server` must be followed by `.`).
R1_PREFIX='^[[:space:]]*#[[:space:]]+([^[:space:]]*\.)?hcloud_server\..*[[:space:]]'
R1_ACTIONS='(must|will) be (replaced|destroyed|created)' # mut:r1-actions
# R2: the resource marker line: -/+ and +/- (replace), `-` (destroy), `+` (create). `~` (in-place
# update) is deliberately not matched.
R2='(^|[[:space:]])(-/\+|\+/-|-|\+)[[:space:]]+resource[[:space:]]+"hcloud_server"' # mut:r2
# `didn.t`: the `.` matches any apostrophe variant.
TERMINATORS='^Plan: [0-9]+ to |^Note: You didn.t use the -out option'

# gmatch <ERE> <text> <rc2-verdict:0|1> : grep -E over a here-string. rc 0/1 are match/no match;
# any other rc (grep error) returns <rc2-verdict>, chosen per caller to FAIL CLOSED.
gmatch() {
  local rc=0
  grep -Eq -- "$1" <<<"$2" || rc=$?
  [[ "$rc" -le 1 ]] || return "$3"
  return "$rc"
}

# strip CR, then decode the entities the drift filer's email path can emit. `&amp;` goes last and
# the pass runs twice so `&amp;quot;` folds too. Text without `&` is returned untouched (the
# bash substitutions are quadratic on long inputs).
normalize() {
  local t="$1" i amp='&' lt='<' gt='>' dq='"' sq="'"
  t="${t//$'\r'/}"
  if [[ "$t" == *'&'* ]]; then
    for i in 1 2; do
      t="${t//&lt;/"$lt"}"
      t="${t//&gt;/"$gt"}"
      t="${t//&quot;/"$dq"}"
      t="${t//&#39;/"$sq"}"
      t="${t//&amp;/"$amp"}"
    done
  fi
  printf '%s' "$t"
}

# has_hcloud_replacement <raw> <normalized> : scans raw U normalized; a grep error counts as a hit
has_hcloud_replacement() {
  local raw="$1" norm="$2" re1="${R1_PREFIX}${R1_ACTIONS}"
  if gmatch "$re1" "$raw" 0 || gmatch "$re1" "$norm" 0; then return 0; fi
  if gmatch "$R2" "$raw" 0 || gmatch "$R2" "$norm" 0; then return 0; fi
  return 1
}

# is_plan_bearing <normalized> : a grep error counts as plan-bearing (it then fails the other checks)
is_plan_bearing() { gmatch '<summary>Plan output' "$1" 0; }

# has_truncation_marker <normalized> : the email-path title; defence in depth only, because the
# 60000-byte `head -c` cut writes no marker at all (the terminator check is the real test).
has_truncation_marker() { gmatch '<summary>Plan output \(truncated\)' "$1" 0; } # mut:truncmark

# has_complete_terminator <normalized> : terraform prints `Plan: N to ...` or the `-out` footer
# AFTER every resource block, so a cut that dropped a resource block dropped these too. A grep
# error counts as "not found".
has_complete_terminator() { gmatch "$TERMINATORS" "$1" 1; } # mut:termfn

# classify : stdin envelope JSON -> one verdict line. stdout-only contract.
classify() {
  local envj tf n i sel=-1 art norm verdict
  envj=$(cat) || return 1
  if [[ ! "$envj" =~ [^[:space:]] ]]; then envj='{"body":"","comments":[]}'; fi
  jq -e 'type=="object" and ((.body // "")|type=="string") and ((.comments // [])|type=="array" and all(.[]; type=="string"))' \
    >/dev/null 2>&1 <<<"$envj" || { printf 'skip:unparseable'; return 0; }
  # One jq call: body, then every comment, NUL-separated, via a temp file (a pipe into mapfile is
  # read a byte at a time).
  tf=$(mktemp) || { printf 'skip:unparseable'; return 0; }
  jq -j '(.body // ""), "\u0000", ((.comments // [])[] | ., "\u0000")' <<<"$envj" >"$tf" 2>/dev/null \
    || { rm -f "$tf"; printf 'skip:unparseable'; return 0; }
  local -a arts=()
  mapfile -d '' -t arts <"$tf"
  rm -f "$tf"
  [[ "${#arts[@]}" -ge 1 ]] || arts=("")
  if [[ ! "${arts[0]}" =~ [^[:space:]] ]]; then printf 'skip:empty-body'; return 0; fi # mut:empty

  # newest first; stop at the first plan-bearing artifact. The cheap raw pre-check cannot miss one:
  # entity decoding never creates the literal `Plan output`.
  n=${#arts[@]}
  for ((i = n - 1; i >= 0; i--)); do
    grep -Fq -- 'Plan output' <<<"${arts[$i]}" || continue
    norm=$(normalize "${arts[$i]}")
    if is_plan_bearing "$norm"; then sel=$i; break; fi # mut:last-artifact
  done
  if [[ "$sel" -lt 0 ]]; then printf 'skip:no-plan-block'; return 0; fi # mut:noplan
  art="${arts[$sel]}"

  verdict=close
  if has_hcloud_replacement "$art" "$norm"; then
    verdict=skip:hcloud-server-replacement
  elif has_truncation_marker "$norm"; then
    verdict=skip:plan-truncated-marker
  fi
  if [[ "$verdict" == close ]] && ! has_complete_terminator "$norm"; then verdict=skip:plan-incomplete; fi # mut:terminator
  printf '%s' "$verdict"
}

# ---------------------------------------------------------------------------------------------
# loop mode
# ---------------------------------------------------------------------------------------------
CONSIDERED=0; CLOSED=0; SKIPPED=0; CLOSE_FAILED=0
declare -A SKIP_REASONS=()
declare -A SKIP_ISSUES=()
ERRF=""

# one-line, control-character-free tail of the stderr capture (a `::` line would be a workflow command)
err_tail() { head -c "$ERR_TAIL" "$ERRF" 2>/dev/null | tr -d '[:cntrl:]'; }

note_skip() {  # <issue> <reason> [detail]
  SKIPPED=$((SKIPPED + 1))
  SKIP_REASONS["$2"]=$(( ${SKIP_REASONS["$2"]:-0} + 1 ))
  SKIP_ISSUES["$2"]="${SKIP_ISSUES["$2"]:-} #$1"
  echo "::notice::drift-autoclose: #$1 left OPEN ($2)${3:+: $3}. See the slug list in scripts/infra-drift-autoclose.sh; an operator can close it by hand."
}

# trusted bot logins: the producer's GITHUB_TOKEN identity in the three spellings gh renders it
BOT_JQ='def bot: . == "github-actions" or . == "app/github-actions" or . == "github-actions[bot]";
  def t: if ((.author.login // "") | bot) then (.body // "") else "" end;
  {body: t, comments: [(.comments // [])[] | t]}'

# read_issue <n> : prints the {body, comments[]} envelope with every non-bot artifact blanked. A
# non-zero rc means the read failed; stdout is untrusted in that case.
read_issue() {
  local raw rc=0
  raw=$(gh issue view "$1" --json author,body,comments 2>"$ERRF") || rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc" # mut:readguard
  jq -c "$BOT_JQ" <<<"$raw" 2>/dev/null
}

do_close() {  # <issue>
  local text rc=0
  text="Auto-closed by \`apply-deploy-pipeline-fix.yml\` after merge ${MERGE_SHA:-unknown}. This workflow applies a fixed set of terraform_data targets; the newest bot-recorded drift plan on this issue showed no pending hcloud_server replacement and was complete, so the drift is treated as re-aligned with HEAD."
  gh issue close "$1" --reason completed --comment "$text" >/dev/null 2>"$ERRF" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    CLOSE_FAILED=$((CLOSE_FAILED + 1))
    echo "::warning::drift-autoclose: closing #$1 failed (rc=$rc): $(err_tail); the loop continues"
    return 0
  fi
  CLOSED=$((CLOSED + 1))
  echo "drift-autoclose: closed #$1"
}

process_issue() {  # <issue>
  local n="$1" envj rc=0 verdict
  CONSIDERED=$((CONSIDERED + 1))
  envj=$(read_issue "$n") || rc=$?
  if [[ "$rc" -ne 0 ]]; then note_skip "$n" gh-view-failed "rc=$rc $(err_tail)"; return 0; fi
  if [[ -z "$envj" ]]; then note_skip "$n" gh-view-failed "empty or unparseable read"; return 0; fi
  verdict=$(classify <<<"$envj") || verdict=skip:classifier-failed # mut:verdict
  [[ "$verdict" == close || "$verdict" == skip:?* ]] || verdict=skip:classifier-failed
  if [[ "$verdict" != close ]]; then note_skip "$n" "${verdict#skip:}"; return 0; fi
  do_close "$n"
}

run_loop() {
  local list rc=0 n reason line
  ERRF=$(mktemp) || { echo "::error::drift-autoclose: mktemp failed"; return 1; }
  trap 'rm -f "${ERRF:-}"' EXIT
  list=$(gh issue list --label "infra-drift" --state open -L "$LIST_LIMIT" \
    --search "infra: drift detected in web-platform in:title" \
    --json number --jq '.[].number' 2>"$ERRF") || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::drift-autoclose: could not list open infra-drift issues (rc=$rc): $(err_tail)"
    return 1
  fi
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then CONSIDERED=$((CONSIDERED + 1)); note_skip "$n" non-numeric-issue-number; continue; fi
    process_issue "$n"
  done <<<"$list"
  if [[ "$CONSIDERED" -ge "$LIST_LIMIT" ]]; then
    echo "::warning::drift-autoclose: the issue list hit the limit ($LIST_LIMIT); further open drift issues were not considered"
  fi
  line="considered=$CONSIDERED closed=$CLOSED skipped=$SKIPPED close_failed=$CLOSE_FAILED"
  echo "drift-autoclose: $line"
  if [[ "$CLOSED" -eq 0 && "$SKIPPED" -gt 0 && -n "${SKIP_REASONS[plan-incomplete]:-}${SKIP_REASONS[no-plan-block]:-}" ]]; then
    echo "::warning::drift-autoclose: nothing closed and issues were skipped as plan-incomplete/no-plan-block; if every issue reads that way, terraform's plan footer or the filer's markup may have changed"
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Drift auto-close"
      echo "$line"
      while IFS= read -r reason; do
        [[ -n "$reason" ]] || continue
        echo "- left open ($reason): ${SKIP_REASONS[$reason]}:${SKIP_ISSUES[$reason]}"
      done < <(printf '%s\n' "${!SKIP_REASONS[@]}" | sort)
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
  fi
  return 0
}

main() {
  case "${1:-}" in
    --classify) classify || printf 'skip:classifier-failed'; echo; return 0 ;;
    "") run_loop ;;
    *) echo "usage: $0 [--classify]" >&2; return 2 ;;
  esac
}
main "$@"
