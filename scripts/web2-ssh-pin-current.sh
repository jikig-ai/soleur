#!/usr/bin/env bash
# web2-ssh-pin-current.sh — observability discoverability probe for #11445.
#
# Asserts the committed web-2 host-key pin (apps/web-platform/infra/web-2-ssh-host-key.pub)
# is parseable pin material for the CURRENT web-2, not a predecessor's:
#   * exactly one non-comment key line, and that line matches the SAME anchored key-shape
#     regex the real consumer applies — local.web_2_ssh_host_key (server.tf) requires
#     ^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[…]{86}=$
#     or terraform plan fails before apply ever runs;
#   * the `# fingerprint:` header carries a SHA256: value BOUND to the key body (the probe
#     recomputes it: base64-decode the blob, sha256, base64 without padding — the OpenSSH
#     fingerprint construction), so a stale body under a hand-freshened header still reds;
#   * the bound fingerprint is not in the predecessor set, anchored to this incident's
#     evidence OUTSIDE the commit: the pre-fix committed file (SHA256:prjb…) vs. the key
#     web-2 offered in apply run 40744937376 (SHA256:OB3/…). "Not a known-predecessor" —
#     NOT "equals today's" — so the next legitimate re-capture (the routine post-replace
#     re-key, ADR-237) stays green without editing this probe.
#
# Pure bash + coreutils (awk, tr, base64, sha256sum, printf) — no ssh-keygen dependency
# (the Check-10 sandbox does not guarantee it). Reads a repo file only — no network, no
# credentials. Input is CR/whitespace-normalized before classification, matching how the
# Terraform consumer reads the same file (server.tf strips \r and trimspace()s comments).
#
# Usage: bash scripts/web2-ssh-pin-current.sh [pin-file]
# Exit: 0 → prints PIN_CURRENT; 1 → named reason on stderr; 2 → usage.
set -euo pipefail

usage() { echo "usage: $0 [pin-file]" >&2; exit 2; }
case "${1-}" in -h|--help) usage ;; esac
[[ $# -le 1 ]] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="${1:-$REPO_ROOT/apps/web-platform/infra/web-2-ssh-host-key.pub}"

# Fingerprints observed on hosts web-2 no longer is. Extend ONLY with a verified
# predecessor fingerprint (run log or superseded commit), never the current key's.
PREDECESSOR_FPS='SHA256:mEDiVY6fDx+3uKNPUZdLn7F/Yzfjq7CZQRcemFC8qbM SHA256:P0J9dUv60r9UHDLAxaTZ9hZDLJ9TYuciQQnQTtdtYiQ SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE'

# Endpoint/file-derived tokens echoed to the operator's stderr: strip C0+DEL (the capture
# script strips U+2028/U+2029 too; tokens here come from a committed reviewed file, and
# dropping the C0 range is the load-bearing half).
san() { printf '%s' "$1" | tr -d '\000-\010\013-\037\177'; }
die() { printf 'web2-ssh-pin-current: %s\n' "$(san "$1")" >&2; exit 1; }

[[ -f "$PIN" ]] || die "pin file missing: $PIN"
[[ -r "$PIN" ]] || die "pin file unreadable: $PIN"

# Classify like the Terraform consumer: strip CR, trim leading whitespace, then a '#'
# line is a comment. Collect non-comment, non-empty key lines.
key_lines="$(tr -d '\r' < "$PIN" | awk '{ t=$0; sub(/^[[:space:]]+/, "", t) } NF && t !~ /^#/')"
n="$(printf '%s\n' "$key_lines" | awk 'NF' | wc -l | tr -d ' ')"
[[ "$n" -gt 0 ]] || die "zero non-comment key lines in $PIN (pin file carries no key)"
[[ "$n" -eq 1 ]] || die "expected exactly one non-comment key line in $PIN, got $n"

# The key line must satisfy the consumer's anchored key shape — a bare type token or a
# truncated blob is PIN_CURRENT on an artifact every consumer rejects at plan time.
printf '%s\n' "$key_lines" | grep -qxE 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=' \
  || die "key line does not match the consumer's anchored ecdsa-sha2-nistp256 key shape (server.tf local.web_2_ssh_host_key regex) — got: $(printf '%s' "$key_lines" | cut -c1-60)…"

# The # fingerprint: header must carry a SHA256: value bound to the key BODY — recompute
# the OpenSSH fingerprint (base64-decoded blob → sha256 → base64, no padding) with
# coreutils only, and require header equality.
key_body="$(printf '%s' "$key_lines" | awk 'NF {print $2; exit}')"
hex="$(printf '%s' "$key_body" | base64 -d 2>/dev/null | sha256sum | awk '{print $1}')" \
  || die "key body is not valid base64 — cannot recompute its fingerprint"
computed="$(printf "$(printf '%s' "$hex" | sed 's/../\\x&/g')" | base64 | tr -d '=')"
fp="$(tr -d '\r' < "$PIN" | awk '/^# fingerprint:/ {print $3; exit}')"
[[ -n "$fp" ]] || die "no '# fingerprint:' header in $PIN (capture-web-2-host-key.sh writes one; a hand-edited pin is unverifiable)"
[[ "$fp" == SHA256:* ]] || die "'# fingerprint:' header is not a SHA256: value — got: $fp"
[[ "SHA256:$computed" == "$fp" ]] \
  || die "fingerprint header $fp does not match the key body's computed fingerprint SHA256:$computed — a stale body under a freshened header"
case " $PREDECESSOR_FPS " in
  *" $fp "*) die "stale pin: $PIN still carries predecessor fingerprint $fp — run scripts/capture-web-2-host-key.sh <web-2-public-ipv4> from an ADMIN_IPS egress" ;;
esac

echo "PIN_CURRENT"
