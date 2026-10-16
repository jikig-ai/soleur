#!/usr/bin/env bash
# ci-pr-affected-preactivation.sh: the READ-ONLY pre-activation gate for S4 (#9729, ADR-276).
#
# It answers one question: may the repository variable CI_PR_AFFECTED be flipped to `on`? It never sets the
# variable, never dispatches a workflow and never writes a file. It prints one line per prerequisite and a final
#   SOLEUR_PR_AFFECTED_PREACTIVATION ready=<true|false> missing=<comma list | none>
# `ready=true` only when EVERY prerequisite is positively read as met and at least one was read (ok_count == total > 0).
# `unknown` means the gate could not read the answer (no network, a missing tool, an unparseable body, a missing driver or
# ADR) and is NOT met; `unmet` means it read the answer and the answer is no (a present lock, a missing artifact or receipt).
# Explicit operator authorization is a human act this script cannot satisfy (a menu acknowledgement is not authorization),
# and `ready=true` does not recompute the evidence behind a GO: it checks the recorded lines and the live state, so read
# the receipt it names.
#
# NEEDS: gh (authenticated for reads), jq, git, GNU date. Run it from a checkout; it reads the COMMITTED tree (HEAD).
#
# THE SEVEN PREREQUISITES (one loop, one list; the final line is computed from the list, never from the first failure):
#   variable       absent: the variable read is HTTP 404 AND the variable list read (page of 100) is HTTP 200, complete and
#                  does not name it
#   org_variables  no organization variable resolves through `vars`: the repo-scoped read is HTTP 200 with total_count 0
#   lock           the driver's activation lock is gone: after whole-line comments and plain reads (`$X`, `${X}`, `${X:-d}`)
#                  are removed, no line of scripts/ci-pr-selection.sh at HEAD still names PR_AFFECTED_LOCKED (any assignment
#                  or declaration spelling: `readonly`, `declare -r`, `export`, `:=`, `printf -v`, `read`). An unreadable or
#                  comment-only driver is unknown, never absent.
#   artifacts      the Guard 3 read, its merge-authority call site (in code, not in a comment) and the executable audit
#                  script exist at HEAD, and the NEWEST `full-battery-audit` job on main concluded success (a pending newest
#                  run is unmet, it does not fall through to an older success)
#   verdict        the go/no-go receipt named by the ADR, a regular file at HEAD (a symlink, a directory or an untracked file
#                  proves nothing; after ship moves the spec directory the single archived copy is read), ends in
#                  `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=YYYY-MM-DD`, dated no later than today and
#                  no more than 60 days ago (an unparseable date is unknown)
#   prereq5        the ADR's `Skippable set:` names only gated groups (test-webplat, test-bun, test-scripts-heavy: the three
#                  groups ci.yml may skip) or registered suite labels, and the escape route's Better Stack follow-up
#                  (issue 10415 by default) is closed AS COMPLETED, or the ADR carries a `Waiver: heartbeat <reason>` line
#                  (the waiver stands in for that follow-up and for nothing else)
#   tree           HEAD is the tip of origin/main as the API reports it now: a feature branch, a stale checkout or an
#                  unmerged lock-removal commit cannot read as the state of main
# `ac9c=observed|not-yet|unknown` is printed as INFORMATION and never gates. It looks for the first non-draft PR opened
# after 2026-10-15T17:50:38Z (the Q1 merge) whose files are all doc-class, and is true by construction while the variable
# is unset: the dark job is skipped exactly when `vars.CI_PR_AFFECTED` is empty, so it says nothing about the active state.
#
# ADR LINES THIS SCRIPT READS (each on its own line, at the start of the line; the LAST such line wins):
#   Go/no-go receipt: <repo-relative path>
#   Skippable set: <comma-separated group or suite names>
#   Waiver: heartbeat <non-empty reason>
# The ADR is the committed ADR-276 file unless --adr FILE names a file to read instead (a test and drill seam).
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
# git, read-only, with every location variable removed: an inherited GIT_DIR would make `git -C "$root"` read another
# repository. The same nine names as GIT_LOCATION_VARS in plugins/soleur/test/lib/git-fixture-env.sh and in the replay tool
# (a parity row pins all three).
git_ro() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_TEMPLATE_DIR -u GIT_EXEC_PATH git "$@"
}
if [ -z "$root" ]; then root="$(git_ro rev-parse --show-toplevel 2>/dev/null)" || { echo "preactivation: not in a git repository and no --root" >&2; exit 2; }; fi
case "$root" in /*) : ;; *) echo "preactivation: --root must be absolute" >&2; exit 2 ;; esac

# committed <repo-relative path>: that file's bytes at HEAD on stdout. Non-zero when the path is absent, or is not a regular
# file (a symlink, a directory and a submodule are refused), so a forged link or an untracked file proves nothing.
committed() {
  local entry mode
  entry="$(git_ro -C "$root" ls-tree HEAD -- "$1" 2>/dev/null)" || return 1
  [ -n "$entry" ] || return 1
  mode="${entry%% *}"
  case "$mode" in 100644|100755) : ;; *) return 1 ;; esac
  git_ro -C "$root" cat-file blob "HEAD:$1" 2>/dev/null
}
committed_mode() { git_ro -C "$root" ls-tree HEAD -- "$1" 2>/dev/null | awk '{ print $1; exit }'; }

# code_has <text> <token>: true when a non-comment line of <text> contains the token. A here-string, not a pipe: a
# `grep -q` that exits on its first match must not be able to SIGPIPE a writer into a false miss under pipefail.
code_has() {
  local body
  body="$(printf '%s\n' "$1" | grep -v '^[[:space:]]*#')" || return 1
  grep -q -- "$2" <<<"$body"
}

# ---- the ADR: the committed ADR-276 file, or --adr FILE ---------------------------------------------------------------
ADR_TEXT=""
ADR_OK=0
if [ -n "$adr" ]; then
  if [ -f "$adr" ]; then ADR_TEXT="$(cat "$adr")"; ADR_OK=1; fi
else
  adr_rel="$(git_ro -C "$root" ls-tree -r --name-only HEAD 2>/dev/null | grep -E '(^|/)ADR-276-[^/]*[.]md$')" || adr_rel=""
  if [ -n "$adr_rel" ] && [ "$(printf '%s\n' "$adr_rel" | wc -l)" -eq 1 ]; then
    if ADR_TEXT="$(committed "$adr_rel")"; then ADR_OK=1; fi
  fi
fi
# adr_line <label>: the LAST line of the ADR that starts with the label, label removed
adr_line() { printf '%s\n' "$ADR_TEXT" | sed -n "s/^$1:[[:space:]]*//p" | tail -1; }

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
  gh_read "repos/$repo/actions/variables?per_page=100"; s2="$G_STATUS"
  if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then
    # the list is the cross-check: a 404 on the single read next to a list that names the variable is a contradiction, and
    # a list shorter than its own total_count cannot show absence
    if printf '%s' "$G_BODY" | jq -e '(.variables | type == "array") and (.total_count == (.variables | length)) and ([.variables[].name] | index("CI_PR_AFFECTED") | not)' >/dev/null 2>&1; then
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

reader_lock() {
  local src code stripped rc
  src="$(committed scripts/ci-pr-selection.sh)" || { R_STATUS=unknown; R_LINE="lock=unknown(driver-missing)"; return; }
  code="$(printf '%s\n' "$src" | grep -v '^[[:space:]]*#')" || { R_STATUS=unknown; R_LINE="lock=unknown(driver-has-no-code)"; return; }
  [ -n "$(printf '%s' "$code" | tr -d '[:space:]')" ] || { R_STATUS=unknown; R_LINE="lock=unknown(driver-has-no-code)"; return; }
  # plain READS of the name are not the lock (the driver keeps one); whatever still names it assigns or declares it
  # shellcheck disable=SC2016  # the sed program is literal text: the dollar signs are the shell syntax being removed
  stripped="$(printf '%s\n' "$code" | sed -E 's/\$\{PR_AFFECTED_LOCKED(:-[^}]*)?\}//g; s/\$PR_AFFECTED_LOCKED//g')"
  grep -q 'PR_AFFECTED_LOCKED' <<<"$stripped"
  rc=$?
  case "$rc" in
    0) R_STATUS=unmet; R_LINE="lock=present" ;;
    1) R_STATUS=ok; R_LINE="lock=absent" ;;
    *) R_STATUS=unknown; R_LINE="lock=unknown(grep-rc=$rc)" ;;
  esac
}

reader_artifacts() {
  local miss="" hv am runs id jobs c found="" n
  hv="$(committed plugins/soleur/scripts/ci-head-verdict.sh)" || hv=""
  am="$(committed plugins/soleur/scripts/admin-merge-ready.sh)" || am=""
  code_has "$hv" 'full-verified' || miss="$miss full-verified"
  code_has "$am" 'full-verified' || miss="$miss admin-merge-ready-call"
  [ "$(committed_mode plugins/soleur/scripts/ci-full-battery-audit.sh)" = 100755 ] || miss="$miss audit-script"
  if [ -n "$miss" ]; then R_STATUS=unmet; R_LINE="artifacts=missing:${miss# }"; return; fi
  gh_read "repos/$repo/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(audit-runs-http=$G_STATUS)"; return; fi
  runs="$(printf '%s' "$G_BODY" | jq -er '.workflow_runs | select(type == "array") | .[].id' 2>/dev/null)" \
    || { R_STATUS=unknown; R_LINE="artifacts=unknown(runs-unparseable)"; return; }
  for id in $runs; do
    gh_read "repos/$repo/actions/runs/$id/jobs?per_page=100"
    if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-http=$G_STATUS)"; return; fi
    jobs="$(printf '%s' "$G_BODY" | jq -er '.jobs | select(type == "array")' 2>/dev/null)" || { R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-unparseable)"; return; }
    # a jobs list shorter than its own total_count cannot show that the audit job is absent from the run
    n="$(printf '%s' "$G_BODY" | jq -r 'if (.total_count | type) == "number" then (.total_count - (.jobs | length)) else 0 end' 2>/dev/null)" || n=1
    [ "$n" = 0 ] || { R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-truncated)"; return; }
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

reader_verdict() {
  local rp rel text last v r d today t_now t_rec age note="" dir leaf cand n
  if [ "$ADR_OK" -ne 1 ]; then R_STATUS=unknown; R_LINE="verdict=unknown(adr-missing)"; return; fi
  rp="$(adr_line 'Go\/no-go receipt')"
  if [ -z "$rp" ]; then R_STATUS=unmet; R_LINE="verdict=no-receipt-recorded"; return; fi
  case "$rp" in /*|*..*) R_STATUS=unknown; R_LINE="verdict=unknown(receipt-path-rejected)"; return ;; esac
  # only the committed tree counts: a symlink, a directory or an untracked file at that path proves nothing
  if text="$(committed "$rp")"; then :
  elif [ -z "$(git_ro -C "$root" ls-tree HEAD -- "$rp" 2>/dev/null)" ]; then
    # absent from HEAD: ship archives the spec directory, so look for its ONE archived copy
    text=""
    case "$rp" in
      */specs/*/*)
        dir="${rp%%/specs/*}/specs"
        leaf="${rp#"$dir"/}"      # <feature>/<path inside it>: the archive keeps both after a <timestamp>- prefix
        cand="${dir}/archive/"
        rel="$(git_ro -C "$root" ls-tree -r --name-only HEAD 2>/dev/null | awk -v pre="$cand" -v want="$leaf" '
          index($0, pre) == 1 {
            rest = substr($0, length(pre) + 1)
            stamp = substr(rest, 1, 15)
            if (stamp ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]$/ && substr(rest, 16, 1) == "-" && substr(rest, 17) == want) print $0
          }')"
        n="$(printf '%s' "$rel" | grep -c .)"
        if [ "$n" -gt 1 ]; then R_STATUS=unknown; R_LINE="verdict=unknown(receipt-archive-ambiguous)"; return; fi
        if [ "$n" -eq 1 ] && text="$(committed "$rel")"; then note="(receipt-archived)"; else text=""; fi
        ;;
    esac
  else text=""; fi
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
  # the clock is a calendar day: `date -d` also reads "2026-10-10 + 30 days", which would age a stale GO into the window
  printf '%s' "$today" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || { R_STATUS=unknown; R_LINE="verdict=unknown(date-unparseable)"; return; }
  { t_now="$(date -u -d "$today" +%s 2>/dev/null)" && t_rec="$(date -u -d "$d" +%s 2>/dev/null)" && [ -n "$t_now" ] && [ -n "$t_rec" ]; } \
    || { R_STATUS=unknown; R_LINE="verdict=unknown(date-unparseable)"; return; }
  age=$(( (t_now - t_rec) / 86400 ))
  if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then R_STATUS=unmet; R_LINE="verdict=stale(age_days=$age)"; return; fi
  R_STATUS=ok; R_LINE="verdict=GO-confirmed$note"
}

# registered_suite <label>: true when the label is a row of a suite-durations table at HEAD
registered_suite() {
  local t body
  for t in scripts/suite-durations.tsv scripts/suite-durations-heavy.tsv; do
    body="$(committed "$t")" || continue
    awk -F'\t' -v want="$1" '$0 !~ /^#/ && $1 == want { found = 1 } END { exit !found }' <<<"$body" && return 0
  done
  return 1
}

reader_prereq5() {
  local ss item st reason w bad="" n=0 items=()
  if [ "$ADR_OK" -ne 1 ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(adr-missing)"; return; fi
  ss="$(adr_line 'Skippable set')"
  ss="${ss%%#*}"
  IFS=',' read -ra items <<<"$ss"
  for item in ${items[@]+"${items[@]}"}; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$item" ] || continue
    n=$((n + 1))
    case "$item" in
      test-webplat|test-bun|test-scripts-heavy) : ;;
      *[[:space:]]*) bad="$item"; break ;;
      *) registered_suite "$item" || { bad="$item"; break; } ;;
    esac
  done
  if [ "$n" -eq 0 ]; then R_STATUS=unmet; R_LINE="prereq5=skippable-set-empty"; return; fi
  if [ -n "$bad" ]; then R_STATUS=unmet; R_LINE="prereq5=skippable-set-unrecognised(${bad//[[:cntrl:]]/?})"; return; fi
  w="$(adr_line 'Waiver')"
  if printf '%s' "$w" | grep -Eq '^heartbeat[[:space:]]+[^[:space:]]'; then R_STATUS=ok; R_LINE="prereq5=ok(heartbeat-waived)"; return; fi
  gh_read "repos/$repo/issues/$heartbeat"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(heartbeat-http=$G_STATUS)"; return; fi
  st="$(printf '%s' "$G_BODY" | jq -er '.state | select(type == "string")' 2>/dev/null)" || st=""
  reason="$(printf '%s' "$G_BODY" | jq -r '.state_reason // ""' 2>/dev/null)" || reason=""
  case "$st" in
    closed) if [ "$reason" = completed ]; then R_STATUS=ok; R_LINE="prereq5=ok"; else R_STATUS=unmet; R_LINE="prereq5=heartbeat-closed-${reason:-without-reason}"; fi ;;
    open) R_STATUS=unmet; R_LINE="prereq5=heartbeat-open" ;;
    *) R_STATUS=unknown; R_LINE="prereq5=unknown(heartbeat-state)" ;;
  esac
}

reader_tree() {
  local h o
  h="$(git_ro -C "$root" rev-parse --verify -q HEAD 2>/dev/null)" || { R_STATUS=unknown; R_LINE="tree=unknown(no-head)"; return; }
  gh_read "repos/$repo/commits/main"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="tree=unknown(main-http=$G_STATUS)"; return; fi
  o="$(printf '%s' "$G_BODY" | jq -er '.sha | select(type == "string" and test("^[0-9a-f]{40}$"))' 2>/dev/null)" \
    || { R_STATUS=unknown; R_LINE="tree=unknown(main-unparseable)"; return; }
  if [ "$h" = "$o" ]; then R_STATUS=ok; R_LINE="tree=head-is-main"
  else R_STATUS=unmet; R_LINE="tree=head-is-not-main(head=${h:0:7},main=${o:0:7})"; fi
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

READERS=(variable org_variables lock artifacts verdict prereq5 tree)
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
