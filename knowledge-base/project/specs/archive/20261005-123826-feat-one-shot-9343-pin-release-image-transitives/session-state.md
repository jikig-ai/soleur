# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-10-04-ci-pin-release-image-transitives-plan.md
- Status: complete
- Draft PR: 9496

### Errors

None blocking. Two minor slips in the planning subagent, both recovered (an over-long `grep` output; a `gh issue create` hook block fixed by adding the `meta/machinery` label).

### Decisions

- The PR edits `.github/workflows/ci.yml` (not `.github/actions/**`), so it must NOT be admin-merged: normal green-CI merge with the merge queue. One PR, no split (CTO ruling).
- likec4: append the literal `--before=2026-09-28` to the Dockerfile install. A lockfile is rejected (breaks the global install layout, conflicts with ADR-050). claude-code: no `--before` (two exact-pinned packages, nothing floating; `--before=2026-09-28` fails ETARGET on 2.1.284); a lock assertion goes into the existing `claude-cli-pin-knows-models.test.ts`.
- PR-time check: the two global installs move into a new Dockerfile stage `cli-tools` that `runner` builds `FROM`; a no-cache `--target cli-tools` build step is added to the existing `web-platform-build` job (about 60 s). A full `--target runner` build was measured at 391 s cold and rejected. The PR body must say "builds the runner stage" is met by its ancestor stage.
- Shard installs: remove the likec4 install from `test-scripts-heavy`; keep it in `test-scripts` (three suites render through `npx` and the install warms the cache). The shard-coverage contract scopes the `likec4` row to the light job. DHH and code-simplicity dissent (keep both) is in `decision-challenges.md`.
- Follow-ups filed during planning: #9497 (scope the gitleaks and bun contract rows per job), #9498 (advisory coverage for the global likec4 tree). Net-issue-flow: this PR closes #9343 and these two count as filings, so fold #9497 in if cheap or consolidate before ship.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: repo-research-analyst, learnings-researcher, functional-discovery, cto, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, security-sentinel, test-design-reviewer.

Remaining: soleur:work -> soleur:review -> soleur:compound -> soleur:ship
