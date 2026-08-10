# Decision Challenges — feat-one-shot-7387-legal-corpus-write-time-gates

Recorded during plan-review (headless pipeline arm). These are **User-Challenges** per
[decision-principles.md](../../../../plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md)
(ADR-084): the operator's stated direction is the default and has been kept. `ship` renders this
into the PR body and files it as an `action-required` issue.

---

## UC-1 — Defer gate 3 (obligation-checklist) to its own issue

**Operator's stated direction (kept):** #7387 scopes three gates; the pipeline instruction was
"implement and ship the three write-time gates."

**The challenge.** Two independent reviewers (code-simplicity, spec-flow-analyzer) and, on separate
grounds, the architecture reviewer, recommend cutting gate 3 from this PR. The plan itself now
carries the supporting evidence:

1. **It ships with no input.** `Files to Create` contains the runner and its suite; there is no
   checklist instance, no declared home, no producer skill, and no CI trigger. Gate 3 would land on
   `main` enforcing zero rows.
2. **The rule that would trigger authorship isn't on main either.** The `Verify that every BINDING
   item LANDED` HARD GATE exists only on the unmerged 7347 branch (`work/SKILL.md:190`).
3. **Its green is fabricable.** AC23 greps the run log for `obligation-checklist`, which matches the
   **unit-suite label** — so the registration AC passes with zero real rows consumed. That is the
   #3366 shape (an unregistered gate indistinguishable from a passing one), reproduced one level up,
   inside the PR whose stated purpose is eliminating it.
4. **Counterfactual value is 2 of 10 P1s** (P1-6, P1-9), and — per the CLO — gate 3 *detects*
   nothing: it executes a checklist a human wrote. Gates 1 and 2 are corpus-generic and always-on.
5. **The format will be wrong.** Built now against one historical 37-row table, the schema fits that
   table. This already happened once in this plan: the first draft's `survivors` field could not
   encode either real deletion row faithfully.

**The case for keeping it here.** #7349 is queued against the same corpus and would use it; the
issue scopes three gates; and building it now means #7349 inherits a tested runner.

**Rebuttal offered by reviewers.** #7349 will hand-author its own list either way. Building the
runner *with* #7349 gives it a live consumer, a real input, and a calibration corpus — and the
format will very likely turn out to be a shell script, which is where this plan's own revision R18
already landed it.

**Disposition:** kept in scope (operator's direction is the default). If it ships here, revision
R24 lists the five things it must additionally carry — declared home, named producer, glob-driven
CI step, absence-detection predicate, and an AC requiring ≥1 real committed checklist executed —
otherwise the "live" `run_suite` line should be dropped rather than fabricated, and Non-Goals should
say plainly that the runner ships without a consumer.

**Operator decision needed:** ship gate 3 in this PR with the R24 wiring, or split it to a follow-up
issue tracked against #7349.

---

## UC-2 — #7349 priority and date (CLO Amendment 8, stands independently of this PR)

**The challenge.** The CLO's review found the 220-line canonical↔mirror drift is not neutral
formatting: the **published** page under-discloses relative to the record. Measured omissions on the
Eleventy mirror include collected-data categories, a named third-country recipient (**Anthropic,
US**), lawful bases, a retention period, the Art. 15/20 self-serve export route, and an Art. 14
posture for involuntary third-party data subjects.

Gate 2 freezes that divergence deliberately (a zero-assertion is unshippable). But a *knowingly
retained* divergence bears on Art. 83(2)(b) (intentional/negligent character) and 83(2)(c)
(mitigating action). A dated remediation record converts this from ongoing-negligent to managed; a
permanent gate with no date is documentary evidence that it was measured, understood, and
institutionalised.

**#7349 today:** OPEN, `priority/p2-medium`, on the "Phase 4: Validate + Scale" milestone whose
trigger is "readiness, not calendar" and whose `dueOn` (2026-05-01) has already passed.

**CLO recommendation:** raise #7349 to P1 with a dated target; cite that date in the gate-2 script
header so the freeze is visibly temporary; and record the specific measured omissions on #7349 and
in `knowledge-base/legal/compliance-posture.md` as an active item — "220 lines of drift" does not
convey them.

**Disposition:** not applied by this plan (it is a priority/scheduling decision on another issue and
a compliance-posture write, both outside #7387's scope). Recorded here so it is not lost.

**Operator decision needed:** approve the #7349 re-prioritisation + compliance-posture entry.
