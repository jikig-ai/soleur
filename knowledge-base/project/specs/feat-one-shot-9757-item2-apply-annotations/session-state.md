# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-23-fix-apply-restore-exit-annotations-plan.md
- Status: complete

### Errors
None. Two non-blocking snags: an issue filing refused by a hook (re-filed with the machinery label as #10932), and decision-challenges.md failing the ruling gate twice (both fixed, gate passes).

### Decisions
- Exits 2 and 5 now each have two causes (source or credential rejection, or a local login failure on the runner); exit 78 is the engine's refusal to run under xtrace with a credential set.
- Explicit 78 arms in the workflow restore step and in gate A2; rewritten 2 and 5 arms; net-zero bytes against the 490,000-byte workflow gate.
- Exit 1 is out of scope and tracked as #10932.
- The merge fires the production apply: an operator-class authorization row. Ship asks one plain question before the PR is marked ready or the merge is armed.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO agent (forks F1-F4); learnings-researcher; dhh, kieran, simplicity, architecture, test-design reviewers.
