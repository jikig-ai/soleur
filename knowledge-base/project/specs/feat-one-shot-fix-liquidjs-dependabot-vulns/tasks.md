---
title: "Tasks: fix liquidjs Dependabot vulnerabilities"
date: 2026-05-27
lane: single-domain
---

# Tasks: fix liquidjs Dependabot vulnerabilities

## Phase 1: Update lockfile

- [ ] 1.1 Run `npm update liquidjs`
- [ ] 1.2 Verify `npm ls liquidjs` shows liquidjs@10.27.0 (or >= 10.26.0)
- [ ] 1.3 Verify `npm audit --audit-level=moderate` exits 0
- [ ] 1.4 Run `npm run docs:build` -- expect exit 0
- [ ] 1.5 Verify `git diff --name-only` shows only `package-lock.json`
- [ ] 1.6 Commit `package-lock.json`
