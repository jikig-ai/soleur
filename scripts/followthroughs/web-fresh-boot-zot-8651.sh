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
# Exit (sweep-followthroughs.sh contract):
#   0 PASS            — newest web-2 run: fresh_boot_ready + image origin app_zot with zot_login=ok
#   1 FAIL            — newest web-2 run (fixed trail) booted DARK, timed out, or was GHCR-served
#   2 NOT YET         — no web-2 run yet, the newest predates the fixed trail, or it is inconclusive
#   3 CANNOT ESTABLISH — gh/jq missing or a GitHub read failed (TRANSIENT:)
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

for id in $ids; do
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: unexpected run id '$id'" >&2; exit 3; }
  jobs=$(gh run view "$id" --repo "$REPO" --json jobs 2>/dev/null) || { echo "TRANSIENT: cannot read jobs of run $id" >&2; exit 3; }
  jid=$(jq -r '[.jobs[] | select((.name == "web_host_replace" or .name == "web_host_create")
                 and (.conclusion // "") != "skipped" and (.conclusion // "") != "")][0].databaseId // empty' <<<"$jobs" 2>/dev/null) \
    || { echo "TRANSIENT: unparseable jobs JSON for run $id" >&2; exit 3; }
  [[ -n "$jid" ]] || continue
  log=$(gh run view --repo "$REPO" --job "$jid" --log 2>/dev/null) || { echo "TRANSIENT: cannot read the log of job $jid (run $id)" >&2; exit 3; }
  # The trail step's own output: field 2 is the step name; drop the timestamp and every
  # echoed-source line (they begin with an ANSI colour escape).
  trail=$(awk -F'\t' -v step="$STEP" 'index($2, step) == 1 { sub(/^[^ ]+ /, "", $3); print $3 }' <<<"$log" \
    | grep -v $'^\e' || true)
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
