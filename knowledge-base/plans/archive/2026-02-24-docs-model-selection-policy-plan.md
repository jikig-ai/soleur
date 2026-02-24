# Plan: Document Model Selection Policy and Standardize to Inherit

**Issue:** #294
**Branch:** feat-model-policy
**Type:** docs/config
**Version bump:** PATCH (3.0.9 -> 3.0.10)

[Updated 2026-02-24] Simplified after plan review. Removed agent-native-architecture reference doc rewrites (those are correct general advice for external developers, not Soleur internal policy).

## Summary

Formalize the implicit model selection policy (`model: inherit` everywhere) into documented standards, fix the one exception (`learnings-researcher` using haiku), and add explicit `effortLevel: high` to project settings.

## Changes

### 1. Fix learnings-researcher model override

**File:** `plugins/soleur/agents/engineering/research/learnings-researcher.md`
**Line 4:** Change `model: haiku` to `model: inherit`

### 2. Add Model Selection Policy to AGENTS.md

**File:** `plugins/soleur/AGENTS.md`
**Location:** Between the Agent Compliance Checklist (ending line 117) and the Skill Compliance Checklist (starting line 119), add a new `## Model Selection Policy` section:

- Default: `model: inherit` for all agents
- Override justification: explicit model overrides require justification in the agent body
- Effort control: session-level only (`env.CLAUDE_CODE_EFFORT_LEVEL` in `.claude/settings.json` or `/model` slider), not per-agent
- No current justified exceptions

Also update line 101 in the Agent Compliance Checklist from:
```
- [ ] `model:` field present (`inherit`, `haiku`, `sonnet`, or `opus`)
```
to:
```
- [ ] `model: inherit` (see Model Selection Policy; explicit overrides require justification)
```

### 3. Add effortLevel to project settings

**File:** `.claude/settings.json`
**Change:** Add `"effortLevel": "high"` as a top-level key alongside the existing `"hooks"` key. Do not nest inside hooks.

### 4. Version bump (PATCH)

- `plugins/soleur/.claude-plugin/plugin.json`: 3.0.9 -> 3.0.10
- `plugins/soleur/CHANGELOG.md`: Add entry
- `plugins/soleur/README.md`: Update version
- Root `README.md`: Update version badge (currently stale at 3.0.7 -- update to 3.0.10)

Note: `.github/ISSUE_TEMPLATE/bug_report.yml` does not exist in this repo -- skip.

### 5. Post-edit verification

```bash
# Verify no agent uses non-inherit model
shopt -s globstar && grep -n 'model:' plugins/soleur/agents/**/*.md | grep -v 'model: inherit'
# Expected: empty (no matches)

# Verify settings.json has effortLevel
grep 'effortLevel' .claude/settings.json
# Expected: "effortLevel": "high"
```

## Files Modified (6 total)

| File | Change |
|------|--------|
| `plugins/soleur/agents/engineering/research/learnings-researcher.md` | `model: haiku` -> `model: inherit` |
| `plugins/soleur/AGENTS.md` | Add Model Selection Policy section, update checklist |
| `.claude/settings.json` | Add `effortLevel: high` |
| `plugins/soleur/.claude-plugin/plugin.json` | Version 3.0.10 |
| `plugins/soleur/CHANGELOG.md` | Add entry |
| `plugins/soleur/README.md` | Update version |

Plus root `README.md` version badge update.

## Test Scenarios

**Given** all agents are checked for model field
**When** running `grep -n 'model:' plugins/soleur/agents/**/*.md | grep -v 'model: inherit'`
**Then** no matches (all agents use inherit)

**Given** the project settings file exists
**When** reading `.claude/settings.json`
**Then** it contains `"effortLevel": "high"` as a top-level key

## Out of Scope

- Changing the constitution (policy lives in AGENTS.md)
- Per-agent effort controls (not supported by Claude Code plugin spec)
- Updating the docs site HTML (no version badges in docs since v2.9.3)
- Rewriting agent-native-architecture reference docs (correct general advice for external developers paying per API token; not related to Soleur internal agent policy)
