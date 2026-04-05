---
title: "investigate: verify bwrap sandbox is functional in production Docker container"
type: fix
date: 2026-04-05
---

# Verify bwrap sandbox in production Docker container

## Overview

Docker's default seccomp profile blocks `CLONE_NEWUSER` for unprivileged processes (moby/moby#42441). The production container runs as `USER soleur` (UID 1001) with no privilege escalation flags. This means the bubblewrap (bwrap) sandbox -- Layer 1 of the three-tier defense-in-depth model -- may be silently non-functional, reducing security to application-level checks only.

## Problem Statement

The Agent SDK configures `sandbox: { enabled: true, allowUnsandboxedCommands: false }` in `apps/web-platform/server/agent-runner.ts:367-379`. bwrap requires `CLONE_NEWUSER` to create user namespaces (it calls `clone(CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD)`). Docker's default seccomp profile blocks this with a mask rule: `ALLOW clone WHEN (arg0 & 0x7E020000) == 0` -- meaning any namespace creation flag (including `CLONE_NEWUSER` at `0x10000000`) causes `EPERM`.

If bwrap fails:

- **With `allowUnsandboxedCommands: false`**: Bash tool calls fail entirely (agent sessions partially broken)
- **With silent SDK fallback**: All agent Bash commands run unsandboxed (security boundary gone)

Either outcome is unacceptable. The `/health` endpoint does not check bwrap functionality, so this failure is invisible to monitoring.

## Proposed Solution (Three-Layer Fix)

Investigation revealed three independent blockers, each requiring its own fix:

| Layer | Blocker | Fix |
|-------|---------|-----|
| Seccomp | Default profile blocks `CLONE_NEWUSER` via mask `0x7E020000` | Custom seccomp profile via `daemon.json` adding ALLOW rules for clone/unshare with CLONE_NEWUSER, plus mount/umount/pivot_root |
| AppArmor | Ubuntu 24.04 `docker-default` profile blocks mount inside user namespaces (`EACCES`) | `--security-opt apparmor=unconfined` on `docker run` |
| SDK | `--proc /proc` fails even with seccomp+AppArmor fixed (kernel restricts proc mount in user namespaces inside containers) | `enableWeakerNestedSandbox: true` in agent-runner.ts (SDK skips `--proc /proc`) |

Steps:

1. **[x] Verify** the problem via SSH diagnosis — confirmed: "No permissions to create new namespace"
2. **[x] Create** custom seccomp profile — tested locally, bwrap works with all three fixes
3. **Deploy** seccomp profile as daemon default via `daemon.json` + Terraform provisioner
4. **Update** ci-deploy.sh with `--security-opt apparmor=unconfined` and bwrap canary check
5. **Update** agent-runner.ts with `enableWeakerNestedSandbox: true`
6. **Deploy** via Terraform + Docker image release, then verify

### Seccomp profile approach: Add ALLOW rules (do NOT modify existing mask)

The #1546 investigation proposed changing the clone mask from `0x7E020000` to `0x6E020000`. **This is wrong** -- bwrap passes `CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID` together. With the modified mask, `CLONE_NEWNS` and `CLONE_NEWPID` bits are still in the mask, so the combined clone call is still blocked.

**Correct approach**: Add two new ALLOW rules to a copy of Docker's default seccomp profile. libseccomp compiles multiple rules for the same syscall into OR conditions in the BPF program:

```json
{
  "names": ["clone"],
  "action": "SCMP_ACT_ALLOW",
  "args": [{
    "index": 0,
    "value": 268435456,
    "valueTwo": 268435456,
    "op": "SCMP_CMP_MASKED_EQ"
  }],
  "excludes": { "caps": ["CAP_SYS_ADMIN"] }
}
```

Semantics: ALLOW clone when `(arg0 & CLONE_NEWUSER) == CLONE_NEWUSER`. Same rule for `unshare`. The `excludes` clause means this rule only applies to unprivileged processes (privileged containers with `CAP_SYS_ADMIN` already have unconditional access). Security: namespace creation WITHOUT `CLONE_NEWUSER` is still blocked by the existing mask rule.

### Daemon-level seccomp vs per-container `--security-opt`

**Using `daemon.json`** (chosen approach): Set the custom seccomp profile as Docker's daemon default. This eliminates per-container `--security-opt` flags, cloud-init `write_files` entries, and the deployment ordering race condition. The profile applies to all containers on the host, but the only other container (telegram-bridge) is not harmed by allowing `CLONE_NEWUSER` -- the kernel gates user namespace creation independently.

**Per-container `--security-opt`** (rejected): Requires updating ci-deploy.sh, cloud-init.yml, and adding conditional logic for every `docker run` invocation. The "three-file sync + one" complexity is disproportionate to the fix. If telegram-bridge ever needs different seccomp rules, that is a future problem.

## Technical Considerations

### Attack Surface Enumeration

The security surface is the container's syscall boundary:

- **clone(2) with namespace flags**: Currently blocked by seccomp. Fix allows `CLONE_NEWUSER` only. Other namespace types (`CLONE_NEWNET`, `CLONE_NEWUTS`, `CLONE_NEWIPC`, `CLONE_NEWCGROUP`) remain blocked unless combined with `CLONE_NEWUSER`. This is safe because the kernel processes `CLONE_NEWUSER` first, creating a user namespace. Other namespace types are then created INSIDE the user namespace (where the process has `CAP_SYS_ADMIN` within that namespace), not in the host namespace.
- **unshare(2) with CLONE_NEWUSER**: Currently falls through to `defaultAction: SCMP_ACT_ERRNO` (no explicit rule exists). Fix adds an explicit ALLOW.
- **clone3(2)**: Returns `ENOSYS` for unprivileged processes (default profile). glibc falls back to `clone(2)`. No change needed. Out of scope for testing (default profile behavior, not modified by this fix).
- **Unchecked paths**: None. The seccomp profile applies to ALL processes in the container regardless of how they were spawned.

### Architecture impacts

- **Daemon-level seccomp**: The profile is set in `/etc/docker/daemon.json` as `"seccomp-profile"` key. Docker loads it at daemon startup and applies to all containers that don't specify their own `--security-opt seccomp=`. A single Terraform provisioner handles both the profile file and the daemon.json update.
- **Docker daemon restart**: Updating `daemon.json` requires `systemctl restart docker`, which restarts all running containers. This is a one-time operation during initial deployment. Containers with `--restart unless-stopped` auto-recover.
- **Canary bwrap check**: Added to ci-deploy.sh canary validation as defense-in-depth. Catches regressions if the seccomp profile is removed or Docker daemon config changes.

### Files modified

| File | Change |
|------|--------|
| `apps/web-platform/infra/seccomp-bwrap.json` | **NEW** -- custom seccomp profile (Docker default + CLONE_NEWUSER + mount/umount/pivot_root rules) |
| `apps/web-platform/infra/server.tf` | New `terraform_data` resource to deploy seccomp profile, update daemon.json, restart Docker, and update ci-deploy.sh |
| `apps/web-platform/infra/ci-deploy.sh` | Add `--security-opt apparmor=unconfined` to all `docker run` commands. Add bwrap canary check. |
| `apps/web-platform/server/agent-runner.ts` | Add `enableWeakerNestedSandbox: true` to sandbox config (SDK skips `--proc /proc`) |
| `apps/web-platform/infra/ci-deploy.test.sh` | Update test expectations for `--security-opt` flag and bwrap canary |

### Performance implications

None. Seccomp profiles are compiled to BPF at container start -- no per-syscall overhead beyond the existing default profile. Adding two rules to the BPF program is negligible.

### Security considerations

- Custom seccomp profile is a fork of Docker's default. The Docker Engine version it was derived from is documented in the JSON file header. A tracking issue is created in Phase 2 for periodic review.
- `seccomp=unconfined` is explicitly rejected as a fix -- it disables ALL syscall filtering.
- `--cap-add SYS_ADMIN` is explicitly rejected -- too broad, allows all namespace types plus many other privileged operations.
- The `excludes: { caps: ["CAP_SYS_ADMIN"] }` clause ensures the custom rules do NOT apply to privileged containers (they already have unconditional access via a separate rule).

## Acceptance Criteria

### Functional Requirements

- [ ] SSH diagnosis confirms bwrap is currently broken in production (or confirms it works -- in which case, only the canary check is needed)
- [ ] Custom seccomp profile allows `CLONE_NEWUSER` via `clone(2)` and `unshare(2)` while keeping all other default restrictions
- [ ] Custom rules do NOT apply to privileged containers (`excludes: { caps: ["CAP_SYS_ADMIN"] }`)
- [ ] Profile deployed to server at `/etc/docker/seccomp-profiles/soleur-bwrap.json` via Terraform
- [ ] Docker daemon configured to use custom profile as default (`daemon.json`)
- [ ] ci-deploy.sh canary validation includes bwrap functionality check
- [ ] ci-deploy.test.sh updated with bwrap canary test expectations
- [ ] `bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` succeeds inside the container after fix
- [ ] Other namespace operations are still blocked (e.g., `unshare --net` without `CLONE_NEWUSER` fails)
- [ ] Tracking issue created for periodic seccomp profile review (Docker version drift)

### Non-Functional Requirements

- [ ] No `seccomp=unconfined` or `--cap-add SYS_ADMIN` -- least-privilege only
- [ ] All changes via Terraform -- no manual SSH for state changes
- [ ] Profile documented with source Docker Engine version for future maintenance

## Test Scenarios

### Acceptance Tests

- Given a production container with the custom seccomp profile, when running `docker exec <container> bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`, then the command succeeds with output `uid=0(root) gid=0(root)` (namespace root, maps to host UID 1001)
- Given a production container with the custom seccomp profile, when running `docker exec <container> unshare --net -- id` (no CLONE_NEWUSER), then the command fails with EPERM (other namespace types still blocked)
- Given ci-deploy.sh with bwrap canary check, when deploying a new version and bwrap works, then the canary passes and production swap proceeds
- Given ci-deploy.sh with bwrap canary check, when deploying a new version and bwrap fails, then the canary fails and production keeps the old version

### Integration Verification

- **SSH verify (pre-fix):** `ssh root@<server> docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` -- expect failure with "No permissions to create new namespace"
- **SSH verify (post-fix):** Same command -- expect success with `uid=0(root) gid=0(root)`
- **Negative test:** `ssh root@<server> docker exec soleur-web-platform unshare --net -- id` -- expect failure (CLONE_NEWNET without CLONE_NEWUSER still blocked)
- **Profile validation:** `ssh root@<server> cat /etc/docker/seccomp-profiles/soleur-bwrap.json | python3 -m json.tool` -- expect valid JSON
- **Daemon config:** `ssh root@<server> docker info --format '{{.SecurityOptions}}'` -- expect seccomp profile path in output

## Implementation Phases

### Phase 1: Diagnosis (infrastructure-only, TDD exempt)

1. SSH into production server (read-only per AGENTS.md)
2. Run: `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`
3. Document the exact error output
4. Check `allowUnsandboxedCommands` SDK behavior: query Sentry for bwrap-related errors
5. Get Docker Engine version: `docker version --format '{{.Server.Version}}'`

### Phase 2: Create seccomp profile

1. Download Docker's default seccomp profile matching the server's Docker Engine version
2. Add the two ALLOW rules (clone+CLONE_NEWUSER, unshare+CLONE_NEWUSER) with `excludes: { caps: ["CAP_SYS_ADMIN"] }`
3. Add header comment documenting source Docker Engine version and diff description
4. Save as `apps/web-platform/infra/seccomp-bwrap.json`
5. Test locally: `docker run --security-opt seccomp=seccomp-bwrap.json node:22-slim bash -c "apt-get update && apt-get install -y bubblewrap && bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id"`
6. Negative test: verify `unshare --net` still fails
7. Create tracking issue for periodic seccomp profile review (Docker Engine version drift)

### Phase 3: Update deploy infrastructure

1. Add `terraform_data.docker_seccomp_config` to `server.tf`:
   - Copy `seccomp-bwrap.json` to `/etc/docker/seccomp-profiles/soleur-bwrap.json`
   - Update `/etc/docker/daemon.json` to add `"seccomp-profile"` key pointing to the profile
   - `systemctl restart docker` (containers auto-recover with `--restart unless-stopped`)
   - `triggers_replace` on profile file hash for future updates
2. Update ci-deploy.sh: add bwrap canary check (`docker exec <canary> bwrap ... -- id`) between health check and swap
3. Update ci-deploy.test.sh with bwrap canary test expectations

### Phase 4: Deploy and verify

1. Run `terraform apply` (deploys seccomp profile, updates daemon.json, restarts Docker)
2. Verify bwrap works in the auto-recovered container: `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`
3. Verify negative test: `docker exec soleur-web-platform unshare --net -- id` (should fail)
4. Trigger a deploy to verify canary bwrap check works end-to-end

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Modify clone mask `0x7E020000` to `0x6E020000` | Rejected | bwrap combines flags; CLONE_NEWNS/NEWPID bits still in mask block the combined call |
| Per-container `--security-opt seccomp=<path>` | Rejected | Four-file sync (ci-deploy.sh, cloud-init.yml, server.tf, profile), deployment ordering race, conditional logic in every `docker run` |
| `--cap-add SYS_ADMIN` | Rejected | Too broad -- allows ALL namespace types plus many other privileged operations |
| `--security-opt seccomp=unconfined` | Rejected | Disables ALL syscall filtering -- worse than having no bwrap |
| Host kernel sysctl `kernel.unprivileged_userns_clone=1` | Insufficient alone | Docker seccomp is independent of kernel sysctl; seccomp profile blocks regardless |
| `--privileged` flag | Rejected | Removes ALL security restrictions -- completely unacceptable |

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Docker daemon restart causes brief container downtime | Certain | Containers restart automatically (10-30s gap) | `--restart unless-stopped` handles recovery; schedule during low-traffic window |
| Seccomp profile has a bug (wrong value, JSON syntax) | Low | Docker daemon refuses to start | Local testing before deploy; `terraform apply` rolls back on failure |
| Docker Engine update changes default seccomp profile | Low (over time) | Custom profile diverges from upstream | Document source version; tracking issue for periodic review |
| bwrap actually works already (kernel override) | Possible | No fix needed | Phase 1 diagnosis confirms; if works, only add canary check |
| AppArmor `restrict_unprivileged_userns` blocks CLONE_NEWUSER despite seccomp fix | Low | bwrap still fails | Docker's `docker-default` AppArmor profile allows `userns_create` since Docker 24.0.7 |

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Risk rated HIGH (security), MEDIUM (production stability, deployment complexity). The custom seccomp profile approach is the correct least-privilege fix. Daemon-level deployment via `daemon.json` simplifies the change to a single Terraform provisioner + ci-deploy.sh canary check. Docker restart is a one-time cost. Deployment sequencing is eliminated because the daemon loads the profile at startup.

## Success Metrics

- bwrap functional inside production container (verified via `docker exec`)
- No regression in other namespace blocking (negative test passes)
- Canary deploy includes bwrap validation
- Docker daemon configured with custom seccomp profile as default

## References & Research

### Internal References

- Defense-in-depth learning: `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- CWE-59 symlink learning: `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`
- Agent SDK sandbox config: `apps/web-platform/server/agent-runner.ts:367-379`
- Existing Terraform provisioner pattern: `apps/web-platform/infra/server.tf:47-77` (disk-monitor)
- ci-deploy.sh canary flow: `apps/web-platform/infra/ci-deploy.sh:135-193`
- Investigation: #1546, worktree `feat-bwrap-uid-remap-1546`

### External References

- Docker seccomp default profile: moby/moby repository `profiles/seccomp/`
- User namespace in Docker: moby/moby#42441 (open since 2021)
- `CLONE_NEWUSER` constant: `0x10000000` (268435456 decimal)
- Ubuntu 24.04 AppArmor userns restriction: `kernel.apparmor_restrict_unprivileged_userns=1`

### Related Work

- Parent investigation: #1546
- This issue: #1557
