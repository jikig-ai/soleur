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
readonly FREEZE_SERVICES="inngest-server.service inngest-redis.service"
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
PHASE=init            # init | frozen | swapped — read by the ERR trap to decide what to resume
K_FREEZE=""; E_FREEZE=""

# ── Primitives (each a seam in the fixture path) ───────────────────────────────────────────────
logger_cmd() { "${LUKS_LOGGER_CMD:-logger}" "$@"; }
systemctl_cmd() { if [[ -n "${LUKS_SYSTEMCTL_CMD:-}" ]]; then "$LUKS_SYSTEMCTL_CMD" "$@"; else systemctl "$@"; fi; }
cryptsetup_cmd() { if [[ -n "${LUKS_CRYPTSETUP_CMD:-}" ]]; then "$LUKS_CRYPTSETUP_CMD" "$@"; else cryptsetup "$@"; fi; }
curl_cmd() { if [[ -n "${LUKS_CURL_CMD:-}" ]]; then "$LUKS_CURL_CMD" "$@"; else curl "$@"; fi; }
redis_cli_cmd() { if [[ -n "${LUKS_REDIS_CLI_CMD:-}" ]]; then "$LUKS_REDIS_CLI_CMD" "$@"; else redis-cli -a "${INNGEST_REDIS_PASSWORD:-}" "$@"; fi; }
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

# restore_service_best_effort — never leave the sole scheduler dark on a failure path. Before the
# pointer is written (PHASE=frozen) the plaintext volume is canonical, so a swap that got part-way
# (plaintext unmounted, canonical mapper opened) is put back first. After it (PHASE=swapped) the
# canonical mapper IS the store. Either way the Redis mount guard is the net under this: it refuses
# to start Redis onto a /mnt/data that does not match the mapper state.
restore_service_best_effort() {
  if [[ "$PHASE" == frozen ]] && ! mounted_from "$MNT" "$(dev_for "$PLAIN_ID")"; then
    if mountpoint -q "$MNT" 2>/dev/null; then umount "$MNT" 2>/dev/null || true; fi
    if [[ -e "$MAPPER_DIR/$CANON_NAME" ]]; then cryptsetup_cmd luksClose "$CANON_NAME" 2>/dev/null || true; fi
    mount "$(dev_for "$PLAIN_ID")" "$MNT" 2>/dev/null || true
  fi
  if [[ "$PHASE" == frozen || "$PHASE" == swapped ]]; then resume_writers_best_effort; fi
}

# refuse <reason> <detail> — a guard said no. Restore service, go terminal, exit 1.
refuse() {
  emit_state 1 "$1" aborted "$2"
  restore_service_best_effort
  flag_set aborted
  exit 1
}

# ── Device predicates ───────────────────────────────────────────────────────────────────────────
dev_for() { printf '%s%s' "$BYID" "$1"; }
# mounted_from <mountpoint> <expected-source> — the mount's SOURCE resolves to the expected device.
mounted_from() {
  local src
  src="$(findmnt -no SOURCE "$1" 2>/dev/null | head -1)" || src=""
  [[ -n "$src" && "$(readlink -f "$src")" == "$(readlink -f "$2")" ]]
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
  printf '%s\n' "$out" | awk -F'[,:=]' '
    /^db[0-9]+:/ { for (i = 1; i < NF; i++) { if ($i == "keys") k += $(i+1); if ($i == "expires") e += $(i+1) } found = 1 }
    END { if (!found) { k = 0; e = 0 } printf "%d %d", k, e }'
}
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ── Freeze / quiesce / resume ──────────────────────────────────────────────────────────────────
freeze_writers() {
  local u
  # PHASE first: a failure or a kill DURING the stops must still resume what was already stopped.
  PHASE=frozen
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
  local u
  for u in inngest-redis.service inngest-server.service; do systemctl_cmd start "$u"; done
  for u in $FREEZE_TIMERS; do systemctl_cmd start "$u"; done
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
  is_real_mount "$dst" || refuse copy-dst-not-a-mount "$dst"
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
  for u in $FREEZE_SERVICES; do
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
  tmp="$(mktemp "$FSTAB.cutover.XXXXXX")"
  awk -v mp="$1" '$1 ~ /^#/ || $2 != mp' "$FSTAB" > "$tmp"
  [[ -z "${2:-}" ]] || printf '%s\n' "$2" >> "$tmp"
  cat "$tmp" > "$FSTAB"; rm -f "$tmp"
  local n; n="$(awk -v mp="$1" '$1 !~ /^#/ && $2 == mp' "$FSTAB" | wc -l)"
  if [[ -n "${2:-}" ]]; then [[ "$n" -eq 1 ]] || refuse fstab-not-exactly-one "$1 has $n lines"
  else [[ "$n" -eq 0 ]] || refuse fstab-not-removed "$1 still has $n lines"; fi
}
envfile_pointer() {  # envfile_pointer <id|""> — the boot-reopen unit's staged copy of the pointer
  local tmp; tmp="$(mktemp "$ENVFILE.cutover.XXXXXX")"
  grep -v '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$ENVFILE" > "$tmp" || true
  # The same file carries the boot-reopen unit's passphrase. A rewrite that dropped it would leave
  # the unit unable to open anything on the next boot, so its survival is asserted before the move.
  if ! grep -q '^INNGEST_REDIS_LUKS_KEY=' "$tmp"; then rm -f "$tmp"; refuse envfile-key-lost "the rewrite of $ENVFILE would drop the passphrase"; fi
  [[ -z "$1" ]] || printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=%s\n' "$1" >> "$tmp"
  chmod 0600 "$tmp"; mv -f "$tmp" "$ENVFILE"
  if [[ -n "$1" ]]; then grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$1" "$ENVFILE" || refuse envfile-pointer "not staged"
  else ! grep -q '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$ENVFILE" || refuse envfile-pointer "not removed"; fi
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
  # Pointer and fstab. Neither order is atomic across Doppler and a file, and both fail SAFE: a
  # pointer without the fstab line mounts the plaintext volume under an open mapper, which the Redis
  # guard refuses; the fstab line without the pointer leaves the mapper unopened and /mnt/data
  # unmounted, which the guard also refuses. Durable pointer first.
  pointer_cmd set "$LUKS_ID"
  # From here the pointer names the encrypted volume, so a reboot takes the pointer arm: a failure
  # path must now keep the canonical mapper, not put the plaintext volume back.
  PHASE=swapped
  envfile_pointer "$LUKS_ID"
  fstab_set "$MNT" "$MAPPER_DIR/$CANON_NAME $MNT ext4 defaults,nofail 0 2"
  fstab_set "$STAGING_MNT"
  PHASE=swapped
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
  assert_quiesced "$MNT"
  mkdir -p "$PLAIN_MNT"
  mountpoint -q "$PLAIN_MNT" || mount "$plain_dev" "$PLAIN_MNT"
  mounted_from "$PLAIN_MNT" "$plain_dev" || refuse rollback-plain-mount "$PLAIN_MNT is not the plaintext volume"
  # Data-safe: whatever the encrypted store took since the swap is copied back and PROVEN equal
  # before anything points at the plaintext volume again.
  copy_store "$MNT" "$PLAIN_MNT"
  t2_verify "$MNT" "$PLAIN_MNT"
  umount "$PLAIN_MNT"
  umount "$MNT"
  cryptsetup_cmd luksClose "$CANON_NAME"
  # The contract's teeth: a canonical mapper left open while /mnt/data is back on plaintext makes the
  # Redis guard refuse EVERY start, on a host with no inbound channel to close it.
  [[ ! -e "$MAPPER_DIR/$CANON_NAME" ]] || refuse rollback-mapper-still-open "$CANON_NAME survived luksClose"
  mount "$plain_dev" "$MNT"
  mounted_from "$MNT" "$plain_dev" || refuse rollback-mount-source "$MNT is not the plaintext volume after rollback"
  pointer_cmd clear
  envfile_pointer ""
  fstab_set "$MNT" "$plain_dev $MNT ext4 defaults,nofail 0 2"
  # Return to the pre-cutover world exactly: the additive volume staged again, non-canonically.
  printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup_cmd luksOpen --key-file - "$luks_dev" "$STAGING_NAME"
  mkdir -p "$STAGING_MNT"
  mount "$MAPPER_DIR/$STAGING_NAME" "$STAGING_MNT"
  fstab_set "$STAGING_MNT" "$MAPPER_DIR/$STAGING_NAME $STAGING_MNT ext4 defaults,nofail 0 2"
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
  copy_store "$MNT" "$STAGING_MNT"
  t2_verify "$MNT" "$STAGING_MNT"
  record_copy_latch
  flag_set copied
  swap_forward
  flag_set swapped
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
  restore_service_best_effort
  flag_set aborted 2>/dev/null || true
  emit_state 143 terminated aborted "SIGTERM in phase $PHASE"
  exit 143
}

on_unexpected_exit() {
  local rc=$?
  # Resume first: an unhandled failure must not leave the sole scheduler dark. The Redis mount guard
  # is the safety net that makes this safe in every phase — it refuses to start Redis onto a
  # /mnt/data that does not match the mapper state.
  restore_service_best_effort
  flag_set aborted 2>/dev/null || true
  emit_state "$rc" "unexpected-exit(from=$(read_flag 2>/dev/null || echo unknown))" aborted
  exit "$rc"
}

main() {
  trap on_unexpected_exit ERR
  trap on_term TERM
  # The probe must be able to measure (measurements.md §1).
  [[ "$(my_uid)" -eq 0 ]] || { emit_state 1 not-root "$(read_flag)"; exit 1; }
  # A single run at a time: the timer re-fires every 30s and a copy can outlast a tick.
  mkdir -p "$STATE_DIR"
  exec 9>"$STATE_DIR/run.lock"
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
      # T2 passed and the latch was written, but the swap did not complete. The copy is only valid
      # while the source has stayed frozen — a reboot restarts Redis — so T2 is RE-RUN now, and a
      # stale copy is re-made rather than trusted on the latch's word.
      assert_ids
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
      K_FREEZE="$(sed -n 's/.*k_freeze=\([0-9]*\).*/\1/p' "$STATE_DIR/copy-verified.latch" 2>/dev/null | tail -1)"
      E_FREEZE="$(sed -n 's/.*e_freeze=\([0-9]*\).*/\1/p' "$STATE_DIR/copy-verified.latch" 2>/dev/null | tail -1)"
      is_uint "$K_FREEZE" && is_uint "$E_FREEZE" || { K_FREEZE=0; E_FREEZE=0; }
      finish_after_swap ;;
    rollback)
      assert_ids
      [[ -n "$(current_pointer)" ]] || refuse rollback-no-pointer "no swap is recorded (pointer absent); nothing to roll back"
      rollback
      flag_set rolled-back
      emit_state 0 rolled-back rolled-back ;;
    done)        emit_state 0 noop-done done ;;
    rolled-back) emit_state 0 noop-rolled-back rolled-back ;;
    aborted)     emit_state 0 noop-aborted aborted ;;
    *)           emit_state 0 noop-unset "${flag:-unset}" ;;
  esac
}

# Run only when executed directly — sourcing (unit tests) must not act on host state.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
