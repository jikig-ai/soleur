# Learning: an inline copy claimed the library's contract, and its parity audit pinned the copies to each other, not to the library

## Problem

S5 (the last slice of the argv-credential sweep, #9597) converted four Better Stack posting scripts of the registry cloud-init to an inline form of `scripts/lib/bearer-curl.sh`
(the host has no checkout). The template comment, the ADR and the commit all called it "the inline form of the library", and the battery pinned the four copies byte-equal.
Six of ten review seats independently found the same defect: the library trims trailing whitespace before judging (`bc_ok`), the inline judge did not. A stored token with a trailing
newline worked on the old argv form (curl sends the trimmed header), so the merge-triggered host replace would have silenced every registry row, with a marker nobody can read on that host.

Three further things the same session measured:

- **A parity audit between copies is not a parity audit against the leader.** The audit would stay green for four identical copies that were all wrong in the same way. The fix pinned the
  judge byte-identical to the canonical inline `_bearer_ok` (modulo the template escape) and ran an accept/reject set, so the copies are pinned to the thing they claim to copy.
- **A carve-out ("decline the replace by dropping one trailing commit") is a claim to execute, not to design.** Review fixes landed as extra commits mixing neutral and registry hunks, so
  `git revert` conflicted in the battery and the ADR. Recovery: rebuild the branch non-interactively as exactly two commits (`git commit-tree` of a "no registry" tree and the final tree), then
  prove the carve-out by reverting the second commit in a scratch worktree, adding the one owner line it needs, and running the battery (688/0). When `origin/main` moved during the rebuild, the
  trees had to be re-overlaid with `git merge-tree --write-tree --merge-base=<old main> <ours> <new main>`; building a tree on the stale main would have silently reverted main's new commits
  (a file-count comparison against `origin/main` caught it).
- **Header and ADR text written for the final state is false in the carve-out state.** "Baseline E holds only the two cla-evidence rows" was true only with the registry commit. State-neutral
  wording plus a battery row that requires an owner line above any non-cla row made declining the replace leave true text.

## Solution

Trim trailing whitespace in all four inline copies and pin the trim and the refusal marker byte-equal across them; compare the judge to the canonical body; execute trailing newline, space, tab, CR
and CRLF tokens through all four scripts; require exactly one expansion of the raw token per script (a second raw read after the judge is invisible to every other check); make headers
state-neutral; keep the registry changes in one commit and verify the revert by running it.

## Key Insight

When prose says "X is the inline form of Y", the contract to pin is Y's, and the test must compare X to Y (or to Y's canonical body), not X1 to X2. And any recovery path the plan promises
("drop one commit") must be executed before the review, then re-executed after the last fix, because every fix commit is a chance to entangle it.

## Session Errors

1. **The inline judge was described as the library's inline form and did not trim** — Recovery: trim + canonical-judge comparison + whitespace rows. **Prevention:** diff every behavior of a claimed copy against its leader (trim, scrub, refusal) before writing "inline form of"; parity between copies is not parity with the leader.
2. **The carve-out was designed but first verified against commits that review fixes then entangled** — Recovery: rebuilt as two commits and re-verified. **Prevention:** run the carve-out revert in a scratch worktree after the LAST fix, not once at planning.
3. **A rebuild on a stale main tree would have reverted main's merged commits** — Recovery: merge-tree overlay, file-count compare against `origin/main`. **Prevention:** after any history rebuild, `git diff --name-only origin/main HEAD` must equal `git diff --name-only origin/main...HEAD`.
4. **The first reorder-mutation builder matched `declare -F bc_curl` instead of the call** — Recovery: anchor on `bc_curl [a-z]`. **Prevention:** a mutation builder must assert its edit hit the construct, not a guard line mentioning the same token.
5. **`s4_run` dropped an injected `HCLOUD_TOKEN` (composite-exported, undeclared in the workflow)** — Recovery: added to the harness exemption list. **Prevention:** when executing a real step body, list the env names its job gets from composites.
6. **Floors went stale after the manifest grew (S3 36 vs 41, S4 20 vs 21) and the negative-canary floors counted runs that planted no canary** — Recovery: floors re-derived; canary floors count only runs carrying the canary. **Prevention:** count what the label claims.
7. **Operator hints in echo text still printed the argv `curl -H` form (Rule E does not read echo)** — Recovery: `printf ... | curl -H @-`, plus a hint row with planted positives. **Prevention:** grep the exposure's spelling in echo/comment text when converting a class.
8. **`git stash list` was denied by the PreToolUse hook while comparing shellcheck baselines** — Recovery: `git show <ref>:<path>`. **Prevention:** already hook-enforced.
9. **A review seat deleted its own sandbox mid-run and reported suite failures from the vanished directory** — Recovery: discarded the result and re-ran both suites on the PR tree. **Prevention:** brief seats to remove a sandbox only after the last command finishes.
10. **Closing text promised actions several times and the Stop hook blocked the turn** — Recovery: stated BLOCKED with the real reason. **Prevention:** when waiting on background seats, name the blocker without future-tense promises.

## Tags

category: integration-issues
module: argv-bearer-sweep, cloud-init-registry, review
