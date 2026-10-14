# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-feat-adopt-github-merge-queue-for-main-plan.md
- Status: recovered from pre-existing master plan (planning subagent a465044e0946dc1b6 was killed by an Anthropic session limit before emitting its Session Summary; its deepen pass left no on-disk artifact — git tree clean).

### Recovery rationale
The #5780 master plan was already authored AND deepened during the PR-1 planning
cycle (it carries the full P0/P1/P2 architecture-review annotations, observability
block, ADR section, and split Pre/Post-merge ACs). It is committed to main and
explicitly partitions PR-1 vs PR-2 items. Re-running a heavy plan+deepen subagent
would regenerate the same artifact and risk re-hitting the session limit, so this
run recovers from the on-disk plan and drives the PR-2 slice directly.

### PR-1 / PR-2 boundary (verified in this worktree at recovery)
PR-1 (#5784, merged 2026-06-30) — confirmed landed:
- merge_group present in all 7 producer workflows (ci, secret-scan, pr-quality-guards,
  legal-doc-cross-document-gate, tenant-integration, dependency-review,
  skill-security-scan-pr-trailer).
- apply-github-infra.yml uses `select(.type=="required_status_checks")`; legacy
  `.rules[0]...` removed.
- merge-queue-stall-check.yml + merge-queue-cla-synthetics.yml both exist.

PR-2 (this branch) — all absent, the work to do:
- infra/github/ruleset-ci-required.tf — add `merge_queue {}` block (Phase 1).
- scripts/create-ci-required-ruleset.sh — DR-skeleton sync (P1-3).
- .github/workflows/scheduled-terraform-drift.yml — add `infra/github` to the matrix (CTO B-2).
- knowledge-base/engineering/architecture/decisions/ADR-032-...md — amend (Phase 5).
- infra/github/README.md — runbook (Phase 5).
- Post-enablement canary — post-merge AC (queue only fires after PR-2 applies); the
  standing merge-queue-stall-check.yml probe (PR-1) is the steady-state signal.

### Errors
- Planning subagent killed by Anthropic session limit (reset 22:20 Europe/Paris).
  Recovered from on-disk master plan; no scope breach (git tree clean at recovery).

### Decisions
- Recover from the pre-existing deepened master plan instead of re-planning.
- Scope work strictly to the 5 PR-2 files + post-merge canary AC; PR-1 items verified done.
- "18 required contexts" = 16 (CI Required ruleset) + 2 (CLA Required: cla-check,
  cla-evidence) — both rulesets gate main; reconciles the plan's "16" with the brief's "18".

### Components Invoked
- soleur:go -> soleur:one-shot (routing); planning subagent (killed); on-disk recovery.
