#!/usr/bin/env bash
# Follow-through verification for #8037: image signature verification has never succeeded.
#
# WHAT IT PROVES. apps/web-platform/infra/ci-deploy.sh `verify_image_signature()` emits, once per
# deploy per web host, exactly one VERDICT line under `logger -t ci-deploy`:
#   IMAGE_VERIFY: ok ref=<repo@sha256:…>
#   IMAGE_VERIFY_FAIL: result=<class> ref=… mode=… detail=<free text>
# and, when the anonymous DOCKER_CONFIG for the cosign pull could not be prepared (the logged
# fail-open back to the credentialed pull, plan Phase 1a), immediately BEFORE that verdict:
#   IMAGE_VERIFY_PREP: anon_config=unavailable
# The failure classes the classifier can produce are unsigned, wrong_identity,
# rekor_unreachable, cosign_absent, inspect_failed and verify_failed. `IMAGE_VERIFY: Sentry POST
# failed` shares the prefix and is NOT a verdict; it is ignored.
#
# Until #8036/#8037's fix every deploy logged result=cosign_absent (the cosign verifier image
# pull rode a revoked GHCR credential). Closure needs a POSITIVE `IMAGE_VERIFY: ok` per host, not
# the absence of cosign_absent: a host that never deploys emits nothing.
#
# GRADING RULE — LATEST VERDICT PER HOST, and why the plan's wording was reconciled to it.
# The plan's PASS line reads "every host … has >=1 `IMAGE_VERIFY: ok` and 0 `result=cosign_absent`",
# while its FAIL line (and the observability review behind it) grades each host on its LATEST
# `IMAGE_VERIFY*` verdict because "any occurrence" would FAIL forever on one ghcr.io blip. The two
# rules disagree exactly on a host with an old cosign_absent followed by ok. This probe takes the
# LATEST-VERDICT rule for every grade: a host passes when its most recent verdict since earliest
# is `IMAGE_VERIFY: ok` (which implies >=1 ok). Earlier cosign_absent lines are reported in the
# per-host counts but do not block closure.
#
# PER-HOST KEY: journald `_MACHINE_ID` (see zot-login-gate-erofs-repaired-6565.sh for why not
# host / host_name — host_name is mislabelled fleet-wide, #6616). Measured on 2026-09-21: every
# IMAGE_VERIFY line in 24 h came from ONE machine id (web-1), so PASS needs >=1 host, never >=2.
#
# FIELD ISOLATION: rows count only when the decoded journald record's SYSLOG_IDENTIFIER FIELD is
# exactly `ci-deploy`. The Better Stack source is shared with the inngest webhook logs, which quote
# issue and PR bodies (this tracker's included) verbatim. A bare substring match false-grades
# (knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-
# isolate-syslog-identifier.md). `raw` is a JSON STRING holding the journald JSON, so it is
# decoded with `fromjson`, never substring-matched.
#
# ORDERING: by the journald `__REALTIME_TIMESTAMP` (microseconds, producer clock) with the `dt`
# ingest time as the fallback. On a timestamp tie a PREP line sorts before a verdict, which is
# the emission order inside one verify_image_signature() call.
#
# "SAME DEPLOY" for the PREP rule: a PREP line belongs to the first verdict that follows it on the
# same host. A PREP with no later verdict is a deploy still in flight and is ignored.
#
# EVIDENCE GATE: only records at or after SOLEUR_FT_EARLIEST count. The sweeper forwards the
# directive's `earliest=`, set from the `deploy_pipeline_fix` apply's completion plus a margin,
# because the co-fired release may still run the old script. The same instant is used as the
# server-side `--since` AND re-checked client-side on __REALTIME_TIMESTAMP.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS               >=1 host observed and every host's latest verdict is `IMAGE_VERIFY: ok`
#                          with no PREP-unavailable line in that deploy. Sweeper closes #8037.
#   1 = FAIL               some host's latest verdict is result=cosign_absent (clean prep): the
#                          verifier image still cannot be pulled. Takes precedence over 5.
#   5 = ACTION REQUIRED    some host's latest verdict is another failure class (unsigned,
#                          wrong_identity, verify_failed, …): the verifier RAN and said something
#                          about the image, which is a human decision; OR the latest verdict was
#                          preceded in the same deploy by `IMAGE_VERIFY_PREP: anon_config=
#                          unavailable`: the fallback put the credentialed pull back, so the
#                          verdict says nothing about the fix.
#   2 = NOT YET            creds unset, query tool missing/failing, earliest in the future, zero
#                          rows, or zero ci-deploy verdicts since earliest (no deploy yet).
#   3 = CANNOT ESTABLISH   SOLEUR_FT_EARLIEST unset/empty/malformed (no evidence gate), rows that
#                          do not decode as the journald envelope, or verdicts with no _MACHINE_ID.
#   78 = refused to run under xtrace with a live credential bound (#7797)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
#   BETTERSTACK_QUERY_PASSWORD (scheduled-followthrough-sweeper.yml), SOLEUR_FT_EARLIEST (the
#   sweeper). Optional: SOLEUR_FT_LIMIT (default 5000). Test seam: COSIGN_VERIFY_8037_BQ.
#
# Output discipline: stdout lands in a PUBLIC issue comment. The free-text `detail=` and `ref=`
# are never printed; the query tool's stderr is discarded (the credential is bound there).
# Machine ids are shortened to 12 hex characters.
#
# Observability layer: 6 (sweeper run log + tracker comment). Runs on a GitHub Actions runner.
#
# RETIREMENT: when #8037 closes, delete this file and its .test.sh, drop its run_suite line in
# scripts/test-all.sh, and remove the directive from the issue body.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${COSIGN_VERIFY_8037_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"

LIMIT="${SOLEUR_FT_LIMIT:-5000}"
if ! [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
  echo "TRANSIENT: invalid SOLEUR_FT_LIMIT '$LIMIT' (expected a positive integer)" >&2
  exit 2
fi

# Explicit empty-check, never `:?` — that aborts with status 1 (= FAIL) under the sweeper.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query Better Stack; a provisioning gap, not evidence." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $QUERY" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "TRANSIENT: jq not on PATH — cannot decode the journald envelope." >&2
  exit 2
fi

# ── EVIDENCE GATE ──────────────────────────────────────────────────────────────────────────────
# No header fallback: an unset earliest would grade deploys that may still have run the OLD
# script (the co-fired release), and `date -d` accepts far more than an ISO instant.
EARLIEST_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
if [[ -z "$EARLIEST" ]]; then
  echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset or empty — no evidence gate. The #8037 directive" >&2
  echo "                  must carry earliest=<ISO instant after the deploy_pipeline_fix apply>." >&2
  exit 3
fi
if ! [[ "$EARLIEST" =~ $EARLIEST_SHAPE ]]; then
  echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is not an ISO instant (YYYY-MM-DDTHH:MM:SSZ); refusing to grade." >&2
  exit 3
fi
EARLIEST_EPOCH="$(date -u -d "$EARLIEST" +%s 2>/dev/null)" || EARLIEST_EPOCH=""
if [[ -z "$EARLIEST_EPOCH" ]]; then
  echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST '$EARLIEST' does not parse as a date; refusing to grade." >&2
  exit 3
fi
NOW_EPOCH="$(date -u +%s)"
if (( EARLIEST_EPOCH > NOW_EPOCH )); then
  echo "TRANSIENT: SOLEUR_FT_EARLIEST ($EARLIEST) is in the future — no evidence can exist yet." >&2
  exit 2
fi
SINCE_SQL="$(date -u -d "@$EARLIEST_EPOCH" '+%Y-%m-%d %H:%M:%S')"
EARLIEST_US=$(( EARLIEST_EPOCH * 1000000 ))

# ── FETCH ──────────────────────────────────────────────────────────────────────────────────────
# --grep IMAGE_VERIFY covers the verdicts AND the PREP line (server-side LIKE, OR-combined). LIMIT
# keeps the NEWEST rows, so a truncated window still holds every host's latest verdict.
RAWOUT="$("$QUERY" --since "$SINCE_SQL" --grep IMAGE_VERIFY --limit "$LIMIT" 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh exited non-zero (auth/config/network). Its output is not" >&2
  echo "           reproduced: the credential is bound in that process and this text is public." >&2
  exit 2
}

ROWS_TOTAL="$(printf '%s\n' "$RAWOUT" | awk 'NF { n++ } END { print n + 0 }')"
if [[ "$ROWS_TOTAL" -eq 0 ]]; then
  echo "TRANSIENT: zero IMAGE_VERIFY rows since $EARLIEST — no deploy has run, or the channel is dark." >&2
  exit 2
fi

# One TSV line per decoded record: <decoded 0|1> <sid 0|1> <mid> <ts_us> <rank> <kind> <class>
#   decoded: the row is a JSON object whose `raw` decodes to a JSON object.
#   sid:     the decoded SYSLOG_IDENTIFIER FIELD is exactly "ci-deploy".
#   rank:    0 for PREP, 1 for a verdict (tie-break: PREP first, the emission order).
#   kind:    ok | fail | prep | other.
PARSED="$(printf '%s\n' "$RAWOUT" | jq -R -r '
  (fromjson? // null) as $row
  | if ($row | type) != "object" then "0\t0\t-\t0\t9\tother\t-"
    else
      (($row.raw // null) | if type == "string" then (fromjson? // null) else . end) as $r
      | if ($r | type) != "object" then "0\t0\t-\t0\t9\tother\t-"
        else
          (($r.message // $r.MESSAGE // "") | tostring) as $m
          | (if ($r.SYSLOG_IDENTIFIER // "") == "ci-deploy" then "1" else "0" end) as $sid
          | (($r._MACHINE_ID // "") | tostring
              | if test("^[0-9a-f]{32}$") then . else "-" end) as $mid
          | ((($r.__REALTIME_TIMESTAMP // "") | tostring | tonumber?)
              // ((($row.dt // "") | tostring)[0:19] + "Z"
                   | (strptime("%Y-%m-%d %H:%M:%SZ") | mktime) * 1000000)? // 0) as $ts
          | if ($m | test("^IMAGE_VERIFY: ok( |$)")) then [ "1", $sid, $mid, ($ts|tostring), "1", "ok", "-" ]
            elif ($m | test("^IMAGE_VERIFY_FAIL: result=[a-z_]+")) then
              [ "1", $sid, $mid, ($ts|tostring), "1", "fail",
                ($m | capture("^IMAGE_VERIFY_FAIL: result=(?<c>[a-z_]+)").c) ]
            elif ($m | test("^IMAGE_VERIFY_PREP: anon_config=unavailable( |$)")) then
              [ "1", $sid, $mid, ($ts|tostring), "0", "prep", "-" ]
            else [ "1", $sid, $mid, ($ts|tostring), "9", "other", "-" ] end
          | join("\t")
        end
    end
' 2>/dev/null)" || PARSED=""

DECODED="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1 == "1" { n++ } END { print n + 0 }')"
if [[ "$DECODED" -eq 0 ]]; then
  echo "CANNOT ESTABLISH: ${ROWS_TOTAL} row(s) returned but none decoded as the journald envelope" >&2
  echo "                  (raw is expected to be a JSON string holding a JSON object). The query" >&2
  echo "                  shape changed; fix the probe, do not read this as evidence." >&2
  exit 3
fi

# Keep ci-deploy records since earliest that are verdicts or PREP.
RELEVANT="$(printf '%s\n' "$PARSED" | awk -F'\t' -v e="$EARLIEST_US" \
  '$1 == "1" && $2 == "1" && ($6 == "ok" || $6 == "fail" || $6 == "prep") && ($4 + 0) >= (e + 0)')"
VERDICTS_NO_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 7 && $3 == "-" && $6 != "prep" { n++ } END { print n + 0 }')"
VERDICTS_WITH_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 7 && $3 != "-" && $6 != "prep" { n++ } END { print n + 0 }')"

if [[ "$VERDICTS_WITH_MID" -eq 0 && "$VERDICTS_NO_MID" -gt 0 ]]; then
  echo "CANNOT ESTABLISH: ${VERDICTS_NO_MID} ci-deploy IMAGE_VERIFY verdict(s) since $EARLIEST carry no" >&2
  echo "                  usable _MACHINE_ID, so no verdict can be attributed to a host." >&2
  exit 3
fi

# Per-host fold, in timestamp order (PREP before verdict on a tie). A PREP attaches to the next
# verdict on the same host; the grade is the LAST verdict and its attached PREP flag.
# Output: <mid> <latest_kind> <latest_class> <latest_prep 0|1> <n_ok> <n_absent> <n_other> <n_prep>
HOSTS="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 7 && $3 != "-"' | sort -t$'\t' -k3,3 -k4,4n -k5,5n | awk -F'\t' '
  {
    mid = $3; kind = $6; cls = $7
    seen[mid] = 1
    if (kind == "prep") { pending[mid] = 1; nprep[mid]++; next }
    verdict[mid] = 1
    lkind[mid] = kind; lcls[mid] = cls; lprep[mid] = (pending[mid] ? 1 : 0); pending[mid] = 0
    if (kind == "ok") nok[mid]++
    else if (cls == "cosign_absent") nabs[mid]++
    else noth[mid]++
  }
  END {
    for (m in verdict)
      printf "%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", m, lkind[m], lcls[m], lprep[m], nok[m], nabs[m], noth[m], nprep[m]
  }' | sort)"

HOSTS_TOTAL="$(printf '%s\n' "$HOSTS" | awk 'NF { n++ } END { print n + 0 }')"
if [[ "$HOSTS_TOTAL" -eq 0 ]]; then
  echo "TRANSIENT: no ci-deploy IMAGE_VERIFY verdict from any host since $EARLIEST — no deploy has run" >&2
  echo "           the fixed script yet (${ROWS_TOTAL} row(s) seen, none a ci-deploy verdict). Zero hosts" >&2
  echo "           is never a PASS. Retry next sweep." >&2
  exit 2
fi

n_fail=0; n_action=0; n_ok=0
REPORT=""
while IFS=$'\t' read -r mid kind cls prep c_ok c_abs c_oth c_prep; do
  [[ -n "$mid" ]] || continue
  short="${mid:0:12}"
  if [[ "$kind" == "ok" ]]; then latest="ok"; else latest="result=${cls}"; fi
  if [[ "$prep" -eq 1 ]]; then
    grade="ACTION REQUIRED (anon_config=unavailable before the latest verdict)"
    n_action=$((n_action + 1))
  elif [[ "$kind" == "ok" ]]; then
    grade="ok"
    n_ok=$((n_ok + 1))
  elif [[ "$cls" == "cosign_absent" ]]; then
    grade="FAIL"
    n_fail=$((n_fail + 1))
  else
    grade="ACTION REQUIRED (new failure class)"
    n_action=$((n_action + 1))
  fi
  REPORT="${REPORT}  host ${short}: latest=${latest} grade=${grade} ok=${c_ok} cosign_absent=${c_abs} other_fail=${c_oth} prep_unavailable=${c_prep}"$'\n'
done <<<"$HOSTS"

if [[ "$n_fail" -gt 0 ]]; then
  echo "FAIL: ${n_fail} of ${HOSTS_TOTAL} host(s) still end on IMAGE_VERIFY_FAIL: result=cosign_absent since"
  echo "      ${EARLIEST} — the cosign verifier image still cannot be pulled, so signature verification"
  echo "      has not run. Graded on each host's LATEST verdict. Leave #8037 open."
  printf '%s' "$REPORT"
  echo "Read the rows with:"
  echo "  doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since '${SINCE_SQL}' --grep IMAGE_VERIFY | jq -r '.raw | fromjson | select(.SYSLOG_IDENTIFIER == \"ci-deploy\") | .message'"
  exit 1
fi

if [[ "$n_action" -gt 0 ]]; then
  echo "ACTION REQUIRED: ${n_action} of ${HOSTS_TOTAL} host(s) need a human decision. Either the verifier"
  echo "      now RUNS and reports a new failure class about the image (unsigned / wrong_identity /"
  echo "      verify_failed / …: decide whether the image or the identity pin is wrong), or the deploy"
  echo "      logged IMAGE_VERIFY_PREP: anon_config=unavailable before its verdict, meaning the"
  echo "      fallback put the credentialed cosign pull back and the verdict says nothing about the fix."
  printf '%s' "$REPORT"
  exit 5
fi

echo "PASS: ${n_ok} host(s) observed since ${EARLIEST}, and every host's latest ci-deploy verdict is"
echo "      IMAGE_VERIFY: ok with no anon_config=unavailable fallback — image signature verification"
echo "      runs and succeeds. Close #8037."
printf '%s' "$REPORT"
exit 0
