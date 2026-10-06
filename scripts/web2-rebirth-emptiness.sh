#!/usr/bin/env bash
# Emptiness evidence for the single-use web-2 volume rebirth (#9372): is the plaintext /mnt/data volume of
# soleur-web-2 provably EMPTY before anything deletes it? Read from Better Stack host_metrics (Vector's
# `filesystem` collector, mountpoint /mnt/data; apps/web-platform/infra/vector.toml [sources.host_metrics.filesystem])
# over the last 7 days. No SSH: the volume's own byte counters are the evidence.
#
# ROW SHAPE (CONFIRMED 2026-10-06). Better Stack stores the bare Vector metric in `raw`, NOT the flat host_name /
# source_kind / metric.name / metric.value record that [transforms.tag_metrics] is written to produce:
#   {"name":"filesystem_used_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb",
#    "filesystem":"ext4","host":"soleur-web-2","mountpoint":"/mnt/data"},"timestamp":...,"gauge":{"value":...}}
# so the query reads tags.host, namespace, tags.mountpoint, name and gauge.value. The first live plan-only run (2026-10-06)
# read the flat paths, matched zero rows and went RED used_bytes_absent_or_host_dark: that is the defect this shape note closes.
# Read-only control against the stored rows, same day (soleur-web-2, /mnt/data, one device /dev/sdb ext4, 7 days):
#   filesystem_used_bytes  n=2019 hours=169 newest_age_s=169 min=15556608 max=16027648 (spread 471040)
#   filesystem_total_bytes n=2019 hours=169 min=max=20957446144
# which satisfies every threshold below. Limits of that control: it ran under Doppler read credentials while the workflow
# uses the repo secrets BETTERSTACK_QUERY_*, so the first plan-only dispatch is the credential-parity check; and its newest row
# (169 s) is younger than the ~40-minute hot window, so the hot arm carries the same shape (inference, not a separate probe).
# Running this script under the Doppler config soleur/prd_terraform re-runs the control: it prints the used series' hours, newest
# age, min, max and spread (not n or the total series; runbook web2-luks-rebirth-9372.md).
# `tags.host` is Vector's OS hostname, where the old host_name was a Terraform-rendered constant: equal forgery resistance (any
# holder of the shared ingest token can write either) and weaker against hostname drift on a re-imaged host. Evidence is keyed by
# hostname plus mountpoint, NOT by the pinned volume id: anything mounted at /mnt/data on a host with that hostname that reports
# one consistent device passes (decision-challenges item 7). RED used_bytes_absent_or_host_dark therefore also means "the stored
# row shape changed" (if the shipper ever starts flattening, tags.host moves to a top-level host), "more than one distinct device
# reported /mnt/data in the window", or "tags.device is missing, empty or not a string on some row": the HAVING below drops that
# metric's whole group, so it reads RED used_bytes_absent_or_host_dark (used series) or RED total_bytes_absent (total series).
# `AND dt <= now()` keeps a future-dated row from pinning the newest age below zero. The SQL and the test fixtures change together.
#
# PASS needs ALL of, from one aggregate over 7 days (hot AND archive arm):
#   - filesystem_used_bytes: at least 160 of 168 distinct hours covered (a gappy series is not evidence),
#     the newest row at most 1800 s old (a dark host is not evidence), a MINIMUM above zero (a missing `value` path
#     reads as 0 in ClickHouse, so zero is "field absent", never "empty"), a maximum at most 1 GiB (a COARSE ceiling:
#     an empty ext4 volume holds only its own metadata, a populated one holds user data, and 1 GiB is deliberately far
#     above the observed level, see ROW SHAPE), and a spread (maximum minus minimum) of at most 64 MiB: a volume that took
#     large writes during the 7 days moves, an idle one does not. Neither bound proves emptiness: a flat pre-existing amount
#     or an in-window write well under 64 MiB passes both (decision-challenges item 1). The printed min/max are read from a PLAN-ONLY run: the
#     `web-platform-infra-apply` environment approval is a job-level gate, so it comes BEFORE this step runs, and an apply
#     dispatch's PASS flows into the delete in the same approved job with no human reading the numbers first. The observed
#     level (about 16 MB) is the volume's own reading, not an independent empty reference: an ext4 volume is never
#     byte-empty, and whatever deploys seed under /mnt/data sits in that figure. It is far below the 1 GiB ceiling.
#   - W2R_DETACHED=1 (heal:detach_done only: the volume was detached by an earlier run of this workflow that had already
#     proven it empty, and a detached device stops reporting): freshness is not required and coverage drops to 24 hours;
#     the zero floor, the ceiling, the spread and the volume-size window still apply.
#   - filesystem_total_bytes: every sample between 15e9 and 21.5e9 bytes, which is the 20 GB volume and not the
#     root disk, so a mis-mounted /mnt/data cannot pass as "small".
# Zero rows is a named RED ("field absent or web-2 dark"), never a pass. A transport failure is rc 2 (no verdict).
#
# STILL UNCONFIRMED: the vector.toml `devices.excludes = ["loop*", "dm-*"]` is matched against the device NAME; whether a
# LUKS mapper device (/dev/mapper/workspaces) matches `dm-*` is unverified, so this evidence is NOT claimed to vanish after LUKS.
# An absent field still fails closed (zero rows, or a value that reads as 0, is RED and never PASS).
#
# Exit: 0 PASS, 1 RED (a verdict), 2 the read did not answer (not a verdict), 3 the shared helper could not load.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

_w2r_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/web2-luks-rows.sh
source "${_w2r_dir}/lib/web2-luks-rows.sh" || { echo "web2-rebirth-emptiness: the shared rows helper could not be loaded"; exit 3; }

W2R_LOOKBACK_DAYS=7
W2R_MIN_HOURS=160
W2R_MAX_NEWEST_AGE_S=1800
W2R_MAX_USED_BYTES=1073741824
W2R_MAX_SPREAD_BYTES=67108864
W2R_DETACHED_MIN_HOURS=24
W2R_TOTAL_MIN_BYTES=15000000000
W2R_TOTAL_MAX_BYTES=21500000000

# One aggregate row per metric name. age is computed by the SERVER (dateDiff against now()); no output alias
# reuses a source column name (`dt`, `raw`). The host predicate is an explicit AND in the OUTER WHERE so it binds
# both the hot arm and the archive arm.
w2r_sql_emptiness() {
  printf '%s' "SELECT JSONExtractString(raw,'name') AS metric_name, count() AS n, countDistinct(toStartOfHour(dt)) AS hours, min(JSONExtractFloat(raw,'gauge','value')) AS vmin, max(JSONExtractFloat(raw,'gauge','value')) AS vmax, min(dateDiff('second', dt, now())) AS newest_age_s
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${W2R_LOOKBACK_DAYS} DAY AND dt <= now()
  AND JSONExtractString(raw,'tags','host') = '${W2L_HOST_NAME}'
  AND JSONExtractString(raw,'namespace') = 'host'
  AND JSONExtractString(raw,'tags','mountpoint') = '/mnt/data'
  AND JSONExtractString(raw,'name') IN ('filesystem_used_bytes','filesystem_total_bytes')
GROUP BY metric_name
HAVING uniqExact(JSONExtractString(raw,'tags','device')) = 1 AND min(length(JSONExtractString(raw,'tags','device'))) > 0
FORMAT JSONEachRow"
}

# w2r_emptiness_verdict <body.jsonl> — prints PASS ... or RED reason=...
w2r_emptiness_verdict() {
  local f="$1" out
  if ! jq -e -s 'all(.[]; type == "object")' "$f" >/dev/null 2>&1; then printf 'RED reason=emptiness_body_unparseable\n'; return 0; fi
  local detached=false minh="$W2R_MIN_HOURS"
  if [[ "${W2R_DETACHED:-0}" == 1 ]]; then detached=true; minh="$W2R_DETACHED_MIN_HOURS"; fi
  out="$(jq -r -s --argjson minh "$minh" --argjson maxage "$W2R_MAX_NEWEST_AGE_S" --argjson maxused "$W2R_MAX_USED_BYTES" --argjson maxspread "$W2R_MAX_SPREAD_BYTES" \
    --argjson detached "$detached" --argjson tmin "$W2R_TOTAL_MIN_BYTES" --argjson tmax "$W2R_TOTAL_MAX_BYTES" '
    def num: if type == "number" then . elif type == "string" and test("^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$") then tonumber else null end;
    (map({(.metric_name): .}) | add // {}) as $m
    | ($m.filesystem_used_bytes) as $u
    | ($m.filesystem_total_bytes) as $t
    | if $u == null then "RED reason=used_bytes_absent_or_host_dark"
      elif ($u.hours | num) == null or ($u.newest_age_s | num) == null or ($u.vmax | num) == null then "RED reason=used_bytes_malformed"
      elif ($u.hours | num) < $minh then "RED reason=coverage_gap hours=\($u.hours | num)"
      elif ($detached | not) and ($u.newest_age_s | num) > $maxage then "RED reason=stale newest_age_s=\($u.newest_age_s | num)"
      elif ($u.vmin | num) == null or ($u.vmin | num) <= 0 then "RED reason=used_bytes_zero_or_missing"
      elif ($u.vmax | num) > $maxused then "RED reason=not_empty max_used_bytes=\($u.vmax | num)"
      elif (($u.vmax | num) - ($u.vmin | num)) > $maxspread then "RED reason=not_flat spread_bytes=\(($u.vmax | num) - ($u.vmin | num))"
      elif $t == null then "RED reason=total_bytes_absent"
      elif ($t.vmin | num) == null or ($t.vmax | num) == null then "RED reason=total_bytes_malformed"
      elif ($t.vmin | num) < $tmin or ($t.vmax | num) > $tmax then "RED reason=not_the_20gb_volume total_min=\($t.vmin | num) total_max=\($t.vmax | num)"
      else "PASS hours=\($u.hours | num) newest_age_s=\($u.newest_age_s | num) max_used_bytes=\($u.vmax | num) min_used_bytes=\($u.vmin | num) ceiling_bytes=\($maxused) spread_bytes=\(($u.vmax | num) - ($u.vmin | num)) detached=\($detached)" end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=emptiness_judge_error"
  printf '%s\n' "$out"
}

w2r_main() {
  local tmp verdict
  tmp="$(mktemp -d)" || { echo "web2-rebirth-emptiness: mktemp failed"; return 2; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  if ! w2l_query "$(w2r_sql_emptiness)" "$tmp/body.jsonl"; then
    echo "web2-rebirth-emptiness: the Better Stack read did not answer. A read fault is not a verdict."
    return 2
  fi
  verdict="$(w2r_emptiness_verdict "$tmp/body.jsonl")"
  printf '%s\n' "$verdict"
  [[ "$verdict" == PASS* ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  w2r_main; rc=$?
  if [[ "$rc" -eq 2 ]]; then exit 2; fi
  exit "$rc"
fi
