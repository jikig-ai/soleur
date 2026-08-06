---
title: "Alpha-tester terms + controller/processor posture for tester-owned repository data"
feature: feat-one-shot-7331-alpha-tester-terms-dpa
issue: "#7331"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: spec
date: 2026-08-06
branch: feat-one-shot-7331-alpha-tester-terms-dpa
plan: knowledge-base/project/plans/2026-08-06-legal-alpha-tester-terms-and-processor-posture-plan.md
predecessor: knowledge-base/project/specs/feat-alpha-onboarding-motion/spec.md
related:
  - knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md
  - knowledge-base/product/roadmap.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Mirrors the ack in the plan. This spec provisions no infrastructure: every requirement writes
markdown under knowledge-base/, edits an operations runbook, or files a GitHub issue. The two
human-performed steps it records — a counterparty deciding whether to countersign, and a law firm
reviewing a contract — are counterparty and professional-services acts, unautomatable by nature
rather than by omission.
-->

# Spec — Alpha-tester terms + controller/processor posture

**Standing constraint:** no third-party personal data in any committed file. The tester is `Skouer` /
`https://github.com/2my8r9ry2t-wq/Skouer` — company name and repository URL only.

## Problem

Issue #7331 asks whether Jikigai is an Art. 28 processor of personal data in an alpha tester's own
repository, and asks for alpha-tester terms. Research established two things the issue does not
contain:

1. **The processor question is already answered, negatively, in published documents.**
   `docs/legal/data-protection-disclosure.md:61` (both mirrors): *"Therefore, Soleur is neither a
   Controller nor a Processor with respect to the data processed locally through the Plugin."*
   Verified empirically — no phone-home path exists in `plugins/soleur/`.
2. **The live exposure is a controller problem, not a processor one.** The operator already holds
   collaborator access to the tester's private repository and reads it for Jikigai's own #1442
   metrics — Art. 4(7) controller activity with no lawful basis recorded. A DPA cannot cure it
   (Art. 28(10)).

## Goals

- Record the determination durably and citably, whichever way it falls.
- Close, or dissolve, the live controller exposure.
- Give every alpha tester something that binds in the Jikigai→tester direction.
- Give testers 2–10 the same treatment automatically, via the runbook.

## Non-Goals

- **Building the `if processor` branch.** The determination proves the antecedent false. No DPA is
  executed, no execution register is created, no Art. 30(2) record is written, no signature probe is
  enrolled.
- **Publishing anything to `docs/legal/`.** Fires the #4330 six-step chain including a SOC 2
  engagement commitment.
- **Amending the T&Cs.** A `TC_VERSION` bump forces every existing user to re-accept.
- **Absorbing the pre-existing defects** found during research — they are filed, not fixed here.
- **Renumbering the runbook.** The agreement folds into the existing Step 2.

## Functional Requirements

**FR1 — Determination.** A record under `knowledge-base/legal/audits/` in the
`2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` format, stating the three postures,
the *whose machine / whose key / whose purpose* test, the four enumerated Posture B triggers, the
Posture C finding, and the Phase 0 empirical evidence. Present whichever way the verdict falls.
It cites ADR-093, ADR-099, ADR-119, ADR-075 and ADR-102, and scopes every non-receipt sentence to
the CLI surface **in the sentence itself**.

**FR2 — Posture C closed or dissolved.** Under Option 2: an LIA, PA-34 in the Art. 30(1) register
with Jikigai as controller, an Art. 14 notice claiming Art. 14(5)(b) in writing, and an amendment to
`article-30-register.md:32`'s in-scope surface list so PA-34 is reachable by a membership predicate.
Under Option 1: the determination records that the access was declined and Posture C does not arise.

**FR3 — Tier 1 alpha notice, unconditional.** Sent to every tester **including tester #1**. ≤90 words,
first-person, merged into the existing welcome-message paragraph, leading with what Soleur owes.
Carries a Terms link, confidentiality owed by Jikigai, end-of-alpha disposition, and a
redact-before-sending instruction. Asks for a one-line reply as assent evidence. Never contains the
word "Plugin"; physically fenced from the DRAFT marking.

**FR4 — Runbook.** Step 2 retitled and carrying the Tier 1 terms inline; the "Known gap" section
replaced by the operating rule; a `Terms` column on the recruitment tally; an offboarding line. No
renumbering.

**FR5 — Records.** A `#7331` row in `compliance-posture.md`; a rewritten fifth requester class in the
statutory catalog (not an Art. 28(3)(e) duty); the fired Anthropic re-evaluation trigger actioned;
roadmap row 4.12.

## Technical Requirements

**TR1 — No row in `tenant-dpa-register.md`.** A `dpa-signed` row starts the §6.1 30-day clock and
invalidates a documented baseline. Four provisioning scripts also parse that table positionally.

**TR2 — No file added under `docs/legal/`.** Guards the #4330 chain and three CI gates.

**TR3 — No follow-through probe.** The runbook already ruled on this shape, the
`follow-through-directive-gate.sh` hook denies it, `exit 2` is **not** silent (the sweeper comments on
TRANSIENT), and the PASS condition would be vacuous at merge. A dated issue with the due date in the
**title** is the mechanism.

**TR4 — No C4 edit.** The only candidate edge duplicates `betaContact -> founder` on the same ordered
pair, and `betaContact` is defined as an *involuntary Art. 14* subject — the wrong actor for a
voluntary Art. 13 submission. The two named c4 tests do not read the committed artifact anyway.

**TR5 — Anchor on content, never line numbers.** The T&Cs have sections 1–17; "§298" and "§112" are
line numbers and would cite clauses that do not exist.

**TR6 — INDEX.md drift.** Staging any `knowledge-base/**/*.md` regenerates `INDEX.md`, which is stale
by thousands of lines. Edit its `## legal` section surgically and `git checkout` the rest.

## Acceptance Criteria

See the plan's `## Acceptance Criteria` (AC1–AC13). AC2 (no personal data in any committed artifact)
is the only irreversible one.

## Open Decisions

Two User-Challenges are recorded in `decision-challenges.md` and are **not** decided here: whether to
revoke collaborator access rather than paper it (UC-1), and whether paid legal time should go to
#7119 first (UC-2).
