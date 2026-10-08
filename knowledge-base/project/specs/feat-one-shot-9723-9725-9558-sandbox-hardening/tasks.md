# Tasks: sandbox hardening cluster (#9723, #9725, #9558)

Plan: `knowledge-base/project/plans/2026-10-08-fix-sandbox-hardening-cluster-plan.md`. Every phase is RED-first: failing test rows land before the behavior change, then the change, then GREEN.

## Phase 1: Shim tail-mask (#9723)

- [x] 1.1 Extend `apps/web-platform/test/bwrap-shim.test.ts` with Guard 1 rows: insertion before first `--`; mask positioned after `--args` payload tokens; payload-carried `--` rewrite arm; positional-boundary arm; malformed `--args` fd fail-closed (exit 65 + `bwrap-shim:` marker).
- [x] 1.2 Implement the three arms + fail-closed in `apps/web-platform/infra/bwrap-shim/bwrap`; update the header comment to record the argv-rewrite trust role.
- [x] 1.3 `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` + `apps/web-platform/test/sandbox-isolation.test.ts` FR7: emit the vendor argv shape (tail `--bind /proc /proc`) and run the spawn through the shim via `SOLEUR_BWRAP_REAL`/`SOLEUR_BWRAP_SECCOMP_BPF` overrides so FR7 measures the deployed chain.
- [x] 1.4 `apps/web-platform/test/sandbox-proc-mask-runtime.test.ts`: SDK-chain interception probe — the vendored spawn PATH-resolves the shim and hands it the tail-bind shape; outcome discrimination lives in the unit rows + FR7b + canary `proc_mask` (the vendored `apply-seccomp` re-scopes procfs, so an SDK-level outcome read cannot discriminate on this host). Amended mechanism: `--proc /proc` (pidns-scoped), NOT `--tmpfs` — `apply-seccomp` resolves `/proc/self/fd/N`.

## Phase 2: Canary probe redesign (coupled to Phase 1)

- [x] 2.1 `apps/web-platform/scripts/sandbox-canary.mjs`: replace `fd_census`'s `ls /proc/self/fd` with a procfs-free POSIX fd enumeration; re-derive `fdLimit` for the new enumerator; add `proc_mask` probe (`test -e /proc/self/environ` must fail inside the replayed sandbox).
- [x] 2.2 `apps/web-platform/scripts/sandbox-canary-regression.test.sh`: update the D3 probe-payload assertion to the new enumerator's marker; assert `proc_mask` is wired.
- [x] 2.3 `apps/web-platform/test/sandbox-canary.test.ts`: classifier rows for `proc_mask` (mask present → pass, populated `/proc` → `sandbox_broken`/`proc_mask_defeated`, unparseable/spawn error → `canary_infra_error`).

## Phase 3: Dual-root deny + cutover gate (#9725)

- [x] 3.1 `apps/web-platform/server/workspace-resolver.ts`: export `workspaceTenantDenyRoots()` (deduped raw `WORKSPACES_ROOT` + `WORKTREE_ROOT` roots, flag-independent); keep `getWorkspaceWorktreeRoot` private.
- [x] 3.2 `apps/web-platform/server/agent-runner-sandbox-config.ts`: deny set via the helper; extend the catastrophic-misconfig throw to both roots; `tenant-deny` emit gains per-root `{root, exists}` rows/`gitDataStoreEnabled`/`workspaceEffectiveRoot`/`workspaceUnderEffectiveRoot`; missing-root Sentry arm covers the effective root; update `KNOWN TAIL CAVEAT` and `deniedCount` comments.
- [x] 3.3 `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` + `agent-runner-sandbox-config.test.ts`: Guard 2 matrix rows (WORKTREE_ROOT set/unset × flag on/off; workspace under each root; catastrophic shapes for both roots).
- [x] 3.4 `apps/web-platform/infra/git-data-flag-precheck.sh`: `SANDBOX_DENY_ROOTS` arm (blocking refuse on `FLAG_MODE=flip`, informational otherwise) + `git-data-flag-precheck.test.sh` row.
- [x] 3.5 `.github/workflows/git-data-cutover.yml` `flip_preconditions`: `GIT_DATA_DENY_FLOOR` semver-floor arm (same `ver_le` + `/health` pattern as `live_image_stale`); refusal message names the remedy.
- [x] 3.6 Re-capture `apps/web-platform/infra/sandbox-canary-argv.json` via the creds-gated capture path with `WORKTREE_ROOT=/tmp/soleur-sandbox-canary-worktrees` set in the capture env; fixture pins both deny roots and still ends `--bind /proc /proc`.

## Phase 4: Support credential gate (#9558)

- [x] 4.1 `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: support + connected-repo rows — `generateInstallationToken`, `writeAskpassScriptTo`, `ensureWorkspaceRepoCloned`, `resolveEffectiveInstallationId` not called; `buildAgentSandboxConfig` asserted `allowGithubEgress:false`; egress-posture log carries `persona`. Command-center regressions stay green.
- [x] 4.2 `apps/web-platform/server/cc-dispatcher.ts`: gate `resolveEffectiveInstallationId`, the `ensureWorkspaceRepoCloned`/`consumeDispatchCloneOutcome` block, and the mint under `mode.runRepoLifecycle` (mint additionally `mode.sandboxWrite !== "none"`); add `persona` to the egress-posture `log.info`; serviceTokens fold-in per plan FR3 (flagged inferred — cuttable at review).
- [x] 4.3 Confirm `buildAgentEnv`'s `gitInstallationToken`/askpass args are the only support-visible token channel (grep sweep, record result in PR).

## Phase 5: Docs, ADR/C4, ship hygiene

- [x] 5.1 ADR-075 addendum: dual-root deny + realized `/proc` mask at the shim layer.
- [x] 5.2 ADR-113 addendum: gated set gains clone/install-resolution/mint/askpass/egress; record the serviceTokens decision.
- [x] 5.3 ADR-272 note: `/proc` deny now realized (mechanism no longer incidental).
- [x] 5.4 C4: record the no-impact enumeration in the PR description (no actor/system/container/relationship delta).
- [x] 5.5 New `apps/web-platform/infra/sandbox-hardening-contract.sh` printing `sandbox-hardening-contract:ok` (the plan's `discoverability_test` command).
- [x] 5.6 Changelog entry; PR body `Closes #9723, #9725, #9558`; `npx markdownlint-cli2` clean on plan + tasks.md; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; touched test shards green via the repo's runner selection.
