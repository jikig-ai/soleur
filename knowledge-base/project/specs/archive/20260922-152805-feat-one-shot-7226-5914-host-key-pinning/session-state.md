# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Post-plan collision re-probe (#7226, #5914, #8125): clean

### Errors
None

### Decisions
- git-data host key: Terraform-minted ED25519, cloud-init install + boot self-check, published to Doppler prd in the same apply, rotated on every replace; follow-on job forces a web release to load the new pin.
- web-1 (non-replaceable): current ECDSA-P256 key captured once direct (not via CF), committed, re-verified via CF strict run pre-merge; bridge + all 19 Terraform connection blocks consume it (ECDSA because TF 1.10.5 negotiates it first).
- App keeps one unpinned fallback reachable only while no pin is loaded AND store flag off; deleting it (closing #5914) is a hard precondition to any GIT_DATA_STORE_ENABLED flip. PR body: Closes #7226, Closes #8125, Ref #5914. DC-1/DC-2 recorded in decision-challenges.md.
- This PR invalidates rung-2 evidence (two-PR sequence); runbook precondition checklist rewritten into a staged five-step post-merge sequence.
- New ADR is ADR-237. No edits under apps/web-platform/infra/sentry/ (#8453 owns it).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: repo-research-analyst, learnings-researcher, cto (x2), clo, cpo, spec-flow-analyzer (x2), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, security-sentinel, framework-docs-researcher, deployment-verification-agent, observability-coverage-reviewer, test-design-reviewer, general-purpose
