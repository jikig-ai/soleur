#!/usr/bin/env bash
# Fresh-host boot-trail reader — the ADR-128 R2/R3/R4/R5 surface, shared by BOTH
# host-provisioning dispatch jobs in .github/workflows/apply-web-platform-infra.yml:
#   * web_host_create  (apply_target=web-host-create,  #6730) — a BIRTH
#   * web_host_replace (apply_target=web-host-replace, #6969) — a REPLACE
#
# EXTRACTED, NOT REWRITTEN. This body is the byte-for-byte `run:` block that lived inline
# in web_host_create, lifted with sed rather than retyped: it is the fix that shipped for
# the web-2 dark boot (#6970), and re-keying a 230-line dense-shell incident fix by hand is
# how a fix becomes a regression.
#
# WHY A SCRIPT AND NOT A SECOND COPY. The replace path needs exactly this surface — a green
# `terraform apply` is not a green boot, and #6969 exists BECAUSE a host came up dark and
# nothing said so. Duplicating the block would have given the two copies one test between
# them: soleur-host-bootstrap-observability.test.sh AC8 pins the QUERY message literals
# against the emitters, and it pinned only the job it was written for. That is the
# "duplicated allow-set guarded by nothing" shape web-host-birth-gate.sh's own header
# records review having mutation-proved. One body, one pin, both callers.
#
# Inputs (environment):
#   WEB_HOST_KEY    the var.web_hosts key being provisioned (e.g. web-2)
#   JOB_STATUS      ${{ job.status }} — only a job that got as far as a successful apply is
#                   entitled to a dark-boot verdict
#   DISPATCH_LABEL  the apply_target name, used in log/summary prose (default web-host-create)
#   DOPPLER_TOKEN   read-only source for SENTRY_AUTH_TOKEN / SENTRY_ORG / SENTRY_PROJECT
#
# Exit: 0 on a clean boot, a skipped read, or a non-success job; 1 on a proven dark boot
# (fatal stage, or no terminal event inside the host's own boot window).

set +e
# Prose-only. Defaulted rather than required so a caller that forgets it degrades to the
# historical wording instead of printing an empty label into the operator-facing summary.
DISPATCH_LABEL="${DISPATCH_LABEL:-web-host-create}"
# R3-adjacent: read creds from Doppler prd_terraform, NOT GitHub repo secrets —
# the repo secret SENTRY_AUTH_TOKEN is unset, so a step reading it self-skips and
# logs "skipped", which is the silent-dark class this step exists to end. Capture
# the fetch rc so a FETCH FAILURE is NAMED rather than collapsed into "not
# configured".
SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN --plain -p soleur -c prd_terraform 2>/tmp/doppler-sentry.err); dop_rc=$?
# Doppler-fetched secrets are NOT auto-masked by Actions (unlike `secrets.*`).
# Every other Doppler read in this job masks; this one was the sole exception, and
# it is the only NEW secret the PR introduced. Latent today (no `set -x` anywhere
# in the file, and nothing echoes it) — masked anyway, because "no current caller
# prints it" is a property of today's code, not of the secret.
[[ -n "${SENTRY_AUTH_TOKEN:-}" ]] && printf '::add-mask::%s\n' "$SENTRY_AUTH_TOKEN"
SENTRY_ORG=$(doppler secrets get SENTRY_ORG --plain -p soleur -c prd_terraform 2>/dev/null || true)
SENTRY_PROJECT=$(doppler secrets get SENTRY_PROJECT --plain -p soleur -c prd_terraform 2>/dev/null || true)
# Echo to the LOG as well as the summary so
# `gh run view <id> --log | grep 'fresh-host Sentry pointer'` works.
echo "${DISPATCH_LABEL} ${WEB_HOST_KEY:-?} — fresh-host Sentry pointer (job=${JOB_STATUS})"
{
  echo "## ${DISPATCH_LABEL} ${WEB_HOST_KEY:-?} — fresh-host Sentry pointer (best-effort)"
  echo ""
  if [[ "${JOB_STATUS}" == "success" ]]; then
    echo "Apply succeeded. The trail below should show the probe fired and the last-reached stage (expect \`cloud_init_complete\` on a healthy fresh boot). An apply can succeed while the boot dies — that is what this read is for."
  else
    echo "The job failed. If the host was created and its boot aborted, a breadcrumb/fatal below names the last-reached stage."
  fi
  echo "_Best-effort: the host id is unknown to the runner, so this matches on message + a recent window — it may show an unrelated host or be empty._"
} >> "$GITHUB_STEP_SUMMARY"
if [[ "$dop_rc" -ne 0 ]]; then
  echo "_Sentry query skipped: DOPPLER FETCH FAILED (rc=${dop_rc}) — verify secrets.DOPPLER_TOKEN scope/validity for soleur/prd_terraform. doppler stderr: $(tr '\n' ' ' </tmp/doppler-sentry.err | tail -c 300)_" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
fi
if [[ -z "${SENTRY_AUTH_TOKEN:-}" || -z "${SENTRY_ORG:-}" || -z "${SENTRY_PROJECT:-}" ]]; then
  echo "_Sentry query skipped: fetch succeeded but SENTRY_AUTH_TOKEN / SENTRY_ORG / SENTRY_PROJECT is empty in Doppler prd_terraform (secret genuinely absent)._" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
fi
# Lockstep with the emit MESSAGE literals in soleur-host-bootstrap.sh and
# cloud-init.yml. Keep byte-identical or
# apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh (AC8) fails
# — that test checks BOTH directions, so a rename on either side goes red here
# rather than silently making this query match nothing.
QUERY='message:"soleur-hostscript-seed failed" OR message:"soleur-host-bootstrap failed" OR message:"soleur-host-bootstrap complete" OR message:"soleur-cloud-init boot stage"'
# R4: the /projects/{org}/{proj}/events/ endpoint IGNORES the `message:` search
# prefix — a message:"x" query returns 0 even for events that provably exist
# (verified against a known event id: bare full-text = 1 hit, message:"x" = 0).
# So fetch RECENT events UNFILTERED and match client-side with a regex DERIVED
# from QUERY (single source, no drift). Passing query=$QUERY here would produce a
# confident, wrong "the host emitted nothing".
MSG_RE=$(printf '%s' "$QUERY" | grep -oE 'message:"[^"]+"' | sed -E 's/message:"([^"]+)"/\1/' | paste -sd'|' -)
# An empty MSG_RE (QUERY reshaped so the extraction yields nothing) would make jq
# test("") match EVERY event and list arbitrary ones as boot stages. Refuse.
if [[ -z "$MSG_RE" ]]; then
  echo "_Sentry query skipped: QUERY message-literal extraction produced an empty regex — refusing to match-all (would mislabel arbitrary events as boot stages)._" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
fi
# POLLED, not sampled once. The earlier form issued a single curl immediately
# after `terraform apply` returned — and the signal it looks for cannot exist yet.
# `cloud_init_complete` is the LAST line of the cloud-init terminal runcmd block
# (anchor: `soleur-boot-emit cloud_init_complete info` in cloud-init.yml — cited by
# content, not by line number, because THIS change shifts it. The previous `:825 of
# 835` coordinate was CORRECT on main; a content anchor is used so the next edit does
# not silently rot it) and the host's own declared budget is
# SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900 (soleur-host-bootstrap.sh). So on a HEALTHY
# birth the single read landed in the no-match branch and printed "the host
# genuinely emitted nothing" — which is byte-identical to what a genuinely dark
# host produces. The step satisfied ADR-128 R2's letter while inverting its purpose:
# it could not discriminate the two states it exists to tell apart.
#
# The budget fits: timeout-minutes is 30 and the apply costs ~5m, so ~16m of polling
# (900s window + slack) leaves margin. Terminal states end the poll early, so a
# healthy boot usually returns in well under the budget.
# The step is `if: always()`, so it also runs when the APPLY failed — and then
# there may be no host at all. Polling 16 minutes for a host that was never
# created would turn every failed apply into a 16-minute red run for no signal.
# On a failed job: read ONCE, report whatever partial boot trail exists, and never
# fail the step (the job is already failing, and a second ::error:: would obscure
# the real cause). Only a job that got as far as a successful apply is entitled to
# a dark-boot verdict.
if [[ "${JOB_STATUS}" == "success" ]]; then
  DEADLINE=$(( SECONDS + 960 ))
else
  DEADLINE=$SECONDS
fi
# (#6969) Host attribution. This is a SHARED Sentry project, so "the last boot-stage
# event" was previously whichever host emitted most recently — the ambiguity that made
# the web-2 dark boot require a separate Hetzner API lookup to resolve host_id
# 155488316 into a name. Mirrors server.tf's host_name expression exactly.
if [[ "${WEB_HOST_KEY}" == "web-1" ]]; then
  EXPECT_HOST="soleur-web-platform"
else
  EXPECT_HOST="soleur-${WEB_HOST_KEY}"
fi
# A MISSING host_name matches (an image predating #6969 emits none, and dropping those
# events would make this gate blind rather than precise); a PRESENT-but-different one
# does not. So the filter can only ever exclude events provably from another host.
JQ_HOSTDEF='def hostok($eh): ([ (.tags // [])[]? | select(.key=="host_name") | .value ][0]) as $hn | ($hn == null or $hn == "" or $hn == $eh);'
TERMINAL=""
LAST_STAGE=""
LAST_DETAIL=""
LAST_HOST=""
FATAL_DETAIL=""
FATAL_STAGE=""
RETRIED=""
RETRY_DETAIL=""
TOTAL=0
while :; do
  HTTP=$(curl -s --max-time 20 -G -o /tmp/sentry-events.json -w '%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    --data-urlencode "per_page=100" \
    --data-urlencode "statsPeriod=1h" \
    --data-urlencode "sort=-timestamp" \
    "https://de.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/" 2>/dev/null || echo "000")
  RESP=$(cat /tmp/sentry-events.json 2>/dev/null || echo "")
  if [[ "$HTTP" != "200" ]] || ! echo "$RESP" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "::warning::fresh-host Sentry read FAILED (HTTP ${HTTP}) — the auto-read did NOT run; this is NOT a 'host emitted nothing' result."
    echo "_Sentry query FAILED (HTTP ${HTTP}) — the auto-read did NOT run; this is NOT a 'host emitted nothing' result. $(echo "$RESP" | jq -r '.detail // empty' 2>/dev/null | tr '\n' ' ' | head -c 160)_" | tee -a "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  # TRUNCATION GUARD. This is a SHARED project (web-1 traffic, app errors,
  # host_metrics), so a full page is not evidence of anything: the fresh host's
  # events may simply be past the cap. "genuinely emitted nothing" is only sayable
  # when the window was not truncated.
  TOTAL=$(echo "$RESP" | jq 'length' 2>/dev/null || echo 0)
  # (#6969) host-scoped selection, and carry the detail/host_name alongside the stage —
  # the whole point of the new channel is that the RUN can name the cause, so these
  # must be SELECTED here, not merely printed in the trail below. The jq programs stay
  # SINGLE-quoted (host matching rides in a concatenated `def`) so the `test($re)`
  # literal the observability suite's AC16 pins stays byte-identical.
  LAST_STAGE=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
    [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
          | ([ (.tags // [])[]? | select(.key=="stage") | .value ][0] // "?") ][0] // ""' 2>/dev/null || echo "")
  LAST_DETAIL=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
    [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
          | ([ (.tags // [])[]? | select(.key=="detail") | .value ][0] // "") ][0] // ""' 2>/dev/null || echo "")
  LAST_HOST=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
    [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
          | ([ (.tags // [])[]? | select(.key=="host_name") | .value ][0] // "") ][0] // ""' 2>/dev/null || echo "")
  # A retry that SUCCEEDED still names a real fault; without this its cause is buried
  # in a green run's collapsed summary and is seen by no one.
  if echo "$RESP" | jq -e --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
    [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
          | select([ (.tags // [])[]? | select(.key=="stage") | .value ][0] == "doppler_retry") ] | length > 0' >/dev/null 2>&1; then
    RETRIED="yes"
    # Capture the RETRY event's OWN detail. Using LAST_DETAIL here would be structurally
    # always-empty: it is [0] of the newest-first list, and this branch is only reached
    # when the newest event is cloud_init_complete, which has no per-stage detail file.
    # The annotation would then reliably print "Detail: <none>" — the retry's cause
    # discarded by the very line whose stated purpose is to surface it.
    RETRY_DETAIL=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
      [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
            | select([ (.tags // [])[]? | select(.key=="stage") | .value ][0] == "doppler_retry")
            | ([ (.tags // [])[]? | select(.key=="detail") | .value ][0] // "") ][0] // ""' 2>/dev/null || echo "")
  fi
  # Terminal = the host finished, or died. Either ends the wait; only one is good.
  if [[ "$LAST_STAGE" == "cloud_init_complete" ]]; then TERMINAL="complete"; break; fi
  if echo "$RESP" | jq -e --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'[.[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh)) | select((.tags // [])[]? | select(.key=="level") | .value == "fatal")] | length > 0' >/dev/null 2>&1; then
    FATAL_STAGE=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
      [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
            | select((.tags // [])[]? | select(.key=="level") | .value == "fatal")
            | ([ (.tags // [])[]? | select(.key=="stage") | .value ][0] // "?") ][0] // ""' 2>/dev/null || echo "")
    FATAL_DETAIL=$(echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
      [ .[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))
            | select((.tags // [])[]? | select(.key=="level") | .value == "fatal")
            | ([ (.tags // [])[]? | select(.key=="detail") | .value ][0] // "") ][0] // ""' 2>/dev/null || echo "")
    TERMINAL="fatal"; break
  fi
  if (( SECONDS >= DEADLINE )); then TERMINAL="timeout"; break; fi
  sleep 30
done
{
  if [[ "$TOTAL" -ge 100 ]]; then
    echo "_NOTE: the recent-events page came back FULL (100/100) on a SHARED project — this window is truncated, so an absence below is NOT proof the host emitted nothing._"
  fi
} | tee -a "$GITHUB_STEP_SUMMARY"
if [[ -n "$LAST_STAGE" ]]; then
  echo "$RESP" | jq -r --arg re "$MSG_RE" --arg eh "$EXPECT_HOST" "$JQ_HOSTDEF"'
    [.[] | select(((.message // .title) // "") | test($re)) | select(hostok($eh))] | .[0:8][]
    | ( [ (.tags // [])[]? | select(.key=="stage") | .value ][0] // "?" ) as $stage
    | ( [ (.tags // [])[]? | select(.key=="host_name") | .value ][0] // "?" ) as $hn
    | ( [ (.tags // [])[]? | select(.key=="detail") | .value ][0] // "" ) as $d
    | "- `\((.message // .title) // "?")` — stage=`\($stage)` host=`\($hn)` (\(.dateCreated // "?"))"
      + (if $d == "" then "" else "\n  - detail: `\($d)`" end)
  ' | tee -a "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi
case "$TERMINAL" in
  complete)
    echo "fresh-host boot reached cloud_init_complete — the host booted clean." | tee -a "$GITHUB_STEP_SUMMARY"
    # (#6969) a retry that succeeded is still a real fault. Surface it as an annotation
    # so the cause is not buried in a green run's collapsed summary.
    if [[ -n "$RETRIED" ]]; then
      echo "::warning::${WEB_HOST_KEY} booted clean but RETRIED a boot stage (stage=doppler_retry observed). The host is healthy; the underlying fault is not. Detail: ${RETRY_DETAIL:-<none captured>}"
      echo "_**Booted clean, but retried.** A \`doppler_retry\` breadcrumb was observed for \`${EXPECT_HOST}\`. Detail: \`${RETRY_DETAIL:-<none captured>}\`_" | tee -a "$GITHUB_STEP_SUMMARY"
    fi
    ;;
  fatal)
    if [[ "${JOB_STATUS}" != "success" ]]; then
      echo "_A fatal boot-stage event was surfaced, but this job did not complete its apply — the trail above may belong to an earlier attempt or another host._" | tee -a "$GITHUB_STEP_SUMMARY"
      exit 0
    fi
    # (#6969) the annotation names the CAUSE, not just the stage. The annotation — not
    # the job summary — is what surfaces at the top of the run page, so the detail has
    # to be interpolated HERE. `detail` carries the failing command's own stderr plus
    # its exit code and attempt count (rc=124 = the call timed out).
    echo "::error::${WEB_HOST_KEY} (${LAST_HOST:-host_name unset}) booted DARK at stage ${FATAL_STAGE:-${LAST_STAGE:-unknown}}: ${FATAL_DETAIL:-<no detail — the failing stage has no producer wired yet; see #6969 follow-up>}"
    echo "::error::runcmd is once-per-instance, so this host CANNOT be repaired by a reboot — it must be replaced. Do NOT put it into service."
    echo "_**The host booted dark.** Host \`${LAST_HOST:-unknown}\`, stage \`${FATAL_STAGE:-${LAST_STAGE:-unknown}}\`._" | tee -a "$GITHUB_STEP_SUMMARY"
    echo "_Cause: \`${FATAL_DETAIL:-<no detail captured>}\`_" | tee -a "$GITHUB_STEP_SUMMARY"
    echo "_runcmd is once-per-instance — replace the host, do not reboot it._" | tee -a "$GITHUB_STEP_SUMMARY"
    exit 1
    ;;
  timeout)
    if [[ "${JOB_STATUS}" != "success" ]]; then
      echo "_No terminal boot event; this job did not complete its apply, so no dark-boot verdict is drawn._" | tee -a "$GITHUB_STEP_SUMMARY"
      exit 0
    fi
    echo "::error::${WEB_HOST_KEY} (${LAST_HOST:-host_name unset}) did not reach cloud_init_complete within 960s (the host's own SOLEUR_FRESH_BOOT_WINDOW_SECONDS is 900). Last-reached stage: ${LAST_STAGE:-none observed}${LAST_DETAIL:+ — detail: ${LAST_DETAIL}}. Treat as DARK until proven otherwise — absence past the boot window is the documented dark-boot signal, not a slow boot."
    echo "_**No terminal boot event inside the host's own boot window.** Host \`${LAST_HOST:-unknown}\`, last-reached stage \`${LAST_STAGE:-none observed}\`. Treated as dark._" | tee -a "$GITHUB_STEP_SUMMARY"
    if [[ -n "$LAST_DETAIL" ]]; then
      echo "_Last detail: \`${LAST_DETAIL}\`_" | tee -a "$GITHUB_STEP_SUMMARY"
    fi
    exit 1
    ;;
esac

