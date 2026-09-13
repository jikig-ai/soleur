# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-11-fix-apply-sentry-infra-red-on-main-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- `iac-plan-write-guard.sh` false-positive on "in the Sentry UI" phrasing; reworded, no opt-out marker used.
- `plan/SKILL.md` Phase 2.10 names a non-existent `apps/web-platform/test/c4-count-parity.test.sh`; C4 verified via `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh` instead.
- learnings-researcher recommended a stale `-target=` allow-list step (superseded by #6589 full-root); recorded, not acted on.

### Decisions
- Run 34491157462 failed at step 15 `sentry_alert live fidelity (AC19/AC20)` — AFTER `Terraform apply` (step 11 green). Forensics artifact shows 28 → 29 `sentry_alert`; not a partial write. Root cause: the probe's reference is a committed live capture (2026-09-09) that cannot contain a rule before it is applied. Re-running the same job cannot go green; roll-forward is the merge push of this fix.
- Fix: the apply job projects its reference from the plan it applies via a three-sided jq module (`tests/scripts/lib/sentry-alert-projection.jq`); the committed `alert-reference.json` remains only for the daily drift job, held equal to the plan by a PR-time gate. Verified 28/28 rules project identically from post-apply state and live capture.
- Single-trigger `triggers.logicType` projects a constant on both sides (provider hard-codes `any-short`).
- Sibling defect folded in: `scheduled-sentry-alert-drift.yml` dead-man's switch fires on every drift verdict (false #8058); regated on `(verdict, filed)` with `!cancelled()`.
- PR `Closes #8050` only; #8057/#8058 close via the drift workflow's own steps on a pre-merge branch dispatch.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: learnings-researcher, repo-research-analyst, functional-discovery, cto, cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, test-design-reviewer, git-history-analyzer, best-practices-researcher, observability-coverage-reviewer
