#!/usr/bin/env bash
# soleur-bastion user_data and Terraform suite (#12866): Guards 2-5 and SHAPE.
#
#   EGRESS  (Guard 2) every accept row and resolver hostname cites a consumer the render installs;
#           input and output drop by default; inet family; no IPv6; sshd masked; the egress script
#           never empties the set on a failed lookup.
#   SETTLE  (Guard 3) the ADR-326 apt and kernel-settle blocks are cloud-init.yml's bytes.
#   HOSTKEY (Guard 4) the only host key the render carries is the fixture Terraform key.
#   BUDGET  (Guard 5) the render is non-empty and at most 32,768 bytes (Hetzner's user_data cap).
#   SHAPE   zero-rule firewall, a unique in-subnet private IP, the cx23 literal and x86 precondition,
#           no web-1 literals, and no other workflow's push filter matching a bastion file.
#
# INSTRUMENT. bastion-cloud-init.yml is a templatefile() source, so every EGRESS/HOSTKEY/BUDGET row
# renders it through `terraform console` (rows can arrive through template variables). Mutation rows
# edit a copy of the template or script and must report "did not land" when the edit is a no-op.
# Without terraform: SKIP-PARTIAL locally, FAIL under CI. The lints live in lib/bastion-lint.py.
#
# ANTI-VACUITY. `cases` moves at every assertion; each guard's H1 re-runs its RED rows against a lint
# replaced by `true` and requires every one to fail; floor and passes+fails==cases by printf + exit
# (ADR-193). Fixture keys are generated per run (ADR-322).
# Presence under apps/web-platform/infra/ IS registration — run-registered-suites.sh (#8736).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
TPL="$DIR/bastion-cloud-init.yml"
EGRESS_SH="$DIR/bastion-egress.sh"
TF="$DIR/bastion.tf"
WEB_TPL="$DIR/cloud-init.yml"
LINT="$DIR/lib/bastion-lint.py"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -z "${2:-}" ]] || printf '       %s\n' "$(head -c 700 <<<"$2")"; }

pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail)" >/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: INSTRUMENT BROKEN (passes=%d fails=%d)\n' "$passes" "$fails" >&2; exit 2
fi
passes=0
fails=0

harness() { printf 'HARNESS: %s\n' "$1" >&2; exit 2; }
for f in "$TPL" "$EGRESS_SH" "$TF" "$WEB_TPL" "$LINT"; do [[ -s "$f" ]] || harness "missing $f"; done
command -v python3 >/dev/null 2>&1 || harness "python3 is required"
python3 -c 'import yaml' 2>/dev/null || harness "PyYAML is required"
WORK="$(mktemp -d "${TMPDIR}/bastion.XXXXXXXX")" || harness "mktemp failed"
case "$WORK" in /*/bastion.*) : ;; *) harness "mktemp returned '$WORK'" ;; esac
trap 'rm -rf "${WORK:?}"' EXIT

# check <label> <want PASS|RED> <cmd...>: RED = the command exits 1 (a violation); 2 is a harness fault.
check() {
  local label="$1" want="$2" out rc; shift 2
  cases=$((cases + 1))
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$want" == PASS && "$rc" -eq 0 ]] || [[ "$want" == RED && "$rc" -eq 1 ]]; then
    pass "$label"
  else
    fail "$label (want $want, rc=$rc)" "$out"
  fi
}
# mutate <src> <dst> <from> <to>: exact, single-occurrence edit; "did not land" is a FAIL row.
mutate() {
  python3 - "$@" <<'PY'
import sys
src, dst, a, b = sys.argv[1:]
t = open(src).read()
if t.count(a) != 1:
    print("mutation did not land (%d occurrences of the anchor)" % t.count(a)); sys.exit(1)
open(dst, "w").write(t.replace(a, b))
PY
}

# ── SHAPE (no render needed) ────────────────────────────────────────────────────────────────
echo "SHAPE"
check "shape: the real files pass" PASS python3 "$LINT" shape "$DIR" "$ROOT"
SHAPE_DIR="$WORK/shape"
shape_row() { # <label> <from> <to> [file]
  local label="$1" from="$2" to="$3" f="${4:-bastion.tf}"
  rm -rf "$SHAPE_DIR"; mkdir -p "$SHAPE_DIR"; cp "$DIR"/*.tf "$SHAPE_DIR"/
  if ! mutate "$DIR/$f" "$SHAPE_DIR/$f" "$from" "$to" >/dev/null; then cases=$((cases + 1)); fail "shape: $label (mutation did not land)"; return; fi
  check "shape: $label" RED python3 "$LINT" shape "$SHAPE_DIR" "$ROOT"
}
shape_row "a firewall rule block (AC5)" 'resource "hcloud_firewall" "bastion" {
  name = "soleur-bastion"' 'resource "hcloud_firewall" "bastion" {
  name = "soleur-bastion"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0"]
  }'
shape_row "the private IP collides with git-data (10.0.1.20)" 'bastion_private_ip = "10.0.1.70"' 'bastion_private_ip = "10.0.1.20"'
shape_row "the private IP collides with a web host default" 'bastion_private_ip = "10.0.1.70"' 'bastion_private_ip = "10.0.1.11"'
shape_row "the private IP is outside the subnet" 'bastion_private_ip = "10.0.1.70"' 'bastion_private_ip = "10.0.2.70"'
shape_row "the server type is a variable" 'server_type = "cx23"' 'server_type = var.git_data_server_type'
shape_row "the x86 precondition is removed" 'data.hcloud_server_type.bastion.architecture == "x86"' 'true'
shape_row "firewall_ids set inline" '  ssh_keys = [hcloud_ssh_key.default.id]' '  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.bastion.id]'
shape_row "a web-1 literal in bastion.tf" '  bastion_host_name  = "soleur-bastion"' '  bastion_host_name  = "soleur-bastion"
  note               = "web-1"'
# A push filter of an unexpected workflow matching a bastion file (fixture repo root).
FAKE="$WORK/fakeroot"; mkdir -p "$FAKE/.github/workflows" "$FAKE/apps/web-platform/infra"
cp "$TF" "$FAKE/apps/web-platform/infra/"
printf 'on:\n  push:\n    paths:\n      - "apps/web-platform/infra/bastion*"\njobs: {}\n' > "$FAKE/.github/workflows/other.yml"
check "shape: another workflow's push filter matches a bastion file" RED python3 "$LINT" shape "$DIR" "$FAKE"
printf 'on:\n  push:\n    paths:\n      - "apps/web-platform/infra/zot-*"\njobs: {}\n' > "$FAKE/.github/workflows/other.yml"
check "shape: a non-matching push filter passes" PASS python3 "$LINT" shape "$DIR" "$FAKE"

# ── SETTLE (Guard 3; source files, no render) ───────────────────────────────────────────────
echo "SETTLE"
SET_RED=()
settle_row() { # <label> <want> <file-to-edit: web|bastion> <from> <to>
  local label="$1" want="$2" which="$3" from="$4" to="$5" w="$WEB_TPL" b="$TPL"
  if [[ "$which" == web ]]; then w="$WORK/web.yml"; mutate "$WEB_TPL" "$w" "$from" "$to" >/dev/null || { cases=$((cases + 1)); fail "settle: $label (mutation did not land)"; return; }
  else b="$WORK/bas.yml"; mutate "$TPL" "$b" "$from" "$to" >/dev/null || { cases=$((cases + 1)); fail "settle: $label (mutation did not land)"; return; }; fi
  [[ "$want" == RED ]] && SET_RED+=("$w|$b")
  check "settle: $label" "$want" python3 "$LINT" settle "$w" "$b"
}
check "settle: the real files match" PASS python3 "$LINT" settle "$WEB_TPL" "$TPL"
settle_row "1: the apt timeout changes in the bastion file only" RED bastion 'until timeout 240 apt-get update' 'until timeout 241 apt-get update'
settle_row "2: the markers are missing from the bastion file" RED bastion '    STAGE=apt_update
' '    STAGE=apt_update_x
'
settle_row "3: the web block changes and the bastion block does not" RED web "printf 'why=second_mismatch'" "printf 'why=second_mismatchX'"
settle_row "4: a second kernel-settle block is appended to the bastion file" RED bastion '  # Post-settle pass:' "  # ADR-326: one reboot onto the new kernel; runcmd re-runs.
  - |
    fi
  # Post-settle pass:"
settle_row "5: linux-image-generic dropped from the bastion package list" RED bastion 'curl linux-image-generic nftables;' 'curl nftables;'
settle_row "H2: the files differ only outside the markers" PASS bastion '  # Post-settle pass:' '  # a comment outside every marker
  # Post-settle pass:'
h1="$(passes=0; fails=0; for r in "${SET_RED[@]}"; do check x RED true "${r%%|*}" "${r#*|}" >/dev/null; done; printf '%s %s' "$passes" "$fails")"
cases=$((cases + 1))
if [[ "${#SET_RED[@]}" -eq 5 && "$h1" == "0 5" ]]; then pass "settle H1: all 5 RED rows fail against a comparison replaced by true"; else fail "settle H1: rows=${#SET_RED[@]} neutered=$h1"; fi

# ── Render (terraform templatefile) ─────────────────────────────────────────────────────────
if ! command -v terraform >/dev/null 2>&1; then
  if [[ -n "${CI:-}" ]]; then printf 'bastion: FAIL (terraform is absent under CI; the render-based half cannot run)\n' >&2; exit 1; fi
  echo "[skip] terraform not installed locally; EGRESS/HOSTKEY/BUDGET rows not executed"
  printf 'bastion: SKIP-PARTIAL (%d assertions, %d failed)\n' "$cases" "$fails"
  [[ "$fails" -eq 0 ]]; exit $?
fi
command -v ssh-keygen >/dev/null 2>&1 || harness "ssh-keygen is required for the fixture host key"
mkdir -p "$WORK/tf" "$WORK/k"
ssh-keygen -q -t ed25519 -N '' -C 'fixture' -f "$WORK/k/key" || harness "ssh-keygen failed"
ssh-keygen -q -t ed25519 -N '' -C 'other' -f "$WORK/k/other" || harness "ssh-keygen failed"
DSN="https://pubkey123@o1.ingest.de.sentry.io/4242"
# render <template> <egress-script> <out> [private-key] [public-key]
render() {
  local priv="${4:-$WORK/k/key}" pub="${5:-$WORK/k/key.pub}"
  printf 'templatefile("%s", { host_name="soleur-bastion", sentry_dsn="%s", sentry_ingest_host="o1.ingest.de.sentry.io", host_ssh_ed25519_private_key=file("%s"), host_ssh_ed25519_public_key=trimspace(file("%s")), bastion_egress_b64=base64encode(file("%s")) })\n' \
    "$1" "$DSN" "$priv" "$pub" "$2" | terraform -chdir="$WORK/tf" console > "$3" 2> "$3.err" \
    || harness "terraform render failed: $(head -c 400 "$3.err")"
}
render "$TPL" "$EGRESS_SH" "$WORK/real.raw"
body() { python3 - "$1" <<'PY'
import sys
L = open(sys.argv[1]).read().splitlines()
if L and L[0].lstrip().startswith("<<"): L = L[1:-1]
sys.stdout.write("\n".join(L) + "\n")
PY
}
body "$WORK/real.raw" > "$WORK/real.yml"

# ── EGRESS (Guard 2) ────────────────────────────────────────────────────────────────────────
echo "EGRESS"
EG_RED=()
check "egress: the real render passes" PASS python3 "$LINT" egress "$WORK/real.raw" "$TF"
egress_row() { # <label> <want> <tpl|sh|tf> <from> <to>
  local label="$1" want="$2" which="$3" from="$4" to="$5" t="$TPL" s="$EGRESS_SH" tf="$TF" n=$((cases + 1))
  case "$which" in
    tpl) t="$WORK/eg$n.yml"; mutate "$TPL" "$t" "$from" "$to" >/dev/null ;;
    sh)  s="$WORK/eg$n.sh";  mutate "$EGRESS_SH" "$s" "$from" "$to" >/dev/null ;;
    tf)  tf="$WORK/eg$n.tf"; mutate "$TF" "$tf" "$from" "$to" >/dev/null ;;
  esac || { cases=$((cases + 1)); fail "egress: $label (mutation did not land)"; return; }
  render "$t" "$s" "$WORK/eg$n.raw"
  [[ "$want" == RED ]] && EG_RED+=("$WORK/eg$n.raw|$tf")
  check "egress: $label" "$want" python3 "$LINT" egress "$WORK/eg$n.raw" "$tf"
}
DNS_ROW='add rule inet soleur_bastion output udp dport 123 accept comment "soleur-egress: systemd-timesyncd"'
egress_row "1: an accept row with no comment" RED tpl "$DNS_ROW" 'add rule inet soleur_bastion output udp dport 123 accept'
egress_row "2: the nftables baseline removed from the render (0 rows)" RED tpl '  - path: /etc/nftables.conf' '  - path: /etc/nftables.conf.disabled'
egress_row "3: a second uncited row after a cited first" RED tpl "$DNS_ROW" "$DNS_ROW
      add rule inet soleur_bastion output tcp dport 22 accept"
egress_row "4: the output chain policy is accept" RED tpl 'add chain inet soleur_bastion output { type filter hook output priority 0; policy drop; }' 'add chain inet soleur_bastion output { type filter hook output priority 0; policy accept; }'
egress_row "5: a row cites cloudflared, which the render does not install" RED tpl '"soleur-egress: systemd-timesyncd"' '"soleur-egress: cloudflared"'
egress_row "6: an accept-all row with a valid-looking citation" RED tpl "$DNS_ROW" "$DNS_ROW
      add rule inet soleur_bastion output oifname \"eth0\" accept comment \"soleur-egress: cloud-init\""
egress_row "8: the refresh timer removed while hostname rows remain" RED tpl '  - path: /etc/systemd/system/bastion-egress.timer' '  - path: /etc/systemd/system/bastion-egress.timer.off'
egress_row "9: a resolver hostname without a citation" RED sh 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/ubuntu.sources' 'security.ubuntu.com'
egress_row "9: a resolver hostname citing an uninstalled consumer" RED sh 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/ubuntu.sources' 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/extra.sources'
egress_row "10: the input chain policy is accept" RED tpl 'add chain inet soleur_bastion input { type filter hook input priority 0; policy drop; }' 'add chain inet soleur_bastion input { type filter hook input priority 0; policy accept; }'
egress_row "10: the input chain is absent" RED tpl '      add chain inet soleur_bastion input { type filter hook input priority 0; policy drop; }
' ''
egress_row "11: the table family is ip, not inet" RED tpl '      add table inet soleur_bastion' '      add table ip soleur_bastion'
egress_row "11: hcloud_server.bastion has ipv6_enabled = true" RED tf 'ipv6_enabled = false' 'ipv6_enabled = true'
egress_row "12: ssh.service is not masked" RED tpl '  - systemctl mask --now ssh.service ssh.socket' '  - systemctl mask --now ssh.socket'
egress_row "H2: a cited row with reordered match fields and extra spaces" PASS tpl "$DNS_ROW" 'add rule inet soleur_bastion output   udp   dport 123    accept   comment "soleur-egress: systemd-timesyncd"'
h1="$(passes=0; fails=0; for r in "${EG_RED[@]}"; do check x RED true "${r%%|*}" "${r#*|}" >/dev/null; done; printf '%s %s' "$passes" "$fails")"
cases=$((cases + 1))
if [[ "${#EG_RED[@]}" -eq 14 && "$h1" == "0 14" ]]; then pass "egress H1: all 14 RED rows fail against a lint replaced by true"; else fail "egress H1: rows=${#EG_RED[@]} neutered=$h1"; fi

# Row 7: the rendered ruleset parses (nft -c). The checker must first prove it discriminates.
python3 - "$WORK/real.yml" "$WORK" <<'PY' || harness "could not extract the ruleset from the render"
import base64, re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
f = {w["path"]: w for w in doc["write_files"]}
base = f["/etc/nftables.conf"]["content"]
sh = base64.b64decode(f["/usr/local/sbin/bastion-egress.sh"]["content"]).decode()
rows = [l.replace('\\"', '"') for l in sh.splitlines() if re.match(r"^add (set|element|rule) ", l)]
rows = [r.replace("${ips}", "192.0.2.10, 192.0.2.11") for r in rows]
open(sys.argv[2] + "/base.nft", "w").write(base)
open(sys.argv[2] + "/full.nft", "w").write('include "%s/base.nft"\n' % sys.argv[2] + "\n".join(rows) + "\n")
PY
NFT_CHECK=""
if command -v nft >/dev/null 2>&1; then
  if unshare -rn true 2>/dev/null; then NFT_CHECK="unshare -rn nft"
  elif [[ "$(id -u)" -eq 0 ]]; then NFT_CHECK="nft"
  elif sudo -n true >/dev/null 2>&1; then NFT_CHECK="sudo -n nft"; fi
fi
nftc() { $NFT_CHECK -c -f "$1" >/dev/null 2>&1; }
printf 'add table inet probe_ok\nadd chain inet probe_ok o { type filter hook output priority 0; policy drop; }\nadd rule inet probe_ok o udp dport 123 accept\n' > "$WORK/good.nft"
printf 'add table inet probe_bad\nadd chain inet probe_bad o { type filter hook output priority 0; policy drop; }\nadd rule inet probe_bad o ip daddr NOT.AN.IP accept\n' > "$WORK/bad.nft"
NFT_RAN=0
if [[ -n "$NFT_CHECK" ]] && nftc "$WORK/good.nft" && ! nftc "$WORK/bad.nft"; then
  NFT_RAN=1
  cases=$((cases + 1)); if nftc "$WORK/full.nft"; then pass "egress 7: the rendered ruleset parses under nft -c"; else fail "egress 7: the rendered ruleset does not parse" "$($NFT_CHECK -c -f "$WORK/full.nft" 2>&1 | head -3)"; fi
  sed 's/udp dport 123 accept/udp dport 123 acept/' "$WORK/base.nft" > "$WORK/base-bad.nft"
  sed "s#$WORK/base.nft#$WORK/base-bad.nft#" "$WORK/full.nft" > "$WORK/full-bad.nft"
  cases=$((cases + 1)); if cmp -s "$WORK/base.nft" "$WORK/base-bad.nft"; then fail "egress 7: syntax mutation did not land"; elif nftc "$WORK/full-bad.nft"; then fail "egress 7: a syntax error in the render is NOT caught"; else pass "egress 7: a syntax error in the render is caught"; fi
elif [[ -n "${CI:-}" ]] && command -v nft >/dev/null 2>&1; then
  cases=$((cases + 1)); fail "egress 7: nft is installed under CI but cannot discriminate (no userns, root or sudo)"
else
  echo "  skip egress 7: nft -c needs nft plus a user namespace, root or passwordless sudo (a present-but-undiscriminating nft FAILs under CI)"
fi

# Row 13: bastion-egress.sh never empties the set when one lookup fails (fixture resolver).
mkdir -p "$WORK/egbin"
cat > "$WORK/egbin/getent" <<'STUB'
#!/bin/sh
[ "$1" = ahostsv4 ] || exit 2
case "$2" in
  "$EG_FAIL_HOST") exit 2 ;;
  archive.ubuntu.com) echo "192.0.2.1 STREAM archive.ubuntu.com" ;;
  security.ubuntu.com) echo "192.0.2.2 STREAM security.ubuntu.com" ;;
  o1.ingest.de.sentry.io) echo "192.0.2.3 STREAM o1.ingest.de.sentry.io" ;;
  *) exit 2 ;;
esac
STUB
cat > "$WORK/egbin/nft" <<'STUB'
#!/bin/sh
{ echo "ARGV $*"; cat; echo; } >> "$EG_NFT_LOG"
STUB
chmod +x "$WORK/egbin/getent" "$WORK/egbin/nft"
printf 'SENTRY_INGEST_HOST=o1.ingest.de.sentry.io\n' > "$WORK/eg.env"
cp "$WORK/base.nft" "$WORK/eg-base.nft"
run_egress() { # <script> <fail-host> -> sets EG_RC and EG_LOG
  : > "$WORK/nft.log"
  EG_RC=0
  env -i PATH="$WORK/egbin:/usr/bin:/bin" EG_FAIL_HOST="$2" EG_NFT_LOG="$WORK/nft.log" \
    BASTION_EGRESS_ENV="$WORK/eg.env" BASTION_EGRESS_BASELINE="$WORK/eg-base.nft" \
    bash "$1" > "$WORK/eg.out" 2>&1 || EG_RC=$?
  EG_LOG="$(cat "$WORK/nft.log")"
}
run_egress "$EGRESS_SH" none
cases=$((cases + 1))
if [[ "$EG_RC" -eq 0 && "$EG_LOG" == *"ARGV -c -f -"* && "$EG_LOG" == *"ARGV -f -"* && "$EG_LOG" == *"192.0.2.1, 192.0.2.2, 192.0.2.3"* ]]; then
  pass "egress 13: all lookups succeed -> one checked batch with every address"
else fail "egress 13: the happy run (rc=$EG_RC)" "$(cat "$WORK/eg.out") $EG_LOG"; fi
egress13() { # <label> <script> -> RED when nft ran after a failed lookup
  run_egress "$2" security.ubuntu.com
  [[ "$EG_RC" -ne 0 && -z "$EG_LOG" ]]
}
cases=$((cases + 1))
if egress13 real "$EGRESS_SH"; then pass "egress 13: a failed lookup exits non-zero and never runs nft"; else fail "egress 13: a failed lookup (rc=$EG_RC)" "$EG_LOG"; fi
mutate "$EGRESS_SH" "$WORK/eg-mut.sh" '[[ -n "$got" ]] || die "lookup failed for ${host} (${consumer})"' '[[ -n "$got" ]] || continue' > "$WORK/m.out"
cases=$((cases + 1))
if [[ ! -s "$WORK/eg-mut.sh" ]]; then fail "egress 13: mutation did not land" "$(cat "$WORK/m.out")"
elif egress13 mutant "$WORK/eg-mut.sh"; then fail "egress 13: a script that drops a failed host is NOT caught"
else pass "egress 13: a script that drops a failed host is caught (nft ran with a short set)"; fi

# ── HOSTKEY (Guard 4) ───────────────────────────────────────────────────────────────────────
echo "HOSTKEY"
HK_RED=()
check "hostkey: the render carries exactly the fixture key" PASS python3 "$LINT" hostkey "$WORK/real.raw" "$WORK/k/key.pub" "$WORK/k/key"
hostkey_row() { # <label> <want> <raw> [expected-pub] [expected-priv]
  [[ "$2" == RED ]] && HK_RED+=("$3")
  check "hostkey: $1" "$2" python3 "$LINT" hostkey "$3" "${4:-$WORK/k/key.pub}" "${5:-$WORK/k/key}"
}
render "$TPL" "$EGRESS_SH" "$WORK/hk1.raw" "$WORK/k/other" "$WORK/k/other.pub"
hostkey_row "1: the render carries a different ed25519 key" RED "$WORK/hk1.raw"
mutate "$TPL" "$WORK/hk2.yml" 'ssh_keys:
  ed25519_private: |
    ${indent(4, host_ssh_ed25519_private_key)}
  ed25519_public: ${host_ssh_ed25519_public_key}' '# keys: ${host_ssh_ed25519_public_key} ${md5(host_ssh_ed25519_private_key)}' > /dev/null
render "$WORK/hk2.yml" "$EGRESS_SH" "$WORK/hk2.raw"
hostkey_row "2: the ssh_keys block is absent" RED "$WORK/hk2.raw"
mutate "$TPL" "$WORK/hk3.yml" '  ed25519_public: ${host_ssh_ed25519_public_key}' '  ed25519_public: ${host_ssh_ed25519_public_key}
  rsa_private: |
    not-a-key' > /dev/null
render "$WORK/hk3.yml" "$EGRESS_SH" "$WORK/hk3.raw"
hostkey_row "3: an rsa_private entry after the compliant ed25519 entry" RED "$WORK/hk3.raw"
mutate "$TPL" "$WORK/hk4.yml" 'ssh_deletekeys: true' 'ssh_deletekeys: false' > /dev/null
render "$WORK/hk4.yml" "$EGRESS_SH" "$WORK/hk4.raw"
hostkey_row "4: ssh_deletekeys: false" RED "$WORK/hk4.raw"
mutate "$TPL" "$WORK/hk5.yml" '  ed25519_public: ${host_ssh_ed25519_public_key}' '  ed25519_public: "${host_ssh_ed25519_public_key}"' > /dev/null
render "$WORK/hk5.yml" "$EGRESS_SH" "$WORK/hk5.raw"
hostkey_row "H2: the same key with different YAML quoting" PASS "$WORK/hk5.raw"
# H1: a comparison that reads its expected key from the render itself certifies row 1's wrong key.
python3 - "$WORK/hk1.raw" "$WORK" <<'PY' || harness "could not read the row-1 render"
import sys, yaml
L = open(sys.argv[1]).read().splitlines()[1:-1]
k = yaml.safe_load("\n".join(L))["ssh_keys"]
open(sys.argv[2] + "/self.pub", "w").write(k["ed25519_public"])
open(sys.argv[2] + "/self.priv", "w").write(k["ed25519_private"])
PY
cases=$((cases + 1))
if python3 "$LINT" hostkey "$WORK/hk1.raw" "$WORK/self.pub" "$WORK/self.priv" >/dev/null 2>&1 \
   && ! python3 "$LINT" hostkey "$WORK/hk1.raw" "$WORK/k/key.pub" "$WORK/k/key" >/dev/null 2>&1; then
  pass "hostkey H1: a self-anchored comparison passes row 1's wrong key; the resource anchor refuses it"
else fail "hostkey H1: the anchor does not discriminate"; fi
h1="$(passes=0; fails=0; for r in "${HK_RED[@]}"; do check x RED true "$r" >/dev/null; done; printf '%s %s' "$passes" "$fails")"
cases=$((cases + 1))
if [[ "${#HK_RED[@]}" -eq 4 && "$h1" == "0 4" ]]; then pass "hostkey H1: all 4 RED rows fail against a lint replaced by true"; else fail "hostkey H1: rows=${#HK_RED[@]} neutered=$h1"; fi

# ── BUDGET (Guard 5) ────────────────────────────────────────────────────────────────────────
echo "BUDGET"
CAP=32768
budget_ok() { local n; n=$(wc -c < "$1" | tr -d ' '); [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 && "$n" -le "$CAP" ]]; }
budget_row() { # <label> <want> <file>
  cases=$((cases + 1))
  if budget_ok "$3"; then got=PASS; else got=RED; fi
  if [[ "$got" == "$2" ]]; then pass "budget: $1 ($(wc -c < "$3" | tr -d ' ') bytes)"; else fail "budget: $1 (want $2, got $got)"; fi
}
budget_row "the real render fits the cap" PASS "$WORK/real.yml"
head -c 40000 /dev/zero | tr '\0' 'x' > "$WORK/b1"; budget_row "1: a render over the cap" RED "$WORK/b1"
: > "$WORK/b2"; budget_row "2: an empty render" RED "$WORK/b2"
head -c 32769 /dev/zero | tr '\0' 'x' > "$WORK/b3"; budget_row "3: one byte over the cap" RED "$WORK/b3"
head -c 32767 /dev/zero | tr '\0' 'x' > "$WORK/b4"; budget_row "H2: one byte under the cap" PASS "$WORK/b4"
cases=$((cases + 1))
if ( wc() { echo 0; }; ! budget_ok "$WORK/real.yml" ); then pass "budget H1: a measurement that returns 0 is RED, never a pass"; else fail "budget H1: a zero measurement passed"; fi

echo
# 53 unconditional rows, plus row 7's two where an nft checker could prove it discriminates (a leg
# without nft skips them loudly; a CI leg WITH an undiscriminating nft fails row 7 instead).
MIN_CASES=$((53 + 2 * NFT_RAN))
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'bastion: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'bastion: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2; exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'bastion: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2; exit 1
fi
printf 'bastion: PASS (%d assertions, 0 failed)\n' "$cases"
