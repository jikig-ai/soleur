#!/usr/bin/env bash
#
# git-data cutover — the READ-ONLY PROOF (epic #5274 / ADR-068 / ADR-220 / ADR-239).
#
# WHAT THIS SCRIPT DOES TODAY. It proves, without changing anything on any host, that the
# reviewer-gated cutover job can reach root on the git-data host and that the store is in the
# state ADR-239 renders and a flag flip would start from:
#   1. access_gate (ADR-220): web-1 answers, `ssh -W` through web-1 reaches git-data's sshd,
#      and root on git-data accepts the root key. Any non-ok verdict exits 3.
#   2. the configuration check, then the store probes, each fail-closed; every remote read goes
#      through gd_capture:
#        refuse_if_config_unsafe      OLD_ROOT, REPO_SUBDIR, STORE_VERIFIED, LUKS_MAPPER and
#                                     TRANSPORT_WRAPPER are safe literals, BEFORE any of them is
#                                     printed or dialed (probe=config, probe_failed reason=arg_*)
#        refuse_if_unmounted          `findmnt --mountpoint $OLD_ROOT` must name a /dev/ device
#        refuse_if_not_on_mapper      ...and that device must be $LUKS_MAPPER (ADR-239 D1: the
#                                     render never serves anything else). A local comparison.
#        refuse_if_store_unverified_or_not_empty
#                                     in ONE ssh session, so every fact is read at one instant:
#                                     the store is still served by that device; the freeze
#                                     sentinel $OLD_ROOT/.cutover-freeze is absent; the mounted
#                                     filesystem has a UUID; $STORE_VERIFIED (the wrappers'
#                                     marker, ADR-239 D3) is a non-empty file whose first line is
#                                     that UUID; $OLD_REPOS is a directory whose containing mount
#                                     is $OLD_ROOT (the wrappers' `stat -c %m` check); and it holds
#                                     no entry at all except the provision/remove lock dotfiles
#                                     and lost+found (the bootstrap's own `_repo_count` rule).
#                                     It emits two lines, probe=store-verified and
#                                     probe=store-empty, each exit code attributed to its stage.
#      A refusal exits 5 with a fixed verdict word. A read that could not be completed
#      (transport, timeout, oversized or multi-line answer) is `probe_failed rc=<n>`, never
#      a store-state verdict. The store-verified words:
#        store_unverified reason=no_fs_uuid       the mounted filesystem reports no UUID
#        store_unverified reason=marker_absent    no marker, an empty one, or not a file
#        store_unverified reason=marker_mismatch  the marker names another filesystem
#        cutover_frozen                           the freeze sentinel exists
#        probe_failed rc=5|6|16                   findmnt failed | the source changed or was
#                                                 over-mounted since store-mounted | head failed
#      and the store-empty words: store_not_empty, or probe_failed rc=3|4|7|8|9|96 (see the
#      function). Every store_unverified verdict means every store wrapper refuses on the host
#      now; cutover_frozen means provision, remove, the transport wrapper and pre-receive do
#      (gc does not read the sentinel). The probes read as root while the wrappers run as git,
#      so a permission fault can make the wrappers refuse where this proof passes: the proof is
#      never STRICTER than the wrappers. The git-user path is attested separately, by the
#      bootstrap's boot_complete erasure_probe=yes and by the fence probe's runuser checks.
#   3. the fence probe (#8101), refuse_if_fence_not_intact: the pre-receive fence the bootstrap
#      plants is a real root:git 750 hooks directory under a root-owned, non-writable parent,
#      holding a real root:root 755 pre-receive the git user can run; the installed transport
#      wrapper pins pushes to it and the system core.hooksPath names it; and it sits on the
#      accepted store device. It checks the fence's SHAPE, not which hook is installed.
# Exit 0 means: access ok; the store is served by the LUKS mapper with the bootstrap's store
# marker bound to its filesystem; it is not frozen; its repositories directory holds no entry
# (lock dotfiles and lost+found excepted, as in the bootstrap's `_repo_count`); and a push
# would run a root-owned pre-receive of the planted shape. It does NOT determine when
# encryption at rest became active for the Art. 30 register; that determination is #8634's.
#
# WHAT IT NO LONGER DOES. The rsync / freeze / repoint / flag-flip / rollback / wipe body was
# deleted (git history keeps it). Its freeze and reload called systemd units that do not
# exist on either host, and a second run after a repoint could rsync a store onto itself.
# #8211 is split in two (ADR-239). PR1 moved the store itself: the git-data render serves the
# LUKS mapper at /mnt/git-data from boot and the bootstrap plants the fence on it. There is
# nothing to copy, because the store has never held a repository.
#
# MODES (#8211 PR2). MODE selects the verb — proof (default), freeze, unfreeze, probe.
# The flag write and the fleet redeploy are WORKFLOW steps, not script verbs: this script
# reads no secret store and the webhook credentials never reach it. Host-side mode mapping:
#   workflow flip     -> precheck(flip) -> preconditions -> MODE=freeze -> flag write ->
#                        track.sh -> per-host git_data_store= readback -> MODE=unfreeze ->
#                        MODE=probe -> GIT_DATA_LUKS_CUTOVER_AT
#   workflow rollback -> precheck(rollback) -> flag write off -> track.sh -> off-line
#                        readback -> MODE=unfreeze (clears only a same-lineage sentinel)
#   workflow unfreeze -> MODE=unfreeze
#   workflow redeploy -> track.sh only (no host-side verb)
# DRY_RUN/ROLLBACK/CONFIRM_WIPE are the superseded PR1 interface; non-default values are
# still refused (verdict=real_cutover_unreconciled) so a stale dispatch cannot wedge the
# new dispatch behind a silent no-op. MODE=proof is what DRY_RUN=1 was.
#
# NO DOPPLER. The flag read moved to its own workflow step (git-data-flag-precheck.sh) so the
# `prd` read token never reaches the process that handles host bytes. This script reads no
# secret store and receives no Doppler token.
#
# ACCESS PATH (ADR-220, #6680). The bridge exports WEB_HOST_SSH (root on web-1). git-data
# (10.0.1.20) has no ingress of its own: it is reached through web-1 as an `ssh -W`
# direct-tcpip channel, authenticating end to end, so no key and no agent socket lands on
# web-1. The workflow supplies GIT_DATA_SSH as `ssh -F <ssh_config>`, whose git-data block
# carries the root key and the literal ProxyCommand through web-1. There are no `ssh`
# fallbacks: an unset invocation fails closed instead of dialing a bare `ssh`.
#
# HOST KEYS (#7226, ADR-237). Both hops are pinned: the bridge's WEB_HOST_SSH trusts only web-1's
# committed ECDSA key, and the workflow's ssh_config trusts web-1's key for the jump and
# git-data's Terraform-minted ED25519 key for the git-data hop, each under a fixed HostKeyAlias.
# A host-key failure is its own verdict, host_key_mismatch, with a reason word (see
# _access_reason, plan H4).
#
# CAPTURED VALUES (P8). gd_capture bounds every remote read (30 s, 4096 bytes), accepts a value
# only when it matches an anchored pattern in full, and never prints the value. A pinned host
# key authenticates the host, not the answer's truth: a compromised web-1 or git-data can still
# answer "mounted, empty", so the bounds stay.
#
# Exit codes: 0 clear; 1 internal error (die: the access gate's mktemp failed); 3 access gate;
# 5 refusal — all mode/probe verdicts (store probes, fence probe, freeze/unfreeze/probe
# verbs, mode_invalid, lineage_absent, frozen_*, lock_held, FREEZE_HELD); 78 xtrace refusal.
set -euo pipefail
# Every regex below is a byte-class check; a UTF-8 locale would widen [A-Za-z] to letters beyond ASCII.
export LC_ALL=C
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

log()  { echo "[git-data-cutover] $*"; }
step() { echo; echo "[git-data-cutover] ===== $* ====="; }
die()  { echo "[git-data-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (all overridable by the workflow; documented defaults) -----
GIT_DATA_HOST="${GIT_DATA_HOST:-10.0.1.20}"
OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"                 # the store root every wrapper hardcodes (LUKS-served since ADR-239)
LUKS_MAPPER="${LUKS_MAPPER:-/dev/mapper/git-data}"    # the device that must serve the store
# The wrappers' positive store marker (ADR-239 D3): bootstrap, gc, provision, remove and the
# transport wrapper default it identically, and its only writer is git-data-bootstrap.sh step 5a.
# The wrappers' GIT_DATA_STORE_VERIFIED override is host-side and invisible here.
STORE_VERIFIED="${STORE_VERIFIED:-/etc/git-data/store-verified}"
REPO_SUBDIR="${REPO_SUBDIR:-repositories}"
OLD_REPOS="${OLD_ROOT}/${REPO_SUBDIR}"
WEB_HOSTS="${WEB_HOSTS:-10.0.1.10}"   # web-1 only: the read-only proof needs one jump host, not every web host

# --- Roster + invocations: parsed ONCE, used by the gate AND every later call ---
# One parse (`read -ra`: first line only, no glob expansion) so the addresses and argv the
# access gate proves are byte-for-byte the ones the store probes later dial. A value that
# is multi-line or not dotted-numeric is recorded, never dialed: an address starting with
# `-` would become an ssh option. Not an exit here — the access gate reports it as a verdict.
WEB_HOST_LIST=()
ROSTER_ERR_ROLE=""    # "" when valid; otherwise the role whose input is malformed
ROSTER_ERR_VERDICT=""
resolve_roster() {
  local h
  case "${WEB_HOSTS}${GIT_DATA_HOST}${WEB_HOST_SSH:-}${GIT_DATA_SSH:-}" in
    *$'\n'*) ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_multiline_input; return 0 ;;
  esac
  read -ra WEB_HOST_LIST <<< "$WEB_HOSTS"
  for h in "${WEB_HOST_LIST[@]}"; do
    if ! [[ "$h" =~ ^[0-9.]+$ ]]; then
      WEB_HOST_LIST=(); ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_host; return 0
    fi
  done
  if ! [[ "$GIT_DATA_HOST" =~ ^[0-9.]+$ ]]; then
    ROSTER_ERR_ROLE=git-data-jump; ROSTER_ERR_VERDICT=invalid_host
  fi
}

# --- Temp state (read by the EXIT trap) ---------------------------------------
ACCESS_TMP=""       # probe capture dir of the access gate; removed on every exit
CAPTURE_TMP=""      # stderr capture dir of gd_capture; removed on every exit
GD_CAPTURED=""      # the last value gd_capture ACCEPTED; never printed

# The trap only drops temp captures: nothing on any host is ever changed, so nothing is
# ever recovered.
cleanup() {
  local rc=$?
  trap - EXIT
  _access_tmp_drop || true
  _capture_tmp_drop || true
  exit "$rc"
}
trap cleanup EXIT

# ============================================================================
# MODE dispatch (#8211 PR2) — the host-side verbs the workflow orchestrates
# ============================================================================
# MODE selects one host-side verb; the flag write, the fleet redeploy and the flag
# read-back are WORKFLOW steps (this script reads no secret store — the contract stands).
#   proof     (default, DRY_RUN=1): the read-only probe chain above.
#   freeze    assert git-data-gc.service inactive -> stop git-data-gc.timer -> write
#             $OLD_ROOT/.cutover-freeze with `writer=<lineage> at=<epoch>` provenance ->
#             purge legacy .<id>.init.lock residue inside the freeze window.
#   unfreeze  read the sentinel; clear it ONLY when its writer lineage equals
#             CUTOVER_LINEAGE -> restart gc.timer. Refuses frozen_unattributed (a sentinel
#             nobody wrote is a host incident, not a cleanup target) and frozen_foreign.
#   probe     the positive replication probe: provision + fenced push + remove of a
#             synthetic id (cutover-probe-<lineage>), leaving zero residue.
# The legacy arm still stands for DRY_RUN!=1/CONFIRM_WIPE!=0 (the wipe is a later PR);
# ROLLBACK=1 maps to MODE=rollback at the WORKFLOW level, not here.
MODE="${MODE:-proof}"
case "$MODE" in
  proof|freeze|unfreeze|probe) : ;;
  *) log "REFUSE verdict=mode_invalid mode=${MODE}"
     echo "::error title=git-data-cutover::verdict=mode_invalid"
     exit 5 ;;
esac
CUTOVER_LINEAGE="${CUTOVER_LINEAGE:-}"
FREEZE_SENTINEL="${OLD_ROOT}/.cutover-freeze"
# The sentinel carries parseable provenance — `writer` names the run lineage the
# workflow stamps (github.run_id) and `at` the host's epoch at write. Writers that
# cannot stamp both fields refuse before touching the store.
LINEAGE_RE='^[A-Za-z0-9._-]{1,64}$'

refuse_legacy_modes() {
  local bad=""
  [ "${DRY_RUN:-1}" = 1 ] || bad="${bad} DRY_RUN"
  [ "${ROLLBACK:-0}" = 0 ] || bad="${bad} ROLLBACK"
  [ "${CONFIRM_WIPE:-0}" = 0 ] || bad="${bad} CONFIRM_WIPE"
  [ -n "$bad" ] || return 0
  log "REFUSE verdict=real_cutover_unreconciled vars=${bad# }"
  echo "::error title=git-data-cutover::verdict=real_cutover_unreconciled"
  log "remedy: MODE selects the verb (proof|freeze|unfreeze|probe); the wipe remains a later PR (#8211)."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- REFUSE verdict=real_cutover_unreconciled\n' >> "$GITHUB_STEP_SUMMARY" || true
  fi
  exit 5
}

# --- gd_exec: one bounded remote WRITE/exec (the write twin of gd_capture) ------
# gd_exec <remote-cmd>: runs it over GIT_DATA_SSH, bounded like gd_capture (30 s, stdin
# /dev/null), and returns ssh's own rc. stdout is discarded — a write verb has no answer
# to accept, and a hostile host's bytes never reach this script's stdout.
gd_exec() {
  local rc=0
  local -a inv
  read -ra inv <<< "${GIT_DATA_SSH:-}"
  [ "${#inv[@]}" -gt 0 ] || return 97
  if [ -z "$CAPTURE_TMP" ]; then CAPTURE_TMP="$(mktemp -d)" || return 95; fi
  : > "$CAPTURE_TMP/capture.err" || return 95
  timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" "$1" \
    </dev/null >/dev/null 2>"$CAPTURE_TMP/capture.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    _access_stderr "$CAPTURE_TMP/capture.err"
  fi
  return "$rc"
}

# --- freeze provenance (host-side; the sentinel's only writer/reader) -----------
# freeze_probe: ONE ssh session answers existence + provenance. Remote exits:
#   0 absent | 2 present+unparseable (frozen_unattributed) | 3 present+UNREADABLE
#   (frozen_unreadable — an I/O fault, not a provenance verdict)
freeze_state=""   # absent|ours|foreign|unattributed|unreadable
freeze_detail=""  # writer + age when parseable
probe_freeze() {
  local rc=0 qs ql cmd
  printf -v qs '%q' "$FREEZE_SENTINEL"
  printf -v ql '%q' "$CUTOVER_LINEAGE"
  cmd="fz=$qs; lin=$ql
    if [ ! -e \"\$fz\" ]; then echo absent; exit 0; fi
    c=\$(head -n 1 \"\$fz\" 2>/dev/null) || exit 3
    w=\$(printf '%s' \"\$c\" | sed -n 's/^writer=\([^ ]*\).*/\1/p')
    a=\$(printf '%s' \"\$c\" | sed -n 's/.* at=\([0-9]*\)$/\1/p')
    [ -n \"\$w\" ] && [ -n \"\$a\" ] || exit 2
    if [ \"\$w\" = \"\$lin\" ]; then echo \"ours writer=\$w at=\$a\"; else echo \"foreign writer=\$w at=\$a\"; fi"
  gd_capture '^(absent|ours writer=[A-Za-z0-9._-]+ at=[0-9]+|foreign writer=[A-Za-z0-9._-]+ at=[0-9]+)$' "$cmd" || rc=$?
  case "$rc" in
    0) ;;
    2) freeze_state=unattributed; return 0 ;;
    3) freeze_state=unreadable; return 0 ;;
    *) _store_refuse freeze-state probe_failed "$rc" ;;
  esac
  case "$GD_CAPTURED" in
    absent) freeze_state=absent ;;
    ours*)  freeze_state=ours ;;
    foreign*) freeze_state=foreign ;;
  esac
  freeze_detail="${GD_CAPTURED#* }"
}

# ============================================================================
# gd_capture — one bounded, pattern-validated remote read on git-data (D-7)
# ============================================================================
# gd_capture <anchored-regex> <remote-cmd>: runs the command over GIT_DATA_SSH with a 30 s
# bound, refuses more than 4096 bytes of stdout, takes ssh's own rc (PIPESTATUS[0], not the
# pipeline's), strips ONE trailing newline, and accepts the value only when it matches the
# pattern in full. A multi-line value never matches. On success GD_CAPTURED holds the value;
# on failure it is empty and the return is ssh's rc, or 96 on a mismatch. The value is never
# printed; a failed read's stderr goes out capped and filtered through _access_stderr.
_capture_tmp_drop() {
  [ -n "$CAPTURE_TMP" ] || return 0
  rm -f "$CAPTURE_TMP/capture.err"
  rmdir "$CAPTURE_TMP" || return 1
  CAPTURE_TMP=""
}
gd_capture() {
  local pat="$1" cmd="$2" rc=0 val=""
  local -a inv
  GD_CAPTURED=""
  read -ra inv <<< "${GIT_DATA_SSH:-}"
  [ "${#inv[@]}" -gt 0 ] || return 97
  if [ -z "$CAPTURE_TMP" ]; then CAPTURE_TMP="$(mktemp -d)" || return 95; fi
  : > "$CAPTURE_TMP/capture.err" || return 95
  # One byte past the cap is read so an oversized answer is refused, never truncated into a
  # value that happens to match. The trailing '.' keeps $(...) from eating newlines.
  val="$(timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" "$cmd" </dev/null 2>"$CAPTURE_TMP/capture.err" | head -c 4097
    st=("${PIPESTATUS[@]}"); printf '.'; exit "${st[0]}")" || rc=$?
  val="${val%.}"
  if [ "$rc" -ne 0 ]; then
    _access_stderr "$CAPTURE_TMP/capture.err"
    return "$rc"
  fi
  [ "${#val}" -le 4096 ] || return 96
  val="${val%$'\n'}"
  case "$val" in
    *$'\n'*) return 96 ;;
  esac
  if ! [[ "$val" =~ $pat ]]; then
    _access_stderr "$CAPTURE_TMP/capture.err"
    return 96
  fi
  GD_CAPTURED="$val"
}

# ============================================================================
# access_gate — every host reachable and authorized BEFORE any store probe (ADR-220)
# ============================================================================
# Three probes, strictly ordered; each runs only after the previous one read ok:
#   web            every roster member runs `true` over WEB_HOST_SSH.
#   git-data-jump  `ssh -W <git-data>:22 <first roster member>` must return an `SSH-2.0-`
#                  line FIRST: web-1's sshd forwards and something answers as an sshd, with
#                  NO git-data credential (liveness, not authenticity — #7226). The verdict
#                  keys on that line, never the pipeline rc, which is ssh's own exit status.
#                  stdin is /dev/null: its EOF makes the remote close right after the banner;
#                  with stdin held open the probe waits out its timeout.
#   git-data-auth  root login over GIT_DATA_SSH; unset -> git_data_root_key_absent (#8189).
# Non-ok exits 3 from THIS body. Keep the call a plain statement: inside $(...) or a
# pipeline its `exit 3` would only leave a subshell and the store probes would run anyway.
# ssh error output is HOSTILE: a compromised web-1 (or the edge) controls the jump hop's banner
# and error text, and the runner parses workflow commands on stdout AND stderr. So:
#   - every probe writes to a file, and the -W line is only compared;
#   - the verdict comes from ssh's exit code plus LINE-ANCHORED patterns over the cleaned text
#     (_access_reason), never from a free substring such as a `verdict=` in that text;
#   - before anything is echoed, every byte outside printable ASCII is stripped (_access_clean):
#     control characters, DEL (\x7f), and multi-byte sequences such as U+2028 / U+2029;
#   - a failed probe's cleaned stderr is printed capped, behind a fixed prefix, inside a
#     ::stop-commands:: span keyed on a per-run random token, so an embedded ::error:: or
#     ::add-mask:: cannot become a workflow command.
# A failure's verdict and reason= are fixed words, never probe bytes.
# ssh keeps the FIRST value of a repeated -o, so the appended options can add, never override.
_access_emit() { # <role> <host> <verdict> [rc] [reason]
  local detail="role=$1 host=$2 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  log "ACCESS ${detail}"
  if [ "$3" = ok ]; then
    echo "::notice title=git-data-cutover access::role=$1 verdict=ok"
  else
    echo "::error title=git-data-cutover access::role=$1 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- ACCESS %s\n' "$detail" >> "$GITHUB_STEP_SUMMARY" || true
  fi
}
_access_clean() { # <captured-stderr-file> — capped, printable ASCII and newlines only
  head -c 8192 "$1" | LC_ALL=C tr -cd '\12\40-\176'
}
# <rc> <captured-stderr-file> -> "<verdict> <reason>". H4 (host identity, #7226) first, in plan
# order and only on ssh's own exit code 255, all ahead of Permission denied (H3):
#   alg      the host offers no key of the pinned algorithm
#   unknown  no pin for the alias (a typo'd HostKeyAlias or an empty known_hosts: a config bug)
#   changed  the host presented a key other than the pin
# Remedy (runbook H4): a wrong web-1 capture -> re-capture PR; git-data re-keyed outside the
# replace job -> replace dispatch; neither -> breach-notice triage. Never re-enable TOFU.
_access_reason() {
  local t
  t="$(_access_clean "$2")"
  if [ "$1" = 124 ]; then echo "failed timeout"
  elif [ "$1" = 255 ] && grep -qE '^Unable to negotiate with .+: no matching host key type found' <<< "$t"; then echo "host_key_mismatch alg"
  elif [ "$1" = 255 ] && grep -qE '^No [A-Za-z0-9-]+ host key is known for ' <<< "$t"; then echo "host_key_mismatch unknown"
  elif [ "$1" = 255 ] && grep -qE '^(@ +WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! +@|Host key verification failed\.)$' <<< "$t"; then echo "host_key_mismatch changed"
  elif grep -qE '^channel [0-9]+: open failed: administratively prohibited' <<< "$t"; then echo "failed forward_refused"
  elif grep -qE '^(ssh: connect to host [^ ]+ port [0-9]+|channel [0-9]+: open failed: connect failed): Connection refused$' <<< "$t"; then echo "failed connect_refused"
  elif grep -qE '^(ssh: connect to host [^ ]+ port [0-9]+|channel [0-9]+: open failed: connect failed): No route to host$' <<< "$t"; then echo "failed no_route"
  elif grep -qE '^[^ ]+: Permission denied \(' <<< "$t"; then echo "failed auth_refused"
  else echo "failed unknown"
  fi
}
_access_fail() { # <role> <host> <rc> <captured-stderr-file> — emit, dump, stop
  local vr
  vr="$(_access_reason "$3" "$4")"
  _access_emit "$1" "$2" "${vr%% *}" "$3" "${vr#* }"
  _access_stderr "$4"
  exit 3
}
_access_stderr() { # <captured-stderr-file>
  [ -s "$1" ] || return 0
  local tok l
  tok="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  echo "::stop-commands::${tok}"
  _access_clean "$1" | while IFS= read -r l || [ -n "$l" ]; do
    printf '[git-data-cutover] probe-stderr: %s\n' "$l"
  done
  echo "::${tok}::"
}
# Removes ONLY the gate's three named captures, then the directory itself: the EXIT trap reads
# a global it did not bind, so nothing here may recurse into whatever that global holds.
_access_tmp_drop() {
  [ -n "$ACCESS_TMP" ] || return 0
  rm -f "$ACCESS_TMP/web.err" "$ACCESS_TMP/jump.err" "$ACCESS_TMP/auth.err"
  rmdir "$ACCESS_TMP" || return 1
  ACCESS_TMP=""
}
access_gate() {
  step "access gate (ADR-220): web -> git-data-jump -> git-data-auth, before any store probe"
  local h rc first
  local -a inv gdinv
  if [ -n "$ROSTER_ERR_ROLE" ]; then _access_emit "$ROSTER_ERR_ROLE" "<invalid>" "$ROSTER_ERR_VERDICT"; exit 3; fi
  read -ra inv <<< "${WEB_HOST_SSH:-}"
  if [ "${#inv[@]}" -eq 0 ]; then _access_emit web "-" web_host_ssh_unset; exit 3; fi
  if [ "${#WEB_HOST_LIST[@]}" -eq 0 ]; then _access_emit web "-" web_roster_empty; exit 3; fi
  ACCESS_TMP="$(mktemp -d)" || die "access gate: mktemp failed"

  for h in "${WEB_HOST_LIST[@]}"; do
    rc=0
    timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$h" true \
      </dev/null >/dev/null 2>"$ACCESS_TMP/web.err" || rc=$?
    [ "$rc" -eq 0 ] || _access_fail web "$h" "$rc" "$ACCESS_TMP/web.err"
    _access_emit web "$h" ok
  done

  rc=0
  first="$(timeout 25 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 -W "${GIT_DATA_HOST}:22" "${WEB_HOST_LIST[0]}" \
    </dev/null 2>"$ACCESS_TMP/jump.err" | head -n 1)" || rc=$?
  first="${first%$'\r'}"
  case "$first" in
    SSH-2.0-*) _access_emit git-data-jump "$GIT_DATA_HOST" ok ;;
    *) _access_fail git-data-jump "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/jump.err" ;;
  esac

  read -ra gdinv <<< "${GIT_DATA_SSH:-}"
  if [ "${#gdinv[@]}" -eq 0 ]; then
    _access_emit git-data-auth "$GIT_DATA_HOST" git_data_root_key_absent
    log "remedy: no root credential reached this step — dispatch apply-git-data-root-key.yml (it mints the key and publishes its read token), then re-dispatch (ADR-220)."
    exit 3
  fi
  rc=0
  timeout 30 "${gdinv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" true \
    </dev/null >/dev/null 2>"$ACCESS_TMP/auth.err" || rc=$?
  [ "$rc" -eq 0 ] || _access_fail git-data-auth "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/auth.err"
  _access_emit git-data-auth "$GIT_DATA_HOST" ok
  _access_tmp_drop
}

# ============================================================================
# Store probes (D-5) — each fails closed with a fixed verdict word, exit 5
# ============================================================================
_store_emit() { # <probe> <verdict> [rc] [reason] — pass "" for rc when a reason has no rc
  local detail="probe=$1 verdict=$2${3:+ rc=$3}${4:+ reason=$4}"
  log "STORE ${detail}"
  if [ "$2" = ok ]; then
    echo "::notice title=git-data-cutover store::probe=$1 verdict=ok"
  else
    echo "::error title=git-data-cutover store::${detail}"
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- STORE %s\n' "$detail" >> "$GITHUB_STEP_SUMMARY" || true
  fi
}
_store_refuse() { # <probe> <verdict> [rc] [reason] — emit, stop
  _store_emit "$@"
  exit 5
}

# The capture pattern admits any one-line findmnt SOURCE shape (device, tmpfs, bind `[..]`,
# host:/export, or empty), so gd_capture's 96 means only "the answer could not be read as one
# line" and is reported with the transport failures. The device test is a separate local match.
#   rc 0 + a /dev/ source   ok
#   rc 0 + any other answer old_store_unmounted             (a non-device source, or none)
#   rc 1                    old_store_unmounted rc=1        (findmnt's own "no such mount")
#   any other rc            probe_failed rc=<n>             (124 timeout, 255 ssh, 141 SIGPIPE,
#                                                            96 unreadable answer, 95/97 local)
STORE_SOURCE=""
refuse_if_unmounted() {
  step "store probe: $OLD_ROOT is mounted on a device"
  local rc=0 q
  printf -v q '%q' "$OLD_ROOT"
  gd_capture '^[][A-Za-z0-9/_.:@+=-]*$' "findmnt -n -o SOURCE --mountpoint $q" || rc=$?
  case "$rc" in
    0) ;;
    1) _store_refuse store-mounted old_store_unmounted "$rc" ;;
    *) _store_refuse store-mounted probe_failed "$rc" ;;
  esac
  [[ "$GD_CAPTURED" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse store-mounted old_store_unmounted
  STORE_SOURCE="$GD_CAPTURED"
  _store_emit store-mounted ok
}

# The configuration check. Every configurable path the probes print or send to git-data is a safe
# literal BEFORE the first `step` line or remote read, so no value can become a workflow command on
# stdout or an option/metacharacter on the remote side. The fence probe keeps its own argument
# checks, because it is also called with explicit arguments (the #8211 fresh-root reuse).
refuse_if_config_unsafe() {
  [[ "$OLD_ROOT" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse config probe_failed "" arg_root
  [[ "$REPO_SUBDIR" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || _store_refuse config probe_failed "" arg_subdir
  [[ "$STORE_VERIFIED" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse config probe_failed "" arg_marker
  [[ "$LUKS_MAPPER" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse config probe_failed "" arg_mapper
  [[ "$TRANSPORT_WRAPPER" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse config probe_failed "" arg_wrapper
}

# ADR-239 D1: the render serves $LUKS_MAPPER at the store root from boot, so any other device
# there is an incident, never a state to proceed from.
refuse_if_not_on_mapper() {
  step "store probe: $OLD_ROOT is served by the LUKS mapper"
  [ -n "$STORE_SOURCE" ] || _store_refuse store-on-mapper probe_failed
  [ "$STORE_SOURCE" = "$LUKS_MAPPER" ] || _store_refuse store-on-mapper store_not_on_mapper
  _store_emit store-on-mapper ok
}

# The pass rests on the bootstrap's evidence, never on the absence of a refusal, and every fact is
# read in ONE ssh session so no fact can change between two reads. The session exits with the first
# failure; the exit code names the stage and the verdict:
#   store-verified
#    5  findmnt could not read the source or the UUID           probe_failed rc=5
#    6  the source is not the one store-mounted accepted
#       (it changed, or a second mount is stacked on the root)  probe_failed rc=6
#   23  the freeze sentinel exists                              cutover_frozen
#   24  the mounted filesystem reports no UUID                  reason=no_fs_uuid
#   21  the marker is absent, empty, or not a file              reason=marker_absent
#   16  head could not read the marker                          probe_failed rc=16
#   22  the marker's first line is not that UUID                reason=marker_mismatch
#   store-empty (reached only after every store-verified fact held)
#    3  $OLD_REPOS is a dangling symlink, or not a directory    probe_failed rc=3
#    7  $OLD_REPOS is missing (the bootstrap always creates it) probe_failed rc=7
#    9  readlink or stat could not resolve it                   probe_failed rc=9
#    8  its containing mount is not $OLD_ROOT (a second mount
#       on repositories/ would hide what lies under it)         probe_failed rc=8
#    4  find failed                                             probe_failed rc=4
# The only output is the entry count, printed last, so rc 0 means every check above held. Any
# other rc (gd_capture's own, transport, timeout) is probe_failed under store-verified; a
# malformed answer (96) on rc 0 can only be the count, so it is probe_failed under store-empty.
# The freeze is read before the marker: a frozen store is refused as frozen, whatever its marker.
# The marker and freeze tests follow symlinks as the wrappers' `[ -s ]`, `head -n 1` and `[ -e ]`
# do; the extra `[ -f ]` only names a non-file marker marker_absent (the wrappers refuse it too).
# The count is the bootstrap's `_repo_count` rule: every direct entry, not only `*.git`, since a
# partial `x/` is user data too. `find -H` follows a symlinked $OLD_REPOS itself, never the
# entries under it. The prefix is plain %q assignments; every other element is single-quoted, so
# nothing expands on the runner.
refuse_if_store_unverified_or_not_empty() {
  local rc=0 reason="" cmd qr qs qm qd
  local -a c
  [[ "$STORE_SOURCE" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse store-verified probe_failed
  step "store probes: the bootstrap's store marker is bound to $OLD_ROOT, it is not frozen, and $OLD_REPOS holds nothing"
  printf -v qr '%q' "$OLD_ROOT"
  printf -v qs '%q' "$STORE_SOURCE"
  printf -v qm '%q' "$STORE_VERIFIED"
  printf -v qd '%q' "$OLD_REPOS"
  c=(
    "r=$qr; src=$qs; mk=$qm; d=$qd"
    'fz="$r/.cutover-freeze"'
    's=$(findmnt -n -o SOURCE --mountpoint "$r") || exit 5'
    '[ "$s" = "$src" ] || exit 6'
    '[ ! -e "$fz" ] || exit 23'
    'fu=$(findmnt -n -o UUID --mountpoint "$r") || exit 5'
    '[ -n "$fu" ] || exit 24'
    '[ -f "$mk" ] && [ -s "$mk" ] || exit 21'
    'm=$(head -n 1 "$mk") || exit 16'
    '[ "$m" = "$fu" ] || exit 22'
    'if [ -L "$d" ] && [ ! -e "$d" ]; then exit 3; fi'
    'if [ ! -e "$d" ]; then exit 7; fi'
    '[ -d "$d" ] || exit 3'
    'dr=$(readlink -f "$d") && rr=$(readlink -f "$r") && t=$(stat -c %m "$dr") || exit 9'
    '[ "$t" = "$rr" ] || exit 8'
    "n=\$(find -H \"\$d\" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name '.init.lock' ! -name lost+found -printf .) || exit 4"
    'echo "${#n}"'
  )
  printf -v cmd '%s; ' "${c[@]}"
  gd_capture '^[0-9]+$' "${cmd%; }" || rc=$?
  case "$rc" in
    0|3|4|7|8|9|96) ;;
    21) reason=marker_absent ;;
    22) reason=marker_mismatch ;;
    24) reason=no_fs_uuid ;;
    23)
      # A held sentinel refuses the proof — EXCEPT a same-lineage one, which only
      # this run's own earlier attempt could have written (freeze runs strictly
      # after a passed proof, so a re-run proving again would re-derive nothing).
      # This is flip resume arm A: `gh run rerun` reuses run_id, hence lineage.
      probe_freeze
      if [ "$freeze_state" = "ours" ]; then
        _store_emit store-verified ok "" resume_same_lineage
        log "resume arm A: same-lineage freeze from this run's earlier attempt — proof already discharged, resuming"
        return 0
      fi
      _store_refuse store-verified cutover_frozen ;;
    *) _store_refuse store-verified probe_failed "$rc" ;;
  esac
  [ -z "$reason" ] || _store_refuse store-verified store_unverified "" "$reason"
  _store_emit store-verified ok
  [ "$rc" -eq 0 ] || _store_refuse store-empty probe_failed "$rc"
  [[ "$GD_CAPTURED" =~ ^0+$ ]] || _store_refuse store-empty store_not_empty
  _store_emit store-empty ok
}

# The fence probe (#8101). git-data-bootstrap.sh plants the pre-receive fence (CAS lease fence,
# freeze-sentinel denial, namespace check). A push reaches it through the transport wrapper, which
# pins `core.hooksPath` on git's command line, and git runs the hook AS THE git USER. So the probe
# reads what a push actually depends on, in ONE ssh session, and exits with the first failure, in
# this order:
#   10  the hooks dir is absent, or is a symlink            reason=hooks_dir_absent
#   12  pre-receive is absent, a symlink, not a regular
#       file, or not executable                             reason=hook_absent
#   16  an instrument failed (a stat)                       probe_failed rc=16
#   11  the hooks dir is not root:git 750                   reason=hooks_dir_owner
#   13  pre-receive is not root:root 755                    reason=hook_owner
#   19  the hooks dir's parent is not root-owned, or is
#       group/other-writable (git could swap the dir)       reason=hooks_parent_writable
#   16  runuser cannot run anything as git at all          probe_failed rc=16
#   17  the git user cannot read and execute pre-receive
#       (group membership, an ACL, a denied traversal)      reason=hook_not_runnable_by_git
#   16  git config exited above 1                           probe_failed rc=16
#   14  the system core.hooksPath (includes resolved) does
#       not name the SERVING hooks path; unset is git's 1   reason=hooks_path_mismatch
#   18  the installed transport wrapper is absent or does
#       not carry the command-line pin to the serving hooks
#       path                                                reason=transport_pin_mismatch
#    5  findmnt -T could not resolve a fence path's source  probe_failed rc=5
#   15  the hooks dir or pre-receive is on another source   reason=hooks_wrong_source
# Any other rc is gd_capture's own, reported probe_failed. SHAPE, NOT CONTENT: a planted
# placeholder hook passes; the content comparison belongs to the rebuilt copy (#8211). The
# answer is unauthenticated while #7226 is open, like every other store probe.
# Arguments (the #8211 reuse on the fresh root): the root probed (default OLD_ROOT), the source
# it must sit on (default STORE_SOURCE), and the hooks path a push is pinned to (default the
# serving OLD_ROOT/hooks, which does not move when a fresh root is probed before the repoint).
# A PASSED empty argument is refused, never defaulted: an empty FRESH_ROOT must not quietly
# probe the serving store. Arguments are validated before anything is printed or dialed.
TRANSPORT_WRAPPER="${TRANSPORT_WRAPPER:-/usr/local/bin/git-data-transport-wrapper.sh}"
refuse_if_fence_not_intact() {
  local root="${1-$OLD_ROOT}" src="${2-$STORE_SOURCE}" serving="${3-$OLD_ROOT/hooks}"
  local rc=0 reason="" cmd pin_hd pin_ex qh qs qsp qw qhd qex
  local -a c
  [[ "$root" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_root
  [[ "$src" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_source
  [[ "$serving" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_serving
  [[ "$TRANSPORT_WRAPPER" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_wrapper
  step "fence probe: $root/hooks holds the pre-receive fence, and a push would run it"
  # The two lines of git-data-transport-wrapper.sh that decide which hooks a push runs. The
  # suite's P2 row pins both against the wrapper itself.
  pin_hd="HOOKS_DIR=\"\${GIT_DATA_HOOKS_DIR:-$serving}\""
  pin_ex='exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"'
  printf -v qh '%q' "$root/hooks"
  printf -v qs '%q' "$src"
  printf -v qsp '%q' "$serving"
  printf -v qw '%q' "$TRANSPORT_WRAPPER"
  printf -v qhd '%q' "$pin_hd"
  printf -v qex '%q' "$pin_ex"
  c=(
    "h=$qh; p=\"\$h/pre-receive\"; src=$qs; sp=$qsp; w=$qw"
    '[ -L "$h" ] && exit 10'
    '[ -d "$h" ] || exit 10'
    '[ -L "$p" ] && exit 12'
    '[ -f "$p" ] && [ -x "$p" ] || exit 12'
    "oh=\$(stat -c '%U:%G %a' \"\$h\") || exit 16"
    "op=\$(stat -c '%U:%G %a' \"\$p\") || exit 16"
    '[ "$oh" = "root:git 750" ] || exit 11'
    '[ "$op" = "root:root 755" ] || exit 13'
    "pp=\$(stat -c '%U %a' \"\${h%/*}\") || exit 16"
    'case "$pp" in "root "[0-7][0145][0145]|"root "[0-7][0-7][0145][0145]) ;; *) exit 19 ;; esac'
    'runuser -u git -- true || exit 16'
    'runuser -u git -- test -r "$p" && runuser -u git -- test -x "$p" || exit 17'
    'v=$(env -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM git config --system --includes --get core.hooksPath); g=$?'
    '[ "$g" -le 1 ] || exit 16'
    '[ "$v" = "$sp" ] || exit 14'
    "grep -qxF -- $qhd \"\$w\" && grep -qxF -- $qex \"\$w\" || exit 18"
    's=$(findmnt -no SOURCE -T "$h") || exit 5; [ "$s" = "$src" ] || exit 15'
    's=$(findmnt -no SOURCE -T "$p") || exit 5; [ "$s" = "$src" ] || exit 15'
    'echo ok'
  )
  printf -v cmd '%s; ' "${c[@]}"
  gd_capture '^ok$' "${cmd%; }" || rc=$?
  case "$rc" in
    0) ;;
    10) reason=hooks_dir_absent ;;
    11) reason=hooks_dir_owner ;;
    12) reason=hook_absent ;;
    13) reason=hook_owner ;;
    14) reason=hooks_path_mismatch ;;
    15) reason=hooks_wrong_source ;;
    17) reason=hook_not_runnable_by_git ;;
    18) reason=transport_pin_mismatch ;;
    19) reason=hooks_parent_writable ;;
    *) _store_refuse fence-shape probe_failed "$rc" ;;
  esac
  [ -z "$reason" ] || _store_refuse fence-shape fence_not_intact "" "$reason"
  _store_emit fence-shape ok
}

# ============================================================================
# freeze / unfreeze / probe — the host-side verbs (#8211 PR2)
# ============================================================================
# Every write runs through gd_exec (bounded, stdout discarded); every read through
# probe_freeze/gd_capture. A transport failure on unfreeze is FREEZE_HELD — the sentinel
# may still be live and unverifiable, which pages, not summarizes.

require_lineage() {
  [[ "$CUTOVER_LINEAGE" =~ $LINEAGE_RE ]] || {
    log "REFUSE verdict=lineage_absent — CUTOVER_LINEAGE must be ${LINEAGE_RE} (the workflow stamps github.run_id)"
    echo "::error title=git-data-cutover::verdict=lineage_absent"
    exit 5
  }
}

mode_freeze() {
  step "freeze: gc quiesce -> timer stop -> sentinel with provenance -> legacy-lock purge"
  require_lineage
  access_gate
  refuse_if_config_unsafe
  # 1. gc.service must be INACTIVE — `stop` on the timer does not quiesce an in-flight
  #    oneshot. Assert before stopping, not after: a running gc mid-freeze is the window
  #    the freeze exists to close. `is-active` folds every non-active state into one rc,
  #    so read ActiveState's value: only `inactive`/`failed` is quiesced.
  local rc=0
  gd_capture '^(active|activating|deactivating|inactive|failed|unknown)$' \
    'systemctl show -p ActiveState --value git-data-gc.service' || rc=$?
  [ "$rc" -eq 0 ] || _store_refuse freeze-gc-quiesce probe_failed "$rc"
  case "$GD_CAPTURED" in
    inactive|failed) : ;;
    # A completed read returning `active` is a state refusal, not an instrument
    # failure — its own verdict word (the taxonomy contract: probe_failed is for
    # reads that could not complete).
    *) _store_refuse freeze-gc-quiesce gc_active ;;
  esac
  gd_exec 'systemctl stop git-data-gc.timer' || _store_refuse freeze probe_failed "$?"
  _store_emit freeze-gc-stopped ok
  # 2. Sentinel state first: ours -> idempotent (a resumed flip re-runs freeze harmlessly);
  #    foreign/unattributed -> refuse.
  probe_freeze
  case "$freeze_state" in
    absent) ;;
    ours) log "freeze already held by this lineage (${freeze_detail}) — resume arm A; sentinel write skipped, purge still runs below" ;;
    foreign) _store_refuse freeze frozen_foreign ;;
    unattributed) _store_refuse freeze frozen_unattributed ;;
    unreadable) _store_refuse freeze frozen_unreadable ;;
  esac
  # 3. Write `writer=<lineage> at=<epoch>` — both fields host-side so a partial write is
  #    unparseable (frozen_unattributed), never half-trusted. Skipped when the sentinel
  #    is already ours (resume arm A): the purge below still runs — a freeze that died
  #    between the write and the purge completes it here, never "re-runs harmlessly".
  if [ "$freeze_state" != "ours" ]; then
    local qs ql
    printf -v qs '%q' "$FREEZE_SENTINEL"
    printf -v ql '%q' "$CUTOVER_LINEAGE"
    gd_exec "printf 'writer=%s at=%s\n' $ql \"\$(date +%s)\" > $qs" \
      || _store_refuse freeze-write probe_failed "$?"
  fi
  _store_emit freeze ok
  # 4. Purge legacy .<id>.init.lock residue INSIDE the freeze window: count, assert no
  #    flock is held on each (an in-flight provision holds the lock past the sentinel
  #    check), then rm. The shared .init.lock and the boot probe's .boot-probe-0.init.lock
  #    are excluded — the former is live machinery, the latter deliberate residue.
  local qd
  printf -v qd '%q' "$OLD_REPOS"
  gd_exec "d=$qd
    tf=\$(mktemp) || exit 4
    find \"\$d\" -mindepth 1 -maxdepth 1 -name '.*.init.lock' ! -name '.init.lock' ! -name '.boot-probe-0.init.lock' -printf . > \"\$tf\" 2>/dev/null || { rm -f \"\$tf\"; exit 4; }
    n=\$(wc -c < \"\$tf\"); rm -f -- \"\$tf\"
    echo \"purge count=\$n\" >&2
    for f in \"\$d\"/.*.init.lock; do
      [ -e \"\$f\" ] || continue
      case \"\$(basename \"\$f\")\" in .init.lock|.boot-probe-0.init.lock) continue ;; esac
      exec 8<\"\$f\"; flock -n 8 || exit 23   # a held lock means an in-flight provision — STOP
      rm -f -- \"\$f\" || exit 5
    done" || {
    rc=$?
    case "$rc" in
      23) _store_refuse lock-purge lock_held ;;
      *) _store_refuse lock-purge probe_failed "$rc" ;;
    esac
  }
  _store_emit lock-purge ok
  log "freeze held: sentinel at $FREEZE_SENTINEL (writer=$CUTOVER_LINEAGE), gc.timer stopped, legacy lock residue purged"
}

mode_unfreeze() {
  step "unfreeze: provenance check -> sentinel clear -> gc.timer restart"
  access_gate
  refuse_if_config_unsafe
  probe_freeze
  case "$freeze_state" in
    absent)
      _store_emit unfreeze ok "" nothing_to_unfreeze
      log "nothing_to_unfreeze — no sentinel at $FREEZE_SENTINEL"
      ;;
    ours)
      local qs
      printf -v qs '%q' "$FREEZE_SENTINEL"
      gd_exec "rm -f -- $qs" || {
        _store_emit unfreeze FREEZE_HELD
        log "FREEZE_HELD: could not clear the sentinel (transport/write failure). This pages: the freeze may still be live and blocks every store verb."
        echo "::error title=git-data-cutover::verdict=FREEZE_HELD"
        exit 5
      }
      _store_emit unfreeze ok
      ;;
    foreign) _store_refuse unfreeze frozen_foreign ;;
    unattributed) _store_refuse unfreeze frozen_unattributed ;;
    unreadable) _store_refuse unfreeze frozen_unreadable ;;
  esac
  if gd_exec 'systemctl start git-data-gc.timer'; then
    log "unfreeze done (state was: ${freeze_state}); gc.timer restarted"
  else
    # The store is writable but gc stays stopped — warn, don't fail the unfreeze.
    echo "::warning title=git-data-cutover::gc.timer restart failed — verify it is running"
    log "unfreeze done (state was: ${freeze_state}); gc.timer restart FAILED — see the warning"
  fi
}

mode_probe() {
  step "probe: transactional provision + fenced push + remove (synthetic id)"
  require_lineage
  access_gate
  refuse_if_config_unsafe
  # The probe proves the FULL transport contract, not the write alone: provision wrapper
  # accepts the id, a push under the CAS fence lands a ref, the remove wrapper erases it.
  # Zero residue is an assertion, not a hope — anything left trips served_repos.
  local probe_id="cutover-probe-${CUTOVER_LINEAGE}"
  # probe_id is `cutover-probe-` + the already-LINAGE_RE-validated lineage — always in
  # the wrapper's id shape, so it needs no separate guard.
  local qp qd
  printf -v qp '%q' "$probe_id"
  printf -v qd '%q' "$OLD_REPOS"
  local rc=0
  gd_exec "id=$qp; d=$qd
    repo=\"\$d/\$id.git\"
    env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=\"\$id\" runuser -u git -- /usr/local/bin/git-data-provision.sh || exit 11
    [ -d \"\$repo\" ] || exit 12
    t=\$(mktemp -d) && chown git:git \"\$t\" || exit 13
    runuser -u git -- sh -c \"cd \\\"\$t\\\" && git init -q && git config user.email cutover@probe && git config user.name probe && git commit -q --allow-empty -m probe && git push --push-option=lease-gen=1 --push-option=worktree-id=cutover-probe \\\"\$repo\\\" HEAD:refs/soleur/worktrees/cutover-probe/probe\" || { rm -rf \"\$t\"; exit 14; }
    rm -rf \"\$t\"
    git --git-dir=\"\$repo\" rev-parse --verify -q refs/soleur/worktrees/cutover-probe/probe >/dev/null || exit 15
    env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=\"\$id\" runuser -u git -- /usr/local/bin/git-data-remove.sh || exit 16
    [ ! -e \"\$repo\" ] || exit 17" || rc=$?
  if [ "$rc" -ne 0 ]; then
    # Zero-residue: try the remove once more (idempotent) before reporting.
    gd_exec "env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=$qp runuser -u git -- /usr/local/bin/git-data-remove.sh" || true
    case "$rc" in
      11) _store_refuse probe probe_failed "" provision ;;
      12) _store_refuse probe probe_failed "" repo_absent_after_provision ;;
      13) _store_refuse probe probe_failed "" scratch ;;
      14) _store_refuse probe fenced_push_failed ;;
      15) _store_refuse probe probe_failed "" ref_not_landed ;;
      16) _store_refuse probe remove_failed ;;
      17) _store_refuse probe residue_left ;;
      *) _store_refuse probe probe_failed "$rc" ;;
    esac
  fi
  _store_emit probe ok
  log "probe clear: $probe_id provisioned, a CAS-fenced push landed a ref, and the erasure removed it (zero residue)"
}

# ============================================================================
# Main
# ============================================================================
main() {
  refuse_legacy_modes
  resolve_roster
  case "$MODE" in
    proof)
      refuse_if_config_unsafe
      log "starting git-data read-only proof (access gate, the store probes, then the fence probe; no host is changed)"
      access_gate
      refuse_if_unmounted
      refuse_if_not_on_mapper
      refuse_if_store_unverified_or_not_empty
      refuse_if_fence_not_intact
      log "read-only proof clear: access ok, served by the LUKS mapper, the bootstrap's store marker bound to its filesystem, not frozen, no entry in the repositories directory, fence in place for pushes"
      echo "::notice title=git-data-cutover store::verdict=clear"
      ;;
    freeze)   mode_freeze ;;
    unfreeze) mode_unfreeze ;;
    probe)    mode_probe ;;
  esac
}

main "$@"
