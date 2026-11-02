# Learning: classify a drain's revealed pairs with the read recorder, and size the slice with one all-edges trial

## Problem
S4 PR4b (#10959) had to drain held-back edges of the affected-index baseline. Declaring a code file makes the audit read it, so every path it names becomes a new pair for that suite; 197 boundary lines had to be classified real read vs mention, and the plan expected about 36 edges.

## Solution
- One throwaway trial declared the whole candidate slice at once (no accept rows) and ran `ratchet --report` once: it gave per-suite reveal counts (130 new pairs, 36 stale lines = exactly the declared edges) instead of 36 separate runs, and `audit --all-refs` supplied every boundary line (the ratchet report prints at most 3 per pair).
- `scripts/audit-suite-reads.sh record --mode check` over the slice suites (two recordings each, about 15 s per suite) listed the files each suite actually opens. Opened in both recordings: real read, declare the exact file. Not opened: mention, accept only if the line kind is in the closed list. Six suites did not record cleanly (rc != 0 under `env -i`) and three were bulk readers (more than 1000 files opened): hold those.
- A code line in a file the suite only greps (never executes) needed a new accept-reason kind; the CTO ruled it with three conditions (recorder, suite text, limits on the mention-holding file).
- Result: 11 of 117 edges declared, 9 real reads, 25 accept rows (18 pairs), baseline 1640 to 1629, round 2 revealed 2 pairs, fixpoint at round 3.

## Key Insight
Reading 197 lines by eye is slower and less reliable than recording what the suites open; the recorder is evidence, the static line kind decides. The yield of a drain is bounded by the holds (hot file with an accept row, more than 10 rows, unreliable recording, bulk reader), not by the cap.

## Session Errors
1. **Plan quoted a truncated CI run id (40223185, real 40223223185).** Recovery: listed runs by full SHA. **Prevention:** resolve run ids from `gh run list --commit <sha>`, never copy a number from a plan.
2. **Bash hooks denied whole calls (a recursive delete with a variable, a process-pattern search, a sleep chain, and later a heredoc that merely quoted the blocked flag).** Recovery: explicit paths, rc files, reworded text. **Prevention:** none beyond the existing hook messages.
3. **A task notification's exit 0 hid test-all-affected.test.sh rc=1 (case m7 SIGTERM under load).** Recovery: read the log's own rc line, re-ran the suite alone (0 failures). **Prevention:** already documented (read the rc file, not the notification).
4. **Three of six review seats stalled and never delivered text; one P1 lead (accept rows for the rule-body data files) was refuted by recorder data and suite text.** Recovery: resumed with "reply now as final text", ran their core checks inline, recorded degraded 3/6 coverage. **Prevention:** brief seats with the deliverable at spawn; verify a P1 lead against the recorder before acting.
5. **Accept file assumed sorted; helper script path doubled.** Recovery: inserted rows after the last same-suite row; fixed the path. **Prevention:** check an ordering convention with `sort -c` before relying on it.
6. **Full local affected gate queued for hours (touching the index is a runner change).** Recovery: documented in runbook section 7; CI is the merge gate. **Prevention:** runbook sentence added.

## Tags
category: workflow-patterns
module: ci-pr-affected
