#!/usr/bin/env bash
# orphan-process-reaper.test.sh — behavioural arms for scripts/orphan-process-reaper.sh (#7537).
#
# This suite exists because the reaper SIGNALS PROCESSES. Every gate it applies
# (own-uid, unlinked cwd, unlinked fd/255, self-exclusion, mount namespace, age)
# is asserted in BOTH directions: the process is flagged when it should be, and
# — carrying far more weight — is NOT flagged when any single gate says no. The
# plan states three times that no sensitivity evidence exists for this
# conjunction, so the negative arms are the ones protecting live work.
#
# FIXTURE REALISM (measured; the obvious fixture is silently wrong).
# The gates test `stat -Lc '%h'` on a /proc magic link. Measured on this box:
#
#   A  symlink -> a nonexistent path "(deleted)"   stat -Lc '%h' -> rc 1, NO value
#   B  symlink -> a live directory                 stat -Lc '%h' -> 2
#   C  symlink -> /proc/<pid>/fd/N held open on an unlinked file
#                                                  stat -Lc '%h' -> 0
#
# Case A is the fixture anyone writes first, and under the detector's own
# fail-toward-alive rule a failed stat counts as `unreadable` and the process is
# NOT flagged — so a suite built on dangling symlinks reports every positive arm
# as passing while the detector never classified anything. Anchor-positive arms
# therefore use case C (or a real process); negative/structural arms may use B.
# AC30b's control arm builds a case-A fixture and requires `unreadable`, so a
# refactor back to dangling symlinks reddens here instead of going green-vacuous.
#
# AUTHORING CONSTRAINTS (see work/SKILL.md):
#   - Never `producer | grep -q` under pipefail; grep a FILE or use a herestring.
#   - Deliberately-nonzero commands inside `$(...)` need `|| true` under set -e.
#   - `cases` is incremented at the CALL SITE; pass()/fail() never move it.
#   - Assertions on the report grammar are PREFIX-ANCHORED (`^signalled `),
#     because a directory may be named `x signalled pid=1 cwd=/y` (AC23).

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The system under test. The mutation battery points this at a mutant copy, so
# every row exercises this suite unmodified — a battery that only mutates the
# SUT cannot see a vacuous harness, which is what the H-rows exist for.
REAPER="${ORPHAN_SUITE_SUT:-$REPO_ROOT/scripts/orphan-process-reaper.sh}"

# The two REAL-PROCESS arms (live procfs, and the end-to-end incident trace)
# cost ~6 s of this suite's ~16 s, almost all of it the member scan forking one
# `stat` per pid on a ~600-pid box. The mutation battery runs this suite once
# per row, so it skips them and says so; the battery's UNMUTATED CONTROL runs
# the full suite including both. That split is safe only because no mutation
# row's witness is a live arm — every M-row reddens on a synthesized fixture —
# and it is stated here rather than inferred so a future row that DOES need a
# live witness is written knowing the battery would not see it.
SKIP_LIVE="${ORPHAN_SUITE_SKIP_LIVE:-0}"

pass_n=0
fails=0
cases=0
# `cases` is incremented at the CALL SITE — immediately before each decision
# block that resolves to exactly one verdict — and NEVER inside pass()/fail().
# That placement is the whole substance of the conservation check at the bottom:
# a counter moved inside both verdict helpers moves WITH the verdict, so stubbing
# `fail() { :; }` drops the row and its count together and `pass_n + fails ==
# cases` still holds. H1/H1b in the mutation battery pin both halves.
#
# Never increment inside `$( )` — a subshell discards it.
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t orphan-reaper.XXXXXXXX)"
HELPER_PIDS=()
cleanup() {
  local p
  for p in ${HELPER_PIDS[@]+"${HELPER_PIDS[@]}"}; do
    [[ "$p" =~ ^[1-9][0-9]*$ ]] || continue
    kill -KILL "$p" 2>/dev/null || true
  done
  rm -rf "$TESTROOT"
}
trap cleanup EXIT

if [[ ! -f "$REAPER" ]]; then
  echo "ERROR: $REAPER does not exist" >&2
  exit 1
fi

UID_NOW="$(id -u)"
CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"

# --- The unlinked-inode handles (case C) -----------------------------------
# One handle per distinct inode identity the fixtures need. Held open for the
# life of the suite, so `stat -L` through them reports nlink 0 the whole time.
UNLINKED_DIR="$TESTROOT/holder"
mkdir -p "$UNLINKED_DIR"

: > "$UNLINKED_DIR/a"
exec 7<>"$UNLINKED_DIR/a"
rm -f "$UNLINKED_DIR/a"
HANDLE_A="/proc/$$/fd/7"          # the canonical doomed cwd inode

: > "$UNLINKED_DIR/b"
exec 8<>"$UNLINKED_DIR/b"
rm -f "$UNLINKED_DIR/b"
HANDLE_B="/proc/$$/fd/8"          # a SECOND, distinct doomed inode

: > "$UNLINKED_DIR/s"
exec 9<>"$UNLINKED_DIR/s"
rm -f "$UNLINKED_DIR/s"
HANDLE_SCRIPT="/proc/$$/fd/9"     # the unlinked script behind fd/255

# Self-check: if these do not read as nlink 0, every positive arm below would
# pass for the wrong reason. Fail LOUDLY as a fixture error rather than
# reporting a phantom SUT regression.
_h="$(stat -Lc '%h' "$HANDLE_A" 2>/dev/null || echo MISSING)"
if [[ "$_h" != "0" ]]; then
  echo "FIXTURE ERROR: unlinked handle reports nlink=$_h, expected 0" >&2
  exit 2
fi

# The `' (deleted)'`-suffixed indirection for fd/255. readlink returns THIS
# path (absolute, suffixed); stat -L follows the chain to the unlinked inode.
DELSCRIPT="$TESTROOT/victim.sh (deleted)"
ln -sfn "$HANDLE_SCRIPT" "$DELSCRIPT"

# A live directory literally named `… (deleted)` — the measured spoof (AC5).
SPOOFDIR="$TESTROOT/work (deleted)"
mkdir -p "$SPOOFDIR"
SPOOFSCRIPT="$TESTROOT/spoof-victim.sh (deleted)"
: > "$SPOOFSCRIPT"

# --- Fixture builders ------------------------------------------------------

fp_new() {  # $1 = name -> echoes a fresh fake procfs root
  local r="$TESTROOT/proc-$1"
  rm -rf "$r"
  mkdir -p "$r"
  # Uptime far past any age floor the arms use, unless an arm overrides it.
  printf '%s 0.00\n' "1000000.00" > "$r/uptime"
  printf '%s' "$r"
}

# /proc/<pid>/stat, in the real layout. `_tc_stat_field` strips through `') '`,
# so after the strip field 1 is state, field 3 is pgrp and field 20 is
# starttime — the indices scripts/lib/test-contention.sh reads.
mk_stat() {  # root pid ppid pgrp starttime_ticks [comm]
  local root="$1" pid="$2" ppid="$3" pgrp="$4" st="$5" comm="${6:-bash}"
  mkdir -p "$root/$pid"
  printf '%s (%s) S %s %s 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s\n' \
    "$pid" "$comm" "$ppid" "$pgrp" "$st" > "$root/$pid/stat"
}

mk_ns() {  # root pid mnt_target pid_target
  local root="$1" pid="$2" mnt="$3" pidns="$4"
  mkdir -p "$root/$pid/ns"
  ln -sfn "$mnt" "$root/$pid/ns/mnt"
  ln -sfn "$pidns" "$root/$pid/ns/pid"
}

# The scanner's own namespace strings, so a fixture can match or differ.
NS_MNT_SELF="$(readlink /proc/self/ns/mnt 2>/dev/null || echo 'mnt:[4026531840]')"
NS_PID_SELF="$(readlink /proc/self/ns/pid 2>/dev/null || echo 'pid:[4026531836]')"

mk_cmdline() {  # root pid text
  local root="$1" pid="$2"
  mkdir -p "$root/$pid"
  printf '%s' "$3" > "$root/$pid/cmdline"
}

# A fully-formed ANCHOR: own uid, unlinked cwd, unlinked+suffixed+regular
# fd/255, same namespaces, aged past the floor.
mk_anchor() {  # root pid [cwd_handle] [starttime]
  local root="$1" pid="$2" cwd="${3:-$HANDLE_A}" st="${4:-100}"
  mkdir -p "$root/$pid/fd"
  mk_stat "$root" "$pid" 1 "$pid" "$st"
  mk_ns "$root" "$pid" "$NS_MNT_SELF" "$NS_PID_SELF"
  ln -sfn "$cwd" "$root/$pid/cwd"
  ln -sfn "$DELSCRIPT" "$root/$pid/fd/255"
  # LIVE stdout, as measured on the real orphan (fd1=/dev/null). This is what
  # makes an fd/1-veto mutation non-equivalent — and it is also the fixture the
  # cut stdout-veto would have refused, which is how that veto was falsified.
  ln -sfn /dev/null "$root/$pid/fd/1"
  mk_cmdline "$root" "$pid" "bash victim.sh"
}

# A set MEMBER: shares the anchor's cwd inode, no fd/255 of its own.
mk_member() {  # root pid [cwd_handle] [starttime] [comm]
  local root="$1" pid="$2" cwd="${3:-$HANDLE_A}" st="${4:-100}" comm="${5:-python3}"
  mkdir -p "$root/$pid/fd"
  mk_stat "$root" "$pid" 1 "$pid" "$st" "$comm"
  mk_ns "$root" "$pid" "$NS_MNT_SELF" "$NS_PID_SELF"
  ln -sfn "$cwd" "$root/$pid/cwd"
  mk_cmdline "$root" "$pid" "$comm worker"
}

# An unlinked DIRECTORY handle: nlink 0 and suffixed like a deleted script, but
# not a regular file. This is the witness for G3's regular-file term — without
# it that term is never the deciding gate and mutating it away is invisible.
mkdir -p "$UNLINKED_DIR/adir"
exec 6<"$UNLINKED_DIR/adir"
rmdir "$UNLINKED_DIR/adir"
HANDLE_DIR="/proc/$$/fd/6"
DELDIR="$TESTROOT/notascript.sh (deleted)"
ln -sfn "$HANDLE_DIR" "$DELDIR"

# --- Driving the reaper ----------------------------------------------------
# The suite pins ORPHAN_REAPER_SELF_PID to a pid that is NOT in any fixture, so
# self-exclusion has a defined answer. H4 in the battery pins that the borrowed
# TC_PROC_ROOT/TC_SELF_PID follow this seam rather than leaking the real /proc.
FIXTURE_SELF_PID=9999001

RR_OUT=""; RR_ERR=""; RR_RC=0
run_reaper() {  # root verb [KEY=VAL ...]
  local root="$1" verb="$2"; shift 2
  local outf errf
  outf="$(mktemp -p "$TESTROOT" out.XXXXXXXX)"
  errf="$(mktemp -p "$TESTROOT" err.XXXXXXXX)"
  RR_RC=0
  env -u CI ORPHAN_PROC_ROOT="$root" \
      ORPHAN_REAPER_SELF_PID="$FIXTURE_SELF_PID" \
      ORPHAN_REAPER_NO_FLOCK=1 \
      ORPHAN_REAPER_EVIDENCE_FILE="$TESTROOT/evidence.log" \
      "$@" \
      bash "$REAPER" "$verb" >"$outf" 2>"$errf" || RR_RC=$?
  RR_OUT="$(cat "$outf")"
  RR_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
}

# Field off the ORPHAN_SCAN counter line. Herestring, never a pipe into a
# short-circuiting reader (the pipefail/SIGPIPE class).
field() {  # name
  awk -v k="$1" '
    /^ORPHAN_SCAN /{
      for (i = 2; i <= NF; i++) { n = index($i, "=");
        if (n && substr($i, 1, n-1) == k) { print substr($i, n+1); exit } }
    }' <<<"$RR_OUT"
}

# Count of report lines whose FIRST field is exactly $1 (prefix-anchored, AC23).
lines_of() {  # prefix
  awk -v p="$1" '$1 == p { n++ } END { print n + 0 }' <<<"$RR_OUT"
}

expect_field() {  # name expected label
  local got; got="$(field "$1")"
  cases=$((cases + 1))
  if [[ "$got" == "$2" ]]; then pass "$3 ($1=$2)"
  else fail "$3 — expected $1=$2, got '${got:-<absent>}'"; fi
}

echo "=== orphan-process-reaper: behavioural arms ==="

# ===========================================================================
# Detection — positive (AC1, AC2)
# ===========================================================================
echo "--- detection: positive ---"

# AC1 — the orphan. cwd and executing script both unlinked after launch.
R="$(fp_new ac1)"
mk_anchor "$R" 4242
run_reaper "$R" report
expect_field valid  1 "AC1 walk is structurally valid"
expect_field anchors 1 "AC1 the orphan is an anchor"
cases=$((cases + 1))
if [[ "$(lines_of anchor)" == "1" ]]; then pass "AC1 one prefix-anchored 'anchor' line"
else fail "AC1 expected exactly one '^anchor ' line, got $(lines_of anchor)"; fi

# AC2 — the load, not the wrapper. The measured three-process shape: a bash
# wrapper with the unlinked fd/255, a second bash, and a non-bash child, all
# sharing ONE unlinked cwd inode. All three are in the reap set, and the
# non-bash child is signalled BEFORE the anchor. This is the arm that ties the
# change to the 62-CPU-minute incident: a run signalling only the anchor
# satisfies the issue's literal conjunction and still leaves the cores held.
R="$(fp_new ac2)"
mk_anchor "$R" 4242                       # the bash wrapper — the only fd/255
mk_member "$R" 4243 "$HANDLE_A" 100 bash  # second bash, no fd/255
mk_member "$R" 4244 "$HANDLE_A" 100 python3
run_reaper "$R" report
expect_field anchors     1 "AC2 exactly one anchor (fd/255 is bash-only)"
expect_field set_members 3 "AC2 the whole set, not just the wrapper"
cases=$((cases + 1))
if [[ "$(lines_of member)" -ge 2 ]]; then pass "AC2 members enumerated in the report"
else fail "AC2 expected >=2 '^member ' lines, got $(lines_of member)"; fi

# AC2 ordering — children before the anchor, so a supervising parent cannot
# respawn them. Asserted on the ORDER of the sink, not by reading the source.
SINK="$TESTROOT/sink-ac2"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0
cases=$((cases + 1))
_last="$(awk 'END{print $1}' "$SINK")"
if [[ "$_last" == "4242" ]]; then pass "AC2/M19 anchor is signalled LAST"
else fail "AC2/M19 anchor must be signalled after its children; sink order was: $(tr '\n' ' ' < "$SINK")"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^4244$' "$SINK" || true)" == "1" ]]; then pass "AC2 the non-bash child is signalled"
else fail "AC2 the CPU-holding child was never signalled — the R1a defect"; fi

# Accept-direction variants (the half a reject-only fixture set cannot see: a
# detector that flags NOTHING satisfies every negative arm).
R="$(fp_new acc-b)"
mk_anchor "$R" 4242
# anchor with ZERO set members
run_reaper "$R" report
expect_field anchors 1 "accept-direction: anchor with zero members still flags"

R="$(fp_new acc-c)"
mk_anchor "$R" 4242 "$HANDLE_B"   # a DIFFERENT unlinked inode
run_reaper "$R" report
expect_field anchors 1 "accept-direction: a different unlinked cwd inode flags"

# ===========================================================================
# Detection — negative (AC3-AC14)
# ===========================================================================
echo "--- detection: negative ---"

# AC3 — THE REAL FALSE POSITIVE. The scripts/tmpfs-guard.sh cron shape:
# deleted fd/1, LIVE cwd, LIVE fd/255. A reaper keyed on stdout kills the tmpfs
# guard on its next cron tick. The fixture reproduces the SHAPE; it does not
# name the pid observed at plan time, which is gone by merge.
R="$(fp_new ac3)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$TESTROOT" "$R/4242/cwd"                 # live cwd
ln -sfn "$SPOOFSCRIPT" "$R/4242/fd/255"           # live script
ln -sfn "$HANDLE_A" "$R/4242/fd/1"                # DELETED stdout
mk_cmdline "$R" 4242 "bash scripts/tmpfs-guard.sh"
run_reaper "$R" report
expect_field anchors     0 "AC3 tmpfs-guard cron shape is NOT flagged"
expect_field would_signal 0 "AC3 tmpfs-guard cron shape would not be signalled"

# AC4 — exe. Deleted exe (the claude self-update, ~11 live hits) with a live
# cwd must not flag, AND `exe` must appear nowhere in the classification path.
R="$(fp_new ac4)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$TESTROOT" "$R/4242/cwd"
ln -sfn "$HANDLE_A" "$R/4242/exe"                 # unlinked binary
run_reaper "$R" report
expect_field anchors 0 "AC4 deleted exe with live cwd is NOT flagged"

# Content anchor on the classifier's own span, not a repo-wide token grep:
# `exe` is never consulted, which is what keeps P2/P3 free by construction.
cases=$((cases + 1))
_clsbody="$(awk '/^_orphan_classify\(\)/{f=1} f{print} f&&/^}/{exit}' "$REAPER")"
if [[ -n "$_clsbody" ]] && ! grep -qE '/exe|\bexe\b' <<<"$_clsbody"; then
  pass "AC4 _orphan_classify never consults exe"
else
  fail "AC4 _orphan_classify references exe (or the function span was not found)"
fi

# AC5 — the measured spoof. A HEALTHY process whose cwd is a real directory
# literally named `… (deleted)` (st_nlink 2 vs 0), with a script whose name
# also carries the suffix. This is the fixture that makes M2 non-vacuous:
# flagging needs the conjunction, so BOTH links must carry the suffix.
R="$(fp_new ac5)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$SPOOFDIR" "$R/4242/cwd"
ln -sfn "$SPOOFSCRIPT" "$R/4242/fd/255"
run_reaper "$R" report
expect_field anchors 0 "AC5 a directory literally named '… (deleted)' is NOT flagged"

# AC6 — foreign mount namespace is unadjudicable. bwrap/rootless containers run
# own-uid with a namespace-private cwd as NORMAL operation, and their lifecycle
# belongs to their supervisor.
R="$(fp_new ac6)"
mk_anchor "$R" 4242
ln -sfn 'mnt:[4026599999]' "$R/4242/ns/mnt"
run_reaper "$R" report
expect_field anchors             0 "AC6 foreign mount namespace is NOT flagged"
expect_field skipped_foreign_ns  1 "AC6 the refusal is counted, not silent"

# AC7 — fail toward alive. Seven cases, each incrementing `cases` at the call
# site. Every one must leave the process unflagged, increment `unreadable`, and
# let the walk COMPLETE.
echo "--- AC7: fail toward alive (7 cases) ---"

# (a) unreadable /proc/<pid> — carries fd/255 so it survives the pre-filter and
#     actually reaches classification (the M12 witness).
R="$(fp_new ac7a)"
mk_anchor "$R" 4242
rm -f "$R/4242/cwd"
ln -sfn "/nonexistent-$$/gone (deleted)" "$R/4242/cwd"
run_reaper "$R" report
expect_field anchors 0 "AC7a unreadable cwd stat -> not flagged"
cases=$((cases + 1))
if [[ "$(field unreadable)" -ge 1 ]]; then pass "AC7a unreadable counted"
else fail "AC7a unreadable was not counted"; fi
cases=$((cases + 1))
if [[ "$RR_RC" == "0" ]]; then pass "AC7a the walk completes"
else fail "AC7a walk aborted (rc=$RR_RC) — errexit on an ordinary outcome"; fi

# (b) unreadable fd/255
R="$(fp_new ac7b)"
mk_anchor "$R" 4242
ln -sfn "/nonexistent-$$/script.sh (deleted)" "$R/4242/fd/255"
run_reaper "$R" report
expect_field anchors 0 "AC7b unreadable fd/255 -> not flagged"

# (c) absent fd/255 (with no anchor anywhere)
R="$(fp_new ac7c)"
mk_member "$R" 4242
run_reaper "$R" report
expect_field anchors 0 "AC7c absent fd/255 -> no anchor"
cases=$((cases + 1))
if [[ "$(field prefiltered_no_fd255)" -ge 1 ]]; then pass "AC7c/M35 pre-filter miss counted separately"
else fail "AC7c/M35 prefiltered_no_fd255 not counted — a ~417-pid baseline would swamp 'unreadable'"; fi

# (d) a pid that vanishes mid-walk
R="$(fp_new ac7d)"
mk_anchor "$R" 4242
mkdir -p "$R/4243/fd"
mk_stat "$R" 4243 1 4243 100
ln -sfn "$DELSCRIPT" "$R/4243/fd/255"
ln -sfn "$HANDLE_A" "$R/4243/cwd"
rm -rf "$R/4243/ns"     # partially-formed entry, as a racing exit leaves it
run_reaper "$R" report
cases=$((cases + 1))
if [[ "$RR_RC" == "0" && "$(field valid)" == "1" ]]; then pass "AC7d vanishing pid -> walk completes"
else fail "AC7d walk did not complete over a partially-formed entry (rc=$RR_RC)"; fi

# (e) unparseable stat
R="$(fp_new ac7e)"
mk_anchor "$R" 4242
printf 'not a stat line at all\n' > "$R/4242/stat"
run_reaper "$R" report
expect_field anchors 0 "AC7e unparseable stat -> not flagged"

# (f) unreadable /proc/uptime — read from the SEAM root, never a literal
#     /proc/uptime, or AC8's two directions are unmeasurable.
R="$(fp_new ac7f)"
mk_anchor "$R" 4242
rm -f "$R/uptime"
run_reaper "$R" report
expect_field anchors 0 "AC7f unreadable uptime -> not flagged"

# (g) non-numeric starttime
R="$(fp_new ac7g)"
mk_anchor "$R" 4242
printf '%s (bash) S 1 4242 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s\n' 4242 "notanumber" > "$R/4242/stat"
run_reaper "$R" report
expect_field anchors 0 "AC7g non-numeric starttime -> not flagged"

# AC8 — age floor, BOTH directions, from ONE fixture.
R="$(fp_new ac8)"
mk_anchor "$R" 4242 "$HANDLE_A" 99999000      # started ~999990s into uptime
printf '%s 0.00\n' "1000000.00" > "$R/uptime" # => ~10s old
run_reaper "$R" report ORPHAN_REAPER_MIN_AGE_S=600
expect_field anchors 0 "AC8 younger than the floor -> NOT flagged"
mk_anchor "$R" 4242 "$HANDLE_A" 100           # ~999999s old
run_reaper "$R" report ORPHAN_REAPER_MIN_AGE_S=600
expect_field anchors 1 "AC8 the same fixture aged past the floor -> flagged"

# Accept-direction: exactly AT the boundary.
mk_anchor "$R" 4242 "$HANDLE_A" $(( (1000000 - 600) * CLK_TCK ))
run_reaper "$R" report ORPHAN_REAPER_MIN_AGE_S=600
expect_field anchors 1 "accept-direction: an anchor exactly at the age floor flags"

# AC9 — THE MEASURED FAIL-OPEN. `_tc_stat_field` returns exit 0 with EMPTY
# output on an unreadable stat file, and empty is arithmetic zero even under
# `set -u`, so `(( (now - "") > 600 ))` PASSES the age floor. Without the
# ^[0-9]+$ validation the gate whose entire job is to spare fresh processes
# fails open. Asserted directly.
R="$(fp_new ac9)"
mk_anchor "$R" 4242
: > "$R/4242/stat"                 # readable, but empty -> empty starttime
run_reaper "$R" report ORPHAN_REAPER_MIN_AGE_S=600
expect_field anchors 0 "AC9 empty starttime is 'unreadable', never a verdict"
cases=$((cases + 1))
if [[ "$(field unreadable)" -ge 1 ]]; then pass "AC9 the empty reading is counted unreadable"
else fail "AC9 an empty borrowed-primitive reading passed the age floor — the measured fail-open"; fi

# AC10 — anchorless. A process in an unlinked cwd with NO anchor anywhere is
# never signalled: the set derives from a confirmed anchor, never its own
# predicate (a set on its own predicate is a second detector wearing the
# first one's authority).
R="$(fp_new ac10)"
mk_member "$R" 4243 "$HANDLE_A"
mk_member "$R" 4244 "$HANDLE_A"
run_reaper "$R" report
expect_field anchors      0 "AC10 anchorless: no anchor"
expect_field set_members  0 "AC10 anchorless: no set"
expect_field would_signal 0 "AC10 anchorless: nothing would be signalled"

# AC11 — self-exclusion, asserted SEPARATELY for anchors and for members,
# because an earlier draft satisfied the first and still contained the suicide
# bug. `git worktree remove` under a running suite leaves test-all.sh, the
# reaper it spawned, and every suite child sharing ONE unlinked cwd.
R="$(fp_new ac11-anchor)"
mk_anchor "$R" "$FIXTURE_SELF_PID"
# EXCLUDE_PGID is pinned to a group no fixture uses so the process-group gate
# cannot fire: without this the arm passes via pgid and mutating self-exclusion
# is invisible (measured — M6, M7 and H4 all survived).
run_reaper "$R" report ORPHAN_REAPER_EXCLUDE_PGID=888888
expect_field anchors 0 "AC11 the scanner never flags ITSELF as an anchor"

R="$(fp_new ac11-member)"
mk_anchor "$R" 4242
mk_member "$R" "$FIXTURE_SELF_PID" "$HANDLE_A"    # scanner shares the doomed inode
run_reaper "$R" report ORPHAN_REAPER_EXCLUDE_PGID=888888
cases=$((cases + 1))
if [[ "$(awk -v p="$FIXTURE_SELF_PID" '$1=="member" && $0 ~ ("pid=" p "( |$)") {n++} END{print n+0}' <<<"$RR_OUT")" == "0" ]]; then
  pass "AC11/M7 the scanner is excluded from the REAP SET (the suicide bug)"
else
  fail "AC11/M7 the scanner appeared in its own reap set"
fi

# Same-process-group exclusion.
R="$(fp_new ac11-pgid)"
mk_anchor "$R" 4242
mk_member "$R" 4250 "$HANDLE_A"
mk_stat "$R" 4250 1 777777 100
run_reaper "$R" report ORPHAN_REAPER_EXCLUDE_PGID=777777
expect_field skipped_same_pgroup 1 "AC11 same-process-group members are excluded and counted"

# AC17/M17 — MEMBERSHIP RESTATES THE GATES; it never inherits the anchor's
# verdict. The witness is a process sharing the anchor's cwd dev:inode that
# fails a gate the ANCHOR passes — here G6, the age floor. Without this arm the
# only thing distinguishing "membership re-checks" from "membership inherits" is
# self-exclusion, which is M7's axis, and the two rows become one mutation
# wearing two names (measured: identical failing-arm sets).
R="$(fp_new ac17-member-gates)"
mk_anchor "$R" 4242 "$HANDLE_A" 100
mk_member "$R" 4243 "$HANDLE_A" 99999000    # same doomed inode, ~10s old
run_reaper "$R" report ORPHAN_REAPER_MIN_AGE_S=600
expect_field anchors     1 "AC17 the aged anchor still flags"
expect_field set_members 1 "AC17 a young member does NOT inherit the anchor's verdict"

# AC12 — structural refusal. The scanner is INSIDE the doomed directory and
# cannot adjudicate it.
R="$(fp_new ac12)"
mk_anchor "$R" 4242
mk_member "$R" "$FIXTURE_SELF_PID" "$HANDLE_A"
run_reaper "$R" report ORPHAN_REAPER_SELF_CWD_OVERRIDE="$HANDLE_A" ORPHAN_REAPER_EXCLUDE_PGID=888888
expect_field valid 0 "AC12 scanner inside the doomed inode -> valid=0"
cases=$((cases + 1))
if [[ "$RR_RC" == "1" ]]; then pass "AC12 a structurally invalid walk exits 1"
else fail "AC12 expected exit 1 for an invalid walk, got $RR_RC"; fi

# AC13 — cardinality cap. Refused WHOLE, counted, and still reported. The cap
# bars automatic action only; `reap` takes an explicit override the banner
# names, so it is a speed bump for a human rather than a wall for the tool.
R="$(fp_new ac13)"
mk_anchor "$R" 4242
for p in 4243 4244 4245 4246; do mk_member "$R" "$p" "$HANDLE_A"; done
run_reaper "$R" report ORPHAN_REAPER_MAX_SET=3
expect_field refused_cap  1 "AC13 an oversized set is refused whole"
expect_field would_signal 0 "AC13 a capped set signals nothing automatically"
cases=$((cases + 1))
if [[ "$(lines_of member)" -ge 1 ]]; then pass "AC13 the full set is still REPORTED"
else fail "AC13 a capped set must still be reported, not hidden"; fi

# AC14 — sibling-session safety. A wedged own-uid `git commit` whose worktree
# still exists is spared by the live-cwd term. Once the worktree is gone it
# becomes a set member — and is REPORTED, never signalled, by the trigger
# design; TERMing it would strand .git/index.lock and break the other
# session's next commit.
R="$(fp_new ac14-live)"
mkdir -p "$R/4250/fd"
mk_stat "$R" 4250 1 4250 100 git
mk_ns   "$R" 4250 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$TESTROOT" "$R/4250/cwd"      # worktree still exists
mk_cmdline "$R" 4250 "git commit"
run_reaper "$R" report
expect_field anchors 0 "AC14 a wedged git commit with a LIVE worktree is not flagged"

R="$(fp_new ac14-gone)"
mk_anchor "$R" 4242
mk_member "$R" 4250 "$HANDLE_A" 100 git
run_reaper "$R" report
expect_field signalled 0 "AC14 the trigger path signals nothing, ever"
cases=$((cases + 1))
if [[ "$(lines_of signalled)" == "0" ]]; then pass "AC14 no '^signalled ' line from the report path"
else fail "AC14 the report path emitted a signalled line"; fi

# AC30b — FIXTURE-REALISM CONTROL. The naive dangling-symlink fixture must
# classify `unreadable`, NOT as an anchor. Without this, a refactor back to
# dangling symlinks turns every positive arm green-but-vacuous.
R="$(fp_new ac30b)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "/tmp/definitely-gone-$$ (deleted)" "$R/4242/cwd"
ln -sfn "/tmp/definitely-gone-$$/s.sh (deleted)" "$R/4242/fd/255"
run_reaper "$R" report
expect_field anchors 0 "AC30b the naive dangling-symlink fixture is 'unreadable', not an anchor"
cases=$((cases + 1))
if [[ "$(field unreadable)" -ge 1 ]]; then pass "AC30b and it is COUNTED unreadable"
else fail "AC30b a dangling fixture must count unreadable — otherwise positive arms pass vacuously"; fi

# Must-PASS non-canonical: a memfd on fd/255 (nlink 0, regular, but NOT a
# script at an absolute deleted path) with an unlinked cwd. `%h == 0` alone is
# far broader than 'the bash script is unlinked', and an anchor authorizes a
# whole reap set.
R="$(fp_new memfd)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$HANDLE_A" "$R/4242/cwd"
ln -sfn "$HANDLE_SCRIPT" "$R/4242/fd/255"   # readlink has NO ' (deleted)' suffix
run_reaper "$R" report
expect_field anchors 0 "AC/M31 a memfd-shaped fd/255 does not become an anchor"

# G3's regular-file term, isolated: an unlinked DIRECTORY behind a
# ' (deleted)'-suffixed absolute path satisfies every other term of G3.
R="$(fp_new notafile)"
mkdir -p "$R/4242/fd"
mk_stat "$R" 4242 1 4242 100
mk_ns   "$R" 4242 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$HANDLE_A" "$R/4242/cwd"
ln -sfn "$DELDIR" "$R/4242/fd/255"
run_reaper "$R" report
expect_field anchors 0 "AC/M31 an unlinked DIRECTORY on fd/255 is not an unlinked script"

# ===========================================================================
# Verbs and evidence (AC15-AC23, AC28b-AC28j)
# ===========================================================================
echo "--- verbs and evidence ---"

# AC15 — `report` signals nothing. The PAIRED POSITIVE is load-bearing: an
# absence assertion alone is satisfied by renaming or dropping the field, so
# signalled=0 is asserted TOGETHER WITH would_signal>0 on ONE summary line.
R="$(fp_new ac15)"
mk_anchor "$R" 4242
mk_member "$R" 4243 "$HANDLE_A"
run_reaper "$R" report
expect_field signalled 0 "AC15 report signals nothing"
cases=$((cases + 1))
if [[ "$(field would_signal)" -gt 0 ]]; then pass "AC15 …and would_signal>0 on the same line (the positive control)"
else fail "AC15 would_signal must be >0 here, or signalled=0 proves nothing"; fi
expect_field mode report "AC15 mode is reported"

# AC16 — exit codes are 0 and 1 and nothing else. That the default exit is
# INDEPENDENT of findings is the point: an earlier draft added 10 for
# 'candidates found', which test-all.sh's suite_exit_class() classifies as
# FAILED — so the first time the detector ever worked, the gate went red.
R="$(fp_new ac16-found)"
mk_anchor "$R" 4242
run_reaper "$R" report
cases=$((cases + 1))
if [[ "$RR_RC" == "0" ]]; then pass "AC16 exit 0 when the walk completes WITH findings"
else fail "AC16 findings must not change the exit code (got $RR_RC)"; fi
R="$(fp_new ac16-empty)"
run_reaper "$R" report
cases=$((cases + 1))
if [[ "$RR_RC" == "0" ]]; then pass "AC16 exit 0 when the walk completes with no findings"
else fail "AC16 expected 0 on an empty walk, got $RR_RC"; fi

# AC17 — `reap` sends TERM only, one pid at a time, never to a process group,
# never escalating to KILL. Asserted against the captured-signal sink, not by
# reading the source.
R="$(fp_new ac17)"
mk_anchor "$R" 4242
mk_member "$R" 4243 "$HANDLE_A"
SINK="$TESTROOT/sink-ac17"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0
cases=$((cases + 1))
if [[ "$(grep -cE '^-' "$SINK" || true)" == "0" ]]; then pass "AC17 no negative pid — never a process group"
else fail "AC17 a process-group signal reached the sink"; fi
cases=$((cases + 1))
if [[ "$(grep -ciE 'KILL' "$SINK" || true)" == "0" ]]; then pass "AC17 no escalation to KILL"
else fail "AC17 the sink recorded a KILL escalation"; fi
expect_field signalled 2 "AC17 both pids signalled, one at a time"

# AC18 — re-verification at the signal site covers pid recycling AND inode
# recycling (the same class). An inode number is pinned only while something
# holds it, and /tmp is tmpfs with fast churn, so a set membership computed at
# T0 is not evidence at T1.
R="$(fp_new ac18)"
mk_anchor "$R" 4242
mk_member "$R" 4243 "$HANDLE_A"
SINK="$TESTROOT/sink-ac18"; : > "$SINK"
# Recycle 4243 between scan and signal: the reaper re-reads starttime before
# signalling, and the seam below rewrites it mid-run.
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0 \
  ORPHAN_REAPER_RECYCLE_PID=4243
expect_field late_refused 1 "AC18 a recycled pid is refused at the signal site"
cases=$((cases + 1))
if [[ "$(grep -cE '^4243$' "$SINK" || true)" == "0" ]]; then pass "AC18 …and never signalled"
else fail "AC18 a recycled pid was signalled"; fi

# AC19 — SEAM SAFETY. The walk is `for d in "$ORPHAN_PROC_ROOT"/[0-9]*` and
# fixtures are directories named like `4242`. Real pids on this box are in the
# 2.9-million range, but LOW pids are live. `reap` therefore refuses outright
# when the seam is not /proc unless a sink is injected.
R="$(fp_new ac19)"
mk_anchor "$R" 1              # a fixture named for a live pid
run_reaper "$R" reap ORPHAN_REAPER_DRY_RUN=0     # NO sink injected
cases=$((cases + 1))
if [[ "$(field signalled)" == "0" && "$RR_RC" != "0" ]]; then
  pass "AC19 reap refuses a non-/proc seam with no injected sink"
else
  fail "AC19 reap proceeded against a fixture root with no sink (rc=$RR_RC) — a live pid could receive TERM"
fi

# AC28d — signal-operand validation. `^[0-9]+$` admits both `0` and `0777`;
# `kill -TERM 0` signals the CALLER'S ENTIRE PROCESS GROUP. Real /proc never
# produces such entries, which is exactly why only the seam path can reach them.
R="$(fp_new ac28d)"
mk_anchor "$R" 4242
mk_member "$R" 0 "$HANDLE_A" 2>/dev/null || true
mkdir -p "$R/0/fd"; mk_stat "$R" 0 1 0 100; mk_ns "$R" 0 "$NS_MNT_SELF" "$NS_PID_SELF"
ln -sfn "$HANDLE_A" "$R/0/cwd"
SINK="$TESTROOT/sink-ac28d"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0
cases=$((cases + 1))
if [[ "$(grep -cE '^0$' "$SINK" || true)" == "0" ]]; then pass "AC28d a /proc entry named '0' never reaches the signal site"
else fail "AC28d pid 0 reached the signal site — kill -TERM 0 signals the caller's process group"; fi

# pid 1 is refused explicitly.
R="$(fp_new ac28d1)"
mk_anchor "$R" 1
SINK="$TESTROOT/sink-ac28d1"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0
cases=$((cases + 1))
if [[ "$(grep -cE '^1$' "$SINK" || true)" == "0" ]]; then pass "AC28d pid 1 is refused"
else fail "AC28d pid 1 reached the signal site"; fi

# AC28e — SINK SHAPE. The injected sink is a FILE PATH pids are appended to,
# never a command name that is executed. An env-var-named command inside a
# shipped script is an arbitrary-execution hook.
R="$(fp_new ac28e)"
mk_anchor "$R" 4242
CANARY="$TESTROOT/canary-executed"
rm -f "$CANARY"
cat > "$TESTROOT/evil-sink" <<EVIL
#!/usr/bin/env bash
touch "$CANARY"
EVIL
chmod +x "$TESTROOT/evil-sink"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$TESTROOT/evil-sink" ORPHAN_REAPER_DRY_RUN=0 || true
cases=$((cases + 1))
if [[ ! -e "$CANARY" ]]; then pass "AC28e the sink is written to, never executed"
else fail "AC28e the sink value was EXECUTED — an arbitrary-execution hook"; fi

# AC20 — EVIDENCE BEFORE SIGNAL. It must precede the signal for a specific
# reason rather than out of caution: after a successful kill the /proc entry is
# gone, so the evidence links can never be re-examined by anyone — and the
# victim class has unrecoverable output by construction, so this is the only
# record that a false positive ever happened.
R="$(fp_new ac20)"
mk_anchor "$R" 4242
EV="$TESTROOT/ev-ac20"; : > "$EV"
SINK="$TESTROOT/sink-ac20"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0 \
  ORPHAN_REAPER_EVIDENCE_FILE="$EV"
cases=$((cases + 1))
if [[ "$(grep -cE 'pid=4242' "$EV" || true)" -ge 1 ]]; then pass "AC20 a journald record precedes the signal"
else fail "AC20 no evidence record was written for the signalled pid"; fi
for f in starttime uid age role verdict cwd_nlink fd255_nlink; do
  cases=$((cases + 1))
  if [[ "$(grep -cE "$f=" "$EV" || true)" -ge 1 ]]; then pass "AC20 evidence carries $f"
  else fail "AC20 evidence record is missing $f"; fi
done

# AC20/M23 — a FAILED evidence write REFUSES the reap rather than signalling
# unrecorded.
R="$(fp_new ac20-fail)"
mk_anchor "$R" 4242
SINK="$TESTROOT/sink-ac20f"; : > "$SINK"
run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN=0 \
  ORPHAN_REAPER_EVIDENCE_FILE="/nonexistent-dir-$$/evidence.log" || true
cases=$((cases + 1))
if [[ "$(wc -l < "$SINK")" == "0" ]]; then pass "AC20/M23 an unwritable evidence channel refuses the reap"
else fail "AC20/M23 signalled with no evidence record"; fi

# AC28g — EVIDENCE-CHANNEL LIVENESS, probed once at startup and printed.
R="$(fp_new ac28g)"
mk_anchor "$R" 4242
run_reaper "$R" report ORPHAN_REAPER_EVIDENCE_FILE="/nonexistent-dir-$$/e.log"
expect_field evidence down "AC28g an unusable evidence channel reports evidence=down"
run_reaper "$R" report
expect_field evidence ok "AC28g a usable evidence channel reports evidence=ok"

# AC21 — DRY-RUN PARSING IS FAIL-SAFE. Anything other than an explicit off
# value means rehearsal, because proc.sh already paid for the alternative
# (PROC_SH_DRY_RUN=true once performed a real kill on a rehearsal request).
for v in 1 true yes "" TRUE anything; do
  R="$(fp_new "ac21-$RANDOM")"
  mk_anchor "$R" 4242
  SINK="$TESTROOT/sink-ac21"; : > "$SINK"
  run_reaper "$R" reap ORPHAN_REAPER_SIGNAL_SINK="$SINK" ORPHAN_REAPER_DRY_RUN="$v"
  cases=$((cases + 1))
  if [[ "$(wc -l < "$SINK")" == "0" ]]; then pass "AC21 DRY_RUN='$v' rehearses (fail-safe)"
  else fail "AC21 DRY_RUN='$v' performed a real signal — the proc.sh incident class"; fi
done

# AC22 — the counter line prints on EVERY invocation with every field separate.
# `unreadable` is load-bearing and not decoration: the fail-toward-alive rule
# silently drops candidates, and without a count of those drops there is no
# evidence distinguishing 'no orphans' from 'the conjunction is unsatisfiable
# in production'.
R="$(fp_new ac22)"
run_reaper "$R" report
for f in anchors set_members would_signal signalled failed refused refused_cap \
         late_refused skipped_same_pgroup skipped_foreign_ns unreadable scanned \
         valid mode evidence; do
  cases=$((cases + 1))
  if [[ -n "$(field "$f")" ]]; then pass "AC22 counter line carries $f"
  else fail "AC22 counter line is missing the $f field"; fi
done

# AC22/M25 — three unreadable entries report unreadable=3, distinguishable
# from a clean walk.
R="$(fp_new ac22u)"
for p in 4242 4243 4244; do
  mkdir -p "$R/$p/fd"
  mk_stat "$R" "$p" 1 "$p" 100
  mk_ns "$R" "$p" "$NS_MNT_SELF" "$NS_PID_SELF"
  ln -sfn "$DELSCRIPT" "$R/$p/fd/255"
  ln -sfn "/nonexistent-$$/gone (deleted)" "$R/$p/cwd"
done
run_reaper "$R" report
expect_field unreadable 3 "AC22/M25 three unreadable entries are distinguishable from a clean walk"

# AC/M5 — the own-uid gate, against the REAL procfs. A foreign-owned /proc
# entry cannot be synthesized without root, so this is the only witness there
# is. Asserts a SHAPE (foreign-uid processes are counted, not silently walked),
# never a count — the value is ambient.
cases=$((cases + 1))
_o=""; _rc=0
_o="$(env -u CI ORPHAN_REAPER_NO_FLOCK=1 bash "$REAPER" report 2>/dev/null)" || _rc=$?
_fu="$(awk '/^ORPHAN_SCAN /{for(i=2;i<=NF;i++){n=index($i,"=");if(substr($i,1,n-1)=="skipped_foreign_uid"){print substr($i,n+1);exit}}}' <<<"$_o")"
if [[ "$_rc" == "0" && "${_fu:-0}" -gt 0 ]]; then
  pass "AC/M5 foreign-uid processes are refused and COUNTED (skipped_foreign_uid=$_fu)"
else
  fail "AC/M5 the own-uid gate has no observable: skipped_foreign_uid=${_fu:-<absent>} against a real /proc"
fi

# AC23 — SANITIZATION AND OUTPUT GRAMMAR. Spaces, `=` and `/` are printable and
# SURVIVE the tr pass, so a directory named `x signalled pid=1 cwd=/y` would
# otherwise render verbatim inside a report line — indistinguishable from a real
# kill record to a reader, to a `grep signalled`, and to AC15's own negative
# assertion. Attacker-influenceable values are emitted LAST, one per line, and
# every grammar assertion is prefix-anchored.
R="$(fp_new ac23)"
EVILNAME="$TESTROOT/x signalled pid=1 cwd="
mkdir -p "$EVILNAME"
mk_anchor "$R" 4242
ln -sfn "$EVILNAME" "$R/4242/cwd"          # live -> not flagged, but still walked
mk_cmdline "$R" 4242 "$(printf 'bash \033[2Kevil\xe2\x80\xa8x\x7f')"
run_reaper "$R" report
cases=$((cases + 1))
if [[ "$(lines_of signalled)" == "0" ]]; then
  pass "AC23 a directory named 'x signalled pid=1 …' cannot forge a '^signalled ' line"
else
  fail "AC23 a crafted path forged a signalled line — the report grammar is not prefix-anchored"
fi
cases=$((cases + 1))
if ! grep -qP '\x1b|\x7f|\xe2\x80\xa8' <<<"$RR_OUT$RR_ERR" 2>/dev/null; then
  pass "AC23 ANSI, DEL and U+2028 bytes are sanitized out of all output"
else
  fail "AC23 non-printable bytes reached the output — check the LC_ALL=C tr pass"
fi
cases=$((cases + 1))
if grep -qE "LC_ALL=C tr -c '\[:print:\]'" "$REAPER"; then
  pass "AC23 the canonical LC_ALL=C byte-wise sanitizer idiom is used"
else
  fail "AC23 LC_ALL=C is load-bearing and must be pinned — it is what makes the pass byte-wise"
fi

# ===========================================================================
# Robustness of the script itself (AC24-AC28c, AC28i, AC28j)
# ===========================================================================
echo "--- robustness ---"

# AC24 — ERREXIT DISCIPLINE. Measured under `set -euo pipefail`:
#   v=$(stat -Lc '%h' /proc/999999/cwd 2>/dev/null)  -> ABORTS, rc=1
#   v=$(readlink /proc/self/fd/255 2>/dev/null)      -> ABORTS, rc=1
# Both are ORDINARY outcomes of this walk (a pid exits between the glob and the
# readlink; 561 of 592 processes have no fd/255 at all), so an unguarded
# capture kills the walk non-deterministically. There is no mechanical
# backstop: scripts/lint-shell-capture-exit.py's NONZERO_IS_AN_ANSWER set
# covers grep/rg/diff/cmp/pgrep/pidof/test and does NOT include readlink or
# stat, so the registered live linter structurally cannot see this class.
# Hence a source-level check IN ADDITION to the behavioural arm.
cases=$((cases + 1))
_bare="$(grep -nE '^[^#]*[a-z_]+=\$\((readlink|stat)[^)]*\)[[:space:]]*$' "$REAPER" || true)"
if [[ -z "$_bare" ]]; then
  pass "AC24 every readlink/stat capture carries an explicit non-zero handler"
else
  fail "AC24 unguarded readlink/stat capture(s): $_bare"
fi

# AC25 — GLOB GUARD. Bash without nullglob iterates a non-matching pattern
# ONCE, LITERALLY (measured), and nullglob is set in none of the three sibling
# libraries. Without `[[ -d "$d" && ! -L "$d" ]] || continue` a walk over an
# empty procfs reports scanned=1. The `! -L` term is not decoration: `[[ -d ]]`
# is TRUE for a symlink-to-directory and every downstream read is `stat -L`,
# which follows it silently.
R="$(fp_new ac25)"
run_reaper "$R" report
expect_field scanned 0 "AC25 an empty procfs reports scanned=0, not 1"

R="$(fp_new ac25b)"
ln -sfn "$TESTROOT" "$R/4242"      # a numeric SYMLINK entry
run_reaper "$R" report
expect_field scanned 0 "AC25 a numeric symlink entry is not walked"

# AC26 — BORROWED PRIMITIVES. They are underscore-private, so an upstream
# rename silently empties the exclusion set — and errexit does not rescue it,
# because `local x=$(_tc_pgrp …)` masks the substitution's status behind
# `local`'s own return of 0.
cases=$((cases + 1))
if grep -qE 'declare -F _tc_self_and_ancestors' "$REAPER" \
   && grep -qE 'declare -F _tc_pgrp' "$REAPER" \
   && grep -qE 'declare -F _tc_starttime_ticks' "$REAPER"; then
  pass "AC26 a declare -F assertion covers all three borrowed helpers"
else
  fail "AC26 the declare -F assertion is missing a borrowed helper name"
fi
# The same assertion in the SUITE, per AC26.
cases=$((cases + 1))
# Sourced in a SUBSHELL: the library rebinds TC_* globals and installs its own
# traps, so sourcing it into this shell would silently change what every later
# arm measures.
if ( TC_PROC_ROOT=/proc TC_SELF_PID=$$ . "$REPO_ROOT/scripts/lib/test-contention.sh" >/dev/null 2>&1 \
     && declare -F _tc_self_and_ancestors >/dev/null \
     && declare -F _tc_pgrp >/dev/null \
     && declare -F _tc_starttime_ticks >/dev/null ); then
  pass "AC26 all three borrowed helpers exist upstream"
else
  fail "AC26 a borrowed _tc_* helper was renamed or removed upstream"
fi

# TC_PROC_ROOT / TC_SELF_PID are set from THIS script's own seams BEFORE the
# source. These — not TC_TMPDIR — are the seams that govern the borrowed
# helpers: _tc_self_and_ancestors() reads both as globals. test-all.sh exports
# TC_TMPDIR and neither of the other two, so pinning only the reaper's own
# procfs seam would leave self-exclusion reading the REAL /proc.
cases=$((cases + 1))
_srcline="$(grep -nE '^[[:space:]]*(\.|source) .*(test-contention\.sh|\$_LIB)' "$REAPER" | head -1 | cut -d: -f1 || true)"
_tcline="$(grep -nE '^[[:space:]]*(export )?TC_PROC_ROOT=' "$REAPER" | head -1 | cut -d: -f1 || true)"
_tsline="$(grep -nE '^[[:space:]]*(export )?TC_SELF_PID=' "$REAPER" | head -1 | cut -d: -f1 || true)"
if [[ -n "$_srcline" && -n "$_tcline" && -n "$_tsline" \
      && "$_tcline" -lt "$_srcline" && "$_tsline" -lt "$_srcline" ]]; then
  pass "AC26 TC_PROC_ROOT and TC_SELF_PID are set BEFORE the source"
else
  fail "AC26 the borrowed-helper seams must be assigned before test-contention.sh is sourced"
fi

# Only those three private readers — no public tc_* verb. tc_acquire locks and
# tc_preamble performs the 6.6 s walk.
cases=$((cases + 1))
_pub="$(grep -nE '^[^#]*[^_a-zA-Z](tc_acquire|tc_preamble|tc_epilogue|tc_capacity_line|tc_tmp_entry_count|tc_used_bytes|tc_avail_mb)[[:space:]]*(\(|$| )' "$REAPER" || true)"
if [[ -z "$_pub" ]]; then pass "AC26/AC28 no public tc_* verb is called"
else fail "AC26/AC28 a public tc_* verb is called: $_pub"; fi

# AC27 — SEAM HONESTY. Every seam declared in the header is READ by the code
# below it. A seam that is documented but unimplemented produces a test that
# sets it, observes no effect, and passes for the wrong reason.
cases=$((cases + 1))
_missing=""
for s in $(grep -oE '\bORPHAN_(REAPER|PROC)_[A-Z_]+\b' "$REAPER" | sort -u || true); do
  # Declared in the header comment block AND read below it.
  if [[ "$(grep -cE "^[^#]*\\\$\{?$s" "$REAPER" || true)" == "0" ]]; then
    _missing="$_missing $s"
  fi
done
if [[ -z "$_missing" ]]; then pass "AC27 every declared seam is read by the code"
else fail "AC27 seam(s) declared but never read:$_missing"; fi

# AC28 — LOCK DISCIPLINE, matching the scripts/tmpfs-guard.sh precedent.
# Three arms: contention, lockfile-uncreatable, and the no-flock seam.
R="$(fp_new ac28)"
mk_anchor "$R" 4242
LOCKF="$TESTROOT/reaper.lock"
: > "$LOCKF"
cases=$((cases + 1))
# Hold the lock from another process, then require exit 0 AND a spoken line.
READY="$TESTROOT/lock-held"; rm -f "$READY"
( exec 200>"$LOCKF"; flock -n 200 || exit 1; : > "$READY"; sleep 10 ) &
_holder=$!
HELPER_PIDS+=("$_holder")
_w=0
while [[ ! -e "$READY" && "$_w" -lt 50 ]]; do sleep 0.1; _w=$((_w + 1)); done
run_reaper "$R" report ORPHAN_REAPER_NO_FLOCK=0 ORPHAN_REAPER_LOCKFILE="$LOCKF"
if [[ ! -e "$READY" ]]; then
  fail "AC28 contention arm: the holder never acquired the lock — fixture error, not a SUT verdict"
elif [[ "$RR_RC" == "0" ]] && grep -qiE 'in flight|skipping' <<<"$RR_ERR$RR_OUT"; then
  pass "AC28 contention: exits 0 and SAYS SO (a silent skip is indistinguishable from 'found nothing')"
else
  fail "AC28 contention arm: rc=$RR_RC, and no in-flight line was printed"
fi
kill -KILL "$_holder" 2>/dev/null || true
wait "$_holder" 2>/dev/null || true

cases=$((cases + 1))
run_reaper "$R" report ORPHAN_REAPER_NO_FLOCK=0 ORPHAN_REAPER_LOCKFILE="/nonexistent-dir-$$/x.lock"
if [[ "$RR_RC" == "0" ]] && grep -qiE 'unserialised|unserialized' <<<"$RR_ERR$RR_OUT"; then
  pass "AC28 uncreatable lockfile: runs UNSERIALISED and says so (never exec 9>/dev/null)"
else
  fail "AC28 uncreatable-lockfile arm: rc=$RR_RC and no 'unserialised' line"
fi
cases=$((cases + 1))
if ! grep -qE '^[^#]*exec [0-9]+>[[:space:]]*/dev/null' "$REAPER"; then
  pass "AC28 never falls back to locking the shared /dev/null inode"
else
  fail "AC28 an exec N>/dev/null lock fallback is present — it locks an inode shared box-wide"
fi
cases=$((cases + 1))
run_reaper "$R" report ORPHAN_REAPER_NO_FLOCK=1
if [[ "$RR_RC" == "0" && "$(field valid)" == "1" ]]; then pass "AC28 ORPHAN_REAPER_NO_FLOCK=1 exercises the unlocked arm"
else fail "AC28 the no-flock seam did not produce a clean run"; fi

# AC28b — PRIVILEGE FLOOR. G1 is `stat -Lc '%u' == id -u`, so under sudo 'own
# uid' silently becomes uid 0 and the enforcement-by-accident (readlink failing
# on a foreign process) evaporates — measured, readlink /proc/1/cwd fails as
# uid 1001 and succeeds as root. The reap set would become EVERY root process
# with an unlinked cwd, a populated class on a box mid-apt. The banner prints a
# reap command an operator may reflexively prefix with sudo when it "doesn't
# work", so this is the realistic path.
cases=$((cases + 1))
if grep -qE 'EUID' "$REAPER" && grep -qE '\bid -u\b' "$REAPER"; then
  pass "AC28b the root refusal reads EUID"
else
  fail "AC28b no EUID-based root refusal found"
fi
R="$(fp_new ac28b)"
mk_anchor "$R" 4242
run_reaper "$R" report ORPHAN_REAPER_FORCE_EUID=0
cases=$((cases + 1))
if [[ "$RR_RC" != "0" && "$(field anchors)" != "1" ]]; then
  pass "AC28b both verbs refuse to run as root"
else
  fail "AC28b the tool proceeded as root (rc=$RR_RC) — G1 PASSES under sudo, which is the danger"
fi

# AC28c — PROCFS IDENTITY, NOT NAME. A `!= /proc` string comparison refuses
# harmless aliases while permitting the one dangerous case it cannot see: a
# procfs from a foreign PID namespace bind-mounted at /proc, whose pids are not
# pids in the reaper's kill namespace.
cases=$((cases + 1))
if grep -qE "stat -fc '%T'" "$REAPER"; then pass "AC28c procfs is checked by identity (stat -fc '%T')"
else fail "AC28c procfs must be identified by filesystem type, not by path name"; fi

# G7 — foreign pid namespace.
R="$(fp_new ac28c-pidns)"
mk_anchor "$R" 4242
ln -sfn 'pid:[4026599998]' "$R/4242/ns/pid"
run_reaper "$R" report
expect_field anchors 0 "AC28c/G7 a foreign pid namespace is not adjudicated"

# The seam UNSET, and the seam EMPTY-BUT-SET. test-contention.sh binds
# TC_PROC_ROOT="${TC_PROC_ROOT:-/proc}" with `:-`, not `-`, so an empty-but-set
# seam silently reverts the borrowed helpers to the real /proc while this
# script's own walk globs /[0-9]* at the FILESYSTEM ROOT.
cases=$((cases + 1))
_o=""; _rc=0
_o="$(env -u CI -u ORPHAN_PROC_ROOT ORPHAN_REAPER_SELF_PID="$FIXTURE_SELF_PID" ORPHAN_REAPER_NO_FLOCK=1 \
      bash "$REAPER" report 2>&1)" || _rc=$?
if [[ "$_rc" == "0" ]] && grep -qE '^ORPHAN_SCAN .*valid=1' <<<"$_o"; then
  pass "AC28c seam UNSET falls back to the real /proc cleanly"
else
  fail "AC28c an unset seam did not produce a valid walk (rc=$_rc)"
fi
cases=$((cases + 1))
_o=""; _rc=0
_o="$(env -u CI ORPHAN_PROC_ROOT="" ORPHAN_REAPER_SELF_PID="$FIXTURE_SELF_PID" ORPHAN_REAPER_NO_FLOCK=1 \
      bash "$REAPER" report 2>&1)" || _rc=$?
if [[ "$_rc" != "0" ]] || grep -qE 'valid=0' <<<"$_o"; then
  pass "AC28c an EMPTY-but-set seam is refused, not silently reverted to /proc"
else
  fail "AC28c an empty seam was accepted — the walk would glob /[0-9]* at the filesystem root"
fi

# AC28f — SET MEMBERSHIP IS DEVICE-QUALIFIED. R2a retired the %d:%i comparison
# from the DELETEDNESS test, but membership is still an inode-NUMBER equality
# test and R1b's cross-device collision applies verbatim. /tmp is dev 50
# (tmpfs) and a worktree is dev 66307 (ext4), and tmpfs hands inode numbers
# from a monotonic counter, so the number is STEERABLE. Without %d an unrelated
# process can be walked into a foreign anchor's set while both independently
# pass every gate — restating the gates per member does not catch it.
cases=$((cases + 1))
if grep -qE "stat -Lc '%d:%i'" "$REAPER" && ! grep -qE "stat -Lc '%i'" "$REAPER"; then
  pass "AC28f set membership compares %d:%i, never bare %i"
else
  fail "AC28f a bare %i membership comparison is cross-device collidable"
fi
# Behavioural: a member on a DIFFERENT inode must not join the set.
R="$(fp_new ac28f)"
mk_anchor "$R" 4242 "$HANDLE_A"
mk_member "$R" 4243 "$HANDLE_B"     # unlinked too, but a different inode
run_reaper "$R" report
expect_field set_members 1 "AC28f a different unlinked inode does not join the set"

# AC28i — STREAM DISCIPLINE. preflight Check 10 matches captured STDOUT with
# stderr discarded, so a counter line on stderr — where all 14 sibling
# contention banners go — makes the discoverability probe a deterministic FAIL
# for a reason unrelated to this change.
R="$(fp_new ac28i)"
mk_anchor "$R" 4242
run_reaper "$R" report
cases=$((cases + 1))
if grep -qE '^ORPHAN_SCAN ' <<<"$RR_OUT"; then pass "AC28i the counter line goes to STDOUT"
else fail "AC28i the ORPHAN_SCAN counter line is not on stdout"; fi
cases=$((cases + 1))
if ! grep -qE '^ORPHAN_SCAN ' <<<"$RR_ERR"; then pass "AC28i …and not duplicated onto stderr"
else fail "AC28i the counter line was also written to stderr"; fi

# AC28j — CI BEHAVIOUR. test-all.sh runs on GitHub-hosted runners in three
# ci.yml shards and in main-health-monitor.yml, and the existing CI exemption
# guards tc_acquire, not the preamble.
R="$(fp_new ac28j)"
mk_anchor "$R" 4242
run_reaper "$R" report CI=true
cases=$((cases + 1))
if [[ "$RR_RC" == "0" ]] && grep -qiE 'CI' <<<"$RR_ERR$RR_OUT"; then
  pass "AC28j under CI the reaper skips and prints one line saying so"
else
  fail "AC28j no CI skip line (rc=$RR_RC)"
fi

# ===========================================================================
# End-to-end (AC38, AC40)
# ===========================================================================
echo "--- end-to-end ---"

# AC38 — LIVE PROCFS SANITY. Deliberately asserts NO finding count: a real
# orphan at verification time is ambient state (cq-ac-must-not-depend-on-
# concurrent-sessions). What this pins is that the walk executes against a real
# procfs at all — the class of breakage a synthesized-/proc suite structurally
# cannot see.
if [[ "$SKIP_LIVE" == "1" ]]; then
  echo "  [skip] AC38/AC40 live-process arms (ORPHAN_SUITE_SKIP_LIVE=1)"
else
cases=$((cases + 1))
_o=""; _rc=0
_o="$(env -u CI ORPHAN_REAPER_NO_FLOCK=1 bash "$REAPER" report 2>/dev/null)" || _rc=$?
if [[ "$_rc" == "0" ]] \
   && grep -qE '^ORPHAN_SCAN .*valid=1' <<<"$_o" \
   && [[ "$(awk '/^ORPHAN_SCAN /{for(i=2;i<=NF;i++){n=index($i,"=");if(substr($i,1,n-1)=="scanned"){print substr($i,n+1);exit}}}' <<<"$_o")" -gt 0 ]]; then
  pass "AC38 a live /proc walk exits 0, reports valid=1 and scanned>0"
else
  fail "AC38 the live-procfs walk did not complete cleanly (rc=$_rc)"
fi

# AC40 — INCIDENT TRACE. Reproduces the 2026-08-13 shape from launch to
# reclamation with a REAL TERM to a REAL victim. Every other kill-side
# criterion runs against the mock, so without this arm no process ever actually
# dies in the suite — and since the plan states three times that it has no
# sensitivity evidence, an end-to-end real-signal arm is the only such evidence
# obtainable before shipping.
echo "--- AC40: incident trace (real signal) ---"
E2E="$TESTROOT/e2e"
mkdir -p "$E2E/work"
cat > "$E2E/work/run.sh" <<'VICTIM'
#!/usr/bin/env bash
# The wrapper: bash, so it carries an fd/255 on this very script. It reports its
# OWN pid — `setsid` forks, so the launcher's $! is setsid's pid, not this one.
echo "$$" > "$E2E_WRAP_FILE"
python3 -c 'import time
while True: time.sleep(0.2)' &
echo "$!" > "$E2E_CHILD_FILE"
wait
VICTIM
chmod +x "$E2E/work/run.sh"

# setsid: a new session, so the victim is neither an ancestor of the suite nor
# in its process group — exactly the shape a detached orphan has.
( cd "$E2E/work" && E2E_WRAP_FILE="$E2E/wrapper.pid" E2E_CHILD_FILE="$E2E/child.pid" \
    setsid bash ./run.sh >/dev/null 2>&1 & ) 2>/dev/null
_w=0
while [[ ! -s "$E2E/child.pid" && "$_w" -lt 60 ]]; do sleep 0.1; _w=$((_w + 1)); done
sleep 0.3
E2E_WRAPPER="$(cat "$E2E/wrapper.pid" 2>/dev/null || echo "")"
E2E_CHILD="$(cat "$E2E/child.pid" 2>/dev/null || echo "")"
[[ -n "$E2E_WRAPPER" ]] && HELPER_PIDS+=("$E2E_WRAPPER")
[[ -n "$E2E_CHILD" ]] && HELPER_PIDS+=("$E2E_CHILD")

# `git worktree remove` on a worktree with a suite still running inside it
# produces the target signature exactly — the honest answer to "has this shape
# ever occurred here", which the zero-hit census cannot supply.
rm -rf "$E2E/work"
sleep 0.3

cases=$((cases + 1))
if [[ -n "$E2E_WRAPPER" ]] && kill -0 "$E2E_WRAPPER" 2>/dev/null; then
  pass "AC40 the victim tree is alive with an unlinked cwd and script"

  # Hop 1: report identifies the anchor, enumerates the set, names the reap
  # command, and signals NOTHING.
  _o=""; _rc=0
  _o="$(env -u CI ORPHAN_REAPER_NO_FLOCK=1 ORPHAN_REAPER_MIN_AGE_S=0 \
        ORPHAN_REAPER_EVIDENCE_FILE="$TESTROOT/ev-e2e" \
        bash "$REAPER" report 2>/dev/null)" || _rc=$?
  cases=$((cases + 1))
  if grep -qE "^anchor pid=$E2E_WRAPPER( |$)" <<<"$_o"; then
    pass "AC40 hop 1: the real orphan is identified as an anchor"
  else
    fail "AC40 hop 1: the real orphan was NOT identified (this is the only sensitivity evidence in the suite)"
  fi
  cases=$((cases + 1))
  if grep -qE '^ORPHAN_SCAN .*signalled=0' <<<"$_o"; then
    pass "AC40 hop 2: the trigger path signals nothing"
  else
    fail "AC40 hop 2: the report path signalled something"
  fi
  cases=$((cases + 1))
  if grep -qiE 'orphan-process-reaper\.sh reap' <<<"$_o"; then
    pass "AC40 hop 3: the exact reap command is named for the set it found"
  else
    fail "AC40 hop 3: the report did not name the reap command a reader must run"
  fi

  # Hop 4: an explicit reap signals the non-bash CHILD before the anchor, with
  # a journald record preceding each signal.
  EV="$TESTROOT/ev-e2e-reap"; : > "$EV"
  _o=""; _rc=0
  _o="$(env -u CI ORPHAN_REAPER_NO_FLOCK=1 ORPHAN_REAPER_MIN_AGE_S=0 ORPHAN_REAPER_DRY_RUN=0 \
        ORPHAN_REAPER_EVIDENCE_FILE="$EV" \
        bash "$REAPER" reap 2>/dev/null)" || _rc=$?
  sleep 0.6
  cases=$((cases + 1))
  if ! kill -0 "$E2E_WRAPPER" 2>/dev/null; then
    pass "AC40 hop 5: the real victim is reclaimed by a real TERM"
  else
    fail "AC40 hop 5: the victim survived an explicit reap"
  fi
  cases=$((cases + 1))
  if [[ -n "$E2E_CHILD" ]] && ! kill -0 "$E2E_CHILD" 2>/dev/null; then
    pass "AC40 hop 6: the CPU-holding child is reclaimed too, not just the wrapper"
  else
    fail "AC40 hop 6: the child that actually held the cores survived — the R1a defect end-to-end"
  fi
  cases=$((cases + 1))
  if [[ -n "$E2E_CHILD" ]] && [[ "$(grep -cE "verdict=authorized pid=$E2E_CHILD( |$)" "$EV" || true)" -ge 1 ]]; then
    pass "AC40 hop 7: an authorizing record precedes the real signal"
  else
    fail "AC40 hop 7: no evidence record for the pid that was actually signalled"
  fi
else
  fail "AC40 the e2e victim did not start — fixture error, not a SUT verdict"
  cases=$((cases + 6))
  fails=$((fails + 6))
fi

fi   # SKIP_LIVE

# ===========================================================================
# Integration with the runner (AC33, AC34)
# ===========================================================================
echo "--- runner integration ---"
TA="$REPO_ROOT/scripts/test-all.sh"

# AC33 — scripts/*.test.sh is NOT auto-globbed by the runner, so an unregistered
# suite is an ORPHAN that gates nothing. Both lines must exist.
for suite_name in orphan-process-reaper orphan-process-reaper-mutation; do
  cases=$((cases + 1))
  if grep -qE "^  run_suite .scripts/[^ ]*. bash scripts/${suite_name}[.]test[.]sh$" "$TA"; then
    pass "AC33 scripts/${suite_name}.test.sh is registered in the runner"
  else
    fail "AC33 scripts/${suite_name}.test.sh is NOT registered — it would gate nothing"
  fi
done

# AC34 — the preamble. Four separate assertions, because each covers a distinct
# way the probe stops being a probe.
cases=$((cases + 1))
if grep -qE '^    timeout 10 bash scripts/orphan-process-reaper\.sh report' "$TA"; then
  pass "AC34 the preamble invokes the REPORT verb under timeout 10"
else
  fail "AC34 the preamble call is not 'timeout 10 … report'"
fi
cases=$((cases + 1))
# `|| _orphan_rc=$?` rather than `|| true`: the caller must be able to SAY that
# the detector did not run. `|| true` alone makes that indistinguishable from
# "it ran and found nothing", and the second reads as an all-clear.
if grep -qE '\|\| _orphan_rc=\$\?' "$TA" && grep -qE "printf 'ORPHAN_SCAN valid=0 reason=rc" "$TA"; then
  pass "AC34/M36 the caller captures rc and emits ORPHAN_SCAN valid=0 itself on a non-zero exit"
else
  fail "AC34/M36 a non-zero rc from the preamble would be swallowed — 'did not run' would read as 'found nothing'"
fi
cases=$((cases + 1))
# AC28h — `timeout` runs its child in its own process group, so the probe
# computing its own pgid would get timeout's pid rather than the runner's. The
# synthesized-procfs arms structurally cannot observe this: they pin
# TC_SELF_PID, so the pgid computed at the REAL call site is never seen.
if grep -qE 'ORPHAN_REAPER_EXCLUDE_PGID=' "$TA"; then
  pass "AC28h the caller passes the exclusion pgid EXPLICITLY rather than letting it be inferred"
else
  fail "AC28h without an explicit exclusion pgid, timeout's own group is excluded instead of the runner's"
fi
cases=$((cases + 1))
# Nothing may invoke `reap` automatically. This is the whole trigger design: the
# detector has never been observed firing on a real orphan.
if [[ "$(grep -cE 'orphan-process-reaper\.sh reap' "$TA" || true)" == "0" ]]; then
  pass "AC34 nothing in the runner invokes reap automatically"
else
  fail "AC34 the runner invokes reap — the first strike must be a reader's judgment"
fi

# ===========================================================================
# Vacuity floors
# ===========================================================================

# ABSOLUTE assertion floor, hand-ratcheted to the measured case count, in the
# comparison shape scripts/guard-vacuity-floor.test.sh recognises. A floor
# written any other way is not covered, not deferred, and not reported as
# unclassified — it is simply ABSENT from that gate's population.
#
# Two constraints on HOW it is written, both learned from that gate rejecting an
# earlier draft of this block:
#
#   * The threshold must be a LITERAL on the line immediately above. That gate
#     builds a mutant from this block plus the preceding plain assignments and
#     zeroes the counters; a threshold computed conditionally is unbound in the
#     mutant, so the floor scores as "not constructible" rather than as one that
#     fires.
#   * Nothing above may spell the comparison out. Prose describing the shape is
#     matched by the same scan that finds the real one, and the slice taken from
#     a comment exits 0 — reported as a floor that does not fire.
#
# The value is the SKIP-LIVE count, which is the lower of the two modes and
# therefore valid in both. Full runs carry 8 more assertions (the live-procfs
# arm and the seven end-to-end hops); those eight are not floored here, and that
# slack is the price of one threshold that is correct under both modes.
MIN_CASES=132
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '\n[FATAL] assertion floor: %d assertions ran, expected at least %d.\n' \
    "$cases" "$MIN_CASES" >&2
  printf '  A suite whose success condition is `fails == 0` exits 0 on "0 passed, 0 failed".\n' >&2
  echo "=== orphan-process-reaper: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# Accounting conservation. The floor above catches "no assertions RAN"; it
# cannot catch "assertions ran and their verdicts were discarded", because
# `cases` keeps its full value when fail() is a no-op.
if [[ $((pass_n + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass_n+fails (%d) != cases (%d).\n' \
    "$((pass_n + fails))" "$cases" >&2
  if [[ $((pass_n + fails)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug: add the increment at that call site.\n' >&2
  fi
  echo "=== orphan-process-reaper: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# ASSERTION-HELPER POSITIVE CONTROL (H1b). Conservation and the absolute floor
# both survive `fail()` being rewritten to increment pass_n: pass_n +1, fails
# +0, cases +1 — so neither can see it, and the suite exits 0. This is defect
# #7 of the 2026-08-14 learning verbatim. The remedy that learning prescribes:
# call both helpers once and verify BOTH counters moved.
_p0="$pass_n"; _f0="$fails"
pass "helper positive control (this assertion is expected)"
fail "helper positive control (this FAIL is expected and is subtracted below)"
if [[ "$pass_n" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf '\n[FATAL] assertion helpers are neutered: pass_n %d->%d, fails %d->%d.\n' \
    "$_p0" "$pass_n" "$_f0" "$fails" >&2
  exit 1
fi
# Subtract the control's own effects so it does not colour the real verdict.
pass_n=$((pass_n - 1)); fails=$((fails - 1))

echo "=== orphan-process-reaper: $pass_n passed, $fails failed ($cases assertions) ==="
[[ "$fails" -eq 0 ]] || exit 1
