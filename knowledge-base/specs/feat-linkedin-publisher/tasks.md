# Tasks: Content-publisher LinkedIn channel automation

## Phase 1: Setup

- [x] 1.1 Add `LINKEDIN_SCRIPT` variable to `scripts/content-publisher.sh` header (alongside `X_SCRIPT`)
- [x] 1.2 Verify `linkedin-community.sh` exists at the expected path and is executable
- [x] 1.3 Add `LINKEDIN_SCRIPT` validation in `main()` when `LINKEDIN_ACCESS_TOKEN` is set (matches X pattern at lines 338-340)

## Phase 2: Core Implementation

- [x] 2.1 Add `linkedin` case to `channel_to_section()` returning `"LinkedIn"` (`scripts/content-publisher.sh:56`)
- [x] 2.2 Add `create_linkedin_fallback_issue()` function following `create_x_fallback_issue()` pattern
- [x] 2.3 Add `post_linkedin()` function with credential check, content extraction, and error propagation (return 1 on failure, not 0)
- [x] 2.4 Add `linkedin)` case to main channel dispatch loop (`scripts/content-publisher.sh:404`)
- [x] 2.5 Add `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` env vars to `scheduled-content-publisher.yml` publish step
- [x] 2.6 Update `scheduled-content-publisher.yml` header comment to mention LinkedIn alongside Discord and X

## Phase 3: Testing

- [x] 3.1 Update `channel_to_section` test: change `"linkedin"` unknown-channel assertion to `"mastodon"` (`test/content-publisher.test.ts:314`)
- [x] 3.2 Add test: `channel_to_section "linkedin"` returns `"LinkedIn"`
- [x] 3.3 Add test: `post_linkedin` skips gracefully when `LINKEDIN_ACCESS_TOKEN` is unset
- [x] 3.4 Add test: `post_linkedin` returns error when `linkedin-community.sh` fails (mock script)
- [x] 3.5 Add `## LinkedIn` section to `test/helpers/sample-content.md` for extraction tests
- [x] 3.5b Add test: `extract_section` correctly extracts `## LinkedIn` section content
- [x] 3.6 Run full test suite: `bun test test/content-publisher.test.ts`
- [x] 3.7 Run `scripts/content-publisher.sh` dry validation (no credentials, verify no crash)
