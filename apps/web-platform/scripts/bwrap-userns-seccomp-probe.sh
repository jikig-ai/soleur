#!/usr/bin/env bash
# #8752 discoverability probe: is the shared nested-userns seccomp hardening
# present on THIS host/image? Run standalone; prints exactly one outcome line:
#
#   USNS_SECCOMP_OK              — artifact byte-identical to the generator's
#                                  output, shim present, and (when bwrap can
#                                  sandbox here) the live deny is measured.
#   USNS_SECCOMP_SKIP_NO_BWRAP   — artifact + shim present but this host cannot
#                                  create a bwrap sandbox (no behavioral proof).
#
# Exit code mirrors the outcome (0 ok/skip-with-warning, 1 fail). Cheap (<15 s),
# no metacharacters needed at the call site.

set -u

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BPF="${SOLEUR_BWRAP_SECCOMP_BPF:-$APP_DIR/infra/bwrap-userns-clone3-deny.bpf}"
GEN="$APP_DIR/scripts/gen-bwrap-userns-seccomp.mjs"
SHIM="${SOLEUR_BWRAP_SHIM:-$APP_DIR/infra/bwrap-shim/bwrap}"
REAL="${SOLEUR_BWRAP_REAL:-/usr/bin/bwrap}"

fail() { echo "USNS_SECCOMP_FAIL: $*" >&2; exit 1; }

# 1. Artifact present, non-empty, raw-sock_filter-shaped.
[ -s "$BPF" ] || fail "artifact missing or empty: $BPF"
sz=$(wc -c <"$BPF" 2>/dev/null | tr -d ' ')
[ -n "$sz" ] && [ "$sz" -gt 0 ] && [ $((sz % 8)) -eq 0 ] || fail "artifact not 8-byte-instruction aligned ($sz bytes)"

# 2. Byte-parity with the generator (the committed bytes ARE the generated
#    program — a hand-edited or stale artifact fails here).
node "$GEN" --check "$BPF" >/dev/null 2>&1 || fail "generator --check parity fails: $BPF (regenerate: node $GEN)"

# 3. Shim present + carries its identity marker.
[ -x "$SHIM" ] || fail "shim missing or non-executable: $SHIM"
grep -q 'bwrap-shim:' "$SHIM" || fail "shim lacks its bwrap-shim: identity marker: $SHIM"

# 4. Behavioral proof when real bwrap can sandbox on this host.
if [ ! -x "$REAL" ]; then
  echo "USNS_SECCOMP_SKIP_NO_BWRAP"
  exit 0
fi
if ! "$REAL" --unshare-user --unshare-pid --unshare-net --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 -- /usr/bin/true >/dev/null 2>&1; then
  echo "USNS_SECCOMP_SKIP_NO_BWRAP"
  exit 0
fi

# 4a. Deny: nested user namespace must EPERM inside the filtered sandbox —
# through the shim (the same PATH interception the Agent SDK spawn takes).
# The shim must reach BOTH real bwrap and the artifact (the env overrides
# make a shim-side exit-65 setup failure distinguishable from a real deny —
# a vacuous non-zero would false-pass).
SOLEUR_BWRAP_SECCOMP_BPF="$BPF" SOLEUR_BWRAP_REAL="$REAL" \
  "$SHIM" --unshare-user --unshare-pid --unshare-net --unshare-ipc --unshare-uts \
  --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --dev /dev \
  -- /usr/bin/unshare -U /usr/bin/true >/dev/null 2>&1
rc=$?
[ "$rc" -ne 65 ] || fail "shim setup failed (exit 65) — artifact/real-bwrap resolution broken"
[ "$rc" -ne 0 ] || fail "nested unshare -U succeeded — filter not applied through the shim"

# 4b. Control: a forked child still runs (the filter is not a blanket deny).
SOLEUR_BWRAP_SECCOMP_BPF="$BPF" SOLEUR_BWRAP_REAL="$REAL" \
  "$SHIM" --unshare-user --unshare-pid --unshare-net --unshare-ipc --unshare-uts \
  --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --dev /dev \
  -- /usr/bin/sh -c '/usr/bin/true' >/dev/null 2>&1 \
  || fail "forked child failed inside the filtered sandbox — filter over-broad?"

echo "USNS_SECCOMP_OK"
exit 0
