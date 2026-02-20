---
feature: feat-semgrep-sast
plan: knowledge-base/plans/2026-02-20-feat-semgrep-sast-coverage-plan.md
issue: "#163"
---

# Tasks: Layer semgrep alongside security-sentinel

## Phase 1: Core Implementation

- [ ] 1.1 Create `plugins/soleur/agents/engineering/review/semgrep-sast.md` agent file
  - YAML frontmatter: name, description (with examples), model: inherit
  - Agent prompt: check semgrep installed, get changed files, run semgrep, format findings
  - Graceful degradation when CLI missing
  - Inline-only output (never write findings to files)

- [ ] 1.2 Update `plugins/soleur/commands/soleur/review.md`
  - Add semgrep-sast to `<conditional_agents>` block
  - Condition: `which semgrep` succeeds
  - Follow existing conditional agent format (heading, task, when-to-run, what-it-checks)

## Phase 2: Documentation and Versioning

- [ ] 2.1 Update `plugins/soleur/README.md`
  - Add semgrep-sast row to agents table
  - Update agent count (33 -> 34)
  - Document security-sentinel vs semgrep-sast roles

- [ ] 2.2 Version bump
  - `plugins/soleur/.claude-plugin/plugin.json`: 2.19.0 -> 2.20.0, update agent count in description
  - `plugins/soleur/CHANGELOG.md`: Add v2.20.0 entry
  - Root `README.md`: Update version badge
  - `.github/ISSUE_TEMPLATE/bug_report.yml`: Update version placeholder
