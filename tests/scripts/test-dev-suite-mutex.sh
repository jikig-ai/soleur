#!/usr/bin/env bash
# Tests for scripts/dev-suite-mutex.sh — the cross-ref advisory mutex for the
# dev-Supabase tenant-integration critical section (#7964).
#
# Hermetic: `psql` is stubbed on PATH. The stub emulates the semantics the SUT
# depends on, not the wire protocol:
#   - a holder invocation (-f <sql>) whose SQL carries the advisory-lock call
#     blocks on an atomic mkdir lock until it is free, then prints the held
#     marker and "sleeps" (holds the lock) until killed — mirroring
#     BEGIN; pg_advisory_xact_lock; marker; pg_sleep(HOLD); COMMIT;
#   - a holder invocation whose SQL does NOT carry the lock call prints the
#     marker immediately even while the lock is held — the mutation that makes
#     "the lock exists" load-bearing rather than incidental;
#   - the holder-identity probe (-c <sql> containing pg_locks) answers
#     $STUB_HOLDER_NAME when the lock is held, empty otherwise;
#   - STUB_NEVER_MARK=1 makes the holder sleep without ever printing the
#     marker — the wait-budget-exhausted path.
#
# Extra stub-facing env is forwarded through env "$@", so pass it as trailing
# args to _acquire/_release/_probe (an env PREFIX on the call only reaches the
# helper's own shell, never the stub).
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/dev-suite-mutex.sh"
MUTEX_SQL="pg_advisory_xact_lock(hashtext('tenant_integration_dev_suite'))"

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the canonical body; do not reword).
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

WORK="$(mktemp -d -t dev-suite-mutex.XXXXXXXX)" || { echo "FATAL: mktemp" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT INT TERM

STUB_BIN="$WORK/bin"
assert_fixture_dir "$STUB_BIN"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/psql" <<'STUB'
#!/usr/bin/env bash
# Stub psql for test-dev-suite-mutex.sh. See suite header for the emulated
# contract. Every call is logged to $STUB_DB_DIR/calls.log.
set -uo pipefail
: "${STUB_DB_DIR:?}"
mkdir -p "$STUB_DB_DIR"
LOCKDIR="$STUB_DB_DIR/lock.d"
CALLS="$STUB_DB_DIR/calls.log"

sql=""; prev=""
for a in "$@"; do
  case "$prev" in
    -f) sql=$(cat "$a" 2>/dev/null || true) ;;
    -c) sql="$a" ;;
  esac
  prev="$a"
done
{
  printf -- '--- psql call (PGAPPNAME=%s) ---\n' "${PGAPPNAME:-<unset>}"
  printf 'URL %s\n' "${1:-<none>}"
  printf '%s\n' "$sql"
} >>"$CALLS"

# Holder-identity probe (pg_locks join pg_stat_activity).
if [[ "$sql" == *pg_locks* ]]; then
  if [[ -d "$LOCKDIR" ]]; then printf '%s\n' "${STUB_HOLDER_NAME:-ti-stub-run1}"; fi
  exit 0
fi

# Marker-suppression arm: holder sleeps, never prints the marker. sleep is
# backgrounded + waited so a trapped TERM interrupts it promptly (bash defers
# traps until a foreground builtin/child completes).
if [[ "${STUB_NEVER_MARK:-0}" == "1" ]]; then
  sleep "${STUB_BLOCK_S:-30}" &
  wait $!
  exit 0
fi

if [[ "$sql" == *"pg_advisory_xact_lock"* || "$sql" == *"pg_advisory_lock("* ]]; then
  # Emulate blocking acquire: wait for the lock dir, take it, announce, hold.
  owned=0
  end=$(( SECONDS + ${STUB_BLOCK_S:-30} ))
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    if (( SECONDS >= end )); then exit 0; fi
    sleep 0.05
  done
  owned=1
  trap '[[ "$owned" == "1" ]] && rmdir "$LOCKDIR" 2>/dev/null; exit 0' TERM INT EXIT
  printf 'DEV_SUITE_MUTEX_HELD\n'
  sleep "${STUB_HOLD_S:-30}" &
  wait $!
  exit 0
fi

# Lock call absent (mutation arm): marker prints with no lock taken — a SUT
# that forgot the lock still "acquires" instantly under this stub, which is
# exactly the vacuity the suite must catch.
printf 'DEV_SUITE_MUTEX_HELD\n'
sleep "${STUB_HOLD_S:-5}" &
wait $!
exit 0
STUB
chmod +x "$STUB_BIN/psql"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "[ok] $*"; }
bad() { fail=$((fail + 1)); echo "[FAIL] $*" >&2; }
assert_file() { # assert_file <label> <path>
  if [[ -f "$2" ]]; then ok "$1"; else bad "$1 (missing file: $2)"; fi
}

setup_case() { # setup_case <name> — fresh per-case stub-DB + state dirs
  local d="$WORK/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/db" "$d/state"
  STUB_DB_DIR="$d/db"
  STATE="$d/state"
}

# Helpers forward trailing args into the SUT's env (env "$@"), which is how a
# case passes stub-facing knobs (STUB_HOLDER_NAME, STUB_NEVER_MARK, ...).
# Helper-scope knobs (WAIT_S, HOLD_S) are read here, not forwarded.
_acquire() { # _acquire <identity> <state-name> [env assignments forwarded to the SUT...]
  local ident="$1" sname="$2"; shift 2
  env PATH="$STUB_BIN:$PATH" \
      STUB_DB_DIR="$STUB_DB_DIR" \
      DATABASE_URL_POOLER="postgres://stub-pooler.invalid/db" \
      DEV_SUITE_MUTEX_IDENTITY="$ident" \
      DEV_SUITE_MUTEX_STATE_DIR="$STUB_DB_DIR/state-$sname" \
      DEV_SUITE_MUTEX_WAIT_S="${WAIT_S:-10}" \
      DEV_SUITE_MUTEX_HOLD_S="${HOLD_S:-30}" \
      "$@" \
      bash "$SUT" acquire
}
_release() { # _release <identity> <state-name> [env...]
  local ident="$1" sname="$2"; shift 2
  env PATH="$STUB_BIN:$PATH" \
      STUB_DB_DIR="$STUB_DB_DIR" \
      DATABASE_URL_POOLER="postgres://stub-pooler.invalid/db" \
      DEV_SUITE_MUTEX_IDENTITY="$ident" \
      DEV_SUITE_MUTEX_STATE_DIR="$STUB_DB_DIR/state-$sname" \
      "$@" \
      bash "$SUT" release
}
_probe() { # _probe <identity> [env...]
  local ident="$1"; shift
  env PATH="$STUB_BIN:$PATH" \
      STUB_DB_DIR="$STUB_DB_DIR" \
      DATABASE_URL_POOLER="postgres://stub-pooler.invalid/db" \
      DEV_SUITE_MUTEX_IDENTITY="$ident" \
      DEV_SUITE_MUTEX_STATE_DIR="$STUB_DB_DIR/state-probe" \
      "$@" \
      bash "$SUT" probe
}
# wait_lock / wait_unlock — poll the stub lock dir.
wait_lock()   { for _ in $(seq 1 200); do [[ -d "$STUB_DB_DIR/lock.d" ]] && return 0; sleep 0.05; done; return 1; }
wait_unlock() { for _ in $(seq 1 200); do [[ ! -d "$STUB_DB_DIR/lock.d" ]] && return 0; sleep 0.05; done; return 1; }

# === Case: free acquire — marker observed, ACQUIRED banner, holder alive =====
setup_case free
rc=0; out=$(_acquire ti-main-run1 a 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -qE 'DEV_SUITE_MUTEX_ACQUIRED after [0-9]+ms'; then
  ok "free acquire emits DEV_SUITE_MUTEX_ACQUIRED after <N>ms (rc=0)"
else
  bad "free acquire: rc=$rc out=$out"
fi
assert_file "holder pid file written" "$STUB_DB_DIR/state-a/holder.pid"
hpid=$(cat "$STUB_DB_DIR/state-a/holder.pid" 2>/dev/null || true)
if kill -0 "$hpid" 2>/dev/null; then
  ok "holder process alive after acquire"
else
  bad "holder process not alive after acquire (pid=$hpid)"
fi
# The lock SQL is the load-bearing line — assert it reached psql, and that the
# holder SQL wraps the lock in an explicit transaction (xact-scoped semantics).
if grep -qF "$MUTEX_SQL" "$STUB_DB_DIR/calls.log"; then
  ok "holder SQL carries pg_advisory_xact_lock(hashtext('tenant_integration_dev_suite'))"
else
  bad "holder SQL missing the advisory-xact lock call"
fi
if grep -qE '^BEGIN;' "$STUB_DB_DIR/calls.log" && grep -qE '^COMMIT;' "$STUB_DB_DIR/calls.log"; then
  ok "holder SQL wraps the lock in BEGIN..COMMIT (transaction scope)"
else
  bad "holder SQL lacks explicit transaction framing"
fi
if grep -q 'pg_sleep' "$STUB_DB_DIR/calls.log"; then
  ok "holder SQL keeps the transaction open via pg_sleep"
else
  bad "holder SQL lacks the pg_sleep hold"
fi
if grep -q 'DEV_SUITE_MUTEX_HELD' "$STUB_DB_DIR/calls.log"; then
  ok "holder SQL emits the post-lock marker the acquirer polls for"
else
  bad "holder SQL emits no post-lock marker"
fi
# Identity must ride PGAPPNAME so a contended run can name its blocker.
if grep -q 'PGAPPNAME=ti-main-run1' "$STUB_DB_DIR/calls.log"; then
  ok "identity rides into psql via PGAPPNAME"
else
  bad "PGAPPNAME did not carry the identity"
fi
# The POOLER url must be the connection target when it is set.
if grep -q 'URL postgres://stub-pooler.invalid/db' "$STUB_DB_DIR/calls.log"; then
  ok "acquire connects via DATABASE_URL_POOLER"
else
  bad "acquire did not connect via DATABASE_URL_POOLER"
fi
rrc=0; rel=$(_release ti-main-run1 a) || rrc=$?
if [[ "$rrc" == "0" ]] && printf '%s' "$rel" | grep -q 'DEV_SUITE_MUTEX_RELEASED'; then
  ok "release emits DEV_SUITE_MUTEX_RELEASED (rc=0)"
else
  bad "release: rc=$rrc out=$rel"
fi
if kill -0 "$hpid" 2>/dev/null; then
  bad "holder still alive after release"
else
  ok "holder dead after release"
fi
if [[ -d "$STUB_DB_DIR/lock.d" ]]; then
  bad "stub lock still held after release"
else
  ok "stub lock free after release"
fi

# === Case: contended acquire — WAITING then CONTENDED_PROCEEDING, holder named
setup_case contended
_acquire ti-main-runA A >/dev/null 2>&1 &
wait_lock || bad "first holder never took the stub lock"
rc=0; out=$(WAIT_S=1 _acquire ti-pr-runB B 'STUB_HOLDER_NAME=ti-sibling-ref-run99' 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_WAITING'; then
  ok "contended acquire announces DEV_SUITE_MUTEX_WAITING"
else
  bad "contended acquire: no WAITING (rc=$rc out=$out)"
fi
if printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_CONTENDED_PROCEEDING'; then
  ok "wait-budget expiry emits DEV_SUITE_MUTEX_CONTENDED_PROCEEDING (rc=0, fail-open)"
else
  bad "contended acquire did not reach CONTENDED_PROCEEDING (rc=$rc out=$out)"
fi
if printf '%s' "$out" | grep -q 'holder=ti-sibling-ref-run99'; then
  ok "contended banner names the holder's application_name"
else
  bad "contended banner does not name the holder (out=$out)"
fi
# Fail-open must not strand a half-acquired holder of our own: our blocked
# psql must be dead, and must not hold the stub lock.
sleep 0.3
if [[ -d "$STUB_DB_DIR/lock.d" ]]; then
  ok "first holder still owns the stub lock (we did not steal it)"
else
  bad "stub lock vanished while first holder alive"
fi
_release ti-main-runA A >/dev/null

# === Case: wait-then-acquire — WAITING then ACQUIRED once the holder releases
setup_case waitacq
_acquire ti-main-runC C 'STUB_HOLD_S=2' >/dev/null 2>&1 &
wait_lock || bad "first holder never took the stub lock (waitacq)"
rc=0; out=$(WAIT_S=15 _acquire ti-pr-runD D 2>&1) || rc=$?
if [[ "$rc" == "0" ]] \
  && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_WAITING' \
  && printf '%s' "$out" | grep -qE 'DEV_SUITE_MUTEX_ACQUIRED after [0-9]+ms'; then
  ok "second acquire waits then ACQUIRED after holder release"
else
  bad "wait-then-acquire: rc=$rc out=$out"
fi
# Ordering pin: WAITING must precede ACQUIRED.
w_line=$(printf '%s\n' "$out" | grep -n 'DEV_SUITE_MUTEX_WAITING' | cut -d: -f1 || true)
a_line=$(printf '%s\n' "$out" | grep -n 'DEV_SUITE_MUTEX_ACQUIRED' | cut -d: -f1 || true)
if [[ -n "$w_line" && -n "$a_line" && "$w_line" -lt "$a_line" ]]; then
  ok "WAITING precedes ACQUIRED in the output order"
else
  bad "output order wrong: WAITING@$w_line ACQUIRED@$a_line"
fi
_release ti-pr-runD D >/dev/null

# === Case: marker never printed — budget exhausts to CONTENDED_PROCEEDING ====
setup_case nevermark
rc=0; out=$(WAIT_S=1 _acquire ti-main-runE E 'STUB_NEVER_MARK=1' 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_CONTENDED_PROCEEDING'; then
  ok "silent holder exhausts the wait budget -> CONTENDED_PROCEEDING"
else
  bad "never-mark arm: rc=$rc out=$out"
fi
if printf '%s' "$out" | grep -qE 'DEV_SUITE_MUTEX_ACQUIRED'; then
  bad "never-mark arm falsely claimed ACQUIRED"
else
  ok "never-mark arm never claims ACQUIRED"
fi

# === Case: holder identity carries CR/LF — must not smuggle an annotation ====
setup_case inject
_acquire ti-main-runF F >/dev/null 2>&1 &
wait_lock || bad "first holder never took the stub lock (inject)"
rc=0; out=$(WAIT_S=1 _acquire ti-pr-runG G "STUB_HOLDER_NAME=evil"$'\r\n'"::error::PWNED" 2>&1) || rc=$?
n_err=$(printf '%s\n' "$out" | grep -cE '^::error::' || true)
if [[ "$n_err" == "0" ]]; then
  ok "DB-returned holder identity cannot smuggle a ::error:: annotation line"
else
  bad "holder identity smuggled an annotation line: $out"
fi
_release ti-main-runF F >/dev/null

# === Case: no database URL — fail-open with a named reason, never abort ======
setup_case nourl
rc=0; out=$(env PATH="$STUB_BIN:$PATH" STUB_DB_DIR="$STUB_DB_DIR" \
      DEV_SUITE_MUTEX_IDENTITY=ti-main-runH \
      DEV_SUITE_MUTEX_STATE_DIR="$STATE" \
      env -u DATABASE_URL_POOLER -u DATABASE_URL \
      bash "$SUT" acquire 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_UNAVAILABLE'; then
  ok "no DB url -> DEV_SUITE_MUTEX_UNAVAILABLE + rc=0 (fail-open)"
else
  bad "no-url arm: rc=$rc out=$out"
fi

# === Case: direct DATABASE_URL fallback — session lock, never over pooler ====
setup_case direct
rc=0; out=$(env PATH="$STUB_BIN:$PATH" STUB_DB_DIR="$STUB_DB_DIR" \
      DATABASE_URL="postgres://stub-direct.invalid/db" \
      DEV_SUITE_MUTEX_IDENTITY=ti-main-runI \
      DEV_SUITE_MUTEX_STATE_DIR="$STATE" \
      DEV_SUITE_MUTEX_WAIT_S=10 DEV_SUITE_MUTEX_HOLD_S=30 \
      env -u DATABASE_URL_POOLER \
      bash "$SUT" acquire 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -qE 'DEV_SUITE_MUTEX_ACQUIRED'; then
  ok "direct DATABASE_URL acquire succeeds"
else
  bad "direct-url arm: rc=$rc out=$out"
fi
if grep -q 'pg_advisory_xact_lock' "$STUB_DB_DIR/calls.log"; then
  bad "direct-url arm used the xact lock (should be session-scoped pg_advisory_lock)"
else
  ok "direct-url arm uses session-scoped pg_advisory_lock (not xact)"
fi
if grep -qE 'pg_advisory_lock\(hashtext' "$STUB_DB_DIR/calls.log"; then
  ok "direct-url arm calls pg_advisory_lock(hashtext(...))"
else
  bad "direct-url arm lacks the session-lock call"
fi
if grep -q 'URL postgres://stub-direct.invalid/db' "$STUB_DB_DIR/calls.log"; then
  ok "direct-url arm connected via DATABASE_URL (not the pooler)"
else
  bad "direct-url arm did not use DATABASE_URL"
fi
env STUB_DB_DIR="$STUB_DB_DIR" DEV_SUITE_MUTEX_STATE_DIR="$STATE" \
  DEV_SUITE_MUTEX_IDENTITY=ti-main-runI bash "$SUT" release >/dev/null

# === Case: session lock must NEVER run over the pooler =======================
# The inverse coupling — a session lock emitted while a pooler URL is the
# connection — leaks locks to unrelated pool renters. The free-acquire case
# already pins the xact call; this pins that the session form is absent.
setup_case poolernosession
rc=0; out=$(_acquire ti-main-runJ J 2>&1) || rc=$?
if ! grep -qE 'pg_advisory_lock\(hashtext' "$STUB_DB_DIR/calls.log"; then
  ok "pooler path never emits session-scoped pg_advisory_lock"
else
  bad "pooler path emitted a session-scoped lock (leak class)"
fi
_release ti-main-runJ J >/dev/null

# === Case: non-canonical identity — green must not depend on fixture values ==
setup_case noncanonical
rc=0; out=$(_acquire 'ti-refs/pull/9999/merge-run424242' K 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_ACQUIRED'; then
  ok "non-canonical identity acquires cleanly"
else
  bad "non-canonical identity: rc=$rc out=$out"
fi
_release 'ti-refs/pull/9999/merge-run424242' K >/dev/null

# === Case: release idempotence ==============================================
setup_case relidem
rc=0; out=$(_release ti-main-runK K 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_RELEASED'; then
  ok "release with nothing held is idempotent (RELEASED, rc=0)"
else
  bad "idempotent release: rc=$rc out=$out"
fi

# === Case: probe reports holder / free =======================================
setup_case probe
_acquire ti-main-runL L >/dev/null 2>&1 &
wait_lock || bad "first holder never took the stub lock (probe)"
rc=0; out=$(_probe ti-main-runL 'STUB_HOLDER_NAME=ti-main-runL' 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'ti-main-runL'; then
  ok "probe names the current holder"
else
  bad "probe held: rc=$rc out=$out"
fi
_release ti-main-runL L >/dev/null
wait_unlock || bad "stub lock never freed (probe)"
rc=0; out=$(_probe ti-main-runL 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'DEV_SUITE_MUTEX_FREE'; then
  ok "probe reports DEV_SUITE_MUTEX_FREE after release"
else
  bad "probe free: rc=$rc out=$out"
fi

# === Case: --help is discoverable ===========================================
rc=0; out=$(bash "$SUT" --help 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'dev-suite-mutex'; then
  ok "--help prints usage naming dev-suite-mutex"
else
  bad "--help: rc=$rc out=$out"
fi

# === anti-vacuity floor =====================================================
readonly MIN_ASSERTIONS=24
if [[ "$((pass + fail))" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' \
    "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo "---"
echo "test-dev-suite-mutex: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
