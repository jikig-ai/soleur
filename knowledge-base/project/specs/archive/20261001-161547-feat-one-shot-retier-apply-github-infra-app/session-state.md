# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-fix-retier-apply-github-infra-app-identity-plan.md
- Status: complete

### Errors
- `GET /user/installations/166065653/repositories` returned 403 for the local user token, so soleur-infra's repository list could not be read directly. Coverage is inferred from Tier-B run 36539258756 (2026-09-29, "No changes"), and the plan adds a pre-Terraform mint step with an exact-repositories check so a missing repo fails before any write.
- Follow-up issues were not filed during planning (plan-only mandate); they are tasks 0.1 and 0.2.
- Lefthook was not on PATH for the two plan commits; markdownlint and the plan lints were run by hand.

### Decisions
- Terraform already authenticates as soleur-infra. Only the workflow's fetch step and its post-apply check still use the evicted key. The fix reuses `.github/actions/mint-infra-app-token` before Terraform, scoped to `{"administration":"write"}` on `soleur,soleur-marketplace` (rulesets' `bypass_actors` are hidden from read tokens). No key returns to `prd_terraform`, and no `infra/github/*.tf` file changes.
- `entrypoint_audit` uses the job's own `github.token` (`issues: write`) instead of an App, because soleur-infra has no `issues` permission.
- The merge carries `[skip-web-platform-apply]` on a commit-body line, because a change to `apply-web-platform-infra.yml` itself would otherwise fire a full apply. The post-merge proof dispatch of `apply-github-infra` is authorized.
- Census G4e becomes "exactly 1 reader, none in a Tier-B job". CENSUS_ROWS stays 38.
- Deferred: swap the marketplace ruleset's bypass actor to soleur-infra (P1 follow-up; it needs a `.tf` change and an apply), and track the pre-existing planted-integration-id exposure until O11 (task 0.2).

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: learnings-researcher, repo-research-analyst, functional-discovery, cto (×2), an opus advisor, the dhh/kieran/code-simplicity reviewers, security-sentinel, architecture-strategist, and a sonnet fact-checker
- Read-only `gh`/`doppler --only-names`, markdownlint-cli2, lint-guard-contract.py, lint-infra-no-human-steps.py
