#!/usr/bin/env bash
# #8516 — static shape gate for the dead-probe heartbeat sibling of
# logtail_exploration_alert.inngest_luks_wrong_volume.
#
# The wrong-volume alert runs on_missing_data = "treat_as_zero": a dead
# SOLEUR_INNGEST_SERVER_PROBE pipeline (emitter / Vector allowlist / sink) reads as ZERO
# wrong-volume rows — silently healthy while a rollback onto plaintext hcloud_volume.inngest_redis
# goes unpaged. The remedy is a dead-man's-switch heartbeat mirroring DP-10
# (betteruptime_heartbeat.workspaces_luks) sized to the probe's HOURLY emission cadence
# (inngest-server-probe.timer: OnUnitActiveSec=1h + AccuracySec=1min), born paused per the
# recorded DP-10/#6210 discipline, with its URL provisioned in Doppler and BOTH resources riding
# the per-merge -target= allow-list in apply-web-platform-infra.yml (the #8754 git_data_prd
# precedent — terraform-target-parity.test.ts requires it), plus an honest
# heartbeat-manifest.ts row (feeder.kind = "none" + tracking_issue + arming_pending).
#
# Every grep is anchored on a syntactic construct, never a bare token that also appears in a
# comment (cq-assert-anchor-not-bare-token), and resource assertions bind to the extracted
# block, not the file (a same-named attribute elsewhere must not satisfy them).
#
# Run: bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPTIME="$DIR/uptime-alerts.tf"
ALERTS="$DIR/betterstack-logs-alerts.tf"
WORKFLOW="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"
MANIFEST="$DIR/../../../plugins/soleur/lib/heartbeat-manifest.ts"

passes=0
fails=0
ok()   { passes=$((passes + 1)); echo "[ok] $1"; }
no()   { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }
have() { grep -qE -- "$1" "$2"; }
has()  { grep -qE -- "$2" <<<"$1"; }

# ---------------------------------------------------------------------------
# (a) The heartbeat resource exists, extracted as a bounded block.
hb_block="$(awk '/^resource "betteruptime_heartbeat" "inngest_server_probe"/{p=1} p{print} p&&/^}/{exit}' "$UPTIME")"
if [ -n "$hb_block" ]; then
  ok "betteruptime_heartbeat.inngest_server_probe exists (hourly dead-probe switch)"
else
  no "uptime-alerts.tf must declare betteruptime_heartbeat.inngest_server_probe (DP-10 mirror for the probe cadence)"
fi

# (b) Budget sized to the hourly emission: period=3600 covers the 1h timer; grace=1800 lets ONE
#     skipped emission page (a missed hourly row IS the anomaly) while absorbing AccuracySec
#     jitter + ingest latency. Deadline = 5400 s.
if has "$hb_block" '^[[:space:]]*period[[:space:]]*=[[:space:]]*3600[[:space:]]*$'; then
  ok "heartbeat period = 3600 (one probe emission interval)"
else
  no "inngest_server_probe must declare period = 3600 (the hourly emission cadence)"
fi
if has "$hb_block" '^[[:space:]]*grace[[:space:]]*=[[:space:]]*1800[[:space:]]*$'; then
  ok "heartbeat grace = 1800 (one missed emission pages; jitter absorbed)"
else
  no "inngest_server_probe must declare grace = 1800"
fi

# (c) Born paused + drift-protected (verbatim DP-10 birth — an unfed unpaused heartbeat pages
#     falsely; Better Stack expects pings from creation, inngest.tf heartbeat comment).
if has "$hb_block" '^[[:space:]]*paused[[:space:]]*=[[:space:]]*true[[:space:]]*$'; then
  ok "heartbeat born paused = true (no false page before the feeder lands)"
else
  no "inngest_server_probe must be born paused = true (DP-10 shape)"
fi
if has "$hb_block" 'ignore_changes[[:space:]]*=[[:space:]]*\[paused\]'; then
  ok "lifecycle { ignore_changes = [paused] } (arming is never reverted by apply)"
else
  no "inngest_server_probe must carry lifecycle { ignore_changes = [paused] }"
fi

# (d) Alert routing mirrors DP-10: email on, noisy channels off, paid-tier policy gated on the var.
if has "$hb_block" '^[[:space:]]*email[[:space:]]*=[[:space:]]*true[[:space:]]*$'; then
  ok "heartbeat email = true"
else
  no "inngest_server_probe must declare email = true"
fi
if has "$hb_block" '^[[:space:]]*call[[:space:]]*=[[:space:]]*false' \
  && has "$hb_block" '^[[:space:]]*sms[[:space:]]*=[[:space:]]*false' \
  && has "$hb_block" '^[[:space:]]*push[[:space:]]*=[[:space:]]*false'; then
  ok "call/sms/push all false (ops@ email only, like DP-10)"
else
  no "inngest_server_probe must set call/sms/push = false"
fi
if has "$hb_block" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier[[:space:]]*\?[[:space:]]*betteruptime_policy\.uptime\[0\]\.id[[:space:]]*:[[:space:]]*null'; then
  ok "policy_id gated on var.betterstack_paid_tier (null on free tier — provider rejects the linkage)"
else
  no "inngest_server_probe must gate policy_id on var.betterstack_paid_tier like its siblings"
fi

# (e) The Doppler URL secret pairs to THIS heartbeat's URL.
sec_block="$(awk '/^resource "doppler_secret" "inngest_server_probe_heartbeat_url"/{p=1} p{print} p&&/^}/{exit}' "$UPTIME")"
if [ -n "$sec_block" ]; then
  ok "doppler_secret.inngest_server_probe_heartbeat_url exists"
else
  no "uptime-alerts.tf must declare doppler_secret.inngest_server_probe_heartbeat_url"
fi
if has "$sec_block" '^[[:space:]]*name[[:space:]]*=[[:space:]]*"INNGEST_SERVER_PROBE_HEARTBEAT_URL"'; then
  ok "secret name = INNGEST_SERVER_PROBE_HEARTBEAT_URL"
else
  no "the secret must be named INNGEST_SERVER_PROBE_HEARTBEAT_URL"
fi
if has "$sec_block" 'value[[:space:]]*=[[:space:]]*betteruptime_heartbeat\.inngest_server_probe\.url'; then
  ok "secret value is THIS heartbeat's url (not a sibling's)"
else
  no "the secret value must be betteruptime_heartbeat.inngest_server_probe.url"
fi
if has "$sec_block" 'config[[:space:]]*=[[:space:]]*"prd"' && has "$sec_block" 'project[[:space:]]*=[[:space:]]*"soleur"'; then
  ok "secret lands in soleur/prd (same sink as inngest_heartbeat_url_prd)"
else
  no "the secret must target project=soleur config=prd"
fi
if has "$sec_block" 'visibility[[:space:]]*=[[:space:]]*"masked"' \
  && has "$sec_block" 'ignore_changes[[:space:]]*=[[:space:]]*\[value\]'; then
  ok "secret masked + value drift-protected"
else
  no "the secret must be visibility=masked with ignore_changes=[value]"
fi

# (f) Task 1 of #8516: the issue is cited inside the wrong-volume alert's own comment block.
#     Window = the comment lines immediately preceding the resource (position-free — the
#     citation may sit anywhere in that block).
res_line="$(grep -n '^resource "logtail_exploration_alert" "inngest_luks_wrong_volume"' "$ALERTS" | cut -d: -f1)"
cite_window=""
if [ -n "$res_line" ]; then
  cite_window="$(head -n "$((res_line - 1))" "$ALERTS" | awk '/^[[:space:]]*#/{buf=buf $0 ORS; next} /^[[:space:]]*$/{next} {buf=""} END{printf "%s", buf}')"
fi
if has "$cite_window" '#8516' && has "$cite_window" 'treat_as_zero' && has "$cite_window" 'inngest_server_probe'; then
  ok "inngest_luks_wrong_volume cites #8516 and names the treat_as_zero blind spot + heartbeat sibling"
else
  no "the comment block above logtail_exploration_alert.inngest_luks_wrong_volume must cite #8516, treat_as_zero, and the heartbeat sibling"
fi
alert_block="$(awk '/^resource "logtail_exploration_alert" "inngest_luks_wrong_volume"/{p=1} p{print} p&&/^}/{exit}' "$ALERTS")"
if has "$alert_block" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"'; then
  ok "the alert still carries on_missing_data = \"treat_as_zero\" (the property the citation documents)"
else
  no "inngest_luks_wrong_volume must keep on_missing_data = \"treat_as_zero\" (changing it is a different design)"
fi

# (g) Both resources ride the per-merge -target= allow-list (delivery path per #8754 precedent;
#     terraform-target-parity.test.ts requires coverage but this pins the exact addresses).
if have '-target=betteruptime_heartbeat\.inngest_server_probe' "$WORKFLOW"; then
  ok "apply-web-platform-infra.yml targets betteruptime_heartbeat.inngest_server_probe"
else
  no "the merge-push apply allow-list must carry -target=betteruptime_heartbeat.inngest_server_probe"
fi
if have '-target=doppler_secret\.inngest_server_probe_heartbeat_url' "$WORKFLOW"; then
  ok "apply-web-platform-infra.yml targets doppler_secret.inngest_server_probe_heartbeat_url"
else
  no "the merge-push apply allow-list must carry -target=doppler_secret.inngest_server_probe_heartbeat_url"
fi
if have '-target=.*inngest_server_probe' "$WORKFLOW" \
  && ! grep -q 'OPERATOR_APPLIED_EXCLUSIONS.*inngest_server_probe' "$WORKFLOW"; then
  ok "neither new address hides in OPERATOR_APPLIED_EXCLUSIONS (exclusion = never applied)"
else
  no "inngest_server_probe must ride -target, not OPERATOR_APPLIED_EXCLUSIONS"
fi

# (h) The heartbeat-manifest row is honest: discovered ⊆ manifest (ADR-117 parity) with a
#     declared unfed state + tracked arming.
mf_window="$(grep -A 30 'name: "inngest_server_probe"' "$MANIFEST" | head -30)"
if has "$mf_window" 'name:[[:space:]]*"inngest_server_probe"'; then
  ok "heartbeat-manifest.ts carries an inngest_server_probe row (discovered⊆manifest parity)"
else
  no "heartbeat-manifest.ts MANIFEST must carry name: \"inngest_server_probe\""
fi
if has "$mf_window" 'kind:[[:space:]]*"none"' && has "$mf_window" 'INNGEST_SERVER_PROBE_HEARTBEAT_URL'; then
  ok "feeder declared kind \"none\" + url_secret INNGEST_SERVER_PROBE_HEARTBEAT_URL (honest-unfed)"
else
  no "the row must declare feeder kind \"none\" with url_secret INNGEST_SERVER_PROBE_HEARTBEAT_URL"
fi
if has "$mf_window" 'tracking_issue:[[:space:]]*[0-9]+' && has "$mf_window" 'arming_pending'; then
  ok "tracking_issue + arming_pending present (deferred capability is tracked, not silent)"
else
  no "the row must carry a positive tracking_issue and an arming_pending block (wg-when-deferring-a-capability)"
fi

# Anti-vacuity: exact assertion count — deleting a block must not leave the suite green.
EXPECTED_PASSES=21
if [ "$passes" -ne "$EXPECTED_PASSES" ]; then
  no "count: ${passes} assertions passed, expected exactly ${EXPECTED_PASSES} — a block of cases was deleted or added without moving the number"
fi

echo ""
echo "=== inngest-server-probe-heartbeat.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
