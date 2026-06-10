#!/usr/bin/env bash
# cron-egress-nftables.sh — install the DOCKER-USER container egress firewall
# (#5046 PR-2 / cron-egress-firewall).
#
# Default-drop egress allowlist for the soleur-web-platform container (and its
# canary) on the default Docker bridge. Contains the 4 live spawn("bash")
# crons that bypass the #5018 PreToolUse hook (ADR-033 I7) and makes the
# hook's Task/Skill relax-minimal safe: a compromised cron can no longer dial
# an arbitrary host — only the grep-enumerated allowlist resolves.
#
# Design (plan §Phase 2.B, arch-confirmed):
#   - All soleur rules live in OUR OWN chain `SOLEUR-EGRESS` (table ip filter);
#     DOCKER-USER carries exactly ONE rule: `iifname "docker0" jump
#     SOLEUR-EGRESS`. Re-asserting = atomically flush+repopulate OUR chain —
#     never surgical handle math in, nor a flush of, the shared DOCKER-USER
#     chain (Docker never flushes DOCKER-USER, so the jump survives dockerd
#     restarts; a REBOOT clears nftables entirely, which is why the
#     cron-egress-firewall.service oneshot re-runs this script every boot).
#   - Container→HOST traffic (host-gateway Inngest :8288) traverses INPUT,
#     not FORWARD/DOCKER-USER — the explicit :8288 accept below is
#     belt-and-braces, not load-bearing. Host OUTPUT (cloudflared tunnel,
#     Vector→Better Stack, GHCR, apt) is never touched.
#   - ORDER MATTERS (availability): the allowlist sets are POPULATED (via
#     cron-egress-resolve.sh) BEFORE the default-drop rules install. If
#     resolution fails, this script aborts WITHOUT installing the drop —
#     fail-open-on-bootstrap is deliberate (app availability > containment;
#     the unit's OnFailure= alarm pages the operator).
set -euo pipefail

BRIDGE_IF="docker0"
LOG_TAG="cron-egress-nftables"
RESOLVE_SCRIPT="${RESOLVE_SCRIPT:-/usr/local/bin/cron-egress-resolve.sh}"

log() { echo "[$LOG_TAG] $*"; }
die() { log "ERROR: $*"; exit 1; }

command -v nft >/dev/null || die "nft binary not found (apt-get install nftables)"
ip link show "$BRIDGE_IF" >/dev/null 2>&1 || die "bridge interface $BRIDGE_IF not found"

# IPv6 bypass guard: the rules below are IPv4 (table ip). If the default
# bridge ever enables IPv6, container egress could bypass the allowlist over
# v6 — fail loudly rather than silently half-contain.
if command -v docker >/dev/null && docker network inspect bridge >/dev/null 2>&1; then
  V6="$(docker network inspect bridge -f '{{.EnableIPv6}}' 2>/dev/null || echo unknown)"
  [[ "$V6" == "false" ]] || die "default bridge EnableIPv6=$V6 — IPv6 egress would bypass the v4 allowlist"
fi

# Host-gateway address for the explicit Inngest :8288 accept. Derived, never
# hardcoded (a daemon.json bip/default-address-pools change shifts it).
BRIDGE_GW="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
[[ -n "$BRIDGE_GW" ]] || BRIDGE_GW="172.17.0.1"

# --- Phase 1: declare table/sets/chains (additive, idempotent) -----------------
# `nft -f` table declarations MERGE into existing state — safe to re-run.
# DOCKER-USER is declared too so this works even before dockerd starts
# (Docker reuses an existing chain; it never flushes DOCKER-USER).
nft -f - <<EOF
table ip filter {
  set soleur_egress_allow {
    type ipv4_addr
  }
  set soleur_egress_dns {
    type ipv4_addr
  }
  chain SOLEUR-EGRESS {
  }
  chain DOCKER-USER {
  }
}
EOF

# --- Phase 2: populate the sets BEFORE any drop rule exists --------------------
# CRON_EGRESS_FROM_LOADER=1 suppresses the resolver's enforcement self-heal
# (the rules are legitimately absent at this point — that's the availability
# ordering, not drift) so loader→resolver→loader cannot recurse.
CRON_EGRESS_FROM_LOADER=1 "$RESOLVE_SCRIPT" || die "allowlist resolution failed — NOT installing default-drop (fail-open bootstrap; OnFailure alarms)"

# --- Phase 3: (re)install our rules atomically ----------------------------------
# One transaction: flush OUR chain + add the ordered rules. First-match-wins,
# drop LAST. Everything in this chain arrived via the iifname-scoped jump, so
# per-rule iifname repeats are unnecessary.
nft -f - <<EOF
flush chain ip filter SOLEUR-EGRESS
add rule ip filter SOLEUR-EGRESS ct state established,related accept comment "soleur-egress: return traffic"
add rule ip filter SOLEUR-EGRESS oifname "$BRIDGE_IF" accept comment "soleur-egress: intra-bridge (canary<->app)"
add rule ip filter SOLEUR-EGRESS udp dport 53 ip daddr @soleur_egress_dns accept comment "soleur-egress: pinned DNS"
add rule ip filter SOLEUR-EGRESS tcp dport 53 ip daddr @soleur_egress_dns accept comment "soleur-egress: pinned DNS tcp"
add rule ip filter SOLEUR-EGRESS udp dport 53 limit rate 10/minute burst 50 packets log prefix "egress-dns-exfil: " comment "soleur-egress: dns exfil log"
add rule ip filter SOLEUR-EGRESS udp dport 53 counter drop comment "soleur-egress: dns exfil drop"
add rule ip filter SOLEUR-EGRESS tcp dport 53 limit rate 10/minute burst 50 packets log prefix "egress-dns-exfil: " comment "soleur-egress: dns exfil log tcp"
add rule ip filter SOLEUR-EGRESS tcp dport 53 counter drop comment "soleur-egress: dns exfil drop tcp"
add rule ip filter SOLEUR-EGRESS ip daddr $BRIDGE_GW tcp dport 8288 accept comment "soleur-egress: host-gateway inngest"
add rule ip filter SOLEUR-EGRESS ip daddr @soleur_egress_allow accept comment "soleur-egress: allowlist"
add rule ip filter SOLEUR-EGRESS limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice comment "soleur-egress: default drop log"
add rule ip filter SOLEUR-EGRESS counter drop comment "soleur-egress: default drop"
EOF

# --- Phase 4: ensure the single DOCKER-USER jump exists -------------------------
if ! nft list chain ip filter DOCKER-USER | grep -q 'jump SOLEUR-EGRESS'; then
  nft insert rule ip filter DOCKER-USER iifname "$BRIDGE_IF" counter jump SOLEUR-EGRESS comment '"soleur-egress: jump"'
  log "installed DOCKER-USER jump rule"
fi

log "OK: SOLEUR-EGRESS active (bridge=$BRIDGE_IF gw=$BRIDGE_GW)"
