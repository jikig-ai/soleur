---
title: "Run app test paths from the app checkout"
date: 2026-09-13
category: workflow
---

When the working directory is `apps/web-platform`, Vitest paths and file
creation destinations must be app-relative. Prefixing them with
`apps/web-platform/` creates a nonexistent nested path and produces a
misleading no-test-files failure.
