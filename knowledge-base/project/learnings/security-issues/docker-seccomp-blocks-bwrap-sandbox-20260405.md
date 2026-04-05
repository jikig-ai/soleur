---
module: WebPlatform
date: 2026-04-05
problem_type: security_issue
component: tooling
symptoms:
  - "Docker default seccomp profile blocks CLONE_NEWUSER, disabling bwrap sandbox"
  - "bwrap UID remapping incorrectly blamed for root-owned workspace files"
root_cause: config_error
resolution_type: documentation_update
severity: high
tags: [bubblewrap, seccomp, docker, sandbox, user-namespace, uid-remapping]
---

# Learning: Docker default seccomp profile silently disables bwrap sandbox

## Problem

Investigation into root-owned workspace files (#1546) revealed that bubblewrap UID remapping does NOT cause root-owned files — the kernel always maps writes back to the host UID. However, the investigation uncovered a more critical concern: Docker's default seccomp profile blocks `CLONE_NEWUSER`, which means bwrap's automatic user namespace creation may fail entirely in production containers, silently disabling the entire OS-level sandbox layer.

## Environment

- Module: WebPlatform (agent-runner sandbox config)
- Affected Component: `apps/web-platform/server/agent-runner.ts:347-379` (sandbox config)
- Date: 2026-04-05

## Symptoms

- Root-owned files in workspace directories after agent sessions
- `removeWorkspaceDir` requires two-phase cleanup (rm + chmod + find -delete)
- Production `docker run` in `ci-deploy.sh` uses no `--privileged` or `--security-opt` flags

## What Didn't Work

**Attempted hypothesis:** bwrap `--uid`/`--gid` flags cause root-owned files via incomplete UID mapping back to outer UID.

- **Why it failed:** The Agent SDK does not use `--uid`/`--gid` flags. Even with `--unshare-user --uid 0 --gid 0`, bwrap's user namespace maps writes back to the host UID (1001). Verified experimentally: files created inside sandbox with apparent UID 0 are owned by UID 1001 outside.

## Session Errors

**uid_map interpretation error in planning subagent** — The planning subagent cited uid_map as `1001 0 1` with non-standard column interpretation. In standard `/proc/[pid]/uid_map` format, `1001 0 1` means ns UID 1001 maps to host UID 0 (root), contradicting experimental results. The actual map is `0 1001 1` (ns UID 0 maps to host UID 1001).

- **Recovery:** Caught by architecture-strategist review agent during review phase. Corrected in the plan file.
- **Prevention:** When documenting kernel data formats (uid_map, seccomp profiles, capability sets), verify interpretation against official kernel documentation (`man user_namespaces`, `man capabilities`) rather than inferring from context.

## Solution

The investigation concluded with documentation rather than a code fix:

1. **bwrap UID remapping is NOT the cause** — bind-mounted writes always preserve the outer UID regardless of in-sandbox appearance
2. **Root-owned files come from:** (a) legacy root-user containers before `USER soleur` Dockerfile migration, (b) kernel-specific edge cases
3. **Existing two-phase cleanup is correct** — `removeWorkspaceDir` in `workspace.ts` is the right mitigation
4. **Follow-up #1557 created** for Docker sandbox availability investigation (P1 security concern)

## Why This Works

The root cause of the investigation target (root-owned files) was misidentified. The actual causes are legacy containers and kernel edge cases, both of which the existing two-phase cleanup handles correctly.

The more important finding is the Docker seccomp concern:

1. Docker's default seccomp profile blocks ALL `CLONE_NEW*` flags (mask `0x7E020000`) for unprivileged processes
2. bwrap requires `CLONE_NEWUSER` to create other namespaces (PID, network) without `CAP_SYS_ADMIN`
3. Without `--privileged` or a custom seccomp profile, bwrap fails and the SDK may fall back to unsandboxed execution
4. This means Layer 1 (OS-level sandbox) of the three-tier security model may be entirely inactive in production

The fix (tracked in #1557) is a custom seccomp profile that allows `CLONE_NEWUSER` while keeping other namespace types blocked: change the clone mask from `0x7E020000` to `0x6E020000`.

## Prevention

- When deploying sandboxed applications in Docker, verify that the seccomp profile permits the namespace types the sandbox requires
- Test sandbox functionality inside the actual production container, not just on bare metal
- Add a startup health check that verifies bwrap can create namespaces (e.g., `bwrap --unshare-pid -- /bin/true`)
- When investigating permission issues, verify the hypothesis experimentally before assuming the root cause

## Related Issues

- See also: [canUseTool defense-in-depth](../2026-03-20-canuse-tool-sandbox-defense-in-depth.md) — three-tier security model where bwrap is Layer 1
- See also: [workspace permission denied two-phase cleanup](../runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md) — the defensive workaround for root-owned files
- See also: [proc sandbox deny session](../2026-03-29-proc-sandbox-deny-session.md) — related sandbox behavior
- GitHub: #1546 (this investigation), #1557 (Docker sandbox follow-up)

## Tags

category: security-issues
module: WebPlatform
