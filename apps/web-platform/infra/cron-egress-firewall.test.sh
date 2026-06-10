#!/usr/bin/env bash
# Drift-guard for the container egress firewall (#5046 PR-2).
#
# Locks the load-bearing invariants of the DOCKER-USER egress allowlist:
#   1. server.tf DELIVERS every firewall artifact (anchored on the delivery
#      construct `source = "${path.module}/<file>"` + its destination — never
#      a bare path, which false-passes when it also appears in chmod/comment
#      lines; see 2026-06-02 drift-guard learning).
#   2. triggers_replace folds BOTH the artifact hashes AND the server id
#      (hr-fresh-host-provisioning — a replaced VM must re-provision).
#   3. The apply workflow -targets the new resource in the SSH block
#      (terraform-target-parity.test.ts enforces the union; this pins the
#      specific block).
#   4. Script safety invariants: sets populate BEFORE default-drop installs
#      (availability ordering); additive-then-prune (no `flush set`);
#      fail-safe-on-empty; DNS pin + fail-loud drop logging present.
#   5. Units alarm on failure (OnFailure=) and the timer survives reboots.
#   6. cloud-init fresh-host mirror carries the artifacts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/apply-web-platform-infra.yml"
LOADER="$SCRIPT_DIR/cron-egress-nftables.sh"
RESOLVER="$SCRIPT_DIR/cron-egress-resolve.sh"
ALARM="$SCRIPT_DIR/cron-egress-alarm.sh"
ALLOWLIST="$SCRIPT_DIR/cron-egress-allowlist.txt"

PASS=0
FAIL=0

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (pattern not found in $(basename "$file"): $pattern)"
  fi
}

assert_not_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (forbidden pattern present in $(basename "$file"): $pattern)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  fi
}

assert_cmd() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description ($*)"
  fi
}

echo "--- cron-egress firewall drift-guard ---"

echo "-- artifacts exist + parse --"
for f in "$LOADER" "$RESOLVER" "$ALARM" "$ALLOWLIST" \
  "$SCRIPT_DIR/cron-egress-firewall.service" \
  "$SCRIPT_DIR/cron-egress-resolve.service" \
  "$SCRIPT_DIR/cron-egress-resolve.timer" \
  "$SCRIPT_DIR/cron-egress-alarm@.service"; do
  assert_cmd "exists: $(basename "$f")" test -f "$f"
done
assert_cmd "loader parses (bash -n)" bash -n "$LOADER"
assert_cmd "resolver parses (bash -n)" bash -n "$RESOLVER"
assert_cmd "alarm parses (bash -n)" bash -n "$ALARM"

echo "-- server.tf delivery (anchored on the file-provisioner construct) --"
assert_grep "resource exists" 'resource "terraform_data" "cron_egress_firewall"' "$SERVER_TF"
for f in cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
  cron-egress-allowlist.txt cron-egress-firewall.service \
  cron-egress-resolve.service cron-egress-resolve.timer; do
  assert_grep "delivers $f (source=)" "source += +\"\\\$\\{path\\.module\\}/$f\"" "$SERVER_TF"
  assert_grep "trigger folds $f hash" "file\\(\"\\\$\\{path\\.module\\}/$f\"\\)" "$SERVER_TF"
done
# The template unit's `@` needs its own anchors (regex-escaping differs).
assert_grep "delivers cron-egress-alarm@.service (source=)" 'source += +"\$\{path\.module\}/cron-egress-alarm@\.service"' "$SERVER_TF"
SERVER_BLOCK="$(awk '/resource "terraform_data" "cron_egress_firewall"/,/^}/' "$SERVER_TF")"
if echo "$SERVER_BLOCK" | grep -qE 'server_id += +hcloud_server\.web\.id'; then
  PASS=$((PASS + 1)); echo "  PASS: cron_egress_firewall trigger folds hcloud_server.web.id"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: cron_egress_firewall trigger does not fold hcloud_server.web.id"
fi
if echo "$SERVER_BLOCK" | grep -q 'mkdir -p /etc/soleur'; then
  PASS=$((PASS + 1)); echo "  PASS: parent dir created before file provisioners (scp does not mkdir)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: missing 'mkdir -p /etc/soleur' before file provisioners"
fi
# Live positive+negative probe (AC-P2.8 iii — the silent-green guard: nft -f
# exits 0 on an inert ruleset; only a real container probe proves enforcement).
if echo "$SERVER_BLOCK" | grep -q 'egress-probe-negative'; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply negative container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply negative container probe missing"
fi
if echo "$SERVER_BLOCK" | grep -q 'egress-probe-positive'; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply positive container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply positive container probe missing"
fi

echo "-- apply workflow SSH -target --"
assert_grep "workflow -targets cron_egress_firewall" 'target=terraform_data\.cron_egress_firewall' "$WORKFLOW"

echo "-- loader safety invariants --"
# Availability ordering: the resolve (set population) line must precede the
# default-drop install (flush chain + add rules) — proven by line order.
RESOLVE_LINE="$(grep -n '"\$RESOLVE_SCRIPT"' "$LOADER" | head -1 | cut -d: -f1)"
DROP_LINE="$(grep -n 'flush chain ip filter SOLEUR-EGRESS' "$LOADER" | head -1 | cut -d: -f1)"
if [[ -n "$RESOLVE_LINE" && -n "$DROP_LINE" && "$RESOLVE_LINE" -lt "$DROP_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: sets populate BEFORE the default-drop installs (line $RESOLVE_LINE < $DROP_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: resolve must run before the drop rules install (resolve=$RESOLVE_LINE drop=$DROP_LINE)"
fi
assert_grep "default-drop log is rate-limited (no journald self-DoS)" 'limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice' "$LOADER"
assert_grep "default-drop terminal rule present" 'counter drop comment "soleur-egress: default drop"' "$LOADER"
assert_grep "DNS pin accept rule" 'udp dport 53 ip daddr @soleur_egress_dns accept' "$LOADER"
assert_grep "DNS exfil drop is logged" 'egress-dns-exfil' "$LOADER"
assert_grep "host-gateway :8288 accept" 'tcp dport 8288 accept' "$LOADER"
assert_grep "bridge gateway derived, not hardcoded" 'docker network inspect bridge' "$LOADER"
assert_grep "IPv6 bypass guard" 'EnableIPv6' "$LOADER"
assert_grep "jump rule scoped to the bridge interface" 'iifname "\$BRIDGE_IF" counter jump SOLEUR-EGRESS' "$LOADER"
assert_not_grep "never flushes the shared DOCKER-USER chain" 'flush chain ip filter DOCKER-USER' "$LOADER"

echo "-- resolver safety invariants --"
# Anchored on the executable form (`flush set ip filter …`), not the bare
# phrase — the resolver's own comment legitimately SAYS "never flush set"
# (comment-prose false-match class, 2026-06-03 learning).
assert_not_grep "never flush-set (additive-then-prune only)" 'flush set ip filter' "$RESOLVER"
# Behavior anchors (executable constructs, NOT prose — a kept comment must
# not green a deleted code path; 2026-06-03 comment-prose learning):
assert_grep "fail-safe on empty resolution (guard construct)" 'refusing to touch the sets' "$RESOLVER"
assert_grep "additive-only tick on partial failure (PRUNE flip construct)" 'PRUNE="no-prune"' "$RESOLVER"
assert_grep "absent dynamic env counts as failed host (no prune on Doppler drift)" 'dynamic-host env .var unset' "$RESOLVER"
if grep -qF "DNS_IPS=$'8.8.8.8" "$RESOLVER"; then
  PASS=$((PASS + 1)); echo "  PASS: DNS pin always unions Docker substitution pair"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: DNS pin must unconditionally seed Docker's 8.8.8.8/8.8.4.4 substitution pair"
fi
assert_grep "container-view resolution unioned (resolver-divergence guard)" 'CONTAINER_VIEW' "$RESOLVER"
assert_grep "self-heal: re-runs loader when enforcement rules missing" 'enforcement rules missing' "$RESOLVER"
assert_grep "self-heal recursion guard (loader sets the env)" 'CRON_EGRESS_FROM_LOADER=1' "$LOADER"
assert_grep "concurrent runs serialized via flock" 'flock -w 120' "$RESOLVER"
assert_grep "BOTH drop prefixes counted toward the Sentry event" "egress-.blocked.dns-exfil.: " "$RESOLVER"
assert_grep "single atomic nft -f batch apply" 'nft -f -' "$RESOLVER"
assert_grep "Sentry Crons ok check-in (dead-timer detection)" 'sentry_checkin ok' "$RESOLVER"
assert_grep "Sentry Crons error check-in on failure" 'sentry_checkin error' "$RESOLVER"

echo "-- unit invariants --"
assert_grep "firewall unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "resolve unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "firewall unit re-asserts every boot" 'WantedBy=multi-user\.target' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "timer survives reboots (Persistent)" 'Persistent=true' "$SCRIPT_DIR/cron-egress-resolve.timer"
assert_grep "resolve runs doppler-wrapped (env for Sentry + dynamic hosts)" 'run --project soleur --config prd' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit sources the doppler token env file" 'EnvironmentFile=-/etc/default/inngest-server' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit sets HOME (doppler os.UserHomeDir requirement)" 'Environment=HOME=/root' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit bounded (no infinite activating hang)" 'TimeoutStartSec=' "$SCRIPT_DIR/cron-egress-resolve.service"

echo "-- cross-file literal parity (replicated literals drift silently) --"
SLUG_RESOLVE="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$RESOLVER" | head -1)"
SLUG_ALARM="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$ALARM" | head -1)"
if [[ -n "$SLUG_RESOLVE" && "$SLUG_RESOLVE" == "$SLUG_ALARM" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: SENTRY_SLUG identical in resolver + alarm ($SLUG_RESOLVE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: SENTRY_SLUG drift (resolver=$SLUG_RESOLVE alarm=$SLUG_ALARM)"
fi
SLUG_VAL="$(echo "$SLUG_RESOLVE" | sed -E 's/SENTRY_SLUG="([^"]+)"/\1/')"
assert_grep "Sentry monitor name matches the scripts' slug" "name += +\"$SLUG_VAL\"" "$SCRIPT_DIR/sentry/cron-monitors.tf"
# Drop-prefix parity: the resolver's journal grep must match the loader's
# nft log prefixes, else drops keep happening while the alert goes dark.
for prefix in 'egress-blocked: ' 'egress-dns-exfil: '; do
  if grep -qF "$prefix" "$LOADER" && grep -qE "egress-.blocked.dns-exfil.: " "$RESOLVER"; then
    PASS=$((PASS + 1)); echo "  PASS: drop prefix '$prefix' present in loader and covered by resolver grep"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: drop prefix '$prefix' parity broken between loader and resolver"
  fi
done

echo "-- alarm content invariants --"
assert_grep "alarm posts Sentry error check-in" 'status=error' "$ALARM"
assert_grep "alarm emails via Resend (disk-monitor precedent)" 'api\.resend\.com/emails' "$ALARM"
assert_grep "alarm email cooldown (no per-tick inbox storm)" 'EMAIL_COOLDOWN_SECS' "$ALARM"

echo "-- allowlist completeness (grep-enumerated runtime hosts) --"
for host in api.anthropic.com github.com api.github.com api.doppler.com \
  edge.api.flagsmith.com api.x.com api.linkedin.com bsky.social discord.com \
  plausible.io api.resend.com api.buttondown.com api.cloudflare.com \
  api.stripe.com api.hetzner.cloud fcm.googleapis.com \
  updates.push.services.mozilla.com web.push.apple.com \
  soleur.ai app.soleur.ai api.soleur.ai api.supabase.com; do
  # -Fxq = exact full-line literal (dots are NOT wildcards)
  if grep -Fxq -- "$host" "$ALLOWLIST"; then
    PASS=$((PASS + 1)); echo "  PASS: allowlists $host"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: allowlists $host (exact line not found)"
  fi
done
# Exact-set guard: a NEW host (the firewall's entire attack-surface dial)
# must force a deliberate edit here carrying its evidence.
HOST_COUNT="$(grep -vcE '^[[:space:]]*#|^[[:space:]]*$' "$ALLOWLIST")"
if [[ "$HOST_COUNT" -eq 22 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: allowlist host count is exactly 22"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: allowlist host count is $HOST_COUNT (expected 22 — update BOTH the allowlist and this test with evidence)"
fi
assert_not_grep "Better Stack is HOST egress (must not be in the container allowlist)" '^(logs\.)?(betterstack|betteruptime)' "$ALLOWLIST"
assert_not_grep "GHCR is HOST egress (must not be in the container allowlist)" '^ghcr\.io$' "$ALLOWLIST"

echo "-- cloud-init fresh-host mirror --"
assert_grep "cloud-init writes the loader" '/usr/local/bin/cron-egress-nftables\.sh' "$CLOUD_INIT"
assert_grep "cloud-init writes the resolver" '/usr/local/bin/cron-egress-resolve\.sh' "$CLOUD_INIT"
assert_grep "cloud-init writes the allowlist" '/etc/soleur/cron-egress-allowlist\.txt' "$CLOUD_INIT"
assert_grep "cloud-init enables the firewall unit" 'systemctl enable --now cron-egress-firewall\.service' "$CLOUD_INIT"
assert_grep "cloud-init enables the resolve timer" 'systemctl enable --now cron-egress-resolve\.timer' "$CLOUD_INIT"
assert_grep "cloud-init installs nftables" '^ *- nftables$' "$CLOUD_INIT"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
