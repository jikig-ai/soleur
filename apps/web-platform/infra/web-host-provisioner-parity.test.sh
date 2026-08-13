#!/usr/bin/env bash
# Web-host provisioner DUAL-DELIVERY parity guard (#7000).
#
# WHAT THIS PINS. server.tf carries 15 `terraform_data` host provisioners whose SSH
# `connection` is pinned to `hcloud_server.web["web-1"]`. That pinning is DELIBERATE and is
# NOT a bug to be fixed by fanning them out over var.web_hosts:
#
#   * CI can SSH exactly ONE host. outputs.tf's `server_ip` is web-1's address, the
#     cf-tunnel-ssh-bridge installs a single iptables NAT rule for it, and the tunnel
#     connector is web-1-only by construction. web-2's public :22 is firewalled to
#     var.admin_ips, which the non-static GH runner egress is not in.
#   * All 15 are `-target=`ed by BARE address across two workflows (14 in
#     apply-web-platform-infra.yml, infra_config_handler_bootstrap in
#     apply-deploy-pipeline-fix.yml), and a bare -target hits EVERY for_each instance — so a
#     fan-out would make every merge dial web-2:22 and hang to the SSH timeout. There is no
#     `timeout` on any connection block, so that burns the job budget.
#   * ADR-114 ("Load-bearing constraint for any I2 implementation") ALREADY records this:
#     "do NOT repoint the ... terraform_data.* connection { host } blocks ... every
#     provisioner dies — and those are -targeted by the per-PR merge apply, so main wedges."
#     (ADR-114 says 12; the real count in this file is 15.) This guard MECHANISES a
#     constraint the architecture already carried in prose.
#   * The plan's Phase 5 (2026-07-24-feat-web-active-active-cluster-iac-plan.md §5.3(c))
#     REMOVES these provisioners once web-1 is cattle. It does not extend them.
#
# So web-2 is NOT wired by SSH — it is wired at BIRTH by the image bake
# (local.host_script_files -> soleur-host-bootstrap.sh) plus cloud-init.yml. That is the
# cattle model (hr-prod-host-config-change-immutable-redeploy).
#
# SCOPE LIMIT, stated plainly: this proves SOURCE parity, not DELIVERED parity. Because
# `hcloud_server.web` carries `ignore_changes = [user_data, ssh_keys, image, ...]` for BOTH
# hosts, an edit to a baked script reaches web-1 at the next merge-apply and reaches web-2
# only on rebuild. Nothing detects that gap — cron-terraform-drift cannot see it (ignore_changes
# suppresses the diff) and host_scripts_content_hash only fires at boot. This guard says
# "the repo describes the same artifact on both paths", NOT "web-2 currently has it".
#
# THE RISK IT CLOSES. The two delivery paths are INDEPENDENT, so an artifact can be added to
# (or changed in) the web-1 SSH path with no matching change on the fresh-boot path. Nothing
# fails: web-1 gets it, CI is green, web-2 silently comes up WITHOUT it on its next rebuild.
#
#     EVERY absolute destination the 15 SSH provisioners WRITE has a fresh-boot counterpart
#     that writes the SAME destination on a fresh cattle host.
#
# WHY DESTINATION-KEYED (this is the whole design). The first version of this guard keyed on
# four enumerated delivery CHANNELS (`provisioner "file"` source, heredoc, rendered `content=`,
# `printf`). Review demonstrated ~13 fail-opens against that shape, because "which command
# performed the write" is an open set: `echo >`, `sed >`, `install`, `tee`, `cp` all existed in
# server.tf already and all evaded it. The DESTINATION is the closed set — it is what a fresh
# host does or does not have. Keying on it makes a new delivery verb a non-event, and it means
# coverage is DERIVED from real install/write statements instead of asserted in a hand-kept
# table. (The first version's table contained a row claiming cloud-init rendered
# /etc/webhook/hooks.json; soleur-host-bootstrap.sh does, and the row was "verified" by a
# systemd ExecStart CONSUMER reference.)
#
# Every input is COMMENT-STRIPPED first, string-aware (a `#` inside a quoted HCL/YAML/shell
# string is not a comment) and covering TRAILING comments, not just full-line ones. The
# previous version stripped only full-line comments and only from server.tf; review showed a
# trailing `# "phantom.sh"` injected a phantom baked filename, prose in cloud-init satisfied
# the delivery requirement, and two of the real sources were passing on comment text alone.
#
# Complements fresh-boot-parity.test.sh, which pins 5 resources DEEPLY (byte-identity of unit
# bodies, env-file key-set parity). This is the BREADTH half. Deliberately overlaps rather
# than assuming the other suite ran.
#
# Every section carries a NON-VACUITY FLOOR: a parse that silently matches nothing must fail
# loudly rather than report a clean sweep of an empty set. The SWEEP-SIZE floors (FLOOR_RESOURCES
# 16, FLOOR_DESTS 57, FLOOR_IDENTITY 5, FLOOR_SEEDED 40) are pinned at the EXACT baseline rather
# than baseline-minus-slack: any slack is a silent-erosion window, and removing a provisioner or a
# delivered artifact is a Phase-5-class change that should cost a deliberate edit here. The §0
# PARSE floors keep slack on purpose -- cloud-init.yml and the bake list legitimately shrink as
# artifacts move onto the image. That slack is real and worth naming: baked 49 vs floor 40,
# write_files 13 vs floor 10, bootstrap installs 46 vs floor 30. Inside each window an extraction
# can go partially blind without tripping the floor (review demonstrated three write_files paths
# hidden at 13->10), so the §0 floors detect a COLLAPSED parse, not a degraded one. The
# per-destination checks in §2/§3 are what cover the degraded case.
#
# Mutation-proven by web-host-provisioner-parity-mutation.test.sh, which asserts WHICH check
# fires for each mutation (a bare non-zero exit credits crashes as detections). Anything that
# battery cannot reach by editing the five INPUT FILES is unproven no matter how green the run
# looks, which is why §5's hygiene checks carry an env-driven reachability probe (see §5).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
# SOLEUR_INFRA_DIR overrides the analysed directory so this guard's own logic can be
# mutation-tested against a sandbox copy in under a second (same rationale as
# run-registered-suites.sh's INFRA_WF override). CI never sets it — verified: the only
# setter in the repo is the mutation battery.
INFRA="${SOLEUR_INFRA_DIR:-$ROOT/apps/web-platform/infra}"

# This loop is the guard's INPUT CONTRACT, and the mutation battery DERIVES its sandbox
# file set from it rather than keeping a second copy (#7014 gap 4). Keep it a single
# `for f in <names>; do` line: the battery parses that shape and hard-fails on divergence,
# because a fifth input read tolerantly (`try/except FileNotFoundError`) would otherwise let
# the battery report a clean run over a check that never executed.
for f in server.tf cloud-init.yml web-probe-envwrite.sh soleur-host-bootstrap.sh webhook.service; do
  [[ -f "$INFRA/$f" ]] || { echo "FATAL: $INFRA/$f not found" >&2; exit 2; }
done

python3 - "$INFRA" <<'PYEOF'
import json, os, re, sys

INFRA = sys.argv[1]
def read(n): return open(os.path.join(INFRA, n)).read()

npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

# ── Comment stripping: string-aware, trailing-comment-aware ──────────────────────────
# A `#` starts a comment ONLY when it is outside a quoted string AND at line-start or
# preceded by whitespace (the YAML rule; also correct for HCL and shell, and it protects
# `http://x#y` and `${VAR#pfx}`). Handles backslash escapes inside strings so an escaped
# quote does not desynchronise the scanner. Trailing comments are stripped, not just
# full-line ones -- review proved a trailing `# "phantom.sh"` injects a phantom filename.
def strip_comments(text):
    out = []; i = 0; n = len(text); in_str = False; quote = ''
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == quote: in_str = False
            i += 1; continue
        if c in '"\'':
            in_str = True; quote = c; out.append(c); i += 1; continue
        if c == '#' and (i == 0 or text[i - 1] in ' \t\n'):
            while i < n and text[i] != '\n': i += 1
            continue
        out.append(c); i += 1
    return ''.join(out)

srv       = strip_comments(read("server.tf"))
ci        = strip_comments(read("cloud-init.yml"))
envwriter = strip_comments(read("web-probe-envwrite.sh"))
bootstrap = strip_comments(read("soleur-host-bootstrap.sh"))

# ── ALLOWLIST: destinations that are LEGITIMATELY web-1-only ─────────────────────────
# Keyed by the exact DESTINATION PATH the failure message prints -- one key namespace, not
# three (the previous version had three and documented one). Value is the reason, which is
# mandatory. Deliberately empty: every destination the 15 write has a real fresh-boot
# counterpart, so nothing needs an exception. Adding an entry is a reviewable diff.
ALLOWLIST: dict[str, str] = {}

# ── §0. Parse the three fresh-boot channels ──────────────────────────────────────────
m = re.search(r'host_script_files = \[(.*?)\n  \]', srv, re.S)
if not m:
    no("0: could not parse local.host_script_files -- fix the extraction, do not trust this run")
    print(f"=== web-host-provisioner-parity: {npass} passed, {nfail} failed ===")
    sys.exit(1)
baked = set(re.findall(r'"([^"]+)"', m.group(1)))
if len(baked) >= 40:
    ok(f"0: parsed local.host_script_files ({len(baked)} baked files)")
else:
    no(f"0: local.host_script_files parsed to only {len(baked)} files (floor 40) -- extraction broken")

# cloud-init write_files paths (structural, anchored to the list-item shape)
wf_paths = set(re.findall(r'^\s*-\s*path:\s*(\S+)\s*$', ci, re.M))
if len(wf_paths) >= 10:
    ok(f"0: parsed cloud-init write_files ({len(wf_paths)} paths)")
else:
    no(f"0: cloud-init write_files parsed to only {len(wf_paths)} paths (floor 10) -- extraction broken")

# soleur-host-bootstrap.sh installs. Two shapes:
#   (a) `for f in A B C; do ... install ... "$SEED/$f" "<DIR>/$f"; done`  -> DIR/A, DIR/B, ...
#   (b) `install ... "$SEED/<src>" <literal-dest>`
# Modelling (a) is what makes this an INSTALL check rather than a BAKE check -- review's P1
# was that the previous version proved membership in a content-hash list and called it delivery.
def parse_bootstrap_installs(text):
    joined = re.sub(r'\\\n\s*', ' ', text)   # join shell line-continuations
    installs = {}                            # dest -> seed source basename
    for fm in re.finditer(r'\bfor\s+(\w+)\s+in\s+(.*?);\s*do(.*?)\bdone\b', joined, re.S):
        var, names_raw, body = fm.group(1), fm.group(2), fm.group(3)
        names = [w for w in names_raw.split() if w and not w.startswith('$')]
        im = re.search(r'\binstall\b[^\n]*?"\$SEED/\$\{?' + var + r'\}?"\s+"?([^"\s]*)/\$\{?'
                       + var + r'\}?"?', body)
        if not im: continue
        d = im.group(1)
        for nm in names:
            installs[f"{d}/{nm}"] = nm
    for im in re.finditer(r'\binstall\b[^\n]*?"\$SEED/([^"$]+)"\s+"?(/[^"\s]+)"?', joined):
        installs[im.group(2)] = im.group(1)
    return installs

bs_installs = parse_bootstrap_installs(bootstrap)
if len(bs_installs) >= 30:
    ok(f"0: parsed soleur-host-bootstrap.sh installs ({len(bs_installs)} destinations)")
else:
    no(f"0: soleur-host-bootstrap.sh parsed to only {len(bs_installs)} installs (floor 30) -- "
       "extraction broken; the install loops changed shape")

# ── §1. Enumerate the SSH-connected terraform_data resources ─────────────────────────
# Brace-balanced and string-aware, so a block ends at its OWN closing brace. The previous
# version split on the next `resource "terraform_data"`, so the last block ran to EOF and
# swallowed two sibling hcloud_volume resources.
def hcl_blocks(hcl, kind):
    for bm in re.finditer(r'resource\s+"' + kind + r'"\s+"([^"]+)"\s*\{', hcl):
        i = bm.end(); depth = 1; in_str = False; q = ''
        while i < len(hcl) and depth > 0:
            c = hcl[i]
            if in_str:
                if c == '\\': i += 2; continue
                if c == q: in_str = False
            elif c in '"\'': in_str = True; q = c
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
            i += 1
        yield bm.group(1), hcl[bm.end():i - 1]

ssh_resources = {}
for name, body in hcl_blocks(srv, "terraform_data"):
    if re.search(r'connection\s*\{[^{}]*?\btype\s*=\s*"ssh"', body, re.S):
        ssh_resources[name] = body

FLOOR_RESOURCES = 16
if len(ssh_resources) >= FLOOR_RESOURCES:
    ok(f"1: swept {len(ssh_resources)} SSH-connected terraform_data resources (floor {FLOOR_RESOURCES})")
else:
    no(f"1: swept only {len(ssh_resources)} SSH-connected terraform_data resources "
       f"(floor {FLOOR_RESOURCES}). Either a provisioner was REMOVED -- which is a Phase-5 "
       "change (plan §5.3(c)), not an incidental edit, and must be done with the rest of "
       "Phase 5 -- or the extraction broke. Check which before editing this floor.")

# Host-pinning. Assert the ABSENCE of for_each rather than the presence of a web-1 string:
# review showed a fanned-out resource with a nested per-provisioner connection kept a literal
# `web["web-1"]` elsewhere in the block and passed the presence check.
fanned = [n for n, b in ssh_resources.items() if re.search(r'^\s*for_each\s*=', b, re.M)]
unpinned = [n for n, b in ssh_resources.items()
            if not re.search(r'host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address', b)]
if not fanned and not unpinned:
    ok(f"1: all {len(ssh_resources)} SSH provisioners are web-1-pinned and none is for_each'd")
else:
    no(f"1: for_each'd={sorted(fanned)} not-web-1-pinned={sorted(unpinned)}. CI has ONE SSH "
       "route (web-1) and all 15 are bare -target'ed, so a fan-out makes every merge-triggered "
       "apply dial a host it cannot reach and hang to the SSH timeout. See ADR-114's "
       "load-bearing constraint. If CI genuinely gained a route to web-2, the tunnel connector, "
       "the firewall and the -target lists must change FIRST, and this check with them.")

# ── §2. Destination sweep: the load-bearing invariant ────────────────────────────────
# ASYMMETRY (the v2 defect, and the reason this is shaped the way it is). The two halves of
# the derivation fail in OPPOSITE directions:
#   * EXTRACTION ("what do the 15 write?") -- a miss is SILENT: the destination never enters
#     the set, so nothing is checked and the guard reports a clean sweep. Enumerating write
#     verbs here is therefore fail-OPEN, which is exactly how v2 shipped: `mv`, `dd of=`,
#     `curl -o`, `python3 - /path`, and any quoted path all walked past it. So this half is
#     INVERTED -- every absolute path is a delivery UNLESS it appears only under a read-only
#     verb. An unknown verb defaults to "delivery", which fails LOUD.
#   * COVERAGE ("does a fresh host write it?") -- a miss is LOUD: the destination reports as
#     uncovered. Enumerating verbs here is safe; the danger is over-CREDITING. So this half is
#     positionally strict: for install/cp/mv the token must be the LAST path (v2 credited a
#     path appearing as the SOURCE argument, which made the whole vector chain unfalsifiable).
READONLY_VERBS = {
    'test', '[', 'grep', 'chmod', 'chown', 'chgrp', 'rm', 'mkdir', 'systemctl',
    'systemd-tmpfiles', 'journalctl', 'ls', 'stat', 'dpkg', 'docker', 'visudo',
    'apparmor_parser', 'bash', 'sh', 'command', 'sysctl', 'printf', 'echo',
    'fail2ban-client', 'systemd-analyze', 'export', 'cd', 'true', 'set',
}
TRANSIENT = ('/tmp/', '/dev/', '/proc/', '/sys/', '/run/')
_SEG = re.compile(r'(?:&&|\|\||[;|])')

# Command prefixes that RUN another command rather than being the command. Classifying the
# segment on the wrapper instead of the wrapped verb is a live defect in both directions:
#
#   * FALSE POSITIVE (this PR shipped one). `runuser -u deploy -- sudo -n /usr/bin/systemctl
#     daemon-reload` classified as verb `runuser`, which is not in READONLY_VERBS, so every
#     absolute path in the segment was credited as a DELIVERED artifact — and the guard then
#     demanded that /usr/bin/systemctl, a binary the base image ships, be installed on the
#     fresh-boot path. Measured: 12 passed / 1 failed on this branch while origin/main was 13/0.
#   * FALSE NEGATIVE. A wrapper whose wrapped verb is a real writer must still be credited, so
#     this resolves TO the wrapped verb rather than exempting the segment.
#
# Each entry maps a wrapper to the options that take a SEPARATE value argument, so the scan can
# skip past them without swallowing the wrapped command. `--` always ends the wrapper's own
# arguments.
_WRAPPERS = {
    'sudo':    {'-u', '-g', '-U', '-p', '-C', '-h', '-r', '-t', '-T'},
    'runuser': {'-u', '-g', '-G', '-c', '--user', '--group', '--shell', '-s'},
    'doas':    {'-u', '-C'},
    'env':     set(),
    'timeout': {'-s', '--signal', '-k', '--kill-after'},
    'nice':    {'-n'},
    'ionice':  {'-c', '-n', '-p'},
    'stdbuf':  {'-i', '-o', '-e'},
    'setsid':  set(),
    'flock':   {'-w', '--wait', '-E', '--conflict-exit-code'},
}


def _split_wrapper(toks):
    """Resolve (effective_verb, wrapper_chain, index_of_wrapped_command) for a tokenised segment.

    The INDEX is returned rather than the wrapper's own tokens so the caller can slice
    `toks[i:]` — reconstructing the wrapped portion by filtering token VALUES would mis-handle a
    segment where the same token appears both inside and after the wrapper's own arguments.
    Conservative by construction: anything it cannot confidently classify terminates the peel, so
    the caller keeps the ORIGINAL verb and the fail-closed over-extraction behaviour is preserved.
    """
    chain = []
    i = 0
    while i < len(toks):
        base = os.path.basename(toks[i].strip('"\'(!'))
        if base not in _WRAPPERS:
            break
        val_opts = _WRAPPERS[base]
        chain.append(base)
        i += 1
        while i < len(toks):
            t = toks[i]
            if t == '--':
                i += 1
                break
            if not t.startswith('-'):
                break
            i += 1
            # `-u deploy` consumes its value; `-u=deploy` and `-udeploy` do not.
            if t in val_opts and i < len(toks):
                i += 1
    if i >= len(toks):
        # Nothing but wrappers and their options (e.g. a bare `sudo -l`). No wrapped command.
        return None, chain, i
    return toks[i].strip('"\'(!'), chain, i


def _unwrap_shell_c(toks):
    """Unwrap ONE level of `bash -c '<command>'` / `sh -c "<command>"`.

    `bash` and `sh` are in READONLY_VERBS deliberately — `bash /usr/local/bin/foo.sh` INVOKES a
    script and must not credit it as a delivered artifact. But that exemption also swallowed the
    payload of `-c`, so `sudo bash -cl "install -m0755 /tmp/x /usr/local/bin/y"` delivered a root
    binary with no fresh-boot counterpart and left the sweep in silence. Measured: dropping
    bash/sh from READONLY_VERBS entirely keeps the real corpus at 13/0, so the blunt fix is
    AVAILABLE — it is rejected because it would false-fire on the first ordinary
    `bash /usr/local/bin/x.sh` invocation anyone adds. Unwrapping `-c` is the narrow form: it
    credits what the shell RUNS without crediting what the shell IS GIVEN TO RUN.

    Returns the inner command's tokens, or None when this is not a `-c` invocation.
    """
    if not toks or os.path.basename(toks[0].strip('"\'(!')) not in ('bash', 'sh', 'dash', 'zsh'):
        return None
    i = 1
    while i < len(toks) and toks[i].startswith('-'):
        # A bundled run containing `c` (-c, -cl, -xc) means the NEXT token is the command string.
        if not toks[i].startswith('--') and 'c' in toks[i][1:]:
            inner = ' '.join(toks[i + 1:]).strip()
            if inner[:1] in ('"', "'"):
                inner = inner[1:]
                q = inner[-1:] if inner[-1:] in ('"', "'") else ''
                if q:
                    inner = inner[:-1]
            return inner.split() if inner else None
        i += 1
    return None


def _sudo_is_list_mode(toks):
    """True when this segment is `sudo`/`doas` in LIST mode.

    Scoped to SUDO'S OWN OPTION RUN — the tokens before the first non-option argument — which is
    the whole point. The previous form searched the ENTIRE segment for `-\\w*l`, so it exempted
    real deliveries that merely happened to contain such a token anywhere:
    `sudo cp -al /tmp/x /usr/local/bin/y`, `sudo rsync -al`, `sudo useradd -l`,
    `sudo bash -cl "install …"`. Each is a genuine write that left the sweep in silence.
    It also MISSED `/usr/bin/sudo -l` (matched on basename now) and `sudo -ln` (an option run
    containing `l`, which the bundled form must accept).
    """
    if not toks:
        return False
    if os.path.basename(toks[0].strip('"\'(!')) not in ('sudo', 'doas'):
        return False
    val_opts = _WRAPPERS['sudo']
    i = 1
    while i < len(toks):
        t = toks[i]
        if t == '--' or not t.startswith('-'):
            return False          # sudo's own options ended without a list flag
        if t == '--list':
            return True
        # A BUNDLED short-option run (`-ln`, `-nl`, `-l`). Reject long options and any
        # `--opt=value` form, which cannot bundle `l`.
        if not t.startswith('--') and 'l' in t[1:]:
            return True
        i += 1
        if t in val_opts and i < len(toks):
            i += 1               # skip this option's separate value
    return False

def _strip_heredoc_bodies(cmd):
    """Drop `<< 'MARK' … MARK` bodies. They are FILE CONTENT (systemd units), not commands --
    an `ExecStart=/usr/local/bin/x` inside one is not this provisioner writing /usr/local/bin/x.
    The `cat > DEST` line itself survives, so the real write is still extracted."""
    return re.sub(r"<<\s*'([A-Za-z0-9_]+)'.*?\n\1(?=\s|$)", "<<STRIPPED", cmd, flags=re.S)

def destinations(body):
    """Every absolute path this provisioner delivers. Fail-closed by over-extraction."""
    out, interpolated, unresolvable = set(), set(), set()
    # `([^"]*)` not `([^"]+)`: `destination = ""` satisfies neither a 1+-char quoted capture nor
    # the non-quote-initial pattern below, so with `+` it evaded BOTH branches and left the sweep
    # in silence -- the exact class this pair exists to close (review F7, reproduced: guard rc=0).
    for d in re.findall(r'destination\s*=\s*"([^"]*)"', body):
        (out if d.startswith('/') else interpolated).add(d)
    # A destination that is not a STRING LITERAL at all -- `destination = local.x`,
    # `destination = var.y` -- is invisible to the quoted extraction above. It does not become
    # a finding; it simply LEAVES THE SWEEP. Converting `destination = "/abs"` attributes to
    # locals is an ordinary HCL refactor, and without this branch two of them could be dropped
    # silently while the guard stayed green, because the FLOOR_DESTS margin absorbed the loss
    # (#7014 gap 1; the margin is now zero as well, so the two defences are independent).
    # Same fail-silent class as the interpolated case, arriving through a second door.
    #
    # ANCHORED to the start of a line. Unanchored, this ran over the WHOLE resource body --
    # including `inline` shell strings and heredoc bodies -- so an ordinary
    # `logger --destination=/var/log/audit.log`, a `grep -q 'destination = local' …`, or a
    # config heredoc line `destination = tcp://logs:514` each produced a bogus "HCL REFERENCE"
    # failure whose remediation text made no sense for the input. All three reproduced at
    # review. An HCL attribute is always the first token on its line; a shell flag or a
    # heredoc payload line is not.
    for d in re.findall(r'^[ \t]*destination\s*=\s*([^"\s]\S*)', body, re.M):
        unresolvable.add(d)
    for arr in re.findall(r'inline\s*=\s*\[(.*?)\n\s*\]', body, re.S):
        for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', arr):
            cmd = _strip_heredoc_bodies(raw.replace('\\n', '\n').replace('\\"', '"'))
            for line in cmd.split('\n'):
                for seg in _SEG.split(line):
                    seg = seg.strip()
                    if not seg: continue
                    toks = seg.split()
                    verb = toks[0].strip('"\'(!') if toks else ''
                    # `install -d` / `mkdir` create DIRECTORIES, not delivered artifacts.
                    if verb == 'install' and re.match(r'\s*-\S*d\b', seg[len(verb):]): continue
                    # `sudo -l` / `sudo --list` is LIST MODE: it resolves and prints what the
                    # target user may run and never executes the command, so the paths in it
                    # are a QUERY, not a delivery. Without this, a policy probe such as
                    # `sudo -n -l -U deploy /usr/bin/systemctl daemon-reload` (#7220 AC4) makes
                    # the guard report that the provisioner "writes" /usr/bin/systemctl and
                    # demand it be delivered on the fresh-boot path — a remediation that makes
                    # no sense for a system binary the base image already ships. `sudo` stays
                    # OUT of READONLY_VERBS, because a bare `sudo <cmd>` genuinely can write;
                    # only the list form is exempt.
                    if _sudo_is_list_mode(toks):
                        continue
                    # Classify on the WRAPPED command, not the privilege wrapper. `_split_wrapper`
                    # returns None only when the segment is wrappers-and-options with no command,
                    # in which case there is nothing to deliver.
                    eff, chain, widx = _split_wrapper(toks)
                    if chain:
                        if eff is None:
                            continue
                        verb = os.path.basename(eff)
                        # The wrapper's OWN arguments are not delivered artifacts either: a
                        # `-u deploy` operand or a `--` separator carries no destination. Scan
                        # only the wrapped command's tokens.
                        toks = toks[widx:]
                        seg = ' '.join(toks)
                    # `bash -c '<cmd>'` (possibly behind a wrapper, hence after the peel above):
                    # classify on <cmd>, not on the shell. One level only — a shell string that
                    # itself spawns another `-c` is not something a static reader should chase.
                    inner = _unwrap_shell_c(toks)
                    if inner:
                        verb = os.path.basename(inner[0].strip('"\'(!'))
                        seg = ' '.join(inner)
                    for m in re.finditer(r'(>>?\s*"?)?((?<![\w$.:/])/[A-Za-z0-9._@/-]+)', seg):
                        path = m.group(2)
                        if m.group(1) or verb not in READONLY_VERBS:
                            out.add(path)
    return ({d for d in out if not d.startswith(TRANSIENT) and d.rstrip('/') != ''},
            {d for d in interpolated},
            unresolvable)

def _last_path(seg):
    """Last path-like argument of a command -- an absolute literal OR a $VAR/${VAR} token.
    Both must be recognised or the LAST-argument test silently falls back to an earlier
    literal, which is how a SOURCE argument gets credited as the destination."""
    p = re.findall(r'(?<![\w])"?((?:/[A-Za-z0-9._@/-]+)|(?:\$\{?\w+\}?))"?(?=\s|$)', seg)
    return p[-1] if p else None

def written_by(text, dest, var_map=None):
    """Does `text` WRITE dest? Positionally strict -- a path appearing as a SOURCE argument,
    or as an `install -d` directory, or in a consumer reference (ExecStart, chmod), does NOT
    count. Verb list may grow freely: a miss here fails LOUD as 'uncovered'."""
    tokens = [dest]
    var = (var_map or {}).get(dest)
    if var: tokens += [f'${var}', '${' + var + '}']
    for line in text.split('\n'):
        if re.match(r'\s*-\s*path:\s*' + re.escape(dest) + r'\s*$', line):
            return True
        for seg in _SEG.split(line):
            seg = seg.strip()
            if not seg: continue
            toks = seg.split()
            verb = toks[0].strip('"\'(!') if toks else ''
            for tok in tokens:
                e = re.escape(tok)
                if re.search(r'>>?\s*"?' + e + r'"?(?:\s|$)', seg): return True
                if re.search(r'\btee\s+(?:-\S+\s+)*"?' + e + r'"?(?:\s|$)', seg): return True
                if re.search(r'\bdd\b[^\n]*\bof="?' + e + r'"?(?:\s|$)', seg): return True
                if re.search(r'\b(?:curl|wget)\b[^\n]*\s-[oO]\s+"?' + e + r'"?(?:\s|$)', seg): return True
                if verb in ('install', 'cp', 'mv'):
                    if verb == 'install' and re.match(r'\s*-\S*d\b', seg[len(verb):]): continue
                    if _last_path(seg) in (tok, f'"{tok}"'): return True
                if verb == 'python3' and _last_path(seg) == tok: return True
    return False

def strip_uninvoked_heredocs(text, invoked_in):
    """A write inside a heredoc BODY is only a delivery if the script that body authors is
    actually RUN on the fresh-boot path. Without this, appending a never-invoked script whose
    body contains `install … /etc/soleur/x` credits /etc/soleur/x as delivered -- dead code
    certifying coverage, structurally the same defect as v1's ExecStart-as-producer row.
    The `cat > TARGET` line itself is preserved, so TARGET remains a real write."""
    def repl(m):
        target, body, marker = m.group(1), m.group(3), m.group(2)
        base = os.path.basename(target.strip('"\''))
        runs = base and (base in invoked_in or len(re.findall(re.escape(base), text)) > 2)
        return m.group(0) if runs else f"cat > {target} <<'{marker}'\nUNINVOKED\n{marker}"
    return re.sub(r"cat > (\S+) <<\s*'([A-Za-z0-9_]+)'\n(.*?)\n\2(?=\s|$)", repl, text, flags=re.S)

def heredoc_scoped_vars(text):
    """`VAR=/abs/path` bindings, scoped to the heredoc body they appear in. v2 built this map
    GLOBALLY, so one stray `CFG=/some/path` anywhere in an 800-line file permanently credited
    that path via an unrelated `install … "$CFG"` ~600 lines away. Scoping kills that."""
    out = {}
    for hm in re.finditer(r"<<\s*'([A-Za-z0-9_]+)'(.*?)\n\1(?=\s|$)", text, re.S):
        body = hm.group(2)
        local = {m.group(2): m.group(1)
                 for m in re.finditer(r'^\s*(\w+)=(/[^\s"\';|&)$]+)\s*$', body, re.M)}
        for path, var in local.items():
            if written_by(body, path, {path: var}): out[path] = var
    return out

bootstrap = strip_uninvoked_heredocs(bootstrap, ci)
bs_vars = heredoc_scoped_vars(bootstrap)

all_dests = {}
for name, body in ssh_resources.items():
    dests, interpolated, unresolvable = destinations(body)
    for d in dests:
        all_dests.setdefault(d, set()).add(name)
    # The remedy deliberately does NOT offer ALLOWLIST. ALLOWLIST is keyed by the resolved
    # DESTINATION PATH and is consulted only in the coverage loop below; this branch fires
    # before any path is known, so an entry added here would suppress nothing AND would then
    # trip §5's stale-entry check -- turning one failure into two. Advice that makes the
    # failure worse is worse than no advice.
    for d in sorted(unresolvable):
        no(f"2: {name} sets destination = {d}, an HCL REFERENCE rather than a string literal, "
           "which the quoted-destination extraction cannot see -- so the destination would "
           "leave the sweep SILENTLY rather than report as uncovered. Use a literal path.")
    # An interpolated destination cannot be statically resolved, so parity CANNOT be proven
    # for it. v2 dropped these silently via a startswith('/') filter -- the purest fail-open
    # in the file, since `destination = "${local.x}/y"` is idiomatic HCL. Not provable is a
    # finding, not a skip.
    for d in sorted(interpolated):
        no(f"2: {name} delivers to {d!r}, an INTERPOLATED destination this guard cannot "
           "statically resolve, so its fresh-boot parity is unproven. Use a literal path. "
           "(ALLOWLIST is not a remedy here -- see the note above the unresolvable branch.)")

uncovered = []
for dest in sorted(all_dests):
    if dest in ALLOWLIST: continue
    chans = []
    if dest in wf_paths:                        chans.append("cloud-init write_files")
    if written_by(ci, dest):                    chans.append("cloud-init write")
    if dest in bs_installs:                     chans.append("bootstrap seed-install")
    if written_by(bootstrap, dest, bs_vars):    chans.append("bootstrap write")
    if written_by(envwriter, dest):             chans.append("web-probe-envwrite")
    if not chans:
        uncovered.append(dest)
        no(f"2: {dest} is written by {sorted(all_dests[dest])} but NOTHING writes it on a "
           "fresh host (not a cloud-init write_files entry, not a cloud-init write, not a "
           "soleur-host-bootstrap.sh install, not web-probe-envwrite.sh). web-2 comes up "
           "WITHOUT it on its next rebuild. Fix by delivering it on the fresh-boot path -- "
           "bake it and install it in soleur-host-bootstrap.sh, or write it from cloud-init. "
           "Only if the artifact is provably meaningless on a fresh host (a running-host "
           "rotation, not config) add it to ALLOWLIST with that reason.")

# Pinned to the EXACT baseline, not baseline-minus-slack. At 50 against a real 52 this floor
# carried a two-destination silent-erosion window: delete two `provisioner "file"` blocks and
# the sweep quietly covers 50 while reporting a clean run (#7014 gap 1). Removing a delivered
# artifact is a Phase-5-class change (plan §5.3(c)), so it SHOULD cost an explicit edit here --
# same margin-zero rationale as FLOOR_RESOURCES and FLOOR_IDENTITY.
FLOOR_DESTS = 57
if len(all_dests) >= FLOOR_DESTS:
    if not uncovered:
        ok(f"2: all {len(all_dests)} SSH-written destinations have a fresh-boot writer "
           f"(floor {FLOOR_DESTS})")
else:
    no(f"2: swept only {len(all_dests)} destinations (floor {FLOOR_DESTS}). Either artifacts "
       "were legitimately removed -- a Phase-5-class change -- or the destination extraction "
       "broke. A clean sweep of nothing is not coverage.")

# ── §3. Bootstrap-installed destinations must have their SEED source BAKED ───────────
# soleur-host-bootstrap.sh installs from "$SEED/<name>", which only exists if <name> is in
# local.host_script_files AND in the Dockerfile COPY set. Baked-but-not-installed is caught
# by §2; installed-but-not-baked is caught here. Both directions, or the pair is not proof.
missing_seed = sorted({src for dest, src in bs_installs.items()
                       if dest in all_dests and src not in baked})
n_checked = sum(1 for d in bs_installs if d in all_dests)
if not missing_seed:
    ok(f"3: all {n_checked} bootstrap-installed destinations have their seed file baked")
else:
    no(f"3: soleur-host-bootstrap.sh installs from $SEED/{missing_seed} but those are NOT in "
       "local.host_script_files, so the seed file will not exist on a fresh host and the "
       "install fails at boot.")

# NON-VACUITY FLOOR. §3 quantifies over `bs_installs INTERSECT all_dests`, and an empty
# intersection makes `missing_seed` empty too -- a clean sweep of nothing, reported as a pass.
# Every other section carried a floor; this one did not (#7014 gap 3).
#
# Pinned at the EXACT baseline, same doctrine as FLOOR_RESOURCES / FLOOR_DESTS / FLOOR_IDENTITY:
# at 30 against a real 36 this carried a six-destination silent-erosion window, and review
# confirmed the battery stayed green at every value from 22 up. A slack floor on a sweep size
# is the defect #7014 gap 1 existed to close; shipping a new one would have re-opened it.
#
# Stated limit, so nobody reads more into it than it proves: against the CURRENT tree this floor
# cannot be exercised in isolation -- instrumentation at review found ZERO destinations covered
# by both a bootstrap install and another channel, so every shrink of the intersection also
# moves §2's per-destination coverage. That is a property of today's delivery layout, not a
# theorem: give a bootstrap-installed destination a second fresh-boot writer and §3's floor
# becomes independently trippable. Its value either way is that an intersection collapse is
# named HERE rather than inferred from a neighbour.
FLOOR_SEEDED = 40
if n_checked >= FLOOR_SEEDED:
    ok(f"3: the seed-baked check ran over {n_checked} bootstrap-installed destinations "
       f"(floor {FLOOR_SEEDED})")
else:
    no(f"3: the seed-baked check ran over only {n_checked} bootstrap-installed destinations "
       f"(floor {FLOOR_SEEDED}). Either the install-loop destinations no longer overlap what "
       "the SSH provisioners write -- which means §3 is checking almost nothing -- or the "
       "bootstrap install extraction drifted. A clean sweep of nothing is not coverage.")

# ── §4. BYTE-IDENTITY where both paths carry their own copy of a unit body ───────────
# A heredoc whose counterpart is a cloud-init write_files entry means the SAME body written
# TWICE, in two files, in two encodings -- drift with no compiler behind it. (Heredocs whose
# counterpart is a BAKED repo file are byte-identical by construction; fresh-boot-parity.test.sh
# §3/§5 pins those, including the install, separately.)
def parse_write_files(text):
    out = {}
    for wm in re.finditer(r'-\s*path:\s*(\S+)\n(.*?)(?=\n  - path: |\n[a-z_]+:\n)', text, re.S):
        path, body = wm.group(1), wm.group(2)
        cm = re.search(r'content:\s*\|\n(.*)', body, re.S)
        if not cm:
            out.setdefault(path, None); continue
        acc = []
        for L in cm.group(1).split('\n'):
            if L.strip() == '': acc.append('')
            elif L.startswith('      '): acc.append(L[6:])
            else: break
        while acc and acc[-1] == '': acc.pop()
        out[path] = '\n'.join(acc)
    return out

wf_bodies = parse_write_files(ci)
n_identity = 0
for name, body in ssh_resources.items():
    for dest, marker in re.findall(r"cat > (\S+) << '([A-Za-z0-9_]+)'", body):
        if dest not in wf_bodies: continue
        if wf_bodies[dest] is None:
            no(f"4: {dest} is heredoc-written by {name} and has a cloud-init write_files entry "
               "with no parseable `content: |` body, so the two copies cannot be compared. "
               "Give it a literal block body, or the drift is invisible.")
            continue
        hm = re.search(r'"cat > ' + re.escape(dest) + r" << '" + marker + r"'\\n(.*?)\\n"
                       + marker + r'"', srv)
        if not hm:
            no(f"4: could not extract the {dest} heredoc body -- fix the extraction rather "
               "than trusting this run")
            continue
        n_identity += 1
        if hm.group(1).replace('\\n', '\n').strip() == wf_bodies[dest].strip():
            ok(f"4: {dest} body identical across server.tf heredoc and cloud-init write_files")
        else:
            no(f"4: {dest} DRIFTED between the server.tf heredoc and the cloud-init "
               "write_files body, so web-1 and web-2 would run DIFFERENT units. The change "
               "that produced this belongs on BOTH paths -- do not edit whichever side is "
               "cheaper just to clear the failure; restore the body the originating change "
               "intended, on both.")

# ── §4b. webhook.service: a REPO FILE against its cloud-init write_files mirror ───────
#
# §4 above only reaches units server.tf writes with a HEREDOC. webhook.service is delivered to
# web-1 by a `provisioner "file"` whose source is the committed repo file, and to a fresh host by
# an INLINE cloud-init write_files body — so it is dual-written in two encodings with no compiler
# behind it, exactly the class §4 exists for, and nothing compared them. Both copies carry a
# "MUST stay in lockstep" comment and neither was enforced (#7220 review).
#
# THE COMPARISON IS DIRECTIVE-WISE, NOT BYTE-WISE, and that is deliberate rather than a
# concession. Measured: the two bodies are NOT byte-identical (the cloud-init copy carries an
# abbreviated comment, because that file is base64gzip'd into user_data against a Hetzner byte
# cap) while all 20 DIRECTIVES match. Byte-identity here would therefore fail on a difference
# systemd cannot observe, and the pressure to clear it would push a maintainer to re-inflate the
# comment into the byte-capped file. What matters is what systemd reads: the directive sequence,
# in order, including section headers.
WEBHOOK_UNIT = "/etc/systemd/system/webhook.service"
def _directives(text):
    return [l.strip() for l in text.split('\n') if l.strip() and not l.strip().startswith('#')]

if WEBHOOK_UNIT not in wf_bodies or wf_bodies[WEBHOOK_UNIT] is None:
    no(f"4b: {WEBHOOK_UNIT} has no parseable cloud-init write_files `content: |` body, so the "
       "repo unit and the fresh-boot copy cannot be compared. A fresh host would boot an "
       "unverified webhook.service -- the only remediation channel on a host with no SSH runbook.")
else:
    repo_unit = _directives(read("webhook.service"))
    mirror_unit = _directives(wf_bodies[WEBHOOK_UNIT])
    # Non-vacuity BEFORE the comparison: two empty lists compare equal, so a broken extraction
    # would report parity between nothing and nothing. webhook.service carries 20 directives.
    if len(repo_unit) < 10 or len(mirror_unit) < 10:
        no(f"4b: extracted only {len(repo_unit)} repo and {len(mirror_unit)} mirror directives "
           "from webhook.service -- fix the extraction rather than trusting this run.")
    else:
        n_identity += 1
        if repo_unit == mirror_unit:
            ok(f"4b: {WEBHOOK_UNIT} directives identical across the repo unit and the "
               f"cloud-init mirror ({len(repo_unit)} directives)")
        else:
            only_repo = [d for d in repo_unit if d not in mirror_unit]
            only_mirror = [d for d in mirror_unit if d not in repo_unit]
            no(f"4b: {WEBHOOK_UNIT} DRIFTED between the committed unit and the cloud-init "
               f"mirror. Only in the repo unit: {only_repo or '(order differs only)'}. Only in "
               f"the mirror: {only_mirror or '(order differs only)'}. web-1 and a freshly built "
               "host would run DIFFERENT webhook units. Put the change on BOTH paths; note the "
               "mirror is byte-capped, so keep COMMENTS short there but never a directive.")

FLOOR_IDENTITY = 5
if n_identity >= FLOOR_IDENTITY:
    ok(f"4: byte-identity checked on {n_identity} dual-written bodies (floor {FLOOR_IDENTITY})")
else:
    no(f"4: byte-identity checked on only {n_identity} bodies (floor {FLOOR_IDENTITY}). Either "
       "a dual-written unit moved to a single delivery path -- a Phase-5-class change -- or "
       "the heredoc/write_files extraction broke.")

# ── §5. ALLOWLIST hygiene: every entry justified, none stale ─────────────────────────
def check_allowlist(entries, label):
    for art, reason in sorted(entries.items()):
        if not reason.strip():
            no(f"5: {label} entry {art!r} has no stated reason")
        if art not in all_dests:
            no(f"5: {label} names {art} but no SSH provisioner writes it -- remove the stale "
               "entry")

check_allowlist(ALLOWLIST, "ALLOWLIST")

# REACHABILITY PROBE (#7014 gap 2). ALLOWLIST is empty -- which is the correct state -- so both
# hygiene checks above are STRUCTURALLY UNREACHABLE from the mutation battery: no edit to the
# four input FILES can add an entry, and the checks could therefore be deleted with the battery
# reporting a full pass. They asserted nothing. This env var feeds a synthetic entry set through
# the SAME function so both arms can be proven to fire.
#
# It is deliberately NOT merged into ALLOWLIST. An env var able to SUPPRESS a §2 finding would
# be a fail-open switch on the guard's load-bearing invariant, and a test hook must never be
# able to make a real failure disappear. This one can only ADD failures. CI never sets it --
# the only setter in the repo is the mutation battery, same contract as SOLEUR_INFRA_DIR.
probe_raw = os.environ.get("SOLEUR_PARITY_ALLOWLIST_PROBE", "")
if probe_raw:
    # RecursionError is not a ValueError, and deeply-nested JSON raises it -- a traceback
    # rather than the named failure this branch exists to produce.
    try:
        probe_entries = json.loads(probe_raw)
    except (ValueError, RecursionError) as exc:
        no(f"5: SOLEUR_PARITY_ALLOWLIST_PROBE is set but is not parseable JSON ({exc})")
        probe_entries = {}
    # Shape-check before use, at BOTH levels. `.items()` on a JSON array raises AttributeError;
    # so does `reason.strip()` on a non-string VALUE, and the first version checked only the
    # top level -- so `{"/a": null}` produced exactly the outcome this comment claimed to
    # prevent: a traceback, non-zero exit, and zero [FAIL] lines. The battery's attribution
    # rule then refuses to credit it, correctly, but as an unexplained failure rather than a
    # named one.
    if not isinstance(probe_entries, dict) or not all(
            isinstance(v, str) for v in probe_entries.values()):
        no("5: SOLEUR_PARITY_ALLOWLIST_PROBE must be a JSON object of {path: reason} with "
           "string values")
        probe_entries = {}
    check_allowlist(probe_entries, "ALLOWLIST probe")

print(f"=== web-host-provisioner-parity: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
PYEOF
