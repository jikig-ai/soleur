#!/usr/bin/env bash
# cron-egress-metadata-endpoint.test.sh — a container cannot reach the Hetzner metadata endpoint (#6931).
#
# WHY. A fresh web host's Doppler read token for prd_workspaces_luks (and the Sentry DSN, the webhook
# secret ...) travel in cloud-init user_data, which the host can read back from the link-local metadata
# endpoint 169.254.169.254. ADR-263 accepts that residual ONLY because containers sit behind the
# default-drop egress firewall and no allowlist entry covers the link-local range, so a compromised
# container cannot fetch user_data. This suite is the regression test that bounds the residual at the
# level of the two allowlist FILES: if anyone adds a link-local address, a covering CIDR or a metadata
# hostname to them, the residual silently widens from "root-equivalent host users" to "any container".
#
# WHAT IT PROVES, AND WHAT IT DOES NOT. It reads the allowlist TEXT only (cron-egress-allowlist.txt and
# cron-egress-allowlist-cidr.txt). Hostnames are NEVER resolved here: a listed vendor name whose A record
# later points into 169.254.0.0/16 is not seen (cron-egress-resolve.sh has no link-local filter; that and
# a ruleset-level test are deferred), and the installed nft ruleset is not exercised.
#
# Every allowlist entry is evaluated, not grepped for a token: CIDRs are checked for COVERAGE of the
# endpoint with ipaddress (so 169.254.0.0/16, 169.0.0.0/8 and 0.0.0.0/0 all trip it, not only the
# spelling the author thought of), IPv6 entries are checked for coverage of the v4-mapped form
# (::ffff:169.254.169.254), and bare/dotted entries are normalised the way inet_aton reads them
# (decimal, octal `0251.0376.0251.0376`, hex `0xa9.0xfe.0xa9.0xfe`, single integers) before comparison.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOW_HOSTS="${CEM_ALLOW_HOSTS:-$DIR/cron-egress-allowlist.txt}"
ALLOW_CIDR="${CEM_ALLOW_CIDR:-$DIR/cron-egress-allowlist-cidr.txt}"

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '[FAIL] %s\n' "$1" >&2; }

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }
for f in "$ALLOW_HOSTS" "$ALLOW_CIDR"; do [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }; done

# Prints one offending entry per line; prints "COUNT <n>" first so a vacuous parse is detectable.
verdict="$(python3 - "$ALLOW_HOSTS" "$ALLOW_CIDR" <<'PY'
import ipaddress, re, sys
META = ipaddress.ip_address("169.254.169.254")
META6 = ipaddress.ip_address("::ffff:169.254.169.254")
LL4 = ipaddress.ip_network("169.254.0.0/16")
LL6 = ipaddress.ip_network("::ffff:169.254.0.0/112")
META_NAMES = {"metadata.hetzner.cloud", "metadata", "metadata.google.internal", "instance-data"}

def aton(text):
    """inet_aton: 1-4 dot-separated parts, each decimal / 0octal / 0xhex; the last part fills the rest."""
    parts = text.split(".")
    if not 1 <= len(parts) <= 4:
        return None
    vals = []
    for p in parts:
        if re.fullmatch(r"0[xX][0-9a-fA-F]+", p):
            vals.append(int(p, 16))
        elif re.fullmatch(r"0[0-7]*", p):
            vals.append(int(p, 8))
        elif re.fullmatch(r"[1-9][0-9]*", p):
            vals.append(int(p, 10))
        else:
            return None
    *head, last = vals
    if any(v > 255 for v in head) or last >= 256 ** (4 - len(head)):
        return None
    n = 0
    for v in head:
        n = (n << 8) | v
    return (n << (8 * (4 - len(head)))) | last

def covers_link_local(net):
    if net.version == 4:
        return META in net or net.overlaps(LL4)
    return META6 in net or net.overlaps(LL6)

bad, n = [], 0
for path in sys.argv[1:]:
    base = path.rsplit("/", 1)[-1]
    for raw in open(path, errors="replace"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        n += 1
        try:
            if covers_link_local(ipaddress.ip_network(line, strict=False)):
                bad.append("%s: %s covers the link-local range" % (base, line))
            continue
        except ValueError:
            pass
        host, _, plen = line.lower().rstrip(".").partition("/")
        if host in META_NAMES or host.startswith("169.254.") or re.fullmatch(r"(?:0x[0-9a-f]+|\d+)", host):
            bad.append("%s: %s names the metadata endpoint" % (base, line))
            continue
        v = aton(host)
        if v is not None:
            prefix = int(plen) if plen.isdigit() and int(plen) <= 32 else 32
            try:
                if covers_link_local(ipaddress.ip_network((v, prefix), strict=False)):
                    bad.append("%s: %s is another spelling of the link-local range" % (base, line))
            except ValueError:
                pass
print("COUNT", n)
for b in bad:
    print(b)
PY
)"
count="$(printf '%s\n' "$verdict" | sed -n 's/^COUNT //p')"
offenders="$(printf '%s\n' "$verdict" | grep -v '^COUNT ' || true)"

# The parse must have SEEN the lists, or "no offenders" proves nothing.
if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge 10 ]; then ok "parsed $count allowlist entries (non-vacuous)"; else no "parsed only '${count:-?}' allowlist entries; the check is vacuous"; fi
if [ -z "$offenders" ]; then ok "no allowlist entry covers 169.254.169.254 or names the metadata endpoint"; else no "metadata endpoint reachable from containers: $offenders"; fi

# Mutation rows: each plants one spelling in a scratch copy and the evaluator must flag it.
SCR="$(mktemp -d)"  # lint-trap-ownership: ok — removed by the EXIT trap on the next line
trap 'rm -rf "$SCR"' EXIT
case "$SCR" in /*) : ;; *) printf '[FATAL] scratch dir not absolute\n' >&2; exit 2 ;; esac
PLANTED=0
plant() { # <label> <host-line|-> <cidr-line|-> <red|green>
  local rc=0
  PLANTED=$((PLANTED + 1))
  cp "$ALLOW_HOSTS" "$SCR/h.txt"; cp "$ALLOW_CIDR" "$SCR/c.txt"
  [ "$2" = - ] || printf '%s\n' "$2" >> "$SCR/h.txt"
  [ "$3" = - ] || printf '%s\n' "$3" >> "$SCR/c.txt"
  CEM_ALLOW_HOSTS="$SCR/h.txt" CEM_ALLOW_CIDR="$SCR/c.txt" CEM_NO_MUTATE=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || rc=$?
  if [ "$4" = red ]; then
    if [ "$rc" -eq 1 ]; then ok "mutation caught: $1"; else no "mutation SURVIVED or broke the instrument (rc=$rc): $1"; fi
  else
    if [ "$rc" -eq 0 ]; then ok "harmless variant stays green: $1"; else no "harmless variant went red (rc=$rc): $1"; fi
  fi
}
if [ -z "${CEM_NO_MUTATE:-}" ]; then
  plant "the exact metadata address as a CIDR host route" - "169.254.169.254/32" red
  plant "the link-local /16" - "169.254.0.0/16" red
  plant "a covering /8" - "169.0.0.0/8" red
  plant "allow-everything" - "0.0.0.0/0" red
  plant "the metadata address as a bare entry in the host list" "169.254.169.254" - red
  plant "a metadata hostname" "metadata.hetzner.cloud" - red
  plant "an unrelated public address" - "203.0.113.7/32" green
  plant "the IPv4-mapped IPv6 spelling as a /128 route" - "::ffff:169.254.169.254/128" red
  plant "the IPv4-mapped IPv6 spelling as a bare host-list entry" "::ffff:169.254.169.254" - red
  plant "the IPv4-mapped IPv6 /96 (covers every v4 address)" - "::ffff:0:0/96" red
  plant "octal dotted spelling, bare" "0251.0376.0251.0376" - red
  plant "octal dotted spelling as a /32" - "0251.0376.0251.0376/32" red
  plant "hex dotted spelling, bare" "0xa9.0xfe.0xa9.0xfe" - red
  plant "hex dotted spelling as a /32" - "0xa9.0xfe.0xa9.0xfe/32" red
  plant "single-integer decimal spelling" "2852039166" - red
  plant "an unrelated public IPv6 range" - "2001:db8::/32" green
  plant "an unrelated octal dotted address (203.0.113.7)" "0313.0.0161.07" - green
  # Anti-vacuity: deleting plant rows leaves a lower count, which must red (the suite otherwise passes
  # with zero mutation rows).
  if [ "$PLANTED" -ne 17 ]; then no "$PLANTED plant rows ran, expected exactly 17: rows were deleted or added without moving the number"; else ok "all $PLANTED plant rows ran (exactly 17)"; fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
