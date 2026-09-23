# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #8600
- Scope check: `git diff origin/main...HEAD --name-only` returned only `plans/` + `specs/` paths — subagent stayed in mandate.
- Collision re-probe after planning (required by one-shot Step 0a.5, point-in-time not a lock):
  #8036 OPEN, #7295 OPEN (plan-discovered `closes:`); `linked:issue --state all` and
  `#N in:body --state open` both empty for each. No collision.

### Errors
None that blocked. Three recovered in-session (recorded by the planner):
- A pre-tool guard refused a scripted append (flagged Doppler CLI string in prose); the retry
  silently dropped `## Scoped Advisor Consult` while two later sections still cited its evidence.
  Caught by section-count discipline.
- A scripted splice ate a closing code fence, which swallowed `## Guard Contract` from
  `lint-guard-contract.py` — it reported zero entries over a file with three. Proven by driving
  the lint RED, not by trusting a green.
- A literal `|` inside a markdown table cell broke markdownlint code-span pairing, producing
  MD038 errors ~600 columns from the real cause.

### Decisions
- **The operator's stated scope was wrong in one respect, and the plan says so.** The ruling names
  sweeping "the home docker config". `ci-deploy.sh` runs under `webhook.service` with
  `ProtectHome=read-only` and `/home` absent from `ReadWritePaths`, so that sweep is structurally
  impossible from that unit. The sweep covers the **deploy** config only; the home entry is
  observed, not swept. Grading the close criterion on `home_ghcr_auth=none` would have kept
  #8036 open forever.
- **The close criterion as stated was vacuous.** "`stage=relogin_failed` absent" also passes on a
  host that stopped deploying. It is now a three-leg conjunction graded per `_MACHINE_ID`,
  discriminated by a `swept=` token the pre-1c script cannot emit — `deploy_ghcr_auth=none` alone
  would pass on a freshly provisioned host running the old code.
- **The sweep is `docker logout ghcr.io`, not a hand-rolled `jq` rewrite.** Five existing workflows
  already use that idiom; the jq form would delete the new write path and carries a mode hazard,
  an extra acceptance criterion and a `credHelpers` blind spot.
- **ADR-096's soak verdict is a recorded FAIL on live operands**, not a dark operand (first framing
  was wrong). The plan authorizes a *partial* 5.3 on the narrower ground that the branch being
  deleted has no reachable success arm — measured, with a public-package control.
- **Two scope challenges declined, not applied**: shipping as two PRs, and absorbing
  `cosign-verify-live-8037.sh`. Both recorded in `decision-challenges.md` for `ship` to surface.

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` ·
`soleur:engineering:research:repo-research-analyst` ·
`soleur:engineering:research:learnings-researcher` · `Explore` ·
scoped strong-model advisor consult (Phase 4.5) · `soleur:engineering:cto` (structural + devex
seats) · `soleur:engineering:review:dhh-rails-reviewer` ·
`soleur:engineering:review:kieran-rails-reviewer` ·
`soleur:engineering:review:code-simplicity-reviewer` · `lint-guard-contract.py` ·
`lint-infra-no-human-steps.py` · `markdownlint-cli2`
