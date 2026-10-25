# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-25-feat-ship-terminator-journald-to-better-stack-plan.md
- Status: complete (the first planning attempt was cut off by an API limit and lost its uncommitted work with the worktree directory; a second attempt committed and pushed as it went)
- Plan artifact: complete (selector=branch)
- Draft PR: #10975. Epic #10205, item #10136, ADR-294. Brand-survival threshold: single-user incident.

### Errors
- The first planning subagent stopped on a weekly rate limit; its worktree directory was gone and nothing had been committed. Recovered by re-attaching a worktree to the existing branch, rebasing the init commit and re-running planning.
- Local run of `cloud-init-inngest-bootstrap.test.sh` fails its tool-gated assertion-count floor because `cloud-init` is not installed locally (CI installs it).
- No `vector` or `stunnel` binary locally: the stunnel line shapes were measured in an alpine container; Vector VRL is untested until the work phase.

### Decisions
1. Admission by unit: add `soleur-inngest-tls.service` to Source 1 `include_units` and Source 2 `exclude_units`; the Source 4 identifier route was rejected.
2. Fail-open drop-list filter for the three healthy-request stunnel lines (infallible VRL); budget 400 rows/day before a flip, 8,000 after.
3. Web-host fan-out accepted: the merge re-delivers `vector.toml` to web-1 and web-2 (observability only, `.prev` restore kept).
4. Replace gating: a separate `user_data` trim PR plus a CI-rendered margin of at least 300 B on current main must land before the replace go is asked; #10543 fixed is a hard precondition; the go names image tag, digest and host id.
5. Security: Doppler-token scrub rule, a pin that the stunnel config has no `debug` key, admission rows that keep the `inngest-tls-health` crit row shipping.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:gdpr-gate; agents: learnings-researcher, soleur:engineering:cto (x2), soleur:product:cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, observability-coverage-reviewer, user-impact-reviewer.

### Constraints carried (owner, verbatim in force)
Arm nothing and merge nothing; no Inngest host replace, no flip, no apply dispatch; no Doppler writes; production evidence only through Better Stack; A5/A6/A7 stay owner-typed.
