---
lane: cross-domain
plan: knowledge-base/project/plans/2026-10-07-fix-vendored-sdk-bwrap-argv-reorder-plan.md
issue: 5862
---

# tasks.md — feat-one-shot-5862-bwrap-argv-reorder (#5862)

Phases mirror the plan's Implementation Phases; AC ids in `[ ]` items map to
the plan's `## Acceptance Criteria`.

## Phase 1 — Failing tests (contract first)

- [ ] T1.1 Rewrite the filesystem assertions in `apps/web-platform/test/agent-runner-helpers.test.ts`: `denyRead` equals exactly `[workspacesRoot(), c4StagingRoot, "/proc"]` (+ `denyReadExtra` when passed); `allowWrite === [own]`; `allowRead` absent when not readOnly, `[own]` when readOnly. Assert the set is unchanged when sibling dirs exist under a stubbed `WORKSPACES_ROOT`. (AC1, AC3)
- [ ] T1.2 `git mv apps/web-platform/test/agent-sandbox-sibling-deny.test.ts apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` and rewrite: constant-deny contract, `enumerateSiblingDenyPaths` not exported, parent-cover (not per-entry) semantics for present/future siblings. (AC2)
- [ ] T1.3 Add the ordering pin to `apps/web-platform/test/sandbox-canary.test.ts` per the plan's Guard Contract (covering `--tmpfs` precedes a ws restore `--bind`; absence of a covering deny fails; implement the 5-row mutation matrix as table-driven cases). Update the committed-fixture census for the new literal root tmpfs + prepDirs membership. (AC5, AC6)
- [ ] T1.4 Add the TOCTOU regression case to `apps/web-platform/test/sandbox-isolation.test.ts`: create a sibling dir on the host while a sandboxed child lives; assert it stays unreadable inside (direct-bwrap layer via `spawnBwrap`'s tmpfs+re-bind shape). (AC7)
- [ ] T1.5 `cd apps/web-platform && npx vitest run test/agent-runner-helpers.test.ts test/agent-sandbox-tenant-deny.test.ts test/sandbox-canary.test.ts` — confirm the new/updated assertions are RED for the right reason.

## Phase 2 — Config rewrite

- [ ] T2.1 Rewrite `filesystem` in `apps/web-platform/server/agent-runner-sandbox-config.ts › buildAgentSandboxConfig()`: `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...denyReadExtra]` deduped; `allowWrite` unchanged; `allowRead: [workspacePath]` only when `readOnly`. (AC1, AC3)
- [ ] T2.2 Delete `enumerateSiblingDenyPaths`, the `degraded` arm, the per-dispatch `readdirSync`, and the enumeration `reportSilentFallback` path. Keep `warnSilentFallback` for the c4-staging mkdir failure. (AC2)
- [ ] T2.3 Rename the structured log `op:"sibling-deny"` → `op:"tenant-deny"`, drop the `degraded` field; keep `feature`, `workspacesRoot`, `workspace`, `deniedCount`, `c4StagingRootReady`. (no consumer found of the old slug — verified at plan time)
- [ ] T2.4 Rewrite the module header to state the deny-then-restore contract this config now depends on (and the fixture pin that guards it).
- [ ] T2.5 Comment sweep (no behavior): `cc-dispatcher.ts` notes referencing per-sibling `denyRead` (the `.worktrees` merge-visibility note and the askpass/workspace-read note); `sandbox-canary.mjs` zero-sibling comments (~`computeCanaryPaths`/`doCapture` areas) where they describe the enumeration-era invariant.
- [ ] T2.6 `cd apps/web-platform && npx vitest run …` for T1 files — the config-shape assertions go GREEN; the fixture-ordering pin stays RED until Phase 3.

## Phase 3 — In-image re-capture + audit (merge-blocker)

- [ ] T3.1 `ANTHROPIC_API_KEY="$(doppler secrets get ANTHROPIC_API_KEY --project soleur --config ci --plain)" SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` → fixture regenerated (capture-emitted bytes only). (AC4)
- [ ] T3.2 Audit the diff: covering `--tmpfs` on the capture root present; ≥1 `--bind ${CANARY_WS} ${CANARY_WS}` after it; `/dev/null` mask set still effective (not shadowed by the restore); `prepDirs` gained the literal root. If falsified → STOP, contingency path per plan (shim rewrite → re-plan). (AC4, AC5)
- [ ] T3.3 `SANDBOX_CANARY_MODE=verify bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` → `verify_ok`. (AC4)

## Phase 4 — ADR-075 amendment

- [ ] T4.1 Append dated amendment to `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`: Option C shipped via the vendored builder's deny-then-restore ordering (SDK 0.3.284 / CLI 2.1.284); per-sibling enumeration removed; status `accepted-with-residual` → `accepted`; residual-undetectability consequence retired. (AC8)

## Phase 5 — Full green + gate self-proof

- [ ] T5.1 Full vitest pass on touched files + `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. (AC9)
- [ ] T5.2 On the PR: `sandbox-canary-capture-gate` reaches `canary --verify OK` without an `sdk-bump-verified:` trailer (no dep bump). (AC10)
