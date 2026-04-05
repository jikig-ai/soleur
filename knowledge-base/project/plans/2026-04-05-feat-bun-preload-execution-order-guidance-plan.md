---
title: "feat: add bun preload execution-order guidance to work SKILL.md"
type: feat
date: 2026-04-05
---

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 1 (References)
**Research agents used:** learnings-scanner (3 related learnings reviewed)

### Key Findings

1. The proposed bullet is technically accurate -- verified against the source learning and two related learnings (cross-runner compat, vi.stubEnv unavailability)
2. No additional bullet points needed -- the cross-runner compat and vi.stubEnv learnings cover different failure modes (mocking API differences, not preload execution order) and are already discoverable via the learnings directory
3. The placement in "Test environment setup" is correct -- this is exactly where an agent would need the guidance, before writing the RED test

### Deepening Assessment

This plan is a 2-line documentation edit with no architecture, performance, security, or UI implications. Full parallel research (40+ agents) would produce zero actionable enhancements. The deepening value here is the verification that the technical claim is accurate and the placement is optimal.

# Add Bun Preload Execution-Order Guidance to Work SKILL.md

## Overview

Route the bun preload execution-order learning into `plugins/soleur/skills/work/SKILL.md` Phase 2 Task Execution Loop, so agents setting up test environments avoid the static-import hoisting pitfall that caused 71 test failures in `apps/web-platform/`.

## Problem Statement

The learning documented in `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md` captures a non-obvious bun behavior: static ES imports are hoisted before imperative code in preload scripts, which means `GlobalRegistrator.register()` (or any DOM-global registration) runs after libraries like `@testing-library/react` have already initialized without DOM globals. The fix is to use dynamic `await import()` for all dependencies after the registration call.

This learning is currently only discoverable via the learnings directory. Agents running `/soleur:work` Phase 2 will not consult learnings unless they happen to match a search. Adding the guidance directly to the "Test environment setup" paragraph in SKILL.md ensures every agent sees it at the moment it matters.

## Proposed Solution

Add a single bullet to the existing **Test environment setup** paragraph in Phase 2 Task Execution Loop (line 241 of `plugins/soleur/skills/work/SKILL.md`), with a back-reference to the source learning.

### Exact edit

**Target file:** `plugins/soleur/skills/work/SKILL.md`

**Target section:** Phase 2: Execute > Task Execution Loop > "Test environment setup" paragraph (currently a single paragraph starting at line 241)

**Current text (line 241-242):**

```markdown
   **Test environment setup:** If the project's test runner cannot run the type of test needed (e.g., React component tests require jsdom but vitest is configured for node), set up the test environment BEFORE starting the task. This is part of RED — the test infrastructure must exist for the test to fail properly.
```

**Proposed replacement:**

```markdown
   **Test environment setup:** If the project's test runner cannot run the type of test needed (e.g., React component tests require jsdom but vitest is configured for node), set up the test environment BEFORE starting the task. This is part of RED — the test infrastructure must exist for the test to fail properly.

   - When configuring bun preload scripts that register DOM globals (e.g., happy-dom), use dynamic `await import()` for all subsequent dependencies — static ES imports are hoisted before any imperative code, causing libraries like @testing-library/react to initialize without DOM globals. See `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`.
```

## Acceptance Criteria

- [x] The bullet appears in `plugins/soleur/skills/work/SKILL.md` under Phase 2 > Task Execution Loop > Test environment setup
- [x] The bullet text matches the issue body exactly, with an added source reference to the learning file
- [x] The existing paragraph text is unchanged
- [x] Markdown linting passes (`npx markdownlint-cli2 --fix plugins/soleur/skills/work/SKILL.md`)

## Test Scenarios

- Given the updated SKILL.md, when an agent reads Phase 2 Task Execution Loop, then the bun preload guidance is visible in the "Test environment setup" section
- Given the updated SKILL.md, when running `npx markdownlint-cli2 plugins/soleur/skills/work/SKILL.md`, then no lint errors are reported
- Given the learning file path referenced in the bullet, when checked with `test -f`, then the file exists

## Context

- **Source learning:** `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`
- **GitHub issue:** #1462
- **Scope:** Single bullet addition to one file. No code changes, no new files, no dependency changes.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## References

- Related issue: #1462
- Source learning: `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`
- Target file: `plugins/soleur/skills/work/SKILL.md` (line 241)
- Related issue: #1430 (original test failure fix)
- Related learning (cross-runner compat): `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md`
- Related learning (vi.stubEnv): `knowledge-base/project/learnings/developer-experience/2026-03-29-bun-test-vi-stubenv-unavailable.md`
