# Learning: New Skill Creation Lifecycle

## Problem

Adding a new skill to the Soleur plugin requires touching 6+ files across the codebase. Missing any registration step causes the skill to be invisible or version metadata to be inconsistent. Additionally, plan documents tend toward over-specification when the deliverable is a markdown-only artifact.

## Solution

### Skill Creation Checklist (6 files)

1. `plugins/soleur/skills/<name>/SKILL.md` -- the skill itself
2. `plugins/soleur/docs/_data/skills.js` -- category map + count comments
3. `plugins/soleur/README.md` -- add row to category table
4. `plugins/soleur/.claude-plugin/plugin.json` -- MINOR version bump + description count
5. `plugins/soleur/CHANGELOG.md` -- new version entry
6. Root `README.md` -- version badge + skill count in description

Also update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder version.

### SKILL.md Authoring Pattern

Follow the `atdd-developer` pattern:
- YAML frontmatter: `name` (kebab-case), `description` (third person: "This skill should be used when...")
- Markdown headings for phases (Phase 0, Phase 1, etc.)
- XML semantic tags (`<critical_sequence>`, `<decision_gate>`) for complex control flow
- Imperative instructions in body, never second person

### Plan-to-Code Ratio

For markdown-only deliverables (skills, agents, commands), keep the plan at roughly 1:1 with the expected output size. A ~300 line plan for a ~150 line skill is over-specified. Remove: pseudocode blocks (prose suffices), test scenarios (non-executable), duplicate sections, risk tables that restate design decisions.

### Git Merge Invalidates Read Cache

After running `git merge origin/main`, any previously-read files that changed in the merge become stale in the Edit tool's cache. Always re-read files immediately before editing if a merge occurred between the initial read and the edit.

## Key Insight

Skill creation is a registration-heavy operation (6 files minimum). The skill content itself is usually straightforward if you follow an existing skill as a template. The risk is in the registration steps, not the skill logic. Use the versioning triad checklist and verify counts match across all files.

## Tags
category: implementation-patterns
module: plugins/soleur/skills
symptoms: missing skill registration, version mismatch, file cache invalidation
