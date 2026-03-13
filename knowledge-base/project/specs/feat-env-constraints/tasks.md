---
feature: feat/env-constraints
plan: knowledge-base/plans/2026-03-03-chore-document-environment-constraints-plan.md
issue: "#394"
deepened: 2026-03-03
---

# Tasks: Document Environment Constraints

## Phase 1: Core Implementation

- [x] 1.1 Add Warp terminal constraint to AGENTS.md Hard Rules section
  - Rule: "The host terminal is Warp. Do not attempt automated terminal manipulation via escape sequences (cursor position queries, TUI rendering, and similar sequences are intercepted by Warp's tmux control mode and silently fail)."
  - Place at end of Hard Rules section, grouped with 1.2
  - Note: Warp *does* support OSC title sequences (`\033]0;...\007`) -- the constraint covers cursor position queries and TUI rendering, not tab title setting
- [x] 1.2 Add non-interactive shell / no-sudo constraint to AGENTS.md Hard Rules section
  - Rule: "The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead."
  - Place immediately after 1.1
- [x] 1.3 Add environment constraints principle to constitution.md Architecture > Always
  - Principle: "Document environment-specific constraints (terminal capabilities, shell limitations) in AGENTS.md Hard Rules when Claude violates them without being told -- these are loaded every turn and prevent dead-end attempts"
  - Place after existing Architecture > Always rules

## Phase 2: Verification

- [x] 2.1 Verify AGENTS.md Hard Rules section stays under 35 lines after changes
- [x] 2.2 Run markdownlint on AGENTS.md and constitution.md
- [ ] 2.3 Run compound before commit
