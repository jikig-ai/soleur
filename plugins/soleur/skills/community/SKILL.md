---
name: community
description: "This skill should be used when managing community presence across platforms (Discord, GitHub, X/Twitter). It provides sub-commands for generating digests, checking health metrics, and listing enabled platforms. Triggers on \"community digest\", \"community health\", \"community platforms\", \"community report\"."
---

# Community Management

Manage community presence across Discord, GitHub, and X/Twitter. Detects enabled platforms from environment variables and delegates data collection to platform-specific scripts.

## Arguments

`$ARGUMENTS` is parsed for a sub-command and optional flags:

```text
community [sub-command] [--headless] [--platform PLATFORM]
community engage [--max-results N] [--headless]
```

If `$ARGUMENTS` is empty or unrecognized, present the sub-command menu below.

If `--headless` is present, skip all interactive prompts and approval gates.

## Platform Detection

Detect enabled platforms by checking environment variables. A platform is enabled only when **all** its required variables are set.

| Platform | Required Variables | Detection |
|----------|-------------------|-----------|
| Discord | `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID` | `printenv DISCORD_BOT_TOKEN && printenv DISCORD_GUILD_ID` |
| GitHub | (none -- always enabled) | `gh auth status` exits 0 |
| X/Twitter | `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` | All 4 set and non-empty |

Run detection at the start of every sub-command. Report which platforms are active before proceeding.

## Scripts

Platform scripts are located at `plugins/soleur/skills/community/scripts/`:

- [discord-community.sh](./scripts/discord-community.sh) -- Discord Bot API wrapper (messages, members, guild-info, channels)
- [discord-setup.sh](./scripts/discord-setup.sh) -- Discord credential setup and validation
- [github-community.sh](./scripts/github-community.sh) -- GitHub API wrapper (activity, contributors, discussions)
- [x-community.sh](./scripts/x-community.sh) -- X/Twitter API v2 wrapper (fetch-metrics, fetch-mentions, fetch-timeline, fetch-user-timeline, post-tweet)
- [x-setup.sh](./scripts/x-setup.sh) -- X/Twitter credential setup and validation

## Sub-Commands

### `digest`

Generate a multi-platform community digest. Spawns the `community-manager` agent with digest instructions.

1. Run platform detection
2. Spawn agent: `community-manager` with prompt: "Generate a community digest covering the last 7 days. Enabled platforms: [list]. Collect data from each enabled platform and produce a unified digest."
3. The agent writes the digest to `knowledge-base/support/community/YYYY-MM-DD-digest.md`

If `--headless` is set, skip the Discord posting approval gate (the agent handles this).

### `health`

Display community health metrics across all enabled platforms. Spawns the `community-manager` agent with health instructions.

1. Run platform detection
2. Spawn agent: `community-manager` with prompt: "Display community health metrics. Enabled platforms: [list]. Show metrics from each enabled platform."
3. Metrics are displayed inline (no file output)

### `platforms`

List all platforms with their configuration status. Does NOT spawn an agent -- runs directly.

1. Run platform detection
2. For each platform, display:

```text
Platform Status
===============

Discord:  [enabled] | [not configured -- missing DISCORD_BOT_TOKEN, DISCORD_GUILD_ID]
GitHub:   [enabled] | [not configured -- gh CLI not authenticated]
X/Twitter: [enabled] | [not configured -- missing X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET]
```

3. For unconfigured platforms, show setup instructions:
   - Discord: "Run `plugins/soleur/skills/community/scripts/discord-setup.sh` to configure"
   - X/Twitter: "Run `plugins/soleur/skills/community/scripts/x-setup.sh validate-credentials` to verify, or `x-setup.sh write-env` to save credentials"

### `engage`

Reply to recent X/Twitter mentions using brand-voice drafts with human approval. Spawns the `community-manager` agent with engagement instructions.

X/Twitter must be enabled (all 4 credential variables set). If X is not configured, report "X/Twitter not configured" and stop.

**Flow:**

1. Run platform detection -- verify X/Twitter is enabled
2. Read the since-id state file (`.soleur/x-engage-since-id`, resolved via `git rev-parse --show-toplevel`). If the file exists and contains a valid numeric ID, pass it as `--since-id` to the fetch command. If missing or non-numeric, skip (fetches last N mentions).
3. Spawn agent: `community-manager` with prompt: "Engage with recent X/Twitter mentions. Use Capability 4: Mention Engagement. Max results: [N]. Since ID: [ID or none]."
4. The agent fetches mentions via `x-community.sh fetch-mentions`
5. For each mention, the agent drafts a reply following brand guide voice (`knowledge-base/marketing/brand-guide.md` sections `## Voice` and `## Channel Notes > ### X/Twitter`). If the brand guide is missing, the agent warns but proceeds with a professional, declarative tone.
6. Each draft is presented via AskUserQuestion with options:
   - **Accept** -- post this reply via `x-community.sh post-tweet --reply-to <mention_id>`
   - **Edit** -- modify the reply text (validate 280-character limit; re-prompt if over)
   - **Skip** -- move to the next mention
   - **Skip all remaining** -- end the session (available after the first mention)
7. After all mentions are processed, the agent updates the since-id state file with the `newest_id` from the fetch response and displays a session summary (processed, posted, skipped counts).

**Since-id state file:**

- Path: `.soleur/x-engage-since-id` (relative to repo root)
- Format: plain text, single line containing the tweet ID
- Created on first run with `mkdir -p .soleur && chmod 600` before writing
- Updated only after all mentions are processed (not per-reply)

**Free tier degradation:** If `fetch-mentions` returns 403 (client-not-enrolled), the community-manager agent switches to manual mode — prompting for tweet URLs instead of fetching mentions automatically. The rest of the pipeline (brand-voice draft, approval, post-tweet) runs unchanged. See Capability 4 Step 1b. When the paid tier activates, this fallback is never triggered.

If `--headless` is set, skip all mentions with a summary message ("Skipped N mentions in headless mode -- engage requires interactive approval"). No replies are posted in headless mode.

## Sub-Command Menu

If no sub-command is provided, present options using the AskUserQuestion tool:

**Question:** "Which community operation would you like to run?"

**Options:**
1. **digest** -- Generate a multi-platform community digest
2. **health** -- Display community health metrics
3. **platforms** -- List platform configuration status
4. **engage** -- Reply to recent X/Twitter mentions

## Important Guidelines

- Platform detection runs at the start of every sub-command -- never assume a platform is enabled
- All Discord API calls go through `discord-community.sh` -- do not call the API directly
- All GitHub API calls go through `github-community.sh` -- do not call `gh` directly
- All X/Twitter API calls go through `x-community.sh` -- do not call the API directly
- The `community-manager` agent handles data collection, analysis, and output formatting
- This skill is the entry point; the agent does the work
- Ownership boundary: community = monitoring + engagement. Broadcasting/distribution is handled by the `social-distribute` skill.

## Platform Surface Check

After a new platform is set up and verified via its setup script (confirmed by the `platforms` sub-command showing `[enabled]`), check whether the platform has been added to all public-facing surfaces. Read each file and verify:

| File | What to look for |
|------|------------------|
| `plugins/soleur/docs/_data/site.json` | URL entry for the platform |
| `plugins/soleur/docs/pages/community.njk` | Card in the Connect section |
| `knowledge-base/marketing/brand-guide.md` | Platform handle mention |

If any surface is missing, output a warning:

```text
[WARNING] Platform <platform-name> is missing from: <list-of-files>.
These files need updating before the integration is complete.
Consider filing: gh issue create --title 'feat(docs): add <platform-name> to website and brand guide'
```

This check does not block provisioning -- it is advisory only. The ops-provisioner agent has a broader version of this check for non-community tools.
