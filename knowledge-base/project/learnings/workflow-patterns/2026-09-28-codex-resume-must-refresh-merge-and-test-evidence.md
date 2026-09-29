---
title: "Codex resume must refresh merge and test evidence"
date: 2026-09-28
category: workflow-patterns
tags: [codex, resume, merge, testing, migrations]
---

# Codex resume must refresh merge and test evidence

The resumed PR had eight conflicts with current main. Its reported green checks
were CLA and CodeQL checks; the conflicting merge ref prevented the PR test
workflows from running. Resolve the merge before treating the check set as a
verification result.

A fresh focused run exposed three stale assertions: a settings repository call
gained an optional argument; the SQL upsert referenced `EXCLUDED`; and the
generation-admission function used `CREATE FUNCTION` with its predicate after
the acceptance assignment. Read the current function before changing its test,
scope assertions to executable syntax, and rerun before relying on the result.

Main allocated migration ordinal 144 to checkout state while this branch used
the same ordinal for Codex rebinding. The unshipped Codex migration moved to 145
with its tests and rollback-ledger reference.

The dev-ledger parity workflow still reads the applied filename and body hash,
not merely the current migration ordinal. Renaming an already-applied migration
to a new ordinal can leave the old dev row orphaned even though the new name is
correct against main. Run the existing reconciliation workflow in dry-run mode
first. If it reports later rows, preserve that refusal; do not opt into the
destructive later-row override without an explicit review of each affected
rollback.

The CI job log endpoint may require `gh api --allow-escape-sequences`; capture
the response to a file and strip ANSI control sequences before printing a
bounded excerpt. A local focused green run does not correct stale CI evidence
until the fix is pushed and the new PR checks complete.

On 2026-09-29, a commit hook was started before the focused SQL assertion suite
was green and consumed an 88-minute repository gate before failing. Finish the
focused red/green loop before starting commit hooks; do not overlap edits with
the full gate.

The first resumed combined Codex test run exposed an old WebSocket fixture that
ended without a terminal status. Update synthetic streams to emit the same
terminal lifecycle event required from the runtime before treating the suite as
green. A trigger-removal mutation must target a uniquely attached WORM function;
removing one of two triggers sharing the same function does not remove that
function's ledger coverage. The installed Pencil CLI only reads format 2.14,
while the committed wireframe is format 2.18; the newer CLI install was
interrupted after repeated `TAR_ENTRY_ERROR Unknown system error -122` failures.
Do not retry the npm installation loop without resolving the host's install
environment; the wireframe screenshot gate remains blocked.

On 2026-09-29, current main advanced to `ec5b2fcede99602edfee43961d77e4dd5677fb10`.
The merged feature worktree had local edits, so `cleanup-merged` correctly
refused to pull there; fetch the updated main ref and reconcile after focused
tests, rather than assuming the old merge base is current.

Session-start cleanup initially could not write its state locks in the sandbox.
The elevated retry acquired them successfully. Full-file legal patch output and
a piped diff preview were truncated; focused hunks and captured comparisons
resolved the tooling errors. Mirror comparisons must use current main's
baseline, since the merge can reduce inherited drift.
