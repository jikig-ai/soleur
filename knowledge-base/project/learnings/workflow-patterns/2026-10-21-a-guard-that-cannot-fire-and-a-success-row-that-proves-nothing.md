---
title: "A guard that cannot fire and a success row that proves nothing are the same defect — spec-row vacuity"
date: 2026-10-21
category: workflow-patterns
issue: 10403
pr: 10738
synced_to: [plan-sharp-edges]
tags: [spec-authoring, vacuous-guard, review-findings, flake-quarantine, test-fix-loop, sentinel-dedup]
---

# Learning: a guard that cannot fire and a success row that proves nothing are the same defect

## Problem

PR #10738 (#10403) added a flake-quarantine screen to `plugins/soleur/skills/test-fix-loop/SKILL.md` — one isolated
re-run per newly-failed test; pass-on-retry on unchanged code = flake → quarantine, file, report. The authored spec
carried a family of defects that a 7-seat review (plus a 7-seat fix round, run sequentially in-process — no Task
surface) had to find, all reducible to one question never asked at authoring time:

- **A guard whose trigger could never be true.** The "possible diff-interaction" flag was keyed on "flaked-test
  path ∩ the loop's own commits" — an intersection that is empty *by construction*, because the loop never edits
  test files. A flag that cannot fire is decoration that reads as coverage.
- **A missing row for the empty set.** An all-flake run produced an empty post-screen failure set that matched no
  termination row, falling through to NON_CONVERGENCE/MAX_ITERATIONS and `git reset --hard` over real fixes.
- **The fix introduced the same class it was remediating.** The new "all failures screened out" row fired on ANY
  non-zero `rc` with an empty post-screen set — including an unparseable run that quarantined nothing. A success
  row an empty input satisfies proves nothing.
- **A mechanism invented where the repo's convention already existed.** Dedup was prescribed as `in:title` search —
  which breaks on a test name carrying `"` or search-significant punctuation — while `check-red-on-main.sh` already
  dedupes trackers on an HTML-comment sentinel matched in issue bodies.
- **Verdict terms with no trigger.** "Auto-close after N consecutive greens" mischaracterized the mirrored workflow
  (it closes on ONE green run); "newly-failed" and "WARN on the Repeatable property" named mechanics undefined in
  the host models.

## Solution

Fixed in `4b7f82ba95` and `6e09c90513`; the shipped spec now reads:

- Diff-interaction is flagged on the two signals that CAN fire: the flake was first observed in an iteration after
  the loop's first fix commit, or the flaked test exercises files this branch's diff touched. The spec names why a
  path intersection can never fire.
- "All failures screened out" requires `rc` non-zero **and ≥1 test quarantined this run**; a zero-failure parse
  with non-zero `rc` falls through to the rows below — nothing screened is nothing proven.
- Dedup lists open `flaky`-labeled issues (`gh issue list --state open --label flaky --json number,body`) and
  matches `<!-- soleur:flake test="<file>::<name>" -->` in bodies, commenting on the existing tracker rather than
  filing a duplicate.
- The checklist states the mirror's real contract: auto-close on the NEXT green run of the same suite, mirroring
  `scheduled-integration-suites.yml`'s auto-close-stale arm.
- The `qa` SKILL.md pointer landed inside the byte ceiling by trimming a redundant clause in the same bullet —
  near-zero-byte edit, 36,989/37,000 B (11 B headroom), per the `lint-skill-body-budget.py` regime.

## Key Insight

For every conditional row a spec adds — a guard, a flag, a termination-table row, a success verdict — two vacuity
checks, both cheap, both skipped here:

1. **Fireability** — can the trigger be true under the mechanism's own invariants? An intersection with a set that
   is empty by construction (a path set the actor never writes) never fires. Re-specify on signals that can:
   timing relative to the actor's own commits, and whether the flagged surface exercises the diff.
2. **Proof burden** — does a success/screened-out row require ≥1 qualifying item? A row satisfied by an empty input
   set greens on nothing; the zero-parse case must fall through, not succeed.

And two corollaries: the checks apply to rows added under review-fix pressure too (the second vacuity was written
while fixing the first batch), and when the repo already ships a mechanism convention (sentinel-in-body dedup in
`check-red-on-main.sh`), mirror it — an invented `in:title` search is weaker on exactly the inputs it exists for
(test names with quotes/punctuation).

## Session Errors

1. **Spec prescribed a diff-interaction guard with an unreachable trigger** (path ∩ commits where the loop never
   edits test files). Recovery: re-specified on timing + exercised-surface signals (`4b7f82ba95`).
   **Prevention:** fireability check on every new conditional row — name one input under the mechanism's own
   invariants that makes the trigger true.
2. **Empty post-screen failure set matched no termination row** → all-flake run would report NON_CONVERGENCE and
   reset real fixes. Recovery: added the screened-out termination row (`4b7f82ba95`). **Prevention:** for every
   filtered set a spec introduces, enumerate the empty-set case explicitly.
3. **Fix-round's screened-out row fired vacuously on an unparseable `rc≠0` run (0 quarantines)** — a success row
   requiring no proof. Recovery: added the `≥1 quarantined this run` conjunct and the zero-parse fall-through
   (`6e09c90513`). **Prevention:** a success row must require a positive count of qualifying items; re-run the
   vacuity checks on rows added in fix rounds.
4. **Dedup prescribed `in:title` where the repo's sentinel convention already existed** — fragile on `"` and search
   punctuation, silently missing the tracker it exists to find. Recovery: adopted `<!-- soleur:flake test=... -->`
   body matching (`4b7f82ba95`). **Prevention:** grep for the sibling mechanism's convention before prescribing a
   new dedup/search key.
5. **Verdict terms without triggers**: "auto-close after N consecutive greens" (mirror closes on one green),
   "newly-failed" undefined, "WARN on the Repeatable property" with no verdict mechanic in the numeric score model.
   Recovery: corrected each (`4b7f82ba95`). **Prevention:** describe the mirrored mechanism's actual contract; every
   verdict term a spec adds must name its trigger in the host's model.
6. **`qa` SKILL.md at 11 B headroom** — friction, not an error: only a net-zero edit could land the checklist
   pointer. Recovery: trimmed a redundant clause in the same bullet; plan had already recorded `36,940/37,000 B` and
   prescribed ≤60 B net growth per the byte-ceiling sharp edge (#8647). **Prevention:** already covered —
   `plan-sharp-edges.md` requires recording `ceiling - wc -c` in the plan; `lint-skill-body-budget.py` enforces it.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/test-fix-loop, plugins/soleur/skills/qa, plugins/soleur/agents/engineering/review/test-design-reviewer
