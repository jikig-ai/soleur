#!/usr/bin/env bash
# #6604 — structural gates for the /workspaces LUKS drift observability plumbing (Phase 2).
# Asserts the emit envelope carries the sentry-alert filter tags (DP-8) and reads the BAKED DSN
# first (DP-9), the daily probe reads the passphrase via the pinned scoped-config form (R9) and
# never `doppler run/download --config prd_workspaces_luks`, the cadence is DAILY (not a 5-min
# poll), and the Vector tag + Sentry alert + heartbeat are wired. Every grep is anchored on a
# syntactic construct, never a bare token that also appears in a comment (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/luks-monitor.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$DIR/workspaces-luks-emit.sh"
PROBE="$DIR/luks-monitor.sh"
SERVICE="$DIR/luks-monitor.service"
TIMER="$DIR/luks-monitor.timer"
VECTOR="$DIR/vector.toml"
BOOT="$DIR/soleur-host-bootstrap.sh"
SENTRY="$DIR/sentry/issue-alerts.tf"
UPTIME="$DIR/uptime-alerts.tf"

passes=0
fails=0
ok()   { passes=$((passes + 1)); echo "[ok] $1"; }
no()   { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }
have() { grep -qE "$1" "$2"; }

# (a) Vector allowlist carries the luks-monitor tag as a quoted list member (not a comment).
if have '^[[:space:]]*"luks-monitor",[[:space:]]*$' "$VECTOR"; then
  ok "vector.toml include_matches.SYSLOG_IDENTIFIER contains \"luks-monitor\""
else
  no "vector.toml must list \"luks-monitor\", in include_matches.SYSLOG_IDENTIFIER"
fi

# (b) The emit envelope carries BOTH filter tags (DP-8) — the sentry_issue_alert filter_match=all
#     requires both, and Vector never reaches Sentry, so the page depends on this envelope.
if have '"feature":"workspaces-luks"' "$EMIT" && have '"op":"workspaces-luks-drift"' "$EMIT"; then
  ok "workspaces-luks-emit.sh envelope carries feature=workspaces-luks AND op=workspaces-luks-drift (DP-8)"
else
  no "workspaces-luks-emit.sh must carry BOTH feature=workspaces-luks and op=workspaces-luks-drift tags"
fi

# (b2) All nine discriminating fields are present in the envelope.
missing=""
for f in device_type mount_source mapper_present luks_open_result header_uuid_match \
         cryptsetup_unit_result doppler_reachable mountpoint_ok host reason; do
  have "\"$f\":\"%s\"" "$EMIT" || missing="$missing $f"
done
if [ -z "$missing" ]; then
  ok "workspaces-luks-emit.sh envelope carries all nine discriminating fields"
else
  no "workspaces-luks-emit.sh envelope missing discriminating field(s):$missing"
fi

# (b3) DP-9: the emit reads the BAKED /etc/default/luks-monitor DSN BEFORE any `doppler secrets get`.
baked_ln=$(grep -nF '/etc/default/luks-monitor' "$EMIT" | head -1 | cut -d: -f1 || true)
dop_ln=$(grep -nE 'doppler secrets get SENTRY_DSN' "$EMIT" | head -1 | cut -d: -f1 || true)
if [ -n "$baked_ln" ] && { [ -z "$dop_ln" ] || [ "$baked_ln" -lt "$dop_ln" ]; }; then
  ok "workspaces-luks-emit.sh reads the BAKED DSN before any Doppler fallback (DP-9)"
else
  no "workspaces-luks-emit.sh must read /etc/default/luks-monitor BEFORE the doppler secrets get fallback (DP-9; baked=$baked_ln doppler=$dop_ln)"
fi

# (c) R9: the probe reads the passphrase via the PINNED scoped-config form, never doppler run/download.
if have "doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks" "$PROBE"; then
  ok "luks-monitor.sh reads WORKSPACES_LUKS_KEY via the pinned 'secrets get --config prd_workspaces_luks' form (R9)"
else
  no "luks-monitor.sh must read WORKSPACES_LUKS_KEY via 'doppler secrets get … --plain --config prd_workspaces_luks' (R9)"
fi
if grep -qE 'doppler (run|secrets download)[^\n]*--config prd_workspaces_luks' "$PROBE"; then
  no "luks-monitor.sh must NEVER use 'doppler run/download --config prd_workspaces_luks' (R9 CWE-522 hole)"
else
  ok "luks-monitor.sh never uses doppler run/download against prd_workspaces_luks (R9)"
fi

# (d) The escrow re-test uses luksOpen --test-passphrase against the real device.
if have 'cryptsetup luksOpen --test-passphrase --key-file -' "$PROBE"; then
  ok "luks-monitor.sh escrow proof uses 'cryptsetup luksOpen --test-passphrase --key-file -'"
else
  no "luks-monitor.sh must use 'cryptsetup luksOpen --test-passphrase --key-file -' for the escrow proof"
fi

# (e) DAILY cadence, not a 5-min poll.
if have '^OnCalendar=daily$' "$TIMER"; then
  ok "luks-monitor.timer fires OnCalendar=daily (not a 5-min poll)"
else
  no "luks-monitor.timer must fire OnCalendar=daily"
fi
if grep -qE 'OnUnitActiveSec|OnCalendar=\*:0/5|OnCalendar=minutely' "$TIMER"; then
  no "luks-monitor.timer must NOT be a minute/5-min poll (the mount state is boot-immutable)"
else
  ok "luks-monitor.timer is not a sub-daily poll"
fi

# (f) The service tags journald as luks-monitor (else Vector never sees the unit's own stderr).
if have '^SyslogIdentifier=luks-monitor$' "$SERVICE"; then
  ok "luks-monitor.service sets SyslogIdentifier=luks-monitor"
else
  no "luks-monitor.service must set SyslogIdentifier=luks-monitor"
fi

# (g) LOG_TAG is a REAL assignment (the drift-fixture contract).
if have '^LOG_TAG="luks-monitor"$' "$PROBE"; then
  ok "luks-monitor.sh assigns LOG_TAG=\"luks-monitor\" (drift-fixture contract)"
else
  no "luks-monitor.sh must assign LOG_TAG=\"luks-monitor\" as a real assignment"
fi

# (h) The Sentry drift alert filters on BOTH tags the emit sets.
if have 'resource "sentry_issue_alert" "workspaces_luks_drift"' "$SENTRY" \
  && have 'value = "workspaces-luks"' "$SENTRY" \
  && have 'value = "workspaces-luks-drift"' "$SENTRY"; then
  ok "sentry_issue_alert.workspaces_luks_drift filters feature=workspaces-luks AND op=workspaces-luks-drift"
else
  no "sentry/issue-alerts.tf must declare sentry_issue_alert.workspaces_luks_drift filtering both tags"
fi

# (i) The daily-probe heartbeat resource exists (the dead-probe switch — P1-4).
if have 'resource "betteruptime_heartbeat" "workspaces_luks"' "$UPTIME"; then
  ok "betteruptime_heartbeat.workspaces_luks exists (daily dead-probe switch)"
else
  no "uptime-alerts.tf must declare betteruptime_heartbeat.workspaces_luks"
fi

# (j) The baked structural gate carries RequiresMountsFor=/mnt/data + chattr +i (C2).
if have 'RequiresMountsFor=/mnt/data' "$BOOT" && have 'chattr \+i' "$BOOT"; then
  ok "soleur-host-bootstrap.sh bakes the structural gate (RequiresMountsFor=/mnt/data + chattr +i)"
else
  no "soleur-host-bootstrap.sh must bake RequiresMountsFor=/mnt/data + chattr +i (C2 structural gate)"
fi

echo ""
echo "=== luks-monitor.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
