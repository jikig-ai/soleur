#!/usr/bin/env bash
# egress-gateway-bootstrap.sh — bring up the Squid egress gateway (#9534).
#
# Idempotent, runs at cloud-init (fresh hosts) and via the terraform_data SSH
# provisioner (running web-1). Creates the dedicated bridge (a named bridge,
# so the iifname-scoped nftables legs have a stable token), the session-token
# dir (mounted rw into the app container, ro into the gateway), and the gw
# container from a digest-pinned image.
#
# Deliberately NO static credential: auth is per-session token files under
# /var/lib/soleur/egress-tokens (spec-flow review — a shared env secret has
# no writer-path and a /proc-harvest hole).
set -euo pipefail

BRIDGE_IF="soleur-egress0"
NET_NAME="soleur-egress0"
GW_NAME="soleur-egress-gw"
GW_PORT=8443
TOKEN_DIR="${EGRESS_GW_TOKEN_DIR:-/var/lib/soleur/egress-tokens}"
CONF_DIR="/usr/local/bin"
IMAGE="${EGRESS_GW_IMAGE:-ubuntu/squid@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029}"

log() { echo "[egress-gw-bootstrap] $*"; }
die() { log "ERROR: $*"; exit 1; }

command -v docker >/dev/null || die "docker not found"

# --- subnet selection (collision-safe, Kieran P2-10) ---------------------------
# A hardcoded /24 could collide with Docker's default-address-pool growth.
# Probe existing networks' subnets; skip any candidate sharing a /16 with an
# existing allocation (conservative — exact overlap math is ipaddress-shaped,
# a /16 collision test covers the realistic pool allocations).
SUBNET=""
GW_IP=""
for cand in 172.31.100.0/24 172.31.101.0/24 172.31.102.0/24 172.31.103.0/24; do
  fam="${cand%.*.*}"
  if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
    existing="$(docker network inspect "$NET_NAME" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
    SUBNET="${existing:-$cand}"
    break
  fi
  clash=0
  while read -r s; do
    [[ -n "$s" && "${s%.*.*}" == "$fam" ]] && clash=1
  done < <(docker network inspect $(docker network ls -q 2>/dev/null) -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
  if (( clash == 0 )); then SUBNET="$cand"; break; fi
done
[[ -n "$SUBNET" ]] || die "no free subnet in the 172.31.100-103.0/24 candidates"
GW_IP="${SUBNET%.*}.2"
log "subnet=$SUBNET gw_ip=$GW_IP"

# --- bridge --------------------------------------------------------------------
if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
  docker network create --subnet="$SUBNET" \
    -o com.docker.network.bridge.name=soleur-egress0 \
    "$NET_NAME" >/dev/null
  log "created bridge $NET_NAME ($BRIDGE_IF)"
fi

# --- token dir ------------------------------------------------------------------
mkdir -p "$TOKEN_DIR"
chmod 750 "$TOKEN_DIR"

# --- gateway container -----------------------------------------------------------
# Baked files land at their conventional install paths: scripts/config under
# /usr/local/bin, the shared deny file under /etc/soleur (the nftables loader
# reads the same copy — single source, single install).
DENY_PATH="/etc/soleur/egress-deny-cidrs.txt"
for f in "$CONF_DIR/egress-gateway-squid.conf" "$CONF_DIR/egress-auth-helper.sh" "$DENY_PATH"; do
  [[ -f "$f" ]] || die "baked file $f missing (host-script install did not land)"
done

if docker inspect "$GW_NAME" >/dev/null 2>&1; then
  docker restart "$GW_NAME" >/dev/null
  log "restarted $GW_NAME (mounted config refreshed)"
else
  docker pull "$IMAGE" >/dev/null || die "image pull failed: $IMAGE"
  docker run -d --name "$GW_NAME" \
    --network "$NET_NAME" --ip "$GW_IP" \
    --log-driver journald --restart unless-stopped \
    -v "$CONF_DIR/egress-gateway-squid.conf:/etc/squid/squid.conf:ro" \
    -v "$CONF_DIR/egress-auth-helper.sh:/usr/local/bin/egress-auth-helper.sh:ro" \
    -v "$DENY_PATH:/etc/squid/egress-deny-cidrs.txt:ro" \
    -v "$TOKEN_DIR:/etc/squid/session-tokens:ro" \
    "$IMAGE" >/dev/null
  log "started $GW_NAME on $NET_NAME at $GW_IP:$GW_PORT"
fi

log "OK: gateway up (bridge=$BRIDGE_IF subnet=$SUBNET gw=$GW_IP)"
