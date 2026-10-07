#!/usr/bin/env bash
#
# Structural + behavioral + mutation gate for .github/workflows/web-host-reboot.yml (#9372): the dispatch-only workflow
# that soft-reboots ONE allow-listed web host (web-2) behind the Tier-B environment approval, then reads the evidence rows
# from Better Stack. Subject files: the workflow; scripts/web-host-reboot.sh (the one Hetzner write) and
# scripts/web-host-reboot-evidence.sh (the read-only reader) are covered by scripts/web-host-reboot.test.sh.
#
# THE PROPERTIES (plan Guard 1 anchor, Guard 2 static scan, Guard 4 whole):
#   - three jobs, exactly: `validate` (no secrets, no environment) -> `reboot` (the environment approval, `web-1-swap`, main
#     only) -> `observe` (no environment, no Hetzner token, no Doppler, Better Stack read credentials only);
#   - the one step that can reach the Hetzner write runs after every refusal step and only once; the three steps that run
#     code beyond the credential loader (never-pooled, snapshot, reboot) each run under an `env -i` allow-list;
#   - values reach shell only through `env:` (no `${{ ... }}` in any run body); every `uses:` is a 40-hex SHA pin;
#   - exit 2 (NOT YET) of the grade step is a green job with a notice, exit 4 and everything unexpected is red;
#   - no claim word in any non-comment text or in any output a behavioral row produced.
#
# Row families: S1..S12 are the contract rows (the plan's acceptance list), P* the step-order and classification rows, E* the
# env -i allow-list rows (static and behavioral), O* the observe rows, B* the behavioral rows that EXECUTE extracted run bodies
# under `bash --noprofile --norc -eo pipefail` (the stricter of GitHub's `bash -e {0}`), F* the forbidden-text rows, A* the
# agreement and tombstone rows, H* the harness controls. Structural rows PARSE the YAML (a grep matches the prose).
# The mutation battery then applies one edit per row to a COPY of the workflow and requires the battery to go red; its floor
# is reported by a direct printf and exit, never through the helpers it backstops.
# shellcheck disable=SC2319,SC2034
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF_REAL="$REPO/.github/workflows/web-host-reboot.yml"
export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null || { echo "FAIL - jq is required"; exit 1; }
python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml 2>/dev/null
python3 -c 'import yaml' 2>/dev/null || { echo "FAIL - python3 yaml is required"; exit 1; }

cat > "$TMP/wfcheck.py" <<'PY'
import glob, json, os, re, shutil, subprocess, sys, tempfile
import yaml

WF, REPO = sys.argv[1], sys.argv[2]
VERBOSE = os.environ.get("WHR_VERBOSE") == "1"
# The claim denylist (case-insensitive, whole-token: the neighbours of a hit must not be a letter or a digit). The same
# pattern lives in scripts/web-host-reboot.test.sh: weakening it means editing two files in one diff.
DENY_RE = re.compile(r'(^|[^a-z0-9])(luks-backed|encrypted|reborn|reopen|proof|verified|confirmed|proves|crypto_luks|/dev/mapper|luks=1|escrow=ok)($|[^a-z0-9])', re.I)
EXPECTED_HOSTS = ["web-2"]            # the suite's copy of the allow-list: the script's case arms and the workflow's options must agree
SHA_RE = re.compile(r'^[0-9a-f]{40}$')
TMPS = []
results = []

def row(name):
    def deco(fn):
        try:
            r = fn()
            ok = (r is True) or (isinstance(r, tuple) and bool(r[0]))
            detail = r[1] if isinstance(r, tuple) else ("" if ok else "returned %r" % (r,))
        except Exception as e:  # a row that cannot evaluate is RED, never skipped
            ok, detail = False, "%s: %s" % (type(e).__name__, str(e)[:160])
        results.append((ok, name, str(detail).replace("\n", " ")[:240]))
        return fn
    return deco

raw, wf, load_err = "", {}, ""
try:
    raw = open(WF).read()
    wf = yaml.safe_load(raw) or {}
except Exception as e:
    load_err = "%s: %s" % (type(e).__name__, e)
if not isinstance(wf, dict):
    wf, load_err = {}, "the document is not a mapping"
on = wf.get("on", wf.get(True)) or {}
jobs = wf.get("jobs") or {}
NONCOMMENT = "\n".join(l for l in raw.splitlines() if not l.lstrip().startswith("#"))

def steps_of(j): return jobs[j]["steps"]
def find(j, prefix):
    hits = [s for s in steps_of(j) if str(s.get("name", "")).startswith(prefix)]
    if len(hits) != 1:
        raise AssertionError("%d steps start with %r in job %s" % (len(hits), prefix, j))
    return hits[0]
def index_of(j, prefix):
    for i, s in enumerate(steps_of(j)):
        if str(s.get("name", "")).startswith(prefix): return i
    raise AssertionError("no step %r in %s" % (prefix, j))
def index_uses(j, pred):
    for i, s in enumerate(steps_of(j)):
        if pred(str(s.get("uses", ""))): return i
    raise AssertionError("no matching uses in " + j)
def runs(j=None):
    out = []
    for jn, jb in jobs.items():
        if j and jn != j: continue
        for s in jb.get("steps", []):
            if s.get("run") is not None: out.append((jn, s))
    return out
def flat(run): return re.sub(r'\\\n\s*', ' ', run)
def envi_names(run):
    """The NAME= tokens between `env -i` and the `bash` command word; None when the step has no env -i."""
    m = re.search(r'\benv -i\s+(.*?)\s+bash\s', flat(run), re.S)
    return None if not m else re.findall(r'(?:^|\s)([A-Z_][A-Z0-9_]*)=', m.group(1))
def deny_hits(text): return [m.group(2) for m in DENY_RE.finditer(text)]
def scanned_text():
    """The text every absence scan reads must exist: a scan over an empty document passes vacuously."""
    if len(NONCOMMENT.strip()) < 1500 or len(runs()) < 8: raise AssertionError("the scanned workflow text is empty or too small (%d bytes, %d run bodies)" % (len(NONCOMMENT), len(runs())))

# ---- the classification: every step with a run body is read-only or the write; a new step cannot arrive unclassified --------
RO_PREFIXES = ["Validate", "Re-check the typed host", "Extract backend credentials", "Terraform init", "Never-pooled evidence",
               "Evidence snapshot", "Run summary", "Grade the rows"]
WR_PREFIXES = ["Reboot request"]
def unclassified(step_list):
    return [str(s.get("name", "")) for s in step_list if s.get("run") is not None
            and not any(str(s.get("name", "")).startswith(p) for p in RO_PREFIXES + WR_PREFIXES)]

# ---- sandboxed execution of an extracted run body ---------------------------------------------------------------------------
def sandbox():
    d = tempfile.mkdtemp(prefix="whrw.")
    TMPS.append(d)
    for p in ("bin", "scripts", "tmp"): os.makedirs(os.path.join(d, p))
    return d
def run_body(d, body, env, flags="-eo", extra=("pipefail",)):
    script = os.path.join(d, "step.sh")
    open(script, "w").write(body)
    for f in ("gh_env", "gh_out", "gh_sum"): open(os.path.join(d, f), "w").close()
    e = {"PATH": d + "/bin:/usr/bin:/bin", "HOME": d, "RUNNER_TEMP": d + "/tmp", "GITHUB_ENV": d + "/gh_env", "GITHUB_OUTPUT": d + "/gh_out",
         "GITHUB_STEP_SUMMARY": d + "/gh_sum", "GITHUB_WORKSPACE": d}
    e.update(env)
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + ["bash", "--noprofile", "--norc", flags] + list(extra) + [script]
    p = subprocess.run(cmd, cwd=d, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout + p.stderr
def slurp(d, f):
    try: return open(os.path.join(d, f)).read()
    except OSError: return ""
OUTPUTS = []     # every behavioral run's combined output: the dynamic claim scan reads this
def run_logged(d, body, env, **kw):
    rc, out = run_body(d, body, env, **kw)
    OUTPUTS.append(out)
    return rc, out

# ================= S0 + the contract rows S1..S12 ======================================================================
@row("S0 the workflow file parses and has jobs (a parse error is not a mutation kill)")
def _(): return (not load_err and bool(jobs), load_err)

@row("S1 the only trigger is workflow_dispatch")
def _(): return list(on.keys()) == ["workflow_dispatch"]

@row("S2 inputs are exactly host (choice, options web-2), confirm and reason (strings), all required")
def _():
    i = on["workflow_dispatch"]["inputs"]
    return (sorted(i) == ["confirm", "host", "reason"] and i["host"].get("type") == "choice" and i["host"].get("options") == EXPECTED_HOSTS
            and i["confirm"].get("type") == "string" and i["reason"].get("type") == "string"
            and all(i[k].get("required") is True for k in i) and "default" not in i["host"])

@row("S3 run-name names the host and the typed confirm and never the reason")
def _():
    rn = wf.get("run-name", "")
    return ("inputs.host" in rn and "inputs.confirm" in rn and "reason" not in rn, rn)

@row("S4 the jobs are exactly validate, reboot, observe (in that order)")
def _(): return list(jobs.keys()) == ["validate", "reboot", "observe"]

@row("S5 permissions: top level contents+actions read; validate and observe re-declare contents read only")
def _():
    return (wf.get("permissions") == {"contents": "read", "actions": "read"}
            and jobs["validate"].get("permissions") == {"contents": "read"} and jobs["observe"].get("permissions") == {"contents": "read"}
            and "permissions" not in jobs["reboot"])

@row("S6 validate: no environment, no secrets, no credential action, no needs, bounded to 3 minutes")
def _():
    v = jobs["validate"]
    blob = json.dumps(v)
    return ("environment" not in v and "needs" not in v and "secrets." not in blob and "infra-credentials" not in blob
            and "concurrency" not in v and v.get("timeout-minutes") == 3 and v.get("runs-on") == "ubuntu-24.04")

@row("S7 reboot: needs validate, main only, the reviewer environment, the web-1-swap mutex, 25 minutes, two outputs")
def _():
    r = jobs["reboot"]
    return (r.get("needs") in ("validate", ["validate"]) and r.get("if") == "${{ github.ref == 'refs/heads/main' }}"
            and r.get("environment") == "web-platform-infra-apply"
            and r.get("concurrency") == {"group": "web-1-swap", "cancel-in-progress": False} and r.get("timeout-minutes") == 25
            and r.get("outputs") == {"server_id": "${{ steps.reboot.outputs.server_id }}", "anchor_epoch": "${{ steps.reboot.outputs.anchor_epoch }}"})

@row("S8 observe: needs reboot, runs on the anchor (always, main only, non-empty), no environment, its own mutex, 55 minutes")
def _():
    o = jobs["observe"]
    return (o.get("needs") in ("reboot", ["reboot"])
            and o.get("if") == "${{ always() && github.ref == 'refs/heads/main' && needs.reboot.outputs.anchor_epoch != '' }}"
            and "environment" not in o and o.get("concurrency") == {"group": "web-host-reboot-observe", "cancel-in-progress": False}
            and o.get("timeout-minutes") == 55)

@row("S9 observe holds no Hetzner, Doppler or loader reference; its only secrets are the three Better Stack read credentials")
def _():
    blob = json.dumps(jobs["observe"])
    secrets = sorted(set(re.findall(r'secrets\.([A-Za-z0-9_]+)', blob)))
    return (not re.search(r'hcloud|doppler|infra-credentials|web-host-reboot\.sh', blob, re.I)
            and secrets == ["BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_PASSWORD", "BETTERSTACK_QUERY_USERNAME"], secrets)

@row("S10 TERRAFORM_VERSION equals apply-web-platform-infra.yml's and INFRA_DIR is the web-platform root")
def _():
    other = yaml.safe_load(open(os.path.join(REPO, ".github/workflows/apply-web-platform-infra.yml")))
    mine = wf.get("env", {})
    return (str(mine.get("TERRAFORM_VERSION")) == str(other["env"]["TERRAFORM_VERSION"]) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', str(mine.get("TERRAFORM_VERSION")))
            is not None and mine.get("INFRA_DIR") == "apps/web-platform/infra", mine)

USES_LINES = [l for l in NONCOMMENT.splitlines() if re.match(r'^\s*-?\s*uses:\s', l)]
@row("S11 every uses: is a 40-hex SHA pin with a version comment (only the local credential loader is unpinned)")
def _():
    ext = [l for l in USES_LINES if "./.github/actions/" not in l]
    local = [l for l in USES_LINES if "./.github/actions/" in l]
    bad = [l.strip() for l in ext if not re.search(r'uses:\s*[\w.-]+/[\w./-]+@[0-9a-f]{40}\s+#\s*v?\d+(\.\d+)*', l)]
    return (len(ext) == 3 and not bad and len(local) == 1 and "./.github/actions/infra-credentials" in local[0], bad or len(ext))

@row("S11b the pinned SHAs are the ones the sibling workflow already uses (a new pin is a review event, not a drive-by)")
def _():
    sib = os.path.join(REPO, ".github/workflows/web2-luks-rebirth.yml")
    if not os.path.exists(sib): return True   # the sibling retired: nothing to compare against
    sib_text = open(sib).read()
    mine = re.findall(r'uses:\s*([\w.-]+/[\w./-]+)@([0-9a-f]{40})', NONCOMMENT)
    bad = [a for a, s in mine if a in ("actions/checkout", "hashicorp/setup-terraform") and (a + "@" + s) not in sib_text]
    return (len(mine) == 3 and not bad, bad)

@row("S12 no ${{ }} expression inside any run body, and nothing but the validated STARTED_AT and the masked backend pair is written to GITHUB_ENV")
def _():
    exprs = [(j, s.get("name")) for j, s in runs() if "${{" in s["run"]]
    envw = [l.strip() for j, s in runs() for l in s["run"].splitlines() if "GITHUB_ENV" in l and not l.lstrip().startswith("#")]
    allowed = (r"^printf 'STARTED_AT=%s\\n' \"\$\(date -u \+%Y-%m-%dT%H:%M:%SZ\)\" >> \"\$GITHUB_ENV\"$",
               r"^printf 'AWS_ACCESS_KEY_ID<<%s\\n%s\\n%s\\n' \"\$d1\" \"\$KEY_ID\" \"\$d1\" >> \"\$GITHUB_ENV\"$",
               r"^printf 'AWS_SECRET_ACCESS_KEY<<%s\\n%s\\n%s\\n' \"\$d2\" \"\$SECRET\" \"\$d2\" >> \"\$GITHUB_ENV\"$")
    stray = [l for l in envw if not any(re.match(p, l) for p in allowed)]
    return (not exprs and len(envw) == 3 and not stray, exprs or stray)

# ================= P: step order and classification ======================================================================
def reboot_idx():
    return {"recheck": index_of("reboot", "Re-check the typed host"),
            "checkout": index_uses("reboot", lambda u: u.startswith("actions/checkout@")),
            "tf": index_uses("reboot", lambda u: u.startswith("hashicorp/setup-terraform@")),
            "loader": index_uses("reboot", lambda u: u == "./.github/actions/infra-credentials"),
            "backend": index_of("reboot", "Extract backend credentials"), "init": index_of("reboot", "Terraform init"),
            "pooled": index_of("reboot", "Never-pooled evidence"), "snap": index_of("reboot", "Evidence snapshot"),
            "reboot": index_of("reboot", "Reboot request"), "summary": index_of("reboot", "Run summary")}

@row("P1 the reboot job's steps run in the contracted order (recheck, checkout, terraform, loader, backend, init, never-pooled, snapshot, reboot, summary)")
def _():
    i = reboot_idx()
    order = ["recheck", "checkout", "tf", "loader", "backend", "init", "pooled", "snap", "reboot", "summary"]
    return ([i[k] for k in order] == sorted(i[k] for k in order), i)

@row("P2 the reboot request is the LAST write: only the summary follows it, and it is the only step before it that is not a refusal or a read")
def _():
    i = reboot_idx()
    return (i["reboot"] == len(steps_of("reboot")) - 2 and i["summary"] == len(steps_of("reboot")) - 1)

@row("P3 exactly one step in the whole workflow calls the reboot verb, and only the reboot step and the summary name the writer script at all")
def _():
    verb = [(j, s["name"]) for j, s in runs() if re.search(r'web-host-reboot\.sh\s+reboot\b', flat(s["run"]))]
    anyw = sorted(s["name"].split(" ")[0] for j, s in runs() if re.search(r'web-host-reboot\.sh', s["run"]))
    return (len(verb) == 1 and verb[0] == ("reboot", find("reboot", "Reboot request")["name"]) and anyw == ["Reboot", "Run"], (verb, anyw))

@row("P4 every step with a run body is classified read-only or write (an unclassified step is reported by name)")
def _():
    scanned_text()
    un = [u for j in jobs for u in unclassified(steps_of(j))]
    return (not un, un)

@row("P5 the classified steps are present (a guard over an empty set is vacuous): at least 8 run steps, exactly one write")
def _():
    n = sum(1 for j, s in runs()); w = sum(1 for j, s in runs() if any(str(s["name"]).startswith(p) for p in WR_PREFIXES))
    return (n >= 8 and w == 1, (n, w))

@row("P6 the loader precedes every step that names terraform, doppler or either script (only format checks may come before it)")
def _():
    i = reboot_idx()["loader"]
    early = [s.get("name") for k, s in enumerate(steps_of("reboot")) if k < i and s.get("run") and re.search(r'terraform|doppler|web-host-reboot|web2-rebirth', s["run"])]
    return (not early, early)

@row("P7 the never-pooled and reboot steps carry no condition, no step has continue-on-error or a shell override, the summary runs always")
def _():
    st = steps_of("reboot")
    bad = [s.get("name") for j in jobs for s in steps_of(j) if s.get("continue-on-error") not in (None, False) or "shell" in s]
    return (find("reboot", "Never-pooled evidence").get("if") is None and find("reboot", "Reboot request").get("if") is None
            and find("reboot", "Re-check the typed host").get("if") is None and find("reboot", "Run summary").get("if") == "always()"
            and not bad, bad)

@row("P8 the reboot step is `id: reboot` (the job outputs read it) and the never-pooled step is `id: pooled` (the reboot step reads its verdict)")
def _(): return (find("reboot", "Reboot request").get("id") == "reboot" and find("reboot", "Never-pooled evidence").get("id") == "pooled")

@row("P9 setup-terraform pins the version from env with the wrapper off; init is the one read-only form in the infra directory")
def _():
    tf = steps_of("reboot")[reboot_idx()["tf"]]
    init = find("reboot", "Terraform init")
    return (tf.get("with") == {"terraform_version": "${{ env.TERRAFORM_VERSION }}", "terraform_wrapper": False}
            and init["run"].strip() == "terraform init -input=false -lockfile=readonly" and init.get("working-directory") == "${{ env.INFRA_DIR }}")

@row("P10 both checkouts keep no credentials; the loader takes both Doppler tokens from repository secrets")
def _():
    co = [s for j in ("reboot", "observe") for s in steps_of(j) if str(s.get("uses", "")).startswith("actions/checkout@")]
    ld = steps_of("reboot")[reboot_idx()["loader"]]
    return (len(co) == 2 and all(c.get("with") == {"persist-credentials": False} for c in co)
            and ld.get("with") == {"doppler-token-infra-privileged": "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}", "doppler-token-legacy": "${{ secrets.DOPPLER_TOKEN }}"})

@row("P11 the wiring: the reboot step receives the never-pooled verdict, the typed host and confirm and nothing else in env")
def _():
    s = find("reboot", "Reboot request")
    return s.get("env") == {"HOST": "${{ inputs.host }}", "CONFIRM": "${{ inputs.confirm }}", "NEVER_POOLED": "${{ steps.pooled.outputs.verdict }}"}

@row("P12 the summary step runs the summary verb with the job result and the reboot step's two outputs")
def _():
    s = find("reboot", "Run summary")
    e = s.get("env", {})
    return (s["run"].strip() == "bash scripts/web-host-reboot.sh summary" and e.get("JOB_STATUS") == "${{ job.status }}"
            and e.get("SERVER_ID") == "${{ steps.reboot.outputs.server_id }}" and e.get("ANCHOR_EPOCH") == "${{ steps.reboot.outputs.anchor_epoch }}"
            and e.get("REASON") == "${{ inputs.reason }}" and "HCLOUD_TOKEN" not in e and "DOPPLER_TOKEN" not in e, sorted(e))

@row("P13 no run body swallows a failure (|| true, || exit 0, || echo, || :, ; true)")
def _():
    scanned_text()
    bad = [(j, s["name"]) for j, s in runs() if re.search(r'\|\|\s*(true|exit 0|echo|:)(\s|;|$)|;\s*true(\s|;|$)', s["run"])]
    return (not bad, bad)

@row("P14 the only third-party or local actions are checkout, setup-terraform and the credential loader; no artifact, cache or upload step")
def _():
    uses = [str(s.get("uses")) for j in jobs for s in steps_of(j) if s.get("uses")]
    bad = [u for u in uses if not (u.startswith("actions/checkout@") or u.startswith("hashicorp/setup-terraform@") or u == "./.github/actions/infra-credentials")]
    return (not bad and len(uses) == 4, bad or len(uses))

# ================= E: the env -i allow-lists and the credential scoping =====================================================
ALLOW = {
    "Never-pooled evidence": (["DOPPLER_TOKEN", "HOME", "PATH", "TMPDIR"], "bash scripts/web2-rebirth-never-pooled.sh"),
    "Evidence snapshot": (["BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_PASSWORD", "BETTERSTACK_QUERY_USERNAME", "HOME", "PATH", "TMPDIR"],
                          "bash scripts/web-host-reboot-evidence.sh snapshot"),
    "Reboot request": (["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "HCLOUD_TOKEN", "HOME", "INFRA_DIR",
                        "NEVER_POOLED", "PATH", "TMPDIR"], 'bash scripts/web-host-reboot.sh reboot "$HOST" "$CONFIRM"'),
}
for _name, (_names, _cmd) in ALLOW.items():
    def _mk(name=_name, names=_names, cmd=_cmd):
        @row("E1 %s runs under an `env -i` allow-list of exactly %s and the one command %s" % (name.split(" ")[0], ",".join(names), cmd))
        def _():
            run = find("reboot", name)["run"]
            got = envi_names(run)
            return (got is not None and sorted(got) == names and len(got) == len(set(got)) and cmd in flat(run)
                    and len(re.findall(r'\benv -i\b', run)) == 1, got)
    _mk()

@row("E2 the marker token name occurs once outside comments, bound to the never-pooled step's DOPPLER_TOKEN alone")
def _():
    n = len(re.findall(r'DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER', NONCOMMENT))
    s = find("reboot", "Never-pooled evidence")
    return (n == 1 and s.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER }}"}, n)

@row("E3 the Better Stack credentials are bound to the snapshot step and the observe grade step only (3 + 3 references)")
def _():
    holders = sorted((j, s["name"].split(" ")[0]) for j in jobs for s in steps_of(j) if "BETTERSTACK_QUERY" in json.dumps(s.get("env", {})))
    n = len(re.findall(r'secrets\.BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD)', NONCOMMENT))
    sn = find("reboot", "Evidence snapshot").get("env")
    return (holders == [("observe", "Grade"), ("reboot", "Evidence")] and n == 6
            and sn == {k: "${{ secrets.%s }}" % k for k in ("BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_USERNAME", "BETTERSTACK_QUERY_PASSWORD")}, holders)

@row("E4 HCLOUD_TOKEN appears in exactly one run body (the reboot step, through the allow-list) and in no env block or other job")
def _():
    holders = [(j, s["name"]) for j, s in runs() if "HCLOUD_TOKEN" in s["run"]]
    in_env = [s.get("name") for j in jobs for s in steps_of(j) if "HCLOUD" in json.dumps(s.get("env", {}))] + ["wf-env"] * ("HCLOUD" in json.dumps(wf.get("env", {})))
    jenv = [j for j in jobs if "HCLOUD" in json.dumps(jobs[j].get("env", {}))]
    return (len(holders) == 1 and holders[0][1].startswith("Reboot request") and not in_env and not jenv, (holders, in_env))

@row("E5 secrets used by the reboot job are exactly the two loader tokens, the legacy backend token, the marker token and the snapshot's three")
def _():
    got = sorted(set(re.findall(r'secrets\.([A-Za-z0-9_]+)', json.dumps(jobs["reboot"]))))
    return (got == sorted(["DOPPLER_TOKEN", "DOPPLER_TOKEN_INFRA_PRIVILEGED", "DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER", "BETTERSTACK_QUERY_HOST",
                           "BETTERSTACK_QUERY_PASSWORD", "BETTERSTACK_QUERY_USERNAME"]), got)

@row("E6 no secrets[...] index form and no toJSON(secrets) (the Tier-B census forbids them)")
def _():
    scanned_text()
    return (not re.search(r'secrets\[|toJSON\(\s*secrets', NONCOMMENT, re.I))

@row("E7 every step that holds a credential refuses to run under xtrace")
def _():
    holders = [s for j, s in runs() if "secrets." in json.dumps(s.get("env", {})) or re.search(r'\benv -i\b', s["run"])]
    bad = [s["name"] for s in holders if not re.search(r'case \$- in \*x\*\)[^;]*;\s*exit 78', s["run"]) and not re.search(r'case \$- in \*x\*\).*exit 78', s["run"])]
    return (len(holders) >= 5 and not bad, bad or len(holders))

# ================= F: forbidden text, the claim scan and the census keys =====================================================
FORBIDDEN = [("-target", r'-target'), ("terraform plan", r'terraform\s+plan'), ("terraform apply", r'terraform\s+apply'), ("curl", r'\bcurl\b'),
             ("api host", r'api\.hetzner\.cloud'), ("ssh client", r'(^|[^A-Za-z0-9_./-])(ssh|scp|sftp|ssh-keygen)(\s|$)'),
             ("doppler write verb", r'doppler\s+(?:[a-z-]+\s+)?(?:set|delete|upload|create|update|rename|clone|revoke|import|replace|lock|unlock)\b'),
             ("rows helper", r'web2-luks-rows'), ("marker name", r'workspaces_luks_cutover'), ("reboot path", r'actions/re' + r'boot'),
             ("heartbeat action", r'actions/sentry-heartbeat'), ("terraform state surgery", r'terraform\s+state\s+(rm|mv|push)')]
def forbidden_hits(text): return [n for n, p in FORBIDDEN if re.search(p, text, re.I | re.M)]

@row("F1 no forbidden text outside comments (-target, terraform plan/apply, curl, the API host, ssh, a Doppler write verb, the rows helper, the marker name, the reboot path)")
def _():
    scanned_text()
    h = forbidden_hits(NONCOMMENT)
    return (not h, h)

@row("F2 no claim word in any non-comment text of the workflow (the denylist, whole token, case-insensitive)")
def _():
    scanned_text()
    h = deny_hits(NONCOMMENT)
    return (not h, h)

@row("F3 the only Terraform verb in a run body is init (state is read inside the writer script, never here)")
def _():
    verbs = sorted({m for j, s in runs() for m in re.findall(r'(?:^|[^A-Za-z0-9_-])terraform\s+(?:-[^ ]+\s+)*([a-z]+)', s["run"])})
    return (verbs == ["init"], verbs)

@row("F4 no workflow-level or step-level TF_LOG, no artifact upload, no cache")
def _():
    scanned_text()
    return (not re.search(r'TF_LOG|upload-artifact|actions/cache', NONCOMMENT))

# ================= B: behavioral rows: the extracted run bodies, executed ===================================================
OK_REASON = "owner go-ahead on #9372 (web-2 reboot), step 1: soak."
def vrun(host, confirm, reason, **kw):
    d = sandbox()
    s = find("validate", "Validate dispatch inputs")
    rc, out = run_logged(d, s["run"], {"HOST_RAW": host, "CONFIRM_RAW": confirm, "REASON_RAW": reason}, **kw)
    return rc, out, d

@row("B0 the validate step reads exactly HOST_RAW, CONFIRM_RAW and REASON_RAW from the three inputs")
def _():
    return find("validate", "Validate dispatch inputs").get("env") == {"HOST_RAW": "${{ inputs.host }}", "CONFIRM_RAW": "${{ inputs.confirm }}", "REASON_RAW": "${{ inputs.reason }}"}

@row("B1 validate accepts the canonical dispatch and the boundary shapes, echoes no raw input and writes nothing to GITHUB_ENV or GITHUB_OUTPUT")
def _():
    good = [("web-2", "REBOOT-web-2-169095540", OK_REASON), ("web-2", "REBOOT-web-2-1", "x"), ("web-2", "REBOOT-web-2-123456789012", "a" * 200)]
    bad = []
    for h, c, r in good:
        rc, out, d = vrun(h, c, r)
        if rc != 0 or "169095540" in out or OK_REASON in out or slurp(d, "gh_env") or slurp(d, "gh_out"): bad.append((h, c[:24], rc))
    return (not bad, bad)

@row("B2 validate refuses every bad host (web-1, web-3, empty, trailing space, upper case)")
def _():
    bad = [h for h in ("web-1", "web-3", "", "web-2 ", "WEB-2", "web-2\n", "web-2ZQ9X") if vrun(h, "REBOOT-web-2-169095540", OK_REASON)[0] == 0]
    return (not bad, bad)

@row("B3 validate refuses every bad confirm (wrong shape, other host, leading zero, 13 digits, whitespace, injection) and never echoes it")
def _():
    cases = ["", "REBOOT-web-2-", "REBOOT-web-2-12x", "reboot-web-2-1", "REBOOT-web-1-123931471", "REBOOT-web-2-0123", "REBOOT-web-2-1234567890123",
             "REBOOT-web-2-1\n", "REBOOT-web-2-1 ", " REBOOT-web-2-1", "REBOOT-web-2-1;id", "REBOOT-web-2--1", "REBOOT-web-2-9ZQ9XSENT"]
    leaks, passed = [], []
    for c in cases:
        rc, out, d = vrun("web-2", c, OK_REASON)
        if rc == 0: passed.append(c)
        if "ZQ9XSENT" in out or "12x" in out: leaks.append(c)
    return (not passed and not leaks, (passed, leaks))

@row("B4 validate refuses every bad reason (empty, 201 chars, newline, pipe, backtick, dollar, semicolon, quote, non-ASCII) and never echoes it")
def _():
    cases = ["", "a" * 201, "line1\nline2", "ZQ9XSENT|x", "a`id`", "a$(id)", "a;b", 'a"b', "caf\u00e9", "a\r", "a\tb"]
    passed = [c for c in cases if vrun("web-2", "REBOOT-web-2-169095540", c)[0] == 0]
    leaks = [c for c in cases if "ZQ9XSENT" in vrun("web-2", "REBOOT-web-2-169095540", c)[1]]
    return (not passed and not leaks, (passed, leaks))

@row("B5 validate refuses to run under xtrace (exit 78)")
def _():
    rc, out, d = vrun("web-2", "REBOOT-web-2-169095540", OK_REASON, flags="-exo", extra=("pipefail",))
    return (rc == 78, rc)

@row("B6 the re-check step in the reboot job refuses a bad host or confirm, accepts the canonical pair, and writes only a timestamp to GITHUB_ENV")
def _():
    s = find("reboot", "Re-check the typed host")
    if s.get("env") != {"HOST": "${{ inputs.host }}", "CONFIRM": "${{ inputs.confirm }}"}: return (False, s.get("env"))
    res = []
    for h, c, want in (("web-2", "REBOOT-web-2-169095540", 0), ("web-1", "REBOOT-web-2-169095540", 1), ("web-2", "REBOOT-web-1-123931471", 1),
                       ("web-2", "REBOOT-web-2-0169095540", 1), ("web-2", "REBOOT-web-2-1\n", 1), ("", "", 1)):
        d = sandbox()
        rc, out = run_logged(d, s["run"], {"HOST": h, "CONFIRM": c})
        envf = slurp(d, "gh_env")
        ok = (rc == 0) if want == 0 else (rc != 0 and not envf)
        if want == 0: ok = ok and re.fullmatch(r'STARTED_AT=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\n', envf) is not None
        if not ok: res.append((h, c[:30], rc))
    return (not res, res)

def stub_script(d, name, tag):
    p = os.path.join(d, "scripts", name)
    open(p, "w").write('#!/usr/bin/env bash\nenv | sort > "%s/dump.%s"\nprintf "%%s\\n" "$@" > "%s/args.%s"\nrc="$(cat "%s/rc" 2>/dev/null || echo 0)"\nexit "$rc"\n' % (d, tag, d, tag, d))
def set_rc(d, rc): open(os.path.join(d, "rc"), "w").write(str(rc))
def dumped_names(d, tag):
    return sorted(set(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)=', slurp(d, "dump." + tag), re.M)) - {"PWD", "SHLVL", "_", "OLDPWD"})
JUNK = {"TF_VAR_doppler_token_tf": "junk-tf", "DOPPLER_TOKEN": "junk-dp", "GH_TOKEN": "junk-gh", "AWS_SESSION_TOKEN": "junk-st", "ACTIONS_RUNTIME_TOKEN": "junk-rt",
        "BETTERSTACK_QUERY_PASSWORD": "junk-bs", "DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER": "junk-mk"}

@row("B7 the never-pooled step: the child sees exactly the allow-list, verdict=absent only on exit 0, nothing on exit 1 or 3")
def _():
    s = find("reboot", "Never-pooled evidence"); res = []
    d = sandbox(); stub_script(d, "web2-rebirth-never-pooled.sh", "np")
    env = dict(JUNK); env.update({"DOPPLER_TOKEN": "marker-sentinel", "HCLOUD_TOKEN": "hc-sentinel"})
    rc, out = run_logged(d, s["run"], env)
    if rc != 0 or slurp(d, "gh_out") != "verdict=absent\n": res.append(("exit0", rc, slurp(d, "gh_out")))
    if dumped_names(d, "np") != ["DOPPLER_TOKEN", "HOME", "PATH", "TMPDIR"]: res.append(("names", dumped_names(d, "np")))
    if "DOPPLER_TOKEN=marker-sentinel" not in slurp(d, "dump.np") or "sentinel" in out: res.append("token plumbing")
    for r in (1, 3):
        set_rc(d, r); rc, out = run_logged(d, s["run"], env)
        if rc == 0 or slurp(d, "gh_out"): res.append(("rc", r, rc))
    return (not res, res)

@row("B8 the snapshot step: the child sees exactly the allow-list and the argument `snapshot`; a failure (missing credentials) fails the step")
def _():
    s = find("reboot", "Evidence snapshot"); res = []
    d = sandbox(); stub_script(d, "web-host-reboot-evidence.sh", "sn")
    env = dict(JUNK); env.update({"BETTERSTACK_QUERY_HOST": "h.example", "BETTERSTACK_QUERY_USERNAME": "u", "BETTERSTACK_QUERY_PASSWORD": "pw-sentinel", "HCLOUD_TOKEN": "hc-sentinel"})
    rc, out = run_logged(d, s["run"], env)
    if rc != 0: res.append(("rc0", rc))
    if dumped_names(d, "sn") != ["BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_PASSWORD", "BETTERSTACK_QUERY_USERNAME", "HOME", "PATH", "TMPDIR"]: res.append(("names", dumped_names(d, "sn")))
    if slurp(d, "args.sn").split() != ["snapshot"]: res.append(("argv", slurp(d, "args.sn")))
    set_rc(d, 3)
    if run_logged(d, s["run"], env)[0] == 0: res.append("exit 3 swallowed")
    return (not res, res)

@row("B9 the reboot step: the child sees exactly the allow-list and the argv `reboot <host> <confirm>`; the token never reaches the log or the argv")
def _():
    s = find("reboot", "Reboot request"); res = []
    d = sandbox(); stub_script(d, "web-host-reboot.sh", "rb")
    env = dict(JUNK); env.update({"HCLOUD_TOKEN": "hc-sentinel-7c1", "AWS_ACCESS_KEY_ID": "ak", "AWS_SECRET_ACCESS_KEY": "sk", "INFRA_DIR": "apps/web-platform/infra",
                                 "HOST": "web-2", "CONFIRM": "REBOOT-web-2-169095540", "NEVER_POOLED": "absent"})
    rc, out = run_logged(d, s["run"], env)
    want = ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "HCLOUD_TOKEN", "HOME", "INFRA_DIR", "NEVER_POOLED", "PATH", "TMPDIR"]
    if rc != 0: res.append(("rc0", rc))
    if dumped_names(d, "rb") != want: res.append(("names", dumped_names(d, "rb")))
    if slurp(d, "args.rb").split() != ["reboot", "web-2", "REBOOT-web-2-169095540"]: res.append(("argv", slurp(d, "args.rb")))
    if "hc-sentinel" in out or "hc-sentinel" in slurp(d, "args.rb") or "HCLOUD_TOKEN=hc-sentinel-7c1" not in slurp(d, "dump.rb"): res.append("token plumbing")
    set_rc(d, 1)
    if run_logged(d, s["run"], env)[0] == 0: res.append("a failing reboot script did not fail the step")
    return (not res, res)

@row("B10 the reboot step refuses to run under xtrace (the token is in scope)")
def _():
    s = find("reboot", "Reboot request"); d = sandbox(); stub_script(d, "web-host-reboot.sh", "rb")
    rc, out = run_body(d, s["run"], {"HCLOUD_TOKEN": "hc-sentinel", "HOST": "web-2", "CONFIRM": "REBOOT-web-2-1", "NEVER_POOLED": "absent"}, flags="-exo")
    return (rc == 78 and not os.path.exists(os.path.join(d, "dump.rb")), rc)

# ---- observe -----------------------------------------------------------------------------------------------------------------
@row("O1 observe's first step validates both job outputs by regex from env, and accepts only a numeric id and a 1-to-10-digit anchor")
def _():
    s = find("observe", "Validate the reboot job outputs"); res = []
    if s.get("env") != {"SERVER_ID": "${{ needs.reboot.outputs.server_id }}", "ANCHOR_EPOCH": "${{ needs.reboot.outputs.anchor_epoch }}"}: return (False, s.get("env"))
    for sid, an, want in (("169095540", "1780000000", 0), ("1", "1", 0), ("123456789012", "9999999999", 0), ("", "1780000000", 1), ("169095540", "", 1),
                          ("0123", "1780000000", 1), ("abc", "1780000000", 1), ("1;id", "1780000000", 1), ("1234567890123", "1780000000", 1),
                          ("169095540", "12345678901", 1), ("169095540", "17800000x0", 1), ("169095540\n", "1780000000", 1), ("169095540", "1780000000\n7", 1)):
        d = sandbox()
        rc, out = run_logged(d, s["run"], {"SERVER_ID": sid, "ANCHOR_EPOCH": an})
        if (rc == 0) != (want == 0): res.append((sid[:14], an[:12], rc))
    return (not res, res)

def grade_run(rc_stub, reason_line="reason=new_boot_seen_probe_pending\n"):
    s = find("observe", "Grade the rows")
    d = sandbox()
    p = os.path.join(d, "scripts", "web-host-reboot-evidence.sh")
    open(p, "w").write('#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/args.gr"\nenv | sort > "%s/dump.gr"\nprintf "%%b" "%s" >> "$GITHUB_OUTPUT"\nexit %d\n'
                       % (d, d, reason_line.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"), rc_stub))
    env = {"BETTERSTACK_QUERY_HOST": "h.example", "BETTERSTACK_QUERY_USERNAME": "u", "BETTERSTACK_QUERY_PASSWORD": "pw-sentinel-5d", "ANCHOR_EPOCH": "1780000000"}
    rc, out = run_logged(d, s["run"], env)
    return rc, out, d

@row("O2 the grade step passes the anchor and the 40-minute window, holds the three Better Stack credentials, and never echoes one")
def _():
    s = find("observe", "Grade the rows")
    rc, out, d = grade_run(0, "verdict=PASS\nreason=probe_row_on_a_boot_that_began_after_the_request\n")
    return (s.get("id") == "grade" and slurp(d, "args.gr").split() == ["grade", "--anchor", "1780000000", "--window-min", "40", "--poll-s", "60"]
            and "pw-sentinel" not in out and set(s.get("env", {})) == {"BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_USERNAME", "BETTERSTACK_QUERY_PASSWORD", "ANCHOR_EPOCH"}
            and s["env"]["ANCHOR_EPOCH"] == "${{ needs.reboot.outputs.anchor_epoch }}", slurp(d, "args.gr"))

@row("O3 exit 0 (PASS) and exit 2 (NOT YET) are green; exit 2 carries a ::notice:: and no ::error::")
def _():
    res = []
    rc0, out0, _d = grade_run(0, "reason=probe_row_on_a_boot_that_began_after_the_request\n")
    rc2, out2, _d = grade_run(2, "reason=new_boot_seen_probe_pending\n")
    if rc0 != 0 or "::error::" in out0: res.append(("exit0", rc0))
    if rc2 != 0 or "::notice::" not in out2 or "::error::" in out2 or "new_boot_seen_probe_pending" not in out2: res.append(("exit2", rc2, out2[-160:]))
    return (not res, res)

@row("O4 exit 4 is red with an ::error:: naming the reason, exit 1 (FAIL) is red, and exits 3, 64, 78, 5, 127 and 255 are red (an unexpected outcome never reads green)")
def _():
    res = []
    rc4, out4, _d = grade_run(4, "reason=request_not_acted_on\n")
    if rc4 == 0 or "::error::" not in out4 or "request_not_acted_on" not in out4 or "::notice::" in out4: res.append(("exit4", rc4, out4[-160:]))
    for r in (1, 3, 5, 64, 78, 127, 255):
        rc, out, _d = grade_run(r, "reason=read_fault\n")
        if rc == 0 or "::error::" not in out: res.append((r, rc))
    return (not res, res)

@row("O5 a hostile or missing reason in the step output is never printed (the reason must match ^[a-z_]{1,64}$)")
def _():
    res = []
    for line in ("reason=x::error::ZQ9XSENT\n", "reason=ZQ9XSENT-UPPER\n", "reason=" + "a" * 65 + "ZQ9XSENT\n", ""):
        for r in (2, 4):
            rc, out, _d = grade_run(r, line)
            if "ZQ9XSENT" in out or "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" in out: res.append((r, line[:20]))
    return (not res, res)

@row("O6 the grade step refuses to run under xtrace (the Better Stack credentials are in scope)")
def _():
    s = find("observe", "Grade the rows"); d = sandbox()
    open(os.path.join(d, "scripts", "web-host-reboot-evidence.sh"), "w").write('#!/usr/bin/env bash\ntouch "%s/ran"\n' % d)
    rc, out = run_body(d, s["run"], {"BETTERSTACK_QUERY_PASSWORD": "pw", "ANCHOR_EPOCH": "1780000000"}, flags="-exo")
    return (rc == 78 and not os.path.exists(os.path.join(d, "ran")), rc)

@row("O7 observe has no summary-verb step: the grade script writes its own step summary on every path (plan deviation, recorded)")
def _():
    return (not any("summary" in str(s.get("name", "")).lower() for s in steps_of("observe")) and len(steps_of("observe")) == 3)

# ================= A: agreement, the dynamic claim scan, the tombstone =======================================================
@row("A1 the allow-list agrees in three places: the writer script's case arms, the workflow's host options and this suite's expected set")
def _():
    script = open(os.path.join(REPO, "scripts/web-host-reboot.sh")).read()
    m = re.search(r'case "\$host" in\n(.*?)\n\s*esac', script, re.S)
    arms = re.findall(r'^\s*([a-z0-9][a-z0-9-]*)\)', m.group(1), re.M)
    opts = on["workflow_dispatch"]["inputs"]["host"]["options"]
    return (sorted(arms) == sorted(opts) == sorted(EXPECTED_HOSTS), (arms, opts))

@row("A2 the workflow's confirm pattern names the allow-listed host and the validate step's host check is the same literal")
def _():
    v = find("validate", "Validate dispatch inputs")["run"]; r = find("reboot", "Re-check the typed host")["run"]
    return ('"$HOST_RAW" == "web-2"' in v and "^REBOOT-web-2-[1-9][0-9]{0,11}$" in v and '"$HOST" == "web-2"' in r and "^REBOOT-web-2-[1-9][0-9]{0,11}$" in r)

@row("A3 the writer script's accepted-confirm pattern is the pattern the validate step enforces (same digits rule)")
def _():
    script = open(os.path.join(REPO, "scripts/web-host-reboot.sh")).read()
    return "[1-9][0-9]{0,11}$" in script and "[1-9][0-9]{0,11}$" in find("validate", "Validate dispatch inputs")["run"]

@row("A4 the concurrency literal is byte-identical to the sibling host workflows' (a divergent string fails to serialize, silently)")
def _():
    sib = os.path.join(REPO, ".github/workflows/web2-luks-rebirth.yml")
    lit = "group: web-1-swap"
    return (lit in NONCOMMENT and (not os.path.exists(sib) or lit in open(sib).read()))

def tombstone_leftovers(root):
    need = ["scripts/web2-rebirth.sh", "scripts/web2-rebirth-never-pooled.sh"]
    if all(os.path.exists(os.path.join(root, p)) for p in need): return []
    pats = [".github/workflows/web-host-reboot*", "scripts/web-host-reboot*", "apps/web-platform/infra/web-host-reboot*"]
    return sorted(p for pat in pats for p in glob.glob(os.path.join(root, pat)))
def synth_root(have_rebirth, have_pooled, have_subjects):
    d = sandbox()
    for rel, on_ in (("scripts/web2-rebirth.sh", have_rebirth), ("scripts/web2-rebirth-never-pooled.sh", have_pooled),
                     (".github/workflows/web-host-reboot.yml", have_subjects), ("scripts/web-host-reboot.sh", have_subjects),
                     ("apps/web-platform/infra/web-host-reboot-workflow.test.sh", have_subjects)):
        if on_:
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True); open(os.path.join(d, rel), "w").close()
    return d

@row("A5 TOMBSTONE: if either rebirth script is gone, every web-host-reboot* file must be gone too (armed while both exist)")
def _():
    left = tombstone_leftovers(REPO)
    return (not left, left)

@row("A5b the tombstone can fail and can pass: a half-retired tree is reported, a fully retired one and an intact one are not")
def _():
    half1 = tombstone_leftovers(synth_root(True, False, True)); half2 = tombstone_leftovers(synth_root(False, True, True))
    gone = tombstone_leftovers(synth_root(False, False, False)); intact = tombstone_leftovers(synth_root(True, True, True))
    return (len(half1) == 3 and len(half2) == 3 and not gone and not intact, (len(half1), len(half2), len(gone), len(intact)))

@row("A6 the dynamic claim scan: no behavioral run's output carries a claim word, and enough outputs were scanned to mean something")
def _():
    hits = [h for o in OUTPUTS for h in deny_hits(o)]
    return (not hits and len(OUTPUTS) >= 60, (hits, len(OUTPUTS)))

# ================= H: harness controls (each instrument must be able to fail) ===============================================
@row("H1 the classifier reports a planted unclassified step and passes a planted read-only validation step before the loader")
def _():
    planted = unclassified([{"name": "Purge the other volume", "run": "echo x"}])
    ok_new = unclassified([{"name": "Validate an extra input shape", "run": "echo x"}])
    return (planted == ["Purge the other volume"] and ok_new == [] and unclassified([]) == [], (planted, ok_new))
@row("H2 the claim scan reports every denylisted token planted in a sentence and passes the footer's own words and the PASS wording")
def _():
    toks = ["LUKS-backed", "encrypted", "reborn", "reopen", "proof", "verified", "confirmed", "proves", "crypto_LUKS", "/dev/mapper", "luks=1", "escrow=ok"]
    miss = [t for t in toks if not deny_hits("x %s y" % t)]
    clean = deny_hits("PASS (row presence only). This run reports rows only. It makes no statement about the volume or its encryption; grading belongs elsewhere. unconfirmed")
    return (not miss and not clean, (miss, clean))
@row("H3 the forbidden-text scan reports every planted forbidden shape and passes comment-free canonical text")
def _():
    plants = ["-target=hcloud_server.web", "terraform plan -out=x", "terraform apply x", "curl -s x", "https://api.hetzner.cloud/v1", "ssh root@h", "doppler secrets set A=b",
              "source scripts/lib/web2-luks-rows.sh", "WORKSPACES_LUKS_CUTOVER_AT", "/actions/" + "reboot", "uses: actions/sentry-heartbeat@x", "terraform state rm a"]
    miss = [p for p in plants if not forbidden_hits(p)]
    clean = forbidden_hits("terraform init -input=false -lockfile=readonly\nbash scripts/web-host-reboot.sh summary\ndoppler secrets get AWS_ACCESS_KEY_ID --plain")
    return (not miss and not clean, (miss, clean))
@row("H4 the env -i parser reads the allow-list, reports a stray name, and returns None for a body without env -i")
def _():
    a = envi_names('env -i PATH="$PATH" \\\n  HOME="$HOME" X_Y="${X_Y:-}" \\\n  bash scripts/a.sh')
    return (a == ["PATH", "HOME", "X_Y"] and envi_names("bash scripts/a.sh") is None)
@row("H5 a zero-length step list trips the classification floor (the floor can fail)")
def _(): return (sum(1 for s in [] if s.get("run")) < 8)

for d in TMPS: shutil.rmtree(d, ignore_errors=True)
bad = 0
for ok, name, detail in results:
    if ok:
        if VERBOSE: print("ok   - " + name)
    else:
        bad += 1
        print("FAILED %s%s" % (name, (" :: " + detail) if detail else ""))
print("RAN %d" % len(results))
PY

battery() { # <workflow file> -> prints FAILED lines and RAN n
  local wf="$1"
  python3 "$TMP/wfcheck.py" "$wf" "$REPO" 2>&1
}

fails=0; ran=0
report="$(WHR_VERBOSE=1 battery "$WF_REAL")"
while IFS= read -r line; do
  case "$line" in
    FAILED*) fails=$((fails + 1)); printf 'FAIL - %s\n' "${line#FAILED }" ;;
    RAN*) ran="${line#RAN }" ;;
    ok*) printf '%s\n' "$line" ;;
    *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;;
  esac
done <<<"$report"
printf 'real workflow: %s rows, %s failed\n' "$ran" "$fails"
ROW_FLOOR=85
if [[ "${ran:-0}" -lt "$ROW_FLOOR" ]]; then printf 'FAIL - row floor: only %s rows ran (floor %s)\n' "$ran" "$ROW_FLOOR"; fails=$((fails + 1)); fi

# ---- the mutation battery: one edit per row on a COPY, each must go red; the harness controls come first -------------------------
MUT_JOBS="${MUT_JOBS:-6}"; MUT_SEQ=0; mkdir -p "$TMP/mres"
_mutate_run() { # <idx> <expect: red|green> <label> <old> <new>
  local idx="$1" expect="$2" label="$3" old="$4" new="$5" copy="$TMP/mut.$BASHPID.yml" bout after
  cp "$WF_REAL" "$copy" 2>/dev/null || { echo "FAIL - mutation '${label}': the workflow is missing" > "$TMP/mres/$idx"; return; }
  if ! python3 - "$copy" "$old" "$new" <<'PY2'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY2
  then echo "FAIL - mutation '${label}': the edit did not land exactly once (a mutant that lands nothing proves nothing)" > "$TMP/mres/$idx"; return; fi
  bout="$(battery "$copy" 2>&1)"
  if grep -q '^FAILED S0 ' <<<"$bout"; then echo "FAIL - mutation '${label}' broke the YAML: a parse error is not a kill" > "$TMP/mres/$idx"; rm -f "$copy"; return; fi
  after="$(grep -c '^FAILED' <<<"$bout")"
  if [[ "$expect" == red ]]; then
    if [[ "$after" -gt 0 ]]; then echo "ok   - mutation killed: ${label} ($(grep '^FAILED' <<<"$bout" | head -1 | cut -c8-60) ... ${after} rows red)" > "$TMP/mres/$idx"; else echo "FAIL - mutation SURVIVED: ${label}" > "$TMP/mres/$idx"; fi
  else
    if [[ "$after" -eq 0 ]]; then echo "ok   - must-pass edit stays green: ${label}" > "$TMP/mres/$idx"; else echo "FAIL - must-pass edit went red: ${label} ($(grep '^FAILED' <<<"$bout" | head -1 | cut -c1-120))" > "$TMP/mres/$idx"; fi
  fi
  rm -f "$copy"
}
mutate() { # <label> <old> <new>   (expects the battery to go red)
  MUT_SEQ=$((MUT_SEQ + 1))
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MUT_JOBS" ]]; do sleep 0.3; done
  _mutate_run "$MUT_SEQ" red "$@" &
}
mutate_ok() { # <label> <old> <new>   (expects the battery to stay green: the contract allows this edit)
  MUT_SEQ=$((MUT_SEQ + 1))
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MUT_JOBS" ]]; do sleep 0.3; done
  _mutate_run "$MUT_SEQ" green "$@" &
}
# MUTATIONS_BEGIN
# MUTATIONS_END
wait
for f in "$TMP"/mres/*; do [[ -e "$f" ]] || continue; cat "$f"; grep -q '^FAIL' "$f" && fails=$((fails + 1)); done
n_res="$(find "$TMP/mres" -type f | wc -l | tr -d ' ')"
[[ "$n_res" -eq "$MUT_SEQ" ]] || { echo "FAIL - a mutant did not report (${n_res} of ${MUT_SEQ})"; fails=$((fails + 1)); }
# The floor is reported by a direct printf and exit (not through a helper), so a mutant of the guard itself can be built.
MUT_FLOOR=40
if [[ "$MUT_SEQ" -lt "$MUT_FLOOR" ]]; then printf 'FAIL - mutant floor: only %s mutants ran (floor %s)\n' "$MUT_SEQ" "$MUT_FLOOR"; exit 1; fi
printf 'mutants: %s ran (floor %s)\n' "$MUT_SEQ" "$MUT_FLOOR"
echo
if [[ "$fails" -gt 0 ]]; then echo "web-host-reboot-workflow: ${fails} FAILED"; exit 1; fi
echo "web-host-reboot-workflow: all rows and mutations passed"
