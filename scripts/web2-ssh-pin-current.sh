#!/usr/bin/env bash
# web2-ssh-pin-current.sh — observability discoverability probe for #11445.
#
# Asserts the committed web-2 host-key pin (apps/web-platform/infra/web-2-ssh-host-key.pub)
# is parseable pin material for the CURRENT web-2, not a predecessor's:
#   * exactly one non-comment `ecdsa-sha2-nistp256` key line (the only key type Terraform's
#     Go client negotiates and the only type every CI consumer's known_hosts writer accepts);
#   * the `# fingerprint:` header does not equal a fingerprint recorded for a predecessor
#     host. The predecessor set is anchored to this incident's evidence OUTSIDE the commit:
#     the pre-fix committed file (SHA256:prjb…) vs. the key web-2 offered in apply run
#     40744937376 (SHA256:OB3/…). "Not a known-predecessor" — NOT "equals today's" — so the
#     next legitimate re-capture (the routine post-replace re-key, ADR-237) stays green
#     without editing this probe.
#
# Pure bash+grep+awk: no ssh-keygen dependency (the Check-10 sandbox does not guarantee it).
# Reads a repo file only — no network, no credentials.
#
# Usage: bash scripts/probes/web2-ssh-pin-current.sh [pin-file]
# Exit: 0 → prints PIN_CURRENT; 1 → named reason on stderr; 2 → usage.
set -euo pipefail

usage() { echo "usage: $0 [pin-file]" >&2; exit 2; }
[[ $# -le 1 ]] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="${1:-$REPO_ROOT/apps/web-platform/infra/web-2-ssh-host-key.pub}"

# Fingerprints observed on hosts web-2 no longer is. Extend ONLY with a verified
# predecessor fingerprint (run log or superseded commit), never the current key's.
PREDECESSOR_FPS='SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE'

die() { printf 'web2-ssh-pin-current: %s\n' "$*" >&2; exit 1; }

[[ -f "$PIN" ]] || die "pin file missing: $PIN"
[[ -r "$PIN" ]] || die "pin file unreadable: $PIN"

# Exactly one non-comment, non-empty key line, and it must be ecdsa-sha2-nistp256.
key_lines="$(awk '!/^#/ && NF' "$PIN")"
n="$(printf '%s\n' "$key_lines" | awk 'NF' | wc -l | tr -d ' ')"
[[ "$n" -gt 0 ]] || die "zero non-comment key lines in $PIN (pin file carries no key)"
[[ "$n" -eq 1 ]] || die "expected exactly one non-comment key line in $PIN, got $n"
key_type="$(printf '%s\n' "$key_lines" | awk 'NF {print $1; exit}')"
[[ "$key_type" == "ecdsa-sha2-nistp256" ]] \
  || die "key line offers '$key_type', not ecdsa-sha2-nistp256 — Terraform's Go client negotiates ECDSA-P256 only"

# The # fingerprint: header must exist and must not name a predecessor host.
fp="$(awk '/^# fingerprint:/ {print $3; exit}' "$PIN")"
[[ -n "$fp" ]] || die "no '# fingerprint:' header in $PIN (capture-web-2-host-key.sh writes one; a hand-edited pin is unverifiable)"
case " $PREDECESSOR_FPS " in
  *" $fp "*) die "stale pin: $PIN still carries predecessor fingerprint $fp — run scripts/capture-web-2-host-key.sh <web-2-public-ipv4> from an ADMIN_IPS egress" ;;
esac

echo "PIN_CURRENT"
