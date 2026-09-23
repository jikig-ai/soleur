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
# Named *_LITERAL, not *_TOKEN: these are journald marker strings, and a `*_TOKEN` name makes
# scripts/lint-shell-trace-credential-refusal.py treat them as credentials the xtrace refusal
# must cover. Widening that refusal to name non-secrets is the wrong repair — it dilutes what
# the guard asserts. The name was the defect.
MARKER_LITERAL='SOLEUR_DEPLOY_GHCR_CONFIG'
RELOGIN_LITERAL='stage=relogin_failed'
VERIFY_LITERAL='IMAGE_VERIFY'

if [[ "${1:-}" == "--explain" ]]; then
  cat <<EXPLAIN
PROBE-READY ghcr-read-retired-8036
  tracker:   #8036 item 1c — retire the host-side GHCR read path
  source:    Better Stack, journald records whose decoded SYSLOG_IDENTIFIER == "ci-deploy"
  key:       _MACHINE_ID (12-hex prefix in the report)
  window:    __REALTIME_TIMESTAMP >= SOLEUR_FT_EARLIEST (no header fallback; unset => exit 3)
  fetch:     ${QUERY##*/} --since <earliest> --grep ${MARKER_LITERAL} --grep relogin_failed --grep ${VERIFY_LITERAL} --limit \${SOLEUR_FT_LIMIT:-5000}
  graded, per host, as a CONJUNCTION (never a pure absence):
    leg 1  latest ${MARKER_LITERAL} line carries a 'swept=' token AND 'deploy_ghcr_auth=none'
           ('swept=' is the version discriminator: the pre-1c script cannot emit it, while
            'deploy_ghcr_auth=none' is also what a freshly provisioned PRE-1c host reads)
    leg 2  zero '${RELOGIN_LITERAL}' rows  (the operator's stated criterion, verbatim)
    leg 3  latest ${VERIFY_LITERAL}* verdict is not 'result=verify_failed'
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
RAWOUT="$("$QUERY" --since "$SINCE_SQL" --grep "$MARKER_LITERAL" --grep relogin_failed --grep "$VERIFY_LITERAL" --limit "$LIMIT" 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh exited non-zero (auth/config/network). Its output is not" >&2
  echo "           reproduced: the credential is bound in that process and this text is public." >&2
  exit 2
}

ROWS_TOTAL="$(printf '%s\n' "$RAWOUT" | awk 'NF { n++ } END { print n + 0 }')"
if [[ "$ROWS_TOTAL" -eq 0 ]]; then
  echo "TRANSIENT: zero matching rows since $EARLIEST — no deploy has run, or the channel is dark." >&2
  exit 2
fi

# SATURATION. `betterstack-query.sh` takes the NEWEST rows (inner ORDER BY dt DESC), so a result
# set that hit the limit has dropped the OLDEST rows — exactly where a surviving pre-1c
# `stage=relogin_failed` sits. Leg 2 grades an ABSENCE, and an absence measured over a truncated
# window is not evidence of anything: a lowered SOLEUR_FT_LIMIT, a widened `earliest`, or a noisy
# fleet would silently turn "89 relogin rows exist" into "zero" and close #8036 on it. The probe
# this one was adapted from is safe without this check only because its legs are
# latest-verdict-shaped; that reasoning does not carry to an absence leg.
if [[ "$ROWS_TOTAL" -ge "$LIMIT" ]]; then
  echo "TRANSIENT: result set saturated at ${ROWS_TOTAL}/${LIMIT} rows. The query keeps the NEWEST" >&2
  echo "           rows, so the oldest since $EARLIEST were dropped — and leg 2 grades an absence" >&2
  echo "           over that whole window. Raise SOLEUR_FT_LIMIT or narrow the window; a verdict" >&2
  echo "           from a truncated read would not be evidence." >&2
  exit 2
fi

# One TSV line per decoded record:
#   <decoded 0|1> <sid 0|1> <mid> <ts_us> <kind> <swept> <deploy_auth> <verify_class>
#   <deploy_cfg> <deploy_creds_store> <deploy_ghcr_helper>
# kind: marker | relogin | verify | other
PARSED="$(printf '%s\n' "$RAWOUT" | jq -R -r --arg mt "$MARKER_LITERAL" '
  (fromjson? // null) as $row
  | if ($row | type) != "object" then "0\t0\t-\t0\tother\t-\t-\t-"
    else
      (($row.raw // null) | if type == "string" then (fromjson? // null) else . end) as $r
      | if ($r | type) != "object" then "0\t0\t-\t0\tother\t-\t-\t-\t-\t-\t-"
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
                (($m | capture(" swept=(?<v>[a-z_]+)").v) // "-"),
                (($m | capture(" deploy_ghcr_auth=(?<v>[a-z_]+)").v) // "-"),
                "-",
                (($m | capture(" deploy_cfg=(?<v>[a-z_]+)").v) // "-"),
                (($m | capture(" deploy_creds_store=(?<v>[a-z_]+)").v) // "-"),
                (($m | capture(" deploy_ghcr_helper=(?<v>[a-z_]+)").v) // "-") ]
            elif ($m | test("stage=relogin_failed")) then
              [ "1", $sid, $mid, ($ts|tostring), "relogin", "-", "-", "-", "-", "-", "-" ]
            elif ($m | test("^IMAGE_VERIFY: ok( |$)")) then
              [ "1", $sid, $mid, ($ts|tostring), "verify", "-", "-", "ok", "-", "-", "-" ]
            elif ($m | test("^IMAGE_VERIFY_FAIL: result=[a-z_]+")) then
              [ "1", $sid, $mid, ($ts|tostring), "verify", "-", "-",
                ($m | capture("^IMAGE_VERIFY_FAIL: result=(?<c>[a-z_]+)").c),
                "-", "-", "-" ]
            else [ "1", $sid, $mid, ($ts|tostring), "other", "-", "-", "-", "-", "-", "-" ] end
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
MARKERS_NO_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 11 && $3 == "-" && $5 == "marker" { n++ } END { print n + 0 }')"
MARKERS_WITH_MID="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 11 && $3 != "-" && $5 == "marker" { n++ } END { print n + 0 }')"

if [[ "$MARKERS_WITH_MID" -eq 0 && "$MARKERS_NO_MID" -gt 0 ]]; then
  echo "CANNOT ESTABLISH: ${MARKERS_NO_MID} ci-deploy ${MARKER_LITERAL} line(s) since $EARLIEST carry no" >&2
  echo "                  usable _MACHINE_ID, so no reading can be attributed to a host." >&2
  exit 3
fi

# Per-host fold in timestamp order. A host is a group iff it emitted at least one MARKER: a host
# that emitted only a relogin row has not demonstrated it ran the new script, and leg 1 is what
# says so — so relogin rows are counted against the host but cannot create one, and a relogin-only
# host surfaces as the UNGRADED count reported below rather than silently vanishing.
# Output: <mid> <swept> <deploy_auth> <n_relogin> <latest_verify_class> <n_marker>
# Per-host fold in timestamp order. A host is a group iff it emitted at least one MARKER: a host
# that emitted only a relogin row has not demonstrated it ran the new script, and leg 1 is what
# says so — so relogin rows are counted against the host but cannot create one, and a relogin-only
# host surfaces as the UNGRADED count reported below rather than silently vanishing.
#
# RELOGIN ROWS ARE COUNTED ONLY IF THEY ARE NEWER THAN THE HOST'S LATEST MARKER. Counting every
# row since `earliest` latches the tracker shut forever: `earliest` is deliberately set to the
# apply's completion PLUS A MARGIN because the co-fired release may still run the OLD script, so
# the window is EXPECTED to contain pre-1c rows. One of them under the old rule pinned leg 2 to
# fail on a host that then retired cleanly and deployed a hundred times. The post-marker window is
# the property actually wanted: "the script that emits `swept=` does not log in to ghcr.io".
# `nrel_all` is carried alongside so the report can still say rows were seen and ignored.
# Output: <mid> <swept> <deploy_auth> <n_relogin_post_marker> <latest_verify> <n_marker>
#         <deploy_cfg> <deploy_creds_store> <deploy_ghcr_helper> <n_relogin_all>
HOSTS="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 11 && $3 != "-"' | sort -t$'\t' -k3,3 -k4,4n | awk -F'\t' '
  {
    mid = $3; kind = $5
    if (kind == "marker") {
      seen[mid] = 1; swept[mid] = $6; dauth[mid] = $7; nmark[mid]++
      dcfg[mid] = $9; dstore[mid] = $10; dhelper[mid] = $11
      if (($4 + 0) > (mts[mid] + 0)) mts[mid] = $4 + 0
    } else if (kind == "relogin") {
      rel[mid] = rel[mid] " " ($4 + 0); nrelall[mid]++
    } else if (kind == "verify") { lver[mid] = $8 }
  }
  END {
    for (m in seen) {
      n = 0; c = split(rel[m], a, " ")
      for (i = 1; i <= c; i++) if (a[i] != "" && (a[i] + 0) > (mts[m] + 0)) n++
      printf "%s\t%s\t%s\t%d\t%s\t%d\t%s\t%s\t%s\t%d\n", m, swept[m], dauth[m], n,
        (lver[m] == "" ? "-" : lver[m]), nmark[m],
        (dcfg[m] == "" ? "-" : dcfg[m]), (dstore[m] == "" ? "-" : dstore[m]),
        (dhelper[m] == "" ? "-" : dhelper[m]), nrelall[m]
    }
  }' | sort)"

HOSTS_TOTAL="$(printf '%s\n' "$HOSTS" | awk 'NF { n++ } END { print n + 0 }')"

# A host that emitted relogin rows but NO marker cannot be GRADED and must not be invisible — and
# it is computed BEFORE the zero-hosts check, because the two states are not the same thing and
# the cheaper check would otherwise swallow the louder one. A host emitting `stage=relogin_failed`
# since `earliest` is positive evidence that the PRE-1c prelude is still running there; reporting
# that as TRANSIENT ("no deploy has run yet") would name a cause the probe measured the opposite
# of. It is a FAIL with its own sentence.
RELOGIN_ONLY="$(printf '%s\n' "$RELEVANT" | awk -F'\t' 'NF >= 11 && $3 != "-"' | awk -F'\t' '
  { if ($5 == "marker") mark[$3] = 1; if ($5 == "relogin") rel[$3] = 1 }
  END { for (m in rel) if (!(m in mark)) n++; print n + 0 }')"

if [[ "$HOSTS_TOTAL" -eq 0 && "$RELOGIN_ONLY" -eq 0 ]]; then
  echo "TRANSIENT: no ci-deploy ${MARKER_LITERAL} line from any host since $EARLIEST — no deploy has" >&2
  echo "           run the new script yet (${ROWS_TOTAL} row(s) seen, none a ci-deploy marker). Zero" >&2
  echo "           hosts is never a PASS. Retry next sweep." >&2
  exit 2
fi

n_fail=0; n_action=0; n_pass=0
REPORT=""
while IFS=$'\t' read -r mid swept dauth nrel lver nmark dcfg dstore dhelper nrelall; do
  [[ -n "$mid" ]] || continue
  short="${mid:0:12}"
  leg1=fail; leg2=fail; leg3=fail
  # LEG 1 — the host runs the new script AND presents no ghcr.io credential from the deploy config.
  # `swept` is "-" when the token is ABSENT, i.e. the pre-1c script: that is the version
  # discriminator and it can never pass. Otherwise the value says what the sweep DID:
  #   yes        re-read and verified clean
  #   no         nothing to sweep
  #   na_absent  no deploy config exists yet (a ForceNew/recut host, or one whose zot login has
  #              not yet written one). A file that is not there presents no credential, so this
  #              is CLEAN — grading it FAIL made #8036 unclosable on any host recut, which is the
  #              exact host class ADR-169 produces.
  #   na_nojq / na_symlink / na_notfile / na_readonly / failed
  #              the sweep could not run or could not verify. Refuse; do not grade clean.
  # BOTH carriers are graded, not just the inline PAT: docker resolves ghcr.io through
  # `credHelpers["ghcr.io"]` with or without an auths entry, so a host reporting
  # `deploy_ghcr_auth=none deploy_ghcr_helper=set` is still presenting a credential.
  case "$swept" in
    yes|no)
      if [[ "$dauth" == "none" && "$dhelper" == "none" ]]; then leg1=pass; fi ;;
    na_absent) leg1=pass ;;
    *) : ;;
  esac
  # LEG 2 — no relogin AFTER the host's latest marker (see the fold above).
  [[ "$nrel" -eq 0 ]] && leg2=pass
  # LEG 3 — the LATEST verify verdict is a good one. Graded as a closed allowlist, never as
  # "is it the one bad literal": `verify_image_signature` emits unsigned / wrong_identity /
  # rekor_unreachable / cosign_absent before falling back to verify_failed, and `cosign_absent`
  # is the literal this work's own evidence records firing 89/89. Under IMAGE_VERIFY_MODE=warn
  # the deploy proceeds, so every one of those was closing the tracker over a broken verify.
  # A host with markers but NO verify verdict is ACTION REQUIRED with its own sentence, never a
  # pass — but never a FAIL either, so it cannot latch the tracker shut.
  case "$lver" in ok|reused_local_reload) leg3=pass ;; *) leg3=fail ;; esac
  if [[ "$leg1" == "pass" && "$leg2" == "pass" && "$leg3" == "pass" ]]; then
    grade="ok"; n_pass=$((n_pass + 1))
  elif [[ "$leg1" != "pass" || "$leg2" != "pass" ]]; then
    grade="FAIL"; n_fail=$((n_fail + 1))
  elif [[ "$lver" == "-" ]]; then
    grade="ACTION REQUIRED (host ran the new script but emitted no IMAGE_VERIFY verdict)"
    n_action=$((n_action + 1))
  else
    grade="ACTION REQUIRED (latest IMAGE_VERIFY is result=${lver})"; n_action=$((n_action + 1))
  fi
  REPORT="${REPORT}  host ${short}: grade=${grade} swept=${swept} deploy_cfg=${dcfg} deploy_ghcr_auth=${dauth} deploy_creds_store=${dstore} deploy_ghcr_helper=${dhelper} relogin_failed_post_marker=${nrel} relogin_failed_in_window=${nrelall} latest_verify=${lver} markers=${nmark}"$'\n'
  # A GLOBAL credsStore is not deleted by the sweep (it is also where the zot entry lives), so
  # config alone cannot prove the helper no longer holds a ghcr.io secret — `docker logout`'s
  # erase is what does that, and it is not observable from here. Say so rather than let the
  # host pass silently on a guarantee this probe did not measure.
  if [[ "$dstore" == "set" ]]; then
    REPORT="${REPORT}    note: deploy_creds_store=set — leg 1 verified the config carries no ghcr.io carrier, but a global credential helper is configured and this probe cannot read what it stores."$'\n'
  fi
done <<<"$HOSTS"

if [[ "$RELOGIN_ONLY" -gt 0 ]]; then
  REPORT="${REPORT}  note: ${RELOGIN_ONLY} host(s) emitted ${RELOGIN_LITERAL} but no ${MARKER_LITERAL} line — ungraded (they have not demonstrated they ran the new script)."$'\n'
fi

if [[ "$n_fail" -gt 0 || "$RELOGIN_ONLY" -gt 0 ]]; then
  echo "FAIL: ${n_fail} of ${HOSTS_TOTAL} graded host(s), plus ${RELOGIN_ONLY} ungraded host(s), do not satisfy"
  echo "      the retirement conjunction since"
  echo "      ${EARLIEST}. Leg 1 needs the latest ${MARKER_LITERAL} line to carry a 'swept=' token,"
  echo "      'deploy_ghcr_auth=none' AND 'deploy_ghcr_helper=none'; leg 2 needs zero"
  echo "      '${RELOGIN_LITERAL}' AFTER that host's latest marker."
  echo "      READ THE swept= VALUE BEFORE ASSIGNING A CAUSE -- they are different remediations:"
  echo "        swept absent (-)  the host is still running the PRE-1c script. Nothing is broken;"
  echo "                          it has not been redeployed yet."
  echo "        swept=failed      the sweep ran and the config is STILL dirty. Investigate."
  echo "        swept=na_nojq     jq is missing on the host, so the sweep could not run."
  echo "        swept=na_symlink  the deploy docker config is a symlink; refused, not vetted."
  echo "        swept=na_notfile  the path exists but is not a regular file."
  echo "        swept=na_readonly the config is not writable by the deploy user."
  echo "        (swept=na_absent is NOT a failure -- no config means no credential to present.)"
  echo "      Leave #8036 open."
  printf '%s' "$REPORT"
  echo "Read the rows with:"
  echo "  doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since '${SINCE_SQL}' --grep ${MARKER_LITERAL} --grep relogin_failed | jq -r '.raw | fromjson | select(.SYSLOG_IDENTIFIER == \"ci-deploy\") | .message'"
  exit 1
fi

if [[ "$n_action" -gt 0 ]]; then
  echo "ACTION REQUIRED: ${n_action} of ${HOSTS_TOTAL} host(s) have the GHCR read path retired (legs 1 and 2"
  echo "      pass) but their latest ${VERIFY_LITERAL} verdict is result=verify_failed — signature"
  echo "      verification is broken there. Under IMAGE_VERIFY_MODE=warn the deploy PROCEEDS, and no"
  echo "      Sentry rule matches this class, so this line is the only notification. Check whether the"
  echo "      sweep clipped the co-resident zot auths entry before reading it as an unrelated defect."
  printf '%s' "$REPORT"
  exit 5
fi

echo "PASS: ${n_pass} host(s) observed since ${EARLIEST}, and every one satisfies all three legs —"
echo "      latest ${MARKER_LITERAL} carries a 'swept=' token with deploy_ghcr_auth=none, zero"
echo "      '${RELOGIN_LITERAL}', and no verify_failed. The host-side GHCR read path is retired."
echo "      Close #8036."
printf '%s' "$REPORT"
exit 0
