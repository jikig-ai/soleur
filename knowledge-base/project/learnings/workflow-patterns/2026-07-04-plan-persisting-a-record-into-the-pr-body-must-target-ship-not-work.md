# Learning: A plan that persists a record into the PR body must target `ship` (sole body author, full-replace) — and a non-technical operator only sees `action-required` issues, not PR bodies

## Problem

The v1 plan for the decision-principles engine (#5984) wired a headless "User-Challenge"
record (a `## Decision Challenges` block) into `work/SKILL.md`, on the stated premise
that "work authors the PR body." Two verified facts break that premise:

1. **`work` does not author the PR body — in either mode.** It has only
   `gh issue create --body` (`work:837,964`); no `gh pr edit/create --body`. In one-shot
   it emits `## Work Phase Complete` and hands off; in direct mode it chains to `ship`.
2. **`ship` is the sole PR-body author and it *full-replaces* the body** from diff
   analysis (`ship:1196,1242`; :1214 "always pass BOTH --title and --body"). Any block
   written earlier is clobbered.

Separately, even a correctly-rendered PR-body block is **invisible to the target
operator**: `operator-digest` ingests merged-PR title/labels/mergedAt + `action-required`-
labelled **issues** only (`operator-digest:76,110-114`) — never PR bodies. one-shot
auto-merges, so the record's "async review" promise is unfulfillable.

Caught by a 5-agent plan-review panel (architecture found the `work`-vs-`ship` defect;
CPO + spec-flow found the operator-legibility gap) — not by the plan author.

## Solution

- **To land content in the PR body, edit `ship` Phase 6's body construction** (the
  `gh pr edit --title --body` site), not `work`/`plan`. If earlier phases produce the
  content, they **detect + persist to a durable artifact** (e.g.
  `knowledge-base/project/specs/<branch>/decision-challenges.md`, alongside
  `session-state.md`); `ship` reads it and folds it into the canonical body. This mirrors
  ADR-083, which edited `plan` Step 4.5 **and** `ship` Phase 5.5 (not `work`) for exactly
  this reason.
- **For a non-technical operator, the legible async surface is an `action-required`
  issue**, not a PR-body block — that is what `operator-digest` Section 4 harvests.
- **Section-name hazard:** a block rendered into the PR body must avoid the
  `ship-operator-step-gate.sh` deny tokens (`Operator`/`Post-merge`/`Follow-up`) and
  operator-action bullets, or the gate blocks the PR. Use informational statements.

## Key Insight

"Which skill authors the PR body" is a load-bearing, non-obvious fact: it's `ship`
(full-replace), never `work`/`plan`. Any plan that persists a record *into the PR body*
must target `ship` and route earlier producers through a durable artifact. And PR-body
content is not an operator-visible surface — the `action-required` issue is.

## Tags
category: workflow-patterns
module: plan
