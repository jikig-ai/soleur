# Tasks: pin the whole likec4 dependency tree (#9300)

Plan: knowledge-base/project/plans/2026-10-01-fix-ci-pin-likec4-transitive-deps-plan.md

Constraint: the PR edits `.github/workflows/ci.yml`. Do not admin-merge. Stop at green CI with the PR ready and report to the operator.

## Phase 1: Guard first (RED)

- [ ] 1.1 In `apps/web-platform/test/c4-likec4-version-pin.test.ts`, add a pure `checkLikec4Pins(files, now)` returning violations.
- [ ] 1.2 Comment-strip each file before extraction; workflows: every non-comment `npm install -g likec4@<digit>` line needs `--before=<D>`.
- [ ] 1.3 `render-c4-model.sh` and `generate-c4-from-components.ts`: extract the single non-comment `export json` line and assert the flag; exclude the three `validate` hint lines.
- [ ] 1.4 Assert one `<D>` across all sites, `LIKEC4_BEFORE` parity in the shell script and `c4-from-components.ts`, valid `YYYY-MM-DD`, at least 3 days old (UTC, injected `now`), site count > 0.
- [ ] 1.5 Failure message prints the bump procedure and `npm view likec4@<version> time --json`.
- [ ] 1.6 String-fed self-test cases for the Guard Contract rows 1-6, harness row (a) (first-match scanner turns row 1 red) and the must-PASS row (all sites moved to another valid old date).
- [ ] 1.7 Fix the stale "THREE install lines" comment in this test.
- [ ] 1.8 Add the date parity assertion to `plugins/soleur/test/c4-from-components.test.ts` beside `LIKEC4_VERSION`.
- [ ] 1.9 Run the suite against unmodified sites; capture the RED output for the PR body.

## Phase 2: Pin the sites (GREEN), D = 2026-09-28

- [ ] 2.1 `.github/workflows/ci.yml`: add `--before=2026-09-28` to the three `Install likec4 CLI` steps; shrink the header NOTE and bullet to a pointer; keep the full install command string out of comments.
- [ ] 2.2 `.github/workflows/main-health-monitor.yml`: same flag as a literal; update the TOOLCHAIN PINS count and note that the date is literal-only.
- [ ] 2.3 `plugins/soleur/scripts/render-c4-model.sh`: `LIKEC4_BEFORE="2026-09-28"`, flag on the `npx` line (same line as `export json`), and the `BUMPING LIKEC4` header section (procedure, policy, mirror failure mode).
- [ ] 2.4 `plugins/soleur/lib/c4-from-components.ts`: export `LIKEC4_BEFORE`.
- [ ] 2.5 `plugins/soleur/scripts/generate-c4-from-components.ts`: import it, add `--before=${LIKEC4_BEFORE}` to the argv on the `export json` line, one comment sentence.

## Phase 3: Verify

- [ ] 3.1 Run `c4-likec4-version-pin`, `render-c4-model.test.sh`, `c4-from-components.test.{sh,ts}`, `c4-canonical.test.ts`, `c4-model-freshness.test.sh`, `scripts-shard-runtime-coverage.test.sh`.
- [ ] 3.2 Re-run the byte-identical render check against the committed `model.likec4.json`.
- [ ] 3.3 Confirm `generate-c4-from-components.ts` surfaces npm stderr on a resolution failure; record cold-cache before/after timing in the PR body.
- [ ] 3.4 `git diff --quiet origin/main...HEAD -- apps/web-platform/Dockerfile apps/web-platform/package.json` exits 0.
- [ ] 3.5 PR body: `Closes #9300`, RED output, Phase 4 issue link, the decision-challenges items. Push, wait for green CI, leave the PR open (no admin merge).

## Phase 4: Deferral

- [ ] 4.1 File one issue for the Dockerfile transitives (likec4 and claude-code) and the vestigial test-scripts installs; milestone from the roadmap; reference it in the PR.
