# Decision Challenges — feat-one-shot-7570-7534-7544-7481-7460-rung2-harness

Persisted headless by `plan-review` (ADR-084 routing). `ship` Phase 6 renders these into the PR
body and files an `action-required` issue. These are **not** applied — they change the operator's
stated direction and need the operator's call.

---

## UC-1 — Three reviewers recommend splitting the PR; the brief asked for one

**Class:** User-Challenge (dropping/splitting operator-requested scope is never Mechanical).

**The operator's stated direction.** The brief's deliverable is *"one merged PR closing as many of
the five as land cleanly, with anything left out named and justified."* That is the default and it
stands unless the operator changes it.

**What the panel said.** `dhh-rails-reviewer`, `soleur:engineering:cto` and
`code-simplicity-reviewer` independently recommended splitting; `cpo` reviewed the same question
and concluded the sequencing is correct and the batch is justified. So the panel is 3–1, not
unanimous.

**The argument that actually lands, and it defeats the plan's own R1.** R1 justified keeping #7460
in-PR by saying that deferring it costs an extra paid dispatch: a rehearsal would attest template A,
#7460 would edit to template B, and a second dispatch would be needed to re-attest. Both DHH and the
CTO pointed out that this cost is incurred only if a dispatch happens *between* the two merges —
and AC 36 commits to **no dispatch in this run**, with the dispatch being a separate operator-chosen
action. The real alternative is *"#7460 ships as its own PR, merged before the next dispatch"*, which
costs **zero** extra dispatches. R1 argued against "defer past a rehearsal", which nobody proposed.
**R1 is wrong as written**, and it has been corrected in the plan.

**The second argument.** The plan's own R3 says #7481 must be built and tested *"against the world
it was specified for (stages 1–5 Sentry-only) before #7460 widens it."* Phase ordering inside one PR
delivers the ordering but not the verification: a reviewer sees the merged end state, where stages
1–5 are no longer Sentry-only, and cannot confirm #7481's arms were ever exercised against the
pre-#7460 world. Bundling destroys the property R3 says is load-bearing.

**What splitting would cost.** A second review cycle, and `cloud-init-git-data.yml` would be touched
in a separate PR — which is still **once**, so constraint 1 is not violated either way.

**Recommended split, if the operator agrees:**

| PR | Closes | Character |
|---|---|---|
| A | #7570, #7544 | same file, both mechanical, small |
| B | #7534 | self-contained in the gate lib + its suite |
| C | #7481 | the substantive review target — half the plan's content |
| D | #7460 | the only Terraform + cloud-init + ADR + security-decision PR |

**Not decided here.** The plan currently keeps all five, restructured into ordered commits with the
issue number in each subject, which is the closest thing to the operator's stated direction that
still answers the reviewability objection. If the operator prefers the four-PR split, the plan's
phases map onto it one-to-one with no rework.

---

## UC-2 — #7544's freshness probe was cut; the refresh mechanism is now a different one

**Class:** Taste (a mechanism substitution the reviewers converged on, not a scope drop).

#7544's issue body asks the plan to *"decide the refresh mechanism"* and points at Dependabot. The
plan originally proposed a follow-through probe. Three reviewers independently found that the
follow-through substrate **closes an issue on exit 0** (`followthrough-convention.md`: *"Exit 0 =
PASS (close-criteria met → sweeper closes the issue)"`), so a probe that exits 0 to mean "still
fine" would close #7544 on the first sweep and stop running within the 14-day
`CLOSED_LOOKBACK_DAYS` window. The mechanism would have been inert.

`code-simplicity-reviewer` then found that `.github/workflows/rule-audit.yml` already carries a
`Detect zot pin staleness` step — cron-driven, polls upstream, files one idempotent
`action-required` issue on drift. The plan now adds an `ubuntu:24.04` case to that existing step
instead of creating two new files.

**Surfaced rather than applied silently** because it substitutes a mechanism the issue named. The
property (*someone is told when the base image moves*) is unchanged and is now durable rather than
14-day-bounded.

---

## UC-3 — #7460's headline claim is off by one stage, and the issue title carries the error

**Class:** Taste (a factual correction to an operator-visible issue title).

#7460 is titled *"bake the Better Stack ingest token so one reader covers all nine boot stages"*.
Measured this session: the `bootcmd` beacon is an **inline bare `curl` to Sentry**, emitted at
`cloud-init-git-data.yml` line 22, before `write_files` at line 47 — so the shared `git-data-emit`
script does not exist yet when it fires, and `stage:bootcmd_start` **cannot** reach Better Stack
regardless of a baked token. Coverage widens to **eight** stages, not nine.

The plan has been corrected throughout. The issue title and ADR-198's text should be corrected too,
which is why this is surfaced rather than applied silently — it edits an issue the operator filed.

### UC-1 RESOLUTION — operator decision, 2026-09-02

**Chosen: split #7460 out only.** PR A (this branch) = Phases 0-4, closes #7570, #7534, #7544,
#7481. PR B (follow-on) = Phase 5, closes #7460.

Not the panel's four-way split, and not the status quo. The operator was shown that the "one PR"
framing originated in the one-shot invocation args written by the assistant, NOT in their own
instruction ("fix the harness defects first"), so no stated operator direction was being overridden
— there was none to override on PR shape.

**Why the minimal split answers both objections.** Both reviewer arguments are about #7460
specifically:

- DHH + CTO refuted R1: deferring #7460 costs an extra paid dispatch only if a dispatch happens
  between the two merges, and AC 36 commits to no dispatch in this run. Splitting costs zero extra
  dispatches.
- R3 requires #7481 to be built and tested against the world it was specified for (stages 1-5
  Sentry-only) before #7460 widens it. Ordered commits inside one PR deliver the ordering but not
  the verifiability: a reviewer sees only the merged end state. With #7460 in its own PR, PR A's
  diff IS the pre-#7460 world, so the property R3 calls load-bearing is directly checkable.

Splitting #7534 and #7544 out as well (the panel's PRs A/B) would have bought reviewability the
operator did not ask for at the price of two further review cycles, which they pay for.

**Cost accepted:** one extra review cycle. **Constraint 1 preserved:** `cloud-init-git-data.yml`
is touched exactly once, in PR B.
