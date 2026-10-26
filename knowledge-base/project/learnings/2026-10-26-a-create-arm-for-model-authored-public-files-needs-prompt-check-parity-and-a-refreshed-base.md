# Learning: a create arm that turns model text into public plugin files fails in the seams, not in the gates

## Problem

WikiSkill Phase 2 (#10550) added a dark-launched "create arm" to the weekly compound-promote proposer: a manual
`input:"patterns"` + `allow_create:true` run renders a brand-new skill (SKILL.md, PURPOSE.md, Cursor stub, README counts,
promotion-log row) from structured model fields and opens a DRAFT PR. Every gate from the plan was implemented and green
(shape allowlist, overlap gate, budget gate, skill-security-scan LOW-RISK, exact six paths). A 13-seat panel, a 10-seat
fix-round panel and a 4-seat verification pass still found about 45 issues. Almost none were in a gate; they were in the
seams between gates and the world they were written against.

## Solution

What the review found and what fixed it (each is a class, not an instance):

1. **A check the prompt never states is a deterministic wasted single-shot run.** The shape rules (300-char field cap, markup
   characters, no double quote in a description, 60-char ident cap stricter than the pattern reader's slug limit) were
   enforced but absent from the model prompt, and the call has no retry. Every numeric and shape rule is now an exported
   constant read by the prompt, the check and the trailer; prompt tests assert anchored sentences, not bare numerals (the
   test nonce contained the digits).
2. **A scan over JOINED text finds phrases no single item contains.** The rendered-file instruction-risk check joined all
   segments with a newline and its gap class `[^.]` spans newlines, so two clean bullets ("Ignore flaky runs" and "Rerun all
   tests") refused a valid skill after the model spend. Scan per line and use `[^.\n]`.
3. **A persist step that builds from a clone taken at the start of a long run silently reverts later edits.** `safeCommitAndPr`
   stages full file bytes from the run-start clone onto the live tip, so a README edit merged mid-run is reverted in the PR
   diff. Refresh the clone at the start of the persist step, re-run the checks on the refreshed tree, and compare origin/main
   blob ids of the files you will overwrite (blob-scoped, so unrelated merges do not refuse).
4. **A credentialed URL in `.git/config` is readable by every script spawned in that clone.** Strip the token from
   `remote.origin.url` before any script spawns and restore it only for the final fetch and the commit helper; never forward
   a raw git error from a tokenized call to Sentry (git can echo the remote). Return a closed evidence object instead.
5. **A denylist over model prose is a tripwire, not a control.** Verb-gate the credential nouns, add file nouns and flag
   variants, state the false positives, and put the real control on the fixed reviewer checklist and the draft PR. Fixed
   server text is exempt by exact line; model lines are never exempt by prefix.
6. **Two arms that share an identifier namespace need shared run state.** The create arm picked a pattern whose cluster hash
   the edit loop had just opened in the same run; both use the branch `self-healing/auto-<hash>-<date>`, so the own-PR replay
   lookup found the EDIT PR and the marker said `opened`. Filter owned hashes before the model call and require the arm's own
   body line on a replay hit.
7. **A detection keyed on a best-effort side effect fails open.** One-open-create detection required a label that is applied
   best-effort; detect by head-ref prefix + body line + head repo (a fork PR must not count, and must not block the arm).
8. **Closed vocabularies need a two-way parity test against the runbook with exact tokens.** The first parity test used a
   loose `\b` fallback and dead regex alternatives that only matched comments.

## Key Insight

For a feature whose output is text a model wrote and a human will merge into a public repository, the gates are the easy
part. The defects live where one stage hands a value to the next: prompt to check, run-start state to persist-time state,
one arm's identifiers to the other arm's, a credential to the processes spawned beside it, and a guard's vocabulary to the
runbook an operator will read. Test those seams with a real git remote and the real spawn path, and give every refusal
a closed token so the operator can diagnose it without SSH.

## Session Errors

1. **The PR's worktree directory was removed mid-pipeline and a fix agent lost its uncommitted work.** The cause was not
   established (the lease window of 240 minutes had likely elapsed in a very long multi-round review; unverified).
   Recovery: recreated the worktree from the pushed branch, reinstalled dependencies, took a 720-minute lease, re-dispatched.
   **Prevention:** commit and push after every agent unit (it limited the loss to one unit); in a pipeline expected to run
   past the lease window, renew the lease at phase boundaries.
2. **The planning agent's decision rows failed `technical-ruling-gate.sh`** (planner-authored "Ruled by planner" rows, a
   non-closed operator category, a parenthesised tag before the colon). Recovery: rewrote or removed the rows. **Prevention:**
   the post-plan gate already catches it; the planner should run it before returning.
3. **Planning used 3 CTO spawns against the pipeline's 2-spawn cap.** Recovery: none needed; recorded in session-state.
   **Prevention:** count spawns inside the planning subagent against the same cap.
4. **Semgrep crashed with an io_uring error on this host.** Recovery: `EIO_BACKEND=posix semgrep -j 1`. **Prevention:** note
   the variable in any semgrep invocation on this machine; the review skill is near its byte ceiling, so this stays here.
5. **A lint warning (`no-regex-spaces`) in new test code surfaced only after the panel.** Recovery: `{4}` quantifier.
   **Prevention:** run eslint on touched test files before the panel, not after.
6. **`git worktree remove` on locked agent worktrees printed "use 'remove -f -f'".** Recovery: left to post-merge cleanup.
   **Prevention:** none needed (one-off).

## Tags
category: workflow-patterns
module: compound-promote
