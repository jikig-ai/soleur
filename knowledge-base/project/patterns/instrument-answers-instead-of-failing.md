---
title: "Instrument answers instead of failing"
summary: "A broken probe, classifier or helper returns a result-shaped answer that reads as clean; separate failed, empty and absent states and add positive controls on the decider itself."
status: open
opened_on: "2026-10-24"
tags: [fail-open, measurement, instruments, guards]
evidence:
  - knowledge-base/project/learnings/2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md
  - knowledge-base/project/learnings/2026-09-20-every-instrument-that-answered-instead-of-failing.md
  - knowledge-base/project/learnings/2026-08-17-an-empty-read-is-three-states-and-my-guard-shipped-two-fail-opens.md
  - knowledge-base/project/learnings/2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift.md
  - knowledge-base/project/learnings/2026-09-10-i-graded-lines-when-the-unit-was-the-command.md
required_reading: false
---
## Root cause

A broken measuring instrument does not raise an error. A grep pattern that matches every line, an
extraction that truncates a program, a helper clobbered by a sourced file, or a decider that always
calls pass each returns something already shaped like a result, so nothing prompts a second look.
Detectors then collapse distinct states (query failed, query answered with nothing, rows returned;
step absent, skipped, or unfinished) into one branch that fails toward silence or a benign skip.
A control on the dispatcher proves dispatch only, not the decision.

## Fix

Keep each state separate in the code path (a failed read, an empty answer and a healthy answer take
different branches) and treat absence, unknown and cancelled as failures unless an explicit skip is
recorded. Verify an instrument with a positive control that must fire before reading its output, put
the control on the deciding function and not only on the reporting wrapper, and drive the gate's real
block against a modelled dependency that refuses unexpected invocations.

## Evidence

- knowledge-base/project/learnings/2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md
- knowledge-base/project/learnings/2026-09-20-every-instrument-that-answered-instead-of-failing.md
- knowledge-base/project/learnings/2026-08-17-an-empty-read-is-three-states-and-my-guard-shipped-two-fail-opens.md
- knowledge-base/project/learnings/2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift.md
- knowledge-base/project/learnings/2026-09-10-i-graded-lines-when-the-unit-was-the-command.md
