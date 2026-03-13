---
title: "feat: Brand vision, strategy & marketing tools"
type: feat
date: 2026-02-12
issue: "#71"
updated: 2026-02-12
---

# Brand Vision, Strategy & Marketing Tools

[Updated 2026-02-12] Revised after plan review -- scope reduced ~50% per DHH, Kieran, and Simplicity reviewer feedback. Cut brand-voice-reviewer agent (inline instead) and github-presence skill (deferred to v2). Kept visual direction per user request.

## Overview

Build the brand identity foundation and first marketing content tool for Soleur. This establishes a new `agents/marketing/` domain with one agent (brand-architect) and one skill (discord-content), anchored by a structured brand guide document.

## Problem Statement

Soleur has no formalized brand identity, voice guidelines, or marketing content infrastructure. The README contains strong but informal positioning language ("Company-as-a-Service", "infinite leverage", soloentrepreneurs). A Discord Community Server exists but has no content creation workflow. Before ramping marketing, the brand needs to be codified and tools need to enforce it consistently.

## Proposed Solution

### Architecture

```
plugins/soleur/
  agents/
    marketing/                          # New domain
      brand-architect.md                # Interactive brand identity workshop
  skills/
    discord-content/
      SKILL.md                          # Discord community content creation + posting

knowledge-base/
  overview/
    brand-guide.md                      # Single source of truth (output of brand-architect)
```

### Key Design Decisions

**1. Bootstrap dependency.** discord-content checks for `brand-guide.md` existence at invocation. If missing, it warns and exits: "No brand guide found. Run the brand architect agent first." This makes the dependency explicit.

**2. Discord overlap with changelog and release-announce (#59).** discord-content is self-contained for v1. It does not subsume the changelog skill or release-announce (#59). Each has a distinct concern:
- `changelog` = generates formatted changelog from git history (content generation)
- `release-announce` (#59) = posts release announcements to Discord/GitHub (distribution, not yet built)
- `discord-content` = creates community content beyond releases (engagement, updates, tips)

**3. Brand voice review is inline, not a separate agent.** [Changed from original plan] Per reviewer feedback, a standalone brand-voice-reviewer agent is premature -- there is no content corpus to review yet. Instead, discord-content includes an inline "Brand Voice Check" section that validates drafts against the brand guide's Voice section before presenting to the user. If a standalone reviewer is needed later, it can be extracted when there are multiple consumers.

**4. Brand guide format: structured markdown with a parsing contract.** The brand guide uses consistent `##` headings that downstream tools depend on. See "Brand Guide Contract" section below for the exact specification.

**5. Content cadence: all user-initiated.** Claude Code plugins have no scheduling mechanism. All content generation is triggered by the user running the skill with a topic description.

**6. All content requires user approval in v1.** [Changed from brainstorm's semi-autonomous proposal] Deferred auto-send until trust is established with the brand voice. Simpler and safer.

**7. github-presence deferred to v2.** [Changed from original plan] Per reviewer feedback, release notes enrichment overlaps with future release-announce (#59), and repo metadata is a one-time `gh repo edit` command. Defer until there is demonstrated need.

**8. Visual assets stored ephemerally.** Brand visual explorations generated during the workshop are saved to a user-specified directory and shown inline. They are NOT committed to git. The brand guide references visual direction in prose (color hex codes, font names, style descriptions). Users can save generated assets separately for Discord/GitHub branding use.

**9. Model selection: `model: inherit`.** The user's session model determines quality/cost.

**10. Brand guide written atomically.** The brand architect collects all workshop answers, then writes the complete brand-guide.md at the end. No partial documents can exist. Git history serves as version control.

### Brand Guide Contract

Downstream tools (discord-content, future skills) depend on these exact heading names:

| Heading | Required | Purpose |
|---------|----------|---------|
| `## Identity` | Yes | Mission, audience, positioning context |
| `## Voice` | Yes | Tone, do's/don'ts, example phrases -- primary reference for content generation |
| `## Visual Direction` | No | Color palette, typography, style -- used for visual asset generation |
| `## Channel Notes` | No | Channel-specific tweaks (Discord length, GitHub formality) |

**Rules:**
- The brand architect MUST use these exact `##` headings (no variations like "Voice and Tone" or "Brand Voice")
- Downstream tools match headings via exact string: `^## Voice$`, `^## Channel Notes$`, etc.
- If a required section is missing, downstream tools warn: "Brand guide is incomplete -- missing [section]. Run brand architect to update."
- If an optional section is missing, downstream tools proceed without it (no warning)
- `### ` subsections within each `##` section are freeform -- no parsing contract on subsections

## Implementation Phases

### Phase 1: Brand Architect Agent + Brand Guide

Create the interactive agent that runs brand identity workshops and outputs a structured brand guide.

**Files to create:**

- `plugins/soleur/agents/marketing/brand-architect.md`

**Draft YAML frontmatter:**

```yaml
---
name: brand-architect
description: "Use this agent when you need to define or refine a brand identity. It guides an interactive workshop covering company identity, positioning, voice and tone, visual direction, and channel-specific guidelines. Outputs a structured brand guide document to knowledge-base/overview/brand-guide.md. <example>Context: The user wants to establish brand identity for their project.\\nuser: \"We need to define our brand voice and visual identity before launching marketing.\"\\nassistant: \"I'll use the brand-architect agent to guide a brand identity workshop and produce a brand guide.\"\\n<commentary>\\nThe user needs a structured brand identity definition, which is the core purpose of the brand-architect agent.\\n</commentary>\\n</example>\\n\\n<example>Context: The user wants to update their existing brand guide.\\nuser: \"Our positioning has evolved. I want to update the brand guide.\"\\nassistant: \"I'll launch the brand-architect agent to review and update the existing brand guide section by section.\"\\n<commentary>\\nThe brand architect detects existing brand guides and offers section-by-section updates rather than starting from scratch.\\n</commentary>\\n</example>"
model: inherit
---
```

**Agent behavior:**

1. Check if `knowledge-base/overview/brand-guide.md` exists
2. **If exists:** Read it, present a summary, and ask which section to update. Present the current content of the selected section, then ask the user for changes. Repeat until the user is done. Write the full document atomically.
3. **If not exists:** Run full interactive workshop using AskUserQuestion, one section at a time:
   - **Identity:** Mission, vision, values, target audience, competitive positioning
   - **Voice:** Brand voice description, tone spectrum, do's and don'ts with concrete examples, example phrases for common scenarios
   - **Visual Direction:** Color palette (hex codes), typography (font names), style description. Optionally invoke `gemini-imagegen` for explorations if `GEMINI_API_KEY` is set. If not set, skip image generation and collect text descriptions only.
   - **Channel Notes:** Discord-specific tone/length guidance, GitHub-specific formality level
4. Write complete brand guide atomically to `knowledge-base/overview/brand-guide.md`

**Brand guide document structure:**

```markdown
---
last_updated: YYYY-MM-DD
---

# Soleur Brand Guide

## Identity

### Mission
[Why Soleur exists]

### Target Audience
[Who Soleur serves]

### Positioning
[Competitive differentiation and key messaging]

## Voice

### Brand Voice
[Core voice description -- e.g., "Ambitious-inspiring: bold, forward-looking, energizing"]

### Tone Spectrum
[How tone varies by context -- e.g., "Discord: casual-enthusiastic, GitHub: professional-precise"]

### Do's and Don'ts

**Do:**
- [Example of on-brand language]

**Don't:**
- [Example of off-brand language]

### Example Phrases
[Concrete examples for common scenarios -- announcements, replies, descriptions]

## Visual Direction

### Color Palette
[Primary and secondary colors with hex codes]

### Typography
[Font families and usage guidelines]

### Style
[Overall visual style description -- e.g., "Clean, modern, developer-focused"]

## Channel Notes

### Discord
[Discord-specific guidelines -- tone, length limits, emoji usage]

### GitHub
[GitHub-specific guidelines -- formality, technical depth]
```

### Phase 2: Discord Content Skill

Create the skill for generating and posting Discord community content.

**Files to create:**

- `plugins/soleur/skills/discord-content/SKILL.md`

**Draft YAML frontmatter:**

```yaml
---
name: discord-content
description: "This skill should be used when creating and posting community content to Discord. It generates brand-consistent posts (project updates, tips, milestones, or custom topics), validates them against the brand guide, and posts via webhook after user approval. Triggers on \"post to Discord\", \"Discord update\", \"community post\", \"Discord announcement\", \"write Discord content\"."
---
```

**Skill behavior:**

1. **Prerequisite check:** Verify `knowledge-base/overview/brand-guide.md` exists (warn and exit if missing). Verify `DISCORD_WEBHOOK_URL` env var is set (warn with setup instructions and exit if missing).
2. **Topic input:** Ask the user "What would you like to post about?" Accept freeform description. Optionally offer: "Summarize recent git activity?" as a shortcut for project updates.
3. **Content generation:** Read brand guide's `## Voice` and `## Channel Notes > ### Discord` sections. Generate draft in brand voice. Enforce 2000-char limit during generation.
4. **Inline brand voice check:** Before presenting to the user, validate the draft against the brand guide's Do's and Don'ts. If issues are found, revise the draft and note what was adjusted.
5. **User approval:** Present final draft with Accept/Edit/Reject options via AskUserQuestion.
   - **Accept:** Proceed to post.
   - **Edit:** User provides feedback, skill regenerates.
   - **Reject:** Discard draft, exit.
6. **Post:** On approval, post via `curl` using plain `content` field (not rich embeds):
   ```bash
   curl -H "Content-Type: application/json" \
     -d "{\"content\": \"$CONTENT\"}" \
     "$DISCORD_WEBHOOK_URL"
   ```
   Content must be properly JSON-escaped before posting.
7. **Error handling:** If webhook returns 4xx/5xx, display the error and the draft content so the user can copy-paste manually. Do not retry.

**Discord webhook payload:** Plain `content` field, consistent with the existing changelog skill pattern. No rich embeds in v1 -- keeps the implementation simple and the content format predictable.

## Acceptance Criteria

- [ ] Given no brand guide exists, when brand architect is invoked, then it runs the full workshop and writes `brand-guide.md` with all four `##` sections (Identity, Voice, Visual Direction, Channel Notes)
- [ ] Given a brand guide exists, when brand architect is invoked, then it reads the existing guide, presents a summary, and allows section-by-section updates without overwriting untouched sections
- [ ] Given the user skips visual direction, when the workshop completes, then the Visual Direction section contains a placeholder noting it was skipped
- [ ] Given `GEMINI_API_KEY` is not set, when visual direction step runs, then image generation is skipped and text descriptions are collected instead (no error)
- [ ] Given `DISCORD_WEBHOOK_URL` is set and brand guide exists, when discord-content runs, then the generated content is under 2000 characters and posted after user approval
- [ ] Given `DISCORD_WEBHOOK_URL` is not set, when discord-content is invoked, then it warns with webhook setup instructions and exits
- [ ] Given brand guide is missing, when discord-content is invoked, then it warns "No brand guide found. Run the brand architect agent first." and exits
- [ ] Given the webhook returns 429/5xx, when posting, then the error is displayed and the draft content is shown for manual copy-paste
- [ ] Given the user selects "Reject", when the approval prompt is dismissed, then no content is posted
- [ ] All new files have correct YAML frontmatter per constitution (agent: name, description with examples, model; skill: name, third-person description)
- [ ] Plugin version bumped (MINOR intent) with CHANGELOG.md, README.md, and plugin.json updated consistently

## Test Scenarios

### Brand Architect Agent

- Given no brand guide exists, when the brand architect is invoked, then it runs the full interactive workshop and writes brand-guide.md atomically with all four required sections and a `last_updated` frontmatter field.
- Given a brand guide already exists, when the brand architect is invoked, then it reads the existing guide, presents its contents, and asks which section to update.
- Given the user updates only the Voice section, when the workshop completes, then Identity, Visual Direction, and Channel Notes are preserved unchanged.
- Given the user skips visual direction, when the workshop completes, then the Visual Direction section contains placeholder text: "Not yet defined. Run brand architect to add visual direction."
- Given `GEMINI_API_KEY` is not set, when the visual direction step runs, then the agent collects text descriptions only and does not attempt image generation.

### Discord Content Skill

- Given `DISCORD_WEBHOOK_URL` is set and brand guide exists, when the user describes a topic, then the skill generates a draft under 2000 characters, performs an inline brand voice check, and presents it for approval.
- Given `DISCORD_WEBHOOK_URL` is not set, when the skill is invoked, then it displays webhook setup instructions and exits.
- Given brand guide is missing, when the skill is invoked, then it warns about the missing brand guide and exits.
- Given the Discord webhook returns a 429 rate limit error, when posting, then the draft is displayed for manual copy-paste and the error is shown.
- Given the user selects "Reject" after reviewing, then no content is posted to Discord.
- Given the user selects "Edit" after reviewing, then the skill accepts feedback and regenerates the draft.

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Brand guide quality depends on user input | High | Medium | Agent provides defaults and examples; guide can be re-run |
| Discord webhook URL not configured | Medium | Low | Clear setup instructions in error message |
| Gemini API unavailable for visual direction | Low | Low | Degrades to text-only descriptions |

## Non-Goals

- Brand voice reviewer as a separate agent (inline in skills instead)
- GitHub presence skill (deferred to v2)
- Twitter/X integration (v2)
- Content calendar or scheduling
- Analytics or engagement tracking
- Multi-channel campaign orchestration
- Full visual design system (logo files, icon sets)
- Blog/long-form content creation
- Issue/discussion engagement via GitHub (v2)
- Auto-send without user approval (v2)
- Rich Discord embeds (plain content field in v1)

## Deferred to v2

| Component | Rationale |
|-----------|-----------|
| brand-voice-reviewer agent | Extract from inline when multiple skills need it |
| github-presence skill | Overlaps with release-announce (#59); repo metadata is a one-time `gh repo edit` |
| Twitter/X content skill | Requires OAuth setup |
| Auto-send for routine content | Build trust with brand voice first |
| Rich Discord embeds | Plain content is sufficient for v1 |

## Version Bump

**Type:** MINOR (new agent + new skill)
**Intent:** 2.1.1 -> 2.2.0

**Files to update:**
- `plugins/soleur/.claude-plugin/plugin.json` -- version + description counts (23 agents, 35 skills)
- `plugins/soleur/CHANGELOG.md` -- v2.2.0 section
- `plugins/soleur/README.md` -- add marketing agents section, add discord-content to skills table, update counts
- Root `README.md` -- version badge
- `.github/ISSUE_TEMPLATE/bug_report.yml` -- version placeholder

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-brand-marketing-brainstorm.md`
- Spec: `knowledge-base/specs/feat-brand-marketing/spec.md`
- Issue: [#71](https://github.com/jikig-ai/soleur/issues/71)
- Related: Issue #59 (release-announce), Issue #43 (multi-platform adapters)
- Pattern references:
  - `plugins/soleur/agents/engineering/design/ddd-architect.md` -- agent frontmatter + structure example
  - `plugins/soleur/skills/every-style-editor/SKILL.md` -- editorial review pattern (for future reviewer extraction)
  - `plugins/soleur/skills/changelog/SKILL.md` -- Discord webhook + audience-aware tone pattern
  - `plugins/soleur/skills/gemini-imagegen/SKILL.md` -- image generation reference
- Plan review feedback: DHH, Kieran, Simplicity reviewers (2026-02-12)
