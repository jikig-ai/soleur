# Learning: GitHub Ruleset PUT API replaces entire payload

## Problem

When updating a GitHub repository ruleset via `PUT /repos/{owner}/{repo}/rulesets/{id}`, the API replaces the **entire** ruleset configuration -- not just the fields you send. If the request body includes only `rules` but omits `bypass_actors` and `conditions`, the update silently strips admin bypass privileges and branch scope from the ruleset.

## Solution

Always include all three top-level fields in the PUT payload:

- `bypass_actors`: preserves OrganizationAdmin and RepositoryRole bypass privileges
- `conditions`: preserves branch targeting (e.g., `~DEFAULT_BRANCH`)
- `rules`: the updated rules array with the new required status checks

Before executing the PUT, fetch the current ruleset state with `gh api repos/{owner}/{repo}/rulesets/{id}` and verify the payload includes the existing `bypass_actors` and `conditions` verbatim.

## Key Insight

The GitHub Ruleset API uses full-replacement semantics on PUT, not partial-update (PATCH). This is a common API anti-pattern where the developer expects merge semantics but gets replace semantics. The deepen-plan phase caught this during review -- the original plan only included `rules` in the payload.

## Tags

category: integration-issues
module: github-actions
