# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-03-chore-supabase-followups-art30-register-orphan-linter-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` → only `plans/` + `specs/`. No breach.
- Post-plan collision re-probe: plan `closes: [7717, 7716, 7718, 6489]`. #6489 was discovered by
  planning (not passed at Step 0a.5) and re-probed: OPEN, zero linked PRs, zero merged body/title
  hits, no `origin/main` grep hit. Clean.

### Errors
- Self-inflicted, caught in-session: a Python slice anchored on `## Alternative Approaches
  Considered` matched a backticked *mention* of that heading and duplicated the Technical Approach
  section. Excised. Same anchor-matched-a-mention class as `cq-cite-content-anchor-not-line-number`
  / `cq-assert-anchor-not-bare-token`.
- Six acceptance criteria were defective on first writing (AC8 unsatisfiable, AC17 grepping an
  absent literal, Guard 1 highwater row inverted, AC19/AC21 asserting proxies, AC22 contradicting
  its own escape hatch). All found by running every AC against the untouched tree, and fixed.
- Non-blocking: `plugin:github:github` MCP server failed to connect; all GitHub work used `gh` CLI.

### Decisions
- W1 promotes the deprecated-endpoint guard via one `run_suite` line on the already-required
  `test` context, NOT the issue's prescribed four-file public-ABI route. The ADR-139
  `ALLOWED_PATHS ∩ SCAN_DIRS` intersection re-derives to EMPTY, so #7716's mandated bot-PR
  preflight reproduction does not apply. Aggregator-union invariant lands as an ADR-139
  amendment, not a new ADR ordinal.
- W6 creates a distinct `knowledge-base/legal/breach-register.md` (CLO ruling): Art. 33(5) is not
  an Art. 30 artifact. Follows the existing `article-30-2-register.md` precedent; an index, not a
  transcription. `__TBD_BETTERSTACK_RETENTION__` and `__TBD_OBSERVED_VOLUME__` resolve to
  `NOT RECORDED` with reasons; `__TBD_DPA_DATE__` to `NOT EXECUTED`.
- W7 cut from a union design to two narrow directory loops on a measurement (53 files → 1 orphan,
  4 → 1), removing the exclusions, seventh surface, 21 ACK entries and parallel covered-set
  derivation as structurally unnecessary.
- #7716 part 2 (`advisors/*`) stays monitor-only as the issue states, but the plan records that
  the "monitor" has no mechanism today and files the designed-but-unbuilt spec-diff poller.
- #7716 part 5's 66-runbook `triggers:` backfill deferred with reasons; the shape-pin and three
  defect fixes ship.
- #6489 folded in as a duplicate of #7716 part 3, with better evidence (the `SUPABASE_PAT` it
  names is a live 401).

### Open decision escalated to operator
- DC-1: two independent reviewers recommend shipping #7717 (statutory) as its own PR. The plan's
  mitigation for bundling was FALSIFIED — `ship` merges `--squash`, so there is no independently
  revertable statutory commit. Coupling recorded as real and unmitigated. Awaiting operator call
  before Step 3 (`/work`).

### Components Invoked
- Skills: `soleur:plan`, `soleur:gdpr-gate`, `soleur:plan-review`, `soleur:deepen-plan`
- Research: `repo-research-analyst`, `learnings-researcher`, `functional-discovery`, 4x `Explore`
- Domain review: `soleur:engineering:cto`, `soleur:legal:clo`, `soleur:product:cpo`
- Plan-review panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, plus `cto` (devex) and `cpo` (delta)
- Gates: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, deepen-plan halts 4.5-4.11,
  live verification of 13 rule IDs, 17 issue citations, 10 labels, every AC against the tree
