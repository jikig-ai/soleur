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
  # (#6416) `inline = local.web1_hostname_assert` — the list lives in the locals
  # block, so there is no `[` to arm on here. Count the reference and validate the
  # list at its DEFINITION site (the rule below). Without this arm the indirection
  # would sail past the guard entirely: `armed` would stay set and mis-attribute
  # the NEXT literal inline list as this provisioner"s.
  armed && /inline[[:space:]]*=[[:space:]]*local\.web1_hostname_assert[[:space:]]*$/ { refs++; armed = 0; next }
  # Any OTHER `inline = local.*` is an unvalidated indirection — fail closed rather
  # than skip it, so this guard cannot be bypassed by hoisting a list into locals.
  armed && /inline[[:space:]]*=[[:space:]]*local\./ {
    printf "FAIL: unvalidated `inline = local.*` indirection (add it to this guard): %s\n", $0
    bad++; armed = 0; next
  }
  armed && /inline[[:space:]]*=[[:space:]]*\[/ { inlist = 1; armed = 0; next }
  # (#6416) Definition site of the shared assert list. Validated exactly like an
  # inline block: its first element must be "set -e".
  /web1_hostname_assert[[:space:]]*=[[:space:]]*\[/ { inlist = 1; armed = 0; next }
  inlist {
    blocks++
    if ($0 ~ /^[[:space:]]*"set -e",$/) ok++
    else printf "FAIL block %d: first element is not \"set -e\": %s\n", blocks, $0
    inlist = 0
  }
  END { printf "blocks=%d ok=%d refs=%d bad=%d\n", blocks, ok, refs, bad }
' "$SERVER_TF")"
echo "$out"
blocks="$(sed -n 's/^blocks=\([0-9]*\) ok=[0-9]* refs=[0-9]* bad=[0-9]*$/\1/p' <<<"$out")"
ok="$(sed -n 's/^blocks=[0-9]* ok=\([0-9]*\) refs=[0-9]* bad=[0-9]*$/\1/p' <<<"$out")"
refs="$(sed -n 's/^blocks=[0-9]* ok=[0-9]* refs=\([0-9]*\) bad=[0-9]*$/\1/p' <<<"$out")"
bad="$(sed -n 's/^blocks=[0-9]* ok=[0-9]* refs=[0-9]* bad=\([0-9]*\)$/\1/p' <<<"$out")"
# Vacuous-pass protection: parser drift that finds 0 blocks must FAIL. The floor is
# MEASURED against the as-written file, not tallied from prose: 19 = 18 literal
# inline blocks (the count on origin/main at #6416) + the shared
# web1_hostname_assert list. The previous floor was 13 against an actual 18 — loose
# enough to let five blocks silently vanish, so it is tightened here while the
# parser is already being touched.
[[ "$blocks" -ge 19 ]] || { echo "FAIL: expected >= 19 remote-exec inline lists, parsed $blocks (parser drift, or a block was legitimately removed — update the floor in this test)"; exit 1; }
[[ "$blocks" -eq "$ok" ]] || { echo "FAIL: $((blocks - ok)) block(s) lack set -e gating"; exit 1; }
[[ "$bad" -eq 0 ]] || { echo "FAIL: $bad unvalidated \`inline = local.*\` indirection(s)"; exit 1; }
# (#6416) The wrong-host tripwire must stay wired into EVERY web-1 SSH provisioner.
# Derived from the as-written file, not a plan-time tally: one reference per
# `connection { host = hcloud_server.web["web-1"] … }` block.
conns="$(grep -c 'host        = hcloud_server.web\["web-1"\].ipv4_address' "$SERVER_TF")"
[[ "$refs" -eq "$conns" ]] || {
  echo "FAIL: $refs web1_hostname_assert reference(s) for $conns web-1 connection block(s) — every web-1 SSH provisioner must carry the #6416 wrong-host tripwire as its FIRST provisioner"
  exit 1
}
echo "PASS: all $blocks remote-exec inline lists open with set -e; all $conns web-1 provisioners carry the #6416 tripwire"
