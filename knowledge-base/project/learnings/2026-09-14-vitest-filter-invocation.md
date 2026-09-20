---
title: "Use the app-local Vitest binary for new filtered suites"
date: 2026-09-14
category: workflow
---

In the web-platform worktree, a filtered `npm run test:ci -- --run <path>`
invocation can resolve a different workspace Vitest binary and report no test
files even when the app-relative path exists. Run the app-local
`npx vitest run <path>` command instead; it resolves the pinned app tool and
keeps the filter rooted at `apps/web-platform`.
