#!/usr/bin/env bash
# Guard 2 (#12008 item 3): the public TCP surface the non-web hosts DECLARE in Terraform, checked
# from the repository text alone. No SSH, no network, no credential.
#
# WHAT THIS IS. A declared-design invariant, like firewall-9000-deny.test.sh: a non-web firewall
# declares no rule block at all (a future egress rule is then a deliberate edit here), every mapped server is
# bound to exactly its own firewall, nothing unmapped exists, and the parser demonstrably reads the web
# firewall (the control). It is a check on what the repository DECLARES. It is not live state: console
# drift, a stale attachment id (#6442) and a firewall that was never applied need a live read, which is a
# session-only step (ADR-322) and is NOT done here.
# Tunnel ingress (tunnel.tf) is outbound-initiated and opens no inbound public port, so it is out of scope.
#
# SCOPE. The *.tf files of ONE directory (apps/web-platform/infra). Other Terraform roots (rehearsal and
# staging roots) are other applies and are not read. Inside the directory the parser fails closed on what it
# cannot read: *.tf.json and *.tofu files, override files, tfvars that enable the default-off host, block
# comments, a resource header that is not the plain multi-line form, a heredoc or a stray quote inside an
# hcloud resource, a file that ends inside a resource, a module that is not listed in MODULE_ALLOW, an hcloud
# resource inside modules/, duplicate resource labels, an unmapped firewall, apply_to on any firewall, and
# any second firewall bound to a mapped server. Not covered: host-local nftables, public_net settings, and
# load balancers or floating ips (none are declared today). The web firewall is a liveness control only: extra
# static rules on it are allowed by design.
#
# Mapping below = one row per server resource label: server | firewall | kind.
#   control   the web firewall: it MUST parse with rules (parser liveness), and its only dynamic rule is the
#             documented admin-address block.
#   plain     a non-web server: its firewall declares no rule block, the server is not count/for_each
#             multiplied, and it is bound to exactly that firewall, either inline (firewall_ids, bound at
#             creation) or by a separate hcloud_firewall_attachment (attaches after first boot, #6442).
#   excluded  default-off, count-gated server whose firewall is not part of the always-on surface (its firewall
#             carries a dynamic admin-address SSH rule, so only the count gate and the absence of a static
#             rule are checked).
# ATTACH_ALLOW is the set of plain servers that may stay attachment-bound. It only shrinks: moving a server to
# inline binding means deleting its entry here; adding an entry is a review event. Editing the MAP kind column
# or ATTACH_ALLOW in the same diff as the Terraform is a deliberate act that review must see.
#
# A new hcloud_server that is not in the mapping makes this suite fail closed, by design: the first infra change
# that adds a server must add its MAP row here and decide inline versus attachment binding.
#
# Parser note: text parsing by resource boundary and brace depth over every .tf file in the directory. Strings are
# blanked and comments (#, //) are cut before braces are counted. Failure messages name resource addresses
# only (already public in the repo): no counts, no ports, no addresses.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REAL_TF="$ROOT/apps/web-platform/infra"

readonly MAP='web|web|control
git_data|git_data|plain
registry|registry|plain
inngest|inngest|plain
grok_dogfood|grok_dogfood|excluded'
readonly ATTACH_ALLOW='git_data registry'
readonly MODULE_ALLOW='git_data_userdata'

pass=0; fail=0
FAILURES=()
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

D="$(mktemp -d -t soleur-run.$$.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$D"' EXIT
export TMPDIR="$D"

# ---- the analyzer: records, then findings --------------------------------------------------------
records() { # dir -> tab-separated SERVER / FIREWALL / ATTACH / MODULE / UNSUPPORTED records
  local f
  for f in "$1"/*.tf; do
    [ -f "$f" ] || continue
    printf '@@FILE\n'
    cat "$f"
  done | awk '
    function rep(n,   s) { s = ""; while (n-- > 0) s = s "_"; return s }
    function count_of(s, ch,   n, i) { n = 0; while ((i = index(s, ch)) > 0) { n++; s = substr(s, i + 1) } return n }
    function collect(s, lit,   out, re, n) { # a token only counts when nothing identifier-like precedes it
      out = ""; re = lit; gsub(/[.]/, "[.]", re); re = "[^A-Za-z0-9_.]" re "[A-Za-z0-9_]+"; n = length(lit); s = " " s
      while (match(s, re)) {
        out = out (out == "" ? "" : ",") substr(s, RSTART + 1 + n, RLENGTH - 1 - n)
        s = substr(s, RSTART + RLENGTH - 1)
      }
      return out
    }
    # B = the line with every string blanked to underscores and any comment cut; C = the same prefix of the raw line
    function scrub(raw,   s, out, p1, p2, cut) {
      s = raw; gsub(/\\"/, "__", s); out = ""
      while (match(s, /"[^"]*"/)) { out = out substr(s, 1, RSTART - 1) rep(RLENGTH); s = substr(s, RSTART + RLENGTH) }
      out = out s
      p1 = index(out, "#"); p2 = index(out, "//"); cut = 0
      if (p1 > 0) cut = p1
      if (p2 > 0 && (cut == 0 || p2 < cut)) cut = p2
      if (cut > 0) out = substr(out, 1, cut - 1)
      B = out; C = substr(raw, 1, length(out))
    }
    /^@@FILE$/ { if (blk != "") print "UNSUPPORTED\tunterminated-resource"; blk = ""; next }
    {
      scrub($0); b = B; c = C
      if (b ~ /\/\*/) print "UNSUPPORTED\tblock-comment"
      if (blk == "") {
        if (inmod) {
          if (c ~ /^[[:space:]]*source[[:space:]]*=/) { t = c; sub(/^[^"]*"/, "", t); sub(/".*$/, "", t); print "MODSRC\t" modlab "\t" t }
          mdepth += count_of(b, "{") - count_of(b, "}")
          if (mdepth <= 0) inmod = 0
          next
        }
        if (b ~ /^[[:space:]]*module[[:space:]]/) {
          t = c; sub(/^[ \t]*module[ \t]+/, "", t); split(t, h, /[ \t{]+/); gsub(/[^A-Za-z0-9_-]/, "", h[1]); print "MODULE\t" h[1]
          modlab = h[1]; mdepth = count_of(b, "{") - count_of(b, "}"); inmod = (mdepth > 0)
          next
        }
        if (c ~ /^[[:space:]]*resource[[:space:]]+("|hcloud_)/) {
          if (c ~ /^[[:space:]]*resource[[:space:]]+"?[A-Za-z0-9_-]+"?[[:space:]]+"?[A-Za-z0-9_-]+"?[[:space:]]*\{[[:space:]]*$/) {
            t = c; sub(/^[ \t]*resource[ \t]+/, "", t); split(t, h, /[ \t{]+/)
            blk = h[1]; lab = h[2]; gsub(/[^A-Za-z0-9_-]/, "", blk); gsub(/[^A-Za-z0-9_-]/, "", lab)
            depth = 1; hascount = 0; gated = 0; hasfe = 0; fwids = ""; inb = 0; ndyn = 0; ndynadmin = 0; nfe = 0; napply = 0
            in_dyn = 0; dyn_has = 0; in_fwids = 0; in_srv = 0; fwid = ""; srvs = ""
            next
          }
          print "UNSUPPORTED\tresource-form"
        }
        next
      }
      d = depth; hc = (blk ~ /^hcloud_/)
      # a resource header at column 0 while a block is open means the brace count drifted: fail closed
      if (c ~ /^resource[ \t]+"/) print "UNSUPPORTED\tbrace-desync"
      if (hc && c ~ /\$\{[^}]*"/) print "UNSUPPORTED\tnested-interpolation"
      if (hc && b ~ /<</) print "UNSUPPORTED\theredoc"
      if (hc && index(b, "\"") > 0) print "UNSUPPORTED\tunbalanced-quote"
      if (blk == "hcloud_server" && d == 1) {
        if (b ~ /^[[:space:]]*count[[:space:]]*=/) { hascount = 1; if (b ~ /\?[[:space:]]*1[[:space:]]*:[[:space:]]*0/ && b ~ /(grok_dogfood_enabled|enable_grok_dogfood)/) gated = 1 }
        if (b ~ /^[[:space:]]*for_each[[:space:]]*=/) hasfe = 1
        if (b ~ /^[[:space:]]*firewall_ids[[:space:]]*=/) in_fwids = 1
      }
      if (in_fwids) { cc = collect(b, "hcloud_firewall."); fwids = fwids (fwids == "" || cc == "" ? "" : ",") cc; if (b ~ /\]/) in_fwids = 0 }
      if (blk == "hcloud_firewall_attachment" && d == 1) {
        if (b ~ /^[[:space:]]*firewall_id[[:space:]]*=/) fwid = collect(b, "hcloud_firewall.")
        if (b ~ /^[[:space:]]*server_ids[[:space:]]*=/) in_srv = 1
      }
      if (in_srv) { cc = collect(b, "hcloud_server."); if (cc != "") srvs = srvs (srvs == "" ? "" : ",") cc; if (b ~ /\]/) in_srv = 0 }
      if (blk == "hcloud_firewall") {
        if (d == 1 && b ~ /^[[:space:]]*(count|for_each)[[:space:]]*=/) nfe++
        if (d == 1 && b ~ /^[[:space:]]*apply_to[[:space:]]*\{/) napply++
        if (in_dyn && !dyn_has && b ~ /for_each[[:space:]]*=[[:space:]]*var\.admin_ips[[:space:]]*$/) { ndynadmin++; dyn_has = 1 }
        if (!in_dyn && d == 1 && c ~ /^[[:space:]]*dynamic[[:space:]]+"?rule"?/) { ndyn++; in_dyn = 1; dyn_has = 0; dyn_d = d }
        else if (!in_dyn && d == 1 && b ~ /^[[:space:]]*rule[[:space:]]*\{/) inb++
      }
      depth = d + count_of(b, "{") - count_of(b, "}")
      if (in_dyn && depth <= dyn_d) in_dyn = 0
      if (depth <= 0) {
        if (blk == "hcloud_server") printf "SERVER\t%s\t%d\t%s\t%d\t%d\n", lab, hascount, fwids, gated, hasfe
        else if (blk == "hcloud_firewall") printf "FIREWALL\t%s\t%d\t%d\t%d\t%d\t%d\n", lab, inb, ndyn, ndynadmin, nfe, napply
        else if (blk == "hcloud_firewall_attachment") printf "ATTACH\t%s\t%s\t%s\n", lab, fwid, srvs
        blk = ""
      }
    }
    END { if (blk != "") print "UNSUPPORTED\tunterminated-resource" }'
}

field() { awk -F'\t' -v k="$1" -v l="$2" -v n="$3" '$1 == k && $2 == l { print $n; exit }'; } # kind label col <records

analyze() { # dir -> prints FINDING lines; empty output = clean
  local dir="$1" rec nserv nfw srv fw kind has fwids inline viaatt bound b attach_actual="" a g gl lab t
  local inb ndyn ndyna nfe
  rec="$(records "$dir")"
  for g in "$dir"/*.tf.json "$dir"/*.tofu "$dir"/*.tofu.json; do
    if [ -e "$g" ]; then echo "FINDING unread-file directory"; break; fi
  done
  for g in "$dir"/override.tf "$dir"/*_override.tf; do
    if [ -e "$g" ]; then echo "FINDING override-file directory"; break; fi
  done
  for g in "$dir"/*.tfvars "$dir"/*.auto.tfvars "$dir"/*.tfvars.json "$dir"/*.auto.tfvars.json; do
    [ -f "$g" ] || continue
    gl="$(grep -E 'enable_grok_dogfood' "$g" | grep -vE 'false')"
    if [ -n "$gl" ]; then echo "FINDING excluded-enabled hcloud_server.grok_dogfood"; fi
  done
  # the default-off host stays default-off in the declaration itself: variable default false, local passes it through unchanged
  if ! cat "$dir"/*.tf 2>/dev/null | awk '/^variable "enable_grok_dogfood"/ { v = 1 } v && /^}/ { v = 0 } v && /^[[:space:]]*default[[:space:]]*=[[:space:]]*false[[:space:]]*(#.*)?$/ { ok = 1 } END { exit ok ? 0 : 1 }'; then
    echo "FINDING excluded-enabled hcloud_server.grok_dogfood"
  fi
  gl="$(cat "$dir"/*.tf 2>/dev/null | grep -E '^[[:space:]]*grok_dogfood_enabled[[:space:]]*=' | grep -vE '=[[:space:]]*var\.enable_grok_dogfood[[:space:]]*(#.*)?$')"
  if [ -n "$gl" ]; then
    echo "FINDING excluded-enabled hcloud_server.grok_dogfood"
  fi
  if [ -d "$dir/modules" ] && grep -rqE '^[[:space:]]*resource[[:space:]]+"?hcloud_' --include='*.tf' "$dir/modules"; then
    echo "FINDING module-hcloud-resource directory"
  fi
  grep '^UNSUPPORTED' <<<"$rec" | sort -u | while IFS=$'\t' read -r _ t; do echo "FINDING unsupported-syntax $t"; done
  grep '^MODSRC' <<<"$rec" | while IFS=$'\t' read -r _ lab t; do
    case "$t" in ./modules/*) : ;; *) echo "FINDING module-source module.${lab}" ;; esac
  done
  grep '^MODULE' <<<"$rec" | while IFS=$'\t' read -r _ lab; do
    case " $MODULE_ALLOW " in *" $lab "*) : ;; *) echo "FINDING unlisted-module module.${lab}" ;; esac
  done
  nserv="$(grep -c '^SERVER' <<<"$rec")"; nfw="$(grep -c '^FIREWALL' <<<"$rec")"
  [ "$nserv" -gt 0 ] || { echo "FINDING no-servers directory"; return; }
  [ "$nfw" -gt 0 ] || echo "FINDING no-firewalls directory"
  awk -F'\t' '$1 == "SERVER" || $1 == "FIREWALL" || $1 == "ATTACH" { c[$1 "\t" $2]++ } END { for (k in c) if (c[k] > 1) print k }' <<<"$rec" | sort \
    | while IFS=$'\t' read -r kind lab; do
        case "$kind" in SERVER) t=hcloud_server ;; FIREWALL) t=hcloud_firewall ;; *) t=hcloud_firewall_attachment ;; esac
        echo "FINDING duplicate-resource ${t}.${lab}"
      done
  while IFS=$'\t' read -r _ srv _; do
    grep -q "^${srv}|" <<<"$MAP" || echo "FINDING unmapped-server hcloud_server.${srv}"
  done < <(grep '^SERVER' <<<"$rec")
  while IFS=$'\t' read -r _ lab _; do
    awk -F'|' -v l="$lab" '$2 == l { f = 1 } END { exit f ? 0 : 1 }' <<<"$MAP" || echo "FINDING unmapped-firewall hcloud_firewall.${lab}"
  done < <(grep '^FIREWALL' <<<"$rec")
  awk -F'\t' '$1 == "FIREWALL" && $7 + 0 > 0 { print $2 }' <<<"$rec" | while read -r lab; do
    echo "FINDING firewall-apply-to hcloud_firewall.${lab}"
  done
  while IFS='|' read -r srv fw kind; do
    has="$(grep -c "^SERVER"$'\t'"${srv}"$'\t' <<<"$rec")"
    if [ "$kind" = excluded ]; then
      if [ "$has" -gt 0 ]; then
        [ "$(field SERVER "$srv" 5 <<<"$rec")" = 1 ] || echo "FINDING excluded-not-gated hcloud_server.${srv}"
        inb="$(field FIREWALL "$fw" 3 <<<"$rec")"
        [ "${inb:-0}" -eq 0 ] || echo "FINDING rule-block hcloud_firewall.${fw}"
      fi
      continue
    fi
    if [ "$has" -eq 0 ]; then
      if [ "$kind" = control ]; then echo "FINDING control-server-missing hcloud_server.${srv}"; else echo "FINDING server-missing hcloud_server.${srv}"; fi
      continue
    fi
    if [ "$(grep -c "^FIREWALL"$'\t'"${fw}"$'\t' <<<"$rec")" -eq 0 ]; then echo "FINDING firewall-missing hcloud_firewall.${fw}"; continue; fi
    # binding: inline (firewall_ids) and/or an attachment naming both this firewall and this server
    fwids="$(field SERVER "$srv" 4 <<<"$rec")"
    inline=0; viaatt=0
    grep -qE "(^|,)${fw}(,|$)" <<<"$fwids" && inline=1
    awk -F'\t' -v f="$fw" -v s="$srv" '$1 == "ATTACH" && $3 == f { n = split($4, a, ","); for (i = 1; i <= n; i++) if (a[i] == s) ok = 1 } END { exit ok ? 0 : 1 }' <<<"$rec" && viaatt=1
    if [ "$inline" -eq 0 ] && [ "$viaatt" -eq 0 ]; then echo "FINDING unbound hcloud_server.${srv}"; fi
    if [ "$viaatt" -eq 1 ] && [ "$kind" != control ]; then attach_actual="$attach_actual $srv"; fi
    # exactly one firewall: every firewall bound to this server, inline or by any attachment, must be the mapped one
    bound="$(awk -F'\t' -v s="$srv" '
      $1 == "SERVER" && $2 == s { n = split($4, x, ","); for (i = 1; i <= n; i++) if (x[i] != "") print x[i] }
      $1 == "ATTACH" { n = split($4, y, ","); for (i = 1; i <= n; i++) if (y[i] == s) print $3 }' <<<"$rec" | sort -u)"
    while read -r b; do
      [ -z "$b" ] && continue
      if [ "$b" != "$fw" ]; then echo "FINDING extra-firewall hcloud_server.${srv}"; break; fi
    done <<<"$bound"
    if [ "$kind" = plain ] && { [ "$(field SERVER "$srv" 3 <<<"$rec")" = 1 ] || [ "$(field SERVER "$srv" 6 <<<"$rec")" = 1 ]; }; then
      echo "FINDING server-multiplied hcloud_server.${srv}"
    fi
    inb="$(field FIREWALL "$fw" 3 <<<"$rec")"; ndyn="$(field FIREWALL "$fw" 4 <<<"$rec")"
    ndyna="$(field FIREWALL "$fw" 5 <<<"$rec")"; nfe="$(field FIREWALL "$fw" 6 <<<"$rec")"
    if [ "$kind" = control ]; then
      [ "${inb:-0}" -gt 0 ] || echo "FINDING parser-liveness hcloud_firewall.${fw}"
      if [ "${ndyn:-0}" -gt "${ndyna:-0}" ] || [ "${nfe:-0}" -gt 0 ]; then echo "FINDING dynamic-rule hcloud_firewall.${fw}"; fi
    else
      [ "${inb:-0}" -eq 0 ] || echo "FINDING rule-block hcloud_firewall.${fw}"
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
  [ "${2:-}" = count ] && printf '  count = local.grok_dogfood_enabled ? 1 : 0\n'
  [ -n "${3:-}" ] && printf '  firewall_ids = [hcloud_firewall.%s.id]\n' "$3"
  printf '}\n\n'
}
tf_fw_plain() { # label  (deny-all: no rule block at all)
  printf 'resource "hcloud_firewall" "%s" {\n  labels = {}\n}\n\n' "$1"
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
    printf 'module "git_data_userdata" {\n  source = "./modules/git-data-userdata"\n}\n\n'
    printf 'variable "enable_grok_dogfood" {\n  type    = bool\n  default = false\n}\n\nlocals {\n  grok_dogfood_enabled = var.enable_grok_dogfood\n}\n\n'
    tf_server grok_dogfood count; tf_fw_plain grok_dogfood
  } > "$1/main.tf"
}
clone() { rm -rf "${D:?}/$2"; cp -r "$D/$1" "$D/$2"; }
edit() { # file sed-args... ; a fixture edit that changes nothing is a broken fixture, not a pass
  local f="$1" before; shift
  before="$(cksum < "$f")"
  sed -i "$@" "$f"
  [ "$(cksum < "$f")" != "$before" ] || { printf '[FATAL] fixture edit changed nothing in %s: %s\n' "$f" "$*" >&2; exit 1; }
}

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
  clone ctl out_only; edit "$D/out_only/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  rule {\n    direction = "out"\n    protocol = "udp"\n  }'
  expect_finding "even an outbound rule on a non-web firewall is a review event (no rule block at all)" out_only rule-block hcloud_firewall.git_data
}
case_inbound() {
  CASES=$((CASES + 1))
  clone ctl inb; edit "$D/inb/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n    port = "22"\n  }'
  expect_finding "inbound rule on a non-web firewall" inb rule-block hcloud_firewall.git_data
}
case_second_member() {
  CASES=$((CASES + 1))
  clone ctl sm; edit "$D/sm/main.tf" '/resource "hcloud_firewall" "inngest" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n  }'
  expect_finding "a violation in a LATER non-web firewall after compliant ones" sm rule-block hcloud_firewall.inngest
  clone ctl sm2; edit "$D/sm2/main.tf" '/resource "hcloud_firewall" "registry" {/a\  rule {\n    direction = "in"\n    protocol = "tcp"\n  }'
  expect_finding "a violation in an EARLIER member while later ones are compliant" sm2 rule-block hcloud_firewall.registry
}
case_empty() {
  CASES=$((CASES + 1))
  mkdir -p "$D/empty"; : > "$D/empty/main.tf"
  expect_finding "a directory with no servers fails, never prints clean" empty no-servers directory
  clone ctl nofw; edit "$D/nofw/main.tf" '/^resource "hcloud_firewall" "git_data"/,/^}/d'
  expect_finding "a firewall resource missing for a mapped server" nofw firewall-missing hcloud_firewall.git_data
  mkdir -p "$D/onlysrv"; { tf_server web; tf_server git_data; } > "$D/onlysrv/main.tf"
  expect_finding "servers with zero firewall resources" onlysrv no-firewalls directory
  clone ctl nosrv; edit "$D/nosrv/main.tf" '/^resource "hcloud_server" "inngest"/,/^}/d'
  expect_finding "a mapped plain server that disappears is a finding, not a silent skip" nosrv server-missing hcloud_server.inngest
  clone ctl noweb; edit "$D/noweb/main.tf" '/^resource "hcloud_server" "web"/,/^}/d'
  expect_finding "the control server disappearing is a finding" noweb control-server-missing hcloud_server.web
}
case_liveness() {
  CASES=$((CASES + 1))
  clone ctl live; edit "$D/live/main.tf" '/^resource "hcloud_firewall" "web"/,/^}/c\resource "hcloud_firewall" "web" {\n}'
  expect_finding "the control (web) firewall with no rules fails: a parser that reads nothing cannot pass" live parser-liveness hcloud_firewall.web
  clone ctl webdyn; edit "$D/webdyn/main.tf" '/^resource "hcloud_firewall" "web" {/a\  dynamic "rule" {\n    for_each = var.other_ips\n    content {\n      direction = "in"\n    }\n  }'
  expect_finding "a non-admin dynamic rule on the web firewall" webdyn dynamic-rule hcloud_firewall.web
}
case_unmapped() {
  CASES=$((CASES + 1))
  clone ctl unm; tf_server brand_new >> "$D/unm/main.tf"
  expect_finding "a server that is not in the mapping (ADDS an instance the guard has never seen)" unm unmapped-server hcloud_server.brand_new
  clone ctl unm2; tf_server brand_new > "$D/unm2/aaa-first.tf"
  expect_finding "an unmapped server in a different file that sorts first" unm2 unmapped-server hcloud_server.brand_new
  clone ctl unm3; tf_server inngest_old > "$D/unm3/zz.tf"
  expect_finding "a label that merely contains a mapped label is still unmapped" unm3 unmapped-server hcloud_server.inngest_old
}
case_binding() {
  CASES=$((CASES + 1))
  clone ctl nb; edit "$D/nb/main.tf" '/^resource "hcloud_firewall_attachment" "git_data"/,/^}/d'
  expect_finding "a mapped server loses its attachment" nb unbound hcloud_server.git_data
  clone ctl nb2; edit "$D/nb2/main.tf" '/firewall_ids/d'
  expect_finding "a mapped server loses its inline firewall_ids line" nb2 unbound hcloud_server.inngest
  clone ctl nb3; edit "$D/nb3/main.tf" 's/server_ids  = \[hcloud_server.registry.id\]/server_ids  = [hcloud_server.git_data.id]/'
  expect_finding "an attachment that names the wrong server leaves the right one unbound" nb3 unbound hcloud_server.registry
}
case_ratchet() {
  CASES=$((CASES + 1))
  clone ctl rt; edit "$D/rt/main.tf" '/firewall_ids/d'; tf_attach inngest inngest 'hcloud_server.inngest.id' >> "$D/rt/main.tf"
  expect_finding "a server newly attachment-bound that is not in the allow-list" rt attachment-not-allowed hcloud_server.inngest
  clone ctl rt2; edit "$D/rt2/main.tf" '/^resource "hcloud_firewall_attachment" "registry"/,/^}/d'
  edit "$D/rt2/main.tf" '/^resource "hcloud_server" "registry" {/a\  firewall_ids = [hcloud_firewall.registry.id]'
  expect_finding "a server moved to inline binding while its allow-list entry remains (the list must shrink)" rt2 allowlist-stale hcloud_server.registry
}
case_dynamic() {
  CASES=$((CASES + 1))
  clone ctl dy; edit "$D/dy/main.tf" '/resource "hcloud_firewall" "registry" {/a\  dynamic "rule" {\n    for_each = var.admin_ips\n    content {\n      direction = "in"\n    }\n  }'
  expect_finding "a dynamic rule block on a non-web firewall is never silent" dy dynamic-rule hcloud_firewall.registry
  clone ctl dy2; edit "$D/dy2/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  for_each = toset(["a"])'
  expect_finding "for_each on a non-web firewall is never silent" dy2 dynamic-rule hcloud_firewall.git_data
  clone ctl dy3; edit "$D/dy3/main.tf" '/resource "hcloud_firewall" "registry" {/a\  dynamic rule {\n    for_each = var.admin_ips\n  }'
  expect_finding "a dynamic rule with a bare label is read like the quoted one" dy3 dynamic-rule hcloud_firewall.registry
}
case_ignored_constructs() {
  CASES=$((CASES + 1))
  clone ctl cm; edit "$D/cm/main.tf" '/resource "hcloud_firewall" "git_data" {/a\# rule {\n# direction = "in"\n# unbalanced {'
  expect_clean "a rule that exists only inside comment lines is ignored" cm
  clone ctl cm2; edit "$D/cm2/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  labels = { note = "x" } # rule { direction = in {'
  expect_clean "a rule mentioned in a trailing comment is ignored" cm2
  clone ctl cm3; edit "$D/cm3/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  note = "a" // a "quoted" { word\n  other = "b" # it is "odd {'
  expect_clean "trailing // and # comments that carry quotes and braces are cut, not parsed" cm3
  clone ctl cm4; printf 'resource "hcloud_ssh_key" "k" {\n  description = "a \\" { b"\n}\n' > "$D/cm4/zz.tf"
  expect_clean "an escaped quote inside a string does not end the string early" cm4
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
    printf 'variable "enable_grok_dogfood" {\n  default = false\n}\nlocals {\n  grok_dogfood_enabled = var.enable_grok_dogfood\n}\n'
  } > "$D/nc/other-name.tf"
  expect_clean "different labels order, attribute order, odd indent and multiline lists still pass (must-PASS non-canonical input)" nc
}
case_excluded() {
  CASES=$((CASES + 1))
  clone ctl ex; edit "$D/ex/main.tf" '/^resource "hcloud_server" "grok_dogfood"/,/^}/c\resource "hcloud_server" "grok_dogfood" {\n}'
  expect_finding "the excluded server must stay count-gated (default-off)" ex excluded-not-gated hcloud_server.grok_dogfood
  clone ctl ex2; edit "$D/ex2/main.tf" 's/count = local.grok_dogfood_enabled ? 1 : 0/count = 1/'
  expect_finding "a count of one is a presence of the field, not a default-off gate" ex2 excluded-not-gated hcloud_server.grok_dogfood
  clone ctl ex3; edit "$D/ex3/main.tf" '/resource "hcloud_firewall" "grok_dogfood" {/a\  rule {\n    direction = "in"\n  }'
  expect_finding "a static inbound rule on the excluded host firewall" ex3 rule-block hcloud_firewall.grok_dogfood
}
case_files() {
  CASES=$((CASES + 1))
  clone ctl fj; printf '{}\n' > "$D/fj/ghost.tf.json"
  expect_finding "a .tf.json file is refused, not skipped" fj unread-file directory
  clone ctl ov; printf '# empty\n' > "$D/ov/override.tf"
  expect_finding "an override file is refused" ov override-file directory
  clone ctl tv; printf 'enable_grok_dogfood = true\n' > "$D/tv/prod.tfvars"
  expect_finding "a tfvars file that enables the default-off host" tv excluded-enabled hcloud_server.grok_dogfood
  clone ctl md; printf 'module "extra" {\n  source = "./m"\n}\n' >> "$D/md/main.tf"
  expect_finding "a module that is not listed is refused" md unlisted-module module.extra
  clone ctl ms2; edit "$D/ms2/main.tf" 's|source = "./modules/git-data-userdata"|source = "git::https://example.invalid/m.git"|'
  expect_finding "a listed module whose source leaves modules/ is refused" ms2 module-source module.git_data_userdata
  clone ctl tv2; printf '{"enable_grok_dogfood": true}\n' > "$D/tv2/prod.auto.tfvars.json"
  expect_finding "a tfvars.json that enables the default-off host" tv2 excluded-enabled hcloud_server.grok_dogfood
  clone ctl tv3; printf 'enable_grok_dogfood = "true"\n' > "$D/tv3/prod.tfvars"
  expect_finding "a quoted true in tfvars is still an enable" tv3 excluded-enabled hcloud_server.grok_dogfood
  clone ctl vd; edit "$D/vd/main.tf" 's/  default = false/  default = true/'
  expect_finding "the variable default flipped to true" vd excluded-enabled hcloud_server.grok_dogfood
  clone ctl lv; edit "$D/lv/main.tf" 's/grok_dogfood_enabled = var.enable_grok_dogfood/grok_dogfood_enabled = true/'
  expect_finding "the local that gates the host flipped to a constant" lv excluded-enabled hcloud_server.grok_dogfood
  clone ctl mh; mkdir -p "$D/mh/modules/m"; printf 'resource "hcloud_server" "q" {\n}\n' > "$D/mh/modules/m/main.tf"
  expect_finding "an hcloud resource inside modules/ is refused" mh module-hcloud-resource directory
  clone ctl dup; tf_fw_plain inngest > "$D/dup/zz.tf"
  expect_finding "a duplicate resource label (an override in all but name)" dup duplicate-resource hcloud_firewall.inngest
  clone ctl dup2; tf_server inngest > "$D/dup2/zz.tf"
  expect_finding "a duplicate server label" dup2 duplicate-resource hcloud_server.inngest
  clone ctl dup3; tf_attach git_data git_data 'hcloud_server.git_data.id' > "$D/dup3/zz.tf"
  expect_finding "a duplicate attachment label" dup3 duplicate-resource hcloud_firewall_attachment.git_data
  clone ctl tofu; printf '# empty\n' > "$D/tofu/ghost.tofu"
  expect_finding "a .tofu file is refused" tofu unread-file directory
  clone ctl ov2; printf '# empty\n' > "$D/ov2/zz_override.tf"
  expect_finding "a *_override.tf file is refused" ov2 override-file directory
}
case_syntax() {
  CASES=$((CASES + 1))
  clone ctl sq; edit "$D/sq/main.tf" '/^resource "hcloud_server" "inngest" {/a\  name = "oops'
  expect_finding "a stray quote inside an hcloud resource is refused" sq unsupported-syntax unbalanced-quote
  clone ctl ut2; printf 'resource "hcloud_ssh_key" "k" {\n  name = "x"\n' > "$D/ut2/aaa.tf"
  expect_finding "a file that ends inside a resource is found even when it is not the last file" ut2 unsupported-syntax unterminated-resource
  clone ctl ni; edit "$D/ni/main.tf" '/^resource "hcloud_firewall" "git_data" {/a\  note = "${var.a ? "}" : "x"}"'
  expect_finding "a nested quote inside an interpolation is refused in an hcloud block (the quote pairing would drift)" ni unsupported-syntax nested-interpolation
  clone ctl bd; { printf 'resource "aws_x" "y" {\n  note = "${var.a ? "{" : "x"}"\n}\n'; tf_server brand_new; } > "$D/bd/zz.tf"
  expect_finding "a drifted brace count that swallows the next resource header is found" bd unsupported-syntax brace-desync
  clone ctl bc; printf '/* a block comment */\n' > "$D/bc/zz.tf"
  expect_finding "a block comment is refused (a commented binding must not read as live)" bc unsupported-syntax block-comment
  clone ctl ol; printf 'resource "hcloud_ssh_key" "k" { name = "x" }\n' > "$D/ol/zz.tf"
  expect_finding "a one-line resource body is refused, never swallowed into the next resource" ol unsupported-syntax resource-form
  clone ctl hd; edit "$D/hd/main.tf" '/^resource "hcloud_server" "inngest" {/a\  user_data = <<-EOT'
  expect_finding "a heredoc inside an hcloud resource is refused" hd unsupported-syntax heredoc
  clone ctl ut; printf 'resource "hcloud_ssh_key" "k" {\n  name = "x"\n' > "$D/ut/zz.tf"
  expect_finding "a file that ends inside a resource" ut unsupported-syntax unterminated-resource
  clone ctl sb; edit "$D/sb/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  name = "x{"\n  rule {\n    direction = "in"\n  }\n  description = "}"'
  expect_finding "braces inside string literals do not hide a rule block" sb rule-block hcloud_firewall.git_data
  clone ctl lc; edit "$D/lc/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [] // hcloud_firewall.inngest.id|'
  expect_finding "a binding that survives only in a // comment is not a binding" lc unbound hcloud_server.inngest
  clone ctl vr; edit "$D/vr/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [var.hcloud_firewall_inngest]|'
  expect_finding "a variable whose name contains the token is not a binding" vr unbound hcloud_server.inngest
  clone ctl hy; printf 'resource "hcloud_server" "ghost-x" {\n}\n' > "$D/hy/zz.tf"
  expect_finding "a hyphenated resource label is parsed, not invisible" hy unmapped-server hcloud_server.ghost-x
  clone ctl ind; printf '  resource "hcloud_server" "ghostindent" {\n  }\n' > "$D/ind/zz.tf"
  expect_finding "an indented resource header is parsed" ind unmapped-server hcloud_server.ghostindent
  clone ctl bare; printf 'resource hcloud_server ghostbare {\n}\n' > "$D/bare/zz.tf"
  expect_finding "a bare-identifier resource header is parsed" bare unmapped-server hcloud_server.ghostbare
}
case_exposure_paths() {
  CASES=$((CASES + 1))
  clone ctl uf; { tf_fw_plain extra; tf_attach extra extra 'hcloud_server.inngest.id'; } > "$D/uf/zz.tf"
  expect_finding "an unmapped firewall" uf unmapped-firewall hcloud_firewall.extra
  clone ctl wf; tf_attach web2 web 'hcloud_server.inngest.id' > "$D/wf/zz.tf"
  expect_finding "the web firewall attached to a non-web server" wf extra-firewall hcloud_server.inngest
  clone ctl si; edit "$D/si/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [hcloud_firewall.inngest.id, hcloud_firewall.web.id]|'
  expect_finding "a second firewall id inline" si extra-firewall hcloud_server.inngest
  clone ctl ap; edit "$D/ap/main.tf" '/resource "hcloud_firewall" "git_data" {/a\  apply_to {\n    label_selector = "x"\n  }'
  expect_finding "apply_to on a firewall" ap firewall-apply-to hcloud_firewall.git_data
  clone ctl mc; edit "$D/mc/main.tf" '/^resource "hcloud_server" "inngest" {/a\  count = 2'
  expect_finding "a plain server multiplied by count" mc server-multiplied hcloud_server.inngest
  clone ctl mf; edit "$D/mf/main.tf" '/^resource "hcloud_server" "registry" {/a\  for_each = toset(["a"])'
  expect_finding "a plain server multiplied by for_each" mf server-multiplied hcloud_server.registry
}
case_binding_lists() {
  CASES=$((CASES + 1))
  clone ctl wfw; edit "$D/wfw/main.tf" '/^resource "hcloud_firewall_attachment" "registry"/,/^}/s/hcloud_firewall.registry.id/hcloud_firewall.git_data.id/'
  expect_finding "an attachment naming the wrong firewall leaves the server unbound" wfw unbound hcloud_server.registry
  clone ctl xt; edit "$D/xt/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [x_hcloud_firewall.inngest.id]|'
  expect_finding "an identifier that merely ends in the token is not a binding" xt unbound hcloud_server.inngest
  clone ctl wl; edit "$D/wl/main.tf" '/^resource "hcloud_firewall_attachment" "registry"/,/^}/s/hcloud_firewall.registry.id/hcloud_firewall.registry_old.id/'
  expect_finding "an attachment whose firewall label merely starts with the mapped one" wl unbound hcloud_server.registry
  clone ctl sub; edit "$D/sub/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [hcloud_firewall.inngest_old.id]|'
  expect_finding "a firewall label that merely starts with the mapped one is not the mapped firewall" sub unbound hcloud_server.inngest
  clone ctl ml; edit "$D/ml/main.tf" 's|firewall_ids = \[hcloud_firewall.inngest.id\]|firewall_ids = [hcloud_firewall.web.id, hcloud_firewall.inngest.id]|'
  expect_finding "a multi-element firewall_ids list is split, so an extra id is seen wherever it sits" ml extra-firewall hcloud_server.inngest
  clone ctl ms; edit "$D/ms/main.tf" '/^resource "hcloud_firewall_attachment" "registry"/,/^}/s/server_ids  = \[hcloud_server.registry.id\]/server_ids  = [hcloud_server.registry.id, hcloud_server.git_data.id]/'
  expect_finding "a multi-element server_ids list is split, so the second server is seen bound to a second firewall" ms extra-firewall hcloud_server.git_data
}
case_real_tree() {
  CASES=$((CASES + 1))
  local out rec
  rec="$(records "$REAL_TF")"
  [ "$(grep -c '^SERVER' <<<"$rec")" -ge 4 ] && ok "real tree: the parser read at least four server resources (liveness)" || bad "real tree: fewer than four servers parsed"
  [ "$(field FIREWALL web 3 <<<"$rec")" -gt 0 ] 2>/dev/null && ok "real tree: the control firewall parsed with inbound rules" || bad "real tree: the control firewall parsed with no inbound rule"
  out="$(analyze "$REAL_TF")"
  [ -z "$out" ] && ok "real tree: the declared-design invariant holds (declared: non-web firewalls deny inbound, every mapped server is bound to exactly its firewall, nothing unmapped)" \
    || bad "real tree: declared-design invariant violated: $(tr '\n' ';' <<<"$out") (a new server needs a MAP row: see the suite header)"
}

[ -d "$REAL_TF" ] || { printf '[FATAL] real Terraform directory missing\n' >&2; exit 1; }
case_baseline; case_inbound; case_second_member; case_empty; case_liveness; case_unmapped
case_binding; case_ratchet; case_dynamic; case_ignored_constructs; case_noncanonical
case_excluded; case_files; case_syntax; case_exposure_paths; case_binding_lists; case_real_tree

# ---- anti-vacuity floors (reported with printf + exit, not through the helpers) ------------------
EXPECTED_CASES=17
if [ "$CASES" -lt "$EXPECTED_CASES" ]; then
  printf '[FATAL] case-count floor: ran %s cases, want >= %s (a case was deleted)\n' "$CASES" "$EXPECTED_CASES" >&2; exit 1
fi
MIN_ASSERTIONS=76
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: %s passed, want >= %s (an assertion was deleted)\n' "$pass" "$MIN_ASSERTIONS" >&2; exit 1
fi

printf '\n%s passed, %s failed (%s cases)\n' "$pass" "$fail" "$CASES"
if [ "$fail" -gt 0 ] || [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILURES:\n'; printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
exit 0
