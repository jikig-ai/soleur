#!/usr/bin/env bash
# mq-lever-e-verdict-12269.sh — verdict probe for the #12269 lever-E measured
# experiment (merge_queue.max_entries_to_build 2 -> 1).
#
# CREDENTIAL POSTURE: needs GH_TOKEN (sweeper forwards the names in `secrets=`;
# the directive carries `secrets=GH_TOKEN`). With GH_TOKEN absent every gh call
# fails -> exit 3 forever, so refuse loudly instead (sibling convention:
# actions-queue-tail-8450.sh).
case "$-" in *x*) [ -n "${GH_TOKEN:+x}" ] && { echo "FATAL: refusing to run under xtrace with GH_TOKEN set" >&2; exit 78; } ;; esac
#
# Followthrough-convention exit vocabulary:
#   0 = verdict reached, tracker may close / soak passes
#   5 = ACTION REQUIRED: the measured signal fired (waste appeared -> re-evaluate
#       the flip; or post-flip soak materially worse -> revert warranted)
#   3 = cannot determine state this sweep (gh/git failure, tracker not found, or
#       the watch report does not yet postdate the flip merge) -> re-poll.
#       NOTE: exit 3 maps to a CANNOT ESTABLISH comment per sweep. The repoll
#       reasons below are transient while the watch schema holds; a schema change
#       or a renamed tf turns them config-dead — treat a persistent reason as a
#       bug to fix, not a state to wait out.
#
# Dual-arm on the LIVE `max_entries_to_build` in infra/github/ruleset-ci-required.tf:
#
#   value==2 (decline regime): count `merge_group` `ci.yml` runs with
#     conclusion=cancelled created since (SOLEUR_FT_EARLIEST - 28d). >=2 means the
#     discarded-speculation premise the decline verdict rested on has appeared ->
#     exit 5 (re-evaluate the flip; same threshold the gate used). <2 -> exit 0.
#
#   value==1 (post-flip regime): read the `test`/`merge_group` row of the
#     ci-wallclock-p90 standing tracker — schema is
#     `| <check> | <surface> | <n> | <p50 (s)> | <p90 (s)> | <p90 dur (s)> | <bound> | <goal> |`
#     (SECONDS, emitted by scripts/watch-wallclock-p90-11774.sh; a zero-sample
#     surface emits `—` placeholders, which is a repoll not a verdict). The body's
#     `Report refreshed: <ISO>` must postdate the flip merge, else exit 3 (the
#     rolling-30 sample is pre-flip — repoll). Revert-warranted (exit 5) iff
#     p50_s > P50_FLOOR*60*1.2 OR p90_s > P50_FLOOR*60*2.5 (the regression lives
#     in the tail: serialization only penalises depth>=2 merges) OR >=2
#     cancelled merge_group runs since the flip merge (churn: the flip made it
#     worse). Otherwise -> exit 0 (keep).
#
# Any gh/git failure -> exit 3. Prints exactly one `REEVAL key=value...` line;
# the sweeper folds the probe's last-4KB output into a <details> block on the
# tracker comment (sweep-followthroughs.sh), so the line must stay self-reading.
#
# Input derivation (followthrough-convention: required inputs must be derivable
# under `env -i`; env vars remain OPTIONAL overrides for fixtures):
#   SOLEUR_FT_TRACKER    standing tracker number; derived via the watch's own
#                        find-or-file (exact title + github-actions author). On a
#                        duplicate-tracker state the LOWEST number wins (the
#                        watch warns and takes list order; same net effect —
#                        both watch-authored trackers carry the same report).
#   SOLEUR_FT_FLIP_MERGED  ISO ts the flip landed on main; derived by an anchored
#                        -G pickaxe on the tf's assignment line (comment edits
#                        cannot move it; a value-only revert can, correctly).
#   SOLEUR_FT_P50_FLOOR  before-window p50 floor in MINUTES (default 49).
#   SOLEUR_FT_EARLIEST   directive `earliest=` (the re-eval date under decline).
#   REPO_ROOT            repo root override (fixture suites); default = repo root.
#
# RETIREMENT: when this probe retires, also remove/consider: the
# `scripts/followthroughs/mq-lever-e-verdict-12269` run_suite row in
# scripts/test-all.sh, its floor row in scripts/suite-durations.tsv, the
# fixture-guard rows in plugins/soleur/test/fixture-relative-assert.baseline.txt,
# the directive comment on #12269, and the pointer sentences in
# infra/github/ruleset-ci-required.tf, infra/github/README.md and ADR-270.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TF="$REPO_ROOT/infra/github/ruleset-ci-required.tf"
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
P50_FLOOR="${SOLEUR_FT_P50_FLOOR:-49}"
TRACKER_TITLE='ci-wallclock-p90: required-check wall-clock report'

repoll() { printf 'REEVAL verdict=repoll reason=%s\n' "$1"; exit 3; }
gh_fail() { repoll "gh-failure"; }

[ -f "$TF" ] || repoll 'tf-missing'
# Comment-strip the WHOLE file first (mirrors _mq_strip_hcl: #, //, and /* */
# state), THEN window to the FIRST `merge_queue {` block, THEN anchored-assign
# grep. Order matters: a /* */-wrapped whole block placed above the real one is
# the T-mq-1.m8 masquerade — stripping inside the window cannot see its opener.
value="$(awk '
  BEGIN { c=0 }
  {
    line=$0; out=""
    for (i=1; i<=length(line); i++) {
      two=substr(line,i,2)
      if (c==0 && (two=="/*")) { c=1; i++; continue }
      if (c==1 && (two=="*/")) { c=0; i++; continue }
      if (c==1) continue
      if (two=="//" || substr(line,i,1)=="#") break
      out=out substr(line,i,1)
    }
    print out
  }' "$TF" \
  | sed -n '/^[[:space:]]*merge_queue[[:space:]]*{/,/^[[:space:]]*}/p' \
  | grep -oE '^[[:space:]]*max_entries_to_build[[:space:]]*=[[:space:]]*[0-9]+' \
  | grep -oE '[0-9]+$' | head -1)"
case "$value" in
  1|2) : ;;
  *) repoll "tf-value-unreadable-or-unsanctioned value=${value:-none}" ;;
esac
[[ "$P50_FLOOR" =~ ^[0-9]{1,6}$ ]] || repoll 'p50-floor-unparseable'

count_cancelled() { # <since-date YYYY-MM-DD> -> prints run count, or rc 1
  local runs
  runs="$(gh run list --repo jikig-ai/soleur --event merge_group --workflow ci.yml \
          --status cancelled --created ">=${1}" --json databaseId,conclusion,createdAt --limit 400 2>/dev/null)" \
    || return 1
  printf '%s' "$runs" | jq 'length' 2>/dev/null
}

if [ "$value" = "2" ]; then
  # ---- decline regime: did the waste premise appear? ----
  [ -n "$EARLIEST" ] || repoll 'earliest-unset'
  # Validate the epoch BEFORE arithmetic: a failed inner `date` inside $(( ))
  # evaluates as unary-minus and silently produces a 1969 window -> false exit 5.
  e_s="$(date -u -d "$EARLIEST" +%s 2>/dev/null)" || repoll 'earliest-unparseable'
  [[ "$e_s" =~ ^[0-9]+$ ]] || repoll 'earliest-unparseable'
  win_start="$(date -u -d "@$(( e_s - 2419200 ))" +%Y-%m-%dT%H:%M:%SZ)"
  n="$(count_cancelled "${win_start%%T*}")" || gh_fail
  [ -n "$n" ] || gh_fail
  if [ "$n" -ge 2 ]; then
    printf 'REEVAL verdict=waste-appeared cancelled=%s window_start=%s\n' "$n" "$win_start"
    exit 5
  fi
  printf 'REEVAL verdict=decline-hold cancelled=%s window_start=%s\n' "$n" "$win_start"
  exit 0
fi

# ---- value==1: post-flip soak ----

# FLIP_MERGED: explicit env override, else anchored -G pickaxe — fires on any
# value edit on the assignment line; # comment lines cannot match (the anchor
# requires the token at column-0). Caveat: a `/* */`-interior assignment line
# WOULD match — the tf currently has none; a comment-only edit there would move
# FLIP_MERGED forward into repoll (conservative direction).
FLIP_MERGED="${SOLEUR_FT_FLIP_MERGED:-}"
if [ -z "$FLIP_MERGED" ]; then
  FLIP_MERGED="$(cd "$REPO_ROOT" && git log -1 --first-parent --format=%cI \
    -G'^[[:space:]]*max_entries_to_build[[:space:]]*=[[:space:]]*[0-9]+' \
    -- infra/github/ruleset-ci-required.tf 2>/dev/null)" \
    || repoll 'flip-merged-underivable'
fi
[ -n "$FLIP_MERGED" ] || repoll 'flip-merged-underivable'
flip_s="$(date -u -d "$FLIP_MERGED" +%s 2>/dev/null)" || repoll 'flip-merged-unparseable'
[ -n "$flip_s" ] || repoll 'flip-merged-unparseable'

# TRACKER: explicit env override, else the watch's own find-or-file (exact title
# + github-actions author; a same-title issue filed by anyone else is never adopted).
TRACKER="${SOLEUR_FT_TRACKER:-}"
if [ -z "$TRACKER" ]; then
  ilist="$(gh issue list --repo jikig-ai/soleur --state open \
      --search "in:title \"$TRACKER_TITLE\"" --limit 20 --json number,title,author 2>/dev/null)" \
    || gh_fail
  TRACKER="$(printf '%s' "$ilist" | jq -r --arg t "$TRACKER_TITLE" '
      def bot: . == "github-actions" or . == "app/github-actions" or . == "github-actions[bot]";
      [.[] | select(.title == $t and ((.author.login // "") | bot)) | .number] | sort | .[0] // empty' 2>/dev/null)"
  [ -n "$TRACKER" ] || repoll 'tracker-not-found'
fi

body="$(gh issue view "$TRACKER" --repo jikig-ai/soleur --json body --jq .body 2>/dev/null)" || gh_fail
[ -n "$body" ] || repoll 'tracker-body-empty'

# Postdate check: the body's `Report refreshed:` must postdate the flip merge —
# the row carries a rolling last-30-green sample, so a fresh report after the
# flip is post-flip-dominated; a stale report is a pre-flip sample -> repoll.
# The charset keeps Z and . so the emitted %FT%TZ parses cleanly; a zone-less
# or absent Z degrades to day granularity, never to a wrong verdict.
refreshed="$(printf '%s\n' "$body" | grep -oE 'Report refreshed: [0-9T:.+Z-]+' | head -1 | grep -oE '[0-9]{4}[^ ]+$' || true)"
[ -n "$refreshed" ] || repoll 'report-refreshed-missing'
ref_s="$(date -u -d "$refreshed" +%s 2>/dev/null)" || repoll 'report-refreshed-unparseable'
if [ "$ref_s" -le "$flip_s" ]; then
  repoll "tracker-report-pre-flip refreshed=$refreshed"
fi

# Real schema: | check | surface | n | p50 (s) | p90 (s) | p90 dur (s) | bound | goal |
row="$(printf '%s\n' "$body" | grep -E '^\|[[:space:]]*test[[:space:]]*\|[[:space:]]*merge_group' | head -1)"
[ -n "$row" ] || repoll 'tracker-row-missing'
p50_s="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$5); print $5}')"
p90_s="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$6); print $6}')"
# Bounded-digit check: a huge field overflows shell arithmetic negative and the
# -gt compare would fail OPEN to keep-flip; a `—` zero-sample row repolls here.
[[ "$p50_s" =~ ^[0-9]{1,9}$ ]] || repoll 'p50-unparseable'
[[ "$p90_s" =~ ^[0-9]{1,9}$ ]] || repoll 'p90-unparseable'
floor_s=$(( 10#$P50_FLOOR * 60 ))

# Tail regression: p50 > floor*1.2 OR p90 > floor*2.5 (p90 naturally ~1.4-2x p50).
if [ "$(( 10#$p50_s * 10 ))" -gt "$(( floor_s * 12 ))" ] || [ "$(( 10#$p90_s * 10 ))" -gt "$(( floor_s * 25 ))" ]; then
  printf 'REEVAL verdict=revert-warranted p50=%ss p90=%ss floor=%ss tracker=%s\n' "$p50_s" "$p90_s" "$floor_s" "$TRACKER"
  exit 5
fi

# Churn signal: if cancelled merge_group runs REAPPEAR at >=2 since the flip,
# serialization made it worse — the same cheap query the decline arm runs.
# Empty output is a read failure like the decline arm's, never a silent zero.
churn_since="${FLIP_MERGED%%T*}"
cn="$(count_cancelled "$churn_since")" || gh_fail
[ -n "$cn" ] || gh_fail
if [ "$cn" -ge 2 ]; then
  printf 'REEVAL verdict=revert-warranted churn=%s p50=%ss p90=%ss floor=%ss tracker=%s\n' "$cn" "$p50_s" "$p90_s" "$floor_s" "$TRACKER"
  exit 5
fi
printf 'REEVAL verdict=keep-flip p50=%ss p90=%ss floor=%ss churn=%s tracker=%s refreshed=%s\n' \
  "$p50_s" "$p90_s" "$floor_s" "$cn" "$TRACKER" "$refreshed"
exit 0
