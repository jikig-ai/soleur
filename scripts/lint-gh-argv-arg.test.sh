#!/usr/bin/env bash
# Unit suite for scripts/lint-gh-argv-arg.py.
#
# The fixture set IS the executable specification of the rule: a standalone
# jq-flag token (--arg and family) inside `gh`'s own argv is a finding; the
# same token past an unquoted `|` boundary (jq's argv), inside a comment,
# inside a quoted string, or inside a heredoc body is data, not argv.
#
# Every must-NOT-fire case carries a POSITIVE CONTROL in the same fixture —
# a known-firing shape whose line the linter must name while leaving the
# guarded one alone. Without that control, a must-not-fire assertion passes
# against a linter that has stopped working entirely (a broken detector and a
# clean tree produce byte-identical output).
set -uo pipefail

# Keep scratch on the large tmpfs — see lint-workflow-errexit-capture.test.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="${GH_ARGV_LINT_SCRIPT:-$SCRIPT_DIR/lint-gh-argv-arg.py}"

TMP="$(mktemp -d -t gh-argv-lint.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PASS=0
FAIL=0
# Anti-vacuity floor. Raise deliberately when adding fixtures.
MIN_ASSERTIONS="${GH_ARGV_LINT_MIN_ASSERTIONS:-29}"

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
# mkfix <name> -- create a fixture root holding .github/workflows/ + scripts/.
mkfix() {
  local name="$1"
  local root="$TMP/fx-$name"
  rm -rf "$root" || { echo "FATAL: rm -rf $root failed"; exit 2; }
  mkdir -p "$root/.github/workflows" "$root/scripts" \
    || { echo "FATAL: mkdir $root failed"; exit 2; }
  printf '%s' "$root"
}

# run_lint <root> -- sets LINT_OUT and LINT_RC. Called as a plain function,
# never `$(run_lint)` — command substitution discards caller-visible rc.
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
assert_not_named() {
  local label="$1" root="$2" bad_line="$3"
  run_lint "$root"
  if grep -qE ":${bad_line}:" "$TMP/out.txt"; then
    fail "$label" "no finding at line ${bad_line}" "$(tr '\n' ' ' < "$TMP/out.txt")"
  else
    pass "$label"
  fi
}

echo "=== lint-gh-argv-arg fixtures ==="

# --- MUST FIRE --------------------------------------------------------------

# F1 -- the canonical defect: `--arg` inside gh's argv in a workflow run body.
r="$(mkfix canonical)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          set -euo pipefail
          EXISTING=$(gh issue list --json number --jq '.[0].number // empty' --arg t "$T")
          echo "$EXISTING"
YAML
assert_fires "F1 --arg inside gh argv in a run: body FIRES" "$r" 9

# F2 -- backslash-continuation: the flag lands on the NEXT physical line.
r="$(mkfix continuation)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          out="$(gh api repos/x/y \
            --jq '.x' --arg t "$T")"
          echo "$out"
YAML
assert_fires "F2 flag on a continuation line FIRES at the gh line" "$r" 8

# F3 -- inside a double-quoted command substitution (house-standard quoting).
r="$(mkfix quoted_sub)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
EXISTING="$(gh issue list --state open --json title --arg t "$TITLE")"
echo "$EXISTING"
SH
assert_fires "F3 --arg inside a quoted command-substitution in scripts/*.sh FIRES" "$r" 3

# F4 -- the flag family beyond --arg (learning 2026-03-04: all of them die
# inside gh argv the same way).
r="$(mkfix family)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
a="$(gh api x --argjson n '{}')"
b="$(gh api x --slurpfile f /dev/null)"
echo "$a $b"
SH
assert_fires "F4 --argjson FIRES" "$r" 2
assert_fires "F4b --slurpfile FIRES" "$r" 3

# F5 -- behind wrapper prefixes: timeout / env / ! must not hide the command.
r="$(mkfix wrappers)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if ! timeout 5s gh api repos/x --arg t v; then echo bad; fi
SH
assert_fires "F5 timeout+! wrapped gh invocation FIRES" "$r" 3

# F6 -- mid-line after a separator: `;` and `&&` open fresh command contexts.
r="$(mkfix midline)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
echo warm-up; gh issue list --arg t "$T"
echo done
SH
assert_fires "F6 a semicolon-then-gh mid-line FIRES" "$r" 2

# F7 -- a defect in the SECOND scanned file after a clean first file (a
# scanner that returns after the first file would read green here).
r="$(mkfix secondfile)"
cat > "$r/.github/workflows/a-clean.yml" <<'YAML'
name: clean
on: workflow_dispatch
jobs: {j: {runs-on: ubuntu-24.04, steps: [{run: "echo ok"}]}}
YAML
cat > "$r/scripts/z-dirty.sh" <<'SH'
#!/usr/bin/env bash
gh api repos/x --arg t v
SH
assert_fires "F7 defect in a later-scanned file FIRES" "$r" 2

# F8 -- a YAML inline `run:` (not a block scalar) is still an executed argv.
r="$(mkfix inline)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: gh api repos/x --arg t v
YAML
assert_fires "F8 inline -run:-gh...--arg FIRES" "$r" 7

# --- MUST NOT FIRE (each with a positive control in the same file) ----------

# G1 -- the canonical CORRECT shape: flag lives in jq's segment past the pipe.
r="$(mkfix pipe)"
cat > "$r/.github/workflows/fx.yml" <<'YAML'
name: fx
on: workflow_dispatch
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          EXISTING=$(gh issue list --json number | jq -r --arg t "$T" '.[0].number // empty')
          bad="$(gh api x --arg t v)"
YAML
assert_fires "G1 control: the bad line in the same body FIRES" "$r" 9
assert_not_named "G1b gh-pipe-jq--arg does NOT fire" "$r" 8

# G2 -- a comment quoting the defect is data, not argv.
r="$(mkfix comment)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
# gh --jq does not forward --arg (cli/cli#10263): keep the flag in jq argv.
out="$(gh api x --arg t v)"
SH
assert_fires "G2 control: the real defect below the comment FIRES" "$r" 3
assert_not_named "G2b the comment line quoting --arg does NOT fire" "$r" 2

# G3 -- `--arg` inside a quoted jq program token is program text, not a flag.
r="$(mkfix quoted_prog)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
gh api repos/x --jq 'select(.flag == "--arg")'
bad="$(gh api x --arg t v)"
SH
assert_fires "G3 control: the real defect in the same file FIRES" "$r" 3
assert_not_named "G3b --arg inside a quoted jq program does NOT fire" "$r" 2

# G4 -- heredoc bodies are stdin data; embedding gh-shaped text is not argv.
r="$(mkfix heredoc)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
cat > /tmp/gen.sh <<'INNER'
gh api repos/x --arg t v
INNER
real="$(gh api y --arg t v)"
SH
assert_fires "G4 control: the real defect AFTER the heredoc FIRES" "$r" 5
assert_not_named "G4b a gh---arg inside a heredoc body does NOT fire" "$r" 3

# G5 -- `--arg` on a non-gh command, and a `${var#x}` parameter expansion.
r="$(mkfix nongh)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
jq -r --arg t "$T" '.x' < in.json
suf="${path#/x/}"
bad="$(gh api z --arg t v)"
SH
assert_fires "G5 control: the real defect in the same file FIRES" "$r" 4
assert_not_named "G5b jq--arg alone does NOT fire" "$r" 2
assert_not_named "G5c the var#x parameter expansion does NOT fire" "$r" 3

# G6 -- near-miss tokens: --argument / --arg= are NOT the jq flag family...
# wait, they are not standalone tokens; gh still rejects them, but that is a
# different (self-diagnosing) failure — the rule keys on standalone flags.
r="$(mkfix nearmiss)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
gh api repos/x --argument-with-dashes v
real="$(gh api y --arg t v)"
SH
assert_fires "G6 control: the real defect in the same file FIRES" "$r" 3
assert_not_named "G6b the --argument-with-dashes near-miss does NOT fire" "$r" 2

# G7 -- the post-fix shape this PR ships: `if ! VAR="$(gh ... | jq --arg ...)"`.
r="$(mkfix postfix)"
cat > "$r/scripts/fx.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if ! EXISTING="$(gh issue list --json number,title | jq -r --arg t "$T" '.[]')"; then
  echo "::error::dedupe query failed"
  EXISTING=""
fi
real="$(gh api y --arg t v)"
SH
assert_fires "G7 control: the real defect in the same file FIRES" "$r" 7
assert_not_named "G7b the normalized fail-open dedupe shape does NOT fire" "$r" 3

# --- the gate's own scope ---------------------------------------------------

# H1 -- a root with nothing to scan is a USAGE error (rc=2), never a pass.
r="$(mkfix emptyroot)"
rm -rf "$r/.github" "$r/scripts"
out="$(python3 "$LINTER" --root "$r" 2>&1)"; rc=$?
if [[ "$rc" == "2" ]]; then
  pass "H1 a root with no scan targets exits 2, not 0"
else
  fail "H1 a root with no scan targets exits 2, not 0" "rc=2" "rc=$rc ($out)"
fi

# H2 -- per-kind scanned counts against the real tree (a total-only count
# could hide one whole root silently dropping out of scope).
live="$(python3 "$LINTER" --root "$REPO_ROOT" 2>&1)"; live_rc=$?
printf '%s\n' "$live" > "$TMP/live.txt"
wf_n="$(sed -n 's/.*scanned \([0-9]*\) workflow.*/\1/p' "$TMP/live.txt" | head -1)"
sh_n="$(sed -n 's/.*, \([0-9]*\) shell script.*/\1/p' "$TMP/live.txt" | head -1)"
if [[ "${wf_n:-0}" -ge 80 ]]; then
  pass "H2 live scan reaches >=80 workflows (got ${wf_n:-0})"
else
  fail "H2 live scan reaches >=80 workflows" ">=80" "${wf_n:-<unparsed>}"
fi
# The floor pins the repo-WIDE walk (all **/*.sh outside fixtures/ and vendored
# dirs), not the scripts/-only scope the first draft carried — a scope regression
# back to ~470 must not stay green.
if [[ "${sh_n:-0}" -ge 1000 ]]; then
  pass "H2b live scan reaches >=1000 shell scripts (got ${sh_n:-0})"
else
  fail "H2b live scan reaches >=1000 shell scripts" ">=1000" "${sh_n:-<unparsed>}"
fi

# H3 -- VERIFY THE VERIFIER: plant the defect into a copy of a live workflow
# and require the linter to catch it. Without this every must-not-fire case
# is compatible with a detector that finds nothing at all.
r="$(mkfix regression)"
rm -rf "$r/.github" && cp -r "$REPO_ROOT/.github" "$r/.github" \
  || { echo "FATAL: could not copy .github"; exit 2; }
target="$r/.github/workflows/scheduled-actions-queue-health.yml"
if [[ -f "$target" ]]; then
  printf '\n# planted regression\nEXISTING=$(gh issue list --json number --arg t "$T")\n' >> "$target"
  mout="$(python3 "$LINTER" --root "$r" --quiet 2>&1)"; mrc=$?
  printf '%s\n' "$mout" > "$TMP/mut.txt"
  if [[ "$mrc" == "1" ]] && grep -q 'scheduled-actions-queue-health.yml' "$TMP/mut.txt"; then
    pass "H3 a planted gh-argv --arg in a live workflow is CAUGHT"
  else
    fail "H3 a planted gh-argv --arg in a live workflow is CAUGHT" \
      "rc=1 naming scheduled-actions-queue-health.yml" \
      "rc=$mrc; $(tr '\n' ' ' < "$TMP/mut.txt")"
  fi
else
  fail "H3 the queue-health workflow is present in the tree copy" "a readable file" "absent"
fi

# H4 -- the live tree is clean (the gate's actual contract).
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
