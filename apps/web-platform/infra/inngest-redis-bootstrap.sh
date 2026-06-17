#!/usr/bin/env bash
# Idempotent bootstrap for the self-hosted Inngest durable Redis (#5450).
#
# Installs redis-server, neutralises the distro default instance (it binds 6379
# and would collide with ours), creates the AOF dir on the PERSISTENT /mnt/data
# volume, and enables the dedicated inngest-redis.service. Delivered as a FILE
# whose file() is hashed into server.tf triggers_replace.config_hash (NOT inline
# remote-exec, which is a silent no-op — 2026-06-14 learning). Re-runnable: every
# step is a no-op when already satisfied.
#
# The .conf and .service are delivered alongside (cloud-init write_files for a
# fresh host; tf file provisioner for the existing host). This script only does
# the imperative install + dir + enable that write_files cannot.
set -euo pipefail

log() { echo "[inngest-redis-bootstrap] $*"; }

REDIS_DATA_DIR="/mnt/data/redis"
UNIT="inngest-redis.service"

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

# 4. Enable + (re)start the dedicated unit. daemon-reload picks up a changed
#    unit file; enable --now is a no-op when already active with the same shape.
systemctl daemon-reload
systemctl enable "$UNIT" >/dev/null 2>&1 || true
systemctl restart "$UNIT"

# 5. Liveness assert — fail LOUD (non-zero) if Redis did not come up, so the
#    deploy gate / provisioner surfaces it (no silent non-durable state).
if ! systemctl is-active --quiet "$UNIT"; then
  log "ERROR: $UNIT did not become active"
  systemctl status "$UNIT" --no-pager -l | tail -20 || true
  exit 1
fi
log "bootstrap complete: $UNIT active, AOF on $REDIS_DATA_DIR"
