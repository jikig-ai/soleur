# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-feat-p4b-select-kb-consumers-suite-for-new-fixtures-plan.md
- Status: complete
- cto_spawns=3

### Errors
- Two `gh issue create` attempts were refused by the filing gate (heredoc in the same command; missing `meta/machinery` label); the third succeeded as #11166.
- A cold `--print-selection` derive exceeded 120 s; re-run in the background.
- markdownlint, guard-contract and ruling-gate lints each failed once on the first draft; fixed.

### Decisions
- Re-scope (CTO Option C): `affected-tests.sh` always delegates to `scripts/test-all.sh --affected`, whose selector matches diff paths only. Add a config-declared content trigger (three flat keys in `.soleur-test-gate.json`) that runs `scripts/test-affected-kb-consumers.test.sh` when an added or untracked line in a configured path contains `knowledge-base/`.
- Hook lives in `finish()` behind an explicit `AFFECTED_CT_ELIGIBLE` flag; scan base is `--base`, then `origin/main`, then `origin/master`; scan error fails toward coverage; `--explain` prints `CONTENT_TRIGGER armed=1`.
- Glob set limited to test trees and suite files to keep the trigger rate at or under 10%.
- Pre-push lane gaps filed as #11166.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: repo-research-analyst, learnings-researcher, cto (x3), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer.

## Review Phase (PR #11164)
- Panel SHA afab36463e; fix round 1 = 26fc507942 (explain/escalated-full/quoted-path/caps/deferred), fix round 1b = cf88c536e0 (NUL parity, dead-glob refusals, `--no-renames`, rc/137/cap rows), verification pass followed by the P3 batch below.
- Dedup ledger (raw -> canonical defect key -> reporting seats): the panel's per-seat reports were not retained verbatim, so this is the rolled-up record.
  - explain/`--full`/escalated-full eligibility split -> `adapter-arm eligibility keyed on the operator's --full, not the gate's escalation` -> architecture, security, code-quality (CTO ruling 1).
  - C-quoted, `-diff`/binary, NUL and symlink scan gaps -> `scan population narrower than the added-lines property` -> security, pattern, test-design.
  - unbounded untracked leg -> `uncapped scan cost` -> performance.
  - vacuous-command refusal naming no key; `skipped` mislabelling budget deferral -> `marker vocabulary` -> code-quality, agent-native (CTO rulings 3, 4).
  - dead/never-matching and match-everything globs -> `config validation narrower than its name` -> security, test-design.
  - structural-cause roll-up: guards and fixtures narrower than the property they name (instances above).
- Verification pass (single verifier seat): all nine fix claims closed; no P1/P2. P3 batch applied: bare `.`/`/.` glob refusal, inert exit arms its own budget, `-a` comment honesty, rows for adapter `--explain --full`, probe shapes, inert+CI deferral. Floor raised to 467. Mutants N1-N5 (7 rows) all killed; repo-global ratchets rc 0.
- Not adopted: untracked quoted-path scan-error outside the globs (fails toward coverage, noisy only); plan/tasks files still naming the removed `AFFECTED_CT_EXPLAIN` (historical).
