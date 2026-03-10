# Tasks: Codex Portability Inventory

## Phase 1: Baseline

- [ ] 1.1 Fetch current Codex docs (skills, agents, MCP, hooks, config)
- [ ] 1.2 Create `codex-baseline.md` with current capabilities and verification date
- [ ] 1.3 Create equivalence mapping table (10 primitives → Codex equivalent or "none")

## Phase 2: Scan & Classify

- [ ] 2.1 Enumerate all 122 components (agents, skills + sub-files, commands)
- [ ] 2.2 Grep each component for 10 primitives, record matches
- [ ] 2.3 Classify green/yellow/red/N/A using worst-primitive-wins
- [ ] 2.4 Flag N/A candidates (Claude Code infrastructure-only)
- [ ] 2.5 Note inter-component dependencies (skill: chains, Task delegations)

## Phase 3: Write Inventory Document

- [ ] 3.1 Summary statistics (counts and percentages)
- [ ] 3.2 Full component inventory table
- [ ] 3.3 Gap analysis per non-portable primitive
- [ ] 3.4 CI/Infrastructure note (GitHub Actions, PreToolUse hooks)
