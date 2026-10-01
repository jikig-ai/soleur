#!/usr/bin/env bash
# Follow-through verification for #8611 — the 72-hour rollback trigger for the streaming change.
#
# #8611 turned on `serve({ streaming: "force" })` for /api/inngest (ADR-243) and put a single-flight
# guard in front of every cron Claude spawn. The failure it must not introduce is a paid Claude call
# that runs twice: a founder's BYOK leader-loop turn billed twice, or a cron run that spawns Claude
# twice under one run id. This probe reads the SOLEUR_CLAUDE_COST markers emitted AFTER the #8611
# deploy and fails on any of:
#
#   * a leader-loop marker with attempt > 0 (the `turn-${n}-claude` step re-ran after it billed);
#   * two leader-loop markers for one (conversation id, turn) — conversation ids are minted per
#     spawn (uuidv5 of the action send id), so a repeat is the same turn billed twice;
#   * two cron markers for one run id (ids equal to the cron name are the no-runid fallback, which
#     repeats across runs by construction, and are excluded).
#
# A FAIL is the rollback signal named in ADR-243: remove `streaming` from app/api/inngest/route.ts,
# and notify and refund any founder whose key was billed twice.
#
# Three shapes it avoids:
#  1. ECHO. Aggregation is field-isolated on message.component = 'claude-cost' and message.source,
#     so a GitHub webhook payload quoting the marker name (this PR's own body) cannot count.
#  2. PRE-DEPLOY ROWS. The #8611 bug produced duplicate cron markers; counting them would fail this
#     check on the bug it fixed. The window starts at the #8611 squash commit on main plus 45 min
#     for the release to deploy, derived from git history (the sweeper checks out full history).
#  3. DARK CHANNEL. Zero markers after the floor is "could not measure", never a clean zero.
#
# Exit semantics (sweep-followthroughs.sh rc→word map):
#   0 = PASS              (>=1 post-deploy leader-loop turn marker, no retries, no duplicates)
#   1 = FAIL              (a double-bill signal, or the marker channel is dark)
#   2 = NOT YET           (no post-deploy leader-loop turn marker yet, or a transient query error)
#   3 = CANNOT ESTABLISH  (credentials not injected, or the merge floor cannot be derived)
#
# Directive:
#   <!-- soleur:followthrough script=scripts/followthroughs/anthropic-double-bill-8611.sh earliest=<merge+72h> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
set -uo pipefail

# Refuse to run under xtrace with a live credential set (#7797): tracing prints expanded commands.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$REPO_ROOT" ]; then
  printf 'CANNOT ESTABLISH: could not resolve the repo root from %s\n' "${BASH_SOURCE[0]}" >&2
  exit 3
fi
QUERY_SH="${FT8611_QUERY_SH:-$REPO_ROOT/scripts/betterstack-query.sh}"
if [ ! -f "$QUERY_SH" ]; then
  printf 'NOT YET: betterstack-query.sh not found at %s\n' "$QUERY_SH" >&2
  exit 2
fi

numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Floor: the #8611 squash commit's commit time on the checked-out history, plus the deploy lag.
# FT8611_MERGE_EPOCH overrides it (tests; or a manual re-grade).
merge_s="${FT8611_MERGE_EPOCH:-}"
if [ -z "$merge_s" ]; then
  merge_s="$(git -C "$REPO_ROOT" log -1 --format=%ct -E --grep='\(#8611\)$' HEAD 2>/dev/null || true)"
fi
if ! numeric "$merge_s"; then
  printf 'CANNOT ESTABLISH: no commit whose subject ends "(#8611)" in this checkout — cannot place the post-deploy window.\n' >&2
  exit 3
fi
floor_s=$(( merge_s + 2700 ))

SRC="(SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"
QUERY="SELECT count() AS markers,
  countIf(s = 'leader-loop' AND t >= 0) AS leader_turns,
  countIf(s = 'leader-loop' AND a > 0) AS leader_retries,
  uniqExactIf((id, t), s = 'leader-loop' AND t >= 0) AS leader_keys,
  countIf(s LIKE 'cron:%' AND id != substring(s, 6)) AS cron_markers,
  uniqExactIf(id, s LIKE 'cron:%' AND id != substring(s, 6)) AS cron_ids
FROM (SELECT JSONExtractString(raw, 'message', 'source') AS s,
             JSONExtractString(raw, 'message', 'id') AS id,
             if(JSONHas(raw, 'message', 'turn'), JSONExtractInt(raw, 'message', 'turn'), -1) AS t,
             JSONExtractInt(raw, 'message', 'attempt') AS a
      FROM ${SRC}
      WHERE dt > toDateTime(${floor_s})
        AND raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%'
        AND JSONExtractString(raw, 'message', 'component') = 'claude-cost')
FORMAT JSONEachRow"

OUT="$(bash "$QUERY_SH" "$QUERY" 2>&1)"
rc=$?
if [ "$rc" -eq 3 ]; then
  printf 'CANNOT ESTABLISH: betterstack-query.sh could not query: %s\n' "${OUT:0:400}" >&2
  exit 3
fi
if [ "$rc" -ne 0 ]; then
  printf 'NOT YET: betterstack-query.sh exited %s: %s\n' "$rc" "${OUT:0:400}" >&2
  exit 2
fi

ROW="$(printf '%s\n' "$OUT" | jq -R -r 'fromjson? | select(type == "object" and has("markers"))
  | [.markers, .leader_turns, .leader_retries, .leader_keys, .cron_markers, .cron_ids]
  | map(tostring) | join(" ")' | head -1)"
read -r markers leader_turns leader_retries leader_keys cron_markers cron_ids <<<"$ROW"
for n in "${markers:-}" "${leader_turns:-}" "${leader_retries:-}" "${leader_keys:-}" "${cron_markers:-}" "${cron_ids:-}"; do
  if ! numeric "$n"; then
    printf 'NOT YET: unparseable query result: %s\n' "${OUT:0:400}" >&2
    exit 2
  fi
done

since="$(date -u -d "@${floor_s}" +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "epoch ${floor_s}")"
summary="markers=${markers} leader_turns=${leader_turns} leader_retries=${leader_retries} leader_keys=${leader_keys} cron_markers=${cron_markers} cron_ids=${cron_ids} since=${since}"

if [ "$markers" -eq 0 ]; then
  printf 'FAIL: 0 SOLEUR_CLAUDE_COST markers since %s — the cost channel is dark, so a double bill could not be seen. %s\n' "$since" "$summary" >&2
  exit 1
fi
if [ "$leader_retries" -gt 0 ] || [ "$leader_turns" -gt "$leader_keys" ] || [ "$cron_markers" -gt "$cron_ids" ]; then
  printf 'FAIL: double-bill signal after the #8611 deploy (rollback trigger, ADR-243). %s\n' "$summary" >&2
  exit 1
fi
if [ "$leader_turns" -eq 0 ]; then
  printf 'NOT YET: no post-deploy leader-loop turn marker yet, so the BYOK path is unexercised. %s\n' "$summary" >&2
  exit 2
fi
printf 'PASS: no retried or duplicated paid Claude call after the #8611 deploy. %s\n' "$summary"
exit 0
