#!/usr/bin/env bash
# Follow-through verification for #8036 item 1c: the host-side GHCR read path is retired.
#
# BUILT BY REPURPOSING scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh, which this PR
# retires: that probe soaked the auth-recovery machinery 1c deletes, so leaving it sweeping would
# have it assert over code that no longer exists. Same journald source, same verdict contract.
#
# ── WHY THE OPERATOR'S STATED CRITERION IS NOT ENOUGH ON ITS OWN ───────────────────────────────
# The 2026-09-22 ruling set the close criterion as "`stage=relogin_failed` absent on the first
# post-apply deploy". That is a PURE-ABSENCE test, and this family already learned what those are
# worth: cosign-verify-live-8037.sh records it in terms — "Closure needs a POSITIVE
# `IMAGE_VERIFY: ok` per host, not the absence of `cosign_absent`: a host that never deploys emits
# nothing." A host that is down, that never ran the new script, or whose log channel is dark also
# emits no `relogin_failed`. So the criterion is graded here as a CONJUNCTION, per host:
#
#   leg 1  the host's LATEST `SOLEUR_DEPLOY_GHCR_CONFIG` marker carries a `swept=` token AND reads
#          `deploy_ghcr_auth=none`;
#   leg 2  the host emitted ZERO `stage=relogin_failed` rows since earliest (the operator's own
#          criterion, kept verbatim);
#   leg 3  the host's LATEST `IMAGE_VERIFY*` verdict is not `result=verify_failed`.
#
# `swept=` IS THE VERSION DISCRIMINATOR, NOT `deploy_ghcr_auth=none`. An earlier draft graded on
# the `none` token alone, reasoning that the whole pre-1c fleet reads `inline`. That is an
# observation about two hosts on one day, not a structural property: `docker login ghcr.io`
# currently FAILS, and a failed login writes no auths entry, so today's `inline` readings are
# stale leftovers from when the PAT still worked. A FRESHLY PROVISIONED host running the PRE-1c
# script would read `deploy_ghcr_auth=none` on its first deploy and sail straight through the
# probe — which is the "the new code never reached this host" failure mode this probe exists to
# catch. The pre-1c script cannot emit a `swept=` token at all, so its PRESENCE is the
# discriminator and its VALUE (yes|no|na) is the drift signal.
#
# `home_ghcr_auth` IS REPORTED BUT NOT GRADED. ci-deploy.sh runs under webhook.service with
# ProtectHome=read-only and /home absent from its ReadWritePaths, so the deploy user cannot write
# ${HOME}/.docker/config.json and the sweep deliberately does not try. Grading on
# `home_ghcr_auth=none` would read `inline` forever and #8036 could never close. The home entry is
# a pre-#6565 fossil; clearing it rides the 1d follow-up with root's config.
#
# LEG 3 EXISTS BECAUSE NOTHING ELSE PAGES ON IT. `grep -n 'cosign\|verify_failed'
# apps/web-platform/infra/sentry/issue-alerts.tf` returns ZERO hits: `verify_image_signature`
# posts a Sentry event, but no rule matches it. That matters here specifically — this change's
# worst arm is "the sweep clips the co-resident zot auths entry", and under the default
# IMAGE_VERIFY_MODE=warn the deploy then PROCEEDS: the release ships while signature verification
# has silently stopped. Routing that detection to cosign-verify-live-8037.sh is not durable
# (#8037 is CLOSED, so the sweeper only evaluates it inside its closed-set lookback), so the leg
# is carried here, on an open tracker, and needs no Terraform apply.
#
# PER-HOST KEY: journald `_MACHINE_ID` (see zot-login-gate-erofs-repaired-6565.sh for why not
# host / host_name — host_name is mislabelled fleet-wide, #6616).
#
# SCOPED TO "EVERY HOST THAT SPOKE", NOT "EVERY DEPLOYING HOST". A probe that groups by
# `_MACHINE_ID` over its own result set structurally cannot see a host that emitted nothing — such
# a host is not a group. Stating the property as "every deploying host" would make the PASS arm a
# green that cannot be driven RED, and would have the close comment say "all hosts confirmed"
# when it means "every host that spoke". PASS therefore needs >=1 host, never >=2.
#
# FIELD ISOLATION: rows count only when the decoded journald record's SYSLOG_IDENTIFIER FIELD is
# exactly `ci-deploy`. The Better Stack source is shared with the inngest webhook logs, which
# quote issue and PR bodies VERBATIM — including this tracker's, which contains the literal
# `stage=relogin_failed` in its title and body. A bare substring match would therefore grade this
# issue's own text as fleet evidence and FAIL forever. `raw` is a JSON STRING holding the journald
# JSON, so it is decoded with `fromjson`, never substring-matched. See
# knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md
#
# ORDERING: by the journald `__REALTIME_TIMESTAMP` (microseconds, producer clock) with the `dt`
# ingest time as the fallback.
#
# EVIDENCE GATE: only records at or after SOLEUR_FT_EARLIEST count. The sweeper forwards the
# directive's `earliest=`, set from the `deploy_pipeline_fix` apply's completion plus a margin,
# because the co-fired release may still run the old script.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS               >=1 host observed and EVERY host satisfies all three legs. Close #8036.
#   1 = FAIL               some host fails leg 1 or leg 2 — the retirement has not landed there,
#                          or the prelude re-login is still firing.
#   5 = ACTION REQUIRED    every host passes legs 1 and 2, but some host's latest IMAGE_VERIFY
#                          verdict is result=verify_failed: signature verification is broken on a
#                          host whose GHCR read path IS retired. A human decision, and the one
#                          outcome a `swept=yes` host can still have that nothing else pages on.
#   2 = NOT YET            creds unset, query tool missing/failing, earliest in the future, zero
#                          rows, or zero ci-deploy markers since earliest (no deploy yet).
#   3 = CANNOT ESTABLISH   SOLEUR_FT_EARLIEST unset/empty/malformed, rows that do not decode as
#                          the journald envelope, or markers with no _MACHINE_ID.
#   78 = refused to run under xtrace with a live credential bound (#7797)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
#   BETTERSTACK_QUERY_PASSWORD (scheduled-followthrough-sweeper.yml), SOLEUR_FT_EARLIEST (the
#   sweeper). Optional: SOLEUR_FT_LIMIT (default 5000). Test seam: GHCR_RETIRED_8036_BQ.
#
# `--explain` prints the graded literals and the SQL shape and exits 0 WITHOUT any network call,
# so the contract is readable on a machine with no credentials.
#
# Output discipline: stdout lands in a PUBLIC issue comment. No config content, username, auth
# value or helper name is ever printed — the marker's vocabulary is closed by construction, and
# the query tool's stderr is discarded (the credential is bound there). Machine ids are shortened
# to 12 hex characters.
#
# Observability layer: 6 (sweeper run log + tracker comment). Runs on a GitHub Actions runner.
#
# RETIREMENT: when #8036 closes, delete this file and its .test.sh, drop its run_suite line in
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
QUERY="${GHCR_RETIRED_8036_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"

# The three graded literals, named once so `--explain` and the grader cannot drift apart.
MARKER_TOKEN='SOLEUR_DEPLOY_GHCR_CONFIG'
RELOGIN_TOKEN='stage=relogin_failed'
VERIFY_TOKEN='IMAGE_VERIFY'

if [[ "${1:-}" == "--explain" ]]; then
  cat <<EXPLAIN
PROBE-READY ghcr-read-retired-8036
  tracker:   #8036 item 1c — retire the host-side GHCR read path
  source:    Better Stack, journald records whose decoded SYSLOG_IDENTIFIER == "ci-deploy"
  key:       _MACHINE_ID (12-hex prefix in the report)
  window:    __REALTIME_TIMESTAMP >= SOLEUR_FT_EARLIEST (no header fallback; unset => exit 3)
  fetch:     ${QUERY##*/} --since <earliest> --grep ${MARKER_TOKEN} --grep relogin_failed --grep ${VERIFY_TOKEN} --limit \${SOLEUR_FT_LIMIT:-5000}
  graded, per host, as a CONJUNCTION (never a pure absence):
    leg 1  latest ${MARKER_TOKEN} line carries a 'swept=' token AND 'deploy_ghcr_auth=none'
           ('swept=' is the version discriminator: the pre-1c script cannot emit it, while
            'deploy_ghcr_auth=none' is also what a freshly provisioned PRE-1c host reads)
    leg 2  zero '${RELOGIN_TOKEN}' rows  (the operator's stated criterion, verbatim)
    leg 3  latest ${VERIFY_TOKEN}* verdict is not 'result=verify_failed'
  NOT graded: home_ghcr_auth / root_ghcr_auth — both are unreachable from webhook.service
           (ProtectHome=read-only; root's home is 0700) and ride the 1d follow-up.
  exits:   0 PASS | 1 FAIL (leg 1 or 2) | 5 ACTION REQUIRED (leg 3) | 2 NOT YET | 3 CANNOT ESTABLISH
  network: none in this mode
EXPLAIN
  exit 0
fi

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
  echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset or empty — no evidence gate. The #8036" >&2
  echo "                  directive must carry earliest=<ISO instant after the deploy_pipeline_fix" >&2
  echo "                  apply>." >&2
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
# Three --grep terms, OR-combined server-side (betterstack-query.sh: "--grep <substr> (repeatable,
# OR-combined)"). `relogin_failed` rather than the full `stage=relogin_failed`: the server-side
# LIKE is a substring match and the shorter term cannot miss a spacing variant; the exact literal
# is re-checked client-side below against the DECODED message.
RAWOUT="$("$QUERY" --since "$SINCE_SQL" --grep "$MARKER_TOKEN" --grep relogin_failed --grep "$VERIFY_TOKEN" --limit "$LIMIT" 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh exited non-zero (auth/config/network). Its output is not" >&2
  echo "           reproduced: the credential is bound in that process and this text is public." >&2
  exit 2
}

ROWS_TOTAL="$(printf '%s\n' "$RAWOUT" | awk 'NF { n++ } END { print n + 0 }')"
if [[ "$ROWS_TOTAL" -eq 0 ]]; then
  echo "TRANSIENT: zero matching rows since $EARLIEST — no deploy has run, or the channel is dark." >&2
  exit 2
fi

# One TSV line per decoded record:
#   <decoded 0|1> <sid 0|1> <mid> <ts_us> <kind> <swept> <deploy_auth> <verify_class>
# kind: marker | relogin | verify | other
PARSED="$(printf '%s\n' "$RAWOUT" | jq -R -r --arg mt "$MARKER_TOKEN" '
  (fromjson? // null) as $row
  | if ($row | type) != "object" then "0\t0\t-\t0\tother\t-\t-\t-"
    else
      (($row.raw // null) | if type == "string" then (fromjson? // null) else . end) as $r
      | if ($r | type) != "object" then "0\t0\t-\t0\tother\t-\t-\t-"
        else
          (($r.message // $r.MESSAGE // "") | tostring) as $m
          | (if ($r.SYSLOG_IDENTIFIER // "") == "ci-deploy" then "1" else "0" end) as $sid
          | (($r._MACHINE_ID // "") | tostring
              | if test("^[0-9a-f]{32}$") then . else "-" end) as $mid
          | ((($r.__REALTIME_TIMESTAMP // "") | tostring | tonumber?)
              // ((($row.dt // "") | tostring)[0:19] + "Z"
                   | (strptime("%Y-%m-%d %H:%M:%SZ") | mktime) * 1000000)? // 0) as $ts
          | if ($m | test("(^| )" + $mt + " ")) then
              [ "1", $sid, $mid, ($ts|tostring), "marker",
                (($m | capture(" swept=(?<v>[a-z]+)").v) // "-"),
                (($m | capture(" deploy_ghcr_auth=(?<v>[a-z]+)").v) // "-"),
                "-" ]
            elif ($m | test("stage=relogin_failed")) then
              [ "1", $sid, $mid, ($ts|tostring), "relogin", "-", "-", "-" ]
            elif ($m | test("^IMAGE_VERIFY: ok( |$)")) then
              [ "1", $sid, $mid, ($ts|tostring), "verify", "-", "-", "ok" ]
            elif ($m | test("^IMAGE_VERIFY_FAIL: result=[a-z_]+")) then
              [ "1", $sid, $mid, ($ts|tostring), "verify", "-", "-",
                ($m | capture("^IMAGE_VERIFY_FAIL: result=(?<c>[a-z_]+)").c) ]
            else [ "1", $sid, $mid, ($ts|tostring), "other", "-", "-", "-" ] end
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

RELEVANT="$(printf '%s\n' "$PARSED" | awk -F'\t' -v e="$EARLIEST_US" \
  '$1 == "1" && $2 == "1" && ($5 == "marker" || $5 == "relogin" || $5 == "verify") && ($4 + 0) >= (e + 0)')"
MARKERS_NO_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 8 && $3 == "-" && $5 == "marker" { n++ } END { print n + 0 }')"
MARKERS_WITH_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 8 && $3 != "-" && $5 == "marker" { n++ } END { print n + 0 }')"

if [[ "$MARKERS_WITH_MID" -eq 0 && "$MARKERS_NO_MID" -gt 0 ]]; then
  echo "CANNOT ESTABLISH: ${MARKERS_NO_MID} ci-deploy ${MARKER_TOKEN} line(s) since $EARLIEST carry no" >&2
  echo "                  usable _MACHINE_ID, so no reading can be attributed to a host." >&2
  exit 3
fi

# Per-host fold in timestamp order. A host is a group iff it emitted at least one MARKER: a host
# that emitted only a relogin row has not demonstrated it ran the new script, and leg 1 is what
# says so — so relogin rows are counted against the host but cannot create one, and a relogin-only
# host surfaces as the UNGRADED count reported below rather than silently vanishing.
# Output: <mid> <swept> <deploy_auth> <n_relogin> <latest_verify_class> <n_marker>
HOSTS="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 8 && $3 != "-"' | sort -t$'\t' -k3,3 -k4,4n | awk -F'\t' '
  {
    mid = $3; kind = $5
    if (kind == "marker") { seen[mid] = 1; swept[mid] = $6; dauth[mid] = $7; nmark[mid]++ }
    else if (kind == "relogin") { nrel[mid]++ }
    else if (kind == "verify") { lver[mid] = $8 }
  }
  END {
    for (m in seen)
      printf "%s\t%s\t%s\t%d\t%s\t%d\n", m, swept[m], dauth[m], nrel[m], (lver[m] == "" ? "-" : lver[m]), nmark[m]
  }' | sort)"

HOSTS_TOTAL="$(printf '%s\n' "$HOSTS" | awk 'NF { n++ } END { print n + 0 }')"

# A host that emitted relogin rows but NO marker cannot be GRADED and must not be invisible — and
# it is computed BEFORE the zero-hosts check, because the two states are not the same thing and
# the cheaper check would otherwise swallow the louder one. A host emitting `stage=relogin_failed`
# since `earliest` is positive evidence that the PRE-1c prelude is still running there; reporting
# that as TRANSIENT ("no deploy has run yet") would name a cause the probe measured the opposite
# of. It is a FAIL with its own sentence.
RELOGIN_ONLY="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 8 && $3 != "-"' | awk -F'\t' '
  { if ($5 == "marker") mark[$3] = 1; if ($5 == "relogin") rel[$3] = 1 }
  END { for (m in rel) if (!(m in mark)) n++; print n + 0 }')"

if [[ "$HOSTS_TOTAL" -eq 0 && "$RELOGIN_ONLY" -eq 0 ]]; then
  echo "TRANSIENT: no ci-deploy ${MARKER_TOKEN} line from any host since $EARLIEST — no deploy has" >&2
  echo "           run the new script yet (${ROWS_TOTAL} row(s) seen, none a ci-deploy marker). Zero" >&2
  echo "           hosts is never a PASS. Retry next sweep." >&2
  exit 2
fi

n_fail=0; n_action=0; n_pass=0
REPORT=""
while IFS=$'\t' read -r mid swept dauth nrel lver nmark; do
  [[ -n "$mid" ]] || continue
  short="${mid:0:12}"
  leg1=fail; leg2=fail; leg3=pass
  # `swept` is "-" when the token is ABSENT from the line — i.e. the pre-1c script. `na` is a
  # PRESENT token meaning "jq was missing so the sweep could not run", and it fails leg 1 with the
  # rest: the marker's own tokens then read `deploy_ghcr_auth=na`, not `none`.
  [[ "$swept" != "-" && "$dauth" == "none" ]] && leg1=pass
  [[ "$nrel" -eq 0 ]] && leg2=pass
  [[ "$lver" == "verify_failed" ]] && leg3=fail
  if [[ "$leg1" == "pass" && "$leg2" == "pass" && "$leg3" == "pass" ]]; then
    grade="ok"; n_pass=$((n_pass + 1))
  elif [[ "$leg1" != "pass" || "$leg2" != "pass" ]]; then
    grade="FAIL"; n_fail=$((n_fail + 1))
  else
    grade="ACTION REQUIRED (latest IMAGE_VERIFY is result=verify_failed)"; n_action=$((n_action + 1))
  fi
  REPORT="${REPORT}  host ${short}: grade=${grade} swept=${swept} deploy_ghcr_auth=${dauth} relogin_failed=${nrel} latest_verify=${lver} markers=${nmark}"$'\n'
done <<<"$HOSTS"

if [[ "$RELOGIN_ONLY" -gt 0 ]]; then
  REPORT="${REPORT}  note: ${RELOGIN_ONLY} host(s) emitted ${RELOGIN_TOKEN} but no ${MARKER_TOKEN} line — ungraded (they have not demonstrated they ran the new script)."$'\n'
fi

if [[ "$n_fail" -gt 0 || "$RELOGIN_ONLY" -gt 0 ]]; then
  echo "FAIL: ${n_fail} of ${HOSTS_TOTAL} graded host(s), plus ${RELOGIN_ONLY} ungraded host(s), do not satisfy"
  echo "      the retirement conjunction since"
  echo "      ${EARLIEST}. Leg 1 needs the latest ${MARKER_TOKEN} line to carry a 'swept=' token AND"
  echo "      'deploy_ghcr_auth=none'; leg 2 needs zero '${RELOGIN_TOKEN}'. A missing 'swept=' means the"
  echo "      host is still running the pre-1c script, NOT that the sweep failed. Leave #8036 open."
  printf '%s' "$REPORT"
  echo "Read the rows with:"
  echo "  doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since '${SINCE_SQL}' --grep ${MARKER_TOKEN} --grep relogin_failed | jq -r '.raw | fromjson | select(.SYSLOG_IDENTIFIER == \"ci-deploy\") | .message'"
  exit 1
fi

if [[ "$n_action" -gt 0 ]]; then
  echo "ACTION REQUIRED: ${n_action} of ${HOSTS_TOTAL} host(s) have the GHCR read path retired (legs 1 and 2"
  echo "      pass) but their latest ${VERIFY_TOKEN} verdict is result=verify_failed — signature"
  echo "      verification is broken there. Under IMAGE_VERIFY_MODE=warn the deploy PROCEEDS, and no"
  echo "      Sentry rule matches this class, so this line is the only notification. Check whether the"
  echo "      sweep clipped the co-resident zot auths entry before reading it as an unrelated defect."
  printf '%s' "$REPORT"
  exit 5
fi

echo "PASS: ${n_pass} host(s) observed since ${EARLIEST}, and every one satisfies all three legs —"
echo "      latest ${MARKER_TOKEN} carries a 'swept=' token with deploy_ghcr_auth=none, zero"
echo "      '${RELOGIN_TOKEN}', and no verify_failed. The host-side GHCR read path is retired."
echo "      Close #8036."
printf '%s' "$REPORT"
exit 0
