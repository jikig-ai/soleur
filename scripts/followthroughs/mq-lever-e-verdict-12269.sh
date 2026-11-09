#!/usr/bin/env bash
# mq-lever-e-verdict-12269.sh — verdict probe for the #12269 lever-E measured
# experiment (merge_queue.max_entries_to_build 2 -> 1).
#
# Followthrough-convention exit vocabulary:
#   0 = verdict reached, tracker may close / soak passes
#   5 = ACTION REQUIRED: the measured signal fired (waste appeared -> re-evaluate
#       the flip; or post-flip soak materially worse -> revert warranted)
#   3 = cannot determine state this sweep (gh failure, or the watch tracker row's
#       measurement window does not yet postdate the flip merge) -> re-poll.
#
# Dual-arm on the LIVE `max_entries_to_build` in infra/github/ruleset-ci-required.tf:
#
#   value==2 (decline regime): count `merge_group` `ci.yml` runs with
#     conclusion=cancelled created since (SOLEUR_FT_EARLIEST - 28d). >=1 means the
#     discarded-speculation premise the decline verdict rested on has appeared ->
#     exit 5 (re-evaluate the flip). 0 -> exit 0 (decline holds).
#
#   value==1 (post-flip regime): read the `test`/`merge_group` p50 row of the
#     ci-wallclock-p90 standing tracker (SOLEUR_FT_TRACKER). If that row's
#     measurement window does not postdate the flip merge (SOLEUR_FT_FLIP_MERGED),
#     it is a pre-flip sample -> exit 3 (re-poll). A p50 materially worse than the
#     before-window floor (SOLEUR_FT_P50_FLOOR, minutes; "materially" = > 20%)
#     -> exit 5 (revert warranted). Otherwise -> exit 0 (keep the flip).
#
# Any gh failure -> exit 3. Prints exactly one `REEVAL key=value...` line per run
# (the sweeper pastes it into the tracker comment).
#
# Env (injected by sweep-followthroughs.sh from the directive + secrets= clause):
#   SOLEUR_FT_EARLIEST   directive `earliest=` timestamp (the re-eval date under
#                        decline; the 28d window counts back from it)
#   SOLEUR_FT_TRACKER    ci-wallclock-p90 tracker issue number (value==1 arm)
#   SOLEUR_FT_FLIP_MERGED  ISO timestamp the flip merged (value==1 arm)
#   SOLEUR_FT_P50_FLOOR  before-window `test` merge_group p50 floor in minutes
#                        (value==1 arm; default 49)
#   REPO_ROOT            repo root override (fixture suites); default = repo root
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TF="$REPO_ROOT/infra/github/ruleset-ci-required.tf"
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
TRACKER="${SOLEUR_FT_TRACKER:-}"
FLIP_MERGED="${SOLEUR_FT_FLIP_MERGED:-}"
P50_FLOOR="${SOLEUR_FT_P50_FLOOR:-49}"

repoll() { printf 'REEVAL verdict=repoll reason=%s\n' "$1"; exit 3; }

[ -f "$TF" ] || repoll 'tf-missing'
value="$(grep -oE 'max_entries_to_build[[:space:]]*=[[:space:]]*[0-9]+' "$TF" | grep -oE '[0-9]+$' | head -1)"
case "$value" in
  1|2) : ;;
  *) repoll "tf-value-unreadable-or-unsanctioned value=${value:-none}" ;;
esac

gh_fail() { repoll "gh-failure"; }

if [ "$value" = "2" ]; then
  # ---- decline regime: did the waste premise appear? ----
  [ -n "$EARLIEST" ] || repoll 'earliest-unset'
  win_start="$(date -u -d "${EARLIEST%Z} - 28 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    || win_start="$(date -u -d "@$(( $(date -u -d "$EARLIEST" +%s) - 2419200 ))" +%Y-%m-%dT%H:%M:%SZ)"
  sdate="${win_start%%T*}"
  runs="$(gh run list --repo jikig-ai/soleur --event merge_group --workflow ci.yml \
          --status cancelled --created ">=${sdate}" --json databaseId,conclusion,createdAt --limit 400 2>/dev/null)" \
    || gh_fail
  n="$(printf '%s' "$runs" | jq 'length' 2>/dev/null)" || gh_fail
  [ -n "$n" ] || gh_fail
  if [ "$n" -ge 1 ]; then
    printf 'REEVAL verdict=waste-appeared cancelled=%s window_start=%s\n' "$n" "$win_start"
    exit 5
  fi
  printf 'REEVAL verdict=decline-hold cancelled=0 window_start=%s\n' "$win_start"
  exit 0
fi

# ---- value==1: post-flip soak ----
[ -n "$TRACKER" ] || repoll 'tracker-unset'
[ -n "$FLIP_MERGED" ] || repoll 'flip-merged-unset'
body="$(gh issue view "$TRACKER" --repo jikig-ai/soleur --json body --jq .body 2>/dev/null)" || gh_fail
[ -n "$body" ] || repoll 'tracker-body-empty'

# Extract the `test`/`merge_group` row: `| test | merge_group | <p50> | <p90> | <w0>..<w1> |`
row="$(printf '%s\n' "$body" | grep -E '^\|[[:space:]]*test[[:space:]]*\|[[:space:]]*merge_group' | head -1)"
[ -n "$row" ] || repoll 'tracker-row-missing'
p50_raw="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$4); print $4}')"
win_raw="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$6); print $6}')"
p50_min="$(printf '%s' "$p50_raw" | grep -oE '^[0-9]+' || true)"
win_end="$(printf '%s' "$win_raw" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1 || true)"
[ -n "$p50_min" ] || repoll 'p50-unparseable'
[ -n "$win_end" ] || repoll 'window-unparseable'

# The row is an after-sample only when its window end postdates the flip merge.
win_end_s="$(date -u -d "$win_end" +%s 2>/dev/null)" || repoll 'window-unparseable'
flip_s="$(date -u -d "$FLIP_MERGED" +%s 2>/dev/null)" || repoll 'flip-merged-unparseable'
if [ "$win_end_s" -le "$flip_s" ]; then
  repoll "tracker-window-pre-flip window_end=$win_end"
fi

# Materially worse = p50 > floor * 1.2 (integer compare on x10).
if [ "$(( p50_min * 10 ))" -gt "$(( P50_FLOOR * 12 ))" ]; then
  printf 'REEVAL verdict=revert-warranted p50=%sm floor=%sm window=%s\n' "$p50_min" "$P50_FLOOR" "$win_raw"
  exit 5
fi
printf 'REEVAL verdict=keep-flip p50=%sm floor=%sm window=%s\n' "$p50_min" "$P50_FLOOR" "$win_raw"
exit 0
