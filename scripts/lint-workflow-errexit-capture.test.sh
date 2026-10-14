#!/usr/bin/env bash
# Unit suite for scripts/lint-workflow-errexit-capture.py.
#
# The fixture set IS the executable specification of the rule. It is written so that every
# must-NOT-fire case carries a POSITIVE CONTROL in the same file: a known-firing shape whose
# line the linter must name while leaving the guarded one alone. Without that control, a
# must-not-fire assertion passes just as happily against a linter that has stopped working
# altogether -- which is the failure mode a "0 findings" gate is most prone to, since a broken
# detector and a clean tree produce byte-identical output.
#
# Read together with the DIRECTION OF ERROR note in the linter: false negatives are preferred,
# so the must-not-fire set is deliberately generous and the must-fire set is the load-bearing
# half.
set -uo pipefail

# A direct invocation of this file inherits the bare /tmp, which on this machine is a
# machine-global 4 GiB tmpfs shared with every parallel worktree; test-all.sh and
# run-registered-suites.sh both default to /var/tmp for exactly that reason. A sandbox-building
# suite whose verdicts depend on another session's disk usage is not a gate.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="${ERREXIT_LINT_SCRIPT:-$SCRIPT_DIR/lint-workflow-errexit-capture.py}"

TMP="$(mktemp -d -t errexit-lint.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PASS=0
FAIL=0
# Anti-vacuity floor. Raise deliberately when adding fixtures.
MIN_ASSERTIONS="${ERREXIT_LINT_MIN_ASSERTIONS:-38}"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1"
  [[ $# -gt 1 ]] && echo "        expected: $2"
  [[ $# -gt 2 ]] && echo "        actual:   $3"
  FAIL=$((FAIL + 1))
}

if [[ ! -f "$LINTER" ]]; then
  echo "FATAL: linter not found at $LINTER"
  exit 2
fi

# --- fixture plumbing -------------------------------------------------------
# mkfix <name> -- create a fixture root and echo its path. Every setup command is checked:
# a harness that fails to SET UP must abort, never silently score the PREVIOUS fixture's
# tree and report a verdict about the linter that it never actually measured.
mkfix() {
  # Two `local`s deliberately: within a single `local a=… b=$a`, the first assignment has not
  # taken effect when the second is expanded (SC2318), so `root` would silently become
  # "$TMP/fx-" for every fixture and they would all share one directory.
  local name="$1"
  local root="$TMP/fx-$name"
  rm -rf "$root" || { echo "FATAL: rm -rf $root failed"; exit 2; }
  mkdir -p "$root/.github/workflows" || { echo "FATAL: mkdir $root failed"; exit 2; }
  printf '%s' "$root"
}

# run_lint <root> -- sets LINT_OUT and LINT_RC.
#
# NOT called as `out="$(run_lint ...)"`. Command substitution runs the function in a SUBSHELL,
# so an rc it assigns to a caller-visible variable is discarded and every caller reads the
# stale outer value -- which here meant every must-FIRE assertion compared against rc=0 and
# failed while the linter was in fact reporting the finding correctly. A function is safe to
# call as `$( )` only when its ONLY contract is stdout; this one also has to report a status,
# so it sets globals and returns nothing.
LINT_RC=0
LINT_OUT=""
run_lint() {
  LINT_OUT="$(python3 "$LINTER" --root "$1" --quiet 2>&1)"
  LINT_RC=$?
  printf '%s\n' "$LINT_OUT" > "$TMP/out.txt"
}

# assert_fires <label> <root> <line-number-that-must-be-named>
assert_fires() {
  local label="$1" root="$2" want_line="$3"
  run_lint "$root"
  if [[ "$LINT_RC" != "1" ]]; then
    fail "$label" "rc=1 (a finding)" "rc=$LINT_RC; output: $(tr '\n' ' ' < "$TMP/out.txt")"
    return 0
  fi
  # grep against a FILE, never `printf | grep -q`: under pipefail an early match makes grep
  # close the pipe, the producer takes SIGPIPE (141), and the pipeline reports failure even
  # though the pattern matched. On a NEGATIVE assertion that same shape fails OPEN.
  if grep -qE ":${want_line}:" "$TMP/out.txt"; then
    pass "$label"
  else
    fail "$label" "a finding at line ${want_line}" "$(tr '\n' ' ' < "$TMP/out.txt")"
  fi
}

# assert_clean <label> <root>
assert_clean() {
  local label="$1" root="$2"
  run_lint "$root"
  if [[ "$LINT_RC" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "rc=0 (no findings)" "rc=$LINT_RC; $(tr '\n' ' ' < "$TMP/out.txt")"
  fi
}

# assert_not_named <label> <root> <line-that-must-NOT-be-named>
# The must-not-fire half of a positive-control fixture.
assert_not_named() {
  local label="$1" root="$2" bad_line="$3"
  run_lint "$root"
  if grep -qE ":${bad_line}:" "$TMP/out.txt"; then
    fail "$label" "no finding at line ${bad_line}" "$(tr '\n' ' ' < "$TMP/out.txt")"
  else
    pass "$label"
  fi
}

echo "=== lint-workflow-errexit-capture fixtures ==="

# --- MUST FIRE --------------------------------------------------------------

# F1 -- the canonical shape: a BARE COMMAND followed by rc=$? on the next line.
# Nine of the seventeen real sites look exactly like this, and they are precisely what an
# assignment-anchored rule (the first draft) was structurally blind to.
r="$(mkfix bare)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          terraform plan -no-color
          rc=$?
          echo "rc=$rc"
YAML
assert_fires "F1 bare command + next-line rc=\$? FIRES" "$r" 9

# F2 -- same-line, semicolon-separated. The canonical instance in the workflow that motivated
# this gate is `out="$(...)"; rc=$?`, so a next-line-only detector misses the headline bug.
r="$(mkfix sameline)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          out="$(bash scripts/checker.sh 2>&1)"; rc=$?
          echo "$out"
YAML
assert_fires "F2 same-line \`cmd; rc=\$?\` FIRES" "$r" 9

# F3 -- ${PIPESTATUS[n]}. Two real sites, including one of the six occurrences this gate is
# justified by, read PIPESTATUS and never touch $?. A $?-only rule is blind to them.
r="$(mkfix pipestatus)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          bash scripts/producer.sh | tee /tmp/out.log
          rc=${PIPESTATUS[0]}
          echo "rc=$rc"
YAML
assert_fires "F3 \${PIPESTATUS[0]} read FIRES" "$r" 9

# F4 -- `shell: bash`. THE HIGHEST-VALUE ANTI-FALSE-NEGATIVE CASE. Writing `shell: bash` reads
# like taking control of the shell contract and changes nothing: Actions maps it to
# `bash --noprofile --norc -eo pipefail {0}`, so errexit is still on.
r="$(mkfix shellbash)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - shell: bash
        run: |
          set -uo pipefail
          terraform plan -no-color
          rc=$?
YAML
assert_fires "F4 \`shell: bash\` does NOT clear -e, so it FIRES" "$r" 10

# F5 -- a `set +e` cancelled by a later COMPOUND re-arm. A matcher keyed on the literal string
# `set -e` misses `set -euo pipefail`, which would let this read as "still cleared" while
# errexit is in fact back on -- shipping an inert fix that looks correct in the diff.
r="$(mkfix rearm)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set +e
          first_thing
          first_rc=$?
          set -euo pipefail
          terraform plan -no-color
          rc=$?
YAML
assert_fires "F5 compound \`set -euo pipefail\` re-arms, so the later capture FIRES" "$r" 12
assert_not_named "F5b the capture BEFORE the re-arm stays clean" "$r" 9

# F6 -- a body with no `set` line at all is not exempt (the real infra-validation.yml shape).
r="$(mkfix noset)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          PLAN_OUTPUT=$(terraform plan -no-color)
          PLAN_EXIT=$?
          echo "$PLAN_EXIT"
YAML
assert_fires "F6 body with no \`set\` line at all FIRES" "$r" 8

# F7 -- a MULTI-LINE command substitution. The real inngest-health site opens
# `response="$(curl \` and reads `curl_rc=$?` nine physical lines later; a physical-line
# matcher misses it entirely.
r="$(mkfix continuation)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          response="$(curl --silent \
            --request POST \
            --url "https://example.invalid/q" \
            --max-time 15)"
          curl_rc=$?
          echo "$curl_rc"
YAML
assert_fires "F7 multi-line \`\\\`-continued substitution FIRES at the opening line" "$r" 9

# F8 -- composite actions run their bodies under the same contract and must be scanned.
r="$(mkfix composite)"
mkdir -p "$r/.github/actions/thing" || { echo "FATAL: mkdir composite failed"; exit 2; }
cat > "$r/.github/actions/thing/action.yml" <<'YAML'
name: thing
runs:
  using: composite
  steps:
    - run: |
        set -uo pipefail
        do_the_thing
        rc=$?
      shell: bash
YAML
assert_fires "F8 composite action bodies are scanned and FIRE" "$r" 7

# F9-F15 -- the evasion shapes found by adversarial review. Every one of these was CLEAN
# against the first revision of the linter, and two of them (`echo "rc=$?"`) are live in the
# scanned tree at .github/workflows/fix-constraints-stage-a.yml:85 and :139 — i.e. the gate
# was reporting those files as scanned while structurally unable to see their captures.

# F9 -- the read is inside a QUOTED string. The old anchor required the identifier to be
# preceded by start-of-line, `[;&|]` or whitespace; a `"` is none of those.
r="$(mkfix quoted_read)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          terraform plan -no-color
          echo "rc=$?" >> "$GITHUB_OUTPUT"
YAML
assert_fires "F9 \`echo \"rc=\$?\"\` FIRES (the live fix-constraints shape)" "$r" 9

# F10 -- a quoted assignment, and the braced form.
r="$(mkfix quoted_assign)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          terraform plan -no-color
          rc="$?"
      - run: |
          set -uo pipefail
          terraform plan -no-color
          rc=${?}
YAML
assert_fires "F10 \`rc=\"\$?\"\` FIRES" "$r" 9
assert_fires "F10b \`rc=\${?}\` FIRES" "$r" 13

# F11 -- a bare `$?` read with no assignment at all. The docstring's own justification for
# anchoring on the read ("the code ITSELF proves the author expected to handle failure")
# applies verbatim here, so excluding it was a regex artifact, not a scope decision.
r="$(mkfix bare_read)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          terraform plan -no-color
          if [[ $? -ne 0 ]]; then echo "::error::failed"; fi
YAML
assert_fires "F11 a bare \`if [[ \$? -ne 0 ]]\` read FIRES" "$r" 9

# F12 -- a `set` line that also CARRIES the command. Falling through unconditionally on any
# SET_RE match made this a one-token bypass of the whole rule.
r="$(mkfix set_carries_cmd)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          set -x; terraform plan -no-color; rc=$?
YAML
assert_fires "F12 \`set -x; cmd; rc=\$?\` FIRES (a set line can carry a command)" "$r" 9

# F13 -- a FALSE heredoc opener inside a string or an arithmetic shift. The old scanner
# blanked every remaining line when no terminator followed, silently disarming the rest of
# the body — unbounded, and reachable from any `echo` documenting heredoc usage.
r="$(mkfix false_heredoc)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          echo "usage: send <<EOF"
          terraform plan -no-color
          rc=$?
      - run: |
          set -uo pipefail
          mask=$(( 1 << n ))
          terraform plan -no-color
          rc=$?
YAML
assert_fires "F13 a heredoc-looking string does not blank the body" "$r" 10
assert_fires "F13b an arithmetic \`<<\` shift does not blank the body" "$r" 15

# F14 -- long-form re-arm and long-form custom shell. A matcher keyed on flag CHARACTERS
# misses `set -o errexit` entirely, so a preceding `set +e` reads as still in effect.
r="$(mkfix long_form)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set +e
          set -o errexit
          terraform plan -no-color
          rc=$?
      - shell: bash -o errexit {0}
        run: |
          terraform plan -no-color
          rc=$?
YAML
assert_fires "F14 \`set -o errexit\` re-arms, so the later capture FIRES" "$r" 10
assert_fires "F14b \`shell: bash -o errexit {0}\` does NOT clear -e" "$r" 14

# F15 -- THE MIS-FIX. The remediation text says "clear errexit around the capture", so the
# most likely next edit puts `set +e` between the command and the read — where it protects
# nothing, because the command already ran armed. For a ${PIPESTATUS[n]} read it is strictly
# worse than the original bug: `set` is a builtin, so bash resets PIPESTATUS and the read
# yields 0 forever (the trap git-data-rung2-rehearsal.yml documents in-tree).
r="$(mkfix clear_after_command)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          terraform plan -no-color
          set +e
          rc=$?
      - run: |
          set -uo pipefail
          producer | tee /tmp/o.log
          set +e
          rc=${PIPESTATUS[0]}
YAML
assert_fires "F15 a clear placed AFTER the command FIRES (it protects nothing)" "$r" 9
assert_fires "F15b same, for a \${PIPESTATUS[n]} read (set also RESETS PIPESTATUS)" "$r" 14

# --- MUST NOT FIRE (each with a positive control in the same file) -----------
# The control is what distinguishes "the linter correctly exempted this" from "the linter is
# broken and finds nothing at all". Both produce a clean run; only the control tells them apart.

# G1 -- an explicit `set +e` protects the capture. Control: a second capture after a re-arm.
r="$(mkfix setplus)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          set +e
          terraform plan -no-color
          rc=$?
          set -e
          other_command
          other_rc=$?
YAML
assert_fires "G1 control: the post-re-arm capture still FIRES" "$r" 13
assert_not_named "G1b a \`set +e\`-protected capture does NOT fire" "$r" 10

# G2 -- `|| rc=$?` is the canonical protection idiom; the command cannot trip errexit.
# This is the exemption whose ORDERING mattered: testing it after stripping the separator
# turns `cmd ||` into `cmd |` and reports the safe idiom as a finding. Measured: that single
# mistake produced 13 false positives, in the two workflows verified as correctly protected.
r="$(mkfix orprotected)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          out="$(bash scripts/checker.sh 2>&1)" || rc=$?
          unprotected_command
          rc2=$?
YAML
assert_fires "G2 control: the unprotected capture in the same body FIRES" "$r" 10
assert_not_named "G2b \`|| rc=\$?\` does NOT fire" "$r" 9

# G3 -- a capture inside an `if` condition: the shell's own control flow consumes the status,
# so errexit never fires on it.
r="$(mkfix ifcond)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          if some_check; then
            rc=$?
            echo "$rc"
          fi
          later_command
          later_rc=$?
YAML
assert_fires "G3 control: the capture after the \`if\` block FIRES" "$r" 13
assert_not_named "G3b a capture inside an \`if\` condition does NOT fire" "$r" 9

# G4 -- a custom `shell:` whose command string genuinely omits -e.
r="$(mkfix customshell)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - shell: bash --noprofile --norc -uo pipefail {0}
        run: |
          terraform plan -no-color
          rc=$?
      - run: |
          terraform plan -no-color
          rc=$?
YAML
assert_fires "G4 control: the sibling step with no custom shell FIRES" "$r" 12
assert_not_named "G4b a custom \`shell:\` that omits -e does NOT fire" "$r" 9

# G5 -- prose. A comment DESCRIBING the bug must not satisfy or trip the gate; every real fix
# in this repo carries a rationale comment quoting the very shape it fixes.
r="$(mkfix comment)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          set +e
          # Without the clear above, `terraform plan` then `rc=$?` would abort AT the plan.
          # That is the whole defect: rc=$? never runs.
          terraform plan -no-color
          rc=$?
YAML
assert_clean "G5 a comment describing the bug does NOT fire" "$r"

# G6 -- a quoted heredoc body is data handed to stdin, not commands this shell runs.
r="$(mkfix heredoc)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -uo pipefail
          cat > /tmp/generated.sh <<'INNER'
          terraform plan -no-color
          rc=$?
          INNER
          real_command
          real_rc=$?
YAML
assert_fires "G6 control: the real capture after the heredoc FIRES" "$r" 13
assert_not_named "G6b a capture inside a quoted heredoc does NOT fire" "$r" 10

# --- the gate's own scope ---------------------------------------------------

# H1 -- a root with no workflows at all is a USAGE error (rc=2), never a pass. A gate that
# scanned nothing must not be indistinguishable from a gate that found nothing.
r="$(mkfix emptyroot)"
out="$(python3 "$LINTER" --root "$r" 2>&1)"; rc=$?
if [[ "$rc" == "2" ]]; then
  pass "H1 a root containing no workflows exits 2, not 0"
else
  fail "H1 a root containing no workflows exits 2, not 0" "rc=2" "rc=$rc ($out)"
fi

# H2 -- PER-KIND scanned counts against the real tree. A single total would let the composite
# actions silently drop out of scope while the number still looked healthy.
live="$(python3 "$LINTER" --root "$REPO_ROOT" 2>&1)"; live_rc=$?
printf '%s\n' "$live" > "$TMP/live.txt"
wf_n="$(sed -n 's/.*scanned \([0-9]*\) workflow.*/\1/p' "$TMP/live.txt" | head -1)"
ac_n="$(sed -n 's/.*, \([0-9]*\) composite action.*/\1/p' "$TMP/live.txt" | head -1)"
bd_n="$(sed -n 's/.*, \([0-9]*\) run: body.*/\1/p' "$TMP/live.txt" | head -1)"
if [[ "${wf_n:-0}" -ge 40 ]]; then
  pass "H2 the live scan reaches at least 40 workflows (got ${wf_n:-0})"
else
  fail "H2 the live scan reaches at least 40 workflows" ">=40" "${wf_n:-<unparsed>}"
fi
if [[ "${ac_n:-0}" -ge 7 ]]; then
  pass "H2b the live scan reaches at least 7 composite actions (got ${ac_n:-0})"
else
  fail "H2b the live scan reaches at least 7 composite actions" ">=7" "${ac_n:-<unparsed>}"
fi
if [[ "${bd_n:-0}" -ge 300 ]]; then
  pass "H2c the live scan reaches at least 300 run: bodies (got ${bd_n:-0})"
else
  fail "H2c the live scan reaches at least 300 run: bodies" ">=300" "${bd_n:-<unparsed>}"
fi

# H3 -- VERIFY THE VERIFIER. Re-introduce the real defect into a COPY of the tree and require
# the linter to catch it. Without this, every assertion above is compatible with a linter whose
# detection has been gutted: the must-fire fixtures could be satisfied by an over-eager rule and
# the must-not-fire ones by a rule that finds nothing, and H2 only proves it read some files.
r="$(mkfix regression)"
rm -rf "$r/.github" && cp -r "$REPO_ROOT/.github" "$r/.github" || { echo "FATAL: could not copy .github"; exit 2; }
target="$r/.github/workflows/scheduled-prod-version-drift.yml"
if [[ -f "$target" ]]; then
  python3 - "$target" <<'PY' || { echo "FATAL: H3 mutator failed"; exit 2; }
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
out, n = [], 0
for l in lines:
    if n == 0 and not l.lstrip().startswith("#") and re.match(r"^\s*set \+e\s*$", l):
        n += 1
        continue
    out.append(l)
assert n == 1, "H3 mutator removed no set +e STATEMENT (comment-only match?)"
open(p, "w").write("\n".join(out))
PY
  mout="$(python3 "$LINTER" --root "$r" --quiet 2>&1)"; mrc=$?
  printf '%s\n' "$mout" > "$TMP/mut.txt"
  if [[ "$mrc" == "1" ]] && grep -q 'scheduled-prod-version-drift.yml' "$TMP/mut.txt"; then
    pass "H3 re-introducing the real defect into a tree copy is CAUGHT"
  else
    fail "H3 re-introducing the real defect into a tree copy is CAUGHT" \
      "rc=1 naming scheduled-prod-version-drift.yml" "rc=$mrc; $(tr '\n' ' ' < "$TMP/mut.txt")"
  fi
  # And the unmutated copy must be clean, or H3 proves nothing about the mutation specifically.
  r2="$(mkfix regression_control)"
  rm -rf "$r2/.github" && cp -r "$REPO_ROOT/.github" "$r2/.github" || { echo "FATAL: could not copy .github"; exit 2; }
  cout="$(python3 "$LINTER" --root "$r2" --quiet 2>&1)"; crc=$?
  if [[ "$crc" == "0" ]]; then
    pass "H3b the same tree copy UNMUTATED is clean (so H3 measured the mutation)"
  else
    fail "H3b the same tree copy UNMUTATED is clean" "rc=0" "rc=$crc; $(printf '%s' "$cout" | tr '\n' ' ')"
  fi
else
  fail "H3 the drift workflow is present in the tree copy" "a readable file" "absent"
fi

# H4 -- the live tree is clean. This is the gate's actual contract.
if [[ "$live_rc" == "0" ]]; then
  pass "H4 the live tree has zero findings"
else
  fail "H4 the live tree has zero findings" "rc=0" "rc=$live_rc; $(printf '%s' "$live" | tr '\n' ' ')"
fi

# --- verdict ----------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo ""
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED: $FAIL assertion(s)"
  exit 1
fi
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAILED: assertion count $TOTAL regressed below MIN_ASSERTIONS=$MIN_ASSERTIONS — a fixture block was deleted"
  exit 1
fi
echo "All tests passed"
