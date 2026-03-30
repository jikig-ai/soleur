---
title: TDD enforcement gap in /work skill and React component test setup
date: 2026-03-30
category: workflow
tags: [tdd, testing, vitest, react, happy-dom, workflow-enforcement]
symptoms:
  - "Agent writes all implementation before any tests"
  - "jsdom ESM compatibility error with html-encoding-sniffer"
  - "bun test picks up .tsx files but cannot provide DOM environment"
module: plugins/soleur/skills/work
severity: high
---

# TDD Enforcement Gap and React Component Test Setup

## Problem

The `/work` skill's Phase 2 execution loop described RED/GREEN/REFACTOR as steps in a text workflow, but had no structural enforcement. During chat UX redesign (#1289), the agent wrote all Phase 1 components (ChatInput, AtMentionDropdown, types.ts changes, ws-client.ts changes, agent-runner.ts changes) before writing any tests. The rationalization was "these are simple type additions and new component files — tests would just be boilerplate." This is exactly the reasoning TDD is designed to prevent.

Additionally, setting up React component testing in vitest required discovering several compatibility issues:

- `jsdom@29` has an ESM/CJS conflict with `html-encoding-sniffer` (`@exodus/bytes/encoding-lite.js`)
- `@vitejs/plugin-react` is ESM-only and cannot be imported from CJS vitest configs
- `bun test` (used by `test-all.sh`) picks up `.tsx` test files but cannot provide DOM environments like happy-dom

## Solution

### TDD Enforcement

Added a **TDD hard gate** to both AGENTS.md (Code Quality section) and `/work` SKILL.md (Phase 2 execution loop):

- Before writing ANY implementation code for a task, determine if it has testable behavior
- If the plan has Test Scenarios or Acceptance Criteria, write the failing test file FIRST
- The test must import the not-yet-created module (import will fail — that's correct)
- Run the test to verify RED (must fail)
- Only then write the minimum implementation (GREEN)
- Infrastructure-only tasks (config, CI, scaffolding) are exempt

The key insight: "The rationalization 'this is simple enough to not need test-first' is exactly the reasoning TDD is designed to prevent."

### React Test Setup

Working configuration for vitest + React component tests:

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  esbuild: {
    jsx: "automatic",  // NOT @vitejs/plugin-react (ESM-only)
  },
  test: {
    environment: "node",
    exclude: ["e2e/**", "node_modules/**"],
    environmentMatchGlobs: [
      ["test/**/*.tsx", "happy-dom"],  // NOT jsdom (ESM compat issues)
    ],
    setupFiles: ["test/setup-dom.ts"],
  },
  resolve: {
    alias: { "@": path.resolve(__dirname) },
  },
});
```

Setup file for matchers and cleanup:

```typescript
// test/setup-dom.ts
import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";

afterEach(async () => {
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }
});
```

### test-all.sh Fix

Changed `bun test apps/web-platform/` to `bash -c "cd apps/web-platform && npx vitest run 2>&1"` because vitest handles both node (`.ts`) and happy-dom (`.tsx`) environments correctly, while bun's test runner cannot.

## Key Insight

Workflow enforcement requires structural gates, not prose instructions. When the AGENTS.md says "Never commit to main" there's a hook that physically blocks it. When the `/work` skill says "Write failing tests first" it was just words the agent could skip. The fix promoted TDD from a suggestion to a hard gate with the same enforcement pattern as other blocked behaviors.

For React testing: use `happy-dom` over `jsdom` (fewer ESM conflicts), use `esbuild: { jsx: "automatic" }` over `@vitejs/plugin-react` (CJS-compatible), and run web-platform tests through vitest (not bun test) to get per-file environment selection.

## Session Errors

1. **TDD violation** — Wrote Phase 1 implementation before tests. Recovery: Added TDD hard gate to AGENTS.md and /work SKILL.md, then wrote tests retroactively. **Prevention:** The new TDD gate in /work Phase 2 structurally blocks implementation before tests.

2. **Missing worktree deps** — Pre-commit hook failed because `bun install` hadn't been run. Recovery: Ran `bun install`. **Prevention:** Worktree manager could auto-install deps on create.

3. **jsdom ESM error** — `jsdom@29` + `html-encoding-sniffer` CJS/ESM conflict. Recovery: Switched to happy-dom. **Prevention:** Use happy-dom for vitest DOM testing (documented above).

4. **@vitejs/plugin-react ESM error** — Plugin is ESM-only, can't be required from CJS config. Recovery: Used `esbuild: { jsx: "automatic" }`. **Prevention:** Use esbuild JSX transform (documented above).

5. **bun test vs vitest mismatch** — `test-all.sh` used `bun test` which picked up .tsx files without DOM env. Recovery: Changed to vitest. **Prevention:** The fix is committed to test-all.sh.

6. **CSS uppercase vs literal text** — `getByText("COMMAND CENTER")` failed because CSS `text-transform: uppercase` doesn't change DOM text content. Recovery: Used literal uppercase text. **Prevention:** Remember that CSS transforms are visual-only; DOM text content is what testing-library queries match.

## Prevention

- The TDD gate in `/work` Phase 2 now structurally prevents implementation-before-tests
- The vitest config with happy-dom + esbuild JSX is documented for future React component test setup
- `test-all.sh` uses vitest for web-platform to support per-file environment selection
