#!/usr/bin/env bash
# Regression guard for #6595: verify-tunnel-ingress-origin.sh must resolve its
# infra dir from its OWN location (absolute, CWD-independent), NOT by `cd`-ing a
# possibly-relative $INFRA_DIR env var.
#
# The post-merge apply of PR #6595 died here:
#   verify-tunnel-ingress-origin.sh: line 18: cd: apps/web-platform/infra: No such file or directory
# because apply-web-platform-infra.yml exports INFRA_DIR=apps/web-platform/infra
# (relative) AND runs the step with working-directory=$INFRA_DIR — so the CWD is
# ALREADY the infra dir, and `cd apps/web-platform/infra` from inside it fails.
# That failure is not cosmetic: the verify step gates the SSH-provisioned apply
# leg (`if: success()`), so it skipped the apply that delivers the fail2ban
# `ignoreip` grant and every other SSH-provisioned resource fleet-wide.
#
# This test reproduces the CI invocation exactly (CWD = infra dir, INFRA_DIR set
# to the relative value) with a stub `doppler` on PATH, and asserts the script
# gets PAST the `cd` — i.e. it reaches its first external call instead of dying
# on a path that does not exist. Hermetic: no network, no doppler, no prod.

set -euo pipefail

echo "verify-tunnel-ingress-origin-infradir.test.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ABS="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$INFRA_ABS/scripts/verify-tunnel-ingress-origin.sh"
# The relative value the workflow exports (env.INFRA_DIR at line 128).
REL_INFRA_DIR="apps/web-platform/infra"

[[ -f "$TARGET" ]] || { echo "FAIL: $TARGET not found"; exit 1; }

fails=0

# --- Stub PATH: a fake `doppler` that records it was reached, then exits. -----------
# doppler is the FIRST external command the script runs after the cd, so reaching
# it proves the cd resolved. It exits 0 with no output; the script then fails its
# own IP-regex check and exits 1 — expected, and irrelevant to this test.
STUB_DIR="$(mktemp -d)"
MARKER="$(mktemp -u)"
trap 'rm -rf "$STUB_DIR"; rm -f "$MARKER"' EXIT
cat >"$STUB_DIR/doppler" <<STUB
#!/usr/bin/env bash
touch "$MARKER"
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# --- Reproduce the CI invocation: CWD = absolute infra dir, INFRA_DIR = relative. ---
set +e
OUT="$(cd "$INFRA_ABS" && INFRA_DIR="$REL_INFRA_DIR" PATH="$STUB_DIR:$PATH" \
  bash "$TARGET" 2>&1)"
set -e

if printf '%s' "$OUT" | grep -qiE 'cd:.*No such file or directory'; then
  echo "FAIL: script died on the relative-INFRA_DIR cd — #6595 regression:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
  fails=1
elif [[ ! -e "$MARKER" ]]; then
  echo "FAIL: script never reached its first external call (doppler stub not hit) — it did not get past the cd:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
  fails=1
else
  echo "PASS: script resolves the infra dir absolutely and reaches its first call with CWD=infra-dir + relative INFRA_DIR"
fi

# --- Also assert the source no longer honors a relative $INFRA_DIR override. --------
# A structural belt to the behavioral test above: the resolution must not be
# `${INFRA_DIR:-...}` (which re-admits the relative env value). It must derive from
# BASH_SOURCE unconditionally.
if grep -qE 'INFRA_DIR="\$\{INFRA_DIR:-' "$TARGET"; then
  echo "FAIL: script still honors a relative \$INFRA_DIR override (\${INFRA_DIR:-...}) — the #6595 bug can recur"
  fails=1
else
  echo "PASS: infra dir is derived from BASH_SOURCE, not a relative env override"
fi

# --- Self-registration: this suite must be wired into infra-validation.yml. ---------
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"
if [[ -f "$INFRA_VALIDATION" ]] && \
   grep -qE 'bash apps/web-platform/infra/verify-tunnel-ingress-origin-infradir\.test\.sh' "$INFRA_VALIDATION"; then
  echo "PASS: suite is registered in infra-validation.yml"
else
  echo "FAIL: suite is NOT registered in infra-validation.yml — it would be an orphan (#5417 class)"
  fails=1
fi

[[ "$fails" -eq 0 ]] || exit 1
echo "OK"
