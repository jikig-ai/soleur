#!/usr/bin/env bash
# capture-web-1-host-key.sh <web-1-public-ipv4> [--out <pin-file>]   (#7226, ADR-237 D2)
#
# Captures web-1's ECDSA-P256 SSH host key ONCE, from an operator machine, and writes the
# committed pin file (default apps/web-platform/infra/web-1-ssh-host-key.pub): `#` header lines
# (method, UTC date, SHA256 fingerprint, cross-check result), then exactly one key line. The file
# is then reviewed and committed in a PR; every CI ssh path and every Terraform connection block
# trusts only that key.
#
# RUN IT FROM A VANTAGE OUTSIDE CLOUDFLARE: the egress IP must be in var.admin_ips (Doppler
# prd_terraform ADMIN_IPS) so ssh-keyscan reaches web-1's public :22 directly -- the Cloudflare
# edge is the threat position #7226 names, so capturing through the tunnel would be circular.
# If the egress is not allowlisted, run /soleur:admin-ip-refresh first (it needs its own ack).
# There is no login: ssh-keyscan only reads the host key the server offers.
#
# REFUSES under CI (CI or GITHUB_ACTIONS set): ssh-keyscan in a CI path is TOFU, which is exactly
# what this pin replaces (Guard 1 row 7). Also refuses when:
#   * the keyscan does not return exactly one ecdsa-sha2-nistp256 key (web-1 without an
#     ECDSA-P256 key is a STOP-and-re-plan condition, plan R5 -- never rotate web-1's key in place);
#   * the operator's known_hosts already holds an ECDSA key for this IP that DIFFERS from the
#     scanned one (investigate before pinning anything; see ADR-237 / the runbook's H4 triage);
#   * the scanned key does not pass the shared pin writer (.github/actions/cf-tunnel-ssh-bridge/
#     write-known-hosts.sh), i.e. the same shape check every CI consumer applies. The composed
#     file (header + that one key line) is not re-validated here: the hermetic suite's C3 row runs
#     the writer over the written file.
#
# Env overrides (tests): SSH_KEYSCAN (default ssh-keyscan), KNOWN_HOSTS (default
# ~/.ssh/known_hosts).
#
# Exit: 0 written; 1 refused/failed; 2 usage.
set -euo pipefail

usage() { echo "usage: $0 <web-1-public-ipv4> [--out <pin-file>]" >&2; exit 2; }
# The canonical fixture-dir assertion, byte-equal to plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh compares every tracked copy against it). It refuses an
# empty, relative or `..`-bearing --out before the pin file is written.
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
die() { printf 'capture-web-1-host-key: %s\n' "$*" >&2; exit 1; }

if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  die "refusing to run under CI (CI/GITHUB_ACTIONS is set): ssh-keyscan in CI is trust-on-first-use. Capture from an operator machine whose egress is in ADMIN_IPS."
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRITER="$REPO_ROOT/.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh"
OUT="$REPO_ROOT/apps/web-platform/infra/web-1-ssh-host-key.pub"
IP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [[ -z "$IP" ]] || usage; IP="$1"; shift ;;
  esac
done
[[ -n "$IP" ]] || usage
[[ "$OUT" == /* ]] || OUT="$PWD/$OUT"   # a relative --out is relative to the caller's cwd
IPV4_RE='^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$'
[[ "$IP" =~ $IPV4_RE ]] || die "not an IPv4 address: $IP"
case "$IP" in
  10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
    die "$IP is a private/loopback address; pass web-1's PUBLIC IPv4 (the capture must not traverse the private net or the tunnel)" ;;
esac
[[ -x "$WRITER" || -r "$WRITER" ]] || die "pin writer not found at $WRITER"
command -v ssh-keygen >/dev/null || die "ssh-keygen is required"
KEYSCAN="${SSH_KEYSCAN:-ssh-keyscan}"
command -v "$KEYSCAN" >/dev/null || die "ssh-keyscan is required"
KNOWN="${KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"

WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# ── 1. scan (stderr carries the banner comments; keep it for the operator) ─────────────────
"$KEYSCAN" -T 10 -t ecdsa "$IP" > "$WORK/scan" 2> "$WORK/scan.err" \
  || die "ssh-keyscan failed (exit $?). Is this egress in ADMIN_IPS? $(tr -d '\000-\010\013-\037\177' < "$WORK/scan.err" | tail -3)"
awk '!/^#/ && NF' "$WORK/scan" > "$WORK/lines"
n="$(wc -l < "$WORK/lines" | tr -d ' ')"
[[ "$n" -eq 1 ]] || die "expected exactly one scanned key line, got $n (no answer from $IP:22, or an unexpected response)"
read -r scanned_host key_type key_body extra < "$WORK/lines" || true
[[ -z "${extra:-}" ]] || die "unexpected extra fields in the keyscan line"
[[ "$scanned_host" == "$IP" ]] || die "keyscan answered for '$scanned_host', not $IP"
[[ "$key_type" == "ecdsa-sha2-nistp256" ]] \
  || die "web-1 offered '$key_type', not ecdsa-sha2-nistp256. STOP and re-plan (plan R5): Terraform's Go client negotiates ECDSA-P256, and rotating web-1's key in place is forbidden."
KEY="$key_type $key_body"

# ── 2. validate with the SAME writer every CI consumer uses ───────────────────────────────
printf '%s\n' "$KEY" > "$WORK/candidate.pub"
bash "$WRITER" web-1 "$WORK/candidate.pub" "$WORK/kh" >/dev/null \
  || die "the scanned key does not pass the pin writer's shape check"
FP="$(ssh-keygen -lf "$WORK/candidate.pub" | awk '{ print $2 }')"
[[ "$FP" == SHA256:* ]] || die "could not compute the fingerprint"

# ── 3. cross-check against the operator's own known_hosts, if it has an entry ─────────────
xcheck="no prior known_hosts entry for this IP"
if [[ -r "$KNOWN" ]]; then
  prior="$(ssh-keygen -F "$IP" -f "$KNOWN" 2>/dev/null | awk '!/^#/ && NF { print $2, $3 }' || true)"
  prior_ec="$(awk '$1 == "ecdsa-sha2-nistp256"' <<<"$prior")"
  if [[ -n "$prior_ec" ]]; then
    if grep -qxF -- "$KEY" <<<"$prior_ec"; then
      xcheck="MATCHES the operator's existing known_hosts ECDSA entry"
    else
      die "MISMATCH: $KNOWN already holds a DIFFERENT ecdsa-sha2-nistp256 key for $IP. Do not pin anything: either web-1 was re-keyed/replaced or this path is intercepted. Follow ADR-237 / the runbook's H4 triage."
    fi
  elif [[ -n "$prior" ]]; then
    xcheck="known_hosts has entries for this IP but none of type ecdsa-sha2-nistp256 (not comparable)"
  fi
fi

# ── 4. write the pin file atomically ──────────────────────────────────────────────────────
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "# web-1 SSH host key pin (#7226, ADR-237). ECDSA-P256: the algorithm Terraform's Go client"
  echo "# negotiates. Consumed by the cf-tunnel-ssh-bridge writer and local.web_1_ssh_host_key."
  echo "# captured: $NOW by scripts/capture-web-1-host-key.sh (ssh-keyscan -T 10 -t ecdsa, direct to"
  echo "#   web-1's public :22 from an ADMIN_IPS egress, not via Cloudflare)"
  echo "# fingerprint: $FP"
  echo "# cross-check: $xcheck"
  printf '%s\n' "$KEY"
} > "$WORK/pin"
assert_fixture_dir "$OUT"
mkdir -p "$(dirname "$OUT")"
cp "$WORK/pin" "$OUT.tmp.$$" && mv -f "$OUT.tmp.$$" "$OUT"

echo "wrote $OUT"
echo "  fingerprint: $FP"
echo "  cross-check: $xcheck"
echo "Record the fingerprint and the capture vantage in the PR body (AC9), then commit the file."
