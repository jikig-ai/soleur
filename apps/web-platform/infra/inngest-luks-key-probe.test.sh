#!/usr/bin/env bash
# Tests for the LUKS key-continuity probe in inngest-cutover-flip.sh (#9927 item 2, ADR-282).
#
# The probe proves, between boots, that the key held in /etc/default/inngest-luks still unlocks a
# keyslot of the LUKS2 header behind the /mnt/data mapper. It lives INSIDE the only control script
# of the sole scheduler, so the suite's job is to prove two things at once: every verdict is
# reachable and exact, and the probe can NEVER change the script's exit status, the flag, or an FSM
# row (Guard 1), never lets the passphrase leave its stdin pipe (Guard 2), and honours its seams
# only under --fixture-seams while emitting only the closed vocabulary (Guard 3).
#
# SHAPE OF THE SUITE
#   * Every case drives the real script (`--fixture-seams`, a terminal noop flag) through stubs for
#     findmnt, cryptsetup (drains stdin on `--key-file -`, records argv, environment and the
#     received key bytes), logger, phone-home, a /proc/meminfo fixture and an oom_score_adj path.
#   * Each GUARD predicate is a function of the script path, so the same predicate runs against the
#     pristine script (must hold) and against a MUTATED SCRATCH COPY (must fail). Every mutation is
#     applied under mktemp -d, never to the tracked file, and a pristine-copy diff proves each
#     mutation LANDED, so a sed that matches nothing cannot read as "RED as expected".
#   * Harness rows: the instrument self-test, a flag_set recorder self-test, a wire assert whose
#     fixture is broken on purpose, must-PASS non-canonical runs, and an exact assertion count
#     reported with printf + exit (never through fail()).
#   * The real-tool arm builds a file-backed LUKS2 container in a temp dir (no root) and runs the
#     script's own pipeline against real cryptsetup. It is skipped with an EXPLICIT marker, never
#     silently, when cryptsetup is absent or cannot build the container here.
#
# Seam used by the RED step only: PROBE_SUITE_TARGET points the suite at another copy of the script
# (the pre-probe revision), proving the suite is RED before the function exists.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${PROBE_SUITE_TARGET:-$SCRIPT_DIR/inngest-cutover-flip.sh}"
UNIT_SRC="$SCRIPT_DIR/inngest-cutover-flip.service"

# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
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

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc";
  else fail "$desc"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}
# assert_true <desc> <command...> — passes when the command exits 0.
assert_true() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# INSTRUMENT SELF-TEST. Every claim below dispatches through pass()/fail(), and the assertion floor
# at the bottom must not. Prove both counters move before trusting anything, then reset. Output
# suppressed so the deliberate FAIL row cannot be misread as a real one.
pass "instrument self-test" >/dev/null
fail "instrument self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion counters are broken (PASS=%s FAIL=%s, expected 1/1).\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v timeout >/dev/null 2>&1 || { echo "UNRESOLVED: timeout missing — the probe cannot run; install coreutils"; exit 3; }
[[ -f "$TARGET" ]] || { echo "FAIL: $TARGET missing" >&2; exit 1; }

# A SINGLE OWNING TRAP (ADR-129) for every scratch root this file allocates.
WORK=""
SCRATCH=""
REAL_ROOT=""
BG_DIR=""
cleanup_all() {
  [[ -n "${WORK:-}" ]] && rm -rf "$WORK"
  [[ -n "${SCRATCH:-}" ]] && rm -rf "$SCRATCH"
  [[ -n "${REAL_ROOT:-}" ]] && rm -rf "$REAL_ROOT"
  [[ -n "${BG_DIR:-}" ]] && rm -rf "$BG_DIR"
  return 0
}
trap cleanup_all EXIT

SENTINEL="SNTLkeyAbC123xYz9876QwErTy"   # synthesized, never a real credential
SUT="$TARGET"                           # the script under test; predicates re-point it at a mutant
EXTRA_TOKENS_SEEN=""

# ---------------------------------------------------------------------------------------------
# Fixture: one case = one scratch dir with every stub and fixture file the script's seams need.
# ---------------------------------------------------------------------------------------------
new_case() {
  clean_host_state_slot
  WORK="$(mktemp -d)"
  assert_fixture_dir "$WORK"
  mkdir -p "$WORK/state"
  TRACE="$WORK/trace"; LOGTRACE="$WORK/logtrace"; PHONETRACE="$WORK/phonetrace"
  KEYFILE="$WORK/luks-env"; STAMP="$WORK/state/luks-key-probe.stamp"
  MEMINFO="$WORK/meminfo"; OOMADJ="$WORK/oom_score_adj"
  : > "$TRACE"; : > "$LOGTRACE"; : > "$PHONETRACE"
  : > "$WORK/arglog"; : > "$WORK/envlog"; : > "$WORK/fmlog"; : > "$WORK/stampseen"
  : > "$OOMADJ"

  # The key file the script reads: one variable, the synthesized sentinel.
  printf 'INNGEST_REDIS_LUKS_KEY=%s\n' "$SENTINEL" > "$KEYFILE"
  printf '%s' "$SENTINEL" > "$WORK/validkey"
  printf 'MemTotal:        4000000 kB\nMemAvailable:    3000000 kB\n' > "$MEMINFO"
  printf '/dev/mapper/inngest-data\n' > "$WORK/findmnt.out"
  printf '/dev/mapper/inngest-data is active and is in use.\n  type:    LUKS2\n  device:  /dev/sdz1\n' > "$WORK/status.out"
  printf '11111111-2222-3333-4444-555555555555\n' > "$WORK/uuid.out"
  printf 'LUKS header information\nKeyslots:\n  0: luks2\n\tKey:        512 bits\n\tPBKDF:      pbkdf2\n' > "$WORK/dump.out"

  cat > "$WORK/cs.sh" <<'EOF'
#!/usr/bin/env bash
# cryptsetup stub. Records argv + environment per call, and on the proof call drains stdin into
# keyrec so the suite can assert the EXACT bytes that arrived on the pipe.
sub="${1:-}"
printf '%s\n' "$*" >> "$STUB_DIR/arglog"
env >> "$STUB_DIR/envlog"
[ -f "${STUB_STAMP:-/nonexistent}" ] && { printf '%s|%s\n' "$sub" "$(cat "$STUB_STAMP")" >> "$STUB_DIR/stampseen"; }
case "$sub" in
  status)
    # exact production argv: status --disable-locks <mapper> (3 words, operand not an option)
    [ "$#" -eq 3 ] && [ "${2:-}" = "--disable-locks" ] && [ -n "${3:-}" ] && [ "${3#-}" = "${3}" ] || exit 98
    [ "${STUB_HANG:-}" = status ] && exec sleep 60
    [ -n "${STUB_RC_STATUS:-}" ] && exit "$STUB_RC_STATUS"
    cat "$STUB_DIR/status.out"; exit 0 ;;
  luksUUID)
    [ "$#" -eq 3 ] && [ "${2:-}" = "--disable-locks" ] && [ "${3:-}" = "$(sed -n 's/^ *device: *//p' "$STUB_DIR/status.out")" ] || exit 98
    [ -n "${STUB_RC_UUID:-}" ] && exit "$STUB_RC_UUID"
    cat "$STUB_DIR/uuid.out"; exit 0 ;;
  isLuks)
    [ "$#" -eq 3 ] && [ "${2:-}" = "--disable-locks" ] && [ "${3:-}" = "$(sed -n 's/^ *device: *//p' "$STUB_DIR/status.out")" ] || exit 98
    exit "${STUB_RC_ISLUKS:-0}" ;;
  luksDump)
    [ "$#" -eq 3 ] && [ "${2:-}" = "--disable-locks" ] && [ "${3:-}" = "$(sed -n 's/^ *device: *//p' "$STUB_DIR/status.out")" ] || exit 98
    [ -n "${STUB_RC_DUMP:-}" ] && exit "$STUB_RC_DUMP"
    cat "$STUB_DIR/dump.out"; exit 0 ;;
  luksOpen)
    # Refuse any argv shape other than the production proof call (exit 98): a mutated call site
    # must RED here rather than be silently accepted by a stub that ignores its arguments.
    if [ "${2:-}" != "--test-passphrase" ] || [ "${3:-}" != "--disable-locks" ] \
       || [ "${4:-}" != "--key-file" ] || [ "${5:-}" != "-" ] || [ -z "${6:-}" ]; then exit 98; fi
    cat > "$STUB_DIR/keyrec"
    [ "${STUB_HANG:-}" = kdf ] && exec sleep 60
    [ -n "${STUB_RC_KDF:-}" ] && exit "$STUB_RC_KDF"
    cmp -s "$STUB_DIR/keyrec" "$STUB_DIR/validkey" && exit 0
    exit 2 ;;
  *) exit 97 ;;
esac
EOF
  cat > "$WORK/fm.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/fmlog"
[ "$*" = "-no SOURCE -T /mnt/data" ] || exit 97
[ "${STUB_HANG:-}" = findmnt ] && exec sleep 60
[ -n "${STUB_RC_FINDMNT:-}" ] && exit "$STUB_RC_FINDMNT"
cat "$STUB_DIR/findmnt.out"
EOF
  cat > "$WORK/logger.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOGTRACE"
EOF
  cat > "$WORK/phone.sh" <<EOF
#!/usr/bin/env bash
printf 'argc=%s argv3=%s :: %s\n' "\$#" "\${3:-}" "\$*" >> "$PHONETRACE"
EOF
  # The flag_set recorder: every flag transition the script attempts lands in TRACE.
  cat > "$WORK/flagset.sh" <<EOF
#!/usr/bin/env bash
printf 'flag:%s\n' "\$1" >> "$TRACE"
exit 0
EOF
  cat > "$WORK/sysctl.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$TRACE"
EOF
  cat > "$WORK/redis.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(printf '%s' "\$1" | tr '[:upper:]' '[:lower:]')" >> "$TRACE"
EOF
  cat > "$WORK/nft.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "$WORK/curl.sh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in '%{http_code}') printf '200'; exit 0 ;; esac; done
printf '%s' '{"data":{"functions":[{"id":"fn-1"}]}}'
EOF
  chmod +x "$WORK"/*.sh
}

end_case() { rm -rf "$WORK"; clean_host_state_slot; WORK=""; }

# The host-default state slot is the noop-throttle stamp's anchor when a seam is refused; clear it
# around every case, guarded (it is root-owned on a runner and must never be the reason a case fails).
clean_host_state_slot() {
  rm -f /var/lock/inngest-cutover-flip.state 2>/dev/null || true
  rm -f /var/lock/inngest-cutover-flip.state.noop-emitted 2>/dev/null || true
}

# run_tick <flag> [VAR=val ...] — one run of the real script; sets RC, STDOUT/STDERR files.
# RUN_PREFIX wraps the run (an outer kill bound); SEAM_FLAG is the argv gate (empty = production).
RUN_PREFIX=""
SEAM_FLAG="--fixture-seams"
RC=0
ENVA=()
build_env() {
  ENVA=(CUTOVER_FLIP_FLAG="$1"
    CUTOVER_SYSTEMCTL_CMD="$WORK/sysctl.sh"
    CUTOVER_REDIS_CLI_CMD="$WORK/redis.sh"
    CUTOVER_FLAG_SET_CMD="$WORK/flagset.sh"
    CUTOVER_LOGGER_CMD="$WORK/logger.sh"
    INNGEST_CUTOVER_STATE="$WORK/state.json"
    INNGEST_CUTOVER_LATCH="$WORK/latch/flip-done.latch"
    INNGEST_CUTOVER_LATCH_MOUNT=""
    CUTOVER_CURL_CMD="$WORK/curl.sh"
    CUTOVER_NFT_CMD="$WORK/nft.sh"
    CUTOVER_PHONE_HOME_CMD="$WORK/phone.sh"
    CUTOVER_DONE_OWNER_MARKER="$WORK/owner/done-owner"
    CUTOVER_VERIFY_WINDOW_S=0
    CUTOVER_VERIFY_INTERVAL_S=0
    CUTOVER_LUKS_KEY_FILE="$KEYFILE"
    CUTOVER_LUKS_PROBE_STAMP="$STAMP"
    CUTOVER_CRYPTSETUP_CMD="$WORK/cs.sh"
    CUTOVER_FINDMNT_CMD="$WORK/fm.sh"
    CUTOVER_MEMINFO="$MEMINFO"
    CUTOVER_OOM_ADJ_PATH="$OOMADJ"
    STUB_DIR="$WORK"
    STUB_STAMP="$STAMP")
}
run_tick() {
  local flag="$1"; shift
  local -a extra=("$@")
  local -a pre=()
  local -a gate=()
  if [[ -n "$RUN_PREFIX" ]]; then read -r -a pre <<< "$RUN_PREFIX"; fi
  if [[ -n "$SEAM_FLAG" ]]; then gate=("$SEAM_FLAG"); fi
  build_env "$flag"
  RC=0
  ${pre[@]+"${pre[@]}"} env "${ENVA[@]}" ${extra[@]+"${extra[@]}"} \
      bash "$SUT" ${gate[@]+"${gate[@]}"} </dev/null >"$WORK/stdout" 2>"$WORK/stderr" || RC=$?
}

now_s() { printf '%(%s)T' -1; }

# probe_summary — "<n logger rows>:<logger detail>:<n phone rows>:<phone detail>:<stamp token>".
# The logger row and the phone-home row must agree; both are plain text, never JSON.
probe_summary() {
  local nl np lrow prow stok
  nl="$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
  np="$(grep -c 'argv3=SOLEUR_INNGEST_LUKS_KEY_PROBE' "$PHONETRACE" || true)"
  lrow="$(grep 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" | sed 's/^-t inngest-cutover-flip SOLEUR_INNGEST_LUKS_KEY_PROBE //' | paste -sd'|' || true)"
  prow="$(grep 'argv3=SOLEUR_INNGEST_LUKS_KEY_PROBE' "$PHONETRACE" | sed 's/^.* :: luks-key-probe //; s/ SOLEUR_INNGEST_LUKS_KEY_PROBE$//' | paste -sd'|' || true)"
  stok="$(cut -d' ' -f1 "$STAMP" 2>/dev/null || true)"
  printf '%s:%s:%s:%s:%s' "$nl" "$lrow" "$np" "$prow" "$stok"
}
expect_summary() { printf '1:%s:1:%s:%s' "$1" "$1" "$2"; }

# verdict <desc> <token> <rc> <at> [VAR=val ...] — one terminal-noop run, exact row on BOTH
# channels, the stamp token, exit 0 and an untouched flag.
verdict() {
  local desc="$1" tok="$2" vrc="$3" at="$4"; shift 4
  run_tick "done" "$@"
  assert_eq "$desc: tick exits 0, flag untouched, row=token=$tok rc=$vrc at=$at on both channels" \
    "0|$(expect_summary "token=$tok rc=$vrc at=$at" "$tok")|" \
    "$RC|$(probe_summary)|$(paste -sd, "$TRACE")"
  EXTRA_TOKENS_SEEN="$EXTRA_TOKENS_SEEN $tok"
}

# ---------------------------------------------------------------------------------------------
# Scratch mutants (Guards 1-3): applied ONLY to copies under mktemp -d, with a pristine-copy diff.
# ---------------------------------------------------------------------------------------------
SCRATCH="$(mktemp -d)"
assert_fixture_dir "$SCRATCH"
PRISTINE="$SCRATCH/pristine.sh"
cp "$TARGET" "$PRISTINE"

# mutate <name> — reads a python body from stdin; `s` is the pristine script text, the body must
# leave the mutated text in `s`. The result is written to $SCRATCH/<name>.sh.
mutate() {
  local name="$1"
  local body
  body="$(cat)"
  python3 -I - "$PRISTINE" "$SCRATCH/$name.sh" "$body" <<'PY'
import sys
src, dst, body = sys.argv[1], sys.argv[2], sys.argv[3]
ns = {"s": open(src).read()}
exec(body, ns)
open(dst, "w").write(ns["s"])
PY
}
# mutation_landed <desc> <name> — the pristine-copy diff proves the mutation changed something.
mutation_landed() {
  if ! cmp -s "$PRISTINE" "$SCRATCH/$2.sh"; then pass "mutation landed: $1"; else fail "mutation did NOT land: $1 (a no-op mutant proves nothing)"; fi
}

# ---------------------------------------------------------------------------------------------
# Background hang cases (30 s KDF timeout is real wall time). Started now, collected later.
# Each runs in its own subshell with its own case dir and writes a result file.
# ---------------------------------------------------------------------------------------------
BG_DIR="$(mktemp -d)"
assert_fixture_dir "$BG_DIR"

# bg_hang <label> <sut> <hang-stage> <outer-bound-seconds>
bg_hang() {
  local label="$1" sut="$2" stage="$3" bound="$4"
  (
    SUT="$sut"
    new_case
    local t0 t1
    t0="$(now_s)"
    RUN_PREFIX="timeout -s KILL $bound"
    run_tick "done" STUB_HANG="$stage"
    t1="$(now_s)"
    printf '%s\n' "$RC" > "$BG_DIR/$label.rc"
    printf '%s\n' "$((t1 - t0))" > "$BG_DIR/$label.secs"
    probe_summary > "$BG_DIR/$label.summary"
    paste -sd, "$TRACE" > "$BG_DIR/$label.flag"
    end_case
  ) &
}

# ---------------------------------------------------------------------------------------------
# G1 mutant #3 (no timeout on the KDF call) is built NOW so its 40 s hang overlaps the pristine one.
# ---------------------------------------------------------------------------------------------
mutate g1_m3 <<'PY'
s = s.replace('timeout -k 5 30 "$cs" luksOpen', '"$cs" luksOpen', 1)
PY
bg_hang pristine_kdf "$TARGET" kdf 45
bg_hang pristine_status "$TARGET" status 45
bg_hang pristine_findmnt "$TARGET" findmnt 45
if ! cmp -s "$PRISTINE" "$SCRATCH/g1_m3.sh"; then
  bg_hang g1_m3_kdf "$SCRATCH/g1_m3.sh" kdf 38
fi

echo "=== inngest-luks-key-probe.test.sh: LUKS key-continuity probe (#9927) ==="

# =============================================================================================
# A. THE VERDICT MATRIX — every token reachable with its exact rc and at= literal
# =============================================================================================
echo "TEST: ok — the right key unlocks the header"
new_case
verdict "right key" ok 0 kdf
assert_eq "the stub received EXACTLY the sentinel bytes on stdin (wire assert)" "yes" \
  "$(printf '%s' "$SENTINEL" | cmp -s - "$WORK/keyrec" && echo yes || echo no)"
assert_eq "the proof call is exactly: luksOpen --test-passphrase --disable-locks --key-file - <device>" \
  "luksOpen --test-passphrase --disable-locks --key-file - /dev/sdz1" "$(grep '^luksOpen' "$WORK/arglog" | paste -sd'|' || true)"
assert_eq "the oom_score_adj shield was written (1000) before the proof" "1000" "$(cat "$OOMADJ")"
assert_eq "the stamp was written FIRST: the first cryptsetup call already saw a pending stamp" "pending" \
  "$(sed -n '1p' "$WORK/stampseen" | cut -d'|' -f2 | cut -d' ' -f1)"
assert_eq "the stamp ends as the verdict token plus an epoch" "ok" "$(cut -d' ' -f1 "$STAMP")"
end_case

echo "TEST: fail_passphrase — a wrong key (rc 2)"
new_case
printf '%s' "some-other-passphrase" > "$WORK/validkey"
verdict "wrong key" fail_passphrase 2 kdf
end_case

echo "TEST: fail_key_absent — missing file, empty value, no variable"
new_case
rm -f "$KEYFILE"
verdict "key file missing" fail_key_absent 2 key
end_case
new_case
printf 'INNGEST_REDIS_LUKS_KEY=\n' > "$KEYFILE"
verdict "empty value" fail_key_absent 1 key
end_case
new_case
printf 'SOMETHING_ELSE=1\n' > "$KEYFILE"
verdict "no key variable" fail_key_absent 1 key
assert_eq "an absent key never reaches cryptsetup or findmnt" "0:0" "$(wc -l < "$WORK/arglog" | tr -d ' '):$(wc -l < "$WORK/fmlog" | tr -d ' ')"
end_case

echo "TEST: indeterminate at=mount — findmnt failing, not a mapper, multi-line and subvol shapes"
new_case
verdict "findmnt rc 1" indeterminate 1 mount STUB_RC_FINDMNT=1
end_case
new_case
printf '/dev/sda1\n' > "$WORK/findmnt.out"
verdict "source is not a /dev/mapper device" indeterminate 0 mount
end_case
new_case
printf '/dev/sda1\n/dev/mapper/inngest-data\n' > "$WORK/findmnt.out"
verdict "multi-line findmnt output: the LAST line is the kernel-served layer" ok 0 kdf
assert_eq "the cryptsetup status call names the mapper from the last line" "status --disable-locks inngest-data" \
  "$(grep '^status' "$WORK/arglog" | sed -n '1p')"
end_case
new_case
printf '/dev/mapper/inngest-data[/sub]\n' > "$WORK/findmnt.out"
verdict "a [subvol] suffix is stripped from the mapper name" ok 0 kdf
assert_eq "the cryptsetup status call names the bare mapper" "status --disable-locks inngest-data" \
  "$(grep '^status' "$WORK/arglog" | sed -n '1p')"
end_case

echo "TEST: indeterminate at=status"
new_case
verdict "cryptsetup status rc 1" indeterminate 1 status STUB_RC_STATUS=1
end_case
new_case
printf '/dev/mapper/inngest-data is active.\n  type:    LUKS2\n' > "$WORK/status.out"
verdict "status output without a device: line" indeterminate 0 status
end_case

echo "TEST: header — fail_header only when isLuks ALSO exits 1"
new_case
verdict "luksUUID rc 1 and isLuks rc 1" fail_header 1 uuid STUB_RC_UUID=1 STUB_RC_ISLUKS=1
end_case
new_case
verdict "luksUUID rc 1 but isLuks rc 4 (a permission-class fault, not a header page)" indeterminate 4 uuid STUB_RC_UUID=1 STUB_RC_ISLUKS=4
end_case
new_case
verdict "luksUUID rc 1 but isLuks rc 0 (the second read disagrees)" indeterminate 0 uuid STUB_RC_UUID=1 STUB_RC_ISLUKS=0
end_case
new_case
verdict "luksUUID rc 4" indeterminate 4 uuid STUB_RC_UUID=4
end_case
new_case
verdict "luksUUID rc 127" indeterminate 127 uuid STUB_RC_UUID=127
end_case
new_case
: > "$WORK/uuid.out"
verdict "luksUUID rc 0 with an empty value" indeterminate 0 uuid
end_case

echo "TEST: memory pre-check from luksDump"
new_case
verdict "luksDump rc 1" indeterminate 1 mem STUB_RC_DUMP=1
end_case
new_case
printf 'Keyslots:\n  0: luks2\n\tPBKDF:      argon2id\n\tMemory:     1048576\n  1: luks2\n\tMemory:     262144\n' > "$WORK/dump.out"
printf 'MemAvailable:    1000000 kB\n' > "$MEMINFO"
verdict "argon2id keyslot (max 1048576 KiB) with 1000000 KiB available is too tight: no KDF" indeterminate 0 mem
assert_eq "a low-memory verdict never reaches the KDF" "0" "$(grep -c '^luksOpen' "$WORK/arglog" || true)"
end_case
new_case
printf 'Keyslots:\n  0: luks2\n\tMemory:     1048576\n  1: luks2\n\tMemory:     262144\n' > "$WORK/dump.out"
printf 'MemAvailable:    1310720 kB\n' > "$MEMINFO"
verdict "available == largest keyslot memory + 262144 KiB runs the KDF" ok 0 kdf
end_case
new_case
printf 'MemTotal:        4000000 kB\n' > "$MEMINFO"
verdict "no MemAvailable line" indeterminate 0 mem
end_case
new_case
rm -f "$MEMINFO"
verdict "meminfo unreadable" indeterminate 0 mem
end_case

echo "TEST: indeterminate at=shield — the oom_score_adj write is refused"
new_case
verdict "shield refused" indeterminate 1 shield CUTOVER_OOM_ADJ_PATH="$WORK/no-such-dir/oom_score_adj"
assert_eq "a refused shield never reaches the KDF" "0" "$(grep -c '^luksOpen' "$WORK/arglog" || true)"
end_case

echo "TEST: indeterminate at=kdf — anything but rc 0 and rc 2"
new_case
verdict "KDF rc 1" indeterminate 1 kdf STUB_RC_KDF=1
end_case
new_case
verdict "KDF rc 4" indeterminate 4 kdf STUB_RC_KDF=4
end_case

echo "TEST: indeterminate — a missing tool is 127 and never a verdict about the key"
new_case
verdict "cryptsetup binary absent" indeterminate 127 status CUTOVER_CRYPTSETUP_CMD="$WORK/absent-cryptsetup"
end_case
new_case
verdict "findmnt and cryptsetup both absent" indeterminate 127 mount \
  CUTOVER_FINDMNT_CMD="$WORK/absent-findmnt" CUTOVER_CRYPTSETUP_CMD="$WORK/absent-cryptsetup"
end_case
new_case
run_tick "done" CUTOVER_LOGGER_CMD="$WORK/absent-logger"
assert_eq "an absent logger loses only the logger copy: the phone-home row still carries the verdict" \
  "0:1:token=ok rc=0 at=kdf" "$RC:$(grep -c 'argv3=SOLEUR_INNGEST_LUKS_KEY_PROBE' "$PHONETRACE" || true):$(grep 'argv3=SOLEUR_INNGEST_LUKS_KEY_PROBE' "$PHONETRACE" | sed 's/^.* :: luks-key-probe //; s/ SOLEUR_INNGEST_LUKS_KEY_PROBE$//')"
end_case

echo "TEST: the three hang cases (timeouts 4 s, 4 s, 30 s) collected from the background batch"
wait
assert_eq "findmnt hangs: killed at its 4 s bound, indeterminate at=mount rc=124, tick exits 0 inside 20 s" \
  "0|$(expect_summary "token=indeterminate rc=124 at=mount" indeterminate)|" \
  "$(cat "$BG_DIR/pristine_findmnt.rc")|$(cat "$BG_DIR/pristine_findmnt.summary")|$(cat "$BG_DIR/pristine_findmnt.flag")"
assert_eq "cryptsetup status hangs: killed at its 4 s bound, indeterminate at=status rc=124, tick exits 0" \
  "0|$(expect_summary "token=indeterminate rc=124 at=status" indeterminate)|" \
  "$(cat "$BG_DIR/pristine_status.rc")|$(cat "$BG_DIR/pristine_status.summary")|$(cat "$BG_DIR/pristine_status.flag")"
assert_eq "the KDF hangs: killed at its 30 s bound, indeterminate at=kdf rc=124, tick exits 0, flag untouched" \
  "0|$(expect_summary "token=indeterminate rc=124 at=kdf" indeterminate)|" \
  "$(cat "$BG_DIR/pristine_kdf.rc")|$(cat "$BG_DIR/pristine_kdf.summary")|$(cat "$BG_DIR/pristine_kdf.flag")"
if [[ "$(cat "$BG_DIR/pristine_kdf.secs" 2>/dev/null || echo 999)" -lt 42 ]]; then
  pass "the hung KDF tick finished inside 42 s (30 s bound + kill grace + emit bounds), far under TimeoutStartSec=420"
else
  fail "the hung KDF tick took $(cat "$BG_DIR/pristine_kdf.secs" 2>/dev/null) s"
fi

echo "TEST: the closed vocabulary — every token is reached by the matrix"
assert_eq "tokens reached: fail_header fail_key_absent fail_passphrase indeterminate ok" \
  "fail_header fail_key_absent fail_passphrase indeterminate ok" \
  "$(printf '%s\n' $EXTRA_TOKENS_SEEN | sort -u | paste -sd' ')"

# =============================================================================================
# B. CADENCE — stamp semantics
# =============================================================================================
seed_stamp() { printf '%s %s\n' "$1" "$2" > "$STAMP"; }
echo "TEST: cadence — due / not due by stamp token and age"
new_case
run_tick "done"
assert_eq "no stamp: the probe runs (first tick after delivery)" "1" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
seed_stamp ok "$(( $(now_s) - 23 * 3600 ))"
run_tick "done"
assert_eq "an ok stamp 23 h old: skip (no row, no cryptsetup call)" "0:0" \
  "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true):$(wc -l < "$WORK/arglog" | tr -d ' ')"
end_case
new_case
seed_stamp ok "$(( $(now_s) - 25 * 3600 ))"
run_tick "done"
assert_eq "an ok stamp 25 h old: probe" "1" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
seed_stamp fail_passphrase "$(( $(now_s) - 59 * 60 ))"
run_tick "done"
assert_eq "a non-ok stamp 59 min old: skip" "0" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
seed_stamp indeterminate "$(( $(now_s) - 61 * 60 ))"
run_tick "done"
assert_eq "a non-ok stamp 61 min old: probe (hourly retry after a non-ok token)" "1" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
seed_stamp pending "$(( $(now_s) - 30 ))"
run_tick "done"
assert_eq "a pending stamp 30 s old counts as non-ok: skip" "0" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
seed_stamp ok "$(( $(now_s) + 7200 ))"
run_tick "done"
assert_eq "a future-dated stamp is treated as unparsable: due once" "1" "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
printf 'garbage\n' > "$STAMP"
run_tick "done"
assert_eq "an unparsable stamp is due once and is rewritten as a well-formed verdict" "1:ok" \
  "$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true):$(cut -d' ' -f1 "$STAMP")"
end_case

echo "TEST: a pending stamp left by a dead run is reported once as at=died (no KDF on that tick)"
new_case
seed_stamp pending "$(( $(now_s) - 7200 ))"
run_tick "done"
assert_eq "an hour-old pending stamp: one indeterminate rc=0 at=died row on both channels, no cryptsetup call, stamp now indeterminate" \
  "0|$(expect_summary 'token=indeterminate rc=0 at=died' indeterminate)|0" \
  "$RC|$(probe_summary)|$(wc -l < "$WORK/arglog" 2>/dev/null | tr -d ' ')"
end_case

echo "TEST: an upstream pipeline stage that fails is indeterminate, never a verdict on the key"
new_case
mkdir -p "$WORK/shim"
printf '#!/bin/sh\nexit 1\n' > "$WORK/shim/head"
chmod +x "$WORK/shim/head"
verdict "head fails: cryptsetup is fed an empty key, so the row is indeterminate at=key (not fail_passphrase)" indeterminate 1 key PATH="$WORK/shim:$PATH"
end_case
new_case
verdict "key file is a directory (grep rc 2 with the path present): a read fault, not an absent key" indeterminate 2 key CUTOVER_LUKS_KEY_FILE="$WORK"
end_case

echo "TEST: a probe that dies mid-run leaves a stamp that blocks the next 30 s re-run"
new_case
RUN_PREFIX="timeout -s KILL 2"
run_tick "done" STUB_HANG=status
RUN_PREFIX=""
assert_eq "the killed probe left a pending stamp" "pending" "$(cut -d' ' -f1 "$STAMP" 2>/dev/null || echo MISSING)"
: > "$WORK/arglog"
run_tick "done"
assert_eq "the immediate re-run is blocked: no cryptsetup call, no row" "0:0" \
  "$(wc -l < "$WORK/arglog" | tr -d ' '):$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case

# pred_pending_skip <script>: an unrecordable pending write SKIPS the probe (Guard 1 row 7).
pred_pending_skip() {
  SUT="$1"
  new_case
  run_tick "done" CUTOVER_LUKS_PROBE_STAMP="$WORK/no-such-dir/stamp"
  local calls rows flag
  calls="$(wc -l < "$WORK/arglog" | tr -d ' ')"
  rows="$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
  flag="$(paste -sd, "$TRACE")"
  end_case
  SUT="$TARGET"
  [[ "$RC" -eq 0 && "$calls" == "0" && "$rows" == "0" && -z "$flag" ]]
}
echo "TEST: an unwritable stamp SKIPS the probe (never a KDF every 30 s)"
assert_true "pending-write failure: probe skipped, no cryptsetup call, no row, exit 0, flag untouched" pred_pending_skip "$TARGET"

# =============================================================================================
# C. GUARD 1 — the probe cannot change the FSM
# =============================================================================================
echo "TEST: Guard 1 — byte-identical tick across the four terminal arms and every failure mode"
# normalize <logtrace>: drop probe rows, mask the per-run start_ts.
normalize() { grep -v 'SOLEUR_INNGEST_LUKS_KEY_PROBE\|luks-key-probe' "$1" | sed 's/"start_ts":"[^"]*"/"start_ts":"X"/' || true; }
# snapshot — everything the FSM owns: exit status, flag trace, normalized rows, state slot.
snapshot() {
  printf 'rc=%s\nflag=%s\n--log\n%s\n--phone\n%s\n--state\n%s\n' "$RC" "$(paste -sd, "$TRACE")" \
    "$(normalize "$LOGTRACE")" "$(normalize "$PHONETRACE")" \
    "$(sed 's/"start_ts":"[^"]*"/"start_ts":"X"/' "$WORK/state.json" 2>/dev/null || true)"
}
isolation_arm() {
  local arm="$1" mode="$2"; shift 2
  local ref got
  new_case
  seed_stamp ok "$(now_s)"
  run_tick "$arm"
  ref="$(snapshot)"
  end_case
  new_case
  run_tick "$arm" "$@"
  got="$(snapshot)"
  local rows
  rows="$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
  end_case
  [[ "$ref" == "$got" && "$rows" == "1" ]]
}
for arm in "done" "rolled-back" "aborted" ""; do
  label="${arm:-unset}"
  assert_true "arm '$label': a FAILING cryptsetup leaves exit, flag, FSM rows and state slot byte-identical to the no-probe run" \
    isolation_arm "$arm" fail STUB_RC_STATUS=1
  assert_true "arm '$label': ABSENT cryptsetup and findmnt (127) leave the tick byte-identical" \
    isolation_arm "$arm" absent CUTOVER_CRYPTSETUP_CMD=/nonexistent/none CUTOVER_FINDMNT_CMD=/nonexistent/none
  assert_true "arm '$label': a SUCCESSFUL probe leaves the tick byte-identical (compliant path not over-blocked)" \
    isolation_arm "$arm" ok
done

echo "TEST: Guard 1 — the probe is NOT reached from armed/flipping/flushed/reflush/rollback"
not_reached() {
  local flag="$1"; shift
  new_case
  run_tick "$flag" "$@"
  local rows calls
  rows="$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
  calls="$(wc -l < "$WORK/arglog" | tr -d ' ')"
  end_case
  [[ "$rows" == "0" && "$calls" == "0" ]]
}
assert_true "armed (forward flip): no probe row, no cryptsetup call" not_reached armed CUTOVER_REDIS_DBSIZE=0
assert_true "flipping (dbsize != 0 abort): no probe" not_reached flipping CUTOVER_REDIS_DBSIZE=5
assert_true "flushed (post-flush resume): no probe" not_reached flushed
assert_true "reflush (bare, refused): no probe" not_reached reflush
assert_true "rollback: no probe" not_reached rollback

# The must-PASS non-canonical rows: the probe skipped (stamp not due), and the noop throttle
# suppressing emit_state. Both must leave the same flag and rows as no probe at all.
echo "TEST: Guard 1 must-PASS — skipped probe and throttled noop leave flag and rows unchanged"
new_case
seed_stamp ok "$(now_s)"
run_tick "done"
assert_eq "stamp not due: probe skipped, flag untouched, exit 0" "0||0" "$RC|$(paste -sd, "$TRACE")|$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
end_case
new_case
touch "$WORK/state.json.noop-emitted"
run_tick "done"
assert_eq "the noop throttle suppresses emit_state; the probe still runs and the flag is untouched" "0||1" \
  "$RC|$(paste -sd, "$TRACE")|$(grep -c 'SOLEUR_INNGEST_LUKS_KEY_PROBE' "$LOGTRACE" || true)"
assert_eq "the throttled noop emitted no FSM row of its own" "0" "$(grep -c 'noop-done' "$LOGTRACE" || true)"
end_case


# RECORDER SELF-TEST. "The probe never calls flag_set" is only as good as the recorder that would
# have seen it. recorder_works <body> installs <body> as the flag_set seam and demands that a real
# armed->flipping transition is observed in the trace; a no-op recorder must therefore FAIL it.
recorder_works() {
  local mode="$1"
  new_case
  if [[ "$mode" == "noop" ]]; then printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/flagset.sh"; fi
  run_tick armed CUTOVER_REDIS_DBSIZE=0
  local seen
  seen="$(grep -c '^flag:flipping$' "$TRACE" || true)"
  end_case
  [[ "$seen" -ge 1 ]]
}
echo "TEST: Guard 1 harness — the flag_set recorder is proven able to record (and a no-op one is caught)"
assert_true "the real recorder observes the armed->flipping transition" recorder_works real
if recorder_works noop; then
  fail "RECORDER SELF-TEST BROKEN: a no-op flag_set recorder still 'observed' a transition"
else
  pass "a no-op flag_set recorder is caught by the recorder self-test (a recorder that cannot record proves nothing)"
fi

# --- the disarm, tested OUTSIDE the `|| true` context -------------------------------------------
# Inside `( f ) || true` errexit and the ERR trap are suppressed in the subshell, so a failing
# command cannot abort the body even without the disarm. The disarm only matters for a call outside
# that context, which is therefore what this predicate exercises: source the script, install the
# FSM's ERR trap, call the wrapper bare in a subshell with a failing cryptsetup, and demand the
# flag recorder never fires.
pred_disarm() {
  local sut="$1" out rc flag
  SUT="$sut"
  new_case
  build_env "done"
  rc=0
  out="$(env "${ENVA[@]}" STUB_RC_STATUS=1 bash -c '
    source "$1" --fixture-seams
    trap on_unexpected_exit ERR
    ( luks_key_probe_tick )
    echo REACHED' _ "$sut" 2>/dev/null </dev/null)" || rc=$?
  flag="$(paste -sd, "$TRACE")"
  end_case
  SUT="$TARGET"
  [[ "$rc" -eq 0 && "$out" == *REACHED* && -z "$flag" ]]
}
echo "TEST: Guard 1 — the disarm holds OUTSIDE the || true context"
assert_true "a bare call with a failing cryptsetup never fires the ERR trap: flag untouched, caller continues" pred_disarm "$TARGET"

# --- static predicates ----------------------------------------------------------------------
nocomments() { sed -E 's/(^|[[:space:]])#.*$/\1/' "$1"; }
# The probe region: from its first helper to the closing brace of luks_key_probe_tick.
probe_region() {
  nocomments "$1" | awk '
    /^luks_probe_stamp_write\(\) \{/ { on=1 }
    on { print }
    /^luks_key_probe_tick\(\) \{/ { tick=1 }
    tick && /^\}/ { exit }'
}
# The tick function alone (the helpers carry no key).
tick_body() {
  nocomments "$1" | awk '/^luks_key_probe_tick\(\) \{/{on=1} on{print} on&&/^\}/{exit}'
}

# pred_callsites: the wrapper appears exactly at the tail of the four terminal noop arms, after each
# arm's own emit_state, in the production `( … ) >/dev/null 2>&1 || true` form, and nowhere else
# (in particular never in emit_state, flag_set, run_preflush_flip or a non-terminal arm).
pred_callsites() {
  local got want
  got="$(nocomments "$1" | awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { fn=$1; sub(/\(\)/,"",fn); arm="" }
    fn=="run_flip" && /^    [^[:space:]]+\)[[:space:]]*$/ { arm=$1; sub(/\)$/,"",arm) }
    /luks_key_probe_tick/ && !/^luks_key_probe_tick\(\) \{/ {
      line=$0; gsub(/^[[:space:]]+/,"",line)
      printf "%s:%s|%s|after=%s\n", fn, arm, line, prev
    }
    NF { split($0, w, " "); prev=w[1] }' | sort)"
  want="$(printf '%s\n' \
    'run_flip:*|( luks_key_probe_tick ) >/dev/null 2>&1 || true|after=emit_state' \
    'run_flip:aborted|( luks_key_probe_tick ) >/dev/null 2>&1 || true|after=emit_state' \
    'run_flip:done|( luks_key_probe_tick ) >/dev/null 2>&1 || true|after=emit_state' \
    'run_flip:rolled-back|( luks_key_probe_tick ) >/dev/null 2>&1 || true|after=emit_state' | sort)"
  [[ "$got" == "$want" ]]
}

# pred_externals: every external command in the probe is under `timeout -k 5 <n>` (or a shell
# builtin), no sleep/until/while-true, no flag_set/emit_state, and enough timeout sites exist that
# the census cannot be satisfied by an empty extraction.
pred_externals() {
  local region bare unwrapped n
  region="$(probe_region "$1")"
  bare="$(printf '%s\n' "$region" | grep -E '(^|[|;&(]|\$\()[[:space:]]*(grep|sed|head|tr|date|stat|cat|awk|tail|mkdir|rm|touch|sleep|curl|logger|cryptsetup|findmnt|sort|wc|cut|doppler|systemctl|blkid|ls|dmsetup|lsblk|ps|flock|jq|base64|od|xxd|dd|readlink|nice|ionice)[[:space:]]' || true)"
  unwrapped="$(printf '%s\n' "$region" | grep -E '"\$cs"|"\$fm"|"\$\{CUTOVER_(LOGGER|PHONE_HOME)_CMD' | grep -vE 'timeout -k 5 [0-9]+ ("\$cs"|"\$fm"|"\$\{CUTOVER_(LOGGER|PHONE_HOME)_CMD)' || true)"
  n="$(printf '%s\n' "$region" | grep -cE 'timeout -k 5 [0-9]+ ' || true)"
  [[ -z "$bare" && -z "$unwrapped" && "$n" -ge 12 ]]
}
pred_no_fsm_or_wait() {
  local region
  region="$(probe_region "$1")"
  ! printf '%s\n' "$region" | grep -qE '\b(flag_set|emit_state|sleep|until|stop_server|start_server)\b|while[[:space:]]+(:|true)|\bfor\b'
}

# pred_g2_static: the Guard 2 shape. Exactly one statement carries --key-file and it is the
# canonical sed|head|tr|cryptsetup pipeline; no other statement reads the key value; exactly one
# luksOpen call; no here-string anywhere in the probe.
pred_g2_static() {
  local body stmts keystmt n_key n_open
  body="$(tick_body "$1")"
  stmts="$(printf '%s\n' "$body" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g')"
  keystmt="$(printf '%s\n' "$stmts" | grep -- '--key-file' || true)"
  n_key="$(printf '%s\n' "$stmts" | grep -c -- '--key-file' || true)"
  n_open="$(printf '%s\n' "$body" | grep -c 'luksOpen' || true)"
  [[ "$n_key" == "1" && "$n_open" == "1" ]] || return 1
  [[ "$keystmt" =~ ^timeout\ -k\ 5\ [0-9]+\ sed\ -n\ \'s/\^INNGEST_REDIS_LUKS_KEY=//p\'\ \"\$keyfile\"\ 2\>/dev/null\ \|\ timeout\ -k\ 5\ [0-9]+\ head\ -n\ 1\ \|\ timeout\ -k\ 5\ [0-9]+\ tr\ -d\ \'\\n\'\ \|\ timeout\ -k\ 5\ [0-9]+\ \"\$cs\"\ luksOpen\ --test-passphrase\ --disable-locks\ --key-file\ -\ \"\$dev\"\ \>/dev/null\ 2\>\&1$ ]] || return 1
  # Every OTHER statement that names the key variable must be the presence test (grep -q).
  local others
  others="$(printf '%s\n' "$stmts" | grep 'INNGEST_REDIS_LUKS_KEY' | grep -v -- '--key-file' | grep -v "^timeout -k 5 [0-9]* grep -q '\^INNGEST_REDIS_LUKS_KEY=\.' \"\$keyfile\" 2>/dev/null\$" || true)"
  [[ -z "$others" ]] || return 1
  # ...and so is every statement that names the key FILE: a read of it into a variable or a second
  # reader is a key sink the name-keyed check above cannot see.
  local kf
  kf="$(printf '%s\n' "$stmts" | grep -F '$keyfile' | grep -v -- '--key-file' | grep -v "^timeout -k 5 [0-9]* grep -q '\^INNGEST_REDIS_LUKS_KEY=\.' \"\$keyfile\" 2>/dev/null\$" | grep -v '^if \[\[ -e "\$keyfile" \]\]; then$' | grep -v '^local keyfile=' || true)"
  [[ -z "$kf" ]] || return 1
  ! probe_region "$1" | grep -q '<<<'
}

# Wire/census/xtrace helpers (runtime).
wire_ok() { printf '%s' "$SENTINEL" | cmp -s - "$WORK/keyrec"; }
pred_g2_wire() {
  SUT="$1"
  new_case
  run_tick "done"
  local sum opens good
  sum="$(probe_summary)"
  opens="$(grep -c '^luksOpen' "$WORK/arglog" || true)"
  good="no"; wire_ok && good="yes"
  end_case
  SUT="$TARGET"
  [[ "$sum" == "$(expect_summary 'token=ok rc=0 at=kdf' ok)" && "$opens" == "1" && "$good" == "yes" ]]
}
# census_clean: no file under the case dir other than the key file, the stub comparator and the
# stub's received-bytes record contains the sentinel (logger, phone-home, stamp, argv log, env dump,
# state slot, stdout, stderr ...).
census_clean() {
  local hits
  hits="$(grep -rlF -- "$SENTINEL" "$WORK" 2>/dev/null | grep -v -e "/luks-env$" -e "/validkey$" -e "/keyrec$" || true)"
  [[ -z "$hits" ]]
}
pred_g2_census() {
  SUT="$1"
  new_case
  run_tick "done"
  local ok1=1
  census_clean || ok1=0
  end_case
  new_case
  printf '%s' "a-different-passphrase" > "$WORK/validkey"
  run_tick "done"
  local ok2=1
  census_clean || ok2=0
  end_case
  SUT="$TARGET"
  [[ "$ok1" == "1" && "$ok2" == "1" ]]
}
# pred_xtrace_off: the function is entered under `set -x` and must switch tracing off at once; the
# only trace lines allowed are the two statements that precede the switch.
pred_xtrace_off() {
  local sut="$1" tr rc bad
  SUT="$sut"
  new_case
  build_env "done"
  rc=0
  env "${ENVA[@]}" bash -c '
    source "$1" --fixture-seams
    set -x
    ( luks_key_probe_tick ) 2>"$2"
    set +x
    true' _ "$sut" "$WORK/xtrace" >/dev/null 2>&1 </dev/null || rc=$?
  tr="$(cat "$WORK/xtrace" 2>/dev/null || true)"
  bad="$(printf '%s\n' "$tr" | grep -vE '^\+ (trap - ERR EXIT|set \+eEx|luks_key_probe_tick)$' | grep -v '^$' || true)"
  local leak=0
  if [[ "$tr" == *"$SENTINEL"* ]]; then leak=1; fi
  end_case
  SUT="$TARGET"
  [[ "$rc" -eq 0 && -z "$bad" && "$leak" -eq 0 ]]
}

# =============================================================================================
# D. GUARD 1/2/3 — green on the pristine script, RED on every mutant
# =============================================================================================
expect_red() {
  local desc="$1" pred="$2" name="$3"
  if "$pred" "$SCRATCH/$name.sh" >/dev/null 2>&1; then
    fail "$desc: the predicate is still GREEN against the mutant (the guard is blind to it)"
  else
    pass "$desc: RED against the mutant"
  fi
}

# NEGATIVE CONTROLS for the verdict-owning helpers (the pass()/fail() self-test at the top proves
# dispatch only): drive each helper once with an input that MUST fail and require the FAIL counter
# to move and the PASS counter not to, then unwind. Reported by printf + exit, not through fail().
pred_ctl_green() { return 0; }
_ctl_p0=$PASS
_ctl_f0=$FAIL
assert_eq "control" "a" "b" >/dev/null
assert_true "control" false >/dev/null
expect_red "control" pred_ctl_green pristine >/dev/null
if [[ "$FAIL" -ne $((_ctl_f0 + 3)) || "$PASS" -ne "$_ctl_p0" ]]; then
  printf 'FATAL: a verdict-owning helper (assert_eq, assert_true or expect_red) cannot reject a failing input (PASS=%s FAIL=%s, expected PASS=%s FAIL=%s).\n' \
    "$PASS" "$FAIL" "$_ctl_p0" "$((_ctl_f0 + 3))" >&2
  exit 1
fi
FAIL=$_ctl_f0

echo "TEST: Guard 1 — call-site set, timeouts and intrusion census (pristine green)"
assert_true "the wrapper is called from exactly the four terminal-noop arm tails, after emit_state" pred_callsites "$TARGET"
assert_true "every external command in the probe is under timeout -k 5 <n> (>=12 sites)" pred_externals "$TARGET"
assert_true "the probe holds no flag_set, emit_state, start/stop_server, sleep, until, while-true or for" pred_no_fsm_or_wait "$TARGET"

echo "TEST: Guard 1 mutation rows (scratch copies under mktemp -d)"
mutate g1_m1 <<'PY'
s = s.replace("    armed)\n", "    armed)\n      ( luks_key_probe_tick ) >/dev/null 2>&1 || true\n", 1)
PY
mutation_landed "G1-1 call added inside the armed arm" g1_m1
expect_red "G1-1 call inside the armed arm" pred_callsites g1_m1

mutate g1_m2 <<'PY'
s = s.replace("  trap - ERR EXIT\n  set +eEx\n", "", 1)
PY
mutation_landed "G1-2 disarm deleted" g1_m2
expect_red "G1-2 disarm deleted, called OUTSIDE the || true context with a failing cryptsetup" pred_disarm g1_m2
# The same deletion under the production || true context stays green — which is exactly why the
# disarm is tested outside it.
with_sut() { local s="$1"; shift; SUT="$s"; "$@"; local r=$?; SUT="$TARGET"; return $r; }
assert_true "G1-2 control: the same deletion under the production || true context stays green" \
  with_sut "$SCRATCH/g1_m2.sh" isolation_arm "done" fail STUB_RC_STATUS=1

mutation_landed "G1-3 timeout removed from the KDF call" g1_m3
expect_red "G1-3 timeout removed from the KDF call (static census)" pred_externals g1_m3
echo "  (G1-3 runtime: hung KDF, collected from the background batch)"
if [[ -f "$BG_DIR/g1_m3_kdf.rc" ]]; then
  if [[ "$(cat "$BG_DIR/g1_m3_kdf.rc")" != "0" || "$(cat "$BG_DIR/g1_m3_kdf.secs")" -ge 36 ]]; then
    pass "G1-3 runtime: without the timeout a hung cryptsetup holds the tick past the bound (RED)"
  else
    fail "G1-3 runtime: the mutant finished inside the bound — the hang case cannot see a missing timeout"
  fi
else
  fail "G1-3 runtime: the mutant hang case did not run (the mutation did not land)"
fi

mutate g1_m4 <<'PY'
s = s.replace("emit_state() {\n", "emit_state() {\n  ( luks_key_probe_tick ) >/dev/null 2>&1 || true\n", 1)
PY
mutation_landed "G1-4 second call site inside emit_state" g1_m4
expect_red "G1-4 second call site inside emit_state" pred_callsites g1_m4

mutate g1_m5 <<'PY'
s = s.replace("( luks_key_probe_tick ) >/dev/null 2>&1 || true", "( luks_key_probe_tick ) >/dev/null 2>&1")
s = s.replace('    *) luks_probe_finish indeterminate "$rc" kdf ;;\n  esac\n  return 0\n}', '    *) luks_probe_finish indeterminate "$rc" kdf ;;\n  esac\n  return 1\n}', 1)
PY
mutation_landed "G1-5 outer || true removed and the wrapper returns 1" g1_m5
pred_isolation_exit() { with_sut "$1" isolation_arm "done" ok; }
expect_red "G1-5 wrapper returns 1 with no outer || true (the tick's exit status changes)" pred_isolation_exit g1_m5

mutate g1_m7 <<'PY'
s = s.replace("luks_probe_stamp_write pending || return 0", "luks_probe_stamp_write pending || true", 1)
PY
mutation_landed "G1-7 an unrecordable pending stamp no longer skips" g1_m7
expect_red "G1-7 pending-write failure no longer skips the probe" pred_pending_skip g1_m7

echo "TEST: Guard 2 — the passphrase never leaves the pipe (pristine green)"
assert_true "static: one canonical sed|head|tr|cryptsetup --key-file - pipeline, one luksOpen, no here-string" pred_g2_static "$TARGET"
assert_true "wire: the stub received exactly the sentinel on stdin, via exactly one luksOpen call" pred_g2_wire "$TARGET"
assert_true "census: the sentinel is in no file other than the key file and the stub comparator (logger, phone-home, stamp, argv, env, state, stdout, stderr), ok and fail flows" pred_g2_census "$TARGET"
assert_true "set -x is switched off by the probe: only the two pre-switch statements are traced and no sentinel appears" pred_xtrace_off "$TARGET"

echo "TEST: Guard 2 mutation rows"
mutate g2_m1 <<'PY'
import re
s = re.sub(r"  timeout -k 5 2 sed -n 's/\^INNGEST_REDIS_LUKS_KEY=//p'.*?>/dev/null 2>&1\n",
  "  keyval=\"$(sed -n 's/^INNGEST_REDIS_LUKS_KEY=//p' \"$keyfile\")\"\n  printf '%s' \"$keyval\" | timeout -k 5 30 \"$cs\" luksOpen --test-passphrase --disable-locks --key-file - \"$dev\" >/dev/null 2>&1\n",
  s, count=1, flags=re.S)
PY
mutation_landed "G2-1 key captured into a variable, then piped" g2_m1
expect_red "G2-1 key assigned to a variable" pred_g2_static g2_m1

mutate g2_m2 <<'PY'
s = s.replace('--key-file - "$dev"', '--key-file=/tmp/k "$dev"', 1)
PY
mutation_landed "G2-2 key passed by --key-file=<path>" g2_m2
expect_red "G2-2 the call lacks --key-file - (static)" pred_g2_static g2_m2
expect_red "G2-2 the call lacks --key-file - (wire: the stub refuses the argv shape)" pred_g2_wire g2_m2

mutate g2_m3 <<'PY'
s = s.replace('  local row="token=${tok} rc=${rc} at=${at}"', '  local row="token=${tok} rc=${rc} at=${at} k=$(sed -n \'s/^INNGEST_REDIS_LUKS_KEY=//p\' "${CUTOVER_LUKS_KEY_FILE:-/etc/default/inngest-luks}")"', 1)
PY
mutation_landed "G2-3 debug log of the extracted value" g2_m3
expect_red "G2-3 a debug logger of the value puts the sentinel in the logger trace" pred_g2_census g2_m3

mutate g2_m4 <<'PY'
s = s.replace('  case "$rc" in\n    0) luks_probe_finish ok 0 kdf ;;', '  timeout -k 5 30 "$cs" luksOpen --test-passphrase --disable-locks "$dev" </dev/null >/dev/null 2>&1\n  case "$rc" in\n    0) luks_probe_finish ok 0 kdf ;;', 1)
PY
mutation_landed "G2-4 a second cryptsetup luksOpen call (a retry) without --key-file -" g2_m4
expect_red "G2-4 call census: a second luksOpen call (static)" pred_g2_static g2_m4
expect_red "G2-4 call census: a second luksOpen call (wire: exactly one luksOpen)" pred_g2_wire g2_m4

mutate g2_m7 <<'PY'
s = s.replace('  # 7. proof.', '  read -r kv < "$keyfile"\n  # 7. proof.', 1)
PY
mutation_landed "G2-7 the key file read into a variable" g2_m7
expect_red "G2-7 a statement that names the key file outside the blessed forms" pred_g2_static g2_m7

mutate g1_m8 <<'PY'
s = s.replace('  # 7. proof.', '  blkid "$dev" >/dev/null 2>&1\n  # 7. proof.', 1)
PY
mutation_landed "G1-8 a bare blkid with no timeout in the probe" g1_m8
expect_red "G1-8 the timeout census sees a bare external outside its original name list" pred_externals g1_m8

pred_upstream_fail() {
  SUT="$1"
  new_case
  mkdir -p "$WORK/shim"
  printf '#!/bin/sh\nexit 1\n' > "$WORK/shim/head"
  chmod +x "$WORK/shim/head"
  run_tick "done" PATH="$WORK/shim:$PATH"
  local sum
  sum="$(probe_summary)"
  end_case
  SUT="$TARGET"
  [[ "$sum" == "$(expect_summary 'token=indeterminate rc=1 at=key' indeterminate)" ]]
}
assert_true "pristine: a failing upstream stage is indeterminate at=key" pred_upstream_fail "$TARGET"
mutate g4_m1 <<'PY'
s = s.replace('    0:0:0|141:0:0) ;;', '    *) ;;', 1)
PY
mutation_landed "G4-1 the upstream-stage guard neutered" g4_m1
expect_red "G4-1 without the guard a failed head reads as fail_passphrase" pred_upstream_fail g4_m1

mutate g2_m5 <<'PY'
s = s.replace("  set +eEx\n", "  set +eE\n  set -x\n", 1)
PY
mutation_landed "G2-5 the probe runs under set -x" g2_m5
expect_red "G2-5 the probe left tracing on" pred_xtrace_off g2_m5

echo "TEST: Guard 2 harness rows"
# RED: change the fixture key so the sentinel never reaches the stub; the wire assert must fail.
new_case
printf 'INNGEST_REDIS_LUKS_KEY=NOTthesentinel\n' > "$KEYFILE"
printf '%s' "NOTthesentinel" > "$WORK/validkey"
run_tick "done"
if wire_ok; then fail "WIRE ASSERT BLIND: the sentinel 'reached' the stub although the fixture key was changed"; else pass "the wire assert fails when the sentinel never reaches the stub (fixture key changed)"; fi
end_case
# Must-PASS non-canonical: a key with '=', a second variable plus comment lines (first match only),
# a trailing space (outside the assumed charset; the observed behaviour is pinned).
wire_bytes() { printf '%s' "$1" | cmp -s - "$WORK/keyrec"; }
new_case
printf 'INNGEST_REDIS_LUKS_KEY=ab=cd==ef\n' > "$KEYFILE"
run_tick "done"
if wire_bytes 'ab=cd==ef'; then pass "a key containing '=' arrives byte-exact (only the variable prefix is stripped)"; else fail "a key containing '=' was altered on the way to the stub"; fi
end_case
new_case
printf 'OTHER=unrelated\n# a comment\nINNGEST_REDIS_LUKS_KEY=first\nINNGEST_REDIS_LUKS_KEY=second\n# trailing comment\n' > "$KEYFILE"
run_tick "done"
if wire_bytes 'first'; then pass "only the FIRST key match is used, other variables and comments are ignored"; else fail "the wrong line reached the stub"; fi
end_case
new_case
printf 'INNGEST_REDIS_LUKS_KEY=ab \n' > "$KEYFILE"
run_tick "done"
if wire_bytes 'ab '; then pass "a trailing space is NOT stripped (pinned; outside the random_password [A-Za-z0-9] assumption the runbook records)"; else fail "the trailing-space behaviour changed"; fi
end_case

echo "TEST: Guard 3 — seam gate and closed vocabulary (pristine green)"
NEW_SEAMS="CUTOVER_CRYPTSETUP_CMD CUTOVER_FINDMNT_CMD CUTOVER_LUKS_KEY_FILE CUTOVER_LUKS_PROBE_STAMP CUTOVER_MEMINFO CUTOVER_OOM_ADJ_PATH"
# pred_seamset: the seam names the script reads (derived by shape) equal the gate's unset list plus
# INNGEST_CUTOVER_FLIP, the six probe seams are in that list, and the list is not empty.
pred_seamset() {
  local derived list expected n
  derived="$(nocomments "$1" | grep -oE '\$\{[#!]?(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+|\$(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' | grep -oE '(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' | sort -u || true)"
  list="$(nocomments "$1" | awk '/^[[:space:]]*for[[:space:]]+_seam[[:space:]]+in/{f=1} f{print} f&&/^[[:space:]]*do[[:space:]]*$/{exit}' | grep -oE '(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' | sort -u || true)"
  expected="$(printf '%s\nINNGEST_CUTOVER_FLIP\n' "$list" | grep -vE '^$' | sort -u || true)"
  n="$(printf '%s\n' "$list" | grep -c '^' || true)"
  local s
  for s in $NEW_SEAMS; do
    printf '%s\n' "$list" | grep -qxF "$s" || return 1
  done
  [[ "$derived" == "$expected" && "$n" -ge 25 ]]
}
assert_true "the derived seam set equals the gate's list plus INNGEST_CUTOVER_FLIP, and the six probe seams are in it (>=25 names)" pred_seamset "$TARGET"

# pred_seam_refusal: WITHOUT --fixture-seams every probe seam must be ignored: nothing written at
# the seam stamp path, the seam cryptsetup/findmnt stubs never run.
pred_seam_refusal() {
  local sut="$1" wrote calls fm
  SUT="$sut"
  new_case
  SEAM_FLAG=""
  run_tick "done"
  SEAM_FLAG="--fixture-seams"
  wrote="no"; [[ -e "$STAMP" ]] && wrote="yes"
  calls="$(wc -l < "$WORK/arglog" | tr -d ' ')"
  fm="$(wc -l < "$WORK/fmlog" | tr -d ' ')"
  end_case
  SUT="$TARGET"
  [[ "$wrote" == "no" && "$calls" == "0" && "$fm" == "0" ]]
}
REFUSAL_RAN=1
if [[ "$(id -u)" == "0" ]]; then
  REFUSAL_RAN=0
  echo "SKIP: seam-refusal runtime arm — running as root, the production default stamp path would be written for real (the static seam-set predicate still ran)"
else
  assert_true "without --fixture-seams every probe seam is ignored: no stamp at the seam path, no stub cryptsetup/findmnt call" pred_seam_refusal "$TARGET"
fi

# pred_vocab: the verdict tokens and at= literals the script can emit are exactly the closed sets.
CLOSED_TOKENS="fail_header fail_key_absent fail_passphrase indeterminate ok"
CLOSED_AT="died kdf key mem mount shield status uuid"
pred_vocab() {
  local calls toks ats
  calls="$(probe_region "$1" | grep -oE 'luks_probe_finish [a-z_]+ +[^ ;]+ +[a-z]+' || true)"
  toks="$(printf '%s\n' "$calls" | awk '{print $2}' | sort -u | paste -sd' ')"
  ats="$(printf '%s\n' "$calls" | awk '{print $4}' | sort -u | paste -sd' ')"
  [[ "$toks" == "$CLOSED_TOKENS" && "$ats" == "$CLOSED_AT" ]]
}
assert_true "the script emits exactly the closed token set (ok fail_passphrase fail_header fail_key_absent indeterminate) and the at= literal set" pred_vocab "$TARGET"

echo "TEST: Guard 3 mutation rows"
mutate g3_m1 <<'PY'
s = s.replace('  local meminfo="${CUTOVER_MEMINFO:-/proc/meminfo}"\n', '  local meminfo="${CUTOVER_MEMINFO:-/proc/meminfo}"\n  local spare="${CUTOVER_SPARE_SEAM:-}"\n', 1)
PY
mutation_landed "G3-1 a new seam read without a gate entry" g3_m1
expect_red "G3-1 a seam read that is not in the for _seam list" pred_seamset g3_m1

mutate g3_m2 <<'PY'
s = s.replace("    CUTOVER_LUKS_PROBE_STAMP \\\n", "", 1)
PY
mutation_landed "G3-2 the stamp seam dropped from the unset list" g3_m2
expect_red "G3-2 list entry dropped (static seam-set)" pred_seamset g3_m2
if [[ "$REFUSAL_RAN" == "1" ]]; then
  expect_red "G3-2 list entry dropped (runtime: the seam is honoured without --fixture-seams and the stamp is written)" pred_seam_refusal g3_m2
fi

mutate g3_m3 <<'PY'
s = s.replace("luks_probe_finish fail_header 1 uuid", "luks_probe_finish fail_headr 1 uuid", 1)
PY
mutation_landed "G3-3 a token outside the closed set" g3_m3
expect_red "G3-3 a token outside the closed set" pred_vocab g3_m3

# =============================================================================================
# E. NFR1 and constants: worst-case wall time computed from the script's own literals
# =============================================================================================
echo "TEST: NFR1 — the worst-case probe duration is computed, not asserted"
REGION="$(probe_region "$TARGET")"
T_SUM="$(printf '%s\n' "$REGION" | grep -oE 'timeout -k 5 [0-9]+ ' | awk '{s+=$4} END {print s+0}')"
T_CNT="$(printf '%s\n' "$REGION" | grep -oE 'timeout -k 5 [0-9]+ ' | wc -l | tr -d ' ')"
T_WORST=$(( T_SUM + 5 * T_CNT ))
UNIT_TIMEOUT="$(grep -E '^TimeoutStartSec=' "$UNIT_SRC" | head -n1 | cut -d= -f2)"
echo "  computed: ${T_CNT} timeout sites, sum ${T_SUM}s + ${T_CNT} x 5s kill grace = ${T_WORST}s worst case; TimeoutStartSec=${UNIT_TIMEOUT}"
if [[ -n "$UNIT_TIMEOUT" && "$T_CNT" -ge 12 && $(( T_WORST * 3 )) -lt "$UNIT_TIMEOUT" ]]; then
  pass "worst case ${T_WORST}s is below TimeoutStartSec=${UNIT_TIMEOUT} with at least 3x margin"
else
  fail "worst case ${T_WORST}s (sites=${T_CNT}) leaves less than 3x margin under TimeoutStartSec=${UNIT_TIMEOUT:-unset}"
fi
assert_eq "GUARD_REV is unchanged (D7: two suites and the stale_image check pin 7761)" 'readonly GUARD_REV="7761"' \
  "$(grep -E '^readonly GUARD_REV=' "$TARGET")"
assert_eq "the unit's StateDirectory still covers the stamp path" "yes" \
  "$(grep -qE '^StateDirectory=inngest-cutover$' "$UNIT_SRC" && grep -qF '/var/lib/inngest-cutover/luks-key-probe.stamp' "$TARGET" && echo yes || echo no)"

# =============================================================================================
# F. REAL-TOOL ARM — the script's own pipeline against a file-backed LUKS2 container (no root)
# =============================================================================================
echo "TEST: real cryptsetup arm (file-backed LUKS2 container)"
REAL_RAN=0
RKEY="realKeyAbc123XyZ456"
if ! command -v cryptsetup >/dev/null 2>&1; then
  # A skip here is the fail-open class: under CI the arm that proves `tr -d '\n'` is load-bearing
  # and exercises the real tool would be silently dropped while the count pin shrinks to match.
  if [[ -n "${CI:-}" ]]; then
    printf 'FAIL: real-tool arm cannot skip under CI: cryptsetup is not installed (the infra leg installs cryptsetup-bin)\n' >&2
    exit 1
  fi
  echo "SKIP: real-tool arm — cryptsetup is not installed on this runner (explicit skip, never silent)"
elif ! command -v truncate >/dev/null 2>&1; then
  echo "SKIP: real-tool arm — truncate is not installed on this runner (explicit skip, never silent)"
else
  REAL_ROOT="$(mktemp -d)"
  assert_fixture_dir "$REAL_ROOT"
  IMG="$REAL_ROOT/disk.img"
  truncate -s 20M "$IMG"
  if printf '%s' "$RKEY" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
       --batch-mode --disable-locks --key-file - "$IMG" >/dev/null 2>&1; then
    REAL_RAN=1
  else
    if [[ -n "${CI:-}" ]]; then
      printf 'FAIL: real-tool arm cannot skip under CI: cryptsetup could not build a file-backed LUKS2 container\n' >&2
      exit 1
    fi
    echo "SKIP: real-tool arm — cryptsetup could not build a file-backed LUKS2 container here (no root / no kernel crypto); explicit skip, never silent"
  fi
fi

if [[ "$REAL_RAN" == "1" ]]; then
  realtool() { cryptsetup luksOpen --test-passphrase --disable-locks --key-file - "$IMG"; }
  rc=0; printf '%s' "$RKEY" | realtool >/dev/null 2>&1 || rc=$?
  assert_eq "real cryptsetup: the right key exits 0" "0" "$rc"
  rc=0; printf '%s' "wrongKey" | realtool >/dev/null 2>&1 || rc=$?
  assert_eq "real cryptsetup: a wrong key exits 2" "2" "$rc"
  rc=0; : | realtool >/dev/null 2>&1 || rc=$?
  assert_eq "real cryptsetup: empty stdin (a blank key) exits 1" "1" "$rc"
  rc=0; printf '%s\n' "$RKEY" | realtool >/dev/null 2>&1 || rc=$?
  assert_eq "real cryptsetup: the right key WITH a trailing newline exits 2 (why the extraction strips it)" "2" "$rc"

  # The script's whole probe against the real tool: findmnt is the stub (no mapper without root),
  # `cryptsetup status` is answered by the wrapper, every other subcommand is the REAL binary.
  cat > "$REAL_ROOT/csreal.sh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = status ]; then printf 'device:  %s\n' "$STUB_REAL_IMG"; exit 0; fi
exec cryptsetup "$@"
EOF
  chmod +x "$REAL_ROOT/csreal.sh"
  real_summary() {
    local keyline="$1" img="$2"
    SUT="${3:-$TARGET}"
    new_case
    printf '%s\n' "$keyline" > "$KEYFILE"
    run_tick "done" CUTOVER_CRYPTSETUP_CMD="$REAL_ROOT/csreal.sh" STUB_REAL_IMG="$img"
    local sum
    sum="$(probe_summary)"
    end_case
    SUT="$TARGET"
    printf '%s' "$sum"
  }
  assert_eq "the script against the real tool: the right key from the host file is ok" \
    "$(expect_summary 'token=ok rc=0 at=kdf' ok)" "$(real_summary "INNGEST_REDIS_LUKS_KEY=$RKEY" "$IMG")"
  assert_eq "the script against the real tool: a wrong key is fail_passphrase rc=2" \
    "$(expect_summary 'token=fail_passphrase rc=2 at=kdf' fail_passphrase)" "$(real_summary "INNGEST_REDIS_LUKS_KEY=notTheKey" "$IMG")"
  truncate -s 20M "$REAL_ROOT/blank.img"
  assert_eq "the script against a blank device: luksUUID rc 1 and isLuks rc 1 is fail_header" \
    "$(expect_summary 'token=fail_header rc=1 at=uuid' fail_header)" "$(real_summary "INNGEST_REDIS_LUKS_KEY=$RKEY" "$REAL_ROOT/blank.img")"
  assert_eq "the script against the real tool: a missing device is indeterminate, never a header verdict" \
    "$(expect_summary 'token=indeterminate rc=4 at=uuid' indeterminate)" "$(real_summary "INNGEST_REDIS_LUKS_KEY=$RKEY" "$REAL_ROOT/no-such.img")"

  pred_real_right_key() {
    [[ "$(real_summary "INNGEST_REDIS_LUKS_KEY=$RKEY" "$IMG" "$1")" == "$(expect_summary 'token=ok rc=0 at=kdf' ok)" ]]
  }
  assert_true "pristine: the real right key is ok" pred_real_right_key "$TARGET"
  mutate g2_m6 <<'PY'
s = s.replace("    | timeout -k 5 2 tr -d '\\n' \\\n", "", 1)
PY
  mutation_landed "G2-6 tr -d '\\n' stripped from the extraction" g2_m6
  expect_red "G2-6 without tr -d the real right key returns rc 2 (fail_passphrase)" pred_real_right_key g2_m6
fi

# --- S8: an EXACT assertion count --------------------------------------------------------------
# The inventory is fixed by this file; a count that drifts (an assertion deleted, a block silently
# skipped) is itself a RED. Bump it in the same edit that adds an assertion. Optional arms that
# skipped with an explicit marker above are subtracted by their own constants.
EXPECTED_ASSERTIONS=148
REAL_ARM_ASSERTIONS=11
REFUSAL_ARM_ASSERTIONS=2
EXPECTED=$EXPECTED_ASSERTIONS
if [[ "$REAL_RAN" != "1" ]]; then EXPECTED=$((EXPECTED - REAL_ARM_ASSERTIONS)); fi
if [[ "$REFUSAL_RAN" != "1" ]]; then EXPECTED=$((EXPECTED - REFUSAL_ARM_ASSERTIONS)); fi
if [[ "$PASS" -ne "$EXPECTED" ]]; then
  # printf + exit, NOT fail() (ADR-193): routing the count through the counter it exists to
  # protect means one edit disarms both. See the instrument self-test at the top.
  printf 'FAIL: assertion-count mismatch: %s assertions ran, expected exactly %s (real arm ran=%s, refusal arm ran=%s) — a block was added without updating this pin, or silently dropped.\n' \
    "$PASS" "$EXPECTED" "$REAL_RAN" "$REFUSAL_RAN" >&2
  exit 1
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
