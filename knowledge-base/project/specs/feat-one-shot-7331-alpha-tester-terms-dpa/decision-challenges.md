# Decision challenges — feat-one-shot-7331-alpha-tester-terms-dpa

Recorded per ADR-084. These are **User-Challenge** class: they argue the operator's stated direction
(as written in issue #7331) should change. They are not auto-applied. `ship` Phase 6 renders this
file into the PR body and files it as an `action-required` issue.

---

## UC-1 — The cheapest control here is behavioural, not documentary

**Raised by:** plan review (DHH panel), corroborated by the CLO determination and the code-simplicity
panel.

**The operator's stated direction (#7331):** determine the processor posture for tester-owned
repository data and, if Jikigai is a processor, draft and execute a DPA.

**The challenge:** research established that Jikigai is **neither** controller nor processor for repo
data on the CLI surface — that position is already published at
`docs/legal/data-protection-disclosure.md:61` and was verified empirically against `plugins/soleur/`.
The only live exposure found is different in kind: the operator **already holds GitHub collaborator
access to the tester's private repository** and reads its `knowledge-base/` tree for Jikigai's own
#1442 metrics. That is a **controller** activity (Art. 4(7), Art. 28(10)) with no lawful basis
recorded — and a DPA cannot cure it.

The runbook's own measurability table shows that access buys **one metric of three** (knowledge-base
growth), on a surface where returns and non-engineering agent usage are unmeasurable regardless. A
tester-supplied `git log --stat` substitutes for it.

**Option 1 — decline or revoke the access (recommended).** Posture C dissolves. No LIA, no Art. 14
notice, no PA-34, no counsel spend, and the published determination holds unchanged with no crossing
trigger in force.

**Option 2 — retain and paper it.** Keep the access for measurement fidelity; ship the LIA + PA-34 +
Art. 14 line (plan Phase 2).

**Why it is not auto-applied:** it changes what the operator does, not merely what the repo records,
and the measurement value of collaborator access is the operator's call. The plan is written so
Phase 2 is skipped under Option 1 and executed under Option 2; nothing else is affected.

---

## UC-2 — The legal budget may be pointed at the wrong problem

**Raised by:** plan review (DHH panel), from the plan's own budget warning.

**The challenge:** the plan's escalation guidance contemplates EUR 300–800 of counsel time for a
bilateral instrument covering an unpaid alpha tester who has not asked for one. Meanwhile
`compliance-posture.md` records, against the same accountability pack any counsel would receive:

- **#7119** — the PA-32 republication limb has **no available lawful basis** as implemented, marked
  **BLOCKING**, with 80 digests published to a public repo carrying commenter handles and stargazer
  names, and no deletions ever.
- **#7120** — the Art. 14 notice clock to that population **expired ~2026-03-19**.
- **#7121** — a full DPIA for PA-32 is **~5 months overdue**.

If there is one legal budget, #7119 concerns identifiable people whose data is being republished
today, without a basis, in public. The alpha instrument concerns a relationship the determination
finds does not yet exist.

**This is not a reason to stop #7331** — the determination, PA-34 and the Tier 1 notice are cheap and
ship without counsel. It is a challenge to the *sequencing of paid legal time*, which only the
operator can decide.
