---
title: Fix Concierge GitHub 403 — wrong-installation token + false-confidence diagnosis
type: fix
date: 2026-06-04
branch: feat-one-shot-concierge-gh-403-token-diagnosis
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 Fix Concierge GitHub 403 — wrong-installation token + false-confidence diagnosis

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Phase 1 (type shape), Phase 3 (import), Research Insights (API contract + precedent-diff)

### Key Improvements
1. Confirmed `GitHubInstallationTokenResponse` (github-app.ts:74-77) currently has
   only `{token, expires_at}` — Phase 1 widening is required, and the type's SOLE
   consumer is github-app.ts itself (type widening blast-radius = zero;
   `hr-type-widening-cross-consumer-grep` satisfied — one consumer, additive).
2. Confirmed `github-api.ts` does NOT currently import `reportSilentFallback` —
   Phase 3's Sentry-mirror step must add the import from `@/server/observability`.
3. Pinned the GitHub REST contract for `POST /app/installations/{id}/access_tokens`:
   the response includes `permissions`, `repository_selection` (`"all" | "selected"`),
   and (when `selected`) `repositories[]` — so Phase 1 logs these from the existing
   `data`, no extra round-trip.
4. Precedent-diff: `findInstallationForRepo` mirrors the existing
   `findOrgInstallationForUser` JWT→list-installs→per-install-probe loop
   (github-app.ts:386-442) — established repo pattern, not novel.

### New Considerations Discovered
- The spike dir `apps/web-platform/scripts/spike/` already exists with `.ts`
  precedents (`dsar-streaming-upload.ts`, `pdf-outline-coverage.ts`) — the
  reproduce harness placement is conventional.
- Gate 4.6/4.7/4.8/4.9 all PASS: User-Brand Impact present (single-user incident),
  Observability 5-field schema complete, no PAT-shaped variables, no UI surface.

## Overview

The Concierge cannot create GitHub issues: every `gh api`/`gh issue` call against
`jikig-ai/soleur` returns **403 Forbidden**, and the Concierge told the user
*"the installation token lacks issues:write"* — a **misdiagnosis**.

**Verified facts (do not re-derive):**
- Org installation `soleur-ai` (id `122213433`) ALREADY has `issues:write`
  granted (`gh api /orgs/jikig-ai/installations`); the committed manifest
  `apps/web-platform/infra/github-app-manifest.json:23` also declares
  `"issues": "write"`.
- The org IP allowlist is DISABLED (`ipAllowListEnabledSetting = DISABLED`) — not
  an IP restriction.
- The runtime token returns 403 on **ALL** REST calls including GETs — broader
  than an issues-scope gap → points at the **token/installation**, not the scope.

**Root cause (confirmed against installed code, not memory):** the GH_TOKEN the
Concierge subprocess receives is minted for the **wrong installation** — the
user's *personal-account* installation, which has **no access to the org-owned
`jikig-ai/soleur` repo** — so every REST call returns
`403 "Resource not accessible by integration"`.

The misdiagnosis is **model-generated**: the Concierge runs `gh` inside the bwrap
sandbox, sees a bare 403, and *invents* "lacks issues:write — file via the UI"
with zero evidence. The server-side `handleErrorResponse`
(`github-api.ts:227-237`) reinforces the same false cause by hard-coding
*"installation may need updated permissions, approve new permissions"* on ANY
403, discarding the real GitHub `message` field.

This plan: (1) selects the **repo-correct installation** at mint time, (2) replaces
both the model's and the server's false-confidence 403 messaging with the actual
API status + GitHub `message` + which installation/token was used, and
(3) adds mint-time observability (installation id, `repository_selection`,
granted `permissions`).

---

## Research Reconciliation — Spec vs. Codebase

| Hypothesis (from task) | Reality (verified against installed code) | Plan response |
|---|---|---|
| H1: GH_TOKEN down-scoped at mint (`permissions` body / `repository_ids`) OR minted for a different installation | **CONFIRMED (different installation).** `cc-dispatcher.ts:1116` mints via `generateInstallationToken(installationId)` where `installationId = resolveInstallationId(args.userId)` (`:1070`). `resolveInstallationId` reads `workspaces.github_installation_id` via the `resolve_workspace_installation_id` RPC. That column is written by `detect-installation/route.ts:141` with `personalInstallationId = findInstallationForLogin(githubLogin)`. **`findInstallationForLogin` (`github-app.ts:356-380`) returns the PERSONAL-account install FIRST** (step 1, `GET /users/{login}/installation`), only falling back to the org install. A personal install has no access to the org repo `jikig-ai/soleur` → 403 on every call. The mint POST (`github-app.ts:494-500`) sends NO `permissions`/`repository_ids` body — so the scope is full-installation; the installation is simply the wrong one. | Fix installation selection (Phase 2) + mint-time observability (Phase 1). |
| H2: `buildSpawnEnv` sources a different token than `githubApiPost`→`generateInstallationToken` | **PARTIALLY.** The Concierge does NOT use `githubApiPost` for issue creation — there is no server-side issues-POST helper in its path. It runs `gh` in-sandbox with GH_TOKEN injected by `agent-env.ts:148` from `cc-dispatcher.ts` (NOT a cron `buildSpawnEnv`; those live in `inngest/functions/*.ts` and are unrelated to the chat Concierge). Both paths ultimately call the same `generateInstallationToken`; the divergence is the *installation id*, not the token source. | Fix is at the installation-selection layer, shared by both. |
| H3: stale/wrong-repo token (would be 401/404) | **Consistent with 403.** A valid token for the wrong installation returns `403 "Resource not accessible by integration"` (permission-class), NOT 401/404. Matches the screenshot evidence exactly. | Surface the real `message` field (Phase 3) to disambiguate forever. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge confidently tells
them to "approve new permissions in GitHub App settings" — sending them on a
fruitless re-consent loop that CANNOT fix the problem (the permission is already
granted), eroding trust in every future Concierge diagnosis.

**If this leaks, the user's workflow is exposed via:** N/A — no new data exposure;
the change tightens which installation token is minted and what error text is
surfaced. The GH_TOKEN value is NEVER logged (`hr-github-app-auth-not-pat`); new
observability logs only the installation id, `repository_selection`, and
`permissions` keys (non-secret metadata).

**Brand-survival threshold:** single-user incident — a single operator hitting a
confidently-wrong diagnosis is a brand-trust failure (the Concierge is the
product's voice). CPO sign-off required at plan time; `user-impact-reviewer`
invoked at review time.

---

## Implementation Phases

> **Phase order is load-bearing.** Phase 1 (observability + reproduce) must land
> before Phase 2 (selection fix) so the reproduce harness proves the diagnosis on
> the CURRENT code, and the new logs confirm the fix flipped `repository_selection`.
> Phase 3 (messaging) is independent and may interleave.

### Phase 0 — Preconditions (verify at /work time, no code)

- [ ] `grep -n "include:" apps/web-platform/vitest.config.ts` — confirm node tests
      live at `test/**/*.test.ts` (verified: line 44). New tests go under
      `apps/web-platform/test/server/`.
- [ ] Confirm runner is `vitest` (verified: `package.json:15 "test": "vitest"`).
      Run tests with `./node_modules/.bin/vitest run <path>` from
      `apps/web-platform/` (NOT `bun test` — `bunfig.toml` ignores).
- [ ] Read installed `findInstallationForLogin` (`github-app.ts:356-442`) and
      `mintAndExchange` (`github-app.ts:494-500`) before editing — confirm the
      personal-first ordering and the no-permissions-body mint still hold.

### Phase 1 — Mint-time observability + reproduce harness

**Goal:** make the next 403 self-diagnosing, and prove the current bug.

1. **Log token metadata at mint** (`github-app.ts` `generateInstallationToken`,
   after `:550` `data = await response.json()`). The access-tokens response body
   already returns `permissions` and `repository_selection` — log them at
   `log.info` keyed by `installationId`. NEVER log `data.token`
   (`hr-github-app-auth-not-pat`). Field shape:
   ```ts
   // github-app.ts — after the JSON parse, before tokenCache.set
   log.info(
     {
       installationId,
       repositorySelection: data.repository_selection, // "all" | "selected"
       permissionKeys: Object.keys(data.permissions ?? {}).sort(),
       appId: getAppId(),
     },
     "Minted installation token",
   );
   ```
   - **Type widening:** extend `GitHubInstallationTokenResponse`
     (`github-app.ts:74-77`, currently `{ token: string; expires_at: string }`) to
     add `repository_selection?: "all" | "selected"` and
     `permissions?: Record<string, string>`. **Verified consumers:**
     `git grep -ln "GitHubInstallationTokenResponse"` returns ONLY
     `github-app.ts` itself — type widening is additive (optional fields) AND
     single-consumer, so blast-radius is zero. `hr-type-widening-cross-consumer-grep`
     satisfied.

   **Research Insights — GitHub REST contract (access-tokens endpoint):**
   `POST /app/installations/{id}/access_tokens` (docs.github.com REST
   apps/installations) returns `token`, `expires_at`, **`permissions`** (object of
   scope→`read|write`), **`repository_selection`** (`"all" | "selected"`), and —
   when `repository_selection == "selected"` — a **`repositories[]`** array. All
   are in the SAME response `data` already parsed at `:550`; logging them adds NO
   round-trip. (This is exactly the field set the runtime guard in Phase 2.2 needs
   to detect "connected repo not in token's selected set".)

2. **Reproduce harness** — a one-off script (NOT committed to prod; lives under
   `apps/web-platform/scripts/spike/` like the existing `dsar-streaming-upload.ts`)
   that mints a token via the **exact runtime path** for a given workspace and
   makes the two diagnostic calls:
   - `GET /installation/repositories` — capture `repository_selection` + repo list.
   - `POST /repos/jikig-ai/soleur/issues` **dry-run** — do NOT actually create;
     instead `GET /repos/jikig-ai/soleur` and `GET /repos/jikig-ai/soleur/issues`
     (read probes that 403 identically if the installation lacks repo access),
     OR POST with a clearly-synthetic title and immediately close. Prefer
     the read-probe form to avoid issue residue.
   - Log the full 403 JSON body (`message`, `documentation_url`), the token's
     `permissions`, and `repository_selection`.
   - **Acceptance:** the harness, run against the affected workspace, prints
     `repository_selection` and a 403 with
     `message: "Resource not accessible by integration"` against the org repo —
     confirming a wrong-installation token, NOT a scope gap. Capture the output in
     the PR body.

### Phase 2 — Select the repo-correct installation (root-cause fix)

**Goal:** the workspace stores / the runtime mints the installation that actually
has access to the connected repo.

The defect is that `findInstallationForLogin` prefers the personal install. Two
fix layers — implement **both** (defense-in-depth; the read-side fix repairs
already-broken workspaces without a reconnect):

1. **Selection fix (`github-app.ts` / `detect-installation` path).** When a repo
   is being connected, choose the installation that can access *that repo*, not the
   user's personal login. The cleanest seam:
   - Add `findInstallationForRepo(owner, repo): Promise<number | null>` to
     `github-app.ts` — iterate app installations, mint each token, probe
     `GET /repos/{owner}/{repo}` (or `GET /installation/repositories` filtered),
     return the first installation whose token can read the repo. Reuse the
     existing iteration shape in `findOrgInstallationForUser` (`:386-442`).
   - In the connect flow (`repo/install/route.ts`, `repo/setup/route.ts`,
     `detect-installation/route.ts`), prefer `findInstallationForRepo` when an
     `owner/repo` is known; fall back to `findInstallationForLogin` only when no
     repo is selected yet.
   - **Precedent-diff (deepen-plan Phase 4.4):** compare against
     `findOrgInstallationForUser` membership-check loop — same JWT→list→per-install
     probe pattern.

2. **Runtime guard / self-heal (`cc-dispatcher.ts` mint site, `:1113-1127`).**
   After minting GH_TOKEN, if `repository_selection === "selected"` and the
   connected repo is NOT in the token's repo set (the new observability already
   surfaces this), do ONE of:
   - re-resolve the correct installation via `findInstallationForRepo` and re-mint;
   - OR degrade honestly (do not inject a token that 403s) and emit the structured
     signal (Phase 3) so the model says "this installation cannot access the repo"
     rather than inventing a scope gap.
   - **Decision to make at /work (document in PR):** auto-heal-and-rewrite the
     stored `workspaces.github_installation_id`, vs. surface-and-instruct. Prefer
     auto-heal (Soleur users are non-technical;
     `feedback_never_defer_operator_actions`) — re-resolve, re-mint, and UPDATE the
     workspace column via the service client in the connect/dispatch path.

3. **Test (`test/server/`):**
   - `findInstallationForRepo` returns the org install when the personal install
     lacks repo access (mock `githubFetch`: personal install token → 403 on
     `GET /repos/...`; org install token → 200).
   - Regression: `findInstallationForLogin` personal-first ordering is preserved
     for the no-repo-connected case (don't break existing callers).
   - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/<new>.test.ts`.

### Phase 3 — Honest 403 messaging (kill the false confidence)

**Goal:** neither the server nor the model asserts a cause it cannot prove.

1. **Server-side (`github-api.ts:227-237`).** Stop hard-coding "approve new
   permissions". Surface the **actual** GitHub `message` field + status + path.
   Parse `bodyText` as JSON, extract `message` and `documentation_url`, and put
   them in the thrown `GitHubApiError`. Mirror to Sentry per
   `cq-silent-fallback-must-mirror-to-sentry` (the existing `log.warn` stays;
   add `reportSilentFallback` so 403s are queryable). **Verified:** `github-api.ts`
   does NOT currently import `reportSilentFallback` — this step must add
   `import { reportSilentFallback } from "@/server/observability";`. Keep the
   message factual:
   ```
   GitHub API 403 for {path}: "{githubMessage}". Installation {id}
   (repository_selection={sel}). This usually means the installation cannot
   access this repository — not a missing permission scope.
   ```
   - **Do NOT** instruct the user to re-consent / change permissions.

2. **Model-side (Concierge system prompt / gh guidance).** The Concierge invents
   the diagnosis because it only sees a bare `gh` 403. Add a directive to the
   Concierge system prompt (grep for where the cc router prompt is assembled;
   `cc-dispatcher.ts` `effectiveSystemPrompt`, `:1238-1246`) instructing:
   - When a `gh` call returns 403, **report the literal `gh` error output** and
     the status — do NOT speculate about which permission/scope is missing.
   - State that the Soleur platform diagnoses installation/permission issues
     server-side; the Concierge should NOT tell users to change GitHub App
     permissions or re-consent.
   - **Verify the prompt-assembly site exists** before writing the FR
     (`grep -n "effectiveSystemPrompt\|systemPrompt" cc-dispatcher.ts`).

3. **Test:** `github-api.test.ts` — a 403 with body
   `{"message":"Resource not accessible by integration"}` produces a
   `GitHubApiError` whose message contains the GitHub `message` text and does NOT
   contain "approve new permissions"/"issues:write". Mirror-to-Sentry asserted via
   the `reportSilentFallback` mock.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (observability):** `generateInstallationToken` logs `installationId`,
      `repositorySelection`, and sorted `permissionKeys` at `log.info` on every
      mint; `data.token` never appears in any log call (grep the function body for
      `data.token` inside a `log.*` — zero matches).
- [ ] **AC2 (reproduce):** the spike harness output is pasted in the PR body,
      showing the affected workspace's token `repository_selection` and a 403 with
      `message: "Resource not accessible by integration"` against
      `jikig-ai/soleur` — proving wrong-installation, not scope gap.
- [ ] **AC3 (selection fix):** `findInstallationForRepo` exists and a unit test
      proves it returns the org install (122213433-class) when the personal install
      token 403s on the org repo. `./node_modules/.bin/vitest run` green.
- [ ] **AC4 (server messaging):** `handleErrorResponse` 403 branch no longer
      contains the literal strings "approve new permissions" or "issues:write";
      its message includes the parsed GitHub `message` field. Asserted by
      `github-api.test.ts`. A `reportSilentFallback` fires on 403 (Sentry mirror).
- [ ] **AC5 (model messaging):** the Concierge system prompt contains a directive
      forbidding speculation about missing scopes/permissions on `gh` 403 and
      forbidding "change GitHub App permissions / re-consent" advice. Grep the
      assembled prompt source for the directive sentinel.
- [ ] **AC6 (no manifest/perms change):** `git diff` touches NEITHER
      `github-app-manifest.json` NOR any GitHub App permission declaration —
      the fix is installation-selection + messaging only (the task's hard constraint).

### Post-merge (operator)

- [ ] **AC7:** after deploy, an affected workspace's NEXT cold Concierge dispatch
      mints a token with `repository_selection` covering `jikig-ai/soleur` (verify
      via the new `log.info` mint line in production logs — NO ssh, the deploy
      pipeline restarts the container on merge to `apps/web-platform/**`).
      `Ref` (not `Closes`) the source issue if one exists; close after verification.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO) — UI-adjacent messaging.

### Engineering (CTO)
**Status:** to be reviewed at deepen-plan / plan-review
**Assessment:** installation-selection is the load-bearing fix; the runtime
self-heal mirrors the SQL/RPC credential-read layer — name its load-bearing
sub-value (repairs already-broken workspaces without reconnect) per the
defense-in-depth-mirroring Sharp Edge.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline) — no new user-facing page/component; the
change is the *content* of an existing error/chat surface (the Concierge's reply).
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings
The user-facing impact is the Concierge's *spoken diagnosis* — a copy/voice change,
not a new flow. CPO sign-off is required (single-user-incident threshold) on the
approach, not on a wireframe.

---

## Infrastructure (IaC)

Skip — pure code change against already-provisioned surfaces
(`apps/web-platform/server/*.ts`, `app/api/repo/*`). No new server, secret,
vendor, or persistent process. The GitHub App and its installations already exist.

---

## Observability

```yaml
liveness_signal:
  what: "Minted installation token" log.info line w/ installationId + repository_selection + permissionKeys
  cadence: per cold Concierge dispatch (token-cache-memoized per installation)
  alert_target: Better Stack log query / Sentry breadcrumb
  configured_in: apps/web-platform/server/github-app.ts (generateInstallationToken)
error_reporting:
  destination: Sentry via reportSilentFallback (github-api 403 handler + cc-dispatcher mint catch)
  fail_loud: true (403 now mirrors to Sentry with real GitHub message + installationId)
failure_modes:
  - mode: wrong-installation token (personal install, no org-repo access)
    detection: repository_selection=="selected" && connected repo absent from token repo set
    alert_route: Sentry feature=github-app op=generate-installation-token + new mint log
  - mode: 403 on issues write
    detection: GitHubApiError(403) with parsed GitHub message
    alert_route: Sentry feature=github-api (new reportSilentFallback on 403)
logs:
  where: app server stdout (pino) -> container logs -> Better Stack
  retention: per existing platform log retention
discoverability_test:
  command: "grep 'Minted installation token' <container-logs> | jq .repositorySelection  # via deploy log pipeline, no remote shell"
  expected_output: "all" (or "selected" including jikig-ai/soleur) for a healthy connected workspace
```

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Change GitHub App permissions / ask operator to re-consent | **Explicitly forbidden** by the task — the permission is already granted; this would not fix the wrong-installation root cause and reinforces the false diagnosis. |
| Down-scope the mint with an explicit `permissions`/`repository_ids` body | Opposite of the problem — the token is already full-installation-scoped; narrowing would make it worse. The issue is *which installation*. |
| Only fix the messaging, not the selection | Leaves every connected-via-personal-install workspace broken; honest messaging would correctly say "wrong installation" but the user still can't create issues. |
| Only fix selection at connect time (no runtime self-heal) | Already-broken workspaces (stored personal install id) stay broken until a manual reconnect — violates `feedback_never_defer_operator_actions`. |

---

## Open Code-Review Overlap

To be populated at deepen-plan / Step 1.7.5 by querying open `code-review` issues
against the Files-to-Edit list. (Default `None` if the check finds no overlap.)

---

## Files to Edit

- `apps/web-platform/server/github-app.ts` — mint-time observability;
  `GitHubInstallationTokenResponse` widening; new `findInstallationForRepo`.
- `apps/web-platform/server/github-api.ts` — `handleErrorResponse` 403 branch:
  parse + surface real GitHub `message`, drop false "approve permissions" text,
  add Sentry mirror.
- `apps/web-platform/server/cc-dispatcher.ts` — runtime guard/self-heal at the
  GH_TOKEN mint site; Concierge system-prompt 403 directive.
- `apps/web-platform/app/api/repo/detect-installation/route.ts`,
  `apps/web-platform/app/api/repo/install/route.ts`,
  `apps/web-platform/app/api/repo/setup/route.ts` — prefer
  `findInstallationForRepo` when owner/repo is known.

## Files to Create

- `apps/web-platform/scripts/spike/reproduce-gh-403.ts` — one-off reproduce
  harness (NOT prod runtime).
- `apps/web-platform/test/server/find-installation-for-repo.test.ts` — selection
  unit test.
- 403-messaging assertions added to existing
  `apps/web-platform/test/server/github-api.test.ts` (edit, not create).

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled.)
- **`findInstallationForLogin` returns the personal install FIRST** — any fix that
  reuses it for repo-connected flows reintroduces the bug. The new
  `findInstallationForRepo` must probe repo access, not login match.
- The mint response's `repository_selection`/`permissions` are returned by the
  access-tokens POST (`github-app.ts:550`), NOT by a separate call — log them from
  the existing `data`, do not add a round-trip.
- Verify the Concierge prompt-assembly site (`effectiveSystemPrompt`,
  `cc-dispatcher.ts:1238-1246`) before writing the model-side directive FR — the
  directive must land in the prompt actually sent to the SDK.
- Tests must live under `apps/web-platform/test/**/*.test.ts` (vitest node project,
  `vitest.config.ts:44`) and run via `./node_modules/.bin/vitest run` — `bun test`
  is ignored by `bunfig.toml`. A co-located `server/*.test.ts` would be silently
  skipped.
- The GH_TOKEN value is NEVER logged (`hr-github-app-auth-not-pat`); new
  observability logs only non-secret metadata (installation id, selection, perm keys).
- Do NOT use `Closes #N` for the source issue if remediation completes post-merge
  (operator AC7) — use `Ref #N` and close after verification.
