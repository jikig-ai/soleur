# Tasks: feat(community): add engage sub-command for X mention engagement

## Phase 1: Shell Script (x-community.sh)

- [ ] 1.1 Add `get_authenticated_user_id` helper function to `x-community.sh`
  - Call `GET /2/users/me`, extract `.data.id`, return plain string
  - Reuse `oauth_sign` for signing
- [ ] 1.2 Add `cmd_fetch_mentions` function to `x-community.sh`
  - Accept `--max-results N` (default 10, validate numeric) and `--since-id ID` flags
  - Call `GET /2/users/{id}/mentions` with query params: `max_results`, `since_id`, `tweet.fields=author_id,created_at,conversation_id`, `expansions=author_id`, `user.fields=username,name`
  - Include query params in OAuth signature (same pattern as `cmd_fetch_metrics`)
  - Transform response: flatten `includes.users` into mention objects for easier consumption
  - Output JSON to stdout matching the plan's schema
- [ ] 1.3 Register `fetch-mentions` in the `main()` case dispatch
- [ ] 1.4 Handle empty mentions (no data array) -- output `{"mentions":[],"meta":{"result_count":0}}` instead of jq error
- [ ] 1.5 Update the usage text in `main()` to include `fetch-mentions`

## Phase 2: SKILL.md Engage Sub-Command

- [ ] 2.1 Add `### engage` sub-command section to `SKILL.md`
  - Document the fetch-draft-approve-post flow
  - Specify platform detection requirement (X must be enabled)
  - Reference brand-guide.md for draft generation
  - Document `--headless` behavior (skip all, no posting)
  - Document `--since-id` state file (`.soleur/x-engage-since-id`)
- [ ] 2.2 Update the sub-command menu in SKILL.md
  - Add option 4: `engage -- Reply to recent X/Twitter mentions`
- [ ] 2.3 Add `$ARGUMENTS` bypass path for `engage` sub-command
  - Support: `community engage [--max-results N] [--headless]`

## Phase 3: Community-Manager Agent Update

- [ ] 3.1 Add Capability 4: Mention Engagement section to `community-manager.md`
  - Step 1: Fetch mentions via `x-community.sh fetch-mentions`
  - Step 2: Read brand-guide.md `## Voice` and `## Channel Notes > ### X/Twitter`
  - Step 3: Draft reply per mention (280-char limit, brand voice)
  - Step 4: Present via AskUserQuestion (Accept/Edit/Skip)
  - Step 5: Post accepted replies via `x-community.sh post-tweet --reply-to`
  - Step 6: Update since-id state file
  - Step 7: Display session summary
- [ ] 3.2 Add since-id state management instructions
  - Read from `.soleur/x-engage-since-id` (resolve via `git rev-parse --show-toplevel`)
  - Pass `--since-id` to `fetch-mentions` if file exists
  - Write `meta.newest_id` after processing

## Phase 4: Gitignore and State

- [ ] 4.1 Add `.soleur/` to `.gitignore` if not already present

## Phase 5: Testing

- [ ] 5.1 Create `test/x-community.test.ts` with tests for `fetch-mentions` command
  - Test: missing credentials exit 1
  - Test: `--max-results` validates numeric input
  - Test: empty mentions response produces clean JSON
  - Test: `--since-id` flag is passed to API call
- [ ] 5.2 Manual verification: run `x-community.sh fetch-mentions` against live API
- [ ] 5.3 Manual verification: run `/soleur:community engage` end-to-end
