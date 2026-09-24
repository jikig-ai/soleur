#!/usr/bin/env bash
# Tests the `apps/web-platform/infra/sentry` leg of `scheduled-terraform-drift.yml` (#6612).
#
# WHAT IS PINNED. The leg exists (S1), binds the apply's credential and nothing else (S2, B1,
# B7), plans the WHOLE root with -detailed-exitcode (S3, B1), turns each terraform exit code
# into the published `exit_code` (B1-B4), redacts the token from the text posted to a public
# issue (B8), and leaves the other two legs on their Doppler path (B5). The shared tail it
# rides is pinned too: the email shows the error rather than 4000 bytes of refresh lines
# (E1, E2), and the drift issue for this stack names the CI apply, not a local one (I1, I2).
# R1-R4 run the extracted step against REAL terraform on a local-backend fixture: that is
# the non-destructive proof the leg detects drift (#6612 "prove it can detect drift").
#
# HOW. Every script under test is EXTRACTED from the workflow with yaml.safe_load, never
# re-implemented, and run the way Actions runs a bare `run:` block: `bash --noprofile
# --norc -e`, NO pipefail. Two steps write to fixed `/tmp/` paths; those paths (and only
# those) are rewritten into this suite's sandbox, and the rewrite is asserted to have landed.
# terraform, doppler and gh are PATH stubs that record argv and SET/UNSET flags, never a
# credential value. Every input is synthesized (cq-test-fixtures-synthesized-only).
#
# Run: bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh
# TERRAFORM_DRIFT_WF=<path> points the suite at a sandbox copy (mutation checks).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${TERRAFORM_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"
SENTRY_DIR="apps/web-platform/infra/sentry"

# `/tmp` is a shared tmpfs and a direct invocation inherits it.
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || { echo "FATAL: sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

[[ -f "$WF" ]] || { echo "FATAL: missing $WF"; exit 2; }

# INSTRUMENT SELF-TEST: both helpers must move their counter, or every verdict below is void.
pass "instrument self-test: pass() moves PASS"
fail "instrument self-test: fail() moves FAIL (EXPECTED — not a real failure)"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: instrument self-test: PASS=%s FAIL=%s, want 1/1\n' "$PASS" "$FAIL"
  exit 2
fi
PASS=0
FAIL=0

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
# STUBS
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/bin-h1" || { echo "FATAL: stub dirs"; exit 2; }

cat > "$TMP/bin/terraform" <<'EOF'
#!/usr/bin/env bash
flag() { if [[ -n "${!1+x}" ]]; then echo "$1=SET"; else echo "$1=UNSET"; fi; }
{
  printf 'TF_ARGV'; printf ' %s' "$@"; printf '\n'
  flag SENTRY_AUTH_TOKEN
  flag TF_VAR_sentry_auth_token
  flag DOPPLER_TOKEN
  flag TF_LOG
  if [[ "${SENTRY_AUTH_TOKEN-}" == "${EXPECT_SENTRY_TOKEN-__unset__}" ]]; then
    echo "TOKEN_MATCH=yes"
  else
    echo "TOKEN_MATCH=no"
  fi
} >> "$STUB_LOG"
echo "stub plan body"
if [[ "${STUB_TF_ECHO_TOKEN:-0}" == "1" ]]; then echo "provider debug: token ${SENTRY_AUTH_TOKEN-}" >&2; fi
exit "${STUB_TF_RC:-0}"
EOF

# H1 harness stub: identical except it IGNORES STUB_TF_RC. B1 must red under it.
sed 's/^exit "\${STUB_TF_RC:-0}"$/exit 0/' "$TMP/bin/terraform" > "$TMP/bin-h1/terraform"
grep -qx 'exit 0' "$TMP/bin-h1/terraform" || { echo "FATAL: H1 stub mutation did not land"; exit 2; }

cat > "$TMP/bin/doppler" <<'EOF'
#!/usr/bin/env bash
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
{ printf 'GH_ARGV'; printf ' %s' "$@"; printf '\n'; } >> "$STUB_LOG"
if [[ "${1-} ${2-}" == "issue list" ]]; then exit 0; fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--body-file" ]]; then cp "$2" "$STUB_GH_BODY"; fi
  shift
done
exit 0
EOF
cp "$TMP/bin/doppler" "$TMP/bin/gh" "$TMP/bin-h1/" || { echo "FATAL: stub copy"; exit 2; }
# The R rows run REAL terraform, but never a real doppler: a regression that routes the sentry
# leg back through `doppler run` must hit the exit-97 stub, not the operator's logged-in CLI.
mkdir -p "$TMP/bin-r" && cp "$TMP/bin/doppler" "$TMP/bin-r/" || { echo "FATAL: bin-r"; exit 2; }
chmod +x "$TMP/bin/"* "$TMP/bin-h1/"* "$TMP/bin-r/"* || { echo "FATAL: chmod"; exit 2; }

# ---------------------------------------------------------------------------
# DRIVERS. Each sets RUN_RC, RUN_OUT (stdout+stderr), RUN_LOG (stub log), RUN_GO
# (GITHUB_OUTPUT) and RUN_RT (RUNNER_TEMP). Extra NAME=VALUE pairs become env.
# ---------------------------------------------------------------------------
N=0
new_run() {
  N=$((N + 1))
  RUN_RT="$TMP/run$N/rt"
  RUN_GO="$TMP/run$N/go"
  RUN_LOG="$TMP/run$N/stub.log"
  RUN_OUT="$TMP/run$N/out"
  mkdir -p "$RUN_RT" || { echo "FATAL: run dir"; exit 2; }
  : > "$RUN_GO"
  : > "$RUN_LOG"
}

# run_plan <bindir> <matrix-dir> <cwd> [NAME=VALUE ...]
run_plan() {
  local bindir="$1" mdir="$2" cwd="$3"
  shift 3
  new_run
  ( cd "$cwd" && env PATH="$bindir:$PATH" MATRIX_DIR="$mdir" GITHUB_OUTPUT="$RUN_GO" \
      RUNNER_TEMP="$RUN_RT" CI_SSH_PUB="$TMP/ci_ssh_key.pub" STUB_LOG="$RUN_LOG" \
      DOPPLER_TOKEN=stub-doppler DOPPLER_PROJECT=soleur DOPPLER_CONFIG=prd_terraform \
      "$@" bash --noprofile --norc -e "$TMP/plan-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}

out_val() { sed -n "s/^$1=//p" "$RUN_GO" | tail -1; }
log_has() { grep -qxF -- "$1" "$RUN_LOG"; }
tf_calls() { grep -c '^TF_ARGV' "$RUN_LOG"; }

# check_sentry_arm <want-exit-code> — the B1 contract. Prints each unmet clause; returns 1 on any.
check_sentry_arm() {
  local want="$1" bad=0 argv
  argv=$(grep '^TF_ARGV' "$RUN_LOG" | head -1)
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC under bash -e"; bad=1; }
  [[ "$(out_val exit_code)" == "$want" ]] || { echo "    exit_code=$(out_val exit_code), want $want"; bad=1; }
  [[ "$(out_val stack_name)" == "web-platform/sentry" ]] || { echo "    stack_name=$(out_val stack_name)"; bad=1; }
  ! grep -qE '^DOPPLER_(ARGV|CALLED)' "$RUN_LOG" || { echo "    doppler was invoked"; bad=1; }
  [[ "$(tf_calls)" -eq 1 ]] || { echo "    terraform calls=$(tf_calls), want 1"; bad=1; }
  [[ " $argv " == *" plan "* ]] || { echo "    argv lacks plan: $argv"; bad=1; }
  for a in -detailed-exitcode -no-color -input=false; do
    [[ " $argv " == *" $a "* ]] || { echo "    argv lacks $a"; bad=1; }
  done
  [[ " $argv " != *" -target"* ]] || { echo "    argv carries -target"; bad=1; }
  log_has SENTRY_AUTH_TOKEN=SET || { echo "    SENTRY_AUTH_TOKEN not set for terraform"; bad=1; }
  log_has TOKEN_MATCH=yes || { echo "    terraform did not see SENTRY_IAC_AUTH_TOKEN as SENTRY_AUTH_TOKEN"; bad=1; }
  log_has TF_VAR_sentry_auth_token=UNSET || { echo "    TF_VAR_sentry_auth_token set"; bad=1; }
  log_has DOPPLER_TOKEN=UNSET || { echo "    DOPPLER_TOKEN reached terraform"; bad=1; }
  log_has TF_LOG=UNSET || { echo "    TF_LOG reached terraform"; bad=1; }
  return "$bad"
}

# Not `detail=$("$@")`: a command substitution is a subshell, so the run counter and any
# FATAL `exit 2` inside a check would be discarded. The detail goes through a file instead.
row() { # row <id> <description> <check-cmd...>
  local id="$1" desc="$2" st
  shift 2
  "$@" > "$TMP/row-detail"
  st=$?
  if [[ "$st" -eq 0 ]]; then pass "$id $desc"; else fail "$id $desc"; cat "$TMP/row-detail"; fi
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
    run_plan "$TMP/bin" "$d" "$REPO_ROOT/$d" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-s1 STUB_TF_RC=2
    [[ "$(out_val exit_code)" == "2" && "$RUN_RC" -eq 0 ]] || {
      echo "    $d driven with stub rc 2: exit_code=$(out_val exit_code) rc=$RUN_RC"; bad=1; }
  done < "$TMP/matrix.txt"
  return "$bad"
}
row S1 "matrix holds each of the three roots once, each is an s3-backed dir, each maps stub rc 2 to exit_code=2" s1

s2() {
  local bad=0 c line
  c=$(grep -c 'secrets\.SENTRY_IAC_AUTH_TOKEN' "$WF")
  [[ "$c" -eq 1 ]] || { echo "    secrets.SENTRY_IAC_AUTH_TOKEN appears $c times in the file, want 1"; bad=1; }
  line=$(grep 'secrets\.SENTRY_IAC_AUTH_TOKEN' "$WF" | head -1)
  [[ "$line" == *"matrix.directory == '$SENTRY_DIR'"* ]] || { echo "    the binding is not gated on the sentry leg"; bad=1; }
  python3 - "$TMP/plan-env.json" <<'PY' || bad=1
import json, sys
env = json.load(open(sys.argv[1]))
v = env.get("SENTRY_IAC_AUTH_TOKEN", "")
if "secrets.SENTRY_IAC_AUTH_TOKEN" not in v:
    print("    plan step env has no SENTRY_IAC_AUTH_TOKEN bound from the secret")
    sys.exit(1)
PY
  return "$bad"
}
row S2 "the secret is bound once, in the plan step env, gated on the sentry leg" s2

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
b_run() { # b_run <bindir> <stub-rc> [extra env...]
  local bindir="$1" rc="$2"
  shift 2
  run_plan "$bindir" "$SENTRY_DIR" "$TMP" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-b EXPECT_SENTRY_TOKEN=synthetic-iac-b \
    TF_LOG=DEBUG STUB_TF_RC="$rc" "$@"
}
b1() { b_run "$TMP/bin" 2; check_sentry_arm 2; }
row B1 "sentry leg, stub rc 2: exit_code=2, raw token, no doppler, no DOPPLER_TOKEN/TF_LOG, one full-root plan" b1
b2() { b_run "$TMP/bin" 0; check_sentry_arm 0; }
row B2 "sentry leg, stub rc 0: exit_code=0" b2
b3() { b_run "$TMP/bin" 1; check_sentry_arm 1; }
row B3 "sentry leg, stub rc 1: exit_code=1" b3

b4() {
  local bad=0
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" SENTRY_IAC_AUTH_TOKEN= STUB_TF_RC=0
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
    run_plan "$TMP/bin" "$d" "$REPO_ROOT/$d" STUB_TF_RC="$want_rc"
    grep -q '^DOPPLER_ARGV run --preserve-env --name-transformer tf-var -- terraform plan -detailed-exitcode' "$RUN_LOG" \
      || { echo "    $d: doppler tf-var path not taken"; bad=1; }
    [[ "$(out_val exit_code)" == "$want_rc" ]] || { echo "    $d: exit_code=$(out_val exit_code), want $want_rc"; bad=1; }
    [[ "$(out_val stack_name)" == "$want_stack" ]] || { echo "    $d: stack_name=$(out_val stack_name)"; bad=1; }
  done
  return "$bad"
}
row B5 "the main and github legs keep their doppler tf-var plan and stack names" b5

b7() {
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" SENTRY_AUTH_TOKEN=decoy-x SENTRY_IAC_AUTH_TOKEN=iac-y \
    EXPECT_SENTRY_TOKEN=iac-y STUB_TF_RC=0
  log_has TOKEN_MATCH=yes || { echo "    terraform saw the ambient SENTRY_AUTH_TOKEN, not SENTRY_IAC_AUTH_TOKEN"; return 1; }
}
row B7 "an ambient SENTRY_AUTH_TOKEN is overridden by SENTRY_IAC_AUTH_TOKEN" b7

b8() {
  local tok="synthetic-iac-$RANDOM$RANDOM" bad=0
  run_plan "$TMP/bin" "$SENTRY_DIR" "$TMP" SENTRY_IAC_AUTH_TOKEN="$tok" STUB_TF_ECHO_TOKEN=1 STUB_TF_RC=1
  [[ -s "$RUN_RT/plan-output.txt" ]] || { echo "    no plan-output.txt"; return 1; }
  ! grep -qF -- "$tok" "$RUN_RT/plan-output.txt" || { echo "    the token survived into plan-output.txt"; bad=1; }
  grep -qF '***' "$RUN_RT/plan-output.txt" || { echo "    no *** redaction marker"; bad=1; }
  return "$bad"
}
row B8 "a token echoed by the provider is scrubbed from plan-output.txt (posted to a public issue)" b8

h1() { b_run "$TMP/bin-h1" 2; if check_sentry_arm 2 > /dev/null; then echo "    B1 passed under a stub that ignores STUB_TF_RC"; return 1; fi; }
row H1 "harness: B1's contract reds under a terraform stub that ignores STUB_TF_RC" h1

# ---------------------------------------------------------------------------
# EMAIL + ISSUE STEPS
# ---------------------------------------------------------------------------
run_email() { # run_email <plan-output-file>
  new_run
  cp "$1" "$RUN_RT/plan-output.txt" || { echo "FATAL: email fixture"; exit 2; }
  ( cd "$TMP" && env GITHUB_OUTPUT="$RUN_GO" RUNNER_TEMP="$RUN_RT" EXIT_CODE=1 \
      STACK_NAME=web-platform/sentry GITHUB_SERVER_URL=https://github.example GITHUB_REPOSITORY=o/r \
      GITHUB_RUN_ID=1 bash --noprofile --norc -e "$TMP/email-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}
for i in $(seq 1 120); do
  printf 'module.monitoring.sentry_alert.rule_%03d_padding_for_length: Refreshing state... [id=1000%03d]\n' "$i" "$i"
done > "$TMP/refresh-only.txt"
{ cat "$TMP/refresh-only.txt"; echo "Error: boom"; } > "$TMP/refresh-then-error.txt"

e1() {
  local bad=0
  run_email "$TMP/refresh-then-error.txt"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC"; bad=1; }
  grep -qF 'Error: boom' "$RUN_GO" || { echo "    the email body lacks the error line"; bad=1; }
  ! grep -qF 'Refreshing state' "$RUN_GO" || { echo "    the email body carries refresh lines"; bad=1; }
  return "$bad"
}
row E1 "the error email shows the error, not 4000 bytes of refresh lines" e1

e2() {
  local bad=0
  run_email "$TMP/refresh-only.txt"
  [[ "$RUN_RC" -eq 0 ]] || { echo "    step rc=$RUN_RC under bash -e"; bad=1; }
  ! grep -qF '<pre>' "$RUN_GO" || { echo "    an all-refresh output still produced a snippet"; bad=1; }
  return "$bad"
}
row E2 "an all-refresh plan output yields an empty snippet and step rc 0" e2

run_issue() { # run_issue <matrix-dir> <stack>
  new_run
  printf 'plan text\n' > "$RUN_RT/plan-output.txt"
  ( cd "$TMP" && env PATH="$TMP/bin:$PATH" STUB_LOG="$RUN_LOG" STUB_GH_BODY="$RUN_RT/body.md" \
      MATRIX_DIR="$1" STACK_NAME="$2" RUNNER_TEMP="$RUN_RT" GH_TOKEN=stub RUN_NUMBER=7 \
      SERVER_URL=https://github.example REPOSITORY=o/r RUN_ID=1 \
      bash --noprofile --norc -e "$TMP/issue-step.sh" ) > "$RUN_OUT" 2>&1
  RUN_RC=$?
}

i1() {
  local bad=0
  run_issue "$SENTRY_DIR" web-platform/sentry
  [[ -s "$RUN_RT/body.md" ]] || { echo "    no issue body rendered (rc=$RUN_RC)"; return 1; }
  grep -qF 'gh workflow run apply-sentry-infra.yml --ref main -f reason=' "$RUN_RT/body.md" \
    || { echo "    body lacks the CI-apply remediation"; bad=1; }
  ! grep -qF 'If the drift is intentional,' "$RUN_RT/body.md" || { echo "    body keeps the local-apply line"; bad=1; }
  ! grep -q '^GH_ARGV workflow' "$RUN_LOG" || { echo "    rendering the body EXECUTED gh workflow run"; bad=1; }
  return "$bad"
}
row I1 "the sentry drift issue names the CI apply (never a local apply) and executes nothing" i1

i2() {
  local bad=0
  run_issue apps/web-platform/infra web-platform
  [[ -s "$RUN_RT/body.md" ]] || { echo "    no issue body rendered (rc=$RUN_RC)"; return 1; }
  grep -qF 'If the drift is intentional,' "$RUN_RT/body.md" || { echo "    main-root body lost its step 2"; bad=1; }
  ! grep -qF 'apply-sentry-infra' "$RUN_RT/body.md" || { echo "    main-root body names the sentry apply"; bad=1; }
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
      ( cd "$FX" && env PATH="$TMP/bin-r:$PATH" STUB_LOG="$RUN_LOG" MATRIX_DIR="$SENTRY_DIR" GITHUB_OUTPUT="$RUN_GO" RUNNER_TEMP="$RUN_RT" \
          CI_SSH_PUB="$TMP/ci_ssh_key.pub" SENTRY_IAC_AUTH_TOKEN=synthetic-iac-r \
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
# Anti-vacuity floor: the 17 unconditional rows (S1-S5, B1-B5, B7, B8, H1, E1, E2, I1, I2).
# The R rows add 4 on top when terraform is present. A floor, not an equality.
FLOOR=17
if (( PASS + FAIL < FLOOR )); then
  printf 'FATAL: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$FLOOR"
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
