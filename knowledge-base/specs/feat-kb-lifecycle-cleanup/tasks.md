# Tasks: feat-kb-lifecycle-cleanup

## Phase 1: Core Implementation - Consolidation Step in compound-docs Skill

- [x] 1.1 Add decision menu option to `plugins/soleur/skills/compound-docs/SKILL.md`
  - [x] 1.1.1 Insert "Consolidate & archive KB artifacts" at position 2 (after "Continue workflow")
  - [x] 1.1.2 Renumber existing options (old 2-7 become 3-8, "Other" stays last)
  - [x] 1.1.3 Gate visibility on `feat-*` branch detection

- [x] 1.2 Add artifact discovery logic
  - [x] 1.2.1 Document branch-name glob: extract `<slug>` from `feat-<slug>`, glob brainstorms/plans/specs
  - [x] 1.2.2 Document skip logic for `*/archive/` directories
  - [x] 1.2.3 Document user confirmation of discovered list + manual file addition option
  - [x] 1.2.4 Document no-artifacts-found handling (notify and return to menu)

- [x] 1.3 Add extraction and approval flow
  - [x] 1.3.1 Document single-agent extraction: reads artifacts, proposes updates to constitution, components, overview
  - [x] 1.3.2 Document one-at-a-time approval (Accept/Skip/Edit per proposal)
  - [x] 1.3.3 Document Edit flow (user provides corrected text, re-shown for Accept/Skip)
  - [x] 1.3.4 Document idempotency: simple substring check, flag for user decision if similar exists
  - [x] 1.3.5 Document immediate application of accepted proposals

- [x] 1.4 Add archival logic
  - [x] 1.4.1 Document archive directory creation (`mkdir -p` on first use)
  - [x] 1.4.2 Document `git mv` with `YYYYMMDD-HHMMSS` timestamp prefix
  - [x] 1.4.3 Document spec directory archival (move entire `feat-<slug>/` dir)
  - [x] 1.4.4 Document `git mv` failure handling (`git add` first, then retry)
  - [x] 1.4.5 Document context-aware archival confirmation (different message when all proposals skipped)
  - [x] 1.4.6 Document archival is independent of extraction approvals
  - [x] 1.4.7 Document single commit for all changes (overview edits + archival moves)

## Phase 2: Integration - compound Command

- [x] 2.1 Update `plugins/soleur/commands/soleur/compound.md`
  - [x] 2.1.1 Add reference to new menu option
  - [x] 2.1.2 Update flow description to mention consolidation step

## Phase 3: Versioning & Documentation

- [x] 3.1 Bump plugin version (MINOR)
  - [x] 3.1.1 Update `plugins/soleur/.claude-plugin/plugin.json` version
  - [x] 3.1.2 Add entry to `plugins/soleur/CHANGELOG.md`
  - [x] 3.1.3 Verify counts in `plugins/soleur/README.md`

## Phase 4: Testing

- [x] 4.1 Validation
  - [x] 4.1.1 Run `bun test` to ensure no regressions
  - [x] 4.1.2 Verify markdown files pass linting
  - [x] 4.1.3 Verify decision menu option text and numbering is correct
