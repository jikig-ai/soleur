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
open(f"{tmp}/env_{mode}.txt", "w", encoding="utf-8").write("".join(k + "\n" for k in keys))
PY
}

# extract_body <step-id> <outfile> -- writes that step's `run` body verbatim. Selected by
# id with an exactly-one precondition for the same reason the condition selectors are
# (#7138): a rename must break this loudly, never silently extract nothing.
extract_body() {
  python3 - "$RELEASE_WF" "$1" "$2" "$3" <<'PY'
import sys, yaml
wf, step_id, out, envout = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = yaml.safe_load(open(wf, encoding="utf-8"))
steps = doc["jobs"]["release-outcome"]["steps"]
hits = [s for s in steps if s.get("id") == step_id]
if len(hits) != 1:
    raise SystemExit(
        "expected exactly 1 step with id=%r in job release-outcome, found %d"
        % (step_id, len(hits))
    )
open(out, "w", encoding="utf-8").write(hits[0]["run"])
open(envout, "w", encoding="utf-8").write(
    "".join(k + "\n" for k in (hits[0].get("env") or {}))
)
PY
}

if ! extract_step fixed || ! extract_step prefix; then
  fail "B0 extract the email step from the shipped workflow" "python/yaml extraction failed"
else
  pass "B0 extract the email step from the shipped workflow"
fi

declares_env_key() {
  local keyfile="$1" key="$2"
  grep -qx -- "$key" "$keyfile"
}

# The subset assertion the acceptance criteria name, stated directly against the shipped file.
if grep -qx 'R_DEPLOY' "$TMP/env_fixed.txt"; then
  pass "B1 shipped step declares R_DEPLOY in its own env:"
else
  fail "B1 shipped step declares R_DEPLOY in its own env:" "not found in step env keys"
fi

if declares_env_key "$TMP/env_fixed.txt" CLASSIFIER; then
  pass "B1a-email email step declares CLASSIFIER in its own env:"
else
  fail "B1a-email email step declares CLASSIFIER in its own env:" "$(cat "$TMP/env_fixed.txt")"
fi

# B1a (#7138) -- BOTH steps must declare CLASSIFIER in their OWN `env:`. Step-level
# `env:` does not cross step boundaries; this is the #7136 rule, and the guarded form
# `${CLASSIFIER:-}` means the linter's guarded-anywhere exemption (A3) cannot catch a
# dropped declaration. Without this, deleting either key reverted the whole fix at
# 48/48 green -- the executed arms supplied the very key the workflow had stopped
# declaring. The harness now derives its env from these files, so this assertion and
# that derivation fail together rather than either one alone.
# B1b..B1e -- the notification conditions, asserted statically because a GitHub `if:`
# expression cannot be evaluated locally. #7136 gave us B1b; #7138 adds B1c/B1d/B1e.
#
# WHY EXACTLY-ONE CARDINALITY IS ASSERTED FOR EVERY SELECTOR (#7138): B1e is a NEGATIVE
# assertion ("the classify step declares no continue-on-error"). Selected loosely, renaming
# the step id would match nothing, "not found" would read as PASS, and -- because BOTH
# widened conditions key on `steps.outcome.*` -- that rename would silently restore #7138
# with every test green. A clean sweep of nothing must never read as success. The old B1b
# selected the mirror by `name.startswith(...)` for want of an id; the step now carries
# `id: mirror`, so all three selectors key on the id.
#
# The two `if:` strings are compared as WHOLE normalized strings, not by substring anchor.
# A substring anchor on `steps.outcome.conclusion == 'failure'` alone would stay green if
# the `steps.outcome.outputs.failed != ''` disjunct were deleted -- which would silently
# revert every pre-#7138 alerting path. Whitespace is collapsed before comparison, so a
# folded (`>-`) and a plain one-line scalar are equivalent here.
if ! COND_REPORT="$(python3 - "$RELEASE_WF" 2>&1 <<'PY'
import sys, yaml

# The shipped conditions, verbatim. Update BOTH sides deliberately or not at all.
EXPECTED = {
    "email": "${{ !cancelled() && (steps.outcome.conclusion == 'failure'"
             " || steps.outcome.outputs.failed != '') }}",
    "mirror": "${{ !cancelled() && (steps.outcome.conclusion == 'failure'"
              " || steps.outcome.outputs.failed != '')"
              " && steps.email.outputs.delivered != '1' }}",
}


def norm(value):
    return " ".join(str(value).split())


doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = doc["jobs"]["release-outcome"]["steps"]


def exactly_one(step_id):
    hits = [s for s in steps if s.get("id") == step_id]
    if len(hits) != 1:
        raise SystemExit(
            "CARDINALITY: expected exactly 1 step with id=%r in job release-outcome, found %d"
            % (step_id, len(hits))
        )
    return hits[0]


rows = []
for step_id, want in EXPECTED.items():
    got = norm(exactly_one(step_id).get("if", ""))
    rows.append(
        "%s\t%s\t%s\t%s"
        % (step_id, "OK" if got == norm(want) else "MISMATCH", got, norm(want))
    )

classify = exactly_one("outcome")
rows.append(
    "outcome-timeout\t%s\t%s\t%s"
    % (
        "PRESENT" if "timeout-minutes" in classify else "ABSENT",
        classify.get("timeout-minutes", ""),
        "PRESENT",
    )
)
rows.append(
    "outcome-coe\t%s\t%s\t%s"
    % (
        "ABSENT" if "continue-on-error" not in classify else "PRESENT",
        classify.get("continue-on-error", ""),
        "ABSENT",
    )
)
print("\n".join(rows))
PY
)"; then
  fail "B1b..B1e step selectors resolve to exactly one step each" "$COND_REPORT"
  COND_REPORT=""
fi

# Field readers over the tab-separated report. A herestring, never a pipe into `grep -q`:
# under `pipefail` an early match makes the producer take SIGPIPE and the pipeline reports
# non-zero even though it matched.
cond_verdict() { awk -v k="$1" -F'\t' '$1 == k { print $2 }' <<< "$COND_REPORT"; }
cond_actual() { awk -v k="$1" -F'\t' '$1 == k { print $3 }' <<< "$COND_REPORT"; }
cond_expected() { awk -v k="$1" -F'\t' '$1 == k { print $4 }' <<< "$COND_REPORT"; }

# B1b (#7136) -- the mirror must NOT inherit the implicit success() guard. Without
# `!cancelled()` it is SKIPPED whenever the email step FAILS -- verified on run 30703438860
# (email=failure, mirror=skipped), which is how both alert channels died together.
if [[ "$(cond_actual mirror)" == *'!cancelled()'* ]]; then
  pass "B1b Sentry mirror survives an email-step crash (!cancelled)"
else
  fail "B1b Sentry mirror survives an email-step crash (!cancelled)" "if: $(cond_actual mirror)"
fi

# B1c (#7138) -- the mirror fires when the CLASSIFIER dies, not only when it reports a
# failure. Before the fix its `if:` read the classifier's OUTPUT alone, so a classify step
# that died before writing $GITHUB_OUTPUT left `failed` empty and skipped this step.
if [[ "$(cond_verdict mirror)" == "OK" ]]; then
  pass "B1c mirror fires on classifier death (whole-condition match)"
else
  fail "B1c mirror fires on classifier death (whole-condition match)" \
    "expected: $(cond_expected mirror)
    actual:   $(cond_actual mirror)"
fi

# B1d (#7138) -- same widening on the EMAIL step. The mirror alone satisfies the issue's
# literal floor, but the email is the plain-language channel the operator actually reads.
if [[ "$(cond_verdict email)" == "OK" ]]; then
  pass "B1d operator email fires on classifier death (whole-condition match)"
else
  fail "B1d operator email fires on classifier death (whole-condition match)" \
    "expected: $(cond_expected email)
    actual:   $(cond_actual email)"
fi

# B1f (#7138) -- the classify step carries its OWN timeout. The job-level
# `timeout-minutes` does not help: a hung classify consumes the whole job budget, so the
# email and mirror steps are never scheduled and the run dies silent -- a mode no widening
# of their conditions can reach. Bounded at the step, a hang becomes a step `failure`,
# which is exactly what B1c/B1d now fire on.
if [[ "$(cond_verdict outcome-timeout)" == "PRESENT" ]]; then
  pass "B1f classify step bounds its own runtime (a hang becomes a catchable failure)"
else
  fail "B1f classify step bounds its own runtime (a hang becomes a catchable failure)" \
    "no timeout-minutes on the classify step — a hang silences both channels"
fi

# B1e (#7138) -- `steps.outcome.conclusion` is the POST-continue-on-error value. Adding
# `continue-on-error:` to the classify step would flip it to `success` and silently disarm
# the guard in BOTH steps above, with no other test failing.
if [[ "$(cond_verdict outcome-coe)" == "ABSENT" ]]; then
  pass "B1e classify step declares no continue-on-error (keeps .conclusion trustworthy)"
else
  fail "B1e classify step declares no continue-on-error (keeps .conclusion trustworthy)" \
    "continue-on-error: $(cond_actual outcome-coe)"
fi

# Stubs. curl records the JSON payload it was handed and reports HTTP 200.
#
# #7138 -- `--data` AND `--data-raw`, not just `-d`. The email step posts with `-d`, but the
# Sentry mirror step posts with `--data`. Scanning for `-d` alone left $PAYLOAD_CAPTURE empty
# for every mirror arm, which would make each payload assertion below fail for the wrong
# reason -- and would make any "no payload was captured" assertion pass VACUOUSLY, for every
# arm, forever.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
payload=""
prev=""
for a in "$@"; do
  case "$prev" in
    -d|--data|--data-raw) payload="$a" ;;
  esac
  prev="$a"
done
printf '%s' "$payload" > "$PAYLOAD_CAPTURE"
printf '%s' "${CURL_HTTP_CODE:-200}"
STUB
chmod +x "$TMP/bin/curl"

# THE HARNESS DERIVES ITS ENVIRONMENT FROM THE STEP'S OWN `env:` BLOCK (#7138).
#
# The first draft hardcoded this list and INJECTED `CLASSIFIER` directly, so it was
# testing a variable the workflow might not declare: deleting `CLASSIFIER:` from either
# step's `env:` left the whole suite green while the fix was entirely reverted. That is
# the #7136 defect class recurring for the new variable, and neither gate caught it --
# the linter exempts `${CLASSIFIER:-}` under its guarded-anywhere rule (A3), and the
# execution arms supplied the very key the workflow had stopped declaring.
#
# Deriving the keys means a dropped `env:` declaration becomes an UNSET variable here, so
# the arms that depend on it go red. A key the step declares but the harness has no value
# for is a loud failure, never a silent omission.
env_value_for() {
  case "$1" in
    RESEND_API_KEY) printf 'test-key' ;;
    VERSION)        printf '0.247.3' ;;
    TAG)            printf 'v0.247.3' ;;
    RUN_URL)        printf '%s' "$RUN_URL_EXPECT" ;;
    GITHUB_SHA)     printf '1111111111111111111111111111111111111111' ;;
    NEXT_PUBLIC_SENTRY_DSN) printf 'https://deadbeef@de.sentry.io/12345' ;;
    REASON)         printf '%s' "${RS_REASON:-}" ;;
    FAILED)         printf '%s' "$RS_FAILED" ;;
    FAILED_HTML)    printf '%s' "$RS_FAILED_HTML" ;;
    # `<OMIT>` models the key being absent from the runner environment entirely.
    R_DEPLOY)   [[ "$RS_RDEP" == "unset" ]] && printf '<OMIT>' || printf '%s' "$RS_RDEP" ;;
    CLASSIFIER) [[ -z "$RS_CLASSIFIER" ]] && printf '<OMIT>' || printf '%s' "$RS_CLASSIFIER" ;;
    *) return 1 ;;
  esac
}

# append_declared_env <name> <env-keys-file> -- appends `KEY=value` for every key the
# step declares. Returns non-zero (and reports) on a key with no harness value.
append_declared_env() {
  local name="$1" keyfile="$2" k v
  # `|| [[ -n "$k" ]]` -- a file whose last line has no trailing newline makes plain
  # `read` return non-zero WITH the value already in $k, so the bare form silently drops
  # the final key. That is a fail-open in the derivation: the harness would supply a key
  # the workflow no longer declares, which is precisely what this function exists to stop.
  while IFS= read -r k || [[ -n "$k" ]]; do
    [[ -z "$k" ]] && continue
    if ! v="$(env_value_for "$k")"; then
      fail "$name" "step declares env key '$k' but the harness has no value for it — add one to env_value_for()"
      return 1
    fi
    [[ "$v" == "<OMIT>" ]] && continue
    envargs+=("$k=$v")
  done < "$keyfile"
  return 0
}

# run_step <name> <mode> <expect_rc> <r_deploy_mode> [classifier] [failed] [failed_html]
#   r_deploy_mode: value | unset
#   classifier:    the value of CLASSIFIER (steps.outcome.conclusion). Empty leaves it
#                  unset, which is the pre-#7138 environment.
run_step() {
  local name="$1" mode="$2" expect_rc="$3" rdep="$4"
  RS_CLASSIFIER="${5:-}"
  RS_FAILED="${6-deploy=failure}"
  RS_FAILED_HTML="${7-<li>Rolling the new version out</li>}"
  RS_RDEP="$rdep"
  local tag="${mode}_${rdep}_${RS_CLASSIFIER:-none}_${#RS_FAILED}_${CURL_HTTP_CODE:-200}"
  local capture="$TMP/payload_${tag}.json"
  local rc out
  : > "$capture"
  local -a envargs=(
    "PATH=$TMP/bin:$PATH"
    "PAYLOAD_CAPTURE=$capture"
    "CURL_HTTP_CODE=${CURL_HTTP_CODE:-200}"
    "GITHUB_OUTPUT=$TMP/gh_output_${tag}"
    "RUNNER_TEMP=$TMP"
  )
  append_declared_env "$name" "$TMP/env_${mode}.txt" || return 0
  : > "$TMP/gh_output_${tag}"
  LAST_GH_OUTPUT="$TMP/gh_output_${tag}"
  # `bash -e`: GitHub runs every `run:` body under `bash --noprofile --norc -e -o pipefail`.
  # The bodies set `-uo pipefail` themselves, which does NOT clear an inherited `-e`, so
  # invoking without it tested a laxer shell than production uses.
  out="$(env -i "${envargs[@]}" bash -e "$TMP/step_${mode}.sh" 2>&1)"
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

  # This branch's own body says the merged code IS live, so the closing line must not tell
  # the operator nothing reaches production. The file's #7095 comment block already lists
  # that exact phrase as one of three claims false in this branch; it stayed unconditional
  # until #7138 branched it, and nothing pinned the correction until this assertion.
  if ! payload_has "$LAST_PAYLOAD" "nothing reaches production"; then
    pass "B3c success branch does not claim the release is stuck"
  else
    fail "B3c success branch does not claim the release is stuck" "$(cat "$LAST_PAYLOAD")"
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

  # -------------------------------------------------------------------------
  # B6 (#7138) -- the EMAIL step's third headline. It fires ONLY when the classifier died
  # AND `needs.deploy.result == 'success'` -- the one state where "did production update?"
  # is settled and "what else failed?" is not.
  #
  # The first draft gated it `R_DEPLOY != 'failure'`, which swept in `skipped` (the
  # DOMINANT failed-release state, since `deploy` needs five upstream jobs) and
  # `cancelled`, and told the operator we could not tell whether a release that never
  # rolled out had reached production. These arms sample EVERY value of R_DEPLOY, not
  # only the two the first draft imagined.
  # -------------------------------------------------------------------------
  run_step "B6 classifier death + deploy success sends without dying" fixed 0 success failure "" ""
  if payload_has "$LAST_PAYLOAD" "[RELEASE STATUS UNKNOWN]"; then
    pass "B6a classifier-death subject differs at the FIRST token, not mid-bracket"
  else
    fail "B6a classifier-death subject differs at the FIRST token, not mid-bracket" "$(cat "$LAST_PAYLOAD")"
  fi
  # A PAIRED POSITIVE for the negative below. An absence assertion on its own is satisfied
  # by replacing the urgency line with anything at all, including nonsense.
  if payload_has "$LAST_PAYLOAD" "the alarm that tells you when a release fails is currently broken"; then
    pass "B6b classifier-death body names the real fault -- the alarm, not the release"
  else
    fail "B6b classifier-death body names the real fault -- the alarm, not the release" "$(cat "$LAST_PAYLOAD")"
  fi
  # The closing urgency line used to be unconditional; production DID update on this
  # branch, so the old text contradicted the email's own opening two paragraphs earlier.
  if ! payload_has "$LAST_PAYLOAD" "nothing reaches production"; then
    pass "B6c classifier-death body does not claim nothing reached production"
  else
    fail "B6c classifier-death body does not claim nothing reached production" "$(cat "$LAST_PAYLOAD")"
  fi
  if ! payload_has "$LAST_PAYLOAD" "<ul></ul>"; then
    pass "B6d classifier-death body renders no empty <ul></ul>"
  else
    fail "B6d classifier-death body renders no empty <ul></ul>" "$(cat "$LAST_PAYLOAD")"
  fi
  # The run link AND the hint that matches the suppressed list. Branching the hint on the
  # headline while branching the list on FAILED_HTML rendered "the red entry named above"
  # with no entry above -- the #7136 dangling-reference shape.
  if payload_has "$LAST_PAYLOAD" "$RUN_URL_EXPECT" \
     && payload_has "$LAST_PAYLOAD" "it shows which parts of the release finished"; then
    pass "B6e run link carries a hint consistent with the suppressed list"
  else
    fail "B6e run link carries a hint consistent with the suppressed list" "$(cat "$LAST_PAYLOAD")"
  fi

  # THE MISSING CELL. The property is a 2x2 over (CLASSIFIER, FAILED non-empty) and the
  # first draft sampled only the anti-diagonal, where the two predicates are perfectly
  # correlated -- so swapping the discriminator from CLASSIFIER to `-z FAILED` in either
  # body survived every assertion. This is the state the workflow's own env comment names
  # as its justification: a classifier that dies AFTER writing its output.
  run_step "B6f classifier died AFTER writing its output" fixed 0 success failure \
    "live-verify=failure" "<li>Checking the live site</li>"
  if payload_has "$LAST_PAYLOAD" "[RELEASE STATUS UNKNOWN]" \
     && payload_has "$LAST_PAYLOAD" "<li>Checking the live site</li>" \
     && payload_has "$LAST_PAYLOAD" "the red entry named above"; then
    pass "B6g a classifier that DID report keeps its list, and the hint matches it"
  else
    fail "B6g a classifier that DID report keeps its list, and the hint matches it" "$(cat "$LAST_PAYLOAD")"
  fi

  # Every R_DEPLOY value meaning production did NOT update must take the definite branch,
  # whatever the classifier did. `skipped` is the one the first draft got wrong.
  for _rdep in failure skipped cancelled unset; do
    run_step "B6h[$_rdep] classifier death + deploy=$_rdep sends without dying" \
      fixed 0 "$_rdep" failure "" ""
    if payload_has "$LAST_PAYLOAD" "production was NOT updated"; then
      pass "B6i[$_rdep] does not falsely reassure when production did not update"
    else
      fail "B6i[$_rdep] does not falsely reassure when production did not update" "$(cat "$LAST_PAYLOAD")"
    fi
  done

  # B7 -- the email's NON-DELIVERY branch had never executed: the stub returned 200
  # unconditionally, so `HTTP_CODE =~ ^2` had a population of one. That branch is what
  # PRODUCES the mirror's `reason`, i.e. the condition the mirror exists to compensate for.
  CURL_HTTP_CODE=500 run_step "B7 non-2xx send records non-delivery" fixed 0 failure
  if grep -qx 'delivered=0' "$LAST_GH_OUTPUT" && grep -qx 'reason=resend_http_500' "$LAST_GH_OUTPUT"; then
    pass "B7a non-delivery records delivered=0 and a reason the mirror can quote"
  else
    fail "B7a non-delivery records delivered=0 and a reason the mirror can quote" "$(cat "$LAST_GH_OUTPUT")"
  fi
  # The consumer side of that contract is pinned statically by B1c (the mirror's `if:`
  # contains `steps.email.outputs.delivered != '1'`); this is the producer side. Without
  # it, writing `delivered=0` on a SUCCESSFUL send passed the whole suite -- and would
  # fire the mirror, and its `exit 1`, on every healthy release.
  run_step "B8 successful send records delivery" fixed 0 failure
  if grep -qx 'delivered=1' "$LAST_GH_OUTPUT"; then
    pass "B8a a delivered email records delivered=1 so the mirror stands down"
  else
    fail "B8a a delivered email records delivered=1 so the mirror stands down" "$(cat "$LAST_GH_OUTPUT")"
  fi

  # -------------------------------------------------------------------------
  # PART B (mirror) -- #7138 makes the mirror reachable with an EMPTY FAILED for the first
  # time. A branch that has never executed is not a branch that works, so the
  # newly-reachable input is EXECUTED here rather than reasoned about.
  # -------------------------------------------------------------------------
  if ! extract_body mirror "$TMP/mirror.sh" "$TMP/env_mirror.txt"; then
    fail "M0 extract the mirror step from the shipped workflow" "python/yaml extraction failed"
  else
    pass "M0 extract the mirror step from the shipped workflow"

    if declares_env_key "$TMP/env_mirror.txt" CLASSIFIER; then
      pass "B1a-mirror mirror step declares CLASSIFIER in its own env:"
    else
      fail "B1a-mirror mirror step declares CLASSIFIER in its own env:" "$(cat "$TMP/env_mirror.txt")"
    fi

    # run_mirror <name> <classifier> <failed> [omit-runner-key]
    #
    # The step's OWN env: keys are derived (see append_declared_env). Only RUNNER-provided
    # keys are supplied here -- the body writes $GITHUB_STEP_SUMMARY unguarded, and an env
    # omitting it aborts with "GITHUB_STEP_SUMMARY: unbound variable", literally the string
    # M1a asserts must be absent. `omit` exists to prove that channel is live.
    #
    # NOTE the exit code is NOT a discriminator here: the body ends in `exit 1` BY DESIGN,
    # and bash also exits 1 on an unbound variable. The assertions below are on the output.
    run_mirror() {
      local name="$1" classifier="$2" failed="$3" omit="${4:-}"
      RS_CLASSIFIER="$classifier"
      RS_FAILED="$failed"
      RS_FAILED_HTML=""
      RS_RDEP="unset"
      RS_REASON=""
      local tag="mirror_${classifier}_${#failed}_${omit:-none}"
      local capture="$TMP/payload_${tag}.json"
      local summary="$TMP/summary_${tag}"
      local rc out
      : > "$capture"
      : > "$summary"
      local -a envargs=(
        "PATH=$TMP/bin:$PATH"
        "PAYLOAD_CAPTURE=$capture"
        "CURL_HTTP_CODE=200"
      )
      [[ "$omit" != "GITHUB_STEP_SUMMARY" ]] && envargs+=("GITHUB_STEP_SUMMARY=$summary")
      append_declared_env "$name" "$TMP/env_mirror.txt" || return 0
      out="$(env -i "${envargs[@]}" bash -e "$TMP/mirror.sh" 2>&1)"
      rc=$?
      LAST_OUT="$out"
      LAST_PAYLOAD="$capture"
      LAST_SUMMARY="$summary"
      if [[ "$rc" -eq 1 ]]; then
        pass "$name"
      else
        fail "$name" "expected exit 1, got $rc — output: $out"
      fi
    }

    # M1 -- THE NEWLY-REACHABLE INPUT: the classifier died before writing its output.
    run_mirror "M1 mirror runs with an empty FAILED (the newly-reachable input)" failure ""
    if ! grep -q "unbound variable" <<< "$LAST_OUT"; then
      pass "M1a the fix does not move the crash into the compensating step"
    else
      fail "M1a the fix does not move the crash into the compensating step" "$LAST_OUT"
    fi
    if payload_has "$LAST_PAYLOAD" '"classifier":"failed"'; then
      pass "M1b event carries the classifier discriminator as its own tag"
    else
      fail "M1b event carries the classifier discriminator as its own tag" "$(cat "$LAST_PAYLOAD")"
    fi
    if payload_has "$LAST_PAYLOAD" "the failing jobs are UNKNOWN" \
       && ! payload_has "$LAST_PAYLOAD" "release FAILED"; then
      pass "M1c event says the failing jobs are UNKNOWN, not that the release failed"
    else
      fail "M1c event says the failing jobs are UNKNOWN, not that the release failed" "$(cat "$LAST_PAYLOAD")"
    fi
    # `op` is the routing key. A discriminator belongs in a NEW tag key -- changing `op`
    # would move the event to a value nothing routes on.
    if payload_has "$LAST_PAYLOAD" '"op":"release-alert-undelivered"'; then
      pass "M1d the routing key op= is unchanged"
    else
      fail "M1d the routing key op= is unchanged" "$(cat "$LAST_PAYLOAD")"
    fi
    if grep -qF "the failing jobs are UNKNOWN" "$LAST_SUMMARY"; then
      pass "M1e the run's step summary tells the same story as the event"
    else
      fail "M1e the run's step summary tells the same story as the event" "$(cat "$LAST_SUMMARY")"
    fi

    # M2 -- the classifier ran fine and reported real failures.
    run_mirror "M2 mirror still reports a real release failure unchanged" success "deploy=failure"
    if payload_has "$LAST_PAYLOAD" "release FAILED" \
       && payload_has "$LAST_PAYLOAD" "deploy=failure" \
       && payload_has "$LAST_PAYLOAD" '"classifier":"ok"'; then
      pass "M2a a genuine release failure is reported with its job list"
    else
      fail "M2a a genuine release failure is reported with its job list" "$(cat "$LAST_PAYLOAD")"
    fi

    # M3 -- THE MISSING CELL, mirror side. The classifier died AFTER writing its output,
    # so conclusion == 'failure' AND the list is populated. The first draft keyed the
    # narrative on CLASSIFIER and threw the list away, asserting "the classifier died
    # before it could record which jobs failed" about a run where it demonstrably had.
    run_mirror "M3 classifier died AFTER writing its output" failure "live-verify=failure"
    if payload_has "$LAST_PAYLOAD" '"classifier":"failed"' \
       && payload_has "$LAST_PAYLOAD" "live-verify=failure" \
       && ! payload_has "$LAST_PAYLOAD" "before it could record"; then
      pass "M3a the tag reports the death while the event KEEPS the job list it has"
    else
      fail "M3a the tag reports the death while the event KEEPS the job list it has" "$(cat "$LAST_PAYLOAD")"
    fi

    # M4 -- POSITIVE CONTROL for M1a. M1a asserts an absence; without an arm proving this
    # harness can OBSERVE an unbound-variable abort, that absence is unfalsifiable. It also
    # pins the env-completeness claim the comment above otherwise makes in prose only.
    run_mirror "M4 omitting a runner-provided key crashes the body" failure "" GITHUB_STEP_SUMMARY
    if grep -q "unbound variable" <<< "$LAST_OUT"; then
      pass "M4a the crash channel M1a watches is live (control)"
    else
      fail "M4a the crash channel M1a watches is live (control)" "$LAST_OUT"
    fi
  fi
fi

echo
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"

# ANTI-VACUITY FLOOR (#7138). Nothing above asserts that the assertions RAN: the exit
# contract is `FAIL > 0`, so deleting a block -- or losing one to a bad merge -- reports
# success. Measured before this floor existed: removing B1c/B1d/B1e left the suite at
# 45/45, exit 0. A FLOOR (-lt), not equality, so the suite grows without churn; lower it
# only deliberately, and say why.
MIN_ASSERTIONS=69
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: assertion count regressed — ran $((PASS + FAIL)), floor is $MIN_ASSERTIONS."
  echo "      Assertions were deleted or skipped. Restore them, or lower the floor on purpose."
  exit 1
fi

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All tests passed"
