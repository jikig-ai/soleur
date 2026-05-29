# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-cron-oauth-probe-app-jwt-decode-recurrence-plan.md
- Status: complete

### Errors
None. (One IaC-routing hook initially blocked the plan write for "operator-driven" framing; resolved by reviewing Phase 2.8 and adding the `iac-routing-ack` marker — the H3 branch is genuinely routed through Terraform/cloud-init, and the H1/H2 Doppler/GitHub-App-key steps are genuinely operator-only with documented "Automation: not feasible" justification.)

### Decisions
- Root cause is NOT key formatting — proven, not guessed. Verified `git merge-base --is-ancestor 9da77d86 db87c27d` = true and `app-private-key.ts` exists at the deployed release SHA: the PKCS#8 fix (#4569, merged 08:22 UTC, deployed by 12:31 UTC) was provably live in release `0.101.100+db87c27d` when the error fired at 14:00 UTC. The recurrence is not deploy-lag. Closes the two dominant prior theories (PKCS#8/CRLF and retry-on-401) that drove 6 failed fixes.
- The plan ships evidence-first triage, not a 7th patch. Phase 1 pulls the `#4568` diagnostic breadcrumb (`ghStatus`/`ghBody`/`clockSkewMs`) already attached to this Sentry event, plus a `GET /app` credential oracle via the immune hand-rolled signer, and a decision rule that selects exactly ONE of four fix branches (H1 App-ID drift / H2 key↔App mismatch / H3 clock skew / H4 octokit DER extraction).
- H1 (wrong/malformed `GITHUB_APP_ID` in `iss`) is the lead hypothesis, strengthened by SDK source: `@octokit/app` accepts `appId: number | string` and never validates it; a client-id-shaped (`Iv23…`) or whitespace App ID is silently signed into the JWT and only GitHub rejects it. A `readAppId()` numeric guard is the only pre-GitHub catch point.
- Surfaced a non-obvious H4 constraint: the `@octokit/app` constructor has no explicit-JWT injection option, so "route through the immune signer" requires a `createAppAuth`/`authStrategy` override.
- Pinned the H3 infra root to `apps/web-platform/infra/inngest.tf` + `cloud-init.yml` (verified no existing time-sync config); added a runbook-correction phase since the current runbook falsely claims #4569 resolved the class.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, Write/Edit
