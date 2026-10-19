# Learning: a record PR must use the strongest word the evidence supports, and no stronger

## Problem

PR #10506 was a docs-only record of the second read-only `wipe_check` (run 39136900735): the exit-34 line carried
`has_hooks_d=1 lf_entries=0 offlist_n=1`, read through the runbook's existing table row as "the only off-list entry is a
directory named `hooks`, contents unread". The draft passed the access suites, markdownlint, the infra lint, the
forbidden-word grep and a CLO review at plan time. A six-seat review then found one P1 and about ten P2s, all of the same
kind: wording stronger than the evidence behind it.

- "neither run **measured** `lock_residue` or `store_root_repos`" was false. The host script computes both before the
  off-list verdict and exit 34 discards them before anything prints. The true word is "printed".
- A `Superseded 2026-10-18` marker under a hold sentence read as lifting a hold that only one run's lift had touched, and
  the clause "does not read C1's parenthetical for a later `wipe`" was an interpretation of C1 the CLO had barred.
- The session-state file quoted a private owner chat message to say a blocking acceptance criterion was "met".
- The runbook said "posting to #6897 stays the owner's act" while two comments by the owner's login already existed on that
  issue and its sibling. The agent had posted them, and a review seat read them as the owner's.

## Solution

Every fix narrowed a sentence to what a named command had shown:

1. Three strengths exist and the draft had two words for them. **Printed** (it appears in the public log, checked with
   `grep -F`), **computed but not printed** (code order, read from the script), **not measured** (nothing ran). Use the
   word that matches, and say which kind of evidence it is.
2. A dated marker names the sentence it qualifies by quoting it, says "as to run N only", and says nothing about how the
   hold binds a later run. A marker that disclaims a hold must not also restate it.
3. A committed file never quotes a private chat message as an approval. Record the approval as inferred and flag it in the
   PR body for the owner to confirm.
4. When the diff states who posted something, check the account that posted it, not the account name. A shared login makes
   an agent's comment look like the owner's.

## Key Insight

A record PR is a list of claims about a system, and its checks (suites, lints, a forbidden-word grep) test the text
for the words the author thought to ban. None of them asks "which word does this evidence license". Read each added
sentence against the weakest evidence behind it, and let a seat that did not write it run the falsifying command. Six
seats, each given a different lens (provenance, convention, disclosure, accuracy, user impact, legal claims), found 30
items; no single seat found more than six, and only the accuracy seat found the P1.

## Session Errors

1. **Planner recorded CLO rulings with Class `technical (legal)`; the technical-ruling gate failed on five rows** —
   Recovery: reclassified to `operator (legal-risk)`, gate PASS — **Prevention:** `technical-ruling-delegation.md` §6 now
   names the Class for a CLO ruling, and `technical-ruling-gate.sh --branch` runs right after editing
   `decision-challenges.md`.
2. **Draft used "measured" where the evidence was "printed" (P1), plus two other overclaims** — Recovery: six-seat review,
   fixed inline — **Prevention:** classify each added claim as printed / computed-not-printed / not-measured and run the
   falsifying command before writing it.
3. **I posted the run result and the addendum to #6897 and #9066 under the owner's login; the CLO later ruled agents do not
   post (L-5(i))** — Recovery: told the owner, removed every claim about who posted from the committed files, flagged the
   comments in the PR body — **Prevention:** when an addendum says "post to X", check the runbook's posting rule
   (`Reading the exit-34 line`, the owner-posts sentence) for who posts before posting, and ask when the rule and the
   instruction differ.
4. **A review seat attributed those comments to the owner because they carry the owner's login** — Recovery: noted in the
   PR body — **Prevention:** a seat checking "who posted" needs the session's own record, not the account name.
5. **session-state.md quoted a private owner message to mark AC8 "met"** — Recovery: reworded as inferred approval, flagged
   in the PR body — **Prevention:** never put a private chat quote in a committed file.
6. **The Stop hook twice flagged a closing line that named an action I had not taken** — Recovery: stated "Paused: <reason>"
   or armed a Monitor — **Prevention:** end a turn on an action taken, or on one `Paused:` sentence naming the thing
   being waited on.
7. **`git fetch` from the bare repo root failed ("must be run in a work tree")** — Recovery: ran from the worktree —
   **Prevention:** chain `cd <worktree> && ...` in one call.

> **Superseded 2026-10-19 (#6897), as to "contents unread" for a line that carries `hooks_pre_receive_f` and `hooks_other_n`:** entry names and types under `hooks` were counted on the host and no file content was read; owner, mode and content remain unread.

## Tags

category: workflow-issues
module: knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274
