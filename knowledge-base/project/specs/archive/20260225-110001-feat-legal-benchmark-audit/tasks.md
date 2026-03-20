# Tasks: Legal Benchmark Audit Mode

Plan: `knowledge-base/plans/2026-02-25-feat-legal-benchmark-audit-plan.md`
Issue: #303

## Phase 1: Agent Extension

- [x] 1.1 Add `### 4. Regulatory Benchmark Mode` section to `plugins/soleur/agents/legal/legal-compliance-auditor.md`
  - [x] 1.1.1 Define "benchmark mode" trigger phrase recognition
  - [x] 1.1.2 Add GDPR Art 13/14 enumerated disclosure checklist
  - [x] 1.1.3 Define `[REGULATORY]` finding format prefix
- [x] 1.2 Add `### 5. Peer Comparison Mode` section
  - [x] 1.2.1 Add curated peer URL table (3 fetchable URLs: Basecamp Terms, Basecamp Privacy, GitHub AUP)
  - [x] 1.2.2 Define WebFetch failure handling (SKIPPED findings)
  - [x] 1.2.3 Define `[PEER:<name>]` finding format prefix
  - [x] 1.2.4 Define skip behavior for document types with no peer equivalent
  - [x] 1.2.5 Add benchmark summary line to standard summary (GDPR disclosure coverage + peer stats)

## Phase 2: Skill Extension

- [x] 2.1 Add benchmark conditional to Phase 2 in `plugins/soleur/skills/legal-audit/SKILL.md` (if "benchmark" in input, append trigger to Task prompt)
- [x] 2.2 Update skill `description:` frontmatter with benchmark trigger phrases
- [x] 2.3 Verify standard audit path unchanged when no sub-command (FR6)

## Phase 3: CLO Update

- [x] 3.1 Update delegation table in `plugins/soleur/agents/legal/clo.md` to mention benchmark mode

## Phase 4: Version Bump

- [x] 4.1 Bump `plugins/soleur/.claude-plugin/plugin.json` to 3.3.0
- [x] 4.2 Add `[3.3.0]` entry to `plugins/soleur/CHANGELOG.md`
- [x] 4.3 Verify `plugins/soleur/README.md` counts unchanged (no new agents/skills)
- [x] 4.4 Update root `README.md` version badge to 3.3.0
- [x] 4.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder to 3.3.0
- [x] 4.6 Verify `plugin.json` description string matches current counts

## Phase 5: Validation

- [x] 5.1 Verify agent description word count still under budget
- [x] 5.2 Run `legal-audit` (no sub-command) to confirm standard audit unchanged
- [x] 5.3 Run `legal-audit benchmark` to confirm benchmark mode works end-to-end
