---
title: "chore(ci): shard/duration manifest rows for the apply-delivery-gap follower suite"
type: chore
date: 2026-10-23
slug: apply-delivery-gap-follower-shard-manifest-rows
branch: feat-one-shot-follower-suite-shard-manifest-rows
issue: 9454
closes: none
brand_survival_threshold: none
---

# chore(ci): shard/duration manifest rows for the apply-delivery-gap follower suite

Ref #9454 (Merge Queue epic, ADR-270), follow-up 1 of 2. The second follow-up (the `sync-pr-behind.sh` cleanup) is a
separate PR and is not bundled here.

## Overview

`plugins/soleur/test/apply-delivery-gap-follower.test.sh` landed on main on 2026-10-23 together with
`.github/workflows/apply-delivery-gap-follower.yml`. The brief asked for its rows in `scripts/suite-shard-legs.tsv` and
`scripts/suite-durations.tsv`, and told this plan to recommend no change if the row is already covered or tolerated by
design.

**Verdict (CTO-ruled, `decision-challenges.md` Q1): recommend NO manifest change in this PR.**

- The suite is genuinely untabled on `origin/main`, but the gap is tolerated by design: all four manifest tests pass with it
  missing, and the runner hashes an untabled label onto a leg deterministically (ADR-240).
- Open PR #10891 already carries the identical rows (same `--incremental --write` regenerator output). A second writer on the
  two TSVs would only create a `# generated-at` conflict for #10891. The runbook's rule for a TSV conflict is regenerate,
  never hand-merge (`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`).
- #10891 is `MERGEABLE` with `mergeStateStatus: UNSTABLE` (not `BLOCKED`), so no required check stops it today. Its failing
  `affected-index-ratchet` job is advisory (observation window #10865, promotion to required held under #10859), red because
  main already lacks reads declarations for the follower and diagnose-inngest-verify suites (tracked by #10448).
- The deliverable is the evidence record, a minimal tracking issue carrying the flip conditions, and the flip note below.

## Research Reconciliation (brief vs codebase)

| Brief claim | Reality (measured 2026-10-23 on `origin/main` 6b8f7fcaf5) | Plan response |
|---|---|---|
| "no row in `suite-shard-legs.tsv` (662 lines) or `suite-durations.tsv` (659 lines)" | Confirmed: 662 and 659 lines, zero matches for `delivery-gap`. | Premise holds. |
| The gap is one suite | THREE registered-but-untabled labels: `plugins/soleur/test/apply-delivery-gap-follower.test.sh`, `plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh`, `scripts/followthroughs/inngest-verify-clean-10390`. The regenerator cannot add one label; the dry run reports `656 tabled (653 pinned verbatim, 3 new at floor 1204ms)`. | Any landing takes all three (Q2), never a hand-added single row. |
| "the manifest tests tell us what is required" | All four pass today with the rows missing (50, 28, 47, 80 checks). They enforce manifest-subset-of-registered (no phantoms), durations keys equal manifest keys, n equals `ci.yml` N, sorted, no duplicates. Nothing enforces registered-subset-of-manifest. `scripts/test-all.sh` `_shard_selects` hashes an untabled label via `cksum % N + 1`. | The row is not required; this is balance and pricing only. |
| "check open PRs for manifest-file conflicts" | #10891 adds the same three rows plus `tests/scripts/hcloud-token-readonly-no-fallback-scan`, and bumps `# generated-at`. #10900 adds one unrelated row. #10937 removes `scripts/infra-config-activation-7220` from both TSVs and both `.tsv.n` files. #7390 is a DIRTY WIP on the same files. | The premise that nobody is adding these rows is stale: #10891 is. Drives the no-change ruling. |

## Research Insights

**Premise Validation.** Checked: epic #9454 is OPEN; the suite and workflow exist on `origin/main`; both TSVs lack the rows;
the suite is registered (it is in the 656-label `--enumerate scripts` set and `scripts/lint-orphan-test-suites.sh` reports
`736 covered, 0 orphaned`); ADR-240 and ADR-270 read. Held: all of the above. Stale: "one suite is missing" (three are) and
the unstated assumption that no other PR adds the rows (#10891 does).

**Property List.**

1. The follower suite runs on exactly one `test-scripts` leg in CI. (Already true via hash fallback, leg 5.)
2. The suite's weight is priced so the leg that carries it is balanced. (False today; delivered by #10891, not by this PR.)

**Cut List.**

- Landing the rows in this PR while #10891 is open: buys property 2 sooner, but #10891 already queues the same rows and a
  second writer buys a conflict, not a property (Q1).
- Hand-adding a single row: the regenerator already buys property 2 and the 2026-10-14 F5 ruling forbids hand edits of the
  TSVs (Q2).
- Writing `src=measured` for the roughly 100 s suite: `measured` means derived from the CI runs named in
  `generated-from-runs`; the scheduled rebalance covers it (Q3).

**Value-proposition measurement (Phase 0.6c).** The only justification for landing the rows is balance.
`( time bash plugins/soleur/test/apply-delivery-gap-follower.test.sh )` printed `real 1m40.222s` and `691 assertions, 691
passed` (local, cold, indicative only). Hash fallback (`printf %s <label> | cksum`, then `% 8 + 1`) puts the suite on leg 5,
priced 892266 ms, so about 992 s true against the current maximum of 912 s on leg 2: roughly +80 s on the CI critical path.
The regenerator would pin it to leg 1 (priced 566523 ms). A bounded CI-time cost, not a correctness risk, which is why
waiting for #10891 is acceptable.

**Institutional learnings applied.**

- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` (TSV conflict: regenerate, never hand-merge).
- `knowledge-base/project/learnings/2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md`
  (incremental mode floor-prices new labels by design).
- `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`.
- `knowledge-base/project/learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md` (call the floor out, do not
  launder it).
- `knowledge-base/project/specs/archive/20261014-172037-feat-one-shot-8316-retire-inngest-host-dark-gate/decision-challenges.md`
  row F5 (no hand edits of the TSVs; stray `*.tsv.n` untouched).

**Related PRs and issues.** #9454 (epic, stays open), #10891 (carries the rows; also edits
`scripts/lib/test-affected-paths.sh`, which this plan does not), #10900, #10937, #7390, draft #10944 (this branch's PR),
#10448 (affected-index completion), #10865 and #10859 (ratchet observation and promotion). Left untouched per the brief:
#9482, #10245, #5840.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 limit) was scanned for `scripts/suite-shard-legs.tsv`,
`scripts/suite-durations.tsv`, `scripts/regenerate-shard-manifest.py` and
`plugins/soleur/test/apply-delivery-gap-follower.test.sh`: zero matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI-balance data for a test suite. No UI surface, regulated data, infrastructure
resource, or architectural decision (the ADR-240 mechanism is used as designed, so no ADR or C4 change). The observability,
encryption-posture, GDPR and guard-contract gates are skipped: the plan edits no code-class file and introduces no store,
connection or guard.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is a CI shard that runs about 80 s
  longer than it could.
- **If this leaks, the user's data is exposed via:** no vector. The plan reads public repo state and read-only `gh` output
  and writes only planning documents.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no user data, credential, or production path is touched, and the failure is a
  slower CI shard, so neither `single-user incident` nor `aggregate pattern` applies.

`threshold: none, reason: the only paths this plan writes are knowledge-base planning documents; the TSVs under scripts/ are read, never written.`

## Implementation

One work-phase step, then the flip note.

1. **Evidence snapshot and tracking issue.** After `git fetch origin main` and a merge-main under
   `plugins/soleur/scripts/lib/session-state.sh with_lock <name> <timeout_s> -- <command>`, record the dated output of:
   `gh pr view 10891 --json state,mergeStateStatus --jq '"\(.state) \(.mergeStateStatus)"'` and
   `python3 scripts/regenerate-shard-manifest.py --incremental | grep '^vs incumbent:'` (dry run, never `--write`).
   Then create ONE minimal tracking issue (the deferral must not be invisible): title `chore(ci): verify apply-delivery-gap
   follower shard rows landed via #10891`, body = the evidence snapshot, the flip note below, and `Ref #9454` (no closing
   keyword), milestone `Post-MVP / Later`. Skip creating it only if #10891 has already merged and the dry run prints
   `0 new` (record the evidence in the PR body instead).
2. The PR is plan-only and merges as the record through the merge queue (`with_lock merge-main` first); the PR body states
   "no manifest rows added; carried by #10891", includes `Ref #9454`, and contains no closing keyword.

**Flip note (the CTO ruling's contingency, not a phase).** If #10891 is closed unmerged, or merged without the rows (dry run
still prints new labels), run `python3 scripts/regenerate-shard-manifest.py --incremental --write` on a fresh merge-main,
never by hand: it takes all registered-untabled labels (today the three above, not
`tests/scripts/hcloud-token-readonly-no-fallback-scan` while that suite is absent from main), stamps `src=floor`, and bumps
`# generated-at` in both files. Re-run the dry run and require `0 new`. After any later merge-main, regenerate on a TSV
conflict rather than hand-merge. Expect the advisory `affected-index-ratchet` to stay red for the follower and
diagnose-inngest-verify pairs (#10448) and say so in that PR. Leave `scripts/lib/test-affected-paths.sh`, both `*.tsv.n`
files and both heavy tables alone (Q4).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add the shard/duration manifest rows for the apply-delivery-gap follower suite" | Overview verdict, flip note | mapped |
| 2 | "Confirm with the existing manifest tests (scripts-shard-manifest.test.sh, scripts-shard-runtime-coverage.test.sh, scripts-shard-totality.test.sh, regenerate-shard-manifest.test.sh) that the suite is genuinely missing and what the tests require" | Research Reconciliation rows 1-3 | mapped |
| 3 | "if it is already covered or the missing row is tolerated by design and adding it is unwarranted, say so and recommend no change" | Overview verdict, `decision-challenges.md` Q1 | mapped |
| 4 | "Do NOT touch scripts/lib/test-affected-paths.sh" | Flip note, Acceptance Criteria 3 | mapped |
| 5 | "Check open PRs for manifest-file conflicts (gh pr list --state open --json number,files) before editing" | Research Reconciliation row 4, Implementation step 1 | mapped |
| 6 | "reference #9454 only (Ref, no closing keywords); merge via the queue using session-state.sh with_lock merge-main; no SSH; no live credentialed probes beyond read-only gh" | Implementation step 2, Acceptance Criteria 4 | mapped |
| 7 | "Leave #9482, #10245, #5840 untouched. Do not close #9454. A second PR for sync-pr-behind.sh cleanup follows separately; do not bundle it." | Flip note, Acceptance Criteria 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Evidence snapshot (open-PR and dry-run read) | "Check open PRs for manifest-file conflicts" | asked |
| Tracking issue | - | inferred - justification: the plan skill's deferral-tracking check treats a deferral without a tracking issue as invisible, and the brief's own "recommend no change" outcome defers the rows to #10891 |
| Flip note naming the regenerator | "the regeneration path is `python3 scripts/regenerate-shard-manifest.py --incremental --write`" | asked |
| `decision-challenges.md` | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | asked |

### Split Assessment

- Subsystems touched: 1 - `knowledge-base`
- Planned files: 3 | Estimated changed lines: 200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Create

- `knowledge-base/project/plans/2026-10-23-chore-apply-delivery-gap-follower-shard-manifest-rows-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-follower-suite-shard-manifest-rows/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-follower-suite-shard-manifest-rows/decision-challenges.md`

## Files to Edit

None under `scripts/`. The pipeline itself also writes
`knowledge-base/project/specs/feat-one-shot-follower-suite-shard-manifest-rows/session-state.md` and may regenerate
`knowledge-base/INDEX.md`.

## Acceptance Criteria

- [ ] AC1: the evidence snapshot is recorded once with its UTC timestamp (the issue body or PR body): the `gh pr view 10891`
  line and the `vs incumbent:` line. Measured while writing this plan: `OPEN UNSTABLE` and
  `vs incumbent: 0 moved, 3 new, 0 no longer registered`.
- [ ] AC2: diff scope: `git diff --name-only origin/main...HEAD` is a subset of the plan, `tasks.md`, `decision-challenges.md`,
  `session-state.md`, and `knowledge-base/INDEX.md`; in particular neither `scripts/suite-shard-legs.tsv` nor
  `scripts/suite-durations.tsv` is in it.
- [ ] AC3: `git diff --quiet "$(git merge-base origin/main HEAD)" HEAD -- scripts/lib/test-affected-paths.sh
  scripts/suite-shard-legs.tsv.n scripts/suite-durations.tsv.n scripts/suite-shard-legs-heavy.tsv
  scripts/suite-durations-heavy.tsv` exits 0.
- [ ] AC4: the PR body contains `Ref #9454`, and `grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#' <body>` prints 0 and
  `grep -ci 'ssh' <body>` prints 0 (both counted over the body text the agent wrote, before any appended attribution line).
  This PR makes no edit to #9454, #9482, #10245 or #5840.
- [ ] AC5: `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0 (measured: `4 rows examined`
  before the taste rows were appended; re-run after any edit to `decision-challenges.md`).
- [ ] AC6: unless #10891 has already merged with `0 new`, a tracking issue exists whose body carries the evidence snapshot,
  the flip note, and `Ref #9454`.

## Test Scenarios

- Given this PR is plan-only, when `git status --short scripts/` is run on the final tree, then it prints nothing
  (integration; same assertion as AC2).
- Given a later contingency run of the flip note, when the dry run is repeated after `--write`, then it prints
  `0 moved, 0 new, 0 no longer registered` (integration; contingency only).

## Sharp Edges

- A green `scripts-shard-manifest` run is NOT evidence that the rows exist: the tests pass with them missing. The dry-run
  `vs incumbent:` line is the single authority (it compares the registered set to the manifest).
- The regenerator stamps `src=floor` (1204 ms) for a suite that takes about 100 s locally; do not relabel it `measured`.
- `--incremental --write` rewrites tracked files under `scripts/`; the dry run (no `--write`) does not. This planning run
  executed `--write` once and reverted with `git checkout -- scripts/`.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one carries
  all three lines.
