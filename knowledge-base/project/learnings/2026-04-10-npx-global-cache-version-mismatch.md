---
title: npx resolves from global cache before node_modules/.bin
date: 2026-04-10
category: build-errors
tags: [npx, vitest, node_modules, test-scripts, dependency-resolution]
symptoms: "vitest run fails with missing rolldown native bindings when invoked via npx"
module: scripts/test-all.sh
synced_to: constitution.md
---

# Learning: npx resolves from global cache before node_modules/.bin

## Problem

`scripts/test-all.sh` used `npx vitest run` to execute tests. On some machines,
this pulled a different vitest version from the npx global cache
(`~/.npm/_npx/`) instead of the one installed in `node_modules/.bin/`. The cached
version depended on rolldown native bindings that were not installed locally,
producing cryptic native module errors unrelated to the test code.

The failure was intermittent because it depended on whether npx had cached a
newer vitest version from a prior unrelated invocation.

## Root Cause

`npx` resolution order: (1) global npx cache (`~/.npm/_npx/`), (2) `$PATH`,
(3) `node_modules/.bin/`. When the cache contains a package matching the
requested name, npx uses it without checking whether the cached version matches
the project lockfile.

`npm run <script>` prepends `node_modules/.bin/` to `$PATH` before executing,
guaranteeing the lockfile-pinned version is used.

## Solution

Replaced `npx vitest run` with `npm run test:ci` in `scripts/test-all.sh` and
added `"test:ci": "vitest run"` to `apps/web-platform/package.json`. The npm
script resolves vitest from `node_modules/.bin/`, which matches the lockfile.

## Prevention

- Never use `npx <tool>` in shared scripts or CI when the tool is a project
  devDependency -- use `npm run <script>` or invoke the binary directly via
  `./node_modules/.bin/<tool>`
- The constitution rule "Never use `npx` to run project devDependencies in
  scripts or CI" enforces this going forward

## Session Errors

1. **Step 0a: ralph-loop path mismatch** -- The one-shot orchestrator invoked
   `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` but the
   correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`. Exit code 127
   on first attempt, corrected on retry.
   - **Prevention:** The SKILL.md already has the correct path. This was a plan
     execution error (the plan specified the wrong path). The AGENTS.md hard rule
     "trace each `../` step to verify the final target before implementing"
     applies -- always verify script paths against the filesystem before running.

## Deviation Analysis

Session was clean against AGENTS.md hard rules except:

- **Path verification (Hard Rule 5):** The ralph-loop script path in the plan
  was wrong and executed verbatim without filesystem verification. The error was
  caught by exit code 127 and corrected on retry. No data loss.

No other deviations detected.
