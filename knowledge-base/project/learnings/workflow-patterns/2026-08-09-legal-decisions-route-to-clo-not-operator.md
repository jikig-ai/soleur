---
title: "Legal decisions route to the CLO agent, not the operator — and a prohibition sweep cannot detect an omission"
date: 2026-08-09
category: workflow-patterns
tags: [routing, clo, legal, verification, review, delegation]
issues: [7347]
pr: 7372
---

# Legal decisions route to the CLO, not the operator

## What happened

PR #7372 (condition **C5** of the alpha-tester controller/processor determination) added scope text to
five published legal documents separating plugin-local from operator-assisted processing. A four-agent
review blocked it on ten P1s. Three of the findings were not edits — they were decisions:

1. a newly-published Art. 6(1)(f) controller limb with no balancing test and no Article 30 entry
2. Art. 14 third-party data subjects (company officers in fixture data, commit authors) addressed
   nowhere in the published corpus
3. the unexecuted annex stating DPF/SCCs/IDTA flatly to a signing counterparty while the public notice
   withheld the transfer mechanism pending condition C6

All three were surfaced to the **operator**, with a note that they needed "your or counsel's call."

The operator's reply: *"why is the CLO not taking ownership for those fixes rather than me or counsel?"*

Correct. The repo already encodes this for engineering — `work/SKILL.md` carries a HARD GATE that
architectural forks route to `soleur:engineering:cto` and never to the operator, on the stated ground
that the operator is non-technical and architecture is the CTO's call. There was **no legal analogue**,
so the legal-domain equivalent defaulted to the operator.

## Why the mistake felt correct

The three decisions were consequential — a lawful basis, a statutory notice route, a contractual
asymmetry. That weight is what triggered the escalation.

**Weight is not a routing signal.** It is the reason to route *to* the domain owner, never past it. The
CTO rule already says this implicitly ("the operator is non-technical, and architecture is the CTO's
call"); nothing said it for legal, and the absence read as "this is too important for an agent."

The second confusion was collapsing two different escalations. *Qualified-counsel review* is a real,
external, costly act — already tracked as #7348, with a threshold catalog at
`knowledge-base/legal/recommended-tools.md`. "This needs counsel" and "this needs a CLO ruling" are not
the same claim, and the first is not a safer default for the second: it converts a decision the CLO can
make today into a spend and a wait.

## The fix

Two HARD GATEs added to `plugins/soleur/skills/work/SKILL.md` Phase 1, as siblings of the CTO rule:

1. **Legal/compliance-substantive decisions route to `soleur:legal:clo`.** Triggers: published-claim
   scope adequacy, lawful basis / balancing test / Art. 30 entry, Art. 13-14 notice adequacy,
   retraction-vs-scoping, notice-vs-instrument asymmetry, whether a determination condition can be
   discharged. Hand the CLO the findings, the governing records, and the binding constraints, and
   require **drafted replacement wording** back — a verdict alone leaves the drafting judgment
   unrouted. Prompt it with "do NOT use AskUserQuestion" (domain leaders default to orchestrator mode
   and would hang a headless run).
2. **Positive verification of binding items.** See below.

## The second defect, which is the more reusable one

The PR's post-implementation verification passed **6 of 6**:

- `terms-and-conditions.md` untouched
- `BODY_EQUIVALENCE_DOCS` unaltered
- pre-existing canonical↔mirror drift neither fixed nor worsened
- disclosure §3.1(b)/(d) neither qualified nor asserted true
- "eleven processing activities" unchanged
- no issue/PR/branch reference in any published legal file

Every one of those is a **prohibition**. Not one was an **obligation**. So the sweep was structurally
incapable of noticing that the implementation had silently dropped:

- amendment **A8** — the disclosure §4.2 preamble's closed section list *"where Jikigai acts as
  Controller (see Sections 2.1b and 2.3)"* needed 2.1c
- amendment **A6** — gdpr-policy §10's *"The register documents eleven processing activities"* was to be
  de-numeralised or deferred; neither happened (and note the prohibition check "eleven unchanged"
  actively **confirmed** the omission as compliance)
- the disclosure §2.3 opener *"Soleur's data processing activities are limited to:"* — the identical
  closed-list fix WAS applied one document over, so the pattern was understood and not carried across

**A negative predicate does not quantify over obligations.** Build the check from the binding list
itself: one grep per item, item id printed next to hit/miss, any miss blocking. This holds with extra
force when implementation was delegated — a delegate's report names what it did, never what it forgot.

The sharpest instance is A6: a prohibition ("do not change the numeral") and an obligation
("de-numeralise or defer") pointed at the same string, and the prohibition sweep reported the untouched
string as a **pass**. Two checks over one token, agreeing, one of them wrong.

## Related

- `plugins/soleur/skills/work/SKILL.md` — the CTO routing gate this mirrors, and both new gates
- `knowledge-base/project/learnings/workflow-patterns/2026-06-15-architectural-fork-decisions-route-to-cto-not-operator.md`
  — the engineering precedent (#5325), same shape, same wrong first instinct
- `knowledge-base/project/specs/feat-one-shot-7347-dpd-operator-assisted-scope/review-findings.md`
  — the ten P1s, including the three that prompted this
- Memory: *never defer operator actions — Soleur users are non-technical; automate everything or fix
  in-session.* The routing default was the same failure in a new domain.
