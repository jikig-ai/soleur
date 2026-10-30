#!/usr/bin/env bash
# watch-code-quality-reeval-9730.sh — gather the data the GitHub Code Quality re-evaluation
# needs and post it ONCE as a comment on the tracker (#9730), on or after 2026-11-14.
# NOTIFY-ONLY: the tracker is never closed, reopened, relabelled or edited, nothing is
# enabled and no repository setting changes. The only GitHub write is one `issue comment`
# on #9730 (via wn_post in scripts/lib/watch-notify-once.sh); every other call is a read.
#
# Why a dedicated workflow and not a follow-through sweeper directive: the sweeper comments
# on every non-pass verdict with no dedup and exit 0 closes the issue (ruling F2 in
# knowledge-base/project/specs/archive/20261028-195636-feat-one-shot-autonomous-start-followthroughs/decision-challenges.md).
# No ruling is made here either: the data comment says the next `soleur:go` session has the
# CTO agent record the keep-off or turn-on ruling (F1). Run weekly by
# .github/workflows/code-quality-followups-watch.yml (RETIREMENT block in its header).
#
# Flow (shared library): earliest gate -> tracker OPEN? -> bot sentinel? -> gather -> post.
# Gather: (a) PR volume per day from 2026-09-01 through today (UTC), one aliased GraphQL
# search per day and kind, 20 days per request; any failure or partial answer is exit 3 with
# nothing posted. (b) billing for EVERY month from 2026-09 through the current month, kept to
# the `code_quality` product only; the org's whole bill is never published. The Actions token
# is expected NOT to read org billing (ruling F3): that degrades to PR volume plus the exact
# commands for the ruling session, a ::warning:: and exit 0.
#
# Modes:  (none)      measure and post once
#         --dry-run   gather and print the would-be body (sentinel as its last line); skip the
#                     earliest gate and the post; the tracker is still READ (read-only) and an info
#                     line says whether the sentinel is present; never spend a sentinel
# Env:    GH_TOKEN + GH_REPO (injected by the workflow); test seams WATCH_NOW (ISO-8601 Z) and
#         WATCH_CHUNK_PAUSE (seconds between GraphQL chunks, default 2).
#
# Exit:   0 posted, or any no-op (before the date, tracker not open or gone, already notified);
#         1 comment post failed; 2 usage; 3 cannot establish (a read the verdict depends on
#         failed; nothing posted, so the next run retries; EVERY exit 3 prints an ::error:: line
#         naming the cause); 78 refusing to run under xtrace.
# A red run is the failure signal (Actions tab + GitHub's failure email), as for the precedent
# watcher scripts/watch-registration-narrowing-9564.sh.
set -uo pipefail
export TZ=UTC

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/watch-notify-once.sh
. "$SCRIPT_DIR/lib/watch-notify-once.sh" || { echo "::error::cannot source scripts/lib/watch-notify-once.sh" >&2; exit 3; }

TRACKER=9730
EARLIEST='2026-11-14T00:00:00Z'
KEY='reeval-9730:v1'
FIRST_DAY='2026-09-01'
FIRST_YEAR=2026
FIRST_MONTH=9
CHUNK_DAYS=20

usage() { echo "usage: ${0##*/} [--dry-run]" >&2; exit 2; }
# The library sets WN_DRY_RUN=0 unconditionally; only this flag may enable dry-run.
# shellcheck disable=SC2034  # read by wn_notify_once_main in the sourced library
if [[ $# -eq 1 && "$1" == "--dry-run" ]]; then WN_DRY_RUN=1
elif [[ $# -ne 0 ]]; then usage
fi

PAUSE="${WATCH_CHUNK_PAUSE:-2}"
[[ "$PAUSE" =~ ^[0-9]+$ ]] || PAUSE=2

# --------------------------------------------------------------- PR volume --------
# pv_chunk DAY...: ONE GraphQL request, two aliased searches per day (o<i> opened, m<i>
# merged). The query hardcodes the repo and built-in keywords only; no third-party text is
# ever interpolated. Every count must be a non-negative integer and every day present.
# Every failure prints an ::error:: naming the cause (HTTP status, never the response body).
PV_DAYS=(); PV_OPENED=(); PV_MERGED=(); PV_T0=0
pv_chunk() {
  local n=$# i=0 d q resp out o m cnt=0 errf err http rc
  local -a od md
  q="query {"
  for d in "$@"; do
    q+=" o${i}: search(query: \"repo:jikig-ai/soleur is:pr created:${d}\", type: ISSUE, first: 1) { issueCount }"
    q+=" m${i}: search(query: \"repo:jikig-ai/soleur is:pr merged:${d}\", type: ISSUE, first: 1) { issueCount }"
    i=$((i + 1))
  done
  q+=" }"
  wn_errfile || { echo "::error::PR-volume search could not create a temp file" >&2; return 3; }
  errf="$WN_ERRF"
  resp="$(gh api graphql -f query="$q" 2>"$errf")"; rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [[ "$rc" -ne 0 ]]; then
    http="$(printf '%s' "$err" | grep -oE 'HTTP [0-9]{3}' | head -n 1 || true)"
    echo "::error::PR-volume search failed (${http:-network or client error})" >&2
    return 3
  fi
  out="$(printf '%s' "$resp" | jq -r --argjson n "$n" '
      (if ((.errors // null) != null) then error("graphql errors") else . end)
      | .data as $d
      | range(0; $n) as $i
      | [ ($d["o\($i)"].issueCount | if type == "number" and . == floor and . >= 0 then tostring else "x" end),
          ($d["m\($i)"].issueCount | if type == "number" and . == floor and . >= 0 then tostring else "x" end) ]
      | join(" ")' 2>/dev/null)" || { echo "::error::PR-volume search returned an unexpected response shape (or GraphQL errors)" >&2; return 3; }
  while read -r o m; do
    [[ "$o" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]] || { echo "::error::PR-volume search returned an unexpected response shape (missing or non-integer count)" >&2; return 3; }
    od+=("$o"); md+=("$m"); cnt=$((cnt + 1))
  done <<<"$out"
  [[ "$cnt" -eq "$n" ]] || { echo "::error::PR-volume search returned an unexpected response shape (${cnt} of ${n} days)" >&2; return 3; }
  PV_DAYS+=("$@"); PV_OPENED+=("${od[@]}"); PV_MERGED+=("${md[@]}")
  return 0
}

gather_pr_volume() {
  local today t0 t1 e i guard=0 pause_needed=0
  local -a all=()
  # Days come from epoch arithmetic and the bash builtin printf (TZ=UTC), not one fork per day.
  t1="$(date -u -d "$(wn_now_iso)" +%s 2>/dev/null)" || { echo "::error::cannot derive today's date" >&2; return 3; }
  t0="$(date -u -d "$FIRST_DAY" +%s 2>/dev/null)" || { echo "::error::cannot derive the first PR-volume day ($FIRST_DAY)" >&2; return 3; }
  [[ "$t0" =~ ^[1-9][0-9]*$ && "$t1" =~ ^[1-9][0-9]*$ ]] || { echo "::error::non-numeric epoch while deriving the PR-volume window" >&2; return 3; }
  PV_T0="$t0"
  printf -v today '%(%F)T' "$t1"
  for ((e = t0; e <= t1; e += 86400)); do
    printf -v i '%(%F)T' "$e"
    all+=("$i")
    guard=$((guard + 1)); [[ "$guard" -lt 4000 ]] || { echo "::error::PR-volume window loop guard tripped" >&2; return 3; }
  done
  [[ "${#all[@]}" -gt 0 && "${all[${#all[@]}-1]}" == "$today" ]] || { echo "::error::empty or inconsistent PR-volume window ($FIRST_DAY..$today)" >&2; return 3; }
  for ((i = 0; i < ${#all[@]}; i += CHUNK_DAYS)); do
    [[ "$pause_needed" -eq 1 && "$PAUSE" -gt 0 ]] && sleep "$PAUSE"
    pause_needed=1
    pv_chunk "${all[@]:i:CHUNK_DAYS}" || { echo "::error::PR-volume search failed or was partial (chunk starting ${all[i]}); posting nothing" >&2; return 3; }
  done
  [[ "${#PV_DAYS[@]}" -eq "${#all[@]}" && "${#PV_OPENED[@]}" -eq "${#all[@]}" && "${#PV_MERGED[@]}" -eq "${#all[@]}" ]] || { echo "::error::PR-volume column lengths disagree after the last chunk" >&2; return 3; }
  return 0
}

# Weekly totals (weeks start on Monday) and the collapsed per-day list.
render_pr_volume() {
  local i dow ws e tot_o=0 tot_m=0 k
  local -A wo=() wm=() wd=()
  local -a order=()
  PV_MD=""
  for ((i = 0; i < ${#PV_DAYS[@]}; i++)); do
    e=$((PV_T0 + i * 86400))
    printf -v dow '%(%u)T' "$e"; printf -v ws '%(%F)T' $((e - (dow - 1) * 86400))
    if [[ -z "${wd[$ws]:-}" ]]; then order+=("$ws"); wo[$ws]=0; wm[$ws]=0; wd[$ws]=0; fi
    wo[$ws]=$((wo[$ws] + PV_OPENED[i])); wm[$ws]=$((wm[$ws] + PV_MERGED[i])); wd[$ws]=$((wd[$ws] + 1))
    tot_o=$((tot_o + PV_OPENED[i])); tot_m=$((tot_m + PV_MERGED[i]))
  done
  PV_MD+="Pull requests in jikig-ai/soleur, ${PV_DAYS[0]} to ${PV_DAYS[${#PV_DAYS[@]}-1]} (UTC), counted by creation day (opened) and by merge day (merged). The final day is partial: it is the day of this run."$'\n\n'
  PV_MD+="Total (${#PV_DAYS[@]} days): ${tot_o} opened, ${tot_m} merged."$'\n\n'
  PV_MD+="| Week starting (Mon) | Opened | Merged | Days counted |"$'\n'"|---|---|---|---|"$'\n'
  for k in "${order[@]}"; do PV_MD+="| ${k} | ${wo[$k]} | ${wm[$k]} | ${wd[$k]} |"$'\n'; done
  PV_MD+=$'\n'"<details><summary>Per-day PR volume (${#PV_DAYS[@]} days)</summary>"$'\n\n'
  for ((i = 0; i < ${#PV_DAYS[@]}; i++)); do PV_MD+="- ${PV_DAYS[i]}: opened ${PV_OPENED[i]}, merged ${PV_MERGED[i]}"$'\n'; done
  PV_MD+=$'\n'"</details>"
}

# --------------------------------------------------------------- billing ----------
# Every month from 2026-09 through the current month. wn_billing_month keeps only the
# `code_quality` product. unreadable:<status> degrades; rc 3 (5xx, 429, rate limit, network,
# unparseable) propagates so a blip retries next Monday instead of spending the one-shot.
BILL_MD=""; BILL_UNREADABLE=0; BILL_CMDS=""; BILL_LATEST=""; BILL_STATUSES=""
gather_billing() {
  local now cy cm y=$FIRST_YEAR m=$FIRST_MONTH rc lines gross net first last tag guard=0 f
  now="$(wn_now_iso)"; cy="${now:0:4}"; cm=$((10#${now:5:2}))
  BILL_MD="| Month | code_quality lines | Gross (USD) | Net (USD) | First dated line | Last dated line |"$'\n'"|---|---|---|---|---|---|"$'\n'
  while :; do
    tag="$(printf '%04d-%02d' "$y" "$m")"
    wn_billing_month "$y" "$m"; rc=$?
    [[ "$rc" -eq 0 ]] || return "$rc"
    case "$WN_BILL_STATUS" in
      ok)
        f="$(printf '%s' "$WN_BILL_JSON" | jq -r '[.lines, ((.gross * 100 | round) / 100), ((.net * 100 | round) / 100), (.first // "-"), (.last // "-")] | map(tostring) | join(" ")' 2>/dev/null)" || { echo "::error::billing aggregate for ${tag} could not be parsed; posting nothing" >&2; return 3; }
        read -r lines gross net first last <<<"$f"
        [[ "$lines" =~ ^[0-9]+$ && "$gross" =~ ^-?[0-9]+(\.[0-9]+)?$ && "$net" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || { echo "::error::billing aggregate for ${tag} has a non-numeric count or amount; posting nothing" >&2; return 3; }
        [[ "$first" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})(T[0-9:.]+Z?)?$ || "$first" == "-" ]] || { echo "::error::billing aggregate for ${tag} has an unparseable first date; posting nothing" >&2; return 3; }
        [[ "$last" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})(T[0-9:.]+Z?)?$ || "$last" == "-" ]] || { echo "::error::billing aggregate for ${tag} has an unparseable last date; posting nothing" >&2; return 3; }
        first="${first:0:10}"; last="${last:0:10}"
        if [[ "$lines" -eq 0 ]]; then
          BILL_MD+="| ${tag} | 0 (no \`code_quality\` line) | 0 | 0 | - | - |"$'\n'
        else
          BILL_MD+="| ${tag} | ${lines} | ${gross} | ${net} | ${first} | ${last} |"$'\n'
          # Only a real date can be the latest line: "-" (no dated line) never counts.
          [[ "$last" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$BILL_LATEST" < "$last" ]] && BILL_LATEST="$last"
        fi ;;
      unreadable:*)
        BILL_UNREADABLE=1
        BILL_STATUSES+="${BILL_STATUSES:+, }${tag} HTTP ${WN_BILL_STATUS#unreadable:}"
        BILL_MD+="| ${tag} | not readable from CI (HTTP ${WN_BILL_STATUS#unreadable:}) | - | - | - | - |"$'\n'
        BILL_CMDS+="gh api 'orgs/jikig-ai/settings/billing/usage?year=${y}&month=${m}'"$'\n' ;;
      *) echo "::error::billing read for ${tag} returned an unknown status '${WN_BILL_STATUS}'; posting nothing" >&2; return 3 ;;
    esac
    [[ "$y" -eq "$cy" && "$m" -eq "$cm" ]] && break
    m=$((m + 1)); if [[ "$m" -gt 12 ]]; then m=1; y=$((y + 1)); fi
    guard=$((guard + 1)); [[ "$guard" -lt 120 ]] || { echo "::error::billing month loop guard tripped" >&2; return 3; }
  done
  return 0
}

render_billing() {
  BILL_SECTION="Only the \`code_quality\` product is read from the usage API and only its aggregates are shown; no other product, SKU, invoice or account figure is published here."$'\n\n'"${BILL_MD}"
  # A "yes" is definite as soon as ONE readable month holds a line on or after the stop day, even
  # when another month was unreadable. A "no" needs EVERY month: with one unreadable it would be a guess.
  local stop="$WN_BILLING_STOP_EXPECTED_BY"
  if [[ "$BILL_LATEST" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && ! "$BILL_LATEST" < "$stop" ]]; then
    BILL_SECTION+=$'\n'"ADR-276 expects no \`code_quality\` line dated ${stop} or later once the switch-off took effect. A \`code_quality\` line dated ${stop} or later is present: yes (latest ${BILL_LATEST})."$'\n'
  elif [[ "$BILL_UNREADABLE" -eq 0 ]]; then
    BILL_SECTION+=$'\n'"ADR-276 expects no \`code_quality\` line dated ${stop} or later once the switch-off took effect. A \`code_quality\` line dated ${stop} or later is present: no."$'\n'
  else
    BILL_SECTION+=$'\n'"ADR-276 expects no \`code_quality\` line dated ${stop} or later once the switch-off took effect. Whether such a line exists is not determinable (at least one month was unreadable)."$'\n'
  fi
  if [[ "$BILL_UNREADABLE" -eq 1 ]]; then
    BILL_SECTION+=$'\n'"Billing is not readable from CI: the default Actions token has no organization billing scope (expected, ruling F3; no billing credential is created for this tracker). The ruling session reads the unreadable months with the operator's own auth:"$'\n\n'
    BILL_SECTION+='```text'$'\n'"${BILL_CMDS}"'```'$'\n'
  fi
}

# --------------------------------------------------------------- compose ---------
gather() {
  gather_pr_volume || return 3
  gather_billing; local rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  render_pr_volume
  render_billing
  if [[ "$BILL_UNREADABLE" -eq 1 ]]; then
    echo "::warning::org billing is not readable from CI (${BILL_STATUSES}); the comment lists the commands for the ruling session" >&2
  fi
  WN_BODY="### GitHub Code Quality re-evaluation data (due on or after 2026-11-14)"$'\n\n'
  WN_BODY+="As recorded in the ADR-276 amendment of 2026-10-19, GitHub Code Quality was switched OFF on 2026-10-19 for jikig-ai/soleur (residual re-checked in the amendment of 2026-10-22). That is a fixed statement taken from the ADR; this script does not read the setting live. Nothing fires on the due date by itself; this comment is the data for the re-evaluation."$'\n\n'
  WN_BODY+="**Scope:** this comment covers the Code Quality half only: the trigger text in the body of this tracker predates the ADR-276 amendment of 2026-10-19. ADR-276's re-evaluation step (1), comparing the open Code Quality and CodeQL alerts with the 23-rule table, is NOT gathered here; the ruling session runs it."$'\n\n'
  WN_BODY+="**Re-enable criteria, as recorded in ADR-276:** re-enable only if (i) a consumer for the findings exists (a ratchet or an issue filer for the type-inference rules) and (ii) the AI-credit spend can be capped (a billing budget on the \`code_quality\` product; availability unverified). What would flip the 2026-10-22 ruling: a consumer for the type-inference rules appears, or a product incident is traced to one of these rule classes. A re-enable resumes metered billing, and whether findings history survives it is unverified; if it is re-enabled, read the sites named in the 2026-10-22 amendment first."$'\n\n'
  WN_BODY+="#### PR volume"$'\n\n'"PR volume per day is printed as usage context for the billing figures below."$'\n\n'"${PV_MD}"$'\n\n'
  WN_BODY+="#### Billing (\`code_quality\` only)"$'\n\n'"${BILL_SECTION}"$'\n'
  WN_BODY+="#### What happens next"$'\n\n'
  WN_BODY+="No ruling is made here. The next \`soleur:go\` session has the CTO agent record the keep-off or turn-on ruling from this data, and decides any successor tracker or watcher before closing the tracker. This tracker stays open and this comment is posted once."$'\n\n'
  WN_BODY+="Nothing was changed: no setting, label, state or file was touched, and Code Quality was not enabled."
  return 0
}

wn_preflight || exit 3
wn_notify_once_main "$TRACKER" "$EARLIEST" "$KEY" gather; rc=$?
exit "$rc"
