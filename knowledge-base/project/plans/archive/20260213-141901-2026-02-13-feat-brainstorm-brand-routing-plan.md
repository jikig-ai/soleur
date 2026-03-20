---
title: "feat: Integrate brand-architect into brainstorm workflow"
type: feat
date: 2026-02-13
---

# Integrate Brand-Architect into Brainstorm Workflow

## Overview

Add a "Specialized Domain Routing" section to `/soleur:brainstorm` Phase 0 that detects brand/marketing topics via keyword matching, confirms with the user, and hands off to the `brand-architect` agent. This gives users a natural entry point for brand workshops through the existing brainstorm command.

## Problem Statement

The brand-architect agent (`agents/marketing/brand-architect.md`) is only invocable via the Task tool. Users who try `/soleur:marketing:brand-architect` get "Unknown skill." There is no user-facing entry point. See issue #76.

## Proposed Solution

Insert a new "Phase 0.5: Specialized Domain Routing" section into `brainstorm.md` between the existing "clear requirements" check and Phase 1. When brand/marketing keywords are detected in the feature description, offer the user a choice to enter the brand workshop instead of the generic brainstorm flow.

### Flow

```
Phase 0 (existing)
  |
  v
Phase 0.5: Specialized Domain Routing (NEW)
  - Scan feature_description for domain keywords
  - Brand/marketing match? -> AskUserQuestion: "Start brand workshop?"
    - Yes -> Phase 3 (worktree) -> Phase 3.6 (issue) -> Task brand-architect -> Output summary
    - No  -> Continue to Phase 1
  |
  v
Phase 1 (existing, unchanged)
```

## Acceptance Criteria

- [x] Feature descriptions containing brand/marketing keywords trigger an AskUserQuestion offering the brand workshop
- [x] Declining the offer continues the normal brainstorm flow unchanged
- [x] Accepting creates a worktree and issue, then invokes brand-architect via Task tool
- [x] No brainstorm document is created for brand workshop sessions
- [x] The output summary uses the existing format with "Document: none (brand workshop)" and an added "Brand guide:" line
- [x] The domain routing section is structured so adding future domains is copy-paste obvious
- [x] Plugin version bumped (MINOR: 2.3.1 -> 2.4.0) with CHANGELOG and README updated

## Test Scenarios

- Given a feature description "define our brand identity", when brainstorm runs Phase 0.5, then AskUserQuestion offers brand workshop
- Given a feature description "add user authentication", when brainstorm runs Phase 0.5, then no domain routing is triggered and Phase 1 starts normally
- Given brand workshop is accepted, when worktree is created, then brand-architect agent is invoked via Task tool with the feature description
- Given brand workshop is declined, when brainstorm continues, then Phase 1 research runs as usual with no side effects

## MVP

### `plugins/soleur/commands/soleur/brainstorm.md` -- Insert after line 55 (after one-shot paragraph)

New section to add:

```markdown
### Phase 0.5: Specialized Domain Routing

Check if the feature description matches a specialized domain that has a dedicated agent.

<!-- To add a new domain: copy the Brand / Marketing block below, change keywords, agent name, and output summary -->

#### Brand / Marketing

**Keywords:** brand, brand identity, brand guide, voice and tone, brand workshop

Scan the feature description text (case-insensitive) for any of these keywords using substring matching. If any keyword appears anywhere in the description, it is a match.

**If no keywords match:** Continue to Phase 1 (no routing offered).

**If keywords match:**

Use **AskUserQuestion tool** to ask: "This looks like a brand/marketing topic. Would you like to run the brand identity workshop instead?"

Options:
1. **Start brand workshop** - Run the brand-architect agent to create or update a brand guide
2. **Brainstorm normally** - Continue with the standard brainstorm flow

**If brainstorm normally is selected:** Continue to Phase 1 as usual.

**If brand workshop is selected:**

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "define our brand identity" -> `brand-identity`). If the description is fewer than 3 words, default to `brand-guide`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
   - Update the issue body with artifact links (brand guide path, branch name)
   - Do NOT generate spec.md -- brand workshops produce a brand guide, not a spec

3. **Navigate to worktree:**

   ```bash
   cd ${WORKTREE_PATH}
   pwd  # Must show .worktrees/feat-<name>
   ```

   Verify location before proceeding.

4. **Hand off to brand-architect:**

   ```
   Task brand-architect(feature_description)
   ```

   The brand-architect agent runs its full interactive workshop and writes the brand guide to `knowledge-base/overview/brand-guide.md` inside the worktree.

5. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Brand workshop complete!

   Document: none (brand workshop)
   Brand guide: knowledge-base/overview/brand-guide.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: The brand guide is now available for discord-content and other marketing skills.
   ```

   End brainstorm execution after displaying this message.
```

### Version Bump Files

**`plugins/soleur/.claude-plugin/plugin.json`** -- Bump version from `2.3.1` to `2.4.0`

**`plugins/soleur/CHANGELOG.md`** -- Add entry:

```markdown
## [2.4.0] - 2026-02-13

### Added

- Brainstorm command detects brand/marketing topics and offers to route to the brand-architect agent (#76)
- New "Specialized Domain Routing" pattern in brainstorm Phase 0 for future domain extensions
```

**`plugins/soleur/README.md`** -- Verify description and counts (no new components added, just enhanced existing command)

**Root `README.md`** -- Update version badge to 2.4.0

**`.github/ISSUE_TEMPLATE/bug_report.yml`** -- Update version placeholder to 2.4.0

## References

- Spec: `knowledge-base/specs/feat-brainstorm-brand-routing/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-13-brainstorm-brand-routing-brainstorm.md`
- Brand-architect agent: `plugins/soleur/agents/marketing/brand-architect.md`
- Brainstorm command: `plugins/soleur/commands/soleur/brainstorm.md`
- Issue: #76
