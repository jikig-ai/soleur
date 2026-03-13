# Tasks: Community Agent

## Phase 1: Shell Scripts (Foundation)

- [x] 1.1 Create `skills/community/scripts/discord-community.sh`
  - Env var validation (DISCORD_BOT_TOKEN format, DISCORD_GUILD_ID numeric)
  - `messages` command: fetch channel messages with pagination
  - `members` command: fetch guild members
  - `guild-info` command: fetch guild metadata
  - `channels` command: list guild text channels
  - Error handling: exit 1 + stderr on failure
  - HTTP 401 detection with token renewal instructions
  - HTTP 429 detection with Retry-After retry
  - Malformed JSON detection
  - Make executable: `chmod +x`

- [x] 1.2 Create `skills/community/scripts/github-community.sh`
  - Auto-detect repo from git remote
  - `activity` command: recent issues/PRs/comments (N days)
  - `contributors` command: active contributors (N days)
  - `discussions` command: recent discussions (graceful skip if disabled)
  - Rate limit detection with actionable message
  - Error handling: exit 1 + stderr on failure
  - Make executable: `chmod +x`

## Phase 2: Community Manager Agent

- [x] 2.1 Create `agents/marketing/community-manager.md`
  - YAML frontmatter: name, description (third person), model: inherit
  - Include 2+ `<example>` blocks with context/user/assistant/commentary
  - Digest generation workflow (call scripts, analyze, write markdown per heading contract, post)
  - Digest file contract: ## Period, ## Activity Summary, ## Top Contributors, ## Trending Topics, ## Unanswered Questions, ## GitHub Activity
  - Digest frontmatter: period_start, period_end, generated_at, channels_analyzed
  - Check brand guide before generating Discord post
  - Health metrics workflow (call scripts, display inline)
  - Content suggestions capability

## Phase 3: Community Skill

- [x] 3.1 Create `skills/community/SKILL.md`
  - YAML frontmatter: name, description (third person)
  - Phase 0: Prerequisites check (env vars with format validation)
  - Sub-command routing: digest, health, post, welcome
  - `digest`: spawn community-manager agent (check brand guide for Discord post)
  - `health`: spawn community-manager agent
  - `post`: inform user to use `/soleur:discord-content` (no programmatic skill invocation)
  - `welcome`: generate message with brand voice, user approval, post via webhook
  - Structure sub-command workflows as Phase sections

## Phase 4: Version Bump and Documentation

- [x] 4.1 Bump version (MINOR) in plugin.json
- [x] 4.2 Update CHANGELOG.md with new entries
- [x] 4.3 Update plugins/soleur/README.md (counts, tables)
- [x] 4.4 Update root README.md version badge
- [x] 4.5 Update .github/ISSUE_TEMPLATE/bug_report.yml placeholder
