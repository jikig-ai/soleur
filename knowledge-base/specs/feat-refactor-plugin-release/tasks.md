# Tasks: refactor plugin release workflow to use reusable-release.yml

## Phase 1: Implementation

- [ ] 1.1 Replace `.github/workflows/version-bump-and-release.yml` contents with thin caller pattern (use Python via Bash tool -- Edit/Write tools are blocked by security hook)
  - [ ] 1.1.1 Keep `name: Version Bump and Release`
  - [ ] 1.1.2 Keep `on: push: branches: [main]` and `workflow_dispatch` with `bump_type` input
  - [ ] 1.1.3 Add `permissions: contents: write, packages: write`
  - [ ] 1.1.4 Add single `release` job calling `./.github/workflows/reusable-release.yml`
  - [ ] 1.1.5 Pass inputs: `component: plugin`, `component_display: "Soleur"`, `path_filter: "plugins/soleur/"`, `tag_prefix: "v"`, `bump_type`, `force_run`
  - [ ] 1.1.6 Add `secrets: inherit`

## Phase 2: Verification

- [ ] 2.1 Trigger `workflow_dispatch` with `bump_type=patch` to verify version continuity
  - [ ] 2.1.1 Confirm new release tag is `v3.23.2` (or next sequential version after current latest)
  - [ ] 2.1.2 Confirm GitHub Release is created with correct title and notes
  - [ ] 2.1.3 Confirm Discord notification is sent
- [ ] 2.2 Verify push trigger skips when no plugin files changed (check a recent non-plugin commit's workflow run)
