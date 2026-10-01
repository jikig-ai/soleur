# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-07-fix-byok-cap-breach-audit-ledger-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `soleur:engineering:review:spec-flow-analyzer` does not exist; the agent lives at
  `soleur:product:spec-flow-analyzer`. Re-spawned successfully, no work lost.
- First commit rejected by `markdown-lint` (MD038, malformed nested code span). Fixed
  and re-committed.
- Three factual claims in the first draft were wrong and are corrected in the plan with
  attribution rather than silent removal: the `audit_byok_use` RLS policy (migration 059
  replaced the owner-keyed policy with a workspace-member one, which also invalidates the
  CLO's derived GDPR ruling — that review must be re-run); the reading of ADR-041's cost
  column; and "pre-existing for the siblings".

### Decisions
- The issue's premise is false, and it reshapes the fix. An unhandled plpgsql
  `RAISE EXCEPTION` discards the same-transaction INSERT, and the function has no
  `EXCEPTION WHEN` handler — verified independently 2026-09-07 (0 handlers). So the three
  "working" sibling branches never persist rows either: the defect is five branches, not
  two, and the naive "add two INSERTs" fix would ship green while writing nothing.
  ADR-045 documents behaviour the code cannot produce.
- Mechanism resolved in the plan, not deferred to `/work`: return a refusal reason instead
  of raising. In-family precedent is `121_byok_cap_trip_from_found.sql`
  (`record_byok_use_and_check_cap`, `RETURNS TABLE(...)`). Autonomous-transaction and
  caller-side variants rejected on the record.
- The load-bearing SUM decision survived adversarial review: cap rows are NOT excluded
  from the window that refused them (exclusion creates a cap leak). Two of its three
  original supports were invalidated and rewritten.
- A larger unrelated defect surfaced and was confirmed: `unit_cost_cents` holds a
  whole-turn total, yet three cap SUMs multiply it by `token_count`. Founder-wide, not
  delegation-scoped.

### Operator scope decision (2026-09-07)
Plan proposed four PRs. Operator approved **PR-1 + PR-3 only**; PR-2 and PR-4 are filed as
tracked issues rather than folded in.
- PR-1 — `byok-delegation-ui-resolver.ts` reads a non-existent `cost_cents` column.
  Verified independently: `037_audit_byok_use.sql` declares `token_count` and
  `unit_cost_cents`; the resolver selects `cost_cents` and coalesces the error to 0, so
  every spend figure renders $0.00. Ships first, independent.
- PR-3 — #7829 proper: the return-status conversion.
- PR-2 (cap unit semantics, founder-wide) and PR-4 (DPD/Art. 30 corpus) → filed.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`; agents `learnings-researcher`,
`repo-research-analyst`, `data-integrity-guardian`, `data-migration-expert`,
`architecture-strategist`, `test-design-reviewer`, `user-impact-reviewer`,
`code-simplicity-reviewer`, `observability-coverage-reviewer`, `spec-flow-analyzer`,
`legal:clo`, plus a strong-model advisor consult.
