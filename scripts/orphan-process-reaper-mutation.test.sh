#!/usr/bin/env bash
# orphan-process-reaper-mutation.test.sh — the mutation battery for
# scripts/orphan-process-reaper.sh (#7537).
#
# WHY THIS EXISTS, in one sentence: the preceding PR in this area shipped nine
# guards that could not be driven red, and a guard that cannot be driven red is
# vacuous. Every check in the detector is mutated out INDIVIDUALLY here, and the
# behavioural suite is required to actually redden for each.
#
# FOUR STRUCTURAL REQUIREMENTS, each closing a named prior defect:
#
#   1. GREEN BASELINE FIRST. The unmutated control runs before any row and must
#      be GREEN; a red control ABORTS the battery rather than scoring rows. A
#      red baseline makes every row pass vacuously (the `fatal: not a git
#      repository` instance), and the hybrid fixture strategy makes an
#      environmental red — a helper that failed to start, an rmdir that raced —
#      entirely plausible here.
#
#   2. PLACEMENT, NOT JUST DIFFERENCE. `cmp`-style "the mutant differs" proves
#      the file changed, never WHERE. The detector repeats the `|| rc=$?`
#      capture idiom at every readlink/stat site, so a file-wide edit can land
#      on a site no fixture exercises while difference still reports "landed".
#      Every row scopes its edit to a named span, asserts the changed line falls
#      INSIDE that span, and asserts EXACTLY ONE line changed.
#
#   3. A row whose edit produced no change is reported VACUOUS and fails the
#      battery — never counted as a pass.
#
#   4. NO MUTATION IS APPLIED INSIDE A COMMAND SUBSTITUTION. A failure inside
#      `$( )` cannot fail the suite, which is how a fully broken harness once
#      left 16 of 18 rows green.
#
# AXIS DISTINCTNESS IS COMPUTED, NOT ASSERTED (AC30). The battery records, per
# mutant, the SET OF FAILING ARM LABELS from the behavioural suite, and asserts
# those sets are pairwise non-identical and non-subset. Two rows that redden the
# same arms are one mutation wearing two names. This replaces a prose claim that
# could only be checked by re-reading a table with something that RUNS.
#
# HARNESS ROWS (H*) edit the SUITE, not the system under test, because a matrix
# that only mutates the SUT cannot see a vacuous harness.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIG="$REPO_ROOT/scripts/orphan-process-reaper.sh"
SUITE="$REPO_ROOT/scripts/orphan-process-reaper.test.sh"

# --- Worker ----------------------------------------------------------------
# Re-entry point: one row, in its own directory. Writes a result file the parent
# reads. Nothing here runs inside a command substitution.
if [[ "${1:-}" == "--worker" ]]; then
  IFS=$'\t' read -r id target span pattern replacement why <<<"$2"
  WORK="$3"
  d="$WORK/$id"
  mkdir -p "$d"
  res="$WORK/res.$id"
  : > "$res"

  src="$ORIG"
  [[ "$target" == "suite" ]] && src="$SUITE"
  # THE MUTANT MUST SIT WHERE ITS OWN PATH RESOLUTION STILL WORKS.
  #
  # Both artifacts resolve siblings from their own location: the detector reads
  # `$(dirname BASH_SOURCE)/lib/test-contention.sh`, and the SUITE computes
  # `REPO_ROOT="$(dirname BASH_SOURCE)/.."` and then reads
  # `$REPO_ROOT/scripts/lib/test-contention.sh` and `$REPO_ROOT/scripts/test-all.sh`.
  # Placing a mutant in a bare temp dir broke the second one: seven assertions
  # failed for ENVIRONMENTAL reasons, so every suite-target row was scored
  # against a RED baseline and a purely cosmetic one-line edit — changing a
  # banner string — was recorded as "reddens the suite: PASS". H1, H1b and H5
  # asserted nothing at all.
  #
  # A synthetic `scripts/` directory with the real siblings symlinked in makes
  # both resolutions succeed, so a red run is attributable to the mutation.
  mkdir -p "$d/scripts"
  ln -sfn "$REPO_ROOT/scripts/lib" "$d/scripts/lib"
  ln -sfn "$REPO_ROOT/scripts/test-all.sh" "$d/scripts/test-all.sh"
  base="$(basename "$src")"
  mut="$d/scripts/$base"

  line=""
  rc=0
  line="$(python3 "$WORK/mutate.py" "$src" "$span" "$pattern" "$replacement" "$mut" 2>&1)" || rc=$?
  if [[ "$rc" != "0" ]]; then
    printf 'STATUS=APPLY_FAILED\nDETAIL=%s\n' "$line" > "$res"
    exit 0
  fi

  # Placement: EXACTLY ONE line changed, and it falls inside the target span.
  changed="$(diff <(cat "$src") <(cat "$mut") | grep -cE '^[<>]' || true)"
  if [[ "$changed" != "2" ]]; then
    printf 'STATUS=PLACEMENT_FAILED\nDETAIL=%s changed hunks (expected exactly one line)\n' "$changed" > "$res"
    exit 0
  fi

  # Drive the REAL suite against the mutant.
  if [[ "$target" == "suite" ]]; then
    run_suite_path="$mut"; run_sut="$ORIG"
    # PER-ROW CONTROL. A suite-target row runs in this synthetic layout, so it
    # needs its own proof that the layout itself is green before the mutation's
    # verdict means anything — the battery's single global control runs from the
    # repo and cannot see a layout defect.
    cp "$SUITE" "$d/scripts/control-$base"
    ctl_out="$d/control.log"; ctl_rc=0
    env -u CI ORPHAN_SUITE_SUT="$ORIG" ORPHAN_SUITE_SKIP_LIVE=1 \
      timeout 300 bash "$d/scripts/control-$base" > "$ctl_out" 2>&1 || ctl_rc=$?
    if [[ "$ctl_rc" != "0" ]]; then
      printf 'STATUS=CONTROL_RED\nDETAIL=the unmutated suite is RED in the worker layout (rc=%s) — this row would score the environment, not the mutation\n' "$ctl_rc" > "$res"
      exit 0
    fi
  else
    run_suite_path="$SUITE"; run_sut="$mut"
  fi

  out="$d/out.log"
  src_rc=0
  env -u CI ORPHAN_SUITE_SUT="$run_sut" ORPHAN_SUITE_SKIP_LIVE=1 \
    timeout 300 bash "$run_suite_path" > "$out" 2>&1 || src_rc=$?

  labels="$(grep -oE '^\s+\[FAIL\] .*' "$out" | sed 's/^[[:space:]]*\[FAIL\] //' | sed 's/ —.*//' | sort -u | tr '\n' '|' || true)"
  printf 'STATUS=RAN\nRC=%s\nLINE=%s\nLABELS=%s\n' "$src_rc" "$line" "$labels" > "$res"
  exit 0
fi

WORK="$(mktemp -d -t orphan-mut.XXXXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Rows are independent — each operates on its own copy in its own temp dir — so
# they are run concurrently. Serial cost is measured and quoted in the PR.
PARALLEL="${ORPHAN_MUT_PARALLEL:-6}"

# --- The mutation applier --------------------------------------------------
# Resolves a NAMED SPAN (a function body, or a section delimited by banner
# comments), requires EXACTLY ONE line in that span to match, replaces it, and
# reports the changed line number. Refuses — exit 2 — on zero matches, on more
# than one, or on a replacement that changes nothing.
cat > "$WORK/mutate.py" <<'PYEOF'
import re, sys

path, span, pattern, replacement, out = sys.argv[1:6]
lines = open(path).read().split("\n")

def span_bounds(name):
    if name.startswith("@"):                      # banner-delimited section
        start_marker, end_marker = name[1:].split("..")
        s = e = None
        for i, l in enumerate(lines):
            if s is None and start_marker in l:
                s = i
            elif s is not None and end_marker in l:
                e = i
                break
        if s is None or e is None:
            sys.exit("SPAN_NOT_FOUND %s" % name)
        return s, e
    for i, l in enumerate(lines):                 # a function body
        if re.match(r"^%s\(\)" % re.escape(name), l):
            for j in range(i + 1, len(lines)):
                if lines[j] == "}":
                    return i, j
            sys.exit("SPAN_UNTERMINATED %s" % name)
    sys.exit("SPAN_NOT_FOUND %s" % name)

lo, hi = span_bounds(span)
rx = re.compile(pattern)
hits = [i for i in range(lo, hi + 1) if rx.search(lines[i])]

if len(hits) == 0:
    sys.exit("NO_MATCH in span %s for %s" % (span, pattern))
if len(hits) > 1:
    # Ambiguity is a battery defect, not a result: the row would not know which
    # site it mutated, and "landed" would stop meaning anything.
    sys.exit("AMBIGUOUS %d matches in span %s for %s" % (len(hits), span, pattern))

i = hits[0]
before = lines[i]
after = rx.sub(replacement, before, count=1)
if after == before:
    sys.exit("VACUOUS replacement changed nothing at line %d" % (i + 1))
lines[i] = after
open(out, "w").write("\n".join(lines))
print(i + 1)
PYEOF

# --- Harness ---------------------------------------------------------------
pass_n=0
fails=0
cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# --- Row table -------------------------------------------------------------
# Tab-separated, in a QUOTED heredoc: patterns carry regex metacharacters and
# shell-significant quotes, and routing them through bash word-splitting is
# where the first draft of this table went wrong. Fields:
#
#   id <TAB> target(sut|suite) <TAB> span <TAB> pattern <TAB> replacement <TAB> why
#
# `span` is either a function name or `@START..END`, matched by SUBSTRING in
# order. Patterns match a WHOLE LINE and replacements supply the whole line,
# including indentation — anchoring on a fragment is what produced ambiguous
# and mis-escaped rows.
ROWS="$WORK/rows.tsv"
cat > "$ROWS" <<'ROWS_EOF'
M1	sut	_orphan_classify	^  if \[\[ "\$role" == "anchor" \]\]; then$	  if false; then	drop the fd/255 conjunct: the deleted-cwd-only fixture becomes an anchor
M2	sut	_orphan_is_unlinked	^  \[\[ "\$n" == "0" \]\]$	  [[ "$(readlink "$1" 2>/dev/null)" == *' (deleted)' ]]	replace the link-count test with a suffix match: the measured spoof is flagged
M3	sut	_orphan_classify	^    \[\[ "\$fdl" == /\* \]\] \|\| return 1$	    { [[ "$fdl" == /* ]] && _orphan_is_unlinked "$d/exe"; } || return 1	add exe to the conjunction: the canonical positive stops flagging
M4	sut	_orphan_classify	^    \[\[ "\$fdl" == \*' \(deleted\)' \]\] \|\| return 1$	    { [[ "$fdl" == *' (deleted)' ]] && ! [[ -e "$d/fd/1" ]]; } || return 1	add fd/1 as a VETO: the canonical positive, whose fd/1 is a live /dev/null, is suppressed
M31	sut	_orphan_classify	^    \[\[ "\$ftype" == "regular file".*$	    [[ -n "$ftype" ]] || return 1	drop G3's regular-file term: predicate breadth widens past "an unlinked script"
M5	sut	@--- The walk ---..--- The reap set ---	^  if \[\[ ! -O "\$d" \]\]; then$	  if false; then	remove the own-uid gate: foreign processes stop being counted, so the gate has no observable
M6	sut	_orphan_classify	^  if \[\[ "\$SELF_CHAIN" == \*" \$pid "\* \]\]; then return 1; fi$	  if [[ "$SELF_CHAIN" == *" $pid "* && "$role" == "member" ]]; then return 1; fi	self-exclusion off for ANCHORS: the scanner appears among anchors
M7	sut	_orphan_classify	^  if \[\[ "\$SELF_CHAIN" == \*" \$pid "\* \]\]; then return 1; fi$	  if [[ "$SELF_CHAIN" == *" $pid "* && "$role" == "anchor" ]]; then return 1; fi	self-exclusion off for MEMBERS: the suicide bug, the caller's own tree enters the reap set
M9	sut	_orphan_classify	^  if \[\[ -n "\$NS_MNT_SELF" && "\$ns" != "\$NS_MNT_SELF" \]\]; then$	  if false; then	remove the mount-namespace gate: a sandboxed process is adjudicated
M33	sut	_orphan_classify	^  if \[\[ -n "\$NS_PID_SELF" && "\$nsp" != "\$NS_PID_SELF" \]\]; then$	  if false; then	remove G7: a foreign pid namespace is accepted, whose pids are not pids here
M29	sut	@--- Privilege floor..--- Seam validation	^if \[\[ "\$_euid" == "0" \|\| "\$_euid_real" == "0" \]\]; then$	if false; then	remove the root refusal: G1 PASSES under sudo, which is exactly the danger
M10	sut	_orphan_classify	^  if \(\( age < ORPHAN_REAPER_MIN_AGE_S \)\); then return 1; fi$	  if false; then return 1; fi	remove the age floor: the seconds-old orphan fixture is flagged
M11	sut	_orphan_classify	^  if \[\[ ! "\$st" =~ .*\]\]; then$	  if false; then	accept a non-numeric starttime: the measured fail-open, empty is arithmetic zero
M12	sut	_orphan_is_unlinked	^  n=\$\(stat -Lc '%h' "\$1" 2>/dev/null\) \|\| return 1$	  n=$(stat -Lc '%h' "$1" 2>/dev/null) || return 0	invert the error default: an unreadable link counts as unlinked
M24	sut	_orphan_classify	^  ns=\$\(readlink "\$d/ns/mnt" 2>/dev/null\) \|\| ns=""$	  ns=$(readlink "$d/ns/mnt" 2>/dev/null)	capture a readlink without deciding its non-zero meaning: the walk aborts on a vanishing pid
M28	sut	@Only three PRIVATE readers..CLK_TCK=	^declare -F _tc_pgrp >/dev/null 2>&1 \|\| \\$	_tc_pgrp() { :; }; declare -F _tc_pgrp >/dev/null 2>&1 || \\	stub a borrowed _tc_* helper with the assertion intact: the exclusion set silently empties
M26	sut	@Only three PRIVATE readers..CLK_TCK=	^declare -F _tc_starttime_ticks >/dev/null 2>&1 \|\| \\$	true _tc_starttime_ticks >/dev/null 2>&1 || \\	delete the declare -F assertion only: its own absence must redden
M13	sut	@--- The walk ---..--- The reap set ---	^  \[\[ -d "\$d" && ! -L "\$d" \]\] \|\| continue$	  :	drop the glob guard: bash iterates a non-matching pattern once, literally
M32	sut	signal_one	^  if \[\[ ! "\$pid" =~ .*\|\| \[\[ "\$pid" == "1" \]\]; then$	  if false; then	relax pid validation AT THE SIGNAL SITE: an entry named 0 reaches kill, where -TERM 0 hits the caller's whole group
M35	sut	@--- The walk ---..--- The reap set ---	^    prefiltered_no_fd255=\$\(\(prefiltered_no_fd255 \+ 1\)\)$	    unreadable=$((unreadable + 1))	collapse the staged drop counters: a ~417-pid baseline swamps the real signal
M8	sut	@--- The reap set ---..--- Verbs ---	^    if \[\[ "\$SELF_CWD_KEY" == "\$a_key" \]\] \\$	    if false; then :	remove the scanner-inside-the-doomed-inode structural refusal
M14	sut	@--- The reap set ---..--- Verbs ---	^      members\+=\("\$p"\); m_st.*$	      members+=("$p"); m_st+=("$_OC_STARTTIME"); m_age+=("$_OC_AGE"); m_cwdnl+=("$_OC_CWD_NLINK"); break	stop at the first member: a second compliant member is never seen
M15	sut	@--- The reap set ---..--- Verbs ---	^      members\+=\("\$p"\); m_st.*$	      true	restrict the reap set to the anchor alone: the child that burns the cores survives
M17	sut	@--- The reap set ---..--- Verbs ---	^      _orphan_classify "\$p" member \|\| continue$	      true	let membership inherit the anchor's verdict instead of restating the gates
M18	sut	@--- The reap set ---..--- Verbs ---	^    if \(\( total > ORPHAN_REAPER_MAX_SET \)\); then$	    if false; then	remove the cardinality cap: an unbounded blast radius proceeds automatically
M30	sut	_orphan_cwd_key	^  k=\$\(stat -Lc '%d:%i' "\$ORPHAN_PROC_ROOT/\$1/cwd" 2>/dev/null\) \|\| k=""$	  k=$(stat -Lc '%i' "$ORPHAN_PROC_ROOT/$1/cwd" 2>/dev/null) || k=""	drop %d from set membership: a cross-device inode-number collision joins the set
M19	sut	@CHILDREN BEFORE THE ANCHOR..emit_summary	^  \[\[ "\$\{SET_ROLES\[\$i\]\}" == "member" \]\] \|\| continue$	  [[ "${SET_ROLES[$i]}" == "anchor" ]] || continue	signal the anchor before its children: a supervising parent respawns them
M20	sut	signal_one	^  if \[\[ ! "\$now_st" =~ .*\]\]; then$	  if false; then	remove starttime re-verification at the signal site: a recycled pid is signalled
M21	sut	@--- reap ---..evidence channel must be live	^if \(\( ROOT_IS_PROCFS == 0 \)\) && \[\[ -z "\$ORPHAN_REAPER_SIGNAL_SINK" \]\]; then$	if false; then	let reap run against a fixture root with no injected sink: a live pid receives a real TERM
M22	sut	signal_one	^  if ! evidence_write "\$rec"; then$	  if false; then	remove the journald record: after a successful kill the evidence is unrecoverable
M23	sut	@evidence write failed for pid..DRY == 1	^    refused=\$\(\(refused \+ 1\)\); return 0$	    refused=$((refused + 1))	let a failed evidence write proceed to the signal: it signals unrecorded
M34	sut	@--- Evidence channel..--- The unlinked predicate	^  if printf '' >> "\$ORPHAN_REAPER_EVIDENCE_FILE" 2>/dev/null; then evidence=ok; fi$	  evidence=ok	remove the startup evidence-channel probe: the tool reports ok while the channel is down
M25	sut	emit_summary	^(.*)unreadable=%s (.*)$	\1\2	drop the unreadable counter: a silent drop is indistinguishable from a real zero
H1	suite	@pass_n=0..TESTROOT=	^fail\(\) \{ fails=.*$	fail() { :; }	stub fail() to a no-op: cases keeps moving while fails stops, breaking conservation
H1b	suite	@pass_n=0..TESTROOT=	^fail\(\) \{ fails=.*$	fail() { pass_n=$((pass_n + 1)); echo "  [FAIL] $1" >&2; }	rewrite fail() to increment pass_n: conservation AND the floor both still hold
H4	sut	@--- Borrowed primitives ---..shellcheck source	^TC_SELF_PID="\$ORPHAN_REAPER_SELF_PID"$	TC_SELF_PID="$$"	leak the REAL procfs identity into a synthetic run: self-exclusion asserts nothing
ROWS_EOF

echo "=== orphan-process-reaper mutation battery ==="

# --- 1. GREEN BASELINE, FULL SUITE, BEFORE ANY ROW ------------------------
echo "--- unmutated control (full suite, live arms included) ---"
ctl_rc=0
env -u CI timeout 600 bash "$SUITE" > "$WORK/control.log" 2>&1 || ctl_rc=$?
cases=$((cases + 1))
if [[ "$ctl_rc" == "0" ]]; then
  pass "control: the unmutated detector passes the full behavioural suite"
else
  fail "control: the UNMUTATED suite is RED (rc=$ctl_rc) — aborting rather than scoring rows against a red baseline"
  echo "--- control tail ---" >&2
  tail -20 "$WORK/control.log" >&2
  echo "=== orphan-process-reaper-mutation: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# --- 2. H2: the applier itself must refuse a no-op edit -------------------
cases=$((cases + 1))
h2_rc=0
python3 "$WORK/mutate.py" "$ORIG" _orphan_is_unlinked 'return 1' 'return 1' "$WORK/h2.sh" >/dev/null 2>&1 || h2_rc=$?
if [[ "$h2_rc" != "0" ]]; then
  pass "H2: a byte-identical 'mutation' is refused as VACUOUS, never counted as a pass"
else
  fail "H2: the applier accepted a no-op edit — every row could report a false pass"
fi

# --- 3. H3: the suite's assertion floor must be present and recognisable ---
floor_present() {  # file
  grep -qE 'if \[\[ "\$cases" -lt "\$MIN_CASES" \]\]' "$1"
}
cases=$((cases + 1))
if floor_present "$SUITE"; then
  pass "H3: the behavioural suite carries an absolute assertion floor in the recognised shape"
else
  fail "H3: no floor in the \`[[ \"\$cases\" -lt N ]]\` shape — guard-vacuity-floor.test.sh would not see it"
fi
cases=$((cases + 1))
python3 "$WORK/mutate.py" "$SUITE" '@Vacuity floors..Accounting conservation' \
  'if \[\[ "\$cases" -lt "\$MIN_CASES" \]\]; then' 'if false; then' "$WORK/h3.sh" >/dev/null 2>&1 || true
if [[ -f "$WORK/h3.sh" ]] && ! floor_present "$WORK/h3.sh"; then
  pass "H3: and removing it is DETECTED — the check is not vacuous"
else
  fail "H3: the floor-presence check could not be driven red"
fi

# --- 4. Run every row -----------------------------------------------------
echo "--- rows ---"
export ORIG SUITE
mut_start=$(date +%s%N)
# `-P` bounded: rows are independent (own copy, own temp dir, own fixtures), and
# a row's verdict is its suite's exit status, which concurrency does not change.
# Wall-clock IS affected, and that is stated with the measurement in the PR.
while IFS= read -r line; do printf '%s\n' "$line"; done < "$ROWS" \
  | xargs -d '\n' -I{} -P "$PARALLEL" bash "$0" --worker '{}' "$WORK"
mut_elapsed=$(( ($(date +%s%N) - mut_start) / 1000000 ))

# --- 5. Score, and compute axis distinctness ------------------------------
declare -A LABELS_OF
red_rows=0
# id -> why this mutant provably changes no verdict. Asserted to SURVIVE: a row
# that starts reddening means the proof below is stale and must be re-derived.
declare -A EXPECT_SURVIVE=(
  [M12]="inverting _orphan_is_unlinked's error default cannot change a verdict: every caller that could act on the inverted answer re-stats the same link immediately afterwards (cwd via _orphan_cwd_key, fd/255 via the regular-file term) and that second read fails identically, so the process is still counted unreadable and left alive"
  [M23]="dropping the return after a failed evidence write cannot change a verdict: the channel is probed ONCE at startup and reap refuses outright when it is down, so the per-signal write failure this row targets is unreachable while that probe stands (mutate M34 to see it)"
)
while IFS=$'\t' read -r id target span pattern replacement why; do
  res="$WORK/res.$id"
  cases=$((cases + 1))
  if [[ ! -f "$res" ]]; then
    fail "$id: produced no result file — the row did not run"
    continue
  fi
  status="$(grep -E '^STATUS=' "$res" | cut -d= -f2- || true)"
  case "$status" in
    APPLY_FAILED)
      fail "$id: the edit did not apply — $(grep -E '^DETAIL=' "$res" | cut -d= -f2-). A row that matched nothing is VACUOUS, not a pass."
      continue ;;
    CONTROL_RED)
      fail "$id: $(grep -E '^DETAIL=' "$res" | cut -d= -f2-)"
      continue ;;
    PLACEMENT_FAILED)
      fail "$id: $(grep -E '^DETAIL=' "$res" | cut -d= -f2-). 'The mutant differs' proves the file changed, never where."
      continue ;;
  esac
  rrc="$(grep -E '^RC=' "$res" | cut -d= -f2- || true)"
  labels="$(grep -E '^LABELS=' "$res" | cut -d= -f2- || true)"
  if [[ -n "${EXPECT_SURVIVE[$id]:-}" ]]; then
    if [[ "$rrc" == "0" ]]; then
      pass "$id survives AS DOCUMENTED (equivalent mutant) — ${EXPECT_SURVIVE[$id]}"
    else
      fail "$id was declared an EQUIVALENT mutant but now reddens — the recorded proof is stale and must be re-derived: ${EXPECT_SURVIVE[$id]}"
    fi
    continue
  fi
  if [[ "$rrc" != "0" ]]; then
    pass "$id reddens the suite — $why"
    red_rows=$((red_rows + 1))
    LABELS_OF["$id"]="$labels"
  else
    fail "$id SURVIVED: the suite stayed green with this check mutated out. Either the fixtures do not exercise the property (fix the FIXTURES), or the mutant is equivalent (prove no verdict changes, and record that it survives) — an unlabelled survivor is how a guard adjacent to a working one ships. [$why]"
  fi
done < "$ROWS"

# H5 — force the suite's final exit to 0 and confirm the battery's own
# red-detection depends on that exit path. Nothing else exercises it: a suite
# whose success condition is `fails == 0` exits 0 on "0 passed, 0 failed".
cases=$((cases + 1))
h5_rc=0
python3 "$WORK/mutate.py" "$SUITE" '@ASSERTION-HELPER POSITIVE CONTROL..fails" -eq 0 ]]' \
  '^\[\[ "\$fails" -eq 0 \]\] \|\| exit 1$' 'true' "$WORK/h5.sh" >/dev/null 2>&1 || h5_rc=$?
if [[ "$h5_rc" != "0" ]]; then
  # The span/pattern must resolve; if it does not, say so rather than scoring it.
  fail "H5: could not neuter the suite's exit path — the row asserted nothing"
else
  # Run the exit-neutered suite against a KNOWN-BROKEN detector. The point is
  # not that the suite is quiet — it is that the suite REPORTS failures and
  # still exits 0, so a battery reading only the exit status would score that
  # row as "survived". This is what makes the battery's verdict depend on the
  # suite's exit path rather than on its own optimism.
  broken="$WORK/broken-sut.sh"
  python3 "$WORK/mutate.py" "$ORIG" "@--- The walk ---..--- The reap set ---" \
    '^  if \[\[ ! -O "\$d" \]\]; then$' '  if false; then' "$broken" >/dev/null 2>&1 || true
  ln -sfn "$REPO_ROOT/scripts/lib" "$WORK/lib" 2>/dev/null || true
  h5_run_rc=0
  env -u CI ORPHAN_SUITE_SUT="$broken" ORPHAN_SUITE_SKIP_LIVE=1 \
    timeout 300 bash "$WORK/h5.sh" > "$WORK/h5.log" 2>&1 || h5_run_rc=$?
  h5_fails="$(grep -cE '^\s+\[FAIL\]' "$WORK/h5.log" || true)"
  if [[ "$h5_run_rc" == "0" && "$h5_fails" -gt 1 ]]; then
    pass "H5: with the exit path neutered the suite reports $h5_fails failures and STILL exits 0 — the battery's verdict rests on that path, not on the suite's own optimism"
  else
    fail "H5: expected a neutered exit to hide real failures (rc=0, fails>1); got rc=$h5_run_rc fails=$h5_fails"
  fi
fi

# AC30 — AXIS DISTINCTNESS, COMPUTED. Two rows that redden the same arms are one
# mutation wearing two names. Non-identical AND non-subset, because a row whose
# failing set is contained in another's is not independent evidence.
echo "--- axis distinctness ---"
ids=("${!LABELS_OF[@]}")
for ((i = 0; i < ${#ids[@]}; i++)); do
  for ((j = i + 1; j < ${#ids[@]}; j++)); do
    a="${ids[$i]}"; b="${ids[$j]}"
    la="${LABELS_OF[$a]}"; lb="${LABELS_OF[$b]}"
    cases=$((cases + 1))
    if [[ "$la" == "$lb" ]]; then
      fail "axes $a and $b redden an IDENTICAL arm set — one mutation wearing two names"
      continue
    fi
    # Subset test, both directions.
    sub=""
    a_in_b=1; b_in_a=1
    IFS='|' read -ra arr_a <<<"$la"
    IFS='|' read -ra arr_b <<<"$lb"
    for x in ${arr_a[@]+"${arr_a[@]}"}; do [[ -z "$x" ]] && continue; [[ "$lb" == *"$x"* ]] || a_in_b=0; done
    for x in ${arr_b[@]+"${arr_b[@]}"}; do [[ -z "$x" ]] && continue; [[ "$la" == *"$x"* ]] || b_in_a=0; done
    [[ "$a_in_b" == "1" ]] && sub="$a ⊆ $b"
    [[ "$b_in_a" == "1" ]] && sub="$b ⊆ $a"
    if [[ -n "$sub" ]]; then
      pass "axes $a and $b differ (proper subset: $sub — narrower witness, not a duplicate)"
    else
      pass "axes $a and $b are distinct"
    fi
  done
done

# THE BUDGET IS AN ASSERTION, not a caption. It was previously computed,
# printed beside the literal string "ceiling: 120000ms", and never compared to
# it — so the battery could drift to 300s and still exit 0 with the ceiling
# printed next to a number exceeding it. That is the exact vacuity class this
# file exists to close, in this file's own budget.
# THE CEILING IS DERIVED FROM THE BATTERY'S SHAPE, and the derivation is here so
# the number can be re-checked rather than trusted.
#
#   rows (36) + per-row controls for the 3 suite-target rows = 39 suite runs
#   x ~19 s per skip-live suite run
#   / -P6
#   ~= 124 s ideal, before any contention.
#
# The plan's original 120000 ms predated both the per-row control (added because
# suite-target rows were otherwise scored against a red baseline) and the
# suite's growth from 122 to 136 assertions, several of which are real-signal
# arms. It was a literal carried forward from a smaller battery — the stale-
# budget shape this repo warns about — so it is re-derived rather than raised.
#
# 240000 ms is ~1.9x the ideal, which absorbs the contention this box routinely
# carries while still failing on a genuine doubling. Measured under sibling
# load: 154 s. On an uncontended box the battery should sit near the ideal; if
# it does not, that is the finding this assertion exists to surface.
MUT_CEILING_MS="${ORPHAN_MUT_CEILING_MS:-240000}"
printf '\n[measurement] mutation rows: %d, wall-clock %dms at -P%s (ceiling: %dms)\n' \
  "$(wc -l < "$ROWS")" "$mut_elapsed" "$PARALLEL" "$MUT_CEILING_MS"
cases=$((cases + 1))
if (( mut_elapsed <= MUT_CEILING_MS )); then
  pass "battery wall-clock ${mut_elapsed}ms is within the ${MUT_CEILING_MS}ms ceiling"
else
  fail "battery wall-clock ${mut_elapsed}ms EXCEEDS the ${MUT_CEILING_MS}ms ceiling — trim rows or move the battery to its own shard rather than raising this silently"
fi

# `red_rows` was accumulated and discarded — the battery's headline number had
# no reader. Assert it against the rows that were actually expected to redden.
cases=$((cases + 1))
_expected_red=$(( $(wc -l < "$ROWS") - ${#EXPECT_SURVIVE[@]} ))
if (( red_rows == _expected_red )); then
  pass "every row expected to redden did so ($red_rows of $_expected_red)"
else
  fail "only $red_rows of $_expected_red rows reddened — the difference is unaccounted for"
fi

MIN_CASES=40
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '\n[FATAL] assertion floor: %d assertions ran, expected at least %d.\n' "$cases" "$MIN_CASES" >&2
  echo "=== orphan-process-reaper-mutation: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

if [[ $((pass_n + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass_n+fails (%d) != cases (%d).\n' "$((pass_n + fails))" "$cases" >&2
  echo "=== orphan-process-reaper-mutation: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

echo "=== orphan-process-reaper-mutation: $pass_n passed, $fails failed ($cases assertions) ==="
[[ "$fails" -eq 0 ]] || exit 1
