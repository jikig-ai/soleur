#!/usr/bin/env bash
# D11 — post-apply liveness assert for the registry-luks-recut dispatch (#6929).
#
# WHY THIS IS NOT A NAIVE `status == "up"` POLL
# ---------------------------------------------
# The store volume is DESTROYED at apply-return, so there is no rollback target: the only thing
# this gate can still do is tell the operator the truth about whether the registry came back.
# That makes a FALSE GREEN the worst possible outcome — worse than no gate.
#
# `betteruptime_heartbeat.registry_prd` is period=60 grace=30, so for 90 SECONDS after the old
# host dies the monitor still reports the DEAD host's residual `up`. And the heartbeat API
# exposes NO `last_ping_at`, so `up` ALONE IS NEVER EVIDENCE OF A NEW BEAT. A poll that starts
# at apply-return and returns on the first `up` would go green over a registry that never came
# back, every time, deterministically.
#
# So this script requires a TRANSITION, not a level:
#   Phase A — establish that the residual window has passed. Either observe a NON-`up` sample
#             (the old beat has aged out — fast path, and proof the monitor is live), or wait
#             out the full period+grace. Whichever comes first.
#   Phase B — only then poll for `up`. That `up` can only have been produced by a beat sent
#             AFTER the residual window, i.e. by the NEW host.
#
# Precedent for heartbeat gating being legitimate when done this way: `arm_one` in
# apps/web-platform/infra/arm-heartbeats.sh, which likewise refuses to accept a level and
# watches for a real beat. (It lived in .github/workflows/apply-web-platform-infra.yml until
# #7587 extracted it; that workflow now only invokes the script.) (The `registry-host-replace` job carries a recorded decision that its
# own best-effort status step is INFORMATIONAL and MUST NOT gate — that note is about a naive
# level read during a fresh boot, which is exactly what Phase A fixes.)
#
# `paused` is a DISTINCT failure, not "not yet up": a paused monitor can never reach `up`, so
# polling on would burn the full deadline and then report the wrong cause.
#
# FAIL-CLOSED on an unreadable token, an unresolvable heartbeat id, or an API error. A gate that
# cannot read its own signal reports failure, never success.
#
# Usage:
#   scripts/registry-heartbeat-poll.sh <tfstate-json> [heartbeat-address]
#
# Env:
#   BETTERSTACK_API_TOKEN   (required) — the Uptime mgmt API token. NOTE this is a DIFFERENT
#                           secret from betterstack-query.sh's BETTERSTACK_QUERY_* ClickHouse
#                           connection creds, and from the host-side INGEST-only
#                           BETTERSTACK_LOGS_TOKEN. Confusing them yields a 401, i.e. a
#                           fail-closed ABORT — loud, not silent.
#   REGISTRY_HB_RESIDUAL_S  (default 150) — Phase A bound. MUST STRICTLY EXCEED period+grace
#                           (60+30=90); see the clock-skew note in Phase A. Overridable only as
#                           a TEST SEAM — lowering it in production silently re-arms the
#                           false-green this script exists to prevent, and
#                           tests/scripts/test-registry-heartbeat-poll.sh pins the default.
#   REGISTRY_HB_DEADLINE_S  (default 480) — Phase B bound (8 min). MUST stay strictly below the
#                           job's timeout-minutes: 30 so this diagnostic wins over an opaque
#                           GitHub cancellation.
#   REGISTRY_HB_INTERVAL_S  (default 10)  — poll interval.
#   REGISTRY_HB_STATUS_CMD  (test seam) — command invoked with the heartbeat id; must echo the
#                           status string. Defaults to a curl against the Better Stack API.
#   REGISTRY_HB_SLEEP_CMD   (test seam) — defaults to `sleep`.

set -uo pipefail

TFSTATE="${1-}"
HB_ADDR="${2-betteruptime_heartbeat.registry_prd}"

# 150 = period(60) + grace(30) + 60s clock-skew margin. The margin is LOAD-BEARING, not padding:
# this script's timer starts at apply-return, but the old host's LAST beat may have been sent
# slightly AFTER that instant (the host dies over a few seconds, not atomically). A bound of
# exactly 90 would therefore expire while the residual `up` is still legitimately in force, and
# Phase B would read that residual as the new host's beat — the precise false-green this whole
# script exists to prevent. Do not lower this to "the real period+grace".
RESIDUAL_S="${REGISTRY_HB_RESIDUAL_S:-150}"
DEADLINE_S="${REGISTRY_HB_DEADLINE_S:-480}"
INTERVAL_S="${REGISTRY_HB_INTERVAL_S:-10}"
SLEEP_CMD="${REGISTRY_HB_SLEEP_CMD:-sleep}"

die() { echo "::error::registry-heartbeat-poll: $*" >&2; exit 1; }

for v in RESIDUAL_S DEADLINE_S INTERVAL_S; do
  if [[ ! "${!v}" =~ ^[1-9][0-9]*$ ]]; then
    die "$v must be a positive integer (got '${!v}')."
  fi
done

[[ -n "$TFSTATE" ]] || die "usage: registry-heartbeat-poll.sh <tfstate-json> [heartbeat-address]"
[[ -f "$TFSTATE" ]] || die "tfstate JSON not found: ${TFSTATE}"

# Resolve the heartbeat id from TFSTATE, never from a name filter. A name filter would silently
# bind to whichever monitor happens to match the string today; the state address is the identity
# terraform itself manages.
HB_ID=$(jq -r --arg a "$HB_ADDR" \
  '.values.root_module.resources[]? | select(.address==$a) | .values.id' "$TFSTATE" 2>/dev/null)
if [[ -z "$HB_ID" || "$HB_ID" == "null" ]]; then
  die "heartbeat address ${HB_ADDR} not found in ${TFSTATE} — cannot verify the registry came back. Refusing to report success."
fi

if [[ -z "${REGISTRY_HB_STATUS_CMD:-}" ]]; then
  [[ -n "${BETTERSTACK_API_TOKEN:-}" ]] || die "BETTERSTACK_API_TOKEN unset — cannot read heartbeat ${HB_ID}. This is the Uptime mgmt API token, NOT BETTERSTACK_QUERY_* and NOT the host-side ingest-only BETTERSTACK_LOGS_TOKEN."
  echo "::add-mask::${BETTERSTACK_API_TOKEN}"
fi

# hb_status → echoes the status string, or "" on any failure (treated as fail-closed by callers).
hb_status() {
  if [[ -n "${REGISTRY_HB_STATUS_CMD:-}" ]]; then
    $REGISTRY_HB_STATUS_CMD "$HB_ID"
    return
  fi
  curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${BETTERSTACK_API_TOKEN}" -H 'Accept: application/json' \
    "https://uptime.betterstack.com/api/v2/heartbeats/${HB_ID}" 2>/dev/null \
    | jq -r '.data.attributes.status // empty' 2>/dev/null
}

echo "registry-heartbeat-poll: heartbeat ${HB_ID} (${HB_ADDR}); residual=${RESIDUAL_S}s deadline=${DEADLINE_S}s interval=${INTERVAL_S}s"

# ── Phase A — age out the dead host's residual `up`. ─────────────────────────────────────────
# Exit early the moment a NON-`up` sample proves the old beat has expired; otherwise wait the
# full window. Either way, everything observed after this point is attributable to a new beat.
waited=0
aged_out=0
while (( waited < RESIDUAL_S )); do
  status=$(hb_status)
  if [[ -z "$status" ]]; then
    die "GET /heartbeats/${HB_ID} failed during the residual window — cannot verify the registry came back. Refusing to report success over an unreadable signal."
  fi
  if [[ "$status" == "paused" ]]; then
    die "heartbeat ${HB_ID} is PAUSED — it can never reach 'up', so liveness cannot be established. Un-pause the monitor and re-verify the registry by hand before trusting this recut."
  fi
  if [[ "$status" != "up" ]]; then
    echo "registry-heartbeat-poll: observed status=${status} after ${waited}s — the dead host's residual beat has aged out. Entering Phase B."
    aged_out=1
    break
  fi
  $SLEEP_CMD "$INTERVAL_S"
  waited=$(( waited + INTERVAL_S ))
done

if (( aged_out == 0 )); then
  # Continuous `up` across a window that STRICTLY EXCEEDS period+grace is itself a transition
  # proof: had no new beat arrived, the old one would have expired inside this window and the
  # monitor would have flipped to `down`. This soundness argument is the ONLY thing that makes
  # the no-transition-observed path safe, and it depends entirely on RESIDUAL_S carrying the
  # skew margin above.
  echo "registry-heartbeat-poll: residual window of ${RESIDUAL_S}s elapsed with status=up throughout — which exceeds period+grace, so a beat NEWER than the old host's last one must have landed (an expired beat would have flipped the monitor to down inside this window)."
fi

# ── Phase B — require `up`, which can now only come from the NEW host. ───────────────────────
waited=0
while (( waited < DEADLINE_S )); do
  status=$(hb_status)
  if [[ -z "$status" ]]; then
    die "GET /heartbeats/${HB_ID} failed while waiting for the new host's first beat — cannot verify the registry came back."
  fi
  if [[ "$status" == "paused" ]]; then
    die "heartbeat ${HB_ID} became PAUSED while waiting for the new host's first beat — it can never reach 'up'. Un-pause and re-verify by hand."
  fi
  if [[ "$status" == "up" ]]; then
    echo "::notice::registry-heartbeat-poll: status=up after ${waited}s in Phase B — the NEW registry host is beating. Liveness established."
    exit 0
  fi
  $SLEEP_CMD "$INTERVAL_S"
  waited=$(( waited + INTERVAL_S ))
done

# Never reached `up`. Name BOTH failure modes and how to tell them apart — the remediation
# differs, and one of them can never self-heal.
cat >&2 <<EOF
::error::registry-heartbeat-poll: heartbeat ${HB_ID} never reached 'up' within ${DEADLINE_S}s of the residual window closing. The store volume is already destroyed, so there is no rollback — the registry is DARK and GHCR fallback is serving pulls. Two causes, and they need DIFFERENT remedies:

  (1) blkid-arm FATAL — cloud-init found a device that is neither empty nor crypto_LUKS and
      refused it ("refusing-non-luks-device"). The volume is now crypto_LUKS, so a boot flake
      here is recoverable with 'registry-host-replace' — the do-not-use warning on that dispatch
      applies ONLY to a still-PLAINTEXT volume.

  (2) reason=device-absent — the attachment landed after the server, cloud-init's 60s device
      wait logged "refusing to luksFormat/mount a missing device" and CONTINUED, consuming the
      per-instance runcmd. The reopen unit then refuses to format a raw device and the zot
      mount-gate FATALs forever. This host will NEVER self-heal; a FULL RECUT is required.

  Discriminate with:
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK
EOF
exit 1
