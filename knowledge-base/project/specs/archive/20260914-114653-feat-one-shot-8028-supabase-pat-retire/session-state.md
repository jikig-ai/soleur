# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-13-security-retire-dead-supabase-pat-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- `iac-plan-write-guard` denied the first Research Insights write (Cut List quoted the rejected arm's CLI verb literally); reworded, added `iac-routing-ack` marker with an `## Infrastructure (IaC)` justification, re-wrote.
- Deepen-plan gate 4.8 matched `var.supabase_access_token` (pre-existing Supabase TF variable the plan only references); rephrased, disposition recorded.
- Plan-review caught a wrong citation (PR #7793 → the xtrace-refusal lint is PR #7858); corrected.

### Decisions
- Migrate `postgrest-reload-schema.sh` to `SUPABASE_ACCESS_TOKEN`; no replacement PAT minted.
- One soak rule: `--best-effort` soaks only absence and transience; a JSON-bodied 401/403 with a token present exits 2 so a dead token reds the next prd release. prd absence caught via `verify-required-secrets.sh`.
- Dev arm (DC-1): do NOT copy the account-scoped token into dev/dev_scheduled or GH secrets — `tenant-integration.yml` runs on `pull_request`. Dev CI keeps the absence-soak; local operators read from `prd_terraform` on demand.
- Retirement scope is 10 configs (inherited from dev/prd roots into 8 branch configs); delete at the two roots from a scratch script with a proven-dead gate and full re-verify — no operator checklist.
- Lint-forced hardenings: xtrace preamble, `curl --disable --noproxy '*' --header @-` (bearer on stdin), baselines regenerated, `scrub_pat` strips runner-command bytes.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher ×2, functional-discovery, cto ×2, coo, advisor consult, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, framework-docs-researcher, verify-the-negative sweep, security-sentinel, silent-failure-hunter, test-design-reviewer, observability-coverage-reviewer, git-history-analyzer
