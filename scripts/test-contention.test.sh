#!/usr/bin/env bash
# test-contention.test.sh — arms for scripts/lib/test-contention.sh (#6789).
#
# Phase 1 (instrumentation): headroom probes, sibling scan, named banners.
# The Phase 3 advisory-queue arms land with the lock itself.
# Phase 4 (#7424): the second view over the same scan — SIBLING_SUITE_DETECTED.
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
#
# argv[0], ppid and pgrp are OPTIONAL trailing parameters (defaults `bash`, 0, 0 —
# byte-identical to the pre-Phase-4 fixture for every 5-argument caller). Phase 4
# needs all three: argv[0] because a suite is routinely exec'd directly
# (`./scripts/foo.test.sh`), and ppid/pgrp because sibling-run children are
# cancelled by ANCESTRY and process group, never by cwd — a fixture that leaves
# both pinned at 0 cannot express a parent/child relationship at all, so every
# cancellation arm would be testing an unreachable branch.
#
# An EMPTY cwd argument deliberately omits the `cwd` symlink, which is how the
# real `<unreadable>` case is reproduced (readlink fails, the lib substitutes the
# literal). Do not "fix" it by pointing the link somewhere: the whole point of
# T11c is that two processes sharing the `<unreadable>` pseudo-path must not
# cancel each other.
CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"
make_fake_proc() {
  local root="$1" pid="$2" cwd="$3" elapsed_s="$4" cmd="$5"
  local argv0="${6:-bash}" ppid="${7:-0}" pgrp="${8:-0}"
  local uptime=100000
  local starttime=$(( (uptime - elapsed_s) * CLK_TCK ))
  mkdir -p "$root/$pid"
  printf '%s 0.00\n' "$uptime" > "$root/uptime"
  # NUL-separated argv, exactly as the kernel presents it.
  printf '%s\0%s\0' "$argv0" "$cmd" > "$root/$pid/cmdline"
  # 19 filler fields (state .. itrealvalue), so starttime lands at field 20.
  # Overall field 4 = ppid and field 5 = pgrp, i.e. filler fields 2 and 3.
  local filler="S $ppid $pgrp" i
  for (( i = 4; i <= 19; i++ )); do filler+=" 0"; done
  printf '%s (te) st) %s %s 0 0\n' "$pid" "$filler" "$starttime" > "$root/$pid/stat"
  [[ -n "$cwd" ]] && ln -sfn "$cwd" "$root/$pid/cwd"
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

echo "=== Phase 4: sibling SUITE probe (SIBLING_SUITE_DETECTED) ==="

# A directly-run suite in another worktree competes for the same tmpfs capacity
# as this runner, but it is NOT a test-all.sh run, so SIBLING_RUN_DETECTED never
# sees it. These arms cover the second view over the SAME single /proc walk.
#
# Every fixture below pins ppid AND pgrp explicitly. A fixture that leaves them
# at 0 cannot distinguish "cancelled by ancestry" from "cancelled by accident",
# because a shared pgrp of 0 would cross-cancel every synthetic process.

suite_view() {  # $1 = proc root
  tc_env env TC_PROC_ROOT="$1" bash -c "source '$LIB'; tc_suite_siblings" 2>&1 || true
}
run_view() {    # $1 = proc root
  tc_env env TC_PROC_ROOT="$1" bash -c "source '$LIB'; tc_siblings" 2>&1 || true
}
preamble_of() { # $1 = proc root, $2 = destination file
  tc_env env TC_PROC_ROOT="$1" TC_MIN_AVAIL_MB=0 \
    bash -c "source '$LIB'; tc_preamble" > "$2" 2>&1 || true
}

# --- T9: a directly-run suite in another worktree IS reported ---------------
SUITE_PROC="$TESTROOT/proc-suite"
SUITE_WT="$TESTROOT/suite-wt"
mkdir -p "$SUITE_WT"
make_fake_proc "$SUITE_PROC" 811001 "$SUITE_WT" 45 "tests/scripts/test-foo.sh" bash 1 811001
out="$(suite_view "$SUITE_PROC")"
if [[ "$(grep -cE "^811001	${SUITE_WT}	4[45]\$" <<<"$out" || true)" -ge 1 ]]; then
  pass "T9: tc_suite_siblings emits pid, worktree and derived elapsed for a run suite"
else
  fail "T9: tc_suite_siblings line shape wrong; got: $out"
fi
# The RUN view must stay blind to it — the two banners answer different questions.
out="$(run_view "$SUITE_PROC")"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "T9: the run view does not see a directly-run suite (views are disjoint)"
else
  fail "T9: tc_siblings matched an individual suite; got: $out"
fi
preamble_of "$SUITE_PROC" "$TESTROOT/pre-suite.txt"
PS9="$TESTROOT/pre-suite.txt"
if [[ "$(grep -cE '^\[contention\] suite siblings: 1 ' "$PS9" || true)" -ge 1 ]]; then
  pass "T9: preamble reports 'suite siblings: 1'"
else
  fail "T9: no suite-siblings count line; got: $(cat "$PS9")"
fi
if [[ "$(grep -cE 'BANNER SIBLING_SUITE_DETECTED: an individual test suite is running in 1 other worktree' "$PS9" || true)" -ge 1 ]]; then
  pass "T9: SIBLING_SUITE_DETECTED fires and names the count"
else
  fail "T9: no SIBLING_SUITE_DETECTED banner; got: $(cat "$PS9")"
fi
if [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$PS9" || true)" -eq 0 ]]; then
  pass "T9: SIBLING_RUN_DETECTED does NOT fire for an individual suite"
else
  fail "T9: the run banner fired for a suite-only fixture; got: $(cat "$PS9")"
fi
# The banner must carry the three-way confirmation instruction, not just a name.
if [[ "$(grep -cE 'isolated re-run, the matching CI gate, and a clean full re-run' "$PS9" || true)" -ge 1 ]]; then
  pass "T9: the suite banner states the three-way confirmation protocol"
else
  fail "T9: suite banner lacks the confirmation protocol; got: $(cat "$PS9")"
fi

# --- T9b: argv[0] IS the suite (direct shebang exec) ------------------------
EXEC_PROC="$TESTROOT/proc-suite-exec"
mkdir -p "$TESTROOT/suite-wt-b"
make_fake_proc "$EXEC_PROC" 812001 "$TESTROOT/suite-wt-b" 12 "--verbose" \
  "./scripts/foo.test.sh" 1 812001
out="$(suite_view "$EXEC_PROC")"
if [[ "$(grep -cE '^812001	' <<<"$out" || true)" -ge 1 ]]; then
  pass "T9b: './scripts/foo.test.sh' as argv[0] is a suite sibling (*.test.sh rule)"
else
  fail "T9b: direct-exec *.test.sh not matched; got: $out"
fi

# --- T10: the RUNNER itself is not an individual suite ----------------------
# `test-all.sh` matches `test-*.sh`, so without the explicit exclusion EVERY full
# run would also count as a suite sibling and the banner would fire on every solo
# run — the "a banner that always fires carries no information" failure mode.
out="$(suite_view "$FAKE_PROC")"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "T10: 'bash scripts/test-all.sh' is NOT counted as an individual suite"
else
  fail "T10: the runner matched the suite predicate; got: $out"
fi
if [[ "$(grep -cE '^\[contention\] suite siblings: 0 ' "$P" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_SUITE_DETECTED' "$P" || true)" -eq 0 ]]; then
  pass "T10: the run-only preamble reports 0 suite siblings and no suite banner"
else
  fail "T10: suite banner/count wrong on a run-only fixture; got: $(cat "$P")"
fi
# T10 at the PREDICATE level. MEASURED: the two arms above cannot see the
# `test-all.sh` exclusion at all, because _tc_scan_procs tests the RUN predicate
# first and every input that would newly match as a suite already classified as
# a run — a mutant deleting the exclusion survives both. The exclusion is the
# second line of defence, and pinning it here is what stops a future reordering
# of that if/elif from turning every full run into a "suite sibling".
out="$(tc_env bash -c "source '$LIB'; _tc_is_suite_basename scripts/test-all.sh && echo MATCH || echo NO" 2>&1 || true)"
if [[ "$out" == "NO" ]]; then
  pass "T10: the suite predicate itself excludes test-all.sh (banner cannot self-fire)"
else
  fail "T10: _tc_is_suite_basename matched the runner; got: $out"
fi
# POSITIVE CONTROL: the same probe MUST match a real suite name, or the arm
# above reads "excluded" for a predicate that matches nothing at all.
out="$(tc_env bash -c "source '$LIB'; _tc_is_suite_basename tests/scripts/test-foo.sh && echo MATCH || echo NO" 2>&1 || true)"
if [[ "$out" == "MATCH" ]]; then
  pass "T10 control: the same predicate DOES match a real test-*.sh suite"
else
  fail "T10 control: the suite predicate matches nothing — the arm above is vacuous; got: $out"
fi

# --- T12: a whitespace-bearing `bash -c` string is not an invocation --------
WS_PROC="$TESTROOT/proc-suite-ws"
mkdir -p "$TESTROOT/ws-wt"
make_fake_proc "$WS_PROC" 813001 "$TESTROOT/ws-wt" 8 "x" bash 1 813001
printf 'bash\0-c\0grep -rn x tests/scripts/test-foo.sh\0' > "$WS_PROC/813001/cmdline"
out="$(suite_view "$WS_PROC")"
if [[ -z "${out//[[:space:]]/}" ]]; then
  pass "T12: a whitespace-bearing 'bash -c' string is not a suite sibling"
else
  fail "T12: the whitespace guard let a command STRING match; got: $out"
fi
# MUTATION CONTROL for T12: the same pid with a real token still matches, so the
# arm above cannot pass by matching nothing at all.
printf 'bash\0tests/scripts/test-foo.sh\0' > "$WS_PROC/813001/cmdline"
out="$(suite_view "$WS_PROC")"
if [[ "$(grep -cE '^813001	' <<<"$out" || true)" -ge 1 ]]; then
  pass "T12 control: a real 'bash tests/scripts/test-foo.sh' still matches"
else
  fail "T12 control: the whitespace guard rejected a real invocation; got: $out"
fi

# --- T11: a runner and ITS OWN suite child count once -----------------------
# The child deliberately sits in a DIFFERENT cwd (suites `cd` into a mktemp
# sandbox), which is exactly why cancellation is by ancestry and not by a cwd
# set-difference: the difference would fail to cancel and double-report.
#
# The child also carries a DIFFERENT pgrp from the runner. That is not cosmetic:
# with a shared pgrp the pgid fallback cancels it and this arm survives a mutant
# that deletes ancestry cancellation entirely (measured — the mutation battery
# caught exactly that). Distinct pgrps make ancestry the ONLY mechanism that can
# cancel here, and T11-pgid below is the arm that covers the fallback.
T11_PROC="$TESTROOT/proc-t11"
mkdir -p "$TESTROOT/t11-wt" "$TESTROOT/t11-sandbox"
make_fake_proc "$T11_PROC" 814001 "$TESTROOT/t11-wt" 300 "scripts/test-all.sh" bash 1 814001
make_fake_proc "$T11_PROC" 814002 "$TESTROOT/t11-sandbox" 20 "tests/scripts/test-foo.sh" \
  bash 814001 814002
preamble_of "$T11_PROC" "$TESTROOT/pre-t11.txt"
if [[ "$(grep -cE '^\[contention\] suite siblings: 0 ' "$TESTROOT/pre-t11.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_SUITE_DETECTED' "$TESTROOT/pre-t11.txt" || true)" -eq 0 ]]; then
  pass "T11: a runner's own suite child is cancelled by ancestry (counted once)"
else
  fail "T11: the suite child was double-reported; got: $(cat "$TESTROOT/pre-t11.txt")"
fi
if [[ "$(grep -cE '^\[contention\] siblings: 1 ' "$TESTROOT/pre-t11.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$TESTROOT/pre-t11.txt" || true)" -ge 1 ]]; then
  pass "T11: the run banner still fires exactly once for that worktree"
else
  fail "T11: run banner/count wrong; got: $(cat "$TESTROOT/pre-t11.txt")"
fi

# --- T11b: ancestry reaches THROUGH a non-matching wrapper ------------------
# `timeout N bash <suite>` puts a non-shell at argv[0], so the wrapper matches
# NEITHER predicate, and `timeout` calls setpgid() so the suite does not even
# share the runner's process group. Only a walk of the WHOLE ppid chain cancels
# it; a parent-only check reports the runner's own child as a sibling worktree.
#
# MEASURED CORRECTION to the plan's §4.3 third bullet: `env VAR=x bash <suite>`
# does NOT survive in argv — env EXECs, so /proc/<pid>/cmdline reads `bash
# <suite>` for all but the first microseconds and the run predicate does match.
# `timeout` FORKS and stays resident, so it is the shape that genuinely hides a
# run behind a non-shell argv[0]. Verified 2026-08-11 on this host.
T11B_PROC="$TESTROOT/proc-t11b"
mkdir -p "$TESTROOT/t11b-wt" "$TESTROOT/t11b-sandbox"
make_fake_proc "$T11B_PROC" 815001 "$TESTROOT/t11b-wt" 400 "scripts/test-all.sh" bash 1 815001
make_fake_proc "$T11B_PROC" 815002 "$TESTROOT/t11b-wt" 30 "x" timeout 815001 815002
printf 'timeout\0600\0bash\0tests/scripts/test-foo.sh\0' > "$T11B_PROC/815002/cmdline"
make_fake_proc "$T11B_PROC" 815003 "$TESTROOT/t11b-sandbox" 29 "tests/scripts/test-foo.sh" \
  bash 815002 815002
preamble_of "$T11B_PROC" "$TESTROOT/pre-t11b.txt"
if [[ "$(grep -cE '^\[contention\] suite siblings: 0 ' "$TESTROOT/pre-t11b.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_SUITE_DETECTED' "$TESTROOT/pre-t11b.txt" || true)" -eq 0 ]]; then
  pass "T11b: ancestry walks past a wrapper with a non-shell argv[0] (counted once)"
else
  fail "T11b: wrapper-hidden run's suite child was reported; got: $(cat "$TESTROOT/pre-t11b.txt")"
fi
if [[ "$(grep -cE '^\[contention\] siblings: 1 ' "$TESTROOT/pre-t11b.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$TESTROOT/pre-t11b.txt" || true)" -ge 1 ]]; then
  pass "T11b: the run banner fires once for the wrapped run"
else
  fail "T11b: run banner/count wrong under a wrapper; got: $(cat "$TESTROOT/pre-t11b.txt")"
fi

# --- T11-pgid: the process-group fallback when the ppid chain is broken -----
# A `run_suite` child inherits the runner's pgid; if it is reparented (its parent
# already reaped) the ppid chain no longer reaches the runner at all. Without the
# pgrp fallback the runner's own child reads as a foreign worktree.
T11P_PROC="$TESTROOT/proc-t11p"
mkdir -p "$TESTROOT/t11p-wt" "$TESTROOT/t11p-sandbox"
make_fake_proc "$T11P_PROC" 816001 "$TESTROOT/t11p-wt" 500 "scripts/test-all.sh" bash 1 816001
make_fake_proc "$T11P_PROC" 816002 "$TESTROOT/t11p-sandbox" 15 "tests/scripts/test-foo.sh" \
  bash 1 816001
preamble_of "$T11P_PROC" "$TESTROOT/pre-t11p.txt"
if [[ "$(grep -cE '^\[contention\] suite siblings: 0 ' "$TESTROOT/pre-t11p.txt" || true)" -ge 1 ]]; then
  pass "T11-pgid: a reparented suite child sharing the runner's pgrp is cancelled"
else
  fail "T11-pgid: pgrp fallback did not cancel; got: $(cat "$TESTROOT/pre-t11p.txt")"
fi

# --- T11c: '<unreadable>' cwds must NOT cross-cancel ------------------------
# tc_siblings substitutes one literal `<unreadable>` for every cwd it cannot
# read, so a cwd set-difference would let a SINGLE unreadable run subtract EVERY
# unreadable suite. Neither process here is related to the other.
T11C_PROC="$TESTROOT/proc-t11c"
make_fake_proc "$T11C_PROC" 817001 "" 600 "scripts/test-all.sh" bash 1 817001
make_fake_proc "$T11C_PROC" 817002 "" 60 "tests/scripts/test-foo.sh" bash 1 817002
preamble_of "$T11C_PROC" "$TESTROOT/pre-t11c.txt"
if [[ "$(grep -cE '^\[contention\] siblings: 1 ' "$TESTROOT/pre-t11c.txt" || true)" -ge 1 ]]; then
  pass "T11c: the unreadable-cwd run is still reported"
else
  fail "T11c: unreadable-cwd run lost; got: $(cat "$TESTROOT/pre-t11c.txt")"
fi
if [[ "$(grep -cE '^\[contention\] suite siblings: 1 ' "$TESTROOT/pre-t11c.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_SUITE_DETECTED' "$TESTROOT/pre-t11c.txt" || true)" -ge 1 ]]; then
  pass "T11c: an unrelated unreadable-cwd suite is NOT cancelled by the run"
else
  fail "T11c: '<unreadable>' cwds cross-cancelled; got: $(cat "$TESTROOT/pre-t11c.txt")"
fi

# --- T11d: over-cancellation control (AC24) ---------------------------------
# Without this arm an implementation that drops EVERY suite match whenever ANY
# run match exists passes T10, T11, T11b and T11-pgid.
T11D_PROC="$TESTROOT/proc-t11d"
mkdir -p "$TESTROOT/t11d-wt-a" "$TESTROOT/t11d-wt-b"
make_fake_proc "$T11D_PROC" 818001 "$TESTROOT/t11d-wt-a" 700 "scripts/test-all.sh" bash 1 818001
make_fake_proc "$T11D_PROC" 818002 "$TESTROOT/t11d-wt-b" 70 "tests/scripts/test-foo.sh" \
  bash 1 818002
preamble_of "$T11D_PROC" "$TESTROOT/pre-t11d.txt"
if [[ "$(grep -cE '^\[contention\] suite siblings: 1 ' "$TESTROOT/pre-t11d.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_SUITE_DETECTED' "$TESTROOT/pre-t11d.txt" || true)" -ge 1 ]]; then
  pass "T11d: an UNRELATED suite in another worktree survives an unrelated run (AC24)"
else
  fail "T11d: over-cancellation dropped an unrelated suite; got: $(cat "$TESTROOT/pre-t11d.txt")"
fi
if [[ "$(grep -cE '^\[contention\] siblings: 1 ' "$TESTROOT/pre-t11d.txt" || true)" -ge 1 ]] \
   && [[ "$(grep -cE 'SIBLING_RUN_DETECTED' "$TESTROOT/pre-t11d.txt" || true)" -ge 1 ]]; then
  pass "T11d: both banners fire independently when both kinds of sibling exist"
else
  fail "T11d: run banner missing alongside the suite banner; got: $(cat "$TESTROOT/pre-t11d.txt")"
fi

# --- T13: no siblings of EITHER kind => neither banner ----------------------
preamble_of "$OTHER_PROC" "$TESTROOT/pre-t13.txt"
if [[ "$(grep -cE 'SIBLING_RUN_DETECTED|SIBLING_SUITE_DETECTED|LOW_TMP_HEADROOM' "$TESTROOT/pre-t13.txt" || true)" -eq 0 ]]; then
  pass "T13: with no sibling of either kind, NEITHER sibling banner fires"
else
  fail "T13: a banner fired with no siblings; got: $(cat "$TESTROOT/pre-t13.txt")"
fi

# --- Back-compat: tc_siblings' output shape is unchanged (AC5) --------------
# The enumerator now emits a leading class column; the run view must strip it, or
# every one of the 22 zero-arg call sites silently shifts a field.
out="$(run_view "$FAKE_PROC")"
nf="$(awk -F'\t' 'NF != 3 {n++} END {print n+0}' <<<"$out" || true)"
if [[ "$nf" == "0" ]] && [[ "$(grep -cE '^424242	' <<<"$out" || true)" -ge 1 ]]; then
  pass "AC5: tc_siblings still emits exactly pid<TAB>cwd<TAB>elapsed (no class column)"
else
  fail "AC5: tc_siblings output shape changed ($nf malformed lines); got: $out"
fi

# --- Structural: ONE /proc walk per preamble --------------------------------
# Two calls are two NON-ATOMIC snapshots, over which the cross-bucket
# cancellation is computed on inconsistent sets. Anchored on the CALL construct
# over comment-stripped code, never on a bare token the file also names in prose.
pre_body="$(awk '/^tc_preamble\(\) \{/,/^\}/' "$LIB" | grep -vE '^[[:space:]]*#' || true)"
pre_lines="$(grep -c . <<<"$pre_body" || true)"
scan_calls="$(grep -oE '_tc_scan_procs' <<<"$pre_body" | wc -l || true)"
view_calls="$(grep -oE '(^|[^_[:alnum:]])tc_(suite_)?siblings' <<<"$pre_body" | wc -l || true)"
if [[ "$pre_lines" -ge 20 ]]; then
  pass "structural probe is non-vacuous: tc_preamble body extracted ($pre_lines lines)"
else
  fail "tc_preamble body extraction returned $pre_lines lines — the arm below is vacuous"
fi
if [[ "$scan_calls" == "1" ]] && [[ "$view_calls" == "0" ]]; then
  pass "tc_preamble derives both counts from ONE _tc_scan_procs snapshot"
else
  fail "tc_preamble walks /proc more than once ($scan_calls scan, $view_calls view calls)"
fi

# --- Per-mount used-bytes attribution (ADR-133 amendment instrument) -------
# WHY BYTES. The shipped per-suite probe records `tmp_delta=<ENTRY COUNT>`, but
# ADR-133's capacity verdict is about BYTES — that ADR explicitly rejected
# count-based reasoning because 4,294 small entries held 160 MB (4.5%) while
# three trees held 3.1 GiB (88%). So the quantity the advisory lock exists to
# protect had never been measured by the instrument shipped to measure it.
#
# WHY `df` AND NOT `du`. ADR-133's question is about a MOUNT's capacity ("a
# machine-global RAM-backed 4 GiB /tmp at 86% full"), not a directory's size, and
# `df` answers it in O(1). A `du` walk was measured on this machine at 2.15 s for
# /tmp and >115 s for /var/tmp — at the per-suite hook that is ~578 walks per
# mount, which is the same observer-effect confound that got a background
# sampler rejected during planning.
#
# WHY PER-MOUNT. test-all.sh points TMPDIR at /var/tmp (disk-backed) while
# pinning TC_TMPDIR at /tmp (the tmpfs), so a probe returning one number for
# "scratch" would re-create the fail-open the comment at test-all.sh:18-29 was
# written to prevent: a healthy reading from the wrong mount is
# indistinguishable from a healthy mount.
#
# THE MUTATION CONTROL IS THE PINNED PAIR. The stub keys its output on the PATH
# argument, so an implementation that ignored its argument, or summed the two
# mounts, returns the SAME number twice — which the distinctness arm rejects —
# and neither pinned value equals their sum.
BYTES_DF_STUB="$TESTROOT/df-bytes-stub.sh"
cat > "$BYTES_DF_STUB" <<'DFEOF'
#!/usr/bin/env bash
# df -P -k shape (header + one data row), keyed on the LAST argument so the two
# mounts report different Used values. Field 3 is Used in 1024-blocks.
target="${*: -1}"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
case "$target" in
  *tmpfs-under-pressure*) printf 'tmpfs 4194304 3500000 694304 84%% /tmp\n' ;;
  *disk-roomy*)           printf '/dev/fake 999999999 4096 999995903 1%% /\n' ;;
  *)                      printf 'unparseable\n' ;;
esac
DFEOF
chmod +x "$BYTES_DF_STUB"
mkdir -p "$TESTROOT/tmpfs-under-pressure" "$TESTROOT/disk-roomy"

if bash -c "source '$LIB'; declare -F tc_used_bytes >/dev/null 2>&1"; then
  pass "tc_used_bytes is defined"
else
  fail "tc_used_bytes is not defined — the bytes instrument does not exist"
fi

bytes_of() {
  TC_DF_CMD="$BYTES_DF_STUB" TC_D="$1" \
    bash -c "source '$LIB'; tc_used_bytes \"\$TC_D\"" 2>/dev/null || echo ""
}
b_tmpfs=$(bytes_of "$TESTROOT/tmpfs-under-pressure")
b_disk=$(bytes_of "$TESTROOT/disk-roomy")

# 3500000 KiB * 1024 and 4096 KiB * 1024. Pinned exactly: a range would admit
# the sum (3588194304), which is the specific wrong answer being rejected.
if [[ "$b_tmpfs" == "3584000000" ]]; then
  pass "tc_used_bytes reports the tmpfs mount's used bytes exactly (3584000000)"
else
  fail "tmpfs mount reported '$b_tmpfs', expected 3584000000"
fi
if [[ "$b_disk" == "4194304" ]]; then
  pass "tc_used_bytes reports the disk mount's used bytes exactly (4194304)"
else
  fail "disk mount reported '$b_disk', expected 4194304"
fi
if [[ -n "$b_tmpfs" && "$b_tmpfs" != "$b_disk" ]]; then
  pass "per-mount attribution: the two mounts report DISTINCT byte counts"
else
  fail "both mounts reported '$b_tmpfs' — the helper ignores its argument or sums the mounts"
fi
if [[ "$b_tmpfs" != "3588194304" && "$b_disk" != "3588194304" ]]; then
  pass "neither mount reports the SUM of the two (3588194304)"
else
  fail "a mount reported the sum of both mounts"
fi

# Degrade, never abort: this runs inside the gate's run-boundary hook, so an
# exception on an unparseable df would take the whole run down mid-flight.
b_bad=$(bytes_of "$TESTROOT/some-other-path")
if [[ "$b_bad" == "0" ]]; then
  pass "an unparseable df reports 0 rather than failing the run"
else
  fail "an unparseable df returned '$b_bad' instead of 0"
fi

# --- T15: the SUITE view dedupes by WORKTREE, not by pid ---------------------
# The run view has carried this pair since #6789; the suite view shipped without
# it, and the gap is not theoretical: replacing `cut -f2 | sort -u | grep -c .`
# with a bare `grep -c .` (count pids, not worktrees) passed all 66 assertions,
# while the SAME mutation on the run view reds. The banner's own text says
# "running in N other worktree(s)", so a pid count makes it say something false.
T15_PROC="$TESTROOT/proc-t15"
mkdir -p "$TESTROOT/t15-wt"
# Two suite processes, ONE worktree -> must collapse to 1.
make_fake_proc "$T15_PROC" 707001 "$TESTROOT/t15-wt" 30 "tests/scripts/test-foo.sh"
make_fake_proc "$T15_PROC" 707002 "$TESTROOT/t15-wt" 40 "tests/scripts/test-bar.sh"
tc_env env TC_PROC_ROOT="$T15_PROC" TC_SELF_PID=999999 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/preamble-t15.txt" 2>&1 || true
if [[ "$(grep -cE '^\[contention\] suite siblings: 1 ' "$TESTROOT/preamble-t15.txt" || true)" -ge 1 ]]; then
  pass "T15: two suite procs in ONE worktree collapse to 'suite siblings: 1'"
else
  fail "T15: expected 'suite siblings: 1'; got: $(grep 'suite siblings' "$TESTROOT/preamble-t15.txt" || true)"
fi

# --- T15b: the suite count REACHES 2 for two distinct worktrees --------------
# Without a genuine N=2 case, a mutation capping the count at 1 survives, and the
# banner's plural has never been exercised.
T15B_PROC="$TESTROOT/proc-t15b"
mkdir -p "$TESTROOT/t15b-wt-a" "$TESTROOT/t15b-wt-b"
make_fake_proc "$T15B_PROC" 708001 "$TESTROOT/t15b-wt-a" 30 "tests/scripts/test-foo.sh"
make_fake_proc "$T15B_PROC" 708002 "$TESTROOT/t15b-wt-b" 40 "tests/scripts/test-bar.sh"
tc_env env TC_PROC_ROOT="$T15B_PROC" TC_SELF_PID=999999 \
  bash -c "source '$LIB'; tc_preamble" > "$TESTROOT/preamble-t15b.txt" 2>&1 || true
if [[ "$(grep -cE '^\[contention\] suite siblings: 2 ' "$TESTROOT/preamble-t15b.txt" || true)" -ge 1 ]]; then
  pass "T15b: suite count reaches 2 for two DISTINCT worktrees (not capped at 1)"
else
  fail "T15b: expected 'suite siblings: 2'; got: $(grep 'suite siblings' "$TESTROOT/preamble-t15b.txt" || true)"
fi

# V5: `df` FAILING is a different case from `df` succeeding with junk, and only the second was
# fixtured — BYTES_DF_STUB exits 0 on every arm including its `unparseable` one. So an
# implementation that dropped the `2>/dev/null` and the `|| kb=""` (`kb=$(... ) || return 1`)
# satisfied every existing assertion while propagating a non-zero return into test-all.sh's
# `set -euo pipefail` at a run-boundary hook — which is the "takes the whole run down mid-flight"
# outcome the helper's own comment says it exists to prevent.
BYTES_DF_FAIL_STUB="$TESTROOT/df-fail-stub.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BYTES_DF_FAIL_STUB"
chmod +x "$BYTES_DF_FAIL_STUB"
# tc_used_bytes emits a trailing newline, so the rc suffix lands on a second line; collapse it
# rather than comparing against a shape that depends on that newline.
# `set -o pipefail` IS THE POINT, and without it this arm is vacuous. The capture is a PIPELINE
# (`df | awk`), whose exit status is awk's — and awk exits 0 on empty input — so a failing df is
# invisible unless pipefail is set. test-all.sh runs `set -euo pipefail` and sources this lib into
# that context, so the production shell is the one where df's failure actually propagates.
# Measured: without pipefail here, replacing `|| kb=""` with `|| return 1` was an EQUIVALENT
# mutation and this arm passed over it.
b_failed=$(TC_DF_CMD="$BYTES_DF_FAIL_STUB" TC_D="$TESTROOT" \
  bash -c "set -o pipefail; source '$LIB'; tc_used_bytes \"\$TC_D\"; printf ' rc=%s' \"\$?\"" 2>/dev/null | tr -d '\n' || echo "ABORTED")
if [[ "$b_failed" == "0 rc=0" ]]; then
  pass "a FAILING df yields 0 and returns success (degrades, never aborts the run)"
else
  fail "a failing df produced '$b_failed' — expected '0 rc=0'"
fi

# V6: nothing asserted that the implementation passes `-P -k`, because the stub ignores its
# arguments entirely. Dropping `-P` lets a long device name wrap onto a second line, so `NR==2`
# becomes the device name alone and field 3 is empty -> silently 0 on the PRODUCTION path while
# every stubbed arm stays green. Dropping `-k` gives `df -h`'s `3.5G`, which fails the numeric
# guard -> also 0. This arm is the only one that runs the helper against the REAL df.
# Bounded, not pinned: the value is a measured quantity, so it asserts shape and non-zero only.
b_real=$(TC_D="$TESTROOT" bash -c "source '$LIB'; tc_used_bytes \"\$TC_D\"" 2>/dev/null || echo "")
if [[ "$b_real" =~ ^[0-9]+$ ]] && [[ "$b_real" -gt 0 ]]; then
  pass "against the REAL df, tc_used_bytes returns a positive integer ($b_real bytes)"
else
  fail "against the real df, tc_used_bytes returned '$b_real' — the -P -k contract is broken"
fi

# POSITIVE CONTROL. The guard below reports THROUGH fail(), so fail() is a single
# point of failure for this entire file: neutered to a no-op it takes the whole
# verdict with it. Measured before this control existed: `fail() { :; }` plus
# deleting the SIBLING_SUITE_DETECTED banner from the lib reported
# "62 passed, 0 failed", exit 0 -- the flagship feature gone, four assertions
# silently vanished, and the cardinality guard DETECTING the shortfall and unable
# to say so. A brace group with a redirect, never `$( )`: command substitution
# runs in a subshell and the increments would be discarded.
_pc_p=$pass_n; _pc_f=$fails
{ pass "positive-control probe"; fail "positive-control probe"; } >/dev/null 2>&1
if [[ "$pass_n" -eq $((_pc_p + 1)) && "$fails" -eq $((_pc_f + 1)) ]]; then
  pass_n="$_pc_p"; fails="$_pc_f"
  echo "  [control] pass() and fail() both move their counters"
else
  echo "  [FATAL] assertion helpers do not move their counters -- every verdict here is void." >&2
  exit 1
fi

# Count BOTH outcomes: a run with genuine failures has a lower pass_n, and testing
# pass_n alone reported "cardinality guard: only 64 ran (expected >= 66)" on a run
# whose real problem was two failures -- a strand message for a non-strand.
# Raised 68 -> 76 with the ADR-181 per-mount bytes arms (6 attribution + 2 contract). At 68 the floor had exactly the slack
# to swallow that whole block: deleting it left the suite green and silent, which is the defect
# this guard exists to prevent, applied to the feature that added it.
if [[ "$((pass_n + fails))" -lt 76 ]]; then
  fail "cardinality guard: only $((pass_n + fails)) assertions ran (expected >= 76)"
fi

echo "=== test-contention: $pass_n passed, $fails failed ==="
[[ "$fails" -eq 0 ]] || exit 1
