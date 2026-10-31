# Decision Challenges — feat-one-shot-11556-reprice-checkpoint

Rows appended by `soleur:plan` (headless pipeline — Task subagent, no TTY).
`ship` Phase 6 renders this table into the PR body and files the
`action-required` issue. Classes: `technical` (CTO ruling shape — never
"Applied by the planner"), `taste`, `operator (<category>)`.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Re-price mechanism for the committed tables: full `--timings-dir x8 --write` (honest re-price of ALL ~600 light labels — reds `scripts/test-all-fast-tier-budget.test.sh` by committing the 8 always-on drifters' real 11-378 s weights and imports #11648's deferred demotion scope) vs incumbent-preserving `--durations` seed (committed table + 7 arm rows replaced by measured medians; budget stays green; #11648 stays deferred) | technical | pending - assumed: incumbent-preserving `--durations` seed — the same mechanism merge commit `8598aae15e` used ("incumbent-preserving regen via --durations seed"), bounded diff, no deferred-scope fold-in. Disqualifier for the assumed option: it leaves the 8 drifting always-on labels' committed weights dishonestly low, so the checkpoint's deeper goal (a table that tells the truth) is only half-served. Disqualifier for the rejected option: `test-all-fast-tier-budget` reds on committed-weight caps (10 s/suite, 300 s total; current 120 labels / 200 s / 0 over-cap), forcing the #11648 demotion doctrine — per-label edge declarations — into a bookkeeping PR. Escalate to soleur:engineering:cto if the full-reprice is preferred. |
| Session-state Updates 18-19 restoration surface: apply the verbatim diff to the archived `specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md` (the file it was written for) vs re-homing the content in this branch's own spec dir | technical | pending - assumed: verbatim apply to the archived file — it is the record the updates were written for; the `.patch` under this spec dir is the transport, not the home. Disqualifier for the alternative: re-homing leaves the archive permanently missing the merge record the next reader of that spec expects at its tail. |
| Measured always-on drift evidence: carry the 8 drifters' real medians onto #11648 as a comment vs record them only in the runbook entry | technical | pending - assumed: both — the runbook entry records the numbers AND a one-comment pointer lands on #11648; the checkpoint already paid the measurement cost, so the evidence reach is ~free and the deferred issue gains concrete values to demote against. Disqualifier for runbook-only: runbook history is the wrong consumer — #11648 is where the demotion work will be planned. |

## Notes

- No operator-class rows: no money, scope, priority/schedule, irreversible or
  production-mutating authorization, legal-risk, or brand decisions in this
  checkpoint (regenerated CI data + docs only).
- Standing-panel check (`cq-ac-must-not-depend-on-concurrent-sessions`): all
  ACs verified deterministic — no ambient-signal assertions.
- Named-panel relevance (independent read): `soleur:engineering:cto` activated
  (tooling Files-to-Edit); CPO/CMO/UX not relevant. Eng panel + CTO lens ran
  inline sequential-fallback; two Mechanical findings applied to the plan
  (AC-8 pipeline-artifact enumeration; runbook `-n`→`-p` flag fix).
