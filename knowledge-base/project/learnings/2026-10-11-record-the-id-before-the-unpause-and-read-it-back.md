---
title: Record the id before the irreversible request, read it back, and never let cleanup change the verdict
date: 2026-10-11
category: logic-errors
module: arm-heartbeats
tags: [record-before-act, books-file, mutation-battery, review-fix-rounds, host-contention]
issue: 9980
pr: 10029
---

# Learning: record-before-act with read-back (arm-heartbeats `--arm-one`, #9980)

## Problem

`--arm-one` unpauses a Better Stack monitor, polls for a real beat and rolls back if none lands. Two review fix-rounds found the same class three times: a live monitor could end up on nobody's books.

- The id was recorded AFTER the unpause. A request that landed server-side with its reply lost left a live, unfed monitor on no books.
- The id was appended with `printf '%s\n' >>` to a persistent, hand-edited books file with no trailing newline. `99` + `42` became `9942`; the documented `--sweep` then re-paused a different monitor while 42 stayed live.
- An append that "succeeds" into a file that does not keep it (`/dev/null`, a procfs entry, a symlink swapped after the preflight) put the id nowhere.
- The residual-books check ("the file still lists the id") was allowed to change the outcome, and the `failed` branch asserted "left paused" for a monitor the run never read.

## Solution

- Record before the request, then READ THE ID BACK from the file and refuse before the PATCH if it is absent. Write a leading newline when the file does not end in one.
- The preflight must prove the cleanup can run too (a sibling scratch file), not only that an append works.
- The residual check is a warning only; it never changes the outcome. Where the run did not establish the state, the message says "read `--status` first" and asserts nothing.
- Pin the ordering with a test that snapshots the books file inside the stub at the instant the unpause PATCH arrives. A test that only inspects the books at the end cannot tell "before" from "after".

## Key Insight

Record-before-act is only as good as the proof that the record exists. An append's exit status is evidence about the write, not about the file. A test pins an ordering only if it observes the world AT the irreversible request.

## Session Errors

- **Mutation rows displaced by new code (M3, M8, M18, M36, M40, M42)** — Recovery: re-anchored. Prevention: after adding code to the SUT, re-drive every mutation row against the current tree; a `sed` that still "lands" can now land on a different line (M8 matched a substring of a new `elif`).
- **A mutant copied into the repo, then failed to detect (M46)** — Recovery: a CDPATH decoy directory outside the repo. Prevention: a mutant must never write inside the tree under test; detection by side effect needs a decoy elsewhere.
- **A payload died on `set -u`, not on the behaviour under test (M36)** — Recovery: use a set variable in the injection. Prevention: when a negative test "passes", confirm it died of the intended cause, not an unbound variable.
- **Wrong script path in the issue (`plugins/soleur/scripts/...`)** — Recovery: real path `apps/web-platform/infra/arm-heartbeats.sh`. Prevention: verify the path named in an issue before planning against it.
- **Runbook rotate dispatch lacked `-f reason=`; the rotate path carries a stale both-volumes assert** — Recovery: dispatch fixed in this PR; the assert is a follow-up in a different subsystem. Prevention: dry-read every dispatch command in a runbook against the workflow's required inputs.
- **Host load ~58 stretched a 35 s suite to ~6 min and blew tool timeouts** — Recovery: stop the local battery, rely on CI after shellcheck and the pre-change green run. Prevention: check `uptime` before a long battery; for a one-line tweak shellcheck + the last green run + CI is the proportionate gate.

## Tags

category: logic-errors
module: arm-heartbeats
