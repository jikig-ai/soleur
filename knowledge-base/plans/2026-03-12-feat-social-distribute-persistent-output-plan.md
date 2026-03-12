---
title: "feat: update social-distribute skill to output persistent content files"
type: feat
date: 2026-03-12
---

# feat: Update social-distribute to output persistent content files

## Overview

Modify the `social-distribute` skill to write platform-specific content variants as `.md` files to `knowledge-base/marketing/distribution-content/` with YAML frontmatter (`status: draft`) instead of outputting content ephemerally to conversation. This connects the content generation skill to the directory-driven pipeline from #549.

## Problem Statement / Motivation

The `social-distribute` skill generates high-quality platform-specific content (Discord, X, Reddit, IH, HN) but outputs everything to the conversation. Content disappears after the session. Meanwhile, #549 landed a directory-driven content publisher that scans `distribution-content/*.md` files with YAML frontmatter and publishes on schedule. These two systems are disconnected -- there is no way to go from "generate content" to "schedule for publishing" without manual copy-paste into a new file.

The desired flow is: **generate (social-distribute) -> review -> schedule -> cron publishes**. Currently the chain breaks at step 1 because output is ephemeral.

## Proposed Solution

Update `SKILL.md` to add a file-writing phase after content generation and approval. Instead of printing variants to conversation as the terminal output, the skill writes a content file in the established format and prints the file path. The user reviews the file and sets `status: scheduled` + `publish_date` when ready.

**Scope:** SKILL.md changes only. No script changes. No workflow changes. No new files beyond the generated content file.

## Technical Approach

### Architecture

```
Blog post (.md)
    |  read by
    v
social-distribute skill (SKILL.md)
    |  generates variants (Phases 1-5, unchanged)
    |  approval flow (Phase 6-7, unchanged)
    |
    v  NEW: Phase 8 (rewritten)
distribution-content/<slug>.md
    |  with YAML frontmatter (status: draft)
    |  sections: Discord, X/Twitter Thread, IndieHackers, Reddit, Hacker News
    |
    v  user sets status: scheduled + publish_date
content-publisher.sh (daily cron, unchanged)
    |  scans directory, publishes to channels
    v
Discord / X (automated)
Reddit / IH / HN (manual sections preserved in file)
```

### Changes to SKILL.md

#### 1. Remove Distribution Pipeline Gate (Phase 0)

The current SKILL.md has a "Distribution Pipeline Gate" at the top that checks if a content file already exists and suggests routing through the automated pipeline. This gate was designed for the old case-statement era. With directory-driven discovery, the skill IS the file creator, so the gate is no longer needed.

**Action:** Delete the `## Distribution Pipeline Gate` section entirely.

#### 2. Phases 1-7 remain unchanged

Content input (Phases 1-3), content generation (Phases 4-5), and approval flow (Phases 6-7) stay as-is. The skill still reads the blog post, gathers stats, generates all 5 platform variants, presents them for review, and posts Discord via webhook after approval.

#### 3. Rewrite Phase 8: Write content file instead of posting Discord ad-hoc

Currently Phase 8 posts to Discord via webhook inline. Replace this with writing the content file. Discord posting moves to the cron pipeline.

**New Phase 8: Write Content File**

1. Derive slug from the blog post filename (strip path, strip `.md`, keep kebab-case)
   - Example: `plugins/soleur/docs/blog/why-most-agentic-tools-plateau.md` -> `why-most-agentic-tools-plateau`
2. Construct the output path: `knowledge-base/marketing/distribution-content/<slug>.md`
3. Check if file already exists -- if so, warn and ask whether to overwrite
4. Write the file with:
   - YAML frontmatter: `title`, `type: pillar`, `publish_date` (empty string -- user fills in), `channels: discord, x`, `status: draft`
   - Section per platform: `## Discord`, `## X/Twitter Thread`, `## IndieHackers`, `## Reddit`, `## Hacker News`
   - Section separators: `---` between sections (matching existing content file format)

**Content file template:**

```markdown
---
title: "<blog post title from frontmatter>"
type: pillar
publish_date: ""
channels: discord, x
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

#### 4. Rewrite Phase 9: Replace manual output with file confirmation

Currently Phase 9 prints all non-Discord variants to the terminal for copy-paste. Since everything is now in the file, replace this with a confirmation message and next-step instructions.

**New Phase 9: Confirmation & Next Steps**

Output:
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

#### 5. Simplify Phase 10: Summary

Update the distribution summary to reflect the new flow:

```
Distribution summary:
- Content file: knowledge-base/marketing/distribution-content/<slug>.md
- Status: draft (review and schedule when ready)
- Discord: Will publish via cron when scheduled
- X/Twitter: Will publish via cron when scheduled
- IndieHackers: Manual (content in file)
- Reddit: Manual (content in file)
- Hacker News: Manual (content in file)
```

#### 6. Discord approval flow decision

The current Phase 7 asks whether to post to Discord immediately via webhook. With the persistent file approach, there are two options:

**Option A (recommended): Keep Discord immediate posting as an option.** The approval flow stays. If user accepts, post to Discord now AND write the file with `channels: x` only (Discord already posted). If user skips, write the file with `channels: discord, x`.

**Option B: Remove immediate Discord posting entirely.** Always write to file as draft. User schedules everything through the cron.

Option A is better because it preserves the existing interactive workflow while adding persistence. The user can still get instant Discord feedback on new content.

**Implementation for Option A:**
- Phase 7 stays as-is (Discord approval)
- If Discord posted successfully: set `channels: x` in frontmatter (Discord already done)
- If Discord skipped or no webhook: set `channels: discord, x` in frontmatter

### File Naming Convention

Use the blog post slug directly, without numeric prefix. The existing content files use `01-`, `02-` numbering from the old case-statement era. New files generated by social-distribute use the blog slug only.

- Existing: `01-legal-document-generation.md`, `06-why-most-agentic-tools-plateau.md`
- New: `why-most-agentic-tools-plateau.md` (if it didn't already exist)

This is forward-compatible. The content-publisher scans all `*.md` files in the directory -- it does not depend on numeric prefixes.

### Edge Cases

**Blog post without frontmatter title.** Fall back to deriving a title from the H1 heading or filename.

**Content file already exists for this blog post.** Present the user with overwrite/skip/rename options via AskUserQuestion. The skill must not silently overwrite existing content files.

**No channels set.** Default to `discord, x` -- these are the two automated channels. Reddit, IH, and HN are manual and don't need to be in the `channels` field.

**`type` field derivation.** Default to `pillar` for blog posts. The existing content files use `case-study` and `pillar`. A blog post is the most common input to social-distribute and maps to `pillar`. If the blog post frontmatter contains a `type` field, use it.

## Non-Goals

- No changes to `content-publisher.sh` -- it already handles the directory-driven format
- No changes to `scheduled-content-publisher.yml` -- the cron pipeline is already in place
- No new script files -- this is a SKILL.md-only change
- No Reddit API automation (deferred per brainstorm decision)
- No campaign calendar integration
- No changes to the content generation logic (Phases 1-5)

## Acceptance Criteria

- [ ] `social-distribute` writes a `.md` file to `knowledge-base/marketing/distribution-content/` after content generation and approval
- [ ] Written file has YAML frontmatter with `title`, `type`, `publish_date`, `channels`, `status: draft`
- [ ] Written file has sections for all 5 platforms: Discord, X/Twitter Thread, IndieHackers, Reddit, Hacker News
- [ ] Written file format matches existing content files (section headings, `---` separators, tweet label format)
- [ ] Distribution Pipeline Gate section removed from SKILL.md
- [ ] If Discord posted via webhook during approval, `channels` field excludes `discord`
- [ ] If content file already exists for the slug, user is prompted before overwrite
- [ ] Skill outputs file path and next-step instructions after writing
- [ ] Existing Phases 1-7 (content input, generation, approval) remain functionally unchanged

## Test Scenarios

- Given a blog post at `plugins/soleur/docs/blog/my-article.md`, when social-distribute runs and user approves all content, then a file `knowledge-base/marketing/distribution-content/my-article.md` is written with `status: draft` frontmatter and all 5 platform sections
- Given a blog post, when social-distribute runs and user approves Discord posting, then the written file has `channels: x` (Discord already posted)
- Given a blog post, when social-distribute runs and user skips Discord, then the written file has `channels: discord, x`
- Given a content file already exists for the slug, when social-distribute runs, then the user is prompted with overwrite/skip options before any write
- Given the written content file, when `publish_date` and `status: scheduled` are set and the cron runs on that date, then `content-publisher.sh` publishes to the declared channels (validates end-to-end integration)

## Dependencies & Risks

**Dependencies:**
- #549 (directory-driven pipeline) -- already merged
- Existing content file format established by #549 -- compatible, no changes needed

**Risks:**
- **Format drift between hand-written and skill-generated content files.** Mitigated by matching the exact format of existing files (same section headings, same tweet label format, same `---` separators).
- **User confusion about draft vs scheduled.** Mitigated by clear next-step instructions in Phase 9 output.

**Semver label:** `semver:patch` -- this is an enhancement to an existing skill, not a new skill.

## References & Research

### Internal References
- Skill: `plugins/soleur/skills/social-distribute/SKILL.md`
- Content publisher: `scripts/content-publisher.sh`
- Content files: `knowledge-base/marketing/distribution-content/*.md`
- Workflow: `.github/workflows/scheduled-content-publisher.yml`
- Brainstorm: `knowledge-base/brainstorms/2026-03-12-unified-marketing-campaign-brainstorm.md`
- Parent plan: `knowledge-base/plans/2026-03-12-feat-unified-marketing-campaign-plan.md` (Follow-Up Issues section)

### Institutional Learnings Applied
- Directory-driven content discovery frontmatter parsing (`knowledge-base/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`) -- use established YAML frontmatter format
- Multi-platform publisher error propagation (`knowledge-base/learnings/2026-03-11-multi-platform-publisher-error-propagation.md`) -- maintain per-file failure semantics
- Discord allowed mentions sanitization -- webhooks must include `allowed_mentions: {parse: []}`

### Related Work
- Issue: #557
- Dependency: #549 (merged)
