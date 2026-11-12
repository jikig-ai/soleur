#!/usr/bin/env bash
# Suite for generic web hosts (#9421 Part 2a, ADR-327): every role a web host holds is a keyed field of
# var.web_hosts, the lists derived from it match every hand-kept copy, the web-1 literals only shrink, and
# the host-bound-state census still holds.
#
# INSTRUMENT. The web-platform root needs a backend for `terraform console`, so the suite copies the
# var.web_hosts and var.web2_lb_weight blocks (variables.tf) and the LB weight locals (cloudflare-lb.tf)
# into an isolated root, then evaluates the SHIPPED expressions read out of inngest-host.tf and tunnel.tf.
# Variable validations run under `console`, so the refusal rows exercise the real validation blocks.
#
# ANTI-VACUITY. `cases` moves at the CALL SITE of every assertion helper, independently of
# pass()/fail(); the floor and the passes+fails==cases identity are reported by printf + exit 1,
# never through fail() (ADR-193).
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
VARS="$DIR/variables.tf"
LB="$DIR/cloudflare-lb.tf"
INN="$DIR/inngest-host.tf"
TUN="$DIR/tunnel.tf"
SRV="$DIR/server.tf"
CI_YML="$DIR/cloud-init.yml"
UPT="$DIR/uptime-alerts.tf"
CENSUS="$ROOT/knowledge-base/engineering/operations/web-host-bound-state-census.md"
SELF_REL="apps/web-platform/infra/web-hosts-generic.test.sh"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both verdict helpers once; refuse to continue unless both counters moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) - EXPECTED, subtracted below"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left passes=%d fails=%d, expected 1/1.\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

eq() { # <name> <actual> <expected>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got [$2], want [$3])"; fi
}
ok() { # <name> <rc>: 0 = holds
  cases=$((cases + 1))
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

ST_P="$passes"; ST_F="$fails"; ST_C="$cases"
{
  eq "selftest eq (must fail)" a b
  ok "selftest ok (must fail)" 1
  eq "selftest eq (must pass)" a a
  ok "selftest ok (must pass)" 0
} > /dev/null 2>&1
if [[ "$fails" -ne $((ST_F + 2)) || "$passes" -ne $((ST_P + 2)) || "$cases" -ne $((ST_C + 4)) ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: eq/ok self-test left passes=%d fails=%d cases=%d, expected +2/+2/+4.\n' "$passes" "$fails" "$cases" >&2
  exit 2
fi
passes="$ST_P"; fails="$ST_F"; cases="$ST_C"

harness() { printf '[HARNESS] %s\n' "$1" >&2; exit 2; }
for f in "$VARS" "$LB" "$INN" "$TUN" "$SRV" "$CI_YML" "$UPT" "$CENSUS"; do [[ -f "$f" ]] || harness "missing $f"; done

WORK="$(mktemp -d "${TMPDIR}/web-hosts-generic.XXXXXXXX")" || harness "mktemp failed"
trap 'rm -rf "${WORK:?}"' EXIT

# block <file> <line-prefix>: the brace-balanced block whose first line starts with the prefix.
block() {
  python3 - "$1" "$2" <<'PY'
import sys
p, pre = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
for i, l in enumerate(lines):
    if l.startswith(pre):
        depth, out = 0, []
        for l2 in lines[i:]:
            out.append(l2)
            depth += l2.count("{") - l2.count("}")
            if depth == 0:
                print("\n".join(out)); sys.exit(0)
sys.exit(3)
PY
}

# ── STRUCTURE: each role reads a keyed field, never a key literal ─────────────────────────────
IPS_EXPR="$(grep -E '^[[:space:]]*web_host_private_ips[[:space:]]*=[[:space:]]*join\(' "$INN" | sed -E 's/^[[:space:]]*web_host_private_ips[[:space:]]*=[[:space:]]*//')"
eq "structure: inngest-host.tf derives web_host_private_ips from var.web_hosts (one assignment)" \
  "$(grep -cE '^[[:space:]]*web_host_private_ips[[:space:]]*=[[:space:]]*join\(",", \[for k in sort\(keys\(var\.web_hosts\)\) : var\.web_hosts\[k\]\.private_ip\]\)$' "$INN")" 1
JUMP_EXPR="$(grep -E '^[[:space:]]*service[[:space:]]*=[[:space:]]*"ssh://' "$TUN" | sed -E 's/^[[:space:]]*service[[:space:]]*=[[:space:]]*"ssh:\/\/\$\{(.*)\}:22"$/\1/')"
eq "structure: the ssh. ingress targets the keyed jump host" "$JUMP_EXPR" 'one([for h in values(var.web_hosts) : h.private_ip if h.jump])'
eq "structure: server.tf connector predicate is the keyed tunnel_connector field" \
  "$(grep -cE '^[[:space:]]*web_tunnel_connector[[:space:]]*=[[:space:]]*each\.value\.tunnel_connector[[:space:]]*$' "$SRV")" 1
eq "structure: no web_tunnel_connector predicate names a key" "$(grep -cE 'web_tunnel_connector[[:space:]]*=.*"web-[0-9]+"' "$SRV")" 0

# ── HARNESS: evaluate the shipped blocks and expressions under terraform console ───────────────
# terraform is required everywhere: the console rows ARE the property (a skip would leave a floor-only shell).
command -v terraform >/dev/null 2>&1 || harness "terraform is not installed (the console rows are not optional)"
H="$WORK/h"; mkdir -p "$H"
{
  block "$VARS" 'variable "web_hosts"' || harness "variable web_hosts block not found"
  block "$VARS" 'variable "web2_lb_weight"' || harness "variable web2_lb_weight block not found"
  block "$LB" 'locals {' || harness "cloudflare-lb.tf locals block not found"
  printf 'locals {\n  derived_ips = %s\n  jump_ip     = %s\n  connector   = one([for k, h in var.web_hosts : k if h.tunnel_connector])\n  primary     = one([for k, h in var.web_hosts : k if h.luks_monitor_profile == "primary"])\n}\n' "$IPS_EXPR" "$JUMP_EXPR"
} > "$H/main.tf"
grep -q 'web_lb_weights' "$H/main.tf" || harness "the extracted cloudflare-lb.tf locals do not define web_lb_weights"

con() { # con <expr> [terraform -var args...] -> stdout of console (JSON-encoded), rc in CON_RC
  local expr="$1"; shift
  CON_OUT="$(cd "$H" && printf '%s\n' "$expr" | timeout 120 terraform console -no-color "$@" 2>&1)"; CON_RC=$?
  CON_FLAT="$(printf '%s' "$CON_OUT" | tr -d '\342\224\202\225\267\265' | tr -s '[:space:]' ' ')"  # unwrap the boxed diagnostic
}
con 'jsonencode(local.web_lb_weights)';                  eq "console: default pool weights (web-1 1, web-2 1 = live)" "$CON_OUT" '"{\"web-1\":1,\"web-2\":1}"'
con 'jsonencode(local.web_lb_weights)' -var web2_lb_weight=0; eq "console: the drain act still lands on web-2" "$CON_OUT" '"{\"web-1\":1,\"web-2\":0}"'
con 'local.derived_ips';                       eq "console: derived web IP list" "$CON_OUT" '"10.0.1.10,10.0.1.11"'
DERIVED_IPS="$(printf '%s' "$CON_OUT" | tr -d '"')"
con 'local.jump_ip';                           eq "console: the jump host is web-1 (unchanged)" "$CON_OUT" '"10.0.1.10"'
JUMP_IP="$(printf '%s' "$CON_OUT" | tr -d '"')"
con 'local.connector';                         eq "console: the tunnel connector is web-2 (unchanged)" "$CON_OUT" '"web-2"'
con 'local.primary';                           eq "console: the luks-monitor primary is web-1 (unchanged)" "$CON_OUT" '"web-1"'

W1='"web-1"={location="hel1",private_ip="10.0.1.10",lb_weight=1,luks_monitor_profile="primary",jump=true}'
W2='"web-2"={location="hel1",private_ip="10.0.1.11",server_type="cpx22",lb_weight=1,tunnel_connector=true}'
W3='"web-3"={location="hel1",private_ip="10.0.1.12",server_type="cpx22"}'
con 'jsonencode(local.web_lb_weights)' -var "web_hosts={${W1},${W2},${W3}}"
eq "third key: web-3 joins the pool drained (declared weight defaults to 0)" "$CON_OUT" '"{\"web-1\":1,\"web-2\":1,\"web-3\":0}"'
con 'local.derived_ips' -var "web_hosts={${W1},${W2},${W3}}"
eq "third key: web-3 joins the derived IP list in key order" "$CON_OUT" '"10.0.1.10,10.0.1.11,10.0.1.12"'
con 'jsonencode(local.web_lb_weights)' -var "web_hosts={${W1},${W2},${W3}}" -var web2_lb_weight=0
eq "third key: the web-2 drain does not touch web-1 or web-3" "$CON_OUT" '"{\"web-1\":1,\"web-2\":0,\"web-3\":0}"'
con 'jsonencode(local.web_lb_ungated)'
eq "ungated: today only web-1 serves outside the drain gate" "$CON_OUT" '"[\"web-1\"]"'
W3P='"web-3"={location="hel1",private_ip="10.0.1.12",server_type="cpx22",lb_weight=1}'
con 'jsonencode(local.web_lb_ungated)' -var "web_hosts={${W1},${W2},${W3P}}"
eq "ungated: web-3 declared at weight 1 is a second ungated host (the pool precondition refuses it)" "$CON_OUT" '"[\"web-1\",\"web-3\"]"'
con 'local.web_lb_ungated_ok'
eq "ungated: today's config passes the ungated-host condition" "$CON_OUT" 'true'
con 'local.web_lb_ungated_ok' -var "web_hosts={${W1},${W2},${W3P}}"
eq "ungated: a second ungated host fails the condition" "$CON_OUT" 'false'
W1D='"web-1"={location="hel1",private_ip="10.0.1.10",lb_weight=0,luks_monitor_profile="primary",jump=true}'
con 'local.web_lb_ungated_ok' -var "web_hosts={${W1D},${W2},${W3P}}"
eq "ungated: a swap (primary drained, standby web-3 at weight 1) fails the condition" "$CON_OUT" 'false'
# The rows above all put every singleton role on web-1, so these separate "is the primary" from "is web-1",
# "is the jump host" and "is the first key" (review: an alias predicate survived the three rows above).
W1J0='"web-1"={location="hel1",private_ip="10.0.1.10",lb_weight=0,jump=true}'
W1J1='"web-1"={location="hel1",private_ip="10.0.1.10",lb_weight=1,jump=true}'
W3R1='"web-3"={location="hel1",private_ip="10.0.1.12",server_type="cpx22",lb_weight=1,luks_monitor_profile="primary"}'
W3R0='"web-3"={location="hel1",private_ip="10.0.1.12",server_type="cpx22",lb_weight=0,luks_monitor_profile="primary"}'
con 'local.web_lb_ungated_ok' -var "web_hosts={${W1D},${W2}}"
eq "ungated: no host outside the gate (primary drained, web-2 gated) passes the condition" "$CON_OUT" 'true'
con 'local.web_lb_ungated_ok' -var "web_hosts={${W1J0},${W2},${W3R1}}"
eq "ungated: the primary role moved to web-3, serving ungated, passes (a deliberate role move, CTO ruling)" "$CON_OUT" 'true'
con 'local.web_lb_ungated_ok' -var "web_hosts={${W1J1},${W2},${W3R0}}"
eq "ungated: the jump host serving ungated while web-3 is the primary fails the condition" "$CON_OUT" 'false'
# The precondition is what turns that condition into a refusal; console cannot evaluate resource lifecycle, so pin it.
eq "ungated: the GA pool's precondition is the ungated-host condition" \
  "$(awk '/^resource "cloudflare_load_balancer_pool" "web_1"/,/^}/' "$LB" | grep -cE '^[[:space:]]*condition[[:space:]]*=[[:space:]]*local\.web_lb_ungated_ok[[:space:]]*$')" 1

refuse() { # refuse <name> <web_hosts HCL> <message fragment>
  con 'jsonencode(local.web_lb_weights)' -var "web_hosts=$2"
  cases=$((cases + 1))
  if [[ "$CON_RC" -ne 0 ]] && grep -qF "$3" <<<"$CON_FLAT"; then pass "$1"; else fail "$1 (rc=$CON_RC, want a refusal naming [$3])"; fi
}
refuse "refuse: two luks-monitor primaries" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.11\",luks_monitor_profile=\"primary\",tunnel_connector=true}}" "exactly one primary host"
refuse "refuse: no luks-monitor primary" "{\"web-1\"={location=\"hel1\",private_ip=\"10.0.1.10\",jump=true},${W2}}" "exactly one primary host"
refuse "refuse: an unknown luks-monitor profile" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.11\",luks_monitor_profile=\"spare\",tunnel_connector=true}}" "must be primary or standby"
refuse "refuse: two jump hosts" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.11\",jump=true,tunnel_connector=true}}" "exactly one host jump = true"
refuse "refuse: no jump host" "{\"web-1\"={location=\"hel1\",private_ip=\"10.0.1.10\",luks_monitor_profile=\"primary\"},${W2}}" "exactly one host jump = true"
refuse "refuse: two tunnel connectors" "{\"web-1\"={location=\"hel1\",private_ip=\"10.0.1.10\",luks_monitor_profile=\"primary\",jump=true,tunnel_connector=true},${W2}}" "exactly one host tunnel_connector = true"
refuse "refuse: no tunnel connector" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.11\"}}" "exactly one host tunnel_connector = true"
refuse "refuse: a duplicate private_ip" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.10\",tunnel_connector=true}}" "private_ip values must be unique"
refuse "refuse: the gateway address (.1)" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.1\",tunnel_connector=true}}" "last octet must be 2-254"
refuse "refuse: an address outside the subnet" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.2.11\",tunnel_connector=true}}" "10.0.1.0/24 private subnet"
refuse "refuse: lb_weight other than 0 or 1" "{${W1},\"web-2\"={location=\"hel1\",private_ip=\"10.0.1.11\",lb_weight=2,tunnel_connector=true}}" "lb_weight must be 0"

# ── PARITY: every hand-kept WEB_HOST_PRIVATE_IPS copy equals the derived list ──────────────────
# Workflows cannot read Terraform at run time, so the copies stay literal; this pins them to the console values.
[[ -n "${DERIVED_IPS:-}" && -n "${JUMP_IP:-}" ]] || harness "the console did not yield the derived IP list and the jump address"
COPIES="$(cd "$ROOT" && git grep -hE '^[[:space:]]*WEB_HOST_PRIVATE_IPS:[[:space:]]*"' -- '.github/workflows/*.yml' | sed -E 's/^[[:space:]]*WEB_HOST_PRIVATE_IPS:[[:space:]]*"([^"]*)".*/\1/')"
NCOPIES="$(printf '%s\n' "$COPIES" | grep -c . || true)"
MIN_COPIES=8
if [[ "$NCOPIES" -lt "$MIN_COPIES" ]]; then
  printf 'web-hosts-generic: FAIL (found %d WEB_HOST_PRIVATE_IPS workflow copies; floor %d - the parity scan may be blind)\n' "$NCOPIES" "$MIN_COPIES" >&2
  exit 1
fi
eq "parity: every workflow WEB_HOST_PRIVATE_IPS copy equals the list derived from var.web_hosts ($NCOPIES copies)" \
  "$(printf '%s\n' "$COPIES" | sort -u | paste -sd'|' -)" "$DERIVED_IPS"
# The singular WEB_HOST_PRIVATE_IP copies are the bridge/dial target behind the ssh. jump AND the /mnt/data and git-data
# operations target. Both roles are web-1 today, so the pin is the jump address; the bastion PR must split the roles.
JCOPIES="$(cd "$ROOT" && git grep -hE '^[[:space:]]*WEB_HOST_PRIVATE_IP:[[:space:]]*"' -- '.github/workflows/*.yml' | sed -E 's/^[[:space:]]*WEB_HOST_PRIVATE_IP:[[:space:]]*"([^"]*)".*/\1/')"
NJCOPIES="$(printf '%s\n' "$JCOPIES" | grep -c . || true)"
if [[ "$NJCOPIES" -lt 3 ]]; then
  printf 'web-hosts-generic: FAIL (found %d WEB_HOST_PRIVATE_IP workflow copies; floor 3 - the jump parity scan may be blind)\n' "$NJCOPIES" >&2
  exit 1
fi
eq "parity: every workflow WEB_HOST_PRIVATE_IP copy is the jump host's address, web-1 today ($NJCOPIES copies)" \
  "$(printf '%s\n' "$JCOPIES" | sort -u | paste -sd'|' -)" "$JUMP_IP"

# ── RATCHET: web-1 literals outside the knowledge base only shrink ────────────────────────────
# Ceilings are the counts measured when this suite landed (2026-11-10). A later PR that removes a
# literal lowers the ceiling in the same commit; one that adds a literal reds here. PR 7 of the #9421
# sequence drives both to zero. Markdown and the knowledge base are history, not configuration.
count_lit() { # count_lit <ERE>
  (cd "$ROOT" && git ls-files -z -- ':!knowledge-base/**' ':!*.md' ":!$SELF_REL" | xargs -0 grep -ohE "$1" 2>/dev/null | wc -l | tr -d ' ')
}
IP_CEIL=318  # re-baselined at the origin/main merge (f6c475f15b): +9 from main's placement-decision-forward-9137 follow-through test (+43 at 4aadbe8109), none from this PR
N_IP="$(count_lit '10\.0\.1\.10([^0-9]|$)')"
cases=$((cases + 1))
if [[ "$N_IP" -le "$IP_CEIL" && "$N_IP" -gt 0 ]]; then pass "ratchet: web-1 private-IP literal count $N_IP <= $IP_CEIL"; else fail "ratchet: web-1 private-IP literal count $N_IP exceeds the ceiling $IP_CEIL (or reads 0 - lower the ceiling to 0 deliberately)"; fi
KEY_CEIL=415  # re-baselined at 4aadbe8109: +5 from main (host-private-ip.ts, exec-placement-forward test); unchanged at f6c475f15b
N_KEY="$(count_lit '"web-1"')"
cases=$((cases + 1))
if [[ "$N_KEY" -le "$KEY_CEIL" && "$N_KEY" -gt 0 ]]; then pass "ratchet: \"web-1\" literal count $N_KEY <= $KEY_CEIL"; else fail "ratchet: \"web-1\" literal count $N_KEY exceeds the ceiling $KEY_CEIL (or reads 0 - lower the ceiling to 0 deliberately)"; fi

# ── CENSUS: each row of web-host-bound-state-census.md still holds ────────────────────────────
GW="$DIR/egress-gateway-bootstrap.sh"
ok "census C1: the baked egress-gateway bootstrap creates the token directory" \
  "$(grep -qE '^mkdir -p "\$TOKEN_DIR"$' "$GW" && grep -qE '^TOKEN_DIR="\$\{EGRESS_GW_TOKEN_DIR:-/var/lib/soleur/egress-tokens\}"$' "$GW"; echo $?)"
GW_AT="$(grep -nE '^  - /usr/local/bin/egress-gateway-bootstrap\.sh$' "$CI_YML" | head -1 | cut -d: -f1)"
MOUNT_AT="$(grep -nE -- '-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens' "$CI_YML" | head -1 | cut -d: -f1)"
ok "census C1: runcmd runs that bootstrap before the app container mounts the directory" \
  "$([[ -n "$GW_AT" && -n "$MOUNT_AT" && "$GW_AT" -lt "$MOUNT_AT" ]]; echo $?)"
ok "census C2: the only cron path a birth writes is /etc/cron.weekly/docker-cleanup, from user_data; no crontab" \
  "$([[ "$(grep -ohE '/etc/cron[^ ]*' "$CI_YML" "$DIR/soleur-host-bootstrap.sh" | sort -u | paste -sd, -)" == "/etc/cron.weekly/docker-cleanup" ]] && ! grep -qE '(^|[^a-z_])crontab([^a-z_]|$)' "$CI_YML" "$DIR/soleur-host-bootstrap.sh"; echo $?)"
ok "census C2: host timers are enabled from user_data" "$([[ "$(grep -cE '^  - systemctl enable --now [a-z0-9-]+\.timer$' "$CI_YML")" -ge 5 ]]; echo $?)"
ok "census C3: probe heartbeat key names derive from the host key at birth" \
  "$(grep -qE "^HOST_UPPER=\"\\\$\(printf '%s' \"\\\$SOLEUR_HOST_KEY\" \| tr 'a-z-' 'A-Z_'\)\"$" "$DIR/web-probe-envwrite.sh"; echo $?)"
N_KEYS="$(block "$VARS" 'variable "web_hosts"' | sed -n '/^  default = {/,/^  }/p' | grep -cE '^    "web-[0-9]+"[[:space:]]*=')"
N_HB="$(grep -cE '^resource "betteruptime_heartbeat" "host_kernel_web_[0-9]+"' "$UPT")"
eq "census C4: one host-kernel heartbeat per var.web_hosts key ($N_KEYS keys)" "$N_HB" "$N_KEYS"
ok "census C3: each probe URL's Doppler secret is minted per var.web_hosts key" \
  "$([[ "$(awk '/^resource "doppler_secret" "web_(zot_consumer|nic_guard|bash_synthetic)_url"/{r=1} r&&/^  for_each = var\.web_hosts$/{n++; r=0} /^}/{r=0} END{print n+0}' "$DIR/web-probe.tf")" -eq 3 ]]; echo $?)"
ok "census C5: the session-proxy certificate SANs derive from var.web_hosts" \
  "$(grep -qE '^  ip_addresses = \[for h in values\(var\.web_hosts\) : h\.private_ip\]$' "$DIR/proxy-tls.tf" && grep -qE '^  dns_names    = concat\(keys\(var\.web_hosts\), \["localhost"\]\)$' "$DIR/proxy-tls.tf"; echo $?)"
ok "census C6: no Terraform resource derives the relay roster or allowlist (hand-kept Doppler values)" \
  "$(! grep -qE '"(SOLEUR_HOST_ROSTER|SOLEUR_PROXY_PEER_ALLOWLIST)"' < <(grep -hvE '^[[:space:]]*#' "$DIR"/*.tf); echo $?)"
eq "census C7: one committed SSH host-key pin per var.web_hosts key ($N_KEYS keys)" \
  "$(find "$DIR" -maxdepth 1 -name 'web-*-ssh-host-key.pub' | wc -l | tr -d ' ')" "$N_KEYS"
ok "census: the doc names all seven rows" "$([[ "$(grep -cE '^\| C[1-7] \|' "$CENSUS")" -eq 7 ]]; echo $?)"

# ── Anti-vacuity floor ────────────────────────────────────────────────────────────────────────
MIN_CASES=42
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'web-hosts-generic: FAIL (only %d assertions ran; floor %d - the suite may have been truncated)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'web-hosts-generic: FAIL (passes %d + fails %d != cases %d - a helper stopped counting)\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'web-hosts-generic: FAIL (%d assertions, %d failed)\n' "$cases" "$fails" >&2
  exit 1
fi
printf 'web-hosts-generic: PASS (%d assertions, 0 failed)\n' "$cases"
