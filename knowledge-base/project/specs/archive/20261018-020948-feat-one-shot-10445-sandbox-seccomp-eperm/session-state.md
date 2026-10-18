# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-16-fix-hosted-agent-bash-apply-seccomp-userns-eperm-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=3

### Errors
None blocking. Runbook deploy-status-debugging.md lives at plugins/soleur/skills/postmerge/references/. Stub-model SDK Bash smoke capture is an unproven time-boxed spike (CI capture fallback).

### Decisions
- Root cause: our bwrap-shim seccomp filter denies unshare(CLONE_NEWUSER), which the SDK apply-seccomp helper needs; every session on every host fails. Canary replay ends in `-- true` so it never runs the wrapper.
- Fix (CTO-ruled): set sandbox.network.allowAllUnixSockets=true so the helper is skipped; conditional on a runtime two-session socket test, else own socket(AF_UNIX) deny ships in this PR.
- Detection: widen classifier + Better Stack logtail alert (threshold 1); Stage B end-to-end SDK Bash smoke, non-blocking first.
- Record: PIR via incident skill + ADR-079/ADR-075 addenda, no new ADR.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents cto (x2), cpo, learnings-researcher, five plan-review seats.
