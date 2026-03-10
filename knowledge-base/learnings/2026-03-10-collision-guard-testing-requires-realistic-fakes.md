# Learning: Collision guard testing requires realistic fake binaries

## Problem

The `pencil-setup` skill includes an evolus/pencil collision guard that checks `pencil --version` output for a specific string to distinguish the correct `pencil` binary from a same-named unrelated tool. During dogfood testing, a naive fake binary (`#!/bin/bash\nexit 0`) was placed in PATH to simulate the collision. The guard passed because the fake produced no output, and the version-string check (grep for expected pattern) correctly failed -- but only by accident. A slightly different guard implementation (e.g., checking exit code instead of output) would have been fooled. Worse, if the fake had echoed the expected version string, the guard would have passed entirely.

The test only caught the collision when using a realistic fake that mimicked evolus/pencil behavior (returning a plausible but wrong version string like `"Evolus Pencil 3.1.0"`).

## Solution

When testing binary collision guards (where two different tools share the same executable name):

1. **Realistic fakes must produce plausible wrong output**, not empty output or silent success. A guard for `pencil --version` should be tested against a fake that outputs `"Evolus Pencil 3.1.0"`, not one that exits 0 silently.
2. **Test both sides of the guard**: confirm the guard rejects the wrong binary AND accepts the right one. A guard that rejects everything is just as broken as one that accepts everything.
3. **Prefer output-content checks over exit-code checks** for collision guards. Exit codes are too coarse -- most well-behaved CLIs return 0 for `--version`. String matching on stdout is the reliable discriminator.

## Key Insight

A collision guard is only as good as its test double. Naive fakes (exit 0, no output) exercise the guard's happy path but miss the actual collision scenario -- two legitimate tools with different output. Always test collision guards with fakes that produce the specific output the wrong tool would actually produce, not just a generic stub.

## Tags
category: runtime-errors
module: pencil-setup
symptoms: collision guard passes with wrong binary, naive test double masks guard failure
