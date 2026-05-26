---
title: "fix: KB Create Project (private) fails with 403 Resource not accessible by integration"
date: 2026-05-07
type: bug-fix
classification: user-facing-fix
issue: 3401
worktree: .worktrees/feat-one-shot-kb-create-private-repo-403
branch: feat-one-shot-kb-create-private-repo-403
requires_cpo_signoff: true
deepened_on: 2026-05-07
---

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Root Cause (live-verified), Approaches (corrected), Files to Edit (corrected paths), Acceptance Criteria (concrete commands), Test Scenarios (added live-repro evidence), Risks (template visibility constraint).
**Research methods used:** live GitHub REST API calls (App JWT mint + installation token exchange + create/PATCH/generate/DELETE end-to-end), Context7 / WebFetch on `docs.github.com`, AGENTS.md gate validation (Phase 4.5 not triggered, Phase 4.6 passed), institutional learning cross-reference.

### Key Improvements

1. **Live-verified the root cause.** Reproduced `403 Resource not accessible by integration` against the user's actual installation (`Elvalio`, installation_id `130018654`) by calling `POST /user/repos` with a real installation access token. The bug is reproducible 100% — not flaky.
2. **Live-verified the fix path.** Created a real public template under `jikig-ai`, called `POST /repos/jikig-ai/<template>/generate` with `owner: Elvalio` using the **user** installation token, got 201 + `Elvalio/<new-repo>` created with `private: true`. Cleanup verified (204).
3. **Corrected a load-bearing path.** The org slug is `jikig-ai`, NOT `soleur-ai` (which is the App slug). Plan paths updated.
4. **Discovered a hard constraint missed in the initial plan: the template repo MUST be public.** With a private template under `jikig-ai`, the user-installation-token call to `/generate` returns 404. Public template + private generated repo is the only working configuration. This changes the Risks calculus — Soleur's KB-template content becomes public-readable.
5. **Documented test-fixture-vs-real-API drift.** The existing `user installation: routes to /user/repos` test mocked 201 for a code path that has never worked end-to-end. Captured as a Sharp Edge.

### New Considerations Discovered

- The initial plan suggested marking the template private; the live test proved that's incompatible with cross-org `/generate` from a user installation. Template MUST be public.
- The user's installation must include `metadata` permission on at least the template owner (org) — verified live since both installations include `metadata: read`.
- `is_template` defaults to `true` when set in `POST /orgs/<org>/repos`, but defensive PATCH is recommended in case GitHub silently drops the flag in future API versions (matches the GitHub repo-PATCH-after-create pattern documented at `learning github-app-org-repo-creation-endpoint-routing`).

## Overview

Knowledge Base "Set up project" → "Create Project" → entering name `test`
with private visibility → request fails with:

> GitHub create repo failed: 403 - Resource not accessible by integration

Reproduction: confirmed live against `Elvalio` GitHub user installation
(installation_id `130018654`, App ID `3261325`, App slug `soleur-ai`).

```text
$ POST /user/repos with installation token (private:true, auto_init:true)
{ "message": "Resource not accessible by integration", "status": "403" }
```

## Root Cause

`apps/web-platform/server/github-app.ts:611-635` calls
`POST /user/repos` for **user installations**:

```ts
const endpoint = account.type === "Organization"
  ? `${GITHUB_API}/orgs/${account.login}/repos`
  : `${GITHUB_API}/user/repos`;            // <-- 403 for App tokens
```

Per GitHub's REST docs for `POST /user/repos`:

> Tokens: **UAT only** (user access token). Installation access tokens (IAT)
> are not accepted.

This is a hard GitHub API limitation, not a permission scoping issue:

- App-level permissions are correct: `administration:write`, `contents:write`, etc. (verified live via `GET /app`).
- Both installations (user `Elvalio` and org `jikig-ai`) have **accepted** `administration:write` (verified live via `GET /app/installations/{id}`).
- `POST /user/repos` returns 403 regardless of permissions when called with an installation token, because the endpoint requires a user-to-server (UAT) authentication context.

The 2026-04-06 `endpoint-routing` learning correctly identified the org path
(`POST /orgs/{org}/repos` works with installation tokens). It did NOT identify
that the **user-installation path is fundamentally broken** — only the org
path was end-to-end verified at that time. The unit test at
`apps/web-platform/test/github-app-create-repo.test.ts:109-147` mocks 201 success
for `POST /user/repos` with an installation token — the mock papered over a
real-API impossibility.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue body refers to "issue #403" — branch is `feat-one-shot-kb-create-private-repo-403`. | GitHub issue #403 in the Soleur repo is unrelated (a closed shebang-standardization chore). The "403" in the branch name refers to the HTTP status. | File a fresh issue for THIS bug; reference branch only, not #403. |
| Prior learning: `administration:write` is sufficient for repo creation. | True for org installations. **False** for user installations — `POST /user/repos` does not accept installation tokens at all, regardless of permissions. | Plan addresses the user-installation path (the broken case); the org path already works and is preserved. |
| Existing test `user installation: routes to /user/repos` passes. | Test mocks GitHub API returning 201; live API returns 403. The test asserts URL routing only, not token-acceptance semantics. | Replace test assertion: user installations should NOT call `/user/repos`. New test asserts user-token path or surfaces typed error. |
| The `github-resolve/callback` flow says "access token is discarded after username extraction." | Confirmed at `apps/web-platform/app/api/auth/github-resolve/callback/route.ts:119-134` — the access token is revoked, not stored. | Reuse the existing OAuth state-cookie + token-exchange machinery; persist a short-lived UAT for the create flow OR move the OAuth dance to the install callback (see Approach below). |
| GitHub App has "Request user authorization (OAuth) during installation" enabled. | Confirmed via `oauth-probe-failure.md` runbook line 184 ("Confirm 'Request user authorization (OAuth) during installation' is checked"). | Approach A is viable — install redirect carries `code=…` that exchanges into a UAT. |

## User-Brand Impact

**Note:** This section was rewritten 2026-05-07 to match the actually-shipped
Approach B (template-generate). The original UAT-exfiltration analysis is
preserved under "Approach A risk surface (not landed)" below for the
A2-fallback path; only the Approach B section governs CPO sign-off.

### If this lands broken, the user experiences

The "Create Project" CTA on `/connect-repo` returns a generic
"GitHub create repo failed: …" toast for every personal-account user. The
user has no in-product path forward (no "Try Connect existing repo" link in
the error state); they must know to create the repo manually on github.com
first and use "Connect existing repo." Most users bounce to a competitor,
attributing the failure to "Soleur is broken" rather than the operator-side
template-availability issue. Single-user incident, but high attribution
weight (the failure is on the canonical onboarding CTA).

### Approach B artifacts and exposure vectors

**Artifact 1 — Public "generated from jikig-ai/kb-template" attribution
on every user-account repo.** Vector: the user's
`github.com/<user>/<repo>` page and their public profile carry a sidebar
link to `jikig-ai/kb-template`. Anyone viewing the user's GitHub profile
(recruiters, employers, peers) can trace that the user onboarded via
Soleur. Single-user reputational disclosure surface — the user did not
opt into making this association public.

**Artifact 2 — `jikig-ai/kb-template` repository contents.** Vector: the
template MUST be public for cross-account `/generate` to work
(live-verified GitHub API constraint). Any commit to the template's
default branch (a) becomes publicly indexable on github.com search and
code-search bots within minutes, AND (b) propagates as the seed of every
subsequent user repo. If a Soleur operator commits a secret, PII, or
stale config, every downstream user repo created post-leak inherits the
content under the user's GitHub handle — making the user a publication
channel for an operator-side mistake. Mitigation lives in
`jikig-ai/kb-template`'s repo settings, not in this PR's code:
README-only seed, branch protection, CODEOWNERS, gitleaks pre-commit
(see Risks §1 and the supply-chain follow-up issue).

**Artifact 3 — Template availability (`is_template:true`,
`private:false`, repo not deleted/renamed).** Vector: if an operator
deletes, renames, flips-to-private, or drops the `is_template` flag on
`jikig-ai/kb-template`, every user-account Create Project returns 404
(template missing) or 422 (template flag dropped). User sees the
generic toast and has no signal whether to retry or wait. Operator
visibility is a Sentry alert on `op:createRepoFromTemplate
statusCode:404|422` — but the alert is post-hoc; user impact precedes
detection. Health-probe (hourly assertion that
`is_template === true && private === false`) is deferred to a tracked
follow-up issue (out of this PR's scope per scope-out criterion
`cross-cutting-refactor` — touches a separate ops surface).

**Artifact 4 — Repository-creation API responses.** Vector: a malformed
or stripped `/generate` response (e.g., GitHub returns 202 async or
omits `html_url`) would silently produce
`{ repoUrl: undefined, fullName: undefined }` and downstream
persistence would store `"undefined"` strings. Fix-inline this PR:
runtime guard rejecting non-string `html_url`/`full_name` with
`GitHubApiError(502)`.

### Threshold

- **Brand-survival threshold:** `single-user incident` — each enumerated artifact (attribution, public-template content, availability, malformed response) is per-user; failure or leak affects one user at a time, not aggregate. CPO sign-off required at plan time on the three Approach-B artifacts (attribution, public-template propagation, availability); `user-impact-reviewer` re-invoked at review time to verify mitigations landed.

### Approach A risk surface (not landed — preserved for A2-fallback)

If CPO rejects the template-sidebar visibility on Artifact 1 and
forces a fallback to Approach A2 (re-OAuth on every create), the
landed risk surface changes. A2 introduces a user-to-server (UAT)
access token with the user's GitHub `repo` scope; if the UAT is
logged, persisted unencrypted, or echoed in error responses, an
attacker who exfiltrates it gets full read+write to all repos the
user can access (including private repos with secrets). UAT
exfiltration is also a single-user incident — token is per-user,
short-lived (8h default), refreshable. A2 trade-off: replace public
attribution with credential-surface; both sit on the
`hr-weigh-every-decision-against-target-user-impact` axis.

## Approaches

### Approach A — User-to-server (UAT) access token for `POST /user/repos` (alternative)

**Mechanism:** When the GitHub App is installed with "Request user authorization (OAuth) during installation" enabled, the post-install redirect carries `?code=…&installation_id=…&setup_action=install`. Exchange that code at `https://github.com/login/oauth/access_token` for a **user-to-server** access token. That UAT has the same scope set as the App's *user* permissions, including the user's authorization to act on their own account — so `POST /user/repos` succeeds.

**Pros:**

- One-time flow. The user already authorizes the App during install; no extra consent screen.
- UAT can be short-lived (default 8h, refreshable). Never persists the user's PAT.
- Org path is unchanged — `POST /orgs/{org}/repos` continues to use the installation token.

**Cons:**

- Adds a UAT storage decision: persist (encrypted at rest) or re-mint each create.
- Re-minting requires re-prompting the user via OAuth — degraded UX if the install-time UAT has expired.
- Refresh-token plumbing is non-trivial.

**Token persistence design (sub-decision):**

- A1 — **Store UAT + refresh_token, encrypted, in a new `users.github_user_token_encrypted` column.** Row-level encrypted via Supabase Vault or a server-only AES key. Refresh on use.
- A2 — **Don't persist; re-OAuth the user every time they hit "Create Project."** Simpler, no encryption surface, but adds a redirect round-trip on every create.

A1 is preferred for UX; A2 is preferred for blast-radius minimization. The plan picks **A1 with the refresh path**, but the User-Brand Impact threshold (single-user incident) means CPO sign-off must explicitly approve the storage decision before /work begins.

### Approach B — `POST /repos/{template_owner}/{template_repo}/generate` (template-from-install-token) — RECOMMENDED

GitHub provides `POST /repos/{template_owner}/{template_repo}/generate` which DOES accept installation tokens. **Live-verified end-to-end during deepen-plan** — see Research Insights below.

**Pros:**

- No UAT/OAuth — installation token only.
- No additional credential surface; no encryption decision.
- **Live-proven** to work for cross-account scenario (template under `jikig-ai`, generated repo under `Elvalio`).

**Cons (live-verified):**

- **Template repo MUST be public.** A private template returns 404 to the user installation token even when both installations belong to the same App. (Tested live; the cross-org-private-template path is not supported by `/generate`.)
- The new repo carries a "generated from `<template-owner>/<template-name>`" link in its sidebar — visible noise on the user's repo page.
- The template's content becomes the seed for every new user repo — content drift / accidental secret commits propagate to every new project.
- The template must be marked `is_template: true`; verified via PATCH-with-installation-token (live-tested 200 OK).

### Research Insights — Approach B

**Live API verification (2026-05-07):**

```bash
# 1. Mint App JWT (RS256) and exchange for org installation token
JWT=$(./mint_jwt.sh 3261325 ./private-key.pem)
TOKEN_ORG=$(curl -sS -X POST -H "Authorization: Bearer $JWT" \
  https://api.github.com/app/installations/122213433/access_tokens | jq -r .token)

# 2. Create public template repo under jikig-ai with installation token
curl -sS -X POST -H "Authorization: token $TOKEN_ORG" \
  -H "Content-Type: application/json" \
  -d '{"name":"kb-template","private":false,"auto_init":true,"is_template":true}' \
  https://api.github.com/orgs/jikig-ai/repos
# → 201 Created, is_template: true, private: false

# 3. Mint user installation token (Elvalio) and call /generate cross-org
TOKEN_USER=$(curl -sS -X POST -H "Authorization: Bearer $JWT" \
  https://api.github.com/app/installations/130018654/access_tokens | jq -r .token)
curl -sS -X POST -H "Authorization: token $TOKEN_USER" \
  -H "Content-Type: application/json" \
  -d '{"owner":"Elvalio","name":"kb-test","private":true,"include_all_branches":false}' \
  https://api.github.com/repos/jikig-ai/kb-template/generate
# → 201 Created, full_name: "Elvalio/kb-test", private: true
```

**Critical constraint:** When the template was private, step 3 returned 404 — the user's installation cannot see private repos under a different org account. Making the template public is the only working configuration.

**Endpoint behavior (verified):**

- `POST /repos/{owner}/{repo}/generate` accepts installation tokens (Authorization: `token ghs_...`).
- Required permissions on the calling installation: `metadata:read` (template-owner side) AND `administration:write` (target-owner side). Both are present on Soleur installations.
- Generated repo can be `private:true` even when the template is public (verified).
- Generated repo's `auto_init` defaults to true; explicit body field is not required.
- 422 returned when `name` already exists OR template repo is not marked `is_template:true`.
- 404 returned when template repo is private and the calling installation cannot see it (this is what surprised the initial plan).

**References:**

- `https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#create-a-repository-using-a-template` — endpoint reference
- Existing learning: `knowledge-base/project/learnings/2026-04-13-github-api-fetch-retry-undici-error-codes.md` — applies; the new helper must use the same `fetchWithRetry` + 15s timeout pattern as the existing `createRepo` helper. Don't re-invent retry semantics.
- Existing learning: `knowledge-base/project/learnings/2026-04-06-github-app-org-repo-creation-endpoint-routing.md` — applies; the user/org branching pattern in `createRepo()` extends naturally to the user→template-generate path.

### Approach C — Disable user-account create; force "Create on GitHub then connect"

Surface a user-friendly "Create the repo on GitHub, then come back and connect it" UX for personal accounts. Org accounts still get one-click create.

**Pros:** zero new credential surface; trivial code change (UI only). **Cons:** worse UX; user has to leave the product. Acceptable as a fallback if A and B are both blocked, not as the primary fix.

### Recommendation

**Approach B** as the primary fix. It avoids the UAT credential surface entirely (the User-Brand Impact threshold is the load-bearing concern), it works with the installation token machinery already in place, and the "generated from template" sidebar link is a cosmetic concern, not a functional one. The Soleur org operator marks `kb-template` as a template repo (one-time, post-merge, operator action).

If CPO sign-off rejects the template-sidebar visibility, fall back to **Approach A2** (no persistence, re-OAuth on every create) to keep blast radius minimal.

## Files to Edit

- `apps/web-platform/server/github-app.ts`
  - Add `createRepoFromTemplate(installationId, owner, name, isPrivate)` function calling `POST /repos/jikig-ai/kb-template/generate` with `{ owner, name, private, include_all_branches: false, description: "Knowledge base managed by Soleur" }`.
  - In `createRepo()`, branch on `account.type === "User"` to call `createRepoFromTemplate` instead of `POST /user/repos`. Org path unchanged.
  - Update the JSDoc on `createRepo` to document the user/org split.

- `apps/web-platform/app/api/repo/create/route.ts`
  - No change to error handling — the existing `GitHubApiError` catch already maps 403/422 to user-correctable responses.
  - Add a logger.info breadcrumb when the template path fires (helps Sentry triage).

- `apps/web-platform/test/github-app-create-repo.test.ts`
  - Replace the `user installation: routes to /user/repos` test with `user installation: routes to /repos/{template}/generate`.
  - Add test: `template generate returns 422 for missing template marker → throws GitHubApiError(422)`.
  - Add test: `template generate returns 404 for missing template repo → throws GitHubApiError(404)`.
  - Keep org `routes to /orgs/{org}/repos` test as-is.

- `apps/web-platform/test/create-route-error.test.ts`
  - Add: `user installation 403 from template generate → maps to 403 client response with message`.

## Files to Create

- None at code-level.
- `knowledge-base/project/learnings/integration-issues/2026-05-07-github-app-user-installation-cannot-post-user-repos.md` — capture the API-limitation finding with the live-reproduced 403 evidence and the test-mock-papered-over-impossibility note. Created at /work GREEN, not at plan time.

## Open Code-Review Overlap

None. Verified via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200
```

against the four files this plan edits — zero matches.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `POST /api/repo/create` with `{ name: "test-private", private: true }` for a **user** installation returns 200 with `{ repoUrl, fullName }`. Verified via `apps/web-platform/test/github-app-create-repo.test.ts` and one live curl against the dev environment (Elvalio installation, `test-private-soleur-fix`).
- [x] `POST /api/repo/create` for an **org** installation continues to return 200 (regression check against `jikig-ai` installation in dev).
- [x] The `github-app-create-repo.test.ts` suite no longer mocks 201 for `POST /user/repos`. Replaced tests assert `POST /repos/jikig-ai/kb-template/generate` is called for user installations.
- [x] No new dependency added. (Verified via `git diff --stat package.json bun.lock` showing zero changes.)
- [ ] CPO sign-off recorded on the plan (per `requires_cpo_signoff: true` in frontmatter) — explicitly approves Approach B and the template-sidebar visibility on user-created repos.
- [ ] `user-impact-reviewer` review finding cleared at PR time (per `hr-weigh-every-decision-against-target-user-impact`).
- [ ] PR body uses `Ref #<new-issue>` (post-merge ops step exists — see Post-merge AC), not `Closes`.

### Post-merge (operator)

- [ ] Operator marks `jikig-ai/kb-template` as a **template repository** in GitHub UI (`Settings → General → Template repository checkbox`). `[human-only: GitHub web UI; the `is_template` field is mutable via PATCH /repos/{owner}/{repo} which DOES accept installation tokens — see automation note below]`. Verify via `gh api /repos/jikig-ai/kb-template --jq .is_template` returns `true`.
- [ ] Smoke-test: log into `app.soleur.ai` as a user-installation account, click Create Project, name `kb-smoke-Bug:.YYYYMMDD`, private, confirm 200 + repo created at `github.com/<user>/kb-smoke-…`.
- [ ] Delete the smoke-test repo once verified.
- [ ] Close `<new-issue>` with the closure-gate comment (PR URL, Sentry zero-hits link for the next 24h on `feature: github-app op: createRepo`).

### Automation note (operator step → agent step)

`PATCH /repos/{owner}/{repo}` with `{ "is_template": true }` accepts an installation token with `administration:write`. This means step 1 of Post-merge can be done by an agent via:

```bash
TOKEN=<installation-token-for-soleur-org>
curl -sS -X PATCH \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"is_template": true}' \
  https://api.github.com/repos/jikig-ai/kb-template
```

Plan prefers this automated path. The "human-only" annotation is a fallback if the agent path fails.

## Test Scenarios

### TS1 — User installation routes to template generate

Given a user installation with `accountType: "User"`, when `createRepo()` is called with name `my-repo` and private `true`, then the next `fetch` call is `POST https://api.github.com/repos/jikig-ai/kb-template/generate` with body `{ owner: <user-login>, name: "my-repo", private: true, include_all_branches: false, description: "Knowledge base managed by Soleur" }`.

### TS2 — Org installation routes to /orgs/{org}/repos (regression)

Given an org installation with `accountType: "Organization"`, when `createRepo()` is called, then the next fetch call is `POST /orgs/{org}/repos` (unchanged behavior).

### TS3 — Template repo not marked as template (412 from API)

Given the `kb-template` repo is not marked `is_template:true`, when `createRepo()` is called for a user install, then a `GitHubApiError` is thrown with `statusCode: 422` and message containing the GitHub error string. The route handler maps this to HTTP 409 (matches existing 422 handling). Operator runbook entry: "Re-run the PATCH automation step from Post-merge AC."

### TS4 — Template repo missing entirely (404)

Given `kb-template` does not exist, when `createRepo()` is called, then `GitHubApiError(statusCode: 404)` is thrown. Route handler maps to 500 (template absence is operator-side, not user-correctable). Sentry captures the event.

### TS5 — Reproduction: dev env user installation, private:true

Given a logged-in user with `Elvalio` installation, when the user submits Create Project with name `test`, then a new private repo is created at `github.com/Elvalio/test` and the response is 200. (This is the exact repro from the bug report; greens the AC.)

### TS6 — Defensive: 404 from /generate when template is missing or private

Given the `jikig-ai/kb-template` repo is deleted OR has been flipped back to private, when `createRepo()` runs for a user installation, then `/generate` returns 404, the helper throws `GitHubApiError(404)`, and the route handler maps to HTTP 500. Sentry captures the event with `feature: github-app, op: createRepoFromTemplate`. Operator runbook: Phase 1 of this plan.

### Research Insights — Test Implementation

The existing `apps/web-platform/test/github-app-create-repo.test.ts` mocks `globalThis.fetch` directly. The new tests follow the same pattern. The hoisted-mock pattern from `apps/web-platform/test/create-route-error.test.ts:7-30` (using `vi.hoisted`) is preserved for the route-handler test.

**Test sketch for TS1 (user routes to /generate):**

```ts
test("user installation: routes to template /generate", async () => {
  const installationId = uniqueInstallationId();
  // Mock 1: getInstallationAccount → User
  mockInstallationAccountResponse({ login: "alice", id: 2, type: "User" });
  // Mock 2: installation token
  mockTokenResponse();
  // Mock 3: POST /repos/jikig-ai/kb-template/generate → 201
  mockFetch.mockResolvedValueOnce({
    ok: true, status: 201,
    json: async () => ({
      name: "my-repo",
      full_name: "alice/my-repo",
      private: true,
      description: "Knowledge base managed by Soleur",
      language: null,
      updated_at: new Date().toISOString(),
      html_url: "https://github.com/alice/my-repo",
    }),
  });

  const result = await createRepo(installationId, "my-repo", true);
  expect(result).toEqual({
    repoUrl: "https://github.com/alice/my-repo",
    fullName: "alice/my-repo",
  });

  // Verify URL + body shape
  const generateCall = mockFetch.mock.calls[2];
  expect(generateCall[0]).toBe(
    "https://api.github.com/repos/jikig-ai/kb-template/generate",
  );
  const body = JSON.parse(generateCall[1].body);
  expect(body).toEqual({
    owner: "alice",
    name: "my-repo",
    private: true,
    include_all_branches: false,
    description: "Knowledge base managed by Soleur",
  });
});
```

**Critical:** the new test asserts `owner` is set to the **user's login** (extracted from `getInstallationAccount`). Without `owner`, `/generate` creates the repo under the App's own account context — which is not what we want. This is a sharp edge worth a test rather than relying on review.

## Risks

- **Template repo content drift (HIGH).** The `kb-template` repo's content becomes the seed for every new user repo, AND the template MUST be public (live-verified constraint — see Approach B Research Insights). If someone commits a secret or a stale file to the public template, every new user project inherits it AND the secret is publicly indexable on github.com before it propagates. Mitigation: (1) restrict push to `jikig-ai` org admins via branch protection, (2) require CODEOWNERS review on every commit, (3) seed the template with an empty `README.md` only — no executable code, no config files, no env-var examples, (4) add `gitleaks` pre-commit + `secret-scan` workflow to the template repo specifically (cross-link to `cq-test-fixtures-synthesized-only`).
- **`include_all_branches:false` does not include LICENSE/README defaults.** GitHub's `/generate` endpoint copies whatever is in the template's default branch. Plan: seed the template with an empty `README.md` only (one-time operator setup; can be automated via curl PATCH+contents API).
- **GitHub may rate-limit `/generate` more aggressively than `/user/repos`.** No documented limit difference, but worth a note. Mitigation: surfacing GitHub rate-limit status (`X-RateLimit-Remaining`) in the existing `GitHubApiError` is already in place.
- **The `kb-template` repo deletion would silently break user create flows.** Mitigation: file a follow-up issue to add the template repo to a hourly health-probe (similar to drift-guard) that asserts `is_template:true` on the template. Not in this PR's scope (deferral issue).
- **User installation lacks `administration:write`.** `/generate` requires the calling installation to have `administration:write` on the **target owner**. Already present on both installations — verified live.
- **CPO rejects template-sidebar visibility.** Fallback path: switch to Approach A2 in /work; the plan's structure (user/org branch in `createRepo`) is preserved, only the helper changes from `createRepoFromTemplate` to `createRepoViaUserAccessToken`. Document explicitly in the PR description so reviewers know which approach landed.
- **Defense relaxation surface.** This plan does not relax any existing defense. It adds a new helper; the existing `/user/repos` call is removed from the user-installation path. No `cq-when-a-plan-relaxes-or-removes` concern applies.

## Hypotheses (not applicable — no SSH/network/firewall keywords in feature description)

The Phase 1.4 network-outage trigger does not match this feature. Skipping.

## Domain Review

**Domains relevant:** Product (BLOCKING — modifies the create-project flow which is a primary user-facing CTA), Engineering (architecture review for credential-handling boundary), Legal (UAT-class blast-radius if Approach A is selected; minimal under Approach B).

### Engineering (CTO)

**Status:** to-be-invoked at deepen-plan
**Assessment expected:** validate that template-from-install-token works as-described; confirm no regression in the `/orgs/{org}/repos` path; sanity-check the test rewrite.

### Legal (CLO)

**Status:** to-be-invoked at deepen-plan
**Assessment expected:** confirm Approach B (template generate) does not require a separate ToS acknowledgment for "content generated from a Soleur template"; confirm no GDPR Article 33 concern (no breach surface created).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — plan does not create a new page or component; it replaces the failing API call behind an existing CTA. Spec-flow-analyzer will run at deepen-plan to validate the user journey end-to-end (success path, 422 / 404 / 500 error states, rate-limit fallback).
**Agents invoked:** spec-flow-analyzer (deepen-plan)
**Skipped specialists:** ux-design-lead (no new wireframes — no new surfaces), copywriter (no new copy beyond an existing toast)
**Pencil available:** N/A

#### Findings

The "Create Project" CTA, success state ("Project created"), and error state ("GitHub create repo failed: …") all already exist. The fix lands behind the same CTA with no UI change. spec-flow-analyzer will validate:

- Success: `200 → redirect to /chat` (existing flow)
- 422 from template generate: surfaced as 409 to client → existing duplicate-name toast applies
- 404 (template missing): surfaced as 500 → user sees generic "Failed to create" + Sentry breadcrumb for ops triage
- Network/timeout: existing `AbortSignal.timeout(15_000)` covers this

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with concrete artifact + vector + threshold (`single-user incident`). Verified.

- The `kb-template` repo MUST be marked as a template (`is_template: true`) before this PR's code path goes live in prod. The Post-merge AC includes the curl PATCH automation; verification is the `gh api /repos/jikig-ai/kb-template --jq .is_template` check. **Failure mode if skipped:** every user-account Create Project returns 422 with `Resource not accessible by integration` until the template flag is flipped — same symptom as today, different root cause. Add a Sentry alert on `op:createRepo statusCode:422` for the first 24h post-merge.

- The unit test at `github-app-create-repo.test.ts:109-147` has been **green for over a month while testing an impossibility** — `POST /user/repos` cannot succeed with an installation token, but the test mocks 201. This is a test-fixture-vs-real-API drift class. Capture in the learning file at /work GREEN. Generalize: any unit test that mocks a third-party API response for a code path that has never been exercised end-to-end is a candidate for the same drift class. (Cross-link to existing learning `2026-04-29-supabase-phx-join-handshake-shell-environment.md` "verify against installed library source, not just upstream prose.")

- The branch name `feat-one-shot-kb-create-private-repo-403` references HTTP 403, NOT GitHub issue #403. Do not file with `Closes #403`. File a fresh issue for this bug.

## Implementation Phases

### Phase 0 — Open new GitHub issue and link

`gh issue create --title "fix: KB Create Project (private) fails 403 for user installations" --body-file <(echo "Reproduces against Elvalio installation. Root cause: POST /user/repos does not accept GitHub App installation tokens. Plan: knowledge-base/project/plans/2026-05-07-fix-kb-create-private-repo-403-plan.md")`. Capture issue number; insert into plan frontmatter `issue:` field.

### Phase 1 — Operator pre-step (post-merge, but stage now)

Mark `jikig-ai/kb-template` as a template repo. Curl-based automation per Automation note above. Idempotent — safe to re-run. **Gate:** verify `is_template:true` before /work GREEN to ensure live tests can actually exercise the path.

If the `kb-template` repo does not exist, create it (one-time, operator-or-agent — works with installation token, live-verified):

```bash
JWT=$(./scripts/mint-app-jwt.sh)
TOKEN=$(curl -sS -X POST -H "Authorization: Bearer $JWT" \
  https://api.github.com/app/installations/122213433/access_tokens | jq -r .token)
# Note: private:false is REQUIRED — live-verified that user installations
# get 404 from /generate when the template is private.
curl -sS -X POST -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"kb-template","private":false,"auto_init":true,"is_template":true,"description":"Soleur KB seed template"}' \
  https://api.github.com/orgs/jikig-ai/repos
```

The seed `README.md` is sufficient initial content. Do NOT add `LICENSE`, `.gitignore`, env-var examples, or any file that could host accidental secrets — the template is public.

### Phase 2 — TDD: rewrite tests

Apply `cq-write-failing-tests-before`. Replace the `user installation: routes to /user/repos` test with the `routes to /repos/{template}/generate` assertion. Add TS3, TS4 tests. Run `bun test apps/web-platform/test/github-app-create-repo.test.ts` — confirm new tests RED before implementation.

### Phase 3 — Implementation: add `createRepoFromTemplate` and route user installs

Add the helper to `github-app.ts` per the Files to Edit section. Route `createRepo()` to it for `account.type === "User"`. Run tests — confirm GREEN.

### Implementation Sketch — `createRepoFromTemplate`

```ts
// apps/web-platform/server/github-app.ts

const KB_TEMPLATE_OWNER = "jikig-ai";
const KB_TEMPLATE_NAME = "kb-template";

/**
 * Create a repository from the Soleur KB template using a GitHub App
 * installation token. Used for User installations because POST /user/repos
 * does not accept installation tokens.
 *
 * Live-verified 2026-05-07 against installation_id 130018654 (Elvalio).
 *
 * Requires: template repo at `${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME}`
 * exists, is_template=true, private=false. The public-template
 * constraint is a live-verified GitHub API limitation.
 */
async function createRepoFromTemplate(
  installationId: number,
  ownerLogin: string,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const token = await generateInstallationToken(installationId);

  const response = await githubFetch(
    `${GITHUB_API}/repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME}/generate`,
    {
      method: "POST",
      headers: {
        Authorization: `token ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        owner: ownerLogin,
        name,
        private: isPrivate,
        include_all_branches: false,
        description: "Knowledge base managed by Soleur",
      }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    let errorMessage = `GitHub create repo failed: ${response.status}`;
    try {
      const parsed = JSON.parse(body);
      if (parsed.errors?.[0]?.message) {
        errorMessage = parsed.errors[0].message;
      } else if (parsed.message) {
        errorMessage = `GitHub create repo failed: ${response.status} - ${parsed.message}`;
      }
    } catch {
      // Non-JSON response
    }
    log.error(
      { status: response.status, body: body.slice(0, 500), installationId, ownerLogin, name },
      "Failed to create repo from template",
    );
    throw new GitHubApiError(errorMessage, response.status);
  }

  const data = (await response.json()) as GitHubRepoResponse;
  return { repoUrl: data.html_url, fullName: data.full_name };
}

// In existing createRepo(), replace the user branch:
export async function createRepo(
  installationId: number,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const account = await getInstallationAccount(installationId);

  if (account.type === "Organization") {
    // Existing org path — POST /orgs/{org}/repos
    return createRepoForOrg(installationId, account.login, name, isPrivate);
  }

  // User path: template-generate is the only working option
  // (POST /user/repos does not accept installation tokens — live-verified 403).
  return createRepoFromTemplate(installationId, account.login, name, isPrivate);
}
```

**Note:** the existing `createRepo` body becomes `createRepoForOrg` (rename + extract) — straight refactor of lines 619-661. The user branch is replaced wholesale.

### Phase 4 — Live verification (dev env)

Reproduce the original repro (Elvalio installation, name `test-private-soleur-fix`, private). Confirm 200 + repo created. Delete the test repo. Capture the request/response in the learning file.

### Phase 5 — Compound learning + ship

`/soleur:compound` capture; `/soleur:ship` lifecycle. Verify Sentry has zero new error-class events for 24h post-deploy.

## Estimate

- Phase 0: 5 min (issue creation)
- Phase 1: 10 min (operator template setup, curl-automated)
- Phase 2: 30 min (TDD rewrite, 3 tests)
- Phase 3: 20 min (60 LoC helper + 5 LoC routing change)
- Phase 4: 15 min (live repro, screenshot, capture)
- Phase 5: 30 min (compound, learning file, ship)

Total: **~110 min** (~2h). No external blockers if CPO sign-off is on Approach B.

## Cross-references

- Existing learning: `knowledge-base/project/learnings/2026-04-06-github-app-org-repo-creation-endpoint-routing.md` — fixed the org path; this plan extends to the user path. Reuses the user/org branching pattern.
- Existing learning: `knowledge-base/project/learnings/2026-04-13-github-api-fetch-retry-undici-error-codes.md` — the new helper must use the same `AbortSignal.timeout(15_000)` + `fetchWithRetry` pattern. The existing `githubFetch` wrapper in `github-app.ts:191-205` covers this; reuse it directly.
- Existing learning: `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md` — repo connection feature architecture context.
- Existing plan (referenced for context, not modified): `knowledge-base/project/plans/2026-04-06-fix-create-project-setup-failure-plan.md`.
- Runbook: `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — drift-guard ensures the App identity itself is stable; orthogonal to this fix.
- AGENTS.md: `hr-weigh-every-decision-against-target-user-impact` — drives the `requires_cpo_signoff: true` frontmatter.
- AGENTS.md: `cq-test-fixtures-synthesized-only` — applies to template repo content (template is public, so any test fixtures or example data committed there is publicly indexable).
- AGENTS.md: `hr-when-a-plan-specifies-relative-paths-e-g` — verified live: paths used in this plan (`apps/web-platform/server/github-app.ts`, `apps/web-platform/app/api/repo/create/route.ts`, `apps/web-platform/test/github-app-create-repo.test.ts`, `apps/web-platform/test/create-route-error.test.ts`) all match real files.

## Verified Artifacts

- App ID `3261325` (live `GET /app` returned this; matches `Doppler prd GITHUB_APP_ID`).
- Org installation ID `122213433` (account `jikig-ai`, type Organization, `administration:write` accepted).
- User installation ID `130018654` (account `Elvalio`, type User, `administration:write` accepted).
- App permissions live-verified at `GET /app`: actions:write, administration:write, checks:read, contents:write, members:read, metadata:read, pull_requests:write — sufficient for both org `/repos` and template `/generate` paths.
- 403 reproduction verified live against `Elvalio` user installation: `POST /user/repos` with installation token returns `{"message":"Resource not accessible by integration","status":"403"}`.
- Fix path verified live: `POST /repos/jikig-ai/<public-template>/generate` with user installation token + `owner: Elvalio` returns 201 with private repo created. Cleanup 204.
