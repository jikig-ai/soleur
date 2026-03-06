---
status: pending
branch: feat-social-distribute
pr: 457
issue: 458
---

# Tasks: Social Distribution Workflow

**Convention:** Run `skill: soleur:compound` before every commit.

## Phase 0: Prep (Bug Fixes)

- [x] 0.1 Fix discord-content SKILL.md: add `allowed_mentions: {parse: []}` to webhook curl payload
- [x] 0.2 Fix CaaS blog article: wrong Lovable citation link (line 27 links to Cursor CNBC article)
- [x] 0.3 Fix CaaS blog article: remove duplicate WhatsApp paragraph (lines 122 vs 126)
- [x] 0.4 Audit all remaining citations and statistics in CaaS article for accuracy
- [x] 0.5 Commit fixes

## Phase 1: Brand Guide Extension

- [x] 1.1 Read current brand guide channel notes section (`knowledge-base/overview/brand-guide.md`)
- [x] 1.2 Write `### X/Twitter` channel notes (tone, thread format, 280-char limit, hook-first, numbering, link placement, hashtag policy)
- [ ] 1.3 Commit brand guide update

## Phase 2: Social Distribute Skill (Core)

### 2.1 Skill Setup
- [ ] 2.1.1 Create `plugins/soleur/skills/social-distribute/` directory
- [ ] 2.1.2 Write SKILL.md with frontmatter (name: social-distribute, third-person description, trigger keywords)

### 2.2 Prerequisites Phase (in SKILL.md)
- [ ] 2.2.1 Check brand guide exists at `knowledge-base/overview/brand-guide.md`
- [ ] 2.2.2 Check `DISCORD_WEBHOOK_URL` env var (warn if missing, don't block -- Discord becomes manual too)
- [ ] 2.2.3 Validate blog post path argument exists and is a `.md` file

### 2.3 Content Input
- [ ] 2.3.1 Read blog post markdown file
- [ ] 2.3.2 Parse YAML frontmatter (extract title, description, date, tags)
- [ ] 2.3.3 Get current stats via shell: count agents, skills, commands, departments; read site.url from site.json
- [ ] 2.3.4 Pass raw article content + stats values as context to LLM generation (LLM handles template vars, strips markup)

### 2.4 Content Generation
- [ ] 2.4.1 Read brand guide `## Voice` section and `## Channel Notes` for Discord and X/Twitter
- [ ] 2.4.2 Generate Discord announcement post (<=2000 chars, include article URL)
- [ ] 2.4.3 Generate X/Twitter thread (hook tweet + numbered thread + final tweet with article link, <=280 chars each)
- [ ] 2.4.4 Generate IndieHackers building update (markdown, transparent metrics)
- [ ] 2.4.5 Generate Reddit post (subreddit-appropriate, non-promotional framing)
- [ ] 2.4.6 Generate HN submission title (<=80 chars, no marketing language) + URL

### 2.5 Approval Flow
- [ ] 2.5.1 Display all 5 variants in a summary view
- [ ] 2.5.2 For Discord (if webhook configured): AskUserQuestion Accept/Edit/Skip
- [ ] 2.5.3 Handle "Edit" by regenerating Discord variant with user feedback
- [ ] 2.5.4 For all other platforms: output formatted text to terminal

### 2.6 Posting (Discord)
- [ ] 2.6.1 Post via curl to `DISCORD_WEBHOOK_URL` with `username: "Sol"`, `avatar_url`, `allowed_mentions: {parse: []}`
- [ ] 2.6.2 Handle HTTP errors: show error, output draft text as fallback
- [ ] 2.6.3 Report success

### 2.7 Manual Platform Output
- [ ] 2.7.1 Print X/Twitter thread, IndieHackers, Reddit, HN content to terminal with clear headers
- [ ] 2.7.2 Include article URL in each output

### 2.8 Distribution Summary
- [ ] 2.8.1 Display summary: which platform was posted, which are manual output

## Phase 3: Registration & Counts

- [ ] 3.1 Add `social-distribute` to `SKILL_CATEGORIES` in `plugins/soleur/docs/_data/skills.js`
- [ ] 3.2 Grep old skill count across repo, update all references (plugin.json description, plugin README, root README, brand-guide.md)
- [ ] 3.3 Commit registration updates

## Phase 4: Verification

- [ ] 4.1 Merge origin/main into feature branch
- [ ] 4.2 Run `/soleur:social-distribute` against the CaaS blog post
- [ ] 4.3 Verify Discord post appears correctly in the channel
- [ ] 4.4 Verify all 5 platform variants are generated with correct formatting
- [ ] 4.5 Verify template variables are resolved (no `{{ stats.agents }}` in output)
