# Learning: CLA System Implementation and GDPR Compliance

## Problem

Implementing a Contributor License Agreement system for a BSL 1.1 licensed project requires coordinating legal documents, CI automation, and GDPR compliance across multiple document locations. Several gotchas emerged during implementation.

## Solution

### 1. CLA Assistant GitHub Action: Correct Repository

The CLA Assistant action lives at `contributor-assistant/github-action` (NOT `cla-assistant/cla-assistant-action`, which 404s). Pin to SHA, not tag:

```yaml
uses: contributor-assistant/github-action@ca4a40a7d1004f18d9960b404b97e5f30a505a08 # v2.6.1
```

### 2. Signature Storage: Repo Branch > Gist

Use repo-based storage on a dedicated `cla-signatures` branch instead of gist-based storage:
- Gists must be owned by the org, not a personal account -- easy to get wrong
- Repo branch keeps signatures under the same access controls, backup, and audit trail
- Requires `contents: write` permission instead of a gist-scoped PAT

### 3. `pull_request_target` Security

The workflow uses `pull_request_target` (runs with write access to base repo). Hard rule: **never add `actions/checkout` or `run:` steps** that could execute attacker-controlled code from fork PRs. The CLA action operates entirely via GitHub API.

Additional security from review:
- Remove `actions: write` permission (unnecessary, expands attack surface)
- Add `github.event.issue.pull_request` guard on `issue_comment` trigger to prevent firing on plain issues

### 4. GDPR: Update ALL Privacy Documents

When adding a new data processing activity (CLA signatures), you must update **all three** GDPR-related documents, not just the one that seems most relevant:

| Document | What to add |
|----------|------------|
| **Privacy Policy** | New section describing data collected, legal basis, retention |
| **Data Protection Disclosure** | New processing activity entry |
| **GDPR Policy** | New lawful basis section with balancing test + processing register entry |

The GDPR policy was missed during initial implementation and caught by the architecture-strategist review agent. The GDPR policy requires the most detail (three-part balancing test).

### 5. Same-Repo Storage Eliminates PAT Requirement

The CLA action has two code paths for writing signatures:
- **With `remote-organization-name`/`remote-repository-name`**: Uses `getPATOctokit()` which requires a real PAT
- **Without those params**: Uses `getDefaultOctokitClient()` which uses `GITHUB_TOKEN`

Since signatures are stored in the same repo (just on a different branch), the remote params are unnecessary. Removing them lets the action fall back to `GITHUB_TOKEN`, eliminating PAT management entirely:

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  PERSONAL_ACCESS_TOKEN: ${{ secrets.GITHUB_TOKEN }}
with:
  path-to-signatures: "signatures/cla.json"
  branch: "cla-signatures"
  # NO remote-organization-name or remote-repository-name
```

### 6. Signatures File Format

The `cla.json` file must use `{"signedContributors": []}`, NOT `[]`. A bare array causes `Cannot read properties of undefined (reading 'some')` because the action accesses `.signedContributors.some()`.

### 7. `issue_comment` Filter Must Allow Signing Comments

Do NOT filter `issue_comment` events by `comment.body == 'recheck'`. The CLA action processes both signing comments and recheck comments internally. Only guard against plain issues (non-PRs):

```yaml
if: |
  (github.event_name == 'pull_request_target') ||
  (github.event_name == 'issue_comment' &&
   github.event.issue.pull_request)
```

The body filter was a review agent suggestion that broke signing -- always test the full sign+verify flow before shipping.

### 8. `pull_request_target` Chicken-and-Egg

Workflow changes to `pull_request_target` triggers can't be tested on the PR that introduces them -- the workflow runs from **main**, not the PR branch. Solutions:
- Add admin bypass to the branch ruleset for bootstrapping
- Merge the fix with `gh pr merge --admin`, then test on a subsequent PR
- Remove the admin bypass after verification (or keep for maintainer convenience)

### 9. Signing Doesn't Update Commit Check

After a user signs via `issue_comment`, the CLA action records the signature but does NOT update the commit check status on the PR. The check stays `FAILURE` until a new `pull_request_target` event fires. Users must push a new commit (even empty: `git commit --allow-empty`) to trigger re-evaluation.

### 10. Dual-Location Legal Docs

Legal docs exist in two locations with different frontmatter:
- `docs/legal/*.md` -- source, YAML frontmatter (`type`, `jurisdiction`, `generated-date`)
- `plugins/soleur/docs/pages/legal/*.md` -- Eleventy site, different frontmatter (`layout`, `permalink`, `description`)

Body content must match. Cross-references use different link formats (relative `.md` vs absolute `.html`). Always update both locations together.

## Session Errors

### Session 1 (Implementation)

1. **Wrong action repo name** -- `cla-assistant/cla-assistant-action` → 404. Correct: `contributor-assistant/github-action`
2. **Gist under wrong account** -- Created under personal `deruelle` instead of org `jikig-ai`. User caught this.
3. **Blank gist creation** -- `echo '[]' | gh gist create` failed with "cannot be blank". Used `echo '{"signatures": []}' | gh gist create` instead. Ultimately moot since we switched to repo-based storage.
4. **Edit without Read** -- Tried to edit Eleventy privacy-policy.md without reading it first. Always Read before Edit.
5. **GDPR policy missed** -- Added CLA processing to Privacy Policy and DPA but forgot the GDPR Policy. Caught by architecture-strategist agent during review.
6. **Review agent false positives** -- Code quality agent reported README badge as 3.3.7 (was actually 3.4.0). Consistency audit claimed T&C missing CLA references (they were present). Always verify review agent findings before acting.

### Session 2 (Post-Merge Setup)

7. **Wrong assumption about GITHUB_TOKEN** -- Assumed swapping `secrets.PERSONAL_ACCESS_TOKEN` → `secrets.GITHUB_TOKEN` was sufficient. The action's `getPATOctokit()` path was triggered by `remote-organization-name`/`remote-repository-name` params, not the token name. Fix: remove the remote params.
8. **Wrong signatures file format** -- Created `cla.json` with `[]`. Action expects `{"signedContributors": []}`. Caused JS runtime error.
9. **Overly restrictive `issue_comment` filter** -- `comment.body == 'recheck'` guard (from review agent suggestion) blocked signing comments. The action handles comment filtering internally.
10. **`pull_request_target` chicken-and-egg** -- Workflow fixes can't be tested on the PR that introduces them. Required admin bypass merges for #326 and #327.
11. **Signing doesn't update commit check** -- After signing, PR check stayed FAILURE. Required empty commit push to trigger `pull_request_target` re-evaluation.

## Key Insight

Two lessons compound here. First: when introducing a new data processing activity, checklist ALL privacy/GDPR documents -- the GDPR Policy is the easiest to forget but requires the most detail. Second: `pull_request_target` workflows have a bootstrapping problem -- you can't test them on the PR that introduces them. Plan for admin bypass merges and post-merge smoke tests. Review agent suggestions (like body filters) can break flows they don't fully understand -- always smoke test the complete user journey (open PR → sign → verify green check) before shipping.

## Tags

category: integration-issues
module: legal, ci, gdpr
