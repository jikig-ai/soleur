#!/usr/bin/env bash
# Raise the `size=` ceiling on the /tmp tmpfs entry in /etc/fstab.
#
# WHY THIS EXISTS
# ---------------
# /tmp here is a RAM-backed tmpfs pinned to a fixed `size=` in /etc/fstab. When a leaking
# process fills it, tool output fails to write and interactive sessions wedge — `du`
# itself cannot write its output on a full tmpfs.
#
# READ THIS BEFORE RAISING THE CEILING. This is a RAISED BACKSTOP, not a free win:
#
#   * tmpfs pages count against physical RAM. The kernel's own tmpfs documentation warns
#     that oversizing an instance can DEADLOCK the machine, because the OOM handler
#     cannot free tmpfs pages.
#   * The existing low pin was therefore incidentally PROTECTIVE: it capped a runaway at
#     the pinned size, at which point writes fail with ENOSPC — a recoverable error —
#     rather than consuming RAM until the box becomes unusable.
#   * Raising it means a future runaway gets further before ENOSPC stops it.
#
# So this script is a complement to fixing the leak, never a substitute. It derives a
# conservative target from actual RAM rather than hardcoding one, and refuses to shrink.
#
# ROOT-GATED, NOT JUDGEMENT-GATED
# -------------------------------
# The script makes 100% of the decisions. The only human contribution is the `sudo`
# credential, which cannot be automated on this host. Run:
#
#     sudo bash scripts/raise-tmp-tmpfs-ceiling.sh --dry-run   # inspect, writes nothing
#     sudo bash scripts/raise-tmp-tmpfs-ceiling.sh             # apply
#
# SCOPE
# -----
# This script does NOT install an /etc/tmpfiles.d age policy. An earlier draft proposed
# dropping /tmp's cleanup age to 2 days; that was cut on safety grounds and must not be
# reinstated. `systemd-tmpfiles` age-cleans by timestamp with no protected-path concept
# and no liveness gate — measured on this host, a 2-day policy would unlink live agent
# session scratchpads. Ceiling only.
set -uo pipefail

# ---------------------------------------------------------------------------
# Injected seams. Tests point these at fixtures; they NEVER touch the real /etc.
# ---------------------------------------------------------------------------
FSTAB="${RAISE_TMPFS_FSTAB:-/etc/fstab}"
MEMINFO="${RAISE_TMPFS_MEMINFO:-/proc/meminfo}"
# The lock lives on its own never-replaced path. Locking $FSTAB itself would be useless:
# the atomic install renames a new inode over it, so a second run would hold a lock on an
# orphaned inode and both would proceed concurrently.
LOCKFILE="${RAISE_TMPFS_LOCK:-${FSTAB}.raise-tmpfs.lock}"
# Fraction of MemTotal to target, as a percentage. 25 is deliberately well under the
# kernel's own 50% default for an unsized tmpfs.
TARGET_PCT="${RAISE_TMPFS_TARGET_PCT:-25}"
BACKUP_KEEP="${RAISE_TMPFS_BACKUP_KEEP:-5}"
# Timestamp is injectable so tests are deterministic.
STAMP="${RAISE_TMPFS_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

die()  { echo "raise-tmp-tmpfs-ceiling: FATAL: $*" >&2; exit 1; }
note() { echo "raise-tmp-tmpfs-ceiling: $*"; }

# ---------------------------------------------------------------------------
# Size parsing. Everything is compared in BYTES.
#
# `4G` vs `4194304k` vs `50%` are three spellings of potentially the same ceiling. A
# string compare would read them as different and re-apply forever, or read a larger
# value as smaller and shrink /tmp. Both are silent.
# ---------------------------------------------------------------------------
mem_total_bytes() {
  local kb
  kb=$(awk '/^MemTotal:/ { print $2; exit }' "$MEMINFO" 2>/dev/null)
  [[ "$kb" =~ ^[0-9]+$ ]] || die "could not read MemTotal from $MEMINFO"
  echo $(( kb * 1024 ))
}

# size_to_bytes <spec> <mem_total_bytes> -> bytes on stdout, or empty + rc=1 if unparseable.
size_to_bytes() {
  local spec="$1" mem="$2" num unit
  [[ -n "$spec" ]] || return 1
  if [[ "$spec" =~ ^([0-9]+)%$ ]]; then
    echo $(( mem * ${BASH_REMATCH[1]} / 100 )); return 0
  fi
  [[ "$spec" =~ ^([0-9]+)([kKmMgG]?)$ ]] || return 1
  num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  case "$unit" in
    "")  ;;   # fall through to the bare-number (bytes) case below
    k|K) echo $(( num * 1024 ));               return 0 ;;
    m|M) echo $(( num * 1024 * 1024 ));        return 0 ;;
    g|G) echo $(( num * 1024 * 1024 * 1024 )); return 0 ;;
  esac
  # mount(8) treats a bare number as BYTES for tmpfs size=.
  echo "$num"; return 0
}

human_g() { awk -v b="$1" 'BEGIN { printf "%.1fG", b / 1073741824 }'; }

# ---------------------------------------------------------------------------
# Locate the single ACTIVE /tmp entry.
#
# Every shape below needs a defined branch, and the catch-all is a LOUD ABORT. An
# `exit 0` on an unrecognised shape would report success having changed nothing — the
# exact false-green class this whole change exists to eliminate.
# ---------------------------------------------------------------------------
find_tmp_line() {
  awk '
    /^[[:space:]]*#/  { next }   # comment
    /^[[:space:]]*$/  { next }   # blank
    { if ($2 == "/tmp") print NR }
  ' "$FSTAB"
}

main() {
  [[ -e "$FSTAB" ]] || die "$FSTAB does not exist"
  [[ -L "$FSTAB" ]] && die "$FSTAB is a symlink; refusing to replace it (an atomic rename would swap the LINK, not its target)"
  [[ -r "$FSTAB" ]] || die "$FSTAB is not readable (run under sudo)"

  local mem target_bytes
  mem=$(mem_total_bytes)
  target_bytes=$(( mem * TARGET_PCT / 100 ))

  local matches count
  matches=$(find_tmp_line)
  count=$(printf '%s' "$matches" | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    die "no active /tmp entry in $FSTAB.
  This host most likely mounts /tmp via systemd's tmp.mount unit instead of fstab.
  Raise the ceiling there:  systemctl edit tmp.mount   (set Options=...,size=$(human_g "$target_bytes"))
  Refusing to exit 0 on a no-op: that would report success having changed nothing."
  fi
  if [[ "$count" -gt 1 ]]; then
    die "found $count active /tmp entries in $FSTAB (lines: $(echo "$matches" | tr '\n' ' ')); refusing to guess which one is live"
  fi

  local lineno line opts cur_spec cur_bytes
  lineno="$matches"
  line=$(awk -v n="$lineno" 'NR == n' "$FSTAB")
  opts=$(awk -v n="$lineno" 'NR == n { print $4 }' "$FSTAB")

  # Field-count sanity: fstab entries are 6 whitespace-separated fields.
  local nf
  nf=$(awk -v n="$lineno" 'NR == n { print NF }' "$FSTAB")
  [[ "$nf" -eq 6 ]] || die "the /tmp entry at line $lineno has $nf fields, expected 6 — refusing to rewrite a malformed line: $line"

  if [[ "$opts" =~ (^|,)size=([^,]+)(,|$) ]]; then
    cur_spec="${BASH_REMATCH[2]}"
    cur_bytes=$(size_to_bytes "$cur_spec" "$mem") || die "cannot parse existing size='$cur_spec' at line $lineno"
  else
    # No size= at all means the kernel default (50% of RAM), which already exceeds our
    # conservative target. Say so explicitly rather than letting an empty-string compare
    # satisfy the idempotency guard.
    note "the /tmp entry has no size= option, so it already defaults to 50% of RAM (~$(human_g $(( mem / 2 )))), which exceeds the $TARGET_PCT% target. Nothing to do."
    return 0
  fi

  note "MemTotal            : $(human_g "$mem")"
  note "current /tmp ceiling: $cur_spec ($(human_g "$cur_bytes"))"
  note "target  /tmp ceiling: $TARGET_PCT% of RAM ($(human_g "$target_bytes"))"

  # NEVER SHRINK. Floor the target at the current value.
  if [[ "$cur_bytes" -ge "$target_bytes" ]]; then
    note "already at or above target — no change. (This script never shrinks /tmp.)"
    return 0
  fi

  local new_spec new_opts new_line
  new_spec="$(( target_bytes / 1024 / 1024 ))M"
  new_opts=$(echo "$opts" | sed -E "s/(^|,)size=[^,]+(,|$)/\1size=${new_spec}\2/")
  new_line=$(awk -v n="$lineno" -v o="$new_opts" 'NR == n { $4 = o; print; exit }' OFS='\t' "$FSTAB")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    note "--dry-run: would rewrite line $lineno"
    note "  before: $line"
    note "  after : $new_line"
    note "  backup: ${FSTAB}.bak.${STAMP}"
    note "  then  : mount -o remount /tmp"
    note "--dry-run: no files written."
    return 0
  fi

  [[ -w "$FSTAB" ]] || die "$FSTAB is not writable — re-run under sudo"

  # Serialize the whole read-modify-write. Two concurrent runs would otherwise collide on
  # a same-second backup name and interleave their writes.
  exec {lockfd}>"$LOCKFILE" || die "cannot open lock file $LOCKFILE"
  flock -w 30 "$lockfd" || die "another run holds $LOCKFILE (waited 30s)"

  cp -p -- "$FSTAB" "${FSTAB}.bak.${STAMP}" || die "backup failed; refusing to modify $FSTAB"
  note "backed up to ${FSTAB}.bak.${STAMP}"

  # Stage the rewrite IN THE SAME DIRECTORY as the target. `mv` is atomic only WITHIN one
  # filesystem; staging in /tmp (a separate tmpfs) or $HOME would silently degrade the
  # rename into copy+unlink, and a kill mid-copy would leave /etc/fstab neither the old
  # file nor a valid new one, with nothing to restore it.
  local tmp
  tmp=$(mktemp "$(dirname "$FSTAB")/.fstab.raise.XXXXXX") || die "cannot stage a temp file beside $FSTAB"
  trap 'rm -f -- "${tmp:-}"' EXIT INT TERM

  awk -v n="$lineno" -v o="$new_opts" 'NR == n { $4 = o } { print }' OFS='\t' "$FSTAB" > "$tmp" \
    || die "failed to render the rewritten fstab"

  # Guarantee a trailing newline. A truncated final line can be dropped by boot-time parsers.
  [[ -s "$tmp" ]] || die "rendered fstab is empty — refusing to install"
  [[ "$(tail -c1 "$tmp" | wc -l)" -eq 1 ]] || printf '\n' >> "$tmp"

  # VALIDATE BEFORE INSTALLING, so the only content ever placed at $FSTAB is already
  # known-good. Validating after the install would mean a window where the live file is
  # broken and only a rollback saves the boot.
  validate_candidate "$tmp" "$lineno" "$target_bytes" "$mem" || die "candidate fstab failed validation; original left untouched"

  # Match the original's mode/ownership explicitly. mktemp creates 0600, which would break
  # non-root readers of fstab.
  chmod --reference="$FSTAB" -- "$tmp" 2>/dev/null || chmod 0644 -- "$tmp"
  chown --reference="$FSTAB" -- "$tmp" 2>/dev/null || true

  sync -- "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$FSTAB" || die "atomic install failed"
  trap - EXIT INT TERM
  # fsync the DIRECTORY too: the rename is atomic but not durable until the directory
  # entry itself is on stable storage.
  sync -- "$(dirname "$FSTAB")" 2>/dev/null || sync
  note "installed. line $lineno now: $(awk -v n="$lineno" 'NR == n' "$FSTAB")"

  prune_backups

  note ""
  note "fstab updated. The running /tmp still has its OLD ceiling until you either reboot"
  note "or remount:"
  note "    sudo mount -o remount /tmp"
  note "Then confirm the LIVE value (not the file):"
  note "    findmnt -no SIZE /tmp"
}

# validate_candidate <file> <expected-lineno> <target-bytes> <mem-bytes>
#
# `findmnt --verify` proves the file PARSES; it does not prove the entry means what was
# intended, and it does not notice that an unrelated line vanished. Both are checked here.
validate_candidate() {
  local cand="$1" lineno="$2" want_bytes="$3" mem="$4" rc=0

  # DIFFERENTIAL, not absolute. `findmnt --verify` does more than parse: it also resolves
  # each source (UUID=/LABEL=/device) and reports unreachable ones. So it legitimately
  # fails on a file whose devices are not present on THIS host — a synthesized test
  # fixture, or a real fstab carrying an entry for a disconnected disk.
  #
  # Treating that as fatal would make the script refuse to run on hosts it is meant to
  # fix. What actually matters is whether OUR rewrite made things worse, so compare the
  # candidate against the original and only fail on a REGRESSION.
  if command -v findmnt >/dev/null 2>&1; then
    local orig_ok=0 cand_ok=0
    findmnt --verify --tab-file "$FSTAB" >/dev/null 2>&1 && orig_ok=1
    findmnt --verify --tab-file "$cand"  >/dev/null 2>&1 && cand_ok=1
    if [[ "$orig_ok" -eq 1 && "$cand_ok" -eq 0 ]]; then
      echo "  validation: findmnt --verify passed on the ORIGINAL but fails on the candidate — the rewrite introduced a defect" >&2
      rc=1
    elif [[ "$orig_ok" -eq 0 ]]; then
      # Pre-existing findings mean --verify cannot discriminate here; the structural
      # checks below carry the load instead.
      echo "  note: findmnt --verify already reports findings on the existing $FSTAB (unresolvable sources are normal for absent devices); relying on structural checks" >&2
    fi
  fi

  # Non-target lines must survive byte-for-byte. A rewrite that correctly fixes size= but
  # drops the `/` or swap entry would pass every size-focused check and leave the machine
  # unbootable — this is the only unbootable path in the change.
  # Count RECORDS (awk NR), not newlines (wc -l). They differ by one whenever the file
  # lacks a trailing newline — and since this script deliberately ADDS that newline, a
  # `wc -l` comparison would report a phantom "line count changed" on exactly the
  # malformed input the newline guard exists to repair.
  local orig_n cand_n
  orig_n=$(awk 'END { print NR }' "$FSTAB"); cand_n=$(awk 'END { print NR }' "$cand")
  [[ "$orig_n" -eq "$cand_n" ]] || {
    echo "  validation: line count changed ($orig_n -> $cand_n)" >&2; rc=1; }

  if ! diff -q <(awk -v n="$lineno" 'NR != n' "$FSTAB") <(awk -v n="$lineno" 'NR != n' "$cand") >/dev/null; then
    echo "  validation: a line OTHER than the /tmp entry changed" >&2; rc=1
  fi

  # Re-parse the emitted line and assert the ceiling is what was intended.
  local new_opts new_spec got
  new_opts=$(awk -v n="$lineno" 'NR == n { print $4 }' "$cand")
  if [[ "$new_opts" =~ (^|,)size=([^,]+)(,|$) ]]; then
    new_spec="${BASH_REMATCH[2]}"
    got=$(size_to_bytes "$new_spec" "$mem") || { echo "  validation: emitted size='$new_spec' is unparseable" >&2; return 1; }
    [[ "$got" -eq "$want_bytes" ]] || {
      echo "  validation: emitted size=$new_spec is $got bytes, expected $want_bytes" >&2; rc=1; }
  else
    echo "  validation: emitted /tmp line has no size= option" >&2; rc=1
  fi

  [[ "$(awk -v n="$lineno" 'NR == n { print $2 }' "$cand")" == "/tmp" ]] || {
    echo "  validation: line $lineno is no longer the /tmp entry" >&2; rc=1; }

  return "$rc"
}

# Bound backup growth. Literal-prefix `find`, never a constructed glob: an empty variable
# in a glob yields a catastrophic pattern, and this is the only root-owned delete here.
# `find -delete`, never `rm -rf`.
prune_backups() {
  local dir base n
  dir=$(dirname "$FSTAB"); base=$(basename "$FSTAB")
  n=$(find "$dir" -maxdepth 1 -type f -name "${base}.bak.*" 2>/dev/null | wc -l)
  [[ "$n" -gt "$BACKUP_KEEP" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name "${base}.bak.*" -printf '%T@ %p\n' 2>/dev/null \
    | sort -n \
    | head -n "$(( n - BACKUP_KEEP ))" \
    | cut -d' ' -f2- \
    | while IFS= read -r old; do
        [[ -n "$old" ]] && find "$old" -maxdepth 0 -type f -delete 2>/dev/null
      done
  note "pruned backups, keeping the $BACKUP_KEEP most recent"
}

main "$@"
