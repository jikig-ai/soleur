# Learning: Reddit API Automation Risk Assessment

## Problem

During planning for a unified marketing campaign pipeline (#549), we assumed Reddit API posting could be automated alongside Discord (webhook) and X (API threads). The brainstorm included Reddit as an automated channel. Research revealed this assumption was wrong.

## Solution

Defer Reddit API automation entirely. Keep generating Reddit-formatted content in distribution content files (the content is good), but post manually. The existing pattern of manual Reddit posting is the correct architecture for now.

## Key Insight

Reddit is fundamentally hostile to automated content distribution, unlike Discord and X:

1. **90/10 Rule:** 90% of Reddit activity must be genuine community participation. A CI bot that only posts articles will be flagged as spam. This fundamentally conflicts with "fire and forget" CI publishing.

2. **Domain reputation poisoning:** If `soleur.ai` gets flagged or consistently downvoted, ALL future posts containing that domain are filtered site-wide — regardless of the posting account's reputation. This is an irreversible blast radius.

3. **November 2025 API registration change:** Reddit killed self-service API key creation. All new apps require pre-approval through the Responsible Builder Policy (7+ day lead time). You can no longer go to `reddit.com/prefs/apps` and get instant credentials.

4. **Shadow removals:** Reddit silently removes posts with no API notification. The poster sees their post normally, but nobody else can. Detecting this requires checking from a different account.

5. **Subreddit-specific barriers:** Minimum karma (often 100+), minimum account age (30+ days), required post flair, AutoModerator rules — all undisclosed and varying per subreddit.

**The right pattern:** Generate Reddit content automatically (social-distribute already does this well), but post it manually through an established account with organic participation history. Automation should stop at "here's your Reddit post, copy-paste it."

**When to reconsider:** Only after the Reddit account has 6+ months of organic participation history with sufficient karma in target subreddits. Even then, semi-automated (human reviews and clicks "post") is safer than fully automated.

## Tags
category: integration-issues
module: distribution-strategy
