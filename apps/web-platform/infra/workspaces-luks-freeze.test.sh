#!/usr/bin/env bash
#
# Behavioral test for workspaces-cutover.sh :: freeze_writers / resume_writers / app_canary
# (#6588 freeze-quiesce).
#
# Context: on 2026-07-19 two consecutive REAL /workspaces LUKS freezes safe-aborted on the C1
# byte-identity verify with exactly ONE difference:
#   SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF count=1 idx=0 icode=>fcst......
#     path=redis/appendonlydir/appendonly.aof.94.incr.aof
# `>fcst......` = checksum + size + mtime differ — a live-appending file, NOT a copy defect. Redis
# persists its AOF to /mnt/data/redis (inngest-redis.conf `dir /mnt/data/redis`, `appendonly yes`)
# and runs as the SYSTEMD UNIT inngest-redis.service, not as a container — so the freeze's
# `systemctl stop webhook.service` + `docker stop $CONTAINER` never touched it and it appended
# straight through the freeze, the pass-2 delta rsync and the verify.
#
# This suite pins three fixes and their mutation twins:
#   (1) inngest-redis.service is in the quiesce set, and is restored on ALL THREE exit paths
#       (success, rollback, dead-man).
#   (2) The G4 straggler assert is fail-closed on a missing lsof (it silently no-opped behind
#       `command -v lsof`), uses NO pipe (`lsof | grep -q .` returns 141 under `set -o pipefail`
#       when the match is early and the producer SIGPIPEs — a size-dependent fail-OPEN, i.e. the
#       gate evaporates precisely when there are many stragglers), and LOGS the holders before it
#       dies (the exact undiagnosable-abort defect #6604 fixed for C1).
#   (3) The app canary targets the middleware-exempt /health, not /api/health (which does not
#       exist and 307s to /login — so the canary would abort every otherwise-successful cutover).
#
# The C1 gate itself is deliberately NOT touched (AC11): the verify correctly caught a real risk —
# copying a live-appending AOF would put a torn journal on the encrypted volume. The writer was not
# quiesced; the gate was right.
#
# Harness: `source` the cutover script (its sourced-detection guard defines the functions without
# running the main body / arming the EXIT trap), override systemctl/docker/lsof/mount/curl/die/
# emit_drift/logger as shell functions AFTER the source, each recording argv to a calls file, then
# run the function under test in a fresh subshell per case. Mirrors workspaces-luks-verify.test.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/workspaces-luks-cutover.yml"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# run_case <script> <func-and-args> <required-fns> [env assignments...]
#
# <required-fns> is a space-separated list of function names the case depends on. The subshell
# asserts each is declared BEFORE running the invocation and exits 97 with HARNESS_UNDEFINED if not.
# Without this, a case that asserts "exits non-zero" (T7/T8) passes vacuously against a script where
# the function does not exist at all — the subshell fails for the wrong reason and the gate reports
# green while testing nothing. `undef` below turns that into a loud FAIL.
# Sources <script>, installs recording stubs, runs <func>. Sets:
#   CASE_RC   subshell exit status
#   CASE_OUT  combined stdout+stderr
#   CALLS     path to the argv-recording file (one "cmd arg arg" line per stubbed invocation)
#   MARKER_LOG path to the logger sink
#
# LSOF_OUT   stub lsof stdout ("" => no holders, exit 1 like the real lsof)
# LSOF_ABSENT=1  make `command -v lsof` fail AND the install fail (fail-closed probe)
# ACTIVE_UNITS   space-separated units for which `systemctl is-active` succeeds
# CURL_CODE  stub curl's echoed HTTP code
run_case() {
  local script="$1" invocation="$2" require="$3"; shift 3
  CALLS="$(mktemp)"; MARKER_LOG="$(mktemp)"; STATE="$(mktemp -d)"
  CASE_OUT="$(
    env "$@" \
      CUTOVER="$script" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG" \
      WORKSPACES_STATE_DIR="$STATE" INVOCATION="$invocation" REQUIRE_FNS="$require" \
    bash -c '
      source "$CUTOVER"                                   # guard => functions only, no main body
      rec() { printf "%s\n" "$*" >> "$CALLS"; }
      # --- stubs (override the sourced defs / real binaries) ---
      systemctl() {
        rec "systemctl $*"
        if [ "${1:-}" = "is-active" ]; then
          local u="${@: -1}"                              # last arg (skips --quiet)
          case " ${ACTIVE_UNITS:-} " in *" $u "*) return 0;; *) return 1;; esac
        fi
        return 0
      }
      docker()  { rec "docker $*"; return 0; }
      mount()   { rec "mount $*"; return 0; }
      umount()  { rec "umount $*"; return 0; }
      cryptsetup() { rec "cryptsetup $*"; return 0; }
      systemd-run() { rec "systemd-run $*"; return 0; }
      logger()  { printf "%s\n" "$*" >> "$MARKER_LOG"; }
      hostname() { echo "test-host"; }
      apt-get() { rec "apt-get $*"; return 1; }           # install always fails (fail-closed probe)
      curl()    { rec "curl $*"; printf "%s" "${CURL_CODE:-200}"; return 0; }
      die()     { echo "DIE: $*"; exit 1; }
      emit_drift() { echo "EMIT_DRIFT: $1"; }
      # LSOF_OUT_FILE, not a big LSOF_OUT env: a multi-MB value exceeds the argv/env limit (E2BIG)
      # and `env` fails BEFORE the harness precondition runs, making a "non-zero exit" assertion pass
      # vacuously. The large-output case is exactly the one T8 needs, so it must come from a file.
      lsof()    {
        rec "lsof $*"
        # Propagate cat exit status -- a hardcoded zero would swallow the producer SIGPIPE 141 that
        # is the entire mechanism mutation M3 exists to reproduce.
        if [ -n "${LSOF_OUT_FILE:-}" ]; then cat "$LSOF_OUT_FILE"; return $?; fi
        [ -n "${LSOF_OUT:-}" ] || return 1
        printf "%s\n" "$LSOF_OUT"; return 0
      }
      # command -v lsof must fail when LSOF_ABSENT=1 so ensure_lsof takes the install path.
      command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "lsof" ] && [ "${LSOF_ABSENT:-}" = "1" ]; then return 1; fi
        builtin command "$@"
      }
      for f in ${REQUIRE_FNS:-}; do
        declare -F "$f" >/dev/null || { echo "HARNESS_UNDEFINED:$f"; exit 97; }
      done
      eval "$INVOCATION"
    ' 2>&1
  )"
  CASE_RC=$?
}

calls()  { cat "$CALLS" 2>/dev/null; }
marker() { cat "$MARKER_LOG" 2>/dev/null; }
# undef — true when the case never ran because a required function is undefined. Any assertion that
# reads a non-zero CASE_RC as evidence MUST consult this first, else "the function is missing" is
# indistinguishable from "the gate fired".
undef() { printf '%s\n' "$CASE_OUT" | grep -q '^HARNESS_UNDEFINED:'; }
# died — the case ran AND aborted through die()/a real non-zero exit (not a harness precondition).
died() { [ "$CASE_RC" -ne 0 ] && ! undef; }

# ---------------------------------------------------------------------------
# T1-T3, T14 — freeze_writers() quiesce set + order + persisted state
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT=""
if calls | grep -qE '^systemctl stop .*inngest-redis\.service'; then
  ok "T1 freeze_writers stops inngest-redis.service (the unquiesced AOF writer)"
else
  no "T1 freeze_writers did NOT stop inngest-redis.service — the quiescence gap is unfixed"
fi

# T2 — order: webhook stopped BEFORE the container; redis stopped before freeze_writers returns.
wh="$(calls | grep -nE '^systemctl stop webhook\.service' | head -1 | cut -d: -f1)"
dk="$(calls | grep -nE '^docker stop' | head -1 | cut -d: -f1)"
rd="$(calls | grep -nE '^systemctl stop .*inngest-redis\.service' | head -1 | cut -d: -f1)"
if [ -n "$wh" ] && [ -n "$dk" ] && [ -n "$rd" ] && [ "$wh" -lt "$dk" ]; then
  ok "T2 quiesce order: webhook stopped before the container (a CI deploy cannot restart it mid-rsync)"
else
  no "T2 quiesce order wrong or incomplete (webhook=$wh docker=$dk redis=$rd)"
fi

# T3 — the quiesced set is persisted so an unattended recovery knows what to restore.
if grep -qE '^QUIESCED_UNITS=.*inngest-redis\.service' "$STATE/state" 2>/dev/null; then
  ok "T3 freeze_writers persists QUIESCED_UNITS naming inngest-redis.service"
else
  no "T3 QUIESCED_UNITS not persisted (or omits inngest-redis.service)"
fi

# T14 — inngest-server is NEVER stopped (pins the deepen reversal: ProtectSystem=strict means it
# cannot write $MOUNT, and TimeoutStopSec=180 would burn 3 min of a ~10 min freeze).
if calls | grep -qE '^systemctl stop .*inngest-server\.service'; then
  no "T14 freeze_writers stops inngest-server.service — reintroduces the 180s TimeoutStopSec cost for zero quiescence benefit"
else
  ok "T14 freeze_writers never stops inngest-server.service (deepen decision pinned)"
fi

# ---------------------------------------------------------------------------
# T7-T9 — G4 fail-closed, no-pipe, logs-before-die
# ---------------------------------------------------------------------------

# T7 — lsof absent AND un-installable => freeze_writers MUST abort (it currently skips silently).
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers ensure_lsof' LSOF_ABSENT=1 LSOF_OUT=""
if died; then
  ok "T7 G4 is fail-closed: absent+un-installable lsof aborts the freeze"
else
  no "T7 G4 silently skipped on a missing lsof — the safety gate evaporates exactly when it is needed"
fi

# T8 — a LARGE holder list must still abort. `lsof +D | grep -q .` returns 141 (SIGPIPE) under
# `set -o pipefail` once the producer outruns grep's early close, so the `&& die` never fires: a
# size-dependent fail-OPEN. Capture-to-variable has no pipe and cannot regress this way.
BIGF="$(mktemp)"; yes 'redis-server 1234 root  7w REG 0,42 /mnt/data/redis/appendonlydir/appendonly.aof' 2>/dev/null | head -20000 > "$BIGF"
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT_FILE="$BIGF"
if died; then
  ok "T8 G4 still aborts on a large holder list (no pipefail/SIGPIPE fail-open)"
else
  no "T8 G4 returned success on a large holder list — the pipe fail-open is present"
fi

# T9 — holders are LOGGED before die (the #6604 undiagnosable-abort class, applied to G4).
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers emit_freeze_holders' LSOF_OUT="redis-server 1234 root 7w REG /mnt/data/redis/appendonlydir/appendonly.aof"
if marker | grep -q 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER'; then
  ok "T9 G4 emits SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER to the Better Stack channel"
else
  no "T9 no SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER marker — a G4 abort stays undiagnosable without SSH"
fi
emit_line="$(printf '%s\n' "$CASE_OUT" | grep -n 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER' | head -1 | cut -d: -f1)"
die_line="$(printf '%s\n' "$CASE_OUT" | grep -n '^DIE:' | head -1 | cut -d: -f1)"
if [ -n "$emit_line" ] && [ -n "$die_line" ] && [ "$emit_line" -lt "$die_line" ]; then
  ok "T9b the holder emit PRECEDES die (evidence survives the abort)"
else
  no "T9b holder emit does not precede die (emit=$emit_line die=$die_line) — evidence is discarded"
fi
if printf '%s\n' "$CASE_OUT" | grep -q '/mnt/data/redis/appendonlydir/appendonly.aof'; then
  ok "T9c the emitted marker names the offending holder path"
else
  no "T9c the marker does not name the holder path — it cannot diagnose the next abort"
fi

# ---------------------------------------------------------------------------
# T4-T6, T13 — resume_writers() on the exit paths
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS="inngest-server.service"
if calls | grep -qE '^systemctl start .*inngest-redis\.service'; then
  ok "T4 resume_writers starts inngest-redis.service"
else
  no "T4 resume_writers does not start inngest-redis.service — the durable Inngest queue stays down"
fi
if calls | grep -qE '^systemctl reset-failed .*inngest-redis\.service'; then
  ok "T4b resume_writers clears failed state before starting (RequiresMountsFor leaves it in 'failed')"
else
  no "T4b no reset-failed before the start — a mount-race failure silently outlives the run"
fi

# T13 — inngest-server already active => reconciled but NOT redundantly started.
if calls | grep -qE '^systemctl start .*inngest-server\.service'; then
  no "T13 redundant inngest-server start issued although it was already active"
else
  ok "T13 no redundant inngest-server start when it is already active"
fi

run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS=""
if calls | grep -qE '^systemctl start .*inngest-server\.service'; then
  ok "T13b inactive inngest-server IS reconciled (started) post-freeze"
else
  no "T13b inactive inngest-server was not reconciled — a redis-window crash-loop outlives the run"
fi

# T5/T6 — rollback() restores redis, and does so AFTER the plaintext remount.
run_case "$CUTOVER" 'DRY_RUN=0 rollback' 'rollback resume_writers' ACTIVE_UNITS="inngest-server.service"
if calls | grep -qE '^systemctl start .*inngest-redis\.service'; then
  ok "T5 rollback() restores inngest-redis.service (DP-6 leaves the host as it found it)"
else
  no "T5 rollback() does not restore inngest-redis.service — a safe-abort leaves the queue down"
fi
mnt_line="$(calls | grep -nE '^mount ' | head -1 | cut -d: -f1)"
rdst_line="$(calls | grep -nE '^systemctl start .*inngest-redis\.service' | head -1 | cut -d: -f1)"
if [ -n "$mnt_line" ] && [ -n "$rdst_line" ] && [ "$mnt_line" -lt "$rdst_line" ]; then
  ok "T6 rollback() remounts BEFORE starting redis (RequiresMountsFor=/mnt/data)"
else
  no "T6 redis start races the remount (mount=$mnt_line start=$rdst_line) — the unit lands in \`failed\`"
fi

# ---------------------------------------------------------------------------
# T10-T11 — app_canary() targets the middleware-exempt path
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200
if calls | grep -qE '^curl .*app\.soleur\.ai/health( |$)'; then
  ok "T10 app_canary probes app.soleur.ai/health (the middleware.ts:113 exemption)"
else
  no "T10 app_canary does not probe /health"
fi
if calls | grep -qE 'app\.soleur\.ai/api/health'; then
  no "T11 app_canary still probes /api/health — 307s to /login, so it aborts every good cutover"
else
  ok "T11 app_canary never probes /api/health"
fi
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=307
if died; then
  ok "T11b app_canary still fails closed on a non-200 (the gate is preserved, only the path moved)"
else
  no "T11b app_canary accepted a 307 — the canary is no longer a gate"
fi

# ---------------------------------------------------------------------------
# T12 — dead-man command restores redis (the unattended path)
# ---------------------------------------------------------------------------

deadman="$(awk '/^arm_dead_man\(\)/,/^}/' "$CUTOVER")"
if printf '%s' "$deadman" | grep -q 'inngest-redis'; then
  ok "T12 the dead-man systemd-run command restarts inngest-redis (the unattended restore path)"
else
  no "T12 dead-man command omits inngest-redis — an unattended recovery leaves the queue down silently"
fi

# ---------------------------------------------------------------------------
# Static guards (AC5 / AC7 / AC8 / AC9)
# ---------------------------------------------------------------------------

# Strip comment lines before grepping: the function body DOCUMENTS the `lsof | grep -q .` trap in
# prose, so a bare body-grep matches its own explanation and false-FAILs a correct implementation.
if [ "$(awk '/^freeze_writers\(\)/,/^}/' "$CUTOVER" | grep -vE '^[[:space:]]*#' | grep -c 'lsof.*| *grep' || true)" -eq 0 ]; then
  ok "AC5 freeze_writers contains no \`lsof … | grep\` pipe"
else
  no "AC5 a pipe is back in the G4 predicate — size-dependent SIGPIPE fail-open"
fi
if [ "$(grep -c 'app\.soleur\.ai/api/health' "$CUTOVER" || true)" -eq 0 ]; then
  ok "AC7 no /api/health reference remains in the cutover script"
else
  no "AC7 /api/health still referenced"
fi
if [ "$(grep -c 'no C1 verify' "$WORKFLOW" || true)" -ge 1 ]; then
  ok "AC9 the dry_run input description states the rehearsal does not run the C1 verify"
else
  no "AC9 dry_run description still misrepresents what a rehearsal covers"
fi

# ---------------------------------------------------------------------------
# Mutation tests (AC13) — each carries the M4-style did-the-sed-land guard.
# ---------------------------------------------------------------------------
mutate() {  # <sed-expr...> -> prints path to a mutated copy of the cutover script
  local mut; mut="$(mktemp --suffix=.sh)"
  cp "$CUTOVER" "$mut"
  local e; for e in "$@"; do sed -i "$e" "$mut"; done
  printf '%s\n' "$mut"
}

# M1 — drop inngest-redis from the quiesce set => T1 MUST flip.
MUT1="$(mutate 's|^QUIESCE_UNITS=.*$|QUIESCE_UNITS="webhook.service"|')"
if ! grep -qE '^QUIESCE_UNITS="webhook\.service"$' "$MUT1"; then
  no "mutation M1 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT1" 'freeze_writers' 'freeze_writers' LSOF_OUT=""
  if calls | grep -qE '^systemctl stop .*inngest-redis\.service'; then
    no "mutation M1 did not flip T1 — the quiesce set is not load-bearing"
  else
    ok "mutation M1 (drop redis from QUIESCE_UNITS): T1 flips (the set is load-bearing)"
  fi
fi
rm -f "$MUT1"

# M2 — restore the `command -v lsof` skip wrapper => T7 MUST flip (silent skip returns).
MUT2="$(mutate 's|^ *ensure_lsof$|  command -v lsof >/dev/null 2>\&1 \|\| return 0|')"
if ! grep -qE '^ *command -v lsof >/dev/null 2>&1 \|\| return 0$' "$MUT2"; then
  no "mutation M2 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT2" 'freeze_writers' 'freeze_writers' LSOF_ABSENT=1 LSOF_OUT=""
  if [ "$CASE_RC" -eq 0 ] && ! undef; then
    ok "mutation M2 (restore the command -v skip): T7 flips to passing (fail-closed is load-bearing)"
  else
    no "mutation M2 did not flip T7 — the fail-closed path is not load-bearing"
  fi
fi
rm -f "$MUT2"

# M3 — reintroduce the pipe => T8 MUST flip on the large-output case (SIGPIPE fail-open).
MUT3="$(mutate 's|^ *holders="\$(lsof +D "\$MOUNT" 2>/dev/null \|\| true)"$|  holders=""; lsof +D "$MOUNT" 2>/dev/null \| grep -q . \&\& holders=x|')"
if ! grep -qF 'lsof +D "$MOUNT" 2>/dev/null | grep -q . && holders=x' "$MUT3"; then
  no "mutation M3 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT3" 'freeze_writers' 'freeze_writers' LSOF_OUT_FILE="$BIGF"
  if [ "$CASE_RC" -eq 0 ] && ! undef; then
    ok "mutation M3 (reintroduce the pipe): T8 flips to passing (proves the no-pipe form is load-bearing)"
  else
    no "mutation M3 did not flip T8 — the large-output SIGPIPE path is not reproduced by this fixture"
  fi
fi
rm -f "$MUT3"

# M4 — move the holder emit AFTER die => T9b MUST flip (evidence discarded, the #6604 defect).
MUT4="$(mutate 's|^ *emit_freeze_holders "\$holders"$|  :|')"
if ! grep -qE '^ *:$' "$MUT4" || grep -qF 'emit_freeze_holders "$holders"' "$MUT4"; then
  no "mutation M4 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT4" 'freeze_writers' 'freeze_writers' LSOF_OUT="redis-server 1234 root 7w REG /mnt/data/redis/appendonlydir/appendonly.aof"
  if marker | grep -q 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER'; then
    no "mutation M4 did not flip T9 — the emit is not load-bearing"
  else
    ok "mutation M4 (drop the holder emit): T9 flips (the emit is load-bearing)"
  fi
fi
rm -f "$MUT4"

# ---------------------------------------------------------------------------
echo
echo "workspaces-luks-freeze.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
