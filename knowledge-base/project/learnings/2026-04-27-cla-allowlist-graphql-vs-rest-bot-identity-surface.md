# Learning: CLA allowlist needs GraphQL bot login, not REST `app/<slug>` form

**Date:** 2026-04-27
**Context:** PR #2908 / Issue #2907
**Category:** integration-issues
**Tags:** github-actions, cla, bot-identity, contributor-assistant, graphql-vs-rest

## Problem

The CLA workflow's allowlist (`.github/workflows/cla.yml:34`) read:

```yaml
allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude"
```

Every PR authored by the Anthropic Claude GitHub App (e.g. `soleur:fix-issue` output) failed `cla-check` until the operator amended commit authorship to `deruelle`. PR #2898 (community digest) appeared to pass CLA on `github-actions[bot]` — but the actual mechanism is different.

## Root Cause

Two distinct bot-identity surfaces with different formats, conflated for ~5 weeks:

| Surface | Used by | Returns for Anthropic App | What allowlist needs |
|---|---|---|---|
| **GraphQL `commit.author.user.login`** | `contributor-assistant/github-action@v2.6.1` (CLA) | `claude[bot]` | `claude[bot]` |
| **REST `gh pr view --json author --jq '.author.login'`** | `scheduled-bug-fixer.yml`, `bot-pr-with-synthetic-checks` | `app/claude` | `app/claude` |

Source-trace from the CLA action (verified at SHA `ca4a40a7d1004f18d9960b404b97e5f30a505a08`):

```ts
// src/graphql.ts
//   getCommitters builds: { name: committer.login || committer.name, id: committer.databaseId }
//   filteredCommitters = committers.filter((c) => c.id !== 41898282)  // github-actions[bot] auto-allowed (hardcoded)

// src/checkAllowList.ts
//   isUserNotInAllowList(committer.name) — exact-string match (with `*` wildcard support)
```

The hardcoded `41898282` filter (the GitHub Actions runner's DB ID) explains why community-digest commits cleared CLA without `github-actions[bot]` strictly needing the allowlist match — they were dropped before the allowlist check.

`app/claude` was added in commit `553d8315` (#1095, 2026-03-25) under the wrong assumption that it was the GraphQL surface; bare `claude` was added in `2d8e8c8d` (#1101) doubling down on the wrong surface. Both were dead from day one.

## Solution

Replace the dead tokens with the canonical GraphQL login, and add an inline comment explaining why this allowlist must NOT be harmonized with sibling REST-surface gates:

```yaml
# contributor-assistant resolves PR authors via GraphQL `commit.author.user.login`
# (returns `claude[bot]` for the Anthropic GitHub App, DB ID 209825114).
# REST-based gates (e.g. .github/workflows/scheduled-bug-fixer.yml) match `app/claude` —
# do NOT harmonize the two; the surfaces are different. See #2907.
allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot]"
```

Validation surface: `pull_request_target` runs the **base branch's** workflow file, so pre-merge probes are vacuous (the PR's own commits run against the OLD allowlist on `main`). Real validation is post-merge observation on the next `claude[bot]`-authored PR.

## Key Insight

When a bot identity is matched against an allowlist in CI, the matching surface dictates the format. **Always read the action's source code (or the gating script's `gh ... --jq` query) to confirm which surface is being read** before adding tokens — do not infer from sibling workflows that may match against a different surface. GitHub returns the same logical bot under different keys depending on whether you ask via REST author payload (`app/<slug>`), GraphQL committer (`<slug>[bot]`), or App installation (`<slug>`).

The contributor-assistant action's hardcoded `databaseId === 41898282` filter for `github-actions[bot]` is also an undocumented load-bearing path: any allowlist debugging that ignores it will reach wrong conclusions about why a given commit cleared CLA.

## Session Errors

- **PreToolUse `security_reminder_hook.py` blocked first Edit to `.github/workflows/cla.yml`** — Recovery: retried the same Edit and it succeeded. The hook printed an educational advisory about GitHub Actions injection vectors; the change (static-string allowlist) didn't match any of the listed risk patterns. **Prevention:** when the security_reminder hook fires on a workflow edit that introduces no untrusted-input interpolation, retry the same Edit; the hook is informational and a single retry succeeds. Not worth a new rule.

## Related

- AGENTS.md `hr-never-fake-git-author` (PR #2815) — inverse failure: worktree config drift made operator commits look like bot commits and tripped CLA. Different mechanism, same surface (CLA gate).
- `knowledge-base/project/learnings/2026-04-24-fake-git-author-bare-repo-bot-override.md` — the worktree-identity drift learning.
- `.github/workflows/scheduled-bug-fixer.yml:206-213` — correct REST-surface usage of `app/claude`.
- `contributor-assistant/github-action@v2.6.1` — pinned at `ca4a40a7d1004f18d9960b404b97e5f30a505a08` in `cla.yml:26`.
