# Spec: Fix Duplicate GitHub Issues During Workflow

**Status:** Draft
**Issue:** #18
**Branch:** `feat-fix-duplicate-issues`

## Problem Statement

The `/soleur:brainstorm` command creates duplicate GitHub issues when invoked with a reference to an existing issue. For example, `/soleur:brainstorm github issue #10` results in both issue #10 and a new issue #15 tracking the same feature.

## Goals

- Detect when brainstorm is invoked with an existing GitHub issue reference
- Skip issue creation in Phase 3.6 when an issue already exists
- Use the existing issue number for all spec/brainstorm references

## Non-Goals

- Automatically updating the existing issue body (can be v2)
- Detecting issues from other sources (PR references, URLs)
- Changing behavior of `/soleur:plan` or other commands

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Parse feature description for issue patterns (`#\d+`, `issue #\d+`, `github issue #\d+`) |
| FR2 | Validate detected issue exists via `gh issue view` |
| FR3 | Skip `gh issue create` when valid existing issue detected |
| FR4 | Use existing issue number in output summary and references |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Modify `plugins/soleur/commands/soleur/brainstorm.md` only |
| TR2 | Add conditional logic in Phase 3.6 section |
| TR3 | Preserve existing behavior when no issue reference found |

## Acceptance Criteria

- [ ] `/soleur:brainstorm github issue #18` does not create a new issue
- [ ] Output shows "Using existing issue: #18" instead of "Issue: #N (created)"
- [ ] `/soleur:brainstorm add dark mode` (no issue ref) still creates a new issue
- [ ] Invalid issue references (e.g., `#99999`) fall back to creating new issue
