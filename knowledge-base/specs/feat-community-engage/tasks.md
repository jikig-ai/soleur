# Tasks: feat(community): add engage sub-command for X mention engagement

## Phase 1: Shell Script (x-community.sh)

- [x] 1.1 Add `get_authenticated_user_id` helper function to `x-community.sh`
  - Call `GET /2/users/me`, extract `.data.id`, return plain string to stdout
  - Reuse `oauth_sign "GET" "${X_API}/2/users/me"` for signing (no extra params)
  - Same error handling as `x_request` (401, 403, 429)
- [x] 1.2 Add `cmd_fetch_mentions` function to `x-community.sh`
  - Accept `--max-results N` (default 10, validate numeric range 5-100) and `--since-id ID` (validate numeric) flags
  - Use `${1:-}` guards for optional positional args (set -euo pipefail compliance)
  - Call `get_authenticated_user_id` to resolve user ID
  - Build query params: `max_results`, `since_id` (if provided), `tweet.fields=author_id,created_at,conversation_id`, `expansions=author_id`, `user.fields=username,name`
  - Include ALL query params in OAuth signature base string (same pattern as `cmd_fetch_metrics`)
  - Append query string to URL separately for curl call
  - Transform response: match `includes.users` to mentions by `author_id` field (not array index -- same user may mention multiple times)
  - Handle empty `data` array: output `{"mentions":[],"meta":{"result_count":0}}` cleanly
  - Output JSON to stdout matching the plan's schema
- [x] 1.3 Register `fetch-mentions` in the `main()` case dispatch
- [x] 1.4 Update the usage text in `main()` to include `fetch-mentions` with arg description

## Phase 2: SKILL.md Engage Sub-Command

- [x] 2.1 Add `### engage` sub-command section to `SKILL.md`
  - Document the fetch-draft-approve-post flow (6 steps)
  - Specify platform detection requirement (X must be enabled)
  - Reference brand-guide.md `## Voice` and `## Channel Notes > ### X/Twitter` for draft generation
  - Document `--headless` behavior: skip all mentions with summary message, no posting
  - Document since-id state file (`.soleur/x-engage-since-id`, resolved via `git rev-parse --show-toplevel`)
  - Document "Skip all remaining" as 4th option after first mention
  - Document Edit flow: validate 280-char limit, re-prompt if over
  - Handle missing brand guide: warn but proceed with professional tone
- [x] 2.2 Update the sub-command menu in SKILL.md
  - Add option 4: `engage -- Reply to recent X/Twitter mentions`
- [x] 2.3 Add `$ARGUMENTS` bypass path for `engage` sub-command
  - Support: `community engage [--max-results N] [--headless]`
  - Strip `--headless` from $ARGUMENTS before processing remaining args (headless convention)

## Phase 3: Community-Manager Agent Update

- [x] 3.1 Add Capability 4: Mention Engagement section to `community-manager.md`
  - Step 1: Fetch mentions via `x-community.sh fetch-mentions` (use prose placeholders, NO `$()` in bash blocks)
  - Step 2: Read brand-guide.md `## Voice` and `## Channel Notes > ### X/Twitter` (if exists; warn if missing)
  - Step 3: Draft reply per mention (280-char limit enforced during generation, brand voice, declarative tone)
  - Step 4: Present via AskUserQuestion (Accept/Edit/Skip/Skip All)
  - Step 5: Post accepted replies via `x-community.sh post-tweet --reply-to <mention_id>`
  - Step 6: Update since-id state file ONLY after all mentions processed
  - Step 7: Display session summary (processed, posted, skipped counts)
- [x] 3.2 Add since-id state management instructions
  - Read: `cat <repo_root>/.soleur/x-engage-since-id 2>/dev/null || true` (use prose, not $())
  - Validate: numeric check, treat non-numeric as missing
  - Pass `--since-id <value>` to `fetch-mentions` if valid file exists
  - Write: `mkdir -p <repo_root>/.soleur && chmod 600 ... && echo <newest_id> > ...` after all mentions processed
- [x] 3.3 Verify no `$()` command substitution in bash blocks (learning 2026-02-22)
  - Use angle-bracket placeholders: `<user_id>`, `<since_id>`, `<mention_id>`
  - Or separate bash blocks per individual command

## Phase 4: Gitignore and State

- [x] 4.1 Add `.soleur/` to `.gitignore` if not already present

## Phase 5: Testing

- [x] 5.1 Create `test/x-community.test.ts` with tests for `fetch-mentions` command
  - Test: missing credentials exit 1
  - Test: `--max-results abc` exits 1 (non-numeric)
  - Test: `--max-results 200` exits 1 (out of range)
  - Test: `--since-id abc` exits 1 (non-numeric)
  - Test: empty mentions response produces clean JSON with `result_count: 0`
  - Test: `--since-id 12345` passes `since_id=12345` to API query params
  - Follow existing test pattern from `test/pre-merge-rebase.test.ts` (bun:test, Bun.spawnSync)
- [ ] 5.2 Manual verification: run `x-community.sh fetch-mentions` against live API
- [ ] 5.3 Manual verification: run `/soleur:community engage` end-to-end
