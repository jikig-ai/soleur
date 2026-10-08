# Tasks: sandbox hardening cluster (#9723, #9725, #9558)

Plan: `knowledge-base/project/plans/2026-10-08-fix-sandbox-hardening-cluster-plan.md`. Every phase is RED-first: failing test rows land before the behavior change, then the change, then GREEN.

## Phase 1: Shim tail-mask (#9723)

- [ ] 1.1 Extend `apps/web-platform/test/bwrap-shim.test.ts` with Guard 1 rows: insertion before first `--`; mask positioned after `--args` payload tokens; payload-carried `--` rewrite arm; positional-boundary arm; malformed `--args` fd fail-closed (exit 65 + `bwrap-shim:` marker).
- [ ] 1.2 Implement the three arms + fail-closed in `apps/web-platform/infra/bwrap-shim/bwrap`; update the header comment to record the argv-rewrite trust role.
- [ ] 1.3 `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` + `apps/web-platform/test/sandbox-isolation.test.ts` FR7: emit the vendor argv shape (tail `--bind /proc /proc`) and run the spawn through the shim via `SOLEUR_BWRAP_REAL`/`SOLEUR_BWRAP_SECCOMP_BPF` overrides so FR7 measures the deployed chain.
- [ ] 1.4 `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts` (or sibling `sandbox-proc-mask-runtime.test.ts`): two-arm outcome probe — control (shim bypassed) sees real `/proc`; treatment (shim on PATH) sees empty `/proc`. Outcome claim only, no mechanism.

## Phase 2: Canary probe redesign (coupled to Phase 1)

- [ ] 2.1 `apps/web-platform/scripts/sandbox-canary.mjs`: replace `fd_census`'s `ls /proc/self/fd` with a procfs-free POSIX fd enumeration; re-derive `fdLimit` for the new enumerator; add `proc_mask` probe (`test -e /proc/self/environ` must fail inside the replayed sandbox).
- [ ] 2.2 `apps/web-platform/scripts/sandbox-canary-regression.test.sh`: update the D3 probe-payload assertion to the new enumerator's marker; assert `proc_mask` is wired.
- [ ] 2.3 `apps/web-platform/test/sandbox-canary.test.ts`: classifier rows for `proc_mask` (mask present → pass, populated `/proc` → `sandbox_broken`/`proc_mask_bypass`, unparseable/spawn error → `canary_infra_error`).

## Phase 3: Dual-root deny + cutover gate (#9725)

- [ ] 3.1 `apps/web-platform/server/workspace-resolver.ts`: export `workspaceTenantDenyRoots()` (deduped raw `WORKSPACES_ROOT` + `WORKTREE_ROOT` roots, flag-independent); keep `getWorkspaceWorktreeRoot` private.
- [ ] 3.2 `apps/web-platform/server/agent-runner-sandbox-config.ts`: deny set via the helper; extend the catastrophic-misconfig throw to both roots; `tenant-deny` emit gains `worktreeRoot`/`gitDataStoreEnabled`/`worktreeRootExists`/`workspaceUnderEffectiveRoot`; missing-root Sentry arm covers the effective root; update `KNOWN TAIL CAVEAT` and `deniedCount` comments.
- [ ] 3.3 `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` + `agent-runner-sandbox-config.test.ts`: Guard 2 matrix rows (WORKTREE_ROOT set/unset × flag on/off; workspace under each root; catastrophic shapes for both roots).
- [ ] 3.4 `apps/web-platform/infra/git-data-flag-precheck.sh`: `SANDBOX_DENY_ROOTS` arm (blocking refuse on `FLAG_MODE=flip`, informational otherwise) + `git-data-flag-precheck.test.sh` row.
- [ ] 3.5 `.github/workflows/git-data-cutover.yml` `flip_preconditions`: `GIT_DATA_DENY_FLOOR` semver-floor arm (same `ver_le` + `/health` pattern as `live_image_stale`); refusal message names the remedy.
- [ ] 3.6 Re-capture `apps/web-platform/infra/sandbox-canary-argv.json` via the creds-gated capture path with `WORKTREE_ROOT=/tmp/soleur-sandbox-canary-worktrees` set in the capture env; fixture pins both deny roots and still ends `--bind /proc /proc`.

## Phase 4: Support credential gate (#9558)

- [ ] 4.1 `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: support + connected-repo rows — `generateInstallationToken`, `writeAskpassScriptTo`, `ensureWorkspaceRepoCloned`, `resolveEffectiveInstallationId` not called; `buildAgentSandboxConfig` asserted `allowGithubEgress:false`; egress-posture log carries `persona`. Command-center regressions stay green.
- [ ] 4.2 `apps/web-platform/server/cc-dispatcher.ts`: gate `resolveEffectiveInstallationId`, the `ensureWorkspaceRepoCloned`/`consumeDispatchCloneOutcome` block, and the mint under `mode.runRepoLifecycle` (mint additionally `mode.sandboxWrite !== "none"`); add `persona` to the egress-posture `log.info`; serviceTokens fold-in per plan FR3 (flagged inferred — cuttable at review).
- [ ] 4.3 Confirm `buildAgentEnv`'s `gitInstallationToken`/askpass args are the only support-visible token channel (grep sweep, record result in PR).

## Phase 5: Docs, ADR/C4, ship hygiene

- [ ] 5.1 ADR-075 addendum: dual-root deny + realized `/proc` mask at the shim layer.
- [ ] 5.2 ADR-113 addendum: gated set gains clone/install-resolution/mint/askpass/egress; record the serviceTokens decision.
- [ ] 5.3 ADR-272 note: `/proc` deny now realized (mechanism no longer incidental).
- [ ] 5.4 C4: record the no-impact enumeration in the PR description (no actor/system/container/relationship delta).
- [ ] 5.5 New `apps/web-platform/infra/sandbox-hardening-contract.sh` printing `sandbox-hardening-contract:ok` (the plan's `discoverability_test` command).
- [ ] 5.6 Changelog entry; PR body `Closes #9723, #9725, #9558`; `npx markdownlint-cli2` clean on plan + tasks.md; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; touched test shards green via the repo's runner selection.
