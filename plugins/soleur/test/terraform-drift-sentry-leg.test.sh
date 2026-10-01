#!/usr/bin/env bash
# Tests the `apps/web-platform/infra/sentry` leg of `scheduled-terraform-drift.yml` (#6612).
#
# WHAT IS PINNED. The leg exists (S1). The workflow binds the apply's credential on that leg
# only, and passes every leg's directory to the steps that branch on it (S2). terraform runs
# a full-root `plan` with exactly the flags that make exit 2 mean drift, under an environment
# ALLOWLIST: nothing else the job exports (Hetzner token, TF_VAR_*, TF_CLI_ARGS*, TF_LOG*,
# proxies, Doppler) reaches it (S3, B1-B3, B7). Each terraform exit code becomes the published
# `exit_code` (B1-B4). The token and UI-entered request bodies are scrubbed from the text
# posted to a public issue, and nothing else is (B8, B9). The other two legs keep their
# Doppler path (B5). The shared tail is pinned too: the email shows the error, not 4000 bytes
# of refresh lines, keeps drift diffs, and names the stack when init never ran (E1-E4); the
# drift issue routes each kind of Sentry drift to the fix the apply's gates accept (I1, I2).
# R1-R4 run the extracted step against REAL terraform on a local-backend fixture: that is
# the non-destructive proof the leg detects drift. CI's scripts shards carry no terraform, so
# there they print `R-arms: SKIPPED`; main-health-monitor.yml installs terraform and runs
# TEST_GROUP=all, which is where the R rows execute on every main build.
#
# HOW. Every script under test is EXTRACTED from the workflow with yaml.safe_load, never
# re-implemented, and run the way Actions runs a bare `run:` block: `bash --noprofile
# --norc -e`, NO pipefail. Two steps write to fixed `/tmp/` paths; those paths (and only
# those) are rewritten into this suite's sandbox, and the rewrite is asserted to have landed.
# terraform, doppler and gh are PATH stubs. Because the step runs terraform under `env -i`,
# the stubs read their settings from a config file rather than the environment; they record
# argv, the SET of environment names they received, and a token-equality flag, never a
# credential value. Every input is synthesized (cq-test-fixtures-synthesized-only).
#
# Run: bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh
# TERRAFORM_DRIFT_WF=<path> points the suite at a sandbox copy (mutation checks).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${TERRAFORM_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"
SENTRY_DIR="apps/web-platform/infra/sentry"
# What terraform may see on the sentry leg: the step's `env -i` allowlist.
ALLOWED_ENV="AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY HOME PATH SENTRY_AUTH_TOKEN"
EXACT_ARGV="plan -detailed-exitcode -no-color -input=false"

# `/tmp` is a shared tmpfs and a direct invocation inherits it.
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0
FAIL=0
ROWS=()
FAILED=()
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); FAILED+=("$1"); }

TMP=$(mktemp -d) || { echo "FATAL: sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

[[ -f "$WF" ]] || { echo "FATAL: missing $WF"; exit 2; }

# Not `detail=$("$@")`: a command substitution is a subshell, so the run counter and any
# FATAL `exit 2` inside a check would be discarded. The detail goes through a file instead.
row() { # row <id> <description> <check-cmd...>
  local id="$1" desc="$2" st
  shift 2
  ROWS+=("$id")
  "$@" > "$TMP/row-detail"
  st=$?
  if [[ "$st" -eq 0 ]]; then pass "$id $desc"; else fail "$id $desc"; cat "$TMP/row-detail"; fi
}

# INSTRUMENT SELF-TEST. Both helpers must move their counter, AND the row dispatcher must
# turn a failing check into a failure: a `row()` that ignores its check's status would
# otherwise report every row green while the counters and the floor still agree.
{
  pass "self-test"
  fail "self-test"
  row X0 "self-test (must fail)" false
  row X1 "self-test (must pass)" true
} > /dev/null
if [[ "$PASS" -ne 2 || "$FAIL" -ne 2 || "${#FAILED[@]}" -ne 2 || "${FAILED[1]}" != "X0 self-test (must fail)" ]]; then
  printf 'FATAL: instrument self-test: PASS=%s FAIL=%s FAILED=%s, want 2/2 with X0 failed\n' \
    "$PASS" "$FAIL" "${FAILED[*]:-}"
  exit 2
fi
PASS=0
FAIL=0
ROWS=()
FAILED=()

echo "=== terraform-drift sentry leg (#6612) ==="

# ---------------------------------------------------------------------------
# EXTRACTION
# ---------------------------------------------------------------------------
python3 - "$WF" "$TMP" <<'PY' || { echo "FATAL: extraction failed"; exit 2; }
import json, sys, yaml
wf, out = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(wf))
job = doc["jobs"]["drift-check"]
steps = job["steps"]

def one(pred, what):
    hits = [s for s in steps if pred(s)]
    if len(hits) != 1:
        print(f"FATAL: {what}: {len(hits)} matching steps, want 1")
        sys.exit(2)
    return hits[0]

plan = one(lambda s: s.get("id") == "plan", "plan step")
open(f"{out}/plan-step.sh", "w").write(plan["run"])
json.dump(plan.get("env", {}), open(f"{out}/plan-env.json", "w"))

email = one(lambda s: s.get("name") == "Prepare email content", "email step")
open(f"{out}/email-step.sh", "w").write(email["run"])
json.dump(email.get("env", {}), open(f"{out}/email-env.json", "w"))

issue = one(lambda s: s.get("name") == "Create or update drift issue", "issue step")
open(f"{out}/issue-step.sh", "w").write(issue["run"])
json.dump(issue.get("env", {}), open(f"{out}/issue-env.json", "w"))

tok = one(lambda s: s.get("id") == "token_drift", "token_drift step")
open(f"{out}/token-if.txt", "w").write(str(tok.get("if", "")))

st = one(lambda s: str(s.get("uses", "")).startswith("hashicorp/setup-terraform@"), "setup-terraform")
open(f"{out}/wrapper.txt", "w").write(repr(st.get("with", {}).get("terraform_wrapper")))

open(f"{out}/matrix.txt", "w").write("\n".join(job["strategy"]["matrix"]["directory"]) + "\n")
PY

# Extraction floor: a truncated or empty plan step parses and "answers"; refuse it.
if ! grep -q 'detailed-exitcode' "$TMP/plan-step.sh" || [[ "$(wc -l < "$TMP/plan-step.sh")" -lt 10 ]]; then
  echo "FATAL: extracted plan step lacks -detailed-exitcode or is under 10 lines"
  exit 2
fi

# The email and issue steps write fixed /tmp/ files. Rewrite ONLY those paths into the
# sandbox, and refuse if the rewrite did not land (it would then write the real /tmp).
mkdir -p "$TMP/sbtmp" || { echo "FATAL: sbtmp"; exit 2; }
for s in email-step issue-step; do
  n=$(grep -c '/tmp/' "$TMP/$s.sh")
  sed -i "s#/tmp/#$TMP/sbtmp/#g" "$TMP/$s.sh" || { echo "FATAL: rewrite $s"; exit 2; }
  if [[ "$n" -lt 1 ]] || grep -q '[^A-Za-z0-9_]/tmp/' <(sed "s#$TMP/sbtmp/##g" "$TMP/$s.sh"); then
    echo "FATAL: /tmp rewrite in $s did not land (before=$n)"
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# STUBS. Settings come from $CONF (terraform runs under `env -i`, so the environment cannot
# carry them). new_run rewrites $CONF for every run.
# ---------------------------------------------------------------------------
CONF="$TMP/stub.conf"
mkdir -p "$TMP/bin" "$TMP/bin-h1" "$TMP/bin-r" || { echo "FATAL: stub dirs"; exit 2; }

cat > "$TMP/bin/terraform" <<'EOF'
#!/usr/bin/env bash
. "__CONF__"
{
  printf 'TF_ARGV'; printf ' %s' "$@"; printf '\n'
  printf 'ENV_NAMES %s\n' "$(compgen -e | grep -vxE 'PWD|SHLVL|_|OLDPWD' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [[ "${SENTRY_AUTH_TOKEN-}" == "${EXPECT_SENTRY_TOKEN-__unset__}" ]]; then
    echo "TOKEN_MATCH=yes"
  else
    echo "TOKEN_MATCH=no"
  fi
} >> "$STUB_LOG"
echo "stub plan body"
if [[ "${STUB_TF_BODY:-0}" == "1" ]]; then
  echo '      + body = "s3cr3t-in-ui-body"'
  echo '      ~ name = "keep-this-name"'
fi
if [[ "${STUB_TF_ECHO_TOKEN:-0}" == "1" ]]; then echo "provider debug: token ${SENTRY_AUTH_TOKEN-}" >&2; fi
exit "${STUB_TF_RC:-0}"
EOF

# H1 harness stub: identical except it IGNORES STUB_TF_RC. B1 must red under it.
sed 's/^exit "\${STUB_TF_RC:-0}"$/exit 0/' "$TMP/bin/terraform" > "$TMP/bin-h1/terraform"
grep -qx 'exit 0' "$TMP/bin-h1/terraform" || { echo "FATAL: H1 stub mutation did not land"; exit 2; }

cat > "$TMP/bin/doppler" <<'EOF'
#!/usr/bin/env bash
. "__CONF__"
if [[ "${MATRIX_DIR-}" == "apps/web-platform/infra/sentry" ]]; then
  echo "DOPPLER_CALLED_ON_SENTRY_LEG" >> "$STUB_LOG"
  exit 97
fi
{ printf 'DOPPLER_ARGV'; printf ' %s' "$@"; printf '\n'; } >> "$STUB_LOG"
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift
exec "$@"
EOF

cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
. "__CONF__"
{ printf 'GH_ARGV'; printf ' %s' "$@"; printf '\n'; } >> "$STUB_LOG"
if [[ "${1-} ${2-}" == "issue list" ]]; then exit 0; fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--body-file" ]]; then cp "$2" "$STUB_GH_BODY"; fi
  shift
done
exit 0
EOF
for f in "$TMP/bin/terraform" "$TMP/bin-h1/terraform" "$TMP/bin/doppler" "$TMP/bin/gh"; do
  sed -i "s#__CONF__#$CONF#" "$f" || { echo "FATAL: conf path"; exit 2; }
  grep -qF "$CONF" "$f" || { echo "FATAL: conf path did not land in $f"; exit 2; }
done
cp "$TMP/bin/doppler" "$TMP/bin/gh" "$TMP/bin-h1/" || { echo "FATAL: stub copy"; exit 2; }
# The R rows run REAL terraform, but never a real doppler: a regression that routes the sentry
# leg back through `doppler run` must hit the exit-97 stub, not the operator's logged-in CLI.
cp "$TMP/bin/doppler" "$TMP/bin-r/" || { echo "FATAL: bin-r"; exit 2; }
chmod +x "$TMP/bin/"* "$TMP/bin-h1/"* "$TMP/bin-r/"* || { echo "FATAL: chmod"; exit 2; }

# ---------------------------------------------------------------------------
# DRIVERS. Each sets RUN_RC, RUN_OUT (stdout+stderr), RUN_LOG (stub log), RUN_GO
# (GITHUB_OUTPUT) and RUN_RT (RUNNER_TEMP).
# ---------------------------------------------------------------------------
N=0
new_run() { # new_run [KEY=VALUE ...] — stub settings for this run
  N=$((N + 1))
  RUN_RT="$TMP/run$N/rt"
  RUN_GO="$TMP/run$N/go"
  RUN_LOG="$TMP/run$N/stub.log"
  RUN_OUT="$TMP/run$N/out"
  mkdir -p "$RUN_RT" || { echo "FATAL: run dir"; exit 2; }
  : > "$RUN_GO"
  : > "$RUN_LOG"
  {
    printf 'STUB_LOG=%q\n' "$RUN_LOG"
    printf 'STUB_GH_BODY=%q\n' "$RUN_RT/body.md"
    local kv
    for kv in "$@"; do printf '%s=%q\n' "${kv%%=*}" "${kv#*=}"; done
  } > "$CONF" || { echo "FATAL: conf"; exit 2; }
}

# run_plan <bindir> <matrix-dir> <cwd> <stub-settings> [ENV=VALUE ...]
#   stub-settings: space-separated KEY=VALUE for the stubs (no spaces in values).
run_plan() {
  local bindir="$1" mdir="$2" cwd="$3" stub="$4"
  shift 4
  # shellcheck disable=SC2086  # stub settings are deliberately word-split
  new_run $stub
  ( cd "$cwd" && env PATH="$bindir:$PATH" MATRIX_DIR="$mdir" GITHUB_OUTPUT="$RUN_GO" \
      RUNNER_TEMP="$RUN_RT" CI_SSH_PUB="$TMP/ci_ssh_key.pub" \
      DOPPLER_TOKEN=stub-doppler DOPPLER_PROJECT=soleur DOPPLER_CONFIG=prd_terraform \
      "$@" bash --noprofile --norc -e "$TMP/plan-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}

out_val() { sed -n "s/^$1=//p" "$RUN_GO" | tail -1; }
log_has() { grep -qxF -- "$1" "$RUN_LOG"; }
tf_calls() { grep -c '^TF_ARGV' "$RUN_LOG"; }

# Everything the job could export into the plan step's environment, and must NOT reach
# terraform on the sentry leg: what infra-credentials writes to $GITHUB_ENV today (Hetzner)
# and after the Tier-B cutover (TF_VAR_*), and the variables that change what a plan measures
# or where the token goes.
DECOYS=(HCLOUD_TOKEN=decoy-hcloud TF_VAR_sentry_org=decoy.example TF_CLI_ARGS=-refresh=false
  TF_CLI_ARGS_plan=-target=x TF_WORKSPACE=decoy TF_LOG=DEBUG TF_LOG_CORE=TRACE
  TF_LOG_PROVIDER=DEBUG HTTPS_PROXY=http://127.0.0.1:9 SENTRY_TOKEN=decoy-st
  AWS_ACCESS_KEY_ID=stub-aws-id AWS_SECRET_ACCESS_KEY=stub-aws-secret)

# check_sentry_arm <want-exit-code> — the B1 contract. Prints each unmet clause; returns 1 on any.
check_sentry_arm() {
  local want="$1" bad=0 argv envs
  argv=$(sed -n 's/^TF_ARGV //p' "$RUN_LOG" | head -1)
  envs=$(sed -n 's/^ENV_NAMES //p' "$RUN_LOG" | head -1)
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC under bash -e"; bad=1; }
  [[ "$(out_val exit_code)" == "$want" ]] || { echo "    exit_code=$(out_val exit_code), want $want"; bad=1; }
  [[ "$(out_val stack_name)" == "web-platform/sentry" ]] || { echo "    stack_name=$(out_val stack_name)"; bad=1; }
  ! grep -qE '^DOPPLER_(ARGV|CALLED)' "$RUN_LOG" || { echo "    doppler was invoked"; bad=1; }
  [[ "$(tf_calls)" -eq 1 ]] || { echo "    terraform calls=$(tf_calls), want 1"; bad=1; }
  # Exact argv: a presence check lets -refresh=false, --target= or any other flag ride along.
  [[ "$argv" == "$EXACT_ARGV" ]] || { echo "    argv='$argv', want '$EXACT_ARGV'"; bad=1; }
  # Exact environment NAME set: the allowlist, and nothing the job exported besides.
  [[ "$envs" == "$ALLOWED_ENV" ]] || { echo "    terraform env='$envs', want '$ALLOWED_ENV'"; bad=1; }
  log_has TOKEN_MATCH=yes || { echo "    terraform did not see SENTRY_IAC_AUTH_TOKEN as SENTRY_AUTH_TOKEN"; bad=1; }
  return "$bad"
}

# ---------------------------------------------------------------------------
# STRUCTURAL
# ---------------------------------------------------------------------------
s1() {
  local bad=0 d c
  for d in apps/web-platform/infra infra/github "$SENTRY_DIR"; do
    c=$(grep -cxF -- "$d" "$TMP/matrix.txt")
    [[ "$c" -eq 1 ]] || { echo "    matrix has $d x$c, want 1"; bad=1; }
  done
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if ! grep -qE 'backend "s3"' "$REPO_ROOT/$d"/*.tf 2>/dev/null; then
      echo "    $d: no dir or no backend \"s3\""; bad=1; continue
    fi
    run_plan "$TMP/bin" "$d" "$REPO_ROOT/$d" "STUB_TF_RC=2" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-s1
    [[ "$(out_val exit_code)" == "2" && "$RUN_RC" -eq 0 ]] || {
      echo "    $d driven with stub rc 2: exit_code=$(out_val exit_code) rc=$RUN_RC"; bad=1; }
  done < "$TMP/matrix.txt"
  return "$bad"
}
row S1 "matrix holds each of the three roots once, each is an s3-backed dir, each maps stub rc 2 to exit_code=2" s1

s2() {
  local bad=0 c
  c=$(grep -c 'secrets\.SENTRY_IAC_AUTH_TOKEN' "$WF")
  [[ "$c" -eq 1 ]] || { echo "    secrets.SENTRY_IAC_AUTH_TOKEN appears $c times in the file, want 1"; bad=1; }
  # The PARSED values, compared exactly: a substring of the line is satisfied by a YAML comment
  # or by an expression like `cond && '' || secret` that hands every leg the token.
  python3 - "$TMP" <<'PY' || bad=1
import json, sys
t = sys.argv[1]
want_tok = "${{ matrix.directory == 'apps/web-platform/infra/sentry' && secrets.SENTRY_IAC_AUTH_TOKEN || '' }}"
bad = 0
plan = json.load(open(f"{t}/plan-env.json"))
if plan.get("SENTRY_IAC_AUTH_TOKEN") != want_tok:
    print(f"    plan env SENTRY_IAC_AUTH_TOKEN = {plan.get('SENTRY_IAC_AUTH_TOKEN')!r}, want {want_tok!r}"); bad = 1
for f in ("plan-env", "issue-env", "email-env"):
    v = json.load(open(f"{t}/{f}.json")).get("MATRIX_DIR")
    if v != "${{ matrix.directory }}":
        print(f"    {f} MATRIX_DIR = {v!r}, want the matrix directory"); bad = 1
sys.exit(bad)
PY
  return "$bad"
}
row S2 "the secret is bound once, exactly as the gated expression, and every branching step receives MATRIX_DIR" s2

s3() {
  local bad=0 arm
  if grep -v '^[[:space:]]*#' "$TMP/plan-step.sh" | grep -q -- '-target'; then
    echo "    plan step carries -target"; bad=1
  fi
  arm=$(awk -v d="$SENTRY_DIR" 'index($0, "\"$MATRIX_DIR\" == \"" d "\"") {on=1} on && /^else$/ {exit} on' \
    "$TMP/plan-step.sh" | grep -v '^[[:space:]]*#')
  [[ -n "$arm" ]] || { echo "    no sentry arm in the plan step"; return 1; }
  [[ "$arm" == *"-detailed-exitcode"* ]] || { echo "    sentry arm lacks -detailed-exitcode"; bad=1; }
  [[ "$arm" != *doppler* ]] || { echo "    sentry arm invokes doppler"; bad=1; }
  return "$bad"
}
row S3 "no -target anywhere in the plan step; the sentry arm plans with -detailed-exitcode and no doppler" s3

s4() {
  local g
  g=$(cat "$TMP/token-if.txt")
  [[ "$g" == "matrix.directory == 'apps/web-platform/infra'" ]] || { echo "    token_drift if: $g"; return 1; }
}
row S4 "the token-drift step stays gated on exactly the main root" s4

s5() { [[ "$(cat "$TMP/wrapper.txt")" == "False" ]] || { echo "    terraform_wrapper=$(cat "$TMP/wrapper.txt")"; return 1; }; }
row S5 "setup-terraform keeps terraform_wrapper: false (the wrapper maps exit 2 to 1)" s5

# ---------------------------------------------------------------------------
# BEHAVIOURAL — the sentry arm
# ---------------------------------------------------------------------------
b_run() { # b_run <bindir> <stub-rc>
  run_plan "$1" "$SENTRY_DIR" "$TMP" "STUB_TF_RC=$2 EXPECT_SENTRY_TOKEN=synthetic-iac-b" \
    SENTRY_IAC_AUTH_TOKEN=synthetic-iac-b "${DECOYS[@]}"
}
b1() { b_run "$TMP/bin" 2; check_sentry_arm 2; }
row B1 "sentry leg, stub rc 2: exit_code=2, exact argv, only the allowlisted env reaches terraform, no doppler" b1
b2() { b_run "$TMP/bin" 0; check_sentry_arm 0; }
row B2 "sentry leg, stub rc 0: exit_code=0" b2
b3() { b_run "$TMP/bin" 1; check_sentry_arm 1; }
row B3 "sentry leg, stub rc 1: exit_code=1" b3

b4() {
  local bad=0
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" "STUB_TF_RC=0" SENTRY_IAC_AUTH_TOKEN=
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC"; bad=1; }
  [[ "$(out_val exit_code)" == "1" ]] || { echo "    exit_code=$(out_val exit_code), want 1"; bad=1; }
  grep -q '::error::sentry_iac_token_absent' "$RUN_OUT" || { echo "    no ::error::sentry_iac_token_absent"; bad=1; }
  [[ "$(tf_calls)" -eq 0 ]] || { echo "    terraform was invoked with an empty token"; bad=1; }
  return "$bad"
}
row B4 "empty SENTRY_IAC_AUTH_TOKEN: exit_code=1, named ::error::, terraform never invoked" b4

b5() {
  local bad=0 d want_rc want_stack
  for spec in "apps/web-platform/infra:2:web-platform" "infra/github:0:infra/github"; do
    IFS=: read -r d want_rc want_stack <<<"$spec"
    run_plan "$TMP/bin" "$d" "$REPO_ROOT/$d" "STUB_TF_RC=$want_rc"
    grep -q '^DOPPLER_ARGV run --preserve-env --name-transformer tf-var -- terraform plan -detailed-exitcode' "$RUN_LOG" \
      || { echo "    $d: doppler tf-var path not taken"; bad=1; }
    [[ "$(out_val exit_code)" == "$want_rc" ]] || { echo "    $d: exit_code=$(out_val exit_code), want $want_rc"; bad=1; }
    [[ "$(out_val stack_name)" == "$want_stack" ]] || { echo "    $d: stack_name=$(out_val stack_name)"; bad=1; }
  done
  return "$bad"
}
row B5 "the main and github legs keep their doppler tf-var plan and stack names" b5

b7() {
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" "STUB_TF_RC=0 EXPECT_SENTRY_TOKEN=iac-y" \
    SENTRY_AUTH_TOKEN=decoy-x SENTRY_IAC_AUTH_TOKEN=iac-y
  log_has TOKEN_MATCH=yes || { echo "    terraform saw the ambient SENTRY_AUTH_TOKEN, not SENTRY_IAC_AUTH_TOKEN"; return 1; }
}
row B7 "an ambient SENTRY_AUTH_TOKEN is overridden by SENTRY_IAC_AUTH_TOKEN" b7

b8() {
  local tok="synthetic-iac-$RANDOM$RANDOM" bad=0
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" "STUB_TF_ECHO_TOKEN=1 STUB_TF_RC=1" SENTRY_IAC_AUTH_TOKEN="$tok"
  [[ -s "$RUN_RT/plan-output.txt" ]] || { echo "    no plan-output.txt"; return 1; }
  ! grep -qF -- "$tok" "$RUN_RT/plan-output.txt" || { echo "    the token survived into plan-output.txt"; bad=1; }
  # Survival: the scrub replaces the token and nothing else.
  grep -qxF 'provider debug: token ***' "$RUN_RT/plan-output.txt" || { echo "    the token's line was not scrubbed to exactly '***'"; bad=1; }
  grep -qxF 'stub plan body' "$RUN_RT/plan-output.txt" || { echo "    non-token plan text was lost"; bad=1; }
  return "$bad"
}
row B8 "a token echoed by the provider is scrubbed from plan-output.txt, and nothing else is" b8

b9() {
  local bad=0
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" "STUB_TF_BODY=1 STUB_TF_RC=2" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-b9
  ! grep -qF 's3cr3t-in-ui-body' "$RUN_RT/plan-output.txt" || { echo "    a UI-entered request body reached plan-output.txt"; bad=1; }
  grep -qF 'body = "***"' "$RUN_RT/plan-output.txt" || { echo "    body was not redacted to \"***\""; bad=1; }
  grep -qF 'name = "keep-this-name"' "$RUN_RT/plan-output.txt" || { echo "    an ordinary attribute was redacted"; bad=1; }
  return "$bad"
}
row B9 "an uptime monitor's request body (not sensitive in the provider schema) is redacted before the public issue" b9

h1() { b_run "$TMP/bin-h1" 2; if check_sentry_arm 2 > /dev/null; then echo "    B1 passed under a stub that ignores STUB_TF_RC"; return 1; fi; }
row H1 "harness: B1's contract reds under a terraform stub that ignores STUB_TF_RC" h1

# ---------------------------------------------------------------------------
# EMAIL + ISSUE STEPS
# ---------------------------------------------------------------------------
run_email() { # run_email <plan-output-file|-> <exit-code> <stack-name> <matrix-dir>
  new_run
  if [[ "$1" != "-" ]]; then cp "$1" "$RUN_RT/plan-output.txt" || { echo "FATAL: email fixture"; exit 2; }; fi
  ( cd "$TMP" && env GITHUB_OUTPUT="$RUN_GO" RUNNER_TEMP="$RUN_RT" EXIT_CODE="$2" \
      STACK_NAME="$3" MATRIX_DIR="$4" GITHUB_SERVER_URL=https://github.example GITHUB_REPOSITORY=o/r \
      GITHUB_RUN_ID=1 bash --noprofile --norc -e "$TMP/email-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}
for i in $(seq 1 120); do
  printf 'module.monitoring.sentry_alert.rule_%03d_padding_for_length: Refreshing state... [id=1000%03d]\n' "$i" "$i"
done > "$TMP/refresh-only.txt"
{ cat "$TMP/refresh-only.txt"; echo "Error: boom"; } > "$TMP/refresh-then-error.txt"
{
  cat "$TMP/refresh-only.txt"
  echo '  # sentry_alert.rule_007 will be updated in-place'
  echo '  ~ name = "old-name" -> "new-name"'
  for i in $(seq 1 90); do printf '      ~ attribute_%03d = "padding-value-to-exceed-the-snippet-budget"\n' "$i"; done
} > "$TMP/refresh-then-drift.txt"

e1() {
  local bad=0
  run_email "$TMP/refresh-then-error.txt" 1 web-platform/sentry "$SENTRY_DIR"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC"; bad=1; }
  grep -qF 'Error: boom' "$RUN_GO" || { echo "    the email body lacks the error line"; bad=1; }
  ! grep -qF 'Refreshing state' "$RUN_GO" || { echo "    the email body carries refresh lines"; bad=1; }
  return "$bad"
}
row E1 "the error email shows the error, not 4000 bytes of refresh lines" e1

e2() {
  local bad=0
  run_email "$TMP/refresh-only.txt" 1 web-platform/sentry "$SENTRY_DIR"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC under bash -e"; bad=1; }
  ! grep -qF '<pre>' "$RUN_GO" || { echo "    an all-refresh output still produced a snippet"; bad=1; }
  return "$bad"
}
row E2 "an all-refresh plan output yields an empty snippet and step rc 0" e2

e3() {
  local bad=0 pre
  run_email "$TMP/refresh-then-drift.txt" 2 web-platform/sentry "$SENTRY_DIR"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC"; bad=1; }
  grep -qF 'sentry_alert.rule_007 will be updated in-place' "$RUN_GO" || { echo "    the drift diff header was filtered out"; bad=1; }
  grep -qF '~ name = &quot;old-name&quot;' "$RUN_GO" 2>/dev/null || grep -qF '~ name = "old-name"' "$RUN_GO" \
    || { echo "    the drift diff line was filtered out"; bad=1; }
  pre=$(sed -n '/<pre>/,/<\/pre>/p' "$RUN_GO" | sed 's/<\/*pre>//g' | tr -d '\n' | wc -c)
  [[ "$pre" -le 4000 ]] || { echo "    snippet is $pre bytes, over the 4000-byte budget"; bad=1; }
  return "$bad"
}
row E3 "a drift email keeps the diff lines and stays within the 4000-byte snippet budget" e3

e4() {
  local bad=0 subj
  run_email - "" "" "$SENTRY_DIR"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC"; bad=1; }
  subj=$(sed -n 's/^subject=//p' "$RUN_GO")
  [[ "$subj" == "[ERROR] Terraform init failed for web-platform/sentry" ]] || { echo "    subject: $subj"; bad=1; }
  ! grep -qF '(exit )' "$RUN_GO" || { echo "    the body prints an empty exit code"; bad=1; }
  return "$bad"
}
row E4 "when init never ran, the email names the stack as the plan step would and says init failed" e4

run_issue() { # run_issue <matrix-dir> <stack>
  new_run
  printf 'plan text\n' > "$RUN_RT/plan-output.txt"
  ( cd "$TMP" && env PATH="$TMP/bin:$PATH" MATRIX_DIR="$1" STACK_NAME="$2" RUNNER_TEMP="$RUN_RT" \
      GH_TOKEN=stub RUN_NUMBER=7 SERVER_URL=https://github.example REPOSITORY=o/r RUN_ID=4242 \
      bash --noprofile --norc -e "$TMP/issue-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}

i1() {
  local bad=0 b="$TMP/run$((N + 1))/rt/body.md" lit
  run_issue "$SENTRY_DIR" web-platform/sentry
  [[ -s "$b" ]] || { echo "    no issue body rendered (rc=$RUN_RC)"; return 1; }
  for lit in 'gh workflow run apply-sentry-infra.yml --ref main -f reason=' 'drift run 4242' \
    'create gate' '[ack-destroy]' 'gh run rerun' '4. Close this issue when resolved'; do
    grep -qF -- "$lit" "$b" || { echo "    body lacks: $lit"; bad=1; }
  done
  for lit in '@@RUN_ID@@' 'If the drift is intentional,' 'If the drift is unintentional,'; do
    ! grep -qF -- "$lit" "$b" || { echo "    body carries: $lit"; bad=1; }
  done
  ! grep -q '^GH_ARGV workflow' "$RUN_LOG" || { echo "    rendering the body EXECUTED gh workflow run"; bad=1; }
  return "$bad"
}
row I1 "the sentry drift issue routes each kind of drift to a fix the apply's gates accept, and executes nothing" i1

i2() {
  local bad=0 b="$TMP/run$((N + 1))/rt/body.md" lit
  run_issue apps/web-platform/infra web-platform
  [[ -s "$b" ]] || { echo "    no issue body rendered (rc=$RUN_RC)"; return 1; }
  for lit in 'If the drift is intentional,' '3. If the drift is unintentional' '4. Close this issue when resolved'; do
    grep -qF -- "$lit" "$b" || { echo "    body lacks: $lit"; bad=1; }
  done
  for lit in 'apply-sentry-infra' 'create gate'; do
    ! grep -qF -- "$lit" "$b" || { echo "    main-root body carries: $lit"; bad=1; }
  done
  return "$bad"
}
row I2 "the main-root drift issue keeps its existing remediation" i2

# ---------------------------------------------------------------------------
# REAL TERRAFORM (local backend, terraform_data — no provider download, no network)
# ---------------------------------------------------------------------------
R_RAN=0
TF_REAL=$(command -v terraform || true)
if [[ -n "$TF_REAL" ]]; then
  FX="$TMP/fixture"
  mkdir -p "$FX" || { echo "FATAL: fixture dir"; exit 2; }
  write_fx() { # write_fx <a-input|-> [b]
    {
      echo 'terraform {'
      echo '  backend "local" {}'
      echo '}'
      [[ "$1" == "-" ]] || printf 'resource "terraform_data" "a" {\n  input = "%s"\n}\n' "$1"
      [[ "${2-}" != "b" ]] || printf 'resource "terraform_data" "b" {\n  input = "new"\n}\n'
    } > "$FX/main.tf"
  }
  write_fx v1
  if ( cd "$FX" && "$TF_REAL" init -input=false -no-color > "$TMP/fx-init.log" 2>&1 \
        && "$TF_REAL" apply -auto-approve -input=false -no-color > "$TMP/fx-apply.log" 2>&1 ); then
    R_RAN=1
    real_plan() { # real_plan <want-exit-code> <want-grep|->
      local bad=0
      new_run
      ( cd "$FX" && env PATH="$TMP/bin-r:$PATH" MATRIX_DIR="$SENTRY_DIR" GITHUB_OUTPUT="$RUN_GO" \
          RUNNER_TEMP="$RUN_RT" CI_SSH_PUB="$TMP/ci_ssh_key.pub" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-r \
          bash --noprofile --norc -e "$TMP/plan-step.sh" ) > "$RUN_OUT" 2>&1
      RUN_RC=$?
      [[ "$(out_val exit_code)" == "$1" ]] || { echo "    exit_code=$(out_val exit_code), want $1"; bad=1; }
      if [[ "$2" != "-" ]]; then
        grep -qF -- "$2" "$RUN_RT/plan-output.txt" || { echo "    plan output lacks '$2'"; bad=1; }
      fi
      return "$bad"
    }
    r1() { write_fx v1; real_plan 0 -; }
    row R1 "real terraform: a converged root reads exit_code=0" r1
    r2() { write_fx v2; real_plan 2 'Plan:'; }
    row R2 "real terraform: a changed attribute reads exit_code=2" r2
    r3() { write_fx v1 b; real_plan 2 '1 to add'; }
    row R3 "real terraform: a declared-but-never-applied resource reads exit_code=2, 1 to add" r3
    r4() { write_fx -; real_plan 2 '1 to destroy'; }
    row R4 "real terraform: a resource removed from config but still in state reads exit_code=2, 1 to destroy" r4
  else
    echo "  FATAL: real-terraform fixture could not init/apply (see below)"
    tail -5 "$TMP/fx-init.log" "$TMP/fx-apply.log" 2>/dev/null
    exit 2
  fi
fi
if [[ "$R_RAN" -eq 1 ]]; then echo "R-arms: ran (terraform $("$TF_REAL" version | head -1))"; else echo "R-arms: SKIPPED (terraform absent)"; fi

# ---------------------------------------------------------------------------
echo "=== $PASS passed / $FAIL failed ==="
# The exact row set, so deleting a row call (or an R row when terraform is present) is a
# failure rather than a smaller green total.
EXPECTED_ROWS="S1 S2 S3 S4 S5 B1 B2 B3 B4 B5 B7 B8 B9 H1 E1 E2 E3 E4 I1 I2"
[[ "$R_RAN" -eq 0 ]] || EXPECTED_ROWS="$EXPECTED_ROWS R1 R2 R3 R4"
if [[ "${ROWS[*]}" != "$EXPECTED_ROWS" ]]; then
  printf 'FATAL: rows run: %s\n       expected: %s\n' "${ROWS[*]}" "$EXPECTED_ROWS"
  exit 1
fi
# Anti-vacuity floor: the 20 unconditional rows. A floor, not an equality; the row-set check
# above is the exact one.
FLOOR=20
if (( PASS + FAIL < FLOOR )); then
  printf 'FATAL: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$FLOOR"
  exit 1
fi
# The verdict reads the append-only FAILED ledger as well as the counter.
[[ "$FAIL" -eq 0 && "${#FAILED[@]}" -eq 0 ]] || exit 1
exit 0
