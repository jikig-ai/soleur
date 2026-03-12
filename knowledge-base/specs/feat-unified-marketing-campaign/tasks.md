# Tasks: Unified Marketing Campaign Plan

## Phase 1: Migrate Content Files + Refactor Script + Update Workflow

### Content Migration

- [ ] 1.1 Replace markdown metadata with YAML frontmatter in `01-legal-document-generation.md` (type: case-study, channels: discord, x, status: published, publish_date in ISO format)
- [ ] 1.2 Replace markdown metadata with YAML frontmatter in `02-operations-management.md`
- [ ] 1.3 Replace markdown metadata with YAML frontmatter in `03-competitive-intelligence.md`
- [ ] 1.4 Replace markdown metadata with YAML frontmatter in `04-brand-guide-creation.md`
- [ ] 1.5 Replace markdown metadata with YAML frontmatter in `05-business-validation.md`
- [ ] 1.6 Replace markdown metadata with YAML frontmatter in `06-why-most-agentic-tools-plateau.md` (type: pillar)

### Script Refactoring

- [ ] 1.7 Add `parse_frontmatter()` and `get_frontmatter_field()` to `content-publisher.sh` using awk counter pattern
- [ ] 1.8 Replace `resolve_content()` and `main()` with scan loop: iterate `distribution-content/*.md`, filter by `publish_date == today` + `status: scheduled`, publish to channels via grep on frontmatter, update status via `sed -i`
- [ ] 1.9 Add stale content warning: if `publish_date < today` and `status: scheduled`, post warning to Discord general webhook
- [ ] 1.10 Add channel-to-section mapping (`x` → `X/Twitter Thread`, `discord` → `Discord`) with unknown channel warning
- [ ] 1.11 Remove `create_manual_issues()` and IH/Reddit/HN manual platform logic. Keep `create_dedup_issue()` for X/Discord fallbacks.

### Workflow Update

- [ ] 1.12 Add `schedule: [{cron: '0 14 * * *'}]` to `scheduled-content-publisher.yml`
- [ ] 1.13 Remove `case_study` choice input; keep `workflow_dispatch` with no inputs
- [ ] 1.14 Change invocation to `bash scripts/content-publisher.sh` (no args)
- [ ] 1.15 Change permissions to `contents: write`
- [ ] 1.16 Add git commit + push step for status updates (`ci: update content distribution status [skip ci]`)

## Phase 2: Testing

- [ ] 2.1 Test scan mode with test content file (`status: scheduled`, `publish_date: today`)
- [ ] 2.2 Test idempotency: re-run after publishing — published files skipped
- [ ] 2.3 Test draft status: `status: draft` file skipped
- [ ] 2.4 Test stale date: yesterday's `publish_date` + `status: scheduled` → Discord warning + skip
- [ ] 2.5 Test missing frontmatter: file without `---` → warning + skip
- [ ] 2.6 Test unknown channel name → warning + skip
- [ ] 2.7 Validate workflow dispatch end-to-end
