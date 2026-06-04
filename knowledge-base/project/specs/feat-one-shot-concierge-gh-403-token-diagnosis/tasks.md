# Tasks — Fix Concierge GitHub 403 (wrong-installation token + false diagnosis)

> **/work reconciliation (2026-06-04).** Live reproduce (Phase 1.4, prod) REFINED
> the root cause: the connected repo is reachable by TWO installs — the org install
> 122213433 (`issues: write`) and a cross-account PERSONAL install 130018654
> (`issues: read`). BOTH return 200 on a plain repo GET, so the "403 on all GETs"
> hypothesis was false; the real cause is the personal install holding only
> `issues: read`, so `POST /issues` 403s. Fix is owner-matched installation
> SELECTION (account login == repo owner → org install, full grant). Two plan
> assumptions were superseded: (a) the proposed `findInstallationForRepo` is
> redundant — added the lighter, deterministic `findInstallationByAccountLogin`
> instead (the existing read-probe `resolveOwningInstallationForRepo` is
> INSUFFICIENT here because both installs pass the read probe); (b) connect-route
> edits (2.3) are unnecessary — the cc-dispatcher self-heal corrects + persists
> the installation on the next dispatch, fixing already-broken workspaces without
> a reconnect. Tests live at `test/*.test.ts` (not `test/server/`).

Plan: `knowledge-base/project/plans/2026-06-04-fix-concierge-github-403-wrong-installation-plan.md`
Lane: cross-domain
Brand-survival threshold: single-user incident (CPO sign-off required before /work)

> Phase order is load-bearing: Phase 1 (observability + reproduce) before Phase 2
> (selection fix). Phase 3 (messaging) may interleave.

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Confirm vitest node-test glob `test/**/*.test.ts` (`vitest.config.ts:44`);
      runner is `vitest` (`package.json:15`). Run via
      `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT `bun test`).
- [ ] 0.2 Read installed `findInstallationForLogin` (`github-app.ts:356-442`) and
      `mintAndExchange` (`:494-500`) — confirm personal-first ordering + no-perms-body mint.
- [ ] 0.3 Confirm `GitHubInstallationTokenResponse` is `{token, expires_at}`
      (`github-app.ts:74-77`) and its only consumer is github-app.ts.

## Phase 1 — Mint-time observability + reproduce

- [ ] 1.1 Widen `GitHubInstallationTokenResponse` with optional
      `repository_selection?: "all" | "selected"` + `permissions?: Record<string,string>`.
- [ ] 1.2 In `generateInstallationToken`, after `:550` JSON parse, `log.info` with
      `{installationId, repositorySelection, permissionKeys: Object.keys(...).sort(), appId}`.
      Assert `data.token` never appears in any `log.*` call.
- [ ] 1.3 Create `apps/web-platform/scripts/spike/reproduce-gh-403.ts`: mint via the
      runtime path for the affected workspace; `GET /installation/repositories` +
      read-probe `GET /repos/jikig-ai/soleur` (avoid issue residue); log full 403
      JSON body + permissions + repository_selection.
- [ ] 1.4 Run the harness; capture output proving `repository_selection` + 403
      `"Resource not accessible by integration"` against the org repo. Paste in PR body.

## Phase 2 — Repo-correct installation selection (root cause)

- [ ] 2.1 Add `findInstallationForRepo(owner, repo)` to `github-app.ts` —
      iterate app installations, mint each token, probe `GET /repos/{owner}/{repo}`,
      return first install whose token reads the repo. Mirror
      `findOrgInstallationForUser` loop (`:386-442`).
- [ ] 2.2 In `cc-dispatcher.ts` mint site (`:1113-1127`): if
      `repository_selection === "selected"` and connected repo absent from token set,
      re-resolve via `findInstallationForRepo`, re-mint, and (decision per PR)
      auto-heal `workspaces.github_installation_id` via service client. Else degrade
      honestly (no token that 403s) + emit Phase-3 structured signal.
- [ ] 2.3 In connect flows (`repo/install/route.ts`, `repo/setup/route.ts`,
      `repo/detect-installation/route.ts`) prefer `findInstallationForRepo` when
      owner/repo known; fall back to `findInstallationForLogin` only when no repo.
- [ ] 2.4 Test `test/server/find-installation-for-repo.test.ts`: returns org install
      when personal install token 403s on org repo; regression that
      `findInstallationForLogin` personal-first ordering preserved for no-repo case.

## Phase 3 — Honest 403 messaging

- [ ] 3.1 `github-api.ts handleErrorResponse` 403 branch: parse `bodyText` JSON,
      extract `message` + `documentation_url`, surface in `GitHubApiError`. Drop
      "approve new permissions"/"issues:write" text. Add
      `import { reportSilentFallback } from "@/server/observability";` and mirror 403.
- [ ] 3.2 Concierge system prompt (`cc-dispatcher.ts effectiveSystemPrompt`
      `:1238-1246`): directive — on `gh` 403, report literal output + status, do NOT
      speculate about missing scope/permission, do NOT tell users to change GitHub
      App permissions or re-consent. Verify the assembly site first.
- [ ] 3.3 Extend `test/server/github-api.test.ts`: 403 body
      `{"message":"Resource not accessible by integration"}` → `GitHubApiError`
      message contains the GitHub message, NOT "approve new permissions"/"issues:write";
      `reportSilentFallback` fires (mock).

## Phase 4 — Verify ACs

- [ ] 4.1 AC1-AC6 pre-merge (see plan). `git diff` touches NEITHER the manifest NOR
      any permission declaration (AC6 hard constraint).
- [ ] 4.2 Full suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
- [ ] 4.3 PR body: `Ref #N` (not `Closes`) for the source issue; AC7 closes
      post-deploy after the mint log confirms correct `repository_selection`.
