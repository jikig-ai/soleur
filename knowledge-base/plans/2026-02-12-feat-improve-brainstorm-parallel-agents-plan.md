---
title: "feat: Improve brainstorm with learnings agent and conversational tone"
type: feat
date: 2026-02-12
updated: 2026-02-12
---

# Improve Brainstorm with Learnings Agent and Conversational Tone

[Updated 2026-02-12] Simplified after parallel review by DHH, Kieran, and Simplicity reviewers. Dropped `best-practices-researcher`, `spec-flow-analyzer`, and the 4-principle philosophy section. Kept `learnings-researcher` and conversational tone guidance.

## Overview

Add `learnings-researcher` alongside `repo-research-analyst` in brainstorm Phase 1, and add conversational tone guidance with a before/after example to the brainstorming skill. Small, focused change that improves context and question quality without duplicating the planning phase.

## Problem Statement

The brainstorm command follows a rigid, prescriptive question script. It runs a single research agent and has no access to institutional learnings (past gotchas, documented solutions). The tone guidance in the skill file is formulaic rather than conversational.

## Proposed Solution

**Three files, four changes:**

1. **`brainstorm.md`** -- Add `learnings-researcher` alongside `repo-research-analyst` in Phase 1.1
2. **`SKILL.md`** -- Add conversational tone guidance + before/after example + "challenge assumptions" technique + one anti-pattern row
3. **`AGENTS.md`** -- Add project-wide anti-sycophancy guidance to Interaction Style section
4. **Version bump** -- MINOR (check current version at implementation time) across plugin.json, CHANGELOG.md, README.md

## Technical Approach

### Change 1: Add learnings-researcher in brainstorm.md

**Current Phase 1.1** (lines ~54-57):
```markdown
#### 1.1 Repository Research (Lightweight)
Run a quick repo scan to understand existing patterns:
- Task repo-research-analyst("Understand existing patterns related to: <feature_description>")
Focus on: similar features, established patterns, CLAUDE.md guidance.
```

**New Phase 1.1** -- Replace with:
```markdown
#### 1.1 Research (Context Gathering)

Run these agents **in parallel** to gather context before dialogue:

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**
- **Repo research:** existing patterns, similar features, CLAUDE.md guidance
- **Learnings:** documented solutions in `knowledge-base/learnings/` -- past gotchas, patterns, lessons learned that might inform WHAT to build

If either agent fails or returns empty, proceed with whatever results are available. Weave findings naturally into your first question rather than presenting a formal summary.
```

**Why `learnings-researcher` and not others:**
- `learnings-researcher` is cheap (haiku model), local-only, and answers WHAT questions ("we tried this before and hit X gotcha")
- `best-practices-researcher` answers HOW questions (community standards, framework conventions) -- belongs in `/soleur:plan` Phase 1.5b where it already runs
- `framework-docs-researcher` is a planning concern -- already in `/soleur:plan` Phase 1.5b
- `spec-flow-analyzer` needs a spec to analyze -- brainstorm output is intentionally incomplete; plan already runs it in Step 3

**AGENTS.md compliance:** Two lightweight agents (one existing, one haiku-model) is consistent with the interaction style guidance. The key change is weaving findings into the first question naturally, not presenting a formal research summary phase.

### Change 2: Conversational Tone in SKILL.md

**Add to the existing "Question Techniques" section** (around line 49), not as a new section:

```markdown
5. **Be curious, not prescriptive**
   Follow the user's energy -- if they light up about an aspect, explore it
   deeper. If they seem decided, don't interrogate. The goal is collaborative
   exploration, not an interview.

   Old (prescriptive):
   > "For authentication, you should use JWT tokens with refresh tokens
   > stored in httpOnly cookies."

   New (curious):
   > "What security constraints are you working with? Have you weighed
   > session-based vs token-based auth for your use case?"
```

**Add to Anti-Patterns table** (around line 174):

| Forcing scripted questions when user leads elsewhere | Follow the user's thread, return to structure later |

**Add a second technique** for challenging assumptions honestly:

```markdown
6. **Challenge assumptions honestly**
   If the user's idea has a flaw or an unexplored risk, say so directly.
   Don't fold your argument just because the user pushes back -- explain
   your reasoning and let them decide. A brainstorm that only validates
   is a wasted brainstorm.
```

**Reconcile with existing guidance:** The current SKILL.md line 102 says "Lead with a recommendation and explain why." This stays -- leading with a recommendation is fine when presenting approaches in Phase 2. The new "curious, not prescriptive" guidance applies to Phase 1 dialogue (understanding the idea), not Phase 2 (presenting approaches). No conflict. "Challenge assumptions" reinforces both -- recommend honestly, don't just agree.

### Change 3: Anti-Sycophancy in AGENTS.md

**Add to the existing "Interaction Style" section** (after the current content about research agents):

```markdown
## Communication Style

- Challenge reasoning instead of validating by default -- explain the counter-argument, then let the user decide.
- Stop excessive validation. If something looks wrong, say so directly.
- Avoid flattery or unnecessary praise. Acknowledge good work briefly, then move on.
```

**Why AGENTS.md and not SKILL.md:** These are general behavior directives that apply to all Soleur interactions (planning, review, work, brainstorm). Putting them in the brainstorm skill would scope them too narrowly. The brainstorm-specific version ("challenge assumptions honestly") lives in the skill; the broader stance lives here.

### Change 4: Version Bump

Check current version in `plugins/soleur/.claude-plugin/plugin.json` at implementation time (defer exact number per learnings). This is a MINOR bump -- wiring a new agent into a command changes user-facing behavior.

**Files to update:**
- `plugins/soleur/.claude-plugin/plugin.json` -- bump version
- `plugins/soleur/CHANGELOG.md` -- add entry with: Added learnings-researcher to brainstorm Phase 1; Changed brainstorming skill question techniques with conversational tone guidance
- `plugins/soleur/README.md` -- verify component counts (no new agents/commands/skills, just wiring)

## Acceptance Criteria

- [ ] Phase 1.1 launches `repo-research-analyst` and `learnings-researcher` in parallel
- [ ] Research findings woven into first question naturally (no formal summary phase)
- [ ] If either agent fails or returns empty, brainstorm proceeds without interruption
- [ ] SKILL.md Question Techniques includes "Be curious, not prescriptive" with before/after example
- [ ] SKILL.md Question Techniques includes "Challenge assumptions honestly"
- [ ] SKILL.md anti-patterns table includes "forcing scripted questions" row
- [ ] AGENTS.md has "Communication Style" section with anti-sycophancy guidance
- [ ] Plugin version bumped (MINOR) across plugin.json, CHANGELOG.md, README.md
- [ ] `best-practices-researcher` NOT present in brainstorm
- [ ] `spec-flow-analyzer` NOT present in brainstorm
- [ ] `framework-docs-researcher` NOT present in brainstorm

## Test Scenarios

- Given a feature description, when brainstorm runs, then both repo-research-analyst and learnings-researcher execute in parallel before dialogue begins
- Given an empty knowledge-base/learnings/ directory, when brainstorm runs, then learnings-researcher returns empty and brainstorm proceeds normally with repo-research findings only
- Given a feature with documented learnings, when brainstorm runs, then relevant gotchas are woven into the first question
- Given the updated SKILL.md, when brainstorm enters dialogue, then questions are open-ended and exploratory rather than formulaic
- Given a user proposes an approach with a clear flaw, when brainstorm is in dialogue, then the agent flags the flaw directly rather than validating the approach

## What Was Cut (and Why)

| Cut | Reason | Where it lives instead |
|-----|--------|----------------------|
| `best-practices-researcher` | Answers HOW, not WHAT | `/soleur:plan` Phase 1.5b |
| `spec-flow-analyzer` (Phase 2.5) | No spec to analyze yet; plan already runs it | `/soleur:plan` Step 3 |
| Formal research summary phase (1.1b) | Contradicts AGENTS.md interaction style; natural weaving is better | N/A -- findings woven into dialogue |
| 4-principle Conversational Philosophy section | Overlapping abstractions for one idea; examples teach better than manifestos | Condensed to 1 technique + 1 example |

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-improve-brainstorm-brainstorm.md`
- Spec: `knowledge-base/specs/feat-improve-brainstorm/spec.md`
- Issue: #52
- Review feedback: DHH, Kieran, Simplicity reviewers (2026-02-12)
