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

## Review round — PR #8600, 10-seat panel (2026-09-23)

**Every seat returned BLOCKING.** Class: the GHCR *code* was deleted while its *claims*
stayed live. Full findings and dispositions in `tasks.md` Phase 7.

Four findings the lead reproduced independently rather than taking on report:

- **`docker logout` does not sweep a helper-backed config** (3 seats). Measured on docker
  29.7.2, throwaway `DOCKER_CONFIG`, no network, four config shapes. With
  `credHelpers["ghcr.io"]` or a global `credsStore`, the verb exits 0 with the same
  "Removing login credentials" line and leaves the file byte-identical. `swept=yes` was
  therefore being emitted over a live revoked PAT, and leg 1 could never go green.
- **`ZOT_GATE_STATUS` reached no sink** (1 seat). `pull_failure_event`'s second argument is
  classifier input only; the journald line omitted it and the Sentry payload had no detail
  field. The repayment recorded in DC-W6 did not exist as written.
- **The leg-2 latch** (1 seat). One pre-1c relogin row inside a window the design
  deliberately opens to them pinned the tracker shut forever.
- **AC-F8's ref guard could not see `pull_failure_event`** (1 seat): `IMAGE_PULL:` is not a
  substring of `IMAGE_PULL_FAIL:`, and zero rows asserted that record anywhere.

**One panel claim corrected by measurement.** The structural seat reported the deleted
#6400 probe would red the sweeper workflow indefinitely. It does not: #6400 closed 63 days
ago, the open-set query is `--state open` and the closed-set query is
`closed:>=now-CLOSED_LOOKBACK_DAYS` (14), so it is selected by neither. `fail()` is also an
stderr print, not the run's `exit 1`. Striking the directive is ship-time hygiene, not a
blocker. Recorded because acting on the reported severity would have been wasted work.

**Two branch bugs the gates caught, not the panel.** `production's` — an unescaped
apostrophe inside a single-quoted `printf` — made the private-NIC alarm step unparseable as
bash, so it could not execute at all; and two `grep | head | cut` captures could abort the
suite under `set -e`. Both were introduced by this PR before the review round.

### Components Invoked (review round)

`soleur:review` · 10-seat panel: `security-sentinel` · `architecture-strategist` ·
`code-quality-analyst` · `pattern-recognition-specialist` · `code-simplicity-reviewer` ·
`test-design-reviewer` · `observability-coverage-reviewer` · `data-integrity-guardian` ·
`agent-native-reviewer` · structural-enumeration seat (guard-shaped diff) ·
`lint-workflow-run-body-syntax.py` · `lint-shell-capture-exit.py` ·
`lint-credential-path-literals.py` · `lint-window-closure-assertion.py` · `shellcheck` ·
`markdownlint-cli2`
