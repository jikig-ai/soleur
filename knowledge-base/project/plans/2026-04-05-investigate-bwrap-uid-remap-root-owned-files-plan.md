---
title: "investigate: bwrap sandbox UID remapping and root-owned workspace files"
type: fix
date: 2026-04-05
---

# investigate: bwrap sandbox UID remapping and root-owned workspace files

## Overview

Issue #1546 asks whether bubblewrap's `--uid`/`--gid` flags can preserve the outer UID (1001) for bind-mounted writes, preventing root-owned files in workspace directories. This plan documents the investigation findings and proposes next steps.

## Problem Statement

The `removeWorkspaceDir` helper in `apps/web-platform/server/workspace.ts` implements a two-phase cleanup (direct rm, then chmod + find -delete) as a defensive workaround for root-owned files in workspace directories. The original assumption was that bubblewrap sandbox UID remapping creates these root-owned files.

**Location:** `apps/web-platform/server/agent-runner.ts:347-379` (sandbox config)

## Investigation Findings

### 1. SDK bwrap invocation does NOT use `--uid`, `--gid`, or explicit `--unshare-user`

The Agent SDK v0.2.80 (`cli.js`) builds bwrap arguments as:

- `--new-session --die-with-parent`
- `--unshare-pid`
- `--unshare-net` (when network restriction enabled)
- `--dev /dev --proc /proc`
- `--bind` / `--ro-bind` for filesystem paths

No `--uid`, `--gid`, or `--unshare-user` flags are passed. The SDK does not expose these as configurable options.

### 2. User namespace is auto-created by bwrap

On non-setuid bwrap (which is the case in both local dev and Docker), bwrap **automatically creates a user namespace** when any namespace flag (`--unshare-pid`, `--unshare-net`) is used. This is because creating other namespaces requires `CAP_SYS_ADMIN`, which is available inside a user namespace even for unprivileged processes.

The uid_map inside the sandbox shows `1001 0 1`, meaning sandbox UID 1001 maps to host UID 0 in the parent namespace mapping table. However, this is a namespace-internal mapping -- the kernel resolves writes to the **real UID** of the calling process.

### 3. Bind-mounted writes preserve outer UID (confirmed experimentally)

Experiments on both bare Linux and Docker (`--privileged`) confirm:

| Scenario | Inside sandbox `id` | File owner outside |
|---|---|---|
| Default (no `--uid`/`--gid`) | uid=1001 | uid=1001 |
| `--unshare-user --uid 0 --gid 0` | uid=0 (root) | uid=1001 |
| Nested directories + files | uid=0 (root) inside | uid=1001 outside |

**Conclusion: bwrap user namespace UID remapping does NOT cause root-owned files on bind-mounted writes.** The `--uid`/`--gid` flags only affect the in-sandbox appearance; the host filesystem always records the real UID.

### 4. Docker default seccomp blocks user namespaces

Docker's default seccomp profile blocks `CLONE_NEWUSER` for unprivileged processes (as of Docker 29.x, moby/moby#42441 remains open). This means:

- Without `--privileged` or `--security-opt seccomp=unconfined`, bwrap fails entirely inside Docker
- The production `docker run` command in `ci-deploy.sh` uses no privilege escalation flags
- bwrap may be failing at runtime in production, with the SDK falling back to unsandboxed execution

**This is a separate concern from #1546** but suggests the sandbox may not be active in production at all.

### 5. Actual root causes of root-owned files

Per the learning at `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`, two verified causes exist:

1. **Legacy root-user containers** from before the non-root migration (Dockerfile `USER soleur` added later)
2. **Kernel-specific user namespace behavior** on certain configurations where the mapping is incomplete

The bwrap UID remapping hypothesis from the issue description is not supported by the investigation.

## Proposed Resolution

### Phase 1: Document findings and close #1546

The investigation concludes that `--uid`/`--gid` tuning is **not applicable** because:

1. The SDK does not use `--uid`/`--gid` and does not expose them as configurable options
2. Even with `--uid 0 --gid 0`, bind-mounted writes preserve the outer UID
3. The root-owned files come from legacy containers and/or kernel-specific behavior, not bwrap UID remapping

The existing two-phase cleanup in `removeWorkspaceDir` is the correct defense for the remaining edge cases (legacy containers, kernel quirks).

### Phase 2: Investigate Docker sandbox availability (new issue)

A separate investigation should verify whether bwrap actually works in the production Docker container. If Docker's seccomp profile blocks user namespaces, the entire sandbox layer is silently inactive. This is a **P1 security concern** -- if the sandbox is non-functional, all agent commands run unsandboxed in production.

**Verification steps:**

1. SSH into production server (read-only diagnosis)
2. `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`
3. If this fails with "No permissions to create new namespace," the sandbox is non-functional

**Potential fixes if sandbox is broken (least-privilege first):**

- Use a custom seccomp profile that allows `CLONE_NEWUSER` only (preferred -- minimal privilege escalation)
- Set `kernel.unprivileged_userns_clone=1` on the host (may already be set; no container change needed)
- Add `--cap-add SYS_ADMIN` (grants namespace creation capability -- broader than needed)
- Add `--security-opt seccomp=unconfined` to Docker run (last resort -- disables ALL seccomp protections)

## Acceptance Criteria

- [x] Investigate bubblewrap UID namespace mapping behavior for bind-mounted writes
- [x] Determine if `--uid`/`--gid` tuning can prevent root-owned files
- [ ] Document the limitation (this plan file)
- [ ] If not fixable at this level, document the limitation in the issue and close

## Test Scenarios

- Given a bwrap sandbox with `--unshare-pid --bind /workspace /workspace`, when a file is created inside the sandbox, then the file is owned by the outer UID (1001) outside the sandbox
- Given a bwrap sandbox with `--unshare-user --uid 0 --gid 0 --bind /workspace /workspace`, when a file is created inside the sandbox, then the file is still owned by the outer UID (1001) outside the sandbox
- Given the production Docker container without privilege escalation, when bwrap attempts to create a user namespace, then it either succeeds (kernel allows) or fails with "No permissions" (seccomp blocks)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a pure infrastructure investigation with no architectural changes required. The investigation reveals that the original hypothesis (bwrap UID remapping causes root-owned files) is incorrect. The existing two-phase cleanup is the correct mitigation. A separate issue should be created to verify Docker sandbox functionality in production.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Add `--uid 1001 --gid 1001` to bwrap args | Not applicable | SDK does not expose these flags; also unnecessary since bind-mounted writes already preserve outer UID |
| Modify SDK source to add `--uid`/`--gid` | Rejected | Would require forking the SDK; also solves a non-problem |
| Run container as root | Rejected | Regression; non-root was added deliberately for security |
| Add `CAP_FOWNER` to container | Rejected | Would allow the container to bypass file ownership checks on any file, excessive privilege |

## References

- Issue: #1546
- Related PR: #1540 (source of the investigation request)
- Learning: `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`
- Learning: `knowledge-base/project/learnings/2026-03-29-proc-sandbox-deny-session.md`
- SDK sandbox config: `apps/web-platform/server/agent-runner.ts:347-379`
- Workspace cleanup: `apps/web-platform/server/workspace.ts:removeWorkspaceDir`
- Docker moby/moby#42441: Default seccomp policy for CLONE_NEWUSER (still open)
- bwrap man page: `--uid UID` requires `--unshare-user` or `--userns`
