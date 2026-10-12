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
  # Set -e: a bare test-AND-assignment in the loop body aborts on the first
  # NON-matching subnet (docker0's 172.17 mismatches every candidate on a
  # fresh host) — if-guard it. The probe runs OUTSIDE the loop's process
  # substitution so its failure is visible to the main shell (a `< <(cmd
  # || die)` subshell's status never propagates; an unreadable answer is
  # not an empty one).
  existing_subnets="$(docker network inspect $(docker network ls -q 2>/dev/null) -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)" \
    || die "subnet-clash probe failed (docker ls/inspect) — refusing a blind candidate"
  while read -r s; do
    if [[ -n "$s" && "${s%.*.*}" == "$fam" ]]; then clash=1; fi
  done <<< "$existing_subnets"
  if (( clash == 0 )); then SUBNET="$cand"; break; fi
done
[[ -n "$SUBNET" ]] || die "no free subnet in the 172.31.100-103.0/24 candidates"
GW_IP="${SUBNET%.*}.2"
log "subnet=$SUBNET gw_ip=$GW_IP"

# --- bridge --------------------------------------------------------------------
# Docker >= 28 installs a raw-PREROUTING drop for packets addressed to a
# container IP arriving via any interface other than the bridge itself — the
# "direct-routing protection" (moby #49325, consolidated per-endpoint by #49829;
# #52224 later moved it to per-subnet). It fires BEFORE conntrack and
# DOCKER-USER, so the loader's `iifname docker0` -> gw:8443 accept can never
# un-block it — measured on web-1: the app container's CONNECT SYNs died at raw
# (1611 packets, egress_gw_probe allow_rc=28) while host->gw and every FORWARD
# marker stayed healthy. `gateway_mode_ipv4=nat-unprotected` keeps masquerading
# (the gw's own upstream dials) but omits the direct-routing drop — the designed
# boundary lives in SOLEUR-EGRESS / SOLEUR-EGRESS-GW plus the loader's
# oifname-scoped direct-routing drop for non-docker0 ingress.
# Older daemons lack both the option and the protection: retry without it.
# Network options are immutable post-create, so a bridge in the wrong mode is
# torn down and rebuilt (the gw is pinned to $GW_IP; the nft legs rebake
# identically on the next loader run).
create_bridge() {
  docker network create --subnet="$SUBNET" \
    -o com.docker.network.bridge.name="$BRIDGE_IF" \
    -o com.docker.network.bridge.gateway_mode_ipv4=nat-unprotected \
    "$NET_NAME" >/dev/null 2>&1 || \
  docker network create --subnet="$SUBNET" \
    -o com.docker.network.bridge.name="$BRIDGE_IF" \
    "$NET_NAME" >/dev/null
}

# Empty on daemon/report failure AND on daemons that lack the option (the
# option's absence is also the pre-fix shape, so emptiness alone is ambiguous
# — the rebuild gate reads the inspect's exit status, not just the value).
SERVER_MAJOR="$(docker version -f '{{.Server.Version}}' 2>/dev/null | grep -oE '^[0-9]+' || true)"
bridge_mode() {
  docker network inspect "$NET_NAME" \
    -f '{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}' 2>/dev/null
}
# die if a >=28 daemon cannot land the mode: a bridge silently created without
# it re-introduces the raw drop (and the elif would destroy-rebuild forever).
require_mode() {
  [[ "${SERVER_MAJOR:-0}" -ge 28 ]] || return 0
  local mode; mode="$(bridge_mode || true)"
  [[ "$mode" == "nat-unprotected" ]] || \
    die "bridge $NET_NAME reports gateway_mode_ipv4='$mode' after create — >=28 daemon refused the option"
}

if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
  create_bridge
  require_mode
  log "created bridge $NET_NAME ($BRIDGE_IF, gw_mode=$(bridge_mode || echo unset))"
else
  MODE_RC=0
  MODE="$(bridge_mode)" || MODE_RC=$?
  if (( MODE_RC == 0 )) && [[ "${SERVER_MAJOR:-0}" -ge 28 && "$MODE" != "nat-unprotected" ]]; then
    # The mode gate is version-guarded: on <28 the option cannot be set, so an
    # unconditional != check would tear the bridge down on every provisioner
    # run. <28 has no direct-routing protection to escape anyway.
    # Refuse to rm while foreign endpoints hold the bridge — `network rm` would
    # fail AFTER the gw is gone, wedging every re-run in a permanently-deleted
    # gw state (strictly worse than running on a wrong-mode bridge).
    MEMBERS="$(docker network inspect "$NET_NAME" -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)" \
      || die "cannot enumerate $NET_NAME members — refusing the rebuild (an unreadable roster is not an empty one)"
    EXTRA="$(for m in $MEMBERS; do if [[ "$m" != "$GW_NAME" ]]; then echo "$m"; fi; done)"
    [[ -z "$EXTRA" ]] || die "bridge $NET_NAME has non-gateway endpoints ($EXTRA) — detach them before the mode rebuild"
    # Ensure the image is local BEFORE the gw is torn down: the run arm's pull
    # is the rebuild window's dominant term and a registry blip there would
    # strand the gw absent.
    docker image inspect "$IMAGE" >/dev/null 2>&1 || \
      docker pull "$IMAGE" >/dev/null || \
      die "image $IMAGE unavailable — refusing to rebuild $NET_NAME"
    docker rm -f "$GW_NAME" >/dev/null 2>&1 || true
    # `rm -f` returning does not guarantee the endpoint sandbox is released;
    # retry the rm briefly, else die (re-runs retry — rm -f above is a no-op).
    _rm_tries=0
    until docker network rm "$NET_NAME" >/dev/null 2>&1; do
      _rm_tries=$(( _rm_tries + 1 ))
      if (( _rm_tries >= 3 )); then die "network rm $NET_NAME failed after gw removal (reattach the gw by re-running this script)"; fi
      sleep 1
    done
    create_bridge
    require_mode
    log "rebuilt bridge $NET_NAME ($BRIDGE_IF, gw_mode=nat-unprotected; the previous mode blocked cross-bridge dials to the gw)"
    # Better Stack-visible correlation: this lands next to the egress_gw_probe
    # stream it explains (the resolver's own tag — bootstrap has no unit).
    logger -t egress-gw-probe "egress_gw_bridge action=rebuilt mode=nat-unprotected host=$(hostname)" 2>/dev/null || true
  fi
fi

# --- token dir ------------------------------------------------------------------
# Owner = the app container's `soleur` uid (1001 — Dockerfile `USER soleur`);
# the dispatcher's writeFileSync mints token files inside it. 0711: the
# gateway's auth helper runs as the `proxy` uid and needs only TRAVERSE (+x)
# for `-f "$TOKDIR/$pass"`; nobody else can LIST the dir, so token filenames
# (the credentials) stay unenumerable. Shared rw mount into the app
# container is the mint channel; residual (accepted, ADR-276): a same-uid
# process in the app container could mint a file here — the container uid is
# the trust boundary; the sandboxed agent is behind denyRead.
mkdir -p "$TOKEN_DIR"
chown 1001:1001 "$TOKEN_DIR"
chmod 0711 "$TOKEN_DIR"

# --- gateway container -----------------------------------------------------------
# Baked files land at their conventional install paths: scripts/config under
# /usr/local/bin, the shared deny file under /etc/soleur (the nftables loader
# reads the same copy — single source, single install).
DENY_PATH="/etc/soleur/egress-deny-cidrs.txt"
for f in "$CONF_DIR/egress-gateway-squid.conf" "$CONF_DIR/egress-auth-helper.sh" "$DENY_PATH"; do
  [[ -f "$f" ]] || die "baked file $f missing (host-script install did not land)"
done

if docker inspect "$GW_NAME" >/dev/null 2>&1; then
  # `docker restart` picks up the mounted config only if the baked files were
  # updated in-place (same inode). The provisioner's file write is in-place;
  # a rename-replace writer would need `docker rm` + recreate — documented
  # invariant of this refresh path.
  docker restart "$GW_NAME" >/dev/null
  log "restarted $GW_NAME (mounted config refreshed)"
else
  # Digest-pinned image: inspect first so a registry blip cannot strand a
  # rebuild whose image is already local (the common case).
  docker image inspect "$IMAGE" >/dev/null 2>&1 || \
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

# Publish the derived target for the app-side forwarder. The subnet is
# collision-probed (172.31.100-103.0/24), so a hardcoded default would dial a
# phantom on a fallback-subnet host; the shared token dir is already the
# app<->gw channel. `host:port` single line; the app reads it when
# EGRESS_GW_HOST/PORT are unset (tests override via env).
printf '%s:%s\n' "$GW_IP" "$GW_PORT" > "$TOKEN_DIR/.gw-target"

# Same-run proof: a TCP open to the gw verifies Squid is listening on the
# rebuilt (or existing) bridge — "apply green" should mean the path works,
# not merely that the files copied. /dev/tcp is a bash builtin (no curl dep);
# it does not exercise the CONNECT path, which the 5-min probe covers.
#
# `docker run -d` and `docker restart` return before Squid binds :8443, so a single
# probe at t~0 is refused on a healthy host (measured: refused 1-3 ms after the
# "started" line in apply run 38228632851, and after the "restarted" line in run
# 38229123048). The check therefore polls. A refused connect returns at once, so the
# per-attempt `timeout` only bounds a filtered attempt; the SECONDS deadline bounds
# the whole wait. SECONDS is an integer counter, so the wait can end up to 1 s early.
GW_WAIT_S="${EGRESS_GW_WAIT_S:-30}"   # tests override; same pattern as EGRESS_GW_IMAGE above

# Container state + the last log lines, for the timeout message. Every command is
# `|| true`: a diagnostics failure must not mask the real die. StartedAt/RestartCount
# tell a `docker restart` incarnation from the previous one's log lines.
gw_diag() {
  log "gw container state: $(docker inspect -f '{{.State.Status}} running={{.State.Running}} restarting={{.State.Restarting}} restarts={{.RestartCount}} exit={{.State.ExitCode}} started={{.State.StartedAt}}' "$GW_NAME" 2>&1 || true)"
  log "gw container logs (last 20 lines):"
  timeout 10 docker logs --tail 20 "$GW_NAME" 2>&1 | sed 's/^/[egress-gw-bootstrap]   /' || true
}

# Poll until the gw accepts a TCP open or GW_WAIT_S elapses. `return 0` is reachable
# only from a successful connect; loop exhaustion falls through to the die. The last
# probe error is kept: "Connection refused" (nothing listening) vs a timeout (packets
# dropped) separates a Squid that is not up from a filtered path.
wait_for_gw_tcp() {
  local deadline=$(( SECONDS + GW_WAIT_S )) attempts=0 err=""
  while :; do
    attempts=$(( attempts + 1 ))
    # shellcheck disable=SC2016 # single quotes on purpose: $1/$2 are bash -c positionals, not this shell's
    if err="$(timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/$2"' gw-probe "$GW_IP" "$GW_PORT" 2>&1)"; then
      log "gw $GW_IP:$GW_PORT answered a TCP open (attempt $attempts)"
      return 0
    fi
    if (( SECONDS >= deadline )); then break; fi
    sleep 1
  done
  log "last probe error: ${err:-<none>}"
  gw_diag
  die "gw $GW_IP:$GW_PORT did not answer a TCP open post-bring-up"
}

wait_for_gw_tcp

log "OK: gateway up (bridge=$BRIDGE_IF subnet=$SUBNET gw=$GW_IP)"
