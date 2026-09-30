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
#   parity   A == B == R, whole entry, parsed (render -> yaml.safe_load; terraform console)
#   order    runcmd[0] is the trap arm, runcmd[1] is the one deny entry
#   exec     copy B runs under bash + set -e against temp files: one 0.0.0.0 and one :: line per
#            name, idempotent, unrelated lines untouched, an existing entry not duplicated
#   agree    the three "resolves ONLY to the sinkhole" implementations (registry heartbeat,
#            ci-deploy.sh _ghcr_blocked_state, the apply-time assertion) on per-name getent shims
#   wiring   both consumers: the locals in triggers_replace AND a last remote-exec block that runs
#            exactly ["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh]
#   census   every `for h in ghcr.io` / `/etc/hosts` in any infra .tf sits inside the two locals
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
# Instrument self-test BEFORE anything is measured: both helpers must move their counters.
pass "instrument: pass() counts"
fail "instrument: fail() counts (this FAIL line is EXPECTED)"
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

HDR = "for h in ghcr.io pkg-containers.githubusercontent.com; do"

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

def locals_block(tf, out):
    """The ghcr_deny locals, cut on content (header line through the second closing EOT)."""
    L = open(tf).read().split("\n")
    try:
        i = L.index("  ghcr_deny_sh        = <<-EOT")
    except ValueError:
        open(out, "w").write(""); return
    ends = [j for j in range(i, len(L)) if L[j] == "  EOT"][:2]
    txt = "\n".join(L[i:ends[-1] + 1]) if len(ends) == 2 else ""
    open(out, "w").write("locals {\n" + txt + "\n}\n" if txt else "")

def strip_comments(t):
    return "\n".join(l for l in t.split("\n") if not l.lstrip().startswith("#"))

def span(src, name):
    m = re.search(r'^resource "terraform_data" "%s" \{\n(.*?)^\}\n' % re.escape(name), src, re.S | re.M)
    return strip_comments(m.group(1)) if m else None

def wiring(tf):
    src = open(tf).read()
    bad = []
    for name in ("zot_consumer_probe_install", "deploy_pipeline_fix_web2"):
        b = span(src, name)
        if b is None:
            bad.append("%s: resource not found" % name); continue
        tr = re.search(r'triggers_replace = sha256\(join\(",", \[\n(.*?)^\s*\]\)\)', b, re.S | re.M)
        trl = [l.strip() for l in tr.group(1).split("\n")] if tr else []
        for want in ("local.ghcr_deny_sh,", "local.ghcr_deny_assert_sh,"):
            if want not in trl:
                bad.append("%s: %s missing from triggers_replace (the deny text must move the hash)" % (name, want[:-1]))
        starts = [m.start() for m in re.finditer(r'^  provisioner "[a-z-]+" \{$', b, re.M)]
        blocks = []
        for s in starts:
            e = b.index("\n  }", s)
            blocks.append(b[s:e + 4])
        if not blocks:
            bad.append("%s: no provisioner blocks" % name); continue
        last = blocks[-1]
        inner = " ".join(last.split("\n", 1)[1].rsplit("\n", 1)[0].split())
        if not last.startswith('  provisioner "remote-exec" {') or \
                inner != 'inline = ["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh]':
            bad.append("%s: the LAST provisioner must be a dedicated remote-exec running exactly "
                       '["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh]; got: %s' % (name, inner[:120]))
        for tok in ("var.", "doppler_", "hooks_json", "${"):
            if tok in last:
                bad.append("%s: the deny block references %s (a sensitive value hides the FATAL; a failure leaves a secret script in /root)" % (name, tok))
        for blk in blocks[:-1]:
            if "ghcr_deny" in blk:
                bad.append("%s: the deny locals appear in a non-dedicated provisioner block" % name)
    print("\n".join("BAD " + x for x in bad) if bad else "OK")

def census(root):
    bad, inside = [], 0
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x != ".terraform"]
        for f in files:
            if not f.endswith(".tf"):
                continue
            p = os.path.join(d, f)
            L = open(p).read().split("\n")
            lo = hi = -1
            if f == "server.tf" and d == root and "  ghcr_deny_sh        = <<-EOT" in L:
                lo = L.index("  ghcr_deny_sh        = <<-EOT")
                ends = [j for j in range(lo, len(L)) if L[j] == "  EOT"][:2]
                hi = ends[-1] if len(ends) == 2 else -1
            for n, l in enumerate(L):
                if l.lstrip().startswith("#"):
                    continue
                if "for h in ghcr.io" in l or "/etc/hosts" in l:
                    if lo <= n <= hi:
                        inside += 1
                    else:
                        bad.append("%s:%d %s" % (os.path.relpath(p, root), n + 1, l.strip()[:100]))
    # deny header + assert header + the one /etc/hosts loop line = 3 sanctioned occurrences
    if inside != 3:
        bad.append("expected exactly 3 sanctioned occurrences inside the two locals, found %d" % inside)
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
# render_a <root> <out dir>: copy A + runcmd[0] + the deny entry's index from the rendered template.
render_a() {
  assert_fixture_dir "$WORK"; mkdir -p "$2" "$WORK/tfa"
  local expr
  expr=$(printf 'base64encode(templatefile("%s", { image_name="ghcr.io/jikig-ai/soleur-web-platform:v9.9.9", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="tt", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="https://k@o1.ingest.de.sentry.io/1", resend_api_key="r", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", registry_endpoint="10.0.1.30:5000", web_colocate_inngest=false, web_tunnel_connector=false, host_name="soleur-web-2", private_ip="10.0.1.20", web_probes_token="t", expected_ip="10.0.1.20", web_host_key="web-2", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k", zot_pull_user="zot-pull", zot_pull_token="dkryFMT07elszGNU18fmtAHOV29gnuBIPW3ahovC" }))' "$1/cloud-init.yml")
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
  render_a "$1" "$WORK/a" || { echo "copy A: $(cat "$WORK/a/why" 2>/dev/null)"; return 1; }
  copy_b "$1" "$WORK/b"
  [[ -s "$WORK/a/A" && -s "$WORK/b/deny.sh" && -s "$WORK/b/assert.sh" && -s "$WORK/copyR" ]] \
    || { echo "a copy is EMPTY (A=$(wc -c < "$WORK/a/A") B=$(wc -c < "$WORK/b/deny.sh") assert=$(wc -c < "$WORK/b/assert.sh")) — $RETIRE"; return 1; }
}
chk_parity() {  # <root>
  render_a "$1" "$WORK/a" || { echo "copy A: $(cat "$WORK/a/why" 2>/dev/null)"; return 1; }
  copy_b "$1" "$WORK/b"
  same "$WORK/a/A" "$WORK/copyR" || { echo "copy A (cloud-init.yml runcmd deny entry) differs from copy R (the registry entry)"; return 1; }
  same "$WORK/b/deny.sh" "$WORK/copyR" || { echo "copy B (local.ghcr_deny_sh) differs from copy R — $RETIRE"; return 1; }
}
chk_order() {  # <root>
  render_a "$1" "$WORK/a" || { echo "copy A: $(cat "$WORK/a/why" 2>/dev/null)"; return 1; }
  [[ "$(cat "$WORK/a/count")" == 1 ]] || { echo "expected exactly one deny entry in the web runcmd, found $(cat "$WORK/a/count")"; return 1; }
  grep -qF 'trap on_err EXIT' "$WORK/a/r0" || { echo "runcmd[0] must stay the #6090 trap-arm entry"; return 1; }
  [[ "$(cat "$WORK/a/idx")" == 1 ]] || { echo "the deny must be runcmd[1] (right after the trap arm), found at $(cat "$WORK/a/idx")"; return 1; }
}
chk_exec() {  # <root>
  copy_b "$1" "$WORK/b" || { echo "copy B unreadable"; return 1; }
  local w="$WORK/exec" n rc
  assert_fixture_dir "$WORK"; rm -rf "$w"; mkdir -p "$w"
  sed -e "s#/etc/cloud/templates/hosts.debian.tmpl#$w/tmpl#g" -e "s#/etc/hosts#$w/hosts#g" "$WORK/b/deny.sh" > "$w/deny.sh"
  if grep -qE '/etc/hosts|/etc/cloud' "$w/deny.sh"; then echo "path substitution left a real path in the script; refusing to run it"; return 1; fi
  { echo 'set -e'; cat "$w/deny.sh"; } > "$w/run.sh"
  printf '127.0.0.1 localhost\n' > "$w/hosts"; printf '127.0.0.1 localhost\n' > "$w/tmpl"
  rc=0; bash "$w/run.sh" && bash "$w/run.sh" || rc=$?
  [[ "$rc" == 0 ]] || { echo "copy B exited $rc under bash + set -e"; return 1; }
  for f in hosts tmpl; do
    for n in ghcr.io pkg-containers.githubusercontent.com; do
      [[ "$(grep -cxF "0.0.0.0 $n" "$w/$f")" == 1 && "$(grep -cxF ":: $n" "$w/$f")" == 1 ]] \
        || { echo "$f: want exactly one '0.0.0.0 $n' and one ':: $n' after two runs"; return 1; }
    done
    [[ "$(head -1 "$w/$f")" == "127.0.0.1 localhost" ]] || { echo "$f: an unrelated line was changed"; return 1; }
  done
  # An existing TAB-separated sinkhole entry is not duplicated; an absent template is skipped.
  rm -f "$w/tmpl"; printf '10.0.0.1 other\n0.0.0.0\tghcr.io\n' > "$w/hosts"
  rc=0; bash "$w/run.sh" || rc=$?
  [[ "$rc" == 0 && ! -e "$w/tmpl" && "$(grep -c 'ghcr\.io' "$w/hosts")" == 1 && "$(head -1 "$w/hosts")" == "10.0.0.1 other" \
    && "$(grep -c 'pkg-containers' "$w/hosts")" == 2 ]] \
    || { echo "pre-seeded hosts: ghcr.io duplicated, an unrelated line changed, or the absent template was created (rc=$rc)"; return 1; }
}
chk_agree() {  # <root>
  copy_b "$1" "$WORK/b" || { echo "copy B unreadable"; return 1; }
  local s="$WORK/shim" row gh pk want_reg want_ci want_as reg ci as rc err bad=""
  assert_fixture_dir "$WORK"; mkdir -p "$s"
  cat > "$s/getent" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == ahosts && $# -eq 2 ]] || { echo "getent shim: unexpected argv: $*" >&2; exit 64; }
case "$2" in
  ghcr.io) v="${GE_GHCR-}" ;;
  pkg-containers.githubusercontent.com) v="${GE_PKG-}" ;;
  *) echo "getent shim: unexpected name: $2" >&2; exit 64 ;;
esac
[[ -n "$v" ]] || exit 2
printf '%b' "$v"
EOF
  chmod +x "$s/getent"
  sed -n '/^_ghcr_blocked_state() {$/,/^}$/p' "$1/ci-deploy.sh" > "$WORK/ci-fn.sh"
  [[ -s "$WORK/ci-fn.sh" ]] || { echo "_ghcr_blocked_state not found in ci-deploy.sh"; return 1; }
  local SINK='0.0.0.0 STREAM x\n0.0.0.0 DGRAM\n:: STREAM\n' ROUT='140.82.121.34 STREAM x\n' \
    MIX='0.0.0.0 STREAM x\n140.82.121.34 STREAM\n' V6='2606:50c0:8000::154 STREAM x\n'
  # ghcr | pkg | registry | ci-deploy | assertion — the last row is the NAMED expected difference:
  # both classifiers probe ghcr.io only (registry parity) while the assertion checks both names.
  while IFS='|' read -r row gh pk want_reg want_ci want_as; do
    reg=$(env GE_GHCR="$gh" GE_PKG="$pk" PATH="$s:$PATH" sh -c ". '$WORK/reg-classifier.sh'; printf %s \"\$GHCR_BLOCKED\"" 2>/dev/null)
    ci=$(env GE_GHCR="$gh" GE_PKG="$pk" PATH="$s:$PATH" bash -euo pipefail -c ". '$WORK/ci-fn.sh'; _ghcr_blocked_state" 2>/dev/null)
    rc=0; env GE_GHCR="$gh" GE_PKG="$pk" PATH="$s:$PATH" bash -c "set -e; $(cat "$WORK/b/assert.sh")" >/dev/null 2>"$WORK/as.err" || rc=$?
    as=pass; [[ "$rc" == 0 ]] || as=fail
    err=""
    if [[ "$as" == fail ]] && ! grep -qE '^FATAL: .* \(#9169\)\. Route back: .*never gh run rerun --failed\.$' "$WORK/as.err"; then err=" (FATAL text/route-back missing)"; fi
    if [[ "$reg" != "$want_reg" || "$ci" != "$want_ci" || "$as" != "$want_as" || -n "$err" ]]; then
      bad="$bad [$row: registry=$reg/$want_reg ci-deploy=$ci/$want_ci assert=$as/$want_as$err]"
    fi
  done <<EOF
sink-only|$SINK|$SINK|1|1|pass
routable-v4|$ROUT|$ROUT|0|0|fail
sink+routable|$MIX|$MIX|0|0|fail
routable-v6-with-::|$V6|$V6|0|0|fail
unresolvable|||unknown|unknown|fail
ghcr-sinked-pkg-routable|$SINK|$ROUT|1|1|fail
EOF
  [[ -z "$bad" ]] || { echo "classifier disagreement:$bad"; return 1; }
}
chk_wiring() {  # <root>
  local o; o=$(python3 "$WORK/g2.py" wiring "$1/server.tf")
  [[ "$o" == OK ]] || { printf '%s — %s\n' "$(tr '\n' ';' <<<"$o")" "$RETIRE"; return 1; }
}
chk_census() {  # <root>
  local o; o=$(python3 "$WORK/g2.py" census "$1")
  [[ "$o" == OK ]] || { printf 'a deny literal / hosts-file write outside the two locals: %s — %s\n' "$(tr '\n' ';' <<<"$o")" "$RETIRE"; return 1; }
}
CHECKS="nonempty parity order exec agree wiring census"

# ── the live tree ─────────────────────────────────────────────────────────────────────────────────
echo "--- Guard 2 on the live tree ---"
for c in $CHECKS; do
  why=$("chk_$c" "$DIR" 2>&1) && pass "$c" || fail "$c: $why"
done

# ── in-suite mutation battery (sandbox copies; each row must red on its NAMED check) ──────────────
echo "--- Guard 2 mutation battery ---"
SB="$WORK/sb"
sandbox() {
  assert_fixture_dir "$SB"; assert_fixture_dir "$DIR"
  rm -rf "$SB"; mkdir -p "$SB"
  (cd "$DIR" && find . -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 -I{} cp --parents {} "$SB/")
  cp "$DIR/cloud-init.yml" "$DIR/ci-deploy.sh" "$SB/"
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
DENY_BLOCK_TF=$'  provisioner "remote-exec" {\n    inline = ["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh]\n  }\n'
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
    inline = ["for h in ghcr.io pkg-containers.githubusercontent.com; do printf '0.0.0.0 %s\\n' \"$h\" >> /etc/hosts; done"]
  }
}
EOF
row "6 a hand-copied deny literal in a new resource in a second .tf" census extra-deny.tf
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

# Floor: reported with printf + exit DIRECTLY, never through pass()/fail() (the floor polices them).
MIN_ASSERTIONS=21
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "=== web-ghcr-deny: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
