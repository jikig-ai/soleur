# Tasks: fix Discord mention injection

## Phase 1: Core Fix

- 1.1 Add `allowed_mentions: {parse: []}` to the `jq` payload in `.github/workflows/version-bump-and-release.yml` "Post to Discord" step (line 263-267)

## Phase 2: Constitution Update

- 2.1 Update the Discord webhook convention in `knowledge-base/overview/constitution.md` (line 92) to require `allowed_mentions: {parse: []}` alongside `username` and `avatar_url`

## Phase 3: Verification

- 3.1 Run markdownlint on modified files
- 3.2 Validate the YAML syntax of the modified workflow file
- 3.3 Run compound (`skill: soleur:compound`) before commit
