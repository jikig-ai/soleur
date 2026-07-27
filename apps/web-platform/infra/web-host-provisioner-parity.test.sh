#!/usr/bin/env bash
# Web-host provisioner DUAL-DELIVERY parity guard (#7000).
#
# WHAT THIS PINS. server.tf carries 15 `terraform_data` host provisioners whose SSH
# `connection` is pinned to `hcloud_server.web["web-1"]`. That pinning is DELIBERATE
# (server.tf, the hcloud_server.web comment: the SSH provisioners stay web-1-scoped so a
# web-2 that is not yet SSH-reachable never hangs the merge-triggered auto-apply) and is
# NOT a bug to be fixed by fanning them out over var.web_hosts:
#
#   * CI can SSH exactly ONE host. outputs.tf's `server_ip` is web-1's address, the
#     cf-tunnel-ssh-bridge installs a single iptables NAT rule for it, and the tunnel
#     connector is web-1-only by construction (ADR-114 I1). web-2's public :22 is
#     firewalled to var.admin_ips, which the non-static GH runner egress is not in.
#   * apply-web-platform-infra.yml `-target=`s these resources by bare address, and a
#     bare -target hits EVERY for_each instance — so a fan-out would make every merge
#     dial web-2:22 from CI, hang to the SSH timeout, and fail the apply.
#   * ADR-143 / #6459 Phase 5 REMOVES these SSH provisioners once web-1 is cattle. It
#     does not extend them. fresh-boot-parity.test.sh §6/§13 already pin that retention.
#
# So web-2 is NOT wired by SSH — it is wired at BIRTH by the image bake
# (local.host_script_files -> soleur-host-bootstrap.sh) plus cloud-init.yml. That is the
# cattle model (hr-prod-host-config-change-immutable-redeploy): a running cattle host is
# immutable and a config change reaches it by rebuild, not by mutation.
#
# THE ACTUAL RISK, and the one this guard closes. Because the two delivery paths are
# INDEPENDENT, an artifact can be added to (or changed in) the web-1 SSH path without a
# matching change on the fresh-boot path. Nothing then fails: web-1 gets it, CI is green,
# and web-2 silently comes up WITHOUT it on its next rebuild. Before this guard, 10 of the
# 15 provisioners had no suite pinning that correspondence at all, and 5
# (disk_monitor_install, resource_monitor_install, container_restart_monitor_install,
# cosign_trusted_root, apparmor_bwrap_profile) were named by no suite whatsoever.
#
# The invariant, therefore, is NOT "these resources are for_each'd". It is:
#
#     EVERY artifact an SSH provisioner delivers to web-1 has a fresh-boot counterpart
#     that delivers the SAME artifact to a fresh cattle host.
#
# Complements fresh-boot-parity.test.sh, which pins the 5 Phase-2.2 resources deeply
# (byte-identity of unit bodies, env-file key-set parity). This guard is the BREADTH
# half: it sweeps all 15 and every artifact each one delivers, so a NEW artifact added to
# any SSH provisioner cannot land without a fresh-boot counterpart. Deliberately overlaps
# rather than assuming the other suite ran.
#
# Delivery channels enumerated (all four that server.tf actually uses):
#   1. provisioner "file" { source = "${path.module}/X" }  -> X must be baked or in cloud-init
#   2. remote-exec heredoc `cat > DEST << 'MARK'`          -> DEST must have a counterpart,
#                                                             and if that counterpart is a
#                                                             cloud-init write_files entry the
#                                                             BODIES must be byte-identical
#   3. provisioner "file" { content = <rendered> }         -> reviewed COVERAGE table
#   4. remote-exec printf / base64 -d > DEST               -> reviewed COVERAGE table
#
# Every section carries a NON-VACUITY FLOOR: a parse that silently matches nothing must
# fail loudly rather than report a clean sweep of an empty set.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
# SOLEUR_INFRA_DIR overrides the analysed directory so this guard's own logic can be
# mutation-tested against a sandbox copy in under a second (same rationale as
# run-registered-suites.sh's INFRA_WF override). CI never sets it, so the default is the
# real tree. A guard whose correctness could only be checked by hand-editing prod HCL
# would not, in practice, be checked -- see web-host-provisioner-parity-mutation.test.sh.
INFRA="${SOLEUR_INFRA_DIR:-$ROOT/apps/web-platform/infra}"

for f in server.tf cloud-init.yml web-probe-envwrite.sh; do
  [[ -f "$INFRA/$f" ]] || { echo "FATAL: $INFRA/$f not found" >&2; exit 2; }
done

# The analysis is parse-heavy (HCL heredoc bodies, cloud-init write_files blocks), so it
# lives in python3 -- the same choice journald-config.test.sh, registry-insecure-config.test.sh
# and web-git-data-probe.test.sh already make. python3 is base on ubuntu-24.04, the runner
# `deploy-script-tests` uses. Emits `[ok] …` / `[FAIL] …`; exit status is the verdict.
python3 - "$INFRA" <<'PYEOF'
import os, re, sys

INFRA = sys.argv[1]
srv = open(os.path.join(INFRA, "server.tf")).read()
ci  = open(os.path.join(INFRA, "cloud-init.yml")).read()
envwriter = open(os.path.join(INFRA, "web-probe-envwrite.sh")).read()

npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

# ── Web-1-only ALLOWLIST ─────────────────────────────────────────────────────────────
# An artifact that is LEGITIMATELY web-1-only goes here, keyed by artifact, valued by the
# reason. Deliberately EMPTY: as measured at #7000, every artifact all 15 provisioners
# deliver does have a fresh-boot counterpart, so nothing needs an exception today. Adding
# an entry is therefore a visible, reviewable diff that must carry a stated reason -- which
# is the point. An entry with an empty reason is rejected below.
ALLOWLIST: dict[str, str] = {}

for art, reason in ALLOWLIST.items():
    if not reason.strip():
        no(f"0: allowlist entry {art!r} has no stated reason")
if all(r.strip() for r in ALLOWLIST.values()):
    ok(f"0: allowlist well-formed ({len(ALLOWLIST)} entries, every one carries a reason)")

# ── Parse local.host_script_files (the image bake set) ────────────────────────────────
# Parsed from the COMMENT-STRIPPED source (see strip_comments below): the bake list carries
# 46 comment lines, one of which contains the literal `provisioner "file"` in prose. Parsing
# raw picks `file` up as a 46th "baked filename", so an SSH provisioner delivering a file
# actually named `file` would have falsely passed §2 -- a guard satisfied by a paragraph.
def _strip_comments(text):
    return '\n'.join(L for L in text.split('\n') if not L.lstrip().startswith('#'))

m = re.search(r'host_script_files = \[(.*?)\n  \]', _strip_comments(srv), re.S)
if not m:
    no("0: could not parse local.host_script_files from server.tf -- fix the extraction, "
       "do not trust this run")
    print(f"=== web-host-provisioner-parity: {npass} passed, {nfail} failed ===")
    sys.exit(1)
baked = set(re.findall(r'"([^"]+)"', m.group(1)))
if len(baked) >= 40:
    ok(f"0: parsed local.host_script_files ({len(baked)} baked files)")
else:
    no(f"0: local.host_script_files parsed to only {len(baked)} files (floor 40) -- "
       "extraction is probably broken")

# ── Parse cloud-init write_files paths + bodies ───────────────────────────────────────
def parse_write_files(text):
    out = {}
    for wm in re.finditer(r'- path: (\S+)\n(.*?)(?=\n  - path: |\n[a-z_]+:\n)', text, re.S):
        path, body = wm.group(1), wm.group(2)
        cm = re.search(r'content: \|\n(.*)', body, re.S)
        if not cm:
            out.setdefault(path, None)
            continue
        lines, acc = cm.group(1).split('\n'), []
        for L in lines:
            if L.strip() == '':
                acc.append('')
            elif L.startswith('      '):
                acc.append(L[6:])
            else:
                break
        while acc and acc[-1] == '':
            acc.pop()
        out[path] = '\n'.join(acc)
    return out

wf = parse_write_files(ci)
if len(wf) >= 10:
    ok(f"0: parsed cloud-init write_files ({len(wf)} paths)")
else:
    no(f"0: cloud-init write_files parsed to only {len(wf)} paths (floor 10) -- "
       "extraction is probably broken")

# ── §1. Enumerate the SSH-connected terraform_data resources ─────────────────────────
# COMMENTS ARE STRIPPED FIRST. server.tf's infra_config_handler_bootstrap rationale contains
# the literal `connection{type="ssh"}` in prose, and every artifact regex below (`type =`,
# `source =`, `printf … >`) would match such prose just as happily as real HCL. That is the
# cq-assert-anchor-not-bare-token trap: a guard that reads a comment as configuration can be
# satisfied -- or inflated past its own floor -- by a paragraph. Full-line comments only:
# HCL `#` starts a line comment, and trailing comments sit after real config on their line,
# so dropping lstrip-starts-with-# lines removes the prose without touching any attribute.
srv_code = _strip_comments(srv)

blocks = re.split(r'\n(?=resource "terraform_data" ")', srv_code)
ssh_resources = {}
for b in blocks:
    rm = re.match(r'resource "terraform_data" "([a-z_0-9]+)"', b)
    if not rm:
        continue
    # `type = "ssh"` inside a connection block, fmt-aligned (terraform fmt re-aligns `=`,
    # so match whitespace-tolerantly -- a single-space pattern would blind this guard the
    # moment the block gains an attribute). Anchored to a `connection {` block so a `type`
    # attribute belonging to some other nested block cannot be read as an SSH connection.
    if re.search(r'connection\s*\{[^}]*?\btype\s*=\s*"ssh"', b, re.S):
        ssh_resources[rm.group(1)] = b

FLOOR_RESOURCES = 15
if len(ssh_resources) >= FLOOR_RESOURCES:
    ok(f"1: swept {len(ssh_resources)} SSH-connected terraform_data resources "
       f"(floor {FLOOR_RESOURCES})")
else:
    no(f"1: swept only {len(ssh_resources)} SSH-connected terraform_data resources "
       f"(floor {FLOOR_RESOURCES}) -- a provisioner was removed, or the extraction broke. "
       "Removing one is a Phase-5 change (ADR-143), not an incidental edit.")

# Every one of them must be host-pinned to web-1 (the deliberate scoping this guard
# documents). If a future change DOES fan one out over var.web_hosts, this fails and
# forces the CI-reachability question above to be answered first.
pinned = [n for n, b in ssh_resources.items()
          if re.search(r'host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address', b)]
if len(pinned) == len(ssh_resources):
    ok(f"1: all {len(pinned)} SSH provisioners are host-pinned to web-1 "
       "(CI can SSH exactly one host -- see header)")
else:
    unpinned = sorted(set(ssh_resources) - set(pinned))
    no(f"1: SSH provisioners not pinned to web-1: {unpinned}. A for_each fan-out makes "
       "every merge-triggered apply dial a host CI has no SSH route to. If this is "
       "intentional, the tunnel connector + firewall + -target list must change FIRST.")

# ── §2. provisioner "file" { source = … } -> must be baked or present in cloud-init ───
n_sources = 0
for name, b in ssh_resources.items():
    for src_file in re.findall(r'source\s*=\s*"\$\{path\.module\}/([^"]+)"', b):
        n_sources += 1
        if src_file in ALLOWLIST:
            continue
        if src_file in baked:
            continue
        if src_file in ci:
            continue
        no(f"2: {name} SSH-delivers {src_file!r} but it is NOT in local.host_script_files "
           "and is not referenced by cloud-init.yml -- a fresh cattle host (web-2) would "
           "come up without it. Bake it, or add it to ALLOWLIST with a reason.")

FLOOR_SOURCES = 30
if n_sources >= FLOOR_SOURCES:
    ok(f"2: swept {n_sources} `provisioner \"file\"` sources, every one has a fresh-boot "
       f"counterpart (floor {FLOOR_SOURCES})")
else:
    no(f"2: swept only {n_sources} `provisioner \"file\"` sources (floor {FLOOR_SOURCES}) "
       "-- the extraction is probably broken; a clean sweep of nothing is not coverage")

# ── §3. remote-exec heredocs -> destination must have a fresh-boot counterpart ────────
heredocs = []   # (resource, dest, marker)
for name, b in ssh_resources.items():
    for dest, marker in re.findall(r"cat > (\S+) << '([A-Z]+)'", b):
        heredocs.append((name, dest, marker))

for name, dest, _marker in heredocs:
    base = os.path.basename(dest)
    if dest in ALLOWLIST or base in ALLOWLIST:
        continue
    if base in baked:          # delivered fresh-boot as a baked repo file
        continue
    if dest in wf:             # delivered fresh-boot by cloud-init write_files
        continue
    no(f"3: {name} heredoc-writes {dest} but no fresh-boot counterpart exists "
       f"(no baked {base!r}, no cloud-init write_files entry) -- web-2 comes up without it.")

FLOOR_HEREDOCS = 7
if len(heredocs) >= FLOOR_HEREDOCS:
    ok(f"3: swept {len(heredocs)} remote-exec heredoc destinations, every one has a "
       f"fresh-boot counterpart (floor {FLOOR_HEREDOCS})")
else:
    no(f"3: swept only {len(heredocs)} heredoc destinations (floor {FLOOR_HEREDOCS}) -- "
       "extraction is probably broken")

# ── §4. BYTE-IDENTITY where both paths carry their own copy of the body ──────────────
# A heredoc whose counterpart is a cloud-init write_files entry means the SAME unit body
# is written out TWICE, in two files, in two encodings. That is the drift shape with no
# compiler behind it: web-1 and web-2 would run different units and nothing would say so.
# (Heredocs whose counterpart is a BAKED repo file are byte-identical by construction --
# fresh-boot-parity.test.sh §5 pins those separately.)
n_identity = 0
for name, dest, marker in heredocs:
    if dest not in wf or wf[dest] is None:
        continue
    hm = re.search(r'"cat > ' + re.escape(dest) + r" << '" + marker + r"'\\n(.*?)\\n"
                   + marker + r'"', srv_code)
    if not hm:
        no(f"4: could not extract the {dest} heredoc body from server.tf -- fix the "
           "extraction rather than trusting this run")
        continue
    n_identity += 1
    if hm.group(1).replace('\\n', '\n').strip() == wf[dest].strip():
        ok(f"4: {dest} body identical across server.tf heredoc and cloud-init write_files")
    else:
        no(f"4: {dest} DRIFTED -- the server.tf heredoc body and the cloud-init "
           "write_files body differ, so web-1 and web-2 run different units.")

FLOOR_IDENTITY = 4
if n_identity >= FLOOR_IDENTITY:
    ok(f"4: byte-identity checked on {n_identity} dual-written bodies "
       f"(floor {FLOOR_IDENTITY})")
else:
    no(f"4: byte-identity checked on only {n_identity} bodies (floor {FLOOR_IDENTITY}) -- "
       "extraction is probably broken")

# ── §5. Rendered / env-file destinations (content= and printf/base64) ────────────────
# These carry INTERPOLATED values, so there is no file to compare. Each is claimed here
# against the channel that covers it on a fresh host, and the claim is then VERIFIED --
# an unverified table would just be a comment.
#   write_files : cloud-init.yml write_files entry for that exact path
#   inline      : cloud-init.yml writes the path from a runcmd/inline block
#   envwriter   : the baked web-probe-envwrite.sh writes it (key-set parity for these
#                 three is pinned separately by fresh-boot-parity.test.sh §12)
COVERAGE = {
    "/etc/default/disk-monitor":              ("write_files", "cloud-init seeds RESEND_API_KEY at boot"),
    "/etc/default/resource-monitor":          ("write_files", "cloud-init seeds RESEND_API_KEY at boot"),
    "/etc/default/container-restart-monitor": ("write_files", "cloud-init seeds RESEND_API_KEY at boot"),
    "/etc/default/web-private-nic-guard":     ("envwriter",   "baked web-probe-envwrite.sh, invoked by cloud-init with per-host inputs"),
    "/etc/default/web-zot-consumer-probe":    ("envwriter",   "baked web-probe-envwrite.sh, invoked by cloud-init with per-host inputs"),
    "/etc/default/web-git-data-probe":        ("envwriter",   "baked web-probe-envwrite.sh, invoked by cloud-init with per-host inputs"),
    "/etc/docker/daemon.json":                ("inline",      "cloud-init writes daemon.json inline, same local.registry_endpoint source"),
    "/etc/webhook/hooks.json":                ("inline",      "cloud-init renders the baked hooks.json.tmpl with the secret at boot"),
}

rendered = set()
for name, b in ssh_resources.items():
    for dest in re.findall(r'content\s*=\s*.*\n\s*destination = "([^"]+)"', b):
        rendered.add(dest)
    for dest in re.findall(r'printf .*?> (/[^\s")]+)', b):
        rendered.add(dest)
    for dest in re.findall(r'base64 -d > (/[^\s")]+)', b):
        rendered.add(dest)

for dest in sorted(rendered):
    if dest in ALLOWLIST:
        continue
    if dest not in COVERAGE:
        no(f"5: {dest} is written by an SSH provisioner but is absent from the COVERAGE "
           "table -- state which fresh-boot channel delivers it to web-2, or ALLOWLIST it.")
        continue
    channel, _reason = COVERAGE[dest]
    if channel == "write_files":
        if dest in wf:
            ok(f"5: {dest} covered fresh-boot by cloud-init write_files")
        else:
            no(f"5: {dest} claims write_files coverage but cloud-init has no such entry")
    elif channel == "inline":
        if dest in ci:
            ok(f"5: {dest} covered fresh-boot by a cloud-init inline write")
        else:
            no(f"5: {dest} claims inline coverage but cloud-init never names it")
    elif channel == "envwriter":
        base = os.path.basename(dest)
        if "web-probe-envwrite.sh" in baked and dest in envwriter:
            ok(f"5: {dest} covered fresh-boot by the baked web-probe-envwrite.sh")
        else:
            no(f"5: {dest} claims envwriter coverage but web-probe-envwrite.sh is not "
               f"baked or does not write {base}")
    else:
        no(f"5: {dest} has an unknown coverage channel {channel!r}")

FLOOR_RENDERED = 8
if len(rendered) >= FLOOR_RENDERED:
    ok(f"5: swept {len(rendered)} rendered/env destinations (floor {FLOOR_RENDERED})")
else:
    no(f"5: swept only {len(rendered)} rendered/env destinations (floor {FLOOR_RENDERED}) "
       "-- extraction is probably broken")

# Stale-entry check: a COVERAGE row for a destination no longer written by any SSH
# provisioner is dead weight that makes the table read as broader than it is.
for dest in sorted(set(COVERAGE) - rendered):
    no(f"5: COVERAGE names {dest} but no SSH provisioner writes it -- remove the stale row")

print(f"=== web-host-provisioner-parity: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
PYEOF
