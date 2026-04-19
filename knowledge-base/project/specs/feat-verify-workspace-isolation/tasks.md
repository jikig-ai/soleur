# Tasks: Cross-Workspace Isolation Integration Suite (MU3)

**Plan:** `knowledge-base/project/plans/2026-04-18-test-cross-workspace-isolation-mu3-plan.md`
**Spec:** `knowledge-base/project/specs/feat-verify-workspace-isolation/spec.md`
**Issue:** #1450 | **PR:** #2610 | **Branch:** feat-verify-workspace-isolation

## Phase 1 — Invocation-path decision spike

- [ ] 1.1 Pick deterministic tier-4 invocation path (SDK direct-tool entry → `spawn("bwrap", argv)` with captured argv → `query()` with model-compliance caveat, in that order). Document choice in sdk-probe-notes.md.
- [ ] 1.2 Verify structured-path tool validators (LS, NotebookRead): do they reject cross-workspace paths before bwrap under `permissionMode: "bypassPermissions"` + no hooks?
- [ ] 1.3 Write `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md` (chosen path, shape, tier attribution of structured-path tools, pinned SDK version at probe time).
- [ ] 1.4 Amend plan Phases 3–6 inline if spike picked spawn-bwrap or query() paths.
- [ ] 1.5 Ensure `apps/web-platform/scripts/sdk-probe.*` is in `.gitignore`; `git rm` the probe script if it slipped in.

## Phase 2 — Fixture helpers

- [ ] 2.1 Create `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` with: `createWorkspacePair`, `seedMarker`, `linkEscape`, `spawnSandboxB`, `rescueStaleFixtures` (with TMPDIR-prefix blast-radius assertion), `probeSkip`.
- [ ] 2.2 Pure Node imports only (`fs`, `os`, `path`, `child_process`) — no SDK.
- [ ] 2.3 Verify fixtures compile (`./node_modules/.bin/tsc --noEmit` in `apps/web-platform`).

## Phase 3 — Smoke test + TDD inversion

- [ ] 3.1 Create `apps/web-platform/test/sandbox-isolation.test.ts` with 3-line top-of-file tier-4 comment.
- [ ] 3.2 Implement `runInSandbox(workspacePath, opts)` — one parameterized helper. Config: `permissionMode: "bypassPermissions"`, `hooks: {}`, `settingSources: []`, `disallowedTools: []`, sandbox config per Phase 1 choice.
- [ ] 3.3 Write FR2 (direct read denial) assertion, wrapped in setup-failure try/catch.
- [ ] 3.4 TDD inversion: temporarily relax sandbox config to include `rootB` in `allowWrite`; confirm test fails with marker in stdout; revert; confirm test passes. Commit inversion evidence separately.
- [ ] 3.5 Run vitest, confirm green. Push.

## Phase 4 — Adversary cases (tier-4-isolatable)

- [ ] 4.1 FR3 direct write denial.
- [ ] 4.2 FR4 prefix-collision (`tenant` vs. `tenant-evil`).
- [ ] 4.3 FR5 symlink escape (realpath canonicalization).
- [ ] 4.4 FR10 LS tool — annotate tier (2 vs 4) per Phase 1 findings.
- [ ] 4.5 FR11 NotebookRead — same annotation.

## Phase 5 — Concurrent sandbox

- [ ] 5.1 FR7 `/proc/<pid>/environ` via `spawnSandboxB` long-running child; READY handshake; marker env; cross-sandbox read attempt; SIGTERM cleanup.
- [ ] 5.2 FR12 Task subagent deferred — file follow-up issue if a deterministic verification approach surfaces.

## Phase 6 — Shared-surface audit (correct sequencing)

- [ ] 6.1 FR8 shared `/tmp`: write as isolation proof (`expect(…).not.toContain(marker)`) with setup-failure guard.
- [ ] 6.2 FR9 SDK session files: same isolation-proof pattern.
- [ ] 6.3 Run full suite, branch on observed result:
  - All green → update `knowledge-base/product/roadmap.md` MU3 row + `## Current State` to Done; PR body notes MU3 closes on merge.
  - Any leak → `gh issue create` per leaking case (`priority/p1-high`, `type/security`, `domain/engineering`, milestone `Pre-Phase 4: Multi-User Readiness Gate`) → invert that case's assertion and wrap in `test.fails({ todo: '#<issue>' })`. No `#TBD` placeholders.
- [ ] 6.4 Add top-of-file lint: any `test.fails({ todo: '#TBD…' })` throws at test-load.

## Phase 7 — Coverage guard

- [ ] 7.1 Declare `COVERAGE: Record<string, string>` in test file; keys = all known path-accepting tools.
- [ ] 7.2 Assert `Object.keys(COVERAGE).sort()` equals the expected tool list exactly.
- [ ] 7.3 Add comment above: review on SDK minor bump.

## Phase 8 — Canary integration

- [ ] 8.1 Append `assert_cross_workspace_isolation` to `apps/web-platform/infra/ci-deploy.test.sh`: precondition `docker inspect`, `timeout 300 docker exec … vitest run test/sandbox-isolation.test.ts`, exit-code disambiguation.
- [ ] 8.2 Verify `/app/node_modules/.bin/vitest` exists in canary image; amend `apps/web-platform/Dockerfile` only if missing.
- [ ] 8.3 File follow-up `feat: promote cross-workspace isolation check to deploy gate` (P2) — do NOT wire into deploy-blocking path in this PR.

## Phase 9 — Pre-merge sweep

- [ ] 9.1 `ANTHROPIC_API_KEY` present in repo secrets OR documented operator task in PR body.
- [ ] 9.2 All AC1–AC6 checkboxes ticked in PR description.
- [ ] 9.3 `npx markdownlint-cli2 --fix` on all changed `.md`.
- [ ] 9.4 `git push` before invoking `/soleur:review`.
- [ ] 9.5 Run `/soleur:review`; resolve findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 9.6 Run `/soleur:compound` before final commit; then `/ship`.

## Dependencies

- Phase 2 depends on Phase 1 (helpers can use probed assumptions, but don't import SDK).
- Phase 3 depends on Phase 1 (invocation path) AND Phase 2 (fixtures).
- Phases 4–7 depend on Phase 3 (harness + inversion proof).
- Phase 8 depends on Phases 3–7 (test file must exist and pass locally).
- Phase 9 depends on everything above.

## Out of Scope (already captured as follow-ups or excluded)

- FR12 Task subagent cross-workspace test (Phase 5.2)
- Promotion of canary assertion to deploy-blocking path (Phase 8.3)
- FR8/FR9 gap fixes (filed per Phase 6.3 if leaks observed)
