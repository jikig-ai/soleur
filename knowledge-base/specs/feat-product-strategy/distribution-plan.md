# Case Study Distribution Plan

**Goal:** 5+ expressions of interest from solo technical founders for the product validation plan (#430).
**Signal types:** Discord message, GitHub star from non-creator, social reply asking to try it, DM requesting access.
**Campaign duration:** 3 weeks (2026-03-12 to 2026-04-01)
**Cadence:** 2 posts per week (Wednesday + Friday), staggered across platforms

## Publishing Calendar

| # | Date (Wed/Fri) | Case Study | Slug | Rationale |
|---|---------------|------------|------|-----------|
| 1 | Wed 2026-03-12 | Legal Document Generation | `case-study-legal-document-generation` | Lead with highest cost comparison (EUR 9k-25k saved). Concrete, measurable, universally needed by founders. |
| 2 | Fri 2026-03-14 | Operations Management | `case-study-operations-management` | Relatable pain -- every founder tracks expenses in spreadsheets. Low barrier to "I need this." |
| 3 | Wed 2026-03-19 | Competitive Intelligence | `case-study-competitive-intelligence` | Highest complexity demo. 17 competitors + battlecards in one session lands hard with technical founders. |
| 4 | Fri 2026-03-21 | Brand Guide Creation | `case-study-brand-guide-creation` | Shows breadth beyond engineering. Marketing capability surprises technical founders who assume "AI = code." |
| 5 | Wed 2026-03-26 | Business Validation | `case-study-business-validation` | Anchor piece. The PIVOT verdict is the most compelling meta-story -- AI telling the founder to change direction. Save for last so the audience has context from the prior 4 studies. |

### Sequencing Rationale

1. **Legal first** -- universally dreaded task, highest dollar comparison, most tangible output (9 documents, 17,761 words). This is the "wait, what?" hook.
2. **Operations second** -- immediately relatable. Every solo founder has a messy expense spreadsheet and forgotten DNS settings. Low-stakes, high-recognition.
3. **Competitive intelligence third** -- demonstrates scale. 17 competitors tracked with battlecards in one session. This is where "full AI organization" becomes concrete.
4. **Brand guide fourth** -- the curveball. Technical founders don't expect AI to produce brand strategy. This broadens the mental model from "code assistant" to "company."
5. **Business validation last** -- the meta-story. AI ran a validation workshop, triggered a kill criterion, and told the founder to pivot. This is the story people share. It needs the prior context to land fully.

## Channel Strategy

### Discord (Soleur Server)

- **Format:** 2000-char announcement post in #announcements or #general
- **Tone:** Builder-to-builder, direct, bold. Emojis sparingly (arrows, checkmarks).
- **Automation:** Fully automated via `discord-content` skill webhook after approval.
- **Timing:** Post at 14:00 UTC (morning US West Coast, afternoon EU).
- **CTA:** Link to blog post + "what department would you build first?"

### X/Twitter (@soleur_ai)

- **Format:** Thread (hook + 2-3 body tweets + final tweet with link). Each tweet under 280 chars.
- **Tone:** Full brand voice. Declarative, concrete, numbers-first. No hedging.
- **Rules:** Hook-first (standalone value), numbered body tweets (2/ 3/), link only in final tweet, no hashtags in body, max one hashtag in final tweet. No emojis in hook.
- **Automation:** Semi-automated via `x-community.sh post-tweet` with `--reply-to` for threads.
- **Timing:** Post at 15:00 UTC (morning US, afternoon EU -- peak engagement window).
- **Engagement:** Monitor mentions via `community` skill digest. Reply to substantive questions within 24h. Escalate to Discord for extended conversations.

### IndieHackers

- **Format:** 500-800 word building-in-public update. Founder narrative, cost comparisons front-and-center.
- **Tone:** Candid, first-person, lean into "I built this for myself and here's what happened."
- **Automation:** Manual. Copy from pre-generated content file.
- **Timing:** Post Thursday mornings (day after X thread, gives IH audience fresh content on their peak day).
- **CTA:** "Has anyone else tried [domain] with AI? What worked?"

### Reddit (r/solopreneur, r/Entrepreneur)

- **Format:** Value-first text post. No self-promotion in title. Frame as experience/lesson, not product announcement.
- **Tone:** Helpful, specific, non-promotional. Lead with the problem and numbers, mention Soleur only in context.
- **Automation:** Manual. Copy from pre-generated content file.
- **Timing:** Post Friday afternoons UTC (US morning, weekend reading mode).
- **Subreddits:** r/solopreneur (primary), r/Entrepreneur (secondary). One post per study, alternate subreddits.
- **CTA:** None explicit. Let comments drive. Reply to questions with specifics.

### Hacker News

- **Format:** Title + URL submission only. No "Show HN" unless it's a direct demo.
- **Tone:** N/A -- title must be factual and non-clickbait. HN penalizes marketing language.
- **Automation:** Manual submission.
- **Timing:** Post Tuesday/Wednesday 14:00-16:00 UTC (HN peak).
- **Strategy:** Submit Legal and Business Validation studies only -- these have the strongest HN appeal (concrete numbers, meta-narrative). Don't burn goodwill by submitting all 5.

## Platform-by-Study Matrix

| Case Study | Discord | X/Twitter | IndieHackers | Reddit | HN |
|-----------|---------|-----------|-------------|--------|-----|
| 1. Legal | Wed 3/12 | Wed 3/12 | Thu 3/13 | Fri 3/14 (r/solopreneur) | Wed 3/12 |
| 2. Operations | Fri 3/14 | Fri 3/14 | -- | -- | -- |
| 3. Competitive Intel | Wed 3/19 | Wed 3/19 | Thu 3/20 | Fri 3/21 (r/Entrepreneur) | -- |
| 4. Brand Guide | Fri 3/21 | Fri 3/21 | -- | -- | -- |
| 5. Business Validation | Wed 3/26 | Wed 3/26 | Thu 3/27 | Fri 3/28 (r/solopreneur) | Wed 3/26 |

**Rationale for selective posting:** IndieHackers, Reddit, and HN audiences overlap. Posting all 5 on each looks spammy. Legal, Competitive Intel, and Business Validation have the strongest standalone value for those platforms. Operations and Brand Guide are best suited for Discord + X where we own the audience relationship.

## Engagement Protocol

### Reply Triage

| Signal | Response Time | Action |
|--------|--------------|--------|
| Question about how it works | < 24h | Direct answer with link to relevant blog post |
| "How do I try this?" / access request | < 4h | DM with onboarding link, log in inbound tracker |
| Technical critique | < 24h | Acknowledge, address specifics, no defensiveness |
| Feature request | < 48h | "Noted. Filed as [issue link]." |
| Trolling / bad faith | Never | Skip per brand guide engagement guardrails |

### Escalation Path

1. **Reply on platform** -- for quick answers and acknowledgments
2. **Invite to Discord** -- for extended conversations, follow-up questions, or anyone showing warm/hot interest
3. **DM** -- only for access requests or when the person clearly wants private communication
4. **GitHub issue** -- for concrete feature requests or bug reports from interested users

### Community Skill Integration

Run `community` skill digest weekly (Fridays) to:
- Fetch X mention activity
- Assess engagement health
- Identify top-performing content for iteration

## Tracking and Metrics

### Weekly Metrics (every Friday)

| Metric | Source | Target |
|--------|--------|--------|
| X thread impressions | `x-community.sh metrics` | 500+ per thread |
| X thread engagement rate | `x-community.sh metrics` | > 2% |
| Discord post reactions | Manual count | 5+ per post |
| IndieHackers upvotes | Manual check | 10+ per post |
| Reddit upvotes | Manual check | 10+ per post |
| HN points | Manual check | 5+ |
| Inbound interest signals | inbound-tracker.md | 5+ total by end of campaign |
| Blog post page views | Plausible Analytics | 50+ per study |

### Success Criteria

- **Primary:** 5+ expressions of interest logged in inbound-tracker.md by 2026-04-01
- **Secondary:** 1+ GitHub star from non-creator account
- **Tertiary:** 2+ Discord server joins from social referrals

### Review Cadence

- **Daily (Mon-Fri):** Check X mentions, Discord activity, reply to anything urgent
- **Weekly (Friday):** Full metrics pull, update inbound tracker, assess what's working
- **Post-campaign (2026-04-02):** Retrospective -- which channels drove interest, which content resonated, what to change for next cycle

## Execution Commands

### Pre-Campaign Setup

```bash
# Verify all blog posts are live
curl -s -o /dev/null -w "%{http_code}" https://soleur.ai/blog/case-study-legal-document-generation/
curl -s -o /dev/null -w "%{http_code}" https://soleur.ai/blog/case-study-brand-guide-creation/
curl -s -o /dev/null -w "%{http_code}" https://soleur.ai/blog/case-study-competitive-intelligence/
curl -s -o /dev/null -w "%{http_code}" https://soleur.ai/blog/case-study-business-validation/
curl -s -o /dev/null -w "%{http_code}" https://soleur.ai/blog/case-study-operations-management/
```

### Discord Posts (Automated)

```bash
# Post #1: Legal Document Generation (Wed 2026-03-12)
# Uses discord-content skill. Content from distribution-content/01-legal-document-generation.md
skill: soleur:discord-content
# Paste Discord variant from content file, approve when prompted

# Post #2: Operations Management (Fri 2026-03-14)
skill: soleur:discord-content

# Post #3: Competitive Intelligence (Wed 2026-03-19)
skill: soleur:discord-content

# Post #4: Brand Guide Creation (Fri 2026-03-21)
skill: soleur:discord-content

# Post #5: Business Validation (Wed 2026-03-26)
skill: soleur:discord-content
```

### X/Twitter Threads (Semi-Automated)

```bash
# Post #1: Legal Document Generation (Wed 2026-03-12)
# Step 1: Post hook tweet
bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet "HOOK_TWEET_TEXT"
# Step 2: Get tweet ID from output, post body tweets as replies
bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet --reply-to TWEET_ID "BODY_TWEET_2"
bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet --reply-to REPLY_ID "BODY_TWEET_3"
bash plugins/soleur/skills/community/scripts/x-community.sh post-tweet --reply-to REPLY_ID "FINAL_TWEET"

# Repeat pattern for each case study. Full tweet text in distribution-content/ files.
```

### X/Twitter Metrics

```bash
# Weekly metrics pull (every Friday)
bash plugins/soleur/skills/community/scripts/x-community.sh metrics

# Mention digest
skill: soleur:community
# Select "digest" option
```

### IndieHackers / Reddit / HN (Manual)

1. Open pre-generated content from `distribution-content/` files
2. Copy the platform-specific variant
3. Post manually on the platform
4. Log the post URL in the inbound tracker

### Social Distribution Skill (Alternative)

```bash
# Generate all variants for a single blog post at once
skill: soleur:social-distribute
# Input: path to blog post markdown file
# Output: platform-specific variants (can verify against pre-generated content)
```

## Automated vs. Manual Breakdown

| Platform | Automation Level | Mechanism | Human Step |
|----------|-----------------|-----------|------------|
| Discord | Fully automated | `discord-content` skill + webhook | Approve post before send |
| X/Twitter | Semi-automated | `x-community.sh post-tweet` | Copy tweet text, chain replies manually |
| IndieHackers | Manual | Pre-generated content, copy-paste | Post, monitor comments |
| Reddit | Manual | Pre-generated content, copy-paste | Post, monitor comments |
| Hacker News | Manual | Pre-generated title + URL | Submit, do not comment on own post |

## Risk Mitigation

- **Reddit self-promotion rules:** All Reddit content is written value-first. Soleur is mentioned as context, not as a pitch. If a post gets flagged, do not repost -- move to the next study.
- **HN flag risk:** Only submit 2 of 5 studies. If the first gets flagged or sinks, skip the second. HN audience is allergic to marketing.
- **X engagement bait:** Every hook tweet delivers standalone value. No "thread" announcements, no engagement farming questions.
- **Content fatigue:** Wednesday/Friday cadence with platform staggering ensures no audience sees the same story twice in one day.
