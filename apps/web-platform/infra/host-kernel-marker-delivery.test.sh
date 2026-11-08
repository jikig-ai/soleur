#!/usr/bin/env bash
# Delivery guard for the SOLEUR_HOST_KERNEL collector on the hosts that do NOT take it from the web image bake (#12007).
#
# WHAT THE SINGLE SOURCE OF TRUTH IS. apps/web-platform/infra/host-kernel-marker.sh (+ .service/.timer). Every other copy must be byte-equal:
#   web-1 / web-2 running hosts   terraform_data.host_kernel_marker_install(_web2) ship the repo files via provisioner "file" (equal by construction;
#                                 fresh-boot-parity.test.sh section 13d pins their shape). HELD: operator-applied, see terraform-target-parity.test.ts.
#   web fresh hosts               image bake (server.tf host_script_files, Dockerfile COPY, .dockerignore) -> soleur-host-bootstrap.sh -> cloud-init.yml
#   inngest dedicated host        inngest-bootstrap.sh writes the collector and its OWN unit pair from quoted heredocs. This suite extracts the three
#                                 heredocs and compares them byte-for-byte to the repo files (the unit differs ONLY in `--role inngest`).
#                                 The OCI bootstrap image already carries inngest-bootstrap.sh, so cloud-init-inngest.yml (its STAGED list) and
#                                 build-inngest-bootstrap-image.yml stay unchanged; the host receives the script only through the digest-pinned bootstrap
#                                 image, so a replaced host gets the emitter after a new bootstrap tag is minted and the pin is bumped.
#   registry host                 cloud-init-registry.yml write_files, a plain inline `content: |` entry (like zot-disk-heartbeat.sh in the same file): a copy of the
#                                 repo file indented 6 spaces with each dollar-brace doubled for templatefile. This suite compares the entry to the file BEFORE the render
#                                 (unescape + dedent == file) and, when terraform is on PATH, AFTER it: the stored form goes through registry-userdata-budget.sh and the
#                                 whole-line comment strip (local.registry_rationale_strip, extracted from zot-registry.tf), and must equal the file with that strip applied.
#                                 zot-disk-heartbeat.sh calls it at most once per 6 h AFTER its own post, reusing that script's post() and token judge.
#
# APPLY PATH (nothing applied by a merge). Neither hcloud_server.registry nor hcloud_server.inngest may appear in any per-merge job of
# apply-web-platform-infra.yml (only the *_host_replace dispatch jobs name them; the host_creates HALT counts create-or-replace and cannot be bypassed
# by [ack-destroy]), and the two web installers are in no -target list at all while the hold stands.
#
# The checker is a pure function over {name -> text}; the mutation battery feeds it corrupted copies and asserts WHICH check id fires.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
INFRA="${SOLEUR_INFRA_DIR:-$ROOT/apps/web-platform/infra}"
WORKFLOW="${SOLEUR_APPLY_WORKFLOW:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"
HELPER="${SOLEUR_HOST_STATE_SH:-$ROOT/plugins/soleur/skills/cve-exposure/scripts/host-state.sh}"

python3 - "$INFRA" "$WORKFLOW" "$HELPER" <<'PYEOF'
import base64, gzip, os, re, shutil, subprocess, sys, tempfile

INFRA, WORKFLOW, HELPER = sys.argv[1], sys.argv[2], sys.argv[3]
FLOOR_CHECKS = 0  # assigned below (43 with terraform on PATH, 42 without); EXACT (a checker that evaluates fewer ids has lost a family, more has gained one unpinned)

npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}")

def read(p):
    with open(p) as f: return f.read()

def load():
    d = lambda n: os.path.join(INFRA, n)
    return {
        "collector": read(d("host-kernel-marker.sh")),
        "service": read(d("host-kernel-marker.service")),
        "timer": read(d("host-kernel-marker.timer")),
        "inngest-bootstrap.sh": read(d("inngest-bootstrap.sh")),
        "cloud-init-registry.yml": read(d("cloud-init-registry.yml")),
        "zot-registry.tf": read(d("zot-registry.tf")),
        "registry-userdata-budget.sh": read(d("registry-userdata-budget.sh")),
        "helper": read(HELPER),
        "workflow": read(WORKFLOW),
    }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────────
def heredocs(text):
    """every quoted HKM heredoc `cat > "<dest>" <<'TAG'` -> {tag: body incl. trailing newline}."""
    out = {}
    for m in re.finditer(r"""cat > "?\$?\{?(\w+)\}?"? <<'(HKM\w*EOF)'[^\n]*\n(.*?)\n\2\n""", text, re.S):
        out[m.group(2)] = m.group(3) + "\n"
    return out

def yaml_entry(yml, path):
    m = re.search(r"^  - path: " + re.escape(path) + r"\n(.*?)(?=^  - path: |^  # ---|\Z)", yml, re.S | re.M)
    return m.group(1) if m else None

def workflow_jobs(wf):
    head = re.search(r"^jobs:\n", wf, re.M)
    body = wf[head.end():]
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\n", body, flags=re.M)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}

def job_if(block):
    m = re.search(r"^    if:(.*?)(?=^    [A-Za-z_-]+:|\Z)", block, re.S | re.M)
    return m.group(1) if m else ""

def job_needs(block):
    m = re.search(r"^    needs:(.*?)(?=^    [A-Za-z_-]+:|\Z)", block, re.S | re.M)
    return re.findall(r"[A-Za-z0-9_-]+", m.group(1)) if m else []

def render_registry(files):
    """Render cloud-init-registry.yml through the REAL budget script; the stripped render, None without terraform, ("ERR", text) on failure."""
    if shutil.which("terraform") is None: return None
    d = tempfile.mkdtemp(prefix="hkmdeliv.")
    try:
        mirror = os.path.join(d, "infra"); os.makedirs(mirror)
        for n, key in (("zot-registry.tf", "zot-registry.tf"), ("cloud-init-registry.yml", "cloud-init-registry.yml"),
                       ("registry-userdata-budget.sh", "registry-userdata-budget.sh")):
            with open(os.path.join(mirror, n), "w") as f: f.write(files[key])
        out = os.path.join(d, "rendered.yml")
        r = subprocess.run(["bash", os.path.join(mirror, "registry-userdata-budget.sh"), out], capture_output=True, text=True, cwd=d)
        if not os.path.exists(out): return ("ERR", r.stdout + r.stderr)
        return read(out)
    finally:
        shutil.rmtree(d, ignore_errors=True)

def entry_body(ent):
    """The dedented lines of a `content: |` block scalar (6-space indent, blank lines kept), or None."""
    m = re.search(r"^    content: \|\n((?:      [^\n]*\n|\n)+)", ent, re.M)
    if not m: return None
    return "".join(l[6:] if l.startswith("      ") else l for l in m.group(1).splitlines(True))

def collector_host(col, name):
    """Run the REAL collector with a stub `hostname` printing <name>; return its trailing host= token."""
    d = tempfile.mkdtemp(prefix="hkmhost.")
    try:
        sp = os.path.join(d, "hkm.sh")
        with open(sp, "w") as f: f.write(col)
        stub = os.path.join(d, "bin"); os.makedirs(stub)
        with open(os.path.join(stub, "hostname"), "w") as f: f.write(f"#!/bin/sh\necho {name}\n")
        os.chmod(os.path.join(stub, "hostname"), 0o755)
        env = dict(os.environ, HKM_TEST="1", HKM_STUB_BIN_DIR=stub, HKM_APT_TIMEOUT_S="1")
        r = subprocess.run(["bash", sp, "--role", "registry"], capture_output=True, text=True, env=env, timeout=60)
        toks = r.stdout.strip().split(" ")
        return toks[-1] if toks else ""
    finally:
        shutil.rmtree(d, ignore_errors=True)

def strip_comments(text, tf):
    """Apply local.registry_rationale_strip, EXTRACTED from zot-registry.tf (Go RE2 and Python agree on this shape), to the collector."""
    m = re.search(r'^\s*registry_rationale_strip\s*=\s*"/(\(\?m\).*?)/"', tf, re.M)
    assert m, "registry_rationale_strip not found"
    pat = m.group(1).replace("(?m)", "", 1).replace("\\t", "\t").replace("\\n", "\n")
    return re.sub(pat, "", text, flags=re.M)

HB_PATH = "/usr/local/bin/zot-disk-heartbeat.sh"
HKM_RE_EXPECTED = "HKM_RE='^SOLEUR_HOST_KERNEL v=1 role=registry kernel=[0-9a-z.-]+ uptime_s=[0-9a-z]+ reboot_required=[0-9a-z]+ sec_updates=[0-9a-z]+ host=soleur-registry$'"
HKM_DEGRADED_EXPECTED = 'HKM_LINE="SOLEUR_HOST_KERNEL v=1 role=registry kernel=unreadable uptime_s=unknown reboot_required=unknown sec_updates=unknown host=soleur-registry"'
# the reader's kernel shape (host-state.sh / the feeder qualify a row only on it); the degraded line must NOT match it
KERNEL_SHAPE = re.compile(r"kernel=[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+ ")
EVAL_COUNT = 0

def check(files, with_render=True):
    """Return the list of failing check ids."""
    global EVAL_COUNT
    bad = []
    def chk(cid, cond):
        global EVAL_COUNT
        EVAL_COUNT += 1
        if not cond: bad.append(cid)
    col = files["collector"]

    # ── I: inngest-bootstrap.sh ──────────────────────────────────────────────────────────────────────────────────
    ib = files["inngest-bootstrap.sh"]
    hd = heredocs(ib)
    chk("I-script", hd.get("HKMSCRIPTEOF") == col)
    chk("I-service-has-role-web-once", files["service"].count("--role web") == 1)
    chk("I-service", hd.get("HKMUNITEOF") == files["service"].replace("--role web", "--role inngest"))
    chk("I-timer", hd.get("HKMTIMEREOF") == files["timer"])
    chk("I-identifier", re.search(r"^SyslogIdentifier=host-kernel-marker$", hd.get("HKMUNITEOF", ""), re.M) is not None)
    m = re.search(r"# host-kernel-marker:begin\n(.*?)# host-kernel-marker:end", ib, re.S)
    blk = m.group(1) if m else ""
    chk("I-block", bool(blk))
    chk("I-gated-on-dedicated-host", re.match(r'\s*if \[\[ "\$DOPPLER_PROJECT" == "soleur-inngest" \]\]; then\n', blk) is not None)
    chk("I-enable", "systemctl enable --now host-kernel-marker.timer" in blk and re.search(r"systemctl start host-kernel-marker\.service \|\| log ", blk) is not None)
    chk("I-reload-before-enable", 0 <= blk.find("systemctl daemon-reload") < blk.find("systemctl enable --now host-kernel-marker.timer"))
    chk("I-script-mode-0755", re.search(r"chmod 0755 \"?\$\{?HKM_SCRIPT\}?\"?", blk) is not None)
    # Observability, never a gate: inngest-bootstrap.sh is `set -euo pipefail`, so every step of the block must log-and-continue on failure.
    chk("I-guarded-writes", len(re.findall(r"""cat > "\$HKM_(?:SCRIPT|UNIT|TIMER)" <<'HKM\w*EOF' \|\| log "warn: """, blk)) == 3
        and re.search(r'chmod 0755 "\$HKM_SCRIPT" \|\| log "warn: ', blk) is not None)
    chk("I-guarded-reload", re.search(r'^  systemctl daemon-reload \|\| log "warn: ', blk, re.M) is not None)

    # ── R: registry ───────────────────────────────────────────────────────────────────────────────────────────────
    ci = files["cloud-init-registry.yml"]
    ent = yaml_entry(ci, "/usr/local/bin/host-kernel-marker.sh")
    chk("R-entry", ent is not None)
    e = ent or ""
    body = entry_body(e)
    chk("R-entry-shape", "encoding:" not in e and body is not None and body.startswith("#!/usr/bin/env bash\n")
        and "permissions: '0755'" in e and "owner: root:root" in e)
    chk("R-no-gz-var", "host_kernel_marker_gz_b64" not in files["zot-registry.tf"] and "host_kernel_marker_gz_b64" not in files["registry-userdata-budget.sh"]
        and "host_kernel_marker_gz_b64" not in ci)
    chk("R-no-unescaped-interpolation", body is not None and re.search(r"(?<!\$)\$\{", body) is None and "%{" not in body)
    # the pre-render copy: unescape the template escape, and the entry must be the repo file byte for byte (comments included)
    chk("R-inline-copy-equals-collector", body is not None and body.replace("$${", "${") == col)
    if with_render:
        rendered = render_registry(files)
        if rendered is None:
            if os.environ.get("CI"):
                bad.append("R-render-unmeasurable"); EVAL_COUNT += 1
            else:
                print("[skip] R-render: terraform not on PATH (local dev; fails closed in CI)")
        elif isinstance(rendered, tuple):
            bad.append("R-render-failed:" + rendered[1][-300:]); EVAL_COUNT += 1
        else:
            # the stored form: comments stripped by the SAME expression the real render uses; the shebang (`#!`) must survive it
            rbody = entry_body(yaml_entry(rendered, "/usr/local/bin/host-kernel-marker.sh") or "")
            chk("R-render-bytes-equal-collector", rbody is not None and rbody == strip_comments(col, files["zot-registry.tf"]) and rbody.startswith("#!/usr/bin/env bash\n"))

    # zot-disk-heartbeat.sh call site
    hb = yaml_entry(ci, HB_PATH) or ""
    hb_m = re.search(r"# hkm:begin\n(.*?)# hkm:end", hb, re.S)
    call = hb_m.group(1) if hb_m else ""
    chk("H-block", bool(call))
    chk("H-single-post-and-judge", hb.count("post() {") == 1 and hb.count("_bs_ok() {") == 1)
    i_post = hb.find("post || post ||"); i_call = hb.find("# hkm:begin"); i_elif = hb.find('elif [ -n "$TOKEN" ]')
    chk("H-after-existing-post-inside-token-branch", 0 <= i_post < i_call < i_elif)
    chk("H-collector-role-registry", "/usr/local/bin/host-kernel-marker.sh --role registry" in call)
    chk("H-bounded", re.search(r"timeout -k 2 [0-9]+ ", call) is not None)
    chk("H-stamp-in-run", re.search(r"HKM_STAMP=/run/[A-Za-z0-9._-]+\n", call) is not None and "-mmin +359" in call)
    chk("H-retry-stamp-in-run", re.search(r"HKM_RETRY=/run/[A-Za-z0-9._-]+\n", call) is not None and "-mmin +29" in call
        and re.search(r'touch "\$HKM_RETRY"', call) is not None)
    # the collector runs under an ALLOWLISTED environment (env -i + a fixed PATH); a denylist of seam names is open-ended and was replaced.
    chk("H-env-allowlisted", "env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin timeout -k 2 45 /usr/local/bin/host-kernel-marker.sh --role registry" in call and "env -u" not in call)
    chk("H-whole-line-judge", HKM_RE_EXPECTED in call and re.search(r'\[\[ "\$HKM_LINE" =~ \$HKM_RE \]\]', call) is not None)
    chk("H-output-judged", "SOLEUR_HOST_KERNEL v=1 role=registry " in call and re.search(r'LINE="\$\{?HKM_LINE\}?"', call.replace("$$", "$")) is not None)
    # a collector that yields nothing valid posts a degraded line that FAILS the reader's kernel shape and names the state
    chk("H-degraded-line", HKM_DEGRADED_EXPECTED in call)
    chk("H-failure-swallowed", not re.search(r"^\s*set -[a-z]*e", hb, re.M) and 'HKM_LINE=""' in call and re.search(r"\n      exit 0\n    owner: root:root", hb) is not None)

    # ── Y: registry host identity ─────────────────────────────────────────────────────────────────────────────────
    helper_id = re.search(r"^readonly REGISTRY_HOST_ID='([^']+)'$", files["helper"], re.M)
    tf_name = re.search(r'resource "hcloud_server" "registry" \{\s*\n\s*name\s*=\s*"([^"]+)"', files["zot-registry.tf"])
    chk("Y-id-found", helper_id is not None and tf_name is not None)
    chk("Y-helper-id-equals-server-name", helper_id is not None and tf_name is not None and helper_id.group(1) == tf_name.group(1))
    chk("Y-no-hostname-override", re.search(r"^\s*(preserve_hostname|hostname|fqdn):", ci, re.M) is None)
    if helper_id is not None:
        # The two host literals in the call site (the whole-line judge and the degraded line) are the registry id the helper pins.
        chk("Y-call-site-host-literals-equal-helper-id", len(re.findall(r" host=" + re.escape(helper_id.group(1)) + r"""["'$]""", call)) == 2 and call.count("host=") == 2)
    if helper_id is not None and tf_name is not None:
        # The host's hostname is the Terraform server name (no cloud-init override, Y-no-hostname-override); the collector's host= for the registry role must
        # equal the id the helper pins, or the helper rejects every registry row as unattributable and the host stays unknown forever.
        chk("Y-collector-host-equals-helper-id", collector_host(col, tf_name.group(1)) == f"host={helper_id.group(1)}")

    # ── A: apply path ─────────────────────────────────────────────────────────────────────────────────────────────
    wf = files["workflow"]
    jobs = workflow_jobs(wf)
    dispatch = {n for n, b in jobs.items() if "workflow_dispatch" in job_if(b)}
    dependents = {n for n, b in jobs.items() if any(x in dispatch for x in job_needs(b))}
    per_merge = {n: b for n, b in jobs.items() if n not in dispatch and n not in dependents}
    chk("A-per-merge-jobs-found", "apply" in per_merge and "preflight" in per_merge and len(dispatch) >= 5)
    def names(block, addr):
        return re.search(r"-(?:target|replace)[= ]['\"]?" + re.escape(addr) + r"['\"]?(?:\s|\\|$)", block, re.M) is not None
    for addr in ("hcloud_server.registry", "hcloud_server.inngest"):
        chk(f"A-{addr}-in-no-per-merge-job", not any(names(b, addr) for b in per_merge.values()))
        chk(f"A-{addr}-named-by-a-dispatch-job", any(names(jobs[n], addr) for n in dispatch))
    for addr in ("terraform_data.host_kernel_marker_install", "terraform_data.host_kernel_marker_install_web2"):
        chk(f"A-{addr}-in-no-target-list", not names(wf, addr))
    ssh_stage = per_merge.get("apply", "")
    chk("A-ssh-stage-found", "-target=terraform_data.egress_gateway_web2" in ssh_stage and "-target=terraform_data.nonlocal_bind_sysctl_web2" in ssh_stage)
    return bad

# ── behaviour of the registry call site (the REAL snippet, absolute paths pointed at a sandbox) ───────────────────────
GOOD_LINE = "SOLEUR_HOST_KERNEL v=1 role=registry kernel=9.9.9-1-test uptime_s=1 reboot_required=0 sec_updates=0 host=soleur-registry"
DEGRADED = "SOLEUR_HOST_KERNEL v=1 role=registry kernel=unreadable uptime_s=unknown reboot_required=unknown sec_updates=unknown host=soleur-registry"
SECRET = "doppler-injected-secret-sentinel"
def run_call_site(files, collector, stamp=None, retry=None, post_fails=False):
    """stamp/retry: None (absent) | "fresh" | "mid" (10 min old) | "old" (40 min old for retry, ancient for stamp)."""
    hb = yaml_entry(files["cloud-init-registry.yml"], HB_PATH) or ""
    m = re.search(r"# hkm:begin\n(.*?)# hkm:end", hb, re.S)
    if not m: return None
    snippet = m.group(1).replace("$$", "$")
    d = tempfile.mkdtemp(prefix="hkmcall.")
    try:
        coll = os.path.join(d, "collector.sh"); stampf = os.path.join(d, "stamp"); retryf = os.path.join(d, "retry")
        posted = os.path.join(d, "posted"); ran = os.path.join(d, "ran"); seen = os.path.join(d, "seenenv")
        pre = f'touch "{ran}"; env > "{seen}"; '
        body = {"ok": f'echo "{GOOD_LINE}"',
                "trailing": f'echo "{GOOD_LINE} t=1"',
                "otherhost": f'echo "{GOOD_LINE.replace("host=soleur-registry", "host=other-host")}"',
                "multiline": f'echo "{GOOD_LINE}"; echo "{GOOD_LINE}"',
                "uppercase": f'echo "{GOOD_LINE.replace("kernel=9.9.9-1-test", "kernel=9.9.9-1-Test")}"',
                "garbage": 'echo "not a marker"', "fail": "exit 7", "empty": ":", "missing": None}[collector]
        if body is not None:
            with open(coll, "w") as f: f.write("#!/bin/sh\n" + pre + body + "\n")
            os.chmod(coll, 0o755)
        snippet = snippet.replace("/usr/local/bin/host-kernel-marker.sh", coll)
        snippet = re.sub(r"HKM_STAMP=/run/[A-Za-z0-9._-]+", "HKM_STAMP=" + stampf, snippet)
        snippet = re.sub(r"HKM_RETRY=/run/[A-Za-z0-9._-]+", "HKM_RETRY=" + retryf, snippet)
        now = __import__("time").time()
        for path, kind, old in ((stampf, stamp, 1.0), (retryf, retry, now - 2400)):
            if kind is None: continue
            open(path, "w").close()
            if kind == "mid": os.utime(path, (now - 600, now - 600))
            if kind == "old": os.utime(path, (old, old))
        post_body = "return 1" if post_fails else f"printf '%s\\n' \"$LINE\" >> '{posted}'"
        prog = f"set -u\nTOKEN=tok\nLINE=original\n_bs_ok() {{ return 0; }}\npost() {{ {post_body}; }}\n{snippet}\necho done-rc=$?\n"
        env = dict(os.environ, HKM_TEST="1", HKM_STUB_BIN_DIR="/nonexistent", DOPPLER_SENTINEL=SECRET)
        r = subprocess.run(["bash", "-c", prog], capture_output=True, text=True, env=env, timeout=90)
        posts = read(posted).splitlines() if os.path.exists(posted) else []
        out = r.stdout.strip().splitlines()
        seen_env = read(seen) if os.path.exists(seen) else None
        return {"rc_line": out[-1] if out else "", "posts": posts, "stamp": os.path.exists(stampf), "retry": os.path.exists(retryf),
                "ran": os.path.exists(ran), "seen_env": seen_env, "err": r.stderr[-200:]}
    finally:
        shutil.rmtree(d, ignore_errors=True)

real = load()

# ── 1. the real tree is clean ─────────────────────────────────────────────────────────────────────────────────────────
before = EVAL_COUNT
got = check(real)
n_eval = EVAL_COUNT - before
HAVE_TF = shutil.which("terraform") is not None
FLOOR_CHECKS = 43 if HAVE_TF else 42
if not got: ok(f"real tree: all {n_eval} delivery checks hold")
else: no(f"real tree: failing checks {got}")
# The id-count floor is EXACT and reported by a direct print + exit 1, never through no(): a family lost (or one added without moving this number)
# must fail even if the verdict helpers were neutered. Without terraform the render arm is skipped, hence one fewer.
if n_eval != FLOOR_CHECKS:
    print(f"host-kernel-marker-delivery: FAIL (checker evaluated {n_eval} ids, expected exactly {FLOOR_CHECKS}: a check family was lost or added without moving the floor)")
    sys.exit(1)
ok(f"checker evaluated exactly {n_eval} ids (floor {FLOOR_CHECKS})")

# ── 2. behaviour of the registry call site ────────────────────────────────────────────────────────────────────────────
def fmt(r):
    return "None" if r is None else {k: r[k] for k in ("posts", "stamp", "retry", "ran", "rc_line")}
def good(r, stamped): return bool(r) and r["posts"] == [GOOD_LINE] and r["stamp"] == stamped and r["retry"] and r["rc_line"] == "done-rc=0"
r = run_call_site(real, "ok")
(ok if good(r, True) else no)(f"call site: no stamp -> posts the collector line once through post(), writes the 6 h stamp and the retry stamp, rc 0 ({fmt(r)})")
(ok if r and r["seen_env"] is not None and SECRET not in r["seen_env"] and "HKM_TEST" not in r["seen_env"] and "HKM_STUB_BIN_DIR" not in r["seen_env"]
    and "PATH=/usr/sbin:/usr/bin:/sbin:/bin" in r["seen_env"] else no)(
    f"call site: the collector sees ONLY the allowlisted environment (no inherited secret, no test seam; fixed system PATH) ({r and r['seen_env'] and r['seen_env'].replace(chr(10), ' ')[-120:]})")
r = run_call_site(real, "ok", stamp="fresh")
(ok if r and r["posts"] == [] and not r["ran"] and r["rc_line"] == "done-rc=0" else no)(f"call site: fresh 6 h stamp -> the collector does not even run ({fmt(r)})")
r = run_call_site(real, "ok", stamp="old")
(ok if good(r, True) else no)(f"call site: 6 h stamp older than 6 h, no retry stamp -> posts again ({fmt(r)})")
r = run_call_site(real, "ok", stamp="old", retry="fresh")
(ok if r and r["posts"] == [] and not r["ran"] and r["rc_line"] == "done-rc=0" else no)(f"call site: stale 6 h stamp but a fresh retry stamp -> the collector does not run (retry throttle) ({fmt(r)})")
r = run_call_site(real, "ok", stamp="old", retry="mid")
(ok if r and r["posts"] == [] and not r["ran"] else no)(f"call site: retry stamp 10 min old -> still throttled ({fmt(r)})")
r = run_call_site(real, "ok", stamp="old", retry="old")
(ok if good(r, True) else no)(f"call site: retry stamp 40 min old -> runs again ({fmt(r)})")
r = run_call_site(real, "ok", retry="fresh")
(ok if r and r["posts"] == [] and not r["ran"] else no)(f"call site: no 6 h stamp but a fresh retry stamp (a failed first attempt) -> throttled, not re-run on the next 5-min tick ({fmt(r)})")
for what in ("garbage", "fail", "empty", "missing", "trailing", "otherhost", "multiline", "uppercase"):
    r = run_call_site(real, what)
    (ok if r and r["posts"] == [DEGRADED] and not r["stamp"] and r["retry"] and r["rc_line"] == "done-rc=0" else no)(
        f"call site: collector '{what}' -> exactly the degraded line is posted, no 6 h stamp, retry stamp written, rc 0 ({fmt(r)})")
(ok if KERNEL_SHAPE.search(DEGRADED) is None and "kernel=unreadable" in DEGRADED and DEGRADED.endswith(" host=soleur-registry") else no)(
    "call site: the degraded line fails the reader's kernel shape and names the state")
r = run_call_site(real, "ok", post_fails=True)
(ok if r and r["posts"] == [] and not r["stamp"] and r["retry"] and r["rc_line"] == "done-rc=0" else no)(
    f"call site: a failing post() is swallowed (rc 0), writes no 6 h stamp, but DOES write the retry stamp so ingest trouble costs at most one collector run per 30 min ({fmt(r)})")
r = run_call_site(real, "garbage", post_fails=True)
(ok if r and r["posts"] == [] and not r["stamp"] and r["retry"] and r["rc_line"] == "done-rc=0" else no)(
    f"call site: a broken collector AND a failing post() still ends rc 0 with the retry stamp ({fmt(r)})")

# ── 3. mutation battery ───────────────────────────────────────────────────────────────────────────────────────────────
def on(name, fn):
    def mut(files):
        out = dict(files); new = fn(files[name]); assert new != files[name], "mutation did not land"; out[name] = new; return out
    return mut
def sub(a, b):
    def f(s):
        assert a in s, f"anchor {a[:50]!r} absent"; return s.replace(a, b, 1)
    return f
def resub(pat, rep):
    def f(s):
        new, n = re.subn(pat, rep, s, count=1, flags=re.M | re.S); assert n == 1, f"pattern {pat!r} did not match"; return new
    return f
def hoist(s):
    m = re.search(r"      # hkm:begin\n.*?      # hkm:end\n", s, re.S)
    assert m, "no hkm block"
    blk = m.group(0)
    s2 = s.replace(blk, "", 1)
    assert "        post() {" in s2
    return s2.replace("        post() {", blk + "        post() {", 1)

SSH_TAIL = "-target=terraform_data.egress_gateway_web2 2>&1"
MUTANTS = [
    ("inngest: collector copy drifts one byte", on("inngest-bootstrap.sh", resub(r"(<<'HKMSCRIPTEOF'[^\n]*\n.*?)exit 0\n", r"\1exit 1\n")), ["I-script"]),
    ("inngest: unit loses --role inngest", on("inngest-bootstrap.sh", sub("host-kernel-marker.sh --role inngest", "host-kernel-marker.sh --role web")), ["I-service"]),
    ("inngest: SyslogIdentifier changed", on("inngest-bootstrap.sh", resub(r"(<<'HKMUNITEOF'[^\n]*\n.*?)SyslogIdentifier=host-kernel-marker\n", r"\1SyslogIdentifier=host-kernel-markerX\n")), ["I-identifier", "I-service"]),
    ("inngest: timer cadence drifts", on("inngest-bootstrap.sh", resub(r"(<<'HKMTIMEREOF'[^\n]*\n.*?)OnBootSec=2min", r"\1OnBootSec=9min")), ["I-timer"]),
    ("inngest: install not gated on the dedicated host", on("inngest-bootstrap.sh", resub(r'(# host-kernel-marker:begin\n)if \[\[ "\$DOPPLER_PROJECT" == "soleur-inngest" \]\]; then', r"\1if true; then")), ["I-gated-on-dedicated-host"]),
    ("inngest: timer never enabled", on("inngest-bootstrap.sh", sub("systemctl enable --now host-kernel-marker.timer", "true")), ["I-enable"]),
    ("inngest: unit gains a second --role web mention (the role rewrite is no longer a single swap)", on("service", lambda s: s + "# --role web\n"), ["I-service-has-role-web-once"]),
    ("inngest: collector not made executable", on("inngest-bootstrap.sh", sub('chmod 0755 "$HKM_SCRIPT"', 'chmod 0644 "$HKM_SCRIPT"')), ["I-script-mode-0755"]),
    ("inngest: collector write unguarded under set -e", on("inngest-bootstrap.sh", sub(" || log \"warn: host-kernel-marker collector write failed (#12007)\"", "")), ["I-guarded-writes"]),
    ("inngest: chmod unguarded under set -e", on("inngest-bootstrap.sh", sub('chmod 0755 "$HKM_SCRIPT" || log "warn: host-kernel-marker chmod failed (#12007)"', 'chmod 0755 "$HKM_SCRIPT"')), ["I-guarded-writes"]),
    ("inngest: daemon-reload unguarded under set -e", on("inngest-bootstrap.sh", sub(' || log "warn: host-kernel-marker daemon-reload failed (#12007)"', "")), ["I-guarded-reload"]),
    ("inngest: daemon-reload dropped", on("inngest-bootstrap.sh", resub(r"(# host-kernel-marker:begin\n.*?)systemctl daemon-reload", r"\1true")), ["I-reload-before-enable"]),
    ("registry: write_files entry removed", on("cloud-init-registry.yml", sub("- path: /usr/local/bin/host-kernel-marker.sh", "- path: /usr/local/bin/other.sh")), ["R-entry"]),
    ("registry: entry grows an encoding key (the retired gz+b64 form)", on("cloud-init-registry.yml", sub("- path: /usr/local/bin/host-kernel-marker.sh\n", "- path: /usr/local/bin/host-kernel-marker.sh\n    encoding: gz+b64\n")), ["R-entry-shape"]),
    ("registry: shebang lost from the entry", on("cloud-init-registry.yml", resub(r"(host-kernel-marker\.sh\n    content: \|\n)      #!/usr/bin/env bash\n", r"\1")), ["R-entry-shape", "R-inline-copy-equals-collector"]),
    ("registry: the retired gz var returns in zot-registry.tf", on("zot-registry.tf", sub("private_ip = local.registry_private_ip\n", "private_ip = local.registry_private_ip\n    host_kernel_marker_gz_b64 = \"x\"\n")), ["R-no-gz-var"]),
    ("registry: the retired gz var returns in the budget script", on("registry-userdata-budget.sh", sub("betterstack_ingest_url = \"${BS_INGEST_URL}\"\n", "betterstack_ingest_url = \"${BS_INGEST_URL}\"\n    host_kernel_marker_gz_b64 = \"x\"\n")), ["R-no-gz-var"]),
    ("registry: inline copy drifts from the collector (code line changed)", on("cloud-init-registry.yml", resub(r"(host-kernel-marker\.sh\n    content: \|\n.*?)      exit 0\n", r"\1      exit 1\n")), ["R-inline-copy-equals-collector"]),
    ("registry: a dollar-brace left unescaped in the entry (templatefile would interpolate it)", on("cloud-init-registry.yml", resub(r"(host-kernel-marker\.sh\n    content: \|\n.*?)\$\$\{HKM_TEST", r"\1${HKM_TEST")), ["R-no-unescaped-interpolation"]),
    ("registry: heartbeat call removed", on("cloud-init-registry.yml", resub(r"      # hkm:begin\n.*?      # hkm:end\n", "")), ["H-block"]),
    ("registry: heartbeat call precedes the existing post", on("cloud-init-registry.yml", hoist), ["H-after-existing-post-inside-token-branch"]),
    ("registry: a fifth copy of the token judge", on("cloud-init-registry.yml", resub(r"(      # hkm:begin\n)", r"\1      _bs_ok() { return 0; }\n")), ["H-single-post-and-judge"]),
    ("registry: a second post() definition", on("cloud-init-registry.yml", resub(r"(      # hkm:begin\n)", r"\1      post() { :; }\n")), ["H-single-post-and-judge"]),
    ("registry: no timeout bound", on("cloud-init-registry.yml", resub(r"timeout -k 2 [0-9]+ ", "")), ["H-bounded"]),
    ("registry: env allowlist dropped (inherits the doppler environment)", on("cloud-init-registry.yml", sub("env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin timeout", "timeout")), ["H-env-allowlisted"]),
    ("registry: allowlist reverted to a seam denylist", on("cloud-init-registry.yml", sub("env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin timeout", "env -u HKM_TEST timeout")), ["H-env-allowlisted"]),
    ("registry: collector role drifts", on("cloud-init-registry.yml", resub(r"(# hkm:begin.*?host-kernel-marker\.sh --role )registry", r"\1web")), ["H-collector-role-registry"]),
    ("registry: posted line no longer the judged one", on("cloud-init-registry.yml", resub(r'(# hkm:begin.*?)LINE="\$HKM_LINE"', r'\1LINE="$HKM_RAW"')), ["H-output-judged"]),
    ("registry: whole-line judge loses its end anchor", on("cloud-init-registry.yml", sub("host=soleur-registry$'", "host=soleur-registry'")), ["H-whole-line-judge"]),
    ("registry: whole-line judge no longer applied", on("cloud-init-registry.yml", sub("if ! [[ \"$HKM_LINE\" =~ $HKM_RE ]]; then", "if false; then")), ["H-whole-line-judge"]),
    ("registry: degraded line would qualify as a kernel", on("cloud-init-registry.yml", sub("kernel=unreadable uptime_s=unknown reboot_required=unknown sec_updates=unknown host=soleur-registry\"\n", "kernel=9.9.9-1-x uptime_s=unknown reboot_required=unknown sec_updates=unknown host=soleur-registry\"\n")), ["H-degraded-line"]),
    ("registry: degraded line carries another host id", on("cloud-init-registry.yml", sub("sec_updates=unknown host=soleur-registry\"\n", "sec_updates=unknown host=soleur-registry2\"\n")), ["H-degraded-line", "Y-call-site-host-literals-equal-helper-id"]),
    ("registry: retry stamp never written", on("cloud-init-registry.yml", sub('touch "$HKM_RETRY" 2>/dev/null || true', "true")), ["H-retry-stamp-in-run"]),
    ("registry: retry stamp moved out of /run", on("cloud-init-registry.yml", sub("HKM_RETRY=/run/", "HKM_RETRY=/var/lib/")), ["H-retry-stamp-in-run"]),
    ("registry: retry throttle window removed", on("cloud-init-registry.yml", sub("-mmin +29", "-mmin +0")), ["H-retry-stamp-in-run"]),
    ("registry: a hostname override is introduced", on("cloud-init-registry.yml", lambda s: s + "\npreserve_hostname: true\n"), ["Y-no-hostname-override"]),
    ("registry: stamp moved out of /run", on("cloud-init-registry.yml", sub("HKM_STAMP=/run/", "HKM_STAMP=/var/lib/")), ["H-stamp-in-run"]),
    ("registry: heartbeat script gains set -e", on("cloud-init-registry.yml", sub("      set -u\n      # (#8386) cron's own PATH", "      set -eu\n      # (#8386) cron's own PATH")), ["H-failure-swallowed"]),
    ("identity: helper id drifts", on("helper", sub("readonly REGISTRY_HOST_ID='soleur-registry'", "readonly REGISTRY_HOST_ID='soleur-registry2'")), ["Y-helper-id-equals-server-name", "Y-collector-host-equals-helper-id"]),
    ("identity: server renamed", on("zot-registry.tf", resub(r'(resource "hcloud_server" "registry" \{\s*\n\s*name\s*=\s*"soleur-registry)"', r'\1-b"')), ["Y-helper-id-equals-server-name"]),
    ("apply: registry replace added to the per-merge apply job", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=hcloud_server.registry 2>&1")), ["A-hcloud_server.registry-in-no-per-merge-job"]),
    ("apply: inngest replace added to the per-merge apply job", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -replace=hcloud_server.inngest 2>&1")), ["A-hcloud_server.inngest-in-no-per-merge-job"]),
    ("apply: web-1 installer enters the SSH stage", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=terraform_data.host_kernel_marker_install 2>&1")), ["A-terraform_data.host_kernel_marker_install-in-no-target-list"]),
    ("apply: web-1 installer enters the SSH stage in the space form (-target addr)", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target terraform_data.host_kernel_marker_install 2>&1")), ["A-terraform_data.host_kernel_marker_install-in-no-target-list"]),
    ("apply: registry replace added to the per-merge apply job in the space form", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -replace hcloud_server.registry 2>&1")), ["A-hcloud_server.registry-in-no-per-merge-job"]),
    ("apply: web-2 installer enters the SSH stage", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=terraform_data.host_kernel_marker_install_web2 2>&1")), ["A-terraform_data.host_kernel_marker_install_web2-in-no-target-list"]),
    ("apply: the dispatch jobs stop naming the registry (vacuity)", on("workflow", lambda s: s.replace("hcloud_server.registry'", "hcloud_server.registry_gone'")), ["A-hcloud_server.registry-named-by-a-dispatch-job"]),
    ("HARMLESS: comment appended to the helper", on("helper", lambda s: s + "\n# harmless\n"), []),
]

for label, mut, expect in MUTANTS:
    try:
        got = check(mut(real), with_render=False)
    except AssertionError as e:
        no(f"mutant '{label}': mutation did not land ({e}) -- fix the anchor, a vacuous mutant proves nothing")
        continue
    if not expect:
        (ok if not got else no)(f"mutant '{label}' is harmless: " + ("still passes" if not got else f"unexpectedly failed {got}"))
    elif all(e in got for e in expect):
        ok(f"mutant '{label}' killed by {expect}")
    else:
        no(f"mutant '{label}' NOT killed by {expect} (failing: {got})")

# The render arm: a collector CODE edit that is not mirrored into the inngest heredocs and the registry entry must be caught by all three members, the registry one
# both before the render (inline copy) and after it (stored form). A comment-only edit is invisible to the stored form by design (the strip), but not to the others.
if HAVE_TF:
    mut = dict(real); mut["collector"] = real["collector"] + ":\n"
    got = check(mut, with_render=True)
    (ok if all(x in got for x in ("I-script", "R-inline-copy-equals-collector", "R-render-bytes-equal-collector")) else no)(
        f"mutant 'collector code edited, no copy re-synced': inngest parity, the inline registry copy and the stored form all fire (failing: {got})")
    mut = dict(real); mut["collector"] = real["collector"] + "# drift\n"
    got = check(mut, with_render=True)
    (ok if "R-inline-copy-equals-collector" in got and "I-script" in got and "R-render-bytes-equal-collector" not in got else no)(
        f"mutant 'collector comment edited, no copy re-synced': both byte copies fire, the comment-stripped stored form does not (failing: {got})")

print(f"=== host-kernel-marker-delivery: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
PYEOF
