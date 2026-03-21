# Tasks: feat-social-distribute-persistent

## Phase 1: SKILL.md Modification

### 1.1 Remove Distribution Pipeline Gate

- [ ] Delete the `## Distribution Pipeline Gate` section from `plugins/soleur/skills/social-distribute/SKILL.md`

### 1.2 Add File-Writing Phase (Phase 8 rewrite)

- [ ] Replace current Phase 8 (Discord webhook posting) with content file writing logic
- [ ] Implement slug derivation from blog post filename
- [ ] Construct output path: `knowledge-base/marketing/distribution-content/<slug>.md`
- [ ] Add existence check with overwrite/skip prompt via AskUserQuestion
- [ ] Define file template with YAML frontmatter (`title`, `type`, `publish_date`, `channels`, `status: draft`)
- [ ] Define section structure matching existing content files (Discord, X/Twitter Thread, IndieHackers, Reddit, Hacker News with `---` separators)

### 1.3 Update Discord Approval Flow (Phase 7 integration)

- [ ] If Discord posted successfully via webhook, set `channels: x` in written file
- [ ] If Discord skipped or no webhook configured, set `channels: discord, x` in written file

### 1.4 Rewrite Phase 9 (Confirmation & Next Steps)

- [ ] Replace manual platform output with file confirmation message
- [ ] Include file path, status, and next-step instructions (review, set publish_date, change status to scheduled)

### 1.5 Simplify Phase 10 (Summary)

- [ ] Update distribution summary to reflect file-based flow instead of ephemeral output

## Phase 2: Testing

### 2.1 Manual Validation

- [ ] Run social-distribute against an existing blog post, verify content file is written correctly
- [ ] Verify YAML frontmatter matches expected format (`title`, `type`, `publish_date`, `channels`, `status: draft`)
- [ ] Verify all 5 platform sections present with correct headings
- [ ] Verify file format matches existing content files (section separators, tweet label format)
- [ ] Verify overwrite prompt appears when content file already exists
- [ ] Verify Discord approval flow correctly adjusts `channels` field

### 2.2 Integration Validation

- [ ] Verify written content file is parseable by `content-publisher.sh` (frontmatter extraction, section extraction)
- [ ] Verify `content-publisher.sh` can publish from a skill-generated file when status is set to `scheduled`

## Phase 3: Commit & Ship

### 3.1 Commit

- [ ] Run compound
- [ ] Commit SKILL.md changes
- [ ] Push and create PR referencing #557
