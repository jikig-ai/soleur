---
title: "feat: Add release-announce skill with ship integration"
type: feat
date: 2026-02-12
issue: "#59"
version-bump: MINOR
---

# feat: Add release-announce skill with ship integration

## Overview

Create a new `/release-announce` skill that generates AI-powered release announcements from CHANGELOG.md and posts them to Discord (webhook) and GitHub Releases (`gh release create`). Integrate into `/ship` Phase 8 as a post-merge step.

## Problem Statement

Release announcements are manual and forgotten. After `/ship` creates and merges a PR, there is no step to notify the community on Discord or create a GitHub Release. This means version releases go unannounced.

## Proposed Solution

A standalone skill at `plugins/soleur/skills/release-announce/SKILL.md` that:

1. Reads the current version from `plugins/soleur/.claude-plugin/plugin.json`
2. Extracts the matching `## [x.y.z]` section from `plugins/soleur/CHANGELOG.md` (parse from heading to next `## [` heading)
3. Generates one detailed AI summary from the changelog section
4. Posts to Discord via `curl` + `DISCORD_WEBHOOK_URL` env var (truncate summary to 1900 chars + release link for Discord)
5. Creates a GitHub Release via `gh release create vX.Y.Z` (uses full summary)

The `/ship` skill gets a small addition to Phase 8: after merge, check if plugin files changed, and if so, invoke `/release-announce`.

**Execution context:** After `gh pr merge --squash`, the code is on main (remote). The skill runs from the worktree but operates against the GitHub API -- `gh release create` and Discord webhook work regardless of local branch. Reading plugin.json from the worktree is correct since it contains the version that was just merged.

## Technical Approach

### Architecture

```
/release-announce (standalone skill)
    |
    +-- Step 1: Read version + changelog, generate summary
    +-- Step 2: Post to Discord (if DISCORD_WEBHOOK_URL set)
    +-- Step 3: Create GitHub Release (if not already exists)

/ship Phase 8 (modified)
    |
    +-- Merge PR (existing)
    +-- Check if plugin.json changed in branch (NEW)
    +-- If yes: invoke /release-announce (NEW)
    +-- Cleanup worktree (existing)
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tag format | `vX.Y.Z` | Standard convention, matches semver |
| Discord format | Plain text markdown | Simpler than embeds, easier to maintain |
| Summary generation | One detailed summary, truncated to 1900 chars for Discord | Simpler than generating two separate summaries |
| Idempotency | Check `gh release view` before creating | Skip GitHub Release if exists |
| Changelog parsing | Extract from `## [version]` to next `## [` heading | Standard Keep a Changelog format |

### Implementation Phases

#### Phase 1: Create release-announce skill

**File:** `plugins/soleur/skills/release-announce/SKILL.md`

SKILL.md structure (3 steps, follows numbered pattern per constitution):

```markdown
---
name: release-announce
description: This skill should be used when announcing a new plugin release
  to Discord and GitHub Releases. It parses CHANGELOG.md, generates an
  AI-powered summary, and posts to configured channels. Triggers on
  "announce release", "post release", "release announcement",
  "/release-announce".
---

# release-announce Skill

## Step 1: Read Version, Changelog, and Generate Summary

1. Read version from plugins/soleur/.claude-plugin/plugin.json
2. Extract ## [version] section from plugins/soleur/CHANGELOG.md
   (parse from `## [X.Y.Z]` heading to next `## [` heading)
3. If section missing: error with clear message, stop
4. Generate a detailed summary of the changelog section
   - Include all categories (Added, Changed, Fixed, Removed)
   - Tone: enthusiastic but professional
   - This summary is used for both Discord and GitHub Release

## Step 2: Post to Discord

1. Check DISCORD_WEBHOOK_URL env var
2. If unset: warn "DISCORD_WEBHOOK_URL not set, skipping Discord", continue
3. Build Discord message:
   ```
   **Soleur vX.Y.Z released!**

   <summary truncated to 1900 chars>

   Full release notes: https://github.com/jikig-ai/soleur/releases/tag/vX.Y.Z
   ```
4. POST via curl: curl -H "Content-Type: application/json" \
     -d '{"content": "<message>"}' "$DISCORD_WEBHOOK_URL"
5. If HTTP response is not 2xx: warn with status code, continue

## Step 3: Create GitHub Release

1. Check if release already exists: gh release view vX.Y.Z
2. If exists: warn "Release vX.Y.Z already exists, skipping", continue
3. Create release: gh release create vX.Y.Z --title "vX.Y.Z" --notes "<full summary>"
4. If fails: warn with error message
5. Report results: print status for each channel and GitHub Release URL
```

#### Phase 2: Modify /ship skill

**File:** `plugins/soleur/skills/ship/SKILL.md`

Add to Phase 8 (Post-Merge Cleanup), after the merge step but before worktree cleanup.

Note: After `gh pr merge --squash`, the code is on main (remote). The skill runs from the worktree but `gh release create` and Discord webhook operate via APIs -- local branch doesn't matter.

```markdown
**If merged:**

1. Check if plugin version was bumped in this branch:
   git diff --name-only $(git merge-base HEAD origin/main)..HEAD -- plugins/soleur/.claude-plugin/plugin.json

2. If plugin.json was modified: Run /release-announce to post announcements

3. Run worktree cleanup (existing step)
```

This is ~5 lines added to an existing phase. Minimal change.

#### Phase 3: Version bump and documentation

- MINOR bump: 2.1.0 -> 2.2.0 (new skill)
- Update versioning triad: plugin.json, CHANGELOG.md, README.md
- Update root README.md badge
- Update .github/ISSUE_TEMPLATE/bug_report.yml placeholder
- Update README.md skill count (34 -> 35) and skill table

## Acceptance Criteria

- [ ] `plugins/soleur/skills/release-announce/SKILL.md` exists with valid frontmatter
- [ ] SKILL.md uses third-person description ("This skill should be used when...")
- [ ] Skill parses version from plugin.json and extracts CHANGELOG.md section
- [ ] Discord posting works when `DISCORD_WEBHOOK_URL` is set
- [ ] Missing `DISCORD_WEBHOOK_URL` produces warning, not error
- [ ] GitHub Release created with `vX.Y.Z` tag via `gh release create`
- [ ] Existing GitHub Release detected and skipped (no duplicate)
- [ ] `/ship` Phase 8 invokes `/release-announce` when plugin.json changed
- [ ] `/ship` Phase 8 skips announcement when no plugin.json change
- [ ] Graceful degradation on network failures (log + continue)
- [ ] Version bumped to 2.2.0 in plugin.json, CHANGELOG.md, README.md
- [ ] Skill count updated in README.md (34 -> 35) and plugin.json description

## Test Scenarios

- Given CHANGELOG.md has a `## [2.2.0]` section, when `/release-announce` runs, then it extracts that section, generates a summary, posts to Discord, and creates a GitHub Release
- Given `DISCORD_WEBHOOK_URL` is unset, when `/release-announce` runs, then it warns "DISCORD_WEBHOOK_URL not set, skipping Discord" and still creates the GitHub Release
- Given GitHub Release v2.2.0 already exists, when `/release-announce` runs, then it skips GitHub Release creation with a warning and still attempts Discord
- Given CHANGELOG.md has no `## [2.2.0]` section, when `/release-announce` runs, then it errors with "Changelog section for v2.2.0 not found" and stops
- Given `/ship` merges a PR that modified plugin.json, when Phase 8 runs, then `/release-announce` is invoked
- Given `/ship` merges a PR without plugin.json changes, when Phase 8 runs, then announcement is skipped

## Dependencies & Risks

**Dependencies:**
- `gh` CLI must be authenticated (already required by `/ship`)
- `curl` must be available (standard on all supported platforms)
- `DISCORD_WEBHOOK_URL` env var for Discord posting

**Risks:**
- Discord webhook URL could be invalid -> mitigated by HTTP response checking
- GitHub Release could fail due to permissions -> mitigated by warning and continuing
- Discord message could exceed 2000-char limit -> mitigated by truncating summary to 1900 chars + appending release link

## References

- Spec: `knowledge-base/specs/feat-release-announce/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-12-release-announce-brainstorm.md`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md` (Phase 8 integration point)
- Changelog skill: `plugins/soleur/skills/changelog/SKILL.md` (Discord webhook pattern)
- Issue: #59
