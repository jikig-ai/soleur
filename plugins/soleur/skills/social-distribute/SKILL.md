---
name: social-distribute
description: "This skill should be used when distributing a blog article across social platforms (Discord, X/Twitter, IndieHackers, Reddit, Hacker News, LinkedIn). Writes a persistent content file for automated publishing."
---

# Social Distribute

Generate platform-specific content variants from a blog article and write them to a persistent content file for the automated publishing pipeline. Discord can optionally be posted immediately via webhook after approval. The content file feeds into the directory-driven cron pipeline (`content-publisher.sh`) for scheduled publishing.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true` and strip `--headless` from `$ARGUMENTS`. The remainder is the blog post path.

**Argument format:** `<blog-post-path> [--headless]`

**Headless defaults for interactive gates:**

- Phase 7 (Discord Approval): auto-selects **Skip** (never auto-post to external platforms without human approval). `channels` is always `discord, x, bluesky, linkedin-company`.
- Phase 9 Step 2 (Overwrite Check): auto-selects **Overwrite** (content is regenerated from the same blog post, so overwriting is idempotent).

## Prerequisites

Before generating content, verify all prerequisites. If a hard prerequisite fails, display the error message and stop. Soft prerequisites display a warning and continue.

### 1. Brand Guide (hard)

Check if `knowledge-base/marketing/brand-guide.md` exists.

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
- Strip any leading `YYYY-MM-DD-` date prefix from the filename portion of the path (regex: `/\d{4}-\d{2}-\d{2}-(.*)/`). Eleventy's `page.fileSlug` strips this prefix, so URLs must match. If no date prefix exists, leave the path unchanged.
- Prepend `site.url`

Example: `plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md` becomes `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`

**UTM Tracking:** Derive the campaign slug from the article URL path — strip `/blog/` prefix and trailing `/`. Example: `/blog/caas-pillar/` → `caas-pillar`. If the slug contains characters other than `a-z`, `0-9`, hyphens, or underscores, replace them with hyphens.

Construct platform-specific tracked URLs using this mapping:

| Platform | Tracked URL |
|----------|------------|
| Discord | `<base-url>?utm_source=discord&utm_medium=community&utm_campaign=<slug>` |
| X/Twitter | `<base-url>?utm_source=x&utm_medium=social&utm_campaign=<slug>` |
| IndieHackers | `<base-url>?utm_source=indiehackers&utm_medium=community&utm_campaign=<slug>` |
| Reddit | `<base-url>?utm_source=reddit` |
| Hacker News | `<base-url>?utm_source=hackernews&utm_medium=community&utm_campaign=<slug>` |
| LinkedIn Personal | `<base-url>?utm_source=linkedin-personal&utm_medium=social&utm_campaign=<slug>` |
| LinkedIn Company Page | `<base-url>?utm_source=linkedin-company&utm_medium=social&utm_campaign=<slug>` |
| Bluesky | `<base-url>?utm_source=bluesky&utm_medium=social&utm_campaign=<slug>` |

Reddit gets minimal UTM parameters (`utm_source` only) to reduce spam filter risk — long marketing-looking URLs can trigger irreversible domain reputation damage on Reddit.

Use each platform's tracked URL in the corresponding Phase 5 variant section instead of the bare base URL.

## Content Generation

### Phase 4: Read Brand Guide

Read the brand guide sections that inform content generation:

1. Read `## Voice` -- apply brand voice, tone, do's and don'ts
2. Read `## Channel Notes > ### Discord` -- apply Discord-specific guidelines
3. Read `## Channel Notes > ### X/Twitter` -- apply X/Twitter-specific guidelines
4. Read `## Channel Notes > ### LinkedIn Personal` -- apply LinkedIn personal profile guidelines
5. Read `## Channel Notes > ### LinkedIn Company Page` -- apply LinkedIn company page guidelines

If a channel notes section is missing for a platform, generate content using only the `## Voice` section.

### Phase 5: Generate All Variants

Using the blog post content, stats values, article URL, and brand guide as context, generate all platform-specific variants. The LLM handles template variable substitution (replace `{{ stats.agents }}` with actual counts), markup stripping (ignore JSON-LD, HTML tags, FAQ accordions), and content adaptation per platform.

**Important:** Every variant must contain resolved numbers, not template syntax like `{{ stats.agents }}`. Use the stats gathered in Phase 2.

#### 5.1 Discord Announcement

- Maximum 2000 characters (UTM-tagged URLs are ~60-80 chars longer than bare URLs — account for this in the character budget)
- Include Discord tracked URL
- Match brand voice from `## Voice` and `## Channel Notes > ### Discord`
- Plain text only (no rich embeds)
- Declarative, concrete, builder-to-builder tone

#### 5.2 X/Twitter Thread

- Hook tweet (standalone value, no "thread" announcement)
- Numbered body tweets (2/ 3/ 4/)
- Final tweet with X/Twitter tracked URL and up to one hashtag
- Each tweet maximum 280 characters
- Match brand voice from `## Voice` and `## Channel Notes > ### X/Twitter`
- Links only in final tweet
- No emojis in hook tweet

#### 5.3 IndieHackers Building Update

- Markdown format
- Transparent metrics and numbers
- Building-in-public framing
- Include IndieHackers tracked URL
- Honest, first-person builder voice

#### 5.4 Reddit Post

- Subreddit-appropriate framing (suggest target subreddits: r/SaaS, r/startups, r/solopreneur, r/artificial)
- Non-promotional title and body
- Value-first: lead with the insight, not the product
- Include Reddit tracked URL naturally in context, not as a CTA (minimal UTM: `?utm_source=reddit` only)
- Reddit detects and punishes self-promotion -- frame as sharing knowledge

#### 5.5 Hacker News Submission

- Title maximum 80 characters
- No marketing language, no ALL CAPS, no exclamation marks
- Factual, understated, curiosity-driven
- Format: `Title | Hacker News tracked URL`
- HN titles that work: questions, counterintuitive claims, concrete results

#### 5.6 LinkedIn Personal

- Thought-leadership framing: case studies, reflections, lessons learned
- First-person, authentic founder voice ("I built..." not "We launched...")
- Aim for ~1,300 characters (optimal organic visibility), max 3,000
- Professional but not corporate -- substantive, measured, and direct
- Match brand voice from `## Voice` and `## Channel Notes > ### LinkedIn Personal`
- Hook-first: opening line must deliver a complete, compelling idea that works in the feed preview
- Include LinkedIn Personal tracked URL naturally in context, not as a standalone CTA
- One or two relevant hashtags maximum (#solofounder, #buildinpublic, #AIagents)
- No promotional framing -- "Here's what I learned building X" outperforms "Check out our new feature Y"
- Tuesday-Thursday mornings perform best (note in content, not enforced)
- Section heading: `## LinkedIn Personal`

#### 5.7 LinkedIn Company Page

- Official announcement tone, third-person company voice ("Soleur now supports...")
- ~1,300 chars optimal, max 3,000
- Professional framing: product updates, feature announcements, milestones
- Match brand voice from `## Voice` and `## Channel Notes > ### LinkedIn Company Page`
- Include LinkedIn Company Page tracked URL naturally in context
- Minimal hashtags (1-2 max)
- Section heading: `## LinkedIn Company Page`

#### 5.8 Bluesky Post

- Maximum 300 characters (grapheme count; Bluesky uses codepoint counting as approximation)
- Standalone value post (no threads -- single posts perform better for distribution)
- Match brand voice from `## Voice`
- Include Bluesky tracked URL
- No hashtags (Bluesky has no hashtag discovery)
- Conversational, direct tone suited to the developer/indie community
- Note: URLs will render as plain text (facet support for clickable links is a future enhancement)
- Section heading: `## Bluesky`

## Approval Flow

### Phase 6: Present All Variants

Display all variants in a summary view with clear headers and character counts:

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

## LinkedIn Personal (1247/1300 optimal, 1247/3000 max)
[content]

## LinkedIn Company Page (1247/1300 optimal, 1247/3000 max)
[content]

## Bluesky (287/300 chars)
[content]
```

### Phase 7: Discord Approval

**If `HEADLESS_MODE=true`:** auto-select **Skip**. Discord is deferred to the content file for cron publishing.

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
>
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

Check for an existing content file matching this slug. The check must account for both slug-only filenames and legacy numeric-prefixed filenames:

```bash
ls knowledge-base/marketing/distribution-content/*<slug>.md 2>/dev/null
```

If a match is found (either `<slug>.md` or `NN-<slug>.md`), use the matched filename as the output path (preserving the existing naming convention).

**If `HEADLESS_MODE=true`:** auto-select **Overwrite** and continue.

**If interactive and a file exists**, use the **AskUserQuestion tool**:

- **Overwrite** -- Replace the existing file with new content
- **Cancel** -- Abort file writing and stop. The user can rename or delete the existing file, then re-run.

**Step 3: Determine channels field**

- If Discord was posted successfully in Phase 8: set `channels: x, bluesky, linkedin-company` (Discord already done)
- If Discord was skipped, failed, or no webhook configured: set `channels: discord, x, bluesky, linkedin-company`

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

**Title:** <ih title>

**Body:**

<ih body content>

---

## Reddit

**Subreddit:** <suggested subreddits>
**Title:** <title>

**Body:**

<body>

---

## Hacker News

**Title:** <title>
**URL:** <Hacker News tracked url>

---

## LinkedIn Personal

<linkedin personal content>

---

## LinkedIn Company Page

<linkedin company page content>

---

## Bluesky

<bluesky content>
```

### Phase 10: Summary & Next Steps

Output the file path, channel status, and instructions:

```
Content file written: knowledge-base/marketing/distribution-content/<slug>.md

Distribution summary:
- Discord: [Posted now via webhook / Will publish via cron when scheduled]
- X/Twitter: Will publish via cron when scheduled
- Bluesky: Will publish via cron when scheduled
- LinkedIn Company Page: Will publish via cron when scheduled
- IndieHackers: Manual (content in file)
- Reddit: Manual (content in file)
- Hacker News: Manual (content in file)
- LinkedIn Personal: Manual (content in file)

Next steps:
1. Review the content file
2. Set publish_date to the target date (YYYY-MM-DD format)
3. Change status from "draft" to "scheduled"
4. The daily cron will publish to Discord, X, Bluesky, and LinkedIn Company Page on the scheduled date
5. Reddit, IndieHackers, Hacker News, and LinkedIn Personal sections are for manual posting
```

## Important Guidelines

- All Discord posting requires explicit user approval before sending -- no auto-send
- Character limits are enforced during generation, not as a post-hoc check (2000 for Discord, 280 per tweet for X/Twitter, 80 for HN title, 300 for Bluesky, 1300 optimal / 3000 max for LinkedIn Personal and LinkedIn Company Page)
- Discord uses the plain `content` field, not rich embeds
- JSON-escape all Discord content before inserting into the webhook payload
- When posting via webhook, always include `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields
- If the brand guide's channel notes section is missing for a platform, generate content using only the `## Voice` section (no error)
- If the user selects "Edit" for Discord, incorporate their feedback and regenerate -- do not present the same draft
- Template variables in blog source (`{{ stats.agents }}` etc.) are resolved by passing current stats as LLM context -- the LLM substitutes actual values during generation
- Markup artifacts (JSON-LD scripts, HTML details/summary tags, Nunjucks tags) in the blog source are ignored during generation -- they are meaningless in social posts
- Missing `DISCORD_BLOG_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL` does not block execution -- Discord is included in the content file's `channels` field for cron publishing
- New content files use the blog post slug as filename. If an existing file with a numeric prefix matches the slug (e.g., `06-<slug>.md`), the existing filename is preserved
