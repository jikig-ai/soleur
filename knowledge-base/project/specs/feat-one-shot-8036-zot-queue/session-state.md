# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-21-fix-zot-queue-dead-ghcr-credential-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Post-plan collision re-probe (2026-09-21): #8036 #8037 #8417 #8408 #8449 all OPEN, no linked or open body-ref PRs besides draft #8456.

### Errors
None (one transient GitHub rate-limit stall; one aborted scripted edit redone).

### Decisions
- 1a: empty `{"auths":{}}` DOCKER_CONFIG + `env -u DOCKER_AUTH_CONFIG` on cosign verify only; 1b marker emits fixed status words, no identity; 1c recommended in PR body (retire host GHCR login, keep CI dual-push).
- #8417: fix both `$$` sites (line 191 PATH and 788 STORE_PROBE_RC), set `_bk_rc=0`; guard over all 8 rendered templates; merge fires registry replace — no "deployed" claim until a new boot shows `cs0.bk0`.
- #8408: (a) Better Stack alert on heartbeat format, >=2 bad rows; (b) zot start gated on in-volume marker + network-guard recovery; (c) daily passphrase test with mem precheck + OOM shield, result on heartbeat.
- #8449 UC2: dispatch workflow, fail on non-zero, never publish host output. #8278 stays blocked with recheck comment. Sweep issue filed last.
- One PR, separately revertable commits; ADR-087/ADR-096 amended; C4 second host→GHCR edge.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, cto, dhh/kieran/simplicity reviewers, security-sentinel, architecture-strategist, observability-coverage-reviewer, test-design-reviewer.
