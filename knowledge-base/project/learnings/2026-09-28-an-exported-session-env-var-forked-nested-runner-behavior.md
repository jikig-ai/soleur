---
title: An exported session env var forked nested-runner behavior — and the failure read as six unrelated reds
date: 2026-09-28
category: test-failures
module: scripts/test-all.sh
tags: [env-inheritance, scratch-root, sandbox, tee, splice, owned-vs-inherited]
issue: 8940
pr: 9034
---

# Learning: presence-gated machinery must be ownership-gated

## Problem

`test-all.sh` gained a tee+retention path keyed on `SOLEUR_SCRATCH_SESSION_ROOT`.
The first full gate then showed six reds across suites that looked unrelated:
`test-all-affected` (every arm `ran=0`, missing record files),
`test-all-killed-classification` (a byte-shape assertion on the `[FAIL]` line),
three lint-orphan suites, and the kb-security census.

The mechanism was one, not six: the outer run *exports* the scratch root, so
nested sandbox runners inherit it. Presence of the var ≠ ownership of the
session. Sandboxes took the NEW tee branch; the python splice that writes the
`RAN` records the suite asserts on lives in the OTHER branch — so sandboxes ran
clean-looking but produced zero records (`ran=0`). The byte-shape suite failed
because the sandbox's `[FAIL]` line carried the parent's `log=` suffix.

A second variant the same week: `test-all-affected`'s sandboxes deliberately
omit `scratch-root.sh` — so `SOLEUR_SCRATCH_SESSION_ROOT` can ONLY arrive by
inheritance. Presence-and-shape tell you nothing about provenance.

## Solution

Owner-gate, not presence-gate: `SOLEUR_SCRATCH_OWNER_PID == $$` decides whether
THIS run owns the scratch session (tee+retention). A nested run keeps the
parent's root by design but must not adopt its machinery. Test sandboxes also
`env -u` the three `SOLEUR_SCRATCH_*` vars so they self-allocate under an outer
gate — the inherited-root failure class now has a fixture that simulates it
(`SOLEUR_SCRATCH_SESSION_ROOT=/tmp/fake SOLEUR_SCRATCH_OWNER_PID=999999`).

## Key Insight

Any env var that is both (a) exported for children and (b) read as a
feature-switch is a two-handed weapon: the child inherits the value but not the
state it names. Gate on *provenance* (an owner pid, a one-shot token), not on
*existence* — and when N unrelated suites all fail at once, look for the shared
inherited precondition before treating them as N defects. The durable-log
machinery that made the other reds diagnosable was the same change that caused
this one.

## Tags

category: test-failures
module: scripts/test-all.sh
