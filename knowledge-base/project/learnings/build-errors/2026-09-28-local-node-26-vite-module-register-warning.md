---
title: Vite's node:module fallback emits a warning on local Node 26
date: 2026-09-28
category: build-errors
module: vitest-local-runtime
---

## Problem

Focused Vitest runs under local Node 26 emitted `DEP0205` from Vite's
`module.register()` compatibility fallback. The repository pins Node 22 in
`.nvmrc`, and CI uses that supported runtime; the warning did not indicate a
test failure.

## Prevention

Use the repository-pinned Node version when interpreting local test output.
Treat `DEP0205` as a runtime warning only while Vite retains this fallback;
reassess it if CI or the pinned runtime begins emitting it.
