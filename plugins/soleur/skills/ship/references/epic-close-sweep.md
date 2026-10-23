# Epic-Close Domain-Leader Sweep — full spec

Loaded by ship Phase 7 Step 3.9 when its trigger fires. The body keeps only the
trigger and the load directive; this file is the executable spec.

Phase 5.5's CMO gate is PR-scoped; three classes of opportunity exist only at
epic scope — (a) **aggregate claims** ("shipped the whole checklist in four
days" lives in no single diff), (b) **cross-child meta-findings** (the pattern
across children is often the arc's strongest claim), (c) **deadline-shaped
timing** (a synthesis pegged to an external article/launch decays on a
calendar no per-PR slotting asks about).

## Trigger

This merge completed a tracked epic — an issue it closed is a child of an epic
whose other children are all CLOSED (the epic issue itself closing also fires).

## Detection

1. `gh pr view <PR> --json closingIssuesReferences` — the issues the merge
   closed (covers `Closes`/`Fixes`/`Resolves`, multiple issues).
2. `gh issue view <N> --json parent` for each issue's epic; empty `parent` →
   grep the issue's body and comments for `Tracked by #N`.
3. `gh issue view <epic> --json body` — extract child task-list rows
   (`- [ ] #N` / `- [x] #N`); when the body carries none, fall back to
   `gh issue view <epic> --json subIssues` and read each child's `state`.

Fire only when ALL hold: a closed `#N` appears among the children (or is the
epic), the child count is ≥2, and every child is closed. An empty child list
is "cannot confirm" — report "epic-close sweep inconclusive for #<epic>";
never fire on a vacuous truth, never skip silently.

## If triggered

1. **Per-child disposition census.** For each child, confirm a Phase 5.5
   disposition exists — a filed brief, a `content-strategy.md` row, or an
   explicit skip-with-reason. A child whose ship tail was resumed manually or
   after a runner failure silently skips Phase 5.5; the census catches that.
2. **Arc-level CMO assessment.** Spawn the CMO agent: "Assess content and
   distribution opportunities from the COMPLETED epic, not any single PR:
   aggregate claims, cross-child meta-findings, external news pegs the epic
   cites, and whether a synthesis piece complements or supersedes the
   per-child briefs. For each child with no disposition, produce a
   retroactive brief."
3. **Interactive:** ask create-now / schedule / skip (Phase 5.5's options).
   **Headless:** auto-file the arc brief + retroactive child briefs (do not
   block). This runs post-merge — a `content-strategy.md` edit lands on a
   reaped worktree, so embed proposed rows in each filed brief's body or land
   them in a follow-up PR from fresh `origin/main`. An issue without a
   strategy row is an orphan (#1173).

## If not triggered

Skip to Step 4 silently.

## Why

Epic #10397 (7 children × 7 PRs) closed with 5/7 per-PR briefs and no
arc-level assessment — the synthesis surfaced only because the operator
asked. The two missed children (#10400, #10404) were both partial-ship tails
— paths a per-PR gate cannot cover. "Gate fixed" is not done — "gate fixed
AND missed case remediated" is done.
