---
title: "fix: match sibling installation ID on GitHub org owner instead of exact repo_url"
type: fix
date: 2026-05-28
lane: single-domain
brand_survival_threshold: none
---

# fix: match sibling installation ID on GitHub org owner instead of exact repo_url

## Overview

The workspace-sibling fallback in `resolveInstallationId` (introduced in commit 52b41e4a, PR #4546) uses `query.eq("repo_url", callerRepoUrl)` to restrict sibling matches to the same `repo_url`. This is too restrictive because GitHub App installations are org-level -- installation `122213433` covers both `jikig-ai/soleur` and `jikig-ai/chatte`.

**Production symptom:** `ops@jikigai.com` (repo_url `https://github.com/jikig-ai/soleur`, installation NULL) cannot resolve installation ID from sibling `jean.deruelle@jikigai.com` (repo_url `https://github.com/jikig-ai/chatte`, installation `122213433`), despite both repos being under the same `jikig-ai` GitHub org.

**Fix:** Extract the GitHub owner (org) from the caller's `repo_url` and match siblings whose `repo_url` starts with the same `https://github.com/<owner>/` prefix, using Supabase's `.like()` filter instead of `.eq()`.

## User-Brand Impact

- **If this lands broken, the user experiences:** sync and KB routes returning "Workspace not connected" (409) for the second user in a multi-user org, identical to the current broken state
- **If this leaks, the user's [data / workflow / money] is exposed via:** a sibling in a DIFFERENT GitHub org resolving a cross-org installation token -- but the owner-prefix match restricts to same-org siblings, and `workspace_members` already scopes to the same workspace
- **Brand-survival threshold:** `none`

The fix is strictly less restrictive than the prior commit's security filter but still scopes to same-org via URL prefix. The workspace_members join already prevents cross-workspace leakage. Worst case regression: same behavior as before (NULL installation, sync fails).

## Observability

```yaml
liveness_signal:
  what: "existing session-sync and KB sync liveness -- no new surface"
  cadence: "per-request"
  alert_target: "Sentry web-platform"
  configured_in: "apps/web-platform/server/resolve-installation-id.ts (reportSilentFallback)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "reportSilentFallback logs to Sentry when tenant-read or sibling lookup fails"

failure_modes:
  - mode: "Owner extraction returns null (non-GitHub or malformed URL)"
    detection: "resolveInstallationId returns null, caller logs via existing observability"
    alert_route: "Sentry web-platform"
  - mode: "Like query matches no siblings (single-user org)"
    detection: "resolveInstallationId returns null, same as current happy path"
    alert_route: "No alert needed -- expected path"

logs:
  where: "Sentry web-platform project + server structured logs"
  retention: "90d (Sentry plan)"

discoverability_test:
  command: "curl -s https://app.soleur.ai/api/repo/status -H 'Cookie: ...' | jq '.repoUrl'"
  expected_output: "non-null repo_url for authenticated user"
```

## Research Insights

### Existing patterns

- `repo_url` values in the `users` table follow the pattern `https://github.com/<owner>/<repo>` consistently (verified via `rg "repo_url" apps/web-platform/` -- setup routes write this shape, e2e fixtures confirm `https://github.com/acme/repo`)
- No existing GitHub URL parser or owner-extractor utility exists in the codebase
- The `resolveInstallationId` function has 3 callers: `kb-route-helpers.ts`, `session-sync.ts`, `app/api/kb/sync/route.ts` -- all import it dynamically
- No dedicated unit tests exist for `resolveInstallationId` (the test files found cover adjacent concerns: `detect-installation-fallback.test.ts` tests the detect-installation route, `installation-id-source-of-truth.test.ts` is a sentinel test for agent-on-spawn-requested)
- Test runner is vitest (NOT bun test -- `bunfig.toml` blocks bun test discovery per #1469)

### URL parsing approach

The simplest owner-extraction pattern is:

```typescript
function extractGitHubOwner(repoUrl: string): string | null {
  const match = repoUrl.match(/^https:\/\/github\.com\/([^/]+)\//);
  return match?.[1] ?? null;
}
```

This extracts `jikig-ai` from `https://github.com/jikig-ai/soleur` and `https://github.com/jikig-ai/chatte`. It returns `null` for non-GitHub URLs or malformed strings.

### Supabase filter

Replace `query.eq("repo_url", callerRepoUrl)` with `query.like("repo_url", "https://github.com/<owner>/%")` where `<owner>` is extracted from the caller's URL. The `%` wildcard in PostgREST `.like()` matches any repo name under the same org.

### Security analysis

The prior exact-match was added to prevent cross-repo token leakage. The org-level match is the correct scoping because:

1. GitHub App installations are org-level (installation `122213433` grants access to all repos in `jikig-ai`)
2. The workspace_members join already restricts to same-workspace siblings
3. An installation token for org `jikig-ai` is valid for both `jikig-ai/soleur` and `jikig-ai/chatte` -- no privilege escalation
4. The owner-prefix match prevents cross-org leakage (a sibling with `https://github.com/other-org/repo` will not match `https://github.com/jikig-ai/%`)

## Open Code-Review Overlap

None

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- single-file bug fix in existing server logic.

## Implementation Phases

### Phase 1: Fix the org-match filter (resolve-installation-id.ts)

**File:** `apps/web-platform/server/resolve-installation-id.ts`

1. Add a helper function `extractGitHubOwner(url: string): string | null` that extracts the owner segment from a `https://github.com/<owner>/...` URL using a regex
2. Update the JSDoc comment (lines 17-18) to reflect org-level matching instead of exact `repo_url` match
3. At line 78-80, replace the `callerRepoUrl` exact-match block:

**Before:**
```typescript
if (callerRepoUrl) {
  query = query.eq("repo_url", callerRepoUrl);
}
```

**After:**
```typescript
if (callerRepoUrl) {
  const owner = extractGitHubOwner(callerRepoUrl);
  if (owner) {
    query = query.like("repo_url", `https://github.com/${owner}/%`);
  }
}
```

If `extractGitHubOwner` returns null (non-GitHub URL), the query runs without a repo_url filter -- same as the pre-52b41e4a behavior, and the workspace_members scoping still prevents cross-workspace leakage.

### Phase 2: Add unit tests

**File to create:** `apps/web-platform/test/resolve-installation-id.test.ts`

Test scenarios:

1. **Returns own installation ID when present** -- user has `github_installation_id` set, no sibling lookup needed
2. **Resolves from sibling with same org** -- caller has `repo_url = https://github.com/jikig-ai/soleur`, sibling has `repo_url = https://github.com/jikig-ai/chatte` with installation set. The `.like("repo_url", "https://github.com/jikig-ai/%")` matches.
3. **Does not resolve from sibling with different org** -- caller has `repo_url = https://github.com/jikig-ai/soleur`, sibling has `repo_url = https://github.com/other-org/repo` with installation set. The `.like()` does NOT match.
4. **Returns null when no siblings exist** -- single-user workspace
5. **Returns null when caller has no repo_url** -- `callerRepoUrl` is null, no `.like()` filter applied but no installation found
6. **Handles non-GitHub URLs gracefully** -- `extractGitHubOwner` returns null, query runs without repo filter

### Phase 3: Verify extractGitHubOwner edge cases

Inline unit tests for the helper:

- `https://github.com/jikig-ai/soleur` -> `jikig-ai`
- `https://github.com/jikig-ai/chatte` -> `jikig-ai`
- `https://github.com/single` -> `null` (no trailing slash/repo)
- `https://gitlab.com/jikig-ai/soleur` -> `null` (not GitHub)
- `null` / empty string -> handled gracefully (null)

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/server/resolve-installation-id.ts` | Add `extractGitHubOwner` helper, replace `.eq("repo_url", ...)` with `.like("repo_url", ...)` using extracted owner |

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/test/resolve-installation-id.test.ts` | Unit tests for `resolveInstallationId` sibling org-match logic and `extractGitHubOwner` edge cases |

## Acceptance Criteria

- [ ] AC1: `extractGitHubOwner("https://github.com/jikig-ai/soleur")` returns `"jikig-ai"`
- [ ] AC2: `extractGitHubOwner("https://github.com/jikig-ai/chatte")` returns `"jikig-ai"`
- [ ] AC3: The sibling query uses `.like("repo_url", "https://github.com/jikig-ai/%")` instead of `.eq("repo_url", "https://github.com/jikig-ai/soleur")` when the caller's repo_url is `https://github.com/jikig-ai/soleur`
- [ ] AC4: A sibling with `repo_url = https://github.com/other-org/repo` does NOT match when the caller is under `jikig-ai`
- [ ] AC5: When `callerRepoUrl` is null, no `.like()` filter is applied (query runs unfiltered against sibling IDs, scoped by workspace)
- [ ] AC6: When `extractGitHubOwner` returns null (non-GitHub URL), no `.like()` filter is applied
- [ ] AC7: All tests pass: `./node_modules/.bin/vitest run test/resolve-installation-id.test.ts`
- [ ] AC8: Existing tests pass: `./node_modules/.bin/vitest run`

## Test Scenarios

- Given a user with `github_installation_id = NULL` and `repo_url = "https://github.com/jikig-ai/soleur"`, when a workspace sibling has `repo_url = "https://github.com/jikig-ai/chatte"` and `github_installation_id = 122213433`, then `resolveInstallationId` returns `122213433`
- Given a user with `github_installation_id = NULL` and `repo_url = "https://github.com/jikig-ai/soleur"`, when a workspace sibling has `repo_url = "https://github.com/other-org/repo"` and `github_installation_id = 999`, then `resolveInstallationId` returns `null`
- Given a user with `github_installation_id = 555`, then `resolveInstallationId` returns `555` without any sibling lookup

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| PostgREST `.like()` with user-derived input | The owner segment is extracted via regex from a `repo_url` already stored in the DB -- not raw user input. The `%` wildcard is appended server-side, not user-controlled. |
| Owner extraction regex mismatch | The regex `^https:\/\/github\.com\/([^/]+)\/` is conservative -- it requires the full `https://github.com/` prefix and captures only the first path segment. Non-matching URLs fall through to null (safe default). |
| Performance of `.like()` vs `.eq()` | The query is already scoped to a small set of sibling IDs (via `.in("id", siblingIds)`), so the `.like()` filter runs over a tiny result set. No index change needed. |

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Store `github_org` as a separate column | Schema migration overhead for a simple URL-parsing fix; the org is derivable from `repo_url` |
| Use `new URL()` for parsing | Heavier than regex for extracting a single path segment; `new URL()` also requires try/catch for malformed URLs |
| Match on full `repo_url` minus the repo name | More complex regex with no additional safety benefit over owner-prefix matching |

## References

- Commit 52b41e4a: Prior fix that introduced the sibling fallback with exact `repo_url` match
- PR #4546: The PR that introduced the current behavior
- `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`: Learning about installation `122213433` covering the `jikig-ai` org

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The vitest test runner (NOT bun test) must be used for `apps/web-platform/` tests per `bunfig.toml` pathIgnorePatterns (see #1469). Use `./node_modules/.bin/vitest run <path>`.
