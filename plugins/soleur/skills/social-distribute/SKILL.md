---
name: social-distribute
description: "This skill should be used when distributing a blog article across social platforms. It reads a blog post, generates platform-specific content variants for Discord, X/Twitter, IndieHackers, Reddit, and Hacker News, optionally posts to Discord via webhook after approval, and writes a persistent content file to distribution-content/ with YAML frontmatter for the automated publishing pipeline. Triggers on \"distribute blog\", \"social distribute\", \"share article\", \"post to social\", \"distribute content\"."
---

# Social Distribute

Generate platform-specific content variants from a blog article and write them to a persistent content file for the automated publishing pipeline. Discord can optionally be posted immediately via webhook after approval. The content file feeds into the directory-driven cron pipeline (`content-publisher.sh`) for scheduled publishing.

## Prerequisites

Before generating content, verify all prerequisites. If a hard prerequisite fails, display the error message and stop. Soft prerequisites display a warning and continue.

### 1. Brand Guide (hard)

Check if `knowledge-base/overview/brand-guide.md` exists.

**If missing:**
> No brand guide found. Run the brand architect agent first to establish brand identity:
> `Use the brand-architect agent to define our brand.`

Stop execution.

### 2. Blog Post Path (hard)

The skill expects a blog post path as an argument (e.g., `/soleur:social-distribute plugins/soleur/docs/blog/my-article.md`).

**If no path provided or file does not exist:**
> Provide a path to a blog post markdown file:
> `/soleur:social-distribute <path-to-blog-post.md>`

Stop execution.

### 3. Discord Webhook URL (soft)

Check if `DISCORD_BLOG_WEBHOOK_URL` or `DISCORD_WEBHOOK_URL` environment variable is set.

**If both missing:**
> Neither `DISCORD_BLOG_WEBHOOK_URL` nor `DISCORD_WEBHOOK_URL` is set. Discord posting will be skipped (manual output only).
> To configure: Server Settings > Integrations > Webhooks > Copy URL from the #blog channel > `export DISCORD_BLOG_WEBHOOK_URL="..."`

Continue execution -- Discord will be included in the content file's `channels` field for cron publishing instead of immediate webhook posting.

## Content Input

### Phase 1: Read Blog Post

1. Read the blog post markdown file at the provided path
2. Parse YAML frontmatter to extract: `title`, `description`, `date`, `tags`

### Phase 2: Gather Current Stats

Run these shell commands to get current component counts:

```bash
# Count agents (recursive .md files under agents/)
find plugins/soleur/agents -name '*.md' | wc -l

# Count skills (directories with SKILL.md)
find plugins/soleur/skills -maxdepth 2 -name 'SKILL.md' | wc -l

# Count commands
ls plugins/soleur/commands/*.md | wc -l

# Count departments (non-empty top-level dirs under agents/)
find plugins/soleur/agents -mindepth 1 -maxdepth 1 -type d | wc -l

# Get site URL
cat plugins/soleur/docs/_data/site.json
```

Extract: `agents` count, `skills` count, `commands` count, `departments` count, `site.url`.

### Phase 3: Build Article URL

Construct the article URL from `site.url` and the blog post path:
- Strip `plugins/soleur/docs/` prefix from the path
- Replace `.md` extension with `/`
- Prepend `site.url`

Example: `plugins/soleur/docs/blog/what-is-company-as-a-service.md` becomes `https://soleur.ai/blog/what-is-company-as-a-service/`

## Content Generation

### Phase 4: Read Brand Guide

Read the brand guide sections that inform content generation:

1. Read `## Voice` -- apply brand voice, tone, do's and don'ts
2. Read `## Channel Notes > ### Discord` -- apply Discord-specific guidelines
3. Read `## Channel Notes > ### X/Twitter` -- apply X/Twitter-specific guidelines

If a channel notes section is missing for a platform, generate content using only the `## Voice` section.

### Phase 5: Generate All Variants

Using the blog post content, stats values, article URL, and brand guide as context, generate all 5 variants. The LLM handles template variable substitution (replace `{{ stats.agents }}` with actual counts), markup stripping (ignore JSON-LD, HTML tags, FAQ accordions), and content adaptation per platform.

**Important:** Every variant must contain resolved numbers, not template syntax like `{{ stats.agents }}`. Use the stats gathered in Phase 2.

#### 5.1 Discord Announcement

- Maximum 2000 characters
- Include article URL
- Match brand voice from `## Voice` and `## Channel Notes > ### Discord`
- Plain text only (no rich embeds)
- Declarative, concrete, builder-to-builder tone

#### 5.2 X/Twitter Thread

- Hook tweet (standalone value, no "thread" announcement)
- Numbered body tweets (2/ 3/ 4/)
- Final tweet with article link and up to one hashtag
- Each tweet maximum 280 characters
- Match brand voice from `## Voice` and `## Channel Notes > ### X/Twitter`
- Links only in final tweet
- No emojis in hook tweet

#### 5.3 IndieHackers Building Update

- Markdown format
- Transparent metrics and numbers
- Building-in-public framing
- Include article URL
- Honest, first-person builder voice

#### 5.4 Reddit Post

- Subreddit-appropriate framing (suggest target subreddits: r/SaaS, r/startups, r/solopreneur, r/artificial)
- Non-promotional title and body
- Value-first: lead with the insight, not the product
- Include article URL naturally in context, not as a CTA
- Reddit detects and punishes self-promotion -- frame as sharing knowledge

#### 5.5 Hacker News Submission

- Title maximum 80 characters
- No marketing language, no ALL CAPS, no exclamation marks
- Factual, understated, curiosity-driven
- Format: `Title | URL`
- HN titles that work: questions, counterintuitive claims, concrete results

## Approval Flow

### Phase 6: Present All Variants

Display all 5 variants in a summary view with clear headers and character counts:

```
## Discord (1847/2000 chars)
[content]

## X/Twitter Thread (4 tweets)
[tweet 1] (267/280 chars)
[tweet 2] (243/280 chars)
...

## IndieHackers
[content]

## Reddit
Suggested subreddits: r/SaaS, r/startups
[title]
[body]

## Hacker News
[title] (72/80 chars)
[url]
```

### Phase 7: Discord Approval

**If `DISCORD_BLOG_WEBHOOK_URL` or `DISCORD_WEBHOOK_URL` is set:**

Use the **AskUserQuestion tool** with three options:

- **Accept** -- Post this content to Discord
- **Edit** -- Provide feedback to revise the Discord variant (regenerate with feedback, re-present)
- **Skip** -- Skip Discord posting, include Discord in content file's `channels` field for cron publishing

**If neither is set:**

Skip this phase. Discord will be included in the content file's `channels` field for cron publishing.

## Posting

### Phase 8: Post to Discord (conditional)

**This phase only runs if the user accepted Discord posting in Phase 7.** If the user skipped Discord or no webhook URL is set, skip to Phase 9.

On acceptance, post the Discord content via webhook.

First get the webhook URL with `printenv DISCORD_BLOG_WEBHOOK_URL || printenv DISCORD_WEBHOOK_URL`, then use the literal URL:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"ESCAPED_CONTENT\", \"username\": \"Sol\", \"avatar_url\": \"AVATAR_URL\", \"allowed_mentions\": {\"parse\": []}}" \
  "<webhook-url>"
```

Replace `<webhook-url>` with the actual URL from `printenv`.

Set `avatar_url` to the hosted logo URL (e.g., the GitHub-hosted `logo-mark-512.png`). Webhook messages freeze author identity at post time -- these fields ensure consistent branding.

**Content must be properly JSON-escaped** before inserting into the payload. Escape double quotes, backslashes, and newlines.

**Payload format:** Plain `content` field only. No rich embeds.

**On success (HTTP 2xx):**
> Posted to Discord successfully.

Track that Discord was posted successfully -- this affects the `channels` field in Phase 9.

**On failure (HTTP 4xx/5xx):**
> Failed to post to Discord (HTTP [status_code]).
>
> Draft content (copy-paste manually):
> ```
> [full draft content]
> ```

Display the draft so the user can post it manually. Do not retry automatically. Treat a failed post as "Discord not posted" for Phase 9's `channels` field.

## Content File Output

### Phase 9: Write Content File

After content generation and approval, write a persistent content file for the directory-driven publishing pipeline.

**Step 1: Derive slug and output path**

Derive the slug from the blog post filename: strip path, strip `.md`, keep kebab-case.

Example: `plugins/soleur/docs/blog/why-most-agentic-tools-plateau.md` → `why-most-agentic-tools-plateau`

Output path: `knowledge-base/marketing/distribution-content/<slug>.md`

**Step 2: Check for existing file**

If a file already exists at the output path, use the **AskUserQuestion tool**:

- **Overwrite** -- Replace the existing file with new content
- **Cancel** -- Abort file writing, print content to conversation instead

If cancelled, fall back to printing all variants to the conversation (legacy behavior) and skip to Phase 11.

**Step 3: Determine channels field**

- If Discord was posted successfully in Phase 8: set `channels: x` (Discord already done)
- If Discord was skipped, failed, or no webhook configured: set `channels: discord, x`

**Step 4: Write the content file**

Write the file with YAML frontmatter and a section per platform. Use the blog post's frontmatter `title` for the content file title. If the blog post has no frontmatter title, fall back to the first H1 heading or the filename.

```markdown
---
title: "<blog post title>"
type: pillar
publish_date: ""
channels: <channels from step 3>
status: draft
---

## Discord

<discord content>

---

## X/Twitter Thread

<tweet 1 with label>

<tweet 2 with label>

...

---

## IndieHackers

<ih content>

---

## Reddit

**Subreddit:** <suggested subreddits>
**Title:** <title>

<body>

---

## Hacker News

**Title:** <title>
**URL:** <article url>
```

### Phase 10: Confirmation & Next Steps

Output the file path and instructions:

```
Content file written: knowledge-base/marketing/distribution-content/<slug>.md

Status: draft

Next steps:
1. Review the content file
2. Set publish_date to the target date (YYYY-MM-DD format)
3. Change status from "draft" to "scheduled"
4. The daily cron will publish to Discord and X on the scheduled date
5. Reddit, IndieHackers, and Hacker News sections are for manual posting
```

## Distribution Summary

### Phase 11: Summary

Display a summary of the distribution:

```
Distribution summary:
- Content file: knowledge-base/marketing/distribution-content/<slug>.md
- Status: draft (review and schedule when ready)
- Discord: [Posted now via webhook / Will publish via cron when scheduled]
- X/Twitter: Will publish via cron when scheduled
- IndieHackers: Manual (content in file)
- Reddit: Manual (content in file)
- Hacker News: Manual (content in file)
```

## Important Guidelines

- All Discord posting requires explicit user approval before sending -- no auto-send
- Character limits are enforced during generation, not as a post-hoc check (2000 for Discord, 280 per tweet for X/Twitter, 80 for HN title)
- Discord uses the plain `content` field, not rich embeds
- JSON-escape all Discord content before inserting into the webhook payload
- When posting via webhook, always include `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields
- If the brand guide's channel notes section is missing for a platform, generate content using only the `## Voice` section (no error)
- If the user selects "Edit" for Discord, incorporate their feedback and regenerate -- do not present the same draft
- Template variables in blog source (`{{ stats.agents }}` etc.) are resolved by passing current stats as LLM context -- the LLM substitutes actual values during generation
- Markup artifacts (JSON-LD scripts, HTML details/summary tags, Nunjucks tags) in the blog source are ignored during generation -- they are meaningless in social posts
- Missing `DISCORD_BLOG_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL` does not block execution -- Discord is included in the content file's `channels` field for cron publishing
- The content file is always written (unless the user cancels on overwrite). Discord webhook posting is optional and independent of the file write
- The `channels` field in the content file reflects what the cron still needs to publish -- if Discord was posted via webhook, it is excluded from `channels`
- Content files use the blog post slug directly as filename (no numeric prefix). The content-publisher scans all `*.md` files in the directory
