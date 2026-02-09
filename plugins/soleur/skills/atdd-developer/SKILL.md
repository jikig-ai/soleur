---
name: atdd-developer
description: This skill should be used when implementing features using Acceptance Test Driven Development. It guides through the RED/GREEN/REFACTOR cycle with explicit permission gates between phases. Triggers on "TDD", "ATDD", "test-driven", "red green refactor", "acceptance test first", "write failing test".
---

# ATDD Developer

Guide feature implementation through the Acceptance Test Driven Development cycle. Each phase requires explicit user approval before proceeding.

## When to Use

- Implementing a new feature with acceptance criteria
- Practicing test-driven development on user stories
- Teaching or reinforcing TDD discipline

## The Cycle

### RED Phase: Write Failing Acceptance Tests

1. Read the user story or feature requirements
2. Write acceptance tests in Given/When/Then format
3. Run the tests -- confirm they fail
4. **STOP and ask permission to proceed to GREEN**

Do not write any implementation code during this phase.

### GREEN Phase: Minimal Implementation

1. Write the minimum code to make the acceptance tests pass
2. Run the tests -- confirm they pass
3. Do not refactor, optimize, or add extra code
4. **STOP and ask permission to proceed to REFACTOR**

The goal is passing tests, not beautiful code. Resist the urge to clean up.

### REFACTOR Phase: Improve the Code

1. Apply refactoring techniques while keeping all tests green
2. Use code-simplicity-reviewer or code-quality-analyst via Task tool for guidance if needed
3. Run the full test suite after each refactoring step
4. **STOP and ask permission to proceed to COMMIT**

If any test fails during refactoring, undo the last change immediately.

### COMMIT Phase: Record the Change

1. Create a commit with a meaningful message referencing the user story
2. Use conventional commit format (e.g., `feat(scope): implement user story`)
3. **Ask if there are more stories to implement**

## Key Principles

- Never skip phases or combine them
- Always ask permission before transitioning between phases
- The RED phase defines the contract; the GREEN phase fulfills it
- Refactoring is only safe when tests are green
- Small cycles are better than large ones
