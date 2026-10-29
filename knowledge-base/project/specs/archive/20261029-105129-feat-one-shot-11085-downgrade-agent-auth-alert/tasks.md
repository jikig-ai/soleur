# Tasks: downgrade the agent-auth-failure diagnostic alert (step 1 of #11085)

Plan: `knowledge-base/project/plans/2026-10-29-chore-downgrade-agent-auth-failure-alert-plan.md`
PR body must say `Ref #11085` and close nothing.

## Phase 1: Setup
- 1.1 Baseline: `terraform -chdir=apps/web-platform/infra/sentry init -backend=false -input=false` then `validate` (expect Success).

## Phase 2: Guard test first (red)
- 2.1 In `apps/web-platform/test/sentry-agent-auth-failure-alert-op-contract.test.ts`: single-action tolerant regex in `ruleProblems()` requiring the `issue_owners` + `NoOne` email; invert the `NoOne` ban into an `ActiveMembers` ban.
- 2.2 `expectedReferenceEntry()` and `RULE_FIXTURE` use `NoOne`.
- 2.3 Flip the harness row ("NoOne fallthrough goes red" becomes "ActiveMembers fallthrough goes red"); add one row for a second action after the compliant first; keep the must-pass non-canonical rows.
- 2.3a Rewrite the `noOne` red-goes row to replace `"NoOne"` with `"ActiveMembers"` and assert `mutated !== RULE_FIXTURE`; the single-action extractor pushes a problem (never throws) when its regex misses.
- 2.4 Reword only the header/chain comment lines that name the email action or `ActiveMembers`; keep the pinned README/.tf phrases.
- 2.5 Run `cd apps/web-platform && npx vitest run test/sentry-agent-auth-failure-alert-op-contract.test.ts`: expect red on the live-rule and reference cases.

## Phase 3: Core change (green)
- 3.1 `apps/web-platform/infra/sentry/issue-alerts.tf`: `fallthrough_type = "NoOne"` on `sentry_alert.agent_auth_failure`; rewrite the "Email only" paragraph, the Lifecycle sentence and the GROUPING sentence (provider rejects zero actions; ownership-rule caveat once). Leave `frequency_minutes`, trigger, filters, `monitor_ids`, `lifecycle` untouched.
- 3.2 `apps/web-platform/infra/sentry/alert-reference.json`: `agent-auth-failure` `fallthroughType` ActiveMembers -> NoOne (one line, key order unchanged).
- 3.3 `apps/web-platform/infra/sentry/README.md`: opening paragraph, responder-steps heading and step 1, step 3 rationale (keep `never archive or ignore it`), Lifecycle (step 1 done 2026-10-29; keep step 2 trigger and the `2026-11-30` sentence).

## Phase 4: Verify
- 4.1 Contract test and `agent-auth-failure-sentry-path.test.ts` green.
- 4.2 `terraform validate` and `terraform fmt -check` green on the Sentry root.
- 4.3 `git diff --stat origin/main...HEAD` lists only the four edited files plus plan artifacts.

## Phase 5: Ship hand-off
- 5.1 PR body: `Ref #11085`, the CTO ruling row from `decision-challenges.md`, and the note that the merge applies to production Sentry (in-place update, zero destroys expected).
- 5.2 Post-merge: confirm `apply-sentry-infra.yml` succeeded and the live-fidelity probe shows no DRIFT for `agent-auth-failure`.
