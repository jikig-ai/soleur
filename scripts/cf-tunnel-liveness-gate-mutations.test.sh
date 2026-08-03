#!/usr/bin/env bash
# Mutation battery for the cf-tunnel-ssh-bridge liveness gate (#7103 R5(b)).
#
# WHAT THIS IS FOR, AND WHAT IT IS NOT.
#
# #7133 re-anchored the W1-W10 assertions in check-cloudflare-token-drift.test.sh onto emissions
# and call shapes rather than bare tokens. That work is correct and shipped. What did NOT ship is
# anything that keeps it correct: an assertion can rot into vacuity silently, and the way you
# discover it is an incident, not a red build. So this battery does one thing — it deletes,
# moves, and retargets the gate in a sandbox and requires the sibling suite to NOTICE, by name.
#
# A mutant that survives is a HARD FAILURE here. It means the assertion nominally covering it
# cannot actually fail, and the gate is protected by nothing.
#
# THREE RULES, each learned from a battery that lied:
#
#   1. NEVER mutate a tracked file. Everything happens in a mktemp -d sandbox holding copies.
#      The suite resolves its own REPO_ROOT from $BASH_SOURCE, so running the COPY there makes it
#      read the sandbox's .github tree and nothing else. A `git status --porcelain` check at the
#      end proves the working tree was untouched.
#
#   2. ASSERT THE MESSAGE, NOT THE EXIT CODE. A mutant that reds for an unrelated reason — a
#      syntax error, a missing file, a different assertion entirely — looks identical to one that
#      was caught, and a battery graded on exit codes reports "all caught" while pinning nothing.
#      Each arm below requires the SPECIFIC W-assertion to be the one that failed.
#
#   3. VERIFY THE MUTATION LANDED. A `sed` whose anchor has drifted silently no-ops, the suite
#      stays green, and the arm reports a surviving mutant that was never actually applied — or
#      worse, an arm that "passes" because nothing changed. assert_landed diffs against a
#      pristine copy and aborts the whole battery on a no-op.
#
# Modelled on .github/scripts/test/test-infra-suite-registration-mutations.sh.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE_REL="scripts/check-cloudflare-token-drift.test.sh"
BRIDGE_REL=".github/actions/cf-tunnel-ssh-bridge/action.yml"
APPLY_REL=".github/workflows/apply-web-platform-infra.yml"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

SB="$(mktemp -d)" || { echo "FATAL: sandbox mktemp failed"; exit 2; }
trap 'rm -rf "$SB"' EXIT

# --- Build the sandbox ----------------------------------------------------------------------
# Copy the whole scripts/ and .github/ trees so the suite's own path resolution works unchanged.
# Any copy failure aborts: a battery that runs against a half-built sandbox does not degrade into
# a missing result, it degrades into a confident wrong one.
mkdir -p "$SB/repo" || { echo "FATAL: mkdir"; exit 2; }
cp -a "$REPO_ROOT/scripts" "$SB/repo/scripts" || { echo "FATAL: cp scripts"; exit 2; }
cp -a "$REPO_ROOT/.github" "$SB/repo/.github" || { echo "FATAL: cp .github"; exit 2; }
cp -a "$SB/repo" "$SB/pristine" || { echo "FATAL: cp pristine"; exit 2; }
[[ -f "$SB/repo/$SUITE_REL" ]]  || { echo "FATAL: suite missing from sandbox"; exit 2; }
[[ -f "$SB/repo/$BRIDGE_REL" ]] || { echo "FATAL: bridge action missing from sandbox"; exit 2; }

# Written as explicit ifs rather than `A && B || C`: BOTH steps must be checked. A restore that
# removed the sandbox but failed to repopulate it would leave the next arm running against an
# empty tree, where every assertion fails and the arm reports its mutant "caught".
restore() {
  if ! rm -rf "$SB/repo"; then echo "FATAL: restore could not clear the sandbox"; exit 2; fi
  if ! cp -a "$SB/pristine" "$SB/repo"; then echo "FATAL: restore could not repopulate the sandbox"; exit 2; fi
}

# Run the sibling suite against the sandbox. Only the W-section verdict lines matter here.
run_suite() { ( cd "$SB/repo" && bash "$SUITE_REL" ) > "$SB/out.log" 2>&1; echo $?; }

# assert_landed <file> — the mutation must have produced a real diff.
assert_landed() {
  local rel="$1"
  if diff -q "$SB/repo/$rel" "$SB/pristine/$rel" >/dev/null 2>&1; then
    echo "  FATAL: mutation did not land in $rel (anchor drifted). Aborting rather than reporting a survivor that was never applied."
    exit 2
  fi
}

# arm <name> <label> <expected-message-regex>
#
# Requires non-zero AND that the SPECIFIC assertion fired, matched on its failure MESSAGE.
# Matching on the W label would not work and the reason is instructive: the suite echoes
# "W6: ..." as a section HEADER but its fail() text never repeats the label, so a label match
# silently never fires and every arm reports "reddened for the wrong reason". Matching the
# message is also the stronger form — it pins what the assertion actually says, so an assertion
# rewritten to check something else stops satisfying its arm.
# EVERY named regex must match — this used to take ONE regex, and M1 passed it an ALTERNATION
# ("scoped invocation at command position|must EMIT ci_ssh_access_denied") under the label
# "W1/W3/W4". Three consequences, all bad: the label claimed three assertions while the regex
# was an OR of two; W4's failure text appeared in NEITHER branch, so W4 was never verified at
# all; and W1 — the assertion whose own comment records that it was previously satisfied by a
# header comment — could be made fully vacuous while this battery still reported the mutant
# "caught, identified by its own message". Verified: neutering W1 alone left the battery 8/8.
#
# Requiring ALL of them is the difference between "something reddened" and "the assertion I
# named reddened", which is this file's own Rule 2.
arm() {
  local name="$1" label="$2"; shift 2
  local rc fails re missing=""
  rc=$(run_suite)
  if [[ "$rc" == "0" ]]; then
    fail "$name — SURVIVED. The assertion nominally covering it ($label) cannot fail; the gate is protected by nothing."
    return
  fi
  fails=$(grep -E '^[[:space:]]*FAIL:' "$SB/out.log")
  for re in "$@"; do
    grep -qE "$re" <<<"$fails" || missing+=" [$re]"
  done
  if [[ -z "$missing" ]]; then
    pass "$name — caught by $label, and EVERY named assertion fired"
  else
    fail "$name — the suite reddened but these named assertions did NOT fire:$missing. A mutant caught for the wrong reason is indistinguishable from one that was missed. FAILures were: $(head -3 <<<"$fails" | tr '\n' ' ')"
  fi
}

# The tree-cleanliness check below compares two `git status` samples. If git cannot answer —
# REPO_ROOT is not a repo, git is absent, the 2>/dev/null swallows a real error — BOTH samples
# are the empty string and the comparison passes having verified nothing. Demonstrated: run this
# file from a non-repo sandbox and it still printed "the working tree is unchanged by this run".
# A check that cannot fail is indistinguishable from one that passed, so require the instrument
# to work before trusting its answer.
if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "FATAL: $REPO_ROOT is not a git repository, so the working-tree escape check below cannot run. Refusing to report a sandbox-safety result this battery did not establish." >&2
  exit 2
fi
TREE_BEFORE="$(git -C "$REPO_ROOT" status --porcelain -- scripts .github 2>/dev/null)"

echo "=== cf-tunnel liveness-gate mutation battery (#7103 R5(b)) ==="

# --- M7: CONTROL FIRST ----------------------------------------------------------------------
# Before any mutant is graded, the unmutated sandbox must be green. Without this, a sandbox that
# is broken for an unrelated reason makes EVERY arm below "catch" its mutant, and the battery
# reports a perfect score while testing nothing.
CONTROL_RC=$(run_suite)
if [[ "$CONTROL_RC" == "0" ]]; then
  pass "M7 control: the unmutated sandbox is green (every arm below is graded against a working baseline)"
else
  fail "M7 control: the UNMUTATED sandbox is already red — every mutation arm below would be meaningless. Suite output: $(grep -E '^[[:space:]]*FAIL:' "$SB/out.log" | head -3 | tr '\n' ' ')"
  echo "---"; echo "cf-tunnel-liveness-gate-mutations.test.sh: $PASS passed, $FAIL failed"; exit 1
fi

# --- M1: delete the entire gate step, leaving the header comment intact ---------------------
# The comment is left deliberately. An assertion anchored on prose rather than on an emission
# would still find its token and pass — which is precisely the false-anchor class #7133 fixed.
restore
python3 - "$SB/repo/$BRIDGE_REL" <<'PY'
import sys, io, re
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
i = s.index('    - name: Gate — CF Access must still admit the ci_ssh credential')
head = s[:i]
# Keep a header comment mentioning the gate; drop the step body entirely.
io.open(p, "w", encoding="utf-8").write(
    head + "    # Gate — CF Access must still admit the ci_ssh credential (step removed by mutation)\n")
PY
assert_landed "$BRIDGE_REL"
arm "M1 gate step deleted (header comment left intact)" "W1+W3+W4" \
    "scoped invocation at command position" \
    "must EMIT ci_ssh_access_denied" \
    "must branch on the JSON verdict"

# --- M3: the gate is no longer the final step -----------------------------------------------
restore
python3 - "$SB/repo/$BRIDGE_REL" <<'PY'
import sys, io
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s = s.rstrip("\n") + "\n\n    - name: Innocuous trailing step (mutation)\n      shell: bash\n      run: echo ok\n"
io.open(p, "w", encoding="utf-8").write(s)
PY
assert_landed "$BRIDGE_REL"
arm "M3 a step runs AFTER the gate (gate no longer final)" "W6" \
    "must be the composite.s final step"

# --- M4: membership drift with the COUNT held constant --------------------------------------
# Repoint one caller at a different action and add a spare `uses:` elsewhere, so the total call
# count is unchanged. A cardinality-only assertion passes this; only a membership assertion
# catches it. This arm exists precisely because it is the one a lazy battery waves through.
restore
python3 - "$SB/repo/$APPLY_REL" "$SB/repo/.github/workflows" <<'PY'
import sys, io, os, re
target, wfdir = sys.argv[1], sys.argv[2]
s = io.open(target, encoding="utf-8").read()
needle = "uses: ./.github/actions/cf-tunnel-ssh-bridge"
assert needle in s, "anchor missing in " + target
s = s.replace(needle, "uses: ./.github/actions/some-other-action", 1)
io.open(target, "w", encoding="utf-8").write(s)
# Add a compensating call site in a DIFFERENT workflow so the total stays 6.
donor = os.path.join(wfdir, "git-data-cutover.yml")
d = io.open(donor, encoding="utf-8").read()
i = d.index("      " + needle)
line = d[i:d.index("\n", i) + 1]
io.open(donor, "w", encoding="utf-8").write(d[:i] + line + d[i:])
PY
assert_landed "$APPLY_REL"
arm "M4 caller membership drifts while the total count is held constant" "W7" \
    "bridge callers drifted"

# --- M5: drop the -replace target, leaving the dispatch-input prose -------------------------
restore
python3 - "$SB/repo/$APPLY_REL" <<'PY'
import sys, io, re
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
out, n = re.subn(r'(?m)^.*-replace=cloudflare_zero_trust_access_service_token\.ci_ssh.*\n', '', s)
assert n > 0, "no -replace line to delete"
io.open(p, "w", encoding="utf-8").write(out)
PY
assert_landed "$APPLY_REL"
arm "M5 the ci_ssh -replace target is deleted (dispatch prose left behind)" "W9" \
    "needs the ci-ssh-token-replace enum option"

# --- M6: retarget the escalation to a DIFFERENT verdict --------------------------------------
# The escalation must be bound to DEAD. Pointing it at 'unverifiable' means a dead credential
# escalates to nobody while the workflow still looks fully wired.
restore
python3 - "$SB/repo/.github/workflows/scheduled-terraform-drift.yml" <<'PY'
import sys, io, re
# TARGETED, not first-match. W10 scopes its check to the `if:` within 3 lines of the step named
# "Open or update an action-required issue (token drift — DEAD credential)"; the file contains
# other `verdict == 'dead'` guards, so a count=1 replace mutates a site NO assertion covers and
# the arm reports a survivor that is really a mis-aimed mutation. The first draft of this arm did
# exactly that.
p = sys.argv[1]
lines = io.open(p, encoding="utf-8").read().split("\n")
step = next(i for i, l in enumerate(lines)
            if l.startswith("      - name: Open or update an action-required issue (token drift"))
for i in range(step, min(step + 4, len(lines))):
    if lines[i].lstrip().startswith("if:") and "dead" in lines[i]:
        lines[i] = lines[i].replace("'dead'", "'unverifiable'").replace('"dead"', '"unverifiable"')
        break
else:
    raise AssertionError("no dead-verdict guard within W10's 3-line scope of the DEAD filer step")
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
assert_landed ".github/workflows/scheduled-terraform-drift.yml"
arm "M6 the escalation is rebound from the DEAD verdict to 'unverifiable'" "W10" \
    "must itself be guarded on verdict == .dead."

# --- M8: ANTI-VACUITY — delete every assertion call ------------------------------------------
# The sibling suite carries an assertion floor. Gutting its pass/fail calls must NOT yield a
# clean exit 0, or "N/N passed" could be produced by a suite that asserts nothing — the exact
# shape that let a PR's only deliverable be deleted at "20/20 passed".
restore
python3 - "$SB/repo/$SUITE_REL" <<'PY'
import sys, io, re
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
# Neuter the reporting helpers rather than deleting call sites, so the file still parses.
out, n = re.subn(r'(?m)^pass\(\) \{[^\n]*\n', 'pass() { :; }\n', s, count=1)
assert n > 0, "pass() definition not found"
io.open(p, "w", encoding="utf-8").write(out)
PY
assert_landed "$SUITE_REL"
M8_RC=$(run_suite)
if [[ "$M8_RC" == "0" ]]; then
  fail "M8 anti-vacuity: the suite exited 0 with its pass() accounting gutted — an assertion floor that permits zero assertions permits deleting the cases under review"
else
  pass "M8 anti-vacuity: a suite that records no passing assertions cannot exit 0 (the floor holds)"
fi

# --- 6.3: the working tree must be untouched -------------------------------------------------
# Everything above ran on copies. If any arm reached a tracked file, this battery has been
# rewriting the repository it is meant to be testing.
restore
# Compared against a snapshot taken BEFORE any mutation, not against absolute cleanliness: this
# battery is itself an untracked file under scripts/, so demanding a pristine tree would fail on
# its own existence. What matters is that nothing CHANGED while it ran.
TREE_AFTER="$(git -C "$REPO_ROOT" status --porcelain -- scripts .github 2>/dev/null)"
if [[ "$TREE_AFTER" == "$TREE_BEFORE" ]]; then
  pass "the working tree is unchanged by this run (every mutation stayed inside the sandbox)"
else
  fail "the working tree CHANGED under scripts/ or .github/ while this battery ran — a mutation escaped the sandbox. Diff: $(diff <(printf '%s' "$TREE_BEFORE") <(printf '%s' "$TREE_AFTER") | head -5 | tr '\n' ' ')"
fi

echo "---"
echo "cf-tunnel-liveness-gate-mutations.test.sh: $PASS passed, $FAIL failed"
# --- Anti-vacuity floor ----------------------------------------------------------------------
# THE RULE THIS FILE IMPOSES ON ITS SIBLING, APPLIED TO ITSELF. M8 enforces an assertion floor on
# check-cloudflare-token-drift.test.sh, and this battery — whose entire deliverable is "the
# sibling suite cannot rot into vacuity" — shipped without one. Verified: neuter pass()/fail()
# here and it reports "0 passed, 0 failed", prints OK, and exits 0, which is byte-indistinguishable
# from a clean run. Anything that strands the arm block (an early exit, a failed restore, a
# renamed SUITE_REL) produced that same output.
#
# A FLOOR, not equality: the count is developer-incremented, so `-eq` would turn every added arm
# into a spurious red — the failure mode that gets a floor deleted rather than updated.
MIN_ASSERTIONS=8
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) arms ran, expected >= $MIN_ASSERTIONS — this battery was stranded, not clean." >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
echo "OK"
