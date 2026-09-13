# Decision Challenges — feat-one-shot-8043-git-data-hash-bound-hardening

Recorded headless by `plan-review` (ADR-084 routing). Each entry is a finding that argues the
**operator's stated scope or direction** should change. None is auto-applied. `ship` Phase 6 renders
this file into the PR body and files it as an `action-required` issue.

---

## UC-1 — Drop `scripts/betterstack-query.sh` (FR13 + Guard 5) from this PR

**Class:** `user-challenge` — a simplify-cut of **operator-requested scope**, which
`decision-principles.md` lists as never-Mechanical.

**Raised by:** dhh-rails-reviewer, plan review 2026-09-10.

**What the operator asked for.** The task brief named two "traps measured today, worth encoding
durably while you are here", the first being that `betterstack-query.sh` silently ignores `--table`
in raw-SQL mode, and said: *"Consider making the flag work or fail loudly."*

**The challenge.** The reviewer's argument, verbatim in substance: the script has **zero hash
coupling**, it is **not one of the six defects**, its whole justification is that the planner nearly
reached a wrong conclusion while investigating, and it already has its own suite at
`tests/scripts/test-betterstack-query-archive.sh`. Attaching a ten-line CLI-flag fix to a
CPO-signed, brand-survival-threshold `single-user incident` PR that gates the birth of the host
holding every user's source code spends reviewer attention on the cheapest item in the batch, right
before a paid rehearsal.

**The case for keeping it.** The trap directly caused a measurement error on this very issue — it
produces a plausible **empty** result against a git-data host and the conclusion "the boot was
dark". It is cheap, and the operator asked for it in the same breath as the batch.

**Default if nobody decides:** the operator's stated direction stands — it stays in this PR. The
plan is written that way.

**If accepted:** remove FR13 and Guard 5 from the plan (the plan numbers them FR13/Guard 5 — this
file's first draft said FR12/Guard 4, which are the evidence-deletion items and must NOT be
removed; corrected at deepen-plan), drop `scripts/betterstack-query.sh`,
`tests/scripts/test-betterstack-query-archive.sh` and
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` from `## Files to Edit`,
and file the fix as its own issue. **One thing in the plan now depends on it:** the Observability
`discoverability_test` is `bash tests/scripts/test-betterstack-query-archive.sh` expecting the
FR13 row label (deepen-plan, Kieran P1-3). If UC-1 is accepted, that probe must be re-pointed in the
same decision — the suite would still pass, but its `expected_output` row would not exist and Check
10 would FAIL at ship.
