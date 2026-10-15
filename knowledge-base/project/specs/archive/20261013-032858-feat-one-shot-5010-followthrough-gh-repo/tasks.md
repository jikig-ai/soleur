# Tasks — fix(cron): buildSpawnEnv missing GH_REPO (#5010)

Plan: `knowledge-base/project/plans/2026-06-08-fix-cron-follow-through-gh-repo-plan.md`
Lane: cross-domain (no spec.md; TR2 fail-closed default)

## Phase 0 — Preconditions (re-verify at /work)

- [ ] 0.1 `grep -n 'REPO_OWNER\|REPO_NAME' apps/web-platform/server/inngest/functions/_cron-shared.ts` → both exported (`"jikig-ai"` / `"soleur"`).
- [ ] 0.2 Re-read import block + `buildSpawnEnv` in `cron-follow-through-monitor.ts` (~L77-91, L268-276) and `cron-daily-triage.ts` (~L177-185); line numbers may have drifted.
- [ ] 0.3 Confirm both crons still have zero clone/`cwd:` (`grep -c 'clone\|cwd:' <file>` = 0).

## Phase 1 — RED (failing tests first)

- [ ] 1.1 Add **T8** to `test/server/inngest/cron-follow-through-monitor.test.ts`, modeled on T7 (L250-290): capture execFileSync env, claude-eval spawn env, and each ensure-labels `gh` spawn env; assert `.GH_REPO === "jikig-ai/soleur"` on all three.
- [ ] 1.2 Add a mirrored `GH_REPO` assertion to `test/server/inngest/cron-daily-triage.test.ts` (extend its GH_TOKEN env-capture test, or add an env-capture test if none).
- [ ] 1.3 Run both suites; confirm the new assertions FAIL (RED).

## Phase 2 — GREEN (one-line fix per file)

- [ ] 2.1 `cron-follow-through-monitor.ts`: extend `./_cron-shared` import with `REPO_OWNER, REPO_NAME`; add `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`,` to `buildSpawnEnv`; update allowlist comments (L257-259, L51-52) to list `GH_REPO`.
- [ ] 2.2 `cron-daily-triage.ts`: same import + `GH_REPO` field + comment edits.
- [ ] 2.3 Run both suites → GREEN.

## Phase 3 — Full-suite + types

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` (covers both crons + substrate-import + registry-count guards).
- [ ] 3.2 `tsc --noEmit` clean.

## Phase 4 — Ship + post-merge verify

- [ ] 4.1 PR body: `Closes #5010` (fix is test-verified; no post-merge prod write required to close).
- [ ] 4.2 Post-merge: read-only Sentry monitor check — `scheduled-follow-through` (id `3f5e80d3-e527-442f-94c2-f3d4e65a6c61`) flips OK on next `0 9 * * 1-5` run; `scheduled-daily-triage` flips OK on next `0 4 * * *` run; `WEB-PLATFORM-W` stops firing. Pull status via Sentry API (no dashboard-eyeball, no ssh).

## Guard reminders (Sharp Edges)

- Relative `./_cron-shared` import ONLY (substrate-import guard regex matches relative form).
- vitest runner (`./node_modules/.bin/vitest run`), not bun; test files under `test/**/*.test.ts`.
- Keep allowlist comment in sync with the `buildSpawnEnv` body.
- `GH_REPO` is a static constant — do NOT fold it into the GH_TOKEN ambient-override test invariant.
