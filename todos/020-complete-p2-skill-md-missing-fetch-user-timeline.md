---
status: pending
priority: p2
issue_id: "020"
tags: [code-review, agent-native]
dependencies: []
---

# Update SKILL.md with fetch-user-timeline command

## Problem Statement

`plugins/soleur/skills/community/SKILL.md` line 42 lists x-community.sh commands but does not include the new `fetch-user-timeline` command. Agents entering through SKILL.md rather than being directly spawned as community-manager would not know the command exists, breaking discoverability.

## Findings

- `community-manager.md` line 43 was updated to include `fetch-user-timeline` in the script description
- `SKILL.md` line 42 still reads: `x-community.sh -- X/Twitter API v2 wrapper (fetch-metrics, fetch-mentions, fetch-timeline, post-tweet)`
- The SKILL.md is the entry point that the skill loader surfaces to agents and users

## Proposed Solutions

### Option 1: Add fetch-user-timeline to SKILL.md parenthetical list

**Approach:** One-line edit to add `fetch-user-timeline` to the command list in SKILL.md.

**Effort:** 1 minute
**Risk:** Low

## Technical Details

**Affected files:**
- `plugins/soleur/skills/community/SKILL.md:42`

## Acceptance Criteria

- [ ] SKILL.md lists `fetch-user-timeline` in x-community.sh description

## Work Log

### 2026-03-13 - Initial Discovery

**By:** Code Review (agent-native-reviewer)

**Actions:**
- Identified SKILL.md was not updated alongside community-manager.md
