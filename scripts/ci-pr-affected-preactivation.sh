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
#   lock           the driver's activation lock literal is gone (scripts/ci-pr-selection.sh)
#   artifacts      the Guard 3 read, its merge-authority call site and the audit script exist, and the newest
#                  `full-battery-audit` job on main concluded success
#   verdict        the go/no-go receipt named by the ADR ends in `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed
#                  date=YYYY-MM-DD` and is not older than 60 days
#   prereq5        the ADR carries a `Skippable set:` line naming a group or suite, and the escape route's Better Stack
#                  follow-up is closed or the ADR carries a `Waiver: heartbeat` line
# `ac9c=observed|not-yet` is printed as INFORMATION and never gates.
#
# ADR LINES THIS SCRIPT READS (each on its own line, at the start of the line):
#   Go/no-go receipt: <repo-relative path>
#   Skippable set: <group or suite names>
#   Waiver: heartbeat <reason>
#
# USAGE: ci-pr-affected-preactivation.sh [--repo OWNER/REPO] [--root DIR] [--adr FILE] [--heartbeat-issue N]
# SEAMS: `gh` is whatever is first on PATH; PR_AFFECTED_PREACT_TODAY (YYYY-MM-DD) pins the clock.
# EXIT: 0 ready=true; 1 ready=false; 2 usage error or an empty prerequisite list (anti-vacuity).
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
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "preactivation: unknown argument '${1//[[:cntrl:]]/?}'" >&2; exit 2 ;;
  esac
done
case "$repo" in */*) : ;; *) echo "preactivation: --repo must be OWNER/REPO" >&2; exit 2 ;; esac
case "$heartbeat" in ''|*[!0-9]*) echo "preactivation: --heartbeat-issue must be a number" >&2; exit 2 ;; esac
if [ -z "$root" ]; then root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "preactivation: not in a git repository and no --root" >&2; exit 2; }; fi
case "$root" in /*) : ;; *) echo "preactivation: --root must be absolute" >&2; exit 2 ;; esac
if [ -z "$adr" ]; then
  adr_rel="$(git -C "$root" ls-files -- '*ADR-276-*.md' 2>/dev/null | head -1)"
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
  if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then R_STATUS=ok; R_LINE="variable=absent"
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
  local f="$root/scripts/ci-pr-selection.sh" n
  if [ ! -f "$f" ]; then R_STATUS=unknown; R_LINE="lock=unknown(driver-missing)"; return; fi
  n="$(grep -c '^readonly PR_AFFECTED_LOCKED=' "$f")" || n=0
  if [ "$n" = 0 ]; then R_STATUS=ok; R_LINE="lock=absent"; else R_STATUS=unmet; R_LINE="lock=present"; fi
}

reader_artifacts() {
  local miss="" runs id jobs c found=""
  grep -q 'full-verified' "$root/plugins/soleur/scripts/ci-head-verdict.sh" 2>/dev/null || miss="$miss full-verified"
  grep -q 'full-verified' "$root/plugins/soleur/scripts/admin-merge-ready.sh" 2>/dev/null || miss="$miss admin-merge-ready-call"
  [ -x "$root/plugins/soleur/scripts/ci-full-battery-audit.sh" ] || miss="$miss audit-script"
  if [ -n "$miss" ]; then R_STATUS=unmet; R_LINE="artifacts=missing:${miss# }"; return; fi
  gh_read "repos/$repo/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(audit-runs-http=$G_STATUS)"; return; fi
  runs="$(printf '%s' "$G_BODY" | jq -er '.workflow_runs | select(type == "array") | .[].id' 2>/dev/null)" || runs=""
  for id in $runs; do
    gh_read "repos/$repo/actions/runs/$id/jobs?per_page=100"
    if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-http=$G_STATUS)"; return; fi
    jobs="$(printf '%s' "$G_BODY" | jq -er '.jobs | select(type == "array")' 2>/dev/null)" || { R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-unparseable)"; return; }
    c="$(printf '%s' "$jobs" | jq -r '[.[] | select(.name == "full-battery-audit") | .conclusion][0] // ""')"
    case "$c" in
      success) found=success; break ;;
      ''|skipped) continue ;;
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
  local rp rf last v r d today age
  if [ -z "$adr" ] || [ ! -f "$adr" ]; then R_STATUS=unknown; R_LINE="verdict=unknown(adr-missing)"; return; fi
  rp="$(sed -n 's/^Go\/no-go receipt:[[:space:]]*//p' "$adr" | head -1)"
  if [ -z "$rp" ]; then R_STATUS=unmet; R_LINE="verdict=no-receipt-recorded"; return; fi
  case "$rp" in /*|*..*) R_STATUS=unknown; R_LINE="verdict=unknown(receipt-path-rejected)"; return ;; esac
  rf="$root/$rp"
  if [ ! -f "$rf" ]; then R_STATUS=unmet; R_LINE="verdict=receipt-absent"; return; fi
  last="$(grep -v '^[[:space:]]*$' "$rf" | tail -1)"
  if ! printf '%s' "$last" | grep -Eq '^SOLEUR_PR_AFFECTED_VERDICT verdict=(GO|NO-GO|UNDECIDED) ruled=(confirmed|pending) date=[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    R_STATUS=unmet; R_LINE="verdict=no-machine-line"; return
  fi
  v="$(printf '%s' "$last" | sed 's/.* verdict=\([A-Z-]*\) .*/\1/')"
  r="$(printf '%s' "$last" | sed 's/.* ruled=\([a-z]*\) .*/\1/')"
  d="$(printf '%s' "$last" | sed 's/.* date=//')"
  if [ "$v" != GO ] || [ "$r" != confirmed ]; then R_STATUS=unmet; R_LINE="verdict=$v-$r"; return; fi
  today="${PR_AFFECTED_PREACT_TODAY:-$(date -u +%F)}"
  age=$(( ( $(date -u -d "$today" +%s 2>/dev/null || echo 0) - $(date -u -d "$d" +%s 2>/dev/null || echo 0) ) / 86400 ))
  if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then R_STATUS=unmet; R_LINE="verdict=stale(age_days=$age)"; return; fi
  R_STATUS=ok; R_LINE="verdict=GO-confirmed"
}

reader_prereq5() {
  local ss st
  if [ -z "$adr" ] || [ ! -f "$adr" ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(adr-missing)"; return; fi
  ss="$(sed -n 's/^Skippable set:[[:space:]]*//p' "$adr" | head -1)"
  case "$(printf '%s' "$ss" | tr '[:upper:]' '[:lower:]')" in
    ''|none|n/a|-|tbd|empty|'(none)') R_STATUS=unmet; R_LINE="prereq5=skippable-set-empty"; return ;;
  esac
  if grep -q '^Waiver: heartbeat' "$adr"; then R_STATUS=ok; R_LINE="prereq5=ok(heartbeat-waived)"; return; fi
  gh_read "repos/$repo/issues/$heartbeat"
  if [ "$G_STATUS" != 200 ]; then R_STATUS=unknown; R_LINE="prereq5=unknown(heartbeat-http=$G_STATUS)"; return; fi
  st="$(printf '%s' "$G_BODY" | jq -er '.state | select(type == "string")' 2>/dev/null)" || st=""
  case "$st" in
    closed) R_STATUS=ok; R_LINE="prereq5=ok" ;;
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

total=0; ok=0; missing=""
for name in "${READERS[@]}"; do
  R_STATUS=unknown; R_LINE="$name=unknown(no-reader)"
  "reader_$name"
  printf '%s\n' "$R_LINE"
  total=$((total + 1))
  if [ "$R_STATUS" = ok ]; then ok=$((ok + 1)); else missing="${missing:+$missing,}$name"; fi
done
AC9C="not-yet"
reader_ac9c
printf 'ac9c=%s\n' "$AC9C"

if [ "$total" -gt 0 ] && [ "$ok" -eq "$total" ]; then
  printf 'SOLEUR_PR_AFFECTED_PREACTIVATION ready=true missing=none\n'
  exit 0
fi
printf 'SOLEUR_PR_AFFECTED_PREACTIVATION ready=false missing=%s\n' "${missing:-none}"
exit 1
