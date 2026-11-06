# Tasks — fix(security): batch-clear three js/shell-command-injection-from-environment CodeQL alerts (279, 302, 303)

Plan: `knowledge-base/project/plans/2026-11-03-fix-codeql-shell-injection-batch-plan.md`

## Phase 1 — Implementation

- [ ] 1.1 `plugins/soleur/scripts/harness-discovery-smoke.ts`: rewrite `resolveBin` as a pure-Node PATH walk (`accessSync` X_OK → `realpathSync`, fallback to candidate) — remove the `run("bash", ["-c", …])` call; add `accessSync`, `constants` to the fs import. (AC1)
- [ ] 1.2 `plugins/soleur/test/harness-discovery-smoke.test.ts`: extend the `resolveBin` describe with a shim-following assertion (fake exec on a PATH prefix symlinked → expect canonical realpath). (AC1)
- [ ] 1.3 `apps/web-platform/test/sdk-bash-probe-runtime.test.ts` line 418: write the HOME/TMPDIR writer script into the `scratch()` dir, spawn `sh <file> <fifo> <HOME>` — no `"-c"`. (AC2)
- [ ] 1.4 Same file line 473: same treatment for the cap.fifo writer, spawn `sh <file> <fifo>` — no `"-c"`. (AC3)

## Phase 2 — Verification

- [ ] 2.1 `bun test plugins/soleur/test/harness-discovery-smoke.test.ts` green. (AC7)
- [ ] 2.2 `cd apps/web-platform && npx vitest run test/sdk-bash-probe-runtime.test.ts` green. (AC7)
- [ ] 2.3 `grep -L -- '"-c"' <both files>` prints both paths (observability probe). (AC4)
- [ ] 2.4 Commits authored `Jean Deruelle <jean.deruelle@jikigai.com>`; PR body names alerts 279/302/303 with per-alert disposition, no `Closes`/`Fixes`/`Resolves`. (AC5, AC6)

## Phase 3 — Review / QA / Ship

- [ ] 3.1 `soleur:review` sequential-fallback panel + fix-round if findings.
- [ ] 3.2 `soleur:qa` on Test Scenarios (unit/integration — no browser/API surfaces).
- [ ] 3.3 `soleur:compound` then `soleur:ship` (semver label: patch; `## Changelog` in PR body; alert references not Closes lines).
