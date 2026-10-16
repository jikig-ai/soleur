# Decision challenges (Item G, `--ratchets` selector)

Technical forks on this branch were ruled by the CTO agent, never put to the operator. Each row is one decision;
the full evidence is in the plan, `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Item G: implement `--ratchets` in scripts/test-all.sh, or record not fixed | technical | Ruled by CTO agent, 2026-10-16: record as not fixed; do not edit the runner - cost is a full-battery `--affected` degrade plus armed `--pr-gated` batteries, and the pre-push ratchet lane plus `--affected` already buy the property |
| Pipe-guard lane gap (option C): in this PR or a follow-up | technical | Ruled by CTO agent, 2026-10-16: separate follow-up issue, conditional-tier lane member preferred - Item G is the selector only and the unconditional-versus-conditional trade is its own decision |
| Meaning of "forbidden-to-edit" for scripts/test-all.sh | technical | Ruled by CTO agent, 2026-10-16: a cost label (PR_GATE_MACHINERY_PATHS arming plus the `runner-changed` full-battery degrade), not a prohibition - no hook, CODEOWNERS entry or AGENTS rule bans the edit |

## Plan-review items not applied (taste)

Raised by the DHH, Kieran and simplicity reviewers; all mechanical findings were applied to the plan. These taste items were kept as planned, and each says what was asked and what was kept.

## 1. Taste: drop the guard-header edit and fold it into the follow-up issue

- Raised by: simplicity reviewer (the edit answers no ask and is the only deliverable that touches a code path).
- Kept, narrowed: the `STILL OPEN` sentence in `.claude/hooks/grep-q-pipe-guard.test.sh` lists Item G as open; after the #9217 record it would assert a falsehood, and the Item D, E and H records updated that same sentence. The neighbouring `DOES NOT SELECT THIS GUARD` sentence moved to the follow-up as the reviewers asked. Decide: keep the one-sentence edit (default) or drop it and let the follow-up own both.

## 2. Taste: cut the six-path sample to the three already measured

- Raised by: DHH and simplicity reviewers.
- Kept: probes take about 13 s unloaded, the first sample included a path not shown to be a producer, and the follow-up issue must carry confirmed numbers. Three paths with one provisional zero is thin.

## 3. Taste: shorten the #9217 comment and drop the 36/27/9/10/3 breakdown

- Raised by: DHH and simplicity reviewers.
- Kept: the CTO supplied that comment text as the record of the ruling and the counts are the evidence that the `grep -lis ratchet` set is a heuristic. They are stamped "as of ee8644bded".

## 4. Taste: collapse the skipped-gate sections and the Property/Cut table into one line

- Raised by: DHH reviewer.
- Kept: the plan skill requires the Property List and Cut List in Research Insights (plan-review reads them) and each skipped gate states its reason in one line.
