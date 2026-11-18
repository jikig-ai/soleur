#!/usr/bin/env python3
"""Lints for the bastion's rendered user_data and Terraform (#12866, Guards 2-4 and SHAPE).

Called by apps/web-platform/infra/bastion.test.sh. Each mode prints one violation per line and exits
0 when clean, 1 on violations, 2 when its inputs cannot be read (a harness fault, never a pass).

  egress  <render.yml> <bastion.tf>          Guard 2: every accept row cites a consumer on the host
                                             and has a closed shape (destination or sending user)
  emitter <render.yml>                       the comment-stripped runcmd sends fresh_boot_ready
  settle  <cloud-init.yml> <bastion.yml>     Guard 3: the ADR-326 blocks are the web hosts' bytes
  hostkey <render.yml> <pub> <priv-file>     Guard 4: the only host key is the Terraform key
  shape   <infra-dir> <repo-root>            SHAPE: firewall, IP, type, literals, push filters
"""
import base64
import ipaddress
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("HARNESS: PyYAML is required", file=sys.stderr)
    sys.exit(2)

# Consumers that exist on every bastion without a write_files entry: the base image's own units and
# the nftables package's unit. A citation outside this set and the render's own files/units is RED.
BASE_CONSUMERS = {"cloud-init", "systemd-resolved", "systemd-timesyncd", "systemd-networkd", "nftables.service"}
STRUCTURAL = [re.compile(r'^(iif|oif) "lo"$'), re.compile(r"^ct state established,related$")]
BASELINE = "/etc/soleur/bastion-nftables.conf"
# The one input accept that is not structural: the DHCP client's replies.
INPUT_OPEN = {"udp sport 67 udp dport 68"}
# Output accepts must name WHERE (ip daddr) or WHO (meta skuid); these shapes widen a row past what
# its qualifier says and are refused outright.
WIDENERS = [(re.compile(r"\b\d+\s*-\s*\d+\b"), "a port range"), (re.compile(r"!="), "a negation"),
            (re.compile(r"\bth\b"), "a transport-header (th) match"),
            (re.compile(r"\bnfproto\b|\bip6\b"), "an IPv6 match"), (re.compile(r"\bl4proto\b"), "an l4proto match")]
PRIVATE = [ipaddress.ip_network(n) for n in
           ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "0.0.0.0/8")]
METADATA_ROW = "meta skuid 0 ip daddr 169.254.169.254 tcp dport 80"
# Output accepts with no destination: exactly these, each pinned to the one daemon that needs it.
# Anything else must say where it goes, so no row can reach git-data:22 or the registry by omission.
USER_ONLY = {"meta skuid systemd-timesync udp dport 123", "meta skuid systemd-network udp sport 68 udp dport 67"}


def daddrs(match):
    """The literal addresses an `ip daddr` qualifier names ([] for a set reference, None if absent)."""
    m = re.search(r"\bip daddr\s+(\{[^}]*\}|@\S+|\S+)", match)
    if not m:
        return None
    v = m.group(1)
    if v.startswith("@"):
        return []
    return [a.strip() for a in v.strip("{}").split(",") if a.strip()]


def load_render(path):
    lines = open(path).read().splitlines()
    if lines and lines[0].lstrip().startswith("<<"):
        lines = lines[1:-1]
    body = "\n".join(lines)
    doc = yaml.safe_load(body)
    if not isinstance(doc, dict):
        raise ValueError("render is not a YAML mapping")
    return doc, body


def files_of(doc):
    out = {}
    for f in doc.get("write_files") or []:
        content = f.get("content", "")
        if f.get("encoding") in ("b64", "base64"):
            content = base64.b64decode(content).decode()
        out[f["path"]] = content
    return out


def tf_block(text, kind, name):
    m = re.search(r'^resource "%s" "%s" \{\n(.*?)^\}' % (re.escape(kind), re.escape(name)), text, re.M | re.S)
    return m.group(1) if m else None


def egress(render, tf_path):
    bad = []
    doc, _ = load_render(render)
    files = files_of(doc)
    tf = open(tf_path).read()
    consumers = set(BASE_CONSUMERS) | set(files)
    consumers |= {os.path.basename(p) for p in files if p.startswith("/etc/systemd/system/")}
    base = files.get(BASELINE)
    script = files.get("/usr/local/sbin/bastion-egress.sh")
    apt_cfg = doc.get("apt") if isinstance(doc.get("apt"), dict) else {}
    if any(p.startswith("/etc/apt/") for p in files) and apt_cfg.get("preserve_sources_list") is not True:
        bad.append("the render writes under /etc/apt/ without apt: {preserve_sources_list: true}; cc_apt_configure runs after write_files and regenerates ubuntu.sources from its http template")
    if "/etc/nftables.conf" in files:
        bad.append("the render writes /etc/nftables.conf, the nftables package's conffile (dpkg's conffile prompt kills apt_install); write %s" % BASELINE)
    if base is None:
        bad.append("baseline %s is absent from the render" % BASELINE)
        base = ""
    if script is None:
        bad.append("bastion-egress.sh is absent from the render")
        script = ""
    stmts = [l.strip() for l in base.splitlines() if l.strip() and not l.strip().startswith("#")]
    # The script's batch rows: `add ...` lines inside the BATCH string.
    stmts += [l.strip().replace('\\"', '"') for l in script.splitlines() if re.match(r'^\s*add (rule|set|element|chain|table) ', l)]
    rules = [s for s in stmts if s.startswith("add rule ")]
    if not rules:
        bad.append("0 rule rows checked")
    for s in stmts:
        if s.startswith(("add table", "add chain", "add rule", "add set", "add element")):
            fam = s.split()[2]
            if fam != "inet":
                bad.append("family is '%s', not inet: %s" % (fam, s))
    for chain in ("input", "output"):
        decl = [s for s in stmts if re.match(r"^add chain inet soleur_bastion %s \{" % chain, s)]
        if len(decl) != 1:
            bad.append("the %s chain is declared %d times (expected 1)" % (chain, len(decl)))
        elif not re.search(r"policy\s+drop\s*;", decl[0]):
            bad.append("the %s chain policy is not drop: %s" % (chain, decl[0]))
    md_drop = next((i for i, s in enumerate(rules) if re.search(r"output ip daddr 169\.254\.169\.254 drop\b", s)), None)
    if md_drop is None:
        bad.append("the output chain carries no ip daddr 169.254.169.254 drop row")
    for i, s in enumerate(rules):
        if not re.search(r"\baccept\b", s):
            continue
        m = re.search(r'\bcomment\s+"soleur-egress:\s*([^"]+?)\s*"', s)
        if not m:
            bad.append("accept row with no soleur-egress citation: %s" % s)
            continue
        if m.group(1) not in consumers:
            bad.append("accept row cites '%s', which the render does not install: %s" % (m.group(1), s))
        match = re.sub(r'\s+comment\s+".*"$', "", s)
        match = re.sub(r"^add rule inet soleur_bastion (input|output)\s+", "", match)
        match = re.sub(r"\s*\baccept\b\s*$", "", match).strip()
        match = re.sub(r"\s+", " ", match)
        structural = any(p.match(match) for p in STRUCTURAL)
        if not (re.search(r"\b[sd]port\b", match) or structural):
            bad.append("accept row matches no port (accept-all shape): %s" % s)
        if structural:
            continue
        if re.match(r"^add rule inet soleur_bastion input\b", s):
            if match not in INPUT_OPEN:
                bad.append("input accept row outside the closed set %s: %s" % (sorted(INPUT_OPEN), s))
            continue
        for rx, what in WIDENERS:
            if rx.search(match):
                bad.append("output accept row carries %s: %s" % (what, s))
        addrs = daddrs(match)
        if addrs is None and match not in USER_ONLY:
            bad.append("output accept row names no destination (ip daddr); only %s may rely on the sending user alone: %s" % (sorted(USER_ONLY), s))
        for a in addrs or []:
            try:
                net = ipaddress.ip_network(a, strict=False)
            except ValueError:
                bad.append("output accept row names an unparseable destination '%s': %s" % (a, s))
                continue
            if any(net.overlaps(n) for n in PRIVATE) and match != METADATA_ROW:
                bad.append("output accept row reaches a private, loopback or link-local destination %s: %s" % (a, s))
        if md_drop is not None and (i > md_drop) == (match == METADATA_ROW):
            bad.append("output accept row on the wrong side of the metadata drop (only the root-only metadata accept may precede it, directly): %s" % s)
    # Resolver allowlist rows (between ALLOW=' and the closing quote).
    m = re.search(r"^ALLOW='\n(.*?)^'", script, re.M | re.S)
    if script and not m:
        bad.append("bastion-egress.sh carries no ALLOW list")
    hosts = [l.split() for l in (m.group(1).splitlines() if m else []) if l.strip()]
    for row in hosts:
        if len(row) < 3 or row[1] != "soleur-egress:":
            bad.append("allowlist hostname without a soleur-egress citation: %s" % " ".join(row))
        elif row[2] not in consumers:
            bad.append("allowlist hostname %s cites '%s', which the render does not install" % (row[0], row[2]))
    if hosts and "/etc/systemd/system/bastion-egress.timer" not in files:
        bad.append("hostname rows remain but the refresh timer is not installed")
    if hosts and "/etc/systemd/system/bastion-egress.service" not in files:
        bad.append("hostname rows remain but bastion-egress.service is not installed")
    boot = " ".join(str(c) for c in (doc.get("bootcmd") or []))
    if not re.search(r"systemctl mask\b[^\n]*\bssh\.service\b", boot):
        bad.append("ssh.service is not masked in bootcmd")
    srv = tf_block(tf, "hcloud_server", "bastion")
    if srv is None:
        bad.append("hcloud_server.bastion is absent from bastion.tf")
    elif not re.search(r"^\s*ipv6_enabled\s*=\s*false\s*$", srv, re.M):
        bad.append("hcloud_server.bastion does not set ipv6_enabled = false")
    return bad


EMIT_READY = re.compile(r'^\s*_emit "soleur-cloud-init boot stage" fresh_boot_ready info\s*$')


def emitter(render):
    """The ready verdict is a live call in the rendered runcmd, after every check stage."""
    doc, _ = load_render(render)
    items = doc.get("runcmd") or []
    lines = [l for it in items for l in str(it).splitlines() if not l.strip().startswith("#")]
    hits = [i for i, l in enumerate(lines) if EMIT_READY.match(l)]
    if len(hits) != 1:
        return ["the comment-stripped runcmd carries %d live fresh_boot_ready _emit calls (expected 1)" % len(hits)]
    stages = [i for i, l in enumerate(lines) if re.match(r"^\s*STAGE=", l)]
    if stages and hits[0] < stages[-1]:
        return ["fresh_boot_ready is sent before the last STAGE= check (%s)" % lines[stages[-1]].strip()]
    return []


ANCHORS = ("STAGE=apt_update", "STAGE=apt_install")
PKG = re.compile(r"(apt-get install -y -o DPkg::Lock::Timeout=300) ([a-z0-9 .+-]+?);")


def settle_blocks(text):
    lines = text.splitlines()
    out = {}
    for a in ANCHORS:
        hits = [i for i, l in enumerate(lines) if l.strip() == a]
        out[a] = [lines[i] + "\n" + (lines[i + 1] if i + 1 < len(lines) else "") for i in hits]
    hits = [i for i, l in enumerate(lines) if l.strip() == "# ADR-326: one reboot onto the new kernel; runcmd re-runs."]
    blocks = []
    for i in hits:
        j = i + 1
        while j < len(lines) and lines[j] != "    fi":
            j += 1
        blocks.append("\n".join(lines[i:j + 1]))
    out["settle"] = blocks
    return out


def settle(web, bastion):
    bad = []
    w, b = settle_blocks(open(web).read()), settle_blocks(open(bastion).read())
    pkgs = None
    for k in list(ANCHORS) + ["settle"]:
        if len(w[k]) != 1:
            bad.append("cloud-init.yml carries %d '%s' blocks (expected 1)" % (len(w[k]), k))
            continue
        if len(b[k]) != 1:
            bad.append("bastion-cloud-init.yml carries %d '%s' blocks (expected 1)" % (len(b[k]), k))
            continue
        wb, bb = w[k][0], b[k][0]
        if k == "STAGE=apt_install":
            m = PKG.search(bb)
            pkgs = m.group(2).split() if m else []
            wb, bb = PKG.sub(r"\1 <pkgs>;", wb), PKG.sub(r"\1 <pkgs>;", bb)
        if wb != bb:
            bad.append("the '%s' block differs from cloud-init.yml's bytes: edit bastion-cloud-init.yml to match, then dispatch bastion-host-replace (#12879)" % k)
    if pkgs is not None and "linux-image-generic" not in pkgs:
        bad.append("linux-image-generic is not in the bastion's apt_install package list")
    return bad


def hostkey(render, pub, priv_file):
    bad = []
    doc, _ = load_render(render)
    keys = doc.get("ssh_keys")
    if not isinstance(keys, dict):
        return ["the ssh_keys block is absent (sshd would mint its own keys)"]
    extra = sorted(set(keys) - {"ed25519_private", "ed25519_public"})
    if extra:
        bad.append("ssh_keys carries other key types: %s" % ", ".join(extra))
    if str(keys.get("ed25519_public", "")).strip() != pub.strip():
        bad.append("the rendered ed25519_public is not the Terraform key's public half")
    if str(keys.get("ed25519_private", "")).strip() != open(priv_file).read().strip():
        bad.append("the rendered ed25519_private is not the Terraform key's private half")
    if doc.get("ssh_deletekeys") is not True:
        bad.append("ssh_deletekeys is not true")
    if "ssh_genkeytypes" in doc:
        bad.append("ssh_genkeytypes is set (keys other than the Terraform key could be generated)")
    return bad


def glob_re(pat):
    out, i = "", 0
    while i < len(pat):
        if pat.startswith("**", i):
            out += ".*"
            i += 2
            if i < len(pat) and pat[i] == "/":
                i += 1
        elif pat[i] == "*":
            out += "[^/]*"
            i += 1
        elif pat[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pat[i])
            i += 1
    return re.compile("^" + out + "$")


# The workflows a bastion merge is expected to wake; any other push-path filter matching a bastion
# file is RED. The first three are the plan's (Proposed Solution). validate-vector-config.yml was
# measured here (#12866): its `apps/web-platform/infra/*.sh` filter matches every infra shell file,
# and it runs validation only (vector validate plus test suites), so it changes no production state.
EXPECTED_WAKE = {"apply-web-platform-infra.yml", "infra-validation.yml", "web-platform-release.yml",
                 "validate-vector-config.yml"}
# Push-triggered with NO path filter, so they wake on every merge whatever it touches. Reviewed
# (#12866 review): each reads the tree (CI, CodeQL gate, merge audit, scanners, vendor pins,
# tenant integration tests) and none applies Terraform, pushes an image or deploys. A new one is RED
# until it is reviewed into this set, because nothing about its paths says what a merge wakes.
EVERY_PUSH = {"ci.yml", "codeql-main-alert-gate.yml", "merge-bypass-audit.yml", "secret-scan.yml",
              "skill-security-scan-corpus.yml", "skill-security-scan-postmerge.yml",
              "tenant-integration.yml", "vendor-pin-verify.yml"}
BASTION_FILES = [
    "apps/web-platform/infra/bastion.tf",
    "apps/web-platform/infra/bastion-cloud-init.yml",
    "apps/web-platform/infra/bastion-egress.sh",
    "apps/web-platform/infra/bastion.test.sh",
    "apps/web-platform/infra/lib/bastion-lint.py",
    "tests/scripts/lib/bastion-resources.txt",
    "tests/scripts/lib/bastion-host-birth-gate.sh",
    "tests/scripts/test-bastion-host-birth-gate.sh",
    "scripts/lib/bastion-boot-verify.sh",
    "tests/scripts/test-bastion-boot-verify.sh",
]


def shape(infra, root):
    bad = []
    tf = open(os.path.join(infra, "bastion.tf")).read()
    fw = tf_block(tf, "hcloud_firewall", "bastion")
    if fw is None:
        bad.append("hcloud_firewall.bastion is absent")
    elif re.search(r"^\s*rule\s*\{", fw, re.M):
        bad.append("hcloud_firewall.bastion carries a rule block (it must have zero inbound rules)")
    srv = tf_block(tf, "hcloud_server", "bastion") or ""
    if not srv:
        bad.append("hcloud_server.bastion is absent")
    if not re.search(r'^\s*server_type\s*=\s*"cx23"\s*$', srv, re.M):
        bad.append('hcloud_server.bastion server_type is not the literal "cx23" (F4)')
    if not re.search(r'architecture\s*==\s*"x86"', srv):
        bad.append("hcloud_server.bastion carries no x86 architecture precondition")
    if re.search(r"firewall_ids", srv):
        bad.append("hcloud_server.bastion sets firewall_ids inline")
    m = re.search(r'^\s*bastion_private_ip\s*=\s*"([0-9.]+)"', tf, re.M)
    if not m:
        bad.append("local.bastion_private_ip is not a literal in bastion.tf")
    else:
        ip = ipaddress.ip_address(m.group(1))
        net = ipaddress.ip_network("10.0.1.0/24")
        if ip not in net or not (2 <= int(str(ip).split(".")[3]) <= 254):
            bad.append("bastion_private_ip %s is not a host address in %s" % (ip, net))
        taken = set()
        for name in sorted(os.listdir(infra)):
            if not name.endswith(".tf") or name == "bastion.tf":
                continue
            t = open(os.path.join(infra, name)).read()
            taken |= set(re.findall(r'private_ip\s*=\s*"(10\.0\.1\.[0-9]+)"', t))
            taken |= set(re.findall(r'_private_ip\s*=\s*"(10\.0\.1\.[0-9]+)"', t))
            if name == "variables.tf":
                g = re.search(r'variable "grok_dogfood_private_ip" \{.*?default\s*=\s*"([0-9.]+)"', t, re.S)
                if g:
                    taken.add(g.group(1))
        if not taken:
            bad.append("no other host private IP was found to compare against (0 checked)")
        if str(ip) in taken:
            bad.append("bastion_private_ip %s collides with another host's private IP" % ip)
    # (The 10.0.1.10 / "web-N" literal ban is web-hosts-generic.test.sh's ratchet, repo-wide.)
    files, bad_list = bastion_files(root)
    bad += bad_list
    wf_dir = os.path.join(root, ".github", "workflows")
    checked = 0
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)  # ~15x faster over 4 MB of workflows
    for name in sorted(os.listdir(wf_dir)):
        if not name.endswith((".yml", ".yaml")) or name in EXPECTED_WAKE:
            continue
        try:
            w = yaml.load(open(os.path.join(wf_dir, name)), Loader=loader)
        except yaml.YAMLError as e:
            bad.append("%s does not parse, so its push filter cannot be read: %s" % (name, str(e).splitlines()[0]))
            continue
        on = (w or {}).get("on", (w or {}).get(True)) if isinstance(w, dict) else None
        if on == "push" or (isinstance(on, list) and "push" in on):
            on = {"push": None}
        if not isinstance(on, dict) or "push" not in on:
            continue
        push = on["push"] or {}
        if not isinstance(push, dict):
            continue
        checked += 1
        if push.get("tags") is not None and push.get("branches") is None and push.get("branches-ignore") is None:
            continue  # tag pushes only: a merge to main does not wake it
        pats, ign = push.get("paths"), push.get("paths-ignore")
        for rel in files:
            if pats is not None:
                pos = [p for p in pats if not p.startswith("!")]
                neg = [p[1:] for p in pats if p.startswith("!")]
                hit = any(glob_re(p).match(rel) for p in pos) and not any(glob_re(p).match(rel) for p in neg)
                why = "push path filter"
            elif ign is not None:
                hit = not any(glob_re(p).match(rel) for p in ign)
                why = "push paths-ignore filter (no ignore pattern covers it)"
            else:
                hit, why = name not in EVERY_PUSH, "push trigger with no path filter (not in the reviewed EVERY_PUSH set)"
            if hit:
                bad.append("%s's %s matches %s" % (name, why, rel))
    if checked == 0:
        bad.append("no workflow push trigger was read (0 checked)")
    return bad


def bastion_files(root):
    """The tracked code files named *bastion* (docs excluded), or the fixed list outside a checkout."""
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", "*bastion*"],
                             capture_output=True, check=True, timeout=30).stdout.decode()
    except (OSError, subprocess.SubprocessError):
        return BASTION_FILES, []
    tracked = sorted(p for p in out.split("\0") if p and not p.startswith(("knowledge-base/", "plugins/")))
    if not tracked:
        return BASTION_FILES, ["git ls-files found no *bastion* file under %s (0 checked)" % root]
    return tracked, []


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    mode, args = argv[1], argv[2:]
    try:
        if mode == "egress":
            bad = egress(*args)
        elif mode == "settle":
            bad = settle(*args)
        elif mode == "hostkey":
            bad = hostkey(args[0], open(args[1]).read(), args[2])
        elif mode == "shape":
            bad = shape(*args)
        elif mode == "emitter":
            bad = emitter(*args)
        else:
            print("HARNESS: unknown mode %s" % mode, file=sys.stderr)
            return 2
    except Exception as e:  # noqa: BLE001 — ANY crash is a harness fault (rc 2), never a RED (rc 1)
        print("HARNESS: %s: %s: %s" % (mode, type(e).__name__, e), file=sys.stderr)
        return 2
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
