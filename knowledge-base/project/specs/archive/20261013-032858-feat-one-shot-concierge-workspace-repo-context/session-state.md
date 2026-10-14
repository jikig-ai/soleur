# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-07-fix-concierge-derive-owner-repo-from-workspace-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause: baseline directive `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` (soleur-go-runner.ts:148-159) tells the agent to infer owner/repo from `git config --get remote.origin.url`, which is empty on a `.git`-less workspace → false "no repo connected" reply.
- Server already resolves `connectedOwner`/`connectedRepo` from the workspace's `repo_url` at cc-dispatcher.ts:1323-1337 but never surfaces them into the cc-path system prompt.
- Fix mirrors leader-path precedent (agent-runner.ts:1429-1441): inject "The connected repository is ${owner}/${repo}" in the cc factory + rewrite baseline directive to drop git-origin inference. Pure prompt-text change.
- Two-file edit: baseline directive in soleur-go-runner.ts; per-dispatch owner/repo addendum in cc-dispatcher.ts.
- Tests: vitest (bun test disabled via bunfig.toml). Threshold = single-user incident → requires_cpo_signoff: true.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- gh issue view (ref verification)
