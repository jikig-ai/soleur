# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-16-fix-cron-gitconfig-containment-plan.md
- Status: complete
- cto_spawns=0 (pipeline-level; planning subagent ran 6 CTO spawns internally)

### Errors
- security-sentinel during deepen-plan was stopped by model safeguards before reporting; AC12 keeps a security-sentinel seat in the review round on the real diff.
- Plan review caught a vacuous NBSP-before-git test design (splitSegments trims U+00A0); fixed in plan.
- Sharp-edges pass found two token-bearing runProc("git") calls in cron-github-cidr-refresh.ts missed by census; added.
- decision-challenges.md had four failing rows; fixed (gate PASS, 31 rows).

### Decisions
- A1 (CTO): fail-closed deny of irregular git/gh command words replaces the both-views design.
- F-A/A2/H5 (CTO): CRON_GIT_CONFIG_PIN in host-git.ts, spread last in all env literals + chokepoints; 7 inherited-env git call sites pinned; bash helpers via withCronGitConfigPin.
- A3/G6/H5 (CTO): write-protect .gitconfig, .config/git, /usr/local/share/soleur on raw+normalised path; TS-compiler-API census with stored per-file maps.
- G2/H1/H3/H4 (CTO): Sentry state-change probes; cron-containment-new-rule-deny event; AC14 read-only post-deploy check.
- Prod HOME assumed writable per Dockerfile and deploy flags; not checked live.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (x6), dhh/kieran/simplicity/architecture/test-design/user-impact reviewers, spec-flow-analyzer, security-sentinel (stopped), learnings-researcher, cpo, gdpr-gate

## Operator Constraints

- constraint: At most one PR.
- constraint: Standing epic constraints apply: dark-launch posture, no flag or prd setting changes, no prod writes.
- constraint: OUT: GIT_CONFIG_COUNT / safe.bareRepository pins; any change to the agent-session env in agent-env.ts; any Dockerfile change; any flag or prd setting change.
- constraint: Prod HOME: treat it as writable and keep P1. The PR body says "assumed writable per the Dockerfile and deploy flags; not checked live".
