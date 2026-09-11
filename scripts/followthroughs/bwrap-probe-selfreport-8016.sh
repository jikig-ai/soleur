#!/usr/bin/env bash
# Follow-through soak for #8016: the blocking bwrap deploy-gate probe now reports its own
# exit code, duration, container state and sanitized stderr (PR #8026). This probe decides
# which of the issue's two closing arms fired.
#
# WHAT IT PROVES. apps/web-platform/infra/ci-deploy.sh emits, once per release, exactly one of
# two journald lines under `logger -t ci-deploy`:
#   SANDBOX_PROBE_OK: bwrap sandbox verified in <image> rc=0 ms=… cstate=… err_chars=… bwrap_err="…"
#   DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image> rc=… ms=… cstate=… err_chars=… bwrap_err="…"
# Both reach Better Stack Logs through Vector's host_scripts_journald source (`ci-deploy` is on
# the SYSLOG_IDENTIFIER allowlist, apps/web-platform/infra/vector.toml). SANDBOX_PROBE_OK did
# not exist before #8026, so its presence is proof the self-reporting marker is LIVE on the
# host -- not merely that deploys ran.
#
# THE TWO ARMS, as stated on the issue:
#   (a) the NEXT OCCURRENCE names its cause -> a human fixes it and closes #8016 by hand.
#       Here: any DEPLOY_ROLLBACK row in the window -> exit 1 (FAIL: comment, leave open).
#       The comment carries the TRUSTED fields (rc/ms/cstate/err_chars) per row and the exact
#       Better Stack query for the free-text bwrap_err. It deliberately does NOT reprint
#       bwrap_err: the sweeper posts stdout into a PUBLIC issue, and the Art. 30 PA-8 (g)
#       bracket authorises that text for Better Stack, not for GitHub.
#   (b) SOAK: N deploys with the marker live and zero recurrence -> the 2026-09-09 occurrence
#       was environmental. Here: zero DEPLOY_ROLLBACK rows AND >= MIN_DEPLOYS SANDBOX_PROBE_OK
#       rows -> exit 0 (PASS: sweeper closes #8016).
#
# FAIL-SAFE: any query/auth/config failure, OR fewer than MIN_DEPLOYS liveness rows -> exit 2
# (TRANSIENT), never PASS. The probe can only close #8016 on positive proof of a live, clean,
# sufficiently-exercised window. FAIL is evaluated BEFORE liveness so a real recurrence is never
# masked into a retry by a fault on the separate liveness query.
#
# Discriminate on the journald SYSLOG_IDENTIFIER FIELD, never a bare substring: inngest ships
# GitHub-webhook logs to the same source, and those embed issue/PR bodies that quote both
# marker strings verbatim (this tracker's own body does). Two byte-forms, as in
# ci-deploy-sentry-post-fail-6475.sh: the server-side LIKE term is against the UNescaped
# column; the client-side grep is over JSONEachRow stdout where inner quotes are escaped.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>= MIN_DEPLOYS SANDBOX_PROBE_OK rows AND zero rollback rows; sweeper closes #8016)
#   1 = FAIL       (>= 1 ci-deploy DEPLOY_ROLLBACK bwrap row; the occurrence that names its cause)
#   2 = TRANSIENT  (creds unset, query fault, or liveness below MIN_DEPLOYS -- inconclusive)
#   78 = refused to run under xtrace with a live credential bound (#7797)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
#   BETTERSTACK_QUERY_PASSWORD (wired in scheduled-followthrough-sweeper.yml). Optional:
#   BWRAP_SOAK_WINDOW (Nh/Nm/Nd, default 7d), BWRAP_SOAK_MIN_DEPLOYS (default 20; the host
#   deploys ~53x/week). Test seam: BWRAP_SOAK_BQ overrides the betterstack-query.sh path.
#
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper
# posts). Runs on a GitHub Actions runner under `env -i`; touches neither journald nor Vector.
#
# RETIREMENT: when #8016 closes, delete this file and its .test.sh, drop the run_suite line in
# scripts/test-all.sh, and remove the directive from the issue body. Nothing else references it.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797). The sweeper publishes probe
# stdout into a public issue comment; a traced bind of the warehouse password would land there.
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
BQ="${BWRAP_SOAK_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"

WINDOW="${BWRAP_SOAK_WINDOW:-7d}"
if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  echo "TRANSIENT: invalid BWRAP_SOAK_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2
  exit 2
fi
MIN_DEPLOYS="${BWRAP_SOAK_MIN_DEPLOYS:-20}"
if ! [[ "$MIN_DEPLOYS" =~ ^[1-9][0-9]*$ ]]; then
  echo "TRANSIENT: invalid BWRAP_SOAK_MIN_DEPLOYS '$MIN_DEPLOYS' (expected a positive integer)" >&2
  exit 2
fi

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# Explicit empty-check, never `:?` -- that form aborts with status 1 (= FAIL) under the
# sweeper's non-interactive shell, so unprovisioned creds would page instead of retry.
if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  echo "TRANSIENT: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not all set -- cannot query Better Stack; inconclusive" >&2
  exit 2
fi

readonly CI_DEPLOY_GREP_MARKER='SYSLOG_IDENTIFIER\":\"ci-deploy\"'
readonly ROLLBACK_MARKER='DEPLOY_ROLLBACK: bwrap sandbox non-functional'
readonly OK_MARKER='SANDBOX_PROBE_OK: bwrap sandbox verified'

# fetch_rows <grep_term> -- raw JSONEachRow rows matching <grep_term> in the window; non-zero
# on any query failure (caller -> TRANSIENT). Mode-2 `--grep` UNION-ALLs the hot window with
# the s3 archive, so a multi-day window is not silently truncated.
fetch_rows() {
  local term="$1" out rc
  out="$("$BQ" --since "$WINDOW" --grep "$term" --limit 1000 2>/dev/null)"; rc=$?
  [[ "$rc" -ne 0 ]] && return 1
  printf '%s' "$out"
  return 0
}

# trusted_fields <row> -- print `dt rc= ms= cstate= err_chars=` from one JSONEachRow row,
# reading each field from the region BEFORE the free-text bwrap_err= (the trusted region).
# Anchored per field, never a leading `.*`: bwrap_err is attacker-influenceable text that
# could contain `rc=0`, and it is emitted last precisely so a cut at its opener discards it.
trusted_fields() {
  local row="$1" dt msg pre
  dt="$(printf '%s' "$row" | sed -n 's/^{"dt":"\([^"]*\)".*/\1/p')"
  msg="${row#*"$ROLLBACK_MARKER"}"
  pre="${msg%%bwrap_err=*}"
  printf '%s ' "${dt:-?}"
  printf '%s' "$pre" | grep -oE '(^| )(rc|ms|cstate|err_chars)=[^ ]+' | tr -d ' ' | tr '\n' ' '
  printf '\n'
}

# (a) RECURRENCE first. A rollback row tagged ci-deploy is itself proof the marker ran, so
# FAIL is sound regardless of what the liveness query says.
rollback_rows="$(fetch_rows "$ROLLBACK_MARKER")" || {
  echo "TRANSIENT: Better Stack query failed (rollback marker) -- auth/config/network" >&2; exit 2; }
offending="$(printf '%s\n' "$rollback_rows" | grep -F "$CI_DEPLOY_GREP_MARKER" | grep -F "$ROLLBACK_MARKER" || true)"
rollback_count="$(printf '%s\n' "$offending" | grep -c . || true)"

if [[ "$rollback_count" -ge 1 ]]; then
  echo "FAIL: ${rollback_count} bwrap deploy-gate rollback(s) in ${WINDOW} -- the next occurrence has named itself. Trusted fields per row (rc: 1 = bwrap's own failure or no such container, 126/127 = could not exec, 128+n = signalled):"
  while IFS= read -r row; do
    [[ -n "$row" ]] && printf '  %s\n' "$(trusted_fields "$row")"
  done <<<"$offending"
  echo "Read the sanitized bwrap_err for each row with:"
  echo "  doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since ${WINDOW} --grep '${ROLLBACK_MARKER}' | jq -r '.raw | fromjson | .message'"
  echo "Fix the named cause, then close #8016 by hand (arm a). This probe leaves it open."
  exit 1
fi

# (b) SOAK. Liveness = SANDBOX_PROBE_OK rows tagged ci-deploy: proof the SELF-REPORTING
# marker is on the host and ran, one per green deploy. Below MIN_DEPLOYS -> not yet.
ok_rows="$(fetch_rows "$OK_MARKER")" || {
  echo "TRANSIENT: Better Stack query failed (SANDBOX_PROBE_OK liveness) -- auth/config/network" >&2; exit 2; }
ok_count="$(printf '%s\n' "$ok_rows" | grep -F "$CI_DEPLOY_GREP_MARKER" | grep -cF "$OK_MARKER" || true)"

if [[ "$ok_count" -lt "$MIN_DEPLOYS" ]]; then
  echo "TRANSIENT: ${ok_count} SANDBOX_PROBE_OK row(s) in ${WINDOW}, need >= ${MIN_DEPLOYS} -- the marker is live but the soak is not yet exercised enough to call the 2026-09-09 occurrence environmental; not PASS" >&2
  exit 2
fi

echo "PASS: ${ok_count} deploys with the self-reporting probe live in ${WINDOW} and zero bwrap rollbacks -- arm (b): the 2026-09-09 occurrence did not recur across >= ${MIN_DEPLOYS} deploys and is closed as environmental. If it recurs later, the DEPLOY_ROLLBACK line now carries rc/ms/cstate/err_chars/bwrap_err; reopen with that evidence."
exit 0
