#!/usr/bin/env bash
# Self-test for the `parked-hold` required-check member step (#12396; ADR-032 amendment 2026-11-08).
#
# WHAT THIS PROVES. scripts/ci-parked-hold.sh is the ONE evaluator behind the `parked-hold` member
# step of the `secret-guards` umbrella in .github/workflows/secret-scan.yml. This suite RUNS it
# (no grep of its text) with a stubbed `gh` on a PRIVATE PATH prefix: no network, no credential, no
# real PR is touched. It also
#   * extracts the workflow step's `run:` block and executes it under `bash --noprofile --norc -eo
#     pipefail`, with the step's env supplied by this suite. The runner itself uses `bash -e {0}`
#     (the steps carry no `shell:` key, so no pipefail): this is STRICTER than the runner, never looser;
#   * pins the workflow SHAPE (events: labeled/unlabeled and merge_group; aggregate
#     membership; step-level event condition; no job-level `if:`; env hoisting; the umbrella's
#     `pull-requests: write`; the job's and both parked-hold steps' keys against an allow-list read from the
#     PARSED YAML, so no spelling of `continue-on-error`, `shell:` or `defaults:` gets past it) and proves the checker is
#     not vacuous by feeding it one mutated copy of the workflow per pinned category, each of which it
#     must reject (section D);
#   * mutates the evaluator itself (case-sensitive match, fail-open, loose queue ref, no retry, extra gh
#     flags, the unevaluable-label arm, the leading-zero normalisation, queue-ref drift) and runs ONE
#     targeted probe per mutant, which must see correct behaviour on the pristine script and wrong
#     behaviour on the mutant (section C);
#   * runs scripts/lint-umbrella-aggregate.sh against a scratch copy of the workflows with
#     every neutraliser the lint's rules name injected into a required umbrella (any spelling of
#     `continue-on-error`, `shell:`, a job-level `if:`, a constant or foreign verdict argument, an early
#     `exit`, ...), each of which must fail with the finding that names its rule (section G).
#
# Guard Contract rows (plan 2026-11-08-feat-founder-acceptance-record-followups-plan.md, Guard 1):
#   1 mixed-case label        -> rows "Parked"/"PARKED"      (mutant: case-sensitive)
#   2 gh API failure          -> rows "gh exits non-zero"    (mutant: fail-open)
#   3 head_ref does not match -> rows "ref ..."              (mutant: loose queue ref)
#   4 payload vs live         -> row  "payload vs live"
#   5-8 workflow shape        -> shape_check against mutated workflow copies
#   9 empty call list         -> the anti-vacuity floor below
#  10 bounded retry           -> rows "one 5xx then 200" / "persistent 5xx" (mutant: no retry)
#
# Prints a row count and then the final line `parked-hold selftest ok` on success. Needs bash, jq,
# python3, git.
#
# SC2046 (word splitting of `$(pr_env N)`) is disabled file-wide below: pr_env and mg_env print fixed
# `KEY=value` words whose values are digits or a queue ref, never whitespace or glob characters, and
# the word split is exactly how they hand several `env` assignments to run_hold.
# shellcheck disable=SC2046
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/ci-parked-hold.sh"
WORKFLOW="$ROOT/.github/workflows/secret-scan.yml"
ORIG_PATH="$PATH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
rows=0
quiet=0

ok()   { rows=$((rows + 1)); [ "$quiet" -eq 1 ] || printf 'ok   %s\n' "$1"; }
bad()  { rows=$((rows + 1)); fails=$((fails + 1)); [ "$quiet" -eq 1 ] || printf 'FAIL %s\n' "$1" >&2; }

# ─── the stubbed gh (private PATH prefix) ───────────────────────────────────────────────────────
STUB="$WORK/stub"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Stub gh: logs argv, serves numbered canned responses from $STUB_DIR (resp.N, falling back to
# resp.last). A response file is: line 1 = exit code, line 2 = stderr text, the rest = stdout body.
# It accepts EXACTLY `api repos/jikig-ai/soleur/pulls/<N>` with N canonical, no leading zero (the one call
# the evaluator makes: no flags, no --jq, no --cache). Any other argv is refused with exit 64 and a line in refused.log,
# which every happy-path row asserts is empty (expect_pass), so an extra flag cannot slip through.
: "${STUB_DIR:?}"
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
if [ "$#" -ne 2 ] || [ "$1" != "api" ] || ! [[ "$2" =~ ^repos/jikig-ai/soleur/pulls/[1-9][0-9]*$ ]]; then
  printf 'refused argv: %s\n' "$*" >>"$STUB_DIR/refused.log"
  echo "stub gh: unexpected argv" >&2
  exit 64
fi
n=$(cat "$STUB_DIR/count" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" >"$STUB_DIR/count"
f="$STUB_DIR/resp.$n"
[ -f "$f" ] || f="$STUB_DIR/resp.last"
[ -f "$f" ] || { echo "stub gh: no response configured" >&2; exit 99; }
rc=$(sed -n '1p' "$f")
sed -n '2p' "$f" >&2
sed -n '3,$p' "$f"
exit "$rc"
STUBEOF
chmod +x "$STUB/gh"

# set_resp <n|last> <rc> <stderr> <body>
set_resp() { printf '%s\n%s\n%s\n' "$2" "$3" "$4" >"$STUB_DIR/resp.$1"; }
reset_stub() { rm -f "$STUB_DIR"/resp.* "$STUB_DIR/count" "$STUB_DIR/calls.log" "$STUB_DIR/refused.log"; }
STUB_DIR="$WORK/state"
mkdir -p "$STUB_DIR"
export STUB_DIR

body() { # body <number> <label,label,...>
  local n="$1" labels="${2:-}" j="[]"
  if [ -n "$labels" ]; then
    j=$(printf '%s' "$labels" | jq -R 'split(",") | map({name: .})')
  fi
  jq -nc --argjson n "$n" --argjson l "$j" '{number: $n, state: "open", labels: $l}'
}

SHA40="0123456789abcdef0123456789abcdef01234567"

# run_hold <script> VAR=VAL ...  -> OUT (stdout+stderr), RC
run_hold() {
  local script="$1"; shift
  OUT=$(env -i HOME="$WORK" PATH="$STUB:$ORIG_PATH" STUB_DIR="$STUB_DIR" PARKED_HOLD_RETRY_SLEEP=0 "$@" bash "$script" 2>&1)
  RC=$?
}

expect_fail() { # expect_fail <label> ; uses RC/OUT
  if [ "$RC" -ne 0 ]; then ok "$1"; else bad "$1 (expected non-zero, got 0: $OUT)"; fi
}
expect_pass() { # also requires that the stub refused nothing (the evaluator made only the pinned gh call)
  if [ -s "$STUB_DIR/refused.log" ]; then bad "$1 (stub gh refused an argv: $(head -n1 "$STUB_DIR/refused.log"))"; return; fi
  if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1 (expected 0, got $RC: $OUT)"; fi
}
expect_out() { # expect_out <label> <fixed substring>
  case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1 (output lacks '$2': $OUT)" ;; esac
}
expect_no_out() {
  case "$OUT" in *"$2"*) bad "$1 (output must not contain '$2': $OUT)" ;; *) ok "$1" ;; esac
}

pr_env() { printf '%s\n' "EVENT_NAME=pull_request" "PR_NUMBER=$1" "REPO=jikig-ai/soleur" "GH_TOKEN=stub-token-not-real"; }
mg_env() { printf '%s\n' "EVENT_NAME=merge_group" "MG_HEAD_REF=$1" "REPO=jikig-ai/soleur" "GH_TOKEN=stub-token-not-real"; }

# ─── the behaviour rows, parameterised by the script under test (pristine or mutant) ─────────────
behaviour_rows() {
  local S="$1" a

  # not parked -> pass; the live read targets the named PR
  reset_stub; set_resp last 0 "" "$(body 77 'enhancement,bug')"
  run_hold "$S" $(pr_env 77); expect_pass "not parked passes"
  if grep -q 'repos/jikig-ai/soleur/pulls/77' "$STUB_DIR/calls.log" 2>/dev/null; then ok "live read targets pulls/77"; else bad "live read targets pulls/77"; fi

  # parked -> fail, with the fixed annotation and nothing else
  reset_stub; set_resp last 0 "" "$(body 77 'parked')"
  run_hold "$S" $(pr_env 77); expect_fail "parked fails"
  expect_out "parked annotation names the PR" '::error::PR #77 is held for the operator (label parked). Do not remove the label, merge or arm auto-merge; the operator removes it. A draft PR is held anyway.'
  expect_no_out "parked annotation does not invite lifting the hold" 'Remove the label'

  # Guard row 1: mixed-case label
  for a in Parked PARKED pArKeD; do
    reset_stub; set_resp last 0 "" "$(body 78 "enhancement,$a")"
    run_hold "$S" $(pr_env 78); expect_fail "mixed-case label $a fails"
  done

  # Must-PASS non-canonical input: near-miss names are not the label
  reset_stub; set_resp last 0 "" "$(body 79 'Parked-not,parked-old,unparked,enhancement')"
  run_hold "$S" $(pr_env 79); expect_pass "near-miss label names pass"

  # Label text other than the fixed annotation never reaches the log
  reset_stub; set_resp last 0 "" "$(body 80 'parked,zz-secret-label-text')"
  run_hold "$S" $(pr_env 80); expect_no_out "other label text is never printed" 'zz-secret-label-text'

  # Guard row 4: payload vs live. Payload says no labels, the API says parked: the API wins.
  reset_stub; set_resp last 0 "" "$(body 81 'parked')"
  printf '{"pull_request":{"number":81,"labels":[]}}\n' >"$WORK/event.json"
  run_hold "$S" $(pr_env 81) PR_LABELS='[]' GITHUB_EVENT_PATH="$WORK/event.json"
  expect_fail "payload vs live: payload empty, API parked -> fail"
  reset_stub; set_resp last 0 "" "$(body 82 'enhancement')"
  printf '{"pull_request":{"number":82,"labels":[{"name":"parked"}]}}\n' >"$WORK/event.json"
  run_hold "$S" $(pr_env 82) PR_LABELS='["parked"]' GITHUB_EVENT_PATH="$WORK/event.json"
  expect_pass "payload vs live: payload parked, API clean -> pass (re-run reuses a stale payload)"

  # Guard row 2: gh fails -> closed, with the fixed unreadable annotation and the HTTP code only
  reset_stub; set_resp last 1 "gh: Server Error (HTTP 500)" ""
  run_hold "$S" $(pr_env 83); expect_fail "gh exits non-zero (persistent 5xx) fails"
  expect_out "unreadable annotation carries the HTTP code" '::error::parked-hold: label state unreadable (HTTP 500); re-run the check (this is not a parked hold)'
  reset_stub; set_resp last 1 "gh: Not Found (HTTP 404)" ""
  run_hold "$S" $(pr_env 84); expect_fail "missing PR (404) fails"
  reset_stub; set_resp last 1 "connection reset by peer" ""
  run_hold "$S" $(pr_env 85); expect_fail "gh exits non-zero with no HTTP code fails"
  expect_out "no HTTP code is reported as unknown" '(HTTP unknown)'

  # Guard row 10: bounded retry. One transient 5xx then 200 passes; a persistent 5xx fails after
  # exactly two attempts (never an unbounded loop).
  reset_stub; set_resp 1 1 "gh: Bad Gateway (HTTP 502)" ""; set_resp last 0 "" "$(body 86 'enhancement')"
  run_hold "$S" $(pr_env 86); expect_pass "one 5xx then 200 passes"
  reset_stub; set_resp 1 1 "gh: Bad Gateway (HTTP 502)" ""; set_resp last 0 "" "$(body 87 'parked')"
  run_hold "$S" $(pr_env 87); expect_fail "one 5xx then 200 parked still fails"
  reset_stub; set_resp last 1 "gh: Bad Gateway (HTTP 502)" ""
  run_hold "$S" $(pr_env 88)
  if [ "$(cat "$STUB_DIR/count" 2>/dev/null)" = "2" ]; then ok "persistent 5xx makes exactly 2 attempts"; else bad "persistent 5xx makes exactly 2 attempts (got $(cat "$STUB_DIR/count" 2>/dev/null))"; fi

  # Unparseable / wrong bodies must not pass as "not parked"
  reset_stub; set_resp last 0 "" "<html>not json</html>"
  run_hold "$S" $(pr_env 89); expect_fail "unparseable JSON fails"
  reset_stub; set_resp last 0 "" "$(body 999 'enhancement')"
  run_hold "$S" $(pr_env 90); expect_fail "body for a different PR number fails"
  reset_stub; set_resp last 0 "" '{"number":91,"labels":null}'
  run_hold "$S" $(pr_env 91); expect_fail "labels not an array fails"
  expect_out "labels null carries the body-shape annotation" '::error::parked-hold: label state unreadable (unexpected response body); re-run the check (this is not a parked hold)'
  reset_stub; set_resp last 0 "" '{"number":92}'
  run_hold "$S" $(pr_env 92); expect_fail "labels missing fails"
  expect_out "labels missing carries the body-shape annotation" '::error::parked-hold: label state unreadable (unexpected response body); re-run the check (this is not a parked hold)'
  reset_stub; set_resp last 0 "" ''
  run_hold "$S" $(pr_env 93); expect_fail "empty body fails"
  # A labels value that is an OBJECT or a STRING is not a label list. `{}` iterates as zero labels, so only the
  # `.labels | type == "array"` clause stops it passing as "does not carry parked".
  reset_stub; set_resp last 0 "" '{"number":94,"labels":{}}'
  run_hold "$S" $(pr_env 94); expect_fail "labels is an empty object fails"
  expect_out "labels object carries the body-shape annotation" '::error::parked-hold: label state unreadable (unexpected response body); re-run the check (this is not a parked hold)'
  reset_stub; set_resp last 0 "" '{"number":95,"labels":"parked"}'
  run_hold "$S" $(pr_env 95); expect_fail "labels is a string fails"
  expect_out "labels string carries the body-shape annotation" '::error::parked-hold: label state unreadable (unexpected response body); re-run the check (this is not a parked hold)'

  # The jq error mapping: a label list that parses as an array but cannot be evaluated (an element that
  # is not an object) is neither "parked" nor "not parked", so it fails closed with its own annotation.
  reset_stub; set_resp last 0 "" '{"number":5,"labels":[1]}'
  run_hold "$S" $(pr_env 5); expect_fail "label element that is not an object fails"
  expect_out "unevaluable label list carries its annotation" '::error::parked-hold: label state unreadable (label list could not be evaluated); re-run the check (this is not a parked hold)'

  # A zero-padded PR_NUMBER is normalised: the API is asked for pulls/77 and the body number 77 matches.
  reset_stub; set_resp last 0 "" "$(body 77 'enhancement')"
  run_hold "$S" $(pr_env 0077); expect_pass "zero-padded PR_NUMBER 0077 matches body number 77"
  if grep -qx 'api repos/jikig-ai/soleur/pulls/77' "$STUB_DIR/calls.log" 2>/dev/null; then ok "zero-padded PR_NUMBER reads pulls/77"; else bad "zero-padded PR_NUMBER reads pulls/77"; fi

  # Input validation happens before any gh call
  for a in "" "abc" "12x" "1;id" '$(id)' "-1"; do
    reset_stub; set_resp last 0 "" "$(body 5 'enhancement')"
    run_hold "$S" EVENT_NAME=pull_request "PR_NUMBER=$a" REPO=jikig-ai/soleur GH_TOKEN=stub
    expect_fail "PR_NUMBER '$a' rejected"
    [ ! -f "$STUB_DIR/calls.log" ] && ok "PR_NUMBER '$a' makes no gh call" || bad "PR_NUMBER '$a' makes no gh call"
  done
  reset_stub; set_resp last 0 "" "$(body 5 'enhancement')"
  run_hold "$S" EVENT_NAME=pull_request PR_NUMBER=5 REPO='evil/repo;x' GH_TOKEN=stub
  expect_fail "malformed REPO rejected"

  # merge_group: PR number comes from the queue ref (the mg_arm regex), checked against its own PR
  reset_stub; set_resp last 0 "" "$(body 123 'enhancement')"
  run_hold "$S" $(mg_env "refs/heads/gh-readonly-queue/main/pr-123-$SHA40")
  expect_pass "merge_group queue ref, not parked, passes"
  if grep -q 'pulls/123' "$STUB_DIR/calls.log" 2>/dev/null; then ok "merge_group reads PR 123 from the ref"; else bad "merge_group reads PR 123 from the ref"; fi
  reset_stub; set_resp last 0 "" "$(body 123 'parked')"
  run_hold "$S" $(mg_env "refs/heads/gh-readonly-queue/main/pr-123-$SHA40")
  expect_fail "merge_group queue ref, parked, fails"

  # Guard row 3: refs that do not match fail closed and make no gh call
  for a in "" "refs/heads/main" "refs/heads/gh-readonly-queue/main/pr-123" \
           "refs/heads/gh-readonly-queue/main/pr-123-abc" \
           "refs/heads/gh-readonly-queue/main/pr-abc-$SHA40" \
           "refs/heads/gh-readonly-queue/other/pr-123-$SHA40" \
           "refs/heads/gh-readonly-queue/main/pr-123-${SHA40}0" \
           "refs/heads/gh-readonly-queue/main/pr-123-$SHA40/x"; do
    reset_stub; set_resp last 0 "" "$(body 123 'enhancement')"
    run_hold "$S" $(mg_env "$a"); expect_fail "ref '${a:-<empty>}' does not match fails"
  done
  reset_stub; set_resp last 0 "" "$(body 123 'enhancement')"
  run_hold "$S" $(mg_env "refs/heads/main"); [ ! -f "$STUB_DIR/calls.log" ] && ok "bad ref makes no gh call" || bad "bad ref makes no gh call"

  # Events with no PR (push, schedule) are a no-op that never fails main's scans
  for a in push schedule; do
    reset_stub; set_resp last 1 "gh: should not be called (HTTP 500)" ""
    run_hold "$S" EVENT_NAME="$a" REPO=jikig-ai/soleur
    expect_pass "$a event is a no-op"
    [ ! -f "$STUB_DIR/calls.log" ] && ok "$a event makes no gh call" || bad "$a event makes no gh call"
  done
}

# ─── the workflow-shape checker (text pins plus a PyYAML key allow-list; companion of lint-umbrella-aggregate.sh) ─
shape_check() { # shape_check <workflow file>  -> 0 iff every shape assertion holds
  python3 -I - "$1" <<'PYEOF'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
errs = []

def err(m):
    errs.append(m)

# on.pull_request.types carries labeled and unlabeled (a re-run on a label event is the whole mechanism)
m = None
for i, l in enumerate(lines):
    if re.match(r"^  pull_request:\s*$", l):
        for j in range(i + 1, min(i + 12, len(lines))):
            t = re.match(r"^\s+types:\s*\[(.*)\]", lines[j])
            if t:
                m = [x.strip() for x in t.group(1).split(",")]
                break
        break
if m is None:
    err("on.pull_request.types not found")
else:
    for need in ("labeled", "unlabeled"):
        if need not in m:
            err(f"on.pull_request.types lacks {need}")
if not any(re.match(r"^  merge_group:", l) for l in lines):
    err("merge_group trigger missing")

# secret-guards job region
start = next((i for i, l in enumerate(lines) if l == "  secret-guards:"), None)
if start is None:
    print("secret-guards job not found"); sys.exit(1)
end = len(lines)
for j in range(start + 1, len(lines)):
    if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[j]):
        end = j; break
job = lines[start:end]
steps_at = next((i for i, l in enumerate(job) if l == "    steps:"), None)
if steps_at is None:
    err("steps: not found in secret-guards")
    head = job
else:
    head = job[:steps_at]
if any(re.match(r"^    if:", l) for l in head):
    err("secret-guards carries a JOB-level if: (a required context must report on every event)")
if not any(re.match(r"^      pull-requests: write", l) for l in head):
    err("secret-guards lacks pull-requests: write (inherited from the umbrella; the label read itself needs only read)")

# The key rules below read the PARSED workflow, not the text: YAML spells one key many ways (bare, "quoted",
# 'quoted', first key after `- `, flow mapping), and a text match sees only the spelling it was written for.
try:
    import yaml
    parsed = yaml.safe_load(open(sys.argv[1], encoding="utf-8").read())
    pjob = parsed["jobs"]["secret-guards"]
    psteps = {x.get("id"): x for x in pjob["steps"] if isinstance(x, dict) and x.get("id")}
except Exception as e:  # PyYAML absent or the file unparseable: this pin cannot hold, so it fails
    err(f"cannot parse the workflow as YAML ({type(e).__name__}); the key allow-list pins cannot run")
    pjob, psteps = {}, {}
JOB_ALLOWED = {"name", "runs-on", "timeout-minutes", "permissions", "steps"}
STEP_ALLOWED = {"id", "if", "name", "env", "run"}
for k in pjob:
    if k not in JOB_ALLOWED:
        err(f"secret-guards job key `{k}` is outside the allow-list (continue-on-error, if and defaults would each neutralise a required context)")

def step_block(sid):
    # A step runs from its `- id:` line to the next step (`      - `) or the job boundary. A 6-space
    # comment INSIDE the step does not end it (keys after it must stay visible); the comment and blank
    # lines that merely precede the NEXT step are trimmed off the end.
    for i, l in enumerate(job):
        if l == f"      - id: {sid}":
            end = len(job)
            for j in range(i + 1, len(job)):
                if re.match(r"^      - ", job[j]):
                    end = j
                    break
            while end > i + 1 and (job[end - 1].strip() == "" or re.match(r"^      #", job[end - 1])):
                end -= 1
            return job[i:end]
    return None

COND = "if: ${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}"
for sid in ("parked-hold", "parked-hold-selftest"):
    b = step_block(sid)
    if b is None:
        err(f"step {sid} missing"); continue
    if not any(l.strip() == COND for l in b):
        err(f"step {sid} lacks the step-level event condition")
    txt = "\n".join(b)
    for k in psteps.get(sid, {}):
        if k not in STEP_ALLOWED:
            err(f"step {sid} carries the key `{k}` (continue-on-error would turn a red step's conclusion into success; shell: would stop the command running)")
    run = re.search(r"\n        run: (.*)", txt)
    if not run:
        err(f"step {sid} has no run:")
    elif "${{" in run.group(1):
        err(f"step {sid} run: interpolates ${{{{ }}}} (inputs must go through env:)")
    if "github.head_ref" in txt or "pull_request.labels" in txt:
        err(f"step {sid} reads head_ref or payload labels")

hold = step_block("parked-hold")
if hold:
    txt = "\n".join(hold)
    for k, v in (("EVENT_NAME", "${{ github.event_name }}"),
                 ("PR_NUMBER", "${{ github.event.pull_request.number }}"),
                 ("MG_HEAD_REF", "${{ github.event.merge_group.head_ref }}"),
                 ("REPO", "${{ github.repository }}"),
                 ("GH_TOKEN", "${{ github.token }}")):
        if f"          {k}: {v}" not in txt:
            err(f"parked-hold env lacks {k}: {v}")
    if "bash scripts/ci-parked-hold.sh" not in txt:
        err("parked-hold does not call scripts/ci-parked-hold.sh")
st = step_block("parked-hold-selftest")
if st:
    txt = "\n".join(st)
    if "GH_TOKEN" in txt:
        err("parked-hold-selftest must receive no GH_TOKEN")
    if "bash scripts/ci-parked-hold.test.sh" not in txt:
        err("parked-hold-selftest does not call scripts/ci-parked-hold.test.sh")

# aggregate: each step in its own member line, scope pull_request,merge_group, || failed=1
agg = step_block("aggregate")
atxt = "\n".join(agg) if agg else ""
for sid in ("parked-hold", "parked-hold-selftest"):
    pat = (r"member " + re.escape(sid) + r" 'pull_request,merge_group' '" + re.escape(sid) + r"' '\$\{\{ steps\." + re.escape(sid)
           + r"\.conclusion \}\}' '\$\{\{ steps\." + re.escape(sid) + r"\.outcome \}\}' \|\| failed=1")
    if not re.search(pat, atxt):
        err(f"aggregate lacks its own member line for {sid}")

if errs:
    print("\n".join(errs)); sys.exit(1)
PYEOF
}

# extract_run <workflow> <step id>: print the step's run: value (single line or block scalar)
extract_run() {
  python3 -I - "$1" "$2" <<'PYEOF'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
sid = sys.argv[2]
for i, l in enumerate(lines):
    if l == f"      - id: {sid}":
        j = i + 1
        while j < len(lines) and not re.match(r"^      - ", lines[j]) and not re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[j]):
            m = re.match(r"^        run: (.*)$", lines[j])
            if m:
                v = m.group(1)
                if v in ("|", "|-", ">"):
                    out = []
                    k = j + 1
                    while k < len(lines) and (lines[k].startswith("          ") or lines[k] == ""):
                        out.append(lines[k][10:])
                        k += 1
                    print("\n".join(out))
                else:
                    print(v)
                sys.exit(0)
            j += 1
sys.exit(1)
PYEOF
}

# ─── A. behaviour of the pristine evaluator ──────────────────────────────────────────────────────
[ -f "$SCRIPT" ] || { echo "FAIL scripts/ci-parked-hold.sh is missing" >&2; exit 1; }
behaviour_rows "$SCRIPT"

# ─── B. refuses to run traced with a live credential ────────────────────────────────────────────
OUT=$(env -i HOME="$WORK" PATH="$STUB:$ORIG_PATH" GH_TOKEN=stub EVENT_NAME=push bash -x "$SCRIPT" 2>&1); RC=$?
if [ "$RC" -eq 78 ]; then ok "refuses under set -x with a live GH_TOKEN"; else bad "refuses under set -x with a live GH_TOKEN (rc $RC)"; fi
case "$OUT" in *stub*GH_TOKEN*|*"GH_TOKEN=stub"*) bad "no token expansion in the trace" ;; *) ok "no token expansion in the trace" ;; esac

# ─── C. the evaluator's mutants must each drive the behaviour rows RED ───────────────────────────
# One targeted probe per mutant (each returns 0 iff the evaluator under test behaves correctly), so the
# mutation battery stays cheap: the full behaviour rows above already ran against the pristine script.
probe_case()     { reset_stub; set_resp last 0 "" "$(body 31 'Parked')"; run_hold "$1" $(pr_env 31); [ "$RC" -ne 0 ]; }
probe_failopen() { reset_stub; set_resp last 1 "gh: Server Error (HTTP 500)" ""; run_hold "$1" $(pr_env 32); [ "$RC" -ne 0 ]; }
probe_ref()      { reset_stub; set_resp last 0 "" "$(body 33 'enhancement')"; run_hold "$1" $(mg_env "refs/heads/gh-readonly-queue/main/pr-33-abc"); [ "$RC" -ne 0 ]; }
probe_retry()    { reset_stub; set_resp 1 1 "gh: Bad Gateway (HTTP 502)" ""; set_resp last 0 "" "$(body 34 'enhancement')"; run_hold "$1" $(pr_env 34); [ "$RC" -eq 0 ]; }
probe_argv()     { reset_stub; set_resp last 0 "" "$(body 35 'enhancement')"; run_hold "$1" $(pr_env 35); [ "$RC" -eq 0 ] && [ ! -s "$STUB_DIR/refused.log" ]; }
probe_evalarm()  { reset_stub; set_resp last 0 "" '{"number":36,"labels":[1]}'; run_hold "$1" $(pr_env 36); [ "$RC" -ne 0 ]; }
probe_labelsobj() { reset_stub; set_resp last 0 "" '{"number":38,"labels":{}}'; run_hold "$1" $(pr_env 38); [ "$RC" -ne 0 ]; }
probe_bodyann()  { reset_stub; set_resp last 0 "" '{"number":39,"labels":null}'; run_hold "$1" $(pr_env 39); [ "$RC" -ne 0 ] && [[ "$OUT" == *'::error::parked-hold: label state unreadable (unexpected response body); re-run the check (this is not a parked hold)'* ]]; }
probe_zeropad()  { reset_stub; set_resp last 0 "" "$(body 37 'enhancement')"; run_hold "$1" $(pr_env 0037); [ "$RC" -eq 0 ] && [ ! -s "$STUB_DIR/refused.log" ]; }

mutant() { # mutant <name> <probe> <sed expression>: the probe must see correct behaviour on the pristine script and wrong behaviour on the mutant
  local name="$1" probe="$2" expr="$3" f="$WORK/mutant-$1.sh"
  sed -E "$expr" "$SCRIPT" >"$f"
  if cmp -s "$SCRIPT" "$f"; then bad "mutant $name did not change the script (anchor drifted)"; return; fi
  if ! "$probe" "$SCRIPT"; then bad "mutant $name: probe fails on the pristine script"; return; fi
  if "$probe" "$f"; then bad "mutant $name survived"; else ok "mutant $name driven RED"; fi
}
mutant case-sensitive probe_case 's/\| ascii_downcase//'
mutant fail-open probe_failopen 's/exit 1 # GUARD:fail-closed/exit 0/'
mutant loose-queue-ref probe_ref 's/\[0-9a-f\]\{40\}\$/.*/'
mutant no-retry probe_retry 's/(while \[ "\$attempt") -lt 2/\1 -lt 1/'
mutant extra-gh-flag probe_argv 's/gh api "repos/gh api --cache 1h "repos/'
mutant eval-arm-passes probe_evalarm 's/(\*\)) fail "[^"]*"/\1 exit 0/'
mutant drop-labels-array-clause probe_labelsobj 's/ and \(\.labels \| type == "array"\)//'
mutant drop-body-annotation-suffix probe_bodyann 's/(\(unexpected response body\)); re-run the check \(this is not a parked hold\)/\1/'
mutant no-leading-zero-normalisation probe_zeropad 's/^pr=\$\(\(10#\$pr\)\).*$//'

# The queue-ref regex is a parity-pinned copy of the one in the two sibling scripts (ADR-270 mg_arm). What is
# compared: the whole anchored literal `^refs/heads/gh-readonly-queue/main/pr-([0-9]+)-<sha>$`, extracted from
# each file, with the SIBLINGS' parentheses around the SHA group removed (they capture the embedded oid; this
# script does not need it). The PR-number group, the `main` base, the 40-hex length and both anchors are compared.
QREF_RE='\^refs/heads/gh-readonly-queue/main/pr-\(\[0-9\]\+\)-\(?\[0-9a-f\]\{40\}\)?\$'
# Comments are stripped BEFORE the literal is extracted: a `# was: <old literal>` line must not be able to supply the
# matching literal for a loosened live regex. A whole-line comment goes, and so does a `<space># ...` tail.
qref_of() { # <file> -> the queue-ref literals in its CODE, one per occurrence, SHA capture group parens removed; empty when none
  sed -E -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$1" | { grep -oE "$QREF_RE" || true; } | sed -E 's/-\((\[0-9a-f\]\{40\})\)\$/-\1$/'
}
qref_parity() { # qref_parity <this script> <oracle copy> <cla copy>: 0 iff each carries exactly ONE literal and all three are equal
  local a b c
  a="$(qref_of "$1")"; b="$(qref_of "$2")"; c="$(qref_of "$3")"
  [ -n "$a" ] && [ "$(printf '%s\n' "$a" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$b" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$c" | wc -l)" -eq 1 ] \
    && [ "$a" = "$b" ] && [ "$a" = "$c" ]
}
ORACLE="$ROOT/scripts/ci-oracle-review.sh"; CLA="$ROOT/scripts/merge-queue-cla-verify.sh"
if qref_parity "$SCRIPT" "$ORACLE" "$CLA"; then ok "queue-ref regex matches ci-oracle-review.sh and merge-queue-cla-verify.sh"; else bad "queue-ref regex matches ci-oracle-review.sh and merge-queue-cla-verify.sh"; fi
qref_mutant() { # qref_mutant <name> <which: script|oracle|cla>: one file's regex drifts; the parity row must go RED
  local name="$1" which="$2" f="$WORK/qref-$1.sh" src
  case "$which" in script) src="$SCRIPT" ;; oracle) src="$ORACLE" ;; cla) src="$CLA" ;; esac
  sed -E 's/pr-\(\[0-9\]\+\)-/pr-([0-9]*)-/' "$src" >"$f"
  if cmp -s "$src" "$f"; then bad "queue-ref mutant $name did not change $which (anchor drifted)"; return; fi
  local s="$SCRIPT" o="$ORACLE" c="$CLA"
  case "$which" in script) s="$f" ;; oracle) o="$f" ;; cla) c="$f" ;; esac
  if qref_parity "$s" "$o" "$c"; then bad "queue-ref mutant $name survived"; else ok "queue-ref mutant $name rejected"; fi
}
qref_mutant drift-in-script script
qref_mutant drift-in-oracle oracle
qref_mutant drift-in-cla cla
# A comment that still carries the ORIGINAL literal above a loosened live regex must not satisfy the parity row.
qref_carrier_mutant() { # qref_carrier_mutant <name> <which: oracle|cla>
  local name="$1" which="$2" f="$WORK/qref-$1.sh" src o="$ORACLE" c="$CLA"
  case "$which" in oracle) src="$ORACLE" ;; cla) src="$CLA" ;; esac
  python3 -I - "$src" "$f" <<'PYEOF'
import re, sys
lit = re.compile(r"\^refs/heads/gh-readonly-queue/main/pr-\(\[0-9\]\+\)-\(?\[0-9a-f\]\{40\}\)?\$")
out = []
for l in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if lit.search(l) and not l.lstrip().startswith("#"):
        out.append("# was: " + l.strip())  # the original literal survives, as a comment only
        l = l.replace("pr-([0-9]+)-", "pr-([0-9]*)-")
    out.append(l)
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out))
PYEOF
  if cmp -s "$src" "$f"; then bad "queue-ref carrier mutant $name did not change $which (anchor drifted)"; return; fi
  if ! grep -qE '^# was: .*pr-\(\[0-9\]\+\)-' "$f"; then bad "queue-ref carrier mutant $name did not plant the comment carrier"; return; fi
  case "$which" in oracle) o="$f" ;; cla) c="$f" ;; esac
  if qref_parity "$SCRIPT" "$o" "$c"; then bad "queue-ref carrier mutant $name survived (a comment supplied the literal)"; else ok "queue-ref carrier mutant $name rejected"; fi
}
qref_carrier_mutant comment-carrier-in-oracle oracle
qref_carrier_mutant comment-carrier-in-cla cla

# ─── D. workflow shape ──────────────────────────────────────────────────────────────────────────
SHAPE_OUT=$(shape_check "$WORKFLOW" 2>&1) && ok "workflow shape holds" || bad "workflow shape: $SHAPE_OUT"

shape_mutant() { # shape_mutant <name> <python re.sub args: pattern repl count>
  local name="$1" f="$WORK/wf-$1.yml"
  python3 -I - "$WORKFLOW" "$f" "$2" "$3" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
out = re.sub(sys.argv[3], sys.argv[4], src, count=1, flags=re.M)
open(sys.argv[2], "w", encoding="utf-8").write(out)
PYEOF
  if cmp -s "$WORKFLOW" "$f"; then bad "shape mutant $name did not change the workflow"; return; fi
  if shape_check "$f" >/dev/null 2>&1; then bad "shape mutant $name survived"; else ok "shape mutant $name rejected"; fi
}
# the sub arguments: PATTERN REPL (python re, MULTILINE)
shape_mutant drop-unlabeled 'types: \[opened, synchronize, reopened, labeled, unlabeled\]' 'types: [opened, synchronize, reopened, labeled]'
shape_mutant drop-merge-group '^  merge_group:' '  merge_group_disabled:'
shape_mutant drop-aggregate-member "^          member parked-hold 'pull_request,merge_group'.*\$" ''
shape_mutant job-level-if '^    timeout-minutes: 15$' "    timeout-minutes: 15\n    if: \${{ github.event_name == 'pull_request' }}"
shape_mutant drop-step-condition "^        if: \\\${{ !cancelled\\(\\) && \\(github.event_name == 'pull_request' \\|\\| github.event_name == 'merge_group'\\) }}\n        name: parked-hold" "        if: \${{ !cancelled() }}\n        name: parked-hold"
shape_mutant drop-permission '^      pull-requests: write.*$' '      pull-requests: read'
shape_mutant interpolated-run '^        run: bash scripts/ci-parked-hold.sh$' '        run: bash scripts/ci-parked-hold.sh ${{ github.event.pull_request.number }}'
shape_mutant drop-env-repo '^          REPO: \${{ github.repository }}\n          GH_TOKEN: \${{ github.token }}\n        run: bash scripts/ci-parked-hold.sh' '          GH_TOKEN: ${{ github.token }}\n        run: bash scripts/ci-parked-hold.sh'
# continue-on-error turns a red step's conclusion into success, so the PR would never be blocked
shape_mutant coe-parked-hold '^(      - id: parked-hold\n)' '\1        continue-on-error: true\n'
shape_mutant coe-selftest '^(      - id: parked-hold-selftest\n)' '\1        continue-on-error: true\n'
shape_mutant coe-expression '^(      - id: parked-hold\n)' '\1        continue-on-error: ${{ always() }}\n'
shape_mutant coe-job-level '^    timeout-minutes: 15$' '    timeout-minutes: 15\n    continue-on-error: true'
# a key placed AFTER a 6-space comment inside the step must still be seen (step_block does not stop at it)
shape_mutant coe-after-comment '^(        name: parked-hold \(fail while[^\n]*\n)' '\1      # a comment inside the step\n        continue-on-error: true\n'
shape_mutant coe-selftest-after-comment '^(        name: parked-hold selftest[^\n]*\n)' '\1      # a comment inside the step\n        continue-on-error: true\n'
# ...and when every OTHER required key sits BEFORE the comment, so only the hidden key distinguishes the verdict
shape_mutant coe-last-key-after-comment '^(        run: bash scripts/ci-parked-hold.sh\n)' '\1      # a comment inside the step\n        continue-on-error: true\n'
shape_mutant coe-selftest-last-key-after-comment '^(        run: bash scripts/ci-parked-hold.test.sh\n)' '\1      # a comment inside the step\n        continue-on-error: true\n'
# other spellings and neighbours of the same neutraliser: only the PARSED allow-list sees these
shape_mutant coe-double-quoted-key '^(      - id: parked-hold\n)' '\1        "continue-on-error": true\n'
shape_mutant coe-single-quoted-key '^(      - id: parked-hold-selftest\n)' "\\1        'continue-on-error': true\\n"
shape_mutant coe-list-item-first-key '^      - id: parked-hold-selftest\n' '      - continue-on-error: true\n        id: parked-hold-selftest\n'
shape_mutant shell-key-on-parked-hold '^(      - id: parked-hold\n)' '\1        shell: "echo {0}"\n'
shape_mutant shell-key-on-selftest '^(      - id: parked-hold-selftest\n)' '\1        shell: "echo {0}"\n'
shape_mutant coe-double-quoted-job-key '^    timeout-minutes: 15$' '    timeout-minutes: 15\n    "continue-on-error": true'
shape_mutant job-defaults-shell '^    timeout-minutes: 15$' '    timeout-minutes: 15\n    defaults:\n      run:\n        shell: "echo {0}"'

# ─── E. the workflow step's run: block, executed under bash -eo pipefail (stricter than the runner's bash -e) ─
RUN_BLOCK=$(extract_run "$WORKFLOW" parked-hold) && ok "extracted the parked-hold run: block" || bad "extract the parked-hold run: block"
SELF_BLOCK=$(extract_run "$WORKFLOW" parked-hold-selftest) && ok "extracted the parked-hold-selftest run: block" || bad "extract the parked-hold-selftest run: block"
if [ -n "${RUN_BLOCK:-}" ]; then
  reset_stub; set_resp last 0 "" "$(body 55 'parked')"
  OUT=$(cd "$ROOT" && env -i HOME="$WORK" PATH="$STUB:$ORIG_PATH" STUB_DIR="$STUB_DIR" PARKED_HOLD_RETRY_SLEEP=0 \
    GITHUB_WORKSPACE="$ROOT" EVENT_NAME=pull_request PR_NUMBER=55 MG_HEAD_REF= REPO=jikig-ai/soleur GH_TOKEN=stub-token-not-real \
    bash --noprofile --norc -eo pipefail -c "$RUN_BLOCK" 2>&1); RC=$?
  expect_fail "workflow run: block fails a parked PR under bash -eo pipefail"
  reset_stub; set_resp last 0 "" "$(body 55 'enhancement')"
  OUT=$(cd "$ROOT" && env -i HOME="$WORK" PATH="$STUB:$ORIG_PATH" STUB_DIR="$STUB_DIR" PARKED_HOLD_RETRY_SLEEP=0 \
    GITHUB_WORKSPACE="$ROOT" EVENT_NAME=pull_request PR_NUMBER=55 MG_HEAD_REF= REPO=jikig-ai/soleur GH_TOKEN=stub-token-not-real \
    bash --noprofile --norc -eo pipefail -c "$RUN_BLOCK" 2>&1); RC=$?
  expect_pass "workflow run: block passes an unparked PR under bash -eo pipefail"
  reset_stub; set_resp last 1 "gh: Server Error (HTTP 500)" ""
  OUT=$(cd "$ROOT" && env -i HOME="$WORK" PATH="$STUB:$ORIG_PATH" STUB_DIR="$STUB_DIR" PARKED_HOLD_RETRY_SLEEP=0 \
    GITHUB_WORKSPACE="$ROOT" EVENT_NAME=merge_group PR_NUMBER= MG_HEAD_REF="refs/heads/gh-readonly-queue/main/pr-56-$SHA40" REPO=jikig-ai/soleur GH_TOKEN=stub-token-not-real \
    bash --noprofile --norc -eo pipefail -c "$RUN_BLOCK" 2>&1); RC=$?
  expect_fail "workflow run: block fails closed on an unreadable merge_group label state"
fi
# the selftest step must not give the stub a credential: its run: block names no token
case "${SELF_BLOCK:-}" in *GH_TOKEN*) bad "selftest run: block must not reference GH_TOKEN" ;; *) ok "selftest run: block references no GH_TOKEN" ;; esac

# ─── F. the evaluator is wired to the dispositions recorded for it ───────────────────────────────
# anchored on the two comment lines that record the member's disposition, not the bare token (any comment satisfies that)
rc_pin() { grep -qE '^#.*, parked-hold and parked-hold-selftest \(added 2026-11-08,' "$1" && grep -qE '^#       - parked-hold / parked-hold-selftest: NOT content-scoped' "$1"; }
if rc_pin "$ROOT/scripts/required-checks.txt"; then ok "required-checks.txt records the member and its disposition"; else bad "required-checks.txt records the member and its disposition"; fi
for m in 's/parked-hold and parked-hold-selftest/parked-hold/' 's/NOT content-scoped/content-scoped/'; do
  sed -E "$m" "$ROOT/scripts/required-checks.txt" >"$WORK/rc-mut.txt"
  if cmp -s "$ROOT/scripts/required-checks.txt" "$WORK/rc-mut.txt"; then bad "required-checks mutant '$m' did not change the file"
  elif rc_pin "$WORK/rc-mut.txt"; then bad "required-checks mutant '$m' survived"; else ok "required-checks mutant '$m' rejected"; fi
done
for f in scripts/ci-parked-hold.sh scripts/ci-parked-hold.test.sh scripts/lib/umbrella-member.sh; do
  grep -qE "^/${f//./\\.}[[:space:]]+@deruelle" "$ROOT/.github/CODEOWNERS" && ok "CODEOWNERS row for $f" || bad "CODEOWNERS row for $f"
done

# ─── G. lint-umbrella-aggregate.sh rejects continue-on-error in a REQUIRED umbrella (class-wide rule (g)) ──────
LINTREPO="$WORK/lintrepo"
mkdir -p "$LINTREPO/scripts/lib" "$LINTREPO/.github/workflows"
cp "$ROOT"/.github/workflows/*.yml "$LINTREPO/.github/workflows/"
cp "$ROOT/scripts/lint-umbrella-aggregate.sh" "$LINTREPO/scripts/"
cp "$ROOT/scripts/lib/umbrella-member.sh" "$LINTREPO/scripts/lib/"
git -C "$LINTREPO" init -q 2>/dev/null
run_lint() { reset_stub; OUT=$(cd "$LINTREPO" && env -i HOME="$WORK" PATH="$ORIG_PATH" bash scripts/lint-umbrella-aggregate.sh 2>&1); RC=$?; }
run_lint; expect_pass "lint-umbrella-aggregate passes on the unmutated workflow copies"
lint_mutant() { # lint_mutant <name> <workflow> <umbrella job> <step id | JOB>: inject continue-on-error: true
  local name="$1" wf="$2" job="$3" at="$4"
  cp "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"
  python3 -I - "$LINTREPO/.github/workflows/$wf" "$job" "$at" <<'PYEOF'
import re, sys
path, job, at = sys.argv[1:4]
lines = open(path, encoding="utf-8").read().split("\n")
i = lines.index(f"  {job}:")
if at == "JOB":
    k = next(j for j in range(i, len(lines)) if lines[j].startswith("    runs-on:"))
    lines.insert(k, "    continue-on-error: true")
else:
    k = next(j for j in range(i, len(lines)) if lines[j] == f"      - id: {at}")
    lines.insert(k + 1, "        continue-on-error: true")
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
  if cmp -s "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"; then bad "lint mutant $name did not change $wf"; else
    run_lint
    if [ "$RC" -ne 0 ] && [[ "$OUT" == *"continue-on-error"* ]]; then ok "lint mutant $name rejected"; else bad "lint mutant $name survived (rc $RC)"; fi
  fi
  cp "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"
}
lint_mutant coe-on-parked-hold secret-scan.yml secret-guards parked-hold
lint_mutant coe-on-secret-guards-job secret-scan.yml secret-guards JOB
lint_mutant coe-on-guards-ruleset-step ci.yml guards-ruleset "$(sed -n '/^  guards-ruleset:/,/^  guards-advisory:/p' "$ROOT/.github/workflows/ci.yml" | grep -m1 -oE '^      - id: [A-Za-z0-9_-]+' | sed 's/^      - id: //')"
lint_mutant coe-on-quality-guards-step pr-quality-guards.yml quality-guards "$(sed -n '/^  quality-guards:/,/^  quality-advisory:/p' "$ROOT/.github/workflows/pr-quality-guards.yml" | grep -m1 -oE '^      - id: [A-Za-z0-9_-]+' | sed 's/^      - id: //')"
# Every other spelling or route by which a member is neutralised while rules (a)-(f) still hold. Each mutant is a
# python re.sub (MULTILINE, count=1) on one workflow copy; it must change the copy, the lint must exit non-zero, and
# its output must carry the finding that names THAT rule (a crash or an unrelated finding does not count as caught).
lint_resub() { # lint_resub <name> <workflow> <pattern> <replacement> <fixed substring the lint output must contain>
  local name="$1" wf="$2" pat="$3" rep="$4" want="$5"
  cp "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"
  python3 -I - "$LINTREPO/.github/workflows/$wf" "$pat" "$rep" <<'PYEOF'
import re, sys
path, pat, rep = sys.argv[1:4]
src = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(re.sub(pat, rep, src, count=1, flags=re.M))
PYEOF
  if cmp -s "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"; then bad "lint mutant $name did not change $wf (anchor drifted)"; else
    run_lint
    if [ "$RC" -ne 0 ] && [[ "$OUT" == *"$want"* ]]; then ok "lint mutant $name rejected"; else bad "lint mutant $name survived or was caught by another rule (rc $RC, wanted '$want')"; fi
  fi
  cp "$ROOT/.github/workflows/$wf" "$LINTREPO/.github/workflows/$wf"
}
SS=secret-scan.yml
# the key class: any spelling of continue-on-error, and the other one-key neutraliser (shell:)
lint_resub coe-double-quoted-key $SS '^(      - id: parked-hold\n)' '\1        "continue-on-error": true\n' 'disallowed step key `continue-on-error`'
lint_resub coe-single-quoted-key $SS '^(      - id: waiver-discipline\n)' "\\1        'continue-on-error': true\\n" 'disallowed step key `continue-on-error`'
lint_resub coe-list-item-first-key $SS '^      - id: parked-hold\n' '      - continue-on-error: true\n        id: parked-hold\n' 'disallowed step key `continue-on-error`'
lint_resub coe-flow-mapping-step $SS '^      - id: parked-hold-selftest\n        if: [^\n]*\n        name: [^\n]*\n        run: bash scripts/ci-parked-hold.test.sh\n' \
  "      - {id: parked-hold-selftest, if: \"\${{ !cancelled() }}\", name: x, run: \"bash scripts/ci-parked-hold.test.sh\", continue-on-error: true}\n" 'disallowed step key `continue-on-error`'
lint_resub coe-double-quoted-job-key $SS '^    timeout-minutes: 15$' '    timeout-minutes: 15\n    "continue-on-error": true' 'job key `continue-on-error`'
lint_resub shell-key-on-member $SS '^(      - id: waiver-discipline\n)' '\1        shell: "echo {0}"\n' 'disallowed step key `shell`'
lint_resub job-defaults-shell $SS '^    timeout-minutes: 15$' '    timeout-minutes: 15\n    defaults:\n      run:\n        shell: "echo {0}"' 'job key `defaults`'
lint_resub job-if-false-secret-guards $SS '^(  secret-guards:\n)' '\1    if: ${{ false }}\n' 'job key `if`'
lint_resub job-if-false-guards-ruleset ci.yml '^(  guards-ruleset:\n)' '\1    if: ${{ false }}\n' 'job key `if`'
lint_resub job-if-false-quality-guards pr-quality-guards.yml '^(  quality-guards:\n)' '\1    if: ${{ false }}\n' 'job key `if`'
lint_resub local-composite-action $SS '^(      - name: Checkout \(full history for diff scans\)\n        uses: )[^\n]*\n' '\1./.github/actions/x\n' '`uses` must be an owner/repo@<40-hex sha> action'
# quality-advisory is NOT exempt from the continue-on-error rule (it has no use of it); guards-advisory still is
lint_mutant coe-on-quality-advisory-step pr-quality-guards.yml quality-advisory "$(sed -n '/^  quality-advisory:/,$p' "$ROOT/.github/workflows/pr-quality-guards.yml" | grep -m1 -oE '^      - id: [A-Za-z0-9_-]+' | sed 's/^      - id: //')"
# the step `if:` grammar
lint_resub if-and-false $SS '^(      - id: waiver-discipline\n        if: [^\n]*?) \}\}\n' '\1 && false }}\n' 'term outside the allow-listed comparison atoms'
lint_resub if-trailing-comment-names-cancelled $SS '^(      - id: waiver-discipline\n)        if: [^\n]*\n' '\1        if: ${{ success() }} # !cancelled()\n' 'does not start with ${{ !cancelled() &&'
lint_resub if-top-level-or $SS '^(      - id: waiver-discipline\n)        if: [^\n]*\n' "\\1        if: \${{ !cancelled() && github.event_name == 'pull_request' || github.event_name == 'merge_group' }}\n" 'top-level `||`'
lint_resub aggregate-if-weakened $SS '^(      - id: aggregate\n        if: )\$\{\{ !cancelled\(\) \}\}' '\1${{ success() }}' 'aggregate `if:` must be exactly'
# the member call: arguments 4 and 5 pinned to the ids' own conclusions/outcomes, and the whole line
lint_resub member-constant-verdict $SS "'\\$\\{\\{ steps.waiver-discipline.conclusion \\}\\}' '\\$\\{\\{ steps.waiver-discipline.outcome \\}\\}'" "'success' 'success'" '4th argument is not exactly'
lint_resub member-foreign-step-verdict $SS "(member parked-hold 'pull_request,merge_group' 'parked-hold' '\\$\\{\\{ steps\\.)parked-hold(\\.conclusion)" '\1parked-hold-selftest\2' '4th argument is not exactly'
lint_resub member-constant-outcome $SS "'\\$\\{\\{ steps.waiver-discipline.outcome \\}\\}' \\|\\| failed=1" "'success' || failed=1" '5th argument is not exactly'
lint_resub member-or-true-between-links $SS "^(          member waiver-discipline [^\\n]*?) \\|\\| failed=1" '\1 || true || failed=1' 'malformed member call'
lint_resub member-trailing-comment $SS "^(          member waiver-discipline [^\\n]*? \\|\\| failed=1)" '\1 # ok' 'malformed member call'
# the aggregate shape: the tail is the last statement
lint_resub early-exit-before-tail $SS '^(          if \[ "\$failed" -ne 0 \]; then\n)' '          exit 0\n\1' 'statement outside the allowed sequence before the tail'
lint_resub statement-after-closing-echo $SS '^(          echo "secret-guards: all member guards green \(or out-of-scope\)")' '\1\n          exit 0' 'statement after the closing echo'
lint_resub tail-cut-before-exit $SS '^            exit 1\n          fi\n          echo "secret-guards: all' '          fi\n          echo "secret-guards: all' 'tail must be echo lines then `exit 1`'
run_lint; expect_pass "lint-umbrella-aggregate passes again once the mutated copies are restored"

# ─── anti-vacuity floor (Guard row 9): an emptied call list must not report ok ───────────────────
# The floor exits directly: it must not run THROUGH bad()/fails, which a neutered assertion machinery silences
# (scripts/guard-vacuity-floor.test.sh). MIN_ROWS is the actual row count (147) minus two; it stays on the line
# directly above the `if` so the meta-guard can bind it when it builds its neutered mutant.
MIN_ROWS=145
if [ "$rows" -lt "$MIN_ROWS" ]; then printf 'parked-hold selftest FAILED: anti-vacuity floor: only %d rows ran (minimum %d)\n' "$rows" "$MIN_ROWS" >&2; exit 1; fi

if [ "$fails" -ne 0 ]; then
  printf 'parked-hold selftest FAILED: %d of %d rows\n' "$fails" "$rows" >&2
  exit 1
fi
printf '%d rows\n' "$rows"
echo "parked-hold selftest ok"
