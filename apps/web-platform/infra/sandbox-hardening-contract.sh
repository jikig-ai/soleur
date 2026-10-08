#!/usr/bin/env bash
# Local discoverability probe for the sandbox-hardening cluster
# (#9723 vendor tail /proc bind, #9725 WORKTREE_ROOT deny gap, #9558 support
# credential surface).
#
# Prints `sandbox-hardening-contract:ok` when every control is present in the
# tree, and `sandbox-hardening-contract: FAIL <what>` (exit 1) otherwise. It is
# a static invariant probe: it proves the controls are WIRED, not that they
# work; the behavioural proof is the suites each comment names.
#
# Compares with `grep -c` counts, never a negated grep: a pattern that fails to
# compile must not read as "nothing found, all good".
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
app="$root/apps/web-platform"
fail=0

need_file() { # need_file <path>
  if [ ! -f "$1" ]; then
    echo "sandbox-hardening-contract: FAIL missing file ${1#"$root"/}"
    fail=1
    return 1
  fi
}

check() { # check <label> <count> <minimum>
  case "$2" in
    '' | *[!0-9]*)
      echo "sandbox-hardening-contract: FAIL $1 (unreadable count '$2')"
      fail=1
      ;;
    *)
      if [ "$2" -lt "$3" ]; then
        echo "sandbox-hardening-contract: FAIL $1 (found $2, want at least $3)"
        fail=1
      fi
      ;;
  esac
}

# --- #9723: the shim re-masks /proc AFTER the vendor's tail bind ------------
shim="$app/infra/bwrap-shim/bwrap"
if need_file "$shim"; then
  check "shim tail re-mask emits --proc /proc" \
    "$(grep -c -E -- '--proc.*/proc' "$shim" || true)" 1
  check "shim fail-closed marker + exit 65" \
    "$(grep -c 'bwrap-shim:' "$shim" || true)" 1
fi
# Canary probe discriminates on HOST PID visibility, never on an empty /proc
# (the vendored apply-seccomp needs /proc/self/fd to exist).
canary="$app/scripts/sandbox-canary.mjs"
if need_file "$canary"; then
  check "proc_mask probe keys on the canary host pid" \
    "$(grep -c 'proc_mask' "$canary" || true)" 1
fi

# --- #9725: dual-root tenant deny (WORKSPACES_ROOT + WORKTREE_ROOT) ----------
resolver="$app/server/workspace-resolver.ts"
cfg="$app/server/agent-runner-sandbox-config.ts"
if need_file "$resolver"; then
  check "workspaceTenantDenyRoots exported from the resolver" \
    "$(grep -c 'export function workspaceTenantDenyRoots' "$resolver" || true)" 1
  check "worktree root joins the deny root set" \
    "$(grep -c 'getWorkspaceWorktreeRoot' "$resolver" || true)" 1
fi
if need_file "$cfg"; then
  check "sandbox config consumes workspaceTenantDenyRoots" \
    "$(grep -c 'workspaceTenantDenyRoots' "$cfg" || true)" 1
fi
# Committed canary fixture pins the second deny landing.
fixture="$app/infra/sandbox-canary-argv.json"
if need_file "$fixture"; then
  check "fixture carries the worktree-root tmpfs deny" \
    "$(grep -c 'soleur-sandbox-canary-worktrees' "$fixture" || true)" 1
  check "fixture still ends on the vendor tail /proc bind" \
    "$(grep -c '"/proc"' "$fixture" || true)" 2
fi
# Cutover gate refuses a flip onto a pre-deny image.
precheck="$app/infra/git-data-flag-precheck.sh"
wf="$root/.github/workflows/git-data-cutover.yml"
if need_file "$precheck"; then
  check "precheck carries the SANDBOX_DENY_ROOTS arm" \
    "$(grep -c 'SANDBOX_DENY_ROOTS' "$precheck" || true)" 2
fi
if need_file "$wf"; then
  check "workflow carries the GIT_DATA_DENY_FLOOR precondition" \
    "$(grep -c 'GIT_DATA_DENY_FLOOR' "$wf" || true)" 2
fi

# --- #9558: support persona mints/clone/askpass/egress are all gated ----------
cc="$app/server/cc-dispatcher.ts"
if need_file "$cc"; then
  check "installation resolve gated on runRepoLifecycle" \
    "$(grep -c 'mode.runRepoLifecycle' "$cc" || true)" 4
  check "mint + askpass belt on sandboxWrite" \
    "$(grep -c 'sandboxWrite !== "none"' "$cc" || true)" 2
  check "egress posture log carries persona" \
    "$(grep -c 'persona: args.persona' "$cc" || true)" 1
  check "dispatch-level reprovision skipped for support" \
    "$(grep -c 'args.persona !== "support" && runner.hasActiveQuery' "$cc" || true)" 1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "sandbox-hardening-contract:ok"
