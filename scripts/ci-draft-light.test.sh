#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 for #9728 (ADR-276 S3): the `draft-light` gate and the red draft aggregator in .github/workflows/ci.yml.
#
# WHAT THE GATE IS. On a `pull_request` run, job `draft-light` decides whether the four measured heavy jobs
# (test-webplat, test-scripts, test-scripts-heavy, shard-totality-mutations) may be skipped because the PR is a
# DRAFT. It is a COST lever allowed to fail in one direction only: every unknown runs the full battery. When it
# does skip them the `test` aggregator concludes RED by design (Option R, ADR-276 Decision 4), so a light draft can
# never be merged on the strength of a light run; the `ready_for_review` run is never light, and runs the full set.
#
# WHAT THIS SUITE PROVES. Not that the YAML mentions the right words, but that
#   * the `light` step body, EXTRACTED from ci.yml and EXECUTED under the shell Actions uses
#     (`bash --noprofile --norc -eo pipefail`) against a gh shim, emits `light=true` LAST and only when the switch is
#     exactly `on`, the action is not `ready_for_review`, the head repository is this repository, and a bounded
#     LIVE read of the pull request returns the JSON boolean draft == true (the event payload's draft flag is not an
#     input);
#   * the wrapper (job `if`, permissions, outputs, flags, env, timeouts, no `uses`/secrets/checkout), the trigger
#     `types:`, the four gated conditions (EVALUATED over an event x output x need-result truth table), the gated-set
#     parity in BOTH directions (derived from the parsed YAML) and the untouched light set are what the design says;
#   * the `test` aggregator body, EXECUTED over result triples, exits 1 with `draft: full battery owed at ready` for a
#     light draft EVEN IF the loop is made to tolerate skipped legs, and is unaffected on merge_group, push and
#     workflow_dispatch;
#   * mutation rows against mutated COPIES of the body and the workflow in mktemp dirs: a mutant is CAUGHT only when the
#     battery or the checker names the expected row; a crash proves nothing;
#   * harness rows: stub bodies that always light, never light or always pass must be refused, and a floor of
#     zero rows must fail.
#
# THE gh SHIM validates the one exact endpoint (`repos/$GH_REPO/pulls/$PR_NUMBER`, no flags), exits non-zero when
# GH_TOKEN is unset as real gh does, logs every call and exits 64 on any other request (a STUB-MISS fails the row).
#
# PRE-MERGE LIMIT. The evaluator encodes the rule it tests. The authority for the live read is the canary on the PR's
# own runs; this suite pins the decision logic and the wiring.
#
# This suite writes ONLY under mktemp rooted at ${TMPDIR:-/var/tmp}; never into the repo.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree);
# the registered runners default to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array, which can only be silenced
# by deleting evidence, not by moving a counter.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WF="$REPO_ROOT/.github/workflows/ci.yml"

SANDBOX=$(mktemp -d "$TMPDIR/ci-draft-light.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

for _dep in python3 jq bash timeout cmp; do
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
# The S2 condition every gated job already carries, and the S3 clause appended to the four heavy ones.
ELIDE_TAIL="(github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true')"
LIGHT_CLAUSE="needs.draft-light.outputs.light != 'true'"
# The four heavy families S3 gates. A NEW HEAVY JOB MUST JOIN THIS SET (needs [push-dedupe, draft-light] plus the clause).
HEAVY_PINNED="shard-totality-mutations test-scripts test-scripts-heavy test-webplat"
# Jobs that carry S2's push-dedupe pair but deliberately NO draft-light term: they run on drafts (the light set).
# e2e is a required context and must keep reporting on drafts (#8450); test-bun is 1.81 min/run (below the 3 min bar);
# web-platform-build and the aggregator `test` are checked on their own below.
S2_ONLY_PINNED="e2e test-bun web-platform-build"
# Every other job: cheap guards and the lever itself. A NEW job must be classified: add it to HEAVY_PINNED or here.
LIGHT_PINNED="adr-ordinals credential-path-guard critical-css-gate detect-changes draft-light encryption-posture grok-fidelity harness-discovery lint-bot-statuses lint-webplat lockfile-sync marketplace-manifest-guard plugin-root-propagation-gate push-dedupe rule-body-lint sandbox-canary-capture-gate service-role-allowlist-gate tc-document-sha-guard"
TYPES_PINNED='["opened", "synchronize", "reopened", "ready_for_review"]'
REASONS="bad_pr ready fork read_error not_draft switch_off ok"
REPO_SLUG="jikig-ai/soleur"
POISON='x
light=true
::error::pwn'
DRAFT_MSG="draft: full battery owed at ready"

mkdir -p "$SANDBOX/shim" "$SANDBOX/shim-timeout" "$SANDBOX/mut" "$SANDBOX/live"

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
import json, os, re, sys, yaml
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
mode, path = sys.argv[1], sys.argv[2]
HEAVY = os.environ.get("HEAVY_PINNED", "").split()
S2ONLY = os.environ.get("S2_ONLY_PINNED", "").split()
LIGHTSET = os.environ.get("LIGHT_PINNED", "").split()
TAIL = os.environ["ELIDE_TAIL"]
CLAUSE = os.environ["LIGHT_CLAUSE"]
TYPES = json.loads(os.environ["TYPES_PINNED"])
CANON_HEAVY = "${{ !cancelled() && " + TAIL + " && " + CLAUSE + " }}"
CANON_S2 = "${{ !cancelled() && " + TAIL + " }}"
CANON_TEST = "${{ always() && " + TAIL + " }}"
ENV_KEYS = {"GH_TOKEN", "GH_REPO", "PR_NUMBER", "ACTION", "HEAD_REPO", "SWITCH"}
LEGS = {"test-webplat", "test-bun", "test-scripts", "test-scripts-heavy", "web-platform-build", "encryption-posture"}

def load():
    try:
        d = yaml.load(open(path).read(), Loader=LOADER)
        return d, (d.get("jobs") or {})
    except Exception as e:
        sys.stderr.write("chk.py crashed: %r\n" % (e,)); sys.exit(2)

def needs(j):
    n = (j or {}).get("needs", [])
    return [n] if isinstance(n, str) else list(n)

def ev(expr, event, elide, light, need_results, cancelled=False):
    e = str(expr).strip()
    if not (e.startswith("${{") and e.endswith("}}")):
        return None
    e = e[3:-2].strip()
    has_status = bool(re.search(r"\b(cancelled|always|success|failure)\(\)", e))
    e = e.replace("!cancelled()", "(not CANC)").replace("always()", "True").replace("success()", "(NEEDOK)")
    e = e.replace("github.event_name", "EV").replace("needs.push-dedupe.outputs.elide", "EL").replace("needs.draft-light.outputs.light", "LT")
    e = e.replace("&&", " and ").replace("||", " or ")
    ok = all(r == "success" for r in need_results)
    try:
        val = bool(eval(e, {"__builtins__": {}}, {"CANC": cancelled, "EV": event, "EL": elide, "LT": light, "NEEDOK": ok}))
    except Exception:
        return None
    if not has_status:
        val = val and ok
    return val

if mode == "extract":
    out = sys.argv[3]
    d, jobs = load()
    job = jobs.get("draft-light")
    steps = (job or {}).get("steps") or []
    body = [s for s in steps if isinstance(s, dict) and s.get("id") == "light" and "run" in s]
    if len(body) != 1:
        sys.stderr.write("found %d light steps in job draft-light (0 = job absent)\n" % len(body)); sys.exit(3)
    open(out + "/body.sh", "w").write(body[0]["run"])
    sys.exit(0)

if mode == "trigger":
    d, jobs = load()
    on = d.get("on", d.get(True)) or {}
    pr = on.get("pull_request") if isinstance(on, dict) else None
    tags = []
    if not isinstance(pr, dict) or pr.get("types") != TYPES:
        tags.append("T-TYPES:%s" % json.dumps((pr or {}).get("types") if isinstance(pr, dict) else pr))
    for k in ("push", "merge_group", "workflow_dispatch"):
        if k not in on: tags.append("T-LOST:" + k)
    # the header comment (everything before `jobs:`) names the stage, the variable and the option
    head = open(path).read().split("\njobs:\n")[0]
    for tok in ("S3", "CI_DRAFT_LIGHT", "Option R"):
        if tok not in head: tags.append("T-HEADER:" + tok)
    print(" ".join(tags)); sys.exit(0)

if mode == "wrapper":
    d, jobs = load()
    tags = []
    job = jobs.get("draft-light")
    if job is None:
        print("W-JOB-MISSING"); sys.exit(0)
    if job.get("if") != "github.event_name == 'pull_request'": tags.append("W-JOBIF")
    if job.get("timeout-minutes") != 3: tags.append("W-JOBTIMEOUT")
    if job.get("permissions") != {"pull-requests": "read"}: tags.append("W-PERM")
    if job.get("outputs") != {"light": "${{ steps.light.outputs.light }}"}: tags.append("W-OUTPUTS")
    if job.get("continue-on-error") is not True: tags.append("W-JOBCOE")
    if job.get("runs-on") != "ubuntu-latest": tags.append("W-RUNSON")
    if needs(job): tags.append("W-JOBNEEDS")
    steps = job.get("steps") or []
    if [s.get("id") for s in steps] != ["light", "would-light"]: tags.append("W-STEPS")
    for s in steps:
        if "uses" in s: tags.append("W-USES")
    txt = json.dumps(job)
    if "secrets." in txt: tags.append("W-SECRETS")
    if "checkout" in txt: tags.append("W-CHECKOUT")
    step = next((s for s in steps if s.get("id") == "light"), {})
    if step.get("continue-on-error") is not True: tags.append("W-COE")
    if step.get("timeout-minutes") != 2: tags.append("W-STEPTIMEOUT")
    if step.get("shell") != "bash": tags.append("W-SHELL")
    env = step.get("env") or {}
    if set(env.keys()) != ENV_KEYS: tags.append("W-ENVKEYS")
    exp = {"GH_TOKEN": "${{ github.token }}", "GH_REPO": "${{ github.repository }}",
           "PR_NUMBER": "${{ github.event.pull_request.number }}", "ACTION": "${{ github.event.action }}",
           "HEAD_REPO": "${{ github.event.pull_request.head.repo.full_name }}", "SWITCH": "${{ vars.CI_DRAFT_LIGHT }}"}
    if any(env.get(k) != v for k, v in exp.items()): tags.append("W-ENVVALUES")
    for s in steps:
        if s is not step and "GH_TOKEN" in (s.get("env") or {}): tags.append("W-TOKEN-LEAK")
    body = step.get("run", "")
    if re.search(r"set\s+-[a-zA-Z]*x|xtrace", body): tags.append("W-XTRACE")
    if "set +x" not in body: tags.append("W-NOXTRACEOFF")
    if "${{" in body: tags.append("W-INTERP")
    gh_calls = len(re.findall(r"\bgh api\b", body))
    t_calls = len(re.findall(r"\btimeout 20 gh api\b", body))
    if gh_calls != 1 or t_calls != 1: tags.append("W-GHTIMEOUT")
    # `light=true` is emitted exactly once, as the LAST emit, after the live read, the draft check and the switch compare
    lights = re.findall(r'emit "light=true"', body)
    if len(re.findall(r'GITHUB_OUTPUT', body)) != 1: tags.append("W-OUTPUT-SINKS")
    emits = [m.start() for m in re.finditer(r'\bemit "', body)]
    i_emit = body.find('emit "light=true"')
    i_read = body.find("gh api"); i_draft = body.find(".draft == true"); i_switch = body.find('[ "$SWITCH" = on ]')
    if len(lights) != 1 or i_emit < 0 or not emits or emits[-1] != i_emit: tags.append("W-LIGHT-LAST")
    if not (0 <= i_read < i_draft < i_switch < i_emit): tags.append("W-LIGHT-ORDER")
    if body.find('[ "$ACTION" != ready_for_review ]') < 0 or body.find('[ "$ACTION" != ready_for_review ]') > i_read: tags.append("W-ACTION-ORDER")
    if body.find('"$HEAD_REPO" = "$GH_REPO"') < 0 or body.find('"$HEAD_REPO" = "$GH_REPO"') > i_read: tags.append("W-FORK-ORDER")
    would = steps[1] if len(steps) > 1 else {}
    if would.get("if") != "steps.light.outputs.would_light == 'true'": tags.append("W-WOULDIF")
    # the release workflow's CI budget awk reads `timeout-minutes: N` alone on a line
    text = open(path).read().split("\n")
    try:
        i0 = text.index("  draft-light:")
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
    dl_needs = sorted(n for n, j in jobs.items() if n not in ("draft-light", "test") and "draft-light" in needs(j))
    dl_if = sorted(n for n, j in jobs.items() if n not in ("draft-light",) and "needs.draft-light" in str((j or {}).get("if", "")))
    # parity, both directions: every job gated is in the pinned set and every pinned heavy job is gated
    if dl_needs != sorted(HEAVY): tags.append("G-SET-NEEDS:" + ",".join(dl_needs))
    if dl_if != sorted(HEAVY): tags.append("G-SET-IF:" + ",".join(dl_if))
    for n in HEAVY:
        j = jobs.get(n)
        if j is None: tags.append("G-MISSING:" + n); continue
        if sorted(needs(j)) != ["draft-light", "push-dedupe"]: tags.append("G-NEEDS:" + n)
        if j.get("if") != CANON_HEAVY: tags.append("G-COND:" + n)
        if j.get("continue-on-error"): tags.append("G-COE:" + n)
    for n in S2ONLY:
        j = jobs.get(n)
        if j is None: tags.append("G-MISSING:" + n); continue
        if "draft-light" in needs(j) or "draft-light" in str(j.get("if", "")): tags.append("G-S2ONLY-TOUCHED:" + n)
        if j.get("if") != CANON_S2: tags.append("G-S2ONLY-COND:" + n)
        if needs(j) != ["push-dedupe"]: tags.append("G-S2ONLY-NEEDS:" + n)
    t = jobs.get("test") or {}
    if "draft-light" not in needs(t): tags.append("G-TEST-NEEDS")
    if t.get("if") != CANON_TEST: tags.append("G-TEST-IF")
    classified = set(HEAVY) | set(S2ONLY) | set(LIGHTSET) | {"test"}
    for n, j in jobs.items():
        if n not in classified: tags.append("G-UNCLASSIFIED:" + n)
        if n not in HEAVY and n not in ("test",) and n != "draft-light":
            if "draft-light" in needs(j) or "needs.draft-light" in str((j or {}).get("if", "")): tags.append("G-EXTRA:" + n)
        if n != "draft-light" and "draft-light" in json.dumps((j or {}).get("outputs", {})): tags.append("G-REEXPORT:" + n)
    for n in LIGHTSET + S2ONLY:
        if n not in jobs: tags.append("G-GONE:" + n)
    print(" ".join(tags)); sys.exit(0)

if mode == "truth":
    d, jobs = load()
    tags = []
    for n in HEAVY:
        j = jobs.get(n) or {}
        for event in ("push", "pull_request", "merge_group", "workflow_dispatch"):
            for elide in ("", "false", "true"):
                for light in ("", "false", "true"):
                    # every need result shape: draft-light/push-dedupe skipped (off their event), success, failure
                    for rs in (("skipped", "success"), ("success", "skipped"), ("skipped", "skipped"), ("failure", "success"), ("success", "failure")):
                        got = ev(j.get("if"), event, elide, light, rs)
                        want = not (event == "push" and elide == "true") and light != "true"
                        if got is None: tags.append("TT-ERR:%s" % n)
                        elif got != want: tags.append("TT:%s:%s:%s:%s" % (n, event, elide or "empty", light or "empty"))
        if ev(j.get("if"), "pull_request", "", "", ("success", "success"), cancelled=True) is not False:
            tags.append("TT-CANCEL:" + n)
    print(" ".join(sorted(set(tags)))); sys.exit(0)

if mode == "agg":
    d, jobs = load()
    t = jobs.get("test")
    if t is None: print("A-MISSING"); sys.exit(0)
    tags = []
    n = needs(t)
    if "draft-light" not in n: tags.append("A-NEEDS")
    if sorted(x for x in n if x not in LEGS) != ["draft-light", "push-dedupe"]: tags.append("A-NEEDS-SET")
    st = (t.get("steps") or [{}])[0]
    env = st.get("env") or {}
    if "".join(str(env.get("DRAFT_LIGHT", "")).split()) != "${{needs.draft-light.outputs.light}}": tags.append("A-ENV")
    if "".join(str(env.get("EVENT_NAME", "")).split()) != "${{github.event_name}}": tags.append("A-EVENT-ENV")
    body = st.get("run", "")
    # the arm sits AFTER the loop and BEFORE the final `if [[ $fail -ne 0 ]]`, once, and exits 1
    i_final = body.find("if [[ $fail -ne 0 ]]")
    i_arm = body.find('"$DRAFT_LIGHT" == "true"')
    i_done = body.rfind("\ndone", 0, i_final if i_final >= 0 else len(body))
    if body.count('"$DRAFT_LIGHT" == "true"') != 1: tags.append("A-ARM-COUNT")
    if not (0 <= i_done < i_arm < i_final): tags.append("A-ARM-PLACE")
    arm = body[i_arm:i_final] if 0 <= i_arm < i_final else ""
    if '"$EVENT_NAME" == "pull_request"' not in body[max(0, i_arm - 120):i_arm + 40]: tags.append("A-ARM-EVENT")
    if "exit 1" not in arm or "exit 0" in arm: tags.append("A-ARM-EXIT")
    if ("echo \"%s\" >&2" % os.environ["DRAFT_MSG"]) not in arm: tags.append("A-ARM-MSG")
    print(" ".join(tags)); sys.exit(0)

if mode == "aggbody":
    out = sys.argv[3]
    d, jobs = load()
    t = jobs["test"]; st = t["steps"][0]
    open(out + "/agg.sh", "w").write(st["run"])
    open(out + "/agg.env", "w").write("".join("%s\n" % k for k in (st.get("env") or {})))
    sys.exit(0)
sys.stderr.write("unknown mode\n"); sys.exit(2)
PY

chk() {
  HEAVY_PINNED="$HEAVY_PINNED" S2_ONLY_PINNED="$S2_ONLY_PINNED" LIGHT_PINNED="$LIGHT_PINNED" ELIDE_TAIL="$ELIDE_TAIL" \
    LIGHT_CLAUSE="$LIGHT_CLAUSE" TYPES_PINNED="$TYPES_PINNED" DRAFT_MSG="$DRAFT_MSG" python3 "$SANDBOX/chk.py" "$@"
}

# ── Helper: the gh shim ──────────────────────────────────────────────────────
cat > "$SANDBOX/shim/gh" <<'SH'
#!/usr/bin/env bash
# FIX: fixture dir. Files: pull.json (served verbatim), mode (ok|fail). EXP_ENDPOINT: the one endpoint this shim serves.
printf '%s\n' "$*" >> "$FIX/calls.log"
if [ "${1:-}" != api ] || [ "$#" -ne 2 ]; then echo "STUB-MISS: argv must be exactly: api <endpoint>: $*" >> "$FIX/calls.log"; exit 64; fi
[ -n "${GH_TOKEN:-}" ] || { echo "gh: GH_TOKEN required" >&2; exit 4; }
if [ "$2" != "$EXP_ENDPOINT" ]; then echo "STUB-MISS: unexpected endpoint: $2" >> "$FIX/calls.log"; exit 64; fi
mode=$(cat "$FIX/mode" 2>/dev/null || echo ok)
case "$mode" in
  fail) printf 'boom\nlight=true\n::error::pwn\n' >&2; exit 1 ;;
esac
cat "$FIX/pull.json"; exit 0
SH
chmod +x "$SANDBOX/shim/gh"
# a `timeout` that always reports a timeout (exit 124), to prove a hung read becomes a full run
cat > "$SANDBOX/shim-timeout/timeout" <<'SH'
#!/usr/bin/env bash
exit 124
SH
chmod +x "$SANDBOX/shim-timeout/timeout"

# ── Fixture builders ─────────────────────────────────────────────────────────
FXD=""
fx_new() { FXD="$1"; assert_fixture_dir "$FXD"; rm -rf "$FXD"; mkdir -p "$FXD"; printf ok > "$FXD/mode"; : > "$FXD/calls.log"; printf '{}' > "$FXD/pull.json"; }
# fx_pull <draft-json-literal>: a realistic pull-request object (extra keys, a poisoned title, a head repository)
fx_pull() {
  assert_fixture_dir "$FXD"
  jq -nc --argjson d "$1" --arg poison "$POISON" --arg repo "$REPO_SLUG" \
    '{url:"https://api.github.com/repos/x/y/pulls/42", number:42, state:"open", title:$poison, draft:$d, head:{ref:"feat-x", repo:{full_name:$repo}}, base:{ref:"main"}}' > "$FXD/pull.json"
}
fx_raw() { assert_fixture_dir "$FXD"; printf '%s' "$1" > "$FXD/pull.json"; }

# ── Row runner: executes a body under the Actions shell against the shim ─────
declare -A E
set_env_defaults() {
  E=([GH_TOKEN]=tok [GH_REPO]="$REPO_SLUG" [PR_NUMBER]=42 [ACTION]=synchronize [HEAD_REPO]="$REPO_SLUG" [SWITCH]=on [EVENT_DRAFT]=__UNSET__)
}
BAT_N=0
BAT_LINES=""
ROWS_SEEN_REASONS=""
# row <id> <expect_light> <expect_would> <expect_reason> <expect_live_reads>   (fixture already built in $FXD, env in E)
row() {
  local id="${1//[^[:alnum:]_.-]/_}" xl="$2" xw="$3" xr="$4" xc="$5" out so rc why="" k
  BAT_N=$((BAT_N + 1))
  assert_fixture_dir "$FXD"
  out="$FXD/gh_output"; so="$FXD/stdout"; : > "$out"
  local pathv jqdir envs=()
  jqdir=$(dirname "$(command -v jq)")
  pathv="${RB_SHIMPATH:-/nonexistent}:$SANDBOX/shim:$jqdir:/usr/bin:/bin"
  for k in GH_TOKEN GH_REPO PR_NUMBER ACTION HEAD_REPO SWITCH EVENT_DRAFT; do
    [ "${E[$k]-__UNSET__}" = "__UNSET__" ] || envs+=("$k=${E[$k]}")
  done
  ( cd "$FXD" && env -i PATH="$pathv" HOME="$FXD" FIX="$FXD" GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="$FXD/summary" \
      EXP_ENDPOINT="repos/${E[GH_REPO]-}/pulls/${E[PR_NUMBER]-}" "${envs[@]}" \
      bash --noprofile --norc -eo pipefail "$BODY" > "$so" 2> "$FXD/stderr" )
  rc=$?
  [ "$rc" -eq 0 ] || why="$why rc=$rc"
  # every output line is a literal verdict; `light=true` can only be the LAST line and only after would_light=true
  local bad_lines
  bad_lines=$(grep -cvE '^(would_light|light)=true$' "$out" || true)
  [ "$bad_lines" = 0 ] || why="$why output-line-not-literal"
  local gl gw lastline
  gl=false; grep -qx 'light=true' "$out" && gl=true
  gw=false; grep -qx 'would_light=true' "$out" && gw=true
  [ "$gl" = "$xl" ] || why="$why light=$gl(want $xl)"
  [ "$gw" = "$xw" ] || why="$why would=$gw(want $xw)"
  if [ "$gl" = true ]; then
    lastline=$(tail -n 1 "$out")
    [ "$lastline" = "light=true" ] || why="$why light-not-last"
    [ "$(grep -c '^light=true$' "$out")" = 1 ] || why="$why light-twice"
    [ "$(head -n 1 "$out")" = "would_light=true" ] || why="$why light-without-would"
  fi
  # stdout: only the one annotation, never a fixture string
  local nlines notices reason
  nlines=$(grep -c '' "$so" || true)
  notices=$(grep -cE '^::(notice|warning) title=ci-draft-light::pr=(invalid|[0-9]+) would_light=(true|false) light=(true|false) reason=[a-z_]+$' "$so" || true)
  [ "$nlines" = 1 ] && [ "$notices" = 1 ] || why="$why stdout-shape(lines=$nlines,annot=$notices)"
  if grep -qF 'pwn' "$so" "$out" "$FXD/summary" "$FXD/stderr" 2>/dev/null; then why="$why fixture-string-leaked"; fi
  reason=$(sed -n 's/.* reason=\([a-z_]*\)$/\1/p' "$so" | head -n 1)
  [ "$reason" = "$xr" ] || why="$why reason=$reason(want $xr)"
  local calls
  calls=$(grep -c '^api ' "$FXD/calls.log" || true)
  [ "$calls" = "$xc" ] || why="$why live-reads=$calls(want $xc)"
  if grep -q 'STUB-MISS' "$FXD/calls.log" 2>/dev/null; then why="$why stub-miss"; fi
  ROWS_SEEN_REASONS="$ROWS_SEEN_REASONS $reason"
  if [ -z "$why" ]; then BAT_LINES="$BAT_LINES"$'\n'"ROW $id ok"; else BAT_LINES="$BAT_LINES"$'\n'"ROW $id bad:$why"; fi
}

# battery <body> : fills BAT_LINES, BAT_N, ROWS_SEEN_REASONS
battery() {
  BODY="$1"; RB_SHIMPATH=""
  BAT_N=0; BAT_LINES=""; ROWS_SEEN_REASONS=""
  local d="$SANDBOX/bat" v a
  # R01 canonical: draft, same repo, switch on, a push to the draft
  fx_new "$d"; fx_pull true; set_env_defaults; row R01-canonical true true ok 1
  # R02 the switch: only the exact string `on` enables light mode (the variable is still observed: would_light)
  for v in "" ON On oN " on " "on " " on" true 1 yes onn "\"on\"" "'on'" $'on\n' $'on\r' "on;" "o n" "off"; do
    fx_new "$d"; fx_pull true; set_env_defaults; E[SWITCH]="$v"; row "R02-switch-[$v]" false true switch_off 1
  done
  fx_new "$d"; fx_pull true; set_env_defaults; E[SWITCH]=__UNSET__; row R02-switch-unset-var false true switch_off 1
  # R03 the event action: only ready_for_review is excluded, and it is excluded before any read
  for a in opened synchronize reopened; do
    fx_new "$d"; fx_pull true; set_env_defaults; E[ACTION]="$a"; row "R03-action-$a" true true ok 1
  done
  fx_new "$d"; fx_pull true; set_env_defaults; E[ACTION]=ready_for_review; row R03-action-ready_for_review false false ready 0
  # R04 the ready run is never light, whatever the variable and the reads say (a lagging read right after `gh pr ready`)
  fx_new "$d"; fx_pull true; set_env_defaults; E[ACTION]=ready_for_review; E[SWITCH]=on; row R04-ready-lagging-read-says-draft false false ready 0
  fx_new "$d"; fx_pull false; set_env_defaults; E[ACTION]=ready_for_review; row R04-ready-read-says-ready false false ready 0
  # R05 head repository: forks (and a deleted fork, whose expression resolves to the empty string) run full, before any read
  for v in attacker/soleur "$REPO_SLUG-evil" "x$REPO_SLUG" "${REPO_SLUG^^}" null ""; do
    fx_new "$d"; fx_pull true; set_env_defaults; E[HEAD_REPO]="$v"; row "R05-head-repo-[$v]" false false fork 0
  done
  fx_new "$d"; fx_pull true; set_env_defaults; E[HEAD_REPO]=__UNSET__; row R05-head-repo-unset false false fork 0
  fx_new "$d"; fx_pull true; set_env_defaults; E[HEAD_REPO]=""; E[GH_REPO]=""; row R05-both-empty false false fork 0
  # R06 the live read: only the JSON boolean true is a draft
  fx_new "$d"; fx_pull false; set_env_defaults; row R06-draft-false false false not_draft 1
  fx_new "$d"; fx_pull null; set_env_defaults; row R06-draft-null false false not_draft 1
  fx_new "$d"; fx_pull '"true"'; set_env_defaults; row R06-draft-string-true false false not_draft 1
  fx_new "$d"; fx_pull '"True"'; set_env_defaults; row R06-draft-string-True false false not_draft 1
  fx_new "$d"; fx_pull 1; set_env_defaults; row R06-draft-number-1 false false not_draft 1
  fx_new "$d"; fx_pull '[true]'; set_env_defaults; row R06-draft-array false false not_draft 1
  fx_new "$d"; fx_pull '{"draft":true}'; set_env_defaults; row R06-draft-object false false not_draft 1
  fx_new "$d"; fx_raw '{"number":42,"state":"open"}'; set_env_defaults; row R06-draft-key-missing false false not_draft 1
  fx_new "$d"; fx_raw '{"head":{"draft":true},"draft":false}'; set_env_defaults; row R06-draft-only-at-top-level false false not_draft 1
  fx_new "$d"; fx_raw '{"draft":false,"labels":[{"draft":true}]}'; set_env_defaults; row R06-draft-nested-array false false not_draft 1
  # R07 a malformed or failed read is full (reason read_error): error, empty, non-JSON, null, a bare array, truncated
  fx_new "$d"; fx_pull true; printf fail > "$d/mode"; set_env_defaults; row R07-read-fails false false read_error 1
  fx_new "$d"; fx_raw ''; set_env_defaults; row R07-read-empty-body false false read_error 1
  fx_new "$d"; fx_raw '{not json'; set_env_defaults; row R07-read-not-json false false read_error 1
  fx_new "$d"; fx_raw 'null'; set_env_defaults; row R07-read-null false false read_error 1
  fx_new "$d"; fx_raw '[{"draft":true}]'; set_env_defaults; row R07-read-array false false read_error 1
  fx_new "$d"; fx_raw '"draft"'; set_env_defaults; row R07-read-string false false read_error 1
  fx_new "$d"; fx_raw '{"draft":tru'; set_env_defaults; row R07-read-truncated false false read_error 1
  fx_new "$d"; fx_raw '{"message":"Not Found"}'; set_env_defaults; row R07-read-error-object false false not_draft 1
  fx_new "$d"; fx_pull true; set_env_defaults; E[GH_TOKEN]=""; row R07-no-token false false read_error 1
  fx_new "$d"; fx_pull true; set_env_defaults; E[GH_TOKEN]=__UNSET__; row R07-token-unset false false read_error 1
  fx_new "$d"; fx_pull true; set_env_defaults; RB_SHIMPATH="$SANDBOX/shim-timeout"; row R07-read-timeout false false read_error 0; RB_SHIMPATH=""
  # R08 a stale event payload never decides: the live read alone does (a re-run after ready, a payload still saying draft)
  fx_new "$d"; fx_pull false; set_env_defaults; E[EVENT_DRAFT]=true; row R08-payload-draft-live-ready false false not_draft 1
  fx_new "$d"; fx_pull true; set_env_defaults; E[EVENT_DRAFT]=false; row R08-payload-ready-live-draft true true ok 1
  # R09 the pull request number never reaches a URL unless it is digits
  for v in "" abc "42/../x" $'4\n2' -1 0x2a "4 2" "42;id" "42?x=1" " 42"; do
    fx_new "$d"; fx_pull true; set_env_defaults; E[PR_NUMBER]="$v"; row "R09-pr-[${v:0:8}]" false false bad_pr 0
  done
  fx_new "$d"; fx_pull true; set_env_defaults; E[PR_NUMBER]=__UNSET__; row R09-pr-unset false false bad_pr 0
  # R10 an empty or all-absent environment resolves 0 inputs: it must emit nothing (full) and never read
  fx_new "$d"; fx_pull true; set_env_defaults; for v in GH_TOKEN GH_REPO PR_NUMBER ACTION HEAD_REPO SWITCH; do E[$v]=__UNSET__; done
  row R10-all-absent false false bad_pr 0
  fx_new "$d"; fx_pull true; set_env_defaults; for v in GH_TOKEN GH_REPO PR_NUMBER ACTION HEAD_REPO SWITCH; do E[$v]=""; done
  row R10-all-empty false false bad_pr 0
  # R11 injection: a poisoned title/body on a MATCHING read reaches no output or annotation; a poisoned stderr likewise (R07-read-fails)
  fx_new "$d"; fx_pull true; set_env_defaults; row R11-poisoned-title-match true true ok 1
  fx_new "$d"; fx_pull true; set_env_defaults; E[SWITCH]="$POISON"; row R11-poisoned-switch false true switch_off 1
  # R12 permitted shapes that are NOT the canonical fixture: reordered keys, pretty-printed, extra keys, a long body
  fx_new "$d"; fx_raw '{"title":"t","labels":[{"name":"a"},{"name":"b"}],"head":{"repo":{"full_name":"x/y"}},"draft":true,"state":"open"}'
  set_env_defaults; row R12-reordered-keys true true ok 1
  fx_new "$d"; printf '{\n  "number": 42,\n  "draft"  :  true ,\n  "body": "%s"\n}\n' "$(printf 'x%.0s' $(seq 1 3000))" > "$d/pull.json"
  set_env_defaults; row R12-pretty-printed-long-body true true ok 1
  fx_new "$d"; fx_pull true; set_env_defaults; E[SWITCH]=on; row R12-switch-on-canonical-again true true ok 1
  # R13 the dark phase: variable unset or off, everything else holds -> observed (would_light), not applied
  fx_new "$d"; fx_pull true; set_env_defaults; E[SWITCH]=""; row R13-dark-would-light false true switch_off 1
  # R14 combinations: switch on but another leg of the conjunction fails
  fx_new "$d"; fx_pull true; set_env_defaults; E[ACTION]=ready_for_review; E[HEAD_REPO]=attacker/soleur; row R14-ready-and-fork false false ready 0
  fx_new "$d"; fx_pull false; set_env_defaults; E[HEAD_REPO]=attacker/soleur; row R14-fork-and-ready-pr false false fork 0
}

# ── Extract the live body ────────────────────────────────────────────────────
LIVE="$SANDBOX/live"
chk extract "$WF" "$LIVE" 2> "$SANDBOX/extract.err"; EXTRACT_RC=$?
if [ "$EXTRACT_RC" -ne 0 ]; then
  fail "EXTRACT: the draft-light step could not be extracted from ci.yml (rc=$EXTRACT_RC: $(head -c 200 "$SANDBOX/extract.err"))"
  # Everything below needs a body; report and stop so the failure is the extraction, not a cascade.
  printf 'ci-draft-light: %d passed, %d failed\n' "$passes" "$fails"
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

# ── Wrapper, trigger, gated set, truth table, aggregator wiring ──────────────
# A checker that CRASHES prints nothing to stdout; its exit status is part of its verdict.
live_check() { # <label> <mode>
  local out rc
  out=$(chk "$2" "$WF" 2>"$SANDBOX/chk.err"); rc=$?
  if [ "$rc" -ne 0 ]; then fail "$1: the checker crashed (rc=$rc: $(head -c 160 "$SANDBOX/chk.err"))"
  elif [ -n "$out" ]; then fail "$1 tags: $out"
  else pass; fi
}
live_check WRAPPER wrapper
live_check TRIGGER trigger
live_check "GATED" gated
live_check "TRUTH TABLE" truth
live_check "AGGREGATOR WIRING" agg

# No required name moves and no draft marker reaches the bot-synthetic path (ADR-276 Decision 4: Option T stays rejected).
names_clean() { # <root> -> prints offenders
  local root="$1" f bad=""
  for f in scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json infra/github/ruleset-ci-required.tf \
           .github/actions/bot-pr-with-synthetic-checks/action.yml apps/web-platform/server/inngest/functions/_cron-safe-commit.ts; do
    [ -f "$root/$f" ] || { bad="$bad MISSING:$f"; continue; }
    if grep -qiE 'draft-light|draft_light' "$root/$f"; then bad="$bad $f"; fi
  done
  printf '%s' "$bad"
}
_nc=$(names_clean "$REPO_ROOT")
if [ -z "$_nc" ]; then pass; else fail "REQUIRED NAMES: draft-light reached a required-context or synthetic-check surface:$_nc"; fi
grep -qx 'test' "$REPO_ROOT/scripts/required-checks.txt" && grep -qx 'e2e' "$REPO_ROOT/scripts/required-checks.txt" && pass \
  || fail "REQUIRED NAMES: test and e2e must both stay in scripts/required-checks.txt"

# ── The aggregator body, EXECUTED ────────────────────────────────────────────
chk aggbody "$WF" "$SANDBOX/live" 2>/dev/null
cp "$SANDBOX/live/agg.sh" "$SANDBOX/pristine-agg.sh" 2>/dev/null
declare -A A
set_agg_defaults() {
  A=([WEBPLAT_RESULT]=success [BUN_RESULT]=success [SCRIPTS_RESULT]=success [SCRIPTS_HEAVY_RESULT]=success [BUILD_RESULT]=success
     [POSTURE_RESULT]=success [EVENT_NAME]=pull_request [DRAFT_LIGHT]="")
}
AGG_N=0; AGG_LINES=""
# arow <id> <want_rc> <want_msg 0|1> <want_success_line 0|1>   (env in A; body in ABODY)
arow() {
  local id="${1//[^[:alnum:]_.-]/_}" wrc="$2" wmsg="$3" wok="$4" rc why="" k so se envs=()
  AGG_N=$((AGG_N + 1))
  so="$SANDBOX/agg.out"; se="$SANDBOX/agg.err"
  for k in "${!A[@]}"; do [ "${A[$k]}" = __UNSET__ ] || envs+=("$k=${A[$k]}"); done
  ( env -i PATH=/usr/bin:/bin "${envs[@]}" bash --noprofile --norc -eo pipefail "$ABODY" >"$so" 2>"$se" )
  rc=$?
  [ "$rc" -eq "$wrc" ] || why="$why rc=$rc(want $wrc)"
  if grep -qF -- "$DRAFT_MSG" "$se"; then [ "$wmsg" = 1 ] || why="$why msg-printed"; else [ "$wmsg" = 0 ] || why="$why msg-missing"; fi
  grep -qF -- "$DRAFT_MSG" "$so" && why="$why msg-on-stdout"
  if [ "$wok" = 1 ]; then grep -qF -- "All six legs green" "$so" || why="$why no-success-line"; else
    [ -s "$so" ] && why="$why stdout-not-empty"; fi
  if [ -z "$why" ]; then AGG_LINES="$AGG_LINES"$'\n'"AROW $id ok"; else AGG_LINES="$AGG_LINES"$'\n'"AROW $id bad:$why"; fi
}
agg_battery() { # <body>
  ABODY="$1"; AGG_N=0; AGG_LINES=""
  # a light draft: the four heavy legs skipped (the shard-totality leg is not an aggregator leg), the light legs green
  set_agg_defaults; A[DRAFT_LIGHT]=true; A[WEBPLAT_RESULT]=skipped; A[SCRIPTS_RESULT]=skipped; A[SCRIPTS_HEAVY_RESULT]=skipped
  arow D1-light-draft-skipped-legs 1 1 0
  # same, with the env order and an extra unrelated leg name (a non-canonical input that must reach the same verdict)
  set_agg_defaults; A[UNRELATED_RESULT]=success; A[DRAFT_LIGHT]=true; A[SCRIPTS_HEAVY_RESULT]=skipped; A[WEBPLAT_RESULT]=skipped; A[SCRIPTS_RESULT]=skipped
  arow D2-light-draft-reordered-extra-leg 1 1 0
  # the arm is unconditional on the legs: a light draft is red even if every leg reads success
  set_agg_defaults; A[DRAFT_LIGHT]=true
  arow D3-light-draft-all-success 1 1 0
  # the arm sits after the loop: a failing leg is still named, and the draft message still prints
  set_agg_defaults; A[DRAFT_LIGHT]=true; A[WEBPLAT_RESULT]=failure; A[SCRIPTS_RESULT]=skipped
  arow D4-light-draft-failed-leg 1 1 0
  # merge_group and push are unaffected: a skipped leg still fails (loop), the draft message never prints; all-green passes
  for ev in merge_group push workflow_dispatch; do
    set_agg_defaults; A[EVENT_NAME]=$ev; A[DRAFT_LIGHT]=true; A[SCRIPTS_RESULT]=skipped
    arow "D5-$ev-light-skipped-leg" 1 0 0
    set_agg_defaults; A[EVENT_NAME]=$ev; A[DRAFT_LIGHT]=true
    arow "D6-$ev-light-all-success" 0 0 1
  done
  # not light: green stays green, a skipped leg stays red, and nothing says "draft"
  for v in "" false FALSE True TRUE 1 yes " true" "true " __UNSET__; do
    set_agg_defaults; A[DRAFT_LIGHT]="$v"
    arow "D7-pr-not-light-[$v]-all-success" 0 0 1
  done
  set_agg_defaults; A[SCRIPTS_RESULT]=skipped
  arow D8-pr-not-light-skipped-leg 1 0 0
  set_agg_defaults; A[EVENT_NAME]=__UNSET__; A[DRAFT_LIGHT]=true
  arow D9-event-unset-light-all-success 0 0 1
  # the loop still names every leg; ordering: the draft message follows the per-leg lines
  set_agg_defaults; A[DRAFT_LIGHT]=true; A[WEBPLAT_RESULT]=skipped
  arow D10-light-draft-one-skipped-leg 1 1 0
}

agg_battery "$SANDBOX/pristine-agg.sh"
_aok=0; _abad=0
while IFS= read -r ln; do
  case "$ln" in
    "AROW "*" ok") _aok=$((_aok + 1)); pass ;;
    "AROW "*) _abad=$((_abad + 1)); fail "AGGREGATOR ${ln#AROW }" ;;
  esac
done <<<"$AGG_LINES"
AGG_CTRL_N=$AGG_N
if [ "$AGG_CTRL_N" -eq $((_aok + _abad)) ] && [ "$AGG_CTRL_N" -ge 23 ]; then pass
else fail "AGGREGATOR COUNT: arow() ran $AGG_CTRL_N rows but $((_aok + _abad)) verdict lines were read (floor 23)"; fi

# a light draft must stay red even if a later edit makes the loop TOLERATE skipped legs (the arm is the verdict, not the loop)
sed 's/^\([[:space:]]*\)fail=1/\1: fail=1/' "$SANDBOX/pristine-agg.sh" > "$SANDBOX/mut/agg-tolerant.sh"
if cmp -s "$SANDBOX/mut/agg-tolerant.sh" "$SANDBOX/pristine-agg.sh"; then fail "TOLERANT: the loop-tolerating mutation did not land"; else
  ABODY="$SANDBOX/mut/agg-tolerant.sh"
  set_agg_defaults; A[DRAFT_LIGHT]=true; A[WEBPLAT_RESULT]=skipped; A[SCRIPTS_RESULT]=skipped; A[SCRIPTS_HEAVY_RESULT]=skipped
  AGG_LINES=""; arow T1-tolerant-loop-light-draft 1 1 0
  case "$AGG_LINES" in *" ok") pass ;; *) fail "TOLERANT: a light draft must exit 1 even when the loop tolerates skipped legs:$AGG_LINES" ;; esac
  # sanity: the tolerant loop really tolerates (off pull_request it exits 0 on a skipped leg), so the row above is not vacuous
  ( env -i PATH=/usr/bin:/bin WEBPLAT_RESULT=success BUN_RESULT=success SCRIPTS_RESULT=skipped SCRIPTS_HEAVY_RESULT=success BUILD_RESULT=success POSTURE_RESULT=success EVENT_NAME=merge_group DRAFT_LIGHT=true bash --noprofile --norc -eo pipefail "$SANDBOX/mut/agg-tolerant.sh" >/dev/null 2>&1 ); _trc=$?
  if [ "$_trc" -eq 0 ]; then pass; else fail "TOLERANT: the tolerant-loop control did not exit 0 off pull_request (rc=$_trc), so the row above proves nothing"; fi
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
# the switch compare: only the exact string `on`
mutate_body m-switch-case '[ "$SWITCH" = on ]' '[ "${SWITCH,,}" = on ]' R02
mutate_body m-switch-trim '[ "$SWITCH" = on ]' '[ "${SWITCH//[[:space:]]/}" = on ]' R02
mutate_body m-switch-prefix '[ "$SWITCH" = on ]' '[[ "$SWITCH" == on* ]]' R02
mutate_body m-switch-always '[ "$SWITCH" = on ]' 'true' R02
mutate_body m-switch-nonempty '[ "$SWITCH" = on ]' '[ -n "$SWITCH" ]' R02
# `light` emitted before the live read (the read fails, the switch is on): must go red on every failed-read row
mutate_body m-light-before-read 'reason=read_error' 'reason=read_error; [ "$SWITCH" = on ] && emit "light=true"' R07
mutate_body m-light-before-draft-check 'reason=not_draft' 'reason=not_draft; [ "$SWITCH" = on ] && emit "light=true"' R06
mutate_body m-light-first 'would=false' 'would=false; [ "$SWITCH" = on ] && emit "light=true"' R0
# the action and the repository
mutate_body m-no-ready-check '[ "$ACTION" != ready_for_review ] || finish' 'true' R03-action-ready
mutate_body m-ready-after-read '[ "$ACTION" != ready_for_review ] || finish' 'true; : ' R04
mutate_body m-no-fork-check '{ [ -n "$HEAD_REPO" ] && [ "$HEAD_REPO" = "$GH_REPO" ]; } || finish' 'true' R05
mutate_body m-no-empty-head '[ -n "$HEAD_REPO" ] && ' '' R05-both-empty
mutate_body m-fork-nocase '[ "$HEAD_REPO" = "$GH_REPO" ]' '[ "${HEAD_REPO,,}" = "${GH_REPO,,}" ]' R05
mutate_body m-fork-prefix '[ "$HEAD_REPO" = "$GH_REPO" ]' '[[ "$HEAD_REPO" == "$GH_REPO"* ]]' R05
# the live read
mutate_body m-payload-draft "jq -e '.draft == true'" '[ "${EVENT_DRAFT:-}" = true ]' R08
mutate_body m-draft-truthy "jq -e '.draft == true'" "jq -e '.draft'" R06
mutate_body m-draft-any-depth "jq -e '.draft == true'" "jq -e 'any(.. | objects | .draft?; . == true)'" R06
mutate_body m-draft-string-ok "jq -e '.draft == true'" "jq -e '(.draft | tostring) == \"true\"'" R06
mutate_body m-no-object-check "jq -e 'type == \"object\"' >/dev/null 2>&1 || finish" 'true' R07
mutate_body m-timeout-removed 'timeout 20 gh api' 'gh api' R07-read-timeout
mutate_body m-stderr-leaks '2>/dev/null) || finish' ') || finish' R07-read-fails
mutate_body m-read-fails-open '2>/dev/null) || finish' "2>/dev/null) || pull='{\"draft\":true}'" R07
mutate_body m-wrong-endpoint 'repos/${GH_REPO}/pulls/${PR_NUMBER}' 'repos/${GH_REPO}/pulls' R01
mutate_body m-flag-added 'gh api "repos' 'gh api --method GET "repos' R01
mutate_body m-no-bad-pr '[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || finish' 'true' R09
mutate_body m-pr-prefix '[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || finish' '[[ "$PR_NUMBER" =~ ^[0-9]+ ]] || finish' R09
mutate_body m-echo-pull "printf '::notice title=ci-draft-light" "printf '%s' \"\$pull\"; printf '::notice title=ci-draft-light" R11
mutate_body m-would-not-emitted 'emit "would_light=true"' ':' R13
mutate_body m-light-twice 'emit "light=true"' 'emit "light=true"; emit "light=true"' R01
mutate_body m-default-light 'would=false' 'would=false; emit "light=true"' R0
mutate_body m-exit-nonzero '  exit 0
}' '  exit 3
}' R0

# EQUIVALENT mutants, recorded rather than hidden: a guard that a LATER guard repeats, so no verdict changes.
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
# the summary line is observability only; dropping it changes no verdict
mutate_body_equiv e-summary-dropped "printf 'draft-light: reason=%s would_light=%s light=%s\\n' \"\$reason\" \"\$would\" \"\$light\" >> \"\${GITHUB_STEP_SUMMARY:-/dev/null}\"" ':'

# harness (b): a stub body that always lights, and one that never emits anything, must be refused by the battery
printf '%s\n' 'printf "would_light=true\nlight=true\n" >> "$GITHUB_OUTPUT"; printf "::notice title=ci-draft-light::pr=invalid would_light=true light=true reason=ok\n"; exit 0' > "$SANDBOX/mut/stub-always.sh"
MUT_RUN=$((MUT_RUN + 1))
battery "$SANDBOX/mut/stub-always.sh"
_n_bad=$(grep -cE '^ROW .* bad:' <<<"$BAT_LINES" || true)
if [ "$_n_bad" -ge 60 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "HARNESS H1: an always-light stub went red on only $_n_bad rows (floor 60)"; fi
printf '%s\n' 'exit 0' > "$SANDBOX/mut/stub-exit0.sh"
MUT_RUN=$((MUT_RUN + 1))
battery "$SANDBOX/mut/stub-exit0.sh"
_n_bad=$(grep -cE '^ROW .* bad:' <<<"$BAT_LINES" || true)
if [ "$_n_bad" -ge 20 ] && grep -qE '^ROW R01-canonical bad:' <<<"$BAT_LINES"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "HARNESS H2: an exit-0 stub went red on only $_n_bad rows or let R01-canonical pass"; fi
printf '%s\n' 'echo light=true' > "$SANDBOX/mut/stub-echo.sh"
MUT_RUN=$((MUT_RUN + 1))
battery "$SANDBOX/mut/stub-echo.sh"
_n_bad=$(grep -cE '^ROW .* bad:' <<<"$BAT_LINES" || true)
if [ "$_n_bad" -ge 60 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "HARNESS H3: an echo-light stub went red on only $_n_bad rows (floor 60)"; fi

# harness (a): an aggregator stub that prints success must be refused by the aggregator battery
printf '%s\n' 'echo "All six legs green (four shards + web-platform-build + encryption-posture)."; exit 0' > "$SANDBOX/mut/agg-stub.sh"
MUT_RUN=$((MUT_RUN + 1))
agg_battery "$SANDBOX/mut/agg-stub.sh"
_n_bad=$(grep -cE '^AROW .* bad:' <<<"$AGG_LINES" || true)
if [ "$_n_bad" -ge 8 ] && grep -qE '^AROW D1-.* bad:' <<<"$AGG_LINES"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "HARNESS H4: a success-printing aggregator stub went red on only $_n_bad rows or let D1 pass"; fi

# aggregator mutants: a mutated COPY of the extracted body run through the aggregator battery
mutate_agg() { # <name> <old> <new> <expected-AROW-prefix>
  local name="$1" old="$2" new="$3" want="$4" f got
  f="$SANDBOX/mut/agg-$name.sh"
  MUT_RUN=$((MUT_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$SANDBOX/pristine-agg.sh" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "MUTANT agg-$name: mutation did NOT land ($(head -c 120 "$SANDBOX/mut.err"))"; return
  fi
  agg_battery "$f"
  got=$(grep -E "^AROW $want.* bad:" <<<"$AGG_LINES" | head -n 1)
  if [ -n "$got" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT agg-$name: no row with prefix $want went red"; fi
}
ARM_PRISTINE=$(python3 - "$SANDBOX/pristine-agg.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
i = s.find('if [[ "$EVENT_NAME" == "pull_request" && "$DRAFT_LIGHT" == "true" ]]')
j = s.find("if [[ $fail -ne 0 ]]")
sys.stdout.write(s[i:j] if 0 <= i < j else "")
PY
)
if [ -n "$ARM_PRISTINE" ]; then pass; else fail "ARM: the draft arm could not be located in the aggregator body (expected an if on EVENT_NAME == pull_request && DRAFT_LIGHT == true before the final check)"; fi
if [ -n "$ARM_PRISTINE" ]; then
  mutate_agg arm-removed "$ARM_PRISTINE" '' D1
  mutate_agg arm-exits-0 '  exit 1
fi
if [[ $fail -ne 0 ]]' '  exit 0
fi
if [[ $fail -ne 0 ]]' D3
  mutate_agg arm-any-event '"$EVENT_NAME" == "pull_request" && ' '' D5
  mutate_agg arm-loose-compare '"$DRAFT_LIGHT" == "true"' '-n "$DRAFT_LIGHT"' D7
  mutate_agg arm-case-insensitive '"$DRAFT_LIGHT" == "true"' '"${DRAFT_LIGHT,,}" == "true"' D7
  mutate_agg arm-event-loose 'if [[ "$EVENT_NAME" == "pull_request" && "$DRAFT_LIGHT"' 'if [[ "$EVENT_NAME" != "push" && "$DRAFT_LIGHT"' D5
  mutate_agg arm-no-message "echo \"$DRAFT_MSG\" >&2" ':' D1
  mutate_agg message-on-stdout "echo \"$DRAFT_MSG\" >&2" "echo \"$DRAFT_MSG\"" D1
  # the arm placed AFTER the final check is unreachable for a light draft (the skipped legs already set fail=1)
  _moved=$(python3 - "$SANDBOX/pristine-agg.sh" "$ARM_PRISTINE" <<'PY'
import sys
s = open(sys.argv[1]).read(); arm = sys.argv[2]
s = s.replace(arm, "", 1)
k = s.rfind("echo \"All six legs green")
sys.stdout.write(s[:k] + arm + s[k:])
PY
  )
  printf '%s' "$_moved" > "$SANDBOX/mut/agg-arm-after-final.sh"
  MUT_RUN=$((MUT_RUN + 1))
  if cmp -s "$SANDBOX/mut/agg-arm-after-final.sh" "$SANDBOX/pristine-agg.sh"; then fail "MUTANT agg-arm-after-final: mutation did NOT land"; else
    agg_battery "$SANDBOX/mut/agg-arm-after-final.sh"
    if grep -qE '^AROW D1-.* bad:' <<<"$AGG_LINES"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "MUTANT agg-arm-after-final: D1 stayed green"; fi
  fi
fi

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
HEAVY_IF="if: \${{ !cancelled() && $ELIDE_TAIL && $LIGHT_CLAUSE }}"
S2_IF="if: \${{ !cancelled() && $ELIDE_TAIL }}"
# trigger
mutate_yml y-types-no-ready "    types: [opened, synchronize, reopened, ready_for_review]" "    types: [opened, synchronize, reopened]" trigger T-TYPES
mutate_yml y-types-only-ready "    types: [opened, synchronize, reopened, ready_for_review]" "    types: [ready_for_review]" trigger T-TYPES
mutate_yml y-header-no-option "(Option R)" "(Option T)" trigger T-HEADER:Option
# the lever job
mutate_yml y-dl-no-if "  draft-light:
    if: github.event_name == 'pull_request'
" "  draft-light:
" wrapper W-JOBIF
mutate_yml y-dl-no-coe "    continue-on-error: true
    runs-on: ubuntu-latest
    timeout-minutes: 3
    permissions:
      pull-requests: read" "    runs-on: ubuntu-latest
    timeout-minutes: 3
    permissions:
      pull-requests: read" wrapper W-JOBCOE
mutate_yml y-dl-needs-heavy "    timeout-minutes: 3
    permissions:
      pull-requests: read" "    needs: [test-webplat]
    timeout-minutes: 3
    permissions:
      pull-requests: read" wrapper W-JOBNEEDS
mutate_yml y-dl-perm "      pull-requests: read" "      pull-requests: write" wrapper W-PERM
mutate_yml y-dl-timeout "    timeout-minutes: 3
    permissions:
      pull-requests: read" "    timeout-minutes: 5
    permissions:
      pull-requests: read" wrapper W-JOBTIMEOUT
mutate_yml y-dl-output "      light: \${{ steps.light.outputs.light }}" "      light: \${{ steps.light.outputs.would_light }}" wrapper W-OUTPUTS
mutate_yml y-dl-switch-var "          SWITCH: \${{ vars.CI_DRAFT_LIGHT }}" "          SWITCH: \${{ vars.CI_PUSH_DEDUPE }}" wrapper W-ENVVALUES
mutate_yml y-dl-payload-draft "          ACTION: \${{ github.event.action }}" "          ACTION: \${{ github.event.pull_request.draft }}" wrapper W-ENVVALUES
mutate_yml y-dl-xtrace-off-gone "          set +x
          emit() { printf '%s\\n' \"\$1\" >> \"\$GITHUB_OUTPUT\"; }
          would=false
          light=false" "          emit() { printf '%s\\n' \"\$1\" >> \"\$GITHUB_OUTPUT\"; }
          would=false
          light=false" wrapper W-NOXTRACEOFF
mutate_yml y-dl-no-step-coe "        continue-on-error: true
        timeout-minutes: 2
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          PR_NUMBER" "        timeout-minutes: 2
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          PR_NUMBER" wrapper W-COE
# the gated set
mutate_yml y-gate-no-clause "  test-webplat:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  test-webplat:
    needs: [push-dedupe, draft-light]
    $S2_IF" gated G-COND:test-webplat
mutate_yml y-gate-no-need "  test-scripts:
    needs: [push-dedupe, draft-light]" "  test-scripts:
    needs: [push-dedupe]" gated G-NEEDS:test-scripts
mutate_yml y-gate-heavy-missing-clause "  shard-totality-mutations:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  shard-totality-mutations:
    needs: [push-dedupe, draft-light]
    if: \${{ !cancelled() && $ELIDE_TAIL }}" gated G-SET-IF
mutate_yml y-gate-success-fn "  test-scripts-heavy:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  test-scripts-heavy:
    needs: [push-dedupe, draft-light]
    if: \${{ success() && $ELIDE_TAIL && $LIGHT_CLAUSE }}" truth TT:test-scripts-heavy
mutate_yml y-gate-lost-cancelled "  test-webplat:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  test-webplat:
    needs: [push-dedupe, draft-light]
    if: \${{ $ELIDE_TAIL && $LIGHT_CLAUSE }}" truth TT:test-webplat
mutate_yml y-gate-light-eq-false "  test-scripts:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  test-scripts:
    needs: [push-dedupe, draft-light]
    if: \${{ !cancelled() && $ELIDE_TAIL && needs.draft-light.outputs.light == 'false' }}" truth TT:test-scripts
mutate_yml y-gate-lost-elide "  test-scripts:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" "  test-scripts:
    needs: [push-dedupe, draft-light]
    if: \${{ !cancelled() && $LIGHT_CLAUSE }}" truth TT:test-scripts
# a fifth heavy job that needs draft-light but forgets the clause, and one gated in the condition but not in needs
mutate_yml y-gate-new-heavy-no-clause "
  credential-path-guard:
" "
  new-heavy-job:
    needs: [push-dedupe, draft-light]
    runs-on: ubuntu-latest
    steps:
      - run: true

  credential-path-guard:
" gated G-SET-NEEDS
mutate_yml y-gate-clause-without-need "
  credential-path-guard:
" "
  new-heavy-job:
    if: \${{ $LIGHT_CLAUSE }}
    runs-on: ubuntu-latest
    steps:
      - run: true

  credential-path-guard:
" gated G-SET-IF
mutate_yml y-gate-unclassified "
  credential-path-guard:
" "
  new-heavy-job:
    runs-on: ubuntu-latest
    steps:
      - run: true

  credential-path-guard:
" gated G-UNCLASSIFIED:new-heavy-job
# the untouched light set: e2e (a required context), test-bun, web-platform-build gain no draft-light term
mutate_yml y-e2e-needs "  e2e:
    needs: [push-dedupe]" "  e2e:
    needs: [push-dedupe, draft-light]" gated G-S2ONLY-TOUCHED:e2e
mutate_yml y-e2e-if "  e2e:
    needs: [push-dedupe]
    $S2_IF" "  e2e:
    needs: [push-dedupe]
    $HEAVY_IF" gated G-S2ONLY-TOUCHED:e2e
mutate_yml y-test-bun-gated "  test-bun:
    needs: [push-dedupe]
    $S2_IF" "  test-bun:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" gated G-S2ONLY-TOUCHED:test-bun
mutate_yml y-build-gated "  web-platform-build:
    needs: [push-dedupe]
    $S2_IF" "  web-platform-build:
    needs: [push-dedupe, draft-light]
    $HEAVY_IF" gated G-S2ONLY-TOUCHED:web-platform-build
# the aggregator: draft-light in needs and env; its own `if:` must not gain the term (it would skip a required context)
mutate_yml y-agg-no-need "web-platform-build, encryption-posture, push-dedupe, draft-light]" "web-platform-build, encryption-posture, push-dedupe]" agg A-NEEDS
mutate_yml y-agg-no-env "          DRAFT_LIGHT: \${{ needs.draft-light.outputs.light }}
" "" agg A-ENV
mutate_yml y-agg-env-literal "          DRAFT_LIGHT: \${{ needs.draft-light.outputs.light }}" "          DRAFT_LIGHT: \${{ needs.draft-light.result }}" agg A-ENV
mutate_yml y-agg-if-term "    if: \${{ always() && $ELIDE_TAIL }}" "    if: \${{ always() && $ELIDE_TAIL && $LIGHT_CLAUSE }}" gated G-TEST-IF
# no required name moves: draft-light in the required set or the synthetic-check surface
for _f in scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json infra/github/ruleset-ci-required.tf; do
  MUT_RUN=$((MUT_RUN + 1))
  _mr="$SANDBOX/mut/root-$(basename "$_f")"; rm -rf "$_mr"; mkdir -p "$_mr"
  for _g in scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json infra/github/ruleset-ci-required.tf \
            .github/actions/bot-pr-with-synthetic-checks/action.yml apps/web-platform/server/inngest/functions/_cron-safe-commit.ts; do
    mkdir -p "$_mr/$(dirname "$_g")"; cp "$REPO_ROOT/$_g" "$_mr/$_g"
  done
  printf '\ndraft-light\n' >> "$_mr/$_f"
  if [ -n "$(names_clean "$_mr")" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "MUTANT required-names-$(basename "$_f"): draft-light appended to $_f went unnoticed"; fi
done

# ── Mutant accounting and measured counts ────────────────────────────────────
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ]; then pass
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught)"; fi
if [ "$MUT_RUN" -ge 79 ] && [ "$EQUIV_RUN" -eq 1 ] && [ "$EQUIV_OK" -eq 1 ]; then pass
else fail "MUTANT FLOOR: $MUT_RUN mutants and controls ran (floor 79), $EQUIV_OK of $EQUIV_RUN equivalent mutants confirmed (want 1 of 1)"; fi

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): a floor that increments the counter it guards shares a
# lifetime with the thing it is checking. This compares against a literal and exits directly.
#
# KEEP THESE TWO ASSIGNMENTS CONTIGUOUS (no comment between them or before the `if`):
# scripts/guard-vacuity-floor.test.sh binds a floor's variables by walking BACKWARD from the `if`.
_total=$((passes + fails))
_FLOOR=197
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-draft-light: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-draft-light: %d passed, %d failed (%d assertions; %d mutants caught of %d; %d battery rows; %d aggregator rows)\n' \
  "$passes" "$fails" "$_total" "$MUT_CAUGHT" "$MUT_RUN" "$CTRL_N" "$AGG_CTRL_N"
exit $(( ${#FAILURES[@]} > 0 ))
