#!/usr/bin/env bash
# #8752 discoverability probe: is the shared nested-userns seccomp hardening
# present on THIS host/image? Run standalone; bounded to <15 s total (each
# spawn is `timeout 10`-wrapped), no metacharacters needed at the call site.
#
# Outcome contract — exactly one line on the outcome stream:
#
#   USNS_SECCOMP_OK              — artifact byte-identical to the generator's
#                                  output, shim present, and (when bwrap can
#                                  sandbox here) the live deny is measured.
#   USNS_SECCOMP_SKIP_NO_BWRAP   — artifact + shim present but this host cannot
#                                  create a bwrap sandbox (no behavioral proof).
#   USNS_SECCOMP_FAIL: <reason>  — on STDERR, exit 1; each reason names the
#                                  failing surface.
#
# Env overrides (test/dev only — never needed in prod):
#   SOLEUR_BWRAP_SECCOMP_BPF  artifact path      (default: $APP_DIR/infra/…bpf)
#   SOLEUR_BWRAP_SHIM         shim path          (default: $APP_DIR/infra/bwrap-shim/bwrap)
#   SOLEUR_BWRAP_REAL         real bwrap path    (default: /usr/bin/bwrap)

set -u

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BPF="${SOLEUR_BWRAP_SECCOMP_BPF:-$APP_DIR/infra/bwrap-userns-clone3-deny.bpf}"
GEN="$APP_DIR/scripts/gen-bwrap-userns-seccomp.mjs"
SHIM="${SOLEUR_BWRAP_SHIM:-$APP_DIR/infra/bwrap-shim/bwrap}"
REAL="${SOLEUR_BWRAP_REAL:-/usr/bin/bwrap}"

if [ "${1:-}" = "--help" ]; then sed -n '2,22p' "$0"; exit 0; fi

fail() { echo "USNS_SECCOMP_FAIL: $*" >&2; exit 1; }

# A shared sandbox argv so the measure/control legs exercise the SAME build.
SANDBOX_ARGV=(--unshare-user --unshare-pid --unshare-net --unshare-ipc --unshare-uts
  --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --dev /dev)

# 1. Artifact present, non-empty, raw-sock_filter-shaped (8-byte insns).
[ -s "$BPF" ] || fail "artifact missing or empty: $BPF"
sz=$(wc -c <"$BPF" 2>/dev/null | tr -d ' ')
[ $((sz % 8)) -eq 0 ] || fail "artifact not 8-byte-instruction aligned ($sz bytes)"

# 2. Byte-parity with the generator (the committed bytes ARE the generated
#    program — a hand-edited or stale artifact fails here).
command -v node >/dev/null || fail "node not on PATH — cannot run generator --check"
node "$GEN" --check "$BPF" >/dev/null 2>&1 || fail "generator --check parity fails: $BPF (regenerate: node $GEN)"

# 3. Shim present + carries its identity marker.
[ -x "$SHIM" ] || fail "shim missing or non-executable: $SHIM"
grep -q 'bwrap-shim:' "$SHIM" || fail "shim lacks its bwrap-shim: identity marker: $SHIM"

# 3b. PATH interception — the contract is scoped to the image's shim slot:
#     when `command -v bwrap` resolves to /usr/local/bin/bwrap it MUST carry
#     the marker (else a binary swapped over the shim intercepts every SDK
#     spawn unfiltered). Other resolutions are dev-host-normal (system bwrap
#     at /usr/bin) — not this probe's claim.
if [ "$(command -v bwrap 2>/dev/null || true)" = "/usr/local/bin/bwrap" ]; then
  grep -q 'bwrap-shim:' /usr/local/bin/bwrap || fail "/usr/local/bin/bwrap lacks the bwrap-shim: marker — interception shadowed"
fi

# 4. Behavioral proof when real bwrap can sandbox on this host.
if [ ! -x "$REAL" ]; then
  echo "USNS_SECCOMP_SKIP_NO_BWRAP"
  exit 0
fi
if ! timeout 10 "$REAL" "${SANDBOX_ARGV[@]}" -- /usr/bin/true >/dev/null 2>&1; then
  echo "USNS_SECCOMP_SKIP_NO_BWRAP"
  exit 0
fi

# 4a. Deny: nested user namespace must EPERM inside the filtered sandbox —
# through the shim (the same PATH interception the Agent SDK spawn takes).
# The denial must carry the payload's own "Operation not permitted" — a bare
# non-zero could be a setup failure that never exercised the filter
# (expected-fail inversion); a shim exit 65 is a setup defect, loudly named.
err=$(SOLEUR_BWRAP_SECCOMP_BPF="$BPF" SOLEUR_BWRAP_REAL="$REAL" \
  timeout 10 "$SHIM" "${SANDBOX_ARGV[@]}" \
  -- /usr/bin/unshare -U /usr/bin/true 2>&1 >/dev/null)
rc=$?
[ "$rc" -ne 0 ] || fail "nested unshare -U SUCCEEDED — filter not applied through the shim"
[ "$rc" -ne 65 ] || fail "shim setup failed (exit 65): $err"
case "$err" in
  *"peration not permitted"*) ;;  # the payload's own EPERM signature
  *) fail "nested unshare -U failed without an EPERM signature (rc=$rc): $err" ;;
esac

# 4b. Control: a forked child still runs (the filter is not a blanket deny).
SOLEUR_BWRAP_SECCOMP_BPF="$BPF" SOLEUR_BWRAP_REAL="$REAL" \
  timeout 10 "$SHIM" "${SANDBOX_ARGV[@]}" \
  -- /usr/bin/sh -c '/usr/bin/true' >/dev/null 2>&1 \
  || fail "forked child failed inside the filtered sandbox — filter over-broad?"

echo "USNS_SECCOMP_OK"
exit 0
