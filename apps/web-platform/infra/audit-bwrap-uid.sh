#!/usr/bin/env bash
# MU1 (Multi-User Readiness Gate item 1) — bubblewrap UID audit.
#
# Verifies that the OS-level sandbox layer in the production container is
# functional AND that the security-opts it depends on are still attached.
#
# Invoke from the MU1 runbook (see
# knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md)
# or wire into CI post-deploy. Safe to run standalone via SSH into the
# production host:
#
#     ssh <prod-host> "cd soleur && bash apps/web-platform/infra/audit-bwrap-uid.sh"
#
# Override the container name for canaries:
#
#     CONTAINER=soleur-web-platform-canary bash .../audit-bwrap-uid.sh
#
# Exit codes:
#   0 — all three checks passed.
#   1 — any check FAILed. stderr describes which.
#
# Related:
#   - canary liveness check in infra/ci-deploy.sh (uses --unshare-pid only).
#     This script adds --unshare-user to audit UID-namespace creation,
#     which is the real isolation primitive — the canary check never
#     exercised it.
#   - learning `docker-seccomp-blocks-bwrap-sandbox-20260405` — default
#     Docker seccomp blocks CLONE_NEWUSER, silently disabling the whole
#     sandbox. Check 2 detects the regression of dropping the custom
#     seccomp/apparmor profiles from the container.
#   - issues #1546 (bwrap UID investigation) and #1557 (Docker sandbox
#     availability) track the broader container-per-workspace work.

set -euo pipefail

CONTAINER="${CONTAINER:-soleur-web-platform}"
EXPECTED_APPARMOR="apparmor=soleur-bwrap"
EXPECTED_SECCOMP="seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json"

fail_count=0

emit_pass() { echo "PASS: $1"; }
emit_fail() { echo "FAIL: $1" >&2; fail_count=$((fail_count + 1)); }

echo "--- MU1 bubblewrap UID audit --- container=$CONTAINER"

# -----------------------------------------------------------------------------
# Check 1: CLONE_NEWUSER works inside the container.
# This is the single syscall the entire sandbox depends on. If Docker's
# default seccomp profile replaces the custom one, CLONE_NEWUSER returns
# EPERM and bwrap exits non-zero before the real workload runs.
# -----------------------------------------------------------------------------

if ! docker exec "$CONTAINER" bwrap \
    --new-session --die-with-parent \
    --unshare-user --unshare-pid \
    --dev /dev --bind / / \
    -- id -u >/dev/null 2>&1; then
  emit_fail "CLONE_NEWUSER rejected inside $CONTAINER — sandbox non-functional (check seccomp/apparmor, see learning docker-seccomp-blocks-bwrap-sandbox-20260405)"
else
  emit_pass "CLONE_NEWUSER works — bwrap can create a user namespace"
fi

# -----------------------------------------------------------------------------
# Check 2: HostConfig.SecurityOpt still carries the custom apparmor/seccomp.
# Regression gate for R5 — if a future deploy drops either --security-opt,
# check 1 might still pass (Docker's default seccomp doesn't ALWAYS block
# CLONE_NEWUSER — depends on kernel unprivileged_userns_clone sysctl) but
# the formal guarantee is gone.
# -----------------------------------------------------------------------------

SECURITY_OPT_JSON=$(
  docker inspect "$CONTAINER" --format '{{json .HostConfig.SecurityOpt}}' 2>/dev/null || echo 'null'
)

if [[ "$SECURITY_OPT_JSON" != *"$EXPECTED_APPARMOR"* ]]; then
  emit_fail "HostConfig.SecurityOpt missing $EXPECTED_APPARMOR (got: $SECURITY_OPT_JSON)"
else
  emit_pass "HostConfig.SecurityOpt includes $EXPECTED_APPARMOR"
fi

if [[ "$SECURITY_OPT_JSON" != *"$EXPECTED_SECCOMP"* ]]; then
  emit_fail "HostConfig.SecurityOpt missing $EXPECTED_SECCOMP (got: $SECURITY_OPT_JSON)"
else
  emit_pass "HostConfig.SecurityOpt includes $EXPECTED_SECCOMP"
fi

# -----------------------------------------------------------------------------
# Check 3: observe the UID bwrap reports inside the namespace.
# Today this is expected to be a single constant (workspaces share the
# container's UID via namespace mapping). Post-container-per-workspace
# (Phase 4 trigger — "triggered at 5+ concurrent users"), this should
# become per-user. Recording the baseline here means drift is detectable:
# if a future audit reports a DIFFERENT UID than recorded in the runbook
# without a matching architectural change, that is a regression signal.
# -----------------------------------------------------------------------------

OBSERVED_UID=$(
  docker exec "$CONTAINER" bwrap \
    --new-session --die-with-parent \
    --unshare-user --unshare-pid \
    --dev /dev --bind / / \
    -- id -u 2>/dev/null || echo "ERROR"
)

if [[ "$OBSERVED_UID" == "ERROR" ]]; then
  emit_fail "Could not observe UID inside bwrap namespace"
else
  echo "INFO: observed UID inside bwrap namespace = $OBSERVED_UID"
  echo "INFO: baseline today = single namespace-mapped UID (pre-container-per-workspace)"
fi

# -----------------------------------------------------------------------------

echo "--- MU1 bubblewrap UID audit complete — failures=$fail_count ---"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
