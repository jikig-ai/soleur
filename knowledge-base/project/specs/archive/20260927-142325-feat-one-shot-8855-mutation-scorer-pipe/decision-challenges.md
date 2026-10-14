---
feature: feat-one-shot-8855-mutation-scorer-pipe
issue: 8855
plan: knowledge-base/project/plans/2026-09-27-fix-mutation-battery-shared-scorer-plan.md
---

# Decision challenges — feat-one-shot-8855-mutation-scorer-pipe

These choices were made during headless planning. They either go beyond the brief or leave a
reviewer's suggestion unapplied. Nothing needs doing unless you disagree.

## DC-1 — One more test battery is fixed than the brief named (scope added)

**Class:** User-Challenge (adds scope).

**Brief:** fix six sites in four named batteries.

**Planned:** fix those six, plus a seventh site in
`apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (`attributed()`).

**Why:**

- Issue #8855's own follow-up comment lists this site.
- It is the only web-platform mutation battery that still has the random-failure bug this issue is about.
  Two more piped `grep -q` row scorers sit outside web-platform (`plugins/soleur/test/hook-input-classification-mutation.test.sh`
  and `scripts/battery-tag-authorship-mutations.test.sh`); those are #7005's scope.
- The six named sites lost that bug when #8763 merged.
- Closing #8855 without it would leave the issue's recorded scope half done.

**To reverse:** drop the betterstack row from the conversion list and from `FILES_8855`, and set the
member count to 5. The site then needs its own issue.

## DC-2 — No pointer telling future battery authors to use the shared scorer (CTO suggestion not applied)

**Class:** Taste.

**Suggestion (CTO plan-review seat):** add one line to the plan skill's Guard Contract reference
saying that row verdicts in web-platform batteries should call `mutation_scorer_failed_on`.

**Why not here:**

- That would edit a plugin skill reference file, which is outside this fix.
- The library's header already states its scope and consumer rule.
- A new battery copied from any of the six converted ones inherits the call.

**To apply:** a one-line edit to `plugins/soleur/skills/plan/references/`, in a separate PR.

## DC-3 — The premise was partly stale when this plan was written (disclosure, no decision needed)

**Class:** Mechanical (a record, not a decision).

**What the issue assumed:** the four named batteries still flake.

**What was true:** #8763 had already replaced `| grep -qF` with `| grep -cF` at the six named sites,
two days before this plan. That removed the random failures there.

**What this PR adds at those sites:**

- An unreadable log stops the run instead of producing a verdict.
- An empty expectation stops the run instead of counting as a pass.
- There is one shared scorer and a guard that can tell the fixed files from a revert.

The PR body states this plainly and does not claim those six sites were flaking.
