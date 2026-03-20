---
title: "Directory-Driven Content Discovery with Frontmatter Parsing in Bash"
date: 2026-03-12
category: integration-issues
tags: [bash, yaml-frontmatter, github-actions, content-publisher, set-euo-pipefail]
module: scripts/content-publisher.sh
---

# Learning: Directory-Driven Content Discovery with Frontmatter Parsing in Bash

## Problem

The content publisher (`scripts/content-publisher.sh`) used a hardcoded `resolve_content()` case statement to map study numbers (1-5) to filenames, display names, and manual platform lists. Adding new content required editing the script in three places: the case statement, the manual platform mapping, and the workflow dispatch input choices. The workflow also required a `study_number` input, making it impossible to run as a zero-argument daily cron job.

This multi-file registration pattern does not scale. Every new content file required coordinated changes across the shell script, the GitHub Actions workflow YAML, and the content file itself.

## Solution

Replaced the case-statement registry with directory-driven content discovery using YAML frontmatter:

1. **Migrated 6 content files** from markdown bold metadata (`**Publish Date:** ...`) to YAML frontmatter with structured fields: `title`, `type`, `publish_date`, `channels`, `status`.

2. **Added frontmatter parsing functions** to `content-publisher.sh`:
   - `parse_frontmatter()` using the awk counter pattern: `awk '/^---$/{c++; next} c==1'` to extract the YAML block between the two `---` delimiters.
   - `get_frontmatter_field()` to extract a named field value from the frontmatter, with `|| true` to guard against grep exit 1 on no match.

3. **Replaced the case statement** with a scan loop that iterates over `$CONTENT_DIR/*.md`, filters by `publish_date == today` and `status: scheduled`, publishes to channels declared in frontmatter, and updates status to `published` via `sed -i`.

4. **Added channel-to-section mapping** (`channel_to_section()`) so frontmatter `channels: discord, x` maps to the correct `## Discord` and `## X/Twitter Thread` section headings in the content file.

5. **Added stale content warning**: files with `status: scheduled` but `publish_date` in the past trigger a Discord warning instead of silently being ignored.

6. **Updated the workflow**: added daily cron (`0 14 * * *`), removed the `study_number` choice input, changed to no-args invocation, added `contents: write` permission, and added a git commit+push step for status updates.

Now adding content is a single operation: drop a `.md` file in `distribution-content/` with the right frontmatter. No script changes, no workflow changes.

## Key Insight

The awk counter pattern (`/^---$/{c++; next} c==1`) is a reliable, dependency-free way to parse YAML frontmatter in bash. It counts `---` delimiters and emits lines only when the counter equals 1 (inside the first frontmatter block). Combined with grep and sed for field extraction, this eliminates the need for external YAML parsers while remaining robust against content that contains `---` horizontal rules outside the frontmatter.

More broadly, directory-driven content discovery (drop a file, declare metadata in frontmatter) eliminates the multi-file registration anti-pattern. The script becomes a generic scanner rather than a registry of known content.

## Session Errors

### 1. Channel parsing collapsed multi-value strings

**Bug:** The channel parsing pipeline `tr ',' ' ' | tr -d ' '` was intended to split `"discord, x"` into separate tokens. Instead, `tr -d ' '` removed all spaces including the delimiter, producing `"discordx"` as a single token.

**Root cause:** `tr -d ' '` is a global character deletion, not a trim. When used after `tr ',' ' '`, it collapses all tokens into one contiguous string.

**Fix:** Replaced the pipeline with `echo "$channels" | tr ',' '\n'` fed into a `while IFS= read -r channel` loop, with `xargs` to trim whitespace per token.

```bash
# Before (broken):
for channel in $(echo "$channels" | tr ',' ' ' | tr -d ' '); do

# After (correct):
while IFS= read -r channel; do
  channel=$(echo "$channel" | xargs)
  [[ -z "$channel" ]] && continue
  # ...
done < <(echo "$channels" | tr ',' '\n')
```

### 2. Arithmetic under set -euo pipefail exits on zero

**Bug:** `((published++))` when `published=0` caused an immediate script exit under `set -euo pipefail`. The `(( ))` arithmetic evaluation returns exit code 1 when the result is 0 (falsy in bash arithmetic), and `set -e` treats that as a failure.

**Root cause:** In bash, `((expr))` returns exit 0 when the expression evaluates to non-zero, and exit 1 when it evaluates to zero. The post-increment `((published++))` evaluates to the *pre-increment* value (0 when `published=0`), so the first increment always fails under `set -e`.

**Fix:** Replaced all `((var++))` with `var=$((var + 1))`, which is a variable assignment (always exit 0) rather than an arithmetic evaluation.

```bash
# Before (fails when published=0):
((published++))

# After (always succeeds):
published=$((published + 1))
```

### 3. grep in pipeline propagates exit 1 through pipefail

**Bug:** `get_frontmatter_field()` used `parse_frontmatter "$file" | grep "^${field}:" | sed ...` to extract a field. When the field did not exist in a file's frontmatter, `grep` returned exit 1 (no match), and `set -o pipefail` propagated that exit code through the pipeline, causing the script to abort.

**Root cause:** `pipefail` sets the pipeline's exit status to the rightmost non-zero exit code. `grep` returns 1 on "no match" (distinct from 2 on error), but pipefail does not distinguish between "no match" and "error."

**Fix:** Appended `|| true` to the pipeline so a no-match grep does not propagate failure.

```bash
# Before (aborts on missing field):
parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//"

# After (returns empty string on missing field):
parse_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/' || true
```

### 4. Plan logic bug: stale content check was unreachable

**Bug:** The scan loop checked for stale content (scheduled files with `publish_date` in the past) *after* the `[[ "$publish_date" == "$today" ]] || continue` guard. Files with past dates hit the `continue` first and never reached the stale check.

**Root cause:** The plan ordered checks as: skip non-scheduled, skip non-today, then check stale. But "non-today" includes both future *and* past dates, so the stale check was dead code.

**Fix:** Reordered the logic to: skip non-scheduled, check stale (past dates), skip non-today (future dates), then publish.

```bash
# Correct ordering:
[[ "$status" == "scheduled" ]] || continue   # 1. Skip non-scheduled
if [[ "$publish_date" < "$today" ]]; then     # 2. Stale: past date
  post_discord_warning "..."
  continue
fi
[[ "$publish_date" == "$today" ]] || continue # 3. Skip future
# 4. Publish
```

## Prevention

1. **Audit `set -euo pipefail` scripts for three vectors**: bare arithmetic expressions that can evaluate to 0, grep in pipelines that can match nothing, and unset positional parameters. These are the three most common silent-exit traps. Run `grep -n '((' script.sh` and `grep -n 'grep.*|' script.sh` as a pre-commit check.

2. **Test string-splitting logic with multi-value inputs containing whitespace.** The `tr` family of commands operates on characters, not tokens. When splitting delimited strings, prefer `tr ',' '\n'` with a `while read` loop over `tr` chains that combine substitution and deletion.

3. **Verify control flow ordering in scan loops.** When a loop has multiple `continue` guards, trace each file category (past, today, future, draft, scheduled) through the guards to confirm each reaches the intended handler. Early `continue` statements can shadow later checks.

4. **Prefer directory-driven discovery over case-statement registries.** When the pattern is "for each item, do X based on metadata," the metadata belongs in the item (frontmatter), not in the orchestrator (case statement). This eliminates the coordination cost of multi-file registration.

## Tags
category: integration-issues
module: scripts/content-publisher.sh
