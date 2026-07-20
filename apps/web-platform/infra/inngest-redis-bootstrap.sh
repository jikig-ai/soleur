#!/usr/bin/env bash
# Idempotent bootstrap for the self-hosted Inngest durable Redis (#5450).
#
# Installs redis-server, neutralises the distro default instance (it binds 6379
# and would collide with ours), creates the AOF dir on the PERSISTENT /mnt/data
# volume, installs the conf + unit, and enables inngest-redis.service.
#
# DELIVERY: this script, inngest-redis.conf, and inngest-redis.service are all
# BAKED INTO the soleur-inngest-bootstrap OCI image (the vector.toml pattern) and
# staged to /tmp by the image entrypoint (existing-host deploy) / cloud-init
# docker-cp (fresh host). inngest-bootstrap.sh installs THIS script to
# /usr/local/bin and runs it; it installs the conf + unit from /tmp itself.
#
# CONF LIVES UNDER /mnt/data/redis, NOT /etc/redis: on the existing-host deploy
# path inngest-bootstrap.sh runs inside webhook.service's ProtectSystem=strict
# mount namespace, where /etc is read-only and only ReadWritePaths (which
# includes /mnt/data, NOT /etc/redis) are writable. /usr/local/bin and
# /etc/systemd/system ARE in that ReadWritePaths set, so the script + unit land
# there; the conf must live on /mnt/data. Re-runnable: every step no-ops when
# already satisfied.
set -euo pipefail

log() { echo "[inngest-redis-bootstrap] $*"; }

REDIS_DATA_DIR="/mnt/data/redis"
REDIS_CONF="$REDIS_DATA_DIR/inngest-redis.conf"
UNIT="inngest-redis.service"
UNIT_FILE="/etc/systemd/system/$UNIT"

# Defense-in-depth (CWE-367, mirrors inngest-bootstrap.sh): refuse to install
# from a symlinked /tmp staging path (a pre-existing local user could pre-create
# a symlink to land attacker content into a root-installed file).
assert_not_symlink() {
  if [[ -L "$1" ]]; then
    log "ERROR: refusing to install from symlinked staging path $1"
    exit 1
  fi
}

# 1. Install redis-server (idempotent — skip the slow apt path when present).
if ! command -v redis-server >/dev/null 2>&1; then
  log "installing redis-server"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq redis-server
else
  log "redis-server already installed ($(redis-server --version | awk '{print $3}'))"
fi

# 2. Neutralise the distro default redis instance — it binds 127.0.0.1:6379 and
#    would race ours for the port. mask so it cannot be pulled in transitively.
if systemctl list-unit-files redis-server.service >/dev/null 2>&1; then
  systemctl disable --now redis-server.service >/dev/null 2>&1 || true
  systemctl mask redis-server.service >/dev/null 2>&1 || true
  log "distro redis-server.service disabled + masked"
fi

# 3. AOF dir on the persistent volume. chown immediately after mkdir (the
#    five-bug-cascade learning). deploy owns it (the unit runs as deploy).
mkdir -p "$REDIS_DATA_DIR"
chown deploy:deploy "$REDIS_DATA_DIR"
chmod 0750 "$REDIS_DATA_DIR"
log "AOF dir $REDIS_DATA_DIR ready (deploy:deploy 0750)"

# 4. Install the conf (onto /mnt/data — webhook-namespace-writable) + the unit
#    (/etc/systemd/system is in ReadWritePaths). Sourced from the /tmp staging
#    the OCI entrypoint / cloud-init populated. Skip the conf install if absent
#    only when it is already in place (re-run without staging).
if [[ -f /tmp/inngest-redis.conf ]]; then
  assert_not_symlink /tmp/inngest-redis.conf
  install -m 0644 /tmp/inngest-redis.conf "$REDIS_CONF"
elif [[ ! -f "$REDIS_CONF" ]]; then
  log "ERROR: /tmp/inngest-redis.conf not staged and $REDIS_CONF absent"
  exit 1
fi
if [[ -f /tmp/inngest-redis.service ]]; then
  assert_not_symlink /tmp/inngest-redis.service
  # #6555: the redis unit dropped `--project` and resolves the project from
  # EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime — no
  # @@DOPPLER_PROJECT@@ sentinel remains, so install it verbatim (no substitution round-trip
  # that could mask a re-introduction).
  install -m 0644 /tmp/inngest-redis.service "$UNIT_FILE"
fi
if [[ ! -f "$UNIT_FILE" ]]; then
  log "ERROR: $UNIT_FILE not installed (no /tmp staging and not pre-present)"
  exit 1
fi

# 5. Enable + (re)start the dedicated unit. daemon-reload picks up a changed
#    unit file; enable --now is a no-op when already active with the same shape.
systemctl daemon-reload
systemctl enable "$UNIT" >/dev/null 2>&1 || true
systemctl restart "$UNIT"

# 6. Liveness assert — fail LOUD (non-zero) if Redis did not come up, so the
#    deploy gate / provisioner surfaces it (no silent non-durable state).
if ! systemctl is-active --quiet "$UNIT"; then
  log "ERROR: $UNIT did not become active"
  systemctl status "$UNIT" --no-pager -l | tail -20 || true
  exit 1
fi
log "bootstrap complete: $UNIT active, AOF on $REDIS_DATA_DIR"
