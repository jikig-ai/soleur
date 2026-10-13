# Feature: Named Domain Leaders

## Problem Statement

Domain leaders are addressed by role acronyms (CTO, CMO, CPO, etc.), making the AI organization feel impersonal and generic. Users cannot develop a sense of ownership over their team. The "full AI organization" brand promise is undermined when the team members have no names.

## Goals

- Users can assign custom names to each of their 8 domain leaders
- Names display as "Name (Role)" format across all surfaces (web + CLI)
- @-mentions work with both custom name and role acronym
- Naming is encouraged but never required -- zero-config users see role titles as today
- Naming creates emotional switching costs aligned with Phase 3 "Make it Sticky"

## Non-Goals

- Personalities / behavioral customization (deferred to Post-MVP, #1879)
- Avatar or visual customization
- Naming specialist agents (only the 8 domain leaders)
- Multi-tenant name sharing (Phase 3 is single-user)

## Functional Requirements

### FR1: Team Settings Page

A "Team" section in the web platform settings where users can set a custom name for each leader. Shows all 8 leaders with their role, current name (or placeholder), and an edit field. Changes persist immediately.

### FR2: Onboarding Prompt

During first-run onboarding, present: "Want to name your team?" with all 8 leaders listed. Skippable. Pre-populated with role acronyms. User can fill in names or skip entirely.

### FR3: Contextual Nudge

After a user's first interaction with a domain leader, display a non-blocking suggestion: "You just worked with your CTO. Want to give them a name?" Dismissible. Only shown once per leader.

### FR4: Display Format

Custom names always display as "Name (Role)" -- e.g., "Alex (CTO)". Role title is never hidden. This applies to: conversation messages, @-mention dropdowns, leader cards, KB artifacts, and CLI output.

### FR5: Dual @-mention Syntax

If a user names their CTO "Alex," both `@Alex` and `@CTO` route to the CTO. The @-mention autocomplete dropdown shows both entries: "Alex (CTO)" and "CTO." Matching is case-insensitive.

### FR6: CLI Knowledge-base Sync

Custom names are synced to `knowledge-base/project/team-config.md` for CLI consumption. CLI agents read this file at session start and use custom names in output while retaining role acronyms for internal routing.

### FR7: Default Experience

Users who never set names see the current behavior: role acronyms everywhere. No degradation of existing UX.

## Technical Requirements

### TR1: Supabase Storage

Names stored in Supabase as a user-level setting. Schema should anticipate multi-user (workspace-level) but Phase 3 implements user-level only. Likely a JSON column on user profile or a dedicated `team_names` table with `(user_id, leader_id, custom_name)`.

### TR2: Agent Routing Integrity

Agent YAML frontmatter `name:` fields remain unchanged. Custom names are a presentation layer. The `domain-router.ts` @-mention parser extends to match custom names but resolves to the same `DomainLeaderId`. All internal routing uses role IDs.

### TR3: Input Validation

Custom names must be validated to prevent prompt injection (names are embedded in system prompts). Constraints: max 30 characters, alphanumeric + spaces only, no special characters or control sequences. Reject names that match reserved words (system prompt fragments).

### TR4: Knowledge-base Sync Format

`team-config.md` follows a simple table format readable by both humans and agents:

```markdown
| Role | Name |
|------|------|
| cto  | Alex |
| cmo  | Morgan |
```

### TR5: Web Platform Integration Points

Extend `domain-leaders.ts` registry to include a `customName` field loaded from Supabase at session start. Components that consume the registry (`at-mention-dropdown.tsx`, `leader-colors.ts`, `welcome-card.tsx`, `domain-router.ts`) use `customName ?? name` for display.
