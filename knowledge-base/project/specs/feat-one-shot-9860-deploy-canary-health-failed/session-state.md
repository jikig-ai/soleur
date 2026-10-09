# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-09-fix-deploy-canary-filecap-bwrap-rollback-plan.md
- Status: complete

### Errors
None blocking. Playwright MCP unavailable (not needed). Sentry RO token cannot list org issues; sentry-issue.sh used instead. Phase 0.5 local repro has no prod apparmor/seccomp profile, so only a real deploy proves the post-fix probe passes.

### Decisions
- Brief premise corrected: tags v0.332.4/v0.332.5/v0.333.0 were NOT built after the module-scope import.meta.url fix (merge-base --is-ancestor false for each); the second cause first appears on v0.333.1 (canary_sandbox_failed).
- Root cause: the Dockerfile setcap on /usr/bin/bwrap makes bubblewrap 0.8.0 refuse every non-root invocation ("Unexpected capabilities but not setuid").
- Fix: drop the file cap (Option O1), PR closes #9871 and refs #9860; the dedicated capped copy suggested in #9871 fails the same way for uid 1001 and is parked for a re-spike.
- One PR, two independently revertable commits: A = Dockerfile + tests; B = remove --cap-add SYS_ADMIN from ci-deploy.sh/cloud-init.yml and a constant-gated skip of the outer-wrap canary.
- Brand-survival threshold aggregate pattern; the fix is only verified by a real deploy reaching the served sha.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, cto, security-sentinel, architecture-strategist, observability-coverage-reviewer, dhh/kieran/code-simplicity reviewers, framework-docs-researcher, learnings-researcher.
