# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-08-chore-zot-pin-v2-1-22-and-docker-pkg-github-deny-registry-replace-plan.md
- Status: complete

### Errors
None blocking (playwright MCP failed to connect; not needed).

### Decisions
- D1 (lead decision): keep "do not touch web-1/web-2": the merge carries [skip-web-platform-apply] and [skip-deploy-fix-apply] on their own lines in a branch commit body; running-host delivery is tracked separately.
- D4 (lead decision): no pre-authorised re-dispatch; on any failure mid-replace, stop and report with the recovery-read block, then wait for an explicit go.
- registry-host-replace has no plan_only; substitute offline render diff + PR-time rehearse jobs + read-only local preflight.
- v2.1.22 bump has one breaking change (dedupe HEAD semantics); step 3b scan with a stop rule.
- PR for the ubuntu half is still open; this PR uses Ref #9252, never Closes.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan and review agents.
