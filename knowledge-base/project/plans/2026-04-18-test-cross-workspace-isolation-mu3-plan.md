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
- **SDK permission semantics (Phase 1 spike, 2026-04-19 — see `sdk-probe-notes.md`):** No direct SDK tool-invocation API exists. Per `sdk.d.ts:1180-1186`, `sandbox.filesystem.allowWrite`/`denyRead` are **additive** to permission rules from Read/Edit tool allow/deny lists — `permissionMode: "bypassPermissions"` may strip the permission-rule-derived bwrap mounts, resulting in *looser* restrictions than production, not tier-4-isolated. **The plan's original tier-isolation design via `bypassPermissions` is contradicted by the SDK contract.** Phase 1 spike committed (`5c23ea29`); founder-approved **Path C** (hybrid): direct `child_process.spawn("bwrap", capturedArgv, ...)` for tier-4-local cases + `query()` with production config for SDK-specific cases (FR8/FR9) + one SDK smoke case.

For prior security-learning context (CWE-22 prefix collision, CWE-59 symlink escape, `/proc` denyRead, canUseTool defense-in-depth, Docker seccomp), see the brainstorm's Research section.

## Research Reconciliation — Spec vs. Codebase

Spec TR4 says `permissions.allow: []` — this is agent-runner's wrapper shape, not an SDK option. Plan uses the SDK's `allowedTools: [...]` instead. Spec FR13 assumes an exported `FILE_TOOLS` constant — none exists in the SDK, so the plan hard-codes the list as a `coverageMap`. Spec FR12 uses "Agent" — SDK calls it `Task`. **Spec TR4 + FR14 assert `permissionMode: "bypassPermissions"` as the tier-4 isolation primitive — Phase 1 spike proved this assumption wrong; Path C (hybrid) replaces it with direct-bwrap-spawn for tier-4-local cases.** First three are wording-level; the tier-isolation correction is architectural but absorbed into the Phase 2-8 revisions below rather than a spec rewrite.

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

**STATUS: COMPLETE.** Spike output committed as `5c23ea29 docs(spec): SDK probe notes — tier-isolation assumption contradicts SDK docs`. Notes at `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md`. Founder approved **Path C (Hybrid)** — most cases direct `spawn("bwrap", capturedArgv, ...)`, FR8/FR9 via real `query()` with production config, one `query()` smoke case proving SDK still invokes bwrap.

Phases 2+ below revised to match Path C.

### Phase 2 — Capture SDK bwrap argv + fixture helpers (~2h)

**2A — Capture bwrap argv (one-time)**. Run a real `query()` with production-equivalent sandbox config in a controlled environment with `strace -f -e trace=execve -s 8192` attached (or a Node `child_process.spawn` wrapper preloaded via `--require`). Capture the exact argv the SDK hands to bwrap. Commit the argv + capture methodology as a table in `sdk-probe-notes.md` ("Captured argv — <date>"). This argv becomes the reference used by Phase 3+ direct-spawn cases. Document re-capture trigger: any `@anthropic-ai/claude-agent-sdk` minor version bump.

- [ ] 2A.1 Write `apps/web-platform/scripts/capture-bwrap-argv.ts` (gitignored) — runs `query()` with production `sandbox` config under strace capture. Minimal prompt that forces bwrap invocation (e.g., "Run: `true`").
- [ ] 2A.2 Execute the capture locally (requires `ANTHROPIC_API_KEY` from `doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain` — if dev config lacks the key, use prd config in read-only mode).
- [ ] 2A.3 Record the full argv in `sdk-probe-notes.md` under a `## Captured bwrap argv (2026-04-19)` heading. Include the SDK version inspected (`0.2.85` unless changed).
- [ ] 2A.4 `git rm apps/web-platform/scripts/capture-bwrap-argv.ts`; ensure `.gitignore` covers `apps/web-platform/scripts/capture-bwrap-argv.*`.

**2B — Fixture helpers**. Zero-dep; helpers exercised by the tests themselves (no meta-test).

- [ ] 2B.1 Create `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` exporting:
  - `createWorkspacePair()` — `{ rootA, rootB, cleanup }`; dirs `/tmp/soleur-isolation-<pid>-<ts>/<uuidA|B>`.
  - `seedMarker(root, name, content)` — writes marker file, returns abs path.
  - `linkEscape(rootA, linkName, target)` — creates symlink (target may be dangling or cross-workspace).
  - `spawnBwrap(workspacePath, argv, command)` — constructs full bwrap argv by templating the captured-argv reference with the workspace-specific bind mount, then `spawn("bwrap", argv, { stdio: ['ignore', 'pipe', 'pipe'] })`. Returns `{ stdout: string, stderr: string, exitCode: number }` after the child exits.
  - `spawnSandboxB(rootB, env, longRunningCommand)` — for FR7; spawns a bwrap child as a long-running process, returns `{ pid, ready: Promise<void>, kill: () => Promise<void> }`; stdout `READY\n` handshake; SIGTERM → 2s → SIGKILL.
  - `rescueStaleFixtures()` — asserts TMPDIR starts with `/tmp/` AND contains `soleur-isolation-` (blast-radius guard per `cq-destructive-prod-tests-allowlist`) before `rm -rf`; `pgrep -f soleur-isolation | xargs -r kill -TERM`.
  - `probeSkip(kind: "direct" | "query")` — `{ skip: boolean, reason: string }`. For `"direct"`: probes `command -v bwrap` + ephemeral `bwrap --unshare-user true` exit code. For `"query"`: additionally probes `process.env.ANTHROPIC_API_KEY`.
- [ ] 2B.2 Pure Node imports only (`fs`, `os`, `path`, `child_process`). No SDK import in the helper module.

### Phase 3 — Smoke (FR2) + TDD inversion (~2h)

Prove the direct-spawn harness can exercise OS-level denial AND that its assertion can actually fail.

- [ ] 3.1 Create `apps/web-platform/test/sandbox-isolation.test.ts` with a top-of-file comment (5 lines): explains Path C — most cases use `spawnBwrap()` with argv captured from the SDK (tier-4-only, deterministic, no LLM); FR8/FR9 use real `query()` with production config (full-stack SDK-integration); one `query()` smoke case proves SDK still invokes bwrap. Cite `sdk-probe-notes.md` for the captured argv reference.
- [ ] 3.2 FR2 smoke via `spawnBwrap(rootA, argv, "cat <rootB>/secret.md")`. Seed marker in `rootB/secret.md`. Assert `stdout` does not contain marker AND `exitCode !== 0`. Wrap in try/catch rethrowing pre-assertion errors as `new Error("setup failure, not leak: ...")`.
- [ ] 3.3 **TDD inversion (C4):** before declaring green, temporarily relax the bwrap argv to include `--bind <rootB> <rootB>` (making rootB writable+readable from the sandbox). Confirm the assertion fails with the marker appearing in stdout. Revert argv. Commit both steps separately so reviewers see the failing-state evidence.
- [ ] 3.4 Run the inverted test → confirm RED; run the proper test → confirm GREEN. Commit when both clean.
- [ ] 3.5 SDK-integration smoke: single `query()` call with production sandbox config asking the model to `cat <rootB>/secret.md`. Accept one retry on ambiguous (non-Bash) output. Assert marker absent. If this test flakes persistently (>30% on local retry), file issue and mark `test.fails({ todo: '#<N>' })` with explanation.

### Phase 4 — Tier-4 adversary cases (~1.5h; direct spawn)

All cases use `spawnBwrap(rootA, argv, command)`. Deterministic; no LLM involvement.

- [ ] 4.1 FR3 direct write: `echo pwned > <rootB>/pwned && ls <rootB>/pwned`; assert exit != 0 AND no `pwned` file in `rootB` after.
- [ ] 4.2 FR4 prefix collision: workspace `<prefix>/tenant`, sibling `<prefix>/tenant-evil/secret.md`; attempt read.
- [ ] 4.3 FR5 symlink escape: `linkEscape(rootA, "link", rootB + "/secret.md")`; `cat rootA/link` — must fail. Also covers dangling-symlink case via realpath canonicalization.
- [ ] 4.4 FR10 / FR11: **SKIPPED at tier-4 layer**. LS and NotebookRead are SDK tools — they don't have a direct-bwrap analog. Two options, decide during implementation: (a) skip entirely — LS/NotebookRead isolation is tier-3 concern, already covered by `sandbox-hook.test.ts` and `sandbox.test.ts`, so #1450's scope becomes "tier-4 + full-stack," not "every tool"; (b) add full-stack `query()` cases for LS/NotebookRead in Phase 5 alongside FR7/FR8/FR9. **Recommendation: (a).** Document the scope change in the top-of-file comment and in Phase 9 PR body. Update coverage map (Phase 7) accordingly.

### Phase 5 — Concurrent sandbox (~2h; direct spawn)

- [ ] 5.1 FR7 `/proc/<pid>/environ`: use `spawnSandboxB(rootB, { LEAK_MARKER: "<uuid>" }, "sleep 60")` — spawns bwrap with long-running child; awaits READY handshake. From a direct `spawnBwrap(rootA, argv, "cat /proc/${B.pid}/environ")`, assert `LEAK_MARKER` absent and exit != 0. `afterEach`: `B.kill()`, assert child exited within 3s.
- [ ] 5.2 FR12 Task subagent: deferred to follow-up issue. Reasoning: same parent process tree, same bwrap mount namespace — assertion is tautological. File `feat: Task-subagent cross-workspace test (MU3 followup)` as P2 if a deterministic verification approach surfaces.

### Phase 6 — Shared-surface audit (~3h; sequencing fixed per Kieran C3)

Write assertions as *isolation proofs* first. Observe results. If leaks surface, invert the assertions and file follow-up issues — not before.

**Path C note:** FR8 and FR9 require real SDK behavior (shared tmpfs + session file handling) so both use `query()` with **production-equivalent config** — `permissionMode: "default"`, hooks enabled, canUseTool callback active. These cases test the full stack, not tier-4 alone. Skip via `probeSkip("query")` if API key absent.

- [ ] 6.1 FR8 shared `/tmp`: run `query()` under rootA with a prompt that writes `/tmp/soleur-isolation-leak-test` containing marker. Separately run `query()` under rootB with a prompt that reads `/tmp/soleur-isolation-leak-test`. Assertion: `expect(stdoutB).not.toContain(marker)`. Wrap in setup-failure try/catch. **If LLM refuses to execute either prompt, mark skip with reason "model declined; retry N/N"** — do not count as green.
- [ ] 6.2 FR9 SDK session files: after `query()` under rootA with `persistSession: true` + session marker, under rootB run `query()` prompting the model to `cat ~/.claude/projects/*` or equivalent enumeration. Assertion: `expect(readResult).not.toContain(markerFromA)`. Same LLM-refusal handling.
- [ ] 6.3 Run the full suite. Branch on observed results:
  - **If FR8 AND FR9 pass (no leaks):** keep assertions as isolation proofs. Update `knowledge-base/product/roadmap.md` MU3 row to `Done (#1450 — all cases pass)` in the same commit. PR body gets a `## Test Results: all shared-surface cases passed; MU3 gate closes on merge` section. Done.
  - **If FR8 or FR9 leaks:** for each leaking case, `gh issue create --title "feat: <gap description> (MU3 gap)" --label priority/p1-high --label type/security --label domain/engineering --milestone "Pre-Phase 4: Multi-User Readiness Gate"`. Body links #1450, this plan, spec. Then invert that case: `expect(readResult).toBe(markerString)` wrapped in `test.fails({ todo: '#<real-issue>' })`. Update roadmap MU3 row to `Test exists; gate open on #<issues>`.
- [ ] 6.4 Lint guard: add a top-of-file check that any `test.fails({ todo })` where `todo.match(/^#TBD/)` throws at test-load time. Protects against `#TBD` placeholders reaching main.

### Phase 7 — Coverage guard (~45min)

Prove every currently-known path-accepting tool has a denial case. Uses explicit map, not title-regex.

Post-Path-C scope change: LS/NotebookRead/NotebookEdit/Glob/Grep are **SDK tool-entry concerns (tier 2/3)**, not tier-4 bwrap. Tier 4 is proven by direct `spawnBwrap` which intercepts *syscalls*, not tool wrappers. The coverage guard therefore shrinks to cases actually in scope:

- [ ] 7.1 Declare `const COVERAGE: Record<string, string> = { "direct-bwrap/Bash": "FR2/FR3/FR4/FR5/FR7", "sdk-query/Bash": "FR2-smoke/FR8/FR9" };` at top of `sandbox-isolation.test.ts`.
- [ ] 7.2 One test asserts both keys exist. Breaking the guard requires explicit update. No SDK version pin.
- [ ] 7.3 Comment above: "Tier-2/3 tool-internal path validation (LS, NotebookRead, Glob, Grep) is covered by `test/sandbox-hook.test.ts` and `test/sandbox.test.ts`. This file covers tier-4 (bwrap syscall-level) + full-stack SDK integration."

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
- [ ] AC2 Direct-spawn tier-4 cases green: FR2, FR3, FR4, FR5, FR7. FR8/FR9 via `query()` are either green (isolation proof) or `test.fails({ todo: '#<real-issue>' })` with no `#TBD` placeholders. FR10/FR11 excluded from this file per Path C scope change (already covered by `test/sandbox-hook.test.ts`).
- [ ] AC3 TDD inversion commit (Phase 3.3) demonstrates the smoke test can fail when bwrap argv is relaxed to include rootB.
- [ ] AC4 Coverage guard (Phase 7) green; keys are `direct-bwrap/Bash` and `sdk-query/Bash`.
- [ ] AC5 Top-of-file comment documents Path C (direct-spawn for tier 4, query() for full-stack) in 5 lines.
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
