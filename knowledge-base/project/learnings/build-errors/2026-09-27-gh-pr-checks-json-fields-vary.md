---
title: gh pr checks exposes a smaller JSON field set than workflow checks
date: 2026-09-27
category: build-errors
module: github-cli-inspection
---

## Problem

Requesting the `conclusion` field from `gh pr checks --json` failed because
that command exposes `state` but not `conclusion`.

## Prevention

Use `gh pr checks --json name,state,link` to inspect PR check results. Query a
workflow run with `gh run view --json conclusion` when a workflow-level
conclusion is required.
