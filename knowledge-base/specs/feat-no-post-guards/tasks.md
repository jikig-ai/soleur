# Tasks: feat/no-post-guards

Source plan: `knowledge-base/plans/2026-03-15-feat-no-post-guards-x-bsky-plan.md`

## Phase 1: Setup

- [ ] 1.1 Merge origin/main into feature branch (`git fetch origin main && git merge origin/main`)
- [ ] 1.2 Read all files to modify before editing (x-community.sh, bsky-community.sh, SKILL.md, scheduled-content-publisher.yml)
- [ ] 1.3 Verify `scheduled-community-monitor.yml` does NOT set any `*_ALLOW_POST` variables (read-only check)

## Phase 2: Core Implementation

- [ ] 2.1 Add `X_ALLOW_POST` guard to `cmd_post_tweet()` in `plugins/soleur/skills/community/scripts/x-community.sh`
  - [ ] 2.1.1 Add guard as first statement in function: `if [[ "${X_ALLOW_POST:-}" != "true" ]]` with `return 1`
  - [ ] 2.1.2 Add `# Guard: require explicit opt-in to post.` comment before the guard
  - [ ] 2.1.3 Add `X_ALLOW_POST` to script header environment variable documentation
- [ ] 2.2 Add `BSKY_ALLOW_POST` guard to `cmd_post()` in `plugins/soleur/skills/community/scripts/bsky-community.sh`
  - [ ] 2.2.1 Add guard as first statement in function: `if [[ "${BSKY_ALLOW_POST:-}" != "true" ]]` with `return 1`
  - [ ] 2.2.2 Add `# Guard: require explicit opt-in to post.` comment before the guard
  - [ ] 2.2.3 Add `BSKY_ALLOW_POST` to script header environment variable documentation
- [ ] 2.3 Add `BASH_SOURCE` guard to `bsky-community.sh` (replace bare `main "$@"` with guarded version)
- [ ] 2.4 Add `X_ALLOW_POST: "true"` to `scheduled-content-publisher.yml` publish step env block
- [ ] 2.5 Update `plugins/soleur/skills/community/SKILL.md` with post guard notes for X and Bluesky

## Phase 3: Testing

- [ ] 3.1 Verify `bash -n` syntax check passes on both modified scripts
- [ ] 3.2 Source x-community.sh and verify guard blocks posting when `X_ALLOW_POST` is unset
- [ ] 3.3 Source x-community.sh and verify guard blocks posting when `X_ALLOW_POST=false`
- [ ] 3.4 Source x-community.sh and verify guard allows posting when `X_ALLOW_POST=true` (will fail at credential check, which is expected)
- [ ] 3.5 Source bsky-community.sh and verify guard blocks posting when `BSKY_ALLOW_POST` is unset
- [ ] 3.6 Source bsky-community.sh and verify guard blocks posting when `BSKY_ALLOW_POST=false`
- [ ] 3.7 Source bsky-community.sh and verify guard allows posting when `BSKY_ALLOW_POST=true` (will fail at credential check, which is expected)
- [ ] 3.8 Verify `scheduled-community-monitor.yml` has no `*_ALLOW_POST` in env block
- [ ] 3.9 Verify `scheduled-content-publisher.yml` has `X_ALLOW_POST: "true"` in env block
- [ ] 3.10 Run `bun test` to ensure no regressions
