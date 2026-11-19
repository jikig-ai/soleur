#!/usr/bin/env bash
# Workflow-grep suite for the #12931 migration-in-progress predicate's PLACEMENT (CTO ruling L79).
#
# The predicate (apps/web-platform/infra/scripts/cf-account-migration-complete.sh) runs as the last
# step of .github/actions/infra-credentials/action.yml and decides its own scope. Its behaviour is
# pinned by apps/web-platform/infra/cf-account-migration-complete.test.sh; THIS suite pins that it
# is reachable from every job that can plan against the web-platform root:
#
#   (1) derive the workflows that run `terraform plan|apply|import|state rm|mv|push` against
#       apps/web-platform/infra (working-directory / -chdir / cd after resolving ${{ env.X }},
#       ${{ matrix.X }} and $X, or a job carrying key=web-platform/terraform.tfstate). Every derived
#       workflow is in the script's gated list or a named exempt workflow, and every gated workflow
#       is derived. An unresolvable directory is RED (one named allowance, below).
#   (2) every such job of a gated workflow (exempt jobs aside) uses ./.github/actions/infra-credentials
#       BEFORE its first such command, unconditionally (no `if:`, no `continue-on-error`, only
#       declared inputs); the action's last step is the predicate, unconditional, env-bound.
#   (3) the exempt jobs exist and contain none of those commands.
#   (4) cf-account-migrate.yml shares the concurrency literal and carries no ssh bridge, ssh,
#       upload-artifact or TF_LOG (skipped with a note until the file exists; the logic is also
#       driven against a synthesized fixture so it is never untested).
#   (5) apply-web-platform-infra.yml contains no `cf-account-migrate` token.
#
# The gated workflow list and the exempt jobs are READ FROM THE SCRIPT (sourced), never re-typed.
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
wfdir, action_path, gated_s, exempt_jobs_s = sys.argv[1:5]
GATED = set(gated_s.split())
EXEMPT_JOBS = set(exempt_jobs_s.split())
ROOT = "apps/web-platform/infra"
STATE_KEY = "key=web-platform/terraform.tfstate"
# Named exempt workflows that may plan against the root (L79). Out of the predicate's scope.
NAMED_EXEMPT = {"scheduled-terraform-drift.yml", "infra-validation.yml", "cf-account-migrate.yml"}
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
docs, analyzed = {}, {}
for f in sorted(glob.glob(os.path.join(wfdir, "*.yml")) + glob.glob(os.path.join(wfdir, "*.yaml"))):
    t = open(f).read()
    rel = os.path.basename(f)
    if "terraform" not in t and rel not in (AWPI, MIGRATE):
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
unknown = sorted(derived - GATED - NAMED_EXEMPT)
out("RED" if unknown else "OK", "A1-unknown-planner",
    ("workflows plan against %s but are neither gated nor named exempt: %s" % (ROOT, unknown)) if unknown
    else "every derived planner is gated or named exempt (derived=%s)" % sorted(derived))
stale = sorted(GATED - derived)
out("RED" if stale else "OK", "A1-gated-derived",
    ("gated workflows that no longer plan against the root: %s" % stale) if stale else "every gated workflow is derived")
for ex in sorted(NAMED_EXEMPT):
    if ex == MIGRATE:
        if ex not in docs:
            out("NOTE", "A1-exempt-" + ex, "absent (being written concurrently); not asserted")
        elif ex not in derived:
            out("NOTE", "A1-exempt-" + ex, "present; its terraform runs inside a script, so it is not derived inline")
        continue
    out("OK" if ex in derived else "RED", "A1-exempt-" + ex,
        "%s %s derived as a root planner" % (ex, "is" if ex in derived else "is NOT (stale exempt name)"))
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
probs = []
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
    for jid, job in ((doc.get("jobs") or {}).items()):
        for s in (job.get("steps") or []) if isinstance(job, dict) else []:
            if isinstance(s, dict) and re.search(r"(?:^|[;&|(!]|\$\(|\bthen\b|\bdo\b)\s*(?:sudo\s+)?(?:ssh|scp|sftp)\s", normal_text(str(s.get("run") or "")), re.M):
                p.append("job %s runs ssh" % jid)
    return p
if MIGRATE in docs:
    p = check_migrate(MIGRATE)
    out("RED" if p else "OK", "A4-migrate", "; ".join(p) if p else "%s shares the concurrency literal; no ssh bridge, ssh, upload-artifact or TF_LOG" % MIGRATE)
else:
    out("SKIP", "A4-migrate", "%s does not exist yet (written concurrently); assertion becomes real when it lands" % MIGRATE)

# (5)
t = docs.get(AWPI, (None, ""))[1]
out("RED" if "cf-account-migrate" in t else "OK", "A5-no-token",
    "%s %s the cf-account-migrate token" % (AWPI, "contains" if "cf-account-migrate" in t else "does not contain"))
PY

GATED_LIST="$(bash -c 'source "$1"; printf "%s " "${CFAM_GATED_WORKFLOWS[@]}"' _ "$SCRIPT")"
EXEMPT_LIST="$(bash -c 'source "$1"; printf "%s " "${CFAM_EXEMPT_JOBS[@]}"' _ "$SCRIPT")"
if [[ -n "${GATED_LIST// /}" && -n "${EXEMPT_LIST// /}" ]]; then
  ok "scope lists read from the script: gated=[${GATED_LIST% }] exempt-jobs=[${EXEMPT_LIST% }]"
else
  no "scope lists could not be read from the script"
fi

mkdir -p "$WORK/cache"
analyze() { # <wfdir> <action> [gated] [exempt] -> analyzer lines on stdout
  CFAM_SCOPE_CACHE="$WORK/cache" python3 "$ANALYZER" "$1" "$2" "${3:-$GATED_LIST}" "${4:-$EXEMPT_LIST}" 2>&1
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
for id in A1-unresolvable A1-unknown-planner A1-gated-derived A1-floor A2-loader-first A2-floor A2-action-step A3-exempt-jobs A5-no-token; do
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
SCAN_OUT="$(analyze "$WORK/scan" "$ACTION" "apply-web-platform-infra.yml" "$EXEMPT_LIST")"
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
mut_row "a new planner workflow outside the lists"  A1-unknown-planner  apply-github-infra.yml 's#^  INFRA_DIR: infra/github#  INFRA_DIR: apps/web-platform/infra#'
mut_row "a gated root's directory becomes unresolvable" A1-unresolvable cf-lb-overlay.yml      's#^  INFRA_DIR: apps/web-platform/infra#  INFRA_DIR: ${{ vars.SOME_DIR }}#'
mut_row "the loader is removed from a gated job"    A2-loader-first     apply-deploy-pipeline-fix.yml 's#uses: \./\.github/actions/infra-credentials#uses: ./.github/actions/not-the-loader#'
mut_row "the loader step becomes conditional"       A2-loader-first     cf-lb-overlay.yml      's#^( +)uses: \./\.github/actions/infra-credentials$#\1uses: ./.github/actions/infra-credentials\n\1if: ${{ inputs.skip != true }}#'
mut_row "the loader step gets continue-on-error"    A2-loader-first     "$AWPI"                's#^( +)uses: \./\.github/actions/infra-credentials$#\1uses: ./.github/actions/infra-credentials\n\1continue-on-error: true#'
mut_row "the token lands in apply-web-platform-infra.yml" A5-no-token   "$AWPI"                '1s#^#\# see cf-account-migrate.yml\n#'
mut_row "predicate step made conditional"           A2-action-step      "" 's#^    - name: Cloudflare account migration in-progress gate \(\#12931\)$#&\n      if: ${{ github.job != '"'"'x'"'"' }}#' action
mut_row "predicate step exit masked"                A2-action-step      "" 's#--from-r2$#--from-r2 || true#' action
mut_row "predicate env interpolates the raw input"  A2-action-step      "" 's#CFAM_WEB_HOST_KEY: \$\{\{ github\.event\.inputs\.web_host_key \}\}#CFAM_WEB_HOST_KEY: ${{ inputs.web_host_key }}#' action
mut_row "predicate step dropped"                    A2-action-step      "" '/^    - name: Cloudflare account migration in-progress gate/,$d' action

# Script-list mutations: the lists come from the script, so drive the analyzer with mutated lists.
o="$(analyze "$WFDIR" "$ACTION" "apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml" "$EXEMPT_LIST")"
if grep -q "^RED A1-unknown-planner .*cf-lb-overlay.yml" <<<"$o"; then ok "MUT gated list loses cf-lb-overlay.yml: A1-unknown-planner RED"; else no "MUT gated list loses cf-lb-overlay.yml: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$GATED_LIST" "$EXEMPT_LIST apply")"
if grep -q "^RED A3-exempt-jobs .*apply runs" <<<"$o"; then ok "MUT exempt list gains the planning job 'apply': A3-exempt-jobs RED"; else no "MUT exempt list gains 'apply': stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$GATED_LIST" "$EXEMPT_LIST no_such_job")"
if grep -q "^RED A3-exempt-jobs .*no_such_job is not a job" <<<"$o"; then ok "MUT exempt list gains a stale name: A3-exempt-jobs RED"; else no "MUT exempt list gains a stale name: stayed green"; fi
o="$(analyze "$WFDIR" "$ACTION" "$GATED_LIST apply-sentry-infra.yml" "$EXEMPT_LIST")"
if grep -q "^RED A1-gated-derived .*apply-sentry-infra.yml" <<<"$o"; then ok "MUT gated list gains a non-root workflow: A1-gated-derived RED"; else no "MUT gated list gains a non-root workflow: stayed green"; fi

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
  cf_account_migrate:
    runs-on: ubuntu-latest
    environment: web-platform-infra-apply
    steps:
      - run: echo "no ssh here; never ssh into a host"
      - run: bash apps/web-platform/infra/scripts/cf-account-migrate-job.sh
YML
  cp "$WFDIR/$AWPI" "$1/"
}
mig_fixture "$WORK/mig-ok"
o="$(analyze "$WORK/mig-ok" "$ACTION" "$AWPI" "$EXEMPT_LIST")"
if grep -q '^OK A4-migrate ' <<<"$o"; then ok "A4 control: a conforming cf-account-migrate.yml fixture is green"; else no "A4 control: conforming fixture not green ($(grep A4 <<<"$o"))"; fi
mig_mut() { # <label> <sed-expr>
  local d
  d="$WORK/mig-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  mig_fixture "$d"
  sed -E "$2" "$WORK/mig-ok/cf-account-migrate.yml" > "$d/cf-account-migrate.yml"
  if cmp -s "$WORK/mig-ok/cf-account-migrate.yml" "$d/cf-account-migrate.yml"; then no "MUT A4 $1: did not land"; return; fi
  if analyze "$d" "$ACTION" "$AWPI" "$EXEMPT_LIST" | grep -q '^RED A4-migrate '; then ok "MUT A4 $1: RED"; else no "MUT A4 $1: stayed green"; fi
}
mig_mut "concurrency group differs"   's#group: terraform-apply-web-platform-host#group: cf-migrate#'
mig_mut "cancel-in-progress true"     's#cancel-in-progress: false#cancel-in-progress: true#'
mig_mut "TF_LOG set"                  's#^(    steps:)$#    env:\n      TF_LOG: DEBUG\n\1#'
mig_mut "upload-artifact step"        's#^(    steps:)$#\1\n      - uses: actions/upload-artifact@v4#'
mig_mut "ssh bridge step"             's#^(    steps:)$#\1\n      - uses: ./.github/actions/cf-tunnel-ssh-bridge#'
mig_mut "an ssh command"              's#^      - run: bash apps#      - run: ssh deploy@host true \&\& bash apps#'

# ── verdict ────────────────────────────────────────────────────────────────────────────────
printf '\ntest-cf-account-migration-scope.sh: %s passed, %s failed (%s cases)\n' "$PASS" "$FAIL" "$CASES"
if (( PASS + FAIL != CASES )); then
  printf 'CONSERVATION FAILED: PASS(%s)+FAIL(%s) != CASES(%s)\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
# A4 on the real file is a SKIP until cf-account-migrate.yml lands, so it is not counted here.
MIN_ASSERTIONS=35
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s assertions ran, floor is %s\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
