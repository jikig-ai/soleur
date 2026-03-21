# Tasks: Parallel Agent Lifecycle Orchestration (Tier 0)

## Phase 1: Core Protocol Document

### 1.1 ~~Create work-lifecycle-parallel.md reference file~~ DONE

- **File:** `plugins/soleur/skills/work/references/work-lifecycle-parallel.md`
- Follow the existing reference file pattern (work-agent-teams.md, work-subagent-fanout.md)
- Include 6 steps: Offer/Auto-select, Generate Contract, Spawn 2 Agents, Collect Results, Integration (commit + test-fix-loop), Write Docs Sequentially
- Each step must include: heading with step number, description, prompt examples, fallthrough semantics
- No halt language ("stop", "announce", "tell the user") -- use "return control" / "proceed to next step"
- Interface contract has 2 sections only: File Scopes (table) + Public Interfaces (signatures)
- Agent prompts for 2 agents (code + tests) with explicit file scoping, pwd verification, and tool restrictions via instructions
- One failure rule: "Keep what worked, finish rest via Tier C"
- Document test-fix-loop clean-tree dependency: coordinator MUST commit before invoking test-fix-loop
- Agent 1 does NOT write test files; Agent 2 writes ALL tests
- **DoD:** Reference file exists, follows existing pattern, contains complete 2-agent protocol

## Phase 2: Work Skill Modification

### 2.1 ~~Add Tier 0 pre-check to work SKILL.md Phase 2~~ DONE

- **File:** `plugins/soleur/skills/work/SKILL.md`
- Insert Tier 0 check BEFORE the existing independence analysis
- Single LLM judgment: "Does this plan have independent code + test workstreams with non-overlapping file scopes?"
- If yes: offer Tier 0 (interactive) or auto-select (pipeline mode)
- If declined or ineligible: fall through to existing Tier A/B/C cascade unchanged
- Add reference file loading instruction: `**Read plugins/soleur/skills/work/references/work-lifecycle-parallel.md now**`
- Update pipeline mode override section to include Tier 0 auto-select
- Verify the existing Tier A/B/C sections are untouched
- **DoD:** SKILL.md has Tier 0 pre-check, pipeline mode updated, A/B/C unchanged

## Phase 3: Testing and Verification

### 3.1 ~~Verify one-shot and ship compatibility~~ DONE

- Read one-shot SKILL.md and trace the flow: plan -> work -> review -> compound -> ship
- Confirm work invocation is unchanged (same args, same Skill tool call)
- Read ship SKILL.md Phase 5 and confirm version triad handling is unaffected
- Confirm no agent touches version triad files
- **DoD:** One-shot and ship flows verified, no changes needed to either

### 3.2 ~~File test-fix-loop stash issue~~ DONE (#409)

- Create a GitHub issue tracking the pre-existing conflict: test-fix-loop uses `git stash` internally but constitution forbids stash in worktrees
- This is not introduced by Tier 0 but is surfaced by it
- **DoD:** GitHub issue created with clear reproduction steps

## Phase 4: Compliance

### 4.1 ~~Version bump (MINOR)~~ DONE (3.8.2 -> 3.9.0)

- **Files:** `plugins/soleur/.claude-plugin/plugin.json`, `plugins/soleur/CHANGELOG.md`, `plugins/soleur/README.md`
- Also check: `.claude-plugin/marketplace.json`, `.github/ISSUE_TEMPLATE/bug_report.yml`, root `README.md`
- MINOR bump for new skill capability
- CHANGELOG entry under `### Added`
- README: verify reference file count is accurate
- **DoD:** All version files updated and consistent
