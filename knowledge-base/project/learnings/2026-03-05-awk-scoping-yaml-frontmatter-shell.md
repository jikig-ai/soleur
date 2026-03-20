# Learning: awk scoping for YAML frontmatter parsing in shell scripts

## Problem

`plugins/soleur/hooks/stop-hook.sh` used `sed` to extract and update YAML frontmatter in Ralph state files. The file format is YAML frontmatter delimited by `---` lines, followed by a freeform prompt body. Two bugs resulted:

1. **Extraction leak:** `sed -n '/^---$/,/^---$/...'` matched ALL `---`-delimited blocks, not just the first one. If the prompt body contained a bare `---` line (e.g., as a Markdown horizontal rule), content after it leaked into the `FRONTMATTER` variable, corrupting parsed values.

2. **Global substitution bleed:** `sed -e "s/^iteration: .*/..."` replaced patterns anywhere in the file. Prompt body text like `iteration: check status` was silently mutated.

Both bugs stem from the same root cause: `sed` range patterns and global substitutions have no concept of "first block only."

## Solution

Replaced both `sed` operations with `awk` using a counter variable `c` that increments on each `---` delimiter line. Only lines where `c==1` (between the first and second `---`) are treated as frontmatter.

**Extraction:** `awk '/^---$/{c++; next} c==1'`

**Update pass:**
```bash
awk -v iter="$NEXT_ITERATION" -v sc="$STUCK_COUNT" '
  /^---$/ { c++; print; next }
  c==1 && /^iteration:/ { print "iteration: " iter; next }
  c==1 && /^stuck_count:/ { print "stuck_count: " sc; next }
  { print }
' "$RALPH_STATE_FILE" > "$TEMP_FILE"
```

## Key Insight

`sed` range expressions (`/start/,/stop/`) match every occurrence of the start/stop pair, not just the first. For file formats that use the same delimiter to mark a single block (like YAML frontmatter's `---`), `awk` with an explicit counter is the correct tool. The pattern `'/^---$/{c++; next} c==1'` is a reliable idiom for "extract only the first `---`-delimited block" and should be the default choice over `sed` for frontmatter parsing in shell scripts.

## Session Errors

Test 13 initially asserted that a bare `---` line in the prompt body would appear in the awk-extracted prompt. However, the existing prompt extractor (line 133: `awk '/^---$/{i++; next} i>=2'`) also consumes `---` lines. The test was corrected to verify against the raw state file instead.

## Related

- `knowledge-base/project/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- `knowledge-base/project/learnings/2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`
- `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`

## Tags
category: logic-errors
module: ralph-loop
