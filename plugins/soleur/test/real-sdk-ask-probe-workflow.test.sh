#!/usr/bin/env bash
# Guards 1 and 2 (plus the AC6 / AC10 / AC18 / AC19 string and parity assertions) for the scheduled real-SDK
# ask-probe workflow (#10111 Part 1, ADR-284 amendment). Plan:
# knowledge-base/project/plans/2026-11-01-chore-scheduled-real-sdk-ask-probe-plan.md (Guard Contract).
#
# GUARD 1 - the workflow's push path filter covers the probe's decision-relevant inputs (depth 1): every file named
#   by ADR-284 Flip criterion 5 and every DIRECT local import of dev-probe-destroy-ask.ts and permission-callback.ts is
#   matched by on.push.paths or carries an explicit EXCLUDED row (with a reason) in the classification table below.
#   The filter is matched with a GitHub-glob matcher against the tracked + untracked file list, never by string
#   equality. This proves CONSISTENCY between the filter and the table, not integrity: review and the weekly cron are
#   the integrity layer (named residual in the ADR).
# GUARD 2 - workflow posture, read from the PARSED YAML (not grep over text): the key is exposed to exactly one step
#   of one job, only the filer job holds issues: write, no step can trace, pull_request cannot run for a fork or for
#   any change except an edit of the files that execute with the key.
#
# THE SUITE'S OWN DETECTOR IS NOT TRUSTED: the floors at the bottom are reported through printf + exit, never through
# ok()/no(); the tally machinery, the YAML loader, the import extractor and the glob matcher each have an instrument
# self-test; every mutation battery restores from a pristine copy and asserts that the mutation LANDED.
#
# PARITY GUARDS (D8): the runner's in_run_allowlist case patterns equal RULED_PUSH_PATHS minus the package files
#   (derived, not restated); the runner's PROBE_STEP_NAME equals the probe step's name: in the workflow; the job
#   outcome expression feeds steps.should-run.outputs.outcome so a run=false push reaches the filer as not-run, and the
#   runner's file-issue treats not-run as a no-op (driven for real against a refusing gh stub).
#
# Reads (declare in scripts/lib/test-affected-paths.sh): .github/workflows/scheduled-real-sdk-ask-probe.yml,
#   apps/web-platform/scripts/dev-probe-destroy-ask.ts, apps/web-platform/scripts/real-sdk-ask-probe.sh,
#   apps/web-platform/scripts/lib/probe-budget.ts, apps/web-platform/server/permission-callback.ts,
#   knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md,
#   infra/github/ruleset-ci-required.tf, scripts/required-checks.txt, plus the file LIST (git ls-files) and the
#   existence of every file named in the classification table.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

WF_REL=".github/workflows/scheduled-real-sdk-ask-probe.yml"
PROBE_REL="apps/web-platform/scripts/dev-probe-destroy-ask.ts"
export RSAP_PROBE_TS="$REPO_ROOT/$PROBE_REL"
PERM_REL="apps/web-platform/server/permission-callback.ts"
RUNNER_REL="apps/web-platform/scripts/real-sdk-ask-probe.sh"
BUDGET_REL="apps/web-platform/scripts/lib/probe-budget.ts"
ADR_REL="knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md"
RULESET_REL="infra/github/ruleset-ci-required.tf"
REQCHECKS_REL="scripts/required-checks.txt"

passes=0
fails=0
MUT_RUN=0
MUT_KILLED=0
FAILED=()

ok() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
no() { fails=$((fails + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

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

SCRATCH="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

# ---------------------------------------------------------------------------------------------------------------
# INSTRUMENT SELF-TEST 1: the tally machinery. A neutered ok()/no() must exit the suite, not pass it.
# ---------------------------------------------------------------------------------------------------------------
tally_probe="$( ( passes=0; fails=0; FAILED=(); ok a >/dev/null; no b >/dev/null; echo "$passes $fails ${#FAILED[@]}" ) )"
if [[ "$tally_probe" != "1 1 1" ]]; then
  printf '[FATAL] instrument self-test: ok()/no() tally is broken (got "%s", want "1 1 1")\n' "$tally_probe" >&2
  exit 1
fi

command -v python3 >/dev/null || { echo "[FATAL] python3 required" >&2; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "[FATAL] python3 PyYAML required" >&2; exit 1; }
command -v git >/dev/null || { echo "[FATAL] git required" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------------------------
# CONSTANTS THAT ARE THE RULING (CTO F2 / plan Phase 4). Editing the workflow's filter requires editing these in the
# same diff - consistency, not integrity.
# ---------------------------------------------------------------------------------------------------------------
read -r -d '' RULED_PUSH_PATHS <<'EOF' || true
apps/web-platform/package.json
apps/web-platform/package-lock.json
apps/web-platform/server/agent-runner-sandbox-config.ts
apps/web-platform/server/sandbox-hook.ts
apps/web-platform/server/agent-runner-query-options.ts
apps/web-platform/server/permission-callback.ts
apps/web-platform/server/destroy-ask-classifier.ts
apps/web-platform/server/destroy-ask-lane.ts
apps/web-platform/server/agent-env.ts
apps/web-platform/scripts/dev-probe-destroy-ask.ts
apps/web-platform/scripts/real-sdk-ask-probe.sh
apps/web-platform/scripts/lib/probe-budget.ts
plugins/soleur/hooks/**
.github/workflows/scheduled-real-sdk-ask-probe.yml
EOF

read -r -d '' RULED_PR_PATHS <<'EOF' || true
.github/workflows/scheduled-real-sdk-ask-probe.yml
apps/web-platform/scripts/dev-probe-destroy-ask.ts
apps/web-platform/scripts/real-sdk-ask-probe.sh
apps/web-platform/scripts/lib/probe-budget.ts
EOF

# CLASSIFICATION TABLE: every DIRECT local import of the probe and of permission-callback.ts (static, multi-line,
# dynamic) must be a row. IN = matched by on.push.paths. EXCLUDED|path|reason = deliberately not in the filter.
# Rows for files that are not direct imports are allowed (stale rows - a path that no longer exists - are RED).
read -r -d '' CLASSIFICATION_TABLE <<'EOF' || true
# --- decision logic that the filter must cover ---------------------------------------------------------------
IN|apps/web-platform/server/agent-runner-query-options.ts
IN|apps/web-platform/server/destroy-ask-lane.ts
IN|apps/web-platform/server/destroy-ask-classifier.ts
IN|apps/web-platform/server/permission-callback.ts
IN|apps/web-platform/scripts/lib/probe-budget.ts
# --- excluded on purpose (a change here is caught by the weekly cron; ruled by CTO F2, cost ceiling) ----------
EXCLUDED|apps/web-platform/server/logger.ts|logging factory, no permission decision; deliberate negative control of the matcher (in the closure, never in the filter)
EXCLUDED|apps/web-platform/server/permission-log.ts|decision telemetry writer, emits after the decision is made
EXCLUDED|apps/web-platform/server/observability.ts|Sentry/pino mirror helper, no permission decision
EXCLUDED|apps/web-platform/server/notifications.ts|notification payload types only
EXCLUDED|apps/web-platform/server/review-gate.ts|the probe stubs abortableReviewGate, so a change to this file is not observable to the probe (covered by the unit tests and the weekly cron)
EXCLUDED|apps/web-platform/server/sandbox.ts|workspace path containment helper for file tools, not the Bash lane
EXCLUDED|apps/web-platform/server/support-directive.ts|support-persona skill allowlist, not in the probe wiring
EXCLUDED|apps/web-platform/server/support-escalation.ts|support-persona denial helper, not in the probe wiring
EXCLUDED|apps/web-platform/server/tool-path-checker.ts|file-tool path checks, not the Bash lane
EXCLUDED|apps/web-platform/server/tool-pattern-checker.ts|file-tool glob checks, not the Bash lane
EXCLUDED|apps/web-platform/server/tool-tiers.ts|not a Bash-lane decider (assertAllowedToolsPreApprovalSafe blocks the Bash family independently); the sibling gated-tier probe dev-probe-approval-gate.ts is NOT scheduled anywhere (out of scope for #10111)
EXCLUDED|apps/web-platform/server/approval/gate-flow.ts|durable-approval slice (ADR-309), flag-gated, separate from the destroy-ask lane
EXCLUDED|apps/web-platform/server/approval/gate-types.ts|type declarations of the durable-approval slice
EXCLUDED|apps/web-platform/server/approval/tools.ts|tool list of the durable-approval slice
EXCLUDED|apps/web-platform/server/safe-bash.ts|safe-Bash allowlist grammar; the probe's control cases exercise it, a regression reaches the weekly cron (CANDIDATE to widen: see the PR notes)
EXCLUDED|apps/web-platform/server/permission-callback-bash-batch.ts|batch-grant cache container; the stale-grant case exercises it, a regression reaches the weekly cron (CANDIDATE to widen: see the PR notes)
EXCLUDED|apps/web-platform/server/workspace-mode.ts|persona/mode resolution input; the probe pins its own fixtures, a regression reaches the weekly cron (CANDIDATE to widen: see the PR notes)
EXCLUDED|apps/web-platform/lib/safety/redaction-allowlist.ts|display redaction of the command text, after the decision
EXCLUDED|apps/web-platform/lib/support-handoff.ts|support hand-off constant, not in the probe wiring
EXCLUDED|apps/web-platform/lib/types.ts|shared type declarations
EOF

# Measured floors (Phase 0.2). The extractor counts DISTINCT local specifiers (relative, or the @/ alias) after
# comment stripping, across static single-line, static multi-line, side-effect, re-export and dynamic forms.
#   probe at origin HEAD (before the probe-budget edit): 12 specifiers, 5 local. permission-callback.ts: 24 specifiers, 22 local.
#   probe in the working tree with the probe-budget import: 13 specifiers, 6 local.
# The floor for the probe is the stable lower bound (5): the probe-budget import is the one in-flight addition.
FLOOR_PROBE_LOCAL=5
FLOOR_PERM_LOCAL=22
FLOOR_ADR_FILES=6

printf '%s\n' "$RULED_PUSH_PATHS" > "$SCRATCH/ruled-push.txt"
printf '%s\n' "$RULED_PR_PATHS" > "$SCRATCH/ruled-pr.txt"
printf '%s\n' "$CLASSIFICATION_TABLE" > "$SCRATCH/table.txt"

# ---------------------------------------------------------------------------------------------------------------
# THE HELPER (python3 -I). One file so the mutation rows can mutate the helper itself (harness rows H1).
# ---------------------------------------------------------------------------------------------------------------
HELPER="$SCRATCH/helper.py"
cat > "$HELPER" <<'PYEOF'
import copy, os, re, subprocess, sys
import yaml

PINS = {
    'actions/checkout': '34e114876b0b11c390a56381ad16ebd13914f8d5',
    'oven-sh/setup-bun': '3d267786b128fe76c2f16a390aa2448b815359f3',
    'actions/setup-node': '49933ea5288caeca8642d1e84afbd3f7d6820020',
    'actions/upload-artifact': 'ea165f8d65b6e75b540449e92b4886f43607fa02',
}
LOCAL_ACTIONS = {'./.github/actions/anthropic-preflight'}
KEYREF = re.compile(r"secrets\s*(?:\.\s*ANTHROPIC_API_KEY\b|\[\s*['\"]ANTHROPIC_API_KEY['\"]\s*\])")
CRON = '17 9 * * 1'
# Shared group for push/schedule/dispatch; a pull_request self-test gets its own per-PR group so it never evicts the
# single pending main/cron run (D5).
GROUP_EXPR = "real-sdk-ask-probe${{ github.event_name == 'pull_request' && format('-pr-{0}', github.event.pull_request.number) || '' }}"
# Two worst-case passes: the whole-probe rerun runs inside the same step. The case count and the per-case timer are READ from the probe
# source (RSAP_PROBE_TS), never restated, so raising either without raising the step ceiling goes red.
def two_pass_min():
    p = os.environ.get('RSAP_PROBE_TS', '')
    t = open(p, encoding='utf-8').read() if p and os.path.exists(p) else ''
    mc = re.search(r'MIN_DEFAULT_CASES\s*=\s*([0-9]+)', t)
    mt = re.search(r'setTimeout\(\(\)\s*=>\s*abort\.abort\(\)\s*,\s*([0-9_]+)\)', t)
    if not (mc and mt):
        return None
    return -(-2 * int(mc.group(1)) * int(mt.group(1).replace('_', '')) // 60000)
TWO_PASS_MIN = two_pass_min()
SET_LINE = re.compile(r'^set(\s+(-[A-Za-z]+|pipefail|-o\s+pipefail))+\s*$')
XTRACE = [
    re.compile(r'(^|[\s;&|(])set\s+(-[A-Za-z]*x|[-+]o\s+xtrace)', re.M),
    re.compile(r'\b(bash|sh)\s+(-[A-Za-z]*x\b|-o\s+xtrace)'),
    re.compile(r'BASH_XTRACEFD|\bPS4='),
]
EXTS = ['.ts', '.tsx', '.mts', '.js', '.mjs', '.json']


def out(*a):
    print(*a)


# --- file list and the GitHub-glob matcher ----------------------------------------------------------------------
def repo_files(repo):
    names = []
    for cmd in (['git', 'ls-files'], ['git', 'ls-files', '--others', '--exclude-standard']):
        names += subprocess.run(cmd, cwd=repo, capture_output=True, text=True, check=True).stdout.split('\n')
    return sorted({n for n in names if n and os.path.exists(os.path.join(repo, n))})


def _rx(pat):
    i, res = 0, []
    while i < len(pat):
        c = pat[i]
        if pat.startswith('**/', i):
            res.append('(?:.*/)?'); i += 3
        elif pat.startswith('**', i):
            res.append('.*'); i += 2
        elif c == '*':
            res.append('[^/]*'); i += 1
        elif c == '?':
            res.append('[^/]'); i += 1
        elif c == '[':
            j = pat.find(']', i + 1)
            if j < 0:
                res.append(re.escape(c)); i += 1
            else:
                res.append(pat[i:j + 1]); i = j + 1
        else:
            res.append(re.escape(c)); i += 1
    return re.compile('^' + ''.join(res) + '$')


def gh_match(pat, path):
    return bool(_rx(pat).match(path))


def expand(entries, files):
    s = set()
    for e in entries:
        s.update(f for f in files if gh_match(e, f))
    return s


# --- the import extractor ---------------------------------------------------------------------------------------
def strip_comments(src):
    res, i, n, state = [], 0, len(src), None
    while i < n:
        c, two = src[i], src[i:i + 2]
        if state is None:
            if two == '//':
                state = 'line'; i += 2; continue
            if two == '/*':
                state = 'block'; i += 2; continue
            if c in '\'"`':
                state = c
            res.append(c); i += 1
        elif state == 'line':
            if c == '\n':
                state = None; res.append(c)
            i += 1
        elif state == 'block':
            if two == '*/':
                state = None; i += 2; continue
            if c == '\n':
                res.append(c)
            i += 1
        else:
            if c == '\\':
                res.append(src[i:i + 2]); i += 2; continue
            if c == state:
                state = None
            elif c == '\n' and state in '\'"':
                state = None  # a quote cannot span a line: a stray quote in a regex literal must not swallow the file
            res.append(c); i += 1
    return ''.join(res)


SPEC = r'''(['"])([^'"\n]+)\1'''
STATIC = re.compile(r'(?:^|[;{}\n])\s*(?:import|export)\s+(?:type\s+)?(?:[\w$*\s,{}]*?)\s*from\s*' + SPEC, re.S)
SIDE = re.compile(r'(?:^|[;{}\n])\s*import\s*' + SPEC)
DYN = re.compile(r'\bimport\s*\(\s*' + SPEC + r'\s*\)')


def specs_of(src):
    s = strip_comments(src)
    found = []
    for rx in (STATIC, SIDE, DYN):
        found += [m.group(2) for m in rx.finditer(s)]
    return found


def resolve(spec, base_rel, fset):
    if spec.startswith('@/'):
        p = 'apps/web-platform/' + spec[2:]
    else:
        p = os.path.normpath(os.path.join(os.path.dirname(base_rel), spec))
    for cand in [p] + [p + e for e in EXTS] + [p + '/index' + e for e in EXTS]:
        if cand in fset:
            return cand
    return None


def local_imports(path, as_rel, fset):
    src = open(path, encoding='utf-8').read()
    sp = specs_of(src)
    loc = sorted({x for x in sp if x.startswith(('./', '../', '@/'))})
    resolved, unresolved = [], []
    for x in loc:
        r = resolve(x, as_rel, fset)
        (resolved if r else unresolved).append(r or x)
    return len(set(sp)), loc, sorted(set(resolved)), unresolved


# --- YAML ------------------------------------------------------------------------------------------------------
def load_wf(path):
    doc = yaml.safe_load(open(path, encoding='utf-8').read())
    return doc


def on_of(doc):
    if not isinstance(doc, dict):
        return {}
    v = doc.get('on', doc.get(True))
    return v if isinstance(v, dict) else {}


def walk(node, path=()):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, path + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, path + (i,))
    elif isinstance(node, str):
        yield path, node


def strip_sh_comments(body):
    return '\n'.join(l for l in body.split('\n') if not l.lstrip().startswith('#'))


# --- Guard 2: posture ----------------------------------------------------------------------------------------
def cmd_posture(wf):
    v = []

    def bad(code, detail=''):
        v.append('VIOLATION %s %s' % (code, detail))

    doc = load_wf(wf) if os.path.exists(wf) and os.path.getsize(wf) > 0 else None
    if not isinstance(doc, dict) or not doc:
        bad('PARSE-EMPTY', 'workflow absent or an empty document')
        doc = {}
    jobs = doc.get('jobs') if isinstance(doc.get('jobs'), dict) else {}
    on = on_of(doc)
    keyrefs = [p for p, s in walk(doc) if KEYREF.search(s)]
    run_steps = 0
    uses_n = 0

    # triggers
    if set(on.keys()) != {'push', 'schedule', 'workflow_dispatch', 'pull_request'}:
        bad('TRIGGER-SET', 'on keys = %s' % sorted(map(str, on.keys())))
    push = on.get('push') if isinstance(on.get('push'), dict) else {}
    if push.get('branches') != ['main']:
        bad('PUSH-BRANCHES', str(push.get('branches')))
    pr = on.get('pull_request') if isinstance(on.get('pull_request'), dict) else {}
    pr_paths = pr.get('paths')
    ruled_pr = [l for l in open(os.environ['RULED_PR']).read().split('\n') if l.strip()]
    if not isinstance(pr_paths, list) or sorted(pr_paths) != sorted(ruled_pr):
        bad('PR-PATHS', 'pull_request.paths = %s' % pr_paths)
    if any(k in pr for k in ('paths-ignore', 'branches-ignore')):
        bad('PR-FILTER-SHAPE', 'paths-ignore/branches-ignore on pull_request')
    sch = on.get('schedule')
    if not (isinstance(sch, list) and len(sch) == 1 and isinstance(sch[0], dict) and sch[0].get('cron') == CRON):
        bad('CRON-SET', 'schedule = %s' % sch)

    # concurrency
    cc = doc.get('concurrency')
    if not (isinstance(cc, dict) and cc.get('group') == GROUP_EXPR and cc.get('cancel-in-progress') is False):
        bad('CONCURRENCY', str(cc))

    # AC6: workflow name
    nm = str(doc.get('name', '')).lower()
    if 'host-only' not in nm or 'production arrival not observed' not in nm:
        bad('NAME-RESIDUAL', 'workflow name lacks the host-only residual and "production arrival not observed"')

    # permissions
    top = doc.get('permissions')
    if top != {'contents': 'read'}:
        bad('PERM-TOP', str(top))
    for jn, j in jobs.items():
        jp = j.get('permissions') if isinstance(j, dict) else None
        if not isinstance(jp, dict):
            bad('PERM-JOB-MISSING', jn)
            continue
        writes = {k: val for k, val in jp.items() if val != 'read'}
        allowed = {'issues': 'write'} if jn == 'file-issue' else {}
        if writes != allowed:
            bad('PERM-JOB-WRITE', '%s writes %s' % (jn, writes))
    if isinstance(jobs.get('probe'), dict) and jobs['probe'].get('permissions') != {'contents': 'read', 'actions': 'read'}:
        bad('PERM-PROBE', str(jobs['probe'].get('permissions')))
    if isinstance(jobs.get('file-issue'), dict) and jobs['file-issue'].get('permissions') != {'contents': 'read', 'issues': 'write'}:
        bad('PERM-FILER', str(jobs['file-issue'].get('permissions')))

    # secrets scope
    probe_env_hits, preflight_with_hits = 0, 0
    for p, s in walk(doc):
        if re.search(r"toJSON\(\s*secrets|secrets\s*\[\s*[^'\"\s]", s):
            bad('SECRETS-DYNAMIC', str(p))
        for m in re.finditer(r'secrets\s*\.\s*([A-Za-z_]+)', s):
            if m.group(1) not in ('ANTHROPIC_API_KEY', 'GITHUB_TOKEN'):
                bad('SECRET-OTHER', '%s %s' % (m.group(1), p))
    for p in keyrefs:
        step = None
        if len(p) >= 5 and p[0] == 'jobs' and p[1] == 'probe' and p[2] == 'steps' and isinstance(p[3], int):
            try:
                step = jobs['probe']['steps'][p[3]]
            except Exception:
                step = None
        if step and p[4:] == ('env', 'ANTHROPIC_API_KEY') and step.get('id') == 'probe':
            probe_env_hits += 1
        elif step and p[4:] == ('with', 'anthropic-api-key') and step.get('uses') == './.github/actions/anthropic-preflight':
            preflight_with_hits += 1
        else:
            bad('KEY-SCOPE', 'secrets.ANTHROPIC_API_KEY referenced at %s' % '/'.join(map(str, p)))
    if probe_env_hits != 1:
        bad('KEY-PROBE-STEP', 'key reaches %d probe-step env blocks (want exactly 1)' % probe_env_hits)
    if preflight_with_hits != 1:
        bad('KEY-PREFLIGHT', 'key reaches %d preflight inputs (want exactly 1)' % preflight_with_hits)

    def env_blocks():
        yield ('workflow',), doc.get('env')
        for jn, j in jobs.items():
            if not isinstance(j, dict):
                continue
            yield ('jobs', jn), j.get('env')
            for i, s in enumerate(j.get('steps') or []):
                if isinstance(s, dict):
                    yield ('jobs', jn, 'steps', i, s.get('id') or s.get('name')), s.get('env')

    for loc, env in env_blocks():
        if isinstance(env, dict) and 'ANTHROPIC_API_KEY' in env:
            is_probe = len(loc) == 5 and loc[1] == 'probe' and loc[4] == 'probe'
            if not is_probe:
                bad('KEY-ENV-SCOPE', 'ANTHROPIC_API_KEY in env at %s' % '/'.join(map(str, loc)))

    # jobs
    if not isinstance(jobs.get('probe'), dict):
        bad('JOB-MISSING', 'probe')
    if not isinstance(jobs.get('file-issue'), dict):
        bad('JOB-MISSING', 'file-issue')
    probe = jobs.get('probe') if isinstance(jobs.get('probe'), dict) else {}
    filer = jobs.get('file-issue') if isinstance(jobs.get('file-issue'), dict) else {}
    pif = str(probe.get('if', ''))
    for needle in ("github.event.pull_request.head.repo.full_name == github.repository", "github.actor != 'dependabot[bot]'", "github.event_name != 'pull_request'"):
        if needle not in pif:
            bad('PROBE-IF', 'probe job if: lacks %r' % needle)
    fif = str(filer.get('if', ''))
    for needle in ('always()', "github.event_name != 'pull_request'", "github.ref == 'refs/heads/main'", "needs.probe.result != 'skipped'"):
        if needle not in fif:
            bad('FILER-IF', 'file-issue if: lacks %r' % needle)
    nd = filer.get('needs')
    if nd not in ('probe', ['probe']):
        bad('FILER-NEEDS', str(nd))
    if probe.get('runs-on') != 'ubuntu-latest':
        bad('PROBE-RUNNER', str(probe.get('runs-on')))
    if probe.get('name') != 'probe':
        bad('PROBE-NAME', 'the probe job name must stay probe: the runner baseline lookup selects .jobs[] by name == probe (got %r)' % (probe.get('name'),))
    jt, sidx = probe.get('timeout-minutes'), {}
    for i, s in enumerate(probe.get('steps') or []):
        if isinstance(s, dict) and s.get('id'):
            sidx[s['id']] = i
    for need in ('should-run', 'preflight', 'probe', 'skip'):
        if need not in sidx:
            bad('PROBE-STEP-MISSING', need)
    if all(k in sidx for k in ('should-run', 'preflight', 'probe', 'skip')):
        if not (sidx['should-run'] < sidx['preflight'] < sidx['probe'] and sidx['preflight'] < sidx['skip']):
            bad('PROBE-STEP-ORDER', str(sidx))
        ps = probe['steps'][sidx['probe']]
        pst = ps.get('timeout-minutes')
        if not (isinstance(jt, int) and isinstance(pst, int) and 0 < pst < jt):
            bad('TIMEOUTS', 'job=%s probe-step=%s' % (jt, pst))
        elif TWO_PASS_MIN is None:
            bad('TIMEOUT-DERIVE', 'could not read MIN_DEFAULT_CASES and the per-case abort timer from the probe source')
        elif pst < TWO_PASS_MIN:
            bad('TIMEOUT-TWO-PASS', 'probe-step=%s is below two worst-case passes (%d min)' % (pst, TWO_PASS_MIN))
        elif jt - pst < 5:
            bad('TIMEOUT-HEADROOM', 'job=%s leaves under 5 min over the probe step (%s) for setup and upload' % (jt, pst))
        pif2 = str(ps.get('if', ''))
        for needle in ("steps.should-run.outputs.run == 'true'", "steps.preflight.outputs.ok == 'true'"):
            if needle not in pif2:
                bad('PROBE-STEP-IF', 'probe step if: lacks %r' % needle)
        if 'real-sdk-ask-probe.sh run' not in str(ps.get('run', '')):
            bad('PROBE-STEP-RUN', 'probe step does not invoke the runner `run` subcommand')
        if 'ANTHROPIC_API_KEY' in str(ps.get('run', '')):
            bad('KEY-IN-RUN', 'probe step run body names the key')
        sk = probe['steps'][sidx['skip']]
        if "steps.preflight.outputs.ok == 'false'" not in str(sk.get('if', '')):
            bad('SKIP-STEP-IF', str(sk.get('if')))
        if 'should-run' in sidx and 'real-sdk-ask-probe.sh should-run' not in str(probe['steps'][sidx['should-run']].get('run', '')):
            bad('SHOULD-RUN-STEP', 'should-run step does not invoke the runner')
    outs = probe.get('outputs') if isinstance(probe.get('outputs'), dict) else {}
    for o in ('outcome', 'reason', 'cost'):
        if o not in outs:
            bad('PROBE-OUTPUT-MISSING', o)
    # D1/D8d: the job outcome is the FIRST non-empty of the probe, skip and should-run step outcomes, so a run=false
    # push (should-run emits outcome=not-run) reaches the filer instead of an empty outcome (a false blind issue).
    oexpr = str(outs.get('outcome', ''))
    om = re.fullmatch(r'\$\{\{\s*(.*?)\s*\}\}', oexpr, re.S)
    terms = [t.strip() for t in om.group(1).split('||')] if om else []

    def sim(vals):
        for t in terms:
            mm = re.fullmatch(r'steps\.([A-Za-z0-9_-]+)\.outputs\.outcome', t)
            if not mm:
                return 'UNPARSEABLE'
            if vals.get(mm.group(1), ''):
                return vals[mm.group(1)]
        return ''
    for vals, want in (({'should-run': 'not-run'}, 'not-run'), ({'skip': 'skipped'}, 'skipped'), ({'probe': 'pass'}, 'pass'),
                       ({'probe': 'fail', 'skip': 'skipped'}, 'fail'), ({}, '')):
        got = sim(vals)
        if got != want:
            bad('OUTCOME-COMPOSE', 'step outputs %s yield job outcome %r, want %r (expression %r)' % (vals, got, want, oexpr))
    if filer.get('steps') and not any(isinstance(s, dict) and (s.get('env') or {}).get('PROBE_OUTCOME') == '${{ needs.probe.outputs.outcome }}' for s in filer['steps']):
        bad('FILER-OUTCOME-WIRE', 'no file-issue step passes PROBE_OUTCOME from needs.probe.outputs.outcome')

    # steps
    for jn, j in jobs.items():
        if not isinstance(j, dict):
            continue
        if 'uses' in j:
            bad('REUSABLE-WORKFLOW', jn)
        for i, s in enumerate(j.get('steps') or []):
            if not isinstance(s, dict):
                bad('STEP-SHAPE', '%s/%d' % (jn, i)); continue
            where = '%s/%s' % (jn, s.get('id') or s.get('name') or i)
            if 'uses' in s:
                uses_n += 1
                u = str(s['uses'])
                if u in LOCAL_ACTIONS:
                    pass
                elif '@' in u:
                    name, ref = u.split('@', 1)
                    if not re.fullmatch(r'[0-9a-f]{40}', ref):
                        bad('USES-NOT-SHA', '%s uses %s' % (where, u))
                    elif PINS.get(name) != ref:
                        bad('USES-PIN', '%s uses %s (not a pin already in use in this repo)' % (where, u))
                else:
                    bad('USES-NOT-SHA', '%s uses %s' % (where, u))
                if u.startswith('actions/checkout@'):
                    w = s.get('with') or {}
                    if w.get('persist-credentials') is not False:
                        bad('CHECKOUT-CREDS', where)
            if 'run' in s:
                run_steps += 1
                body = str(s['run'])
                if s.get('shell') != 'bash':
                    bad('SHELL', '%s shell=%r' % (where, s.get('shell')))
                lines = [l for l in body.split('\n') if l.strip() and not l.lstrip().startswith('#')]
                if not lines or not SET_LINE.match(lines[0].strip()):
                    bad('SET-LINE', '%s first command is not an explicit set line' % where)
                code = strip_sh_comments(body)
                for rx in XTRACE:
                    if rx.search(code):
                        bad('XTRACE', where)
                if '${{' in body:
                    bad('EXPR-IN-RUN', '%s interpolates an expression into a run body' % where)
                if jn != 'probe' or s.get('id') != 'probe':
                    if 'ANTHROPIC_API_KEY' in body:
                        bad('KEY-IN-RUN', where)
            if s.get('shell') not in (None, 'bash'):
                bad('SHELL', '%s shell=%r' % (where, s.get('shell')))
    # probe-job content
    ptext = '\n'.join(str(s.get('run', '')) for s in (probe.get('steps') or []) if isinstance(s, dict))
    if 'npm ci --ignore-scripts' not in ptext:
        bad('NPM-CI', 'probe job lacks `npm ci --ignore-scripts`')
    for needle in ('bubblewrap', 'socat', 'kernel.apparmor_restrict_unprivileged_userns=0'):
        if needle not in ptext:
            bad('SANDBOX-SETUP', 'probe job lacks %s' % needle)
    ups = [s for s in (probe.get('steps') or []) if isinstance(s, dict) and str(s.get('uses', '')).startswith('actions/upload-artifact@')]
    if len(ups) != 1:
        bad('ARTIFACT', 'upload-artifact steps = %d' % len(ups))
    else:
        u = ups[0]
        if 'always()' not in str(u.get('if', '')) or (u.get('with') or {}).get('retention-days') != 90 \
                or 'real-sdk-ask-probe-' not in str((u.get('with') or {}).get('name', '')):
            bad('ARTIFACT', 'upload-artifact must be if: always(), retention-days 90, name real-sdk-ask-probe-*')
    ftext = '\n'.join(str(s.get('run', '')) for s in (filer.get('steps') or []) if isinstance(s, dict))
    if 'real-sdk-ask-probe.sh file-issue' not in ftext:
        bad('FILER-RUN', 'file-issue job does not invoke the runner `file-issue` subcommand')

    out('FACT keyrefs=%d' % len(keyrefs))
    out('FACT jobs=%d' % len(jobs))
    out('FACT run_steps=%d' % run_steps)
    out('FACT uses=%d' % uses_n)
    for line in v:
        out(line)


def runner_allowlist(runner):
    """Case patterns of the runner's in_run_allowlist() arms that `return 0`, normalised to GitHub-glob spelling."""
    t = open(runner, encoding='utf-8').read() if os.path.exists(runner) else ''
    m = re.search(r'^in_run_allowlist\(\)\s*\{(.*?)^\}', t, re.S | re.M)
    pats = set()
    for line in (m.group(1) if m else '').split('\n'):
        a = re.match(r'^\s*([^#\s)][^)]*?)\)\s*return\s+0\b', line)
        if a:
            for p in a.group(1).split('|'):
                p = p.strip()
                pats.add(p[:-2] + '/**' if p.endswith('/*') and not p.endswith('/**') else p)
    return pats


def cmd_allowlist(runner, ruled):
    v = []
    want = {l.strip() for l in open(ruled).read().split('\n') if l.strip()}
    want = {e for e in want if os.path.basename(e) not in ('package.json', 'package-lock.json')}
    got = runner_allowlist(runner)
    if not got:
        v.append('VIOLATION ALLOWLIST-UNREADABLE the runner has no in_run_allowlist() arms that return 0')
    for e in sorted(want - got):
        v.append('VIOLATION ALLOWLIST-MISSING %s is ruled but the runner in_run_allowlist does not return 0 for it' % e)
    for e in sorted(got - want):
        v.append('VIOLATION ALLOWLIST-EXTRA %s is in the runner in_run_allowlist but not in the ruled push paths' % e)
    out('FACT patterns=%d' % len(got))
    out('FACT ruled=%d' % len(want))
    for line in v:
        out(line)


def cmd_stepname(wf, runner):
    v = []
    t = open(runner, encoding='utf-8').read() if os.path.exists(runner) else ''
    m = re.search(r'^PROBE_STEP_NAME=(?:"([^"\n]*)"|\'([^\'\n]*)\')\s*(?:#.*)?$', t, re.M)
    rname = (m.group(1) if m and m.group(1) is not None else (m.group(2) if m else '')) or ''
    if not rname:
        v.append('VIOLATION STEPNAME-RUNNER-UNREADABLE the runner has no PROBE_STEP_NAME="..." constant')
    doc = load_wf(wf) if os.path.exists(wf) and os.path.getsize(wf) > 0 else {}
    jobs = doc.get('jobs') if isinstance(doc.get('jobs'), dict) else {}
    allsteps = [s for s in ((jobs.get('probe') or {}).get('steps') or []) if isinstance(s, dict)]
    steps = [s for s in allsteps if s.get('id') == 'measured']
    wname = str(steps[0].get('name', '')) if len(steps) == 1 else ''
    if not wname:
        v.append('VIOLATION STEPNAME-WF-UNREADABLE the workflow has no single baseline-marker step (id: measured) with a name:')
    if rname and wname and rname != wname:
        v.append('VIOLATION STEPNAME-PARITY runner PROBE_STEP_NAME=%r but the workflow baseline-marker step name: is %r' % (rname, wname))
    if len(steps) == 1:
        cond = re.sub(r'\s+', ' ', str(steps[0].get('if', '')))
        # The marker may run only on an explicit verdict: always() (so it runs after a failing probe step) AND outcome pass or fail, nothing else.
        want = "always() && (steps.probe.outputs.outcome == 'pass' || steps.probe.outputs.outcome == 'fail')"
        if cond != want:
            v.append('VIOLATION STEPNAME-MEASURED-IF the baseline-marker step if: must be always() && (outcome == pass || outcome == fail) and nothing else, got %r' % cond)
        # The marker must be a plain step that cannot fail or be waved through: no continue-on-error, and a run body without `exit`.
        if steps[0].get('continue-on-error') not in (None, False) or re.search(r'\bexit\b', str(steps[0].get('run', ''))):
            v.append('VIOLATION STEPNAME-MEASURED-BODY the baseline-marker step must not set continue-on-error or call exit')
        ids = [s.get('id') for s in allsteps]
        if 'probe' not in ids or ids.index('probe') > ids.index('measured'):
            v.append('VIOLATION STEPNAME-MEASURED-ORDER the baseline-marker step must come after the probe step')
    out('FACT stepname=%s' % wname)
    for line in v:
        out(line)


def cmd_envnames(wf):
    doc = load_wf(wf)
    names = set()
    for jn, j in doc['jobs'].items():
        for s in j.get('steps') or []:
            r = str(s.get('run', ''))
            if re.search(r'real-sdk-ask-probe\.sh\s+(should-run|run|file-issue)', r):
                for k in (s.get('env') or {}):
                    names.add(k)
    for n in sorted(names):
        out('ENVNAME %s' % n)


def cmd_stepenv(wf, step_id):
    """Print KEY=VALUE for the env of a step, expressions replaced by x, for the behavioural run."""
    doc = load_wf(wf)
    for j in doc['jobs'].values():
        for s in j.get('steps') or []:
            if s.get('id') == step_id:
                for k, val in (s.get('env') or {}).items():
                    out('%s=%s' % (k, re.sub(r'\$\{\{.*?\}\}', 'x', str(val))))
                return


def cmd_steprun(wf, step_id):
    doc = load_wf(wf)
    for j in doc['jobs'].values():
        for s in j.get('steps') or []:
            if s.get('id') == step_id:
                sys.stdout.write(re.sub(r'\$\{\{.*?\}\}', 'x', str(s.get('run', ''))))
                return
    sys.exit(4)


def cmd_allruns(wf, dest):
    doc = load_wf(wf)
    n = 0
    for jn, j in doc['jobs'].items():
        for i, s in enumerate(j.get('steps') or []):
            if 'run' in s:
                n += 1
                open(os.path.join(dest, 'run-%s-%d.sh' % (jn, i)), 'w').write(re.sub(r'\$\{\{.*?\}\}', 'x', str(s['run'])) + '\n')
    out('FACT runs=%d' % n)


# --- Guard 1: coverage ------------------------------------------------------------------------------------------
def adr_files(adr, fset):
    text = open(adr, encoding='utf-8').read()
    m = re.search(r'^## Flip checklist\s*$(.*?)(?=^## )', text, re.S | re.M)
    item = ''
    if m:
        m5 = re.search(r'^5\. (.*?)(?=^6\. )', m.group(1), re.S | re.M)
        item = m5.group(1) if m5 else ''
    found, unmatched = set(), []
    for t in re.findall(r'`([^`\s]+)`', item):
        if '/' not in t:
            continue
        if t.startswith('server/'):
            t = 'apps/web-platform/' + t
        elif not t.startswith(('apps/', 'plugins/', 'scripts/', '.github/')):
            continue
        hit = [f for f in fset if gh_match(t, f)]
        if not hit:
            unmatched.append(t)
        found.update(hit)
    return sorted(found), unmatched


def parse_table(path, bad):
    rows, seen = {}, set()
    for ln, raw in enumerate(open(path).read().split('\n'), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('|')
        if parts[0] == 'IN' and len(parts) == 2 and parts[1].strip():
            kind, p, reason = 'IN', parts[1].strip(), ''
        elif parts[0] == 'EXCLUDED' and len(parts) >= 2 and parts[1].strip():
            kind, p, reason = 'EXCLUDED', parts[1].strip(), '|'.join(parts[2:]).strip()
        else:
            bad('TABLE-MALFORMED', 'line %d: %s' % (ln, line)); continue
        if p in seen:
            bad('TABLE-DUP', p); continue
        seen.add(p)
        rows[p] = (kind, reason)
    return rows


def cmd_cover(repo, wf, table, ruled, probe, probe_as, perm, perm_as, adr):
    v = []

    def bad(code, detail=''):
        v.append('VIOLATION %s %s' % (code, detail))

    files = repo_files(repo)
    fset = set(files)
    doc = load_wf(wf) if os.path.exists(wf) and os.path.getsize(wf) > 0 else {}
    push = on_of(doc).get('push') if isinstance(on_of(doc).get('push'), dict) else {}
    entries = push.get('paths') if isinstance(push.get('paths'), list) else []
    if not entries:
        bad('PUSH-PATHS-EMPTY', 'no on.push.paths array in the parsed workflow')
    ruled_entries = [l for l in open(ruled).read().split('\n') if l.strip()]

    for e in entries:
        if not any(gh_match(e, f) for f in files):
            bad('DEAD-ENTRY', 'on.push.paths entry %s matches no tracked or untracked file' % e)
    sel, want = expand(entries, files), expand(ruled_entries, files)
    for f in sorted(want - sel):
        bad('RULED-MISSING', '%s is in the ruled set but not selected by on.push.paths' % f)
    for f in sorted(sel - want):
        bad('RULED-EXTRA', '%s is selected by on.push.paths but is not in the ruled set' % f)

    rows = parse_table(table, bad)
    for p, (kind, reason) in rows.items():
        if p not in fset:
            bad('TABLE-STALE', '%s is a table row but no such file exists' % p)
        if kind == 'EXCLUDED' and len(reason) < 8:
            bad('EXCLUDED-NO-REASON', p)
        matched = any(gh_match(e, p) for e in entries)
        if kind == 'IN' and not matched:
            bad('IN-NOT-MATCHED', '%s is classified IN but no on.push.paths entry matches it' % p)
        if kind == 'EXCLUDED' and matched:
            bad('EXCLUDED-MATCHED', '%s is classified EXCLUDED but the filter matches it' % p)

    facts = {}
    direct = {}
    for label, path, as_rel in (('probe', probe, probe_as), ('perm', perm, perm_as)):
        total, loc, resolved, unresolved = local_imports(path, as_rel, fset)
        facts[label + '_total'], facts[label + '_local'] = total, len(loc)
        for u in unresolved:
            bad('UNRESOLVED-IMPORT', '%s imports %s which resolves to no file' % (as_rel, u))
        for r in resolved:
            direct.setdefault(r, []).append(as_rel)
    for r, by in sorted(direct.items()):
        if r not in rows:
            bad('NOT-IN-TABLE', '%s (direct import of %s) is neither matched-and-classified nor EXCLUDED in the table' % (r, ','.join(sorted(set(by)))))

    af, unmatched = adr_files(adr, fset) if os.path.exists(adr) else ([], [])
    facts['adr_files'] = len(af)
    for t in unmatched:
        bad('ADR-TOKEN-UNMATCHED', t)
    for f in af:
        if not any(gh_match(e, f) for e in entries) and not (f in rows and rows[f][0] == 'EXCLUDED'):
            bad('ADR-FILE-UNCOVERED', '%s is named by ADR-284 criterion 5 but is neither matched by on.push.paths nor an EXCLUDED row' % f)
    facts['push_entries'] = len(entries)
    facts['direct_imports'] = len(direct)
    for k, val in facts.items():
        out('FACT %s=%d' % (k, val))
    for line in v:
        out(line)


def cmd_imports(path, as_rel, repo):
    fset = set(repo_files(repo))
    total, loc, resolved, unresolved = local_imports(path, as_rel, fset)
    out('# total=%d local=%d' % (total, len(loc)))
    for r in resolved:
        out(r)
    for u in unresolved:
        out('UNRESOLVED ' + u)


def cmd_match(pat, path):
    out('yes' if gh_match(pat, path) else 'no')


# --- Guard 1 row 7 / AC18: doc-vs-code parity ---------------------------------------------------------------
def cmd_parity(wf, adr, budget):
    v = []

    def bad(code, detail=''):
        v.append('VIOLATION %s %s' % (code, detail))

    doc = load_wf(wf) if os.path.exists(wf) and os.path.getsize(wf) > 0 else {}
    push = on_of(doc).get('push') if isinstance(on_of(doc).get('push'), dict) else {}
    entries = push.get('paths') if isinstance(push.get('paths'), list) else []
    text = open(adr, encoding='utf-8').read() if os.path.exists(adr) else ''
    m = re.search(r'^## Amendment 2026-11-01 \(#10111, Part 1\)\s*$(.*?)(?=^## |\Z)', text, re.S | re.M)
    sect = m.group(1) if m else ''
    if not sect:
        bad('AMENDMENT-ABSENT', 'ADR-284 has no "## Amendment 2026-11-01 (#10111, Part 1)" section')
    nent = 0
    for e in entries:
        nent += 1
        tail = e[len('apps/web-platform/'):] if e.startswith('apps/web-platform/') else e
        tail = tail[:-3] if tail.endswith('/**') else tail
        tail = os.path.basename(tail) if tail.startswith('.github/workflows/') else tail
        if tail not in sect:
            bad('PARITY-ENTRY', 'on.push.paths entry %s is not listed in the ADR-284 amendment' % e)
    b = open(budget).read() if os.path.exists(budget) else ''
    mb = re.search(r'RUN_BUDGET_USD\s*(?::\s*number\s*)?=\s*([0-9]+(?:\.[0-9]+)?)', b)
    if not mb:
        bad('BUDGET-UNREADABLE', 'no RUN_BUDGET_USD constant in the budget helper')
        cap = None
    else:
        cap = mb.group(1)
        # anchored on the phrase that states the figure: a bare "$4" elsewhere in the section must not satisfy it
        if not re.search(r'Spend\s+cap\s+(?:\*\*)?\$' + re.escape(cap) + r'(?![0-9]|\.[0-9])(?:\*\*)?\s+per\s+run', sect):
            bad('PARITY-CAP', 'the amendment does not state "Spend cap $%s per run" (RUN_BUDGET_USD=%s)' % (cap, cap))
    for label, fig in (('Monthly ceiling $25', r'Monthly\s+ceiling\s+(?:\*\*)?\$25(?![0-9])'), ('Review trigger $2.50', r'Review\s+trigger\s+(?:\*\*)?\$2\.50(?![0-9])')):
        if not re.search(fig, sect):
            bad('PARITY-FIGURE', 'the amendment lacks "%s"' % label)
    out('FACT entries=%d' % nent)
    out('FACT cap=%s' % cap)
    for line in v:
        out(line)


# --- mutation tooling -------------------------------------------------------------------------------------------
def cmd_ymut(src, dst, stmt):
    d = yaml.safe_load(open(src, encoding='utf-8').read())
    d = {('on' if k is True else k): v for k, v in d.items()}
    before = yaml.safe_dump(d, sort_keys=False)
    g = {'d': d, 'copy': copy}
    exec(stmt, g)
    after = yaml.safe_dump(d, sort_keys=False)
    if before == after:
        sys.exit(2)
    open(dst, 'w').write(yaml.safe_dump(d, sort_keys=False))


def cmd_tmut(src, dst, old, new):
    s = open(src, encoding='utf-8').read()
    if old not in s:
        sys.exit(2)
    t = s.replace(old, new, 1)
    if t == s:
        sys.exit(2)
    open(dst, 'w').write(t)


def cmd_rmut(src, dst, pattern, repl):
    s = open(src, encoding='utf-8').read()
    t, n = re.subn(pattern, repl, s, count=1, flags=re.M)
    if n != 1 or t == s:
        sys.exit(2)
    open(dst, 'w').write(t)


def cmd_prepend(src, dst, text):
    s = open(src, encoding='utf-8').read()
    open(dst, 'w').write(text + '\n' + s)


def main():
    a = sys.argv[1:]
    c = a[0]
    if c == 'posture': cmd_posture(a[1])
    elif c == 'envnames': cmd_envnames(a[1])
    elif c == 'allowlist': cmd_allowlist(a[1], a[2])
    elif c == 'stepname': cmd_stepname(a[1], a[2])
    elif c == 'stepenv': cmd_stepenv(a[1], a[2])
    elif c == 'steprun': cmd_steprun(a[1], a[2])
    elif c == 'allruns': cmd_allruns(a[1], a[2])
    elif c == 'cover': cmd_cover(*a[1:10])
    elif c == 'imports': cmd_imports(a[1], a[2], a[3])
    elif c == 'match': cmd_match(a[1], a[2])
    elif c == 'parity': cmd_parity(a[1], a[2], a[3])
    elif c == 'ymut': cmd_ymut(a[1], a[2], a[3])
    elif c == 'tmut': cmd_tmut(a[1], a[2], a[3], a[4])
    elif c == 'rmut': cmd_rmut(a[1], a[2], a[3], a[4])
    elif c == 'prepend': cmd_prepend(a[1], a[2], a[3])
    else:
        sys.exit(5)


main()
PYEOF

export RULED_PR="$SCRATCH/ruled-pr.txt"

# ---------------------------------------------------------------------------------------------------------------
# small harness
# ---------------------------------------------------------------------------------------------------------------
OUT=""
HRC=0
helper() {
  OUT="$(python3 -I "$HELPER" "$@" 2>&1)"
  HRC=$?
  if [[ "$HRC" -ne 0 ]]; then
    no "helper crashed: $1 (rc=$HRC): ${OUT:0:300}"
  fi
  return 0
}
has_v() { # <code> [substring]
  local code="$1" sub="${2-}"
  if [[ -n "$sub" ]]; then
    grep -E "^VIOLATION ${code}( |\$)" <<<"$OUT" | grep -qF -- "$sub"
  else
    grep -qE "^VIOLATION ${code}( |\$)" <<<"$OUT"
  fi
}
any_v() { grep -q '^VIOLATION ' <<<"$OUT"; }
fact() { sed -n "s/^FACT $1=//p" <<<"$OUT" | head -1; }
nviol() { grep -c '^VIOLATION ' <<<"$OUT" || true; }
floor_trips() { [[ "${1:-0}" -lt "$2" ]]; } # value floor

# expect_red <desc> <code> [substring]  - the current $OUT must carry that violation
expect_red() {
  local desc="$1" code="$2" sub="${3-}"
  MUT_RUN=$((MUT_RUN + 1))
  if has_v "$code" "$sub"; then
    MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: $desc"
  else
    no "mutant survived (wanted VIOLATION $code${sub:+ naming $sub}): $desc :: $(grep -m3 '^VIOLATION' <<<"$OUT" | tr '\n' '|')"
  fi
}
expect_green() { # <desc>  - $OUT must carry no violation
  if any_v; then no "must-PASS went red: $1 :: $(grep -m3 '^VIOLATION' <<<"$OUT" | tr '\n' '|')"; else ok "GREEN: $1"; fi
}

PRISTINE="$SCRATCH/pristine"
MUTD="$SCRATCH/m"
mkdir -p "$PRISTINE" "$MUTD"
assert_fixture_dir "$PRISTINE"
assert_fixture_dir "$MUTD"

WF="$REPO_ROOT/$WF_REL"
ADR="$REPO_ROOT/$ADR_REL"
PROBE="$REPO_ROOT/$PROBE_REL"
PERM="$REPO_ROOT/$PERM_REL"
RUNNER="$REPO_ROOT/$RUNNER_REL"
BUDGET="$REPO_ROOT/$BUDGET_REL"

# Pristine copies: every mutant derives from these, and the live files are compared with them at the end.
for rel in "$WF_REL" "$ADR_REL" "$PROBE_REL" "$PERM_REL" "$BUDGET_REL" "$RUNNER_REL"; do
  if [[ -f "$REPO_ROOT/$rel" ]]; then cp -p "$REPO_ROOT/$rel" "$PRISTINE/$(basename "$rel")"; fi
done
cp -p "$HELPER" "$PRISTINE/helper.py"

# ===============================================================================================================
# INSTRUMENT SELF-TESTS (positive controls for the helper itself)
# ===============================================================================================================
echo "== instrument self-tests =="

# glob matcher semantics
m1="$(python3 -I "$HELPER" match 'plugins/soleur/hooks/**' 'plugins/soleur/hooks/a/b.sh')"
m2="$(python3 -I "$HELPER" match 'apps/web-platform/server/destroy-ask-*.ts' 'apps/web-platform/server/destroy-ask-lane.ts')"
m3="$(python3 -I "$HELPER" match 'apps/web-platform/server/destroy-ask-*.ts' 'apps/web-platform/server/sub/destroy-ask-lane.ts')"
m4="$(python3 -I "$HELPER" match 'apps/web-platform/server/permission-callbak.ts' "$PERM_REL")"
m5="$(python3 -I "$HELPER" match 'apps/web-platform/package*.json' 'apps/web-platform/package-lock.json')"
if [[ "$m1 $m2 $m3 $m4 $m5" == "yes yes no no yes" ]]; then ok "glob matcher: ** crosses /, * does not, near-miss does not match"; else no "glob matcher semantics wrong: $m1 $m2 $m3 $m4 $m5"; fi

# the extractor on a synthesized fixture (single-line, multi-line, side-effect, re-export, dynamic, comments, strings)
mkdir -p "$SCRATCH/fx/apps/web-platform/server"
cat > "$SCRATCH/fx/extractor-fixture.ts" <<'TSEOF'
import { a } from "./one";
import {
  b,
  type C,
} from "./two";
import type { D } from './three';
import * as E from "../four";
import "./five-side-effect";
export { f } from "./six";
export * from "./seven";
export { notAReexport, alsoNot };
// import { z } from "./commented-out";
/* import { y } from "./block-commented";
   import("./block-dynamic"); */
const url = "https://example.invalid/import { x } from './in-a-string-url'";
const lazy = await import("./eight-dynamic");
const re = /['"]/g;
import { g } from "@/lib/nine-alias";
import { h } from "react";
TSEOF
want_fx="./eight-dynamic ./five-side-effect ./one ./seven ./six ./three ./two @/lib/nine-alias ../four"
got_fx="$(python3 -I -c '
import sys
helper = open(sys.argv[2]).read().rsplit("\nmain()", 1)[0]
g = {}
exec(compile(helper, "helper", "exec"), g)
sp = g["specs_of"](open(sys.argv[3]).read())
print(" ".join(sorted(set(x for x in sp if x.startswith(("./", "../", "@/"))))))
' "$HELPER" "$HELPER" "$SCRATCH/fx/extractor-fixture.ts")"
want_sorted="$(tr ' ' '\n' <<<"$want_fx" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$got_fx" == "$want_sorted" ]]; then ok "extractor fixture: multi-line, dynamic, side-effect, re-export found; comments, strings and bare 'export {a}' ignored"; else no "extractor fixture mismatch: got [$got_fx] want [$want_sorted]"; fi

# the YAML loader reads a trivial document (a neutered loader would return empty for everything)
printf 'name: x\non:\n  push:\n    paths: ["a"]\njobs: {}\n' > "$SCRATCH/fx/tiny.yml"
tiny="$(python3 -I -c '
import sys
helper = open(sys.argv[1]).read().rsplit("\nmain()", 1)[0]
g = {}
exec(compile(helper, "helper", "exec"), g)
d = g["load_wf"](sys.argv[2])
print(g["on_of"](d).get("push", {}).get("paths"))
' "$HELPER" "$SCRATCH/fx/tiny.yml")"
if [[ "$tiny" == "['a']" ]]; then ok "YAML loader returns the on.push.paths of a known document (the on: key is read as True)"; else no "YAML loader instrument self-test: got [$tiny]"; fi

# ===============================================================================================================
# REAL-FILE CHECKS
# ===============================================================================================================
echo "== workflow presence =="
if [[ -f "$WF" ]]; then ok "workflow file exists: $WF_REL"; else no "workflow file absent: $WF_REL"; fi

echo "== Guard 2: workflow posture (real file) =="
helper posture "$WF"
POSTURE_REAL="$OUT"
if any_v; then no "posture: $(nviol) violation(s): $(grep '^VIOLATION' <<<"$OUT" | head -8 | tr '\n' '|')"; else ok "posture: zero violations"; fi
KEYREFS="$(fact keyrefs)"; JOBS_N="$(fact jobs)"; RUN_STEPS="$(fact run_steps)"; USES_N="$(fact uses)"
if [[ "${KEYREFS:-0}" -ge 2 ]]; then ok "posture dispatch: $KEYREFS key references found (probe env + preflight input)"; else no "posture dispatch: only ${KEYREFS:-0} key reference(s) found"; fi
if [[ "${JOBS_N:-0}" -ge 2 ]]; then ok "posture dispatch: $JOBS_N jobs found"; else no "posture dispatch: only ${JOBS_N:-0} job(s) found"; fi
if [[ "${RUN_STEPS:-0}" -ge 5 ]]; then ok "posture dispatch: $RUN_STEPS run steps inspected"; else no "posture dispatch: only ${RUN_STEPS:-0} run step(s) inspected"; fi
if [[ "${USES_N:-0}" -ge 6 ]]; then ok "posture dispatch: $USES_N uses references inspected"; else no "posture dispatch: only ${USES_N:-0} uses reference(s) inspected"; fi

echo "== cron literal / header / marker (AC19, hook override, task design) =="
CRON_LITERAL='17 9 * * 1'
if [[ -f "$WF" ]]; then
  cron_n="$(grep -cF -- "$CRON_LITERAL" "$WF")"
  if [[ "$cron_n" == "1" ]]; then ok "cron literal appears exactly once (AC19)"; else no "cron literal appears $cron_n times in the workflow (want exactly 1)"; fi
  first_line="$(head -1 "$WF")"
  if [[ "$first_line" == '# <!-- gate-override: new-scheduled-cron-prefer-inngest -->' ]]; then ok "line 1 is the ADR-033 gate-override marker"; else no "line 1 is not the gate-override marker: $first_line"; fi
  header="$(awk '/^name:/ {exit} {print}' "$WF")"
  if grep -qE '^# +Why GitHub Actions and not Inngest' <<<"$header" && grep -qF 'Inngest' <<<"$header"; then ok "header carries the Why-not-Inngest justification"; else no "header lacks the 'Why GitHub Actions and not Inngest' justification"; fi
  if grep -qE '^# Task design:$' <<<"$header"; then ok "header carries '# Task design:'"; else no "header lacks '# Task design:'"; fi
  for k in trigger services next human_reentry dedupe source_dedupe; do
    if grep -qE "^#   ${k}:" <<<"$header"; then ok "task-design key present: $k"; else no "task-design key missing: $k"; fi
  done
else
  no "cron/header checks: workflow absent"
fi

echo "== not a required check (AC1) =="
for needle in "real-sdk-ask-probe" "Scheduled: real-SDK"; do
  if grep -qiF -- "$needle" "$REPO_ROOT/$REQCHECKS_REL"; then no "$REQCHECKS_REL names '$needle'"; else ok "$REQCHECKS_REL does not name '$needle'"; fi
  if grep -qiF -- "$needle" "$REPO_ROOT/$RULESET_REL"; then no "$RULESET_REL names '$needle'"; else ok "$RULESET_REL does not name '$needle'"; fi
done

echo "== AC6 user-visible strings and AC10 production-sink absence =="
FORB="verified in ""production"
HOST_RE='(^|[^A-Za-z-])host-only([^A-Za-z-]|$)'
ARRIVAL='production arrival not observed'
for rel in "$WF_REL" "$RUNNER_REL"; do
  f="$REPO_ROOT/$rel"
  if [[ ! -f "$f" ]]; then no "AC6/AC10: $rel is absent"; continue; fi
  if grep -qiF -- "$FORB" "$f"; then no "AC6: $rel contains the forbidden claim"; else ok "AC6: $rel never claims the forbidden production verification"; fi
  if grep -qiE -- "$HOST_RE" "$f"; then ok "AC6: $rel states the host-only residual"; else no "AC6: $rel lacks the host-only residual"; fi
  if grep -qiF -- "$ARRIVAL" "$f"; then ok "AC6: $rel states 'production arrival not observed'"; else no "AC6: $rel lacks 'production arrival not observed'"; fi
done

SINK_RE='SENTRY_DSN|NEXT_PUBLIC_SENTRY|sentry\.io|BETTER_?STACK|betterstack|environment=probe|flagsmith|feature[-_ ]flag|sentry-heartbeat|cron-monitors|doppler[[:space:]]+(run|secrets|setup)|dopplerhq/'
sink_hits() { grep -vE '^[[:space:]]*#' "$1" | grep -nEi -- "$SINK_RE"; }
for rel in "$WF_REL" "$RUNNER_REL"; do
  f="$REPO_ROOT/$rel"
  if [[ ! -f "$f" ]]; then continue; fi
  if sink_hits "$f" >/dev/null; then no "AC10: $rel names a production sink / flag / Doppler read: $(sink_hits "$f" | head -3 | tr '\n' '|')"; else ok "AC10: $rel emits into no production sink and reads no flag or Doppler config"; fi
done

echo "== SKIPPED summary step, run for real (AC6 job summary) =="
if [[ -f "$WF" ]]; then
  helper steprun "$WF" skip
  SKIP_RUN="$OUT"
  if [[ -n "$SKIP_RUN" ]]; then
    printf '%s\n' "$SKIP_RUN" > "$SCRATCH/skip-step.sh"
    helper stepenv "$WF" skip
    SKIP_ENV=()
    while IFS= read -r l; do [[ -n "$l" ]] && SKIP_ENV+=("$l"); done <<<"$OUT"
    : > "$SCRATCH/summary.md"; : > "$SCRATCH/gh-output.txt"
    skip_stdout="$(env -i PATH="$PATH" HOME="$SCRATCH" GITHUB_STEP_SUMMARY="$SCRATCH/summary.md" GITHUB_OUTPUT="$SCRATCH/gh-output.txt" ${SKIP_ENV[@]+"${SKIP_ENV[@]}"} bash --noprofile --norc -eo pipefail "$SCRATCH/skip-step.sh" 2>&1)"
    skip_rc=$?
    if [[ "$skip_rc" -eq 0 ]]; then ok "skip step runs clean under bash --noprofile --norc -eo pipefail"; else no "skip step exited $skip_rc: ${skip_stdout:0:200}"; fi
    if grep -qF 'SKIPPED' "$SCRATCH/summary.md"; then ok "skip step summary says SKIPPED"; else no "skip step summary lacks SKIPPED"; fi
    if grep -qiE -- "$HOST_RE" "$SCRATCH/summary.md" && grep -qiF -- "$ARRIVAL" "$SCRATCH/summary.md"; then ok "skip step summary carries the host-only residual and 'production arrival not observed'"; else no "skip step summary lacks the AC6 strings"; fi
    if grep -qF '::warning::' <<<"$skip_stdout"; then ok "skip step prints a ::warning::"; else no "skip step prints no ::warning::"; fi
    if grep -qx 'outcome=skipped' "$SCRATCH/gh-output.txt"; then ok "skip step writes outcome=skipped (never a pass)"; else no "skip step does not write outcome=skipped"; fi
    if grep -qiF -- "$FORB" "$SCRATCH/summary.md"; then no "skip summary contains the forbidden claim"; else ok "skip summary never claims the forbidden production verification"; fi
  else
    no "skip step has no run body"
  fi
else
  no "skip step: workflow absent"
fi

echo "== every run body parses (bash -n after expression stripping) =="
if [[ -f "$WF" ]]; then
  mkdir -p "$SCRATCH/runs"
  helper allruns "$WF" "$SCRATCH/runs"
  nruns="$(fact runs)"
  if [[ "${nruns:-0}" -ge 5 ]]; then ok "extracted $nruns run bodies"; else no "extracted only ${nruns:-0} run bodies"; fi
  for f in "$SCRATCH"/runs/run-*.sh; do
    [[ -e "$f" ]] || continue
    if bash --noprofile --norc -n "$f" 2>/dev/null; then ok "bash -n: $(basename "$f")"; else no "bash -n failed: $(basename "$f")"; fi
  done
fi

echo "== workflow <-> runner interface (env names and output names the workflow relies on) =="
if [[ -f "$WF" && -f "$RUNNER" ]]; then
  helper envnames "$WF"
  ENVNAMES="$OUT"
  n_env=0
  while IFS= read -r line; do
    nm="${line#ENVNAME }"
    case "$nm" in ANTHROPIC_API_KEY|GH_TOKEN|NODE_ENV) continue ;; esac
    n_env=$((n_env + 1))
    if grep -qF -- "$nm" "$RUNNER"; then ok "runner reads workflow-provided env $nm"; else no "workflow passes env $nm that the runner never mentions"; fi
  done < <(grep '^ENVNAME ' <<<"$ENVNAMES")
  if [[ "$n_env" -ge 3 ]]; then ok "interface census: $n_env workflow-provided env names inspected"; else no "interface census: only $n_env env names inspected"; fi
  for o in outcome reason cost provenance run; do
    if grep -qE -- "(^|[^A-Za-z_])${o}=|emit[[:space:]]+${o}([[:space:]]|\$)" "$RUNNER"; then ok "runner writes the '$o' output"; else no "runner never writes a '$o' output"; fi
  done
  for sub in should-run run file-issue; do
    if grep -qE -- "(^|[[:space:]]|\\()${sub}\\)" "$RUNNER"; then ok "runner dispatches subcommand $sub"; else no "runner has no '$sub)' dispatch arm"; fi
  done
else
  no "interface check: workflow or runner absent ($WF_REL, $RUNNER_REL)"
fi

echo "== parity (D8): runner allowlist, PROBE_STEP_NAME, not-run composition =="
ALLOW_REAL="VIOLATION unset"; STEPNAME_REAL="VIOLATION unset"
if [[ -f "$WF" && -f "$RUNNER" ]]; then
  # (a) the runner's in_run_allowlist case patterns == RULED_PUSH_PATHS minus the package files (derived, not restated)
  helper allowlist "$RUNNER" "$SCRATCH/ruled-push.txt"
  ALLOW_REAL="$OUT"
  if any_v; then no "allowlist parity: $(grep '^VIOLATION' <<<"$OUT" | head -4 | tr '\n' '|')"; else ok "allowlist parity: the runner in_run_allowlist equals the ruled push paths minus the package files"; fi
  ALLOW_N="$(fact patterns)"; RULED_N="$(fact ruled)"
  if [[ "${ALLOW_N:-0}" -ge 12 && "${RULED_N:-0}" -ge 12 ]]; then ok "allowlist parity dispatch: $ALLOW_N runner patterns vs $RULED_N ruled non-package paths (floor 12)"; else no "allowlist parity dispatch: runner patterns=${ALLOW_N:-0} ruled=${RULED_N:-0}, floor 12"; fi
  # (c) PROBE_STEP_NAME in the runner == the probe step name: in the workflow
  helper stepname "$WF" "$RUNNER"
  STEPNAME_REAL="$OUT"
  if any_v; then no "PROBE_STEP_NAME parity: $(grep '^VIOLATION' <<<"$OUT" | head -3 | tr '\n' '|')"; else ok "PROBE_STEP_NAME parity: the runner constant equals the workflow probe step name"; fi
  if [[ -n "$(fact stepname)" ]]; then ok "PROBE_STEP_NAME dispatch: a probe step name was read ($(fact stepname))"; else no "PROBE_STEP_NAME dispatch: no probe step name read"; fi
  # (d) the runner emits outcome=not-run from should-run, and its file-issue treats not-run as a no-op (driven for real)
  # Captured first, then matched: `sed | grep -q` under pipefail returns 141 when grep exits early and sed takes SIGPIPE (an intermittent false negative).
  RUNNER_CODE="$(sed -E 's/^[[:space:]]*#.*$//' "$RUNNER")"
  if grep -qE -- '^[[:space:]]*emit[[:space:]]+outcome[[:space:]]+not-run[[:space:]]*$' <<<"$RUNNER_CODE"; then ok "runner should-run emits outcome not-run"; else no "runner never emits outcome not-run"; fi
  FSTUB="$SCRATCH/filer-stub"
  mkdir -p "$FSTUB/bin"
  assert_fixture_dir "$FSTUB"
  cat > "$FSTUB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_LOG:?}"
exit 1
GHEOF
  chmod +x "$FSTUB/bin/gh"
  F_RC=0; F_OUT=""; F_GHLOG=""
  drive_filer() { # <outcome>  -> F_RC F_OUT F_GHLOG (a gh stub that logs every call and fails)
    : > "$FSTUB/gh.log"
    F_OUT="$(env -i PATH="$FSTUB/bin:$PATH" HOME="$SCRATCH" GH_STUB_LOG="$FSTUB/gh.log" GITHUB_EVENT_NAME=push GITHUB_REPOSITORY=example/repo GITHUB_RUN_ID=1 PROBE_OUTCOME="$1" PROBE_JOB_RESULT=success bash --noprofile --norc "$RUNNER" file-issue 2>&1)"
    F_RC=$?
    F_GHLOG="$(cat "$FSTUB/gh.log")"
  }
  drive_filer not-run
  if [[ "$F_RC" -eq 0 && -z "$F_GHLOG" ]] && grep -qF 'files nothing' <<<"$F_OUT"; then ok "composition: file-issue with PROBE_OUTCOME=not-run exits 0, calls no gh and says it files nothing"; else no "composition: not-run was not a clean no-op (rc=$F_RC gh='${F_GHLOG:0:80}' out='${F_OUT:0:120}')"; fi
  drive_filer skipped
  if [[ "$F_RC" -eq 0 && -z "$F_GHLOG" ]]; then ok "composition control: skipped is the same no-op"; else no "composition control: skipped was not a no-op (rc=$F_RC gh='${F_GHLOG:0:80}')"; fi
  drive_filer fail
  if [[ "$F_RC" -ne 0 && -n "$F_GHLOG" ]]; then ok "composition positive control: PROBE_OUTCOME=fail reaches gh (the stub is wired, so the empty not-run log means something)"; else no "composition positive control: fail never reached the gh stub (rc=$F_RC gh='${F_GHLOG:0:80}')"; fi
  drive_filer not-ran
  MUT_RUN=$((MUT_RUN + 1))
  if [[ "$F_RC" -eq 2 && -z "$F_GHLOG" ]]; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: composition a misspelt outcome (not-ran) is refused (rc 2), never treated as not-run"; else no "mutant survived: not-ran was tolerated (rc=$F_RC gh='${F_GHLOG:0:80}')"; fi
fi

echo "== Guard 1: push filter coverage (real files) =="
cover() { # <wf> <table> <ruled> <probe> <perm> <adr>
  helper cover "$REPO_ROOT" "$1" "$2" "$3" "$4" "$PROBE_REL" "$5" "$PERM_REL" "$6"
}
cover "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
COVER_REAL="$OUT"
if any_v; then no "coverage: $(nviol) violation(s): $(grep '^VIOLATION' <<<"$OUT" | head -6 | tr '\n' '|')"; else ok "coverage: zero violations"; fi
PROBE_LOCAL="$(fact probe_local)"; PERM_LOCAL="$(fact perm_local)"; ADR_FILES="$(fact adr_files)"; DIRECT_N="$(fact direct_imports)"
printf 'MEASURED probe_local=%s perm_local=%s adr_files=%s direct_imports=%s push_entries=%s probe_total=%s perm_total=%s\n' \
  "$PROBE_LOCAL" "$PERM_LOCAL" "$ADR_FILES" "$DIRECT_N" "$(fact push_entries)" "$(fact probe_total)" "$(fact perm_total)"
if floor_trips "$PROBE_LOCAL" "$FLOOR_PROBE_LOCAL"; then no "extractor floor: probe has $PROBE_LOCAL local imports, floor $FLOOR_PROBE_LOCAL"; else ok "extractor floor: probe has $PROBE_LOCAL local imports (floor $FLOOR_PROBE_LOCAL)"; fi
if floor_trips "$PERM_LOCAL" "$FLOOR_PERM_LOCAL"; then no "extractor floor: permission-callback has $PERM_LOCAL local imports, floor $FLOOR_PERM_LOCAL"; else ok "extractor floor: permission-callback has $PERM_LOCAL local imports (floor $FLOOR_PERM_LOCAL)"; fi
if floor_trips "$ADR_FILES" "$FLOOR_ADR_FILES"; then no "extractor floor: ADR criterion 5 names $ADR_FILES files, floor $FLOOR_ADR_FILES"; else ok "extractor floor: ADR criterion 5 names $ADR_FILES files (floor $FLOOR_ADR_FILES)"; fi

echo "== doc-vs-code parity (AC18) =="
helper parity "$WF" "$ADR" "$BUDGET"
PARITY_REAL="$OUT"
if any_v; then no "parity: $(grep '^VIOLATION' <<<"$OUT" | head -5 | tr '\n' '|')"; else ok "parity: the ADR-284 amendment lists every push path and the \$4 / \$25 / \$2.50 figures match RUN_BUDGET_USD"; fi
if [[ "$(fact entries)" -ge 14 ]]; then ok "parity dispatch: $(fact entries) push entries compared"; else no "parity dispatch: only $(fact entries) push entries compared"; fi

# ===============================================================================================================
# MUTATION BATTERY (only meaningful from a green pristine; a red pristine reports itself instead of faking kills)
# ===============================================================================================================
mut_y() { # <name> <src> <dst> <python stmt>  -> 0 landed
  python3 -I "$HELPER" ymut "$2" "$3" "$4"
  local rc=$?
  if [[ "$rc" -eq 0 && -s "$3" ]] && ! cmp -s "$2" "$3"; then ok "mutation landed: $1"; return 0; fi
  no "mutation did NOT land: $1 (rc=$rc)"
  return 1
}
mut_r() { # <name> <src> <dst> <regex> <replacement>  (re.sub, count 1, MULTILINE)
  python3 -I "$HELPER" rmut "$2" "$3" "$4" "$5"
  local rc=$?
  if [[ "$rc" -eq 0 ]] && ! cmp -s "$2" "$3"; then ok "mutation landed: $1"; return 0; fi
  no "mutation did NOT land: $1 (rc=$rc)"
  return 1
}
mut_t() { # <name> <src> <dst> <old> <new>
  python3 -I "$HELPER" tmut "$2" "$3" "$4" "$5"
  local rc=$?
  if [[ "$rc" -eq 0 ]] && ! cmp -s "$2" "$3"; then ok "mutation landed: $1"; return 0; fi
  no "mutation did NOT land: $1 (rc=$rc)"
  return 1
}

PRISTINE_WF="$PRISTINE/$(basename "$WF_REL")"
KEYEXPR='${{ secrets.ANTHROPIC_API_KEY }}'

if [[ -f "$PRISTINE_WF" ]] && ! grep -q '^VIOLATION' <<<"$POSTURE_REAL"; then
  echo "== Guard 2 mutation matrix =="
  posture_mut() { # <name> <code> <stmt> [substring]
    local m="$MUTD/g2-$1.yml"
    if mut_y "$1" "$PRISTINE_WF" "$m" "$3"; then helper posture "$m"; expect_red "G2 $1" "$2" "${4-}"; else MUT_RUN=$((MUT_RUN + 1)); fi
  }
  posture_mut key-job-env KEY-SCOPE "d['jobs']['probe']['env']={'ANTHROPIC_API_KEY':'$KEYEXPR'}"
  posture_mut key-job-env-env-scope KEY-ENV-SCOPE "d['jobs']['probe']['env']={'ANTHROPIC_API_KEY':'x'}"
  posture_mut key-workflow-env KEY-SCOPE "d['env']={'ANTHROPIC_API_KEY':'$KEYEXPR'}"
  posture_mut key-second-step KEY-SCOPE "d['jobs']['probe']['steps'].append({'name':'extra','shell':'bash','run':'set -euo pipefail\necho hi','env':{'ANTHROPIC_API_KEY':'$KEYEXPR'}})"
  posture_mut key-second-step-bracket-spelling KEY-SCOPE "d['jobs']['probe']['steps'].append({'name':'extra','shell':'bash','run':'set -euo pipefail\necho hi','env':{'K':\"\${{ secrets['ANTHROPIC_API_KEY'] }}\"}})"
  posture_mut key-in-filer-job KEY-SCOPE "d['jobs']['file-issue']['steps'][-1].setdefault('env',{})['K']='$KEYEXPR'"
  posture_mut key-removed-from-probe KEY-PROBE-STEP "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0]['env'].pop('ANTHROPIC_API_KEY')"
  posture_mut key-echoed-in-run KEY-IN-RUN "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0].update(run='set -euo pipefail\necho \"\$ANTHROPIC_API_KEY\"\nbash apps/web-platform/scripts/real-sdk-ask-probe.sh run')"
  posture_mut other-secret SECRET-OTHER "d['jobs']['file-issue']['steps'][-1].setdefault('env',{})['T']='\${{ secrets.DOPPLER_TOKEN }}'"
  posture_mut dynamic-secrets SECRETS-DYNAMIC "d['jobs']['file-issue']['steps'][-1].setdefault('env',{})['T']='\${{ toJSON(secrets) }}'"
  posture_mut set-x XTRACE "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0]['run']='set -x\n'+[s for s in d['jobs']['probe']['steps'] if 'run' in s][0]['run']"
  posture_mut set-euxo XTRACE "[s for s in d['jobs']['probe']['steps'] if 'run' in s][1]['run']=[s for s in d['jobs']['probe']['steps'] if 'run' in s][1]['run'].replace('set -euo pipefail','set -euxo pipefail',1)"
  posture_mut bash-x XTRACE "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0]['run']+='\nbash -x ./x.sh\n'"
  posture_mut xtrace-fd XTRACE "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0]['run']+='\nexport BASH_XTRACEFD=2\n'"
  posture_mut pr-paths-widened PR-PATHS "d['on']['pull_request']['paths'].append('apps/web-platform/**')" 2>/dev/null
  posture_mut pr-paths-narrowed PR-PATHS "d['on']['pull_request']['paths'].pop()"
  posture_mut pr-target TRIGGER-SET "d['on']['pull_request_target']={'paths':['x']}"
  posture_mut workflow-run-trigger TRIGGER-SET "d['on']['workflow_run']={'workflows':['x']}"
  posture_mut push-branch-widened PUSH-BRANCHES "d['on']['push']['branches']=['main','feat/**']"
  posture_mut same-repo-if-dropped PROBE-IF "d['jobs']['probe'].pop('if')"
  posture_mut same-repo-compare-weakened PROBE-IF "d['jobs']['probe']['if']=d['jobs']['probe']['if'].replace('github.event.pull_request.head.repo.full_name == github.repository','true')"
  posture_mut dependabot-clause-dropped PROBE-IF "d['jobs']['probe']['if']=d['jobs']['probe']['if'].replace(\"github.actor != 'dependabot[bot]'\",'true')"
  posture_mut issues-write-workflow-level PERM-TOP "d['permissions']['issues']='write'"
  posture_mut issues-write-on-probe PERM-JOB-WRITE "d['jobs']['probe']['permissions']['issues']='write'"
  posture_mut contents-write-on-filer PERM-JOB-WRITE "d['jobs']['file-issue']['permissions']['contents']='write'"
  posture_mut write-all PERM-TOP "d['permissions']='write-all'"
  posture_mut probe-perms-lack-actions-read PERM-PROBE "d['jobs']['probe']['permissions'].pop('actions')"
  posture_mut filer-perms-missing PERM-JOB-MISSING "d['jobs']['file-issue'].pop('permissions')"
  posture_mut unpinned-tag USES-NOT-SHA "d['jobs']['probe']['steps'][0]['uses']='actions/checkout@v4'"
  posture_mut short-sha USES-NOT-SHA "d['jobs']['probe']['steps'][0]['uses']='actions/checkout@34e1148'"
  posture_mut unknown-sha USES-PIN "d['jobs']['probe']['steps'][0]['uses']='actions/checkout@'+'0'*40"
  posture_mut new-action-sha USES-PIN "d['jobs']['probe']['steps'].insert(1,{'uses':'actions/cache@'+'1'*40})"
  posture_mut persist-credentials-dropped CHECKOUT-CREDS "d['jobs']['probe']['steps'][0]['with'].pop('persist-credentials')"
  posture_mut shell-dropped SHELL "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0].pop('shell')"
  posture_mut shell-dash-x SHELL "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0].update(shell='bash -x {0}')"
  posture_mut set-line-dropped SET-LINE "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0].update(run='echo no-set-line')"
  posture_mut expr-in-run EXPR-IN-RUN "[s for s in d['jobs']['probe']['steps'] if 'run' in s][0]['run']+='\necho \${{ github.event.pull_request.title }}\n'"
  posture_mut second-cron CRON-SET "d['on']['schedule'].append({'cron':'17 9 * * 1'})"
  posture_mut cron-changed CRON-SET "d['on']['schedule'][0]['cron']='*/5 * * * *'"
  posture_mut cancel-in-progress CONCURRENCY "d['concurrency']['cancel-in-progress']=True"
  posture_mut concurrency-group CONCURRENCY "d['concurrency']['group']='other'"
  posture_mut concurrency-pr-segment-dropped CONCURRENCY "d['concurrency']['group']='real-sdk-ask-probe'"
  posture_mut concurrency-pr-group-shared CONCURRENCY "d['concurrency']['group']=d['concurrency']['group'].replace('github.event.pull_request.number','github.run_id')"
  posture_mut name-residual-dropped NAME-RESIDUAL "d['name']='Scheduled: real-SDK ask probe'"
  posture_mut filer-if-pr-guard-dropped FILER-IF "d['jobs']['file-issue']['if']=d['jobs']['file-issue']['if'].replace(\"github.event_name != 'pull_request'\",'true')"
  posture_mut filer-if-main-guard-dropped FILER-IF "d['jobs']['file-issue']['if']=d['jobs']['file-issue']['if'].replace(\"github.ref == 'refs/heads/main'\",'true')"
  posture_mut filer-needs-dropped FILER-NEEDS "d['jobs']['file-issue'].pop('needs')"
  posture_mut preflight-after-probe PROBE-STEP-ORDER "s=d['jobs']['probe']['steps']; i=[k for k,x in enumerate(s) if x.get('id')=='preflight'][0]; p=s.pop(i); s.append(p)"
  posture_mut probe-timeout-inverted TIMEOUTS "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0]['timeout-minutes']=999"
  posture_mut probe-job-renamed PROBE-NAME "d['jobs']['probe']['name']='run-probe'"
  posture_mut probe-timeout-below-two-passes TIMEOUT-TWO-PASS "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0]['timeout-minutes']=30"
  posture_mut job-timeout-no-headroom TIMEOUT-HEADROOM "d['jobs']['probe']['timeout-minutes']=52"
  posture_mut outcome-should-run-term-dropped OUTCOME-COMPOSE "d['jobs']['probe']['outputs']['outcome']=d['jobs']['probe']['outputs']['outcome'].replace(' || steps.should-run.outputs.outcome','')" "not-run"
  posture_mut outcome-wrong-step-id OUTCOME-COMPOSE "d['jobs']['probe']['outputs']['outcome']=d['jobs']['probe']['outputs']['outcome'].replace('steps.should-run.outputs.outcome','steps.preflight.outputs.outcome')" "not-run"
  posture_mut outcome-skip-term-dropped OUTCOME-COMPOSE "d['jobs']['probe']['outputs']['outcome']=d['jobs']['probe']['outputs']['outcome'].replace(' || steps.skip.outputs.outcome','')" "skipped"
  posture_mut outcome-unparseable-operator OUTCOME-COMPOSE "d['jobs']['probe']['outputs']['outcome']=d['jobs']['probe']['outputs']['outcome'].replace(' || ',' && ')"
  posture_mut filer-outcome-unwired FILER-OUTCOME-WIRE "[x for x in d['jobs']['file-issue']['steps'] if 'env' in x][0]['env']['PROBE_OUTCOME']='skipped'"
  posture_mut probe-timeout-dropped TIMEOUTS "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0].pop('timeout-minutes')"
  posture_mut artifact-retention ARTIFACT "[s for s in d['jobs']['probe']['steps'] if str(s.get('uses','')).startswith('actions/upload-artifact')][0]['with']['retention-days']=7"
  posture_mut artifact-if-always ARTIFACT "[s for s in d['jobs']['probe']['steps'] if str(s.get('uses','')).startswith('actions/upload-artifact')][0].pop('if')"
  posture_mut bubblewrap-step-removed SANDBOX-SETUP "d['jobs']['probe']['steps']=[s for s in d['jobs']['probe']['steps'] if 'bubblewrap' not in str(s.get('run',''))]"
  posture_mut npm-ci-ignore-scripts NPM-CI "[s.update(run=s['run'].replace('npm ci --ignore-scripts','npm ci')) for s in d['jobs']['probe']['steps'] if 'run' in s]"
  posture_mut reusable-workflow REUSABLE-WORKFLOW "d['jobs']['x']={'uses':'./.github/workflows/ci.yml'}"
  posture_mut runner-not-ubuntu PROBE-RUNNER "d['jobs']['probe']['runs-on']='self-hosted'"
  posture_mut probe-output-dropped PROBE-OUTPUT-MISSING "d['jobs']['probe']['outputs'].pop('outcome')"

  # row 7: the guard's own dispatch - an empty workflow must be RED and must trip the floors
  : > "$MUTD/g2-empty.yml"
  helper posture "$MUTD/g2-empty.yml"
  expect_red "G2 empty-workflow-file" PARSE-EMPTY
  if floor_trips "$(fact keyrefs)" 2 && floor_trips "$(fact jobs)" 2; then ok "G2 empty workflow trips the dispatch floors (keyrefs<2 and jobs<2)"; else no "G2 empty workflow did not trip the dispatch floors"; fi
  # text-level mutations
  if mut_t "cron literal repeated in a header comment" "$PRISTINE_WF" "$MUTD/g2-cron-comment.yml" "# <!-- gate-override" "# 17 9 * * 1 stray comment
# <!-- gate-override"; then
    c2="$(grep -cF -- "$CRON_LITERAL" "$MUTD/g2-cron-comment.yml")"
    MUT_RUN=$((MUT_RUN + 1))
    if [[ "$c2" != "1" ]]; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: AC19 counts a repeated cron literal ($c2)"; else no "mutant survived: cron literal repeated but count is 1"; fi
  fi
  # AC10 / AC6 text mutants
  printf '%s\nenv:\n  SENTRY_DSN: x\n' "$(cat "$PRISTINE_WF")" > "$MUTD/g2-sink.yml"
  MUT_RUN=$((MUT_RUN + 1))
  if sink_hits "$MUTD/g2-sink.yml" >/dev/null; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: AC10 grep catches an appended SENTRY_DSN"; else no "mutant survived: AC10 grep missed SENTRY_DSN"; fi
  printf '# a comment that mentions SENTRY_DSN is a prohibition, not an emission\n%s\n' "$(cat "$PRISTINE_WF")" > "$MUTD/g2-sink-comment.yml"
  if sink_hits "$MUTD/g2-sink-comment.yml" >/dev/null; then no "must-PASS went red: AC10 flags a comment-only mention"; else ok "GREEN: AC10 ignores a comment-only mention"; fi
  printf '%s\n      - run: echo "%s"\n' "$(cat "$PRISTINE_WF")" "$FORB" > "$MUTD/g2-claim.yml"
  MUT_RUN=$((MUT_RUN + 1))
  if grep -qiF -- "$FORB" "$MUTD/g2-claim.yml"; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: AC6 grep catches the forbidden production-verification claim"; else no "mutant survived: AC6 grep missed the forbidden claim"; fi

  echo "== Guard 2 harness rows =="
  # H1: the YAML parse returns an empty document -> RED
  if mut_t "H1 parse returns an empty document" "$PRISTINE/helper.py" "$MUTD/helper-h1.py" "    doc = yaml.safe_load(open(path, encoding='utf-8').read())
    return doc" "    doc = {}
    return doc"; then
    OUT="$(python3 -I "$MUTD/helper-h1.py" posture "$WF" 2>&1)"
    MUT_RUN=$((MUT_RUN + 1))
    if has_v PARSE-EMPTY; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: G2 H1 empty-parse helper cannot go green"; else no "G2 H1 survived: an empty-parse helper reported green"; fi
  fi
  # H2: must-PASS non-canonical shapes
  if mut_y "H2 extra read-only job with no secret" "$PRISTINE_WF" "$MUTD/g2-h2-job.yml" "d['jobs']['lint-extra']={'runs-on':'ubuntu-latest','permissions':{'contents':'read'},'steps':[{'shell':'bash','run':'set -euo pipefail\necho ok'}]}"; then
    helper posture "$MUTD/g2-h2-job.yml"; expect_green "G2 H2 extra read-only job"
  fi
  if mut_y "H2 reordered env on the probe step" "$PRISTINE_WF" "$MUTD/g2-h2-env.yml" "s=[s for s in d['jobs']['probe']['steps'] if s.get('id')=='probe'][0]; s['env']=dict(reversed(list(s['env'].items())))"; then
    helper posture "$MUTD/g2-h2-env.yml"; expect_green "G2 H2 reordered env"
  fi
else
  no "Guard 2 mutation matrix cannot run: the pristine workflow is absent or red ($(grep -c '^VIOLATION' <<<"$POSTURE_REAL") violation(s))"
fi

echo "== Guard 1 mutation matrix =="
# Row 2 does not need the pristine to be green: it is a pure extractor/floor row.
: > "$MUTD/empty-probe.ts"
helper cover "$REPO_ROOT" "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$MUTD/empty-probe.ts" "$PROBE_REL" "$PERM" "$PERM_REL" "$ADR"
MUT_RUN=$((MUT_RUN + 1))
if floor_trips "$(fact probe_local)" "$FLOOR_PROBE_LOCAL"; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: G1 row 2 an empty probe fixture yields $(fact probe_local) imports, the floor ($FLOOR_PROBE_LOCAL) trips"; else no "G1 row 2 survived: empty probe fixture still found $(fact probe_local) imports"; fi
: > "$MUTD/empty-perm.ts"
helper cover "$REPO_ROOT" "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PROBE_REL" "$MUTD/empty-perm.ts" "$PERM_REL" "$ADR"
MUT_RUN=$((MUT_RUN + 1))
if floor_trips "$(fact perm_local)" "$FLOOR_PERM_LOCAL"; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: G1 row 2b an empty permission-callback fixture trips its floor"; else no "G1 row 2b survived"; fi

# Row 4: the ADR criterion-5 sentence reworded so the extractor yields zero files.
if mut_t "G1 row 4 ADR criterion 5 reworded" "$PRISTINE/$(basename "$ADR_REL")" "$MUTD/adr-row4.md" $'\n5. No SDK, bundled-CLI' $'\n5) No SDK, bundled-CLI'; then
  helper cover "$REPO_ROOT" "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PROBE_REL" "$PERM" "$PERM_REL" "$MUTD/adr-row4.md"
  MUT_RUN=$((MUT_RUN + 1))
  if floor_trips "$(fact adr_files)" "$FLOOR_ADR_FILES"; then MUT_KILLED=$((MUT_KILLED + 1)); ok "RED: G1 row 4 reworded sentence yields $(fact adr_files) ADR files, the floor trips"; else no "G1 row 4 survived: still $(fact adr_files) ADR files"; fi
fi

if [[ -f "$PRISTINE_WF" ]] && ! grep -q '^VIOLATION' <<<"$COVER_REAL"; then
  cover_mut() { # <name> <code> <stmt> [substring]
    local m="$MUTD/g1-$1.yml"
    if mut_y "$1" "$PRISTINE_WF" "$m" "$3"; then cover "$m" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"; expect_red "G1 $1" "$2" "${4-}"; else MUT_RUN=$((MUT_RUN + 1)); fi
  }
  cover_mut row1-permission-callback-dropped IN-NOT-MATCHED "d['on']['push']['paths'].remove('$PERM_REL')" "$PERM_REL"
  cover_mut row1b-names-in-ruled-missing RULED-MISSING "d['on']['push']['paths'].remove('$PERM_REL')" "$PERM_REL"
  cover_mut row5-near-miss-entry DEAD-ENTRY "d['on']['push']['paths'][d['on']['push']['paths'].index('$PERM_REL')]='apps/web-platform/server/permission-callbak.ts'" "permission-callbak.ts"
  cover_mut row5b-near-miss-leaves-file-unmatched IN-NOT-MATCHED "d['on']['push']['paths'][d['on']['push']['paths'].index('$PERM_REL')]='apps/web-platform/server/permission-callbak.ts'" "$PERM_REL"
  cover_mut widened-to-server-glob RULED-EXTRA "d['on']['push']['paths'].append('apps/web-platform/server/**')" "apps/web-platform/server/logger.ts"
  cover_mut widened-matches-excluded-row EXCLUDED-MATCHED "d['on']['push']['paths'].append('apps/web-platform/server/**')" "apps/web-platform/server/logger.ts"
  cover_mut ruled-package-lock-dropped RULED-MISSING "d['on']['push']['paths'].remove('apps/web-platform/package-lock.json')" "package-lock.json"
  cover_mut ruled-hooks-dropped RULED-MISSING "d['on']['push']['paths'].remove('plugins/soleur/hooks/**')" "plugins/soleur/hooks/"
  cover_mut push-paths-removed PUSH-PATHS-EMPTY "d['on']['push'].pop('paths')"

  # Row 3: two NEW direct imports appended to a copy of permission-callback.ts, neither in the filter nor the table.
  cand=()
  while IFS= read -r f; do
    b="$(basename "$f" .ts)"
    if grep -qF "|apps/web-platform/server/${b}.ts" "$SCRATCH/table.txt"; then continue; fi
    if grep -qF "apps/web-platform/server/${b}.ts" "$SCRATCH/ruled-push.txt"; then continue; fi
    cand+=("$b")
    [[ "${#cand[@]}" -ge 2 ]] && break
  done < <(cd "$REPO_ROOT" && git ls-files 'apps/web-platform/server/*.ts' | grep -vE '\.test\.ts$')
  if [[ "${#cand[@]}" -ge 2 ]]; then
    cat "$PRISTINE/$(basename "$PERM_REL")" > "$MUTD/perm-row3.ts"
    printf '\nimport {\n  zzNewOne,\n} from "./%s";\nexport const lazyTwo = () => import("./%s");\n' "${cand[0]}" "${cand[1]}" >> "$MUTD/perm-row3.ts"
    if ! cmp -s "$PRISTINE/$(basename "$PERM_REL")" "$MUTD/perm-row3.ts"; then
      ok "mutation landed: G1 row 3 two new direct imports (${cand[0]}, ${cand[1]})"
      helper cover "$REPO_ROOT" "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PROBE_REL" "$MUTD/perm-row3.ts" "$PERM_REL" "$ADR"
      expect_red "G1 row 3 first new import named (multi-line static)" NOT-IN-TABLE "apps/web-platform/server/${cand[0]}.ts"
      expect_red "G1 row 3 second new import named (dynamic import())" NOT-IN-TABLE "apps/web-platform/server/${cand[1]}.ts"
    else
      no "mutation did NOT land: G1 row 3"
    fi
  else
    no "G1 row 3 cannot pick two unclassified server files"
  fi

  # Row 6: a new EXCLUDED row with an empty reason; and table hygiene.
  printf '%s\nEXCLUDED|apps/web-platform/server/agent-env.ts|\n' "$CLASSIFICATION_TABLE" > "$MUTD/table-row6.txt"
  cover "$WF" "$MUTD/table-row6.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 row 6 EXCLUDED with an empty reason" EXCLUDED-NO-REASON "apps/web-platform/server/agent-env.ts"
  grep -v 'server/logger.ts' "$SCRATCH/table.txt" > "$MUTD/table-missing-row.txt"
  cover "$WF" "$MUTD/table-missing-row.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 a direct import with no table row" NOT-IN-TABLE "apps/web-platform/server/logger.ts"
  printf '%s\nEXCLUDED|apps/web-platform/server/does-not-exist-anymore.ts|stale row for a deleted file\n' "$CLASSIFICATION_TABLE" > "$MUTD/table-stale.txt"
  cover "$WF" "$MUTD/table-stale.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 stale table row" TABLE-STALE "does-not-exist-anymore"
  printf '%s\nEXCLUDED|apps/web-platform/server/logger.ts|duplicate row for the same file\n' "$CLASSIFICATION_TABLE" > "$MUTD/table-dup.txt"
  cover "$WF" "$MUTD/table-dup.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 duplicate table row" TABLE-DUP "apps/web-platform/server/logger.ts"
  printf '%s\nthis line is not a row\n' "$CLASSIFICATION_TABLE" > "$MUTD/table-malformed.txt"
  cover "$WF" "$MUTD/table-malformed.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 malformed table line" TABLE-MALFORMED
  sed 's#^IN|apps/web-platform/server/destroy-ask-lane.ts#EXCLUDED|apps/web-platform/server/destroy-ask-lane.ts|reclassified to excluded by mistake#' "$SCRATCH/table.txt" > "$MUTD/table-reclass.txt"
  cover "$WF" "$MUTD/table-reclass.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
  expect_red "G1 a filtered file reclassified EXCLUDED" EXCLUDED-MATCHED "destroy-ask-lane.ts"

  echo "== Guard 1 harness rows =="
  # H1: the matcher always returns true -> the deliberately excluded negative control must turn the suite RED.
  if mut_t "H1 matcher always true" "$PRISTINE/helper.py" "$MUTD/helper-g1h1.py" "    return bool(_rx(pat).match(path))" "    return True"; then
    OUT="$(python3 -I "$MUTD/helper-g1h1.py" cover "$REPO_ROOT" "$WF" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PROBE_REL" "$PERM" "$PERM_REL" "$ADR" 2>&1)"
    expect_red "G1 H1 an always-true matcher is caught by the excluded negative control" EXCLUDED-MATCHED "apps/web-platform/server/logger.ts"
  fi
  # H2: must-PASS non-canonical: the two destroy-ask files as one glob.
  if mut_y "H2 destroy-ask-* glob in place of the two file names" "$PRISTINE_WF" "$MUTD/g1-h2.yml" "p=d['on']['push']['paths']; p.remove('apps/web-platform/server/destroy-ask-classifier.ts'); p[p.index('apps/web-platform/server/destroy-ask-lane.ts')]='apps/web-platform/server/destroy-ask-*.ts'"; then
    cover "$MUTD/g1-h2.yml" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
    expect_green "G1 H2 destroy-ask-*.ts glob"
  fi
  # H2b: must-PASS: reordered entries
  if mut_y "H2 reordered push paths" "$PRISTINE_WF" "$MUTD/g1-h2b.yml" "d['on']['push']['paths'].reverse()"; then
    cover "$MUTD/g1-h2b.yml" "$SCRATCH/table.txt" "$SCRATCH/ruled-push.txt" "$PROBE" "$PERM" "$ADR"
    expect_green "G1 H2 reordered push paths"
  fi
else
  no "Guard 1 mutation matrix (rows 1, 3, 5, 6, harness) cannot run: the pristine workflow is absent or the real coverage run is red ($(grep -c '^VIOLATION' <<<"$COVER_REAL") violation(s))"
fi

echo "== Guard 1 row 7 / Guard 5 row 6: doc-vs-code parity mutants =="
if [[ -f "$PRISTINE_WF" ]] && ! grep -q '^VIOLATION' <<<"$PARITY_REAL"; then
  ADR_P="$PRISTINE/$(basename "$ADR_REL")"
  if mut_t "G1 row 7 drop the agent-env entry from the amendment" "$ADR_P" "$MUTD/adr-row7.md" $'- `apps/web-platform/server/agent-env.ts`\n' ''; then
    helper parity "$WF" "$MUTD/adr-row7.md" "$BUDGET"; expect_red "G1 row 7 a push entry missing from the ADR amendment" PARITY-ENTRY "agent-env.ts"
  fi
  if mut_r "G5 row 6 the amendment states \$40 per run" "$ADR_P" "$MUTD/adr-g5r6.md" 'Spend cap(\s+)(\*\*)?\$4' 'Spend cap\g<1>\g<2>$40'; then
    helper parity "$WF" "$MUTD/adr-g5r6.md" "$BUDGET"; expect_red "G5 row 6 cap figure differs from RUN_BUDGET_USD" PARITY-CAP
  fi
  if mut_t "G5 row 6b RUN_BUDGET_USD raised to 40" "$PRISTINE/$(basename "$BUDGET_REL")" "$MUTD/budget-40.ts" 'RUN_BUDGET_USD = 4;' 'RUN_BUDGET_USD = 40;'; then
    helper parity "$WF" "$ADR" "$MUTD/budget-40.ts"; expect_red "G5 row 6b code cap differs from the ADR figure" PARITY-CAP
  fi
  if mut_r "parity: the \$25 ceiling dropped from the amendment" "$ADR_P" "$MUTD/adr-no25.md" 'Monthly(\s+)ceiling(\s+)(\*\*)?\$25(\*\*)?' 'Monthly\g<1>ceiling\g<2>unset'; then
    helper parity "$WF" "$MUTD/adr-no25.md" "$BUDGET"; expect_red "parity: monthly ceiling missing" PARITY-FIGURE
  fi
  if mut_r "parity: the \$2.50 review trigger dropped from the amendment" "$ADR_P" "$MUTD/adr-no250.md" 'Review(\s+)trigger(\s+)(\*\*)?\$2\.50(\*\*)?' 'Review\g<1>trigger\g<2>unset'; then
    helper parity "$WF" "$MUTD/adr-no250.md" "$BUDGET"; expect_red "parity: review trigger missing" PARITY-FIGURE "Review trigger"
  fi
  : > "$MUTD/empty-budget.ts"
  helper parity "$WF" "$ADR" "$MUTD/empty-budget.ts"; expect_red "parity: budget helper without RUN_BUDGET_USD" BUDGET-UNREADABLE
else
  no "parity mutants cannot run: ADR amendment / budget helper / workflow are not all present and green ($(grep '^VIOLATION' <<<"$PARITY_REAL" | head -3 | tr '\n' '|'))"
fi

echo "== parity mutants (D8): allowlist, PROBE_STEP_NAME =="
PRISTINE_RUNNER="$PRISTINE/$(basename "$RUNNER_REL")"
if [[ -f "$PRISTINE_WF" && -f "$PRISTINE_RUNNER" ]] && ! grep -q '^VIOLATION' <<<"$ALLOW_REAL" && ! grep -q '^VIOLATION' <<<"$STEPNAME_REAL"; then
  allow_mut() { # <name> <code> <old> <new> [substring]  (text mutation of a runner copy)
    local m="$MUTD/runner-$1.sh"
    if mut_t "$1" "$PRISTINE_RUNNER" "$m" "$3" "$4"; then helper allowlist "$m" "$SCRATCH/ruled-push.txt"; expect_red "allowlist $1" "$2" "${5-}"; else MUT_RUN=$((MUT_RUN + 1)); fi
  }
  allow_mut allowlist-agent-env-dropped ALLOWLIST-MISSING '|apps/web-platform/server/agent-env.ts)' ')' "apps/web-platform/server/agent-env.ts"
  allow_mut allowlist-probe-budget-dropped ALLOWLIST-MISSING '|apps/web-platform/scripts/lib/probe-budget.ts)' ')' "scripts/lib/probe-budget.ts"
  allow_mut allowlist-extra-entry ALLOWLIST-EXTRA '|apps/web-platform/server/agent-env.ts)' '|apps/web-platform/server/agent-env.ts|apps/web-platform/server/logger.ts)' "apps/web-platform/server/logger.ts"
  allow_mut allowlist-hooks-narrowed ALLOWLIST-MISSING 'plugins/soleur/hooks/*)' 'plugins/soleur/hooks/sub/*)' "plugins/soleur/hooks/**"
  allow_mut allowlist-workflow-dropped ALLOWLIST-MISSING '.github/workflows/scheduled-real-sdk-ask-probe.yml) return 0' '.github/workflows/not-this-one.yml) return 0' "scheduled-real-sdk-ask-probe.yml"
  : > "$MUTD/runner-empty.sh"
  helper allowlist "$MUTD/runner-empty.sh" "$SCRATCH/ruled-push.txt"; expect_red "allowlist a runner without in_run_allowlist" ALLOWLIST-UNREADABLE
  if [[ "$(fact patterns)" -lt 12 ]]; then ok "allowlist an empty runner trips the dispatch floor (patterns<12)"; else no "allowlist an empty runner did not trip the dispatch floor"; fi
  # the derivation drops only package files: a package file in the runner arms is an EXTRA, not silently skipped
  allow_mut allowlist-package-json-added ALLOWLIST-EXTRA '|apps/web-platform/server/agent-env.ts)' '|apps/web-platform/server/agent-env.ts|apps/web-platform/package.json)' "apps/web-platform/package.json"

  # PROBE_STEP_NAME parity
  if mut_r "PROBE_STEP_NAME constant renamed in the runner copy" "$PRISTINE_RUNNER" "$MUTD/runner-stepname.sh" '^(PROBE_STEP_NAME=["'"'"']?)Record that' '\g<1>Skip that'; then
    helper stepname "$WF" "$MUTD/runner-stepname.sh"; expect_red "stepname the runner constant drifts from the workflow" STEPNAME-PARITY
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step renamed in the workflow copy" "$PRISTINE_WF" "$MUTD/wf-stepname.yml" "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='measured'][0]['name']='Run the probe'"; then
    helper stepname "$MUTD/wf-stepname.yml" "$RUNNER"; expect_red "stepname the workflow step drifts from the runner constant" STEPNAME-PARITY
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step name removed in the workflow copy" "$PRISTINE_WF" "$MUTD/wf-noname.yml" "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='measured'][0].pop('name')"; then
    helper stepname "$MUTD/wf-noname.yml" "$RUNNER"; expect_red "stepname a nameless baseline-marker step" STEPNAME-WF-UNREADABLE
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step widened to every outcome" "$PRISTINE_WF" "$MUTD/wf-measured-any.yml" "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='measured'][0].__setitem__('if','always()')"; then
    helper stepname "$MUTD/wf-measured-any.yml" "$RUNNER"; expect_red "stepname a marker that runs after a blind outcome" STEPNAME-MEASURED-IF
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step also accepts blind" "$PRISTINE_WF" "$MUTD/wf-measured-blind.yml" "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='measured'][0].__setitem__('if',\"always() && (steps.probe.outputs.outcome == 'pass' || steps.probe.outputs.outcome == 'fail' || steps.probe.outputs.outcome == 'blind')\")"; then
    helper stepname "$MUTD/wf-measured-blind.yml" "$RUNNER"; expect_red "stepname a marker that also accepts blind" STEPNAME-MEASURED-IF
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step made unfailable" "$PRISTINE_WF" "$MUTD/wf-measured-coe.yml" "[s for s in d['jobs']['probe']['steps'] if s.get('id')=='measured'][0].update({'continue-on-error': True, 'run': 'exit 1'})"; then
    helper stepname "$MUTD/wf-measured-coe.yml" "$RUNNER"; expect_red "stepname a marker with continue-on-error and exit" STEPNAME-MEASURED-BODY
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_y "baseline-marker step moved before the probe step" "$PRISTINE_WF" "$MUTD/wf-measured-early.yml" "(lambda L: (L.insert(0, L.pop([i for i,s in enumerate(L) if s.get('id')=='measured'][0]))))(d['jobs']['probe']['steps'])"; then
    helper stepname "$MUTD/wf-measured-early.yml" "$RUNNER"; expect_red "stepname a marker ordered before the probe" STEPNAME-MEASURED-ORDER
  else MUT_RUN=$((MUT_RUN + 1)); fi
  helper stepname "$WF" "$MUTD/runner-empty.sh"; expect_red "stepname a runner without the constant" STEPNAME-RUNNER-UNREADABLE
  # TWO_PASS_MIN is derived from the probe source: a slower per-case timer must red the pristine 50-minute step ceiling.
  if mut_t "probe per-case abort timer raised to 300 s in the probe copy" "$REPO_ROOT/$PROBE_REL" "$MUTD/probe-slow.ts" 'abort.abort(), 180_000' 'abort.abort(), 300_000'; then
    RSAP_PROBE_TS="$MUTD/probe-slow.ts" helper posture "$WF"; expect_red "timeouts a slower per-case timer is not covered by the step ceiling" TIMEOUT-TWO-PASS
  else MUT_RUN=$((MUT_RUN + 1)); fi
  if mut_t "probe timer unreadable in the probe copy" "$REPO_ROOT/$PROBE_REL" "$MUTD/probe-notimer.ts" 'abort.abort(), 180_000' 'abort.abort(), LIMIT_MS'; then
    RSAP_PROBE_TS="$MUTD/probe-notimer.ts" helper posture "$WF"; expect_red "timeouts an unreadable per-case timer is refused, not defaulted" TIMEOUT-DERIVE
  else MUT_RUN=$((MUT_RUN + 1)); fi
else
  no "parity mutants cannot run: the pristine workflow/runner is absent or a parity check is red ($(grep -h '^VIOLATION' <<<"${ALLOW_REAL-}${STEPNAME_REAL-}" | head -3 | tr '\n' '|'))"
fi

# ---------------------------------------------------------------------------------------------------------------
# PRISTINE INTEGRITY: nothing above may have edited a live file.
# ---------------------------------------------------------------------------------------------------------------
for rel in "$WF_REL" "$ADR_REL" "$PROBE_REL" "$PERM_REL" "$BUDGET_REL" "$RUNNER_REL"; do
  if [[ -f "$PRISTINE/$(basename "$rel")" ]]; then
    if cmp -s "$PRISTINE/$(basename "$rel")" "$REPO_ROOT/$rel"; then ok "live file untouched by the battery: $rel"; else no "live file changed during the run: $rel"; fi
  fi
done

# ---------------------------------------------------------------------------------------------------------------
# FLOORS AND VERDICT. Reported through printf + exit, never through ok()/no(), so a neutered tally cannot disarm them.
# MIN_ASSERTIONS and MIN_MUTANTS are LOWER BOUNDS (the measured counts at the last edit); raise them with a new row.
# ---------------------------------------------------------------------------------------------------------------
echo ""
echo "real-sdk-ask-probe-workflow.test.sh: $passes passed, $fails failed ($((passes + fails)) assertions, $MUT_KILLED/$MUT_RUN mutants killed)"
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1; fi
MIN_ASSERTIONS=307
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2; exit 1
fi
MIN_MUTANTS=115
if [[ "$MUT_RUN" -lt "$MIN_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$MIN_MUTANTS" >&2; exit 1
fi
if [[ "$MUT_KILLED" -ne "$MUT_RUN" ]]; then
  printf '[FATAL] %s of %s mutants survived\n' "$((MUT_RUN - MUT_KILLED))" "$MUT_RUN" >&2
  printf '  failed: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then printf '  failed: %s\n' "${FAILED[@]}" >&2; exit 1; fi
exit 0
