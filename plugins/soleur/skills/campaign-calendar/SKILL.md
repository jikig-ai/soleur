---
name: campaign-calendar
description: "This skill should be used when generating or refreshing the rolling campaign calendar. Scans knowledge-base/marketing/distribution-content/ markdown frontmatter, groups by status (overdue/upcoming/draft/published), writes a calendar view."
---

# Campaign Calendar

Generate a rolling campaign calendar by scanning `knowledge-base/marketing/distribution-content/*.md` files and grouping them by status. Replaces the fixed distribution plan that expires with no rollover.

## Arguments

`$ARGUMENTS` is parsed for optional flags:

```text
campaign-calendar [--headless] [--stale-days <N>]
```

If `$ARGUMENTS` contains `--headless`, set `HEADLESS=true`. This skill has no interactive prompts, so `--headless` is a no-op for convention compliance.

`--stale-days <N>` sets the draft-staleness threshold for the "Stale Draft" group (default 7).

## Execution

### Phase 1: Scan Content Files

1. Glob `knowledge-base/marketing/distribution-content/*.md` to find all content files.

2. If zero files are found, write a calendar with the empty state message (see Phase 3) and skip to Phase 4.

3. For each file found, read the file and extract YAML frontmatter fields:
   - `title` (string)
   - `type` (string: case-study, pillar, announcement)
   - `publish_date` (YYYY-MM-DD)
   - `channels` (comma-separated string)
   - `status` (draft, scheduled, published)

4. If a file has no YAML frontmatter delimiters (`---`), skip it and note: "Skipped [filename]: no frontmatter found."

5. If a file has frontmatter but is missing required fields (`title`, `status`), include it with "unknown" for missing values.

### Phase 2: Classify Entries

Classify each content file into one of five groups using `status`, `publish_date`, and draft age:

| Group | Condition | Sort Order |
|-------|-----------|------------|
| **Overdue** | `status: scheduled` AND `publish_date < today` | Oldest first (most overdue at top) |
| **Upcoming** | `status: scheduled` AND `publish_date >= today` | Soonest first |
| **Stale Draft — needs approval** | `status: draft` AND draft age > N days (default N=7) | Oldest first (most stale at top) |
| **Draft** | `status: draft` AND draft age ≤ N days | Alphabetical by title |
| **Published** | `status: published` | Most recent `publish_date` first |

Today's date: use the current date at execution time.

**Why a distinct stale group:** `content-publisher.sh` skips any file whose
`status != scheduled` *before* its stale-sweep, so a `draft` never ages out and
never alerts — an un-approved draft strands silently forever. This group is the
only cadence signal for that class (e.g. a `feature-tweet` ship draft the
operator never flipped to `scheduled`).

**Draft age:** derive from the leading `YYYY-MM-DD` in the filename
(`<YYYY-MM-DD>-<slug>.md`, the `feature-tweet` naming) when present; otherwise
from the file's git first-commit date (`git log --diff-filter=A --format=%cs -1
-- <file>`), falling back to filesystem mtime. `age_days = today − that_date`.
N defaults to 7; override via the `--stale-days <N>` argument.

### Phase 3: Generate Calendar Markdown

Write the calendar to `knowledge-base/marketing/campaign-calendar.md` with this structure:

```markdown
---
last_updated: YYYY-MM-DD
---

# Campaign Calendar

Rolling view of content distributions. Auto-generated from `distribution-content/` frontmatter.

## Overdue

> These items have a scheduled publish date in the past but have not been published.

| Title | Type | Publish Date | Channels | Status |
|-------|------|-------------|----------|--------|
| ... | ... | ... | ... | scheduled |

## Upcoming

| Title | Type | Publish Date | Channels | Status |
|-------|------|-------------|----------|--------|
| ... | ... | ... | ... | scheduled |

## Stale Draft — needs approval

> Drafts older than N days (default 7) still awaiting operator approval. The
> publisher never ages these out — flip `publish_date` + `status: scheduled` to
> release, or delete if abandoned.

| Title | Type | Age (days) | Channels | Status |
|-------|------|-----------|----------|--------|
| ... | ... | ... | ... | draft |

## Draft

| Title | Type | Publish Date | Channels | Status |
|-------|------|-------------|----------|--------|
| ... | ... | ... | ... | draft |

## Published

| Title | Type | Publish Date | Channels | Status |
|-------|------|-------------|----------|--------|
| ... | ... | ... | ... | published |
```

**Rules:**
- Omit any section that has zero entries (do not show empty tables).
- If zero files were found in Phase 1, write: `No content files found in distribution-content/.`
- The `last_updated` frontmatter field uses today's date in YYYY-MM-DD format.
- If the Overdue section has entries, add a blockquote warning above its table.

### Phase 4: Write and Report

1. Write the generated markdown to `knowledge-base/marketing/campaign-calendar.md`.

2. **If running in CI** (detected by the presence of `GITHUB_ACTIONS` environment variable or if the workflow prompt includes commit instructions):

   Run these commands to persist the calendar:

   ```bash
   git add knowledge-base/marketing/campaign-calendar.md
   git diff --cached --quiet && echo "Calendar unchanged, skipping commit." && exit 0
   git commit -m "ci: update campaign calendar [skip ci]"
   git push origin main || { git pull --rebase origin main && git push origin main; }
   ```

3. **If running manually** (no CI environment detected):

   Print: "Calendar written to `knowledge-base/marketing/campaign-calendar.md`. To persist, run: `gh workflow run scheduled-campaign-calendar.yml`"
