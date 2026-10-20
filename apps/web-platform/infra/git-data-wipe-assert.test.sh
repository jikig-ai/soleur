#!/usr/bin/env bash
#
# git-data-wipe-assert.sh and the MODE=wipe_assert verb of git-data-cutover.sh (#10138, ADR-239
# amendment 2026-10-09, design-wipe-body-pr.md 3.2-3.4; Guards 2, 5 and 8 of the wipe plan).
#
# THREE TIERS.
#   A  SHIM. The REAL host script, fed the way production feeds it (`bash -s < file`), over a simulated
#      host: every system read the script makes goes through an external command (cat, stat, realpath,
#      ls, find, date, findmnt, cryptsetup, blockdev, dmsetup, losetup, mount, umount, dumpe2fs, dd), and
#      those are PATH shims reading one "world" directory. The script carries no test seam (ADR-214).
#      Runs unprivileged, everywhere. It proves every verdict, the fixed output grammar, the
#      path-typed allowlist, the teardown, and that NO synthesized tenant name reaches stdout, stderr, a
#      state file or a directory the script made. The shims RECORD their argv: the suite asserts the
#      operand/flag contract of every selector-bearing call (the right device, `iflag=direct`, never an
#      `of=` but /dev/null, a read-only mount, the `N 8` snapshot table, losetup on the COW file, the 2 s
#      quiescence sleep) as one exact multiset per phase, plus a no-write-shaped-argv invariant on EVERY run.
#      The script's `mktemp -d -p /dev/shm` is answered by a shim that creates the directory under the world
#      (and records it), so a run never touches the shared host's /dev/shm and the leak check is scoped to the
#      directories THIS run created (an unrelated entry in /dev/shm cannot move it).
#   B  VERB. git-data-cutover.sh MODE=wipe_assert against an `ssh` shim: argument refusal before any
#      remote call, the script body on stdin, the %q-quoted command, the per-phase bound, every rc ->
#      verdict word, transport rcs as probe_failed, off-shape answers refused, and the rc table of the
#      script header equal to its `die` calls and to the verb's case arms.
#   C  LOOPBACK. The listing unit on REAL loop devices and a REAL dm snapshot over a deliberately dirty
#      ext4 journal (needs root, losetup, dmsetup, mkfs.ext4, debugfs, python3). WITHOUT the device layer
#      this tier is SKIPPED LOUDLY (SKIP(LOOPBACK_UNAVAILABLE) on stdout and stderr, and the summary says
#      the tier did NOT run); with WIPE_ASSERT_REQUIRE_LOOPBACK=1 (the CI step) it is a FAILURE with the
#      literal token LOOPBACK_UNAVAILABLE and exit 2. The plan requires it to run once on the CI runner
#      image before an owner approval is spent on the listing.
#
# FORBIDDEN-PHRASE LIST (CLO, decision-challenges.md): nothing this suite asserts on, and nothing the
# script prints, claims more than a device-level fact. The words erased, wiped, secure erasure, "no
# copies" and "holds no personal data" appear nowhere in the script or the verb (row GP).
#
# Run: bash apps/web-platform/infra/git-data-wipe-assert.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh derives it).
set -uo pipefail
export LC_ALL=C
# WA_TEST_RUN_TIMEOUT is suite-private (the per-run bound of run_script; only the harness row H6 sets it): an ambient value must not
# disable the bound (0) or fail every world (1)
unset WA_TEST_RUN_TIMEOUT
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/git-data-wipe-assert.sh"
CUTOVER="$DIR/git-data-cutover.sh"

pass=0
fail=0
executed=0
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1"; }

# INSTRUMENT SELF-TEST — drive both counters once each and refuse to continue unless both moved.
_p0=$pass; _f0=$fail
ok "instrument self-test (expected)" >/dev/null
no "instrument self-test (expected)" >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ]; then
  echo "FATAL: instrument self-test did not move both counters" >&2; exit 2
fi
pass=$_p0; fail=$_f0; executed=0

# The canonical P1b guard (#7810): the one shape plugins/soleur/test/lib/fixture-scan.py accepts as
# proof that a write's operand is absolute. Duplicated per file by the repo's own convention.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
instrument() { echo "INSTRUMENT: $*" >&2; exit 2; }
# grep_none <grep args...> — true ONLY when grep exits 1 (no match). A match (rc 0) and a grep error (rc >= 2: an unreadable file,
# a bad option) are both "not clean", so a broken probe can never read as an absence.
grep_none() { local _grc=0; grep "$@" > /dev/null 2>&1 || _grc=$?; [ "$_grc" -eq 1 ]; }

[ -f "$SCRIPT" ] || instrument "missing $SCRIPT"
[ -f "$CUTOVER" ] || instrument "missing $CUTOVER"
for b in python3 awk sed find mkfifo cp cmp timeout mktemp truncate; do
  command -v "$b" >/dev/null 2>&1 || instrument "required binary '$b' not found on PATH"
done
[ -d /dev/shm ] || instrument "/dev/shm is absent (the listing keeps its COW there)"

T="$(mktemp -d "${TMPDIR}/gd-wipe-assert.XXXXXXXX")" || instrument "mktemp -d failed"
assert_fixture_dir "$T"
cleanup() { rm -rf "$T"; return 0; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════════════════
# Shared synthesized fixtures. cq-test-fixtures-synthesized-only: every name and id is made up.
# ══════════════════════════════════════════════════════════════════════════════════════════
ID_T=111111111   # the typed plaintext volume id
ID_L=222222222   # the LUKS volume id
ID_S=333333333   # the server id
NOW=1760000000
UPTIME_S=3600
ROWDT=$((NOW - UPTIME_S + 1200))   # the boot_complete row: 20 minutes after boot
# Tenant-looking names: they must never appear in any output stream or file the script writes.
CORPUS_REPO_A="ws-7f3a91c2-acme-corp.git"
CORPUS_REPO_B="ws-b04d55e1-globex-lab.git"
CORPUS_TOP_DIR="tenant-4b8e0d-initech"
CORPUS_TOP_FILE="user_c0ffee_billing.json"
CORPUS_NL_A="NLA-9c1e-split"
CORPUS_NL_B="NLB-9c1e-name"
# A tenant-shaped name that sits INSIDE the hooks directory, beside the fixed-name probe (never pre-receive itself:
# that name is a compile-time constant and state/argv legitimately records it).
CORPUS_HK_FILE="ws-5d2c7e-umbrella-corp.pack"
PATS="$T/corpus.pats"
printf '%s\n' "$CORPUS_REPO_A" "$CORPUS_REPO_B" "$CORPUS_TOP_DIR" "$CORPUS_TOP_FILE" "$CORPUS_NL_A" "$CORPUS_NL_B" "$CORPUS_HK_FILE" > "$PATS" || instrument "corpus write failed"
CORPUS_N=$(wc -l < "$PATS")

# ══════════════════════════════════════════════════════════════════════════════════════════
# TIER A — the world shim
# ══════════════════════════════════════════════════════════════════════════════════════════
SH="$T/shim"; assert_fixture_dir "$SH"; mkdir -p "$SH" || instrument "mkdir shim failed"
cat > "$SH/_shim" <<'SHIM'
#!/usr/bin/env bash
# One dispatcher, many names. $WORLD describes the simulated host; the shim's own directory is stripped
# from PATH so anything it delegates to is the REAL tool.
n="${0##*/}"
SD="${0%/*}"
PATH="${PATH#"$SD":}"
W="${WORLD:?}"
ST="$W/state"
last="${*: -1}"
note() { printf '%s %s\n' "$n" "$1" >> "$ST/calls"; }
flag() { [ -e "$W/$1" ]; }
# rec — one TAB-separated line per call of every selector-bearing command: the command name, then its argv
# EXACTLY as the host script passed it. The suite asserts the operand/flag contract over this record.
rec() { { printf '%s' "$n"; local a; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$ST/argv"; }
case "$n" in
  blockdev|cryptsetup|dd|dumpe2fs|findmnt|find|losetup|mount|umount|dmsetup|sleep|udevadm|realpath|stat|mktemp|truncate) rec "$@" ;;
esac
# tree_read — a content-reader command handed an operand UNDER the mounted tree ($W/shm/<tmp>/mnt/<something>, or the mount root
# $W/shm/<tmp>/mnt itself; an `if=` prefix is looked through) is a READ of the world's tree and is recorded in state/reads. Scoped
# to the tree on purpose: the script's own pipeline use of wc, sed, awk, grep and dd (stdin, sysfs text, the device) names no
# such operand and records nothing. cat, head and the checksum/dump tools record in their own arms below. The recorder sees ONLY
# the commands shimmed here (a name list: the readers below plus paste, uniq, strings and od); a reader outside it (tee, rev, file, tar,
# nl ...) or a relative operand after a cd is invisible to it, and so is any operand that is not under the tree (a /dev/mapper node,
# the raw device): the static layer (hk_outside_closed with its touch list, hk_no_file_redirect) is the backstop for those.
case "$n" in
  tail|sed|grep|cut|awk|wc|dd|python3|perl|diff|cmp|sort|paste|uniq)
    for _a in "$@"; do
      case "${_a#if=}" in "$W"/shm/*/mnt|"$W"/shm/*/mnt/*) printf '%s\t%s\n' "$n" "$*" >> "$ST/reads"; break ;; esac
    done ;;
esac
case "$n" in
  cat)
    case "$last" in
      /sys/*/stat)
        c=0; [ -f "$ST/stat_calls" ] && c="$(cat "$ST/stat_calls")"
        printf '%s' "$((c + 1))" > "$ST/stat_calls"
        if flag stat_alt && [ "$c" -ge 1 ]; then exec cat "$W/stat_alt"; fi
        # stat_fail_from <n>: the n-th and every later sysfs stat read fails (an instrument fault, not a value)
        if flag stat_fail_from && [ "$c" -ge "$(cat "$W/stat_fail_from")" ]; then exit 1; fi
        exec cat "$W/files$last" ;;
      /sys/*|/proc/*|/var/lib/cloud/*)
        [ -f "$W/files$last" ] || exit 1
        exec cat "$W/files$last" ;;
    esac
    # a cat of any other path is a READ of the world's tree (the script's own cats are sysfs, procfs and cloud-init only):
    # recorded, so a content read of a file under hooks is visible to the suite whatever the script does with the rc
    printf 'cat\t%s\n' "$*" >> "$ST/reads"
    exec cat "$@" ;;
  head)
    # the script reads the store marker with head; any other head is a READ of something else
    [ "$last" = "$W/marker" ] || printf 'head\t%s\n' "$*" >> "$ST/reads"
    exec head "$@" ;;
  sha256sum|sha1sum|sha512sum|md5sum|b2sum|cksum|xxd|od|hexdump|strings|base64|tac|nl)
    # the readers a content probe would use: the script never calls one, so any call is recorded
    printf '%s\t%s\n' "$n" "$*" >> "$ST/reads"
    exec "$n" "$@" ;;
  wc)
    # wc_garbage_at <n>: the n-th wc call prints a non-number (an instrument fault), after draining its input
    c=0; [ -f "$ST/wc_calls" ] && c="$(cat "$ST/wc_calls")"
    c=$((c + 1)); printf '%s' "$c" > "$ST/wc_calls"
    if flag wc_garbage_at && [ "$c" = "$(cat "$W/wc_garbage_at")" ]; then cat > /dev/null; printf 'x\n'; exit 0; fi
    exec wc "$@" ;;
  date)
    if [ "${1-}" = "+%s" ]; then exec cat "$W/now"; fi
    exec date "$@" ;;
  sleep) exit 0 ;;
  udevadm) exit 0 ;;
  mktemp)
    # the script asks for `-d -p /dev/shm` (the suite asserts exactly that argv); the directory is created
    # under the WORLD instead, so a run touches nothing on the shared host's /dev/shm, and the directories
    # THIS run created are exactly the ones recorded here.
    mkdir -p "$W/shm" || exit 1
    d="$(mktemp -d -p "$W/shm")" || exit 1
    printf '%s\n' "$d" >> "$ST/shm_dirs"
    printf '%s\n' "$d"; exit 0 ;;
  truncate) exec truncate "$@" ;;
  tail|sed|grep|cut|python3|perl|diff|cmp|sort|paste|uniq) exec "$n" "$@" ;;
  awk)
    # awk_fail_at <n>: the n-th awk call the host script makes exits 2 (a crashed or missing instrument)
    a=0; [ -f "$ST/awk_calls" ] && a="$(cat "$ST/awk_calls")"
    a=$((a + 1)); printf '%s' "$a" > "$ST/awk_calls"
    if flag awk_fail_at && [ "$a" = "$(cat "$W/awk_fail_at")" ]; then exit 2; fi
    exec awk "$@" ;;
  stat)
    case "$last" in
      /dev/*)
        # stat_denied_byid: the by-id link is listed but a stat of it fails (EACCES/EIO/ELOOP) -- not "gone"
        if flag stat_denied_byid && [ "$last" = "/dev/disk/by-id/scsi-0HC_Volume_111111111" ]; then exit 1; fi
        p="$last"; fmt=""; follow=0; prev=""
        for a in "$@"; do
          [ "$prev" = "-c" ] && fmt="$a"
          [ "$a" = "-L" ] && follow=1
          prev="$a"
        done
        if [ "$follow" = 1 ]; then
          t="$(awk -v p="$p" '$1 == p { print $2 }' "$W/links")"
          [ -z "$t" ] || p="$t"
        fi
        line="$(awk -v p="$p" '$1 == p { print }' "$W/nodes")"
        if [ -z "$line" ]; then
          # a link (no -L) exists even when its target is missing
          [ "$follow" = 0 ] && [ -n "$(awk -v p="$p" '$1 == p { print $2 }' "$W/links")" ] && exit 0
          exit 1
        fi
        ty="$(printf '%s\n' "$line" | awk '{ print $2 }')"; mm="$(printf '%s\n' "$line" | awk '{ print $3 }')"
        case "$fmt" in
          %F) if [ "$ty" = block ]; then echo "block special file"; else echo "regular file"; fi ;;
          '%t:%T') echo "$mm" ;;
          *) : ;;
        esac
        exit 0 ;;
    esac
    exec stat "$@" ;;
  realpath)
    case "$last" in
      /dev/mapper/git-data-pt-snap) if [ -e "$ST/snap_up" ]; then echo "$last"; exit 0; fi; exit 1 ;;
      /dev/*)
        t="$(awk -v p="$last" '$1 == p { print $2 }' "$W/links")"
        if [ -n "$t" ]; then echo "$t"; exit 0; fi
        if [ -n "$(awk -v p="$last" '$1 == p { print }' "$W/nodes")" ]; then echo "$last"; exit 0; fi
        exit 1 ;;
    esac
    exec realpath "$@" ;;
  findmnt)
    want=""; mp=""; src=""; prev=""
    for a in "$@"; do
      [ "$prev" = "-o" ] && want="$a"
      [ "$prev" = "--mountpoint" ] && mp="$a"
      [ "$prev" = "-S" ] && src="$a"
      prev="$a"
    done
    if [ "$src" = "/dev/mapper/git-data-pt-snap" ]; then
      # the leftover snapshot's own mount (phase=clear): present only while the world says it is mounted
      if [ -e "$ST/mounted" ] && [ -s "$W/clear_mnt" ]; then cat "$W/clear_mnt"; exit 0; fi
      exit 1
    fi
    if [ -n "$src" ]; then
      if [ -s "$W/findmnt_S" ]; then cat "$W/findmnt_S"; exit 0; fi
      exit 1
    fi
    if [ "$mp" = "$(cat "$W/root_path")" ]; then
      flag fail_findmnt && exit 1
      case "$want" in
        SOURCE) cat "$W/findmnt_source"; exit 0 ;;
        UUID) cat "$W/fs_uuid"; exit 0 ;;
      esac
    fi
    # the snapshot's private mount point
    if [ -e "$ST/mounted" ] && [ "$want" = SOURCE ]; then echo "/dev/mapper/git-data-pt-snap"; exit 0; fi
    exit 1 ;;
  cryptsetup)
    case "${1-}" in
      status) flag fail_cs_status && exit 4
              printf '/dev/mapper/git-data is active and is in use.\n  type:    LUKS2\n  device:  %s\n' "$(cat "$W/cs_device")"; exit 0 ;;
      isLuks) exit "$(cat "$W/isluks_rc")" ;;
    esac
    exit 9 ;;
  blockdev)
    case "${1-}" in
      --getro)
        g=0; [ -f "$ST/getro_calls" ] && g="$(cat "$ST/getro_calls")"
        printf '%s' "$((g + 1))" > "$ST/getro_calls"
        # getro_fail_from <n>: the n-th and every later getro read fails
        if flag getro_fail_from && [ "$g" -ge "$(cat "$W/getro_fail_from")" ]; then exit 1; fi
        cat "$W/ro"; exit 0 ;;
      --getsz) cat "$W/getsz"; exit 0 ;;
    esac
    exit 9 ;;
  ls)
    case "$last" in
      /sys/*) [ -f "$W/files$last" ] || exit 2; cat "$W/files$last"; exit 0 ;;
      /dev/disk/by-id)
        # the by-id directory: one name per link of the world; byid_gone drops the typed volume's link,
        # fail_byid_ls is an unreadable directory, byid_listing_empty a listing that shows nothing at all
        flag fail_byid_ls && exit 2
        flag byid_listing_empty && exit 0
        awk -v g="$([ -e "$W/byid_gone" ] && echo 1 || echo 0)" '{ n = $1; sub(/.*\//, "", n); if (g == 1 && n == "scsi-0HC_Volume_111111111") next; print n }' "$W/links"
        exit 0 ;;
      "$(cat "$W/root_path")") flag fail_ls_root && exit 2 ;;
    esac
    exec ls "$@" ;;
  find)
    if [ "${1-}" = "/proc" ]; then
      [ -f "$W/open_handles" ] && cat "$W/open_handles"
      exit "$(cat "$W/find_proc_rc" 2>/dev/null || echo 0)"
    fi
    # The hooks reads, keyed per call on the path (BEFORE the generic -printf %y arm below, which the shape call also
    # matches; the generic flag still dies at the top-level listing first). The shape call prints only %y (its last
    # argument); the pre-receive call carries -name. hooks_ht / hooks_pr_out make either call print a chosen string;
    # bump_errors_hooks raises the ext4 errors_count the moment the shape call runs.
    case "${1-}" in
      */hooks)
        if [ "$last" = "%y" ]; then
          flag fail_hooks_shape && exit 3
          if flag hooks_ht; then cat "$W/hooks_ht"; exit 0; fi
          if flag bump_errors_hooks; then printf '1\n' > "$W/files/sys/fs/ext4/dm-3/errors_count"; fi
        else
          flag fail_hooks_pr && exit 3
          if flag hooks_pr_out; then cat "$W/hooks_pr_out"; exit 0; fi
        fi ;;
    esac
    case "$*" in *"-printf %y"*) if flag fail_find_listing; then exit 3; fi ;; esac
    case "$*" in *"-name .cutover-freeze"*) if flag fail_find_freeze; then exit 1; fi ;; esac
    exec find "$@" ;;
  dd) flag fail_dd && exit 1; exit 0 ;;
  dumpe2fs)
    if [ "$last" = "/dev/mapper/git-data-pt-snap" ]; then cat "$W/sb_snap"; else flag fail_dumpe2fs && exit 1; cat "$W/sb_origin"; fi
    exit 0 ;;
  losetup)
    note "$1"
    case "${1-}" in
      --find) flag fail_losetup && exit 1; : > "$ST/loop"; echo /dev/loop99; exit 0 ;;
      -d) flag fail_losetup_d && exit 1; rm -f "$ST/loop"; exit 0 ;;
      -l) [ -e "$ST/loop" ] && [ -f "$W/losetup_l" ] && cat "$W/losetup_l"; exit 0 ;;
    esac
    exit 9 ;;
  dmsetup)
    case "${1-}" in
      ls) flag fail_dm_ls && exit 1
          cat "$W/dm_ls"
          [ -e "$ST/snap_up" ] && printf 'git-data-pt-snap\t(253:3)\n'
          exit 0 ;;
      info)
        case "$*" in
          *blkdevname*) echo dm-3; exit 0 ;;
        esac
        [ -e "$ST/snap_up" ] && exit 0
        exit 1 ;;
      create) note create; flag fail_create && exit 1; : > "$ST/snap_up"; exit 0 ;;
      deps) cat "$W/deps"; exit 0 ;;
      table) [ -e "$ST/snap_up" ] || exit 1
        # dm_table2, when present, answers every read AFTER the first (a snapshot swapped in during the ownership proof)
        if [ -e "$W/dm_table2" ] && [ -e "$ST/table_read1" ]; then cat "$W/dm_table2"; else : > "$ST/table_read1"; cat "$W/dm_table"; fi; exit 0 ;;
      remove) note remove; flag fail_remove && exit 1; rm -f "$ST/snap_up"; exit 0 ;;
      status) if flag snap_invalid; then echo "0 2097152 snapshot Invalid"; else echo "0 2097152 snapshot 16/1000000 16"; fi; exit 0 ;;
    esac
    exit 9 ;;
  mount)
    note mount
    mnt="$last"
    flag fail_mount && exit 32
    cp -a "$W/tree/." "$mnt/" || exit 33
    : > "$ST/mounted"
    # proof that the corpus really was on the mounted tree during the run (a floor on the no-names rows)
    seen="$(find "$mnt" -mindepth 1 | grep -cF -f "$W/pats" || true)"
    printf '%s\n' "$seen" > "$ST/corpus_seen"
    exit 0 ;;
  umount)
    note umount
    mnt="$last"
    flag fail_umount && exit 32
    [ ! -d "$mnt" ] || find "$mnt" -mindepth 1 -delete
    rm -f "$ST/mounted"
    if flag written_on_umount; then cp "$W/written_on_umount" "$W/files/sys/dev/block/8:16/stat"; fi
    exit 0 ;;
esac
echo "shim: no arm for $n" >&2
exit 99
SHIM
chmod +x "$SH/_shim" || instrument "chmod shim failed"
for _n in awk cat date sleep udevadm stat realpath findmnt cryptsetup blockdev ls find dd dumpe2fs losetup dmsetup mount umount mktemp truncate \
  head wc sha256sum sha1sum sha512sum md5sum b2sum cksum xxd od hexdump strings base64 tac nl \
  tail sed grep cut python3 perl diff cmp sort paste uniq; do
  ln -s _shim "$SH/$_n" || instrument "ln shim $_n failed"
done

# world <name> — a fresh simulated host in the CLEAN state. Sets W.
world() {
  W="$T/w-$1"
  assert_fixture_dir "$W"
  mkdir -p "$W/state" "$W/tree" "$W/root" "$W/files/sys/dev/block/8:16" "$W/files/proc/self" \
    "$W/files/var/lib/cloud/data" "$W/files/sys/fs/ext4/dm-3" || instrument "world $1: mkdir failed"
  printf '%s' "$NOW" > "$W/now"
  : > "$W/state/calls"
  : > "$W/state/argv"
  : > "$W/state/reads"   # exists from the start: an absent file must never read as "no reader was called"
  printf '2097152\n' > "$W/getsz"
  cp "$PATS" "$W/pats" || instrument "world $1: corpus copy failed"
  printf '%s %s\n' "$UPTIME_S.55" "12000.10" > "$W/files/proc/uptime"
  printf '%s\n' "$ID_S" > "$W/files/var/lib/cloud/data/instance-id"
  printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"
  : > "$W/files/sys/dev/block/8:16/holders"
  printf '36 35 8:1 / / rw - ext4 /dev/sda1 rw\n40 35 253:0 / /mnt/git-data rw - ext4 /dev/mapper/git-data rw\n' > "$W/files/proc/self/mountinfo"
  printf '0\n' > "$W/files/sys/fs/ext4/dm-3/errors_count"
  printf '/dev/disk/by-id/scsi-0HC_Volume_%s /dev/sdb\n/dev/disk/by-id/scsi-0HC_Volume_%s /dev/sdc\n' "$ID_T" "$ID_L" > "$W/links"
  printf '/dev/sdb block 8:10\n/dev/sdc block 8:20\n' > "$W/nodes"
  printf '/dev/sdc\n' > "$W/cs_device"
  printf '1\n' > "$W/isluks_rc"
  printf '1\n' > "$W/ro"
  printf '/dev/mapper/git-data\n' > "$W/findmnt_source"
  printf '8a1f0c2e-1111-4222-8333-944455556666\n' > "$W/fs_uuid"
  printf '8a1f0c2e-1111-4222-8333-944455556666\n' > "$W/marker"
  printf '%s' "$W/root" > "$W/root_path"
  printf '1 dependencies\t: (8, 16)\n' > "$W/deps"
  : > "$W/dm_ls"
  printf 'No devices found\n' > "$W/dm_ls"
  : > "$W/findmnt_S"
  : > "$W/open_handles"
  printf 'Filesystem features:      has_journal ext_attr resize_inode dir_index filetype needs_recovery extent\nFilesystem state:         not clean\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_origin"
  printf 'Filesystem features:      has_journal ext_attr resize_inode dir_index filetype extent\nFilesystem state:         clean\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_snap"
  tree_clean
}
# tree builders — the contents the mount shim copies onto the snapshot's private mount point.
tree_reset() { assert_fixture_dir "$W"; find "$W/tree" -mindepth 1 -delete || instrument "tree reset failed"; }
tree_clean() { tree_reset; mkdir -p "$W/tree/repositories" "$W/tree/lost+found" && : > "$W/tree/.gc-cursor" || instrument "tree_clean failed"; }

# run_script <phase> [VAR=value …] — the production shape: the script on STDIN to `bash -s`, inputs as env words.
RC=0
run_script() {
  local phase="$1"; shift
  local -a extra=()
  if [ "$phase" = pre ]; then extra=("WIPE_ROW_DT=$ROWDT" "WIPE_LISTING=run"); fi
  assert_fixture_dir "$W"
  rm -f "$W/out" "$W/err"
  RC=0
  # bounded: a content read of a FIFO named pre-receive (world a149) blocks forever, and a hung run must read as RED (rc 124), not stall the suite
  # (WA_TEST_RUN_TIMEOUT is 30 s; only the harness row H6 lowers it, to prove the bound itself)
  timeout -k 5 "${WA_TEST_RUN_TIMEOUT:-30}" env -i PATH="$SH:/usr/bin:/bin" WORLD="$W" \
    WIPE_PHASE="$phase" WIPE_TYPED_ID="$ID_T" WIPE_LUKS_ID="$ID_L" WIPE_SERVER_ID="$ID_S" \
    WIPE_OLD_ROOT="$W/root" WIPE_LUKS_MAPPER=/dev/mapper/git-data WIPE_STORE_VERIFIED="$W/marker" \
    "${extra[@]}" "$@" \
    bash -s < "${RUN_SCRIPT:-$SCRIPT}" > "$W/out" 2> "$W/err" || RC=$?
}

RE_PRE='^wipe_assert pre ok layout_signal=(ok|not_run) journal=(dirty|clean|na) top_d=([0-9]+|na) top_f=([0-9]+|na) top_l=([0-9]+|na) top_o=([0-9]+|na) repos=([0-9]+|na) boot_to_row_s=[0-9]+ lock_residue=([0-9]+|na) store_root_repos=[0-9]+$'
RE_POST='^wipe_assert (post_detach|finish) ok byid=gone mapper_read=ok store_root=ok$'
RE_ERR='^wipe-assert: rc=[0-9]+ reason=[a-z_0-9]+( [a-z_]+=[0-9]+)*$'
# RE_34 — the rc=34 line: eight fixed fields, then an OPTIONAL group of four (hk_entries hk_nonfile hk_pr_f hk_pr_small).
# Captures: 1 has_hooks_d, 2 lf_entries, 3 offlist_n, 4 the whole group (empty when absent), 5-8 the four hk_ values.
RE_34='^wipe-assert: rc=34 reason=offlist top_d=[0-9]+ top_f=[0-9]+ top_l=[0-9]+ top_o=[0-9]+ repos=[0-9]+ has_hooks_d=([01]) lf_entries=([0-9]+) offlist_n=([0-9]+)( hk_entries=([0-9]+) hk_nonfile=([0-9]+) hk_pr_f=([01]) hk_pr_small=([01]))?$'
INVARIANT_RUNS=0
NAMES_SEEN_RUNS=0
RC34_LINES_CHECKED=0
HK_GROUP_LINES_CHECKED=0
# l34_base <line> <has_hooks_d> <lf_entries> <offlist_n> — a refusal must be explainable: some top-level entry was off the
# list, or the top-level lost+found held something (an all-zero pair cannot occur with rc 34). Two derived invariants as
# well: the hooks bit implies an off-list entry (the bit never feeds the allowlist), and the off-list count cannot exceed
# the top-level entries counted by type.
l34_base() {
  local l="$1" hk="$2" lf="$3" n="$4" tops _k _v
  tops=0
  for _k in top_d top_f top_l top_o; do _v="${l##*"$_k"=}"; tops=$((tops + 10#${_v%% *})); done
  { [ "$((10#$n))" -gt 0 ] || [ "$((10#$lf))" -gt 0 ]; } && { [ "$hk" = 0 ] || [ "$((10#$n))" -ge 1 ]; } && [ "$((10#$n))" -le "$tops" ]
}
# line34_ok <line> — the STRICT EMIT check, on every line the script prints: the base invariants, and the hk_ group present
# if and only if has_hooks_d=1, with its four invariants (hk_nonfile <= hk_entries, hk_pr_small <= hk_pr_f,
# hk_entries >= hk_nonfile + hk_pr_f, hk_pr_f=1 implies hk_entries >= 1).
line34_ok() {
  local l="$1" hk lf n grp e nf pf ps
  [[ "$l" =~ $RE_34 ]] || return 1
  hk="${BASH_REMATCH[1]}"; lf="${BASH_REMATCH[2]}"; n="${BASH_REMATCH[3]}"; grp="${BASH_REMATCH[4]}"
  e="${BASH_REMATCH[5]}"; nf="${BASH_REMATCH[6]}"; pf="${BASH_REMATCH[7]}"; ps="${BASH_REMATCH[8]}"
  l34_base "$l" "$hk" "$lf" "$n" || return 1
  if [ "$hk" = 1 ]; then [ -n "$grp" ] || return 1; else [ -z "$grp" ] || return 1; fi
  [ -z "$grp" ] && return 0
  [ "$((10#$nf))" -le "$((10#$e))" ] && [ "$ps" -le "$pf" ] && [ "$((10#$e))" -ge "$((10#$nf + pf))" ] && { [ "$pf" = 0 ] || [ "$((10#$e))" -ge 1 ]; }
}
# line34_grammar_ok <line> — the POSTING grammar (CLO L3): everything the strict check accepts, plus the already-printed
# eight-field line (has_hooks_d=1, no hk_ group; run 39136900735 is one). Anything else (a partial group, a group with
# has_hooks_d=0, an extra token) is rejected.
line34_grammar_ok() {
  local l="$1" hk lf n grp
  line34_ok "$l" && return 0
  [[ "$l" =~ $RE_34 ]] || return 1
  hk="${BASH_REMATCH[1]}"; lf="${BASH_REMATCH[2]}"; n="${BASH_REMATCH[3]}"; grp="${BASH_REMATCH[4]}"
  [ "$hk" = 1 ] && [ -z "$grp" ] && l34_base "$l" "$hk" "$lf" "$n"
}
# invariants <label> — what EVERY run owes, success or refusal.
invariants() {
  local label="$1" leak bad lines left
  INVARIANT_RUNS=$((INVARIANT_RUNS + 1))
  # 1. no corpus name in stdout, stderr or any state file (the world's tree/files are the SOURCE and excluded)
  leak="$(grep -rlF -f "$PATS" "$W/out" "$W/err" "$W/state" || true)"
  if [ -z "$leak" ]; then ok "$label: no synthesized tenant name in stdout, stderr or any state file"
  else no "$label: a synthesized name reached: $leak"; fi
  # 2. the output grammar: stdout is empty or ONE line of the fixed shape; every stderr line is a fixed reason line
  lines="$(wc -l < "$W/out")"
  bad=0
  if [ "$lines" -gt 1 ]; then bad=1; fi
  if [ "$lines" -eq 1 ] && ! [[ "$(cat "$W/out")" =~ $RE_PRE || "$(cat "$W/out")" =~ $RE_POST ]]; then bad=1; fi
  while IFS= read -r l; do
    [[ "$l" =~ $RE_ERR ]] || bad=1
  done < "$W/err"
  if [ "$bad" = 0 ]; then ok "$label: stdout is empty or one fixed-shape line, every stderr line is a fixed reason line"
  else no "$label: output grammar violated: out=[$(tr '\n' '|' < "$W/out" | cut -c1-200)] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
  # 3. teardown: no snapshot, loop or mount, and no directory THIS run's script created is left behind. The
  # mktemp shim creates the script's `mktemp -d -p /dev/shm` directory under the world (and records it), so
  # the comparison is scoped to what the run itself made: an unrelated entry in the host's /dev/shm cannot
  # move it, and a leak of the script's own COW/mnt directories cannot hide in a whole-listing diff.
  left="$(ls -A "$W/shm" 2>/dev/null | wc -l)"
  if [ ! -e "$W/state/snap_up" ] && [ ! -e "$W/state/loop" ] && [ ! -e "$W/state/mounted" ] && [ "$left" = 0 ]; then
    ok "$label: no snapshot, loop device, mount or directory this run created survives"
  else no "$label: transient state leaked (snap=$([ -e "$W/state/snap_up" ] && echo y || echo n) loop=$([ -e "$W/state/loop" ] && echo y || echo n) mounted=$([ -e "$W/state/mounted" ] && echo y || echo n) own_dirs_left=$left)"; fi
  # 4. nothing the run called is write-shaped: no dd `of=` but /dev/null, every mount read-only, no loop/truncate on
  # a /dev node, and the snapshot table is non-persistent (`N 8`)
  if argv_safe "$W/state/argv"; then ok "$label: no write-shaped argv (dd of= only /dev/null, mounts read-only, loop and COW never on a /dev node, snapshot N 8)"
  else no "$label: a write-shaped argv was recorded: $(tr '\t' ' ' < "$W/state/argv" | grep -E ' of=| rw|snapshot' | head -3 | cut -c1-200)"; fi
  if [ -s "$W/state/corpus_seen" ] && [ "$(cat "$W/state/corpus_seen")" -gt 0 ]; then NAMES_SEEN_RUNS=$((NAMES_SEEN_RUNS + 1)); fi
}
# rc34_once — exactly ONE stderr line carries the rc=34 prefix (a second `say wipe-assert: rc=34 reason=offlist_x sz=N` before the real
# one would pass a last-line-only check and RE_ERR alike). A grep error reads as "not once".
rc34_once() { [ "$(grep -c '^wipe-assert: rc=34 ' "$W/err" 2>/dev/null)" = 1 ]; }
# expect_refuse <label> <rc> <reason-prefix> [<exact tail of an rc=34 line, from top_d= onward>] — a refusal: nothing
# on stdout, the rc and a fixed reason on stderr. When the expected AND the actual rc are 34 the last stderr line must
# also be the strict fixed shape, and with a tail it must equal the whole expected line (a substring match would
# accept offlist_n=10 or a trailing token).
expect_refuse() {
  local label="$1" rc="$2" reason="$3" tail34="${4:-}" last
  last="$(tail -n 1 "$W/err")"
  if [ "$RC" = "$rc" ] && [ ! -s "$W/out" ] && [[ "$last" == "wipe-assert: rc=$rc reason=$reason"* ]]; then
    ok "$label -> rc $rc reason=$reason, stdout empty"
  else no "$label: expected rc=$rc reason=$reason; got rc=$RC out=[$(cut -c1-80 "$W/out")] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
  if [ "$rc" = 34 ] && [ "$RC" = 34 ]; then
    RC34_LINES_CHECKED=$((RC34_LINES_CHECKED + 1))
    case "$last" in *" hk_entries="*) HK_GROUP_LINES_CHECKED=$((HK_GROUP_LINES_CHECKED + 1)) ;; esac
    if line34_ok "$last" && rc34_once; then ok "$label: the rc=34 line is the strict fixed shape (digits and 0/1 bits only; the hk_ group iff has_hooks_d=1) and the only rc=34 line"
    else no "$label: the rc=34 line is not the strict fixed shape, or it is not the only rc=34 line: [$last]"; fi
    if [ -n "$tail34" ]; then
      if [ "$last" = "wipe-assert: rc=34 reason=offlist $tail34" ]; then ok "$label: the whole rc=34 line equals the expected one"
      else no "$label: the rc=34 line differs: got [$last], want [wipe-assert: rc=34 reason=offlist $tail34]"; fi
    else no "$label: an rc=34 row must pin the whole expected line (no tail given)"; fi
  elif [ -n "$tail34" ]; then no "$label: a tail was given for a row that is not an rc=34 refusal (want rc=$rc, got rc=$RC)"; fi
  invariants "$label"
}
# expect_line <label> <regex>
expect_line() {
  local label="$1" re="$2" got
  got="$(cat "$W/out")"
  if [ "$RC" = 0 ] && [[ "$got" =~ $re ]] && [ ! -s "$W/err" ]; then ok "$label -> rc 0, $got"
  else no "$label: expected rc 0 and /$re/; got rc=$RC out=[$got] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
  invariants "$label"
}
called() { grep -c "^$1 " "$W/state/calls" 2>/dev/null || true; }

# argv_safe <record> — the record of EVERY selector-bearing call holds nothing that could write to the retained
# device: dd `of=` is /dev/null or absent, every mount carries `-o ro,...`, losetup/truncate never aim at a /dev
# node (the COW is a file), and the snapshot table is `... N 8` (non-persistent, so nothing is ever written back).
argv_safe() {
  awk -F'\t' '
    $1 == "dd"       { for (i = 2; i <= NF; i++) if ($i ~ /^of=/ && $i != "of=/dev/null") bad = 1 }
    $1 == "mount"    { ok = 0; for (i = 2; i < NF; i++) if ($i == "-o" && $(i + 1) ~ /^ro(,|$)/) ok = 1; if (!ok) bad = 1 }
    $1 == "truncate" { if ($NF ~ /^\/dev\//) bad = 1 }
    $1 == "losetup"  { if ($2 != "-d" && $NF ~ /^\/dev\//) bad = 1 }
    $1 == "dmsetup" && $2 == "create" { if ($NF !~ / N 8$/) bad = 1 }
    END { exit bad }' "$1"
}
# argv_norm <world> — the world's record with its own paths abstracted (@W@ = the world, @D@ = the script's
# mktemp directory) and TAB shown as `|`, sorted: one comparable multiset of every selector-bearing call.
argv_norm() {
  local w="$1" d
  local -a sedargs=()
  d="$(head -n 1 "$w/state/shm_dirs" 2>/dev/null || true)"
  [ -z "$d" ] || sedargs+=(-e "s#${d}#@D@#g")
  sedargs+=(-e "s#${w}#@W@#g")
  sed "${sedargs[@]}" "$w/state/argv" | tr '\t' '|' | LC_ALL=C sort
}
# contract_has <world> <line> [count] — the normalised record holds that exact line (exactly <count> times if given)
contract_has() {
  local n; n="$(argv_norm "$1" | grep -cxF -- "$2" || true)"
  if [ -n "${3-}" ]; then [ "$n" = "$3" ]; else [ "$n" -ge 1 ]; fi
}
# contract_eq <world> <expected-text> — the whole record equals the expected multiset (no extra call, none missing)
contract_eq() { cmp -s <(argv_norm "$1") <(printf '%s\n' "$2" | LC_ALL=C sort); }

# The contract world: a journal of 8192 blocks of 4096 bytes (so the COW is 8192*4096 + 64 MiB = 100663296 bytes) and a
# device of 4194304 sectors (so the table size comes from `blockdev --getsz`, not a constant).
set_contract() {
  printf '4194304\n' > "$W/getsz"
  printf 'Filesystem features:      has_journal ext_attr resize_inode dir_index filetype needs_recovery extent\nFilesystem state:         not clean\nTotal journal blocks:     8192\nBlock size:               4096\n' > "$W/sb_origin"
}
# THE MODEL: the exact multiset of selector-bearing calls (command, then argv; TAB shown as `|`; @W@ = the world,
# @D@ = the script's mktemp directory) the host script makes. Every line was read against the script: the typed
# device /dev/sdb for getro/getsz/dumpe2fs/isLuks/findmnt -S/the /proc scan, the LUKS backing /dev/sdc only for the
# identity read, the mapper only for the uncached read, never an `of=` but /dev/null, `-o ro,...` on the one mount,
# the table `0 <getsz> snapshot <origin> <cow-loop> N 8`, losetup on the COW FILE, the 2 s quiescence sleep.
# pre, WIPE_LISTING=run
EXP_PRE="$(cat <<'EXP_EOF'
blockdev|--getro|/dev/sdb
blockdev|--getro|/dev/sdb
blockdev|--getsz|/dev/sdb
cryptsetup|isLuks|--|/dev/sdb
cryptsetup|status|git-data
dmsetup|create|git-data-pt-snap|--table|0 4194304 snapshot /dev/sdb /dev/loop99 N 8
dmsetup|deps|git-data-pt-snap
dmsetup|info|-c|--noheadings|-o|blkdevname|git-data-pt-snap
dmsetup|ls
dmsetup|ls
dmsetup|remove|--retry|git-data-pt-snap
dmsetup|status|git-data-pt-snap
dmsetup|status|git-data-pt-snap
dumpe2fs|-h|/dev/mapper/git-data-pt-snap
dumpe2fs|-h|/dev/sdb
findmnt|-n|-S|/dev/sdb
findmnt|-n|-o|SOURCE|--mountpoint|@D@/mnt
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|repositories|-printf|T:%y
find|/proc|-ignore_readdir_race|-maxdepth|3|-type|l|-regex|/proc/[0-9]+/fd/[0-9]+|-lname|/dev/sdb|-print|-quit
find|@D@/mnt/lost+found|-mindepth|1|-maxdepth|1|-printf|x
find|@D@/mnt/repositories|-mindepth|1|-maxdepth|1|!|(|-type|f|(|-name|.*.init.lock|-o|-name|.init.lock|)|)|!|(|-type|d|-name|lost+found|-empty|)|-printf|x
find|@D@/mnt/repositories|-mindepth|1|-maxdepth|1|-type|f|-name|.?*.init.lock|-printf|x
find|@D@/mnt|-mindepth|1|-maxdepth|1|-printf|%y\t%f\0
losetup|--find|--show|--|@D@/cow
losetup|-d|/dev/loop99
mktemp|-d|-p|/dev/shm
mount|-o|ro,errors=remount-ro,nosuid,nodev,noexec|/dev/mapper/git-data-pt-snap|@D@/mnt
realpath|-e|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
realpath|-e|--|/dev/mapper/git-data-pt-snap
realpath|-e|--|/dev/mapper/git-data-pt-snap
realpath|-e|--|/dev/sdc
sleep|2
stat|-L|-c|%F|--|/dev/sdb
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_222222222
stat|-L|-c|%t:%T|--|/dev/sdb
stat|-L|-c|%t:%T|--|/dev/sdc
truncate|-s|100663296|--|@D@/cow
udevadm|settle|--timeout=15
umount|@D@/mnt
EXP_EOF
)"
# pre, WIPE_LISTING=skip (wipe_check): the metadata read, no snapshot, loop, mount, dd or mktemp call
EXP_SKIP="$(cat <<'EXP_EOF'
blockdev|--getro|/dev/sdb
cryptsetup|isLuks|--|/dev/sdb
cryptsetup|status|git-data
dmsetup|ls
findmnt|-n|-S|/dev/sdb
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|repositories|-printf|T:%y
find|/proc|-ignore_readdir_race|-maxdepth|3|-type|l|-regex|/proc/[0-9]+/fd/[0-9]+|-lname|/dev/sdb|-print|-quit
realpath|-e|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
realpath|-e|--|/dev/sdc
sleep|2
stat|-L|-c|%F|--|/dev/sdb
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_111111111
stat|-L|-c|%t:%T|--|/dev/disk/by-id/scsi-0HC_Volume_222222222
stat|-L|-c|%t:%T|--|/dev/sdb
stat|-L|-c|%t:%T|--|/dev/sdc
EXP_EOF
)"
# post_detach / finish (the by-id link already gone)
EXP_POST="$(cat <<'EXP_EOF'
dd|if=/dev/mapper/git-data|of=/dev/null|bs=4096|count=1|iflag=direct
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|SOURCE|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
findmnt|-n|-o|UUID|--mountpoint|@W@/root
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
find|-H|@W@/root|-mindepth|1|-maxdepth|1|-name|.cutover-freeze|-print
EXP_EOF
)"

caught_contract_pre()  { contract_eq "$W" "$EXP_PRE"; }
caught_contract_skip() { contract_eq "$W" "$EXP_SKIP"; }
caught_contract_post() { contract_eq "$W" "$EXP_POST"; }

echo "--- TIER A: the host script over a simulated host"

# ── the clean host: skip (wipe_check) and run (wipe) ──────────────────────────────────────────
world a-skip
run_script pre WIPE_LISTING=skip
expect_line "A01 clean host, listing skipped (the finish-phase shape)" '^wipe_assert pre ok layout_signal=not_run journal=na top_d=na top_f=na top_l=na top_o=na repos=na boot_to_row_s=1200 lock_residue=na store_root_repos=0$'
if [ "$(called dmsetup)" = 0 ] && [ "$(called mount)" = 0 ] && [ "$(called losetup)" = 0 ]; then ok "A01 skip: no snapshot was created, nothing mounted (wipe_check stays a metadata read)"
else no "A01 skip: a snapshot call was made"; fi
# the operand/flag contract: the record of every selector-bearing call equals the modelled argv (a wrong device, a
# missing flag or an extra call is a failure; nothing is merely "called")
if caught_contract_skip; then ok "A01 contract (skip): exactly the modelled argv, no snapshot, loop, mount, dd or mktemp call"
else no "A01 contract (skip): the recorded argv differs from the model: $(argv_norm "$W" | head -40 | tr '\n' ';' | cut -c1-600)"; fi

world a-run
set_contract
run_script pre
expect_line "A02 clean host, listing run (dirty journal)" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0$'
if caught_contract_pre; then ok "A02 contract (pre, listing): every operand and flag is the modelled one (typed device for getro/getsz/dumpe2fs/isLuks/findmnt -S/the /proc scan, iflag-free, if=/of= never the device, ro mount, table 0 <sectors> snapshot <origin> <cow> N 8, losetup on the COW file, 2 s quiescence)"
else no "A02 contract (pre, listing): the recorded argv differs from the model: $(argv_norm "$W" | tr '\n' ';' | cut -c1-900)"; fi

# must-PASS: lock dotfiles at the top level and inside repositories/, lost+found inside repositories/
world a-locks
tree_clean
: > "$W/tree/.init.lock"; : > "$W/tree/.ws-9.init.lock"
: > "$W/tree/repositories/.init.lock"; : > "$W/tree/repositories/.ws-9.init.lock"; mkdir -p "$W/tree/repositories/lost+found"
run_script pre
expect_line "A03 (must-PASS) lock dotfiles and lost+found are not repositories" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=3 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=2 store_root_repos=0$'

# the exclusions are TYPED: a lock is a regular file, lost+found an empty directory
world a-lfcontent
: > "$W/tree/lost+found/$CORPUS_TOP_FILE"
run_script pre
expect_refuse "A06 a top-level lost+found that holds a file is off the allowlist (its contents are opened)" 34 offlist "top_d=2 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=1 offlist_n=0"
world a-lfdeep
mkdir -p "$W/tree/lost+found/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A07 a top-level lost+found that holds a directory is off the allowlist" 34 offlist "top_d=2 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=1 offlist_n=0"
world a-lockdir-top
mkdir -p "$W/tree/.init.lock"
run_script pre
expect_refuse "A08 a top-level DIRECTORY named like the lock file is off the allowlist (the lock exclusion is for regular files)" 34 offlist "top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"
world a-lockdir-repos
mkdir -p "$W/tree/repositories/.ws-9.init.lock/$CORPUS_REPO_A"
run_script pre
expect_refuse "A09 a DIRECTORY named like a lock under repositories/ counts as an entry" 37 repositories_not_empty
if grep -q 'repos=1' "$W/err"; then ok "A09 the lock-named directory is COUNTED (repos=1), no name"; else no "A09 count missing: $(cat "$W/err")"; fi
world a-locklink-repos
ln -s lost+found "$W/tree/repositories/.init.lock"
run_script pre
expect_refuse "A09b a SYMLINK named like the bare lock under repositories/ counts as an entry" 37 repositories_not_empty
world a-lfrepos-content
mkdir -p "$W/tree/repositories/lost+found/$CORPUS_REPO_A"
run_script pre
expect_refuse "A09c a repositories/lost+found that holds an entry counts (only an EMPTY one is excluded)" 37 repositories_not_empty

world a-clean-journal
printf 'Filesystem features:      has_journal ext_attr resize_inode dir_index filetype extent\nFilesystem state:         clean\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_origin"
run_script pre
expect_line "A04 a clean journal reads journal=clean" '^wipe_assert pre ok layout_signal=ok journal=clean top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0$'

world a-norepos
tree_reset; mkdir -p "$W/tree/lost+found"
run_script pre
expect_line "A05 (must-PASS) a volume with no repositories directory and nothing else is empty" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=1 top_f=0 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0$'

# ── A1 (2026-10-15): store_root_repos (the LUKS store root: an independent barrier for the separated wipe) ──
# A read-only count of $OLD_ROOT/repositories with the bootstrap exclusions; the host is NOT told the variant, the
# runner refuses on a non-zero count. Counts only, never a name.
world a-sr-repos
mkdir -p "$W/root/repositories/$CORPUS_REPO_A" "$W/root/repositories/$CORPUS_TOP_DIR"; : > "$W/root/repositories/.ws-9.init.lock"; : > "$W/root/repositories/.init.lock"
run_script pre
expect_line "A95 two repositories under the store root (lock files excluded) -> store_root_repos=2, exit 0, no name" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=2$'
world a-sr-locksonly
mkdir -p "$W/root/repositories/lost+found"; : > "$W/root/repositories/.ws-9.init.lock"
run_script pre
expect_line "A96 (must-PASS) only lock files and an empty lost+found under the store root -> store_root_repos=0" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0$'
world a-sr-lfcontent
mkdir -p "$W/root/repositories/lost+found/$CORPUS_REPO_A"
run_script pre
expect_line "A97 a store-root repositories/lost+found that holds an entry counts (only an EMPTY one is excluded)" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=1$'
world a-sr-symlink
ln -s lost+found "$W/root/repositories"
run_script pre
expect_refuse "A98 a store-root repositories that is a SYMLINK is unreadable, never counted as empty" 42 store_root_unreadable
world a-sr-skip
mkdir -p "$W/root/repositories/$CORPUS_REPO_A"
run_script pre WIPE_LISTING=skip
expect_line "A99 the store-root count runs even when the snapshot listing is skipped (lock_residue=na)" '^wipe_assert pre ok layout_signal=not_run journal=na top_d=na top_f=na top_l=na top_o=na repos=na boot_to_row_s=1200 lock_residue=na store_root_repos=1$'

# ── A1 (2026-10-15) phase=clear: clear a LEFTOVER git-data-pt-snap (CTO follow-up ruling) ───────────────────────────
# A SIGKILL during the listing cannot be trapped, so the throwaway snapshot, its mount, its loop device and its COW file
# can outlive the run. The clear proves the leftover is OURS before it touches it: the snapshot's origin is the typed
# device, its COW is a loop device backed by a COW file inside the pinned /dev/shm directory that also holds the mount.
RE_CLEAR='^wipe_assert clear ok snapshot=(cleared|absent)$'
CLR_DIR=/dev/shm/tmp.AbCdEfGhIj
clear_state() { # the state a SIGKILLed listing leaves behind, in the CURRENT world
  : > "$W/state/snap_up"; : > "$W/state/mounted"; : > "$W/state/loop"
  printf '0 2097152 snapshot 8:16 7:99 N 8\n' > "$W/dm_table"
  printf '%s/mnt\n' "$CLR_DIR" > "$W/clear_mnt"
  printf '/dev/loop99 %s/cow\n' "$CLR_DIR" > "$W/losetup_l"
}
clear_world() { world "$1"; clear_state; }
clear_inv() { # <label> — the grammar, the name leak and the write-shape invariants of a clear run (the teardown one is the assertion itself)
  local label="$1" bad=0 got lines leak
  INVARIANT_RUNS=$((INVARIANT_RUNS + 1))
  leak="$(grep -rlF -f "$PATS" "$W/out" "$W/err" "$W/state" || true)"
  if [ -z "$leak" ]; then ok "$label: no synthesized tenant name in stdout, stderr or any state file"; else no "$label: a synthesized name reached: $leak"; fi
  lines="$(wc -l < "$W/out")"; got="$(cat "$W/out")"
  if [ "$lines" -gt 1 ]; then bad=1; fi
  if [ "$lines" -eq 1 ] && ! [[ "$got" =~ $RE_CLEAR ]]; then bad=1; fi
  while IFS= read -r l; do [[ "$l" =~ $RE_ERR ]] || bad=1; done < "$W/err"
  if [ "$bad" = 0 ]; then ok "$label: stdout is empty or one fixed-shape clear line, every stderr line is a fixed reason line"; else no "$label: output grammar violated: out=[$got] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
  if argv_safe "$W/state/argv"; then ok "$label: no write-shaped argv"; else no "$label: a write-shaped argv was recorded"; fi
}
clear_detaches() { grep -c "^losetup	-d	" "$W/state/argv" 2>/dev/null || true; }
clear_removals() { grep -c "^dmsetup	remove	--retry	git-data-pt-snap$" "$W/state/argv" 2>/dev/null || true; }
clear_expect_refuse() { # <label> <rc> <reason> — a refusal removes NOTHING
  local label="$1" rc="$2" reason="$3" last
  last="$(tail -n 1 "$W/err")"
  if [ "$RC" = "$rc" ] && [ ! -s "$W/out" ] && [[ "$last" == "wipe-assert: rc=$rc reason=$reason"* ]] && [ "$(clear_removals)" = 0 ] && [ "$(called umount)" = 0 ] && [ "$(clear_detaches)" = 0 ] && [ -e "$W/state/snap_up" ]; then
    ok "$label -> rc $rc reason=$reason, stdout empty, nothing removed (no remove, umount or loop detach; the snapshot is still up)"
  else no "$label: expected rc=$rc reason=$reason with nothing removed; got rc=$RC removals=$(clear_removals) umount=$(called umount) out=[$(cut -c1-80 "$W/out")] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
  clear_inv "$label"
}
clear_world c-ok
run_script clear
if [ "$RC" = 0 ] && [ "$(cat "$W/out")" = "wipe_assert clear ok snapshot=cleared" ] && [ ! -s "$W/err" ] && [ "$(clear_removals)" = 1 ] && [ "$(called umount)" = 1 ] && [ "$(clear_detaches)" = 1 ] \
   && [ ! -e "$W/state/snap_up" ] && [ ! -e "$W/state/mounted" ] && [ ! -e "$W/state/loop" ]; then
  ok "C01 a leftover snapshot of the typed device is cleared: ONE remove of the pinned name (--retry), ONE umount, ONE loop detach, nothing left -> rc 0, snapshot=cleared"
else no "C01 clear failed: rc=$RC out=[$(cat "$W/out")] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)] removals=$(clear_removals) umount=$(called umount) detaches=$(clear_detaches)"; fi
clear_inv "C01"
if grep -qE "^dmsetup	remove	--retry	git-data-pt-snap$" "$W/state/argv" && ! grep -vq "git-data-pt-snap$" < <(grep -E "^dmsetup	remove" "$W/state/argv"); then
  ok "C01 the only dmsetup remove ever sent names the pinned snapshot (git-data-pt-snap); no name comes from an input"
else no "C01 a dmsetup remove named something else"; fi
world c-absent
run_script clear
if [ "$RC" = 0 ] && [ "$(cat "$W/out")" = "wipe_assert clear ok snapshot=absent" ] && [ "$(clear_removals)" = 0 ] && [ "$(called umount)" = 0 ] && [ "$(clear_detaches)" = 0 ]; then
  ok "C02 no leftover snapshot -> rc 0, snapshot=absent, nothing removed (idempotent)"
else no "C02 absent case: rc=$RC out=[$(cat "$W/out")] removals=$(clear_removals)"; fi
clear_inv "C02"
clear_world c-origin-other
printf '0 2097152 snapshot 8:32 7:99 N 8\n' > "$W/dm_table"
run_script clear
clear_expect_refuse "C03 a snapshot whose origin is another device is not ours" 43 snapshot_not_ours
clear_world c-cow-notloop
printf '0 2097152 snapshot 8:16 8:99 N 8\n' > "$W/dm_table"
run_script clear
clear_expect_refuse "C04 a snapshot whose COW is not a loop device (major 8, minor 99 = a LISTED /dev/loop99) is not ours: only major 7 is the loop driver" 43 snapshot_not_ours
clear_world c-multiline
printf '0 2097152 snapshot 8:16 7:99 N 8\n2097152 2097152 linear 8:16 2097152\n' > "$W/dm_table"
run_script clear
clear_expect_refuse "C04c a multi-segment table whose FIRST line looks right is not ours (one segment only)" 43 snapshot_not_ours
clear_world c-swapped
printf '0 2097152 snapshot 8:16 7:99 N 8\n' > "$W/dm_table"
printf '0 2097152 snapshot 8:32 7:99 N 8\n' > "$W/dm_table2"
run_script clear
clear_expect_refuse "C04d a snapshot that changes between the proof and the removal (the table is re-read right before it) is not ours" 43 snapshot_not_ours
clear_world c-persistent
printf '0 2097152 snapshot 8:16 7:99 P 8\n' > "$W/dm_table"
run_script clear
clear_expect_refuse "C04b a PERSISTENT snapshot (P) is not ours: ours is always N" 43 snapshot_not_ours
clear_world c-mnt-outside
printf '/mnt/elsewhere/mnt\n' > "$W/clear_mnt"
run_script clear
clear_expect_refuse "C05 a mount outside the pinned /dev/shm/tmp.<id>/mnt shape is not ours" 43 snapshot_not_ours
clear_world c-mnt-two
printf '%s/mnt\n%s/mnt\n' "$CLR_DIR" "/dev/shm/tmp.ZyXwVuTsRq" > "$W/clear_mnt"
run_script clear
clear_expect_refuse "C06 two mounts of the snapshot are not ours" 43 snapshot_not_ours
clear_world c-loop-backing
printf '/dev/loop99 /var/tmp/cow\n' > "$W/losetup_l"
run_script clear
clear_expect_refuse "C07 a loop device backed by a file outside the pinned /dev/shm/tmp.<id>/cow is not ours" 43 snapshot_not_ours
clear_world c-loop-absent
printf '/dev/loop5 %s/cow\n' "$CLR_DIR" > "$W/losetup_l"
run_script clear
clear_expect_refuse "C08 a COW loop the loop listing does not show is not ours" 43 snapshot_not_ours
clear_world c-dirs-differ
printf '/dev/loop99 /dev/shm/tmp.ZyXwVuTsRq/cow\n' > "$W/losetup_l"
run_script clear
clear_expect_refuse "C09 a mount and a COW file in DIFFERENT directories are not ours" 43 snapshot_not_ours
clear_world c-open
printf '/proc/4242/fd/7\n' > "$W/open_handles"
run_script clear
clear_expect_refuse "C10 a process holding the snapshot open is never torn down underneath" 27 handle_open
clear_world c-lname
run_script clear
if grep -q "^find	/proc	.*	-lname	/dev/dm-3	" "$W/state/argv"; then ok "C10b the open-handle scan names the snapshot's own device node (/dev/dm-N from the pinned name's blkdevname), not an input"
else no "C10b the /proc scan did not name /dev/dm-3: $(grep '^find	/proc' "$W/state/argv" | tr '\t' ' ' | cut -c1-200)"; fi
clear_world c-notluks-host
printf '0\n' > "$W/isluks_rc"
run_script clear
clear_expect_refuse "C11 the typed device being LUKS (or unknown) stops a clear exactly as it stops a wipe" 23 luks_or_unknown
clear_world c-args
run_script clear WIPE_ROW_DT=1760000000
if [ "$RC" = 16 ] && [[ "$(tail -n 1 "$W/err")" == "wipe-assert: rc=16 reason=arg_pre_only"* ]] && [ "$(clear_removals)" = 0 ]; then ok "C12 a clear that is handed a boot row date or a listing mode refuses (arg_pre_only), nothing removed"
else no "C12 clear accepted pre-only inputs: rc=$RC"; fi
clear_inv "C12"
clear_world c-remove-fails
touch "$W/fail_remove"
run_script clear
if [ "$RC" = 36 ] && [ ! -s "$W/out" ] && [[ "$(tail -n 1 "$W/err")" == "wipe-assert: rc=36 reason=teardown_failed"* ]]; then ok "C13 a remove that fails is wipe_snapshot_teardown_failed (rc 36), never a success"
else no "C13 failed remove: rc=$RC out=[$(cat "$W/out")] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
clear_inv "C13"
clear_world c-umount-fails
touch "$W/fail_umount"
run_script clear
if [ "$RC" = 36 ] && [ ! -s "$W/out" ] && [[ "$(tail -n 1 "$W/err")" == "wipe-assert: rc=36 reason=teardown_failed"* ]] && [ "$(clear_removals)" = 1 ]; then ok "C14 a failed umount is rc 36 and the remaining steps are still attempted (collect-then-continue)"
else no "C14 failed umount: rc=$RC removals=$(clear_removals) err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
clear_inv "C14"
clear_world c-written
printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/written_on_umount"
run_script clear
if [ "$RC" = 29 ] && [ ! -s "$W/out" ] && [[ "$(tail -n 1 "$W/err")" == "wipe-assert: rc=29 reason=sectors_written"* ]]; then ok "C15 origin write counters that moved during the clear are wipe_device_written (rc 29): the clear proves the origin untouched after the removal"
else no "C15 written origin: rc=$RC err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
clear_inv "C15"
clear_world c-ro-lost
printf '0\n' > "$W/ro"
run_script clear
clear_expect_refuse "C16 an origin whose kernel read-only flag is not 1 is wipe_ro_flag_lost, nothing removed" 30 ro_flag_lost
# ── the layout-independent signal: off-list, non-empty, unparseable ──────────────────────────────
world a-offdir
mkdir -p "$W/tree/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A10 an extra top-level directory: the refusal carries COUNTS and fixed fields only" 34 offlist "top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-offfile
: > "$W/tree/$CORPUS_TOP_FILE"
run_script pre
expect_refuse "A11 an extra top-level file" 34 offlist "top_d=2 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-reposlink
tree_reset; mkdir -p "$W/tree/lost+found" "$W/outside/$CORPUS_REPO_A"; ln -s "$W/outside" "$W/tree/repositories"
run_script pre
expect_refuse "A12 repositories is a SYMLINK: never followed, off the allowlist" 34 offlist "top_d=1 top_f=0 top_l=1 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-reposfile
tree_reset; mkdir -p "$W/tree/lost+found"; : > "$W/tree/repositories"
run_script pre
expect_refuse "A13 repositories is a regular file" 34 offlist "top_d=1 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-fifo
mkfifo "$W/tree/$CORPUS_TOP_FILE" || instrument "mkfifo failed"
run_script pre
expect_refuse "A14 a FIFO at the top level counts as other and is off the allowlist" 34 offlist "top_d=2 top_f=1 top_l=0 top_o=1 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"
if grep -q 'top_o=1' "$W/err"; then ok "A14 the FIFO is counted under top_o"; else no "A14 the FIFO was not counted as other: $(cat "$W/err")"; fi

world a-gclink
rm -f "$W/tree/.gc-cursor"; ln -s /etc/hostname "$W/tree/.gc-cursor"
run_script pre
expect_refuse "A15 .gc-cursor as a symlink is off the allowlist (path-typed, not name-only)" 34 offlist "top_d=2 top_f=0 top_l=1 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-lostfile
rmdir "$W/tree/lost+found" && : > "$W/tree/lost+found" || instrument "A16 setup failed"
run_script pre
expect_refuse "A16 lost+found as a file is off the allowlist" 34 offlist "top_d=1 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-absent-beside
tree_reset; mkdir -p "$W/tree/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A17 no repositories directory beside a non-allowlisted entry" 34 offlist "top_d=1 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"

world a-nonempty
mkdir -p "$W/tree/repositories/$CORPUS_REPO_A" "$W/tree/repositories/$CORPUS_REPO_B"
run_script pre
expect_refuse "A20 repositories/ holds entries after the replay" 37 repositories_not_empty
if grep -q 'repos=2' "$W/err"; then ok "A20 the refusal carries a COUNT (repos=2) and no name"; else no "A20 count missing: $(cat "$W/err")"; fi
if [[ "$(tail -n 1 "$W/err")" != *has_hooks_d* ]]; then ok "A20 an rc 37 refusal carries no rc=34 diagnostic field"; else no "A20 an rc 37 line carries has_hooks_d: $(tail -n 1 "$W/err")"; fi

# ── rc=34 diagnostic fields (2026-10-18): a fixed-vocabulary bit for the system directory and two counts ──────
world a120-incident
tree_reset; mkdir -p "$W/tree/repositories" "$W/tree/lost+found" "$W/tree/hooks"
run_script pre
expect_refuse "A120 incident replay: repositories, lost+found and hooks (directories) only" 34 offlist "top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1 hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"
world a122-hooks-and-tenant
mkdir -p "$W/tree/hooks" "$W/tree/$CORPUS_TOP_DIR"; : > "$W/tree/$CORPUS_TOP_FILE"
run_script pre
expect_refuse "A122 hooks beside a tenant-shaped directory and file in one listing: only the bit and the counts leave" 34 offlist "top_d=4 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=3 hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"
for v in symlink file dotd upper fifo suffix; do
  world "a123-$v"
  case "$v" in
    symlink) mkdir -p "$W/outside-hooks"; : > "$W/outside-hooks/pre-receive"; ln -s "$W/outside-hooks" "$W/tree/hooks"; ex="top_d=2 top_f=1 top_l=1 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
    file)    : > "$W/tree/hooks"; ex="top_d=2 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
    dotd)    mkdir -p "$W/tree/hooks.d"; ex="top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
    upper)   mkdir -p "$W/tree/Hooks"; ex="top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
    fifo)    mkfifo "$W/tree/hooks" || instrument "mkfifo failed"; ex="top_d=2 top_f=1 top_l=0 top_o=1 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
    suffix)  mkdir -p "$W/tree/old-hooks"; ex="top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1" ;;
  esac
  run_script pre
  expect_refuse "A123 hooks variant ($v): only an exact, case-sensitive DIRECTORY named hooks sets the bit" 34 offlist "$ex"
done
world a124-nested-hooks
mkdir -p "$W/tree/lost+found/hooks"
run_script pre
expect_refuse "A124 a nested lost+found/hooks directory: the top-level bit reads 0 and the entry is counted under lost+found" 34 offlist "top_d=2 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=1 offlist_n=0"
world a125-locks-and-offdir
touch "$W/tree/.init.lock" "$W/tree/.5.init.lock"; mkdir -p "$W/tree/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A125 allowlisted lock files beside one off-list directory: the locks are not counted as off-list" 34 offlist "top_d=3 top_f=3 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"
world a126-lf-many
mkdir -p "$W/tree/lost+found/d"; touch "$W/tree/lost+found/a" "$W/tree/lost+found/d/b"
run_script pre
expect_refuse "A126 lost+found holding two entries (one nested deeper): lf_entries is a non-recursive COUNT, not a flag" 34 offlist "top_d=2 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=2 offlist_n=0"
world a129-offdir-and-lf
mkdir -p "$W/tree/$CORPUS_TOP_DIR"; : > "$W/tree/lost+found/$CORPUS_TOP_FILE"
run_script pre
expect_refuse "A129 an off-list directory AND an entry inside lost+found: both counters move" 34 offlist "top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=1 offlist_n=1"
world a132-hooks-and-control
mkdir -p "$W/tree/hooks"; : > "$W/tree/bad"$'\001'"name"
run_script pre
expect_refuse "A132 a valid hooks directory AND a control-character name: rc 35, the refusal precedes any bit" 35 record_control
if [[ "$(tail -n 1 "$W/err")" != *has_hooks_d* ]]; then ok "A132 the rc 35 line carries no has_hooks_d field"; else no "A132 an rc 35 line carries has_hooks_d: $(tail -n 1 "$W/err")"; fi

# ── rc=34 hooks shape fields (2026-10-19): ONE optional group of four, present iff has_hooks_d=1 ─────────────────
# hk_entries / hk_nonfile / hk_pr_f / hk_pr_small describe the depth-1 TYPE and SIZE metadata of a real top-level hooks
# directory at one moment; no name, size or content leaves the host. A printed 0 is "zero at that moment", never "unread".
# Every world is pinned by the WHOLE line. Synthesized names only (cq-test-fixtures-synthesized-only).
HK_HEAD="top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1"
hk_tree() { tree_reset; mkdir -p "$W/tree/repositories" "$W/tree/lost+found" "$W/tree/hooks"; }
hk_clean() { # <label> — no reader was called on a tree path (the reads file exists and is empty) and neither a name nor a size bound reached an output
  if [ -e "$W/state/reads" ] && [ ! -s "$W/state/reads" ]; then ok "$1: no shimmed reader was called on a tree path (cat, head, a checksum or dump tool, tail, sed, grep, cut, awk, wc, dd, python3, perl, diff, cmp, sort): no read was recorded; a reader outside that list is covered by the static layer (HK8, HK10-HK11), not by this row"
  else no "$1: a reader was called, or the recorder file is missing: $(tr '\t' ' ' < "$W/state/reads" | head -3 | cut -c1-200)"; fi
  if grep_none -F -e pre-receive -e 4096 -e 4097 "$W/out" "$W/err"; then ok "$1: neither the probed name nor a size bound reached stdout or stderr"
  else no "$1: the probed name or a size bound reached an output (or the probe itself failed)"; fi
}
# world setups (also used by the mutation rows below): the contents of the hooks directory
set_hk_pronly()    { hk_tree; : > "$W/tree/hooks/pre-receive"; }
set_hk_three()     { hk_tree; cp "$HK_STRIPPED" "$W/tree/hooks/pre-receive"; : > "$W/tree/hooks/$CORPUS_HK_FILE"; : > "$W/tree/hooks/.dot-synth"; }
set_hk_subdir()    { hk_tree; : > "$W/tree/hooks/pre-receive"; mkdir -p "$W/tree/hooks/$CORPUS_TOP_DIR"; : > "$W/tree/hooks/$CORPUS_TOP_DIR/a-synth"; : > "$W/tree/hooks/$CORPUS_TOP_DIR/b-synth"; }
set_hk_mixed()     { hk_tree; mkdir "$W/tree/hooks/dir-synth"; ln -s /nowhere-synth "$W/tree/hooks/link-synth"; mkfifo "$W/tree/hooks/fifo-synth" || instrument "mkfifo failed"; : > "$W/tree/hooks/post-receive"; }
set_hk_prlink()    { hk_tree; mkdir -p "$W/outside"; printf 'x' > "$W/outside/live-synth"; ln -s "$W/outside/live-synth" "$W/tree/hooks/pre-receive"; }
set_hk_lookalike() { hk_tree; : > "$W/tree/hooks/Pre-receive"; : > "$W/tree/hooks/pre-receive.bak"; : > "$W/tree/hooks/old-pre-receive"; : > "$W/tree/hooks/pre-receivX"; }
set_hk_4096()      { hk_tree; truncate -s 4096 "$W/tree/hooks/pre-receive"; }
set_hk_4097()      { hk_tree; truncate -s 4097 "$W/tree/hooks/pre-receive"; }
set_hk_prdir()     { hk_tree; mkdir "$W/tree/hooks/pre-receive"; }
set_hk_prfifo()    { hk_tree; mkfifo "$W/tree/hooks/pre-receive" || instrument "mkfifo failed"; }
set_hk_nested()    { hk_tree; mkdir "$W/tree/hooks/sub-synth"; : > "$W/tree/hooks/sub-synth/pre-receive"; }
set_hk_ht_all()    { hk_tree; printf 'fsdcbpDUl' > "$W/hooks_ht"; }
set_hk_ht_x()      { hk_tree; printf 'fx' > "$W/hooks_ht"; }
set_hk_shape_fail() { hk_tree; touch "$W/fail_hooks_shape"; }
set_hk_pr_fail()   { hk_tree; : > "$W/tree/hooks/pre-receive"; touch "$W/fail_hooks_pr"; }
set_hk_pr_x()      { hk_tree; : > "$W/tree/hooks/pre-receive"; printf 'x' > "$W/hooks_pr_out"; }
set_hk_wc_nonfile() { hk_tree; printf '4' > "$W/wc_garbage_at"; }
set_hk_errbump()   { hk_tree; touch "$W/bump_errors_hooks"; }
hk_row() { # <label> <group> — run the pre phase on the current world and pin the WHOLE rc=34 line
  run_script pre
  expect_refuse "$1" 34 offlist "$HK_HEAD $2"
  hk_clean "$1"
}
hk_fail() { # <label> <reason> — a failed or unparseable hooks read refuses at rc 33 with a fixed word and prints no hk_ text
  expect_refuse "$1" 33 "$2"
  if grep_none -F hk_ "$W/out" "$W/err"; then ok "$1: no hk_ text on any output (no partial line)"; else no "$1: hk_ text reached an output (or the probe itself failed)"; fi
}
# the shipped hook as a host receives it (the Terraform strip of whole-line comments), as a fixture and for the bound row.
# The strip expression is READ from modules/git-data-userdata/main.tf, never restated here: the extraction is the anchored one of
# git-data-runcmd-rehearsal.test.sh B1 (a commented decoy line cannot be picked up; \t and \n converted as B1 converts them), with
# B1's known-commented probe and a decoy probe of its own, so a stripper that disagreed with production fails here, not silently.
HK_STRIPPED="$T/hk-stripped-hook.sh"
python3 -I - "$DIR/git-data-pre-receive.sh" "$HK_STRIPPED" "$DIR/modules/git-data-userdata/main.tf" <<'PY' || instrument "stripping the shipped hook failed"
import re, sys
s = open(sys.argv[1], "rb").read().decode()
tf = open(sys.argv[3], "rb").read().decode()
ANCHORED = r'^\s*git_data_rationale_strip\s*=\s*"([^"]*)"'
m = re.search(ANCHORED, tf, re.M)
if not m:
    print("no git_data_rationale_strip in modules/git-data-userdata/main.tf", file=sys.stderr); sys.exit(1)
expr = m.group(1)
if not (expr.startswith("/") and expr.endswith("/")):
    print("git_data_rationale_strip is not a /.../ regex literal: %r" % expr, file=sys.stderr); sys.exit(1)
d = re.search(ANCHORED, '# git_data_rationale_strip = "/(?m)decoy/"\n' + tf, re.M)
if not d or d.group(1) != expr:
    print("the anchored extraction picked up a commented decoy line", file=sys.stderr); sys.exit(1)
strip = re.compile(expr[1:-1].replace("\\t", "\t").replace("\\n", "\n"))
if not strip.search("#!/bin/sh\n# a comment\n"):
    print("the strip expression matches nothing on a known-commented probe", file=sys.stderr); sys.exit(1)
open(sys.argv[2], "wb").write(strip.sub("", s).encode())
PY
[ -s "$HK_STRIPPED" ] || instrument "the stripped hook fixture is empty"

world a140-hk-pronly
set_hk_pronly
hk_row "A140 hooks holding only a 0-byte regular pre-receive" "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"
if contract_has "$W" 'find|@D@/mnt/hooks|-mindepth|1|-maxdepth|1|-printf|%y' 1 \
   && contract_has "$W" 'find|@D@/mnt/hooks|-mindepth|1|-maxdepth|1|-name|pre-receive|-type|f|(|-size|-4097c|-printf|s|-o|-printf|b|)' 1; then
  ok "A140 the two hooks reads are exactly the modelled argv: no -L, -H, -iname, %f, %p or trailing slash, one %y walk and one fixed-letter pre-receive find"
else no "A140 the hooks reads differ from the model: $(argv_norm "$W" | grep '/hooks' | tr '\n' ';' | cut -c1-400)"; fi
world a141-hk-three
set_hk_three
hk_row "A141 the stripped shipped hook as pre-receive beside a tenant-shaped file and a dotfile: three entries, a count not a flag" "hk_entries=3 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"
world a142-hk-subdir
set_hk_subdir
hk_row "A142 pre-receive beside a subdirectory holding two files: depth 1 only, the directory counts once" "hk_entries=2 hk_nonfile=1 hk_pr_f=1 hk_pr_small=1"
world a143-hk-mixed
set_hk_mixed
hk_row "A143 a directory, a symlink, a FIFO and a regular file named post-receive: no pre-receive, three non-files" "hk_entries=4 hk_nonfile=3 hk_pr_f=0 hk_pr_small=0"
world a144-hk-prlink
set_hk_prlink
hk_row "A144 pre-receive as a symlink to a LIVE regular file outside hooks: a link is not a regular file, nothing is followed" "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"
world a145-hk-lookalike
set_hk_lookalike
hk_row "A145 Pre-receive, pre-receive.bak, old-pre-receive and pre-receivX: the match is exact and case-sensitive" "hk_entries=4 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"
world a146-hk-4096
set_hk_4096
hk_row "A146 pre-receive of exactly 4096 bytes is within the bound" "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"
world a147-hk-4097
set_hk_4097
hk_row "A147 pre-receive of 4097 bytes is one over the bound" "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=0"
# pre-receive must be a regular file DIRECTLY inside hooks: a directory, a FIFO and a file nested one level down never set the bits
world a148-hk-prdir
set_hk_prdir
hk_row "A148 pre-receive as a DIRECTORY: counted as one non-file entry, not a regular file" "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"
world a149-hk-prfifo
set_hk_prfifo
hk_row "A149 pre-receive as a FIFO: counted as one non-file entry, not a regular file" "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"
world a153-hk-nested
set_hk_nested
hk_row "A153 hooks/sub/pre-receive only (no top-level pre-receive): the nested file is not directly inside hooks" "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"
# the type-string alphabet: unprivileged worlds cannot create s, c, b, D or U entries, so the shape call is made to print
# each letter (the shim's hooks_ht override) beside an f
for _L in f d l c b p s D U; do
  world "a150-hk-ht-$_L"
  hk_tree; printf 'f%s' "$_L" > "$W/hooks_ht"
  if [ "$_L" = f ]; then _hn=0; else _hn=1; fi
  hk_row "A150 type string f$_L: letter $_L is $([ "$_hn" = 0 ] && echo a regular file || echo a non-file)" "hk_entries=2 hk_nonfile=$_hn hk_pr_f=0 hk_pr_small=0"
done
world a151-hk-ht-all
set_hk_ht_all
hk_row "A151 every type letter at once: nine entries, eight non-files" "hk_entries=9 hk_nonfile=8 hk_pr_f=0 hk_pr_small=0"
world a152-hk-ht-big
hk_tree; head -c 100000 /dev/zero | tr '\0' f > "$W/hooks_ht"
hk_row "A152 a 100000-entry type string is counted by its length, not flagged (the count is pinned; no time bound is claimed)" "hk_entries=100000 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"
# a read that fails or answers off-shape is rc 33 with a fixed word, never a default 0 and never a partial line
world a160-hk-shape-fail
set_hk_shape_fail
run_script pre
hk_fail "A160 the shape find fails" hooks_shape_failed
world a161-hk-ht-unknown
set_hk_ht_x
run_script pre
hk_fail "A161 the shape find prints a character outside the type alphabet (x)" hooks_shape_unparseable
world a161b-hk-ht-upper
hk_tree; printf 'fF' > "$W/hooks_ht"
run_script pre
hk_fail "A161b an upper-case F is outside the type alphabet (case-sensitive)" hooks_shape_unparseable
# wc calls in these worlds: 1 repositories count, 2 lock count, 3 lost+found count, 4 the non-file count, 5 the alphabet count
world a162-hk-wc-nonfile
set_hk_wc_nonfile
run_script pre
hk_fail "A162 the non-file count is not a number" hooks_shape_unparseable
world a163-hk-wc-alpha
hk_tree; printf '5' > "$W/wc_garbage_at"
run_script pre
hk_fail "A163 the alphabet count is not a number" hooks_shape_unparseable
world a164-hk-pr-fail
set_hk_pr_fail
run_script pre
hk_fail "A164 the pre-receive find fails" hooks_pr_failed
world a165-hk-pr-unknown
set_hk_pr_x
run_script pre
hk_fail "A165 the pre-receive find prints a letter other than s or b" hooks_pr_unparseable
world a165b-hk-pr-two
hk_tree; : > "$W/tree/hooks/pre-receive"; printf 'sb' > "$W/hooks_pr_out"
run_script pre
hk_fail "A165b the pre-receive find prints two letters" hooks_pr_unparseable
# ORDER: the reads sit before the ext4 errors_count re-read, so an error they induce is caught by it
world a166-hk-errcount
set_hk_errbump
run_script pre
hk_fail "A166 a filesystem error induced by the hooks reads is caught by the errors_count re-read" errors_count_changed_by_listing

world a-newline
tree_reset; mkdir -p "$W/tree/repositories" "$W/tree/${CORPUS_NL_A}"$'\n'"${CORPUS_NL_B}"
run_script pre
expect_refuse "A21 a top-level name with a newline is unparseable, never skipped" 35 record_control

world a-findfail
touch "$W/fail_find_listing"
run_script pre
expect_refuse "A22 a failing listing find is NO signal (the terminator record is missing), never an empty listing" 33 listing_failed

# ── the snapshot apparatus ───────────────────────────────────────────────────────────────────────
world a-createfail
touch "$W/fail_create"
run_script pre
expect_refuse "A30 dmsetup create fails" 33 snapshot_create_failed

world a-mountfail
touch "$W/fail_mount"
run_script pre
expect_refuse "A31 the snapshot does not mount" 33 snapshot_mount_failed

world a-invalid
touch "$W/snap_invalid"
run_script pre
expect_refuse "A32 an invalidated snapshot (COW overflow)" 33 snapshot_invalid

world a-notreplayed
printf 'Filesystem features:      has_journal needs_recovery\nFilesystem state:         not clean\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_snap"
run_script pre
expect_refuse "A33 the journal did not replay into the snapshot" 33 journal_not_replayed

world a-witherrors
printf 'Filesystem features:      has_journal extent\nFilesystem state:         clean with errors\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_snap"
run_script pre
expect_refuse "A34 a replayed snapshot that reads 'with errors'" 33 snapshot_with_errors

world a-errcount
printf '3\n' > "$W/files/sys/fs/ext4/dm-3/errors_count"
run_script pre
expect_refuse "A35 ext4 errors_count differs from the volume's historical count after the replay" 33 errors_count_changed_by_replay

world a-deps
printf '1 dependencies\t: (8, 32)\n' > "$W/deps"
run_script pre
expect_refuse "A36 the snapshot's origin is another device" 33 snapshot_origin_mismatch

world a-losetupfail
touch "$W/fail_losetup"
run_script pre
expect_refuse "A37 losetup of the COW fails" 33 losetup_failed

world a-dumpfail
touch "$W/fail_dumpe2fs"
run_script pre
expect_refuse "A38 dumpe2fs of the origin fails" 33 dumpe2fs_failed

world a-bs1024
set_contract
printf 'Filesystem features:      has_journal needs_recovery\nFilesystem state:         not clean\nTotal journal blocks:     8192\nBlock size:               1024\n' > "$W/sb_origin"
run_script pre
if contract_has "$W" 'truncate|-s|100663296|--|@D@/cow' 1; then ok "A39a a 1024-byte block size is clamped to 4096 when the COW is sized (8192*4096 + 64 MiB)"; else no "A39a COW size: $(argv_norm "$W" | grep '^truncate' || true)"; fi

world a-geometry
printf 'Filesystem features:      has_journal needs_recovery\n' > "$W/sb_origin"
run_script pre
expect_refuse "A39 the journal geometry is unreadable, so the COW cannot be sized" 33 geometry_unreadable

# ── teardown ─────────────────────────────────────────────────────────────────────────────────────
world a-umountfail
touch "$W/fail_umount"
run_script pre
if [ "$RC" = 36 ] && [ ! -s "$W/out" ] && grep -q 'rc=36 reason=teardown_failed' "$W/err"; then ok "A40 umount fails -> rc 36 teardown_failed (outranks every other verdict)"
else no "A40 expected rc 36 teardown_failed; got rc=$RC err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
# the apparatus is deliberately still up in the simulation (the teardown FAILED); the invariants that matter here are the grammar and the names
if [ "$(wc -l < "$W/state/shm_dirs")" = 1 ] && [ -d "$(head -n 1 "$W/state/shm_dirs")/mnt" ]; then ok "A40 the script keeps its COW directory while the mount survives (it never removes a tree under a live mount); the suite removes it below"
else no "A40 the COW directory state after a failed umount is not the modelled one"; fi
rm -rf -- "$W/shm"
leak="$(grep -rlF -f "$PATS" "$W/out" "$W/err" "$W/state" || true)"
if [ -z "$leak" ]; then ok "A40 no name in any output or state file on the teardown-failure path"; else no "A40 name leaked: $leak"; fi

world a-removefail
touch "$W/fail_remove"
run_script pre
if [ "$RC" = 36 ] && [ ! -s "$W/out" ]; then ok "A41 dmsetup remove fails -> rc 36"; else no "A41 expected rc 36; got rc=$RC err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi

world a-loopdfail
touch "$W/fail_losetup_d"
run_script pre
if [ "$RC" = 36 ] && [ ! -s "$W/out" ]; then ok "A42 losetup -d fails -> rc 36"; else no "A42 expected rc 36; got rc=$RC err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi

world a-written-listing
printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/written_on_umount"
run_script pre
expect_refuse "A43 the origin's counters moved during the listing" 29 origin_written_during_listing

# ── H1/H2: the store facts ───────────────────────────────────────────────────────────────────────
world a-notmapper
printf '/dev/sdb\n' > "$W/findmnt_source"
run_script pre
expect_refuse "A50 the store is not served by the mapper" 11 store_not_on_mapper
world a-frozen
: > "$W/root/.cutover-freeze"
run_script pre
expect_refuse "A51 the freeze sentinel exists" 12 cutover_frozen
world a-freeze-probe
touch "$W/fail_find_freeze"
run_script pre
expect_refuse "A56 the store root cannot be read for the freeze sentinel (EACCES/EIO): probe_failed, never 'not frozen'" 16 freeze_probe
world a-freeze-noroot
rmdir "$W/root"
run_script pre
expect_refuse "A57 the store root does not exist (real find, ENOENT): the sentinel's absence is not asserted" 16 freeze_probe

world a-nouuid
: > "$W/fs_uuid"
run_script pre
expect_refuse "A52 the mounted filesystem reports no UUID" 13 no_fs_uuid
world a-nomarker
rm -f "$W/marker"
run_script pre
expect_refuse "A53 the store marker is absent" 14 marker_absent
world a-markerbad
printf 'ffffffff-0000-4000-8000-000000000000\n' > "$W/marker"
run_script pre
expect_refuse "A54 the store marker names another filesystem" 15 marker_mismatch
world a-findmntfail
touch "$W/fail_findmnt"
run_script pre
expect_refuse "A55 findmnt cannot read the source: probe_failed, not a store verdict" 16 findmnt_source

# ── H3-H5: the device ────────────────────────────────────────────────────────────────────────────
world a-nobyid
: > "$W/links"
run_script pre
expect_refuse "A60 the by-id link of the typed id does not resolve" 20 byid_unresolved
world a-notblock
printf '/dev/sdb file 8:10\n/dev/sdc block 8:20\n' > "$W/nodes"
run_script pre
expect_refuse "A61 the node is not a block special file" 21 not_block
world a-isbacking
printf '/dev/sdb\n' > "$W/cs_device"
run_script pre
expect_refuse "A62 the typed device IS the mapper's backing device" 22 typed_is_backing
world a-lucksmismatch
printf '/dev/disk/by-id/scsi-0HC_Volume_%s /dev/sdb\n/dev/disk/by-id/scsi-0HC_Volume_%s /dev/sdd\n' "$ID_T" "$ID_L" > "$W/links"
printf '/dev/sdb block 8:10\n/dev/sdc block 8:20\n/dev/sdd block 8:30\n' > "$W/nodes"
run_script pre
expect_refuse "A63 the LUKS volume's by-id device is not the mapper's backing device (both directions)" 38 luks_not_backing
world a-csfail
touch "$W/fail_cs_status"
run_script pre
expect_refuse "A64 cryptsetup status fails: probe_failed" 16 cryptsetup_status
world a-isluks0
printf '0\n' > "$W/isluks_rc"
run_script pre
expect_refuse "A65 cryptsetup isLuks exits 0: the device is LUKS" 23 luks_or_unknown
world a-isluks4
printf '4\n' > "$W/isluks_rc"
run_script pre
expect_refuse "A66 cryptsetup isLuks exits 4: unknown is never read as plaintext" 23 luks_or_unknown

# ── H6/H7: mounted, holders, leftover snapshot, open handle ──────────────────────────────────────
world a-inmountinfo
printf '40 35 8:16 / /mnt/x rw - ext4 /dev/sdb rw\n' >> "$W/files/proc/self/mountinfo"
run_script pre
expect_refuse "A70 a mountinfo line carries the device number" 24 in_mountinfo
world a-findmntS
printf '/dev/sdb /mnt/x ext4 rw\n' > "$W/findmnt_S"
run_script pre
expect_refuse "A71 findmnt -S names a mount of the device" 24 findmnt_source
world a-holders
printf 'dm-0\n' > "$W/files/sys/dev/block/8:16/holders"
run_script pre
expect_refuse "A72 the device has holders" 25 holders
world a-noholdersdir
rm -f "$W/files/sys/dev/block/8:16/holders"
run_script pre
expect_refuse "A73 no sysfs holders entry: refused, not assumed empty" 25 holders_unreadable
world a-leftsnap
printf 'git-data-pt-snap\t(253:9)\n' > "$W/dm_ls"
run_script pre
expect_refuse "A74 a leftover git-data-pt-snap exists" 26 snapshot_present
world a-dmlsfail
touch "$W/fail_dm_ls"
run_script pre
expect_refuse "A75 dmsetup ls fails: probe_failed, not 'no snapshot'" 16 dmsetup_ls
world a-handle
printf '/proc/4242/fd/7\n' > "$W/open_handles"
run_script pre
expect_refuse "A76 a process holds the device open" 27 handle_open
world a-handle-unknown
printf '1\n' > "$W/find_proc_rc"
run_script pre
expect_refuse "A77 the /proc scan fails twice with no hit: unknown refuses" 27 handle_unknown

# ── H8: quiescent, untouched since enumeration, kernel read-only ─────────────────────────────────
world a-active
printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"
printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/stat_alt"
run_script pre
expect_refuse "A80 the sector counters move between two reads" 28 counters_moved
world a-written
printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"
run_script pre
expect_refuse "A81 sectors written are nonzero although stable (absolute zero required)" 29 sectors_written
world a-discarded
printf '0 0 0 0 0 0 0 0 0 0 0 0 0 5\n' > "$W/files/sys/dev/block/8:16/stat"
run_script pre
expect_refuse "A82 sectors discarded are nonzero" 29 sectors_written
world a-rolost
printf '0\n' > "$W/ro"
run_script pre
expect_refuse "A83 the kernel read-only flag is gone" 30 ro_flag_lost
world a-shortstat
printf '0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"
run_script pre
expect_refuse "A84 a sysfs stat without discard fields is unreadable, never zero" 16 stat_unreadable

# A failed READ is an instrument failure (rc 16), never a host verdict: the three late reads used to compare an
# empty string and report wipe_device_written / wipe_ro_flag_lost.
world a-stat-late-fail
printf '2' > "$W/stat_fail_from"
run_script pre WIPE_LISTING=skip
expect_refuse "A85 the final sysfs stat read fails: an instrument failure, not sectors_written_late" 16 stat_unreadable_late
world a-stat-after-fail
printf '2' > "$W/stat_fail_from"
run_script pre
expect_refuse "A86 the sysfs stat read after the listing teardown fails: an instrument failure, not origin_written_during_listing" 16 stat_unreadable_after
world a-getro-after-fail
printf '1' > "$W/getro_fail_from"
run_script pre
expect_refuse "A87 the read-only flag read after the listing fails: an instrument failure, not ro_flag_lost_after" 16 getro_failed_after
# the awk membership gates: a crashed awk is not "no hit" (the 1st awk call is the mountinfo gate, the 2nd the
# snapshot-name gate; with the listing run the 3rd reads the origin superblock, the 4th the snapshot's
# features, the 5th its state, and the 6th the post-teardown name list)
for _g in 1:in_mountinfo:pre-skip 2:snapshot_present:pre-skip 3:origin_superblock:pre 4:snapshot_features:pre 5:snapshot_state:pre 6:snapshot_remains:pre; do
  _n="${_g%%:*}"; _rest="${_g#*:}"; _w="${_rest%%:*}"; _m="${_rest#*:}"
  world "a-awk-$_n"
  printf '%s' "$_n" > "$W/awk_fail_at"
  if [ "$_m" = pre-skip ]; then run_script pre WIPE_LISTING=skip; else run_script pre; fi
  expect_refuse "A88.$_n the awk gate ($_w) crashes: an instrument failure (rc 16 awk_failed), not a clean pass" 16 awk_failed
done

# ── H9/H10: the instance and the boot generation ─────────────────────────────────────────────────
world a-instance
printf '999999999\n' > "$W/files/var/lib/cloud/data/instance-id"
run_script pre
expect_refuse "A90 /var/lib/cloud/data/instance-id differs from the Hetzner server id" 31 instance_id_differs
world a-instance-shape
printf 'i-0abc\n' > "$W/files/var/lib/cloud/data/instance-id"
run_script pre
expect_refuse "A91 instance-id is not numeric (the H9 claim fails closed, and says why)" 31 instance_id_nonnumeric
world a-bootafter
run_script pre WIPE_ROW_DT=$((NOW - UPTIME_S - 60))
expect_refuse "A92 the host booted AFTER the boot_complete row (a reboot since the row)" 32 host_booted_after_row
world a-window
run_script pre WIPE_ROW_DT=$((NOW - UPTIME_S + 4000))
expect_refuse "A93 the row is further after the boot than the bounded window" 32 row_outside_window
if grep -q 'boot_to_row_s=4000' "$W/err"; then ok "A93 the measured boot-to-row seconds are on the refusal (digits)"; else no "A93 boot_to_row_s missing: $(cat "$W/err")"; fi
world a-boundary
run_script pre WIPE_ROW_DT=$((NOW - UPTIME_S + 3600))
expect_line "A94 (must-PASS) a row exactly at the window bound passes" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=3600 lock_residue=0 store_root_repos=0$'

# ── post_detach / finish ─────────────────────────────────────────────────────────────────────────
world a-post
touch "$W/byid_gone"
run_script post_detach
expect_line "A100 post_detach: link gone, mapper read, store root" '^wipe_assert post_detach ok byid=gone mapper_read=ok store_root=ok$'
if caught_contract_post; then ok "A100 contract (post_detach): the uncached read is dd if=<mapper> of=/dev/null iflag=direct and nothing else writes or reads a device"
else no "A100 contract (post_detach): the recorded argv differs from the model: $(argv_norm "$W" | tr '\n' ';' | cut -c1-600)"; fi
world a-finish
touch "$W/byid_gone"
run_script finish
expect_line "A101 finish: the same checks under their own phase word" '^wipe_assert finish ok byid=gone mapper_read=ok store_root=ok$'
world a-postpresent
run_script post_detach
expect_refuse "A102 the by-id link is still present after the detach" 40 byid_still_present
if contract_has "$W" 'sleep|1' 20; then ok "A102 the settle wait is 20 one-second sleeps (WA_SETTLE_TRIES)"; else no "A102 settle sleeps: $(argv_norm "$W" | grep -c '^sleep|' || true)"; fi
world a-postdd
touch "$W/byid_gone" "$W/fail_dd"
run_script post_detach
expect_refuse "A103 the uncached mapper read fails" 41 mapper_read_failed
world a-postroot
touch "$W/byid_gone" "$W/fail_ls_root"
run_script post_detach
expect_refuse "A104 the store root cannot be listed" 42 store_root_unreadable
world a-postbyid-unreadable
touch "$W/fail_byid_ls"
run_script post_detach
expect_refuse "A106 the by-id directory cannot be listed: 'cannot tell' (probe_failed), never 'gone'" 16 byid_dir_unreadable
world a-postbyid-empty
touch "$W/byid_gone" "$W/byid_listing_empty"
run_script post_detach
expect_refuse "A107 a by-id listing that does not even show the retained LUKS link is no proof of absence" 16 byid_listing_incomplete
world a-postbyid-stat
touch "$W/stat_denied_byid"
run_script post_detach
expect_refuse "A108 a stat of the by-id link that FAILS while the listing still names it is not 'gone'" 40 byid_still_present
world a-postfreeze-probe
touch "$W/byid_gone" "$W/fail_find_freeze"
run_script post_detach
expect_refuse "A109 post_detach: the freeze sentinel cannot be read, so it is not asserted absent" 16 freeze_probe
world a-postnotmapper
touch "$W/byid_gone"
printf '/dev/sdb\n' > "$W/findmnt_source"
run_script post_detach
expect_refuse "A105 post_detach: the store is no longer served by the mapper" 11 store_not_on_mapper

# ── inputs and xtrace ────────────────────────────────────────────────────────────────────────────
world a-args
run_script bogus
expect_refuse "A110 an unknown phase" 16 arg_phase
world a-args2
run_script pre WIPE_LUKS_ID="$ID_T"
expect_refuse "A111 the typed id equals the LUKS id" 16 arg_ids_equal
world a-args3
run_script pre "WIPE_TYPED_ID=12;touch x"
expect_refuse "A112 a non-numeric volume id" 16 arg_ids
world a-args4
run_script pre WIPE_LISTING=maybe
expect_refuse "A113 an unknown listing mode" 16 arg_listing
world a-args5
run_script pre WIPE_ROW_DT=
expect_refuse "A114 pre without the row's dt" 16 arg_row_dt
world a-args6
touch "$W/byid_gone"
run_script post_detach WIPE_LISTING=run
expect_refuse "A115 a listing mode outside pre" 16 arg_pre_only
world a-xtrace
touch "$W/byid_gone"
assert_fixture_dir "$W"
RC=0
env -i PATH="$SH:/usr/bin:/bin" WORLD="$W" WIPE_PHASE=post_detach WIPE_TYPED_ID="$ID_T" WIPE_LUKS_ID="$ID_L" WIPE_SERVER_ID="$ID_S" \
  WIPE_OLD_ROOT="$W/root" WIPE_LUKS_MAPPER=/dev/mapper/git-data WIPE_STORE_VERIFIED="$W/marker" \
  bash -x -s < "$SCRIPT" > "$W/out" 2> "$W/err" || RC=$?
if [ "$RC" = 16 ] && [ ! -s "$W/out" ] && [ "$(grep -c 'refusing to run under xtrace' "$W/err")" -ge 1 ]; then ok "A116 the script refuses to run under xtrace (the listing holds names)"
else no "A116 xtrace was not refused: rc=$RC"; fi

# ── the corpus is real: the names were on the mounted tree, in a representative number of runs ───
# 15 = the corpus-on-the-tree runs and 7 = the corpus patterns, each measured unprivileged, loopback skipped, 2026-10-19 (CORPUS_N is the
# line count of the pattern file above; NAMES_SEEN_RUNS is read after the Tier-A rows, before the mutation matrix)
# shellcheck disable=SC2015  # ok()/no() cannot fail, so this is a true if/else
[ "$NAMES_SEEN_RUNS" -ge 15 ] && ok "GN: the corpus really was on the mounted tree in $NAMES_SEEN_RUNS runs (the no-names rows are not vacuous)" \
  || no "GN: the corpus reached the mounted tree in only $NAMES_SEEN_RUNS runs"
if [ "$CORPUS_N" -ge 7 ]; then ok "GN: the synthesized corpus holds $CORPUS_N patterns"; else no "GN: the corpus shrank to $CORPUS_N patterns"; fi

# ── forbidden phrases (CLO): the script and the verb claim device-level facts only ───────────────
forbidden="$(grep -inE '\b(erased|wiped|secure(ly)? erasure|no copies|holds no personal data|art\. ?17 satisfied)\b' "$SCRIPT" || true)"
verb_forbidden="$(sed -n '/^mode_wipe_assert()/,/^}/p' "$CUTOVER" | grep -inE '\b(erased|wiped|secure(ly)? erasure|no copies|holds no personal data)\b' || true)"
if [ -z "$forbidden" ] && [ -z "$verb_forbidden" ]; then ok "GP: no forbidden phrase (erased, wiped, secure erasure, no copies, holds no personal data) in the script or the verb"
else no "GP: forbidden phrase present: $forbidden $verb_forbidden"; fi

# ── mutation matrix on the HOST SCRIPT (each row must turn its named case RED) ─────────────────────
echo "--- mutation matrix (host script)"
MUT_DIR="$T/mut"; assert_fixture_dir "$MUT_DIR"; mkdir -p "$MUT_DIR" || instrument "mkdir mut failed"
MUT_ROWS=0
# mutate_script <name> <old> <new> [<old2> <new2>] — copy the script with exactly one occurrence of each
# <old> replaced. Sets MUTANT; returns 1 (silently) when an anchor is not unique or the edit is neutral.
mutate_script() {
  MUTANT="$MUT_DIR/$1.sh"
  python3 - "$SCRIPT" "$MUTANT" "${@:2}" <<'PY' || return 1
import sys
src, dst = sys.argv[1:3]
pairs = sys.argv[3:]
s = open(src).read()
for i in range(0, len(pairs), 2):
    assert s.count(pairs[i]) == 1, s.count(pairs[i])
    s = s.replace(pairs[i], pairs[i + 1])
open(dst, "w").write(s)
PY
  if cmp -s "$SCRIPT" "$MUTANT"; then return 1; fi
  return 0
}
# mutant_row <name> <old> <new> <world-setup-fn> <phase> <case-fn> — the case function must be FALSE
# (the mutant is caught as wrong) for the row to pass; a still-true case is a missed mutation.
mutant_row() {
  local name="$1"
  mutate_script "$name" "$2" "$3" ${7:+"$7" "$8"} || { no "M-$name: the mutation anchor is not unique, or the edit is neutral"; return 0; }
  MUT_ROWS=$((MUT_ROWS + 1))
  # a STATIC case reads only the mutant's TEXT ($MUTANT), never a world or a run: running the mutant first would change nothing
  if [[ " ${STATIC_CASES:-} " != *" $6 "* ]]; then
    world "m-$name"
    "$4"
    if [ "$5" = pre-skip ]; then RUN_SCRIPT="$MUTANT" run_script pre WIPE_LISTING=skip; else RUN_SCRIPT="$MUTANT" run_script "$5"; fi
    RUN_SCRIPT=""
  fi
  if "$6"; then no "M-$name: the mutant is still accepted by the original's case (the row is vacuous or the mutation was neutral)"
  else ok "M-$name: the named case goes RED against the mutant"; fi
}
RUN_SCRIPT=""
set_offdir()   { mkdir -p "$W/tree/$CORPUS_TOP_DIR"; }
set_reposlink() { tree_reset; mkdir -p "$W/tree/lost+found" "$W/outside/$CORPUS_REPO_A"; ln -s "$W/outside" "$W/tree/repositories"; }
set_written()  { printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"; }
set_isluks0()  { printf '0\n' > "$W/isluks_rc"; }
set_findfail() { touch "$W/fail_find_listing"; }
set_markerbad() { printf 'ffffffff-0000-4000-8000-000000000000\n' > "$W/marker"; }
set_clean()    { :; }
set_notmapper() { printf '/dev/sdb\n' > "$W/findmnt_source"; }
set_holders()  { printf 'dm-0\n' > "$W/files/sys/dev/block/8:16/holders"; }
set_isbacking() { printf '/dev/sdb\n' > "$W/cs_device"; }
set_umountfail() { touch "$W/fail_umount"; }
set_gone()     { touch "$W/byid_gone"; }
set_notblock() { printf '/dev/sdb file 8:10\n/dev/sdc block 8:20\n' > "$W/nodes"; }
caught_rc()   { # <rc> — true when the run is refused with that rc and prints nothing on stdout
  [ "$RC" = "$1" ] && [ ! -s "$W/out" ]
}
caught_16() { caught_rc 16; }
caught_34() { caught_rc 34; }
caught_29() { caught_rc 29; }
caught_30() { caught_rc 30; }
caught_23() { caught_rc 23; }
caught_33() { caught_rc 33; }
caught_15() { caught_rc 15; }
caught_11() { caught_rc 11; }
caught_25() { caught_rc 25; }
caught_22() { caught_rc 22; }
caught_36() { caught_rc 36; }
caught_21() { caught_rc 21; }
caught_grammar() { # the output is ONE line of the fixed pre grammar and nothing else
  local got; got="$(cat "$W/out")"; [ "$(wc -l < "$W/out")" = 1 ] && [[ "$got" =~ $RE_PRE ]] && [ ! -s "$W/err" ]
}
caught_no_leak() { # no synthesized name in stdout/stderr (the mutant prints one)
  grep_none -rlF -f "$PATS" "$W/out" "$W/err"
}

# M1 (Guard 8 row 1): the classifier prints one synthesized name
mutant_row m1-prints-name '      [ -n "$n" ] || die 35 record_empty' '      [ -n "$n" ] || die 35 record_empty
      say "$n"' set_offdir pre caught_no_leak
# M2 (Guard 8 row 4): a digest of the listing rides on the output line
mutant_row m2-digest 'store_root_repos=%s\n'"'"' \' 'store_root_repos=%s digest=0f0f\n'"'"' \' set_clean pre caught_grammar
# M3: the path-typed allowlist is name-only (a symlinked repositories is accepted)
mutant_row m3-name-only-allowlist '        repositories:d) HAS_REPOS=yes ;;' '        repositories:*) HAS_REPOS=yes ;;' set_reposlink pre caught_34
# M4: the absolute-zero written counters check is dropped
mutant_row m4-no-absolute-zero '    [ "$W0" = "0 0" ] || die 29 sectors_written' '    :' set_written pre caught_29
# M5: only exit 1 of isLuks is "not LUKS" -- the check is dropped
mutant_row m5-isluks-ignored '    [ "$rc" -eq 1 ] || die 23 luks_or_unknown' '    :' set_isluks0 pre caught_23
# M6: a failed find reads as an empty listing (the terminator requirement dropped)
mutant_row m6-find-failure-is-empty '    [ "$saw_end" = 1 ] || die 33 listing_failed' '    :' set_findfail pre caught_33
# M7: the marker equality is dropped
mutant_row m7-marker-unchecked '    [ "$m" = "$fu" ] || die 15 marker_mismatch' '    :' set_markerbad pre caught_15
# M8: the mapper-source check is dropped
mutant_row m8-source-unchecked '    [ "$s" = "$MAPPER" ] || die 11 store_not_on_mapper' '    :' set_notmapper pre caught_11
# M9: holders ignored
mutant_row m9-holders-ignored '    [ -z "$hold" ] || die 25 holders' '    :' set_holders pre-skip caught_25
# M10: the backing-device check (typed device is the mapper backing) is dropped
mutant_row m10-backing-unchecked '    [ "$bmm" != "$MM" ] || die 22 typed_is_backing' '    :' set_isbacking pre caught_22
# M11: a teardown failure is swallowed (both the in-line check and the EXIT trap's retry)
mutant_row m11-teardown-swallowed '    wa_release || die 36 teardown_failed' '    wa_release || true' set_umountfail pre caught_36 \
  '      wa_release || { say "wipe-assert: rc=36 reason=teardown_failed"; exit 36; }' '      wa_release || true'
# M12: a non-block node is accepted
mutant_row m12-block-unchecked '    [ "$t" = "block special file" ] || die 21 not_block' '    :' set_notblock pre caught_21
# M13-M15: a failed read compared as an empty string (the three late reads)
set_stat_late()  { printf '2' > "$W/stat_fail_from"; }
set_getro_after() { printf '1' > "$W/getro_fail_from"; }
set_awk_gate1()  { printf '1' > "$W/awk_fail_at"; }
mutant_row m13-late-stat-read-unchecked '  w_late="$(wstat)" || die 16 stat_unreadable_late' '  w_late="$(wstat)"' set_stat_late pre-skip caught_16
mutant_row m14-after-stat-read-unchecked '    w_after="$(wstat)" || die 16 stat_unreadable_after' '    w_after="$(wstat)"' set_stat_late pre caught_16
mutant_row m15-getro-after-unchecked '    ro_after="$(blockdev --getro "$DEV")" || die 16 getro_failed_after' '    ro_after="$(blockdev --getro "$DEV")"' set_getro_after pre caught_16
mutant_row m16-awk-gate-fails-open '    case "$arc" in 0) return 0 ;; 1) return 1 ;; *) die 16 awk_failed ;; esac' '    case "$arc" in 0) return 0 ;; *) return 1 ;; esac' set_awk_gate1 pre-skip caught_16
# M17-M20: the listing and probe tightening
set_lfcontent()   { : > "$W/tree/lost+found/$CORPUS_TOP_FILE"; }
set_lockdir()     { mkdir -p "$W/tree/repositories/.ws-9.init.lock/$CORPUS_REPO_A"; }
set_lfrepos()     { mkdir -p "$W/tree/repositories/lost+found/$CORPUS_REPO_A"; }
set_stat_denied() { touch "$W/stat_denied_byid"; }
set_noroot()      { rmdir "$W/root"; }
caught_37() { caught_rc 37; }
caught_40() { caught_rc 40; }
mutant_row m17-lostfound-contents-unread '      [ "$ln" -eq 0 ] || OFFLIST=1' '      :' set_lfcontent pre caught_34
# rc=34 diagnostic fields: each case is TRUE only on the pristine whole line for its world, rc 34 included
set_hooksfile()  { : > "$W/tree/hooks"; }
set_hooksdotd()  { mkdir -p "$W/tree/hooks.d"; }
set_hooksdir()   { tree_reset; mkdir -p "$W/tree/repositories" "$W/tree/lost+found" "$W/tree/hooks"; }
set_hookstenant() { mkdir -p "$W/tree/hooks" "$W/tree/$CORPUS_TOP_DIR"; : > "$W/tree/$CORPUS_TOP_FILE"; }
# line34_is <tail> — rc 34, the LAST stderr line equals the whole expected one and is the ONLY rc=34 line, EVERY stderr line is a
# fixed reason line and no corpus name reached stdout or stderr (a mutant that emits an earlier line must not pass on its last line alone)
line34_is() {
  local l
  [ "$RC" = 34 ] && [ "$(tail -n 1 "$W/err")" = "wipe-assert: rc=34 reason=offlist $1" ] && rc34_once || return 1
  while IFS= read -r l; do [[ "$l" =~ $RE_ERR ]] || return 1; done < "$W/err"
  grep_none -rlF -f "$PATS" "$W/out" "$W/err"
}
caught_hooksfile()   { line34_is "top_d=2 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"; }
caught_hooksdotd()   { line34_is "top_d=3 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=0 offlist_n=1"; }
caught_lfentries()   { line34_is "top_d=2 top_f=1 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=1 offlist_n=0"; }
caught_hookstenant() { line34_is "top_d=4 top_f=2 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=3 hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"; }
caught_hooksdir()    { line34_is "top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1 hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"; }
mutant_row m-hooks-name-only 'if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi' 'if [ "$n" = hooks ]; then HAS_HOOKS=1; fi' set_hooksfile pre caught_hooksfile
mutant_row m-hooks-glob 'if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi' 'if [[ "$n" == hooks* ]] && [ "$t" = d ]; then HAS_HOOKS=1; fi' set_hooksdotd pre caught_hooksdotd
mutant_row m-lf-entries-zero '      LF_ENTRIES="$ln"' '      LF_ENTRIES=0' set_lfcontent pre caught_lfentries
mutant_row m-offlist-n-flag '*) OFFLIST=1; OFFLIST_N=$((OFFLIST_N + 1)) ;;' '*) OFFLIST=1; OFFLIST_N=1 ;;' set_hookstenant pre caught_hookstenant
mutant_row m-hooks-allowlisted '        .gc-cursor:f | .init.lock:f) : ;;' '        .gc-cursor:f | .init.lock:f) : ;;
        hooks:d) : ;;' set_hooksdir pre caught_hooksdir
mutant_row m-line-leaks-name '      case "$n" in *[[:cntrl:]]*) die 35 record_control ;; esac' '      case "$n" in *[[:cntrl:]]*) die 35 record_control ;; esac
      LEAK="$n"' set_hookstenant pre caught_hookstenant \
  ' offlist_n=$OFFLIST_N$HK_TAIL"' ' offlist_n=$OFFLIST_N$HK_TAIL x=$LEAK"'
mutant_row m18-lock-excluded-by-name '"$WA_MNT/repositories" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '"'"'.*.init.lock'"'"' -o -name '"'"'.init.lock'"'"' \) \)' '"$WA_MNT/repositories" -mindepth 1 -maxdepth 1 ! -name '"'"'.*.init.lock'"'"' ! -name '"'"'.init.lock'"'"'' set_lockdir pre caught_37
mutant_row m19-lostfound-repos-excluded-by-name '! \( -type d -name lost+found -empty \) -printf x | wc -c)" || die 33 repos_count_failed' '! -name lost+found -printf x | wc -c)" || die 33 repos_count_failed' set_lfrepos pre caught_37
# A1 (2026-10-15): the store-root count and the id-bearing lock count.
set_srrepos()  { mkdir -p "$W/root/repositories/$CORPUS_REPO_A"; }
set_srlocks()  { mkdir -p "$W/root/repositories"; : > "$W/root/repositories/.ws-9.init.lock"; }
set_srsymlink() { ln -s lost+found "$W/root/repositories"; }
set_lockres()  { tree_clean; : > "$W/tree/repositories/.ws-9.init.lock"; }
caught_srr1()  { grep -qE ' store_root_repos=1$' "$W/out"; }
caught_srr0()  { grep -qE ' store_root_repos=0$' "$W/out"; }
caught_lockres1() { grep -qE ' lock_residue=1 ' "$W/out"; }
caught_42()    { caught_rc 42; }
mutant_row m24-store-root-count-hardcoded '        SRR="$n" ;;' '        SRR=0 ;;' set_srrepos pre caught_srr1
mutant_row m25-store-root-lock-counted '! \( -type f \( -name '"'"'.*.init.lock'"'"' -o -name '"'"'.init.lock'"'"' \) \) ! \( -type d -name lost+found -empty \) -printf x | wc -c)" || die 42 store_root_unreadable' '-printf x | wc -c)" || die 42 store_root_unreadable' set_srlocks pre caught_srr0
mutant_row m26-store-root-symlink-accepted '      *) die 42 store_root_unreadable ;;' '      *) SRR=0 ;;' set_srsymlink pre caught_42
mutant_row m27-lock-residue-repos-dropped '      LOCKS=$((LOCKS + lk))' '      LOCKS="$LOCKS_TOP"' set_lockres pre caught_lockres1
# A1 (2026-10-15): the clear phase (CTO follow-up ruling, Guard 9 rows 7-13). Each edit makes a leftover this file did not
# make removable, or lets a touched origin / a failed removal pass; the named clear case must go RED against it.
set_cl_ok()      { clear_state; }
set_cl_origin()  { clear_state; printf '0 2097152 snapshot 8:32 7:99 N 8\n' > "$W/dm_table"; }
set_cl_persist() { clear_state; printf '0 2097152 snapshot 8:16 7:99 P 8\n' > "$W/dm_table"; }
set_cl_dirs()    { clear_state; printf '/dev/loop99 /dev/shm/tmp.ZyXwVuTsRq/cow\n' > "$W/losetup_l"; }
set_cl_open()    { clear_state; printf '/proc/4242/fd/7\n' > "$W/open_handles"; }
set_cl_written() { clear_state; printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/written_on_umount"; }
set_cl_ro()      { clear_state; printf '0\n' > "$W/ro"; }
set_cl_rmfail()  { clear_state; touch "$W/fail_remove"; }
caught_43() { caught_rc 43; }
caught_27c() { caught_rc 27; }
caught_lname() { [ "$RC" = 0 ] && grep -q "^find	/proc	.*	-lname	/dev/dm-3	" "$W/state/argv"; }
caught_36td() { [ "$RC" = 36 ] && [ ! -s "$W/out" ] && [[ "$(head -n 1 "$W/err")" == "wipe-assert: rc=36 reason=teardown_failed"* ]]; }
caught_clear_ok() { [ "$RC" = 0 ] && [ "$(cat "$W/out")" = "wipe_assert clear ok snapshot=cleared" ]; }
mutant_row m50-clear-origin-unchecked '[ "$d" = "$(devno_dec "$MM")" ] && ' '' set_cl_origin clear caught_43
mutant_row m52-clear-persistent-accepted ' [ "$f" = N ] &&' '' set_cl_persist clear caught_43
mutant_row m53-clear-dirs-unchecked 'if [ -n "$mntdir" ] && [ "$mntdir" != "$cowdir" ]; then die 43 snapshot_not_ours; fi' ':' set_cl_dirs clear caught_43
mutant_row m54-clear-handles-unchecked '-lname "/dev/$dmn" -print -quit)" || rc=$?' '-lname "/dev/never" -print -quit)" || rc=$?' set_cl_ok clear caught_lname
mutant_row m55-clear-counters-unchecked 'case "$W0" in "0 0") : ;; *) die 29 sectors_written ;; esac' ':' set_cl_written clear caught_29
mutant_row m56-clear-ro-unchecked 'case "$ro" in 1) : ;; *) die 30 ro_flag_lost ;; esac' ':' set_cl_ro clear caught_30
mutant_row m57-clear-removal-swallowed 'if ! wa_release; then die 36 teardown_failed; fi' 'wa_release || true' set_cl_rmfail clear caught_36td
mutant_row m20-byid-stat-fails-open '    while byid_present; do' '    while stat -- "$BYID"; do' set_stat_denied post_detach caught_40
mutant_row m21-freeze-by-test-e '    fz="$(find -H "$OLD_ROOT" -mindepth 1 -maxdepth 1 -name .cutover-freeze -print)" || die 16 freeze_probe' '    fz=""; [ ! -e "$OLD_ROOT/.cutover-freeze" ] || fz=x' set_noroot pre caught_16
# M22-M33: the selector mutants (each aims one call at the wrong operand or drops/adds one flag): the clean run's
# whole argv record must stop equalling the model
mutant_row m22-getro-on-mapper '    ro="$(blockdev --getro "$DEV")" || die 16 getro_failed' '    ro="$(blockdev --getro "$MAPPER")" || die 16 getro_failed' set_contract pre caught_contract_pre
mutant_row m23-isluks-on-mapper '    cryptsetup isLuks -- "$DEV" || rc=$?' '    cryptsetup isLuks -- "$MAPPER" || rc=$?' set_contract pre caught_contract_pre
mutant_row m24-proc-scan-on-mapper "-lname \"\$DEV\"" "-lname \"\$MAPPER\"" set_contract pre caught_contract_pre
mutant_row m25-dd-writes-the-device 'dd if="$MAPPER" of=/dev/null bs=4096' 'dd if="$MAPPER" of="$DEV" bs=4096' set_gone post_detach caught_contract_post
mutant_row m26-dd-cached-read ' count=1 iflag=direct ||' ' count=1 ||' set_gone post_detach caught_contract_post
mutant_row m27-mount-read-write 'mount -o ro,errors=remount-ro,nosuid,nodev,noexec' 'mount -o rw,errors=remount-ro,nosuid,nodev,noexec' set_contract pre caught_contract_pre
mutant_row m28-snapshot-persistent 'snapshot $DEV $WA_LOOP N 8' 'snapshot $DEV $WA_LOOP P 8' set_contract pre caught_contract_pre
mutant_row m29-snapshot-origin-cow-swapped 'snapshot $DEV $WA_LOOP N 8' 'snapshot $WA_LOOP $DEV N 8' set_contract pre caught_contract_pre
mutant_row m30-loop-on-the-device 'losetup --find --show -- "$WA_DIR/cow"' 'losetup --find --show -- "$DEV"' set_contract pre caught_contract_pre
mutant_row m31-no-quiescence-sleep '    sleep 2' '    :' set_contract pre caught_contract_pre
mutant_row m32-cow-size-constant 'cow_bytes=$((jb * bs + 67108864))' 'cow_bytes=4096' set_contract pre caught_contract_pre
mutant_row m33-no-direct-find-regex "-regex '/proc/[0-9]+/fd/[0-9]+'" "-regex '/proc/[0-9]+/fdinfo/[0-9]+'" set_contract pre caught_contract_pre
# ── rc=34 hooks shape fields: the Guard Contract mutation matrix (2026-10-19) ────────────────────────────────────
# Each row runs an UNMUTATED control first (the case must hold for the real script, or the mutant row would be vacuous),
# then the mutant: the named case must go RED. Cases pin the WHOLE rc=34 line (or the fixed rc-33 word).
HK_ALLOWED="$T/hk-allowed.lines"
cat > "$HK_ALLOWED" <<'HKEOF'
    HK_TAIL=""
    if [ "$HAS_HOOKS" = 1 ]; then
      budget
      ht="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -printf '%y')" || die 33 hooks_shape_failed
      nf="$(printf '%s' "$ht" | tr -d f | wc -c)" || die 33 hooks_shape_failed
      al="$(printf '%s' "$ht" | tr -d 'dflcbpsDU' | wc -c)" || die 33 hooks_shape_failed
      [[ "$nf" =~ ^[0-9]+$ && "$al" =~ ^[0-9]+$ ]] || die 33 hooks_shape_unparseable
      [ "$((10#$al))" -eq 0 ] || die 33 hooks_shape_unparseable
      pr="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -name "$WA_HK_PR" -type f \( -size -$((WA_HK_PR_MAX + 1))c -printf s -o -printf b \))" || die 33 hooks_pr_failed
      [[ "$pr" =~ ^[sb]?$ ]] || die 33 hooks_pr_unparseable
      HK_PR_F=0
      if [ -n "$pr" ]; then HK_PR_F=1; fi
      HK_PR_SMALL=0
      if [ "$pr" = s ]; then HK_PR_SMALL=1; fi
      HK_TAIL=" hk_entries=${#ht} hk_nonfile=$((10#$nf)) hk_pr_f=$HK_PR_F hk_pr_small=$HK_PR_SMALL"
    fi
HKEOF
# hk_block <script> — the lines between the two hooks sentinels. hk_block_closed <script> — a STRUCTURAL check (this is not a
# syscall trace: the suite has no strace, A116 refuses xtrace, and a shim sees only argv): the non-comment lines of the hooks
# block are EXACTLY the reviewed literals above, in the reviewed ORDER (a SEQUENCE compare, no sort: a dropped, an added, a
# duplicated, a replaced or a reordered line fails; the heredoc above is in block order and is green on the unmodified script), so
# a content read written as a command, a builtin ($(<f), read <f, mapfile) or an extra find fails here whatever it is called.
# Outside the block three further rules hold (hk_outside_closed, hk_no_file_redirect, hk_budget_first below), and the reader shims
# (a content reader handed a tree operand) are a separate, independent layer.
hk_block() { awk '/# ---- BEGIN wipe-hooks reads ----/{f=1;next} /# ---- END wipe-hooks reads ----/{f=0} f' "$1"; }
hk_code() { grep -vE '^[[:space:]]*(#.*)?$' "$1" || true; }   # the non-comment, non-blank lines of a file
hk_block_closed() {
  local got want
  got="$(hk_block "$1" | hk_code /dev/stdin)"
  want="$(hk_code "$HK_ALLOWED")"
  [ -n "$want" ] && [ "$got" = "$want" ]
}
# hk_budget_first <script> — inside the hooks block the one `budget` line precedes the first timeout-30 find (a budget that runs
# after the finds no longer bounds the two 30 s reads; no cheap clock world exists because budget reads the SECONDS builtin).
hk_budget_first() { hk_block "$1" | awk '/^      budget$/ { b = NR } /timeout 30 find/ { if (!f) f = NR } END { exit !(b && f && b < f) }'; }
# The lines OUTSIDE the block that touch the mounted tree or the raw snapshot are exactly these, as a MULTISET (every one reviewed;
# a line dropped and masked by a duplicate of another fails). "Touch" is derived from the script's own variables, not from the names
# of the files a reader would want: every name that holds the hooks directory, the pre-receive file or a hook constant (WA_HK*,
# HK_*, hooks, pre-receive), the mounted tree or the directory that holds it (WA_MNT, /mnt, WA_DIR, tgt = the findmnt target of
# the mount, mntdir and cowdir = the directories parsed from it), the snapshot node and its kernel name (WA_SNAP, /dev/mapper, dm and
# dmn = the blkdevname, so `/dev/$dm`; src, got and want = the mount source and the two realpaths of the snapshot node), the device
# behind it (DEV; BYID and BYID_LUKS = the by-id names of the retired device and of the LUKS volume; MAPPER and MAPPER_NAME = the
# mapper of the old store) and the loop and COW file (WA_LOOP, lo = the losetup listing, lk = the loop node, lf = the COW file).
# BYID and MAPPER are unbounded on purpose (they also match BYID_LUKS and MAPPER_NAME); the short lowercase names are word-bounded so
# an ordinary word does not match. That set was read off the script (grep for every assignment of or to a mount path, a mapper node, a
# device or a loop node, 2026-10-19); a new variable that holds one of them must be added to HK_TOUCH_RE and its lines reviewed here.
# Not touch words, on purpose: OLD_ROOT and MARKER (the OLD store's root and its marker file, a different tree from the retired
# device: a read of them is the old-store verification the script is for), and sb, ssb, st, tbl, names and hits (the text of a command
# that already ran, not a path). A new line that touches any of the names above comes back here. The /mnt term is load-bearing (the
# mount root and every path under it); do not narrow this. The recorder sees only a TREE operand, so a read of the raw volume by
# another name is seen by this list alone.
HK_TOUCH_RE='WA_HK|pre-receive|hooks|HK_|WA_MNT|/mnt|WA_DIR|WA_SNAP|WA_LOOP|/dev/mapper|BYID|MAPPER|(^|[^A-Za-z0-9_])(tgt|cowdir|mntdir|DEV|src|got|want|dm|dmn|lf|lk|lo)([^A-Za-z0-9_]|$)'
HK_OUT_ALLOWED="$T/hk-out-allowed.lines"
cat > "$HK_OUT_ALLOWED" <<'HKEOF'
  readonly WA_SNAP=git-data-pt-snap
  readonly WA_HK_DIR=hooks
  readonly WA_HK_PR=pre-receive
  readonly WA_HK_PR_MAX=4096
  WA_DIR="" WA_MNT="" WA_LOOP="" WA_SNAP_UP=0 WA_MOUNTED=0
      if timeout 30 umount "$WA_MNT"; then WA_MOUNTED=0; else first="umount"; fi
    if [ "$WA_SNAP_UP" = 1 ]; then
      if timeout 45 dmsetup remove --retry "$WA_SNAP"; then WA_SNAP_UP=0; else first="${first:-dmsetup}"; fi
    if [ -n "$WA_LOOP" ]; then
      if timeout 10 losetup -d "$WA_LOOP"; then WA_LOOP=""; else first="${first:-losetup}"; fi
    if [ "$WA_MOUNTED" != 1 ] && [ -n "$WA_DIR" ]; then
      if rm -f -- "$WA_DIR/cow"; then
        rmdir -- "$WA_MNT" "$WA_DIR" || true
        WA_DIR=""
    if [ -n "$WA_DIR$WA_LOOP" ] || [ "$WA_SNAP_UP" = 1 ] || [ "$WA_MOUNTED" = 1 ]; then
  DEV="" MM="" SYS="" W0="" BOOT_TO_ROW=""
    DEV="$(realpath -e -- "$BYID")" || die 20 byid_unresolved
    [[ "$DEV" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || die 20 byid_unresolved
    t="$(stat -L -c %F -- "$DEV")" || die 21 stat_failed
    MM="$(devnum_hex "$DEV")" || die 16 devno_unreadable
    cryptsetup isLuks -- "$DEV" || rc=$?
    hits="$(findmnt -n -S "$DEV")" || rc=$?
    if awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 26 snapshot_present; fi
      hits="$(timeout 20 find /proc -ignore_readdir_race -maxdepth 3 -type l -regex '/proc/[0-9]+/fd/[0-9]+' -lname "$DEV" -print -quit)" || rc=$?
    ro="$(blockdev --getro "$DEV")" || die 16 getro_failed
    st="$(dmsetup status "$WA_SNAP")" || die 33 snapshot_status_unreadable
      if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi
    local ht nf al pr HK_PR_F HK_PR_SMALL
    sb="$(timeout 20 dumpe2fs -h "$DEV")" || die 33 dumpe2fs_failed
    WA_DIR="$(mktemp -d -p /dev/shm)" || { WA_DIR=""; die 33 mktemp_failed; }
    WA_MNT="$WA_DIR/mnt"
    mkdir -- "$WA_MNT" || die 33 mkdir_failed
    truncate -s "$cow_bytes" -- "$WA_DIR/cow" || die 33 cow_failed
    WA_LOOP="$(losetup --find --show -- "$WA_DIR/cow")" || { WA_LOOP=""; die 33 losetup_failed; }
    sz="$(blockdev --getsz "$DEV")" || die 33 getsz_failed
    if ! timeout 30 dmsetup create "$WA_SNAP" --table "0 $sz snapshot $DEV $WA_LOOP N 8"; then
      if dmsetup info "$WA_SNAP"; then WA_SNAP_UP=1; fi
    WA_SNAP_UP=1
    deps="$(dmsetup deps "$WA_SNAP")" || die 33 deps_unreadable
    timeout 45 mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$WA_SNAP" "$WA_MNT" || die 33 snapshot_mount_failed
    src="$(findmnt -n -o SOURCE --mountpoint "$WA_MNT")" || die 33 mount_source_unreadable
    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved
    ssb="$(timeout 20 dumpe2fs -h "/dev/mapper/$WA_SNAP")" || die 33 snapshot_superblock_unreadable
    dm="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 33 blkdevname_unreadable
    wl_classify < <(timeout 30 find "$WA_MNT" -mindepth 1 -maxdepth 1 -printf '%y\t%f\0' && printf 'E\tEND\0')
      rn="$(timeout 30 find "$WA_MNT/repositories" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '.*.init.lock' -o -name '.init.lock' \) \) ! \( -type d -name lost+found -empty \) -printf x | wc -c)" || die 33 repos_count_failed
      lk="$(timeout 30 find "$WA_MNT/repositories" -mindepth 1 -maxdepth 1 -type f -name '.?*.init.lock' -printf x | wc -c)" || die 33 lock_count_failed
      ln="$(timeout 30 find "$WA_MNT/lost+found" -mindepth 1 -maxdepth 1 -printf x | wc -c)" || die 33 lostfound_count_failed
    if awk_hit "$names_after" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 36 snapshot_remains; fi
    ro_after="$(blockdev --getro "$DEV")" || die 16 getro_failed_after
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D top_f=$TOP_F top_l=$TOP_L top_o=$TOP_O repos=$REPOS has_hooks_d=$HAS_HOOKS lf_entries=$LF_ENTRIES offlist_n=$OFFLIST_N$HK_TAIL"
    ro="$(blockdev --getro "$DEV")" || die 16 getro_unreadable
    local names tbl tbl2 c d e f h dmn rc try hits tgt mntdir lo lk lf cowdir
    if ! awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then CLEAR_RESULT=absent; return 0; fi
    tbl="$(dmsetup table "$WA_SNAP")" || die 16 table_unreadable
    dmn="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 16 blkdevname_unreadable
    tgt="$(findmnt -n -o TARGET -S "/dev/mapper/$WA_SNAP")" || rc=$?
    mntdir=""
    if [ -n "$tgt" ]; then
      case "$tgt" in *$'\n'*) die 43 snapshot_not_ours ;; esac
      [[ "$tgt" =~ ^(/dev/shm/tmp\.[A-Za-z0-9]{6,12})/mnt$ ]] || die 43 snapshot_not_ours
      mntdir="${BASH_REMATCH[1]}"
    cowdir="${BASH_REMATCH[1]}"
    if [ -n "$mntdir" ] && [ "$mntdir" != "$cowdir" ]; then die 43 snapshot_not_ours; fi
    tbl2="$(dmsetup table "$WA_SNAP")" || die 16 table_unreadable
    WA_DIR="$cowdir"; WA_MNT="$cowdir/mnt"; WA_LOOP="$lk"; WA_SNAP_UP=1
    if [ -n "$mntdir" ]; then WA_MOUNTED=1; fi
    if awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 36 snapshot_remains; fi
      LOCKS=$((LOCKS + lk))
      [[ "$lk" =~ ^[0-9]+$ ]] || die 33 lock_count_unparseable
      hits="$(timeout 20 find /proc -ignore_readdir_race -maxdepth 3 -type l -regex '/proc/[[:digit:]]+/fd/[[:digit:]]+' -lname "/dev/$dmn" -print -quit)" || rc=$?
    [ "$got" = "$want" ] || die 33 mount_source_not_snapshot
    [ "$s" = "$MAPPER" ] || die 11 store_not_on_mapper
    [[ "$dmn" =~ ^dm-[0-9]+$ ]] || die 16 blkdevname_unparseable
    [[ "$lf" =~ ^(/dev/shm/tmp\.[A-Za-z0-9]{6,12})/cow(\ \(deleted\))?$ ]] || die 43 snapshot_not_ours
    case "$lf" in "" | *$'\n'*) die 43 snapshot_not_ours ;; esac
    case $'\n'"$names"$'\n' in *$'\n'"${BYID##*/}"$'\n'*) return 0 ;; esac
    case $'\n'"$names"$'\n' in *$'\n'"${BYID_LUKS##*/}"$'\n'*) : ;; *) die 16 byid_listing_incomplete ;; esac
    e0="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    e1="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    got="$(realpath -e -- "$src")" || die 33 mount_source_unresolved
    lf="$(printf '%s\n' "$lo" | sed -n "s#^${lk}[[:space:]][[:space:]]*\(.*\)\$#\1#p")"
    lk="/dev/loop${e#*:}"
    lmm="$(devnum_hex "$BYID_LUKS")" || die 38 luks_byid_unresolved
    lo="$(losetup -l -n -O NAME,BACK-FILE)" || die 16 losetup_list
    local sb jb bs cow_bytes eh sz deps src got want ssb dm e0 e1 rn ln lk names_after hold_after w_after ro_after
    mm="$(devnum_hex "$BYID")" || die 20 device_vanished
    st="$(cryptsetup status "$MAPPER_NAME")" || die 16 cryptsetup_status
    timeout 30 dd if="$MAPPER" of=/dev/null bs=4096 count=1 iflag=direct || die 41 mapper_read_failed
  BYID="/dev/disk/by-id/scsi-0HC_Volume_$TYPED"
  [[ "$OLD_ROOT" =~ ^/[A-Za-z0-9/_.-]+$ && "$MARKER" =~ ^/[A-Za-z0-9/_.-]+$ && "$MAPPER" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || die 16 arg_paths
  local BYID_LUKS="/dev/disk/by-id/scsi-0HC_Volume_$LUKSID"
  local MAPPER_NAME="${MAPPER##*/}"
  local OLD_ROOT="${WIPE_OLD_ROOT-}" MAPPER="${WIPE_LUKS_MAPPER-}" MARKER="${WIPE_STORE_VERIFIED-}"
HKEOF
hk_outside() { awk '/# ---- BEGIN wipe-hooks reads ----/{f=1;next} /# ---- END wipe-hooks reads ----/{f=0;next} !f' "$1"; }
# hk_outside_closed <script> — the touching lines outside the block, sorted, equal the reviewed list, sorted (multiset equality; the
# block itself is a sequence compare, hk_block_closed). HK_FIRST_BAD is set to the first line that differs (an unreviewed line, or a reviewed one that went missing, with
# comm's `<TAB>` marking a line only in the reviewed list), so a failure names its offender.
hk_outside_closed() {
  local l got want
  HK_FIRST_BAD=""
  got="$(while IFS= read -r l; do
    [[ "$l" =~ ^[[:space:]]*# ]] && continue
    [[ "$l" =~ $HK_TOUCH_RE ]] || continue
    printf '%s\n' "$l"
  done < <(hk_outside "$1") | LC_ALL=C sort)"
  want="$(LC_ALL=C sort "$HK_OUT_ALLOWED")"
  [ -n "$want" ] && [ "$got" = "$want" ] && return 0
  HK_FIRST_BAD="$(comm -3 <(printf '%s\n' "$got") <(printf '%s\n' "$want") | head -n 1 | cut -c1-200)"
  return 1
}
# hk_no_file_redirect <script> — no non-comment line of the script reads a file by redirection or by the $(<f) builtin: the only
# input redirections are /dev/null, here-strings, heredocs and process substitutions (a `read < path`, `exec 5<path`, a subshell
# `(<path cmd)`, an awk `getline x < f` or an awk `-F: < f` is flagged). There is NO blanking of `[[ ]]`, `(( ))` or awk programs: a
# lexical blank hid real reads twice (a read between quoted brackets, a getline inside an awk program), so every `<` that is shaped
# like a redirect is flagged wherever it sits, and a comparison is written -lt in this script (the live script holds none; were one
# ever needed it would be allowed by an exact reviewed literal, not by a pattern). The `$(<f)` builtin is a separate test. The
# lines are read from the file itself, the last line with or without a trailing newline, and the count of lines read must equal
# the count of lines in the file, so a read that stops early is a failure, not a clean pass. An unreadable or empty file is a
# failure, never a clean pass. The leading class excludes only `<` and `>` (so `&&<"$f" cat` is a redirect, not a `&<`; the script holds
# no `&<`), and a `<&N` descriptor dup is excluded by the trailing class. The harness rows H6 pin both directions. HK_FIRST_BAD is set to the first offending line.
hk_no_file_redirect() {
  local l raw n=0 want re_redir='(^|[^<>])<[[:space:]]*[^<(&[:space:]=]' re_builtin='\$\([[:space:]]*<'
  HK_FIRST_BAD=""
  [ -s "$1" ] || { HK_FIRST_BAD="(unreadable or empty: $1)"; return 1; }
  want="$(grep -c '' "$1")" || { HK_FIRST_BAD="(unreadable: $1)"; return 1; }
  while IFS= read -r raw || [ -n "$raw" ]; do
    n=$((n + 1))
    [[ "$raw" =~ ^[[:space:]]*# ]] && continue
    l="${raw//< \/dev\/null/}"; l="${l//<\/dev\/null/}"
    if [[ "$l" =~ $re_builtin ]] || [[ "$l" =~ $re_redir ]]; then HK_FIRST_BAD="$(printf '%s' "$raw" | cut -c1-200)"; return 1; fi
  done < "$1"
  [ "$n" = "$want" ] || { HK_FIRST_BAD="(read $n of $want lines: $1)"; return 1; }
  return 0
}
# hk_die_args_plain <script> — no die or say call hands a command substitution (or a backtick) to its argument slot: RE_ERR admits
# any key=digits tail, so a size, uid or mode read from the tree could otherwise leave the host on a fixed-word line.
hk_die_args_plain() {
  local l rest re_call='(^|[[:space:];{(|&])(die|say)[[:space:]](.*)$' re_cs='\$\([^(]|`'
  while IFS= read -r l; do
    [[ "$l" =~ ^[[:space:]]*# ]] && continue
    if [[ "$l" =~ $re_call ]]; then
      rest="${BASH_REMATCH[3]}"
      if [[ "$rest" =~ $re_cs ]]; then return 1; fi
    fi
  done < "$1"
  return 0
}
hk_is() { line34_is "$HK_HEAD $1"; }
hk_rc33() { [ "$RC" = 33 ] && [ "$(tail -n 1 "$W/err")" = "wipe-assert: rc=33 reason=$1" ]; }
caught_hk_pronly()    { hk_is "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"; }
caught_hk_three()     { hk_is "hk_entries=3 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"; }
caught_hk_subdir()    { hk_is "hk_entries=2 hk_nonfile=1 hk_pr_f=1 hk_pr_small=1"; }
caught_hk_mixed()     { hk_is "hk_entries=4 hk_nonfile=3 hk_pr_f=0 hk_pr_small=0"; }
caught_hk_prlink()    { hk_is "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"; }
caught_hk_lookalike() { hk_is "hk_entries=4 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0"; }
caught_hk_4096()      { hk_is "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"; }
caught_hk_4097()      { hk_is "hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=0"; }
caught_hk_ht_all()    { hk_is "hk_entries=9 hk_nonfile=8 hk_pr_f=0 hk_pr_small=0"; }
caught_hk_argv() { # the two hooks reads carry the exact modelled argv (kills a trailing slash, -L, -H, a changed depth)
  caught_hk_pronly \
    && contract_has "$W" 'find|@D@/mnt/hooks|-mindepth|1|-maxdepth|1|-printf|%y' 1 \
    && contract_has "$W" 'find|@D@/mnt/hooks|-mindepth|1|-maxdepth|1|-name|pre-receive|-type|f|(|-size|-4097c|-printf|s|-o|-printf|b|)' 1
}
caught_hk33_shape_failed()      { hk_rc33 hooks_shape_failed; }
caught_hk33_shape_unparseable() { hk_rc33 hooks_shape_unparseable; }
caught_hk33_pr_failed()         { hk_rc33 hooks_pr_failed; }
caught_hk33_pr_unparseable()    { hk_rc33 hooks_pr_unparseable; }
caught_hk33_errcount()          { hk_rc33 errors_count_changed_by_listing; }
# recorder (the reads file exists AND is empty: a missing file or a dead recorder must not read as "never opened"), static rules, both
caught_recorder_quiet() { [ -e "$W/state/reads" ] && [ ! -s "$W/state/reads" ]; }
caught_outside_closed() { hk_outside_closed "$MUTANT" && hk_no_file_redirect "$MUTANT"; }
caught_no_open() { caught_recorder_quiet && hk_block_closed "$MUTANT" && caught_outside_closed; }
caught_budget_first() { hk_budget_first "$MUTANT"; }
caught_die_args_plain() { hk_die_args_plain "$MUTANT"; }
# hk_emit_sites_pinned <script> — the number of places the script can write to the two original fds is pinned: `say` call sites
# (the die body, the teardown line, the one rc=34 line), writes to fd 3 (the say body) and writes to fd 4 (the three stdout lines).
# A fourth `say` or any further write to an original fd is a new channel off the host and returns to review. Counted as OCCURRENCES,
# not lines: `say` is counted as a WORD TOKEN (every non-word character is a separator, so `say "x"`, `say;`, `say${IFS}"x"` and
# `a;say;say` are each counted, one per occurrence) and the pinned count is the three call sites plus the one definition `say()`
# (a second definition or a second call each add a token); `>&3` and `>&4` (with or without a blank after the `>&`); and the TOTAL
# number of `>&` tokens is pinned too, so a spelling the per-fd patterns do not match (`>&03`, `>&0004`) still moves a count. Every
# other spelling of a write to a descriptor by name or by variable (`>/dev/fd/N`, `>/proc/self/fd/N`, `>&"$X"`, `>&$X`) must be
# absent. Named literals, measured on the unmodified script (non-comment lines only), unprivileged, on 2026-10-19: the 7 `>&` tokens
# are the xtrace refusal's `>&2`, the two `exec` dups `3>&2 4>&1`, the say body's `>&3` and the three `>&4` stdout lines. A count is
# not an identity test, it is the tripwire for an added write site.
HK_SAY_SITES=3
HK_SAY_DEFS=1
HK_FD3_WRITES=1
HK_FD4_WRITES=3
HK_FD_OTHER_WRITES=0
HK_FD_REDIRECTS=7
hk_emit_sites_pinned() {
  local code say3 fd3 fd4 fdx fdall
  code="$(hk_code "$1")"
  [ -n "$code" ] || return 1
  say3="$(printf '%s\n' "$code" | tr -c 'A-Za-z0-9_\n' '\n' | grep -cx say)" || say3=0
  fd3="$(printf '%s\n' "$code" | grep -oE '>&[[:space:]]*3' | wc -l)"
  fd4="$(printf '%s\n' "$code" | grep -oE '>&[[:space:]]*4' | wc -l)"
  fdx="$(printf '%s\n' "$code" | grep -oE '/dev/fd/|/proc/self/fd/|>&[[:space:]]*[^-0-9[:space:]]' | wc -l)"
  fdall="$(printf '%s\n' "$code" | grep -oE '>&' | wc -l)"
  [ "$((say3))" = "$((HK_SAY_SITES + HK_SAY_DEFS))" ] && [ "$((fd3))" = "$HK_FD3_WRITES" ] && [ "$((fd4))" = "$HK_FD4_WRITES" ] \
    && [ "$((fdx))" = "$HK_FD_OTHER_WRITES" ] && [ "$((fdall))" = "$HK_FD_REDIRECTS" ]
}
caught_emit_pinned() { hk_emit_sites_pinned "$MUTANT"; }
caught_hk_pr_nonfile() { hk_is "hk_entries=1 hk_nonfile=1 hk_pr_f=0 hk_pr_small=0"; }
# The cases that read only the script text: no world and no run is needed for them (mutant_row and the control below skip both).
STATIC_CASES=" caught_outside_closed caught_budget_first caught_die_args_plain caught_emit_pinned "
# hk_mutant <name> <setup> <case> <old> <new> [<old2> <new2>]
# The control (the case against the UNMUTATED script, in a world built by <setup>) depends only on (setup, case, script), so the
# run is done once per such triple and its VERDICT is cached; every row still asserts its own control line from the cached verdict,
# so a failing control fails every row that uses it (the cache can only skip an identical re-run, never hide a failure). The key
# carries the script's checksum, so a different script text is a different key.
declare -A HK_CTRL=()
HK_SIG="$(cksum < "$SCRIPT")"
hk_mutant() {
  local name="$1" set="$2" case_="$3" key
  shift 3
  key="$set|$case_|$HK_SIG|${RUN_SCRIPT:-}"
  if [ -z "${HK_CTRL[$key]+x}" ]; then
    if [[ "$STATIC_CASES" != *" $case_ "* ]]; then world "c-$name"; "$set"; run_script pre; fi
    MUTANT="$SCRIPT"
    if "$case_"; then HK_CTRL[$key]=ok; else HK_CTRL[$key]=bad; fi
  fi
  if [ "${HK_CTRL[$key]}" = ok ]; then ok "M-$name control: the unmutated script satisfies the case"
  else no "M-$name control: the unmutated script does NOT satisfy the case (the mutant row would be vacuous)"; fi
  mutant_row "$name" "$1" "$2" "$set" pre "$case_" ${3:+"$3" "$4"}
}
HK_FIND='find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1'
# 1. the group is emitted only when the guard holds (file and hooks.d worlds expect no group)
hk_mutant m-hk-guard-dropped-file set_hooksfile caught_hooksfile '    if [ "$HAS_HOOKS" = 1 ]; then' '    if :; then'
hk_mutant m-hk-guard-dropped-dotd set_hooksdotd caught_hooksdotd '    if [ "$HAS_HOOKS" = 1 ]; then' '    if :; then'
# 2. a second probed name
hk_mutant m-hk-second-name set_hk_mixed caught_hk_mixed '-name "$WA_HK_PR" -type f' '\( -name "$WA_HK_PR" -o -name post-receive \) -type f'
# 3. hk_entries as a flag
hk_mutant m-hk-entries-flag set_hk_three caught_hk_three 'hk_entries=${#ht}' 'hk_entries=$((${#ht} > 0))'
# 4. depth
hk_mutant m-hk-recursive set_hk_subdir caught_hk_subdir "$HK_FIND -printf" 'find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -printf'
hk_mutant m-hk-mindepth0 set_hooksdir caught_hooksdir "$HK_FIND -printf" 'find "$WA_MNT/$WA_HK_DIR" -mindepth 0 -maxdepth 1 -printf'
# 5. the non-file count (a directory-only count, then a d/l/p-only alphabet)
hk_mutant m-hk-nonfile-dirs-only set_hk_mixed caught_hk_mixed 'nf="$(printf '"'"'%s'"'"' "$ht" | tr -d f | wc -c)"' 'nf="$(printf '"'"'%s'"'"' "$ht" | tr -cd d | wc -c)"'
hk_mutant m-hk-nonfile-alphabet set_hk_ht_all caught_hk_ht_all 'nf="$(printf '"'"'%s'"'"' "$ht" | tr -d f | wc -c)"' 'nf="$(printf '"'"'%s'"'"' "$ht" | tr -cd dlp | wc -c)"'
# 6. a followed symlink
hk_mutant m-hk-pr-follows-symlink set_hk_prlink caught_hk_prlink '-type f \( -size' '-xtype f \( -size'
# 7. the name match: suffix glob, case-insensitive, prefix glob
hk_mutant m-hk-pr-glob-suffix set_hk_lookalike caught_hk_lookalike '-name "$WA_HK_PR" -type f' '-name "$WA_HK_PR*" -type f'
hk_mutant m-hk-pr-iname set_hk_lookalike caught_hk_lookalike '-name "$WA_HK_PR" -type f' '-iname "$WA_HK_PR" -type f'
hk_mutant m-hk-pr-glob-prefix set_hk_lookalike caught_hk_lookalike '-name "$WA_HK_PR" -type f' '-name "*$WA_HK_PR" -type f'
# 8. the size bound, both directions, and the two letters exchanged
hk_mutant m-hk-bound-4095 set_hk_4096 caught_hk_4096 'readonly WA_HK_PR_MAX=4096' 'readonly WA_HK_PR_MAX=4095'
hk_mutant m-hk-bound-4097 set_hk_4097 caught_hk_4097 'readonly WA_HK_PR_MAX=4096' 'readonly WA_HK_PR_MAX=4097'
hk_mutant m-hk-size-no-plus-one set_hk_4096 caught_hk_4096 '-size -$((WA_HK_PR_MAX + 1))c' '-size -$((WA_HK_PR_MAX))c'
hk_mutant m-hk-size-plus-two set_hk_4097 caught_hk_4097 '-size -$((WA_HK_PR_MAX + 1))c' '-size -$((WA_HK_PR_MAX + 2))c'
hk_mutant m-hk-sb-swapped set_hk_4096 caught_hk_4096 '-printf s -o -printf b' '-printf b -o -printf s'
# 9. failures ignored, unparseable answers accepted
hk_mutant m-hk-shape-failure-ignored set_hk_shape_fail caught_hk33_shape_failed "-printf '%y')\" || die 33 hooks_shape_failed" "-printf '%y')\""
hk_mutant m-hk-pr-failure-ignored set_hk_pr_fail caught_hk33_pr_failed '-printf b \))" || die 33 hooks_pr_failed' '-printf b \))"'
hk_mutant m-hk-counts-unchecked set_hk_wc_nonfile caught_hk33_shape_unparseable '[[ "$nf" =~ ^[0-9]+$ && "$al" =~ ^[0-9]+$ ]] || die 33 hooks_shape_unparseable' ':'
hk_mutant m-hk-alphabet-unchecked set_hk_ht_x caught_hk33_shape_unparseable '[ "$((10#$al))" -eq 0 ] || die 33 hooks_shape_unparseable' ':'
hk_mutant m-hk-pr-letter-unchecked set_hk_pr_x caught_hk33_pr_unparseable '[[ "$pr" =~ ^[sb]?$ ]] || die 33 hooks_pr_unparseable' ':'
# 10. a trailing slash on the hooks path (the kernel would follow a symlinked hooks): both finds
hk_mutant m-hk-trailing-slash-shape set_hk_pronly caught_hk_argv "$HK_FIND -printf" 'find "$WA_MNT/$WA_HK_DIR/" -mindepth 1 -maxdepth 1 -printf'
hk_mutant m-hk-trailing-slash-pr set_hk_pronly caught_hk_argv "$HK_FIND -name" 'find "$WA_MNT/$WA_HK_DIR/" -mindepth 1 -maxdepth 1 -name'
# 11. ORDER: the e1 errors_count re-read moved BEFORE the hooks block (the block then runs after the check that covers it)
hk_mutant m-hk-after-e1 set_hk_errbump caught_hk33_errcount \
  '    e1="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing
' '' \
  '    # ---- BEGIN wipe-hooks reads ----
' '    e1="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing
    # ---- BEGIN wipe-hooks reads ----
'
# 12. a content read of pre-receive: a command in the block, a builtin in the block, and a command placed OUTSIDE the block. Each case
# below is the UNION (reader recorder + closed block + outside static rules, caught_no_open); 12b splits the three layers and proves
# each on its own.
hk_mutant m-hk-read-cat set_hk_pronly caught_no_open '      HK_PR_F=0' '      x="$(cat "$WA_MNT/$WA_HK_DIR/$WA_HK_PR")"
      HK_PR_F=0'
hk_mutant m-hk-read-sha256sum set_hk_pronly caught_no_open '      HK_PR_F=0' '      sha256sum "$WA_MNT/$WA_HK_DIR/$WA_HK_PR"
      HK_PR_F=0'
hk_mutant m-hk-read-head set_hk_pronly caught_no_open '      HK_PR_F=0' '      head -c 16 "$WA_MNT/$WA_HK_DIR/$WA_HK_PR"
      HK_PR_F=0'
hk_mutant m-hk-read-builtin set_hk_pronly caught_no_open '      HK_PR_F=0' '      x="$(<"$WA_MNT/$WA_HK_DIR/$WA_HK_PR")"
      HK_PR_F=0'
hk_mutant m-hk-read-cat-outside-block set_hk_pronly caught_no_open '    # ---- BEGIN wipe-hooks reads ----
' '    x="$(cat "$WA_MNT/$WA_HK_DIR/$WA_HK_PR")"
    # ---- BEGIN wipe-hooks reads ----
'
# 12b. A content read placed OUTSIDE the block, one row per reader family, each inserted just above the BEGIN sentinel. The insert is
# guarded by HAS_HOOKS=1 and reads the real path under the mounted tree. Three independent layers, each proven on its own:
#   -union   the combined case (recorder, closed block, outside rules) must go RED for EVERY family
#   -rec     the reader shim recorder ALONE must see it (a reader handed a tree operand lands in state/reads). A recorder that is not
#            proven live proves nothing, so these rows are its per-reader controls (a known reader on a tree path must leave
#            state/reads non-empty). caught_recorder_quiet (the reads file exists and is empty) is used by the union control
#            (caught_no_open) and by every -rec row, in both directions; the static-only and the budget, die-args and emit rows do not use it
#   -static  the outside-block static rules ALONE must see it (hk_outside_closed + hk_no_file_redirect)
# A builtin ($(<f), read < f) is invisible to a shim by nature: only the static layer can see it, so those families have no -rec row.
HK_BEGIN='    # ---- BEGIN wipe-hooks reads ----
'
HK_PRP='"$WA_MNT/$WA_HK_DIR/$WA_HK_PR"'
hk_outside_read() { # <family> <recorder-visible 1|0> <inserted command>
  hk_mutant "m-hk-rd-$1-union" set_hk_pronly caught_no_open "$HK_BEGIN" "    [ \"\$HAS_HOOKS\" = 1 ] && $3
$HK_BEGIN"
  if [ "$2" = 1 ]; then
    hk_mutant "m-hk-rd-$1-rec" set_hk_pronly caught_recorder_quiet "$HK_BEGIN" "    [ \"\$HAS_HOOKS\" = 1 ] && $3
$HK_BEGIN"
  fi
}
hk_outside_read builtin 0 "x_hk=\"\$(<$HK_PRP)\""
hk_outside_read readredir 0 "read -r x_hk < $HK_PRP"
hk_outside_read tail 1 "x_hk=\"\$(tail -c 16 $HK_PRP)\""
hk_outside_read sed 1 "x_hk=\"\$(sed -n 1p $HK_PRP)\""
hk_outside_read grep 1 "x_hk=\"\$(grep -c . $HK_PRP)\""
hk_outside_read cut 1 "x_hk=\"\$(cut -c1-16 $HK_PRP)\""
hk_outside_read dd 1 "dd if=$HK_PRP bs=16 count=1 of=/dev/null"
hk_outside_read awk 1 "x_hk=\"\$(awk 'NR==1' $HK_PRP)\""
hk_outside_read wc 1 "x_hk=\"\$(wc -c $HK_PRP)\""
hk_outside_read python3 1 "x_hk=\"\$(python3 -c 'import sys; print(open(sys.argv[1], \"rb\").read(16))' $HK_PRP)\""
hk_outside_read perl 1 "x_hk=\"\$(perl -ne 'print; last' $HK_PRP)\""
hk_outside_read head 1 "x_hk=\"\$(head -c 16 $HK_PRP)\""
hk_outside_read sha256sum 1 "x_hk=\"\$(sha256sum $HK_PRP)\""
hk_outside_read cat 1 "x_hk=\"\$(cat $HK_PRP)\""
hk_outside_read diff 1 "x_hk=\"\$(diff $HK_PRP /dev/null)\""
hk_outside_read cmp 1 "x_hk=\"\$(cmp $HK_PRP /dev/null)\""
hk_outside_read sort 1 "x_hk=\"\$(sort $HK_PRP)\""
hk_outside_read paste 1 "x_hk=\"\$(paste $HK_PRP)\""
hk_outside_read uniq 1 "x_hk=\"\$(uniq $HK_PRP)\""
hk_outside_read strings 1 "x_hk=\"\$(strings $HK_PRP)\""
hk_outside_read od 1 "x_hk=\"\$(od -c $HK_PRP)\""
# the bare mount root as the operand (no trailing slash, no file under it): a recursive read of the whole tree
HK_MNTP='"$WA_MNT"'
hk_outside_read mntroot 1 "x_hk=\"\$(grep -rc x $HK_MNTP)\""
# the path built in two steps (no literal hooks path on the reading line): the recorder sees the operand, the static rule sees both lines
hk_mutant m-hk-rd-indirect-union set_hk_pronly caught_no_open "$HK_BEGIN" '    hk_d="$WA_MNT/$WA_HK_DIR"
    [ "$HAS_HOOKS" = 1 ] && x_hk="$(tail -c 16 "$hk_d/$WA_HK_PR")"
'"$HK_BEGIN"
hk_mutant m-hk-rd-indirect-rec set_hk_pronly caught_recorder_quiet "$HK_BEGIN" '    hk_d="$WA_MNT/$WA_HK_DIR"
    [ "$HAS_HOOKS" = 1 ] && x_hk="$(tail -c 16 "$hk_d/$WA_HK_PR")"
'"$HK_BEGIN"
# the static layer alone, for a recorder-visible reader and for each builtin form
hk_mutant m-hk-rd-tail-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && x_hk="$(tail -c 16 "$WA_MNT/$WA_HK_DIR/$WA_HK_PR")"
'"$HK_BEGIN"
hk_mutant m-hk-rd-builtin-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && x_hk="$(<"$WA_MNT/$WA_HK_DIR/$WA_HK_PR")"
'"$HK_BEGIN"
# a redirect from a path that names none of the touch words (hooks, pre-receive, HK_, WA_MNT, /mnt, WA_DIR, the tree and snapshot
# variables, /dev/mapper): only the redirect rule sees it, in its plain form, in the subshell form `(<f cmd)` (the first character
# class once excluded the opening parenthesis) and as an awk getline (a read inside an awk program, which no blanking hides)
hk_mutant m-hk-rd-redirect-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && read -r x_hk < "/etc/hostname"
'"$HK_BEGIN"
hk_mutant m-hk-rd-subshell-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && (<"/etc/hostname" wc -c)
'"$HK_BEGIN"
hk_mutant m-hk-rd-awk-getline-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && awk '"'"'BEGIN{ getline x < "/etc/hostname" }'"'"'
'"$HK_BEGIN"
# a path built from $WA_DIR plus a glob names no hooks word and no /mnt on its line: only the WA_DIR term of the touch rule sees it
hk_mutant m-hk-rd-wadir-glob-static set_hk_pronly caught_outside_closed "$HK_BEGIN" '    [ "$HAS_HOOKS" = 1 ] && x_hk="$(uniq "$WA_DIR"/mn?/h*/pre-r*)"
'"$HK_BEGIN"
# every name the script uses for the mounted tree, the directory that holds it, the snapshot node (and its kernel name), the device
# behind it (by-id names included), the mapper of the old store and the loop node and COW file is a touch word (HK_TOUCH_RE above, read
# off the script): a read through any of them, on a line that names no hooks word and no WA_MNT, is seen by the touch list alone (the
# recorder cannot see a glob that matches nothing in the world, nor an operand that is not under the tree: a raw read of the volume
# or of the COW file by another name is seen only here). Each row is inserted just after the line that assigns or first uses the
# name, in the clear path, where the real script holds the value. Not covered by a row of its own: WA_SNAP_UP, lo (the listing text).
hk_insert_after() { # <name> <anchor line (without its newline)> <inserted line>
  hk_mutant "$1" set_hk_pronly caught_outside_closed "$2"$'\n' "$2"$'\n'"$3"$'\n'
}
hk_insert_after m-hk-rd-tgt-paste-static '    tgt="$(findmnt -n -o TARGET -S "/dev/mapper/$WA_SNAP")" || rc=$?' '    x_hk="$(paste "$tgt"/h*/pre-r*)"'
hk_insert_after m-hk-rd-cowdir-uniq-static '    cowdir="${BASH_REMATCH[1]}"' '    uniq "$cowdir"/mn?/h*/pre-r*'
hk_insert_after m-hk-rd-mntdir-tail-static '      mntdir="${BASH_REMATCH[1]}"' '      tail -c 8 "$mntdir"/m??/h*/pre-r*'
hk_insert_after m-hk-rd-mapper-strings-static '    timeout 45 mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$WA_SNAP" "$WA_MNT" || die 33 snapshot_mount_failed' '    strings "/dev/mapper/$WA_SNAP"'
hk_insert_after m-hk-rd-mapper-ddod-static '    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved' '    dd if=/dev/mapper/$WA_SNAP | od -c'
hk_insert_after m-hk-rd-mapper-literal-static '    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved' '    strings /dev/mapper/git-data-pt-snap'
hk_insert_after m-hk-rd-snap-split-static '    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved' '    strings "/dev/m""apper/$WA_SNAP"'
hk_insert_after m-hk-rd-dev-strings-static '    sb="$(timeout 20 dumpe2fs -h "$DEV")" || die 33 dumpe2fs_failed' '    strings "$DEV"'
hk_insert_after m-hk-rd-wa-loop-static '    WA_LOOP="$(losetup --find --show -- "$WA_DIR/cow")" || { WA_LOOP=""; die 33 losetup_failed; }' '    od -c "$WA_LOOP"'
# the names that hold the retired device, the snapshot kernel name, the mount source and the COW file, each on a line that names no
# hooks word, no WA_* and no /dev/mapper: before they were touch words a raw read through any of them left the touch list and the
# redirect rule green (the recorder sees only a tree operand)
hk_insert_after m-hk-rd-dm-dd-static '    dm="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 33 blkdevname_unreadable' '    x_hk="$(dd if=/dev/$dm bs=16 count=1 | wc -c)"'
hk_insert_after m-hk-rd-dmn-strings-static '    dmn="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 16 blkdevname_unreadable' '    strings "/dev/$dmn"'
hk_insert_after m-hk-rd-src-head-static '    src="$(findmnt -n -o SOURCE --mountpoint "$WA_MNT")" || die 33 mount_source_unreadable' '    head -c 16 "$src"'
hk_insert_after m-hk-rd-got-od-static '    got="$(realpath -e -- "$src")" || die 33 mount_source_unresolved' '    od -c "$got"'
hk_insert_after m-hk-rd-want-cat-static '    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved' '    cat "$want"'
hk_insert_after m-hk-rd-lf-head-static '    lf="$(printf '"'"'%s\n'"'"' "$lo" | sed -n "s#^${lk}[[:space:]][[:space:]]*\(.*\)\$#\1#p")"' '    head -c 16 "$lf"'
hk_insert_after m-hk-rd-lk-od-static '    lk="/dev/loop${e#*:}"' '    od -c "$lk"'
hk_insert_after m-hk-rd-byid-strings-static '  BYID="/dev/disk/by-id/scsi-0HC_Volume_$TYPED"' '  strings "$BYID"'
hk_insert_after m-hk-rd-byidluks-strings-static '  local BYID_LUKS="/dev/disk/by-id/scsi-0HC_Volume_$LUKSID"' '  strings "$BYID_LUKS"'
hk_insert_after m-hk-rd-mapper-name-strings-static '  local MAPPER_NAME="${MAPPER##*/}"' '  strings "$MAPPER"'
# 14. ORDER: the budget call moved from before the finds to after them (still one budget line, still the same set of lines)
hk_mutant m-hk-budget-after-finds set_hk_pronly caught_budget_first '      budget
      ht=' '      ht=' \
  '      HK_PR_F=0
      if [ -n "$pr" ]; then' '      budget
      HK_PR_F=0
      if [ -n "$pr" ]; then'
# 15. pre-receive must be a regular file DIRECTLY inside hooks: by BEHAVIOUR (a world), not only by the argv pin
hk_mutant m-hk-pr-nodepth set_hk_nested caught_hk_pr_nonfile '-maxdepth 1 -name "$WA_HK_PR"' '-name "$WA_HK_PR"'
hk_mutant m-hk-pr-nontype-dir set_hk_prdir caught_hk_pr_nonfile '-type f \( -size' '! -type l \( -size'
hk_mutant m-hk-pr-nontype-fifo set_hk_prfifo caught_hk_pr_nonfile '-type f \( -size' '! -type l \( -size'
# 16. no die or say argument carries a command substitution (a size, uid or mode read from the tree on a fixed-word line)
hk_mutant m-hk-die-arg-substitution set_hk_pronly caught_die_args_plain '    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing' '    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing "sz=$(printf 1)"'
# 17. the emit channel: a second rc=34-prefixed line before the real one (the whole-line and last-line checks alone pass it; the one-line check and
# the site count each see it), and a further write to the original stderr (only the count sees it)
hk_mutant m-hk-second-say set_hooksdir caught_hooksdir '      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D' '      say "wipe-assert: rc=34 reason=offlist_x sz=$OFFLIST_N"
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D'
hk_mutant m-hk-second-say-pinned set_hooksdir caught_emit_pinned '      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D' '      say "wipe-assert: rc=34 reason=offlist_x sz=$OFFLIST_N"
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D'
hk_mutant m-hk-extra-fd3-write set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  say2() { printf '%s\\n' \"\$*\" >&3; }"
# the emit-site count is OCCURRENCES, and every spelling of a write to an original descriptor is counted: a second say on a line that
# already holds one (the die body; the teardown line's exit), a write to fd 4 spelled with a blank, by /dev/fd and by a variable
hk_mutant m-hk-emit-say-on-die-line set_hooksdir caught_emit_pinned 'shift; say "wipe-assert: rc=$rc reason=$*"; exit "$rc"; }' 'shift; say "wipe-assert: rc=$rc reason=$*"; say "wipe-assert: rc=34 reason=offlist_x sz=$OFFLIST_N"; exit "$rc"; }'
hk_mutant m-hk-emit-say-replaces-exit set_hooksdir caught_emit_pinned 'exit 36; }' 'say "wipe-assert: rc=36 reason=teardown_failed sz=9"; exit 36; }'
hk_mutant m-hk-emit-fd4-blank set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  printf x >& 4"
hk_mutant m-hk-emit-dev-fd4 set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  printf x >/dev/fd/4"
hk_mutant m-hk-emit-fd-variable set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  printf x >&\"\$X4\""
# spellings the per-fd patterns and the single-space say pattern did not match: a zero-padded descriptor (`>&03` is fd 3), a say whose
# argument is separated by ${IFS} (word-splits to a call), and a say with no argument followed by `;`
hk_mutant m-hk-emit-fd3-padded set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  printf x >&03"
hk_mutant m-hk-emit-say-ifs set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }"$'\n''  say${IFS}"x"'
hk_mutant m-hk-emit-say-semicolon set_hooksdir caught_emit_pinned "  say() { printf '%s\\n' \"\$*\" >&3; }" "  say() { printf '%s\\n' \"\$*\" >&3; }
  say;"
echo "    ($MUT_ROWS mutation rows run)"

# Harness rows (the mutation machinery itself is not neutered)
world h1
set_offdir
if ! mutate_script h1-neutral 'readonly WA_SETTLE_TRIES=20' 'readonly WA_SETTLE_TRIES=20'; then ok "H1: a neutral edit is reported as 'did not land' (mutation landing is checked, not assumed)"
else no "H1: a neutral edit was treated as a mutation"; fi
# The failure counter really moves: a refusal row driven against a clean host must FAIL.
world h2
run_script pre
_pf=$fail; _pp=$pass
expect_refuse "H2-probe (EXPECTED TO FAIL: a clean host does not refuse)" 34 offlist >/dev/null
if [ "$fail" -gt "$_pf" ]; then ok "H2: a refusal row against a clean host goes RED (the assertion machinery can fail)"; fail=$_pf; pass=$_pp; executed=$((executed - 4))
else no "H2: a refusal row against a clean host stayed green"; fi

# The one-rc=34-line rule of expect_refuse is not neutered: a script that prints a SECOND rc=34-prefixed line before the real one (the last line
# is still the expected one and still the strict shape) must make expect_refuse FAIL, and the real script must pass. The probe's counters
# are restored (it must not move a floor).
if mutate_script h8-second-say '      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D' '      say "wipe-assert: rc=34 reason=offlist_x sz=$OFFLIST_N"
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D'; then
  world h8; set_hooksdir
  RUN_SCRIPT="$MUTANT" run_script pre; RUN_SCRIPT=""
  _pf=$fail; _pp=$pass; _pe=$executed; _pr=$RC34_LINES_CHECKED; _pg=$HK_GROUP_LINES_CHECKED; _pi=$INVARIANT_RUNS; _pn=$NAMES_SEEN_RUNS
  expect_refuse "H8-probe (EXPECTED TO FAIL: two rc=34 lines)" 34 offlist "$HK_HEAD hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0" >/dev/null
  _h8_failed=$((fail - _pf))
  fail=$_pf; pass=$_pp; executed=$_pe; RC34_LINES_CHECKED=$_pr; HK_GROUP_LINES_CHECKED=$_pg; INVARIANT_RUNS=$_pi; NAMES_SEEN_RUNS=$_pn
  world h8b; set_hooksdir; run_script pre
  if [ "$_h8_failed" = 1 ] && rc34_once; then ok "H8: a second rc=34-prefixed stderr line makes expect_refuse fail (exactly the one-line check), and the real script prints exactly one"
  else no "H8: expect_refuse accepted two rc=34 lines ($_h8_failed failing checks), or the real script printed other than one"; fi
else no "H8: the second-say mutation did not land"; fi

# The strict-line helpers themselves are not neutered (a loosened regex or a dropped predicate goes RED here).
_g34='wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=0 lf_entries=7 offlist_n=0'
if line34_ok "$_g34"; then ok "H3: a non-canonical good rc=34 line (lf_entries=7 offlist_n=0) is accepted"; else no "H3: a good rc=34 line was rejected"; fi
if ! line34_ok "${_g34/has_hooks_d=0/has_hooks_d=2}"; then ok "H3: has_hooks_d=2 is rejected (the bit is 0 or 1)"; else no "H3: has_hooks_d=2 was accepted"; fi
if ! line34_ok "$_g34 digest=0f0f"; then ok "H3: a trailing token is rejected"; else no "H3: a trailing token was accepted"; fi
if ! line34_ok "${_g34/lf_entries=7/lf_entries=0}"; then ok "H3: offlist_n=0 with lf_entries=0 is rejected (nothing explains the refusal)"; else no "H3: an unexplained rc=34 line was accepted"; fi
if ! line34_ok "${_g34/offlist_n=0/offlist_n=9}"; then ok "H3: offlist_n above the top-level entry count is rejected"; else no "H3: an impossible offlist_n was accepted"; fi
# the hk_ group: strict emit check (line34_ok) and posting grammar (line34_grammar_ok)
_h8='wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1'   # the run-39136900735 line
_hg='hk_entries=7 hk_nonfile=2 hk_pr_f=0 hk_pr_small=0'                                                                  # non-canonical good group
if line34_ok "$_h8 $_hg"; then ok "H3: a non-canonical good group (hk_entries=7 hk_nonfile=2) is accepted by the strict check"; else no "H3: a good group was rejected by the strict check"; fi
if line34_ok "$_h8 hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1"; then ok "H3: the single pre-receive shape is accepted by the strict check"; else no "H3: the pre-receive shape was rejected"; fi
if ! line34_ok "$_h8"; then ok "H3: has_hooks_d=1 WITHOUT the group is rejected by the strict emit check (the new script never prints it)"; else no "H3: a has_hooks_d=1 line without the group passed the strict check"; fi
if ! line34_ok "$_g34 $_hg"; then ok "H3: the group with has_hooks_d=0 is rejected"; else no "H3: a group with has_hooks_d=0 was accepted"; fi
if ! line34_ok "${_h8/offlist_n=1/offlist_n=0} $_hg"; then ok "H3: has_hooks_d=1 with offlist_n=0 is rejected (the bit implies an off-list entry), group present"; else no "H3: a hooks bit without an off-list entry was accepted"; fi
_k=0
for _p in "hk_entries=7" "hk_entries=7 hk_nonfile=2" "hk_entries=7 hk_nonfile=2 hk_pr_f=0"; do
  _k=$((_k + 1))
  if ! line34_ok "$_h8 $_p" && ! line34_grammar_ok "$_h8 $_p"; then ok "H3: a partial group (truncation point $_k) is rejected by both checks"; else no "H3: a partial group (truncation point $_k) was accepted"; fi
done
if ! line34_ok "$_h8 hk_nonfile=2 hk_entries=7 hk_pr_f=0 hk_pr_small=0"; then ok "H3: a swapped field order is rejected"; else no "H3: a swapped order was accepted"; fi
if ! line34_ok "$_h8 hk_entries=1 hk_nonfile=2 hk_pr_f=0 hk_pr_small=0"; then ok "H3: hk_nonfile above hk_entries is rejected"; else no "H3: hk_nonfile > hk_entries was accepted"; fi
if ! line34_ok "$_h8 hk_entries=1 hk_nonfile=1 hk_pr_f=1 hk_pr_small=0"; then ok "H3: hk_entries=1 hk_nonfile=1 hk_pr_f=1 is rejected (entries >= nonfile + pr_f; the only row isolating it)"; else no "H3: entries < nonfile + pr_f was accepted"; fi
if ! line34_ok "$_h8 hk_entries=2 hk_nonfile=0 hk_pr_f=0 hk_pr_small=1"; then ok "H3: hk_pr_small=1 with hk_pr_f=0 is rejected"; else no "H3: small without f was accepted"; fi
if ! line34_ok "$_h8 hk_entries=2 hk_nonfile=0 hk_pr_f=2 hk_pr_small=0"; then ok "H3: hk_pr_f=2 is rejected (the bit is 0 or 1)"; else no "H3: hk_pr_f=2 was accepted"; fi
if ! line34_ok "$_h8 $_hg hk_extra=1"; then ok "H3: a fifth token after the group is rejected"; else no "H3: a fifth token was accepted"; fi
if line34_grammar_ok "$_h8"; then ok "H3: the posting grammar accepts the already-printed eight-field line with has_hooks_d=1 (run 39136900735 stays valid)"; else no "H3: the printed eight-field line was rejected by the posting grammar"; fi
if line34_grammar_ok "$_h8 $_hg" && line34_grammar_ok "$_g34"; then ok "H3: the posting grammar accepts a non-canonical good group and a has_hooks_d=0 line"; else no "H3: the posting grammar rejected a good line"; fi
if ! line34_grammar_ok "$_g34 $_hg" && ! line34_grammar_ok "$_h8 $_hg digest=0f0f" && ! line34_grammar_ok "${_h8/offlist_n=1/offlist_n=0}"; then ok "H3: the posting grammar rejects a group with has_hooks_d=0, an extra token and an unexplained has_hooks_d=1 line"; else no "H3: the posting grammar accepted a bad line"; fi
# the closed-set helper is exact (a sequence compare): a duplicated line and a dropped line are both refused, the real block is accepted
if mutate_script h4-dup '      budget
      ht=' '      budget
      budget
      ht=' && ! hk_block_closed "$MUTANT" && hk_block_closed "$SCRIPT"; then ok "H4: a duplicated block line is refused by the closed-set check (the real block is accepted)"
else no "H4: the closed-set check accepted a duplicated block line, or refused the real block"; fi
if mutate_script h4-drop '      HK_PR_SMALL=0
' '' && ! hk_block_closed "$MUTANT"; then ok "H4: a dropped block line is refused by the closed-set check"
else no "H4: the closed-set check accepted a block with a line missing"; fi
# grep_none: only an exit 1 is an absence; a match and a grep error are both "not clean"
_gn_f="$T/grep-none.txt"; printf 'alpha\n' > "$_gn_f"
if grep_none -F beta "$_gn_f" && ! grep_none -F alpha "$_gn_f" && ! grep_none -F alpha "$T/no-such-file"; then ok "H5: grep_none is true only on exit 1 (a match and an unreadable file are both refused)"
else no "H5: grep_none accepts a match or a grep error as an absence"; fi
# the closed-set helpers are exact: a REORDER of the block fails (hk_block_closed is a sequence compare), and a reviewed outside line
# dropped and masked by a duplicate of another fails (hk_outside_closed is a multiset compare); the failure names the first differing line
_nf_l="$(sed -n '/^      nf=/p' "$HK_ALLOWED")"; _al_l="$(sed -n '/^      al=/p' "$HK_ALLOWED")"
if [ -n "$_nf_l" ] && [ -n "$_al_l" ] && mutate_script h4-swap "$_nf_l"$'\n'"$_al_l" "$_al_l"$'\n'"$_nf_l" && ! hk_block_closed "$MUTANT" && hk_block_closed "$SCRIPT"; then ok "H4: two block lines swapped (nf= and al=) are refused by the closed-set check (a sequence compare, not a sort)"
else no "H4: the closed-set check accepted a reordered block, or refused the real block"; fi
if mutate_script h4-outside-dupdrop '    mkdir -- "$WA_MNT" || die 33 mkdir_failed
' '    mkdir -- "$WA_MNT" || die 33 mkdir_failed
    mkdir -- "$WA_MNT" || die 33 mkdir_failed
' '      [[ "$tgt" =~ ^(/dev/shm/tmp\.[A-Za-z0-9]{6,12})/mnt$ ]] || die 43 snapshot_not_ours
' '' && ! hk_outside_closed "$MUTANT" && [ -n "$HK_FIRST_BAD" ] && hk_outside_closed "$SCRIPT"; then ok "H4: an outside line duplicated while a reviewed guard line is dropped (same count, every line reviewed) is refused by the outside check, which names the first difference (the real script is accepted)"
else no "H4: the outside check accepted a duplicate-and-drop, or named no line, or refused the real script"; fi
# hk_no_file_redirect: the allowed redirections are not flagged; EVERY other `<` that is shaped like a redirect is, wherever it sits (inside
# [[ ]], (( )), an awk program or between quoted brackets: nothing is blanked, a comparison is written -lt); a final line with no
# trailing newline is read; and an unreadable file is a failure, never a clean pass
_rd="$T/redir-probe.sh"
_k=0
for _l in '  cat < /dev/null' '  cat </dev/null' '  read -r a <<< "$x"' '  wl_classify < <(find . -print)' '  x=$(( a << 2 ))' '  cat <&3' '  true && cat <&3' "  awk 'NR == 3' \"\$f\""; do
  _k=$((_k + 1)); printf '%s\n' "$_l" > "$_rd"
  if hk_no_file_redirect "$_rd"; then ok "H6: an allowed redirection or a form with no redirect is not flagged (case $_k)"; else no "H6: an allowed form was flagged (case $_k): [$_l]"; fi
done
_k=0
for _l in '  read -r x < "$f"' '  exec 5<"$f"' '  (<"$f" wc -c)' '  ( <"$f" wc -c)' '  x=$(<"$f")' '  x=$(( $(<"$f") + 1 ))' '  [[ -n "$(cat <"$f")" ]]' '  (( n++ )); read -r x < "$f"' '  [[ a < b ]] && read -r x < "$f"' "  awk 'NR < 3' < \"\$f\"" \
  '  [[ "$a" < "$b" ]]' "  awk 'NR < 3' \"\$f\"" '  x=$((a < b))' '  (( a < b )) && echo y' \
  "  awk 'BEGIN{ getline x < f }'" "  x=\"\$(awk -v p=\"\$f\" 'BEGIN{ getline x < p; print length(x) }')\"" "  awk -f p.awk x && read -r v < \"\$f\" || die 33 x" "  awk -F: < \"\$f\" '{print \$1}'" \
  '  echo "[["; read -r v < "$f"; echo "]]"' '  echo "(("; read -r v < "$f"; echo "))"' \
  '  true &&<"$f" cat' '  x=$(true &&<"$f" cat)' '  true &&< "$f" cat'; do
  _k=$((_k + 1)); printf '%s\n' "$_l" > "$_rd"
  if ! hk_no_file_redirect "$_rd" && [ "$HK_FIRST_BAD" = "$_l" ]; then ok "H6: a file read by redirection or builtin is flagged and the line is named (case $_k)"; else no "H6: a file read was not flagged, or the line was not named (case $_k): [$_l]"; fi
done
# the last line with no trailing newline is read, and the line count read equals the line count of the file
printf 'echo hi\n  read -r v < "$f"' > "$_rd"
if ! hk_no_file_redirect "$_rd" && [ "$HK_FIRST_BAD" = '  read -r v < "$f"' ]; then ok "H6: a read on a final line with no trailing newline is flagged and the line is named"; else no "H6: a final line with no trailing newline was not read ([$HK_FIRST_BAD])"; fi
printf 'echo hi\n  true' > "$_rd"
if hk_no_file_redirect "$_rd"; then ok "H6: a clean file whose last line has no trailing newline is accepted (the line count matches)"; else no "H6: a clean file with no trailing newline was refused ([$HK_FIRST_BAD])"; fi
# a read loop that ends before the end of the file is a failure, not a clean pass (the loop is made to stop after its first line by a
# `read` that reports end-of-input from the second call on, in a subshell so nothing leaks)
printf 'echo one\necho two\necho three\n' > "$_rd"
if hk_no_file_redirect "$_rd" && ( _rn=0; read() { local _r=0; builtin read "$@" || _r=$?; _rn=$((_rn + 1)); if [ "$_rn" -ge 2 ]; then printf -v "${!#}" ''; return 1; fi; return "$_r"; }; ! hk_no_file_redirect "$_rd" && [ -n "$HK_FIRST_BAD" ] ); then ok "H6: a read loop that stops before the end of the file is refused (the lines read must equal the lines in the file)"
else no "H6: a read loop that stopped early read as clean"; fi
if ! hk_no_file_redirect "$T/no-such-file-probe"; then ok "H6: an unreadable file is a failure of the redirect rule, never a clean pass"; else no "H6: the redirect rule passed an unreadable file"; fi
# the run bound itself: a script that would run for 8 s is cut at the 2 s bound and the run reads rc 124 (without the bound it would end rc 0)
world h6
printf 'while [ "$SECONDS" -lt 8 ]; do :; done\n' > "$T/hang.sh"
WA_TEST_RUN_TIMEOUT=2 RUN_SCRIPT="$T/hang.sh" run_script pre
RUN_SCRIPT=""
if [ "$RC" = 124 ]; then ok "H6: a hung run returns rc 124 through the run_script timeout (a blocked read reads as RED, not as a stall)"; else no "H6: the run_script timeout did not bound a long run (rc=$RC)"; fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# TIER B — the cutover verb
# ══════════════════════════════════════════════════════════════════════════════════════════
echo "--- TIER B: git-data-cutover.sh MODE=wipe_assert"
SB="$T/sshshim"; assert_fixture_dir "$SB"; mkdir -p "$SB" || instrument "mkdir sshshim failed"
cat > "$SB/ssh" <<'SSHSHIM'
#!/usr/bin/env bash
last="${*: -1}"
printf 'ssh\n' >> "$TL/calls"
case " $* " in *" -W "*) echo "SSH-2.0-OpenSSH_9.6"; exit 0 ;; esac
[ "$last" = true ] && exit 0
printf '%s\n' "$last" > "$TL/cmd"
cat > "$TL/stdin"
[ -f "$TL/hang" ] && sleep 20
[ -f "$TL/answer" ] && cat "$TL/answer"
[ -z "${SHIM_ERR:-}" ] || printf '%s\n' "$SHIM_ERR" >&2
exit "$(cat "$TL/rc")"
SSHSHIM
cat > "$SB/timeout" <<'TOSHIM'
#!/usr/bin/env bash
SD="${0%/*}"
# the REAL timeout, found without the shim directory; the child keeps the shim PATH (so it finds the ssh shim)
REAL="$(PATH="${PATH#"$SD":}" command -v timeout)"
printf '%s\n' "$1" >> "$TL/timeouts"
if [ -f "$TL/hang" ] && [ "$1" != 25 ] && [ "$1" != 30 ]; then shift; exec "$REAL" 2 "$@"; fi
exec "$REAL" "$@"
TOSHIM
chmod +x "$SB/ssh" "$SB/timeout" || instrument "chmod sshshim failed"

VRC=0
# run_verb <label> <answer-line|-> <rc> [VAR=value …]
run_verb() {
  local label="$1" answer="$2" rc="$3"; shift 3
  TL="$T/tl-$label"; assert_fixture_dir "$TL"; mkdir -p "$TL" || instrument "mkdir $TL failed"
  : > "$TL/calls"; : > "$TL/timeouts"; printf '%s' "$rc" > "$TL/rc"
  if [ "$answer" != "-" ]; then printf '%s\n' "$answer" > "$TL/answer"; fi
  : > "$TL/gh_output"; : > "$TL/gh_summary"
  VRC=0
  env -i PATH="$SB:/usr/bin:/bin" HOME="$T" TL="$TL" MODE=wipe_assert \
    GIT_DATA_SSH="ssh -F /dev/null" WEB_HOST_SSH="ssh -F /dev/null" \
    GITHUB_OUTPUT="$TL/gh_output" GITHUB_STEP_SUMMARY="$TL/gh_summary" \
    "$@" bash "$CUTOVER" > "$TL/out" 2> "$TL/err" || VRC=$?
}
PRE_ANS='wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0'
V_PRE=(WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run)
V_POST=(WIPE_PHASE=post_detach WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S")
has_store() { grep -qxF "[git-data-cutover] STORE probe=wipe-assert verdict=$1" "$TL/out"; }
no_remote_call() { [ "$(wc -l < "$TL/calls")" = 0 ]; }

run_verb b01 "$PRE_ANS" 0 "${V_PRE[@]}"
if [ "$VRC" = 0 ] && grep -qxF "[git-data-cutover] WIPE_ASSERT pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0" "$TL/out" && has_store ok; then
  ok "B01 pre with the listing: exit 0, the fixed-shape line is logged (counts only)"
else no "B01 pre did not pass: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)]"; fi
if grep -qxF "wipe_assert=$PRE_ANS" "$TL/gh_output" && grep -qxF -- "- WIPE_ASSERT pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200 lock_residue=0 store_root_repos=0" "$TL/gh_summary"; then
  ok "B01 the line is written to GITHUB_OUTPUT and the step summary, verbatim"
else no "B01 output/summary missing the line"; fi
if cmp -s "$SCRIPT" "$TL/stdin"; then ok "B02 the host script is sent on STDIN, byte for byte (the single ssh site, gd_capture)"
else no "B02 the stdin of the remote call is not the host script"; fi
CMD="$(cat "$TL/cmd")"
EXPECT_CMD="WIPE_PHASE=pre WIPE_TYPED_ID=$ID_T WIPE_LUKS_ID=$ID_L WIPE_SERVER_ID=$ID_S WIPE_OLD_ROOT=/mnt/git-data WIPE_LUKS_MAPPER=/dev/mapper/git-data WIPE_STORE_VERIFIED=/etc/git-data/store-verified WIPE_ROW_DT=$ROWDT WIPE_LISTING=run bash -s"
if [ "$CMD" = "$EXPECT_CMD" ]; then ok "B03 the remote command is exactly the %q-quoted inputs in front of 'bash -s' (nothing else is sent)"
else no "B03 remote command differs: [$CMD]"; fi
if [ "$(paste -sd' ' "$TL/timeouts")" = "30 25 30 300" ]; then ok "B04 bounds: access gate 30/25/30, the listing session 300 s"
else no "B04 bounds differ: [$(paste -sd' ' "$TL/timeouts")]"; fi

# rc 34: the host's last stderr line is relayed by the verb as one probe-stderr line, whole (this row guards the
# passthrough filter in the verb, not the host script; the line is far below the 8192-byte cap, so it does not guard that).
L34='wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1 hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1'
run_verb b34 - 34 "${V_PRE[@]}" SHIM_ERR="$L34"
if grep -qxF "[git-data-cutover] probe-stderr: $L34" "$TL/out"; then ok "B04b the rc=34 diagnostic line survives the verb's stderr filter whole, behind one probe-stderr prefix"
else no "B04b the rc=34 line did not pass through the verb: $(tr '\n' '|' < "$TL/out" | cut -c1-300)"; fi

run_verb b05 "$PRE_ANS" 0 "${V_PRE[@]/WIPE_LISTING=run/WIPE_LISTING=skip}"
if [ "$VRC" = 0 ] && [ "$(paste -sd' ' "$TL/timeouts")" = "30 25 30 90" ] && grep -q 'WIPE_LISTING=skip bash -s' "$TL/cmd"; then ok "B05 pre with WIPE_LISTING=skip (wipe_check): 90 s bound, skip is what is sent"
else no "B05 skip arm: rc=$VRC timeouts=[$(paste -sd' ' "$TL/timeouts")]"; fi

POST_ANS='wipe_assert post_detach ok byid=gone mapper_read=ok store_root=ok'
run_verb b06 "$POST_ANS" 0 "${V_POST[@]}"
if [ "$VRC" = 0 ] && grep -qxF "[git-data-cutover] WIPE_ASSERT post_detach ok byid=gone mapper_read=ok store_root=ok" "$TL/out" && [ "$(paste -sd' ' "$TL/timeouts")" = "30 25 30 90" ] && ! grep -q 'WIPE_ROW_DT\|WIPE_LISTING' "$TL/cmd"; then
  ok "B06 post_detach: exit 0, 90 s, no pre-only input is sent"
else no "B06 post_detach: rc=$VRC"; fi
run_verb b07 "wipe_assert finish ok byid=gone mapper_read=ok store_root=ok" 0 "${V_POST[@]/post_detach/finish}"
if [ "$VRC" = 0 ]; then ok "B07 finish: exit 0"; else no "B07 finish: rc=$VRC"; fi

# A1 (2026-10-15) phase=clear through the cutover verb: its own fixed answer shape, a 240 s bound (the host's own budget), no pre-only input
V_CLEAR=(WIPE_PHASE=clear WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S")
run_verb b20 "wipe_assert clear ok snapshot=cleared" 0 "${V_CLEAR[@]}"
if [ "$VRC" = 0 ] && grep -qxF "[git-data-cutover] WIPE_ASSERT clear ok snapshot=cleared" "$TL/out" && has_store ok && [ "$(paste -sd' ' "$TL/timeouts" | awk '{print $NF}')" = 240 ] && ! grep -q 'WIPE_ROW_DT\|WIPE_LISTING' "$TL/cmd" \
   && grep -qxF "wipe_assert=wipe_assert clear ok snapshot=cleared" "$TL/gh_output"; then
  ok "B20 clear: exit 0, 240 s, the answer is logged and written to GITHUB_OUTPUT verbatim, no pre-only input is sent"
else no "B20 clear: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-200)]"; fi
run_verb b21 "wipe_assert clear ok snapshot=absent" 0 "${V_CLEAR[@]}"
if [ "$VRC" = 0 ] && grep -qxF "[git-data-cutover] WIPE_ASSERT clear ok snapshot=absent" "$TL/out"; then ok "B21 clear with no leftover: exit 0, snapshot=absent"; else no "B21 clear absent: rc=$VRC"; fi
run_verb b22 "wipe_assert clear ok snapshot=wiped" 0 "${V_CLEAR[@]}"
if [ "$VRC" != 0 ] && ! grep -q "WIPE_ASSERT clear" "$TL/out"; then ok "B22 an answer outside the two fixed clear words is never accepted"; else no "B22 clear accepted an off-shape answer: rc=$VRC"; fi
run_verb b23 "wipe_assert pre ok layout_signal=ok" 0 "${V_CLEAR[@]}"
if [ "$VRC" != 0 ] && ! grep -q "WIPE_ASSERT" "$TL/out"; then ok "B23 a pre-shaped answer cannot satisfy a clear call"; else no "B23 a pre answer satisfied a clear call: rc=$VRC"; fi
run_verb b24 - 43 "${V_CLEAR[@]}"
if [ "$VRC" = 5 ] && has_store wipe_snapshot_not_ours; then ok "B24 clear: script rc 43 -> exit 5, verdict=wipe_snapshot_not_ours"; else no "B24 clear rc 43: rc=$VRC"; fi
run_verb b25 "wipe_assert clear ok snapshot=cleared" 0 "${V_CLEAR[@]}" WIPE_LISTING=run
if [ "$VRC" != 0 ] && grep -q "arg_pre_only" "$TL/out"; then ok "B25 clear refuses a listing mode input (arg_pre_only): the pre-only inputs are not accepted"; else no "B25 clear accepted WIPE_LISTING: rc=$VRC"; fi

# row dt as the ISO form the Better Stack row carries
run_verb b08 "$PRE_ANS" 0 "${V_PRE[@]/WIPE_ROW_DT=$ROWDT/WIPE_ROW_DT=2026-10-11 12:51:03}"
_iso_epoch="$(date -u -d '2026-10-11 12:51:03' +%s)"
if [ "$VRC" = 0 ] && grep -q "WIPE_ROW_DT=$_iso_epoch " "$TL/cmd"; then ok "B08 an ISO 'YYYY-MM-DD HH:MM:SS' row dt is converted to epoch seconds before it is sent"
else no "B08 iso row dt: rc=$VRC cmd=[$(cut -c1-200 "$TL/cmd")]"; fi

# every rc of the script -> its fixed verdict word
echo "--- rc -> verdict word"
declare -A WORD=(
  [11]=store_not_on_mapper [12]=cutover_frozen [20]=wipe_device_absent [21]=wipe_device_not_block
  [22]=wipe_device_is_luks_backing [23]=wipe_device_luks_or_unknown [24]=wipe_device_mounted
  [25]=wipe_device_has_holders [26]=wipe_snapshot_present [27]=wipe_device_open [28]=wipe_device_active
  [29]=wipe_device_written [30]=wipe_ro_flag_lost [31]=wipe_instance_mismatch [32]=wipe_boot_generation_mismatch
  [33]=wipe_boot_layout_signal_absent [34]=wipe_boot_layout_signal_offlist [35]=wipe_boot_layout_signal_unparseable
  [36]=wipe_snapshot_teardown_failed [37]=wipe_plaintext_not_empty [38]=wipe_luks_identity_mismatch
  [40]=wipe_device_still_attached [41]=wipe_mapper_read_failed [42]=wipe_store_root_unreadable
  [43]=wipe_snapshot_not_ours
)
for rc in "${!WORD[@]}"; do
  run_verb "r$rc" - "$rc" "${V_PRE[@]}"
  if [ "$VRC" = 5 ] && has_store "${WORD[$rc]}"; then ok "RC $rc -> exit 5, verdict=${WORD[$rc]}"
  else no "RC $rc: expected verdict=${WORD[$rc]}; rc=$VRC out=[$(grep STORE "$TL/out" | tr '\n' '|' | cut -c1-200)]"; fi
done
for pair in "13:no_fs_uuid" "14:marker_absent" "15:marker_mismatch"; do
  rc="${pair%%:*}"; rs="${pair#*:}"
  run_verb "r$rc" - "$rc" "${V_PRE[@]}"
  if [ "$VRC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=wipe-assert verdict=store_unverified reason=$rs" "$TL/out"; then ok "RC $rc -> exit 5, store_unverified reason=$rs"
  else no "RC $rc: expected store_unverified reason=$rs; rc=$VRC"; fi
done
for rc in 16 124 141 255 7 97; do
  run_verb "t$rc" - "$rc" "${V_PRE[@]}"
  if [ "$VRC" = 5 ] && has_store "probe_failed rc=$rc"; then ok "RC $rc (instrument or transport) -> probe_failed rc=$rc, never a host verdict"
  else no "RC $rc: expected probe_failed rc=$rc; rc=$VRC out=[$(grep STORE "$TL/out" | tr '\n' '|' | cut -c1-200)]"; fi
done
# a timeout: the session hangs, gd_capture's bound cuts it
run_verb b20 - 0 "${V_PRE[@]}"
: > "$TL/hang"
VRC=0
env -i PATH="$SB:/usr/bin:/bin" HOME="$T" TL="$TL" MODE=wipe_assert GIT_DATA_SSH="ssh -F /dev/null" WEB_HOST_SSH="ssh -F /dev/null" \
  "${V_PRE[@]}" bash "$CUTOVER" > "$TL/out" 2> "$TL/err" || VRC=$?
if [ "$VRC" = 5 ] && has_store "probe_failed rc=124"; then ok "B20 a hung session is cut by the explicit bound -> probe_failed rc=124 (a tested fail-closed word)"
else no "B20 timeout: rc=$VRC out=[$(grep STORE "$TL/out" | tr '\n' '|' | cut -c1-200)]"; fi

# off-shape answers are refused, never accepted
run_verb b21 "$PRE_ANS digest=0f0f" 0 "${V_PRE[@]}"
if [ "$VRC" = 5 ] && has_store "probe_failed rc=96"; then ok "B21 an answer with an extra token (a digest) is refused: probe_failed rc=96"
else no "B21 off-shape answer accepted: rc=$VRC"; fi
run_verb b22 "$POST_ANS" 0 "${V_PRE[@]}"
if [ "$VRC" = 5 ] && has_store "probe_failed rc=96"; then ok "B22 a post_detach answer cannot satisfy a pre call"
else no "B22 phase confusion accepted: rc=$VRC"; fi
run_verb b23 "wipe_assert finish ok byid=gone mapper_read=ok store_root=ok" 0 "${V_POST[@]}"
if [ "$VRC" = 5 ] && has_store "probe_failed rc=96"; then ok "B23 a finish answer cannot satisfy a post_detach call"
else no "B23 phase confusion accepted: rc=$VRC"; fi
run_verb b24 "$PRE_ANS
wipe_assert pre ok layout_signal=not_run" 0 "${V_PRE[@]}"
if [ "$VRC" = 5 ] && has_store "probe_failed rc=96"; then ok "B24 a multi-line answer is refused"; else no "B24 multi-line answer accepted: rc=$VRC"; fi

# arguments: refused BEFORE any remote call
echo "--- argument refusals (no remote call is made)"
refuse_args() { # <label> <expected-reason-or-verdict> <VAR=value …>
  local label="$1" want="$2"; shift 2
  run_verb "$label" "$PRE_ANS" 0 "$@"
  if [ "$VRC" = 5 ] && no_remote_call && grep -qF "$want" "$TL/out"; then ok "$label -> exit 5 ($want), no ssh call at all"
  else no "$label: rc=$VRC calls=$(wc -l < "$TL/calls") out=[$(grep STORE "$TL/out" | tr '\n' '|' | cut -c1-200)]"; fi
}
refuse_args b30 "reason=arg_phase" WIPE_PHASE=bogus WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S"
refuse_args b31 "reason=arg_volume_id" WIPE_PHASE=pre "WIPE_VOLUME_ID=12;id" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run
refuse_args b32 "reason=arg_luks_volume_id" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID= WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run
refuse_args b33 "reason=arg_server_id" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID=0x1 WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run
refuse_args b34 "verdict=wipe_target_is_luks" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_T" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run
refuse_args b35 "reason=arg_row_dt" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_LISTING=run
refuse_args b36 "reason=arg_listing" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT"
refuse_args b37 "reason=arg_listing" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=maybe
refuse_args b38 "reason=arg_pre_only" WIPE_PHASE=post_detach WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_LISTING=run
refuse_args b39 "reason=arg_pre_only" WIPE_PHASE=finish WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT"
refuse_args b40 "reason=arg_row_dt" WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" "WIPE_ROW_DT=yesterday" WIPE_LISTING=run

# a bad OLD_ROOT is refused by the shared config check before the host is dialed
run_verb b41 "$PRE_ANS" 0 "${V_PRE[@]}" 'OLD_ROOT=/mnt/x;touch /y'
if [ "$VRC" = 5 ] && no_remote_call && grep -qF 'reason=arg_root' "$TL/out"; then ok "B41 an unsafe OLD_ROOT is refused before any remote call (the shared config check)"
else no "B41 unsafe OLD_ROOT: rc=$VRC calls=$(wc -l < "$TL/calls")"; fi
# an unknown mode is still refused (the closed MODE list grew by exactly one)
run_verb b42 - 0 "${V_PRE[@]}" MODE=wipe
if [ "$VRC" = 5 ] && grep -qF 'verdict=mode_invalid' "$TL/out" && no_remote_call; then ok "B42 MODE=wipe is still mode_invalid (only wipe_assert joined the closed list)"
else no "B42 MODE=wipe: rc=$VRC"; fi

# ── parity: the rc table of the script header == the die calls == the verb's case arms ────────────
echo "--- parity rows"
python3 - "$SCRIPT" "$CUTOVER" > "$T/parity.out" 2> "$T/parity.err" <<'PY'
import re, sys
script = open(sys.argv[1]).read()
cut = open(sys.argv[2]).read()
hdr = script.split("# EXIT CODES", 1)[1].split("# Keep the table", 1)[0]
hdr_codes = set(int(m) for m in re.findall(r"(?<![0-9])([1-4][0-9])(?= [a-z])", hdr))
die_codes = set(int(m) for m in re.findall(r"\bdie ([0-9]+) ", script))
die_codes |= set(int(m) for m in re.findall(r"rc=([0-9]+) reason=", script) if m.isdigit())
fn = cut.split("mode_wipe_assert() {", 1)[1].split("\n}\n", 1)[0]
arms = set(int(m) for m in re.findall(r"^\s+([0-9]+)\) _wipe_refuse", fn, re.M))
words_cut = set(re.findall(r"_wipe_refuse (wipe_[a-z_]+|store_not_on_mapper|cutover_frozen)", fn))
words_hdr = set(re.findall(r"\b(wipe_[a-z_]+|store_not_on_mapper|cutover_frozen)\b", hdr))
print("hdr", sorted(hdr_codes))
print("die", sorted(die_codes))
print("arms", sorted(arms))
print("HDR_EQ_DIE", hdr_codes == die_codes)
print("ARMS_EQ_DIE_MINUS_16", arms == (die_codes - {16}))
print("WORDS_IN_HDR", words_cut <= words_hdr, sorted(words_cut - words_hdr))
print("NARMS", len(arms), "NWORDS", len(words_cut))
PY
if [ "$(sed -n 's/^HDR_EQ_DIE //p' "$T/parity.out")" = True ]; then ok "P1 every exit code in the script header table is a 'die' in the script, and the reverse"
else no "P1 header table and die calls differ: $(tr '\n' '|' < "$T/parity.out") $(cat "$T/parity.err")"; fi
if [ "$(sed -n 's/^ARMS_EQ_DIE_MINUS_16 //p' "$T/parity.out")" = True ]; then ok "P2 the verb maps exactly the script's codes (16 is probe_failed by default)"
else no "P2 verb arms differ from the script's codes: $(tr '\n' '|' < "$T/parity.out")"; fi
if [ "$(sed -n 's/^WORDS_IN_HDR //p' "$T/parity.out" | cut -d' ' -f1)" = True ]; then ok "P3 every wipe_* verdict word of the verb is in the script header table"
else no "P3 a verdict word is missing from the header: $(grep WORDS_IN_HDR "$T/parity.out")"; fi
_narms="$(sed -n 's/^NARMS \([0-9]*\) .*/\1/p' "$T/parity.out")"
if [ "${_narms:-0}" -ge 25 ]; then ok "P4 floor: the verb maps ${_narms} script codes (>= 25)"; else no "P4 floor: only ${_narms:-0} codes mapped"; fi
# every code the verb maps is exercised by a row above (WORD map + 13/14/15)
_covered=$(( ${#WORD[@]} + 3 ))
if [ "$_covered" = "$_narms" ]; then ok "P5 the rc -> word rows cover every arm of the verb ($_covered of $_narms)"
else no "P5 the verb has $_narms arms but $_covered rows"; fi
# no test seam (ADR-214): neither file reads an env name that exists only for a test
seams="$(grep -nE 'WIPE_ASSERT_(SEAM|TEST|ROOT|FAKE|SKIP)|_TEST_PIN' "$SCRIPT" "$CUTOVER" || true)"
if [ -z "$seams" ]; then ok "P6 no test seam in the host script or the verb (ADR-214)"; else no "P6 a seam exists: $seams"; fi
# the verb sends exactly these env names, nothing else (a hostile id cannot add one)
_names="$(sed -n '/^mode_wipe_assert()/,/^}/p' "$CUTOVER" | grep -oE 'WIPE_[A-Z_]+=\$' | sort -u | paste -sd' ' -)"
if [ "$_names" = "WIPE_LISTING=\$ WIPE_LUKS_ID=\$ WIPE_LUKS_MAPPER=\$ WIPE_OLD_ROOT=\$ WIPE_PHASE=\$ WIPE_ROW_DT=\$ WIPE_SERVER_ID=\$ WIPE_STORE_VERIFIED=\$ WIPE_TYPED_ID=\$" ]; then
  ok "P7 the verb sends exactly nine env words to the host"
else no "P7 the verb's env words differ: [$_names]"; fi

# ── hooks shape fields: static rows (the constants, their provenance, the block's shape) ─────────────────────────
echo "--- hooks shape rows"
HK_DIR_C="$(sed -n 's/^  readonly WA_HK_DIR=\([^ #]*\).*/\1/p' "$SCRIPT")"
HK_PR_C="$(sed -n 's/^  readonly WA_HK_PR=\([^ #]*\).*/\1/p' "$SCRIPT")"
HK_MAX_C="$(sed -n 's/^  readonly WA_HK_PR_MAX=\([0-9]*\).*/\1/p' "$SCRIPT")"
if [ "$(grep -cE '^  readonly WA_HK_(DIR|PR)=' "$SCRIPT")" = 2 ] && [ -n "$HK_DIR_C" ] && [ -n "$HK_PR_C" ]; then ok "HK1 exactly two probed names outside the allowlist arms, each a readonly constant ($HK_DIR_C as a directory at the top level, $HK_PR_C as a regular file directly inside it)"
else no "HK1 the probed names are not exactly two readonly constants"; fi
if [ "$(grep -cF 'if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi' "$SCRIPT")" = 1 ] && [ "$HK_DIR_C" = hooks ]; then ok "HK2 the hooks literal in wl_classify equals WA_HK_DIR (wl_classify is not edited; the constant is tied to it here)"
else no "HK2 the wl_classify literal and WA_HK_DIR differ (WA_HK_DIR=[$HK_DIR_C])"; fi
BOOT="$DIR/git-data-bootstrap.sh"
_b_dir="$(sed -n 's|^HOOKS_DIR="\$GIT_DATA_ROOT/\([^"/]*\)".*|\1|p' "$BOOT")"
_b_pr="$(sed -n 's|^PRE_RECEIVE="\$HOOKS_DIR/\([^"/]*\)"$|\1|p' "$BOOT")"
if [ -n "$_b_dir" ] && [ -n "$_b_pr" ] && [ "$_b_dir" = "$HK_DIR_C" ] && [ "$_b_pr" = "$HK_PR_C" ]; then ok "HK3 the basenames of HOOKS_DIR and PRE_RECEIVE in git-data-bootstrap.sh equal WA_HK_DIR and WA_HK_PR"
else no "HK3 bootstrap basenames [$_b_dir] [$_b_pr] differ from the constants [$HK_DIR_C] [$HK_PR_C]"; fi
case "$HK_PR_C" in *[\*\?\[\\]*|"") no "HK4 WA_HK_PR is empty or carries a glob character: [$HK_PR_C]" ;; *) ok "HK4 WA_HK_PR carries none of the find -name glob characters" ;; esac
if [ "$(grep -cF 'timeout 30 find "$WA_MNT/$WA_HK_DIR" ' "$SCRIPT")" = 2 ] && [ "$(grep -cF '$WA_HK_DIR/' "$SCRIPT")" = 0 ]; then ok "HK5 exactly two timeout-30 finds on the hooks path, and the path never carries a trailing slash (a slash would make the kernel follow a symlinked hooks)"
else no "HK5 the hooks finds are not exactly two or the path has a trailing slash"; fi
_stripped_n="$(wc -c < "$HK_STRIPPED")"
if [ "$HK_MAX_C" = 4096 ] && [ "$_stripped_n" -gt 0 ] && [ "$_stripped_n" -le "$HK_MAX_C" ]; then ok "HK6 WA_HK_PR_MAX equals the pinned 4096 and the stripped shipped hook ($_stripped_n bytes) is within it"
else no "HK6 bound: script literal [$HK_MAX_C] (pinned 4096), stripped hook $_stripped_n bytes"; fi
if [ "$(grep -cE '^ +exit 34$' "$SCRIPT")" = 1 ] && [ "$(grep -cF 'offlist_n=$OFFLIST_N$HK_TAIL"' "$SCRIPT")" = 1 ]; then ok "HK7 one exit 34 site, and its single say line carries the group"
else no "HK7 the exit-34 site or the say line differs"; fi
if hk_block_closed "$SCRIPT" && [ "$(grep -cE '^      budget$' < <(hk_block "$SCRIPT"))" = 1 ] && hk_budget_first "$SCRIPT"; then ok "HK8 the non-comment lines of the hooks block are exactly the reviewed literals, each once (structural, not a syscall trace), and budget is called once, before the first find"
else no "HK8 the hooks block is not the reviewed one, or budget does not precede the finds"; fi
if hk_outside_closed "$SCRIPT"; then ok "HK10 outside the hooks block only the $(wc -l < "$HK_OUT_ALLOWED" | tr -d ' ') reviewed lines (a multiset) name the hooks directory, the pre-receive file, a hook constant, the mounted tree, its directory, the snapshot node or the device"
else no "HK10 the touching lines outside the hooks block are not the reviewed ones; first difference: [$HK_FIRST_BAD]"; fi
if hk_no_file_redirect "$SCRIPT"; then ok "HK11 no line of the script reads a file by redirection or by the builtin (only /dev/null, here-strings and process substitutions)"
else no "HK11 the script reads a file by redirection or by the builtin; first offending line: [$HK_FIRST_BAD]"; fi
if hk_die_args_plain "$SCRIPT"; then ok "HK12 no die or say call passes a command substitution in its arguments (a value read from the tree cannot ride a fixed-word line)"
else no "HK12 a die or say call carries a command substitution in its arguments"; fi
_hk_forbid=(-e '(^| )-L( |$)' -e '(^| )-H( |$)' -e '-iname' -e '%f' -e '%p' -e '2>&1' -e '<<' -e 'mapfile' -e 'readarray' -e 'exec ')
# grep_none: only an exit 1 (no match) is clean; a grep error reads as not clean, never as an absence
if hk_block "$SCRIPT" | grep_none -E "${_hk_forbid[@]}"; then ok "HK9 the hooks block has no -L, -H, -iname, %f, %p, 2>&1, here-string, mapfile or exec"
else no "HK9 a forbidden construct is in the hooks block (or the probe itself failed): $(hk_block "$SCRIPT" | grep -E "${_hk_forbid[@]}" | head -n 1 | cut -c1-200)"; fi
if hk_emit_sites_pinned "$SCRIPT"; then ok "HK13 the script has exactly $HK_SAY_SITES say call sites and $HK_SAY_DEFS definition (word tokens, every spelling), $HK_FD3_WRITES write to fd 3, $HK_FD4_WRITES writes to fd 4, $HK_FD_OTHER_WRITES other descriptor writes and $HK_FD_REDIRECTS \`>&\` tokens in all (measured 2026-10-19; a further channel off the host returns to review)"
else no "HK13 the say tokens or the descriptor writes are not the pinned $HK_SAY_SITES+$HK_SAY_DEFS / $HK_FD3_WRITES / $HK_FD4_WRITES / $HK_FD_OTHER_WRITES / $HK_FD_REDIRECTS"; fi
# HK14 the literal ERE in the runbook equals RE_34 byte for byte, in BOTH places the runbook carries it: the fenced block under the
# "Literal pattern (" paragraph, and the single-quoted argument of the `grep -E` in the extraction command an operator runs. The
# paragraph must be unique; the FIRST fence after it must be the ```text fence (any other fence first is a failure, so a stale plain
# fence plus a decoy ```text fence further down cannot satisfy it); the block is exactly one non-empty line; the extraction command
# holds exactly one `grep -E '^wipe-assert: rc=34 ...'` (a second one makes the extracted text two lines, which cannot equal the
# candidate). The one-liner is read by the shape of its grep argument, not by its position,
# so a change to the commands around it (the CR strip, the prefix strip) does not move it. hk_runbook_re_equals takes the candidate
# and the file, so the harness can prove each one-sided edit goes RED on a copy of the runbook.
RB="$(cd "$DIR/../../.." && pwd)/knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md"
hk_runbook_re() { # <runbook> — the one fenced line under the paragraph
  [ -s "$1" ] && [ "$(grep -c '^Literal pattern (' "$1")" = 1 ] || return 1
  awk '/^Literal pattern \(/ { a = 1; next } a && !f && /^```/ { if ($0 == "```text") { f = 1; next } bad = 1; exit } f && /^```$/ { done = 1; exit } f { print } END { exit (bad || !done) }' "$1"
}
hk_runbook_cmd_re() { # <runbook> — the argument of the one `grep -E '^wipe-assert: rc=34 ...'` of the extraction command
  local m
  [ -s "$1" ] || return 1
  m="$(grep -hoE "grep -E '\^wipe-assert: rc=34 [^']*'" "$1")" || return 1
  m="${m#grep -E \'}"
  printf '%s\n' "${m%\'}"
}
hk_runbook_re_equals() { # <candidate> [<runbook>] — both copies are one non-empty line equal to the candidate
  local rb="${2:-$RB}" got cmd
  got="$(hk_runbook_re "$rb")" || return 1
  cmd="$(hk_runbook_cmd_re "$rb")" || return 1
  [ -n "$got" ] && [ "$(printf '%s\n' "$got" | wc -l)" = 1 ] && [ "$got" = "$1" ] && [ "$cmd" = "$1" ]
}
if hk_runbook_re_equals "$RE_34"; then ok "HK14 the literal ERE in the runbook (the fenced block under 'Literal pattern (' and the grep -E argument of the extraction command) equals RE_34 byte for byte"
else no "HK14 the runbook's literal ERE is missing, not unique, not one line, in the wrong fence, or differs from RE_34 (in the fenced block or in the extraction command)"; fi
if ! hk_runbook_re_equals "${RE_34/rc=34/rc=35}" && ! hk_runbook_re_equals "${RE_34%\$}" && ! hk_runbook_re_equals ""; then ok "H7: the runbook-parity helper goes RED on a one-character edit of RE_34, a dropped anchor and an empty candidate"
else no "H7: the runbook-parity helper accepted an edited or empty RE_34"; fi
# runbook copies with ONE place edited: each must go RED, the unedited copy must stay GREEN (the control)
hk_rb_variant() { # <name> <mode> — write $T/rb-<name>.md from the runbook; return 1 when the edit did not land
  python3 - "$RB" "$T/rb-$1.md" "$2" "$RE_34" <<'PY' || return 1
import sys
src, dst, mode, re34 = sys.argv[1:5]
lines = open(src).read().split("\n")
out = []
para = [i for i, l in enumerate(lines) if l.startswith("Literal pattern (")]
assert len(para) == 1
cmdl = [i for i, l in enumerate(lines) if "grep -E '^wipe-assert: rc=34 " in l]
assert len(cmdl) == 1
if mode == "oneliner":
    lines[cmdl[0]] = lines[cmdl[0]].replace("hk_pr_f=([01])", "hk_pr_f=([0-9])")
elif mode == "fence-stale-decoy":
    f = [i for i in range(para[0], len(lines)) if lines[i] == "```text"][0]
    lines[f] = "```"
    lines[f + 1] = lines[f + 1].replace("rc=34", "rc=35")
    lines += ["", "```text", re34, "```", ""]
elif mode == "bash-fence-first":
    f = [i for i in range(para[0], len(lines)) if lines[i] == "```text"][0]
    lines[f] = "```bash"
elif mode == "block-only":
    f = [i for i in range(para[0], len(lines)) if lines[i] == "```text"][0]
    lines[f + 1] = lines[f + 1].replace("hk_pr_f=([01])", "hk_pr_f=([0-9])")
elif mode == "second-oneliner":
    lines.insert(cmdl[0] + 1, lines[cmdl[0]])
elif mode == "none":
    pass
open(dst, "w").write("\n".join(lines))
PY
  { [ "$2" = none ] || ! cmp -s "$RB" "$T/rb-$1.md"; }
}
_rb_ok=1
hk_rb_variant ctl none && hk_runbook_re_equals "$RE_34" "$T/rb-ctl.md" || _rb_ok=0
for _m in oneliner fence-stale-decoy bash-fence-first block-only second-oneliner; do
  hk_rb_variant "$_m" "$_m" && ! hk_runbook_re_equals "$RE_34" "$T/rb-$_m.md" || { _rb_ok=0; echo "# H7 variant not RED: $_m" >&2; }
done
if [ "$_rb_ok" = 1 ]; then ok "H7: an unedited runbook copy is accepted, and each one-sided edit goes RED (the grep -E one-liner alone, the fenced block alone, a stale plain fence with a decoy text fence at the end, a bash fence first, a second one-liner)"
else no "H7: a runbook copy with a single edited place was accepted by the parity check, or an edit did not land"; fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# TIER C — the listing unit on real loop devices
# ══════════════════════════════════════════════════════════════════════════════════════════
LOOPBACK_RAN=0
loopback_unavailable() { # <reason>
  if [ "${WIPE_ASSERT_REQUIRE_LOOPBACK:-0}" = 1 ]; then
    echo "LOOPBACK_UNAVAILABLE: $*" >&2
    echo "git-data-wipe-assert: LOOPBACK_UNAVAILABLE — real-device evidence was NOT collected (WIPE_ASSERT_REQUIRE_LOOPBACK=1 makes that a failure)." >&2
    exit 2
  fi
  echo "SKIP(LOOPBACK_UNAVAILABLE): $* — tier C (the listing on a real dm snapshot over a dirty journal) did NOT run."
  echo "SKIP(LOOPBACK_UNAVAILABLE): $* — tier C did NOT run." >&2
}
loopback_tier() {
  local b
  for b in losetup dmsetup blockdev mkfs.ext4 dumpe2fs debugfs mount umount findmnt mountpoint sha256sum python3 realpath cryptsetup; do
    command -v "$b" >/dev/null 2>&1 || { loopback_unavailable "required binary '$b' not found on PATH"; return 0; }
  done
  if dmsetup info git-data-pt-snap >/dev/null 2>&1; then loopback_unavailable "device-mapper name 'git-data-pt-snap' is already in use (another run, or a real host)"; return 0; fi
  LOOPBACK_RAN=1
  echo "--- TIER C: the listing unit on real loop devices"
  CLEAN_MOUNTS=(); CLEAN_LOOPS=(); CLEAN_DMS=()
  lb_teardown() {
    local i
    for ((i = ${#CLEAN_MOUNTS[@]} - 1; i >= 0; i--)); do
      mountpoint -q "${CLEAN_MOUNTS[$i]}" 2>/dev/null && { umount "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1 || umount -l "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1; }
    done
    for ((i = ${#CLEAN_DMS[@]} - 1; i >= 0; i--)); do dmsetup info "${CLEAN_DMS[$i]}" >/dev/null 2>&1 && dmsetup remove --retry "${CLEAN_DMS[$i]}" >/dev/null 2>&1; done
    for ((i = ${#CLEAN_LOOPS[@]} - 1; i >= 0; i--)); do losetup -d "${CLEAN_LOOPS[$i]}" >/dev/null 2>&1; done
    return 0
  }
  trap 'lb_teardown; cleanup' EXIT
  LB="$T/lb"; assert_fixture_dir "$LB"; mkdir -p "$LB" || instrument "mkdir lb failed"
  declare -gA LOOP_IMG=()
  # A reused loop number can come back kernel read-only: `blockdev --setro` (BLKROSET) survives a detach on newer kernels, and
  # an earlier loopback suite on the same runner leaves it behind (CI run 38715878045: "source write-protected, mounted
  # read-only" on the first populate). The image is this run's own, so make it writable and read the flag back.
  lb_attach() {
    LOOP="$(losetup --find --show "$1")" || instrument "losetup failed for $1"; CLEAN_LOOPS+=("$LOOP"); LOOP_IMG[$LOOP]="$1"
    blockdev --setrw "$LOOP" || instrument "setrw failed for $LOOP"
    [ "$(blockdev --getro "$LOOP")" = 0 ] || instrument "$LOOP is still read-only after setrw"
  }
  lb_detach() { local i; losetup -d "$1" || instrument "losetup -d $1 failed"; for i in "${!CLEAN_LOOPS[@]}"; do [ "${CLEAN_LOOPS[$i]}" != "$1" ] || unset 'CLEAN_LOOPS[i]'; done; CLEAN_LOOPS=("${CLEAN_LOOPS[@]}"); unset 'LOOP_IMG[$1]'; }
  lb_image() { # <tag> — a fresh 256 MiB ext4 image on a loop device. Sets LOOP and IMG.
    IMG="$LB/$1.img"; truncate -s 256M "$IMG" || instrument "truncate failed"
    mkfs.ext4 -q -F "$IMG" >/dev/null 2>&1 || instrument "mkfs.ext4 failed"
    lb_attach "$IMG"
  }
  lb_needs_recovery() { local sb; sb="$(dumpe2fs -h "$1" 2>/dev/null)" || return 2; [[ "$sb" == *"Filesystem features:"*" needs_recovery"* ]]; }
  lb_origin_sha() { local img="${LOOP_IMG[$1]:-}"; [ -f "$img" ] || instrument "no backing file for $1"; blockdev --flushbufs "$1" || instrument "flushbufs failed"; sha256sum < "$img"; }
  lb_wstat() { local f; read -r -a f < "/sys/class/block/${1##*/}/stat" || instrument "sysfs stat unreadable"; printf '%s %s' "${f[6]}" "${f[13]}"; }
  lb_populate() { # <loop> <snippet> — mount rw, run, unmount cleanly
    local loop="$1" snippet="$2" mnt="$LB/pop-mnt"
    mkdir -p "$mnt" || instrument "mkdir pop-mnt failed"
    mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
    ( cd "$mnt" && eval "$snippet" ) || { umount "$mnt"; instrument "populate snippet failed: $snippet"; }
    umount "$mnt" || instrument "umount after populate failed"
  }
  # lb_journal_only <tag> <mkdir-rel> <fsync-rel> — a checkpointed anchor, then <mkdir-rel> created, its
  # parent directory fsync'd and the filesystem shut down FROM THE SAME PROCESS; the backing file is
  # COPIED BEFORE umount, so the new entry is in the journal but not in the home blocks (the
  # discriminating shape: a noload read would miss it). Sets ARM_LOOP; returns 1 if the shape did not form.
  lb_journal_only() {
    local tag="$1" rel="$2" syncrel="$3" mnt="$LB/jo-mnt" orig_loop orig_img copy="$LB/$1.jo.img" ls parent
    lb_image "$tag"; orig_loop="$LOOP"; orig_img="$IMG"
    lb_populate "$orig_loop" 'mkdir -p repositories && : > repositories/.anchor.init.lock'
    mkdir -p "$mnt" || instrument "mkdir jo-mnt failed"
    mount -o rw "$orig_loop" "$mnt" || instrument "rw mount failed"
    CLEAN_MOUNTS+=("$mnt")
    python3 - "$mnt" "$rel" "$syncrel" <<'PY' || { umount "$mnt" 2>/dev/null; instrument "the journal-only build failed"; }
import fcntl, os, struct, sys
m, rel, srel = sys.argv[1:4]
os.mkdir(os.path.join(m, rel))
d = os.open(os.path.join(m, srel) if srel != "." else m, os.O_RDONLY)
os.fsync(d)
os.close(d)
fd = os.open(m, os.O_RDONLY)
fcntl.ioctl(fd, 0x8004587D, struct.pack('I', 1))
os.close(fd)
PY
    cp --sparse=always "$orig_img" "$copy" || instrument "copying the shut-down image failed"
    umount "$mnt" || instrument "umount after shutdown failed"
    lb_detach "$orig_loop"
    rm -f "$orig_img"
    lb_attach "$copy"
    ARM_LOOP="$LOOP"
    lb_needs_recovery "$ARM_LOOP" || return 1
    parent="${rel%/*}"; [ "$parent" != "$rel" ] || parent=""
    ls="$(debugfs -c -R "ls -l /$parent" "$ARM_LOOP" 2>/dev/null)" || return 1
    [[ "$ls" != *"${rel##*/}"* ]] || return 1
    return 0
  }
  lb_build_jo() { local try; for try in 1 2 3; do lb_journal_only "$1-$try" "$2" "$3" && return 0; done; instrument "arm $1: after 3 builds the entry was not journal-only"; }
  lb_dirty() { # <loop> — leave a dirty journal on an otherwise populated image
    local loop="$1" mnt="$LB/dirty-mnt"
    mkdir -p "$mnt" || instrument "mkdir dirty-mnt failed"
    mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
    CLEAN_MOUNTS+=("$mnt")
    mkdir -p "$mnt/repositories/probe.git" && rmdir "$mnt/repositories/probe.git" || instrument "probe mkdir/rmdir failed"
    python3 - "$mnt" <<'PY' || instrument "EXT4_IOC_SHUTDOWN failed"
import fcntl, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
fcntl.ioctl(fd, 0x8004587D, struct.pack('I', 1))
os.close(fd)
PY
    umount "$mnt" || instrument "umount after shutdown failed"
    lb_needs_recovery "$loop" || instrument "the dirtied image does not carry needs_recovery"
  }

  # The driver: core + unit extracted by their sentinels from the REAL script, run in a CHILD bash.
  CORE="$LB/core.sh"; UNIT="$LB/unit.sh"
  awk '/# ---- BEGIN wipe-core ----/{f=1;next} /# ---- END wipe-core ----/{f=0} f' "$SCRIPT" > "$CORE" || instrument "core extraction failed"
  awk '/# ---- BEGIN wipe-listing unit ----/{f=1;next} /# ---- END wipe-listing unit ----/{f=0} f' "$SCRIPT" > "$UNIT" || instrument "unit extraction failed"
  [ "$(grep -c . "$CORE")" -ge 40 ] || instrument "the wipe-core extracted too few lines (sentinels moved?)"
  [ "$(grep -c . "$UNIT")" -ge 60 ] || instrument "the wipe-listing unit extracted too few lines (sentinels moved?)"
  bash -n "$CORE" && bash -n "$UNIT" || instrument "an extracted unit is not valid bash"
  DRV="$LB/drv.sh"
  cat > "$DRV" <<'DRVEOF'
exec 3>&2 4>&1 1>/dev/null 2>/dev/null </dev/null
. "$1"
budget() { :; }   # the main body's wall-clock check lives outside the extracted core; the unit calls it before the hooks reads
DEV="$3"; BYID="$3"
MM="$(devnum_hex "$DEV")" || { say "driver: devno"; exit 16; }
SYS="/sys/dev/block/$(devno_dec "$MM")"
W0="$(wstat)" || { say "driver: wstat"; exit 16; }
. "$2"
wipe_listing
printf 'J=%s d=%s f=%s l=%s o=%s repos=%s\n' "$J" "$TOP_D" "$TOP_F" "$TOP_L" "$TOP_O" "$REPOS" >&4
exit 0
DRVEOF
  lb_leak_state() {
    { losetup -a 2>/dev/null | grep -E "\\(($LB/|/dev/shm/)" | sort || true
      echo ---
      dmsetup ls 2>/dev/null | grep -E '^git-data-pt-snap[[:space:]]' | sort || true
      echo ---
      ls -d /dev/shm/*/cow /dev/shm/*/mnt 2>/dev/null | sort || true; }
  }
  # lb_run <arm> <loop> — a child runs the unit; the parent owes the five invariants of every arm.
  lb_run() {
    local arm="$1" loop="$2" sha0 sha1 w0 w1 leak0 leak1
    sync
    sha0="$(lb_origin_sha "$loop")" || instrument "$arm: hashing failed"
    w0="$(lb_wstat "$loop")"
    blockdev --setro "$loop" || instrument "$arm: setro failed"
    [ "$(blockdev --getro "$loop")" = 1 ] || instrument "$arm: getro did not read back 1"
    leak0="$(lb_leak_state)"
    LB_RC=0
    env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash "$DRV" "$CORE" "$UNIT" "$loop" > "$LB/$arm.out" 2> "$LB/$arm.err" || LB_RC=$?
    sha1="$(lb_origin_sha "$loop")" || instrument "$arm: hashing failed"
    w1="$(lb_wstat "$loop")"
    leak1="$(lb_leak_state)"
    if [ "$sha0" = "$sha1" ]; then ok "C $arm the origin's bytes are unchanged (sha256 of the backing file)"; else no "C $arm the origin's bytes CHANGED"; fi
    if [ "$w0" = "$w1" ]; then ok "C $arm the origin's sectors written/discarded are unchanged ($w0)"; else no "C $arm the origin's counters moved ($w0 -> $w1)"; fi
    if [ "$(blockdev --getro "$loop")" = 1 ]; then ok "C $arm the origin is still kernel read-only"; else no "C $arm the origin is NOT read-only"; fi
    if [ "$leak0" = "$leak1" ]; then ok "C $arm no loop, dm device or /dev/shm entry survives"; else no "C $arm transient state leaked"; fi
    if dmsetup info git-data-pt-snap >/dev/null 2>&1; then no "C $arm git-data-pt-snap still exists"; dmsetup remove --retry git-data-pt-snap >/dev/null 2>&1; else ok "C $arm no git-data-pt-snap device remains"; fi
    leak="$(grep -rlF -f "$PATS" "$LB/$arm.out" "$LB/$arm.err" || true)"
    if [ -z "$leak" ]; then ok "C $arm no synthesized name in stdout or stderr"; else no "C $arm a name reached an output: $leak"; fi
  }
  lb_expect() { # <arm> <rc> <literal in stdout|stderr>
    local arm="$1" rc="$2" lit="$3"
    if [ "$LB_RC" = "$rc" ] && { grep -qF -- "$lit" "$LB/$arm.out" || grep -qF -- "$lit" "$LB/$arm.err"; }; then ok "C $arm rc $rc and '$lit'"
    else no "C $arm expected rc $rc with '$lit'; got rc=$LB_RC out=[$(cat "$LB/$arm.out")] err=[$(tr '\n' '|' < "$LB/$arm.err")]"; fi
  }
  ARMS_C=0
  # A: dirty journal, an allowlisted tree
  ARMS_C=$((ARMS_C + 1))
  lb_image a; A_LOOP="$LOOP"
  lb_populate "$A_LOOP" 'mkdir -p repositories && : > .gc-cursor'
  lb_dirty "$A_LOOP"
  lb_run A "$A_LOOP"
  lb_expect A 0 'J=dirty d=2 f=1 l=0 o=0 repos=0'
  # B: an off-list directory that exists ONLY in the journal (a noload read would miss it)
  ARMS_C=$((ARMS_C + 1))
  lb_build_jo b "$CORPUS_TOP_DIR" "."
  lb_run B "$ARM_LOOP"
  lb_expect B 34 'reason=offlist'
  # C: a repository that exists ONLY in the journal
  ARMS_C=$((ARMS_C + 1))
  lb_build_jo c "repositories/$CORPUS_REPO_A" "repositories"
  lb_run C "$ARM_LOOP"
  lb_expect C 37 'reason=repositories_not_empty repos=1'
  # D: repositories is a SYMLINK
  ARMS_C=$((ARMS_C + 1))
  lb_image d; D_LOOP="$LOOP"
  lb_populate "$D_LOOP" "mkdir -p real/$CORPUS_REPO_A && ln -s real repositories"
  lb_run D "$D_LOOP"
  lb_expect D 34 'reason=offlist'
  # E: a clean journal and an empty allowlisted tree
  ARMS_C=$((ARMS_C + 1))
  lb_image e; E_LOOP="$LOOP"
  lb_populate "$E_LOOP" 'mkdir -p repositories'
  lb_run E "$E_LOOP"
  lb_expect E 0 'J=clean d=2 f=0 l=0 o=0 repos=0'
  # F: nothing but lost+found
  ARMS_C=$((ARMS_C + 1))
  lb_image f; F_LOOP="$LOOP"
  lb_run F "$F_LOOP"
  lb_expect F 0 'J=clean d=1 f=0 l=0 o=0 repos=0'
  # G: a top-level file that is not on the allowlist, named like a tenant document
  ARMS_C=$((ARMS_C + 1))
  lb_image g; G_LOOP="$LOOP"
  lb_populate "$G_LOOP" "mkdir -p repositories && : > $CORPUS_TOP_FILE"
  lb_run G "$G_LOOP"
  lb_expect G 34 'reason=offlist'
  # H: the production layout the host script itself creates (repositories, hooks holding a pre-receive, lost+found)
  ARMS_C=$((ARMS_C + 1))
  lb_image h; H_LOOP="$LOOP"
  lb_populate "$H_LOOP" 'mkdir -p repositories hooks && : > hooks/pre-receive'
  lb_run H "$H_LOOP"
  lb_expect H 34 'reason=offlist'
  if [ "$(tail -n 1 "$LB/H.err")" = 'wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1 hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1' ]; then ok "C H the whole rc=34 line names the hooks directory, one off-list entry and the hk_ shape of a 0-byte pre-receive on a real image"
  else no "C H the rc=34 line differs: [$(tail -n 1 "$LB/H.err")]"; fi
  # floor
  EXPECTED_ARMS_C=8
  if [ "$ARMS_C" -ne "$EXPECTED_ARMS_C" ]; then
    printf '[FATAL] anti-vacuity floor: %s loopback arms ran, expected exactly %s\n' "$ARMS_C" "$EXPECTED_ARMS_C" >&2; exit 1
  fi
}

if [ "$(id -u)" -eq 0 ]; then
  loopback_tier
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  echo "--- TIER C: re-running the loopback tier under sudo"
  _c_rc=0
  sudo -n env WIPE_ASSERT_REQUIRE_LOOPBACK="${WIPE_ASSERT_REQUIRE_LOOPBACK:-0}" bash "${BASH_SOURCE[0]}" --loopback-tier || _c_rc=$?
  if [ "$_c_rc" -eq 0 ]; then LOOPBACK_RAN=1; ok "C the loopback tier passed under sudo"; else no "C the loopback tier FAILED under sudo (rc=$_c_rc)"; fi
else
  loopback_unavailable "not root and passwordless sudo is unavailable"
fi

# ══════════════════════════════════════════════════════════════════════════════════════════
# FLOOR — self-contained: bash builtins and this suite's own counters, reported by printf + exit and
# never through ok()/no() (ADR-193). Each bound is a literal on the line directly above its `if`.
# ══════════════════════════════════════════════════════════════════════════════════════════
# 45 = the 23 earlier rc=34 rows + 22 hooks-shape rows (A140-A149, A150 x9, A151, A152, A153): re-measured unprivileged, loopback skipped, 2026-10-19 (unchanged by the second and third fix rounds: they add no expect_refuse run)
EXPECTED_RC34_LINES=45
if [ "$RC34_LINES_CHECKED" -lt "$EXPECTED_RC34_LINES" ]; then
  printf '[FATAL] anti-vacuity floor: only %s rc=34 lines were checked for the strict shape, floor is %s\n' "$RC34_LINES_CHECKED" "$EXPECTED_RC34_LINES" >&2
  exit 1
fi
# EXACT count of the expect_refuse rc=34 lines that carry the hk_ group (RC34_LINES_CHECKED is a floor and the CI loopback tier
# lifts `executed`; this one moves only when a hooks row is added or removed). Re-measured unprivileged, loopback skipped, 2026-10-19 (unchanged).
# 24 = A120, A122 and the 22 hooks-shape rows above.
EXPECTED_HK_GROUP_LINES=24
if [ "$HK_GROUP_LINES_CHECKED" -ne "$EXPECTED_HK_GROUP_LINES" ]; then
  printf '[FATAL] anti-vacuity floor: %s rc=34 lines carried the hk_ group, expected exactly %s\n' "$HK_GROUP_LINES_CHECKED" "$EXPECTED_HK_GROUP_LINES" >&2
  exit 1
fi
# 160 = 129 + 31 hooks-shape runs (the 22 rc=34 rows above + the 9 rc=33 rows A160-A166): re-measured unprivileged, loopback skipped, 2026-10-19 (unchanged by the second and third fix rounds)
EXPECTED_INVARIANT_RUNS=160
if [ "$INVARIANT_RUNS" -lt "$EXPECTED_INVARIANT_RUNS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s host-script runs were checked for the output invariants, floor is %s\n' "$INVARIANT_RUNS" "$EXPECTED_INVARIANT_RUNS" >&2
  exit 1
fi
# 1381 = executed assertions of an unprivileged run with the loopback tier skipped (the way the local gate runs): measured unprivileged, loopback skipped, 2026-10-19
# (1240 before the first review round; 1292 after it: +52 = 26 rows of HK13, HK14, H4, H6 (with its run-bound row), H7 and H8, 16 for the 12b
# families diff, cmp, sort and mntroot (union and -rec, control and mutant row each), 4 for the subshell and WA_DIR-glob static rows and 6 for
# the three emit-channel rows. 1350 after the second: +58 = 11 net in H6 (the redirect rule without blanking: 26 allowed and flagged forms, the
# no-trailing-newline pair and the early-stop row, replacing 18), 1 in H7 (the one-sided runbook edits), 16 for the 12b families paste, uniq,
# strings and od (union and -rec), 20 for ten static rows (tgt, cowdir, mntdir, three /dev/mapper forms, DEV and WA_LOOP touch-list rows,
# and WA_SNAP alone, plus the awk getline row) and 10 for the five new emit-channel rows. 1381 after the third: +31 = 20 for ten static
# touch-list rows (dm, dmn, src, got, want, lf, lk, BYID, BYID_LUKS, MAPPER), 6 for the three emit rows (`>&03`, `say${IFS}"x"`, `say;`) and
# 5 net in H6 (two allowed `<&3` forms and three flagged `&&<` forms)).
# Equal to the executed count of that run, so the merge gate relies on the CI run in which tier C executes and lifts `executed`.
MIN_ASSERTIONS=1381
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s — rows were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf 'ok   - anti-vacuity floor: %s assertions over %s invariant-checked runs (floors %s / %s), %s rc=34 lines checked (floor %s), %s with the hk_ group (exactly %s)\n' "$executed" "$INVARIANT_RUNS" "$MIN_ASSERTIONS" "$EXPECTED_INVARIANT_RUNS" "$RC34_LINES_CHECKED" "$EXPECTED_RC34_LINES" "$HK_GROUP_LINES_CHECKED" "$EXPECTED_HK_GROUP_LINES"

echo ""
if [ "$LOOPBACK_RAN" = 1 ]; then _lb="loopback tier RAN"; else _lb="loopback tier did NOT run (SKIPPED: see SKIP(LOOPBACK_UNAVAILABLE) above)"; fi
echo "=== git-data-wipe-assert.test.sh: ${pass} passed, ${fail} failed; ${_lb} ==="
[ "$fail" -eq 0 ]
