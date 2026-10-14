# Decision challenges — feat-one-shot-7331-alpha-tester-terms-dpa

Recorded per ADR-084. These are **User-Challenge** class: they argue the operator's stated direction
(as written in issue #7331) should change. They are not auto-applied. `ship` Phase 6 renders this
file into the PR body and files it as an `action-required` issue.

**Both challenges were answered by the operator on 2026-08-06.** The original challenge text below
is preserved verbatim; each carries a `Resolution` block recording what was chosen. UC-1 was
answered directly. UC-2's premise changed underneath it — a second operator answer (Task 0.1) made
the instrument it was arguing about non-conditional — so it is re-assessed rather than simply
closed.

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

### Resolution — 2026-08-06: **Option 2 (retain and paper).** RESOLVED.

The operator retains collaborator access to the tester's private repository and papers it. Posture C
is therefore **live and ongoing**, not hypothetical.

**Consequences now in force.** Plan Phase 2 **executes** — the Art. 6(1)(f) LIA, **PA-35** as the
**controller** record for this ongoing collaborator-access observation in the Art. 30(1) register
(PA-34 is the separate, session-bound dogfooding limb), the amendment to that register's in-scope
surface list, and the Art. 14 notice line. The Option 1 arm of AC5 no longer has a live branch. The
*"skipped under Option 1"* framing survives only where it is quoting the original challenge or the
pre-resolution plan state — every prescriptive use of it is gone. The runbook
operating rule can no longer say *"do not accept collaborator access on a tester's repository"* as
the house rule, because the house is not following it — it states the standing rule and records the
tester #1 exception with its papering.

**What the challenge got right and keeps.** The measurability arithmetic is unchanged: the access
still buys **one metric of three**, and a tester-supplied `git log --stat` would still substitute.
Option 2 was chosen on measurement fidelity, not because Option 1 was unavailable. That means the
revocation option stays live as the cheapest de-escalation if the papering proves burdensome, and
the LIA's Art. 6(1)(f) necessity limb must confront it honestly — a less intrusive means exists and
was declined, which is a balancing fact the LIA has to carry rather than omit.

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

### Resolution — 2026-08-06: **re-derived, and it survives.** RESOLVED.

**Its stated premise died.** UC-2 argued that #7119 outranks *"a **conditional** instrument for an
unpaid tester who has not asked for one."* The Task 0.1 answer removed the word that was doing the
work: **the instrument is not conditional.** Posture B fired on 2026-08-06, the processing happened,
and an Art. 28(3) instrument is now a real deliverable. A challenge whose premise is falsified is
normally closed — this one is re-derived instead, because the conclusion turns out not to depend on
the dead premise.

**It still holds, on different reasoning.** The comparison was never conditional-vs-actual; it was
always **magnitude**. #7119 involves ~80 digests **already published to a public repository**
carrying commenter handles and stargazer names, never deleted, **still running**, with an expired
Art. 14 clock (#7120) and a ~5-month-overdue DPIA (#7121) attached. The alpha instrument concerns
**one identified counterparty**, who **requested** the processing, whose exposure is **bounded**
(a single session) and **closed forward** by a free behavioural control, and whose Anthropic-side
copy lapses ~2026-09-05. The alpha exposure moved from *hypothetical* to *small and closed*.
**#7119 wins on scale, publicity and continuance. It is not close.**

**Recommendation: no counsel spend on the alpha instrument now.** Not because it is hypothetical —
it is not — but because the behavioural control (plan Phase 4.2b / AC14: *no Jikigai-keyed runs
against tester content until the instrument is countersigned*) closes the exposure at **$0**. That
defers the **spend**, not the **drafting**: the marked internal draft ships at $0 and is adequate for
one unpaid friendly tester. **Counsel is bought at exactly one moment — before the instrument is
sent** (AC13).

**Two pricing corrections that came out of the re-derivation.** The plan quoted *"EUR 300–800"*;
`recommended-tools.md` §`vendor-msa-review` says **"$300-800"** — **USD**, against a French SARL, so
budget in EUR with FX and reverse-charge VAT. More substantively: **neither listed SKU is the right
product.** §`vendor-msa-review` and §`ai-vendor-terms` (~$200-400) are **contract-scan** offerings; a
lawful-basis / Art. 14 / DPIA question is **data-protection advice**. Before budgeting, establish
whether the marketplace offers a data-protection-advice SKU and whether the panel is GDPR-qualified.
Treat $300-800 as a floor for the wrong product, not a quote.

**The free move, recorded here because it outranks both.** Re-derive the #1442 metric to non-personal
aggregates (commit/file/directory counts) instead of reading repository content. It costs nothing,
keeps the metric, and takes PA-35 out of Art. 4(1) scope almost entirely. Deferred at plan
Phase 6.3 — the operator elected Option 2 under UC-1 and this plan executes that election.
