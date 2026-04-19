# Plan: Cross-Workspace Isolation Integration Suite (MU3)

**Issue:** #1450
**Branch:** feat-verify-workspace-isolation
**Worktree:** .worktrees/feat-verify-workspace-isolation/
**PR:** #2610 (draft)
**Brainstorm:** knowledge-base/project/brainstorms/2026-04-18-verify-workspace-isolation-brainstorm.md
**Spec:** knowledge-base/project/specs/feat-verify-workspace-isolation/spec.md
**Date:** 2026-04-18

## Overview

Prove that one workspace's sandboxed process cannot read, write, or leak data from another workspace via filesystem, `/proc`, shared `/tmp`, or SDK session files. Two test surfaces:

- **Vitest PR subset** at `apps/web-platform/test/sandbox-isolation.test.ts` — runs on every PR; skips if bwrap, API key, or `CLONE_NEWUSER` unavailable.
- **Canary full matrix** = `docker exec` of the same vitest file inside the canary container post-deploy, via `apps/web-platform/infra/ci-deploy.test.sh`. One implementation, two execution contexts.

Closes #1450 (test exists). MU3 gate closes in this PR if all shared-surface cases pass; otherwise stays open until follow-up issues resolve.

## Research Insights

- **SDK sandbox site:** `apps/web-platform/server/agent-runner.ts:941-958`. Shape: `sandbox: { enabled, autoAllowBashIfSandboxed, allowUnsandboxedCommands, enableWeakerNestedSandbox, network, filesystem: { allowWrite: [workspacePath], denyRead: ["/workspaces", "/proc"] } }`. bwrap argv is assembled internally by `@anthropic-ai/claude-agent-sdk`.
- **Workspace derivation:** `apps/web-platform/server/workspace.ts:49` — `provisionWorkspace(userId)` writes to `join(process.env.WORKSPACES_ROOT || "/workspaces", userId)`. UUID-validated at `workspace.ts:13`.
- **Test runner:** `apps/web-platform/vitest.config.ts:18` already includes `test/**/*.test.ts` in `node` environment — no config change. Run via `./node_modules/.bin/vitest run` (AGENTS `cq-in-worktrees-run-vitest-via-node-node`).
- **Prior art:** `test/sandbox.test.ts` (path-logic unit), `test/sandbox-hook.test.ts` (hook callback unit), `infra/ci-deploy.test.sh:919-962` (existential bwrap canary). None are cross-workspace isolation tests.
- **SDK permission semantics (Context7-confirmed):** `permissionMode: "bypassPermissions"` skips `canUseTool` but **hooks still fire**. Tier-4 isolation therefore requires `permissionMode: "bypassPermissions"` AND no PreToolUse hooks registered in the test's `query()` options.

For prior security-learning context (CWE-22 prefix collision, CWE-59 symlink escape, `/proc` denyRead, canUseTool defense-in-depth, Docker seccomp), see the brainstorm's Research section.

## Research Reconciliation — Spec vs. Codebase

Spec TR4 says `permissions.allow: []` — this is agent-runner's wrapper shape, not an SDK option. Plan uses the SDK's `allowedTools: [...]` instead. Spec FR13 assumes an exported `FILE_TOOLS` constant — none exists in the SDK, so the plan hard-codes the list as a `coverageMap`. Spec FR12 uses "Agent" — SDK calls it `Task`. All three are wording-level, not architecture changes.

## Plan Review Applied

Two Kieran-identified architectural blockers drove Phase 1's scope:

- **C1 — `query()` determinism.** Invoking `query({ prompt: "Run this bash: cat <B>/secret" })` depends on the model choosing to call the Bash tool. For an MU3 gate this is unacceptable. Phase 1 picks a deterministic tier-4 invocation path: either an SDK direct-tool entry, `child_process.spawn("bwrap", capturedArgv)`, or a harness that short-circuits the model.
- **C2 — Structured-path tool validators.** Tools like `LS` and `NotebookRead` may enforce path constraints internally before bwrap sees the syscall. Phase 1 verifies whether `bypassPermissions` actually disables tool-internal validation.

If Phase 1 finds the SDK path is non-deterministic and no direct entry exists, the whole suite reduces to `spawn("bwrap", sdkCapturedArgv, "bash", "-c", attack)` — simpler, faster, but requires intercepting argv once to capture it. Phase 1 decides the architecture; Phases 2+ implement the winner.

Other applied changes: spike scope narrowed (no API-key probe, no concurrent-query probe — inlined); completeness guard uses explicit `coverageMap` instead of title-regex and drops SDK version pin; canary tier is `docker exec vitest run` against the same test file (no separate node script); FR6 dangling symlink dropped (covered by FR5 realpath path); FR12 Task subagent deferred as follow-up (tautological if same process tree); detail level MORE, no embedded code blocks.

## Dependencies & Preconditions

- `bubblewrap` installed in `apps/web-platform/Dockerfile` ✓
- `seccomp-bwrap.json` permits `CLONE_NEWUSER` on canary ✓
- Vitest 1.x in `apps/web-platform` (supports `test.fails`, `describe.skipIf`) ✓
- `ANTHROPIC_API_KEY` in local `.env` (verify before Phase 3) — if absent, `gh secret list --repo jikig-ai/soleur | grep -i anthropic` confirms CI secret; file a pre-merge operator task in the PR body if missing.
- GHA runner `CLONE_NEWUSER` support — assumed present on ubuntu-24.04; vitest skips cleanly if not.

## Open Code-Review Overlap

None. Queried 28 open `code-review`-labeled issues against every planned file path — zero matches.

## Implementation Phases

### Phase 1 — Invocation-path decision spike (~1.5h)

Resolve C1 + C2 before writing any test. Output: one commit updating the plan + `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md`. No scaffolding under `apps/web-platform/infra/` — probe code lives in `apps/web-platform/scripts/sdk-probe.ts` (gitignored) and is deleted after notes are written.

- [ ] 1.1 Confirm C1 empirically: pick the minimum invocation that deterministically runs a chosen shell command inside the SDK-configured bwrap. Candidates in order of preference: (a) SDK direct-tool entry for Bash (if exported), (b) `child_process.spawn("bwrap", argv)` with argv captured once from an instrumented SDK run, (c) `query()` with prompt + `allowedTools: ["Bash"]` accepting the model-compliance risk.
- [ ] 1.2 Confirm C2: for `LS` and `NotebookRead` tool calls under `permissionMode: "bypassPermissions"` + no hooks, does the tool's own input validator reject cross-workspace paths before bwrap? If yes, those tool-level tests are tier-2 assertions, not tier-4, and the plan's FR10/FR11 semantics change.
- [ ] 1.3 Write `sdk-probe-notes.md` with: chosen invocation path (candidate letter), exact code shape, whether structured-path tools reach tier 4, SDK version pinned at probe time.
- [ ] 1.4 Amend this plan's Phase 3–6 scaffolding notes if the spike chose (b) or (c) — one inline edit, not a rewrite.
- [ ] 1.5 `git rm apps/web-platform/scripts/sdk-probe.ts` if it landed in git; confirm `.gitignore` covers `apps/web-platform/scripts/sdk-probe.*`.

### Phase 2 — Fixture helpers (~1.5h)

Land a zero-dep helper module. Helpers are exercised by the isolation tests themselves — no separate meta-test.

- [ ] 2.1 Create `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` exporting:
  - `createWorkspacePair()` — returns `{ rootA, rootB, cleanup }`; dirs are `/tmp/soleur-isolation-<pid>-<ts>/<uuidA|B>`.
  - `seedMarker(rootB, name, content)` — writes marker file, returns absolute path.
  - `linkEscape(rootA, linkName, target)` — creates symlink (target may be dangling or cross-workspace).
  - `spawnSandboxB(rootB, env, longRunningCommand)` — spawns a child Node process, returns `{ pid, ready: Promise<void>, kill: () => Promise<void> }`; stdout `READY\n` handshake; `kill()` sends SIGTERM, awaits exit.
  - `rescueStaleFixtures()` — at test boot: asserts TMPDIR prefix starts with `/tmp/` AND contains `soleur-isolation-` (blast-radius guard per AGENTS `cq-destructive-prod-tests-allowlist`) before `rm -rf`; then `pgrep -f sandbox-isolation | xargs -r kill -TERM`.
  - `probeSkip()` — returns `boolean` (skip if true); logs the reason to stderr. Probes in order: `command -v bwrap`, `process.env.ANTHROPIC_API_KEY`, `spawnSync('bwrap', ['--unshare-user', 'true'])` exit code.
- [ ] 2.2 Make helpers pure Node (`fs`, `os`, `path`, `child_process`). No SDK import.

### Phase 3 — Smoke (FR2) + TDD inversion (~2h)

Prove the harness can exercise OS-level denial AND that its assertion can actually fail.

- [ ] 3.1 Create `apps/web-platform/test/sandbox-isolation.test.ts` with a tight top-of-file comment (3 lines): each test uses `permissionMode: "bypassPermissions"` + `hooks: {}`, so bwrap (tier 4) is the sole active defender; a passing assertion means OS-level denial, not higher-tier path validation.
- [ ] 3.2 Implement `runInSandbox(workspacePath, opts)` — one parameterized helper, not two — using whichever invocation path Phase 1 chose. `opts`: `{ prompt?, toolName?, toolInput?, allowedTools }`. Shared sandbox config: `filesystem.allowWrite: [workspacePath]`, `filesystem.denyRead: ["/workspaces", "/proc"]`, `settingSources: []`, `hooks: {}`, `permissionMode: "bypassPermissions"`, `disallowedTools: []` (tier 2 not exercised).
- [ ] 3.3 Write FR2: seed `rootB/secret.md`, `runInSandbox(rootA, { prompt: bash-cat-command, allowedTools: ["Bash"] })`, assert `stdout` does not contain marker AND exit != 0. Wrap in try/catch that rethrows pre-assertion errors as `new Error("setup failure, not leak: ...")`.
- [ ] 3.4 **TDD inversion (C4):** before declaring green, temporarily change `allowWrite: [rootA]` to `allowWrite: [rootA, rootB]` (or equivalent relaxation per Phase 1's chosen path), confirm the assertion fails with the marker appearing in stdout. Restore config. Commit both steps separately so reviewers see the failing-state evidence.
- [ ] 3.5 Run the inverted test → confirm RED; run the proper test → confirm GREEN. Commit when both are clean.

### Phase 4 — Tier-4-isolatable adversary cases (~2h)

- [ ] 4.1 FR3 direct write denial: `runInSandbox(rootA, { prompt: "echo pwned > <B>/pwned", allowedTools: ["Bash"] })`; assert exit != 0 AND no `pwned` file in `rootB` after.
- [ ] 4.2 FR4 prefix collision: workspace at `<prefix>/tenant`, sibling at `<prefix>/tenant-evil/secret.md`; assert denial.
- [ ] 4.3 FR5 symlink escape: `linkEscape(rootA, "link", rootB + "/secret.md")`; `cat rootA/link` via Bash; assert denial. Also covers dangling-symlink case (realpath canonicalization).
- [ ] 4.4 FR10 LS tool: `runInSandbox(rootA, { toolName: "LS", toolInput: { path: rootB }, allowedTools: ["LS"] })`; assert denial. **If Phase 1's C2 investigation found LS has an internal path validator that fires before bwrap, mark this case as tier-2 in the test comment and retain it for coverage — or move it to a separate "tier-2 regression" describe block.**
- [ ] 4.5 FR11 NotebookRead: seed `rootB/foo.ipynb` (minimal valid notebook JSON); run NotebookRead against it from `rootA`; same tier-2-vs-tier-4 caveat as FR10.

### Phase 5 — Concurrent-sandbox case (~2h)

- [ ] 5.1 FR7 `/proc/<pid>/environ`: use `spawnSandboxB` to launch a long-running child with marker env `LEAK_MARKER=<uuid>` + `sleep 60`. Await child's READY. From sandbox A, attempt `cat /proc/${B.pid}/environ`. Assert `LEAK_MARKER` absent and exit != 0. `afterEach`: `B.kill()`, assert exit within 3s.
- [ ] 5.2 FR12 Task subagent: deferred to follow-up issue. Plan captures reasoning: same parent process tree, same bwrap mount namespace — assertion is tautological without a separate invocation path. File `feat: Task-subagent cross-workspace test (MU3 followup)` as P2 if a clean verification approach surfaces later.

### Phase 6 — Shared-surface audit (~3h; sequencing fixed per Kieran C3)

Write assertions as *isolation proofs* first. Observe results. If leaks surface, invert the assertions and file follow-up issues — not before.

- [ ] 6.1 FR8 shared `/tmp`: sandbox A writes `/tmp/soleur-isolation-leak-test` with marker; spawn sandbox B (separate child process via `spawnSandboxB`) and from B attempt `cat /tmp/soleur-isolation-leak-test`. Assertion: `expect(stdoutB).not.toContain(marker)`. Wrap in setup-failure try/catch.
- [ ] 6.2 FR9 SDK session files: after a full `query()` under sandbox A with `persistSession: true`, under sandbox B attempt to read `~/.claude/projects/<dir>/`. Assertion: `expect(readResult).not.toContain(markerFromA)`.
- [ ] 6.3 Run the full suite. Branch on observed results:
  - **If FR8 AND FR9 pass (no leaks):** keep assertions as isolation proofs. Update `knowledge-base/product/roadmap.md` MU3 row to `Done (#1450 — all cases pass)` in the same commit. PR body gets a `## Test Results: all shared-surface cases passed; MU3 gate closes on merge` section. Done.
  - **If FR8 or FR9 leaks:** for each leaking case, `gh issue create --title "feat: <gap description> (MU3 gap)" --label priority/p1-high --label type/security --label domain/engineering --milestone "Pre-Phase 4: Multi-User Readiness Gate"`. Body links #1450, this plan, spec. Then invert that case: `expect(readResult).toBe(markerString)` wrapped in `test.fails({ todo: '#<real-issue>' })`. Update roadmap MU3 row to `Test exists; gate open on #<issues>`.
- [ ] 6.4 Lint guard: add a top-of-file check that any `test.fails({ todo })` where `todo.match(/^#TBD/)` throws at test-load time. Protects against `#TBD` placeholders reaching main.

### Phase 7 — Coverage guard (~45min)

Prove every currently-known path-accepting tool has a denial case. Uses explicit map, not title-regex.

- [ ] 7.1 At top of `sandbox-isolation.test.ts`, declare `const COVERAGE: Record<string, string> = { Bash: "FR2/FR3", LS: "FR10", NotebookRead: "FR11", NotebookEdit: "pending", Read: "via Bash", Write: "via Bash", Edit: "via Bash", Glob: "pending", Grep: "pending", Task: "deferred#<N>" };`.
- [ ] 7.2 One test: `expect(Object.keys(COVERAGE).sort()).toEqual(["Bash","Edit","Glob","Grep","LS","NotebookEdit","NotebookRead","Read","Task","Write"]);`. Breaking the guard requires explicit tool list update. No SDK version pin — dependabot PR review catches new SDK tools via changelog, not a hidden test tripwire.
- [ ] 7.3 Document in a comment above COVERAGE: "Review this map when `@anthropic-ai/claude-agent-sdk` minor version bumps. Add pending cases or update the list."

### Phase 8 — Canary integration (~1h; vitest-in-container)

No separate canary node script. `docker exec` runs vitest against the same file.

- [ ] 8.1 Append to `apps/web-platform/infra/ci-deploy.test.sh`:
  - Function `assert_cross_workspace_isolation()`: precondition `docker inspect -f '{{.State.Running}}' soleur-web-platform-canary == true`; wrap `timeout 300 docker exec soleur-web-platform-canary /app/node_modules/.bin/vitest run test/sandbox-isolation.test.ts --reporter=verbose`; distinguish exit codes 124 (timeout), 125/126/127 (docker-side), 0 (pass), other (vitest failure).
  - Invoke next to the existing `assert_bwrap_canary_check` call.
- [ ] 8.2 Verify the canary container image includes vitest (`node_modules/.bin/vitest`) in the final `COPY` — if not, amend `apps/web-platform/Dockerfile` to ensure test deps are in the deploy image, OR document that the canary uses a dev-deps variant of the image.
- [ ] 8.3 Do NOT wire the canary assertion into `ci-deploy.sh` deploy-blocking path in this PR. File follow-up `feat: promote cross-workspace isolation check to deploy gate` as P2 after matrix stabilizes.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `cd apps/web-platform && ANTHROPIC_API_KEY=... ./node_modules/.bin/vitest run test/sandbox-isolation.test.ts` passes locally OR skips with `probeSkip()` reason logged to stderr (never a silent pass).
- [ ] AC2 All FR2, FR3, FR4, FR5, FR7, FR10, FR11 cases green. FR8/FR9 are either green (isolation proof) or `test.fails({ todo: '#<real-issue>' })` with no `#TBD` placeholders.
- [ ] AC3 TDD inversion commit (Phase 3.4) demonstrates the smoke test can fail when sandbox config is relaxed.
- [ ] AC4 Coverage guard (Phase 7) green; proven to fail when a key is removed.
- [ ] AC5 Top-of-file comment names tier-4 isolation rationale in 3 lines.
- [ ] AC6 `npx markdownlint-cli2 --fix` run on all changed `.md` files.

### Post-merge (operator)

- [ ] AC7 `bash apps/web-platform/infra/ci-deploy.test.sh` runs `assert_cross_workspace_isolation` on next canary deploy; result logged.
- [ ] AC8 If FR8/FR9 leaked: follow-up issues appear in `Pre-Phase 4: Multi-User Readiness Gate` milestone and are referenced in MU3 roadmap row.
- [ ] AC9 If all shared-surface passed: `knowledge-base/product/roadmap.md` MU3 row and `## Current State` section updated in same PR, and MU3 milestone closes.

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` | Zero-dep fixture helpers |
| `apps/web-platform/test/sandbox-isolation.test.ts` | Vitest integration suite |
| `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md` | Phase 1 findings |

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.test.sh` | Append `assert_cross_workspace_isolation` + invocation |
| `apps/web-platform/Dockerfile` | Only if Phase 8.2 finds vitest missing in deploy image |
| `knowledge-base/product/roadmap.md` | MU3 row + `## Current State` (Phase 6.3) |
| `.gitignore` | Add `apps/web-platform/scripts/sdk-probe.*` if not already covered |

## Out of Scope

- Fixing any shared-surface gap FR8/FR9 exposes (each gets its own issue).
- Container-per-workspace isolation (#673, Phase 4 trigger).
- HTTP-layer E2E test.
- Tiers 1–3 isolation tests (covered by existing `sandbox.test.ts` / `sandbox-hook.test.ts`).
- Wiring canary assertion into deploy-blocking path.
- FR12 Task subagent isolation — follow-up issue if a deterministic verification approach surfaces.

## Risks

| Risk | Mitigation |
|---|---|
| Phase 1 finds `query()` non-deterministic AND no direct-tool entry exists → must use `spawn("bwrap", capturedArgv)` path | Acceptable — in fact simpler and more deterministic. Argv captured once from instrumented SDK run; SDK minor bumps re-run the capture. |
| FR10/FR11 tool-internal validators fire before bwrap (Phase 1 C2) | Mark those cases as tier-2 assertions and keep for coverage; file follow-up to add direct tier-4 LS/NotebookRead test via the spawn-bwrap path. |
| Vitest budget (<90s PR subset) exceeded by `query()` roundtrips | Fall back to PR subset = FR2+FR4+FR5 only; canary covers the rest. |
| `spawnSandboxB` hangs awaiting READY | 30s `ready` timeout; fail fast with setup error. |
| Workspace cleanup leaves root-owned files (UID remap) | `rescueStaleFixtures` best-effort; file issue if reproduces. No sudo available in CI. |

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm). Product tier = NONE (internal test suite, no user-facing surface, no new component files).

### Engineering

**Status:** reviewed (carry-forward)
**Assessment:** bwrap is SDK-internal; test asserts behavior, not config. Four-tier defense model; tier 4 isolated via `permissionMode: "bypassPermissions"` + no hooks. Phase 1 spike de-risks `query()` determinism before committing harness. Known attack surfaces from prior security learnings. Predicted gaps (`/tmp`, session files) filed as follow-up issues, not patched inline — preserves "verify, don't rewrite."
