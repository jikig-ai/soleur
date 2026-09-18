#!/usr/bin/env bash
# inngest-luks-cutover.sh — the ADR-142 additive blue-green cutover of the Redis AOF store onto the
# LUKS volume (#6894). Runs ON the dedicated Inngest host as a root oneshot
# (inngest-luks-cutover.service) fired every 30s by inngest-luks-cutover.timer. The host has no
# inbound channel, so a Doppler-flag poll is the only no-SSH trigger — the same shape as
# inngest-cutover-flip.sh, and a SEPARATE flag and FSM from it: the flip owns the one authorized
# FLUSHALL, and a copy that preserves data does not belong behind the flag that destroys it.
#
# ── STATE TABLE (task 4.2) — INNGEST_LUKS_CUTOVER on soleur-inngest/prd ────────────────────────
#
#   state        written by            guard on entry (on-host)                 action → successor
#   ───────────  ────────────────────  ───────────────────────────────────────  ─────────────────────────────
#   (unset)      —                     —                                        no-op
#   armed        op=luks-cutover       pointer ABSENT; plaintext canonical;     set copying → freeze → copy
#                (reviewer-gated)      additive staged and verified             → T2 → latch → set copied → …
#   copying      this script           pointer ABSENT (else: refuse, stale)     re-freeze → re-copy → T2 →
#                                                                                latch → set copied → …
#   copied       this script, AFTER    T2 re-verified NOW (a reboot may have   swap → set swapped → …
#                T2 + latch            restarted Redis and staled the copy)
#   swapped      this script, AFTER    /mnt/data = canonical mapper over the    resume → T3 → set done
#                pointer + fstab       additive volume
#   done         this script, AFTER T3 —                                        no-op (terminal)
#   rollback     op=luks-rollback      a swap has happened (pointer present)    reverse-copy → T2 → swap
#                (reviewer-gated)                                               back → set rolled-back
#   rolled-back  this script           —                                        no-op (terminal)
#   aborted      this script (ERR      —                                        no-op (terminal); writers
#                trap, or a refusal)                                            are resumed before it lands
#
# Every abort point in the body names its reason; `emit_state` carries it to Better Stack.
#
# ── LOAD-BEARING INVARIANTS ────────────────────────────────────────────────────────────────────
#   * TERMINAL STATES ARE NO-OPS, and the ERR trap drives the flag to one. That is the whole
#     re-fire story: a completed run leaves the flag terminal, so a re-poll refuses before anything
#     is touched. No epoch token — Fork D cut it for exactly this reason.
#   * THE LATCH RECORDS COMPLETION-WITH-VERIFICATION, NEVER ENTRY. It is written after T2 passes and
#     lives in THIS FSM's own state dir. It is never appended to the flip FSM's flush latch
#     (/mnt/data/inngest-cutover/flip-done.latch) — that file is a monotonic record other readers
#     parse, and Fork L exists to carry it across the swap intact.
#   * THE COPY IS THE WHOLE MOUNT, NOT redis/. The flip's flush latch lives on /mnt/data; a swap
#     onto a device without it is, to that latch, a recut — and would re-open a second FLUSHALL
#     against a populated store. T2 names the latch path explicitly (Fork L).
#   * ROLLBACK REVERSE-COPIES. Switching back to the plaintext volume without copying would drop
#     every write made on the encrypted store since the swap. The same copy + T2 machinery runs
#     with the roles reversed, so a rollback is exactly as data-safe as the cutover.
#   * THE PROBE MUST BE ABLE TO MEASURE. Unprivileged blkid reads a LUKS device as blank (rc 2); the
#     script asserts root before anything else (specs/…/measurements.md §1).
#   * NO QUIESCE FLAG. Fork Q removed it from the critical path: Redis being stopped is what makes
#     the copy consistent, and the arming route's connection-refused arm already answers callers.
#
# ── FIXTURE SEAMS — INERT UNLESS argv[1] IS --fixture-seams ────────────────────────────────────
# Same reasoning as inngest-cutover-flip.sh's #7761 gate, verbatim in consequence: this runs as ROOT
# under `doppler run`, and every seam below is read from the environment and several are EXECUTED,
# so without the gate a Doppler secret whose NAME matched a seam would be root command execution
# inside the unit that moves the store. argv is the one channel `doppler run` cannot supply.
set -Eeuo pipefail

# #7797: this script binds the LUKS passphrase and the Redis password, and `set -x` would write
# both to stderr — which journald ships off-box under the SyslogIdentifier below. Refuse instead.
case "$-" in
  *x*)
    if [ -n "${INNGEST_REDIS_LUKS_KEY:+x}${INNGEST_REDIS_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

readonly LOG_TAG="inngest-luks-cutover"
readonly GUARD_REV="6894"

if [[ "${1:-}" != "--fixture-seams" ]]; then
  _seams_present=0
  # THE SEAM LIST. inngest-luks-cutover.test.sh derives the seam set from this file by shape and
  # asserts it equals this list, so a seam read added without adding it here reds the suite. Keep
  # one name per line and `do` on its own line.
  for _seam in \
    LUKS_BYID \
    LUKS_CRYPTSETUP_CMD \
    LUKS_CURL_CMD \
    LUKS_ENVFILE \
    LUKS_FLAG \
    LUKS_FLAG_SET_CMD \
    LUKS_FSTAB \
    LUKS_GQL_URL \
    LUKS_HEALTH_URL \
    LUKS_LOGGER_CMD \
    LUKS_MAPPER_DIR \
    LUKS_MNT \
    LUKS_NOOP_THROTTLE_S \
    LUKS_PLAIN_MNT \
    LUKS_POINTER_CMD \
    LUKS_PROC \
    LUKS_REDIS_CLI_CMD \
    LUKS_STAGING_MNT \
    LUKS_STATE_DIR \
    LUKS_SYSFS \
    LUKS_SYSTEMCTL_CMD \
    LUKS_UID \
    LUKS_VERIFY_INTERVAL_S \
    LUKS_VERIFY_WINDOW_S
  do
    if [[ -n "${!_seam+x}" ]]; then
      _seams_present=$((_seams_present + 1))
    fi
    unset "$_seam"
  done
  if [[ "$_seams_present" -gt 0 ]]; then
    logger -t "$LOG_TAG" \
      "SOLEUR_INNGEST_LUKS_CUTOVER_SEAM_REFUSED count=${_seams_present} detail=fixture seam names were present in the environment without --fixture-seams; they were unset and ignored. A name in the soleur-inngest/prd Doppler config collided with a seam name. #6894" \
      2>/dev/null || true
  fi
  unset _seam _seams_present
fi

# ── Configuration ───────────────────────────────────────────────────────────────────────────────
# The two volume ids are staged by the first-boot stage into /etc/default/inngest-luks-volumes
# (this script ships in the image and cannot see template variables). T2 and T3 compare every mount
# against THESE ids — never against a kernel /dev/sd* name, never by mount-path string alone.
PLAIN_ID="${INNGEST_LUKS_PLAIN_VOLUME_ID:-}"
LUKS_ID="${INNGEST_LUKS_ADDITIVE_VOLUME_ID:-}"
BYID="${LUKS_BYID:-/dev/disk/by-id}/scsi-0HC_Volume_"
MAPPER_DIR="${LUKS_MAPPER_DIR:-/dev/mapper}"
MNT="${LUKS_MNT:-/mnt/data}"
STAGING_MNT="${LUKS_STAGING_MNT:-/mnt/data-luks}"
PLAIN_MNT="${LUKS_PLAIN_MNT:-/mnt/data-plain}"
FSTAB="${LUKS_FSTAB:-/etc/fstab}"
ENVFILE="${LUKS_ENVFILE:-/etc/default/inngest-luks}"
STATE_DIR="${LUKS_STATE_DIR:-/var/lib/inngest-luks-cutover}"
SYSFS="${LUKS_SYSFS:-/sys/class/block}"
PROC="${LUKS_PROC:-/proc}"
HEALTH_URL="${LUKS_HEALTH_URL:-http://127.0.0.1:8288/health}"
GQL_URL="${LUKS_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
VERIFY_WINDOW_S="${LUKS_VERIFY_WINDOW_S:-120}"
VERIFY_INTERVAL_S="${LUKS_VERIFY_INTERVAL_S:-5}"
readonly CANON_NAME=inngest-redis
readonly STAGING_NAME=inngest-redis-staging
readonly FLIP_LATCH_REL=inngest-cutover/flip-done.latch
readonly AOF_MANIFEST_REL=redis/appendonlydir/appendonly.aof.manifest
# THE FREEZE SET — enumerated, not named by a function (the sibling ADR records seven aborted
# freezes from answering "what writes under the mount" by memory). Discovered 2026-09-18 by
# grepping every artifact delivered to this host for /mnt/data and classifying each reference:
#   inngest-redis.service         WRITES   the AOF, dir /mnt/data/redis
#   inngest-cutover-flip.timer    WRITES   appends the flush latch under /mnt/data/inngest-cutover
#   inngest-server.service        client   Redis's only client; stopped before Redis so it cannot
#                                          error-loop against a stopped store
#   inngest-server-probe.timer    READS    du/statfs of /mnt/data; frozen so it cannot publish a
#                                          data_mount_devid read mid-swap
# NOT frozen, measured read-only: vector (host_metrics statfs), inngest-server-flip-guard.sh (reads
# a root-disk marker). assert_quiesced below scans /proc for ANY holder, so a writer this list
# missed aborts the run instead of racing the copy. Timers stop first so nothing re-fires a service.
readonly FREEZE_TIMERS="inngest-cutover-flip.timer inngest-server-probe.timer"
readonly FREEZE_SERVICES="inngest-server.service inngest-redis.service inngest-server-probe.service"
# THE FLIP SERVICE IS NOT IN THE FREEZE SET, AND THAT IS DELIBERATE — it is REFUSED instead.
# Stopping its timer does not stop an instance already running, and that instance holds the one
# authorized FLUSHALL: it can empty the store mid-copy and it restarts inngest-server.service behind
# this FSM's back. But SIGTERMing a run that may be mid-FLUSHALL to make room for a copy is the
# worse trade — so the two FSMs are made mutually exclusive instead, before anything is stopped.
readonly CONFLICT_SERVICES="inngest-cutover-flip.service"
# THE OWNING TRAP (ADR-129) for the two rewrite helpers below. Both allocate a tempfile NEXT TO the
# file they replace — /etc/fstab and /etc/default/inngest-luks — because a rename is only atomic
# within a filesystem. A death between the mktemp and the mv would otherwise leave
# `fstab.cutover.XXXXXX` sitting in /etc on a host with no inbound channel to clean it up.
LUKS_TMPFILES=()
cleanup_tmpfiles() {
  local _f
  for _f in ${LUKS_TMPFILES[@]+"${LUKS_TMPFILES[@]}"}; do [[ -n "$_f" ]] && rm -f "$_f"; done
}
trap cleanup_tmpfiles EXIT

START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
PHASE=init            # init | frozen | swapped — read by the ERR trap to decide what to resume
K_FREEZE=""; E_FREEZE=""

# ── Primitives (each a seam in the fixture path) ───────────────────────────────────────────────
logger_cmd() { "${LUKS_LOGGER_CMD:-logger}" "$@"; }
systemctl_cmd() { if [[ -n "${LUKS_SYSTEMCTL_CMD:-}" ]]; then "$LUKS_SYSTEMCTL_CMD" "$@"; else systemctl "$@"; fi; }
cryptsetup_cmd() { if [[ -n "${LUKS_CRYPTSETUP_CMD:-}" ]]; then "$LUKS_CRYPTSETUP_CMD" "$@"; else cryptsetup "$@"; fi; }
curl_cmd() { if [[ -n "${LUKS_CURL_CMD:-}" ]]; then "$LUKS_CURL_CMD" "$@"; else curl "$@"; fi; }
# REDISCLI_AUTH, never `-a`: this repo's own inngest-bootstrap.sh records why (argv is world-readable
# through /proc/<pid>/cmdline) — and this is the file whose assert_quiesced walks /proc itself.
redis_cli_cmd() { if [[ -n "${LUKS_REDIS_CLI_CMD:-}" ]]; then "$LUKS_REDIS_CLI_CMD" "$@"; else REDISCLI_AUTH="${INNGEST_REDIS_PASSWORD:-}" redis-cli "$@"; fi; }
my_uid() { printf '%s' "${LUKS_UID:-$(id -u)}"; }

read_flag() {
  local raw
  if [[ -n "${LUKS_FLAG+x}" ]]; then raw="$LUKS_FLAG"; else raw="${INNGEST_LUKS_CUTOVER:-}"; fi
  printf '%s' "$raw" | tr -d '[:space:]'
}
flag_set() {
  if [[ -n "${LUKS_FLAG_SET_CMD:-}" ]]; then "$LUKS_FLAG_SET_CMD" "$1"
  else doppler secrets set INNGEST_LUKS_CUTOVER "$1" --project soleur-inngest --config prd --silent >/dev/null; fi
}
# pointer_cmd set <id> | clear — the DURABLE pointer (Doppler outlives the host; the root disk does not).
# EVERY Doppler write here ends `>/dev/null`: `doppler secrets set|delete` prints ALL remaining secrets
# of the config to stdout, and this unit's stdout is the journal, which Vector ships off-box — so a
# bare write would publish INNGEST_REDIS_LUKS_KEY and the Redis password to Better Stack.
pointer_cmd() {
  if [[ -n "${LUKS_POINTER_CMD:-}" ]]; then "$LUKS_POINTER_CMD" "$@"; return; fi
  case "$1" in
    set)   doppler secrets set INNGEST_LUKS_ACTIVE_VOLUME_ID "$2" --project soleur-inngest --config prd --silent >/dev/null ;;
    clear) doppler secrets delete INNGEST_LUKS_ACTIVE_VOLUME_ID --project soleur-inngest --config prd --yes --silent >/dev/null ;;
  esac
}
current_pointer() { printf '%s' "${INNGEST_LUKS_ACTIVE_VOLUME_ID:-}" | tr -d '[:space:]'; }

emit_state() {  # emit_state <exit_code> <reason> <flag> [detail]
  local json
  json="$(jq -nc --argjson exit_code "$1" --arg reason "$2" --arg flag "$3" --arg detail "${4:-}" \
    --arg phase "$PHASE" --arg k_freeze "$K_FREEZE" --arg e_freeze "$E_FREEZE" \
    --arg start_ts "$START_TS" --arg guard "$GUARD_REV" \
    '{marker:"SOLEUR_INNGEST_LUKS_CUTOVER", exit_code:$exit_code, reason:$reason, flag:$flag,
      phase:$phase, k_freeze:$k_freeze, e_freeze:$e_freeze, detail:$detail, start_ts:$start_ts, guard:$guard}')"
  mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$json" > "$STATE_DIR/state.json" 2>/dev/null || true
  logger_cmd -t "$LOG_TAG" "$json" 2>/dev/null || true
}

# emit_noop <reason> <flag> — a TERMINAL state's heartbeat, throttled.
#
# The terminal arms are reached on every 30s tick for the rest of the host's life, so an unthrottled
# emit is ~2,880 rows/day of "nothing happened" on a shared Better Stack source — and vector.toml
# requires a fresh quota decision for each timer-driven tag. Worse than the quota: those rows CROWD
# OUT the transition row. A reader taking the newest N rows of this tag sees only no-ops after a
# couple of hours, which is how the sibling tag starved its own hourly probe (#8054).
#
# 300s, not an hour: the dispatch's G3 liveness gate asks "has this host emitted in the last 15
# minutes", and a one-per-hour heartbeat would make a healthy host read SILENT and refuse a
# legitimate cutover. Three rows per window keeps that gate answerable while cutting volume ~10x.
NOOP_THROTTLE_S="${LUKS_NOOP_THROTTLE_S:-300}"
emit_noop() {
  local stamp="$STATE_DIR/noop-emitted" now last
  now="$(date +%s)"
  last="$(stat -c %Y "$stamp" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [[ $(( now - last )) -lt "$NOOP_THROTTLE_S" ]]; then return 0; fi
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  : > "$stamp" 2>/dev/null || true
  emit_state 0 "$1" "$2"
}

# restore_service_best_effort — never leave the sole scheduler dark on a failure path. Before the
# pointer is written (PHASE=frozen) the plaintext volume is canonical, so a swap that got part-way
# (plaintext unmounted, canonical mapper opened) is put back first. After it (PHASE=swapped) the
# canonical mapper IS the store. Either way the Redis mount guard is the net under this: it refuses
# to start Redis onto a /mnt/data that does not match the mapper state.
restore_service_best_effort() {
  # THE MOUNT-REPAIR BRANCH IS `frozen` ONLY, and that is the whole correctness of it: it encodes
  # "the plaintext volume is canonical", which is true for the forward path before the swap and
  # FALSE for every line of rollback(), where the canonical mapper is the store by design. Putting
  # plaintext back mid-rollback mounts a half-copied backstop and restarts Redis on it.
  if [[ "$PHASE" == frozen ]] && ! mounted_from "$MNT" "$(dev_for "$PLAIN_ID")"; then
    if mountpoint -q "$MNT" 2>/dev/null; then umount "$MNT" 2>/dev/null || true; fi
    if [[ -e "$MAPPER_DIR/$CANON_NAME" ]]; then cryptsetup_cmd luksClose "$CANON_NAME" 2>/dev/null || true; fi
    mount "$(dev_for "$PLAIN_ID")" "$MNT" 2>/dev/null || true
  fi
  # THE ROLLBACK-PHASE REPAIR, the mirror image: during rollback() the canonical mapper IS the
  # store, and the only window in which /mnt/data is not a mount is between its `umount "$MNT"` and
  # the final `mount "$plain_dev" "$MNT"`. A refusal or kill inside that window (rollback-mapper-
  # still-open is the named one) used to fall through to resume_writers, which started Redis onto a
  # bare root-disk directory; the Redis mount guard refused, and the scheduler was dark until a
  # reboot. Put a store back first: the mapper if it is still open (the reverse copy is not known
  # complete until luksClose succeeded), else the plaintext volume if this rollback's own latch says
  # the reverse copy was verified.
  if [[ "$PHASE" == rollback ]] && ! is_real_mount "$MNT"; then
    if [[ -e "$MAPPER_DIR/$CANON_NAME" ]]; then
      mount "$MAPPER_DIR/$CANON_NAME" "$MNT" 2>/dev/null || true
    elif [[ -s "$STATE_DIR/rollback-verified.latch" ]]; then
      mount "$(dev_for "$PLAIN_ID")" "$MNT" 2>/dev/null || true
    fi
  fi
  # RESUME ON THE RECORD, not on the phase. A process that did not perform the freeze (the tick
  # AFTER a kill) has PHASE=init and would resume nothing — which is how a crash mid-swap left the
  # sole scheduler stopped with the flag driven terminal, permanently, on a host with no way in.
  # The record is written by the freeze and cleared by a completed resume.
  if [[ "$PHASE" == frozen || "$PHASE" == swapped || "$PHASE" == rollback ]] || [[ -s "$(FROZEN_RECORD)" ]]; then
    resume_writers_best_effort
  fi
}

# refuse <reason> <detail> — a guard said no. Restore service, go terminal, exit 1.
# THE FLAG AN ABORT WRITES. `aborted` is TERMINAL — the next tick no-ops on it — so it is only
# correct when the host is back in a world a re-dispatch can act on. A swap that has LANDED is not
# that world: PHASE=swapped means /mnt/data is already the canonical mapper on the additive volume
# and only the bookkeeping (envfile, fstab, the durable pointer) is incomplete. swap_forward's own
# comment says "the next 30s tick can finish" that bookkeeping, and that was true only for a
# SIGKILL, which skips every trap and leaves the flag at `copied`. A SIGTERM (TimeoutStartSec), an
# ERR-trapped Doppler failure on the pointer write, or a refusal inside envfile_pointer/fstab_set
# all ran through here and wrote `aborted` — a host serving the encrypted store with the pointer
# ABSENT, no verb able to reach it (luks-cutover refuses on-host as canonical-not-plaintext,
# luks-rollback refuses at G2 on the absent pointer), and a reboot before fstab was rewritten
# serving the STALE plaintext store. Found at the ship-time advisor consult. Writing `copied`
# instead hands the next tick to repair_forward_if_swapped, which re-drives the bookkeeping; a
# refusal that persists there loops every 30s under this unit's own tag, which is LOUD, where
# `aborted` was silent.
#
# A rollback-phase abort still writes `aborted`: re-driving a rollback automatically is not safe
# (the backstop may be detached — rollback-no-backstop), so it is left to the operator, and the
# dispatcher's G1 admits `aborted` for op=luks-rollback when the pointer is PRESENT, because the
# pointer — not the flag — is the declared authority for where the store is.
abort_flag() {
  if [[ "${PHASE:-init}" == swapped ]]; then printf 'copied'; else printf 'aborted'; fi
}
refuse() {
  local f; f="$(abort_flag)"
  emit_state 1 "$1" "$f" "$2"
  restore_service_best_effort
  flag_set "$f"
  exit 1
}

# ── Device predicates ───────────────────────────────────────────────────────────────────────────
dev_for() { printf '%s%s' "$BYID" "$1"; }
# mounted_from <mountpoint> <expected-source> — the mount's SOURCE resolves to the expected device.
# `tail -1`, never `head -1`: findmnt lists a stacked mountpoint oldest-first, so head returns the
# SHADOWED mount while the last one is what the kernel actually serves. restore_service_best_effort
# umounts with `|| true` and then mounts unconditionally, so a busy umount stacks — and head would
# then report the mapper while Redis writes to the plaintext volume on top of it.
mounted_from() {
  local src
  src="$(findmnt -no SOURCE "$1" 2>/dev/null | tail -1)" || src=""
  [[ -n "$src" && "$(readlink -f "$src")" == "$(readlink -f "$2")" ]]
}
# same_device <a> <b> — the two paths resolve to ONE filesystem. Path inequality is not device
# inequality: two mountpoints of the same device have different paths and identical st_dev.
same_device() {
  local da db
  da="$(stat -c %d "$1" 2>/dev/null)" || return 1
  db="$(stat -c %d "$2" 2>/dev/null)" || return 1
  [[ -n "$da" && "$da" == "$db" ]]
}
# backing_is <mapper-name> <device> — the mapper's ONLY backing device is <device> (sysfs slaves/).
backing_is() {
  local dm want got
  dm="$(basename "$(readlink -f "$MAPPER_DIR/$1")")" || dm=""
  want="$(basename "$(readlink -f "$2")")" || want=""
  got="$(ls "$SYSFS/$dm/slaves" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" || got=""
  [[ -n "$want" && "$got" == "$want" ]]
}
# is_real_mount — st_dev differs from the parent's. `mountpoint` is fooled by systemd's self-binds
# under ProtectSystem (inngest-cutover-flip.sh #7761); a bind mount preserves st_dev.
is_real_mount() {
  local d pd
  d="$(stat -L -c %d "$1" 2>/dev/null)" || return 1
  pd="$(stat -L -c %d "$1/.." 2>/dev/null)" || return 1
  [[ -n "$d" && -n "$pd" && "$d" != "$pd" ]]
}

# ── T1: the last reading before the stop ───────────────────────────────────────────────────────
# INFO keyspace SUM, not DBSIZE: DBSIZE reads database 0 only and this store spans several — the
# probe emitter already recorded a summed 16 against a db0 read of nothing.
keyspace_sum() {  # prints "<keys> <expires>" or "__UNREADABLE__"
  local out
  out="$(redis_cli_cmd INFO keyspace 2>/dev/null)" || { printf '__UNREADABLE__'; return; }
  # AN ERROR REPLY EXITS 0. `NOAUTH`/`WRONGPASS` print to stdout and return success, the awk finds no
  # db line, and the sum reads a perfectly valid "0 0" — which makes T3's two population predicates
  # vacuous and lets an EMPTY store cut over and be marked done. The section header is what
  # separates "Redis answered and the store is empty" from "Redis refused to answer".
  printf '%s\n' "$out" | grep -qi '^# Keyspace' || { printf '__UNREADABLE__'; return; }
  printf '%s\n' "$out" | awk -F'[,:=]' '
    /^db[0-9]+:/ { for (i = 1; i < NF; i++) { if ($i == "keys") k += $(i+1); if ($i == "expires") e += $(i+1) } found = 1 }
    END { if (!found) { k = 0; e = 0 } printf "%d %d", k, e }'
}
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ── Freeze / quiesce / resume ──────────────────────────────────────────────────────────────────
# THE RESUME SET IS RECORDED, NOT ASSUMED (#8077 Guard 2 #6c). An unconditional `start
# inngest-server.service` re-arms a scheduler an operator deliberately quiesced — the class
# ci-deploy.test.sh's start-writer inventory exists to catch. So the freeze records which units
# were ACTIVE before it stopped them, into this FSM's own state dir (the run that resumes may be a
# later 30s tick, or a later boot), and the resume starts exactly those and nothing else.
FROZEN_RECORD() { printf '%s/frozen-active' "$STATE_DIR"; }
freeze_writers() {
  local u active=""
  # PHASE first: a failure or a kill DURING the stops must still resume what was already stopped.
  PHASE=frozen
  for u in $FREEZE_TIMERS $FREEZE_SERVICES; do
    if systemctl_cmd is-active --quiet "$u"; then active="$active $u"; fi
  done
  # UNION with the record a previous process left, never overwrite it. A re-entry after a kill
  # (the copied) and rollback) arms both freeze again) finds the units that earlier freeze stopped
  # already INACTIVE — so they are not in this pass's `active`, and an overwrite would drop them
  # from the record for good: the resume then restarts only what THIS pass stopped (the timers) and
  # Redis stays down with the flag reading rolled-back. Measured in the rb-unmounted-window world.
  # resume_writers consumes the record, so a union never resumes a unit twice across ticks.
  local prev u2
  prev="$(cat "$(FROZEN_RECORD)" 2>/dev/null || true)"
  for u2 in $prev; do
    case " $active " in *" $u2 "*) : ;; *) active="$active $u2" ;; esac
  done
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s\n' "$active" > "$(FROZEN_RECORD)" 2>/dev/null || true
  for u in $FREEZE_TIMERS; do systemctl_cmd stop "$u"; done
  for u in $FREEZE_SERVICES; do systemctl_cmd stop "$u"; done
  for u in $FREEZE_SERVICES; do
    if systemctl_cmd is-active --quiet "$u"; then refuse unit-still-active "$u is still active after stop"; fi
  done
}
# assert_quiesced <dir>... — no process holds an fd or cwd under any of the dirs. A /proc walk, so
# it needs no lsof/fuser (neither is in this host's package list).
assert_quiesced() {
  local d fd link p holders=""
  for p in "$PROC"/[0-9]*; do
    [[ -d "$p" ]] || continue
    for link in "$p"/cwd "$p"/fd/*; do
      [[ -e "$link" || -L "$link" ]] || continue
      fd="$(readlink "$link" 2>/dev/null)" || continue
      for d in "$@"; do
        case "$fd" in "$d"|"$d"/*) holders="$holders ${p##*/}"; break ;; esac
      done
    done
  done
  [[ -z "$holders" ]] || refuse mount-not-quiesced "pids still holding $*:$holders"
}
resume_writers() {
  local u recorded=""
  recorded="$(cat "$(FROZEN_RECORD)" 2>/dev/null || true)"
  if [[ -z "${recorded// /}" ]]; then
    # No record: this process did not perform the freeze (a resume after a reboot or a kill). Fall
    # back to the ENABLED set — still never starting a unit the operator has disabled, and still
    # never starting one unconditionally.
    for u in $FREEZE_TIMERS $FREEZE_SERVICES; do
      if systemctl_cmd is-enabled --quiet "$u" 2>/dev/null; then recorded="$recorded $u"; fi
    done
  fi
  # Redis before the server (its only client), timers last so nothing re-fires mid-resume.
  for u in inngest-redis.service inngest-server.service $FREEZE_TIMERS; do
    case " $recorded " in *" $u "*) systemctl_cmd start "$u" ;; esac
  done
  # Consumed: the record exists to answer "is something still frozen?", so leaving it behind would
  # make every later failure path resume units it never stopped.
  rm -f "$(FROZEN_RECORD)" 2>/dev/null || true
}
resume_writers_best_effort() { resume_writers 2>/dev/null || true; }

# ── Copy + T2 (the hard-abort predicate; no Redis is started) ───────────────────────────────────
# copy_store <src-mnt> <dst-mnt> — replace dst's contents with src's, whole mount (Fork L).
copy_store() {
  local src="$1" dst="$2"
  # This function `rm -rf`s the destination's contents, so it checks the destination ITSELF rather
  # than trusting every caller to have: never empty, never /, never the source, always a real mount.
  case "$dst" in ""|/|//|/.) refuse copy-dst-unsafe "destination '$dst'" ;; /*) : ;; *) refuse copy-dst-unsafe "destination '$dst' is relative" ;; esac
  [[ "$(readlink -f "$dst")" != "$(readlink -f "$src")" ]] || refuse copy-dst-is-src "$dst"
  # DEVICE identity, not path identity. A rollback killed after it remounted the plaintext volume at
  # /mnt/data re-enters with that volume mounted at BOTH paths: the strings differ, the device does
  # not, and the `find … rm -rf` below empties the live store before `cp` notices it is copying a
  # file onto itself. Measured against a real kernel with two bind mounts of one directory.
  ! same_device "$dst" "$src" || refuse copy-dst-is-src "$dst and $src are the same filesystem"
  is_real_mount "$dst" || refuse copy-dst-not-a-mount "$dst"
  # The SOURCE was unguarded: a kill between two umounts leaves /mnt/data a bare root-disk directory,
  # and copying THAT over the backstop is the same wipe by another route.
  is_real_mount "$src" || refuse copy-src-not-a-mount "$src"
  # The destination is cleared first, so a retry after a partial copy never merges old and new.
  # lost+found is filesystem metadata that mkfs creates on BOTH sides; it is left alone.
  # The trailing slash makes find descend into $dst even when the path reaches it via a symlink.
  find "$dst/" -mindepth 1 -maxdepth 1 ! -name lost+found -exec rm -rf -- {} +
  cp -a -- "$src/." "$dst/"
}
# tree_listing <root> — relative path + type + size + sha256 per regular file, sorted. Readability
# is a SEPARATE predicate: an unreadable tree prints the sentinel, never an empty listing that would
# compare equal to another empty listing.
tree_listing() {
  local root="$1"
  ( cd "$root" && find . -mindepth 1 ! -path './lost+found' ! -path './lost+found/*' -printf '%y %s %p\n' | LC_ALL=C sort ) 2>/dev/null \
    || { printf '__UNREADABLE__'; return; }
}
tree_checksums() {
  local root="$1"
  ( cd "$root" && find . -type f ! -path './lost+found/*' -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum ) 2>/dev/null \
    || { printf '__UNREADABLE__'; return; }
}
tree_bytes() {  # the sum of regular-file sizes; du -sb counts directory blocks, which differ by device
  local root="$1"
  ( cd "$root" && find . -type f ! -path './lost+found/*' -printf '%s\n' | awk '{ s += $1 } END { printf "%d", s }' ) 2>/dev/null \
    || { printf '__UNREADABLE__'; return; }
}
# t2_verify <src-mnt> <dst-mnt> — byte identity over a FROZEN source. Every reading's readability is
# checked on its own before any comparison: an unreadable sentinel compared as a string would not
# equal a real listing, but merged into a numeric test it would coerce, and the two are kept apart.
# t2_check <src> <dst> — a PURE predicate: prints the failing reason and returns 1, or returns 0.
# It touches no flag and no unit, so it can also be used to ask "is an existing copy still valid?"
# without that question aborting the run (the `copied` resume below does exactly that).
t2_check() {
  local src="$1" dst="$2" a b u
  for u in $FREEZE_SERVICES $CONFLICT_SERVICES; do
    if systemctl_cmd is-active --quiet "$u"; then printf 't2-unit-active %s' "$u"; return 1; fi
  done
  a="$(tree_listing "$src")"; b="$(tree_listing "$dst")"
  if [[ "$a" == "__UNREADABLE__" || "$b" == "__UNREADABLE__" ]]; then printf 't2-listing-unreadable'; return 1; fi
  [[ "$a" == "$b" ]] || { printf 't2-listing-differs'; return 1; }
  a="$(tree_checksums "$src")"; b="$(tree_checksums "$dst")"
  if [[ "$a" == "__UNREADABLE__" || "$b" == "__UNREADABLE__" ]]; then printf 't2-checksums-unreadable'; return 1; fi
  [[ "$a" == "$b" ]] || { printf 't2-checksums-differ'; return 1; }
  a="$(tree_bytes "$src")"; b="$(tree_bytes "$dst")"
  if ! is_uint "$a" || ! is_uint "$b"; then printf 't2-bytes-unreadable'; return 1; fi
  [[ "$a" -eq "$b" ]] || { printf 't2-bytes-differ %s/%s' "$a" "$b"; return 1; }
  # Fork L: the flip FSM's flush latch is ONE path and the property is about that path.
  #
  # EQUIVALENT-MUTANT NOTE, measured rather than assumed. The latch lives INSIDE the tree the two
  # legs above walk, so every way it can differ -- absent on the copy, or present with different
  # bytes -- is already caught by `t2-listing-differs` or `t2-checksums-differ`. Deleting this leg
  # therefore leaves the suite green (mutation row "T2 flip-latch leg deleted", SURVIVED), and that
  # survival is the truth about the leg, not a gap in the suite: the suite's own `t2-latch` row
  # asserts rc only, because the REASON at that point belongs to the checksum leg.
  #
  # It is kept, and kept HERE, on purpose. Moving it above the listing leg to make it reachable was
  # tried and rejected: `t2-latch` would then out-rank `t2-listing-unreadable`, and an unreadable
  # destination would be reported as a mid-copy flip -- trading a vacuous leg for a wrong
  # diagnosis. What it does buy is a named failure if either tree walker is ever narrowed (an
  # exclude added to `find`, a checksum leg restricted to the AOF directory), which would silently
  # drop the one path whose divergence means a second FLUSHALL ran.
  if [[ -e "$src/$FLIP_LATCH_REL" ]] && ! cmp -s "$src/$FLIP_LATCH_REL" "$dst/$FLIP_LATCH_REL"; then
    printf 't2-flip-latch-missing'; return 1
  fi
  # Read-only structural AOF check on the COPY (never --fix: that truncates from the first bad byte).
  if [[ -e "$dst/$AOF_MANIFEST_REL" ]]; then
    command -v redis-check-aof >/dev/null 2>&1 || { printf 't2-aof-checker-absent'; return 1; }
    redis-check-aof "$dst/$AOF_MANIFEST_REL" >/dev/null 2>&1 || { printf 't2-aof-structure'; return 1; }
  fi
  return 0
}
t2_verify() {  # the refusing wrapper: T2 is a hard abort
  local why
  why="$(t2_check "$1" "$2")" || refuse "${why%% *}" "T2 failed: $why (src=$1 dst=$2)"
}
record_copy_latch() {  # completion-with-verification, in this FSM's own state dir — never the flip's
  mkdir -p "$STATE_DIR" && printf 'copy_verified_at=%s k_freeze=%s e_freeze=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$K_FREEZE" "$E_FREEZE" >> "$STATE_DIR/copy-verified.latch" \
    || refuse latch-unrecordable "could not append $STATE_DIR/copy-verified.latch"
}

# ── fstab + staged env ─────────────────────────────────────────────────────────────────────────
fstab_set() {  # fstab_set <mountpoint> [<line>] — replace in place; no line = remove; assert ≤1
  local tmp
  tmp="$(mktemp "$FSTAB.cutover.XXXXXX")"; LUKS_TMPFILES+=("$tmp")
  awk -v mp="$1" '$1 ~ /^#/ || $2 != mp' "$FSTAB" > "$tmp"
  [[ -z "${2:-}" ]] || printf '%s\n' "$2" >> "$tmp"
  # mv, not `cat >`: a death or ENOSPC mid-write leaves /etc/fstab TRUNCATED, and under `nofail`
  # the next boot then mounts nothing at /mnt/data. The tempfile is already beside the target, which
  # is what makes the rename atomic — the sibling envfile_pointer has always done this.
  chmod 0644 "$tmp"; mv -f "$tmp" "$FSTAB"
  local n; n="$(awk -v mp="$1" '$1 !~ /^#/ && $2 == mp' "$FSTAB" | wc -l)"
  if [[ -n "${2:-}" ]]; then [[ "$n" -eq 1 ]] || refuse fstab-not-exactly-one "$1 has $n lines"
  else [[ "$n" -eq 0 ]] || refuse fstab-not-removed "$1 still has $n lines"; fi
}
envfile_pointer() {  # envfile_pointer <id|""> — the boot-reopen unit's staged copy of the pointer
  local tmp; tmp="$(mktemp "$ENVFILE.cutover.XXXXXX")"; LUKS_TMPFILES+=("$tmp")
  grep -v '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$ENVFILE" > "$tmp" || true
  # The same file carries the boot-reopen unit's passphrase. A rewrite that dropped it would leave
  # the unit unable to open anything on the next boot, so its survival is asserted before the move.
  if ! grep -q '^INNGEST_REDIS_LUKS_KEY=' "$tmp"; then rm -f "$tmp"; refuse envfile-key-lost "the rewrite of $ENVFILE would drop the passphrase"; fi
  [[ -z "$1" ]] || printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=%s\n' "$1" >> "$tmp"
  chmod 0600 "$tmp"; mv -f "$tmp" "$ENVFILE"
  # COUNTED, not merely present — systemd's EnvironmentFile is last-wins, so a duplicate line from
  # any other writer would silently decide which volume the boot-reopen unit opens. The sibling
  # fstab_set has always counted; this one asserted presence until the enumeration pass caught it.
  #
  # EQUIVALENT-MUTANT NOTE. This is a post-condition on THIS function's own write: the `grep -v`
  # above strips every pre-existing pointer line and at most one is appended, so `n` is 1 (or 0)
  # by construction and no input can drive the count elsewhere. Weakening `-eq 1` to a presence
  # test therefore leaves the suite green (mutation row "envfile cardinality -> presence",
  # SURVIVED), and the suite's `envfile-dup` row -- which seeds a SECOND pointer line before the
  # run -- passes either way for the same reason. The check stays because it is the assertion a
  # future edit would break: replace the `grep -v` with a targeted `sed`, or append before
  # stripping, and this line is what says so.
  local n; n="$(grep -c '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$ENVFILE" || true)"
  if [[ -n "$1" ]]; then
    { [[ "$n" -eq 1 ]] && grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$1" "$ENVFILE"; } || refuse envfile-pointer "expected exactly one staged pointer line, found $n"
  else
    [[ "$n" -eq 0 ]] || refuse envfile-pointer "expected the pointer line removed, found $n"
  fi
}

# ── Preconditions ──────────────────────────────────────────────────────────────────────────────
assert_ids() {
  is_uint "$PLAIN_ID" && is_uint "$LUKS_ID" && [[ "$PLAIN_ID" != "$LUKS_ID" ]] \
    || refuse volume-ids-unreadable "plain='$PLAIN_ID' additive='$LUKS_ID' (staged by the first-boot stage)"
  # The unit runs `doppler run --no-exit-on-missing-only-secrets`, so a name missing from Doppler
  # arrives as an absent variable rather than a failed start. The passphrase is first dereferenced
  # mid-swap, with the store unmounted — where `set -u` would kill the script without the ERR trap
  # and leave the scheduler dark. So its presence is asserted here, before anything stops.
  [[ -n "${INNGEST_REDIS_LUKS_KEY:-}" ]] || refuse luks-key-absent "INNGEST_REDIS_LUKS_KEY was not injected"
  # The Redis password is the same class of input: absent, every INFO returns an error reply, and
  # the store predicates below go quiet rather than loud.
  [[ -n "${INNGEST_REDIS_PASSWORD:-}" ]] || refuse redis-password-absent "INNGEST_REDIS_PASSWORD was not injected; every keyspace read would return an error reply"
}
# The pre-cutover world, proven through both links on both sides before anything is stopped.
assert_precutover_topology() {
  [[ -z "$(current_pointer)" ]] || refuse pointer-already-set "the pointer names $(current_pointer); this host is past the cutover"
  is_real_mount "$MNT" || refuse not-a-mount "$MNT"
  mounted_from "$MNT" "$(dev_for "$PLAIN_ID")" || refuse canonical-not-plaintext "$MNT is not mounted from the plaintext volume"
  is_real_mount "$STAGING_MNT" || refuse staging-not-a-mount "$STAGING_MNT"
  mounted_from "$STAGING_MNT" "$MAPPER_DIR/$STAGING_NAME" || refuse staging-not-mapper "$STAGING_MNT is not the staging mapper"
  backing_is "$STAGING_NAME" "$(dev_for "$LUKS_ID")" || refuse staging-wrong-backing "the staging mapper is not backed by the additive volume"
  [[ ! -e "$MAPPER_DIR/$CANON_NAME" ]] || refuse canonical-mapper-open "$CANON_NAME is open pre-cutover"
  # The swap rewrites this file to stage the pointer; if it does not carry the passphrase already,
  # the boot-reopen unit could not open the store on the next boot. Checked before anything stops.
  grep -q '^INNGEST_REDIS_LUKS_KEY=' "$ENVFILE" 2>/dev/null || refuse envfile-key-absent "$ENVFILE carries no passphrase"
  assert_no_conflicting_fsm
}
# The sibling FSM must not be mid-run. Checked before the freeze AND again inside T2 (a flip that
# starts during the copy window is the case a single entry check cannot see).
assert_no_conflicting_fsm() {
  local u
  for u in $CONFLICT_SERVICES; do
    if systemctl_cmd is-active --quiet "$u"; then
      refuse flip-in-flight "$u is running: it owns the FLUSHALL and restarts the server; the two FSMs must not overlap"
    fi
  done
}

# ── Swap (forward) ─────────────────────────────────────────────────────────────────────────────
swap_forward() {
  local luks_dev; luks_dev="$(dev_for "$LUKS_ID")"
  umount "$STAGING_MNT"
  cryptsetup_cmd luksClose "$STAGING_NAME"
  umount "$MNT"
  printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$luks_dev" "$CANON_NAME"
  mount "$MAPPER_DIR/$CANON_NAME" "$MNT"
  mounted_from "$MNT" "$MAPPER_DIR/$CANON_NAME" || refuse swap-mount-source "$MNT is not the canonical mapper after the swap"
  backing_is "$CANON_NAME" "$luks_dev" || refuse swap-wrong-backing "the canonical mapper is not backed by the additive volume"
  # PHASE FIRST, and it is not a formality: bash defers the TERM trap until the foreground command
  # returns, so a kill during the Doppler call below is deferred for the whole network round trip.
  # With PHASE still `frozen` the restore branch would put the PLAINTEXT volume back underneath a
  # pointer that already names the encrypted one — Redis live on a device the pointer disclaims.
  PHASE=swapped
  # ORDER: the ON-HOST world first, the durable pointer LAST.
  #
  # These are three non-atomic writes read by DIFFERENT consumers: `/etc/default/inngest-luks` by the
  # boot-reopen unit, `/etc/fstab` by systemd's generator, Doppler by this FSM and by a first boot.
  # A crash between them desynchronises, and the direction matters. Pointer-first leaves Doppler
  # naming the encrypted volume while fstab still mounts the plaintext one, so a reboot serves
  # plaintext under an encrypted claim — the silent un-encryption this whole change exists to
  # prevent. Pointer-LAST leaves the host correctly serving encrypted with Doppler merely stale,
  # which the next 30s tick can finish and which no reader misreads as encrypted.
  envfile_pointer "$LUKS_ID"
  fstab_set "$MNT" "$MAPPER_DIR/$CANON_NAME $MNT ext4 defaults,nofail 0 2"
  fstab_set "$STAGING_MNT"
  # systemd-fstab-generator built mnt-data.mount from the OLD line at boot, and it keeps that
  # `What=` until a reload — so between here and the next daemon-reload, a `systemctl restart
  # mnt-data.mount` (or any dependency pulling it) remounts the PLAINTEXT device over the encrypted
  # store. Reloading is cheap and makes the generated unit agree with the fstab we just wrote.
  systemctl_cmd daemon-reload || true
  pointer_cmd set "$LUKS_ID"
}

# repair_forward_if_swapped — returns 0 when the world is already past the swap and has been made
# consistent, 1 when it is still pre-cutover and the ordinary path applies.
#
# The test is the MOUNT, not the flag: the flag is what we failed to write. If /mnt/data is the
# canonical mapper backed by the additive volume, the swap succeeded and only the bookkeeping is
# missing — so finish the bookkeeping in the same order swap_forward writes it.
repair_forward_if_swapped() {
  # THE UNMOUNTED WINDOW. A kill without a trap (SIGKILL, OOM) between swap_forward's `umount "$MNT"`
  # and its `mount "$MAPPER_DIR/$CANON_NAME" "$MNT"` leaves nothing mounted at /mnt/data: the next
  # tick has PHASE=init, the frozen-only mount repair does not fire, the check below sees no mapper
  # mount, and assert_precutover_topology refuses `not-a-mount` — terminal, with the writers
  # resumed onto a bare directory the Redis guard refuses. Dark until a reboot. The world is
  # identifiable: the copy latch is present (T2 passed), staging is torn down (swap_forward's first
  # two steps), and /mnt/data is not a mount. Every step of swap_forward past that point is
  # idempotent, so re-drive it: open the canonical mapper if the kill landed before luksOpen, mount
  # it, and fall into the bookkeeping below.
  if ! is_real_mount "$MNT" && ! is_real_mount "$STAGING_MNT" && [[ -s "$STATE_DIR/copy-verified.latch" ]]; then
    if [[ ! -e "$MAPPER_DIR/$CANON_NAME" ]]; then
      printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$(dev_for "$LUKS_ID")" "$CANON_NAME"
    fi
    mount "$MAPPER_DIR/$CANON_NAME" "$MNT"
    emit_state 0 repair-remount swapped "a kill landed between the two mounts of the swap; the canonical mapper is re-mounted"
  fi
  mounted_from "$MNT" "$MAPPER_DIR/$CANON_NAME" || return 1
  backing_is "$CANON_NAME" "$(dev_for "$LUKS_ID")" \
    || refuse repair-wrong-backing "$MNT is the canonical mapper but it is not backed by the additive volume"
  PHASE=swapped
  emit_state 0 repair-forward swapped "a kill landed inside the swap; the mount is correct, completing the bookkeeping"
  envfile_pointer "$LUKS_ID"
  fstab_set "$MNT" "$MAPPER_DIR/$CANON_NAME $MNT ext4 defaults,nofail 0 2"
  fstab_set "$STAGING_MNT"
  systemctl_cmd daemon-reload || true
  [[ -n "$(current_pointer)" ]] || pointer_cmd set "$LUKS_ID"
  return 0
}
# THE TORN-DOWN STAGING WINDOW, the other half of the same kill. Between swap_forward's
# `umount "$STAGING_MNT"` and its `umount "$MNT"`, plaintext is still the store but the staging
# mapper is unmounted (and, one step later, closed). The next tick's assert_precutover_topology
# then refuses `staging-not-a-mount` on every re-arm until a reboot re-stages the volume. The
# pre-cutover topology is cheap to restore and every step is idempotent, and the `copied)` arm
# re-verifies the copy against the plaintext store (t2_check) before it swaps, so nothing here
# trusts the latch. Only fires when /mnt/data IS the plaintext volume — the forward repair above
# owns the other world.
restage_if_torn_down() {
  mounted_from "$MNT" "$(dev_for "$PLAIN_ID")" || return 0
  is_real_mount "$STAGING_MNT" && return 0
  if [[ ! -e "$MAPPER_DIR/$STAGING_NAME" ]]; then
    printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$(dev_for "$LUKS_ID")" "$STAGING_NAME"
  fi
  mkdir -p "$STAGING_MNT"
  mount "$MAPPER_DIR/$STAGING_NAME" "$STAGING_MNT"
  emit_state 0 repair-restage copied "a kill landed after the staging teardown; the staging mapper is re-mounted so the swap can re-drive"
}

# ── T3: after the restart, on the canonical mapper ─────────────────────────────────────────────
t3_verify() {
  local deadline code fns k_after
  deadline=$(( $(date +%s) + VERIFY_WINDOW_S ))
  while :; do
    code="$(curl_cmd -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" 2>/dev/null || echo 000)"
    if [[ "$code" == "200" ]]; then
      # The GraphQL `functions` count, never the unregistered REST route (a 404 body reads as zero).
      # Type-guarded exactly as inngest-cutover-flip.sh's verify_serving: `.data.functions | length`
      # alone reads a null as 0 and a STRING as its character count — the second is a false serving.
      fns="$(curl_cmd -s --max-time 5 -H 'content-type: application/json' \
        --data-binary '{"query":"query RegistryProbe { functions { id } }"}' "$GQL_URL" 2>/dev/null \
        | jq -r '(.data.functions // null) | if type == "array" then length else "nan" end' 2>/dev/null || echo "")"
      is_uint "$fns" && [[ "$fns" -ge 1 ]] && break
    fi
    [[ "$(date +%s)" -lt "$deadline" ]] || return 10
    sleep "$VERIFY_INTERVAL_S"
  done
  # The fourth predicate: /health and functions are Postgres and registration facts, and an EMPTY
  # store answers both. The keyspace sum on the canonical mapper is the one that sees the store.
  read -r k_after _ <<< "$(keyspace_sum)" || k_after=""
  is_uint "$k_after" || return 11                                        # readability, on its own
  [[ ! ( "$K_FREEZE" -gt 0 && "$k_after" -eq 0 ) ]] || return 12          # a populated store read empty
  [[ "$k_after" -ge $(( K_FREEZE - E_FREEZE )) ]] || return 13            # volatile keys may expire; no more
  mounted_from "$MNT" "$MAPPER_DIR/$CANON_NAME" || return 14
  # The mapper NAME is not the device. swap_forward proves the backing; the `swapped` resume arm
  # reaches T3 without ever having run swap_forward, so without this it never proves it at all.
  backing_is "$CANON_NAME" "$(dev_for "$LUKS_ID")" || return 15
  return 0
}

# ── Rollback: reverse-copy, then swap back ─────────────────────────────────────────────────────
rollback() {
  local plain_dev luks_dev rc=0
  plain_dev="$(dev_for "$PLAIN_ID")"; luks_dev="$(dev_for "$LUKS_ID")"
  # -e on the by-id ALIAS, which the platform only creates for an attached volume: that is the
  # question ("is the backstop attached?"), and -e follows the alias to the device node.
  [[ -e "$plain_dev" ]] || refuse rollback-no-backstop "the plaintext volume is not attached; there is nothing to roll back onto"
  freeze_writers
  PHASE=rollback
  assert_quiesced "$MNT"
  mkdir -p "$PLAIN_MNT"
  # RE-ENTRY ACROSS THE UNMOUNTED WINDOW: a rollback killed after `luksClose` but before the final
  # `mount "$plain_dev" "$MNT"` left nothing at /mnt/data and the reverse copy already PROVEN (the
  # latch written after t2_verify below). Copying again would refuse `copy-src-not-a-mount` —
  # terminal, and dark. Put the plaintext volume back and take the finished path below. The mapper
  # must be gone: with it open the reverse copy is not known complete, and the plain volume would
  # be mounted under an open canonical mapper — the pair the Redis guard refuses.
  if ! is_real_mount "$MNT" && [[ ! -e "$MAPPER_DIR/$CANON_NAME" ]] && [[ -s "$STATE_DIR/rollback-verified.latch" ]]; then
    if mountpoint -q "$PLAIN_MNT" 2>/dev/null; then umount "$PLAIN_MNT"; fi
    mount "$plain_dev" "$MNT"
    emit_state 0 rollback-remount rollback "a kill landed after the reverse copy was proven; the plaintext volume is re-mounted"
  fi
  # RE-ENTRY: a rollback killed after its final `mount "$plain_dev" "$MNT"` already put the store
  # back. Mounting the same device at the staging path too would give copy_store two views of one
  # filesystem — the wipe above. If /mnt/data is already the plaintext volume, the move is done.
  if mounted_from "$MNT" "$plain_dev"; then
    emit_state 0 rollback-already-restored rollback "/mnt/data is already the plaintext volume; finishing the bookkeeping"
    envfile_pointer ""
    fstab_set "$MNT" "$plain_dev $MNT ext4 defaults,nofail 0 2"
    # The pre-cutover world has the additive volume STAGED; a re-entry that skipped the teardown
    # below also skipped the re-stage, so do it here when it is missing (idempotent).
    if ! is_real_mount "$STAGING_MNT"; then
      if [[ ! -e "$MAPPER_DIR/$STAGING_NAME" ]]; then
        printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$luks_dev" "$STAGING_NAME"
      fi
      mkdir -p "$STAGING_MNT"
      mount "$MAPPER_DIR/$STAGING_NAME" "$STAGING_MNT"
      fstab_set "$STAGING_MNT" "$MAPPER_DIR/$STAGING_NAME $STAGING_MNT ext4 defaults,nofail 0 2"
    fi
    systemctl_cmd daemon-reload || true
    pointer_cmd clear
    rm -f "$STATE_DIR/rollback-verified.latch"
    PHASE=init
    resume_writers
    return 0
  fi
  mountpoint -q "$PLAIN_MNT" || mount "$plain_dev" "$PLAIN_MNT"
  mounted_from "$PLAIN_MNT" "$plain_dev" || refuse rollback-plain-mount "$PLAIN_MNT is not the plaintext volume"
  # copy_store CLEARS this destination, so it needs the same quiescence the source got. The forward
  # path passes both mounts; this one passed only the source until the enumeration pass caught it.
  assert_quiesced "$PLAIN_MNT"
  # Data-safe: whatever the encrypted store took since the swap is copied back and PROVEN equal
  # before anything points at the plaintext volume again.
  copy_store "$MNT" "$PLAIN_MNT"
  t2_verify "$MNT" "$PLAIN_MNT"
  # Proven-equal is recorded BEFORE the teardown that follows, in this FSM's own state dir: it is
  # what lets a re-entry (and restore_service_best_effort) put the plaintext volume back at
  # /mnt/data after a kill in the unmounted window without copying again from a source that is no
  # longer mounted.
  mkdir -p "$STATE_DIR" && printf 'rollback_verified_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/rollback-verified.latch"
  umount "$PLAIN_MNT"
  umount "$MNT"
  cryptsetup_cmd luksClose "$CANON_NAME"
  # The contract's teeth: a canonical mapper left open while /mnt/data is back on plaintext makes the
  # Redis guard refuse EVERY start, on a host with no inbound channel to close it.
  [[ ! -e "$MAPPER_DIR/$CANON_NAME" ]] || refuse rollback-mapper-still-open "$CANON_NAME survived luksClose"
  mount "$plain_dev" "$MNT"
  mounted_from "$MNT" "$plain_dev" || refuse rollback-mount-source "$MNT is not the plaintext volume after rollback"
  # Durable pointer LAST here too: envfile+fstab first means a crash leaves the host serving
  # plaintext with Doppler merely stale, which the next tick finishes. The reverse order leaves
  # Doppler cleared while the boot world still names the encrypted volume — a reboot would then
  # discard everything Redis wrote on plaintext since the rollback.
  envfile_pointer ""
  fstab_set "$MNT" "$plain_dev $MNT ext4 defaults,nofail 0 2"
  # Return to the pre-cutover world exactly: the additive volume staged again, non-canonically.
  printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$luks_dev" "$STAGING_NAME"
  mkdir -p "$STAGING_MNT"
  mount "$MAPPER_DIR/$STAGING_NAME" "$STAGING_MNT"
  fstab_set "$STAGING_MNT" "$MAPPER_DIR/$STAGING_NAME $STAGING_MNT ext4 defaults,nofail 0 2"
  systemctl_cmd daemon-reload || true
  pointer_cmd clear
  rm -f "$STATE_DIR/rollback-verified.latch"
  PHASE=init
  resume_writers
}

# ── Forward run ────────────────────────────────────────────────────────────────────────────────
run_copy_and_swap() {
  assert_precutover_topology
  # T1 — the last reading before the stop. Unreadable is a refusal, not a zero.
  read -r K_FREEZE E_FREEZE <<< "$(keyspace_sum)" || true
  is_uint "$K_FREEZE" && is_uint "$E_FREEZE" || refuse t1-unreadable "INFO keyspace could not be read before the freeze"
  freeze_writers
  assert_quiesced "$MNT" "$STAGING_MNT"
  # THE CRITICAL SECTION IS MINUTES LONG WITH EVERY WRITER STOPPED, and systemd will not re-run a
  # Type=oneshot that is still activating — so the 30s timer produces no rows here either. Without
  # these, an operator watching Better Stack cannot tell a running copy from a dead host, which is
  # the one distinction that decides whether to wait or to replace.
  emit_state 0 phase-frozen copying "writers stopped; k_freeze=$K_FREEZE e_freeze=$E_FREEZE"
  emit_state 0 phase-copy-start copying "copying the whole mount"
  copy_store "$MNT" "$STAGING_MNT"
  t2_verify "$MNT" "$STAGING_MNT"
  record_copy_latch
  flag_set copied
  emit_state 0 phase-copy-verified copied "T2 passed; swapping"
  swap_forward
  flag_set swapped
  emit_state 0 phase-swapped swapped "mount swapped; verifying on the canonical mapper"
  finish_after_swap
}
finish_after_swap() {
  resume_writers
  local rc=0; t3_verify || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    emit_state 1 "t3-failed-rc$rc" rollback "T3 failed after the swap; rolling back (data-safe reverse copy)"
    flag_set rollback
    rollback
    flag_set rolled-back
    emit_state 1 "t3-failed-rolled-back" rolled-back "rc=$rc"
    exit 1
  fi
  flag_set done
  emit_state 0 cutover-complete done "k_freeze=$K_FREEZE"
}

# on_term — systemd's TimeoutStartSec kill, or a stop. A signal does not fire the ERR trap, and a
# kill between the freeze and the resume would otherwise leave every writer stopped.
on_term() {
  trap - ERR TERM
  local f; f="$(abort_flag)"
  restore_service_best_effort
  flag_set "$f" 2>/dev/null || true
  emit_state 143 terminated "$f" "SIGTERM in phase $PHASE"
  exit 143
}

on_unexpected_exit() {
  local rc=$?
  trap - ERR TERM
  # Resume first: an unhandled failure must not leave the sole scheduler dark. The Redis mount guard
  # is the safety net that makes this safe in every phase — it refuses to start Redis onto a
  # /mnt/data that does not match the mapper state.
  local f; f="$(abort_flag)"
  restore_service_best_effort
  flag_set "$f" 2>/dev/null || true
  emit_state "$rc" "unexpected-exit(from=$(read_flag 2>/dev/null || echo unknown))" "$f"
  exit "$rc"
}

main() {
  trap on_unexpected_exit ERR
  trap on_term TERM
  # The probe must be able to measure (measurements.md §1).
  [[ "$(my_uid)" -eq 0 ]] || { emit_state 1 not-root "$(read_flag)"; exit 1; }
  # A single run at a time: the timer re-fires every 30s and a copy can outlast a tick.
  mkdir -p "$STATE_DIR"
  # A redirection failure here (ENOSPC, a read-only /var) fires the ERR trap and drives the flag
  # TERMINAL — spending the run on an infrastructure hiccup. It is not a statement about the store.
  exec 9>"$STATE_DIR/run.lock" || { emit_state 0 lock-unavailable "$(read_flag)" "could not open $STATE_DIR/run.lock"; exit 0; }
  if ! flock -n 9; then emit_state 0 in-progress "$(read_flag)" "another run holds the lock"; exit 0; fi
  local flag; flag="$(read_flag)"
  case "$flag" in
    armed)
      assert_ids
      flag_set copying
      run_copy_and_swap ;;
    copying)
      # A crash during the copy. The source is the canonical plaintext store and was never touched,
      # so re-running the whole freeze→copy→T2 is safe.
      assert_ids
      run_copy_and_swap ;;
    copied)
      # T2 passed and the latch was written, but the swap did not complete. TWO WORLDS land here and
      # only one of them is pre-cutover.
      #
      # If a kill landed INSIDE swap_forward, the host is already past the point of no return —
      # /mnt/data may be the canonical mapper, the mapper may be open, the pointer may be written.
      # Handing that world to assert_precutover_topology means refusing it (`not-a-mount`,
      # `canonical-mapper-open`, `pointer-already-set`), and a refusal is TERMINAL: the writers stay
      # stopped and every later tick no-ops. That turned a recoverable kill into a permanently dark
      # scheduler on a host with no inbound channel. So the mid-swap world is REPAIRED FORWARD
      # instead — every step of swap_forward past the mount is idempotent, which is what makes this
      # safe to re-drive rather than unwind.
      assert_ids
      if repair_forward_if_swapped; then
        flag_set swapped
        finish_after_swap
        return
      fi
      restage_if_torn_down
      assert_precutover_topology
      read -r K_FREEZE E_FREEZE <<< "$(keyspace_sum)" || true
      is_uint "$K_FREEZE" && is_uint "$E_FREEZE" || { K_FREEZE=0; E_FREEZE=0; }
      freeze_writers
      assert_quiesced "$MNT" "$STAGING_MNT"
      if ! t2_check "$MNT" "$STAGING_MNT" >/dev/null; then
        copy_store "$MNT" "$STAGING_MNT"
        t2_verify "$MNT" "$STAGING_MNT"
        record_copy_latch
      fi
      swap_forward
      flag_set swapped
      finish_after_swap ;;
    swapped)
      # The swap completed; resume and verify on the canonical mapper.
      assert_ids
      PHASE=swapped
      K_FREEZE="$( { sed -n 's/.*k_freeze=\([0-9]*\).*/\1/p' "$STATE_DIR/copy-verified.latch" 2>/dev/null || true; } | tail -1)"
      E_FREEZE="$( { sed -n 's/.*e_freeze=\([0-9]*\).*/\1/p' "$STATE_DIR/copy-verified.latch" 2>/dev/null || true; } | tail -1)"
      is_uint "$K_FREEZE" && is_uint "$E_FREEZE" || { K_FREEZE=0; E_FREEZE=0; }
      finish_after_swap ;;
    rollback)
      assert_ids
      [[ -n "$(current_pointer)" ]] || refuse rollback-no-pointer "no swap is recorded (pointer absent); nothing to roll back"
      # And it must name THIS host's additive volume. Any other value is a pointer this FSM did not
      # write, so "a swap has happened" is not what it evidences — rolling back on it would unmount
      # a store this host cannot account for.
      [[ "$(current_pointer)" == "$LUKS_ID" ]] || refuse rollback-pointer-mismatch "the pointer names $(current_pointer), not this host's additive volume $LUKS_ID"
      rollback
      flag_set rolled-back
      emit_state 0 rolled-back rolled-back ;;
    done)        emit_noop noop-done done ;;
    rolled-back) emit_noop noop-rolled-back rolled-back ;;
    aborted)     emit_noop noop-aborted aborted ;;
    *)           emit_noop noop-unset "${flag:-unset}" ;;
  esac
}

# Run only when executed directly — sourcing (unit tests) must not act on host state.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
