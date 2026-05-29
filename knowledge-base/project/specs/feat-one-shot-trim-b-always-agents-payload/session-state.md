# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-chore-trim-agents-b-always-budget-and-wire-linter-plan.md
- Status: complete
- Resolves: GitHub issue #4599

### Errors
None. (One self-caught arithmetic error in the first-draft byte ledger was corrected during deepen-plan and documented in-plan as an audit trail — corrected levers provably clear the hard <22000 gate with 788 B margin.)

### Decisions
- Path (a) executed: bring B_ALWAYS under 22000 AND wire `scripts/lint-agents-rule-budget.py` into CI. Path (b) (raise/retire limit) rejected — 22k is a legitimate proxy for per-turn always-loaded context bloat.
- Demotion sharply constrained: `hr-*` and compliance-tier bodies pinned to core (CPO sign-off PR #3496). Only 2 ship/merge-phase `wg-*` gates safely demotable core→rest (loader loads rest.md only on code/infra/multi-class sessions, not single-class docs-only).
- Reduction is condensing-led, not demotion-led: AGENTS.md index is irreducible; all bytes come from AGENTS.core.md. Load-bearing lever is iterative guidance-preserving condensing (collapse learning-path tails to issue-# breadcrumbs, relocate Why/How narrative to cited learning files, tighten redundant prose).
- Guidance-preservation guardrail: no rule deleted, no retired-rule-ids.txt entries (demotion keeps id in index with flipped `→ rest` pointer). /work stops trimming at target and records residual rather than stripping load-bearing directives.
- CI wiring: add two `run_suite` lines (live linter + companion `.test.sh`) to the `want_scripts` shard of `scripts/test-all.sh`; `ci.yml` test-scripts job already runs it — no workflow edit needed.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan (gates 4.4/4.6/4.7/4.8 all PASS; loader-class-fit + rule-ID citation checks inline)
