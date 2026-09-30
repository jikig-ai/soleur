# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-feat-inngest-provision-degraded-sentry-alert-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Operator authorization (recorded 2026-09-30)
The operator chose the second Sentry alert rule on #9299 ("let's go with a second Sentry alert"). Merging this PR auto-runs `apply-sentry-infra.yml`: 1 create (`inngest-provision-degraded`) plus 1 in-place update (`inngest-provision-failure` narrowed to `provision_attempt_failed`). Authorized. No other production writes. Admin merge is allowed when CI is green (no workflow files are edited). After merge, verify both live rules by a read-only projection diff against `alert-reference.json`.

### Errors
- markdownlint MD038 on two code spans (fixed before commit).
- One item in the planner's own verify-agent prompt was wrong (#7142 was never cited); dropped.

### Decisions
- New rule `sentry_alert.inngest_provision_degraded`:
  - one condition, `stage eq bootstrap_done_degraded`;
  - trigger `event_frequency_count > 0 / 1h`;
  - `frequency_minutes = 33` (unused; #9263 claims 29 and 32);
  - no `detail nc` row (DC-2);
  - no first-seen or regression triggers (DC-4).
- Narrowed rule: `stage eq provision_attempt_failed` plus `depends_on = [sentry_alert.inngest_provision_degraded]`, so a failed create cannot leave the degraded stage paged by nothing (DC-1, DC-6).
- Op-contract test renamed to `sentry-inngest-provision-alerts-op-contract.test.ts`. T3 becomes a partition check over the two rules. New rows T1b, T2b, T4c and T7b; both rules forbid `environment =`.
- The C4 count bump to "36 of the 38" is kept (DC-5).
- Runbook: add a sibling degraded-page section and drop the shared-throttle caveat. ADR-257 gets exact edits to its two blockquotes. The learning gets an appended dated note only.

### Components Invoked
- soleur:plan, including learnings-researcher, an advisor consult and a read-only Sentry probe
- soleur:plan-review: DHH, Kieran, code-simplicity, CTO
- soleur:deepen-plan: observability-coverage-reviewer, test-design-reviewer, a verify sweep
- lints: markdownlint-cli2, lint-infra-no-human-steps.py

## Work Phase
- Status: complete (commit e4d3c4c7f0 for rules/reference/README/test; docs commit follows)
- RED on base `.tf`: 7 failed / 6 passed (T1b, T2b, T3, T4b, T4c, T7b, T8). GREEN: 13/13.
- T25: 65 passed, 0 failed. `terraform fmt -check` clean; `validate` green (init -backend=false, scratch copy).
- C4: c4-count-parity, c4-model-freshness green; c4-code-syntax + c4-render 35/35.

### Mutation tally (control 13/13 green; every mutation confirmed landed; pristine restore verified)
| Row | Result |
| --- | --- |
| M1 rename degraded label | RED: T1b, T2b, T3, T7b, T8 |
| M2 re-bundle failure `in` | RED: T3 |
| M3 degraded value typo | RED: T3 |
| M5 extra warning emit | RED: T3 |
| M6 degraded freq 120 | RED: T7, T7b |
| M10 stage in cloud-init.yml | RED: T8 |
| M11 environment on degraded | RED: T1b |
| H1 `#`-commented stage row | RED: T2b, T3, T8 |
| H1b `//`-commented stage row | RED: T2b, T3, T8 |
| H2 block reorder + field order swap | GREEN 13/13 (as required) |

### Decisions (work)
- ADR-257: appended `Superseded 2026-09-30 (#9299)` pointers under both #9176 blockquotes instead of rewriting them (dated records are append-only). AC8 amended in the plan to match.
- Degraded-rule comment states the detail's real shape (`why=<reasons>.attempt=<n>.iid=<iid>`), not "only the two reasons", after reading cloud-init-inngest.yml.

## Review Phase
- Panel (10/10 returned, report-only at 3195d89649): security, test-design, architecture, pattern, code-quality, git-history, data-integrity, performance, agent-native, semgrep-sast (0 findings, 142 rules on 2 files).
- Findings: 0 P1 / 3 P2 / ~12 P3. All fixed inline in dbdb4fc66d except the wontfix items below; filed as scope-out: 0.
- Structural-cause roll-up: every test-design survivor was one gap. The absence claims covered only the kinds in the author's head (tagged rows, #/// comments, email actions, the provision block). Fixed by pinning whole multisets and shapes.
- Wontfix: folding the T1/T1b, T2/T2b and T7/T7b pairs into `describe.each` (the row ids are the plan's and the mutation ledger's, and folding renumbers them); the repeated "a second email is not a duplicate" point (each runbook section is a landing point).
- Coordination: posted on #9263 that whichever merges second must re-count README and the C4 `sentry -> founder` text.

### Mutation battery after the fixes (control 13/13; every row landed; pristine restore verified)
| Row | Result |
| --- | --- |
| M1, M2, M3, M5, M6, M10, M11, H1, H1b | RED as before |
| X1 level row on degraded / X2 on failure | RED: T2b / T2 |
| X3 count = 0 | RED: T1b |
| X4 /* */-hidden enabled = true | RED: T1b |
| X5 depends_on dropped | RED: T1 |
| X6 trailing-comment trigger | RED: T2b, T7b |
| X7 NIC script emits provision_attempt_failed | RED: T3 |
| X8 second bootstrap_done_degraded emit in on_exit | RED: T3 |
| X10 one-line extra action filter | RED: T2b |
| X11 extra first_seen_event trigger | RED: T2b |
| X12 lifecycle dropped | RED: T1b |
| X13 locals block after the resource | RED: T1b |
| H2 reorder + field swap | GREEN (as required) |
- X9 (emit wrapped in `if false`) cannot be seen by a static test; `cloud-init-inngest-provision-unit.test.sh` row TD1 reds on it (test-design seat).
