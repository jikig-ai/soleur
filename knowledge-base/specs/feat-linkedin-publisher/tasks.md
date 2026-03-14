# Tasks: Content-publisher LinkedIn channel automation

## Phase 1: Setup

- [ ] 1.1 Add `LINKEDIN_SCRIPT` variable to `scripts/content-publisher.sh` header (alongside `X_SCRIPT`)
- [ ] 1.2 Verify `linkedin-community.sh` exists at the expected path and is executable

## Phase 2: Core Implementation

- [ ] 2.1 Add `linkedin` case to `channel_to_section()` returning `"LinkedIn"` (`scripts/content-publisher.sh:56`)
- [ ] 2.2 Add `create_linkedin_fallback_issue()` function following `create_x_fallback_issue()` pattern
- [ ] 2.3 Add `post_linkedin()` function with credential check, content extraction, and error propagation (return 1 on failure, not 0)
- [ ] 2.4 Add `linkedin)` case to main channel dispatch loop (`scripts/content-publisher.sh:404`)
- [ ] 2.5 Add `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` env vars to `scheduled-content-publisher.yml` publish step

## Phase 3: Testing

- [ ] 3.1 Update `channel_to_section` test: change `"linkedin"` unknown-channel assertion to `"mastodon"` (`test/content-publisher.test.ts:314`)
- [ ] 3.2 Add test: `channel_to_section "linkedin"` returns `"LinkedIn"`
- [ ] 3.3 Add test: `post_linkedin` skips gracefully when `LINKEDIN_ACCESS_TOKEN` is unset
- [ ] 3.4 Add test: `post_linkedin` returns error when `linkedin-community.sh` fails (mock script)
- [ ] 3.5 Add `## LinkedIn` section to `test/helpers/sample-content.md` for extraction tests
- [ ] 3.6 Run full test suite: `bun test test/content-publisher.test.ts`
- [ ] 3.7 Run `scripts/content-publisher.sh` dry validation (no credentials, verify no crash)
