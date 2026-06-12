# Learning: `gh ... --search` returns empty cross-repo under the in-action App token; use the List API

## Problem

The operator-digest's first live run (#5085) posted a digest whose **"What your
company built"** section read *"Nothing shipped this week"* — despite ~100 PRs
merged in the window (a Phase-4 dry-run on the same window returned 100). The
other three sections (money via `git log`, incidents via `ls`, action-needed via
`gh issue list --label`) were all accurate. The run concluded `success`; the scrub
post-step ran clean. So the pipeline mechanically worked, but the **primary section
was silently wrong** — exactly the comprehension-failure the feature exists to prevent.

## Root cause

The merged-PR read used the **Search API**:

```bash
gh pr list -R jikig-ai/soleur --state merged --search "merged:>=$SINCE" --limit 100
```

`gh pr list --search` (and `gh issue list --search`) routes to GitHub's **Search
API** (`/search/issues`), which is a distinct endpoint from the **List API**
(`/repos/{owner}/{repo}/pulls` | `/issues`). Under `claude-code-action`'s
**in-action App-installation token** (the token the agent's Bash bridge uses), a
**cross-repo Search-API query returns empty** — the #3403 cross-repo-read class,
but manifesting specifically on the Search API. The List API works cross-repo under
the same token (that is why `gh issue list --label action-required` returned all 7
items correctly).

Locally, both forms return 100 PRs — because a developer's personal token has full
Search-API access. The divergence only appears under the in-action token, so it
cannot be caught by a local dry-run; only the live run surfaced it.

A second `--search` lurked in the prior-week continuity query
(`gh issue list ... --search "Digest in:title"`). Even though it targets the action's
*own* repo, the same Search-API behaviour would have broken the liveness loop —
every week falsely reading "this is the first digest" and never emitting the
"Last week: #N" back-reference.

## Solution

Switch both reads to the **List API** + client-side filtering:

```bash
# merged PRs — filter mergedAt >= $SINCE in synthesis
gh pr list -R jikig-ai/soleur --state merged --limit 100 --json title,labels,mergedAt
# prior digest — take the highest-numbered issue whose title starts with "Digest:"
gh issue list -R jikig-ai/operator-digest --state all --json number,title --limit 20
```

Added a contract-test regression guard: any `gh pr/issue list` command that
reintroduces `--search` fails the test (comment lines documenting "NOT --search"
are exempt).

## Key insight

`--search` ≠ `--list` at the API layer. The GitHub **Search API** behaves
differently under a scoped/App-installation token than the **List/REST API** —
cross-repo Search queries can return empty while the equivalent List query
succeeds. For any read that must work inside `claude-code-action` (or any
App-installation-token context), **prefer the List API + client-side filter over
`--search`**. A local dry-run with a personal token cannot detect this — the
in-action token is the only faithful test, so a live smoke run is mandatory before
trusting a cross-repo `--search` read.

## Session Errors

- **First live digest's primary section was a false "Nothing shipped".**
  Recovery: diagnosed the Search-vs-List API divergence, switched both reads to the
  List API + client-side filter, added a regression guard.
  Prevention: the contract-test guard now rejects `--search` in `gh pr/issue list`
  commands; this learning documents the API-layer distinction. A live smoke run
  (not just a local dry-run) is required to catch in-action-token-only behaviour.

## Tags
category: integration-issues
module: plugins/soleur/skills/operator-digest
