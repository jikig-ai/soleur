#!/usr/bin/env bash
# merge-bypass-audit.sh — detective post-merge probe for ruleset-bypass landings (#12666).
#
# For ONE merge SHA on `main` this decides whether the landing carried the signal the
# required-check ruleset exists to enforce, and makes a BYPASS loud (deduped GitHub issue,
# label `compliance/critical`, plus a ::error annotation) instead of silent — the gap
# PR #12565 exposed when it merged over a ~21 h red required `test` check.
#
# VERDICT CONTRACT (plan Guard 1; rulings in decision-challenges.md):
#   ok  via=merge_group   a `merge_group` run OF THE REQUIRED-BATTERY WORKFLOW
#                         (.github/workflows/ci.yml) with conclusion=success exists on the
#                         merge SHA — the queue is the full-battery authority (ADR-276). A
#                         merge_group success from any OTHER workflow confers nothing.
#   ok  via=pr_head       no qualifying queue run, but the source PR's head has every
#                         required context green AT the merge instant (a compliant direct
#                         merge).
#   bypass                at least one required context was not green at merge — filed as a
#                         deduped compliance/critical issue + ::error, exit 1. If the issue
#                         create itself fails the classification survives anyway:
#                         `verdict=bypass filed=FAILED`, exit 2.
#   bypass class=no_source_pr
#                         no source PR resolvable (direct push) — same alert path, exit 1.
#   check_flipped_after_merge
#                         every required context was green at merge but at least one is red
#                         NOW (a post-merge re-run flipped it): a CI regression report
#                         (::warning), NEVER bypass — CTO ruling T11. Exit 0.
#   unread                ANY API read that cannot establish the answer exits 2 with an
#                         ::error annotation AND a deduped, unlabeled unread-notice issue —
#                         a red run alone is not a durable artifact (best-effort: a filing
#                         failure only warns, the exit stays 2). The unread-answer rule:
#                         never exit 0 and never guess the kinder verdict (the
#                         empty-body-verdict learning, 2026-09-22).
#
# "Green" means check-run conclusion success, skipped, or neutral — the conclusions
# GitHub itself counts as satisfying a required check (attack surface row (e)).
#
# Green-at-merge is PROVEN, never assumed: among the head's check runs for a context, the
# latest run started at-or-before the merge instant must be completed with a green
# conclusion at-or-before that instant. A run still in flight at merge is a pending
# required check — landing over it is a bypass, not a compliant merge (its at_merge_state
# reports `completed_after_merge` when it has since finished). Ordering is declared
# UNESTABLISHED when ANY of a context's runs carries a null started_at or is completed
# with a null completed_at — a deliberately conservative posture: a transient queued
# re-run missing timestamps can yield `unread` on an otherwise clean merge, and that is
# loud by design (a missed bypass is silent; a false unread reds one run).
#
# ANCESTRY GATE: before the source-PR arm is trusted, `compare/<sha>...main` must report
# `ahead` or `identical` — proof the SHA sits on main's history. A dispatched/backfilled
# SHA that never landed could otherwise resolve a green source-PR arm and report a false
# `ok`. One extra API read on every audit that gets past the queue arm.
#
# REQUIRED-SET AUTHORITY: scripts/ci-required-ruleset-canonical-required-status-checks.json
# — the canonical file the daily cron-ruleset-bypass-audit holds equal to the live ruleset
# (ruleset 14145388), so required-set drift alarms this probe for free (ruling T12).
# All 11 canonical contexts carry integration_id 15368 (GitHub Actions), so check runs —
# not legacy statuses — are the right read surface, and each context is matched on
# {name, app.id}: a foreign check-app posting a colliding context name cannot corrupt
# the ordering read.
#
# DEDUPE: before filing, an open-issue search on the dedupe key; a hit naming the key in
# title or body suppresses refiling (the merge SHA for bypass alerts, the fixed notice
# title for unread notices). No auto-close arm: a bypass finding does not go green on a
# later run of the same SHA, unlike the sibling drift audit's self-healing class.
#
# KNOWN RESIDUALS (adjudicated; kept loud rather than engineered away):
#   * self-tamper — the audit runs the probe code from the pushed commit it audits, so a
#     tampering push could silence THIS script; it cannot silence the alert for its own
#     landing (a tampering push has no merge_queue run and no source PR -> class
#     no_source_pr), and git history preserves the evidence trail.
#   * one-push-one-landing — only github.sha (the push tip) is audited; intermediate
#     commits in a multi-commit direct push are not individually audited (the tip's
#     no_source_pr verdict still flags the class).
#   * backfill caution — audits judge a historical merge by TODAY's canonical required
#     set: contexts added since the merge read as false `no_run_at_merge` bypasses, and
#     contexts removed clear old bypasses. Read backfill findings against the required
#     set in force at the merge date.
#
# The VERDICT begin/end marker comments bracketing the verdict block below are the
# mutation anchor for fixture arm D (the always-ok instrument control — it counts them
# and rewrites between them) — do not remove, duplicate, or quote them elsewhere.
#
# Usage:
#   scripts/merge-bypass-audit.sh <merge-sha>     audit one merge commit on main
#   scripts/merge-bypass-audit.sh --self-check    required-set parses + gh auth resolves;
#                                               prints `merge-bypass-audit self-check ok`
#
# Exit: 0 ok / check_flipped_after_merge · 1 bypass (+filed or deduped issue) · 2 unread.
#
# Env seams (fixture suite):
#   MBA_REPO           owner/name (default $GITHUB_REPOSITORY, else jikig-ai/soleur)
#   MBA_REQUIRED_JSON  required-set JSON path (default: sibling canonical file)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${MBA_REPO:-${GITHUB_REPOSITORY:-jikig-ai/soleur}}"
REQUIRED_JSON="${MBA_REQUIRED_JSON:-${SCRIPT_DIR}/ci-required-ruleset-canonical-required-status-checks.json}"
ISSUE_LABEL="compliance/critical"
MAX_PAGES=10   # check-runs pagination cap: a runaway page stream is unread, not BYPASS
PER_PAGE=100   # page size for the paginated list reads (actions/runs, check-runs)
# Fixed unread-notice title AND its dedupe key: all unread findings share one open notice.
UNREAD_NOTICE_TITLE="[merge-bypass-audit] unread verdict — investigation needed"

usage() { printf 'usage: %s <merge-sha>|--self-check\n' "${0##*/}" >&2; exit 2; }

# unread_notice <detail> — the durable artifact for an unread verdict: a deduped,
# UNLABELED issue under the fixed title above (dedupe is by the title itself, not a SHA,
# so every unread finding shares the one open notice). STRICTLY best-effort: every read
# or write failure only warns — nothing here may change the exit code or mask the
# verdict line, so it never routes through die_unread.
unread_notice() {
  local detail="$1" search_body hits created
  search_body="$(api_get "search/issues" -f "q=repo:${REPO} is:issue is:open ${UNREAD_NOTICE_TITLE} in:title,body")" || {
    printf '::warning::merge-bypass-audit: unread-notice dedupe search failed; continuing\n' >&2
    return 0
  }
  hits="$(jq --arg s "$UNREAD_NOTICE_TITLE" \
        '[.items[]? | select((((.title // "") + " " + (.body // "")) | contains($s)))] | length' \
        <<<"$search_body" 2>/dev/null)" || {
    printf '::warning::merge-bypass-audit: unread-notice dedupe projection failed; continuing\n' >&2
    return 0
  }
  if [[ "$hits" -gt 0 ]]; then return 0; fi
  created="$(gh issue create --repo "$REPO" --title "$UNREAD_NOTICE_TITLE" \
    --body "The merge-bypass audit returned an \`unread\` verdict (exit 2). A red run is not a durable artifact — this deduped notice is the investigation trail.

Latest unread detail: \`${detail}\`.

Filed by \`scripts/merge-bypass-audit.sh\`; deduped on this fixed title — one open unread-notice at a time." 2>/dev/null)" || {
    printf '::warning::merge-bypass-audit: unread-notice issue create failed; continuing\n' >&2
    return 0
  }
  printf '::warning::merge-bypass-audit: unread notice filed: %s\n' "$created" >&2
  return 0
}

# die_unread <what> — the unread-answer rule: exit 2, never exit 0 on an unread verdict.
die_unread() {
  printf '::error::merge-bypass-audit: unread answer — %s\n' "$1" >&2
  printf 'verdict=unread detail=%s\n' "${1// /_}"
  # The durable artifact only fires once a real audit is in flight — an invalid-sha
  # operand is operator error, not an audit verdict worth a repo issue.
  if [[ "${_SHA_VALIDATED:-0}" == 1 ]]; then unread_notice "$1" || :; fi
  exit 2
}

# load_required_contexts — fills REQUIRED_CONTEXTS_JSON with [{context, integration_id}]
# pairs (a missing integration_id projects as -1, matching only app-less check runs);
# invalid or empty canonical is unread (a corrupt required set cannot prove green).
REQUIRED_CONTEXTS_JSON=""
load_required_contexts() {
  [[ -f "$REQUIRED_JSON" ]] || die_unread "required-set JSON not found: $REQUIRED_JSON"
  jq -e 'type == "array" and length > 0
         and all(.[]; (.context | type == "string") and (.context | length > 0)
                 and ((.integration_id // 0) | type == "number"))' \
     "$REQUIRED_JSON" >/dev/null 2>&1 \
    || die_unread "required-set JSON is not an array of {context:string, integration_id?:number} objects: $REQUIRED_JSON"
  REQUIRED_CONTEXTS_JSON="$(jq -c '[.[] | {context, integration_id: (.integration_id // -1)}]' "$REQUIRED_JSON")" \
    || die_unread "required-set JSON context projection failed: $REQUIRED_JSON"
}

# api_get <endpoint> [gh api args…] — one gh api read; body on stdout. Callers `|| die_unread`.
api_get() { gh api "$@"; }

# ---------------------------------------------------------------- self-check
self_check() {
  _SHA_VALIDATED=1   # self-check gates the audit in CI — its failures are audit-blocking
  command -v gh  >/dev/null 2>&1 || die_unread "gh is not on PATH"
  command -v jq  >/dev/null 2>&1 || die_unread "jq is not on PATH"
  load_required_contexts
  api_get "repos/$REPO" >/dev/null \
    || die_unread "gh auth/repo read failed for $REPO (self-check)"
  printf 'merge-bypass-audit self-check ok\n'
  exit 0
}

# ---------------------------------------------------------------- dedupe + file
# file_alert <sha> <kind> <title> <body> [dedupe_key] — dedupe on the key (default: the
# merge SHA; an open issue naming the key in title or body suppresses refiling), then
# create the labeled issue. A create FAILURE does not degrade the verdict to unread:
# the classification survives as `verdict=bypass filed=FAILED`, exit 2.
file_alert() {
  local sha="$1" kind="$2" title="$3" body="$4" dedupe_key search_body hits created
  dedupe_key="${5:-$sha}"
  search_body="$(api_get "search/issues" -f "q=repo:${REPO} is:issue is:open ${dedupe_key} in:title,body")" \
    || die_unread "issue dedupe search failed for $sha"
  jq -e 'type == "object" and (.total_count | type == "number") and (.items | type == "array")' \
     <<<"$search_body" >/dev/null 2>&1 \
    || die_unread "issue dedupe search body invalid for $sha"
  hits="$(jq --arg s "$dedupe_key" '[.items[] | select((((.title // "") + " " + (.body // "")) | contains($s)))] | length' <<<"$search_body")" \
    || die_unread "issue dedupe search projection failed for $sha"
  if [[ "$hits" -gt 0 ]]; then
    printf '::error::merge-bypass-audit: BYPASS %s — %s (alert deduped: open issue already names the dedupe key)\n' "$sha" "$kind" >&2
    printf 'verdict=bypass class=%s sha=%s deduped=open-issue\n' "$kind" "$sha"
    exit 1
  fi
  created="$(gh issue create --repo "$REPO" --title "$title" --label "$ISSUE_LABEL" --body "$body")" || {
    printf '::error::merge-bypass-audit: BYPASS %s — %s (alert filing FAILED; classification survives as filed=FAILED)\n' "$sha" "$kind" >&2
    printf 'verdict=bypass class=%s sha=%s filed=FAILED\n' "$kind" "$sha"
    exit 2
  }
  printf '::error::merge-bypass-audit: BYPASS %s — %s (alert filed: %s)\n' "$sha" "$kind" "$created" >&2
  printf 'verdict=bypass class=%s sha=%s filed=%s\n' "$kind" "$sha" "$created"
  exit 1
}

# ---------------------------------------------------------------- audit one merge
audit() {
  local sha="$1"
  [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die_unread "invalid merge sha: '$sha'"
  _SHA_VALIDATED=1
  load_required_contexts

  # (a) merge_group success on the merge SHA -> OK — but ONLY a success from the
  # required-battery workflow (ci.yml) counts: ANY other workflow's merge_group success
  # is not queue authority and falls through to the source-PR arm.
  local runs_body total_runs
  runs_body="$(api_get "repos/${REPO}/actions/runs?event=merge_group&head_sha=${sha}&per_page=${PER_PAGE}")" \
    || die_unread "actions/runs read failed for $sha"
  jq -e 'type == "object" and (.workflow_runs | type == "array") and (.total_count | type == "number")' \
     <<<"$runs_body" >/dev/null 2>&1 \
    || die_unread "actions/runs body invalid for $sha"
  total_runs="$(jq '.total_count' <<<"$runs_body")" || die_unread "actions/runs total_count unread for $sha"
  [[ "$total_runs" -le "$(jq '.workflow_runs | length' <<<"$runs_body")" ]] \
    || die_unread "actions/runs truncated for $sha (total_count=$total_runs over one page)"
  if [[ "$(jq '[.workflow_runs[]
            | select(.path == ".github/workflows/ci.yml" and .conclusion == "success")] | length' <<<"$runs_body")" -gt 0 ]]; then
    printf 'verdict=ok via=merge_group sha=%s\n' "$sha"
    exit 0
  fi

  # (a') ancestry gate: `compare/<sha>...main` must report ahead|identical — proof the
  # sha sits on main's history — before the source-PR arm is trusted. A sha that never
  # landed (diverged/behind/missing status, e.g. a backfilled PR head) could otherwise
  # resolve a green source-PR arm and read as a false `ok`. One extra read per audit.
  local cmp_body cmp_status
  cmp_body="$(api_get "repos/${REPO}/compare/${sha}...main")" \
    || die_unread "compare read failed for ${sha}...main"
  jq -e 'type == "object" and (.status | type == "string")' \
     <<<"$cmp_body" >/dev/null 2>&1 \
    || die_unread "compare body invalid for ${sha}...main"
  cmp_status="$(jq -r '.status' <<<"$cmp_body")" || die_unread "compare status unread for $sha"
  case "$cmp_status" in
    ahead|identical) : ;;   # main is ahead-of-or-equal the sha: the sha is on main
    *) die_unread "sha not an ancestor of main (compare status: ${cmp_status})" ;;
  esac

  # (b) resolve the source PR: prefer the commits/{sha}/pulls association whose
  # merge_commit_sha IS this sha; fall back to the commit message `(#N)` /
  # `Merge pull request #N` spellings and verify the named PR the same way.
  local pulls_body pr_sel="" pr_num="" head_sha="" merge_time=""
  pulls_body="$(api_get "repos/${REPO}/commits/${sha}/pulls")" \
    || die_unread "commits/pulls read failed for $sha"
  jq -e 'type == "array"' <<<"$pulls_body" >/dev/null 2>&1 \
    || die_unread "commits/pulls body invalid for $sha"
  pr_sel="$(jq -c --arg s "$sha" '[.[] | select(.merge_commit_sha == $s and .merged_at != null)] | first // empty' <<<"$pulls_body")" \
    || die_unread "commits/pulls projection failed for $sha"
  if [[ -z "$pr_sel" ]]; then
    local commit_body msg n pr_body
    commit_body="$(api_get "repos/${REPO}/commits/${sha}")" \
      || die_unread "commit read failed for $sha"
    jq -e 'type == "object" and (.commit | type == "object")' <<<"$commit_body" >/dev/null 2>&1 \
      || die_unread "commit body invalid for $sha"
    msg="$(jq -r '.commit.message // ""' <<<"$commit_body")" || die_unread "commit message unread for $sha"
    n="$(printf '%s' "$msg" | sed -nE '1s/^.*\(#([0-9]+)\).*$/\1/p')"
    [[ -n "$n" ]] || n="$(printf '%s' "$msg" | sed -nE 's/^Merge pull request #([0-9]+).*$/\1/p')"
    if [[ -n "$n" ]]; then
      pr_body="$(api_get "repos/${REPO}/pulls/${n}")" \
        || die_unread "pulls/$n read failed for $sha"
      jq -e 'type == "object"' <<<"$pr_body" >/dev/null 2>&1 \
        || die_unread "pulls/$n body invalid for $sha"
      if [[ "$(jq -r --arg s "$sha" 'if (.merged == true and .merge_commit_sha == $s and .merged_at != null and (.head.sha | type == "string")) then "yes" else "no" end' <<<"$pr_body")" == "yes" ]]; then
        pr_sel="$(jq -c '{number, merged_at, head}' <<<"$pr_body")" || die_unread "pulls/$n projection failed"
      fi
    fi
  fi
  if [[ -n "$pr_sel" ]]; then
    pr_num="$(jq -r '.number' <<<"$pr_sel")" || die_unread "source PR number unread for $sha"
    head_sha="$(jq -r '.head.sha' <<<"$pr_sel")" || die_unread "source PR head sha unread for $sha"
    [[ "$head_sha" =~ ^[0-9a-fA-F]{40}$ ]] || die_unread "source PR head sha malformed for $sha"
    # The merge instant is the source PR's merged_at — needed only on the PR-resolved
    # path below; the no_source_pr alert makes no use of a timestamp.
    merge_time="$(jq -r '.merged_at // ""' <<<"$pr_sel")" || die_unread "source PR merged_at unread for $sha"
    [[ -n "$merge_time" ]] || die_unread "no merge timestamp resolvable for $sha"
  fi
  if [[ -z "$pr_sel" ]]; then
    file_alert "$sha" "no_source_pr" \
      "[merge-bypass-audit] commit ${sha} on main has no resolvable source PR" \
      "Merge commit \`${sha}\` landed on \`main\` with no merge_queue success run and no source PR resolvable via \`/commits/{sha}/pulls\` or the commit-message \`#N\` spellings — a direct push (or an unresolvable merge) is the enforcement-gap class this probe exists to flag (#12666).

Sanctioned-revert class: \`post-merge-monitor.yml\` bot-fixes push reverts straight to \`main\` (\`git push origin main\`). If this SHA is a monitor revert, this alert is the expected direct-push flag — adjudicate it and close as a false positive.

Evidence: no \`merge_group\` run with conclusion=success on the SHA; no merged PR naming it as \`merge_commit_sha\`.

Filed by \`scripts/merge-bypass-audit.sh\`; deduped per merge SHA. Audit doc: \`knowledge-base/engineering/operations/post-mortems/2026-11-12-pr-12565-red-required-check-bypass-audit-postmortem.md\`."
  fi

  # (c) the source PR head's check runs vs the required set. `green` = the conclusions
  # GitHub counts as satisfying a required check; `green_at_merge` additionally requires
  # the run to have been the latest started at-or-before the merge instant AND completed
  # green at-or-before it — a run in flight at merge is a pending required check.
  local page=1 got=0 total_cr=0 runs_lines="" page_body page_runs
  while :; do
    page_body="$(api_get "repos/${REPO}/commits/${head_sha}/check-runs?per_page=${PER_PAGE}&page=${page}")" \
      || die_unread "check-runs read failed for head $head_sha (page $page)"
    jq -e 'type == "object" and (.check_runs | type == "array") and (.total_count | type == "number")' \
       <<<"$page_body" >/dev/null 2>&1 \
      || die_unread "check-runs body invalid for head $head_sha (page $page)"
    total_cr="$(jq '.total_count' <<<"$page_body")" || die_unread "check-runs total_count unread"
    page_runs="$(jq -c '.check_runs[]' <<<"$page_body")" || die_unread "check-runs projection failed"
    if [[ -n "$page_runs" ]]; then
      runs_lines+="$page_runs"$'\n'
      got="$(printf '%s\n' "$runs_lines" | grep -c .)" || die_unread "check-runs accumulation failed"
    fi
    [[ "$got" -ge "$total_cr" || "$page" -ge "$MAX_PAGES" ]] && break
    page=$((page + 1))
  done
  [[ "$got" -ge "$total_cr" ]] \
    || die_unread "check-runs truncated for head $head_sha (got $got of $total_cr)"

  local verdict_json unest_n bad_n flipped_n unest bad flipped
  verdict_json="$(printf '%s\n' "$runs_lines" | jq -s -c --arg mt "$merge_time" --argjson ctxs "$REQUIRED_CONTEXTS_JSON" '
    def green: .status == "completed"
               and (.conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral");
    . as $all
    | [ $ctxs[] as $c
        # Match on {name, app.id}: a foreign check-app posting a colliding context name
        # must not enter the ordering read.
        | ([ $all[] | select(.name == $c.context
                             and (.app.id // -1) == $c.integration_id) ]) as $mine
        | ($mine | sort_by((.started_at // ""), (.id // 0)) | last) as $latest
        | ([ $mine[] | select(.started_at != null and .started_at <= $mt) ]
             | sort_by(.started_at, (.id // 0)) | last) as $atmerge
        | {
            context: $c.context,
            unestablished: ([ $mine[] | select(.started_at == null
                                   or (.status == "completed" and .completed_at == null)) ]
                            | length > 0),
            green_at_merge: ($atmerge != null and ($atmerge | green)
                             and $atmerge.completed_at != null and $atmerge.completed_at <= $mt),
            at_merge_state: (if $atmerge == null then "no_run_at_merge"
                             elif ($atmerge | green) and $atmerge.completed_at != null
                                  and $atmerge.completed_at <= $mt then "green"
                             elif $atmerge.status == "completed" and $atmerge.completed_at != null
                                  and $atmerge.completed_at > $mt then "completed_after_merge"
                             elif $atmerge.status != "completed" then "pending_at_merge"
                             else $atmerge.conclusion end),
            latest_green: ($latest != null and ($latest | green)),
            latest_state: (if $latest == null then "none"
                           elif $latest.status != "completed" then $latest.status
                           else $latest.conclusion end)
          }
      ] as $rows
    | {
        unestablished: [ $rows[] | select(.unestablished) | .context ],
        bad:           [ $rows[] | select(.green_at_merge | not)
                         | { context: .context, state: .at_merge_state } ],
        flipped:       [ $rows[] | select(.green_at_merge and (.latest_green | not))
                         | { context: .context, state: .latest_state } ]
      }')" || die_unread "check-run verdict computation failed for $sha"
  unest_n="$(jq '.unestablished | length' <<<"$verdict_json")" || die_unread "verdict projection failed (unestablished)"
  bad_n="$(jq '.bad | length' <<<"$verdict_json")" || die_unread "verdict projection failed (bad)"
  flipped_n="$(jq '.flipped | length' <<<"$verdict_json")" || die_unread "verdict projection failed (flipped)"

  # >>> VERDICT >>>
  if [[ "$unest_n" -gt 0 ]]; then
    unest="$(jq -c '.unestablished' <<<"$verdict_json")" || die_unread "verdict detail unread (unestablished)"
    die_unread "check-run ordering unestablished for required context(s) $unest on PR #$pr_num head $head_sha"
  elif [[ "$bad_n" -gt 0 ]]; then
    bad="$(jq -c '.bad' <<<"$verdict_json")" || die_unread "verdict detail unread (bad)"
    file_alert "$sha" "bypass" \
      "[merge-bypass-audit] merge ${sha} landed over a non-green required set" \
      "Merge commit \`${sha}\` (source PR #${pr_num}, head \`${head_sha}\`) landed on \`main\` with no merge_queue success run, and the PR head did NOT have every required check green at the merge instant — the enforcement-gap class of #12565 / #12666.

Required context(s) not green at merge (\`${merge_time}\`):
\`\`\`json
${bad}
\`\`\`

Required set: \`scripts/ci-required-ruleset-canonical-required-status-checks.json\` (ruleset 14145388 canonical).

Filed by \`scripts/merge-bypass-audit.sh\`; deduped per merge SHA. Audit doc: \`knowledge-base/engineering/operations/post-mortems/2026-11-12-pr-12565-red-required-check-bypass-audit-postmortem.md\`."
  elif [[ "$flipped_n" -gt 0 ]]; then
    flipped="$(jq -c '.flipped' <<<"$verdict_json")" || die_unread "verdict detail unread (flipped)"
    printf '::warning::merge-bypass-audit: check_flipped_after_merge %s — required context(s) %s were green at merge (%s) but are not green now; a post-merge re-run flipped them (CI regression, not bypass)\n' "$sha" "$flipped" "$merge_time" >&2
    printf 'verdict=check_flipped_after_merge sha=%s pr=%s flipped=%s\n' "$sha" "$pr_num" "$flipped"
    exit 0
  else
    printf 'verdict=ok via=pr_head sha=%s pr=%s\n' "$sha" "$pr_num"
    exit 0
  fi
  # <<< VERDICT <<<
}

[[ $# -le 1 ]] || usage   # extra operands ("<sha> garbage", "<sha> --self-check") are errors
case "${1:-}" in
  --self-check) self_check ;;
  "") usage ;;
  -*) usage ;;
  *) audit "$1" ;;
esac
