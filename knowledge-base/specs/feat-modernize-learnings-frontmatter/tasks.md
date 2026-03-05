# Tasks: modernize learnings corpus YAML frontmatter

## Phase 1: Setup

- [ ] 1.1 Audit current state: count files by frontmatter status (none, partial, complete)
- [ ] 1.2 Build category taxonomy from existing 43 frontmatter files + filename patterns
- [ ] 1.3 Determine creation date for `agent-prompt-sharp-edges-only.md` via `git log`

## Phase 2: Core Implementation

- [ ] 2.1 Write `scripts/backfill-frontmatter.sh` migration script
  - [ ] 2.1.1 Parse inline bold metadata (`**Date:**`, `**Tags:**`, `**Issues:**`)
  - [ ] 2.1.2 Extract title from first `# Heading` line
  - [ ] 2.1.3 Infer category from filename slug using pattern matching
  - [ ] 2.1.4 Generate YAML frontmatter block with required fields
  - [ ] 2.1.5 Prepend frontmatter to files without it
  - [ ] 2.1.6 Augment existing partial frontmatter with missing required fields
  - [ ] 2.1.7 Normalize `symptom:` (singular) to `symptoms:` (array)
  - [ ] 2.1.8 Handle inline metadata cleanup (remove duplicated bold fields)
- [ ] 2.2 Rename `agent-prompt-sharp-edges-only.md` with date prefix using `git mv`
- [ ] 2.3 Run migration script on all 138 files
- [ ] 2.4 Manual review: spot-check 10-15 files across different categories for correctness

## Phase 3: Testing & Validation

- [ ] 3.1 Validate all files have 4 required frontmatter fields (`title`, `date`, `category`, `tags`)
- [ ] 3.2 Verify no content below frontmatter was modified (diff audit)
- [ ] 3.3 Run markdownlint on all modified files
- [ ] 3.4 Run `bun test` to verify no test regressions
- [ ] 3.5 Check category distribution (target: 10-15 distinct values)
