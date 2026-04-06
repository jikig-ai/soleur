---
module: web-platform
date: 2026-04-05
problem_type: security_issue
component: tooling
symptoms:
  - "bwrap: No permissions to create new namespace"
  - "bwrap: Failed to make / slave: Permission denied"
  - "bwrap: Can't mount proc on /newroot/proc: Operation not permitted"
root_cause: config_error
resolution_type: config_change
severity: critical
tags: [bwrap, bubblewrap, seccomp, apparmor, docker, user-namespaces, sandbox, clone-newuser]
synced_to: [work]
---

# Troubleshooting: bwrap sandbox non-functional in Docker container (three-layer fix)

## Problem

The bubblewrap (bwrap) OS-level sandbox — Layer 1 of the three-tier defense-in-depth model — was completely non-functional inside the production Docker container. Three independent blockers at different system layers prevented bwrap from creating user namespaces and performing mount operations.

## Environment

- Module: web-platform (agent-runner.ts, ci-deploy.sh, server.tf)
- Docker Engine: 29.3.0
- Host OS: Ubuntu 24.04
- Container base: node:22-slim (Debian)
- Container user: soleur (UID 1001, non-root)
- Date: 2026-04-05

## Symptoms

- `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` fails with "No permissions to create new namespace"
- Agent SDK configured with `sandbox: { enabled: true, allowUnsandboxedCommands: false }` — Bash tool calls likely fail silently or error
- `/health` endpoint does not check bwrap functionality — failure is invisible to monitoring

## What Didn't Work

**Attempted: Modify clone mask from 0x7E020000 to 0x6E020000**

- Why it failed: bwrap passes `CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID` combined in a single `clone()` call. Removing only the `CLONE_NEWUSER` bit (0x10000000) from the deny mask still blocks the combined call because `CLONE_NEWNS` (0x00020000) and `CLONE_NEWPID` (0x20000000) bits are still in the mask.

**Attempted: Custom seccomp profile with CLONE_NEWUSER only**

- Why it failed: Seccomp was only one of three blockers. Even with CLONE_NEWUSER allowed, bwrap failed with "Failed to make / slave: Permission denied" (EACCES from AppArmor).

**Attempted: Custom seccomp + apparmor=unconfined**

- Why it failed: `--proc /proc` still failed with "Can't mount proc on /newroot/proc: Operation not permitted". Docker's masked /proc paths prevent proc mounting inside user namespaces.

## Session Errors

**Plan subagent hit rate limit**

- **Recovery:** Fell back to inline planning (no compaction benefit but pipeline continued)
- **Prevention:** Rate limits are external — no prevention possible. The fallback path works correctly.

**Sentry API returned 404 for bwrap error search**

- **Recovery:** Skipped Sentry check — not critical for diagnosis since SSH confirmed the problem directly.
- **Prevention:** Verify Sentry org/project slugs via `gh api` or Doppler before constructing API URLs.

**CWD confusion during git commit**

- **Recovery:** Changed to worktree root with explicit `cd` before `git add`.
- **Prevention:** Always use absolute paths or verify `pwd` before git operations in worktrees. The AGENTS.md rule "Run `pwd` before every file write or git command" covers this.

**Test mock `seq` function broken by combined mock pattern**

- **Recovery:** Split combined `for m in sudo chown seq flock` mock into individual mocks, giving `seq` its own script that echoes "1".
- **Prevention:** When writing shell test mocks, never combine tools with different output requirements into a single mock script. Each mock should replicate the minimum behavior of the tool it replaces.

**Three independent blockers discovered (not just one)**

- **Recovery:** Iterative testing — each fix revealed the next blocker. Local Docker testing with `strace` identified each layer.
- **Prevention:** When fixing syscall-level issues in Docker containers, test with `--privileged` first to establish a working baseline, then remove privileges one at a time to identify which layer blocks each operation.

**Docker seccomp `includes.caps` is compile-time, not runtime**

- **Recovery:** Added mount/umount/pivot_root as unconditional ALLOW rules (not gated by CAP_SYS_ADMIN).
- **Prevention:** Docker's seccomp profile `includes`/`excludes` fields are evaluated by the Docker daemon when building the BPF filter, NOT at syscall time. A process gaining CAP_SYS_ADMIN inside a user namespace does NOT gain access to CAP_SYS_ADMIN-gated seccomp rules because the BPF was compiled without them.

**Initial plan proposed daemon.json-only approach**

- **Recovery:** Architecture review identified that per-container `--security-opt` is simpler and avoids Docker restart.
- **Prevention:** When multiple `--security-opt` flags are needed per-container, keep them all per-container rather than mixing daemon-level and per-container approaches.

## Solution

Three independent fixes at different system layers:

**1. Custom seccomp profile (Docker daemon default)**

Added 4 rules to Docker's default seccomp profile:

```json
// Rule: Allow mount/umount/pivot_root unconditionally (bwrap needs these inside user namespaces)
{"names": ["mount", "umount", "umount2", "pivot_root"], "action": "SCMP_ACT_ALLOW"}

// Rule: Allow clone with CLONE_NEWUSER
{"names": ["clone"], "action": "SCMP_ACT_ALLOW",
 "args": [{"index": 0, "value": 268435456, "valueTwo": 268435456, "op": "SCMP_CMP_MASKED_EQ"}],
 "excludes": {"caps": ["CAP_SYS_ADMIN"]}}

// Rule: Allow unshare with CLONE_NEWUSER (same pattern)
// Rule: s390 variant for clone (arg index 1 instead of 0)
```

**2. AppArmor unconfined**

```bash
docker run --security-opt apparmor=unconfined ...
```

Ubuntu 24.04's `docker-default` AppArmor profile blocks `mount()` inside user namespaces. `apparmor=unconfined` removes this restriction.

**3. SDK enableWeakerNestedSandbox**

```typescript
sandbox: {
  enabled: true,
  enableWeakerNestedSandbox: true, // skips --proc /proc
  // ...
}
```

Docker containers cannot mount proc inside user namespaces (kernel restriction on masked /proc paths). The SDK's `enableWeakerNestedSandbox` flag skips `--proc /proc`. This is safe because `/proc` is already in `denyRead`.

**4. Bwrap canary check in ci-deploy.sh**

```bash
if ! docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true 2>&1; then
  echo "Canary sandbox check failed, rolling back..."
  exit 1
fi
```

## Why This Works

1. **Seccomp layer**: The `SCMP_CMP_MASKED_EQ` rule fires when `CLONE_NEWUSER` (0x10000000) is among the flags, regardless of what other flags are combined. libseccomp OR's multiple rules for the same syscall in the BPF program, so the new ALLOW rule coexists with the existing deny-mask rule. Namespace creation WITHOUT `CLONE_NEWUSER` is still blocked.

2. **AppArmor layer**: Docker's `docker-default` AppArmor profile was designed before user namespaces in containers were common. It blocks mount operations that bwrap needs inside user namespaces. Disabling AppArmor is acceptable because bwrap itself provides equivalent MAC-like isolation for agent processes.

3. **proc mount**: The kernel restricts proc mounting inside user namespaces within Docker containers because Docker masks certain `/proc` paths for security. The SDK's weaker sandbox mode skips proc mounting, relying on the existing `denyRead: ["/proc"]` for file-level protection.

## Prevention

- When deploying applications that use Linux namespaces (bwrap, Flatpak, toolbox) inside Docker containers, test with `--privileged` first, then remove privileges one at a time to identify blockers.
- Docker's default seccomp profile `includes.caps` is compile-time, not runtime. A process gaining capabilities inside a user namespace does NOT gain access to capability-gated seccomp rules.
- Ubuntu 24.04+ has `kernel.apparmor_restrict_unprivileged_userns=1` — Docker's default AppArmor profile restricts mount inside user namespaces. Plan for `apparmor=unconfined` or a custom profile.
- The Claude Agent SDK's `enableWeakerNestedSandbox` flag is the intended workaround for Docker containers where proc mounting fails.
- Always add a runtime verification for security features (like the bwrap canary check) — silent degradation is worse than a noisy failure.

## Related Issues

- Parent investigation: #1546
- This issue: #1557
- Tracking: #1568 (periodic seccomp profile review)
- Review: #1569 (move seccomp to per-container), #1570 (custom AppArmor profile)
- Defense-in-depth learning: `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- Symlink escape learning: `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`
