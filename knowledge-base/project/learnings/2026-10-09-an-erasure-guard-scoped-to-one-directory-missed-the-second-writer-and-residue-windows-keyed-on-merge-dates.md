---
title: An erasure guard scoped to one directory missed the second writer, and residue windows were keyed on merge dates
date: 2026-10-09
category: security-issues
tags: [art-17, erasure, residue, guard-scope, review, git-data, gdpr]
issue: 9066
---

# Learning: an erasure guard scoped to one directory missed the second writer; residue windows were keyed on merge dates

## Problem

#9066: a zero-byte `.<auth.users.id>.init.lock` file kept the user id on the git-data store after Art. 17 erasure.
The code half was already on main (PR #9226 made the lock one constant name), so this PR added a test guard
(`subject_id_leaks`: no entry other than `<id>.git` carries the id) plus retention docs. An 11-seat panel, a
targeted fix round and a verification pass still found, in order:

- A second id-bearing file the guard could not see: `git-data-gc.sh` writes the last repo's name (`<id>.git`) to
  `.gc-cursor` one level above the repo root the guard scans.
- The docs said the running host still served the old wrappers; a host replace had run the day before.
- The "plaintext volume" residue window was dated by the PR merge (#8564), then by the next replace; the true cut
  is the day the plaintext-serving host was destroyed (a failed replace in between served nothing).
- The guard itself failed open: it aborted only its own `$(...)` subshell, ignored unreadable entries and
  symlink targets, and its arms passed even when the wrapper exited right after the lock.

## Solution

- Guard: callers end `|| exit 2`; the predicate also checks symlink targets and merges grep stderr into its
  output; fixtures cover nested name, nested content, nested symlink and an unscannable root; each arm asserts it
  reached the code and the root holds exactly the expected entries with an empty lock (catches transformed ids a
  substring cannot); a refused-path arm checks a refusal writes nothing.
- Docs: boundaries stated from the instance lifecycle, the replace stated as read from the run and head, the
  `.gc-cursor` limb disclosed in the Art. 30 marker, ADR, runbook and decision log (DC-4), CLO re-attested with a
  scoped disposition.

## Key Insight

A property named for the whole store ("no entry carries the id") is only as wide as the directory the change
touches. Derive a guard's scope from the WRITERS of the identifier (grep every script that handles it, including
cursors, caches and sidecars outside the data directory), not from the one path the fix edits. And date a
residue window from the instance lifecycle (server created and destroyed, by apply run), never from a PR merge
date: deploy is not merge, and a failed replace creates a host that served nothing.

## Session Errors

1. **Brief premise stale: the constant lock was already on main.** Recovery: the planning subagent read the wrappers. Prevention: re-derive a brief's "still to do" against `origin/main` before dispatching (already a work-skill rule).
2. **Present-tense production-state claim ("the running host serves the old wrappers") written without reading the apply runs.** Recovery: security seat found run 37846545572. Prevention: before writing a claim about what a host serves, list the replace runs since the payload merged (`gh run list --workflow apply-web-platform-infra.yml`) and cite the run, not the host.
3. **Residue window keyed on a PR merge, then on the wrong replace run.** Recovery: read the ADR's own lifecycle record (server id and creation time) and the failed 2026-09-24 run. Prevention: a window boundary is an instance event; cite the run that created/destroyed the instance.
4. **Guard predicate exited inside `$(...)`, so a mis-aimed call read as clean.** Recovery: `|| exit 2` at every caller. Prevention: any guard helper called in a command substitution needs its abort checked at the call site; mutate a mis-aimed call to prove it.
5. **Read a suite's rc through `echo "$(basename "$t") rc=$?"`.** Recovery: re-ran with `rc=$?` on its own line. Prevention: the documented trap; capture rc before any expansion that runs a command.
6. **A new fixture write site moved the fixture-relative ratchet (+1 per suite).** Recovery: `assert_fixture_dir` before the write. Prevention: run the fixture ratchets before the first commit of any `*.test.sh` edit (work step 6.6).
7. **Scope of the guard was one directory.** Recovery: structural-enumeration seat mapped the writers. Prevention: see Key Insight; routed to plan sharp edges.
8. **A one-statement `local a=… d="$OUT/$a"` and a "operator direction" phrase tripping the no-human-steps lint.** One-off; recovered immediately.

## Tags

category: security-issues
module: apps/web-platform/infra
