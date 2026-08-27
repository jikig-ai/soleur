# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-26-fix-release-build-dockerignored-import-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Two recoverable:
- The IaC write-guard hook rejected the plan twice; trigger was the phrase "out-of-band", not
  operator framing. Rephrased rather than opted out.
- A hypothesised second latent build break in `lib/feature-flags/identity.test.ts` was refuted by a
  green run before reaching the plan. The refutation is recorded because it corrected the Guard
  Contract.

### Decisions
- The issue is misdiagnosed; 3 of its 6 scope items were cut. The `claude-agent-sdk` ESM line and
  the `cron-ux-audit` critical-dependency trace are webpack WARNINGS, present verbatim in the last
  green run that deployed to production (`32414879638` / `dc201e75`). `serverExternalPackages` has
  listed the package since the MVP commit. The real fatal error is `vitest.config.ts:4` importing
  `./test/repo-wide-suites`, which `.dockerignore` strips — introduced by #7666 on 08-20. The
  freeze is 6 days, not 19; the 08-07..08-10 failures the issue cites had a different cause
  entirely (zot mirror `DIGEST_INVALID`).
- Alerting scope item cut as already-bought. Three channels fired continuously: release-failure
  email (measured HTTP 200), the drift alerter returning `DRIFT_SUSTAINED`, and standing P0
  `action-required` issue #7676, open since 08-21. The gap was response, not detection — the plan
  names response latency as knowingly unaddressed rather than letting a deferral imply coverage.
- Fix flipped from a `.dockerignore` re-include to `git mv`. The Dockerfile runner stage copies no
  app-root file but `next.config.mjs`, so the "it would ship into the runtime image" objection was
  false. The move deletes the cross-boundary edge instead of creating a permanently-guarded
  exception, matching how the structurally identical #6852 was fixed.
- Regression guard collapsed to one predicate, then gained three chokepoints: tsconfig `@/` alias
  extraction, two-sided membership, and specifier resolution.
- The freeze is not uniform. `apply-web-platform-infra.yml` and `apply-sentry-infra.yml` auto-apply
  on merge, so `a05ae1f77` disarmed a Sentry cert monitor live while the producer change making
  that safe stayed frozen. Filed as AC15.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`; agents: `learnings-researcher`, `Explore`,
`architecture-strategist`, `test-design-reviewer`, `code-simplicity-reviewer`,
`user-impact-reviewer`; `gh run list/view --log-failed`, `docker build` busybox context probes,
`lint-guard-contract.py`, `lint-infra-no-human-steps.py`.

## Work Phase
- Status: implementation complete (PR-1a)
- Rebased onto origin/main (sibling #7705 touched repo-wide-containment.test.ts)

### Measured preconditions (2026-08-26)
- Prod frozen at `build_sha=dc201e757f63faa2001b4cf3e4ae4d8e6748bb38` — matches the plan's expected
  pre-fix value, corroborating "last green run = dc201e75 / 2026-08-20T20:35Z".
- Real failing build log (run 32860030881): `Failed to compile.` →
  `Type error: Cannot find module './test/repo-wide-suites'` at vitest.config.ts:4. The
  claude-agent-sdk ESM line and the cron-ux-audit trace precede it as WARNINGS.
- Zero undeployed Supabase migrations.
- Reference set: 5 sites, exactly as planned.

### Acceptance criteria
- AC1 — 0 residual `test/repo-wide-suites` refs: PASS
- AC2 — busybox context probe, file PRESENT post-fix (ABSENT pre-fix): PASS
- AC3 — `docker build --target builder`: PASS, rc=0, image produced, all 6 builder stages.
  Load-bearing twice over: no second failure was masked behind the type error, AND the build
  succeeded WITH the claude-agent-sdk ESM warning present — empirically falsifying the issue's
  stated root cause in-session.
- AC4 — `tsc --noEmit`: PASS, 0 errors
- AC5 — full battery: 348/350 suites, 0 killed, 1 declined (not relevant to diff).
  1 FAIL: `scripts/orphan-process-reaper-mutations` — 603/604 assertions pass; the single failure
  is a WALL-CLOCK BUDGET assertion (285722ms vs a 240000ms ceiling), not a correctness failure.
  Not attributable to this diff: the only `scripts/` change is a one-line comment fix. A sibling
  worktree was measured running the full battery concurrently. An isolated re-run is queued to
  execute once the machine reports CAPACITY_OK.
- Lint: eslint 0, shellcheck 0 (discharging the LEFTHOOK=0 commit obligation).

### Verified independently (not restated from the plan)
- Dockerfile runner stage copies no app-root file except `next.config.mjs`, so the move adds
  nothing to the shipped image.
- `.dockerignore` already documents this failure class from an earlier occurrence.
- Split-brain: `apply-web-platform-infra` and `apply-sentry-infra` both succeeded on FIVE
  consecutive commits (a05ae1f77, 924994b2f, c33e7d88a, 42df7d416, f2f3cc4bc) whose image
  releases all failed. Stronger than the plan's single-instance framing.

### Session errors
- Scratchpad under /tmp was reaped overnight, losing the first battery log and four issue drafts.
  The commit survived; the tree was byte-identical to when AC3 ran, so AC3 was not re-run.
  Durable artifacts now live in /var/tmp. Worth compounding: agent scratch under /tmp is not
  durable across a day boundary on this machine.
