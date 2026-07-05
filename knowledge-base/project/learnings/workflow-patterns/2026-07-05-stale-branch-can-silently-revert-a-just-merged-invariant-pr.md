# Learning: a concurrently-open stale branch can silently REVERT a just-merged small PR

## Problem

Earlier in the same session I merged PR #6014 — a small "record the §(c) LB-weight
invariant" change touching three files (ADR-068 amendment, `moved-block-wedge-cutover-5887.md`
runbook §(c) callout, `server.tf` HARD GATE comment). I verified it on `origin/main`
immediately after merge (`git show origin/main:…ADR-068… | grep -c "LB-weight gate §(c)"` → 1).

Later, building the follow-up autonomous-cutover PR, a subagent reported the runbook "lacked
the §(c) callout." Investigation found **all three of #6014's edits were gone from `origin/main`**:

```
git log --oneline origin/main -- <runbook>      # → #5984 (7e5fb720a) touched it AFTER #6014
git diff <#6014-sha> <#5984-sha> --stat -- server.tf ADR-068… runbook…
  server.tf   |  9 ----
  ADR-068…    | 27 ----
  runbook…    | 54 ++++-----------------
```

`#5984` ("decision-principles engine") was an **unrelated branch that had forked from `main`
BEFORE #6014 merged**. When #5984 merged, its stale copies of those three files won, silently
reverting #6014. No conflict fired — the merge machinery took #5984's (older) version of the
whole file because #5984's branch-point predated #6014 and #5984 also happened to touch those
files (or a rebase/merge resolved in its favor).

## Root cause

A small, fast-merged PR is maximally exposed to this: the window between "merge" and "a
long-lived sibling branch merges" is exactly when a stale sibling that touched the same files
overwrites it. "I verified it landed on main" is a point-in-time check, not a durable guarantee —
`main` is mutable and a stale branch is a silent revert vector, not just a conflict risk.

## Solution / prevention

1. **Do not build on a just-merged invariant without re-verifying it still exists on `main` at
   build time.** When a later PR depends on content a recent small PR added, `git show
   origin/main:<file> | grep <sentinel>` at the START of the dependent work — treat absence as a
   silent revert, not a mistake in your memory.
2. **Restore via the current PR rather than a separate revert-of-the-revert.** Here the follow-up
   PR already re-touched all three files (ADR amendment, runbook rewrite, server.tf comment), so
   the clean fix was to fold the restoration into it (one explicit commit:
   `fix(infra): restore §(c) HARD GATE comment on server.tf (reverted by #5984)`), not a separate hotfix.
3. **A load-bearing invariant should live in the code-adjacent guard, not only in docs.** The
   `server.tf` comment sits on the exact `ignore_changes=[placement_group_id]` line a future
   cutover edits first — that placement makes it the hardest to lose silently and the most likely
   to be seen at the moment of the dangerous action. Docs (ADR/runbook) are necessary but softer.
4. **For the reviewer:** the "all-members drift-guard must rebase before ship" learning has a
   sibling here — a *small docs/invariant* PR is at risk of being reverted by a stale sibling even
   without any guard. A dependent PR's review should re-derive the invariant's presence on fresh
   `origin/main`, not trust the predecessor PR's merge.

## Session Errors

1. **#5984 stale-branch clobber of merged #6014** — Recovery: restored ADR amendment + runbook
   rewrite (Phase 3) + `server.tf` comment (explicit commit) inside the follow-up PR. Prevention:
   re-verify a just-merged invariant on `origin/main` before depending on it (this learning).
2. **Fan-out-created `*.test.sh` not CI-registered** — two subagent-authored test files
   (`lb-weight-gate.test.sh`, `lint-infra-no-human-steps.test.sh`) were not registered in
   `infra-validation.yml` / `test-all.sh`; without registration they never gate in CI. Recovery:
   orchestrator registered both before ship. Prevention: a one-shot/work fan-out orchestrator that
   delegates NEW `*.test.sh` creation must verify each is wired into its CI runner (infra tests →
   `infra-validation.yml`; `scripts/*.test.sh` → `test-all.sh` explicit list) in the integration
   step — the existing "register new infra test.sh same commit" rule applies to the orchestrator,
   not just the file author.
3. **New enforcement lint shipped failing-OPEN** — the first cut of `lint-infra-no-human-steps.py`
   passed the canonical human step ("the operator reboots web-1 by hand": `\breboot\b` matches only
   the bare lemma; backticked command stripped before imperative match; one-blank-line actor/step
   gap). Recovery: review agents surfaced it; hardened (inflection, raw-line, non-blank adjacency,
   wider lexicons, fail-closed ignore-regions). Prevention: a NEW source-scan enforcement gate needs
   adversarial evasion fixtures (the phrasings it MUST catch) at authoring time, not only happy-path
   fixtures — mutation-test the gate against the inputs it exists to block.
4. **Push rejected after rebase** — one-off; `--force-with-lease` on the draft-PR branch after a
   rebase is expected.
5. **Background `cmd > /tmp/log 2>&1` left the task output file empty** — one-off; redirect sends
   output away from the task file (already-documented footgun); read the real log.

## Tags
category: workflow-patterns
module: git-merge, review, one-shot
