# Tasks — MU1 fixture repo + AC-2 wiring (#2605)

Derived from `knowledge-base/project/plans/2026-04-19-ops-mu1-fixture-repo-and-ac2-test-plan.md`.

## Phase 1 — Fixture repo (PAUSE FOR CONFIRMATION)

- [x] 1.1 Confirm with operator before creating the `jikig-ai/mu1-fixture` repo.
- [x] 1.2 `gh repo create jikig-ai/mu1-fixture --public --disable-issues --disable-wiki --description "MU1 AC-2 clone-verification fixture for jikig-ai/soleur. See #2605."`.
- [x] 1.3 Clone the new repo locally, add `README.md` and `knowledge-base/README.md` (content per plan "Files to Create"), commit, push.
- [x] 1.4 `gh repo edit jikig-ai/mu1-fixture --enable-projects=false --enable-discussions=false`.
- [x] 1.5 Verify AC-A: `gh repo view jikig-ai/mu1-fixture --json visibility,isArchived,description,hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled,hasDiscussionsEnabled`.

## Phase 2 — Install the `soleur-ai` App (PAUSE FOR CONFIRMATION)

- [x] 2.1 Confirm with operator before changing the App's install scope.
- [x] 2.2 Browser handoff: add `mu1-fixture` to the App's "Only select repositories" list at `https://github.com/organizations/jikig-ai/settings/installations` (page kept open for the operator; the only genuinely manual step).
- [x] 2.3 After install, fetch the repo-scoped installation id via `GET /repos/jikig-ai/mu1-fixture/installation` with an App JWT (built from `prd`-scoped `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`). Record the id.
- [x] 2.4 Verify AC-B: the fetched install has `app_slug = soleur-ai` and `repository_selection = "selected"`.

## Phase 3 — Doppler `dev` secrets (PAUSE FOR CONFIRMATION)

- [x] 3.1 Confirm with operator before any `doppler secrets set` call (widens dev surface for `GITHUB_APP_PRIVATE_KEY`).
- [x] 3.2 Copy `GITHUB_APP_ID` prd → dev via stdin pipe.
- [x] 3.3 Copy `GITHUB_APP_PRIVATE_KEY` prd → dev via stdin pipe (multiline-safe form).
- [x] 3.4 Set `MU1_FIXTURE_REPO_URL` in dev (`echo -n` piped, no trailing newline).
- [x] 3.5 Set `MU1_FIXTURE_INSTALLATION_ID` in dev (`echo -n` piped).
- [x] 3.6 Verify AC-C: four `doppler secrets get … --plain` reads match expected shapes. PEM must have real newlines (`wc -l > 1`).
- [x] 3.7 Smoke-test JWT signing from dev creds (`createSign("RSA-SHA256")`) — catches PEM encoding drift before the test runs.

## Phase 4 — AC-2 test block

- [x] 4.1 Replace the placeholder comment in `apps/web-platform/test/mu1-integration.test.ts` with a `describe.skipIf(...)` block titled exactly `MU1 AC-2: provisionWorkspaceWithRepo clones fixture`.
- [x] 4.2 Inside the block: assert `Number.isFinite` + `> 0` + `Number.isInteger` on the parsed installation id BEFORE invoking `provisionWorkspaceWithRepo`.
- [x] 4.3 Assert `README.md` exists, `.git/` exists, `plugins/soleur` symlink target is `PLUGIN_ROOT`.
- [x] 4.4 Reuse the existing `provisionedWorkspaces` array + `afterEach` cleanup — no new hooks.
- [x] 4.5 Update `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`: step 1 / step 2 expected-output lines, AC-2 row in "Acceptance Criteria Under Verification", fallback-section rename, remove `#2605` from "Known Deferrals".
- [x] 4.6 Verify AC-D locally: `cd apps/web-platform && MU1_INTEGRATION=1 doppler run -p soleur -c dev -- ./node_modules/.bin/vitest run test/mu1-integration.test.ts` passes with `6 passed, 0 skipped`.
- [x] 4.7 Verify AC-E locally: `cd apps/web-platform && ./node_modules/.bin/vitest run test/mu1-integration.test.ts` (no env) passes with `4 passed, 2 skipped`.

## Phase 5 — Follow-ups / ship

- [ ] 5.1 Run the open code-review overlap check (plan section "Open Code-Review Overlap") — expect zero matches.
- [ ] 5.2 Markdownlint the changed `.md` files (plan + runbook).
- [ ] 5.3 `/soleur:ship` to push, open PR, run review+compound gates.
- [ ] 5.4 PR body contains `Closes #2605`.
- [ ] 5.5 Post-merge: run updated runbook, attach output to #2605, close issue.
- [ ] 5.6 Post-merge: verify App install scope is still "Only select repositories" a week later (AC-G check from plan).
