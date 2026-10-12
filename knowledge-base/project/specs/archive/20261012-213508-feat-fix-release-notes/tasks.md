# Tasks: fix release notes empty on PR merge

## Phase 1: Fix PR Number Extraction

- [x] 1.1 Replace `head -1` regex with GitHub API commit-to-PR lookup in "Find merged PR" step
- [x] 1.2 Add `tail -1` fallback when API call fails
- [x] 1.3 Add PR validation check (verify extracted number is a PR, not an issue)

## Phase 2: Fix Discord Webhook Identity

- [x] 2.1 Add `username` and `avatar_url` fields to the Discord webhook `jq` payload

## Phase 3: Repair v3.9.2 Release

- [x] 3.1 Update v3.9.2 release body with correct changelog from PR #415 body
- [ ] 3.2 Document Discord repost as manual step (requires webhook secret)

## Phase 4: Testing

- [x] 4.1 Verify regex extraction works for single-ref commits (`feat: thing (#200)`)
- [x] 4.2 Verify regex extraction works for multi-ref commits (`feat: thing (#100) (#200)`)
- [x] 4.3 Verify no-ref commits fall through to warning path
- [x] 4.4 Verify PR validation rejects issue numbers

## Phase 5: Ship

- [ ] 5.1 Run compound
- [ ] 5.2 Commit and push
- [ ] 5.3 Create PR with `semver:patch` label
- [ ] 5.4 Merge and verify release notes are populated correctly
