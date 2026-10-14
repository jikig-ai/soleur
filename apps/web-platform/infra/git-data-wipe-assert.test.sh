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
#      state file or /dev/shm.
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
PATS="$T/corpus.pats"
printf '%s\n' "$CORPUS_REPO_A" "$CORPUS_REPO_B" "$CORPUS_TOP_DIR" "$CORPUS_TOP_FILE" "$CORPUS_NL_A" "$CORPUS_NL_B" > "$PATS" || instrument "corpus write failed"
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
case "$n" in
  cat)
    case "$last" in
      /sys/*/stat)
        c=0; [ -f "$ST/stat_calls" ] && c="$(cat "$ST/stat_calls")"
        printf '%s' "$((c + 1))" > "$ST/stat_calls"
        if flag stat_alt && [ "$c" -ge 1 ]; then exec cat "$W/stat_alt"; fi
        exec cat "$W/files$last" ;;
      /sys/*|/proc/*|/var/lib/cloud/*)
        [ -f "$W/files$last" ] || exit 1
        exec cat "$W/files$last" ;;
    esac
    exec cat "$@" ;;
  date)
    if [ "${1-}" = "+%s" ]; then exec cat "$W/now"; fi
    exec date "$@" ;;
  sleep) exit 0 ;;
  udevadm) exit 0 ;;
  stat)
    case "$last" in
      /dev/*)
        if flag byid_gone && [ "$last" = "/dev/disk/by-id/scsi-0HC_Volume_111111111" ]; then exit 1; fi
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
      --getro) cat "$W/ro"; exit 0 ;;
      --getsz) echo 2097152; exit 0 ;;
    esac
    exit 9 ;;
  ls)
    case "$last" in
      /sys/*) [ -f "$W/files$last" ] || exit 2; cat "$W/files$last"; exit 0 ;;
    esac
    exec ls "$@" ;;
  find)
    if [ "${1-}" = "/proc" ]; then
      [ -f "$W/open_handles" ] && cat "$W/open_handles"
      exit "$(cat "$W/find_proc_rc" 2>/dev/null || echo 0)"
    fi
    case "$*" in *"-printf %y"*) if flag fail_find_listing; then exit 3; fi ;; esac
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
    find "$mnt" -mindepth 1 -delete
    rm -f "$ST/mounted"
    if flag written_on_umount; then cp "$W/written_on_umount" "$W/files/sys/dev/block/8:16/stat"; fi
    exit 0 ;;
esac
echo "shim: no arm for $n" >&2
exit 99
SHIM
chmod +x "$SH/_shim" || instrument "chmod shim failed"
for _n in cat date sleep udevadm stat realpath findmnt cryptsetup blockdev ls find dd dumpe2fs losetup dmsetup mount umount; do
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
  SHM_BEFORE="$(ls -A /dev/shm 2>/dev/null | sort | paste -sd, -)"
  RC=0
  env -i PATH="$SH:/usr/bin:/bin" WORLD="$W" \
    WIPE_PHASE="$phase" WIPE_TYPED_ID="$ID_T" WIPE_LUKS_ID="$ID_L" WIPE_SERVER_ID="$ID_S" \
    WIPE_OLD_ROOT="$W/root" WIPE_LUKS_MAPPER=/dev/mapper/git-data WIPE_STORE_VERIFIED="$W/marker" \
    "${extra[@]}" "$@" \
    bash -s < "${RUN_SCRIPT:-$SCRIPT}" > "$W/out" 2> "$W/err" || RC=$?
  SHM_AFTER="$(ls -A /dev/shm 2>/dev/null | sort | paste -sd, -)"
}

RE_PRE='^wipe_assert pre ok layout_signal=(ok|not_run) journal=(dirty|clean|na) top_d=([0-9]+|na) top_f=([0-9]+|na) top_l=([0-9]+|na) top_o=([0-9]+|na) repos=([0-9]+|na) boot_to_row_s=[0-9]+$'
RE_POST='^wipe_assert (post_detach|finish) ok byid=gone mapper_read=ok store_root=ok$'
RE_ERR='^wipe-assert: rc=[0-9]+ reason=[a-z_0-9]+( [a-z_]+=[0-9]+)*$'
INVARIANT_RUNS=0
NAMES_SEEN_RUNS=0
# invariants <label> — what EVERY run owes, success or refusal.
invariants() {
  local label="$1" leak bad lines
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
  # 3. teardown: no snapshot, loop, mount or /dev/shm directory left behind
  if [ ! -e "$W/state/snap_up" ] && [ ! -e "$W/state/loop" ] && [ ! -e "$W/state/mounted" ] && [ "$SHM_BEFORE" = "$SHM_AFTER" ]; then
    ok "$label: no snapshot, loop device, mount or /dev/shm entry survives"
  else no "$label: transient state leaked (snap=$([ -e "$W/state/snap_up" ] && echo y || echo n) loop=$([ -e "$W/state/loop" ] && echo y || echo n) mounted=$([ -e "$W/state/mounted" ] && echo y || echo n) shm=[$SHM_BEFORE]->[$SHM_AFTER])"; fi
  if [ -s "$W/state/corpus_seen" ] && [ "$(cat "$W/state/corpus_seen")" -gt 0 ]; then NAMES_SEEN_RUNS=$((NAMES_SEEN_RUNS + 1)); fi
}
# expect_refuse <label> <rc> <reason-prefix> — a refusal: nothing on stdout, the rc and a fixed reason on stderr.
expect_refuse() {
  local label="$1" rc="$2" reason="$3" last
  last="$(tail -n 1 "$W/err")"
  if [ "$RC" = "$rc" ] && [ ! -s "$W/out" ] && [[ "$last" == "wipe-assert: rc=$rc reason=$reason"* ]]; then
    ok "$label -> rc $rc reason=$reason, stdout empty"
  else no "$label: expected rc=$rc reason=$reason; got rc=$RC out=[$(cut -c1-80 "$W/out")] err=[$(tr '\n' '|' < "$W/err" | cut -c1-200)]"; fi
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

echo "--- TIER A: the host script over a simulated host"

# ── the clean host: skip (wipe_check) and run (wipe) ──────────────────────────────────────────
world a-skip
run_script pre WIPE_LISTING=skip
expect_line "A01 clean host, listing skipped (wipe_check)" '^wipe_assert pre ok layout_signal=not_run journal=na top_d=na top_f=na top_l=na top_o=na repos=na boot_to_row_s=1200$'
if [ "$(called dmsetup)" = 0 ] && [ "$(called mount)" = 0 ] && [ "$(called losetup)" = 0 ]; then ok "A01 skip: no snapshot was created, nothing mounted (wipe_check stays a metadata read)"
else no "A01 skip: a snapshot call was made"; fi

world a-run
run_script pre
expect_line "A02 clean host, listing run (dirty journal)" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200$'

# must-PASS: lock dotfiles at the top level and inside repositories/, lost+found inside repositories/
world a-locks
tree_clean
: > "$W/tree/.init.lock"; : > "$W/tree/.ws-9.init.lock"
: > "$W/tree/repositories/.init.lock"; : > "$W/tree/repositories/.ws-9.init.lock"; mkdir -p "$W/tree/repositories/lost+found"
run_script pre
expect_line "A03 (must-PASS) lock dotfiles and lost+found are not repositories" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=3 top_l=0 top_o=0 repos=0 boot_to_row_s=1200$'

world a-clean-journal
printf 'Filesystem features:      has_journal ext_attr resize_inode dir_index filetype extent\nFilesystem state:         clean\nTotal journal blocks:     16384\nBlock size:               4096\n' > "$W/sb_origin"
run_script pre
expect_line "A04 a clean journal reads journal=clean" '^wipe_assert pre ok layout_signal=ok journal=clean top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200$'

world a-norepos
tree_reset; mkdir -p "$W/tree/lost+found"
run_script pre
expect_line "A05 (must-PASS) a volume with no repositories directory and nothing else is empty" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=1 top_f=0 top_l=0 top_o=0 repos=0 boot_to_row_s=1200$'

# ── the layout-independent signal: off-list, non-empty, unparseable ──────────────────────────────
world a-offdir
mkdir -p "$W/tree/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A10 an extra top-level directory" 34 offlist
if grep -q 'top_d=3 top_f=1 top_l=0 top_o=0 repos=0' "$W/err"; then ok "A10 the refusal carries COUNTS only (top_d=3)"; else no "A10 counts missing from the refusal: $(cat "$W/err")"; fi

world a-offfile
: > "$W/tree/$CORPUS_TOP_FILE"
run_script pre
expect_refuse "A11 an extra top-level file" 34 offlist

world a-reposlink
tree_reset; mkdir -p "$W/tree/lost+found/$CORPUS_REPO_A"; ln -s lost+found "$W/tree/repositories"
run_script pre
expect_refuse "A12 repositories is a SYMLINK: never followed, off the allowlist" 34 offlist

world a-reposfile
tree_reset; mkdir -p "$W/tree/lost+found"; : > "$W/tree/repositories"
run_script pre
expect_refuse "A13 repositories is a regular file" 34 offlist

world a-fifo
mkfifo "$W/tree/$CORPUS_TOP_FILE" || instrument "mkfifo failed"
run_script pre
expect_refuse "A14 a FIFO at the top level counts as other and is off the allowlist" 34 offlist
if grep -q 'top_o=1' "$W/err"; then ok "A14 the FIFO is counted under top_o"; else no "A14 the FIFO was not counted as other: $(cat "$W/err")"; fi

world a-gclink
rm -f "$W/tree/.gc-cursor"; ln -s /etc/hostname "$W/tree/.gc-cursor"
run_script pre
expect_refuse "A15 .gc-cursor as a symlink is off the allowlist (path-typed, not name-only)" 34 offlist

world a-lostfile
rmdir "$W/tree/lost+found" && : > "$W/tree/lost+found" || instrument "A16 setup failed"
run_script pre
expect_refuse "A16 lost+found as a file is off the allowlist" 34 offlist

world a-absent-beside
tree_reset; mkdir -p "$W/tree/$CORPUS_TOP_DIR"
run_script pre
expect_refuse "A17 no repositories directory beside a non-allowlisted entry" 34 offlist

world a-nonempty
mkdir -p "$W/tree/repositories/$CORPUS_REPO_A" "$W/tree/repositories/$CORPUS_REPO_B"
run_script pre
expect_refuse "A20 repositories/ holds entries after the replay" 37 repositories_not_empty
if grep -q 'repos=2' "$W/err"; then ok "A20 the refusal carries a COUNT (repos=2) and no name"; else no "A20 count missing: $(cat "$W/err")"; fi

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
expect_line "A94 (must-PASS) a row exactly at the window bound passes" '^wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=3600$'

# ── post_detach / finish ─────────────────────────────────────────────────────────────────────────
world a-post
touch "$W/byid_gone"
run_script post_detach
expect_line "A100 post_detach: link gone, mapper read, store root" '^wipe_assert post_detach ok byid=gone mapper_read=ok store_root=ok$'
world a-finish
touch "$W/byid_gone"
run_script finish
expect_line "A101 finish: the same checks under their own phase word" '^wipe_assert finish ok byid=gone mapper_read=ok store_root=ok$'
world a-postpresent
run_script post_detach
expect_refuse "A102 the by-id link is still present after the detach" 40 byid_still_present
world a-postdd
touch "$W/byid_gone" "$W/fail_dd"
run_script post_detach
expect_refuse "A103 the uncached mapper read fails" 41 mapper_read_failed
world a-postroot
touch "$W/byid_gone"
rmdir "$W/root"
run_script post_detach
expect_refuse "A104 the store root cannot be listed" 42 store_root_unreadable
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
# shellcheck disable=SC2015  # ok()/no() cannot fail, so this is a true if/else
[ "$NAMES_SEEN_RUNS" -ge 6 ] && ok "GN: the corpus really was on the mounted tree in $NAMES_SEEN_RUNS runs (the no-names rows are not vacuous)" \
  || no "GN: the corpus reached the mounted tree in only $NAMES_SEEN_RUNS runs"
if [ "$CORPUS_N" -ge 6 ]; then ok "GN: the synthesized corpus holds $CORPUS_N patterns"; else no "GN: the corpus shrank to $CORPUS_N patterns"; fi

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
  world "m-$name"
  "$4"
  if [ "$5" = pre-skip ]; then RUN_SCRIPT="$MUTANT" run_script pre WIPE_LISTING=skip; else RUN_SCRIPT="$MUTANT" run_script "$5"; fi
  RUN_SCRIPT=""
  if "$6"; then no "M-$name: the mutant is still accepted by the original's case (the row is vacuous or the mutation was neutral)"
  else ok "M-$name: the named case goes RED against the mutant"; fi
}
RUN_SCRIPT=""
set_offdir()   { mkdir -p "$W/tree/$CORPUS_TOP_DIR"; }
set_reposlink() { tree_reset; mkdir -p "$W/tree/lost+found/$CORPUS_REPO_A"; ln -s lost+found "$W/tree/repositories"; }
set_written()  { printf '0 0 0 0 0 0 8 0 0 0 0 0 0 0\n' > "$W/files/sys/dev/block/8:16/stat"; }
set_isluks0()  { printf '0\n' > "$W/isluks_rc"; }
set_findfail() { touch "$W/fail_find_listing"; }
set_markerbad() { printf 'ffffffff-0000-4000-8000-000000000000\n' > "$W/marker"; }
set_clean()    { :; }
set_notmapper() { printf '/dev/sdb\n' > "$W/findmnt_source"; }
set_holders()  { printf 'dm-0\n' > "$W/files/sys/dev/block/8:16/holders"; }
set_isbacking() { printf '/dev/sdb\n' > "$W/cs_device"; }
set_umountfail() { touch "$W/fail_umount"; }
set_notblock() { printf '/dev/sdb file 8:10\n/dev/sdc block 8:20\n' > "$W/nodes"; }
caught_rc()   { # <rc> — true when the run is refused with that rc and prints nothing on stdout
  [ "$RC" = "$1" ] && [ ! -s "$W/out" ]
}
caught_34() { caught_rc 34; }
caught_29() { caught_rc 29; }
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
  [ -z "$(grep -rlF -f "$PATS" "$W/out" "$W/err" || true)" ]
}

# M1 (Guard 8 row 1): the classifier prints one synthesized name
mutant_row m1-prints-name '      [ -n "$n" ] || die 35 record_empty' '      [ -n "$n" ] || die 35 record_empty
      say "$n"' set_offdir pre caught_no_leak
# M2 (Guard 8 row 4): a digest of the listing rides on the output line
mutant_row m2-digest 'boot_to_row_s=%s\n'"'"' \' 'boot_to_row_s=%s digest=0f0f\n'"'"' \' set_clean pre caught_grammar
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
PRE_ANS='wipe_assert pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200'
V_PRE=(WIPE_PHASE=pre WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S" WIPE_ROW_DT="$ROWDT" WIPE_LISTING=run)
V_POST=(WIPE_PHASE=post_detach WIPE_VOLUME_ID="$ID_T" WIPE_LUKS_VOLUME_ID="$ID_L" WIPE_SERVER_ID="$ID_S")
has_store() { grep -qxF "[git-data-cutover] STORE probe=wipe-assert verdict=$1" "$TL/out"; }
no_remote_call() { [ "$(wc -l < "$TL/calls")" = 0 ]; }

run_verb b01 "$PRE_ANS" 0 "${V_PRE[@]}"
if [ "$VRC" = 0 ] && grep -qxF "[git-data-cutover] WIPE_ASSERT pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200" "$TL/out" && has_store ok; then
  ok "B01 pre with the listing: exit 0, the fixed-shape line is logged (counts only)"
else no "B01 pre did not pass: rc=$VRC out=[$(tr '\n' '|' < "$TL/out" | cut -c1-300)]"; fi
if grep -qxF "wipe_assert=$PRE_ANS" "$TL/gh_output" && grep -qxF -- "- WIPE_ASSERT pre ok layout_signal=ok journal=dirty top_d=2 top_f=1 top_l=0 top_o=0 repos=0 boot_to_row_s=1200" "$TL/gh_summary"; then
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
  lb_attach() { LOOP="$(losetup --find --show "$1")" || instrument "losetup failed for $1"; CLEAN_LOOPS+=("$LOOP"); LOOP_IMG[$LOOP]="$1"; }
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
  # floor
  EXPECTED_ARMS_C=7
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
EXPECTED_INVARIANT_RUNS=70
if [ "$INVARIANT_RUNS" -lt "$EXPECTED_INVARIANT_RUNS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s host-script runs were checked for the output invariants, floor is %s\n' "$INVARIANT_RUNS" "$EXPECTED_INVARIANT_RUNS" >&2
  exit 1
fi
MIN_ASSERTIONS=365
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s — rows were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf 'ok   - anti-vacuity floor: %s assertions over %s invariant-checked runs (floors %s / %s)\n' "$executed" "$INVARIANT_RUNS" "$MIN_ASSERTIONS" "$EXPECTED_INVARIANT_RUNS"

echo ""
if [ "$LOOPBACK_RAN" = 1 ]; then _lb="loopback tier RAN"; else _lb="loopback tier did NOT run (SKIPPED: see SKIP(LOOPBACK_UNAVAILABLE) above)"; fi
echo "=== git-data-wipe-assert.test.sh: ${pass} passed, ${fail} failed; ${_lb} ==="
[ "$fail" -eq 0 ]
