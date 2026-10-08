# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-10-08-fix-sandbox-hardening-cluster-plan.md
- Status: complete

### Errors

- Plan initially claimed `apps/web-platform/infra/lb-weight-gate.sh` did not exist; corrected during deepen pass (it exists — ADR-143 D3 gate).
- Planning subagent had no Task/spawn tool, so plan/deepen research fan-out ran inline; all mechanical gates passed and halts recorded.

### Decisions

- #9723 fixed at the bwrap PATH shim (`infra/bwrap-shim/bwrap`): appended `--proc /proc` after the vendor tail bind (NOT `--tmpfs` — the vendored `apply-seccomp` inner command execs through `/proc/self/fd`), fail-closed exit 65 on unresolvable shapes; `fd_census` replay probe redesigned (procfs-free dup-test); `proc_mask` probe keys on host-PID visibility.
- #9725 fixed with unconditional dual-root deny via `workspaceTenantDenyRoots()` exported from `workspace-resolver.ts` covering WORKSPACES_ROOT + WORKTREE_ROOT at every flag state; fixture re-captured in-image (`SANDBOX_CANARY_MODE=capture` on `node:22-slim`) with WORKTREE_ROOT pinned; `SANDBOX_DENY_ROOTS` arm added to `git-data-flag-precheck.sh` + `GIT_DATA_DENY_FLOOR` live-image floor added to `git-data-cutover.yml`.
- #9558 fixed by gating the repo-credential surface (`resolveInstallationId`, `resolveEffectiveInstallationId`, mint, askpass, egress, dispatch-level `reprovisionWorkspaceOnDispatch`) under `mode.runRepoLifecycle` + `mode.sandboxWrite !== "none"`; egress-posture log carries `persona`. serviceTokens deliberately NOT gated (orthogonal third-party keys, egress-closed sandbox — recorded in the ADR-113 addendum).
- Single PR; `brand_survival_threshold: single-user incident`, `requires_cpo_signoff: true`; ADR-075/ADR-113/ADR-272 addenda; C4 no-impact enumeration.

### Components Invoked

- soleur:plan, soleur:deepen-plan, soleur:work, soleur:spec-templates (inline execution)
- gh issue view (#9723, #9725, #9558), gh pr view (#9709), lint-guard-contract.py, markdownlint-cli2, cloud-detect.sh, live bwrap 0.12.0 mechanism tests, in-image canary capture (stubbed model turn; real SDK+config argv)
