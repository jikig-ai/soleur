# Learning: an orphaned WIP draft PR can be the only carrier of an arc's institutional knowledge — salvage with a fresh-branch hybrid, never a rebase

## Problem

The edge-coverage-residuals arc (issue 10117) shipped its deliverable through
two repackaged PRs (10237, 10242) while the original WIP draft (PR 10190) stayed
open — carrying 5 learnings, the spec/plan/brainstorm, and two normative
cross-reference bullets that existed nowhere else. A bare "close as superseded"
would have destroyed the arc's durable knowledge; a rebase-and-merge of the
stale branch would have replayed its deliverable commits against their own
evolved merged descendants (conflict churn + stale-text reversion risk).

## Solution

CTO agent ruled (2026-10-14) a hybrid option C, executed as one-shot PR 10335:

- Salvage onto a FRESH branch off main tip — copy each file verbatim via
  `git show <source-branch>:<path>`, so the stale branch never enters the diff.
- Learnings land at their LIVE paths (archive-gate exempt); planning docs land
  DIRECTLY at `*/archive/<ts>-<basename>` destinations — the
  `wg-kb-artifacts-archived-in-pr` gate only requires the files live under
  archive/ in the diff, so a fresh branch skips the move-commit entirely.
- Port only the normative pointers (the two bullets citing the learnings),
  extracted verbatim from the branch by anchor grep. Audit the branch's OTHER
  diffs on the same files before porting: the branch also carried a stale
  paragraph variant and two deletions of bullets main still needs — all three
  were main-side drift, not salvageable content.
- Retarget only the pointers a LIVE file will dereference (the learning's
  `related_artifacts` frontmatter → archive path). Dead pointers INSIDE the
  archived docs are convention-tolerated — ~100 sibling archive sets dangle
  identically, and fixing them breaks the byte-verbatim contract.

## Key Insight

1. **"Deliverable merged" does not mean "branch disposable."** Enumerate the
   branch's full file list against main before closing — the doc trail and the
   learnings ship on the same branch as the code and die with it.
2. **The archive gate accepts direct-at-destination placement.** Salvage does
   not need to re-enact history (land-live-then-move); it only needs the end
   state the gate checks.
3. **Re-verify verbatim claims against the ref, not the checkout.** Two review
   seats lacked exec tooling; the lead's `diff <(git show <branch>:<p>) <p>`
   and `gh` probes against live PR/issue state are the independent arm.
4. **A stale branch is a diff you must audit hunk-by-hunk.** "Copy everything"
   is wrong twice over: main's evolved text must win where it drifted, and the
   branch's deletions of still-live main content must not be ported.

## Prevention

- Before closing any superseded draft PR: `gh pr view <N> --json files` and
  `git diff --name-status $(git merge-base origin/main <branch>)..<branch>` —
  if any added file is absent on main, it is salvage, not cleanup.
- When a review seat reports "no exec/gh — reconstructed from manifest": the
  lead re-runs every GitHub-side claim (PR/issue state, merge SHAs, file
  lists) and every byte-identity check before merging.

## Session Errors

- A `decision-challenges.md` row wrote `Ruled by CTO agent, <date> (verbatim
  from brief):` — a parenthetical between date and colon broke the
  technical-ruling gate's `^Ruled by (CTO|CLO) agent, <date>: ` regex.
  **Prevention:** the gate catches it mechanically; write parentheticals
  inside the decision text, never inside the prefix.
- A verification step diffed `origin/main...HEAD` while the appended bullet
  was still uncommitted and read 0 lines. **Prevention:** verify committed
  diffs against committed state; for uncommitted work diff the merge-base
  against the working tree.
- First lint attempt invoked `markdownlint-cli2`; the repo pins `markdownlint`
  (markdownlint-cli). **Prevention:** check `node_modules/.bin/` before
  guessing the binary name.
- Review seats (no exec tool) could not run `gh pr diff`; coverage relied on
  the plan's file manifest. **Prevention:** the lead independently verifies
  the complete file list (`gh pr view <N> --json files` on both sides) — done.
- The plan-phase subagent had no Task tool and ran the research fan-out +
  review panel inline. **Prevention:** documented in session-state.md Errors;
  acceptable on a mechanical-copy plan, risky on a mechanism-design one.
- A plan-phase commit was blocked by `guardrails.sh` — the ambient shell CWD
  was the bare repo root. **Prevention:** embed `cd <worktree> && git -C
  <worktree> commit` so the precommit guard's target resolution sees the
  worktree branch.
- The first `run_subagent` spawn failed on a transient connection error;
  retry succeeded. **Prevention:** none — transient; retry once before
  redesigning the dispatch.
- `cloud-detect.sh` reported `not-local:no-devin-env`. **Prevention:** none —
  informational; proceed normally per the skill's cloud-mode rule.

## Tags

category: workflow-patterns
module: one-shot, git-worktree, archive-kb, review
