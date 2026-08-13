#!/usr/bin/env bash
# Mutation battery for the #7104 PR-B bounded re-push — Guard 1 and Guard 2 (tasks 4.3, 8.2).
#
# AC21: "Every Guard 1 and Guard 2 mutation row is committed and drives the suite RED when
# applied, including the two rows that target the guard's own dispatch." A matrix in a plan is a
# claim; this file is the measurement. Every sibling bash mutation battery in this directory is
# `*-mutation.test.sh` AND registered in .github/workflows/infra-validation.yml
# (workspaces-luks-g4, web-host-provisioner-parity, inngest-rls, scan-workflow,
# zot-image-staleness, cf-tunnel-liveness-gate), so this one follows both halves of that
# convention. An unrun battery is a claim, not a guard.
#
# WHAT IT DRIVES. Each row copies a minimal repo skeleton, applies exactly one mutation, and runs
# the real suite that is supposed to catch it — infra-config-gate.test.sh for the Guard 1 and
# Guard 2 rows, infra-config-verify.test.sh for the stub-fidelity row. The tracked tree is never
# mutated.
#
# WHICH AXES THIS BATTERY EDITS, stated so the omissions are visible rather than implied:
#   dispatch           — G1-4 (the predicate's own `declare -F`), D1 (the harness's fail())
#   fixture shape      — G1-6 (the fixture builder's default supplying the asserted value)
#   member cardinality — G1-5 (a SECOND member added to the success set)
#   population growth  — G2-3 (a SECOND production apply site ADDED, not an edit to the first)
#   region boundaries  — G2-5 (a nested `done` inside the pinned region)
#   authority input    — D2 (the output the workflow's `if:` literals are validated against)
#   assertion count    — G2-7 (the anti-vacuity floor, via deletion of a pinned block)
#   harness stubbing   — S1 (the PATH stub's argv contract)
#   the floor          — G1-7 (the predicate's one passing arm; without it the predicate could be
#                        `return 1` unconditionally and every refusal row would stay green)
#
# AXES THIS BATTERY DOES **NOT** EDIT:
#   demotion — leaving asserted bytes identical and rewording the prose above them so the
#     prescription reads as conditional. Nothing in this diff is a prose prescription that a gate
#     enforces; ADR-189 is a decision record, not an enforced contract. Not applicable rather
#     than skipped.
#   fixture direction — the far side of a transform. Guard 1's predicate is a one-directional
#     allow-list (exactly one input shape returns 0), and G1-7 IS the opposite-direction fixture.
#     There is no second direction to sample.
#   the cf-tunnel-ssh-bridge composite action — the third production-reachable path named in
#     Guard 2's assembly. Pre-existing, unmodified by this PR, and out of scope by decision (see
#     the assembly note in infra-config-gate.test.sh); mutating it would test a guard this PR did
#     not build.
#
# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a battery that builds a
# sandbox per case must not have its verdicts depend on another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

GATE_SUITE=apps/web-platform/infra/infra-config-gate.test.sh
VERIFY_SUITE=apps/web-platform/infra/infra-config-verify.test.sh

# --- the mutators -------------------------------------------------------------------------------
# Defined before the child-mode dispatch below, because bash resolves a function at call time and
# the child block runs before anything further down the file.
#
# Every mutation asserts its own anchor cardinality and exits 3 on a miss. A mutator that silently
# no-ops reports the BASELINE, which is indistinguishable from "the suite did not detect this".
_mutate_impl() {
  python3 - "$1" "$2" <<'PYEOF'
import os, re, sys

box, case = sys.argv[1], sys.argv[2]
INFRA  = os.path.join(box, 'apps/web-platform/infra')
GATE   = os.path.join(INFRA, 'infra-config-gate.sh')
TEST   = os.path.join(INFRA, 'infra-config-gate.test.sh')
VERIFY = os.path.join(INFRA, 'infra-config-verify.sh')
WF     = os.path.join(box, '.github/workflows/apply-deploy-pipeline-fix.yml')

def die(msg):
    sys.stderr.write('MUTATOR-FAIL[%s]: %s\n' % (case, msg))
    sys.exit(3)

def sub(path, old, new, want=1):
    s = open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != want:
        die('anchor occurs %d time(s) in %s, expected %d -- anchor: %r'
            % (n, os.path.basename(path), want, old[:100]))
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, want))

def sub_in_fn(path, name, old, new, want=1):
    s = open(path, encoding='utf-8').read()
    m = re.search(r'^%s\(\)\s*\{\s*$' % re.escape(name), s, re.M)
    if not m:
        die('no function %s() in %s' % (name, os.path.basename(path)))
    e = re.search(r'^\}\s*$', s[m.end():], re.M)
    if not e:
        die('function %s() is unterminated' % name)
    a, b = m.end(), m.end() + e.start()
    body = s[a:b]
    n = body.count(old)
    if n != want:
        die('anchor occurs %d time(s) inside %s(), expected %d -- anchor: %r'
            % (n, name, want, old[:100]))
    open(path, 'w', encoding='utf-8').write(s[:a] + body.replace(old, new, want) + s[b:])

def delete_block(path, start_literal, end_line='fi'):
    """Delete from the line holding start_literal through the next line equal to end_line."""
    lines = open(path, encoding='utf-8').read().splitlines(keepends=True)
    starts = [i for i, l in enumerate(lines) if start_literal in l]
    if len(starts) != 1:
        die('start anchor occurs %d time(s), expected 1: %r' % (len(starts), start_literal))
    i = starts[0]
    for j in range(i + 1, len(lines)):
        if lines[j].rstrip('\n') == end_line:
            open(path, 'w', encoding='utf-8').writelines(lines[:i] + lines[j + 1:])
            return
    die('no terminating %r line after the start anchor' % end_line)

# ---- Guard 1 — infra_config_should_repush (the re-push decision) -------------------------------
if case == 'G1-1':
    # Row 1 — THE PRIMARY ROW. Drop the dpf-replaced clause so the predicate decides on frame
    # shape alone. Three merge classes replace no DPF and legitimately publish no frame; each
    # would then become a spurious production re-push, which is the defect PR-A shipped to stop.
    sub(GATE, '  [[ "$dpf_replaced" == "true" ]] || return 1',
              '  : # MUTATED G1-1: dpf-replaced clause dropped')

elif case == 'G1-2':
    # Row 2 — relax the polarity guard, so a non-canonical reading (jq's string `null` on a
    # missing key, an address rename, an empty resource_changes[]) stops being discriminated and
    # reads as "no push expected" permanently and silently.
    sub_in_fn(GATE, 'infra_config_should_repush', '^(true|false)$', '^.*$')

elif case == 'G1-3':
    # Row 3 — -lt becomes -le, so a frame published in the same whole second as the baseline
    # re-pushes. Equality is FRESH: that frame was delivered, and re-pushing on it writes
    # production for a run that already succeeded.
    sub_in_fn(GATE, 'infra_config_should_repush',
              '[[ "$start_ts" -lt "$baseline" ]]', '[[ "$start_ts" -le "$baseline" ]]')

elif case == 'G1-4':
    # Row 4 — THE GUARD'S OWN DISPATCH. Rename the predicate, leaving every call site in place.
    # A decision function that is silently absent must never read as "do not re-push" or as
    # success.
    sub(GATE, 'infra_config_should_repush() {', 'infra_config_should_repush_RENAMED() {')

elif case == 'G1-5':
    # Row 5 — add a SECOND member to the success set: an unreadable frame becomes licence to
    # write production, "because we cannot rule the race out". Allow-list semantics are the whole
    # contract, and treating uncertainty as licence inverts the polarity.
    #
    # The verdict is flipped in place rather than by DELETING the numeric guard, and the reason is
    # measured. Deleting it (`if false; then`) lets a non-numeric start_ts reach
    # `[[ "$start_ts" -lt "$baseline" ]]`, where bash's arithmetic context treats `notanumber` as
    # a VARIABLE NAME — so under this suite's `set -u` the guard's absence is a FATAL abort, not a
    # failed assertion. The suite exits 1 having printed no verdict at all, which this battery
    # correctly refuses to score as detection: an abort is equally compatible with a suite that
    # became incapable of passing for an unrelated reason. Flipping the return keeps the mutation
    # on the axis the row is about — the size of the success set.
    sub_in_fn(GATE, 'infra_config_should_repush',
              'is not a stale frame" >&2\n    return 1',
              'is not a stale frame" >&2\n    return 0')

elif case == 'G1-6':
    # Row 6 — VACUITY. Make the fixture builder's default supply the value the case also asserts
    # on. Cases that return the same verdict under two different decision rules measure nothing.
    sub(TEST, '''    printf '{"exit_code":0,"start_ts":%s}\\n' "$2" > "$1"''',
              '''    printf '{"exit_code":0,"start_ts":1000}\\n' > "$1"''')

elif case == 'G1-7':
    # Row 7 — THE FLOOR / positive control. Make the predicate refuse unconditionally. Without a
    # passing row it could be `return 1` always and every refusal row would still be green.
    sub_in_fn(GATE, 'infra_config_should_repush',
              '[[ "$start_ts" -lt "$baseline" ]]', 'return 1')

# ---- Guard 2 — the production call-site pin ----------------------------------------------------
elif case == 'G2-1':
    # Row 1 (pre-existing #6594) — move the content assert INSIDE the poll loop, so it becomes an
    # any-of-N coin flip across fresh connector selections. The pin's original property must
    # still hold after PR-B re-points it across the extraction boundary.
    sub(VERIFY,
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\ndone\n',
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\n'
        '  adjudicate_infra_config /tmp/infra-config-status-response.txt . infra-config-apply.sh || true\n'
        'done\n')

elif case == 'G2-2':
    # Row 2 — delete the predicate call and inline an equivalent condition. Guard 1's entire
    # matrix would then certify a predicate production does not run.
    sub(VERIFY,
        'if infra_config_should_repush /tmp/infra-config-status-response.txt "$DPF_REPLACED" "$APPLY_START_EPOCH"; then',
        'if [[ "$DPF_REPLACED" == "true" ]]; then')

elif case == 'G2-3':
    # Row 3 — BOUNDEDNESS, as re-derived by plan R22.6. The latch this row originally named was
    # pruned with the inline design; the replacement property is "exactly one step in the job
    # invokes terraform apply against tfplan-repush". Add a SECOND production apply.
    sub(WF,
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n',
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n'
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n')

elif case == 'G2-4':
    # Row 6 (the one R22.6 keeps from R18.2) — wrap the predicate call in a function. Bash
    # suspends errexit for a CONDITION context and the suspension propagates into the function
    # body, so a production terraform apply downstream of it would run with -e off.
    sub(VERIFY,
        '      if infra_config_should_repush /tmp/infra-config-status-response.txt "$DPF_REPLACED" "$APPLY_START_EPOCH"; then',
        '      repush_once() { infra_config_should_repush "$@"; }\n'
        '      if repush_once /tmp/infra-config-status-response.txt "$DPF_REPLACED" "$APPLY_START_EPOCH"; then')

elif case == 'G2-5':
    # Row 5 — REGION BOUNDARY. Add a nested loop between the pinned anchors. The pin's original
    # first-match `awk '... $1=="done" {print NR; exit}'` scan was structurally blind to this;
    # only the counting pass added by task 8.1 can see it.
    #
    # The loop is written across THREE LINES on purpose, and the first attempt at this row is why:
    # a one-liner `for _mutant in 1; do :; done` leaves `$1` equal to `for`, so it adds no
    # `$1=="done"` line and does not perturb the axis the guard counts at all. It landed (the
    # diff-vs-pristine check passed) and the suite stayed green — a mutation that measures nothing
    # while looking like a survivor. `done` has to be the first FIELD of its own line, which is
    # exactly the shape the pin quantifies over.
    sub(VERIFY,
        '# --- Final adjudication (fail loud; no silent pass) ---',
        'for _mutant in 1; do\n  :\ndone\n'
        '# --- Final adjudication (fail loud; no silent pass) ---')

elif case == 'G2-6':
    # Row 6' (R20.7 §1) — the SOURCED library is production-reachable and invisible to every grep
    # over the workflow, and it is the file this PR adds a function to. Add a command-position
    # production write to it.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_write() {\n  terraform apply -auto-approve\n}\n')

elif case == 'G2-7':
    # Row 7 — ASSERTION COUNT. Delete the pinned block itself. The GATE_MIN_ASSERTIONS floor is
    # the only thing that makes a silent truncation loud rather than clean-looking.
    delete_block(TEST, 'if [[ ! -f "$APPLY_WF" ]]; then')

# ---- dispatch, authority and stub-fidelity rows ------------------------------------------------
elif case == 'D1':
    # THE HARNESS'S OWN DISPATCH. Neuter fail(). Measured BEFORE task 8.1's correction: this
    # reported `127 passed, 0 failed`, exit 0, with the known-negative self-test GREEN, because
    # that self-test redefined fail() inside its own subshell and so could not observe the real
    # one being neutered.
    sub(TEST, 'fail() { echo "  FAIL: $1"; fail=$((fail + 1)); }', 'fail() { :; }')

elif case == 'D2':
    # AUTHORITY / ROOT INPUT. The workflow's `if:` literals are validated against what
    # infra-config-verify.sh can EMIT, so the emitter is the guard's root input. Delete the output
    # the whole re-push chain is keyed on: every downstream step then silently skips and the job
    # greens having verified nothing — #6594's latched false-green, reintroduced by its remedy.
    sub(VERIFY, '        echo "repush_needed=true" >> "$GITHUB_OUTPUT"\n', '')

elif case == 'S1':
    # HARNESS STUBBING. Corrupt the production curl invocation's URL. A PATH stub that answers
    # identically regardless of argv puts the test seam ABOVE the code under test, and the query
    # shape then ships unpinned.
    sub(VERIFY, '"https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status"',
                '"https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-STATUS-TYPO"')

else:
    die('unknown case id')
PYEOF
}

# --- child mode (one row) ----------------------------------------------------------------------
# Rows are independent by construction — each gets its own sandbox copy — so they run
# concurrently. The gate suite alone is ~13 s, and 16 sequential rows would put this battery at
# ~4 min on the merge-gate critical path. Self-invocation keeps the mutator definitions
# single-sourced rather than duplicating them into a helper script.
#
# The child writes ONE result line to a file and never prints to stdout, so the parent renders
# rows in matrix order rather than completion order. Interleaved output from a parallel fan-out is
# how a battery's verdict becomes unreadable at exactly the moment it matters.
if [[ "${1:-}" == "--row" ]]; then
  _id="$2"; _suite="$3"; _want_rc="$4"; _marker="$5"; _result="$6"; _pristine="$7"

  _box="$(mktemp -d -t "repushmut-$_id.XXXXXXXX")" || {
    printf 'SETUPFAIL|%s|0|mktemp box\n' "$_id" > "$_result"; exit 0; }
  cp -a "$_pristine/." "$_box/" || {
    printf 'SETUPFAIL|%s|0|cp box\n' "$_id" > "$_result"; rm -rf "$_box"; exit 0; }

  if ! _muterr="$(_mutate_impl "$_box" "$_id" 2>&1)"; then
    printf 'SETUPFAIL|%s|0|mutator did not apply: %s\n' "$_id" "${_muterr//|/ }" > "$_result"
    rm -rf "$_box"; exit 0
  fi

  # Prove the mutation LANDED, against the PRISTINE copy — never against git HEAD, which is
  # legitimately dirty mid-PR. A mutation that did not land reports the baseline, and a baseline
  # result is indistinguishable from "the suite did not detect this".
  if diff -rq "$_pristine" "$_box" >/dev/null 2>&1; then
    printf 'SETUPFAIL|%s|0|mutation changed nothing (the mutator is a no-op)\n' "$_id" > "$_result"
    rm -rf "$_box"; exit 0
  fi

  _log="$(mktemp -t "repushmut-$_id.XXXXXXXX.log")" || {
    printf 'SETUPFAIL|%s|0|mktemp log\n' "$_id" > "$_result"; rm -rf "$_box"; exit 0; }
  bash "$_box/$_suite" > "$_log" 2>&1; _rc=$?

  # Assert the EXPECTED rc, not merely non-zero, AND that a check NAMING the property reported.
  # "Some assertion failed" is not detection: it is equally compatible with a suite that has
  # become incapable of passing for an unrelated reason.
  _why=""
  [[ "$_rc" == "$_want_rc" ]] || _why="rc=$_rc want=$_want_rc"
  if [[ -z "$_why" ]] && ! grep -qF -- "$_marker" "$_log"; then
    _why="rc ok but no check named the property"
  fi
  if [[ -n "$_why" ]]; then
    printf 'NOTASEXPECTED|%s|%s|%s\n' "$_id" "$_rc" "$_why" > "$_result"
    grep -E '^  FAIL|FLOOR|self-test' "$_log" | head -3 | sed 's/^/          /' >> "$_result"
  else
    printf 'RED|%s|%s|\n' "$_id" "$_rc" > "$_result"
  fi
  rm -rf "$_box" "$_log"
  exit 0
fi

# ================================================================================================
# parent mode
# ================================================================================================
echo "infra-config-repush-mutation.test.sh (#7104 PR-B — Guard 1 + Guard 2)"

for tool in python3 jq git diff; do
  command -v "$tool" >/dev/null || { echo "SETUP-FAIL: $tool not on PATH" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "SETUP-FAIL: python3 pyyaml unavailable" >&2; exit 2; }

# --- the minimal skeleton the two suites read ---------------------------------------------------
# Both resolve REPO_ROOT as SCRIPT_DIR/../../.., so the sandbox must reproduce that shape.
# Copying the top-level TRACKED files only: apps/web-platform/infra also holds an untracked
# .terraform provider cache (~168 MB), and `cp -a` of the whole directory would put that on the
# critical path of every row.
PRISTINE="$(mktemp -d -t repushmut-pristine.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp pristine" >&2; exit 2; }
RESULTS="$(mktemp -d -t repushmut-results.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp results" >&2; exit 2; }
trap 'rm -rf "$PRISTINE" "$RESULTS"' EXIT
mkdir -p "$PRISTINE/apps/web-platform/infra" "$PRISTINE/.github/workflows" \
  || { echo "SETUP-FAIL: mkdir skeleton" >&2; exit 2; }

copied=0
while IFS= read -r rel; do
  cp "$REPO_ROOT/$rel" "$PRISTINE/apps/web-platform/infra/" || { echo "SETUP-FAIL: cp $rel" >&2; exit 2; }
  copied=$((copied + 1))
done < <(git -C "$REPO_ROOT" ls-files apps/web-platform/infra | awk -F/ 'NF==4')
# Cardinality floor on the SETUP itself: an empty or truncated skeleton would make every row below
# a statement about a directory that does not contain the code under test.
[[ "$copied" -ge 50 ]] || { echo "SETUP-FAIL: copied only $copied infra files (expected >= 50)" >&2; exit 2; }

for wf in infra-validation.yml apply-deploy-pipeline-fix.yml; do
  cp "$REPO_ROOT/.github/workflows/$wf" "$PRISTINE/.github/workflows/" \
    || { echo "SETUP-FAIL: cp $wf" >&2; exit 2; }
done

# --- the UNMUTATED control ----------------------------------------------------------------------
# A red baseline voids every row below: each would then be reporting the baseline's failure and
# calling it detection. Run it first, on the pristine skeleton, for BOTH suites.
for suite in "$GATE_SUITE" "$VERIFY_SUITE"; do
  log="$(mktemp -t repushmut-base.XXXXXXXX.log)" || { echo "SETUP-FAIL: mktemp base log" >&2; exit 2; }
  bash "$PRISTINE/$suite" > "$log" 2>&1; base_rc=$?
  if [[ "$base_rc" -ne 0 ]]; then
    echo "SETUP-FAIL: baseline for $(basename "$suite") is NOT green (rc=$base_rc) — every mutation verdict below would be meaningless" >&2
    grep -E 'FAIL' "$log" >&2
    rm -f "$log"; exit 2
  fi
  echo "  baseline $(basename "$suite"): GREEN (rc=0) — $(grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1)"
  rm -f "$log"
done
echo

# --- the matrix ---------------------------------------------------------------------------------
# id | suite | expected-rc | marker the failing check must print | description
ROWS=(
  "G1-1|$GATE_SUITE|1|#7104 P1:|G1 r1 dpf-replaced clause dropped (primary)"
  "G1-2|$GATE_SUITE|1|#7104 P2b:|G1 r2 polarity guard relaxed off ^(true|false)"
  "G1-3|$GATE_SUITE|1|#7104 P4:|G1 r3 freshness -lt -> -le (equality re-pushes)"
  "G1-4|$GATE_SUITE|1|the predicate is not defined|G1 r4 predicate renamed (OWN DISPATCH)"
  "G1-5|$GATE_SUITE|1|#7104 P5:|G1 r5 second success member: unreadable frame"
  "G1-6|$GATE_SUITE|1|#7104 P4:|G1 r6 builder default supplies asserted value"
  "G1-7|$GATE_SUITE|1|#7104 P3:|G1 r7 predicate refuses always (FLOOR)"
  "G2-1|$GATE_SUITE|1|is not terminal|G2 r1 content assert moved INSIDE the poll loop"
  "G2-2|$GATE_SUITE|1|#7104 Guard 2 (5)(6):|G2 r2 predicate decision inlined in the script"
  "G2-3|$GATE_SUITE|1|#7104 Guard 2 (7):|G2 r3 a SECOND production apply site added"
  "G2-4|$GATE_SUITE|1|#7104 Guard 2 (5)(6):|G2 r6 predicate call wrapped in a function"
  "G2-5|$GATE_SUITE|1|done-lines-strictly-between=2|G2 r5 nested done inside the pinned region"
  "G2-6|$GATE_SUITE|1|#7104 Guard 2 (8):|G2 r6' write added to the sourced library"
  "G2-7|$GATE_SUITE|1|assertion-count floor|G2 r7 the pin block itself deleted"
  "D1|$GATE_SUITE|1|harness self-test|harness fail() neutered (OWN DISPATCH)"
  "D2|$GATE_SUITE|1|#7104 Guard 1:|repush_needed output never written"
  "S1|$VERIFY_SUITE|1|#7104 I1 pass 1:|production status URL corrupted (stub argv)"
)

# Bounded fan-out. Rows are hermetic, but this machine runs parallel worktrees and the suites
# each build their own mktemp sandboxes, so the cap stays well under the core count.
JOBS=$(( $(nproc 2>/dev/null || echo 4) - 2 ))
[[ "$JOBS" -gt 4 ]] && JOBS=4
[[ "$JOBS" -lt 1 ]] && JOBS=1
echo "running ${#ROWS[@]} rows, ${JOBS} at a time (fresh sandbox copy each; expected rc AND the named check are both asserted):"

for row in "${ROWS[@]}"; do
  IFS='|' read -r id suite want marker _desc <<< "$row"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$suite" "$want" "$marker" "$RESULTS/$id" "$PRISTINE"
done | xargs -P "$JOBS" -d '\n' -I{} bash -c 'IFS=$'"'"'\t'"'"' read -r a b c d e f <<< "{}"; bash "$0" --row "$a" "$b" "$c" "$d" "$e" "$f"' "${BASH_SOURCE[0]}"

RED=0; NOTASEXPECTED=0; N=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r id _suite _want marker desc <<< "$row"
  N=$((N + 1))
  rf="$RESULTS/$id"
  if [[ ! -s "$rf" ]]; then
    echo "SETUP-FAIL: row $id produced no result file — the child never completed" >&2
    exit 2
  fi
  IFS='|' read -r status _rid rc why < <(head -1 "$rf")
  case "$status" in
    SETUPFAIL)
      echo "SETUP-FAIL: row $id — $why" >&2
      exit 2 ;;
    RED)
      RED=$((RED + 1))
      printf '  %-5s %-52s RED rc=%-2s [%s]\n' "$id" "$desc" "$rc" "$marker" ;;
    *)
      NOTASEXPECTED=$((NOTASEXPECTED + 1))
      printf '  %-5s %-52s NOT-AS-EXPECTED (%s)\n' "$id" "$desc" "$why"
      tail -n +2 "$rf" ;;
  esac
done

echo
echo "---"
echo "infra-config-repush-mutation.test.sh: $RED/$N mutations behaved as expected, $NOTASEXPECTED did not"
# Cardinality floor: a battery that silently ran zero rows would otherwise print 0/0 and exit 0.
if [[ "$N" -lt 17 ]]; then
  echo "  FAIL: only $N rows ran, expected >= 17 (7 Guard 1 + 7 Guard 2 + 3 dispatch/authority/stub)" >&2
  exit 1
fi
[[ "$NOTASEXPECTED" -eq 0 ]] || exit 1
echo "OK"
