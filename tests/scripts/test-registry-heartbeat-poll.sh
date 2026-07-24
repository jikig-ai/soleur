#!/usr/bin/env bash
# Test suite for scripts/registry-heartbeat-poll.sh (D11, #6929).
#
# The property under test is a TRANSITION, not a level — so the fixtures are STATEFUL stubs that
# change on the Nth invocation. A static stub can only probe t=0 and t=∞ and would never exercise
# the case the gate exists for (the dead host's residual `up`): with a stub that always says
# "up", a naive first-`up`-wins poll and the correct transition poll are indistinguishable.
# See 2026-07-19-my-own-mutation-battery-was-the-false-confidence.md.
#
# Every case pins RESIDUAL/DEADLINE/INTERVAL and stubs sleep to a no-op so the suite runs in
# milliseconds — but the stub COUNTS its calls, because a sleep stubbed to nothing would
# silently void the budget contract the deadline arms rely on.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
POLL="${ROOT}/scripts/registry-heartbeat-poll.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  printf '       rc=%s\n' "${2:-?}"
  printf '       out=%s\n' "${3:-}"
}

# A valid tfstate carrying the heartbeat address.
cat > "$TMP/tfstate.json" <<'EOF'
{"values":{"root_module":{"resources":[
  {"address":"betteruptime_heartbeat.registry_prd","values":{"id":"777001"}},
  {"address":"hcloud_server.registry","values":{"id":"5"}}
]}}}
EOF

# A tfstate WITHOUT the heartbeat (the resolve-failure case).
printf '{"values":{"root_module":{"resources":[]}}}' > "$TMP/tfstate-empty.json"

# make_stub <file> <status...> — echoes the Nth status on the Nth call, then repeats the last.
make_stub() {
  local f="$1"; shift
  local counter="${f}.n"
  printf '0' > "$counter"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'n=$(cat %q); n=$((n+1)); printf "%%s" "$n" > %q\n' "$counter" "$counter"
    printf 'seq=(%s)\n' "$(printf '%q ' "$@")"
    printf 'i=$(( n - 1 )); (( i >= ${#seq[@]} )) && i=$(( ${#seq[@]} - 1 ))\n'
    printf 'printf "%%s" "${seq[$i]}"\n'
  } > "$f"
  chmod +x "$f"
}

# A sleep stub that COUNTS calls (a no-op sleep would void the budget contract silently).
SLEEP_STUB="$TMP/sleep-stub.sh"
printf '#!/usr/bin/env bash\nn=$(cat %q 2>/dev/null || echo 0); printf "%%s" "$((n+1))" > %q\n' \
  "$TMP/sleep.n" "$TMP/sleep.n" > "$SLEEP_STUB"
chmod +x "$SLEEP_STUB"

run_poll() {
  printf '0' > "$TMP/sleep.n"
  REGISTRY_HB_STATUS_CMD="$1" \
  REGISTRY_HB_SLEEP_CMD="$SLEEP_STUB" \
  REGISTRY_HB_RESIDUAL_S="${RESIDUAL:-90}" \
  REGISTRY_HB_DEADLINE_S="${DEADLINE:-480}" \
  REGISTRY_HB_INTERVAL_S="${INTERVAL:-10}" \
    bash "$POLL" "${2:-$TMP/tfstate.json}" 2>&1
}

check() {
  local name="$1" want_rc="$2" needle="$3" stub="$4" state="${5-}"
  local out rc
  out="$(run_poll "$stub" "$state")"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== registry-heartbeat-poll ===\n\n'

# ── THE case this gate exists for ────────────────────────────────────────────────────────────
# The old host is dead but its beat has not yet expired. A naive first-`up`-wins poll reads that
# residual level at t=0 and reports the NEW host as beating — over a registry that is DARK.
#
# Phase A must refuse to accept an `up` sampled inside the residual window. Here the monitor
# holds the stale `up` for two samples and only then flips to `down`; a correct poll therefore
# cannot conclude anything until that flip, and must then wait for a genuinely new `up`.
make_stub "$TMP/residual-then-dark.sh" up up down down down down down down down down
RESIDUAL=90 DEADLINE=30 INTERVAL=10 \
  check "residual 'up' then dark forever => FAIL (the false-green this gate prevents)" \
    1 "never reached 'up'" "$TMP/residual-then-dark.sh"

# The DEFAULT residual bound is load-bearing and must strictly exceed period(60)+grace(30).
# A future edit that "corrects" it to the real 90 would re-arm the false-green above, because
# the timer starts at apply-return while the old host's last beat can land moments later.
default_residual=$(sed -n 's/^RESIDUAL_S="\${REGISTRY_HB_RESIDUAL_S:-\([0-9]*\)}"$/\1/p' "$POLL")
if [[ "$default_residual" =~ ^[0-9]+$ ]] && (( default_residual > 90 )); then
  pass "default residual (${default_residual}s) strictly exceeds period+grace (90s)"
else
  fail "default REGISTRY_HB_RESIDUAL_S must be a number strictly greater than 90 (period 60 + grace 30) — a bound of exactly period+grace expires while the residual 'up' is still in force" \
    "-" "parsed='${default_residual}'"
fi

# The honest recovery: residual up -> down (aged out) -> up (the NEW host beats).
make_stub "$TMP/recovers.sh" up up down down up
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "residual up -> down -> up (new host beats) => PASS" \
    0 "Liveness established" "$TMP/recovers.sh"

# Fast path: the very first sample is already non-up, so the residual window is provably over.
make_stub "$TMP/fast.sh" down up
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "first sample already non-up => Phase A exits early" \
    0 "aged out" "$TMP/fast.sh"

# Aged out but the new host never comes back — the dark-registry outcome, reported honestly.
make_stub "$TMP/never-back.sh" down down down down down down down down down down
RESIDUAL=90 DEADLINE=30 INTERVAL=10 \
  check "aged out but never returns => FAIL naming both causes" \
    1 "device-absent" "$TMP/never-back.sh"

# ── paused is a DISTINCT failure, not "not yet up" ───────────────────────────────────────────
make_stub "$TMP/paused.sh" paused
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "paused during residual window => distinct PAUSED failure" \
    1 "PAUSED" "$TMP/paused.sh"

make_stub "$TMP/paused-later.sh" down paused
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "paused during Phase B => distinct PAUSED failure" \
    1 "became PAUSED" "$TMP/paused-later.sh"

# ── fail-closed on an unreadable signal ──────────────────────────────────────────────────────
make_stub "$TMP/empty.sh" ""
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "API error (empty status) during residual => fail-closed" \
    1 "Refusing to report success" "$TMP/empty.sh"

make_stub "$TMP/empty-later.sh" down ""
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "API error during Phase B => fail-closed" \
    1 "failed while waiting" "$TMP/empty-later.sh"

# ── fail-closed on an unresolvable heartbeat id ──────────────────────────────────────────────
make_stub "$TMP/ok.sh" down up
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "heartbeat address absent from tfstate => fail-closed" \
    1 "not found in" "$TMP/ok.sh" "$TMP/tfstate-empty.json"

make_stub "$TMP/ok2.sh" down up
RESIDUAL=90 DEADLINE=480 INTERVAL=10 \
  check "tfstate file missing => fail-closed" \
    1 "tfstate JSON not found" "$TMP/ok2.sh" "$TMP/nope.json"

# ── argument validation ──────────────────────────────────────────────────────────────────────
out=$(REGISTRY_HB_STATUS_CMD="$TMP/ok.sh" REGISTRY_HB_RESIDUAL_S=0 \
        bash "$POLL" "$TMP/tfstate.json" 2>&1); rc=$?
if [[ "$rc" -eq 1 && "$out" == *"positive integer"* ]]; then
  pass "non-positive RESIDUAL => fail-closed on own argument"
else
  fail "non-positive RESIDUAL must fail-closed" "$rc" "$out"
fi

# ── the sleep budget is REAL, not a stub that silently no-ops ────────────────────────────────
# Without this, a `sleep` stubbed to nothing would void the deadline contract: the loops would
# spin to their bound instantly and every timing assertion above would pass vacuously.
make_stub "$TMP/budget.sh" up up up up up up up up up up up up
RESIDUAL=30 DEADLINE=40 INTERVAL=10 run_poll "$TMP/budget.sh" >/dev/null 2>&1
n=$(cat "$TMP/sleep.n")
# Phase A burns its full bound (status=up throughout): waited 0,10,20 -> 3 sleeps, then exits at
# 30. Phase B then sees `up` on its FIRST sample and returns immediately — 0 sleeps. Total 3.
if [[ "$n" == "3" ]]; then
  pass "sleep called exactly 3x (residual 30/10, Phase B returns on first sample) — budget contract holds"
else
  fail "sleep call count must be 3 (3 residual + 0 deadline); a no-op sleep would void every timing assertion" "$n" "counted=$n"
fi

# And the complementary budget: when Phase B has to burn its whole deadline.
make_stub "$TMP/budget2.sh" down down down down down down down down
RESIDUAL=30 DEADLINE=40 INTERVAL=10 run_poll "$TMP/budget2.sh" >/dev/null 2>&1
n=$(cat "$TMP/sleep.n")
# Phase A exits on the FIRST sample (already non-up) -> 0 sleeps. Phase B: 0,10,20,30 -> 4.
if [[ "$n" == "4" ]]; then
  pass "sleep called exactly 4x (Phase A early-exit + deadline 40/10) — budget contract holds"
else
  fail "sleep call count must be 4 (0 residual + 4 deadline)" "$n" "counted=$n"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
