---
title: "Bun segfaults from leaked setInterval timers in tests"
date: 2026-03-20
category: test-failures
tags: [bun, testing, timer-leak, segfault, bridge, afterEach]
module: apps/telegram-bridge
---

# Learning: Bun segfaults from leaked setInterval timers in tests

## Problem

`bun test` crashes with a segfault (RSS ~1GB) when running the telegram-bridge test suite. The crash was dismissed in a previous session as "a known Bun bug unrelated to our changes" — but it was caused by our test code.

Root cause: `Bridge.sendUserMessage()` fire-and-forgets `startTurnStatus()`, which creates a `setInterval` for typing indicators. When `writeToStdin` throws (sync or async), the error handler calls `cleanupTurnStatus()` — but `startTurnStatus` hasn't finished yet (it yields at its first `await`), so `turnStatus` is still null and the cleanup is a no-op. The `setInterval` leaks permanently.

With ~10 tests leaking 100ms intervals, mock call records accumulate unboundedly across the test run, spiking RSS to 1GB and triggering Bun's allocator segfault.

## Solution

1. Added `Bridge.destroy()` method that synchronously clears all timers (watchdog + typing interval) and resets state
2. Added `afterEach(() => bridge.destroy())` to every describe block in the test file
3. Also cleans up `bridge2` in the watchdog streaming test

## Key Insight

Fire-and-forget async methods that create timers are a timer leak hazard in tests. The error recovery path runs before the timer-creating method has finished, so cleanup is a no-op. The fix is structural: `afterEach` with a `destroy()` method that forcibly clears all timers, regardless of the async state of creation methods.

**Meta-lesson:** When a test runner crashes (segfault, OOM), never dismiss it as a "known runtime bug." Investigate whether your code is triggering it. Added a hard rule to AGENTS.md to enforce this.

## Tags

category: test-failures
module: apps/telegram-bridge
