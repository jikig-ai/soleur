---
title: "feat: Rolling Campaign Calendar"
type: feat
date: 2026-03-12
---

# feat: Rolling Campaign Calendar

## Overview

Create a dedicated Soleur skill (`soleur:campaign-calendar`) that scans `knowledge-base/marketing/distribution-content/*.md`, parses frontmatter, generates a markdown calendar grouped by status, and commits the result. Runs weekly via GitHub Actions and on-demand via `/soleur:campaign-calendar`.

## Problem Statement / Motivation

The fixed distribution plan (`knowledge-base/marketing/content-strategy.md`) expires March 30, 2026 with no rollover mechanism. A prior 15-piece content plan went 100% unexecuted because overcommitment wasn't visible (learning: `2026-03-03-cmo-orchestrated-strategy-review-pattern.md`). The current plan can't reflect real-time status changes from `content-publisher.sh`.

## Proposed Solution

Two deliverables:

1. **Skill**: `plugins/soleur/skills/campaign-calendar/SKILL.md` — the agent reads distribution-content files, generates the calendar markdown, writes it, and commits/pushes in CI
2. **Workflow**: `.github/workflows/scheduled-campaign-calendar.yml` — weekly cron invocation via `claude-code-action`

No separate bash script. The LLM is already running via `claude-code-action` and can read 6 markdown files and generate a table directly. The content-publisher's 447-line bash script earns its complexity with real I/O (Discord webhooks, X API, OAuth). A calendar generator that reads files and writes markdown does not.

### Architecture Flow

```
GitHub Actions cron (Monday 16:00 UTC)
  └─ claude-code-action invokes /soleur:campaign-calendar
       ├─ Agent globs distribution-content/*.md
       ├─ Agent reads each file's frontmatter (title, type, publish_date, channels, status)
       ├─ Agent generates markdown table grouped by status (overdue → scheduled → draft → published)
       ├─ Agent writes knowledge-base/marketing/campaign-calendar.md
       └─ Agent commits + pushes (inside agent prompt, not post-step)
```

### v2 Deferred Items

- **CMO strategy notes** — spawn CMO agent for commentary on what's working and gaps
- **Per-week capacity summary** — flag overcommitment (>2 pieces/week)
- **Twice-weekly cron** — increase frequency if weekly proves insufficient

## Technical Considerations

### CI Workflow Constraints

From learnings `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` and `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`:

- **Push MUST happen inside the agent prompt** — `claude-code-action` revokes its token in post-step cleanup. A `git push` in a subsequent workflow step fails.
- **AGENTS.md main-commit override required** — the workflow prompt must include: `IMPORTANT: This is an automated CI workflow. The AGENTS.md rule "Never commit directly to main" does NOT apply here.`
- **Use `plugin_marketplaces` and `plugins` inputs** for Soleur discovery in CI.
- **Guard empty commits**: `git diff --cached --quiet` before `git commit`.
- **Concurrency group** prevents parallel runs (manual dispatch + scheduled collision).
- **Commit message**: `ci: update campaign calendar [skip ci]` — prevents cascading workflow triggers.
- **Push retry**: `git push origin main || { git pull --rebase origin main && git push origin main; }` — handles non-fast-forward from content-publisher commits.
- **Discord failure notification** — follows existing scheduled workflow pattern.

### Cron Timing

Content-publisher runs daily at 14:00 UTC. Calendar runs Monday at 16:00 UTC — after the publisher has had time to flip any Monday-scheduled content from `scheduled` to `published`. This avoids showing stale status values.

### Manual vs CI Invocation

When run manually via `/soleur:campaign-calendar`, the skill writes the file for preview but does NOT commit. Reason: in a worktree, committing creates a PR that conflicts with the CI direct-push model. The skill prints: "Calendar written. To persist, run: `gh workflow run scheduled-campaign-calendar.yml`"

### Status Grouping

Four groups, not three. Files with `status: scheduled` and `publish_date < today` are "overdue" — the exact failure mode this feature exists to surface:

1. **Overdue** — scheduled but past publish_date (warning)
2. **Upcoming** — scheduled with future publish_date
3. **Draft** — not yet scheduled
4. **Published** — already distributed (most recent first)

### Registration Requirements

From learning `2026-02-22-skill-count-propagation-locations.md`:

New skill must be registered in 5 locations:

1. `docs/_data/skills.js` — add to `SKILL_CATEGORIES`
2. `plugins/soleur/README.md` — update components table count
3. `README.md` (root) — update skill count
4. `knowledge-base/overview/brand-guide.md` — update count (2 occurrences)
5. `plugin.json` — update description count

### Related Specs

This plan implements `feat-unified-marketing-campaign/spec.md` FR4 ("CMO-maintained campaign-calendar.md that provides a rolling view of upcoming and past distributions"). The `feat-rolling-campaign-calendar/spec.md` is the authoritative spec.

## Acceptance Criteria

- [x] `plugins/soleur/skills/campaign-calendar/SKILL.md` exists with correct frontmatter (third-person description)
- [x] Agent reads distribution-content/*.md files and parses frontmatter (title, type, publish_date, channels, status)
- [x] Calendar groups content into 4 statuses: overdue, upcoming, draft, published
- [x] Handles edge cases: zero files (empty state message), malformed frontmatter (skip with warning)
- [x] `knowledge-base/marketing/campaign-calendar.md` generated with `last_updated` frontmatter
- [x] `.github/workflows/scheduled-campaign-calendar.yml` triggers Monday 16:00 UTC via cron + `workflow_dispatch`
- [x] Workflow uses `claude-code-action` with `plugin_marketplaces` and `plugins` inputs
- [x] Workflow prompt includes AGENTS.md main-commit override
- [x] Push happens inside agent prompt with rebase-retry, not post-step
- [x] Commit message includes `[skip ci]`
- [x] Empty commits guarded with `git diff --cached --quiet`
- [x] Concurrency group prevents parallel runs
- [x] Discord failure notification on workflow error
- [x] Manual invocation writes file but does not commit
- [x] Skill counts updated in 5 locations
- [x] Skill registered in `docs/_data/skills.js`

## Test Scenarios

- Given distribution-content/ has 6 files with mixed statuses, when the skill runs, then the calendar contains all 6 entries grouped correctly (overdue, upcoming, draft, published)
- Given distribution-content/ is empty, when the skill runs, then the calendar is generated with a "No content files found" note
- Given a file has missing frontmatter delimiters, when the agent reads it, then the file is skipped with a note
- Given a file has `status: scheduled` and `publish_date` in the past, when the calendar generates, then it appears in the "Overdue" section
- Given the calendar content is identical to the existing file, when the agent attempts to commit, then no commit is created
- Given manual invocation, when the skill completes, then the file is written but not committed

## Dependencies & Risks

**Dependencies:**

- #549 (unified marketing campaign) — CLOSED, landed. Content files have frontmatter.
- `claude-code-action` v1 — for CI invocation. Must pin to SHA.
- `ANTHROPIC_API_KEY` repo secret — already configured for content-publisher.

**Risks:**

- GitHub Actions cron has ~15-minute timing variance — acceptable for weekly refresh
- Token cost per run: ~1 Sonnet invocation (no sub-agent spawn) — low cost

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-12-rolling-campaign-calendar-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-rolling-campaign-calendar/spec.md`
- Content publisher script: `scripts/content-publisher.sh:37-47` (frontmatter parsing reference)
- Content publisher workflow: `.github/workflows/scheduled-content-publisher.yml`
- Schedule skill template: `plugins/soleur/skills/schedule/SKILL.md`
- Unified campaign spec FR4: `knowledge-base/project/specs/feat-unified-marketing-campaign/spec.md`

### Institutional Learnings

- `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` — push inside agent prompt
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md` — token revocation
- `2026-03-03-cmo-orchestrated-strategy-review-pattern.md` — overcommitment visibility failure
- `2026-02-22-skill-count-propagation-locations.md` — 5 registration locations
- `2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md` — CI plugin discovery

### Related Issues

- #558 — this issue
- #549 — unified marketing campaign (dependency, CLOSED)
- Draft PR: #564

## Files to Create/Modify

### New Files

| File | Description |
|------|-------------|
| `plugins/soleur/skills/campaign-calendar/SKILL.md` | Skill definition: read files, generate calendar, write output, commit in CI |
| `.github/workflows/scheduled-campaign-calendar.yml` | GitHub Actions weekly cron (Mon 16:00 UTC) |
| `knowledge-base/marketing/campaign-calendar.md` | Output artifact (generated, not hand-written) |

### Modified Files

| File | Change |
|------|--------|
| `docs/_data/skills.js` | Add campaign-calendar to SKILL_CATEGORIES |
| `plugins/soleur/README.md` | Update skill count |
| `README.md` | Update skill count |
| `knowledge-base/overview/brand-guide.md` | Update skill count (2 occurrences) |
| `plugin.json` | Update description skill count |
