#!/usr/bin/env bash
# Guard 2 (#12008 item 3): the public TCP surface the non-web hosts DECLARE in Terraform, checked
# from the repository text alone. No SSH, no network, no credential.
#
# WHAT THIS IS. A declared-design invariant, like firewall-9000-deny.test.sh: a non-web firewall
# declares no inbound rule, every mapped server is bound to its firewall, nothing unmapped exists, and the
# parser demonstrably reads the web firewall (the control). It is a check on what the repository
# DECLARES. It is not live state: console drift, a stale attachment id (#6442) and a firewall that was
# never applied need a live read, which is a session-only step (ADR-322) and is NOT done here.
# Tunnel ingress (tunnel.tf) is outbound-initiated and opens no inbound public port, so it is out of scope.
#
# Mapping below = one row per server resource label: server | firewall | binding kind.
#   control     the web firewall: it MUST parse with inbound rules (parser liveness), and its only
#               dynamic rule is the documented admin-address block.
#   inline      the server carries firewall_ids naming its firewall (bound at creation).
#   attachment  bound by a separate hcloud_firewall_attachment (attaches after first boot, #6442).
#   excluded    default-off, count-gated server whose firewall is not part of the always-on surface.
# ATTACH_ALLOW is the set of non-control servers that may stay attachment-bound. It only shrinks:
# moving a server to inline binding means deleting its entry here; adding an entry is a review event.
#
# A new hcloud_server that is not in the mapping makes this suite fail closed, by design: the first
# infra change that adds a server must add its row here.
#
# Parser note: text parsing by resource boundary and brace depth over every .tf file in the directory.
# Comment lines are dropped first. Failure messages name resource addresses only (already public in
# the repo): no counts, no ports, no addresses.
# A trailing comment that itself contains a double quote is not stripped; the parse then fails closed
# (a finding), never silent.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REAL_TF="$ROOT/apps/web-platform/infra"

readonly MAP='web|web|control
git_data|git_data|attachment
registry|registry|attachment
inngest|inngest|inline
grok_dogfood|grok_dogfood|excluded'
readonly ATTACH_ALLOW='git_data registry'

pass=0; fail=0
FAILURES=()
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

D="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'rm -rf "$D"' EXIT
export TMPDIR="$D"

# ---- the analyzer: records, then findings --------------------------------------------------------
records() { # dir -> tab-separated SERVER / FIREWALL / ATTACH records, one per resource
  local f
  for f in $(LC_ALL=C ls "$1"/*.tf 2>/dev/null); do
    sed -E -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]+#[^"]*$//' "$f"
  done | awk '
    function collect(s, lit,   out, re) {
      out = ""; re = lit "[A-Za-z0-9_]+"
      while (match(s, re)) {
        out = out (out == "" ? "" : ",") substr(s, RSTART + length(lit), RLENGTH - length(lit))
        s = substr(s, RSTART + RLENGTH)
      }
      return out
    }
    function count_of(s, ch,   t) { t = s; return gsub(ch, ch, t) }
    /^resource[[:space:]]+"[a-z_]+"[[:space:]]+"[A-Za-z0-9_]+"[[:space:]]*\{/ && blk == "" {
      blk = $2; lab = $3; gsub(/"/, "", blk); gsub(/"/, "", lab)
      depth = 1; hascount = 0; fwids = ""; inb = 0; ndyn = 0; ndynadmin = 0; nfe = 0
      in_rule = 0; in_dyn = 0; in_fwids = 0; in_srv = 0; fwid = ""; srvs = ""; dirout = 0
      next
    }
    blk == "" { next }
    {
      line = $0; d = depth
      if (blk == "hcloud_server" && d == 1) {
        if (line ~ /^[[:space:]]*count[[:space:]]*=/) hascount = 1
        if (line ~ /^[[:space:]]*firewall_ids[[:space:]]*=/) in_fwids = 1
      }
      if (in_fwids) { fwids = fwids (fwids == "" || collect(line, "hcloud_firewall.") == "" ? "" : ",") collect(line, "hcloud_firewall."); if (line ~ /\]/) in_fwids = 0 }
      if (blk == "hcloud_firewall_attachment" && d == 1) {
        if (line ~ /^[[:space:]]*firewall_id[[:space:]]*=/) fwid = collect(line, "hcloud_firewall.")
        if (line ~ /^[[:space:]]*server_ids[[:space:]]*=/) in_srv = 1
      }
      if (in_srv) { c = collect(line, "hcloud_server."); if (c != "") srvs = srvs (srvs == "" ? "" : ",") c; if (line ~ /\]/) in_srv = 0 }
      if (blk == "hcloud_firewall") {
        if (d == 1 && line ~ /^[[:space:]]*(count|for_each)[[:space:]]*=/) nfe++
        if (in_dyn && line ~ /for_each[[:space:]]*=[[:space:]]*var\.admin_ips[[:space:]]*$/) ndynadmin++
        if (!in_rule && !in_dyn && d == 1 && line ~ /^[[:space:]]*dynamic[[:space:]]+"rule"/) { ndyn++; in_dyn = 1; dyn_d = d }
        else if (!in_rule && !in_dyn && d == 1 && line ~ /^[[:space:]]*rule[[:space:]]*\{/) { in_rule = 1; rule_d = d; dirout = 0 }
        else if (in_rule && line ~ /direction[[:space:]]*=[[:space:]]*"out"/) dirout = 1
      }
      depth = d + count_of(line, "{") - count_of(line, "}")
      if (in_rule && depth <= rule_d) { if (!dirout) inb++; in_rule = 0 }
      if (in_dyn && depth <= dyn_d) in_dyn = 0
      if (depth <= 0) {
        if (blk == "hcloud_server") printf "SERVER\t%s\t%d\t%s\n", lab, hascount, fwids
        else if (blk == "hcloud_firewall") printf "FIREWALL\t%s\t%d\t%d\t%d\t%d\n", lab, inb, ndyn, ndynadmin, nfe
        else if (blk == "hcloud_firewall_attachment") printf "ATTACH\t%s\t%s\t%s\n", lab, fwid, srvs
        blk = ""
      }
    }'
}

field() { awk -F'\t' -v k="$1" -v l="$2" -v n="$3" '$1 == k && $2 == l { print $n; exit }'; } # kind label col <records

analyze() { # dir -> prints FINDING lines; empty output = clean
  local dir="$1" rec nserv nfw row srv fw kind has fwids found attach_actual="" a
  rec="$(records "$dir")"
  nserv="$(grep -c '^SERVER' <<<"$rec")"; nfw="$(grep -c '^FIREWALL' <<<"$rec")"
  [ "$nserv" -gt 0 ] || { echo "FINDING no-servers directory"; return; }
  [ "$nfw" -gt 0 ] || echo "FINDING no-firewalls directory"
  while IFS=$'\t' read -r _ srv _ _; do
    grep -q "^${srv}|" <<<"$MAP" || echo "FINDING unmapped-server hcloud_server.${srv}"
  done < <(grep '^SERVER' <<<"$rec")
  while IFS='|' read -r srv fw kind; do
    has="$(grep -c "^SERVER"$'\t'"${srv}"$'\t' <<<"$rec")"
    if [ "$kind" = excluded ]; then
      if [ "$has" -gt 0 ] && [ "$(field SERVER "$srv" 3 <<<"$rec")" != 1 ]; then echo "FINDING excluded-not-gated hcloud_server.${srv}"; fi
      continue
    fi
    [ "$has" -gt 0 ] || { [ "$kind" = control ] && echo "FINDING control-server-missing hcloud_server.${srv}"; continue; }
    if [ "$(grep -c "^FIREWALL"$'\t'"${fw}"$'\t' <<<"$rec")" -eq 0 ]; then echo "FINDING firewall-missing hcloud_firewall.${fw}"; continue; fi
    # binding: inline wins, then an attachment naming both this firewall and this server
    fwids="$(field SERVER "$srv" 4 <<<"$rec")"
    if grep -qE "(^|,)${fw}(,|$)" <<<"$fwids"; then
      found=inline
    elif awk -F'\t' -v f="$fw" -v s="$srv" '$1 == "ATTACH" && $3 == f { n = split($4, a, ","); for (i = 1; i <= n; i++) if (a[i] == s) ok = 1 } END { exit ok ? 0 : 1 }' <<<"$rec"; then
      found=attachment
    else
      found=none
    fi
    [ "$found" != none ] || echo "FINDING unbound hcloud_server.${srv}"
    if [ "$found" = attachment ] && [ "$kind" != control ]; then attach_actual="$attach_actual $srv"; fi
    local inb ndyn ndyna nfe
    inb="$(field FIREWALL "$fw" 3 <<<"$rec")"; ndyn="$(field FIREWALL "$fw" 4 <<<"$rec")"
    ndyna="$(field FIREWALL "$fw" 5 <<<"$rec")"; nfe="$(field FIREWALL "$fw" 6 <<<"$rec")"
    if [ "$kind" = control ]; then
      [ "${inb:-0}" -gt 0 ] || echo "FINDING parser-liveness hcloud_firewall.${fw}"
      if [ "${ndyn:-0}" -gt "${ndyna:-0}" ] || [ "${nfe:-0}" -gt 0 ]; then echo "FINDING dynamic-rule hcloud_firewall.${fw}"; fi
    else
      [ "${inb:-0}" -eq 0 ] || echo "FINDING inbound-rule hcloud_firewall.${fw}"
      if [ "${ndyn:-0}" -gt 0 ] || [ "${nfe:-0}" -gt 0 ]; then echo "FINDING dynamic-rule hcloud_firewall.${fw}"; fi
    fi
  done <<<"$MAP"
  for a in $attach_actual; do
    case " $ATTACH_ALLOW " in *" $a "*) : ;; *) echo "FINDING attachment-not-allowed hcloud_server.${a}" ;; esac
  done
  for a in $ATTACH_ALLOW; do
    case " $attach_actual " in *" $a "*) : ;; *) echo "FINDING allowlist-stale hcloud_server.${a}" ;; esac
  done
}

# ---- fixture builders (synthesized; resource labels only, no real names or values) ---------------
tf_server() { # label [count] [firewall-label]
  printf 'resource "hcloud_server" "%s" {\n' "$1"
  [ "${2:-}" = count ] && printf '  count = local.enabled ? 1 : 0\n'
  [ -n "${3:-}" ] && printf '  firewall_ids = [hcloud_firewall.%s.id]\n' "$3"
  printf '}\n\n'
}
tf_fw_plain() { # label  (deny-all: one outbound rule only)
  printf 'resource "hcloud_firewall" "%s" {\n  rule {\n    direction = "out"\n    protocol = "tcp"\n    port = "443"\n  }\n}\n\n' "$1"
}
tf_fw_web() {
  printf '# a comment mentioning rule { and dynamic "rule" must not count\n'
  printf 'resource "hcloud_firewall" "web" {\n  dynamic "rule" {\n    for_each = var.admin_ips\n    content {\n      direction = "in"\n      protocol = "tcp"\n      port = "22"\n      source_ips = [rule.value]\n    }\n  }\n  rule {\n    direction = "in"\n    protocol = "tcp"\n    port = "443"\n  }\n}\n\n'
}
tf_attach() { # label firewall server-expr
  printf 'resource "hcloud_firewall_attachment" "%s" {\n  firewall_id = hcloud_firewall.%s.id\n  server_ids  = [%s]\n}\n\n' "$1" "$2" "$3"
}
base_fixture() { # dir
  mkdir -p "$1"
  {
    tf_server web
    tf_fw_web
    tf_attach web web 'for h in hcloud_server.web : h.id'
    tf_server git_data; tf_fw_plain git_data; tf_attach git_data git_data 'hcloud_server.git_data.id'
    tf_server registry; tf_fw_plain registry; tf_attach registry registry 'hcloud_server.registry.id'
    tf_server inngest "" inngest; tf_fw_plain inngest
    printf 'removed {\n  from = hcloud_firewall_attachment.inngest\n  lifecycle {\n    destroy = false\n  }\n}\n\n'
    tf_server grok_dogfood count; tf_fw_plain grok_dogfood
  } > "$1/main.tf"
}
clone() { rm -rf "$D/$2"; cp -r "$D/$1" "$D/$2"; }

# ---- expectations --------------------------------------------------------------------------------
CASES=0
expect_clean() { # label dir
  local out; out="$(analyze "$D/$2")"
  [ -z "$out" ] && ok "$1" || bad "$1 -> unexpected findings: $(tr '\n' ';' <<<"$out")"
}
expect_finding() { # label dir code address
  local out; out="$(analyze "$D/$2")"
  if grep -qxF "FINDING $3 $4" <<<"$out"; then
    ok "$1"
    if grep -qE '[0-9]' <<<"$out"; then bad "$1 -> a finding carries a digit (counts, ports and addresses are not printed)"; fi
  else
    bad "$1 -> no 'FINDING $3 $4' in: $(tr '\n' ';' <<<"$out")"
  fi
}

# Instrument self-test: the two helpers must accept and reject, reported without the helpers.
base_fixture "$D/ctl"
_p=$pass; _f=$fail
expect_clean "ctl-positive" ctl >/dev/null
expect_clean "ctl-negative (deliberately wrong)" nonexistent_dir >/dev/null
expect_finding "ctl-finding-wrong" ctl no-such-code x >/dev/null
if [ "$pass" -ne $((_p + 1)) ] || [ "$fail" -ne $((_f + 2)) ]; then
  printf '[FATAL] instrument self-test failed (pass %s->%s fail %s->%s)\n' "$_p" "$pass" "$_f" "$fail" >&2; exit 1
fi
pass=$_p; fail=$_f; FAILURES=()

case_baseline() {
  CASES=$((CASES + 1))
  expect_clean "baseline fixture is clean (positive control)" ctl
  clone ctl out_only; sed -i '/resource "hcloud_firewall" "git_data" {/a\  rule {\n    direction = "out"\n    protocol = "udp"\n  }' "$D/out_only/main.tf"
  expect_clean "an extra outbound rule on a non-web firewall is fine" out_only
}
case_inbound() {
  CASES=$((CASES + 1))
  clone ctl inb; sed -i '/resource "hcloud_firewall" "git_data" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n    port = "22"\n  }' "$D/inb/main.tf"
  expect_finding "inbound rule on a non-web firewall" inb inbound-rule hcloud_firewall.git_data
  clone ctl inb2; sed -i '/resource "hcloud_firewall" "git_data" {/a\  rule {\n    protocol = "tcp"\n  }' "$D/inb2/main.tf"
  expect_finding "a rule with no direction counts as inbound" inb2 inbound-rule hcloud_firewall.git_data
}
case_second_member() {
  CASES=$((CASES + 1))
  clone ctl sm; sed -i '/resource "hcloud_firewall" "inngest" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n  }' "$D/sm/main.tf"
  expect_finding "a violation in a LATER non-web firewall after compliant ones" sm inbound-rule hcloud_firewall.inngest
  clone ctl sm2; sed -i '/resource "hcloud_firewall" "registry" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n  }' "$D/sm2/main.tf"
  expect_finding "a violation in an EARLIER member while later ones are compliant" sm2 inbound-rule hcloud_firewall.registry
}
case_empty() {
  CASES=$((CASES + 1))
  mkdir -p "$D/empty"; : > "$D/empty/main.tf"
  expect_finding "a directory with no servers fails, never prints clean" empty no-servers directory
  clone ctl nofw; sed -i '/^resource "hcloud_firewall" "git_data"/,/^}/d' "$D/nofw/main.tf"
  expect_finding "a firewall resource missing for a mapped server" nofw firewall-missing hcloud_firewall.git_data
  mkdir -p "$D/onlysrv"; { tf_server web; tf_server git_data; } > "$D/onlysrv/main.tf"
  expect_finding "servers with zero firewall resources" onlysrv no-firewalls directory
}
case_liveness() {
  CASES=$((CASES + 1))
  clone ctl live; sed -i '/^resource "hcloud_firewall" "web"/,/^}/c\resource "hcloud_firewall" "web" {\n}' "$D/live/main.tf"
  expect_finding "the control (web) firewall with no rules fails: a parser that reads nothing cannot pass" live parser-liveness hcloud_firewall.web
  clone ctl webdyn; sed -i '/^resource "hcloud_firewall" "web" {/a\  dynamic "rule" {\n    for_each = var.other_ips\n    content {\n      direction = "in"\n    }\n  }' "$D/webdyn/main.tf"
  expect_finding "a non-admin dynamic rule on the web firewall" webdyn dynamic-rule hcloud_firewall.web
}
case_unmapped() {
  CASES=$((CASES + 1))
  clone ctl unm; tf_server brand_new >> "$D/unm/main.tf"
  expect_finding "a server that is not in the mapping (ADDS an instance the guard has never seen)" unm unmapped-server hcloud_server.brand_new
  clone ctl unm2; tf_server brand_new > "$D/unm2/aaa-first.tf"
  expect_finding "an unmapped server in a different file that sorts first" unm2 unmapped-server hcloud_server.brand_new
}
case_binding() {
  CASES=$((CASES + 1))
  clone ctl nb; sed -i '/^resource "hcloud_firewall_attachment" "git_data"/,/^}/d' "$D/nb/main.tf"
  expect_finding "a mapped server loses its attachment" nb unbound hcloud_server.git_data
  clone ctl nb2; sed -i '/firewall_ids/d' "$D/nb2/main.tf"
  expect_finding "a mapped server loses its inline firewall_ids line" nb2 unbound hcloud_server.inngest
  clone ctl nb3; sed -i 's/server_ids  = \[hcloud_server.registry.id\]/server_ids  = [hcloud_server.git_data.id]/' "$D/nb3/main.tf"
  expect_finding "an attachment that names the wrong server leaves the right one unbound" nb3 unbound hcloud_server.registry
}
case_ratchet() {
  CASES=$((CASES + 1))
  clone ctl rt; sed -i '/firewall_ids/d' "$D/rt/main.tf"; tf_attach inngest inngest 'hcloud_server.inngest.id' >> "$D/rt/main.tf"
  expect_finding "a server newly attachment-bound that is not in the allow-list" rt attachment-not-allowed hcloud_server.inngest
  clone ctl rt2; sed -i '/^resource "hcloud_firewall_attachment" "registry"/,/^}/d' "$D/rt2/main.tf"
  sed -i '/^resource "hcloud_server" "registry" {/a\  firewall_ids = [hcloud_firewall.registry.id]' "$D/rt2/main.tf"
  expect_finding "a server moved to inline binding while its allow-list entry remains (the list must shrink)" rt2 allowlist-stale hcloud_server.registry
}
case_dynamic() {
  CASES=$((CASES + 1))
  clone ctl dy; sed -i '/resource "hcloud_firewall" "registry" {/a\  dynamic "rule" {\n    for_each = var.admin_ips\n    content {\n      direction = "in"\n    }\n  }' "$D/dy/main.tf"
  expect_finding "a dynamic rule block on a non-web firewall is never silent" dy dynamic-rule hcloud_firewall.registry
  clone ctl dy2; sed -i '/resource "hcloud_firewall" "git_data" {/a\  for_each = toset(["a"])' "$D/dy2/main.tf"
  expect_finding "for_each on a non-web firewall is never silent" dy2 dynamic-rule hcloud_firewall.git_data
}
case_ignored_constructs() {
  CASES=$((CASES + 1))
  clone ctl cm; sed -i '/resource "hcloud_firewall" "git_data" {/a\# rule {\n# direction = "in"\n# unbalanced {' "$D/cm/main.tf"
  expect_clean "a rule that exists only inside comment lines is ignored" cm
  clone ctl cm2; sed -i '/resource "hcloud_firewall" "git_data" {/a\  labels = { note = "x" } # rule { direction = in {' "$D/cm2/main.tf"
  expect_clean "a rule mentioned in a trailing comment is ignored" cm2
  expect_clean "a removed block for an old attachment is ignored (present in the baseline)" ctl
}
case_noncanonical() {
  CASES=$((CASES + 1))
  mkdir -p "$D/nc"
  {
    printf 'resource "hcloud_firewall" "registry" {\n\t# odd indent and comments\n\tlabels = {}\n}\n\n'
    printf 'resource "hcloud_server" "registry" {\n  name = "fx"\n}\n\n'
    printf 'resource "hcloud_firewall_attachment" "registry" {\n  server_ids = [\n    hcloud_server.registry.id,\n  ]\n  firewall_id = hcloud_firewall.registry.id\n}\n\n'
    tf_server web; tf_fw_web; tf_attach web web 'for h in hcloud_server.web : h.id'
    tf_server git_data; tf_fw_plain git_data; tf_attach git_data git_data 'hcloud_server.git_data.id'
    printf 'resource "hcloud_server" "inngest" {\n  firewall_ids = [\n    hcloud_firewall.inngest.id,\n  ]\n}\nresource "hcloud_firewall" "inngest" {\n}\n'
    tf_server grok_dogfood count; tf_fw_plain grok_dogfood
  } > "$D/nc/other-name.tf"
  expect_clean "different labels order, attribute order, odd indent and multiline lists still pass (must-PASS non-canonical input)" nc
}
case_excluded() {
  CASES=$((CASES + 1))
  clone ctl ex; sed -i '/^resource "hcloud_server" "grok_dogfood"/,/^}/c\resource "hcloud_server" "grok_dogfood" {\n}' "$D/ex/main.tf"
  expect_finding "the excluded server must stay count-gated (default-off)" ex excluded-not-gated hcloud_server.grok_dogfood
}
case_real_tree() {
  CASES=$((CASES + 1))
  local out rec
  rec="$(records "$REAL_TF")"
  [ "$(grep -c '^SERVER' <<<"$rec")" -ge 4 ] && ok "real tree: the parser read at least four server resources (liveness)" || bad "real tree: fewer than four servers parsed"
  [ "$(field FIREWALL web 3 <<<"$rec")" -gt 0 ] 2>/dev/null && ok "real tree: the control firewall parsed with inbound rules" || bad "real tree: the control firewall parsed with no inbound rule"
  out="$(analyze "$REAL_TF")"
  [ -z "$out" ] && ok "real tree: the declared-design invariant holds (non-web firewalls deny inbound, every mapped server is bound, nothing unmapped)" \
    || bad "real tree: declared-design invariant violated: $(tr '\n' ';' <<<"$out")"
}

[ -d "$REAL_TF" ] || { printf '[FATAL] real Terraform directory missing\n' >&2; exit 1; }
case_baseline; case_inbound; case_second_member; case_empty; case_liveness; case_unmapped
case_binding; case_ratchet; case_dynamic; case_ignored_constructs; case_noncanonical
case_excluded; case_real_tree

# ---- anti-vacuity floors (reported with printf + exit, not through the helpers) ------------------
EXPECTED_CASES=12
if [ "$CASES" -lt "$EXPECTED_CASES" ]; then
  printf '[FATAL] case-count floor: ran %s cases, want >= %s (a case was deleted)\n' "$CASES" "$EXPECTED_CASES" >&2; exit 1
fi
MIN_ASSERTIONS=28
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: %s passed, want >= %s (an assertion was deleted)\n' "$pass" "$MIN_ASSERTIONS" >&2; exit 1
fi

printf '\n%s passed, %s failed (%s cases)\n' "$pass" "$fail" "$CASES"
if [ "$fail" -gt 0 ] || [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILURES:\n'; printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
exit 0
