---
title: "fix(ci): canary #12557 exposes two main-line regressions from #12521 (kb-consumers baseline + ADR-276 MD032)"
type: fix
date: 2026-11-10
slug: fix-ci-canary-regressions
branch: feat-one-shot-12559-canary-regressions
issue: 12559
closes: 12559
lane: cross-domain
---

# fix(ci): canary #12557 exposes two main-line regressions from #12521 (kb-consumers baseline + ADR-276 MD032)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). There is no spec.md for this branch; the assessment below found no relevant domain anyway, so the widened fan-out is moot.

## Enhancement Summary

**Deepened on:** 2026-11-10
**Sections enhanced:** 3 (Research Insights attribution, Observability added, Plan Review note)
**Research agents used:** none — no nested-spawn capability on this harness (per `2026-11-01-devin-subagents-cannot-spawn-nested-subagents.md`); all deepen gates ran as inline mechanical passes.

### Key Improvements

1. Attribution verified against the regressing squash itself, not the issue's prose: `b258336e` is an ancestor of `origin/main` and its diff adds the `ci-oracle-lane.*` names into `scripts/ci-oracle-review.test.sh` (+102 lines), removes 7 lines from `scripts/test-affected-kb-consumers.baseline.txt`, and adds the un-blanked ADR-276 bullet — both regressions in one commit.
2. `## Observability` section added — required by deepen-plan Phase 4.7 (`scripts/*.txt` is not pure-docs); the liveness surface is the gate suites' own verdicts, with a `<15 s` allowlisted probe (`grep -c` → `5`).
3. deepen-plan gates run: 4.6 User-Brand Impact PASS; 4.7 Observability — section added (this enhancement); 4.8 PAT none; 4.9 UI n/a; 4.10 Encryption skip (no store/connection introduced — "merge queue" is the GitHub feature, not a provisioned store); 4.11 Guard Contract skip (deliverable is fixture rows for an existing guard + a whitespace fix — no guard created); 4.12 Scope Check PASS; 4.13 Task Design skip (no new autonomous task); 4.5 network-outage skip; 4.55 downtime skip; 4.4 precedent-diff: row shape follows the `scripts/ci-oracle-lane` precedent at baseline lines 160-164.

### New Considerations Discovered

- The regressing commit deleted 7 baseline rows while adding the lane-file references — the regression is "touched the oracle's inputs without regenerating its baseline", not new drift.

## Overview

Canary PR #12557 (a trivial comment-only diff) fails two required checks on `pull_request`, proving the failures are main-line regressions introduced by the S4-retirement squash `b258336e` (PR #12521): (1) the `oracle-index-check` leg reports five un-baselined kb-consumer rows charged to `scripts/ci-oracle-review`, and (2) `markdown-lint --repo-sweep` reports MD032 at ADR-276 line 694. Both root causes are already diagnosed in #12559 and were re-verified in this worktree; the fix is five two-column baseline rows plus one blank line.

## Research Insights

**Premise Validation** (plan Phase 0.6): issue #12559 is OPEN with the expected title; canary PR #12557 is OPEN with auto-merge armed (`MERGE`, branch `canary-s4-retire-mq`); all five cited files exist on `origin/main`. `collision-precheck.sh 12559` found one open PR naming the issue — **PR #12560, this pipeline's own auto-created WIP draft on this same branch** (no files yet) — plus foreign `test-all.sh` processes in unrelated sibling worktrees (`feat-one-shot-host-git-consumers-hardening`, `feat-one-shot-12514-claude-code-cli-fable-bump`), which explains the box contention observed during verification. No stale premise.

**Property List** (plan Phase 0.6b):

- P1 — `bash scripts/test-affected-kb-consumers.test.sh` exits 0 with the five refs the oracle charges to `scripts/ci-oracle-review` recorded in the baseline.
- P2 — `bash scripts/markdown-lint.sh --repo-sweep` exits 0; MD032 on ADR-276 cleared.

**Cut List**: "Fix the oracle's one-hop TOKEN scan so naming a file does not charge its strings" — buys P1 but changes the guard's semantics beyond the ask; the suite's own contract (header §BASELINE) prescribes recording oracle-visible gaps in the baseline. Cut.

**Baseline contract — the precision point.** Per `scripts/test-affected-kb-consumers.test.sh` header §BASELINE and the oracle's `baseline` mode (embedded python, ~lines 375-383): an **`argv-code` row is `label<TAB>path` — two columns, NO classification column**. Only non-argv-code forms (today the 8 `dir-operand-tests` rows) carry `label<TAB>path<TAB>form<TAB>false-positive: <reason>`, and row c1's UNCLASSIFIED check only fires on `NF>=3` rows. The CI failure output names the form: `VIOLATION scripts/ci-oracle-review knowledge-base argv-code`. **Reconciliation — issue vs. contract:** the issue says "extend the baseline with the five rows classified `false-positive: <reason>`"; the contract says argv-code rows carry no classification, and a 4-column argv-code row would fail check b1 (regeneration emits two columns and the diff would not match). The correct fix is the five two-column rows — exactly what `--write-baseline` emits — with the false-positive reasoning carried in the commit message instead of a baseline column.

**Root cause verified in code.** `scripts/ci-oracle-review.test.sh` names `scripts/ci-oracle-lane.sh` and `scripts/ci-oracle-lane.test.sh` at lines 108-109 (a stub-docs file list) and line 134 (`printf 'scripts/ci-oracle-lane.sh\n' > "$FX/diff-oracle.txt"`, fixture data). The oracle's `argv_code_refs` follows one hop into scripts a suite names (FORMS table, ~line 264), so the lane files' `knowledge-base` strings are charged to the review suite — the same five paths already baselined under `scripts/ci-oracle-lane` at `scripts/test-affected-kb-consumers.baseline.txt:160-164`. These are scan false positives (naming a file is not reading it; the kb strings are lane fixture/pattern data). **Attribution verified against `b258336e` itself** (ancestor of `origin/main`; PR #12521 MERGED): the squash's diff adds those exact `ci-oracle-lane.*` names to `ci-oracle-review.test.sh` (+102 lines), removes 7 rows from the baseline, and adds the un-blanked `- 2026-11-09 S4 retired` bullet to ADR-276 — one commit produced both regressions.

**Regression 2 verified locally.** `node_modules/.bin/markdownlint --config .markdownlint.json knowledge-base/engineering/architecture/decisions/ADR-276-….md` reports exactly `694 error MD032/blanks-around-lists [Context: "- 2026-11-09 S4 retired, verdi..."]` — the bullet at line 694 directly follows the `Notes:` paragraph ending at line 693.

**Relevant learnings**: `2026-11-09-a-comment-cleanup-shipped-a-fresh-false-claim-and-the-affected-gate-timed-out-on-contention.md` — the affected-gate enumeration is slow under sibling-pipeline load (observed: `--print-selection` exceeded a 120 s cap); budget minutes for verification runs, and a timeout is unresolved coverage, not a pass.

**Conventions**: plain TSV, no header line, `LC_ALL=C sort -u` ordering (`scripts/ci-oracle-review` sorts immediately after the `scripts/ci-oracle-lane` block). All markdown must pass markdownlint (constitution Testing §Always). Verify in a real worktree — the suite derives its population from `git` state; the bare repo root does not qualify.

## Implementation Phases

### Phase 1 — Baseline rows (regression 1)

1. Run `bash scripts/test-affected-kb-consumers.test.sh --write-baseline`.
2. Verify `git diff scripts/test-affected-kb-consumers.baseline.txt` shows exactly five added lines and zero removed/modified lines; each is `scripts/ci-oracle-review<TAB><path>` (two columns) for `knowledge-base`, `knowledge-base/engineering/architecture/diagrams`, `knowledge-base/project`, `knowledge-base/project/learnings`, `knowledge-base/project/specs`.
3. If `--write-baseline` emits anything else (e.g. a `UNCLASSIFIED` row from unrelated drift), stop and surface — do not hand-edit around unexpected drift.
4. Record the false-positive rationale in the commit message (the baseline has no column for it on argv-code rows): "naming `scripts/ci-oracle-lane.*` in comments/stub docs is not a read; the kb strings are lane fixture/pattern data (`zzleak-*.md`, the `O-DIAGRAMS-FLAG` arm)."

### Phase 2 — ADR-276 blank line (regression 2)

1. In `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`, insert one blank line between the `Notes:` paragraph (ends line 693) and the `- 2026-11-09 S4 retired, verdict NO-GO …` bullet (line 694). No other edits to the file.

### Phase 3 — Verify

1. `bash scripts/test-affected-kb-consumers.test.sh` → exit 0 (run in this worktree; allow several minutes under box contention).
2. `bash scripts/markdown-lint.sh --repo-sweep` → exit 0.

## Files to Edit

- `scripts/test-affected-kb-consumers.baseline.txt` — five added argv-code rows (two-column TSV) for producer `scripts/ci-oracle-review`.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — one inserted blank line before the `## Amendment 2026-11-09` lead-in bullet.

## Files to Create

None.

## Non-Goals

- Changing the oracle's one-hop TOKEN scan semantics — the suite's contract prescribes baseline recording for oracle-visible gaps (Cut List above).
- Updating canary PR #12557 — post-merge operator step per #12559 (not part of this diff).
- Sweeps of other latent baseline drift — `--write-baseline` output beyond the five rows is surfaced, not folded in.

## User-Brand Impact

- **If this lands broken, the user experiences:** required PR checks (`oracle-index-check`, `quality-guards`) stay red across every open PR — the merge queue stays closed for the product; or a wrongly-shaped baseline row masks a genuinely uncovered knowledge-base reader in a future suite.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user-data surface — the diff touches a test-fixture baseline and an ADR markdown file only.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is CI fixture data plus a docs whitespace fix; the user-facing artifact at stake is CI signal integrity, not user data or workflow.

## Observability

```yaml
liveness_signal:
  what: "the two required check legs whose red state this fix clears: test-affected-kb-consumers (oracle-index-check) and markdown-lint --repo-sweep (quality-guards)"
  cadence: "every pull_request + merge_group run"
  alert_target: "red required check on the PR"
  configured_in: ".github/workflows/ (the legs that invoke scripts/test-affected-kb-consumers.test.sh and scripts/markdown-lint.sh)"
error_reporting:
  destination: "suite stdout in the CI job log"
  fail_loud: "[FAIL] b1: baseline differs from --write-baseline output / VIOLATION rows naming the producer; markdownlint 'error MD032' lines"
failure_modes:
  - mode: "a suite's argv gains a new uncovered kb reference (one-hop name charge)"
    detection: "oracle VIOLATION row + b1 baseline-diff FAIL naming the producer and path"
    alert_route: "red oracle-index-check leg"
  - mode: "a stale baseline row survives the read it recorded"
    detection: "b1 FAIL — regeneration drops the row"
    alert_route: "red oracle-index-check leg"
  - mode: "a markdown structural regression lands under a swept root"
    detection: "markdownlint rule error at file:line"
    alert_route: "red quality-guards leg"
logs:
  where: "GitHub Actions job log for the failing leg"
  retention: "CI log retention"
discoverability_test:
  command: grep -c '^scripts/ci-oracle-review' scripts/test-affected-kb-consumers.baseline.txt
  expected_output: "5"
```

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for `scripts/test-affected-kb-consumers.baseline.txt`, the ADR-276 filename, `scripts/test-affected-kb-consumers`, and `ci-oracle-review`: zero hits.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (procedural lane: lint-fix-class baseline data + one markdown blank line; no new user surface, data store, credential, or workflow).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "extend `scripts/test-affected-kb-consumers.baseline.txt` with the five `scripts/ci-oracle-review` rows classified `false-positive: <reason>` (or `--write-baseline` then hand-classify the UNCLASSIFIED rows)" [issue #12559] | Phase 1 / Files-to-Edit entry 1 | mapped — reconciliation in Research Insights: argv-code rows are two-column, so `--write-baseline` emits the five rows with nothing to hand-classify |
| 2 | "The `## Amendment 2026-11-09` bullet landed with no blank line after the `Notes:` paragraph. Fix: insert the blank line." [issue #12559] | Phase 2 / Files-to-Edit entry 2 | mapped |
| 3 | "After fix merges: `gh pr update-branch 12557` (or push), re-verify green + merge_group covers all 11 required contexts" [issue #12559] | Non-Goals | descoped — justification: issue marks this post-merge, "not part of this plan's edits" per the brief |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 baseline rows | "extend `scripts/test-affected-kb-consumers.baseline.txt` with the five `scripts/ci-oracle-review` rows" | asked |
| Phase 2 blank line | "Fix: insert the blank line." | asked |
| Phase 3 verification commands | "Verify with `bash scripts/test-affected-kb-consumers.test.sh`" / "Verify with `bash scripts/markdown-lint.sh --repo-sweep`" | asked |
| Commit-message rationale (Phase 1.4) | — | inferred — justification: argv-code rows carry no classification column, so the false-positive reasoning must live somewhere; the commit message is the remaining durable carrier |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 2 | Estimated changed lines: ~6
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `bash scripts/test-affected-kb-consumers.test.sh` exits 0 in this worktree, with check b1 (baseline equals `--write-baseline` output) green.
- [ ] `git diff scripts/test-affected-kb-consumers.baseline.txt` shows exactly five added lines — `scripts/ci-oracle-review<TAB>knowledge-base`, `<TAB>knowledge-base/engineering/architecture/diagrams`, `<TAB>knowledge-base/project`, `<TAB>knowledge-base/project/learnings`, `<TAB>knowledge-base/project/specs` — and no removed or modified lines.
- [ ] `bash scripts/markdown-lint.sh --repo-sweep` exits 0; `node_modules/.bin/markdownlint --config .markdownlint.json knowledge-base/engineering/architecture/decisions/ADR-276-….md` reports zero findings.
- [ ] The ADR-276 diff is a single inserted blank line at (former) line 694 — no content change.

## Test Scenarios

- Given the five rows are absent, when `bash scripts/test-affected-kb-consumers.test.sh` runs, then it exits non-zero naming the five `scripts/ci-oracle-review` violations (pre-fix red — already observed in CI per #12559). `integration`
- Given the baseline carries the five two-column argv-code rows, when the suite runs, then it exits 0 and `--write-baseline` output is byte-identical to the committed file. `integration`
- Given the `Notes:` paragraph is immediately followed by a bullet, when `node_modules/.bin/markdownlint --config .markdownlint.json <ADR-276>` runs, then MD032 fires at that line (pre-fix red — verified locally). `unit`
- Given one blank line inserted before the bullet, when the same markdownlint command runs, then it reports zero findings. `unit`

## Context

- Failing CI legs (issue #12559): `oracle-index-check` and `quality-guards` on canary PR #12557 runs 42796450472 / 42796450573.
- The suite derives its population from the real runner (`test-all.sh --enumerate-commands/--print-selection --paths=README.md`); it requires a real worktree and is slow under load — do not read a contention timeout as a pass (learning `2026-11-09-…-timed-out-on-contention`).
- This branch has no `spec.md`; `lane:` was defaulted fail-closed to `cross-domain`.

## References

- Issue: #12559 — "fix(ci): canary #12557 exposes two main-line regressions from #12521"
- Canary: PR #12557 (`canary-s4-retire-mq`, auto-merge armed)
- Regressing squash: `b258336e` (PR #12521, S4 retirement)
- Suite contract: `scripts/test-affected-kb-consumers.test.sh` header §BASELINE / §READ FORMS
- Baseline: `scripts/test-affected-kb-consumers.baseline.txt:160-164` (the `scripts/ci-oracle-lane` precedent rows)

## Plan Review

Not fanned out: this planning run executed inside a pipeline subagent with no Task/spawn capability, so the reviewer panel could not be dispatched. The change is a diagnosed two-file, ~6-line mechanical fix; deepen-plan runs next in the pipeline and `soleur:review` seats will cover the PR. Mechanical findings were self-applied where caught (argv-code row shape reconciliation above).
