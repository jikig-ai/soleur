# Spec: Verify Workspace Isolation at Process Level (MU3)

**Issue:** #1450
**Branch:** feat-verify-workspace-isolation
**Date:** 2026-04-18
**Brainstorm:** knowledge-base/project/brainstorms/2026-04-18-verify-workspace-isolation-brainstorm.md

## Problem Statement

The Claude Agent SDK at `apps/web-platform/server/agent-runner.ts:941-958` configures a bubblewrap (bwrap) OS sandbox per user session with `allowWrite: [workspacePath]` and `denyRead: ["/workspaces", "/proc"]`. The bwrap argv is assembled internally by the SDK and is not inspectable from our code.

No cross-workspace integration test exists. Existing tests cover path-logic (`test/sandbox.test.ts`), the PreToolUse hook callback (`test/sandbox-hook.test.ts`), and an existential "does bwrap run at all" canary in `infra/ci-deploy.test.sh`. None verify that a process running inside sandbox A cannot read, write, or leak data from workspace B.

The Pre-Phase 4 Multi-User Readiness Gate (`knowledge-base/product/roadmap.md:264-272`) blocks founder recruitment until MU3 is verified. Without a cross-workspace isolation test, MU3 cannot be closed.

## Goals

- G1: Vitest integration test `apps/web-platform/test/sandbox-isolation.test.ts` runs on every PR, exercising a subset of the adversary matrix, skipping cleanly if `bwrap` or `ANTHROPIC_API_KEY` is absent.
- G2: Canary shell test extending `apps/web-platform/infra/ci-deploy.test.sh` runs the full adversary matrix + shared-surface audit against the canary Docker container post-deploy, using production seccomp/AppArmor.
- G3: Test cases use attack vectors that reach tier 4 (bwrap), not attacks that tier 1–3 already deny.
- G4: Failing cases land as `test.fails({ todo: '#NNNN' })` (vitest) or `expect_fail_with_todo` (shell) with linked follow-up issues; PR merges with known gaps documented.
- G5: Completeness guard enumerates the SDK `FILE_TOOLS` set and fails when a new path-accepting tool is added without a matching cross-workspace denial case.
- G6: Closing #1450 does NOT close the MU3 gate; MU3 gate closes only when all follow-up gap issues close.

## Non-Goals

- Rewriting the SDK sandbox configuration or adding bwrap argv flags.
- Implementing container-per-workspace isolation (#673, deferred to Phase 4).
- Fixing discovered gaps (shared `/tmp`, shared `~/.claude/projects/`) in this PR — each gets a dedicated follow-up issue.
- Full end-to-end HTTP-layer test through the web-platform API — this is a process-level test invoking the SDK directly.
- Verifying tiers 1, 2, or 3 (PreToolUse hooks, `disallowedTools`, `canUseTool` callback) — those have their own tests in `test/sandbox-hook.test.ts`, etc.
- Closing the MU3 gate itself.

## Functional Requirements

- FR1: **Fixture** — Test harness creates two real directories under a temp `WORKSPACES_ROOT`, seeded with a marker file in workspace B (e.g., `/tmp/.../wsroot/<uuidB>/secret.md` containing a known string).
- FR2: **Direct read denial** — Sandbox bound to workspace A attempts `Bash cat <workspaceB>/secret.md`; assert non-zero exit AND stdout does not contain the marker string.
- FR3: **Direct write denial** — Sandbox A attempts `Bash echo pwned > <workspaceB>/pwned`; assert failure AND marker file absent from B after.
- FR4: **Prefix-collision denial** — Workspace A is `/tmp/.../wsroot/tenant`; attempt access to `/tmp/.../wsroot/tenant-evil/secret.md`; assert denial. Regression guard for CWE-22 learning.
- FR5: **Symlink escape denial** — Create symlink `<workspaceA>/link -> <workspaceB>/secret.md`; `Read` and `Bash cat <workspaceA>/link` must both fail. Regression guard for CWE-59 learning.
- FR6: **Dangling symlink handled** — Symlink to non-existent target fails as missing target, not as permission bypass.
- FR7: **`/proc` environ denial** — Start a long-running process in sandbox B with a distinctive env var; from sandbox A attempt `cat /proc/<B-pid>/environ`; assert the marker env is not returned.
- FR8: **Shared `/tmp` case** — Sandbox A writes `/tmp/A-marker`; sandbox B attempts `cat /tmp/A-marker`. If this passes (no leakage), test is green. If it fails, case is marked `test.fails` with follow-up issue link.
- FR9: **SDK session-file case** — After a query in sandbox A persists a session under `~/.claude/projects/`, sandbox B attempts to read the session file. Same fail-with-issue pattern as FR8.
- FR10: **LS tool case** — SDK `LS` tool invoked with `<workspaceB>` path; assert denial.
- FR11: **NotebookRead tool case** — SDK `NotebookRead` invoked against a `.ipynb` file in workspace B; assert denial.
- FR12: **Agent subagent inheritance** — SDK `Agent` tool receives a prompt pointing at workspace B; assert the sub-session also denies access.
- FR13: **Completeness guard** — Test enumerates the SDK's path-accepting tools (Read, Write, Edit, LS, Glob, Grep, NotebookRead, NotebookEdit, Bash, Agent); each must have a matching cross-workspace denial case in FR2–FR12. New tool additions without a matching case cause the completeness guard to fail.
- FR14: **Per-case tier-4 attribution** — Each case either uses an attack vector known to pass tier 3 (Bash command strings, `/proc` reads, post-realpath symlinks) OR runs with tiers 1–3 explicitly relaxed (`bypassPermissions` or equivalent SDK flag). Document in test code comments which tier each case exercises.
- FR15: **Skip semantics** — Vitest file skips the entire suite with a clear reason if `which bwrap` fails, or if `ANTHROPIC_API_KEY` is absent, or if a runtime probe confirms `CLONE_NEWUSER` is blocked. Skip, not pass.

## Technical Requirements

- TR1: **Test placement** — Vitest file at `apps/web-platform/test/sandbox-isolation.test.ts`. Canary helper at `apps/web-platform/infra/canary-sandbox-isolation.ts` invoked via `docker exec` from `ci-deploy.test.sh`.
- TR2: **Vitest environment** — `node` environment (not `happy-dom`). Matches existing `test/**/*.test.ts` include pattern in `apps/web-platform/vitest.config.ts`; no config changes required.
- TR3: **Worktree-safe vitest invocation** — `./node_modules/.bin/vitest run` per `cq-in-worktrees-run-vitest-via-node-node`.
- TR4: **SDK config** — `settingSources: []`, `permissions.allow: []`, explicit `ANTHROPIC_API_KEY` passed, `sandbox: { enabled: true, allowWrite: [<A>], denyRead: ["/workspaces", "/proc"] }`. Cases requiring tier-4 isolation set `bypassPermissions: true` (or the SDK equivalent) for that sub-test only; other cases run production-equivalent config.
- TR5: **Fixture helpers zero-dep** — Fixture setup (directory creation, marker files, symlink creation, process spawning for `/proc` case) lives in `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts`, no transitive Supabase/WebSocket imports.
- TR6: **Concurrent-sandbox support** — Cases FR7 and FR8 require two sandboxes running concurrently. If the SDK serializes `query()` calls in a single Node process, the fixture spawns a child Node process for sandbox B and communicates via stdout markers.
- TR7: **Canary orchestration** — New assertion function in `ci-deploy.test.sh` (e.g., `assert_cross_workspace_isolation`) that `docker exec`s `node infra/canary-sandbox-isolation.ts`. Follows existing `assert_bwrap_canary_check` precedent (lines 919-939).
- TR8: **Follow-up issue creation** — On test authoring, if FR8 or FR9 fail against the real SDK, file a GitHub issue per gap (title: `feat: private /tmp per sandbox (MU3 gap)` / `feat: per-tenant SDK session root (MU3 gap)`), milestone `Pre-Phase 4: Multi-User Readiness Gate`, labels `priority/p1-high`, `type/security`, `domain/engineering`. Issue body links #1450 and the test case.
- TR9: **Test runtime budget** — Vitest subset target <90s total (runs on PR). Canary full matrix target <5min (runs post-deploy). If the SDK `query()` roundtrip makes the vitest subset exceed budget, reduce PR subset to 3 smoke cases (FR2, FR4, FR5) and rely on canary for the rest.
- TR10: **No `git stash`** — Fixture cleanup uses `rm -rf` on the temp WORKSPACES_ROOT, never `git stash`. AGENTS.md `hr-never-git-stash-in-worktrees`.

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/test/sandbox-isolation.test.ts` | Vitest integration test — PR gate subset |
| `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` | Zero-dep fixture setup/teardown helpers |
| `apps/web-platform/infra/canary-sandbox-isolation.ts` | Node script invoked by canary shell test, exercises full matrix |

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/infra/ci-deploy.test.sh` | Add `assert_cross_workspace_isolation` invoking the canary node script post-canary-boot |
| `apps/web-platform/infra/ci-deploy.sh` | If needed: add invocation of the canary isolation check as a deploy gate (same place as existing `bwrap --version` canary) |

## Acceptance Criteria

- AC1: `./node_modules/.bin/vitest run test/sandbox-isolation.test.ts` passes locally with bwrap + `ANTHROPIC_API_KEY` available; skips with clear reason otherwise.
- AC2: `bash apps/web-platform/infra/ci-deploy.test.sh` (run against the canary container) exercises all FR2–FR13 cases and either passes or marks specific cases as `expect_fail_with_todo` with linked issues.
- AC3: At least one `test.fails` case links to a filed follow-up issue milestoned to Pre-Phase 4 (predicted: `/tmp` sharing or session-file sharing).
- AC4: Completeness guard (FR13) fails the test when the path-accepting tool list in the test does not match the current SDK export; proving the guard works requires a one-line assertion that throws with the SDK's current tool list baked in.
- AC5: Test file documents in a top-of-file comment which tier each case is designed to exercise and why the chosen attack vector bypasses tiers 1–3.
- AC6: #1450 closes on merge; MU3 roadmap row updates to `[#1450](...) Test exists — gate open on #NEW1, #NEW2`.

## Out of Scope (Follow-up Issues)

Predicted but filed only when the test actually fails against the real SDK:

- **Private `/tmp` per sandbox** — if FR8 fails
- **Per-tenant SDK session root** — if FR9 fails
- Container-per-workspace isolation (#673) — already tracked, Phase 4 trigger.
