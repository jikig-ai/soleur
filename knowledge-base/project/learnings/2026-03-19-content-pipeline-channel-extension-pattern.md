# Learning: Content Pipeline Channel Extension Pattern

## Problem

Adding new social distribution channels (Bluesky, LinkedIn Company Page) to the automated content publishing pipeline required understanding the 3-layer architecture and ensuring all layers were updated consistently.

## Solution

The content pipeline has 3 layers that must be updated together when adding a channel:

1. **Content generation** (`social-distribute/SKILL.md`) — Add platform-specific content generation template with character limits and tone guidelines
2. **Publisher script** (`scripts/content-publisher.sh`) — Add channel mapping, posting function (with graceful skip + fallback issue), and dispatch case
3. **CI workflow** (`scheduled-content-publisher.yml`) — Pass platform credentials as env vars, add safety guards (e.g., `BSKY_ALLOW_POST: "true"`)

Plus the content generator workflow must update the hardcoded `channels:` list.

Each posting function follows the same pattern:

- Check credentials → skip with warning if missing (return 0)
- Extract section content → skip if empty
- Call API wrapper script → create fallback issue on failure (return 1)
- Print success message

LinkedIn organization posting reuses the personal posting script (`linkedin-community.sh`) with an `--author` flag override — no separate script needed.

## Key Insight

When API wrapper scripts already exist (`bsky-community.sh`, `linkedin-community.sh`), adding a new channel to the pipeline requires zero new files. The existing graceful-skip + fallback-issue pattern makes every new channel safe to deploy even without credentials configured — the pipeline degrades gracefully rather than failing.

## Tags

category: integration-issues
module: content-publisher
