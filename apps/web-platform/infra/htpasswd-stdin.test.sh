#!/usr/bin/env bash
#
# The htpasswd password-on-stdin FORM, proved against the REAL binary (argv-bearer sweep, #9757).
#
# WHY THIS SUITE EXISTS. Every other row that touches the converted htpasswd calls runs a STUB: the
# battery in tests/scripts/test-argv-bearer-sweep.sh reads the step text and a refusing stub docker, and
# a stub only proves the call is SHAPED right, never that `htpasswd -Bin <user>` with the password on
# stdin hashes the password, that `htpasswd -vi <file> <user>` verifies it, or what each exit code means.
# Those facts decide whether the conversion is a no-op or a silent outage (a hash over an EMPTY password
# makes the registry reject every pull). This suite measures them, on BOTH images the converted calls run on:
#   - ubuntu:24.04 + apache2-utils   the shipped registry host image (the cloud-init `_htp_verify` probe and the
#                                     boot-step htpasswd lines run there)
#   - httpd:2.4-alpine               the image the registry-luks-recut rehearsal step runs through `docker run`
# and, on the second, through docker itself, because docker does NOT forward the caller's stdin without
# its own `-i`: `printf pw | docker run --rm httpd htpasswd -Bin u` (no `-i`) exits 0 and hashes the EMPTY
# password. That negative control is why the workflow step carries `docker run --rm -i`.
#
# THE CONTRACT MEASURED (the registry template's `_htp_verify` probe and boot block run exactly these calls; do not loosen the rows):
#   create        printf pw | htpasswd -Bin user > file       exit 0, one `user:$2y$...` entry
#   match         printf pw | htpasswd -vi file user          exit 0
#   mismatch      wrong password                              exit 3
#   absent user   a user that is not in the file              exit 6
#   unreadable    the file cannot be read (as another uid)    exit 1
#   over 72 B     an 80-byte password hashes, and a DIFFERENT tail after byte 72 still verifies (exit 0): bcrypt truncates at 72
#                 bytes. The old `-Bbn`/`-vb` argv form truncates identically, so the conversion weakens nothing; the zot tokens
#                 are 40 characters.
#   over 256 B    a 300-byte password: `htpasswd -Bin` exits 5 ("password too long (>256)") and writes no entry.
#   and the legacy `htpasswd -vb file user pw` accepts a hash made by `-Bin` (the two forms interoperate, so a
#   host baked by the old form and verified by the new form, or the reverse, does not diverge).
#
# THE BOOT BLOCK ITSELF (rows B1-B12, ubuntu arm): the registry template's REAL boot step, rendered offline by
# registry-userdata-budget.sh and run through `bash -s` with set -euo pipefail, against the real htpasswd: file mode,
# both entries, each token verifying for its own user only, the failure arms (first call fails, SECOND call fails, empty
# pull token, empty push token), and an argv recorder proving no password or `b` option cluster reaches htpasswd's
# argument list (with a control that the same judge calls the old argv form RED). A render that works but whose block
# no longer has the stdin form is a FAILURE, never a skip: that is the regression this arm exists to catch.
#
# IMAGES ARE NAMED BY DIGEST (the manifest-list digest, measured with `docker buildx imagetools inspect`;
# MediaType application/vnd.oci.image.index.v1+json): the ubuntu pin is read from the one copy the
# rehearsal suite owns (rule-audit.yml watches it), the httpd pin is owned here. NOTE the workflow step
# itself runs the FLOATING `httpd:2.4-alpine` tag: this suite pins what it MEASURED, it does not pin the step.
#
# FAIL-CLOSED RULE. Under CI (CI=1/true or GITHUB_ACTIONS set) an absent or unreachable docker daemon, an
# image that cannot be pulled, or a fixture whose apt cycle failed is a FAILURE (infra-validation.yml
# asserts docker before the suites run; this suite must never turn that absence into a green). Locally it
# SKIPS, loudly: the skip names the cause and the number of rows NOT run, and the declared rows still count
# toward the floor. A docker-less laptop therefore reads "skipped", never "passed".
#
# Run: bash apps/web-platform/infra/htpasswd-stdin.test.sh
# Presence under apps/web-platform/infra/ IS registration (ADR-252): run-registered-suites.sh derives it.
# All passwords are synthesized per run; nothing is read from Doppler or the environment.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Canonical assert_fixture_dir (byte-identical copy: the fixture-relative ratchet recognises only this text).
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

# ── image pins ───────────────────────────────────────────────────────────────────────
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "${DIR}/git-data-runcmd-rehearsal.test.sh" 2>/dev/null | head -1)"
[ -n "$UBUNTU_BASE" ] || { printf 'FAIL SETUP: no UBUNTU_BASE pin readable from git-data-runcmd-rehearsal.test.sh\n' >&2; exit 1; }
HTTPD_IMAGE='httpd:2.4-alpine@sha256:3440c39d8d6f54fa9ad2549e5a60c19ddd435faadc29c1ad28aa795f71888889'

# Bounded apt: the in-container apt cycle for apache2-utils goes through lib/apt-bounded.sh (the infra
# census bans a raw apt-get in a .test.sh). 180 s is the budget git-data-ownership.test.sh measured for one cycle.
APT_LIB="${DIR}/lib/apt-bounded.sh"
APT_BUDGET_S=180
[ -r "$APT_LIB" ] || { echo "FAIL: ${APT_LIB} is missing — the ubuntu arm's apt cycle could not be bounded" >&2; exit 1; }
# shellcheck source=lib/apt-bounded.sh
. "$APT_LIB"

# ── counters ─────────────────────────────────────────────────────────────────────────
passes=0; fails=0; SKIPPED=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
# FAILURES is append-only and is what the verdict reads; `fails` is its mirror and is cross-checked below.
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Declared rows: 2 pins + 2 images x 11 contract rows + 2 docker-forwarding rows + 12 boot-block rows. A skipped arm still DECLARES its
# rows (they count toward the floor and are reported as skipped, never as passed).
PIN_ROWS=2
IMAGE_ROWS=11
DOCKER_I_ROWS=2
BOOT_ROWS=12   # the rendered registry boot block, run through `bash -s` in the ubuntu image (#10119)
DECLARED_ROWS=$((PIN_ROWS + 2 * IMAGE_ROWS + DOCKER_I_ROWS + BOOT_ROWS))
FLOOR=38   # a literal on purpose: it must be edited by hand when rows are added (38 = 2 + 2*11 + 2 + 12)

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────────────
# `pass`/`fail` are the machinery every row reports through; a no-op `fail` would leave the suite green
# over real defects. Drive both in both directions, then restore the counters so the totals stay exact.
# Reported with printf + exit, never through the helpers under test.
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass "instrument self-test: pass moves passes" >/dev/null
_p1=$passes
fail "instrument self-test: fail moves fails (expected; retracted immediately)" >/dev/null 2>&1
if [ "$_p1" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  printf 'FATAL: the pass/fail helpers do not count (passes %s->%s, fails %s->%s, ledger %s->%s)\n' \
    "$_p0" "$_p1" "$_f0" "$fails" "$_n0" "${#FAILURES[@]}" >&2
  exit 2
fi
passes=$_p0; fails=$_f0; FAILURES=("${FAILURES[@]:0:$_n0}")

# The row-reading helpers are instrumented the same way: a rows file is fabricated that holds one rc, and each
# comparator is required to accept the equal value and refuse a different one. A comparator that always
# answers yes would pass every contract row below.
_rv() { sed -n "s/^$1=//p" "$2" | tail -1; }
_eq() { [ "$(_rv "$1" "$3")" = "$2" ]; }
_st="$(mktemp -d "${TMPDIR}/htpst-self.XXXXXX")"; assert_fixture_dir "$_st"
printf 'probe=3\n' > "$_st/rows"
if ! _eq probe 3 "$_st/rows" || _eq probe 0 "$_st/rows" || _eq missing 3 "$_st/rows"; then
  printf 'FATAL: the rc comparator is blind (accepted a wrong value, refused the right one, or accepted a row that is absent)\n' >&2
  rm -rf "$_st"; exit 2
fi
rm -rf "$_st"

printf '\n=== htpasswd-stdin (the -i password-on-stdin form, real binary) ===\n\n'

# ── PIN ROWS ─────────────────────────────────────────────────────────────────────────
if grep -qE '^ubuntu:24\.04@sha256:[0-9a-f]{64}$' <<<"$UBUNTU_BASE"; then pass "P1: the ubuntu image is a tag@sha256:<64-hex> pin"
else fail "P1: UBUNTU_BASE is not a tag@sha256:<64-hex> pin" "$UBUNTU_BASE"; fi
if grep -qE '^httpd:2\.4-alpine@sha256:[0-9a-f]{64}$' <<<"$HTTPD_IMAGE"; then pass "P2: the httpd image is a tag@sha256:<64-hex> pin"
else fail "P2: HTTPD_IMAGE is not a tag@sha256:<64-hex> pin" "$HTTPD_IMAGE"; fi

# ── DOCKER GATE (fail closed under CI) ───────────────────────────────────────────────
_in_ci() { [ -n "${GITHUB_ACTIONS:-}" ] || [ "${CI:-}" = "1" ] || [ "${CI:-}" = "true" ]; }
# A skip DECLARES the rows it did not run. Under CI it is a failure and the suite ends here, loudly.
_arm_skip() { # <rows> <reason>
  if _in_ci; then
    fail "docker arm: $2 — and this is CI, so it is a FAILURE: the runner must provide docker and the pinned images"
    printf '\n=== htpasswd-stdin: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
    exit 1
  fi
  SKIPPED=$((SKIPPED + $1))
  printf '  SKIP %s row(s) NOT RUN: %s\n' "$1" "$2"
}

DOCKER_OK=1
if ! command -v docker >/dev/null 2>&1; then _arm_skip $((2 * IMAGE_ROWS + DOCKER_I_ROWS + BOOT_ROWS)) "docker is absent"; DOCKER_OK=0
elif ! docker info >/dev/null 2>&1; then _arm_skip $((2 * IMAGE_ROWS + DOCKER_I_ROWS + BOOT_ROWS)) "the docker daemon is unreachable"; DOCKER_OK=0
fi

if [ "$DOCKER_OK" = 1 ]; then
  TMP="$(mktemp -d "${TMPDIR}/htpasswd-stdin.XXXXXX")"
  assert_fixture_dir "$TMP"
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/ubuntu" "$TMP/httpd"

  # The driver is POSIX sh (dash on ubuntu, busybox ash on alpine) and records one `name=rc` row each. The
  # password is synthesized per run and never printed. `su nobody` reads the file as another uid: root would
  # read a 0600 file, so the unreadable row needs a different principal, and a CONTROL row proves that same
  # su invocation succeeds on a readable file (a broken su would otherwise read as "unreadable, rc 1").
  cat > "$TMP/drive.sh" <<'DRV'
set -u
r() { printf '%s=%s\n' "$1" "$2" >> /out/rows; }
d=$(mktemp -d); f="$d/htp"
PW="synth-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s' "$PW" | htpasswd -Bin alice > "$f" 2>/dev/null; r create $?
r bcrypt "$(grep -c '^alice:\$2y\$' "$f")"
printf '%s' "$PW" | htpasswd -vi "$f" alice >/dev/null 2>&1; r match $?
printf '%s' "${PW}x" | htpasswd -vi "$f" alice >/dev/null 2>&1; r mismatch $?
printf '%s' "$PW" | htpasswd -vi "$f" bob >/dev/null 2>&1; r absent $?
printf '' | htpasswd -vi "$f" alice >/dev/null 2>&1; r emptypw $?
htpasswd -vb "$f" alice "$PW" >/dev/null 2>&1; r legacy_vb $?
chmod 711 "$d"; chmod 644 "$f"
printf '%s' "$PW" | su -s /bin/sh nobody -c "htpasswd -vi $f alice" >/dev/null 2>&1; r unreadable_control $?
chmod 600 "$f"
printf '%s' "$PW" | su -s /bin/sh nobody -c "htpasswd -vi $f alice" >/dev/null 2>&1; r unreadable $?
# Length behaviour (synthetic): bcrypt truncates at 72 bytes; htpasswd refuses a stdin password over 256 bytes.
a72="$(head -c 72 /dev/zero | tr '\0' a)"; f2="$d/htp2"
printf '%s' "${a72}ZZZZZZZZ" | htpasswd -Bin carol > "$f2" 2>/dev/null
printf '%s' "${a72}YYYYYYYY" | htpasswd -vi "$f2" carol >/dev/null 2>&1; r over72_other_tail $?
a300="$(head -c 300 /dev/zero | tr '\0' b)"; f3="$d/htp3"
printf '%s' "$a300" | htpasswd -Bin dave > "$f3" 2>/dev/null; r over256_create $?
r over256_entries "$(grep -c . "$f3" 2>/dev/null)"
echo DRIVER_DONE
DRV
  # The ubuntu prelude: bounded apt install of apache2-utils (lib/apt-bounded.sh), then the shared driver.
  cat > "$TMP/drive-ubuntu.sh" <<'DRVU'
set -u
. /work/apt/apt-bounded.sh || exit 97
gd_apt_install_bounded apache2-utils || exit $?
sh /work/drive.sh
[ -r /work/block.sh ] && bash /work/boot-drive.sh
exit 0
DRVU

  # ── the rendered registry boot block (#10119) ─────────────────────────────────────
  # The boot step is a quoted ZOTEOF heredoc fed to `doppler run ... -- bash -s` inside a Terraform templatefile (no literal heredoc opener in this
  # comment or in the greps below: the vacuity meta-guard's heredoc scanner would read it as a body that swallows the suite's floor). A hand-written substitution
  # would test a copy; this takes the text from the SAME offline render registry-userdata-budget.sh produces (the comment-stripped
  # bytes a host is given), cuts the heredoc body, and cuts it again before the first statement AFTER the htpasswd lines (the docker
  # wait loop), so what runs is the isolation check, the empty-token guards and the htpasswd construction. The wrapper line itself is
  # asserted statically below. `doppler` and `jq` are stubs (the isolation check lists four admitted names); htpasswd is the REAL binary.
  BOOT_OK=0; BOOT_RENDERED=0
  if command -v terraform >/dev/null 2>&1 && bash "${DIR}/registry-userdata-budget.sh" "$TMP/rendered.yml" >/dev/null 2>&1 && [ -s "$TMP/rendered.yml" ]; then
    BOOT_RENDERED=1
    awk '/-- bash -s <<.ZOTEOF.$/{f=1; next} /^    ZOTEOF$/{f=0} f{print}' "$TMP/rendered.yml" | sed -E 's/^    //' \
      | awk '/^for i in \$\(seq 1 30\); do docker info/{exit} {print}' > "$TMP/block.sh"
    printf 'echo BOOT_BLOCK_DONE\n' >> "$TMP/block.sh"
    if grep -q 'set -euo pipefail' "$TMP/block.sh" && grep -q 'htpasswd -Bin' "$TMP/block.sh" && ! grep -qF 'docker info' "$TMP/block.sh" \
       && grep -qE "doppler run --project soleur-registry --config prd -- bash -s <<.ZOTEOF." "$TMP/rendered.yml"; then BOOT_OK=1; fi
  fi
  cat > "$TMP/boot-drive.sh" <<'BDRV'
set -u
BR=/out/boot-rows
r() { printf '%s=%s\n' "$1" "$2" >> "$BR"; }
mkdir -p /stubs /stubs-fail
printf '#!/bin/sh\nprintf "%%s\\n" ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN REGISTRY_LUKS_KEY\n' > /stubs/doppler
printf '#!/bin/sh\ncat\n' > /stubs/jq
printf '#!/bin/sh\ncat >/dev/null\nexit 9\n' > /stubs-fail/htpasswd
mkdir -p /stubs-failpush
BOOT_REAL_HTPASSWD="$(command -v htpasswd)"
# Fails only for the PUSH user (the block's second htpasswd call); the pull call reaches the real binary.
printf '#!/bin/sh\ncase "$*" in *zot-push*) cat >/dev/null; exit 9 ;; esac\nexec %s "$@"\n' "$BOOT_REAL_HTPASSWD" > /stubs-failpush/htpasswd
chmod +x /stubs/* /stubs-fail/* /stubs-failpush/*
# The usernames are the block's own rendered literals (zot-pull / zot-push today), read from it rather than assumed.
UPULL="$(sed -n "s/^printf '%s' \"\$ZOT_PULL_TOKEN\" | htpasswd -Bin '\([^']*\)'.*/\1/p" /work/block.sh)"
UPUSH="$(sed -n "s/^printf '%s' \"\$ZOT_PUSH_TOKEN\" | htpasswd -Bin '\([^']*\)'.*/\1/p" /work/block.sh)"
r users "$([ -n "$UPULL" ] && [ -n "$UPUSH" ] && [ "$UPULL" != "$UPUSH" ] && echo ok || echo missing)"
PWPULL="synthp-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"; PWPUSH="synths-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
run_block() { # <umask> <pull token> <push token> [extra PATH dir]: the block fed to `bash -s` on stdin, as the heredoc does
  rm -rf /etc/zot
  ( umask "$1"; export ZOT_PULL_TOKEN="$2" ZOT_PUSH_TOKEN="$3"; export PATH="${4:+$4:}/stubs:$PATH"; bash -s < /work/block.sh > /work/block.out 2>&1 ); BRC=$?
}
run_block 022 "$PWPULL" "$PWPUSH"
r block_rc "$BRC"; r block_done "$(grep -c '^BOOT_BLOCK_DONE$' /work/block.out)"
r mode "$(stat -c %a /etc/zot/htpasswd 2>/dev/null)"
r entries "$(grep -cE "^(${UPULL}|${UPUSH}):\\\$2y\\\$" /etc/zot/htpasswd 2>/dev/null)"
printf '%s' "$PWPULL" | htpasswd -vi /etc/zot/htpasswd "$UPULL" >/dev/null 2>&1; r v_pull $?
printf '%s' "$PWPUSH" | htpasswd -vi /etc/zot/htpasswd "$UPUSH" >/dev/null 2>&1; r v_push $?
printf '%s' "$PWPULL" | htpasswd -vi /etc/zot/htpasswd "$UPUSH" >/dev/null 2>&1; r v_cross $?
run_block 000 "$PWPULL" "$PWPUSH"
r mode_umask0 "$(stat -c %a /etc/zot/htpasswd 2>/dev/null)"
run_block 022 "$PWPULL" "$PWPUSH" /stubs-fail
r fail_rc "$BRC"; r fail_done "$(grep -c '^BOOT_BLOCK_DONE$' /work/block.out)"
r fail_entries "$(cat /etc/zot/htpasswd 2>/dev/null | wc -l | tr -d ' ')"
run_block 022 "$PWPULL" "$PWPUSH" /stubs-failpush
r failpush_rc "$BRC"; r failpush_done "$(grep -c '^BOOT_BLOCK_DONE$' /work/block.out)"
r failpush_entries "$(grep -cE '^[^:]+:\$2y\$' /etc/zot/htpasswd 2>/dev/null)"   # bcrypt entries, not lines: htpasswd -n may add a blank line
run_block 022 "" "$PWPUSH"
r empty_rc "$BRC"; r empty_file "$([ -e /etc/zot/htpasswd ] && echo present || echo absent)"
r empty_msg "$(grep -c 'ZOT_PULL_TOKEN empty' /work/block.out)"
run_block 022 "$PWPULL" ""
r emptypush_rc "$BRC"; r emptypush_file "$([ -e /etc/zot/htpasswd ] && echo present || echo absent)"
r emptypush_msg "$(grep -c 'ZOT_PUSH_TOKEN empty' /work/block.out)"
# ARGV RECORDING (#10119): a wrapper ahead of the REAL htpasswd on PATH appends each call's argument list to a log, then execs the real binary,
# so the property "no password and no option cluster holding b on the argument list" is read off what the process actually received. The
# CONTROL runs the same block with the two lines turned back into the argv form (-Bbn user "$TOKEN"); the same judge must call that RED,
# otherwise a judge that always says "clean" would pass the real run.
mkdir -p /stubs-rec
REAL_HTPASSWD="$(command -v htpasswd)"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> /work/argv.log\nexec %s "$@"\n' "$REAL_HTPASSWD" > /stubs-rec/htpasswd
chmod +x /stubs-rec/htpasswd
argv_judge() { # <argv log> <pull token> <push token>: prints clean | token-on-argv | b-cluster
  if grep -qF -e "$2" -e "$3" "$1"; then echo token-on-argv
  elif grep -qE '(^| )-[A-Za-z]*b[A-Za-z]*( |$)' "$1"; then echo b-cluster
  else echo clean; fi
}
rm -f /work/argv.log; : > /work/argv.log
run_block 022 "$PWPULL" "$PWPUSH" /stubs-rec
r argv_calls "$(grep -c . /work/argv.log)"; r argv_real "$(argv_judge /work/argv.log "$PWPULL" "$PWPUSH")"
sed -E "s/^printf '%s' \"\\\$ZOT_PULL_TOKEN\" \| htpasswd -Bin ('[^']*') +> /htpasswd -Bbn \1 \"\$ZOT_PULL_TOKEN\" > /; s/^printf '%s' \"\\\$ZOT_PUSH_TOKEN\" \| htpasswd -Bin ('[^']*') +>> /htpasswd -Bbn \1 \"\$ZOT_PUSH_TOKEN\" >> /" /work/block.sh > /work/block-argv.sh
r argv_ctl_landed "$(grep -c 'htpasswd -Bbn' /work/block-argv.sh)"
rm -f /work/argv.log; : > /work/argv.log
rm -rf /etc/zot
( umask 022; export ZOT_PULL_TOKEN="$PWPULL" ZOT_PUSH_TOKEN="$PWPUSH"; export PATH="/stubs-rec:/stubs:$PATH"; bash -s < /work/block-argv.sh > /work/block-argv.out 2>&1 )
r argv_ctl "$(argv_judge /work/argv.log "$PWPULL" "$PWPUSH")"
echo BOOT_DRIVER_DONE
BDRV
  _boot_rows() { # <rows file>
    local R="$1"
    if _eq block_rc 0 "$R" && _eq block_done 1 "$R"; then pass "B1: the rendered boot block runs to its end under bash -s with set -euo pipefail (exit 0)"
    else fail "B1: the rendered boot block did not run clean (rc=$(_rv block_rc "$R") done=$(_rv block_done "$R"))"; fi
    if _eq mode 600 "$R"; then pass "B2: /etc/zot/htpasswd is mode 600 (born that way, no chmod)"
    else fail "B2: the htpasswd file is not mode 600 (mode=$(_rv mode "$R"))"; fi
    if _eq users ok "$R" && _eq entries 2 "$R" && _eq v_pull 0 "$R" && _eq v_push 0 "$R"; then pass "B3: two bcrypt entries, and each token verifies for its own user with htpasswd -vi (the stdin form hashed the real password)"
    else fail "B3: entries/verification wrong (entries=$(_rv entries "$R") pull=$(_rv v_pull "$R") push=$(_rv v_push "$R"))"; fi
    if _eq v_cross 3 "$R"; then pass "B4: the pull token does NOT verify for the push user (each pipeline fed its own token)"
    else fail "B4: cross-verification is not exit 3 (rc=$(_rv v_cross "$R")): the entries may share a password"; fi
    if _eq mode_umask0 600 "$R"; then pass "B5: under umask 000 the file is STILL mode 600 (install -m 600 creates it narrow)"
    else fail "B5: with umask 000 the file is not mode 600 (mode=$(_rv mode_umask0 "$R"))"; fi
    if ! _eq fail_rc 0 "$R" && _eq fail_done 0 "$R" && _eq fail_entries 0 "$R"; then pass "B6: a failing first htpasswd aborts the block under set -e BEFORE the >> line: no second entry, no completion"
    else fail "B6: a failing htpasswd did not abort cleanly (rc=$(_rv fail_rc "$R") done=$(_rv fail_done "$R") lines=$(_rv fail_entries "$R"))"; fi
    if _eq empty_rc 1 "$R" && _eq empty_file absent "$R" && _eq empty_msg 1 "$R"; then pass "B7: an empty pull token FATALs (exit 1) before the htpasswd file is created"
    else fail "B7: the empty-token guard did not stop the block first (rc=$(_rv empty_rc "$R") file=$(_rv empty_file "$R"))"; fi
    if ! _eq failpush_rc 0 "$R" && _eq failpush_done 0 "$R" && _eq failpush_entries 1 "$R"; then pass "B11: a failing SECOND (push) htpasswd aborts the block under set -e: one pull entry written, no completion (the probe then reports push unknown, never true)"
    else fail "B11: a failing push htpasswd did not abort cleanly (rc=$(_rv failpush_rc "$R") done=$(_rv failpush_done "$R") lines=$(_rv failpush_entries "$R"))"; fi
    if _eq emptypush_rc 1 "$R" && _eq emptypush_file absent "$R" && _eq emptypush_msg 1 "$R"; then pass "B12: an empty push token FATALs (exit 1) before the htpasswd file is created (printf '' | htpasswd -Bin would otherwise write a valid empty-password entry)"
    else fail "B12: the empty-push-token guard did not stop the block first (rc=$(_rv emptypush_rc "$R") file=$(_rv emptypush_file "$R"))"; fi
    if _eq argv_calls 2 "$R" && _eq argv_real clean "$R"; then pass "B9: the REAL htpasswd was called exactly twice and neither argument list holds a password or an option cluster with b (argv recorded by a wrapper ahead of it on PATH)"
    else fail "B9: the recorded htpasswd argv is not clean (calls=$(_rv argv_calls "$R") verdict=$(_rv argv_real "$R"))"; fi
    if _eq argv_ctl_landed 2 "$R" && _eq argv_ctl token-on-argv "$R"; then pass "B10: CONTROL — the same block with the two lines turned back into the argv form (-Bbn user \"\$TOKEN\") is judged token-on-argv (the B9 judge can say no)"
    else fail "B10: the argv-form control was not judged RED (landed=$(_rv argv_ctl_landed "$R") verdict=$(_rv argv_ctl "$R")): the B9 judge may be blind"; fi
    if [ "$(grep -c . "$R")" -ge 25 ]; then pass "B8: the boot driver recorded every row (anti-vacuity: no row was silently dropped)"
    else fail "B8: the boot driver recorded fewer rows than it runs ($(grep -c . "$R"))"; fi
  }

  _pull_or_skip() { # <image> <rows>: 0 when the image is local or pulled
    docker image inspect "$1" >/dev/null 2>&1 && return 0
    docker pull -q "$1" >/dev/null 2>&1 && return 0
    return 1
  }
  _contract_rows() { # <label> <rows file>
    local L="$1" R="$2"
    _eq create 0 "$R"      && pass "$L C1: printf pw | htpasswd -Bin user > file exits 0" || fail "$L C1: -Bin did not create the entry (rc=$(_rv create "$R"))"
    _eq bcrypt 1 "$R"      && pass "$L C2: the file holds exactly one user:\$2y\$ bcrypt entry" || fail "$L C2: the entry is not a single bcrypt line (count=$(_rv bcrypt "$R"))"
    _eq match 0 "$R"       && pass "$L C3: printf pw | htpasswd -vi file user exits 0 (match)" || fail "$L C3: -vi did not verify the password -Bin hashed (rc=$(_rv match "$R"))"
    _eq mismatch 3 "$R"    && pass "$L C4: a wrong password exits 3" || fail "$L C4: wrong password rc is not 3 (rc=$(_rv mismatch "$R"))"
    _eq absent 6 "$R"      && pass "$L C5: a user that is not in the file exits 6" || fail "$L C5: absent-user rc is not 6 (rc=$(_rv absent "$R"))"
    _eq emptypw 3 "$R"     && pass "$L C6: an EMPTY stdin password does not verify (exits 3; this is what a lost docker -i would hash)" || fail "$L C6: an empty password verified or mapped elsewhere (rc=$(_rv emptypw "$R"))"
    _eq legacy_vb 0 "$R"   && pass "$L C7: the legacy -vb form accepts the hash -Bin made (the forms interoperate)" || fail "$L C7: the old -vb form rejects an -Bin hash (rc=$(_rv legacy_vb "$R"))"
    _eq unreadable_control 0 "$R" && pass "$L C8: control: the same su-as-nobody call on a READABLE file exits 0" || fail "$L C8: the unreadable-row instrument is broken: su as nobody cannot even read a 0644 file (rc=$(_rv unreadable_control "$R"))"
    _eq unreadable 1 "$R"  && pass "$L C9: an unreadable file exits 1" || fail "$L C9: unreadable-file rc is not 1 (rc=$(_rv unreadable "$R"))"
    _eq over72_other_tail 0 "$R" && pass "$L C10: bcrypt truncates at 72 bytes (a different tail after byte 72 still verifies; the old argv form did the same)" || fail "$L C10: the over-72-byte behaviour changed (rc=$(_rv over72_other_tail "$R"))"
    if [ "$(_rv over256_create "$R")" != 0 ] && _eq over256_entries 0 "$R"; then pass "$L C11: a 300-byte stdin password is refused by htpasswd -Bin (non-zero) and writes no entry"; else fail "$L C11: a 300-byte password was accepted or wrote an entry (rc=$(_rv over256_create "$R") entries=$(_rv over256_entries "$R"))"; fi
  }
  _arm_done() { # <out dir>: the docker rc just captured in ARM_RC; ARM_DONE=1 when the driver ran to its last line
    ARM_DONE=0; grep -qx DRIVER_DONE "$1/stdout" && ARM_DONE=1
    return 0
  }

  # -- ubuntu:24.04 + apache2-utils (the shipped host image) ------------------------
  [ "$BOOT_OK" = 1 ] || : > "$TMP/block.sh"
  if ! _pull_or_skip "$UBUNTU_BASE"; then _arm_skip $((IMAGE_ROWS + BOOT_ROWS)) "the pinned ubuntu image is not local and could not be pulled"
  else
    : > "$TMP/ubuntu/rows"
    gd_apt_state_arm "$TMP/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }
    docker run --rm -v "$GD_APT_STATE:/work/apt" -e DEBIAN_FRONTEND=noninteractive -v "$TMP/drive.sh:/work/drive.sh:ro" -v "$TMP/drive-ubuntu.sh:/work/drive-ubuntu.sh:ro" -v "$TMP/boot-drive.sh:/work/boot-drive.sh:ro" -v "$TMP/block.sh:/work/block.sh:ro" -v "$TMP/ubuntu:/out" "$UBUNTU_BASE" bash /work/drive-ubuntu.sh > "$TMP/ubuntu/stdout" 2>&1
    ARM_RC=$?; _arm_done "$TMP/ubuntu"
    if [ "$ARM_DONE" = 1 ]; then
      _contract_rows "ubuntu:24.04+apache2-utils" "$TMP/ubuntu/rows"
      if [ "$BOOT_OK" = 1 ] && grep -qx BOOT_DRIVER_DONE "$TMP/ubuntu/stdout"; then _boot_rows "$TMP/ubuntu/boot-rows"
      elif [ "$BOOT_OK" = 1 ]; then fail "boot rows: the boot driver did not complete" "$(tail -5 "$TMP/ubuntu/stdout" | tr '\n' ' ')"; SKIPPED=$((SKIPPED + BOOT_ROWS - 1))
      elif [ "$BOOT_RENDERED" = 1 ]; then fail "boot rows: the registry user_data rendered, but its boot block no longer has the stdin htpasswd form (set -euo pipefail, htpasswd -Bin, the doppler wrapper line): the conversion regressed, whatever the environment"; SKIPPED=$((SKIPPED + BOOT_ROWS - 1))
      elif _in_ci; then fail "boot rows: the registry render failed, and this is CI (terraform and the offline render are required)"; SKIPPED=$((SKIPPED + BOOT_ROWS - 1))
      else _arm_skip "$BOOT_ROWS" "terraform is absent or the offline render/extraction failed (the boot-block rows need the same render registry-userdata-budget.sh makes)"; fi
    elif grep -qx FIXTURE_APT_FAILED "$TMP/ubuntu/stdout" || [ "$ARM_RC" = 125 ]; then
      _arm_skip $((IMAGE_ROWS + BOOT_ROWS)) "the ubuntu fixture did not reach the driver (docker rc=$ARM_RC): $(tail -2 "$TMP/ubuntu/stdout" | tr '\n' ' ')"
    else
      fail "ubuntu arm: the driver did not complete (docker rc=$ARM_RC)" "$(tail -5 "$TMP/ubuntu/stdout" | tr '\n' ' ')"
      SKIPPED=$((SKIPPED + IMAGE_ROWS + BOOT_ROWS - 1))
    fi
  fi

  # -- httpd:2.4-alpine (the rehearsal step's image) --------------------------------
  if ! _pull_or_skip "$HTTPD_IMAGE"; then _arm_skip $((IMAGE_ROWS + DOCKER_I_ROWS)) "the pinned httpd image is not local and could not be pulled"
  else
    : > "$TMP/httpd/rows"
    docker run --rm -v "$TMP/drive.sh:/work/drive.sh:ro" -v "$TMP/httpd:/out" "$HTTPD_IMAGE" sh /work/drive.sh > "$TMP/httpd/stdout" 2>&1
    ARM_RC=$?; _arm_done "$TMP/httpd"
    if [ "$ARM_DONE" = 1 ]; then _contract_rows "httpd:2.4-alpine" "$TMP/httpd/rows"
    else
      fail "httpd arm: the driver did not complete (docker rc=$ARM_RC)" "$(tail -5 "$TMP/httpd/stdout" | tr '\n' ' ')"
      SKIPPED=$((SKIPPED + IMAGE_ROWS - 1))
    fi

    # -- docker's own -i: the form the workflow step uses ---------------------------
    # POSITIVE: with docker -i the password reaches htpasswd, so the file verifies it. NEGATIVE CONTROL: without it
    # docker forwards nothing, htpasswd hashes the empty password, and the SAME verification exits 3 — the row that
    # shows the positive one can fail.
    DPW="synth-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
    mkdir -p "$TMP/di"
    printf '%s' "$DPW" | docker run --rm -i "$HTTPD_IMAGE" htpasswd -Bin zuser > "$TMP/di/with-i" 2>/dev/null; _c_with=$?
    printf '%s' "$DPW" | docker run --rm "$HTTPD_IMAGE" htpasswd -Bin zuser > "$TMP/di/without-i" 2>/dev/null; _c_without=$?
    _verify() { printf '%s' "$DPW" | docker run --rm -i -v "$1:/f:ro" "$HTTPD_IMAGE" htpasswd -vi /f zuser >/dev/null 2>&1; }
    _verify "$TMP/di/with-i"; _v_with=$?
    _verify "$TMP/di/without-i"; _v_without=$?
    if [ "$_c_with" = 0 ] && [ "$_v_with" = 0 ]; then pass "D1: through docker WITH -i the password reaches htpasswd (hash verifies, exit 0)"
    else fail "D1: with docker -i the hash did not verify (create rc=$_c_with, verify rc=$_v_with)"; fi
    if [ "$_v_without" = 3 ]; then pass "D2: NEGATIVE CONTROL — without docker -i the password is NOT forwarded: the hash covers an empty password (verify exits 3)"
    else fail "D2: without docker -i the hash still verified or failed differently (create rc=$_c_without, verify rc=$_v_without): docker -i may no longer be required, or the control is blind"; fi
  fi
fi

# ── FLOOR + LEDGER ───────────────────────────────────────────────────────────────────
# Skipped rows count toward the floor (they were DECLARED), never toward passes. Reported with printf + exit
# INSIDE this block, never through pass()/fail(): a neutered helper cannot disarm it.
if [ "$DECLARED_ROWS" -ne "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: the declared row count is %s but the floor literal is %s — raise both in one edit.\n' "$DECLARED_ROWS" "$FLOOR" >&2
  exit 1
fi
_ran=$((passes + fails + ${SKIPPED:-0}))   # ${SKIPPED:-0}: SKIPPED moves by N rows, not +1, so the vacuity meta-guard cannot zero it, and the default keeps its mutant bound
if [ "$_ran" -lt 38 ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran/declared, floor is 38 — arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}"; exit 1
fi
[ "$DOCKER_OK" = 1 ] && gd_apt_state_summary 2>/dev/null
printf '\n=== htpasswd-stdin: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
exit $(( ${#FAILURES[@]} > 0 ))
