# Tasks: Cross-Workspace Isolation Integration Suite (MU3)

**Plan:** `knowledge-base/project/plans/2026-04-18-test-cross-workspace-isolation-mu3-plan.md`
**Spec:** `knowledge-base/project/specs/feat-verify-workspace-isolation/spec.md`
**Spike notes:** `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md`
**Issue:** #1450 | **PR:** #2610 | **Branch:** feat-verify-workspace-isolation

## Phase 1 — Invocation-path decision spike — ✅ COMPLETE

Spike output committed (`5c23ea29`). SDK has no direct tool-invocation API; `bypassPermissions` may strip permission-rule-derived bwrap mounts. Path C (hybrid) approved by founder. Phases 2+ revised below.

## Phase 2A — Capture SDK bwrap argv (one-time) — ✅ COMPLETE

- [x] 2A.1 Write `apps/web-platform/scripts/capture-bwrap-argv.ts` (gitignored) that invokes `query()` with production-equivalent sandbox config under `strace -f -e trace=execve` or a `child_process.spawn` wrapper preloaded via `--require`.
- [x] 2A.2 Run capture locally with `doppler run -p soleur -c dev -- node --require ./spawn-capture.js apps/web-platform/scripts/capture-bwrap-argv.ts` (or equivalent).
- [x] 2A.3 Record the full captured argv in `sdk-probe-notes.md` under `## Captured bwrap argv (2026-04-19)` with SDK version reference.
- [x] 2A.4 `git rm apps/web-platform/scripts/capture-bwrap-argv.ts`; ensure `.gitignore` covers `apps/web-platform/scripts/capture-bwrap-argv.*`.

## Phase 2B — Fixture helpers

- [x] 2B.1 Create `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` exporting: `createWorkspacePair`, `seedMarker`, `linkEscape`, `spawnBwrap`, `spawnSandboxB`, `rescueStaleFixtures` (TMPDIR allowlist), `probeSkip("direct" | "query")`.
- [x] 2B.2 Pure Node imports only — no SDK in the helper module.
- [x] 2B.3 Verify typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 3 — Smoke test + TDD inversion

- [x] 3.1 Create `apps/web-platform/test/sandbox-isolation.test.ts` with top-of-file comment explaining Path C (5 lines, references sdk-probe-notes.md).
- [x] 3.2 FR2 via `spawnBwrap(rootA, argv, "cat <rootB>/secret.md")`; assert marker absent + exit != 0; setup-failure guard.
- [x] 3.3 TDD inversion: relax argv to `--bind <rootB> <rootB>`, confirm RED, restore, confirm GREEN. Commit both separately. (RED commit c4773729; restored in successor.)
- [ ] 3.4 FR2-smoke via real `query()` with production sandbox config: model reads `<rootB>/secret.md` — assert marker absent. One retry on non-Bash output. Flake budget: >30% skip with filed issue.

## Phase 4 — Tier-4 adversary cases (direct spawn)

- [x] 4.1 FR3 direct write denial via `spawnBwrap`. (host-side pin; inversion probe confirmed --bind rootB without --tmpfs leaks leaked.md to host.)
- [x] 4.2 FR4 prefix collision via `spawnBwrap`. (user1 vs user10 naming; same isolation pattern as FR2.)
- [x] 4.3 FR5 symlink escape via `linkEscape` + `spawnBwrap`. (rootA/peek → rootB/secret.md; tmpfs overlay blocks resolution.)
- [x] 4.4 FR10/FR11 (LS, NotebookRead): **scope change per Path C.** Out of scope for this file; coverage remains in `test/sandbox-hook.test.ts` + `test/sandbox.test.ts`. Documented in top-of-file comment.

## Phase 5 — Concurrent sandbox (direct spawn)

- [ ] 5.1 FR7 `/proc/<pid>/environ` via `spawnSandboxB` (long-running bwrap child) + `spawnBwrap` cross-read attempt.
- [ ] 5.2 FR12 Task subagent — deferred follow-up issue (already planned).

## Phase 6 — Shared-surface audit (full-stack query())

Uses production-equivalent `query()` config — `permissionMode: "default"`, hooks enabled, canUseTool active. Tests the full stack, not tier 4 alone.

- [ ] 6.1 FR8 shared `/tmp`: two `query()` runs (rootA write, rootB read). Assertion: marker absent in rootB stdout. LLM refusal → skip with reason.
- [ ] 6.2 FR9 SDK session files: rootA `query()` with `persistSession: true`, rootB `query()` enumerates `~/.claude/projects/`. Marker absent assertion.
- [ ] 6.3 Run suite; branch on observed results:
  - All green → roadmap MU3 row → Done, PR body notes MU3 closes.
  - Any leak → file issues (`priority/p1-high`, `type/security`, `domain/engineering`, milestone Pre-Phase 4 Gate), invert assertion, wrap in `test.fails({ todo: '#<issue>' })`.
- [ ] 6.4 Top-of-file lint guard: any `test.fails({ todo: '#TBD…' })` throws at test-load.

## Phase 7 — Coverage guard

- [ ] 7.1 `const COVERAGE = { "direct-bwrap/Bash": "FR2/FR3/FR4/FR5/FR7", "sdk-query/Bash": "FR2-smoke/FR8/FR9" };` at top of file.
- [ ] 7.2 One test asserts both keys exist.
- [ ] 7.3 Comment pointing at `test/sandbox-hook.test.ts` + `test/sandbox.test.ts` for tier-2/3 tool-path coverage.

## Phase 8 — Canary integration

- [ ] 8.1 Append `assert_cross_workspace_isolation` to `apps/web-platform/infra/ci-deploy.test.sh`: docker inspect precondition + `timeout 300 docker exec … vitest run test/sandbox-isolation.test.ts`; exit-code disambiguation.
- [ ] 8.2 Verify `/app/node_modules/.bin/vitest` exists in canary image; amend Dockerfile if missing.
- [ ] 8.3 File follow-up `feat: promote cross-workspace isolation check to deploy gate` (P2).

## Phase 9 — Pre-merge sweep

- [ ] 9.1 `ANTHROPIC_API_KEY` present OR PR body operator task.
- [ ] 9.2 All AC1–AC6 checkboxes ticked in PR description.
- [ ] 9.3 `npx markdownlint-cli2 --fix` on all changed `.md`.
- [ ] 9.4 `git push` before `/soleur:review`.
- [ ] 9.5 Run `/soleur:review`; resolve findings inline.
- [ ] 9.6 `/soleur:compound` → `/ship`.

## Dependencies

- Phase 2A is independent (can start anytime). Its output feeds Phase 2B (`spawnBwrap` templates on captured argv) and all subsequent direct-spawn phases.
- Phase 2B depends on Phase 2A's output.
- Phases 3, 4, 5 depend on Phase 2B.
- Phase 6 depends on Phase 2B and API key availability.
- Phase 7 depends on Phase 3–6.
- Phase 8 depends on Phase 3–7.
- Phase 9 depends on everything.

## Path C summary (for quick reference)

- **Direct-bwrap (no LLM):** FR2, FR3, FR4, FR5, FR7 — deterministic, fast.
- **Real query():** FR2-smoke, FR8, FR9 — full-stack test, LLM-dependent.
- **Out of scope:** FR10, FR11, FR12 — deferred or delegated to existing tier-2/3 tests.

## Out of Scope

- LS/NotebookRead tier-4 tests (Path C scope change — already tier-2/3 tested).
- FR12 Task subagent (deferred follow-up).
- Canary deploy-blocking wiring (deferred follow-up).
- FR8/FR9 gap fixes (filed per Phase 6.3 if leaks observed).
