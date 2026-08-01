#!/usr/bin/env bash
# Tests for scripts/lint-workflow-step-env-refs.py, plus a live execution harness for the
# step the guard was written for (#7136).
#
# TWO CLASSES, BOTH LOAD-BEARING:
#
#   PART A -- the linter over synthetic workflow fixtures. Asserts the bug shape is caught
#   and that each measured exemption (guarded-anywhere, $GITHUB_ENV carry-forward, in-body
#   assignment, single-quoted/escaped literals, lowercase, runner-provided) still holds.
#   Assert on EXIT CODES, not on message text.
#
#   PART B -- EXECUTION of the real step body extracted from the shipped
#   .github/workflows/web-platform-release.yml, under bash, with curl/jq stubbed. This is
#   the acceptance criterion "verified against a forced-failure run, not only by reading the
#   YAML": it runs the shipped text under the failure condition on every CI run, which a
#   one-off workflow dispatch would not. Part B includes a MUTATION PROOF -- the same harness
#   run against the pre-fix body (reconstructed by deleting R_DEPLOY from the step's env)
#   MUST die with "unbound variable". Without that case, Part B could pass vacuously against
#   a harness that never actually exercised the branch.
#
# Exit contract of the SUT: 0 clean, 1 findings / nothing scanned / unparseable input.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/lint-workflow-step-env-refs.py"
RELEASE_WF="$REPO_ROOT/.github/workflows/web-platform-release.yml"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "  detail: $2"
  FAIL=$((FAIL + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# PART A -- linter behaviour over fixtures
# ---------------------------------------------------------------------------

CASE_N=0
# mkwf <<'YAML' ... YAML  -> echoes the path of a throwaway workflow file
mkwf() {
  CASE_N=$((CASE_N + 1))
  local f="$TMP/wf_${CASE_N}.yml"
  cat > "$f"
  printf '%s' "$f"
}

# expect_exit <name> <expected> <file...>
expect_exit() {
  local name="$1" expected="$2"
  shift 2
  local out rc
  out="$(python3 "$SUT" "$@" 2>&1)"
  rc=$?
  if [[ "$rc" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $rc — output: $out"
  fi
}

echo "== Part A: linter fixtures =="

# A1 -- the #7136 shape: uppercase, unguarded, declared only on ANOTHER step.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: classify
        env:
          R_DEPLOY: ${{ needs.deploy.result }}
        run: echo "classified"
      - name: email
        env:
          VERSION: ${{ needs.release.outputs.version }}
        run: |
          set -uo pipefail
          if [[ "${R_DEPLOY}" == "success" ]]; then echo hi; fi
YAML
)"
expect_exit "A1 catches the cross-step env bug shape" 1 "$f"

# A2 -- same body, variable declared in THIS step's env (the fix).
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: email
        env:
          R_DEPLOY: ${{ needs.deploy.result }}
        run: |
          if [[ "${R_DEPLOY}" == "success" ]]; then echo hi; fi
YAML
)"
expect_exit "A2 clean when declared in the step's own env" 0 "$f"

# A3 -- guarded anywhere in the step exempts every reference to that name. This is the
# `[[ -n "${X:-}" ]] || exit 1` then bare `${X}` idiom; 16 real occurrences on main.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: bridge
        run: |
          [[ -n "${WEB_HOST_SSH:-}" ]] || { echo "no bridge"; exit 1; }
          ${WEB_HOST_SSH} host "uptime"
YAML
)"
expect_exit "A3 guarded-anywhere exempts later bare refs" 0 "$f"

# A4 -- $GITHUB_ENV export from an EARLIER step in the same job.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: setup
        run: |
          REMOTE_DIR=/var/tmp/x
          echo "REMOTE_DIR=$REMOTE_DIR" >> "$GITHUB_ENV"
      - name: use
        run: rm -rf "$REMOTE_DIR"
YAML
)"
expect_exit "A4 honours \$GITHUB_ENV carry-forward" 0 "$f"

# A5 -- a $GITHUB_ENV write does NOT exempt the SAME step: GITHUB_ENV lands in the NEXT step.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: only
        run: |
          echo "LATER_VAR=1" >> "$GITHUB_ENV"
          echo "reading ${OTHER_VAR} now"
YAML
)"
expect_exit "A5 same-step \$GITHUB_ENV write does not exempt that step" 1 "$f"

# A6 -- assigned in the body.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: local
        run: |
          BODY="<p>x</p>"
          BODY="${BODY}<p>y</p>"
          echo "$BODY"
YAML
)"
expect_exit "A6 in-body assignment is not a finding" 0 "$f"

# A7 -- literal `$VAR` text: single-quoted region and backslash-escaped. Never expanded.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: literals
        run: |
          echo "run: curl -H \"Authorization: Bearer \$HCLOUD_TOKEN\" https://api"
          printf '%s\n' 'SELECT * FROM remote($BS_TABLE)'
YAML
)"
expect_exit "A7 single-quoted and escaped literals are not references" 0 "$f"

# A8 -- lowercase locals are shellcheck's SC2154 domain, not this gate's.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: jqargs
        run: |
          jq -n --arg from "a" '{from: $from, other: $missing}'
YAML
)"
expect_exit "A8 ignores lowercase names" 0 "$f"

# A9 -- runner-provided variables need no declaration.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: runner
        run: echo "$GITHUB_SHA $RUNNER_TEMP $HOME" >> "$GITHUB_OUTPUT"
YAML
)"
expect_exit "A9 runner-provided variables are exempt" 0 "$f"

# A10 -- workflow-level and job-level env both count.
f="$(mkwf <<'YAML'
name: t
on: push
env:
  WF_LEVEL: a
jobs:
  j:
    runs-on: ubuntu-latest
    env:
      JOB_LEVEL: b
    steps:
      - name: scopes
        run: echo "${WF_LEVEL} ${JOB_LEVEL}"
YAML
)"
expect_exit "A10 workflow-level and job-level env count as declared" 0 "$f"

# A10b -- `mapfile`/`readarray` targets count as assigned. Regression guard for the ReDoS
# rewrite: the option-grammar regex this replaced was exponentially backtrackable
# (CodeQL py/redos), so the whole-line identifier harvest must still cover the array name.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: mapfile
        run: |
          mapfile -t HOSTS < /tmp/hosts
          readarray -t -d '' PATHS < /tmp/paths
          echo "${HOSTS[0]} ${PATHS[0]}"
YAML
)"
expect_exit "A10b mapfile/readarray targets count as assigned" 0 "$f"

# A10c -- the pathological input for the replaced regex must return promptly, not hang.
f="$(mkwf <<'YAML'
name: t
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: redos-shape
        run: |
          mapfile -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 -0 X
YAML
)"
START_S=$SECONDS
expect_exit "A10c pathological mapfile line does not backtrack" 0 "$f"
if [[ $((SECONDS - START_S)) -lt 10 ]]; then
  pass "A10d pathological input completes in under 10s"
else
  fail "A10d pathological input completes in under 10s" "took $((SECONDS - START_S))s"
fi

# A11 -- unparseable YAML fails closed rather than reporting clean.
printf 'name: t\non: push\njobs:\n  j:\n   steps: [ unclosed\n' > "$TMP/bad.yml"
expect_exit "A11 unparseable workflow fails closed" 1 "$TMP/bad.yml"

# A12 -- a clean sweep of NOTHING must not read as success.
mkdir -p "$TMP/empty"
out="$(cd "$TMP/empty" && python3 "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "A12 zero files scanned exits non-zero"
else
  fail "A12 zero files scanned exits non-zero" "expected exit 1, got $rc — $out"
fi

# A13 -- the real tree is clean. This is the gate's steady state: no allowlist, no baseline.
expect_exit "A13 repository workflows are clean" 0

# ---------------------------------------------------------------------------
# PART B -- execute the SHIPPED step body
# ---------------------------------------------------------------------------

echo
echo "== Part B: execution of the shipped release-outcome email step =="

# extract_step <mode>  -- writes the step's run body to $TMP/step_<mode>.sh and its declared
# env keys to $TMP/env_<mode>.txt. mode=fixed uses the shipped env; mode=prefix reconstructs
# the pre-#7136 state by dropping R_DEPLOY from the step's env (the mutation proof).
extract_step() {
  local mode="$1"
  python3 - "$RELEASE_WF" "$mode" "$TMP" <<'PY'
import sys, yaml
wf, mode, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(wf, encoding="utf-8"))
steps = doc["jobs"]["release-outcome"]["steps"]
step = next(s for s in steps if s.get("id") == "email")
keys = [k for k in (step.get("env") or {}) if not (mode == "prefix" and k == "R_DEPLOY")]
open(f"{tmp}/step_{mode}.sh", "w", encoding="utf-8").write(step["run"])
open(f"{tmp}/env_{mode}.txt", "w", encoding="utf-8").write("\n".join(keys))
PY
}

if ! extract_step fixed || ! extract_step prefix; then
  fail "B0 extract the email step from the shipped workflow" "python/yaml extraction failed"
else
  pass "B0 extract the email step from the shipped workflow"
fi

# The subset assertion the acceptance criteria name, stated directly against the shipped file.
if grep -qx 'R_DEPLOY' "$TMP/env_fixed.txt"; then
  pass "B1 shipped step declares R_DEPLOY in its own env:"
else
  fail "B1 shipped step declares R_DEPLOY in its own env:" "not found in step env keys"
fi

# Stubs. curl records the JSON payload it was handed and reports HTTP 200.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
payload=""
prev=""
for a in "$@"; do
  [[ "$prev" == "-d" ]] && payload="$a"
  prev="$a"
done
printf '%s' "$payload" > "$PAYLOAD_CAPTURE"
printf '200'
STUB
chmod +x "$TMP/bin/curl"

# run_step <name> <mode> <expect_rc> <r_deploy_mode> -- r_deploy_mode: value | unset
run_step() {
  local name="$1" mode="$2" expect_rc="$3" rdep="$4"
  local capture="$TMP/payload_${mode}_${rdep}.json"
  local rc out
  : > "$capture"
  local -a envargs=(
    "PATH=$TMP/bin:$PATH"
    "PAYLOAD_CAPTURE=$capture"
    "RESEND_API_KEY=test-key"
    "VERSION=0.247.3"
    "TAG=v0.247.3"
    "FAILED=deploy=failure"
    "FAILED_HTML=<li>Rolling the new version out</li>"
    "RUN_URL=https://github.com/jikig-ai/soleur/actions/runs/30703438860"
    "GITHUB_OUTPUT=$TMP/gh_output_${mode}_${rdep}"
    "RUNNER_TEMP=$TMP"
  )
  [[ "$rdep" != "unset" ]] && envargs+=("R_DEPLOY=$rdep")
  : > "$TMP/gh_output_${mode}_${rdep}"
  out="$(env -i "${envargs[@]}" bash "$TMP/step_${mode}.sh" 2>&1)"
  rc=$?
  LAST_OUT="$out"
  LAST_PAYLOAD="$capture"
  if [[ "$rc" -eq "$expect_rc" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expect_rc, got $rc — output: $out"
  fi
}

payload_has() {
  local capture="$1" needle="$2"
  grep -qF -- "$needle" "$capture"
}

if ! command -v jq >/dev/null 2>&1; then
  fail "B2..B6 execution cases" "jq is required by the step body but is not installed"
else
  RUN_URL_EXPECT="https://github.com/jikig-ai/soleur/actions/runs/30703438860"

  # B2 -- the forced-failure case: this is the exact condition that has been firing in
  # production since 2026-07-30 and delivering nothing.
  run_step "B2 deploy=failure sends without dying" fixed 0 failure
  if payload_has "$LAST_PAYLOAD" "production was NOT updated" \
     && payload_has "$LAST_PAYLOAD" "$RUN_URL_EXPECT"; then
    pass "B2a failure branch: correct subject + run link"
  else
    fail "B2a failure branch: correct subject + run link" "$(cat "$LAST_PAYLOAD")"
  fi

  # B3 -- the branch that had NEVER executed, because the step always died first.
  run_step "B3 deploy=success sends without dying" fixed 0 success
  if payload_has "$LAST_PAYLOAD" "production WAS updated"; then
    pass "B3a success branch: correct subject"
  else
    fail "B3a success branch: correct subject" "$(cat "$LAST_PAYLOAD")"
  fi
  # The unconditional tail tells the operator to "send the run link above" — so the link
  # has to be in BOTH branches. It was not, before #7136.
  if payload_has "$LAST_PAYLOAD" "$RUN_URL_EXPECT"; then
    pass "B3b success branch carries the run link its own text refers to"
  else
    fail "B3b success branch carries the run link its own text refers to" "$(cat "$LAST_PAYLOAD")"
  fi

  # B4 -- R_DEPLOY absent from the environment entirely must NOT kill the step, and must
  # take the alarming branch (over-warn, never falsely reassure).
  run_step "B4 R_DEPLOY unset survives" fixed 0 unset
  if payload_has "$LAST_PAYLOAD" "production was NOT updated"; then
    pass "B4a unset R_DEPLOY degrades to the 'NOT updated' branch"
  else
    fail "B4a unset R_DEPLOY degrades to the 'NOT updated' branch" "$(cat "$LAST_PAYLOAD")"
  fi

  # B5 -- MUTATION PROOF. Same harness, pre-fix env (R_DEPLOY removed) AND the guard
  # removed from the expansion: must reproduce the production failure exactly.
  sed 's/\${R_DEPLOY:-}/${R_DEPLOY}/' "$TMP/step_prefix.sh" > "$TMP/step_prefixbare.sh"
  cp "$TMP/env_prefix.txt" "$TMP/env_prefixbare.txt"
  run_step "B5 pre-fix body dies (mutation proof)" prefixbare 1 unset
  if grep -q "unbound variable" <<< "$LAST_OUT"; then
    pass "B5a pre-fix failure is the reported 'R_DEPLOY: unbound variable'"
  else
    fail "B5a pre-fix failure is the reported 'R_DEPLOY: unbound variable'" "$LAST_OUT"
  fi
  if [[ ! -s "$LAST_PAYLOAD" ]]; then
    pass "B5b pre-fix body never reaches the send (no payload captured)"
  else
    fail "B5b pre-fix body never reaches the send (no payload captured)" "$(cat "$LAST_PAYLOAD")"
  fi
fi

echo
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All tests passed"
