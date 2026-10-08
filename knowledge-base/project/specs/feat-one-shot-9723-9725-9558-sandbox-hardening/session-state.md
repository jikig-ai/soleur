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

## Review Phase

- PR: https://github.com/jikig-ai/soleur/pull/9768 (draft)
- Panel: 12 seats at 0d66a280f4 (PANEL_SHA), risk tier `single-user incident` (code class)
- Fix round 1 commit: `171e74fb90` — 9 targeted seats re-verified
- Deferred to synthesis: shim-shadowed-by-real-bwrap boot probe stays report-only (deploy-gate promotion is a separate ops decision); non-/proc procfs dest + non-workflow flag writes documented scope-outs.

### Review findings resolved (fix round 1)

- P0: `dispatchSoleurGo` reprovision `else` arm fired `reprovisionWorkspaceOnDispatch` on every support dispatch → both arms gated on `resolveWorkspaceMode(args.persona).runRepoLifecycle`; dispatch-level test pins it.
- P1: `workspaceTenantDenyRoots()` used the flag-collapsed `getWorkspaceWorktreeRoot()` → now raw `WORKSPACES_ROOT`/`WORKTREE_ROOT` unconditionally (staging + rollback windows stay masked); `"/"` and non-absolute/`..` roots throw; existing roots get realpath aliases.
- P1: shim Arm-B/C could mount-over the mask via trailing outer options — upstream `parse_args_recurse` resumes outer-argv options after an `--args` payload, so the mask always splices at the OUTER setup end (verified bwrap 0.12.0).
- P1: empty/write-only `--args` payload silently re-emitted (mapfile succeeds) → now fails closed exit 65.
- P1: `resolveC4Eligible` + stored `GITHUB_TOKEN` serviceTokens still reachable for support → gated on `runRepoLifecycle` / stripped for `sandboxWrite==="none"`.
- P2: precheck write arm (`FLAG_WRITE_VALUE=true`, any mode) bypassed the deny check → `detect_deny_roots` gates it.
- P2: merged setup lacking `--unshare-pid`/`--unshare-all` → refuse (the mask is decorative without a pidns).
- P2/P3: opt_kind arity table single-sourced; fd-ref scan scoped to command-side tokens; existsSync single-pass emit; `tenantDenyRoots[{root,exists}]` + `gitDataStoreEnabled` + `workspaceEffectiveRoot` + `workspaceUnderEffectiveRoot`; FR7b EACCES degrade; fd_census baseline pinned; contract needles code-shaped; FLOOR=97; docs reconciled.
