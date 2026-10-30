---
date: 2026-10-29
pr: "#11442"
issue: "#11424"
severity: workflow-mechanism
title: Running review seats as headless `devin -p` subprocesses
tags: [review, seats, devin-cli, headless, session-resume, sequential-fallback]
---

## Context

This session ran `soleur:review`'s 8-seat panel (plus coverage consult,
ADR-267 fix round, and verification pass) WITHOUT the Task/subagent tool —
seats ran as `devin -p` headless subprocesses, one per seat, against
`prompt-file`s under a `mktemp -d` scratch.

## What works / what bites

- **File writes are rejected.** A headless `devin -p` run outside the
  workspace cannot `Write` (e.g. to `/var/tmp/...` scratch) — the write is
  rejected non-interactively. Fix: instruct the seat to emit its ENTIRE
  report as its final stdout message; capture `> seat.report.out`.
- **Session resume:** `devin -r <session-id> -p` continues a seat's session —
  the fix round reused the same 8 session ids so each seat kept its own
  prior-finding context (FIX-VERIFIED/FIX-MISS contract). Session ids are
  printed at spawn.
- **Session locks:** resuming while a session is open fails with
  `session_locked` — retry after the holder exits; check `ps -p <pid>`
  before launching the resume.
- **Concurrency:** parallel `devin -p` instances work (backgrounded with
  `&` + `wait`), but seat dispatch is still *sequential-fallback* class —
  disclose `Reviewed-Coverage: sequential-fallback` in the trailer and never
  claim independent native-Task coverage.
- **`--respect-workspace-trust false` + `--verbosity 0`** keep seat output
  to just the report.
- Seat prompts must carry: worktree path, the exact `git diff A..B` range,
  report-only/no-edit/no-write contract, and the output format.

## Failure modes seen

- Seat exited rc=0 with NO report (the write-wall swallowed the report
  attempt) — re-run/resume with the stdout-report instruction.
- A `pgrep -f` self-match blocked a process check — use captured PIDs or
  `list_runs`/`kill_mine`, never `pgrep -f`.

## Prevention

Reusable prompt contract for future headless seats lives in this file; the
scratch layout used was `/var/tmp/soleur-11424-run/{review,fixround}/`.
