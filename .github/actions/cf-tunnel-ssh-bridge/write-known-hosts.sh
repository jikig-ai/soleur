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
#   * Repeat calls with DIFFERENT aliases append into one file (the cutover's two hops). Before
#     appending, EVERY existing line of <out> must be a line this script could have written
#     (`<alias> ecdsa-sha2-nistp256 <body>` or `<alias> ssh-ed25519 <body>`, validated exactly as
#     a pin is). A pre-seeded @cert-authority / @revoked line, a host-pattern line (`web-1,foo`,
#     `*`), a comment or a CR refuses: this writer never extends a file it cannot vouch for. A
#     second entry for an alias already present refuses, checked on every comma-separated host
#     field of every line. The file is replaced atomically and left 0444.
#   * Only the SHA256 fingerprint is printed, never the key body.
#   * A refusal prints `::error title=write-known-hosts::verdict=pin_refused alias=<alias>
#     reason=<word>` (one fixed word per arm; the alias only once it has passed validation) plus
#     a human line on stderr. Neither ever echoes bytes read from <pin-file> or <out>.
#
# Exit 0 on success; 1 on any refusal, with nothing written.
set -euo pipefail

# The fixture-dir assertion, byte-equal to the canonical definition in
# plugins/soleur/test/test-helpers.sh (plugins/soleur/test/fixture-dir-operand-assert.test.sh
# compares every tracked copy against it). Copied rather than sourced: this runs in CI from the
# action directory. It backs the OUT_RE / dot-segment checks below before any write.
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

ALIAS_OUT="invalid"   # printed in the annotation only after the alias passes validation
# die <reason-word> <human message>. The message is composed from fixed text and values this
# script derived (counts, argument positions), never from file bytes.
die() {
  printf '::error title=write-known-hosts::verdict=pin_refused alias=%s reason=%s\n' "$ALIAS_OUT" "$1"
  printf 'write-known-hosts: refused (%s): %s\n' "$1" "$2" >&2
  exit 1
}

[[ $# -eq 3 ]] || die usage "usage: write-known-hosts.sh <alias> <pin-file> <out>"
alias="$1" pin_file="$2" out="$3"

ALIAS_RE='^[a-z0-9][a-z0-9.-]*$'
[[ "$alias" =~ $ALIAS_RE ]] || die alias_invalid "alias must match $ALIAS_RE"
ALIAS_OUT="$alias"
OUT_RE='^/[A-Za-z0-9/_.-]+$'
[[ "$out" =~ $OUT_RE ]] || die out_path_invalid "out path must match $OUT_RE"
case "$out" in
  */../*|*/..|*/./*|*/.|*//*|/proc/*|/sys/*|/dev/*) die out_path_invalid "out path has a dot/empty segment or is under /proc, /sys or /dev" ;;
esac
[[ ! -L "$out" ]] || die out_symlink "out path is a symlink"
[[ ! -e "$out" || -f "$out" ]] || die out_not_regular "out path exists and is not a regular file"
[[ -f "$pin_file" && -r "$pin_file" ]] || die pin_unreadable "pin file is missing or unreadable"

# awk, not `grep -v`: grep exits 1 when nothing survives, which pipefail turns into an abort
# with no diagnosis. awk always exits 0 and the count check below names the failure.
keys="$(awk '{ gsub(/\r/, "") } /^[[:space:]]*(#|$)/ { next } { print }' "$pin_file")" \
  || die pin_unreadable "pin file could not be read"
if [[ -z "$keys" ]]; then count=0; else count="$(grep -c '' <<<"$keys")"; fi
[[ "$count" -eq 1 ]] || die key_count "pin file must hold exactly one key line, found $count"
pin="$keys"

case "$pin" in
  ecdsa-sha2-nistp256\ *)
    ALGO=ecdsa-sha2-nistp256
    # twin: apps/web-platform/infra/server.tf local.web_1_ssh_host_key (HCL regex())
    RE='^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=$'
    ;;
  ssh-ed25519\ *)
    ALGO=ssh-ed25519
    # twin: apps/web-platform/infra/git-data-flag-precheck.sh (the GIT_DATA_SSH_HOST_KEY read);
    # apps/web-platform/server/git-data-replication.ts (resolveGitDataHostKeyPin);
    # apps/web-platform/infra/modules/git-data-userdata/variables.tf (host_ssh_ed25519_public_key)
    RE='^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$'
    ;;
  *) die algorithm "unsupported key algorithm (want ecdsa-sha2-nistp256 or ssh-ed25519)" ;;
esac
# $RE MUST stay unquoted: a quoted right-hand side makes =~ a literal string compare, which
# rejects every valid pin (tests/scripts/test-write-known-hosts.sh row Q proves it).
[[ $pin =~ $RE ]] || die key_shape "key line does not match the $ALGO pin shape"

# The existing file, if any. Both checks run over EVERY line, before anything is written.
# ECDSA / ED25519 bodies below are the same regexes as the pin arms above (one file, two uses).
if [[ -f "$out" ]]; then
  # 1. Duplicate alias: any comma-separated host field of any line that equals <alias>, or is a
  #    wildcard pattern that would also match it.
  if ! awk -v a="$alias" '{ n = split($1, h, ","); for (i = 1; i <= n; i++) if (h[i] == a || h[i] ~ /[*?!]/) bad = 1 }
                          END { exit bad }' "$out"; then
    die alias_present "an entry for alias '$alias' (or a host pattern covering it) already exists in the out file"
  fi
  # 2. Every line must be one this script could have written. `LC_ALL=C` so the bracket ranges
  #    are byte ranges; `\r` never matches the body classes, so a CR anywhere refuses.
  if ! LC_ALL=C awk '
      !/^[a-z0-9][a-z0-9.-]* (ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+\/]+=|ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+\/]+)$/ { bad = 1; next }
      $2 == "ecdsa-sha2-nistp256" && length($3) != 140 { bad = 1 }
      $2 == "ssh-ed25519" && length($3) != 68 { bad = 1 }
      END { exit bad }' "$out"; then
    die foreign_line "the out file holds a line this writer did not write (marker, pattern, comment, CR or mis-shaped key); refusing to extend it"
  fi
fi

assert_fixture_dir "$out"
tmp="$(mktemp "$out.XXXXXX")" || die write_failed "cannot create a temp file next to the out file"
assert_fixture_dir "$tmp"
trap 'rm -f "$tmp"' EXIT
{
  if [[ -f "$out" ]]; then cat "$out"; fi
  printf '%s %s\n' "$alias" "$pin"
} > "$tmp" || die write_failed "cannot write the temp file"
chmod 0444 "$tmp"
mv -f "$tmp" "$out" || die write_failed "cannot move the temp file into place"
trap - EXIT

fp="$(printf '%s %s\n' "$alias" "$pin" | ssh-keygen -lf - 2>/dev/null | awk '{ print $2 }')" || fp=""
printf 'write-known-hosts: pinned %s %s %s\n' "$alias" "${pin%% *}" "${fp:-SHA256:<ssh-keygen unavailable>}"
