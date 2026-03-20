---
title: Unified Marketing Campaign Plan
type: feat
date: 2026-03-12
---

# feat: Unified Marketing Campaign Plan

## Overview

Replace the hardcoded content-publisher.sh case statement (integers 1-6) with directory-driven content discovery using YAML frontmatter. Add a daily cron trigger. Clean break — no backwards compatibility with the old integer path.

## Problem Statement / Motivation

Three disconnected distribution tracks exist:

1. **Automated pipeline** — `content-publisher.sh` with a `case` statement mapping integers 1-6 to content files in `distribution-content/`
2. **Ad-hoc skill** — `social-distribute` generates variants ephemerally in conversation
3. **One-off plans** — each new blog post gets its own bespoke distribution plan

Adding content item #7 requires editing 3 files (bash script case statement, workflow YAML choice input, new content file). The distribution-plan.md expires March 30 with no rollover mechanism.

## Proposed Solution

**Directory-driven content discovery** with self-describing content files. Each `.md` file in `distribution-content/` declares its own metadata via YAML frontmatter (`title`, `type`, `publish_date`, `channels`, `status`). The script scans the directory instead of switching on integers. A daily cron publishes files where `publish_date == today` and `status: scheduled`.

**Scope changes from brainstorm:**
- Reddit API automation deferred (90/10 rule, domain reputation risk, November 2025 API registration changes)
- Social-distribute skill update deferred to follow-up issue (different kind of change with different risks)
- Campaign calendar deferred (derived artifact — write when needed, not a code dependency)

## Technical Approach

### Architecture

```
distribution-content/*.md  ◄── each file has YAML frontmatter
    │                           (title, type, publish_date, channels, status)
    │ scanned by
    ▼
content-publisher.sh
    │ publishes to
    ├── Discord (webhook)
    └── X/Twitter (API thread via x-community.sh)

scheduled-content-publisher.yml
    │ daily cron (14:00 UTC)
    └── invokes content-publisher.sh (no args = scan mode)
```

### Content File Format (after migration)

```markdown
---
title: "Why Most Agentic Tools Plateau"
type: pillar
publish_date: 2026-03-15
channels: discord, x
status: scheduled
---

## Discord
[content up to 2000 chars]

---

## X/Twitter Thread
**Tweet 1 (Hook) -- 272 chars:**
[tweet text]

**Tweet 2 (Body) -- 267 chars:**
[tweet text]

---

## Reddit
**Subreddit:** r/solopreneur
**Title:** [title]
**Body:**
[content — manual posting only, not in channels field]

---

## Hacker News
**Title:** [title]
**URL:** [url]
```

Note: `channels` is a comma-separated string, not a YAML list. Avoids array parsing in bash — just `grep -q "discord"` on the field value. Reddit/HN sections stay in the file for manual use but are not listed in `channels`.

### Channel-to-Section Mapping

The script needs an explicit mapping since channel names in frontmatter don't match section headings:

| Channel name | Section heading |
|---|---|
| `discord` | `## Discord` |
| `x` | `## X/Twitter Thread` |

Unknown channel names produce a warning and are skipped.

### Implementation

#### Phase 1: Migrate Content Files + Refactor Script + Update Workflow

**1a. Add YAML frontmatter to all 6 content files**

Replace existing markdown bold metadata (`**Blog post:**`, `**Title:**`, `**Publish date:** Thu 2026-03-12`) with proper YAML frontmatter. Convert dates to ISO format (`YYYY-MM-DD`). Remove the old markdown header lines. Section structure stays unchanged.

All 6 get `status: published` since they've already been distributed.

**1b. Refactor content-publisher.sh**

Delete `resolve_content()` case statement entirely. No backwards compatibility — clean break. Replace `main()` entry point with scan-based flow:

```bash
parse_frontmatter() {
  local file="$1"
  awk '/^---$/{c++; next} c==1' "$file"
}

get_frontmatter_field() {
  local file="$1" field="$2"
  parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/'
}
```

Pattern source: `plugins/soleur/hooks/stop-hook.sh:43-47`. Two functions, not three — `get_frontmatter_list()` is unnecessary.

The scan loop in `main()`:

```bash
today=$(date +%Y-%m-%d)
content_dir="knowledge-base/project/specs/feat-product-strategy/distribution-content"
failures=0

for file in "$content_dir"/*.md; do
  [[ -f "$file" ]] || continue

  status=$(get_frontmatter_field "$file" "status")
  publish_date=$(get_frontmatter_field "$file" "publish_date")
  channels=$(get_frontmatter_field "$file" "channels")

  # Skip non-scheduled or wrong date
  [[ "$status" == "scheduled" ]] || continue
  [[ "$publish_date" == "$today" ]] || continue

  # Stale content warning
  if [[ "$status" == "scheduled" && "$publish_date" < "$today" ]]; then
    echo "WARNING: Stale scheduled content: $file (publish_date: $publish_date)" >&2
    # Post stale warning to Discord general webhook
    continue
  fi

  # Publish to declared channels
  if echo "$channels" | grep -q "discord"; then
    discord_content=$(extract_section "$file" "Discord")
    [[ -n "$discord_content" ]] && post_discord "$discord_content" || ((failures++))
  fi

  if echo "$channels" | grep -q "x"; then
    post_x_thread "$file" || ((failures++))
  fi

  # Update status in-place
  sed -i 's/^status: scheduled/status: published/' "$file"

  sleep 5  # Rate limit buffer between files
done

exit $((failures > 0 ? 2 : 0))
```

**1c. Remove manual platform logic**

Delete `create_manual_issues()` and the IH/Reddit/HN manual platform logic. **Keep `create_dedup_issue()`** — it's still used by `create_x_fallback_issue()`, `create_partial_thread_issue()`, and `create_discord_fallback_issue()` for error recovery.

**1d. Update workflow YAML**

Modify `.github/workflows/scheduled-content-publisher.yml`:

1. Add daily cron trigger: `schedule: [{cron: '0 14 * * *'}]`
2. Keep `workflow_dispatch` (no inputs — script always scans)
3. Change invocation: `bash scripts/content-publisher.sh` (no args)
4. Change permissions to `contents: write` (for status update commits)
5. Add git commit + push step after publishing:

```yaml
- name: Commit status updates
  if: success() || steps.publish.outcome == 'success'
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add knowledge-base/project/specs/feat-product-strategy/distribution-content/
    git diff --cached --quiet && exit 0  # No changes = no commit
    git commit -m "ci: update content distribution status [skip ci]"
    git push
```

**Status-update-commit details:**
- **Commit message:** `ci: update content distribution status [skip ci]` — the `[skip ci]` prevents workflow recursion (push doesn't trigger another workflow run)
- **Push target:** Direct to `main`. This is bot-generated metadata (status flag), not code. Per learnings: direct push is simpler and more reliable than PR flow for fully-overwritten bot content.
- **Race condition:** If someone pushes to main between checkout and status push, the push fails. The workflow's `concurrency: cancel-in-progress: false` prevents overlapping cron runs. Manual + cron overlap is a theoretical risk but practically eliminated by the `concurrency` group name. If the push fails, content stays `scheduled` and will retry next cron run.
- **Recursion guard:** `[skip ci]` in commit message. GitHub Actions respects this for `push`-triggered workflows. The content-publisher workflow triggers on `schedule` and `workflow_dispatch`, not `push`, so it's doubly safe.

#### Phase 2: Testing

- Test scan mode with a test content file (`status: scheduled`, `publish_date: today`)
- Test idempotency: re-run after publishing — already-published files skipped
- Test draft status: `status: draft` file skipped
- Test past date: yesterday's `publish_date` with `status: scheduled` → warning + skipped
- Test missing frontmatter: file without `---` block → warning + skipped
- Test unknown channel name → warning + skipped
- Validate workflow dispatch works end-to-end

### Edge Cases

**Missed cron runs.** `publish_date` in the past with `status: scheduled` is skipped with a warning posted to Discord general webhook. Content should be manually rescheduled. This is intentional — auto-publishing stale content at an arbitrary time is worse than skipping it.

**Multiple files same date.** Processed in filesystem order (glob expansion). 5-second delay between files for Discord webhook rate limits.

**Per-file failure semantics.** Status updates are per-file via `sed -i` immediately after successful publishing. If file A succeeds and file B fails, A gets `published`, B stays `scheduled`. Overall exit code: 0 = all succeeded, 2 = partial failure.

**Invalid frontmatter.** Missing `status` or `publish_date` → warning log + skip. Empty `channels` → warning log + skip.

## Acceptance Criteria

- [ ] All 6 existing content files have YAML frontmatter with `title`, `type`, `publish_date`, `channels`, `status`
- [ ] `content-publisher.sh` parses frontmatter and scans directory for `publish_date == today` + `status: scheduled`
- [ ] `content-publisher.sh` updates `status` to `published` after successful distribution via `sed -i`
- [ ] `scheduled-content-publisher.yml` has a daily cron trigger alongside `workflow_dispatch`
- [ ] Workflow commits status changes back to main with `[skip ci]`
- [ ] `create_manual_issues()` and IH/Reddit/HN logic removed; `create_dedup_issue()` preserved for fallbacks
- [ ] Stale content (`publish_date < today`, `status: scheduled`) emits Discord warning

## Test Scenarios

- Given a content file with `publish_date: 2026-03-15` and `status: scheduled`, when the script runs on 2026-03-15, then the file is published to declared channels and status is updated to `published`
- Given a content file with `publish_date: 2026-03-14` (yesterday) and `status: scheduled`, when the script runs on 2026-03-15, then a warning is posted to Discord and the file is skipped
- Given a content file with `status: published`, when the script runs, then the file is skipped (idempotent)
- Given a content file with `status: draft`, when the script runs, then the file is skipped
- Given a content file with missing frontmatter, when the script scans, then a warning is logged and the file is skipped
- Given a content file with `channels: discord, x` but no `## X/Twitter Thread` section, then Discord posts normally and X is skipped with a warning

## Dependencies & Risks

**Dependencies:**
- Existing `x-community.sh` and Discord webhook infrastructure (stable, no changes needed)
- GitHub Actions secrets for X API credentials (already configured)

**Risks:**
- **Frontmatter parsing fragility in bash:** Mitigated by using the established `awk` counter pattern and simple flat fields. No nested YAML, no list parsing.
- **X API HTTP 402 (pay-per-use billing):** Already handled by existing fallback issue creation. `create_dedup_issue()` preserved for this.
- **Status push to main from CI:** Mitigated by `[skip ci]` commit message, `concurrency` group, and the fact that content-publisher triggers on `schedule`/`workflow_dispatch`, not `push`.
- **Cron timing:** 14:00 UTC (morning US ET/PT). Adjustable.

## Follow-Up Issues

These were scoped out during review to keep this PR focused:

1. **Social-distribute skill update** — Make it output persistent content files with `status: draft` frontmatter instead of ephemeral conversation output. Separate PR because it's an AI skill behavior change with different risks.
2. **Campaign calendar** — CMO-maintained rolling view derived from content files. Write when useful — it's a document, not a code dependency.
3. **Reddit API automation** — Deferred. Research showed 90/10 rule, domain reputation risk, and November 2025 registration changes make it high-risk. Revisit when there's an established Reddit account with organic participation.

## References & Research

### Internal References
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-12-unified-marketing-campaign-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-unified-marketing-campaign/spec.md`
- Current publisher: `scripts/content-publisher.sh` (resolve_content at case statement, extract_section at line 36)
- Workflow: `.github/workflows/scheduled-content-publisher.yml`
- Content files: `knowledge-base/project/specs/feat-product-strategy/distribution-content/*.md`
- Frontmatter parser pattern: `plugins/soleur/hooks/stop-hook.sh:43-47`
- Community scripts: `plugins/soleur/skills/community/scripts/x-community.sh`

### Institutional Learnings Applied
- Multi-platform publisher error propagation (exit code 2 for partial failure)
- X API pay-per-use billing and web fallback (HTTP 402 handling)
- awk scoping for YAML frontmatter parsing (counter pattern, not sed ranges)
- Shell API wrapper hardening (5-layer defense)
- `set -euo pipefail` upgrade pitfalls (bare positional refs, grep-in-pipeline)
- Discord allowed mentions sanitization (`allowed_mentions: {parse: []}`)
- GitHub Actions auto-push vs PR for bot content (direct push for bot metadata)

### Related Work
- Issue: #549
- PR: #556 (draft)
- Current campaign plan: `knowledge-base/project/specs/feat-product-strategy/distribution-plan.md`
