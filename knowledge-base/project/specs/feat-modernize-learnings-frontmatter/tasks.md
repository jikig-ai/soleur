# Tasks: modernize learnings corpus YAML frontmatter

## Phase 1: Setup

- [ ] 1.1 Audit current state: count files by frontmatter status (none, partial, complete)
- [ ] 1.2 Build category taxonomy from existing 43 frontmatter files + filename patterns
- [ ] 1.3 Determine creation date for `agent-prompt-sharp-edges-only.md` via `git log --follow --diff-filter=A`
- [ ] 1.4 Verify `grep -oE` works for date extraction (POSIX ERE, not PCRE)

## Phase 2: Core Implementation

- [ ] 2.1 Write `scripts/backfill-frontmatter.sh` migration script
  - [ ] 2.1.1 Parse inline bold metadata (`**Date:**`, `**Tags:**`, `**Issues:**`) with variant formatting
  - [ ] 2.1.2 Extract title from first `# Heading` line, strip `Learning:` / `Learnings:` / `Troubleshooting:` prefixes
  - [ ] 2.1.3 Infer category from filename slug using priority-ordered `case` patterns (most specific first)
  - [ ] 2.1.4 Generate YAML frontmatter block with required fields (`title`, `date`, `category`, `tags`)
  - [ ] 2.1.5 Prepend frontmatter to files without it (85 files)
  - [ ] 2.1.6 Augment existing partial frontmatter with missing required fields (10 files)
  - [ ] 2.1.7 Normalize `symptom:` (singular) to `symptoms:` (array)
  - [ ] 2.1.8 Preserve existing `synced_to`, CORA-specific fields, and `last_reviewed`/`review_cadence` fields
  - [ ] 2.1.9 Guard all `grep` calls with `|| true` for `set -euo pipefail` compatibility
  - [ ] 2.1.10 Use `${var:-}` defaults for optional function parameters under `set -u`
- [ ] 2.2 Rename `agent-prompt-sharp-edges-only.md` with date prefix using `git add` then `git mv`
- [ ] 2.3 Run migration script on all 138 files
- [ ] 2.4 Write `scripts/verify-frontmatter.sh` validation script
- [ ] 2.5 Manual review: spot-check 10-15 files across different categories for correctness

## Phase 3: Testing & Validation

- [ ] 3.1 Run `scripts/verify-frontmatter.sh` -- all files have 4 required frontmatter fields
- [ ] 3.2 Verify no content below frontmatter was modified (body hash comparison or diff audit)
- [ ] 3.3 Run idempotency check: execute script twice, confirm no diff on second run
- [ ] 3.4 Run markdownlint on all modified files
- [ ] 3.5 Run `bun test` to verify no test regressions
- [ ] 3.6 Check category distribution (target: 10-15 distinct values, no category with <3 or >25 files)
- [ ] 3.7 Run post-run verification: `grep -rL '^---' knowledge-base/project/learnings/*.md` returns 0 files
