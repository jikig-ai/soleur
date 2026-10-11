# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-11-chore-zot-consumer-probe-head-pinned-manifest-plan.md
- Status: complete

### Errors
None blocking (hook required meta/machinery label on follow-up issue creation; resolved).

### Decisions
- Web image left unpinned (no committed digest); tracked as #10044 (DC-1). PR closes #10004.
- Pin reaches web-1 only via local.zot_probe_repo_pinned + two-line server.tf edit; local.zot_probe_repo stays bare for cloud-init.
- One ref shape repo@sha256:<64hex>, one HEAD per pinned repo, one appended marker field pin_verdict.
- Probe suite in PROMOTED_FILES: raise MIN_ASSERTS (199 -> higher) and BASELINE_DECLARED_PROBES (+1).
- Post-plan re-probe: open PR 10046 (egress hotfix) also edits server.tf — different scope; serialize applies at ship.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; research/review agents per planner summary.
