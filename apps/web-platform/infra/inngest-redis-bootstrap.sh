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

# Refuse to run under tracing FIRST (the #7797/#11103 shape): this script installs
# credential-resolving scripts (the ACLEOF acl writer below), and a traced run echoes
# their bodies into stderr, which journald ships off-box. Unconditional, tests the
# STATE ($-), works in bash and dash, value-free message.
case $- in
  *x*) printf '[FATAL] refusing to run under xtrace: this script installs credential-handling scripts and -x would echo their bodies (see #11103)\n' >&2; exit 78 ;;
esac

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
# AN UNREADABLE IDENTITY IS NOT A LICENCE. The first cut of this read collapsed three cases into
# one `exit 0`: the web host (correct), a dedicated host whose env file failed to write, and a
# dedicated host whose file exists but lost DOPPLER_PROJECT. The last two are exactly the broken
# hosts this guard exists for, and it waved them through — the file is written by cloud-init and
# augmented in place by inngest-bootstrap.sh, so "present but empty" is a real failure mode, not a
# hypothetical. Note the unit declares `EnvironmentFile=/etc/default/inngest-server` WITHOUT the
# leading `-`, so systemd has already refused to start us if the file is absent; the absent arm
# below is kept explicit rather than assumed.
ENVFILE=/etc/default/inngest-server
if [ ! -e "$ENVFILE" ]; then
  # Nothing here claims to be any host. Nothing to assert.
  exit 0
fi
if [ ! -r "$ENVFILE" ]; then
  echo "FATAL: $ENVFILE exists but is unreadable — refusing to start Redis; this guard cannot tell which host it is on, and the pre-recut arm it would skip is the one that keeps the AOF off the root disk" >&2
  exit 1
fi
proj="$( . "$ENVFILE" 2>/dev/null; printf '%s' "${DOPPLER_PROJECT:-}" )"
if [ -z "$proj" ]; then
  echo "FATAL: $ENVFILE carries no DOPPLER_PROJECT — refusing to start Redis; host identity is unreadable and this guard will not infer it from an absence" >&2
  exit 1
fi
[ "$proj" = "soleur-inngest" ] || exit 0

if ! mountpoint -q "$MOUNT"; then
  echo "FATAL: $MOUNT is not a mountpoint — refusing to start Redis; the AOF would land on the ephemeral root disk" >&2
  exit 1
fi
exit 0
GUARDEOF
log "installed /usr/local/bin/inngest-redis-mount-guard.sh (two-state /mnt/data guard, #7695)"

# 3.6 (#11103). The acl writer the unit's second ExecStartPre calls. Same delivery as the
#     mount-guard above: heredoc-internal so it rides the same bootstrap script on every host
#     (no STAGED list or image-manifest edit), reconcile-always on every run.
#
#     WHY aclfile AT ALL. The pre-#11103 unit wrapped the start in an inner `bash -c` that
#     expanded "$INNGEST_REDIS_PASSWORD" onto redis-server's argv — a traced launch
#     (SHELLOPTS=xtrace / BASH_ENV / bash -x) printed it to stderr and journald shipped it
#     off-box, and /proc/<pid>/cmdline (0444) + `CONFIG GET requirepass` exposed it even
#     untraced. The conf now declares `aclfile`; this script turns the Doppler-injected
#     password into `user default on #<sha256> ~* &* +@all` — the secret never lands on argv
#     OR disk: the `#` spelling writes the password's SHA256 directly (a `>` spelling would
#     leave the cleartext in the file at rest — review P2), and `AUTH <pw>` resolves to the
#     default user either way, so the inngest `redis://:<pw>@127.0.0.1:6379` client is
#     unchanged.
install -m 0755 /dev/stdin /usr/local/bin/inngest-redis-acl.sh <<'ACLEOF'
#!/usr/bin/env bash
# ExecStartPre acl writer for inngest-redis.service (#11103). Runs under
# `doppler run --only-secrets INNGEST_REDIS_PASSWORD` — it sees exactly one secret.
# Exits 0 (aclfile written) or non-zero (refusal/validation failure — the unit fails
# designed-loud, same posture as the mount-guard).

# Refuse to run under tracing FIRST (the #7797/#10363 shape): this script resolves a live
# credential and a traced launch would print it to stderr, which journald ships off-box.
# Unconditional on purpose, tests the STATE ($-), works in bash and dash, and stays above
# every expansion below. The message must stay value-free.
case $- in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #11103)\n' >&2; exit 78 ;;
esac
set -u

# The acl file path. INNGEST_REDIS_ACL_FILE is a TEST-ONLY override seam: the unit's
# --only-secrets bound injects INNGEST_REDIS_PASSWORD and nothing else, so on a host this
# is always the default; the suite sets it to replay validation rows off /mnt/data.
ACL_FILE="${INNGEST_REDIS_ACL_FILE:-/mnt/data/redis/inngest-redis.acl}"

# Value-free validation (FATAL, no write): the aclfile grammar cannot carry whitespace
# (it would split the rule), quotes or a backslash (they escape out of the >password
# token), or control bytes. random_password.inngest_redis_password_* emits alnum-only
# (special=false), so a compliant secret always passes; a malformed one fails the unit
# loud rather than writing a rule that silently changes auth.
if [ -z "${INNGEST_REDIS_PASSWORD:-}" ]; then
  printf 'FATAL: INNGEST_REDIS_PASSWORD is unset or empty — refusing to write the aclfile (value-free)\n' >&2
  exit 1
fi
# `=~`, not `printf | grep -q` — under pipefail an early-exiting grep can
# read as a miss (#9217 grep-q-pipe guard). The class matches whitespace, a quote,
# a backslash or a control byte, identically to the previous grep -E pattern.
_acl_bad_re='[[:space:]"'"'"'\\[:cntrl:]]'
if [[ "$INNGEST_REDIS_PASSWORD" =~ $_acl_bad_re ]]; then
  printf 'FATAL: INNGEST_REDIS_PASSWORD carries whitespace, a quote, a backslash or a control byte — refusing to write the aclfile (value-free)\n' >&2
  exit 1
fi

# Hash BEFORE the write: `#` is the aclfile grammar's SHA256 form — AUTH presents cleartext
# and Redis hashes it for the comparison, so the on-disk artifact never carries the
# credential (a `>` rule would persist it at rest — review P2). Unsalted SHA256 of a
# random_password-minted 48-char alnum is not a dictionary target.
ACL_HASH="$(printf '%s' "$INNGEST_REDIS_PASSWORD" | sha256sum | cut -d' ' -f1)"
# Atomic tmp+mv (never a half-written aclfile at 0600, deploy-owned — the writer runs as
# User=deploy and can only write inside ReadWritePaths=/mnt/data/redis).
ACL_TMP="$(mktemp "${ACL_FILE}.tmp.XXXXXX")"
trap 'rm -f "$ACL_TMP"' EXIT
chmod 0600 "$ACL_TMP"
printf 'user default on #%s ~* &* +@all\n' "$ACL_HASH" > "$ACL_TMP"
mv -f "$ACL_TMP" "$ACL_FILE"
trap - EXIT
ACLEOF
log "installed /usr/local/bin/inngest-redis-acl.sh (aclfile writer, #11103)"

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
