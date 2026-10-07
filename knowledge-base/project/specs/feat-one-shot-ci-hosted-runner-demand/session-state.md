# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. First job-minute pass overcounted queued-then-cancelled jobs (9,392 vs 7,456 true) and was re-measured; two false premises in the first Stage 1 draft were fixed at plan review; three GitHub semantics (fork-PR repository variables, GITHUB_TOKEN `gh pr ready` triggering workflows, same-name check-run rollup) are recorded as Stage 3 entry gates.

### Decisions
- Measured window 2026-10-07 13:04Z-19:04Z: 7,456 runner job-minutes (lower bound), mean concurrency 21, p90 57, pool at 55+ concurrent jobs 22% of minutes and at the 60-job cap itself 0.6% and at 58 or more 12.5% on a reviewer re-run (bursty). A same-window re-run measured 8,414 job-minutes; see the plan's re-measure subsection. Team = 60 concurrent verified against GitHub docs.
- Ranking: push-main dedupe (9512) up to 1,018 min; draft-light checks net 180 to 895 at steady state (first-pass to re-measure inputs; the in-window transient 591 to 1,277 is not the steady state), tied with push-main dedupe within window noise; PR affected-only 300-700 gross (parked); fan-out trim (CodeQL code scanning up to 294 and GitHub Code Quality up to 239 on PR heads, security decisions; secret-scan smoke up to 134). Superseded-run cancellation is not a lever (4%).
- Stage 1 is NOT in this PR (up to 1.8% gross saving, would break docs-only scope). This PR ships plan, ADR-276 (proposed), lever-5 memo (CTO-reviewed), tasks and stage issues 9727-9730.
- Deepen findings: admin-merge skips the queue, so merge_group is not the full-battery authority there; gh pr ready then auto-merge within seconds can enqueue on draft-run greens (ship Phase 6 must wait, fail closed); all-skipped run concludes `skipped`, so the elided push-main run needs one real attestation job.
- Lever 5 memo: demand levers first, then Enterprise quote, then spend-capped larger runners, Hetzner ephemeral last with strict security conditions. Nothing provisioned.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents repo-research-analyst, learnings-researcher, cto, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer.
