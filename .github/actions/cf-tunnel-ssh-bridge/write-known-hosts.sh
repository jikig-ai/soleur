#!/usr/bin/env bash
# write-known-hosts.sh <alias> <pin-file> <out>  (#7226, ADR-237)
#
# The ONE validated writer that turns an SSH host-key pin into a known_hosts line for every CI
# bash ssh path: the cf-tunnel-ssh-bridge (web-1, from the committed
# apps/web-platform/infra/web-1-ssh-host-key.pub) and git-data-cutover.yml (web-1 again, plus
# git-data from the Doppler-published GIT_DATA_SSH_HOST_KEY the flag precheck wrote to a file).
#
# Contract:
#   * <pin-file> holds `#` comment lines, blank lines and EXACTLY ONE key line. CR bytes are
#     stripped first (a CRLF checkout is not an error). Zero or two-plus key lines refuse.
#   * The key line must match the regex for its algorithm EXACTLY: no host pattern, no marker
#     (@cert-authority / @revoked), no comment, no leading or trailing whitespace. A mis-shaped
#     pin could otherwise inject a known_hosts wildcard that trusts an attacker key for every host.
#   * <alias> is the HostKeyAlias the caller's ssh uses; the file holds `<alias> <key>`.
#   * <out> must match ^/[A-Za-z0-9/_.-]+$ -- callers expand ${WEB_HOST_SSH} UNQUOTED, so a
#     space or metacharacter in the path would split or inject into the ssh argv.
#   * Repeat calls with DIFFERENT aliases append into one file (the cutover's two hops). A second
#     entry for an alias already present refuses. The file is replaced atomically and left 0444.
#   * Only the SHA256 fingerprint is printed, never the key body.
#
# Exit 0 on success; 1 on any refusal, with nothing written.
set -euo pipefail

die() { printf 'write-known-hosts: refused: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 3 ]] || die "usage: write-known-hosts.sh <alias> <pin-file> <out>"
alias="$1" pin_file="$2" out="$3"

[[ "$alias" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "alias must match ^[a-z0-9][a-z0-9.-]*\$"
OUT_RE='^/[A-Za-z0-9/_.-]+$'
[[ "$out" =~ $OUT_RE ]] || die "out path must match $OUT_RE"
[[ ! -L "$out" ]] || die "out path is a symlink"
[[ ! -e "$out" || -f "$out" ]] || die "out path exists and is not a regular file"
[[ -f "$pin_file" && -r "$pin_file" ]] || die "pin file is missing or unreadable"

# awk, not `grep -v`: grep exits 1 when nothing survives, which pipefail turns into an abort
# with no diagnosis. awk always exits 0 and the count check below names the failure.
keys="$(awk '{ gsub(/\r/, "") } /^[[:space:]]*(#|$)/ { next } { print }' "$pin_file")" \
  || die "pin file could not be read"
if [[ -z "$keys" ]]; then count=0; else count="$(grep -c '' <<<"$keys")"; fi
[[ "$count" -eq 1 ]] || die "pin file must hold exactly one key line, found $count"
pin="$keys"

case "$pin" in
  ecdsa-sha2-nistp256\ *)
    # twin: apps/web-platform/infra/server.tf local.web_1_ssh_host_key (HCL regex())
    RE='^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=$'
    ;;
  ssh-ed25519\ *)
    # twin: apps/web-platform/server/git-data-replication.ts resolveGitDataHostKeyPin;
    # apps/web-platform/infra/git-data-flag-precheck.sh (the GIT_DATA_SSH_HOST_KEY read)
    RE='^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$'
    ;;
  *) die "unsupported key algorithm (want ecdsa-sha2-nistp256 or ssh-ed25519)" ;;
esac
# $RE MUST stay unquoted: a quoted right-hand side makes =~ a literal string compare, which
# rejects every valid pin (tests/scripts/test-write-known-hosts.sh row Q proves it).
[[ $pin =~ $RE ]] || die "key line does not match the ${pin%% *} pin shape"

if [[ -f "$out" ]] && awk -v a="$alias" '$1 == a { f = 1 } END { exit !f }' "$out"; then
  die "an entry for alias '$alias' already exists in $out"
fi

tmp="$(mktemp "$out.XXXXXX")" || die "cannot create a temp file next to $out"
trap 'rm -f "$tmp"' EXIT
{
  if [[ -f "$out" ]]; then cat "$out"; fi
  printf '%s %s\n' "$alias" "$pin"
} > "$tmp"
chmod 0444 "$tmp"
mv -f "$tmp" "$out"
trap - EXIT

fp="$(printf '%s %s\n' "$alias" "$pin" | ssh-keygen -lf - 2>/dev/null | awk '{ print $2 }')" || fp=""
printf 'write-known-hosts: pinned %s %s %s\n' "$alias" "${pin%% *}" "${fp:-SHA256:<ssh-keygen unavailable>}"
