#!/usr/bin/env bash
# Wiring suite for the bastion REPLACE route's reusable body (#12879, ADR-327 step 2b; CTO ruling Q-R4).
#
# The gate, boot-verify and readiness libraries have their own suites. THIS suite pins that the
# workflow calls them the way their properties assume, in two ways:
#
#   STRUCTURE, from the PARSED workflow (python3 -I + yaml.safe_load, the way GitHub reads it):
#     1. the job's environment; no continue-on-error anywhere; no job-level if: (Q-R6); no shell:/defaults
#        override; no run: block interpolates ${{ }} (so the bodies executed below are the bytes the
#        runner executes)
#     2. the full step list (a closed set) and the step order by id, Require main first
#     3. the exact if: strings of the plan summary, toctou, boot_anchor, apply, verify, cancel_poweroff,
#        record_pin, summary and cleanup steps; no step before the plan summary carries an if:
#     4. a CLOSED set of terraform invocations: comment-stripped, every word `terraform` in any run: body
#        or env:/with: value (any quoting, `"terraform"`, an assignment `tf=terraform`, -chdir= and flags in
#        any order) is one reviewed (step, subcommand) pair; exactly one plan and one apply; the apply's
#        only positional argument is "$PLAN_DIR/tfplan"; no mutating verb (destroy, import, taint, state
#        rm|mv|push, -destroy, -refresh-only) anywhere
#     5. every consumed steps.X.outputs.Y is written by step X (run text, the library it calls, or the
#        composite action's outputs:); every steps.X.outcome names a real step
#     8. the plan files (Q-R8): umask 077 in exactly the read, plan and toctou steps; every line naming
#        tfplan is one reviewed line (nothing cats, jq-dumps or uploads it); the step `uses:` are a closed
#        set (no upload-artifact); no ${{ runner.temp }} anywhere
#   BEHAVIOUR, by EXECUTING the real step bodies (extracted from the parsed workflow) under `env -i`
#   with a PATH that is ONLY a stub directory: stub terraform / doppler / curl / gh / ssh-keygen that
#   record their argv and REFUSE (exit 64) any invocation they do not model (doppler only `-p soleur -c
#   prd_terraform`; terraform show/apply only of the saved plan file), a whitelist of real coreutils and
#   jq, and a fake workspace whose gate and stock libraries are recording stubs (boot-verify and
#   bearer-curl are the real ones, so the TOCTOU re-read and the cancel power-off run their real code
#   against the stub curl). Each step's environment is its OWN parsed env: (plus the workflow env:),
#   with every ${{ }} expression resolved from ONE explicit context table (BASE_CTX, overridden per
#   row with @expr=value); an expression missing from the table, or a harness value for a key the
#   step's env: sets, refuses the run (RED). The harness supplies only runner and job env (GITHUB_*,
#   RUNNER_TEMP, the GITHUB_ENV exports PLAN_DIR / CI_SSH_PUB / HCLOUD_TOKEN) and the stub knobs.
#   GITHUB_ACTIONS is never set, so the libraries' test-only seams stay inert.
#     6. the main-only, tier_b, confirm and pin refusals exit non-zero; the confirm text never reaches
#        a workflow command; a gate ABORT and a stock refusal exit non-zero AND the stub log shows the
#        gate was called; every TOCTOU refusal (servers changed, firewall re-read, Q-R3, a non-integer
#        pre-apply id) exits non-zero and the success writes pre_ids from the FRESH read; the three
#        private_key_* fields and HCLOUD_TOKEN are masked; the cancel step records the library's own
#        verdict (Q-R7) in BOTH workflows, `failed` when the library cannot load; the summaries print
#        one distinct line per cancel verdict (an unknown one included), the Q-R7 next-dispatch lines
#        and go red on an unverified, empty or unrecognised outcome.
#     L. the LIFECYCLE: every run: step of the job, in order, carrying GITHUB_ENV and step outputs as
#        the runner does: terraform plan runs only in the plan step and apply only in the apply step
#        (stub log, every step); no other terraform verb than the reviewed set; the read and plan files
#        are mode 600 (umask 077); a synthetic secret seeded in the plan JSON reaches no step's output,
#        summary, GITHUB_OUTPUT or GITHUB_ENV; the anchor is the current time; the always() cleanup
#        deletes exactly the plan directory (a sibling under RUNNER_TEMP survives).
#     7. mutation rows: one per wiring survivor the review found (SYNTHESIS section A and the round-1
#        fix review) plus the Q-R3, Q-R6, Q-R7 and Q-R8 changes. Each edits a temp copy EXACTLY ONCE
#        (proved: count == 1 and the copy differs) and must turn its named check RED; one row is
#        labelled EQUIVALENT with its reason and must stay green. The unmutated control runs first.
#
# ANTI-VACUITY (ADR-193). The positive control, the control-is-GREEN verdict, the duplicate-id check
# and the exact floors report by printf + exit 1, never through pass()/fail(). Every helper that owns
# a verdict (v, vv, refused, run_step's refusals, mut, equiv, smut) is driven with a must-fail input
# (CONTROLS) whose counters unwind with its subshell. Two suite-helper mutants (smut) run a mutated
# COPY of this suite against a mutated workflow and must exit non-zero on the named control line.
#
# Run: bash tests/scripts/test-bastion-host-replace-workflow.sh
# shellcheck disable=SC2016 # single-quoted programs and expected literals hold $-text on purpose
set -uo pipefail
unset GITHUB_ACTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
REPO="$(cd "$HERE/../.." && pwd)"
RWF="$REPO/.github/workflows/bastion-host-replace.yml"
CWF="$REPO/.github/workflows/bastion-host-create.yml"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d "${TMPDIR}/bhr-workflow.XXXXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
NAME=test-bastion-host-replace-workflow
die() { printf '%s: FAIL (%s)\n' "$NAME" "$1" >&2; exit 1; }

passes=0 fails=0 cases=0
pass() { cases=$((cases + 1)); passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { cases=$((cases + 1)); fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

# ── Positive control: pass() and fail() each move their own counter and the case count ────────
pc="$(passes=0 fails=0 cases=0; pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "$cases")"
[[ "$pc" == "1 1 2" ]] || die "CONTROL positive control: pass()/fail() counters read '${pc}', want '1 1 2'"
echo "positive control: pass() and fail() both move their own counters"

for f in "$RWF" "$CWF"; do
  [[ -f "$f" ]] || die "workflow missing: ${f#"$REPO"/}"
done

# ── The parsed-workflow helper ────────────────────────────────────────────────────────────────
PY="$WORK/wf.py"
cat > "$PY" <<'PY'
import os, re, sys, yaml
from collections import Counter
Loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

def load(p):
    with open(p) as fh:
        return yaml.load(fh, Loader=Loader)

def job_of(doc, name):
    return ((doc or {}).get("jobs") or {}).get(name) or {}

def strip(run):
    return "\n".join(l for l in str(run or "").split("\n") if not l.lstrip().startswith("#"))

def logical(text):
    return re.sub(r"\\\n", " ", text)

def emit(cid, ok, detail=""):
    print(("OK %s" % cid) if ok else ("RED %s %s" % (cid, detail)).rstrip())

def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", str(s).lower()).strip("-")[:48]

def step_key(st, i):
    if st.get("id"):
        return str(st["id"])
    if st.get("name"):
        return "n-" + slug(st["name"])
    return "step%02d" % i

def envstr(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return "" if v is None else str(v)

def extract(wf, job, outdir):
    # Every run: step, keyed by id (else its name): body, working-directory, and its OWN env: as
    # NUL-separated KEY=VALUE records with the ${{ }} expressions left for the harness to resolve.
    os.makedirs(outdir, exist_ok=True)
    doc = load(wf)
    with open(os.path.join(outdir, "_wf.env"), "w") as fh:
        for k, v in ((doc or {}).get("env") or {}).items():
            fh.write("%s=%s\0" % (k, envstr(v)))
    keys = []
    for i, st in enumerate(job_of(doc, job).get("steps") or []):
        if "run" not in st:
            continue
        k = step_key(st, i)
        if k in keys:
            k = "%s-%02d" % (k, i)
        keys.append(k)
        with open(os.path.join(outdir, k + ".sh"), "w") as fh:
            fh.write(str(st["run"]))
        with open(os.path.join(outdir, k + ".wd"), "w") as fh:
            fh.write(str(st.get("working-directory") or ""))
        with open(os.path.join(outdir, k + ".env"), "w") as fh:
            for ek, ev in (st.get("env") or {}).items():
                fh.write("%s=%s\0" % (ek, envstr(ev)))
    with open(os.path.join(outdir, "_order"), "w") as fh:
        fh.write("\n".join(keys) + "\n")

ORDER = ["require_main", "creds", "tier_b", "validate", "readiness", "read", "plan", "plan_summary",
         "toctou", "boot_anchor", "apply", "verify", "cancel_poweroff", "record_pin", "summary", "cleanup"]
# The full step list, a closed set: a run: step by its key (id, else n-<name slug>), any other by id or uses.
STEP_LIST = ["require_main", "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5",
             "hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85", "creds", "tier_b", "validate",
             "readiness", "n-generate-ephemeral-ssh-public-key-for-var-ssh-ke", "n-verify-required-secrets-present",
             "n-extract-r2-backend-credentials-assert-sentry-dsn", "n-terraform-init", "read", "plan", "plan_summary",
             "toctou", "boot_anchor", "apply", "verify", "cancel_poweroff", "record_pin", "summary", "cleanup"]
USES = ["actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5",
        "hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85", "./.github/actions/infra-credentials"]
IFS = {
    "plan_summary": "always()",
    "toctou": "inputs.plan_only != true",
    "boot_anchor": "inputs.plan_only != true",
    "apply": "inputs.plan_only != true",
    "verify": "${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') && inputs.plan_only != true }}",
    "cancel_poweroff": "${{ cancelled() && steps.apply.outcome != 'skipped' && steps.verify.outcome != 'success' && inputs.plan_only != true }}",
    "record_pin": "${{ !cancelled() && steps.verify.outcome == 'success' }}",
    "summary": "always()",
    "cleanup": "always()",
}
# Pin 4, a CLOSED set: every word `terraform` in the job, as (step key, subcommand). record_pin's third
# `output` is its error message ("Read both with terraform output ..."), reviewed text.
TF_SITES = Counter({("n-terraform-init", "init"): 1, ("plan", "plan"): 1, ("plan", "show"): 2, ("apply", "apply"): 1,
                    ("record_pin", "output"): 3, ("summary", "state list"): 1})
TF_WORD = re.compile(r"""(?<![\w.-])['"\\]?terraform(?![\w-])""")
MUTATING = re.compile(r"(?<![\w])-?(destroy|import|taint|untaint|force-unlock|refresh-only)(?![\w-])"
                      r"|(?<![\w-])state\s+(rm|mv|push|replace-provider)(?![\w-])")
# Q-R8: every comment-stripped logical line naming tfplan (whitespace collapsed), a CLOSED list.
TFPLAN_LINES = [
    ('plan', 'doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -out="$PLAN_DIR/tfplan" "${replace_args[@]}" -target=\'tls_private_key.bastion_host_ssh\' -target=\'hcloud_firewall.bastion\' -target=\'hcloud_server.bastion\' -target=\'hcloud_server_network.bastion\' -target=\'hcloud_firewall_attachment.bastion\' -var="ssh_key_path=${CI_SSH_PUB}" 2>&1 | tf_redact_random_ids'),
    ('plan', 'terraform show -no-color "$PLAN_DIR/tfplan" > "$PLAN_DIR/tfplan.txt"'),
    ('plan', 'terraform show -json "$PLAN_DIR/tfplan" > "$PLAN_DIR/tfplan.json"'),
    ('plan', 'rc=0; keys="$(jq -r \'.. | objects | to_entries[] | select(.key | startswith("private_key_")) | .value | strings\' "$PLAN_DIR/tfplan.json")" || rc=$?'),
    ('plan', 'if ! bastion_host_replace_gate "$PLAN_DIR/tfplan.json" "$EXPECTED_ID" "$PLAN_DIR/hetzner-servers.json"; then'),
    ('plan', 'grep -E \'will be destroyed|must be replaced|will be updated in-place|Plan:\' "$PLAN_DIR/tfplan.txt" | head -30 >&2'),
    ('plan', 'if ! stock_preflight_gate tfplan.json; then'),
    ('plan', 'grep -E \'^Plan:\' "$PLAN_DIR/tfplan.txt" || true'),
    ('plan_summary', 'if [[ "${PLAN_OUTCOME}" == success && -f "${PLAN_DIR:-/nonexistent}/tfplan.json" ]]; then'),
    ('plan_summary', 'jq -r \'.resource_changes[] | select((.change.actions | index("no-op")) == null and (.change.actions | index("read")) == null) | "- `\\(.change.actions | join(","))` `\\(.address)`"\' "$PLAN_DIR/tfplan.json"'),
    ('toctou', 'fw_id="$(jq -r \'[.resource_changes[] | select(.address == "hcloud_firewall.bastion") | .change.after.id | tostring][0] // ""\' "$PLAN_DIR/tfplan.json")"'),
    ('apply', 'if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -no-color -input=false "$PLAN_DIR/tfplan" 2>&1 | tf_redact_random_ids; then'),
    ('apply', 'stock_recovery_report bastion-host-replace "$PLAN_DIR/tfplan.json" --probe-state'),
]
UMASK = [("read", "umask 077"), ("plan", "umask 077"), ("toctou", "umask 077")]

def tf_sub(rest):
    toks = rest.lstrip("'\"").split()
    i = 0
    while i < len(toks) and toks[i].startswith("-"):
        i += 1
    if i >= len(toks):
        return "<none>"
    t = toks[i].strip("'\"")
    if t == "state" and i + 1 < len(toks):
        return "state " + toks[i + 1].strip("'\"")
    return t

def walk_keys(node, key):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield v
            yield from walk_keys(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from walk_keys(v, key)

def walk_strings(node):
    if isinstance(node, dict):
        for v in node.values():
            yield from walk_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk_strings(v)
    elif isinstance(node, str):
        yield node

def written(st, repo):
    out = set()
    if "uses" in st and str(st["uses"]).startswith("./"):
        act = os.path.join(repo, str(st["uses"])[2:], "action.yml")
        if os.path.isfile(act):
            out |= set((load(act).get("outputs") or {}).keys())
    run = strip(st.get("run"))
    for line in run.split("\n"):
        if '"$GITHUB_OUTPUT"' in line:
            m = re.search(r"""(?:^|[\s'"])([A-Za-z_][A-Za-z0-9_]*)=""", line)
            if m:
                out.add(m.group(1))
    if re.search(r"(?m)^\s*bastion_boot_verify\s", run) and "scripts/lib/bastion-boot-verify.sh" in run:
        lib = os.path.join(repo, "scripts/lib/bastion-boot-verify.sh")
        for line in open(lib).read().split("\n"):
            if line.lstrip().startswith("#") or "GITHUB_OUTPUT" not in line:
                continue
            m = re.search(r"printf '([A-Za-z_][A-Za-z0-9_]*)=", line)
            if m:
                out.add(m.group(1))
    return out

def structural(wf, cwf, repo):
    try:
        doc = load(wf)
    except Exception:  # an unparseable mutant is RED on every structural row
        doc = {}
    job = job_of(doc, "bastion_host_replace")
    steps = job.get("steps") or []
    emit("S1-environment", job.get("environment") == "web-platform-infra-apply", repr(job.get("environment")))
    coe = list(walk_keys(doc, "continue-on-error"))
    emit("S1-no-continue-on-error", bool(job) and not coe, "%d continue-on-error key(s)" % len(coe))
    emit("S1-no-job-if", bool(job) and "if" not in job, repr(job.get("if")))
    shells = [s.get("id") or s.get("name") for s in steps if "shell" in s]
    emit("S1-no-shell-override", bool(steps) and not shells and "defaults" not in job and "defaults" not in (doc or {}), repr(shells))
    expr = [s.get("id") or s.get("name") for s in steps if "${{" in str(s.get("run") or "")]
    emit("S1-run-no-expression", bool(steps) and not expr, repr(expr))
    keys = [step_key(s, i) if "run" in s else (s.get("id") or s.get("uses") or s.get("name")) for i, s in enumerate(steps)]
    emit("S2-step-list", keys == STEP_LIST, "steps %r" % keys)
    ids = [s.get("id") for s in steps]
    bad = [i for i in ORDER if ids.count(i) != 1]
    emit("S2-ids", not bad, "missing or doubled: %r" % bad)
    emit("S2-require-main-first", bool(ids) and ids[0] == "require_main", repr(ids[:1]))
    pos = [ids.index(i) for i in ORDER if ids.count(i) == 1]
    emit("S2-order", not bad and pos == sorted(pos), "order %r" % [i for i in ids if i in ORDER])
    by = {s.get("id"): s for s in steps if s.get("id")}
    for sid, want in IFS.items():
        got = (by.get(sid) or {}).get("if")
        emit("S3-if-%s" % sid, got == want, "got %r" % got)
    cut = ids.index("plan_summary") if "plan_summary" in ids else len(ids)
    early = [s.get("id") or s.get("name") or s.get("uses") for s in steps[:cut] if "if" in s]
    emit("S3-no-if-before-plan-summary", bool(steps) and not early, repr(early))
    # Pin 4: the closed set of terraform sites.
    sites, apply_rest, mut, tfl, um = Counter(), [], [], Counter(), Counter()
    for k, s in zip(keys, steps):
        text = logical(strip(s.get("run")))
        for m in TF_WORD.finditer(text):
            rest = text[m.end():].split("\n", 1)[0]
            sub = tf_sub(rest)
            sites[(k, sub)] += 1
            if sub == "apply":
                apply_rest.append(rest)
        for blk in ("env", "with"):
            for ek, ev in ((s.get(blk) or {}) if isinstance(s.get(blk), dict) else {}).items():
                if TF_WORD.search(str(ev)):
                    sites[(k, "%s:%s" % (blk, ek))] += 1
        mut += [(k, m.group(0)) for m in MUTATING.finditer(text)]
        for line in text.split("\n"):
            c = re.sub(r"\s+", " ", line.strip())
            if "tfplan" in c:
                tfl[(k, c)] += 1
            if re.search(r"(?<![\w])umask(?![\w])", c):
                um[(k, c)] += 1
    diff = sorted((sites - TF_SITES).items()) + sorted(("missing", k) for k in (TF_SITES - sites))
    emit("S4-terraform-closed-set", bool(steps) and sites == TF_SITES, "unreviewed or missing terraform sites %r" % diff)
    plans = sum(v for (k, sub), v in sites.items() if sub == "plan")
    applies = sum(v for (k, sub), v in sites.items() if sub == "apply")
    emit("S4-one-plan", plans == 1, "%d terraform plan invocation(s)" % plans)
    emit("S4-one-apply", applies == 1, "%d terraform apply invocation(s)" % applies)
    pos_args = None
    if len(apply_rest) == 1:
        rest = re.split(r"\s\d*[>|;&]", apply_rest[0].lstrip("'\""))[0]
        pos_args = [t for t in rest.split() if not t.startswith("-")][1:]
    emit("S4-apply-arg", pos_args == ['"$PLAN_DIR/tfplan"'], "positional %r" % pos_args)
    emit("S4-no-mutating-verb", bool(steps) and not mut, repr(mut))
    w = {s.get("id"): written(s, repo) for s in steps if s.get("id")}
    consumed, outcomes = [], []
    for s in steps:
        blob = " ".join(str(v) for v in [s.get("if", ""), s.get("env", ""), s.get("with", "")])
        consumed += re.findall(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", blob)
        outcomes += re.findall(r"steps\.([A-Za-z0-9_-]+)\.(?:outcome|conclusion)", blob)
    unwritten = sorted({"%s.%s" % c for c in consumed if c[1] not in w.get(c[0], set())})
    emit("S5-outputs", bool(consumed) and not unwritten, "consumed but never written: %r" % unwritten)
    unknown = sorted({o for o in outcomes if o not in w})
    emit("S5-outcomes", bool(outcomes) and not unknown, "unknown step ids: %r" % unknown)
    want_pre = "${{ steps.toctou.outputs.pre_ids }}"
    badenv = [sid for sid in ("verify", "cancel_poweroff", "summary") if ((by.get(sid) or {}).get("env") or {}).get("PRE_IDS") != want_pre]
    emit("S6-preids-env", not badenv, "PRE_IDS not bound from steps.toctou.outputs.pre_ids in %r" % badenv)
    pre = [l for l in strip((by.get("toctou") or {}).get("run")).split("\n") if re.match(r'\s*pre="\$\(jq ', l)]
    emit("S6-pre-from-fresh", len(pre) == 1 and pre[0].rstrip().endswith('"$fresh")"') and "hetzner-servers.json" not in pre[0], repr(pre))
    retired = [os.path.basename(p) for p in (wf, cwf) if "powered_off_or_absent" in open(p).read()]
    emit("S7-no-retired-cancel-token", not retired, repr(retired))
    # Q-R8: the plan-file controls.
    emit("S8-umask-077", um == Counter(UMASK), "umask lines %r" % sorted(um.items()))
    tdiff = sorted((tfl - Counter(TFPLAN_LINES)).items()) + sorted(("missing", k) for k in (Counter(TFPLAN_LINES) - tfl))
    emit("S8-tfplan-closed-set", bool(steps) and tfl == Counter(TFPLAN_LINES), "unreviewed or missing tfplan lines %r" % tdiff)
    uses = [str(s["uses"]) for s in steps if "uses" in s]
    emit("S8-uses-closed", uses == USES, "uses %r" % uses)
    rt = [x for x in walk_strings(doc) if "runner.temp" in x]
    emit("S8-no-runner-temp-expression", bool(steps) and not rt, repr(rt))

def once(src, dst, code):
    s = open(src).read()
    g = {"re": re, "s": s, "n": None}
    exec(code, g)
    if g["n"] != 1 or g["s"] == s:
        sys.exit(3)
    open(dst, "w").write(g["s"])

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "extract":
        extract(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "structural":
        structural(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "mutate":
        once(sys.argv[2], sys.argv[3], sys.argv[4])
PY

# ── The stub PATH (used ALONE) and the fake workspaces ─────────────────────────────────────────
# Each fake models ONLY the argv this job uses and refuses the rest (exit 64, logged): a step that
# runs doppler on another config, shows state instead of the saved plan, or applies without it fails.
STUB="$WORK/bin"
mkdir -p "$STUB" "$WORK/home"
for t in jq grep head tail cat mktemp tr date rm sed awk seq sleep env dirname cut wc sort basename mkdir cp touch ls tee uniq; do
  p="$(command -v "$t")" || die "host tool $t is not available for the stub PATH"
  ln -s "$p" "$STUB/$t"
done
cat > "$STUB/terraform" <<EOF
#!${BASH_BIN}
printf 'terraform' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
refuse() { printf 'TFREFUSED %s\n' "\$*" >> "\$STUB_LOG"; echo "stub terraform: refused \$* (not a modeled invocation)" >&2; exit 64; }
planfile() { [[ -n "\$1" && -f "\$1" && "\$(cat "\$1")" == STUB-PLANFILE ]]; }
args=("\$@"); i=0
while [[ "\${args[\$i]:-}" == -* ]]; do [[ "\${args[\$i]}" == -chdir=* ]] || refuse "global flag \${args[\$i]}"; i=\$((i + 1)); done
sub="\${args[\$i]:-}"; rest=("\${args[@]:\$((i + 1))}")
case "\$sub" in
  init) printf 'TFSUB init\n' >> "\$STUB_LOG" ;;
  plan)
    printf 'TFSUB plan\n' >> "\$STUB_LOG"; out=""
    for a in "\${rest[@]}"; do
      case "\$a" in
        -out=*) out="\${a#-out=}" ;;
        -no-color|-input=false|-replace=*|-target=*|-var=*) ;;
        *) refuse "plan \$a" ;;
      esac
    done
    [[ -n "\$out" ]] || refuse "plan without -out"
    printf 'STUB-PLANFILE' > "\$out"
    exit "\${STUB_TF_PLAN_RC:-0}" ;;
  show)
    printf 'TFSUB show\n' >> "\$STUB_LOG"; op="" json=0
    for a in "\${rest[@]}"; do
      case "\$a" in -json) json=1 ;; -no-color) ;; -*) refuse "show \$a" ;; *) [[ -z "\$op" ]] || refuse "show \$op \$a"; op="\$a" ;; esac
    done
    planfile "\$op" || refuse "show of '\$op' (not the saved plan file)"
    if [[ "\$json" -eq 1 ]]; then cat "\$STUB_PLAN_JSON"; else echo "Plan: 1 to add, 1 to change, 1 to destroy."; fi ;;
  apply)
    printf 'TFSUB apply\n' >> "\$STUB_LOG"; op=""
    for a in "\${rest[@]}"; do
      case "\$a" in -no-color|-input=false) ;; -*) refuse "apply \$a" ;; *) [[ -z "\$op" ]] || refuse "apply \$op \$a"; op="\$a" ;; esac
    done
    planfile "\$op" || refuse "apply without the saved plan file ('\$op')"
    exit "\${STUB_TF_APPLY_RC:-0}" ;;
  state)
    printf 'TFSUB state %s\n' "\${rest[0]:-}" >> "\$STUB_LOG"
    [[ "\${rest[0]:-}" == list && \${#rest[@]} -eq 1 ]] || refuse "state \${rest[*]}"
    printf '%s\n' "\${STUB_STATE_LIST:-hcloud_server.bastion}" ;;
  output) printf 'TFSUB output\n' >> "\$STUB_LOG"; exit 1 ;;
  *) printf 'TFSUB %s\n' "\$sub" >> "\$STUB_LOG"; refuse "\$sub" ;;
esac
EOF
cat > "$STUB/doppler" <<EOF
#!${BASH_BIN}
printf 'doppler' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
refuse() { printf 'DOPPLER_REFUSED %s\n' "\$*" >> "\$STUB_LOG"; echo "stub doppler: refused \$* (only -p soleur -c prd_terraform is modeled)" >&2; exit 64; }
if [[ "\${1:-}" == run ]]; then
  shift; proj="" cfg=""
  while [[ \$# -gt 0 && "\$1" != -- ]]; do
    case "\$1" in
      -p) proj="\${2:-}"; shift 2 ;;
      -c) cfg="\${2:-}"; shift 2 ;;
      --preserve-env) shift ;;
      --name-transformer) [[ "\${2:-}" == tf-var ]] || refuse "--name-transformer \${2:-}"; shift 2 ;;
      *) refuse "run flag \$1" ;;
    esac
  done
  [[ "\$proj" == soleur && "\$cfg" == prd_terraform && "\${1:-}" == -- ]] || refuse "run -p '\$proj' -c '\$cfg'"
  shift
  exec "\$@"
fi
if [[ "\${1:-} \${2:-} \${4:-}" == "secrets get --plain" && \$# -eq 4 ]]; then
  [[ "\${DOPPLER_PROJECT:-}" == soleur && "\${DOPPLER_CONFIG:-}" == prd_terraform ]] || refuse "secrets get from '\${DOPPLER_PROJECT:-}/\${DOPPLER_CONFIG:-}'"
  case "\$3" in SENTRY_DSN) echo "https://synthkey@sentry.invalid/1" ;; *) echo "synth-\$3" ;; esac
  exit 0
fi
refuse "\$*"
EOF
cat > "$STUB/gh" <<EOF
#!${BASH_BIN}
printf 'gh' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
EOF
cat > "$STUB/ssh-keygen" <<EOF
#!${BASH_BIN}
printf 'ssh-keygen' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
EOF
cat > "$STUB/curl" <<EOF
#!${BASH_BIN}
out="" w="" url="" method=GET cfg=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -w) w="\$2"; shift 2 ;;
    -X) method="\$2"; shift 2 ;;
    --config) cfg="\$2"; shift 2 ;;
    --max-time|--noproxy) shift 2 ;;
    https://*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
auth=no
if [[ "\$cfg" == - ]] && grep -q '^header = "Authorization: Bearer ' ; then auth=yes; fi
printf 'curl %s %s auth=%s\n' "\$method" "\$url" "\$auth" >> "\$STUB_LOG"
body_file="" body='{}' code=404
case "\$method \$url" in
  "GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion") body_file="\${STUB_SERVERS:-}"; code="\${STUB_SERVERS_CODE:-200}" ;;
  "GET https://api.hetzner.cloud/v1/firewalls/"*) body_file="\${STUB_FW:-}"; code="\${STUB_FW_CODE:-200}" ;;
  "POST https://api.hetzner.cloud/v1/servers/"*"/actions/poweroff") body='{"action":{"id":7}}'; code=201 ;;
  "GET https://api.hetzner.cloud/v1/actions/7") body='{"action":{"status":"success"}}'; code=200 ;;
esac
[[ -n "\$body_file" && -f "\$body_file" ]] && body="\$(cat "\$body_file")"
if [[ -n "\$out" ]]; then printf '%s' "\$body" > "\$out"; else printf '%s' "\$body"; fi
printf '%b' "\${w//%\{http_code\}/\$code}"
EOF
chmod +x "$STUB/terraform" "$STUB/doppler" "$STUB/gh" "$STUB/ssh-keygen" "$STUB/curl"

mkws() { # <dir> <real|stubbv|broken>: a fake GITHUB_WORKSPACE
  local ws="$1"
  mkdir -p "$ws/scripts/lib" "$ws/tests/scripts/lib" "$ws/apps/web-platform/infra"
  ln -s "$REPO/scripts/lib/bearer-curl.sh" "$ws/scripts/lib/bearer-curl.sh"
  case "$2" in
    real) ln -s "$REPO/scripts/lib/bastion-boot-verify.sh" "$ws/scripts/lib/bastion-boot-verify.sh" ;;
    stubbv) printf '%s\n' 'bastion_boot_verify() { printf "boot_verify %s: %s\n" "$#" "$*" >> "$STUB_LOG"; return "${STUB_BV_RC:-0}"; }' \
      '_bbv_poweroff() { printf "poweroff %s\n" "$*" >> "$STUB_LOG"; _BBV_POWEROFF=powered_off; }' > "$ws/scripts/lib/bastion-boot-verify.sh" ;;
    broken) printf '%s\n' 'return 1' > "$ws/scripts/lib/bastion-boot-verify.sh" ;;
  esac
  printf '%s\n' 'tf_redact_random_ids() { cat; }' > "$ws/tests/scripts/lib/tf-redact-random-ids.sh"
  printf '%s\n' \
    'bastion_host_replace_gate() { printf "gate %s\n" "$*" >> "$STUB_LOG"; echo "stub gate rc=${STUB_GATE_RC:-0}"; return "${STUB_GATE_RC:-0}"; }' \
    'bastion_replace_next_dispatch() { printf "next_dispatch %s\n" "$*" >> "$STUB_LOG"; echo "next dispatch: STUB LINE"; }' \
    > "$ws/tests/scripts/lib/bastion-host-replace-gate.sh"
  printf '%s\n' \
    'stock_preflight_gate() { printf "stock %s cwd=%s\n" "$*" "$PWD" >> "$STUB_LOG"; return "${STUB_STOCK_RC:-0}"; }' \
    'stock_abort_closing() { printf "stock_abort_closing %s\n" "$1" >> "$STUB_LOG"; }' \
    'stock_recovery_report() { printf "stock_recovery_report %s\n" "$*" >> "$STUB_LOG"; }' \
    > "$ws/tests/scripts/lib/stock-preflight-gate.sh"
}
WS="$WORK/ws"; WSV="$WORK/wsv"; WSB="$WORK/wsb"
mkws "$WS" real; mkws "$WSV" stubbv; mkws "$WSB" broken

# ── Synthesized fixtures (cq-test-fixtures-synthesized-only) ──────────────────────────────────
FX="$WORK/fx"; mkdir -p "$FX"
srv() { # <id> [status] [ip] [name] [role]
  jq -cn --argjson id "$1" --arg st "${2:-running}" --arg ip "${3:-10.0.1.70}" --arg nm "${4:-soleur-bastion}" --arg rl "${5:-bastion}" \
    '{id: $id, name: $nm, labels: {role: $rl}, status: $st, private_net: [{network: 9001, ip: $ip, alias_ips: []}], public_net: {ipv4: null}, created: "2026-11-01T00:00:00Z"}'
}
docs() { jq -cn --argjson s "[$(IFS=,; echo "$*")]" '{servers: $s, meta: {pagination: {total_entries: ($s | length)}}}'; }
docs "$(srv 111)" > "$FX/s111.json"
docs > "$FX/s-none.json"
docs "$(srv 111 off)" > "$FX/s111-off.json"
docs "$(srv 112)" > "$FX/s112.json"
docs "$(srv 111 running 10.0.1.71)" > "$FX/s111-ip.json"
docs "$(srv 111 running 10.0.1.70 soleur-bastion web)" > "$FX/s111-role.json"
docs "$(srv 111 running 10.0.1.70 soleur-bastion-old)" > "$FX/s111-name.json"
docs "$(srv 111)" "$(srv 222)" > "$FX/s111-222.json"
docs "$(srv 222)" > "$FX/s222.json"
jq -c '.servers[0].public_net = {ipv4: {ip: "203.0.113.9"}} | .servers[0].created = "2026-11-02T00:00:00Z"' "$FX/s111.json" > "$FX/s111-unprojected.json"
# A non-canonical number (jq 1.7+ keeps the literal: 111.0 == 111 as numbers, "111.0" as text).
sed 's/"id":111,/"id":111.0,/' "$FX/s111.json" > "$FX/s111-noncanonical.json"
grep -qF '"id":111.0,' "$FX/s111-noncanonical.json" || die "fixture: the non-canonical id did not land"
fwdoc() { jq -cn --argjson t "[$(IFS=,; echo "$*")]" '{firewall: {id: 555, name: "soleur-bastion", rules: [], applied_to: $t}}'; }
fws() { printf '{"type":"server","server":{"id":%s}}' "$1"; }
FWL='{"type":"label_selector","label_selector":{"selector":"role=web"},"applied_to_resources":[]}'
fwdoc "$(fws 111)" > "$FX/fw111.json"
fwdoc > "$FX/fw-none.json"
fwdoc "$(fws 111)" "$FWL" > "$FX/fw111-label.json"
fwdoc "$(fws 999)" > "$FX/fw999.json"
fwdoc "$(fws 111)" "$(fws 999)" > "$FX/fw111-999.json"
echo '{}' > "$FX/fw-noarray.json"
# The plan JSON: the firewall a no-op with a known id; the host key's three private_key_* fields,
# multi-line; and a declared root variable holding a synthetic secret (Q-R8: the plan JSON holds every
# declared variable's value in clear) that no step may ever print.
PVMARK=SYNTHETIC-PLAN-VARIABLE-MARKER
KEYS='{"private_key_openssh": "SYNTH-OPENSSH-HEAD\nSYNTH-OPENSSH-LINE-A\nSYNTH-OPENSSH-LINE-B\nSYNTH-OPENSSH-TAIL\n",
       "private_key_pem": "SYNTH-PEM-HEAD\nSYNTH-PEM-LINE-A\nSYNTH-PEM-TAIL\n",
       "private_key_pem_pkcs8": "SYNTH-PEM-HEAD\nSYNTH-PKCS8-LINE-A\nSYNTH-PEM-TAIL\n"}'
jq -n --argjson k "$KEYS" --arg pvm "$PVMARK" '{format_version: "1.2",
  variables: {synthetic_plan_variable: {value: $pvm}},
  resource_changes: [
    {address: "hcloud_firewall.bastion", type: "hcloud_firewall", change: {actions: ["no-op"], before: {id: "555"}, after: {id: "555"}}},
    {address: "tls_private_key.bastion_host_ssh", type: "tls_private_key", change: {actions: ["no-op"], before: $k, after: $k}}],
  prior_state: {values: {root_module: {resources: [{address: "tls_private_key.bastion_host_ssh", values: $k}]}}}}' > "$FX/plan.json"
jq '(.resource_changes[] | select(.address == "hcloud_firewall.bastion") | .change.after) |= del(.id)' "$FX/plan.json" > "$FX/plan-nofwid.json"

# ── The step runner ───────────────────────────────────────────────────────────────────────────
LOG="$WORK/stub.log"; OUT="$WORK/step.out"; GO="$WORK/gh-output"; GS="$WORK/gh-summary"; GE="$WORK/gh-env"; RT="$WORK/runner-temp"
PD="$RT/bastion-replace.TESTDIR0"
mkdir -p "$RT"
STEPS=""
RS_RC=0 RS_OK=0
# THE context table: every ${{ }} expression a step env: (or working-directory) may use, with the value
# a real replace dispatch gives it. A row overrides an entry with @expr=value (or deletes it with
# @!expr); an expression absent from the table refuses the run. `env.*` comes from the workflow env:.
declare -A BASE_CTX=(
  [inputs.confirm]=REPLACE-bastion [inputs.plan_only]=false [inputs.reason]="synthetic reason" [inputs.expected_bastion_server_id]=111
  [secrets.DOPPLER_TOKEN]=synthdoppler [secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED]=synthprivileged [secrets.SENTRY_ACTIONS_RO_TOKEN]=synthsentry
  [github.sha]=0123456789abcdef0123456789abcdef01234567 [github.token]=synthghtoken [github.server_url]=https://github.invalid
  [github.repository]=synthetic/repo [github.run_id]=1 [job.status]=success
  [steps.creds.outputs.source]=tier_b [steps.plan.outcome]=success [steps.toctou.outputs.pre_ids]=111 [steps.preids.outputs.pre_ids]=111
  [steps.boot_anchor.outputs.epoch]=1700000000 [steps.apply.outcome]=success [steps.verify.outcome]=success
  [steps.verify.outputs.server_id]=333 [steps.verify.outputs.poweroff_result]=not_needed [steps.verify.outputs.comment_result]=posted
  [steps.cancel_poweroff.outputs.result]=""
)
declare -A CTX=()
subst() { # <text>: resolve every ${{ expr }} from CTX into SUBST_OUT; rc 1 (SUBST_BAD) on an unstubbed one
  local v="$1" out="" e
  SUBST_BAD=""
  while [[ "$v" == *'${{'* ]]; do
    out+="${v%%'${{'*}"; v="${v#*'${{'}"
    [[ "$v" == *'}}'* ]] || { SUBST_BAD="(unterminated)"; return 1; }
    e="${v%%'}}'*}"; v="${v#*'}}'}"
    e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
    [[ -n "${CTX[$e]+set}" ]] || { SUBST_BAD="$e"; return 1; }
    out+="${CTX[$e]}"
  done
  SUBST_OUT="$out$v"
}
newpd() { # <saved-servers-doc> [plan-json]: a fresh plan directory holding the saved plan file
  rm -rf -- "$PD"; mkdir -p "$PD"
  cp "$1" "$PD/hetzner-servers.json"
  cp "${2:-$FX/plan.json}" "$PD/tfplan.json"
  printf 'STUB-PLANFILE' > "$PD/tfplan"
}
run_step() { # <key> <ws> [@expr=value | @!expr | VAR=value]...: run the extracted step body as the runner would
  local key="$1" ws="$2" script a rec k cwd
  local -a extras=() envs=()
  local stepkeys=" "
  shift 2
  script="$STEPS/$key.sh"
  : > "$LOG"; : > "$GO"; : > "$GS"; : > "$GE"; : > "$OUT"
  RS_OK=0; RS_RC=127
  [[ -f "$script" ]] || { echo "HARNESS: no run: step '$key' in the parsed workflow" > "$OUT"; return 0; }
  CTX=(); for k in "${!BASE_CTX[@]}"; do CTX[$k]="${BASE_CTX[$k]}"; done
  for a in "$@"; do
    case "$a" in
      @!*) unset "CTX[${a#@!}]" ;;
      @*) a="${a#@}"; CTX[${a%%=*}]="${a#*=}" ;;
      *) extras+=("$a") ;;
    esac
  done
  while IFS= read -r -d '' rec; do
    subst "${rec#*=}" || { echo "HARNESS: unstubbed expression '${SUBST_BAD}' in the workflow env ${rec%%=*}" > "$OUT"; RS_RC=125; return 0; }
    CTX[env.${rec%%=*}]="$SUBST_OUT"; envs+=("${rec%%=*}=$SUBST_OUT")
  done < "$STEPS/_wf.env"
  while IFS= read -r -d '' rec; do
    subst "${rec#*=}" || { echo "HARNESS: unstubbed expression '${SUBST_BAD}' in ${key}'s env ${rec%%=*}" > "$OUT"; RS_RC=125; return 0; }
    envs+=("${rec%%=*}=$SUBST_OUT"); stepkeys+="${rec%%=*} "
  done < "$STEPS/$key.env"
  for a in "${extras[@]}"; do
    [[ "$stepkeys" != *" ${a%%=*} "* ]] || { echo "HARNESS: ${key}'s own env: sets ${a%%=*}; the harness never supplies it" > "$OUT"; RS_RC=126; return 0; }
  done
  subst "$(cat "$STEPS/$key.wd")" || { echo "HARNESS: unstubbed expression '${SUBST_BAD}' in ${key}'s working-directory" > "$OUT"; RS_RC=125; return 0; }
  cwd="$ws${SUBST_OUT:+/$SUBST_OUT}"
  [[ -d "$cwd" ]] || { echo "HARNESS: ${key}'s working-directory '${SUBST_OUT}' is not in the fake workspace" > "$OUT"; RS_RC=124; return 0; }
  RS_OK=1
  (cd "$cwd" && env -i PATH="$STUB" HOME="$WORK/home" GITHUB_WORKSPACE="$ws" GITHUB_OUTPUT="$GO" GITHUB_STEP_SUMMARY="$GS" \
    GITHUB_ENV="$GE" RUNNER_TEMP="$RT" STUB_LOG="$LOG" "${extras[@]}" "${envs[@]}" "$BASH_BIN" -e "$script") > "$OUT" 2>&1
  RS_RC=$?
}
v() { # <check-id> <0|1 condition rc> [detail]: one verdict line for a step run (RED when the harness refused it)
  if [[ "$2" -eq 0 && "$RS_OK" -eq 1 ]]; then echo "OK $1"; else echo "RED $1 rc=${RS_RC} ${3:-} $(tr '\n' ' ' < "$OUT" | head -c 300)"; fi
}
vv() { # <check-id> <0|1 condition rc> [detail]: one verdict line for a check across steps
  if [[ "$2" -eq 0 ]]; then echo "OK $1"; else echo "RED $1 ${3:-}"; fi
}
refused() { # <check-id> <message substring>: non-zero exit AND the named refusal printed AND no pre_ids written
  [[ "$RS_RC" -ne 0 ]] && grep -qF -- "$2" "$OUT" && ! grep -q '^pre_ids=' "$GO"
  v "$1" $? "(want a refusal naming '$2')"
}
logged() { grep -qF -- "$1" "$LOG"; }
po_line() { awk 'p { print; exit } /^A green run means/ { p = 1 }' "$GS"; }

# ── analyze <replace-wf> <create-wf> [group...]: every check, one OK/RED line each ──────────────
analyze() {
  local rwf="$1" cwf="$2" g groups
  shift 2
  groups="${*:-S M T V R P A Q B C D X L}"
  STEPS="$WORK/steps.$$.$RANDOM"
  rm -rf -- "$STEPS"; python3 -I "$PY" extract "$rwf" bastion_host_replace "$STEPS" 2>/dev/null || true
  for g in $groups; do
    case "$g" in
      S) python3 -I "$PY" structural "$rwf" "$cwf" "$REPO" 2>&1 || echo "RED S-crash structural analyzer crashed" ;;
      M) run_step require_main "$WS" GITHUB_REF=refs/heads/feat-x
         refused M-branch-refused "Nothing was planned or destroyed."
         run_step require_main "$WS" GITHUB_REF=refs/heads/main
         [[ "$RS_RC" -eq 0 ]]; v M-main-passes $? ;;
      T) run_step tier_b "$WS" @steps.creds.outputs.source=legacy
         refused T-legacy-refused "is HELD"
         run_step tier_b "$WS" @steps.creds.outputs.source=
         refused T-unset-refused "is HELD"
         run_step tier_b "$WS"
         [[ "$RS_RC" -eq 0 ]]; v T-tier_b-passes $? ;;
      V) run_step validate "$WS" @inputs.confirm=REPLACE-bastio
         refused V-confirm-refused "confirm must be exactly"
         run_step validate "$WS" @inputs.confirm=BIRTH-bastion
         refused V-birth-token-refused "confirm must be exactly"
         run_step validate "$WS" "@inputs.confirm=x"$'\n'"::stop-commands::SYNTHTOKEN"$'\n'"::warning::INJECTED"
         [[ "$RS_RC" -ne 0 ]] && ! grep -qE '^::(stop-commands|warning)::' "$OUT" && ! grep -qF SYNTHTOKEN "$OUT" && ! grep -qF INJECTED "$OUT"
         v V-confirm-never-echoed $? "(dispatch text reached a workflow command)"
         for bad in 0123 abc "12 3" 1234567890123 "" "111"$'\n'"222"; do
           run_step validate "$WS" "@inputs.expected_bastion_server_id=$bad"
           refused "V-pin-refused-$(printf '%s' "${bad:-empty}" | tr -c 'A-Za-z0-9' '_')" "expected_bastion_server_id must be"
         done
         run_step validate "$WS" @inputs.expected_bastion_server_id=111
         [[ "$RS_RC" -eq 0 ]]; v V-pin-passes $?
         run_step validate "$WS" @inputs.expected_bastion_server_id=none
         [[ "$RS_RC" -eq 0 ]]; v V-none-passes $? ;;
      R) rm -rf -- "$RT"/bastion-replace.*; mkdir -p "$RT"
         run_step read "$WS" HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s111.json"
         rd="$(sed -n 's/^PLAN_DIR=//p' "$GE")"
         [[ "$RS_RC" -eq 0 && "$rd" == "$RT"/bastion-replace.* && -f "$rd/hetzner-servers.json" ]] && jq -e --slurpfile w "$FX/s111.json" '. == $w[0]' "$rd/hetzner-servers.json" >/dev/null \
           && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion auth=yes" && grep -qF -- '- id `111`' "$GS"
         v R-read-saves-the-graded-document $?
         rm -rf -- "$RT"/bastion-replace.*
         run_step read "$WS" HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s111.json" STUB_SERVERS_CODE=503
         [[ "$RS_RC" -ne 0 ]] && grep -qF "Hetzner server read FAILED" "$OUT" && grep -qF "Nothing was planned or destroyed." "$OUT"
         v R-read-failure-stops-before-the-plan $?
         rm -rf -- "$RT"/bastion-replace.*; mkdir -p "$RT" ;;
      P) local penv=(PLAN_DIR="$PD" CI_SSH_PUB=/tmp/ci_ssh_key.pub HCLOUD_TOKEN=synthetichcloudtoken0 STUB_PLAN_JSON="$FX/plan.json")
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}"
         [[ "$RS_RC" -eq 0 ]] && logged "gate $PD/tfplan.json 111 $PD/hetzner-servers.json" && logged "stock tfplan.json cwd=$PD"
         v P-pass-calls-gate-and-stock $?
         grep -E '^terraform( -[^ ]+)* plan ' "$LOG" > "$WORK/plan-argv" || true
         [[ "$(wc -l < "$WORK/plan-argv")" -eq 1 ]] && grep -qF " -out=$PD/tfplan -replace=hcloud_server.bastion " "$WORK/plan-argv" \
           && [[ "$(grep -o -- ' -target=' "$WORK/plan-argv" | wc -l)" -eq 5 ]]
         v P-replace-arm-plans-replace $?
         ok=0
         for l in SYNTH-OPENSSH-LINE-A SYNTH-OPENSSH-LINE-B SYNTH-PEM-LINE-A SYNTH-PKCS8-LINE-A; do grep -qxF "::add-mask::$l" "$OUT" || ok=1; done
         v P-private-keys-masked "$ok" "(a private_key_* line was not masked)"
         grep -qxF "::add-mask::synthetichcloudtoken0" "$OUT"; v P-hcloud-token-masked $? "(HCLOUD_TOKEN was not masked)"
         newpd "$FX/s-none.json"; run_step plan "$WS" "${penv[@]}" @inputs.expected_bastion_server_id=none
         [[ "$RS_RC" -eq 0 ]] && ! grep -qF -- '-replace=' "$LOG" && logged "gate $PD/tfplan.json none $PD/hetzner-servers.json"
         v P-recovery-arm-plans-no-replace $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" STUB_GATE_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "gate $PD/tfplan.json 111 $PD/hetzner-servers.json" && grep -qF 'gate ABORTED' "$OUT" && ! logged "stock "
         v P-gate-abort-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" STUB_STOCK_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "gate $PD/tfplan.json" && logged "stock tfplan.json" && logged "stock_abort_closing bastion-host-replace"
         v P-stock-refusal-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" STUB_TF_PLAN_RC=1
         [[ "$RS_RC" -ne 0 ]] && ! logged "gate "
         v P-plan-failure-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" HCLOUD_TOKEN=
         [[ "$RS_RC" -ne 0 ]] && logged "gate " && ! logged "stock "
         v P-no-token-stops $? ;;
      A) newpd "$FX/s111.json"; run_step apply "$WS" PLAN_DIR="$PD"
         [[ "$RS_RC" -eq 0 && "$(grep -c '^terraform' "$LOG")" -eq 1 ]] && grep -qxF "terraform apply -no-color -input=false $PD/tfplan" "$LOG" && ! logged TFREFUSED
         v A-applies-only-the-gated-plan $?
         newpd "$FX/s111.json"; run_step apply "$WS" PLAN_DIR="$PD" STUB_TF_APPLY_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "stock_recovery_report bastion-host-replace $PD/tfplan.json --probe-state"
         v A-failed-apply-exits-1 $? ;;
      Q) local qenv=(PLAN_DIR="$PD" HCLOUD_TOKEN=synthetichcloudtoken0)
         toctou() { # <saved> <fresh> <fw> <pin> [plan] [VAR=...]
           local saved="$1" fresh="$2" fw="$3" pin="$4" plan="${5:-$FX/plan.json}"
           shift 5 2>/dev/null || shift $#
           newpd "$saved" "$plan"
           run_step toctou "$WS" "${qenv[@]}" "@inputs.expected_bastion_server_id=$pin" STUB_SERVERS="$fresh" STUB_FW="$fw" "$@"
         }
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=111" ]] && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion auth=yes" \
           && logged "curl GET https://api.hetzner.cloud/v1/firewalls/555 auth=yes"
         v Q-pass-writes-fresh-preids $?
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw-none.json" 111
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=111" ]]; v Q-pass-firewall-unbound-on-replace $?
         toctou "$FX/s-none.json" "$FX/s-none.json" "$FX/fw-none.json" none
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=none" ]]; v Q-pass-recovery $?
         toctou "$FX/s111.json" "$FX/s111-unprojected.json" "$FX/fw111.json" 111
         [[ "$RS_RC" -eq 0 ]]; v Q-pass-unprojected-field-changed $?
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan.json" STUB_SERVERS_CODE=503
         refused Q-servers-read-failure "TOCTOU re-read FAILED"
         local c
         for c in off:s111-off id:s112 ip:s111-ip role:s111-role name:s111-name count:s111-222; do
           toctou "$FX/s111.json" "$FX/${c#*:}.json" "$FX/fw111.json" 111
           refused "Q-changed-${c%%:*}" "the live bastion changed since the plan"
         done
         toctou "$FX/s111.json" "$FX/s111-noncanonical.json" "$FX/fw111.json" 111
         refused Q-pre-ids-not-integer "did not read as an integer"
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan-nofwid.json"
         refused Q-firewall-id-unreadable "hcloud_firewall.bastion id did not read as a number"
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan.json" STUB_FW_CODE=404
         refused Q-firewall-read-failure "TOCTOU firewall read FAILED"
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw-noarray.json" 111
         refused Q-firewall-no-applied-to "TOCTOU firewall read FAILED"
         for c in label:fw111-label other:fw999 extra:fw111-999; do
           toctou "$FX/s111.json" "$FX/s111.json" "$FX/${c#*:}.json" 111
           refused "Q-firewall-${c%%:*}" "firewall is applied to a label selector or to a server other than the pin"
         done
         toctou "$FX/s-none.json" "$FX/s-none.json" "$FX/fw111.json" none
         refused Q-firewall-bound-on-recovery "firewall is applied to a label selector or to a server other than the pin" ;;
      B) run_step verify "$WSV" @steps.apply.outcome=failure STUB_BV_RC=1
         [[ "$RS_RC" -eq 1 ]] && grep -qxF "boot_verify 4: 1700000000 failure bastion-host-replace 111" "$LOG"
         v B-verify-passes-four-args-and-its-rc $?
         run_step verify "$WSV" @steps.toctou.outputs.pre_ids=none @steps.boot_anchor.outputs.epoch=1700000123 STUB_BV_RC=0
         [[ "$RS_RC" -eq 0 ]] && grep -qxF "boot_verify 4: 1700000123 success bastion-host-replace none" "$LOG"
         v B-verify-ready-exits-0 $? ;;
      C) cancel_rows C "$WS" steps.toctou.outputs.pre_ids ;;
      D) summary_rows ;;
      X) local XSTEPS="$WORK/xsteps.$$.$RANDOM" keep="$STEPS"
         python3 -I "$PY" extract "$cwf" bastion_host_create "$XSTEPS" 2>/dev/null || true
         STEPS="$XSTEPS"
         cancel_rows X "$WS" steps.preids.outputs.pre_ids
         run_step verify "$WSV" @steps.apply.outcome=failure STUB_BV_RC=1
         [[ "$RS_RC" -eq 1 ]] && grep -qxF "boot_verify 4: 1700000000 failure bastion-host-create 111" "$LOG"
         v X-verify-passes-four-args-and-its-rc $?
         cancel_lines X
         STEPS="$keep" ;;
      L) lifecycle_rows ;;
    esac
  done
}
cancel_rows() { # <prefix> <ws> <pre-ids expression>: the cancel step records the library's own verdict (Q-R7)
  local p="$1" ws="$2" pk="$3" cenv=(HCLOUD_TOKEN=synthetichcloudtoken0)
  run_step cancel_poweroff "$ws" "${cenv[@]}" "@$pk=" STUB_SERVERS="$FX/s111-222.json"
  [[ "$RS_RC" -ne 0 && "$(cat "$GO")" == "result=refused_no_preids" ]] && ! logged "curl POST"; v "$p-cancel-records-refused" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" "@$pk=111" STUB_SERVERS="$FX/s111-222.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=powered_off" ]] && logged "curl POST https://api.hetzner.cloud/v1/servers/222/actions/poweroff auth=yes" \
    && ! logged "servers/111/actions"; v "$p-cancel-powers-off-the-new-server" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" "@$pk=111" STUB_SERVERS="$FX/s111.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=old_untouched" ]] && ! logged "curl POST"; v "$p-cancel-records-old-untouched" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" "@$pk=none" STUB_SERVERS="$FX/s-none.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=absent" ]]; v "$p-cancel-records-absent" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" "@$pk=111" STUB_SERVERS="$FX/s111-222.json" STUB_SERVERS_CODE=500
  [[ "$RS_RC" -ne 0 && "$(cat "$GO")" == "result=failed" ]]; v "$p-cancel-records-failed" $?
  run_step cancel_poweroff "$WSB" "${cenv[@]}" "@$pk=111" STUB_SERVERS="$FX/s111-222.json"
  [[ "$RS_RC" -ne 0 && "$(cat "$GO")" == "result=failed" ]] && ! logged "curl "; v "$p-cancel-source-failure-records-failed" $?
}
cancel_lines() { # <prefix>: the summary prints one distinct line per cancel verdict; REFUSED is not FAILED; an unknown one is UNKNOWN
  local p="$1" r=0 lines="" rl="" fl="" ul=""
  local sctx=(@steps.plan.outcome=success @steps.apply.outcome=cancelled @steps.verify.outcome=skipped @job.status=cancelled)
  for r in powered_off absent old_untouched refused_no_preids failed; do
    run_step summary "$WS" "${sctx[@]}" "@steps.cancel_poweroff.outputs.result=$r"
    lines+="$(po_line)"$'\n'
    [[ "$r" == refused_no_preids ]] && rl="$(po_line)"
    [[ "$r" == failed ]] && fl="$(po_line)"
  done
  [[ "$(grep -c . <<<"$lines")" -eq 5 && "$(sort -u <<<"$lines" | grep -c .)" -eq 5 ]] && ! grep -qE 'no verdict recorded|UNKNOWN verdict' <<<"$lines"
  v "$p-summary-one-line-per-cancel-verdict" $? "(lines: $(tr '\n' '|' <<<"$lines"))"
  r=0; [[ "$rl" == *REFUSED* && "$rl" != *FAILED* && "$fl" == *FAILED* ]] || r=1
  v "$p-summary-refused-is-not-failed" "$r" "(refused '$rl' failed '$fl')"
  run_step summary "$WS" "${sctx[@]}" @steps.cancel_poweroff.outputs.result=synthetic_new_verdict
  ul="$(po_line)"
  [[ "$ul" == *"UNKNOWN verdict"* ]] && ! grep -qxF -- "$ul" <<<"$lines"
  v "$p-summary-unknown-cancel-verdict" $? "(line '$ul')"
}
summary_rows() { # the replace summary's next-dispatch lines (Q-R7) and its red exits
  local senv=(PLAN_DIR="$PD" HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s222.json")
  newpd "$FX/s111.json"
  run_step summary "$WS" "${senv[@]}" @steps.plan.outcome=success @steps.apply.outcome=success @steps.verify.outcome=success \
    @steps.verify.outputs.server_id=333 @steps.verify.outputs.poweroff_result=not_needed
  [[ "$RS_RC" -eq 0 ]] && grep -qxF -- "- next dispatch: none needed — the replacement is READY as server 333; the next replace pins that id." "$GS" \
    && ! logged next_dispatch && ! logged "curl " && ! logged terraform && ! grep -qF 'gh workflow run' "$GS"
  v D-ready-needs-no-dispatch $?
  for o in "" skipped; do
    run_step summary "$WS" "${senv[@]}" "@steps.plan.outcome=$o" @steps.apply.outcome=skipped @steps.verify.outcome=skipped @job.status=failure
    [[ "$RS_RC" -eq 0 ]] && grep -qxF -- "- next dispatch: nothing was read (the run stopped before the plan); fix the refusal above and re-dispatch." "$GS" \
      && ! logged next_dispatch && ! logged "curl " && ! logged terraform && ! grep -qF 'FAILED' "$OUT"
    v "D-stopped-before-plan-reads-nothing-${o:-empty}" $?
  done
  run_step summary "$WS" "${senv[@]}" @steps.plan.outcome=success @steps.apply.outcome=failure @steps.verify.outcome=failure \
    @steps.verify.outputs.poweroff_result=powered_off @steps.toctou.outputs.pre_ids=111 @job.status=failure
  [[ "$RS_RC" -eq 0 ]] && logged "next_dispatch 111 $PD/hetzner-servers-after.json 1" && logged "terraform state list" && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion"
  v D-failed-run-reads-fresh-for-next-dispatch $?
  run_step summary "$WS" "${senv[@]}" @steps.plan.outcome=success @steps.apply.outcome=success @steps.verify.outcome=skipped @job.status=failure
  [[ "$RS_RC" -ne 0 ]] && grep -qF "the replacement is UNVERIFIED and may be running" "$OUT"
  v D-red-success-unverified $?
  run_step summary "$WS" "${senv[@]}" @steps.plan.outcome=success @steps.apply.outcome=synthetic @steps.verify.outcome=pair @job.status=failure
  [[ "$RS_RC" -ne 0 ]] && grep -qF "unrecognised outcome pair 'synthetic/pair'" "$OUT"
  v D-red-unrecognised-pair $?
  # verify=failure: the one empty-apply pair the case below would pass (*/failure), so only the EMPTY exit refuses it.
  run_step summary "$WS" "${senv[@]}" @steps.plan.outcome=success @steps.apply.outcome= @steps.verify.outcome=failure @job.status=failure
  [[ "$RS_RC" -ne 0 ]] && grep -qF "a step outcome is EMPTY" "$OUT"
  v D-red-empty-outcome $?
  cancel_lines D
}
# ── The lifecycle: EVERY run: step in order, as the runner carries GITHUB_ENV and step outputs ──
# The composite credential loader is not a run: step; its exports are the table's
# steps.creds.outputs.source and the job env HCLOUD_TOKEN. The verify step runs against the recording
# boot-verify stub (the real one polls Sentry); every other step runs the real libraries.
TF_LOG_ALLOWED=" n-terraform-init:init plan:plan plan:show apply:apply record_pin:output summary:state_list "
lifecycle_rows() {
  local key ws line k r pdl="" mode_read="" mode_plan="" seeded=1 notrun="" now epoch
  local -A job=([HCLOUD_TOKEN]=synthetichcloudtoken0 [GITHUB_REF]=refs/heads/main) lctx=()
  local -a args
  local tf="$WORK/life-tf.$RANDOM" all="$WORK/life-out.$RANDOM"
  : > "$tf"; : > "$all"
  rm -rf -- "$RT"; mkdir -p "$RT/keep.sentinel"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    ws="$WS"; [[ "$key" == verify ]] && ws="$WSV"
    args=()
    for k in "${!lctx[@]}"; do args+=("@$k=${lctx[$k]}"); done
    for k in "${!job[@]}"; do args+=("$k=${job[$k]}"); done
    run_step "$key" "$ws" "${args[@]}" STUB_SERVERS="$FX/s111.json" STUB_FW="$FX/fw111.json" STUB_PLAN_JSON="$FX/plan.json"
    [[ "$RS_OK" -eq 1 ]] || notrun+="$key($(head -c 120 "$OUT")) "
    sed -n "s|^TFSUB \(.*\)|$key:\1|p" "$LOG" | tr ' ' '_' >> "$tf"
    grep -E '^terraform .* -(destroy|refresh-only)( |$)' "$LOG" | sed "s|^|$key:argv:|" >> "$tf" || true
    cat "$OUT" "$GS" "$GO" "$GE" >> "$all"
    case "$key" in
      read) pdl="$(sed -n 's/^PLAN_DIR=//p' "$GE" | tail -1)"; mode_read="$(stat -c %a "$pdl/hetzner-servers.json" 2>/dev/null)" ;;
      plan) mode_plan="$(cd "$pdl" 2>/dev/null && stat -c '%n=%a' tfplan tfplan.txt tfplan.json 2>/dev/null | tr '\n' ' ')"
            grep -qF "$PVMARK" "$pdl/tfplan.json" 2>/dev/null && seeded=0 ;;
    esac
    while IFS= read -r line; do [[ "$line" == *=* ]] && job[${line%%=*}]="${line#*=}"; done < "$GE"
    while IFS= read -r line; do [[ "$line" == *=* ]] && lctx[steps.$key.outputs.${line%%=*}]="${line#*=}"; done < "$GO"
    if [[ "$RS_RC" -eq 0 ]]; then lctx[steps.$key.outcome]=success; else lctx[steps.$key.outcome]=failure; fi
  done < "$STEPS/_order"
  r=0; [[ -s "$STEPS/_order" && -z "$notrun" ]] || r=1; vv L-every-run-step-executed "$r" "(the harness could not run: ${notrun})"
  r=0; [[ "$(grep -c '^plan:plan$' "$tf")" -eq 1 && "$(grep -c ':plan$' "$tf")" -eq 1 ]] || r=1
  vv L-plan-only-in-plan "$r" "(terraform plan ran as: $(grep ':plan$' "$tf" | tr '\n' ' '))"
  r=0; [[ "$(grep -c '^apply:apply$' "$tf")" -eq 1 && "$(grep -c ':apply$' "$tf")" -eq 1 ]] || r=1
  vv L-apply-only-in-apply "$r" "(terraform apply ran as: $(grep ':apply$' "$tf" | tr '\n' ' '))"
  local odd=""
  while IFS= read -r line; do [[ "$TF_LOG_ALLOWED" == *" $line "* ]] || odd+="$line "; done < "$tf"
  r=0; [[ -s "$tf" && -z "$odd" ]] || r=1; vv L-terraform-log-closed-set "$r" "(unreviewed terraform invocations: ${odd:-none logged})"
  r=0; [[ "$mode_read" == 600 ]] || r=1; vv L-umask-read "$r" "(hetzner-servers.json mode '${mode_read}', want 600)"
  r=0; [[ "$mode_plan" == "tfplan=600 tfplan.txt=600 tfplan.json=600 " ]] || r=1; vv L-umask-plan "$r" "(plan files '${mode_plan}', want 600 each)"
  r=0; [[ "$seeded" -eq 0 ]] && ! grep -qF "$PVMARK" "$all" || r=1
  vv L-no-plan-secret-printed "$r" "(seeded in tfplan.json: $([[ "$seeded" -eq 0 ]] && echo yes || echo NO); printed: $(grep -c -F "$PVMARK" "$all") line(s))"
  now="$(date -u +%s)"; epoch="${lctx[steps.boot_anchor.outputs.epoch]:-}"
  r=0; [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch <= now && now - epoch < 600 )) || r=1
  vv L-anchor-is-now "$r" "(anchor '${epoch}', now ${now})"
  r=0; [[ -n "$pdl" && -n "$mode_plan" && ! -e "$pdl" ]] || r=1; vv L-cleanup-deletes-plan-dir "$r" "(plan dir '${pdl}' still present or never made)"
  r=0; [[ -d "$RT/keep.sentinel" ]] || r=1; vv L-cleanup-exact "$r" "(the cleanup removed more than the plan directory)"
  rm -rf -- "$RT"; mkdir -p "$RT"
}

# ── The verdict-owning row helpers ────────────────────────────────────────────────────────────
MUT_N=0 META_N=0
mut() { # <label> <file: replace|create> <group> <check-id> <python: sets s and n (n = matches, must be 1)>
  local label="$1" which="$2" group="$3" want="$4" code="$5" r="$WORK/control-replace.yml" c="$WORK/control-create.yml" dst o
  MUT_N=$((MUT_N + 1))
  dst="$WORK/mut-$MUT_N.yml"
  if [[ "$which" == replace ]]; then
    python3 -I "$PY" mutate "$r" "$dst" "$code" 2>/dev/null && ! cmp -s "$r" "$dst" || { fail "mutation did not land exactly once: $label"; return; }
    o="$(analyze "$dst" "$c" "$group")"
  else
    python3 -I "$PY" mutate "$c" "$dst" "$code" 2>/dev/null && ! cmp -s "$c" "$dst" || { fail "mutation did not land exactly once: $label"; return; }
    o="$(analyze "$r" "$dst" "$group")"
  fi
  if grep -qE "^RED ${want}( |$)" <<<"$o"; then pass "mutation RED ($want): $label"; else fail "mutation SURVIVED ($want stayed green): $label"; fi
}
equiv() { # <label> <reason> <group> <check-id> <python>: a mutant that is EQUIVALENT in production must stay green
  local label="$1" reason="$2" group="$3" want="$4" code="$5" r="$WORK/control-replace.yml" dst o
  MUT_N=$((MUT_N + 1))
  dst="$WORK/mut-$MUT_N.yml"
  python3 -I "$PY" mutate "$r" "$dst" "$code" 2>/dev/null && ! cmp -s "$r" "$dst" || { fail "mutation did not land exactly once: $label"; return; }
  o="$(analyze "$dst" "$WORK/control-create.yml" "$group")"
  if grep -qE "^OK ${want}$" <<<"$o"; then pass "EQUIVALENT ($want stays green): $label — $reason"; else fail "EQUIVALENT row went RED ($want): $label — it is not equivalent; make it a mut row"; fi
}
smut() { # <label> <expected control line> <suite python> [workflow python]: a mutated COPY of this suite must exit non-zero on that line
  local label="$1" want="$2" scode="$3" wcode="${4:-}" d o rc
  META_N=$((META_N + 1)); d="$(mktemp -d "$WORK/meta.XXXXXXXX")" || die "mktemp failed"
  mkdir -p "$d/tests/scripts" "$d/.github/workflows"
  ln -s "$REPO/scripts" "$d/scripts"; ln -s "$REPO/tests/scripts/lib" "$d/tests/scripts/lib"; ln -s "$REPO/.github/actions" "$d/.github/actions"
  cp "$CWF" "$d/.github/workflows/bastion-host-create.yml"
  python3 -I "$PY" mutate "$SELF" "$d/tests/scripts/$(basename "$SELF")" "$scode" 2>/dev/null || { fail "suite mutation did not land exactly once: $label"; return; }
  if [[ -n "$wcode" ]]; then
    python3 -I "$PY" mutate "$RWF" "$d/.github/workflows/bastion-host-replace.yml" "$wcode" 2>/dev/null || { fail "workflow mutation did not land exactly once: $label"; return; }
  else
    cp "$RWF" "$d/.github/workflows/bastion-host-replace.yml"
  fi
  o="$(BHRW_META=1 timeout 900 "$BASH_BIN" "$d/tests/scripts/$(basename "$SELF")" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF -- "$want" <<<"$o"; then pass "suite mutant caught (${want}): $label"; else fail "suite mutant NOT caught: $label (rc=$rc, want a line naming '$want')"; fi
}
# once(a, b): replace the one occurrence of a with b; n counts occurrences.
O='def once(a, b):
    global s, n
    n = s.count(a); s = s.replace(a, b)
'
W1='once("        if: inputs.plan_only != true\n        id: apply\n", "        if: always() && inputs.plan_only != true\n        id: apply\n")'

# ── CONTROLS: every helper that owns a verdict must still be able to REJECT ─────────────────────
# Each is driven with a known input in a subshell (its counters and RS_* unwind with it) and must give
# the known verdict. Reported by printf + exit 1, never through pass()/fail() (ADR-193).
expect() { # <label> <first word wanted> <command...>
  local label="$1" want="$2" got; shift 2
  got="$("$@" 2>/dev/null | head -1 | cut -d' ' -f1)"
  [[ "$got" == "$want" ]] || die "CONTROL ${label}: want ${want}, got '${got}'"
}
counted() { ( passes=0; fails=0; cases=0; MUT_N=0; META_N=0; "$@" >/dev/null 2>&1; printf '%s/%s' "$passes" "$fails" ); }
ctl_v() { RS_OK="$1"; RS_RC=0; printf 'synthetic\n' > "$OUT"; v ctl "$2"; }
ctl_refused() { RS_OK=1; RS_RC="$1"; printf '%s\n' "$2" > "$OUT"; printf '%s' "$3" > "$GO"; refused ctl "$4"; }
ctl_rsok() { run_step "$@"; echo "RSOK=$RS_OK"; }
expect "v: a false condition is RED" RED ctl_v 1 1
expect "v: a harness-refused run is RED even on a true condition" RED ctl_v 0 0
expect "v: a true condition on a run is OK" OK ctl_v 1 0
expect "vv: a false condition is RED" RED vv ctl 1
expect "vv: a true condition is OK" OK vv ctl 0
expect "refused: a zero exit is RED" RED ctl_refused 0 "the named refusal" "" "the named refusal"
expect "refused: another message is RED (the message conjunct)" RED ctl_refused 1 "some other refusal" "" "the named refusal"
expect "refused: a written pre_ids is RED (the pre_ids conjunct)" RED ctl_refused 1 "the named refusal" "pre_ids=111" "the named refusal"
expect "refused: the named refusal is OK" OK ctl_refused 1 "the named refusal" "" "the named refusal"
STEPS="$WORK/ctl-steps"; python3 -I "$PY" extract "$RWF" bastion_host_replace "$STEPS" 2>/dev/null || die "the real workflow did not extract"
expect "run_step: an expression missing from the table refuses the run" RSOK=0 ctl_rsok tier_b "$WS" '@!steps.creds.outputs.source'
expect "run_step: a harness value for the step's own env: key refuses the run" RSOK=0 ctl_rsok tier_b "$WS" CRED_SOURCE=tier_b
expect "run_step: a step the parsed workflow lacks refuses the run" RSOK=0 ctl_rsok no_such_step "$WS"
expect "run_step: the table's own values run the step" RSOK=1 ctl_rsok tier_b "$WS"
cp "$RWF" "$WORK/control-replace.yml"; cp "$CWF" "$WORK/control-create.yml"
c="$(counted mut ctl replace S S4-one-plan "$O"'once("# Q-R6: a branch dispatch is a RED refusal", "# Q-R6: a branch dispatch is a red refusal")')"
[[ "$c" == 0/1 ]] || die "CONTROL mut: a behaviour-identical (comment-only) mutant must report SURVIVED (passes/fails=${c})"
c="$(counted mut ctl replace S S3-if-toctou "$O"'once("        id: plan\n", "        id: plan\n        continue-on-error: true\n")')"
[[ "$c" == 0/1 ]] || die "CONTROL mut: a mutant that turns only ANOTHER check red must report SURVIVED for the named one (passes/fails=${c})"
c="$(counted mut ctl replace S S4-one-plan "$O"'once("NO SUCH WORKFLOW TEXT", "x")')"
[[ "$c" == 0/1 ]] || die "CONTROL mut: a mutation that does not land must fail (passes/fails=${c})"
c="$(counted equiv ctl "not equivalent" Q Q-changed-off "$O"'once("read the id from its summary. Nothing applied.\"\n            exit 1", "read the id from its summary. Nothing applied.\"\n            true")')"
[[ "$c" == 0/1 ]] || die "CONTROL equiv: a mutant that turns its check RED is not equivalent and must fail (passes/fails=${c})"
if [[ -z "${BHRW_META:-}" ]]; then
  c="$(counted smut ctl "NO-SUCH-CONTROL-LINE" "$O"'once("pc=\"$(passes=0 fails=0 cases=0; pass x >/dev/null; fail y >/dev/null;", "pc=\"$(passes=0 fails=0 cases=0; pass x >/dev/null; pass y >/dev/null;")')"
  [[ "$c" == 0/1 ]] || die "CONTROL smut: a child that exits on another line than the named one must fail (passes/fails=${c})"
fi
echo "controls: v, vv, refused, run_step, mut, equiv and smut each reject a must-fail input"

# ── Control: the unmutated workflows, through the same machinery the mutants use ───────────────
echo "control (unmutated workflows)"
CONTROL="$(analyze "$WORK/control-replace.yml" "$WORK/control-create.yml")"
n_ok="$(grep -c '^OK ' <<<"$CONTROL")"; n_red="$(grep -c '^RED ' <<<"$CONTROL")"; n_all="$(grep -c . <<<"$CONTROL")"
[[ "$n_red" -eq 0 && "$n_ok" -eq "$n_all" && "$n_ok" -gt 0 ]] \
  || die "CONTROL the unmutated workflows are GREEN: ok=${n_ok} red=${n_red} lines=${n_all}; first RED: $(grep -m1 '^RED ' <<<"$CONTROL" | head -c 400)"
dups="$(sed -E 's/^(OK|RED) ([^ ]+).*/\2/' <<<"$CONTROL" | sort | uniq -d | tr '\n' ' ')"
[[ -z "$dups" ]] || die "CONTROL check ids printed more than once: ${dups}"
MIN_CHECKS=119  # measured 2026-11-28 (round 2): the literal number of control checks (never derived from the output)
[[ "$n_all" -eq "$MIN_CHECKS" ]] || die "CONTROL the control printed ${n_all} checks, want exactly ${MIN_CHECKS}"
echo "the unmutated control is GREEN (${n_ok} checks, each id once)"
echo "checks"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if [[ "$line" == "OK "* ]]; then pass "${line#OK }"; else fail "${line#RED }"; fi
done <<<"$CONTROL"

# ── Mutation rows (pin 7): each must turn its named check RED ─────────────────────────────────
echo "mutation rows"
mut "Guard 2 the live read's failure ignored" replace R R-read-failure-stops-before-the-plan "$O"'once("_bbv_servers_doc \"$PLAN_DIR/hetzner-servers.json\")\" || rc=$?", "_bbv_servers_doc \"$PLAN_DIR/hetzner-servers.json\")\" || true")'
mut "Guard 2 the gate grades a document other than the saved read" replace P P-pass-calls-gate-and-stock "$O"'once("\"$EXPECTED_ID\" \"$PLAN_DIR/hetzner-servers.json\"; then", "\"$EXPECTED_ID\" \"$PLAN_DIR/hetzner-servers-toctou.json\"; then")'
mut "Guard 2 F4 the -replace array set on both arms" replace P P-recovery-arm-plans-no-replace "$O"'once("if [[ \"$EXPECTED_ID\" != none ]]; then\n            replace_args=", "if true; then\n            replace_args=")'
mut "W5 the gate call no-op'd (if ! : bastion_host_replace_gate)" replace P P-gate-abort-stops "$O"'once("if ! bastion_host_replace_gate \"", "if ! : bastion_host_replace_gate \"")'
mut "W2 the gate ABORT exit 1 -> true" replace P P-gate-abort-stops "$O"'once("| head -30 >&2\n            exit 1", "| head -30 >&2\n            true")'
mut "W3 continue-on-error on the plan step" replace S S1-no-continue-on-error "$O"'once("        id: plan\n", "        id: plan\n        continue-on-error: true\n")'
mut "W1 the apply if: gains always()" replace S S3-if-apply "$O"'once("        if: inputs.plan_only != true\n        id: apply\n", "        if: always() && inputs.plan_only != true\n        id: apply\n")'
mut "W12 a terraform -chdir=. plan inserted before the apply" replace S S4-one-plan "$O"'once("          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply", "          terraform -chdir=. plan -no-color -input=false -out=\"$PLAN_DIR/tfplan\"\n          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply")'
mut "W12b the same re-plan, executed" replace A A-applies-only-the-gated-plan "$O"'once("          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply", "          terraform -chdir=. plan -no-color -input=false -out=\"$PLAN_DIR/tfplan\"\n          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply")'
mut "the apply's plan argument widened (\"\$PLAN_DIR/tfplan\"2)" replace S S4-apply-arg "$O"'once("terraform apply -no-color -input=false \"$PLAN_DIR/tfplan\"", "terraform apply -no-color -input=false \"$PLAN_DIR/tfplan\"2")'
mut "W4 the TOCTOU compare refusal exit 1 -> true" replace Q Q-changed-off "$O"'once("read the id from its summary. Nothing applied.\"\n            exit 1", "read the id from its summary. Nothing applied.\"\n            true")'
mut "W11 the TOCTOU compare if false" replace Q Q-changed-id "$O"'once("if [[ \"$same\" != true ]]; then", "if false; then")'
mut "the TOCTOU projection narrowed back (no private_net)" replace Q Q-changed-ip "$O"'once(", private_net: [(.private_net // [])[] | {network, ip}]}", "}")'
mut "the TOCTOU projection narrowed back (no name)" replace Q Q-changed-name "$O"'once("{id, name, role: .labels.role,", "{id, role: .labels.role,")'
mut "m8 the TOCTOU fresh read swapped for the plan-time doc" replace Q Q-changed-off "$O"'once("rc=0; why=\"$(_bbv_servers_doc \"$fresh\")\" || rc=$?\n          if [[ \"$rc\" -ne 0 ]]; then\n            echo \"::error::bastion-host-replace: TOCTOU", "rc=0; cp \"$PLAN_DIR/hetzner-servers.json\" \"$fresh\"\n          if [[ \"$rc\" -ne 0 ]]; then\n            echo \"::error::bastion-host-replace: TOCTOU")'
mut "m10 pre_ids read from the plan-time doc" replace S S6-pre-from-fresh "$O"'once("else join(\" \") end'"'"' \"$fresh\")\"", "else join(\" \") end'"'"' \"$PLAN_DIR/hetzner-servers.json\")\"")'
mut "Q-R3 the firewall binding check if false" replace Q Q-firewall-label "$O"'once("if [[ \"$fw_ok\" != true ]]; then", "if false; then")'
mut "Q-R3 the firewall binding refusal exit 1 -> true" replace Q Q-firewall-other "$O"'once("Re-run plan_only. Nothing applied.\"\n            exit 1", "Re-run plan_only. Nothing applied.\"\n            true")'
mut "Q-R3 a recovery-arm firewall may hold the pin" replace Q Q-firewall-bound-on-recovery "$O"'once("$s == [] or ($pin != \"none\" and $s == [$pin])", "$s == [] or $s == [$pin] or $pin == \"none\"")'
mut "Q-R3 the firewall read failure ignored" replace Q Q-firewall-read-failure "$O"'once("if [[ \"$code\" != 200 ]] || ! jq -e", "if false && ! jq -e")'
mut "m4 the stock preflight neutered (&& false)" replace P P-stock-refusal-stops "$O"'once("if ! stock_preflight_gate tfplan.json; then", "if ! stock_preflight_gate tfplan.json && false; then")'
mut "W6 verify binds steps.toctou.outputs.pre_id" replace S S5-outputs "$O"'once("          BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}\n          PRE_IDS: ${{ steps.toctou.outputs.pre_ids }}", "          BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}\n          PRE_IDS: ${{ steps.toctou.outputs.pre_id }}")'
mut "W7 the TOCTOU output renamed preids= (structure)" replace S S5-outputs "$O"'once("printf '"'"'pre_ids=%s\\n'"'"' \"$pre\"", "printf '"'"'preids=%s\\n'"'"' \"$pre\"")'
mut "W7 the TOCTOU output renamed preids= (behaviour)" replace Q Q-pass-writes-fresh-preids "$O"'once("printf '"'"'pre_ids=%s\\n'"'"' \"$pre\"", "printf '"'"'preids=%s\\n'"'"' \"$pre\"")'
mut "W8 verify if: drops the failed-apply arm" replace S S3-if-verify "$O"'once(" || steps.apply.outcome == '"'"'failure'"'"') && inputs.plan_only != true }}", ") && inputs.plan_only != true }}")'
mut "W9 the mask printf neutered" replace P P-private-keys-masked "$O"'once("then printf '"'"'::add-mask::%s\\n'"'"' \"$line\"; fi; done <<<\"$keys\"", "then printf '"'"'%.0s'"'"' \"$line\"; fi; done <<<\"$keys\"")'
mut "W10 the mask jq selects numbers" replace P P-private-keys-masked "$O"'once("| .value | strings'"'"' \"$PLAN_DIR/tfplan.json\"", "| .value | numbers'"'"' \"$PLAN_DIR/tfplan.json\"")'
mut "m3 the tier_b check if false" replace T T-legacy-refused "$O"'once("if [[ \"$CRED_SOURCE\" != \"tier_b\" ]]; then", "if false; then")'
mut "m7 the confirm check if false" replace V V-confirm-refused "$O"'once("if [[ \"$CONFIRM_RAW\" != \"REPLACE-bastion\" ]]; then", "if false; then")'
mut "the pin check if false" replace V V-pin-refused-abc "$O"'once("if ! (LC_ALL=C; [[ \"$EXPECTED_ID_RAW\" =~", "if false && ! (LC_ALL=C; [[ \"$EXPECTED_ID_RAW\" =~")'
mut "security: the confirm text echoed into ::error::" replace V V-confirm-never-echoed "$O"'once("(the value given is not echoed: dispatch text never reaches a workflow command)", "(got '"'"'${CONFIRM_RAW}'"'"')")'
mut "Q-R6 the Require main refusal neutered" replace M M-branch-refused "$O"'once("[[ \"$GITHUB_REF\" == refs/heads/main ]] || {", "true || {")'
mut "Q-R6 the job-level if: restored" replace S S1-no-job-if "$O"'once("  bastion_host_replace:\n    runs-on:", "  bastion_host_replace:\n    if: github.ref == '"'"'refs/heads/main'"'"'\n    runs-on:")'
mut "pin 2 the anchor and apply swapped" replace S S2-order "$O"'a = s.index("      - name: Stamp boot-trail run anchor (bastion replace)")
b = s.index("      - name: Terraform apply (bastion replace)")
c = s.index("      - name: Verify the bastion boot")
s = s[:a] + s[b:c] + s[a:b] + s[c:]
n = 1'
mut "Q-R7 replace cancel records failed for a refusal" replace C C-cancel-records-refused "$O"'once("echo \"result=${_BBV_POWEROFF:-failed}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=failed\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 replace cancel records a fixed success token" replace C C-cancel-records-absent "$O"'once("echo \"result=${_BBV_POWEROFF}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 a READY run still prints a dispatch line" replace D D-ready-needs-no-dispatch "$O"'once("elif [[ \"${APPLY_OUTCOME}/${VERIFY_OUTCOME}\" == success/success ]]; then", "elif false; then")'
mut "Q-R7 a run stopped before the plan still reads" replace D D-stopped-before-plan-reads-nothing-empty "$O"'once("if [[ \"${PLAN_OUTCOME:-skipped}\" == skipped ]]; then", "if [[ \"${PLAN_OUTCOME}\" == skipped ]]; then")'
mut "Q-R7 the replace summary loses its refused_no_preids cancel line" replace D D-summary-one-line-per-cancel-verdict "$O"'once("refused_no_preids) po=\"**power-off after a cancel REFUSED", "refused_no_preids_x) po=\"**power-off after a cancel REFUSED")'
mut "Q-R7 create cancel restores powered_off_or_absent" create X X-cancel-records-absent "$O"'once("echo \"result=${_BBV_POWEROFF}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off_or_absent\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 create cancel records failed for a refusal" create X X-cancel-records-refused "$O"'once("echo \"result=${_BBV_POWEROFF:-failed}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=failed\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 the create summary folds REFUSED into FAILED" create X X-summary-refused-is-not-failed "$O"'once("refused_no_preids) po=\"**power-off after a cancel REFUSED: the pre-apply id set was missing or malformed, so nothing was powered off.**", "refused_no_preids) po=\"**power-off after a cancel FAILED: the pre-apply id set was missing or malformed.**")'
mut "the retired token reappears in the create summary" create S S7-no-retired-cancel-token "$O"'once("            absent) po=\"Cancelled: no soleur-bastion server exists", "            powered_off_or_absent) po=\"x\" ;;\n            absent) po=\"Cancelled: no soleur-bastion server exists")'
mut "the create verify drops the pre-apply id set" create X X-verify-passes-four-args-and-its-rc "$O"'once(" bastion-host-create \"${PRE_IDS:-}\" || rc=$?", " bastion-host-create || rc=$?")'
# Pin 4, a CLOSED set (the round-1 fix review's survivors E35, E13, E13b, E12 and their kin).
mut "E35 a terraform destroy in the TOCTOU step (structure)" replace S S4-terraform-closed-set "$O"'once("          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n", "          terraform -chdir=apps/web-platform/infra destroy -auto-approve -target=hcloud_server.bastion\n          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n")'
mut "E35 the same destroy, executed (stub log)" replace L L-terraform-log-closed-set "$O"'once("          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n", "          terraform -chdir=apps/web-platform/infra destroy -auto-approve -target=hcloud_server.bastion\n          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n")'
mut "E13 a quoted \"terraform\" apply in the TOCTOU step (structure)" replace S S4-one-apply "$O"'once("          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n", "          \"terraform\" -chdir=apps/web-platform/infra apply -auto-approve -input=false\n          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n")'
mut "E13 the same quoted apply, executed (stub log)" replace L L-apply-only-in-apply "$O"'once("          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n", "          \"terraform\" -chdir=apps/web-platform/infra apply -auto-approve -input=false\n          fresh=\"$PLAN_DIR/hetzner-servers-toctou.json\"\n")'
mut "E13b tf=terraform; \$tf apply in boot_anchor (structure)" replace S S4-terraform-closed-set "$O"'once("          epoch=$(date -u +%s)\n", "          tf=terraform; $tf -chdir=apps/web-platform/infra apply -auto-approve\n          epoch=$(date -u +%s)\n")'
mut "E13b the same indirection, executed (stub log)" replace L L-apply-only-in-apply "$O"'once("          epoch=$(date -u +%s)\n", "          tf=terraform; $tf -chdir=apps/web-platform/infra apply -auto-approve\n          epoch=$(date -u +%s)\n")'
mut "E12 a quoted terraform plan in boot_anchor (structure)" replace S S4-one-plan "$O"'once("          epoch=$(date -u +%s)\n", "          \"terraform\" -chdir=apps/web-platform/infra plan -out=\"$PLAN_DIR/tfplan\"\n          epoch=$(date -u +%s)\n")'
mut "E12 the same re-plan, executed (stub log)" replace L L-plan-only-in-plan "$O"'once("          epoch=$(date -u +%s)\n", "          \"terraform\" -chdir=apps/web-platform/infra plan -out=\"$PLAN_DIR/tfplan\"\n          epoch=$(date -u +%s)\n")'
ENVTF='once("        id: boot_anchor\n", "        id: boot_anchor\n        env:\n          TF: terraform\n")
m = n
once("          epoch=$(date -u +%s)\n", "          \"$TF\" -chdir=. apply -auto-approve\n          epoch=$(date -u +%s)\n")
n = n * m'
mut "env indirection: TF: terraform in a step env:, \"\$TF\" apply (structure)" replace S S4-terraform-closed-set "$O$ENVTF"
mut "env indirection, executed (stub log)" replace L L-apply-only-in-apply "$O$ENVTF"
mut "a split word (terra\"\"form apply) only the stub log can see" replace L L-apply-only-in-apply "$O"'once("          epoch=$(date -u +%s)\n", "          terra\"\"form -chdir=. apply -auto-approve\n          epoch=$(date -u +%s)\n")'
mut "a -destroy flag on the plan" replace S S4-no-mutating-verb "$O"'once("terraform plan -no-color -input=false -out=", "terraform plan -destroy -no-color -input=false -out=")'
# Step env: bound from the parsed workflow (the round-1 survivors E1-E6): a literal in place of the expression.
mut "E2 CRED_SOURCE bound to the literal tier_b" replace T T-legacy-refused "$O"'once("CRED_SOURCE: ${{ steps.creds.outputs.source }}", "CRED_SOURCE: tier_b")'
mut "E1 CONFIRM_RAW bound to the literal REPLACE-bastion" replace V V-confirm-refused "$O"'once("CONFIRM_RAW: ${{ inputs.confirm }}", "CONFIRM_RAW: REPLACE-bastion")'
mut "E6 EXPECTED_ID_RAW bound to none" replace V V-pin-refused-abc "$O"'once("EXPECTED_ID_RAW: ${{ inputs.expected_bastion_server_id }}", "EXPECTED_ID_RAW: none")'
mut "E3 BOOT_TRAIL_SINCE bound to 1" replace B B-verify-passes-four-args-and-its-rc "$O"'once("BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}", "BOOT_TRAIL_SINCE: \"1\"")'
mut "E4 the anchor stamps epoch=1" replace L L-anchor-is-now "$O"'once("epoch=$(date -u +%s)", "epoch=1")'
mut "E5 the verify APPLY_OUTCOME bound to success" replace B B-verify-passes-four-args-and-its-rc "$O"'once("APPLY_OUTCOME: ${{ steps.apply.outcome }}\n          BOOT_TRAIL_SINCE", "APPLY_OUTCOME: success\n          BOOT_TRAIL_SINCE")'
mut "the plan EXPECTED_ID bound to the literal 111" replace P P-recovery-arm-plans-no-replace "$O"'once("EXPECTED_ID: ${{ inputs.expected_bastion_server_id }}\n        run: |\n          set +e", "EXPECTED_ID: \"111\"\n        run: |\n          set +e")'
mut "the TOCTOU EXPECTED_ID bound to the literal none" replace Q Q-pass-writes-fresh-preids "$O"'once("EXPECTED_ID: ${{ inputs.expected_bastion_server_id }}\n        run: |\n          set -euo pipefail\n          umask 077", "EXPECTED_ID: none\n        run: |\n          set -euo pipefail\n          umask 077")'
# Q-R8: the plan-file controls (E8, E9, E36, Y6, Y6b).
mut "E9 umask 022 in the read step" replace L L-umask-read "$O"'once("          set -euo pipefail\n          umask 077\n          PLAN_DIR=", "          set -euo pipefail\n          umask 022\n          PLAN_DIR=")'
mut "umask 022 in the plan step" replace L L-umask-plan "$O"'once("          set -uo pipefail\n          umask 077\n", "          set -uo pipefail\n          umask 022\n")'
mut "umask 022 in the plan step (structure)" replace S S8-umask-077 "$O"'once("          set -uo pipefail\n          umask 077\n", "          set -uo pipefail\n          umask 022\n")'
mut "E36 the plan JSON cat after the masks" replace L L-no-plan-secret-printed "$O"'once("          unset keys\n", "          unset keys\n          cat \"$PLAN_DIR/tfplan.json\"\n")'
mut "E36 the same cat (structure)" replace S S8-tfplan-closed-set "$O"'once("          unset keys\n", "          unset keys\n          cat \"$PLAN_DIR/tfplan.json\"\n")'
Y6='once("      - name: TOCTOU re-pin", "      - name: Show the plan\n        run: jq . \"$PLAN_DIR/tfplan.json\"\n\n      - name: TOCTOU re-pin")'
mut "Y6 an id-less jq . tfplan.json step" replace L L-no-plan-secret-printed "$O$Y6"
mut "Y6 the same step (the closed step list)" replace S S2-step-list "$O$Y6"
mut "Y6 the same step (the closed tfplan lines)" replace S S8-tfplan-closed-set "$O$Y6"
Y6B='once("      - name: TOCTOU re-pin", "      - uses: actions/upload-artifact@v4\n        with:\n          path: ${{ runner.temp }}\n\n      - name: TOCTOU re-pin")'
mut "Y6b an upload-artifact step" replace S S8-uses-closed "$O$Y6B"
mut "Y6b the same step's runner.temp path" replace S S8-no-runner-temp-expression "$O$Y6B"
mut "E8 the cleanup deletes another path" replace L L-cleanup-deletes-plan-dir "$O"'once("rm -rf -- \"${PLAN_DIR}\"", "rm -rf -- \"${PLAN_DIR}.x\"")'
mut "the cleanup deletes all of RUNNER_TEMP" replace L L-cleanup-exact "$O"'once("rm -rf -- \"${PLAN_DIR}\"", "rm -rf -- \"${RUNNER_TEMP:?}\"")'
# The round-1 P3s: summary red exits, the cancel source failure, the token mask, the fakes' selectors.
mut "E10 the summary's success/* red exit dropped" replace D D-red-success-unverified "$O"'once("read the runbook\"; exit 1 ;;", "read the runbook\" ;;")'
mut "E10b the unrecognised-pair red exit dropped" replace D D-red-unrecognised-pair "$O"'once("do not treat this run as verified\"; exit 1 ;;", "do not treat this run as verified\" ;;")'
mut "E11 the empty-outcome red exit dropped" replace D D-red-empty-outcome "$O"'once("Treat any soleur-bastion as UNVERIFIED.\"\n            exit 1", "Treat any soleur-bastion as UNVERIFIED.\"\n            true")'
mut "E32 the replace cancel's source failure records powered_off" replace C C-cancel-source-failure-records-failed "$O"'once("echo \"result=failed\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off\" >> \"$GITHUB_OUTPUT\"")'
mut "E32 the create cancel's source failure records powered_off" create X X-cancel-source-failure-records-failed "$O"'once("echo \"result=failed\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off\" >> \"$GITHUB_OUTPUT\"")'
mut "E22 the HCLOUD_TOKEN mask dropped" replace P P-hcloud-token-masked "$O"'once("[[ -n \"$HCLOUD_TOKEN\" ]] && printf '"'"'::add-mask::%s\\n'"'"' \"$HCLOUD_TOKEN\"", ":")'
mut "E33 the plan runs doppler on dev_terraform" replace P P-pass-calls-gate-and-stock "$O"'once("doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform plan", "doppler run --preserve-env -p soleur -c dev_terraform --name-transformer tf-var -- \\\n            terraform plan")'
mut "E34 terraform show -json with no plan operand (state)" replace P P-pass-calls-gate-and-stock "$O"'once("terraform show -json \"$PLAN_DIR/tfplan\" >", "terraform show -json >")'
mut "the replace summary loses its unknown cancel-verdict arm" replace D D-summary-unknown-cancel-verdict "$O"'once("            *) po=\"**power-off after a cancel: UNKNOWN verdict", "            synthetic_x) po=\"**power-off after a cancel: UNKNOWN verdict")'
mut "the create summary loses its unknown cancel-verdict arm" create X X-summary-unknown-cancel-verdict "$O"'once("            *) po=\"**power-off after a cancel: UNKNOWN verdict", "            synthetic_x) po=\"**power-off after a cancel: UNKNOWN verdict")'
mut "security 7a the pre-apply integer check dropped" replace Q Q-pre-ids-not-integer "$O"'once("if [[ \"$pre\" != none || ", "if false && [[ \"$pre\" != none || ")'
equiv "A6 the TOCTOU servers-read refusal exit 1 -> true" "_bbv_servers_doc removes the document on a failed read (rm -f), so the jq --slurpfile that follows fails under set -e: the step still exits non-zero after the TOCTOU re-read FAILED line" \
  Q Q-servers-read-failure "$O"'once("TOCTOU re-read FAILED ${why#*FAILED }. Nothing applied.\"\n            exit 1", "TOCTOU re-read FAILED ${why#*FAILED }. Nothing applied.\"\n            true")'
MIN_MUT=88  # the literal number of mut + equiv rows above
[[ "$MUT_N" -eq "$MIN_MUT" ]] || die "CONTROL ${MUT_N} mutation rows ran, want exactly ${MIN_MUT}"

# ── Suite-helper mutants (ADR-193): a mutated COPY of this suite must still go red ──────────────
MIN_META=0
if [[ -z "${BHRW_META:-}" ]]; then
  echo "suite-helper mutants"
  smut "H10 fail() counts passes, with the apply if: always() (W1)" "CONTROL positive control" \
    "$O"'once("fail() { cases=$((cases + 1)); fa" + "ils=$((fails + 1));", "fail() { cases=$((cases + 1)); passes=$((passes + 1));")' "$O$W1"
  smut "the apply if: always() (W1) against the real helpers" "CONTROL the unmutated workflows are GREEN" \
    "$O"'once("# Run: bash tests/scripts/test-bastion-host-replace-work" + "flow.sh", "# Run:  bash tests/scripts/test-bastion-host-replace-workflow.sh")' "$O$W1"
  MIN_META=2
fi
[[ "$META_N" -eq "$MIN_META" ]] || die "CONTROL ${META_N} suite-helper mutants ran, want exactly ${MIN_META}"

# ── Verdict (exact floors, printf + exit) ─────────────────────────────────────────────────────
echo
MIN_CASES=$((MIN_CHECKS + MIN_MUT + MIN_META))  # every literal above: the control checks, the mutation rows, the suite mutants
[[ "$cases" -eq "$MIN_CASES" ]] || die "CONTROL ${cases} assertions ran, want exactly ${MIN_CASES}"
[[ $((passes + fails)) -eq "$cases" ]] || die "CONTROL accounting: passes+fails=$((passes + fails)) != cases=${cases}"
printf '%s: %d passed, %d failed (%d assertions)\n' "$NAME" "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
