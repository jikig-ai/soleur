# Learning: git tag --sort=-version:refname requires all tags fetched

## Problem

When computing the latest version from prefixed git tags (e.g., `web-v0.1.0`, `telegram-v0.2.0`), `gh release view` cannot be used because it returns the single "latest" release across ALL tag namespaces — not filtered by prefix. And `gh release list` sorts by creation date, not semver, so a manually created hotfix `web-v0.1.5` after `web-v0.2.0` would be returned as "latest."

The natural alternative is `git tag --list 'web-v*' --sort=-version:refname | head -1`, which sorts tags by semver. But GitHub Actions `actions/checkout` with `fetch-depth: 2` only fetches tags reachable from the last 2 commits. Tags on older commits are invisible, causing the version to reset to `0.0.0`.

## Solution

Add `git fetch --tags` after checkout to ensure all tags are available:

```yaml
- uses: actions/checkout@... # v4.x
  with:
    fetch-depth: 2

- name: Fetch all tags
  run: git fetch --tags

- name: Get latest version
  run: |
    LATEST_TAG=$(git tag --list "${TAG_PREFIX}*" --sort=-version:refname | head -1)
    if [ -z "$LATEST_TAG" ]; then
      CURRENT="0.0.0"
    else
      CURRENT="${LATEST_TAG#"$TAG_PREFIX"}"
    fi
```

This fetches only tag refs (not full history), adding minimal overhead while making all version tags available for sorting.

## Key Insight

`git tag --sort=-version:refname` is semver-aware and handles prefixed tags correctly (e.g., `web-v0.10.0 > web-v0.9.0`). But it only sees locally available tags. In CI with shallow clones, always run `git fetch --tags` before version computation. The existing plugin workflow avoids this by using `gh release view` (API call, no local tags needed), but that approach breaks when multiple tag namespaces coexist in a monorepo.

## Tags
category: integration-issues
module: ci-cd, github-actions, versioning
severity: high
