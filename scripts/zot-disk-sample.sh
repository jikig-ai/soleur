#!/usr/bin/env bash
# zot-disk-sample.sh — pull the newest SOLEUR_ZOT_DISK emission out of Better Stack and print
# its fields as key=value lines (#7278).
#
# WHY THIS IS A SCRIPT. registry-zot-inventory.yml carried this logic TWICE — once for the
# start sample and once for the end sample — as ~110 near-identical lines of workflow YAML,
# including a byte-identical `field()` awk splitter and a byte-identical envelope anchor. That
# is the arrangement the same workflow argues against for its pass condition: "a pass condition
# written into workflow YAML is one no test can reach." The two copies had already drifted —
# they used a WEAKER decoder than the two sibling scripts (`jq -r '.raw | fromjson | .message'`
# with no `-R`, no `fromjson?` and no `// empty`), so a single non-JSON row in a multiplexed
# source aborted the whole decode instead of being skipped.
#
# SEVERITY IS THE CALLER'S CHOICE, NOT THIS SCRIPT'S. That is the one real difference between
# the two call sites: a missing START sample is fatal (there is no baseline to compute delta_gb
# against), while a missing END sample only costs the straddle check. So this script reports
# WHAT HAPPENED via distinct exit codes and lets each caller decide what it means. Collapsing
# them into one "failed" would reproduce the defect this lever exists to avoid — a caller that
# cannot tell "could not measure" from "measured, and the answer is absent".
#
# EXIT CONTRACT:
#   0  sampled       fields printed on stdout
#   2  query_failed  betterstack-query.sh could not answer (transport). NOT evidence of absence.
#   3  no_row        the query answered and NO row matched the emission envelope. This IS a
#                    measured absence of the heartbeat — a fact about the host, not the query.
#   4  decode_failed a row matched the envelope but its double-encoded payload would not decode.
#   64 usage
#
# STDOUT (exit 0 only), one key=value per line:
#   fs_size_gb= pcent= boot_id= zot_restarts= sample_at= sample_age_s=
# A field the marker did not carry is printed EMPTY rather than omitted, so a consumer reading
# with a fixed key set cannot silently skip one.
#
# ENV: BETTERSTACK_QUERY_HOST / _USERNAME / _PASSWORD (read by betterstack-query.sh).
set -uo pipefail

SINCE="30m"
LIMIT="50"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    *) printf 'zot-disk-sample: unknown argument %s\n' "$1" >&2; exit 64 ;;
  esac
done
[[ -n "$SINCE" && -n "$LIMIT" ]] || { printf 'zot-disk-sample: --since and --limit need values.\n' >&2; exit 64; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY="${ZOT_DISK_SAMPLE_QUERY_CMD:-bash ${ROOT}/scripts/betterstack-query.sh}"

rc=0
# Word-splitting on $QUERY is deliberate: it is a command word plus flags, and the test seam
# supplies its own. Not user input on any production path.
# shellcheck disable=SC2086
ROWS="$($QUERY --no-archive --since "$SINCE" --grep SOLEUR_ZOT_DISK --limit "$LIMIT")" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  printf 'zot-disk-sample: betterstack-query.sh exited %s (query_rc=%s). This is a transport failure, NOT evidence that the heartbeat is absent.\n' "$rc" "$rc" >&2
  exit 2
fi

# ENVELOPE ANCHOR, not a bare substring. --grep compiles to an unanchored
# `raw LIKE '%SOLEUR_ZOT_DISK%'` over a source EVERY host multiplexes into, and GitHub webhook
# payloads quoting this marker name have contaminated exactly this query before (measured
# 2026-07-15 on the sibling SOLEUR_PRIVATE_NIC stream: 3 rows returned, 0 of them emissions).
# A genuine host emission POSTs {"message":"SOLEUR_ZOT_DISK …"}, so its stored `raw` STARTS
# with that prefix; a Vector-shipped journald row's raw starts with {"PRIORITY":… and can
# never match. Rows come back oldest-first, so `tail -n 1` is the newest.
NEWEST="$(printf '%s\n' "$ROWS" \
  | { grep -F '"raw":"{\"message\":\"SOLEUR_ZOT_DISK ' || true; } | tail -n 1)"
if [[ -z "$NEWEST" ]]; then
  printf 'zot-disk-sample: the query answered but no row matched the emission envelope (rows_matched=0). The heartbeat is not landing; this is a MEASURED absence, not a query failure.\n' >&2
  exit 3
fi

# DECODE BEFORE MATCHING. Better Stack's `raw` column is DOUBLE-encoded JSON, so a bare grep
# against it silently returns nothing. `-R` + `fromjson?` + `// empty` matches the decoder in
# zot-inventory-assert-marker.sh and zot-inventory-marker-7278.sh: a mixed source carries rows
# this has no business reading, and a hard `fromjson` aborts the whole pipeline on the first
# one instead of skipping it.
decode_rc=0
LINE="$(printf '%s\n' "$NEWEST" | jq -R -r 'fromjson? | .raw // empty' \
        | jq -R -r 'fromjson? | .message // empty')" || decode_rc=$?
DT="$(printf '%s\n' "$NEWEST" | jq -R -r 'fromjson? | .dt // empty')" || decode_rc=$?
if [[ "$decode_rc" -ne 0 || -z "$LINE" ]]; then
  printf 'zot-disk-sample: a row matched the envelope but its double-encoded payload would not decode (decode_rc=%s). This is a decode failure on a row that WAS returned, not an absence of the heartbeat.\n' "$decode_rc" >&2
  exit 4
fi

# `zot_last_err` is the marker's LAST field and the only one that may carry spaces, so a
# whitespace split reaches every field ahead of it intact.
field() {
  printf '%s\n' "$LINE" | tr ' ' '\n' | awk -F= -v k="$1" '$1==k {print $2; exit}'
}

SAMPLE_EPOCH=0
SAMPLE_EPOCH="$(date -u -d "${DT} UTC" +%s 2>/dev/null)" || SAMPLE_EPOCH=0
NOW_EPOCH="$(date -u +%s)"
AGE_S=-1
if [[ "$SAMPLE_EPOCH" -gt 0 ]]; then AGE_S=$(( NOW_EPOCH - SAMPLE_EPOCH )); fi

printf 'fs_size_gb=%s\n'   "$(field fs_size_gb)"
printf 'pcent=%s\n'        "$(field pcent)"
printf 'boot_id=%s\n'      "$(field boot_id)"
printf 'zot_restarts=%s\n' "$(field zot_restarts)"
printf 'sample_at=%s\n'    "${DT// /T}"
printf 'sample_age_s=%s\n' "$AGE_S"
