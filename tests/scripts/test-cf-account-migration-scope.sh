#!/usr/bin/env bash
# Workflow-grep suite for the #12931 migration-in-progress predicate's PLACEMENT (CTO ruling L79).
#
# The predicate (apps/web-platform/infra/scripts/cf-account-migration-complete.sh) runs as the last
# step of .github/actions/infra-credentials/action.yml and decides its own scope. Its behaviour is
# pinned by apps/web-platform/infra/cf-account-migration-complete.test.sh; THIS suite pins that it
# is reachable from every job that can plan against the web-platform root:
#
#   Scope is DENY BY DEFAULT (CTO D1): every workflow that uses ./.github/actions/infra-credentials
#   is gated unless the script's CFAM_EXEMPT_WORKFLOWS names it.
#   (1) derive the workflows whose INLINE `run:` text runs `terraform plan|apply|import|state
#       rm|mv|push` against apps/web-platform/infra (working-directory / -chdir / cd after resolving
#       ${{ env.X }}, ${{ matrix.X }} and $X, or a job carrying key=web-platform/terraform.tfstate).
#       Every derived workflow is a loader caller (so gated or named exempt) or the one named
#       non-caller (infra-validation.yml). Every exempt name is a real loader caller. An
#       unresolvable directory is RED (one named allowance, below).
#   (2) every such job of a gated workflow (exempt jobs aside) uses ./.github/actions/infra-credentials
#       BEFORE its first such command, unconditionally (no `if:`, no `continue-on-error`, only
#       declared inputs); the action's last step is the predicate, unconditional, env-bound.
#   (3) the exempt jobs exist and contain none of those commands.
#   (6) no exempt workflow outside the plan-only pair, nor a repo script it runs with `bash <path>`
#       (one level, plus the repo scripts that script sources), pairs a terraform invocation with
#       the bare root path apps/web-platform/infra (not followed by /<subdir>). This is the only
#       place script-wrapped Terraform is seen; composite actions and reusable callees are not.
#   (7) the cf-account-migrate job script carries no workflow-file list (it reads the exempt list).
#   (4) cf-account-migrate.yml shares the concurrency literal, carries no ssh bridge, ssh,
#       upload-artifact or TF_LOG, and has EXACTLY two jobs whose environment and REHEARSAL are
#       literals in the two exact pairs (CTO D7). Absent is RED. The logic is also driven against a
#       synthesized fixture with one mutation row per bypass shape.
#   (5) apply-web-platform-infra.yml contains no `cf-account-migrate` token.
#
# The exempt workflow list, the plan-only subset and the exempt jobs are READ FROM THE SCRIPT
# (sourced), never re-typed.
# Mutation rows sed a copy of one input, prove the copy differs, and require the named check RED.
#
# Run: bash tests/scripts/test-cf-account-migration-scope.sh
# shellcheck disable=SC2016 # single-quoted sed/python programs expand later, on purpose
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WFDIR="$REPO/.github/workflows"
ACTION="$REPO/.github/actions/infra-credentials/action.yml"
SCRIPT="$REPO/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"

PASS=0
FAIL=0
CASES=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
ok() { CASES=$((CASES + 1)); pass "$1"; }
no() { CASES=$((CASES + 1)); fail "$1"; }

_pc_p=$PASS; _pc_f=$FAIL; _pc_c=$CASES
ok "instrument self-test" >/dev/null
no "instrument self-test" >/dev/null
if (( PASS != _pc_p + 1 || FAIL != _pc_f + 1 || CASES != _pc_c + 2 )); then
  printf '[FATAL] instrument self-test: pass()/fail() did not move their counters\n' >&2
  exit 2
fi
PASS=$_pc_p; FAIL=$_pc_f; CASES=$_pc_c

for f in "$ACTION" "$SCRIPT" "$WFDIR/apply-web-platform-infra.yml"; do
  [[ -f "$f" ]] || { printf '[FATAL] missing input %s\n' "$f" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { printf '[FATAL] need python3 + PyYAML\n' >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR%/}/cfam-scope-test.XXXXXXXX")"
case "$WORK" in /*/*) ;; *) printf '[FATAL] bad work dir %s\n' "$WORK" >&2; exit 2 ;; esac
trap 'rm -rf "$WORK"' EXIT

ANALYZER="$WORK/analyze.py"
cat > "$ANALYZER" <<'PY'
"""Prints one line per check: `OK <id> <msg>` or `RED <id> <msg>`, plus `NOTE`/`SKIP` lines."""
import os, re, sys, glob
import yaml

Loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
wfdir, action_path, exempt_s, plan_only_s, exempt_jobs_s, repo_root = sys.argv[1:7]
EXEMPT = set(exempt_s.split())
PLAN_ONLY = set(plan_only_s.split())
EXEMPT_JOBS = set(exempt_jobs_s.split())
ROOT = "apps/web-platform/infra"
STATE_KEY = "key=web-platform/terraform.tfstate"
# The one derived planner that never calls the loader, so the predicate never runs there: the
# PR plan matrix of infra-validation.yml (plan -refresh=false, its own Tier-A backend read).
NONCALLER_OK = {"infra-validation.yml"}
LOADER = re.compile(r"^[ \t]*(?:-[ \t]+)?uses:[ \t]*\./\.github/actions/infra-credentials/?[ \t]*(?:#.*)?$", re.M)
# The ONE unresolvable-directory allowance: infra-validation.yml's PR plan matrix is
# fromJSON(needs.detect-changes.outputs.plan_directories), decided at run time. It is a named exempt
# workflow, so it is counted as touching the root (conservatively) instead of reddening.
UNRESOLVABLE_OK = {"infra-validation.yml"}
AWPI = "apply-web-platform-infra.yml"
MIGRATE = "cf-account-migrate.yml"
CONC = "terraform-apply-web-platform-host"

def out(kind, cid, msg): print("%s %s %s" % (kind, cid, msg))

def join_continuations(body):
    return re.sub(r"\\\n", " ", body)

def normal_text(body):
    """Shell text outside quotes, comments and heredoc bodies; `$( … )` inside double quotes kept.
    Same length and line layout as join_continuations(body), so offsets map back to the raw text."""
    body = join_continuations(body)
    st, heredoc = ["n"], None
    lines = body.split("\n")
    text_out = []
    pending_tags = []
    for line in lines:
        if heredoc:
            if line.strip() == heredoc[0] or (heredoc[1] and line.lstrip("\t") == heredoc[0]):
                heredoc = None
            text_out.append("")
            continue
        buf = []
        i, n = 0, len(line)
        while i < n:
            c = line[i]
            top = st[-1]
            if top in ("n", "sub"):
                if c == "#" and (i == 0 or line[i - 1] in " \t;&|("):
                    break
                if c == "'":
                    st.append("s"); buf.append(" "); i += 1; continue
                if c == '"':
                    st.append("d"); buf.append(" "); i += 1; continue
                if top == "sub" and c == ")":
                    st.pop(); buf.append(c); i += 1; continue
                if line.startswith("$(", i):
                    st.append("sub"); buf.append("$("); i += 2; continue
                m = re.match(r"<<(-?)\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line[i:])
                if m and not line.startswith("<<<", i) and (i == 0 or line[i - 1] != "<"):
                    pending_tags.append((m.group(2), m.group(1) == "-"))
                    buf.append(" " * len(m.group(0))); i += len(m.group(0)); continue
                buf.append(c); i += 1; continue
            if top == "s":
                if c == "'":
                    st.pop()
                buf.append(" "); i += 1; continue
            if top == "d":
                if c == "\\" and i + 1 < n:
                    buf.append("  "); i += 2; continue
                if c == '"':
                    st.pop(); buf.append(" "); i += 1; continue
                if line.startswith("$(", i):
                    st.append("sub"); buf.append("$("); i += 2; continue
                buf.append(" "); i += 1; continue
        text_out.append("".join(buf))
        if pending_tags and st[-1] in ("n", "sub"):
            heredoc = pending_tags[0]; pending_tags = []
    return "\n".join(text_out)

TF_CMD = re.compile(
    r"(?:^|[;&|(!]|\$\(|\bthen\b|\bdo\b|\belse\b|--)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:timeout\s+\S+\s+)?"
    r"terraform\s+((?:-chdir=\S+\s+)?)(plan|apply|import|state\s+(?:rm|mv|push))\b", re.M)
CD = re.compile(r"(?:^|[;&|(]|\bthen\b|\bdo\b)\s*cd\s", re.M)

def resolve(expr, envs, matrix):
    """-> list of candidate strings, or None when unresolvable."""
    cands = [expr]
    for _ in range(4):
        nxt, changed = [], False
        for c in cands:
            m = re.search(r"\$\{\{\s*([^}]*?)\s*\}\}", c)
            if m:
                changed = True
                inner = m.group(1)
                if inner == "github.workspace":
                    nxt.append(c[:m.start()] + c[m.end():]); continue
                mm = re.fullmatch(r"env\.([A-Za-z_][A-Za-z0-9_]*)", inner)
                if mm:
                    v = next((e[mm.group(1)] for e in envs if isinstance(e, dict) and mm.group(1) in e), None)
                    if v is None: return None
                    nxt.append(c[:m.start()] + str(v) + c[m.end():]); continue
                mm = re.fullmatch(r"matrix\.([A-Za-z_][A-Za-z0-9_-]*)", inner)
                if mm and isinstance(matrix, dict) and isinstance(matrix.get(mm.group(1)), list) \
                        and all(isinstance(x, str) for x in matrix[mm.group(1)]):
                    for x in matrix[mm.group(1)]:
                        nxt.append(c[:m.start()] + x + c[m.end():])
                    continue
                return None
            m = re.search(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", c)
            if m:
                changed = True
                name = m.group(1)
                if name == "GITHUB_WORKSPACE":
                    nxt.append(c[:m.start()] + c[m.end():]); continue
                v = next((e[name] for e in envs if isinstance(e, dict) and name in e), None)
                if v is None: return None
                nxt.append(c[:m.start()] + str(v) + c[m.end():]); continue
            nxt.append(c)
        cands = nxt
        if not changed: break
    if any("$" in c for c in cands): return None
    return cands

def norm(p):
    p = p.strip().strip("'\"")
    while p.startswith("./"): p = p[2:]
    p = p.lstrip("/").rstrip("/")
    return p

def analyze_workflow(rel, doc, text):
    """-> list of (job_id, job, [ (step_idx, touches_root, unresolved_expr) ]) for terraform commands."""
    res = []
    jobs = (doc or {}).get("jobs") or {}
    wf_env = doc.get("env") if isinstance(doc.get("env"), dict) else {}
    wf_wd = (((doc.get("defaults") or {}).get("run") or {}).get("working-directory"))
    for jid, job in jobs.items():
        if not isinstance(job, dict): continue
        steps = job.get("steps") or []
        job_env = job.get("env") if isinstance(job.get("env"), dict) else {}
        job_wd = (((job.get("defaults") or {}).get("run") or {}).get("working-directory"))
        matrix = (job.get("strategy") or {}).get("matrix")
        job_text = "\n".join(normal_text(str(s.get("run") or "")) for s in steps if isinstance(s, dict))
        key_root = STATE_KEY in job_text
        hits = []
        for i, s in enumerate(steps):
            if not isinstance(s, dict) or not s.get("run"): continue
            raw = join_continuations(str(s["run"]))
            nt = normal_text(str(s["run"]))
            envs = [s.get("env") or {}, job_env, wf_env]
            for m in TF_CMD.finditer(nt):
                chdir = m.group(1).strip()
                base = s.get("working-directory") or job_wd or wf_wd
                cds = list(CD.finditer(nt[:m.start()]))
                if chdir:
                    d = chdir[len("-chdir="):]
                elif cds:
                    # The cd ARGUMENT is read from the raw text at the same offset: in the normal
                    # text a quoted "$INFRA_DIR" is blanked.
                    a = re.match(r"\s*(?:\"([^\"]*)\"|'([^']*)'|(\S+))", raw[cds[-1].end():])
                    arg = next((g for g in (a.groups() if a else ()) if g is not None), "")
                    d = arg if (not base or arg.startswith("$") or arg.startswith("/")) else str(base) + "/" + arg
                else:
                    d = base if base is not None else "."
                cands = resolve(str(d), envs, matrix)
                if cands is None:
                    hits.append((i, key_root, str(d)))
                else:
                    hits.append((i, key_root or any(norm(c) == ROOT for c in cands), None))
        if hits:
            res.append((jid, job, hits))
    return res

# Per-file results are cached by content hash (CFAM_SCOPE_CACHE), so the mutation rows, which
# change one file each, re-analyze only that file. The cache key is the bytes, so a mutated copy
# can never be served a stale answer.
import hashlib, pickle
CACHE = os.environ.get("CFAM_SCOPE_CACHE", "")
docs, analyzed, texts, CALLERS = {}, {}, {}, set()
for f in sorted(glob.glob(os.path.join(wfdir, "*.yml")) + glob.glob(os.path.join(wfdir, "*.yaml"))):
    t = open(f).read()
    rel = os.path.basename(f)
    texts[rel] = t
    if LOADER.search(t):
        CALLERS.add(rel)
    if "terraform" not in t and rel not in (AWPI, MIGRATE) and rel not in EXEMPT:
        continue
    cpath = os.path.join(CACHE, hashlib.sha256((rel + "\0" + t).encode()).hexdigest()) if CACHE else ""
    if cpath and os.path.exists(cpath):
        with open(cpath, "rb") as fh:
            docs[rel], analyzed[rel] = pickle.load(fh)
        continue
    try:
        doc = yaml.load(t, Loader=Loader) or {}
    except yaml.YAMLError as e:
        out("RED", "parse", "%s does not parse: %s" % (rel, str(e).splitlines()[0]))
        continue
    docs[rel] = (doc, t)
    analyzed[rel] = analyze_workflow(rel, doc, t)
    if cpath:
        with open(cpath, "wb") as fh:
            pickle.dump((docs[rel], analyzed[rel]), fh)

GATED = CALLERS - EXEMPT
derived, unresolved, root_jobs, all_tf_jobs = set(), [], {}, {}
for rel in docs:
    for jid, job, hits in analyzed[rel]:
        all_tf_jobs[(rel, jid)] = hits
        for (i, touches, unres) in hits:
            if unres is not None:
                if rel in UNRESOLVABLE_OK:
                    derived.add(rel); root_jobs.setdefault((rel, jid), (job, []))[1].append(i)
                else:
                    unresolved.append("%s/%s step %d dir %r" % (rel, jid, i, unres))
            elif touches:
                derived.add(rel); root_jobs.setdefault((rel, jid), (job, []))[1].append(i)

# (1)
if unresolved:
    out("RED", "A1-unresolvable", "terraform directory not resolvable: " + "; ".join(unresolved[:5]))
else:
    out("OK", "A1-unresolvable", "every terraform command's directory resolved (allowance: %s)" % ",".join(sorted(UNRESOLVABLE_OK)))
unknown = sorted(derived - CALLERS - NONCALLER_OK)
out("RED" if unknown else "OK", "A1-unknown-planner",
    ("workflows plan against %s but neither call the loader nor are the named non-caller: %s" % (ROOT, unknown)) if unknown
    else "every derived planner calls the loader or is the named non-caller (derived=%s)" % sorted(derived))
stale = sorted(x for x in EXEMPT if x not in CALLERS)
out("RED" if stale or not EXEMPT else "OK", "A1-exempt-callers",
    ("exempt names that are not loader callers under %s: %s" % (os.path.basename(wfdir), stale)) if stale
    else "all %d exempt names are real loader callers; gated=%s" % (len(EXEMPT), sorted(GATED)))
bad_po = sorted(PLAN_ONLY - EXEMPT)
out("RED" if bad_po or not PLAN_ONLY else "OK", "A1-plan-only-subset",
    ("plan-only names missing from the exempt list: %s" % bad_po) if bad_po else "plan-only %s is a subset of the exempt list" % sorted(PLAN_ONLY))
for ex in sorted(PLAN_ONLY):
    if ex == MIGRATE:
        if ex in derived:
            out("NOTE", "A1-exempt-" + ex, "derived inline")
        else:
            out("NOTE", "A1-exempt-" + ex, "present; its terraform runs inside a script, so it is not derived inline")
        continue
    out("OK" if ex in derived else "RED", "A1-exempt-" + ex,
        "%s %s derived as a root planner" % (ex, "is" if ex in derived else "is NOT (stale plan-only name)"))
if len(derived) < 4:
    out("RED", "A1-floor", "only %d workflows derived; the derivation is broken" % len(derived))
else:
    out("OK", "A1-floor", "%d workflows derived" % len(derived))

# (2)
action = yaml.load(open(action_path).read(), Loader=Loader)
inputs = set((action.get("inputs") or {}).keys())
bad2, n2 = [], 0
for (rel, jid), (job, idxs) in sorted(root_jobs.items()):
    if rel not in GATED: continue
    if rel == AWPI and jid in EXEMPT_JOBS: continue
    n2 += 1
    steps = job.get("steps") or []
    first = min(idxs)
    L = [i for i, s in enumerate(steps) if isinstance(s, dict) and re.fullmatch(r"\./\.github/actions/infra-credentials/?", str(s.get("uses", "")).strip())]
    if not L or L[0] >= first:
        bad2.append("%s/%s: loader at %s, first terraform command at step %d" % (rel, jid, L[:1] or "none", first)); continue
    s = steps[L[0]]
    if "if" in s: bad2.append("%s/%s: loader step is conditional (if: %r)" % (rel, jid, s["if"]))
    if "continue-on-error" in s: bad2.append("%s/%s: loader step has continue-on-error" % (rel, jid))
    extra = sorted(set((s.get("with") or {}).keys()) - inputs)
    if extra: bad2.append("%s/%s: loader passes undeclared inputs %s" % (rel, jid, extra))
out("RED" if bad2 else "OK", "A2-loader-first",
    "; ".join(bad2[:5]) if bad2 else "all %d root-planning jobs of the gated workflows load the predicate first, unconditionally" % n2)
out("RED" if n2 < 10 else "OK", "A2-floor", "%d gated root-planning jobs checked" % n2)

steps = (action.get("runs") or {}).get("steps") or []
last = steps[-1] if steps else {}
want_env = {
    "CFAM_WORKFLOW_REF": "${{ github.workflow_ref }}",
    "CFAM_JOB": "${{ github.job }}",
    "CFAM_EVENT_NAME": "${{ github.event_name }}",
    "CFAM_WEB_HOST_KEY": "${{ github.event.inputs.web_host_key }}",
    "CFAM_DOPPLER_TOKEN_LEGACY": "${{ inputs.doppler-token-legacy }}",
}
run = str(last.get("run") or "")
# Closed set: the run text must BE the reviewed command. A denylist of mask shapes is a bypass list
# (`! bash …`, a trailing `&`, `| cat` all passed the old regex); the regex below stays as a diagnostic.
PRED_RUN = 'bash "${GITHUB_ACTION_PATH}/../../../apps/web-platform/infra/scripts/cf-account-migration-complete.sh" --from-r2'
probs = []
if run.strip() != PRED_RUN: probs.append("predicate run is not exactly %r (got %r)" % (PRED_RUN, run.strip()[:160]))
if "cf-account-migration-complete.sh" not in run or "--from-r2" not in run: probs.append("last step does not run the predicate --from-r2")
if "if" in last: probs.append("predicate step is conditional")
if "continue-on-error" in last: probs.append("predicate step has continue-on-error")
if "${{" in run: probs.append("predicate run: interpolates ${{ }}")
if re.search(r"\|\||;|&&|\|\s*true|exit\s+0", run): probs.append("predicate run: chains or masks its exit")
if (last.get("env") or {}) != want_env: probs.append("predicate env != %s" % want_env)
if last.get("shell") != "bash": probs.append("predicate shell is not bash")
out("RED" if probs else "OK", "A2-action-step", "; ".join(probs) if probs else "the action's last step is the unconditional, env-bound predicate")

# (3)
awpi = docs.get(AWPI, ({}, ""))[0]
bad3 = []
for j in sorted(EXEMPT_JOBS):
    if j not in (awpi.get("jobs") or {}): bad3.append("%s is not a job of %s (stale exempt name)" % (j, AWPI))
    elif (AWPI, j) in all_tf_jobs: bad3.append("exempt job %s runs a terraform plan/apply/import/state command" % j)
out("RED" if bad3 or not EXEMPT_JOBS else "OK", "A3-exempt-jobs",
    "; ".join(bad3) if bad3 else "exempt jobs %s exist and run no terraform command" % sorted(EXEMPT_JOBS))

# (4)
def check_migrate(rel):
    doc, text = docs[rel]
    p = []
    c = doc.get("concurrency")
    if not isinstance(c, dict) or c.get("group") != CONC or c.get("cancel-in-progress") is not False:
        p.append("workflow-level concurrency is not {group: %s, cancel-in-progress: false}" % CONC)
    for tok in ("cf-tunnel-ssh-bridge", "upload-artifact", "TF_LOG"):
        if tok in text: p.append("contains %s" % tok)
    jobs = doc.get("jobs") or {}
    for jid, job in jobs.items():
        for s in (job.get("steps") or []) if isinstance(job, dict) else []:
            if isinstance(s, dict) and re.search(r"(?:^|[;&|(!]|\$\(|\bthen\b|\bdo\b)\s*(?:sudo\s+)?(?:ssh|scp|sftp)\s", normal_text(str(s.get("run") or "")), re.M):
                p.append("job %s runs ssh" % jid)
    # D7: exactly two jobs; environment, if and the job step's REHEARSAL are exact literals.
    want = {
        "cf_account_migrate_rehearsal": ("inputs.rehearsal", "infra-privileged", "true"),
        "cf_account_migrate_apply": ("${{ !inputs.rehearsal }}", "web-platform-infra-apply", "false"),
    }
    if set(jobs) != set(want):
        p.append("jobs are %s, want exactly %s" % (sorted(jobs), sorted(want)))
    for jid, (cond, env, reh) in want.items():
        job = jobs.get(jid)
        if not isinstance(job, dict): continue
        if job.get("if") != cond: p.append("%s if: %r, want %r" % (jid, job.get("if"), cond))
        e = job.get("environment")
        if not isinstance(e, str) or "${{" in e or e != env: p.append("%s environment: %r, want the literal %r" % (jid, e, env))
        runs = [st for st in (job.get("steps") or []) if isinstance(st, dict) and "cf-account-migrate-job.sh" in str(st.get("run") or "")]
        if len(runs) != 1:
            p.append("%s has %d steps running cf-account-migrate-job.sh, want 1" % (jid, len(runs))); continue
        r = (runs[0].get("env") or {}).get("REHEARSAL")
        if not isinstance(r, str) or "${{" in r or r != reh: p.append("%s REHEARSAL: %r, want the literal %r" % (jid, r, reh))
        if "REHEARSAL" in (job.get("env") or {}) or "REHEARSAL" in (doc.get("env") or {}):
            p.append("%s: REHEARSAL is also set at job or workflow level" % jid)
    return p
if MIGRATE in docs:
    p = check_migrate(MIGRATE)
    out("RED" if p else "OK", "A4-migrate", "; ".join(p) if p else "%s shares the concurrency literal; no ssh bridge, ssh, upload-artifact or TF_LOG; two jobs with the exact literal environment/REHEARSAL pairs" % MIGRATE)
else:
    out("RED", "A4-migrate", "%s is absent from %s" % (MIGRATE, os.path.basename(wfdir)))

# (5)
t = docs.get(AWPI, (None, ""))[1]
out("RED" if "cf-account-migrate" in t else "OK", "A5-no-token",
    "%s %s the cf-account-migrate token" % (AWPI, "contains" if "cf-account-migrate" in t else "does not contain"))

# (6) exempt workflows outside the plan-only pair never plan the root, inline or one script deep.
TF_INVOKE = re.compile(
    r"(?:^|[;&|(!{]|\$\(|\bthen\b|\bdo\b|\belse\b|--)\s*"
    r"(?:(?:sudo|exec|command|time|nohup)\s+|(?:timeout|env)(?:\s+(?:-[uk]\s+\S+|-\S+|[A-Za-z_][A-Za-z0-9_]*=\S*|\d\S*))*\s+)*"
    r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*terraform\s+(?:-chdir=\S+\s+(?!-chdir=))?(?!-chdir=)"
    r"(?!(?:output|show|version|fmt|validate|providers|console|graph|init|-version|-help|--version|--help)\b)\S", re.M)
# Bare = not followed by a name character or by "/" (a subdir, a glob, or a trailing slash).
ROOT_BARE = re.compile(r"apps/web-platform/infra(?![A-Za-z0-9_./-])")
BASH_CALL = re.compile(r"(?:^|[;&|(]|\bthen\b|\bdo\b|&&|\|\|)\s*(?:timeout\s+\S+\s+)?bash\s+(?:-\S+\s+)*[\"']?([^\s\"';|&)]+\.sh)\b", re.M)
SOURCE_CALL = re.compile(r"(?:^|[;&|(]|\bthen\b|&&)\s*(?:source|\.)\s+[\"']?([^\s\"';|&)]+\.sh)\b", re.M)

def code_lines(t):
    return "\n".join(l for l in t.split("\n") if not l.lstrip().startswith("#"))

def repo_path(p):
    for pre in ("${GITHUB_WORKSPACE}/", "$GITHUB_WORKSPACE/", "${{ github.workspace }}/", "./"):
        if p.startswith(pre): p = p[len(pre):]
    if p.startswith("$") or p.startswith("/"):
        m = re.search(r"(?:^|/)((?:scripts|apps|tests|plugins|\.github)/.*)$", p)
        if not m: return None
        p = m.group(1)
    f = os.path.join(repo_root, p)
    return p if os.path.isfile(f) else None

def plans_root(text, shell_text):
    return bool(TF_INVOKE.search(shell_text)) and bool(ROOT_BARE.search(code_lines(text)))

bad6, n6, followed = [], 0, 0
for ex in sorted(EXEMPT - PLAN_ONLY):
    if ex not in texts: continue
    n6 += 1
    doc = docs.get(ex, (None, ""))[0]
    if doc is None:
        try: doc = yaml.load(texts[ex], Loader=Loader) or {}
        except yaml.YAMLError: doc = {}
    runs = [str(st.get("run") or "") for j in ((doc.get("jobs") or {}).values()) if isinstance(j, dict)
            for st in (j.get("steps") or []) if isinstance(st, dict)]
    run_nt = "\n".join(normal_text(r) for r in runs)
    if plans_root(texts[ex], run_nt):
        bad6.append("%s (inline)" % ex)
    for r in runs:
        for m in BASH_CALL.finditer(join_continuations(r)):
            rp = repo_path(m.group(1))
            if not rp: continue
            followed += 1
            st = open(os.path.join(repo_root, rp)).read()
            parts = [(rp, st)]
            for sm in SOURCE_CALL.finditer(code_lines(st)):
                sp = repo_path(sm.group(1))
                if sp and sp != rp: parts.append((sp, open(os.path.join(repo_root, sp)).read()))
            if plans_root("\n".join(x[1] for x in parts), "\n".join(normal_text(x[1]) for x in parts)):
                bad6.append("%s via bash %s (+ sourced %s)" % (ex, rp, [x[0] for x in parts[1:]]))
out("RED" if bad6 else "OK", "A6-exempt-no-root-planner",
    ("exempt workflows that plan the web-platform root: " + "; ".join(bad6[:5])) if bad6
    else "%d exempt non-plan-only workflows and %d bash-run repo scripts carry no root terraform invocation" % (n6, followed))
out("RED" if n6 < 8 else "OK", "A6-floor", "%d exempt non-plan-only workflows checked" % n6)
PY

EXEMPT_WF="$(bash -c 'source "$1"; printf "%s " "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$SCRIPT")"
PLAN_ONLY="$(bash -c 'source "$1"; printf "%s " "${CFAM_PLAN_ONLY_WORKFLOWS[@]}"' _ "$SCRIPT")"
EXEMPT_LIST="$(bash -c 'source "$1"; printf "%s " "${CFAM_EXEMPT_JOBS[@]}"' _ "$SCRIPT")"
if [[ -n "${EXEMPT_WF// /}" && -n "${PLAN_ONLY// /}" && -n "${EXEMPT_LIST// /}" ]]; then
  ok "scope lists read from the script: exempt=[${EXEMPT_WF% }] plan-only=[${PLAN_ONLY% }] exempt-jobs=[${EXEMPT_LIST% }]"
else
  no "scope lists could not be read from the script"
fi

mkdir -p "$WORK/cache"
analyze() { # <wfdir> <action> [exempt-workflows] [exempt-jobs] [plan-only] -> analyzer lines on stdout
  # ${N-...} without the colon: an explicit "" argument means an EMPTY list, not the default.
  CFAM_SCOPE_CACHE="$WORK/cache" python3 "$ANALYZER" "$1" "$2" "${3-$EXEMPT_WF}" "${5-$PLAN_ONLY}" "${4-$EXEMPT_LIST}" "$REPO" 2>&1
}

# ── the real tree ──────────────────────────────────────────────────────────────────────────
REAL_OUT="$WORK/real.out"
analyze "$WFDIR" "$ACTION" > "$REAL_OUT"
while IFS= read -r line; do
  kind="${line%% *}"; rest="${line#* }"
  case "$kind" in
    OK) ok "$rest" ;;
    RED) no "$rest" ;;
    NOTE|SKIP) printf '  [%s] %s\n' "$kind" "$rest" ;;
    *) no "analyzer emitted an unexpected line: $line" ;;
  esac
done < "$REAL_OUT"
for id in A1-unresolvable A1-unknown-planner A1-exempt-callers A1-plan-only-subset A1-floor A2-loader-first A2-floor A2-action-step A3-exempt-jobs A4-migrate A5-no-token A6-exempt-no-root-planner A6-floor; do
  grep -q "^OK $id " "$REAL_OUT" || grep -q "^RED $id " "$REAL_OUT" || no "check $id never ran"
done

# ── scanner controls: decoys are not commands, real forms are ───────────────────────────────
mkdir -p "$WORK/scan"
cat > "$WORK/scan/decoy.yml" <<'YML'
name: decoy
on: workflow_dispatch
env:
  INFRA_DIR: apps/web-platform/infra
jobs:
  decoy:
    runs-on: ubuntu-latest
    steps:
      - working-directory: ${{ env.INFRA_DIR }}
        run: |
          echo "::error::run terraform plan by hand; then terraform apply"
          # terraform apply -auto-approve
          printf 'The plan step runs `terraform plan`\n'
          cat <<EOF
          terraform state rm cloudflare_record.www
          EOF
          LEVER="Run a plan first; terraform apply tfplan"
YML
cat > "$WORK/scan/real.yml" <<'YML'
name: real
on: workflow_dispatch
env:
  INFRA_DIR: apps/web-platform/infra
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: |
          OUT="$(terraform -chdir=apps/web-platform/infra plan -no-color)"
  b:
    runs-on: ubuntu-latest
    steps:
      - working-directory: ${{ env.INFRA_DIR }}
        run: |
          doppler run --name-transformer tf-var -- \
            terraform apply tfplan
  c:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cd "$INFRA_DIR" && terraform state mv a b
YML
cp "$WFDIR/apply-web-platform-infra.yml" "$WORK/scan/"
SCAN_OUT="$(analyze "$WORK/scan" "$ACTION" "" "$EXEMPT_LIST" "")"
if grep -q '^OK A1-unknown-planner .*decoy' <<<"$SCAN_OUT" || grep -q "^RED A1-unknown-planner .*'decoy.yml'" <<<"$SCAN_OUT"; then
  no "scanner: quoted/commented/heredoc terraform text was derived as a command (decoy.yml)"
else
  ok "scanner: echo/printf/comment/heredoc/assignment terraform text is not a command"
fi
if grep -q "^RED A1-unknown-planner .*'real.yml'" <<<"$SCAN_OUT"; then
  ok "scanner: \$(terraform -chdir=…), a continued 'doppler run -- terraform' and 'cd \"\$INFRA_DIR\" &&' are commands"
else
  no "scanner: real.yml's three command forms were not derived ($(grep A1-unknown <<<"$SCAN_OUT"))"
fi

# ── mutation rows ──────────────────────────────────────────────────────────────────────────
# mirror <name>: a workflows dir of symlinks to the real files, so one file can be replaced.
mirror() {
  local d="$WORK/mut/$1"
  mkdir -p "$d/wf"
  for f in "$WFDIR"/*.yml "$WFDIR"/*.yaml; do [[ -e "$f" ]] && ln -s "$f" "$d/wf/$(basename "$f")"; done
  cp "$ACTION" "$d/action.yml"
  printf '%s' "$d"
}
# mut_wf <label> <expect-RED-id> <file> <sed-expr> [action|wf]
mut_row() {
  local label="$1" id="$2" file="$3" expr="$4" what="${5:-wf}" d src dst o
  d="$(mirror "$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')")"
  if [[ "$what" == action ]]; then src="$ACTION"; dst="$d/action.yml"; else src="$WFDIR/$file"; dst="$d/wf/$file"; rm -f "$dst"; fi
  sed -E "$expr" "$src" > "$dst.tmp" && mv "$dst.tmp" "$dst"
  if cmp -s "$src" "$dst"; then no "MUT $label: the mutation did not land (cmp identical)"; return; fi
  o="$(analyze "$d/wf" "$d/action.yml")"
  if grep -q "^RED $id " <<<"$o"; then ok "MUT $label: $id RED"; else no "MUT $label: $id stayed green ($(grep " $id " <<<"$o" | head -1))"; fi
}
AWPI=apply-web-platform-infra.yml
mut_row "an exempt workflow starts planning the root" A6-exempt-no-root-planner apply-github-infra.yml 's#^  INFRA_DIR: infra/github#  INFRA_DIR: apps/web-platform/infra#'
mut_row "a gated root's directory becomes unresolvable" A1-unresolvable cf-lb-overlay.yml      's#^  INFRA_DIR: apps/web-platform/infra#  INFRA_DIR: ${{ vars.SOME_DIR }}#'
mut_row "a root planner drops the loader entirely"  A1-unknown-planner  apply-deploy-pipeline-fix.yml 's#uses: \./\.github/actions/infra-credentials#uses: ./.github/actions/not-the-loader#'
mut_row "the loader is removed from one gated job"  A2-loader-first     "$AWPI"                '/^  apply:$/,/^  [a-z_]+:$/s#uses: \./\.github/actions/infra-credentials#uses: ./.github/actions/not-the-loader#'
mut_row "the loader step becomes conditional"       A2-loader-first     cf-lb-overlay.yml      's#^( +)uses: \./\.github/actions/infra-credentials$#\1uses: ./.github/actions/infra-credentials\n\1if: ${{ inputs.skip != true }}#'
mut_row "the loader step gets continue-on-error"    A2-loader-first     "$AWPI"                's#^( +)uses: \./\.github/actions/infra-credentials$#\1uses: ./.github/actions/infra-credentials\n\1continue-on-error: true#'
mut_row "the token lands in apply-web-platform-infra.yml" A5-no-token   "$AWPI"                '1s#^#\# see cf-account-migrate.yml\n#'
mut_row "predicate step made conditional"           A2-action-step      "" 's#^    - name: Cloudflare account migration in-progress gate \(\#12931\)$#&\n      if: ${{ github.job != '"'"'x'"'"' }}#' action
mut_row "predicate step exit masked"                A2-action-step      "" 's#--from-r2$#--from-r2 || true#' action
# S1 in block form: in a plain scalar a leading `!` is a YAML tag, so the bypass is `run: |` + `! bash …`.
mut_row "predicate exit negated (S1)"               A2-action-step      "" 's#^      run: (bash .*cf-account-migration-complete\.sh" --from-r2)$#      run: |\n        ! \1#' action
mut_row "predicate backgrounded (S2)"               A2-action-step      "" 's#^(      run: bash .*cf-account-migration-complete\.sh" --from-r2)$#\1 \&#' action
mut_row "predicate piped into cat (S3)"             A2-action-step      "" 's#^(      run: bash .*cf-account-migration-complete\.sh" --from-r2)$#\1 | cat#' action
mut_row "the migrate workflow is emptied"           A4-migrate          cf-account-migrate.yml '1,$d'
mut_row "predicate env interpolates the raw input"  A2-action-step      "" 's#CFAM_WEB_HOST_KEY: \$\{\{ github\.event\.inputs\.web_host_key \}\}#CFAM_WEB_HOST_KEY: ${{ inputs.web_host_key }}#' action
mut_row "predicate step dropped"                    A2-action-step      "" '/^    - name: Cloudflare account migration in-progress gate/,$d' action

# Script-list mutations: the lists come from the script, so drive the analyzer with mutated lists.
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF key-rotate.yml" "$EXEMPT_LIST")"
if grep -q "^RED A6-exempt-no-root-planner .*key-rotate.yml via bash scripts/key-rotate.sh" <<<"$o"; then ok "MUT exempt list gains key-rotate.yml: A6 RED via scripts/key-rotate.sh (+ the sourced inngest-key-rotate.sh)"; else no "MUT exempt list gains key-rotate.yml: stayed green ($(grep ' A6-exempt-no' <<<"$o"))"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF inngest-key-rotate.yml" "$EXEMPT_LIST")"
if grep -q "^RED A6-exempt-no-root-planner .*inngest-key-rotate.yml via bash scripts/inngest-key-rotate.sh" <<<"$o"; then ok "MUT exempt list gains inngest-key-rotate.yml: A6 RED via its script"; else no "MUT exempt list gains inngest-key-rotate.yml: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF apply-web-platform-infra.yml" "$EXEMPT_LIST")"
if grep -q "^RED A6-exempt-no-root-planner .*apply-web-platform-infra.yml (inline)" <<<"$o"; then ok "MUT exempt list gains apply-web-platform-infra.yml: A6 RED (inline root terraform)"; else no "MUT exempt list gains apply-web-platform-infra.yml: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF infra-validation.yml" "$EXEMPT_LIST")"
if grep -q "^RED A1-exempt-callers .*infra-validation.yml" <<<"$o"; then ok "MUT exempt list gains a non-caller: A1-exempt-callers RED"; else no "MUT exempt list gains a non-caller: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF" "$EXEMPT_LIST apply")"
if grep -q "^RED A3-exempt-jobs .*apply runs" <<<"$o"; then ok "MUT exempt list gains the planning job 'apply': A3-exempt-jobs RED"; else no "MUT exempt list gains 'apply': stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF" "$EXEMPT_LIST no_such_job")"
if grep -q "^RED A3-exempt-jobs .*no_such_job is not a job" <<<"$o"; then ok "MUT exempt list gains a stale name: A3-exempt-jobs RED"; else no "MUT exempt list gains a stale name: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$EXEMPT_WF" "$EXEMPT_LIST" "$PLAN_ONLY not-exempt.yml")"
if grep -q "^RED A1-plan-only-subset " <<<"$o"; then ok "MUT plan-only gains a name outside the exempt list: A1-plan-only-subset RED"; else no "MUT plan-only subset: stayed green"; fi

# (6) controls on synthesized trees: a subdir root and a read-only `terraform output` stay green,
# a bash-run script that applies the root goes red.
mkdir -p "$WORK/a6/wf" "$WORK/a6/repo/scripts"
cp "$WFDIR/$AWPI" "$WORK/a6/wf/"
cat > "$WORK/a6/repo/scripts/sub.sh" <<'SH'
# the parent root apps/web-platform/infra is read only through remote state
cd apps/web-platform/infra/sentry && terraform apply -auto-approve tfplan
SH
cat > "$WORK/a6/repo/scripts/out.sh" <<'SH'
terraform -chdir=apps/web-platform/infra init -backend=false
terraform -chdir=apps/web-platform/infra output -raw server_ip
SH
cat > "$WORK/a6/repo/scripts/lib.sh" <<'SH'
ROOT_DIR="${ROOT:-.}/apps/web-platform/infra"
SH
cat > "$WORK/a6/repo/scripts/root.sh" <<'SH'
source "$HERE/scripts/lib.sh"
run() { ( cd "$ROOT_DIR" && doppler run -- \
    terraform "$@" ); }
SH
for n in sub out root; do
  cat > "$WORK/a6/wf/x-$n.yml" <<YML
name: x
on: workflow_dispatch
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/infra-credentials
      - run: bash scripts/$n.sh apply
YML
done
a6() { CFAM_SCOPE_CACHE="$WORK/cache" python3 "$ANALYZER" "$WORK/a6/wf" "$ACTION" "$1" "" "$EXEMPT_LIST" "$WORK/a6/repo" 2>&1; }
if grep -q '^OK A6-exempt-no-root-planner ' <<<"$(a6 x-sub.yml)"; then ok "A6 control: a subdir apply with the root named only in a comment is not a root planner"; else no "A6 control: subdir script reddened ($(a6 x-sub.yml | grep A6-exempt))"; fi
if grep -q '^OK A6-exempt-no-root-planner ' <<<"$(a6 x-out.yml)"; then ok "A6 control: a root 'terraform init' + 'output' (read-only) is not a root planner"; else no "A6 control: read-only script reddened ($(a6 x-out.yml | grep A6-exempt))"; fi
if grep -q '^RED A6-exempt-no-root-planner .*x-root.yml via bash scripts/root.sh' <<<"$(a6 x-root.yml)"; then ok "A6: a bash-run script whose sourced lib names the bare root and runs terraform \"\$@\" is a root planner"; else no "A6: script-wrapped root planner not seen ($(a6 x-root.yml | grep A6-exempt))"; fi

# (i)/(ii): the predicate's own scope decision, deny by default.
scope_of() { CFAM_WORKFLOW_REF="example-org/example-repo/.github/workflows/$1@refs/heads/main" CFAM_JOB="${2:-x}" CFAM_EVENT_NAME=workflow_dispatch CFAM_WEB_HOST_KEY="" bash -c 'source "$1"; cfam_scope' _ "$SCRIPT" 2>/dev/null; }
for w in new-planner.yml key-rotate.yml inngest-key-rotate.yml; do
  if [[ "$(scope_of "$w")" == "gated full" ]]; then ok "scope: $w is gated full (deny by default)"; else no "scope: $w -> '$(scope_of "$w")', want 'gated full'"; fi
done
# Every named exempt workflow being exempt-workflow is B19 in cf-account-migration-complete.test.sh.

# (7) the job script carries no workflow-file list: it reads the predicate's exempt list.
JOB="$REPO/apps/web-platform/infra/scripts/cf-account-migrate-job.sh"
wf_tokens() { awk '!/^[[:space:]]*#/' "$1" | grep -oE '[A-Za-z0-9_-]+\.ya?ml' | sort -u | tr '\n' ' '; }
if [[ -f "$JOB" && -z "$(wf_tokens "$JOB")" ]]; then ok "the job script names no workflow file outside comments"; else no "the job script names workflow files: [$(wf_tokens "$JOB")]"; fi
sed 's/^readonly LIVE_STATUSES=/readonly GATED_WORKFLOWS=(apply-web-platform-infra.yml key-rotate.yml)\n&/' "$JOB" > "$WORK/job-mut.sh"
if ! cmp -s "$JOB" "$WORK/job-mut.sh" && [[ -n "$(wf_tokens "$WORK/job-mut.sh")" ]]; then ok "MUT a hand list in the job script: (7) RED"; else no "MUT a hand list in the job script: did not land or stayed green"; fi

# (4) against a synthesized cf-account-migrate.yml, so the check is exercised before the real one lands.
mig_fixture() { # <dir>
  mkdir -p "$1"
  cat > "$1/cf-account-migrate.yml" <<'YML'
name: cf-account-migrate
on:
  workflow_dispatch:
    inputs:
      migrate_phase: {type: choice, options: [redirects-dns, zone-rest]}
concurrency:
  group: terraform-apply-web-platform-host
  cancel-in-progress: false
jobs:
  cf_account_migrate_rehearsal:
    if: inputs.rehearsal
    runs-on: ubuntu-latest
    environment: infra-privileged
    steps:
      - run: echo "no ssh here; never ssh into a host"
      - env:
          REHEARSAL: "true"
        run: bash apps/web-platform/infra/scripts/cf-account-migrate-job.sh
  cf_account_migrate_apply:
    if: ${{ !inputs.rehearsal }}
    runs-on: ubuntu-latest
    environment: web-platform-infra-apply
    steps:
      - env:
          REHEARSAL: "false"
        run: bash apps/web-platform/infra/scripts/cf-account-migrate-job.sh
YML
  cp "$WFDIR/$AWPI" "$1/"
}
mig_fixture "$WORK/mig-ok"
o="$(analyze "$WORK/mig-ok" "$ACTION" "" "$EXEMPT_LIST" "")"
if grep -q '^OK A4-migrate ' <<<"$o"; then ok "A4 control: a conforming cf-account-migrate.yml fixture is green"; else no "A4 control: conforming fixture not green ($(grep A4 <<<"$o"))"; fi
mig_mut() { # <label> <sed-expr>
  local d
  d="$WORK/mig-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  mig_fixture "$d"
  sed -E "$2" "$WORK/mig-ok/cf-account-migrate.yml" > "$d/cf-account-migrate.yml"
  if cmp -s "$WORK/mig-ok/cf-account-migrate.yml" "$d/cf-account-migrate.yml"; then no "MUT A4 $1: did not land"; return; fi
  if analyze "$d" "$ACTION" "" "$EXEMPT_LIST" "" | grep -q '^RED A4-migrate '; then ok "MUT A4 $1: RED"; else no "MUT A4 $1: stayed green"; fi
}
mig_mut "concurrency group differs"   's#group: terraform-apply-web-platform-host#group: cf-migrate#'
mig_mut "cancel-in-progress true"     's#cancel-in-progress: false#cancel-in-progress: true#'
mig_mut "TF_LOG set"                  's#^(    steps:)$#    env:\n      TF_LOG: DEBUG\n\1#'
mig_mut "upload-artifact step"        's#^(    steps:)$#\1\n      - uses: actions/upload-artifact@v4#'
mig_mut "ssh bridge step"             's#^(    steps:)$#\1\n      - uses: ./.github/actions/cf-tunnel-ssh-bridge#'
mig_mut "an ssh command"              's#^      - run: echo "no ssh#      - run: ssh deploy@host true; echo "no ssh#'
mig_mut "apply environment literal swapped (W1)" 's#environment: web-platform-infra-apply#environment: infra-privileged#'
mig_mut "rehearsal environment literal swapped"  's#environment: infra-privileged#environment: web-platform-infra-apply#'
mig_mut "environment rendered from the input"    's#environment: web-platform-infra-apply#environment: ${{ inputs.rehearsal \&\& '"'"'infra-privileged'"'"' || '"'"'web-platform-infra-apply'"'"' }}#'
mig_mut "REHEARSAL literal swapped"              's#REHEARSAL: "false"#REHEARSAL: "true"#'
mig_mut "REHEARSAL rendered from the input"      's#REHEARSAL: "false"#REHEARSAL: ${{ inputs.rehearsal }}#'
mig_mut "apply if inverted"                      's#if: \$\{\{ !inputs\.rehearsal \}\}#if: inputs.rehearsal#'
mig_mut "a third job"                            's#^jobs:$#jobs:\n  extra:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"#'
mig_mut "one job collapses both legs"            '/^  cf_account_migrate_apply:$/,$d'

# ── verdict ────────────────────────────────────────────────────────────────────────────────
printf '\ntest-cf-account-migration-scope.sh: %s passed, %s failed (%s cases)\n' "$PASS" "$FAIL" "$CASES"
if (( PASS + FAIL != CASES )); then
  printf 'CONSERVATION FAILED: PASS(%s)+FAIL(%s) != CASES(%s)\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
MIN_ASSERTIONS=62
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s assertions ran, floor is %s\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
