# Tasks: Unified Marketing Campaign Plan

## Phase 1: Migrate Content Files + Refactor Script + Update Workflow

### Content Migration

- [x] 1.1 Replace markdown metadata with YAML frontmatter in `01-legal-document-generation.md` (type: case-study, channels: discord, x, status: published, publish_date in ISO format)
- [x] 1.2 Replace markdown metadata with YAML frontmatter in `02-operations-management.md`
- [x] 1.3 Replace markdown metadata with YAML frontmatter in `03-competitive-intelligence.md`
- [x] 1.4 Replace markdown metadata with YAML frontmatter in `04-brand-guide-creation.md`
- [x] 1.5 Replace markdown metadata with YAML frontmatter in `05-business-validation.md`
- [x] 1.6 Replace markdown metadata with YAML frontmatter in `06-why-most-agentic-tools-plateau.md` (type: pillar)

### Script Refactoring

- [x] 1.7 Add `parse_frontmatter()` and `get_frontmatter_field()` to `content-publisher.sh` using awk counter pattern
- [x] 1.8 Replace `resolve_content()` and `main()` with scan loop: iterate `distribution-content/*.md`, filter by `publish_date == today` + `status: scheduled`, publish to channels via grep on frontmatter, update status via `sed -i`
- [x] 1.9 Add stale content warning: if `publish_date < today` and `status: scheduled`, post warning to Discord general webhook
- [x] 1.10 Add channel-to-section mapping (`x` → `X/Twitter Thread`, `discord` → `Discord`) with unknown channel warning
- [x] 1.11 Remove `create_manual_issues()` and IH/Reddit/HN manual platform logic. Keep `create_dedup_issue()` for X/Discord fallbacks.

### Workflow Update

- [x] 1.12 Add `schedule: [{cron: '0 14 * * *'}]` to `scheduled-content-publisher.yml`
- [x] 1.13 Remove `case_study` choice input; keep `workflow_dispatch` with no inputs
- [x] 1.14 Change invocation to `bash scripts/content-publisher.sh` (no args)
- [x] 1.15 Change permissions to `contents: write`
- [x] 1.16 Add git commit + push step for status updates (`ci: update content distribution status [skip ci]`)

## Phase 2: Testing

- [x] 2.1 Test scan mode with test content file (`status: scheduled`, `publish_date: today`)
- [x] 2.2 Test idempotency: re-run after publishing — published files skipped
- [x] 2.3 Test draft status: `status: draft` file skipped
- [x] 2.4 Test stale date: yesterday's `publish_date` + `status: scheduled` → Discord warning + skip
- [x] 2.5 Test missing frontmatter: file without `---` → warning + skip
- [x] 2.6 Test unknown channel name → warning + skip
- [x] 2.7 Validate workflow dispatch end-to-end
