# Learning: a waived gate step took a sibling step's skip optimization with it

## Problem

PR #12294 let a brief's `ci-is-the-gate` token waive the affected-test step of the Grok pre-push gate. The sibling script
`grok-fidelity-gate.sh` skips the AGENTS rule-budget lint with the comment "grok-pre-push-gate already ran test-all", and
the pre-push script exported that skip unconditionally. With the affected step waived, nothing ran the lint locally, yet the
banner said "the other steps passed". The design, the plan review and a CTO ruling all missed it; one architecture seat found
it by reading the sibling script in full.

## Solution

The dispatch block now carries a `FIDELITY_SKIP_BUDGET` variable (1 by default, 0 on a waive) and the export derives from it.
Tests pin it three ways: the value the sliced block yields, an executable run of the real script from the dispatch block
through the export line, and a footprint count of every reference outside the sentinel blocks.

## Key Insight

When a plan waives, skips or reorders a gate step, grep the pipeline for later steps whose own skip rests on "because X ran".
A waiver changes what every downstream optimization may assume, and those assumptions live in comments, not code.
Separately, three test-harness patterns recurred: a helper that decides its own verdict (`assert_has`) is disarmable
independently of `pass()`/`fail()`, so drive it in both directions; an extraction anchored on a substring or a comment
(`gateLines` stripping comments, a line-wrapped phrase) pins spelling, not the command, so pin the exact fence line;
`printf '<%s>\n' "$@"` prints `<>` for zero args, so loop over `"$@"`.

## Session Errors

- **Plan claim not run: a fence comment keeps the `affected-tests.sh` literal for the DISPATCH pin** — `gateLines` strips comments, so the pin went red. Recovery: widen `gateLines` for work step 9 only. **Prevention:** run the pin a plan names before relying on it.
- **Mutation sandbox had no `.git`** — the suite's `git rev-parse --show-toplevel` row aborted the control (rc 128). Recovery: `git init` the sandbox. **Prevention:** a sandbox for a guard that derives its corpus from git must be a repo; check the control first.
- **T19e control assumed UNDECIDABLE; got OWED** — Recovery: assert the reason text. **Prevention:** measure a control's real output before pinning it.
- **No-arg vs empty-arg indistinguishable in the argv log** — Recovery: log a RUN marker plus one line per argument.
- **Eight unguarded relative operands** in new fixture helpers raised the fixture-relative ratchet. Recovery: the sourced canonical `assert_fixture_dir`. **Prevention:** run the ratchet suites after adding fixture helpers.
- **Waiver hid the rule-budget lint** (above). **Prevention:** plan sharp-edges bullet.
- **Executable slice ran real code** — the harness stubbed `SKIP_BUILD`, `npm`, `step`, `run_step` and now `cd`s into scratch. **Prevention:** stub every command in a sliced span.
- **Hook blocks** on `git commit` with a variable path and on `git stash list`. Recovery: literal paths; no stash. One-off.

## Tags

category: workflow-patterns
module: ship, work, review, grok-pre-push-gate
