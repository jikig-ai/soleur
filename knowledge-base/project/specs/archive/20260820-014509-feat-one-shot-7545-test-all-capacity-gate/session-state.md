# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-19-chore-test-all-pre-launch-capacity-gate-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #7614
- Collision gate: cleared at Step 0a.5 and re-probed after planning. Plan frontmatter is
  `issue: 7545` / `closes: 7545` — no target drift, so no new refs required checking.
  Merged PR #7538 surfaced on both the `linked:issue` and body-text probes with a non-empty
  path intersection (`scripts/test-all.sh`), but its `closingIssuesReferences` is
  `[7402, 7429, 7523]` and #7545's body files that work under "already done".
  Same file, different concern → citation, not collision.

### Errors
None blocking. Two recoverable in-session issues, both resolved by the planning subagent:
- `iac-plan-write-guard.sh` PreToolUse hook blocked the first plan write on an incidental
  "operator runs" phrase co-occurring with "mount". Fixed by rephrasing, NOT by the ack
  opt-out — there was no real infrastructure step to acknowledge.
- `lint-guard-contract.py` read 0 mutation rows for three guards: escaped pipes (`\|\|`)
  broke its table parser, and no guard carried the `**Mutation matrix**` field the linter
  scopes on. Both fixed; final run rc=0 across 4 guard entries.

### Decisions
- **The hard decline was cut and replaced with a non-blocking pre-launch verdict.** Six-agent
  review converged. Decisive evidence is inside ADR-133 itself: it records
  `LOCK_ACQUIRED … after 616310ms` — a wait redeemed at 616 s that a `>= 1` sibling decline
  refuses at t=0, converting a completed gate into zero coverage. The draft's
  "Pareto, never worse" claim was falsified by the ADR it cited for licence.
- **Root cause found: `TC_LOCK_TIMEOUT` is undersized ~3×.** 900 s against a measured ~45-minute
  hold means the budget expires by construction — that is *why* N runs land together.
  ADR-133's addendum names raising it as "a candidate the original Alternatives never
  considered", so it is licensed where abort-on-timeout and admission-control are recorded
  rejections. This is the fix for the `LOCK_CONTENDED_PROCEEDING` scope bullet.
- **Two blast-radius consumers are moot rather than patched.** `lefthook.yml:234` runs the
  runner at `pre-commit`, so a decline would have blocked `git commit` on any staged
  `*.{ts,tsx,js,jsx}`; and `ship`/`one-shot` document `rc=4` as subagent-only, which would
  have sent a ship session to set `SOLEUR_ALLOW_FULL_GATE=1` — the exact override that
  recreates the incident. v2 changes no exit code, so both dissolve.
- **Diff justification ships as a report, not a fifth relevance array.** Measured ceiling is
  4 gated suites of 167 `run_suite` registrations (~2.4%), against a documented six-site
  change with live defect history. Tightens the operator's own "real but small" steer
  (3 declines of 325).
- **Scope reversals surfaced, not silently applied** — DC-1 and DC-2 in
  `decision-challenges.md` for `ship` Phase 6 to render into the PR body. The decline is
  deferred behind #7454 item 3's evidence bar; the shipped verdict line is the instrument
  that produces most of that evidence.

### Open risk carried into Work
- Raising `TC_LOCK_TIMEOUT` means a session can block longer. Plan Phase 0.3 requires
  measuring the real full-gate duration before picking the value — do not pick it by argument.

### Components Invoked
- `Skill: soleur:plan` → `Skill: soleur:plan-review` → `Skill: soleur:deepen-plan`
- Research: `repo-research-analyst`, `learnings-researcher`
- Review panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, `cto` (named-panel relevance gate computed
  independently: `cpo`/`cmo`/`ux-design-lead` inactive, no UI surface)
- Deepen passes: verify-the-negative (12/12 claims `confirms`), post-rewrite stale-reference audit
- Gates: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, deepen-plan halts 4.6–4.11
