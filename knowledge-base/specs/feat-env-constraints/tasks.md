---
feature: feat/env-constraints
plan: knowledge-base/plans/2026-03-03-chore-document-environment-constraints-plan.md
issue: "#394"
---

# Tasks: Document Environment Constraints

## Phase 1: Core Implementation

- [ ] 1.1 Add Warp terminal constraint to AGENTS.md Hard Rules section
  - One-line rule: Warp terminal does not support ANSI escape sequences for tab manipulation
  - Place after existing Hard Rules, before Workflow Gates
- [ ] 1.2 Add non-interactive shell / no-sudo constraint to AGENTS.md Hard Rules section
  - One-line rule: Bash tool runs without sudo access, provide manual instructions instead
  - Place adjacent to the Warp rule (group environment constraints together)
- [ ] 1.3 Add environment constraints principle to constitution.md Architecture > Always
  - Document the pattern: environment-specific constraints go in AGENTS.md Hard Rules
  - Place after existing architecture rules

## Phase 2: Verification

- [ ] 2.1 Verify AGENTS.md token budget is not materially impacted
  - Count words in AGENTS.md before and after changes
- [ ] 2.2 Run markdownlint on modified files
- [ ] 2.3 Run compound before commit
