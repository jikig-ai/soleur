#!/usr/bin/env bash
# test-contention.test.sh — arms for scripts/lib/test-contention.sh (#6789).
#
# Phase 1 (instrumentation): headroom probes, sibling scan, named banners.
# The Phase 3 advisory-queue arms land with the lock itself.
#
# AUTHORING CONSTRAINTS (from work/SKILL.md, learned the hard way in #6588):
#   - Never `producer | grep -q` under `set -o pipefail`: an EARLY match makes
#     grep close the pipe, the producer takes SIGPIPE (141), and pipefail turns
#     a genuine MATCH into a non-zero pipeline — so every NEGATIVE assertion
#     fails OPEN. Grep a FILE, or use `grep -c` on a herestring.
#   - A deliberately-nonzero command inside `$(...)` aborts under `set -e`
#     before fail() can print — suffix `|| true` inside the substitution.
#   - Every arm carries a mutation control: an arm that passes against a gutted
#     implementation asserts nothing.
#   - Minimum-cardinality guard: a loop over an empty data source exits 0 with
#     ZERO coverage, which reads exactly like success.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): a fake procfs,
# fake worktree dirs, and nothing written outside TESTROOT.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/test-contention.sh"

pass_n=0
fails=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t test-contention.XXXXXXXX)"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB does not exist" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture: a synthetic procfs containing one "sibling" test-all.sh process.
#
# /proc/<pid>/stat layout: field 1 = pid, field 2 = comm (parenthesized),
# field 3 = state, ... field 22 = starttime. After stripping through the LAST
# ') ', starttime is field 20. The filler is built programmatically so the
# index cannot drift from a hand-counted literal — a miscount here would move
# starttime and silently turn the elapsed assertion into a constant check.
#
# comm is deliberately "(te) st)" — it contains BOTH a space and an INNER
# close-paren, so a parser that splits on whitespace, or strips through the
# FIRST ') ' rather than the last, mis-indexes and reddens. A comm with a space
# but no inner ')' does NOT discriminate first-vs-last and lets that mutation
# survive; the mutation battery caught exactly that gap in this fixture.
# ---------------------------------------------------------------------------
CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"
make_fake_proc() {
  local root="$1" pid="$2" cwd="$3" elapsed_s="$4" cmd="$5"
  local uptime=100000
  local starttime=$(( (uptime - elapsed_s) * CLK_TCK ))
  mkdir -p "$root/$pid"
  printf '%s 0.00\n' "$uptime" > "$root/uptime"
  # NUL-separated argv, exactly as the kernel presents it.
  printf 'bash\0%s\0' "$cmd" > "$root/$pid/cmdline"
  # 19 filler fields (state .. itrealvalue), so starttime lands at field 20.
  local filler="S" i
  for (( i = 2; i <= 19; i++ )); do filler+=" 0"; done
  printf '%s (te) st) %s %s 0 0\n' "$pid" "$filler" "$starttime" > "$root/$pid/stat"
  ln -sfn "$cwd" "$root/$pid/cwd"
  printf 'MemAvailable:    7000000 kB\n' > "$root/meminfo"
  printf '3.96 9.72 14.60 2/2934 572235\n' > "$root/loadavg"
}

SIB_WT="$TESTROOT/worktrees/feat-sibling-branch"
mkdir -p "$SIB_WT"
FAKE_PROC="$TESTROOT/proc"
make_fake_proc "$FAKE_PROC" 424242 "$SIB_WT" 620 "scripts/test-all.sh"

OTHER_PROC="$TESTROOT/proc-other"
mkdir -p "$TESTROOT/other-wt"
make_fake_proc "$OTHER_PROC" 313131 "$TESTROOT/other-wt" 30 "scripts/some-other-script.sh"

FAKE_TMP="$TESTROOT/tmp"
mkdir -p "$FAKE_TMP"
touch "$FAKE_TMP/a" "$FAKE_TMP/b" "$FAKE_TMP/c"

tc_env() {
  env TC_PROC_ROOT="$FAKE_PROC" \
      TC_TMPDIR="$FAKE_TMP" \
      TC_SELF_PID=999999 \
      TC_XDG_DIR="" \
      TC_NPROC=16 \
      "$@"
}

echo "=== Phase 1: instrumentation ==="

# --- Arm 1: entry count ----------------------------------------------------
out="$(tc_env bash -c "source '$LIB'; tc_tmp_entry_count" 2>&1 || true)"
if [[ "$out" == "3" ]]; then
  pass "tc_tmp_entry_count counts entries in TC_TMPDIR"
else
  fail "tc_tmp_entry_count expected 3, got: $out"
fi

# --- Arm 2: sibling scan ---------------------------------------------------
tc_env bash -c "source '$LIB'; tc_siblings" > "$TESTROOT/siblings.txt" 2>&1 || true
S="$TESTROOT/siblings.txt"
if [[ "$(grep -cE '^424242	' "$S" || true)" -ge 1 ]]; then
  pass "tc_siblings emits the sibling pid"
else
  fail "tc_siblings did not emit pid 424242; got: $(cat "$S")"
fi
if [[ "$(grep -cF -- "$SIB_WT" "$S" || true)" -ge 1 ]]; then
  pass "tc_siblings resolves the sibling worktree via /proc/<pid>/cwd"
else
  fail "tc_siblings did not resolve cwd $SIB_WT; got: $(cat "$S")"
fi
# Elapsed must be DERIVED from starttime+uptime, not a constant. 620s synthesized.
if [[ "$(grep -cE '	62[0-9]$' "$S" || true)" -ge 1 ]]; then
  pass "tc_siblings derives elapsed seconds from stat starttime + uptime"
else
  fail "tc_siblings elapsed not ~620s; got: $(cat "$S")"
fi

# --- Arm 3: self-exclusion (mutation control for arm 2) --------------------
# Same fixture, but the scanner is told the sibling IS itself. A scanner that
# ignores TC_SELF_PID passes arm 2 and fails here; that asymmetry is the point.
out="$(tc_env env TC_SELF_PID=424242 bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "tc_siblings excludes its own pid"
else
  fail "tc_siblings should have excluded self pid 424242; got: $out"
fi

# --- Arm 3b: ANCESTOR exclusion, not merely self-exclusion -----------------
# The runner is normally launched through a wrapper shell whose own cmdline
# contains "test-all.sh". Excluding only $$ reports the caller's OWN
# invocation as a concurrent sibling on every run. Observed live: a clean solo
# run reported 2 phantom siblings, both in its own ancestor chain.
#
# Fixture: pid 555001 (the wrapper) is the PARENT of pid 555002 (the script).
# Scanning as 555002 must yield ZERO siblings.
ANC_PROC="$TESTROOT/proc-anc"
mkdir -p "$TESTROOT/anc-wt"
make_fake_proc "$ANC_PROC" 555001 "$TESTROOT/anc-wt" 90 "scripts/test-all.sh"
make_fake_proc "$ANC_PROC" 555002 "$TESTROOT/anc-wt" 88 "scripts/test-all.sh"
# Re-stamp 555002's ppid to 555001 (field 4 overall => field 2 after comm).
anc_filler="S 555001"
for (( i = 4; i <= 19; i++ )); do anc_filler+=" 0"; done
printf '555002 (te) st) %s %s 0 0\n' "$anc_filler" "$(( (100000 - 88) * CLK_TCK ))" \
  > "$ANC_PROC/555002/stat"
out="$(tc_env env TC_PROC_ROOT="$ANC_PROC" TC_SELF_PID=555002 \
  bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "tc_siblings excludes the whole ancestor chain, not just its own pid"
else
  fail "tc_siblings reported its own wrapper as a sibling; got: $out"
fi
# MUTATION CONTROL: an unrelated pid in the same fixture IS still reported, so
# the arm above cannot pass by simply returning nothing.
out="$(tc_env env TC_PROC_ROOT="$ANC_PROC" TC_SELF_PID=999999 \
  bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ "$(grep -cE '^555001	' <<<"$out" || true)" -ge 1 ]]; then
  pass "tc_siblings still reports non-ancestor test-all.sh processes"
else
  fail "ancestor exclusion suppressed an unrelated sibling; got: $out"
fi

# --- Arm 3c: MENTIONING the runner is not RUNNING it -----------------------
# A substring match over the joined cmdline reports every process that merely
# names test-all.sh: `grep test-all`, an editor with the file open, or a
# `bash -c` whose command string contains it — including inside a comment.
# Observed live: a probe whose own trailing comment read "# scripts/test-all.sh"
# matched itself as a concurrent run. The matcher must anchor on an ARGV TOKEN
# whose basename is exactly test-all.sh.
MENTION_PROC="$TESTROOT/proc-mention"
mkdir -p "$TESTROOT/mention-wt"
make_fake_proc "$MENTION_PROC" 777001 "$TESTROOT/mention-wt" 10 "x"
# Single argv token that CONTAINS the name but is not a path to it.
printf 'bash\0-c\0cd /x && echo hi # scripts/test-all.sh\0' \
  > "$MENTION_PROC/777001/cmdline"
out="$(tc_env env TC_PROC_ROOT="$MENTION_PROC" bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "a process that only MENTIONS test-all.sh is not counted as a run"
else
  fail "substring match counted a mere mention as a sibling; got: $out"
fi
# A `grep test-all` process must not match either.
printf 'grep\0-rn\0test-all.sh\0scripts/\0' > "$MENTION_PROC/777001/cmdline"
out="$(tc_env env TC_PROC_ROOT="$MENTION_PROC" bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "a grep for test-all.sh is not counted as a run"
else
  fail "a grep argument was counted as a sibling; got: $out"
fi
# MUTATION CONTROL: a REAL invocation in the same fixture still matches, so the
# two arms above cannot pass by matching nothing at all.
printf 'bash\0scripts/test-all.sh\0scripts\0' > "$MENTION_PROC/777001/cmdline"
out="$(tc_env env TC_PROC_ROOT="$MENTION_PROC" bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ "$(grep -cE '^777001	' <<<"$out" || true)" -ge 1 ]]; then
  pass "a real 'bash scripts/test-all.sh' invocation still matches"
else
  fail "token anchoring rejected a real invocation; got: $out"
fi

# --- Arm 3d: same process-GROUP subshells are excluded, not just ancestors --
# The `&`-backgrounding + command-substitution subshells of THIS invocation
# share its pgid but are NOT ancestors of the preamble's $$, so they would be
# flagged as concurrent siblings without a pgid exclusion (observed: a
# "running 0s" self-phantom). A genuinely separate run has a different pgid.
# rest-field layout after the comm strip: 1=state 2=ppid 3=pgrp ... 20=starttime.
PG_PROC="$TESTROOT/proc-pg"
mkdir -p "$PG_PROC" "$TESTROOT/pg-wt"
printf '100000 0.00\n' > "$PG_PROC/uptime"
_pg_st="$(( (100000 - 5) * CLK_TCK ))"
mk_pg_proc() {  # pid, pgrp
  local pid="$1" pg="$2"
  local d="$PG_PROC/$pid"
  mkdir -p "$d"
  printf 'bash\0scripts/test-all.sh\0scripts\0' > "$d/cmdline"
  # filler fields 1..19: state, ppid=1, pgrp=$pg, then zeros to field 19.
  local f="S 1 $pg" i
  for (( i = 4; i <= 19; i++ )); do f+=" 0"; done
  printf '%s (x) %s %s 0 0\n' "$pid" "$f" "$_pg_st" > "$d/stat"
  ln -sfn "$TESTROOT/pg-wt" "$d/cwd"
}
mk_pg_proc 666002 42   # self
mk_pg_proc 666003 42   # same group, ppid=1 (NOT an ancestor) -> must be excluded
mk_pg_proc 666004 99   # different group -> must be reported
out="$(tc_env env TC_PROC_ROOT="$PG_PROC" TC_SELF_PID=666002 \
  bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ "$(grep -cE '^666003	' <<<"$out" || true)" -eq 0 ]]; then
  pass "a same-process-group non-ancestor subshell is excluded (self-fork phantom)"
else
  fail "a same-pgid subshell was flagged as a sibling; got: $out"
fi
if [[ "$(grep -cE '^666004	' <<<"$out" || true)" -ge 1 ]]; then
  pass "a DIFFERENT-process-group test-all.sh run is still reported (not over-excluded)"
else
  fail "pgid exclusion suppressed a genuinely separate run; got: $out"
fi

# --- Arm 4: a non-test-all.sh process is not a sibling ---------------------
out="$(tc_env env TC_PROC_ROOT="$OTHER_PROC" bash -c "source '$LIB'; tc_siblings" 2>&1 || true)"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "tc_siblings ignores processes that are not test-all.sh"
else
  fail "tc_siblings matched a non-test-all.sh process; got: $out"
fi

# --- Arm 5: preamble names avail, used%, siblings, load, cores (AC1) ------
tc_env bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/preamble.txt" 2>&1 || true
P="$TESTROOT/preamble.txt"
for token in 'avail' 'used' 'siblings' 'load' 'cores'; do
  if [[ "$(grep -cEi -- "$token" "$P" || true)" -ge 1 ]]; then
    pass "preamble names '$token'"
  else
    fail "preamble missing '$token'; got: $(cat "$P")"
  fi
done
# A percentage must actually be rendered, not merely labelled.
if [[ "$(grep -cE '[0-9]+% used' "$P" || true)" -ge 1 ]]; then
  pass "preamble renders a real used-percentage value"
else
  fail "preamble has no 'NN% used' value; got: $(cat "$P")"
fi

# --- Arm 6: preamble names the sibling's WORKTREE PATH and PID (AC2) -------
# AC2 is explicit that "a sibling is running" is insufficient.
if [[ "$(grep -cF -- "$SIB_WT" "$P" || true)" -ge 1 ]] \
   && [[ "$(grep -cE '424242' "$P" || true)" -ge 1 ]]; then
  pass "preamble names the sibling worktree path AND pid (AC2)"
else
  fail "preamble lacks sibling worktree path or pid; got: $(cat "$P")"
fi

# --- Arm 6b: the sibling COUNT is distinct worktrees, not raw pids ---------
# Two pids in ONE worktree are one logical run competing for the tmpfs; a raw
# pid count overstates the contention and makes the banner's number wrong.
tc_env env TC_PROC_ROOT="$ANC_PROC" TC_SELF_PID=999999 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/preamble-anc.txt" 2>&1 || true
if [[ "$(grep -cE 'siblings: 1 ' "$TESTROOT/preamble-anc.txt" || true)" -ge 1 ]]; then
  pass "sibling count counts distinct worktrees (2 pids in 1 worktree => 1)"
else
  fail "sibling count is not worktree-distinct; got: $(grep siblings "$TESTROOT/preamble-anc.txt" || true)"
fi

# --- Arm 6c: the count reaches 2 for TWO distinct worktrees -----------------
# Arm 6b samples the distinct-worktree dedup only at "collapses to 1"; without a
# genuine N=2 case, a mutation capping the count at 1 (`sort -u | head -1`)
# survives. Two test-all.sh runs in DIFFERENT worktrees must report siblings: 2.
TWO_PROC="$TESTROOT/proc-two"
mkdir -p "$TESTROOT/wt-a" "$TESTROOT/wt-b"
make_fake_proc "$TWO_PROC" 606001 "$TESTROOT/wt-a" 100 "scripts/test-all.sh"
make_fake_proc "$TWO_PROC" 606002 "$TESTROOT/wt-b" 200 "scripts/test-all.sh"
tc_env env TC_PROC_ROOT="$TWO_PROC" TC_SELF_PID=999999 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/preamble-two.txt" 2>&1 || true
if [[ "$(grep -cE 'siblings: 2 ' "$TESTROOT/preamble-two.txt" || true)" -ge 1 ]]; then
  pass "sibling count reaches 2 for two DISTINCT worktrees (dedup not capped at 1)"
else
  fail "sibling count did not reach 2; got: $(grep siblings "$TESTROOT/preamble-two.txt" || true)"
fi

# --- Arm 7: banners NAME WHICH condition fired (1.3) -----------------------
# Forced by raising the floor above available space, so the arm needs no df
# stub and holds on any host regardless of real /tmp occupancy.
tc_env env TC_MIN_AVAIL_MB=99999999 bash -c "source '$LIB'; tc_preamble" \
  > "$TESTROOT/banner-low.txt" 2>&1 || true
if [[ "$(grep -cE 'LOW_TMP_HEADROOM' "$TESTROOT/banner-low.txt" || true)" -ge 1 ]]; then
  pass "low-headroom banner names the LOW_TMP_HEADROOM condition"
else
  fail "no LOW_TMP_HEADROOM banner; got: $(cat "$TESTROOT/banner-low.txt")"
fi
if [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$P" || true)" -ge 1 ]]; then
  pass "sibling banner names the SIBLING_RUN_DETECTED condition"
else
  fail "no SIBLING_RUN_DETECTED banner; got: $(cat "$P")"
fi
# MUTATION CONTROL: with no sibling and ample headroom, NEITHER banner fires.
# Without this, a lib that unconditionally prints both banners passes above.
tc_env env TC_PROC_ROOT="$OTHER_PROC" TC_MIN_AVAIL_MB=0 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/banner-none.txt" 2>&1 || true
if [[ "$(grep -cE 'LOW_TMP_HEADROOM|SIBLING_RUN_DETECTED' "$TESTROOT/banner-none.txt" || true)" -eq 0 ]]; then
  pass "no banner fires when headroom is ample and no sibling runs"
else
  fail "a banner fired unconditionally; got: $(cat "$TESTROOT/banner-none.txt")"
fi

# --- Arm 7b: LOW_TMP_HEADROOM is pinned to HEADROOM, not to the sibling ------
# Arm 7 forces low headroom with a huge floor, but that fixture ALSO has a
# sibling — so a mutation that fires LOW_TMP_HEADROOM on `sib_count > 0`
# (decoupled from headroom entirely) passes it. These arms de-correlate the two
# conditions with a df SEAM that pins a KNOWN avail/used, so the headroom
# banner's own condition is what is tested.
DF_STUB="$TESTROOT/df-stub.sh"
cat > "$DF_STUB" <<'DFEOF'
#!/usr/bin/env bash
# Emit a df -P -k shape: header + one data row. TC_DF_AVAIL_KB / TC_DF_USED_PCT
# pin the values the lib parses (field 4 = avail KB, field 5 = used%).
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
printf 'tmpfs 4194304 3500000 %s %s%% /tmp\n' "${TC_DF_AVAIL_KB:-3000000}" "${TC_DF_USED_PCT:-16}"
DFEOF
chmod +x "$DF_STUB"

# Low headroom (100 MB avail = 102400 KB, below the default 1024 MB floor) AND
# NO sibling → LOW_TMP_HEADROOM MUST fire, SIBLING_RUN_DETECTED must NOT.
tc_env env TC_PROC_ROOT="$OTHER_PROC" TC_DF_CMD="$DF_STUB" \
  TC_DF_AVAIL_KB=102400 TC_DF_USED_PCT=97 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/df-low.txt" 2>&1 || true
if [[ "$(grep -cE 'LOW_TMP_HEADROOM' "$TESTROOT/df-low.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$TESTROOT/df-low.txt" || true)" -eq 0 ]]; then
  pass "LOW_TMP_HEADROOM fires on low headroom with NO sibling (pinned df)"
else
  fail "headroom banner not isolated from sibling; got: $(cat "$TESTROOT/df-low.txt")"
fi
# The pinned avail/used values must actually render (tc_avail_mb / tc_used_pct
# are now on the LEFT of a call, not just 'some digit is present').
if [[ "$(grep -cE '100MB avail' "$TESTROOT/df-low.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE '97% used' "$TESTROOT/df-low.txt" || true)" -ge 1 ]]; then
  pass "preamble renders the pinned df avail (100MB) and used% (97%)"
else
  fail "pinned df values not rendered; got: $(grep contention "$TESTROOT/df-low.txt" | head -2)"
fi
# Ample headroom (3 GB avail) WITH a sibling → LOW must be ABSENT, SIBLING present.
# This is the arm that catches the `avail_mb < FLOOR` → `sib_count > 0` mutation.
tc_env env TC_DF_CMD="$DF_STUB" TC_DF_AVAIL_KB=3000000 TC_DF_USED_PCT=16 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/df-ample.txt" 2>&1 || true
if [[ "$(grep -cE 'LOW_TMP_HEADROOM' "$TESTROOT/df-ample.txt" || true)" -eq 0 ]] \
   && [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$TESTROOT/df-ample.txt" || true)" -ge 1 ]]; then
  pass "LOW_TMP_HEADROOM is ABSENT under ample headroom even WITH a sibling"
else
  fail "LOW fired under ample headroom (decoupled from its condition); got: $(cat "$TESTROOT/df-ample.txt")"
fi

# --- Arm 8: epilogue reports a real delta ----------------------------------
touch "$FAKE_TMP/d" "$FAKE_TMP/e"
tc_env bash -c "source '$LIB'; tc_epilogue 3" > "$TESTROOT/epilogue.txt" 2>&1 || true
if [[ "$(grep -cE 'delta 2' "$TESTROOT/epilogue.txt" || true)" -ge 1 ]]; then
  pass "tc_epilogue reports the +2 entry delta"
else
  fail "tc_epilogue did not report delta 2; got: $(cat "$TESTROOT/epilogue.txt")"
fi
# MUTATION CONTROL: an epilogue hardcoding "delta 2" would pass above.
tc_env bash -c "source '$LIB'; tc_epilogue 5" > "$TESTROOT/epilogue0.txt" 2>&1 || true
if [[ "$(grep -cE 'delta 0' "$TESTROOT/epilogue0.txt" || true)" -ge 1 ]]; then
  pass "tc_epilogue computes the delta rather than hardcoding it"
else
  fail "tc_epilogue delta is not computed; got: $(cat "$TESTROOT/epilogue0.txt")"
fi

# --- Arm 9: the module observes only — it must not mutate anything ---------
# The whole premise is that instrumentation ships ahead of every fix; a probe
# that creates or deletes files would destroy the conditions it exists to see.
before_n="$(find "$FAKE_TMP" -mindepth 1 -maxdepth 1 | wc -l)"
tc_env bash -c "source '$LIB'; tc_preamble; tc_epilogue 0" >/dev/null 2>&1 || true
after_n="$(find "$FAKE_TMP" -mindepth 1 -maxdepth 1 | wc -l)"
if [[ "$before_n" == "$after_n" ]]; then
  pass "the module creates and deletes nothing (observe-only)"
else
  fail "module mutated TC_TMPDIR: $before_n -> $after_n"
fi

echo "=== Phase 3: advisory queue ==="

SS_ROOT="$TESTROOT/session-state"
mkdir -p "$SS_ROOT/locks"
# All lock arms point at the REAL session-state.sh (the primitive under test is
# reused, not re-implemented) but anchor its state root into TESTROOT.
#
# `env -u CI` is LOAD-BEARING: GitHub Actions injects CI=true, and tc_acquire is
# CI-exempt (it skips the lock and emits LOCK_SKIPPED_CI). Without scrubbing CI
# here, every arm that expects the lock to ACTUALLY engage — the positive
# control, the advisory-timeout arm, and the "CI-skip does not fire when CI is
# unset" mutation control — takes the exempt path and fails, but ONLY under CI
# (green locally, red in CI: the vitest-unstub-can't-clear-inherited-env class
# from work/SKILL.md). The CI-exemption arm below re-sets CI=true explicitly.
lock_env() {
  env -u CI SOLEUR_SESSION_STATE_ROOT="$SS_ROOT" \
      TC_PROC_ROOT="$FAKE_PROC" TC_TMPDIR="$FAKE_TMP" TC_XDG_DIR="" \
      "$@"
}

# --- Arm 10: POSITIVE CONTROL — a free lock is acquirable -------------------
# Without this control, a broken probe reads as "blocked" and would justify
# building the stale-holder detection Phase 3.6 proves is dead code (the
# three-attempt trap in the plan's Sharp Edges).
out="$(lock_env bash -c "source '$LIB'; tc_acquire 6789-free 3; echo RC=\$?" 2>&1 || true)"
if [[ "$(grep -cE 'LOCK_ACQUIRED' <<<"$out" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'RC=0' <<<"$out" || true)" -ge 1 ]]; then
  pass "POSITIVE CONTROL: a free lock is acquired (probe is valid)"
else
  fail "positive control failed — later lock arms are meaningless: $out"
fi

# --- Arm 11: advisory timeout PROCEEDS, never aborts (AC4) ------------------
# A live holder is synthesized by a background shell holding the same flock.
HELD="$SS_ROOT/locks/6789-testall.lock"
: > "$HELD"
flock -x "$HELD" -c 'sleep 12' &
HOLDER=$!
sleep 1
lock_env bash -c "source '$LIB'; tc_acquire 6789-testall 2; echo RC=\$?" \
  > "$TESTROOT/timeout.txt" 2>&1 || true
if [[ "$(grep -cE 'RC=0' "$TESTROOT/timeout.txt" || true)" -ge 1 ]]; then
  pass "AC4: a lock held past the timeout still returns success (advisory)"
else
  fail "AC4: contended acquire did not return success; got: $(cat "$TESTROOT/timeout.txt")"
fi
if [[ "$(grep -cE 'LOCK_CONTENDED_PROCEEDING' "$TESTROOT/timeout.txt" || true)" -ge 1 ]]; then
  pass "AC4: the advisory banner names LOCK_CONTENDED_PROCEEDING"
else
  fail "AC4: no advisory banner; got: $(cat "$TESTROOT/timeout.txt")"
fi
kill "$HOLDER" 2>/dev/null || true
wait "$HOLDER" 2>/dev/null || true

# --- Arm 12: kill switch (AC3) ---------------------------------------------
out="$(lock_env env SOLEUR_DISABLE_SESSION_STATE=1 \
  bash -c "source '$LIB'; tc_acquire 6789-ks 2; echo RC=\$?" 2>&1 || true)"
if [[ "$(grep -cE 'RC=0' <<<"$out" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'LOCK_SKIPPED_DISABLED' <<<"$out" || true)" -ge 1 ]]; then
  pass "AC3: SOLEUR_DISABLE_SESSION_STATE=1 skips acquisition and says so"
else
  fail "AC3: kill switch not honoured; got: $out"
fi

# --- Arm 13: CI exemption (AC5) --------------------------------------------
out="$(lock_env env CI=true \
  bash -c "source '$LIB'; tc_acquire 6789-ci 2; echo RC=\$?" 2>&1 || true)"
if [[ "$(grep -cE 'RC=0' <<<"$out" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'LOCK_SKIPPED_CI' <<<"$out" || true)" -ge 1 ]]; then
  pass "AC5: CI set skips acquisition and says so"
else
  fail "AC5: CI exemption not honoured; got: $out"
fi
# MUTATION CONTROL: without CI, the CI-skip path must NOT fire — otherwise a lib
# that always skips passes arm 13 while locking nothing, ever.
out="$(lock_env bash -c "source '$LIB'; tc_acquire 6789-noci 2" 2>&1 || true)"
if [[ "$(grep -cE 'LOCK_SKIPPED_CI' <<<"$out" || true)" -eq 0 ]]; then
  pass "CI-skip does not fire when CI is unset"
else
  fail "CI-skip fired with CI unset; got: $out"
fi

# --- Arm 14: kernel releases the lock on SIGKILL (AC5b) --------------------
# Asserts the property Phase 3.6 relies on, so a future refactor to a
# hand-rolled PID-file scheme reddens HERE instead of silently reintroducing a
# hang. Includes a positive control (BLOCKED while alive) so a broken probe
# cannot pass as "released".
K="$SS_ROOT/locks/6789-kill.lock"
: > "$K"
# The holder must be the process we SIGKILL, with no surviving child holding
# the fd. `flock -c 'sleep 30'` runs sleep as flock's CHILD, which inherits the
# locked fd and outlives the kill — the exact confound the plan's Sharp Edges
# records as attempt 2. Instead open the fd in a shell, lock it, then `exec`
# sleep so sleep REPLACES the shell at the same pid and IS the sole fd holder.
bash -c 'exec 9>"'"$K"'"; flock -x 9; exec sleep 30' &
KPID=$!
sleep 1
blocked="$(flock -w 1 -x "$K" -c true 2>&1 && echo FREE || echo BLOCKED)"
kill -9 "$KPID" 2>/dev/null || true
wait "$KPID" 2>/dev/null || true
sleep 1
after="$(flock -w 2 -x "$K" -c true 2>&1 && echo FREE || echo BLOCKED)"
if [[ "$blocked" == "BLOCKED" && "$after" == "FREE" ]]; then
  pass "AC5b: flock is kernel-released after SIGKILL (no stale detection needed)"
else
  fail "AC5b: expected BLOCKED then FREE, got '$blocked' then '$after'"
fi

# --- Arm 15: no stale-holder detection code exists (Phase 3.6) -------------
# Anchored on the syntactic shapes a hand-rolled scheme needs, over CODE only
# (this suite's own prose names them). A match means dead code crept in.
lib_code="$(grep -vE '^[[:space:]]*#' "$LIB")"
if [[ "$(grep -cE 'kill -0|/proc/[^/]*holder|stale_pid|holder_pid' <<<"$lib_code" || true)" -eq 0 ]]; then
  pass "Phase 3.6: the lib contains no stale-holder detection path"
else
  fail "the lib appears to implement stale-holder detection (dead code per AC5b)"
fi
# POSITIVE CONTROL for the negative grep above: the SAME extraction+pattern must
# be able to MATCH when the shape IS present, or a typo'd regex reads "clean
# forever". Feed the extractor a line that contains one of the forbidden tokens.
_probe_code="$(printf 'if kill -0 "$stale_pid"; then :; fi\n')"
if [[ "$(grep -cE 'kill -0|/proc/[^/]*holder|stale_pid|holder_pid' <<<"$_probe_code" || true)" -ge 1 ]]; then
  pass "the stale-holder pattern is live (matches when the shape is present)"
else
  fail "the stale-holder detection regex matches nothing — the negative arm is vacuous"
fi

# --- Minimum-cardinality guard ---------------------------------------------
# A silently-empty run exits 0 with zero coverage, which reads exactly like
# success. This is the guard for that.
if [[ "$pass_n" -lt 40 ]]; then
  fail "cardinality guard: only $pass_n assertions ran (expected >= 40)"
fi

echo "=== test-contention: $pass_n passed, $fails failed ==="
[[ "$fails" -eq 0 ]] || exit 1
