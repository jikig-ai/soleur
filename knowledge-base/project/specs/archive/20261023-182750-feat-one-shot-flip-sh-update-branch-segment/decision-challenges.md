# Decision Challenges

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Regression test lives in a new suite file instead of a row in an existing suite | technical | Ruled by CTO agent, 2026-10-23: keep a separate suite - only a stub that can return the live 400 makes a revert go red, and the shared operator-ack-guard stub answers 200 to everything; maintenance cost is one copied pty driver, extract a shared helper when a third flip.sh suite appears. Disclosed in the PR body. |
| Mutation matrix and harness rows are one-time PR evidence, not permanent suite content | technical | Ruled by CTO agent, 2026-10-23: keep the permanent suite to scenarios 1-4 so it cannot become slow or flaky; record the mutation runs once in the PR body. |
| Append-before-flip leaves an orphan audit row on any failed write | technical | Ruled by CTO agent, 2026-10-23: out of scope for this fix (the audit table is WORM); track as a follow-up issue with candidate fixes (outcome-update row, status column, append after confirmation). |
