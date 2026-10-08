#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 for #9727 (ADR-276 S1): the secret-scan `smoke-relevance` gate.
#
# WHAT THE GATE IS. `.github/workflows/secret-scan.yml` job `smoke-relevance` lists the PR's
# files through the pulls/files API and writes `smoke=false` only when the list is complete,
# current (the PR head did not move) AND touches nothing the ten `smoke-tests` cases execute,
# read or create. `smoke-tests` runs unless that output is the exact string `false`. It is a COST
# optimisation, not a control: the five required scanners still run on every PR. CODEOWNERS covers
# this suite and the workflow, but that review is advisory until the CI ruleset requires it.
#
# WHAT THIS SUITE PROVES. Not that the YAML mentions the right words, but that the step body,
# EXTRACTED from the workflow and EXECUTED under the shell GitHub Actions uses for `shell: bash`
# (`bash --noprofile --norc -eo pipefail`; the step pins `shell: bash`, checked below), yields the
# right verdict for each input class, and that the wrapper (job `if:`, `needs:`, outputs,
# permissions, env, the smoke-tests matrix) is what the design says.
#
#   * a named subject list, each member as a modification and as a rename SOURCE, plus prefix
#     rows, near-miss rows (must yield `false`) and a non-subject control;
#   * a derived sweep: EVERY tracked file, partitioned by an independent Python statement of the
#     intended subject set, must yield the matching verdict (catches a loosened SUBJECT_RE). The
#     partition is pinned to the `git ls-files` count (non-subject + subject + skipped), the subject
#     direction is checked PER FILE (grep -v over every subject file, so a narrowed alternative cannot
#     hide behind the chunk's any-match) and a deterministic sample is fed through the body one file at a time;
#   * a structural anchor: every tracked file or directory prefix that appears as a token in the
#     PARSED smoke-tests job (run bodies, uses, with, env) must match the body's SUBJECT_RE, with
#     a known-positive control and shape rows. There is NO exemption: the one operand that is only
#     quoted text (the runbook path in a ::warning:: message) is listed in SUBJECT_RE by exact path;
#   * the smoke-tests matrix case names must equal the case arms of the job's run script;
#   * every fetch failure shape fails OPEN (`smoke=true` with a reason): non-zero exit, page one
#     then failure, empty list, entry count differing from the event's `changed_files` in either
#     direction, the 3000-entry cap (>= 3000), a failed head fetch, a head that moved, a matcher error;
#   * mutation rows run against mutated COPIES of the body / workflow in mktemp dirs. A mutant is
#     CAUGHT only when this suite's own check returns its "assertion failed" verdict (rc 1) AND
#     the failure text names the expected effect. A mutant that merely crashes (rc 2, 126, 127, a
#     signal) is NOT caught: a crash proves nothing about the assertion.
#
# HARNESS ROWS. H1: stubs that always print one verdict must turn the shared row function red on
# the opposite class. Positive controls drive the verdict-owning helpers (assert_sc, report_rows,
# mutant_verdict, the shape compare, the symlink scan, the sweep floor, check_scn's crash class) once
# with an input that MUST fail, including a deliberately uncatchable mutant.
# The assertion-count floor is guarded by scripts/guard-vacuity-floor.test.sh, not re-tested here.
#
# THE gh SHIM validates the two exact endpoints (`repos/<GH_REPO>/pulls/<PR_NUMBER>/files?per_page=100`
# and `repos/<GH_REPO>/pulls/<PR_NUMBER>` with `--jq .head.sha`), whitelists the real flags used
# (`api`, `--paginate`, `--jq`), exits non-zero when GH_TOKEN is unset as real gh does, applies the
# passed --jq with real jq, serves page one only without --paginate, flushes page one before
# failing in page-then-fail mode, and logs every call.
#
# ACCEPTED LIMITS (recorded decisions, shape rows below expect 0 operands for each): the membership
# derivation only sees whole tokens that are tracked files or nested tracked directories. It cannot see a
# glob (`cat scripts/lint-*.sh`), a directory change followed by a bare name (`cd scripts && bash
# lint-workflows.sh`), a path composed from a variable (`d=scripts; bash $d/x.sh`) or a bare top-level
# directory word (`ls scripts`). The five required scanners still run on every PR; the cost of such a
# miss is a skipped smoke matrix on a PR that edits an input of a future step, caught by review of that step.
#
# PRE-MERGE LIMIT. The suite cannot prove GitHub's `needs`/status-function skip semantics; the
# `false` arm is exercised by the PR scratch canary and the first post-merge PR that touches no
# subject path (plan Phase 6, 7).
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
WF="$REPO_ROOT/.github/workflows/secret-scan.yml"
REQUIRED="$REPO_ROOT/scripts/required-checks.txt"
RULESET="$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json"

SANDBOX=$(mktemp -d "$TMPDIR/ss-smoke-gate.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

for _dep in python3 jq git grep sed cut awk; do
  command -v "$_dep" >/dev/null 2>&1 || { printf 'FAIL: %s is required\n' "$_dep" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step body (python3 -c "import yaml" failed)\n' >&2
  exit 2; }

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

# ── Expected literals (the design's reading of the wrapper) ──────────────────
IF_LITERAL="github.event_name == 'pull_request' && !cancelled() && (needs.smoke-relevance.result != 'success' || needs.smoke-relevance.outputs.smoke != 'false')"
R_SUBJ="subject path changed"
R_NOSUBJ="no subject path changed"
R_FETCH="file list fetch failed"
R_EMPTY="empty file list"
R_MISMATCH="file list does not match the event's changed_files"
R_CAP="at the file-list cap"
R_HEADFETCH="head fetch failed"
R_HEADMOVED="head moved"
R_MATCHER="matcher error rc=2"
HEAD_DEFAULT="headsha-synthetic-0001"
# Distinct operands membership derives from the PARSED smoke-tests job, re-derived from the live
# workflow on 2026-10-08: lint-fixture-content.mjs, rename-guard.sh, allowlist-diff.sh,
# .gitleaks.toml, the directory apps/web-platform/test/__synthesized__/ (the rename cases mkdir and
# git mv into it) and one runbook path named inside a ::warning:: message.
OPERAND_FLOOR=6
# The one derived operand that is only TEXT: the rename-laundering case names the runbook inside a
# ::warning:: message ("update knowledge-base/.../secret-scanning.md"); it is never executed or read.
# It is NOT exempted from the anchor: SUBJECT_RE lists it by exact path (over-inclusive, conservative).
RUNBOOK_PATH="knowledge-base/engineering/operations/secret-scanning.md"
RUNBOOK_ALT='|knowledge-base/engineering/operations/secret-scanning\.md'

# The named subject list: what the ten smoke cases execute, read or create (and implicit git inputs).
SUBJ=(
  ".github/workflows/secret-scan.yml"
  ".gitleaks.toml"
  ".gitleaksignore"
  "knowledge-base/engineering/operations/secret-scanning.md"
  "apps/web-platform/scripts/rename-guard.sh"
  "apps/web-platform/scripts/allowlist-diff.sh"
  "apps/web-platform/scripts/lint-fixture-content.mjs"
  "apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"
  ".gitignore"
  ".gitattributes"
  "apps/web-platform/.gitignore"
  "docs/sub/.gitattributes"
  "apps/web-platform/server/smoke/with-secret.ts"
  "apps/web-platform/test/__goldens__/smoke/x"
  "apps/web-platform/lib/safety/smoke/x"
  "smoke/x.txt"
  "apps/web-platform/test/__synthesized__/now-allowed.ts"
  "apps/web-platform/test/__synthesized__"
  "apps/web-platform/server/smoke"
  "smoke"
  "apps"
  "apps/web-platform"
  "apps/web-platform/test"
  "apps/web-platform/test/__goldens__"
  "apps/web-platform/server"
  "apps/web-platform/lib"
  "apps/web-platform/lib/safety"
  "gitleaks"
  "gitleaks.tgz"
  "gitleaks/x"
)

# ── Helper programs (written once into the sandbox) ──────────────────────────
mkdir -p "$SANDBOX/mut" "$SANDBOX/live" "$SANDBOX/shim" "$SANDBOX/wf" "$SANDBOX/sweep"

cat > "$SANDBOX/extract.py" <<'PY'
import sys, yaml
# the C loader parses the same safe subset ~10x faster; fall back to the pure-Python SafeLoader
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
wf, out = sys.argv[1], sys.argv[2]
try:
    d = yaml.load(open(wf).read(), Loader=LOADER)
    job = (d.get("jobs") or {}).get("smoke-relevance")
    steps = (job or {}).get("steps") or []
    runs = [s for s in steps if isinstance(s, dict) and "run" in s]
    if len(runs) != 1:
        sys.stderr.write("found %d run steps in job smoke-relevance (0 steps = job absent)\n" % len(runs))
        sys.exit(3)
    env = runs[0].get("env") or {}
    open(out + "/body.sh", "w").write(runs[0]["run"])
    open(out + "/env.tsv", "w").write("".join("%s\t%s\n" % (k, v) for k, v in env.items()))
except SystemExit:
    raise
except Exception as e:  # a crash must be distinguishable from "found 0"
    sys.stderr.write("extract.py crashed: %r\n" % (e,))
    sys.exit(2)
PY

cat > "$SANDBOX/wrapper.py" <<'PY'
import os, re, sys, yaml
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
wf, req = sys.argv[1], sys.argv[2]
try:
    tags = []
    jobs = yaml.load(open(wf), Loader=LOADER).get("jobs") or {}
    sr, st = jobs.get("smoke-relevance"), jobs.get("smoke-tests")

    def needs(j):
        n = (j or {}).get("needs", [])
        return [n] if isinstance(n, str) else list(n)

    if sr is None:
        tags.append("W-JOB-MISSING")
    if st is None:
        tags.append("W-SMOKE-MISSING")
    if st is not None:
        if st.get("if") != os.environ["EXP_SMOKE_IF"]:
            tags.append("W-IF")
        if needs(st) != ["smoke-relevance"]:
            tags.append("W-NEEDS")
        if st.get("continue-on-error"):
            tags.append("W-COE-SMOKE")
        m = (st.get("strategy") or {}).get("matrix")
        cases = m.get("case") if isinstance(m, dict) else None
        if not isinstance(cases, list) or len(cases) != 10 or len(set(cases)) != 10 or set(m) - {"case"}:
            tags.append("W-MATRIX")
        for s in st.get("steps") or []:
            if "if" in s:
                tags.append("W-ST-IF")
            if "continue-on-error" in s:
                tags.append("W-ST-COE")
        # matrix identity: the case names must equal the top-level arms of `case "${CASE}" in` in the
        # one step that takes CASE from the matrix (a renamed entry or arm is an "Unknown case" at run time)
        cs = [s for s in st.get("steps") or [] if isinstance(s.get("env"), dict) and "CASE" in s["env"]]
        if len(cs) != 1 or cs[0]["env"]["CASE"] != "${{ matrix.case }}" or 'case "${CASE}" in' not in cs[0].get("run", ""):
            tags.append("W-CASE-STEP")
        elif isinstance(cases, list):
            arms = re.findall(r"(?m)^  ([A-Za-z0-9_-]+)\)[ \t]*$", cs[0]["run"])
            if sorted(arms) != sorted(cases):
                tags.append("W-MATRIX-ARMS")
    for n, j in jobs.items():
        if n != "smoke-tests" and ("smoke-relevance" in needs(j) or "smoke-tests" in needs(j)):
            tags.append("W-NEEDS-OTHER:" + n)
    names = set()
    for line in open(req):
        line = line.rstrip("\n")
        if line.strip() and not line.lstrip().startswith("#"):
            names.add(line)
    req_jobs = [n for n, j in jobs.items() if (j or {}).get("name") in names]
    if len(req_jobs) < 5:
        tags.append("W-REQUIRED-COUNT")
    for n in req_jobs:
        if "smoke-relevance" in needs(jobs[n]) or "smoke-tests" in needs(jobs[n]):
            tags.append("W-REQUIRED-EDGE:" + n)
    if sr is not None:
        if sr.get("name") in names:
            tags.append("W-NOTREQ")
        if sr.get("if") != "github.event_name == 'pull_request'":
            tags.append("W-JOBIF")
        if sr.get("outputs") != {"smoke": "${{ steps.relevance.outputs.smoke }}"}:
            tags.append("W-OUTPUTS")
        if sr.get("permissions") != {"contents": "read", "pull-requests": "read"}:
            tags.append("W-PERM")
        if sr.get("continue-on-error"):
            tags.append("W-COE")
        steps = sr.get("steps") or []
        runs = [s for s in steps if "run" in s]
        if len(steps) != 1 or len(runs) != 1:
            tags.append("W-STEPS")
        else:
            if runs[0].get("id") != "relevance":
                tags.append("W-ID")
            if runs[0].get("shell") != "bash":
                tags.append("W-SHELL")
            if runs[0].get("continue-on-error"):
                tags.append("W-COE-STEP")
            if runs[0].get("env") != {
                "GH_TOKEN": "${{ github.token }}",
                "GH_REPO": "${{ github.repository }}",
                "PR_NUMBER": "${{ github.event.pull_request.number }}",
                "CHANGED_FILES": "${{ github.event.pull_request.changed_files }}",
                "HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
            }:
                tags.append("W-ENV")
    print("\n".join(tags))
except Exception as e:
    sys.stderr.write("wrapper.py crashed: %r\n" % (e,))
    sys.exit(2)
PY

# operands.py <workflow> <job> <tracked.z>: MEMBERSHIP derivation from the PARSED job (comments are
# gone). Every token of every run body, uses, with value and env value that is a tracked file, or a
# tracked directory prefix (a nested path), is an operand; directories print with a trailing slash.
# operands.py --shapes <cases.json> <tracked.z>: for each {kind, val} case build a one-step smoke-tests
# job, parse it, and print its operand count (one process for all shape rows).
cat > "$SANDBOX/operands.py" <<'PY'
import json, re, sys, yaml
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
shapes = sys.argv[1] == "--shapes"
tracked = set(x for x in open(sys.argv[3], "rb").read().decode("utf-8", "replace").split("\0") if x)
dirs = set()
for f in tracked:
    parts = f.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))
SPLIT = re.compile(r"""[\s'"`=<>;&|(){}$,:\[\]\\]+""")

def operands(j):
    vals = []
    def add_map(m):
        if isinstance(m, dict):
            vals.extend(v for v in m.values() if isinstance(v, str))
    add_map(j.get("env"))
    for s in j.get("steps") or []:
        if not isinstance(s, dict):
            continue
        for k in ("run", "uses", "working-directory"):
            if isinstance(s.get(k), str):
                vals.append(s[k])
        add_map(s.get("with"))
        add_map(s.get("env"))
    found = set()
    for v in vals:
        for tok in SPLIT.split(v):
            t = tok.rstrip(".,:;")
            while t.startswith("./"):
                t = t[2:]
            t = t.lstrip("/").rstrip("/")
            if not t:
                continue
            if t in tracked:
                found.add(t)
            elif t in dirs and "/" in t:
                found.add(t + "/")
    return sorted(found)

if shapes:
    for c in json.load(open(sys.argv[2])):
        kind, val = c["kind"], c["val"]
        if kind == "ycomment":
            text = "jobs:\n  smoke-tests:\n    runs-on: x\n    steps:\n      # " + val + "\n      - run: 'true'\n"
        else:
            step = {"run": val} if kind == "run" else {"run": "true", "env": {"GITLEAKS_CONFIG": val}} if kind == "env" else {"uses": val}
            text = yaml.safe_dump({"jobs": {"smoke-tests": {"runs-on": "x", "steps": [step]}}})
        print(len(operands(yaml.load(text, Loader=LOADER)["jobs"]["smoke-tests"])))
else:
    j = (yaml.load(open(sys.argv[1]), Loader=LOADER).get("jobs") or {})[sys.argv[2]]
    ops = operands(j)
    if ops:
        print("\n".join(ops))
PY

# sweep.py <tracked.z> <outdir>: partition EVERY tracked file with an INDEPENDENT statement of the
# intended subject set (procedural, deliberately not the regex) and write gh-shim pages, chunked
# below 2000 entries so the 3000 cap is never reached. Index lines: <kind> <dir> <count>.
cat > "$SANDBOX/sweep.py" <<'PY'
import json, os, sys
raw, out = sys.argv[1], sys.argv[2]
EXACT = {".github/workflows/secret-scan.yml", ".gitleaks.toml", ".gitleaksignore", "gitleaks", "gitleaks.tgz",
         "knowledge-base/engineering/operations/secret-scanning.md"}
ANCESTORS = {"apps", "apps/web-platform", "apps/web-platform/test", "apps/web-platform/test/__goldens__",
             "apps/web-platform/server", "apps/web-platform/lib", "apps/web-platform/lib/safety"}
SYNTH = "apps/web-platform/test/__synthesized__"
def is_subject(p):
    parts = p.split("/")
    if p in EXACT or p in ANCESTORS:
        return True
    if p.startswith("apps/web-platform/scripts/"):
        return True
    if p == SYNTH or p.startswith(SYNTH + "/"):
        return True
    if parts[0] in ("gitleaks", "gitleaks.tgz"):
        return True
    if parts[-1] in (".gitignore", ".gitattributes"):
        return True
    return "smoke" in parts
subj, non, skipped = [], [], 0
for b in open(raw, "rb").read().split(b"\0"):
    if not b:
        continue
    try:
        p = b.decode("utf-8")
    except UnicodeDecodeError:
        skipped += 1
        continue
    if "\n" in p:
        skipped += 1
        continue
    (subj if is_subject(p) else non).append(p)
# one subject name per line (names containing a newline were skipped above): the per-file check input
open(os.path.join(out, "subject-names.txt"), "w").write("".join(p + "\n" for p in subj))
n = 0
for kind, names in (("subj", subj), ("non", non)):
    for ci in range(0, len(names), 2000):
        chunk = names[ci:ci + 2000]
        d = os.path.join(out, "%s-%03d" % (kind, ci // 2000))
        os.makedirs(d)
        for pi in range(0, len(chunk), 100):
            page = [{"filename": f, "status": "modified"} for f in chunk[pi:pi + 100]]
            json.dump(page, open(os.path.join(d, "page-%03d.json" % (pi // 100 + 1)), "w"))
        print(kind, d, len(chunk))
sys.stderr.write("skipped %d\n" % skipped)
PY

# reqctx.py <required-checks.txt> <ruleset json>: print every required context naming smoke
cat > "$SANDBOX/reqctx.py" <<'PY'
import json, re, sys
txt, js = sys.argv[1], sys.argv[2]
try:
    names = []
    t = [l.strip() for l in open(txt) if l.strip() and not l.lstrip().startswith("#")]
    d = json.load(open(js))
    if not isinstance(d, list):
        raise ValueError("ruleset json is not a list")
    j = [e["context"] for e in d if isinstance(e, dict) and isinstance(e.get("context"), str)]
    if len(t) < 5 or len(j) < 5:
        raise ValueError("fewer than 5 required contexts read (txt=%d json=%d)" % (len(t), len(j)))
    print("\n".join(n for n in t + j if re.search("smoke", n, re.I)))
except Exception as e:
    sys.stderr.write("reqctx.py crashed: %r\n" % (e,))
    sys.exit(2)
PY

cat > "$SANDBOX/mutate.py" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("replace target matched %d times, expected exactly 1: %r\n" % (n, old[:80]))
    sys.exit(3)
if old == new:
    sys.stderr.write("replacement does not change the text\n")
    sys.exit(3)
open(path, "w").write(s.replace(old, new))
PY

# The gh shim. Validates the two exact endpoints, whitelists the real flags, mirrors real gh's exit
# when GH_TOKEN is unset, applies --jq with real jq, logs every call.
cat > "$SANDBOX/shim/gh" <<'SHIM'
#!/usr/bin/env bash
set -u
log="${SHIM_LOG:?}"
{ printf 'ARGV:'; printf ' [%s]' "$@"; printf '\n'; } >> "$log"
[ "${1:-}" = api ] || { echo "gh shim: unsupported subcommand '${1:-}'" >&2; exit 64; }
shift
paginate=0; jqexpr=""; have_jq=0; endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) shift; [ $# -gt 0 ] || { echo "gh shim: --jq needs a value" >&2; exit 64; }; jqexpr="$1"; have_jq=1 ;;
    -*) echo "gh shim: unknown flag '$1' (real gh would not accept an invented flag)" >&2; exit 64 ;;
    *) [ -z "$endpoint" ] || { echo "gh shim: two endpoints" >&2; exit 64; }; endpoint="$1" ;;
  esac
  shift
done
[ -n "${GH_TOKEN:-}" ] || {
  echo "gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable." >&2; exit 4; }
want_head="repos/${GH_REPO:-?}/pulls/${PR_NUMBER:-?}"
want="$want_head/files?per_page=100"
if [ "$endpoint" = "$want_head" ]; then
  [ "$have_jq" = 1 ] && [ "$jqexpr" = ".head.sha" ] || { echo "gh shim: the head endpoint is only served with --jq .head.sha" >&2; exit 66; }
  [ "$paginate" = 0 ] || { echo "gh shim: the head endpoint is not paginated" >&2; exit 66; }
  if [ "${SHIM_HEAD_MODE:-ok}" = fail ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  jq -r "$jqexpr" "${SHIM_HEAD_FILE:?}"; exit $?
fi
[ "$endpoint" = "$want" ] || { echo "gh shim: endpoint '$endpoint' != '$want'" >&2; exit 65; }
[ "$have_jq" = 1 ] || { echo "gh shim: this suite's gate always passes --jq" >&2; exit 66; }
mode="${SHIM_MODE:-ok}"
if [ "$mode" = fail ]; then echo "gh: HTTP 502" >&2; exit 1; fi
shopt -s nullglob
pages=( "${SHIM_PAGES:?}"/page-*.json )
[ "${#pages[@]}" -gt 0 ] || { echo "gh shim: no pages configured" >&2; exit 67; }
if [ "$paginate" = 0 ]; then pages=( "${pages[0]}" ); fi
i=0
for p in "${pages[@]}"; do
  i=$((i + 1))
  jq -r "$jqexpr" "$p" || exit $?
  if [ "$mode" = page-then-fail ] && [ "$i" = 1 ]; then echo "gh: HTTP 502 on page 2" >&2; exit 1; fi
done
exit 0
SHIM
chmod +x "$SANDBOX/shim/gh"
printf '[]\n' > "$SANDBOX/shim-direct-page.json"
printf '{"head":{"sha":"%s"}}\n' "$HEAD_DEFAULT" > "$SANDBOX/shim-direct-head.json"

git -C "$REPO_ROOT" ls-files -z > "$SANDBOX/tracked.z" || {
  printf 'FAIL: git ls-files failed\n' >&2; exit 2; }

# ── Guard 1 - extraction / dispatch ──────────────────────────────────────────
# A harness that extracts 0 steps cannot tell "the body is clean" from "the body was never
# found", so 0 extracted steps must FAIL (and the run cannot continue without a body).
if ! python3 "$SANDBOX/extract.py" "$WF" "$SANDBOX/live" 2>"$SANDBOX/x.err"; then
  fail "G1.0 extraction: could not extract the smoke-relevance step body / env from secret-scan.yml: $(cat "$SANDBOX/x.err")"
  printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" $((passes + fails))
  exit 1
fi
pass
BODY="$SANDBOX/live/body.sh"
ENVFILE="$SANDBOX/live/env.tsv"

if [ -s "$BODY" ] && bash -n "$BODY" 2>"$SANDBOX/n.err"; then pass; else fail "G1.1 the extracted body is empty or does not parse (bash -n): $(cat "$SANDBOX/n.err" 2>/dev/null)"; fi

RE_VAL=$(sed -n "s/^[[:space:]]*SUBJECT_RE='\\(.*\\)'[[:space:]]*\$/\\1/p" "$BODY")
if [ -n "$RE_VAL" ] && [ "$(grep -c '' <<<"$RE_VAL")" -eq 1 ]; then pass; else fail "G1.2 the body must assign SUBJECT_RE on exactly one bare line (got: $RE_VAL)"; fi
RE_ASSIGN="SUBJECT_RE='$RE_VAL'"

# ── Scenario machinery ───────────────────────────────────────────────────────
SCN=""; RC=0; WHY=""; CALLS=0; GOUT_N=0
SC_MODE=ok; SC_CHANGED=0; SC_NOTOKEN=0; SC_SUMMARY=""; SC_EV=""; SC_ER=""
SC_HEAD_MODE=ok; SC_HEAD_EVENT="$HEAD_DEFAULT"; SC_HEAD_CUR="$HEAD_DEFAULT"
SC_NAMES=(); X_EV=""; X_ER=""

scn_new() {
  SCN=$(mktemp -d "$SANDBOX/scn.XXXXXX") || { printf 'FAIL: mktemp scn\n' >&2; exit 2; }
  mkdir "$SCN/pages"; : > "$SCN/calls.log"
  SC_MODE=ok; SC_CHANGED=0; SC_NOTOKEN=0; SC_SUMMARY=""
  SC_HEAD_MODE=ok; SC_HEAD_EVENT="$HEAD_DEFAULT"; SC_HEAD_CUR="$HEAD_DEFAULT"
}

# pg <page-number> [name | old=>new]...   (writes a pulls/files page; "old=>new" is a rename)
pg() {
  local n
  n=$(printf '%03d' "$1"); shift
  jq -n '$ARGS.positional | map(if contains("=>") then (split("=>")) as $p
         | {filename: $p[1], previous_filename: $p[0], status: "renamed"}
         else {filename: ., status: "modified"} end)' --args "$@" > "$SCN/pages/page-$n.json"
}

# exec_scn <body>: run the body under the Actions default shell with the workflow's own env keys.
exec_scn() {
  local body="$1" k v val
  local -a envargs=()
  printf '{"head":{"sha":"%s"}}\n' "$SC_HEAD_CUR" > "$SCN/head.json"
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    case "$v" in
      '${{ github.token }}') val="tok-synthetic" ;;
      '${{ github.repository }}') val="example-org/example-repo" ;;
      '${{ github.event.pull_request.number }}') val="4242" ;;
      '${{ github.event.pull_request.changed_files }}') val="$SC_CHANGED" ;;
      '${{ github.event.pull_request.head.sha }}') val="$SC_HEAD_EVENT" ;;
      *) val="UNMAPPED-EXPRESSION" ;;
    esac
    if [ "$k" = GH_TOKEN ] && [ "$SC_NOTOKEN" = 1 ]; then continue; fi
    envargs+=("$k=$val")
  done < "$ENVFILE"
  ( cd "$SCN" && env -i PATH="$SANDBOX/shim:$PATH" HOME="$SCN" \
      GITHUB_OUTPUT="$SCN/gh_output" GITHUB_STEP_SUMMARY="${SC_SUMMARY:-$SCN/summary}" \
      SHIM_LOG="$SCN/calls.log" SHIM_PAGES="$SCN/pages" SHIM_MODE="$SC_MODE" \
      SHIM_HEAD_FILE="$SCN/head.json" SHIM_HEAD_MODE="$SC_HEAD_MODE" \
      "${envargs[@]}" bash --noprofile --norc -eo pipefail "$body" ) >"$SCN/stdout" 2>"$SCN/stderr" </dev/null
  RC=$?
  CALLS=$(grep -c '^ARGV:' "$SCN/calls.log" || true)
  GOUT_N=0
  if [ -f "$SCN/gh_output" ]; then GOUT_N=$(grep -c '' "$SCN/gh_output" || true); fi
}

# check_scn <expected verdict: true|false|notfalse> <expected reason>
# returns 0 = as expected, 1 = assertion failed (see WHY), 2 = the body CRASHED (never "caught").
# gh is called once when the body stops at the file list (fetch, empty, count, cap) and twice
# (file list, then the head lookup) when it gets further.
check_scn() {
  local ev="$1" er="$2" bad=0 got_v="" got_r="" line colon_n=0 gout exp_calls=2
  WHY=""
  case "$er" in "$R_FETCH"|"$R_EMPTY"|"$R_MISMATCH"|"$R_CAP") exp_calls=1 ;; esac
  if [ "$RC" -eq 2 ] || [ "$RC" -ge 126 ]; then
    WHY="CRASH rc=$RC stderr=$(head -c 200 "$SCN/stderr")"; return 2
  fi
  while IFS= read -r line; do
    case "$line" in
      ::*)
        colon_n=$((colon_n + 1))
        if [[ "$line" =~ ^::notice::smoke-relevance:\ smoke=(true|false)\ \((.*)\)$ ]]; then
          got_v="${BASH_REMATCH[1]}"; got_r="${BASH_REMATCH[2]}"
        fi ;;
    esac
  done < "$SCN/stdout"
  gout=""
  if [ -f "$SCN/gh_output" ]; then gout=$(tr '\n' '|' < "$SCN/gh_output"); fi
  WHY="verdict=$got_v reason='$got_r' out='$gout' outlines=$GOUT_N colonlines=$colon_n rc=$RC calls=$CALLS"
  if [ "$CALLS" -ne "$exp_calls" ]; then bad=1; WHY="$WHY [CALLS: gh was called $CALLS times, expected exactly $exp_calls]"; fi
  if [ "$ev" = notfalse ]; then
    # summary write failed: the output must NOT already carry smoke=false (the matrix must run)
    if [ -f "$SCN/gh_output" ] && grep -qx 'smoke=false' "$SCN/gh_output"; then
      bad=1; WHY="$WHY [NOTFALSE: smoke=false was written although the summary write failed]"
    fi
    return $bad
  fi
  if [ "$RC" -ne 0 ]; then bad=1; WHY="$WHY [RC: body exited $RC]"; fi
  if [ "$GOUT_N" -ne 1 ] || [ "$gout" != "smoke=$ev|" ]; then bad=1; WHY="$WHY [OUTPUT: expected exactly one line smoke=$ev]"; fi
  if [ "$colon_n" -ne 1 ]; then bad=1; WHY="$WHY [STDOUT: expected exactly one :: line]"; fi
  if [ "$got_v" != "$ev" ]; then bad=1; WHY="$WHY [VERDICT: expected $ev]"; fi
  if [ "$got_r" != "$er" ]; then bad=1; WHY="$WHY [REASON: expected '$er']"; fi
  return $bad
}

# ── Scenario functions: each runs the body passed as $1 and sets SC_EV / SC_ER ───
set_names() { X_EV="$1"; X_ER="$2"; shift 2; SC_NAMES=("$@"); }
sc_names() { scn_new; SC_CHANGED=${#SC_NAMES[@]}; pg 1 "${SC_NAMES[@]}"; exec_scn "$1"; SC_EV="$X_EV"; SC_ER="$X_ER"; }
sc_fail() { scn_new; SC_MODE=fail; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
sc_notoken() { scn_new; SC_NOTOKEN=1; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
# page one has NO subject file and matches CHANGED_FILES; the subject file is only on failed page two
sc_pthf() { scn_new; SC_MODE=page-then-fail; SC_CHANGED=2; pg 1 docs/a.md docs/b.md; pg 2 .gitleaks.toml; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
sc_twopage() { scn_new; SC_CHANGED=3; pg 1 docs/a.md knowledge-base/b.md; pg 2 .gitleaks.toml; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_twopage_clean() { scn_new; SC_CHANGED=2; pg 1 knowledge-base/a.md; pg 2 plugins/b.ts; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# an empty list with changed_files=0 passes the count check: the empty guard is what keeps this at smoke=true
sc_empty() { scn_new; SC_CHANGED=0; pg 1; exec_scn "$1"; SC_EV=true; SC_ER="$R_EMPTY"; }
sc_short() { scn_new; SC_CHANGED=3; pg 1 docs/a.md docs/b.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
sc_long() { scn_new; SC_CHANGED=2; pg 1 docs/a.md docs/b.md docs/c.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
sc_blank() { scn_new; SC_CHANGED=""; pg 1 docs/a.md docs/b.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
gen_pages_n() { # <entries>: that many non-subject entries in pages of 100
  local p n="$1" full=$(( $1 / 100 )) rest=$(( $1 % 100 ))
  for p in $(seq 1 "$full"); do
    jq -n --argjson p "$p" '[range(100) | {filename: ("docs/gen/\($p)/f\(.).md"), status: "added"}]' \
      > "$SCN/pages/page-$(printf '%03d' "$p").json"; done
  if [ "$rest" -gt 0 ]; then
    jq -n --argjson p $((full + 1)) --argjson r "$rest" '[range($r) | {filename: ("docs/gen/\($p)/f\(.).md"), status: "added"}]' \
      > "$SCN/pages/page-$(printf '%03d' $((full + 1))).json"
  fi
}
gen_pages_3000() { gen_pages_n 3000; }
sc_cap() { scn_new; SC_CHANGED=3050; gen_pages_3000; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
# 2999 entries matching the event with no subject path: below the cap, so it is trusted (smoke=false)
sc_cap_below() { scn_new; SC_CHANGED=2999; gen_pages_n 2999; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# GitHub caps the list at 3000: a list of exactly 3000 matching the event may be truncated, so it fails open
sc_cap_exact() { scn_new; SC_CHANGED=3000; gen_pages_3000; exec_scn "$1"; SC_EV=true; SC_ER="$R_CAP"; }
sc_rename_out() { scn_new; SC_CHANGED=1; pg 1 ".gitleaks.toml=>docs/x.md"; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_rename_in() { scn_new; SC_CHANGED=1; pg 1 "docs/x.md=>.gitleaks.toml"; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_rename_clean() { scn_new; SC_CHANGED=1; pg 1 "docs/old.md=>docs/new.md"; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# the summary write fails (GITHUB_STEP_SUMMARY is a directory): the output must not say false
sc_summary_fail() { scn_new; mkdir "$SCN/sumdir"; SC_SUMMARY="$SCN/sumdir"; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=notfalse; SC_ER=""; }
sc_hostile() { scn_new; SC_CHANGED=2; pg 1 $'docs/a\n::error::x' $'docs/b\nsmoke=false'; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# a stray line (no F/P framing) that LOOKS like a subject path is not an entry: the real name is docs/a<newline>smoke/x
sc_hostile_stray() { scn_new; SC_CHANGED=1; pg 1 $'docs/a\nsmoke/x'; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# a stray line that merely STARTS with F (not an F<TAB> entry) must not be counted as an entry
sc_hostile_fstray() { scn_new; SC_CHANGED=1; pg 1 $'docs/a\nFoo'; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# a TAB inside a filename is legal in git: the name is everything after the FIRST tab (cut -f2-, not -f2)
sc_tab_name() { scn_new; SC_CHANGED=1; pg 1 $'docs/a\t/smoke/b'; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
# a name that forges an extra F<TAB> entry must change the count and fail OPEN
sc_hostile_forge() { scn_new; SC_CHANGED=1; pg 1 $'docs/a\nF\tdocs/forged'; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
# the PR head moved since the event: the list may describe another commit
sc_head_moved() { scn_new; SC_CHANGED=1; pg 1 docs/a.md; SC_HEAD_CUR="headsha-synthetic-0002"; exec_scn "$1"; SC_EV=true; SC_ER="$R_HEADMOVED"; }
sc_head_fetch() { scn_new; SC_CHANGED=1; pg 1 docs/a.md; SC_HEAD_MODE=fail; exec_scn "$1"; SC_EV=true; SC_ER="$R_HEADFETCH"; }
sc_head_match() { scn_new; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# an event without a head sha cannot be compared: both sides empty must not read as "matches"
sc_head_empty() { scn_new; SC_CHANGED=1; pg 1 docs/a.md; SC_HEAD_EVENT=""; SC_HEAD_CUR=""; exec_scn "$1"; SC_EV=true; SC_ER="$R_HEADMOVED"; }

assert_sc() { # <label> <scenario fn> <body>
  local rc
  "$2" "$3"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  if [ "$rc" -eq 0 ]; then pass; else fail "$1: $WHY"; fi
}

MUT_RUN=0
MUT_CAUGHT=0
# A mutant counts as caught ONLY on the suite's own assertion verdict (check rc 1) whose WHY
# names the expected effect; a crash (rc 2) or a mutant whose effect is not the expected one fails.
mutant_verdict() { # <label> <check rc> <expected WHY substring>
  MUT_RUN=$((MUT_RUN + 1))
  if [ "$2" -eq 1 ] && [[ "$WHY" == *"$3"* ]]; then
    MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else
    fail "MUTANT NOT CAUGHT: $1 (check rc=$2, expected WHY to contain [$3], got: $WHY)"
  fi
}
mutant_sc() { # <label> <scenario fn> <mutant body> <expected WHY substring>
  local rc
  "$2" "$3"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  mutant_verdict "$1" "$rc" "$4"
}

# land <name> <src> <old> <new> [<old> <new>]...: copy src and apply EXACT-ONCE replacements.
LANDED=""
land() {
  local name="$1" src="$2"
  shift 2
  LANDED="$SANDBOX/mut/$name"
  cp "$src" "$LANDED"
  while [ $# -ge 2 ]; do
    if ! python3 "$SANDBOX/mutate.py" "$LANDED" "$1" "$2" 2>"$SANDBOX/mut.err"; then
      fail "mutation landing: $name: $(cat "$SANDBOX/mut.err")"; return 1
    fi
    shift 2
  done
  if cmp -s "$src" "$LANDED"; then fail "mutation landing: $name left the text unchanged"; return 1; fi
  return 0
}

# ── The shared row function (named list, prefix rows, near-misses, control) ───
ROW_ID=(); ROW_RC=(); ROW_WHY=()
row() { # <id> <ev> <er> <body> <names...>
  local id="$1" ev="$2" er="$3" body="$4" rc
  shift 4
  set_names "$ev" "$er" "$@"
  sc_names "$body"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  ROW_ID+=("$id"); ROW_RC+=("$rc"); ROW_WHY+=("$WHY")
}
# Rename-INTO a subject path is covered by sc_rename_in (and its P-only mutant below): the body treats
# an entry's F and P names identically, so a per-member rename-destination row adds nothing.
run_rows() { # <body> [quick]: quick = modification rows + control only
  local body="$1" s
  ROW_ID=(); ROW_RC=(); ROW_WHY=()
  for s in "${SUBJ[@]}"; do
    row "mod:$s" true "$R_SUBJ" "$body" "$s"
    if [ "${2:-}" != quick ]; then
      row "rename-source:$s" true "$R_SUBJ" "$body" "$s=>docs/moved-away.md"
    fi
  done
  if [ "${2:-}" != quick ]; then
    row "prefix-new-helper" true "$R_SUBJ" "$body" apps/web-platform/scripts/new-helper.mjs
    row "prefix-nested" true "$R_SUBJ" "$body" apps/web-platform/scripts/lib/x.mjs
    row "prefix-synthesized-nested" true "$R_SUBJ" "$body" apps/web-platform/test/__synthesized__/sub/y.ts
    row "near-miss:scripts-extra" false "$R_NOSUBJ" "$body" apps/web-platform/scripts-extra/x
    row "near-miss:.gitleaks.toml.bak" false "$R_NOSUBJ" "$body" .gitleaks.toml.bak
    row "near-miss:secret-scan.yml.bak" false "$R_NOSUBJ" "$body" .github/workflows/secret-scan.yml.bak
    row "near-miss:foo.gitignore" false "$R_NOSUBJ" "$body" docs/foo.gitignore
    row "near-miss:.gitignored" false "$R_NOSUBJ" "$body" docs/.gitignored
    row "near-miss:smoke.md" false "$R_NOSUBJ" "$body" docs/smoke.md
    row "near-miss:smokey/" false "$R_NOSUBJ" "$body" smokey/x.ts
    row "near-miss:xsmoke" false "$R_NOSUBJ" "$body" docs/xsmoke
    row "near-miss:docs/.gitleaks.toml" false "$R_NOSUBJ" "$body" docs/.gitleaks.toml
    row "near-miss:x/.github/workflows/secret-scan.yml" false "$R_NOSUBJ" "$body" x/.github/workflows/secret-scan.yml
    row "near-miss:docs/.gitleaksignore" false "$R_NOSUBJ" "$body" docs/.gitleaksignore
    row "near-miss:__synthesized__x" false "$R_NOSUBJ" "$body" apps/web-platform/test/__synthesized__x/y.ts
    row "near-miss:test/other.ts" false "$R_NOSUBJ" "$body" apps/web-platform/test/other.ts
    row "near-miss:__goldens__/x.snap" false "$R_NOSUBJ" "$body" apps/web-platform/test/__goldens__/x.snap
    row "near-miss:server/x.ts" false "$R_NOSUBJ" "$body" apps/web-platform/server/x.ts
    row "near-miss:lib/safety/x.ts" false "$R_NOSUBJ" "$body" apps/web-platform/lib/safety/x.ts
    row "near-miss:apps/foo" false "$R_NOSUBJ" "$body" apps/foo
    row "near-miss:gitleaks-extra" false "$R_NOSUBJ" "$body" gitleaks-extra
    row "near-miss:docs/gitleaks" false "$R_NOSUBJ" "$body" docs/gitleaks
    row "near-miss:gitleaks.tgz.bak" false "$R_NOSUBJ" "$body" gitleaks.tgz.bak
    row "near-miss:runbook.md.bak" false "$R_NOSUBJ" "$body" knowledge-base/engineering/operations/secret-scanning.md.bak
    row "near-miss:runbook-prefixed" false "$R_NOSUBJ" "$body" docs/knowledge-base/engineering/operations/secret-scanning.md
    row "near-miss:runbook-dot-unescaped" false "$R_NOSUBJ" "$body" knowledge-base/engineering/operations/secret-scanningXmd
    row "near-miss:runbook-sibling" false "$R_NOSUBJ" "$body" knowledge-base/engineering/operations/other-runbook.md
  fi
  row "control:non-subject" false "$R_NOSUBJ" "$body" knowledge-base/x.md plugins/y.ts
}
report_rows() { # <label prefix>
  local i
  for i in "${!ROW_ID[@]}"; do
    if [ "${ROW_RC[$i]}" -eq 0 ]; then pass; else fail "$1 ${ROW_ID[$i]}: ${ROW_WHY[$i]}"; fi
  done
}
row_rc_of() { # <id> -> prints the rc recorded for that row id
  local i
  for i in "${!ROW_ID[@]}"; do
    if [ "${ROW_ID[$i]}" = "$1" ]; then printf '%s' "${ROW_RC[$i]}"; return 0; fi
  done
  printf 'missing'
}

# ── Shim self-tests: the shim must reject invented flags, wrong endpoints, a missing token ──
shim_direct() { # <ENV=val...> gh <args...>
  ( env -i PATH="$SANDBOX/shim:$PATH" GH_TOKEN=t GH_REPO=o/r PR_NUMBER=7 \
      SHIM_LOG="$SANDBOX/shim-direct.log" SHIM_PAGES="$SANDBOX/shim-direct-pages" SHIM_MODE=ok \
      SHIM_HEAD_FILE="$SANDBOX/shim-direct-head.json" "$@" ) >/dev/null 2>&1
}
mkdir -p "$SANDBOX/shim-direct-pages"; cp "$SANDBOX/shim-direct-page.json" "$SANDBOX/shim-direct-pages/page-001.json"
shim_direct gh api --paginate "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "SHIM: the exact endpoint with whitelisted flags must succeed (rc=$_r)"; fi
shim_direct gh api -f a=b "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 64 ]; then pass; else fail "SHIM: an invented flag (-f) must exit 64 like a rejected real flag (rc=$_r)"; fi
shim_direct gh api "repos/o/r/pulls/7/files" --jq '.[]'; _r=$?
if [ "$_r" -eq 65 ]; then pass; else fail "SHIM: a different endpoint must exit 65 (rc=$_r)"; fi
shim_direct GH_TOKEN= gh api "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 4 ]; then pass; else fail "SHIM: an unset GH_TOKEN must exit non-zero (4) as real gh does (rc=$_r)"; fi
shim_direct gh api "repos/o/r/pulls/7" --jq .head.sha; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "SHIM: the head endpoint with --jq .head.sha must succeed (rc=$_r)"; fi
shim_direct gh api "repos/o/r/pulls/7" --jq .head; _r=$?
if [ "$_r" -eq 66 ]; then pass; else fail "SHIM: the head endpoint with any other --jq must exit 66 (rc=$_r)"; fi
shim_direct gh api --paginate "repos/o/r/pulls/7" --jq .head.sha; _r=$?
if [ "$_r" -eq 66 ]; then pass; else fail "SHIM: the head endpoint is not paginated, --paginate must exit 66 (rc=$_r)"; fi
shim_direct SHIM_HEAD_MODE=fail gh api "repos/o/r/pulls/7" --jq .head.sha; _r=$?
if [ "$_r" -eq 1 ]; then pass; else fail "SHIM: SHIM_HEAD_MODE=fail must exit 1 (rc=$_r)"; fi

# ── Guard 1 rows: named list, prefix rows, near-misses, control (live body) ──
run_rows "$BODY"
report_rows "G1"
_N_ROWS=${#ROW_ID[@]}

# ── Fetch-failure shapes and list integrity (live body) ──────────────────────
assert_sc "G1 fetch failure fails open" sc_fail "$BODY"
assert_sc "G1 missing GH_TOKEN fails open" sc_notoken "$BODY"
assert_sc "G1 page-then-failure (subject file only on failed page two) fails open" sc_pthf "$BODY"
assert_sc "G1 must-PASS: two-page list, subject on page two" sc_twopage "$BODY"
assert_sc "G1 must-PASS: two-page list with no subject path" sc_twopage_clean "$BODY"
assert_sc "G1 empty list (changed_files=0) fails open" sc_empty "$BODY"
assert_sc "G1 list shorter than changed_files fails open" sc_short "$BODY"
assert_sc "G1 list longer than changed_files fails open" sc_long "$BODY"
assert_sc "G1 blank CHANGED_FILES fails open" sc_blank "$BODY"
assert_sc "G1 3000-entry cap (list 3000, event 3050) fails open" sc_cap "$BODY"
assert_sc "G1 exactly 3000 entries matching the event (possibly truncated) fails open" sc_cap_exact "$BODY"
assert_sc "G1 rename out of a subject path" sc_rename_out "$BODY"
assert_sc "G1 rename into a subject path" sc_rename_in "$BODY"
assert_sc "G1 must-PASS: rename between non-subject paths" sc_rename_clean "$BODY"
assert_sc "G1 summary write failure leaves no smoke=false" sc_summary_fail "$BODY"
assert_sc "G1 hostile names: one smoke= line, no injected :: line" sc_hostile "$BODY"
assert_sc "G1 hostile name with a stray subject-looking line is not an entry" sc_hostile_stray "$BODY"
assert_sc "G1 hostile name forging an F entry changes the count and fails open" sc_hostile_forge "$BODY"
assert_sc "G1 stray line starting with F (not an F<TAB> entry) is not counted" sc_hostile_fstray "$BODY"
assert_sc "G1 a TAB inside a subject filename is kept whole (docs/a<TAB>/smoke/b)" sc_tab_name "$BODY"
assert_sc "G1 2999 entries matching the event, no subject path: trusted, below the cap" sc_cap_below "$BODY"
assert_sc "G1 PR head moved since the event fails open" sc_head_moved "$BODY"
assert_sc "G1 head lookup failure fails open" sc_head_fetch "$BODY"
assert_sc "G1 must-PASS: head matches the event, no subject path" sc_head_match "$BODY"
assert_sc "G1 empty head on both sides fails open" sc_head_empty "$BODY"

# matcher error: SUBJECT_RE replaced by "(" is an INPUT to the live arm (grep rc 2), not a mutant
BODY_BADRE=""
if land S-badre "$BODY" "$RE_ASSIGN" "SUBJECT_RE='('"; then
  BODY_BADRE="$LANDED"
  set_names true "$R_MATCHER" docs/a.md
  assert_sc "G1 matcher error (SUBJECT_RE replaced by '(') fails open" sc_names "$BODY_BADRE"
fi

# ── Derived sweep: every tracked file against an independent statement of the subject set ────
# Non-subject tracked files (any chunk) must yield false; subject tracked files must yield true.
# Names containing a newline or invalid UTF-8 cannot be framed and are skipped (counted below).
python3 "$SANDBOX/sweep.py" "$SANDBOX/tracked.z" "$SANDBOX/sweep" > "$SANDBOX/sweep.index" 2>"$SANDBOX/sweep.err" \
  || fail "SWEEP could not partition the tracked files: $(cat "$SANDBOX/sweep.err")"
SW_SEEN=0
sweep_run() { # <body>: 0 = every chunk as expected, else the failing check's rc with WHY set; SW_SEEN = files fed
  local kind d n rc=0
  SW_SEEN=0
  while read -r kind d n; do
    scn_new; cp "$d"/page-*.json "$SCN/pages/"; SC_CHANGED=$n
    exec_scn "$1"
    if [ "$kind" = non ]; then check_scn false "$R_NOSUBJ"; else check_scn true "$R_SUBJ"; fi; rc=$?
    if [ "$rc" -ne 0 ]; then WHY="sweep $kind chunk ${d##*/} ($n files): $WHY"; return "$rc"; fi
    SW_SEEN=$((SW_SEEN + n))
  done < "$SANDBOX/sweep.index"
  WHY=""; return 0
}
# sweep_subject_each <body> <re>: the subject direction PER FILE. (1) every subject file must match the
# regex (grep -v over the whole list: a narrowed alternative cannot hide behind a chunk's any-match);
# (2) a deterministic sample of at least 25 subject files (every 4th, sorted) is fed through the BODY one
# file at a time. Returns 0, or 1 with WHY naming the first offender.
sweep_subject_each() {
  local names="$SANDBOX/sweep/subject-names.txt" miss f i=0 fed=0
  WHY=""
  miss=$(grep -vE "$2" "$names" | head -3 | tr '\n' ' ')
  if [ -n "$miss" ]; then WHY="SWEEP-SUBJECT: tracked subject file(s) the regex does not match: $miss"; return 1; fi
  while IFS= read -r f; do
    i=$((i + 1))
    [ $((i % 4)) -eq 1 ] || continue
    scn_new; SC_CHANGED=1; pg 1 "$f"; exec_scn "$1"; fed=$((fed + 1))
    check_scn true "$R_SUBJ" || { WHY="SWEEP-SUBJECT: $f fed alone: $WHY"; return 1; }
  done < <(LC_ALL=C sort "$names")
  SW_FED=$fed
  return 0
}
SW_FED=0
sweep_floor_ok() { [ "$1" -ge 1000 ] && [ "$2" -ge 3 ]; } # <non-subject count> <subject count>
_sw_non=$(awk '$1=="non" {s+=$3} END {print s+0}' "$SANDBOX/sweep.index")
_sw_subj=$(awk '$1=="subj" {s+=$3} END {print s+0}' "$SANDBOX/sweep.index")
_sw_skipped=$(sed -n 's/^skipped \([0-9][0-9]*\)$/\1/p' "$SANDBOX/sweep.err")
# the entry count of git's own listing, derived without the partitioner (one NUL ends each entry)
_ls_n=$(tr -cd '\0' < "$SANDBOX/tracked.z" | wc -c)
if sweep_floor_ok "$_sw_non" "$_sw_subj"; then pass
else fail "SWEEP is vacuous: $_sw_non non-subject and $_sw_subj subject tracked files partitioned (need >= 1000 and >= 3)"; fi
if [ -n "$_sw_skipped" ] && [ $((_sw_non + _sw_subj + _sw_skipped)) -eq "$_ls_n" ]; then pass
else fail "SWEEP partition ($_sw_non non-subject + $_sw_subj subject + ${_sw_skipped:-?} skipped) does not equal the $_ls_n tracked files: a chunk or file was lost"; fi
sweep_run "$BODY"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "SWEEP live body, rc=$_r: $WHY"; fi
if [ "$SW_SEEN" -eq $((_sw_non + _sw_subj)) ]; then pass
else fail "SWEEP fed $SW_SEEN files through the body, the partition holds $((_sw_non + _sw_subj)): the chunk loop stopped early"; fi
sweep_subject_each "$BODY" "$RE_VAL"; _r=$?
if [ "$_r" -eq 0 ] && [ "$SW_FED" -ge 25 ]; then pass
else fail "SWEEP subject direction per file, rc=$_r fed=$SW_FED (need >= 25): $WHY"; fi

# ── Wrapper assertions (equalities on the extracted workflow, not whole-file grep) ──────────
export EXP_SMOKE_IF="$IF_LITERAL"
run_wrapper() { # <workflow file>: sets WHY to the newline-joined tags; returns 0 clean, 1 tags, 2 crash
  local out
  if ! out=$(python3 "$SANDBOX/wrapper.py" "$1" "$REQUIRED" 2>"$SANDBOX/w.err"); then
    WHY="CRASH wrapper.py: $(cat "$SANDBOX/w.err")"; return 2
  fi
  WHY=$(tr '\n' ' ' <<<"$out")
  if [ -n "$out" ]; then return 1; fi
  return 0
}
run_wrapper "$WF"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "W live workflow wrapper: rc=$_r tags: $WHY"; fi

# ── smoke must never be a required context (a required rollup reads `skipped` as green) ─────
reqctx_check() { # <required-checks.txt> <ruleset json>: 0 clean, 1 a smoke context is required, 2 crash
  local out
  if ! out=$(python3 "$SANDBOX/reqctx.py" "$1" "$2" 2>"$SANDBOX/rq.err"); then
    WHY="CRASH reqctx.py: $(cat "$SANDBOX/rq.err")"; return 2
  fi
  WHY=""
  if [ -n "$out" ]; then
    WHY="SMOKE-REQUIRED: required context(s) naming smoke: $(tr '\n' ',' <<<"$out") - a required smoke rollup would make a skipped matrix read as green and turn this cost optimisation into a control (see ADR-032, branch protection as IaC)"
    return 1
  fi
  return 0
}
reqctx_check "$REQUIRED" "$RULESET"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "REQUIRED live required contexts: rc=$_r $WHY"; fi
cp "$REQUIRED" "$SANDBOX/mut/required-smoke.txt"; printf 'smoke (allowlist-positive)\n' >> "$SANDBOX/mut/required-smoke.txt"
reqctx_check "$SANDBOX/mut/required-smoke.txt" "$RULESET"; _r=$?
mutant_verdict "R1 required-checks.txt gains 'smoke (allowlist-positive)'" "$_r" "SMOKE-REQUIRED: required context(s) naming smoke: smoke (allowlist-positive)"
jq '. + [{"context": "smoke (allowlist-positive)", "integration_id": 15368}]' "$RULESET" > "$SANDBOX/mut/ruleset-smoke.json"
reqctx_check "$REQUIRED" "$SANDBOX/mut/ruleset-smoke.json"; _r=$?
mutant_verdict "R2 canonical ruleset JSON gains a smoke context" "$_r" "SMOKE-REQUIRED: required context(s) naming smoke: smoke (allowlist-positive)"

# ── No symlinked subject files (a symlink in the subject set would be read through) ─────────
symlink_scan() { # <re>: reads `git ls-files -s` lines on stdin, prints each mode-120000 path that matches the regex
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qE "$1" <<<"$f"; then printf '%s\n' "$f"; fi
  done < <(awk -F'\t' '$1 ~ /^120000 / {print $2}')
}
_links=$(git -C "$REPO_ROOT" ls-files -s | symlink_scan "$RE_VAL")
if [ -z "$_links" ]; then pass; else fail "G1 a tracked symlink matches SUBJECT_RE (mode 120000): $(tr '\n' ' ' <<<"$_links")"; fi
# positive controls (the repo has no tracked subject symlink, so the live scan alone can never fire)
_TABC=$(printf '\t')
if [ "$(printf '120000 0000000000000000000000000000000000000000 0%s.gitleaks.toml\n' "$_TABC" | symlink_scan "$RE_VAL")" = ".gitleaks.toml" ]; then pass
else fail "CONTROL symlink_scan: a mode-120000 .gitleaks.toml was not reported"; fi
if [ -z "$(printf '100644 0000000000000000000000000000000000000000 0%s.gitleaks.toml\n' "$_TABC" | symlink_scan "$RE_VAL")" ]; then pass
else fail "CONTROL symlink_scan: a regular file (mode 100644) was reported as a symlink"; fi
if [ -z "$(printf '120000 0000000000000000000000000000000000000000 0%sdocs/x.md\n' "$_TABC" | symlink_scan "$RE_VAL")" ]; then pass
else fail "CONTROL symlink_scan: a symlink outside SUBJECT_RE was reported"; fi

# ── Operand anchor ───────────────────────────────────────────────────────────
# Membership, not a verb list: every token of the PARSED smoke-tests job (run bodies, uses, with,
# env) that is a tracked file or a tracked directory prefix must match SUBJECT_RE. No exemptions.
N_OPS=0
anchor_check() { # <workflow file> <subject re>: 0 ok, 1 assertion failed, 2 extractor crash
  local ops op rc=0
  WHY=""
  if ! ops=$(python3 "$SANDBOX/operands.py" "$1" smoke-tests "$SANDBOX/tracked.z" 2>"$SANDBOX/op.err"); then
    WHY="CRASH operands.py: $(cat "$SANDBOX/op.err")"; return 2
  fi
  N_OPS=0
  if [ -n "$ops" ]; then N_OPS=$(grep -c '' <<<"$ops" || true); fi
  if [ "$N_OPS" -lt "$OPERAND_FLOOR" ]; then
    WHY="${WHY}OPERANDS-FLOOR: only $N_OPS distinct tracked operands, measured $OPERAND_FLOOR; "; rc=1
  fi
  while IFS= read -r op; do
    [ -n "$op" ] || continue
    if ! grep -qE "$2" <<<"$op"; then WHY="${WHY}OPERAND-OUTSIDE-PATTERN: $op; "; rc=1; fi
  done <<<"$ops"
  return $rc
}
anchor_check "$WF" "$RE_VAL"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "ANCHOR live smoke-tests operands: rc=$_r $WHY"; fi
LIVE_OPS=$N_OPS
# known-positive control: the extractor really finds each known operand by name in the live job
_ops_live=$(python3 "$SANDBOX/operands.py" "$WF" smoke-tests "$SANDBOX/tracked.z" | tr '\n' ' ')
for _must in apps/web-platform/scripts/lint-fixture-content.mjs apps/web-platform/scripts/rename-guard.sh \
             apps/web-platform/scripts/allowlist-diff.sh .gitleaks.toml apps/web-platform/test/__synthesized__/ \
             "$RUNBOOK_PATH"; do
  if [[ " $_ops_live" == *" $_must "* ]]; then pass; else fail "ANCHOR control: the extractor did not find the known operand $_must in the live job (found: $_ops_live)"; fi
done
# shape rows: each shape must yield exactly the expected number of operands
_T=scripts/lint-workflows.sh
_A=$(git -C "$REPO_ROOT" ls-files '.github/actions/*/action.yml' | head -1 | xargs -r dirname)
if [ -n "$_A" ]; then pass; else fail "ANCHOR shape setup: no tracked .github/actions/<dir>/action.yml to use as a uses: ./ operand"; fi
SHAPE_KIND=(); SHAPE_EXP=(); SHAPE_LABEL=(); SHAPE_VAL=()
shape() { # <kind> <expected count> <label> <value>   (collected, evaluated in one python run by shapes_run)
  SHAPE_KIND+=("$1"); SHAPE_EXP+=("$2"); SHAPE_LABEL+=("$3"); SHAPE_VAL+=("$4")
}
shapes_run() {
  local i got
  local -a counts
  for i in "${!SHAPE_KIND[@]}"; do
    jq -nc --arg k "${SHAPE_KIND[$i]}" --arg v "${SHAPE_VAL[$i]}" '{kind: $k, val: $v}'
  done | jq -s . > "$SANDBOX/shapes.json"
  if ! mapfile -t counts < <(python3 "$SANDBOX/operands.py" --shapes "$SANDBOX/shapes.json" "$SANDBOX/tracked.z" 2>"$SANDBOX/sh.err"); then
    fail "ANCHOR shape rows: operands.py --shapes crashed: $(cat "$SANDBOX/sh.err")"; return
  fi
  if [ "${#counts[@]}" -ne "${#SHAPE_KIND[@]}" ]; then
    fail "ANCHOR shape rows: ${#counts[@]} results for ${#SHAPE_KIND[@]} cases: $(cat "$SANDBOX/sh.err")"; return
  fi
  for i in "${!SHAPE_KIND[@]}"; do
    got="${counts[$i]}"
    if [ "$got" -eq "${SHAPE_EXP[$i]}" ]; then pass; else fail "ANCHOR shape '${SHAPE_LABEL[$i]}': expected ${SHAPE_EXP[$i]} operand(s), got $got for: ${SHAPE_VAL[$i]}"; fi
  done
}
# shellcheck disable=SC2016  # the literal ${GITHUB_WORKSPACE} must reach the YAML value unexpanded
_GW='${GITHUB_WORKSPACE}'
shape run 1 "bash" "bash $_T --x"
shape run 1 "sh" "sh $_T"
shape run 1 "node" "node $_T"
shape run 1 "python3" "python3 $_T"
shape run 1 "source" "source $_T"
shape run 1 "dot" ". $_T"
shape run 1 "jq -f" "jq -f $_T in.json"
shape run 1 "leading ./" "./$_T"
shape run 1 "bash with flag" "bash -x $_T"
shape run 1 "bash -c nested node" "bash -c \"node $_T\""
shape run 1 "quoted GITHUB_WORKSPACE expansion" "bash \"$_GW/$_T\""
shape run 1 "cat piped to bash" "cat $_T | bash"
shape run 1 "redirect source" "bash < $_T"
shape run 1 "VAR=file prefix assignment" "GITLEAKS_CONFIG=$_T ./gitleaks detect"
shape run 1 "runtime path that is also tracked (membership, superset)" "mkdir -p $_T"
shape run 1 ".gitleaks operand" "git add .gitleaksignore"
shape run 1 "bash comment inside a run body (superset)" "# see $_T"
shape env 1 "GITLEAKS_CONFIG env value" "$_T"
shape uses 1 "uses ./ action dir" "./$_A"
shape run 0 "untracked operand" "bash scripts/definitely-not-a-tracked-file.sh"
shape run 0 "variable operand" "bash \"\$SOME_SCRIPT\""
shape run 0 "bare word equal to a top-level directory" "echo scripts are run"
# ACCEPTED LIMITS, recorded as decisions (see the suite comment): forms the membership derivation cannot see
shape run 0 "ACCEPTED LIMIT: glob" "cat scripts/lint-*.sh"
shape run 0 "ACCEPTED LIMIT: cd then a bare name" "cd scripts && bash lint-workflows.sh"
shape run 0 "ACCEPTED LIMIT: variable-composed path" "d=scripts; bash \$d/lint-workflows.sh"
shape run 0 "ACCEPTED LIMIT: bare top-level directory word" "ls scripts"
shape ycomment 0 "YAML comment-only mention" "bash $_T"
shapes_run

# M2: a reference to a REAL tracked file outside the pattern, added as a step of the smoke-tests job.
# One variant per sort position of the offending operand (first / middle / last of the sorted list).
STEP_ANCHOR=$'      - name: Configure git identity (for staging fixtures)\n'
m2_variant() { # <name> <offending path> <expected sort position note>
  if land "M2-$1.yml" "$WF" "$STEP_ANCHOR" $'      - name: probe\n        run: cat '"$2"$'\n\n'"$STEP_ANCHOR"; then
    anchor_check "$LANDED" "$RE_VAL"; _r=$?
    mutant_verdict "M2 smoke-tests gains 'cat $2' ($3: a real tracked file outside the pattern)" "$_r" "OPERAND-OUTSIDE-PATTERN: $2"
  fi
}
m2_variant first .github/CODEOWNERS "sorts first"
m2_variant middle AGENTS.md "sorts in the middle"
m2_variant last "$_T" "sorts last"
# the runbook is a REAL operand when a step reads it: it is handled by SUBJECT_RE (exact path), not by an
# exemption. Live regex: green. Regex without the runbook alternative: the same step is flagged.
if land M2-runbook.yml "$WF" "$STEP_ANCHOR" $'      - name: probe\n        run: cat '"$RUNBOOK_PATH"$'\n\n'"$STEP_ANCHOR"; then
  anchor_check "$LANDED" "$RE_VAL"; _r=$?
  if [ "$_r" -eq 0 ]; then pass; else fail "ANCHOR 'cat $RUNBOOK_PATH' in smoke-tests must be covered by SUBJECT_RE: rc=$_r $WHY"; fi
  _re_norb="${RE_VAL/"$RUNBOOK_ALT"/}"
  if [ "$_re_norb" = "$RE_VAL" ]; then fail "ANCHOR runbook alternative '$RUNBOOK_ALT' is not in SUBJECT_RE"; else
    anchor_check "$LANDED" "$_re_norb"; _r=$?
    mutant_verdict "M2 smoke-tests gains 'cat $RUNBOOK_PATH' and SUBJECT_RE has no runbook alternative (no exemption hides it)" "$_r" "OPERAND-OUTSIDE-PATTERN: $RUNBOOK_PATH"
    # the live job's own mention (the ::warning:: text) is covered by the alternative alone
    anchor_check "$WF" "$_re_norb"; _r=$?
    mutant_verdict "M2 live job's quoted runbook path is flagged when the alternative is dropped" "$_r" "OPERAND-OUTSIDE-PATTERN: $RUNBOOK_PATH"
  fi
fi
# an untracked reference proves nothing and must not trip the anchor (the control for the above)
if land M2-untracked.yml "$WF" "$STEP_ANCHOR" $'      - name: probe\n        run: bash scripts/definitely-not-a-tracked-file.sh\n\n'"$STEP_ANCHOR"; then
  anchor_check "$LANDED" "$RE_VAL"; _r=$?
  if [ "$_r" -eq 0 ]; then pass; else fail "ANCHOR an untracked operand must not trip the anchor: $WHY"; fi
fi
# a tracked DIRECTORY prefix outside the pattern (uses: ./ action dir) trips it too
if land M2-uses-dir.yml "$WF" "$STEP_ANCHOR" $'      - name: probe\n        uses: ./'"$_A"$'\n\n'"$STEP_ANCHOR"; then
  anchor_check "$LANDED" "$RE_VAL"; _r=$?
  mutant_verdict "M2 smoke-tests gains 'uses: ./$_A' (a tracked directory outside the pattern)" "$_r" "OPERAND-OUTSIDE-PATTERN: $_A/"
fi

# Row 3: fewer than the measured operands, or 0 extracted steps, must FAIL
# the text below is the workflow's own redirect, assembled so the P1b scanner does not read it as this file's write
_RD='>'
if land M3-fewer-ops.yml "$WF" "bash apps/web-platform/scripts/allowlist-diff.sh ${_RD}\"\$SMOKE_OUT\"" "echo noop ${_RD}\"\$SMOKE_OUT\""; then
  anchor_check "$LANDED" "$RE_VAL"; _r=$?
  mutant_verdict "M3 one operand removed from the job (fewer than the measured $OPERAND_FLOOR)" "$_r" "OPERANDS-FLOOR"
fi
if land M3-job-renamed "$WF" $'\n  smoke-relevance:\n' $'\n  smoke-relevancex:\n'; then
  _x="$SANDBOX/mut/m3x"; mkdir -p "$_x"
  python3 "$SANDBOX/extract.py" "$LANDED" "$_x" 2>"$SANDBOX/x.err"; _r=$?
  MUT_RUN=$((MUT_RUN + 1))
  if [ "$_r" -eq 3 ] && grep -q 'found 0 run steps' "$SANDBOX/x.err"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT NOT CAUGHT: M3 job renamed so 0 steps are extracted (extract rc=$_r: $(cat "$SANDBOX/x.err"))"; fi
fi

# ── Row 1: SUBJECT_RE mutants (each against the row naming the member it must keep) ─────────
subj_mut() { # <name> <expected got-reason> <path> <old> <new>
  local name="$1" got="$2" path="$3"
  shift 3
  if land "M1-$name" "$BODY" "$@"; then
    set_names true "$R_SUBJ" "$path"
    mutant_sc "M1 $name: $path must stay subject" sc_names "$LANDED" "reason='$got'"
  fi
}
subj_mut never-match "$R_NOSUBJ" .gitleaks.toml "$RE_ASSIGN" "SUBJECT_RE='^\$'"
subj_mut drop-workflow-alt "$R_NOSUBJ" .github/workflows/secret-scan.yml '\.github/workflows/secret-scan\.yml|' ''
subj_mut drop-toml-alt "$R_NOSUBJ" .gitleaks.toml '\.gitleaks\.toml|' ''
subj_mut drop-ignore-alt "$R_NOSUBJ" .gitleaksignore '|\.gitleaksignore' ''
subj_mut drop-runbook-alt "$R_NOSUBJ" "$RUNBOOK_PATH" "$RUNBOOK_ALT" ''
subj_mut drop-prefix-alt "$R_NOSUBJ" apps/web-platform/scripts/rename-guard.sh '|^apps/web-platform/scripts/' ''
subj_mut drop-gitattributes-alt "$R_NOSUBJ" .gitattributes '|(^|/)\.git(attributes|ignore)$' ''
subj_mut drop-smoke-alt "$R_NOSUBJ" apps/web-platform/server/smoke/with-secret.ts '|(^|/)smoke(/|$)' ''
# the cases create fixtures under FOUR smoke directories; a narrowed alternative that keeps only the
# server one must be caught by a named member under each of the other two
subj_mut narrow-smoke-server-only-goldens "$R_NOSUBJ" apps/web-platform/test/__goldens__/smoke/x \
  '|(^|/)smoke(/|$)' '|^(smoke|apps/web-platform/server/smoke)(/|$)'
subj_mut narrow-smoke-server-only-safety "$R_NOSUBJ" apps/web-platform/lib/safety/smoke/x \
  '|(^|/)smoke(/|$)' '|^(smoke|apps/web-platform/server/smoke)(/|$)'
subj_mut smoke-file-collision "$R_NOSUBJ" apps/web-platform/server/smoke '(^|/)smoke(/|$)' '(^|/)smoke/'
subj_mut drop-synthesized-alt "$R_NOSUBJ" apps/web-platform/test/__synthesized__/now-allowed.ts '|^apps/web-platform/test/__synthesized__(/|$)' ''
subj_mut synthesized-file-collision "$R_NOSUBJ" apps/web-platform/test/__synthesized__ '__synthesized__(/|$)' '__synthesized__/'
subj_mut drop-ancestors-alt "$R_NOSUBJ" apps/web-platform/test/__goldens__ '|^apps(/web-platform(/(test(/__goldens__)?|server|lib(/safety)?))?)?$' ''
subj_mut narrow-ancestors "$R_NOSUBJ" apps/web-platform/lib/safety 'lib(/safety)?' 'lib'
subj_mut drop-gitleaks-bin-alt "$R_NOSUBJ" gitleaks.tgz '|^gitleaks(\.tgz)?(/|$)' ''
subj_mut narrow-prefix "$R_NOSUBJ" apps/web-platform/scripts/new-helper.mjs '|^apps/web-platform/scripts/' \
  '|^apps/web-platform/scripts/(rename-guard\.sh|allowlist-diff\.sh|lint-fixture-content\.mjs|parse-gitleaks-allowlists\.mjs)$'
# loosening direction: each mutant must turn a non-subject path (or the sweep) red
if land M1-drop-leading-caret "$BODY" "SUBJECT_RE='^(\\.github" "SUBJECT_RE='(\\.github"; then
  set_names false "$R_NOSUBJ" x/.github/workflows/secret-scan.yml
  mutant_sc "M1 leading ^ of the first group dropped: x/.github/workflows/secret-scan.yml must stay non-subject" sc_names "$LANDED" "verdict=true"
fi
if land M1-extra-json-alt "$BODY" '(^|/)smoke(/|$)'"'" '(^|/)smoke(/|$)|\.json$'"'"; then
  sweep_run "$LANDED"; _r=$?
  mutant_verdict "M1 an extra '|\\.json\$' alternative: the derived sweep must see non-subject tracked files turn true" "$_r" "verdict=true"
fi

# the subject direction PER FILE: a prefix narrowed to four named scripts still matches the chunk's
# any-match (so the chunk sweep above stays green); only the per-file check and the one-at-a-time body sample see it
if land M1-sweep-narrow-prefix "$BODY" '|^apps/web-platform/scripts/' \
  '|^apps/web-platform/scripts/(rename-guard\.sh|allowlist-diff\.sh|lint-fixture-content\.mjs|parse-gitleaks-allowlists\.mjs)$'; then
  _re_n=$(sed -n "s/^[[:space:]]*SUBJECT_RE='\\(.*\\)'[[:space:]]*\$/\\1/p" "$LANDED")
  sweep_subject_each "$LANDED" "$_re_n"; _r=$?
  mutant_verdict "M1 prefix narrowed to four scripts: the per-file subject check must name an unmatched tracked file" "$_r" "SWEEP-SUBJECT: tracked subject file(s) the regex does not match"
  sweep_subject_each "$LANDED" "$RE_VAL"; _r=$?
  mutant_verdict "M1 prefix narrowed to four scripts: the one-at-a-time body sample must see a sampled file turn false" "$_r" "fed alone"
fi

# ── Row 4: the fetch ─────────────────────────────────────────────────────────
FETCH_END="end)'); then"
if land M4-or-true "$BODY" "$FETCH_END" "end)' || true); then"; then
  mutant_sc "M4 lines=\$(gh api ... || true): a failed fetch must be 'file list fetch failed'" sc_fail "$LANDED" "reason='$R_EMPTY'"
  mutant_sc "M4 lines=\$(gh api ... || true): page one then failure must not yield smoke=false" sc_pthf "$LANDED" "verdict=false"
fi
if land M4-no-paginate "$BODY" 'gh api --paginate "repos' 'gh api "repos'; then
  mutant_sc "M4 --paginate dropped: a subject file on page two must still be found" sc_twopage "$LANDED" "reason='$R_MISMATCH'"
fi

# ── Row 5: guards inside the body ────────────────────────────────────────────
# With the redundant name-extraction arm gone, the empty-list guard is load-bearing: an empty list
# with changed_files=0 passes the count check and would otherwise end in smoke=false.
if land M5-no-empty-guard "$BODY" 'if [ -z "$lines" ]; then emit true "empty file list"; exit 0; fi' ':'; then
  mutant_sc "M5 empty-list guard removed (empty list + changed_files=0 must not become smoke=false)" sc_empty "$LANDED" "reason='$R_NOSUBJ'"
fi
COUNT_TEST='[ "$(grep -c "^F$T" <<<"$lines")" != "$CHANGED_FILES" ]'
if land M5-no-count-check "$BODY" "$COUNT_TEST" 'false'; then
  mutant_sc "M5 CHANGED_FILES comparison removed (list shorter than the event)" sc_short "$LANDED" "reason='$R_NOSUBJ'"
  mutant_sc "M5 CHANGED_FILES comparison removed (list longer than the event)" sc_long "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-cap-removed "$BODY" 'if [ "$CHANGED_FILES" -ge 3000 ]; then emit true "at the file-list cap"; exit 0; fi' ':'; then
  mutant_sc "M5 file-list cap check removed (exactly 3000 entries)" sc_cap_exact "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-cap-gt "$BODY" '"$CHANGED_FILES" -ge 3000' '"$CHANGED_FILES" -gt 3000'; then
  mutant_sc "M5 file-list cap boundary -ge 3000 weakened to -gt 3000" sc_cap_exact "$LANDED" "reason='$R_NOSUBJ'"
fi
HEAD_FETCH='if ! cur_head=$(gh api "repos/$GH_REPO/pulls/$PR_NUMBER" --jq .head.sha); then emit true "head fetch failed"; exit 0; fi'
HEAD_CMP='if [ -z "$HEAD_SHA" ] || [ "$cur_head" != "$HEAD_SHA" ]; then emit true "head moved"; exit 0; fi'
if land M5-head-check-dropped "$BODY" "$HEAD_CMP" ':'; then
  mutant_sc "M5 head comparison dropped (PR head moved)" sc_head_moved "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-head-compare-swapped "$BODY" '"$cur_head" != "$HEAD_SHA"' '"$cur_head" = "$HEAD_SHA"'; then
  mutant_sc "M5 head comparison swapped (matching head read as moved)" sc_head_match "$LANDED" "reason='$R_HEADMOVED'"
  mutant_sc "M5 head comparison swapped (moved head read as current)" sc_head_moved "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-head-fetch-or-true "$BODY" "$HEAD_FETCH" 'cur_head=$(gh api "repos/$GH_REPO/pulls/$PR_NUMBER" --jq .head.sha || true)'; then
  mutant_sc "M5 head lookup failure swallowed (reason must stay 'head fetch failed')" sc_head_fetch "$LANDED" "reason='$R_HEADMOVED'"
fi
if land M5-head-empty-guard-dropped "$BODY" '[ -z "$HEAD_SHA" ] || ' ''; then
  mutant_sc "M5 empty-HEAD_SHA guard dropped (both sides empty)" sc_head_empty "$LANDED" "reason='$R_NOSUBJ'"
fi
if [ -n "$BODY_BADRE" ] && land M5-rc2-nomatch "$BODY_BADRE" '*) emit true "matcher error rc=$rc";;' '*) emit false "matcher error rc=$rc";;'; then
  set_names true "$R_MATCHER" docs/a.md
  mutant_sc "M5 grep rc 2 treated as no-match" sc_names "$LANDED" "verdict=false reason='$R_MATCHER'"
fi
if land M5-no-previous-filename "$BODY" '(if .previous_filename then "P\t" + .previous_filename else empty end)' 'empty'; then
  mutant_sc "M5 previous_filename branch removed (rename OUT of a subject path)" sc_rename_out "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-names-from-P-only "$BODY" 'names=$(cut -s -f2- <<<"$lines")' 'names=$(grep -E "^P$T" <<<"$lines" | cut -f2-)'; then
  mutant_sc "M5 matcher fed only the previous_filename column (rename INTO a subject path)" sc_rename_in "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-cut-f2 "$BODY" 'cut -s -f2-' 'cut -s -f2'; then
  mutant_sc "M5 cut -f2 (not -f2-): a TAB inside a filename truncates the name (docs/a<TAB>/smoke/b)" sc_tab_name "$LANDED" "reason='$R_NOSUBJ'"
fi
if land M5-count-prefix-F-only "$BODY" 'grep -c "^F$T"' 'grep -c "^F"'; then
  mutant_sc "M5 entry count matches a bare ^F: a stray line starting with F is counted" sc_hostile_fstray "$LANDED" "reason='$R_MISMATCH'"
fi
if land M5-cap-2999 "$BODY" '"$CHANGED_FILES" -ge 3000' '"$CHANGED_FILES" -ge 2999'; then
  mutant_sc "M5 file-list cap lowered to 2999: a trusted 2999-entry list fails open" sc_cap_below "$LANDED" "reason='$R_CAP'"
fi
if land M5-cut-without-s "$BODY" 'cut -s -f2-' 'cut -f2-'; then
  mutant_sc "M5 cut without -s: a stray subject-looking line becomes a name" sc_hostile_stray "$LANDED" "verdict=true"
fi

# ── Row 6: output order and cardinality ──────────────────────────────────────
OUT_LINE='echo "smoke=$1" >> "$GITHUB_OUTPUT"'
NOTICE_LINE='echo "::notice::smoke-relevance: smoke=$1 ($2)"'
if land M6-output-first "$BODY" "$OUT_LINE" ':' "$NOTICE_LINE" "$OUT_LINE; $NOTICE_LINE"; then
  mutant_sc "M6 GITHUB_OUTPUT written before the (failing) summary write" sc_summary_fail "$LANDED" "NOTFALSE"
fi
if land M6-twice "$BODY" "$OUT_LINE" "$OUT_LINE; $OUT_LINE"; then
  set_names true "$R_SUBJ" .gitleaks.toml
  mutant_sc "M6 the step writes smoke= twice" sc_names "$LANDED" "outlines=2"
fi

# ── Row 7: wrapper mutants on workflow copies ────────────────────────────────
wf_mut() { # <name> <expected tag> <old> <new>...
  local name="$1" tag="$2" r
  shift 2
  if land "M7-$name.yml" "$WF" "$@"; then
    run_wrapper "$LANDED"; r=$?
    mutant_verdict "M7 $name" "$r" "$tag"
  fi
}
wf_mut if-drop-result-arm "W-IF" "(needs.smoke-relevance.result != 'success' || needs.smoke-relevance.outputs.smoke != 'false')" \
  "(needs.smoke-relevance.outputs.smoke != 'false')"
wf_mut if-flip-to-eq-true "W-IF" "outputs.smoke != 'false'" "outputs.smoke == 'true'"
wf_mut if-drop-cancelled "W-IF" " && !cancelled()" ""
wf_mut if-drop-event-conjunct "W-IF" "if: github.event_name == 'pull_request' && !cancelled() && (" "if: (!cancelled()) && ("
wf_mut needs-extra "W-NEEDS" $'    needs: smoke-relevance\n' $'    needs: [smoke-relevance, scan]\n'
wf_mut needs-added-to-required-job "W-REQUIRED-EDGE" $'  lint-fixture-content:\n    name: lint fixture content\n' \
  $'  lint-fixture-content:\n    name: lint fixture content\n    needs: smoke-relevance\n'
wf_mut step-continue-on-error "W-COE-STEP" $'        id: relevance\n' $'        id: relevance\n        continue-on-error: true\n'
wf_mut step-shell-dropped "W-SHELL" $'        id: relevance\n        shell: bash\n' $'        id: relevance\n'
wf_mut job-continue-on-error "W-COE" $'    timeout-minutes: 5\n' $'    timeout-minutes: 5\n    continue-on-error: true\n'
wf_mut permissions-widened "W-PERM" $'      pull-requests: read\n    outputs:' $'      pull-requests: write\n    outputs:'
wf_mut job-if-dropped "W-JOBIF" $'    timeout-minutes: 5\n    if: github.event_name == \'pull_request\'\n' $'    timeout-minutes: 5\n'
wf_mut output-expression "W-OUTPUTS" 'smoke: ${{ steps.relevance.outputs.smoke }}' "smoke: 'true'"
wf_mut step-id-renamed "W-ID" $'        id: relevance\n' $'        id: relevancex\n'
wf_mut env-value-changed "W-ENV" '          CHANGED_FILES: ${{ github.event.pull_request.changed_files }}' \
  '          CHANGED_FILES: ${{ github.event.pull_request.number }}'
wf_mut env-head-sha-changed "W-ENV" $'          CHANGED_FILES: ${{ github.event.pull_request.changed_files }}\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}' \
  $'          CHANGED_FILES: ${{ github.event.pull_request.changed_files }}\n          HEAD_SHA: ${{ github.event.pull_request.base.sha }}'
wf_mut matrix-case-dropped "W-MATRIX" $'          - colocated-lib-test-allowlist\n' ''
wf_mut matrix-include-added "W-MATRIX" $'      matrix:\n        case:\n' $'      matrix:\n        include:\n          - case: extra\n        case:\n'
wf_mut matrix-entry-renamed "W-MATRIX-ARMS" $'          - allowlist-negative\n' $'          - allowlist-negativex\n'
wf_mut case-arm-renamed "W-MATRIX-ARMS" $'            allowlist-negative)\n' $'            allowlist-negativex)\n'
wf_mut case-step-env-changed "W-CASE-STEP" $'          CASE: ${{ matrix.case }}\n' $'          CASE: ${{ github.event_name }}\n'
wf_mut smoke-step-if "W-ST-IF" "$STEP_ANCHOR" "$STEP_ANCHOR        if: false"$'\n'
wf_mut smoke-step-continue-on-error "W-ST-COE" "$STEP_ANCHOR" "$STEP_ANCHOR        continue-on-error: true"$'\n'

# ── H1: stubs that always print one verdict must be told apart ───────────────
make_stub() { # <name> <verdict> <reason>
  local f="$SANDBOX/mut/stub-$1.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files?per_page=100" --jq ".[].filename" >/dev/null || true\n'
    printf 'gh api "repos/$GH_REPO/pulls/$PR_NUMBER" --jq .head.sha >/dev/null || true\n'
    printf 'echo "::notice::smoke-relevance: smoke=%s (%s)"\n' "$2" "$3"
    printf 'echo "smoke=%s" >> "$GITHUB_OUTPUT"\n' "$2"
  } > "$f"
  printf '%s' "$f"
}
count_failed_rows() { printf '%s\n' "${ROW_RC[@]}" | grep -vc '^0$' || true; }
STUB_FALSE=$(make_stub false false "$R_NOSUBJ")
STUB_TRUE=$(make_stub true true "$R_SUBJ")
# an always-false stub: every named-list row must fail, the non-subject control must pass
run_rows "$STUB_FALSE" quick
_failed=$(count_failed_rows)
if [ "$_failed" -eq "${#SUBJ[@]}" ] && [ "$(row_rc_of 'mod:.gitleaks.toml')" -eq 1 ]; then pass
else fail "H1 a stub that always writes smoke=false must fail exactly the named-list rows (failed $_failed of ${#ROW_ID[@]})"; fi
if [ "$(row_rc_of 'control:non-subject')" -eq 0 ]; then pass
else fail "H1 the always-false stub must PASS the non-subject control (the two verdicts must be distinguishable)"; fi
# an always-true stub: the non-subject control must fail, the named-list rows must pass
run_rows "$STUB_TRUE" quick
_failed=$(count_failed_rows)
if [ "$_failed" -eq 1 ] && [ "$(row_rc_of 'control:non-subject')" -eq 1 ]; then pass
else fail "H1 a stub that always writes smoke=true must fail exactly the non-subject control (failed $_failed)"; fi

# ── Positive controls for the verdict-owning helpers ─────────────────────────
# assert_sc, report_rows and mutant_verdict decide every row above. Each is driven ONCE with an input
# that MUST fail; its failure counter must move. The counters and ledger are then unwound, and a
# violation is reported through printf + exit (never through the helper under test).
ctl_snapshot() { _c_p=$passes; _c_f=$fails; _c_n=${#FAILURES[@]}; _c_mr=$MUT_RUN; _c_mc=$MUT_CAUGHT; }
ctl_restore() { passes=$_c_p; fails=$_c_f; MUT_RUN=$_c_mr; MUT_CAUGHT=$_c_mc; FAILURES=("${FAILURES[@]:0:$_c_n}"); }
ctl_die() {
  printf 'FAIL CONTROL: %s\n' "$1" >&2
  printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" $((passes + fails))
  exit 1
}

# assert_sc: the always-false stub on the empty-list scenario (expects smoke=true) must record one failure
ctl_snapshot
assert_sc "CONTROL assert_sc (expected failure)" sc_empty "$STUB_FALSE" 2>/dev/null
_mf=$((fails - _c_f)); _mn=$((${#FAILURES[@]} - _c_n)); _mp=$((passes - _c_p))
ctl_restore
if [ "$_mf" -eq 1 ] && [ "$_mn" -eq 1 ] && [ "$_mp" -eq 0 ]; then pass
else ctl_die "assert_sc did not record exactly one failure for an input that must fail (fails+$_mf ledger+$_mn passes+$_mp)"; fi

# report_rows: one failing row and one passing row must move the counters by exactly one each
ctl_snapshot
ROW_ID=(ctl-ok ctl-bad); ROW_RC=(0 1); ROW_WHY=("fine" "synthetic failing row")
report_rows "CONTROL report_rows (expected failure)" 2>/dev/null
_mf=$((fails - _c_f)); _mn=$((${#FAILURES[@]} - _c_n)); _mp=$((passes - _c_p))
ctl_restore
if [ "$_mf" -eq 1 ] && [ "$_mn" -eq 1 ] && [ "$_mp" -eq 1 ]; then pass
else ctl_die "report_rows did not record one failure and one pass for a failing and a passing row (fails+$_mf ledger+$_mn passes+$_mp)"; fi

# mutant_verdict: caught only on (rc 1 AND the named effect). rc 0 (an uncatchable mutant), rc 2 (a
# crash) and a wrong effect must each register as NOT caught; rc 1 with the effect must register as caught.
ctl_snapshot
WHY="synthetic: the NAMED-EFFECT happened"
mutant_verdict "CONTROL caught" 1 "NAMED-EFFECT" 2>/dev/null
_mc_caught=$((MUT_CAUGHT - _c_mc)); _mf_caught=$((fails - _c_f))
mutant_verdict "CONTROL crash is not caught" 2 "NAMED-EFFECT" 2>/dev/null
mutant_verdict "CONTROL wrong effect is not caught" 1 "OTHER-EFFECT" 2>/dev/null
# the deliberately UNCATCHABLE mutant: a whitespace-only edit of the body behaves identically, so the
# check passes (rc 0) and mutant_verdict must NOT count it caught
set_names true "$R_SUBJ" .gitleaks.toml
if land C-whitespace "$BODY" "T=\$(printf '\\t')" "T=\$(printf '\\t')   "; then
  mutant_sc "CONTROL whitespace-only mutant (uncatchable)" sc_names "$LANDED" "reason='$R_SUBJ'" 2>/dev/null
else
  ctl_die "could not land the whitespace-only control mutant"
fi
_mc_all=$((MUT_CAUGHT - _c_mc)); _mf_all=$((fails - _c_f)); _mr_all=$((MUT_RUN - _c_mr))
ctl_restore
if [ "$_mc_caught" -eq 1 ] && [ "$_mf_caught" -eq 0 ] && [ "$_mc_all" -eq 1 ] && [ "$_mf_all" -eq 3 ] && [ "$_mr_all" -eq 4 ]; then pass
else ctl_die "mutant_verdict mis-scored the controls (first caught+$_mc_caught fails+$_mf_caught; all caught+$_mc_all fails+$_mf_all runs+$_mr_all; expected 1/0 and 1/3/4)"; fi

# shapes_run decides every shape row: one row with a WRONG expected count must record exactly one failure
# (and a right one exactly one pass), or the compare has been neutered
ctl_snapshot
SHAPE_KIND=(run run); SHAPE_EXP=(2 1); SHAPE_LABEL=(ctl-wrong ctl-right); SHAPE_VAL=("bash $_T" "bash $_T")
shapes_run 2>/dev/null
_mf=$((fails - _c_f)); _mn=$((${#FAILURES[@]} - _c_n)); _mp=$((passes - _c_p))
ctl_restore
if [ "$_mf" -eq 1 ] && [ "$_mn" -eq 1 ] && [ "$_mp" -eq 1 ]; then pass
else ctl_die "shapes_run did not record one failure and one pass for a wrong and a right expectation (fails+$_mf ledger+$_mn passes+$_mp)"; fi

# check_scn's crash class: a body that CRASHED (rc 2, or >= 126: not executable, not found, a signal) is never
# an assertion verdict (return 2), while an ordinary failing exit (1, 125) is (return 1)
ctl_scn_rc() { # <body exit code> -> prints "<check_scn rc>:<WHY starts with CRASH ? y : n>"
  local r
  scn_new; : > "$SCN/stdout"; : > "$SCN/stderr"; RC=$1; CALLS=0; GOUT_N=0
  check_scn false "$R_NOSUBJ"; r=$?
  case "$WHY" in CRASH*) printf '%s:y' "$r" ;; *) printf '%s:n' "$r" ;; esac
}
_crash_bad=""
for _x in 2 126 127 139; do [ "$(ctl_scn_rc "$_x")" = "2:y" ] || _crash_bad="$_crash_bad rc$_x=$(ctl_scn_rc "$_x")"; done
for _x in 1 125; do [ "$(ctl_scn_rc "$_x")" = "1:n" ] || _crash_bad="$_crash_bad rc$_x=$(ctl_scn_rc "$_x")"; done
if [ -z "$_crash_bad" ]; then pass
else fail "CONTROL check_scn crash class: a crashing body must return 2, an ordinary failing exit 1 (got:$_crash_bad)"; fi

# the sweep floor: a vacuous or lopsided partition must be refused, a real one accepted
if ! sweep_floor_ok 0 0 && ! sweep_floor_ok 999 5 && ! sweep_floor_ok 5000 2 && sweep_floor_ok 1000 3; then pass
else fail "CONTROL sweep_floor_ok: (0,0), (999,5) and (5000,2) must be refused and (1000,3) accepted"; fi

# ── Mutant accounting and measured counts ────────────────────────────────────
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ]; then pass
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught)"; fi
if [ "$LIVE_OPS" -ge "$OPERAND_FLOOR" ]; then pass; else fail "ANCHOR the live job yielded $LIVE_OPS operands, measured $OPERAND_FLOOR"; fi

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): a floor that increments the counter it guards shares a
# lifetime with the thing it is checking. This compares against a literal and exits directly.
# Set to the FULL measured count, not a slack figure.
#
# KEEP THESE TWO ASSIGNMENTS CONTIGUOUS (no comment between them or before the `if`):
# scripts/guard-vacuity-floor.test.sh binds a floor's variables by walking BACKWARD from the `if`.
_total=$((passes + fails))
_FLOOR=259
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions; %d mutants caught; %d operands; %d rows; sweep %d+%d files)\n' \
  "$passes" "$fails" "$_total" "$MUT_CAUGHT" "$LIVE_OPS" "$_N_ROWS" "$_sw_non" "$_sw_subj"
exit $(( ${#FAILURES[@]} > 0 ))
