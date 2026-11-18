#!/usr/bin/env bash
# soleur-bastion user_data and Terraform suite (#12866): Guards 2-5 and SHAPE.
#
#   EGRESS  (Guard 2) every accept row and resolver hostname cites a consumer the render installs;
#           every output accept names its destination (or is the NTP/DHCP row pinned to its daemon
#           user), none reaches a private, loopback or link-local address, no port range, negation,
#           th or IPv6 match; input and output drop by default; inet family; no IPv6; sshd masked;
#           the baseline is not the nftables conffile; apt sources are preserved; the egress script
#           never empties the set on a failed lookup and never loads a private answer.
#   EMITTER the comment-stripped rendered runcmd sends fresh_boot_ready once, after its last check.
#   SETTLE  (Guard 3) the ADR-326 apt and kernel-settle blocks are cloud-init.yml's bytes.
#   HOSTKEY (Guard 4) the only host key the render carries is the fixture Terraform key.
#   BUDGET  (Guard 5) the render is non-empty and at most 32,768 bytes (Hetzner's user_data cap).
#   SHAPE   zero-rule firewall, a unique in-subnet private IP, the cx23 literal and x86 precondition,
#           and no other workflow's push trigger waking on a tracked bastion file (git ls-files).
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
# A RED row with EXPECT set also requires that text in the lint's output, so it is red for the
# violation it names (the lint maps any crash to rc 2, so rc 1 is always a named violation).
check() {
  local label="$1" want="$2" out rc; shift 2
  cases=$((cases + 1))
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$want" == PASS && "$rc" -eq 0 ]] || [[ "$want" == RED && "$rc" -eq 1 && "$out" == *"${EXPECT:-}"* ]]; then
    pass "$label"
  else
    fail "$label (want $want${EXPECT:+ naming '$EXPECT'}, rc=$rc)" "$out"
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
# A push filter of an unexpected workflow matching a bastion file (fixture repo root: not a git
# checkout, so the lint falls back to its fixed file list).
FAKE="$WORK/fakeroot"; mkdir -p "$FAKE/.github/workflows" "$FAKE/apps/web-platform/infra"
cp "$TF" "$FAKE/apps/web-platform/infra/"
fake_wf() { printf '%b' "$1" > "$FAKE/.github/workflows/other.yml"; }
fake_wf 'on:\n  push:\n    paths:\n      - "apps/web-platform/infra/bastion*"\njobs: {}\n'
EXPECT="push path filter" check "shape: another workflow's push filter matches a bastion file" RED python3 "$LINT" shape "$DIR" "$FAKE"
fake_wf 'on:\n  push:\n    branches: [main]\njobs: {}\n'
EXPECT="no path filter" check "shape: an unreviewed push trigger with no path filter wakes on every bastion file" RED python3 "$LINT" shape "$DIR" "$FAKE"
fake_wf 'on:\n  push:\n    paths-ignore:\n      - "docs/**"\njobs: {}\n'
EXPECT="paths-ignore" check "shape: a paths-ignore filter that does not cover the bastion files" RED python3 "$LINT" shape "$DIR" "$FAKE"
fake_wf 'on:\n  push:\n    paths: [\n'
EXPECT="does not parse" check "shape: an unparseable workflow is a violation, not a skip" RED python3 "$LINT" shape "$DIR" "$FAKE"
fake_wf 'on:\n  push:\n    tags: ["v*"]\njobs: {}\n'
check "shape: a tag-only push trigger passes (a merge does not wake it)" PASS python3 "$LINT" shape "$DIR" "$FAKE"
fake_wf 'on:\n  push:\n    paths:\n      - "apps/web-platform/infra/zot-*"\njobs: {}\n'
check "shape: a non-matching push filter passes" PASS python3 "$LINT" shape "$DIR" "$FAKE"
# In a checkout the file list is `git ls-files '*bastion*'`, so a bastion file no list names (2b's
# replace gate, say) is still covered: a filter matching ONLY that file must be RED.
GROOT="$WORK/gitroot"; mkdir -p "$GROOT/.github/workflows" "$GROOT/scripts/lib"
: > "$GROOT/scripts/lib/bastion-replace-gate.sh"
printf 'on:\n  push:\n    paths:\n      - "scripts/lib/bastion-replace-*"\njobs: {}\n' > "$GROOT/.github/workflows/other.yml"
if git -C "$GROOT" init -q 2>/dev/null && git -C "$GROOT" add -A 2>/dev/null; then
  EXPECT="scripts/lib/bastion-replace-gate.sh" check "shape: a tracked bastion file outside the fixed list is covered (git ls-files)" RED python3 "$LINT" shape "$DIR" "$GROOT"
else harness "git init of the shape fixture failed"; fi
# Zero-item floors: each comparison that found nothing to compare must fail.
ZROOT="$WORK/zeroroot"; mkdir -p "$ZROOT/.github/workflows"
printf 'on:\n  workflow_dispatch: {}\njobs: {}\n' > "$ZROOT/.github/workflows/other.yml"
EXPECT="no workflow push trigger was read" check "shape floor: no workflow carries a push trigger (0 checked)" RED python3 "$LINT" shape "$DIR" "$ZROOT"
if git -C "$ZROOT" init -q 2>/dev/null && git -C "$ZROOT" add -A 2>/dev/null; then
  EXPECT="found no *bastion* file" check "shape floor: a checkout with no tracked bastion file (0 checked)" RED python3 "$LINT" shape "$DIR" "$ZROOT"
else harness "git init of the zero fixture failed"; fi
ZINFRA="$WORK/zeroinfra"; mkdir -p "$ZINFRA"; cp "$TF" "$ZINFRA/"
EXPECT="no other host private IP was found" check "shape floor: no other host's private IP to compare against (0 checked)" RED python3 "$LINT" shape "$ZINFRA" "$ROOT"

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
  printf 'templatefile("%s", { host_name="soleur-bastion", sentry_dsn="%s", sentry_ingest_host="o1.ingest.de.sentry.io", private_ip="10.0.1.70", host_ssh_ed25519_private_key=file("%s"), host_ssh_ed25519_public_key=trimspace(file("%s")), bastion_egress_b64=base64encode(file("%s")) })\n' \
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
egress_row() { # <label> <want> <tpl|sh|tf> <from> <to> [expected-message]
  local label="$1" want="$2" which="$3" from="$4" to="$5" msg="${6:-}" t="$TPL" s="$EGRESS_SH" tf="$TF" n=$((cases + 1))
  case "$which" in
    tpl) t="$WORK/eg$n.yml"; mutate "$TPL" "$t" "$from" "$to" >/dev/null ;;
    sh)  s="$WORK/eg$n.sh";  mutate "$EGRESS_SH" "$s" "$from" "$to" >/dev/null ;;
    tf)  tf="$WORK/eg$n.tf"; mutate "$TF" "$tf" "$from" "$to" >/dev/null ;;
  esac || { cases=$((cases + 1)); fail "egress: $label (mutation did not land)"; return; }
  render "$t" "$s" "$WORK/eg$n.raw"
  [[ "$want" == RED ]] && EG_RED+=("$WORK/eg$n.raw|$tf")
  EXPECT="$msg" check "egress: $label" "$want" python3 "$LINT" egress "$WORK/eg$n.raw" "$tf"
}
NTP_ROW='add rule inet soleur_bastion output meta skuid systemd-timesync udp dport 123 accept comment "soleur-egress: systemd-timesyncd"'
MD_DROP='      add rule inet soleur_bastion output ip daddr 169.254.169.254 drop
'
# add_row <cited nft row>: appends a row after the NTP row (the last baseline row).
add_row() { printf '%s\n      %s' "$NTP_ROW" "$1"; }
egress_row "1: an accept row with no comment" RED tpl "$NTP_ROW" 'add rule inet soleur_bastion output meta skuid systemd-timesync udp dport 123 accept' "no soleur-egress citation"
egress_row "2: the nftables baseline removed from the render (0 rows)" RED tpl '  - path: /etc/soleur/bastion-nftables.conf' '  - path: /etc/soleur/bastion-nftables.conf.disabled' "is absent from the render"
egress_row "3: a second uncited row after a cited first" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output tcp dport 22 accept')" "no soleur-egress citation"
egress_row "4: the output chain policy is accept" RED tpl 'add chain inet soleur_bastion output { type filter hook output priority 0; policy drop; }' 'add chain inet soleur_bastion output { type filter hook output priority 0; policy accept; }' "policy is not drop"
egress_row "5: a row cites cloudflared, which the render does not install" RED tpl '"soleur-egress: systemd-timesyncd"' '"soleur-egress: cloudflared"' "does not install"
egress_row "6: an accept-all row with a valid-looking citation" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output oifname "eth0" accept comment "soleur-egress: cloud-init"')" "accept-all shape"
egress_row "8: the refresh timer removed while hostname rows remain" RED tpl '  - path: /etc/systemd/system/bastion-egress.timer' '  - path: /etc/systemd/system/bastion-egress.timer.off' "refresh timer is not installed"
egress_row "9: a resolver hostname without a citation" RED sh 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/ubuntu.sources' 'security.ubuntu.com' "without a soleur-egress citation"
egress_row "9: a resolver hostname citing an uninstalled consumer" RED sh 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/ubuntu.sources' 'security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/extra.sources' "does not install"
egress_row "10: the input chain policy is accept" RED tpl 'add chain inet soleur_bastion input { type filter hook input priority 0; policy drop; }' 'add chain inet soleur_bastion input { type filter hook input priority 0; policy accept; }' "policy is not drop"
egress_row "10: the input chain is absent" RED tpl '      add chain inet soleur_bastion input { type filter hook input priority 0; policy drop; }
' '' "declared 0 times"
egress_row "11: the table family is ip, not inet" RED tpl '      add table inet soleur_bastion' '      add table ip soleur_bastion' "not inet"
egress_row "11: hcloud_server.bastion has ipv6_enabled = true" RED tf 'ipv6_enabled = false' 'ipv6_enabled = true' "ipv6_enabled = false"
egress_row "12: ssh.service is not masked" RED tpl '  - systemctl mask --now ssh.service ssh.socket' '  - systemctl mask --now ssh.socket' "not masked"
# Closed shape (#12866 review): every output accept names its destination, or is one of the two
# user-pinned daemon rows; nothing reaches the private network, the metadata endpoint or IPv6.
egress_row "14: a cited row to git-data:22" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr 10.0.1.20 tcp dport 22 accept comment "soleur-egress: cloud-init"')" "private, loopback or link-local destination 10.0.1.20"
egress_row "14: a cited row to the whole private subnet on :22" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr 10.0.1.0/24 tcp dport 22 accept comment "soleur-egress: cloud-init"')" "destination 10.0.1.0/24"
egress_row "14: a cited row to the registry (10.0.1.30:5000)" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr { 192.0.2.9, 10.0.1.30 } tcp dport 5000 accept comment "soleur-egress: cloud-init"')" "destination 10.0.1.30"
egress_row "15: tcp/443 to any destination with a valid citation" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output tcp dport 443 accept comment "soleur-egress: cloud-init"')" "names no destination"
egress_row "15: tcp/22 to any destination with a valid citation" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output tcp dport 22 accept comment "soleur-egress: nftables.service"')" "names no destination"
egress_row "15: a root-only row with no destination (root reaches git-data:22)" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output meta skuid 0 tcp dport 22 accept comment "soleur-egress: cloud-init"')" "names no destination"
egress_row "15: the NTP row without its user pin" RED tpl "$NTP_ROW" 'add rule inet soleur_bastion output udp dport 123 accept comment "soleur-egress: systemd-timesyncd"' "names no destination"
egress_row "16: a full port range" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr 192.0.2.9 tcp dport 1-65535 accept comment "soleur-egress: cloud-init"')" "a port range"
egress_row "16: a transport-header match" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr 192.0.2.9 th sport 0-65535 accept comment "soleur-egress: cloud-init"')" "transport-header"
egress_row "16: a negated port" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output ip daddr 192.0.2.9 udp dport != 0 accept comment "soleur-egress: cloud-init"')" "a negation"
egress_row "16: an IPv6 match" RED tpl "$NTP_ROW" "$(add_row 'add rule inet soleur_bastion output meta nfproto ipv6 tcp dport 443 accept comment "soleur-egress: cloud-init"')" "an IPv6 match"
DHCP_OUT='      add rule inet soleur_bastion output meta skuid systemd-network udp sport 68 udp dport 67 accept comment "soleur-egress: systemd-networkd"
'
egress_row "17: the metadata drop removed" RED tpl "$MD_DROP" '' "no ip daddr 169.254.169.254 drop row"
egress_row "17: an accept row moved above the metadata drop" RED tpl "$MD_DROP$DHCP_OUT" "$DHCP_OUT$MD_DROP" "wrong side of the metadata drop"
egress_row "18: an input accept outside the DHCP reply" RED tpl 'add rule inet soleur_bastion input udp sport 67 udp dport 68 accept comment "soleur-egress: systemd-networkd"' 'add rule inet soleur_bastion input tcp dport 22 accept comment "soleur-egress: systemd-networkd"' "outside the closed set"
egress_row "19: the render writes the nftables package conffile" RED tpl '  - path: /etc/soleur/bastion-nftables.conf' '  - path: /etc/nftables.conf' "nftables package's conffile"
egress_row "20: ubuntu.sources written without preserve_sources_list" RED tpl 'apt:
  preserve_sources_list: true
' '' "preserve_sources_list"
egress_row "22: bastion-egress.service removed while hostname rows remain" RED tpl '  - path: /etc/systemd/system/bastion-egress.service' '  - path: /etc/systemd/system/bastion-egress.service.off' "bastion-egress.service is not installed"
egress_row "22: bastion-egress.sh carries no ALLOW list" RED sh "ALLOW='" "ALLOWED='" "carries no ALLOW list"
egress_row "H2: a cited row with reordered match fields and extra spaces" PASS tpl "$NTP_ROW" 'add rule inet soleur_bastion output   meta skuid systemd-timesync   udp   dport 123    accept   comment "soleur-egress: systemd-timesyncd"'
h1="$(passes=0; fails=0; for r in "${EG_RED[@]}"; do check x RED true "${r%%|*}" "${r#*|}" >/dev/null; done; printf '%s %s' "$passes" "$fails")"
cases=$((cases + 1))
if [[ "${#EG_RED[@]}" -eq 32 && "$h1" == "0 32" ]]; then pass "egress H1: all 32 RED rows fail against a lint replaced by true"; else fail "egress H1: rows=${#EG_RED[@]} neutered=$h1"; fi
# Zero-item floors: a check that examined nothing must fail, never pass vacuously.
python3 - "$WORK/real.yml" "$WORK/zero.yml" <<'PY' || harness "could not build the zero-rule render"
import base64, re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for w in doc["write_files"]:
    if w["path"] == "/etc/soleur/bastion-nftables.conf":
        w["content"] = "\n".join(l for l in w["content"].splitlines() if not l.strip().startswith("add rule")) + "\n"
    if w["path"] == "/usr/local/sbin/bastion-egress.sh":
        sh = base64.b64decode(w["content"]).decode()
        w["content"] = base64.b64encode("\n".join(l for l in sh.splitlines() if not l.startswith("add rule")).encode()).decode()
open(sys.argv[2], "w").write(yaml.safe_dump(doc))
PY
EXPECT="0 rule rows checked" check "egress floor: a render with zero rule rows" RED python3 "$LINT" egress "$WORK/zero.yml" "$TF"

# Row 7: the rendered ruleset parses (nft -c). The checker must first prove it discriminates.
python3 - "$WORK/real.yml" "$WORK" <<'PY' || harness "could not extract the ruleset from the render"
import base64, re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
f = {w["path"]: w for w in doc["write_files"]}
base = f["/etc/soleur/bastion-nftables.conf"]["content"]
sh = base64.b64decode(f["/usr/local/sbin/bastion-egress.sh"]["content"]).decode()
rows = [l.replace('\\"', '"') for l in sh.splitlines() if re.match(r"^add (set|element|rule) ", l)]
rows = [r.replace("${ips}", "192.0.2.10, 192.0.2.11") for r in rows]
# nft resolves `meta skuid <name>` against THIS host's passwd at parse time; a user the bastion has
# (Ubuntu's _apt) may be absent here (a non-Debian dev box), so only absent names become root.
import pwd
def known(u):
    try:
        pwd.getpwnam(u); return u
    except KeyError:
        return "root"
fix = lambda t: re.sub(r"(?<![\w-])(_apt|systemd-timesync|systemd-network)(?![\w-])", lambda m: known(m.group(1)), t)
base, rows = fix(base), [fix(r) for r in rows]
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
  "$EG_PRIV_HOST") echo "10.0.1.20 STREAM $2" ;;
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
run_egress() { # <script> <fail-host> [private-answer-host] -> sets EG_RC and EG_LOG
  : > "$WORK/nft.log"
  EG_RC=0
  env -i PATH="$WORK/egbin:/usr/bin:/bin" EG_FAIL_HOST="$2" EG_PRIV_HOST="${3:-none}" EG_NFT_LOG="$WORK/nft.log" \
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
# Row 21: a public name answering with a private address never reaches the set (git-data is 10.0.1.20).
run_egress "$EGRESS_SH" none security.ubuntu.com
cases=$((cases + 1))
if [[ "$EG_RC" -ne 0 && -z "$EG_LOG" && "$(cat "$WORK/eg.out")" == *"10.0.1.20, a private"* ]]; then
  pass "egress 21: a lookup answering 10.0.1.20 exits non-zero and never runs nft"
else fail "egress 21: a private answer (rc=$EG_RC)" "$(cat "$WORK/eg.out") $EG_LOG"; fi
mutate "$EGRESS_SH" "$WORK/eg-priv.sh" '      10.*|127.*|169.254.*' '      127.*|169.254.*' > "$WORK/m.out"
run_egress "$WORK/eg-priv.sh" none security.ubuntu.com
cases=$((cases + 1))
if [[ ! -s "$WORK/eg-priv.sh" ]]; then fail "egress 21: mutation did not land" "$(cat "$WORK/m.out")"
elif [[ "$EG_RC" -eq 0 && "$EG_LOG" == *"10.0.1.20"* ]]; then pass "egress 21: a script without the 10/8 refusal is caught (10.0.1.20 reached the set)"
else fail "egress 21: the mutant did not load 10.0.1.20 (rc=$EG_RC), so the row proves nothing" "$EG_LOG"; fi

# ── EMITTER: the ready verdict is a live call after every check stage ──────────────────────
echo "EMITTER"
check "emitter: the real render sends fresh_boot_ready after its last check" PASS python3 "$LINT" emitter "$WORK/real.raw"
READY_EMIT='    _emit "soleur-cloud-init boot stage" fresh_boot_ready info
'
mutate "$TPL" "$WORK/em1.yml" "$READY_EMIT" '    # _emit "soleur-cloud-init boot stage" fresh_boot_ready info (word kept in a comment)
' > /dev/null && render "$WORK/em1.yml" "$EGRESS_SH" "$WORK/em1.raw"
EXPECT="0 live fresh_boot_ready" check "emitter: the ready call deleted, the word left in a comment" RED python3 "$LINT" emitter "$WORK/em1.raw"
mutate "$TPL" "$WORK/em2.yml" "    STAGE=ssh_masked
" "$READY_EMIT    STAGE=ssh_masked
" > /dev/null
mutate "$WORK/em2.yml" "$WORK/em2b.yml" "    _emit \"soleur-cloud-init boot stage\" cloud_init_complete info
$READY_EMIT" '    _emit "soleur-cloud-init boot stage" cloud_init_complete info
' > /dev/null && render "$WORK/em2b.yml" "$EGRESS_SH" "$WORK/em2.raw"
EXPECT="before the last STAGE=" check "emitter: the ready call moved above the ssh_masked check" RED python3 "$LINT" emitter "$WORK/em2.raw"

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
mutate "$TPL" "$WORK/hk6.yml" 'ssh_deletekeys: true' 'ssh_deletekeys: true
ssh_genkeytypes: [ed25519]' > /dev/null
render "$WORK/hk6.yml" "$EGRESS_SH" "$WORK/hk6.raw"
EXPECT="ssh_genkeytypes is set" hostkey_row "5: ssh_genkeytypes is set (sshd could mint its own keys)" RED "$WORK/hk6.raw"
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
if [[ "${#HK_RED[@]}" -eq 5 && "$h1" == "0 5" ]]; then pass "hostkey H1: all 5 RED rows fail against a lint replaced by true"; else fail "hostkey H1: rows=${#HK_RED[@]} neutered=$h1"; fi

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
# 85 unconditional rows, plus row 7's two where an nft checker could prove it discriminates (a leg
# without nft skips them loudly; a CI leg WITH an undiscriminating nft fails row 7 instead).
# NFT_RAN is re-bound here so the floor block stands alone (guard-vacuity-floor mutates only this block).
NFT_RAN="${NFT_RAN:-0}"
MIN_CASES=$((85 + 2 * NFT_RAN))
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
