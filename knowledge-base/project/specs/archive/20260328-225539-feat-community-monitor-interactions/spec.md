# Spec: Community Monitor GitHub Interactions

**Issue:** #1248
**Branch:** community-monitor-interactions
**Status:** Draft

## Problem Statement

The daily community monitor tracks GitHub activity (issue/PR counts, contributors, repo stats) but does not surface individual interactions — specifically, comments from external users on issues and PRs. This means community engagement signals are invisible unless manually checked.

## Goals

- Surface external user comments on GitHub issues/PRs in the daily digest
- Provide enough context (commenter, issue title, comment snippet) to decide whether follow-up is needed
- Follow existing platform script and community-router conventions

## Non-Goals

- X/Twitter reply tracking (deferred — Free tier API limitation)
- Reaction/emoji tracking on issues/PRs
- Automated response to comments
- Cross-platform interaction correlation

## Functional Requirements

- **FR1:** `github-community.sh fetch-interactions` command fetches issue and PR comments from the last 24 hours
- **FR2:** Filter to external users only using `author_association` field (keep `NONE`, `CONTRIBUTOR`, `FIRST_TIMER`, `FIRST_TIME_CONTRIBUTOR`) and exclude bots via `.user.type != "Bot"` plus `[bot]$` login fallback
- **FR3:** Output JSON with commenter login, issue/PR number, comment snippet (first ~120 chars, newlines stripped), and URL
- **FR4:** Community-manager agent renders interactions as a `**Community Interactions:**` sub-section within `## GitHub Activity` in the digest
- **FR5:** Scheduled workflow passes interaction data to the agent for digest generation

## Technical Requirements

- **TR1:** Use `gh api` REST endpoints (`/repos/{owner}/{repo}/issues/comments` with `since` parameter)
- **TR2:** Handle pagination via `gh api --paginate` piped through `jq -s 'add // []'` (per learnings)
- **TR3:** Follow the five-layer API wrapper hardening pattern (per learnings)
- **TR4:** Stay within the 50 max-turns budget of the scheduled workflow

## Acceptance Criteria

- [ ] Daily digest includes a `**Community Interactions:**` sub-section under `## GitHub Activity` when external comments exist
- [ ] Sub-section shows a table: commenter | issue/PR | comment snippet
- [ ] Bot and org-member comments are excluded
- [ ] No interactions section when there are no external comments (clean omission)
- [ ] `github-community.sh fetch-interactions` works standalone for testing
