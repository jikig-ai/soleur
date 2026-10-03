#!/usr/bin/env bash
# audit-suite-reads.test.sh — Guard 1 of the always-on read recorder (#9307, PR-B / B1).
#
# PROPERTY. scripts/audit-suite-reads.sh never reports a suite `demotable` from an incomplete or
# unstable recording (queue overflow, failed watch, repeat disagreement, sentinel damage), from a
# non-zero exit, from a flagged probe, or from reads outside its cover.
#
# ASSEMBLY. Every verdict flows through the single `verdict()` function. This suite drives it two
# ways: (A) the `verdict` subcommand over SYNTHESIZED event streams (replay), and (B) the REAL reader
# (scripts/lib/inotify-open-recorder.py) and the REAL `record` path over fixture repositories whose
# fake runner emits SUITE_COMMAND / AFFECTED_SELECTED records. Every RED row asserts the exit code AND
# a message substring, so a crash cannot read as RED. Rows follow the Guard 1 mutation matrix in
# knowledge-base/project/plans/2026-10-02-chore-affected-gate-reprice-recorder-runner-leaf-plan.md
# (rows 1, 1b, 2..17). The inotify arms need only python3 + ctypes (no inotify-tools), so CI runs them.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail (grep a file or use [[ == ]]);
# capture rc on its own line; verdict helpers are defined AFTER the one subshell that sources the
# script under test; scratch is mktemp-based with an owning EXIT trap. Row 1b SKIPs (counted, loud)
# only when python3 ctypes inotify is unavailable, and FAILS under CI.

# shellcheck disable=SC2016  # fixture suite bodies and awk-free literals are single-quoted on purpose
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${AUDIT_SUITE_READS_SCRIPT:-$REPO_ROOT/scripts/audit-suite-reads.sh}"
READER="$REPO_ROOT/scripts/lib/inotify-open-recorder.py"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t audit-suite-reads.XXXXXXXX)" || exit 2

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
assert_fixture_dir "$TESTROOT"
BG_PIDS=""
# shellcheck disable=SC2329  # invoked through the EXIT trap
cleanup() {
  local p
  for p in $BG_PIDS; do kill -CONT "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  rm -rf -- "$TESTROOT"
}
trap cleanup EXIT INT TERM HUP

# The one place the script under test is SOURCED: read its disqualifier table (entries "name|regex").
DISQ_ENTRIES="$( (
  # shellcheck source=/dev/null
  source "$SCRIPT" >/dev/null 2>&1 || exit 1
  printf '%s\n' "${DISQ_TABLE[@]}"
) 2>/dev/null)"

# ---- verdict helpers (defined AFTER the sourcing above) --------------------------------------------
PASS=0; FAIL=0; cases=0; SKIPPED=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

# Instrument self-test: both verdict helpers must move their counters.
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

ok_if() { # ok_if <name> <rc-of-condition>
  cases=$((cases + 1))
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1"; fi
}
skip_or_fail() { # a counted skip locally, a failure under CI
  if [[ -n "${CI:-}" ]]; then
    cases=$((cases + 1)); fail "$1 (cannot be skipped under CI)"
  else
    SKIPPED=$((SKIPPED + 1)); echo "  [SKIP] $1"
  fi
}

have_python_inotify() {
  python3 -c 'import ctypes; ctypes.CDLL(None).inotify_init1' >/dev/null 2>&1
}

row_of() { # row_of <table-file> <label> -> the AUDIT_READS row for that label
  awk -F'\t' -v l="label=$2" '$1 == "AUDIT_READS" && $2 == l { print; exit }' "$1"
}

# expect_row <name> <want-rc> <label> <want-verdict> <needle-in-row>
expect_row() {
  local name=$1 wrc=$2 label=$3 wv=$4 needle=$5 row bad=""
  row="$(row_of "$OUT" "$label")"
  [[ "$RC" == "$wrc" ]] || bad="$bad rc=$RC(want $wrc)"
  [[ "$row" == *$'\t'"verdict=$wv"$'\t'* ]] || bad="$bad verdict-not-$wv"
  [[ "$row" == *"$needle"* ]] || bad="$bad missing[$needle]"
  cases=$((cases + 1))
  if [[ -z "$bad" ]]; then pass "$name"; else fail "$name:$bad :: row=[$row]"; fi
}
expect_err() { # expect_err <name> <want-rc> <stderr-needle>
  local bad=""
  [[ "$RC" == "$2" ]] || bad="$bad rc=$RC(want $2)"
  [[ "$(cat "$ERR")" == *"$3"* ]] || bad="$bad stderr-missing[$3]"
  cases=$((cases + 1))
  if [[ -z "$bad" ]]; then pass "$1"; else fail "$1:$bad :: $(head -c 300 "$ERR")"; fi
}

# ---- replay builders ---------------------------------------------------------------------------------
NONCE="n0nce$$x"
FAKE_REV="0123456789abcdef0123456789abcdef01234567"
RUNN=0; WIN=0
new_run() {
  RUNN=$((RUNN + 1)); RUN="$TESTROOT/run.$RUNN"
  mkdir -p "$RUN/root/data" "$RUN/root/.audit-sentinels"
  : > "$RUN/events"; printf 'ready\n' > "$RUN/reader.err"
  printf 'NONCE\t%s\nREV\t%s\n' "$NONCE" "$FAKE_REV" > "$RUN/meta"
  WIN=0
}
mksuite() { # mksuite <relpath> <line>...
  local f="$RUN/root/$1"; shift
  mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"
}
# emit_win <label> <rep> <rc> <flag> <cover> <files> [event]...   event: path | D:path | C:path | Q | RAW:line
emit_win() {
  local label=$1 rep=$2 rc=$3 flag=$4 cover=$5 files=$6 e
  shift 6
  WIN=$((WIN + 1))
  printf 'W\t%s\t%s\t%s\t%s\t%s\t0.50\t%s\t%s\n' "$WIN" "$label" "$rep" "$rc" "$flag" "$cover" "$files" >> "$RUN/meta"
  printf 'O\t.audit-sentinels/%s-start-%s\n' "$NONCE" "$WIN" >> "$RUN/events"
  for e in "$@"; do
    case "$e" in
      D:*) printf 'D\t%s\n' "${e#D:}" ;;
      C:*) printf 'C\t%s\n' "${e#C:}" ;;
      RAW:*) printf '%s\n' "${e#RAW:}" ;;
      Q) printf 'Q\n' ;;
      *) printf 'O\t%s\n' "$e" ;;
    esac >> "$RUN/events"
  done
  printf 'O\t.audit-sentinels/%s-end-%s\n' "$NONCE" "$WIN" >> "$RUN/events"
}
# pair <slug> <cover> <event>...  : two agreeing recordings of suite <slug>.sh (rc 0)
pair() {
  local slug=$1 cover=$2; shift 2
  emit_win "$slug" 1 0 - "$cover" "$slug.sh" "$@"
  emit_win "$slug" 2 0 - "$cover" "$slug.sh" "$@"
}
run_verdict() {
  OUT="$RUN/out"; ERR="$RUN/err"
  bash "$SCRIPT" verdict --events "$RUN/events" --reader-err "$RUN/reader.err" --meta "$RUN/meta" \
    --root "$RUN/root" ${1+"$@"} >"$OUT" 2>"$ERR"
  RC=$?
}

echo "== A. replay: verdict() over synthesized streams =="

# Row 0 (positive control): a compliant suite is demotable; the revision is stamped into the row.
new_run
mksuite good.sh 'cat data/a.txt'
pair good 'good.sh|data/a.txt' good.sh data/a.txt
run_verdict
expect_row "row 0: compliant suite is demotable" 0 good demotable "rev=$FAKE_REV"
expect_row "row 0: mode stamped" 0 good demotable "mode=demote"

# Row 1: IN_Q_OVERFLOW inside a suite window; and one only in the gap that follows a window.
new_run
mksuite ovin.sh 'cat data/a.txt'; mksuite ovgap.sh 'cat data/a.txt'; mksuite after.sh 'cat data/a.txt'
emit_win ovin 1 0 - 'ovin.sh|data/a.txt' ovin.sh ovin.sh data/a.txt Q
emit_win ovin 2 0 - 'ovin.sh|data/a.txt' ovin.sh ovin.sh data/a.txt
pair ovgap 'ovgap.sh|data/a.txt' ovgap.sh data/a.txt
printf 'Q\n' >> "$RUN/events"          # lands in the gap after ovgap's second window
pair after 'after.sh|data/a.txt' after.sh data/a.txt
run_verdict
expect_row "row 1: overflow inside window -> unreliable (rc 3)" 3 ovin unreliable "reason=q_overflow"
expect_row "row 1: overflow only in the following gap -> unreliable" 3 ovgap unreliable "reason=q_overflow_gap"
expect_row "row 1: the suite AFTER the gap is unaffected (table still written)" 3 after demotable "reason=ok"

# Row 2: `Failed to watch` on reader stderr -> every suite unreliable. Also: reader never became ready.
new_run
mksuite g1.sh 'cat data/a.txt'; mksuite g2.sh 'cat data/a.txt'
pair g1 'g1.sh|data/a.txt' g1.sh data/a.txt
pair g2 'g2.sh|data/a.txt' g2.sh data/a.txt
printf 'ready\nFailed to watch /x/y\n' > "$RUN/reader.err"
run_verdict
expect_row "row 2: failed watch -> first suite unreliable" 3 g1 unreliable "reason=watch_failed"
expect_row "row 2: failed watch -> second suite unreliable" 3 g2 unreliable "reason=watch_failed"
printf 'nothing\n' > "$RUN/reader.err"
run_verdict
expect_row "row 2b: reader never printed ready -> unreliable" 3 g1 unreliable "reason=reader_not_ready"

# Row 3: a file test outside the cover (the open-event stream cannot see it) -> disqualified.
new_run
mksuite probe.sh 'cat data/a.txt' '[[ -e some/missing/path ]] && echo there'
pair probe 'probe.sh|data/a.txt' probe.sh data/a.txt
run_verdict
expect_row "row 3: [[ -e missing ]] outside the cover -> disqualified" 0 probe disqualified "probe:some/missing/path"
expect_row "row 3: reason is probe" 0 probe disqualified "reason=probe"

# Row 4: every suite is scanned, not just the first one.
new_run
mksuite first.sh 'cat data/a.txt'; mksuite second.sh 'cat data/a.txt' 'test -f nope/x'
mksuite third.sh 'cat data/a.txt' 'ls elsewhere/dir'
pair first 'first.sh|data/a.txt' first.sh data/a.txt
pair second 'second.sh|data/a.txt' second.sh data/a.txt
pair third 'third.sh|data/a.txt' third.sh data/a.txt
run_verdict
expect_row "row 4: compliant first suite stays demotable" 0 first demotable "reason=ok"
expect_row "row 4: probing second suite is disqualified" 0 second disqualified "probe:nope/x"
expect_row "row 4: a later ls probe is disqualified too" 0 third disqualified "probe:elsewhere/dir"

# Row 5: zero suites enumerated, and (separately) zero windows -> exit 4, distinct messages, not usage 2.
new_run
run_verdict
expect_err "row 5: zero suites enumerated -> exit 4" 4 "zero suites enumerated"
new_run
mksuite z.sh 'true'
printf 'W\t1\tz\t1\t0\t-\t0.5\tz.sh\tz.sh\n' >> "$RUN/meta"
run_verdict
expect_err "row 5: zero windows recorded -> exit 4" 4 "zero windows"
bash "$SCRIPT" verdict >/dev/null 2>"$TESTROOT/usage.err"; RC=$?; ERR="$TESTROOT/usage.err"
expect_err "row 5: usage error is exit 2 (not 4)" 2 "usage"

# Row 6: one read outside the cover and nothing else -> exactly uncovered, path listed.
new_run
mksuite unc.sh 'cat data/a.txt data/other.txt'
pair unc 'unc.sh|data/a.txt' unc.sh data/a.txt data/other.txt
run_verdict
expect_row "row 6: read outside cover -> uncovered" 0 unc uncovered "data/other.txt"
expect_row "row 6: reason is reads-outside-cover" 0 unc uncovered "reason=reads-outside-cover"

# Row 7: non-zero exit and exit 124 -> unreliable.
new_run
mksuite rcn.sh 'exit 3'; mksuite rct.sh 'sleep 999'
emit_win rcn 1 3 - 'rcn.sh' rcn.sh rcn.sh
emit_win rct 1 124 - 'rct.sh' rct.sh rct.sh
run_verdict
expect_row "row 7: rc 3 -> unreliable rc" 3 rcn unreliable "reason=rc"
expect_row "row 7: rc 124 -> unreliable timeout" 3 rct unreliable "reason=timeout"

# Row 8: two recordings of one suite disagree on the opened set (the extra read is covered).
new_run
mksuite flaky.sh 'cat data/a.txt'
emit_win flaky 1 0 - 'flaky.sh|data/a.txt|data/b.txt' flaky.sh flaky.sh data/a.txt
emit_win flaky 2 0 - 'flaky.sh|data/a.txt|data/b.txt' flaky.sh flaky.sh data/a.txt data/b.txt
run_verdict
expect_row "row 8: repeat disagreement -> unreliable" 3 flaky unreliable "reason=repeat_disagree"

# Row 9: one fixture per entry of the carried-disqualifier table.
declare_sample() { # declare_sample <entry-name> -> a suite line the entry's regex must match
  case "$1" in
    git-diff) echo 'git diff --stat' ;;           git-log) echo 'git log -1' ;;
    git-show) echo 'git show HEAD' ;;             git-rev-list) echo 'git rev-list HEAD' ;;
    git-merge-base) echo 'git merge-base a b' ;;  git-status) echo 'git status --short' ;;
    git-ls-files) echo 'git ls-files' ;;          git-ls-tree) echo 'git ls-tree HEAD' ;;
    origin-main) echo 'echo origin/main' ;;       changed-flag) echo 'run --changed' ;;
    base-flag) echo 'run --base HEAD' ;;          net-curl) echo 'curl -s https://x.invalid' ;;
    net-gh) echo 'gh api repos/x' ;;              net-doppler) echo 'doppler run -- x' ;;
    net-ssh) echo 'ssh host true' ;;               clock-date) echo 'now=$(date +%s)' ;;
    clock-epoch) echo 'echo $EPOCHSECONDS' ;;
    *) echo "" ;;
  esac
}
n_entries=0; n_missing_sample=0
new_run
declare -a ENTRY_NAMES
ENTRY_NAMES=()
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="${entry%%|*}"
  sample="$(declare_sample "$name")"
  if [[ -z "$sample" ]]; then n_missing_sample=$((n_missing_sample + 1)); echo "  no fixture sample for table entry [$name]" >&2; continue; fi
  n_entries=$((n_entries + 1)); ENTRY_NAMES[${#ENTRY_NAMES[@]}]="$name"
  mksuite "rx_$name.sh" 'cat data/a.txt' "$sample"
  pair "rx_$name" "rx_$name.sh|data/a.txt" "rx_$name.sh" data/a.txt
done <<EOF
$DISQ_ENTRIES
EOF
run_verdict
cases=$((cases + 1))
if (( n_entries >= 8 )) && (( n_missing_sample == 0 )); then pass "row 9: table has $n_entries entries (floor 8), every entry has a fixture sample"
else fail "row 9: table floor/sample coverage (entries=$n_entries missing-sample=$n_missing_sample)"; fi
for name in ${ENTRY_NAMES[@]+"${ENTRY_NAMES[@]}"}; do
  expect_row "row 9: [$name] -> disqualified" 0 "rx_$name" disqualified "regex:$name"
done
# deleting a table entry reds its own fixture (scratch copy of the script, landed check by md5 + line count)
mkdir -p "$TESTROOT/mut/scripts/lib"
cp "$READER" "$TESTROOT/mut/scripts/lib/inotify-open-recorder.py"
for name in ${ENTRY_NAMES[@]+"${ENTRY_NAMES[@]}"}; do
  M="$TESTROOT/mut/scripts/audit-suite-reads.sh"
  grep -vF -- "  \"$name|" "$SCRIPT" > "$M"
  before=$(wc -l < "$SCRIPT"); after=$(wc -l < "$M")
  lm=0; [[ $((before - after)) == 1 ]] || lm=1
  [[ "$(md5sum < "$SCRIPT")" != "$(md5sum < "$M")" ]] || lm=1
  ok_if "row 9: deleting [$name] landed (exactly one line, md5 differs)" "$lm"
  OUT="$RUN/out.mut"; ERR="$RUN/err.mut"
  bash "$M" verdict --events "$RUN/events" --reader-err "$RUN/reader.err" --meta "$RUN/meta" --root "$RUN/root" >"$OUT" 2>"$ERR"; RC=$?
  row="$(row_of "$OUT" "rx_$name")"
  mm=0; [[ "$row" != *"regex:$name"* ]] || mm=1
  ok_if "row 9: with [$name] deleted its fixture no longer flags regex:$name" "$mm"
done

# Row 10: size caps, each boundary pair (exactly at the cap passes; one over is disqualified).
build_dirs_run() { # <n data dirs> : reads suite.sh + n distinct d<i>/f files, cover lists them as files
  local n=$1 i cover="d.sh" ev="d.sh"
  new_run; mksuite d.sh 'true'
  for ((i = 1; i <= n; i++)); do cover="$cover|d$i/sub/f"; ev="$ev d$i/sub/f"; done
  # shellcheck disable=SC2086
  pair d "$cover" $ev
}
build_dirs_run 7; run_verdict
expect_row "row 10: 8 second-level dirs (the cap) -> demotable" 0 d demotable "dirs=8"
build_dirs_run 8; run_verdict
expect_row "row 10: 9 second-level dirs -> disqualified broad" 0 d disqualified "reason=broad"
build_files_run() { # <n files> in one cover dir
  local n=$1 i ev="" ; local -a evs
  new_run; mksuite f.sh 'true'
  evs=(f.sh)
  for ((i = 1; i <= n; i++)); do evs[${#evs[@]}]="big/sub/f$i"; done
  pair f 'f.sh|big/' "${evs[@]}"
}
build_files_run 699; run_verdict
expect_row "row 10: 700 files (the cap) -> demotable" 0 f demotable "files=700"
build_files_run 700; run_verdict
expect_row "row 10: 701 files -> disqualified broad" 0 f disqualified "reason=broad"
build_cover_run() { # <n cover edges>
  local n=$1 i cover="c.sh"
  new_run; mksuite c.sh 'true'
  for ((i = 2; i <= n; i++)); do cover="$cover|unread$i.txt"; done
  pair c "$cover" c.sh
}
build_cover_run 14; run_verdict
expect_row "row 10: cover of 14 edges (the cap) -> demotable" 0 c demotable "cover=14"
build_cover_run 15; run_verdict
expect_row "row 10: cover of 15 edges -> disqualified wide-cover" 0 c disqualified "reason=wide-cover"

# Row 11: the same oversized reads/cover in check mode apply no cap; vocabulary is covered/uncovered/unreliable.
build_cover_run 15; run_verdict --mode check
expect_row "row 11: check mode, 15-edge cover -> covered (no cap)" 0 c covered "reason=ok"
build_files_run 700; run_verdict --mode check
expect_row "row 11: check mode, 701 files -> covered (no cap)" 0 f covered "files=701"
build_dirs_run 8; run_verdict --mode check
expect_row "row 11: check mode, 9 dirs -> covered (no cap)" 0 d covered "dirs=9"
cases=$((cases + 1))
if [[ "$(cat "$OUT")" != *demotable* ]] && [[ "$(cat "$OUT")" != *disqualified* ]]; then pass "row 11: check mode never says demotable/disqualified"
else fail "row 11: check-mode output holds demotable/disqualified"; fi
new_run; mksuite k.sh 'git diff' 'cat data/a.txt'; pair k 'k.sh|data/a.txt' k.sh data/a.txt data/zzz
run_verdict --mode check
expect_row "row 11: check mode, read outside cover -> uncovered" 0 k uncovered "data/zzz"
expect_row "row 11: check mode reports the carried disqualifier as info only" 0 k uncovered "regex:git-diff"
new_run; mksuite k.sh 'cat data/a.txt'; emit_win k 1 0 - 'k.sh|data/a.txt' k.sh k.sh data/a.txt Q
run_verdict --mode check
expect_row "row 11: check mode, overflow -> unreliable" 3 k unreliable "reason=q_overflow"

# Row 12 (replay half): a window the recorder refused for load carries the flag.
new_run; mksuite l.sh 'true'
printf 'W\t1\tl\t1\t-\tload_refused\t99.00\tl.sh\tl.sh\n' >> "$RUN/meta"
run_verdict
expect_row "row 12: load_refused flag -> unreliable" 3 l unreliable "reason=load_refused"

# Row 13: a directory created during the suite -> disqualified.
new_run; mksuite mk.sh 'mkdir -p newdir' 'cat data/a.txt'
pair mk 'mk.sh|data/a.txt' mk.sh data/a.txt C:newdir
run_verdict
expect_row "row 13: directory created mid-suite -> disqualified" 0 mk disqualified "reason=created-dir"

# Row 14: back-to-back windows keep their own events; sentinel damage makes the row unreliable.
new_run; mksuite wa.sh 'cat data/a.txt'; mksuite wb.sh 'cat data/b.txt'
pair wa 'wa.sh|data/a.txt' wa.sh data/a.txt
pair wb 'wb.sh|data/b.txt' wb.sh data/b.txt
run_verdict
expect_row "row 14: adjacent window A keeps only its own events" 0 wa demotable "reason=ok"
expect_row "row 14: adjacent window B keeps only its own events" 0 wb demotable "reason=ok"
new_run; mksuite sm.sh 'cat data/a.txt'
emit_win sm 1 0 - 'sm.sh|data/a.txt' sm.sh sm.sh data/a.txt
# drop the end sentinel of window 1
grep -vF -- "-end-1" "$RUN/events" > "$RUN/events.cut"; mv "$RUN/events.cut" "$RUN/events"
run_verdict
expect_row "row 14: missing end sentinel -> unreliable" 3 sm unreliable "reason=sentinel"
new_run; mksuite sd.sh 'cat data/a.txt'
emit_win sd 1 0 - 'sd.sh|data/a.txt' sd.sh sd.sh data/a.txt
printf 'O\t.audit-sentinels/%s-start-1\n' "$NONCE" >> "$RUN/events"   # duplicated start sentinel
run_verdict
expect_row "row 14: duplicated sentinel -> unreliable" 3 sd unreliable "reason=sentinel"
new_run; mksuite sw.sh 'cat data/a.txt'
emit_win sw 1 0 - 'sw.sh|data/a.txt' sw.sh sw.sh data/a.txt "RAW:O"$'\t'".audit-sentinels/${NONCE}-start-9"
run_verdict
expect_row "row 14: a stray sentinel inside a window -> unreliable" 3 sw unreliable "reason=sentinel"
new_run; mksuite mf.sh 'cat data/a.txt'
emit_win mf 1 0 - 'mf.sh|data/a.txt' mf.sh mf.sh data/a.txt "RAW:garbage-line"
run_verdict
expect_row "row 14b: malformed event line -> unreliable" 3 mf unreliable "reason=malformed"

# Row 17 (must-PASS, non-canonical): reads are a strict subset of a differently ordered cover; the only
# file tests are on that cover.
new_run
mksuite sub.sh 'cat data/z.txt data/a.txt' '[[ -f data/a.txt ]] && [ -d data ]'
pair sub 'data/unused.txt|data/a.txt|sub.sh|data/z.txt' data/z.txt data/a.txt sub.sh
run_verdict
expect_row "row 17: strict-subset reads, reordered cover, probes on the cover -> demotable" 0 sub demotable "reason=ok"

echo "== B. real reader and record path over fixture repositories =="

HAVE_INOTIFY=0; have_python_inotify && HAVE_INOTIFY=1
NETNS_REAL=0
if unshare -rn true >/dev/null 2>&1 || bwrap --unshare-net --dev-bind / / true >/dev/null 2>&1; then
  NETNS_REAL=1
else
  export AUDIT_READS_ALLOW_NO_NETNS=1
  echo "  (no usable network namespace tool here: record runs with the test-only AUDIT_READS_ALLOW_NO_NETNS seam)"
fi
printf '0.10 0.10 0.10 1/1 1\n' > "$TESTROOT/loadavg.quiet"
printf '99.00 99.00 99.00 1/1 1\n' > "$TESTROOT/loadavg.busy"
mkdir -p "$TESTROOT/rtmp" "$TESTROOT/home"

fx_git() { # fx_git <dir> <git args...> : hermetic git in a fixture
  local d=$1; shift
  assert_fixture_dir "$d"
  env -i HOME="$TESTROOT/home" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -C "$d" -c user.name=fx -c user.email=fx@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
FXN=0
mkfx() { # mkfx -> FX (a git repo with a fake runner)
  FXN=$((FXN + 1)); FX="$TESTROOT/fx.$FXN"
  mkdir -p "$FX/scripts" "$FX/suites" "$FX/data"
  assert_fixture_dir "$FX"
  fx_git "$FX" init -q
  : > "$FX/scripts/fake-enum.tsv"; : > "$FX/scripts/fake-sel.tsv"
  cat > "$FX/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --enumerate-commands) cat "$d/fake-enum.tsv" ;;
  --print-selection) cat "$d/fake-sel.tsv" ;;
  *) exit 64 ;;
esac
RUNNER
  echo "fixture a" > "$FX/data/a.txt"; echo "fixture b" > "$FX/data/b.txt"; echo "fixture c" > "$FX/data/c.txt"
}
fx_suite() { # fx_suite <slug> <cover '|'-joined or -> <body line>... : suite file + enum + selection rows
  local slug=$1 cover=$2; shift 2
  printf '#!/usr/bin/env bash\n' > "$FX/suites/$slug.sh"
  printf '%s\n' "$@" >> "$FX/suites/$slug.sh"
  printf 'SUITE_COMMAND\t%s\tbash\tsuites/%s.sh\n' "$slug" "$slug" >> "$FX/scripts/fake-enum.tsv"
  printf 'AFFECTED_SELECTED\t%s\t0\tedge:declared\t%s\n' "$slug" "$cover" >> "$FX/scripts/fake-sel.tsv"
}
fx_commit() {
  fx_git "$FX" add -A
  fx_git "$FX" commit -q -m fixture
  FX_SHA="$(fx_git "$FX" rev-parse HEAD)"
}
RECN=0
run_record() { # run_record <extra record args...> : env-controlled, outputs under $TESTROOT/rec.N
  RECN=$((RECN + 1)); REC="$TESTROOT/rec.$RECN"; mkdir -p "$REC"
  OUT="$REC/stdout"; ERR="$REC/stderr"
  env TMPDIR="$TESTROOT/rtmp" SECRET_TOKEN=leak AUDIT_READS_LOADAVG_FILE="${LOADFILE:-$TESTROOT/loadavg.quiet}" \
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$REC/out" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}

if (( HAVE_INOTIFY == 0 )); then
  skip_or_fail "section B (real reader + record rows): python3 ctypes inotify unavailable"
else
  # ---- the main fixture: one record run drives rows 1/3/4/6/7/8/13/14/17 live -----------------------
  mkfx
  NETCHECK='true'
  (( NETNS_REAL == 1 )) && NETCHECK='[[ "$(grep -c : /proc/net/dev)" -le 1 ]] || exit 14'
  fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null' '[[ -f data/a.txt ]] || exit 9'
  fx_suite probe '^data/a.txt' 'cat data/a.txt >/dev/null' '[[ -e some/missing/path ]] || true'
  fx_suite uncov '^data/a.txt' 'cat data/a.txt data/b.txt >/dev/null'
  fx_suite exit3 '' 'exit 3'
  fx_suite slow '' 'sleep 30'
  fx_suite flaky '^data/a.txt|^data/b.txt' 'n=0; [ -f "$HOME/count" ] && n=$(cat "$HOME/count")' 'echo $((n + 1)) > "$HOME/count"' \
    'if [ $((n % 2)) -eq 0 ]; then cat data/a.txt; else cat data/b.txt; fi >/dev/null'
  fx_suite mkdirs '^data/a.txt' 'mkdir "newdir.$$"' 'cat data/a.txt >/dev/null'
  fx_suite junk '^data/a.txt' 'echo x > junk.txt'
  fx_suite sub1 '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_suite sub2 '^data/b.txt' 'cat data/b.txt >/dev/null'
  fx_suite envck '' '[[ -z "${SECRET_TOKEN:-}" ]] || exit 11' 'case "$HOME" in */scratch/home) ;; *) exit 12 ;; esac' \
    'case "$PATH" in *:*) exit 13 ;; esac' "$NETCHECK"
  fx_commit
  run_record --cover-from-selection --timeout 4
  RC_LIVE_MAIN=$RC
  cases=$((cases + 1))
  if [[ "$RC_LIVE_MAIN" == 3 ]]; then pass "live: table written and exit 3 because rows are unreliable"; else fail "live: expected exit 3, got $RC_LIVE_MAIN :: $(head -c 400 "$ERR")"; fi
  expect_row "live row 0: compliant suite is demotable with the revision stamped" 3 okay demotable "rev=$FX_SHA"
  expect_row "live row 3/4: probing suite (after a compliant one) -> disqualified" 3 probe disqualified "probe:some/missing/path"
  expect_row "live row 6: read outside the cover -> uncovered, path listed" 3 uncov uncovered "data/b.txt"
  expect_row "live row 7: non-zero exit -> unreliable rc" 3 exit3 unreliable "reason=rc"
  expect_row "live row 7: cap hit -> unreliable timeout (rc 124)" 3 slow unreliable "reason=timeout"
  expect_row "live row 8: two recordings disagree -> unreliable" 3 flaky unreliable "reason=repeat_disagree"
  expect_row "live row 13: directory created under the checkout -> disqualified" 3 mkdirs disqualified "reason=created-dir"
  expect_row "live: a suite that dirties the checkout -> unreliable contaminated" 3 junk unreliable "reason=contaminated"
  expect_row "live row 14: back-to-back suite 1 keeps only its own reads" 3 sub1 demotable "reason=ok"
  expect_row "live row 14: back-to-back suite 2 keeps only its own reads" 3 sub2 demotable "reason=ok"
  expect_row "live: env -i, scratch PATH/HOME, no inherited secret, network-less -> suite exits 0" 3 envck demotable "rc=0"
  cases=$((cases + 1))
  if [[ -z "$(ls -d "$TESTROOT"/rtmp/soleur-audit-reads.* 2>/dev/null)" ]]; then pass "live: checkout directory removed on exit"; else fail "live: leftover checkout under rtmp"; fi

  # ---- row 17 live (must-PASS) + row 15 (cover comes from the audited checkout) ------------------------
  mkfx
  fx_suite sub '^data/c.txt|^data/a.txt|^data/unused.txt' 'cat data/a.txt data/c.txt >/dev/null' '[[ -f data/c.txt ]] && [ -d data ]'
  fx_commit
  printf 'AFFECTED_SELECTED\tsub\t0\tedge:declared\t^zzz-live-tree-only\n' > "$FX/scripts/fake-sel.tsv"   # dirty, uncommitted
  run_record --cover-from-selection
  expect_row "live row 17: strict-subset reads of a reordered cover -> demotable" 0 sub demotable "files=3"
  expect_row "live row 15: cover came from the audited checkout (live-tree mutation ignored)" 0 sub demotable "reason=ok"

  # ---- row 5 live: zero suites -> exit 4, distinct message ------------------------------------------
  mkfx; fx_commit
  run_record --cover-from-selection
  expect_err "live row 5: zero suites enumerated -> exit 4" 4 "zero suites enumerated"
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  run_record --cover-from-selection --only no-such-label
  expect_err "live: --only naming nothing enumerates zero suites -> exit 4" 4 "zero suites enumerated"

  # ---- row 12 live: load above --max-load -> refusal, rows unreliable ----------------------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  LOADFILE="$TESTROOT/loadavg.busy" run_record --cover-from-selection --max-load 4.0
  expect_row "live row 12: load above --max-load -> refusal, row unreliable" 3 okay unreliable "reason=load_refused"
  LOADFILE="$TESTROOT/loadavg.busy" run_record --cover-from-selection --max-load 200
  expect_row "live row 12: the same load under a higher --max-load is not refused" 0 okay demotable "load=99.00"

  # ---- usage / refusal exits ------------------------------------------------------------------------------
  for argset in "" "frobnicate" "record --only ../x" "record --mode weird" "record --max-load abc" "verdict --mode weird"; do
    # shellcheck disable=SC2086
    bash "$SCRIPT" $argset >/dev/null 2>"$TESTROOT/u.err"; RC=$?; ERR="$TESTROOT/u.err"
    expect_err "usage: [$argset] -> exit 2" 2 "audit-suite-reads"
  done
  # no network-less namespace tool on PATH -> refuse to start (exit 2, named message)
  NB="$TESTROOT/nonet-bin"; mkdir -p "$NB"
  for t in bash git python3 uname mktemp rm grep awk sed sort cat env dirname basename tr cut wc head tail find mkdir tar ls id cmp od tee sleep; do
    p="$(command -v "$t" 2>/dev/null)" && [[ -n "$p" && -x "$p" ]] && ln -sf "$p" "$NB/$t"
  done
  env -i PATH="$NB" HOME="$TESTROOT/home" TMPDIR="$TESTROOT/rtmp" "$NB/bash" "$SCRIPT" record --repo "$FX" >"$TESTROOT/nn.out" 2>"$TESTROOT/nn.err"; RC=$?; ERR="$TESTROOT/nn.err"
  expect_err "refusal: neither unshare nor bwrap -> exit 2, named message" 2 "network-less"

  # ---- row 16: remove the verdict call from `record` -> the real-reader arm goes RED --------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  real_arm_green() { # 0 iff the real record path produced a demotable row
    run_record --cover-from-selection
    [[ "$(row_of "$OUT" okay)" == *$'\t'"verdict=demotable"$'\t'* ]] && [[ "$RC" == 0 ]]
  }
  real_arm_green; g=$?
  ok_if "row 16: pristine script - real-reader arm is green (control)" "$g"
  M="$TESTROOT/mut/scripts/audit-suite-reads.sh"
  anchors=$(grep -c 'RECORD-VERDICT-CALL' "$SCRIPT")
  awk '/RECORD-VERDICT-CALL/ { print ": # verdict call removed by the mutation harness"; next } { print }' "$SCRIPT" > "$M"
  lm=0; [[ "$anchors" == 1 ]] || lm=1
  [[ "$(md5sum < "$SCRIPT")" != "$(md5sum < "$M")" ]] || lm=1
  ok_if "row 16: mutation landed (one anchor, md5 differs)" "$lm"
  SAVED_SCRIPT="$SCRIPT"; SCRIPT="$M"
  real_arm_green; g=$?
  SCRIPT="$SAVED_SCRIPT"
  ok_if "row 16: verdict call removed from record -> the real-reader arm goes RED" "$(( g == 0 ))"

  # ---- cleanup on SIGTERM: no leftover checkout, no leftover suite process ----------------------------------
  mkfx; fx_suite hang '' 'sleep 61.717' 'true'; fx_commit
  rm -rf -- "$TESTROOT/rtmp"; mkdir -p "$TESTROOT/rtmp"
  env TMPDIR="$TESTROOT/rtmp" AUDIT_READS_LOADAVG_FILE="$TESTROOT/loadavg.quiet" \
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/term.out" >/dev/null 2>&1 &
  tp=$!; BG_PIDS="$BG_PIDS $tp"
  for _i in $(seq 1 100); do
    if [[ -n "$(ls -d "$TESTROOT"/rtmp/soleur-audit-reads.* 2>/dev/null)" ]] && pgrep -f 'sleep 61.717' >/dev/null 2>&1; then break; fi
    sleep 0.1
  done
  kill -TERM "$tp" 2>/dev/null
  wait "$tp" 2>/dev/null
  sleep 0.3
  left=0; [[ -z "$(ls -d "$TESTROOT"/rtmp/soleur-audit-reads.* 2>/dev/null)" ]] || left=1
  ok_if "cleanup: SIGTERM removes the checkout directory" "$left"
  if command -v pgrep >/dev/null 2>&1; then
    left=0; if pgrep -f 'sleep 61.717' >/dev/null 2>&1; then left=1; pkill -f 'sleep 61.717' 2>/dev/null; fi
    ok_if "cleanup: SIGTERM kills the suite's process group" "$left"
  fi

  # ---- row 1b: the REAL reader, stopped while more events than max_queued_events arrive -------------------
  maxq="$(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null || echo 0)"
  if ! [[ "$maxq" =~ ^[0-9]+$ ]] || (( maxq <= 0 )) || (( maxq > 100000 )); then
    skip_or_fail "row 1b: max_queued_events=$maxq cannot be saturated by a unit test"
  else
    OV="$TESTROOT/ov"; mkdir -p "$OV/root/many" "$OV/root/.audit-sentinels"
    nfiles=$((maxq + 1000))
    python3 - "$OV/root" "$NONCE" "$nfiles" <<'PYEOF'
import os, sys
root, nonce, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
for i in range(n):
    open(os.path.join(root, "many", "f%d" % i), "w").close()
for k in ("start-1", "end-1"):
    open(os.path.join(root, ".audit-sentinels", "%s-%s" % (nonce, k)), "w").close()
PYEOF
    python3 "$READER" "$OV/root" --exclude .git >"$OV/events" 2>"$OV/reader.err" &
    rp=$!; BG_PIDS="$BG_PIDS $rp"
    for _i in $(seq 1 100); do grep -qx ready "$OV/reader.err" 2>/dev/null && break; sleep 0.1; done
    : < "$OV/root/.audit-sentinels/${NONCE}-start-1"
    kill -STOP "$rp"
    python3 - "$OV/root" "$nfiles" <<'PYEOF'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    with open(os.path.join(root, "many", "f%d" % i)) as fh:
        pass
PYEOF
    : < "$OV/root/.audit-sentinels/${NONCE}-end-1"
    kill -CONT "$rp"
    for _i in $(seq 1 100); do grep -qx Q "$OV/events" 2>/dev/null && break; sleep 0.1; done
    sleep 0.3
    kill "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
    grep -qx Q "$OV/events"; g=$?
    ok_if "row 1b: the real reader reports IN_Q_OVERFLOW after $nfiles opens with the queue at $maxq" "$g"
    printf 'NONCE\t%s\nREV\t%s\nW\t1\tovl\t1\t0\t-\t0.5\tmany/\t-\n' "$NONCE" "$FAKE_REV" > "$OV/meta"
    RUN="$OV"; bash "$SCRIPT" verdict --events "$OV/events" --reader-err "$OV/reader.err" --meta "$OV/meta" --root "$OV/root" >"$OV/out" 2>"$OV/err"; RC=$?
    OUT="$OV/out"
    expect_row "row 1b: row for the overflowed live recording is unreliable" 3 ovl unreliable "reason=q_overflow"
  fi
fi

echo "== C. script header and floors =="
hdr="$TESTROOT/header.txt"; awk 'NR > 1 && /^#/ { print } /^[^#]/ && NR > 1 { exit }' "$SCRIPT" > "$hdr"
for phrase in "probes of missing files" "directories created mid-run" "window-boundary" "env -i" "unshare"; do
  g=0; grep -qF -- "$phrase" "$hdr" || g=1
  ok_if "header names the blind spot / mechanism: [$phrase]" "$g"
done
bash "$SCRIPT" --help >"$TESTROOT/help.out" 2>&1; RC=$?
g=0; [[ "$RC" == 0 ]] && grep -qF -- "record" "$TESTROOT/help.out" && grep -qF -- "--cover-from-selection" "$TESTROOT/help.out" || g=1
ok_if "--help exits 0 and names record + --cover-from-selection" "$g"

CASES_FLOOR=75
cases=$((cases + 1))
if (( cases >= CASES_FLOOR )) || (( SKIPPED > 0 && cases >= 55 )); then pass "population floor: $cases rows driven (floor $CASES_FLOOR)"
else fail "population floor: only $cases rows driven (floor $CASES_FLOOR) - rows were deleted?"; fi

echo ""
echo "$PASS passed, $FAIL failed (skipped: $SKIPPED, rows: $cases)"
if (( FAIL > 0 )); then exit 1; fi
exit 0
