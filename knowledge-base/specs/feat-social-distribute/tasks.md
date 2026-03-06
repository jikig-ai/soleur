---
status: pending
branch: feat-social-distribute
pr: 457
issue: 458
---

# Tasks: Social Distribution Workflow

## Phase 0: Blog Accuracy Audit

- [ ] 0.1 Verify all external links in CaaS article (check HTTP status codes)
- [ ] 0.2 Fix wrong Lovable citation (line 27 links to Cursor CNBC article, not Lovable)
- [ ] 0.3 Remove duplicate WhatsApp paragraph (lines 122-126 repeat lines 121-122)
- [ ] 0.4 Verify "9,000+ Claude Code plugins" claim from nxcode.io source
- [ ] 0.5 Verify Dario Amodei quote (70-80% probability, Inc.com source)
- [ ] 0.6 Verify Sam Altman quote (felloai.com source)
- [ ] 0.7 Verify Lovable "$200M ARR at $6.6B valuation" stat and find correct source link
- [ ] 0.8 Verify Cursor "$1B ARR at $29.3B valuation" stat
- [ ] 0.9 Verify Mike Krieger quote attribution
- [ ] 0.10 Commit blog fixes

## Phase 1: Brand Guide Extension

- [ ] 1.1 Read current brand guide channel notes section (`knowledge-base/overview/brand-guide.md`)
- [ ] 1.2 Write `### X/Twitter` channel notes (tone, thread format, 280-char limit, hook-first, numbering, link placement, hashtag policy)
- [ ] 1.3 Write `### IndieHackers` channel notes (building update format, transparent metrics, markdown support, community norms)
- [ ] 1.4 Write `### Reddit` channel notes (subreddit targets, self-post vs link-post, anti-self-promotion norms, tone shift)
- [ ] 1.5 Write `### Hacker News` channel notes (title conventions, Show HN vs direct, no marketing language, technical credibility)
- [ ] 1.6 Update brand-guide.md component counts if referencing skill count
- [ ] 1.7 Commit brand guide updates

## Phase 2: Post-Publish Distribution Checklist

- [ ] 2.1 Create `knowledge-base/marketing/post-publish-distribution.md` with per-channel checklist
- [ ] 2.2 Include: platform, format, character limits, manual vs automated, account URL, env var requirement
- [ ] 2.3 Commit checklist

## Phase 3: Social Distribute Skill (Core)

### 3.1 Skill Setup
- [ ] 3.1.1 Create `plugins/soleur/skills/social-distribute/` directory
- [ ] 3.1.2 Write SKILL.md frontmatter (name: social-distribute, third-person description, trigger keywords)

### 3.2 Prerequisites Phase
- [ ] 3.2.1 Check brand guide exists at `knowledge-base/overview/brand-guide.md`
- [ ] 3.2.2 Check `DISCORD_WEBHOOK_URL` env var (warn if missing, don't block)
- [ ] 3.2.3 Check X/Twitter env vars: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` (warn if missing, degrade to text)
- [ ] 3.2.4 Validate blog post path argument exists and is a `.md` file

### 3.3 Content Preprocessing
- [ ] 3.3.1 Read blog post markdown file
- [ ] 3.3.2 Parse YAML frontmatter (extract title, description, date, tags)
- [ ] 3.3.3 Resolve template variables: read `docs/_data/stats.js` counting logic and `docs/_data/site.json` for values
- [ ] 3.3.4 Strip `<script>` blocks (JSON-LD)
- [ ] 3.3.5 Strip `<details>` blocks (FAQ accordions)
- [ ] 3.3.6 Strip YAML frontmatter from content body
- [ ] 3.3.7 Produce clean article text for content generation

### 3.4 Content Generation
- [ ] 3.4.1 Read brand guide `## Voice` section
- [ ] 3.4.2 Read brand guide `## Channel Notes` for each target platform
- [ ] 3.4.3 Read content repurposing table from `knowledge-base/overview/content-strategy.md` (optional -- article may not be in table)
- [ ] 3.4.4 Generate Discord announcement post (<=2000 chars, include article URL)
- [ ] 3.4.5 Generate X/Twitter thread (hook tweet + numbered thread + final tweet with article link)
- [ ] 3.4.6 Generate IndieHackers building update (markdown, transparent metrics)
- [ ] 3.4.7 Generate Reddit post (subreddit-appropriate, non-promotional framing)
- [ ] 3.4.8 Generate HN submission title (<=80 chars, no marketing language)
- [ ] 3.4.9 Inline brand voice check on each variant against Do's/Don'ts

### 3.5 Approval Flow
- [ ] 3.5.1 Display all 5 variants in a summary view
- [ ] 3.5.2 For Discord: AskUserQuestion Accept/Edit/Skip
- [ ] 3.5.3 For X/Twitter: AskUserQuestion Accept/Edit/Skip
- [ ] 3.5.4 For manual platforms: output formatted text (no approval needed -- user decides whether to post)
- [ ] 3.5.5 Handle "Edit" by regenerating single platform variant with user feedback
- [ ] 3.5.6 Handle "Skip" by moving to next platform

### 3.6 Posting (Discord)
- [ ] 3.6.1 Post via curl to `DISCORD_WEBHOOK_URL` with `username: "Sol"`, `avatar_url`, `allowed_mentions: {parse: []}`
- [ ] 3.6.2 Handle HTTP errors: show error, output draft text as fallback
- [ ] 3.6.3 Report success with message link if available

### 3.7 Posting (X/Twitter)
- [ ] 3.7.1 Construct OAuth 1.0a authorization header
- [ ] 3.7.2 Post first tweet via `POST https://api.twitter.com/2/tweets`
- [ ] 3.7.3 Post subsequent tweets with `reply.in_reply_to_tweet_id`
- [ ] 3.7.4 On mid-thread failure: report posted tweets with URLs, output remaining as text
- [ ] 3.7.5 Handle auth errors (401/403): output text, show error
- [ ] 3.7.6 Handle rate limits (429): output text, show retry-after

### 3.8 Manual Platform Output
- [ ] 3.8.1 Print IndieHackers, Reddit, HN content to terminal with clear headers
- [ ] 3.8.2 Include article URL in each output
- [ ] 3.8.3 For HN: output both title and URL (ready to paste into submit form)

### 3.9 Headless Mode
- [ ] 3.9.1 Check `$ARGUMENTS` for `--headless` flag
- [ ] 3.9.2 In headless: skip AskUserQuestion prompts, auto-approve all platforms
- [ ] 3.9.3 Safety constraints still apply in headless (env var checks, error handling)

### 3.10 Distribution Summary
- [ ] 3.10.1 Display summary: which platforms posted, skipped, or output as text
- [ ] 3.10.2 Include URLs for posted content where available

## Phase 4: Fix discord-content `allowed_mentions` Bug

- [ ] 4.1 Read current discord-content SKILL.md webhook payload
- [ ] 4.2 Add `allowed_mentions: {parse: []}` to the curl payload
- [ ] 4.3 Commit fix

## Phase 5: Registration & Counts

- [ ] 5.1 Add `social-distribute` to `SKILL_CATEGORIES` in `plugins/soleur/docs/_data/skills.js`
- [ ] 5.2 Update skill count in `plugins/soleur/plugin.json` description (NOT version)
- [ ] 5.3 Update skill count in `plugins/soleur/README.md` (table + count)
- [ ] 5.4 Update skill count in root `README.md`
- [ ] 5.5 Grep old skill count across repo to catch any other references
- [ ] 5.6 Update `knowledge-base/overview/brand-guide.md` component counts if present
- [ ] 5.7 Commit registration updates

## Phase 6: Final Verification

- [ ] 6.1 Run `/soleur:social-distribute` against the CaaS blog post (dry run without X keys)
- [ ] 6.2 Verify Discord post appears correctly in the channel
- [ ] 6.3 Verify X/Twitter degrades gracefully to text output
- [ ] 6.4 Verify all 5 platform variants are generated with correct formatting
- [ ] 6.5 Verify template variables are resolved (no `{{ stats.agents }}` in output)
- [ ] 6.6 Verify `--headless` mode works
