# Tasks: Bluesky and LinkedIn Company Page Distribution

## Phase 1: Bluesky Integration in content-publisher.sh

- [ ] 1.1 Add `bluesky` mapping to `channel_to_section()` in `scripts/content-publisher.sh`
- [ ] 1.2 Add `BSKY_SCRIPT` path variable after line 32
- [ ] 1.3 Add `post_bluesky()` function with graceful skip pattern
- [ ] 1.4 Add `create_bluesky_fallback_issue()` function
- [ ] 1.5 Add `bluesky` case to main dispatch `while` loop
- [ ] 1.6 Add `bsky-community.sh` existence validation in `main()`
- [ ] 1.7 Update env var documentation in file header comment

## Phase 2: LinkedIn Company Page (Separate Author)

- [ ] 2.1 Add `--author` flag to `linkedin-community.sh` `cmd_post_content()`
- [ ] 2.2 Add `post_linkedin_company()` function to `content-publisher.sh`
- [ ] 2.3 Update `linkedin-company` case in main dispatch to use `post_linkedin_company()`
- [ ] 2.4 Update env var documentation in file header

## Phase 3: social-distribute SKILL.md Updates

- [ ] 3.1 Add Phase 5.8: Bluesky Post content generation template
- [ ] 3.2 Update Phase 6 presentation to include Bluesky
- [ ] 3.3 Update Phase 9 Step 3 channels field logic
- [ ] 3.4 Update Phase 9 Step 4 content file template with `## Bluesky` section
- [ ] 3.5 Update Phase 10 summary
- [ ] 3.6 Update Headless Mode channel defaults

## Phase 4: Workflow Updates

- [ ] 4.1 Update `scheduled-content-generator.yml` channels from `discord, x` to `discord, x, bluesky, linkedin-company`
- [ ] 4.2 Add Bluesky and LinkedIn secrets to `scheduled-content-publisher.yml`
- [ ] 4.3 Remove `TODO(#590)` comment and add `LINKEDIN_ALLOW_POST: "true"`

## Phase 5: Tests

- [ ] 5.1 Add `bluesky` to `channel_to_section` test in `test/content-publisher.test.ts`
- [ ] 5.2 Add `## Bluesky` section to `test/helpers/sample-content.md`
- [ ] 5.3 Add `extract_section` test for Bluesky
- [ ] 5.4 Add `post_bluesky` graceful skip test
- [ ] 5.5 Update `test/helpers/sample-frontmatter.md` channels field
- [ ] 5.6 Add `post_linkedin_company` graceful skip tests (no token, no org ID)
