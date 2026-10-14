# Decision challenges — feat-one-shot-7424-killed-vs-failed-suite-reporting

Recorded by `plan-review` (headless arm). These are findings that argue the **operator's stated
scope** should change. Per ADR-084 routing they are never auto-applied — the operator's direction
is the default. `ship` Phase 6 renders this file into the PR body and files it as an
`action-required` issue.

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
soleur:engineering:cto (devex lens), plus the Step-4.5 strong-model advisor consult.

---

## UC-1 — Two reviewers recommend cutting remediation item 3 (declared time budgets) entirely

**decisionClass:** `user-challenge` (a simplify-cut of operator-requested scope)

**Operator's stated direction (the default, kept in the plan):** issue #7424 lists three
remediations, and item 3 is *"Give the long batteries an explicit, named time budget."* The plan
implements it as an advisory `[budget]` line driven by a `case` lookup.

**What the panel found:**
- **dhh-rails-reviewer (P0-3):** the budget mechanism is a solution without a measured problem —
  nothing consumes the `[budget]` line, it changes no outcome, and it adds a hand-maintained table
  that must be re-measured whenever a suite's cost changes.
- **code-simplicity-reviewer (cut #3):** it is a second mechanism doing a job the `[KILLED]` marker
  and the elapsed-ms already do; the elapsed time is *already printed on every line*.
- **kieran-rails-reviewer (P1-7):** as specified the AC is **vacuously satisfiable** — with zero
  budgets declared, "every declared value carries a measurement comment" is trivially true, so
  Phase 5 can ship an empty `case` and pass its own AC while delivering none of item 3.
  Compounding it: the prescribed measurement is *"run the 9-minute battery standalone"* — the very
  suite the incident shows getting killed — with no stated fallback if it is killed again.

**Why it is not Mechanical:** the issue names item 3 explicitly. Dropping it narrows what
`Closes #7424` means.

**Recommendation if the operator agrees:** cut Phase 5 and its AC15, and fold "declared budgets for
long suites" into the Phase-7.2 tracking issue with the trigger *"when a second suite is observed
KILLED, or when a budget consumer exists."* Items 1 and 2 — the two the issue itself ranks highest —
are unaffected.

**Disposition taken in the plan:** item 3 is **kept**, with Kieran's vacuity hole closed (AC15 now
requires at least one non-empty declared budget, and T14 drives the emitter through a fixture with a
0 ms budget so the line is proven regardless of what got measured). If measurement is not obtainable
in-session, the plan defers Phase 5 to the tracking issue rather than shipping an empty lookup.

---

## UC-2 — DHH recommends splitting the sibling-probe work (remediation item 2) into its own PR

**decisionClass:** `user-challenge` (changes the delivery shape of operator-requested scope)

**Operator's stated direction (the default, kept in the plan):** the task names both the
terminated-vs-failed reporting gap **and** the sibling-probe scope gap, and `Closes #7424` covers
both.

**What the panel found (dhh-rails-reviewer P1-1):** the two halves share only the issue number.
Phase 4 touches a different file, has a different failure mode, and carries the review burden of a
`/proc`-scanning predicate — while Phases 1-3 are the change that retires the actual misreading.
Bundling them means the high-value half waits on the risky half.

**Why it is not Mechanical:** splitting would leave #7424 partially closed and require a second
issue/PR the operator did not ask for.

**Recommendation if the operator agrees:** ship Phases 1-3 + 6 as this PR (`Closes #7424` narrowed,
or the issue re-scoped), and Phase 4 as an immediate follow-up.

**Disposition taken in the plan:** **kept together.** The two halves co-occurred in the incident —
the run that misreported `[FAIL]` is the same run whose preamble reported `siblings: 0` while a
sibling was running that exact suite — and the plan's own §Risks R2 is the mitigation for the
probe's one real hazard. Splitting is recorded here for the operator rather than taken.

---

## Non-challenges (applied directly — recorded for traceability)

These were **Mechanical** correctness findings and were auto-applied to the plan; they are listed
so the operator can see what moved without re-reading the diff:

- **kieran P0-1** — `kill -l` is neither a decode nor a bounds check as the plan claimed. Measured:
  `kill -l 0` → `EXIT` (rc 0), `kill -l 32`/`33` → **empty name** (rc 0), `kill -l 143` → `TERM`
  (masks >64). Classifier now requires a **non-empty** decoded name; table gained rows 160/161/192.
- **kieran P0-2** — the classification `case` had no `ok)` or `*)` arm, so an unrecognized class
  counted the suite as **passed**. Now fails loud and counts as FAILED.
- **dhh P0-1** — the sandbox suite copies **one file**, so a sourced `scripts/lib/suite-exit-class.sh`
  would be absent under test and the degradation stub would silently defeat the assertions. The
  classifier is now **inlined** into `scripts/test-all.sh`; the separate lib and its unit suite are
  deleted.
- **kieran P1-2 / advisor Change 1** — the cwd set-difference was the wrong primitive (suites `cd`
  into `mktemp` sandboxes; `<unreadable>` collapses; `env`/`timeout` wrappers hide a run). Replaced
  with ancestry/pgid cancellation over a **single** `/proc` walk.
- **kieran P1-3 / cto F13** — `[KILLED]` lines never reached the health-monitor issue body.
- **cto F1** — `test-fix-loop` terminates on "zero failures", so a killed-only run would have made
  it stage fixes and **report success**: an agent-level false green the plan wrongly called
  unreachable.
- **kieran P1-6** — `killed=0` initialization and the `exit 3` arm were never actually written.
- **kieran P1-5** — the "six banned constructions" list was an incomplete paraphrase of the live
  regex; the plan now instructs reading the regex instead of restating it.
