#!/usr/bin/env bash
# Web-host provisioner DUAL-DELIVERY parity guard (#7000).
#
# WHAT THIS PINS. server.tf carries 18 `terraform_data` host provisioners whose SSH
# `connection` is pinned to `hcloud_server.web["web-1"]`. That pinning is DELIBERATE and is
# NOT a bug to be fixed by fanning them out over var.web_hosts:
#
#   * CI can SSH exactly ONE host. outputs.tf's `server_ip` is web-1's address, the
#     cf-tunnel-ssh-bridge installs a single iptables NAT rule for it, and the tunnel
#     connector is web-1-only by construction. web-2's public :22 is firewalled to
#     var.admin_ips, which the non-static GH runner egress is not in.
#   * All 18 are `-target=`ed by BARE address across two workflows (17 in
#     apply-web-platform-infra.yml, infra_config_handler_bootstrap in
#     apply-deploy-pipeline-fix.yml), and a bare -target hits EVERY for_each instance — so a
#     fan-out would make every merge dial web-2:22 and hang to the SSH timeout. There is no
#     `timeout` on any connection block, so that burns the job budget.
#   * ADR-114 ("Load-bearing constraint for any I2 implementation") ALREADY records this:
#     "do NOT repoint the ... terraform_data.* connection { host } blocks ... every
#     provisioner dies — and those are -targeted by the per-PR merge apply, so main wedges."
#     (ADR-114's 2026-07-27 amendment says 15; the count in this file is 18 as of #7226, whose web_1_host_key_probe writes nothing.) This guard MECHANISES a
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
#     EVERY absolute destination the 18 SSH provisioners WRITE has a fresh-boot counterpart
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
# 19, FLOOR_DESTS 75, FLOOR_IDENTITY 5, FLOOR_SEEDED 40) are pinned at the EXACT baseline rather
# than baseline-minus-slack: any slack is a silent-erosion window, and removing a provisioner or a
# delivered artifact is a Phase-5-class change that should cost a deliberate edit here. The §0
# PARSE floors keep slack on purpose -- cloud-init.yml and the bake list legitimately shrink as
# artifacts move onto the image. That slack is real and worth naming: baked 49 vs floor 40,
# write_files 14 vs floor 11 (13 vs 10 until #8651 added the networkd fallback file), bootstrap installs 46 vs floor 30. Inside each window an extraction
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
# mutation-tested against a sandbox copy in under a second (same seam the
# run-registered-suites.sh fixtures use for glob derivation). CI never sets it —
# verified: the only setter in the repo is the mutation battery.
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
# mandatory. Adding an entry is a reviewable diff.
#
# This was "deliberately empty" until #7539, on the claim that every destination the 17 write
# has a real fresh-boot counterpart. That stopped being true when #7539 added a rotation
# backup, and the sentence is corrected here rather than left to read as still-surveyed --
# a claim that silently outlives the set it described is the exact defect #7539 fixes.
ALLOWLIST: dict[str, str] = {
    # A transient last-known-good backup, not config. server.tf writes it ONLY when vector is
    # already running with an existing config, `rm -f`s it when that precondition fails, and
    # `rm -f`s it again after a successful swap -- so it never persists in steady state and a
    # fresh host must NOT have one. Delivering it on the fresh-boot path (the other remedy the
    # §2 message offers) would be actively wrong: it would seed a "known-good" restore target
    # onto a host where vector has never run, which is precisely the poisoned-restore shape
    # the guarded snapshot exists to prevent.
    "/etc/vector/vector.toml.prev":
        "running-host rotation artifact (#7539): written only from a demonstrably-running "
        "agent, removed on both the failure and success paths, absent by design on a fresh "
        "host.",
    # ── #9151: the deploy_pipeline_fix_web2 sibling's FILE_MAP members with no fresh-boot
    # writer. These arrived fleet-wide through push-infra-config.sh → the web-1-pinned
    # infra-config webhook, so they were never on the bake path (a pre-existing gap this
    # change does not widen). On web-2 the sibling itself IS the coverage: its
    # hcloud_server.web["web-2"].id trigger re-delivers them after every host replacement,
    # which no fresh-boot channel can promise for a file this late in the boot.
    # The shared reason is stated once per entry because §5 requires a non-empty string.
    "/usr/local/bin/inngest-enumerate-reminders.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/inngest-rearm-reminders.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/inngest-wiped-volume-verify.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/cat-inngest-verify-state.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/inngest-inventory.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/git-lock-chardevice-sweep.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/usr/local/bin/inngest-doublefire-probe.sh":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/etc/systemd/system/inngest-heartbeat.service.d/10-inngest-heartbeat-doppler-token.conf":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/etc/systemd/system/inngest-server.service.d/10-inngest-server-doppler-token.conf":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
    "/etc/systemd/system/inngest-redis.service.d/10-inngest-redis-doppler-token.conf":
        "FILE_MAP running-host artifact (#9151): never on the bake path; a rebuilt web-2 "
        "receives it via the sibling's host-id re-fire, not cloud-init.",
}

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
if len(wf_paths) >= 11:
    ok(f"0: parsed cloud-init write_files ({len(wf_paths)} paths)")
else:
    no(f"0: cloud-init write_files parsed to only {len(wf_paths)} paths (floor 11) -- extraction broken")

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

FLOOR_RESOURCES = 21  # +1 #9151: deploy_pipeline_fix_web2; +2 #9534: egress_gateway + egress_gateway_web2
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
#
# #9151 added a SECOND allowed destination: web-2. The set stays a closed enumeration —
# {web-1} plus {web-2} — because CI has exactly two SSH routes: direct to web-1 through the
# pinned bridge, and the web-1-bastion `ssh -L` forward to web-2's private IP
# (apply-deploy-pipeline-fix.yml, ADR-220). Any other address is an unrouted dial that hangs
# to the SSH timeout on every merge-triggered apply.
DIAL_W1 = r'host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address'
DIAL_W2 = r'host\s*=\s*hcloud_server\.web\["web-2"\]\.ipv4_address'
# `count` is the other fan-out/kill-switch meta-arg: `count = 0` silently disables the
# sibling with every row green; `count = 2` doubles the dial. Swept together.
fanned = [n for n, b in ssh_resources.items() if re.search(r'^\s*(for_each|count)\s*=', b, re.M)]
unpinned = [n for n, b in ssh_resources.items()
            if not (re.search(DIAL_W1, b) or re.search(DIAL_W2, b))]
if not fanned and not unpinned:
    ok(f"1: all {len(ssh_resources)} SSH provisioners pin a committed web host (web-1|web-2), none for_each'd or count'd")
else:
    no(f"1: fanned(for_each-or-count)={sorted(fanned)} not-web-1-or-web-2-pinned={sorted(unpinned)}. CI has TWO SSH "
       "routes (web-1 direct, web-2 via the web-1 bastion forward) and every resource is bare "
       "-target'ed, so a fan-out or a third host makes every merge-triggered apply dial a host "
       "it cannot reach and hang to the SSH timeout. See ADR-114's load-bearing constraint. If "
       "CI genuinely gained another route, the forward, the firewall and the -target lists "
       "must change FIRST, and this check with them.")

# The web-2 sibling class (#9151 / #7103-B4). The vetted web-2 dialer set is exactly two
# resources today: deploy_pipeline_fix_web2 and (#9534) egress_gateway_web2 — the latter
# delivers the squid gateway to the RUNNING web-2 (replace-only delivery would leave an
# entitled session on web-2 fail-closed until its next -replace). A web-2 dialer MUST pin
# local.web_2_ssh_host_key (Guard 2's per-host rule asserts the twin from the connection
# side; this side pins it from the resource census, so deleting EITHER local reference reds
# here). It must NEVER carry the credential material web-1 receives: the full-prd Doppler
# token, its .tmpl, or the push plumbing. A copy-pasted infra_config_handler_bootstrap
# carries all three — the failure that puts the prd credential on a host the issue
# explicitly scopes out of this change.
W2_DIALERS = [n for n, b in ssh_resources.items() if re.search(DIAL_W2, b)]
W2_ALLOWED = {"deploy_pipeline_fix_web2", "egress_gateway_web2"}
w2_bad_key = [n for n in W2_DIALERS
              if not re.search(r'host_key\s*=\s*local\.web_2_ssh_host_key', ssh_resources[n])]
# Credential-boundary token set, widened at review: a bare `doppler_token` covers
# var.doppler_token, webhook_doppler_token_env AND the pre-encoded twin
# soleur_doppler_token_env_b64; `DOPPLER_TOKEN` covers the env spellings.
# `soleur-doppler-token` keeps the hyphenated .tmpl/path name. `doppler-token`
# (bare hyphen) would false-positive on the legitimate `10-*-doppler-token.conf`
# drop-ins, so it is deliberately absent — those files point units AT the
# credential path; they do not carry the value.
W2_CRED_RE = r'doppler_token|DOPPLER_TOKEN|soleur-doppler-token|push-infra-config'
w2_creds = [n for n in W2_DIALERS if re.search(W2_CRED_RE, ssh_resources[n])]
w2_named = "deploy_pipeline_fix_web2" in W2_DIALERS
if w2_named and not w2_bad_key and not w2_creds and set(W2_DIALERS) == W2_ALLOWED:
    ok(f"1: web-2 siblings {sorted(W2_ALLOWED)} pin local.web_2_ssh_host_key and carry no credential material "
       f"(exactly {len(W2_ALLOWED)} web-2 dialers)")
else:
    no(f"1: web-2 sibling class broken: vetted={sorted(W2_ALLOWED)}, "
       f"web-2 dialers={sorted(W2_DIALERS)}, wrong-or-missing web_2 host_key={sorted(w2_bad_key)}, "
       f"credential-material references={sorted(w2_creds)}. "
       "Web-2 dialers must be exactly the vetted set, must pin local.web_2_ssh_host_key, and must "
       "never reference the prd credential under any spelling "
       "(var.doppler_token / webhook_doppler_token_env / soleur_doppler_token_env_b64 / "
       "SOLEUR_DOPPLER_TOKEN / soleur-doppler-token / push-infra-config).")
# #8609 (plan 1.4): the GitHub App key read token rides the SAME credential file web-2 does not
# receive in place, so the denylist above needs no change — but only while every spelling of the
# new credential falls inside it. Pinned: the pattern is byte-unchanged and matches each spelling
# (the variable, its TF_VAR_ export, the rendered env line), so narrowing it reds here.
_w2_new_spellings = ["var.github_app_runtime_doppler_token", "TF_VAR_github_app_runtime_doppler_token",
                     "GITHUB_APP_DOPPLER_TOKEN"]
_w2_missed = [t for t in _w2_new_spellings if not re.search(W2_CRED_RE, t)]
if W2_CRED_RE == r'doppler_token|DOPPLER_TOKEN|soleur-doppler-token|push-infra-config' and not _w2_missed:
    ok("1: web-2's credential denylist is unchanged and covers every spelling of the #8609 App-key read token")
else:
    no(f"1: web-2's credential denylist changed or misses the #8609 App-key read token: missed={_w2_missed}")
# The webhook channel twin: hooks.json rides the sibling's sanctioned base64 delivery
# to /etc/webhook/hooks.json, and web-1 legitimately receives it. If the template's
# argument map gains a doppler/token reference, a rendered credential reaches web-2
# through a channel the block-level grep cannot see. The arg map itself may not
# name one. (A `soleur_doppler_token_b64` PAYLOAD KEY inside hooks.json.tmpl is the
# armed-but-unreachable mapping — a name, not a value; asserted separately.)
_hooks_args = re.search(r'hooks_json\s*=\s*templatefile\([^,]+,\s*\{(.*?)\}', srv, re.S)
hooks_injected = bool(_hooks_args and re.search(r'(?i)doppler|token\b',
                                              re.sub(r'\bwebhook_deploy_secret\b', '',
                                                     _hooks_args.group(1))))
if _hooks_args is not None and not hooks_injected:
    ok("1: hooks.json's templatefile arg map carries no credential reference beyond webhook_deploy_secret")
else:
    no(f"1: hooks_json templatefile args gained a credential reference — a rendered value would "
       f"ride the sanctioned base64 delivery to web-2: {_hooks_args.group(1) if _hooks_args else 'hooks_json local not found'!r}")

# ── §2. Destination sweep: the load-bearing invariant ────────────────────────────────
# ASYMMETRY (the v2 defect, and the reason this is shaped the way it is). The two halves of
# the derivation fail in OPPOSITE directions:
#   * EXTRACTION ("what do the 17 write?") -- a miss is SILENT: the destination never enters
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
    out, interpolated, unresolvable, script_args = set(), set(), set(), set()
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
    # `script`/`scripts` provisioner args upload-and-run files whose bodies write
    # arbitrary paths -- the inline sweep cannot see them. None is used in this
    # fleet today; report them rather than let a new one slip under the sweep
    # (review enumeration 2a). Reported through their own channel: they are not
    # `destination =` attributes.
    for s in re.findall(r'^[ \t]*scripts?\s*=\s*(\S+)', body, re.M):
        script_args.add(s)
    # The array terminator tolerates the same-line form `inline = ["a"]`: a `]` is the
    # real terminator only when a newline, comma or `}` follows (a `]` inside a quoted
    # string is followed by more string bytes). A trailing single-line inline in the
    # LAST provisioner previously produced no `\n\s*\]` at all and left the sweep
    # silently (review enumeration 2b).
    for arr in re.findall(r'inline\s*=\s*\[(.*?)\](?=\s*[\n,}])', body, re.S):
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
            unresolvable,
            script_args)

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
    dests, interpolated, unresolvable, script_args = destinations(body)
    for d in sorted(script_args):
        no(f"2: {name} uses remote-exec `{d.split('=')[0].strip()}` ({d}) -- an uploaded script "
           "writes arbitrary paths that the destination sweep cannot see. Deliver through `file` "
           "provisioners + `inline` remote-exec so every destination is swept.")
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
# 57 -> 59 in #7539. The Vector-reload hardening added two destinations to
# journald_persistent: /etc/vector/vector.toml.prev (the rotation backup, ALLOWLISTed above)
# and /usr/local/bin/vector. The second is an over-extraction -- the provisioner only TESTS
# (`[ ! -x ]`) and INVOKES (`vector validate`) that path, it never delivers it -- but this
# extractor is fail-closed by over-extraction by design, and the path is genuinely installed
# on the fresh-boot path by soleur-host-bootstrap.sh, so it clears §2 truthfully rather than
# needing an exception. Measured, not assumed: origin/main sweeps 57, this tree sweeps 59.
FLOOR_DESTS = 79  # +16 #9151: the web-2 sibling's destinations not already swept via the web-1 bridge (7 FILE_MAP scripts, 4 drop-in confs, 5 others — measured, margin-zero); +4 #9534: egress_gateway writes (squid.conf, auth helper, deny CIDRs, bootstrap script)
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

# REACHABILITY PROBE (#7014 gap 2). The hygiene checks above remain STRUCTURALLY UNREACHABLE
# from the mutation battery: no edit to the four input FILES can add, remove or corrupt an
# ALLOWLIST entry, so the checks could be deleted with the battery still reporting a full pass.
# They would assert nothing. This env var feeds a synthetic entry set through the SAME function
# so both arms can be proven to fire.
#
# Until #7539 this note justified itself with "ALLOWLIST is empty -- which is the correct
# state". The list is no longer empty, and that clause was never the load-bearing one anyway:
# unreachability follows from the battery mutating FILES while the list lives in this script,
# which holds at any cardinality. The stale half is removed rather than re-stated.
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
main_rc=$?

# ── GUARD 2 (#7226 / #8125 / #9151, ADR-237): every Terraform SSH connection block pins the host key ──
# PROPERTY. Every `connection {}` block (type "ssh", which is also Terraform's default) in any
# `.tf` or `.tf.json` file of the repository sets EXACTLY ONE `host_key`, and that value is in
# the ALLOW-SET below ({web-1, web-2} pins since #9151; git-data's pin joins it when a
# connection block dials git-data). `null`, `""` and any other expression are outside the set.
# A block whose host is hcloud_server.web["web-1"] must use `local.web_1_ssh_host_key`
# specifically, and one whose host is hcloud_server.web["web-2"] must use
# `local.web_2_ssh_host_key` (whitespace inside the reference is normalised away before the
# match). Without host_key, Terraform's Go client accepts whatever key the peer presents on
# every provisioner run, the same TOFU the bash bridge had (#7226).
#
# UNIVERSE. `git ls-files --cached --others --exclude-standard -- '*.tf' '*.tf.json'` at the
# repository root (tracked files plus new files not yet added), so a connection block in ANY
# Terraform root -- apps/*/infra, infra/github, a new root nobody listed -- is swept. The
# §0-§5 parity program above reads the web-platform infra directory only; this one does not.
#
# PER BLOCK, not a comparison of totals: moving a host_key from one block into another keeps the
# totals equal and must still go RED (one block has 0, the other 2). The walker strips comments
# first, so tunnel.tf's prose mention of `connection { host }` is not a block. .tf.json files are
# parsed as JSON and every `connection` object (or list of objects) at any depth is a block.
#
# Floors: at least 23 blocks (19 in server.tf incl. web_1_host_key_probe, 1 in
# ci-ssh-key.tf, 3 in workspaces-luks.tf) and at least 70 scanned files. The local
# must be defined exactly once, from
# the committed pin. SOLEUR_TF_REPO overrides the repository root for the mutation battery, which
# builds a scratch repository whose apps/web-platform/infra IS the SOLEUR_INFRA_DIR sandbox.
TF_REPO="${SOLEUR_TF_REPO:-$ROOT}"
python3 - "$TF_REPO" "$INFRA" <<'G2EOF'
import json, pathlib, re, subprocess, sys

REPO = pathlib.Path(sys.argv[1]).resolve()
INFRA = pathlib.Path(sys.argv[2]).resolve()
ALLOWED_HOST_KEYS = {"local.web_1_ssh_host_key", "local.web_2_ssh_host_key"}
npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

# HCL comment stripping: `#`, `//` and `/* */` outside double-quoted strings. Newlines inside a
# block comment are kept so reported line numbers stay true.
def strip_hcl(text):
    out = []; i = 0; n = len(text); in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == '#' or text.startswith('//', i):
            while i < n and text[i] != '\n': i += 1
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append('\n' * text.count('\n', i, j)); i = j; continue
        out.append(c); i += 1
    return ''.join(out)

def block_body(text, start):
    """Body of the brace block whose `{` is at text[start-1]; string-aware."""
    i = start; depth = 1; in_str = False
    while i < len(text) and depth > 0:
        c = text[i]
        if in_str:
            if c == '\\': i += 2; continue
            if c == '"': in_str = False
        elif c == '"': in_str = True
        elif c == '{': depth += 1
        elif c == '}': depth -= 1
        i += 1
    return text[start:i - 1]

if INFRA != REPO / "apps/web-platform/infra":
    no(f"G2: the analysed infra dir {INFRA} is not <repo>/apps/web-platform/infra under {REPO}; "
       "Guard 2 would sweep a different server.tf than the parity program")
ls = subprocess.run(["git", "-C", str(REPO), "ls-files", "-z", "--cached", "--others",
                     "--exclude-standard", "--", "*.tf", "*.tf.json"],
                    capture_output=True, text=True)
if ls.returncode != 0:
    no(f"G2: git ls-files failed under {REPO}: {ls.stderr.strip()}")
files = sorted({REPO / p for p in ls.stdout.split("\0") if p and ".terraform/" not in p})
FLOOR_FILES = 70
if len(files) >= FLOOR_FILES:
    ok(f"G2: scanned {len(files)} .tf/.tf.json files (floor {FLOOR_FILES})")
else:
    no(f"G2: scanned only {len(files)} .tf/.tf.json files (floor {FLOOR_FILES}) -- the walk is broken")

def json_blocks(node, path):
    """Every `connection` value in a .tf.json document, at any depth."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "connection":
                for i, c in enumerate(v if isinstance(v, list) else [v]):
                    yield (f"{path}.connection[{i}]", c)
            else:
                yield from json_blocks(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from json_blocks(v, f"{path}[{i}]")

blocks = []   # (file:line, body-or-dict)
local_defs = []   # web_1_ssh_host_key definitions
local_defs_2 = [] # web_2_ssh_host_key definitions (#9151)
for f in files:
    raw = f.read_text()
    rel = f.relative_to(REPO)
    if f.name.endswith(".tf.json"):
        try:
            doc = json.loads(raw)
        except ValueError as e:
            no(f"G2: {rel} is not valid JSON ({e}); its connection blocks cannot be checked")
            continue
        for loc, c in json_blocks(doc, ""):
            blocks.append((f"{rel}:{loc}", c))
        def defines_local(node, key):
            if isinstance(node, dict):
                return key in node or any(defines_local(v, key) for v in node.values())
            if isinstance(node, list):
                return any(defines_local(v, key) for v in node)
            return False
        if defines_local(doc, "web_1_ssh_host_key"):
            local_defs.append((f"{rel}:json", ""))
        if defines_local(doc, "web_2_ssh_host_key"):
            local_defs_2.append((f"{rel}:json", ""))
        continue
    src = strip_hcl(raw)
    for m in re.finditer(r'(?<![\w.])connection\s*\{', src):
        line = src.count('\n', 0, m.start()) + 1
        blocks.append((f"{rel}:{line}", block_body(src, m.end())))
    for m in re.finditer(r'(?m)^\s*web_1_ssh_host_key\s*=', src):
        line = src.count('\n', 0, m.start()) + 1
        # Bound at the END OF THE LOCALS BLOCK, not a fixed width: the web-2 twin lives in a
        # sibling `locals {}` block, and a fixed 600-char window let web-2's `one(` mask a
        # mutation that removed it from web-1's expression (G2-7).
        end = src.find("\n}", m.end())
        local_defs.append((f"{rel}:{line}", src[m.end():end if end != -1 else m.end() + 600]))
    for m in re.finditer(r'(?m)^\s*web_2_ssh_host_key\s*=', src):
        line = src.count('\n', 0, m.start()) + 1
        end = src.find("\n}", m.end())
        local_defs_2.append((f"{rel}:{line}", src[m.end():end if end != -1 else m.end() + 600]))

def is_winrm(b):
    if isinstance(b, dict):
        return b.get("type") == "winrm"
    return bool(re.search(r'(?m)^\s*type\s*=\s*"winrm"', b))

ssh_blocks = [(loc, b) for loc, b in blocks if not is_winrm(b)]
FLOOR_BLOCKS = 23  # +1 #9151: deploy_pipeline_fix_web2; measured 23 = 19 server.tf + 1 ci-ssh-key.tf + 3 workspaces-luks.tf (#8632/#8706/#9123)
if len(ssh_blocks) >= FLOOR_BLOCKS:
    ok(f"G2: swept {len(ssh_blocks)} SSH connection blocks (floor {FLOOR_BLOCKS})")
else:
    no(f"G2: swept only {len(ssh_blocks)} SSH connection blocks (floor {FLOOR_BLOCKS}). A block "
       "was removed or the walker broke -- check which before editing this floor.")

# host_key values, normalised: HCL `local.x` stays as written; a JSON "${local.x}" template is
# unwrapped to the same expression; JSON null and "" become the HCL spellings `null` / `""`.
def host_keys(b):
    if isinstance(b, dict):
        if "host_key" not in b:
            return []
        v = b["host_key"]
        if v is None:
            return ["null"]
        if isinstance(v, str):
            m = re.fullmatch(r'\$\{\s*(.*?)\s*\}', v)
            return [m.group(1) if m else json.dumps(v)]
        return [json.dumps(v)]
    return re.findall(r'(?m)^\s*host_key\s*=\s*(.+?)\s*$', b)

def dials_web_1(b):
    text = json.dumps(b) if isinstance(b, dict) else b
    return 'hcloud_server.web["web-1"]' in re.sub(r'\s+', '', text).replace('\\"', '"')

def dials_web_2(b):
    text = json.dumps(b) if isinstance(b, dict) else b
    return 'hcloud_server.web["web-2"]' in re.sub(r'\s+', '', text).replace('\\"', '"')

bad_count, bad_value, bad_web1, bad_web2 = [], [], [], []
for loc, b in ssh_blocks:
    keys = host_keys(b)
    if len(keys) != 1:
        bad_count.append(f"{loc} (host_key x{len(keys)})")
        continue
    if keys[0] not in ALLOWED_HOST_KEYS:
        bad_value.append(f"{loc} (host_key = {keys[0]})")
    if dials_web_1(b) and keys[0] != "local.web_1_ssh_host_key":
        bad_web1.append(f"{loc} (host_key = {keys[0]})")
    if dials_web_2(b) and keys[0] != "local.web_2_ssh_host_key":
        bad_web2.append(f"{loc} (host_key = {keys[0]})")
if not bad_count:
    ok(f"G2: every one of the {len(ssh_blocks)} SSH connection blocks sets exactly one host_key")
else:
    no("G2: connection block without exactly one host_key: " + ", ".join(bad_count) + ". Every "
       "Terraform SSH connection must pin the peer's host key (ADR-237); a web-N block uses "
       "`host_key = local.web_N_ssh_host_key`.")
if not bad_value:
    ok(f"G2: every host_key is in the allow-set {sorted(ALLOWED_HOST_KEYS)}")
else:
    no("G2: host_key outside the allow-set " + str(sorted(ALLOWED_HOST_KEYS)) + ": "
       + ", ".join(bad_value) + ". null, \"\" or an ad-hoc expression disables or bypasses the pin; "
       "add a new pin local to ALLOWED_HOST_KEYS (with review) instead.")
if not bad_web1:
    ok("G2: every web-1 connection block pins host_key to local.web_1_ssh_host_key")
else:
    no("G2: web-1 connection block pins host_key to something other than "
       "local.web_1_ssh_host_key: " + ", ".join(bad_web1))
if not bad_web2:
    ok("G2: every web-2 connection block pins host_key to local.web_2_ssh_host_key")
else:
    no("G2: web-2 connection block pins host_key to something other than "
       "local.web_2_ssh_host_key: " + ", ".join(bad_web2))

# Web-2 dialer residence (review enumeration): §1's sibling census reads server.tf
# only, so a terraform_data dialing web["web-2"] born in another .tf/.tf.json would
# face host_key rules here but escape the credential-boundary and destination
# checks entirely. Assert every web-2-dialing connection block lives in
# apps/web-platform/infra/server.tf; §1 then pins it to the sibling alone.
w2_elsewhere = [loc for loc, b in ssh_blocks
                if dials_web_2(b) and not loc.startswith("apps/web-platform/infra/server.tf:")]
if not w2_elsewhere:
    ok("G2: every web-2-dialing connection block lives in apps/web-platform/infra/server.tf")
else:
    no("G2: web-2-dialing connection block(s) outside server.tf — they escape the "
       "sibling-class credential/destination checks in §1: " + ", ".join(w2_elsewhere))

# The local is the ONE place the committed pin enters Terraform: defined once, read from the
# committed file, through one() (exactly one key line) and the anchored ECDSA-P256 regex().
if len(local_defs) != 1:
    no(f"G2: local.web_1_ssh_host_key must be defined exactly once, found {len(local_defs)}: "
       + ", ".join(l for l, _ in local_defs))
else:
    loc, rhs = local_defs[0]
    want = [r'^\s*regex\(', r'\^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB\[A-Za-z0-9\+/\]\{86\}=\$',
            r'\bone\(', r'file\("\$\{path\.module\}/web-1-ssh-host-key\.pub"\)']
    missing = [w for w in want if not re.search(w, rhs)]
    if not missing:
        ok(f"G2: local.web_1_ssh_host_key ({loc}) is regex(ECDSA-P256, one(<committed pin lines>))")
    else:
        no(f"G2: local.web_1_ssh_host_key ({loc}) lost its shape; missing {missing}")

# web-2 twin (#9151): same once-defined + anchored-shape contract, against its own pin file.
if len(local_defs_2) != 1:
    no(f"G2: local.web_2_ssh_host_key must be defined exactly once, found {len(local_defs_2)}: "
       + ", ".join(l for l, _ in local_defs_2))
else:
    loc, rhs = local_defs_2[0]
    want = [r'^\s*regex\(', r'\^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB\[A-Za-z0-9\+/\]\{86\}=\$',
            r'\bone\(', r'file\("\$\{path\.module\}/web-2-ssh-host-key\.pub"\)']
    missing = [w for w in want if not re.search(w, rhs)]
    if not missing:
        ok(f"G2: local.web_2_ssh_host_key ({loc}) is regex(ECDSA-P256, one(<committed pin lines>))")
    else:
        no(f"G2: local.web_2_ssh_host_key ({loc}) lost its shape; missing {missing}")

print(f"=== web-host-provisioner-parity Guard 2: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
G2EOF
g2_rc=$?
[[ "$main_rc" -eq 0 && "$g2_rc" -eq 0 ]]
