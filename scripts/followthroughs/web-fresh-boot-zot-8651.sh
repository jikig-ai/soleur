#!/usr/bin/env bash
# web-fresh-boot-zot-8651.sh — follow-through probe that owns the closure of issue 8651.
#
# 8651: every fresh web-host boot since the 2026-07-17 zot cutover resolved its seed image to
# GHCR (the zot selection read Doppler tokenlessly, #6985), and the GHCR read PAT is revoked
# (AP-016), so every fresh web boot was DARK. The fix bakes the zot endpoint + pull credential
# into user_data. Merging it changes no host (hcloud_server.web ignore_changes = [user_data]);
# only a web-host-replace of web-2 realizes it. The zot soak's WEB_BLOCKER arm
# (zot-soak-6122.sh) accepts the issue only as CLOSED/COMPLETED, so that state must follow an
# OBSERVED zot-served boot — never the merge.
#
# EVIDENCE = THE DISPATCHED JOB'S OWN LOG, not a Sentry query. The web-platform DSN is public
# (it ships in the browser bundle), so any Sentry event this probe could read is forgeable; a
# GitHub Actions job log is not. The probe reads the newest web_host_replace/web_host_create
# job for web-2 and grades ONLY the output lines of its "Surface fresh-host Sentry breadcrumb
# trail" step (GitHub also echoes each step's `run:` source into the log; those lines carry an
# ANSI prefix and are excluded). That step is fresh-host-boot-trail.sh, which prints the image
# origin (a server-side, host- and run-anchored Sentry read) next to its own boot verdict.
# Residual, stated: a DSN holder could still race a forged app_zot into the few minutes of a
# live replace run — the verdict line still requires the real host's fresh_boot_ready and no
# fatal, and the run itself must exist, be dispatched, and pass its reviewer environment.
#
# ATTRIBUTION EXPIRY (#11600/#11607). GitHub drops step-name attribution ~2-3 weeks after a job
# completes: every log line returns under field 2 `UNKNOWN STEP` while the content survives —
# and a proven zot-served boot otherwise falls through to "no web-2 run", indistinguishable
# from "the replace never happened". When the named-step trail holds no trail-pattern line
# (empty OR partially attributed), the probe recovers the step's output region on the runner's
# `##[group]Run` headers — the first header stamped at or after the step's `startedAt` (from
# `gh run view --json jobs`, camelCase) opens it, the next header or EOF closes it — after a
# global CR + UTF-8 BOM strip (one mark per section; only the `//` strip clears them all).
# The recovered region flows through the SAME emitted-vs-echoed filter as the named path and
# REPLACES the trail when it carries trail-pattern lines. A trail step that never ran
# (plan_only `skipped`, or absent from the jobs JSON) is a designed absence: `continue`, no
# tripwire. On a SUCCESS job a still-empty trail after recovery is a degraded channel —
# TRANSIENT exit 3 naming the cause; on a non-success job the unreadable trail stays
# best-effort (the carried residual). Carried residuals from the technique (8178/#11603): a
# `::group::` title literally beginning `Run ` can false-bound a region, and sub-second skew
# between `startedAt` and the header stamp can select an adjacent region.
#
# Exit (sweep-followthroughs.sh contract):
#   0 PASS            — newest web-2 run: fresh_boot_ready + image origin app_zot with zot_login=ok
#   1 FAIL            — newest web-2 run (fixed trail) booted DARK, timed out, or was GHCR-served
#   2 NOT YET         — no web-2 run yet, the newest predates the fixed trail, or it is inconclusive
#   3 CANNOT ESTABLISH — gh/jq missing, a GitHub read failed, or a success job's trail could not
#                       be measured (log drift / unrecoverable attribution expiry) (TRANSIENT:)
#   78                — refused to run under xtrace (GH_TOKEN is in the environment)
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: GH_TOKEN is in the environment (see #7797)\n' >&2; exit 78 ;;
esac

REPO="${WEB_ZOT_8651_REPO:-jikig-ai/soleur}"
HOST_KEY="web-2"
HOST_NAME="soleur-web-2"
WORKFLOW="apply-web-platform-infra.yml"
STEP="Surface fresh-host Sentry breadcrumb trail"

for b in gh jq; do
  command -v "$b" >/dev/null 2>&1 || { echo "TRANSIENT: '$b' is not installed — cannot read the replace job log." >&2; exit 3; }
done

ids=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch -L 40 \
  --json databaseId --jq '.[].databaseId' 2>/dev/null) || {
  echo "TRANSIENT: gh run list failed for $WORKFLOW — declare GH_TOKEN in the directive's secrets= clause." >&2; exit 3; }

# emit_content — the ONE chokepoint for the emitted-vs-echoed rule (#9905): input
# lines of shape "<ts> <content>" (field 3 of a `gh run view --log` line, or a
# recovered region line), output the content minus lines whose content begins
# with an ANSI escape (echoed `run:` source). The named-step anchor and the
# UNKNOWN STEP recovery both consume through it, so the filter can never drift
# between two copies.
emit_content() {
  awk '{ line = $0; sub(/^[^ ]+ /, "", line)
         if (substr(line, 1, 1) == sprintf("%c", 27)) next
         print line }'
}

for id in $ids; do
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: unexpected run id '$id'" >&2; exit 3; }
  jobs=$(gh run view "$id" --repo "$REPO" --json jobs 2>/dev/null) || { echo "TRANSIENT: cannot read jobs of run $id" >&2; exit 3; }
  # One jq over the response already in hand: the first non-skipped
  # web_host_replace/web_host_create job's id + conclusion, plus its trail
  # step's conclusion and startedAt — `gh run view --json jobs` spells the
  # field camelCase `startedAt` (NOT the REST `started_at` the #11603 port reads).
  jobs_tsv=$(jq -r --arg step "$STEP" '[.jobs[] | select((.name == "web_host_replace" or .name == "web_host_create")
                 and (.conclusion // "") != "skipped" and (.conclusion // "") != "")][0]
                 | "\(.databaseId)\t\(.conclusion)\t\(([.steps[]? | select(.name | startswith($step)) | .conclusion] | .[0] // "absent"))\t\(([.steps[]? | select(.name | startswith($step)) | .startedAt] | .[0] // "-"))"' <<<"$jobs" 2>/dev/null) \
    || { echo "TRANSIENT: unparseable jobs JSON for run $id" >&2; exit 3; }
  IFS=$'\t' read -r jid jcon jstep jstart <<<"$jobs_tsv"
  [[ -n "$jid" ]] || continue
  # A trail step that never ran — a plan_only `skipped`, or a run predating the
  # step (`absent`) — is a designed absence, not drift: keep the
  # continue-on-no-pointer posture. Recovery and the tripwire engage only for
  # a step that ran.
  [[ "$jstep" == "skipped" || "$jstep" == "absent" ]] && continue
  log=$(gh run view --repo "$REPO" --job "$jid" --log 2>/dev/null) || { echo "TRANSIENT: cannot read the log of job $jid (run $id)" >&2; exit 3; }
  # Normalize once for EVERY consumer of "$log" (8178's exact idiom): gh writes
  # a UTF-8 BOM at the start of EVERY step section after the first — landing
  # after the two tab fields, immediately before the timestamp — and a real
  # log carries one mark PER section, so only the global `//` strip clears them
  # all. Without it `^[0-9]` misses every later `##[group]Run` header and the
  # region derivation below comes back empty on every real aged log.
  log=${log//$'\r'/}
  log=${log//$'\357\273\277'/}
  # The trail step's own output: field 2 is the step name, field 3 is
  # "<ts> <content>". Echoed `run:` source begins with an ANSI escape AFTER the
  # timestamp — emit_content drops it.
  trail=$(awk -F'\t' -v step="$STEP" 'index($2, step) == 1 { print $3 }' <<<"$log" | emit_content)
  # ATTRIBUTION-EXPIRY RECOVERY (#11600/#11607): an aged log arrives with every
  # line under "UNKNOWN STEP" — the named anchor above yields nothing while the
  # content survives. The trigger is a PATTERNLESS named trail, not only an
  # empty one: partial attribution leaves emitted lines under the step name
  # while the pointer/ready sit under UNKNOWN STEP, and a nonempty-but-
  # patternless trail on a success job is the same degraded channel an empty
  # one is. Slice the trail step's output region on the runner's `##[group]Run`
  # headers: the first header stamped at or after the step's startedAt opens
  # it, the next header (or EOF) closes it. The awk is
  # git-data-boot-poll-8178.sh's region derivation verbatim; the region then
  # flows through the SAME emit_content chokepoint as the named path, and the
  # recovered region REPLACES the named trail only when it carries
  # trail-pattern lines (the region is the step's whole emitted output).
  TRAIL_PATTERN='web-host-(replace|create) web-[0-9]+ — fresh-host Sentry pointer|fresh-host boot reached fresh_boot_ready'
  recovery_cause=""
  if ! grep -qE "$TRAIL_PATTERN" <<<"$trail"; then
    trail=""
    if [[ "$jstart" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
      region=$(awk -v ps="${jstart:0:19}" '
        { line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line); ts = substr(line, 1, 19) }
        line ~ /^[0-9][0-9TZ:.-]* ##\[group\]Run / { if (started) exit; if (ts >= ps) { started = 1; next } }
        started { print line }' <<<"$log")
      if [[ -z "$region" ]]; then
        recovery_cause=" (attribution-expired log: no ##[group]Run header at/after ${jstart:0:19} yielded a region)"
      else
        region_trail=$(emit_content <<<"$region")
        if grep -qE "$TRAIL_PATTERN" <<<"$region_trail"; then
          trail="$region_trail"
        elif [[ -z "$region_trail" ]]; then
          recovery_cause=" (attribution-expired log: recovered region held no emitted lines)"
        else
          # A success job's trail step always emits the pointer — a region
          # with output but no trail-pattern line is a degraded channel
          # (#11600), never a quiet empty trail.
          recovery_cause=" (attribution-expired log: recovered region emitted no trail-pattern lines)"
        fi
      fi
    else
      recovery_cause=" (the trail step's jobs-JSON entry carried no usable startedAt)"
    fi
  fi
  # Tripwire, evaluated AFTER recovery: a SUCCESS-conclusion job's trail step
  # always emits at least the pointer line — zero parseable trail-pattern
  # lines means the parse channel itself broke (log shape drift OR
  # attribution expiry the recovery could not slice), which is measurable
  # CANNOT ESTABLISH, not a quiet "no run". A non-success job's unreadable
  # trail stays best-effort `continue` (the carried residual).
  if [[ "$jcon" == "success" && -z "$trail" ]]; then
    echo "TRANSIENT: run $id job $jid concluded success but the \`$STEP\` step emitted zero parseable lines — the log shape drifted; refusing to grade an unmeasured trail${recovery_cause}." >&2
    exit 3
  fi
  grep -qE "^web-host-(replace|create) ${HOST_KEY} — fresh-host Sentry pointer" <<<"$trail" || continue

  url="https://github.com/${REPO}/actions/runs/${id}"
  # The FIXED trail prints an image-origin line (or its named read failure). Its absence means
  # this run's boot-trail code predates the fix, so it says nothing about the fixed template.
  origin=$(grep -m1 -F "image-origin (\`${HOST_NAME}\`" <<<"$trail" || true)
  if [[ -z "$origin" ]] && ! grep -qF "image-origin read FAILED" <<<"$trail"; then
    echo "NOT YET: the newest ${HOST_KEY} run ($url) predates the fixed boot trail — dispatch web-host-replace web_host_key=web-2, confirm=REPLACE-web-2."
    exit 2
  fi
  if grep -qE "booted DARK|did not reach cloud_init_complete" <<<"$trail"; then
    echo "FAIL: ${HOST_KEY} booted DARK on $url. Map the fatal detail's nic=/zot=[…cause=…] fields to the plan's Observability failure modes, fix forward, then re-dispatch — runcmd is once-per-instance, an unchanged re-replace repeats."
    exit 1
  fi
  if grep -qE 'stage=app_ghcr_(served|fallback)' <<<"$origin"; then
    echo "FAIL: ${HOST_KEY} was served by GHCR, not zot, on $url: ${origin}"
    exit 1
  fi
  if grep -qF "fresh-host boot reached fresh_boot_ready" <<<"$trail" \
     && grep -qF "stage=app_zot" <<<"$origin" && grep -qF "zot_login=ok" <<<"$origin"; then
    echo "PASS: ${HOST_KEY} booted zot-served and reported fresh_boot_ready on $url — ${origin}. The detail carries zot_login=… (the GHCR leg was retired by #8036 1d); a pre-1d detail may still carry ghcr_login=…, which is not asserted."
    exit 0
  fi
  echo "NOT YET: the newest ${HOST_KEY} run ($url) is inconclusive (no fresh_boot_ready + app_zot/zot_login=ok pair) — re-run \`fresh-host-boot-trail.sh --image-origin ${HOST_NAME}\` or re-dispatch."
  exit 2
done
echo "NOT YET: no web_host_replace/web_host_create run for ${HOST_KEY} in the last 40 dispatches of $WORKFLOW."
exit 2
