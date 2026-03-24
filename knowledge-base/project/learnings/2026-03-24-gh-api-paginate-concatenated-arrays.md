# Learning: gh api --paginate concatenates arrays on multi-page responses, breaking --argjson

## Problem

When using `gh api --paginate` on endpoints that return JSON arrays (e.g., `/repos/{owner}/{repo}/stargazers`), the CLI outputs separate JSON arrays per page rather than merging them into a single array. On single-page responses this is invisible — the output is a valid single array. On multi-page responses (30+ items at default page size), the output is `[...page1...][...page2...]` — concatenated arrays.

This is valid as a jq input stream (`echo '[1][2]' | jq '.[]'` works), but it is NOT valid as a single JSON argument. Passing it to `jq --argjson` fails with `jq: invalid JSON text passed to --argjson`.

The plan for this feature verified `--paginate` behavior live against a repo with 5 stars (single page) and concluded the output was valid JSON. The multi-page concatenation behavior was only caught by a review agent analyzing scalability.

## Solution

Pipe `--paginate` output through `jq -s 'add // []'` to merge all page arrays into a single array:

```bash
# BAD: breaks at 30+ items (multi-page)
stargazers=$(gh api "repos/${repo}/stargazers" --paginate 2>&1)
jq -n --argjson stargazers "$stargazers" '{...}'

# GOOD: works at any scale
stargazers=$(gh api "repos/${repo}/stargazers?per_page=100" \
  --paginate 2>&1 | jq -s 'add // []')
jq -n --argjson stargazers "$stargazers" '{...}'
```

The `add // []` handles: multi-page (merges arrays), single-page (identity), and empty response (returns `[]`).

Also add `?per_page=100` to reduce API pages by ~3x (default is 30/page).

## Key Insight

**Single-page API verification does not validate pagination logic.** When a plan verifies an API call live against low-volume data, it only exercises the single-page path. The pagination threshold must be tested explicitly — either by forcing pagination (`per_page=10`) or testing against a high-volume repo. This is a class of verification gap where "works on my data" masks a latent bug.

The general rule for `gh api --paginate` with array endpoints: always pipe through `jq -s 'add // []'` regardless of current data volume.

## Session Errors

1. **Plan prescribed --paginate as producing valid single-array JSON** — The plan stated "Verified live that --paginate merges arrays into valid JSON" based on a 5-star repo (single page only). **Recovery:** Performance review agent caught the multi-page concatenation behavior. Fixed by piping through `jq -s 'add // []'`. **Prevention:** When plans verify API pagination behavior, require testing at multi-page scale (force with `per_page=10` or use a high-volume public repo).

2. **Plan prescribed unnecessary JSON validation guard** — The plan included a `jq empty` defensive check that was inconsistent with sibling commands and unnecessary since `gh api` success already guarantees valid JSON. **Recovery:** Simplicity reviewer identified the inconsistency. Removed the guard. **Prevention:** Before adding defensive code, check if sibling functions in the same file use the pattern. If none do, question whether it's needed.

3. **Markdown lint failure on first commit** — `session-state.md` had missing blank lines around headings/lists (MD022, MD032). Pre-existing SKILL.md lint error (line 138) also triggered. **Recovery:** Fixed formatting, committed successfully on second attempt. **Prevention:** Write markdown with blank lines around all headings and lists from the start.

## Related Learnings

- `2026-03-04-gh-jq-does-not-support-arg-flag.md` — gh --jq does not support --arg/--argjson flags
- `2026-03-09-shell-api-wrapper-hardening-patterns.md` — Layer 3: validate JSON before consuming
- `2026-03-10-jq-generator-silent-data-loss.md` — jq generator patterns can silently drop records
- `2026-03-18-stop-hook-jq-invalid-json-guard.md` — jq parse error handling under set -euo pipefail

## Tags

category: api-integration
module: community/github-stats
severity: high
