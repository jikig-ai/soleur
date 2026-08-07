---
title: "Alpha-tester terms + controller/processor posture for tester-owned repository data"
feature: feat-one-shot-7331-alpha-tester-terms-dpa
issue: "#7331"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: spec
date: 2026-08-06
revised: 2026-08-06
revision_reason: "Preconditions 0.1 and 0.6 answered; Posture B fired retroactively and Posture C is live. Verdict inverted — see the plan's '## Revision' section."
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
repository, and asks for alpha-tester terms.

**Revised 2026-08-06 — two blocking preconditions were answered and they invert the verdict.**
(1) The 2026-08-06 guided-onboarding session ran on the **operator's machine under Jikigai's
Anthropic API key** — a verbatim instance of Posture B trigger 2, which therefore **fired
retroactively**, without the Art. 28(3) instrument that must precede it. (2) UC-1 resolved to
**Option 2**: the operator **retains** collaborator access and papers it, so Posture C is live.
**Both postures now apply**, and the validation record shows they **co-occurred in one run** — the
operator ran that session *"with a second purpose of dogfooding the onboarding experience itself."*

Three things the issue does not contain, as they now stand:

1. **The published position is narrower than the alpha configuration — not falsified, and not an
   answer to it.** `docs/legal/data-protection-disclosure.md` §2.1 (both mirrors): *"Therefore,
   Soleur is neither a Controller nor a Processor with respect to the data processed locally through
   the Plugin."* That **remains true within its stated scope** — Plugin-local processing, on the
   User's own machine, under the User's own credentials — and the `plugins/soleur/` egress scan
   confirms limbs (b)/(c) empirically. It does **not** reach operator-run, Jikigai-key-funded
   processing. **Limb (d)** (*"Users authenticate directly … using their own API keys"*) is phrased
   unconditionally and is inaccurate as a general description once an operator-assisted mode exists —
   a recorded **finding**, filed rather than edited here. Overclaiming in **either** direction is the
   failure mode; see the plan's Overview for the formulation of record.
2. **A live controller problem alongside it.** The operator holds collaborator access to the tester's
   private repository and reads it for Jikigai's own #1442 metrics — Art. 4(7) controller activity
   with no lawful basis recorded. A DPA cannot cure it (Art. 28(10)). Now papered by election.
3. **A materialised processor gap.** Tester content egressed to Anthropic under a **Jikigai** key,
   making Anthropic **Jikigai's** sub-processor for that egress, under a 30-day retention window
   (`zero_retention_amendment: unsigned`) expiring ~2026-09-05.

## Goals

- Record the determination durably and citably, whichever way it falls.
- **Close the live controller exposure** (Posture C — papered, per UC-1 Option 2).
- **Remediate the 2026-08-06 Posture B session** and stop it recurring.
- Give every alpha tester something that binds in the Jikigai→tester direction.
- Give testers 2–10 the same treatment automatically, via the runbook.

## Non-Goals

- **Building the `if processor` branch as the issue framed it** — a DPA covering personal data at
  rest in the tester's repository. That relationship still does not exist: plugin-local processing on
  the tester's machine under the tester's key is not Jikigai processing. **The restored instrument
  covers operator-assisted runs only.** *(Superseded in part: the branch is no longer wholly out of
  scope — see below.)*
- **The `tenant-dpa-register.md` row and the signature probe stay cut.** #4330 item iv forbids the
  row and names the successor (`customer-dpa-register.md`, on counter-signature). The probe is denied
  by `follow-through-directive-gate.sh`, its PASS condition is vacuous at merge, and `exit 2` is not
  silent. Neither is affected by the inversion.
- **Publishing anything to `docs/legal/`.** Fires the #4330 six-step chain including a SOC 2
  engagement commitment. **Restoring the Tier 2 instrument does not fire it** — that chain is keyed
  to publishing the *customer-facing Web Platform DPA template* on one of three named triggers, none
  of which has fired. The instrument here is bilateral, alpha-scoped and unpublished.
- **Amending `docs/legal/` to fix the limb (d) narrowness.** Recorded as a finding and filed; not
  edited in this PR.
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

**FR1b — Determination content specific to the inversion.** It carries the scope formulation (what
§2.1 covers, what it does not, the limb (d) finding); the **dual-purpose** analysis — processor for
the instructed limb, controller for the dogfooding limb, Art. 28(10) scoped to the excess — with
**both residual uncertainties stated unresolved**; and the **corrected Art. 28(4)** position:
Anthropic's DPA auto-incorporates and binds, so Art. 28(4) is **inchoate, not breached** (there is no
tester contract to mirror); the live defects are **Art. 28(2)** (no sub-processor authorisation or
notice), the absent instrument, and the 30-day retention. Trigger 2 is marked **FIRED**.

**FR2 — Posture C closed (Option 2 chosen — unconditional).** An LIA whose necessity limb **names the
declined less-intrusive alternative**; **PA-34** (dogfooding limb of the session) and **PA-35**
(ongoing #1442 observation) in the Art. 30(1) register with Jikigai as controller; an Art. 14 notice
claiming Art. 14(5)(b) in writing; and a **rewrite of `article-30-register.md` §0's in-scope
predicate** to key on *purposes or credentials, regardless of host* — not another surface appended to
the list, which is what left the #7100 defect in place.

**FR2b — Posture B recorded and remediated.** An Art. 30(2) processor record at a **new**
`knowledge-base/legal/article-30-2-register.md` (separate file, cross-linked from §0); the five
remediation steps in the plan's `## Retroactive remediation`; and the **behavioural control** — no
Jikigai-keyed runs against tester content until the instrument is countersigned.

**FR2c — Tier 2 Art. 28(3) instrument, restored and re-scoped.** Covers **operator-assisted runs
only**. Names Anthropic as an authorised sub-processor, is **effective forward**, and carries a
recital acknowledging the 2026-08-06 session — ratification evidencing good faith, **not** a
retroactive cure. Drafted from the template's §7.2 and §10 only; **never** Schedule 4's TOMs. Ships
as a marked draft; **counsel review gates sending it, not writing it**.

**FR3 — Tier 1 alpha notice, unconditional.** Sent to every tester **including tester #1**. ≤90 words,
first-person, merged into the existing welcome-message paragraph. Carries a Terms link,
confidentiality owed by Jikigai, end-of-alpha disposition, the collaborator-access purpose stated
plainly, and a redact-before-sending instruction. Asks for a one-line reply as assent evidence. Never
contains the word "Plugin"; physically fenced from the DRAFT marking.
**The prescribed lead is WITHDRAWN**: *"it runs on your machine, on your key — I can't see your
repo"* is false in **both** halves for tester #1 and must not ship. Lead instead with what is true and
reassuring — the tool runs locally and Jikigai operates no server that reaches their code; where
Jikigai does have access it is access the tester granted, for a stated purpose, revocable at a word.

**FR3b — Retroactive-remediation message, separate from Tier 1.** ~5 sentences, plain language, no
apology theatre. States that tester content transited Jikigai's Anthropic account under a 30-day
retention window, and that the session also served Jikigai's own improvement purpose. It rides
alongside Tier 1, never inside it — a ≤90-word warm welcome would either blow its budget or bury the
disclosure.

**FR4 — Runbook.** Step 2 retitled and carrying the Tier 1 terms inline; the "Known gap" section
replaced by the operating rule with **trigger 2 marked FIRED**; the **behavioural control** as a hard
gate; the collaborator-access rule stated **with its tester #1 exception**, since a rule the runbook
violates in its only worked example teaches the exception; a `Terms` column on the recruitment tally;
an offboarding line. No renumbering.

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
*(Re-checked against the inversion: the Posture B egress runs over the already-modelled `github` and
Anthropic edges from the operator's own workstation, which the model treats as the founder actor. No
new element or arrow is created by a Jikigai-keyed session — only a new record of it.)*

**TR5 — Anchor on content, never line numbers.** The T&Cs have sections 1–17; "§298" and "§112" are
line numbers and would cite clauses that do not exist.

**TR6 — INDEX.md drift.** Staging any `knowledge-base/**/*.md` regenerates `INDEX.md`, which is stale
by thousands of lines. Edit its `## legal` section surgically and `git checkout` the rest.

**TR7 — A new register file is unguarded, not failing.**
`apps/web-platform/test/legal-doc-consistency.test.ts` loads an **explicit site list** naming
`knowledge-base/legal/article-30-register.md` by path, so `article-30-2-register.md` will not break
CI — and will not be checked either. If it carries an `RCS <City>` token, enrol it in that list, or
it becomes an unguarded fourth site: the drift class #4086 closed.
## Acceptance Criteria

See the plan's `## Acceptance Criteria` (**AC1–AC16**, extended by the revision: AC1b, AC5b, AC5c,
AC14, AC15, AC16). AC2 (no personal data in any committed artifact) is the only irreversible one.
**AC15 is the most easily missed** — it asserts the withdrawn Tier 1 lead does not ship, in the
**negation form** rather than as substring absence, excluding planning artifacts from its own scope.

## Resolved Decisions

Both User-Challenges in `decision-challenges.md` were answered by the operator on **2026-08-06**:

- **UC-1 → Option 2 (retain and paper).** Phase 2 executes. The standing de-escalation — revoke, or
  re-derive #1442 to non-personal aggregates (commit/file counts) — is recorded and deferred
  (plan Phase 6.3), not actioned.
- **UC-2 → re-derived, and it survives.** Its original premise died (the instrument is no longer
  conditional), but **#7119 still outranks** on scale, publicity and continuance: ~80 digests already
  public with named handles, never deleted, still running. The alpha exposure is one identified
  counterparty who requested the processing, closed forward by the behavioural control.
  **Recommendation: no counsel spend on the alpha instrument now.**
