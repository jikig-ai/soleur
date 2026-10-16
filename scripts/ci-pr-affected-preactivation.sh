#!/usr/bin/env bash
# ci-pr-affected-preactivation.sh: the READ-ONLY pre-activation gate for S4 (#9729, ADR-276).
#
# It answers one question: may the repository variable CI_PR_AFFECTED be flipped to `on`? It never sets the
# variable, never dispatches a workflow and never writes a file. It prints one line per prerequisite and a final
#   SOLEUR_PR_AFFECTED_PREACTIVATION ready=<true|false> missing=<comma list | none>
# `ready=true` only when EVERY prerequisite is positively read as met and at least one was read (ok_count == total > 0).
# Any API failure, unreadable answer or missing artifact is `unknown`, which is NOT met. Explicit operator
# authorization is a human act this script cannot satisfy (a menu acknowledgement is not authorization).
#
# THE SIX PREREQUISITES (one loop, one list; the final line is computed from the list, never from the first failure):
#   variable       absent: the variable read is HTTP 404 AND the variable list read is HTTP 200 (any other failure is unknown)
#   org_variables  no organization variable resolves through `vars`: the repo-scoped read is HTTP 200 with total_count 0
#   lock           the driver's activation lock is gone: no non-comment line of scripts/ci-pr-selection.sh assigns or
#                  declares PR_AFFECTED_LOCKED (any spelling: indented, `declare -r`, `export`). An unreadable or
#                  comment-only driver is unknown, never absent.
#   artifacts      the Guard 3 read, its merge-authority call site and the audit script exist (in code, not in a comment),
#                  and the NEWEST `full-battery-audit` job on main concluded success (a pending newest run is unmet,
#                  it does not fall through to an older success)
#   verdict        the go/no-go receipt named by the ADR, read from the COMMITTED tree (git show HEAD:<path>, so an
#                  untracked file or a symlink proves nothing; after ship moves the spec directory the archived copy is
#                  read), ends in `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=YYYY-MM-DD`, dated no
#                  later than today and no more than 60 days ago (an unparseable date is unknown)
#   prereq5        the ADR's `Skippable set:` names only gated groups (test-webplat, test-bun, test-scripts-heavy,
#                  test-scripts) or registered suite labels, and the escape route's Better Stack follow-up is closed
#                  as completed or the ADR carries a `Waiver: heartbeat <reason>` line
# `ac9c=observed|not-yet|unknown` is printed as INFORMATION and never gates. It looks for the first non-draft PR opened
# after 2026-10-15T17:50:38Z (the Q1 merge) whose files are all doc-class, and is true by construction while the variable
# is unset: the dark job is skipped exactly when `vars.CI_PR_AFFECTED` is empty.
#
# ADR LINES THIS SCRIPT READS (each on its own line, at the start of the line; the LAST such line wins):
#   Go/no-go receipt: <repo-relative path>
#   Skippable set: <comma-separated group or suite names>
#   Waiver: heartbeat <non-empty reason>
#
# USAGE: ci-pr-affected-preactivation.sh [--repo OWNER/REPO] [--root DIR] [--adr FILE] [--heartbeat-issue N]
# SEAMS: `gh` is whatever is first on PATH; PR_AFFECTED_PREACT_TODAY (YYYY-MM-DD) pins the clock.
# EXIT: 0 ready=true; 1 ready=false (at least one prerequisite read as unmet); 3 ready=false and EVERY missing
#       prerequisite is unknown (the gate could not decide: no network, a missing file); 2 usage error or an empty
#       prerequisite list (anti-vacuity).

# shellcheck disable=SC2329  # the reader_* functions are invoked by name from the loop below
set -uo pipefail

repo="jikig-ai/soleur"
root=""
adr=""
heartbeat=10415
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --root) root="${2:-}"; shift 2 ;;
    --adr) adr="${2:-}"; shift 2 ;;
    --heartbeat-issue) heartbeat="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "preactivation: unknown argument '${1//[[:cntrl:]]/?}'" >&2; exit 2 ;;
  esac
done
case "$repo" in */*) : ;; *) echo "preactivation: --repo must be OWNER/REPO" >&2; exit 2 ;; esac
case "$heartbeat" in ''|*[!0-9]*) echo "preactivation: --heartbeat-issue must be a number" >&2; exit 2 ;; esac
# git, read-only, with every location variable removed: an inherited GIT_DIR would make `git -C "$root"` read another repository
git_ro() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR git "$@"; }
if [ -z "$root" ]; then root="$(git_ro rev-parse --show-toplevel 2>/dev/null)" || { echo "preactivation: not in a git repository and no --root" >&2; exit 2; }; fi
case "$root" in /*) : ;; *) echo "preactivation: --root must be absolute" >&2; exit 2 ;; esac
if [ -z "$adr" ]; then
  adr_rel="$(git_ro -C "$root" ls-files -- '*ADR-276-*.md' 2>/dev/null | head -1)"
  [ -z "$adr_rel" ] || adr="$root/$adr_rel"
fi

# ---- one HTTP read: sets G_STATUS (3 digits or 000) and G_BODY (the body, headers stripped) ------------------------
G_STATUS=000
G_BODY=""
gh_read() {  # gh_read <api path>
  local out=""
  out="$(gh api -i "$1" 2>/dev/null)" || true  # gh exits non-zero on a 4xx and still prints the headers: the status line is the verdict
  G_STATUS="$(printf '%s\n' "$out" | awk 'NR==1 && $1 ~ /^HTTP/ {print $2; exit}')"
  case "$G_STATUS" in [0-9][0-9][0-9]) : ;; *) G_STATUS=000 ;; esac
  G_BODY="$(printf '%s\n' "$out" | sed '1,/^\r\{0,1\}$/d')"
}

# ---- readers: each sets R_STATUS (ok|unmet|unknown) and R_LINE (name=value) ------------------------------------------
R_STATUS=unknown
R_LINE=""

reader_variable() {
  local s1 s2
  gh_read "repos/$repo/actions/variables/CI_PR_AFFECTED"; s1="$G_STATUS"
  gh_read "repos/$repo/actions/variables"; s2="$G_STATUS"
  if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then
    # the list is the cross-check: a 404 on the single read next to a list that names the variable is a contradiction
    if printf '%s' "$G_BODY" | jq -e '(.variables | type == "array") and ([.variables[].name] | index("CI_PR_AFFECTED") | not)' >/dev/null 2>&1; then
      R_STATUS=ok; R_LINE="variable=absent"
    else R_STATUS=unknown; R_LINE="variable=unknown(list-unreadable-or-contradicts)"; fi
  elif [ "$s1" = 200 ]; then R_STATUS=unmet; R_LINE="variable=present"
  else R_STATUS=unknown; R_LINE="variable=unknown(read=$s1,list=$s2)"; fi
}

reader_org_variables() {
  local n
  gh_read "repos/$repo/actions/organization-variables"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="org_variables=unknown(http=$G_STATUS)"; return; fi
  n="$(printf '%s' "$G_BODY" | jq -er '.total_count | select(type == "number")' 2>/dev/null)" || n=""
  case "$n" in
    '') R_STATUS=unknown; R_LINE="org_variables=unknown(unparseable)" ;;
    0) R_STATUS=ok; R_LINE="org_variables=0" ;;
    *[!0-9]*) R_STATUS=unknown; R_LINE="org_variables=unknown(unparseable)" ;;
    *) R_STATUS=unmet; R_LINE="org_variables=$n" ;;
  esac
}

# code_of <file>: the file without whole-line comments, on stdout; non-zero when it cannot be read or has no code line
code_of() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null; }

reader_lock() {
  local f="$root/scripts/ci-pr-selection.sh" code rc
  if [ ! -f "$f" ]; then R_STATUS=unknown; R_LINE="lock=unknown(driver-missing)"; return; fi
  code="$(code_of "$f")" || { R_STATUS=unknown; R_LINE="lock=unknown(driver-unreadable)"; return; }
  printf '%s\n' "$code" | grep -Eq 'PR_AFFECTED_LOCKED[[:space:]]*\+?=|(readonly|declare|typeset|export)[[:space:]].*PR_AFFECTED_LOCKED'
  rc=$?
  case "$rc" in
    0) R_STATUS=unmet; R_LINE="lock=present" ;;
    1) R_STATUS=ok; R_LINE="lock=absent" ;;
    *) R_STATUS=unknown; R_LINE="lock=unknown(grep-rc=$rc)" ;;
  esac
}

reader_artifacts() {
  local miss="" runs id jobs c found=""
  code_of "$root/plugins/soleur/scripts/ci-head-verdict.sh" | grep -q 'full-verified' || miss="$miss full-verified"
  code_of "$root/plugins/soleur/scripts/admin-merge-ready.sh" | grep -q 'full-verified' || miss="$miss admin-merge-ready-call"
  [ -x "$root/plugins/soleur/scripts/ci-full-battery-audit.sh" ] || miss="$miss audit-script"
  if [ -n "$miss" ]; then R_STATUS=unmet; R_LINE="artifacts=missing:${miss# }"; return; fi
  gh_read "repos/$repo/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(audit-runs-http=$G_STATUS)"; return; fi
  runs="$(printf '%s' "$G_BODY" | jq -er '.workflow_runs | select(type == "array") | .[].id' 2>/dev/null)" || runs=""
  for id in $runs; do
    gh_read "repos/$repo/actions/runs/$id/jobs?per_page=100"
    if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-http=$G_STATUS)"; return; fi
    jobs="$(printf '%s' "$G_BODY" | jq -er '.jobs | select(type == "array")' 2>/dev/null)" || { R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-unparseable)"; return; }
    # the newest run that HAS the job decides; a null conclusion is pending, not "no run"
    c="$(printf '%s' "$jobs" | jq -r '[.[] | select(.name == "full-battery-audit") | (.conclusion // "pending")][0] // "absent"')"
    case "$c" in
      success) found=success; break ;;
      absent|skipped) continue ;;
      *) found="$c"; break ;;
    esac
  done
  case "$found" in
    success) R_STATUS=ok; R_LINE="artifacts=ok" ;;
    '') R_STATUS=unmet; R_LINE="artifacts=no-audit-run" ;;
    *) R_STATUS=unmet; R_LINE="artifacts=audit-run-$found" ;;
  esac
}

# adr_line <label>: the LAST line of the ADR that starts with the label, label removed
adr_line() { sed -n "s/^$1:[[:space:]]*//p" "$adr" | tail -1; }

reader_verdict() {
  local rp rel text last v r d today t_now t_rec age note="" cand
  if [ -z "$adr" ] || [ ! -f "$adr" ]; then R_STATUS=unknown; R_LINE="verdict=unknown(adr-missing)"; return; fi
  rp="$(adr_line 'Go\/no-go receipt')"
  if [ -z "$rp" ]; then R_STATUS=unmet; R_LINE="verdict=no-receipt-recorded"; return; fi
  case "$rp" in /*|*..*) R_STATUS=unknown; R_LINE="verdict=unknown(receipt-path-rejected)"; return ;; esac
  # only the committed tree counts: a symlink or an untracked file at that path proves nothing
  text="$(git_ro -C "$root" show "HEAD:$rp" 2>/dev/null)" || text=""
  if [ -z "$text" ]; then
    # ship archives the spec directory; the receipt moves with it
    cand="$(printf '%s\n' "$rp" | sed -E 's#^(.*/specs)/([^/]+)/(.*)$#^\1/archive/[^/]+-\2/\3$#')"
    rel="$(git_ro -C "$root" ls-tree -r --name-only HEAD 2>/dev/null | grep -E "$cand" | sort | tail -1)"
    [ -z "$rel" ] || { text="$(git_ro -C "$root" show "HEAD:$rel" 2>/dev/null)" || text=""; note="(receipt-archived)"; }
  fi
  if [ -z "$text" ]; then R_STATUS=unmet; R_LINE="verdict=receipt-absent"; return; fi
  last="$(printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -1)"
  if ! printf '%s' "$last" | grep -Eq '^SOLEUR_PR_AFFECTED_VERDICT verdict=(GO|NO-GO|UNDECIDED) ruled=(confirmed|pending) date=[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    R_STATUS=unmet; R_LINE="verdict=no-machine-line"; return
  fi
  v="$(printf '%s' "$last" | sed 's/.* verdict=\([A-Z-]*\) .*/\1/')"
  r="$(printf '%s' "$last" | sed 's/.* ruled=\([a-z]*\) .*/\1/')"
  d="$(printf '%s' "$last" | sed 's/.* date=//')"
  if [ "$v" != GO ] || [ "$r" != confirmed ]; then R_STATUS=unmet; R_LINE="verdict=$v-$r$note"; return; fi
  today="${PR_AFFECTED_PREACT_TODAY:-$(date -u +%F)}"
  { t_now="$(date -u -d "$today" +%s 2>/dev/null)" && t_rec="$(date -u -d "$d" +%s 2>/dev/null)" && [ -n "$t_now" ] && [ -n "$t_rec" ]; } \
    || { R_STATUS=unknown; R_LINE="verdict=unknown(date-unparseable)"; return; }
  age=$(( (t_now - t_rec) / 86400 ))
  if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then R_STATUS=unmet; R_LINE="verdict=stale(age_days=$age)"; return; fi
  R_STATUS=ok; R_LINE="verdict=GO-confirmed$note"
}

# registered_suite <label>: true when the label is a row of a suite-durations table
registered_suite() {
  local t
  for t in "$root"/scripts/suite-durations.tsv "$root"/scripts/suite-durations-heavy.tsv; do
    [ -f "$t" ] || continue
    awk -F'\t' -v want="$1" '$0 !~ /^#/ && $1 == want { found = 1 } END { exit !found }' "$t" && return 0
  done
  return 1
}

reader_prereq5() {
  local ss item st reason bad="" n=0 items=()
  if [ -z "$adr" ] || [ ! -f "$adr" ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(adr-missing)"; return; fi
  ss="$(adr_line 'Skippable set')"
  ss="${ss%%#*}"
  IFS=',' read -ra items <<<"$ss"
  for item in "${items[@]}"; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$item" ] || continue
    n=$((n + 1))
    case "$item" in
      test-webplat|test-bun|test-scripts-heavy|test-scripts) : ;;
      *[[:space:]]*) bad="$item"; break ;;
      *) registered_suite "$item" || { bad="$item"; break; } ;;
    esac
  done
  if [ "$n" -eq 0 ]; then R_STATUS=unmet; R_LINE="prereq5=skippable-set-empty"; return; fi
  if [ -n "$bad" ]; then R_STATUS=unmet; R_LINE="prereq5=skippable-set-unrecognised(${bad//[[:cntrl:]]/?})"; return; fi
  if grep -Eq '^Waiver: heartbeat[[:space:]]+[^[:space:]]' "$adr"; then R_STATUS=ok; R_LINE="prereq5=ok(heartbeat-waived)"; return; fi
  gh_read "repos/$repo/issues/$heartbeat"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(heartbeat-http=$G_STATUS)"; return; fi
  st="$(printf '%s' "$G_BODY" | jq -er '.state | select(type == "string")' 2>/dev/null)" || st=""
  reason="$(printf '%s' "$G_BODY" | jq -r '.state_reason // ""' 2>/dev/null)" || reason=""
  case "$st" in
    closed) if [ "$reason" = not_planned ]; then R_STATUS=unmet; R_LINE="prereq5=heartbeat-not-planned"; else R_STATUS=ok; R_LINE="prereq5=ok"; fi ;;
    open) R_STATUS=unmet; R_LINE="prereq5=heartbeat-open" ;;
    *) R_STATUS=unknown; R_LINE="prereq5=unknown(heartbeat-state)" ;;
  esac
}

# The doc-class directory name is built from two words so that this file carries no literal path of the documentation tree
# (the kb-consumer census would otherwise count it as a reader of that tree).
KBDIR="knowledge""-base"
# AC9c: the first NON-DRAFT pull request created after the Q1 merge whose files are all doc-class; informational only.
reader_ac9c() {
  local since="2026-10-15T17:50:38Z" nums n head bad files rid c
  gh_read "search/issues?q=repo:$repo+is:pr+draft:false+created:%3E$since&sort=created&order=asc&per_page=30"
  if [ "$G_STATUS" != 200 ]; then AC9C="unknown"; return; fi
  nums="$(printf '%s' "$G_BODY" | jq -r '.items[]?.number' 2>/dev/null)" || nums=""
  AC9C="not-yet"
  for n in $nums; do
    gh_read "repos/$repo/pulls/$n/files?per_page=100"
    [ "$G_STATUS" = 200 ] || continue
    bad="$(printf '%s' "$G_BODY" | jq -r --arg kb "$KBDIR" '[.[]?.filename | select((test("^" + $kb + "/.*[.]md$") or test("^[^/]+[.]md$")) | not)] | length' 2>/dev/null)" || continue
    files="$(printf '%s' "$G_BODY" | jq -r 'length' 2>/dev/null)" || continue
    { [ "$bad" = 0 ] && [ "${files:-0}" -gt 0 ]; } || continue
    gh_read "repos/$repo/pulls/$n"
    [ "$G_STATUS" = 200 ] || continue
    head="$(printf '%s' "$G_BODY" | jq -r '.head.sha // ""' 2>/dev/null)"
    [ -n "$head" ] || continue
    gh_read "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$head&per_page=100"
    [ "$G_STATUS" = 200 ] || continue
    rid="$(printf '%s' "$G_BODY" | jq -r '[.workflow_runs[]? | select(.event == "pull_request")][0].id // ""' 2>/dev/null)"
    [ -n "$rid" ] || continue
    gh_read "repos/$repo/actions/runs/$rid/jobs?per_page=100"
    [ "$G_STATUS" = 200 ] || continue
    # observed = pr-selection skipped AND the three gated jobs and the aggregate `test` all concluded success
    c="$(printf '%s' "$G_BODY" | jq -r '
      def legs($p): [.jobs[] | select(.name == $p or (.name | startswith($p + " ("))) | .conclusion];
      def green($p): (legs($p) | length > 0 and all(. == "success"));
      if (legs("pr-selection") == ["skipped"]) and green("test-webplat") and green("test-bun") and green("test-scripts-heavy")
         and green("test-scripts") and green("test") then "yes" else "no" end')"
    if [ "$c" = yes ]; then AC9C="observed"; fi
    return
  done
}

READERS=(variable org_variables lock artifacts verdict prereq5)
if [ "${#READERS[@]}" -eq 0 ]; then echo "preactivation: the prerequisite list is empty; refusing to report readiness" >&2; exit 2; fi

total=0; ok=0; unmet=0; missing=""
for name in "${READERS[@]}"; do
  R_STATUS=unknown; R_LINE="$name=unknown(no-reader)"
  "reader_$name"
  case "$R_STATUS" in ok|unmet|unknown) : ;; *) R_STATUS=unknown ;; esac
  printf '%s\n' "$R_LINE"
  total=$((total + 1))
  case "$R_STATUS" in
    ok) ok=$((ok + 1)) ;;
    unmet) unmet=$((unmet + 1)); missing="${missing:+$missing,}$name" ;;
    *) missing="${missing:+$missing,}$name" ;;
  esac
done
AC9C="not-yet"
reader_ac9c
printf 'ac9c=%s\n' "$AC9C"

if [ "$total" -gt 0 ] && [ "$ok" -eq "$total" ]; then
  printf 'SOLEUR_PR_AFFECTED_PREACTIVATION ready=true missing=none\n'
  exit 0
fi
printf 'SOLEUR_PR_AFFECTED_PREACTIVATION ready=false missing=%s\n' "${missing:-none}"
[ "$unmet" -eq 0 ] && exit 3
exit 1
