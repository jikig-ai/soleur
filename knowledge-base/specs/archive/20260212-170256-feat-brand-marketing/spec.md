# Spec: Brand Vision, Strategy & Marketing Tools

**Feature:** Brand identity foundation and marketing content tools
**Branch:** `feat-brand-marketing`
**Status:** Draft

## Problem Statement

Soleur has no formalized brand identity, voice guidelines, or marketing content infrastructure. The README contains strong but informal positioning language. A Discord Community Server exists but only has planned (not implemented) release announcement automation. There are no tools to create, review, or distribute brand-consistent content across channels.

## Goals

1. Define and codify Soleur's brand identity (positioning, voice, messaging, visual direction)
2. Build an interactive agent that guides brand identity workshops and produces brand guides
3. Create a content review agent that enforces brand consistency on outbound content
4. Build skills for Discord community content creation and GitHub presence improvement
5. Establish a semi-autonomous content workflow (routine auto-sends, novel requires approval)

## Non-Goals

- Twitter/X integration (v2)
- Content calendar or scheduling system
- Analytics or engagement tracking
- Multi-channel campaign orchestration
- Full visual design system (logo files, icon sets, etc.)
- Blog/long-form content creation

## Functional Requirements

| ID | Requirement | Priority |
|----|------------|----------|
| FR1 | Brand architect agent guides users through interactive brand identity workshop | Must |
| FR2 | Brand architect outputs structured brand guide to `knowledge-base/overview/brand-guide.md` | Must |
| FR3 | Brand architect supports visual exploration via `gemini-imagegen` | Should |
| FR4 | Brand voice reviewer agent checks content against brand guide | Must |
| FR5 | Brand voice reviewer provides specific improvement suggestions | Must |
| FR6 | Discord content skill creates community posts (updates, tips, engagement) | Must |
| FR7 | Discord content skill auto-sends routine content, pauses for novel content approval | Must |
| FR8 | Discord content skill posts via `DISCORD_WEBHOOK_URL` env var | Must |
| FR9 | GitHub presence skill enriches release notes with brand-consistent language | Should |
| FR10 | GitHub presence skill manages repo metadata and README polish | Should |

## Technical Requirements

| ID | Requirement |
|----|------------|
| TR1 | New `agents/marketing/` domain directory for marketing agents |
| TR2 | Brand architect and voice reviewer follow existing agent conventions (YAML frontmatter, examples) |
| TR3 | Discord and GitHub skills follow flat skill directory convention (`skills/<name>/SKILL.md`) |
| TR4 | Brand guide document is plain markdown, accessible to all agents |
| TR5 | Discord posting uses curl + webhook (consistent with changelog skill pattern) |
| TR6 | Plugin version bump required (new agents + skills = MINOR bump) |

## Architecture

```
plugins/soleur/
  agents/
    marketing/                    # New domain
      brand-architect.md          # FR1, FR2, FR3
      brand-voice-reviewer.md     # FR4, FR5
  skills/
    discord-content/              # FR6, FR7, FR8
      SKILL.md
    github-presence/              # FR9, FR10
      SKILL.md

knowledge-base/
  overview/
    brand-guide.md                # FR2 output artifact
```

## Acceptance Criteria

- [ ] Running the brand architect agent produces a complete brand guide document
- [ ] Brand voice reviewer correctly flags off-brand content and suggests improvements
- [ ] Discord content skill can create and post routine community updates
- [ ] Discord content skill pauses for approval on novel content
- [ ] GitHub presence skill can enrich release notes with brand-consistent language
- [ ] All new components follow existing plugin conventions (frontmatter, naming, directory structure)
- [ ] Plugin version bumped with changelog and README updated
