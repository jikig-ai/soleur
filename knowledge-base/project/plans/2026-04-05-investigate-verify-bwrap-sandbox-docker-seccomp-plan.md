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

## Proposed Solution

1. **Verify** the problem exists via read-only SSH diagnosis
2. **Create** a custom seccomp profile that adds ALLOW rules for `clone` and `unshare` with `CLONE_NEWUSER`
3. **Deploy** via Terraform file provisioner (same pattern as `disk_monitor_install` in `server.tf:47-77`)
4. **Update** `ci-deploy.sh` and `cloud-init.yml` to use `--security-opt seccomp=<path>`
5. **Add** bwrap canary health check to `ci-deploy.sh`
6. **Verify** bwrap works inside the container after deployment

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

Semantics: ALLOW clone when `(arg0 & CLONE_NEWUSER) == CLONE_NEWUSER`. Same rule for `unshare`. Security: namespace creation WITHOUT `CLONE_NEWUSER` is still blocked by the existing mask rule.

## Technical Considerations

### Attack Surface Enumeration

The security surface is the container's syscall boundary:

- **clone(2) with namespace flags**: Currently blocked by seccomp. Fix allows `CLONE_NEWUSER` only. Other namespace types (`CLONE_NEWNET`, `CLONE_NEWUTS`, `CLONE_NEWIPC`, `CLONE_NEWCGROUP`) remain blocked unless combined with `CLONE_NEWUSER`. This is safe because the kernel processes `CLONE_NEWUSER` first, creating a user namespace. Other namespace types are then created INSIDE the user namespace (where the process has `CAP_SYS_ADMIN` within that namespace), not in the host namespace.
- **unshare(2) with CLONE_NEWUSER**: Currently falls through to `defaultAction: SCMP_ACT_ERRNO` (no explicit rule exists). Fix adds an explicit ALLOW.
- **clone3(2)**: Returns `ENOSYS` for unprivileged processes (default profile). glibc falls back to `clone(2)`. No change needed.
- **Unchecked paths**: None. The seccomp profile applies to ALL processes in the container regardless of how they were spawned.

### Architecture impacts

- **ci-deploy.sh update mechanism**: The deploy script on the server was written by cloud-init at provision time and is never updated. A new `terraform_data` resource is needed to copy updated ci-deploy.sh to the existing server (same pattern as `disk_monitor_install`).
- **Three-file sync + one**: ci-deploy.sh, cloud-init.yml, Dockerfile, AND the seccomp profile must stay in lockstep.
- **Graceful degradation**: ci-deploy.sh checks if seccomp profile exists before adding `--security-opt`. This eliminates the Terraform-apply-before-deploy race condition.
- **Canary bwrap check**: Added to canary validation (not health endpoint) to avoid Docker restart loops.

### Deployment ordering

1. Merge PR to main
2. Run `terraform apply` (copies seccomp profile + ci-deploy.sh to server)
3. Release workflow fires webhook → updated ci-deploy.sh uses seccomp profile

If terraform apply hasn't run when a deploy fires, graceful degradation means the old ci-deploy.sh runs without `--security-opt` (same as today). The fix takes effect on the NEXT deploy after terraform apply.

### Files modified

| File | Change |
|------|--------|
| `apps/web-platform/infra/seccomp-bwrap.json` | **NEW** -- custom seccomp profile (Docker default + CLONE_NEWUSER rules) |
| `apps/web-platform/infra/ci-deploy.sh` | Add `--security-opt seccomp=` to canary + production `docker run`. Add bwrap canary check. Graceful degradation if profile missing. |
| `apps/web-platform/infra/cloud-init.yml` | Write seccomp profile via `write_files`. Add `--security-opt` to initial `docker run`. |
| `apps/web-platform/infra/server.tf` | New `terraform_data` resources for seccomp profile and ci-deploy.sh deployment to existing server. New `templatefile` variable for seccomp profile. |
| `apps/web-platform/infra/ci-deploy.test.sh` | Update mock docker expectations for `--security-opt` flag. Add bwrap canary test. |

### Performance implications

None. Seccomp profiles are compiled to BPF at container start -- no per-syscall overhead beyond the existing default profile. Adding two rules to the BPF program is negligible.

### Security considerations

- Custom seccomp profile is a fork of Docker's default. Must document the Docker Engine version it was derived from and create a tracking issue for periodic review.
- `seccomp=unconfined` is explicitly rejected as a fix -- it disables ALL syscall filtering.
- `--cap-add SYS_ADMIN` is explicitly rejected -- too broad, allows all namespace types plus many other privileged operations.

## Acceptance Criteria

### Functional Requirements

- [ ] SSH diagnosis confirms bwrap is currently broken in production (or confirms it works -- in which case, only the health check is needed)
- [ ] Custom seccomp profile allows `CLONE_NEWUSER` via `clone(2)` and `unshare(2)` while keeping all other default restrictions
- [ ] Profile deployed to server at `/etc/docker/seccomp-profiles/soleur-web-platform.json` via Terraform file provisioner
- [ ] ci-deploy.sh uses `--security-opt seccomp=<path>` for both canary and production containers (graceful fallback if file missing)
- [ ] cloud-init.yml writes seccomp profile via `write_files` AND references it in initial `docker run`
- [ ] ci-deploy.sh canary validation includes bwrap functionality check
- [ ] ci-deploy.sh on existing server is updated via new `terraform_data` provisioner
- [ ] ci-deploy.test.sh updated with mock expectations for `--security-opt` flag
- [ ] `bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` succeeds inside the container after fix
- [ ] Other namespace operations are still blocked (e.g., `unshare --net` without `CLONE_NEWUSER` fails)

### Non-Functional Requirements

- [ ] No `seccomp=unconfined` or `--cap-add SYS_ADMIN` -- least-privilege only
- [ ] All changes via Terraform -- no manual SSH for state changes
- [ ] Profile documented with source Docker Engine version for future maintenance

## Test Scenarios

### Acceptance Tests

- Given a production container with the custom seccomp profile, when running `docker exec <container> bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`, then the command succeeds with output `uid=0(root) gid=0(root)` (namespace root, maps to host UID 1001)
- Given a production container with the custom seccomp profile, when running `docker exec <container> unshare --net -- id` (no CLONE_NEWUSER), then the command fails with EPERM (other namespace types still blocked)
- Given ci-deploy.sh with the seccomp profile, when deploying a new version, then the canary runs with `--security-opt seccomp=<path>` and the bwrap canary check passes before swap
- Given ci-deploy.sh without the seccomp profile on disk, when deploying a new version, then the canary runs WITHOUT `--security-opt` (graceful degradation, no deploy failure)

### Integration Verification

- **SSH verify (pre-fix):** `ssh root@<server> docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id` -- expect failure with "No permissions to create new namespace"
- **SSH verify (post-fix):** Same command -- expect success with `uid=0(root) gid=0(root)`
- **Negative test:** `ssh root@<server> docker exec soleur-web-platform unshare --net -- id` -- expect failure (CLONE_NEWNET without CLONE_NEWUSER still blocked)
- **Profile validation:** `ssh root@<server> cat /etc/docker/seccomp-profiles/soleur-web-platform.json | python3 -m json.tool` -- expect valid JSON

## Implementation Phases

### Phase 1: Diagnosis (infrastructure-only, TDD exempt)

1. SSH into production server (read-only per AGENTS.md)
2. Run: `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`
3. Document the exact error output
4. Check `allowUnsandboxedCommands` SDK behavior: query Sentry for bwrap-related errors

### Phase 2: Create seccomp profile

1. Download Docker's default seccomp profile for the Docker Engine version on the server
2. Add the two ALLOW rules (clone+CLONE_NEWUSER, unshare+CLONE_NEWUSER)
3. Save as `apps/web-platform/infra/seccomp-bwrap.json`
4. Test locally: `docker run --security-opt seccomp=seccomp-bwrap.json node:22-slim bash -c "apt-get update && apt-get install -y bubblewrap && bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id"`
5. Negative test: verify `unshare --net` still fails

### Phase 3: Update deploy infrastructure

1. Add `terraform_data.seccomp_profile_install` to `server.tf` (file provisioner)
2. Add `terraform_data.ci_deploy_update` to `server.tf` (file provisioner for ci-deploy.sh)
3. Update ci-deploy.sh:
   - Graceful seccomp detection: `if [[ -f "$SECCOMP_PROFILE" ]]; then SECCOMP_OPT="--security-opt seccomp=$SECCOMP_PROFILE"; fi`
   - Add `$SECCOMP_OPT` to canary and production `docker run`
   - Add bwrap canary check between health check and swap
4. Update cloud-init.yml:
   - Add seccomp profile to `write_files` (base64-encoded via `templatefile`)
   - Add `--security-opt seccomp=<path>` to initial `docker run`
   - Add seccomp profile variable to `templatefile()` call in server.tf
5. Update ci-deploy.test.sh with new mock expectations

### Phase 4: Deploy and verify

1. Run `terraform apply` (deploys seccomp profile + updated ci-deploy.sh to server)
2. Trigger a deploy (or wait for the PR merge release)
3. Verify bwrap works: `docker exec soleur-web-platform bwrap --new-session --die-with-parent --unshare-pid --dev /dev --proc /proc --bind / / -- id`
4. Verify negative test: `docker exec soleur-web-platform unshare --net -- id` (should fail)

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Modify clone mask `0x7E020000` → `0x6E020000` | Rejected | bwrap combines flags; CLONE_NEWNS/NEWPID bits still in mask block the combined call |
| `--cap-add SYS_ADMIN` | Rejected | Too broad -- allows ALL namespace types plus many other privileged operations |
| `--security-opt seccomp=unconfined` | Rejected | Disables ALL syscall filtering -- worse than having no bwrap |
| Host kernel sysctl `kernel.unprivileged_userns_clone=1` | Insufficient alone | Docker seccomp is independent of kernel sysctl; seccomp profile blocks regardless |
| Docker daemon-level seccomp profile (`daemon.json`) | Considered | Simpler (no per-container flags), but applies to ALL containers on host including telegram-bridge. Per-container is more surgical. |
| `--privileged` flag | Rejected | Removes ALL security restrictions -- completely unacceptable |

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Seccomp profile has a bug (wrong value, JSON syntax) | Low | Canary deploy fails, rollback to old container | Local testing before deploy; canary catches failures |
| Terraform apply runs after CI deploy | Medium | One deploy runs without seccomp (same as today) | Graceful degradation in ci-deploy.sh; fix takes effect on next deploy |
| Docker Engine update changes default seccomp profile | Low (over time) | Custom profile diverges from upstream | Document source version; tracking issue for periodic review |
| bwrap actually works already (kernel override) | Possible | No fix needed | Phase 1 diagnosis confirms; if works, only add health check |
| AppArmor `restrict_unprivileged_userns` blocks CLONE_NEWUSER despite seccomp fix | Low | bwrap still fails | Docker's `docker-default` AppArmor profile allows `userns_create` since Docker 24.0.7 |

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Risk rated HIGH (security), MEDIUM (production stability, deployment complexity). The custom seccomp profile approach is the correct least-privilege fix. Critical gap identified: ci-deploy.sh update mechanism must be added via `terraform_data` provisioner. The `ignore_changes` on `user_data` means the existing server never gets cloud-init updates -- all changes to the running server must go through Terraform provisioners. Deployment sequencing (terraform apply before CI deploy) addressed by graceful degradation.

## Success Metrics

- bwrap functional inside production container (verified via `docker exec`)
- No regression in other namespace blocking (negative test passes)
- Canary deploy includes bwrap validation
- All three deployment paths (canary, production, new server provisioning) use the custom seccomp profile

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
