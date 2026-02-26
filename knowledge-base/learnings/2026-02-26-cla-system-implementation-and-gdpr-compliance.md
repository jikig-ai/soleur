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

### 5. Dual-Location Legal Docs

Legal docs exist in two locations with different frontmatter:
- `docs/legal/*.md` -- source, YAML frontmatter (`type`, `jurisdiction`, `generated-date`)
- `plugins/soleur/docs/pages/legal/*.md` -- Eleventy site, different frontmatter (`layout`, `permalink`, `description`)

Body content must match. Cross-references use different link formats (relative `.md` vs absolute `.html`). Always update both locations together.

## Session Errors

1. **Wrong action repo name** -- `cla-assistant/cla-assistant-action` → 404. Correct: `contributor-assistant/github-action`
2. **Gist under wrong account** -- Created under personal `deruelle` instead of org `jikig-ai`. User caught this.
3. **Blank gist creation** -- `echo '[]' | gh gist create` failed with "cannot be blank". Used `echo '{"signatures": []}' | gh gist create` instead. Ultimately moot since we switched to repo-based storage.
4. **Edit without Read** -- Tried to edit Eleventy privacy-policy.md without reading it first. Always Read before Edit.
5. **GDPR policy missed** -- Added CLA processing to Privacy Policy and DPA but forgot the GDPR Policy. Caught by architecture-strategist agent during review.
6. **Review agent false positives** -- Code quality agent reported README badge as 3.3.7 (was actually 3.4.0). Consistency audit claimed T&C missing CLA references (they were present). Always verify review agent findings before acting.

## Key Insight

When introducing a new data processing activity, create a checklist of ALL privacy/GDPR documents that need updating -- not just the obvious ones. The GDPR Policy requires the most thorough treatment (balancing test, processing register) but is easy to overlook because the Privacy Policy feels like "the" privacy document. Review agents catch gaps that manual passes miss, but their findings must be verified since they produce false positives.

## Tags

category: integration-issues
module: legal, ci, gdpr
