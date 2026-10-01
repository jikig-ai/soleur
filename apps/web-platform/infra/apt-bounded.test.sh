#!/usr/bin/env bash
#
# Unit suite for lib/apt-bounded.sh (#9379): one shared wall-clock bound on every in-container
# apt cycle in the git-data suites, with expiry routed to the declared environment decline
# (FIXTURE_APT_FAILED + exit 100) and every non-timeout failure keeping its own rc.
#
# Host-only: a stub `apt-get` on PATH and the real coreutils `timeout`; no docker, no network.
# Behaviour rows drive the helper in a fresh `bash` (set -u, the shell the container drivers
# give it). The assembly row is DERIVED from the two consumer suites rather than listed.
#
# Run: bash apps/web-platform/infra/apt-bounded.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${DIR}/lib/apt-bounded.sh"
OWN="${DIR}/git-data-ownership.test.sh"
REH="${DIR}/git-data-runcmd-rehearsal.test.sh"

passes=0; fails=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once inside a subshell and refuse to continue
# unless every observable moved. Reported with printf + exit, never through the helpers it guards.
_st="$( { pass st-a; fail st-b; } >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}" )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() did not move their counters and ledger (got "%s", want "1 1 1").\n' "$_st" >&2
  exit 1
fi

W="$(mktemp -d "${TMPDIR}/aptb.XXXXXX")"
trap 'rm -rf "$W"' EXIT
STUB="$W/bin"; mkdir -p "$STUB"
# Stub apt-get. Mode comes from GD_STUB_MODE; every invocation appends one line to GD_STUB_CALLS.
cat > "$STUB/apt-get" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >> "${GD_STUB_CALLS:?}"
n=$(wc -l < "${GD_STUB_CALLS}")
case "${GD_STUB_MODE:?}" in
  ok)   exit 0 ;;
  fail) echo "E: Failed to fetch http://alice:s3cr3t@proxy.invalid:3128/ubuntu/dists/noble/InRelease  Unable to connect" >&2; exit 100 ;;
  hang) sleep 300 & echo "$!" > "${GD_STUB_CHILD:?}"; wait ;;
  hang-once) if [ "$n" -eq 1 ]; then sleep 300 & echo "$!" > "${GD_STUB_CHILD:?}"; wait; fi; exit 0 ;;
  slow) sleep "${GD_STUB_SLEEP:-1}"; exit 0 ;;
  fail-then-ok) [ "$n" -eq 1 ] && { echo "E: transient" >&2; exit 100; }; exit 0 ;;
  oom)  exit 137 ;;
esac
exit 99
STUBEOF
chmod +x "$STUB/apt-get"

# run_helper <mode> <budget|unset> [pkg...] — sets RC OUT ERR CALLS ELAPSED. The state dir is rebuilt
# per call unless KEEP_STATE=1 (rows that chain calls to prove the budget is SHARED); PRE_SPENT seeds it.
run_helper() {
  local mode="$1" budget="$2"; shift 2
  OUT="$W/out"; ERR="$W/err"; CALLS="$W/calls"; : > "$CALLS"; : > "$OUT"; : > "$ERR"
  rm -f "$W/child"
  if [ "${KEEP_STATE:-0}" != 1 ]; then
    rm -rf "$W/state"
    if [ "$budget" != unset ]; then mkdir -p "$W/state"; printf '%s\n' "$budget" > "$W/state/budget"; printf '%s\n' "${PRE_SPENT:-}" | sed '/^$/d' > "$W/state/spent"; fi
  fi
  local t0; t0=$(date +%s)
  RC=0
  # shellcheck disable=SC2016  # single-quoted on purpose: expands inside the fresh bash
  env PATH="$STUB:$PATH" GD_STUB_MODE="$mode" GD_STUB_CALLS="$CALLS" GD_STUB_CHILD="$W/child" \
    GD_APT_LOG="$W/apt.log" GD_APT_BACKOFFS="0 0" GD_APT_STATE_DIR="$W/state" \
    bash --noprofile --norc -c 'set -u; . "$1" || exit 97; shift; gd_apt_install_bounded "$@"' _ "$LIB" "${@:-curl}" \
    >"$OUT" 2>"$ERR" || RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
}
calls() { wc -l < "$CALLS" | tr -d ' '; }
last_err_line() { tail -n 1 "$ERR"; }
spent_total() { awk '{s += $1} END {print s + 0}' "$W/state/spent"; }

checked=0
row() { checked=$((checked + 1)); }

# ── Rows ─────────────────────────────────────────────────────────────────────────────────
row; run_helper ok 60 curl python3
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ] && grep -q '^update ' "$CALLS" && grep -qE '^install .*Acquire::Retries=5.* curl python3$' "$CALLS" && ! grep -q . "$ERR"; then
  pass "A1: healthy archive — rc 0, update then install once each, nothing on stderr"
else fail "A1: healthy archive" "rc=$RC calls=$(calls) calls-file=[$(tr '\n' '|' < "$CALLS")] stderr=[$(head -c 200 "$ERR")]"; fi

row; run_helper hang 3 curl
_child="$(cat "$W/child" 2>/dev/null || true)"
_orphan=no; [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null && _orphan=yes
if [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 10 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] \
   && grep -qE '^FIXTURE_APT_CAUSE: timeout ' "$ERR" && [ -n "$_child" ] && [ "$_orphan" = no ] && [ "$(spent_total)" -ge 3 ]; then
  pass "A2: hung archive — bounded (${ELAPSED}s), rc 100, cause=timeout then the bare marker LAST, no orphan child, the time is charged"
else fail "A2: hung archive" "rc=$RC elapsed=${ELAPSED}s orphan=$_orphan child=[$_child] spent=$(spent_total) last=[$(last_err_line)] stderr=[$(head -c 300 "$ERR")]"; fi
[ -n "$_child" ] && kill "$_child" 2>/dev/null || true

row; PRE_SPENT=40 run_helper ok 30 curl
if [ "$RC" -eq 100 ] && [ "$(calls)" -eq 0 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && grep -qE '^FIXTURE_APT_CAUSE: timeout ' "$ERR"; then
  pass "A3: budget already spent by earlier containers — no apt invoked, same marker, rc 100"
else fail "A3: budget already spent" "rc=$RC calls=$(calls) last=[$(last_err_line)]"; fi

row; run_helper fail-then-ok 60 curl
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 3 ]; then
  pass "A4: transient failure then success — retry preserved (3 apt calls: update fail, update, install)"
else fail "A4: transient failure then success" "rc=$RC calls=$(calls)"; fi

row; GD_STUB_SLEEP=1 run_helper slow 30 curl
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ]; then
  pass "A5: slow archive inside the budget still passes (the bound must not reject a slow day)"
else fail "A5: slow archive inside the budget" "rc=$RC calls=$(calls) elapsed=${ELAPSED}s"; fi

row; run_helper oom 60 curl
if [ "$RC" -eq 137 ] && [ "$(calls)" -eq 1 ] && ! grep -qx FIXTURE_APT_FAILED "$ERR"; then
  pass "A6: an OOM-shaped kill (rc 137, no timeout) keeps its rc, is not retried, and does NOT emit the decline marker"
else fail "A6: OOM-shaped kill" "rc=$RC calls=$(calls) last=[$(last_err_line)]"; fi

row; run_helper fail 60 curl
if [ "$RC" -eq 100 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && ! grep -q 's3cr3t' "$ERR" && grep -q '\*\*\*' "$ERR" \
   && grep -qE '^FIXTURE_APT_CAUSE: apt-error ' "$ERR" && [ "$(calls)" -eq 3 ]; then
  pass "A7: exhausted apt errors — 3 attempts, credentials scrubbed from the tail, cause=apt-error, marker last, rc 100"
else fail "A7: exhausted apt errors" "rc=$RC calls=$(calls) last=[$(last_err_line)] stderr=[$(head -c 300 "$ERR")]"; fi

row; run_helper ok unset curl
if [ "$RC" -eq 98 ] && [ "$(calls)" -eq 0 ] && ! grep -qx FIXTURE_APT_FAILED "$ERR"; then
  pass "A8: an UNARMED budget (state mount forgotten) is a loud harness defect (rc 98), never a silent fallback or the decline"
else fail "A8: unarmed budget" "rc=$RC calls=$(calls) stderr=[$(head -c 200 "$ERR")]"; fi

row
_rc_missing=0
env PATH="$STUB:$PATH" bash --noprofile --norc -c '. /nonexistent/apt-bounded.sh || exit 97' >/dev/null 2>&1 || _rc_missing=$?
if [ "$_rc_missing" -eq 97 ]; then pass "A9: a missing lib at a loop site exits 97, not the environment-decline 100"
else fail "A9: missing lib" "rc=$_rc_missing"; fi

# A11 — the budget is SHARED: a second container inherits what the first spent. Two calls, one state.
row
GD_STUB_SLEEP=2 run_helper slow 6 curl      # ~4 s of apt time charged (update + install, 2 s each)
_first_rc=$RC
KEEP_STATE=1 run_helper hang 6 curl         # only ~2 s left: must be cut off near 2 s, not near 6
if [ "$_first_rc" -eq 0 ] && [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 6 ] && [ "$(spent_total)" -ge 6 ]; then
  pass "A11: shared budget — the second container inherited the first one's spend (cut off after ${ELAPSED}s, total charged $(spent_total)s of 6)"
else fail "A11: shared budget" "first-rc=$_first_rc rc=$RC elapsed=${ELAPSED}s spent=$(spent_total)"; fi
[ -f "$W/child" ] && kill "$(cat "$W/child")" 2>/dev/null || true

# A12 — only APT time is charged: sleeping OUTSIDE the helper between two containers spends nothing.
row
run_helper ok 4 curl
_first_rc=$RC
sleep 5
KEEP_STATE=1 run_helper ok 4 curl
if [ "$_first_rc" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(spent_total)" -le 2 ]; then
  pass "A12: non-apt time is not charged (5 s elapsed between containers on a 4 s budget; charged $(spent_total)s)"
else fail "A12: non-apt time charged" "first-rc=$_first_rc rc=$RC spent=$(spent_total)"; fi

# A13 — a STALLED attempt is cut at the per-attempt cap and retried: the first apt call hangs, the cap
# (2 s) kills it, the retry succeeds, and the 20 s budget was never close to spent. Without the cap the
# first attempt would own the whole budget (20 s) and the container would decline.
row; GD_APT_ATTEMPT_CAP=2 run_helper hang-once 20 curl
_child="$(cat "$W/child" 2>/dev/null || true)"; [ -n "$_child" ] && kill "$_child" 2>/dev/null || true
if [ "$RC" -eq 0 ] && [ "$ELAPSED" -le 8 ] && [ "$(calls)" -eq 3 ] && [ "$(spent_total)" -le 8 ]; then
  pass "A13: a stalled attempt is cut at the per-attempt cap and retried (rc 0 after ${ELAPSED}s, 3 apt calls, charged $(spent_total)s of 20)"
else fail "A13: per-attempt cap" "rc=$RC elapsed=${ELAPSED}s calls=$(calls) spent=$(spent_total)"; fi

# A14 — a PERSISTENT stall is bounded by attempts x cap, not by the whole budget: 3 attempts of 1 s.
row; GD_APT_ATTEMPT_CAP=1 run_helper hang 30 curl
_child="$(cat "$W/child" 2>/dev/null || true)"; [ -n "$_child" ] && kill "$_child" 2>/dev/null || true
if [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 10 ] && [ "$(calls)" -eq 3 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && grep -qE '^FIXTURE_APT_CAUSE: timeout .*attempt=3 ' "$ERR"; then
  pass "A14: a persistent stall is bounded by 3 capped attempts (${ELAPSED}s of a 30 s budget), cause=timeout, marker last"
else fail "A14: persistent stall" "rc=$RC elapsed=${ELAPSED}s calls=$(calls) stderr=[$(head -c 300 "$ERR")]"; fi

# ── Derived assembly row ─────────────────────────────────────────────────────────────────
# For each consumer suite: comment-stripped, continuation-joined. The number of `docker run --rm`
# commands that mount the lib, the number that pass the shared deadline, and the number of
# gd_apt_install_bounded calls must be EQUAL and non-zero, and no raw apt-get may sit in command
# position (anchored so the R4 INJECT test line and FIXTURE-FAIL message strings do not match).
_joined() { sed 's/^[[:space:]]*#.*$//' "$1" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}'; }
_asm=""; _tot=0
for f in "$OWN" "$REH"; do
  j="$(_joined "$f")"
  # shellcheck disable=SC2016  # a literal `$GD_APT_STATE` in the suite text, not an expansion
  m=$(printf '%s\n' "$j" | grep -E 'docker run --rm' | grep -cF '$GD_APT_STATE:/work/apt' || true)
  c=$(printf '%s\n' "$j" | grep -cE '^[[:space:]]*(if[[:space:]]+)?gd_apt_install_bounded[[:space:]]' || true)
  g=$(printf '%s\n' "$j" | grep -cE '^[[:space:]]*gd_apt_state_arm[[:space:]]' || true)
  raw=$(printf '%s\n' "$j" | grep -cE '^[[:space:]]*(if[[:space:]]+)?(timeout[[:space:]]+[^[:space:]]+[[:space:]]+)?apt-get[[:space:]]+(update|install)' || true)
  _tot=$((_tot + c))
  if [ "$m" -lt 1 ] || [ "$m" -ne "$c" ] || [ "$raw" -ne 0 ] || [ "$g" -ne "$m" ]; then
    _asm="${_asm} $(basename "$f"):[mounts=$m helper-calls=$c arm-calls=$g raw-apt=$raw]"
  fi
done
row
if [ -z "$_asm" ] && [ "$_tot" -eq 6 ]; then
  pass "A10: assembly (derived) — every apt-bearing docker run arms and mounts the shared state and calls the helper; no raw apt (6 sites)"
else fail "A10: assembly drift" "${_asm:-ok} total-helper-calls=$_tot (want 6)"; fi

# ── FLOOR + LEDGER (ADR-193: printf + exit inside the block, never through pass()/fail()) ──
if [ "$checked" -lt 14 ]; then
  printf 'FAIL ANTI-VACUITY: only %s rows ran, floor is 14 — rows were deleted or the suite exited early.\n' "$checked" >&2
  exit 1
fi
if [ "$((passes + fails))" -ne "$checked" ]; then
  printf 'FAIL ANTI-VACUITY: %s rows ran but %s verdicts were counted — a row asserted nothing or twice.\n' "$checked" "$((passes + fails))" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}"; exit 1
fi
printf '\n=== apt-bounded: %d passed, %d failed ===\n\n' "$passes" "$fails"
exit $(( ${#FAILURES[@]} > 0 ))
