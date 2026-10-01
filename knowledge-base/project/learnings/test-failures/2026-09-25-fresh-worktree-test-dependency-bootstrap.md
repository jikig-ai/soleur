---
date: 2026-09-25
problem_type: workflow_error
component: web-platform-tests
status: closed
tags: [worktrees, test-isolation, dependencies]
---

# Install the app dependencies before testing in a fresh worktree

The first Codex Web guard test run in a fresh worktree failed during Vitest
bootstrap with `Could not resolve 'vitest/config'`. The worktree had no
`apps/web-platform/node_modules`; this was not a product-code failure.

Running `npm ci --ignore-scripts --no-audit --no-fund` from
`apps/web-platform` installed the pinned dependencies. The focused tests and
typecheck then ran. Future fresh-worktree test runs should check for the
project-local binary first, install from the app lockfile when absent, and
invoke `./node_modules/.bin/vitest` so an external `npx` cache cannot supply a
different version.
