# Brand Vision, Strategy & Marketing Tools

**Date:** 2026-02-12
**Status:** Accepted
**Participants:** Jean, Claude

## Context

Soleur has made significant progress as a product. A Discord Community Server is live, and release announcements are being automated (issue #59). Before ramping up marketing, we need to design the brand vision and strategy -- and build the tools to enforce it consistently.

The README already has strong positioning language ("Company-as-a-Service", "infinite leverage", soloentrepreneurs) but nothing is formalized. No brand guide, no marketing agents, no content creation workflow exists.

## What We're Building

### 1. Brand Architect Agent (`agents/marketing/brand-architect.md`)

An interactive agent that guides users through a brand identity workshop:

- **Mission, vision, values** -- Why Soleur exists, where it's going, what it stands for
- **Positioning** -- Target audience, competitive differentiation, key messaging
- **Voice and tone** -- How Soleur sounds across channels (ambitious-inspiring externally, challenge-reasoning internally)
- **Messaging pillars** -- Core themes that all content should reinforce
- **Visual direction** -- Color palette suggestions, typography recommendations, logo direction (uses `gemini-imagegen` for explorations)

**Output:** A structured brand guide document at `knowledge-base/overview/brand-guide.md`

### 2. Brand Voice Reviewer Agent (`agents/marketing/brand-voice-reviewer.md`)

Reviews any outbound content against the brand guide before posting. Modeled after `every-style-editor` but for Soleur's brand:

- Checks voice/tone alignment
- Validates messaging pillar coverage
- Flags off-brand language
- Suggests improvements

### 3. Discord Content Skill (`skills/discord-content/`)

Creates and posts Discord community content with two modes:

- **Auto-send** (routine): Release summaries, weekly project updates, milestone celebrations
- **Approval required** (novel): Community engagement posts, thought pieces, announcements

References the brand guide for consistent voice. Uses `DISCORD_WEBHOOK_URL` env var for posting.

### 4. GitHub Presence Skill (`skills/github-presence/`)

Improves Soleur's public-facing GitHub artifacts:

- Enriches release notes with brand-consistent language
- Manages repo metadata (description, topics, social preview)
- Polishes README sections
- Engages with discussions and issues in brand voice

### 5. Brand Guide Document (`knowledge-base/overview/brand-guide.md`)

The single source of truth for Soleur's brand identity. Generated via the brand-architect agent, referenced by all marketing tools. Structured sections:

- Company identity (mission, vision, values)
- Positioning and messaging framework
- Voice and tone guidelines
- Visual identity direction
- Content guidelines per channel

## Why This Approach

**Brand-first, tools-second.** The brand guide is a small artifact (one document) but high-leverage -- it prevents content inconsistency without over-engineering a full marketing platform.

**Semi-autonomous model.** Routine content auto-sends (release notes, weekly updates). Novel content pauses for human approval. This builds trust while maximizing leverage.

**Start where users are.** Discord and GitHub are where early adopters already engage. Twitter/X deferred to v2 to avoid OAuth complexity.

**New agent domain.** `agents/marketing/` is a natural extension alongside `engineering/`, `research/`, `workflow/`. The brand architect and voice reviewer are genuinely different capabilities from anything in the existing domains.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Brand voice | Ambitious-inspiring | Like Vercel's marketing. Bold, forward-looking, energizing. Contrasts with internal dev culture (challenge-reasoning, no flattery). |
| First channels | Discord + GitHub | Existing infrastructure, where early adopters are. Lowest friction to first post. |
| V2 channel | Twitter/X | High reach for dev tools but requires OAuth setup. Deferred. |
| Autonomy model | Semi-autonomous | Routine auto-sends, novel requires approval. Builds trust during brand-establishment phase. |
| Agent architecture | New `marketing/` domain | Clean separation. Agents: brand-architect, brand-voice-reviewer. Skills stay flat per convention. |
| Brand guide location | `knowledge-base/overview/brand-guide.md` | Accessible to all agents. Next to constitution and other foundational docs. |
| Visual identity | Included (simple) | Color palette, typography, logo direction via gemini-imagegen. Iterate as company evolves. |

## Open Questions

1. **Content cadence** -- How often should Discord community posts go out? Weekly? After every release? Need to establish a rhythm without being noisy.
2. **Release-announce integration** -- Issue #59 already plans Discord release announcements. How does `discord-content` relate? Should release-announce become a sub-workflow of discord-content, or stay separate?
3. **Brand guide evolution** -- How do we handle brand guide updates as the company matures? Version the document? Track changes?
4. **Multi-channel adapter** -- Issue #43 proposed messaging platform adapters. Does this influence the discord-content skill design, or is that premature?

## Existing Assets to Leverage

- `every-style-editor` -- Pattern for brand voice reviewer (editorial review against a reference document)
- `gemini-imagegen` -- Visual exploration for brand identity
- `feature-video` -- Demo/marketing video creation
- `changelog` -- Audience-aware tone guidance, Discord webhook pattern
- README positioning language -- Starting point for brand messaging

## Phasing

**Phase 1 (This feature):**
- Brand architect agent
- Brand voice reviewer agent
- Brand guide document (generated via workshop)
- Discord content skill
- GitHub presence skill

**Phase 2 (Future):**
- Twitter/X content skill
- Content calendar/scheduling
- Analytics and engagement tracking

**Phase 3 (Future):**
- Full marketing campaign orchestration
- Multi-channel content strategy agent
- A/B testing for messaging
