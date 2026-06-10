#!/usr/bin/env bash
# Drift-guard: every `provisioner "remote-exec"` inline block in server.tf
# must open with "set -e", as its first non-comment element. Terraform joins
# inline into ONE shell script with NO implicit errexit and fails only on the
# LAST command's exit status (#5089/#5101) — without set -e every intermediate
# assertion is decorative (silent-green).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"

# Flag-based awk (NOT /start/,/end/ ranges — self-match trap): arm on
# `provisioner "remote-exec"`, then on `inline = [`, then the first
# non-comment line must be "set -e", . Comments may legally sit between
# `inline = [` and the first element (docker_seccomp_config does this).
out="$(awk '
  /provisioner "remote-exec"/ { armed = 1 }
  armed && /inline = \[/      { inlist = 1; armed = 0; next }
  inlist {
    if ($0 ~ /^[[:space:]]*#/) next
    blocks++
    if ($0 ~ /^[[:space:]]*"set -e",$/) ok++
    else printf "FAIL block %d: first element is not \"set -e\": %s\n", blocks, $0
    inlist = 0
  }
  END { printf "blocks=%d ok=%d\n", blocks, ok }
' "$SERVER_TF")"
echo "$out"
blocks="$(sed -n 's/^blocks=\([0-9]*\) ok=[0-9]*$/\1/p' <<<"$out")"
ok="$(sed -n 's/^blocks=[0-9]* ok=\([0-9]*\)$/\1/p' <<<"$out")"
# Vacuous-pass protection: parser drift that finds 0 blocks must FAIL.
[[ "$blocks" -ge 13 ]] || { echo "FAIL: expected >= 13 remote-exec blocks, parsed $blocks (parser drift?)"; exit 1; }
[[ "$blocks" -eq "$ok" ]] || { echo "FAIL: $((blocks - ok)) block(s) lack set -e gating"; exit 1; }
echo "PASS: all $blocks remote-exec inline blocks open with set -e"
