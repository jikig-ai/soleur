# Tasks — feat-one-shot-9771-testing-strategy-skill

Plan: `knowledge-base/project/plans/2026-10-19-feat-testing-strategy-residual-machinery-plan.md`
Ruling record: `knowledge-base/project/specs/feat-one-shot-9771-testing-strategy-skill/decision-challenges.md` (items 1–3)

## 1. Setup

- [x] 1.1 Confirm worktree/branch: `git branch --show-current` → `feat-one-shot-9771-testing-strategy-skill`
- [x] 1.2 Re-read the WARN-rule context: `### Verdict rules` + the unit-row declared exception in `plugins/soleur/agents/engineering/review/test-design-reviewer.md`
- [x] 1.3 Re-read `plugins/soleur/test/test-pyramid-fixtures.test.sh` CENSUS/ROLE/DRIFT blocks and the two existing fixtures under `plugins/soleur/test/fixtures/test-pyramid/`

## 2. Core Implementation (RED first — cq-write-failing-tests-before)

- [x] 2.1 Extend `test-pyramid-fixtures.test.sh` FIRST (fails before FR-1 lands):
      census 2 → 4 entries; ROLE map adds `subprocess-fanout-unweighed.diff` → WARN
      role and `pure-sh-assertions.diff` → no-WARN role; DRIFT block pins the new
      WARN vocabulary + the `suite-durations.tsv` anchor in `test-design-reviewer.md`;
      update the header's census comment.
- [x] 2.2 Write `plugins/soleur/test/fixtures/test-pyramid/subprocess-fanout-unweighed.diff`:
      unified diff (`--- /dev/null`, `+++ b/`, `@@`) adding one `.test.sh` that boots
      a stub server (`&` background proc, pgid reaper, bound port), no TSV row.
- [x] 2.3 Write `plugins/soleur/test/fixtures/test-pyramid/pure-sh-assertions.diff`:
      unified diff adding one `test-*.sh` of pure greps/assertions (no spawn signals).
- [x] 2.4 GREEN — `test-design-reviewer.md`: add the FR-1 WARN bullet under
      `### Verdict rules` (NEW `*.test.sh`/`test-*.sh` + subprocess-fan-out signals
      + no `measured`/non-default `floor` row for the suite label in
      `scripts/suite-durations.tsv` → WARN commit an honest floor estimate), plus a
      cross-ref clause in the unit-row declared exception pointing at the rule.
      WARN-only; never on duration alone.
- [x] 2.5 `apps/web-platform/test/README.md`: add "Test file placement" convention
      (`test/<area>/` namespacing mirroring the SUT — `test/app/`, `test/server/`,
      `test/api/`; flat files grandfathered, no mass move).
- [x] 2.6 `apps/web-platform/test/README.md`: add "Flaky-test policy" section
      (CI-only retry cap — `playwright.config.ts` `retries: 1`, never raised
      per-suite to mask; flake → filed issue, `fixme`/skip only with issue ref;
      nightly leg auto-files `ci/integration-suites` on red, auto-closes on green).
- [x] 2.7 Run `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` → exit 0
      (AC-4/AC-5).

## 3. Testing

- [x] 3.1 `grep -n 'suite-durations' plugins/soleur/agents/engineering/review/test-design-reviewer.md` → anchor present inside the new WARN bullet (AC-1)
- [x] 3.2 `grep -n 'placement' apps/web-platform/test/README.md` hits (AC-2)
- [x] 3.3 `grep -n 'flaky' apps/web-platform/test/README.md` hits (AC-3)
- [x] 3.4 `git diff --name-only origin/main...HEAD | grep -c 'skills/testing-strategy'` → 0 (AC-7)
- [x] 3.5 `npx markdownlint-cli2` on edited docs files
- [ ] 3.6 `gh issue comment 9771` — post ruling + adjudications + re-open trigger;
      PR body carries `Closes #9771` (AC-6)
