#!/usr/bin/env bash
# #6604 — SSH-free discriminating Sentry emit for the /workspaces LUKS at-rest drift class.
#
# Mirrors cron-egress-enforce-probe.sh's emit boundary, with TWO deliberate #6604 corrections:
#
#  DP-9 (baked-DSN-first): cron-egress-enforce-probe.sh resolves the DSN via
#  `doppler secrets get` ONLY. Copying that verbatim reintroduces the exact circular trap this
#  emit exists to page on — the "Doppler unreachable ⇒ passphrase absent ⇒ mapper never opens"
#  mode would lose its DSN by the SAME cause and go dark. So this reads the BAKED DSN first
#  (/etc/default/luks-monitor, written root:root 0600 by cloud-init.yml), and only falls back to
#  Doppler if the bake is somehow empty. The bake survives a total Doppler outage.
#
#  DP-8 (feature+op tags): the Sentry drift PAGE depends ENTIRELY on the direct-curl envelope
#  matching the sentry_issue_alert filter (feature=workspaces-luks ∧ op IS_IN workspaces-luks-drift)
#  — Vector is Better-Stack-only and never reaches Sentry. cron-egress-enforce-probe.sh sets only
#  stage/host_id/probe_result, which would NOT match. This envelope carries feature/op (modelled on
#  the ghcr envelope, soleur-host-bootstrap.sh:185) PLUS the nine discriminating fields so the
#  competing failure modes are told apart in ONE event (§2.9.2 blind-surface).
#
# The nine discriminating fields (read from the WL_* environment the caller exports):
#   device_type mount_source mapper_present luks_open_result header_uuid_match
#   cryptsetup_unit_result doppler_reachable mountpoint_ok host reason
#
# Usage:  WL_REASON=<slug> WL_DEVICE_TYPE=... [WL_LEVEL=fatal|warning] \
#           bash workspaces-luks-emit.sh
#         (or `source` it and call `workspaces_luks_emit`). ALWAYS returns 0 — a paging emit must
#         never itself brick a boot or a cutover step (fail-open, like _sentry_emit).

# Strip `"` and `\` (JSON-structural) then any non-printable BEFORE interpolation into the Sentry
# body — host id is cloud-metadata, not attacker-controlled, but a stray backslash/newline would
# corrupt the envelope.
# shellcheck disable=SC1003  # '"\\' deletes " and \ (JSON-structural) — matches cron-egress-enforce-probe.sh
_wl_scrub() { printf '%s' "${1:-}" | tr -d '"\\' | tr -cd '[:print:]'; }

workspaces_luks_emit() {
  ( set +e
    local level dsn key shost proj host body
    level="$(_wl_scrub "${WL_LEVEL:-fatal}")"
    [ -n "$level" ] || level=fatal

    # DP-9: BAKED DSN first (survives a Doppler outage — the exact mode this pages on), Doppler last.
    dsn=""
    if [ -r /etc/default/luks-monitor ]; then
      # shellcheck disable=SC1091
      . /etc/default/luks-monitor 2>/dev/null || true
      dsn="${SOLEUR_SENTRY_DSN:-}"
    fi
    if [ -z "$dsn" ]; then
      dsn=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
            || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
            || true)
    fi
    [ -n "$dsn" ] || return 0

    key=$(printf '%s' "$dsn" | sed -E 's#https://([^@]+)@.*#\1#')
    shost=$(printf '%s' "$dsn" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
    proj=$(printf '%s' "$dsn" | sed -E 's#.*/([0-9]+)$#\1#')
    host="$(_wl_scrub "${WL_HOST:-$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) )}")"

    # feature/op are the sentry_issue_alert filter keys (DP-8). The nine fields discriminate the
    # failure modes; every value is scrubbed of JSON-structural bytes.
    body=$(printf '{"message":"workspaces LUKS at-rest drift","level":"%s","logger":"luks-monitor","tags":{"feature":"workspaces-luks","op":"workspaces-luks-drift","device_type":"%s","mount_source":"%s","mapper_present":"%s","luks_open_result":"%s","header_uuid_match":"%s","cryptsetup_unit_result":"%s","doppler_reachable":"%s","mountpoint_ok":"%s","host":"%s","reason":"%s"}}' \
      "$level" \
      "$(_wl_scrub "${WL_DEVICE_TYPE:-unknown}")" \
      "$(_wl_scrub "${WL_MOUNT_SOURCE:-unknown}")" \
      "$(_wl_scrub "${WL_MAPPER_PRESENT:-unknown}")" \
      "$(_wl_scrub "${WL_LUKS_OPEN_RESULT:-unknown}")" \
      "$(_wl_scrub "${WL_HEADER_UUID_MATCH:-unknown}")" \
      "$(_wl_scrub "${WL_CRYPTSETUP_UNIT_RESULT:-unknown}")" \
      "$(_wl_scrub "${WL_DOPPLER_REACHABLE:-unknown}")" \
      "$(_wl_scrub "${WL_MOUNTPOINT_OK:-unknown}")" \
      "$host" \
      "$(_wl_scrub "${WL_REASON:-unspecified}")")

    curl -m 10 --retry 3 -sf -X POST "https://$shost/api/$proj/store/" \
      -H 'Content-Type: application/json' \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$key" \
      -d "$body" >/dev/null 2>&1 || true
  ) || true
  return 0
}

# Direct-exec entrypoint (the sourced form calls workspaces_luks_emit directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  workspaces_luks_emit
fi
