#!/usr/bin/env bash
# Delivery guard for the SOLEUR_HOST_KERNEL collector on the hosts that do NOT take it from the web image bake (#12007).
#
# WHAT THE SINGLE SOURCE OF TRUTH IS. apps/web-platform/infra/host-kernel-marker.sh (+ .service/.timer). Every other copy must be byte-equal:
#   web-1 / web-2 running hosts   terraform_data.host_kernel_marker_install(_web2) ship the repo files via provisioner "file" (equal by construction;
#                                 fresh-boot-parity.test.sh section 13d pins their shape). HELD: operator-applied, see terraform-target-parity.test.ts.
#   web fresh hosts               image bake (server.tf host_script_files, Dockerfile COPY, .dockerignore) -> soleur-host-bootstrap.sh -> cloud-init.yml
#   inngest dedicated host        inngest-bootstrap.sh writes the collector and its OWN unit pair from quoted heredocs. This suite extracts the three
#                                 heredocs and compares them byte-for-byte to the repo files (the unit differs ONLY in `--role inngest`), pins that the
#                                 destination assignments equal the web installers' destination paths, and pins that every install step is guarded
#                                 (set -euo pipefail) AND reports a failure through a shipped journald line. Whole-line `#` comments are stripped from the
#                                 install block before any check, so a commented-out step cannot satisfy a pin.
#                                 The OCI bootstrap image already carries inngest-bootstrap.sh, so cloud-init-inngest.yml (its STAGED list) and
#                                 build-inngest-bootstrap-image.yml stay unchanged; the host receives the script only through the digest-pinned bootstrap
#                                 image, so a replaced host gets the emitter after a new bootstrap tag is minted and the pin is bumped.
#   registry host                 EXEMPT, keyed to #12386. A merged change to cloud-init-registry.yml auto-fires registry-host-replace-dispatch.yml (deliver=true when the
#                                 offline-rendered user_data differs from the merge base), which REPLACES the production registry host with no reviewer gate, so the
#                                 registry emitter ships in a follow-up PR. Until then cloud-init-registry.yml, zot-registry.tf and registry-userdata-budget.sh carry NO
#                                 collector (the R rows pin that), the collector already accepts `--role registry`, and its registry id constant equals the id host-state.sh
#                                 pins (the Y rows). The follow-up PR flips this exemption ON PURPOSE: the R ratchet goes RED the moment a collector token enters the registry
#                                 cloud-init, and that PR replaces the R rows with the delivery pins.
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
import os, re, shutil, subprocess, sys, tempfile

INFRA, WORKFLOW, HELPER = sys.argv[1], sys.argv[2], sys.argv[3]

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
        "server.tf": read(d("server.tf")),
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

def strip_whole_line_comments(text):
    """Drop every line whose first non-blank character is `#`, so a commented-out step cannot satisfy a pin."""
    return "".join(l for l in text.splitlines(True) if not l.lstrip().startswith("#"))

def web_dests(tf, res):
    """{extension: destination} of the three provisioner "file" destinations of one web installer resource, or None."""
    m = re.search(r'resource "terraform_data" "' + re.escape(res) + r'" \{\n(.*?)^\}', tf, re.S | re.M)
    if not m: return None
    dests = re.findall(r'^\s*destination\s*=\s*"([^"]+)"', strip_whole_line_comments(m.group(1)), re.M)
    return {d.rsplit(".", 1)[1]: d for d in dests} if len(dests) == 3 else None

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

EVAL_COUNT = 0

def check(files):
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
    # EVERY pin below reads the block with whole-line comments stripped: a step commented out must not satisfy it.
    blk = strip_whole_line_comments(m.group(1)) if m else ""
    chk("I-block", bool(blk))
    chk("I-gated-on-dedicated-host", re.match(r'\s*if \[\[ "\$DOPPLER_PROJECT" == "soleur-inngest" \]\]; then\n', blk) is not None)
    # Every command pin anchors at COMMAND POSITION (`^[ \t]*` under re.M): the whole-line-comment strip does not cover a trailing `: # <same text>` mutant.
    chk("I-enable", re.search(r"^[ \t]*systemctl enable --now host-kernel-marker\.timer ", blk, re.M) is not None
        and re.search(r"^[ \t]*systemctl start host-kernel-marker\.service \|\| hkm_warn oneshot_start ", blk, re.M) is not None)
    chk("I-reload-before-enable", 0 <= blk.find("systemctl daemon-reload") < blk.find("systemctl enable --now host-kernel-marker.timer"))
    chk("I-script-mode-0755", re.search(r"^[ \t]*chmod 0755 \"?\$\{?HKM_SCRIPT\}?\"?", blk, re.M) is not None)
    # Observability, never a gate: inngest-bootstrap.sh is `set -euo pipefail`, so every step of the block must report-and-continue on failure.
    chk("I-guarded-writes", len(re.findall(r"""^[ \t]*cat > "\$HKM_(?:SCRIPT|UNIT|TIMER)" <<'HKM\w*EOF' \|\| hkm_warn write_(?:script|unit|timer) \"""", blk, re.M)) == 3
        and re.search(r'^[ \t]*chmod 0755 "\$HKM_SCRIPT" \|\| hkm_warn chmod_script "', blk, re.M) is not None)
    chk("I-guarded-reload", re.search(r'^  systemctl daemon-reload \|\| hkm_warn daemon_reload "', blk, re.M) is not None)
    chk("I-guarded-enable", re.search(r'^  systemctl enable --now host-kernel-marker\.timer \|\| hkm_warn timer_enable "', blk, re.M) is not None)
    # Every guarded failure is ALSO a shipped journald line (`log` goes to the bootstrap's stderr only, which is not shipped): one helper, seven call sites.
    # ORDER is pinned: the shipped `logger` line first, `log ... || true` last (a failing stderr write makes `log` return 1, and under set -e that exits the bootstrap
    # before the off-box line is written; reproduced with `2>&-`).
    chk("I-warn-logger", re.search(r'^  hkm_warn\(\) \{\n    logger -t host-kernel-marker "HOST_KERNEL_MARKER_INSTALL_WARN step=\$1" \|\| true\n    log "warn: host-kernel-marker \$2" \|\| true\n  \}$', blk, re.M) is not None)
    # The helper is DEFINED before its first use (a call before the definition is command-not-found under set -e on a real run).
    chk("I-warn-defined-before-use", 0 <= blk.find("hkm_warn() {") < blk.find('cat > "$HKM_SCRIPT"'))
    logger_lines = [l for l in blk.splitlines() if l.lstrip().startswith("logger ")]
    chk("I-warn-not-a-marker", len(logger_lines) == 1 and "SOLEUR_HOST_KERNEL" not in logger_lines[0])
    chk("I-warn-call-sites", len(re.findall(r" \|\| hkm_warn [a-z_]+ \"", blk)) == 7)
    # The destination assignments equal the web installers' destination paths (a rename here installs a second, unreviewed copy that the web pair does not own).
    w1 = web_dests(files["server.tf"], "host_kernel_marker_install")
    w2 = web_dests(files["server.tf"], "host_kernel_marker_install_web2")
    chk("I-dest-web-pair-found", w1 is not None and w1 == w2 and set(w1) == {"sh", "service", "timer"})
    for var, ext in (("HKM_SCRIPT", "sh"), ("HKM_UNIT", "service"), ("HKM_TIMER", "timer")):
        a = re.findall(r'^  ' + var + r'="([^"]+)"$', blk, re.M)
        chk(f"I-dest-{ext}-equals-web-installer", w1 is not None and a == [w1.get(ext)])

    # ── R: registry host is EXEMPT (#12386) ───────────────────────────────────────────────────────────────────────
    # A merged cloud-init-registry.yml change auto-fires the production registry host REPLACE (registry-host-replace-dispatch.yml), so this PR must carry NO registry
    # emitter. The follow-up PR flips the exemption on purpose; these rows go RED the moment a collector token enters the registry cloud-init / render inputs.
    ci = files["cloud-init-registry.yml"]
    chk("R-exempt-no-collector-path", "host-kernel-marker" not in ci)
    chk("R-exempt-no-marker-token", "SOLEUR_HOST_KERNEL" not in ci)
    chk("R-exempt-render-inputs-untouched", all(x not in files[f] for f in ("zot-registry.tf", "registry-userdata-budget.sh") for x in ("host_kernel_marker", "host-kernel-marker", "SOLEUR_HOST_KERNEL")))
    chk("R-collector-accepts-role-registry", re.search(r"^  web \| inngest \| registry\) :", col, re.M) is not None)

    # ── Y: registry host identity ─────────────────────────────────────────────────────────────────────────────────
    helper_id = re.search(r"^readonly REGISTRY_HOST_ID='([^']+)'$", files["helper"], re.M)
    coll_id = re.search(r"^readonly REGISTRY_HOST_ID='([^']+)'$", col, re.M)
    tf_name = re.search(r'resource "hcloud_server" "registry" \{\s*\n\s*name\s*=\s*"([^"]+)"', files["zot-registry.tf"])
    chk("Y-id-found", helper_id is not None and tf_name is not None and coll_id is not None)
    chk("Y-helper-id-equals-server-name", helper_id is not None and tf_name is not None and helper_id.group(1) == tf_name.group(1))
    chk("Y-collector-id-constant-equals-helper-id", helper_id is not None and coll_id is not None and helper_id.group(1) == coll_id.group(1))
    chk("Y-no-hostname-override", re.search(r"^\s*(preserve_hostname|hostname|fqdn):", ci, re.M) is None)
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

real = load()

# ── 1. the real tree is clean ─────────────────────────────────────────────────────────────────────────────────────────
before = EVAL_COUNT
got = check(real)
n_eval = EVAL_COUNT - before
if not got: ok(f"real tree: all {n_eval} delivery checks hold")
else: no(f"real tree: failing checks {got}")
# The id-count floor is EXACT and reported by a direct print + exit 1, never through no(): a family lost (or one added without moving this number)
# must fail even if the verdict helpers were neutered. No check depends on terraform or the CI environment.
FLOOR_CHECKS = 38
if n_eval != FLOOR_CHECKS:
    print(f"host-kernel-marker-delivery: FAIL (checker evaluated {n_eval} ids, expected exactly {FLOOR_CHECKS}: a check family was lost or added without moving the floor)")
    sys.exit(1)
ok(f"checker evaluated exactly {n_eval} ids (floor {FLOOR_CHECKS})")

# ── 2. mutation battery ───────────────────────────────────────────────────────────────────────────────────────────────
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

SSH_TAIL = "-target=terraform_data.egress_gateway_web2 2>&1"
ENABLE_LINE = '  systemctl enable --now host-kernel-marker.timer || hkm_warn timer_enable "timer enable failed (#12007)"'
MUTANTS = [
    ("inngest: collector copy drifts one byte", on("inngest-bootstrap.sh", resub(r"(<<'HKMSCRIPTEOF'[^\n]*\n.*?)exit 0\n", r"\1exit 1\n")), ["I-script"]),
    ("inngest: unit loses --role inngest", on("inngest-bootstrap.sh", sub("host-kernel-marker.sh --role inngest", "host-kernel-marker.sh --role web")), ["I-service"]),
    ("inngest: unit loses OOMPolicy=continue (the service and its heredoc copy drift)", on("inngest-bootstrap.sh", sub("OOMPolicy=continue\n", "")), ["I-service"]),
    ("inngest: SyslogIdentifier changed", on("inngest-bootstrap.sh", resub(r"(<<'HKMUNITEOF'[^\n]*\n.*?)SyslogIdentifier=host-kernel-marker\n", r"\1SyslogIdentifier=host-kernel-markerX\n")), ["I-identifier", "I-service"]),
    ("inngest: timer cadence drifts", on("inngest-bootstrap.sh", resub(r"(<<'HKMTIMEREOF'[^\n]*\n.*?)OnBootSec=2min", r"\1OnBootSec=9min")), ["I-timer"]),
    ("inngest: install not gated on the dedicated host", on("inngest-bootstrap.sh", resub(r'(# host-kernel-marker:begin\n)if \[\[ "\$DOPPLER_PROJECT" == "soleur-inngest" \]\]; then', r"\1if true; then")), ["I-gated-on-dedicated-host"]),
    ("inngest: the timer enable is neutered to `: # <same text>` (trailing-comment mutant)", on("inngest-bootstrap.sh", sub(ENABLE_LINE, "  : # " + ENABLE_LINE.lstrip())), ["I-enable", "I-guarded-enable"]),
    ("inngest: the oneshot start is neutered to `: # <same text>` (trailing-comment mutant)", on("inngest-bootstrap.sh", sub("  systemctl start host-kernel-marker.service ||", "  : # systemctl start host-kernel-marker.service ||")), ["I-enable"]),
    ("inngest: the chmod is neutered to `: # <same text>` (trailing-comment mutant)", on("inngest-bootstrap.sh", sub('  chmod 0755 "$HKM_SCRIPT" ||', '  : # chmod 0755 "$HKM_SCRIPT" ||')), ["I-script-mode-0755", "I-guarded-writes"]),
    ("inngest: timer never enabled", on("inngest-bootstrap.sh", sub("systemctl enable --now host-kernel-marker.timer ||", "true ||")), ["I-enable", "I-guarded-enable"]),
    ("inngest: the timer enable is COMMENTED OUT (a whole-line comment must not satisfy the pin)", on("inngest-bootstrap.sh", sub(ENABLE_LINE, "  # " + ENABLE_LINE.lstrip())), ["I-enable", "I-guarded-enable", "I-reload-before-enable"]),
    ("inngest: the timer enable is unguarded under set -e", on("inngest-bootstrap.sh", sub(' || hkm_warn timer_enable "timer enable failed (#12007)"', "")), ["I-guarded-enable", "I-warn-call-sites"]),
    ("inngest: the oneshot start is unguarded under set -e", on("inngest-bootstrap.sh", sub(' || hkm_warn oneshot_start "oneshot non-zero (timer will retry in 6h)"', "")), ["I-enable", "I-warn-call-sites"]),
    ("inngest: unit gains a second --role web mention (the role rewrite is no longer a single swap)", on("service", lambda s: s + "# --role web\n"), ["I-service-has-role-web-once"]),
    ("inngest: collector not made executable", on("inngest-bootstrap.sh", sub('chmod 0755 "$HKM_SCRIPT"', 'chmod 0644 "$HKM_SCRIPT"')), ["I-script-mode-0755"]),
    ("inngest: collector write unguarded under set -e", on("inngest-bootstrap.sh", sub(' || hkm_warn write_script "collector write failed (#12007)"', "")), ["I-guarded-writes"]),
    ("inngest: chmod unguarded under set -e", on("inngest-bootstrap.sh", sub('chmod 0755 "$HKM_SCRIPT" || hkm_warn chmod_script "chmod failed (#12007)"', 'chmod 0755 "$HKM_SCRIPT"')), ["I-guarded-writes"]),
    ("inngest: daemon-reload unguarded under set -e", on("inngest-bootstrap.sh", sub(' || hkm_warn daemon_reload "daemon-reload failed (#12007)"', "")), ["I-guarded-reload"]),
    ("inngest: daemon-reload dropped", on("inngest-bootstrap.sh", resub(r"(# host-kernel-marker:begin\n.*?)systemctl daemon-reload", r"\1true")), ["I-reload-before-enable"]),
    ("inngest: the shipped logger line is dropped from the failure helper", on("inngest-bootstrap.sh", resub(r'    logger -t host-kernel-marker "HOST_KERNEL_MARKER_INSTALL_WARN step=\$1" \|\| true\n', "")), ["I-warn-logger"]),
    ("inngest: hkm_warn runs `log` BEFORE `logger` (a failing stderr write would exit the bootstrap before the off-box line)", on("inngest-bootstrap.sh", resub(r'(  hkm_warn\(\) \{\n)(    logger -t [^\n]*\n)(    log [^\n]*\n)', r"\1\3\2")), ["I-warn-logger"]),
    ("inngest: hkm_warn's `log` loses its '|| true' (a failing stderr write aborts the bootstrap)", on("inngest-bootstrap.sh", sub('host-kernel-marker $2" || true', 'host-kernel-marker $2"')), ["I-warn-logger"]),
    ("inngest: hkm_warn is defined BELOW its first use", on("inngest-bootstrap.sh", lambda s: (lambda m: s.replace(m.group(0), "", 1).replace("# host-kernel-marker:end", m.group(0) + "# host-kernel-marker:end", 1))(re.search(r"  hkm_warn\(\) \{\n.*?\n  \}\n", s, re.S))), ["I-warn-defined-before-use"]),
    ("inngest: the logger line loses its '|| true' (a missing logger would abort the bootstrap)", on("inngest-bootstrap.sh", sub('step=$1" || true', 'step=$1"')), ["I-warn-logger"]),
    ("inngest: the logger message becomes a SOLEUR_HOST_KERNEL row (a failed install would read as a kernel row)", on("inngest-bootstrap.sh", sub("HOST_KERNEL_MARKER_INSTALL_WARN step=", "SOLEUR_HOST_KERNEL v=1 step=")), ["I-warn-logger", "I-warn-not-a-marker"]),
    ("inngest: a failure path reverts to a bare log (not shipped)", on("inngest-bootstrap.sh", sub('|| hkm_warn timer_enable "timer enable failed (#12007)"', '|| log "warn: host-kernel-marker timer enable failed (#12007)"')), ["I-guarded-enable", "I-warn-call-sites"]),
    ("inngest: collector destination renamed (a second, unowned copy)", on("inngest-bootstrap.sh", sub('HKM_SCRIPT="/usr/local/bin/host-kernel-marker.sh"', 'HKM_SCRIPT="/usr/local/bin/host-kernel-marker2.sh"')), ["I-dest-sh-equals-web-installer"]),
    ("inngest: service destination renamed", on("inngest-bootstrap.sh", sub('HKM_UNIT="/etc/systemd/system/host-kernel-marker.service"', 'HKM_UNIT="/etc/systemd/system/host-kernel-marker2.service"')), ["I-dest-service-equals-web-installer"]),
    ("inngest: timer destination moved", on("inngest-bootstrap.sh", sub('HKM_TIMER="/etc/systemd/system/host-kernel-marker.timer"', 'HKM_TIMER="/run/systemd/system/host-kernel-marker.timer"')), ["I-dest-timer-equals-web-installer"]),
    ("web installer: the web-2 collector destination drifts from web-1's", on("server.tf", resub(r'(resource "terraform_data" "host_kernel_marker_install_web2" \{.*?destination\s*=\s*")/usr/local/bin/host-kernel-marker\.sh"', r'\1/usr/local/bin/hkm.sh"')), ["I-dest-web-pair-found"]),
    # R: the registry exemption is a ratchet. Each mutation is what the follow-up PR would do; it must go RED so flipping the exemption is deliberate.
    ("registry ratchet: the collector path appears in cloud-init-registry.yml", on("cloud-init-registry.yml", lambda s: s + "\n# /usr/local/bin/host-kernel-marker.sh\n"), ["R-exempt-no-collector-path"]),
    ("registry ratchet: the SOLEUR_HOST_KERNEL token appears in cloud-init-registry.yml", on("cloud-init-registry.yml", lambda s: s + "\n# SOLEUR_HOST_KERNEL\n"), ["R-exempt-no-marker-token"]),
    ("registry ratchet: a collector var appears in zot-registry.tf", on("zot-registry.tf", lambda s: s + "\n# host_kernel_marker_gz_b64\n"), ["R-exempt-render-inputs-untouched"]),
    ("registry ratchet: a collector var appears in the budget script", on("registry-userdata-budget.sh", lambda s: s + "\n# host_kernel_marker_gz_b64\n"), ["R-exempt-render-inputs-untouched"]),
    ("registry: the collector stops accepting --role registry", on("collector", sub("web | inngest | registry) :", "web | inngest) :")), ["R-collector-accepts-role-registry"]),
    ("registry: a hostname override is introduced", on("cloud-init-registry.yml", lambda s: s + "\npreserve_hostname: true\n"), ["Y-no-hostname-override"]),
    ("identity: helper id drifts", on("helper", sub("readonly REGISTRY_HOST_ID='soleur-registry'", "readonly REGISTRY_HOST_ID='soleur-registry2'")), ["Y-helper-id-equals-server-name", "Y-collector-id-constant-equals-helper-id", "Y-collector-host-equals-helper-id"]),
    ("identity: the collector's id constant drifts", on("collector", sub("readonly REGISTRY_HOST_ID='soleur-registry'", "readonly REGISTRY_HOST_ID='soleur-registry2'")), ["Y-collector-id-constant-equals-helper-id", "Y-collector-host-equals-helper-id"]),
    ("identity: server renamed", on("zot-registry.tf", resub(r'(resource "hcloud_server" "registry" \{\s*\n\s*name\s*=\s*"soleur-registry)"', r'\1-b"')), ["Y-helper-id-equals-server-name"]),
    ("apply: registry replace added to the per-merge apply job", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=hcloud_server.registry 2>&1")), ["A-hcloud_server.registry-in-no-per-merge-job"]),
    ("apply: inngest replace added to the per-merge apply job", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -replace=hcloud_server.inngest 2>&1")), ["A-hcloud_server.inngest-in-no-per-merge-job"]),
    ("apply: web-1 installer enters the SSH stage", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=terraform_data.host_kernel_marker_install 2>&1")), ["A-terraform_data.host_kernel_marker_install-in-no-target-list"]),
    ("apply: web-1 installer enters the SSH stage in the space form (-target addr)", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target terraform_data.host_kernel_marker_install 2>&1")), ["A-terraform_data.host_kernel_marker_install-in-no-target-list"]),
    ("apply: registry replace added to the per-merge apply job in the space form", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -replace hcloud_server.registry 2>&1")), ["A-hcloud_server.registry-in-no-per-merge-job"]),
    ("apply: web-2 installer enters the SSH stage", on("workflow", sub(SSH_TAIL, "-target=terraform_data.egress_gateway_web2 -target=terraform_data.host_kernel_marker_install_web2 2>&1")), ["A-terraform_data.host_kernel_marker_install_web2-in-no-target-list"]),
    ("apply: the dispatch jobs stop naming the registry (vacuity)", on("workflow", lambda s: s.replace("hcloud_server.registry'", "hcloud_server.registry_gone'")), ["A-hcloud_server.registry-named-by-a-dispatch-job"]),
    ("HARMLESS: comment appended to the helper", on("helper", lambda s: s + "\n# harmless\n"), []),
    ("HARMLESS: a whole-line comment added inside the inngest install block", on("inngest-bootstrap.sh", sub("# host-kernel-marker:end", "# a harmless extra comment mentioning systemctl enable --now host-kernel-marker.timer\n# host-kernel-marker:end")), []),
]

for label, mut, expect in MUTANTS:
    try:
        got = check(mut(real))
    except AssertionError as e:
        no(f"mutant '{label}': mutation did not land ({e}) -- fix the anchor, a vacuous mutant proves nothing")
        continue
    if not expect:
        (ok if not got else no)(f"mutant '{label}' is harmless: " + ("still passes" if not got else f"unexpectedly failed {got}"))
    elif all(e in got for e in expect):
        ok(f"mutant '{label}' killed by {expect}")
    else:
        no(f"mutant '{label}' NOT killed by {expect} (failing: {got})")

print(f"=== host-kernel-marker-delivery: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
PYEOF
