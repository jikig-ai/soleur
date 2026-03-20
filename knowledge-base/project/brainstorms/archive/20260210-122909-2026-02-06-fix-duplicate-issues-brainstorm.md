# Brainstorm: Fix Duplicate GitHub Issues During Workflow

**Date:** 2026-02-06
**Status:** Complete
**Related Issue:** #18

## What We're Building

A fix to the `/soleur:brainstorm` command to prevent duplicate GitHub issues when brainstorming starts from an existing issue (e.g., `/soleur:brainstorm github issue #10`).

## Problem Statement

When a brainstorm session starts with a reference to an existing GitHub issue:
- The workflow currently creates a **new** GitHub issue in Phase 3.6
- This results in duplicate issues (e.g., #10/#15, #14/#16)
- The original issue becomes orphaned while the new issue tracks the work

## Why This Approach

**Detection-based skip:** Parse the feature description for issue references and skip issue creation if one exists.

This approach:
- Requires minimal changes to the brainstorm command
- Works for the common pattern of `github issue #N` in arguments
- Links artifacts to the existing issue rather than creating duplicates

## Key Decisions

1. **Detection method:** Regex parse `#\d+` or `issue #\d+` from feature description
2. **Behavior when issue detected:**
   - Skip `gh issue create` step
   - Use existing issue number in all references
   - Update existing issue with spec/brainstorm links (optional)
3. **Scope:** Only affects `/soleur:brainstorm` command, Phase 3.6

## Open Questions

None - requirements are clear.

## Implementation Notes

Modify `plugins/soleur/commands/soleur/brainstorm.md`:

In Phase 3.6, before creating a new issue:
1. Parse feature_description for issue reference pattern
2. If found, extract issue number and verify it exists (`gh issue view #N`)
3. Skip creation, use existing issue number for all subsequent references
4. Optionally: Update existing issue body with links to brainstorm/spec files
