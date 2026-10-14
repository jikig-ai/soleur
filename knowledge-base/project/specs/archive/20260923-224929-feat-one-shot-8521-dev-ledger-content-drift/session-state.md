# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- First `gh issue create` blocked by a hook (body file not yet written); retried after writing it.
- Second hook block required a filing classification; added `--label meta/machinery`, #8605 filed.
- One `sleep 30` blocked by the harness; waited on agent notifications instead.

### Decisions
- Scope widened on evidence: the 2026-09-22 recurrence was the in-flight arm (`139_…` owned by open #8507) plus the #8583 arm (`138_…`), not #8521. Main-side ownership classification under ADR-061's per-ref rule is added so `Closes #8520` is honest; ADR-061 amended rather than a new ADR.
- Fail the PR pre-merge instead of re-applying ("a migration applied to dev is immutable, merged or not"). Auto re-apply and per-PR ephemeral DB rejected. Guard runs once, pre-apply, as a base-ref copy; base/introduction/deleted decision made in full-history `detect-changes`.
- Ownership is git-only in a throwaway bare repo: branches own only files absent from main, merged heads skipped, main-history exclusion, 30-day freshness (else `stale`, blocks); fails closed as `UNCLASSIFIED`.
- Cut after review: post-apply second check, offline ledger-file mode, `BEGIN READ ONLY` wrapper, pinned base SHA, any `run-migrations.sh` edit (its cwd bug is #8606).
- Recorded for the operator, not applied (decision-challenges.md): dev-reconcile workflow, push-time warning, 30-day threshold, guard-list generalization.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, functional-discovery, cto (x2), general-purpose advisor, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer, observability-coverage-reviewer
- Filed: #8605 (deferred self-service dev discard), #8606 (run-migrations.sh unmerged-check cwd bug)

## Work Phase
- Status: complete (Phases 0-5; AC1-AC9 verified locally)
- Suite: `dev-ledger-parity.test.sh` 65/65; mutation battery 20/20 killed (14 guard operands, 6 action.yml operands), control green, tracked files restored byte-identical. One survivor (A3 identity check) was a fixture defect (here-string trailing empty line), fixed and re-killed.
- AC8 timing (real origin, 95 heads, this box at load ~66): owner build 26.9 s / 17.2 s. Plan's unloaded estimate 9-13 s.
- Local `TEST_GROUP=scripts` gate REFUSED (rc=4, two sibling full-gate runs). Substitute: 3 consumer suites + 49 census-shaped test-all rows. Results: 47 green; `lint-diagnosis-claims` red on a real ADR-166 wording defect in this diff (fixed); `orphan-process-reaper-mutations` hit a 300 s local cap under load (untouched by this diff; CI's required `test` context is authoritative).
- Ratchets moved by the new files and fixed at the code: guard-vacuity-floor (suite PROMOTED), fixture-relative-assert + fixture-dir-operand-assert (canonical assert_fixture_dir), lint-shell-capture-exit.
- GDPR gate: skipped (no diff path matches the canonical regex).
