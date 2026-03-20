---
title: "fix: Remove community and report-bug skills from plugin loader"
type: fix
date: 2026-02-22
---

# fix: Remove community and report-bug skills from plugin loader

## Enhancement Summary

**Deepened on:** 2026-02-22
**Sections enhanced:** 5 (Problem, Root Cause, Solution Steps, Files Modified, Risk Assessment)
**Research sources:** codebase grep analysis, plugin loader learnings, brand-guide count locations, community-manager agent dependency analysis

### Key Improvements
1. Found 2 additional skill count locations the original plan missed: `knowledge-base/overview/brand-guide.md` (lines 21, 51)
2. Found `skills.js` category comment line needs updating (line 7)
3. Identified 3 exact lines in community-manager agent needing update (17, 19, 209) with specific replacement text
4. Confirmed report-bug has zero downstream dependencies (no file references `soleur:report-bug`)
5. Confirmed community scripts directory (`skills/community/scripts/`) is actively used by community-manager agent at 13 call sites

## Problem

After the v3.0.3 cleanup that moved reference files out of `commands/` to prevent autocomplete pollution, two skills still appear in the plugin loader that should not be user-invocable skills:

1. **`/soleur:community`** -- Requires Discord credentials (`DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `DISCORD_WEBHOOK_URL`). The community-manager agent already directly uses the shell scripts at `skills/community/scripts/`. The skill is a thin routing wrapper that adds no value over invoking the agent directly.

2. **`/soleur:report-bug`** -- A user-only utility for filing GitHub issues. The earlier command-vs-skill analysis (learning `2026-02-12-command-vs-skill-selection-criteria.md`) explicitly categorized `report-bug` as "Commands (user-only): Actions requiring human intent that agents should never invoke autonomously." It was incorrectly migrated to a skill in v3.0.0.

Neither skill is invoked by any other skill or workflow via the Skill tool (verified by grep). Removing them from the plugin loader reduces autocomplete noise from 52 to 50 skills.

## Root Cause

Both skills were created as proper `skills/<name>/SKILL.md` files and are correctly discovered by the plugin loader. The issue is not a loader bug -- it is that these two capabilities should not be in the skill namespace at all:

- `community`: Infrastructure setup skill that requires pre-configured Discord credentials. Better served by the community-manager agent directly. The skill's own body acknowledges this -- the `post` sub-command simply says "use discord-content skill directly" because skills cannot invoke skills.
- `report-bug`: User-only action (filing bugs) that should not be agent-discoverable. Was explicitly classified as "user-only" in the command/skill taxonomy (learning `2026-02-12-command-vs-skill-selection-criteria.md`, line 15).

### Research Insights

**Plugin loader behavior (from learning `2026-02-12-plugin-loader-agent-vs-skill-recursion.md`):**
- Skills loader discovers exactly `skills/<name>/SKILL.md` at one level of nesting
- Removing the SKILL.md file is sufficient to make a skill invisible -- the directory and its contents can remain
- This is the inverse of the v3.0.3 fix which moved files INTO skills directories to hide them

**Dependency analysis (verified by grep):**
- `soleur:report-bug`: Zero references anywhere in the codebase outside its own SKILL.md and docs/changelog
- `soleur:community`: Referenced only in its own SKILL.md and in the community-manager agent (3 lines referencing `/soleur:community setup`)
- Neither is used in any Skill tool invocation by any other skill or agent

## Solution

Remove both `SKILL.md` files. The plugin loader only discovers `skills/<name>/SKILL.md` -- removing the file makes the skill invisible while preserving the directory and its contents (scripts, etc.).

### Step 1: Remove SKILL.md files

| File to Remove | Reason |
|----------------|--------|
| `plugins/soleur/skills/community/SKILL.md` | Thin wrapper around community-manager agent; requires Discord credentials |
| `plugins/soleur/skills/report-bug/SKILL.md` | User-only utility incorrectly migrated to skill |

Use `git rm` to track the deletion:

```text
git rm plugins/soleur/skills/community/SKILL.md
git rm -r plugins/soleur/skills/report-bug/
```

### Step 2: Preserve community scripts directory

The `plugins/soleur/skills/community/scripts/` directory MUST be preserved. The community-manager agent references these scripts directly at 13 call sites:

- `skills/community/scripts/discord-community.sh` -- Discord Bot API wrapper (messages, members, guild-info, channels)
- `skills/community/scripts/discord-setup.sh` -- Discord bot setup automation (validate-token, discover-guilds, list-channels, create-webhook, write-env, verify)
- `skills/community/scripts/github-community.sh` -- GitHub API wrapper (activity, contributors, discussions)

The agent at `agents/support/community-manager.md` line 23 references: `skills/community/scripts/`.

After removing SKILL.md, the directory structure becomes:

```text
skills/community/
  scripts/
    discord-community.sh
    discord-setup.sh
    github-community.sh
```

This is valid -- the loader ignores directories without SKILL.md.

### Step 3: Remove report-bug directory entirely

Since `report-bug/` contains only `SKILL.md` and no scripts or references, delete the entire directory:

```text
git rm -r plugins/soleur/skills/report-bug/
```

### Step 4: Update community-manager agent references

The community-manager agent references `/soleur:community setup` at 3 locations. Since the skill is being removed, update these to reference the setup script path directly.

**Lines to update in `plugins/soleur/agents/support/community-manager.md`:**

| Line | Old Text | New Text |
|------|----------|----------|
| 17 | `direct the user to run /soleur:community setup and stop.` | `direct the user to run the Discord setup script at plugins/soleur/skills/community/scripts/discord-setup.sh and stop.` |
| 19 | `Run /soleur:community setup to configure.` | `Run the setup script: DISCORD_BOT_TOKEN_INPUT="<token>" plugins/soleur/skills/community/scripts/discord-setup.sh validate-token` |
| 209 | `direct users to /soleur:community setup which handles bot creation, token validation, and .env configuration via discord-setup.sh` | `direct users to run the setup scripts at plugins/soleur/skills/community/scripts/discord-setup.sh for bot creation, token validation, and .env configuration` |

### Step 5: Update docs data file

Remove both entries from `plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES and update the comment:

- Line 7: Change `// Last verified: 2026-02-22 (4 categories, 52 skills)` to `// Last verified: 2026-02-22 (4 categories, 50 skills)`
- Line 48: Remove `"report-bug": "Review & Planning",`
- Line 53: Remove `community: "Workflow",`

### Step 6: Update README.md skill table and counts

Remove both entries from the skills table in `plugins/soleur/README.md`:
- `community` row
- `report-bug` row

Update the skill count from 52 to 50:
- Line 44: `| Skills | 52 |` -> `| Skills | 50 |`

### Step 7: Update plugin.json description

Update the skill count in `plugins/soleur/.claude-plugin/plugin.json` description field:
- Line 4: `"52 skills"` -> `"50 skills"`

### Step 8: Update root README.md

Update the skill count text in root `README.md`:
- Line 14: `"52 skills"` -> `"50 skills"`

### Step 9: Update brand guide

Update the skill count in `knowledge-base/overview/brand-guide.md`:
- Line 21: `"52 skills"` -> `"50 skills"`
- Line 51: `"52 skills"` -> `"50 skills"`

### Step 10: Version bump (PATCH)

Update the versioning triad:
- `plugins/soleur/.claude-plugin/plugin.json` -- bump version (3.0.3 -> 3.0.4)
- `plugins/soleur/CHANGELOG.md` -- document removal under `### Removed`
- `plugins/soleur/README.md` -- verify counts match

### Step 11: Verification

Run these verification commands after all changes:

```text
# Verify no remaining references to removed skills in active files
grep -rn 'soleur:community\|soleur:report-bug' plugins/soleur/ --include='*.md' --include='*.js'

# Verify community scripts still exist
ls plugins/soleur/skills/community/scripts/

# Verify skill count (should be 50 directories with SKILL.md)
find plugins/soleur/skills -name "SKILL.md" -type f | wc -l

# Verify all "52" references are updated
grep -rn '\b52 skills\b' .
```

Expected results: grep for removed skills returns only CHANGELOG.md entries (historical). Skill count returns 50. No remaining "52 skills" in active files.

## Acceptance Criteria

- [x] `/soleur:community` no longer appears in plugin loader autocomplete
- [x] `/soleur:report-bug` no longer appears in plugin loader autocomplete
- [x] Community scripts at `skills/community/scripts/` still exist and are accessible by community-manager agent
- [x] community-manager agent no longer references non-existent `/soleur:community setup` skill
- [x] `docs/_data/skills.js` SKILL_CATEGORIES no longer lists `community` or `report-bug`
- [x] All skill counts updated to 50 across 5 files: plugin.json, plugin README.md, root README.md, brand-guide.md, skills.js comment
- [x] Version bump (PATCH)

## Files Modified

**Deleted (2 files + 1 directory):**
- `plugins/soleur/skills/community/SKILL.md`
- `plugins/soleur/skills/report-bug/` (entire directory)

**Edited (7 files):**
- `plugins/soleur/agents/support/community-manager.md` -- remove `/soleur:community setup` references (3 lines)
- `plugins/soleur/docs/_data/skills.js` -- remove 2 skill category entries, update comment count
- `plugins/soleur/README.md` -- remove 2 skill table rows, update count from 52 to 50
- `plugins/soleur/.claude-plugin/plugin.json` -- version bump + skill count update
- `plugins/soleur/CHANGELOG.md` -- document changes
- Root `README.md` -- update skill count from 52 to 50
- `knowledge-base/overview/brand-guide.md` -- update skill count from 52 to 50 (2 occurrences)

## Risk Assessment

**Low risk.** Neither skill is invoked by any other skill or agent via the Skill tool (grep verified). The community scripts are preserved for the community-manager agent. The report-bug skill has zero dependencies.

### Edge Cases Considered

1. **Community scripts directory without SKILL.md:** Valid pattern -- the loader ignores directories without SKILL.md. The community-manager agent references scripts by path, not through the skill discovery mechanism.

2. **Users who know `/soleur:community`:** Will get "skill not found." The community-manager agent remains available via Task and provides identical functionality. The setup sub-command's functionality remains available through the shell scripts. Acceptable trade-off for cleaner autocomplete.

3. **Brand guide stale counts:** Found 2 occurrences of "52 skills" in brand-guide.md that the original plan missed. These are in prose text used by content generation -- stale counts propagate into marketing copy and Discord posts.

4. **CHANGELOG references:** Historical CHANGELOG entries mentioning community and report-bug skills should NOT be updated -- they are accurate records of when these skills existed. The grep verification step should filter out CHANGELOG.md hits.

5. **Docs site dynamic rendering:** The skills page at `docs/pages/skills.html` renders from `skills.js` data. Removing entries from SKILL_CATEGORIES means the skills page automatically reflects the change with no HTML edits needed.
