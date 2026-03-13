# Feature: Unified Marketing Campaign Plan

## Problem Statement

Marketing distribution is fragmented across three disconnected systems: a hardcoded content-publisher.sh (case statement mapping integers 1-6), an ad-hoc social-distribute skill, and one-off distribution plans per content piece. Adding new content requires editing 3 files. The CMO agent has no connection to distribution infrastructure. The current campaign plan expires March 30, 2026 with no rollover mechanism.

## Goals

- Zero-registration content pipeline: adding content = dropping a file in `distribution-content/`
- Automated daily publishing via cron trigger scanning content file frontmatter
- Unified content generation flow where social-distribute outputs persistent content files
- Rolling campaign calendar maintained by the CMO agent

## Non-Goals

- Automating IndieHackers or Hacker News posting (no APIs, manual when warranted)
- Reddit API automation (90/10 rule, domain reputation risk, API registration changes make it high-risk; content generated but posted manually)
- Real-time post-merge distribution triggers (cron is sufficient)
- Content analytics or engagement tracking (separate concern)
- A/B testing of distribution variants
- Central manifest or registry file (directory scanning replaces this)

## Functional Requirements

### FR1: Directory-Driven Content Discovery

`content-publisher.sh` scans `distribution-content/*.md` files and reads YAML frontmatter instead of using a hardcoded case statement. Each content file declares its own `title`, `type`, `publish_date`, `channels`, and `status`.

### FR2: Daily Cron Publishing

`scheduled-content-publisher.yml` runs on a daily cron schedule. It invokes `content-publisher.sh` in scan mode, which finds files with `publish_date == today` and `status: scheduled`, publishes to declared channels, and updates status to `published`.

### FR3: Social-Distribute Content File Output

The `social-distribute` skill generates platform-specific content variants and saves them as a markdown file in `distribution-content/` with proper frontmatter (`status: draft`). Replaces ephemeral conversation-only output.

### FR4: Living Campaign Calendar

CMO-maintained `campaign-calendar.md` that provides a rolling view of upcoming and past distributions. Derived from scanning content files. Updated weekly or on demand by the CMO agent.

### FR5: Existing Content Migration

Retrofit YAML frontmatter onto all 6 existing content files in `distribution-content/`. Set appropriate `type`, `channels`, and `status: published` for already-distributed content.

## Technical Requirements

### TR1: Frontmatter Parsing in Bash

`content-publisher.sh` must parse YAML frontmatter from markdown files. Use `awk` or `sed` to extract the frontmatter block between `---` delimiters, then parse key-value pairs. No external YAML parser dependency.

### TR2: Idempotent Publishing

Publishing the same content file twice must not create duplicate posts. The `status: published` field prevents re-publishing. The existing deduplication for GitHub issues (title-based) is dropped since manual issues are eliminated.

### TR3: Workflow Backwards Compatibility

During migration, `content-publisher.sh` should support both the old integer-based invocation (for in-flight scheduled items) and the new scan mode. The integer path can be removed after all existing content is retrofitted.

### TR4: Status Write-Back from CI

The workflow needs `contents: write` permission to commit `status: published` changes back to the repo after successful publishing. The cron job must git commit and push status updates to prevent re-publishing on subsequent runs.
