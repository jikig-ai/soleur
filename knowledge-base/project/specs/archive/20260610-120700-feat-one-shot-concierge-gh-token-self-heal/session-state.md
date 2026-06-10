# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-09-fix-concierge-sandbox-github-egress-gh-forbidden-plan.md
- Status: complete

### Errors
None

### Decisions
- **Diagnosis reframe (load-bearing):** the task's hypothesis is refuted by the code — the GH_TOKEN mint at `cc-dispatcher.ts:1470` already consumes `effectiveInstallationId` (since PR #5031, test-pinned at `cc-dispatcher-real-factory.test.ts:727`). The token plane is fully swept; the actually-unswept plane is the **sandbox network**: `agent-runner-sandbox-config.ts` ships `network.allowedDomains: []`, so the SDK sandbox proxy denies CONNECT to `api.github.com` for every in-sandbox `gh`/`git` process, producing exactly the transport-shaped `Post "https://api.github.com/graphql": Forbidden` (a GitHub-side 403 would render as `HTTP 403:`/`GraphQL:`). Verified against the installed `@anthropic-ai/claude-agent-sdk@0.2.85` bundle, not docs.
- **Fix shape:** egress-iff-entitled-token — `buildAgentSandboxConfig(workspacePath, { allowGithubEgress: Boolean(args.ghToken) })` with `GITHUB_EGRESS_DOMAINS = ["github.com", "api.github.com"]` (exact hosts, no wildcards). Derivation (not a flag) makes the half-wired state unrepresentable; legacy leader path never passes `ghToken` (verified zero references) so its sandbox stays fully closed — never widens beyond the existing membership/entitlement gate (AC5 invariance check).
- **Scope-outs:** #5067 least-privilege narrowing refuted as cause (Concierge mint is unscoped + cache-key isolated); legacy leader path's raw-`installationId` GitHub tools deferred via tracking issue; cc-dispatcher decomposition (#3243) and WS event field (#3242) acknowledged, not folded.
- **Threshold:** `single-user incident` with `requires_cpo_signoff: true`; security-sentinel + user-impact-reviewer mandatory at PR review; Phase 0 pivot gate prescribed (if the deny-shape probe disproves the sandbox hypothesis, stop and re-diagnose via Sentry self-heal/mint queries before any code).
- **Pipeline constraint:** no subagent Task tool available in planning context, so plan-review, domain review, and deepen-pass verifications ran inline (recorded as such in the plan); all deepen halt gates (4.6/4.7/4.8/4.9) pass.

### Components Invoked
- Skill: soleur:plan (Step 1)
- Skill: soleur:deepen-plan (Step 2)
- Inline (no Task tool): repo research, learnings research, premise validation (`gh pr/issue view` on #5041/#5031/#4946/#5018/#4826), SDK bundle verification, code-review overlap check, domain review (CTO/Security/CPO inline), GDPR advisory, plan-review lenses, verify-the-negative pass
- Artifacts committed and pushed: plan (`9de753c97`, deepened `50f77a43f`) + tasks.md
