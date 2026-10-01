---
date: 2026-09-18
category: machinery
module: github-actions-local-actions
related:
  - .github/workflows/scheduled-devin-docs-drift.yml
  - .github/workflows/scheduled-marketplace-drift.yml
  - .github/actions/sentry-heartbeat/
---

# Learning: `uses: ./` composite actions need `actions/checkout` — and `continue-on-error` makes the failure silent

## Problem

A scheduled workflow's job invoked a repo-local composite action
(`uses: ./.github/actions/sentry-heartbeat`) without ever running
`actions/checkout`. A comment at the top of the job asserted the
composite "resolves from the repo ref automatically" — a mechanism that
does not exist. Local actions resolve from the runner's checked-out
tree; without a checkout, GitHub emits
`##[error] Can't find 'action.yml' ... Did you forget to run
actions/checkout before running your local action?`.

The failure shipped green. The step carried `continue-on-error: true`
(deliberate — a Sentry ingest outage must not red the watcher itself),
which also swallowed the resolution error, so every run reported success
while the heartbeat never fired. This is exactly the silent-heartbeat
class the monitor exists to avoid (#7493): the thing that reports
liveness was itself dead, and nothing distinguished "alive and quiet"
from "never wired".

## Detection

Not by any fixture or lint — the repo's drift-check fixture suite
exercises the check step's `run:` body against synthesized docs, but no
suite models step *wiring* (a missing checkout is a job-graph property,
not a script property). It surfaced only on the watcher's FIRST live run
(35333427096), where the `##[error]` line was visible in the job log.

## Fix / rule

Any job that calls `uses: ./` needs `actions/checkout` first; sibling
convention is `persist-credentials: false`. When adding a step that
invokes a local composite, do not rationalize away the checkout — the
"inputs are remote anyway" argument (true for the check's HTTPS fetches)
does not extend to action resolution. After wiring any heartbeat or
notification step, verify it on the first real run's step list, not just
the job conclusion — `continue-on-error` makes conclusion a non-signal.

Fixed in #8280 (checkout added, comment corrected); verified live on
run 35340407015 where `Sentry check-in (final)` concluded success.
