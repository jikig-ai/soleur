# Brainstorm: Unified Marketing Campaign Plan

**Date:** 2026-03-12
**Issue:** #549
**Status:** Complete
**Participants:** Founder, CMO (domain assessment)

## What We're Building

A directory-driven distribution pipeline that eliminates manual content registration. Instead of hardcoding content items in a bash case statement, `content-publisher.sh` scans `distribution-content/*.md` files and reads YAML frontmatter to determine what to publish, when, and where. A rolling campaign calendar maintained by the CMO provides the bird's-eye view.

## Why This Approach

The current system has three disconnected distribution tracks:

1. **Automated pipeline** — `content-publisher.sh` with a hardcoded case statement mapping integers 1-6 to content files
2. **Ad-hoc skill** — `social-distribute` generates variants on-the-fly for blog posts without content files
3. **One-off plans** — each new content piece gets its own bespoke markdown plan

Adding content item #7 requires editing 3 files (bash script, workflow YAML, new content file). The CMO agent has no connection to this infrastructure. The distribution-plan.md expires March 30 with no mechanism to roll forward.

**Directory-driven** was chosen over a central manifest (YAML/JSON) because any manifest creates the same coordination problem — a registry that needs manual updating. With directory scanning, adding content = dropping a file. No manifest to fall out of sync.

## Key Decisions

### 1. Content Discovery: Directory-driven, no manifest

`content-publisher.sh` scans `distribution-content/*.md` files instead of switching on integers. Each content file is self-describing via YAML frontmatter:

```yaml
---
title: "Why Most Agentic Tools Plateau"
type: pillar          # case-study | pillar | announcement
publish_date: 2026-03-15
channels: [discord, x, reddit]
status: scheduled     # draft | scheduled | published
---
```

Slug is derived from filename. No central registry.

### 2. Distribution Trigger: Daily cron

A daily GitHub Actions cron trigger scans content files for `publish_date == today` and `status: scheduled`. Fully automated once content is scheduled. This replaces the current `workflow_dispatch`-only trigger.

Chosen over post-merge detection because timing control matters — content may merge Monday but distribute Thursday. Cron + `publish_date` decouples shipping from distribution.

### 3. Platform Automation: Discord + X + Reddit

- **Discord:** Webhook (existing, works well)
- **X/Twitter:** API thread posting (existing, works well)
- **Reddit:** New API integration (new work)
- **IndieHackers / Hacker News:** Dropped from automated pipeline. Tracked in the living calendar as "manual when high-impact" — no more GitHub issue creation for copy-paste.

### 4. Content Generation Flow: Merged pipeline

`social-distribute` skill becomes the content file generator:

1. social-distribute reads blog post → generates platform variants → saves as content file with `status: draft`
2. Human reviews the content file
3. CMO sets `publish_date` and flips to `status: scheduled`
4. Daily cron publishes and sets `status: published`

This eliminates ephemeral ad-hoc output. Every distribution gets a permanent, auditable artifact.

### 5. Living Campaign Calendar

The CMO maintains a rolling `campaign-calendar.md` derived from scanning the content directory. Updated weekly or on demand. This replaces the fixed-date `distribution-plan.md` that expires March 30.

### 6. Minimal Frontmatter

Five fields only: `title`, `type`, `publish_date`, `channels`, `status`. No priority, campaign tags, or grouping metadata. YAGNI — add later if needed.

## Open Questions

- **Content directory location:** Should `distribution-content/` stay under `knowledge-base/project/specs/feat-product-strategy/` or move to a top-level location like `knowledge-base/distribution-content/`?
- **Reddit API setup:** Which Reddit API approach (OAuth app, script app)? Subreddit targeting per content type?
- **Existing content migration:** Retrofit frontmatter onto all 6 existing content files in one batch, or incrementally as each is (re-)published?
- **CMO calendar cadence:** Weekly refresh or event-driven (new content merged → CMO updates calendar)?
- **Failure handling for cron:** If cron fails to publish (API error), should it retry next day or create an alert? Current script exits with code 2 for partial failures.
