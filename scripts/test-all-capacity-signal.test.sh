#!/usr/bin/env bash
# test-all-capacity-signal.test.sh — the mutation battery for #7545's pre-launch
# capacity signal.
#
# WHAT IS UNDER TEST. Four guards, each with its own mutation matrix in the plan
# (`knowledge-base/project/plans/2026-08-19-chore-test-all-pre-launch-capacity-gate-plan.md`):
#
#   Guard 1 — the capacity verdict (`tc_capacity_line`), derived from the SAME
#             single /proc walk tc_preamble's banners use, which never reports a
#             degraded reading as a healthy box.       [M1-M11b, H1-H4]
#   Guard 2 — `test-all.sh --capacity` is side-effect free.       [M12-M14, H5]
#   Guard 3 — the wait cannot abort, and is legible.              [M15-M18, H6]
#
# A Guard 4 (a diff-justification report) was CUT during review rather than
# fixed: it could not change a decision under either TEST_GROUP value (forbidden
# from advising under `all` by ADR-183 Ceiling 1, redundant under an explicit
# shard), it was a fifth hand-written path-prefix list where #7545 asked for
# reuse of scripts/lib/test-relevance-paths.sh, and it was already wrong —
# `.github/`, `CLAUDE.md`, `apps/cla-evidence/` and four apps/web-platform
# subtrees all reported `DIFF_TOUCHES: none`, the confidently-reassuring reading
# its own comment warned against.
#
# WHY A SIGNAL AND NOT A DECLINE. #7545 asked for a pre-launch DECISION that
# declines an over-capacity run. That was cut on review against measured
# evidence — ADR-133 records a wait `LOCK_ACQUIRED … after 616310ms`, i.e.
# REDEEMED at 616 s behind two siblings, which a `>= 1` sibling decline refuses
# at t=0, converting a gate that COMPLETED into no coverage at all. See the
# ADR-133 addendum and `decision-challenges.md` DC-2. Nothing here changes an
# exit code; every arm below asserts a STATEMENT, never a refusal.
#
# AUTHORING CONSTRAINTS (work/SKILL.md; each one cost a debug cycle somewhere):
#   - Never `producer | grep -q` under `set -o pipefail`: an EARLY match makes
#     grep close the pipe, the producer takes SIGPIPE (141), and pipefail turns
#     a genuine MATCH into a non-zero pipeline — so every NEGATIVE assertion
#     fails OPEN. Grep a FILE, or `grep -c` on a herestring.
#   - A deliberately-nonzero command inside `$( … )` aborts under `set -e`
#     before fail() can print — suffix `|| true` INSIDE the substitution.
#   - `cases` is incremented at the CALL SITE, never inside pass()/fail() and
#     never inside `$( … )` (a subshell increment is discarded).
#   - Every threshold gets below / AT / far-above rows. Without the AT row the
#     corresponding `>=`→`>` mutation is vacuous — the defect that made v1's own
#     mutation matrix unsound.
#   - must-PASS rows (H3/H4/H5/H6/H7) are as load-bearing as the RED rows: only
#     a must-PASS row catches a guard that rejects everything.
#
# ADR-193 COMPLIANCE. This file lives under `scripts/`, which
# `scripts/guard-vacuity-floor.test.sh` declares in its DERIVED population
# (`COVERED_DIRS='^(scripts/|plugins/soleur/test/)'`), so it is enrolled the
# moment it lands. All four decisions are satisfied at the bottom of this file:
# the floor `exit 1`s directly (D1), `cases` moves at the call site (D2), an
# accounting-conservation check is present (D3), and it runs BEFORE the floor
# (D4).
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): a fake procfs, a
# fake `df`, fake worktree dirs, and nothing written outside TESTROOT.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/test-contention.sh"
RUNNER="$REPO_ROOT/scripts/test-all.sh"

pass_n=0
fails=0
cases=0
# `cases` is incremented at the CALL SITE, never inside pass()/fail(). That
# placement is the whole substance of the conservation check at the bottom: a
# counter that moves inside both verdict helpers moves WITH the verdict, so
# stubbing fail() to a no-op drops the row and its count together and
# `pass_n + fails == cases` still holds.
# Every failure is ALSO appended to a file, and the exit decision at the bottom
# reads THAT, not the counter. Measured on the counter-only form: inserting a
# single `fails=0` line before the summary printed
#   === … 59 passed, 0 failed (66 assertions) ===
# and exited 0 — an arithmetic that is impossible on a green run (59 != 66),
# carrying seven real [FAIL] lines, landing in CI as `ok` because run_suite
# classifies purely on exit code. Conservation did not catch it because it ran
# upstream on the true counters; the floor did not because `cases` was intact.
# Silencing an append-only record means DELETING EVIDENCE, not moving a number.
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; printf '%s\n' "$1" >> "$FAILLOG"; }

TESTROOT="$(mktemp -d -t test-all-capacity.XXXXXXXX)"
FAILLOG="$TESTROOT/failures.log"
: > "$FAILLOG"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

for _required in "$LIB" "$RUNNER"; do
  if [[ ! -f "$_required" ]]; then
    echo "ERROR: $_required does not exist" >&2
    exit 1
  fi
done

CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"

# EVERY variable the SUT branches on is cleared before each fixture applies its
# own. Enumerated FROM THE SUT (`grep -oE '\$\{[A-Z_][A-Z0-9_]*' scripts/lib/test-contention.sh`),
# not from memory — fixing only the one that bit guarantees a next instance.
#
# WHY THIS IS NOT HYGIENE. `tc_acquire` returns EARLY on `CI` and on
# `SOLEUR_DISABLE_SESSION_STATE` (before the lock, the heartbeat and the
# re-sample), so with `CI` inherited every Guard 3 arm asserts against
# `LOCK_SKIPPED_CI` and this suite reports 58/8 — and it is REGISTERED in
# test-all.sh, which CI's required `test` context runs. Measured: 66/0 locally,
# 58/8 under `CI=1`, i.e. green for the author and red on merge.
# `_SOLEUR_TEST_CONTENTION_LOADED` is worse in kind: inherited as 1 it makes the
# lib's double-source guard `return` immediately, so nothing under test is even
# defined.
TC_CLEAN=(env
  -u CI
  -u SOLEUR_DISABLE_SESSION_STATE
  -u SOLEUR_SUBAGENT
  -u SOLEUR_ALLOW_FULL_GATE
  -u SOLEUR_TEST_FORCE_ALL
  -u _SOLEUR_TEST_CONTENTION_LOADED
  -u TC_PROC_ROOT -u TC_TMPDIR -u TC_XDG_DIR -u TC_SELF_PID
  -u TC_MIN_AVAIL_MB -u TC_NPROC -u TC_DF_CMD
  -u TC_SESSION_STATE -u TC_LOCK_TIMEOUT -u TC_WAIT_HEARTBEAT_S
  -u TC_LAST_SIB_COUNT -u TC_LAST_SIB_COUNT_OK
  -u TC_LAST_AVAIL_MB -u TC_LAST_AVAIL_MB_OK
  -u TC_LAST_MEMAVAIL_MB -u TC_LAST_MEMAVAIL_MB_OK
  -u TC_LAST_SIB_ROWS -u TC_LAST_SUITE_COUNT -u TC_LAST_SUITE_COUNT_OK
  # XDG_RUNTIME_DIR and TMPDIR were MISSING from this list while the comment
  # above claimed it was enumerated from the SUT. They are in that grep's output.
  # The consequence was concrete: TC_XDG_DIR was passed EMPTY, the lib reads it
  # with `:-` (which treats empty as unset), so tc_preamble fell through to the
  # operator's real $XDG_RUNTIME_DIR — a live directory with ~6400 entries — and
  # AC9's byte-identity assertion would flake on any file touched there between
  # its two calls, reporting "promoting variables must change no bytes".
  -u XDG_RUNTIME_DIR -u TMPDIR
)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A synthetic /proc entry. Mirrors scripts/test-contention.test.sh's helper so
# both suites exercise the same field layout: 19 filler fields so starttime
# lands at field 20 after the last ') '.
make_fake_proc() {
  local root="$1" pid="$2" cwd="$3" elapsed_s="$4" cmd="$5"
  local argv0="${6:-bash}" ppid="${7:-0}" pgrp="${8:-0}"
  local uptime=100000
  local starttime=$(( (uptime - elapsed_s) * CLK_TCK ))
  mkdir -p "$root/$pid"
  printf '%s 0.00\n' "$uptime" > "$root/uptime"
  printf '%s\0%s\0' "$argv0" "$cmd" > "$root/$pid/cmdline"
  local filler="S $ppid $pgrp" i
  for (( i = 4; i <= 19; i++ )); do filler+=" 0"; done
  printf '%s (te) st) %s %s 0 0\n' "$pid" "$filler" "$starttime" > "$root/$pid/stat"
  [[ -n "$cwd" ]] && ln -sfn "$cwd" "$root/$pid/cwd"
  printf 'MemAvailable:    7000000 kB\n' > "$root/meminfo"
  printf '3.96 9.72 14.60 2/2934 572235\n' > "$root/loadavg"
}

# A bystander process, so a "zero siblings" fixture still has READABLE process
# entries. This is what keeps `siblings=0` (a measurement) distinguishable from
# `unreadable_proc` (an absence of measurement) — without it the healthy fixture
# and the degraded fixture would be the same directory shape and AC5(c) could
# not be written at all.
add_bystander() {
  local root="$1"
  make_fake_proc "$root" 101010 "$TESTROOT/bystander-wt" 42 "scripts/some-other-script.sh"
}

# A fake `df` honouring the exact `-P -k <dir>` call shape every caller uses.
# $2 is the Available field in 1024-blocks, or a literal token for the
# unparseable arm.
make_df_stub() {
  local path="$1" avail_kb="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted-on"
echo "tmpfs 4194304 1000000 ${avail_kb} 25% /tmp"
EOF
  chmod +x "$path"
}

# Build a complete fixture directory and echo the env assignments that select
# it. Keyword args keep the call sites readable at 20+ arms.
#
#   siblings=N        distinct sibling WORKTREES running test-all.sh
#   sibling_pids=N    pids per worktree (to separate worktree-count from pid-count)
#   avail_kb=...      what the fake df reports as Available (1024-blocks)
#   meminfo=ok|gone   whether /proc/meminfo is readable
#   proc=ok|empty     whether the proc root carries readable process entries
# NOTE the directory is minted with `mktemp -d`, NOT a counter. Every call site
# is `FX=$(make_fixture …)`, i.e. a COMMAND SUBSTITUTION — a subshell — so an
# `N=$((N + 1))` here is discarded in the parent and every fixture would land in
# the same directory, silently ACCUMULATING sibling pids from previous fixtures.
# Measured while writing this suite: the 2-sibling fixture reported 5 and the
# at-threshold tmpfs row read as contended, because it was reading the previous
# arm's processes. That is the same subshell-increment trap this file's header
# warns about for `cases`, one construct over — and here it produced plausible
# wrong NUMBERS rather than an obvious error.
make_fixture() {
  local siblings=0 sibling_pids=1 avail_kb=3072000 meminfo=ok proc=ok cores=16 suites=0
  local kv
  for kv in "$@"; do
    case "$kv" in
      siblings=*)     siblings="${kv#*=}" ;;
      suites=*)       suites="${kv#*=}" ;;
      sibling_pids=*) sibling_pids="${kv#*=}" ;;
      avail_kb=*)     avail_kb="${kv#*=}" ;;
      meminfo=*)      meminfo="${kv#*=}" ;;
      proc=*)         proc="${kv#*=}" ;;
      cores=*)        cores="${kv#*=}" ;;
      *) echo "make_fixture: unknown key '$kv'" >&2; exit 2 ;;
    esac
  done

  local dir
  dir="$(mktemp -d "$TESTROOT/fx.XXXXXXXX")"
  local proc_root="$dir/proc" tmpdir="$dir/tmp" df_stub="$dir/df"
  mkdir -p "$proc_root" "$tmpdir"

  if [[ "$proc" == "ok" ]]; then
    add_bystander "$proc_root"
    local w p pid=200000
    for (( w = 1; w <= siblings; w++ )); do
      mkdir -p "$dir/wt-$w"
      for (( p = 1; p <= sibling_pids; p++ )); do
        pid=$((pid + 1))
        make_fake_proc "$proc_root" "$pid" "$dir/wt-$w" $(( 100 * w )) "scripts/test-all.sh"
      done
    done
    # Individual suites running in other worktrees — a second contention axis.
    # ppid/pgrp are set so the scan's ancestry/pgid cancellation does not absorb
    # them.
    local sp=300000 q
    for (( q = 1; q <= suites; q++ )); do
      sp=$((sp + 1)); mkdir -p "$dir/swt-$q"
      make_fake_proc "$proc_root" "$sp" "$dir/swt-$q" 45 "tests/scripts/test-foo.sh" bash 1 "$sp"
    done
  fi

  # `proc=empty` leaves the directory with no process entries — the AC5(c)
  # witness. It MUST still carry meminfo: without it the fixture was degraded on
  # TWO axes at once, and 2 of AC5(c)'s 3 rows then passed under their own defect
  # (a forced-healthy procfs probe) carried entirely by the meminfo signal. A
  # fixture degraded on two axes cannot attribute either.
  if [[ "$proc" == "empty" ]]; then
    printf 'MemAvailable:    7000000 kB\n' > "$proc_root/meminfo"
    printf '3.96 9.72 14.60 2/2934 572235\n' > "$proc_root/loadavg"
    printf '100000 0.00\n' > "$proc_root/uptime"
  fi

  if [[ "$proc" == "ok" && "$meminfo" == "gone" ]]; then
    rm -f "$proc_root/meminfo"
  fi

  make_df_stub "$df_stub" "$avail_kb"

  # TC_XDG_DIR points at a path that CANNOT exist, never at the empty string:
  # the lib reads it with `:-`, so empty means "fall through to the operator's
  # real XDG_RUNTIME_DIR" and the fixture stops being hermetic.
  printf 'TC_PROC_ROOT=%s\nTC_TMPDIR=%s\nTC_DF_CMD=%s\nTC_SELF_PID=999999\nTC_XDG_DIR=%s/nonexistent-xdg\nTC_NPROC=%s\n' \
    "$proc_root" "$tmpdir" "$df_stub" "$dir" "$cores"
}

# Run tc_preamble (to populate the promoted values) then tc_capacity_line, and
# echo ONLY the verdict line. Env assignments arrive on stdin from make_fixture.
verdict_for() {
  local env_block="$1"
  local -a envs=()
  local line
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done <<<"$env_block"
  "${TC_CLEAN[@]}" "${envs[@]}" bash -c '
    set -euo pipefail
    source "$1"
    tc_preamble >/dev/null 2>&1
    tc_capacity_line
  ' _ "$LIB" 2>/dev/null || true
}

# Same, but returns the preamble output AND the verdict, so an arm can assert
# the two agree (AC10).
preamble_and_verdict_for() {
  local env_block="$1"
  local -a envs=()
  local line
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done <<<"$env_block"
  "${TC_CLEAN[@]}" "${envs[@]}" bash -c '
    set -euo pipefail
    source "$1"
    tc_preamble 2>&1
    echo "---VERDICT---"
    tc_capacity_line
  ' _ "$LIB" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Guard 1 — the capacity verdict
# ---------------------------------------------------------------------------

echo "--- Guard 1: the capacity verdict ---"

# H3 (must-PASS): a healthy box must yield CAPACITY_OK. Only a must-PASS row
# catches a guard that rejects everything.
FX_HEALTHY="$(make_fixture siblings=0 avail_kb=3072000)"
V_HEALTHY="$(verdict_for "$FX_HEALTHY")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_HEALTHY" || true)" -ge 1 ]]; then
  pass "H3 must-PASS: a healthy fake box yields CAPACITY_OK"
else
  fail "H3 must-PASS: healthy box did not yield CAPACITY_OK; got: $V_HEALTHY"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_(CONTENDED|UNKNOWN)' <<<"$V_HEALTHY" || true)" -eq 0 ]]; then
  pass "H3 must-PASS: a healthy box emits neither CONTENDED nor UNKNOWN"
else
  fail "H3 must-PASS: healthy box emitted a non-OK verdict: $V_HEALTHY"
fi

# H4 (must-PASS): a non-canonical but healthy fixture. The contract permits core
# count and TC_TMPDIR to vary, so a guard keyed on either would be wrong.
FX_NONCANON="$(make_fixture siblings=0 avail_kb=2048000 cores=4)"
V_NONCANON="$(verdict_for "$FX_NONCANON")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_NONCANON" || true)" -ge 1 ]]; then
  pass "H4 must-PASS: a non-canonical healthy fixture (4 cores, own TMPDIR) still yields CAPACITY_OK"
else
  fail "H4 must-PASS: non-canonical healthy fixture did not yield CAPACITY_OK; got: $V_NONCANON"
fi

# --- AC3: the sibling threshold at below / AT / far-above -------------------
# M1 (delete the sibling arm) reddens on the 1- and 5-sibling rows.
# M3 (`>=` -> `>`) reddens on the AT row (1 sibling) SPECIFICALLY — that row is
# the entire reason the mutation is not vacuous.

FX_SIB1="$(make_fixture siblings=1 avail_kb=3072000)"
V_SIB1="$(verdict_for "$FX_SIB1")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$V_SIB1" || true)" -ge 1 ]]; then
  pass "AC3/M3 at-threshold: 1 sibling yields CAPACITY_CONTENDED"
else
  fail "AC3/M3 at-threshold: 1 sibling did not yield CONTENDED; got: $V_SIB1"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*sibling_runs' <<<"$V_SIB1" || true)" -ge 1 ]]; then
  pass "AC3: the 1-sibling verdict names reason=sibling_runs"
else
  fail "AC3: the 1-sibling verdict did not name sibling_runs; got: $V_SIB1"
fi

FX_SIB5="$(make_fixture siblings=5 avail_kb=3072000)"
V_SIB5="$(verdict_for "$FX_SIB5")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$V_SIB5" || true)" -ge 1 ]]; then
  pass "AC3 far-above: 5 siblings yields CAPACITY_CONTENDED"
else
  fail "AC3 far-above: 5 siblings did not yield CONTENDED; got: $V_SIB5"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'measured_runs=5' <<<"$V_SIB5" || true)" -ge 1 ]]; then
  pass "AC2/AC7: the verdict reports the measured runner count (5)"
else
  fail "AC2/AC7: the verdict did not report measured_runs=5; got: $V_SIB5"
fi

# --- AC2: distinct WORKTREES, not pids --------------------------------------
# M8 (count pids instead of distinct worktrees) reddens here.

FX_TWO_WT="$(make_fixture siblings=2 sibling_pids=1 avail_kb=3072000)"
V_TWO_WT="$(verdict_for "$FX_TWO_WT")"

cases=$((cases + 1))
if [[ "$(grep -cE 'measured_runs=2' <<<"$V_TWO_WT" || true)" -ge 1 ]]; then
  pass "AC2: two distinct sibling worktrees count as 2"
else
  fail "AC2: two distinct worktrees did not count as 2; got: $V_TWO_WT"
fi

FX_ONE_WT_TWO_PID="$(make_fixture siblings=1 sibling_pids=2 avail_kb=3072000)"
V_ONE_WT_TWO_PID="$(verdict_for "$FX_ONE_WT_TWO_PID")"

cases=$((cases + 1))
if [[ "$(grep -cE 'measured_runs=1' <<<"$V_ONE_WT_TWO_PID" || true)" -ge 1 ]]; then
  pass "AC2/M8: two pids in ONE worktree count as 1, not 2"
else
  fail "AC2/M8: two pids in one worktree did not count as 1; got: $V_ONE_WT_TWO_PID"
fi

# --- AC4: the tmpfs floor at below / AT / far-above -------------------------
# M2 (delete the tmpfs arm) reddens on the 1023 MB row.
# M4 (`<` -> `<=`) reddens on the AT row (1024 MB) SPECIFICALLY.
# 1 MB = 1024 * 1024 bytes = 1024 1024-blocks, so avail_kb = MB * 1024.

FX_TMP_BELOW="$(make_fixture siblings=0 avail_kb=$(( 1023 * 1024 )))"
V_TMP_BELOW="$(verdict_for "$FX_TMP_BELOW")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$V_TMP_BELOW" || true)" -ge 1 ]]; then
  pass "AC4 below-floor: 1023MB tmpfs yields CAPACITY_CONTENDED"
else
  fail "AC4 below-floor: 1023MB did not yield CONTENDED; got: $V_TMP_BELOW"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*low_tmp' <<<"$V_TMP_BELOW" || true)" -ge 1 ]]; then
  pass "AC4: the below-floor verdict names reason=low_tmp"
else
  fail "AC4: the below-floor verdict did not name low_tmp; got: $V_TMP_BELOW"
fi

FX_TMP_AT="$(make_fixture siblings=0 avail_kb=$(( 1024 * 1024 )))"
V_TMP_AT="$(verdict_for "$FX_TMP_AT")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_TMP_AT" || true)" -ge 1 ]]; then
  pass "AC4/M4 at-threshold: exactly 1024MB tmpfs is NOT contended (the floor is <, not <=)"
else
  fail "AC4/M4 at-threshold: 1024MB was treated as contended; got: $V_TMP_AT"
fi

FX_TMP_HIGH="$(make_fixture siblings=0 avail_kb=$(( 3000 * 1024 )))"
V_TMP_HIGH="$(verdict_for "$FX_TMP_HIGH")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_TMP_HIGH" || true)" -ge 1 ]]; then
  pass "AC4 far-above: 3000MB tmpfs is not contended"
else
  fail "AC4 far-above: 3000MB was treated as contended; got: $V_TMP_HIGH"
fi

# --- AC7: every line carries the measured value AND the threshold -----------
# M10 (drop the value or the threshold) reddens here.

cases=$((cases + 1))
if [[ "$(grep -cE 'sibling_threshold=[0-9]+' <<<"$V_SIB1" || true)" -ge 1 ]]; then
  pass "AC7/M10: the verdict carries the sibling THRESHOLD, not just the measurement"
else
  fail "AC7/M10: no sibling_threshold on the line; got: $V_SIB1"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'tmp_floor_mb=[0-9]+' <<<"$V_TMP_BELOW" || true)" -ge 1 ]]; then
  pass "AC7/M10: the verdict carries the tmpfs FLOOR, not just the measurement"
else
  fail "AC7/M10: no tmp_floor_mb on the line; got: $V_TMP_BELOW"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'tmp_avail_mb=1023' <<<"$V_TMP_BELOW" || true)" -ge 1 ]]; then
  pass "AC7/M10: the verdict carries the measured tmpfs value (1023)"
else
  fail "AC7/M10: no measured tmp_avail_mb on the line; got: $V_TMP_BELOW"
fi

# --- AC5: every degraded input yields UNKNOWN, never OK ---------------------
# M6 (collapse UNKNOWN into OK) reddens on all three.
# M11b (read the promoted value WITHOUT its validity flag) reddens on the df row
# specifically: tc_avail_mb degrades an unparseable probe to 0, which is below
# every floor, so the value alone reports CONTENDED reason=low_tmp — a degraded
# read presenting as a measured one, the exact collapse P5 forbids.

FX_DF_BAD="$(make_fixture siblings=0 avail_kb=not-a-number)"
V_DF_BAD="$(verdict_for "$FX_DF_BAD")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_UNKNOWN' <<<"$V_DF_BAD" || true)" -ge 1 ]]; then
  pass "AC5(b)/M11b: a non-numeric df reading yields CAPACITY_UNKNOWN"
else
  fail "AC5(b)/M11b: non-numeric df did not yield UNKNOWN; got: $V_DF_BAD"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*unparseable_df' <<<"$V_DF_BAD" || true)" -ge 1 ]]; then
  pass "AC5(b): the degraded-df verdict names reason=unparseable_df"
else
  fail "AC5(b): the degraded-df verdict did not name unparseable_df; got: $V_DF_BAD"
fi

# The discriminating half of M11b: the degraded df must NOT be reported as
# low_tmp. Without the validity flag it would be, because the value degraded to 0.
cases=$((cases + 1))
if [[ "$(grep -cE 'low_tmp' <<<"$V_DF_BAD" || true)" -eq 0 ]]; then
  pass "M11b: a degraded df is NOT reported as low_tmp (the value alone would say 0MB)"
else
  fail "M11b: a degraded df was reported as low_tmp — the validity flag is not being read; got: $V_DF_BAD"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_DF_BAD" || true)" -eq 0 ]]; then
  pass "AC5(b)/M6: a degraded df never reads as CAPACITY_OK"
else
  fail "AC5(b)/M6: a degraded df read as OK; got: $V_DF_BAD"
fi

FX_MEM_GONE="$(make_fixture siblings=0 avail_kb=3072000 meminfo=gone)"
V_MEM_GONE="$(verdict_for "$FX_MEM_GONE")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_UNKNOWN' <<<"$V_MEM_GONE" || true)" -ge 1 ]]; then
  pass "AC5(a): an unreadable /proc/meminfo yields CAPACITY_UNKNOWN"
else
  fail "AC5(a): unreadable meminfo did not yield UNKNOWN; got: $V_MEM_GONE"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*unparseable_meminfo' <<<"$V_MEM_GONE" || true)" -ge 1 ]]; then
  pass "AC5(a): the degraded-meminfo verdict names reason=unparseable_meminfo"
else
  fail "AC5(a): the degraded-meminfo verdict did not name unparseable_meminfo; got: $V_MEM_GONE"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_MEM_GONE" || true)" -eq 0 ]]; then
  pass "AC5(a)/M6: unreadable meminfo never reads as CAPACITY_OK"
else
  fail "AC5(a)/M6: unreadable meminfo read as OK; got: $V_MEM_GONE"
fi

FX_PROC_EMPTY="$(make_fixture proc=empty avail_kb=3072000)"
V_PROC_EMPTY="$(verdict_for "$FX_PROC_EMPTY")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_UNKNOWN' <<<"$V_PROC_EMPTY" || true)" -ge 1 ]]; then
  pass "AC5(c): a procfs with no readable process entries yields CAPACITY_UNKNOWN"
else
  fail "AC5(c): an unreadable procfs did not yield UNKNOWN; got: $V_PROC_EMPTY"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*unreadable_proc' <<<"$V_PROC_EMPTY" || true)" -ge 1 ]]; then
  pass "AC5(c): the degraded-procfs verdict names reason=unreadable_proc"
else
  fail "AC5(c): the degraded-procfs verdict did not name unreadable_proc; got: $V_PROC_EMPTY"
fi

# The discriminating half: an unusable procfs must not be reported as a
# CONFIDENT zero siblings. This is what separates "measured no siblings" from
# "could not measure siblings" — the same collapse as M11b, one signal over.
cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_PROC_EMPTY" || true)" -eq 0 ]]; then
  pass "AC5(c)/M6: an unusable procfs never reads as a healthy box with zero siblings"
else
  fail "AC5(c)/M6: an unusable procfs read as OK; got: $V_PROC_EMPTY"
fi

# --- AC6 / M7: per-signal precedence ----------------------------------------
# One reading degraded AND another over threshold => CONTENDED, with the
# degraded reading still NAMED. M7 (let one degraded reading suppress a
# CONTENDED verdict derived from a healthy one) reddens here.

FX_MIXED="$(make_fixture siblings=2 avail_kb=not-a-number)"
V_MIXED="$(verdict_for "$FX_MIXED")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$V_MIXED" || true)" -ge 1 ]]; then
  pass "AC6/M7: a degraded df does NOT suppress a CONTENDED verdict from the healthy sibling reading"
else
  fail "AC6/M7: mixed input did not yield CONTENDED; got: $V_MIXED"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'degraded=[^ ]*unparseable_df' <<<"$V_MIXED" || true)" -ge 1 ]]; then
  pass "AC6: the CONTENDED verdict still NAMES the degraded reading"
else
  fail "AC6: the CONTENDED verdict did not name the degraded reading; got: $V_MIXED"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*sibling_runs' <<<"$V_MIXED" || true)" -ge 1 ]]; then
  pass "AC6: the mixed verdict's reason is the signal that actually crossed a threshold"
else
  fail "AC6: the mixed verdict did not name sibling_runs; got: $V_MIXED"
fi

# --- Arms the review proved were missing (each one had a live defect) ---

# C1: the degraded RENDERING, not just the classification. Making the render
# unconditional survived at 66/0 while printing `measured_runs=0` for a procfs
# that could not be measured — an absence of measurement rendered as a
# measurement of absence, one field over from M11b, asserted by nothing.
cases=$((cases + 1))
if [[ "$(grep -cE 'measured_runs=\?' <<<"$V_PROC_EMPTY" || true)" -ge 1 ]]; then
  pass "C1: an unmeasurable procfs renders measured_runs=? — never a digit"
else
  fail "C1: an unmeasurable procfs rendered a NUMBER for the runner count; got: $V_PROC_EMPTY"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'tmp_avail_mb=\?' <<<"$V_DF_BAD" || true)" -ge 1 ]]; then
  pass "C1: an unparseable df renders tmp_avail_mb=? — never a digit"
else
  fail "C1: an unparseable df rendered a NUMBER for tmp avail; got: $V_DF_BAD"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'memavail_mb=\?' <<<"$V_MEM_GONE" || true)" -ge 1 ]]; then
  pass "C1: an unreadable meminfo renders memavail_mb=? — never a digit"
else
  fail "C1: an unreadable meminfo rendered a NUMBER for memavail; got: $V_MEM_GONE"
fi

# C2: EVERY field of the tail, not the three that happened to have arms. The
# whole `memavail_mb=` field could be deleted at 66/0.
cases=$((cases + 1))
_missing=""
for _f in measured_runs measured_suites sibling_threshold tmp_avail_mb tmp_floor_mb memavail_mb; do
  [[ "$(grep -cE "$_f=" <<<"$V_HEALTHY" || true)" -ge 1 ]] || _missing="${_missing:+$_missing,}$_f"
done
if [[ -z "$_missing" ]]; then
  pass "AC7/C2: the verdict tail carries every declared field"
else
  fail "AC7/C2: the verdict tail is missing field(s): $_missing; got: $V_HEALTHY"
fi

# C3: TWO signals contended at once. No fixture ever crossed both thresholds, so
# the `${contended:+$contended,}` accumulator only ever ran at one member and
# overwriting instead of joining survived — on a real box with both signals hot
# the verdict would silently drop sibling_runs.
FX_BOTH="$(make_fixture siblings=2 avail_kb=$(( 500 * 1024 )))"
V_BOTH="$(verdict_for "$FX_BOTH")"

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*sibling_runs' <<<"$V_BOTH" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'reason=[^ ]*low_tmp' <<<"$V_BOTH" || true)" -ge 1 ]]; then
  pass "C3: two crossed thresholds are BOTH named (the accumulator joins, not overwrites)"
else
  fail "C3: a verdict with two crossed thresholds dropped one; got: $V_BOTH"
fi

# The SUITE axis. tc_preamble computes suite_count and the first draft promoted
# only the runner count, so CAPACITY_OK was reachable on a box whose own
# SIBLING_SUITE_DETECTED banner was firing in the same run.
FX_SUITES="$(make_fixture siblings=0 suites=2 avail_kb=3072000)"
V_SUITES="$(verdict_for "$FX_SUITES")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$V_SUITES" || true)" -ge 1 ]]; then
  pass "suite-axis: sibling SUITES alone yield CAPACITY_CONTENDED (not a healthy box)"
else
  fail "suite-axis: sibling suites read as healthy — the false-OK this arm exists for; got: $V_SUITES"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*sibling_suites' <<<"$V_SUITES" || true)" -ge 1 ]]; then
  pass "suite-axis: the verdict names reason=sibling_suites"
else
  fail "suite-axis: the verdict did not name sibling_suites; got: $V_SUITES"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'measured_suites=2' <<<"$V_SUITES" || true)" -ge 1 ]]; then
  pass "suite-axis: the verdict reports the measured suite count (2)"
else
  fail "suite-axis: the verdict did not report measured_suites=2; got: $V_SUITES"
fi

# The FLOOR is an operator seam and must be shape-asserted like every other
# value. Measured before the guard: TC_MIN_AVAIL_MB=2G printed CAPACITY_OK on a
# tmpfs with 4MB free, rc=0, with the failed signal not even named as degraded.
FX_FLOOR="$(make_fixture siblings=0 avail_kb=$(( 4 * 1024 )))"
V_FLOOR_BAD="$(verdict_for "$(printf '%s\nTC_MIN_AVAIL_MB=2G\n' "$FX_FLOOR")")"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_OK' <<<"$V_FLOOR_BAD" || true)" -eq 0 ]]; then
  pass "floor: a non-numeric TC_MIN_AVAIL_MB never reads as a healthy box"
else
  fail "floor: TC_MIN_AVAIL_MB=2G reported CAPACITY_OK on a 4MB tmpfs; got: $V_FLOOR_BAD"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=[^ ]*unusable_floor' <<<"$V_FLOOR_BAD" || true)" -ge 1 ]]; then
  pass "floor: an unusable floor is NAMED, not silently skipped"
else
  fail "floor: an unusable floor was not named; got: $V_FLOOR_BAD"
fi

# not_probed: unset is a different fault from set-and-invalid, and reporting the
# second when the first is true sends a reader to investigate three probes that
# are all fine.
V_UNPROBED="$("${TC_CLEAN[@]}" bash -c 'set -euo pipefail; source "$1"; tc_capacity_line' _ "$LIB" 2>/dev/null || true)"

cases=$((cases + 1))
if [[ "$(grep -cE 'reason=not_probed' <<<"$V_UNPROBED" || true)" -ge 1 ]]; then
  pass "not_probed: a verdict with no preamble names the real fault, not three phantom probe failures"
else
  fail "not_probed: a verdict with no preamble misdiagnosed; got: $V_UNPROBED"
fi

# --- AC10 / M9: one walk, one source of truth -------------------------------
# The verdict must consume tc_preamble's promoted values, never re-walk /proc.
# M9 (have the verdict re-walk) reddens here because two non-atomic snapshots
# can disagree; this arm pins that they agree on a FIXED fixture, which is the
# falsifiable half.

PV_TWO="$(preamble_and_verdict_for "$FX_TWO_WT")"
PV_BANNER_N="$(sed -n 's/.*siblings: \([0-9]*\) other worktree.*/\1/p' <<<"$PV_TWO" | head -1 || true)"
PV_VERDICT_N="$(sed -n 's/.*measured_runs=\([0-9]*\).*/\1/p' <<<"$PV_TWO" | head -1 || true)"

cases=$((cases + 1))
if [[ -n "$PV_BANNER_N" && "$PV_BANNER_N" == "$PV_VERDICT_N" ]]; then
  pass "AC10/M9: the verdict's sibling count equals tc_preamble's banner count in the same run ($PV_BANNER_N)"
else
  fail "AC10/M9: verdict/banner sibling counts disagree (banner='$PV_BANNER_N' verdict='$PV_VERDICT_N')"
fi

# M9's STRUCTURAL half, and it is the half that can actually fail.
#
# The behavioural arm above cannot catch a re-walk on a HERMETIC fixture: a
# second walk over a fake /proc that nobody is mutating returns the same count,
# so the mutation "have the verdict re-walk /proc" would survive it as an
# equivalent mutant. The defect M9 names is not "a wrong number" but "a SECOND
# NON-ATOMIC SNAPSHOT", which only shows up on a live box where the sibling set
# changes between the two reads — precisely the box no suite can fixture.
#
# So the property is asserted where it is decidable: tc_capacity_line's body
# must contain no scan call at all. Anchored on the CALL construct rather than a
# bare word, so a mention in a comment cannot satisfy or break it.
TCL_BODY="$(sed -n '/^tc_capacity_line() {/,/^}/p' "$LIB")"

cases=$((cases + 1))
if [[ -n "$TCL_BODY" ]]; then
  if [[ "$(grep -cE '^[^#]*(_tc_scan_procs|tc_siblings)[[:space:]]*(\||$|\))' <<<"$TCL_BODY" || true)" -eq 0 ]]; then
    pass "AC10/M9 structural: tc_capacity_line takes no /proc walk of its own — it consumes tc_preamble's readings"
  else
    fail "AC10/M9 structural: tc_capacity_line calls a scan directly — that is a second non-atomic snapshot"
  fi
else
  fail "AC10/M9 structural: could not extract tc_capacity_line's body from the lib — the arm was NOT evaluated"
fi

# --- AC9: tc_preamble's stderr is byte-identical to origin/main's -----------
# Promoting VARIABLES must change zero output bytes: work/SKILL.md greps the
# `[contention] BANNER` names as a contract. Materialized by the repo's existing
# idiom (`git show origin/main:<path>`), as test-all-killed-classification.test.sh
# already does for the runner — without a named mechanism this AC is unfalsifiable.
# PINNED TO AN IMMUTABLE SHA, not to origin/main. Demonstrated during review:
# with origin/main pointed at this branch's own content (i.e. the state one
# second after merge), a banner regression injected into BOTH sides passed AC9
# green — the arm reduces to X == X and the byte-identity contract it exists to
# protect is unguarded from the merge commit onward.
#
# This is the pre-#7545 lib, the last commit before the promotion landed.
AC9_BASELINE_SHA="45ea9f7e9"
MAIN_LIB="$TESTROOT/baseline-test-contention.sh"
MAIN_LIB_OK=0
if git -C "$REPO_ROOT" show "${AC9_BASELINE_SHA}:scripts/lib/test-contention.sh" > "$MAIN_LIB" 2>/dev/null; then
  MAIN_LIB_OK=1
fi

cases=$((cases + 1))
if [[ "$MAIN_LIB_OK" == 1 ]]; then
  FX_BYTES="$(make_fixture siblings=2 avail_kb=$(( 900 * 1024 )))"
  _envs=()
  while IFS= read -r _l; do [[ -n "$_l" ]] && _envs+=("$_l"); done <<<"$FX_BYTES"
  OUT_NEW="$("${TC_CLEAN[@]}" "${_envs[@]}" bash -c 'source "$1"; tc_preamble' _ "$LIB" 2>&1 || true)"
  OUT_MAIN="$("${TC_CLEAN[@]}" "${_envs[@]}" bash -c 'source "$1"; tc_preamble' _ "$MAIN_LIB" 2>&1 || true)"
  if [[ "$OUT_NEW" == "$OUT_MAIN" ]]; then
    pass "AC9: tc_preamble's output is byte-identical to the pinned pre-#7545 baseline on a fixed fake /proc"
  else
    fail "AC9: tc_preamble's output DIFFERS from the pinned baseline — promoting variables must change no bytes"
    diff <(printf '%s\n' "$OUT_MAIN") <(printf '%s\n' "$OUT_NEW") | head -20 >&2 || true
  fi
else
  # Not silently skipped: a missing baseline is reported as its own outcome so
  # an unfalsifiable run cannot read as a clean one.
  fail "AC9: could not materialize the pinned baseline (git show failed) — AC9 was NOT evaluated"
fi

# --- M5: the guard's own dispatch -------------------------------------------
# A verdict-less run must not pass. Asserted against the RUNNER, since that is
# where the single call site lives.

echo "--- Guard 1: dispatch (M5) ---"

FX_DISPATCH="$(make_fixture siblings=0 avail_kb=3072000)"
_envs=()
while IFS= read -r _l; do [[ -n "$_l" ]] && _envs+=("$_l"); done <<<"$FX_DISPATCH"
CAP_OUT="$(cd "$REPO_ROOT" && "${TC_CLEAN[@]}" "${_envs[@]}" \
  bash "$RUNNER" --capacity 2>&1 || true)"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_(OK|CONTENDED|UNKNOWN)' <<<"$CAP_OUT" || true)" -ge 1 ]]; then
  pass "M5: the runner emits a named capacity verdict (a verdict-less run must not pass)"
else
  fail "M5: the runner emitted NO capacity verdict; got: $CAP_OUT"
fi

# --- M11 / AC15: the lib-stub arm -------------------------------------------
# With the lib absent the verdict must still be emitted, as
# CAPACITY_UNKNOWN reason=lib_unavailable — never silently vanish.

echo "--- Guard 1: lib-absent stub (M11 / AC15) ---"

STUB_SANDBOX="$TESTROOT/stub-sandbox"
mkdir -p "$STUB_SANDBOX/scripts/lib"
cp "$RUNNER" "$STUB_SANDBOX/scripts/test-all.sh"
# Deliberately do NOT copy scripts/lib/test-contention.sh: that is the fixture.
STUB_OUT="$(cd "$STUB_SANDBOX" && "${TC_CLEAN[@]}" \
  bash "$STUB_SANDBOX/scripts/test-all.sh" --capacity 2>&1 || true)"

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_UNKNOWN' <<<"$STUB_OUT" || true)" -ge 1 ]]; then
  pass "M11/AC15: with the lib absent the runner still emits CAPACITY_UNKNOWN"
else
  fail "M11/AC15: with the lib absent no capacity verdict was emitted; got: $STUB_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'lib_unavailable' <<<"$STUB_OUT" || true)" -ge 1 ]]; then
  pass "M11/AC15: the lib-absent verdict names reason=lib_unavailable"
else
  fail "M11/AC15: the lib-absent verdict did not name lib_unavailable; got: $STUB_OUT"
fi

# ---------------------------------------------------------------------------
# Guard 2 — `--capacity` is side-effect free
# ---------------------------------------------------------------------------

echo "--- Guard 2: --capacity is side-effect free ---"

# AC8: exits 0.
CAP_RC=0
(cd "$REPO_ROOT" && "${TC_CLEAN[@]}" "${_envs[@]}" \
  bash "$RUNNER" --capacity >/dev/null 2>&1) || CAP_RC=$?

cases=$((cases + 1))
if [[ "$CAP_RC" -eq 0 ]]; then
  pass "AC8: --capacity exits 0"
else
  fail "AC8: --capacity exited $CAP_RC, expected 0"
fi

# AC8 / M12: takes no lock. The absence of any LOCK_ line is the assertion —
# moving the branch below tc_acquire makes one appear.
cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_' <<<"$CAP_OUT" || true)" -eq 0 ]]; then
  pass "AC8/M12: --capacity emits no LOCK_ line (it takes no lock)"
else
  fail "AC8/M12: --capacity emitted a LOCK_ line — it is reaching tc_acquire; got: $CAP_OUT"
fi

# AC8 / M14: runs no suite. Both the per-suite header and the terminal marker
# are asserted absent, so a fall-through into the loop cannot go unnoticed.
cases=$((cases + 1))
if [[ "$(grep -cE '^=== [0-9]+/[0-9]+ suites passed ===$' <<<"$CAP_OUT" || true)" -eq 0 ]]; then
  pass "AC8/M14: --capacity never reaches the terminal suites-passed marker"
else
  fail "AC8/M14: --capacity reached the suite loop; got: $CAP_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^--- ' <<<"$CAP_OUT" || true)" -eq 0 ]]; then
  pass "AC8/M14: --capacity emits no per-suite header line"
else
  fail "AC8/M14: --capacity emitted a suite header; got: $CAP_OUT"
fi

# --capacity must report the per-sibling detail, which is what makes it useful
# for identifying WHICH worktree to wait for.
FX_CAPSIB="$(make_fixture siblings=2 avail_kb=3072000)"
_capenvs=()
while IFS= read -r _l; do [[ -n "$_l" ]] && _capenvs+=("$_l"); done <<<"$FX_CAPSIB"
CAPSIB_OUT="$(cd "$REPO_ROOT" && "${TC_CLEAN[@]}" "${_capenvs[@]}" \
  bash "$RUNNER" --capacity 2>&1 || true)"

cases=$((cases + 1))
if [[ "$(grep -cE 'pid [0-9]+ in ' <<<"$CAPSIB_OUT" || true)" -ge 2 ]]; then
  pass "--capacity reports the per-sibling pid/worktree detail for both siblings"
else
  fail "--capacity did not report per-sibling detail; got: $CAPSIB_OUT"
fi

# H5 (must-PASS) / M13: --capacity on a CONTENDED box still exits 0. AC8 alone
# pins only the general case; making it `exit 1` under contention is the
# mutation this row exists for — and it is the exact shape of the decline that
# was cut, so this row is also the regression guard for that reversal.
CAPSIB_RC=0
(cd "$REPO_ROOT" && "${TC_CLEAN[@]}" "${_capenvs[@]}" \
  bash "$RUNNER" --capacity >/dev/null 2>&1) || CAPSIB_RC=$?

cases=$((cases + 1))
if [[ "$CAPSIB_RC" -eq 0 ]]; then
  pass "H5 must-PASS/M13: --capacity on a CONTENDED box still exits 0 (it states, never refuses)"
else
  fail "H5 must-PASS/M13: --capacity exited $CAPSIB_RC on a contended box; the verdict must not block"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'CAPACITY_CONTENDED' <<<"$CAPSIB_OUT" || true)" -ge 1 ]]; then
  pass "H5: the contended --capacity run does report CONTENDED (the fixture is not vacuous)"
else
  fail "H5: the contended fixture did not produce a CONTENDED verdict; got: $CAPSIB_OUT"
fi

# ---------------------------------------------------------------------------
# Guard 3 — the wait cannot abort, and is legible
# ---------------------------------------------------------------------------

echo "--- Guard 3: the wait cannot abort, and is legible ---"

# A stub session-state.sh supplying acquire_lock. STUB_ACQUIRE_RC selects the
# acquired/contended arm and STUB_ACQUIRE_SLEEP how long the "wait" lasts, so
# the heartbeat has a real interval to fire in.
STUB_SS="$TESTROOT/session-state-stub.sh"
cat > "$STUB_SS" <<'EOF'
# RECORDS ITS ARGV. The previous stub was a pure function of two env vars the
# case set, discarding "$name" and "$timeout_s" — so no arm could witness the
# seam's contract, and dropping "$timeout_s" from tc_acquire's call survived at
# 66/0. The raised budget was asserted as a source literal and as an argument
# NOWHERE, while a real acquire_lock would silently use its own default.
acquire_lock() {
  printf '%s\n' "$*" > "${STUB_ARGV_FILE:-/dev/null}"
  sleep "${STUB_ACQUIRE_SLEEP:-0}"
  return "${STUB_ACQUIRE_RC:-0}"
}
EOF

# Drive tc_acquire under a fixture and report `rc=<n>` plus its stderr.
acquire_run() {
  local env_block="$1"; shift
  local -a envs=()
  local line
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done <<<"$env_block"
  "${TC_CLEAN[@]}" "${envs[@]}" TC_SESSION_STATE="$STUB_SS" "$@" bash -c '
    set -euo pipefail
    source "$1"
    tc_acquire "test-arm"
    echo "rc=$?"
  ' _ "$LIB" 2>&1 || echo "rc=ABORTED"
}

# H6 (must-PASS): an uncontended acquire emits LOCK_ACQUIRED and no heartbeat.
FX_ACQ_OK="$(make_fixture siblings=0 avail_kb=3072000)"
ACQ_OK_OUT="$(acquire_run "$FX_ACQ_OK" STUB_ACQUIRE_RC=0 STUB_ACQUIRE_SLEEP=0 TC_WAIT_HEARTBEAT_S=60)"

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_ACQUIRED' <<<"$ACQ_OK_OUT" || true)" -ge 1 ]]; then
  pass "H6 must-PASS: an uncontended acquire still emits LOCK_ACQUIRED"
else
  fail "H6 must-PASS: no LOCK_ACQUIRED on the uncontended arm; got: $ACQ_OK_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_WAIT_HEARTBEAT' <<<"$ACQ_OK_OUT" || true)" -eq 0 ]]; then
  pass "H6 must-PASS: an uncontended acquire emits NO heartbeat (it never waited)"
else
  fail "H6 must-PASS: a heartbeat fired on an acquire that never waited; got: $ACQ_OK_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^rc=0$' <<<"$ACQ_OK_OUT" || true)" -ge 1 ]]; then
  pass "AC11/M15: tc_acquire returns 0 on the uncontended arm"
else
  fail "AC11/M15: tc_acquire did not return 0 on the uncontended arm; got: $ACQ_OK_OUT"
fi

# AC12 / M16: the heartbeat names the holder and fires at the interval.
FX_ACQ_HB="$(make_fixture siblings=1 avail_kb=3072000)"
ACQ_HB_OUT="$(acquire_run "$FX_ACQ_HB" STUB_ACQUIRE_RC=0 STUB_ACQUIRE_SLEEP=3 TC_WAIT_HEARTBEAT_S=1)"

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_WAIT_HEARTBEAT' <<<"$ACQ_HB_OUT" || true)" -ge 1 ]]; then
  pass "AC12/M16: the wait emits a heartbeat while blocked"
else
  fail "AC12/M16: no heartbeat during a 3s wait at a 1s interval; got: $ACQ_HB_OUT"
fi

# The beat names the LOCK, not a "holder". Identifying the holder was cut: the
# old line took head -1 of a /proc walk, which named a fellow WAITER ~83% of the
# time on the pileup this feature exists for, and cost ~6 s of /proc walking per
# beat on an already-contended box.
cases=$((cases + 1))
if [[ "$(grep -cE "LOCK_WAIT_HEARTBEAT.*test-arm" <<<"$ACQ_HB_OUT" || true)" -ge 1 ]]; then
  pass "AC12: the heartbeat names the lock it is waiting on"
else
  fail "AC12: the heartbeat does not name the lock; got: $ACQ_HB_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_WAIT_HEARTBEAT.*(holder pid=|worktree=)' <<<"$ACQ_HB_OUT" || true)" -eq 0 ]]; then
  pass "AC12: the heartbeat claims NO holder identity (it cannot know it)"
else
  fail "AC12: the heartbeat asserts a holder it cannot know; got: $ACQ_HB_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_WAIT_HEARTBEAT.*BANNER' <<<"$ACQ_HB_OUT" || true)" -ge 1 ]] \
   || [[ "$(grep -cE '\[contention\] BANNER LOCK_WAIT_HEARTBEAT' <<<"$ACQ_HB_OUT" || true)" -ge 1 ]]; then
  pass "AC12: the heartbeat carries the BANNER prefix work/SKILL.md's triage grep reads"
else
  fail "AC12: the heartbeat is invisible to the documented triage grep; got: $ACQ_HB_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_WAIT_HEARTBEAT.*waited=[0-9]+s of [0-9]+s' <<<"$ACQ_HB_OUT" || true)" -ge 1 ]]; then
  pass "AC12: the heartbeat reports MEASURED elapsed against its budget"
else
  fail "AC12: the heartbeat does not report elapsed seconds; got: $ACQ_HB_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^rc=0$' <<<"$ACQ_HB_OUT" || true)" -ge 1 ]]; then
  pass "AC11/M15: tc_acquire returns 0 on the heartbeat arm"
else
  fail "AC11/M15: tc_acquire did not return 0 on the heartbeat arm; got: $ACQ_HB_OUT"
fi

# AC13 / M17: the contended banner re-samples the sibling count rather than
# reporting tc_preamble's reading, which after a full budget is stale.
FX_ACQ_RESAMPLE="$(make_fixture siblings=3 avail_kb=3072000)"
ACQ_RS_OUT="$(acquire_run "$FX_ACQ_RESAMPLE" STUB_ACQUIRE_RC=1 STUB_ACQUIRE_SLEEP=0 TC_WAIT_HEARTBEAT_S=60)"

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_CONTENDED_PROCEEDING' <<<"$ACQ_RS_OUT" || true)" -ge 1 ]]; then
  pass "AC13: the contended arm emits LOCK_CONTENDED_PROCEEDING"
else
  fail "AC13: no LOCK_CONTENDED_PROCEEDING on the contended arm; got: $ACQ_RS_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_CONTENDED_PROCEEDING.*siblings_now=3' <<<"$ACQ_RS_OUT" || true)" -ge 1 ]]; then
  pass "AC13/M17: the contended banner reports a RE-SAMPLED sibling count (3)"
else
  fail "AC13/M17: the contended banner does not report a re-sampled count; got: $ACQ_RS_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^rc=0$' <<<"$ACQ_RS_OUT" || true)" -ge 1 ]]; then
  pass "AC11/M15: tc_acquire returns 0 on the contended arm (ADR-133 Decision 3: proceeds, never aborts)"
else
  fail "AC11/M15: tc_acquire did not return 0 on the contended arm; got: $ACQ_RS_OUT"
fi

# M18 — THE zero-sibling contended arm. `grep -c` exits 1 on a zero count, so a
# re-sample copying tc_preamble's counting idiom WITHOUT its trailing `|| true`
# aborts tc_acquire under `set -e`. And zero siblings is the EXPECTED post-wait
# state (the holder exited — that is why the lock was released), so the naive
# implementation breaks the never-abort property on the single most common path.
# `tc_acquire "test-all"` is a bare top-level command in the runner, so that
# abort kills the whole run with no summary, no rc file and no [FAIL] line.
FX_ACQ_ZERO="$(make_fixture siblings=0 avail_kb=3072000)"
ACQ_ZERO_OUT="$(acquire_run "$FX_ACQ_ZERO" STUB_ACQUIRE_RC=1 STUB_ACQUIRE_SLEEP=0 TC_WAIT_HEARTBEAT_S=60)"

cases=$((cases + 1))
if [[ "$(grep -cE '^rc=ABORTED$' <<<"$ACQ_ZERO_OUT" || true)" -eq 0 ]]; then
  pass "M18: tc_acquire does not ABORT when the post-wait sibling count is zero"
else
  fail "M18: tc_acquire ABORTED on zero post-wait siblings — the grep -c or-true guard is missing; got: $ACQ_ZERO_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^rc=0$' <<<"$ACQ_ZERO_OUT" || true)" -ge 1 ]]; then
  pass "AC11/M15/M18: tc_acquire returns 0 on the ZERO-sibling contended arm (the common post-wait state)"
else
  fail "AC11/M15/M18: tc_acquire did not return 0 on the zero-sibling contended arm; got: $ACQ_ZERO_OUT"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'LOCK_CONTENDED_PROCEEDING.*siblings_now=0' <<<"$ACQ_ZERO_OUT" || true)" -ge 1 ]]; then
  pass "AC13/M18: the zero-sibling contended banner reports siblings_now=0 rather than omitting the field"
else
  fail "AC13/M18: the zero-sibling contended banner did not report siblings_now=0; got: $ACQ_ZERO_OUT"
fi

# AC14: the raised budget must exceed the measured full-gate hold time. Read the
# default out of the lib by SHAPE, so a future edit of the constant is caught
# rather than a stale literal being re-asserted here.
TC_TIMEOUT_DEFAULT="$(sed -n 's/^TC_LOCK_TIMEOUT="\${TC_LOCK_TIMEOUT:-\([0-9]*\)}"$/\1/p' "$LIB" | head -1 || true)"

cases=$((cases + 1))
if [[ "$TC_TIMEOUT_DEFAULT" =~ ^[0-9]+$ ]] && (( TC_TIMEOUT_DEFAULT >= 2700 )); then
  pass "AC14: TC_LOCK_TIMEOUT's default ($TC_TIMEOUT_DEFAULT s) exceeds the ~2700s measured full-gate hold time"
else
  fail "AC14: TC_LOCK_TIMEOUT's default ('$TC_TIMEOUT_DEFAULT') does not exceed the ~2700s hold time — the budget expires by construction"
fi

# The seam must be documented in the lib's own TEST SEAMS block (plan Phase 2.1b).
cases=$((cases + 1))
if [[ "$(grep -cE '^#   TC_WAIT_HEARTBEAT_S' "$LIB" || true)" -ge 1 ]]; then
  pass "Phase 2.1b: TC_WAIT_HEARTBEAT_S is listed in the lib's TEST SEAMS block"
else
  fail "Phase 2.1b: TC_WAIT_HEARTBEAT_S is missing from the lib's TEST SEAMS block"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^#   TC_DF_CMD' "$LIB" || true)" -ge 1 ]]; then
  pass "Phase 2.1b: TC_DF_CMD (a pre-existing omission) is listed in the lib's TEST SEAMS block"
else
  fail "Phase 2.1b: TC_DF_CMD is missing from the lib's TEST SEAMS block"
fi

# ---------------------------------------------------------------------------
# Arms for the REVIEW FIXES themselves. A review-driven fix lands after the
# tests, so nothing forces coverage for it — which is the same blind spot the
# fix closed, one layer out. Each of these was mutation-proven.
# ---------------------------------------------------------------------------

echo "--- review-fix arms ---"

# The lib-stub guard must name EVERY function whose absence would abort, not one
# believed to dominate. Reproduced before the fix: a lib carrying tc_acquire but
# not tc_capacity_line left the stubs uninstalled and the runner exited 127 with
# no summary, no rc file and no [FAIL] line.
SKEW_DIR="$TESTROOT/skew"
mkdir -p "$SKEW_DIR/scripts/lib"
cp "$RUNNER" "$SKEW_DIR/scripts/test-all.sh"
cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$SKEW_DIR/scripts/lib/" 2>/dev/null || true
# a lib with tc_acquire and NO tc_capacity_line
{ echo 'tc_preamble() { :; }'; echo 'tc_epilogue() { :; }'; echo 'tc_tmp_entry_count() { printf "0\n"; }'
  echo 'tc_used_bytes() { printf "0\n"; }'; echo 'tc_siblings() { :; }'; echo 'tc_acquire() { :; }'
} > "$SKEW_DIR/scripts/lib/test-contention.sh"
SKEW_RC=0
SKEW_OUT="$(cd "$SKEW_DIR" && "${TC_CLEAN[@]}" bash scripts/test-all.sh --capacity 2>&1)" || SKEW_RC=$?

cases=$((cases + 1))
if [[ "$SKEW_RC" -eq 0 && "$(grep -cE 'CAPACITY_UNKNOWN' <<<"$SKEW_OUT" || true)" -ge 1 ]]; then
  pass "skew: --capacity against a lib missing tc_capacity_line still answers, named, exit 0"
else
  fail "skew: --capacity did not answer under version skew (rc=$SKEW_RC); got: $SKEW_OUT"
fi

# THE STUB BLOCK'S ASSEMBLY, asserted directly. The behavioural arm above cannot
# reach it: --capacity carries its OWN `declare -F` guard, so it answers
# correctly whatever the stub block does. The regression that matters is on the
# NORMAL run path, where a bare top-level call to an undefined function exits 127
# under `set -e` with no summary, no rc file and no [FAIL] line. Measured: this
# arm named that property while testing a different one, and the mutation
# reverting the guard to `tc_acquire` alone SURVIVED at 80/0 until this replaced
# it. The property is "every lib function the runner calls at top level is
# covered by the stub block", so it is asserted over that set, not over a sample.
# Each capture below carries `|| true` INSIDE the substitution: grep exits 1 on
# no-match, pipefail propagates it, and under this file's `set -e` the assignment
# would kill the suite — making the "could not extract / arm NOT evaluated"
# branches below unreachable, i.e. the exact fail-open they exist to report.
# Caught by scripts/lint-shell-capture-exit.py, not by ten review agents.
#
# THE GUARD MUST FIRE WHENEVER ANY STUBBED FUNCTION IS MISSING. Being stubbed is
# worthless if the guard never trips — the body only runs when the condition
# does. Measured: an "is it named in the guard OR stubbed in the body" assertion
# ALSO survived the mutation, because every function is stubbed by construction.
# The decidable property is set equality between what the block stubs and what
# the guard checks.
STUB_BODY="$(awk '/^_tc_lib_incomplete=0$/,/^fi$/' "$RUNNER")"
STUBBED="$(grep -oE '^  tc_[a-z_]+\(\)' "$RUNNER" | tr -d ' ()' | sort -u || true)"
CHECKED="$(grep -oE '^_TC_STUBBED_FNS="[^"]*"' "$RUNNER" | sed 's/^_TC_STUBBED_FNS="//; s/"$//' | tr ' ' '\n' | sort -u || true)"

cases=$((cases + 1))
if [[ -n "$STUBBED" && -n "$CHECKED" ]]; then
  _unchecked="$(comm -23 <(printf '%s\n' "$STUBBED") <(printf '%s\n' "$CHECKED") | tr '\n' ',' )"
  if [[ -z "${_unchecked//,/}" ]]; then
    pass "stub assembly: every function the block stubs is also checked by its guard ($(wc -l <<<"$CHECKED") fns)"
  else
    fail "stub assembly: stubbed but NOT checked by the guard: ${_unchecked%,} — version skew leaves the stubs uninstalled and the runner exits 127"
  fi
else
  fail "stub assembly: could not extract the stub set (stubbed='$STUBBED' checked='$CHECKED') — arm NOT evaluated"
fi

# --capacity must consume tc_preamble's promoted rows, never walk again. The
# behavioural arm cannot see this (two walks over a hermetic fixture agree), so
# it is asserted where it is decidable: the branch's own source.
CAP_BLOCK="$(awk '/^if \[\[ "\$\{1:-\}" == "--capacity" \]\]; then$/,/^fi$/' "$RUNNER")"

cases=$((cases + 1))
if [[ -n "$CAP_BLOCK" ]]; then
  if [[ "$(grep -cE '^[^#]*(tc_siblings|_tc_scan_procs)' <<<"$CAP_BLOCK" || true)" -eq 0 ]]; then
    pass "--capacity takes NO second /proc walk (it reads the promoted rows)"
  else
    fail "--capacity walks /proc again — the verdict and its own detail rows can then disagree"
  fi
else
  fail "--capacity: could not extract the branch — this arm was NOT evaluated"
fi

cases=$((cases + 1))
if [[ "$(grep -cE 'TC_LAST_SIB_ROWS' <<<"$CAP_BLOCK" || true)" -ge 1 ]]; then
  pass "--capacity reads TC_LAST_SIB_ROWS (one walk, one source of truth)"
else
  fail "--capacity does not read the promoted rows"
fi

# This suite's OWN exit decision must read an append-only record. Measured on the
# counter form: one inserted `fails=0` printed "59 passed, 0 failed (66
# assertions)" and exited 0, landing in CI as ok.
SELF_SRC="$(grep -vE '^[[:space:]]*#' "$0" || true)"

cases=$((cases + 1))
if [[ "$(grep -cF 'FAILLOG' <<<"$SELF_SRC" || true)" -ge 2 ]] \
   && [[ "$(grep -cE '^\[\[ ! -s "\$FAILLOG" \]\] \|\| exit 1$' <<<"$SELF_SRC" || true)" -ge 1 ]]; then
  pass "self: the exit decision reads the append-only failure log, not a mutable counter"
else
  fail "self: the exit decision reads a counter — one assignment can zero it and still exit 0"
fi

# The heartbeat must MEASURE elapsed, not accumulate nominal intervals (the
# accumulator drifted ~11% low and overshot its own orphan bound).
HB_BODY="$(awk '/^_tc_wait_heartbeat\(\) \{/,/^\}/' "$LIB")"

cases=$((cases + 1))
if [[ "$(grep -cE 'EPOCHSECONDS' <<<"$HB_BODY" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'waited=\$\(\( waited \+ interval \)\)' <<<"$HB_BODY" || true)" -eq 0 ]]; then
  pass "heartbeat: elapsed is read from a clock, never summed from nominal intervals"
else
  fail "heartbeat: elapsed is accumulated — it drifts by the cost of each beat"
fi

cases=$((cases + 1))
if [[ "$(grep -cE '^[^#]*(tc_siblings|_tc_scan_procs)' <<<"$HB_BODY" || true)" -eq 0 ]]; then
  pass "heartbeat: no /proc walk per beat (~313 CPU-s per wait, on a fork-starved box)"
else
  fail "heartbeat: walks /proc per beat — the diagnostic participates in the incident"
fi

# ---------------------------------------------------------------------------
# Registration (AC18) — asserted on the invoked PATH, not only the label.
# `scripts/lint-orphan-test-suites.sh` derives coverage from the path, so a
# label-only assertion would pass a registration whose path is typo'd.
# ---------------------------------------------------------------------------

echo "--- Registration ---"

cases=$((cases + 1))
if [[ "$(grep -cE 'bash scripts/test-all-capacity-signal\.test\.sh' "$RUNNER" || true)" -ge 1 ]]; then
  pass "AC18: this suite is registered in test-all.sh by its invoked PATH"
else
  fail "AC18: this suite has no run_suite registration in test-all.sh — repo-root scripts/*.test.sh is NOT auto-discovered, so it would run in zero runners and stay green forever"
fi

# ---------------------------------------------------------------------------
# AC17 — no exit-code contract changed.
# The EXIT CONTRACT block is the runner's published semantics; this PR ships a
# statement, never a refusal, so the block must be untouched.
# ---------------------------------------------------------------------------

cases=$((cases + 1))
if [[ "$(grep -cE '^# EXIT CONTRACT' "$RUNNER" || true)" -ge 1 ]]; then
  pass "AC17: the runner still carries its EXIT CONTRACT block"
else
  fail "AC17: the EXIT CONTRACT block is missing from the runner"
fi

# ---------------------------------------------------------------------------
# ADR-193 D3/D4 — accounting conservation, evaluated BEFORE the floor.
#
# The floor below catches "no assertions RAN". It cannot catch "assertions ran
# and their verdicts were discarded", because `cases` keeps its full value when
# fail() is a no-op. Every assertion records exactly one verdict, so
# pass_n + fails MUST equal cases. Reported DIRECTLY (never through this suite's
# own fail()), because a check enforced through the suspect cannot witness the
# suspect — that is H1.
#
# ORDERING (ADR-193 Decision 4): conservation runs FIRST. A neutered fail()
# deflates the counts, so the floor would ALSO trip and would name the wrong
# fault ("assertions were added or removed" instead of "a verdict was
# discarded").
#
# MEASURED, and the first attempt at the H1 row was WRONG — recorded because the
# wrong version looks like coverage. Neutering fail() ALONE survives: on a green
# tree no fail() ever fires, so pass_n=66/fails=0/cases=66 still conserves and
# the suite exits 0. That is not an equivalent mutant, it is a fixture that does
# not exercise the property — H1's claim is "a discarded verdict cannot hide a
# REAL failure", and a green tree has no real failure to hide.
#
# The row that actually tests it is COMPOSITE: neuter fail() *and* inject a
# genuine defect (M1, deleting the sibling arm). Measured: the suite then prints
# `59 passed, 0 failed (66 assertions)` — which without this check exits 0 and
# reads as clean while concealing seven real failures — and this check fires
# `pass_n+fails (59) != cases (66)`, naming the discarded verdict.
# ---------------------------------------------------------------------------

if [[ $((pass_n + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass_n+fails (%d) != cases (%d).\n' \
    "$((pass_n + fails))" "$cases" >&2
  if [[ $((pass_n + fails)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== test-all-capacity-signal: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# ADR-193 D1/H2 — the anti-vacuity floor.
#
# `exit 1` DIRECTLY, never through this suite's own fail(): a floor routed
# through the verdict helper cannot witness a broken verdict helper (H1). H2 —
# delete every fixture so zero arms run — fails here on `0 passed, 0 failed`.
#
# DERIVED BY RUNNING THE AS-WRITTEN FILE, never estimated from the plan's prose:
# a floor guessed from a count in a plan is exactly the unmeasured claim this
# whole change exists to remove. Zero slack is deliberate.
# ---------------------------------------------------------------------------

MIN_CASES=73
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CASES" >&2
  echo "=== test-all-capacity-signal: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

echo "=== test-all-capacity-signal: $pass_n passed, $fails failed ($cases assertions) ==="
# Reads the append-only record, never the counter. See fail() above.
[[ ! -s "$FAILLOG" ]] || exit 1
