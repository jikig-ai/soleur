#!/usr/bin/env bash
# infra-drift-autoclose.sh -- decide whether an open `infra-drift` issue may be auto-closed.
#
# Called by the "Auto-close any open drift issues for this stack" step of
# .github/workflows/apply-deploy-pipeline-fix.yml. That workflow plans and applies FIVE
# `-target` terraform_data resources, while the drift issue is filed by
# scheduled-terraform-drift.yml from an UNTARGETED `terraform plan -detailed-exitcode`. So the
# comment "re-aligned with HEAD" is only substantiated for the targets; an issue whose plan shows
# a pending hcloud_server replacement is NOT re-aligned and must stay open.
#
# Modes:
#   (default)    loop over open `infra-drift` issues; close each one the classifier clears.
#   --classify   read {"body": <string>, "comments": [<string>, ...]} on stdin, print exactly one
#                line (`close` or `skip:<slug>`), never call gh. Empty stdin is the empty envelope.
#
# The decision judges the NEWEST plan-bearing artifact (the last of body + comments that carries a
# `<summary>Plan output` block): scheduled-terraform-drift.yml writes the first plan into the body
# and every later scan as a comment, so the newest one is the current observation. Judging the
# union would strand an issue open forever once any scan showed a server replacement, even after
# the host was replaced. Anything not provably complete, readable and replacement-free is a skip.
#
# No `set -e`: every gh/jq call is captured with an explicit `|| rc=$?` so a failing producer is
# never read as an empty-but-OK result. Functions called as `$(fn)` have a stdout-only contract.
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# R1: a resource-header line for exactly type hcloud_server. The address class is a POSIX bracket
# expression with `]` first (backslash is literal inside one, so a `\[\]` spelling ends the class
# at the first `]` and never matches an indexed address). `hcloud_server_network` is NOT matched.
R1_PREFIX='^[[:space:]]*#[[:space:]]+([A-Za-z0-9_-]+\.)*hcloud_server\.[][A-Za-z0-9_."'"'"'-]+[[:space:]]+(is tainted, so )?'
R1_ACTIONS='(must|will) be (replaced|destroyed|created)' # mut:r1-actions
R2='(-/\+|\+/-)[[:space:]]+resource[[:space:]]+"hcloud_server"' # mut:r2
TERMINATORS='^Plan: [0-9]+ to |^Note: You didn.t use the -out option'

# strip CR, then decode the entities the drift filer's email path can emit. `&amp;` goes last and
# the pass runs twice so `&amp;quot;` folds too.
normalize() {
  local t="$1" i amp='&' lt='<' gt='>' dq='"' sq="'"
  t="${t//$'\r'/}"
  for i in 1 2; do
    t="${t//&lt;/"$lt"}"
    t="${t//&gt;/"$gt"}"
    t="${t//&quot;/"$dq"}"
    t="${t//&#39;/"$sq"}"
    t="${t//&amp;/"$amp"}"
  done
  printf '%s' "$t"
}

# has_hcloud_replacement <raw> <normalized> : scans raw U normalized
has_hcloud_replacement() {
  local raw="$1" norm="$2" re1="${R1_PREFIX}${R1_ACTIONS}"
  if grep -Eq -- "$re1" <<<"$raw" || grep -Eq -- "$re1" <<<"$norm"; then return 0; fi
  if grep -Eq -- "$R2" <<<"$raw" || grep -Eq -- "$R2" <<<"$norm"; then return 0; fi
  return 1
}

# is_plan_bearing <normalized>
is_plan_bearing() { grep -Fq -- '<summary>Plan output' <<<"$1"; }

# has_truncation_marker <normalized> : the email-path title; defence in depth only, because the
# 60000-byte `head -c` cut writes no marker at all (the terminator check is the real test).
has_truncation_marker() { grep -Eq -- '<summary>Plan output \(truncated\)' <<<"$1"; }

# has_complete_terminator <normalized> : terraform prints `Plan: N to ...` or the `-out` footer
# AFTER every resource block, so a cut that dropped a resource block dropped these too.
has_complete_terminator() { grep -Eq -- "$TERMINATORS" <<<"$1"; }

# classify_envelope : stdin envelope JSON -> one verdict line. stdout-only contract.
classify() {
  local envj rc=0 body ncom i art norm sel first_plan_idx=-1 last_plan_idx=-1 verdict
  envj=$(cat) || return 1
  if [[ -z "${envj//[[:space:]]/}" ]]; then envj='{"body":"","comments":[]}'; fi
  jq -e 'type=="object" and ((.body // "")|type=="string") and ((.comments // [])|type=="array" and all(.[]; type=="string"))' \
    >/dev/null 2>&1 <<<"$envj" || { printf 'skip:unparseable'; return 0; }
  body=$(jq -r '.body // ""' <<<"$envj") || { printf 'skip:unparseable'; return 0; }
  ncom=$(jq -r '(.comments // []) | length' <<<"$envj") || { printf 'skip:unparseable'; return 0; }
  [[ "$ncom" =~ ^[0-9]+$ ]] || { printf 'skip:unparseable'; return 0; }

  if [[ -z "${body//[[:space:]]/}" ]]; then printf 'skip:empty-body'; return 0; fi # mut:empty

  # artifacts: index 0 = body, 1..n = comments in order
  local -a arts=("$body")
  for ((i = 0; i < ncom; i++)); do
    art=$(jq -r --argjson i "$i" '.comments[$i]' <<<"$envj") || { printf 'skip:unparseable'; return 0; }
    arts+=("$art")
  done
  for ((i = 0; i < ${#arts[@]}; i++)); do
    norm=$(normalize "${arts[$i]}")
    if is_plan_bearing "$norm"; then
      [[ "$first_plan_idx" -ge 0 ]] || first_plan_idx=$i
      last_plan_idx=$i
    fi
  done
  if [[ "$last_plan_idx" -lt 0 ]]; then printf 'skip:no-plan-block'; return 0; fi # mut:noplan
  sel=$last_plan_idx # mut:last-artifact
  art="${arts[$sel]}"
  norm=$(normalize "$art")

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
ERRF=""

note_skip() {  # <issue> <reason>
  SKIPPED=$((SKIPPED + 1))
  SKIP_REASONS["$2"]=$(( ${SKIP_REASONS["$2"]:-0} + 1 ))
  echo "::notice::drift-autoclose: #$1 left OPEN ($2)"
}

# read_issue <n> : prints the {body, comments[]} envelope. A non-zero rc means the read failed;
# stdout is untrusted in that case (gh can emit partial output before failing).
read_issue() {
  local raw rc=0
  raw=$(gh issue view "$1" --json body,comments 2>"$ERRF") || rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc" # mut:readguard
  jq -c '{body: (.body // ""), comments: [(.comments // [])[] | (.body // "")]}' <<<"$raw" 2>/dev/null
}

do_close() {  # <issue>
  local text rc=0
  text="Auto-closed by \`apply-deploy-pipeline-fix.yml\` after merge ${MERGE_SHA:-unknown}. This workflow applies five terraform_data targets; the newest recorded drift plan on this issue showed no pending hcloud_server replacement and was complete, so the drift is treated as re-aligned with HEAD."
  gh issue close "$1" --reason completed --comment "$text" >/dev/null 2>"$ERRF" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    CLOSE_FAILED=$((CLOSE_FAILED + 1))
    echo "::warning::drift-autoclose: closing #$1 failed (rc=$rc); the loop continues"
    return 0
  fi
  CLOSED=$((CLOSED + 1))
  echo "drift-autoclose: closed #$1"
}

process_issue() {  # <issue>
  local n="$1" envj rc=0 verdict
  CONSIDERED=$((CONSIDERED + 1))
  envj=$(read_issue "$n") || rc=$?
  if [[ "$rc" -ne 0 ]]; then note_skip "$n" gh-view-failed; return 0; fi # mut:procrc
  if [[ -z "$envj" ]]; then note_skip "$n" gh-view-failed; return 0; fi
  verdict=$(classify <<<"$envj") # mut:verdict
  if [[ "$verdict" != close ]]; then note_skip "$n" "${verdict#skip:}"; return 0; fi
  do_close "$n"
}

run_loop() {
  local list rc=0 n reason line
  ERRF=$(mktemp) || { echo "::error::drift-autoclose: mktemp failed"; return 1; }
  trap 'rm -f "${ERRF:-}"' EXIT
  list=$(gh issue list --label "infra-drift" --state open -L 200 \
    --search "infra: drift detected in web-platform in:title" \
    --json number --jq '.[].number' 2>"$ERRF") || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::drift-autoclose: could not list open infra-drift issues (rc=$rc): $(head -c 300 "$ERRF")"
    return 1
  fi
  for n in $list; do
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then note_skip "$n" non-numeric-issue-number; CONSIDERED=$((CONSIDERED + 1)); continue; fi
    process_issue "$n"
  done
  line="considered=$CONSIDERED closed=$CLOSED skipped=$SKIPPED close_failed=$CLOSE_FAILED"
  echo "drift-autoclose: $line"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Drift auto-close"
      echo "$line"
      for reason in "${!SKIP_REASONS[@]}"; do echo "- skipped ($reason): ${SKIP_REASONS[$reason]}"; done
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
  fi
  return 0
}

main() {
  case "${1:-}" in
    --classify) classify; echo; return 0 ;;
    "") run_loop ;;
    *) echo "usage: $0 [--classify]" >&2; return 2 ;;
  esac
}
main "$@"
exit $?
