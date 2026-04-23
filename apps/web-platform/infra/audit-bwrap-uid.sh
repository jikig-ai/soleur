#!/usr/bin/env bash
# MU1 (Multi-User Readiness Gate item 1) — bubblewrap UID audit.
#
# Verifies that the OS-level sandbox layer in the production container is
# functional AND that the security-opts it depends on are still attached.
#
# Invoke from the MU1 runbook (see
# knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md)
# or wire into CI post-deploy. Safe to run standalone by piping from any
# Soleur worktree (the prod host has no repo checkout by design — see #2606):
#
#     ssh <prod-host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh
#
# Override the container name for canaries:
#
#     ssh <prod-host> "CONTAINER=soleur-web-platform-canary bash -s" \
#         < apps/web-platform/infra/audit-bwrap-uid.sh
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
# Path to the on-host seccomp profile used as the hash-compare source of
# truth. Overridable for tests; defaults to the prod deploy path bind-mounted
# by `ci-deploy.sh`.
EXPECTED_SECCOMP_PATH="${EXPECTED_SECCOMP_PATH:-/etc/docker/seccomp-profiles/soleur-bwrap.json}"

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
#
# Seccomp: Docker resolves `--security-opt seccomp=<path>` to the inlined
# JSON at container-create time, so the literal path does NOT survive into
# HostConfig.SecurityOpt. We hash-compare the inlined JSON against the
# on-host file; jq -cS canonicalizes whitespace + key order so byte-equal
# content hashes identically.
# -----------------------------------------------------------------------------

# Iterate each SecurityOpt element on its own line. `|| true` so strict-mode
# does not abort the whole script when docker errors — we want a clear FAIL.
SECURITY_OPT_ENTRIES=$(
  docker inspect "$CONTAINER" \
    --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' 2>/dev/null \
    || true
)

if printf '%s\n' "$SECURITY_OPT_ENTRIES" | grep -qF "$EXPECTED_APPARMOR"; then
  emit_pass "HostConfig.SecurityOpt includes $EXPECTED_APPARMOR"
else
  emit_fail "HostConfig.SecurityOpt missing $EXPECTED_APPARMOR (got: $SECURITY_OPT_ENTRIES)"
fi

SECCOMP_ENTRY=$(printf '%s\n' "$SECURITY_OPT_ENTRIES" | sed -n 's/^seccomp=//p' | head -n1)

if [[ -z "$SECCOMP_ENTRY" ]]; then
  emit_fail "HostConfig.SecurityOpt has no seccomp= entry — custom profile not attached (got: $SECURITY_OPT_ENTRIES)"
elif [[ "$SECCOMP_ENTRY" == /* ]]; then
  # A literal path surviving into HostConfig means Docker did not resolve
  # the --security-opt seccomp=<path> flag at create time (missing file or
  # old docker version). Drift either way.
  emit_fail "seccomp entry is a literal path, not inlined JSON — Docker did not resolve --security-opt (got: $SECCOMP_ENTRY)"
elif [[ ! -r "$EXPECTED_SECCOMP_PATH" ]]; then
  emit_fail "On-host seccomp profile missing at $EXPECTED_SECCOMP_PATH — deploy state incoherent"
else
  # jq -cS = --compact-output --sort-keys. Canonical form → byte-stable hash.
  # `|| true` on both pipes: under `set -euo pipefail`, a jq failure would
  # abort the script before the "not valid JSON" branch can emit. We want
  # malformed JSON to land in an explicit FAIL, not a silent strict-mode exit.
  FILE_HASH=$(jq -cS . "$EXPECTED_SECCOMP_PATH" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
  INLINED_HASH=$(printf '%s' "$SECCOMP_ENTRY" | jq -cS . 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
  EMPTY_HASH=$(printf '' | sha256sum | cut -d' ' -f1)

  if [[ -z "$FILE_HASH" || "$FILE_HASH" == "$EMPTY_HASH" ]]; then
    emit_fail "On-host seccomp profile at $EXPECTED_SECCOMP_PATH is not valid JSON"
  elif [[ "$INLINED_HASH" != "$FILE_HASH" ]]; then
    emit_fail "seccomp drift: inlined profile sha256=${INLINED_HASH:0:12} != on-host sha256=${FILE_HASH:0:12}"
  else
    emit_pass "HostConfig.SecurityOpt seccomp matches on-host profile (sha256=${FILE_HASH:0:12})"
  fi
fi

# -----------------------------------------------------------------------------

echo "--- MU1 bubblewrap UID audit complete — failures=$fail_count ---"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
