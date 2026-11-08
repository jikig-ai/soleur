---
date: 2026-11-08
session: feat-one-shot-10862-norun-investigation
category: workflow-issues
tags: [mutation-testing, review-fix-round, fixture-authoring, equivalent-mutants, resume]
pr: 12377
issue: 10862
---

# Learning: a mutate row is only real if the mutant is killable by construction

## Problem

During `soleur:review` on PR #12377 (the `ci_runs` check-runs corroboration fix for #10862), the
post-panel fix commit added four new `mutate` rows plus assertions. The ADR-267 fix round then
reproduced, by actually running the battery, that **all of the new pins failed in three distinct
ways — the fixes themselves were broken**:

- `corroboration-sha-filter-dropped` and `corroboration-event-filter-dropped` **survived**: the
  mutants dropped conjuncts inside `corroborating_runs`'s run filter, but `ci_runs`'s final
  `return [r for r in runs if event in FULL_EVENTS and head_sha == sha]` re-applied both
  conjuncts on the way out. The inner conjuncts were *equivalent mutants* — the redundant
  downstream filter masked the change.
- `corroboration-namespace-ignored` **crashed**: the replacement removed the regex's only `%s`
  while leaving ` % re.escape(repo)` on the line → `TypeError: not all arguments converted`.
  A crash is not a kill.
- `row_corr_trunc` was **red on the pristine SUT**: it bound `checkruns`/`rundetail` fixtures
  while `REPO_NAME=""`, so `*_path` helpers keyed them under the default repo `jikig-ai/soleur`,
  but `corr_run` collects `--repo jikig-ai/fourth` — the fixtures never existed for the collect,
  the unit took the empty-checkruns path, and `reason` stayed `no-run` instead of `runs-read:`.
- One plain-logic assertion (`reqs(9004) -eq 0`) asserted something impossible: a check-run only
  carries `details_url`; the `event` field lives on the run-detail object, so the read MUST be
  fetched to be filtered. "Filtered out" was confused with "never read".

## Solution

Three construction rules, each verified by re-running the battery after the fix:

1. **A mutant's replacement text must leave executable code.** Dropping a format arg out of a
   `"...%s..." % x` expression is a guaranteed `TypeError`. Keep the arity (or rewrite the whole
   expression): the namespace mutant was respelled to swap the whole regex literal INCLUDING the
   `% re.escape(repo)` tail for a literal with no format arg.
2. **No downstream filter may re-apply the conjunct the mutant drops.** `ci_runs`'s final filter
   was scoped to listing vias only (`via in ("head-sha","head-sha-retry")`), making
   `corroborating_runs`'s triple filter the sole guard on its path — the per-conjunct mutants now
   change the outcome and are killed.
3. **Fixture keys are computed from ambient env at bind time, not collect time.** `fx`/`fx_once`
   bodies key on `REPO_NAME`; any row that re-binds a fixture around a `corr_run` must set
   `REPO_NAME` itself (the helper clears it), including the restore.
4. **Know which side of the read a filter lives on.** URL-shape filters (repo namespace regex)
   run pre-fetch — `reqs(...)` stays 0. Field filters (event, sha, path) run post-read — the
   fetch happens, `reqs(...)` is 1, and the assertion is "fetched then rejected", not "never
   fetched".

## Key Insight

A mutation battery verifies the mutants its author *remembered to write*; it says nothing about
whether those mutants are killable by construction. The fix round exists precisely because the
author is the one who can't see it — equivalent-mutant masking and unkillable replacement text
are invisible from inside the diff. The cheap pre-check before declaring a new mutate row done:
apply the edit by hand, run the row, confirm it is green on pristine and red under the mutant —
which is exactly what the fix-round seats did and the suite could not have told you.

## Session Errors

1. **Assertion asserted an impossibility** (`reqs(9004) -eq 0`): run `event` lives on the
   run-detail object, so a matching in-repo `details_url` is fetched then filtered.
   **Prevention:** classify every new filter as pre-fetch or post-read before writing the
   request-count assertion; count the read the filter cannot avoid.
2. **Fixtures bound under the wrong repo key** (`row_corr_trunc` pristine-red):
   `REPO_NAME` was cleared before the `fx` calls while `corr_run` ran `--repo $R4`.
   **Prevention:** set the ambient key var inside the row for both bind and restore; verify the
   row green-on-pristine before shipping it.
3. **Equivalent mutants** (sha/event conjuncts): a downstream filter re-applied the same
   conjuncts. **Prevention:** for each new conjunct, ask "what else filters this field before the
   observable?" — if anything does, the pin needs the downstream check removed or a different
   observable (e.g. `runs_via`, request counts).
4. **Unkillable mutant text** (namespace): dropped `%s` keeping `% arg`. **Prevention:** after a
   mutant's replacement, the expression must still be valid — check %-format arity specifically.
5. **Stale writer on resume**: an orphaned `ejections` process from the interrupted session was
   still appending to the shared out dir, producing byte-identical duplicate unit lines that
   `aggregate` refused. **Prevention:** before resuming a shared-dir collect, `ps` for prior
   writers on the same `--out` and kill them.
6. **Direction-of-error claim backwards** in runbook/cause docs ("kept failures only grow the
   numerator" — the undetectable direction is a dropped lone failure under a kept success reading
   clean, i.e. under-counting). **Prevention:** trace the arithmetic for the worst direction
   before writing "conservative"; the verb belongs to the bound, not the intuition.
7. **Accept row unattributed at commit granularity**: the tip commit added an `accept.tsv` row
   for a literal introduced three commits earlier; `ratchet` (base `HEAD^1`) flagged it
   accept-unattributed. Folded the row into the literal's own commit.
   **Prevention:** land an accept row in the commit that adds the covered literal, not a later one.
8. One-offs: `gh issue view --comments --json` usage error; a fix-round seat died on rate limit
   (recorded as a missing seat, not coverage).

## Proposed workflow rule (Error-to-Workflow Feedback)

> **cq-mutant-killable-by-construction** — Before declaring a new `mutate` row done, verify the
> mutant is killable by construction: (a) the replacement leaves the expression executable
> (watch %-format arity, dropped names); (b) no downstream filter re-applies the conjunct or
> shape being dropped; (c) any fixture the discriminating row binds is keyed under the same env
> the collect will run (ambient vars like `REPO_NAME` are read at bind time). Suggested home:
> the `mutate` authoring comment block in `plugins/soleur/test/ci-pr-affected-replay.test.sh` or
> the suite's convention docs — enforcement tier: advisory (a lint for these is disproportionate;
> the fix round is the enforcer).

## Tags

mutation-testing, equivalent-mutants, fixture-authoring, env-scoped-fixture-keys, review-fix-round,
resume-hygiene, direction-of-error-claims
