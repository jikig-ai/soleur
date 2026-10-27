#!/usr/bin/env bash
# watch-lint-ratchet-reeval-10515.sh — on or after 2027-01-18, gather the data the
# lint-ratchet user-mode deferral re-evaluation (#10515) needs and post it ONCE as a
# comment on that tracker. NOTIFY-ONLY: the tracker is never closed, reopened,
# relabelled or edited; the only GitHub write is one `issue comment` (via wn_post in
# scripts/lib/watch-notify-once.sh); every other gh call is a read (`issue view`,
# GET-shaped `api`). Nothing here changes a repository setting.
#
# No ruling is made here. The comment says so: the next `soleur:go` session has the CTO
# agent apply the flip condition to this data (decision-challenges.md F1).
#
# Data window: 2026-10-19 (the merge of PR #10514) to now. Hits are LEADS, not verdicts.
# The keywords below are hardcoded from the 2026-10-22 triage comment on #10515 (the six
# deferred items, item 4 split into Windows and notebooks, and the sharpened trigger for
# item 3); every query hardcodes `repo:jikig-ai/soleur` and built-in keywords only, so no
# third-party text ever reaches a query. Third-party strings (titles, logins, commit
# subjects) are rendered only through wn_sanitize, as inert code spans; bodies are never
# pasted.
#
# Order (the shared flow in wn_notify_once_main): xtrace refusal -> earliest gate ->
# tracker OPEN? -> bot sentinel present? -> gather -> post. Sentinel:
# <!-- code-quality-followups-watch:reeval-10515:v1 -->, always the exact last line.
#
# SELF-DISABLE: once the tracker is not OPEN every run is a cheap no-op.
#
# Modes:
#   (default)   post the data comment once (on or after the date)
#   --dry-run   gather and print the would-be comment; skips the date gate, the tracker
#               read and the sentinel read; never posts and never spends the sentinel
# Env: GH_TOKEN (injected by the workflow); WATCH_NOW (test seam, ISO-8601 Z);
#      WATCH_REPO_ROOT (test seam: the checkout whose git history, ledger and ADR are read).
#
# Exit: 0 posted / dry-run / any no-op (before the date, tracker not open, gone or already
#         notified); 1 comment post failed; 2 usage; 3 cannot establish (a search, the
#         tracker read, a billing read that is not a plain "unreadable" or git failed;
#         nothing posted, so the next run retries); 78 refusing to run under xtrace.
# A red run is the only failure signal (Actions tab + GitHub's failure email).
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

TRACKER=10515
EARLIEST='2027-01-18T00:00:00Z'
KEY='reeval-10515:v1'
WINDOW_START='2026-10-19'
# The tracker itself and the code-quality epic (#10331) are never listed as hits.
EXCLUDE_JSON='[10515,10331]'
LEDGER_REL='knowledge-base/operations/expenses.md'
ADR_DIR_REL='knowledge-base/engineering/architecture/decisions'
LINT_RATCHET_REL='plugins/soleur/scripts/lint-ratchet.py'
HIT_CAP=20

usage() { echo "usage: ${0##*/} [--dry-run]" >&2; exit 2; }
DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1; [[ $# -eq 1 ]] || usage ;;
  *) usage ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${WATCH_REPO_ROOT:-$(cd "$HERE/.." && pwd)}"
if [[ ! -r "$HERE/lib/watch-notify-once.sh" ]]; then
  echo "::error::shared library scripts/lib/watch-notify-once.sh is missing; cannot run" >&2
  exit 3
fi
# shellcheck source=lib/watch-notify-once.sh
. "$HERE/lib/watch-notify-once.sh"
WN_DRY_RUN="$DRY"

BODY_ACC=""
add() { BODY_ACC+="$1"$'\n'; }

# ------------------------------------------------------------------- searches ----
# Percent-encode in pure bash (no fork): everything outside the RFC 3986 unreserved set.
URLENC=""
urlenc() {
  local in="$1" out="" c i h
  for (( i = 0; i < ${#in}; i++ )); do
    c="${in:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) out+="$c" ;;
      *) printf -v h '%%%02X' "'$c"; out+="$h" ;;
    esac
  done
  URLENC="$out"
}

# run_search TERMS -> SEARCH_JSON (the hits minus the excluded numbers). rc 3 on any failure.
SEARCH_JSON=""
run_search() {
  local q enc raw
  q="repo:jikig-ai/soleur created:>=${WINDOW_START} $1"
  urlenc "$q"; enc="$URLENC"
  [[ -n "$enc" ]] || return 3
  raw="$(gh api "search/issues?q=${enc}&per_page=30&sort=created&order=desc" 2>/dev/null)" || return 3
  SEARCH_JSON="$(printf '%s' "$raw" | jq -c --argjson ex "$EXCLUDE_JSON" '
      if (.items | type) == "array" then
        [.items[] | select((.number | type) == "number")
                  | select(.number as $n | ($ex | index($n)) | not)]
      else error("no items array") end' 2>/dev/null)" || return 3
  [[ -n "$SEARCH_JSON" ]] || return 3
  return 0
}

# render_search HEADING TERMS [NOTE]: one `####` section; rc 3 when the search fails.
render_search() {
  local heading="$1" terms="$2" note="${3:-}" n shown rec num state date login assoc typ kind title ext
  local login_s assoc_s title_s
  if ! run_search "$terms"; then
    echo "::error::search '${terms}' failed; posting nothing (the next run retries)" >&2
    return 3
  fi
  # ONE jq call: the first line is the hit count, then one record per shown hit.
  mapfile -t RECS < <(printf '%s' "$SEARCH_JSON" | jq -r --argjson cap "$HIT_CAP" '
      length,
      (.[:$cap][] | [(.number | tostring), (.state // ""), ((.created_at // "")[:10]),
                     (.user.login // ""), (.author_association // ""), (.user.type // ""),
                     (if .pull_request then "pull request" else "issue" end), (.title // "")]
                  | map(tostring | gsub("[\\x00-\\x1f\\x7f]"; "")) | join("\u001f"))')
  n="${RECS[0]:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 3
  add "#### ${heading}"
  add ""
  add "Search: \`${terms}\` (repo \`jikig-ai/soleur\`, created on or after ${WINDOW_START})."
  [[ -z "$note" ]] || add "$note"
  add ""
  if [[ "$n" -eq 0 ]]; then
    add "Found no hits in the window."
    add ""
    return 0
  fi
  shown="$n"
  if [[ "$n" -gt "$HIT_CAP" ]]; then
    shown="$HIT_CAP"
    add "${shown} of ${n} returned shown (cap ${HIT_CAP}). Hits are leads, not verdicts."
  else
    add "${n} returned, all shown. Hits are leads, not verdicts."
  fi
  add ""
  for rec in "${RECS[@]:1}"; do
    [[ -n "$rec" ]] || continue
    IFS=$'\x1f' read -r num state date login assoc typ kind title <<<"$rec"
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    [[ "$state" =~ ^(open|closed)$ ]] || state="unknown"
    [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || date="unknown"
    [[ "$kind" =~ ^(issue|pull\ request)$ ]] || kind="item"
    # Plain GitHub logins and association enums are already inert; anything else goes
    # through the sanitizer like every other third-party string.
    if [[ "$login" =~ ^[A-Za-z0-9-]{1,39}(\[bot\])?$ ]]; then login_s="\`${login}\`"; else login_s="$(wn_sanitize "$login")" || return 3; fi
    if [[ "$assoc" =~ ^[A-Z_]{1,24}$ ]]; then assoc_s="\`${assoc}\`"; else assoc_s="$(wn_sanitize "$assoc")" || return 3; fi
    title_s="$(wn_sanitize "$title")" || return 3
    ext=""
    case "$assoc" in
      OWNER|MEMBER) ;;
      *) if [[ "$typ" != "Bot" && "$login" != *"[bot]" ]]; then ext=" **external**"; fi ;;
    esac
    add "- #${num} ${kind}, ${state}, created ${date}, by ${login_s} (association ${assoc_s})${ext}: ${title_s}"
  done
  add ""
  return 0
}

# ------------------------------------------------------------ verbatim helpers ----
# A repo-controlled line printed verbatim inside a fence: C0 controls dropped, and an
# HTML-comment opener/closer broken so it can never forge or pre-spend a sentinel.
fence_line() {
  local l
  l="$(printf '%s' "$1" | tr -d '\000-\010\013-\037\177')"
  l="${l//<!--/< !--}"; l="${l//-->/-- >}"
  [[ "$l" != *'~~~'* ]] || l="(line contains a fence marker; not printed)"
  printf '%s\n' "$l"
}

ledger_and_adr() {
  local ledger adr f line
  add "### Code Quality state"
  add ""
  add "Expense-ledger line (verbatim, \`${LEDGER_REL}\`):"
  add ""
  ledger="$(grep -m1 -E '^\| GitHub Code Quality' "$ROOT/$LEDGER_REL" 2>/dev/null || true)"
  if [[ -n "$ledger" ]]; then
    add '~~~text'; add "$(fence_line "$ledger")"; add '~~~'
  else
    add "(no \`| GitHub Code Quality\` line found in the ledger)"
  fi
  add ""
  add "ADR-276 amendment heading(s) on the Code Quality decision (verbatim):"
  add ""
  adr=""
  for f in "$ROOT/$ADR_DIR_REL"/ADR-276-*.md; do
    [[ -f "$f" ]] || continue
    adr="$(grep -E '^## Amendment .*Code Quality' "$f" 2>/dev/null || true)"
    break
  done
  if [[ -n "$adr" ]]; then
    add '~~~text'
    while IFS= read -r line; do add "$(fence_line "$line")"; done <<<"$adr"
    add '~~~'
  else
    add "(no matching ADR-276 amendment heading found)"
  fi
  add ""
  return 0
}

# Values from the billing reply: a plain number or date is already inert and goes into a
# code span directly (one perl start per value adds up); anything else is sanitized.
span_num() { if [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then printf '`%s`' "$1"; else wn_sanitize "$1"; fi; }
span_date() { if [[ "$1" == none || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([T\ ][0-9:.Z+-]*)?$ ]]; then printf '`%s`' "$1"; else wn_sanitize "$1"; fi; }

# --------------------------------------------------------------------- billing ----
# Only the `code_quality` product is aggregated (wn_billing_month); the org's whole bill is
# never published. Months run from 2026-10 (the window) to the current month.
billing_section() {
  local now y m ny nm brc code_after=0 j lines gross net first last tag when unread_y="" unread_m=""
  now="$(wn_now_iso)"
  [[ "$now" =~ ^([0-9]{4})-([0-9]{2})- ]] || return 3
  ny="${BASH_REMATCH[1]}"; nm=$((10#${BASH_REMATCH[2]}))
  add "### Billing (\`code_quality\` product only)"
  add ""
  y=2026; m=10
  if (( y * 12 + m > ny * 12 + nm )); then
    add "No billing month in the window yet."
    add ""
    return 0
  fi
  while (( y * 12 + m <= ny * 12 + nm )); do
    wn_billing_month "$y" "$m"; brc=$?
    if [[ "$brc" -ne 0 ]]; then
      echo "::error::billing read for ${y}-${m} failed transiently; posting nothing (the next run retries)" >&2
      return 3
    fi
    case "$WN_BILL_STATUS" in
      ok)
        j="$WN_BILL_JSON"
        IFS=$'\x1f' read -r lines gross net first last < <(printf '%s' "$j" | jq -r '
            [(.lines | tostring), (.gross | tostring), (.net | tostring), (.first // "none"), (.last // "none")]
            | map(tostring | gsub("[\\x00-\\x1f\\x7f]"; "")) | join("\u001f")') || return 3
        [[ "$lines" =~ ^[0-9]+$ ]] || return 3
        tag="no line dated after ${WINDOW_START}"
        if [[ "$lines" -gt 0 && "${last:0:10}" > "$WINDOW_START" ]]; then tag="usage dated after ${WINDOW_START}"; code_after=1; fi
        when="$(printf '%04d-%02d' "$y" "$m")"
        add "- ${when}: ${lines} line(s), month gross $(span_num "$gross"), net $(span_num "$net"), first $(span_date "$first"), last $(span_date "$last"); ${tag}"
        ;;
      unreadable:*)
        unread_y="$y"; unread_m="$m"
        break ;;
      *) return 3 ;;
    esac
    m=$((m + 1)); if (( m > 12 )); then m=1; y=$((y + 1)); fi
  done
  if [[ -n "$unread_y" ]]; then
    add "Billing is not readable from CI (\`${WN_BILL_STATUS}\`: the Actions token has no organization billing scope). The ruling session reads it with the operator's own auth, one call per month:"
    add ""
    y="$unread_y"; m="$unread_m"
    while (( y * 12 + m <= ny * 12 + nm )); do
      add "- \`gh api 'orgs/jikig-ai/settings/billing/usage?year=${y}&month=${m}'\` (keep only the \`code_quality\` product)"
      m=$((m + 1)); if (( m > 12 )); then m=1; y=$((y + 1)); fi
    done
    echo "::warning::org billing is not readable from CI (${WN_BILL_STATUS}); the comment says so and lists the commands to run locally" >&2
  else
    if [[ "$code_after" -eq 1 ]]; then
      add ""
      add "Any \`code_quality\` usage dated after ${WINDOW_START}: yes (billing was expected to stop with the 2026-10-19 toggle; investigate before any flip)."
    else
      add ""
      add "Any \`code_quality\` usage dated after ${WINDOW_START}: no."
    fi
  fi
  add ""
  return 0
}

commits_section() {
  local log h d s s_s
  log="$(git -C "$ROOT" log --first-parent --max-count=20 --since="${WINDOW_START}T00:00:00Z" --format='%h%x09%cs%x09%s' -- "$LINT_RATCHET_REL" 2>/dev/null)" || {
    echo "::error::git log for ${LINT_RATCHET_REL} failed; posting nothing (the next run retries)" >&2
    return 3
  }
  add "### Commits touching \`${LINT_RATCHET_REL}\` since ${WINDOW_START}"
  add ""
  if [[ -z "$log" ]]; then
    add "None on the first-parent history."
    add ""
    return 0
  fi
  while IFS=$'\t' read -r h d s; do
    [[ "$h" =~ ^[0-9a-f]{4,40}$ ]] || continue
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || d="unknown"
    s_s="$(wn_sanitize "$s")" || return 3
    add "- \`${h}\` ${d} ${s_s}"
  done <<<"$log"
  add ""
  return 0
}

# ---------------------------------------------------------------------- gather ----
gather() {
  BODY_ACC=""
  add "## Re-evaluation data: lint-ratchet user-mode deferrals (#${TRACKER})"
  add ""
  add "Collected $(wn_now_iso) by the weekly \`code-quality-followups-watch\` workflow. Window: ${WINDOW_START} (merge of PR #10514) to now. This watcher changes no issue state, label or setting, and posts this notice once. Keyword hits are leads for the ruling session, not verdicts; titles are third-party text and are shown as code spans only."
  add ""
  add "### Deferred-item search leads"
  add ""
  add "Keywords come from the 2026-10-22 triage comment on this tracker. An author marked **external** is neither OWNER, MEMBER nor a bot."
  add ""
  render_search 'Item 1: user-mode JS/TS (eslint)' 'ratchet eslint' || return 3
  render_search 'Item 2: monorepo and nested ruff configs' 'ratchet monorepo' || return 3
  render_search 'Item 3: changed-files-only advisory mode' 'ratchet "changed files"' || return 3
  render_search 'Item 4a: native Windows' 'ratchet windows' || return 3
  render_search 'Item 4b: notebooks (.ipynb)' 'ratchet notebook' || return 3
  render_search 'Item 5: opt-in telemetry' 'ratchet telemetry' 'Static note: build blocked on `soleur:legal:clo` review; a hit here is still a valid flip signal ("any item above becomes a filed user request").' || return 3
  render_search 'Item 6: ever-better as an alternative engine' 'ever-better' 'A hit here is a valid flip signal ("someone files a request to try it"); research only.' || return 3
  add "### Sharpened trigger for item 3"
  add ""
  add "A filed issue reporting a ruff budget overrun or a ruff timeout from \`lint-ratchet.py auto\`, or a measured whole-tree run over 5 minutes on a user repository."
  add ""
  render_search 'Signal A: ruff exceeded the total budget' '"ruff exceeded the total budget"' || return 3
  render_search 'Signal B: ruff timeout from lint-ratchet.py auto' 'ruff timeout ratchet' || return 3
  ledger_and_adr || return 3
  billing_section || return 3
  commits_section || return 3
  add "### What this notice does not do"
  add ""
  add "Flip condition (from the tracker): any deferred item becomes a filed user request, or the Code Quality keep-or-drop decision in the code-quality epic changes the value of in-agent linting. No ruling is made here and nothing was changed. This tracker stays open."
  add ""
  add "The next \`soleur:go\` session has the CTO agent apply the flip condition to this data."
  WN_BODY="${BODY_ACC%$'\n'}"
  return 0
}

wn_preflight || exit 3
wn_notify_once_main "$TRACKER" "$EARLIEST" "$KEY" gather; rc=$?
exit "$rc"
