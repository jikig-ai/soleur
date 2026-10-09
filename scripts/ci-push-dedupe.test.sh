#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 for #9512 (ADR-276 S2): the `push-dedupe` proof in .github/workflows/ci.yml.
#
# WHAT THE GATE IS. On a push to `main`, job `push-dedupe` decides whether the eight heavy `ci.yml` jobs
# may be skipped because an identical-SHA `merge_group` run of the same workflow already passed. It is a
# COST optimisation that is allowed to fail in one direction only: every unknown runs the full battery.
# The deploy arm still sees a `success` push run because `push-dedupe` and the ungated cheap guards run.
#
# WHAT THIS SUITE PROVES. Not that the YAML mentions the right words, but that the proof step body,
# EXTRACTED from ci.yml and EXECUTED under the shell Actions uses (`bash --noprofile --norc -eo pipefail`)
# against a gh shim, yields the right verdict for each input class, and that the wrapper (job `if`,
# permissions, outputs, step flags, env), the eight gated conditions and the unchanged `test` aggregator
# are what the design says.
#
#   * a battery of rows over event, ref, attempt, SHA, variable shape, run listing shape, job listing
#     shape and API failure shape, each with an expected (elide, would_elide, reason);
#   * invariants applied to EVERY row: exit 0, every output line is a literal `elide=`/`would_elide=`
#     verdict, every stdout line is the one annotation, `mg_run` is `none` or digits, and no fixture
#     string (a poisoned title, branch or stderr) reaches an output or an annotation;
#   * a wrapper check on the parsed YAML (permissions, outputs, step flags, env, timeouts, no uses/secrets);
#   * a gated-set parity check derived from the parsed YAML in both directions, with the canonical
#     condition EVALUATED over an event x output x need-result truth table (the status-function semantics
#     included: without one a skipped need skips the job, which would drop a required context);
#   * the `test` aggregator pinned byte-for-byte (a digest) and EXECUTED over a triple with one leg
#     skipped, which must fail: the proof demands only the `test` job, which is sound only while that holds;
#   * mutation rows against mutated COPIES of the body and the workflow in mktemp dirs. A mutant is CAUGHT
#     only when the battery or the checker names the expected row; a crash proves nothing;
#   * harness rows: a stub proof that always elides must be refused, and a catch-all gh shim must not
#     let the must-be-false rows pass.
#
# THE gh SHIM validates the two exact endpoints (the runs listing with `event=merge_group`, a 40-hex
# `head_sha` and `per_page=100`; the jobs listing with `per_page=100&filter=latest` for a run id that
# exists), exits non-zero when GH_TOKEN is unset as real gh does, logs every call, and exits 64 on any
# other request (a STUB-MISS fails the row). It deliberately applies NO server-side filtering: the search
# parameters are advisory, so every row also proves the client-side re-check.
#
# PRE-MERGE LIMIT. The evaluator encodes the rule it tests. The authority for the `event != push` half is
# the live canary on the PR's own `pull_request` and `merge_group` runs; the `push` half first runs on `main`.
#
# This suite writes ONLY under mktemp rooted at ${TMPDIR:-/var/tmp}; never into the repo.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree);
# the registered runners default to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array, which can only be silenced by
# deleting evidence, not by moving a counter.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WF="$REPO_ROOT/.github/workflows/ci.yml"

SANDBOX=$(mktemp -d "$TMPDIR/ci-push-dedupe.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

for _dep in python3 jq bash timeout cmp md5sum; do
  command -v "$_dep" >/dev/null 2>&1 || { printf 'FAIL: %s is required\n' "$_dep" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to parse ci.yml (python3 -c "import yaml" failed)\n' >&2; exit 2; }

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
# pass() and fail() must each move their counters; a neutered helper makes every row below quiet.
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass
fail "instrument self-test (expected, not a real failure)" 2>/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() did not each move their counter by one (%s %s %s)\n' \
    "$passes" "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
passes=$_p0; fails=$_f0; FAILURES=()

# ── Pinned expectations (the design's reading of the wrapper) ────────────────
GATED_PINNED="e2e shard-totality-mutations test test-bun test-scripts test-scripts-heavy test-webplat web-platform-build"
# sha256 of the `test` aggregator job minus its `needs` and `if`, as json.dumps(sort_keys=True), measured
# on the unmodified tree before this stage (the aggregator body, env, timeout and runner must not move).
AGG_DIGEST="12a297030c34e7c1e8b5fa89833f0643857d61a61fef76e0dea016831976cc75"
# The jobs that are deliberately NOT gated (cheap guards that keep the push run's conclusion `success` when the heavy
# jobs are skipped). A NEW job must be classified: add it to GATED_PINNED (heavy) or here (cheap), never neither.
UNGATED_PINNED="adr-ordinals credential-path-guard critical-css-gate detect-changes encryption-posture grok-fidelity harness-discovery lint-bot-statuses lint-webplat lockfile-sync marketplace-manifest-guard plugin-root-propagation-gate rule-body-lint sandbox-canary-capture-gate service-role-allowlist-gate tc-document-sha-guard"
REASONS="not_push not_main rerun bad_sha proof_error no_mg_success no_test_job switch_off ok"
SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
REPO_SLUG="jikig-ai/soleur"
MG_ID=111
POISON='x
elide=true
::error::pwn'

mkdir -p "$SANDBOX/shim" "$SANDBOX/shim-timeout" "$SANDBOX/shim-catchall" "$SANDBOX/mut" "$SANDBOX/live"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# ── Helper: the YAML checker (one program, several modes) ────────────────────
cat > "$SANDBOX/chk.py" <<'PY'
import hashlib, json, os, re, sys, yaml
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
mode, path = sys.argv[1], sys.argv[2]
GATED = os.environ.get("GATED_PINNED", "").split()
UNGATED = os.environ.get("UNGATED_PINNED", "").split()
AGG = os.environ.get("AGG_DIGEST", "")
CANON = {"test": "${{ always() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}"}
CANON_DEFAULT = "${{ !cancelled() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}"
ENV_KEYS = {"GH_TOKEN", "GH_REPO", "SHA", "EVENT_NAME", "REF", "RUN_ATTEMPT", "SWITCH"}

def load():
    try:
        d = yaml.load(open(path).read(), Loader=LOADER)
        return d, (d.get("jobs") or {})
    except Exception as e:
        sys.stderr.write("chk.py crashed: %r\n" % (e,)); sys.exit(2)

def needs(j):
    n = (j or {}).get("needs", [])
    return [n] if isinstance(n, str) else list(n)

def ev(expr, event, elide, need, cancelled=False):
    e = str(expr).strip()
    if not (e.startswith("${{") and e.endswith("}}")):
        return None
    e = e[3:-2].strip()
    has_status = bool(re.search(r"\b(cancelled|always|success|failure)\(\)", e))
    e = e.replace("!cancelled()", "(not CANC)").replace("always()", "True").replace("success()", "(NEEDOK)")
    e = e.replace("github.event_name", "EV").replace("needs.push-dedupe.outputs.elide", "EL")
    e = e.replace("&&", " and ").replace("||", " or ")
    try:
        val = bool(eval(e, {"__builtins__": {}}, {"CANC": cancelled, "EV": event, "EL": elide, "NEEDOK": need == "success"}))
    except Exception:
        return None
    if not has_status:
        val = val and need == "success"
    return val

if mode == "extract":
    out = sys.argv[3]
    d, jobs = load()
    job = jobs.get("push-dedupe")
    steps = (job or {}).get("steps") or []
    proof = [s for s in steps if isinstance(s, dict) and s.get("id") == "proof" and "run" in s]
    if len(proof) != 1:
        sys.stderr.write("found %d proof steps in job push-dedupe (0 = job absent)\n" % len(proof)); sys.exit(3)
    open(out + "/body.sh", "w").write(proof[0]["run"])
    sys.exit(0)

if mode == "wrapper":
    d, jobs = load()
    tags = []
    job = jobs.get("push-dedupe")
    if job is None:
        print("W-JOB-MISSING"); sys.exit(0)
    if job.get("if") != "github.event_name == 'push'": tags.append("W-JOBIF")
    if job.get("timeout-minutes") != 3: tags.append("W-JOBTIMEOUT")
    if job.get("permissions") != {"actions": "read"}: tags.append("W-PERM")
    if job.get("outputs") != {"elide": "${{ steps.proof.outputs.elide }}"}: tags.append("W-OUTPUTS")
    if job.get("continue-on-error") is not True: tags.append("W-JOBCOE")
    if job.get("runs-on") != "ubuntu-latest": tags.append("W-RUNSON")
    if needs(job): tags.append("W-JOBNEEDS")
    steps = job.get("steps") or []
    if [s.get("id") for s in steps] != ["proof", "would-elide"]: tags.append("W-STEPS")
    for s in steps:
        if "uses" in s: tags.append("W-USES")
    txt = json.dumps(job)
    if "secrets." in txt: tags.append("W-SECRETS")
    if "checkout" in txt: tags.append("W-CHECKOUT")
    proof = next((s for s in steps if s.get("id") == "proof"), {})
    if proof.get("continue-on-error") is not True: tags.append("W-COE")
    if proof.get("timeout-minutes") != 2: tags.append("W-STEPTIMEOUT")
    if proof.get("shell") != "bash": tags.append("W-SHELL")
    if set((proof.get("env") or {}).keys()) != ENV_KEYS: tags.append("W-ENVKEYS")
    env = proof.get("env") or {}
    exp = {"GH_TOKEN": "${{ github.token }}", "GH_REPO": "${{ github.repository }}", "SHA": "${{ github.sha }}",
           "EVENT_NAME": "${{ github.event_name }}", "REF": "${{ github.ref }}", "RUN_ATTEMPT": "${{ github.run_attempt }}",
           "SWITCH": "${{ vars.CI_PUSH_DEDUPE }}"}
    if any(env.get(k) != v for k, v in exp.items()): tags.append("W-ENVVALUES")
    for s in steps:
        if s is not proof and "GH_TOKEN" in (s.get("env") or {}): tags.append("W-TOKEN-LEAK")
    body = proof.get("run", "")
    if re.search(r"set\s+-[a-zA-Z]*x|xtrace", body): tags.append("W-XTRACE")
    if "set +x" not in body: tags.append("W-NOXTRACEOFF")
    if "${{" in body: tags.append("W-INTERP")
    gh_calls = len(re.findall(r"\bgh api\b", body))
    t_calls = len(re.findall(r"\btimeout 20 gh api\b", body))
    if gh_calls != 2 or t_calls != 2: tags.append("W-GHTIMEOUT")
    i_def = body.find('emit "elide=false"'); i_gh = body.find("gh api")
    if i_def < 0 or i_gh < 0 or i_def > i_gh: tags.append("W-DEFAULT-ORDER")
    i_true = body.find('emit "elide=true"'); i_chk = body.find("reason=no_test_job")
    if body.count('emit "elide=true"') != 1 or i_true < 0 or i_chk < 0 or i_true < i_chk: tags.append("W-TRUE-ORDER")
    would = steps[1] if len(steps) > 1 else {}
    if would.get("if") != "steps.proof.outputs.would_elide == 'true'": tags.append("W-WOULDIF")
    # the release workflow's CI budget awk reads `timeout-minutes: N` alone on a line
    text = open(path).read().split("\n")
    try:
        i0 = text.index("  push-dedupe:")
    except ValueError:
        tags.append("W-JOB-TEXT"); print(" ".join(tags)); sys.exit(0)
    blk = []
    for ln in text[i0 + 1:]:
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", ln): break
        blk.append(ln)
    if sum(1 for ln in blk if ln == "    timeout-minutes: 3") != 1: tags.append("W-TIMEOUT-LINE")
    print(" ".join(tags)); sys.exit(0)

if mode == "gated":
    d, jobs = load()
    tags = []
    got = sorted(n for n, j in jobs.items() if "needs.push-dedupe.outputs.elide" in str((j or {}).get("if", "")))
    if got != sorted(GATED): tags.append("G-SET:" + ",".join(got))
    for n in GATED:
        j = jobs.get(n)
        if j is None: tags.append("G-MISSING:" + n); continue
        if "push-dedupe" not in needs(j): tags.append("G-NEEDS:" + n)
        if j.get("if") != CANON.get(n, CANON_DEFAULT): tags.append("G-COND:" + n)
        if j.get("continue-on-error"): tags.append("G-COE:" + n)
    for n, j in jobs.items():
        if n not in GATED and n != "push-dedupe" and "push-dedupe" in needs(j): tags.append("G-EXTRANEED:" + n)
        if n not in GATED and n != "push-dedupe" and n not in UNGATED: tags.append("G-UNCLASSIFIED:" + n)
        if n not in GATED and set(needs(j)) & set(GATED): tags.append("G-DEPENDENT:" + n)
        if n != "push-dedupe" and "push-dedupe" in json.dumps((j or {}).get("outputs", {})): tags.append("G-REEXPORT:" + n)
    for n in UNGATED:
        if n not in jobs: tags.append("G-GONE:" + n)
    print(" ".join(tags)); sys.exit(0)

if mode == "truth":
    d, jobs = load()
    tags = []
    for n in GATED:
        j = jobs.get(n) or {}
        for event in ("push", "pull_request", "merge_group", "workflow_dispatch"):
            for elide in ("", "false", "true"):
                needs_ = ("success", "failure") if event == "push" else ("skipped",)
                for need in needs_:
                    got = ev(j.get("if"), event, elide, need)
                    want = not (event == "push" and elide == "true")
                    if got is None: tags.append("TT-ERR:%s" % n)
                    elif got != want: tags.append("TT:%s:%s:%s:%s" % (n, event, elide or "empty", need))
        if ev(j.get("if"), "push", "false", "success", cancelled=True) is not False and "always()" not in str(j.get("if")):
            tags.append("TT-CANCEL:" + n)
    print(" ".join(sorted(set(tags)))); sys.exit(0)

if mode == "agg":
    d, jobs = load()
    t = jobs.get("test")
    if t is None: print("A-MISSING"); sys.exit(0)
    rest = {k: v for k, v in t.items() if k not in ("needs", "if")}
    got = hashlib.sha256(json.dumps(rest, sort_keys=True).encode()).hexdigest()
    print("" if got == AGG else "A-DIGEST:" + got); sys.exit(0)

if mode == "aggbody":
    out = sys.argv[3]
    d, jobs = load()
    t = jobs["test"]; st = t["steps"][0]
    open(out + "/agg.sh", "w").write(st["run"])
    open(out + "/agg.env", "w").write("".join("%s\n" % k for k in (st.get("env") or {})))
    sys.exit(0)
sys.stderr.write("unknown mode\n"); sys.exit(2)
PY

chk() { GATED_PINNED="$GATED_PINNED" UNGATED_PINNED="$UNGATED_PINNED" AGG_DIGEST="$AGG_DIGEST" python3 "$SANDBOX/chk.py" "$@"; }

# ── Helper: the gh shim ──────────────────────────────────────────────────────
cat > "$SANDBOX/shim/gh" <<'SH'
#!/usr/bin/env bash
# FIX: fixture dir. Files: runs.json, jobs-<id>.json, mode (ok|fail_runs|fail_jobs|bad_runs|bad_jobs|nonarray).
printf '%s\n' "$*" >> "$FIX/calls.log"
[ "${1:-}" = api ] || { echo "STUB-MISS: not api: $*" >> "$FIX/calls.log"; exit 64; }
[ -n "${GH_TOKEN:-}" ] || { echo "gh: GH_TOKEN required" >&2; exit 4; }
ep="${2:-}"
mode=$(cat "$FIX/mode" 2>/dev/null || echo ok)
runs_re="^repos/${GH_REPO}/actions/workflows/ci\\.yml/runs\\?event=merge_group&head_sha=[0-9a-f]{40}&per_page=100\$"
jobs_re="^repos/${GH_REPO}/actions/runs/([0-9]+)/jobs\\?per_page=100&filter=latest\$"
if [[ "$ep" =~ $runs_re ]]; then
  case "$mode" in
    fail_runs) printf 'boom\nelide=true\n::error::pwn\n' >&2; exit 1 ;;
    bad_runs) printf '{not json'; exit 0 ;;
    nonarray) printf '{"message":"rate limited"}'; exit 0 ;;
  esac
  if [ "${CATCHALL:-}" = 1 ]; then cat "$CATCHALL_RUNS"; exit 0; fi
  cat "$FIX/runs.json"; exit 0
elif [[ "$ep" =~ $jobs_re ]]; then
  id="${BASH_REMATCH[1]}"
  case "$mode" in
    fail_jobs) printf 'boom\nelide=true\n::error::pwn\n' >&2; exit 1 ;;
    bad_jobs) printf '{not json'; exit 0 ;;
  esac
  if [ "${CATCHALL:-}" = 1 ]; then cat "$CATCHALL_JOBS"; exit 0; fi
  [ -f "$FIX/jobs-$id.json" ] || { echo "STUB-MISS: no fixture for run $id" >> "$FIX/calls.log"; exit 64; }
  cat "$FIX/jobs-$id.json"; exit 0
fi
echo "STUB-MISS: unexpected endpoint: $ep" >> "$FIX/calls.log"
exit 64
SH
chmod +x "$SANDBOX/shim/gh"
# a `timeout` that always reports a timeout (exit 124), to prove a hung read becomes a full run
cat > "$SANDBOX/shim-timeout/timeout" <<'SH'
#!/usr/bin/env bash
exit 124
SH
chmod +x "$SANDBOX/shim-timeout/timeout"

# ── Fixture builders ─────────────────────────────────────────────────────────
# fx_run <id> <event> <status> <conclusion|null> <sha> <branch> <repo> <path> [title]
FXD=""
fx_new() { FXD="$1"; assert_fixture_dir "$FXD"; rm -rf "$FXD"; mkdir -p "$FXD"; : > "$FXD/runs.ndjson"; printf ok > "$FXD/mode"; : > "$FXD/calls.log"; }
fx_run() {
  assert_fixture_dir "$FXD"
  jq -nc --argjson id "$1" --arg ev "$2" --arg st "$3" --arg c "$4" --arg sha "$5" --arg br "$6" --arg repo "$7" --arg path "$8" --arg title "${9:-t}" \
    '{id:$id,event:$ev,status:$st,conclusion:(if $c=="null" then null else $c end),head_sha:$sha,head_branch:$br,path:$path,display_title:$title,head_repository:{full_name:$repo}}' >> "$FXD/runs.ndjson"
}
fx_flush() { assert_fixture_dir "$FXD"; jq -s '{workflow_runs: .}' "$FXD/runs.ndjson" > "$FXD/runs.json"; }
# fx_jobs <runid> name:conclusion ...
fx_jobs() {
  assert_fixture_dir "$FXD"
  local id="$1"; shift
  if [ "$#" -eq 0 ]; then printf '{"jobs":[]}\n' > "$FXD/jobs-$id.json"; return; fi
  local args=() n c
  for pair in "$@"; do n="${pair%%:*}"; c="${pair#*:}"; args+=("$n" "$c"); done
  printf '%s\n' "${args[@]}" | jq -Rn '[inputs] as $a | {jobs: [range(0; ($a|length); 2) | {name: $a[.], conclusion: (if $a[.+1]=="null" then null else $a[.+1] end)}]}' > "$FXD/jobs-$id.json"
}
GOOD_JOBS=(test-webplat:success test-bun:success test:success e2e:success)
QB="gh-readonly-queue/main/pr-1-$SHA_A"
fx_canonical() {
  fx_new "$1"
  fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"
  fx_flush
}

# ── Row runner: executes a body under the Actions shell against the shim ─────
# Globals per row: ROW_ENV (assoc of overrides), RB_SHIMPATH, RB_CATCHALL.
declare -A E
set_env_defaults() {
  E=([GH_TOKEN]=tok [GH_REPO]="$REPO_SLUG" [SHA]="$SHA_A" [EVENT_NAME]=push [REF]=refs/heads/main [RUN_ATTEMPT]=1 [SWITCH]=on)
}
BAT_N=0
BAT_LINES=""
ROWS_SEEN_REASONS=""
# row <id> <expect_elide> <expect_would> <expect_reason>   (fixture already built in $FXD, env in E)
row() {
  local id="$1" xe="$2" xw="$3" xr="$4" out so rc why=""
  BAT_N=$((BAT_N + 1))
  assert_fixture_dir "$FXD"
  out="$FXD/gh_output"; so="$FXD/stdout"; : > "$out"
  local pathv jqdir
  jqdir=$(dirname "$(command -v jq)")
  pathv="${RB_SHIMPATH:-/nonexistent}:$SANDBOX/shim:$jqdir:/usr/bin:/bin"
  ( cd "$FXD" && env -i PATH="$pathv" HOME="$FXD" FIX="$FXD" GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="$FXD/summary" \
      GH_TOKEN="${E[GH_TOKEN]}" GH_REPO="${E[GH_REPO]}" SHA="${E[SHA]}" EVENT_NAME="${E[EVENT_NAME]}" REF="${E[REF]}" \
      RUN_ATTEMPT="${E[RUN_ATTEMPT]}" SWITCH="${E[SWITCH]}" CATCHALL="${RB_CATCHALL:-}" CATCHALL_RUNS="${RB_CA_RUNS:-}" CATCHALL_JOBS="${RB_CA_JOBS:-}" \
      bash --noprofile --norc -eo pipefail "$BODY" > "$so" 2> "$FXD/stderr" )
  rc=$?
  [ "$rc" -eq 0 ] || why="$why rc=$rc"
  # every output line is a literal verdict
  local bad_lines
  bad_lines=$(grep -cvE '^(elide|would_elide)=(true|false)$' "$out" || true)
  [ "$bad_lines" = 0 ] || why="$why output-line-not-literal"
  # last-wins values
  local ge gw
  ge=$(grep -E '^elide=' "$out" | tail -n 1 | cut -d= -f2)
  gw=$(grep -E '^would_elide=' "$out" | tail -n 1 | cut -d= -f2)
  [ "$ge" = "$xe" ] || why="$why elide=$ge(want $xe)"
  [ "$gw" = "$xw" ] || why="$why would=$gw(want $xw)"
  if [ "$ge" = true ]; then
    [ "$(grep -E '^[a-z_]+=' "$out" | tail -n 1)" = "elide=true" ] || why="$why true-not-last"
  fi
  # stdout: only the one annotation, never a fixture string, mg_run numeric or none
  local nlines notices reason mg
  nlines=$(grep -c '' "$so" || true)
  notices=$(grep -cE '^::(notice|warning) title=ci-push-dedupe::sha=[0-9a-f]{40}|^::(notice|warning) title=ci-push-dedupe::sha=invalid' "$so" || true)
  [ "$nlines" = 1 ] && [ "$notices" = 1 ] || why="$why stdout-shape(lines=$nlines,annot=$notices)"
  if grep -qF 'pwn' "$so" "$out" "$FXD/summary" "$FXD/stderr" 2>/dev/null; then why="$why fixture-string-leaked"; fi
  reason=$(sed -n 's/.* reason=\([a-z_]*\) mg_run=.*/\1/p' "$so" | head -n 1)
  mg=$(sed -n 's/.* mg_run=\(.*\)$/\1/p' "$so" | head -n 1)
  [ "$reason" = "$xr" ] || why="$why reason=$reason(want $xr)"
  [[ "$mg" =~ ^(none|[0-9]+)$ ]] || why="$why mg_run=$mg"
  if grep -q 'STUB-MISS' "$FXD/calls.log" 2>/dev/null; then why="$why stub-miss"; fi
  ROWS_SEEN_REASONS="$ROWS_SEEN_REASONS $reason"
  if [ -z "$why" ]; then BAT_LINES="$BAT_LINES"$'\n'"ROW $id ok"; else BAT_LINES="$BAT_LINES"$'\n'"ROW $id bad:$why"; fi
}

# battery <body> [shim-path] : fills BAT_LINES, BAT_N, ROWS_SEEN_REASONS
battery() {
  BODY="$1"; RB_SHIMPATH=""; RB_CATCHALL="${2:-}"
  BAT_N=0; BAT_LINES=""; ROWS_SEEN_REASONS=""
  local d="$SANDBOX/bat" v ev
  # R01 canonical, variable on
  fx_canonical "$d"; set_env_defaults; row R01-canonical true true ok
  # R02 variable unset / empty
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=""; row R02-switch-unset false true switch_off
  # R03 variable shapes that must NOT enable elision
  for v in ON " on " On true 1 yes "on " " on" onn; do
    fx_canonical "$d"; set_env_defaults; E[SWITCH]="$v"; row "R03-switch-[$v]" false true switch_off
  done
  # R04 other events are never elided and never proven
  for ev in pull_request merge_group workflow_dispatch schedule; do
    fx_canonical "$d"; set_env_defaults; E[EVENT_NAME]="$ev"; row "R04-event-$ev" false false not_push
  done
  # R05 other refs
  for v in refs/heads/foo refs/pull/1/merge refs/heads/main2 ""; do
    fx_canonical "$d"; set_env_defaults; E[REF]="$v"; row "R05-ref-[$v]" false false not_main
  done
  # R06 re-runs
  for v in 2 3 0 ""; do
    fx_canonical "$d"; set_env_defaults; E[RUN_ATTEMPT]="$v"; row "R06-attempt-[$v]" false false rerun
  done
  # R07 malformed SHA
  for v in abc "${SHA_A^^}" "${SHA_A}a" "${SHA_A:0:39}" "" "${SHA_A:0:39}g" $'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nelide=true'; do
    fx_canonical "$d"; set_env_defaults; E[SHA]="$v"; row "R07-sha-[${v:0:12}]" false false bad_sha
  done
  # R08 merge_group run state other than completed+success
  for v in "in_progress:null" "queued:null" "completed:cancelled" "completed:failure" "completed:skipped" "completed:timed_out" "completed:neutral" "completed:null" "in_progress:success" "queued:success"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group "${v%%:*}" "${v#*:}" "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush
    set_env_defaults; row "R08-state-$v" false false no_mg_success
  done
  # R09 a lagging search returns a run for another SHA
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_B" "gh-readonly-queue/main/pr-2-$SHA_B" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R09-other-sha false false no_mg_success
  # R10 branch prefix
  for v in main feature/x gh-readonly-queue/other/pr-1 "x/gh-readonly-queue/main/pr-1" gh-readonly-queue/main; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$v" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R10-branch-[$v]" false false no_mg_success
  done
  # R11 the `test` job: missing, skipped, failed, cancelled, prefix collision only
  for v in "test-scripts (1/8):success" "test:skipped" "test:failure" "test:cancelled" "test:null" "tests:success" "Test:success" "test-scripts:success"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" test-webplat:success e2e:success "$v"; fx_flush; set_env_defaults; row "R11-test-job-[$v]" false false no_test_job
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID"; fx_flush; set_env_defaults; row R11-empty-job-list false false no_test_job
  # R12 API failure shapes: every one is a full run with reason proof_error
  for v in fail_runs bad_runs nonarray fail_jobs bad_jobs; do
    fx_canonical "$d"; printf '%s' "$v" > "$d/mode"; set_env_defaults; row "R12-api-$v" false false proof_error
  done
  fx_canonical "$d"; set_env_defaults; RB_SHIMPATH="$SANDBOX/shim-timeout"; row R12-api-timeout false false proof_error; RB_SHIMPATH=""
  fx_canonical "$d"; set_env_defaults; E[GH_TOKEN]=""; row R12-no-token false false proof_error
  # R13 binding: a run that is not a merge_group run of THIS repository's ci.yml cannot vouch, even on a queue-named branch
  for v in pull_request workflow_dispatch push schedule; do
    fx_new "$d"; fx_run "$MG_ID" "$v" completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R13-event-$v" false false no_mg_success
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "attacker/soleur" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R13-fork-repo false false no_mg_success
  for v in .github/workflows/other.yml .github/workflows/x-ci.yml ci.yml ".github/workflows/ci.yml@refs/heads/main"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" "$v"
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R13-path-[$v]" false false no_mg_success
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" ""
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R13-empty-path false false no_mg_success
  # R14 injection: a poisoned title/branch on a MATCHING run (poisoned stderr on a failing read is the R12 rows, via row()'s leak check)
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "gh-readonly-queue/main/$POISON" "$REPO_SLUG" .github/workflows/ci.yml "$POISON"
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R14-poisoned-match true true ok
  # R15 permitted shapes that are NOT the canonical fixture
  fx_new "$d"; fx_run 100 merge_group completed failure "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs 100 test:failure; fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush
  # reverse listing order: success first, older failure second
  jq -s '{workflow_runs: (. | reverse)}' "$d/runs.ndjson" > "$d/runs.json"
  set_env_defaults; row R15-two-runs-reverse-order true true ok
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" lint-bot-statuses:skipped e2e:success test:success test-webplat:success advisory:skipped; fx_flush
  set_env_defaults; row R15-job-order-extra-advisory true true ok
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=on; row R15-switch-on-canonical-again true true ok
  # R16 the proof is evaluated for the dark phase: variable unset, canonical, would be elided
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=""; row R16-dark-would-elide false true switch_off
  # R17 a run id that is not digits never reaches a URL (it would add path segments to the jobs read)
  fx_new "$d"; jq -nc --arg sha "$SHA_A" --arg br "$QB" --arg repo "$REPO_SLUG" '{id:"111/../../../../repos/x",event:"merge_group",status:"completed",conclusion:"success",head_sha:$sha,head_branch:$br,path:".github/workflows/ci.yml",head_repository:{full_name:$repo}}' >> "$d/runs.ndjson"
  fx_flush; set_env_defaults; row R17-nonnumeric-run-id false false proof_error
}

# ── Extract the live body ────────────────────────────────────────────────────
LIVE="$SANDBOX/live"
chk extract "$WF" "$LIVE" 2> "$SANDBOX/extract.err"; EXTRACT_RC=$?
if [ "$EXTRACT_RC" -ne 0 ]; then
  fail "EXTRACT: the push-dedupe proof step could not be extracted from ci.yml (rc=$EXTRACT_RC: $(head -c 200 "$SANDBOX/extract.err"))"
  # Everything below needs a body; report and stop so the failure is the extraction, not a cascade.
  printf 'ci-push-dedupe: %d passed, %d failed\n' "$passes" "$fails"
  exit 1
fi
cp "$LIVE/body.sh" "$SANDBOX/pristine-body.sh"
bash -n "$LIVE/body.sh" 2>/dev/null && pass || fail "SYNTAX: the extracted body does not parse under bash -n"

# ── Control run of the battery on the live body ──────────────────────────────
battery "$LIVE/body.sh"
CTRL_N=$BAT_N; CTRL_LINES="$BAT_LINES"; CTRL_REASONS="$ROWS_SEEN_REASONS"
_ok=0; _bad=0
while IFS= read -r ln; do
  case "$ln" in
    "ROW "*" ok") _ok=$((_ok + 1)); pass ;;
    "ROW "*) _bad=$((_bad + 1)); fail "BATTERY ${ln#ROW }" ;;
  esac
done <<<"$CTRL_LINES"
# independent producer count: the rows executed (counter in row()) must equal the verdict lines read back
if [ "$CTRL_N" -eq $((_ok + _bad)) ] && [ "$CTRL_N" -ge 78 ]; then pass
else fail "BATTERY COUNT: row() ran $CTRL_N rows but $((_ok + _bad)) verdict lines were read (floor 78)"; fi
# every reason code in the enum is reached at least once, taken from what the body PRINTED
_missing=""
for r in $REASONS; do
  case " $CTRL_REASONS " in *" $r "*) ;; *) _missing="$_missing $r" ;; esac
done
if [ -z "$_missing" ]; then pass; else fail "REASONS: never reached:$_missing"; fi

# ── Wrapper, gated set, truth table, aggregator ──────────────────────────────
# A checker that CRASHES prints nothing to stdout; its exit status is part of its verdict.
live_check() { # <label> <mode>
  local out rc
  out=$(chk "$2" "$WF" 2>"$SANDBOX/chk.err"); rc=$?
  if [ "$rc" -ne 0 ]; then fail "$1: the checker crashed (rc=$rc: $(head -c 160 "$SANDBOX/chk.err"))"
  elif [ -n "$out" ]; then fail "$1 tags: $out"
  else pass; fi
}
live_check WRAPPER wrapper
live_check "GATED" gated
live_check "TRUTH TABLE" truth
live_check AGGREGATOR agg
# the canonical condition is restated by two pre-existing suites' carve-outs; each copy must still equal ci.yml's
for pair in "plugins/soleur/test/ci-e2e-skip-anchors.test.sh|!cancelled()" "plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh|always()"; do
  f="${pair%%|*}"; fn="${pair#*|}"
  lit="$fn && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true')"
  if [ "$(grep -cF -- "$lit" "$REPO_ROOT/$f")" -ge 1 ]; then pass; else fail "PARITY: $f no longer carries the canonical condition ($lit)"; fi
done

# the proof demands only the `test` job: that is sound only while the aggregator concludes red on a
# skipped leg. Execute the extracted aggregator over a merge_group triple with one gated leg skipped.
chk aggbody "$WF" "$SANDBOX/live" 2>/dev/null
agg_run() { # <skipped-leg-var|none>
  local envs=() k
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$k" in EVENT_NAME) envs+=("EVENT_NAME=merge_group") ;; *) envs+=("$k=success") ;; esac
  done < "$SANDBOX/live/agg.env"
  [ "$1" = none ] || envs+=("$1=skipped")
  env -i PATH=/usr/bin:/bin "${envs[@]}" bash --noprofile --norc -eo pipefail "$SANDBOX/live/agg.sh" >/dev/null 2>&1
}
if [ -s "$SANDBOX/live/agg.sh" ]; then
  agg_run none; rc0=$?
  agg_run SCRIPTS_RESULT; rc1=$?
  agg_run BUN_RESULT; rc2=$?
  agg_run BUILD_RESULT; rc3=$?
  if [ "$rc0" -eq 0 ] && [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$rc3" -ne 0 ]; then pass
  else fail "COUPLING: the aggregator must pass on an all-success triple (rc=$rc0) and fail on a skipped leg (scripts rc=$rc1, bun rc=$rc2, build rc=$rc3)"; fi
else
  fail "COUPLING: the test aggregator body could not be extracted"
fi

# ── Mutation rows ────────────────────────────────────────────────────────────
MUT_RUN=0; MUT_CAUGHT=0
cat > "$SANDBOX/mut.py" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
# mutate_body <name> <old> <new> <expected-row-prefix>: the battery on the mutant must flag a row with the prefix
mutate_body() {
  local name="$1" old="$2" new="$3" want="$4" f got
  f="$SANDBOX/mut/$name.sh"
  MUT_RUN=$((MUT_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$SANDBOX/pristine-body.sh" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "MUTANT $name: mutation did NOT land ($(head -c 120 "$SANDBOX/mut.err"))"; return
  fi
  if cmp -s "$f" "$SANDBOX/pristine-body.sh"; then fail "MUTANT $name: mutant is byte-identical to the pristine body"; return; fi
  battery "$f"
  if [ "$want" = NONE ]; then # known-negative control: a harmless edit must leave EVERY row green
    got=$(grep -E "^ROW .* bad:" <<<"$BAT_LINES" | head -n 1)
    if [ -z "$got" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "CONTROL $name: a harmless edit turned a row red ($got)"; fi
    return
  fi
  got=$(grep -E "^ROW $want.* bad:" <<<"$BAT_LINES" | head -n 1)
  if [ -n "$got" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT $name: no row with prefix $want went red"; fi
}
mutate_body c-harmless-noop 'note=invalid' 'note=invalid; :' NONE
# the verdict logic itself must be able to say "not caught": a mutant that changes nothing observable is refused above
mutate_body m-switch-case '[ "$SWITCH" = on ]' '[ "${SWITCH,,}" = on ]' R03
mutate_body m-switch-always '[ "$SWITCH" = on ]' 'true' R03
mutate_body m-no-push-check '[ "$EVENT_NAME" = push ] || finish' 'true' R04
mutate_body m-no-main-check '[ "$REF" = refs/heads/main ] || finish' 'true' R05
mutate_body m-no-attempt-check '[ "$RUN_ATTEMPT" = 1 ] || finish' 'true' R06
mutate_body m-no-sha-check '[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || finish' 'true' R07
mutate_body m-conclusion '.conclusion == "success" and .head_sha' '.head_sha' R08
mutate_body m-status '.status == "completed" and .conclusion' '.conclusion' R08
mutate_body m-no-sha-recheck ' and .head_sha == $sha' '' R09
mutate_body m-no-branch-prefix ' and ((.head_branch // "") | startswith("gh-readonly-queue/main/"))' '' R10
mutate_body m-test-prefix '.name == "test" and' '(.name | startswith("test")) and' R11
mutate_body m-test-conclusion 'select(.name == "test" and .conclusion == "success")' 'select(.name == "test")' R11
mutate_body m-no-event-check '.event == "merge_group" and ' '' R13
mutate_body m-no-repo-check ' and .head_repository.full_name == $repo' '' R13
mutate_body m-no-path-check ' and .path == ".github/workflows/ci.yml"' '' R13
mutate_body m-path-endswith '.path == ".github/workflows/ci.yml"' '(.path | endswith("ci.yml"))' R13
mutate_body m-runs-stderr 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' 'head_sha=${SHA}&per_page=100") || finish' R12
mutate_body m-jobs-stderr 'filter=latest" 2>/dev/null) || finish' 'filter=latest") || finish' R12
# fail-open on a failed read (the read is replaced by a vouching answer): must go red on the failure rows
_open_runs=$(cat <<'EOS'
head_sha=${SHA}&per_page=100" 2>/dev/null) || runs=$(printf '{"workflow_runs":[{"event":"merge_group","status":"completed","conclusion":"success","head_sha":"%s","path":".github/workflows/ci.yml","head_repository":{"full_name":"%s"},"head_branch":"gh-readonly-queue/main/x","id":111}]}' "$SHA" "$GH_REPO")
EOS
)
mutate_body m-runs-failure-fails-open 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' "$_open_runs" R12
mutate_body m-jobs-failure-fails-open 'filter=latest" 2>/dev/null) || finish' 'filter=latest" 2>/dev/null) || jobs='"'"'{"jobs":[{"name":"test","conclusion":"success"}]}'"'"'' R12
mutate_body m-echo-branch "printf '::notice title=ci-push-dedupe::sha=%s" "printf '%s' \"\$runs\"; printf '::notice title=ci-push-dedupe::sha=%s" R14
# REORDER: write elide=true before the jobs read, with a jobs read that fails (R12-api-fail_jobs must go red)
mutate_body m-reorder-true 'mg="$id"' 'mg="$id"; emit "elide=true"' R12
mutate_body m-default-after-gh 'emit "elide=false"' ':' R12
mutate_body m-mgid-unchecked '[[ "$id" =~ ^[0-9]+$ ]] || finish' 'true' R17

# EQUIVALENT mutants, recorded rather than hidden: each removes a guard that a LATER guard repeats, so no verdict
# changes (a failed runs read leaves the listing empty, which the array check, then the id extraction, both refuse).
# Reading 2 of "a surviving mutant" in the work skill: equivalent, proven by the battery staying green on it.
EQUIV_RUN=0; EQUIV_OK=0
mutate_body_equiv() {
  local name="$1" old="$2" new="$3" f
  f="$SANDBOX/mut/$name.sh"; EQUIV_RUN=$((EQUIV_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$SANDBOX/pristine-body.sh" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "EQUIVALENT $name: mutation did NOT land"; return
  fi
  battery "$f"
  if [ -z "$(grep -E '^ROW .* bad:' <<<"$BAT_LINES")" ]; then EQUIV_OK=$((EQUIV_OK + 1)); pass
  else fail "EQUIVALENT $name: expected no row to go red, but one did (not equivalent: add a killing row)"; fi
}
mutate_body_equiv e-runs-failure-ignored 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' 'head_sha=${SHA}&per_page=100" 2>/dev/null) || true'
mutate_body_equiv e-nonarray-check-dropped "jq -e '.workflow_runs | type == \"array\"' >/dev/null 2>&1 || finish" 'cat >/dev/null'

# harness: a stub proof that always elides must be refused by the battery
printf '%s\n' 'printf "elide=true\nwould_elide=true\n" >> "$GITHUB_OUTPUT"; printf "::notice title=ci-push-dedupe::sha=invalid would_elide=true elide=true reason=ok mg_run=none\n"; exit 0' > "$SANDBOX/mut/stub-always.sh"
MUT_RUN=$((MUT_RUN + 1))
battery "$SANDBOX/mut/stub-always.sh"
_n_bad=$(grep -cE '^ROW .* bad:' <<<"$BAT_LINES" || true)
if [ "$_n_bad" -ge 50 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "HARNESS H1: an always-elide stub went red on only $_n_bad rows (floor 50)"; fi
# harness: a catch-all gh shim (canonical fixture for every call) must not let the must-be-false rows pass
fx_canonical "$SANDBOX/ca"; RB_CA_RUNS="$SANDBOX/ca/runs.json"; RB_CA_JOBS="$SANDBOX/ca/jobs-$MG_ID.json"
MUT_RUN=$((MUT_RUN + 1))
battery "$LIVE/body.sh" 1
RB_CA_RUNS=""; RB_CA_JOBS=""
if grep -qE '^ROW R(08|09|10|11|13)' <<<"$(grep -E '^ROW .* bad:' <<<"$BAT_LINES")"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "HARNESS H2: with a catch-all gh shim the no_mg_success / no_test_job rows must still go red"; fi

# workflow mutants: yml copies run through the checkers
# mutate_yml <name> <old> <new> <mode> <expected-tag-prefix>
mutate_yml() {
  local name="$1" old="$2" new="$3" cmode="$4" want="$5" f got
  f="$SANDBOX/mut/$name.yml"
  MUT_RUN=$((MUT_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$WF" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "MUTANT $name: mutation did NOT land ($(head -c 120 "$SANDBOX/mut.err"))"; return
  fi
  cmp -s "$f" "$WF" && { fail "MUTANT $name: byte-identical to ci.yml"; return; }
  got=$(chk "$cmode" "$f" 2>/dev/null)
  case " $got " in
    *" $want"*) MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass ;;
    *) fail "MUTANT $name: checker $cmode did not report $want (got: ${got:0:160})" ;;
  esac
}
COND_DEFAULT="if: \${{ !cancelled() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}"
mutate_yml y-no-coe "        continue-on-error: true
        timeout-minutes: 2
" "        timeout-minutes: 2
" wrapper W-COE
mutate_yml y-no-step-timeout "        timeout-minutes: 2
        env:" "        timeout-minutes: 9
        env:" wrapper W-STEPTIMEOUT
mutate_yml y-job-timeout "    timeout-minutes: 3
    permissions:" "    timeout-minutes: 5
    permissions:" wrapper W-JOBTIMEOUT
mutate_yml y-no-output "      elide: \${{ steps.proof.outputs.elide }}" "      elide: \${{ steps.proof.outputs.would_elide }}" wrapper W-OUTPUTS
mutate_yml y-perm "      actions: read" "      actions: write" wrapper W-PERM
mutate_yml y-success-fn "  test-bun:
    needs: [push-dedupe]
    $COND_DEFAULT" "  test-bun:
    needs: [push-dedupe]
    if: \${{ success() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}" truth TT:test-bun
mutate_yml y-no-event-disjunct "  test-bun:
    needs: [push-dedupe]
    $COND_DEFAULT" "  test-bun:
    needs: [push-dedupe]
    if: \${{ !cancelled() && needs.push-dedupe.outputs.elide != 'true' }}" truth TT:test-bun
mutate_yml y-lost-cancelled "  test-bun:
    needs: [push-dedupe]
    $COND_DEFAULT" "  test-bun:
    needs: [push-dedupe]
    if: \${{ github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true' }}" truth TT:test-bun
mutate_yml y-lost-need "  test-bun:
    needs: [push-dedupe]" "  test-bun:
    needs: []" gated G-NEEDS:test-bun
mutate_yml y-extra-gated "    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true'
" "    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true' || needs.push-dedupe.outputs.elide == 'x'
" gated G-SET
mutate_yml y-agg-env "          EVENT_NAME: \${{ github.event_name }}
        run: |
          # NAME THE MEASURED CAUSE" "          EVENT_NAME: \${{ github.event_name }}
          ELIDE: \${{ needs.push-dedupe.outputs.elide }}
        run: |
          # NAME THE MEASURED CAUSE" agg A-DIGEST
mutate_yml y-agg-tolerate "              skipped)
                echo \"\$shard: SKIPPED — the leg did not run\" >&2" "              skipped)
                fail=0
                echo \"\$shard: SKIPPED — the leg did not run\" >&2" agg A-DIGEST

# the coupling row itself must go red when the aggregator tolerates a skipped leg
cp "$SANDBOX/live/agg.sh" "$SANDBOX/mut/agg-tol.sh" 2>/dev/null
MUT_RUN=$((MUT_RUN + 1))
if python3 "$SANDBOX/mut.py" "$SANDBOX/live/agg.sh" "$SANDBOX/mut/agg-tol.sh" '      echo "$shard: SKIPPED — the leg did not run" >&2' '      fail=0; continue' 2>/dev/null; then
  _save="$SANDBOX/live/agg.sh"; cp "$_save" "$SANDBOX/live/agg.orig"; cp "$SANDBOX/mut/agg-tol.sh" "$_save"
  agg_run SCRIPTS_RESULT; _rc=$?
  cp "$SANDBOX/live/agg.orig" "$_save"
  if [ "$_rc" -eq 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT agg-tolerates-skip: a tolerant aggregator should exit 0 on a skipped leg (the coupling row would see it); got rc=$_rc"; fi
else
  fail "MUTANT agg-tolerates-skip: mutation did NOT land"
fi

# ── Mutant accounting and measured counts ────────────────────────────────────
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ]; then pass
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught)"; fi
if [ "$MUT_RUN" -ge 40 ] && [ "$EQUIV_RUN" -eq 2 ] && [ "$EQUIV_OK" -eq 2 ]; then pass
else fail "MUTANT FLOOR: $MUT_RUN killing mutants ran (floor 40), $EQUIV_OK of $EQUIV_RUN equivalent mutants confirmed (want 2 of 2)"; fi

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): a floor that increments the counter it guards shares a
# lifetime with the thing it is checking. This compares against a literal and exits directly.
#
# KEEP THESE TWO ASSIGNMENTS CONTIGUOUS (no comment between them or before the `if`):
# scripts/guard-vacuity-floor.test.sh binds a floor's variables by walking BACKWARD from the `if`.
_total=$((passes + fails))
_FLOOR=132
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-push-dedupe: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-push-dedupe: %d passed, %d failed (%d assertions; %d mutants caught of %d; %d battery rows)\n' \
  "$passes" "$fails" "$_total" "$MUT_CAUGHT" "$MUT_RUN" "$CTRL_N"
exit $(( ${#FAILURES[@]} > 0 ))
