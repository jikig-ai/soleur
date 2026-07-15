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
# `inline = [` and the first element (docker_seccomp_config did this
# pre-sweep; the skip stays so future comment placement cannot false-FAIL).
# The global comment-skip also prevents a doc comment quoting the arming
# tokens from creating a phantom block. The `inline` match tolerates
# fmt-aligned padding (`inline     = [`) — terraform fmt aligns equals
# signs when a provisioner carries a second attribute. Known limit: a
# future `script =` provisioner leaves armed=1 dangling (fail-closed —
# it mis-attributes the next inline list as its own, never false-PASSes).
out="$(awk '
  /^[[:space:]]*#/ { next }
  /provisioner "remote-exec"/ { armed = 1 }
  armed && /inline[[:space:]]*=[[:space:]]*\[/ { inlist = 1; armed = 0; next }
  inlist {
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
[[ "$blocks" -ge 13 ]] || { echo "FAIL: expected >= 13 remote-exec blocks, parsed $blocks (parser drift, or a block was legitimately removed — update the floor in this test)"; exit 1; }
[[ "$blocks" -eq "$ok" ]] || { echo "FAIL: $((blocks - ok)) block(s) lack set -e gating"; exit 1; }
echo "PASS: all $blocks remote-exec inline blocks open with set -e"
