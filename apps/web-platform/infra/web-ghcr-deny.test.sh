#!/usr/bin/env bash
# Guard 2 (#9169, plan 2026-09-30-infra-deny-ghcr-on-web-hosts): every copy of the ghcr.io
# hosts-file deny that can reach a web host is the registry's runcmd entry, byte for byte, and
# every running-host route hashes AND runs it in a dedicated, secret-free, last remote-exec block.
#
#   copy R  cloud-init-registry.yml's runcmd entry (the byte source; zot-image-fetch.test.sh R10
#           proves its executed effect). Read-only here: that host's user_data is ForceNew.
#   copy A  cloud-init.yml's runcmd[1] (fresh/replaced web hosts), right after the trap arm.
#   copy B  server.tf local.ghcr_deny_sh (+ local.ghcr_deny_assert_sh), run on the RUNNING hosts
#           by zot_consumer_probe_install (web-1) and deploy_pipeline_fix_web2 (web-2).
#
# Checks (each takes a root dir, so the in-suite mutation battery can point it at a sandbox):
#   parity    A == B == R, whole entry, parsed (render -> yaml.safe_load; terraform console), on
#             BOTH web_tunnel_connector arms (web-1 is born with true, web-2 with false)
#   order     runcmd[0] is the trap arm, runcmd[1] is the one deny entry (both arms)
#   exec      copy B runs under sh + set -e against temp files: one 0.0.0.0 and one :: line per
#             name, idempotent, unrelated lines untouched, an existing entry not duplicated
#   agree     the three "resolves ONLY to the sinkhole" implementations (registry heartbeat,
#             ci-deploy.sh _ghcr_blocked_state, the apply-time assertion) on per-name getent shims
#   wiring    both consumers: the locals in triggers_replace AND a last remote-exec block that runs
#             exactly ["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh]; no count/for_each/
#             lifecycle on either; var.web_hosts names exactly the hosts those two routes reach; and
#             hcloud_server.web's user_data is the plain cloud-init.yml render
#   census    across the infra .tf/.sh/.yml/.tmpl files: the deny loop header appears only in its
#             three sanctioned copies, and nothing writes /etc/hosts or cloud-init's hosts template
#   probe     the rehearsal's dockerd deny probe (#9799 item 5), static over zot-image-rehearse.sh: one pull,
#             inside assert_dockerd_denied, after a >= 6 s sleep, output kept, the call after the deny and ending in
#             `|| die`
#
# The render/console half needs terraform: SKIP locally without it, FAIL CLOSED under CI.
# Every fixture is synthesized (cq-test-fixtures-synthesized-only).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETIRE="the deny must move to the successor route or be retired with it (active-active Phase 5, ADR-143); cloud-init copy A is the end state"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
# Instrument self-test BEFORE anything is measured: both helpers must move their counters. Output
# suppressed so the deliberate FAIL line cannot lead a runner's failure excerpt.
pass "instrument: pass() counts" >/dev/null
fail "instrument: fail() counts" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] instrument: pass/fail counters did not move (pass=%s fail=%s)\n' "$PASS" "$FAIL" >&2; exit 2
fi
PASS=0; FAIL=0

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/web-ghcr-deny.XXXXXX")" || exit 2
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
harness() { printf '[HARNESS] %s\n' "$1" >&2; exit 2; }

if ! command -v terraform >/dev/null 2>&1; then
  if [[ -n "${CI:-}" ]]; then harness "terraform is REQUIRED in CI (a silent skip would be vacuous)"; fi
  echo "  SKIP: terraform not on PATH (local dev; fails closed in CI) — Guard 2 not run"
  exit 0
fi

# ── python helpers ──────────────────────────────────────────────────────────────────────────────
assert_fixture_dir "$WORK"
cat > "$WORK/g2.py" <<'PY'
import base64, os, re, sys, yaml

HDR = "for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do"
LOC_START = re.compile(r"^\s*ghcr_deny_sh\s*=\s*<<-EOT\s*$")
ASSERT_START = re.compile(r"^\s*ghcr_deny_assert_sh\s*=\s*<<-EOT\s*$")
EOT = re.compile(r"^\s*EOT\s*$")
# A shell loop over the deny's names, in either order (`for h in ... ; do`). A string that merely
# NAMES the header (zot-image-rehearse.sh finds the registry entry by it) is not a loop.
DENY_LOOP = re.compile(r"\bfor\s+h\s+in\s+[^;\n\"']*\b(?:ghcr\.io|pkg-containers\.githubusercontent\.com|docker\.pkg\.github\.com)\b[^;\n\"']*;\s*do\b")
# A write to the hosts file or cloud-init's hosts template, in any of the usual shell shapes, plus a
# FILE_MAP destination (infra-config-apply.sh's `B64|/dest|mode|owner` rows).
HOSTS_WRITE = re.compile(
    r"(?:>>?|\btee\b(?:\s+-a)?|\bsed\s+(?:-[a-zA-Z]*i|--in-place)\S*|\b(?:cp|mv|install|ln|truncate)\b)"
    r"[^;&|\n]*?/etc/+(?:host|cloud/+templates/+host)"
    r"|\|\s*/etc/+(?:host|cloud/+templates/+host)[^|]*\|")
CENSUS_EXT = (".tf", ".sh", ".yml", ".yaml", ".tmpl")

def runcmd(src_b64, out_dir):
    """Rendered template (base64) -> out_dir/idx (deny entry index), out_dir/A, out_dir/r0."""
    body = base64.b64decode(open(src_b64).read().strip().strip('"')).decode()
    items = yaml.safe_load(body)["runcmd"]
    hits = [i for i, e in enumerate(items) if isinstance(e, str) and HDR in e]
    open(os.path.join(out_dir, "count"), "w").write(str(len(hits)))
    open(os.path.join(out_dir, "idx"), "w").write(str(hits[0]) if hits else "-1")
    open(os.path.join(out_dir, "A"), "w").write(items[hits[0]] if hits else "")
    r0 = items[0] if items and isinstance(items[0], str) else ""
    open(os.path.join(out_dir, "r0"), "w").write(r0)

def deny_span(L):
    """(first, last) line index of the two ghcr_deny locals, or None."""
    s = next((i for i, l in enumerate(L) if LOC_START.match(l)), None)
    a = next((i for i, l in enumerate(L) if ASSERT_START.match(l)), None)
    if s is None or a is None or a < s:
        return None
    e = next((j for j in range(a + 1, len(L)) if EOT.match(L[j])), None)
    return (s, e) if e is not None else None

def locals_block(tf, out):
    L = open(tf).read().split("\n")
    sp = deny_span(L)
    open(out, "w").write("locals {\n" + "\n".join(L[sp[0]:sp[1] + 1]) + "\n}\n" if sp else "")

def strip_comments(t):
    return "\n".join(l for l in t.split("\n") if not l.lstrip().startswith("#"))

def span(src, kind, name):
    m = re.search(r'^resource "%s" "%s" \{\n(.*?)^\}\n' % (kind, re.escape(name)), src, re.S | re.M)
    return strip_comments(m.group(1)) if m else None

DEDICATED = 'provisioner "remote-exec" { inline = [ "set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh, ] }'
CONSUMERS = {"zot_consumer_probe_install": "web-1", "deploy_pipeline_fix_web2": "web-2"}

def wiring(root):
    src = open(os.path.join(root, "server.tf")).read()
    bad = []
    for name, host in CONSUMERS.items():
        b = span(src, "terraform_data", name)
        if b is None:
            bad.append("%s: resource not found" % name); continue
        if re.search(r"^\s*(count|for_each)\s*=|^\s*lifecycle\s*\{", b, re.M):
            bad.append("%s: carries count/for_each/lifecycle, which can disable or freeze the deny route" % name)
        if 'hcloud_server.web["%s"].ipv4_address' % host not in b:
            bad.append("%s: its connection no longer reaches %s" % (name, host))
        tr = re.search(r'triggers_replace = sha256\(join\(",", \[\n(.*?)^\s*\]\)\)', b, re.S | re.M)
        trl = [l.strip() for l in tr.group(1).split("\n")] if tr else []
        for want in ("local.ghcr_deny_sh,", "local.ghcr_deny_assert_sh,"):
            if want not in trl:
                bad.append("%s: %s missing from triggers_replace (the deny text must move the hash)" % (name, want[:-1]))
        # Every provisioner, one-line or multi-line, at any indentation.
        starts = [m.start() for m in re.finditer(r'^\s*provisioner\s+"', b, re.M)]
        if not starts:
            bad.append("%s: no provisioner blocks" % name); continue
        blocks = [b[s:e] for s, e in zip(starts, starts[1:] + [len(b)])]
        if " ".join(blocks[-1].split()) != DEDICATED:
            bad.append("%s: the LAST provisioner must be exactly %s; got: %s" % (name, DEDICATED, " ".join(blocks[-1].split())[:140]))
        for blk in blocks[:-1]:
            if "ghcr_deny" in blk:
                bad.append("%s: the deny locals appear in a non-dedicated provisioner block" % name)
    # The two routes are singletons; a host they do not reach gets the deny only at birth.
    vt = open(os.path.join(root, "variables.tf")).read()
    m = re.search(r'^variable "web_hosts" \{\n(.*?)^\}\n', vt, re.S | re.M)
    keys = sorted(set(re.findall(r'^\s*"(web-[0-9]+)"\s*=\s*\{', m.group(1), re.M))) if m else []
    if keys != sorted(CONSUMERS.values()):
        bad.append("var.web_hosts names %s but the running-host deny routes reach %s — add a route for the new host" % (keys, sorted(CONSUMERS.values())))
    w = re.search(r'^resource "hcloud_server" "web" \{\n(.*?)^\}\n', src, re.S | re.M)
    if not w or not re.search(r'^\s*user_data\s*=\s*base64gzip\(templatefile\("\$\{path\.module\}/cloud-init\.yml",\s*\{\s*$', w.group(1), re.M):
        bad.append("hcloud_server.web user_data is no longer the plain base64gzip(templatefile(cloud-init.yml)) render copy A is proven against")
    print("\n".join("BAD " + x for x in bad) if bad else "OK")

def census(root):
    bad = []
    sanctioned = {("server.tf", "locals"): 0, ("cloud-init.yml", ""): 0, ("cloud-init-registry.yml", ""): 0}
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".terraform", "test", "tests", "fixtures")]
        for f in files:
            if not f.endswith(CENSUS_EXT) or ".test." in f:
                continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root)
            L = open(p, encoding="utf-8", errors="replace").read().split("\n")
            sp = deny_span(L) if rel == "server.tf" else None
            for n, l in enumerate(L):
                if l.lstrip().startswith("#"):
                    continue
                if HOSTS_WRITE.search(l):
                    bad.append("%s:%d writes the hosts file outside the deny: %s" % (rel, n + 1, l.strip()[:100]))
                if DENY_LOOP.search(l):
                    key = (rel, "locals") if sp and sp[0] <= n <= sp[1] else (rel, "")
                    if key in sanctioned:
                        sanctioned[key] += 1
                    else:
                        bad.append("%s:%d a deny loop outside its three sanctioned copies: %s" % (rel, n + 1, l.strip()[:100]))
    want = {("server.tf", "locals"): 2, ("cloud-init.yml", ""): 1, ("cloud-init-registry.yml", ""): 1}
    for k, v in want.items():
        if sanctioned[k] != v:
            bad.append("%s%s: %d deny loop header(s), want %d" % (k[0], " (ghcr_deny locals)" if k[1] else "", sanctioned[k], v))
    print("\n".join("BAD " + x for x in bad) if bad else "OK")

cmd = sys.argv[1]
if cmd == "runcmd": runcmd(sys.argv[2], sys.argv[3])
elif cmd == "locals": locals_block(sys.argv[2], sys.argv[3])
elif cmd == "wiring": wiring(sys.argv[2])
elif cmd == "census": census(sys.argv[2])
else: sys.exit(64)
PY

# ── extraction (each takes a root dir; writes under $WORK only) ───────────────────────────────────
tfconsole() {  # <scratch dir> <expr> <out> : the console's quoted base64 string, verbatim
  printf '%s\n' "$2" | terraform -chdir="$1" console > "$3" 2> "$3.err"
}
# render_a <root> <out dir> <web_tunnel_connector>: copy A + runcmd[0] + the deny entry's index.
render_a() {
  assert_fixture_dir "$WORK"; mkdir -p "$2" "$WORK/tfa"
  local expr
  expr=$(printf 'base64encode(templatefile("%s", { image_name="ghcr.io/jikig-ai/soleur-web-platform:v9.9.9", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="tt", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="https://k@o1.ingest.de.sentry.io/1", resend_api_key="r", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", workspaces_luks_fresh_boot_token="lt", registry_endpoint="10.0.1.30:5000", web_colocate_inngest=false, web_tunnel_connector=%s, host_name="soleur-web-2", private_ip="10.0.1.20", web_probes_token="t", expected_ip="10.0.1.20", web_host_key="web-2", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k", zot_pull_user="zot-pull", zot_pull_token="dkryFMT07elszGNU18fmtAHOV29gnuBIPW3ahovC" }))' "$1/cloud-init.yml" "$3")
  tfconsole "$WORK/tfa" "$expr" "$2/web.b64" || { printf 'render failed: %s' "$(head -c 300 "$2/web.b64.err")" > "$2/why"; return 1; }
  python3 "$WORK/g2.py" runcmd "$2/web.b64" "$2" || { echo "runcmd parse failed" > "$2/why"; return 1; }
}
# copy_b <root> <out dir>: out/deny.sh + out/assert.sh as terraform evaluates the two locals.
copy_b() {
  assert_fixture_dir "$WORK"; mkdir -p "$2" "$2/tf"
  : > "$2/deny.sh"; : > "$2/assert.sh"
  python3 "$WORK/g2.py" locals "$1/server.tf" "$2/tf/main.tf" || return 1
  [[ -s "$2/tf/main.tf" ]] || return 1
  tfconsole "$2/tf" 'base64encode(local.ghcr_deny_sh)' "$2/deny.b64" || return 1
  tfconsole "$2/tf" 'base64encode(local.ghcr_deny_assert_sh)' "$2/assert.b64" || return 1
  tr -d '"\n' < "$2/deny.b64" | base64 -d > "$2/deny.sh" || return 1
  tr -d '"\n' < "$2/assert.b64" | base64 -d > "$2/assert.sh" || return 1
}

# ── copy R (read once, from the real registry template; never mutated) ───────────────────────────
mkdir -p "$WORK/R"
bash "$DIR/registry-userdata-budget.sh" "$WORK/R/rendered.yml" > "$WORK/R/budget.log" 2>&1 \
  || harness "registry-userdata-budget.sh could not render copy R: $(tail -c 300 "$WORK/R/budget.log")"
base64 -w0 "$WORK/R/rendered.yml" > "$WORK/R/reg.b64"
python3 "$WORK/g2.py" runcmd "$WORK/R/reg.b64" "$WORK/R" || harness "copy R: registry runcmd did not parse"
[[ "$(cat "$WORK/R/count")" == 1 && -s "$WORK/R/A" ]] || harness "copy R: expected exactly one deny entry in the registry runcmd"
cp "$WORK/R/A" "$WORK/copyR"
# The registry heartbeat classifier (write_files, not runcmd): 5 lines from GHCR_BLOCKED=unknown.
awk '/^ *GHCR_BLOCKED=unknown$/{f=1} f{print; n++} n==5{exit}' "$DIR/cloud-init-registry.yml" \
  | sed -E 's/^ {6}//' > "$WORK/reg-classifier.sh"
[[ "$(sed -n 2p "$WORK/reg-classifier.sh")" == *'getent ahosts ghcr.io'* && "$(sed -n 5p "$WORK/reg-classifier.sh")" == "fi" ]] \
  || harness "could not extract the registry ghcr_blocked classifier (5 lines from GHCR_BLOCKED=unknown)"

same() { cmp -s "$1" "$2"; }

# ── the checks: each prints a reason and returns non-zero on failure ─────────────────────────────
chk_nonempty() {  # <root>
  render_a "$1" "$WORK/a-false" false || { echo "copy A: $(cat "$WORK/a-false/why" 2>/dev/null)"; return 1; }
  copy_b "$1" "$WORK/b"
  [[ -s "$WORK/a-false/A" && -s "$WORK/b/deny.sh" && -s "$WORK/b/assert.sh" && -s "$WORK/copyR" ]] \
    || { echo "a copy is EMPTY (A=$(wc -c < "$WORK/a-false/A") B=$(wc -c < "$WORK/b/deny.sh") assert=$(wc -c < "$WORK/b/assert.sh")); is the ghcr_deny_sh / ghcr_deny_assert_sh heredoc still named and closed?"; return 1; }
}
chk_parity() {  # <root>
  local arm
  for arm in false true; do
    render_a "$1" "$WORK/a-$arm" "$arm" || { echo "copy A (web_tunnel_connector=$arm): $(cat "$WORK/a-$arm/why" 2>/dev/null)"; return 1; }
    [[ "$(cat "$WORK/a-$arm/count")" == 1 ]] || { echo "copy A (web_tunnel_connector=$arm): expected exactly one deny entry (the three-name header), found $(cat "$WORK/a-$arm/count") -- the header drifted, so the entry cannot be compared"; return 1; }
    same "$WORK/a-$arm/A" "$WORK/copyR" || { echo "copy A (cloud-init.yml runcmd deny entry, web_tunnel_connector=$arm) differs from copy R (the registry entry)"; return 1; }
  done
  copy_b "$1" "$WORK/b"
  same "$WORK/b/deny.sh" "$WORK/copyR" || { echo "copy B (local.ghcr_deny_sh) differs from copy R"; return 1; }
  # The assertion is the only per-name proof on a running host, and nothing else derives its name list
  # from the deny loop's: a name added to the deny but not to the assertion would be denied unproven.
  local bn an
  bn=$(grep -m1 -oE 'for h in [^;]+; do' "$WORK/b/deny.sh"); an=$(grep -m1 -oE 'for h in [^;]+; do' "$WORK/b/assert.sh")
  [[ -n "$bn" && "$bn" == "$an" ]] || { echo "copy B: the assertion's name list ('$an') differs from the deny loop's ('$bn')"; return 1; }
}
chk_order() {  # <root>
  local arm
  for arm in false true; do
    render_a "$1" "$WORK/a-$arm" "$arm" || { echo "copy A (web_tunnel_connector=$arm): $(cat "$WORK/a-$arm/why" 2>/dev/null)"; return 1; }
    [[ "$(cat "$WORK/a-$arm/count")" == 1 ]] || { echo "web_tunnel_connector=$arm: expected exactly one deny entry in the web runcmd, found $(cat "$WORK/a-$arm/count")"; return 1; }
    grep -qxE '[[:space:]]*trap on_err EXIT' "$WORK/a-$arm/r0" || { echo "runcmd[0] must stay the #6090 trap-arm entry (an executed 'trap on_err EXIT' line)"; return 1; }
    [[ "$(cat "$WORK/a-$arm/idx")" == 1 ]] || { echo "web_tunnel_connector=$arm: the deny must be runcmd[1] (right after the trap arm), found at $(cat "$WORK/a-$arm/idx")"; return 1; }
  done
}
chk_exec() {  # <root> — copy B runs the way remote-exec runs it: POSIX sh, set -e first
  copy_b "$1" "$WORK/b" || { echo "copy B unreadable"; return 1; }
  local w="$WORK/exec" n rc
  assert_fixture_dir "$WORK"; rm -rf "$w"; mkdir -p "$w"
  sed -e "s#/etc/cloud/templates/hosts.debian.tmpl#$w/tmpl#g" -e "s#/etc/hosts#$w/hosts#g" "$WORK/b/deny.sh" > "$w/deny.sh"
  if grep -qE '/etc/hosts|/etc/cloud' "$w/deny.sh"; then echo "path substitution left a real path in the script; refusing to run it"; return 1; fi
  { echo 'set -e'; cat "$w/deny.sh"; } > "$w/run.sh"
  printf '127.0.0.1 localhost\n' > "$w/hosts"; printf '127.0.0.1 localhost\n' > "$w/tmpl"
  rc=0; sh "$w/run.sh" && sh "$w/run.sh" || rc=$?
  [[ "$rc" == 0 ]] || { echo "copy B exited $rc under sh + set -e"; return 1; }
  for f in hosts tmpl; do
    for n in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do
      [[ "$(grep -cxF "0.0.0.0 $n" "$w/$f")" == 1 && "$(grep -cxF ":: $n" "$w/$f")" == 1 ]] \
        || { echo "$f: want exactly one '0.0.0.0 $n' and one ':: $n' after two runs"; return 1; }
    done
    [[ "$(head -1 "$w/$f")" == "127.0.0.1 localhost" ]] || { echo "$f: an unrelated line was changed"; return 1; }
  done
  # An existing TAB-separated sinkhole entry is not duplicated; an absent template is skipped.
  rm -f "$w/tmpl"; printf '10.0.0.1 other\n0.0.0.0\tghcr.io\n' > "$w/hosts"
  rc=0; sh "$w/run.sh" || rc=$?
  [[ "$rc" == 0 && ! -e "$w/tmpl" && "$(grep -c 'ghcr\.io' "$w/hosts")" == 1 && "$(head -1 "$w/hosts")" == "10.0.0.1 other" \
    && "$(grep -c 'pkg-containers' "$w/hosts")" == 2 && "$(grep -c 'docker\.pkg\.github\.com' "$w/hosts")" == 2 ]] \
    || { echo "pre-seeded hosts: ghcr.io duplicated, an unrelated line changed, the absent template was created, or a name not appended exactly once (rc=$rc)"; return 1; }
}
chk_agree() {  # <root>
  copy_b "$1" "$WORK/b" || { echo "copy B unreadable"; return 1; }
  local s="$WORK/shim" row gh pk dk want_reg want_ci want_as reg ci as rc err exp_name bad=""
  assert_fixture_dir "$WORK"; mkdir -p "$s"
  cat > "$s/getent" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == ahosts && $# -eq 2 ]] || { echo "getent shim: unexpected argv: $*" >&2; exit 64; }
case "$2" in
  ghcr.io) v="${GE_GHCR-}" ;;
  pkg-containers.githubusercontent.com) v="${GE_PKG-}" ;;
  docker.pkg.github.com) v="${GE_DOCKERPKG-}" ;;
  *) echo "getent shim: unexpected name: $2" >&2; exit 64 ;;
esac
[[ -n "$v" ]] || exit 2
printf '%b' "$v"
EOF
  chmod +x "$s/getent"
  sed -n '/^_ghcr_blocked_state() {$/,/^}$/p' "$1/ci-deploy.sh" > "$WORK/ci-fn.sh"
  [[ -s "$WORK/ci-fn.sh" ]] || { echo "_ghcr_blocked_state not found in ci-deploy.sh"; return 1; }
  local SINK='0.0.0.0 STREAM x\n0.0.0.0 DGRAM\n:: STREAM\n' ROUT='140.82.121.34 STREAM x\n' \
    MIX='0.0.0.0 STREAM x\n140.82.121.34 STREAM\n' V6='2606:50c0:8000::154 STREAM x\n' LOOP='127.0.0.1 STREAM x\n'
  # ghcr | pkg | docker-pkg | registry | ci-deploy | assertion. The one-name-not-sinked rows are the
  # NAMED expected difference: both classifiers probe ghcr.io only (registry parity) while the
  # assertion checks all three names — so it must fail whichever of the three is not sinked.
  # Each implementation runs under its production shell: the registry heartbeat script is bash,
  # ci-deploy.sh is bash with set -euo pipefail, and a remote-exec inline script runs under sh.
  while IFS='|' read -r row gh pk dk want_reg want_ci want_as; do
    reg=$(env GE_GHCR="$gh" GE_PKG="$pk" GE_DOCKERPKG="$dk" PATH="$s:$PATH" bash -c ". '$WORK/reg-classifier.sh'; printf %s \"\$GHCR_BLOCKED\"" 2>/dev/null)
    ci=$(env GE_GHCR="$gh" GE_PKG="$pk" GE_DOCKERPKG="$dk" PATH="$s:$PATH" bash -euo pipefail -c ". '$WORK/ci-fn.sh'; _ghcr_blocked_state" 2>/dev/null)
    rc=0; env GE_GHCR="$gh" GE_PKG="$pk" GE_DOCKERPKG="$dk" PATH="$s:$PATH" sh -c "set -e; $(cat "$WORK/b/assert.sh")" >/dev/null 2>"$WORK/as.err" || rc=$?
    as=pass; [[ "$rc" == 0 ]] || as=fail
    err=""
    if [[ "$as" == fail ]] && ! grep -qE '^FATAL: .* \(#9169\)\. Route back: .*never gh run rerun --failed\.$' "$WORK/as.err"; then err=" (FATAL text/route-back missing)"; fi
    # The FATAL must name the host that actually failed, not just look like a FATAL.
    exp_name=""
    case "$row" in
      ghcr-sinked-pkg-routable) exp_name=pkg-containers.githubusercontent.com ;;
      ghcr-routable-pkg-sinked) exp_name=ghcr.io ;;
      dockerpkg-*) exp_name=docker.pkg.github.com ;;
    esac
    if [[ "$as" == fail && -n "$exp_name" ]] && ! grep -qF "FATAL: $exp_name does not resolve ONLY" "$WORK/as.err"; then err="$err (FATAL does not name $exp_name)"; fi
    if [[ "$reg" != "$want_reg" || "$ci" != "$want_ci" || "$as" != "$want_as" || -n "$err" ]]; then
      bad="$bad [$row: registry=$reg/$want_reg ci-deploy=$ci/$want_ci assert=$as/$want_as$err]"
    fi
  done <<EOF
sink-only|$SINK|$SINK|$SINK|1|1|pass
routable-v4|$ROUT|$ROUT|$ROUT|0|0|fail
sink+routable|$MIX|$MIX|$MIX|0|0|fail
routable-v6-with-::|$V6|$V6|$V6|0|0|fail
loopback-127|$LOOP|$LOOP|$LOOP|0|0|fail
unresolvable||||unknown|unknown|fail
ghcr-sinked-pkg-routable|$SINK|$ROUT|$SINK|1|1|fail
ghcr-routable-pkg-sinked|$ROUT|$SINK|$SINK|0|0|fail
dockerpkg-routable-others-sinked|$SINK|$SINK|$ROUT|1|1|fail
dockerpkg-unresolvable-others-sinked|$SINK|$SINK||1|1|fail
EOF
  [[ -z "$bad" ]] || { echo "classifier disagreement:$bad"; return 1; }
}
chk_wiring() {  # <root>
  local o; o=$(python3 "$WORK/g2.py" wiring "$1")
  [[ "$o" == OK ]] || { printf '%s — %s\n' "$(tr '\n' ';' <<<"$o")" "$RETIRE"; return 1; }
}
chk_census() {  # <root>
  local o; o=$(python3 "$WORK/g2.py" census "$1")
  [[ "$o" == OK ]] || { printf '%s — %s\n' "$(tr '\n' ';' <<<"$o")" "$RETIRE"; return 1; }
}
chk_probe() {  # <root>: the rehearsal's dockerd deny probe (#9799 item 5); static, over zot-image-rehearse.sh
  # Pins the dockerd probe's spelling and wiring, not every ghcr.io contact: the builder's curl calls run
  # before the deny on purpose and are not read here.
  local f="$1/zot-image-rehearse.sh" code body pulls n wait_s waits pull_ln sleep_ln deny_ln call_ln
  [[ -s "$f" ]] || { echo "zot-image-rehearse.sh is missing or empty"; return 1; }
  code=$(grep -nvE '^[[:space:]]*#' "$f")   # "<lineno>:<line>" for every non-comment line
  pulls=$(grep -E '\b(docker|dk)\b.*\bpull\b' <<<"$code" || true)
  n=$(grep -c . <<<"$pulls" || true)
  [[ "$n" == 1 ]] || { echo "expected exactly one non-comment docker/dk pull in zot-image-rehearse.sh, found $n"; return 1; }
  grep -qF '/dev/null' <<<"$pulls" && { echo "the docker pull discards its output (/dev/null): a recurrence of the bypass would be undiagnosable"; return 1; }
  pull_ln=${pulls%%:*}
  body=$(awk '/^assert_dockerd_denied\(\) \{/{f=1} f{print NR":"$0} f&&/^}/{exit}' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  [[ -n "$body" ]] || { echo "assert_dockerd_denied is missing"; return 1; }
  grep -qE "^${pull_ln}:" <<<"$body" || { echo "the docker pull (line ${pull_ln}) is not inside assert_dockerd_denied"; return 1; }
  waits=$(grep -c 'HOSTS_CACHE_WAIT_S=' <<<"$code" || true)
  [[ "$waits" == 1 ]] || { echo "HOSTS_CACHE_WAIT_S must be assigned exactly once (found $waits)"; return 1; }
  wait_s=$(sed -n 's/^HOSTS_CACHE_WAIT_S=\([1-9][0-9]*\)$/\1/p' "$f")
  [[ "$wait_s" =~ ^[1-9][0-9]*$ ]] || { echo "HOSTS_CACHE_WAIT_S is not a bare positive integer on a line of its own"; return 1; }
  (( wait_s >= 6 )) || { echo "HOSTS_CACHE_WAIT_S is $wait_s; it must be >= 6 (Go caches the hosts file for 5 s)"; return 1; }
  sleep_ln=$(grep -E '^[0-9]+:[[:space:]]+sleep "\$HOSTS_CACHE_WAIT_S"[[:space:]]*$' <<<"$body" | head -n 1); sleep_ln=${sleep_ln%%:*}
  [[ "$sleep_ln" =~ ^[0-9]+$ ]] && (( sleep_ln < pull_ln )) \
    || { echo "assert_dockerd_denied has no 'sleep \"\$HOSTS_CACHE_WAIT_S\"' before the docker pull (line ${pull_ln})"; return 1; }
  grep -qF '&& rc=0 || rc=$?' <<<"$body" || { echo "assert_dockerd_denied no longer captures the pull status with '&& rc=0 || rc=\$?'"; return 1; }
  grep -qE '^[0-9]+:[[:space:]]+return 1$' <<<"$body" || { echo "assert_dockerd_denied has no 'return 1' (a successful pull must fail the rehearsal)"; return 1; }
  deny_ln=$(grep -E '^[0-9]+:sudo sh "\$W/deny\.sh"[[:space:]]*$' <<<"$code" | head -n 1); deny_ln=${deny_ln%%:*}
  call_ln=$(grep -E '^[0-9]+:assert_dockerd_denied ' <<<"$code" | head -n 1); call_ln=${call_ln%%:*}
  [[ "$deny_ln" =~ ^[0-9]+$ && "$call_ln" =~ ^[0-9]+$ ]] && (( deny_ln < call_ln )) \
    || { echo "the assert_dockerd_denied call (line '${call_ln}') does not come after the deny application (line '${deny_ln}')"; return 1; }
  sed -n "${call_ln},$((call_ln + 1))p" "$f" | grep -qE '\|\| die "' \
    || { echo "the assert_dockerd_denied call (line ${call_ln}) no longer ends in '|| die': a successful pull would not fail the rehearsal"; return 1; }
}
CHECKS="nonempty parity order exec agree wiring census probe"

# ── the live tree ─────────────────────────────────────────────────────────────────────────────────
echo "--- Guard 2 on the live tree ---"
for c in $CHECKS; do
  why=$("chk_$c" "$DIR" 2>&1) && pass "$c" || fail "$c: $why"
done
if [[ "$FAIL" -ne 0 ]]; then
  # A red live tree would also red the battery's control; report the real failure, not a harness fault.
  echo "=== web-ghcr-deny: $PASS passed, $FAIL failed (mutation battery skipped: the live tree is red) ==="
  exit 1
fi

# ── in-suite mutation battery (sandbox copies; each row must red on its NAMED check) ──────────────
echo "--- Guard 2 mutation battery ---"
SB="$WORK/sb"
sandbox() {
  assert_fixture_dir "$SB"; assert_fixture_dir "$DIR"
  rm -rf "$SB"; mkdir -p "$SB"
  find "$DIR" -maxdepth 1 -type f ! -name '*.test.*' -exec cp -t "$SB/" {} +
  (cd "$DIR" && find . -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 -I{} cp --parents {} "$SB/")
}
sub() {  # <file> <old> <new> : literal, first occurrence; a missing anchor is a HARNESS fault
  python3 - "$SB/$1" "$2" "$3" <<'PY' || harness "mutation anchor not found in $1"
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s:
    sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
}
row() {  # <label> <check> <file mutated>
  if [[ -e "$DIR/$3" ]] && cmp -s "$DIR/$3" "$SB/$3"; then harness "row $1: the mutation did not land in $3"; fi
  if "chk_$2" "$SB" >/dev/null 2>&1; then fail "mutation SURVIVED: $1 (expected the $2 check to red)"
  else pass "mutation RED on $2: $1"; fi
  sandbox
}
sandbox
for c in $CHECKS; do "chk_$c" "$SB" >/dev/null 2>&1 || harness "control: the unmutated sandbox fails $c"; done
pass "control: the unmutated sandbox passes every check"

DENY_ENTRY_TAIL=$'    done\n  # #8651/#6438: converge'
DENY_BLOCK_TF=$'  provisioner "remote-exec" {\n    inline = [\n      "set -e",\n      local.ghcr_deny_sh,\n      local.ghcr_deny_assert_sh,\n    ]\n  }\n'
sub server.tf "printf '0.0.0.0 %s\n:: %s\n'" "printf '127.0.0.1 %s\n:: %s\n'"
row "1 0.0.0.0 -> 127.0.0.1 in copy B only" parity server.tf
sub cloud-init.yml "$DENY_ENTRY_TAIL" $'    done\n    : > /etc/hosts\n  # #8651/#6438: converge'
row "2 ': > /etc/hosts' appended as the last line of copy A's entry" parity cloud-init.yml
sub server.tf $'    local.ghcr_deny_sh,\n    local.ghcr_deny_assert_sh,\n    file("${path.module}/web-2-ssh-host-key.pub")' \
  $'    local.ghcr_deny_assert_sh,\n    file("${path.module}/web-2-ssh-host-key.pub")'
row "3 local.ghcr_deny_sh dropped from deploy_pipeline_fix_web2's triggers_replace" wiring server.tf
sub server.tf "$DENY_BLOCK_TF" ""
row "4 zot_consumer_probe_install's dedicated deny block deleted" wiring server.tf
sub server.tf "$DENY_BLOCK_TF" ""
sub server.tf $'      "systemctl list-timers web-zot-consumer-probe.timer --no-pager",\n' \
  $'      "systemctl list-timers web-zot-consumer-probe.timer --no-pager",\n      local.ghcr_deny_sh,\n      local.ghcr_deny_assert_sh,\n'
row "5 the deny locals moved INTO web-1's token-bearing block" wiring server.tf
assert_fixture_dir "$SB"
cat > "$SB/extra-deny.tf" <<'EOF'
resource "terraform_data" "handcopied_deny" {
  provisioner "remote-exec" {
    inline = ["for h in pkg-containers.githubusercontent.com ghcr.io; do printf '0.0.0.0 %s\\n' \"$h\" >> /etc/cloud/templates/hosts.debian.tmpl; done"]
  }
}
EOF
row "6 a hand-copied, name-reordered deny writing only the hosts template, in a second .tf" census extra-deny.tf
python3 - "$SB/cloud-init.yml" <<'PY' || harness "row 7/8 anchor missing"
import sys
p = sys.argv[1]; s = open(p).read()
start = s.index("  # #9169: ghcr.io deny")
end = s.index("  # #8651/#6438: converge")
blk = s[start:end]; s = s[:start] + s[end:]
nl = s.index("\n", s.index("  - networkctl reload")) + 1
open(p, "w").write(s[:nl] + blk + s[nl:])
PY
row "7 copy A moved to runcmd[2] (after networkctl reload)" order cloud-init.yml
python3 - "$SB/cloud-init.yml" <<'PY' || harness "row 8 anchor missing"
import sys
p = sys.argv[1]; s = open(p).read()
start = s.index("  # #9169: ghcr.io deny")
end = s.index("  # #8651/#6438: converge")
blk = s[start:end]; s = s[:start] + s[end:]
at = s.index("  # (#6090 follow-up) Arm the baked")
open(p, "w").write(s[:at] + blk + s[at:])
PY
row "8 copy A moved above the trap-arm entry" order cloud-init.yml
sub server.tf 'if [ -z "$a" ] || printf' 'if [ -n "$a" ] && printf'
row "9 the assertion weakened so an unresolvable name passes" agree server.tf
sub ci-deploy.sh "grep -qvxE '0\\.0\\.0\\.0|::'" "grep -qvE '0\\.0\\.0\\.0|::'"
row "10 -x dropped from _ghcr_blocked_state's whole-value match" agree ci-deploy.sh
sub server.tf "  ghcr_deny_sh        = <<-EOT" "  ghcr_deny_shx       = <<-EOT"
row "11 the heredoc renamed, so the console read of copy B is empty" nonempty server.tf
sub server.tf "$DENY_BLOCK_TF" "$DENY_BLOCK_TF"$'  provisioner "remote-exec" { inline = ["sed -i /ghcr/d /etc/host?"] }\n'
row "12 a one-line provisioner after web-1's deny block that undoes it" wiring server.tf
sub ci-deploy.sh "unset _ghcr_blocked" $'unset _ghcr_blocked\nfor h in ghcr.io; do printf \'127.0.0.1 %s\\n\' "$h" >> /etc/hosts; done'
row "13 a drifted 127.0.0.1 deny in a host script (ci-deploy.sh)" census ci-deploy.sh
sub server.tf '      a=$(timeout 10 getent ahosts "$h" | awk' '      a=$(timeout 10 getent ahosts pkg-containers.githubusercontent.com | awk'
row "14 the assertion stops probing ghcr.io itself" agree server.tf
sub server.tf "grep -cvxE '0\\.0\\.0\\.0|::' >/dev/null; then" "grep -cvxE '0\\.0\\.0\\.0|::|127\\.0\\.0\\.1' >/dev/null; then"
row "15 the assertion accepts 127.0.0.1 as the sinkhole" agree server.tf
sub server.tf $'resource "terraform_data" "zot_consumer_probe_install" {\n' $'resource "terraform_data" "zot_consumer_probe_install" {\n  count = 0\n'
row "16 count = 0 on web-1's deny route" wiring server.tf
python3 - "$SB/cloud-init.yml" <<'PY' || harness "row 17 anchor missing"
import sys
p = sys.argv[1]; s = open(p).read()
start = s.index("  - |\n    for f in /etc/hosts")
end = s.index("  # #8651/#6438: converge")
open(p, "w").write(s[:start] + "%{ if !web_tunnel_connector ~}\n" + s[start:end] + "%{ endif ~}\n" + s[end:])
PY
row "17 copy A wrapped so it vanishes on the web_tunnel_connector=true (web-1) arm" parity cloud-init.yml
sub server.tf '  user_data = base64gzip(templatefile("${path.module}/cloud-init.yml", {' '  user_data = base64gzip(replace(templatefile("${path.module}/cloud-init.yml", {'
row "18 hcloud_server.web user_data post-processed instead of the plain render" wiring server.tf
sub variables.tf $'    "web-2" = { location = "hel1", private_ip = "10.0.1.11", server_type = "cpx22" }\n' \
  $'    "web-2" = { location = "hel1", private_ip = "10.0.1.11", server_type = "cpx22" }\n    "web-3" = { location = "hel1", private_ip = "10.0.1.12", server_type = "cpx22" }\n'
row "19 a third web host that neither running-host route reaches" wiring variables.tf
# #9390: the deny names THREE hosts. Rows 20-24 each break exactly one copy or the assertion for the third
# (docker.pkg.github.com) name. Copy R is the reference every check compares against, so a BODY drift in R
# alone is caught on the LIVE tree (A and B then differ from it: parity red) and a HEADER drift in R exits 2
# as a harness fault (no entry matches HDR); the rows below mutate A and B.
OLD_HDR='for h in ghcr.io pkg-containers.githubusercontent.com; do'
NEW_HDR='for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do'
sub cloud-init.yml "$NEW_HDR" "$OLD_HDR"
row "20 the third name dropped from copy A only" parity cloud-init.yml
sub cloud-init.yml "$NEW_HDR" "$OLD_HDR"
row "21 the third name dropped from copy A, read as ZERO deny entries by the order check" order cloud-init.yml
sub server.tf $'    for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do\n      a=$(timeout 10 getent ahosts "$h"' \
  $'    for h in ghcr.io pkg-containers.githubusercontent.com; do\n      a=$(timeout 10 getent ahosts "$h"'
row "22 the third name dropped from the apply-time assertion only, deny loop unchanged" agree server.tf
sub cloud-init.yml "$NEW_HDR" $'for g in example.invalid; do :; done\n      '"$NEW_HDR"
row "23 a fourth name loop added to copy A beside the compliant three-name header (found, but its bytes differ)" parity cloud-init.yml
sub server.tf "$NEW_HDR" 'for h in docker.pkg.github.com ghcr.io pkg-containers.githubusercontent.com; do'
row "24 the names reordered in copy B's deny loop only" parity server.tf
assert_fixture_dir "$SB"
cat > "$SB/extra-deny-dockerpkg.tf" <<'EOF'
resource "terraform_data" "handcopied_dockerpkg_deny" {
  provisioner "remote-exec" {
    inline = ["for h in docker.pkg.github.com; do printf '0.0.0.0 %s\\n' \"$h\" >> \"$f\"; done"]
  }
}
EOF
row "25 a hand-copied deny loop naming ONLY the third host, writing through \"\$f\" (only DENY_LOOP can see it)" census extra-deny-dockerpkg.tf
sub server.tf $'    for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do\n      a=$(timeout 10 getent ahosts "$h"' \
  $'    for h in ghcr.io pkg-containers.githubusercontent.com; do\n      a=$(timeout 10 getent ahosts "$h"'
row "26 the assertion's name list no longer equals the deny loop's (parity, not only the per-name agree rows)" parity server.tf
sub server.tf 'echo "FATAL: $h does not resolve ONLY' 'echo "FATAL: ghcr.io does not resolve ONLY'
row "27 the assertion's FATAL always names ghcr.io whichever host failed (an operator would chase the wrong host)" agree server.tf

# The rehearsal's dockerd deny probe (#9799 item 5): each row reverts one property of assert_dockerd_denied.
ZR=zot-image-rehearse.sh
sub $ZR 'out="$(timeout 120 sudo docker pull "$ref" 2>&1)"' 'out="$(timeout 120 sudo docker pull "$ref" 2>/dev/null)"'
row "28 the dockerd probe discards the pull output (a recurrence of the bypass would be undiagnosable)" probe $ZR
sub $ZR $'  sleep "$HOSTS_CACHE_WAIT_S"\n' $'  :\n'
row "29 the 7 s wait before the pull is deleted (the probe races Go's hosts-file cache again)" probe $ZR
sub $ZR 'HOSTS_CACHE_WAIT_S=7' 'HOSTS_CACHE_WAIT_S=1'
row "30 the wait is shortened below the 5 s cache" probe $ZR
sub $ZR '  || die "dockerd could still pull' '  || true "dockerd could still pull'
row "31 the call no longer dies: a successful pull would not fail the rehearsal" probe $ZR
sub $ZR 'sudo sh "$W/deny.sh"' 'true'
row "32 the deny is no longer applied before the probe" probe $ZR
sub $ZR $'step "fetch + verify + load the published asset"' $'dk pull "ghcr.io/x@sha256:$D" >/dev/null 2>&1 || true\nstep "fetch + verify + load the published asset"'
row "33 a second pull, spelled dk pull, outside the probe (invisible to a literal 'docker pull' count)" probe $ZR
sub $ZR '2>&1)" && rc=0 || rc=$?' '2>&1)" && rc=0 || rc=0'
row "34 the pull status is forced to success, so a refused pull and a successful one read alike" probe $ZR

# Harness row (must PASS): copy A re-indented under its `- |` parses to the same entry.
python3 - "$SB/cloud-init.yml" <<'PY' || harness "re-indent anchor missing"
import sys
p = sys.argv[1]; L = open(p).read().split("\n")
i = L.index("    for f in /etc/hosts /etc/cloud/templates/hosts.debian.tmpl; do")
for j in range(i, i + 6):
    L[j] = "  " + L[j]
open(p, "w").write("\n".join(L))
PY
cmp -s "$DIR/cloud-init.yml" "$SB/cloud-init.yml" && harness "re-indent did not land"
chk_parity "$SB" >/dev/null 2>&1 && chk_order "$SB" >/dev/null 2>&1 \
  && pass "harness: copy A re-indented (non-canonical YAML, same parsed entry) still passes parity + order" \
  || fail "harness: a re-indented but identical copy A was rejected (the check reads bytes, not the parsed entry)"
sandbox
# Harness row (must RED): a comparator that always agrees makes row 1 survive — so the battery,
# not just the live-tree run, depends on the comparator.
sub server.tf "printf '0.0.0.0 %s\n:: %s\n'" "printf '127.0.0.1 %s\n:: %s\n'"
if ( same() { return 0; }; chk_parity "$SB" >/dev/null 2>&1 ); then
  pass "harness: with same() forced true, row 1's mutation goes undetected (the comparator is load-bearing)"
else fail "harness: row 1 was detected even with same() forced true — parity is not decided by the comparator"; fi
sandbox
# Harness row (must RED the benign edit): row() itself must count a surviving mutation as a FAIL. Every
# other row passes only if row() is honest, and a row() reduced to `if false` left the suite green.
printf '\n# harmless trailing comment\n' >> "$SB/server.tf"
SURV_FAILS=$( ( PASS=0; FAIL=0; row "benign edit" parity server.tf >/dev/null 2>&1; echo "$FAIL" ) )
if [[ "$SURV_FAILS" == 1 ]]; then pass "harness: row() reports a mutation that no check detects as a FAIL (a benign edit survives, and is counted)"
else fail "harness: row() did not count a surviving mutation (FAIL count '$SURV_FAILS', want 1) -- the whole battery is unfalsifiable"; fi
sandbox

# Floor at the MEASURED count (8 live checks + control + 34 rows + 3 harness rows = 46; was 29 before
# #9390 added rows 20-27 and the row() honesty control). Reported with printf + exit DIRECTLY, never
# through pass()/fail() (the floor polices them).
MIN_ASSERTIONS=46
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "=== web-ghcr-deny: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
