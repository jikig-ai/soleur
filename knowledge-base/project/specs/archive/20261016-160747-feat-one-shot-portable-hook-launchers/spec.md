---
title: Portable repository hook launchers
lane: single-domain
domain: engineering
---

# Feature: Portable repository hook launchers

## Problem Statement

Codex cannot launch the repository rules-loader and guardrails from the bare repository root because its configured Git probe requires a worktree. Devin's deepest fallback carries the same assumption.

## Goals

- Repair the actual configured entrypoints across bare and working checkouts.
- Preserve existing Claude/Grok and environment-override behavior and safety-hook contracts.

## Non-Goals

- New harness hook capabilities, matcher changes, a generic dispatcher or installed-plugin root resolution.
- PR #9051, live operations, builds, browser/provider/account work or hook-body redesign.

## Functional Requirements

### FR1: Resolve the selected repository

Codex derives its root from Git; Devin preserves Claude project override, Devin project override, then Git. Git tries the active checkout first, and falls back to absolute Git directory only for a positively identified bare repository; only a terminal `/.git` is removed. A missing selected target or failed discovery dispatches no alternate checkout.

### FR2: Preserve hook invocation

Keep each interpreter, target, argument tail, working directory, stdin bytes, stdout/stderr, exit status, matcher and timeout unchanged. Registered targets remain singly enumerable for the Devin disposition audit.

## Technical Requirements

### TR1: Test actual configurations

Execute commands extracted from native config registries in hermetic synthetic ordinary, nested, linked-worktree, Soleur-style bare and conventional-bare repositories, including spaces. Cover precedence, invalid roots, missing target ownership and exact streams/status. Use real hook entrypoint smoke cases for rule context and guard response compatibility.

### TR2: Keep ownership boundaries

Apply the bounded Git fallback inline; a new helper would require the same bootstrap. Installed-plugin execution remains governed by its separate plugin-root contract. Cursor's existing lack of repository hook execution remains accurately scoped.

## Plan

See `knowledge-base/project/plans/archive/20261016-160747-2026-10-15-fix-portable-hook-launchers-plan.md` and `interface-contract.md` for the exact expression, guard contract and code/test scopes.
