#!/usr/bin/env bash
# Follow-through verification for #8743 — web-2 deploys aborted at plugin-mount
# seeding (`fchmodat2 .claude-plugin: operation not permitted`) from 2026-09-24
# 07:19 UTC until the fix, while every release run reported success (the /health
# check is LB-routed and only ever answered by web-1).
#
# WHAT IT VERIFIES. The fix replaces `docker cp soleur-plugin-seed:` (which
# untars CLIENT-SIDE as the deploy uid and cannot chmod/delete a uid-1001 tree)
# with a container-side `docker run --rm -u 0` seed in ci-deploy.sh. That makes
# the outcome gradeable — but only as a CONJUNCTION, per
# scripts/betterstack-assert-absence.sh's semantics: "zero bad rows" is
# meaningless until the channel is provably alive AND the fix provably ran:
#
#   (b) POSITIVE CONTROL — soleur-web-2 still ships ci-deploy/webhook journald
#       rows since SOLEUR_FT_EARLIEST. SYSLOG_IDENTIFIER=webhook ships via
#       Vector source 4 (exact tag set) at any priority; ci-deploy is the
#       `logger -t ci-deploy` tag. Zero of both = dark channel, never a clean
#       zero.
#   (c) POST-FIX MARKER — a row only the new path emits. `PLUGIN_SEED_PROBE`
#       (the seed container's in-surface emit, before mutation) OR a
#       Deploy-succeeded-class `ci-deploy` marker reachable only after the
#       seed + canary + prod swap succeed: `INNGEST_HEALTH_CHECK` /
#       `BWRAP_USERNS_SYSCTL_` / `Deploy succeeded`. Under the OLD script web-2
#       aborted at the seed EVERY time, so any of these post-earliest is proof a
#       deploy got past the seed. If none exists, the fix has not exercised the
#       host and there is nothing to grade.
#   (a) ABSENCE — zero `fchmodat2` rows on web-2 at/after the FIRST post-fix
#       marker. The fixed script contains no `docker cp soleur-plugin-seed`, so
#       a post-marker fchmodat2 is a genuine regression, exit 1.
#
# WINDOW NOTE. The scan starts at SOLEUR_FT_EARLIEST (the directive earliest,
# merge+2d). Pre-delivery fchmodat2 rows are EXPECTED inside the window — the
# old script kept running until the fixed ci-deploy.sh was delivered — which is
# why the absence floor is the first marker timestamp, not the window edge.
#
# HOST SCOPING. `JSONExtractString(raw,'host_name') = 'soleur-web-2'` — Vector
# renders @@HOST_NAME@@ per host (vector.toml:746-751; soleur-web-2's rows were
# measured under that value when the incident was found). `_MACHINE_ID` is not
# usable here: its value is unknowable off-box and mints fresh on -replace. If
# host_name ever regresses, the control arm reads 0 and the verdict is CANNOT
# ESTABLISH — never a false PASS.
#
# Exit semantics (sweep-followthroughs.sh rc→word map):
#   0 = PASS               control >=1 AND marker >=1 AND zero fchmodat2 rows
#                          at/after the first marker
#   1 = FAIL               >=1 fchmodat2 row on web-2 at/after the first post-fix
#                          marker — the abort path is still live after the fix
#   2 = NOT YET            no post-fix marker yet (the fix has not exercised
#                          web-2), earliest in the future, or a transient query
#                          error
#   3 = CANNOT ESTABLISH   credentials unset, earliest unset/malformed, the
#                          positive control reads 0 (channel dark / host_name
#                          moved), or the transport reports "nothing was
#                          queried" (rc 3)
#   78 = refused to run under xtrace with a live credential bound (#7797)
#
# Required env: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (declared in the
#   directive secrets= clause; already wired in
#   scheduled-followthrough-sweeper.yml), SOLEUR_FT_EARLIEST (the sweeper
#   forwards the directive's earliest=). Test seam: FT8743_QUERY_SH.
#
# Directive:
#   <!-- soleur:followthrough script=scripts/followthroughs/web2-plugin-seed-8743.sh earliest=<merge+2d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# RETIREMENT: when #8743 closes, delete this file and its .test.sh, drop its
# run_suite line in scripts/test-all.sh, and remove the directive from the
# issue body.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

# Refuse to run under xtrace with a live credential set (#7797): tracing prints
# expanded commands, and the password rides one.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

HOST_NAME='soleur-web-2'

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${FT8743_QUERY_SH:-$SCRIPT_DIR/../betterstack-query.sh}"
if [ ! -f "$QUERY" ]; then
  printf 'NOT YET: betterstack-query.sh not found at %s\n' "$QUERY" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'NOT YET: jq not on PATH — cannot decode the JSONEachRow result.\n' >&2
  exit 2
fi

numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ── EVIDENCE GATE ─────────────────────────────────────────────────────────────
# The sweeper forwards the directive earliest; no fallback — a missing clock
# would grade pre-delivery rows against a fix that had not shipped.
EARLIEST_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
if [[ -z "$EARLIEST" ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset — no evidence gate. The\n' >&2
  printf '                  #8743 directive must carry earliest=<ISO instant after the\n' >&2
  printf '                  fix merge (merge+2d per the plan).\n' >&2
  exit 3
fi
if ! [[ "$EARLIEST" =~ $EARLIEST_SHAPE ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST %s is not an ISO instant (YYYY-MM-DDTHH:MM:SSZ); refusing to grade.\n' "$EARLIEST" >&2
  exit 3
fi
EARLIEST_EPOCH="$(date -u -d "$EARLIEST" +%s 2>/dev/null)" || EARLIEST_EPOCH=""
if [[ -z "$EARLIEST_EPOCH" ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST %s does not parse as a date; refusing to grade.\n' "$EARLIEST" >&2
  exit 3
fi
NOW_EPOCH="$(date -u +%s)"
if (( EARLIEST_EPOCH > NOW_EPOCH )); then
  printf 'NOT YET: SOLEUR_FT_EARLIEST (%s) is in the future — no post-fix evidence can exist yet.\n' "$EARLIEST" >&2
  exit 2
fi
SINCE_SQL="$(date -u -d "@$EARLIEST_EPOCH" '+%Y-%m-%d %H:%M:%S')"

SRC="(SELECT dt, raw, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS sid FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS sid FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"

# The marker predicate: PLUGIN_SEED_PROBE (the new seed's own emit) OR a
# Deploy-succeeded-class logger row that is only reachable after the seed, canary
# and prod swap all succeeded — under the pre-fix script web-2 aborted at the
# seed every deploy, so none of these can exist before the fix.
MARKER_PRED="raw LIKE '%PLUGIN_SEED_PROBE%' OR raw LIKE '%INNGEST_HEALTH_CHECK%' OR raw LIKE '%BWRAP_USERNS_SYSCTL_%' OR raw LIKE '%Deploy succeeded%'"

SCAN_SQL="SELECT
  countIf(sid = 'ci-deploy' OR sid = 'webhook') AS control_rows,
  countIf(raw LIKE '%PLUGIN_SEED_PROBE%') AS probe_rows,
  countIf(raw LIKE '%INNGEST_HEALTH_CHECK%' OR raw LIKE '%BWRAP_USERNS_SYSCTL_%' OR raw LIKE '%Deploy succeeded%') AS deploy_ok_rows,
  countIf(raw LIKE '%fchmodat2%') AS fchmod_rows_total,
  minIf(dt, ${MARKER_PRED}) AS first_marker_dt,
  uniqExact(JSONExtractString(raw,'_MACHINE_ID')) AS machine_ids
FROM ${SRC}
WHERE dt > toDateTime('${SINCE_SQL}')
  AND JSONExtractString(raw,'host_name') = '${HOST_NAME}'
FORMAT JSONEachRow"

# run_one <sql> — prints the single result row on stdout and RETURNS the
# sweep-contract code (callers `|| rc=$?` — a bare `exit` here would die inside
# the command substitution and degrade every transport arm to rc of the
# assignment). A multi-line or unparseable body is NOT a zero count: JSONEachRow
# for these aggregate SELECTs is exactly one object, and a ClickHouse exception
# echoed after a count is a partial answer, not an answer.
run_one() {
  local sql="$1" out rc
  out="$(bash "$QUERY" "$sql" 2>&1)"; rc=$?
  if [[ "$rc" -eq 3 ]]; then
    printf 'CANNOT ESTABLISH: betterstack-query.sh could not query: %s\n' "${out:0:200}" >&2
    return 3
  fi
  if [[ "$rc" -ne 0 ]]; then
    printf 'NOT YET: betterstack-query.sh exited %s: %s\n' "$rc" "${out:0:200}" >&2
    return 2
  fi
  if grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' <<<"$out"; then
    printf 'NOT YET: the query response carries an error alongside the count: %s\n' "${out:0:200}" >&2
    return 2
  fi
  local nrows
  nrows="$(printf '%s\n' "$out" | jq -R -r 'fromjson? | select(type == "object") | .' | grep -c '{' || true)"
  if [[ "$nrows" != "1" ]]; then
    printf 'NOT YET: unparseable query result (%s row(s) decoded): %s\n' "$nrows" "${out:0:200}" >&2
    return 2
  fi
  printf '%s' "$out"
}

run_rc=0
SCAN_OUT="$(run_one "$SCAN_SQL")" || run_rc=$?
[[ "$run_rc" -eq 0 ]] || exit "$run_rc"
# TAB-joined: first_marker_dt itself contains a space ('YYYY-MM-DD HH:MM:SS'),
# so a default-IFS `read` would split it mid-field.
IFS=$'\t' read -r control_rows probe_rows deploy_ok_rows fchmod_rows_total first_marker_dt machine_ids <<<"$(printf '%s\n' "$SCAN_OUT" | jq -R -r '
  fromjson? | select(type == "object" and has("control_rows"))
  | [.control_rows, .probe_rows, .deploy_ok_rows, .fchmod_rows_total, .first_marker_dt, .machine_ids]
  | map(tostring) | join("\t")')"

for n in "${control_rows:-}" "${probe_rows:-}" "${deploy_ok_rows:-}" "${fchmod_rows_total:-}" "${machine_ids:-}"; do
  if ! numeric "$n"; then
    printf 'NOT YET: unparseable scan result: %s\n' "${SCAN_OUT:0:300}" >&2
    exit 2
  fi
done
marker_rows=$(( probe_rows + deploy_ok_rows ))
first_marker_dt="${first_marker_dt:-}"

verdict() { # $1 outcome, $2 post_fix_fchmod_rows, $3 exit
  echo "SOLEUR_WEB2_SEED_ASSERT outcome=$1 host=${HOST_NAME} control_rows=${control_rows} marker_rows=${marker_rows} fchmod_rows_total=${fchmod_rows_total} post_fix_fchmod_rows=$2 first_marker_dt=${first_marker_dt} machine_ids=${machine_ids} since=${EARLIEST}"
  exit "$3"
}

# CONTROL FIRST — its failure modes dominate: zero control rows means the
# channel cannot answer at all, so every later count is unmeasurable.
if [[ "$control_rows" -eq 0 ]]; then
  printf 'CANNOT ESTABLISH: zero ci-deploy/webhook rows for %s since %s — the channel is dark (or host_name moved), so an absence result would be vacuous.\n' "$HOST_NAME" "$EARLIEST" >&2
  verdict cannot_establish - 3
fi

if [[ "$marker_rows" -eq 0 ]]; then
  printf 'NOT YET: no post-fix marker (PLUGIN_SEED_PROBE or a Deploy-succeeded-class ci-deploy row) on %s since %s — the fix has not exercised the host; %s fchmodat2 rows in-window are pre-delivery history, not a verdict.\n' "$HOST_NAME" "$EARLIEST" "$fchmod_rows_total" >&2
  verdict not_yet - 2
fi

# first_marker_dt is '1970-01-01 00:00:00' on an empty minIf — marker_rows > 0
# already excludes that, but refuse a non-date shape defensively: feeding it to
# toDateTime would floor the absence window at the epoch and re-grade history.
if ! [[ "$first_marker_dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
  printf 'NOT YET: first_marker_dt did not decode (%s): %s\n' "$first_marker_dt" "${SCAN_OUT:0:300}" >&2
  verdict not_yet - 2
fi

ABSENCE_SQL="SELECT count() AS n FROM ${SRC}
WHERE dt >= toDateTime('${first_marker_dt}')
  AND JSONExtractString(raw,'host_name') = '${HOST_NAME}'
  AND raw LIKE '%fchmodat2%'
FORMAT JSONEachRow"

run_rc=0
POST_FIX="$(run_one "$ABSENCE_SQL")" || run_rc=$?
[[ "$run_rc" -eq 0 ]] || exit "$run_rc"
post_fix_fchmod_rows="$(printf '%s\n' "$POST_FIX" | jq -R -r 'fromjson? | select(type == "object" and has("n")) | .n' | head -1)"
if ! numeric "$post_fix_fchmod_rows"; then
  printf 'NOT YET: unparseable absence count: %s\n' "${POST_FIX:0:300}" >&2
  verdict not_yet - 2
fi

if [[ "$post_fix_fchmod_rows" -gt 0 ]]; then
  printf 'FAIL: %s fchmodat2 row(s) on %s at/after the first post-fix marker (%s) — the abort path is still live after the fix deploy.\n' "$post_fix_fchmod_rows" "$HOST_NAME" "$first_marker_dt" >&2
  verdict fail "$post_fix_fchmod_rows" 1
fi

printf 'PASS: zero fchmodat2 rows on %s since the first post-fix deploy marker (%s); the container-side seed is exercising the host.\n' "$HOST_NAME" "$first_marker_dt"
verdict pass 0 0
