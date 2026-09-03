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

# 3.5 (#7695). The two-state mount guard the unit's ExecStartPre calls. Installed from HERE
#     rather than baked into the OCI image because this script already owns /usr/local/bin on both
#     the fresh-host and existing-host paths, and the unit must never reference a file that might
#     not exist — an ExecStartPre pointing at a missing binary fails the unit outright.
#
#     WHY THE UNIT NEEDS IT AT ALL, given RequiresMountsFor=/mnt/data. That directive orders this
#     unit after the mount UNIT systemd generates from fstab — but the failure it has to catch is
#     the one where NO mount unit exists: cloud-init's LUKS stage aborted, /mnt/data is a plain
#     directory on the ephemeral root disk, and RequiresMountsFor resolves to nothing. Redis then
#     starts happily and writes its AOF to a disk that does not survive a replace, while the
#     ledger, the ADR and the cloud-init comments all claim LUKS at rest.
#
#     TWO STATES, and the stronger one does NOT depend on an identity read. If the mapper exists,
#     this IS the encrypted store and /mnt/data must be mounted from it — asserted unconditionally,
#     so the guard cannot be disarmed by an unreadable env file. Only the weaker
#     "is it a mountpoint at all" arm is scoped by identity, because the co-located web host
#     legitimately has its own /mnt/data (the workspaces volume) and this unit is installed there
#     too by the SHARED bootstrap.
#
#     ONE-STATE WOULD DEADLOCK THE PLAN. A gate that always demanded /dev/mapper/inngest-redis
#     would refuse to start Redis on the PRE-recut host, whose volume is still plaintext ext4 —
#     blocking the very cutover this apparatus exists to enable.
install -m 0755 /dev/stdin /usr/local/bin/inngest-redis-mount-guard.sh <<'GUARDEOF'
#!/usr/bin/env bash
# ExecStartPre guard for inngest-redis.service (#7695). Refuses to start Redis onto a /mnt/data
# that is not the persistent store. Read-only; exits 0 (allow) or 1 (refuse).
set -uo pipefail
MOUNT=/mnt/data
MAPPER=/dev/mapper/inngest-redis

# STATE 2 — the mapper is open, so this host has been recut and /mnt/data MUST be on it.
# Asserted FIRST and unconditionally: the presence of the mapper is itself positive proof of
# which store this is, so no identity read can disarm it.
if [ -e "$MAPPER" ]; then
  if ! mountpoint -q "$MOUNT"; then
    echo "FATAL: $MAPPER is open but $MOUNT is not a mountpoint — refusing to start Redis; the AOF would land on the ephemeral root disk while every artifact claims LUKS at rest" >&2
    exit 1
  fi
  src="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null | head -1 || true)"
  if [ "$src" != "$MAPPER" ]; then
    echo "FATAL: $MAPPER is open but $MOUNT is mounted from '${src:-<unreadable>}' — refusing to start Redis onto the wrong device" >&2
    exit 1
  fi
  exit 0
fi

# STATE 1 — no mapper. On the DEDICATED host that is the legitimate pre-recut steady state
# (plaintext ext4), and the only thing to assert is that /mnt/data is a real mount rather than a
# directory on the root disk. Scoped by POSITIVE identity (DOPPLER_PROJECT), never by the absence
# of something: the co-located web host runs this same unit and has its own /mnt/data.
proj=""
if [ -r /etc/default/inngest-server ]; then
  proj="$( . /etc/default/inngest-server 2>/dev/null; printf '%s' "${DOPPLER_PROJECT:-}" )"
fi
[ "$proj" = "soleur-inngest" ] || exit 0

if ! mountpoint -q "$MOUNT"; then
  echo "FATAL: $MOUNT is not a mountpoint — refusing to start Redis; the AOF would land on the ephemeral root disk" >&2
  exit 1
fi
exit 0
GUARDEOF
log "installed /usr/local/bin/inngest-redis-mount-guard.sh (two-state /mnt/data guard, #7695)"

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
