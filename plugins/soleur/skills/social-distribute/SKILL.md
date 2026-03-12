---
name: social-distribute
description: "This skill should be used when distributing a blog article across social platforms. It reads a blog post, generates platform-specific content variants for Discord, X/Twitter, IndieHackers, Reddit, and Hacker News, posts to Discord via webhook after approval, and outputs formatted text for all other platforms. Triggers on \"distribute blog\", \"social distribute\", \"share article\", \"post to social\", \"distribute content\"."
---

# Social Distribute

Generate platform-specific content variants from a blog article and distribute across social channels. Discord is posted via webhook after approval. All other platforms output formatted text for manual posting.

## Distribution Pipeline Gate

Before generating content or posting manually, check if a content file already exists for this blog post in `knowledge-base/specs/feat-product-strategy/distribution-content/`. If `content-publisher.sh` and the `scheduled-content-publisher.yml` workflow can handle this content, route through the automated pipeline instead of posting ad-hoc. Ad-hoc posting bypasses thread recovery, fallback issue creation, and deduplication.

**Check:** `ls knowledge-base/specs/feat-product-strategy/distribution-content/*<slug>* 2>/dev/null` where `<slug>` is derived from the blog post filename.

- **If content file exists:** Inform the user and suggest triggering the workflow: `gh workflow run "Scheduled: Content Publisher" -f case_study=<number>`. Do not post manually.
- **If no content file exists:** Continue with ad-hoc generation, but recommend creating a content file and extending `content-publisher.sh` for future use. Output a warning: "No distribution content file found. Consider creating one in `distribution-content/` for automated distribution."

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

Continue execution -- Discord becomes manual output like the other platforms.

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
- **Skip** -- Skip Discord posting, continue to manual output

**If neither is set:**

Skip this phase. Discord content is included in the manual output.

## Posting

### Phase 8: Post to Discord

On acceptance, post the content via webhook.

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

**On failure (HTTP 4xx/5xx):**
> Failed to post to Discord (HTTP [status_code]).
>
> Draft content (copy-paste manually):
> ```
> [full draft content]
> ```

Display the draft so the user can post it manually. Do not retry automatically.

## Manual Platform Output

### Phase 9: Output Remaining Platforms

Print all non-Discord variants to the terminal with clear headers for easy copy-paste:

```
---
## X/Twitter Thread
Copy and paste each tweet in order:

1/ [hook tweet]

2/ [body tweet]

3/ [body tweet]

4/ [final tweet with link]

---
## IndieHackers
[full post content]

---
## Reddit
Suggested subreddits: r/SaaS, r/startups, r/solopreneur, r/artificial
Title: [title]

[body]

---
## Hacker News
Title: [title]
URL: [article URL]
```

If Discord was skipped or failed, include the Discord content in this output too.

## Distribution Summary

### Phase 10: Summary

Display a summary of what was distributed:

```
Distribution complete:
- Discord: [Posted / Skipped / Failed (manual output provided)]
- X/Twitter: Manual output
- IndieHackers: Manual output
- Reddit: Manual output
- Hacker News: Manual output
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
- Missing `DISCORD_BLOG_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL` does not block execution -- Discord becomes manual output alongside the other platforms
