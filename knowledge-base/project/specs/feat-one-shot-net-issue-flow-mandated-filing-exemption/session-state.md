# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-02-feat-net-issue-flow-mandated-filing-exemption-plan.md
- Status: complete

### Errors
- A live P0 was found in production tooling, unrelated to but blocking this feature: the
  net-issue-flow gate already exceeds the hook's `timeout 8` (measured 7.7–8.1 s; 1 of 3 runs
  returned `rc=124`, which the hook translates to `exit 0` — no deny, no telemetry). The blocking
  gate is intermittently a silent always-pass today. Folded in as blocking prerequisite FR0.
- Nine P0 defects found in plan v1 by the review panel, four from claims asserted off documents
  rather than measured: the "fail-closed" guarantee was actually fail-OPEN (a failed `merge-base`
  makes `git show ":path"` read the staged index — 101 ids, `rc=0`); the adjacency claim was
  inverted (42 of 101 tags sit right after `[id:]`); the ack gate leaves 27 of 101 rules ungated;
  and the attribution readout does not exist. All corrected in v2.
- Three acceptance criteria were structurally unsatisfiable (asserting a merge-base set that cannot
  exist pre-merge). One AC was vacuously green (case-sensitive grep missed a capitalised variant).
  One proposed test seam was a production self-grant vector.
- Plan-write blocked once by the IaC guard — plan prose quoted the guard's own trigger tokens.
  Rephrased rather than acked.

### Decisions
- Derive the qualifying set from a `[mandates-filing]` corpus tag, matched per rule line, read from
  the merge-base — never adjacency, never the worktree, never a bare `:path` (both self-grant).
- Scope extraction to `^(hr|wg)-` so the exemption set is by construction a subset of the ADR-092
  ack gate's coverage.
- Keep the report honest: `Filing:` keeps its true count, exemptions get their own line, plus a
  `Rejected:` line naming the cause per non-exempt issue.
- Restored `work/SKILL.md` and `review/SKILL.md` to Files-to-Edit after v1 wrongly cut them.
  `work/SKILL.md` is the live writer for the tagged rule.
- Recorded rather than applied the two challenges to operator-specified scope (DC-1, DC-2) per
  ADR-084 — both propose designs the brief's constraints 1 and 2 explicitly rule out (a free-form
  `reason=` token and a bare label are the self-serve shape; the brief mandates corpus derivation).
  Operator direction remains the plan default; `/ship` files them as action-required.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: `soleur:engineering:cto` (x2),
`dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`,
`spec-flow-analyzer`, `learnings-researcher`, `Explore` (x3); deepen halt gates 4.5-4.10;
`gh`, `git`, `jq`, `lint-agents-rule-budget.py`.
