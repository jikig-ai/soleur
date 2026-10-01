#!/usr/bin/env bash
# cron-egress-metadata-endpoint.test.sh — a container cannot reach the Hetzner metadata endpoint (#6931).
#
# WHY. A fresh web host's Doppler read token for prd_workspaces_luks (and the Sentry DSN, the webhook
# secret ...) travel in cloud-init user_data, which the host can read back from the link-local metadata
# endpoint 169.254.169.254. ADR-263 accepts that residual ONLY because containers sit behind the
# default-drop egress firewall and no allowlist entry covers the link-local range, so a compromised
# container cannot fetch user_data. This suite is the regression test that bounds the residual: if
# anyone ever adds a link-local address, a covering CIDR, or a hostname that resolves there to the
# allowlists, the residual silently widens from "root-equivalent host users" to "any container".
#
# Every allowlist entry is evaluated, not grepped for a token: CIDRs are checked for COVERAGE of the
# endpoint with ipaddress (so 169.254.0.0/16, 169.0.0.0/8 and 0.0.0.0/0 all trip it, not only the
# spelling the author thought of), and hostnames are checked against the metadata names.
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
META_NAMES = {"metadata.hetzner.cloud", "metadata", "metadata.google.internal", "instance-data"}
bad, n = [], 0
for path in sys.argv[1:]:
    for raw in open(path, errors="replace"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        n += 1
        try:
            net = ipaddress.ip_network(line, strict=False)
            if META in net or net.overlaps(ipaddress.ip_network("169.254.0.0/16")):
                bad.append("%s: %s covers the link-local range" % (path.rsplit("/", 1)[-1], line))
            continue
        except ValueError:
            pass
        host = line.lower().rstrip(".")
        if host in META_NAMES or host.startswith("169.254.") or re.fullmatch(r"(?:0x[0-9a-f]+|\d+)", host):
            bad.append("%s: %s names the metadata endpoint" % (path.rsplit("/", 1)[-1], line))
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
SCR="$(mktemp -d)"
case "$SCR" in /*) : ;; *) printf '[FATAL] scratch dir not absolute\n' >&2; exit 2 ;; esac
trap 'rm -rf "$SCR"' EXIT
plant() { # <label> <host-line|-> <cidr-line|-> <red|green>
  local rc=0
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
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
