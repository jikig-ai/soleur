# Learning: resuming a PR after a session where the plugin never loaded, and a shared baseline literal that every concurrent PR conflicts on

## Problem
PR #10101 (hosted must-ask lane, Ref #10054) finished work and review in a session where the Soleur plugin did not load, so compound and ship never ran. Resuming meant: a local review-triage commit that was never pushed, `origin/main` moved by several PRs, and a content conflict in `plugins/soleur/test/preflight-discoverability-test.test.ts`.

The conflict was the `BASELINE_DECLARED_PROBES` literal. This PR bumped 63 -> 64; main had since taken two other +1 bumps (kdeny grant, egress gateway probe) to 65. A line-level merge cannot combine three independent "+1"s on one number, and each side's comment block sits on the same lines.

## Solution
Keep main's two comment blocks verbatim, append this PR's block rebased to "65 -> 66", set the literal to 66, and run the test (179 pass) before committing the merge. The derived count, not the textual union, is what decides the literal.

## Key Insight
A hand-maintained counter that every concurrent PR must bump is a guaranteed merge conflict, and the "right" resolution is recomputation, not picking a side. Tracked as #10156 (append-only list instead of a literal).

## Session Errors
1. **Plugin did not load in the prior session; compound and ship were skipped** — Recovery: resumed via `/soleur:go` with an explicit compound-then-ship instruction — Prevention: the resume brief must state "verify plugin loaded" first; a missing plugin is a session error to file per `wg-every-session-error-must-produce-either`.
2. **Review-triage commit (fd533d97c6) left unpushed** — Recovery: pushed with the merge commit — Prevention: the review skill's trailer step should push, so PR HEAD matches the reviewed HEAD.
3. **Merge conflict on `BASELINE_DECLARED_PROBES`** — Recovery: recomputed to 66 and ran the suite — Prevention: #10156.
4. **`gh pr view` returned `mergeable: UNKNOWN` immediately after fetch/push** — Recovery: re-queried after a short wait (MERGEABLE) — Prevention: poll before concluding a PR is conflicted.

## Tags
category: workflow-issues
module: preflight-discoverability-test
