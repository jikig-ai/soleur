---
title: "CI job images force-color vitest output — count greps split on ANSI escapes"
date: 2026-10-11
category: testing
issue: 9815
pr: 10025
---

# CI job images force-color vitest output — count greps split on ANSI

**Class:** a suite asserts on `Test Files N passed`-shaped vitest output that
is plain locally but colorized in CI. The escape codes sit *inside* the
matched region (`[2m Test Files [22m [1m[32m2 passed[39m`), so
`grep -E 'Test Files[[:space:]]+2 passed'` never matches and every arm reds —
with rc=0, so the failure looks vacuous rather than environmental.

**Detection cost:** the log dump shows green ✓ marks and the correct counts
visibly present; the assertion is invisible unless you notice the escapes.
Locally the same suite is green — non-TTY output is uncolored, so the defect
only exists in CI (or wherever FORCE_COLOR-style env is set).

**Fix:** strip ANSI on capture, before assertion —
`sed -e $'s/\033\[[0-9;]*m//g'`. Two traps in the fix itself:

1. `\x1b` is GNU-sed only; BSD sed (stock macOS) needs a literal ESC byte —
   `$'s/\033.../'` inside ANSI-C quoting produces it portably.
2. Escaping the escape: writing the line through a python/heredoc layer
   easily produces `\\033` (literal backslash-033, matches nothing). Verify
   the committed bytes with `echo -e "\033[32mX\033[0m" | <the sed>`.

**Related same-session class:** `mapfile` is bash ≥4.0 and the runner's
stated floor is 3.2 (stock macOS `/bin/bash`). A while-read loop is the 3.2
shape; `mapfile` fails `command not found` and the subsequent `"${arr[@]}"`
aborts under `set -u` — the feature's primary path redded only off-Linux.
