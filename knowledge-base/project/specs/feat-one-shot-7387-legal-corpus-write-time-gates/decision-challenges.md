# Decision Challenges — feat-one-shot-7387-legal-corpus-write-time-gates

Recorded during plan-review (headless pipeline arm). These are **User-Challenges** per
[decision-principles.md](../../../../plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md)
(ADR-084): the operator's stated direction is the default and was kept pending a decision.

> **Both were put to the operator on 2026-08-10 and are now DECIDED and APPLIED.** They are reported
> in the PR body as applied decisions, not filed as `action-required`. See the resolution block under
> each challenge.

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

**RESOLVED 2026-08-10 — split to a follow-up. Filed as #7392.**

The operator took the reviewers' recommendation. This PR ships gates 1 and 2 only. #7392 carries the
full gate-3 design (sourced-shell-DSL input, the three verbs, pre-edit-must-fail validation, the
`anchor_covers` measured identity, the necessary-not-sufficient PASS message, the row-21 mutation
case) plus the five R24 wiring requirements as acceptance criteria, and will be built against #7349
so it lands with a live consumer and a calibration corpus.

Applied: plan `## Scope decisions` D-A; Phase 4 and the gate-3 input-format section marked deferred;
AC15–AC20 moved to #7392; the `obligation-checklist` rows removed from *Files to Create* and from the
registration count (five `run_suite` lines, not six); Non-Goals states the deferral plainly.

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

**RESOLVED 2026-08-10 — approved and applied.**

#7349 raised `priority/p2-medium` → **`priority/p1-high`**, with a **2026-09-30** remediation target
and the CLO's specific measured omissions recorded on the issue (not "220 lines of drift", which
conveys none of them). Gate 2's script header must cite that date — task 3.10 — so the freeze it
institutionalises is visibly temporary. If the date moves, the header moves with it; the two are
deliberately coupled. A matching active item goes into `knowledge-base/legal/compliance-posture.md`.
