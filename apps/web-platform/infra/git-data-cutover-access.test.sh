#!/usr/bin/env bash
#
# git-data-cutover read-only proof (#6680 / #8189 / ADR-220). Access gate, store probes, captured
# values, real-mode refusal, workflow wiring and step gating, and a runtime arm.
#
# Access gate — git-data-cutover.sh's access_gate runs web (every roster member) -> git-data-jump
#   (an `ssh -W` banner through web-1, no git-data credential) -> git-data-auth; a non-ok verdict
#   exits 3 before any store probe. No probe byte reaches the runner's workflow-command parser
#   unsanitized. Observed through ONE timeline file ($TL): PATH shims for `ssh`, `doppler` and
#   `timeout` append to it, so every remote call is ordered in one stream.
# Guard 2 (plan) — no run exits 0 on an unmounted, cut-over or non-empty store; each probe fails
#   closed, and a read that could not complete is probe_failed, never a store-state verdict; the
#   count runs only on the source the mount probe accepted; the script carries no
#   rsync/cryptsetup/mount/umount/mkfs/touch/rm -rf/systemctl/doppler.
# Guard 3 — the root token's reference census lives in tests/scripts/test-git-data-root-token-census.sh
#   (registered in scripts/test-all.sh, so it runs on every PR rather than only on infra paths).
# Guard 5 — gd_capture bounds (30 s, 4096 bytes), anchors and never prints a captured value; no
#   raw capture of an ssh invocation outside it.
# Guard 6 (cutover half) — workflow-level git-data-state, cancel-in-progress False, the literal
#   equal to git_data_host_replace's group in apply-web-platform-infra.yml.
# Guard 7 — the workflow's inputs are exactly {confirm, mode, lineage}; DRY_RUN/ROLLBACK/CONFIRM_WIPE carrying a
#   non-default value exits 5 with an EMPTY timeline.
# Bridge — the "Decode CI SSH private key" step exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH} on
#   the server-ip branch and exactly {TF_VAR_ci_ssh_private_key} on the terraform branch.
# Workflow (D-6 / AC9) — parsed as YAML (`on:` read through the True-key lookup); step GATING is
#   pinned (no continue-on-error before the script step; only teardown and summary carry if:); the
#   key-fetch, ssh_config, secrets-check and teardown step bodies are EXECUTED, not grepped.
# Runtime arm — the real script against real OpenSSH in the pinned ubuntu:24.04 image, including
#   the workflow's own ssh_config writer end to end through a web-1 jump, both hops host-key
#   PINNED (#7226), and the H4 verdict host_key_mismatch reason=changed|unknown|alg from real ssh
#   error text. Under CI=true a missing docker is a FAILURE.
# Host-key pin (#7226, plan D3/H4) — WEB_HOST_SSH fixtures carry the bridge's pinned form; the
#   ssh_config writer is executed with the shared write-known-hosts.sh and both Host blocks are
#   resolved by real `ssh -G`; _access_reason's H4 branches key on ssh's exit code (255) plus
#   line-anchored patterns, so hostile banner text cannot pick a verdict.
#
# Harness conventions (plan › Guard Contract): code-edit rows run as MUTANTS through mutate()
# (copy, sed the copy, assert the edit landed on the expected diff-line count, point the suite's
# override at the copy, require the NAMED case RED); fixture rows are negative cases; floors are
# reported with printf + exit, never through pass()/fail().
#
# The script under test carries no test seam (ADR-214): it is driven through PATH shims only.
# GDC_* variables are seams of the SUITE (GDC_SCRIPT, GDC_WORKFLOW, GDC_ACTION).
#
# Run: bash apps/web-platform/infra/git-data-cutover-access.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

# pass() cannot fail, so the runtime rows' `cond && pass || fail` is a true if/else.
# shellcheck disable=SC2015
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SCRIPT="${GDC_SCRIPT:-$DIR/git-data-cutover.sh}"
ACTION="${GDC_ACTION:-$ROOT/.github/actions/cf-tunnel-ssh-bridge/action.yml}"
WF="${GDC_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
IV="$ROOT/.github/workflows/infra-validation.yml"
APPLY_WF="$ROOT/.github/workflows/apply-web-platform-infra.yml"
# The pinned base image is owned by git-data-runcmd-rehearsal.test.sh (rule-audit.yml watches
# that copy); read it from there so a pin bump cannot leave this arm on a stale image.
REHEARSAL="$DIR/git-data-runcmd-rehearsal.test.sh"
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "$REHEARSAL" 2>/dev/null | head -1)"

passes=0; fails=0; SKIPPED=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both counters
# to move, so a neutered helper cannot report a clean run. Reported with printf + exit.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$SCRIPT" "$ACTION" "$WF" "$IV" "$APPLY_WF"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }
[ -n "$UBUNTU_BASE" ] || { printf 'FAIL SETUP: no UBUNTU_BASE pin readable from %s\n' "$REHEARSAL" >&2; exit 1; }
REAL_TIMEOUT="$(command -v timeout)" || { printf 'FAIL SETUP: timeout(1) not found\n' >&2; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { printf 'FAIL SETUP: ssh-keygen not found\n' >&2; exit 1; }
command -v ssh >/dev/null 2>&1 || { printf 'FAIL SETUP: ssh not found\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/gdc-access.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
# A literal `exit 0` anywhere above the verdict would skip the floor; the trap turns that into
# a failure (an EXIT trap may override the exit status).
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
BIN="$T/bin"
mkdir -p "$BIN" "$T/mut" "$T/steps" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data-cutover read-only proof (ADR-220, #8189) ===\n\n'

# ── shims ─────────────────────────────────────────────────────────────────────────────
# ssh: log argv (newlines flattened) and its stdin to $TL; parse options the way ssh does;
# refuse an empty destination (exit 64); answer per scenario.
cat > "$BIN/ssh" <<'SHIM'
#!/usr/bin/env bash
line="ssh"
for a in "$@"; do line+=" ${a//$'\n'/ }"; done
printf '%s\n' "$line" >> "$TL"
printf 'ssh-stdin %s\n' "$(readlink /proc/$$/fd/0)" >> "$TL"
args=("$@"); n=${#args[@]}; i=0; dest=""; w=""; cmd=()
while (( i < n )); do
  a="${args[$i]}"
  case "$a" in
    -i|-o|-l|-p|-F|-J) i=$((i + 2)) ;;
    -W) w="${args[$((i + 1))]:-}"; i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) dest="$a"; cmd=("${args[@]:$((i + 1))}"); break ;;
  esac
done
[ -n "$dest" ] || { echo "ssh-shim: empty destination" >&2; exit 64; }
if [ -n "$w" ]; then
  [ -n "${SHIM_JUMP_STDERR:-}" ] && printf '%s' "$SHIM_JUMP_STDERR" >&2
  case "${SHIM_JUMP:-banner}" in
    banner)       printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    banner_extra) printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\nextra-bytes\n'; exit 255 ;;
    line2)        printf '\nSSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    http)         printf 'HTTP/1.0 400 Bad Request\r\n'; exit 0 ;;
    none)         exit 255 ;;
  esac
fi
c="${cmd[*]}"
if [ "$c" = "true" ]; then
  if [ "$dest" = "10.0.1.20" ]; then
    if [ "${SHIM_AUTH_RC:-0}" != 0 ]; then
      if [ -n "${SHIM_AUTH_STDERR:-}" ]; then printf '%s' "$SHIM_AUTH_STDERR" >&2; else echo "root@${dest}: Permission denied (publickey)." >&2; fi
    fi
    exit "${SHIM_AUTH_RC:-0}"
  fi
  for r in ${SHIM_WEB_REFUSE:-}; do
    if [ "$r" = "$dest" ]; then
      if [ -n "${SHIM_WEB_STDERR:-}" ]; then printf '%s' "$SHIM_WEB_STDERR" >&2; else echo "root@${dest}: Permission denied (publickey)." >&2; fi
      exit "${SHIM_WEB_RC:-255}"
    fi
  done
  [ -n "${SHIM_WEB_OK_STDERR:-}" ] && printf '%s' "$SHIM_WEB_OK_STDERR" >&2
  exit 0
fi
case "$c" in
  "findmnt -n -o SOURCE --mountpoint "*)
    case "${SHIM_FINDMNT:-mapper}" in
      mapper)    printf '/dev/mapper/git-data\n' ;;
      plain)     printf '/dev/sdb\n' ;;
      mapperalt) printf '/dev/mapper/gd-alt\n' ;;
      mapperpre) printf '/dev/mapper/git-data-plain\n' ;;
      empty)  : ;;
      rc1)    exit 1 ;;
      tmpfs)  printf 'tmpfs\n' ;;
      rc255)  echo "ssh: connect to host 10.0.1.20 port 22: Connection timed out" >&2; exit 255 ;;
      line2)  printf '/dev/sdb\nCANARY-SECOND-LINE-7f3a\n' ;;
      noeol)  printf '/dev/mapper/git-data' ;;
      big)    printf '/dev/'; head -c 5000 /dev/zero | tr '\0' a ;;
      hang)   exec sleep 30 ;;
    esac
    exit 0 ;;
  "r="*)
    # The store session: the store-verified facts, then the entry count, in one command.
    # SHIM_VERIFY answers the session as a whole; with the default `ok`, SHIM_COUNT picks the count.
    [ -n "${SHIM_VERIFY_STDERR:-}" ] && printf '%s' "$SHIM_VERIFY_STDERR" >&2
    case "${SHIM_VERIFY:-ok}" in
      ok)
        case "${SHIM_COUNT:-zero}" in
          zero)    printf '0\n' ;;
          one)     printf '1\n' ;;
          zero2nl) printf '0\n\n' ;;
          err)     echo "find: cannot open directory: Permission denied" >&2; exit 4 ;;
        esac ;;
      r255)  echo "ssh: connect to host 10.0.1.20 port 22: Connection timed out" >&2; exit 255 ;;
      r*)    exit "${SHIM_VERIFY#r}" ;;
      line2) printf '0\nCANARY-VERIFY-LINE-2\n' ;;
      empty) : ;;
      notok) printf 'nok\n' ;;
      x0)    printf 'x0\n' ;;
      exec)  exec bash -c "$c" ;;
    esac
    exit 0 ;;
  "h="*)
    case "${SHIM_FENCE:-ok}" in
      ok)    printf 'ok\n' ;;
      r255)  echo "ssh: connect to host 10.0.1.20 port 22: Connection timed out" >&2; exit 255 ;;
      r*)    exit "${SHIM_FENCE#r}" ;;
      line2) printf 'ok\nCANARY-FENCE-LINE-2\n' ;;
      empty) : ;;
      notok) printf 'nok\n' ;;
      exec)  exec bash -c "$c" ;;
    esac
    exit 0 ;;
  # ── PR2 mode-verb remotes ─────────────────────────────────────────────────────────
  "systemctl show "*)
    case "${SHIM_GC_STATE:-inactive}" in
      r*) exit "${SHIM_GC_STATE#r}" ;;
      *)  printf '%s\n' "${SHIM_GC_STATE}"; exit 0 ;;
    esac ;;
  "systemctl stop "*)   exit "${SHIM_GC_STOP_RC:-0}" ;;
  "systemctl start "*)  exit "${SHIM_GC_START_RC:-0}" ;;
  "fz="*)
    # The freeze provenance session: absent | ours/foreign (writer + at) | rc 2 unattributed.
    case "${SHIM_FREEZE:-absent}" in
      absent)   printf 'absent\n' ;;
      ours)     printf 'ours writer=%s at=1700000000\n' "${CUTOVER_LINEAGE:-x}" ;;
      foreign)  printf 'foreign writer=other at=1700000000\n' ;;
      unattributed) exit 2 ;;
      r*)    exit "${SHIM_FREEZE#r}" ;;
    esac
    exit 0 ;;
  "printf 'writer="*)   exit "${SHIM_FREEZE_WRITE_RC:-0}" ;;
  "d="*)   # the legacy-lock purge session
    case "${SHIM_PURGE:-ok}" in
      ok)    exit 0 ;;
      held)  exit 23 ;;
      r*)    exit "${SHIM_PURGE#r}" ;;
    esac ;;
  "rm -f "*)   exit "${SHIM_UNFREEZE_RC:-0}" ;;
  "id="*)   # the transactional probe session
    case "${SHIM_PROBE:-ok}" in
      ok)       exit 0 ;;
      provfail) exit 11 ;;
      nocreate) exit 12 ;;
      scratch)  exit 13 ;;
      pushfail) exit 14 ;;
      noref)    exit 15 ;;
      remfail)  exit 16 ;;
      residue)  exit 17 ;;
      r*)    exit "${SHIM_PROBE#r}" ;;
    esac ;;
  "env -i "*)   # the probe's residue-cleanup retry — always exits 0 (idempotent remove)
    exit 0 ;;
esac
exit "${SHIM_REMOTE_RC:-1}"
SHIM
# findmnt: reached ONLY by the store session or the fence command when SHIM_VERIFY=exec /
# SHIM_FENCE=exec runs the remote bytes locally.
# `-o UUID --mountpoint <path>` answers SHIM_FINDMNT_UUID (default the synthesized FIX_UUID; `empty`
# answers nothing, `fail` exits 1). `-o SOURCE --mountpoint <path>` answers SHIM_FINDMNT_S (default
# the mapper; a two-line value simulates a stacked mount).
# `-T <path>` answers the source that path lives on: SHIM_FINDMNT_T (default the mount probe's
# mapper), or `fail` for a findmnt that cannot resolve it.
# The fence command asks for the hooks dir and pre-receive separately: SHIM_FINDMNT_TH / _TP
# answer those two paths (each defaulting to SHIM_FINDMNT_T), so each comparison is drivable alone.
FIX_UUID=6d1f0c2e-8b4a-4f3e-9a7d-2c5e8b1f4a90   # the findmnt shim's default UUID answer
cat > "$BIN/findmnt" <<SHIM
#!/usr/bin/env bash
if [ "\$*" = "-n -o UUID --mountpoint \${!#}" ]; then
  u="\${SHIM_FINDMNT_UUID:-$FIX_UUID}"
  case "\$u" in
    empty) exit 0 ;;
    fail)  echo "findmnt: cannot read UUID" >&2; exit 1 ;;
    *)     printf '%s\\n' "\$u"; exit 0 ;;
  esac
fi
if [ "\$*" = "-n -o SOURCE --mountpoint \${!#}" ]; then printf '%s\\n' "\${SHIM_FINDMNT_S:-/dev/mapper/git-data}"; exit 0; fi
[ "\${3:-}" = -T ] || { echo "findmnt-shim: unexpected argv: \$*" >&2; exit 64; }
a="\${SHIM_FINDMNT_T:-/dev/mapper/git-data}"
case "\${!#}" in
  */hooks) a="\${SHIM_FINDMNT_TH:-\$a}" ;;
  */pre-receive) a="\${SHIM_FINDMNT_TP:-\$a}" ;;
esac
case "\$a" in
  fail) echo "findmnt: can't find target" >&2; exit 1 ;;
  *) printf '%s\\n' "\$a" ;;
esac
SHIM
# stat / git / runuser: reached ONLY by the fence command under SHIM_FENCE=exec (the script itself
# calls none of them). A CI user cannot own a root:git tree, so these answer for the paths the
# fence command reads; an unset answer falls through to the real binary.
REAL_STAT="$(command -v stat)" || { printf 'FAIL SETUP: stat not found\n' >&2; exit 1; }
# The store session asks `stat -c %m <repositories>` for its containing mount: SHIM_STAT_M answers
# (`fail` exits 1); unset, the answer is the resolved OLD_ROOT the case ran with, i.e. "on the root".
cat > "$BIN/stat" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = -c ] && [ "\${2:-}" = %m ]; then
  case "\${SHIM_STAT_M:-}" in
    fail) echo "stat: cannot statx" >&2; exit 1 ;;
    "")   readlink -f "\${OLD_ROOT:-/mnt/git-data}"; exit 0 ;;
    *)    printf '%s\\n' "\$SHIM_STAT_M"; exit 0 ;;
  esac
fi
[ "\${SHIM_STAT_FAIL:-0}" = 1 ] && { echo "stat: cannot statx" >&2; exit 1; }
case "\${!#}" in
  */hooks) v="\${SHIM_STAT_H-}" ;;
  */pre-receive) v="\${SHIM_STAT_P-}" ;;
  *) v="\${SHIM_STAT_PARENT-}" ;;
esac
[ -n "\$v" ] && { printf '%s\n' "\$v"; exit 0; }
exec "$REAL_STAT" "\$@"
SHIM
cat > "$BIN/git" <<'SHIM'
#!/usr/bin/env bash
[ "$*" = "config --system --includes --get core.hooksPath" ] || { echo "git-shim: unexpected argv: $*" >&2; exit 64; }
[ -n "${SHIM_GIT_RC:-}" ] && exit "$SHIM_GIT_RC"
printf '%s\n' "${SHIM_GIT_HP:?git-shim: no SHIM_GIT_HP}"
SHIM
cat > "$BIN/runuser" <<'SHIM'
#!/usr/bin/env bash
[ "${1:-}" = -u ] && [ "${2:-}" = git ] && [ "${3:-}" = -- ] || { echo "runuser-shim: unexpected argv: $*" >&2; exit 64; }
[ "${SHIM_RUNUSER_BROKEN:-0}" = 1 ] && { echo "runuser: user git does not exist" >&2; exit 1; }
[ -n "${SHIM_RUNUSER_RC:-}" ] && [ "${4:-}" != true ] && exit "$SHIM_RUNUSER_RC"
shift 3; exec "$@"
SHIM
# doppler: the script must never call it. Logged and refused.
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$TL"
echo "doppler-shim: git-data-cutover.sh must not call doppler" >&2
exit 1
SHIM
# timeout: log the bound, then run the real command (so a probe without its bound is visible).
# SHIM_TIMEOUT_S swaps in a REAL timeout with a short bound, for the hung-host rows.
cat > "$BIN/timeout" <<SHIM
#!/usr/bin/env bash
printf 'timeout %s\n' "\$1" >> "\$TL"
shift
if [ -n "\${SHIM_TIMEOUT_S:-}" ]; then exec "$REAL_TIMEOUT" "\$SHIM_TIMEOUT_S" "\$@"; fi
exec "\$@"
SHIM
chmod +x "$BIN/ssh" "$BIN/findmnt" "$BIN/doppler" "$BIN/timeout" "$BIN/stat" "$BIN/git" "$BIN/runuser" || { printf 'FAIL SETUP: chmod shims\n' >&2; exit 1; }

# The bridge's pinned bash-mode invocation (plan D3), with fixture paths.
WEB_INV='ssh -F /dev/null -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/fixture/web-1.known_hosts -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root'
GD_INV='ssh -F /fixture/gd-ssh-config'

# run_case <name> [VAR=value ...] — runs the script (CASE_SCRIPT, default the real one) under the
# shims, bounded by CASE_TIMEOUT. Sets OUT, TLF, RC.
run_case() {
  local name="$1"; shift
  TLF="$T/$name.tl"; OUT="$T/$name.out"
  : > "$TLF" || { printf 'FAIL SETUP: cannot write %s\n' "$TLF" >&2; exit 1; }
  "$REAL_TIMEOUT" -k 3 "${CASE_TIMEOUT:-60}" env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" "$@" \
    bash "${CASE_SCRIPT:-$SCRIPT}" > "$OUT" 2>&1
  RC=$?
}
tl_ssh() { grep -c '^ssh ' "$TLF" || true; }
tl_line() { grep -nE -- "$1" "$TLF" | head -1 | cut -d: -f1; }
has_access() { grep -qE "^\[git-data-cutover\] ACCESS role=$1 host=[^ ]+ verdict=$2( |$)" "$OUT"; }
has_store() { grep -qE "^\[git-data-cutover\] STORE probe=$1 verdict=$2( |$)" "$OUT"; }
# Any remote that is not a read: LUKS/mount/rsync/systemd/sentinel shapes, or any doppler call.
# findmnt is a READ (the store probe) and is deliberately not in this list. `mountpoint` matches as
# the mountpoint(1) command, not as findmnt's `--mountpoint` option (the MM rows below pin both).
mutating() { grep -qE '^ssh .*(cryptsetup|(^|[^-])mountpoint|rsync|systemctl|rm -f|touch |test -f|(^| )u?mount )|^doppler ' "$TLF"; }
# The count runs inside the store session (r=…), after its store-verified checks.
no_count_probe() { ! grep -qE '^ssh .* 10\.0\.1\.20 r=' "$TLF"; }
# Detail text for a failure, neutralised so a failing row cannot raise a real annotation.
ctx() { printf 'rc=%s | out: %s | tl: %s' "$RC" "$(tail -c 600 "$OUT" | tr '\n' '|')" "$(tr '\n' '|' < "$TLF" | cut -c1-400)" | sed 's/::/: :/g; s/##\[/#-#[/g'; }

WEB_PROBE='^ssh -F /dev/null -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/fixture/web-1\.known_hosts -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20'
JUMP_PROBE="$WEB_PROBE -W 10\\.0\\.1\\.20:22 10\\.0\\.1\\.10\$"
KEYED=(WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV")

# mutate <name> <file> <expected-diff-lines> <sed -E program> — copies <file> to $T/mut/<name>,
# applies the edit, and requires it to have landed on exactly the expected number of diff lines
# (`<` plus `>`). Sets MUTANT. A mutation that does not land reports the baseline, which is
# indistinguishable from a pass — so the landing is itself an assertion.
MUTANT=""
mutate() {
  local name="$1" src="$2" want="$3" expr="$4" got
  MUTANT="$T/mut/$name.$(basename "$src")"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if ! sed -E -i "$expr" "$MUTANT" 2>"$T/mut/$name.sed.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.sed.err")"; return 1
  fi
  got="$(diff "$src" "$MUTANT" | grep -cE '^[<>]' || true)"
  # A script mutant that no longer parses would go RED for the wrong reason.
  if [ "${src%.sh}" != "$src" ] && ! bash -n "$MUTANT" 2>/dev/null; then
    fail "M-$name: the mutant does not parse (bash -n) — it would go RED for the wrong reason" "sed -E [$expr]"; return 1
  fi
  if [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want" "sed -E [$expr]"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
# mutant_red <name> <case-fn> [args...] — the named case must go RED against $MUTANT.
mutant_red() {
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named case stayed GREEN against the mutant" "$(ctx)"
  else pass "M-$name: the named case goes RED against the mutant"; fi
}
# mutant_red self-test (ADR-193), both directions, in a subshell so the counters roll back: a case
# that stays GREEN must count one failure, a case that goes RED one pass. Reported with printf + exit.
_mr="$( (RC=- OUT=/dev/null TLF=/dev/null; mutant_red st-green true >/dev/null; printf '%s,%s ' "$passes" "$fails"; mutant_red st-red false >/dev/null; printf '%s,%s' "$passes" "$fails") )"
if [ "$_mr" != "$passes,$((fails + 1)) $((passes + 1)),$((fails + 1))" ]; then
  printf 'FAIL INSTRUMENT: mutant_red self-test read "%s" (from %s,%s) — a GREEN case must fail, a RED case must pass\n' "$_mr" "$passes" "$fails" >&2; exit 1
fi

# ── ACCESS GATE (unit rows) ───────────────────────────────────────────────────────────

# S1 / S12 — canonical key-absent stop, with the real-mode variables unset AND set to their defaults.
for mode in unset defaults; do
  if [ "$mode" = unset ]; then run_case "s1$mode" WEB_HOST_SSH="$WEB_INV" GITHUB_STEP_SUMMARY="$T/s1$mode.summary"
  else run_case "s1$mode" WEB_HOST_SSH="$WEB_INV" DRY_RUN=1 ROLLBACK=0 CONFIRM_WIPE=0 GITHUB_STEP_SUMMARY="$T/s1$mode.summary"; fi
  if [ "$RC" = 3 ] && has_access web ok && has_access git-data-jump ok \
     && [ "$(grep -E '^\[git-data-cutover\] ACCESS ' "$OUT" | tail -1)" = "[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
    pass "S1 ($mode): exits 3 at git-data-auth verdict=git_data_root_key_absent after web ok + jump ok"
  else fail "S1 ($mode): did not stop at git_data_root_key_absent with exit 3" "$(ctx)"; fi
  if [ "$(tl_ssh)" = 2 ] && grep -qE "$WEB_PROBE 10\\.0\\.1\\.10 true\$" "$TLF" && grep -qE "$JUMP_PROBE" "$TLF" \
     && ! mutating && ! grep -q 'STORE ' "$OUT"; then
    pass "S1/S12 ($mode): timeline is exactly {web probe, jump probe}; no store probe and no doppler call"
  else fail "S1/S12 ($mode): timeline is not exactly {web probe, jump probe}" "$(ctx)"; fi
done
if grep -qx 'timeout 30' "$T/s1unset.tl" && grep -qx 'timeout 25' "$T/s1unset.tl" && ! grep -qv -e '^ssh' -e '^timeout' "$T/s1unset.tl" \
   && [ "$(grep -c '^ssh-stdin ' "$T/s1unset.tl")" = 2 ] && [ "$(grep -cx 'ssh-stdin /dev/null' "$T/s1unset.tl")" = 2 ]; then
  pass "X1: the web probe is bounded by timeout 30, the jump by timeout 25, and every probe's stdin is /dev/null"
else fail "X1: probe bounds or stdin changed" "$(tr '\n' '|' < "$T/s1unset.tl")"; fi
if [ "$(cat "$T/s1unset.summary" 2>/dev/null)" = "- ACCESS role=web host=10.0.1.10 verdict=ok
- ACCESS role=git-data-jump host=10.0.1.20 verdict=ok
- ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
  pass "S1: \$GITHUB_STEP_SUMMARY carries exactly the three verdict lines"
else fail "S1: \$GITHUB_STEP_SUMMARY content differs" "$(tr '\n' '|' < "$T/s1unset.summary" 2>/dev/null)"; fi

# S15 — annotations: exactly these three, ok -> ::notice, non-ok -> ::error.
if [ "$(grep -E '^::' "$T/s1unset.out")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::error title=git-data-cutover access::role=git-data-auth verdict=git_data_root_key_absent" ]; then
  pass "S15: exactly three annotations — ::notice for the ok verdicts, ::error for the stop"
else fail "S15: annotation set/levels differ" "$(grep -E '^::' "$T/s1unset.out" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# S2 / row 1 — key present, auth refused.
run_case s2 "${KEYED[@]}" SHIM_AUTH_RC=255
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=failed rc=255 reason=auth_refused' "$OUT" \
   && ! mutating && no_count_probe && ! grep -q 'findmnt' "$TLF" \
   && grep -qE '^ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10\.0\.1\.20 true$' "$TLF"; then
  pass "S2/row1: auth refused -> exit 3, failed rc=255 reason=auth_refused, no store probe"
else fail "S2/row1: a refused auth did not stop the run before the store probes" "$(ctx)"; fi

# X2 — auth failing with a non-255 rc is still a failure.
run_case x2 "${KEYED[@]}" SHIM_AUTH_RC=1
if [ "$RC" = 3 ] && has_access git-data-auth failed && grep -q 'verdict=failed rc=1 ' "$OUT" && ! grep -q 'findmnt' "$TLF"; then
  pass "X2: auth rc=1 is failed (not only rc=255)"
else fail "X2: a non-255 auth failure was not caught" "$(ctx)"; fi

# S11 / H3 / row 2 — all ok, two-host roster, key set: the first store probe FOLLOWS every access probe.
run_case s11 "${KEYED[@]}" WEB_HOSTS="10.0.1.10 10.0.1.11"
_w1="$(tl_line ' 10\.0\.1\.10 true$')"; _w2="$(tl_line ' 10\.0\.1\.11 true$')"; _j="$(tl_line ' -W 10\.0\.1\.20:22 ')"
_a="$(tl_line '^ssh -F /fixture/gd-ssh-config .* 10\.0\.1\.20 true$')"; _m="$(tl_line ' findmnt -n -o SOURCE --mountpoint ')"
if [ -n "$_w1" ] && [ -n "$_w2" ] && [ -n "$_j" ] && [ -n "$_a" ] && [ -n "$_m" ] \
   && [ "$_w1" -lt "$_w2" ] && [ "$_w2" -lt "$_j" ] && [ "$_j" -lt "$_a" ] && [ "$_a" -lt "$_m" ] \
   && has_access git-data-auth ok && [ "$RC" = 0 ]; then
  pass "S11/H3/row2: all probes ok -> the gate passes; web(10) < web(11) < jump < auth < findmnt probe"
else fail "S11/H3/row2: gate order in the timeline is wrong or the gate did not pass" "w1=$_w1 w2=$_w2 j=$_j a=$_a m=$_m $(ctx)"; fi
if grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.10$' "$TLF" && ! grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.11$' "$TLF"; then
  pass "row10: the jump dials the first roster member"
else fail "row10: the jump did not dial the first roster member" "$(ctx)"; fi

# S6 / row 4 — second roster member refuses.
run_case s6 "${KEYED[@]}" WEB_HOSTS="10.0.1.10 10.0.1.11" SHIM_WEB_REFUSE=10.0.1.11
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.11 verdict=failed rc=255 reason=auth_refused' "$OUT" \
   && ! grep -qE ' -W ' "$TLF" && ! mutating; then
  pass "S6/row4: the second roster member's refusal exits 3 naming it, before the jump"
else fail "S6/row4: a refusing second roster member was not caught" "$(ctx)"; fi

# X3 — a web probe killed by its timeout (rc 124) is failed reason=timeout.
run_case x3 WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=124
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.10 verdict=failed rc=124 reason=timeout' "$OUT" && ! grep -qE ' -W ' "$TLF"; then
  pass "X3: a timed-out web probe (rc 124) is failed reason=timeout"
else fail "X3: a timed-out web probe was not reported as reason=timeout" "$(ctx)"; fi

# S7 / row 3 — empty roster (whitespace: an EMPTY WEB_HOSTS takes the script's default).
run_case s7 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=" "
if [ "$RC" = 3 ] && has_access web web_roster_empty && [ "$(tl_ssh)" = 0 ]; then
  pass "S7/row3: an empty roster exits 3 with web_roster_empty and dials nothing"
else fail "S7/row3: an empty roster was not refused" "$(ctx)"; fi

# S8 — WEB_HOST_SSH unset, and blank-but-set.
for v in unset blank; do
  if [ "$v" = unset ]; then run_case "s8$v"; else run_case "s8$v" WEB_HOST_SSH="   "; fi
  if [ "$RC" = 3 ] && has_access web web_host_ssh_unset && [ "$(tl_ssh)" = 0 ]; then
    pass "S8 ($v): WEB_HOST_SSH $v -> web_host_ssh_unset, exit 3"
  else fail "S8 ($v): WEB_HOST_SSH $v did not produce web_host_ssh_unset + exit 3" "$(ctx)"; fi
done

# S9 — argument hygiene: option-shaped addresses that CONTAIN digits and dots.
run_case s9 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS="-oProxyCommand=/tmp/1.2.sh"
if [ "$RC" = 3 ] && has_access web invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9: an option-shaped roster member is invalid_host and never reaches ssh argv"
else fail "S9: an option-shaped roster member was not refused" "$(ctx)"; fi
run_case s9b WEB_HOST_SSH="$WEB_INV" GIT_DATA_HOST="-oProxyCommand=10.0.0.1"
if [ "$RC" = 3 ] && has_access git-data-jump invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9b: an option-shaped GIT_DATA_HOST is invalid_host before any probe"
else fail "S9b: an option-shaped GIT_DATA_HOST was not refused" "$(ctx)"; fi

# X4 — a multi-line roster is refused as one input, never split two different ways.
run_case x4 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=$'10.0.1.10\n10.0.1.11'
if [ "$RC" = 3 ] && has_access web invalid_multiline_input && [ "$(tl_ssh)" = 0 ]; then
  pass "X4: a multi-line WEB_HOSTS is invalid_multiline_input, nothing dialed"
else fail "X4: a multi-line WEB_HOSTS was not refused" "$(ctx)"; fi

# S10 — key set, web fails: neither jump nor auth is dialed.
run_case s10 "${KEYED[@]}" SHIM_WEB_REFUSE=10.0.1.10
if [ "$RC" = 3 ] && has_access web failed && ! grep -qE ' -W |gd-ssh-config' "$TLF"; then
  pass "S10: a failed web probe stops before the jump and the auth probe"
else fail "S10: probes continued after a failed web probe" "$(ctx)"; fi

# S3 / row 6 — key set, jump returns no banner: jump failed, no auth probe.
FIX_R2_STDERR='channel 0: open failed: administratively prohibited: open failed'
run_case s3 "${KEYED[@]}" SHIM_JUMP=none SHIM_JUMP_STDERR="$FIX_R2_STDERR"$'\n'
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-jump host=10.0.1.20 verdict=failed rc=255 reason=forward_refused' "$OUT" \
   && ! grep -q 'gd-ssh-config' "$TLF" && ! has_access git-data-auth '[a-z_]+'; then
  pass "S3/row6: no banner -> git-data-jump failed reason=forward_refused; the auth probe never ran"
else fail "S3/row6: a failed jump did not stop before the auth probe" "$(ctx)"; fi
if grep -qxF "[git-data-cutover] probe-stderr: ${FIX_R2_STDERR}" "$OUT"; then
  pass "S3: the failed probe's stderr is logged behind the fixed probe-stderr prefix"
else fail "S3: the failed probe's stderr was not logged" "$(ctx)"; fi

# X5 — a final stderr line without a trailing newline is still printed.
run_case x5 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="line-one"$'\n'"last-no-newline"
if grep -qxF '[git-data-cutover] probe-stderr: last-no-newline' "$OUT"; then
  pass "X5: a final stderr line without a newline is not dropped"
else fail "X5: the final stderr line was dropped" "$(ctx)"; fi

# S4 / row 7 — banner then more output with a non-zero rc -> ok.
run_case s4 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=banner_extra
if [ "$RC" = 3 ] && has_access git-data-jump ok && has_access git-data-auth git_data_root_key_absent; then
  pass "S4/row7: banner + more output (ssh rc 255) is jump ok — the verdict keys on the banner, not the rc"
else fail "S4/row7: a banner followed by more output was not read as ok" "$(ctx)"; fi

# S5 / X6 — banner on line 2, and a non-SSH first line -> failed.
for mode in line2 http; do
  run_case "s5$mode" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP="$mode"
  if [ "$RC" = 3 ] && has_access git-data-jump failed; then
    pass "S5 ($mode): a first line that is not an SSH-2.0- banner is jump failed"
  else fail "S5 ($mode): a non-banner first line was accepted" "$(ctx)"; fi
done

# S14 / row 9 — forged workflow commands in probe stderr (both parsers, indented, CR/LF) never
# escape one random-token span, and the token differs per run.
FORGED=$'::error title=git-data-cutover access::role=git-data-jump verdict=ok\r\n  ::add-mask::y\n##[add-mask]x\n##[error]forged\r\n::stop-commands::guess\n'
_toks=()
for k in 1 2; do
  run_case "s14r$k" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FORGED"
  _s14="$(python3 - "$OUT" <<'PY'
import re, sys
raw = open(sys.argv[1], 'rb').read().decode('latin-1')
if '\r' in raw: print('CR present'); sys.exit()
lines = raw.split('\n')
expected_outside = [
    '::notice title=git-data-cutover access::role=web verdict=ok',
    '::error title=git-data-cutover access::role=git-data-jump verdict=failed rc=255 reason=unknown',
]
tok = None; spans = 0; inside = False; forged_inside = 0; outside_cmds = []
for l in lines:
    if inside:
        if l == '::%s::' % tok: inside = False; continue
        if not l.startswith('[git-data-cutover] probe-stderr: '): print('unprefixed line in span: %r' % l[:80]); sys.exit()
        if any(ord(c) < 32 or ord(c) > 126 for c in l): print('non-printable in span'); sys.exit()
        if 'verdict=ok' in l or '##[' in l or '::add-mask::' in l: forged_inside += 1
        continue
    m = re.match(r'^::stop-commands::([0-9a-f]{16,})$', l)
    if m: tok = m.group(1); inside = True; spans += 1; continue
    if '##[' in l: print('legacy command outside span: %r' % l[:100]); sys.exit()
    if l.lstrip().startswith('::'): outside_cmds.append(l.lstrip())
if inside: print('span never closed'); sys.exit()
if outside_cmds != expected_outside: print('outside commands: %r' % outside_cmds); sys.exit()
if spans != 1 or forged_inside < 4: print('spans=%d forged_inside=%d' % (spans, forged_inside)); sys.exit()
print('OK ' + tok)
PY
)"
  case "$_s14" in
    OK\ *) _toks+=("${_s14#OK }"); pass "S14/row9 (run $k): forged ::/##[ bytes stay inside one span; outside it only the two script annotations exist" ;;
    *) fail "S14/row9 (run $k): probe bytes reached the workflow-command parser" "$(printf '%s' "$_s14" | sed 's/::/: :/g; s/##\[/#-#[/g')" ;;
  esac
done
if [ "${#_toks[@]}" = 2 ] && [ "${_toks[0]}" != "${_toks[1]}" ]; then
  pass "S14: the stop-commands token differs between runs"
else fail "S14: the stop-commands token did not vary (${_toks[*]:-none})"; fi

# ── H4 — host identity (#7226): host_key_mismatch reason=changed|unknown|alg ─────────
# ssh's own error text, as OpenSSH 9.x prints it. The classifier keys on ssh's exit code (255)
# plus LINE-ANCHORED patterns, in plan order: alg, unknown, changed — all ahead of auth_refused.
HK_CHANGED=$'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\nIT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!\nHost key for web-1 has changed and you have requested strict checking.\nHost key verification failed.\n'
HK_UNKNOWN=$'No ECDSA host key is known for web-1 and you have requested strict checking.\nHost key verification failed.\n'
HK_ALG=$'Unable to negotiate with 10.0.1.10 port 22: no matching host key type found. Their offer: ssh-ed25519\n'
# case_hk <label> <role> <want-verdict-detail> [VAR=value ...] — exit 3 with exactly this ACCESS
# line and its ::error twin, and nothing dialed past the failing role.
case_hk() {
  local label="$1" role="$2" want="$3" host=10.0.1.10; shift 3
  [ "$role" = web ] || host=10.0.1.20
  run_case "hk-$label" "$@"
  [ "$RC" = 3 ] && grep -qxF "[git-data-cutover] ACCESS role=$role host=$host verdict=$want" "$OUT" \
    && grep -qxF "::error title=git-data-cutover access::role=$role verdict=$want" "$OUT" && ! grep -q 'findmnt' "$TLF"
}
case_hk_changed() { case_hk changed web "host_key_mismatch rc=255 reason=changed" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_STDERR="$HK_CHANGED"; }
case_hk_unknown() { case_hk unknown web "host_key_mismatch rc=255 reason=unknown" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_STDERR="$HK_UNKNOWN"; }
case_hk_alg() { case_hk alg web "host_key_mismatch rc=255 reason=alg" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_STDERR="$HK_ALG"; }
case_hk_rc1() { # the same text on a remote (non-255) exit is not ssh's verdict: failed, never host_key_mismatch
  case_hk rc1 web "failed rc=1 reason=unknown" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=1 SHIM_WEB_STDERR="$HK_CHANGED"
}
case_hk_midline() { # the phrase inside a banner line, not at its start, picks nothing
  case_hk midline web "failed rc=255 reason=unknown" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 \
    SHIM_WEB_STDERR=$'banner: Host key verification failed.\nbanner: @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nbanner: Unable to negotiate with x: no matching host key type found\nbanner: No ECDSA host key is known for web-1\n'
}
case_hk_rc1_unknown() { # the unknown text on a remote (non-255) exit: failed, never host_key_mismatch
  case_hk rc1u web "failed rc=1 reason=unknown" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=1 SHIM_WEB_STDERR="$HK_UNKNOWN"
}
case_hk_rc1_alg() { # the alg text on a remote (non-255) exit: failed, never host_key_mismatch
  case_hk rc1a web "failed rc=1 reason=unknown" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=1 SHIM_WEB_STDERR="$HK_ALG"
}
if case_hk_changed; then pass "HK1: REMOTE HOST IDENTIFICATION HAS CHANGED + Host key verification failed (rc 255) -> role=web verdict=host_key_mismatch reason=changed, exit 3"
else fail "HK1: a changed web-1 host key was not host_key_mismatch reason=changed" "$(ctx)"; fi
if case_hk_unknown; then pass "HK2: No ECDSA host key is known for web-1 (rc 255) -> reason=unknown, ahead of the Host key verification failed line that follows it"
else fail "HK2: an unknown host key was not host_key_mismatch reason=unknown" "$(ctx)"; fi
if case_hk_alg; then pass "HK3: Unable to negotiate … no matching host key type found (rc 255) -> reason=alg"
else fail "HK3: an algorithm mismatch was not host_key_mismatch reason=alg" "$(ctx)"; fi
if case_hk jump git-data-jump "host_key_mismatch rc=255 reason=changed" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR=$'Host key verification failed.\n' \
   && ! grep -q 'gd-ssh-config' "$TLF"; then
  pass "HK4: the jump hop failing host verification -> role=git-data-jump verdict=host_key_mismatch reason=changed; no auth probe"
else fail "HK4: a jump-hop host-key failure was not host_key_mismatch" "$(ctx)"; fi
if case_hk auth git-data-auth "host_key_mismatch rc=255 reason=changed" "${KEYED[@]}" SHIM_AUTH_RC=255 SHIM_AUTH_STDERR=$'Host key for git-data has changed and you have requested strict checking.\nHost key verification failed.\n'; then
  pass "HK5: the git-data hop failing host verification -> role=git-data-auth verdict=host_key_mismatch reason=changed; no store probe"
else fail "HK5: a git-data host-key failure was not host_key_mismatch" "$(ctx)"; fi
if case_hk perm web "failed rc=255 reason=auth_refused" WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10; then
  pass "HK6 (must-PASS): Permission denied (publickey) alone is still failed reason=auth_refused (H3, not H4)"
else fail "HK6: a plain auth refusal changed verdict" "$(ctx)"; fi
if case_hk_rc1; then pass "HK7: host-key text on a non-255 exit -> failed reason=unknown (the verdict needs ssh's own exit code)"
else fail "HK7: host-key text on a remote exit picked host_key_mismatch" "$(ctx)"; fi
if case_hk_rc1_unknown; then pass "HK7b: 'No ECDSA host key is known' on a non-255 exit -> failed reason=unknown, not host_key_mismatch"
else fail "HK7b: the unknown-key text on a remote exit picked host_key_mismatch" "$(ctx)"; fi
if case_hk_rc1_alg; then pass "HK7c: 'no matching host key type found' on a non-255 exit -> failed reason=unknown, not host_key_mismatch"
else fail "HK7c: the alg text on a remote exit picked host_key_mismatch" "$(ctx)"; fi
if case_hk_midline; then pass "HK8: the H4 phrases (changed, alg, unknown) inside banner lines (not line-anchored) -> failed reason=unknown"
else fail "HK8: an unanchored H4 phrase picked a verdict" "$(ctx)"; fi
if grep -qxF '[git-data-cutover] probe-stderr: @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' "$T/hk-changed.out"; then
  pass "HK9: the raw ssh text of a host_key_mismatch is printed behind the probe-stderr prefix, inside the stop-commands span"
else fail "HK9: the host-key failure's stderr was not printed behind its prefix" "$(tr '\n' '|' < "$T/hk-changed.out" | sed 's/::/: :/g' | cut -c1-400)"; fi
# HK10 — a hostile banner (U+2028/U+2029, DEL, ESC, ::error:: and verdict=ok) on a host-key failure
# changes neither the verdict nor the annotation set; every control byte is stripped before echo.
HK_HOSTILE=$'::error title=git-data-cutover access::role=web verdict=ok\nverdict=ok\n\xe2\x80\xa8::add-mask::z\xe2\x80\xa9\x7f\x1b[31mred\nHost key verification failed.\n'
run_case hk-hostile WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_STDERR="$HK_HOSTILE"
_hk10="$(python3 - "$OUT" <<'PY2'
import re, sys
raw = open(sys.argv[1], 'rb').read()
if any(b in raw for b in (b'\x7f', b'\x1b', b'\xe2\x80\xa8', b'\xe2\x80\xa9', b'\r')): print('control bytes survived'); sys.exit()
lines = raw.decode('ascii').split('\n')
tok = None; inside = False; outside = []
for l in lines:
    if inside:
        if l == '::%s::' % tok: inside = False
        elif not l.startswith('[git-data-cutover] probe-stderr: '): print('unprefixed %r' % l[:60]); sys.exit()
        continue
    m = re.match(r'^::stop-commands::([0-9a-f]{16,})$', l)
    if m: tok = m.group(1); inside = True; continue
    if l.lstrip().startswith('::'): outside.append(l.lstrip())
if inside: print('span never closed'); sys.exit()
want = ['::error title=git-data-cutover access::role=web verdict=host_key_mismatch rc=255 reason=changed']
print('OK' if outside == want else 'outside %r' % outside)
PY2
)"
if [ "$RC" = 3 ] && [ "$_hk10" = OK ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.10 verdict=host_key_mismatch rc=255 reason=changed' "$OUT"; then
  pass "HK10: a banner carrying ::error::, verdict=ok, U+2028/U+2029, DEL and ESC leaves the verdict host_key_mismatch; control bytes stripped, commands confined to the span"
else fail "HK10: hostile banner text changed the verdict or escaped the span" "rc=$RC $(printf '%s' "$_hk10" | sed 's/::/: :/g')"; fi
run_case hk-okbanner "${KEYED[@]}" SHIM_WEB_OK_STDERR=$'::error title=git-data-cutover access::role=web verdict=failed\nHost key verification failed.\n'
if [ "$RC" = 0 ] && has_access web ok && ! grep -q 'probe-stderr' "$OUT" && [ "$(grep -c '^::error' "$OUT")" = 0 ]; then
  pass "HK11: a successful probe (rc 0) whose stderr forges a failure stays ok; its stderr is never printed"
else fail "HK11: stderr on a successful probe changed the verdict or was printed" "$(ctx)"; fi

# X10 — xtrace refusal: the script refuses to run under -x before doing anything.
TLF="$T/x10.tl"; OUT="$T/x10.out"; : > "$TLF"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" WEB_HOST_SSH="$WEB_INV" bash -x "$SCRIPT" > "$OUT" 2>&1
RC=$?
if [ "$RC" = 78 ] && [ ! -s "$TLF" ]; then pass "X10: under bash -x the script exits 78 before any ssh or doppler call"
else fail "X10: the xtrace refusal did not fire first" "$(ctx)"; fi

# AC5 — no `${X_SSH:-ssh}`-style fallback in any form (comment-stripped code).
_code="$(sed -E 's/^[[:space:]]*#.*$//' "$SCRIPT")"
if ! grep -qE '_SSH:?[-=]ssh\}' <<< "$_code"; then
  pass "AC5: no \${*_SSH:-ssh} / :=ssh / -ssh / =ssh fallback in git-data-cutover.sh"
else fail "AC5: an ssh fallback expansion survives" "$(grep -nE '_SSH:?[-=]ssh\}' <<< "$_code")"; fi

# X11 — the script's GIT_DATA_HOST default is the Terraform-owned private address.
_tf_ip="$(sed -nE 's/^[[:space:]]*git_data_private_ip[[:space:]]*=[[:space:]]*"([0-9.]+)".*$/\1/p' "$DIR/git-data.tf" | head -1)"
_sh_ip="$(sed -nE 's/^GIT_DATA_HOST="\$\{GIT_DATA_HOST:-([0-9.]+)\}".*$/\1/p' "$SCRIPT" | head -1)"
if [ -n "$_tf_ip" ] && [ "$_tf_ip" = "$_sh_ip" ]; then pass "X11: GIT_DATA_HOST default ($_sh_ip) equals git-data.tf local.git_data_private_ip"
else fail "X11: GIT_DATA_HOST default '$_sh_ip' != git-data.tf '$_tf_ip'"; fi

# ── AC2 — the canonical read-only proof and its exact remote timeline ─────────────────
cat > "$T/ac2.expected" <<'EXP'
ssh -F /dev/null -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/fixture/web-1.known_hosts -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20 10.0.1.10 true
ssh -F /dev/null -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/fixture/web-1.known_hosts -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20 -W 10.0.1.20:22 10.0.1.10
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 true
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 findmnt -n -o SOURCE --mountpoint /mnt/git-data
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 r=/mnt/git-data; src=/dev/mapper/git-data; mk=/etc/git-data/store-verified; d=/mnt/git-data/repositories; fz="$r/.cutover-freeze"; s=$(findmnt -n -o SOURCE --mountpoint "$r") || exit 5; [ "$s" = "$src" ] || exit 6; [ ! -e "$fz" ] || exit 23; fu=$(findmnt -n -o UUID --mountpoint "$r") || exit 5; [ -n "$fu" ] || exit 24; [ -f "$mk" ] && [ -s "$mk" ] || exit 21; m=$(head -n 1 "$mk") || exit 16; [ "$m" = "$fu" ] || exit 22; if [ -L "$d" ] && [ ! -e "$d" ]; then exit 3; fi; if [ ! -e "$d" ]; then exit 7; fi; [ -d "$d" ] || exit 3; dr=$(readlink -f "$d") && rr=$(readlink -f "$r") && t=$(stat -c %m "$dr") || exit 9; [ "$t" = "$rr" ] || exit 8; n=$(find -H "$d" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name '.init.lock' ! -name lost+found -printf .) || exit 4; echo "${#n}"
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 h=/mnt/git-data/hooks; p="$h/pre-receive"; src=/dev/mapper/git-data; sp=/mnt/git-data/hooks; w=/usr/local/bin/git-data-transport-wrapper.sh; [ -L "$h" ] && exit 10; [ -d "$h" ] || exit 10; [ -L "$p" ] && exit 12; [ -f "$p" ] && [ -x "$p" ] || exit 12; oh=$(stat -c '%U:%G %a' "$h") || exit 16; op=$(stat -c '%U:%G %a' "$p") || exit 16; [ "$oh" = "root:git 750" ] || exit 11; [ "$op" = "root:root 755" ] || exit 13; pp=$(stat -c '%U %a' "${h%/*}") || exit 16; case "$pp" in "root "[0-7][0145][0145]|"root "[0-7][0-7][0145][0145]) ;; *) exit 19 ;; esac; runuser -u git -- true || exit 16; runuser -u git -- test -r "$p" && runuser -u git -- test -x "$p" || exit 17; v=$(env -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM git config --system --includes --get core.hooksPath); g=$?; [ "$g" -le 1 ] || exit 16; [ "$v" = "$sp" ] || exit 14; grep -qxF -- HOOKS_DIR=\"\$\{GIT_DATA_HOOKS_DIR:-/mnt/git-data/hooks\}\" "$w" && grep -qxF -- exec\ git\ -c\ \"core.hooksPath=\$\{HOOKS_DIR\}\"\ \"\$\{verb#git-\}\"\ \"\$repo_real\" "$w" || exit 18; s=$(findmnt -no SOURCE -T "$h") || exit 5; [ "$s" = "$src" ] || exit 15; s=$(findmnt -no SOURCE -T "$p") || exit 5; [ "$s" = "$src" ] || exit 15; echo ok
EXP
# case_ac2_timeline <run-name> — the recorded remote timeline equals the expected file exactly.
case_ac2_timeline() {
  run_case "$1" "${KEYED[@]}" GITHUB_STEP_SUMMARY="$T/$1.summary"
  diff <(grep -E '^(ssh|doppler) ' "$TLF") "$T/ac2.expected" > "$T/$1.diff" 2>&1
}
case_ac2_timeline ac2
_ac2_diff_rc=$?
# case_ac2_clear — the canonical run (mapper source, bound marker, no freeze, count 0, fence ok)
# exits 0 with every store probe ok. A function, so a harness mutant can re-run it.
case_ac2_clear() {
  [ "$RC" = 0 ] && has_store store-mounted ok && has_store store-on-mapper ok && has_store store-verified ok \
    && has_store store-empty ok && has_store fence-shape ok \
    && grep -qxF '::notice title=git-data-cutover store::verdict=clear' "$OUT"
}
if case_ac2_clear; then
  pass "AC2: key present, the LUKS mapper serving, the marker bound, not frozen, empty store, fence intact -> exit 0 with every store probe and the fence probe ok"
else fail "AC2: the canonical read-only proof did not exit 0 clear" "$(ctx)"; fi
if [ "$_ac2_diff_rc" = 0 ]; then
  pass "AC2: diff of the recorded remote timeline against the expected file is empty (web, jump, auth, findmnt, the store session, fence — nothing else)"
else fail "AC2: the remote timeline differs from the expected file" "$(tr '\n' '|' < "$T/ac2.diff" | cut -c1-500)"; fi
if [ "$(grep '^timeout ' "$TLF" | paste -sd' ' -)" = "timeout 30 timeout 25 timeout 30 timeout 30 timeout 30 timeout 30" ] \
   && [ "$(grep -c '^ssh-stdin /dev/null$' "$TLF")" = 6 ] && [ "$(grep -c '^ssh-stdin ' "$TLF")" = 6 ]; then
  pass "AC2/G5: every remote call is bounded (30/25/30/30/30/30) with stdin /dev/null"
else fail "AC2/G5: a remote call lost its bound or its /dev/null stdin" "$(tr '\n' '|' < "$TLF" | cut -c1-500)"; fi
if [ "$(grep -E '^::' "$OUT")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::notice title=git-data-cutover access::role=git-data-auth verdict=ok
::notice title=git-data-cutover store::probe=store-mounted verdict=ok
::notice title=git-data-cutover store::probe=store-on-mapper verdict=ok
::notice title=git-data-cutover store::probe=store-verified verdict=ok
::notice title=git-data-cutover store::probe=store-empty verdict=ok
::notice title=git-data-cutover store::probe=fence-shape verdict=ok
::notice title=git-data-cutover store::verdict=clear" ] && ! grep -q '/dev/mapper' "$OUT"; then
  pass "AC2: exactly nine ::notice annotations of fixed words; the captured device name is never printed"
else fail "AC2: annotation set differs, or the captured value was printed" "$(grep -E '^::|/dev/mapper' "$OUT" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# ── GUARD 2 — store probes fail closed ────────────────────────────────────────────────
# Each case is a function so a mutant can re-run exactly the case its matrix row names.
case_unmounted_empty() { # findmnt rc 0 with an empty source
  run_case g2empty "${KEYED[@]}" SHIM_FINDMNT=empty
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted' "$OUT" && no_count_probe
}
case_mount_transport() { # the findmnt read dies in ssh itself (rc 255): a probe error, not a store state
  run_case g2rc255 "${KEYED[@]}" SHIM_FINDMNT=rc255
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=probe_failed rc=255' "$OUT" && no_count_probe \
    && grep -qxF '::error title=git-data-cutover store::probe=store-mounted verdict=probe_failed rc=255' "$OUT"
}
# ADR-239 D1: the render serves only the mapper, so a plaintext source is refused before any
# further probe is dialed (neither the store-verified session nor the count).
no_verify_probe() { ! grep -qE '^ssh .* 10\.0\.1\.20 r=' "$TLF"; }
no_fence_probe() { ! grep -qE '^ssh .* 10\.0\.1\.20 h=' "$TLF"; }
case_not_mapper() {
  run_case g2plain "${KEYED[@]}" SHIM_FINDMNT=plain
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-on-mapper verdict=store_not_on_mapper' "$OUT" && no_count_probe && no_verify_probe \
    && grep -qxF '::error title=git-data-cutover store::probe=store-on-mapper verdict=store_not_on_mapper' "$OUT"
}
case_probe_error() {
  run_case g2err "${KEYED[@]}" SHIM_COUNT=err
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=4' "$OUT" \
    && grep -qxF '[git-data-cutover] probe-stderr: find: cannot open directory: Permission denied' "$OUT"
}
# The mutating-verb census over every non-comment line (whole-line and ` # ` trailing comments
# stripped). At least 50 lines must be scanned. Re-admitting rsync here is the #8211 rebuild, and
# that copy must also carry hooks/ in both passes (#8101).
case_verb_census() { # <script>
  local code n hits
  # PR2: the write verbs legitimately live INSIDE the mode functions' remote-command
  # strings (systemctl/rm/flock/runuser run on git-data via gd_exec, never on this host).
  # The census exempts those function bodies; a mutating verb anywhere else — or a
  # resurrected deleted-function name ANYWHERE — still trips it.
  code="$(sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]+# .*$//' "$1" | awk '
    /^(mode_freeze|mode_unfreeze|mode_probe|probe_freeze|require_lineage|gd_exec)\(\) \{/ {skip=1; next}
    skip && /^\}/ {skip=0; next}
    !skip' | grep -vE '^[[:space:]]*$')"
  n="$(printf '%s\n' "$code" | wc -l)"
  hits="$(printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z0-9_-])(rsync|cryptsetup|mount|umount|mkfs(\.[a-z0-9]+)?|touch|systemctl|doppler|web_ssh)([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_-])rm[[:space:]]+-[A-Za-z]*(rf|fr)|soleur-(web|drain)|(bulk|delta)_rsync|repoint_luks_[a-z_]+|canary_luks_[a-z_]+|old_volume_[a-z_]+|prepare_luks_[a-z_]+|verify_set_identity|(acquire|release)_freeze|flip_flag_and_reload' || true)"
  CENSUS_DETAIL="scanned=$n hits=[$(printf '%s' "$hits" | tr '\n' '|' | cut -c1-300)]"
  [ "$n" -ge 50 ] && [ -z "$hits" ]
}

if case_unmounted_empty; then pass "S4b/G2: findmnt exits 0 with an EMPTY source -> old_store_unmounted (no rc: the read itself succeeded), exit 5, count never dialed"
else fail "S4b/G2: an empty findmnt source was accepted" "$(ctx)"; fi
run_case g2rc1 "${KEYED[@]}" SHIM_FINDMNT=rc1
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=1' "$OUT" && no_count_probe; then
  pass "S4/G2: findmnt non-zero -> old_store_unmounted rc=1, exit 5"
else fail "S4/G2: a failing findmnt was not refused" "$(ctx)"; fi
run_case g2tmpfs "${KEYED[@]}" SHIM_FINDMNT=tmpfs
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted' "$OUT" && no_count_probe; then
  pass "S4c/G2: a non-device source (tmpfs) is old_store_unmounted (no rc)"
else fail "S4c/G2: a non-device source was accepted" "$(ctx)"; fi
if case_mount_transport; then pass "S4d/G2: findmnt read failing in ssh (rc 255) -> probe_failed rc=255, never old_store_unmounted"
else fail "S4d/G2: a transport failure was reported as a store state" "$(ctx)"; fi
if case_not_mapper; then pass "S5/G2: findmnt names a plaintext device -> store_not_on_mapper, exit 5, store-verified and count never dialed"
else fail "S5/G2: a store not served by the mapper was not refused" "$(ctx)"; fi
run_case g2one "${KEYED[@]}" SHIM_COUNT=one
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=store_not_empty' "$OUT"; then
  pass "S6/G2: a count of 1 -> store_not_empty, exit 5"
else fail "S6/G2: a non-empty store was not refused" "$(ctx)"; fi
if case_probe_error; then pass "G2: a failing count probe -> probe_failed rc=4, its stderr printed behind the fixed prefix"
else fail "G2: a failing count probe was not probe_failed" "$(ctx)"; fi
run_case g2nl "${KEYED[@]}" SHIM_COUNT=zero2nl
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=96' "$OUT"; then
  pass "G5: only ONE trailing newline is stripped — \"0\\n\\n\" is probe_failed rc=96"
else fail "G5: a count with two trailing newlines was accepted" "$(ctx)"; fi
run_case g2noeol "${KEYED[@]}" SHIM_FINDMNT=noeol
if [ "$RC" = 0 ] && has_store store-mounted ok && has_store store-on-mapper ok; then pass "H2: a mapper source with no trailing newline is accepted (the count row covers one trailing newline)"
else fail "H2: a source without a trailing newline was refused" "$(ctx)"; fi

# The store session EXECUTED against a synthesized store (SHIM_VERIFY=exec runs the remote bytes
# locally), so the missing / not-a-directory / symlink / mount semantics are the command's own. Every
# root carries a bound marker at <root>/store-verified, so the count stage is reached.
_store() { # <name> — a fresh fixture store root under $T, with a bound marker
  assert_fixture_dir "$T/store-$1"
  rm -rf "$T/store-$1"; mkdir -p "$T/store-$1" || { printf 'FAIL SETUP: mkdir store\n' >&2; exit 1; }
  printf '%s\n' "$FIX_UUID" > "$T/store-$1/store-verified" || { printf 'FAIL SETUP: marker\n' >&2; exit 1; }
  printf '%s' "$T/store-$1"
}
# case_store_exec <root> <run-name> [VAR=value ...] — the store session executed over <root>.
case_store_exec() {
  local sr="$1" nm="$2"; shift 2
  run_case "$nm" "${KEYED[@]}" SHIM_VERIFY=exec OLD_ROOT="$sr" STORE_VERIFIED="$sr/store-verified" "$@"
}
# `_store`'s own guard runs inside `$( )`, where `exit` kills only the subshell and the caller
# binds "" — so each binding is re-guarded HERE, in the shell that performs the writes.
case_missing_repos() { # a mounted root with no repositories dir: bootstrap always creates it
  local sr
  sr="$(_store missing)"; assert_fixture_dir "$sr"
  case_store_exec "$sr" g2missing
  [ "$RC" = 5 ] && has_store store-verified ok && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=7' "$OUT"
}
case_other_mount() { # the repositories dir's containing mount is not the store root
  local sr
  sr="$(_store othermnt)"; assert_fixture_dir "$sr"; mkdir -p "$sr/repositories"
  case_store_exec "$sr" g2othermnt SHIM_STAT_M=/elsewhere
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=8' "$OUT"
}
if case_missing_repos; then pass "S7/H2: a mounted root with NO repositories dir -> probe_failed rc=7 (git-data-bootstrap.sh creates it; absent is abnormal, never a count of 0)"
else fail "S7/H2: a missing repositories dir was not probe_failed rc=7" "$(ctx)"; fi
if case_other_mount; then pass "S7e: repositories whose containing mount is not the store root (a second mount over it) -> probe_failed rc=8"
else fail "S7e: a count on another mount was accepted" "$(ctx)"; fi
_sr="$(_store mfail)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories"
case_store_exec "$_sr" g2mfail SHIM_STAT_M=fail
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=9' "$OUT"; then
  pass "S7f: stat unable to resolve the repositories mount -> probe_failed rc=9"
else fail "S7f: an unresolvable mount was not probe_failed rc=9" "$(ctx)"; fi
_sr="$(_store dangling)"; assert_fixture_dir "$_sr"; ln -s "$_sr/nowhere" "$_sr/repositories"
case_store_exec "$_sr" g2dangling
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=3' "$OUT"; then
  pass "S7g: a dangling repositories symlink -> probe_failed rc=3, never a count of 0"
else fail "S7g: a dangling symlink was not probe_failed rc=3" "$(ctx)"; fi
_sr="$(_store other)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories/notes" && : > "$_sr/repositories/x.gitx" && : > "$_sr/repositories/README"
_S7B_ROOT="$_sr"
case_any_entry() { case_store_exec "$_S7B_ROOT" g2other; [ "$RC" = 5 ] && has_store store-empty store_not_empty; }
if case_any_entry; then pass "S7b: entries that are not *.git count too (the bootstrap's _repo_count rule: a partial x/ is user data) -> store_not_empty"
else fail "S7b: a non-*.git entry under repositories/ was not counted" "$(ctx)"; fi
_sr="$(_store locks)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories/lost+found" && : > "$_sr/repositories/.boot-probe-0.init.lock" && : > "$_sr/repositories/.ws-9.init.lock"
_S7H_ROOT="$_sr"
case_locks_skipped() { case_store_exec "$_S7H_ROOT" g2locks; [ "$RC" = 0 ] && has_store store-empty ok; }
if case_locks_skipped; then pass "S7h (must-PASS): lock dotfiles and lost+found do not count (the bootstrap's exclusions) -> clear"
else fail "S7h: a lock dotfile or lost+found was counted" "$(ctx)"; fi
_sr="$(_store realrepo)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories/ws-1.git"
case_store_exec "$_sr" g2realrepo
if [ "$RC" = 5 ] && has_store store-empty store_not_empty; then pass "S6b: one real *.git entry under the store -> store_not_empty"
else fail "S6b: a real repository entry was not counted" "$(ctx)"; fi
_sr="$(_store symlink)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/target/ws-2.git" && ln -s "$_sr/target" "$_sr/repositories"
case_store_exec "$_sr" g2symlink
if [ "$RC" = 5 ] && has_store store-empty store_not_empty; then pass "S7c: a symlinked repositories dir is followed (find -H) -> store_not_empty"
else fail "S7c: a symlinked repositories dir hid a repository" "$(ctx)"; fi
_sr="$(_store notdir)"; assert_fixture_dir "$_sr"; : > "$_sr/repositories"
case_store_exec "$_sr" g2notdir
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=3' "$OUT"; then
  pass "S7d: a repositories path that is not a directory -> probe_failed rc=3"
else fail "S7d: a non-directory repositories path was not a probe error" "$(ctx)"; fi
# P4 — the count's exclusions are the bootstrap's `_repo_count` exclusions, both sides exactly once.
case_count_parity() { # <script> <bootstrap>
  local sx bx
  sx="$(grep -oE "find -H [^)]*-printf \." "$1" | grep -oE "! -name [^ ]+" | tr -d "'" | LC_ALL=C sort | paste -sd' ' -)"
  bx="$(awk '/^_repo_count\(\) \{/,/^\}/' "$2" | grep -oE "! -name [^ ]+" | tr -d "'" | LC_ALL=C sort | paste -sd' ' -)"
  COUNT_PARITY_DETAIL="script=[$sx] bootstrap=[$bx]"
  [ -n "$sx" ] && [ "$sx" = "$bx" ] && [ "$(grep -cE "find -H [^)]*-printf \." "$1")" = 1 ]
}
if case_count_parity "$SCRIPT" "$DIR/git-data-bootstrap.sh"; then pass "P4: the count skips exactly what the bootstrap's _repo_count skips ($COUNT_PARITY_DETAIL)"
else fail "P4: the count's exclusions drifted from the bootstrap's _repo_count" "$COUNT_PARITY_DETAIL"; fi

if case_verb_census "$SCRIPT"; then pass "G2 census: no rsync/cryptsetup/mount/umount/mkfs/touch/rm -rf/systemctl/doppler/web_ssh or deleted cutover function in the script ($CENSUS_DETAIL)"
else fail "G2 census: a mutating verb or deleted function survives" "$CENSUS_DETAIL"; fi

# G2/G7 order: main() calls, as plain statements, each exactly once and in this order.
case_main_order() { # <script>
  local main calls
  main="$(awk '/^main\(\) \{/{m=1; next} m && /^\}/{exit} m' "$1" | sed -E 's/^[[:space:]]*#.*$//' | grep -vE '^[[:space:]]*$')"
  calls="$(printf '%s\n' "$main" | grep -oE '(refuse_legacy_modes|resolve_roster|refuse_if_config_unsafe|access_gate|refuse_if_unmounted|refuse_if_not_on_mapper|refuse_if_store_unverified_or_not_empty|refuse_if_fence_not_intact)([[:space:]]*$)|[a-z_]+\)[[:space:]]*(mode_freeze|mode_unfreeze|mode_probe)[[:space:]]*;;$' | sed -E 's/^([a-z_]+\)[[:space:]]*)?([a-z_]+).*$/\2/' | paste -sd, -)"
  ORDER_DETAIL="$calls"
  [ "$calls" = "refuse_legacy_modes,resolve_roster,refuse_if_config_unsafe,access_gate,refuse_if_unmounted,refuse_if_not_on_mapper,refuse_if_store_unverified_or_not_empty,refuse_if_fence_not_intact,mode_freeze,mode_unfreeze,mode_probe" ] \
    && [ "$(grep -cE '(\$\(|`|\||&&)[^#]*(access_gate|refuse_if_|refuse_legacy_modes)|(access_gate|refuse_if_[a-z_]+|refuse_legacy_modes)[[:space:]]*(\|\||&&|\|)' "$1" || true)" = 0 ]
}
if case_main_order "$SCRIPT"; then pass "H5: main() runs refuse_legacy_modes, resolve_roster, then MODE-dispatch — the proof arm in probe order, the mode verbs via mode_*"
else fail "H5: main() order/shape is wrong" "calls=[$ORDER_DETAIL]"; fi

# ── CONFIG — every configurable path is a safe literal before anything is printed or dialed ──
# case_config <label> <reason> <VAR=value> — probe=config refuses, NOTHING is dialed (not even the
# access gate), and the raw value never reaches the output.
case_config() {
  local label="$1" reason="$2" kv="$3"
  run_case "cfg-$label" "${KEYED[@]}" "$kv"
  CONFIG_VALUE="${kv#*=}"
  [ "$RC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=config verdict=probe_failed reason=$reason" "$OUT" \
    && [ "$(tl_ssh)" = 0 ] && ! grep -qF -- "${CONFIG_VALUE:-@@none@@}" "$OUT"
}
case_arg_root() { case_config root-semi arg_root 'OLD_ROOT=/x;touch /tmp/p'; }
case_arg_marker() { case_config marker-rel arg_marker STORE_VERIFIED=rel/marker; }
case_arg_mapper_nl() { case_config mapper-nl arg_mapper "LUKS_MAPPER=$(printf '/dev/x\nqz7w')"; }
case_arg_subdir() { case_config subdir-slash arg_subdir 'REPO_SUBDIR=a/b'; }
for spec in "root-semi|arg_root|OLD_ROOT=/x;touch /tmp/p" "root-nl|arg_root|OLD_ROOT=$(printf '/mnt/x\n::error::forged')" \
            "marker-rel|arg_marker|STORE_VERIFIED=rel/marker" "marker-semi|arg_marker|STORE_VERIFIED=/etc/x;y" \
            "marker-nl|arg_marker|STORE_VERIFIED=$(printf '/etc/x\nqz7w')" \
            "mapper-nl|arg_mapper|LUKS_MAPPER=$(printf '/dev/x\nqz7w')" "mapper-semi|arg_mapper|LUKS_MAPPER=/dev/x;y" \
            "subdir-slash|arg_subdir|REPO_SUBDIR=a/b" "subdir-dotdot|arg_subdir|REPO_SUBDIR=.." "subdir-nl|arg_subdir|REPO_SUBDIR=$(printf 'sub7q\nqz7w')" \
            "wrapper-rel|arg_wrapper|TRANSPORT_WRAPPER=rel/wrapper"; do
  IFS='|' read -r -d '' _lbl _why _kv <<< "$spec" || true
  _kv="${_kv%$'\n'}"
  if case_config "$_lbl" "$_why" "$_kv"; then pass "CFG ($_lbl): an unsafe value -> probe=config probe_failed reason=$_why, nothing dialed, the value never printed"
  else fail "CFG ($_lbl): an unsafe configured value was not refused before any dial, or was printed" "$(ctx)"; fi
done

# ── GUARD 1 — the store is served by the configured LUKS mapper (ADR-239 D1) ──────────
# case_ord — a plaintext source AND a non-empty count: the on-mapper refusal must win, so moving the
# call after the store session is observable (it would read store_not_empty).
case_ord() {
  run_case g1ord "${KEYED[@]}" SHIM_FINDMNT=plain SHIM_COUNT=one SHIM_VERIFY=ok
  [ "$RC" = 5 ] && has_store store-on-mapper store_not_on_mapper && ! grep -q 'store_not_empty' "$OUT"
}
case_map_pre() { # a mapper whose name merely STARTS with the configured one
  run_case g1pre "${KEYED[@]}" SHIM_FINDMNT=mapperpre
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-on-mapper verdict=store_not_on_mapper' "$OUT" && no_verify_probe
}
if case_ord; then pass "ORD: a plaintext source with a non-empty store reads store_not_on_mapper, never store_not_empty"
else fail "ORD: the on-mapper refusal did not come first" "$(ctx)"; fi
if case_map_pre; then pass "MAP-PRE: /dev/mapper/git-data-plain is not the configured mapper -> store_not_on_mapper (string equality, not a prefix)"
else fail "MAP-PRE: a mapper sharing the configured prefix was accepted" "$(ctx)"; fi

# ── GUARD 2 — a pass is backed by the bootstrap's verified-store evidence (ADR-239 D3) ──
# case_verify <mode> <expected-verdict> [VAR=value ...] — SHIM_VERIFY=<mode> (canned session answer)
# refused at the store-verified stage: exit 5, the exact line, no store-empty line, no fence dialed.
case_verify() {
  local mode="$1" want="$2"; shift 2
  run_case "v-$mode" "${KEYED[@]}" SHIM_VERIFY="$mode" "$@"
  [ "$RC" = 5 ] && has_store store-on-mapper ok \
    && grep -qxF "[git-data-cutover] STORE probe=store-verified verdict=$want" "$OUT" \
    && ! grep -q 'probe=store-empty' "$OUT" && no_fence_probe && ! grep -q 'verdict=clear' "$OUT"
}
# case_verify_empty <mode> <expected-verdict> — refused at the store-empty stage: every store-verified
# fact held (its ok line), then the exact store-empty line, no fence dialed.
case_verify_empty() {
  local mode="$1" want="$2"; shift 2
  run_case "ve-$mode" "${KEYED[@]}" SHIM_VERIFY="$mode" "$@"
  [ "$RC" = 5 ] && has_store store-verified ok \
    && grep -qxF "[git-data-cutover] STORE probe=store-empty verdict=$want" "$OUT" && no_fence_probe
}
case_v21() { case_verify r21 "store_unverified reason=marker_absent"; }
case_v22() { case_verify r22 "store_unverified reason=marker_mismatch"; }
case_v16() { case_verify r16 "probe_failed rc=16"; }
case_v127() { case_verify r127 "probe_failed rc=127"; }
case_v8() { case_verify_empty r8 "probe_failed rc=8"; }
for spec in "V24:r24:store_unverified reason=no_fs_uuid" "V21:r21:store_unverified reason=marker_absent" \
            "V22:r22:store_unverified reason=marker_mismatch" "V23:r23:cutover_frozen" \
            "V5:r5:probe_failed rc=5" "V6:r6:probe_failed rc=6" "V16:r16:probe_failed rc=16" \
            "V127:r127:probe_failed rc=127" "V255:r255:probe_failed rc=255"; do
  IFS=: read -r _id _m _w <<< "$spec"
  if case_verify "$_m" "$_w"; then pass "$_id ($_m): remote exit ${_m#r} -> store-verified $_w, exit 5; no store-empty verdict, fence never dialed"
  else fail "$_id ($_m): expected store-verified $_w" "$(ctx)"; fi
done
for spec in "VE3:r3:probe_failed rc=3" "VE4:r4:probe_failed rc=4" "VE7:r7:probe_failed rc=7" \
            "VE8:r8:probe_failed rc=8" "VE9:r9:probe_failed rc=9"; do
  IFS=: read -r _id _m _w <<< "$spec"
  if case_verify_empty "$_m" "$_w"; then pass "$_id ($_m): remote exit ${_m#r} is the count stage -> store-verified ok, then store-empty $_w"
  else fail "$_id ($_m): expected store-verified ok then store-empty $_w" "$(ctx)"; fi
done
if grep -qxF '::error title=git-data-cutover store::probe=store-verified verdict=store_unverified reason=marker_mismatch' "$T/v-r22.out"; then
  pass "V22: the reason word reaches the ::error annotation"
else fail "V22: the reason word did not reach the annotation" "$(grep -E '^::' "$T/v-r22.out" | tr '\n' '|' | sed 's/::/: :/g')"; fi
if case_verify_empty line2 "probe_failed rc=96" && ! grep -q 'CANARY-VERIFY-LINE-2' "$OUT"; then
  pass "Vline2: an answer with an injected second line is store-empty probe_failed rc=96 and the canary is never printed"
else fail "Vline2: a multi-line session answer was accepted or printed" "$(ctx)"; fi
case_vempty() { case_verify_empty empty "probe_failed rc=96"; }
case_vnotok() { case_verify_empty notok "probe_failed rc=96"; }
case_vx0() { case_verify_empty x0 "probe_failed rc=96"; }
if case_vempty; then pass "Vempty: an empty exit-0 answer is store-empty probe_failed rc=96"
else fail "Vempty: an empty answer was accepted" "$(ctx)"; fi
if case_vnotok; then pass "Vnotok: an exit-0 answer 'nok' is store-empty probe_failed rc=96"
else fail "Vnotok: a non-count answer was accepted" "$(ctx)"; fi
if case_vx0; then pass "Vx0: an exit-0 answer 'x0' is store-empty probe_failed rc=96 (the anchor is ^[0-9]+\$, not [0-9]+)"
else fail "Vx0: a count with a leading non-digit was accepted" "$(ctx)"; fi
# VINJ — hostile remote stderr on a refusal cannot raise an annotation of its own.
run_case vinj "${KEYED[@]}" SHIM_VERIFY=r22 SHIM_VERIFY_STDERR=$'::error::x\n::add-mask::y\n'
if [ "$RC" = 5 ] && has_store store-verified store_unverified \
   && [ "$(grep -E '^::(notice|error|warning|add-mask)' "$OUT")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::notice title=git-data-cutover access::role=git-data-auth verdict=ok
::notice title=git-data-cutover store::probe=store-mounted verdict=ok
::notice title=git-data-cutover store::probe=store-on-mapper verdict=ok
::error title=git-data-cutover store::probe=store-verified verdict=store_unverified reason=marker_mismatch" ] \
   && grep -qxF '[git-data-cutover] probe-stderr: ::error::x' "$OUT" && grep -qE '^::stop-commands::[0-9a-f]{16,}$' "$OUT"; then
  pass "VINJ: remote stderr carrying ::error:: and ::add-mask:: appears only behind probe-stderr: inside the stop-commands span; the only annotations are the fixed ones"
else fail "VINJ: remote stderr raised an annotation or escaped its span" "$(grep -E '^::' "$OUT" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# VX — the store session EXECUTED (SHIM_VERIFY=exec runs the remote bytes locally) against a fixture
# root holding an empty repositories dir and its marker at <root>/store-verified; it never reads the
# runner's /mnt/git-data or /etc/git-data, and every fixture path lives inside the guarded root.
_vxroot() { # <name> — a fresh fixture root
  assert_fixture_dir "$T/vx-$1"
  rm -rf "$T/vx-$1"; mkdir -p "$T/vx-$1/repositories" || { printf 'FAIL SETUP: mkdir vx root\n' >&2; exit 1; }
  printf '%s' "$T/vx-$1"
}
# case_vx <root> <expected> [VAR=value ...] — `ok` must clear with exit 0; anything else is the exact
# store-verified line, exit 5, no store-empty verdict and no fence dialed.
case_vx() {
  local root="$1" want="$2" nm; shift 2
  nm="vx-$(basename "$root")"
  run_case "$nm" "${KEYED[@]}" SHIM_VERIFY=exec OLD_ROOT="$root" STORE_VERIFIED="$root/store-verified" "$@"
  if [ "$want" = ok ]; then [ "$RC" = 0 ] && has_store store-verified ok && has_store store-empty ok && grep -qxF '::notice title=git-data-cutover store::verdict=clear' "$OUT"
  else [ "$RC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=store-verified verdict=$want" "$OUT" && ! grep -q 'probe=store-empty' "$OUT" && no_fence_probe; fi
}
_r="$(_vxroot ok)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/store-verified"; _VX_OK="$_r"
case_vx_ok() { case_vx "$_VX_OK" ok; }
if case_vx_ok; then pass "VX-ok: a marker whose first line is the mounted filesystem's UUID, no freeze sentinel, an empty repositories dir on the root -> exit 0"
else fail "VX-ok: a bound marker did not clear" "$(ctx)"; fi
_r="$(_vxroot nomk)"; assert_fixture_dir "$_r"
if case_vx "$_r" "store_unverified reason=marker_absent"; then pass "VX-nomk: no marker -> reason=marker_absent"
else fail "VX-nomk: a missing marker was not marker_absent" "$(ctx)"; fi
_r="$(_vxroot emptymk)"; assert_fixture_dir "$_r"; : > "$_r/store-verified"; _VX_EMPTYMK="$_r"
case_vx_emptymk() { case_vx "$_VX_EMPTYMK" "store_unverified reason=marker_absent"; }
if case_vx_emptymk; then pass "VX-emptymk: an empty marker -> reason=marker_absent"
else fail "VX-emptymk: an empty marker was not marker_absent" "$(ctx)"; fi
# A NON-empty directory: an empty one can report size 0 and would not tell [ -f ] from [ -s ].
_r="$(_vxroot dirmk)"; assert_fixture_dir "$_r"; mkdir -p "$_r/store-verified" && printf '%s\n' "$FIX_UUID" > "$_r/store-verified/inner"; _VX_DIRMK="$_r"
case_vx_dirmk() { case_vx "$_VX_DIRMK" "store_unverified reason=marker_absent"; }
if case_vx_dirmk; then pass "VX-dirmk: a non-empty directory at the marker path -> reason=marker_absent"
else fail "VX-dirmk: a directory at the marker path was not marker_absent" "$(ctx)"; fi
_r="$(_vxroot symlinkok)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/marker-target" && ln -s "$_r/marker-target" "$_r/store-verified"
if case_vx "$_r" ok; then pass "VX-symlinkok (must-PASS): a marker that is a symlink to a bound file clears (the wrappers follow it too)"
else fail "VX-symlinkok: a symlinked bound marker was refused (stricter than the wrappers)" "$(ctx)"; fi
_r="$(_vxroot mismatch)"; assert_fixture_dir "$_r"; printf '%s\n' 0b3e9f71-5c2d-4a8e-8f16-7d4c2a9e1b05 > "$_r/store-verified"; _VX_MISMATCH="$_r"
case_vx_mismatch() { case_vx "$_VX_MISMATCH" "store_unverified reason=marker_mismatch"; }
if case_vx_mismatch; then pass "VX-mismatch: a marker naming another filesystem -> reason=marker_mismatch"
else fail "VX-mismatch: an unbound marker was accepted" "$(ctx)"; fi
_r="$(_vxroot crlf)"; assert_fixture_dir "$_r"; printf '%s\r\n' "$FIX_UUID" > "$_r/store-verified"
if case_vx "$_r" "store_unverified reason=marker_mismatch"; then pass "VX-crlf: a marker '<uuid>\\r' -> reason=marker_mismatch (head -n 1 keeps the \\r, as in the wrappers)"
else fail "VX-crlf: a CRLF marker was accepted" "$(ctx)"; fi
_r="$(_vxroot twoline)"; assert_fixture_dir "$_r"; printf '%s\nsecond\n' "$FIX_UUID" > "$_r/store-verified"
if case_vx "$_r" ok; then pass "VX-2line (must-PASS): a bound first line followed by a second line clears (the wrappers read head -n 1)"
else fail "VX-2line: a bound first line with a trailing line was refused" "$(ctx)"; fi
# Empty equals empty: a filesystem with no UUID and a marker whose first line is empty.
_r="$(_vxroot nouuid)"; assert_fixture_dir "$_r"; printf '\n' > "$_r/store-verified"; _VX_NOUUID="$_r"
case_vx_nouuid() { case_vx "$_VX_NOUUID" "store_unverified reason=no_fs_uuid" SHIM_FINDMNT_UUID=empty; }
if case_vx_nouuid; then pass "VX-nouuid: no filesystem UUID and a marker with an empty first line -> reason=no_fs_uuid, never ok"
else fail "VX-nouuid: an empty UUID matched an empty marker line" "$(ctx)"; fi
_r="$(_vxroot uuidfail)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/store-verified"
if case_vx "$_r" "probe_failed rc=5" SHIM_FINDMNT_UUID=fail; then pass "VX-uuidfail: findmnt unable to read the UUID -> probe_failed rc=5"
else fail "VX-uuidfail: a failed UUID read was not probe_failed rc=5" "$(ctx)"; fi
_r="$(_vxroot overmount)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/store-verified"; _VX_OVERMOUNT="$_r"
case_vx_overmount() { case_vx "$_VX_OVERMOUNT" "probe_failed rc=6" SHIM_FINDMNT_S=$'/dev/mapper/git-data\n/dev/sdb'; }
if case_vx_overmount; then pass "VX-overmount: a second mount stacked on the store root (two SOURCE lines) -> probe_failed rc=6"
else fail "VX-overmount: a stacked mount was accepted" "$(ctx)"; fi
_r="$(_vxroot frozen)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/store-verified" && : > "$_r/.cutover-freeze"; _VX_FROZEN="$_r"
case_vx_frozen() { case_vx "$_VX_FROZEN" cutover_frozen; }
if case_vx_frozen; then pass "VX-frozen: a .cutover-freeze sentinel under the store root -> cutover_frozen"
else fail "VX-frozen: a frozen store was accepted" "$(ctx)"; fi
# Frozen AND unverified: the freeze is read first, so the operator gets the frozen row.
_r="$(_vxroot frozennomk)"; assert_fixture_dir "$_r"; : > "$_r/.cutover-freeze"; _VX_FROZEN_NOMK="$_r"
case_vx_frozen_nomk() { case_vx "$_VX_FROZEN_NOMK" cutover_frozen; }
if case_vx_frozen_nomk; then pass "VX-frozen-nomk: frozen and missing its marker -> cutover_frozen (the freeze is read before the marker)"
else fail "VX-frozen-nomk: a frozen store with no marker did not read cutover_frozen" "$(ctx)"; fi
_r="$(_vxroot frozendangling)"; assert_fixture_dir "$_r"; printf '%s\n' "$FIX_UUID" > "$_r/store-verified" && ln -s "$_r/nowhere" "$_r/.cutover-freeze"
if case_vx "$_r" ok; then pass "VX-frozen-dangling (must-PASS): a dangling .cutover-freeze symlink clears (the wrappers test -e too)"
else fail "VX-frozen-dangling: a dangling sentinel symlink was refused (stricter than the wrappers)" "$(ctx)"; fi
# MM — mutating() still catches mountpoint(1) in every command position, and only findmnt's option
# form is exempt.
for spec in "ok|ssh x 10.0.1.20 mountpoint -q /mnt/git-data" "ok|ssh x 10.0.1.20 /usr/bin/mountpoint -q /mnt/git-data" \
            "ok|ssh x 10.0.1.20 true; mountpoint -q /x" "ok|ssh x 10.0.1.20 a && mountpoint /x" "ok|ssh x 10.0.1.20 v=\$(mountpoint -q /x)" \
            "no|ssh x 10.0.1.20 findmnt -n -o SOURCE --mountpoint /mnt/git-data"; do
  IFS='|' read -r _want _line <<< "$spec"
  printf '%s\n' "$_line" > "$T/mm.tl"
  _got=no; TLF="$T/mm.tl" mutating && _got=ok
  if [ "$_got" = "$_want" ]; then pass "MM ($_want): mutating() on [$_line]"
  else fail "MM: mutating() read [$_line] as $_got, expected $_want"; fi
done

# ── FENCE PROBE (#8101) — a push would run a root-owned pre-receive of the planted shape ──
# In every negative row the fence probe is the ONLY refusal: the four store probes read ok first.
# case_fence <mode> <expected-verdict> — SHIM_FENCE=<mode>, exit 5, the exact STORE line.
case_fence() {
  run_case "f-$1" "${KEYED[@]}" SHIM_FENCE="$1" GITHUB_STEP_SUMMARY="$T/f-$1.summary"
  [ "$RC" = 5 ] && has_store store-mounted ok && has_store store-on-mapper ok && has_store store-verified ok && has_store store-empty ok \
    && grep -qxF "[git-data-cutover] STORE probe=fence-shape verdict=$2" "$OUT" \
    && ! grep -q 'verdict=clear' "$OUT"
}
for spec in "F2:r10:hooks_dir_absent" "F3:r11:hooks_dir_owner" "F4:r12:hook_absent" "F5:r13:hook_owner" \
            "F6:r14:hooks_path_mismatch" "F7:r15:hooks_wrong_source" "F7b:r17:hook_not_runnable_by_git" \
            "F7c:r18:transport_pin_mismatch" "F7d:r19:hooks_parent_writable"; do
  IFS=: read -r _id _m _r <<< "$spec"
  if case_fence "$_m" "fence_not_intact reason=$_r"; then pass "$_id ($_m): remote exit ${_m#r} -> fence_not_intact reason=$_r, exit 5, after all four store probes read ok"
  else fail "$_id ($_m): expected fence_not_intact reason=$_r" "$(ctx)"; fi
done
# The ::error annotation and the step summary are what the runbook tells the operator to read.
if grep -qxF '::error title=git-data-cutover store::probe=fence-shape verdict=fence_not_intact reason=hooks_path_mismatch' "$T/f-r14.out" \
   && grep -qxF -- '- STORE probe=fence-shape verdict=fence_not_intact reason=hooks_path_mismatch' "$T/f-r14.summary"; then
  pass "F6: the reason word reaches the ::error annotation and the step summary"
else fail "F6: the reason word did not reach the annotation or the step summary" "$(grep -E '^::' "$T/f-r14.out" | tr '\n' '|' | sed 's/::/: :/g')"; fi
for spec in "F8:r5:5" "F8b:r16:16" "F9:r255:255"; do
  IFS=: read -r _id _m _r <<< "$spec"
  if case_fence "$_m" "probe_failed rc=$_r" && ! grep -q 'fence_not_intact' "$OUT"; then
    pass "$_id ($_m): remote exit $_r is probe_failed rc=$_r — an instrument or transport failure is never a store-state word"
  else fail "$_id ($_m): expected probe_failed rc=$_r" "$(ctx)"; fi
done
if case_fence line2 "probe_failed rc=96" && ! grep -q 'CANARY-FENCE-LINE-2' "$OUT"; then
  pass "F10: an answer with an injected second line is probe_failed rc=96 and the second line is never printed"
else fail "F10: a multi-line fence answer was accepted or printed" "$(ctx)"; fi
# The trailing `echo ok` is the proof the command reached its end: nothing else is accepted.
for _m in empty notok; do
  if case_fence "$_m" "probe_failed rc=96"; then pass "F10 ($_m): an exit-0 answer that is not exactly 'ok' is probe_failed rc=96"
  else fail "F10 ($_m): a non-ok exit-0 answer was accepted" "$(ctx)"; fi
done
# The fence command EXECUTED against a synthesized tree (SHIM_FENCE=exec). The CI user cannot be
# root:git, so these trees stop at 10, 12 or 11 on the real stat.
_ftree() { # <name> — a fresh fixture root under $T with an empty repositories dir
  assert_fixture_dir "$T/fence-$1"
  rm -rf "$T/fence-$1"; mkdir -p "$T/fence-$1/repositories" || { printf 'FAIL SETUP: mkdir fence tree\n' >&2; exit 1; }
  printf '%s' "$T/fence-$1"
}
case_fence_exec() { # <tree> <reason>
  run_case "fx-$(basename "$1")" "${KEYED[@]}" SHIM_FENCE=exec OLD_ROOT="$1"
  [ "$RC" = 5 ] && has_store store-empty ok && grep -qxF "[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=$2" "$OUT"
}
_fr="$(_ftree nohooks)"; assert_fixture_dir "$_fr"
if case_fence_exec "$_fr" hooks_dir_absent; then pass "F11: no hooks dir on the store -> reason=hooks_dir_absent"
else fail "F11: a missing hooks dir was not hooks_dir_absent" "$(ctx)"; fi
_fr="$(_ftree nohook)"; assert_fixture_dir "$_fr"; mkdir -p "$_fr/hooks"
if case_fence_exec "$_fr" hook_absent; then pass "F12: a hooks dir with no pre-receive -> reason=hook_absent"
else fail "F12: a missing pre-receive was not hook_absent" "$(ctx)"; fi
_fr="$(_ftree noexec)"; assert_fixture_dir "$_fr"; mkdir -p "$_fr/hooks" && printf '#!/bin/sh\nexit 1\n' > "$_fr/hooks/pre-receive" && chmod 0644 "$_fr/hooks/pre-receive"
_F12B_TREE="$_fr"
case_fence_noexec() { case_fence_exec "$_F12B_TREE" hook_absent; }
if case_fence_noexec; then pass "F12b: a regular but NON-executable (0644) pre-receive -> reason=hook_absent (git would never run it)"
else fail "F12b: a non-executable pre-receive was not hook_absent" "$(ctx)"; fi
_fr="$(_ftree hooklink)"; assert_fixture_dir "$_fr"; mkdir -p "$_fr/hooks" && printf '#!/bin/sh\nexit 1\n' > "$_fr/hook-target" && chmod 0755 "$_fr/hook-target" && ln -s "$_fr/hook-target" "$_fr/hooks/pre-receive"
if case_fence_exec "$_fr" hook_absent; then pass "F12c: a pre-receive that is a symlink to an executable -> reason=hook_absent"
else fail "F12c: a symlinked pre-receive was accepted" "$(ctx)"; fi
_fr="$(_ftree symlink)"; assert_fixture_dir "$_fr"; mkdir -p "$T/fence-symlink-target" && ln -s "$T/fence-symlink-target" "$_fr/hooks"
if case_fence_exec "$_fr" hooks_dir_absent; then pass "F13: a hooks path that is a symlink to a real dir -> reason=hooks_dir_absent"
else fail "F13: a symlinked hooks dir was accepted" "$(ctx)"; fi
_fr="$(_ftree owner)"; assert_fixture_dir "$_fr"; mkdir -p "$_fr/hooks" && printf '#!/bin/sh\nexit 1\n' > "$_fr/hooks/pre-receive" && chmod 0755 "$_fr/hooks/pre-receive"
if case_fence_exec "$_fr" hooks_dir_owner; then pass "F14: hooks dir + executable pre-receive owned by the CI user, not root:git 750 -> reason=hooks_dir_owner"
else fail "F14: a non-root-owned hooks dir was accepted" "$(ctx)"; fi
# The branches past 11, EXECUTED: a planted-shape tree whose ownership, git's config, git's
# permission check and the installed transport wrapper are answered by the stat/git/runuser
# shims. The wrapper is the REAL git-data-transport-wrapper.sh with its hooks default rewritten
# to this tree, so the pin the probe looks for is the one the wrapper actually carries.
_ffull() { # <name> [wrapper-sed-program] — a fence tree that clears every check
  local r
  r="$(_ftree "$1")"; assert_fixture_dir "$r"
  mkdir -p "$r/hooks" && printf '#!/bin/sh\nexit 1\n' > "$r/hooks/pre-receive" && chmod 0755 "$r/hooks/pre-receive" \
    || { printf 'FAIL SETUP: fence tree %s\n' "$1" >&2; exit 1; }
  sed -e "s#GIT_DATA_HOOKS_DIR:-/mnt/git-data/hooks}#GIT_DATA_HOOKS_DIR:-$r/hooks}#" ${2:+-e "$2"} "$DIR/git-data-transport-wrapper.sh" > "$r/wrapper" \
    || { printf 'FAIL SETUP: fence wrapper %s\n' "$1" >&2; exit 1; }
  printf '%s' "$r"
}
case_fence_full() { # <tree> <expected-verdict> [VAR=value ...] — overrides go last, so they win
  local tree="$1" want="$2" nm; shift 2
  nm="ff-$(basename "$tree")-$(printf '%s' "$*" | tr -c 'A-Za-z0-9_.=-' _)"
  run_case "$nm" "${KEYED[@]}" SHIM_FENCE=exec OLD_ROOT="$tree" TRANSPORT_WRAPPER="$tree/wrapper" \
    SHIM_STAT_H='root:git 750' SHIM_STAT_P='root:root 755' SHIM_STAT_PARENT='root 755' SHIM_GIT_HP="$tree/hooks" "$@"
  if [ "$want" = ok ]; then [ "$RC" = 0 ] && has_store fence-shape ok && grep -qxF '::notice title=git-data-cutover store::verdict=clear' "$OUT"
  else [ "$RC" = 5 ] && has_store store-empty ok && grep -qxF "[git-data-cutover] STORE probe=fence-shape verdict=$want" "$OUT"; fi
}
_FFULL="$(_ffull full)"; assert_fixture_dir "$_FFULL"
case_fence_full_ok() { case_fence_full "$_FFULL" ok; }
if case_fence_full_ok; then pass "FX0: the planted shape, a git-runnable hook, the system hooksPath and the real wrapper's pin all agree -> fence-shape ok, exit 0"
else fail "FX0: a fully intact fence did not clear" "$(ctx)"; fi
for spec in "FX13|fence_not_intact reason=hook_owner|SHIM_STAT_P=root:git 755" \
            "FX16s|probe_failed rc=16|SHIM_STAT_FAIL=1" \
            "FX19|fence_not_intact reason=hooks_parent_writable|SHIM_STAT_PARENT=root 775" \
            "FX19b|fence_not_intact reason=hooks_parent_writable|SHIM_STAT_PARENT=git 755" \
            "FX17|fence_not_intact reason=hook_not_runnable_by_git|SHIM_RUNUSER_RC=1" \
            "FX16r|probe_failed rc=16|SHIM_RUNUSER_BROKEN=1" \
            "FX16g|probe_failed rc=16|SHIM_GIT_RC=2" \
            "FX14u|fence_not_intact reason=hooks_path_mismatch|SHIM_GIT_RC=1" \
            "FX14v|fence_not_intact reason=hooks_path_mismatch|SHIM_GIT_HP=/elsewhere/hooks" \
            "FX15h|fence_not_intact reason=hooks_wrong_source|SHIM_FINDMNT_TH=/dev/nvme1n1" \
            "FX15p|fence_not_intact reason=hooks_wrong_source|SHIM_FINDMNT_TP=/dev/nvme1n1" \
            "FX5|probe_failed rc=5|SHIM_FINDMNT_TH=fail"; do
  IFS='|' read -r _id _want _kv <<< "$spec"
  if case_fence_full "$_FFULL" "$_want" "$_kv"; then pass "$_id ($_kv): the executed fence command -> $_want"
  else fail "$_id ($_kv): expected $_want" "$(ctx)"; fi
done
_fr="$(_ffull nopin '/^exec git -c "core.hooksPath=/d')"; assert_fixture_dir "$_fr"
_FX18_TREE="$_fr"
case_fence_nopin() { case_fence_full "$_FX18_TREE" "fence_not_intact reason=transport_pin_mismatch"; }
if case_fence_nopin; then pass "FX18: the installed wrapper without its command-line hooksPath pin -> reason=transport_pin_mismatch"
else fail "FX18: a wrapper that no longer pins the fence was accepted" "$(ctx)"; fi
_fr="$(_ffull otherpin 's#GIT_DATA_HOOKS_DIR:-/[^}]*}#GIT_DATA_HOOKS_DIR:-/other/hooks}#')"; assert_fixture_dir "$_fr"
if case_fence_full "$_fr" "fence_not_intact reason=transport_pin_mismatch"; then pass "FX18b: the installed wrapper pinning a different hooks dir -> reason=transport_pin_mismatch"
else fail "FX18b: a wrapper pinning another hooks dir was accepted" "$(ctx)"; fi
# F15 — an earlier refusal stops the proof before the fence probe (green on the pre-probe script too).
run_case f15 "${KEYED[@]}" SHIM_FINDMNT=rc1
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=1' "$OUT" && ! grep -q 'probe=fence-shape' "$OUT" \
   && ! grep -qE '^ssh .* 10\.0\.1\.20 h=/' "$TLF"; then
  pass "F15: an unmounted store stops the proof before the fence probe is dialed"
else fail "F15: the fence probe ran after a mount refusal" "$(ctx)"; fi
# MAP-ALT (must-PASS, non-canonical) — the comparison keys on the CONFIGURED mapper, and every later
# probe expects the source the mount probe accepted, never a fixed device.
case_map_alt() {
  run_case mapalt "${KEYED[@]}" LUKS_MAPPER=/dev/mapper/gd-alt SHIM_FINDMNT=mapperalt
  [ "$RC" = 0 ] && has_store store-on-mapper ok && has_store fence-shape ok \
    && grep -qE '^ssh .* 10\.0\.1\.20 r=/mnt/git-data; src=/dev/mapper/gd-alt; ' "$TLF" \
    && grep -qE '^ssh .* 10\.0\.1\.20 h=/mnt/git-data/hooks; p="\$h/pre-receive"; src=/dev/mapper/gd-alt; ' "$TLF"
}
if case_map_alt; then pass "MAP-ALT (must-PASS): LUKS_MAPPER=/dev/mapper/gd-alt served by gd-alt clears; store-verified and the fence are probed against /dev/mapper/gd-alt"
else fail "MAP-ALT: a consistent non-default mapper was refused, or a probe did not carry the accepted source" "$(ctx)"; fi
# F16 — the probe's parameters (the #8211 reuse on FRESH_ROOT). The script ends in an
# unconditional `main "$@"`, so the functions are EXTRACTED (header line through the closing brace)
# and called in a child bash with every global they read set. The definition must be unique, or
# the extraction and bash would test different copies.
_fence_lib() { # <script>
  local fn body n
  n="$(sed -E 's/^[[:space:]]*#.*$//' "$1" | grep -c 'refuse_if_fence_not_intact' || true)"
  [ "$n" = 2 ] || { F16_DETAIL="refuse_if_fence_not_intact appears $n times in code, expected 2 (definition + main call)"; return 1; }
  : > "$T/fence-lib.sh" || { printf 'FAIL SETUP: cannot write fence-lib\n' >&2; exit 1; }
  for fn in gd_capture _store_emit _store_refuse refuse_if_fence_not_intact; do
    body="$(awk -v n="$fn" 'index($0, n "() {") == 1 { m = 1 } m { print } m && /^\}/ { exit }' "$1")"
    [ -n "$body" ] || { F16_DETAIL="no $fn extracted"; return 1; }
    printf '%s\n' "$body" >> "$T/fence-lib.sh"
  done
}
_fence_call() { # [args...] — the extracted probe in a child bash; sets RC OUT TLF
  TLF="$T/f16.tl"; OUT="$T/f16.out"; : > "$TLF"
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" bash -c '
    set -euo pipefail
    log() { printf "[git-data-cutover] %s\n" "$*"; }; step() { :; }; _access_stderr() { :; }
    CAPTURE_TMP=""; GD_CAPTURED=""; GIT_DATA_HOST=10.0.1.20; GIT_DATA_SSH="ssh -F /fixture/gd-ssh-config"
    OLD_ROOT=/mnt/git-data; STORE_SOURCE=/dev/mapper/git-data; TRANSPORT_WRAPPER=/usr/local/bin/git-data-transport-wrapper.sh
    source "$1"; shift
    refuse_if_fence_not_intact "$@"
  ' _ "$T/fence-lib.sh" "$@" > "$OUT" 2>&1
  RC=$?
  cat "$OUT" >> "$T/f16.all.out"   # every call's verdicts feed the RB observed set
}
case_fence_params() { # <script>
  _fence_lib "$1" || return 1
  _fence_call /x/fresh /dev/mapper/git-data
  F16_DETAIL="rc=$RC tl=[$(grep -E '^ssh ' "$TLF" | cut -c1-300)]"
  [ "$RC" = 0 ] && [ "$(grep -cE '^ssh ' "$TLF")" = 1 ] \
    && grep -qE '^ssh .* 10\.0\.1\.20 h=/x/fresh/hooks; p="\$h/pre-receive"; src=/dev/mapper/git-data; sp=/mnt/git-data/hooks; w=/usr/local/bin/git-data-transport-wrapper\.sh; ' "$TLF" \
    && grep -qF 'GIT_DATA_HOOKS_DIR:-/mnt/git-data/hooks' "$TLF"
}
if case_fence_params "$SCRIPT"; then pass "F16: called with an explicit root and source, the probe checks /x/fresh/hooks against /dev/mapper/git-data while the hooksPath and the wrapper pin stay the SERVING path"
else fail "F16: the probe's parameters did not reach its remote command" "$F16_DETAIL"; fi
# F16b — a PASSED empty or unsafe argument is refused before anything is printed or dialed; an
# empty FRESH_ROOT must never quietly probe the serving store.
case_fence_arg() { # <reason> <args...>
  local want="$1"; shift
  _fence_call "$@"
  [ "$RC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=fence-shape verdict=probe_failed reason=$want" "$OUT" && ! grep -qE '^ssh ' "$TLF"
}
if _fence_lib "$SCRIPT"; then
  for spec in "arg_root||" "arg_root|/x;touch /tmp/p|/dev/sdb" "arg_source|/x/fresh|" "arg_source|/x/fresh|sdb" \
              "arg_serving|/x/fresh|/dev/sdb|rel/hooks"; do
    IFS='|' read -r _want _a1 _a2 _a3 <<< "$spec"
    if [ -n "$_a3" ]; then case_fence_arg "$_want" "$_a1" "$_a2" "$_a3"; else case_fence_arg "$_want" "$_a1" "$_a2"; fi
    if [ "$RC" = 5 ] && grep -qxF "[git-data-cutover] STORE probe=fence-shape verdict=probe_failed reason=$_want" "$OUT" && ! grep -qE '^ssh ' "$TLF"; then
      pass "F16b ($_want: [$_a1] [$_a2] [$_a3]): refused as probe_failed reason=$_want, nothing dialed"
    else fail "F16b ($_want: [$_a1] [$_a2] [$_a3]): not refused before dialing" "rc=$RC $(tr '\n' '|' < "$OUT" | cut -c1-200)"; fi
  done
  if case_fence_arg arg_root $'/x\n::error::forged' /dev/sdb && ! grep -q '::error::forged' "$OUT"; then
    pass "F16b (newline root): a root carrying a newline and a workflow command is refused and never printed"
  else fail "F16b (newline root): a newline-bearing root was printed or dialed" "rc=$RC $(tr '\n' '|' < "$OUT" | sed 's/::/: :/g' | cut -c1-200)"; fi
else fail "F16b: the probe could not be extracted" "$F16_DETAIL"; fi
# P1 — the probe's ownership literals equal git-data-bootstrap.sh's _own rows. Occurrences are
# COUNTED (not lines: the literal and a looser alternative can share one line), both sides must
# match exactly once, and two empty extractions never compare equal.
case_fence_parity() { # <script>
  local boot="$DIR/git-data-bootstrap.sh" code u bd bh sd sh
  code="$(sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]+# .*$//' "$1")"
  u="$(sed -nE 's/^GIT_USER="([a-z]+)"$/\1/p' "$boot")"
  bd="$(sed -nE 's/^\$HOOKS_DIR (root:\$GIT_USER [0-7]+) .*$/\1/p' "$boot")"; bd="${bd//\$GIT_USER/$u}"
  bh="$(sed -nE 's/^\$PRE_RECEIVE (root:root [0-7]+) .*$/\1/p' "$boot")"
  sd="$(sed -nE "s/.*\[ \"\\\$oh\" = \"([^\"]+)\" \].*/\1/p" <<< "$code")"
  sh="$(sed -nE "s/.*\[ \"\\\$op\" = \"([^\"]+)\" \].*/\1/p" <<< "$code")"
  PARITY_DETAIL="user=[$u] boot=[$bd|$bh] script=[$sd|$sh]"
  [ "$(grep -cE '^GIT_USER="[a-z]+"$' "$boot")" = 1 ] && [ "$(grep -cE '^\$HOOKS_DIR root:\$GIT_USER ' "$boot")" = 1 ] \
    && [ "$(grep -cE '^\$PRE_RECEIVE ' "$boot")" = 1 ] \
    && [ "$(grep -oF '"$oh" = "' <<< "$code" | wc -l)" = 1 ] && [ "$(grep -oF '"$op" = "' <<< "$code" | wc -l)" = 1 ] \
    && [ -n "$bd" ] && [ -n "$bh" ] && [ "$sd" = "$bd" ] && [ "$sh" = "$bh" ]
}
if case_fence_parity "$SCRIPT"; then pass "P1: the fence probe's ownership literals equal git-data-bootstrap.sh's _own rows ($PARITY_DETAIL)"
else fail "P1: the fence probe's ownership literals drifted from the bootstrap" "$PARITY_DETAIL"; fi
# P2 — the two wrapper lines the probe looks for are the two lines git-data-transport-wrapper.sh
# carries (its hooks default and its command-line pin), each exactly once on both sides.
case_pin_parity() { # <script> <wrapper>
  local code
  code="$(sed -E 's/^[[:space:]]*#.*$//' "$1")"
  [ "$(grep -cxF '  pin_hd="HOOKS_DIR=\"\${GIT_DATA_HOOKS_DIR:-$serving}\""' <<< "$code")" = 1 ] \
    && [ "$(grep -cxF "  pin_ex='exec git -c \"core.hooksPath=\${HOOKS_DIR}\" \"\${verb#git-}\" \"\$repo_real\"'" <<< "$code")" = 1 ] \
    && [ "$(grep -cxF 'OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"                 # the store root every wrapper hardcodes (LUKS-served since ADR-239)' "$1")" = 1 ] \
    && [ "$(grep -cxF 'HOOKS_DIR="${GIT_DATA_HOOKS_DIR:-/mnt/git-data/hooks}"' "$2")" = 1 ] \
    && [ "$(grep -cxF 'exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"' "$2")" = 1 ]
}
if case_pin_parity "$SCRIPT" "$DIR/git-data-transport-wrapper.sh"; then pass "P2: the wrapper lines the probe requires are exactly the hooks default and the command-line pin git-data-transport-wrapper.sh carries"
else fail "P2: the probe's expected wrapper pin drifted from git-data-transport-wrapper.sh" "$(grep -nE '^HOOKS_DIR=|^exec git' "$DIR/git-data-transport-wrapper.sh" | tr '\n' '|')"; fi

# (An unsafe TRANSPORT_WRAPPER through the whole script is refused by the config check: CFG wrapper-rel.)
# P3 — the defaults the proof compares against equal every wrapper's. The definer populations are
# DERIVED over git-data-*.sh (never listed by hand), excluding the suites and the cutover script, and
# each is paired with set identity, so a new definer with its own default reds. A definer may assign
# each name exactly ONCE in any form (plain, indented, readonly, export, declare): a later
# reassignment would override the default this row compares. The freeze path must be rooted in the
# SAME file's own root variable. The wrappers read GIT_DATA_STORE_DEVICE / GIT_DATA_STORE_VERIFIED /
# GIT_DATA_CUTOVER_FREEZE / GIT_DATA_REPO_ROOT overrides; the proof ignores them, because a
# host-side override is invisible to it.
_p3_assigns() { # <file> <name> — how many times the file assigns <name>, in any declaration form
  grep -cE "^[[:space:]]*((readonly|export|local|declare([[:space:]]+-[a-zA-Z]+)?)[[:space:]]+)?$2=" "$1" || true
}
case_parity() { # <script> <dir>
  local script="$1" dir="$2" f b v n rootvar rootval bad="" mapper mk root fz repos dev_set=() mk_set=() fz_set=() root_set=() repo_set=()
  mapper="$(sed -nE 's/^LUKS_MAPPER="\$\{LUKS_MAPPER:-([^}]*)\}".*$/\1/p' "$script")"
  mk="$(sed -nE 's/^STORE_VERIFIED="\$\{STORE_VERIFIED:-([^}]*)\}".*$/\1/p' "$script")"
  root="$(sed -nE 's/^OLD_ROOT="\$\{OLD_ROOT:-([^}]*)\}".*$/\1/p' "$script")"
  repos="$root/$(sed -nE 's/^REPO_SUBDIR="\$\{REPO_SUBDIR:-([^}]*)\}".*$/\1/p' "$script")"
  fz="$(sed -nE "s/^    'fz=\"\\\$r(\/[^\"]+)\"'\$/\1/p" "$script")"
  for f in "$dir"/git-data-*.sh; do
    case "$f" in *.test.sh|*/git-data-cutover.sh) continue ;; esac
    b="$(basename "$f")"
    for v in STORE_DEVICE STORE_VERIFIED cutover_freeze MOUNT_ROOT GIT_DATA_ROOT REPO_ROOT; do
      n="$(_p3_assigns "$f" "$v")"
      [ "$n" -le 1 ] || bad="$bad $b:$v-assigned-${n}x"
    done
    rootvar=""; rootval=""
    if [ "$(_p3_assigns "$f" MOUNT_ROOT)$(_p3_assigns "$f" GIT_DATA_ROOT)" != 00 ]; then
      root_set+=("$b")
      rootvar="$(sed -nE 's/^(MOUNT_ROOT|GIT_DATA_ROOT)=.*$/\1/p' "$f" | head -n 1)"
      rootval="$(sed -nE 's/^(MOUNT_ROOT|GIT_DATA_ROOT)="(\$\{[A-Z_]+:-)?(\/[^}"]*)\}?"$/\3/p' "$f")"
      { [ -n "$rootval" ] && [ "$rootval" = "$root" ]; } || bad="$bad $b:root=[$rootval]"
    fi
    if [ "$(_p3_assigns "$f" STORE_DEVICE)" != 0 ]; then
      dev_set+=("$b")
      v="$(sed -nE 's/^STORE_DEVICE="\$\{GIT_DATA_STORE_DEVICE:-([^}]*)\}"$/\1/p' "$f")"
      { [ -n "$v" ] && [ "$v" = "$mapper" ]; } || bad="$bad $b:STORE_DEVICE=[$v]"
    fi
    if [ "$(_p3_assigns "$f" STORE_VERIFIED)" != 0 ]; then
      mk_set+=("$b")
      v="$(sed -nE 's/^STORE_VERIFIED="\$\{GIT_DATA_STORE_VERIFIED:-([^}]*)\}"$/\1/p' "$f")"
      { [ -n "$v" ] && [ "$v" = "$mk" ]; } || bad="$bad $b:STORE_VERIFIED=[$v]"
    fi
    if [ "$(_p3_assigns "$f" cutover_freeze)" != 0 ]; then
      fz_set+=("$b")
      # Rooted in THIS file's own root variable, never in one it does not set.
      v=""; [ -z "$rootvar" ] || v="$(sed -nE "s/^cutover_freeze=\"\\\$\\{GIT_DATA_CUTOVER_FREEZE:-\\\$\\{${rootvar}\\}(\\/[^}]*)\\}\"\$/\\1/p" "$f")"
      { [ -n "$v" ] && [ "$v" = "$fz" ]; } || bad="$bad $b:cutover_freeze=[$v]"
    fi
    if [ "$(_p3_assigns "$f" REPO_ROOT)" != 0 ]; then
      repo_set+=("$b")
      v="$(sed -nE 's/^REPO_ROOT="\$\{GIT_DATA_REPO_ROOT:-([^}]*)\}"$/\1/p; s/^REPO_ROOT="\$(GIT_DATA_ROOT|MOUNT_ROOT)(\/[^" ]*)".*$/\1 \2/p' "$f")"
      case "$v" in "$rootvar "*) v="$rootval${v#"$rootvar "}" ;; esac
      { [ -n "$v" ] && [ "$v" = "$repos" ]; } || bad="$bad $b:REPO_ROOT=[$v]"
    fi
  done
  PARITY3_DETAIL="mapper=[$mapper] marker=[$mk] root=[$root] repos=[$repos] freeze=[$fz] device={${dev_set[*]}} marker={${mk_set[*]}} freeze={${fz_set[*]}} root={${root_set[*]}} repo={${repo_set[*]}} bad=[${bad# }]"
  local five="git-data-bootstrap.sh git-data-gc.sh git-data-provision.sh git-data-remove.sh git-data-transport-wrapper.sh"
  [ -n "$mapper" ] && [ -n "$mk" ] && [ -n "$root" ] && [ -n "$fz" ] && [ "$repos" != "$root/" ] && [ -z "$bad" ] \
    && [ "${dev_set[*]}" = "$five" ] && [ "${mk_set[*]}" = "$five" ] && [ "${repo_set[*]}" = "$five" ] \
    && [ "${fz_set[*]}" = "git-data-pre-receive.sh git-data-provision.sh git-data-remove.sh git-data-transport-wrapper.sh" ] \
    && [ "${root_set[*]}" = "git-data-bootstrap.sh git-data-gc.sh git-data-pre-receive.sh git-data-provision.sh git-data-remove.sh git-data-transport-wrapper.sh" ]
}
# P3 runs over a COPIED directory, so its mutants never touch a tracked definer.
assert_fixture_dir "$T/p3"; mkdir -p "$T/p3" || { printf 'FAIL SETUP: mkdir p3\n' >&2; exit 1; }
cp "$DIR"/git-data-*.sh "$T/p3/" || { printf 'FAIL SETUP: copy p3 definers\n' >&2; exit 1; }
if case_parity "$SCRIPT" "$T/p3"; then pass "P3: LUKS_MAPPER, STORE_VERIFIED, the freeze suffix, OLD_ROOT and OLD_ROOT/REPO_SUBDIR equal every derived definer's single default (5/5/4/6/5, set identity) ($PARITY3_DETAIL)"
else fail "P3: the proof's defaults drifted from the wrappers'" "$PARITY3_DETAIL"; fi

# Doppler is never called by any case above (the shim logs every call).
if ! grep -lq '^doppler ' "$T"/*.tl 2>/dev/null; then pass "D-3: no case invoked doppler — the script reads no secret store"
else fail "D-3: the script called doppler" "$(grep -l '^doppler ' "$T"/*.tl | head -3 | tr '\n' ' ')"; fi

# ── GUARD 5 — captured values ─────────────────────────────────────────────────────────
case_line2() { # injected second line: refused AND the canary never printed
  run_case g5line2 "${KEYED[@]}" SHIM_FINDMNT=line2
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=probe_failed rc=96' "$OUT" \
    && ! grep -q 'CANARY-SECOND-LINE' "$OUT" && no_count_probe
}
case_hang() {
  CASE_TIMEOUT=15 run_case g5hang "${KEYED[@]}" SHIM_FINDMNT=hang SHIM_TIMEOUT_S=2
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=probe_failed rc=124' "$OUT"
}
case_capture_census() { # <script>
  local code outside calls
  code="$(sed -E 's/^[[:space:]]*#.*$//' "$1")"
  # Lines outside access_gate/gd_capture/gd_exec/resolve_roster that expand an ssh
  # invocation. gd_exec (PR2) is the write twin of gd_capture — same bound, same pin, no
  # stdout acceptance — so it joins the allowlist.
  outside="$(printf '%s\n' "$code" | awk '
    /^(access_gate|gd_capture|gd_exec|resolve_roster)\(\) \{/ {skip=1; next}
    skip && /^\}/ {skip=0; next}
    !skip' | grep -nE '"\$\{(inv|gdinv)\[@\]\}"|\$\{?GIT_DATA_SSH|\$\{?WEB_HOST_SSH' || true)"
  calls="$(printf '%s\n' "$code" | grep -cE '^[[:space:]]+gd_capture ' || true)"
  CAPTURE_DETAIL="calls=$calls outside=[$(printf '%s' "$outside" | tr '\n' '|' | cut -c1-300)]"
  [ -z "$outside" ] && [ "$calls" -ge 1 ] && [ "$calls" = 5 ]
}
if case_line2; then pass "S8a/G5: a findmnt answer with an injected second line is probe_failed rc=96 and neither line is printed"
else fail "S8a/G5: a multi-line captured value was accepted or printed" "$(ctx)"; fi
if case_hang; then pass "S8b/G5: a hung host is cut by gd_capture's timeout -> probe_failed rc=124, exit 5"
else fail "S8b/G5: a hung host was not bounded" "$(ctx)"; fi
run_case g5big "${KEYED[@]}" SHIM_FINDMNT=big
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=probe_failed rc=96' "$OUT" && ! grep -q 'aaaaaaaaaa' "$OUT"; then
  pass "G5: a 5005-byte answer that would match once truncated is refused (cap 4096), never printed"
else fail "G5: an oversized answer was truncated into an accepted value, or printed" "$(ctx)"; fi
if case_capture_census "$SCRIPT"; then pass "G5 census: exactly five gd_capture call sites; no ssh invocation is expanded outside access_gate/gd_capture ($CAPTURE_DETAIL)"
else fail "G5 census: a raw capture or a stray invocation exists" "$CAPTURE_DETAIL"; fi

# ── GUARD 7 — real modes are refused before any remote call ───────────────────────────
case_refuse() { # <label> <VAR=value>
  run_case "g7$1" "${KEYED[@]}" "$2"
  [ "$RC" = 5 ] && [ ! -s "$TLF" ] \
    && grep -qE '^\[git-data-cutover\] REFUSE verdict=real_cutover_unreconciled vars=' "$OUT" \
    && [ "$(grep -E '^::' "$OUT")" = "::error title=git-data-cutover::verdict=real_cutover_unreconciled" ] \
    && grep -q '#8211' "$OUT"
}
for kv in DRY_RUN=0 ROLLBACK=1 CONFIRM_WIPE=1 DRY_RUN=true; do
  _lbl="$(printf '%s' "$kv" | tr '=A-Z' '-a-z')"
  if case_refuse "$_lbl" "$kv"; then pass "S9/G7 ($kv): exit 5 real_cutover_unreconciled naming #8211, and the timeline is EMPTY"
  else fail "S9/G7 ($kv): a real mode was not refused before any remote call" "$(ctx)"; fi
done
run_case g7empty "${KEYED[@]}" DRY_RUN= ROLLBACK= CONFIRM_WIPE=
if [ "$RC" = 0 ] && ! grep -q 'REFUSE' "$OUT"; then pass "G7 harness: empty DRY_RUN/ROLLBACK/CONFIRM_WIPE take the defaults and reach the proof"
else fail "G7 harness: empty values were refused" "$(ctx)"; fi
if [ "$(grep -c 'DRY_RUN\|ROLLBACK\|CONFIRM_WIPE' "$T/g7dry_run-0.out")" -ge 1 ] && ! grep -qE 'vars=.*(=|[0-9])' "$T/g7dry_run-0.out"; then
  pass "G7: the refusal names the variable, never its value"
else fail "G7: the refusal printed a value or no variable" "$(tr '\n' '|' < "$T/g7dry_run-0.out")"; fi

# ── BRIDGE — the "Decode CI SSH private key" export set ───────────────────────────────
# The committed web-1 pin's key line (comments skipped), and the shared writer both callers use.
WEB1_PIN="$(awk '/^[[:space:]]*(#|$)/ { next } { print }' "$DIR/web-1-ssh-host-key.pub" | tr -d '\r')"
WKH="$(dirname "$ACTION")/write-known-hosts.sh"
[ -n "$WEB1_PIN" ] && [ -f "$WKH" ] || { printf 'FAIL SETUP: web-1 pin file or %s missing\n' "$WKH" >&2; exit 1; }
python3 - "$ACTION" "$T/decode.sh" <<'PY' > "$T/g2.count"
import sys, yaml
act = yaml.safe_load(open(sys.argv[1]))
bodies = [s["run"] for s in (act.get("runs") or {}).get("steps") or []
          if str(s.get("name", "")).startswith("Decode CI SSH private key") and s.get("run")]
if len(bodies) == 1: open(sys.argv[2], "w").write(bodies[0])
print(len(bodies))
PY
if [ "$(cat "$T/g2.count")" != 1 ]; then
  fail "BR: extracted $(cat "$T/g2.count") 'Decode CI SSH private key' run bodies, expected exactly 1" "never a pass on zero"
else
  pass "BR: extracted exactly one 'Decode CI SSH private key' run body"
  mkdir -p "$T/g2bin" || { printf 'FAIL SETUP: mkdir g2bin\n' >&2; exit 1; }
  cat > "$T/g2bin/doppler" <<'SHIM'
#!/usr/bin/env bash
[ "$*" = "secrets get DEPLOY_SSH_PRIVATE_KEY --plain" ] || { echo "doppler-shim: unexpected argv: $*" >&2; exit 64; }
cat "$G2_KEY"
SHIM
  chmod +x "$T/g2bin/doppler"
  # _names <env-file> — NAMEs from both NAME=value and NAME<<DELIM forms, sorted, comma-joined.
  _names() {
    awk 'inh { if ($0 == delim) inh = 0; next }
         match($0, /^[A-Za-z_][A-Za-z0-9_]*<</) { print substr($0, 1, RLENGTH - 2); delim = substr($0, RLENGTH + 1); inh = 1; next }
         match($0, /^[A-Za-z_][A-Za-z0-9_]*=/) { print substr($0, 1, RLENGTH - 1) }' "$1" | LC_ALL=C sort -u | paste -sd, -
  }
  _g2_run() { # <label> <server-ip-input> <tmp-root>
    local label="$1" sip="$2" troot="$3"
    assert_fixture_dir "$troot"
    mkdir -p "$troot" || { printf 'FAIL SETUP: mkdir %s\n' "$troot" >&2; exit 1; }
    rm -f "$troot/k" "$troot/k.pub"
    ssh-keygen -q -t ed25519 -N '' -C "g2-$label" -f "$troot/k" || { printf 'FAIL SETUP: ssh-keygen\n' >&2; exit 1; }
    : > "$troot/github_env"
    rm -rf "$troot/rt"; mkdir -p "$troot/rt" || { printf 'FAIL SETUP: mkdir %s/rt\n' "$troot" >&2; exit 1; }
    env -i PATH="$T/g2bin:/usr/bin:/bin" TMPDIR="$troot" GITHUB_ENV="$troot/github_env" G2_KEY="$troot/k" \
      RUNNER_TEMP="$troot/rt" GITHUB_WORKSPACE="$ROOT" ACTION_PATH="$(dirname "$ACTION")" \
      DOPPLER_TOKEN=fixture SERVER_IP_INPUT="$sip" bash --noprofile --norc -eo pipefail "$T/decode.sh" > "$troot/stdout" 2>&1
    G2_RC=$?; G2_ENV="$troot/github_env"
  }
  # Two server-ip values and two temp roots: the export set must not depend on either.
  for variant in 10.0.1.10 10.0.1.99; do
    _g2_run "sip-$variant" "$variant" "$T/g2-$variant"
    _got="$(_names "$G2_ENV")"
    _kf="$(sed -n 's/^CI_SSH_KEYFILE=//p' "$G2_ENV")"
    _kh="$T/g2-$variant/rt/web-1.known_hosts"
    _want_inv="ssh -F /dev/null -i ${_kf} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${_kh} -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root"
    if [ "$G2_RC" = 0 ] && [ "$_got" = "CI_SSH_KEYFILE,WEB_HOST_SSH" ]; then
      pass "BR (server-ip $variant): server-ip branch exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH}"
    else fail "BR (server-ip $variant): export set is [$_got] (rc=$G2_RC), expected CI_SSH_KEYFILE,WEB_HOST_SSH" "$(tail -3 "$T/g2-$variant/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
    if [ -n "$_kf" ] && [ "$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")" = "$_want_inv" ] && cmp -s "$_kf" "$T/g2-$variant/k"; then
      pass "BR (server-ip $variant): WEB_HOST_SSH is byte-equal to the pinned invocation (plan D3) and the keyfile holds the key"
    else fail "BR (server-ip $variant): WEB_HOST_SSH value or keyfile content changed" "got=[$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")] want=[$_want_inv]"; fi
    # The runtime arm drives real OpenSSH with THIS invocation (key and known_hosts as placeholders),
    # so its host-key rows test exactly what the bridge exports.
    if [ -n "$_kf" ]; then
      sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV" | sed "s#${_kf}#@KEY@#; s#${_kh}#@KH@#" > "$T/bridge-inv.tmpl"
    fi
    if [ "$(cat "$_kh" 2>/dev/null)" = "web-1 $WEB1_PIN" ] && [ "$(stat -c %a "$_kh" 2>/dev/null)" = 444 ]; then
      pass "BR (server-ip $variant): \$RUNNER_TEMP/web-1.known_hosts is exactly 'web-1 <committed pin>', mode 444"
    else fail "BR (server-ip $variant): the web-1 known_hosts file differs" "[$(head -c 200 "$_kh" 2>/dev/null)]"; fi
  done
  _g2_run tf "" "$T/g2-tf"
  _got="$(_names "$G2_ENV")"
  if [ "$G2_RC" = 0 ] && [ "$_got" = "TF_VAR_ci_ssh_private_key" ]; then
    pass "BR: terraform branch exports exactly {TF_VAR_ci_ssh_private_key} (heredoc form parsed)"
  else fail "BR: terraform branch export set is [$_got] (rc=$G2_RC), expected TF_VAR_ci_ssh_private_key" "$(tail -3 "$T/g2-tf/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
fi

# ── MODE VERBS (PR2) — freeze / unfreeze / probe over the same shims ──────────────────
# run_mode <name> <mode> [VAR=value ...] — a full-mode run: access gate + config defaults
# clear, then the verb's own remotes under their SHIM_* arms.
run_mode() {
  local name="$1" mode="$2"; shift 2
  run_case "$name" "${KEYED[@]}" MODE="$mode" CUTOVER_LINEAGE="lin-test-1" "$@"
}
LIN="lin-test-1"

echo; echo "--- mode verbs (MODE=freeze|unfreeze|probe)"

# MZ-F1: freeze on a clean store — gc quiesced, timer stopped, sentinel written with
# provenance, purge runs; verdict=ok on all three probes.
run_mode mz-f1-ok freeze SHIM_GC_STATE=inactive SHIM_FREEZE=absent SHIM_PURGE=ok
if [ "$RC" = 0 ] && has_store freeze ok && has_store freeze-gc-stopped ok && has_store lock-purge ok \
   && grep -q 'systemctl stop git-data-gc.timer' "$TLF" && grep -q "printf 'writer=" "$TLF" && grep -q "$LIN" "$TLF"; then
  pass "MZ-F1: freeze on a clean store: gc stop -> sentinel (writer=lineage) -> purge, all ok"
else fail "MZ-F1: freeze happy path wrong" "$(ctx)"; fi

# MZ-F2: a RUNNING gc.service refuses before the timer stop — the window it must close.
# verdict=gc_active (a completed read returning a refused state is NOT probe_failed).
run_mode mz-f2-gcactive freeze SHIM_GC_STATE=active
if [ "$RC" = 5 ] && has_store freeze-gc-quiesce gc_active \
   && ! grep -q 'systemctl stop' "$TLF" && ! grep -q "printf 'writer=" "$TLF"; then
  pass "MZ-F2: gc.service active -> verdict=gc_active, before the timer stop and the sentinel"
else fail "MZ-F2: an active gc.service was not refused" "$(ctx)"; fi

# MZ-F3: a sentinel with THIS lineage is resume arm A — idempotent, no write.
run_mode mz-f3-ours freeze SHIM_GC_STATE=inactive SHIM_FREEZE=ours
if [ "$RC" = 0 ] && has_store freeze ok && grep -q 'resume arm A' "$OUT" \
   && ! grep -q "writer=$LIN" "$TLF"; then
  pass "MZ-F3: freeze on a same-lineage sentinel -> resume arm A, no write, exit 0"
else fail "MZ-F3: same-lineage freeze was not idempotent" "$(ctx)"; fi

# MZ-F4/MZ-F5: a sentinel another lineage wrote, or an unparseable one, refuses.
run_mode mz-f4-foreign freeze SHIM_GC_STATE=inactive SHIM_FREEZE=foreign
if [ "$RC" = 5 ] && has_store freeze frozen_foreign && ! grep -q "printf 'writer=" "$TLF"; then
  pass "MZ-F4: a foreign sentinel -> verdict=frozen_foreign, no write"
else fail "MZ-F4: a foreign sentinel was not refused" "$(ctx)"; fi
run_mode mz-f5-unattr freeze SHIM_GC_STATE=inactive SHIM_FREEZE=unattributed
if [ "$RC" = 5 ] && has_store freeze frozen_unattributed; then
  pass "MZ-F5: an unparseable sentinel -> verdict=frozen_unattributed"
else fail "MZ-F5: an unparseable sentinel was not refused" "$(ctx)"; fi

# MZ-F6: no CUTOVER_LINEAGE -> lineage_absent before any remote call.
run_case mz-f6-nolin "${KEYED[@]}" MODE=freeze
if [ "$RC" = 5 ] && grep -qF 'verdict=lineage_absent' "$OUT" && [ ! -s "$TLF" ]; then
  pass "MZ-F6: MODE=freeze without CUTOVER_LINEAGE -> lineage_absent, nothing dialed"
else fail "MZ-F6: a lineage-less freeze was not refused" "$(ctx)"; fi

# MZ-F7: a held legacy lock stops the purge — an in-flight provision past the sentinel.
run_mode mz-f7-lockheld freeze SHIM_GC_STATE=inactive SHIM_FREEZE=absent SHIM_PURGE=held
if [ "$RC" = 5 ] && has_store lock-purge lock_held; then
  pass "MZ-F7: a held lock mid-purge -> probe=lock-purge verdict=lock_held (sentinel still written)"
else fail "MZ-F7: a held legacy lock was not refused" "$(ctx)"; fi

# MZ-U1: unfreeze on our sentinel — cleared, gc.timer restarted.
run_mode mz-u1-ours unfreeze SHIM_FREEZE=ours
if [ "$RC" = 0 ] && has_store unfreeze ok && grep -q 'rm -f --' "$TLF" && grep -q 'systemctl start git-data-gc.timer' "$TLF"; then
  pass "MZ-U1: same-lineage unfreeze clears the sentinel and restarts gc.timer"
else fail "MZ-U1: same-lineage unfreeze failed" "$(ctx)"; fi

# MZ-U2: no sentinel -> nothing_to_unfreeze, timer still restarted (convergent).
run_mode mz-u2-absent unfreeze SHIM_FREEZE=absent
if [ "$RC" = 0 ] && grep -q 'nothing_to_unfreeze' "$OUT" && grep -q 'systemctl start git-data-gc.timer' "$TLF" && ! grep -q 'rm -f --' "$TLF"; then
  pass "MZ-U2: absent sentinel -> nothing_to_unfreeze (still restarts gc.timer, removes nothing)"
else fail "MZ-U2: absent-sentinel unfreeze wrong" "$(ctx)"; fi

# MZ-U3/U4: foreign/unattributed sentinels refuse — never cleared.
run_mode mz-u3-foreign unfreeze SHIM_FREEZE=foreign
if [ "$RC" = 5 ] && has_store unfreeze frozen_foreign && ! grep -q 'rm -f --' "$TLF"; then
  pass "MZ-U3: foreign sentinel -> unfreeze refuses frozen_foreign, sentinel untouched"
else fail "MZ-U3: foreign sentinel was cleared" "$(ctx)"; fi
run_mode mz-u4-unattr unfreeze SHIM_FREEZE=unattributed
if [ "$RC" = 5 ] && has_store unfreeze frozen_unattributed && ! grep -q 'rm -f --' "$TLF"; then
  pass "MZ-U4: unattributed sentinel -> unfreeze refuses frozen_unattributed, sentinel untouched"
else fail "MZ-U4: unattributed sentinel was cleared" "$(ctx)"; fi

# MZ-U5: FREEZE_HELD — the rm fails (hop dead); the paging verdict, not a summary.
run_mode mz-u5-held unfreeze SHIM_FREEZE=ours SHIM_UNFREEZE_RC=255
if [ "$RC" = 5 ] && grep -qF 'FREEZE_HELD' "$OUT" && grep -qF 'verdict=FREEZE_HELD' "$OUT"; then
  pass "MZ-U5: an unwritable sentinel on unfreeze -> FREEZE_HELD (paging verdict)"
else fail "MZ-U5: a failed sentinel clear did not page" "$(ctx)"; fi

# MZ-U6/F8: an UNREADABLE sentinel is its own verdict — an I/O fault is not a
# provenance verdict (unattributed) nor an instrument failure (probe_failed).
run_mode mz-u6-unread unfreeze SHIM_FREEZE=r3
if [ "$RC" = 5 ] && has_store unfreeze frozen_unreadable && ! grep -q 'rm -f --' "$TLF"; then
  pass "MZ-U6: an unreadable sentinel on unfreeze -> verdict=frozen_unreadable"
else fail "MZ-U6: an unreadable sentinel was misclassified" "$(ctx)"; fi
run_mode mz-f8-unread freeze SHIM_GC_STATE=inactive SHIM_FREEZE=r3
if [ "$RC" = 5 ] && has_store freeze frozen_unreadable; then
  pass "MZ-F8: an unreadable sentinel on freeze -> verdict=frozen_unreadable"
else fail "MZ-F8: an unreadable sentinel was misclassified on freeze" "$(ctx)"; fi

# MZ-P1: the transactional probe — provision + fenced push + remove, zero residue.
run_mode mz-p1-ok probe SHIM_PROBE=ok
if [ "$RC" = 0 ] && has_store probe ok && grep -q 'git-data-provision.sh' "$TLF" && grep -q 'git-data-remove.sh' "$TLF" && grep -q 'lease-gen' "$TLF" \
   && grep -qF 'HEAD:refs/soleur/worktrees/cutover-probe/probe' "$TLF"    && ! grep -qF 'refs/heads/cutover-probe' "$TLF"; then
  pass "MZ-P1: probe -> provision + CAS-fenced in-namespace push + remove, verdict=ok"
else fail "MZ-P1: probe happy path wrong" "$(ctx)"; fi

# MZ-P2: a push the fence refuses -> fenced_push_failed, and the residue-cleanup retry ran.
run_mode mz-p2-pushfail probe SHIM_PROBE=pushfail
# The retry is a SECOND ssh call whose remote command starts `env -i` (the probe's own
# remote starts `id=` and flattens an inline `env -i … git-data-remove.sh` — a single
# grep would satisfy without the retry ever running, so count >= 2 remove-bearing
# lines AND require a line whose remote segment begins env -i after the host:port).
remove_lines="$(grep -c 'git-data-remove.sh' "$TLF" || true)"
if [ "$RC" = 5 ] && has_store probe fenced_push_failed    && [ "$remove_lines" -ge 2 ]    && grep -qE ' 10\.0\.1\.20 env -i PATH=' "$TLF"; then
  pass "MZ-P2: a refused push -> fenced_push_failed, cleanup retry attempted"
else fail "MZ-P2: a refused push was not attributed" "$(ctx)"; fi

# MZ-P3/P4: remove failure and residue are their own verdicts.
run_mode mz-p3-remfail probe SHIM_PROBE=remfail
if [ "$RC" = 5 ] && has_store probe remove_failed; then
  pass "MZ-P3: a failed remove -> verdict=remove_failed"
else fail "MZ-P3: a failed remove was not attributed" "$(ctx)"; fi
run_mode mz-p4-residue probe SHIM_PROBE=residue
if [ "$RC" = 5 ] && has_store probe residue_left; then
  pass "MZ-P4: a repo surviving remove -> verdict=residue_left"
else fail "MZ-P4: residue was not attributed" "$(ctx)"; fi

# MZ-P9: the probe's push refspec is INSIDE the fence's worktree namespace — the real
# pre-receive rejects refs/heads/* for any worktree-id, so a `refs/heads/cutover-probe`
# push can never land (the fence is planted at birth by the same PR; D0 ownership).
if grep -qF "HEAD:refs/soleur/worktrees/cutover-probe/probe" "$SCRIPT" \
   && grep -qF "rev-parse --verify -q refs/soleur/worktrees/cutover-probe/probe" "$SCRIPT" \
   && ! grep -qF "refs/heads/cutover-probe" "$SCRIPT"; then
  pass "MZ-P9: the probe pushes/verifies refs/soleur/worktrees/cutover-probe/probe — the only namespace the fence admits"
else fail "MZ-P9: the probe refspec is outside the worktree namespace (the fence would reject it on every real run)"; fi

# MZ-P5: provision failure -> probe_failed reason=provision.
run_mode mz-p5-provfail probe SHIM_PROBE=provfail
if [ "$RC" = 5 ] && has_store probe probe_failed && grep -q 'reason=provision' "$OUT"; then
  pass "MZ-P5: a failed provision -> probe_failed reason=provision"
else fail "MZ-P5: a failed provision was not attributed" "$(ctx)"; fi

# MZ-P6/P7/P8: the probe's other probe_failed reasons — wrapper lied, scratch failed,
# the fence accepted bytes no ref holds.
run_mode mz-p6-nocreate probe SHIM_PROBE=nocreate
if [ "$RC" = 5 ] && has_store probe probe_failed && grep -q 'reason=repo_absent_after_provision' "$OUT"; then
  pass "MZ-P6: provision without a repo -> probe_failed reason=repo_absent_after_provision"
else fail "MZ-P6: an absent repo post-provision was not attributed" "$(ctx)"; fi
run_mode mz-p7-scratch probe SHIM_PROBE=scratch
if [ "$RC" = 5 ] && has_store probe probe_failed && grep -q 'reason=scratch' "$OUT"; then
  pass "MZ-P7: a scratch-setup failure -> probe_failed reason=scratch"
else fail "MZ-P7: a scratch failure was not attributed" "$(ctx)"; fi
run_mode mz-p8-noref probe SHIM_PROBE=noref
if [ "$RC" = 5 ] && has_store probe probe_failed && grep -q 'reason=ref_not_landed' "$OUT"; then
  pass "MZ-P8: a push whose ref never landed -> probe_failed reason=ref_not_landed"
else fail "MZ-P8: an unlanded ref was not attributed" "$(ctx)"; fi

# MZ-L: an unsafe probe id (bad lineage -> id shape) refuses arg_probe_id.
run_mode mz-l-badid probe CUTOVER_LINEAGE='bad;id'
if [ "$RC" = 5 ] && grep -qF 'verdict=lineage_absent' "$OUT" && [ ! -s "$TLF" ]; then
  pass "MZ-L: a lineage with metacharacters -> lineage_absent before any remote"
else fail "MZ-L: an unsafe lineage was not refused" "$(ctx)"; fi

# MZ-V: MODE=bogus -> verdict=mode_invalid, nothing dialed.
run_case mz-v-bogus "${KEYED[@]}" MODE=bogus
if [ "$RC" = 5 ] && grep -qF 'verdict=mode_invalid' "$OUT" && [ ! -s "$TLF" ]; then
  pass "MZ-V: an unknown MODE -> verdict=mode_invalid, exit 5, nothing dialed"
else fail "MZ-V: an unknown mode was not refused" "$(ctx)"; fi

# MZ-RA: resume arm A — a proof run whose store session hits a SAME-LINEAGE sentinel
# (only this run's earlier attempt could have written it) tolerates and continues.
# SHIM_VERIFY=r23 simulates the remote exit-23 (sentinel present); probe_freeze then
# answers `ours` via SHIM_FREEZE.
run_case mz-ra-resume "${KEYED[@]}" MODE=proof SHIM_VERIFY=r23 SHIM_FREEZE=ours CUTOVER_LINEAGE=lin-test-1
if [ "$RC" = 0 ] && grep -q 'resume_same_lineage' "$OUT" && grep -q 'resume arm A' "$OUT"; then
  pass "MZ-RA: same-lineage sentinel during proof -> resume_same_lineage, proof passes"
else fail "MZ-RA: resume arm A did not tolerate the same-lineage sentinel" "$(ctx)"; fi
# MZ-RB: the foreign-sentinel proof refusal is unchanged — a sentinel some OTHER run
# wrote still wedges a proof (the reviewer-cited wedge guard).
run_case mz-rb-foreign "${KEYED[@]}" MODE=proof SHIM_VERIFY=r23 SHIM_FREEZE=foreign CUTOVER_LINEAGE=lin-test-1
if [ "$RC" = 5 ] && has_store store-verified cutover_frozen; then
  pass "MZ-RB: foreign sentinel during proof -> verdict=cutover_frozen (still refused)"
else fail "MZ-RB: a foreign sentinel was tolerated by the proof" "$(ctx)"; fi

# ── WORKFLOW — git-data-cutover.yml (D-6 / AC9 / G6 / G7) ──────────────────────────────
cat > "$T/wf.py" <<'PY'
import sys, yaml, json, re
# Split so the doppler-set precommit hook (which greps the literal) does not trip on this TEST.
SECRETS_SET = "doppler secrets" + " set"
wf_path, iv_path, apply_path, steps_dir = sys.argv[1:5]
wf_text = open(wf_path).read()
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
try:
    wf = yaml.safe_load(wf_text) or {}
except Exception as e:
    print("FAIL\tWF0: workflow parses as YAML\t%s" % str(e)[:200]); sys.exit()
check("WF0: workflow parses as YAML", isinstance(wf, dict))
iv = yaml.safe_load(open(iv_path)); ap = yaml.safe_load(open(apply_path))
on = wf.get(True) or wf.get("on") or {}
check("WF-on: the only trigger is workflow_dispatch (on: read through the True-key lookup)", isinstance(on, dict) and list(on.keys()) == ["workflow_dispatch"], on if not isinstance(on, dict) else list(on.keys()))
inputs = ((on.get("workflow_dispatch") or {}).get("inputs") or {}) if isinstance(on, dict) else {}
check("G7/AC9: workflow_dispatch inputs are exactly {confirm, lineage, mode} (PR2: mode selects proof|flip|rollback|unfreeze|redeploy; lineage is the stranded-sentinel lever for unfreeze)", sorted(inputs.keys()) == ["confirm", "lineage", "mode"], sorted(inputs.keys()))
check("AC9: the mode input is a closed choice of exactly proof|flip|rollback|unfreeze|redeploy",
      sorted((inputs.get("mode") or {}).get("options") or []) == ["flip", "proof", "redeploy", "rollback", "unfreeze"],
      (inputs.get("mode") or {}).get("options"))
check("WF-perm: permissions are exactly {contents: read, actions: read} (actions:read is the precondition run-state reads)",
      wf.get("permissions") == {"actions": "read", "contents": "read"}, wf.get("permissions"))
env = wf.get("env") or {}
check("WF1: workflow env WEB_HOST_PRIVATE_IP is 10.0.1.10", env.get("WEB_HOST_PRIVATE_IP") == "10.0.1.10", env.get("WEB_HOST_PRIVATE_IP"))
rep = ((ap.get("jobs") or {}).get("git_data_host_replace") or {}).get("concurrency") or {}
conc = wf.get("concurrency") or {}
check("G6: workflow-level concurrency group equals git_data_host_replace's literal (git-data-state)",
      isinstance(conc, dict) and bool(rep.get("group")) and conc.get("group") == rep.get("group") == "git-data-state", (conc, rep.get("group")))
check("G6: workflow-level cancel-in-progress is False", isinstance(conc, dict) and conc.get("cancel-in-progress") is False, conc)
jobs = wf.get("jobs") or {}
check("WF-jobs: exactly two jobs, cutover and notify-failure (the notify job is separate so it still runs when the cutover job is cancelled, times out or loses its runner)", sorted(jobs.keys()) == ["cutover", "notify-failure"], list(jobs.keys()))
job = jobs.get("cutover") or {}
envname = job.get("environment")
if isinstance(envname, dict): envname = envname.get("name")
check("AC9: job cutover declares environment web-platform-infra-apply", envname == "web-platform-infra-apply", envname)
check("WF-jobconc: the job joins web-1-swap (the flip's fan-out deploy mutates web-1 — a concurrent release must not interleave)",
      (job.get("concurrency") or {}).get("group") == "web-1-swap" and (job.get("concurrency") or {}).get("cancel-in-progress") is False,
      job.get("concurrency"))
check("WF-timeout: the job timeout is >= 120 minutes (a fan-out swap inside a flip can take ~80 min)",
      isinstance(job.get("timeout-minutes"), int) and job["timeout-minutes"] >= 120, job.get("timeout-minutes"))
check("WF-jobenv: the job declares no job-level env", "env" not in job)
steps = job.get("steps") or []
def idx(pred):
    return [i for i, s in enumerate(steps) if pred(s)]
BRIDGE = "./.github/actions/cf-tunnel-ssh-bridge"
pos = {
    "confirm": idx(lambda s: s.get("id") == "confirm"),
    "checkout": idx(lambda s: str(s.get("uses", "")).startswith("actions/checkout@")),
    "doppler": idx(lambda s: s.get("id") == "doppler"),
    "flag_precheck": idx(lambda s: s.get("id") == "flag_precheck"),
    "secrets_check": idx(lambda s: s.get("id") == "secrets_check"),
    "flip_preconditions": idx(lambda s: s.get("id") == "flip_preconditions"),
    "bridge": idx(lambda s: s.get("uses") == BRIDGE),
    "key_fetch": idx(lambda s: s.get("id") == "key_fetch"),
    "ssh_config": idx(lambda s: s.get("id") == "ssh_config"),
    "host_proof": idx(lambda s: isinstance(s.get("env"), dict) and s["env"].get("MODE") == "proof"),
    "freeze": idx(lambda s: isinstance(s.get("env"), dict) and s["env"].get("MODE") == "freeze"),
    "flag_write": idx(lambda s: s.get("id") == "flag_write"),
    "redeploy": idx(lambda s: isinstance(s.get("run"), str) and "dispatch-web-redeploy/track.sh" in s["run"] and not s.get("if") == "always()"),
    "unfreeze": idx(lambda s: isinstance(s.get("env"), dict) and s["env"].get("MODE") == "unfreeze"),
    "probe": idx(lambda s: isinstance(s.get("env"), dict) and s["env"].get("MODE") == "probe"),
    "teardown": idx(lambda s: s.get("name") == "Tear down cloudflared SSH bridge"),
    "finalizer": idx(lambda s: s.get("name") and "Finalizer" in s["name"]),
}
single = all(len(v) == 1 for v in pos.values())
order = ["confirm", "checkout", "doppler", "flag_precheck", "secrets_check", "flip_preconditions", "bridge", "key_fetch", "ssh_config", "host_proof", "freeze", "flag_write", "redeploy", "unfreeze", "probe", "finalizer", "teardown"]
check("D-6: each step exists exactly once, in order confirm < checkout < doppler < flag precheck < secrets check < preconditions < bridge < key fetch < ssh_config < proof < freeze < flag write < redeploy < unfreeze < probe < finalizer < teardown (the finalizer runs BEFORE the bridge teardown — its unfreeze arm needs the SSH path alive)",
      single and [pos[k][0] for k in order] == sorted(pos[k][0] for k in order), {k: v for k, v in pos.items()})
def step(k):
    return steps[pos[k][0]] if len(pos[k]) == 1 else {}
b = step("bridge")
check("WF3: bridge passes server-ip from env.WEB_HOST_PRIVATE_IP", (b.get("with") or {}).get("server-ip") == "${{ env.WEB_HOST_PRIVATE_IP }}", (b.get("with") or {}).get("server-ip"))
check("WF4: the bridge is gated to the host-touching modes (not redeploy; not a nothing-rollback)",
      bool(b) and "!= 'redeploy'" in str(b.get("if")) and "nothing_to_rollback != '1'" in str(b.get("if")) and "env" not in b, b.get("if"))
check("WF-bridge-token: bridge doppler-token is secrets.DOPPLER_TOKEN", (b.get("with") or {}).get("doppler-token") == "${{ secrets.DOPPLER_TOKEN }}", (b.get("with") or {}).get("doppler-token"))
fp = step("flag_precheck")
check("AC9: flag precheck binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD, FLAG_MODE} and runs the precheck script, gated off redeploy",
      fp.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}", "FLAG_MODE": "${{ steps.confirm.outputs.mode }}"}
      and "git-data-flag-precheck.sh" in str(fp.get("run", "")) and "!= 'redeploy'" in str(fp.get("if")),
      (fp.get("env"), fp.get("if")))
sc = step("secrets_check")
check("WF-secrets: secrets check tests presence only ({DOPPLER_TOKEN_PRESENT, GIT_DATA_ROOT_TOKEN_PRESENT, FLAG_WRITE_TOKEN_PRESENT} as != '' booleans) + MODE",
      sc.get("env") == {"DOPPLER_TOKEN_PRESENT": "${{ secrets.DOPPLER_TOKEN != '' }}", "GIT_DATA_ROOT_TOKEN_PRESENT": "${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT != '' }}", "FLAG_WRITE_TOKEN_PRESENT": "${{ secrets.DOPPLER_TOKEN_GIT_DATA_FLAG != '' }}", "MODE": "${{ steps.confirm.outputs.mode }}"}, sc.get("env"))
kf = step("key_fetch")
check("AC9: key fetch binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_GIT_DATA_ROOT}, gated off redeploy",
      kf.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}"} and "!= 'redeploy'" in str(kf.get("if")), (kf.get("env"), kf.get("if")))
cf = step("ssh_config")
check("WF-sshcfg: the ssh_config writer has no env: and is gated to host-touching modes", bool(cf) and "env" not in cf and "!= 'redeploy'" in str(cf.get("if")), cf.get("if"))
r = step("host_proof")
check("WF6: the host-side proof step binds {WEB_HOSTS, GIT_DATA_SSH, MODE=proof, CUTOVER_LINEAGE=cutover-<run_id>}",
      r.get("env") == {"WEB_HOSTS": "${{ env.WEB_HOST_PRIVATE_IP }}", "GIT_DATA_SSH": "ssh -F ${{ runner.temp }}/gd-ssh-config", "MODE": "proof", "CUTOVER_LINEAGE": "cutover-${{ github.run_id }}"}, r.get("env"))
check("WF10: the proof step runs the script, mode-gated to proof|flip — unfreeze is EXCLUDED (the proof refuses a held sentinel, which is unfreeze's only reason to exist)",
      str(r.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-cutover.sh"
      and "proof" in str(r.get("if")) and "'unfreeze'" not in str(r.get("if")), (r.get("run"), r.get("if")))
uf = step("unfreeze")
check("WF10b: the unfreeze step accepts the operator lineage override (stranded sentinel recovery) and falls back to this run's lineage",
      bool(uf) and "inputs.lineage" in json.dumps(uf.get("env") or {}), (uf.get("env") or {}).get("CUTOVER_LINEAGE"))
asrt = next((s for s in steps if "git_data_store" in str(s.get("name") or "")), None)
check("WF11: the per-host assert keys web-1 on BOTH host_name spellings — 'soleur-web-platform' and the live #6616 mislabel 'soleur-inngest-prd' — via an IN list",
      bool(asrt) and "soleur-web-platform soleur-inngest-prd" in str(asrt.get("run") or "")
      and "host_name') IN (" in str(asrt.get("run") or "")
      and "soleur-web-1" not in str(asrt.get("run") or ""),
      str(asrt.get("run") or "")[:120])
td = step("teardown")
check("WF7: teardown is if: always() and after the script step", td.get("if") == "always()")
# Step GATING (C7): the content rows above cannot see a step that stops gating. Before the script
# step nothing may continue past its own failure, and only teardown and the summary run on a failed job.
SUMMARY = "Run summary"
coe = [s.get("id") or s.get("name") or s.get("uses") for s in steps if "continue-on-error" in s]
summ = [s for s in steps if s.get("name") == SUMMARY]
always_steps = [s.get("name") or s.get("id") for s in steps if s.get("if") == "always()"]
check("WF-gating: no step carries continue-on-error; exactly teardown + finalizer + summary carry if:always()",
      len(steps) >= 15 and not coe
      and sorted(always_steps) == sorted(["Tear down cloudflared SSH bridge", "Finalizer — total unwind on an incomplete flip", SUMMARY])
      and td.get("if") == "always()" and len(summ) == 1 and summ[0].get("if") == "always()",
      (coe, always_steps))
# C7: every OTHER if: is a mode/output gate only — no `false`, no success() drift.
bad_ifs = [s.get("name") or s.get("id") for s in steps
           if "if" in s and s.get("if") != "always()"
           and not re.search(r"steps\.(confirm\.outputs\.mode|flag_precheck\.outputs)", str(s["if"]))]
check("WF-gating: every non-always() if: gates on steps.confirm.outputs.mode or flag_precheck outputs (no arbitrary if:)",
      not bad_ifs, bad_ifs)
# The finalizer is the TOTAL unwind contract: flag off -> redeploy -> unfreeze -> gc.
fz = step("finalizer")
fzbody = fz.get("run") or ""
fzcode = "\n".join(l for l in fzbody.splitlines() if not l.lstrip().startswith("#"))
check("WF-finalizer: the finalizer unwinds flag off (write seam), redeploys via track.sh, and unfreezes via MODE=unfreeze",
      "GIT_DATA_STORE_ENABLED" in fzcode and SECRETS_SET in fzcode
      and "dispatch-web-redeploy/track.sh" in fzcode and "MODE=unfreeze" in fzcode
      and "git-data-cutover.sh" in fzcode and "flag_written" in fzcode,
      fzcode[:400])
check("WF-finalizer: the finalizer binds BOTH tokens it needs (write seam + prd_terraform read) and no other secret",
      fz.get("env") and fz["env"].get("DOPPLER_TOKEN_GIT_DATA_FLAG") == "${{ secrets.DOPPLER_TOKEN_GIT_DATA_FLAG }}" and fz["env"].get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN }}",
      fz.get("env"))
body = td.get("run") or ""
code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
check("WF8: teardown deletes the NAT rule, kills cloudflared, shreds the CI keyfile, the root key, the ssh_config, the known_hosts and the pin, each guarded",
      all(t in code for t in ('[[ -n "${SERVER_IP:-}" ]]', 'iptables -t nat -D OUTPUT', '[[ -n "${CLOUDFLARED_PID:-}" ]]',
                              '[[ -n "${CI_SSH_KEYFILE:-}" && -f "$CI_SSH_KEYFILE" ]]', 'shred -u "$CI_SSH_KEYFILE"',
                              '[[ -f "$RUNNER_TEMP/gd-root-key" ]]', 'shred -u "$RUNNER_TEMP/gd-root-key"',
                              '[[ -f "$RUNNER_TEMP/gd-ssh-config" ]]', 'shred -u "$RUNNER_TEMP/gd-ssh-config"',
                              '"$RUNNER_TEMP/gd-known-hosts"', '"$RUNNER_TEMP/git-data.pin"')))
dumped = json.dumps(wf)
SECRET_RE = r"secrets\s*(?:\.\s*([A-Za-z0-9_]+)|\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\])"
def secrets_in(obj):
    return sorted(set(a or b for a, b in re.findall(SECRET_RE, json.dumps(obj))))
secrets = secrets_in(wf)
check("WF9: the referenced secrets are exactly {DOPPLER_TOKEN, DOPPLER_TOKEN_GIT_DATA_FLAG, DOPPLER_TOKEN_GIT_DATA_ROOT, DOPPLER_TOKEN_INFRA_PRIVILEGED, DOPPLER_TOKEN_PRD, GITHUB_TOKEN, RESEND_API_KEY, SENTRY_ACTIONS_RO_TOKEN, SENTRY_API_HOST}",
      secrets == ["DOPPLER_TOKEN", "DOPPLER_TOKEN_GIT_DATA_FLAG", "DOPPLER_TOKEN_GIT_DATA_ROOT", "DOPPLER_TOKEN_INFRA_PRIVILEGED", "DOPPLER_TOKEN_PRD", "GITHUB_TOKEN", "RESEND_API_KEY", "SENTRY_ACTIONS_RO_TOKEN", "SENTRY_API_HOST"], secrets)
check("AC9: DOPPLER_TOKEN_WRITE is not referenced", "DOPPLER_TOKEN_WRITE" not in dumped)
# PRD token census: every place in the parsed workflow that names it (>= 1 step scanned).
# EVERY job is scanned (the census used to read only the cutover job's steps, so a credential bound in
# a second job was invisible): all_steps spans every job, and job-level keys are scanned per job.
all_steps = [(jn, s) for jn, j in jobs.items() for s in (j.get("steps") or [])]
prd_sites = [("step", s.get("id") or s.get("name")) for jn, s in all_steps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
prd_sites += [("top", k) for k, v in wf.items() if k != "jobs" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
prd_sites += [("job", jn + "." + k) for jn, j in jobs.items() for k, v in j.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
check("AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step (%d steps scanned across %d jobs)" % (len(all_steps), len(jobs)),
      len(all_steps) >= 2 and len(jobs) == 2 and prd_sites == [("step", "flag_precheck")], prd_sites)
# The write-seam token census: bound ONLY on the steps that write prd — flag_write, the
# cutover-stamp step and the finalizer's unwind. secrets_check's presence probe
# (FLAG_WRITE_TOKEN_PRESENT, a boolean) is a name-reference, not a binding — exempt.
wr_sites = sorted(s.get("id") or s.get("name") for jn, s in all_steps if "DOPPLER_TOKEN_GIT_DATA_FLAG" in json.dumps(s) and s.get("id") != "secrets_check")
wr_job_level = sorted(jn + "." + k for jn, j in jobs.items() for k, v in j.items() if k != "steps" and "DOPPLER_TOKEN_GIT_DATA_FLAG" in json.dumps(v, default=str))
check("AC9: DOPPLER_TOKEN_GIT_DATA_FLAG is bound exactly on {flag_write, cutover stamp, finalizer} — in no other step of ANY job and at no job level",
      wr_sites == sorted(["finalizer", "Write GIT_DATA_LUKS_CUTOVER_AT (last — proven cutover only)", "flag_write"]) and not wr_job_level, (wr_sites, wr_job_level))
# G7 row: the PR1 variable vocabulary is gone (DRY_RUN/CONFIRM_WIPE refuse at the SCRIPT);
# `rollback` is a real mode name now, not a refused env.
real_modes = re.findall(r"\b(DRY_RUN|CONFIRM_WIPE|dry_run|confirm_wipe)\b", dumped)
check("G7: no DRY_RUN/CONFIRM_WIPE vocabulary anywhere in the workflow (mode/rollback are real verbs)", not real_modes, sorted(set(real_modes)))
refs = sorted(set(re.findall(r"inputs\.([A-Za-z0-9_]+)", dumped)))
check("WF-inputs-refs: only inputs.confirm, inputs.lineage and inputs.mode are referenced", refs == ["confirm", "lineage", "mode"], refs)
# Pins on the RAW text (the `# v` comment is not in the parse).
uses = [l.strip() for l in wf_text.splitlines() if re.match(r"^\s*(-\s+)?uses:\s", l)]
remote = [u for u in uses if not re.search(r"uses:\s+\./", u)]
local = [re.sub(r"^(-\s+)?uses:\s+", "", u) for u in uses if re.search(r"uses:\s+\./", u)]
NOTIFY_ACTION = "./.github/actions/notify-ops-email"
check("AC9 pins: every remote uses: is @<40 hex> # v… (%d remote), and the only local actions are the bridge and the notify composite" % len(remote),
      len(remote) >= 2 and all(re.search(r"uses:\s+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v", u) for u in remote) and sorted(local) == sorted([BRIDGE, NOTIFY_ACTION]),
      (remote, local))
# --- notify-failure (Guard 2, #8211 plan): a failed, stranded or cancelled cutover always reaches the
# notify path, a clean run never does, and the path carries no workspace id, no free-text input and no
# privileged credential. The finalizer and the notify body are EXECUTED below (NB/FZ rows); these rows pin
# the wiring around them. Every comparison is on the WHOLE normalized expression or the WHOLE key set,
# never on a substring a decoy can satisfy. ---
notify = jobs.get("notify-failure") or {}
nsteps = notify.get("steps") or []
nif = " ".join(str(notify.get("if") or "").split())
NIF = "always() && (needs.cutover.result == 'failure' || needs.cutover.result == 'cancelled') && needs.cutover.outputs.started != 'false'"
check("N-if: notify-failure needs cutover and its if: is EXACTLY always() && (failure || cancelled) && started != 'false' — never != 'success' (a skipped run must not email), never failure() alone, never an implicit success()",
      notify.get("needs") == "cutover" and nif == NIF, nif)
JOBKEYS = {"needs", "if", "runs-on", "timeout-minutes", "permissions", "steps"}
cut_keys = set(job.keys())
check("N-jobkeys: every job key is on its allowlist — notify-failure carries exactly {needs, if, runs-on, timeout-minutes, permissions, steps} (no environment, concurrency, env, outputs, continue-on-error), and the cutover job carries no continue-on-error, permissions, env or defaults",
      bool(notify) and set(notify.keys()) == JOBKEYS
      and cut_keys <= {"runs-on", "timeout-minutes", "environment", "concurrency", "outputs", "steps"}
      and notify.get("permissions") == {"contents": "read", "issues": "write"}
      and isinstance(notify.get("timeout-minutes"), int) and notify["timeout-minutes"] <= 10,
      (sorted(set(notify.keys()) ^ JOBKEYS), sorted(cut_keys)))
check("N-secrets: notify-failure references exactly {GITHUB_TOKEN, RESEND_API_KEY} — no Doppler token, no flag-write token",
      bool(notify) and secrets_in(notify) == ["GITHUB_TOKEN", "RESEND_API_KEY"], secrets_in(notify))
# A `secrets` token that is not `secrets.NAME` (toJSON(secrets), secrets[env.X]) is a binding no census sees, and a
# top-level env: or defaults: entry is inherited by every job — scan the whole parsed workflow for both.
all_exprs = " ".join(re.findall(r"\$\{\{(.*?)\}\}", dumped))
all_tokens = re.findall(r"\bsecrets\b", all_exprs)
named_tokens = re.findall(r"\bsecrets\s*\.\s*[A-Za-z0-9_]+", all_exprs)
top_nonjobs = {k: v for k, v in wf.items() if k not in ("jobs", True, "on", "name", "concurrency", "permissions", "env")}
check("N-secrets-form: every `secrets` token in the workflow is the literal secrets.NAME form (no toJSON(secrets), no secrets[...] lookup), and no top-level key other than the declared env names a secret (a workflow-level env is inherited by every job)",
      len(all_tokens) == len(named_tokens) and "secrets" not in json.dumps(wf.get("env") or {}) and not top_nonjobs,
      (len(all_tokens), len(named_tokens), sorted(top_nonjobs)))
n_co = [i for i, x in enumerate(nsteps) if str(x.get("uses", "")).startswith("actions/checkout@")]
n_em = [i for i, x in enumerate(nsteps) if x.get("uses") == NOTIFY_ACTION]
n_is = [i for i, x in enumerate(nsteps) if "gh issue create" in str(x.get("run", ""))]
email_s = nsteps[n_em[0]] if len(n_em) == 1 else {}
issue_s = nsteps[n_is[0]] if len(n_is) == 1 else {}
check("N-order: checkout (persist-credentials false) precedes the local notify-ops-email action; the email step is id email with continue-on-error TRUE; the issue step has none, no if:, and runs both gh issue create and gh issue comment, after the email step (the issue is the primary channel)",
      len(n_co) == 1 and len(n_em) == 1 and len(n_is) == 1 and n_co[0] < n_em[0] < n_is[0]
      and (nsteps[n_co[0]].get("with") or {}) == {"persist-credentials": False}
      and email_s.get("id") == "email" and email_s.get("continue-on-error") is True
      and "continue-on-error" not in issue_s and "if" not in issue_s and "gh issue comment" in str(issue_s.get("run", "")),
      (n_co, n_em, n_is, email_s.get("continue-on-error"), issue_s.get("continue-on-error")))
bodies = [x.get("run") or "" for x in nsteps]
check("N-body: no notify run: body interpolates a ${{ }} expression and the job never references inputs.* in any spelling (inputs.x, inputs['x'], github.event) — every value arrives through env:",
      bool(notify) and not any("${{" in b for b in bodies)
      and not re.search(r"\binputs\b|github\.event|toJSON|vars\.", json.dumps(notify)), [b[:60] for b in bodies if "${{" in b])
EXPR_OK = [r"needs\.cutover\.result", r"needs\.cutover\.outputs\.(mode|finalizer_ran|freeze_held|recovery_failed|probe_failed|started)",
           r"github\.(run_id|server_url|repository)", r"secrets\.(GITHUB_TOKEN|RESEND_API_KEY)",
           r"steps\.body\.outputs\.(subject|body)", r"steps\.email\.outcome"]
exprs = [e.strip() for e in re.findall(r"\$\{\{(.*?)\}\}", json.dumps(nsteps))]
bad_exprs = [e for e in exprs if not any(re.fullmatch(p_, e) for p_ in EXPR_OK)]
body_env = (next((x for x in nsteps if x.get("id") == "body"), {}).get("env")) or {}
check("N-exprs: every ${{ }} expression in the notify steps is on the allowlist (the needs.cutover verdict outputs, run id/url, the two secrets, the body step's own outputs and the email outcome), and the body step's env is EXACTLY the nine verdict inputs with their canonical sources",
      bool(exprs) and not bad_exprs and body_env == {
          "MODE": "${{ needs.cutover.outputs.mode }}", "RESULT": "${{ needs.cutover.result }}",
          "FINALIZER_RAN": "${{ needs.cutover.outputs.finalizer_ran }}", "FREEZE_HELD": "${{ needs.cutover.outputs.freeze_held }}",
          "RECOVERY_FAILED": "${{ needs.cutover.outputs.recovery_failed }}", "PROBE_FAILED": "${{ needs.cutover.outputs.probe_failed }}",
          "RUN_ID": "${{ github.run_id }}", "RUN_URL": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"},
      (bad_exprs, sorted(body_env)))
# every steps.<id>.outputs / steps.<id>.outcome reference must resolve to a declared step id in ITS job
def ref_ok(jname, jobd):
    ids = {x.get("id") for x in (jobd.get("steps") or []) if x.get("id")}
    refs = set(re.findall(r"steps\.([A-Za-z0-9_-]+)\.(?:outputs|outcome|conclusion)", json.dumps(jobd)))
    return sorted(refs - ids)
check("N-refs: every steps.<id>.outputs/outcome reference in either job resolves to a step id declared in that same job (a renamed id would otherwise read empty and still pass every substring row)",
      not ref_ok("cutover", job) and not ref_ok("notify-failure", notify), (ref_ok("cutover", job), ref_ok("notify-failure", notify)))
oc = job.get("outputs") or {}
check("N-outputs: the cutover job exports exactly {mode, started, finalizer_ran, freeze_held, recovery_failed, probe_failed} with these exact expressions",
      oc == {"mode": "${{ steps.confirm.outputs.mode }}", "started": "${{ steps.confirm.outputs.mode != '' }}",
             "finalizer_ran": "${{ steps.finalizer.outputs.ran }}", "freeze_held": "${{ steps.finalizer.outputs.freeze_held }}",
             "recovery_failed": "${{ steps.finalizer.outputs.recovery_failed }}",
             "probe_failed": "${{ steps.probe.outcome == 'failure' && '1' || '' }}"}, oc)
check("N-finalizer: the finalizer step has id finalizer and is fed the unfreeze step's outcome (its behaviour is pinned by the executed FZ rows)",
      step("finalizer").get("id") == "finalizer" and (step("finalizer").get("env") or {}).get("UNFREEZE_OUTCOME") == "${{ steps.unfreeze.outcome }}"
      and (step("unfreeze").get("id") == "unfreeze"), (step("finalizer").get("env"), step("unfreeze").get("id")))
pr = step("probe")
check("N-probe: the single MODE=probe step carries id probe, runs after the unfreeze step, is gated to flip OR rollback, and has no continue-on-error (a failed probe fails the run red after the unwind)",
      pr.get("id") == "probe" and pos["probe"][0] > pos["unfreeze"][0] and "'flip'" in str(pr.get("if")) and "'rollback'" in str(pr.get("if"))
      and "continue-on-error" not in pr and "always()" not in str(pr.get("if")), pr.get("if"))
# Step bodies for the executed rows.
for k in ("key_fetch", "ssh_config", "secrets_check", "teardown", "finalizer"):
    s = step(k)
    if isinstance(s.get("run"), str):
        open("%s/%s.sh" % (steps_dir, k), "w").write(s["run"])
_nb = next((x for x in nsteps if x.get("id") == "body"), {})
if isinstance(_nb.get("run"), str):
    open("%s/notify_body.sh" % steps_dir, "w").write(_nb["run"])
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
# Since #8736 this suite is registered by PRESENCE (the deploy-script-tests
# legs glob-derive it), so the step under test is the legs' runner invocation —
# one step definition (the matrix fans it out), unmasked.
mine = [s for s in ivsteps if isinstance(s.get("run"), str) and s["run"].strip() == "bash apps/web-platform/infra/run-registered-suites.sh"]
check("AC10: infra-validation.yml's legs invoke the suite runner in exactly one step with no if:/continue-on-error",
      len(mine) == 1 and "if" not in mine[0] and not mine[0].get("continue-on-error"), len(mine))
print("\n".join(out))
PY
# wf_row <tsv> <name-prefix> — 0 when the named row is ok.
# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# YAML leg crashed on a mutant) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }
python3 "$T/wf.py" "$WF" "$IV" "$APPLY_WF" "$T/steps" > "$T/wf.tsv" 2> "$T/wf.err"
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -eq 50 ] || fail "WF: $_wf_n workflow verdicts were produced (expected exactly 50) — the YAML leg crashed, or a row was added or deleted without restating the count" "$(head -c 300 "$T/wf.err")"

# ── WORKFLOW STEPS, EXECUTED ──────────────────────────────────────────────────────────
# Per-name Doppler shim: answers per project/config/secret AND per flag presence, mirroring the
# measured v3.75.3 semantics (see git-data-flag-precheck.sh). A store is a directory tree
# $DOPPLER_STORE/<project>/<config>/<NAME>.
mkdir -p "$T/kbin" || { printf 'FAIL SETUP: mkdir kbin\n' >&2; exit 1; }
cat > "$T/kbin/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "${DOPPLER_LOG:-/dev/null}"
[ "${1:-}" = secrets ] && [ "${2:-}" = get ] || { echo "doppler-shim: unsupported: $*" >&2; exit 64; }
name="${3:-}"; shift 3
plain=0; noexit=0; proj=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plain) plain=1; shift ;;
    --no-exit-on-missing-secret) noexit=1; shift ;;
    -p|--project) proj="${2:-}"; shift 2 ;;
    -c|--config) cfg="${2:-}"; shift 2 ;;
    *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
[ "${SHIM_DOPPLER_SCOPE_ERROR:-0}" = 1 ] && { echo "Doppler Error: This token does not have access to requested config '$cfg'" >&2; exit 1; }
[ "$plain" = 1 ] || { echo "doppler-shim: --plain required" >&2; exit 64; }
d="$DOPPLER_STORE/$proj/$cfg"
if [ -z "$proj" ] || [ -z "$cfg" ] || [ ! -d "$d" ]; then echo "Doppler Error: Could not find requested config '$cfg'" >&2; exit 1; fi
if [ -f "$d/$name" ]; then cat "$d/$name"; exit 0; fi
if [ "$noexit" = 1 ] && [ "${SHIM_DOPPLER_IGNORE_FLAG:-0}" != 1 ]; then exit 0; fi
echo "Doppler Error: Could not find requested secret: $name" >&2; exit 1
SHIM
chmod +x "$T/kbin/doppler"

# Key fetch.
if [ ! -s "$T/steps/key_fetch.sh" ]; then
  fail "KF: the key fetch step body was not extracted" "never a pass on zero"
else
  ssh-keygen -q -t ed25519 -N '' -C fixture-root -f "$T/fixture-root" || { printf 'FAIL SETUP: ssh-keygen root\n' >&2; exit 1; }
  _kf_run() { # <label> <store-mode: good|garbage|empty|none> [extra env...]
    local label="$1" mode="$2"; shift 2
    local -a KF_FLAGS=(-eo pipefail)
    [ "${KF_XTRACE:-0}" = 1 ] && KF_FLAGS=(-x -eo pipefail)
    KR="$T/kf-$label"
    assert_fixture_dir "$KR"
    rm -rf "$KR"; mkdir -p "$KR/rt" "$KR/store/soleur-git-data-root/prd" || { printf 'FAIL SETUP: mkdir kf\n' >&2; exit 1; }
    case "$mode" in
      good)    printf '%s' "$(cat "$T/fixture-root")" > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      garbage) printf 'NOT-A-KEY-CANARY-91c\nsecond line\n' > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      empty)   : > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      none)    : ;;
    esac
    : > "$KR/github_env"; : > "$KR/doppler.log"
    env -i PATH="$T/kbin:/usr/bin:/bin" HOME="$KR" RUNNER_TEMP="$KR/rt" GITHUB_ENV="$KR/github_env" DOPPLER_STORE="$KR/store" \
      DOPPLER_LOG="$KR/doppler.log" DOPPLER_TOKEN=fixture-root-read "$@" \
      bash --noprofile --norc "${KF_FLAGS[@]}" "$T/steps/key_fetch.sh" > "$KR/stdout" 2>&1
    KF_RC=$?
  }
  _kf_run good good
  _key="$KR/rt/gd-root-key"
  if [ "$KF_RC" = 0 ] && [ -f "$_key" ] && [ "$(stat -c %a "$_key")" = 600 ] && [ -z "$(tail -c 1 "$_key")" ] \
     && ssh-keygen -y -f "$_key" </dev/null >/dev/null 2>&1 && cmp -s "$_key" "$T/fixture-root"; then
    pass "KF1: a good key lands at \$RUNNER_TEMP/gd-root-key, mode 600, with a trailing newline, and derives a public key"
  else fail "KF1: the key fetch did not produce a usable 0600 key file" "rc=$KF_RC $(tail -3 "$KR/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
  _kf_leak="$(python3 - "$KR/stdout" "$T/fixture-root" <<'PY'
import sys
out = open(sys.argv[1]).read().split("\n"); key = [l for l in open(sys.argv[2]).read().split("\n") if l]
masks = [l[len("::add-mask::"):] for l in out if l.startswith("::add-mask::")]
first_other = next((i for i, l in enumerate(out) if l and not l.startswith("::add-mask::")), len(out))
last_mask = max((i for i, l in enumerate(out) if l.startswith("::add-mask::")), default=-1)
problems = []
if sorted(set(masks)) != sorted(set(key)): problems.append("mask set != key lines")
if last_mask > first_other: problems.append("a mask followed other output")
for l in out:
    if l.startswith("::add-mask::"): continue
    if any(k in l for k in key if len(k) > 8): problems.append("key bytes outside a mask line")
print("OK" if not problems else ";".join(problems))
PY
)"
  if [ "$_kf_leak" = OK ]; then pass "KF1: every key line is add-masked before any other output, and no key byte reaches stdout otherwise"
  else fail "KF1: key masking/leak check failed" "$_kf_leak"; fi
  if [ ! -s "$KR/github_env" ] && [ "$(cat "$KR/doppler.log")" = "doppler secrets get GIT_DATA_ROOT_SSH_PRIVATE_KEY --plain -p soleur-git-data-root -c prd" ]; then
    pass "KF1: nothing is written to \$GITHUB_ENV, and doppler is called exactly once with -p soleur-git-data-root -c prd"
  else fail "KF1: GITHUB_ENV written or doppler argv differs" "env=[$(head -c 100 "$KR/github_env")] log=[$(tr '\n' '|' < "$KR/doppler.log")]"; fi
  for spec in "none:rc_nonzero" "empty:empty" "garbage:not_openssh_key"; do
    _m="${spec%%:*}"; _r="${spec##*:}"
    _kf_run "$_m" "$_m"
    _unmasked="$(grep -v '^::add-mask::' "$KR/stdout" || true)"
    if [ "$KF_RC" != 0 ] && grep -qxF "::error title=git-data-cutover key::verdict=git_data_root_key_fetch_failed reason=${_r}" "$KR/stdout" \
       && ! grep -q 'NOT-A-KEY-CANARY' <<< "$_unmasked"; then
      pass "KF ($_m): fails with verdict=git_data_root_key_fetch_failed reason=$_r, printing the reason word only"
    else fail "KF ($_m): expected reason=$_r" "rc=$KF_RC $(tr '\n' '|' < "$KR/stdout" | sed 's/::/: :/g' | cut -c1-300)"; fi
  done
  _kf_run scope good SHIM_DOPPLER_SCOPE_ERROR=1
  if [ "$KF_RC" != 0 ] && grep -qF 'reason=rc_nonzero' "$KR/stdout"; then pass "S10b/KF: a revoked or wrong-scope token is reason=rc_nonzero"
  else fail "S10b/KF: a scope error was not rc_nonzero" "rc=$KF_RC $(tr '\n' '|' < "$KR/stdout" | sed 's/::/: :/g')"; fi
  KF_XTRACE=1 _kf_run xtrace good
  if [ "$KF_RC" = 78 ] && [ ! -s "$KR/doppler.log" ] && [ ! -e "$KR/rt/gd-root-key" ]; then pass "KF: under xtrace the key fetch exits 78 before calling doppler"
  else fail "KF: the key fetch ran under xtrace" "rc=$KF_RC"; fi
fi

# ssh_config writer — its output is resolved by the REAL OpenSSH (`ssh -G`), not grepped alone.
if [ ! -s "$T/steps/ssh_config.sh" ]; then
  fail "SC: the ssh_config step body was not extracted" "never a pass on zero"
else
  # The git-data pin the flag precheck would have written: a key generated at test time.
  ssh-keygen -q -t ed25519 -N '' -C gd-pin-fixture -f "$T/gd-pin-key" || { printf 'FAIL SETUP: ssh-keygen gd pin\n' >&2; exit 1; }
  GD_PIN="$(cut -d' ' -f1,2 "$T/gd-pin-key.pub")"
  _sc_run() { # <label> <ci-keyfile-path-or-empty> [write-root-key=1] [git-data.pin content|ABSENT]
    SR="$T/sc-$1"
    assert_fixture_dir "$SR"
    rm -rf "$SR"; mkdir -p "$SR/rt" || { printf 'FAIL SETUP: mkdir sc\n' >&2; exit 1; }
    [ "${3:-1}" = 1 ] && printf 'fixture-root-key\n' > "$SR/rt/gd-root-key"
    [ "${4-$GD_PIN}" = ABSENT ] || printf '%s\n' "${4-$GD_PIN}" > "$SR/rt/git-data.pin"
    printf 'fixture-ci-key\n' > "$SR/ci-key"
    env -i PATH=/usr/bin:/bin HOME="$SR" RUNNER_TEMP="$SR/rt" GITHUB_WORKSPACE="$ROOT" ${2:+CI_SSH_KEYFILE="$2"} \
      bash --noprofile --norc -eo pipefail "$T/steps/ssh_config.sh" > "$SR/stdout" 2>&1
    SC_RC=$?; SC_CFG="$SR/rt/gd-ssh-config"; SC_KH="$SR/rt/gd-known-hosts"
  }
  _sc_run good "$T/sc-good/ci-key"
  if [ "$SC_RC" = 0 ] && [ -f "$SC_CFG" ] && [ "$(stat -c %a "$SC_CFG")" = 600 ]; then pass "SC1: the writer succeeds and the config is mode 600"
  else fail "SC1: the ssh_config writer failed" "rc=$SC_RC $(tr '\n' '|' < "$SR/stdout" | sed 's/::/: :/g')"; fi
  _sc_struct="$(python3 - "$SC_CFG" "$SR/rt/gd-root-key" "$T/sc-good/ci-key" "$SC_KH" <<'PY'
import sys, re
try: lines = open(sys.argv[1]).read().splitlines()
except Exception as e: print("unreadable"); sys.exit()
cfg, rootkey, cikey, kh = sys.argv[1:5]
blocks = {}; cur = None; problems = []; order = []
for l in lines:
    s = l.strip()
    if not s: continue
    kw = s.split(None, 1)[0].lower()
    if kw in ("host", "match"):
        cur = s; order.append(s); blocks[cur] = []; continue
    if cur is None: problems.append("option outside a block: " + s); continue
    blocks[cur].append(s)
if order != ["Host 10.0.1.10", "Host 10.0.1.20"]: problems.append("host lines %r" % order)
HARD = ["IdentitiesOnly yes", "BatchMode yes", "LogLevel INFO", "ForwardAgent no", "ClearAllForwardings yes",
        "PermitLocalCommand no", "ControlPath none", "UpdateHostKeys no", "StrictHostKeyChecking yes",
        "UserKnownHostsFile " + kh, "GlobalKnownHostsFile /dev/null", "User root"]
# Host-key pin (#7226): each block trusts exactly its own alias and algorithm.
PIN = {"Host 10.0.1.10": ["HostKeyAlias web-1", "HostKeyAlgorithms ecdsa-sha2-nistp256"],
       "Host 10.0.1.20": ["HostKeyAlias git-data", "HostKeyAlgorithms ssh-ed25519"]}
# The TOFU forms, built by concatenation (the tree-wide TOFU guard scans for the literals).
TOFU = ["stricthostkeychecking " + "accept" + "-new", "stricthostkeychecking " + "no", "userknownhostsfile " + "/dev/" + "null"]
want_id = {"Host 10.0.1.10": cikey, "Host 10.0.1.20": rootkey}
for h, opts in blocks.items():
    for o in HARD + PIN.get(h, ["?"]):
        if o not in opts: problems.append("%s lacks %s" % (h, o))
    for o in opts:
        if " ".join(o.lower().split()) in TOFU: problems.append("%s carries a TOFU option %r" % (h, o))
    for k in ("stricthostkeychecking", "userknownhostsfile", "hostkeyalias", "hostkeyalgorithms", "globalknownhostsfile"):
        if sum(1 for o in opts if o.lower().split()[0] == k) != 1: problems.append("%s: %s not exactly once" % (h, k))
    ids = [o for o in opts if o.lower().startswith("identityfile ")]
    if ids != ["IdentityFile " + want_id.get(h, "?")]: problems.append("%s identityfiles %r" % (h, ids))
    if any("%" in o for o in opts): problems.append("%s carries a %% token" % h)
pc20 = [o for o in blocks.get("Host 10.0.1.20", []) if o.lower().startswith("proxycommand ")]
if pc20 != ["ProxyCommand ssh -F %s -W 10.0.1.20:22 10.0.1.10" % cfg]: problems.append("proxycommand %r" % pc20)
if any(o.lower().startswith("proxy") for o in blocks.get("Host 10.0.1.10", [])): problems.append("web block has a proxy")
want_ct = {"Host 10.0.1.10": ["ConnectTimeout 10"], "Host 10.0.1.20": ["ConnectTimeout 20"]}
for h, want in want_ct.items():
    got = [o for o in blocks.get(h, []) if o.lower().startswith("connecttimeout")]
    if got != want: problems.append("%s connecttimeout %r" % (h, got))
print("OK" if not problems else "; ".join(problems))
PY
)"
  if [ "$_sc_struct" = OK ]; then pass "SC2: exactly Host 10.0.1.10 then Host 10.0.1.20 (no Host */Match), one IdentityFile each, literal ProxyCommand, ConnectTimeout 10 on the web-1 hop and 20 on git-data, every hardening option in both, each block pinned to its own alias and algorithm, no TOFU option"
  else fail "SC2: ssh_config structure differs" "$_sc_struct"; fi
  if [ "$(cat "$SC_KH" 2>/dev/null)" = "web-1 $WEB1_PIN
git-data $GD_PIN" ] && [ "$(stat -c %a "$SC_KH" 2>/dev/null)" = 444 ]; then
    pass "SC7: \$RUNNER_TEMP/gd-known-hosts is exactly 'web-1 <committed pin>' then 'git-data <precheck pin>', mode 444 (the shared writer, twice)"
  else fail "SC7: the known_hosts file differs" "[$(tr '\n' '|' < "$SC_KH" 2>/dev/null | cut -c1-300)]"; fi
  _g20="$(ssh -G -F "$SC_CFG" 10.0.1.20 2>/dev/null)"; _g10="$(ssh -G -F "$SC_CFG" 10.0.1.10 2>/dev/null)"
  if grep -qxF "proxycommand ssh -F $SC_CFG -W 10.0.1.20:22 10.0.1.10" <<< "$_g20" \
     && [ "$(grep '^identityfile ' <<< "$_g20")" = "identityfile $SR/rt/gd-root-key" ] && grep -qx 'user root' <<< "$_g20" \
     && [ "$(grep '^identityfile ' <<< "$_g10")" = "identityfile $T/sc-good/ci-key" ] && ! grep -q '^proxycommand ' <<< "$_g10" \
     && grep -qx 'identitiesonly yes' <<< "$_g20" && grep -qx 'forwardagent no' <<< "$_g10" \
     && grep -qx 'connecttimeout 10' <<< "$_g10" && grep -qx 'connecttimeout 20' <<< "$_g20" \
     && grep -qx 'hostkeyalias web-1' <<< "$_g10" && grep -qx 'hostkeyalias git-data' <<< "$_g20" \
     && grep -qx 'hostkeyalgorithms ecdsa-sha2-nistp256' <<< "$_g10" && grep -qx 'hostkeyalgorithms ssh-ed25519' <<< "$_g20" \
     && grep -qx 'stricthostkeychecking true' <<< "$_g10" && grep -qx 'stricthostkeychecking true' <<< "$_g20" \
     && grep -qx "userknownhostsfile $SC_KH" <<< "$_g10" && grep -qx "userknownhostsfile $SC_KH" <<< "$_g20" \
     && grep -qx 'globalknownhostsfile /dev/null' <<< "$_g20" && grep -qx 'updatehostkeys false' <<< "$_g20"; then
    pass "SC3: real OpenSSH (ssh -G) resolves git-data to the root key via the web-1 ProxyCommand (connect 20 s), and web-1 to the CI key with no proxy (connect 10 s); both strict, one known_hosts, aliases web-1/git-data, algorithms ecdsa-sha2-nistp256/ssh-ed25519"
  else fail "SC3: ssh -G resolution differs" "$(printf '%s' "$_g20" | grep -E '^(proxycommand|identityfile|user) ' | tr '\n' '|')"; fi
  _sc_run nokey ""
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && grep -qF 'verdict=ssh_config_key_absent' "$SR/stdout"; then pass "SC4: CI_SSH_KEYFILE unset -> ssh_config_key_absent, nothing written"
  else fail "SC4: the writer ran without the CI keyfile" "rc=$SC_RC"; fi
  _sc_run noroot "$T/sc-noroot/ci-key" 0
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ]; then pass "SC5: no root key file -> refused, nothing written"
  else fail "SC5: the writer ran without the root key" "rc=$SC_RC"; fi
  mkdir -p "$T/sc bad" && printf 'k\n' > "$T/sc bad/ci-key"
  _sc_run unsafe "$T/sc bad/ci-key"
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && grep -qF 'verdict=ssh_config_path_unsafe' "$SR/stdout"; then pass "SC6: a keyfile path with a space -> ssh_config_path_unsafe, nothing written"
  else fail "SC6: an unsafe path reached the config" "rc=$SC_RC"; fi
  _sc_run nopin "$T/sc-nopin/ci-key" 1 ABSENT
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && [ ! -e "$SC_KH" ] && grep -qxF '::error title=git-data-cutover ssh_config::verdict=git_data_host_key_unavailable reason=absent' "$SR/stdout"; then
    pass "SC8: no \$RUNNER_TEMP/git-data.pin -> git_data_host_key_unavailable reason=absent, no known_hosts and no ssh_config written"
  else fail "SC8: the writer ran without the git-data pin" "rc=$SC_RC $(tr '\n' '|' < "$SR/stdout" | sed 's/::/: :/g')"; fi
  _sc_run badpin "$T/sc-badpin/ci-key" 1 "$GD_PIN extra@host"
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && grep -qxF '::error title=git-data-cutover ssh_config::verdict=git_data_host_key_unavailable reason=invalid' "$SR/stdout"; then
    pass "SC9: a malformed git-data pin -> the shared writer refuses, reason=invalid, no ssh_config written"
  else fail "SC9: a malformed git-data pin reached the config" "rc=$SC_RC $(tr '\n' '|' < "$SR/stdout" | sed 's/::/: :/g')"; fi
fi

# Secrets check — the root token's absence is its own verdict.
if [ ! -s "$T/steps/secrets_check.sh" ]; then
  fail "SEC: the secrets check step body was not extracted" "never a pass on zero"
else
  _sec() { env -i PATH=/usr/bin:/bin "$@" bash --noprofile --norc -eo pipefail "$T/steps/secrets_check.sh" > "$T/sec.out" 2>&1; SEC_RC=$?; }
  _sec DOPPLER_TOKEN_PRESENT=true GIT_DATA_ROOT_TOKEN_PRESENT=false
  if [ "$SEC_RC" != 0 ] && grep -qxF '::error title=git-data-cutover secrets::verdict=git_data_root_token_absent' "$T/sec.out"; then
    pass "S10/SEC: an empty DOPPLER_TOKEN_GIT_DATA_ROOT -> verdict=git_data_root_token_absent, step fails (before the bridge)"
  else fail "S10/SEC: an absent root token was not reported" "rc=$SEC_RC $(tr '\n' '|' < "$T/sec.out" | sed 's/::/: :/g')"; fi
  _sec DOPPLER_TOKEN_PRESENT=true GIT_DATA_ROOT_TOKEN_PRESENT=true
  if [ "$SEC_RC" = 0 ] && ! grep -q '::error' "$T/sec.out"; then pass "SEC: both tokens present -> the step passes"
  else fail "SEC: present tokens were refused" "rc=$SEC_RC"; fi
  _sec DOPPLER_TOKEN_PRESENT=false GIT_DATA_ROOT_TOKEN_PRESENT=true
  if [ "$SEC_RC" != 0 ]; then pass "SEC: an absent DOPPLER_TOKEN fails the step"
  else fail "SEC: an absent DOPPLER_TOKEN passed"; fi
fi

# Teardown — EXECUTED with PATH stubs for sudo/iptables/shred (kill is the builtin, aimed at a
# real sleeping fixture process). The key file and the ssh_config must be gone afterwards.
mkdir -p "$T/tdbin" || { printf 'FAIL SETUP: mkdir tdbin\n' >&2; exit 1; }
cat > "$T/tdbin/sudo" <<'SHIM'
#!/usr/bin/env bash
exec "$@"
SHIM
cat > "$T/tdbin/iptables" <<'SHIM'
#!/usr/bin/env bash
printf 'iptables %s\n' "$*" >> "$TD_LOG"
SHIM
cat > "$T/tdbin/shred" <<'SHIM'
#!/usr/bin/env bash
printf 'shred %s\n' "$*" >> "$TD_LOG"
[ "${1:-}" = -u ] && [ -n "${2:-}" ] && rm -f -- "$2"
SHIM
chmod +x "$T/tdbin/sudo" "$T/tdbin/iptables" "$T/tdbin/shred"
case_teardown() { # <teardown-body-file>
  local body="$1" pid
  TDR="$T/td-run"
  assert_fixture_dir "$TDR"
  rm -rf "$TDR"; mkdir -p "$TDR/rt" || { printf 'FAIL SETUP: mkdir td\n' >&2; exit 1; }
  [ -s "$body" ] || { TD_DETAIL="no teardown body extracted"; return 1; }
  printf 'k\n' > "$TDR/rt/gd-root-key"; printf 'c\n' > "$TDR/rt/gd-ssh-config"; printf 'ci\n' > "$TDR/ci-key"; : > "$TDR/log"
  printf 'kh\n' > "$TDR/rt/gd-known-hosts"; printf 'pin\n' > "$TDR/rt/git-data.pin"; chmod 0444 "$TDR/rt/gd-known-hosts" "$TDR/rt/git-data.pin"
  sleep 60 & pid=$!
  env -i PATH="$T/tdbin:/usr/bin:/bin" HOME="$TDR" RUNNER_TEMP="$TDR/rt" TD_LOG="$TDR/log" SERVER_IP=10.0.1.10 \
    CLOUDFLARED_PID="$pid" CI_SSH_KEYFILE="$TDR/ci-key" bash --noprofile --norc -e "$body" > "$TDR/stdout" 2>&1
  TD_RC=$?
  local alive=1; kill -0 "$pid" 2>/dev/null || alive=0
  [ "$alive" = 1 ] && kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  TD_DETAIL="rc=$TD_RC alive=$alive files=[$(ls -A "$TDR/rt" | tr '\n' ' ')] log=[$(tr '\n' '|' < "$TDR/log")]"
  [ "$TD_RC" = 0 ] && [ ! -e "$TDR/rt/gd-root-key" ] && [ ! -e "$TDR/rt/gd-ssh-config" ] && [ ! -e "$TDR/ci-key" ] && [ "$alive" = 0 ] \
    && [ ! -e "$TDR/rt/gd-known-hosts" ] && [ ! -e "$TDR/rt/git-data.pin" ] \
    && grep -qxF 'iptables -t nat -D OUTPUT -d 10.0.1.10 -p tcp --dport 22 -j REDIRECT --to-ports 2222' "$TDR/log"
}
if case_teardown "$T/steps/teardown.sh"; then
  pass "TD: the teardown body, executed, removes the root key, the ssh_config, the CI keyfile, the known_hosts and the pin (both 0444), kills cloudflared and deletes the NAT rule"
else fail "TD: the executed teardown left key material or the bridge behind" "$TD_DETAIL"; fi

# ── NB / FZ — the notify body and the finalizer, EXECUTED (#8211 review: the census pinned their SPELLING
# and nothing ran them, so deleting an `exit 1` or inverting a branch left every row green). Both bodies are
# extracted by wf.py; ${{ github.run_id }} is rendered to a constant the way the runner would, the CLI shim
# and the two scripts the finalizer calls are PATH/cwd stubs that log their calls. Every case compares the
# WHOLE $GITHUB_OUTPUT content and the exit code, so a missing, extra or misplaced output write is a red case.
mkdir -p "$T/nbfz" || { printf 'FAIL SETUP: mkdir nbfz\n' >&2; exit 1; }
nb_run() { # <body-file> <MODE> <RESULT> <FINALIZER_RAN> <FREEZE_HELD> <RECOVERY_FAILED> <PROBE_FAILED> [RUN_ID]
  local body="$1" d="$T/nbfz/nb"
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d" || { printf 'FAIL SETUP: mkdir nb\n' >&2; exit 1; }
  : > "$d/out"
  env -i PATH=/usr/bin:/bin RUNNER_TEMP="$d" GITHUB_OUTPUT="$d/out" RUN_ID="${8-12345}" RUN_URL=https://example.invalid/run \
    MODE="$2" RESULT="$3" FINALIZER_RAN="$4" FREEZE_HELD="$5" RECOVERY_FAILED="$6" PROBE_FAILED="$7" \
    bash --noprofile --norc -eo pipefail "$body" > "$d/stdout" 2>&1
  NB_RC=$?
  NB_SUBJ="$(sed -n 's/^subject=//p' "$d/out")"; NB_HTML="$(sed -n 's/^body=//p' "$d/out")"; NB_LINES="$(wc -l < "$d/out")"
  NB_TXT=""; [ -f "$d/notify-body.txt" ] && NB_TXT="$(cat "$d/notify-body.txt")"
  NB_DETAIL="rc=$NB_RC lines=$NB_LINES subject=[$NB_SUBJ]"
}
case_nb() { # <body-file> — every NB row; returns non-zero on the first miss (NB_WHY names it)
  local body="$1"
  NB_WHY=""
  nb_run "$body" flip failure 1 1 "" ""
  [ "$NB_RC" = 0 ] && [ "$NB_LINES" = 2 ] && [[ "$NB_SUBJ" == *"[git-data-cutover flip failure] FREEZE_HELD" ]] && [[ "$NB_TXT" == *"mode=unfreeze"* ]] && [[ "$NB_TXT" == *"--ref main"* ]] \
    && [[ "$NB_TXT" == *"confirm=UNFREEZE-GIT-DATA"* ]] && [[ "$NB_HTML" == *"mode=unfreeze"* ]] || { NB_WHY="NB1 freeze_held: $NB_DETAIL"; return 1; }
  nb_run "$body" flip failure 1 1 1 ""
  [[ "$NB_SUBJ" == *"FREEZE_HELD RECOVERY_FAILED" ]] || { NB_WHY="NB2 both verdicts: $NB_DETAIL"; return 1; }
  nb_run "$body" "" cancelled "" "" "" ""
  [[ "$NB_SUBJ" == *"STATE UNKNOWN" ]] && [[ "$NB_TXT" == *"STATE UNKNOWN"* ]] && [[ "$NB_TXT" == *"mode=unfreeze"* ]] || { NB_WHY="NB3 no verdict, cancelled: $NB_DETAIL"; return 1; }
  nb_run "$body" flip failure 1 "" "" ""
  [[ "$NB_SUBJ" == *"] FAILED" ]] && [[ "$NB_TXT" == *"finalizer ran"* ]] && [[ "$NB_TXT" != *"STATE UNKNOWN"* ]] && [[ "$NB_TXT" != *"mode=unfreeze"* ]] || { NB_WHY="NB4 failed, finalizer ran, nothing stranded: $NB_DETAIL"; return 1; }
  nb_run "$body" proof failure 1 "" "" ""
  [[ "$NB_TXT" == *"read-only"* ]] && [[ "$NB_TXT" != *"STATE UNKNOWN"* ]] || { NB_WHY="NB5 proof: $NB_DETAIL"; return 1; }
  nb_run "$body" rollback failure 1 "" "" 1
  [[ "$NB_SUBJ" == *"PROBE_FAILED" ]] && [[ "$NB_TXT" != *"mode=unfreeze"* ]] || { NB_WHY="NB6 probe failed alone: $NB_DETAIL"; return 1; }
  nb_run "$body" 'x;rm -rf y' failure 1 1 "" ""
  [[ "$NB_SUBJ" == *"[git-data-cutover unknown failure]"* ]] && [ "$NB_LINES" = 2 ] || { NB_WHY="NB7 hostile MODE: $NB_DETAIL"; return 1; }
  nb_run "$body" flip failure 1 1 "" "" '1; echo x'
  [ "$NB_RC" != 0 ] || { NB_WHY="NB8 a non-numeric run id was accepted: $NB_DETAIL"; return 1; }
  return 0
}
if [ ! -s "$T/steps/notify_body.sh" ]; then
  fail "NB: the notify body step was not extracted" "never a pass on zero"
elif case_nb "$T/steps/notify_body.sh"; then
  pass "NB: the notify body, EXECUTED — verdict words and the unfreeze remedy appear exactly when a stranded state is reported, a failed run whose finalizer ran reads as FAILED (not STATE UNKNOWN), no-verdict reads as STATE UNKNOWN, proof says read-only, a hostile MODE or run id cannot add an output line"
else fail "NB: the executed notify body misreported a case" "$NB_WHY"; fi

# Finalizer: cwd = a scratch tree holding stubs at the paths the step calls.
mkdir -p "$T/nbfz/fzbin" || { printf 'FAIL SETUP: mkdir fzbin\n' >&2; exit 1; }
cat > "$T/nbfz/fzbin/doppler" <<'SHIM'
#!/usr/bin/env bash
case "$1 $2" in
  "secrets set") printf 'flagwrite\n' >> "$FZ_LOG"; exit "${STUB_FLAGWRITE_RC:-0}" ;;
  "secrets get") echo stub-value; exit 0 ;;
esac
exit 0
SHIM
chmod +x "$T/nbfz/fzbin/doppler"
fz_run() { # <body-file> <MODE> <UNFREEZE_OUTCOME> <markers: space list> [STUB_ENV...]
  local body="$1" mode="$2" uo="$3" markers="$4" d="$T/nbfz/fz" m; shift 4
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d/rt/cutover-progress" "$d/apps/web-platform/infra" "$d/.github/actions/dispatch-web-redeploy" || { printf 'FAIL SETUP: mkdir fz\n' >&2; exit 1; }
  : > "$d/out"; : > "$d/log"
  for m in $markers; do : > "$d/rt/cutover-progress/$m"; done
  cat > "$d/apps/web-platform/infra/git-data-cutover.sh" <<'STUB'
#!/usr/bin/env bash
printf 'git-data-cutover MODE=%s\n' "${MODE:-}" >> "$FZ_LOG"
exit "${STUB_UNFREEZE_RC:-0}"
STUB
  cat > "$d/.github/actions/dispatch-web-redeploy/track.sh" <<'STUB'
#!/usr/bin/env bash
printf 'track\n' >> "$FZ_LOG"
exit "${STUB_TRACK_RC:-0}"
STUB
  sed 's/\${{ github\.run_id }}/12345/g' "$body" > "$d/finalizer.sh"
  ( cd "$d" && env -i PATH="$T/nbfz/fzbin:/usr/bin:/bin" RUNNER_TEMP="$d/rt" GITHUB_OUTPUT="$d/out" FZ_LOG="$d/log" \
      MODE="$mode" UNFREEZE_OUTCOME="$uo" DOPPLER_TOKEN=x DOPPLER_TOKEN_GIT_DATA_FLAG=y WEB_HOSTS=10.0.1.10 GIT_DATA_SSH=ssh WEB_HOST_PRIVATE_IPS=10.0.1.10 "$@" \
      bash --noprofile --norc -eo pipefail finalizer.sh > "$d/stdout" 2>&1 )
  FZ_RC=$?
  FZ_OUT="$(sort "$d/out" | tr '\n' ' ')"; FZ_LOGTXT="$(tr '\n' '|' < "$d/log")"
  FZ_UNFREEZES="$(grep -c 'MODE=unfreeze' "$d/log" || true)"
  FZ_DETAIL="rc=$FZ_RC out=[$FZ_OUT] calls=[$FZ_LOGTXT]"
}
fz_expect() { # <name> <rc> <outputs sorted, space-terminated> <unfreeze-call-count>
  [ "$FZ_RC" = "$2" ] && [ "$FZ_OUT" = "$3" ] && [ "$FZ_UNFREEZES" = "$4" ] || { FZ_WHY="$1: want rc=$2 out=[$3] unfreezes=$4; got $FZ_DETAIL"; return 1; }
}
case_fz() { # <finalizer-body-file>
  local body="$1"
  FZ_WHY=""
  fz_run "$body" flip skipped "freeze_held flag_written"
  fz_expect "FZ1 flip, clean total unwind" 0 "ran=1 " 1 || return 1
  [[ "$FZ_LOGTXT" == *"flagwrite"* ]] && [[ "$FZ_LOGTXT" == *"track"* ]] || { FZ_WHY="FZ1 the unwind did not write the flag off and redeploy: $FZ_DETAIL"; return 1; }
  fz_run "$body" flip skipped "freeze_held" STUB_UNFREEZE_RC=1
  fz_expect "FZ2 flip, unfreeze fails" 1 "freeze_held=1 ran=1 recovery_failed=1 " 1 || return 1
  fz_run "$body" flip skipped "flag_written" STUB_FLAGWRITE_RC=1
  fz_expect "FZ3 flip, flag-off write fails" 1 "ran=1 recovery_failed=1 " 0 || return 1
  fz_run "$body" flip success "flag_written freeze_held cutover_at_written"
  fz_expect "FZ4 flip, concluded" 0 "ran=1 " 0 || return 1
  fz_run "$body" rollback success "flag_written"
  fz_expect "FZ5 rollback, its own unfreeze succeeded: no second unfreeze, no output" 0 "ran=1 " 0 || return 1
  fz_run "$body" rollback failure "flag_written" STUB_UNFREEZE_RC=1
  fz_expect "FZ6 rollback, unfreeze failed and the retry fails" 1 "freeze_held=1 ran=1 recovery_failed=1 " 1 || return 1
  fz_run "$body" rollback skipped "flag_written"
  fz_expect "FZ6b rollback, unfreeze skipped and the retry succeeds" 0 "ran=1 " 1 || return 1
  fz_run "$body" unfreeze failure ""
  fz_expect "FZ7 unfreeze mode, the step failed: the sentinel may still be held" 0 "freeze_held=1 ran=1 " 0 || return 1
  fz_run "$body" unfreeze success ""
  fz_expect "FZ8 unfreeze mode, clean" 0 "ran=1 " 0 || return 1
  fz_run "$body" proof success ""
  fz_expect "FZ9 proof mode" 0 "ran=1 " 0 || return 1
  fz_run "$body" flip failure ""
  fz_expect "FZ10 flip, nothing to unwind (a precheck failure)" 0 "ran=1 " 0 || return 1
  return 0
}
if [ ! -s "$T/steps/finalizer.sh" ]; then
  fail "FZ: the finalizer step body was not extracted" "never a pass on zero"
elif case_fz "$T/steps/finalizer.sh"; then
  pass "FZ: the finalizer, EXECUTED over 11 mode x outcome x marker cases — freeze_held and recovery_failed are exported only from the failed-unfreeze and failed-unwind branches, a clean unwind or a concluded rollback exports only ran=1 and never re-runs unfreeze, a failed unfreeze MODE exports freeze_held, and the exit code carries RECOVERY_FAILED"
else fail "FZ: the executed finalizer diverged" "$FZ_WHY"; fi

# ── RB — every store-probe word has a runbook row, and every verdict-map row names a live word ──
# Scope: the store and fence probes' verdict and reason words (everything through _store_*). The
# access gate's words and real_cutover_unreconciled do not go through _store_*; they are held to the
# repo-wide emitter check below only. Two independent producers must agree: the script's text, and
# what the unit rows above observed. RB therefore runs AFTER every unit row and BEFORE the mutants:
# the observed set is a snapshot of $T/*.out at this point.
RUNBOOK="$ROOT/knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md"
_rb_script_words() { # <script> — sorted, unique
  local code i
  local -a toks
  code="$(sed -E 's/^[[:space:]]*#.*$//' "$1")"
  { printf '%s\n' "$code" | { grep -oE '_store_(refuse|emit) [^;|]*' || true; } | while read -ra toks; do
      for i in 2 4; do if [[ "${toks[$i]:-}" =~ ^[a-z0-9_]+$ ]]; then printf '%s\n' "${toks[$i]}"; fi; done
    done
    printf '%s\n' "$code" | sed -nE 's/^[[:space:]]+[0-9]+\) reason=([a-z0-9_]+) ;;$/\1/p'
  } | { grep -vxE 'ok|' || true; } | LC_ALL=C sort -u
}
_rb_observed_lines() { cat "$T"/*.out 2>/dev/null | sed -nE 's/^\[git-data-cutover\] STORE probe=([a-z-]+) verdict=([a-z0-9_]+)( rc=[0-9]+)?( reason=([a-z0-9_]+))?$/\1 \2 \5/p'; }
_rb_observed_lines | cut -d' ' -f2- | tr ' ' '\n' | { grep -vxE 'ok|' || true; } | LC_ALL=C sort -u > "$T/rb.observed"
_rb_observed_lines | awk '$2 != "ok" { print $1, $2 }' | LC_ALL=C sort -u > "$T/rb.pairs"
_rb_map() { awk '/^## Verdict map$/ { m = 1; next } m && /^## / { exit } m' "$1"; }
# case_rb <script> <runbook> [observed-words-file] — four independent checks, each with its own mutant:
#   sw=ow     the script's words equal the observed words (an extractor miss, or a word no row emits)
#   miss      every script word appears in the verdict map
#   extra     every verdict=/reason= word on ANY map row is emitted by something in the repo (a stale
#             row such as a retired verdict fails here whatever spelling the row uses)
#   pairs     every probe=P verdict=V pair a map row names was observed from the script
case_rb() {
  local sw ow map w p v miss="" extra="" badpair="" pairs
  sw="$(_rb_script_words "$1")"; ow="$(cat "${3:-$T/rb.observed}")"; map="$(_rb_map "$2")"
  for w in $sw; do grep -qE "(^|[^A-Za-z0-9_])${w}([^A-Za-z0-9_]|\$)" <<< "$map" || miss="$miss $w"; done
  for w in $(printf '%s\n' "$map" | { grep -E '^\|' || true; } \
      | { grep -oE 'verdict=[a-z0-9_]+|reason=<?[a-z0-9_]+(\\?\|[a-z0-9_]+)*' || true; } \
      | sed -E 's/^(verdict|reason)=<?//; s/\\//g' | tr '|' '\n' | { grep -vxE 'ok|' || true; } | LC_ALL=C sort -u); do
    grep -qxF -- "$w" <<< "$sw" && continue
    git -C "$ROOT" grep -qwF -- "$w" -- ':!*.md' ':!*.test.*' ':!knowledge-base' 2>/dev/null || extra="$extra $w"
  done
  pairs="$(printf '%s\n' "$map" | { grep -oE 'probe=[a-z-]+ verdict=[a-z0-9_]+' || true; } | sed -E 's/^probe=//; s/ verdict=/ /' | LC_ALL=C sort -u)"
  while read -r p v; do
    [ -n "$p" ] || continue
    grep -qxF -- "$p $v" "$T/rb.pairs" || badpair="$badpair $p:$v"
  done <<< "$pairs"
  RB_DETAIL="script=$(wc -w <<< "$sw") observed=$(wc -w <<< "$ow") map-pairs=$(grep -c . <<< "$pairs") missing-from-map=[${miss# }] not-emitted=[${extra# }] unobserved-pairs=[${badpair# }] diff=[$(diff <(printf '%s\n' "$sw") <(printf '%s\n' "$ow") | grep -E '^[<>]' | tr '\n' ' ')]"
  [ -n "$sw" ] && [ "$sw" = "$ow" ] && [ -n "$pairs" ] && [ -z "$miss" ] && [ -z "$extra" ] && [ -z "$badpair" ]
}
[ -f "$RUNBOOK" ] || { printf 'FAIL SETUP: %s not found\n' "$RUNBOOK" >&2; exit 1; }
if case_rb "$SCRIPT" "$RUNBOOK"; then pass "RB: the script's store-probe words equal the observed words, each has a verdict-map row, every map row's word has an emitter, and every probe/verdict pair the map names was observed ($RB_DETAIL)"
else fail "RB: the store-probe words, the observed words and the runbook verdict map disagree" "$RB_DETAIL"; fi

# ── MUTANTS ───────────────────────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its named case RED)"
# shellcheck disable=SC2016  # sed programs are data
{
# G2 row 1 — accept an empty findmnt source.
if mutate g2-empty-source "$SCRIPT" 2 's#^  \[\[ "\$GD_CAPTURED" =~ \^/dev/\[A-Za-z0-9/_.-\]\+\$ \]\] \|\| _store_refuse store-mounted old_store_unmounted$#  [[ "$GD_CAPTURED" =~ ^(/dev/[A-Za-z0-9/_.-]+)?$ ]] || _store_refuse store-mounted old_store_unmounted#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g2-empty-source case_unmounted_empty
fi
# G2 row 2 is Guard 1 row 2 (g1-2-no-dispatch) below: refuse_if_not_on_mapper deleted from main.
# G2 row 3 — treat a failed count probe as zero.
if mutate g2-failed-count-zero "$SCRIPT" 2 's#^  \[ "\$rc" -eq 0 \] \|\| _store_refuse store-empty probe_failed "\$rc"$#  [ "$rc" -eq 0 ] || GD_CAPTURED=0#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g2-failed-count-zero case_probe_error
fi
# G2 row 4 — reintroduce the bulk rsync function of the deleted body.
if mutate g2-bulk-rsync "$SCRIPT" 1 's#^main\(\) \{$#bulk_rsync() { gd_capture "^$" "rsync -aHAX --delete /mnt/git-data/repositories/ /mnt/git-data-luks/repositories/"; }\n&#'; then
  mutant_red g2-bulk-rsync case_verb_census "$MUTANT"
fi
# G5 row 1 — return the value without the pattern check (both the multi-line and the regex arm).
if mutate g5-no-pattern "$SCRIPT" 4 "s#^    \\*\\\$'\\\\n'\\*\\) return 96 ;;\$#    *NEVER*) return 96 ;;#; s#^  if ! \\[\\[ \"\\\$val\" =~ \\\$pat \\]\\]; then\$#  if false; then#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-no-pattern case_line2
fi
# G5 row 2 — drop the timeout wrapper.
if mutate g5-no-timeout "$SCRIPT" 2 's#^  val="\$\(timeout 30 #  val="$(#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-no-timeout case_hang
fi
# G5 row 3 — echo the captured value in the mismatch branch.
if mutate g5-echo-value "$SCRIPT" 2 "s#^    \\*\\\$'\\\\n'\\*\\) return 96 ;;\$#    *\$'\\\\n'*) printf '%s\\\\n' \"\$val\"; return 96 ;;#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-echo-value case_line2
fi
# G5 row 4 — a raw capture of the invocation outside gd_capture.
if mutate g5-raw-capture "$SCRIPT" 1 's#^  \[ -n "\$STORE_SOURCE" \] \|\| _store_refuse store-on-mapper probe_failed$#  local -a inv; read -ra inv <<< "${GIT_DATA_SSH:-}"; STORE_SOURCE="$("${inv[@]}" "$GIT_DATA_HOST" findmnt -no SOURCE /mnt/git-data)"\n&#'; then
  mutant_red g5-raw-capture case_capture_census "$MUTANT"
fi
# G7 row 1 — re-add a rollback input.
if mutate g7-rollback-input "$WF" 2 's#^      confirm:$#&\n      rollback:\n        type: boolean#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-g7.tsv" 2>&1
  mutant_red g7-rollback-input wf_row "$T/mut/wf-g7.tsv" "G7/AC9: workflow_dispatch inputs"
fi
# G7 row 2 — refuse only ROLLBACK/DRY_RUN: drop the CONFIRM_WIPE arm.
if mutate g7-no-wipe-arm "$SCRIPT" 1 '/^  \[ "\$\{CONFIRM_WIPE:-0\}" = 0 \] \|\| bad=/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g7-no-wipe-arm case_refuse mwipe CONFIRM_WIPE=1
fi
# G7 row 3 — REORDER: the refusal after access_gate (the proof branch's first remote call).
if mutate g7-reorder "$SCRIPT" 2 '/^  refuse_legacy_modes$/d; s#^      access_gate$#&\n      refuse_legacy_modes#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g7-reorder case_refuse mreorder DRY_RUN=0
fi
# G6 row 1 — rename the cutover workflow's group.
if mutate g6-group-rename "$WF" 2 's#^  group: git-data-state$#  group: git-data-cutover#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-g6.tsv" 2>&1
  mutant_red g6-group-rename wf_row "$T/mut/wf-g6.tsv" "G6: workflow-level concurrency group"
fi
# C1 row — report a transport failure of the mount read as a store state.
if mutate c1-transport-as-unmounted "$SCRIPT" 2 's#^    \*\) _store_refuse store-mounted probe_failed "\$rc" ;;$#    *) _store_refuse store-mounted old_store_unmounted "$rc" ;;#'; then
  CASE_SCRIPT="$MUTANT" mutant_red c1-transport-as-unmounted case_mount_transport
fi
# C3 row 1 is Guard 2 row 13 (g2v-13-no-target): the count's mount check.
# C3 row 2 — count a missing repositories dir as 0.
if mutate c3-missing-as-zero "$SCRIPT" 2 's#then exit 7; fi#then echo 0; exit 0; fi#'; then
  CASE_SCRIPT="$MUTANT" mutant_red c3-missing-as-zero case_missing_repos
fi
# C7 row 1 — continue-on-error on the key fetch.
if mutate c7-key-fetch-coe "$WF" 1 's#^        id: key_fetch$#&\n        continue-on-error: true#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-c7a.tsv" 2>&1
  mutant_red c7-key-fetch-coe wf_row "$T/mut/wf-c7a.tsv" "WF-gating:"
fi
# C7 row 2 — the confirm token check never runs.
if mutate c7-confirm-if-false "$WF" 1 's#^        id: confirm$#&\n        if: false#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-c7b.tsv" 2>&1
  mutant_red c7-confirm-if-false wf_row "$T/mut/wf-c7b.tsv" "WF-gating:"
fi
# C7 row 3 — teardown only on success.
if mutate c7-teardown-success "$WF" 2 '/^      - name: Tear down cloudflared SSH bridge$/{n;s#^        if: always\(\)$#        if: success()#}'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-c7c.tsv" 2>&1
  mutant_red c7-teardown-success wf_row "$T/mut/wf-c7c.tsv" "WF-gating:"
fi
# C7 row 4 — teardown stops shredding the ssh_config (content rows are grep-free here: executed).
if mutate c7-teardown-keeps-config "$WF" 2 's#^            shred -u "\$RUNNER_TEMP/gd-ssh-config" 2>/dev/null \|\| true$#            true#'; then
  rm -f "$T/mut/teardown.sh"
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-c7d.tsv" 2>&1
  # The mutant's teardown body must have been extracted, or the case goes RED for the wrong reason.
  if [ -s "$T/mut/teardown.sh" ]; then mutant_red c7-teardown-keeps-config case_teardown "$T/mut/teardown.sh"
  else fail "M-c7-teardown-keeps-config: no teardown body was extracted from the mutant" "$(head -c 300 "$T/mut/wf-c7d.tsv")"; fi
fi
# Guard 2 / Guard 3 (#8211 plan) — the notify-failure job, its outputs, and the rollback probe.
# Each row edits a COPY of the workflow and requires the NAMED census row to go RED; wf_row returns 1
# only when the row is present and not ok, so a crashed YAML leg can never read as RED.
# g2n-N rows cover the notify path (Guard 2); g3p-N rows the probe step's gating (P3).
g2n_row() { # <name> <diff-lines> <sed -E program> <census-row prefix>
  local name="$1" want="$2" expr="$3" prefix="$4"
  if mutate "$name" "$WF" "$want" "$expr"; then
    python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-$name.tsv" 2>&1
    mutant_red "$name" wf_row "$T/mut/wf-$name.tsv" "$prefix"
  fi
}
# 1 — the notify job disappears (renamed away): the two-job census goes RED.
g2n_row g2n-1-no-notify-job 2 's#^  notify-failure:$#  notify-failed:#' "WF-jobs:"
# 2 — drop always() from its if: (an implicit success() makes the job unreachable on every run it exists for).
g2n_row g2n-2-no-always 2 's#^(    if: )always\(\) && #\1#' "N-if:"
# 3 — failure() only: a cancelled run and a failed rollback probe no longer notify.
g2n_row g2n-3-failure-only 2 's#^    if: always\(\) && \(needs\.cutover\.result.*$#    if: always() \&\& failure()#' "N-if:"
# 4 — the notify job joins the reviewer-gated environment (credential scope).
g2n_row g2n-4-environment 1 's#^  notify-failure:$#&\n    environment: web-platform-infra-apply#' "N-jobkeys:"
# 5 — bind the flag-write token in the notify job, after a compliant RESEND_API_KEY binding.
g2n_row g2n-5-flag-token 1 's#^          SUBJECT: \$\{\{ steps\.body\.outputs\.subject \}\}$#&\n          DOPPLER_TOKEN_GIT_DATA_FLAG: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_FLAG }}#' "N-secrets:"
# 6 — interpolate a free-text input into the notification body.
g2n_row g2n-6-input-in-body 1 's#^          RUN_ID: \$\{\{ github\.run_id \}\}$#&\n          LINEAGE: ${{ inputs.lineage }}#' "N-body:"
# 8 — widen the condition to != 'success' (a skipped run would email).
g2n_row g2n-8-not-success 2 's#^    if: always\(\) && \(needs\.cutover\.result.*$#    if: always() \&\& needs.cutover.result != '"'"'success'"'"'#' "N-if:"
# 9 — the probe step no longer runs after a rollback.
g2n_row g3p-1-probe-flip-only 2 "/^        id: probe\$/{n;s#^        if: \(steps\.confirm\.outputs\.mode == 'flip' \|\| steps\.confirm\.outputs\.mode == 'rollback'\) && #        if: steps.confirm.outputs.mode == 'flip' \&\& #}" "N-probe:"
# 10 — the probe step may fail without failing the run (the CPO condition would be unenforced).
g2n_row g3p-2-probe-coe 1 's#^        id: probe$#&\n        continue-on-error: true#' "N-probe:"
# 11 — executed-behaviour mutants: each edits ONE line of the finalizer or the notify body and the EXECUTED
# NB/FZ cases (not a spelling row) must go RED. exec_row extracts the mutant's bodies with wf.py and runs
# case_fz / case_nb over them.
exec_row() { # <name> <diff-lines> <sed -E program> <fz|nb>
  local name="$1" want="$2" expr="$3" kind="$4" sd
  if mutate "$name" "$WF" "$want" "$expr"; then
    sd="$T/mut/steps-$name"; mkdir -p "$sd"
    python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$sd" > "$T/mut/wf-$name.tsv" 2>&1
    if [ "$kind" = fz ] && [ -s "$sd/finalizer.sh" ]; then mutant_red "$name" case_fz "$sd/finalizer.sh"
    elif [ "$kind" = nb ] && [ -s "$sd/notify_body.sh" ]; then mutant_red "$name" case_nb "$sd/notify_body.sh"
    else fail "M-$name: no $kind body was extracted from the mutant" "$(head -c 200 "$T/mut/wf-$name.tsv")"; fi
  fi
}
exec_row fz1-recovery-exit-deleted 2 '/echo "recovery_failed=1" >> "\$GITHUB_OUTPUT"/{n;s#^( +)exit 1$#\1:#}' fz
exec_row fz2-freeze-marker-inverted 2 's#if \[\[ -f "\$prog/freeze_held" \]\]; then#if [[ ! -f "$prog/freeze_held" ]]; then#' fz
exec_row fz3-rollback-always-retries 2 's#if \[\[ "\$MODE" == "rollback" && "\$\{UNFREEZE_OUTCOME:-\}" == "success" \]\]; then#if [[ "$MODE" == "rollback" \&\& "${UNFREEZE_OUTCOME:-}" == "never" ]]; then#' fz
exec_row fz4-clean-unwind-exports-freeze-held 1 's#^(              echo "finalizer: freeze cleared, gc\.timer restarted")$#\1\n              echo "freeze_held=1" >> "$GITHUB_OUTPUT"#' fz
exec_row fz5-ran-output-deleted 1 '/^          echo "ran=1" >> "\$GITHUB_OUTPUT"$/d' fz
exec_row nb1-state-unknown-inverted 2 's#^          if \[ -z "\$words" \]; then$#          if [ -n "$words" ]; then#' nb
exec_row nb2-remedy-line-dropped 2 "s#^            if \[ -n \"\\\$remedy\" \]; then printf '%s\\\\n' \"\\\$remedy\"; fi\$#            :#" nb
exec_row nb3-subject-output-dropped 2 's#^            echo "subject=\$\{subject\}"$#            :#' nb
exec_row nb4-unknown-without-remedy 2 's#^              remedy_needed=1$#              :#' nb
# 12 — census-level mutants over the notify wiring.
g2n_row g2n-9-started-clause-dropped 2 "s# \\&\\& needs\\.cutover\\.outputs\\.started != 'false'\$##" "N-if:"
g2n_row g2n-10-workflow-env-secret 1 's#^env:$#&\n  LEAK: ${{ secrets.RESEND_API_KEY }}#' "N-secrets-form:"
g2n_row g2n-11-cutover-job-continue-on-error 1 's#^    timeout-minutes: 120$#&\n    continue-on-error: true#' "N-jobkeys:"
g2n_row g2n-12-event-json-in-body-env 1 's#^          RUN_ID: \$\{\{ github\.run_id \}\}$#&\n          EV: ${{ toJSON(github.event) }}#' "N-body:"
g2n_row g2n-13-email-step-not-best-effort 1 '/^        id: email$/{n;/continue-on-error: true/d}' "N-order:"
g2n_row g2n-14-body-id-renamed 2 's#^        id: body$#        id: bodz#' "N-refs:"
# H4 (#7226) — host-identity classifier rows.
# HK-M1 — drop the alg branch: an algorithm mismatch falls through to failed/unknown.
if mutate hk-m1-no-alg "$SCRIPT" 1 '/^  elif \[ "\$1" = 255 \] && grep -qE .\^Unable to negotiate with /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m1-no-alg case_hk_alg
fi
# HK-M2 — drop the unknown branch: an empty known_hosts reads as a changed key.
if mutate hk-m2-no-unknown "$SCRIPT" 1 '/^  elif \[ "\$1" = 255 \] && grep -qE .\^No \[A-Za-z0-9-\]\+ host key is known for /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m2-no-unknown case_hk_unknown
fi
# HK-M3 — the changed branch no longer requires ssh's own exit code 255.
if mutate hk-m3-no-rc-gate "$SCRIPT" 2 's#^  elif \[ "\$1" = 255 \] && (grep -qE .\^\(@ \+WARNING)#  elif \1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m3-no-rc-gate case_hk_rc1
fi
# HK-M4 — the changed pattern loses its line anchor.
if mutate hk-m4-unanchored "$SCRIPT" 2 "s#grep -qE '\\^\\(@ \\+WARNING#grep -qE '(@ +WARNING#"; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m4-unanchored case_hk_midline
fi
# HK-M5 — the H4 branches move BELOW auth_refused-style free matching: a host-key failure whose
# text also carries a Permission denied line must still be host_key_mismatch.
if mutate hk-m5-perm-first "$SCRIPT" 1 's#^  if \[ "\$1" = 124 \]; then echo "failed timeout"$#&\n  elif grep -qF "Host key verification failed" <<< "$t"; then echo "failed auth_refused"#'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m5-perm-first case_hk_changed
fi
# HK-M6 — the unknown pattern loses its line anchor: a banner line naming the phrase picks it.
if mutate hk-m6-unknown-unanchored "$SCRIPT" 2 "s#grep -qE '\\^No \\[A-Za-z0-9-\\]#grep -qE 'No [A-Za-z0-9-]#"; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m6-unknown-unanchored case_hk_midline
fi
# HK-M7 — the unknown branch no longer requires ssh's own exit code 255.
if mutate hk-m7-unknown-no-rc-gate "$SCRIPT" 2 's#^  elif \[ "\$1" = 255 \] && (grep -qE .\^No )#  elif \1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m7-unknown-no-rc-gate case_hk_rc1_unknown
fi
# HK-M8 — the alg branch no longer requires ssh's own exit code 255.
if mutate hk-m8-alg-no-rc-gate "$SCRIPT" 2 's#^  elif \[ "\$1" = 255 \] && (grep -qE .\^Unable to negotiate)#  elif \1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m8-alg-no-rc-gate case_hk_rc1_alg
fi
# HK-M9 — the alg pattern loses its line anchor.
if mutate hk-m9-alg-unanchored "$SCRIPT" 2 "s#grep -qE '\\^Unable to negotiate#grep -qE 'Unable to negotiate#"; then
  CASE_SCRIPT="$MUTANT" mutant_red hk-m9-alg-unanchored case_hk_midline
fi

# Fence (#8101) mutants. M6 and M9 were cut in plan review; the rows below follow the review round.
# M1 — own dispatch: the probe is never called.
if mutate f-m1-no-call "$SCRIPT" 1 '/^      refuse_if_fence_not_intact$/d'; then
  mutant_red f-m1-no-call case_main_order "$MUTANT"
fi
# M2 — the probe "passes" without reading anything.
if mutate f-m2-no-read "$SCRIPT" 2 "/^refuse_if_fence_not_intact\\(\\) \\{/,/^\\}/s#^  gd_capture '\\^ok\\\$' .*\$#  GD_CAPTURED=ok#"; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m2-no-read case_fence r10 "fence_not_intact reason=hooks_dir_absent"
fi
# M3 — second member after a compliant first: drop the executable test on pre-receive.
if mutate f-m3-no-exec-test "$SCRIPT" 2 's#^    '"'"'\[ -f "\$p" \] && \[ -x "\$p" \] \|\| exit 12'"'"'$#    '"'"'[ -f "$p" ] || exit 12'"'"'#'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m3-no-exec-test case_fence_noexec
fi
# M4 — the ownership literal drifts from the bootstrap's.
if mutate f-m4-mode-770 "$SCRIPT" 2 's#^(    '"'"'\[ "\$oh" = "root:git )750#\1770#'; then
  mutant_red f-m4-mode-770 case_fence_parity "$MUTANT"
fi
# M4b — a LOOSER alternative beside the exact literal, on the same line (a line count cannot see it).
if mutate f-m4b-loosened "$SCRIPT" 2 's#^(    '"'"')(\[ "\$oh" = "root:git 750" \] \|\| exit 11)#\1[ "$oh" = "root:git 777" ] || \2#'; then
  mutant_red f-m4b-loosened case_fence_parity "$MUTANT"
fi
# M5 — a named refusal is swallowed.
if mutate f-m5-swallow "$SCRIPT" 2 's#^  \[ -z "\$reason" \] \|\| _store_refuse fence-shape fence_not_intact "" "\$reason"$#  [ -z "$reason" ] || true#'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m5-swallow case_fence r10 "fence_not_intact reason=hooks_dir_absent"
fi
# M7 / M12 — the store-source comparison of the hooks dir / of pre-receive is deleted.
if mutate f-m7-no-dir-source "$SCRIPT" 1 '/^    '"'"'s=\$\(findmnt -no SOURCE -T "\$h"\)/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m7-no-dir-source case_fence_full "$_FFULL" "fence_not_intact reason=hooks_wrong_source" SHIM_FINDMNT_TH=/dev/nvme1n1
fi
if mutate f-m12-no-hook-source "$SCRIPT" 1 '/^    '"'"'s=\$\(findmnt -no SOURCE -T "\$p"\)/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m12-no-hook-source case_fence_full "$_FFULL" "fence_not_intact reason=hooks_wrong_source" SHIM_FINDMNT_TP=/dev/nvme1n1
fi
# M8 — REORDER: the probe runs before the mount probe.
if mutate f-m8-reorder "$SCRIPT" 2 '/^      refuse_if_fence_not_intact$/d; s#^      refuse_if_unmounted$#      refuse_if_fence_not_intact\n&#'; then
  mutant_red f-m8-reorder case_main_order "$MUTANT"
fi
# M10 — the hooksPath expectation derived from the probed root, not the serving path.
if mutate f-m10-sp-from-root "$SCRIPT" 2 "s#^  printf -v qsp '%q' \"\\\$serving\"\$#  printf -v qsp '%q' \"\$root/hooks\"#"; then
  mutant_red f-m10-sp-from-root case_fence_params "$MUTANT"
fi
# M11 — an instrument failure (remote 16) rendered as a store-state reason.
if mutate f-m11-16-as-reason "$SCRIPT" 1 's#^    15\) reason=hooks_wrong_source ;;$#    16) reason=hook_owner ;;\n&#'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m11-16-as-reason case_fence r16 "probe_failed rc=16"
fi
# M13 — git's own permission check is dropped (root's -x stands in for the git user's).
if mutate f-m13-no-git-exec "$SCRIPT" 1 '/^    '"'"'runuser -u git -- test -r /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m13-no-git-exec case_fence_full "$_FFULL" "fence_not_intact reason=hook_not_runnable_by_git" SHIM_RUNUSER_RC=1
fi
# M13b — runuser's own failure reads as the git user being unable to run the hook.
if mutate f-m13b-runuser-broken "$SCRIPT" 1 '/^    '"'"'runuser -u git -- true /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m13b-runuser-broken case_fence_full "$_FFULL" "probe_failed rc=16" SHIM_RUNUSER_BROKEN=1
fi
# M14 — the transport wrapper's pin is no longer read.
if mutate f-m14-no-pin "$SCRIPT" 1 '/^    "grep -qxF -- \$qhd /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m14-no-pin case_fence_nopin
fi
# M15 — the parent-writability check is dropped.
if mutate f-m15-no-parent "$SCRIPT" 1 '/^    '"'"'case "\$pp" in /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m15-no-parent case_fence_full "$_FFULL" "fence_not_intact reason=hooks_parent_writable" SHIM_STAT_PARENT='root 775'
fi
# M16 — the answer anchor loosened: an empty exit-0 answer would read as ok.
if mutate f-m16-loose-anchor "$SCRIPT" 2 "/^refuse_if_fence_not_intact\\(\\) \\{/,/^\\}/s#^  gd_capture '\\^ok\\\$' #  gd_capture '.*' #"; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m16-loose-anchor case_fence empty "probe_failed rc=96"
fi
# M17 — a hardcoded default source instead of the one the mount probe accepted.
if mutate f-m17-fixed-source "$SCRIPT" 2 's#src="\$\{2-\$STORE_SOURCE\}"#src="${2-/dev/mapper/git-data}"#'; then
  CASE_SCRIPT="$MUTANT" mutant_red f-m17-fixed-source case_map_alt
fi
# M18 — an empty passed argument silently defaults (the ${1:- form).
if mutate f-m18-empty-defaults "$SCRIPT" 2 's#local root="\$\{1-\$OLD_ROOT\}"#local root="${1:-$OLD_ROOT}"#'; then
  if _fence_lib "$MUTANT"; then mutant_red f-m18-empty-defaults case_fence_arg arg_root "" ""
  else fail "M-f-m18-empty-defaults: the mutant's probe could not be extracted" "$F16_DETAIL"; fi
  _fence_lib "$SCRIPT" || fail "M-f-m18-empty-defaults: could not restore the pristine extraction" "$F16_DETAIL"
fi
# H-a (harness) — the shim's fence arm always answers ok: the negative rows must go RED, so
# they are driven by the shim mode, not by the script's text.
if mutate f-ha-shim-always-ok "$BIN/ssh" 2 's#^    case "\$\{SHIM_FENCE:-ok\}" in$#    case ok in#'; then
  mkdir -p "$T/binha" && cp "$BIN"/* "$T/binha/" && cp "$MUTANT" "$T/binha/ssh" && chmod +x "$T/binha/ssh" \
    || { printf 'FAIL SETUP: harness mutant bin\n' >&2; exit 1; }
  BIN="$T/binha" mutant_red f-ha-shim-always-ok case_fence r10 "fence_not_intact reason=hooks_dir_absent"
fi
# _harness_bin <name> <shim> — a copy of $BIN whose <shim> is $MUTANT; prints the directory.
_harness_bin() {
  local d="$T/bin-$1"
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d" && cp "$BIN"/* "$d/" && cp "$MUTANT" "$d/$2" && chmod +x "$d/$2" \
    || { printf 'FAIL SETUP: harness mutant bin %s\n' "$1" >&2; exit 1; }
  printf '%s' "$d"
}
# Guard 1 (ADR-239 D1) — the store is served by the configured LUKS mapper.
# G1-1 — polarity reverted.
if mutate g1-1-polarity "$SCRIPT" 2 's#^  \[ "\$STORE_SOURCE" = "\$LUKS_MAPPER" \] \|\| _store_refuse store-on-mapper store_not_on_mapper$#  [ "$STORE_SOURCE" != "$LUKS_MAPPER" ] || _store_refuse store-on-mapper store_not_on_mapper#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-1-polarity case_not_mapper
fi
# G1-2 — own dispatch: the probe is never called (the re-anchored G2 row 2).
if mutate g1-2-no-dispatch "$SCRIPT" 1 '/^      refuse_if_not_on_mapper$/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-2-no-dispatch case_not_mapper
fi
# G1-3 — second member: the equality loosened to a prefix match.
if mutate g1-3-prefix "$SCRIPT" 2 's#^  \[ "\$STORE_SOURCE" = "\$LUKS_MAPPER" \] \|\| (_store_refuse store-on-mapper store_not_on_mapper)$#  [[ $STORE_SOURCE == /dev/mapper/* ]] || \1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-3-prefix case_map_pre
fi
# G1-4 — REORDER: the on-mapper call after the store session.
if mutate g1-4-reorder "$SCRIPT" 2 '/^      refuse_if_not_on_mapper$/d; s#^      refuse_if_store_unverified_or_not_empty$#&\n      refuse_if_not_on_mapper#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-4-reorder case_ord
fi
# G1-5 — the refusal swallowed into an emit.
if mutate g1-5-swallow "$SCRIPT" 2 's#^(  \[ "\$STORE_SOURCE" = "\$LUKS_MAPPER" \] \|\| )_store_refuse (store-on-mapper store_not_on_mapper)$#\1_store_emit \2#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-5-swallow case_not_mapper
fi
# G1-6 — the arg_mapper check deleted.
if mutate g1-6-no-arg-mapper "$SCRIPT" 1 '/^  \[\[ "\$LUKS_MAPPER" =~ /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g1-6-no-arg-mapper case_arg_mapper_nl
fi
# G1-H (harness) — the ssh shim's canonical source reverted to a plaintext device: AC2 must go RED,
# which proves the canonical input is the mapper.
case_ac2_run() { run_case ac2h "${KEYED[@]}"; case_ac2_clear; }
if mutate g1-h-shim-plain "$BIN/ssh" 2 's#case "\$\{SHIM_FINDMNT:-mapper\}" in#case "${SHIM_FINDMNT:-plain}" in#'; then
  _hb="$(_harness_bin g1h ssh)"; assert_fixture_dir "$_hb"
  BIN="$_hb" mutant_red g1-h-shim-plain case_ac2_run
fi

# Config — every configurable path is checked before anything is printed or dialed.
# CFG-1 — the check runs after the access gate: a config fault would dial first.
if mutate cfg-1-after-access "$SCRIPT" 2 '/^      refuse_if_config_unsafe$/d; s#^      access_gate$#&\n      refuse_if_config_unsafe#'; then
  CASE_SCRIPT="$MUTANT" mutant_red cfg-1-after-access case_arg_root
fi
# CFG-2 / CFG-3 / CFG-4 — one check deleted each.
if mutate cfg-2-no-arg-root "$SCRIPT" 1 '/^  \[\[ "\$OLD_ROOT" =~ .* arg_root$/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red cfg-2-no-arg-root case_arg_root
fi
if mutate cfg-3-no-arg-marker "$SCRIPT" 1 '/^  \[\[ "\$STORE_VERIFIED" =~ /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red cfg-3-no-arg-marker case_arg_marker
fi
if mutate cfg-4-no-arg-subdir "$SCRIPT" 1 '/^  \[\[ "\$REPO_SUBDIR" =~ /d'; then
  CASE_SCRIPT="$MUTANT" mutant_red cfg-4-no-arg-subdir case_arg_subdir
fi

# Guard 2 (ADR-239 D3) — a pass is backed by the bootstrap's verified-store evidence, and the count
# is read in the same session. Every row but the dispatch rows is scoped to the function's range.
_G2R='/^refuse_if_store_unverified_or_not_empty\(\) \{/,/^\}/'
# G2-1 — own dispatch: the session is never run.
if mutate g2v-1-no-dispatch "$SCRIPT" 1 '/^      refuse_if_store_unverified_or_not_empty$/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-1-no-dispatch case_v21
fi
# G2-2 — the session "passes" without reading.
if mutate g2v-2-no-read "$SCRIPT" 2 "${_G2R}s#^  gd_capture '\\^\\[0-9\\]\\+\\\$' .*\$#  GD_CAPTURED=0#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-2-no-read case_v22
fi
# G2-3 — second member after a compliant first: the marker equality dropped, presence kept.
if mutate g2v-3-no-equality "$SCRIPT" 1 "${_G2R}{/^    '\\[ \"\\\$m\" = \"\\\$fu\" \\] \\|\\| exit 22'\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-3-no-equality case_vx_mismatch
fi
# G2-4 — the freeze element dropped.
if mutate g2v-4-no-freeze "$SCRIPT" 1 "${_G2R}{/^    '\\[ ! -e \"\\\$fz\" \\] \\|\\| exit 23'\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-4-no-freeze case_vx_frozen
fi
# G2-5a — empty equals empty: the UUID presence check dropped.
if mutate g2v-5a-no-uuid-check "$SCRIPT" 1 "${_G2R}{/^    '\\[ -n \"\\\$fu\" \\] \\|\\| exit 24'\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-5a-no-uuid-check case_vx_nouuid
fi
# G2-5b — the non-empty test dropped alone.
if mutate g2v-5b-no-size "$SCRIPT" 2 "${_G2R}s#^    '\\[ -f \"\\\$mk\" \\] && \\[ -s \"\\\$mk\" \\] \\|\\| exit 21'\$#    '[ -f \"\$mk\" ] || exit 21'#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-5b-no-size case_vx_emptymk
fi
# G2-6 — the same-session source re-check dropped.
if mutate g2v-6-no-source "$SCRIPT" 1 "${_G2R}{/^    '\\[ \"\\\$s\" = \"\\\$src\" \\] \\|\\| exit 6'\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-6-no-source case_vx_overmount
fi
# G2-7 — the answer anchor loosened to anything.
if mutate g2v-7-any-answer "$SCRIPT" 2 "${_G2R}s#^  gd_capture '\\^\\[0-9\\]\\+\\\$' #  gd_capture '.*' #"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-7-any-answer case_vempty
fi
# G2-8 — an instrument failure (remote 16) rendered as a store state.
if mutate g2v-8-16-as-state "$SCRIPT" 1 "${_G2R}s#^    21\\) reason=marker_absent ;;\$#    16) reason=marker_absent ;;\\n&#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-8-16-as-state case_v16
fi
# G2-9 — the regular-file test dropped, leaving -s: a non-empty directory passes -s.
if mutate g2v-9-no-file-test "$SCRIPT" 2 "${_G2R}s#^    '\\[ -f \"\\\$mk\" \\] && \\[ -s \"\\\$mk\" \\] \\|\\| exit 21'\$#    '[ -s \"\$mk\" ] || exit 21'#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-9-no-file-test case_vx_dirmk
fi
# G2-10 — the explicit catch-all arm deleted: an unknown rc would fall through.
if mutate g2v-10-no-default "$SCRIPT" 1 "${_G2R}{/^    \\*\\) _store_refuse store-verified probe_failed \"\\\$rc\" ;;\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-10-no-default case_v127
fi
# G2-11 — the anchor loosened from ^[0-9]+$ to [0-9]+.
if mutate g2v-11-unanchored "$SCRIPT" 2 "${_G2R}s#^  gd_capture '\\^\\[0-9\\]\\+\\\$' #  gd_capture '[0-9]+' #"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-11-unanchored case_vx0
fi
# G2-12 — a count-stage rc attributed to the verify stage.
if mutate g2v-12-stage-attribution "$SCRIPT" 2 "${_G2R}s#^    0\\|3\\|4\\|7\\|8\\|9\\|96\\) ;;\$#    0|3|4|7|9|96) ;;#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-12-stage-attribution case_v8
fi
# G2-13 — the containing-mount check dropped: a count over a second mount would read.
if mutate g2v-13-no-target "$SCRIPT" 1 "${_G2R}{/^    '\\[ \"\\\$t\" = \"\\\$rr\" \\] \\|\\| exit 8'\$/d}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-13-no-target case_other_mount
fi
# G2-14 — the count narrowed back to *.git names only.
if mutate g2v-14-git-only "$SCRIPT" 2 "${_G2R}s#! -name '\\.\\*\\.init\\.lock' ! -name '\\.init\\.lock' ! -name lost\\+found#-name '*.git'#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-14-git-only case_any_entry
fi
# G2-15 — the lock dotfiles no longer skipped (a lock dotfile would read as a repository).
if mutate g2v-15-locks-counted "$SCRIPT" 2 "${_G2R}s#! -name '\\.\\*\\.init\\.lock' ##"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-15-locks-counted case_locks_skipped
fi
# G2-16 — REORDER: the freeze read after the marker (a frozen host missing its marker would read
# marker_absent and send the operator to the wrong row).
if mutate g2v-16-freeze-late "$SCRIPT" 2 "${_G2R}{/^    '\\[ ! -e \"\\\$fz\" \\] \\|\\| exit 23'\$/d; s#^    '\\[ \"\\\$m\" = \"\\\$fu\" \\] \\|\\| exit 22'\$#&\\n    '[ ! -e \"\$fz\" ] || exit 23'#}"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2v-16-freeze-late case_vx_frozen_nomk
fi
# G2-17 — the count's exclusions drift from the bootstrap's (lost+found dropped).
if mutate g2v-17-count-parity "$SCRIPT" 2 "${_G2R}s# ! -name lost\\+found##"; then
  mutant_red g2v-17-count-parity case_count_parity "$MUTANT" "$DIR/git-data-bootstrap.sh"
fi
# G2-H1 (harness) — the ssh shim's session arm hardwired to ok: the canned negatives go RED.
if mutate g2v-h1-shim-always-ok "$BIN/ssh" 2 's#^    case "\$\{SHIM_VERIFY:-ok\}" in$#    case ok in#'; then
  _hb="$(_harness_bin g2h1 ssh)"; assert_fixture_dir "$_hb"
  BIN="$_hb" mutant_red g2v-h1-shim-always-ok case_v22
fi
# G2-H2 (harness) — the findmnt shim's UUID branch collapsed into SOURCE.
if mutate g2v-h2-no-uuid-branch "$BIN/findmnt" 2 's#^if \[ "\$\*" = "-n -o UUID --mountpoint \$\{!\#\}" \]; then$#if false; then#'; then
  _hb="$(_harness_bin g2h2 findmnt)"; assert_fixture_dir "$_hb"
  BIN="$_hb" mutant_red g2v-h2-no-uuid-branch case_vx_ok
fi
# G2-H3 (harness) — the SOURCE answer ignores SHIM_FINDMNT_S.
if mutate g2v-h3-fixed-source "$BIN/findmnt" 2 's#"\$\{SHIM_FINDMNT_S:-/dev/mapper/git-data\}"#/dev/mapper/git-data#'; then
  _hb="$(_harness_bin g2h3 findmnt)"; assert_fixture_dir "$_hb"
  BIN="$_hb" mutant_red g2v-h3-fixed-source case_vx_overmount
fi
# G2-H4 (harness) — the stat shim's containing-mount answer ignores SHIM_STAT_M.
if mutate g2v-h4-fixed-mount "$BIN/stat" 2 's#^    \*\)    printf .%s\\n. "\$SHIM_STAT_M"; exit 0 ;;$#    *)    readlink -f "${OLD_ROOT:-/mnt/git-data}"; exit 0 ;;#'; then
  _hb="$(_harness_bin g2h4 stat)"; assert_fixture_dir "$_hb"
  BIN="$_hb" mutant_red g2v-h4-fixed-mount case_other_mount
fi

# RB — one row per check, each tripping ONLY that check.
# RB-1 (miss) — a script word deleted from the map copy, no other word added.
if mutate rb-1-miss "$RUNBOOK" 2 '/^\| \*\*Tampering signal\*\*/s# reason=marker_mismatch`#`#'; then
  mutant_red rb-1-miss case_rb "$SCRIPT" "$MUTANT"
fi
# RB-2 (extra) — a stale row in the old spelling, naming a retired verdict and no probe.
if mutate rb-2-stale-row "$RUNBOOK" 1 '/^\| The store holds repositories \|/i | The store root is already the LUKS mapper | `verdict=already_cut_over` (exit 5) | Nothing to do. |'; then
  mutant_red rb-2-stale-row case_rb "$SCRIPT" "$MUTANT"
fi
# RB-3 (sw=ow) — a word the unit rows observed goes missing from the observed set.
if mutate rb-3-observed-drop "$T/rb.observed" 1 '/^no_fs_uuid$/d'; then
  mutant_red rb-3-observed-drop case_rb "$SCRIPT" "$RUNBOOK" "$MUTANT"
fi
# RB-4 (pairs) — a map row names a verdict under the wrong probe.
if mutate rb-4-wrong-probe "$RUNBOOK" 2 's#`probe=store-verified verdict=cutover_frozen`#`probe=store-mounted verdict=cutover_frozen`#'; then
  mutant_red rb-4-wrong-probe case_rb "$SCRIPT" "$MUTANT"
fi
# RB-5 — a new script refusal word (several checks) and RB-6 — a renamed reason (several checks).
if mutate rb-5-new-script-word "$SCRIPT" 1 's#^  _store_emit store-on-mapper ok$#  [ -n "$STORE_SOURCE" ] || _store_refuse store-on-mapper store_vanished\n&#'; then
  mutant_red rb-5-new-script-word case_rb "$MUTANT" "$RUNBOOK"
fi
if mutate rb-6-renamed-reason "$SCRIPT" 2 's#^    24\) reason=no_fs_uuid ;;$#    24) reason=no_fs_uid ;;#'; then
  mutant_red rb-6-renamed-reason case_rb "$MUTANT" "$RUNBOOK"
fi

# P3 — over copied directories, one row per property.
_p3dir() { # <name> — a fresh copy of the pristine p3 tree
  local d="$T/p3-$1"
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d" && cp "$T"/p3/git-data-*.sh "$d/" || { printf 'FAIL SETUP: p3 dir %s\n' "$1" >&2; exit 1; }
  printf '%s' "$d"
}
# p3_red <name> <file-in-p3> <expected-diff-lines> <sed> [dest-basename] — a mutated copy of one
# definer placed into a fresh p3 tree (under dest-basename when given); case_parity must go RED.
p3_red() {
  local name="$1" src="$2" want="$3" expr="$4" dest="${5:-$(basename "$2")}" pd
  if mutate "$name" "$src" "$want" "$expr"; then
    pd="$(_p3dir "$name")"; assert_fixture_dir "$pd"
    cp "$MUTANT" "$pd/$dest" || { printf 'FAIL SETUP: p3 %s\n' "$name" >&2; exit 1; }
    mutant_red "$name" case_parity "$SCRIPT" "$pd"
  fi
}
if mutate p3-1-script-mapper "$SCRIPT" 2 's#^LUKS_MAPPER="\$\{LUKS_MAPPER:-/dev/mapper/git-data\}"#LUKS_MAPPER="${LUKS_MAPPER:-/dev/mapper/gd}"#'; then
  mutant_red p3-1-script-mapper case_parity "$MUTANT" "$T/p3"
fi
p3_red p3-2-definer-marker "$T/p3/git-data-gc.sh" 2 's#^STORE_VERIFIED="\$\{GIT_DATA_STORE_VERIFIED:-/etc/git-data/store-verified\}"$#STORE_VERIFIED="${GIT_DATA_STORE_VERIFIED:-/etc/git-data/verified}"#'
p3_red p3-3-extra-definer "$T/p3/git-data-luks-reopen.sh" 1 '1s#$#\nSTORE_DEVICE="${GIT_DATA_STORE_DEVICE:-/dev/mapper/other}"#'
# p3-4 — the freeze path rooted in a variable the file never sets.
p3_red p3-4-freeze-foreign-root "$T/p3/git-data-provision.sh" 2 's#^cutover_freeze="\$\{GIT_DATA_CUTOVER_FREEZE:-\$\{MOUNT_ROOT\}/\.cutover-freeze\}"$#cutover_freeze="${GIT_DATA_CUTOVER_FREEZE:-${GIT_DATA_ROOT}/.cutover-freeze}"#'
# p3-5 — a later plain reassignment overrides the compared default.
p3_red p3-5-shadow-reassignment "$T/p3/git-data-gc.sh" 1 '/^STORE_DEVICE="\$\{GIT_DATA_STORE_DEVICE:-/a STORE_DEVICE="/dev/sdb"'
# p3-6 — set identity alone: a new definer whose every value is correct.
p3_red p3-6-new-definer "$T/p3/git-data-gc.sh" 1 '1s#$#\n\# a copy under a new name#' git-data-zz-copy.sh
# p3-7 — the wrappers' repositories root moved alone.
p3_red p3-7-repo-root "$T/p3/git-data-remove.sh" 2 's#^REPO_ROOT="\$\{GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories\}"$#REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repos}"#'
}

# ── RUNTIME ARM — real OpenSSH (pinned ubuntu:24.04) ─────────────────────────────────
RUNTIME_ROWS=27
_runtime_skip() {
  if [ "${CI:-}" = "true" ]; then
    fail "runtime arm: $1 — and CI=true, so this is a FAILURE: the runner must provide docker"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  else
    SKIPPED=$((SKIPPED + RUNTIME_ROWS)); printf '  SKIP runtime arm (%s rows): %s\n' "$RUNTIME_ROWS" "$1"
  fi
}
if [ "${GDC_SKIP_RUNTIME:-}" = 1 ] && [ "${CI:-}" != "true" ]; then _runtime_skip "GDC_SKIP_RUNTIME=1 (local iteration)"
elif ! command -v docker >/dev/null 2>&1; then _runtime_skip "docker absent"
elif ! docker info >/dev/null 2>&1; then _runtime_skip "docker daemon unreachable"
else
  mkdir -p "$T/rt/out" || { printf 'FAIL SETUP: mkdir rt\n' >&2; exit 1; }
  cp "$SCRIPT" "$T/rt/git-data-cutover.sh" || { printf 'FAIL SETUP: cp script\n' >&2; exit 1; }
  cp "$DIR/git-data-transport-wrapper.sh" "$T/rt/wrapper.sh" || { printf 'FAIL SETUP: cp wrapper\n' >&2; exit 1; }
  if [ -s "$T/steps/ssh_config.sh" ]; then cp "$T/steps/ssh_config.sh" "$T/rt/sshcfg.sh"; else : > "$T/rt/sshcfg.sh"; fi
  cp "$WKH" "$T/rt/wkh.sh" || { printf 'FAIL SETUP: cp write-known-hosts.sh\n' >&2; exit 1; }
  # The bridge's exported WEB_HOST_SSH (captured by the BR rows); the plan-D3 literal if the
  # decode step could not be run (the BR rows then already fail).
  if grep -q '@KEY@' "$T/bridge-inv.tmpl" 2>/dev/null && grep -q '@KH@' "$T/bridge-inv.tmpl"; then cp "$T/bridge-inv.tmpl" "$T/rt/web-inv.tmpl"
  else printf '%s\n' 'ssh -F /dev/null -i @KEY@ -o StrictHostKeyChecking=yes -o UserKnownHostsFile=@KH@ -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -l root' > "$T/rt/web-inv.tmpl"; fi
  cat > "$T/rt/drive.sh" <<'DRV'
set -u
export DEBIAN_FRONTEND=noninteractive
# Bounded apt (#8744): Acquire::Retries=5 inside each call and a 3-attempt loop with
# 10s/30s backoff around the pair. The pair sits inside `if` — a tested context — so a
# failed update can never fall through into an install attempt that was skipped. Output
# goes to a fixture log instead of /dev/null: on exhaustion its credential-scrubbed tail
# (apt error text can embed proxy user:pass@host) prints BEFORE the marker, so the fleet
# log says WHY instead of a bare rc=100. The host greps the marker with -qx, so it stays
# a bare line. Tail and marker both go to stderr: docker demuxes stdout/stderr, so a
# stdout marker would race a stderr tail and could land BEFORE the diagnostics it
# follows (measured — a cross-stream write order is not preserved).
_apt_log=/tmp/apt-fixture.log; : > "$_apt_log"
_apt_ok=0
for _apt_try in 1 2 3; do
  if apt-get update -qq -o Acquire::Retries=5 >> "$_apt_log" 2>&1 \
     && apt-get install -y -qq -o Acquire::Retries=5 openssh-server openssh-client netcat-openbsd iproute2 git >> "$_apt_log" 2>&1; then
    _apt_ok=1; break
  fi
  case "$_apt_try" in 1) sleep 10 ;; 2) sleep 30 ;; esac
done
[ "$_apt_ok" -eq 1 ] || { tail -n 20 "$_apt_log" | sed -e 's#//[^/@[:space:]]*:[^/@[:space:]]*@#//***:***@#g' -e 's#//[^/@[:space:]:]*@#//***@#g' >&2; echo FIXTURE_APT_FAILED >&2; exit 100; }
mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
ssh-keygen -A >/dev/null 2>&1
ssh-keygen -q -t ed25519 -N '' -f /tmp/k && cp /tmp/k.pub /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
# Host-key pins (#7226): every sshd here serves the container's own host keys. The web-1 pin is
# its ECDSA key in the committed file's shape (a header comment, then the key line); the git-data
# pin is its ED25519 key, as the flag precheck writes it. The workflow's writer runs from a
# GITHUB_WORKSPACE-shaped tree, exactly as the ssh_config step calls it.
mkdir -p /ws/.github/actions/cf-tunnel-ssh-bridge /ws/apps/web-platform/infra
install -m 755 /work/wkh.sh /ws/.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh
{ echo '# fixture: container ECDSA host key'; cut -d' ' -f1,2 /etc/ssh/ssh_host_ecdsa_key.pub; } > /ws/apps/web-platform/infra/web-1-ssh-host-key.pub
cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub > /tmp/gd.pin
bash /work/wkh.sh web-1 /ws/apps/web-platform/infra/web-1-ssh-host-key.pub /tmp/web.kh >/dev/null || { echo FIXTURE_PIN_FAILED; exit 101; }
ssh-keygen -q -t ecdsa -b 256 -N '' -f /tmp/other-ecdsa && ssh-keygen -q -t ed25519 -N '' -f /tmp/other-ed25519
cut -d' ' -f1,2 /tmp/other-ecdsa.pub > /tmp/other-ecdsa.pin
bash /work/wkh.sh web-1 /tmp/other-ecdsa.pin /tmp/web-wrong.kh >/dev/null || { echo FIXTURE_PIN_FAILED; exit 101; }
: > /tmp/web-empty.kh
cut -d' ' -f1,2 /tmp/other-ed25519.pub > /tmp/gd-wrong.pin
# pinned_web <keyfile> <known_hosts> [ssh args...] — the bridge's exported bash-mode WEB_HOST_SSH
# (the BR rows capture it from action.yml's decode step), with this fixture's key and known_hosts.
pinned_web() { local k="$1" kh="$2" t; shift 2; t="$(cat /work/web-inv.tmpl)"; t="${t//@KEY@/$k}"; printf '%s%s' "${t//@KH@/$kh}" "${*:+ $*}"; }
sshd_on() { # addr port extra-option...
  local a="$1" p="$2"; shift 2
  # stdout/stderr to /dev/null: a backgrounded child holding the $(...) pipe open makes the
  # caller's command substitution wait for it forever.
  /usr/sbin/sshd -D -o ListenAddress="$a" -p "$p" -o PasswordAuthentication=no -o PermitRootLogin=prohibit-password "$@" -E "/tmp/sshd-$a-$p.log" >/dev/null 2>&1 &
  echo $!
}
WEB_OK=$(sshd_on 127.0.0.1 2201)
WEB_NOFWD=$(sshd_on 127.0.0.1 2202 -o AllowTcpForwarding=no)
# Serves ONLY its ED25519 host key: a client pinned to ECDSA cannot negotiate (H4 reason=alg).
WEB_EDONLY=$(sshd_on 127.0.0.1 2203 -o HostKey=/etc/ssh/ssh_host_ed25519_key)
GD=$(sshd_on 127.0.0.2 22)
sleep 1
echo FIXTURE_OK
row() { printf '%s=%s\n' "$1" "$2" >> /out/rows; }
drive() { # label web-port [known_hosts]
  local s e rc
  s=$(date +%s)
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root WEB_HOSTS=127.0.0.1 GIT_DATA_HOST=127.0.0.2 \
    WEB_HOST_SSH="$(pinned_web /tmp/k "${3:-/tmp/web.kh}" -p "$2")" \
    bash /work/git-data-cutover.sh > "/out/$1.out" 2>&1
  rc=$?; e=$(date +%s)
  row "$1_rc" "$rc"; row "$1_elapsed" "$((e - s))"
}
drive r1 2201
drive r2 2202
drive rhkc 2201 /tmp/web-wrong.kh
drive rhku 2201 /tmp/web-empty.kh
drive rhka 2203
kill "$GD"; wait "$GD" 2>/dev/null
drive r3 2201
( while :; do printf 'HTTP/1.0 400 Bad Request\r\n\r\n' | nc -N -l 127.0.0.2 22 >/dev/null 2>&1; done ) >/dev/null 2>&1 &
# The listener serves one connection per loop turn, so a second confirming probe would race its
# restart: record the first success, then let it re-arm before the real probe.
listening=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if nc -z 127.0.0.2 22 2>/dev/null; then listening=1; break; fi
  sleep 0.5
done
row r4_listening "$listening"
sleep 1
drive r4 2201
kill "$WEB_OK" "$WEB_NOFWD" "$WEB_EDONLY" 2>/dev/null

# ── The workflow's own ssh_config, end to end: web-1 (10.0.1.10) authorizes ONLY the CI key,
# git-data (10.0.1.20) ONLY the root key, and a root session's PATH (/usr/local/sbin first) finds a
# fixture findmnt/find that record the remote commands. The script itself runs with
# PATH=/usr/sbin:/usr/bin:/bin, so the fixtures are reached only through sshd.
ipok=1
ip addr add 10.0.1.10/32 dev lo >/dev/null 2>&1 || ipok=0
ip addr add 10.0.1.20/32 dev lo >/dev/null 2>&1 || ipok=0
row ip_ok "$ipok"
ssh-keygen -q -t ed25519 -N '' -f /tmp/ci && ssh-keygen -q -t ed25519 -N '' -f /tmp/gdroot
install -m 600 /tmp/ci.pub /etc/ssh/ak-web && install -m 600 /tmp/gdroot.pub /etc/ssh/ak-gd
mkdir -p /fixture /rt && : > /out/remote.log
# The store session also asks `findmnt -n -o UUID --mountpoint <root>`: that one answers /fixture/findmnt.uuid.
# /mnt/git-data is an anonymous volume, i.e. a REAL mount point, so the session's own
# `stat -c %m` containing-mount check runs for real; it is emptied with find, never removed.
cat > /usr/local/sbin/findmnt <<'F'
#!/bin/bash
printf 'findmnt %s\n' "$*" >> /out/remote.log
if [ "$3" = UUID ]; then cat /fixture/findmnt.uuid; else cat /fixture/findmnt.out; fi
exit "$(cat /fixture/findmnt.rc)"
F
cat > /usr/local/sbin/find <<'F'
#!/bin/bash
printf 'find %s\n' "$*" >> /out/remote.log
exec /usr/bin/find "$@"
F
chmod 755 /usr/local/sbin/findmnt /usr/local/sbin/find
# The pre-receive fence as git-data-bootstrap.sh plants it (#8101): a root:git 0750 hooks dir, a
# root:root 0755 hook, and the system core.hooksPath naming it. Re-planted after every rm -rf.
groupadd -f git
id git >/dev/null 2>&1 || useradd -M -g git -s /bin/sh git
install -m 755 /work/wrapper.sh /usr/local/bin/git-data-transport-wrapper.sh
plant_fence() {
  mkdir -p /mnt/git-data/hooks && chown root:git /mnt/git-data/hooks && chmod 0750 /mnt/git-data/hooks
  printf '#!/bin/sh\nexit 1\n' > /mnt/git-data/hooks/pre-receive && chown root:root /mnt/git-data/hooks/pre-receive && chmod 0755 /mnt/git-data/hooks/pre-receive
  git config --system core.hooksPath /mnt/git-data/hooks
}
W1=$(sshd_on 10.0.1.10 22 -o AuthorizedKeysFile=/etc/ssh/ak-web)
G1=$(sshd_on 10.0.1.20 22 -o AuthorizedKeysFile=/etc/ssh/ak-gd)
sleep 1
install -m 600 /tmp/gdroot /rt/gd-root-key
cp /tmp/gd.pin /rt/git-data.pin
env -i PATH=/usr/bin:/bin HOME=/root RUNNER_TEMP=/rt GITHUB_WORKSPACE=/ws CI_SSH_KEYFILE=/tmp/ci bash --noprofile --norc -eo pipefail /work/sshcfg.sh > /out/sshcfg.out 2>&1
row sshcfg_rc "$?"
# The same writer run with a WRONG git-data pin (another ED25519 key) into a second RUNNER_TEMP.
mkdir -p /rt2 && install -m 600 /tmp/gdroot /rt2/gd-root-key && cp /tmp/gd-wrong.pin /rt2/git-data.pin
env -i PATH=/usr/bin:/bin HOME=/root RUNNER_TEMP=/rt2 GITHUB_WORKSPACE=/ws CI_SSH_KEYFILE=/tmp/ci bash --noprofile --norc -eo pipefail /work/sshcfg.sh > /out/sshcfg2.out 2>&1
row sshcfg2_rc "$?"
accepted() { grep -c 'Accepted publickey for root' "/tmp/sshd-$1-22.log" 2>/dev/null || true; }
drive2() { # label [runner-temp]
  local wb gb
  wb=$(accepted 10.0.1.10); gb=$(accepted 10.0.1.20)
  : > /out/remote.log
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root WEB_HOSTS=10.0.1.10 \
    WEB_HOST_SSH="$(pinned_web /tmp/ci /tmp/web.kh)" \
    GIT_DATA_SSH="ssh -F ${2:-/rt}/gd-ssh-config" bash /work/git-data-cutover.sh > "/out/$1.out" 2>&1
  row "$1_rc" "$?"
  row "$1_web_accepted" "$(( $(accepted 10.0.1.10) - wb ))"; row "$1_gd_accepted" "$(( $(accepted 10.0.1.20) - gb ))"
  cp /out/remote.log "/out/$1.remote"
}
# The canonical host (ADR-239): the store served by the mapper, and the bootstrap's marker holding
# the filesystem UUID, written the way step 5a writes it.
U=4f1c2a9e-7b3d-4e8a-9c6f-2d5b8a1e0c73
printf '%s\n' "$U" > /fixture/findmnt.uuid
mkdir -p /etc/git-data && printf '%s\n' "$U" > /etc/git-data/store-verified
printf '/dev/mapper/git-data\n' > /fixture/findmnt.out; echo 0 > /fixture/findmnt.rc; find /mnt/git-data -mindepth 1 -delete; mkdir -p /mnt/git-data/repositories; plant_fence
drive2 r5
drive2 rhkg /rt2
mkdir -p /mnt/git-data/repositories/ws-1.git
drive2 r6
printf '/dev/sdb\n' > /fixture/findmnt.out; find /mnt/git-data -mindepth 1 -delete
drive2 r7
printf '/dev/mapper/git-data\n' > /fixture/findmnt.out; install -m 600 /tmp/ci.pub /etc/ssh/ak-gd
drive2 r8
install -m 600 /tmp/gdroot.pub /etc/ssh/ak-gd; mkdir -p /mnt/git-data/repositories; plant_fence
git config --system --unset core.hooksPath
drive2 rf2
git config --system core.hooksPath /mnt/git-data/hooks
# An [include] after the direct value redirects the EFFECTIVE hooksPath; a scoped read without
# --includes would miss it.
printf '[core]\n\thooksPath = /elsewhere/hooks\n' > /etc/gitconfig-redirect
git config --system include.path /etc/gitconfig-redirect
drive2 rfinc
git config --system --unset include.path
# The git user cannot traverse to the hook (root can): git would skip it and accept the push.
chmod 700 /mnt
drive2 rf17
chmod 755 /mnt
# The installed transport wrapper no longer pins the fence on git's command line.
sed -i '/^exec git -c "core.hooksPath=/d' /usr/local/bin/git-data-transport-wrapper.sh
drive2 rf18
install -m 755 /work/wrapper.sh /usr/local/bin/git-data-transport-wrapper.sh
# RVM: the marker names another filesystem. The trap restores it however the subshell ends, so the
# next row never depends on this one's order; RVM2 proves the restore.
( trap 'printf "%s\n" "$U" > /etc/git-data/store-verified' EXIT
  printf '%s\n' 9a2e6c14-3b7f-4d91-8e05-c6f1a2b3d4e7 > /etc/git-data/store-verified
  drive2 rvm )
drive2 rvm2
kill "$W1" "$G1" 2>/dev/null
echo DRIVER_DONE
DRV
  : > "$T/rt/out/rows"
  # Bounded: a hung driver must fail this arm loudly, never eat the CI job's clock.
  _cname="gdc-access-$$-${RANDOM}"
  timeout -k 10 480 docker run --rm --cap-add NET_ADMIN --name "$_cname" -v /mnt/git-data -v "$T/rt/drive.sh:/work/drive.sh:ro" \
    -v "$T/rt/git-data-cutover.sh:/work/git-data-cutover.sh:ro" -v "$T/rt/sshcfg.sh:/work/sshcfg.sh:ro" -v "$T/rt/wrapper.sh:/work/wrapper.sh:ro" \
    -v "$T/rt/wkh.sh:/work/wkh.sh:ro" -v "$T/rt/web-inv.tmpl:/work/web-inv.tmpl:ro" \
    -v "$T/rt/out:/out" "$UBUNTU_BASE" bash /work/drive.sh > "$T/rt/stdout" 2>&1
  DRC=$?
  docker rm -f "$_cname" >/dev/null 2>&1 || true
  if grep -qx DRIVER_DONE "$T/rt/stdout"; then
    _rv() { sed -n "s/^$1=//p" "$T/rt/out/rows" | tail -1; }
    _acc() { grep -qE "^\[git-data-cutover\] ACCESS role=$2 host=[^ ]+ verdict=$3( |$)" "$T/rt/out/$1.out"; }
    _sto() { grep -qE "^\[git-data-cutover\] STORE probe=$2 verdict=$3( |$)" "$T/rt/out/$1.out"; }
    _rctx() { tr '\n' '|' < "$T/rt/out/$1.out" | tail -c 500 | sed 's/::/: :/g'; }
    # OpenSSH 9.6 logs "Unable to negotiate ..." and "channel N: open failed: ..." at INFO: an
    # invocation carrying LogLevel=ERROR hides exactly the text these rows classify.
    _ll_hint() { grep -q 'LogLevel=ERROR' "$T/rt/web-inv.tmpl" && printf ' (the bridge WEB_HOST_SSH carries -o LogLevel=ERROR, which suppresses this INFO-level ssh text)'; }
    { [ "$(_rv r1_rc)" = 3 ] && _acc r1 web ok; } && pass "R1a: real sshd — web ok and the run exits 3" || fail "R1a: real-sshd web probe/exit" "rc=$(_rv r1_rc) $(_rctx r1)"
    _acc r1 git-data-jump ok && pass "R1b: real sshd — ssh -W returns the target's SSH-2.0- banner (jump ok, no git-data credential)" || fail "R1b: real-sshd jump not ok" "$(_rctx r1)"
    _acc r1 git-data-auth git_data_root_key_absent && pass "R1c: real sshd — git-data-auth verdict=git_data_root_key_absent" || fail "R1c: real-sshd auth verdict" "$(_rctx r1)"
    _el="$(_rv r1_elapsed)"
    { [ -n "$_el" ] && [ "$_el" -lt 20 ]; } && pass "R1d: the canonical gate finished in ${_el}s (< 20s; the jump's own bound is 25s)" || fail "R1d: the gate took ${_el:-?}s (>= 20s)" "$(_rctx r1)"
    { [ "$(_rv r2_rc)" = 3 ] && grep -qE 'role=git-data-jump host=[^ ]+ verdict=failed rc=[0-9]+ reason=forward_refused$' "$T/rt/out/r2.out"; } \
      && pass "R2a: AllowTcpForwarding no — jump failed reason=forward_refused, exit 3" || fail "R2a: forwarding-refused jump not failed/forward_refused$(_ll_hint)" "$(_rctx r2)"
    grep -qxF '[git-data-cutover] probe-stderr: channel 0: open failed: administratively prohibited: open failed' "$T/rt/out/r2.out" \
      && pass "R2b: the real refusal stderr matches the unit rows' fixture text" || fail "R2b: real refusal stderr differs from the fixture$(_ll_hint)" "$(_rctx r2)"
    { [ "$(_rv r3_rc)" = 3 ] && grep -qE 'role=git-data-jump host=[^ ]+ verdict=failed rc=[0-9]+ reason=connect_refused$' "$T/rt/out/r3.out"; } \
      && pass "R3: git-data sshd stopped — jump failed reason=connect_refused" || fail "R3: stopped target not failed/connect_refused$(_ll_hint)" "$(_rctx r3)"
    [ "$(_rv r4_listening)" = 1 ] && pass "R4a: the non-SSH listener was bound before the probe (R4b is not a refused connect)" || fail "R4a: the non-SSH listener never bound" "$(_rctx r4)"
    { [ "$(_rv r4_rc)" = 3 ] && _acc r4 git-data-jump failed && ! grep -q 'connect failed' "$T/rt/out/r4.out"; } \
      && pass "R4b (negative control): a non-SSH listener is jump failed — the banner rule can fail" || fail "R4b: a non-SSH listener was accepted as a banner, or was never reached" "$(_rctx r4)"
    { [ "$(_rv rhkc_rc)" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=web host=127\.0\.0\.1 verdict=host_key_mismatch rc=255 reason=changed$' "$T/rt/out/rhkc.out"; } \
      && pass "RHK1: real OpenSSH, web-1 pinned to ANOTHER ECDSA key -> role=web verdict=host_key_mismatch reason=changed, exit 3" || fail "RHK1: a wrong web-1 pin was not host_key_mismatch reason=changed" "rc=$(_rv rhkc_rc) $(_rctx rhkc)"
    { [ "$(_rv rhku_rc)" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=web host=127\.0\.0\.1 verdict=host_key_mismatch rc=255 reason=unknown$' "$T/rt/out/rhku.out"; } \
      && pass "RHK2: real OpenSSH, an EMPTY known_hosts -> reason=unknown (never trusted on first use)" || fail "RHK2: an empty known_hosts was not host_key_mismatch reason=unknown" "rc=$(_rv rhku_rc) $(_rctx rhku)"
    { [ "$(_rv rhka_rc)" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=web host=127\.0\.0\.1 verdict=host_key_mismatch rc=255 reason=alg$' "$T/rt/out/rhka.out"; } \
      && pass "RHK3: real OpenSSH, an sshd serving only ED25519 to a client pinned to ECDSA -> reason=alg" || fail "RHK3: an algorithm mismatch was not host_key_mismatch reason=alg$(_ll_hint)" "rc=$(_rv rhka_rc) $(_rctx rhka)"
    { [ "$(_rv sshcfg2_rc)" = 0 ] && [ "$(_rv rhkg_rc)" = 3 ] && _acc rhkg web ok && _acc rhkg git-data-jump ok \
      && grep -qE '^\[git-data-cutover\] ACCESS role=git-data-auth host=10\.0\.1\.20 verdict=host_key_mismatch rc=255 reason=changed$' "$T/rt/out/rhkg.out" \
      && [ "$(_rv rhkg_gd_accepted)" = 0 ]; } \
      && pass "RHK4: the workflow's ssh_config with a WRONG git-data pin -> web ok, jump ok, git-data-auth host_key_mismatch reason=changed, and git-data never saw the root key" || fail "RHK4: a wrong git-data pin was not refused at git-data-auth" "sshcfg2=$(_rv sshcfg2_rc) rc=$(_rv rhkg_rc) gd=$(_rv rhkg_gd_accepted) $(_rctx rhkg)"
    { [ "$(_rv ip_ok)" = 1 ] && [ "$(_rv sshcfg_rc)" = 0 ]; } \
      && pass "R5-fixture: 10.0.1.10/10.0.1.20 bound in the container and the workflow's ssh_config writer ran (rc 0)" || fail "R5-fixture: address binding or the ssh_config writer failed" "ip=$(_rv ip_ok) sshcfg=$(_rv sshcfg_rc) $(tr '\n' '|' < "$T/rt/out/sshcfg.out" 2>/dev/null | sed 's/::/: :/g')"
    { [ "$(_rv r5_rc)" = 0 ] && _acc r5 web ok && _acc r5 git-data-jump ok && _acc r5 git-data-auth ok && _sto r5 store-mounted ok && _sto r5 store-on-mapper ok && _sto r5 store-verified ok && _sto r5 store-empty ok && _sto r5 fence-shape ok; } \
      && pass "R5a/AC2 runtime: real OpenSSH through the generated ssh_config, BOTH hops strictly pinned — access ok x3, store probes ok x4 (the mapper, a bound marker), fence ok on a real root:git 0750 tree, exit 0" || fail "R5a: the end-to-end read-only proof did not exit 0" "rc=$(_rv r5_rc) $(_rctx r5)"
    [ "$(cat "$T/rt/out/r5.remote" 2>/dev/null)" = "findmnt -n -o SOURCE --mountpoint /mnt/git-data
findmnt -n -o SOURCE --mountpoint /mnt/git-data
findmnt -n -o UUID --mountpoint /mnt/git-data
find -H /mnt/git-data/repositories -mindepth 1 -maxdepth 1 ! -name .*.init.lock ! -name .init.lock ! -name lost+found -printf .
findmnt -no SOURCE -T /mnt/git-data/hooks
findmnt -no SOURCE -T /mnt/git-data/hooks/pre-receive" ] \
      && pass "R5b: on git-data the commands observed are exactly the mount read, the store session's source and UUID reads and its count, and the fence's two findmnt -T reads" || fail "R5b: unexpected remote commands" "$(tr '\n' '|' < "$T/rt/out/r5.remote" 2>/dev/null)"
    { [ "$(_rv r5_web_accepted)" = 6 ] && [ "$(_rv r5_gd_accepted)" = 4 ]; } \
      && pass "R5c: web-1 accepted 6 CI-key logins (web, jump, and the ProxyCommand hop of auth/findmnt/store session/fence); git-data accepted 4 root-key logins" || fail "R5c: login counts differ" "web=$(_rv r5_web_accepted) gd=$(_rv r5_gd_accepted)"
    { [ "$(_rv r6_rc)" = 5 ] && _sto r6 store-empty store_not_empty; } \
      && pass "R6a: a real ws-1.git under /mnt/git-data/repositories -> store_not_empty, exit 5" || fail "R6a: a non-empty store passed" "rc=$(_rv r6_rc) $(_rctx r6)"
    grep -qxF "find -H /mnt/git-data/repositories -mindepth 1 -maxdepth 1 ! -name .*.init.lock ! -name .init.lock ! -name lost+found -printf ." "$T/rt/out/r6.remote" \
      && pass "R6b: the count ran on git-data as find -H … with the bootstrap's exclusions" || fail "R6b: the count command differs" "$(tr '\n' '|' < "$T/rt/out/r6.remote" 2>/dev/null)"
    { [ "$(_rv r7_rc)" = 5 ] && _sto r7 store-on-mapper store_not_on_mapper; } \
      && pass "R7: a plaintext /dev/sdb source -> store_not_on_mapper, exit 5" || fail "R7: a store not served by the mapper passed" "rc=$(_rv r7_rc) $(_rctx r7)"
    { [ "$(_rv r8_rc)" = 3 ] && grep -qE 'role=git-data-auth host=10\.0\.1\.20 verdict=failed rc=[0-9]+ reason=auth_refused$' "$T/rt/out/r8.out"; } \
      && pass "R8 (negative control): git-data authorizing only the CI key -> auth_refused — the git-data block offers ONLY the root key" || fail "R8: the git-data block authenticated with a key other than the root key" "rc=$(_rv r8_rc) $(_rctx r8)"
    { [ "$(_rv rf2_rc)" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=hooks_path_mismatch' "$T/rt/out/rf2.out"; } \
      && pass "RF2: real git with core.hooksPath unset (git config exits 1) -> fence_not_intact reason=hooks_path_mismatch, exit 5" || fail "RF2: an unset hooksPath was not hooks_path_mismatch" "rc=$(_rv rf2_rc) $(_rctx rf2)"
    { [ "$(_rv rfinc_rc)" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=hooks_path_mismatch' "$T/rt/out/rfinc.out"; } \
      && pass "RFINC: real git with an [include] redirecting core.hooksPath -> reason=hooks_path_mismatch (the effective value, includes resolved)" || fail "RFINC: an include-redirected hooksPath was accepted" "rc=$(_rv rfinc_rc) $(_rctx rfinc)"
    { [ "$(_rv rf17_rc)" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=hook_not_runnable_by_git' "$T/rt/out/rf17.out"; } \
      && pass "RF17: a real git user that cannot traverse /mnt (root still can) -> reason=hook_not_runnable_by_git" || fail "RF17: a hook the git user cannot reach was accepted" "rc=$(_rv rf17_rc) $(_rctx rf17)"
    { [ "$(_rv rf18_rc)" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=transport_pin_mismatch' "$T/rt/out/rf18.out"; } \
      && pass "RF18: the REAL transport wrapper, installed without its command-line pin -> reason=transport_pin_mismatch (R5a proves the unmodified wrapper satisfies the probe)" || fail "RF18: a wrapper without its pin was accepted" "rc=$(_rv rf18_rc) $(_rctx rf18)"
    { [ "$(_rv rvm_rc)" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-verified verdict=store_unverified reason=marker_mismatch' "$T/rt/out/rvm.out" \
      && ! grep -qF '4f1c2a9e-7b3d-4e8a-9c6f-2d5b8a1e0c73' "$T/rt/out/rvm.out" && ! grep -qF '9a2e6c14-3b7f-4d91-8e05-c6f1a2b3d4e7' "$T/rt/out/rvm.out"; } \
      && pass "RVM: real OpenSSH, a marker naming another filesystem -> store_unverified reason=marker_mismatch; neither the UUID nor the marker bytes reach the output" || fail "RVM: an unbound marker was accepted, or a captured value was printed" "rc=$(_rv rvm_rc) $(_rctx rvm)"
    { [ "$(_rv rvm2_rc)" = 0 ] && _sto rvm2 store-verified ok; } \
      && pass "RVM2: the canonical host right after RVM clears — the trap restored the marker" || fail "RVM2: the canonical host did not clear after RVM" "rc=$(_rv rvm2_rc) $(_rctx rvm2)"
  elif grep -qx FIXTURE_PIN_FAILED "$T/rt/stdout"; then
    fail "runtime arm: the fixture host-key pins could not be written by write-known-hosts.sh" "$(tail -5 "$T/rt/stdout" | tr '\n' ' ' | sed 's/::/: :/g')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  elif grep -qx FIXTURE_APT_FAILED "$T/rt/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$T/rt/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$T/rt/stdout" | tr '\n' ' ' | sed 's/::/: :/g')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER (ADR-193: reported with printf + exit, never through pass()/fail()) ─────
# Both checks are EXACT (-ne): a floor below the count it measures is slack a deletion can spend,
# and every skip path adds RUNTIME_ROWS, so the totals are the same in every environment (under
# CI, -ne also proves RUNTIME_ROWS equals the runtime rows that actually ran).
# MUTANT_FLOOR, computed from the matrices before it was measured (#8211 PR2 proof half, restated at
# code review): the 47 rows before it (Guard 2 x4, Guard 5 x4, Guard 6 x1, Guard 7 x3, C1 x1, C3 x2,
# C7 x4, Fence x19, H4 x9), less g2-no-cut-over (now Guard 1 row 2) and c3-no-source-identity (now
# Guard 2 row 13); g5-raw-capture, c3-missing-as-zero, f-m2, f-m16 and f-m17 were re-anchored, each
# counted once = 45. Plus Guard 1 rows 1-6 and its harness row = 7; config rows 1-4 = 4; Guard 2
# rows 1-17 = 17 plus 4 harness rows plus the count-parity row = 22; RB rows 1-6 = 6; P3 rows 1-7 = 7.
# Total 91, measured 91 on the first run after the runtime arm was final. Guard 3's four rows live
# with the census in tests/scripts/test-git-data-root-token-census.sh. #8211 (notify-failure plan):
# plus g2n-1..6, 8 (the notify job, 7 rows), g3p-1..2 (the probe step) and fz1-5, nb1-4 (the EXECUTED finalizer
# and notify body) and g2n-9..14 (the notify wiring) = 24, so exactly 115.
MUTANT_FLOOR=115
if [ "$MUTANTS_RUN" -ne "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: %s mutants executed, the floor is exactly %s — a matrix row did not land, was deleted, or was added without restating the floor.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR, restated from a measured run after the #8211 PR2 proof half's code review:
# mutants 91 x 2 = 182; runtime 27 (RFSRC deleted; RVM and RVM2 added); everything else 279 — the
# script's unit rows (access gate, H4, AC2, CFG x11, Guard 1, Guard 2 incl. the canned V/VE rows and
# the executed VX and count rows, the MM rows, the fence probe, MZ-P/L/V/U/F/RA/RB, RB, Guard 5,
# Guard 7), the bridge export set, the 50 workflow YAML verdicts and the executed workflow steps.
# Total 488 — exact, not a margin: removing or adding an assertion on purpose costs one edit here.
# #8211 (notify-failure plan) after code review: 115 mutants x 2 = 230 (the base above counted 91 x 2), the
# workflow YAML verdicts 38 -> 50 (N-if, N-jobkeys, N-secrets, N-secrets-form, N-order, N-body, N-exprs,
# N-refs, N-outputs, N-finalizer, N-probe), plus the executed NB and FZ rows (2): 517 -> 549, measured.
FLOOR=549
_ran=$((passes + fails + SKIPPED))
if [ "$_ran" -ne "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran/declared, the floor is exactly %s — cases were deleted, added without restating the floor, skipped, or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-cutover-access: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
