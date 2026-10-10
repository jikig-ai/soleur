---
title: "Probe workflow state after a cancellation timeout"
date: 2026-10-09
category: workflow-patterns
module: github-actions
---

## Problem

Cancelling superseded guard run `37950491879` returned HTTP 504. A subsequent
shell command succeeded, so the shell's final exit status hid the failed API
request. A state probe showed the old run still queued and its replacement
pending; the first response did not prove cancellation.

## Prevention

Keep API mutations and dependent shell actions separate. Inspect each response,
then read the run's status and conclusion. Retry a transient cancellation only
for the identified superseded run, keeping the replacement watch armed.
A submitted cancellation is a request, not a terminal verdict. Claim completion
only after the state probe confirms it; exclude superseded cancellations from
the effective current-head check verdict.
