#!/usr/bin/env bash
# Follow-through soak for #5934 (post-deploy non-recurrence of the char-device
# .git/config.lock worktree-creation wedge; AC10 of the durable-fix plan).
#
# PR (#5934) ships the durable substrate remediation: a privileged, host-side,
# quiescent char-device sweep (git-lock-chardevice-sweep.sh, ADR-081) that clears
# any residual CHARACTER-DEVICE config.lock on /mnt/data/workspaces BEFORE the
# container's agents start, plus the sharpened in-sandbox forensic
# (worktree-manager.sh: SOLEUR_GIT_LOCK_UNREMOVABLE ... type=chardevice rdev=…).
#
# The regression signal is an in-sandbox UNREMOVABLE char-device event: a wedge
# that reached a LIVE Concierge session despite the pre-`docker run` sweep. Its
# ABSENCE across the soak window is the empirical test of the plan's claim that a
# quiescent host-side sweep durably preempts the wedge (and that #5912's lockless
# writer becomes dead-code insurance rather than a load-bearing path).
#
# Because the directive's `earliest=` gates this to the first sweep >=7d after the
# deploy, the rolling statsPeriod window starts AFTER the deploy — so any matching
# event in-window is a genuine post-fix recurrence, not pre-fix noise.
#
# PLUMBING NOTE (honest limitation): this queries Sentry for the in-sandbox
# sentinel, which requires the orchestrator's captured-stdout → Sentry mirror to be
# live. If that mirror is not yet wired, a 0-count is a LOWER BOUND, not a proof;
# the sweep's own host-side SOLEUR_CHARDEV_SWEEP_* markers (vector.toml → journald →
# Better Stack) are the complementary host-side signal. A recurrence that DOES reach
# Sentry fails this soak loudly, which is the value here.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero char-device UNREMOVABLE events in-window; sweeper closes #5934)
#   1 = FAIL       (>=1 event found; the wedge recurred — sweeper comments, leaves open)
#   2 = TRANSIENT  (Sentry API unreachable / unparseable; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml as
#   secrets.SENTRY_IAC_AUTH_TOKEN).

set -uo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"

ORG="jikigai-eu"
API="https://sentry.io/api/0"
# statsPeriod window: default 7d matches AC10's soak; overridable for a manual run.
STATS_PERIOD="${CHARDEVICE_SOAK_STATS_PERIOD:-7d}"

# Pin to the char-device wedge signature: the loud in-sandbox sentinel AND the
# chardevice discriminator (excludes the benign regular/dir/symlink UNREMOVABLE
# forms). Both phrases must appear in the event message.
QUERY='"SOLEUR_GIT_LOCK_UNREMOVABLE" "type=chardevice"'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=${STATS_PERIOD}&per_page=10&field=title&field=timestamp&field=level"

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

EVENT_COUNT=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)

if ! [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse event count from response" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  echo "PASS: 0 char-device config.lock UNREMOVABLE events in ${STATS_PERIOD} window (durable sweep #5934 holds)"
  exit 0
fi

echo "FAIL: $EVENT_COUNT char-device config.lock UNREMOVABLE event(s) in ${STATS_PERIOD} window — the wedge recurred post-fix"
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp) (id=\(.id))"' | head -10
exit 1
