# Decision Challenges — feat-one-shot-11556-reprice-checkpoint

Rows appended by `soleur:plan` (headless pipeline — Task subagent, no TTY).
`ship` Phase 6 renders this table into the PR body and files the
`action-required` issue. Classes: `technical` (CTO ruling shape — never
"Applied by the planner"), `taste`, `operator (<category>)`.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Re-price mechanism for the committed tables: full `--timings-dir x8 --write` (honest re-price of ALL ~600 light labels — reds `scripts/test-all-fast-tier-budget.test.sh` by committing the 8 always-on drifters' real 11-378 s weights and imports #11648's deferred demotion scope) vs incumbent-preserving `--durations` seed (committed table + 7 arm rows replaced by measured medians; budget stays green; #11648 stays deferred) | technical | Ruled by CTO agent, 2026-10-31: incumbent-preserving `--durations` seed — seed TSV = the committed `scripts/suite-durations.tsv` with only the 7 arm rows replaced by measured medians from the 8 post-merge artifact runs, then `--durations seed.tsv --write`; byte-for-byte the mechanism merge commit `8598aae15e` used (`suite-durations.tsv:3` seed-provenance header is the receipt), bounded diff, keeps the deferred demotion scope with its owning issue. Dissent: the alternative is the more honest table — the seed knowingly re-commits 8 stale always-on weights and leaves the price book half-true; mitigated because the staleness is disclosed in the always-on-drift issue and the seed-provenance header, and that issue's re-eval deadline is the forcing function for the real re-price. Evidence that would flip: the drift issue closed wontfix, or demonstrated shard-balance error from stale incumbents exceeding the arm-reprice gain — neither exists today. |
| Session-state Updates 18-19 restoration surface: apply the verbatim diff to the archived `specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md` (the file it was written for) vs re-homing the content in this branch's own spec dir | technical | Ruled by CTO agent, 2026-10-31: verbatim apply to the archived file — the patch was authored against that exact path (`git apply --check` passes against index `c839fe85d8`), the file's own in-archive precedent (Updates 14-17 appended post-archive) establishes the append-until-merge convention, and the merge record is the terminal entry a reader of that archived spec expects at its tail; the `.patch` under this spec dir is transport, not the home. Dissent: minimal — editing an archived artifact nominally blurs the active/archive boundary, but no archive-freeze rule was found and the in-file precedent defeats it. |
| Measured always-on drift evidence: carry the 8 drifters' real medians onto #11648 as a comment vs record them only in the runbook entry | technical | Ruled by CTO agent, 2026-10-31: both — carry the fresh medians onto #11648 as a comment AND record them in the runbook entry; the issue's own acceptance criterion demands exactly this verification ("verify against a calm main-side run before demoting"), the 8 post-merge runs are a second independent measurement against its existing 5-run table, and the measurement cost is already paid. Dissent: marginal redundancy if the fresh numbers merely corroborate — accepted; one comment with the medians plus a one-line agree/disagree verdict is cheap and requested. |

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
