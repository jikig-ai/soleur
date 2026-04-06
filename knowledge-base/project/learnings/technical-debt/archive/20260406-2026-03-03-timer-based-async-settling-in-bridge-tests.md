---
title: Timer-based async settling in bridge tests
date: 2026-03-03
category: technical-debt
tags: [testing, async, flaky-tests, telegram-bridge]
severity: medium
---

# Timer-Based Async Settling in Bridge Tests

## Problem

11 test cases in `apps/telegram-bridge/test/bridge.test.ts` use `await new Promise((r) => setTimeout(r, 50))` to wait for fire-and-forget async operations to settle. One test uses a 200ms wait for a watchdog timer.

Affected lines: 372, 397, 489, 513, 674, 700, 733, 745, 814, 822, 844.

## Root Cause

`Bridge` methods like `startTurnStatus` and `sendUserMessage` fire-and-forget their async work without returning a handle. Tests have no way to await completion other than time-based settling.

## Key Insight

Timer-based settling is sensitive to machine load and could produce false negatives on slow CI runners. The fix is to return `Promise` handles from fire-and-forget methods, but this requires changing the Bridge API contract.

## Tags

testing, async, flaky-tests, telegram-bridge
