# Tasks: feat-one-shot-12757-cron-gitconfig-containment

Plan: `knowledge-base/project/plans/2026-11-16-fix-cron-gitconfig-containment-plan.md` (Closes #12757, Ref #9601).
Rulings: `decision-challenges.md` in this directory. One PR. No flag, prd, Dockerfile or `agent-env.ts` change.

## Phase 1: Setup and RED tests (plan Phase 0)

- [ ] 1.1 Write the hook rows (plan 3.3) against unchanged source. Record which rows are allowed today and which
  are denied for a different reason.
  - [ ] 1.1.1 Guard 1 rows: `.gitconfig`, `.config/git`, the normalisation rows, the `AGENT_GIT_GLOBAL_CONFIG`
    drift row, the must-pass rows.
  - [ ] 1.1.2 The verb table (5 verbs × 4 forms × roadmap-review and bug-fixer), the 11 single rows, the
    anti-vacuity and table-coverage harness assertions.
  - [ ] 1.1.3 The allowlist census, the raw-rule regression rows and the must-pass rows (these must pass before the
    fix).
- [ ] 1.2 Write `test/server/inngest/cron-spawn-git-config-pin.test.ts` on the TypeScript compiler API. It covers:
  - rows 0, 2, 4, 4b, 4c, 4d, 5, 5b and 6
  - the binding check and its synthetic-source FAIL controls
  - the walk self-test
  - diff-style failure messages and identity-keyed stored maps

  Row 5 uses `gitCleanEnv` plus `fixtureCeiling`, never `gitFixtureEnv`.
  - [ ] 1.2.1 Run the sweep once and seed `KNOWN_HOME_LITERALS` (23 files, 26 sites), `KNOWN_GIT_SPAWNS` (15 pairs)
    and `GIT_CAPABLE_LITERAL_EXCLUSIONS`, classifying every hit (each exclusion needs a reason).
- [ ] 1.3 Extend `cron-claude-eval-substrate-exit.test.ts` with rows 1, 3 and 6. Row 6 is the wiring row,
  filtered by op, and includes the re-arm case.
- [ ] 1.3b Add the partial `@/server/host-git` mock to `test/setup-node.ts` (CTO H1).
- [ ] 1.3c Add row 7 to the deny-marker test: `countNewRuleDenials`, plus the `classifyNewRuleDeny`/`decide()` parity
  check (CTO H3).
- [ ] 1.4 Run the whole of `test/server/inngest/` and capture the RED log for the PR body, using the plan's Phase 0
  pre-fix expectation list. A load or type error does not count as RED.

## Phase 2: Core implementation

- [ ] 2.1 Hook, commit A (plan 1.1): add the three `WRITE_PROTECTED_PATTERNS` entries, the `posix.normalize` arm, and
  the XDG note.
- [ ] 2.2 Hook, commit B on its own, so it can be reverted alone (plan 1.2): `commandWordShapeReason` (position,
  escaped word, `gh api` hint, flag reason), called after `argumentInjectionReason`.
- [ ] 2.3 `server/host-git.ts` gains:
  - `CRON_GIT_CONFIG_PIN`, with the docstring pointer to the census
  - `agentGitConfigReadable(path)`, pure and uncached
  - `xdgGitResidualPresent(home)`
  - `withCronGitConfigPin(env)`
- [ ] 2.4 Substrate chokepoints:
  - `spawnClaudeEval` env and `spawnSimple` env both end with the pin.
  - Re-probe on every call, with a latch that fires on a transition and re-arms. It reports `cron-git-config-pin`
    and `cron-git-xdg-config-present` through `reportSilentFallback` and never blocks.
  - Add `countNewRuleDenials` in `parseClaudeResultLine`, emitting `warnSilentFallback` op
    `cron-containment-new-rule-deny` (CTO H3).
- [ ] 2.4b Export `classifyNewRuleDeny` from the hook and use it in the hook's own new-rule deny paths. Add
  `countNewRuleDenials` to `server/cron-filing-deny-marker.ts`.
- [ ] 2.5 The 26 `HOME:` literals in 23 files: import from `@/server/host-git` and spread the pin last. Fold the
  `buildPublisherEnv` loop into its literal, keeping undefined values (no filter).
  - [ ] 2.5.0 In the four `spawnScriptCapture` helpers, use `env: withCronGitConfigPin(opts.env)` (CTO H5).
  - [ ] 2.5.1 Right after adding the import to `cron-bug-fixer.ts`, run `cron-bug-fixer.test.ts`. If its `node:fs`
    mock breaks, switch it to `importOriginal`.
- [ ] 2.6 Class C sites:
  - strategy-review clone
  - the `spawnGit` helpers in compound-promote, content-publisher, rule-prune and weekly-analytics; remove `env?`
    from their opts types
  - the cidr-refresh `runProc("git", …)` calls at the clone and the status
- [ ] 2.7 vendor-drift `spawnGit`/`spawnGitStdout`: remove `env?` and `...opts?.env`.
- [ ] 2.8 Correct the K2 comment in `cron-gh-output-framing-hook.test.ts` (CTO G1).

## Phase 3: Architecture records

- [ ] 3.1 ADR-033 dated #12757 amendment via `soleur:architecture`. It covers:
  - the I7(a) paths and normalisation
  - the scoped pin invariant
  - the shape rule
  - the residuals: node probes, XDG ignore/attributes, founder-workspace git, non-literal spawn commands, flag-led
    allowlist lines
  - the new-cron checklist item
- [ ] 3.2 ADR-287 addendum item 2: add the one-line dated cross-reference (CTO G1).

## Phase 4: Testing and verification (plan Phase 5)

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` on the five named suites, every edited cron's
  suite, `host-git`, `agent-env` and `dockerfile-git-version-floor`.
- [ ] 4.2 `./node_modules/.bin/tsc --noEmit`.
- [ ] 4.3 The `discoverability_test` probe prints `protected-path write`.
- [ ] 4.4 `bash plugins/soleur/test/c4-count-parity.test.sh` stays green.
- [x] 4.5 Apply the AC10 mutation rows locally, confirm RED, revert, and list them in the PR body:
  - Guard 3 rows #5, #6 and #7e
  - Guard 2 rows #2, #4 and #5
  - Guard 1 rows #6b and #8
  - Guard 3 rows #12-#16, which cover the latch, the bash helper, the pin function, the binding check and row 4d

## Phase 5: Review and ship

- [ ] 5.1 A separate `soleur:review` round with the security-sentinel and user-impact-reviewer seats (AC12). Treat
  any shrink of a stored map, or any new exclusion, as a finding.
- [ ] 5.2 File the CTO G4 follow-up issue under #9601: founder-workspace git spawns in `git-config-atomic.ts` and
  `push-branch.ts`. Give it a re-evaluation criterion and a milestone, and link #12757.
- [ ] 5.3 The PR body carries:
  - `Closes #12757` and `Ref #9601`
  - "Prod HOME: assumed writable per the Dockerfile and deploy flags; not checked live."
  - the RED log
  - the diffs of the stored maps
- [ ] 5.4 After the deploy, run the read-only AC14 checks. No manual cron trigger.
  - (a) Sentry `cron-git-config-pin` and `cron-git-xdg-config-present`
  - (b) the `claude-eval-nonzero-nofix` and no-PR baseline comparison
  - (c) the `bot-fix/attempted` join against `cron-containment-new-rule-deny`
- [ ] 5.5 Put the H2 operator-authorised label-removal line in the revert runbook section of the PR body. Leave it
  empty unless AC14(c) finds issues.
