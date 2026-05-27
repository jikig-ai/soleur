---
title: "fix: match sibling installation ID on GitHub org owner instead of exact repo_url"
type: fix
date: 2026-05-28
lane: single-domain
brand_survival_threshold: none
---

# fix: match sibling installation ID on GitHub org owner instead of exact repo_url

## Enhancement Summary

**Deepened on:** 2026-05-28
**Sections enhanced:** 5 (Research Insights, Implementation Phases, Acceptance Criteria, Risks, Test Scenarios)
**Research agents used:** repo-research (codebase grep), installed-SDK verification, normalizeRepoUrl case-analysis

### Key Improvements
1. **Use `.ilike()` instead of `.like()`** -- `normalizeRepoUrl` (`lib/repo-url.ts:8-10`) preserves path case, so two users in the same org could store `jikig-ai` vs `Jikig-AI`. Case-insensitive ILIKE prevents silent mismatches.
2. **Export `extractGitHubOwner` for direct testability** -- unit tests can verify the helper in isolation without mocking the full Supabase chain.
3. **Added case-sensitivity test scenario** -- AC and test scenarios now cover case-variant org names.

### New Considerations Discovered
- `normalizeRepoUrl` (`apps/web-platform/lib/repo-url.ts:8-10`) explicitly preserves owner/repo path case per its JSDoc: "GitHub path segments are case-insensitive at the API but case-sensitive for display"
- GitHub org names are restricted to `[a-zA-Z0-9-]` (no `_` or `%`), so SQL LIKE/ILIKE wildcard injection via owner name is structurally impossible for GitHub URLs
- `.ilike()` confirmed in installed `@supabase/postgrest-js` at `dist/index.d.mts:1048-1049`

## Overview

The workspace-sibling fallback in `resolveInstallationId` (introduced in commit 52b41e4a, PR #4546) uses `query.eq("repo_url", callerRepoUrl)` to restrict sibling matches to the same `repo_url`. This is too restrictive because GitHub App installations are org-level -- installation `122213433` covers both `jikig-ai/soleur` and `jikig-ai/chatte`.

**Production symptom:** `ops@jikigai.com` (repo_url `https://github.com/jikig-ai/soleur`, installation NULL) cannot resolve installation ID from sibling `jean.deruelle@jikigai.com` (repo_url `https://github.com/jikig-ai/chatte`, installation `122213433`), despite both repos being under the same `jikig-ai` GitHub org.

**Fix:** Extract the GitHub owner (org) from the caller's `repo_url` and match siblings whose `repo_url` starts with the same `https://github.com/<owner>/` prefix, using Supabase's `.ilike()` (case-insensitive) filter instead of `.eq()`. Case-insensitive matching is required because `normalizeRepoUrl` (`lib/repo-url.ts`) preserves the user-typed case of path segments.

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

Replace `query.eq("repo_url", callerRepoUrl)` with `query.ilike("repo_url", "https://github.com/<owner>/%")` where `<owner>` is extracted from the caller's URL. The `%` wildcard in PostgREST `.ilike()` matches any repo name under the same org, case-insensitively.

### Deepen-plan: case-sensitivity finding

**Critical correction from deepen-plan research.** The plan originally proposed `.like()` (case-sensitive). Reading `apps/web-platform/lib/repo-url.ts` revealed that `normalizeRepoUrl` preserves path case per its JSDoc (lines 8-10):

> "GitHub path segments are case-insensitive at the API but case-sensitive for display; the user's typed form is the display form, so we keep it."

This means two users in the same workspace could have `repo_url` values `https://github.com/jikig-ai/soleur` and `https://github.com/Jikig-AI/chatte` (different case for the org segment). A case-sensitive `.like()` would fail to match these as same-org. The fix is to use `.ilike()` (case-insensitive LIKE), confirmed available at `@supabase/postgrest-js/dist/index.d.mts:1048-1049`.

### Deepen-plan: LIKE wildcard injection analysis

GitHub org names are restricted to `[a-zA-Z0-9-]` per GitHub's naming rules. The SQL LIKE wildcards `%` and `_` are not valid in GitHub org names, so the extracted owner segment cannot inject additional wildcards into the `.ilike()` pattern. The only `%` in the pattern is the server-appended one at the end. This analysis holds for all GitHub URLs; non-GitHub URLs cause `extractGitHubOwner` to return `null`, skipping the filter entirely.

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

1. Add and **export** a helper function `extractGitHubOwner(url: string): string | null` that extracts the owner segment from a `https://github.com/<owner>/...` URL using a regex. Exported for direct unit testing.
2. Update the JSDoc comment (lines 17-18) to reflect org-level matching via `.ilike()` instead of exact `repo_url` match
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
    query = query.ilike("repo_url", `https://github.com/${owner}/%`);
  }
}
```

**Why `.ilike()` not `.like()`:** `normalizeRepoUrl` (`lib/repo-url.ts`) preserves path case. Two users in the same org could store `jikig-ai` vs `Jikig-AI`. GitHub org names are case-insensitive, so `.ilike()` is the correct semantic match.

If `extractGitHubOwner` returns null (non-GitHub URL), the query runs without a repo_url filter -- same as the pre-52b41e4a behavior, and the workspace_members scoping still prevents cross-workspace leakage.

### Phase 2: Add unit tests

**File to create:** `apps/web-platform/test/resolve-installation-id.test.ts`

Test scenarios:

1. **Returns own installation ID when present** -- user has `github_installation_id` set, no sibling lookup needed
2. **Resolves from sibling with same org** -- caller has `repo_url = https://github.com/jikig-ai/soleur`, sibling has `repo_url = https://github.com/jikig-ai/chatte` with installation set. The `.ilike("repo_url", "https://github.com/jikig-ai/%")` matches.
3. **Resolves from sibling with same org, different case** -- caller has `repo_url = https://github.com/jikig-ai/soleur`, sibling has `repo_url = https://github.com/Jikig-AI/chatte`. The `.ilike()` matches case-insensitively.
4. **Does not resolve from sibling with different org** -- caller has `repo_url = https://github.com/jikig-ai/soleur`, sibling has `repo_url = https://github.com/other-org/repo` with installation set. The `.ilike()` does NOT match.
5. **Returns null when no siblings exist** -- single-user workspace
6. **Returns null when caller has no repo_url** -- `callerRepoUrl` is null, no `.ilike()` filter applied but no installation found
7. **Handles non-GitHub URLs gracefully** -- `extractGitHubOwner` returns null, query runs without repo filter

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
| `apps/web-platform/server/resolve-installation-id.ts` | Add exported `extractGitHubOwner` helper, replace `.eq("repo_url", ...)` with `.ilike("repo_url", ...)` using extracted owner |

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/test/resolve-installation-id.test.ts` | Unit tests for `resolveInstallationId` sibling org-match logic and `extractGitHubOwner` edge cases |

## Acceptance Criteria

- [ ] AC1: `extractGitHubOwner("https://github.com/jikig-ai/soleur")` returns `"jikig-ai"`
- [ ] AC2: `extractGitHubOwner("https://github.com/jikig-ai/chatte")` returns `"jikig-ai"`
- [ ] AC3: The sibling query uses `.ilike("repo_url", "https://github.com/jikig-ai/%")` instead of `.eq("repo_url", "https://github.com/jikig-ai/soleur")` when the caller's repo_url is `https://github.com/jikig-ai/soleur`. Verified via `grep -n 'ilike' apps/web-platform/server/resolve-installation-id.ts` returning at least 1 match.
- [ ] AC4: A sibling with `repo_url = https://github.com/other-org/repo` does NOT match when the caller is under `jikig-ai`
- [ ] AC5: When `callerRepoUrl` is null, no `.ilike()` filter is applied (query runs unfiltered against sibling IDs, scoped by workspace)
- [ ] AC6: When `extractGitHubOwner` returns null (non-GitHub URL), no `.ilike()` filter is applied
- [ ] AC7: `extractGitHubOwner` is exported from `resolve-installation-id.ts`. Verified via `grep -n 'export.*extractGitHubOwner' apps/web-platform/server/resolve-installation-id.ts`.
- [ ] AC8: No remaining `.eq("repo_url"` in `resolve-installation-id.ts`. Verified via `grep -c 'eq("repo_url"' apps/web-platform/server/resolve-installation-id.ts` returns 0.
- [ ] AC9: All tests pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/resolve-installation-id.test.ts`
- [ ] AC10: Existing tests pass: `cd apps/web-platform && ./node_modules/.bin/vitest run`

## Test Scenarios

- Given a user with `github_installation_id = NULL` and `repo_url = "https://github.com/jikig-ai/soleur"`, when a workspace sibling has `repo_url = "https://github.com/jikig-ai/chatte"` and `github_installation_id = 122213433`, then `resolveInstallationId` returns `122213433`
- Given a user with `github_installation_id = NULL` and `repo_url = "https://github.com/jikig-ai/soleur"`, when a workspace sibling has `repo_url = "https://github.com/Jikig-AI/chatte"` (different case) and `github_installation_id = 122213433`, then `resolveInstallationId` returns `122213433` (case-insensitive match via `.ilike()`)
- Given a user with `github_installation_id = NULL` and `repo_url = "https://github.com/jikig-ai/soleur"`, when a workspace sibling has `repo_url = "https://github.com/other-org/repo"` and `github_installation_id = 999`, then `resolveInstallationId` returns `null`
- Given a user with `github_installation_id = 555`, then `resolveInstallationId` returns `555` without any sibling lookup

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| PostgREST `.ilike()` with user-derived input | The owner segment is extracted via regex from a `repo_url` already stored in the DB -- not raw user input. The `%` wildcard is appended server-side, not user-controlled. GitHub org names are restricted to `[a-zA-Z0-9-]` -- no LIKE wildcards (`%`, `_`) are possible in valid GitHub org names. |
| Owner extraction regex mismatch | The regex `^https:\/\/github\.com\/([^/]+)\/` is conservative -- it requires the full `https://github.com/` prefix and captures only the first path segment. Non-matching URLs fall through to null (safe default). |
| Performance of `.ilike()` vs `.eq()` | The query is already scoped to a small set of sibling IDs (via `.in("id", siblingIds)`), so the `.ilike()` filter runs over a tiny result set. No index change needed. ILIKE is slightly slower than LIKE due to case folding, but negligible on <10 rows. |
| Case-sensitivity drift | `normalizeRepoUrl` preserves path case (`lib/repo-url.ts:8-10`). Using `.ilike()` makes the match case-insensitive, matching GitHub's own behavior. If `normalizeRepoUrl` ever starts lowercasing paths, `.ilike()` still works correctly (`.ilike()` is a superset of `.like()` for all-lowercase inputs). |

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
- The vitest test runner (NOT bun test) must be used for `apps/web-platform/` tests per `bunfig.toml` pathIgnorePatterns (see #1469). Use `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
- **[Deepen-plan finding]** Do NOT use `.like()` -- use `.ilike()`. The `normalizeRepoUrl` utility at `lib/repo-url.ts` explicitly preserves path case (lines 8-10). Two users setting up the same org with different casing would produce case-variant `repo_url` values that a case-sensitive `.like()` would fail to match. `.ilike()` maps to Postgres `ILIKE` which is case-insensitive.
- **[Deepen-plan finding]** The `extractGitHubOwner` helper must be **exported** from `resolve-installation-id.ts` so the test file can import and test it directly without going through the full `resolveInstallationId` mock chain.
