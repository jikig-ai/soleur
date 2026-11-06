#!/usr/bin/env bash
# Delivery guard for the net.ipv4.ip_nonlocal_bind=1 host sysctl (#12167 PR-G).
#
# WHY IT EXISTS. The prod web container publishes its session-relay port on the host's Hetzner
# private address (`-p "${PROXY_BIND:-127.0.0.1}:8443:8443"`, ci-deploy.sh). That NIC is a
# post-boot hot attach (cloud-init.yml, RequiredForOnline=no) and nothing orders docker.service
# after it, so on reboot a publish on a not-yet-configured IP makes docker-proxy fail to bind and
# the WHOLE container (80/443/3000 too) fails to start. net.ipv4.ip_nonlocal_bind=1 lets
# docker-proxy bind the absent address; DNAT matches once the lease lands; source IPs are preserved.
#
# THE SAME ONE-LINE FILE REACHES THREE PLACES and they must not drift:
#   1. web-1 running host   terraform_data.nonlocal_bind_sysctl       (SSH, frozen cloud-init)
#   2. web-2 running host   terraform_data.nonlocal_bind_sysctl_web2  (SSH over the web-1 bastion forward)
#   3. fresh hosts          cloud-init.yml write_files (byte-identical copy, row-17c style)
# Both resources are `-target`ed in apply-web-platform-infra.yml's SSH stage (the same stage as the
# other *_web2 twins, e.g. journald_persistent_web2).
#
# The checker is a pure function over {file name -> text}; the mutation battery below feeds it
# corrupted copies and asserts WHICH check id fires (a bare non-zero exit would credit a crash).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
INFRA="${SOLEUR_INFRA_DIR:-$ROOT/apps/web-platform/infra}"
WORKFLOW="${SOLEUR_APPLY_WORKFLOW:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"

python3 - "$INFRA" "$WORKFLOW" <<'PYEOF'
import os, re, sys

INFRA, WORKFLOW = sys.argv[1], sys.argv[2]
CONF = "99-soleur-nonlocal-bind.conf"
DEST = "/etc/sysctl.d/99-soleur-nonlocal-bind.conf"
KEYLINE = "net.ipv4.ip_nonlocal_bind=1"

def read(p):
    with open(p) as f: return f.read()

def load():
    return {
        CONF: read(os.path.join(INFRA, CONF)) if os.path.exists(os.path.join(INFRA, CONF)) else None,
        "server.tf": read(os.path.join(INFRA, "server.tf")),
        "cloud-init.yml": read(os.path.join(INFRA, "cloud-init.yml")),
        "workflow": read(WORKFLOW),
    }

def tf_block(tf, name):
    """Brace-balanced body of resource "terraform_data" "<name>" (full-line comments stripped)."""
    tf = "\n".join(l for l in tf.split("\n") if not l.lstrip().startswith("#"))
    m = re.search(r'resource\s+"terraform_data"\s+"' + re.escape(name) + r'"\s*\{', tf)
    if not m: return None
    i, depth = m.end(), 1
    while i < len(tf) and depth:
        depth += {"{": 1, "}": -1}.get(tf[i], 0); i += 1
    return tf[m.end():i - 1]

def inline_cmds(block):
    out = []
    for arr in re.findall(r'inline\s*=\s*\[(.*?)\n\s*\]', block, re.S):
        out.append(re.findall(r'"((?:[^"\\]|\\.)*)"', arr))
    return out

def check(files):
    """Return the list of failing check ids."""
    bad = []
    conf = files[CONF]
    # ── C: the repo source file ──────────────────────────────────────────────────────────
    if conf is None:
        bad.append("C-exists")
    else:
        live = [l for l in conf.split("\n") if l.strip() and not l.lstrip().startswith("#")]
        if live != [KEYLINE]: bad.append("C-key")
        if not conf.endswith("\n") or conf.endswith("\n\n"): bad.append("C-eol")
    # ── R: the two SSH resources ─────────────────────────────────────────────────────────
    for tag, name, host, hk in (("R1", "nonlocal_bind_sysctl", "web-1", "web_1_ssh_host_key"),
                                ("R2", "nonlocal_bind_sysctl_web2", "web-2", "web_2_ssh_host_key")):
        b = tf_block(files["server.tf"], name)
        if b is None:
            bad.append(f"{tag}-exists"); continue
        if not (re.search(r'host\s*=\s*hcloud_server\.web\["' + host + r'"\]\.ipv4_address', b)
                and re.search(r'host_key\s*=\s*local\.' + hk + r'\b', b)
                and 'type        = "ssh"' in b):
            bad.append(f"{tag}-host")
        if re.search(r'^\s*(for_each|count)\s*=', b, re.M): bad.append(f"{tag}-fanout")
        if not (re.search(r'config_hash\s*=\s*sha256\([^)]*file\("\$\{path\.module\}/' + re.escape(CONF) + r'"\)', b, re.S)
                and re.search(r'server_id\s*=\s*hcloud_server\.web\["' + host + r'"\]\.id', b)):
            bad.append(f"{tag}-trigger")
        fp = re.search(r'provisioner\s+"file"\s*\{(.*?)\n  \}', b, re.S)
        if not (fp and 'source      = "${path.module}/' + CONF + '"' in fp.group(1)
                and 'destination = "' + DEST + '"' in fp.group(1)):
            bad.append(f"{tag}-file")
        execs = inline_cmds(b)
        flat = "\n".join(c for cmds in execs for c in cmds)
        if not execs or any(not c or c[0] != "set -e" for c in execs):
            bad.append(f"{tag}-set-e")
        if not (f"chmod 0644 {DEST}" in flat and f"chown root:root {DEST}" in flat):
            bad.append(f"{tag}-perm")
        if not re.search(r'(^|\n)sysctl -w net\.ipv4\.ip_nonlocal_bind=1(\n|$)', flat):
            bad.append(f"{tag}-apply")
        # Verification must READ the live value back and fail loudly (exit 1 + FATAL) if it is not 1.
        if not re.search(r'sysctl -n net\.ipv4\.ip_nonlocal_bind\)\\" = \'1\'.*FATAL.*exit 1', flat):
            bad.append(f"{tag}-verify")
        if f"grep -qx '{KEYLINE}' {DEST}" not in flat:
            bad.append(f"{tag}-persist")
        if tag == "R2" and not re.search(r'script_path\s*=\s*"[^"]*%RAND%[^"]*"', b):
            bad.append("R2-script-path")
    # ── CI: cloud-init write_files copy, byte-identical (row-17c style) ──────────────────
    ci = files["cloud-init.yml"]
    m = re.search(r'^  - path: ' + re.escape(DEST) + r'\n((?:    .*\n|\n)*)', ci, re.M)
    if not m:
        bad.append("CI-entry")
    else:
        ent = m.group(1)
        if "    owner: root:root\n" not in ent or "    permissions: '0644'\n" not in ent:
            bad.append("CI-perm")
        cm = re.search(r'^    content: \|\n((?:      .*\n|\n)+)', ent, re.M)
        if not cm:
            bad.append("CI-content")
        else:
            body = "".join((l[6:] if l.startswith("      ") else l) for l in cm.group(1).splitlines(True))
            if conf is None or body != conf: bad.append("CI-parity")
            if "${" in body or "%{" in body: bad.append("CI-interp")
    # first boot: write_files lands after the sysinit sysctl pass, so cloud-init must load it itself
    if not re.search(r'^  - sysctl -p ' + re.escape(DEST) + r'$', ci, re.M): bad.append("CI-load")
    # ── W: the apply workflow's SSH stage targets both resources ─────────────────────────
    wf = files["workflow"]
    sm = re.search(r'- name: Terraform apply \(SSH-provisioned resources, over the bridge\)(.*?)\n      - name:', wf, re.S)
    stage = sm.group(1) if sm else ""
    for tag, name in (("W1", "nonlocal_bind_sysctl"), ("W2", "nonlocal_bind_sysctl_web2")):
        if not re.search(r'^\s*-target=terraform_data\.' + name + r'(\s|\\|$)', stage, re.M):
            bad.append(f"{tag}-target")
    return bad

# ── real tree ───────────────────────────────────────────────────────────────────────────
npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

real = load()
bad = check(real)
if not bad: ok("real tree: file, web-1 + web-2 resources, cloud-init copy and workflow targets all conform")
else: no(f"real tree: failing checks {bad}")

# ── mutation battery: WHICH check fires, per mutation ──────────────────────────────────
def res_mut(name, fn):
    def go(f):
        t = f["server.tf"]
        m = re.search(r'resource\s+"terraform_data"\s+"' + name + r'"\s*\{', t)
        if not m: return f
        i, depth = m.end(), 1
        while i < len(t) and depth:
            depth += {"{": 1, "}": -1}.get(t[i], 0); i += 1
        g = dict(f); g["server.tf"] = t[:m.start()] + fn(t[m.start():i]) + t[i:]
        return g
    return go

def sub(old, new, count=1):
    def fn(s):
        assert old in s, f"mutation anchor missing: {old!r}"
        return s.replace(old, new, count)
    return fn

def on(key, fn):
    def go(f):
        g = dict(f); g[key] = fn(f[key]); return g
    return go

R1, R2 = "nonlocal_bind_sysctl", "nonlocal_bind_sysctl_web2"
VERIFY = "sysctl -n net.ipv4.ip_nonlocal_bind"
MUTANTS = [
    # (label, mutation, expected ids that MUST be among the failures; [] = harmless)
    ("conf: wrong sysctl name",            on(CONF, sub("ip_nonlocal_bind=1", "ip_nonlocal_bindx=1")), ["C-key", "CI-parity"]),
    ("conf: value 0",                      on(CONF, sub("ip_nonlocal_bind=1", "ip_nonlocal_bind=0")), ["C-key", "CI-parity"]),
    ("conf: file missing",                 on(CONF, lambda s: None), ["C-exists"]),
    ("conf: second sysctl smuggled in",    on(CONF, lambda s: s + "net.ipv4.ip_forward=1\n"), ["C-key"]),
    ("web-1: wrong sysctl name in -w",     res_mut(R1, sub("sysctl -w net.ipv4.ip_nonlocal_bind=1", "sysctl -w net.ipv4.ip_nonlocal_bindx=1")), ["R1-apply"]),
    ("web-1: value 0 in -w",               res_mut(R1, sub("sysctl -w net.ipv4.ip_nonlocal_bind=1", "sysctl -w net.ipv4.ip_nonlocal_bind=0")), ["R1-apply"]),
    ("web-2: wrong sysctl name in -w",     res_mut(R2, sub("sysctl -w net.ipv4.ip_nonlocal_bind=1", "sysctl -w net.ipv4.ip_nonlocal_bindx=1")), ["R2-apply"]),
    ("web-2: value 0 in -w",               res_mut(R2, sub("sysctl -w net.ipv4.ip_nonlocal_bind=1", "sysctl -w net.ipv4.ip_nonlocal_bind=0")), ["R2-apply"]),
    ("web-1: file never written",          res_mut(R1, sub('provisioner "file"', 'provisioner "local-exec"')), ["R1-file"]),
    ("web-1: destination moved",           res_mut(R1, sub('destination = "' + DEST + '"', 'destination = "/tmp/99-soleur-nonlocal-bind.conf"')), ["R1-file"]),
    ("web-2: file never written",          res_mut(R2, sub('provisioner "file"', 'provisioner "local-exec"')), ["R2-file"]),
    ("web-2: destination moved",           res_mut(R2, sub('destination = "' + DEST + '"', 'destination = "/tmp/99-soleur-nonlocal-bind.conf"')), ["R2-file"]),
    ("web-1: verification removed",        res_mut(R1, sub(VERIFY, "true")), ["R1-verify"]),
    ("web-1: verification not fatal",      res_mut(R1, sub("exit 1", "true")), ["R1-verify"]),
    ("web-2: verification removed",        res_mut(R2, sub(VERIFY, "true")), ["R2-verify"]),
    ("web-1: persisted-file check removed", res_mut(R1, sub("grep -qx", "true")), ["R1-persist"]),
    ("web-1: set -e dropped",              res_mut(R1, sub('"set -e",', '"true",')), ["R1-set-e"]),
    ("web-1: mode 0600",                   res_mut(R1, sub("chmod 0644", "chmod 0600")), ["R1-perm"]),
    ("web-2: not owned by root",           res_mut(R2, sub("chown root:root", "chown nobody:nobody")), ["R2-perm"]),
    ("web-1: trigger no longer hashes the file", res_mut(R1, sub('file("${path.module}/' + CONF + '")', '"x"')), ["R1-trigger"]),
    ("web-1: server_id fold-in dropped",   res_mut(R1, sub('hcloud_server.web["web-1"].id', '"x"')), ["R1-trigger"]),
    ("web-2: dials web-1",                 res_mut(R2, sub('hcloud_server.web["web-2"].ipv4_address', 'hcloud_server.web["web-1"].ipv4_address')), ["R2-host"]),
    ("web-2: wrong host key",              res_mut(R2, sub("local.web_2_ssh_host_key", "local.web_1_ssh_host_key")), ["R2-host"]),
    ("web-2: fixed script_path",           res_mut(R2, sub("web2-%RAND%", "web2-fixed")), ["R2-script-path"]),
    ("web-1 resource removed",             on("server.tf", lambda s: s.replace('resource "terraform_data" "nonlocal_bind_sysctl" {', 'resource "terraform_data" "renamed_away" {')), ["R1-exists"]),
    ("cloud-init: entry removed",          on("cloud-init.yml", lambda s: s.replace("- path: " + DEST, "- path: /etc/sysctl.d/99-other.conf")), ["CI-entry"]),
    ("cloud-init: content drifted",        on("cloud-init.yml", sub("ip_nonlocal_bind=1", "ip_nonlocal_bind=0")), ["CI-parity"]),
    ("cloud-init: first-boot load dropped", on("cloud-init.yml", sub("  - sysctl -p " + DEST + "\n", "")), ["CI-load"]),
    ("cloud-init: wrong mode",             on("cloud-init.yml", lambda s: re.sub(r"(path: " + re.escape(DEST) + r"\n(?:    .*\n)*?    permissions: )'0644'", r"\1'0666'", s)), ["CI-perm"]),
    ("workflow: web-1 target removed",     on("workflow", lambda s: re.sub(r"^\s*-target=terraform_data\.nonlocal_bind_sysctl \\\n", "", s, flags=re.M)), ["W1-target"]),
    ("workflow: web-2 target removed",     on("workflow", lambda s: re.sub(r"^\s*-target=terraform_data\.nonlocal_bind_sysctl_web2 \\\n", "", s, flags=re.M)), ["W2-target"]),
    ("HARMLESS: comment edit in server.tf", on("server.tf", lambda s: s + "\n# harmless trailing comment\n"), []),
    ("DRIFT: conf comment edited without the cloud-init copy",  on(CONF, lambda s: s.replace("Terraform-managed", "Terraform-managed (edited)")), ["CI-parity"]),
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
        ok(f"mutant '{label}' killed by {[e for e in expect]}")
    else:
        no(f"mutant '{label}' NOT killed by {expect} (failing: {got})")

print(f"=== nonlocal-bind-sysctl: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
PYEOF
