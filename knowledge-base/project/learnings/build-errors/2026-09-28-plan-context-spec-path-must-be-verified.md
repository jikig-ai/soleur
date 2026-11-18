---
title: Verify a feature spec path before including it in a batched read
date: 2026-09-28
category: build-errors
module: plan-context-discovery
---

## Problem

A batched `sed` probe included `knowledge-base/project/specs/<branch>/spec.md`
before checking whether the file existed. The feature directory contained only
`tasks.md` and `session-state.md`; the failed read did not invalidate the other
results, but it obscured the plan inspection.

## Prevention

Resolve a feature's tracked spec files with `rg --files knowledge-base/project/specs/<branch>`
before batching reads. Do not assume every feature directory contains `spec.md`.
