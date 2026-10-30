#!/usr/bin/env bash
# #11602 — the inngest host's host_metrics collectors are trimmed on main
# (`collectors = ["memory", "filesystem"]`, `scrape_interval_secs = 900`,
# apps/web-platform/infra/vector.toml) and the pinned bootstrap image already
# carries the trim, but the live host is birth-frozen: its vector.toml is only
# re-read at birth via the baked image, so the trim reaches it ONLY inside a
# later image through `apply_target=inngest-host-replace`. This probe is the
# issue's measured close condition — the issue's own acceptance query, run
# off-box:
#
#   GROUP BY tags.collector over the trailing window (default 24h),
#   rows isolated on tags.host='soleur-inngest'
#
# Metric rows arrive in NATIVE Vector shape — `tags.host`/`tags.collector`/
# `name`/`gauge.value` are the only fields (top-level `host`, `host_name`,
# `SYSLOG_IDENTIFIER`, `source_kind` are all ABSENT; the tag_metrics remap is a
# measured no-op on metric events). `tags.host` is therefore the ONLY
# discriminator the metric shape offers — and it is exactly the field the
# issue's acceptance query groups by. Do not add a host_name check here:
# metric rows do not carry one, and requiring it would keep this probe
# TRANSIENT forever on a healthy post-replace host.
#
#   exit 0 = PASS        the observed collector set is exactly
#                        {memory, filesystem} with >=1 row of each — positive
#                        liveness AND trim delivered; #11602 close evidence.
#   exit 1 = FAIL        deliberately unreachable — until the replace lands
#                        this probe's only honest states are PASS and
#                        TRANSIENT; a FAIL that can never discriminate is a
#                        sweeper misfire.
#   exit 2 = TRANSIENT   reasons: credentials_unprovisioned | query_failed |
#                        selector_failed | query_tool_missing | no_host_metrics
#                        | untrimmed. `untrimmed` covers BOTH a superset (the
#                        pre-replace state) and a partial set — the message
#                        names the observed collectors.
#   exit 78              refused to run under xtrace with a live credential.
#
# TRAILING-WINDOW CONTAMINATION NOTE: for <=24h post-replace, residual
# old-generation rows keep the set a superset → TRANSIENT `untrimmed`. That is
# the fail-safe direction and self-clears as the window slides; do not
# compensate by shrinking the default window.
#
# THE READ IS MODE-1 RAW SQL — the GROUP BY runs server-side. A mode-2
# --limit read returns the NEWEST N rows, and on a ~17.8k-row/day untrimmed
# host a 500-row tail covers ~40 minutes: a collector that emits sparsely
# could fall outside it and the set would read as "trimmed" while cpu/disk/load
# still ship. Server-side aggregation covers the whole window and returns ~5
# rows. The $BS_TABLE/$BS_TABLE_S3 tokens are substituted by
# betterstack-query.sh itself.
#
# TRACKER: #11602 — PASS requires >=1 row of EACH collector (positive
# liveness: a host dark for the whole window cannot satisfy it) AND set
# equality with {memory, filesystem}. Anything else is TRANSIENT, never FAIL.
#
# Tracker directive (goes in the issue body; a deferred operator step — the
# probe is inert until enrolled):
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-hostmetrics-trim-11602.sh earliest=2026-10-30T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# Credential posture: BETTERSTACK_QUERY_HOST / BETTERSTACK_QUERY_USERNAME /
# BETTERSTACK_QUERY_PASSWORD, already wired into the sweeper env. No
# `${VAR:?}` — vault provision order is not guaranteed and the lint bans the
# form. Reader stderr is never echoed: it can carry the username and the
# query host.
#
# RETIREMENT: when #11602 closes, remove —
#   - this probe and scripts/followthroughs/inngest-hostmetrics-trim-11602.test.sh
#   - its run_suite line in scripts/test-all.sh (the
#     "scripts/followthroughs/inngest-hostmetrics-trim-11602" registration)
#   - the `<!-- soleur:followthrough ... -->` directive on issue #11602
#     (or the `follow-through` label if the directive stays)
#   - the #11602 counterpart mention in the runbook section
#     knowledge-base/engineering/operations/runbooks/inngest-server.md
#     ("Post-replace: the boot-trace allowlist (#7596)")
set -uo pipefail

# xtrace refusal (the probes' credential discipline, #7797): a traced run
# would print the Better Stack credentials to the log.
case "$-" in
  *x*)                                                    # [mut:xtrace]
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="$SCRIPT_DIR/../betterstack-query.sh"               # [mut:query-path]
INNGEST_HOST='soleur-inngest'                                   # [mut:host]
WINDOW="${TRIM_WINDOW:-${SOLEUR_FT_WINDOW:-24h}}"         # [mut:window]

# --- credentials: absent = TRANSIENT, never ${VAR:?} ------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then                                        # [mut:cred]
  printf 'TRANSIENT: reason=credentials_unprovisioned — missing:%s. The sweeper env or doppler -c prd_terraform provides these; retry once provisioned.\n' \
    "$missing" >&2
  exit 2
fi
[[ -x "$QUERY" || -f "$QUERY" ]] || {
  printf 'TRANSIENT: reason=query_tool_missing — %s not found.\n' "$QUERY" >&2
  exit 2
}

# The trailing window maps to a ClickHouse INTERVAL. Accept only the relative
# forms the sweeper passes (Nh/Nm/Nd); anything else is a malformed request —
# TRANSIENT query_failed, never a silent default (a silently shortened window
# could read "trimmed" on stale coverage). This check sits AFTER the
# credential and reader gates — a provisioning fault must never lose to a
# window-parse error (sibling ordering).
if [[ "$WINDOW" =~ ^([0-9]+)([hmd])$ ]]; then
  case "${BASH_REMATCH[2]}" in
    h) INTERVAL="${BASH_REMATCH[1]} HOUR" ;;
    m) INTERVAL="${BASH_REMATCH[1]} MINUTE" ;;
    d) INTERVAL="${BASH_REMATCH[1]} DAY" ;;
  esac
else
  printf 'TRANSIENT: reason=query_failed detail=window_unparseable window=%s — expected <N>h|<N>m|<N>d; no verdict formed this pass.\n' "$WINDOW" >&2
  exit 2
fi

# --- the read: one server-side GROUP BY over hot + archive ------------------
# The tags.host literal sits in a SQL literal position; INNGEST_HOST is a baked
# constant (no env seam), so no quoting layer is needed. The `tags.host`
# isolation happens WHERE-side — noise rows (stunnel4/doppler journald,
# non-metric shapes) never reach the verdict.
SQL="SELECT c, n FROM (SELECT JSONExtractString(raw, 'tags', 'collector') AS c, count() AS n FROM (SELECT raw FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL ${INTERVAL} UNION ALL SELECT raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND (dt >= now() - INTERVAL ${INTERVAL})) WHERE JSONExtractString(raw, 'tags', 'host') = '${INNGEST_HOST}' GROUP BY c) WHERE c != '' ORDER BY c FORMAT JSONEachRow"

qrc=0
rows="$("$QUERY" "$SQL" 2>/dev/null)" || qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  printf 'TRANSIENT: reason=query_failed rc=%s — the Better Stack read failed; no verdict can be formed this pass.\n' "$qrc" >&2
  exit 2
fi

# Post-decode isolation: every NON-BLANK output line must be JSON (a truncated
# or exception tail means the read is untrustworthy → selector_failed); a line
# that decodes to an object without the {c:string, n:number} aggregate shape is
# a foreign row and is ignored — the verdict reads .c, never row shape. The
# .c value is additionally charset-gated to ^[a-z_]+$ BEFORE it can enter the
# observed set: a forged `collector:"filesystem memory"` row would otherwise
# satisfy the exact-set string compare on its own, and the gated charset is
# also what makes `observed=` safe to echo into sweeper output (the comment
# channel). The per-collector row floor (n >= 1, positive liveness) is the
# awk arm — a zero-count row is not evidence of a shipping collector.
jrc=0
cols="$(printf '%s\n' "$rows" \
  | jq -R -r '
      select(length > 0)
      | (fromjson? // "BADLINE") as $d
      | if $d == "BADLINE" then "BADLINE\t-"
        elif ($d | type) == "object" and ($d.c? | type) == "string" and ($d.c | test("^[a-z_]+$")) and ($d.n? | type) == "number" and $d.c != "" then "\($d.c)\t\($d.n)" # [mut:charset]
        else "FOREIGN\t-" end' 2>/dev/null \
  | awk -F'\t' '$1 == "BADLINE" || $1 == "FOREIGN" {print $1; next} $2+0 >= 1 {print $0; next}')" || jrc=$?  # [mut:nfloor]
if [[ "$jrc" -ne 0 ]]; then
  printf 'TRANSIENT: reason=selector_failed rc=%s — jq failed to decode; the aggregate row shape may have changed.\n' "$jrc" >&2
  exit 2
fi

if printf '%s\n' "$cols" | grep -qx 'BADLINE'; then
  printf 'TRANSIENT: reason=selector_failed — a non-JSON line rode in on the read (truncated body or exception tail); the window was not trusted.\n' >&2
  exit 2
fi
observed="$(printf '%s\n' "$cols" | grep -vxE 'FOREIGN|BADLINE' | cut -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"
if [[ -z "$observed" ]]; then
  if [[ -z "$(printf '%s' "$rows" | tr -d '[:space:]')" ]]; then
    printf 'TRANSIENT: reason=no_host_metrics — zero host_metrics rows for tags.host=%s in the trailing %s. Expected until the next inngest-host-replace lands; also the honest state if the host or its Vector leg is dark.\n' \
      "$INNGEST_HOST" "$WINDOW" >&2
  else
    printf 'TRANSIENT: reason=selector_failed — the read returned rows but none matched the {c:string, n:number} aggregate shape under the collector charset gate; the query contract drifted.\n' >&2
  fi
  exit 2
fi

# PASS iff the observed collector set is exactly {memory, filesystem} — sorted,
# space-joined, compared as one string so a missing OR extra member fails the
# same way.
WANT='filesystem memory'                                       # [mut:set]
if [[ "$observed" == "$WANT" ]]; then
  # The per-collector counts come from $cols — the already-decoded,
  # already-typed TSV — never a second pass over raw row content: nothing
  # unvalidated may echo verbatim into the PASS the sweeper posts.
  n_mem="$(printf '%s\n' "$cols" | awk -F'\t' '$1 == "memory" {print $2; exit}')"
  n_fs="$(printf '%s\n' "$cols" | awk -F'\t' '$1 == "filesystem" {print $2; exit}')"
  printf 'PASS: trailing %s over tags.host=%s shows collectors exactly {memory, filesystem} (memory rows=%s filesystem rows=%s) — the host_metrics trim is live on the inngest host; #11602 close evidence.\n' \
    "$WINDOW" "$INNGEST_HOST" "${n_mem:-?}" "${n_fs:-?}"
  exit 0
fi

printf 'TRANSIENT: reason=untrimmed observed=%s — the trailing %s collector set for tags.host=%s is not exactly {memory, filesystem}. Pre-replace this is the expected state (the full collector set ships); post-replace it means the trim did not arrive or residual old-generation rows still fill the window (self-clears within %s).\n' \
  "$observed" "$WINDOW" "$INNGEST_HOST" "$WINDOW" >&2
exit 2
