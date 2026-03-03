# Tasks: Parallel Agent Lifecycle Orchestration (Tier 0)

## Phase 1: Core Protocol Document

### 1.1 Create work-lifecycle-parallelism.md reference file
- **File:** `plugins/soleur/skills/work/references/work-lifecycle-parallelism.md`
- Follow the existing reference file pattern (work-agent-teams.md, work-subagent-fanout.md)
- Include 6 steps: Offer/Auto-select, Generate Contract, Spawn Agents, Collect Results, Integration, Failure Handling
- Each step must include: heading with step number, description, code/prompt examples, fallthrough semantics
- No halt language ("stop", "announce", "tell the user") -- use "return control" / "proceed to next step"
- Include the interface contract heading-level schema (Module Map, Agent Scopes, Public Interfaces, Data Flow, Usage Examples)
- Include agent prompt templates for all 3 agents with explicit file scoping and tool restrictions
- Include partial failure decision table
- Include file scope verification step before committing
- **DoD:** Reference file exists, follows existing pattern, contains complete protocol

## Phase 2: Work Skill Modification

### 2.1 Add Tier 0 pre-check to work SKILL.md Phase 2
- **File:** `plugins/soleur/skills/work/SKILL.md`
- Insert Tier 0 category detection BEFORE the existing independence analysis
- Category detection: scan TaskList for code/test/doc task signals
- If all 3 categories present: offer Tier 0 (interactive) or auto-select (pipeline mode)
- If declined or ineligible: fall through to existing Tier A/B/C cascade unchanged
- Add reference file loading instruction: `**Read plugins/soleur/skills/work/references/work-lifecycle-parallelism.md now**`
- Update pipeline mode override section to include Tier 0 auto-select
- Verify the existing Tier A/B/C sections are untouched
- **DoD:** SKILL.md has Tier 0 pre-check, pipeline mode updated, A/B/C unchanged

## Phase 3: Testing and Verification

### 3.1 Verify one-shot control flow is unbroken
- Read one-shot SKILL.md and trace the flow: plan -> work -> review -> compound -> ship
- Confirm work invocation is unchanged (same args, same Skill tool call)
- Confirm work's Phase 4 handoff behavior is unchanged for all tiers
- **DoD:** One-shot flow verified, no changes needed to one-shot

### 3.2 Verify ship compatibility
- Read ship SKILL.md Phase 5 and confirm version triad handling
- Confirm Agent 3 scope excludes version triad files
- Confirm ship will still detect plugin changes and bump correctly
- **DoD:** Ship compatibility verified, no changes needed to ship

## Phase 4: Compliance

### 4.1 Version bump (MINOR)
- **Files:** `plugins/soleur/.claude-plugin/plugin.json`, `plugins/soleur/CHANGELOG.md`, `plugins/soleur/README.md`
- Also check: `.claude-plugin/marketplace.json`, `.github/ISSUE_TEMPLATE/bug_report.yml`, root `README.md`
- MINOR bump for new skill capability
- CHANGELOG entry under `### Added`
- README: verify reference file count is accurate
- **DoD:** All version files updated and consistent
