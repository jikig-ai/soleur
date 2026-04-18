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
# Reject anything that isn't a plausible docker container/name/id identifier
# before interpolating it into docker exec/docker inspect. The audit is
# documented as "safe to run standalone via SSH" — unvalidated env wins make
# that claim untrue.
if [[ ! "$CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "FAIL: CONTAINER env var contains unsupported characters: '$CONTAINER'" >&2
  exit 2
fi
EXPECTED_APPARMOR="apparmor=soleur-bwrap"
EXPECTED_SECCOMP="seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json"

fail_count=0

emit_pass() { echo "PASS: $1"; }
emit_fail() { echo "FAIL: $1" >&2; fail_count=$((fail_count + 1)); }

echo "--- MU1 bubblewrap UID audit --- container=$CONTAINER"

# -----------------------------------------------------------------------------
# Check 1: CLONE_NEWUSER works inside the container + observe the UID bwrap
# reports inside the namespace.
#
# CLONE_NEWUSER is the single syscall the entire sandbox depends on. If
# Docker's default seccomp profile replaces the custom one, CLONE_NEWUSER
# returns EPERM and bwrap exits non-zero before the real workload runs.
#
# The observed UID is the baseline today (single namespace-mapped UID,
# since workspaces share the container's UID pre-container-per-workspace).
# Post-container-per-workspace (Phase 4 trigger — "triggered at 5+
# concurrent users"), this should flip to per-user. Recording it means
# drift is detectable: a future audit reporting a different UID without a
# matching architectural change is a regression signal.
# -----------------------------------------------------------------------------

BWRAP_UID_OUTPUT=$(
  docker exec "$CONTAINER" bwrap \
    --new-session --die-with-parent \
    --unshare-user --unshare-pid \
    --dev /dev --bind / / \
    -- id -u 2>&1
) || BWRAP_UID_EXIT=$?
BWRAP_UID_EXIT="${BWRAP_UID_EXIT:-0}"

if [[ "$BWRAP_UID_EXIT" -ne 0 ]]; then
  emit_fail "CLONE_NEWUSER rejected inside $CONTAINER — sandbox non-functional (output: ${BWRAP_UID_OUTPUT}; see learning docker-seccomp-blocks-bwrap-sandbox-20260405)"
else
  emit_pass "CLONE_NEWUSER works — bwrap can create a user namespace (observed UID=${BWRAP_UID_OUTPUT})"
  echo "INFO: baseline today = single namespace-mapped UID (pre-container-per-workspace)"
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

echo "--- MU1 bubblewrap UID audit complete — failures=$fail_count ---"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
