---
title: Telegram bridge index.ts mixes three concerns with no test coverage
date: 2026-03-03
category: technical-debt
tags: [telegram-bridge, code-organization, testing]
severity: medium
---

# Telegram Bridge index.ts Mixes Three Concerns

## Problem

`apps/telegram-bridge/src/index.ts` is 402 lines handling three distinct concerns:

1. Environment variable validation and configuration
2. grammY bot setup and message routing
3. Claude CLI process lifecycle management (spawn, restart loop with exponential backoff, stdout parsing)

The core logic module `bridge.ts` (438 lines) is well-tested with ~130 tests, but `index.ts` has zero test coverage and no corresponding `index.test.ts`.

## Key Insight

The process-management logic (exponential backoff, restart loop, stdout stream parsing) is complex enough to warrant extraction into a testable module. Entry points are inherently harder to test, but extracting the process manager would bring the untested surface area under control.

## Tags

telegram-bridge, code-organization, testing
