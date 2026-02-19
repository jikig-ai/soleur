# Tasks: Functional Overlap Detection

**Plan:** `knowledge-base/plans/2026-02-19-feat-functional-overlap-detection-plan.md`
**Issue:** #155
**Branch:** feat-functional-overlap-check

## Phase 1: Functional-Discovery Agent

- [x] 1.1 Create `plugins/soleur/agents/engineering/discovery/functional-discovery.md`
  - [x] 1.1.1 Write YAML frontmatter: name, description (third person), model: inherit
  - [x] 1.1.2 Write example block with user/assistant/commentary dialogue (follow agent-finder format)
  - [x] 1.1.3 Write Input section: feature_description from spawning command
  - [x] 1.1.4 Write Step 1: Query registries (inline curl x3, 5s timeout, parallel)
  - [x] 1.1.5 Write Step 2: Trust filtering (3-tier model, copy from agent-finder)
  - [x] 1.1.6 Write Step 3: Deduplication (name + author, case-insensitive)
  - [x] 1.1.7 Write Step 4: Already-installed check (scan community dirs)
  - [x] 1.1.8 Write Step 5: Present results (AskUserQuestion multiSelect, max 5)
  - [x] 1.1.9 Write Step 6: Install approved (fetch, validate, provenance, write)
  - [x] 1.1.10 Write Step 7: Report summary
  - [x] 1.1.11 Write Error Handling section (copy patterns from agent-finder)

## Phase 2: Plan Command Integration

- [x] 2.1 Add Phase 1.5b to `plugins/soleur/commands/soleur/plan.md`
  - [x] 2.1.1 Insert after existing Phase 1.5 (stack-gap check), before Phase 1.6
  - [x] 2.1.2 Extract feature_description, spawn functional-discovery agent
  - [x] 2.1.3 Handle results: installed -> announce, skipped/zero/failed -> continue silently

## Phase 3: Version Bump and Documentation

- [x] 3.1 Read current version from `plugins/soleur/.claude-plugin/plugin.json`
- [x] 3.2 MINOR bump version in `plugin.json`
- [x] 3.3 Update `plugins/soleur/CHANGELOG.md` with new entry
- [x] 3.4 Update `plugins/soleur/README.md` agent count and table
- [x] 3.5 Update root `README.md` version badge
- [x] 3.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [x] 3.7 Verify `plugin.json` description matches updated component counts
