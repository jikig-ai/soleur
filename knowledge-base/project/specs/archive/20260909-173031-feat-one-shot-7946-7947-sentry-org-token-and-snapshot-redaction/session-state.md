# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-09-feat-sentry-org-token-and-snapshot-redaction-plan.md
- Status: complete (plan + plan-review + deepen-plan; all deepen halts evaluated, 4.6/4.7/4.8/4.11 pass, rest no-trigger)
- Scope verified: `git diff 5c8f42a3c..HEAD --name-only` empty; artifacts untracked under `plans/` + `specs/` only. Planning subagent ran no git write commands, as briefed.
- Collision gate re-probed AFTER planning returned (~2.4h run), per the #7247 lesson that the
  gate covers the issues typed, not the ones the plan decides to close. Plan `closes:` was
  [7946, 7947] — both still OPEN, no closing PRs, no linked PRs. Only body-probe hit remains
  merged PR #7948, discriminated as a citation (touches `knowledge-base/` only; it is the
  compound learning that filed these issues).

### Delivery boundary (DC-1 accepted — see decision-challenges.md §DC-1 RESOLUTION)

This branch/PR #7975 now ships **#7947 only**. Plan frontmatter narrowed to `issue: 7947`,
`closes: [7947]`. #7946 (plan Phase 3) ships on a follow-on worktree and PR because its Phase 3.1
performs live prod mutations (Sentry Internal Integration mint, `gh secret set`, tracker
issue-body rewrites) that require explicit per-command operator authorization under
`hr-menu-option-ack-not-prod-write-auth` — and the #7947 guard must not be parked behind that gate.

Work scope for this PR: Phase 0 (measurement gate), Phase 1 (RED tests), Phase 2 (#7947 GREEN),
and the #7947 slices of Phases 4-6. Phase 3 is OUT OF SCOPE here.

### Errors

None from the planning subagent. One self-corrected false negative it flagged: a research
subagent reported ADR-202 absent after searching `learnings/` instead of `decisions/`; verified
directly and recorded in the plan so the error does not propagate.

### Decisions

- #7946's premise is materially stale: the sweeper already binds the org-level `iac-terraform-prd`
  token. The residual hazard is the env-var NAME `SENTRY_AUTH_TOKEN`, which a local
  `doppler run -c prd_terraform` silently satisfies with the personal credential. Deliverable
  became "retire the ambiguous name and narrow the scopes", not "migrate the token".
- The rename as first drafted would have re-opened #7797 inside the PR that closes it: 13 of 16
  followthrough files carry the ADR-202 xtrace refusal keyed to the OLD credential name, so
  renaming consumption alone leaves the hatch open on the new one. Also draws down 21 Rule D
  baseline entries (`--changed` bypasses the baseline by design). Both budgeted, with guard
  mutation rows that red on the mismatch.
- #7947's premise was unmeasured and the first fix pointed at the wrong provenance: an
  agent-TYPED value is already in the transcript as the tool-call argument, so a probe that fills
  the field measures nothing. Phase 0 sets its sentinel only by non-agent paths and gates Phase 1
  on the verdict, including a "neither leaks" arm that would close #7947 on the measurement.
  Reading installed `playwright-core@1.58.2` moved the premise from unmeasured to strongly
  evidenced: its aria-snapshot generator excludes checkbox/radio/file from value rendering and
  does NOT exclude `password`.
- Scope cut ~25%: both new lints became rule families inside lints that already own their
  populations (zero new `run_suite` lines); compatibility shim and disuse soak probe cut for
  cause. Property P5 rewritten to name its bypasses; P7 stated as NOT achieved on the
  Playwright-MCP path rather than implied away.
- The interceptor moved into the shipped plugin manifest: `plugins/soleur/hooks/hooks.json`
  declares only `SessionStart` and `Stop`, so a hook in `.claude/settings.json` never reaches a
  customer — as drafted, the non-technical operator the plan exists to protect got prose and
  nothing else.

### Components Invoked

- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `Explore` x2, `learnings-researcher`, `repo-research-analyst`, `engineering:cto`,
  `legal:clo`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`,
  `spec-flow-analyzer`, `security-sentinel`, `framework-docs-researcher`, scoped strong-model
  consult, two mechanical realism sweeps
- Gates green: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`,
  `lint-credential-path-literals.py`, `lint-followthrough-varq-ban.sh`,
  `lint-orphan-test-suites.sh`, `bun test plugins/soleur/test/components.test.ts` (1297 pass)
