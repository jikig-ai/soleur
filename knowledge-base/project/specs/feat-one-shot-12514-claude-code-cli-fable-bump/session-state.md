# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-10-chore-bump-claude-code-cli-fable-5-2-plan.md
- Status: complete
- cto_spawns=0 (technical-ruling gate rc=0 after a category/pipe rewrite; no gate-driven spawn)

### Errors

- plan-sharp-edges.md read page 1 + keyword scan only (context budget).
- deepen-plan ran a bounded panel (security, test-design, negative-claims check); disclosed in the plan's Enhancement Summary.
- Planning host ran the 2.1.321 / 0.3.321 binaries once for a fake-key init probe before the CTO F15 ruling; disclosed as F15.

### Decisions

- Pin exactly claude-code 2.1.321 and agent-sdk 0.3.321 (SDK in lockstep, pen-cli override and lockfile in the same commit) - CTO F1, F2.
- No release-age waiver; pin commit only after 2026-11-12T19:04Z - CTO F3, F15.
- sdk-bump-verified trailer carries the full real-SDK sandbox evidence plus cron hook probe, in a throwaway container - CTO F4, F12, F15.
- Two standing guards (model ids from AUTOFIX_PAIRS plus AGENT_DEFAULT_MODEL; default-effort rows) in both binaries; folds in #8643 - CTO F6, F6r, F9.
- Correct four "unverified" prose sites to measured fact - CTO F7.

### Components Invoked

- soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan; agents cto, learnings-researcher, cpo, dhh/kieran/simplicity/architecture reviewers, spec-flow-analyzer, security-sentinel, test-design-reviewer.

## Operator Constraints

- constraint: Needs a CTO ruling on the supply-chain bump, the sdk-bump-verified ack, lockfile regeneration, and confirmation that the fable alias resolves to 5.2 on the chosen version.
- cto_spawns=1 (install.cjs diff ruling, Phase 1.1)

## Work Phase (pre-floor pause, 2026-11-10)

- Done: Phase 1.1 static checks (PR #12553 body), guards 4/5 + AGENT_DEFAULT_MODEL + shared AUTOFIX_PAIRS parser + selection edges (bcb741870b), prose sweep (a7a129c406), F16 plan amendment (e028194729). Pushed.
- Local verification: targeted vitest 181 pass / 2 fail by design (real-binary rows on 311 pins), tsc rc 0, bun model-launch-review 33/0, orphan lint rc 0.
- Affected gate: UNRESOLVED, nothing measured - the runner-lib edit forces MODE=full (runner-changed), and the full run was refused (sibling full-gate in flight). Run the full gate after the pin commit, when the 2 by-design rows should be green.
- Paused: release-age floor clears 2026-11-12T19:04Z. Resume at plan Phase 2.1.
