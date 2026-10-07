# Learning: a docs-only ADR/plan PR needed four review rounds because every fix round added new unmeasured claims

## Problem

PR 9722 (plan + ADR-276 proposal + runner-supply memo for reducing hosted-runner CI demand) was
docs-only, yet took a five-seat panel, a two-seat fix-round, one verification seat and three fix
commits. Each fix commit introduced errors its writer had not measured:

- The first fix wrote `all_outside_collaborators` as the strict fork-PR approval value. The GitHub
  OpenAPI enum is `first_time_contributors_new_to_github | first_time_contributors | all_external_contributors`.
- It also wrote "36 workflows trigger on `issues`". A YAML-aware parse of `.github/workflows/*.yml`
  gives 4 (bare `on:` parses as boolean `True`, which is why a naive grep over-counts).
- The second fix defined an admin-merge "full-battery marker" as a completed `CI` run on the head
  SHA, which an affected-mode PR run satisfies equally. The verification seat caught that.

A history seat also reported a P1 ("latest ADR on origin/main is 271") that was a stale-ref read;
`git ls-tree origin/main` showed ADR-275, so the plan's claim was right.

## Solution

- Verify a seat's claim about `main` against a fresh `git fetch` + `git ls-tree origin/main` before
  acting; refute it in the disposition if it fails.
- For every number or enum a fix ADDS, run the falsifying command in the same edit (OpenAPI spec for
  an enum, a YAML parse for trigger counts) and name the command in the document.
- Treat a marker/flag/discriminator introduced to distinguish two modes as unfinished until you can
  name the API field that separates them.
- Run the fix-round and the single verification pass over the FIX RANGE only, with seats briefed to
  grade the new text as its own change.

## Key Insight

On a documents-only PR the defects are claims, and a fix commit is the least-audited surface in the
diff: it is written fast, from a seat's summary, while the author holds the old defect in mind.
Three rounds of "fix, then a fresh seat finds the fix's own errors" is the expected cost unless the
fixer runs the falsifying command for each added claim.

## Session Errors

1. **First job-minute pass overcounted cancelled jobs (9,392 vs 7,456)** — Recovery: re-measured with
   runner-less jobs excluded — Prevention: filter `runner_id > 0` and conclusion != skipped before summing.
2. **History seat's stale-ref P1** — Recovery: `git ls-tree origin/main` — Prevention: brief seats to
   `git fetch origin main` first and cite the command for any claim about main.
3. **Fix commit 1 added a wrong API enum and a wrong trigger count** — Recovery: fix-round seats ran the
   falsifying commands — Prevention: the writer runs the command for each number/enum it adds.
4. **Fix commit 2 defined an indistinguishable marker** — Recovery: verification seat — Prevention: name
   the API field that discriminates before calling a marker defined.
5. **`emit-review-trailer.sh --risk-tier` rejected a descriptive value** — Recovery: `--risk-tier none` —
   Prevention: pass one of `none|single-user incident|aggregate pattern`.
6. **Session-start `.mcp.json` restore overwrote an uncommitted local edit** — Recovery: backed up to the
   scratchpad first — Prevention: back up any modified tracked file before the restore step.
7. **Brief claimed no tracker issue existed; #8683 did, and a sibling session was live on the target
   worktree** — Recovery: collision probes (issue search, worktree mtimes, process cwd) and an operator
   question — Prevention: the one-shot collision gate already prescribes these probes; follow them before
   filing an issue.

## Tags
category: workflow-issues
module: review, docs-pr
